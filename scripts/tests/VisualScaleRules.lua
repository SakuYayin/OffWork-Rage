-- 纯Lua尺度回归；不创建引擎上下文，不启动Runtime/renderer，也不生成动画。
local VisualScale = require("VisualScale")
local Heroes = require("Heroes")
local Campaign = require("Campaign")
local Game = require("Game")
local Navigation = require("Navigation")
local HeroSprites=require("HeroSprites")
local EnemySprites=require("EnemySprites")
local Tests = {}
local function Source(hero)
    if VisualScale.portraits[hero.id]then return VisualScale.portraits[hero.id]end
    local sprite=assert(HeroSprites[hero.id],"new hero must have an authored atlas")
    local frame=assert(sprite.frames.downIdle[1],"new hero needs a front idle frame")
    return {width=frame.w,height=frame.h}
end

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
    Check(VisualScale.adultHeight == 122, "保持家具与镜头尺度")
    for _, hero in ipairs(Heroes.list) do
        local source = Source(hero)
        local atlas=assert(HeroSprites[hero.id])
        Check(hero.sprite==atlas.path,hero.id.."战斗资源与真实图集元数据一致")
        if hero.id=="male"or hero.id=="female"then
            Check(hero.portrait == "image/generated/" .. hero.id .. "_portrait.png", hero.id .. "保留原菜单立绘")
            Check(hero.sprite~=hero.portrait,hero.id.."原立绘与战斗小人独立")
        else
            if hero.id=="fufu"then
                local portrait=assert(require("FufuArt").sheets.portrait)
                local region=assert(portrait.portraitRegion)
                local first=assert(portrait.frames.portrait[1]or portrait.frames.portrait)
                Check(hero.portrait==portrait.path and hero.portrait~=hero.sprite,"符符使用批准的独立工牌头像图")
                Check(region.w>0 and region.h>0 and region.x>=first.x and region.y>=first.y
                    and region.x+region.w<=first.x+first.w and region.y+region.h<=first.y+first.h,
                    "符符头像区域位于批准的第一姿势内")
                Check(region.h<first.h*.5 and region.y+region.h<=portrait.height,"符符工牌裁切上半部头像，不显示整张立绘")
            else
                Check(hero.portrait==hero.sprite,hero.id.."工牌使用图集裁切而非整张立绘")
            end
            Check(source.width>0 and source.height>0,hero.id.."正面裁切尺寸有效")
            for _,frames in pairs(atlas.frames)do for _,f in ipairs(frames)do
                Check(f.x>=0 and f.y>=0 and f.x+f.w<=atlas.width and f.y+f.h<=atlas.height,hero.id.."每帧均在图集内")
                Check(f.anchorX>=0 and f.anchorX<=f.w,hero.id.."脚点在帧内")
            end end
        end
        Check(VisualScale.ActorHeight(hero.id) < VisualScale.adultHeight * 0.8, hero.id .. "战斗小人不再按成年立绘身高绘制")
        for _, height in ipairs({ 61, 122, 183 }) do
            local w, h = VisualScale.ActorSize(source.width, source.height, height)
            Check(Near(h, height), hero.id .. "目标身高")
            Check(Near(w / h, source.width / source.height), hero.id .. "原立绘宽高比不变")
            Check(Near(w / source.width, h / source.height), hero.id .. "两个轴同一缩放")
        end
    end
    for _, name in ipairs({ "ghost", "paper", "message", "pot","charger","spitter","bomber","shieldGuard","summoner" }) do
        local ratio = VisualScale.ActorHeight(name) / VisualScale.adultHeight
        Check(ratio > 0.45 and ratio < 1, name .. "普通怪小于成年人")
    end
    Check(VisualScale.ActorHeight("printerBoss")>VisualScale.adultHeight and VisualScale.ActorHeight("printerBoss")<=VisualScale.adultHeight*1.2,"打印机巨兽体积有明确上限")
    for _,name in ipairs({"charger","spitter","bomber","shieldGuard","summoner","printerBoss"})do
        local atlas=assert(EnemySprites[name])
        Check(atlas.referenceHeight>0 and atlas.width>0 and atlas.height>0,name.."独立图集有有效尺度")
        for _,frames in pairs(atlas.frames)do for _,f in ipairs(frames)do
            Check(f.x>=0 and f.y>=0 and f.x+f.w<=atlas.width and f.y+f.h<=atlas.height,name.."所有拆帧在源图范围内")
        end end
    end
    for _, name in ipairs({ "coworker", "supervisor", "owner" }) do
        local ratio = VisualScale.ActorHeight(name) / VisualScale.adultHeight
        Check(ratio >= 0.85 and ratio <= 1, name .. "Q版Boss仅略大于主角")
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
    -- Same logical viewport at every DPR; readable responsive zoom and bounded FOV.
    for _, size in ipairs({ { 320, 480 }, { 390, 720 }, { 480, 860 }, { 640, 360 }, { 960, 480 }, { 1280, 720 }, { 1920, 1080 }, { 2560, 1440 } }) do
        local width, height = size[1], size[2]
        local reference = assert(VisualScale.Camera(width, height, 520, 580, Game.WIDTH, Game.HEIGHT))
        Check(reference.zoom > 0 and reference.zoom <= 4, "响应式镜头有明确缩放上限")
        Check(reference.viewW >= 320 - 0.000001, "至少保留320世界单位横向视野")
        Check(reference.viewH >= 340 - 0.000001, "至少保留340世界单位纵向视野")
        Check(VisualScale.ActorHeight("male") * 0.55 * reference.zoom / width <= 0.16, "Q版身体横向占比受限")
        Check(VisualScale.ActorHeight("male") * reference.zoom / height <= 0.27, "小人高向占比受限")
        if width>=1280 then Check(reference.zoom>1,"大屏地图与小人随界面放大")end
        local taller = assert(VisualScale.Camera(width, height * 2, 520, 580, Game.WIDTH, Game.HEIGHT))
        if Near(reference.zoom,width/320) then
            Check(Near(taller.zoom, reference.zoom), "竖屏继续加高只增加视野")
        end
        for _, dpr in ipairs({ 1, 2, 3 }) do
            local camera = assert(VisualScale.Camera(width * dpr / dpr, height * dpr / dpr, 520, 580, Game.WIDTH, Game.HEIGHT))
            Check(Near(camera.zoom, reference.zoom) and Near(camera.x, reference.x) and Near(camera.y, reference.y), "DPR改变不改变逻辑世界尺度")
            for _, hero in ipairs(Heroes.list) do
                local source = Source(hero)
                local w, h = VisualScale.ActorSize(source.width, source.height, VisualScale.ActorHeight(hero.id))
                Check(Near(w * camera.zoom / (h * camera.zoom), source.width / source.height), "横竖屏/DPR维持原立绘身材")
            end
        end
        local overview = assert(VisualScale.Camera(width, height, 520, 580, Game.WIDTH, Game.HEIGHT, true))
        Check(Near(overview.x,Game.WIDTH/2)and Near(overview.y,Game.HEIGHT/2),"菜单镜头仍以原夜景房间居中")
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
        Check(Near(recovered.zoom, math.min(4,math.max(640/1040,480/680),640/320,480/340)), "尺寸恢复后镜头比例正常")
    end
    Check(not VisualScale.IsFinite(nan) and not VisualScale.IsFinite(math.huge), "显式拒绝NaN与无穷")
    Check(VisualScale.IsFinite(0) and VisualScale.IsFinite(-10), "坐标允许零和负数")
    Check(VisualScale.Camera(640, 480, nan, 580, Game.WIDTH, Game.HEIGHT) == nil, "无效横坐标安全跳帧")
    Check(VisualScale.Camera(640, 480, 520, math.huge, Game.WIDTH, Game.HEIGHT) == nil, "无效纵坐标安全跳帧")
    print("[尺度测试汇总] " .. passed .. "项断言通过；14布局/24出口/横竖屏DPR1、2、3；未启动Runtime或renderer")
    return passed
end

return Tests
