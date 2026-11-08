-- 武器数值与等级回归（S2）。契约：lua/Weapons.lua 顶部注释 + docs/design/02-weapons-buffs-ults.md §2。
-- 本文件只 require Weapons，不依赖 Game/Navigation（Weapons.lua:5-7 的设计承诺）。
-- 数值即契约：改 Weapons.lua 任何一个常数都会让这里红。
local Weapons = require("Weapons")

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

-- 最小 g fixture：Weapons 只读写 g.weapons / g.weaponTimer / thermosCombo / paperclipCount
local function NewG()
    return {
        weapons = { thermos = 0, paperclip = 0, pie = 0, laser = 0, extinguisher = 0 },
        weaponTimer = { thermos = 0, paperclip = 0, pie = 0, laser = 0, extinguisher = 0 },
        thermosCombo = 0, paperclipCount = 0,
    }
end

-- ------------------------------------------------------------------ ① 纯数据/公式
local function DataChecks()
    -- 1. 启用列表恰好 3 把、顺序即 DEFS 顺序；laser/extinguisher 定义保留但 disabled
    local list = Weapons.EnabledList()
    eq(#list, 3, "EnabledList 数量 = 3")
    eq(list[1].id, "thermos", "EnabledList[1].id")
    eq(list[2].id, "paperclip", "EnabledList[2].id")
    eq(list[3].id, "pie", "EnabledList[3].id")
    ok(Weapons.Get("laser") ~= nil and Weapons.Get("laser").enabled == false, "laser 存在且 disabled")
    ok(Weapons.Get("extinguisher") ~= nil and Weapons.Get("extinguisher").enabled == false, "extinguisher 存在且 disabled")

    -- 2. 保温杯伤害表 L1..L5 严格单调递增（减半口径：46..104）
    eq(Weapons.ThermosDamage(1), 46, "ThermosDamage(1)")
    eq(Weapons.ThermosDamage(5), 104, "ThermosDamage(5)")
    for l = 1, 4 do
        ok(Weapons.ThermosDamage(l) < Weapons.ThermosDamage(l + 1),
            string.format("ThermosDamage L%d(%d) < L%d(%d)", l, Weapons.ThermosDamage(l), l + 1, Weapons.ThermosDamage(l + 1)))
    end
    eq(Weapons.Get("thermos").damage[1], 46, "Get(thermos).damage[1]")
    eq(Weapons.Get("thermos").damage[5], 104, "Get(thermos).damage[5]")

    -- 3. 三把启用武器伤害曲线全部严格单调
    local curves = {
        { id = "thermos", fn = Weapons.ThermosDamage },
        { id = "paperclip", fn = Weapons.PaperclipDamage },
        { id = "pie", fn = Weapons.PieDamage },
    }
    for _, c in ipairs(curves) do
        for l = 1, 4 do
            ok(c.fn(l) < c.fn(l + 1),
                -- %d 遇到小数（回形针削弱后 damage[1]=13.5）会在 Lua 5.3 抛
                -- "number has no integer representation"，改用 %s 走 tostring。
                string.format("%s damage L%d(%s) < L%d(%s)", c.id, l, tostring(c.fn(l)), l + 1, tostring(c.fn(l + 1))))
        end
    end

    -- 4. 范围/穿透：96+6L；pierce 表 {0,0,1,1,2}
    eq(Weapons.ThermosRadius(1), 102, "ThermosRadius(1)=96+6*1")
    eq(Weapons.ThermosRadius(5), 126, "ThermosRadius(5)=96+6*5")
    ok(Weapons.ThermosRadius(1) < Weapons.ThermosRadius(5), "保温杯半径随等级扩大")
    eq(Weapons.PaperclipPierce(1), 0, "PaperclipPierce(1)")
    eq(Weapons.PaperclipPierce(5), 2, "PaperclipPierce(5)")

    -- 4b. 回形针弹弓削弱（task-9，用户口径「射速，攻击削弱10%」）：
    --     伤害全档 ×0.9（保留一位小数，不取整——Hit 侧 math.floor 会自然取整），
    --     射速 −10% ⇔ 间隔 ×1.1（0.34 → 0.374）。
    --     基准常数 13.5 必须与 damage[1] 一致，否则 Scaling.Growth 的 Lv1 基准会漂。
    near(Weapons.Get("paperclip").damage[1], 13.5, 1e-9, "paperclip damage[1]=13.5（削弱后）")
    near(Weapons.Get("paperclip").damage[5], 33.3, 1e-9, "paperclip damage[5]=33.3（削弱后）")
    near(Weapons.PaperclipDamage(1), 13.5, 1e-9, "PaperclipDamage(1) 与 damage[1] 同步")
    near(Weapons.PaperclipDamage(5), 33.3, 1e-9, "PaperclipDamage(5) 无成长偏差")
    near(Weapons.PaperclipCooldown(1), 0.374, 1e-9, "PaperclipCooldown(1)=0.374（射速 −10%）")

    -- 5. 大饼半径：56+5L、70+8L
    eq(Weapons.PieExplodeRadius(1), 61, "PieExplodeRadius(1)=56+5*1")
    eq(Weapons.PiePoolRadius(1), 78, "PiePoolRadius(1)=70+8*1")
    eq(Weapons.PieExplodeRadius(5), 81, "PieExplodeRadius(5)=56+5*5")
    eq(Weapons.PiePoolRadius(5), 110, "PiePoolRadius(5)=70+8*5")

    -- 6/7. 冷却按攻速反比缩放
    near(Weapons.ThermosCooldown(1.0), 1.15, 0.001, "ThermosCooldown(1.0)")
    near(Weapons.ThermosCooldown(2.0), 0.575, 0.001, "ThermosCooldown(2.0)")
    near(Weapons.PaperclipCooldown(1.0), 0.374, 0.001, "PaperclipCooldown(1.0)")
    ok(Weapons.ThermosCooldown(2.0) < Weapons.ThermosCooldown(1.0), "攻速越快冷却越短")

    -- 顺带锁死 PieCooldown 公式（Weapons.lua:146 注释口径 2.05/(1+0.08L)）
    near(Weapons.PieCooldown(1), 2.05 / 1.08, 1e-9, "PieCooldown(1)")
end

-- ------------------------------------------------------------------ ② 等级状态机
local function StateChecks()
    -- 8. Level 读 g.weapons、Upgrade 升 1 级、上限 5
    local g = NewG()
    eq(Weapons.Level(g, "thermos"), 0, "Level 初始 0")
    ok(Weapons.Has(g, "thermos") == false, "L0 时 Has=false")
    eq(Weapons.Upgrade(g, "thermos"), 1, "Upgrade 返回新等级 1")
    eq(Weapons.Level(g, "thermos"), 1, "Upgrade 后 Level=1")
    ok(Weapons.Has(g, "thermos") == true, "L1 时 Has=true")
    for _ = 1, 8 do Weapons.Upgrade(g, "thermos") end
    eq(Weapons.Level(g, "thermos"), 5, "连升 8 次仍封顶 5")
    ok(g.weaponTimer.thermos ~= nil, "Upgrade 会补 weaponTimer 键（Weapons.lua:97-98）")
    -- Level 对缺失键安全兜底（Weapons.lua:87 or 0）
    eq(Weapons.Level(g, "nonesuch"), 0, "Level 缺失键兜底 0")

    -- 10. ResetTimers：五个计时键全归零 + 连击/计数清零
    local h = NewG()
    h.weaponTimer = { thermos = 1.5, paperclip = 0.3, pie = 2.0, laser = 0.1, extinguisher = 9.0 }
    h.thermosCombo, h.paperclipCount = 2, 4
    Weapons.ResetTimers(h)
    for _, id in ipairs({ "thermos", "paperclip", "pie", "laser", "extinguisher" }) do
        eq(h.weaponTimer[id], 0, "ResetTimers 清 weaponTimer." .. id)
    end
    eq(h.thermosCombo, 0, "ResetTimers 清 thermosCombo")
    eq(h.paperclipCount, 0, "ResetTimers 清 paperclipCount")

    -- 11. ClampLevel 夹取 -- 实测口径: 夹到 1..5（Weapons.lua:77-82）；
    -- "未持有=0"由 Level() 的 or 0 兜底承担，ClampLevel 本身不会返回 0。
    eq(Weapons.ClampLevel(-3), 1, "ClampLevel(-3) 下界夹到 1（实测口径）")
    eq(Weapons.ClampLevel(0), 1, "ClampLevel(0)")
    eq(Weapons.ClampLevel(1.7), 1, "ClampLevel(1.7) 先 floor")
    eq(Weapons.ClampLevel(3), 3, "ClampLevel(3) 区间内原样")
    eq(Weapons.ClampLevel(99), 5, "ClampLevel(99) 上界夹到 5")
end

-- ------------------------------------------------------------------ 入口
function M.Run()
    pass, fail = 0, 0
    DataChecks()
    StateChecks()
    print(string.format("[Weapons] %d passed, %d failed", pass, fail))
    if fail > 0 then error(string.format("Weapons: %d assertions failed", fail), 0) end
    if pass < 40 then error(string.format("Weapons: 断言数 %d 少于 40", pass), 0) end
    return true
end

local function Start() return M.Run() end
M.Start = Start

return M
