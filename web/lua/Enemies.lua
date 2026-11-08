-- Enemies.lua — S3 怪物定义与 AI 行为（kind 6/7/11/12/13/14）。
-- 契约（Game.lua 调用面，签名冻结）：Get/NAME/Init/Step。kind 1..5 定义仍在 Game.lua 本地 ENEMIES，数值锁死不得在此重复或覆盖。
-- 铁律：Step 内禁止 Navigation.Graph；移动只走 Game.Move/Chase，弹幕走 Game.HostileShot(g,x,y,vx,vy,damage)，
-- 召唤走 Game.Spawn，自爆伤害走 Game.TakeDamage。attackCooldown/stunTimer 由本文件自己递减。
local Enemies = {}

-- kind → each enemy's authored animation atlas; no recycled pot/paper stand-ins.
local NAMES = { [6] = "charger", [7] = "spitter", [11] = "bomber", [12] = "shieldGuard", [13] = "summoner", [14] = "printerBoss" }

-- 减半口径数值表。kind 14 是新 BOSS，hp=900 即为最终口径（Campaign.floors 之外的独立覆写）。
local DEFS = {
    [6]  = { hp = 62,  speed = 30, damage = 16, xp = 9,  radius = 15, brain = "charger" },
    [7]  = { hp = 44,  speed = 26, damage = 11, xp = 8,  radius = 13, brain = "spitter" },
    [11] = { hp = 34,  speed = 72, damage = 22, xp = 6,  radius = 13, brain = "bomber" },
    [12] = { hp = 96,  speed = 32, damage = 13, xp = 12, radius = 17, brain = "shield" },
    [13] = { hp = 110, speed = 28, damage = 15, xp = 14, radius = 18, brain = "summoner" },
    [14] = { hp = 900, speed = 40, damage = 21, xp = 0,  radius = 26, brain = "boss_printer" },
}

-- 引用 Game 的导出。Game 是全局表（Game.lua 顶部 local Game = {} 后挂在包名下导出）。
local function G()
    -- Resolve at call time: Game requires this module during its own load, and
    -- isolated rule tests temporarily supply a host without retaining that stub.
    return package.loaded["Game"]or require("Game")
end

function Enemies.Get(kind)
    return DEFS[kind]
end

function Enemies.NAME(kind)
    return NAMES[kind] or "ghost"
end

-- 保安 shield 脑：正面 120°（与朝向夹角 ≤60°）减伤 70%。玩家命中结算侧调用，返回 0.3 或 1.0。
function Enemies.ShieldMul(e, dirX, dirY)
    local ai = e and e.ai
    if not ai or ai.brain ~= "shield" or not ai.guarding then return 1 end
    local fx, fy = e.faceX or 1, e.faceY or 0
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 1e-4 then return 1 end
    local dot = (fx * dirX + fy * dirY) / (len * math.max(1e-4, math.sqrt(dirX * dirX + dirY * dirY)))
    return dot >= 0.5 and 0.3 or 1
end

-- 给实体 e 初始化 AI 字段。e 本体字段（hp/speed/damage/xp/radius/faceX/attackCooldown…）由 Game.Spawn 建立。
function Enemies.Init(e, kind)
    local def = DEFS[kind]
    if not def then return e end
    e.ai = { brain = def.brain, state = "idle", timer = 0, t = 0 }
    e.stunTimer = 0
    e.shieldHp = 0
    if def.brain == "charger" then
        -- chargeSpeed 11：base 30 × 11 ≈ 330px/s，对齐 03 文档的「冲刺 340」。
        -- 原来写 7 只有 210px/s，玩家走位就能躲，撞门专员没有威慑。
        e.ai.windup, e.ai.chargeSpeed, e.ai.chargeTime, e.ai.recover = 0.6, 11, 0.55, 0.4
        e.ai.chargeX, e.ai.chargeY = 1, 0
    elseif def.brain == "spitter" then
        e.ai.keepMin, e.ai.keepMax, e.ai.fireCd = 180, 260, 1.8
    elseif def.brain == "bomber" then
        e.ai.triggerDist, e.ai.blastRadius, e.ai.blastDamage = 46, 62, 22
    elseif def.brain == "shield" then
        e.ai.chargeCd, e.ai.chargeSpeed, e.ai.chargeTime, e.ai.windup, e.ai.recover = 4, 5, 0.55, 0.35, 0.4
        e.ai.chargeX, e.ai.chargeY = 1, 0
        e.ai.guarding = true
    elseif def.brain == "summoner" then
        e.ai.keepDist, e.ai.summonCd = 200, 5
    elseif def.brain == "boss_printer" then
        e.ai.cycle = 0          -- 1=扇形5发 2=全向8发 3=冲锋
        e.ai.gap, e.ai.windup, e.ai.chargeTime, e.ai.chargeSpeed = 1.6, 0.45, 0.7, 5
        e.ai.shotSpeed, e.ai.chargeX, e.ai.chargeY = 160, 1, 0
    end
    return e
