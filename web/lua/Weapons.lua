-- 《下班！别拦我》：武器数据与纯函数（S2 战斗系统）。
-- 设计依据：docs/design/02-weapons-buffs-ults.md §2，减半口径见 07-halved-plan.md §2.6：
--   thermos / paperclip / pie 三把启用；laser / extinguisher 定义保留但 enabled = false。
--
-- 【纯数据 + 纯函数】本模块不 require 任何玩法模块，也不碰 g 的实体表：
-- 命中判定、特效、音效一律留在 Game.lua 的 ActionImpact 里，本文件只回答「多少伤害、多大范围、多久冷却」。
-- 这样 tests/Weapons.lua 可以在没有 Game / Navigation 的环境里逐条断言数值。
--
-- 【等级】所有武器统一 maxLevel = 5，等级存 g.weapons[id]，与 g.upgrades[id] 双轨；
-- g.upgrades 负责「卡出过几次」（用于抽卡去重与上限），g.weapons 负责「当前等级」。
-- 两者由 Weapons.Upgrade 同步，任何别处都不要单独改 g.weapons。
--
-- 【表被 clamp】所有查表函数都接受 1..5 之外的等级并夹到区间内：
-- 抽卡上限已经挡住越界，这里再夹一次是为了让调试时手写 g.weapons.thermos = 9 不会数组取 nil。
local Weapons = {}
local Loadout=require("Loadout")
local Scaling=require("HeroScaling")

-- 表按 3 段排列：先启用，后禁用。顺序即 HUD 与抽卡展示顺序。
Weapons.DEFS = {
    {
        id = "thermos", title = "保温杯警告", tag = "武器 / 保温杯", color = "gold",
        desc = "近战三段连击。第三下砸碎地板，附带眩晕与枸杞池。",
        icon = "coffee", enabled = true, maxLevel = 5,
        -- 三段伤害：第 1/2 段取基数，第 3 段 ×1.45
        damage = { 46, 57, 70, 85, 104 },
        thirdMul = 1.45, thirdKnock = 468, normalKnock = 260, stun = 0.25,
        poolDamage = { 8, 10, 12, 14, 16 },
    },
    {
        id = "paperclip", title = "回形针弹弓", tag = "武器 / 弹弓", color = "teal",
        desc = "直线穿透。每第5发追加一枚强化回形针：伤害×1.4，额外穿透1次。",
        icon = "range", enabled = true, maxLevel = 5,
        damage = { 13.5, 17.1, 21.6, 27, 33.3 },
        pierce = { 0, 0, 1, 1, 2 },
        speed = 640, life = 0.62, knock = 70, slow = 0.6,
    },
    {
        id = "pie", title = "画饼充饥", tag = "武器 / 大饼", color = "pink",
        desc = "抛物线爆炸并在落点留下馋人的饼池，持续烫伤。",
        icon = "damage", enabled = true, maxLevel = 5,
        damage = { 52, 66, 83, 104, 130 },
        poolDamage = { 6, 8, 10, 12, 15 },
        knock = 110, poolLife = 4.2, poolTicks = 10,
    },
    {
        id = "laser", title = "激光打印", tag = "武器 / 打印机", color = "purple",
        desc = "六段跳射引导光束，对首领额外加成。（当前版本未启用）",
        icon = "attack", enabled = false, maxLevel = 5,
        damage = { 60, 74, 90, 110, 134 },
    },
    {
        id = "extinguisher", title = "灭火器", tag = "武器 / 重装", color = "purple",
        desc = "六发弹夹的范围喷射，打空留下干粉池。（当前版本未启用）",
        icon = "attack", enabled = false, maxLevel = 5,
        damage = { 18, 22, 27, 33, 40 },
    },
}

Weapons.LIST = Weapons.DEFS

local BY_ID = {}
for _, def in ipairs(Weapons.DEFS) do BY_ID[def.id] = def end

---@param id string
---@return table?
function Weapons.Get(id) return BY_ID[id] end

