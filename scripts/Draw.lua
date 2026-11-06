-- 生图像素办公室：生成角色/场景/家具，程序化特效和真实碰撞分区。
-- 这里只消费玩法数据，不写入房间状态；HUD/商店交互统一交给 main.lua 的 UI。
local Draw = {}
local Game = require("Game")
local Art = require("Art")
local VisualScale = require("VisualScale")

local C = {
    ink = { 17, 24, 34 }, floor = { 57, 68, 73 }, tile = { 63, 75, 79 },
    line = { 45, 56, 63 }, wall = { 41, 45, 65 }, wallTop = { 77, 78, 99 },
    teal = { 66, 229, 186 }, tealDark = { 29, 94, 89 }, gold = { 255, 210, 109 },
    pink = { 255, 105, 127 }, purple = { 173, 146, 245 }, white = { 234, 240, 225 },
    paper = { 237, 219, 179 }, blue = { 109, 180, 220 }, muted = { 136, 154, 160 },
    wood = { 162, 133, 106 }, woodLight = { 197, 166, 128 }, woodDark = { 95, 79, 74 },
    accent = { 66, 229, 186 }, accentDark = { 29, 94, 89 }, carpet = { 35, 65, 66 },
    metal = { 105, 129, 143 }, cream = { 245, 232, 192 }, red = { 169, 52, 70 },
}
Draw.colors = C

local FLOOR_COLORS = {
    { floor = { 54, 78, 78 }, tile = { 60, 86, 85 }, line = { 40, 62, 65 },
        wall = { 34, 51, 62 }, wallTop = { 83, 120, 126 }, accent = { 78, 233, 185 },
        accentDark = { 29, 99, 88 }, carpet = { 31, 66, 65 } },
    { floor = { 57, 63, 91 }, tile = { 64, 70, 101 }, line = { 40, 44, 69 },
        wall = { 36, 35, 65 }, wallTop = { 104, 98, 149 }, accent = { 176, 149, 255 },
        accentDark = { 76, 64, 124 }, carpet = { 48, 42, 81 } },
    { floor = { 80, 56, 64 }, tile = { 90, 63, 69 }, line = { 58, 37, 48 },
        wall = { 52, 33, 45 }, wallTop = { 133, 86, 91 }, accent = { 255, 206, 100 },
        accentDark = { 137, 76, 54 }, carpet = { 103, 35, 55 } },
}

---@type NVGContextWrapper?
local vg = nil
local font = -1

local function Color(name, alpha)
    local c = C[name] or C.white
    return nvgRGBA(c[1], c[2], c[3], math.floor(alpha or 255))
end
local function Rect(x, y, w, h, color, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, math.floor(x), math.floor(y), math.ceil(w), math.ceil(h))
    nvgFillColor(vg, Color(color, alpha))
    nvgFill(vg)
end
local function Circle(x, y, r, color, alpha)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFillColor(vg, Color(color, alpha))
    nvgFill(vg)
end
local function Text(x, y, text, size, color, align, alpha)
    if font < 0 then return end
    nvgFontFaceId(vg, font)
    nvgFontSize(vg, size)
    nvgTextAlign(vg, (align or NVG_ALIGN_CENTER) + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, Color("ink", alpha))
    nvgText(vg, x + 1, y + 2, text)
    nvgFillColor(vg, Color(color, alpha))
    nvgText(vg, x, y, text)
end
local function Stroke(x, y, r, width, color, alpha)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgStrokeWidth(vg, width)
    nvgStrokeColor(vg, Color(color, alpha))
    nvgStroke(vg)
end

local function Shadow(x, y, w)
    nvgBeginPath(vg)
    nvgEllipse(vg, x, y, w / 2, math.max(4, w * 0.13))
    nvgFillColor(vg, nvgRGBA(6, 12, 22, 105))
    nvgFill(vg)
end

