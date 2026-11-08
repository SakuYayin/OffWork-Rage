-- S3 怪物定义与 AI 回归（kind 6/7/11/12/13/14）。契约：Enemies.lua 头注释（签名冻结 Get/NAME/Init/Step）。
-- 纯逻辑：Game 依赖（Visible/Move/TakeDamage/HostileShot/Spawn）用桩表替换。
-- 注意：Enemies.G() 惰性 require("Game") 并缓存 local Game——桩必须在首次 Step 前放入 package.loaded.Game，
-- 且之后只能原位重置计数器，不能换新表（换表后 Enemies 仍调用旧表）。
local realGame = package.loaded and package.loaded.Game or nil
local Enemies

local M = {}
local pass, fail = 0, 0

local function ok(cond, label)
    if cond then pass = pass + 1
    else
        fail = fail + 1
        print("  FAIL " .. label)
    end
end

local function eq(actual, expected, label)
    if actual == expected then pass = pass + 1
    else
        fail = fail + 1
        print(string.format("  FAIL %s: got %s want %s", label, tostring(actual), tostring(expected)))
    end
end

local function near(actual, expected, tol, label)
    if type(actual) == "number" and math.abs(actual - expected) <= tol then pass = pass + 1
    else
        fail = fail + 1
        print(string.format("  FAIL %s: got %s want %s±%s", label, tostring(actual),
            tostring(expected), tostring(tol)))
    end
end

-- ------------------------------------------------------------------ 桩（唯一一张表，原位重置）
local stub = {
    visible = true, moveCalls = 0, takeCalls = 0, takeDmg = nil,
    shotCalls = 0, shotDmg = nil, spawnCalls = 0, spawnKinds = {},
}
stub.Visible = function() return stub.visible end
stub.Move = function() stub.moveCalls = stub.moveCalls + 1 end
stub.TakeDamage = function(_, dmg) stub.takeCalls = stub.takeCalls + 1; stub.takeDmg = dmg end
stub.HostileShot = function(_, _, _, _, _, _, dmg)
    stub.shotCalls = stub.shotCalls + 1; stub.shotDmg = dmg
