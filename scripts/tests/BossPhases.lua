-- BOSS 三阶段回归。契约：BossPhases.lua 头注释（66%/33% 只升不降、三档倍率表、破防只延长不缩短、
-- 消费式 WantsCharge/WantsRing、P3+floor3 每 10s 自动破防 1.2s）。纯逻辑，无 DOM 依赖。
local BossPhases = require("BossPhases")

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

local function NewBoss(hp)
    return { hp = hp, maxHp = 1000 }
end

-- ------------------------------------------------------------------ ① Init / Tick 相位推进
local function InitTickChecks()
    local e = NewBoss(1000)
    local b = BossPhases.Init(e)
    ok(type(b) == "table" and b.phase == 1, "Init 建 phase=1")
    eq(e.boss, b, "Init 返回 e.boss")
    eq(b.breakTimer, 0, "Init breakTimer=0")
    -- 幂等：二次调用不重建
    b.phase, b.chargeTimer = 2, 1.5
    local b2 = BossPhases.Init(e)
    eq(b2, b, "Init 幂等（同一张表）")
    eq(b2.phase, 2, "幂等不重置 phase")
    near(b2.chargeTimer, 1.5, 1e-9, "幂等不重置计时器")
    eq(BossPhases.Init(nil), nil, "Init(nil) 不崩返回 nil")
    eq(BossPhases.Init(42), nil, "Init(非表) 返回 nil")

    -- 66% 进 P2、33% 进 P3，只升不降；同步写 g.bossPhase = phase-1
    local g = {}
    local t = NewBoss(1000)
    eq(BossPhases.Tick(g, t, 0.016), 1, "满血 Tick 仍 P1")
    eq(g.bossPhase, 0, "Tick 镜像 g.bossPhase=P1-1")
    t.hp = 660
    eq(BossPhases.Tick(g, t, 0.016), 2, "66% 进 P2")
    eq(g.bossPhase, 1, "P2 镜像")
    t.hp = 999 -- 回血不得降相位
    eq(BossPhases.Tick(g, t, 0.016), 2, "回血不降相位（只升不降）")
    t.hp = 330
    eq(BossPhases.Tick(g, t, 0.016), 3, "33% 进 P3")
    eq(g.bossPhase, 2, "P3 镜像")
    t.hp = 0
    eq(BossPhases.Tick(g, t, 0.016), 3, "0 血仍 P3")
    -- 边界：正好等于阈值即触发
    local r = NewBoss(1000)
    r.hp = 660.0
    BossPhases.Tick({}, r, 0)
    eq(r.boss.phase, 2, "ratio==0.66 即进 P2")
    -- maxHp 缺失不推进
    local nm = { hp = 1 }
    BossPhases.Tick({}, nm, 0.016)
    eq(nm.boss.phase, 1, "maxHp 缺失不推进相位")
    -- Tick(nil) 不崩
    eq(BossPhases.Tick(nil, nil, 0.016), 1, "Tick(nil,nil) 不崩返回 1")
end

-- ------------------------------------------------------------------ ② 三档倍率
local function MulChecks()
    local mk = function(phase)
        local e = NewBoss(1000)
        e.boss = { phase = phase }
        return e
    end
    near(BossPhases.SpeedMul(mk(1)), 1.00, 1e-9, "SpeedMul P1")
    near(BossPhases.SpeedMul(mk(2)), 1.15, 1e-9, "SpeedMul P2")
    near(BossPhases.SpeedMul(mk(3)), 1.30, 1e-9, "SpeedMul P3")
    near(BossPhases.CooldownMul(mk(1)), 1.00, 1e-9, "CooldownMul P1")
    near(BossPhases.CooldownMul(mk(2)), 0.85, 1e-9, "CooldownMul P2")
    near(BossPhases.CooldownMul(mk(3)), 0.70, 1e-9, "CooldownMul P3")
    near(BossPhases.DamageMul(mk(1)), 1.00, 1e-9, "DamageMul P1")
    near(BossPhases.DamageMul(mk(2)), 1.10, 1e-9, "DamageMul P2")
    near(BossPhases.DamageMul(mk(3)), 1.25, 1e-9, "DamageMul P3")
    eq(BossPhases.BulletCount(mk(1)), 1, "BulletCount P1")
    eq(BossPhases.BulletCount(mk(2)), 3, "BulletCount P2")
    eq(BossPhases.BulletCount(mk(3)), 5, "BulletCount P3")
    -- 返回值是 number（+0.0 浮点口径）
    ok(type(BossPhases.SpeedMul(mk(1))) == "number", "SpeedMul 返回 number")
    -- nil/非法实体兜底
    near(BossPhases.SpeedMul(nil), 1.0, 1e-9, "SpeedMul(nil) 兜底 P1")
    eq(BossPhases.BulletCount(nil), 1, "BulletCount(nil) 兜底 1")