-- 基底仍与Game.GetObstacles的AABB完全相同，不改导航；高度统一按成年人标定。
-- 长柜/服务器分成同高的前后排；地面纵深不再决定单柜身高。
local function Furniture(d)
    local x, y, w, h, kind = d.x, d.y, d.w, d.h, d.kind or "desk"
    local grid = VisualScale.FurnitureGrid(kind, w, h)
    Rect(x + 5, y + 6, w, h, "ink", 72)
    if kind == "partition" then
        local rise = grid.height
        Rect(x, y - rise, w, h + rise, "ink")
        Art.Image("partition", x + 2, y - rise + 2, math.max(1, w - 4), h + rise - 4, 1)
        Rect(x, y - rise, w, 3, "metal")
        Rect(x + 2, y - rise + 3, math.max(1, w - 4), 2, "white", 100)
        Rect(x, y + h - 4, w, 4, "wall")
        local spacing = VisualScale.adultHeight * VisualScale.furniture.partition.bayWidthRatio
        if w > h then
            for xx = x + spacing, x + w - 8, spacing do Rect(xx, y - rise, 3, h + rise, "metal", 155) end
        else
            for yy = y + spacing, y + h - 6, spacing do Rect(x + 1, yy, w - 2, 2, "metal", 150) end
        end
    else
        local image = kind == "server" and "server" or (kind == "cabinet" and "cabinet" or (kind == "planter" and "planter" or "desk"))
        for row = 1, grid.rows do
            local bottom = y + row * grid.depth
            for col = 1, grid.columns do
                Art.Image(image, x + (col - 1) * grid.width, bottom - grid.height, grid.width, grid.height, 1)
            end
        end
    end
end

local function Background(g)
    local floor = math.max(1, math.min(3, g.floor or 1))
    local room = g.room
    local colors = FLOOR_COLORS[floor] or FLOOR_COLORS[1]
    for key, value in pairs(colors) do C[key] = value end
    Art.Image(floor == 1 and "floor1" or (floor == 2 and "floor2" or "floor3"), 0, 0, Game.WIDTH, Game.HEIGHT, 1)
    -- 门与触发器共用Game.GetExit：视觉底边就是脚下可达门槛，不改门洞/碰撞。
    local exit = Game.GetExit(g)
    local door = VisualScale.ExitBounds(exit)
    local open = g.roomCleared == true
    Art.Contain(open and "exitOpen" or "exitClosed", door.x, door.y, door.w, door.h, 1)
    Rect(exit.triggerX - exit.w * 0.42, exit.triggerY - 3, exit.w * 0.84, 5, open and "teal" or "metal", 130)
    if open then
        for i = 1, 3 do
            local yy = exit.triggerY + 15 + i * 18 - (g.visualTime * 24) % 18
            Rect(exit.triggerX - 5, yy, 10, 3, "teal", 185 - i * 28)
            Rect(exit.triggerX - 10, yy + 3, 20, 3, "teal", 185 - i * 28)
        end
    end
    -- 房间名与出口方向已在顶部HUD显示，不再用世界标牌遮挡门洞和生成招牌。
    Rect(60, 650, 420, 20, "ink", 180)
    Text(74, 660, room.layoutName or "办公分区", 12, "muted", NVG_ALIGN_LEFT)
    -- 地面分区线/导向标记都是可通行贴花，不冒充碰撞墙。
    if room.kind == "elite" then
        for i = 0, 7 do
            Rect(60 + i * 18, 157, 10, 3, "gold", 165)
            Rect(848 + i * 18, 157, 10, 3, "gold", 165)
        end
    end
    local spawn = Game.GetSpawn(g)
    Rect(spawn.x - 38, spawn.y + 38, 76, 14, "ink", 95)
    Rect(spawn.x - 28, spawn.y + 41, 56, 2, "accent", 100)
end

local function Keyboard(x, y, angle, scale)
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, angle)
    nvgScale(vg, scale or 1, scale or 1)
    Rect(-19, -8, 38, 16, "ink")
    Rect(-17, -7, 34, 12, "muted")
    for row = 1, 2 do
        for col = 1, 8 do Rect(-18 + col * 4, -9 + row * 4, 3, 3, "white") end
    end
    Rect(-9, 3, 18, 2, "teal")
    nvgRestore(vg)
end

local function Boss(g, e)
    local floor = math.max(1, math.min(3, e.bossFloor or g.floor or 1))
    local name = floor == 1 and "coworker" or (floor == 2 and "supervisor" or "owner")
    Art.Actor(name, e.x, e.y, VisualScale.ActorHeight(name),
        e.x < g.player.x, g.visualTime + e.seed, e.dashing == true, e.hit > 0, 1)
    if g.bossPhase == 1 then
        Stroke(e.x, e.y - 2, 29 + math.sin(g.visualTime * 5) * 2, 2, "pink", 125)
    end
end