end
stub.Spawn = function(_, kind) stub.spawnCalls = stub.spawnCalls + 1; stub.spawnKinds[#stub.spawnKinds + 1] = kind end

local function ResetStub()
    stub.visible = true
    stub.moveCalls, stub.takeCalls, stub.takeDmg = 0, 0, nil
    stub.shotCalls, stub.shotDmg = 0, nil
    stub.spawnCalls = 0
    for i = 1, #stub.spawnKinds do stub.spawnKinds[i] = nil end
end

local function NewG(px, py)
    return { player = { x = px, y = py }, enemies = { {} }, pools = {}, time = 0, floor = 1 }
end

local function NewE(kind)
    local def = Enemies.Get(kind)
    local e = { x = 0, y = 0, hp = def.hp, speed = def.speed, damage = def.damage,
        xp = def.xp, radius = def.radius, faceX = 1, faceY = 0,
        attackCooldown = 0, moving = false }
    Enemies.Init(e, kind)
    return e
end

-- ------------------------------------------------------------------ ① 定义表 / NAME / Init / ShieldMul
local function DataChecks()
    local WANTS = {
        [6]  = { hp = 62, speed = 30, damage = 16, xp = 9, radius = 15, brain = "charger" },
        [7]  = { hp = 44, speed = 26, damage = 11, xp = 8, radius = 13, brain = "spitter" },
        [11] = { hp = 34, speed = 72, damage = 22, xp = 6, radius = 13, brain = "bomber" },
        [12] = { hp = 96, speed = 32, damage = 13, xp = 12, radius = 17, brain = "shield" },
        [13] = { hp = 110, speed = 28, damage = 15, xp = 14, radius = 18, brain = "summoner" },
        [14] = { hp = 900, speed = 40, damage = 21, xp = 0, radius = 26, brain = "boss_printer" },
    }
    for kind = 6, 14 do
        local def = Enemies.Get(kind)
        local w = WANTS[kind]
        if w then
            ok(def ~= nil, "Get(" .. kind .. ") 存在")
            if def then
                eq(def.hp, w.hp, "Get(" .. kind .. ").hp")
                eq(def.speed, w.speed, "Get(" .. kind .. ").speed")
                eq(def.damage, w.damage, "Get(" .. kind .. ").damage")
                eq(def.xp, w.xp, "Get(" .. kind .. ").xp")
                eq(def.radius, w.radius, "Get(" .. kind .. ").radius")
                eq(def.brain, w.brain, "Get(" .. kind .. ").brain")
            end
        else
            eq(Enemies.Get(kind), nil, "Get(" .. kind .. ") 不在 S3 表内")
        end
    end

    -- Six expanded enemies now use their own authored sprite sheets.
    local NAMES = { [6] = "charger", [7] = "spitter", [11] = "bomber", [12] = "shieldGuard", [13] = "summoner", [14] = "printerBoss" }
    local WHITELIST = { ghost = true, charger=true,spitter=true,bomber=true,shieldGuard=true,summoner=true,printerBoss=true }
    for kind = 6, 14 do
        local n = Enemies.NAME(kind)
        ok(WHITELIST[n] == true, "NAME(" .. kind .. ")=" .. tostring(n) .. " 在白名单")
        eq(n, NAMES[kind] or "ghost", "NAME(" .. kind .. ") 精确值")
    end
    eq(Enemies.NAME(1), "ghost", "NAME(1) 兜底 ghost")
    eq(Enemies.NAME(99), "ghost", "NAME(99) 兜底 ghost")

    -- Init：字段建立
    for kind = 6, 14 do
        if WANTS[kind] then
            local e = NewE(kind)
            eq(e.ai.brain, WANTS[kind].brain, "Init(" .. kind .. ").ai.brain")
        end
    end
    local e = NewE(6)
    eq(e.stunTimer, 0, "Init 后 stunTimer=0")
    eq(e.shieldHp, 0, "Init 后 shieldHp=0")
    eq(e.ai.state, "idle", "Init 后 state=idle")
    eq(e.ai.timer, 0, "Init 后 timer=0")
    near(e.ai.windup, 0.6, 1e-9, "charger windup 0.6")
    near(e.ai.chargeTime, 0.55, 1e-9, "charger chargeTime 0.55")
    -- 二次调用：重建同样结构（state/timer/stunTimer 全部复位）
    e.stunTimer, e.ai.timer = 0.7, 0.3
    Enemies.Init(e, 6)
    eq(e.ai.brain, "charger", "二次 Init brain 不变")
    eq(e.ai.state, "idle", "二次 Init state 复位")
    eq(e.ai.timer, 0, "二次 Init timer 复位")
    eq(e.stunTimer, 0, "二次 Init stunTimer 复位")
    local s = NewE(12)
    eq(s.ai.guarding, true, "shield 初始 guarding=true")
    near(s.ai.chargeCd, 4, 1e-9, "shield chargeCd 4")
    local b = NewE(14)
    eq(b.ai.cycle, 0, "boss_printer cycle 从 0 起")
    near(b.ai.gap, 1.6, 1e-9, "boss_printer gap 1.6")

    -- ShieldMul：非 shield 脑 1；guarding 正面 0.3 背面 1；不 guarding 1；零朝向 1
    local g0 = NewE(12)
    near(Enemies.ShieldMul(g0, 1, 0), 0.3, 1e-9, "正面命中 0.3")
    near(Enemies.ShieldMul(g0, -1, 0), 1, 1e-9, "背面命中 1")
    near(Enemies.ShieldMul(g0, 0.6, 0.8), 0.3, 1e-9, "斜向 dot=0.6>=0.5 仍 0.3")
    g0.ai.guarding = false
    near(Enemies.ShieldMul(g0, 1, 0), 1, 1e-9, "不 guarding 1")
    g0.ai.guarding = true
    g0.faceX, g0.faceY = 0, 0
    near(Enemies.ShieldMul(g0, 1, 0), 1, 1e-9, "零朝向向量 1")
    local c6 = NewE(6)
    near(Enemies.ShieldMul(c6, 1, 0), 1, 1e-9, "非 shield 脑 1")
    near(Enemies.ShieldMul(nil, 1, 0), 1, 1e-9, "nil 实体 1")
end

-- ------------------------------------------------------------------ ② Step 行为
local function StepChecks()
    -- charger：idle 累积 0.9s 且距离<320 -> windup 0.6 -> charge 0.55 -> recover 0.4 -> idle
    ResetStub()
    local g = NewG(300, 0)
    local e = NewE(6)
    for _ = 1, 8 do Enemies.Step(g, e, 0.1) end
    eq(e.ai.state, "idle", "charger 0.8s 未到阈值仍 idle")
    Enemies.Step(g, e, 0.1)
    eq(e.ai.state, "windup", "charger 累积 0.9s 且 dist<320 进 windup")
    Enemies.Step(g, e, 0.6)
    eq(e.ai.state, "charge", "charger windup 0.6s 后进 charge")
    Enemies.Step(g, e, 0.55)
    eq(e.ai.state, "recover", "charger charge 0.55s 后进 recover")
    Enemies.Step(g, e, 0.4)
    eq(e.ai.state, "idle", "charger recover 0.4s 后回 idle")
    ok(stub.moveCalls > 0, "charger windup/charge 走 Game.Move")
    eq(stub.takeCalls, 0, "charger 冲刺未贴脸不结算伤害")
    -- 距离远不进 windup
    local g2 = NewG(400, 0)
    local e2 = NewE(6)
    for _ = 1, 12 do Enemies.Step(g2, e2, 0.1) end
    eq(e2.ai.state, "idle", "charger dist>=320 不进 windup")
    -- stunTimer 自递减
    e2.stunTimer = 0.5
    Enemies.Step(g2, e2, 0.2)
    near(e2.stunTimer, 0.3, 1e-9, "Step 递减 stunTimer")

    -- bomber：dist<46 自爆 22 伤且 hp=0；远处不爆且交回默认移动
    ResetStub()
    local gb = NewG(30, 0)
    local eb = NewE(11)
    ok(Enemies.Step(gb, eb, 0.1) == true, "bomber 自爆帧接管")
    eq(stub.takeCalls, 1, "bomber 触发 TakeDamage")
    near(stub.takeDmg, 22, 1e-9, "bomber 自爆伤害 22")
    eq(eb.hp, 0, "bomber 自爆后 hp=0")
    ResetStub()
    local gb2 = NewG(100, 0)
    local eb2 = NewE(11)
    ok(Enemies.Step(gb2, eb2, 0.1) == false, "bomber 远距交回默认 Chase")
    eq(stub.takeCalls, 0, "bomber 远距不爆")
    eq(eb2.hp, 34, "bomber 远距不掉血")

    -- spitter：180..260 站桩；太近后退太远靠近；1.8s 到点连发 3 弹
    ResetStub()
    local gs = NewG(220, 0)
    local es = NewE(7)
    Enemies.Step(gs, es, 0.1)
    eq(es.moving, false, "spitter 区间内站桩")
    eq(stub.moveCalls, 0, "spitter 站桩不调 Move")
    eq(stub.shotCalls, 0, "spitter 未到 1.8s 不发弹")
    ResetStub()
    local gs2 = NewG(400, 0)
    local es2 = NewE(7)
    Enemies.Step(gs2, es2, 1.8)
    eq(stub.shotCalls, 3, "spitter 1.8s 到点连发 3 弹")
    eq(stub.shotDmg, 11, "spitter 弹幕伤害=e.damage")
    eq(es2.moving, true, "spitter 超距靠近 moving=true")
    ok(stub.moveCalls >= 1, "spitter 靠近调 Move")
    ResetStub()
    local gs3 = NewG(100, 0)
    local es3 = NewE(7)
    Enemies.Step(gs3, es3, 0.1)
    ok(stub.moveCalls >= 1, "spitter 太近后退调 Move")
    ResetStub()
    local gs4 = NewG(430, 0)
    local es4 = NewE(7)
    Enemies.Step(gs4, es4, 1.8)
    eq(stub.shotCalls, 0, "spitter dist>420 不发弹")

    -- summoner：5s 到点 Spawn kind=1 一次
    ResetStub()
    local gm = NewG(220, 0)
    local em = NewE(13)
    Enemies.Step(gm, em, 4.9)
    eq(stub.spawnCalls, 0, "summoner 4.9s 未到点不召唤")
    Enemies.Step(gm, em, 0.1)
    eq(stub.spawnCalls, 1, "summoner 5s 到点召唤一次")
    eq(stub.spawnKinds[1], 1, "summoner 召 kind=1")
    Enemies.Step(gm, em, 5.0)
    eq(stub.spawnCalls, 2, "summoner 再 5s 再召唤")
    ResetStub()
    local gm2 = NewG(100, 0)
    local em2 = NewE(13)
    Enemies.Step(gm2, em2, 0.1)
    ok(stub.moveCalls >= 1, "summoner 太近拉开距离")

    -- boss_printer：cycle 1(扇形5发) -> 2(全向8发) -> 3(冲锋) 循环
    ResetStub()
    local gp = NewG(400, 0)
    local ep = NewE(14)
    Enemies.Step(gp, ep, 1.6)
    eq(ep.ai.cycle, 1, "printer 第一招 cycle=1")
    eq(stub.shotCalls, 5, "printer cycle1 扇形 5 发")
    Enemies.Step(gp, ep, 0.4)
    eq(ep.ai.state, "idle", "printer 弹幕后 recover 0.4s 回 idle")
    Enemies.Step(gp, ep, 1.6)
    eq(ep.ai.cycle, 2, "printer 第二招 cycle=2")
    eq(stub.shotCalls, 13, "printer cycle2 全向 8 发")
    Enemies.Step(gp, ep, 0.4)
    Enemies.Step(gp, ep, 1.6)
    eq(ep.ai.cycle, 3, "printer 第三招 cycle=3")
    eq(ep.ai.state, "windup", "printer cycle3 进冲锋 windup")
    eq(stub.shotCalls, 13, "printer 冲锋招不发弹")
    Enemies.Step(gp, ep, 0.45)
    eq(ep.ai.state, "charge", "printer windup 0.45s 后 charge")
    Enemies.Step(gp, ep, 0.7)
    eq(ep.ai.state, "recover", "printer charge 0.7s 后 recover")
    Enemies.Step(gp, ep, 0.4)
    Enemies.Step(gp, ep, 1.6)
    eq(ep.ai.cycle, 1, "printer 三招循环回 cycle=1")
    eq(stub.shotCalls, 18, "printer 第二轮扇形 5 发")
    eq(stub.takeCalls, 0, "printer 冲刺未贴脸不结算")
end

-- ------------------------------------------------------------------ 入口
function M.Run()
    pass, fail = 0, 0
    package.loaded.Game = stub -- 首次 G() 前放桩；Enemies 缓存后一直用这张表
    Enemies = require("Enemies")
    DataChecks()
    StepChecks()
    package.loaded.Game = realGame -- 恢复现场（Enemies 的 local 缓存无法撤，Lead 每文件独立 VM 不受影响）
    print(string.format("[Enemies] %d passed, %d failed", pass, fail))
    if fail > 0 then error(string.format("Enemies: %d assertions failed", fail), 0) end
    if pass < 120 then error(string.format("Enemies: 断言数 %d 少于 120", pass), 0) end
    return true
end

local function Start() return M.Run() end
M.Start = Start

return M