end

-- ------------------------------------------------------------------ ③ 破防窗口
local function BreakChecks()
    local e = NewBoss(1000)
    eq(BossPhases.BreakWindow(e), false, "未破防 false")
    near(BossPhases.OpenBreak(e, 2.0), 2.0, 1e-9, "OpenBreak 开 2s 窗口")
    eq(BossPhases.BreakWindow(e), true, "窗口内 true")
    near(BossPhases.OpenBreak(e, 1.0), 2.0, 1e-9, "OpenBreak 只延长不缩短（1s 改不掉 2s）")
    near(BossPhases.OpenBreak(e, 3.0), 3.0, 1e-9, "更长的窗口可以延长")
    -- Tick 递减到 0
    BossPhases.Tick({}, e, 3.0)
    eq(BossPhases.BreakWindow(e), false, "Tick 递减后窗口关闭")
    -- OpenBreak 非法入参兜底 1.2
    local e2 = NewBoss(1000)
    near(BossPhases.OpenBreak(e2, -1), 1.2, 1e-9, "OpenBreak 非法时长兜底 1.2")
    near(BossPhases.OpenBreak(nil, 1), 0, 1e-9, "OpenBreak(nil) 返回 0 不崩")
    eq(BossPhases.BreakWindow(nil), false, "BreakWindow(nil) 不崩")
    eq(BossPhases.BreakWindow(42), false, "BreakWindow(非表) 不崩")

    -- P3+floor3 每 10s 自动破防 1.2s（floor1 不自动破防）
    local a = NewBoss(1000)
    a.bossFloor = 3
    a.boss = { phase = 3, breakTimer = 0, breakCd = 0 }
    for _ = 1, 9 do BossPhases.Tick({}, a, 1.0) end
    eq(BossPhases.BreakWindow(a), false, "floor3 P3 第 9s 未自动破防")
    BossPhases.Tick({}, a, 1.0)
    eq(BossPhases.BreakWindow(a), true, "floor3 P3 第 10s 自动破防")
    BossPhases.Tick({}, a, 1.2)
    eq(BossPhases.BreakWindow(a), false, "自动破防 1.2s 后关闭")
    local f1 = NewBoss(1000)
    f1.bossFloor = 1
    f1.boss = { phase = 3, breakTimer = 0, breakCd = 0 }
    for _ = 1, 12 do BossPhases.Tick({}, f1, 1.0) end
    eq(BossPhases.BreakWindow(f1), false, "floor1 P3 不自动破防")
end