local function Entity(g, e)
    Shadow(e.x, e.y, e.kind == 5 and 60 or 32)
    if e.kind == 5 then
        Boss(g, e)
    else
        local name = e.kind == 1 and "ghost" or (e.kind == 2 and "paper" or (e.kind == 3 and "message" or "pot"))
        Art.Actor(name, e.x, e.y, VisualScale.ActorHeight(name), e.x > g.player.x, g.visualTime + e.seed, e.kind ~= 3, e.hit > 0, 1)
    end
    if e.hp < e.maxHp and e.kind ~= 5 then
        Rect(e.x - 16, e.y + 7, 32, 4, "ink", 220)
        Rect(e.x - 15, e.y + 8, 30 * math.max(0, e.hp / e.maxHp), 2, "pink")
    end
end

local function Player(g)
    local p = g.player
    local name = g.heroId == "female" and "female" or "male"
    Shadow(p.x, p.y, 34)
    Stroke(p.x, p.y - 1, 18, 1, name == "female" and "pink" or "teal", 125)
    local alpha = p.invuln > 0 and math.floor(g.visualTime * 18) % 2 == 0 and 0.48 or 1
    Art.Actor(name, p.x, p.y, VisualScale.ActorHeight(name), p.faceX < 0, g.visualTime, p.moving, false, alpha)
end

local function Effects(g)
    for _, e in ipairs(g.effects) do
        local ratio = math.max(0, e.life / e.maxLife)
        if e.kind == "slash" then
            nvgSave(vg)
            nvgTranslate(vg, e.x, e.y - 12)
            nvgRotate(vg, e.angle)
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, e.size * (1 - ratio * 0.15), -1.52, 1.52, NVG_CW)
            nvgStrokeWidth(vg, 16 * ratio)
            nvgStrokeColor(vg, Color("teal", 190 * ratio))
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgArc(vg, 0, 0, e.size - 7, -1.4, 1.4, NVG_CW)
            nvgStrokeWidth(vg, 3)
            nvgStrokeColor(vg, Color("white", 240 * ratio))
            nvgStroke(vg)
            Keyboard(math.cos((1 - ratio) * 2.6 - 1.3) * (e.size - 18),
                math.sin((1 - ratio) * 2.6 - 1.3) * (e.size - 18), 0.6, 1)
            nvgRestore(vg)
        elseif e.kind == "burst" then
            Stroke(e.x, e.y, e.size * (1 - ratio), 7 * ratio + 2, "teal", ratio * 220)
            Stroke(e.x, e.y, e.size * (1 - ratio) * 0.85, 2, "gold", ratio * 170)
        elseif e.kind == "warning" then
            nvgSave(vg)
            nvgTranslate(vg, e.x, e.y)
            nvgRotate(vg, e.angle)
            Rect(0, -22, 500, 44, "pink", 35 + math.sin(g.visualTime * 25) * 20)
            Rect(0, -23, 500, 2, "pink", 160)
            Rect(0, 22, 500, 2, "pink", 160)
            nvgRestore(vg)
        elseif e.kind == "coffee" then
            Stroke(e.x, e.y, (1 - ratio) * 70, 4, "gold", ratio * 200)
        else
            local color = e.kind == "hurt" and "pink" or (e.kind == "crit" and "gold" or "white")
            Text(e.x, e.y - (1 - ratio) * 28, e.text, e.kind == "crit" and 22 or 17, color, nil, ratio * 255)
        end
    end
end

function Draw.Init()
    vg = nvgCreate(0)
    font = nvgCreateFont(vg, "pixel", "Fonts/FusionPixel-12px-Prop-zh_hans.ttf")
    Art.Init(vg)
    print("[绘制] 生图像素美术上下文就绪，字体句柄=" .. font)
    return vg
end

function Draw.Stop()
    Art.Stop()
    if vg then nvgDelete(vg); vg = nil end
end

