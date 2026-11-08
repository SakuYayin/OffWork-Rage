-- 《下班！别拦我》：16 条通用 BUFF（S2 减半口径）。
-- 设计依据：docs/design/02-weapons-buffs-ults.md §6.2 B01–B32；07-halved-plan.md §2.6 只保留 16 条。
--
-- 【与设计文档的唯一一处偏离，必须记录】
-- B17 phaseWalk（移动无视敌人碰撞）在本项目里是**空效果**：Game.Update 的玩家位移只调
-- Move(g, p, ...)，而 Move 只查 Navigation 的墙体障碍，玩家本来就不会被敌人挡住。
-- 保留它等于发一张没用的卡，因此换成 B19 magnetPlus（拾取范围 +70/层，common）。
-- 其余 15 条与文档逐字一致，数值见下。要恢复 phaseWalk 必须先给玩家加敌人碰撞。
--
-- 【icon 硬约束】每条 icon 必须是 InterfaceIcons.buff 图集的 12 帧之一
-- （stapler/coffee/damage/speed/attack/range/magnet/health/regen/armor/crit/rage）。
-- UISkin.lua 的 Skin.Icon 内部是 assert(d.frames[id])，写错字面量会让 HUD 直接崩。
--
-- 【不 require("Game")】Game.lua 在头部 require 本模块，反向 require 会成环。
-- 需要真正的伤害结算时走 package.loaded["Game"] 惰性取（Endless.lua 同款写法）。
--
-- 【状态放哪】等级存 g.buffs[id]；其他计时器一律放 g.buffState[id]，别往 g 上撒散字段。
local Buffs = {}
local Scaling=require("HeroScaling")

local function Game() return package.loaded["Game"] end

local function state(g, id)
    g.buffState = g.buffState or {}
    local s = g.buffState[id]
    if not s then s = {}; g.buffState[id] = s end
    return s
end

-- 稀有度只影响抽卡权重：common 100 / rare 40 / epic 12（见 Game.RollChoices）。
Buffs.LIST = {
    {
        id = "critDamage", title = "毒舌暴击", tag = "暴击强化", color = "gold",
        desc = "暴击伤害从 1.8 倍提升到 2.15 倍。", rarity = "rare", maxLevel = 2, icon = "crit",
    },
    {
        id = "armorBreak", title = "拆穿画皮", tag = "破甲", color = "pink",
        desc = "命中使目标受伤 +2，持续 4 秒，最多叠 3 层。", rarity = "common", maxLevel = 3, icon = "damage",
    },
    {
        id = "execute", title = "优化名单", tag = "处决", color = "gold",
        desc = "对生命低于 18% 的目标造成 2.2 倍伤害。", rarity = "epic", maxLevel = 1, icon = "crit",
    },
    {
        id = "elemental", title = "情绪污染", tag = "持续伤害", color = "purple",
        desc = "命中附加 3 秒灼烧，每秒造成本次伤害的 8%。", rarity = "epic", maxLevel = 1, icon = "damage",
    },
    {
        id = "haste", title = "手速惊人", tag = "攻速强化", color = "teal",
        desc = "全部武器动作速度 +12%。", rarity = "rare", maxLevel = 3, icon = "attack",
    },
    {
        id = "multishot", title = "群发邮件", tag = "弹道强化", color = "pink",
        desc = "每 4 次远程攻击额外发射 1 发。", rarity = "epic", maxLevel = 1, icon = "range",
    },
    {
        id = "shield", title = "带薪发呆", tag = "护盾", color = "teal",
        desc = "每 12 秒获得 1 层护盾，抵挡一次完整伤害。", rarity = "epic", maxLevel = 2, icon = "armor",
    },
    {
        id = "lifesteal", title = "吸同事的血", tag = "吸血", color = "pink",
        desc = "造成伤害的 3% 转化为生命。", rarity = "rare", maxLevel = 2, icon = "health",
    },
    {
        id = "lastStand", title = "困兽之斗", tag = "绝境", color = "pink",
        desc = "生命低于 25% 时减伤 40%、攻速 +20%。", rarity = "epic", maxLevel = 1, icon = "health",
    },
    {
        id = "dash", title = "闪人", tag = "位移", color = "teal",
        desc = "按 Z 瞬步，0.18 秒无敌，冷却 4 秒。", rarity = "epic", maxLevel = 2, icon = "speed",
    },
    {
        id = "magnetPlus", title = "摸鱼大师", tag = "拾取强化", color = "teal",
        desc = "经验拾取范围 +70。", rarity = "common", maxLevel = 2, icon = "magnet",
    },
    {
        id = "rageGain", title = "越想越气", tag = "怒气", color = "pink",
        desc = "怒气获取 +30%。", rarity = "rare", maxLevel = 2, icon = "rage",
    },
    {
        id = "ultPower", title = "爆发预演", tag = "大招强化", color = "gold",
        desc = "大招范围 +20%，伤害 +20%（女主只加范围）。", rarity = "epic", maxLevel = 2, icon = "rage",
    },
    {
        id = "coinGain", title = "报销高手", tag = "经济", color = "gold",
        desc = "获得金币 +35%。", rarity = "common", maxLevel = 2, icon = "coffee",
    },
    {
        id = "reroll", title = "重开一版", tag = "抽卡", color = "purple",
        desc = "每次升级可重掷一次选项。", rarity = "rare", maxLevel = 2, icon = "stapler",
    },
    {
        id = "chain", title = "连坐制度", tag = "连锁", color = "purple",
        desc = "命中时有 25% 几率弹向附近另一名敌人，造成 50% 伤害。", rarity = "epic", maxLevel = 1, icon = "attack",
    },
}

