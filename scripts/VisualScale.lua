-- 仅定义视觉尺度；沿用 Game/Campaign 的 1040×680 平面坐标，不参与碰撞/导航。
-- 原立绘是唯一身体比例标准：不把独立生成的 battle 图当成同一身材。
---@class OfficeVisualSize
---@field width number
---@field height number
---@class OfficeFurnitureScale
---@field heightRatio number 图片总高度/成年人身高（不是碰撞厚度）
---@field bayWidthRatio number 每个家具单元的参考宽度/成年人身高
---@field depthRatio number 允许重复一排家具的地面纵深/成年人身高
---@class OfficeFurnitureGrid
---@field columns integer
---@field rows integer
---@field width number 单元地面宽度
---@field depth number 单元地面纵深
---@field height number 单元图片总高度
---@class OfficeVisualExit
---@field x number
---@field y number
---@field w number
---@field h number
---@class OfficeVisualCamera
---@field zoom number X/Y 共用，不是两个独立缩放值
---@field viewW number
---@field viewH number
---@field x number 镜头中心
---@field y number

local VisualScale = {}

-- 保持既有主角122世界单位身高，修正源图而非扩大物理世界。
VisualScale.adultHeight = 122
---@type table<string, OfficeVisualSize>
VisualScale.portraits = { male = { width = 244, height = 672 }, female = { width = 371, height = 672 } }
---@type table<string, number>
VisualScale.actorRatios = {
    male = 1, female = 1, ghost = 0.82, paper = 0.72, message = 0.54, pot = 0.88,
    coworker = 1.04, supervisor = 1.08, owner = 1.12,
}
---@type table<string, OfficeFurnitureScale>
VisualScale.furniture = {
    desk = { heightRatio = 0.50, bayWidthRatio = 0.80, depthRatio = 0.54 },
    cabinet = { heightRatio = 0.88, bayWidthRatio = 0.52, depthRatio = 0.54 },
    server = { heightRatio = 0.95, bayWidthRatio = 0.52, depthRatio = 0.54 },
    planter = { heightRatio = 0.42, bayWidthRatio = 0.45, depthRatio = 0.54 },
    partition = { heightRatio = 0.58, bayWidthRatio = 0.46, depthRatio = 0.54 },
}
-- 原有160高门框约1.31个成年人；上限不允许门图凭屏幕高度变成巨门。
VisualScale.door = { maxHeightRatio = 1.32 }
VisualScale.camera = { minWidthInAdults = 5.25, minHeightInAdults = 3.5, maxZoom = 1, lookAboveRatio = 0.55 }

---@param name string
---@return number
function VisualScale.ActorHeight(name)
    return VisualScale.adultHeight * assert(VisualScale.actorRatios[name], "未配置角色视觉身高：" .. name)
end

-- 完整源图只乘一个系数，保留发型、四肢、姿态、武器和脚点的原始像素比例。
---@param width number
---@param height number
---@param targetHeight number
---@return number, number
function VisualScale.ActorSize(width, height, targetHeight)
    assert(width > 0 and height > 0 and targetHeight > 0, "角色源图/目标尺寸必须为正")
    local scale = targetHeight / height
    return width * scale, height * scale
end

-- 家具基底仍精确覆盖原碰撞AABB；重复单元只改变贴图分布，不增删障碍。
-- 图片总高度单独按成年人标定，长机柜的地面纵深不能变成单个巨型高柜。
---@param kind string
---@param width number
---@param depth number
---@return OfficeFurnitureGrid
function VisualScale.FurnitureGrid(kind, width, depth)
    assert(width > 0 and depth > 0, "家具基底尺寸必须为正")
    local spec = VisualScale.furniture[kind] or VisualScale.furniture.desk
    local columns = kind == "planter" and 1 or math.max(1, math.floor(width / (VisualScale.adultHeight * spec.bayWidthRatio) + 0.5))
    local rows = kind == "planter" and 1 or math.max(1, math.ceil(depth / (VisualScale.adultHeight * spec.depthRatio)))
    return { columns = columns, rows = rows, width = width / columns, depth = depth / rows,
        height = VisualScale.adultHeight * spec.heightRatio }
end

-- 门槛与门宽来自同一个真实出口数据；只限制立面高度，门底边不漂移。
---@param exit CampaignExit
---@return OfficeVisualExit
function VisualScale.ExitBounds(exit)
    local height = math.min(exit.h, VisualScale.adultHeight * VisualScale.door.maxHeightRatio)
    return { x = exit.x, y = exit.triggerY - height, w = exit.w, h = height }
end

-- Yoga未完成布局、窗口暂不可用时可能产生NaN；<=0无法识别NaN。
---@param value any
---@return boolean
function VisualScale.IsFinite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

---@param value any
---@return boolean
function VisualScale.IsPositiveSize(value)
    return VisualScale.IsFinite(value) and value > 0
end

---@param target number
---@param view number
---@param extent number
---@return number
local function Center(target, view, extent)
    if view >= extent then return extent / 2 end
    return math.max(view / 2, math.min(extent - view / 2, target))
end

-- 模式B的逻辑像素镜头：长屏只增加可见范围，绝不用max/COVER把世界撑满。
-- 极窄/极矮面板等比缩小，至少保留5.25人宽、3.5人高的战术视野。
-- 地图小于视野时居中留边，不以拉伸或放大消除留边。
---@param width number 逻辑像素
---@param height number 逻辑像素
---@param targetX number 玩家脚点
---@param targetY number 玩家脚点
---@param worldWidth number Game.WIDTH
---@param worldHeight number Game.HEIGHT
---@param overview boolean? 菜单/选人显示完整背景
---@return OfficeVisualCamera? 未就绪或非有限尺寸时跳过本帧
function VisualScale.Camera(width, height, targetX, targetY, worldWidth, worldHeight, overview)
    if not VisualScale.IsPositiveSize(width) or not VisualScale.IsPositiveSize(height)
        or not VisualScale.IsPositiveSize(worldWidth) or not VisualScale.IsPositiveSize(worldHeight)
        or not VisualScale.IsFinite(targetX) or not VisualScale.IsFinite(targetY) then return nil end
    local policy = VisualScale.camera
    local minWidth = overview and worldWidth or VisualScale.adultHeight * policy.minWidthInAdults
    local minHeight = overview and worldHeight or VisualScale.adultHeight * policy.minHeightInAdults
    local zoom = math.min(policy.maxZoom, width / minWidth, height / minHeight)
    if not VisualScale.IsPositiveSize(zoom) then return nil end
    local viewW, viewH = width / zoom, height / zoom
    if not VisualScale.IsPositiveSize(viewW) or not VisualScale.IsPositiveSize(viewH) then return nil end
    local x = overview and worldWidth / 2 or Center(targetX, viewW, worldWidth)
    local y = overview and worldHeight / 2 or Center(targetY - VisualScale.adultHeight * policy.lookAboveRatio, viewH, worldHeight)
    return { zoom = zoom, viewW = viewW, viewH = viewH, x = x, y = y }
end

return VisualScale