-- raw NanoVG 模式B：先用系统逻辑分辨率与DPR，场景按可用面板响应式取景。
function Draw.Render(g, area, uiScale)
    if not vg then return end
    local dpr = graphics:GetDPR()
    local physicalWidth, physicalHeight = graphics:GetWidth(), graphics:GetHeight()
    if not VisualScale.IsPositiveSize(dpr) or not VisualScale.IsPositiveSize(uiScale)
        or not VisualScale.IsPositiveSize(physicalWidth) or not VisualScale.IsPositiveSize(physicalHeight)
        or not VisualScale.IsFinite(area.x) or not VisualScale.IsFinite(area.y)
        or not VisualScale.IsPositiveSize(area.w) or not VisualScale.IsPositiveSize(area.h) then return end
    local width, height = physicalWidth / dpr, physicalHeight / dpr
    local factor = uiScale / dpr
    local ax, ay, aw, ah = area.x * factor, area.y * factor, area.w * factor, area.h * factor
    if not VisualScale.IsPositiveSize(width) or not VisualScale.IsPositiveSize(height)
        or not VisualScale.IsFinite(ax) or not VisualScale.IsFinite(ay) then return end
    -- 保留原地图；短边决定等比缩小、长边增加视野，绝不以高屏COVER放大世界。
    local camera = VisualScale.Camera(aw, ah, g.player.x, g.player.y, Game.WIDTH, Game.HEIGHT,
        g.mode == "menu" or g.mode == "character")
    -- 所有校验必须在BeginFrame之前；无效布局不开始半截NanoVG帧，下一帧自动恢复。
    if not camera then return end
    nvgBeginFrame(vg, width, height, dpr)
    nvgShapeAntiAlias(vg, 0)
    local zoom = camera.zoom
    local ox, oy = ax + aw / 2 - camera.x * zoom, ay + ah / 2 - camera.y * zoom
    Rect(ax, ay, aw, ah, "ink")
    nvgSave(vg)
    nvgScissor(vg, ax, ay, aw, ah)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, zoom, zoom)
    if g.shake > 0 then nvgTranslate(vg, math.sin(g.visualTime * 130) * g.shake, math.cos(g.visualTime * 110) * g.shake * 0.6) end
    Background(g)
    for _, pool in ipairs(g.pools) do
        local a = math.min(1, pool.life) * 140
        Circle(pool.x, pool.y, pool.radius, "woodDark", a)
        Stroke(pool.x, pool.y, pool.radius - 3, 2, "gold", a)
        for i = 1, 5 do Rect(pool.x + math.sin(i * 17) * pool.radius * 0.7,
            pool.y + math.cos(i * 11) * pool.radius * 0.7, 5, 3, "gold", a) end
    end
    for _, gem in ipairs(g.gems) do
        local y = gem.y - 3 + math.sin(g.visualTime * 4 + gem.x) * 2
        if gem.heal then
            Rect(gem.x - 7, y - 8, 14, 16, "ink")
            Rect(gem.x - 5, y - 6, 10, 12, "white")
            Rect(gem.x - 1, y - 4, 2, 8, "pink")
            Rect(gem.x - 3, y - 1, 6, 2, "pink")
        else
            Rect(gem.x - 5, y - 5, 10, 10, "tealDark")
            Rect(gem.x - 3, y - 7, 6, 14, "tealDark")
            Rect(gem.x - 3, y - 4, 6, 8, "teal")
            Rect(gem.x - 1, y - 5, 2, 4, "white")
        end
    end
    -- 家具/玩家/敌人按同一脚点排序，角色走到隔断后会被遮挡。
    local sorted = {}
    for i, d in ipairs(Game.GetDesks(g)) do
        sorted[#sorted + 1] = { y = d.y + d.h, kind = "furniture", data = d, index = i }
    end
    for _, e in ipairs(g.enemies) do
        if e.hp > 0 then sorted[#sorted + 1] = { y = e.y, kind = "enemy", data = e } end
    end
    sorted[#sorted + 1] = { y = g.player.y, kind = "player" }
    table.sort(sorted, function(a, b) return a.y < b.y end)
    for _, item in ipairs(sorted) do
        if item.kind == "furniture" then Furniture(item.data, item.index, g.floor)
        elseif item.kind == "player" then Player(g)
        else Entity(g, item.data) end
    end
    for _, s in ipairs(g.shots) do
        nvgSave(vg); nvgTranslate(vg, s.x, s.y); nvgRotate(vg, math.atan(s.vy, s.vx))
        Rect(-13, -3, 22, 6, "teal", 50)
        Rect(-7, -2, 14, 4, "white")
        Rect(5, -3, 3, 6, "teal")
        nvgRestore(vg)
    end
    for _, s in ipairs(g.hostileShots) do
        Rect(s.x - 9, s.y - 6, 18, 12, "ink")
        Rect(s.x - 7, s.y - 5, 14, 9, s.kind == 2 and "gold" or "pink")
        Rect(s.x - 4, s.y - 2, 8, 2, "ink")
        Rect(s.x - 5, s.y + 4, 4, 3, s.kind == 2 and "gold" or "pink")
    end
    for _, p in ipairs(g.particles) do Rect(p.x, p.y, p.size, p.size, p.color, math.min(255, p.life * 500)) end
    Effects(g)
    if g.flash > 0 then Rect(32, 20, 976, 628, "pink", g.flash * 230) end
    nvgRestore(vg)
    nvgEndFrame(vg)
end

return Draw
