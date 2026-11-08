-- 生图像素办公室：生成角色/场景/家具，程序化特效和真实碰撞分区。
-- 这里只消费玩法数据，不写入房间状态；HUD/商店交互统一交给 main.lua 的 UI。
local Draw = {}
local Game = require("Game")
local Art = require("Art")
local VisualScale = require("VisualScale")
local EnemyAnimation = require("EnemyAnimation")
local FufuVisuals=require("FufuVisuals")

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
local menuActors={
    {heroId="male",player={x=650,y=515,moving=true},locomotion={time=0,duration=.72,faceX=1,faceY=0}},
    {heroId="female",player={x=735,y=570,moving=false},locomotion={time=0,duration=1.2,faceX=0,faceY=1}},
}

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

-- 冲刺预告带：从脚点 (x,y) 沿单位方向 (dx,dy) 画一条前伸 len 的渐隐长条，末端带箭头。
-- gfx.js 只导出 nvgRect/nvgCircle/nvgEllipse/nvgArc，没有 nvgMoveTo/nvgLineTo，
-- 所以斜向长条只能用 nvgSave + nvgTranslate + nvgRotate 后在旋转坐标系里摆 Rect 拼。
-- back：向本体后方延伸的长度，让带子起点压在脚下而不是从身体外缘凭空开始（原来的脱节就出在这）。
local function ChargeLane(x, y, dx, dy, len, back, width, color, alpha)
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1e-4 or len <= 0 then return end
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, math.atan(dy / d, dx / d))
    local total = back + len
    local segs = 8
    for i = 0, segs - 1 do
        local t0 = i / segs
        -- 靠本体端最实，末端只剩 15%：既连住本体，又不会变成一条实心粉带压住地面。
        Rect(-back + total * t0, -width / 2, total / segs + 0.5, width, color, alpha * (1 - 0.85 * t0))
    end
    local head = math.max(6, width * 1.1)
    for s = -1, 1, 2 do
        nvgSave(vg)
        nvgTranslate(vg, len, 0)
        nvgRotate(vg, s * 0.62)
        Rect(-head, -1.5, head, 3, color, alpha * 0.85)
        nvgRestore(vg)
    end
    nvgRestore(vg)
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
    Art.Enemy(g,e)
    if g.bossPhase == 1 then
        Stroke(e.x, e.y - 2, 29 + math.sin(g.visualTime * 5) * 2, 2, "pink", 125)
    end
end