local HERO_BUFFS={
 {id="folderReinforced",hero="intern",title="钛合金档案夹",tag="实习生专属",desc="每层文件夹重击伤害+22.5%，范围半径+10.8。",rarity="rare",maxLevel=3,icon="folderReinforced",color="gold"},
 {id="internProtection",hero="intern",title="实习生保护期",tag="实习生专属",desc="每层护盾上限+27、基础免伤+5.4%，获得时恢复27护盾。",rarity="rare",maxLevel=3,icon="internProtection",color="teal"},
 {id="internTempo",hero="intern",title="厚积薄发",tag="实习生专属",desc="每层文件夹攻击频率+10.8%。",rarity="common",maxLevel=3,icon="internTempo",color="purple"},
 {id="parallelThreads",hero="programmer",title="并行线程",tag="程序员专属",desc="每层每次额外发射1个二进制弹。",rarity="epic",maxLevel=2,icon="parallelThreads",color="teal"},
 {id="cacheWarmup",hero="programmer",title="缓存预热",tag="程序员专属",desc="每层二进制发射频率+10%，最高每秒6.25轮。",rarity="common",maxLevel=3,icon="cacheWarmup",color="purple"},
 {id="codeExploit",hero="programmer",title="漏洞注入",tag="程序员专属",desc="二进制自带1次穿透；每层基础伤害+3、穿透+1。",rarity="rare",maxLevel=3,icon="codeExploit",color="pink"},
 {id="fufuSnack",hero="fufu",title="加餐时间",tag="符符专属",desc="每层糕点充能速度+12%，每格最低8秒。",rarity="rare",maxLevel=3,icon="fufuSnack",color="gold"},
 {id="fufuCheckup",hero="fufu",title="毛孩子体检",tag="符符专属",desc="每层伙伴最大生命+20%，现有生命按比例变化。",rarity="common",maxLevel=3,icon="fufuCheckup",color="teal"},
 {id="fufuClaws",hero="fufu",title="爪牙保养",tag="符符专属",desc="每层输出伙伴伤害+15%，丹旺旺仍不造成攻击伤害。",rarity="rare",maxLevel=3,icon="fufuClaws",color="pink"},
 {id="fufuMaple",hero="fufu",title="枫叶抓痕",tag="符符专属",desc="每层枫叶小猫每层流血每秒伤害+2。",rarity="rare",maxLevel=3,icon="fufuMaple",color="pink"},
 {id="fufuWater",hero="fufu",title="活水饮水机",tag="符符专属",desc="每层潮湿持续+1秒，水流伤害+10%。",rarity="common",maxLevel=3,icon="fufuWater",color="teal"},
 {id="fufuProtection",hero="fufu",title="守护小保镖",tag="符符专属",desc="每层丹旺旺生命+15%、代受减伤+5%、反伤+5%，最多35%减伤、45%反伤。",rarity="rare",maxLevel=3,icon="fufuProtection",color="teal"},
 {id="fufuTeething",hero="fufu",title="双倍磨牙棒",tag="符符专属",desc="每层普通猫猫和狗狗伤害同时+15%，狗单次伤害始终为猫2倍。",rarity="rare",maxLevel=3,icon="fufuTeething",color="gold"},
 {id="fufuWaterproof",hero="fufu",title="防水接线板",tag="符符专属",desc="每层通电灯泡概率+5个百分点，从普通概率扣除，最多35%。",rarity="rare",maxLevel=3,icon="fufuWaterproof",color="teal"},
 {id="fufuLink",hero="fufu",title="串联电路",tag="符符专属",desc="每层通电连锁次级目标+1，最多4个；不回跳、不递归。",rarity="epic",maxLevel=2,icon="fufuLink",color="purple"},
 {id="fufuBlink",hero="fufu",title="眨眼别怕",tag="符符专属",desc="每层闪光灯泡概率+5个百分点，最多20%；Boss硬直仍为0.2秒。",rarity="rare",maxLevel=2,icon="fufuBlink",color="gold"},
 {id="fufuBlanket",hero="fufu",title="回家小毯子",tag="符符专属",desc="每层清房时伙伴回复最大生命10%，受当前波治疗衰减影响。",rarity="common",maxLevel=2,icon="fufuBlanket",color="teal"},
 {id="fufuDuty",hero="fufu",title="值班小闹钟",tag="符符专属",desc="每层每格糕点充能完成时恢复5护盾，最多15护盾。",rarity="epic",maxLevel=2,icon="fufuDuty",color="purple"},
}
for _,def in ipairs(HERO_BUFFS)do Buffs.LIST[#Buffs.LIST+1]=def end
local BY_ID = {}
for _, def in ipairs(Buffs.LIST) do BY_ID[def.id] = def end

function Buffs.Get(id) return BY_ID[id] end

---@return integer 0 表示未持有
function Buffs.Level(g, id) return (g.buffs and g.buffs[id]) or 0 end
Buffs.Count = Buffs.Level
function Buffs.Scale(g,id)
 local def=BY_ID[id]
 return def and def.hero=="intern"and Scaling.Exclusive(g)or Scaling.Generic(g)
end
function Buffs.EffectLevel(g,id)return Buffs.Level(g,id)*Buffs.Scale(g,id)end
local INTERN_DESCS={
 critDamage="每层暴击倍率额外+0.175，基础倍率1.8不变。",
 armorBreak="命中使目标受伤+1，持续4秒，最多叠3层。",
 execute="对生命低于18%的目标造成1.6倍伤害。",
 elemental="命中附加3秒灼烧，每秒造成本次伤害的4%。",
 haste="每层全部武器动作速度+6%。",
 multishot="每8次远程发射额外发射1枚弹体。",
 shield="每12秒获得1层护盾，消耗时使该次伤害减半。",
 lifesteal="每层将造成伤害的1.5%转化为生命。",
 lastStand="生命低于25%时减伤20%、攻速+10%。",
 dash="Z瞬步并无敌0.09秒，冷却4秒；2级冷却3.6秒。",
 magnetPlus="每层经验拾取范围+35。",
 rageGain="每层怒气获取+15%。",
 ultPower="每层大招范围+10%、伤害+10%。",
 coinGain="每层获得金币+17.5%，不足1币的增益会累计。",
 reroll="每层每次升级获得0.5次重掷，半次额度保留到下次升级。",
 chain="命中时有25%几率连锁，首跳造成25%伤害，最多2跳。",
}
function Buffs.Description(g,def)
 if g.heroId=="intern"and not def.hero then return (INTERN_DESCS[def.id]or def.desc).."（许宁：通用增益效果50%。）"end
 return def.desc
end
function Buffs.RerollGrant(g)return Scaling.Count(g,"reroll",Buffs.EffectLevel(g,"reroll"))end
function Buffs.ExtraProjectiles(g)
 if Buffs.Level(g,"multishot")<=0 then return 0 end
 local s=state(g,"multishot");s.shots=(s.shots or 0)+1
 if s.shots%4==0 then return Scaling.Count(g,"multishot",Buffs.Scale(g,"multishot"))end
 return 0
end

---@return table[] { id, level, def }
function Buffs.Active(g)
    local out = {}
    if not g.buffs then return out end
    for _, def in ipairs(Buffs.LIST) do
        local level = g.buffs[def.id] or 0
        if level > 0 then out[#out + 1] = { id = def.id, level = level, def = def } end
    end
    return out
end

---拿一层。返回新等级；同时把「拿到那一刻」的一次性效果做掉（目前只有护盾要初始化计时）。
function Buffs.Apply(g, id)
    local def=Buffs.Get(id)
    if not def or(def.hero and def.hero~=g.heroId)then return 0 end
    g.buffs = g.buffs or {}
    local previous=g.buffs[id]or 0
    local level = math.min(def.maxLevel or 1,previous + 1)
    if level==previous then return level end
    g.buffs[id] = level
    if id == "magnetPlus" then
        g.magnet = (g.magnet or 66) + 70*Buffs.Scale(g,id)
    elseif id == "shield" then
        state(g, id).timer = 0
    elseif id=="internProtection"then
        g.shieldMax=(g.hero and g.hero.shield or 100)+30*Buffs.EffectLevel(g,id)
        g.shield=math.min(g.shieldMax,(g.shield or 0)+30*Buffs.Scale(g,id))
    end
    local fufu=package.loaded["FufuCombat"]
    if fufu and def.hero=="fufu"then fufu.OnBuff(g,id)end
    return level
end

-- ---------------------------------------------------------------- 查询
---@return number 暴击倍率（基础 1.8）
function Buffs.CritMul(g)
    local level = Buffs.EffectLevel(g, "critDamage")
    if level <= 0 then return 1.8 end
    return 1.8 + 0.35 * level
end

---@return number 动作速度倍率（>1 更快）
function Buffs.AttackSpeedMul(g)
    local mul = 1 + 0.12 * Buffs.EffectLevel(g, "haste")
    local p = g.player
    if p and Buffs.Level(g, "lastStand") > 0 and p.maxHp > 0 and p.hp / p.maxHp < 0.25 then
        mul = mul * (1+.20*Buffs.Scale(g,"lastStand"))
    end
    return mul
end

---@return number 受到伤害的倍率（<1 表示减伤）
function Buffs.DamageTakenMul(g)
    local p = g.player
    if p and Buffs.Level(g, "lastStand") > 0 and p.maxHp > 0 and p.hp / p.maxHp < 0.25 then
        return 1-.40*Buffs.Scale(g,"lastStand")
    end
    return 1
end

---@return number 处决倍率
function Buffs.ExecuteMul(g, e)
    if Buffs.Level(g, "execute") <= 0 then return 1 end
    if not e or not e.maxHp or e.maxHp <= 0 then return 1 end
    if e.hp / e.maxHp < 0.18 then return 1+1.2*Buffs.Scale(g,"execute") end
    return 1
end

---@return number 怒气获取倍率
function Buffs.RageMul(g) return 1 + 0.30 * Buffs.EffectLevel(g, "rageGain") end

---@return number 金币获取倍率
function Buffs.CoinMul(g) return 1 + 0.35 * Buffs.EffectLevel(g, "coinGain") end
function Buffs.CoinReward(g,base)
 if g.heroId=="intern"then return base+Scaling.Count(g,"coinGain",base*(Buffs.CoinMul(g)-1))end
 return math.floor(base*Buffs.CoinMul(g)+.5)
end

---@return number 大招威力（女主只吃范围，不吃这个倍率）
function Buffs.UltPower(g) return 1 + 0.20 * Buffs.EffectLevel(g, "ultPower") end

---@return number 大招范围倍率（男女都吃）
function Buffs.UltRadius(g) return 1 + 0.20 * Buffs.EffectLevel(g, "ultPower") end

---@return integer 目标身上的破甲层数（0..3）
function Buffs.ArmorBreak(g, e) return (e and e.armorBreak) or 0 end

-- ---------------------------------------------------------------- 护盾
---@return integer
function Buffs.ShieldCount(g) return state(g, "shield").charges or 0 end

---@return boolean 真表示这次伤害被护盾吃掉
function Buffs.ConsumeShield(g)
    local s = state(g, "shield")
    if (s.charges or 0) > 0 then
        s.charges = s.charges - 1
        s.timer = 12
        return true
    end
    return false
end

-- ---------------------------------------------------------------- 冲刺
---@return boolean
function Buffs.DashReady(g)
    return Buffs.Level(g, "dash") > 0 and (state(g, "dash").cooldown or 0) <= 0
end

---瞬步：0.18s 无敌 + 沿朝向的高速位移。位移本身由 Game.Update 读 player.dashTimer 结算。
function Buffs.StartDash(g, nx, ny)
    if not Buffs.DashReady(g) then return false end
    local p = g.player
    local length = math.sqrt(nx * nx + ny * ny)
    if length < 0.001 then nx, ny, length = p.faceX or 1, p.faceY or 0, 1 end
    p.dashTimer = 0.18*Buffs.Scale(g,"dash")
    p.dashDirX, p.dashDirY = nx / length, ny / length
    p.invuln = math.max(p.invuln or 0,p.dashTimer)
    state(g, "dash").cooldown = math.max(1.6, 4.0 - 0.8 * (Buffs.Level(g, "dash") - 1)*Buffs.Scale(g,"dash"))
    return true
end

---闪人的**只读**状态快照，给 HUD/UI 用（不建 state、不推进计时，避免 UI 刷新影响战斗计时）。
---@param g table
---@return table { level:number, ready:boolean, cooldown:number, maxCooldown:number, active:boolean }
function Buffs.DashState(g)
    local level = Buffs.Level(g, "dash")
    local cooldown = 0
    local active = false
    if g and g.buffState and g.buffState["dash"] then
        cooldown = math.max(0, g.buffState["dash"].cooldown or 0)
    end
    if g and g.player and (g.player.dashTimer or 0) > 0 then active = true end
    local maxCooldown = math.max(1.6, 4.0 - 0.8 * math.max(0, level - 1) * Buffs.Scale(g, "dash"))
    return {
        level = level,
        ready = level > 0 and cooldown <= 0,
        cooldown = cooldown,
        maxCooldown = maxCooldown,
        active = active,
    }
end

-- ---------------------------------------------------------------- 命中回调
local chaining = false

---命中后的 BUFF 侧结算。调用点在 Game.Hit 里，amount 是**已经算完所有乘区**的最终伤害。
---@param g table
---@param e table 敌人
---@param amount number 本次实际造成的伤害
---@param crit boolean
function Buffs.OnHit(g, e, amount, crit)
    if not e or e.hp < 0 and amount <= 0 then return end
    -- B03 破甲：叠层并刷新计时，当前这一下不吃自己新加的层。
    local armorLevel = Buffs.Level(g, "armorBreak")
    if armorLevel > 0 then
        e.armorBreak = math.min(3, (e.armorBreak or 0) + 1)
        e.armorBreakTimer = 4.0
    end
    -- B05 情绪污染：同目标不叠层，只刷新持续时间并取较高 DPS。
    if Buffs.Level(g, "elemental") > 0 then
        local dps = 0.08 * amount*Buffs.Scale(g,"elemental")
        if (e.dotDps or 0) < dps then e.dotDps = dps end
        e.dotTimer = 3.0
        e.dotTick = e.dotTick or 0
    end
    -- B13 吸血
    local lifesteal = Buffs.Level(g, "lifesteal")
    if lifesteal > 0 and amount > 0 then
        local heal = amount * 0.03 * lifesteal*Buffs.Scale(g,"lifesteal")
        local p = g.player
        if p then local G=Game();if G and G.Heal then G.Heal(g,heal)else p.hp=math.min(p.maxHp,p.hp+heal)end end
    end
    -- B31 连坐：25% 弹向 120 内另一名敌人，最多 2 跳。chaining 防递归。
    if Buffs.Level(g, "chain") > 0 and not chaining and amount > 0 and math.random() < 0.25 then
        local G = Game()
        if G and G.TrueHit then
            chaining = true
            local source, hops = e, 0
            local power = amount * 0.5*Buffs.Scale(g,"chain")
            while hops < 2 and power >= 1 do
                local best, bestDistance = nil, 120
                for _, other in ipairs(g.enemies) do
                    if other ~= source and other.hp > 0 and other ~= e then
                        local dx, dy = other.x - source.x, other.y - source.y
                        local d = math.sqrt(dx * dx + dy * dy)
                        if d < bestDistance then best, bestDistance = other, d end
                    end
                end
                if not best then break end
                G.TrueHit(g, best, power, 0, 0, 0)
                source, power, hops = best, power * 0.5, hops + 1
            end
            chaining = false
        end
    end
end

-- ---------------------------------------------------------------- 每帧
---护盾充能、冲刺冷却。由 Game.Update 在实体逻辑之前调一次。
function Buffs.Update(g, dt)
    local shieldLevel = Buffs.Level(g, "shield")
    if shieldLevel > 0 then
        local s = state(g, "shield")
        s.charges = s.charges or 0
        if s.charges < shieldLevel then
            s.timer = (s.timer or 0) - dt
            if s.timer <= 0 then
                s.charges = s.charges + 1
                s.timer = 12
            end
        end
    end
    local d = state(g, "dash")
    if (d.cooldown or 0) > 0 then d.cooldown = math.max(0, d.cooldown - dt) end
    -- 玩家瞬步位移本身在 Game.Update 的移动段结算，这里只递减计时。
    local p = g.player
    if p and (p.dashTimer or 0) > 0 then p.dashTimer = math.max(0, p.dashTimer - dt) end
end

---敌人身上的 BUFF 状态：破甲计时、灼烧跳伤。由 Game.UpdateEnemies 每帧调一次。
function Buffs.UpdateEnemies(g, dt)
    local G = Game()
    for _, e in ipairs(g.enemies) do
        if e.hp > 0 then
            if (e.armorBreak or 0) > 0 then
                e.armorBreakTimer = (e.armorBreakTimer or 0) - dt
                if e.armorBreakTimer <= 0 then
                    e.armorBreak = nil
                    e.armorBreakTimer = nil
                end
            end
            if (e.dotTimer or 0) > 0 then
                e.dotTimer = e.dotTimer - dt
                e.dotTick = (e.dotTick or 0) - dt
                if e.dotTick <= 0 then
                    e.dotTick = 0.5
                    if G and G.TrueHit then G.TrueHit(g, e, (e.dotDps or 0) * 0.5, 0, 0, 0) end
                end
                if e.dotTimer <= 0 then e.dotDps, e.dotTimer = nil, nil end
            end
            -- 女主大招标记：命中计数消耗完就清掉
            if (e.markHits or 0) > 0 then
                e.markTimer = (e.markTimer or 0) - dt
                if e.markTimer <= 0 then e.markHits, e.markTimer = nil, nil end
            end
        end
    end
end

-- 抽卡时要排除已满级的 BUFF
function Buffs.CanLevel(g, def)
    return Buffs.Level(g, def.id) < (def.maxLevel or 3)
end

return Buffs