---@return table[] 只含 enabled 的武器，抽卡与 HUD 用这个
function Weapons.EnabledList()
    local out = {}
    for _, def in ipairs(Weapons.DEFS) do
        if def.enabled then out[#out + 1] = def end
    end
    return out
end

-- ---------------------------------------------------------------- 等级与计时
local function clampLevel(level)
    level = math.floor((level or 0) + 0.0)
    if level < 1 then return 1 end
    if level > 5 then return 5 end
    return level
end
Weapons.ClampLevel = clampLevel

---@return integer 0 表示还没拿到这把武器
function Weapons.Level(g, id)
    return (g.weapons and g.weapons[id]) or 0
end

function Weapons.Has(g, id) return Weapons.Level(g, id) > 0 end

---@return table 武器定义；未持有返回 def 但 level 为 0，调用方自行判断
function Weapons.Upgrade(g, id)
    local def=Weapons.Get(id)
    if not def or not def.enabled or not Loadout.Acquire(g,id)then return Weapons.Level(g,id)end
    g.weapons = g.weapons or {}
    local level = math.min(5, (g.weapons[id] or 0) + 1)
    g.weapons[id] = level
    g.weaponTimer = g.weaponTimer or {}
    if g.weaponTimer[id] == nil then g.weaponTimer[id] = 0 end
    return level
end

---@return number 冷却剩余
function Weapons.Timer(g, id)
    return (g.weaponTimer and g.weaponTimer[id]) or 0
end

function Weapons.SetTimer(g, id, value)
    g.weaponTimer = g.weaponTimer or {}
    g.weaponTimer[id] = value
end

-- 进房间/开新局必须清，否则上一间的冷却会带进下一间（tests/Actions.lua:420 换房断言会红）。
function Weapons.ResetTimers(g)
    g.weaponTimer = { thermos = 0, paperclip = 0, pie = 0, laser = 0, extinguisher = 0 }
    g.thermosCombo = 0
    g.paperclipCount = 0
end

-- ---------------------------------------------------------------- 数值表
-- 三个取表函数共用同一套夹取逻辑，避免每处都写一遍。
local function pick(def, key, level) return def[key][clampLevel(level)] end

---@return number 保温杯单段基础伤害（第 3 段由调用方乘 def.thirdMul）
function Weapons.ThermosDamage(level,g) return Scaling.Growth(g,46,pick(BY_ID.thermos,"damage",level)) end

---@return number 扇区半径：96 + 6*L（Lv1 = 102，Lv5 = 126）
function Weapons.ThermosRadius(level,g) return Scaling.Growth(g,102,96+6*clampLevel(level))end

---@param rate number 有效攻速倍率（g.attackSpeed × BUFF 攻速乘区）
---@return number 三段连击的冷却（秒）
function Weapons.ThermosCooldown(rate) return 1.15 / math.max(0.2, rate or 1) end

---@return number 枸杞池每跳伤害
function Weapons.ThermosPoolDamage(level,g)return Scaling.Growth(g,8,pick(BY_ID.thermos,"poolDamage",level))end

function Weapons.PaperclipDamage(level,g)return Scaling.Growth(g,13.5,pick(BY_ID.paperclip,"damage",level))end
function Weapons.PaperclipPierce(level,g)return Scaling.Growth(g,0,pick(BY_ID.paperclip,"pierce",level))end
function Weapons.PaperclipCooldown(rate) return 0.374 / math.max(0.2, rate or 1) end

function Weapons.PieDamage(level,g)return Scaling.Growth(g,52,pick(BY_ID.pie,"damage",level))end
function Weapons.PiePoolDamage(level,g)return Scaling.Growth(g,6,pick(BY_ID.pie,"poolDamage",level))end
---@return number 爆炸半径：56 + 5*L
function Weapons.PieExplodeRadius(level,g)return Scaling.Growth(g,61,56+5*clampLevel(level))end
---@return number 饼池半径：70 + 8*L
function Weapons.PiePoolRadius(level,g)return Scaling.Growth(g,78,70+8*clampLevel(level))end
---@return number 冷却：2.05 / (1 + 0.08*L)
function Weapons.PieCooldown(level,g)return 2.05/Scaling.Growth(g,1.08,1+.08*clampLevel(level))end
---@return number 射程：夹在 60..300
function Weapons.PieRange(distance)
    if distance < 60 then return 60 end
    if distance > 300 then return 300 end
    return distance
end

return Weapons