-- ------------------------------------------------------------------ ④ 消费式意图与召唤
local function WantsChecks()
    -- WantsCharge：floor1+P3 每 6s 到点 true，读到一次后清
    local c = NewBoss(1000)
    c.bossFloor = 1
    c.boss = { phase = 3, chargeTimer = 0 }
    for _ = 1, 5 do BossPhases.Tick({}, c, 1.0) end
    eq(BossPhases.WantsCharge(c), false, "floor1 P3 5s 未到点")
    BossPhases.Tick({}, c, 1.0)
    eq(BossPhases.WantsCharge(c), true, "floor1 P3 6s 到点想冲锋")
    eq(BossPhases.WantsCharge(c), false, "WantsCharge 消费式（读后清）")
    -- floor2 P3 不冲锋
    local c2 = NewBoss(1000)
    c2.bossFloor = 2
    c2.boss = { phase = 3, chargeTimer = 0 }
    for _ = 1, 7 do BossPhases.Tick({}, c2, 1.0) end
    eq(BossPhases.WantsCharge(c2), false, "floor2 P3 不冲锋")
    -- floor1 P2 不冲锋
    local c3 = NewBoss(1000)
    c3.bossFloor = 1
    c3.boss = { phase = 2, chargeTimer = 0 }
    for _ = 1, 7 do BossPhases.Tick({}, c3, 1.0) end
    eq(BossPhases.WantsCharge(c3), false, "floor1 P2 不冲锋")

    -- WantsRing：floor3+P2 每 5s 到点，floor1 P3 不发
    local r = NewBoss(1000)
    r.bossFloor = 3
    r.boss = { phase = 2, ringTimer = 0 }
    for _ = 1, 4 do BossPhases.Tick({}, r, 1.0) end
    eq(BossPhases.WantsRing(r), false, "floor3 P2 4s 未到点")
    BossPhases.Tick({}, r, 1.0)
    eq(BossPhases.WantsRing(r), true, "floor3 P2 5s 到点想环形弹幕")
    eq(BossPhases.WantsRing(r), false, "WantsRing 消费式（读后清）")
    local r2 = NewBoss(1000)
    r2.bossFloor = 1
    r2.boss = { phase = 3, ringTimer = 0 }
    for _ = 1, 6 do BossPhases.Tick({}, r2, 1.0) end
    eq(BossPhases.WantsRing(r2), false, "floor1 P3 不发环形弹幕")

    -- SummonCount：floor2+P3 才 2；其它 0；SummonKind floor2=2
    local s = NewBoss(1000)
    s.bossFloor = 2
    s.boss = { phase = 3 }
    eq(BossPhases.SummonCount(s), 2, "SummonCount floor2 P3 = 2")
    eq(BossPhases.SummonKind(s), 2, "SummonKind floor2 = 2")
    s.boss.phase = 2
    eq(BossPhases.SummonCount(s), 0, "floor2 P2 不召唤")
    local s2 = NewBoss(1000)
    s2.bossFloor = 1
    s2.boss = { phase = 3 }
    eq(BossPhases.SummonCount(s2), 0, "floor1 P3 不召唤")
    eq(BossPhases.SummonKind(s2), 1, "SummonKind 非floor2 = 1")
end

-- ------------------------------------------------------------------ ⑤ 公告文案
local function LineChecks()
    local e = NewBoss(1000)
    e.bossFloor = 1
    local g = { bossName = "工贼同事" }
    local line = BossPhases.OnPhaseChange(g, e, 2)
    ok(type(line) == "string" and line:sub(1, #"工贼同事") == "工贼同事", "文案带 g.bossName 前缀")
    ok(type(BossPhases.OnPhaseChange({}, e, 3)) == "string", "无 bossName 仍返回文案")
    ok(type(BossPhases.OnPhaseChange(nil, nil, nil)) == "string", "全 nil 入参不崩")
    ok(type(BossPhases.OnPhaseChange(g, e, 99)) == "string", "phase 越界夹到 3 不崩")
end

-- ------------------------------------------------------------------ 入口
function M.Run()
    pass, fail = 0, 0
    InitTickChecks()
    MulChecks()
    BreakChecks()
    WantsChecks()
    LineChecks()
    print(string.format("[BossPhases] %d passed, %d failed", pass, fail))
    if fail > 0 then error(string.format("BossPhases: %d assertions failed", fail), 0) end
    if pass < 60 then error(string.format("BossPhases: 断言数 %d 少于 60", pass), 0) end
    return true
end

local function Start() return M.Run() end
M.Start = Start

return M