local AFFIX_LABELS = {guard="减伤", reflect="反伤", shield="护盾", summon="召唤", haste="疾速", volatile="自爆"}
local function Entity(g, e)
    local name=EnemyAnimation.Name(e)
    Shadow(e.x, e.y, e.kind == 5 and 60 or (e.kind == 14 and 32 * 1.35 or 32))
    if e.kind == 5 then
        Boss(g, e)
    else
        local name = e.kind == 1 and "ghost" or (e.kind == 2 and "paper" or (e.kind == 3 and "message" or "pot"))
        Art.Enemy(g,e)
    end
    if not e.deathTime and e.hp < e.maxHp and e.kind ~= 5 then
        local height=VisualScale.ActorHeight(name)
        Rect(e.x - 16, e.y-height-9, 32, 4, "ink", 220)
        Rect(e.x - 15, e.y-height-8, 30 * math.max(0, e.hp / e.maxHp), 2, "pink")
    end
    if not e.deathTime and (e.hp or 0) > 0 then
        local tone = e.affix == "reflect" and "pink" or (e.affix == "volatile" and "gold" or "teal")
        local top = e.y - VisualScale.ActorHeight(name or "paper") - 22
        if AFFIX_LABELS[e.affix] then Text(e.x, top, AFFIX_LABELS[e.affix], 12, tone) end
        if (e.shieldMax or 0) > 0 and (e.shield or 0) > 0 then
            Rect(e.x-17, top+6, 34, 4, "ink", 220)
            Rect(e.x-16, top+7, 32*math.min(1,e.shield/e.shieldMax), 2, "blue")
        end
        if e.reflectPending then Stroke(e.x,e.y,180,2,"pink",160) end
        if e.blastTimer then
            Stroke(e.x,e.y,90,3,"gold",190)
            Stroke(e.x,e.y,90*math.max(0,e.blastTimer/.7),2,"pink",210)
        end
    end
    -- S2 状态指示：字段缺席时整块不执行，旧数据绘制完全不变。
    local armorBreak, dotTimer = e.armorBreak or 0, e.dotTimer or 0
    local markHits, stunTimer = e.markHits or 0, e.stunTimer or 0
    if armorBreak > 0 or dotTimer > 0 or markHits > 0 or stunTimer > 0 then
        local top = e.y - VisualScale.ActorHeight(name or "paper") - 16
        if stunTimer > 0 then
            -- 眩晕条按最长眩晕 1.2s（男主大招）归一化，否则 0.25s 的保温杯眩晕会让条子瞬间满格。
            Rect(e.x - 10, top - 11, 20 * math.min(1, stunTimer / 1.2), 3, "gold", 220)
        end
        if dotTimer > 0 then
            local blink = math.floor(g.visualTime * 12) % 2 == 0 and 255 or 120
            Rect(e.x - 3, top - 6, 6, 6, "purple", blink)
        end
        if armorBreak > 0 then
            local count = math.min(6, armorBreak)
            for i = 1, count do
                local bx = e.x - (count - 1) * 2.5 + (i - 1) * 5
                Rect(bx - 1, top - 1, 6, 6, "ink", 210)
                Rect(bx, top, 4, 4, "pink")
            end
        end
        if markHits > 0 then
            local count = math.min(6, markHits)
            for i = 1, count do
                Rect(e.x - (count - 1) * 2.5 + (i - 1) * 5, top + 6, 4, 4, "purple", 235)
            end
        end
    end
    -- S3 新怪状态可视化：只读 ai 字段，任一缺失整块跳过；尺寸按 radius 推算。
    local ai = e.ai
    if ai and e.hp > 0 then
        local brain = ai.brain
        if brain == "charger" then
            -- kind=6：蓄力时脚下收缩预警环 + 朝 chargeX/chargeY 的冲刺预告带；
            -- 冲刺时同一条带子淡出，玩家能读出"它正沿这条线撞过来"。
            -- 旧实现是从 e.x+cx*radius 起画的 45px 细条（len=radius*3），起点离本体一个身位，
            -- 画出来就是地上一根跟怪没关系的粉色长条——这就是脱节的根因。
            local cx, cy = ai.chargeX or 1, ai.chargeY or 0
            local laneW = e.radius * 0.8
            if ai.state == "windup" then
                local t = math.max(0, math.min(1, (ai.t or 0) / (ai.windup or 0.6)))
                Stroke(e.x, e.y, e.radius * (1.6 - 0.6 * t), 2, "pink", 150 + 80 * t)
                -- 预告带随蓄力进度由淡转实（70→200），长度固定 150px 便于判断落点。
                ChargeLane(e.x, e.y, cx, cy, 150, e.radius * 0.6, laneW, "pink", 70 + 130 * t)
            elseif ai.state == "charge" then
                -- 冲刺中按剩余时间淡出（200→70），带子始终贴着当前脚下，不会与本体分离。
                local k = math.max(0, math.min(1, (ai.t or 0) / (ai.chargeTime or 0.55)))
                ChargeLane(e.x, e.y, cx, cy, 150, e.radius * 0.6, laneW, "pink", 200 - 130 * k)
            end
        elseif brain == "spitter" then
            -- kind=7：fireCd 临近 0（<0.5s）头顶画 3 段蓄势刻度。
            local cd = ai.fireCd
            if cd and cd < 0.5 then
                local seg = cd < 0.17 and 3 or (cd < 0.34 and 2 or 1)
                -- 锚点必须是本怪自己的贴图名：spitter 与 paper 比例恰好都是 .72（=87.84），
                -- 数值相同才让旧写法看起来没问题；一旦某个比例被单独调整，头顶刻度就会脱节。
                local ty = e.y - VisualScale.ActorHeight("spitter") - 22
                for i = 1, seg do Rect(e.x - 8 + (i - 1) * 8, ty, 5, 4, "gold", 230) end
            end
        elseif brain == "bomber" then
            -- kind=11：距玩家越近脉动环越快，<60px 才显示。
            local p = g.player
            if p then
                local dx, dy = e.x - p.x, e.y - p.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < 120 then
                    -- 危险圈按真实自爆半径（ai.blastRadius=62）画：原来只有 22px 的脉动环，
                    -- 玩家看不出"站到 62px 内就会被炸"，指示器与实际伤害范围脱节。
                    Stroke(e.x, e.y, ai.blastRadius or 62, 1, "pink", 55)
                end
                if dist < 60 then
                    local pulse = 0.5 + 0.5 * math.sin(g.visualTime * (14 - dist * 0.14))
                    Stroke(e.x, e.y, e.radius * (1.2 + 0.5 * pulse), 2, "pink", 120 + 100 * pulse)
                end
            end
        elseif brain == "shield" then
            -- kind=12：guarding 时画朝 faceX/faceY 的 120° 正面护盾弧（半角 60°），冲锋中不画。
            -- 与 charger 同源的冲锋：windup/charge 沿 chargeX/chargeY 给方向预告带（青色对应护盾主题）。
            if ai.state == "windup" then
                local t = math.max(0, math.min(1, (ai.t or 0) / (ai.windup or 0.35)))
                ChargeLane(e.x, e.y, ai.chargeX or 1, ai.chargeY or 0, 130, e.radius * 0.6, e.radius * 0.8, "teal", 60 + 120 * t)
            elseif ai.state == "charge" then
                local k = math.max(0, math.min(1, (ai.t or 0) / (ai.chargeTime or 0.55)))
                ChargeLane(e.x, e.y, ai.chargeX or 1, ai.chargeY or 0, 130, e.radius * 0.6, e.radius * 0.8, "teal", 180 - 110 * k)
            end
            if ai.guarding then
                local fx, fy = e.faceX or 1, e.faceY or 0
                local face = math.atan(fy, fx)
                local half = math.pi / 3
                nvgBeginPath(vg)
                nvgArc(vg, e.x, e.y, e.radius * 1.5, face - half, face + half, NVG_CW)
                nvgStrokeWidth(vg, 3)
                nvgStrokeColor(vg, Color("teal", 190))
                nvgStroke(vg)
            end
        elseif brain == "summoner" then
            -- kind=13：summonCd < 1s 时脚下画旋转 4 点召唤阵。
            local cd = ai.summonCd
            if cd and cd < 1 then
                local spin = g.visualTime * 2.5
                local rr = e.radius * 1.7
                for i = 0, 3 do
                    local a = spin + i * math.pi / 2
                    Rect(e.x + math.cos(a) * rr - 2, e.y + math.sin(a) * rr * 0.5 - 2, 4, 4, "purple", 210)
                end
            end
        elseif brain == "boss_printer" then
            -- kind=14：cycle 1/2/3 → 头顶金/紫/粉小方块。
            local cycle = ai.cycle or 0
            local col = cycle == 1 and "gold" or (cycle == 2 and "purple" or "pink")
            -- 血条占 e.y-height-9 .. -5，方块原来放 -14..-6 会压住血条；上移到 -22 的独立一行。
            local topY = e.y - VisualScale.ActorHeight("printerBoss") - 22
            Rect(e.x - 4, topY, 8, 8, col)
            -- cycle==3 是冲锋招（windup 0.45s / chargeTime 0.7s），同款金色预告带。
            if ai.state == "windup" then
                local t = math.max(0, math.min(1, (ai.t or 0) / (ai.windup or 0.45)))
                ChargeLane(e.x, e.y, ai.chargeX or 1, ai.chargeY or 0, 170, e.radius * 0.6, e.radius * 0.8, "gold", 70 + 130 * t)
            elseif ai.state == "charge" then
                local k = math.max(0, math.min(1, (ai.t or 0) / (ai.chargeTime or 0.7)))
                ChargeLane(e.x, e.y, ai.chargeX or 1, ai.chargeY or 0, 170, e.radius * 0.6, e.radius * 0.8, "gold", 200 - 130 * k)
            end
        end
    end
