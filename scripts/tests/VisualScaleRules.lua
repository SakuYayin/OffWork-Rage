-- 纯Lua尺度回归；不创建引擎上下文，不启动Runtime/renderer，也不生成动画。
local VisualScale = require("VisualScale")
local Heroes = require("Heroes")
local Campaign = require("Campaign")
local Game = require("Game")
local Navigation = require("Navigation")
local Tests = {}

---@param a number
---@param b number
---@return boolean
local function Near(a, b) return math.abs(a - b) < 0.000001 end

---@param externalCheck fun(value: any, message: string)?
---@return integer
function Tests.Run(externalCheck)
    local passed = 0
    local function Check(value, message)
        if externalCheck then externalCheck(value, message)
        else assert(value, "[尺度测试失败] " .. message) end
        passed = passed + 1
    end
    Check(Game.WIDTH == 1040 and Game.HEIGHT == 680, "物理地图未扩大")
    Check(#Campaign.layouts == 14, "保留14个成熟布局")
    Check(VisualScale.adultHeight == 122, "保持原主角世界身高")
    for _, hero in ipairs(Heroes.list) do
        local source = assert(VisualScale.portraits[hero.id])
        Check(hero.portrait == "image/generated/" .. hero.id .. "_portrait.png", hero.id .. "原立绘未换源")
        Check(hero.sprite == "image/generated/" .. hero.id .. "_battle.png", hero.id .. "保留后续动画候选配置")
        for _, height in ipairs({ 61, 122, 183 }) do
            local w, h = VisualScale.ActorSize(source.width, source.height, height)
            Check(Near(h, height), hero.id .. "目标身高")
            Check(Near(w / h, source.width / source.height), hero.id .. "原立绘宽高比不变")
            Check(Near(w / source.width, h / source.height), hero.id .. "两个轴同一缩放")
        end
    end
    for _, name in ipairs({ "ghost", "paper", "message", "pot" }) do
        local ratio = VisualScale.ActorHeight(name) / VisualScale.adultHeight
        Check(ratio > 0.45 and ratio < 1, name .. "普通怪小于成年人")
    end
    for _, name in ipairs({ "coworker", "supervisor", "owner" }) do
        local ratio = VisualScale.ActorHeight(name) / VisualScale.adultHeight
        Check(ratio >= 1 and ratio <= 1.15, name .. "Boss不是夸张巨人")
    end
    Check(Near(VisualScale.furniture.desk.heightRatio, 0.5), "桌约半人高")
    Check(VisualScale.furniture.cabinet.heightRatio < 1 and VisualScale.furniture.cabinet.heightRatio > 0.8, "柜略低于成年人")
    for layoutIndex, obstacles in ipairs(Campaign.layouts) do
        for _, obstacle in ipairs(obstacles) do
            local x, y, width, depth, kind = obstacle.x, obstacle.y, obstacle.w, obstacle.h, obstacle.kind
            local grid = VisualScale.FurnitureGrid(kind, width, depth)
            Check(grid.rows >= 1 and grid.columns >= 1, "布局" .. layoutIndex .. "家具单元数有效")
            Check(Near(grid.width * grid.columns, width) and Near(grid.depth * grid.rows, depth), "家具基底覆盖同一碰撞AABB")
            local spec = assert(VisualScale.furniture[kind])
            Check(Near(grid.height, VisualScale.adultHeight * spec.heightRatio), "家具高度独立于地面纵深")
            Check(obstacle.x == x and obstacle.y == y and obstacle.w == width and obstacle.h == depth and obstacle.kind == kind, "未写入共享碰撞布局")
        end
    end
    local exits = 0
    local seen = {}
    for floor = 1, 3 do
        for _, room in ipairs(Campaign.Build(floor)) do
            local exit = room.exit
            local oldY, oldHeight, oldRadius, oldClearance = exit.y, exit.h, exit.radius, exit.clearance
            local bounds = VisualScale.ExitBounds(exit)
            Check(Near(bounds.y + bounds.h, exit.triggerY), "门视觉底边=真实触发门槛")
            Check(bounds.x == exit.x and bounds.w == exit.w, "门宽仍由真实出口定义")
            Check(Near(bounds.h, exit.h) and Near(bounds.y, exit.y), "现有门框坐标与高度不改")
            Check(bounds.h > VisualScale.adultHeight and bounds.h <= VisualScale.adultHeight * 1.32, "门符合成年人尺度")
            Check(exit.y == oldY and exit.h == oldHeight and exit.radius == oldRadius and exit.clearance == oldClearance, "未修改触发器或门洞净空")
            local nav = Navigation.New(Campaign.Desks(room))
            local path = Navigation.FindPath(nav, room.spawn.x, room.spawn.y, exit.triggerX, exit.triggerY, 12)
            Check(path ~= nil and #path > 0, "14图原导航仍可从出生到真实门槛")
            exits = exits + 1
            seen[room.layout] = true
        end
    end
    local layouts = 0
    for _ in pairs(seen) do layouts = layouts + 1 end
    Check(exits == 24 and layouts == 14, "覆盖3层24房间全部14布局")
    -- 同逻辑宽高的DPR1/2/3必须相同；高屏不产生COVER放大。
    for _, size in ipairs({ { 320, 480 }, { 390, 720 }, { 480, 860 }, { 640, 360 }, { 960, 480 }, { 1280, 720 }, { 1920, 1080 }, { 2560, 1440 } }) do
        local width, height = size[1], size[2]
        local reference = assert(VisualScale.Camera(width, height, 520, 580, Game.WIDTH, Game.HEIGHT))
        Check(reference.zoom > 0 and reference.zoom <= 1, "镜头不以面板高度放大世界")
        Check(reference.viewW >= VisualScale.adultHeight * 5.25 - 0.000001, "至少5.25人宽视野")
        Check(reference.viewH >= VisualScale.adultHeight * 3.5 - 0.000001, "至少3.5人高视野")
        Check(VisualScale.adultHeight * reference.zoom / width <= 1 / 5.25 + 0.000001, "手机角色不占半屏宽")
        Check(VisualScale.adultHeight * reference.zoom / height <= 1 / 3.5 + 0.000001, "角色不占半屏高")
        local taller = assert(VisualScale.Camera(width, height * 2, 520, 580, Game.WIDTH, Game.HEIGHT))
        if Near(reference.zoom, math.min(1, width / (122 * 5.25))) then
            Check(Near(taller.zoom, reference.zoom), "竖屏继续加高只增加视野")
        end
        for _, dpr in ipairs({ 1, 2, 3 }) do
            local camera = assert(VisualScale.Camera(width * dpr / dpr, height * dpr / dpr, 520, 580, Game.WIDTH, Game.HEIGHT))
            Check(Near(camera.zoom, reference.zoom) and Near(camera.x, reference.x) and Near(camera.y, reference.y), "DPR改变不改变逻辑世界尺度")
            for _, hero in ipairs(Heroes.list) do
                local source = assert(VisualScale.portraits[hero.id])
                local w, h = VisualScale.ActorSize(source.width, source.height, VisualScale.ActorHeight(hero.id))
                Check(Near(w * camera.zoom / (h * camera.zoom), source.width / source.height), "横竖屏/DPR维持原立绘身材")
            end
        end
        local overview = assert(VisualScale.Camera(width, height, 520, 580, Game.WIDTH, Game.HEIGHT, true))
        Check(overview.viewW >= Game.WIDTH - 0.000001 and overview.viewH >= Game.HEIGHT - 0.000001, "菜单背景完整等比可见")
        for _, point in ipairs({ { 60, 154 }, { 980, 154 }, { 60, 616 }, { 980, 616 } }) do
            local camera = assert(VisualScale.Camera(width, height, point[1], point[2], Game.WIDTH, Game.HEIGHT))
            Check(point[1] >= camera.x - camera.viewW / 2 and point[1] <= camera.x + camera.viewW / 2, "边界玩家横向在视野内")
            Check(point[2] >= camera.y - camera.viewH / 2 and point[2] <= camera.y + camera.viewH / 2, "边界玩家脚点纵向在视野内")
            Check(point[2] - 122 >= camera.y - camera.viewH / 2 - 0.000001, "边界玩家原立绘头部不裁切")
        end
    end
    -- NaN与无穷值不能靠<=0筛掉；临时无效尺寸返回nil，不抛异常或污染后续帧。
    local nan = 0 / 0
    for _, invalid in ipairs({ 0, -1, nan, math.huge, -math.huge }) do
        Check(not VisualScale.IsPositiveSize(invalid), "拒绝非正数或非有限尺寸")
        Check(VisualScale.Camera(invalid, 480, 520, 580, Game.WIDTH, Game.HEIGHT) == nil, "无效面板宽安全跳帧")
        Check(VisualScale.Camera(640, invalid, 520, 580, Game.WIDTH, Game.HEIGHT) == nil, "无效面板高安全跳帧")
        Check(VisualScale.Camera(640, 480, 520, 580, invalid, Game.HEIGHT) == nil, "无效地图宽安全跳帧")
        Check(VisualScale.Camera(640, 480, 520, 580, Game.WIDTH, invalid) == nil, "无效地图高安全跳帧")
        local recovered = assert(VisualScale.Camera(640, 480, 520, 580, Game.WIDTH, Game.HEIGHT))
        Check(Near(recovered.zoom, math.min(1, 640 / (122 * 5.25), 480 / (122 * 3.5))), "尺寸恢复后保持原镜头比例")
    end
    Check(not VisualScale.IsFinite(nan) and not VisualScale.IsFinite(math.huge), "显式拒绝NaN与无穷")
    Check(VisualScale.IsFinite(0) and VisualScale.IsFinite(-10), "坐标允许零和负数")
    Check(VisualScale.Camera(640, 480, nan, 580, Game.WIDTH, Game.HEIGHT) == nil, "无效横坐标安全跳帧")
    Check(VisualScale.Camera(640, 480, 520, math.huge, Game.WIDTH, Game.HEIGHT) == nil, "无效纵坐标安全跳帧")
    print("[尺度测试汇总] " .. passed .. "项断言通过；14布局/24出口/横竖屏DPR1、2、3；未启动Runtime或renderer")
    return passed
end

return Tests