end

-- 朝向更新：只有明显移动时才转向，避免贴脸抖动。
local function Face(e, nx, ny)
    if nx ~= 0 or ny ~= 0 then e.faceX, e.faceY = nx, ny end
end

-- 每帧推进该怪行为。返回 true=本帧行为已完全接管；false=交回 Game.lua 默认移动逻辑。
-- 约定：Game.UpdateEnemies 在调 Enemies.Step 前已递减 e.hit/e.shootTimer/attackCooldown（Animation.Step）；
-- 本函数自己递减 e.stunTimer 与 ai 内计时器。
-- 第 4 参 slow 来自 Game.UpdateEnemies 的咖啡池减速（1=正常，0.48=池中）。
-- 原来签名只有 3 参，Game 传的第 4 个被静默丢弃，导致咖啡池对新怪完全无效。
function Enemies.Step(g, e, dt, slow)
    local ai = e.ai
    if not ai then return false end
    local mov = slow or 1
    local attackRate=e.attackRate or 1
    e.stunTimer = math.max(0, (e.stunTimer or 0) - dt)
    local Game = G()
    local px, py = g.player.x, g.player.y
    local dx, dy = px - e.x, py - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local nx, ny = dist > 1e-4 and dx / dist or 1, dist > 1e-4 and dy / dist or 0

    if ai.brain == "charger" then
        -- 蓄力 0.6s（原地抖动）→ 冲刺 speed×7 持续 0.55s → 硬直 0.4s，循环；冲刺撞到玩家才造成伤害。
        if ai.state == "idle" then
            Face(e, nx, ny)
            ai.timer = ai.timer + dt*attackRate
            -- 阈值比较带 1e-6 容差：dt 累加（如 0.1×9）会得到 0.8999999999999999，严格 >= 会漏触发。
            if ai.timer >= 0.9 - 1e-6 and dist < 320 and G().Visible(g, e.x, e.y, px, py) then
                ai.state, ai.timer, ai.t = "windup", 0, 0
                ai.chargeX, ai.chargeY = nx, ny
            end
            return false       -- 平时交回默认追击
        elseif ai.state == "windup" then
            ai.t = ai.t + dt
            -- 原地抖动：小幅度来回蹭，不产生净位移
            local jig = math.sin(ai.t * 40) * 14 * dt
            G().Move(g, e, -nx * jig, -ny * jig, e.radius)
            if ai.t >= ai.windup then ai.state, ai.t = "charge", 0 end
            return true
        elseif ai.state == "charge" then
            ai.t = ai.t + dt
            G().Move(g, e, ai.chargeX * e.speed * ai.chargeSpeed * mov * dt, ai.chargeY * e.speed * ai.chargeSpeed * mov * dt, e.radius)
            -- 冲刺中撞到玩家才结算伤害（贴脸判定，不用动画 impact）
            if dist < e.radius + 30 and e.attackCooldown <= 0 then
                e.attackCooldown = 0.9
                G().TakeDamage(g, e.damage)
            end
            if ai.t >= ai.chargeTime then ai.state, ai.t, ai.timer = "recover", 0, 0 end
            return true
        else -- recover 硬直
            ai.t = ai.t + dt
            if ai.t >= ai.recover then ai.state, ai.timer, ai.t = "idle", 0, 0 end
            return true
        end

    elseif ai.brain == "bomber" then
        -- 高速贴近，距离 < 46 自爆：半径 62 内玩家 22 伤害，自己立刻死（hp=0）。
        if dist < ai.triggerDist then
            G().TakeDamage(g, e.damage or ai.blastDamage)
            e.hp = 0
            return true
        end
        return false           -- 贴身移动交给默认 Chase（speed 72 已够快）

    elseif ai.brain == "spitter" then
        -- 保持 180~260 距离；每 1.8s 扇形 3 发（-0.22/0/+0.22，弹速 300，伤害=e.damage）。
        ai.fireCd = ai.fireCd - dt*attackRate
        local canSee = G().Visible(g, e.x, e.y, px, py, 6)
        if ai.fireCd <= 0 and dist < 420 and canSee then
            ai.fireCd = 1.8
            local base = math.atan(dy, dx)
            local spd = 300
            for i = -1, 1 do
                local a = base + i * 0.22
                G().HostileShot(g, e.x, e.y, math.cos(a), math.sin(a), spd, e.damage)
            end
        end
        if not canSee then return false end
        -- 距离控制：太近后退，太远靠近，区间内站桩
        if dist < ai.keepMin then
            G().Move(g, e, -nx * e.speed * mov * dt, -ny * e.speed * mov * dt, e.radius)
            Face(e, nx, ny)
            e.moving = true
        elseif dist > ai.keepMax then
            G().Move(g, e, nx * e.speed * mov * dt, ny * e.speed * mov * dt, e.radius)
            Face(e, nx, ny)
            e.moving = true
        else
            e.moving = false
        end
        return true

    elseif ai.brain == "shield" then
        -- 每 4s 冲锋 1 次（charger 变体，速度×5）；平时正面朝玩家维持格挡（Guarding 姿态）。
        if ai.state == "idle" then
            Face(e, nx, ny)
            ai.chargeCd = ai.chargeCd - dt*attackRate
            ai.timer = ai.timer + dt
            if ai.chargeCd <= 0 and dist < 300 and G().Visible(g, e.x, e.y, px, py) then
                ai.state, ai.t, ai.chargeCd = "windup", 0, 4
                ai.chargeX, ai.chargeY = nx, ny
            end
            return false
        elseif ai.state == "windup" then
            ai.t = ai.t + dt
            if ai.t >= ai.windup then ai.state, ai.t = "charge", 0 end
            return true
        elseif ai.state == "charge" then
            ai.t = ai.t + dt
            ai.guarding = false       -- 冲锋时不格挡
            G().Move(g, e, ai.chargeX * e.speed * ai.chargeSpeed * mov * dt, ai.chargeY * e.speed * ai.chargeSpeed * mov * dt, e.radius)
            if dist < e.radius + 30 and e.attackCooldown <= 0 then
                e.attackCooldown = 0.9
                G().TakeDamage(g, e.damage)
            end
            if ai.t >= ai.chargeTime then ai.state, ai.t, ai.guarding = "recover", 0, false end
            return true
        else
            ai.t = ai.t + dt
            if ai.t >= ai.recover then ai.state, ai.t, ai.guarding = "idle", 0, true end
            return true
        end

    elseif ai.brain == "summoner" then
        -- 每 5s 召唤 1 只 kind=1 在自身周围；自身不强攻，保持 200 距离。
        ai.summonCd = ai.summonCd - dt*attackRate
        if ai.summonCd <= 0 and #g.enemies < 40 then
            ai.summonCd = 5
            local a = (e.seed or 0) + g.time * 1.7
            local sx, sy = e.x + math.cos(a) * 46, e.y + math.sin(a) * 46
            G().Spawn(g, 1, sx, sy)
        end
        if dist < ai.keepDist * 0.7 then
            -- 拉开距离，速度用满额
            G().Move(g, e, -nx * e.speed * mov * dt, -ny * e.speed * mov * dt, e.radius)
            Face(e, nx, ny)
            e.moving = true
        elseif dist > ai.keepDist * 1.3 then
            G().Move(g, e, nx * e.speed * 0.6 * mov * dt, ny * e.speed * 0.6 * mov * dt, e.radius)
            Face(e, nx, ny)
            e.moving = true
        else
            e.moving = false
        end
        return true

    elseif ai.brain == "boss_printer" then
        -- 三招循环：1=扇形5发弹幕 2=原地全向8发 3=冲锋；每招间隔 1.6s。
        if ai.state == "idle" then
            Face(e, nx, ny)
            ai.gap = ai.gap - dt
            if ai.gap <= 0 then
                ai.cycle = ai.cycle % 3 + 1
                if ai.cycle == 3 then
                    ai.state, ai.t = "windup", 0
                    ai.chargeX, ai.chargeY = nx, ny
                else
                    -- 弹幕招：扇形 5 发（对准玩家）或全向 8 发
                    local base = math.atan(dy, dx)
                    if ai.cycle == 1 then
                        for i = -2, 2 do
                            local a = base + i * 0.22
                            G().HostileShot(g, e.x, e.y, math.cos(a), math.sin(a), ai.shotSpeed, e.damage)
                        end
                    else
                        for i = 0, 7 do
                            local a = base + i / 8 * math.pi * 2
                            G().HostileShot(g, e.x, e.y, math.cos(a), math.sin(a), ai.shotSpeed * 0.8, e.damage)
                        end
                    end
                    ai.state, ai.t, ai.gap = "recover", 0, 1.6
                end
            end
            return false           -- 间隔期照常缓慢追击（默认逻辑）
        elseif ai.state == "windup" then
            ai.t = ai.t + dt
            local jig = math.sin(ai.t * 34) * 16 * dt
            G().Move(g, e, -nx * jig, -ny * jig, e.radius)
            if ai.t >= ai.windup then ai.state, ai.t, ai.gap = "charge", 0, 1.6 end
            return true
        elseif ai.state == "charge" then
            ai.t = ai.t + dt
            G().Move(g, e, ai.chargeX * e.speed * ai.chargeSpeed * mov * dt, ai.chargeY * e.speed * ai.chargeSpeed * mov * dt, e.radius)
            if dist < e.radius + 30 and e.attackCooldown <= 0 then
                e.attackCooldown = 0.9
                G().TakeDamage(g, e.damage)
            end
            if ai.t >= ai.chargeTime then ai.state, ai.t = "recover", 0 end
            return true
        else
            ai.t = ai.t + dt
            if ai.t >= 0.4 then ai.state = "idle" end
            return true
        end
    end

    return false
end

return Enemies