end

local function Player(g)
    local p = g.player
    local name = g.heroId or "male"
    -- 冲刺残影：沿冲刺反方向留两个曳光圆，先画才在角色身后。
    if (p.dashTimer or 0) > 0 then
        local dx, dy = p.dashDirX or 0, p.dashDirY or 0
        Circle(p.x - dx * 14, p.y - dy * 14, 10, "teal", 60)
        Circle(p.x - dx * 28, p.y - dy * 28, 10, "teal", 30)
    end
    Shadow(p.x, p.y, 34)
    Stroke(p.x, p.y - 1, 18, 1, name == "female" and "pink" or "teal", 125)
    local alpha = p.invuln > 0 and math.floor(g.visualTime * 18) % 2 == 0 and 0.48 or 1
    Art.Hero(g, VisualScale.ActorHeight(name), alpha)
end

local function Effects(g)
    for _, e in ipairs(g.effects) do
        local ratio = math.max(0, e.life / e.maxLife)
        local frame=math.min(4,1+math.floor((1-ratio)*4))
        if FufuVisuals.Effect(Art,e,g)then
        elseif e.kind == "slash" then
            Art.Fx("weapon",frame,e.x+math.cos(e.angle)*e.size*.4,
                e.y-22+math.sin(e.angle)*e.size*.4,e.size*1.55,1,e.angle)
        elseif e.kind == "burst" then
            Art.Fx("area",8+frame,e.x,e.y-8,e.size*2.15,math.min(1,ratio*3))
        elseif e.kind=="stapleHit"then
            Art.Fx("weapon",8+frame,e.x,e.y,e.size,math.min(1,ratio*3))
        elseif e.kind=="binaryHit"then
            Art.Fx("combatExpansion",(e.text=="1"and 8 or 4)+frame,e.x,e.y,e.size*(1.3-ratio*.3),ratio)
        elseif e.kind=="paperclipHit"then
            Art.Fx("clipProjectile",1,e.x,e.y,e.size*(.8+(1-ratio)*.3),ratio,(1-ratio)*1.5)
        elseif e.kind=="paperclipCast"then
            Art.Fx("weaponExpansion",4+frame,e.x,e.y,e.size,ratio,e.angle)
        elseif e.kind=="pickup"then
            Art.Fx("area",ratio>.5 and 15 or 16,e.x,e.y,e.size,ratio)
        elseif e.kind=="coin"then
            Art.Fx("loot",4,e.x,e.y-(1-ratio)*30,e.size,math.min(1,ratio*3),nil,true)
        elseif e.kind == "warning" then
            nvgSave(vg)
            nvgTranslate(vg, e.x, e.y)
            nvgRotate(vg, e.angle)
            Rect(0, -22, 500, 44, "pink", 35 + math.sin(g.visualTime * 25) * 20)
            Rect(0, -23, 500, 2, "pink", 160)
            Rect(0, 22, 500, 2, "pink", 160)
            nvgRestore(vg)
        elseif e.kind == "coffee" then
            Art.Fx("weapon",12+frame,e.x,e.y-8,e.size*2,math.min(1,ratio*3))
        elseif e.kind=="folderSlam"then
            Art.Fx("combatExpansion",frame,e.x,e.y-35,e.size*.75,math.min(1,ratio*3),e.angle)
        elseif e.kind=="shieldImpact"then
            Art.Fx("combatExpansion",12+frame,e.x,e.y,e.size,math.min(1,ratio*3))
        elseif e.kind=="codeCast"then
            Art.Fx("weaponExpansion",12+frame,e.x,e.y,e.size,ratio,e.angle)
        elseif e.kind == "slamRing" then
            -- 男主大招砸桌：金色冲击环 + 8 条放射裂纹，全部程序化，不占图集帧。
            Stroke(e.x, e.y, e.size * (0.35 + (1 - ratio) * 0.65), 6 * ratio + 2, "gold", math.floor(ratio * 220))
            local crackLen = e.size * 0.8 * (1 - ratio)
            nvgSave(vg)
            nvgTranslate(vg, e.x, e.y)
            for i = 1, 8 do
                nvgSave(vg)
                nvgRotate(vg, i / 8 * math.pi * 2)
                Rect(e.size * 0.12, -1.5, crackLen, 3, "gold", math.floor(160 * ratio))
                nvgRestore(vg)
            end
            nvgRestore(vg)
        elseif e.kind == "scanRing" then
            -- 女主大招职场洞察：紫色扫描环由内向外收束。
            Stroke(e.x, e.y, e.size * (1 - ratio * 0.6), 3, "purple", math.floor(ratio * 200))
            Stroke(e.x, e.y, e.size * 0.6 * (1 - ratio * 0.4), 1, "purple", math.floor(120 * ratio))
        elseif e.kind == "mark" then
            -- 洞察标记的小十字。
            local markAlpha = math.floor(ratio * 255)
            Rect(e.x - e.size * 0.5, e.y - 1, e.size, 2, "purple", markAlpha)
            Rect(e.x - 1, e.y - e.size * 0.5, 2, e.size, "purple", markAlpha)
        elseif e.kind == "pieBoom" then
            Art.Fx("weaponExpansion",8+frame,e.x,e.y-8,e.size*2,math.min(1,ratio*3))
        elseif e.kind == "thermosSmash" then
            Art.Fx("weaponExpansion",frame,e.x,e.y-12,e.size*1.8,math.min(1,ratio*3),e.angle)
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
    -- Original night map, uniform responsive camera; no background recoloring.
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
        -- S2 分派：kind 缺省是旧咖啡池。pie/thermos 用程序化绘制，不新增图集帧。
        local fade = math.min(1, pool.life * 1.5)
        if pool.kind == "pie" then
            Art.Fx("weaponExpansion",12,pool.x,pool.y-5,pool.radius*2.1,fade*.55)
        elseif pool.kind == "thermos" then
            Art.Fx("weaponExpansion",4,pool.x,pool.y-5,pool.radius*2.1,fade*.50)
        else
            local age=3.6-pool.life
            local frame=age<.28 and math.min(4,1+math.floor(age/.07))or 5+math.floor(age*6)%4
            Art.Fx("area",frame,pool.x,pool.y-10,pool.radius*2.8,math.min(1,pool.life*2))
        end
    end
    for _, gem in ipairs(g.gems) do
        local y = gem.y - 3 + math.sin(g.visualTime * 4 + gem.x) * 2
        if gem.weapon then
            Art.Item(gem.weapon,gem.x,y-7,34,34)
        elseif gem.heal then
            Art.Item("riceball",gem.x,y-5,28,28)
        else
            local tier=gem.value>=20 and 3 or(gem.value>=10 and 2 or 1)
            local frame=tier==1 and 5+math.floor(g.time*5+gem.x)%4 or tier
            Art.Fx("loot",frame,gem.x,y-5,24+tier*3,1,nil,true)
        end
    end
    -- 家具/玩家/敌人按同一脚点排序，角色走到隔断后会被遮挡。
    local sorted = {}
    local function InView(x,y)
        return math.abs(x-camera.x)<camera.viewW/2+200 and math.abs(y-camera.y)<camera.viewH/2+200
    end
    for i, d in ipairs(Game.GetDesks(g)) do
        sorted[#sorted + 1] = { y = d.y + d.h, kind = "furniture", data = d, index = i }
    end
    for _, e in ipairs(g.enemies) do
        if e.hp > 0 and InView(e.x,e.y) then sorted[#sorted + 1] = { y = e.y, kind = "enemy", data = e } end
    end
    for _,pet in ipairs(g.pets or {})do if(pet.hp or 1)>0 and InView(pet.x,pet.y)then sorted[#sorted+1]={y=pet.y,kind="pet",data=pet}end end
    for _,e in ipairs(g.defeated or {})do if InView(e.x,e.y)then sorted[#sorted+1]={y=e.y,kind="enemy",data=e}end end
    if g.mode=="menu" then
        for _,actor in ipairs(menuActors)do
            actor.locomotion.time=g.visualTime
            sorted[#sorted+1]={y=actor.player.y,kind="menuActor",data=actor}
        end
    else sorted[#sorted + 1] = { y = g.player.y, kind = "player" } end
    table.sort(sorted, function(a, b) return a.y < b.y end)
    for _, item in ipairs(sorted) do
        if item.kind == "furniture" then Furniture(item.data, item.index, g.floor)
        elseif item.kind == "player" then Player(g)
        elseif item.kind=="pet"then FufuVisuals.Pet(Art,vg,g,item.data)
        elseif item.kind == "menuActor" then
            Shadow(item.data.player.x,item.data.player.y,34)
            Art.Hero(item.data,VisualScale.ActorHeight(item.data.heroId)*1.1,1)
        else Entity(g, item.data);FufuVisuals.Status(Art,g,item.data,VisualScale.ActorHeight(EnemyAnimation.Name(item.data))) end
    end
    for _, s in ipairs(g.shots) do
        -- kind 缺省即 staple：旧数据没有该字段，必须走原画法。
        local shotKind = s.kind or "staple"
        if shotKind=="bulb"then FufuVisuals.Bulb(Art,s,g)
        elseif shotKind=="binary"then
            Art.Fx("combatExpansion",(s.digit==1 and 8 or 4)+1+math.floor(g.time*12)%4,s.x,s.y-10,36,1)
        elseif shotKind == "paperclip" then
            Art.Fx("clipProjectile",1,s.x,s.y-10,27,1,math.atan(s.vy,s.vx))
        elseif shotKind == "pie" then
            -- 大饼：life 按 1.0 归一的 sin 伪造抛物线高度，越接近落地半径越大。
            local t = math.max(0, math.min(1, 1 - (s.life or 0)))
            local lift = math.max(0, math.sin(t * math.pi))
            local height = lift * 26
            Art.Item("pie",s.x,s.y-10-height,32,32)
        else
            Art.Fx("weapon",5+math.floor(g.time*12)%4,s.x,s.y-10,57,1,math.atan(s.vy,s.vx))
        end
    end
    for _, s in ipairs(g.hostileShots) do
        Art.Item("phone",s.x,s.y-8,22,27)
    end
    for _, p in ipairs(g.particles) do Rect(p.x, p.y, p.size, p.size, p.color, math.min(255, p.life * 500)) end
    Effects(g)
    if g.flash > 0 then Rect(32, 20, 976, 628, "pink", g.flash * 230) end
    nvgRestore(vg)
    nvgEndFrame(vg)
end

return Draw
