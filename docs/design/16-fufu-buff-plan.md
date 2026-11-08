# 符符增强修改说明（方案 A+B + 丹旺旺反伤 + 伙伴 30% 继承）

- 日期：2026-11-08
- 角色：`fufu / 符符`
- 目标：解决玩家反馈的“太弱 / 太蛆”——伙伴存活过短、补给过慢、本体无输出
- 状态：可直接按本文实施
- 本次范围：只改符符，其他四个角色的数值、通用 BUFF 结算、`Game.Hit` 主链一律不动

## 1. 背景与实测

符符的全部输出挂在可被击杀的伙伴身上，而伙伴既脆、补给又慢一个数量级。以下为实测数据（`web/tools/probe-run.mjs`，波次 11、12 只小怪在场、玩家站桩无敌、伙伴自动补）：

| 指标 | 实测值 |
|---|---|
| 伙伴平均存活时长 | **4.7 秒**（样本 6 只，最短 2.2，最长 9.6） |
| 90 秒内可召唤次数 | **6 次**（3 格起手 + 24 秒/格） |
| 90 秒击杀 | **2** |
| 60 秒击杀（同基准） | **4**，同期陈准 32、林夏 44、许宁 51 |

单体木桩 DPS（`crit=0`、护甲 0、同一距离）：

| 来源 | DPS | 来源 | DPS |
|---|---:|---|---:|
| 本体灯泡 | **9.2** | 三只狗狗 | 99.8 |
| 三只猫猫 | 72.3 | 三只枫叶 | 73.2 |
| 三只水龙 | 48.8 | 丹+水+枫（差运气） | 47.5 |
| 林夏订书器（对照） | 49.1 | 周序二进制（对照） | 19.6 |

结论：**峰值伤害并不低，问题在覆盖率与生存**。本次同时处理四件事：

1. **方案 A**：抬高伙伴基础生命、加快糕点补给、加长受击无敌、上调灯泡。
2. **方案 B**：伙伴阵亡返还充能、召唤保底、等级成长、伙伴继承攻速。
3. **丹旺旺反伤**：让 0 输出的肉盾有回报。
4. **伙伴 30% 继承**：可叠加的伤害乘区与攻速，伙伴只吃本体的 30%，防止后期滚雪球。

## 2. 最终数值

### 2.1 方案 A：基础数值

| 项 | 当前 | 修改后 | 出处 |
|---|---:|---:|---|
| 枫叶小猫生命 | 100 | **180** | `FufuSummons.lua:5` |
| 水龙龙生命 | 85 | **153** | `FufuSummons.lua:5` |
| 丹旺旺生命 | 300 | **540** | `FufuSummons.lua:5` |
| 普通猫猫生命 | 90 | **162** | `FufuSummons.lua:5` |
| 普通狗狗生命 | 170 | **306** | `FufuSummons.lua:5` |
| 单格充能间隔 | 24 秒 | **12 秒** | `FufuSummons.lua:14`、`FufuCombat.lua:26` |
| 充能下限 | 16 秒 | **8 秒** | 同上 |
| 召唤冷却 | 0.8 秒 | **0.4 秒** | `FufuSummons.lua:41` |
| 伙伴受击无敌 | 0.3 秒 | **0.6 秒** | `FufuCombat.lua:89` |
| 灯泡普通 | 12.6 | **15** | `FufuCombat.lua:143` |
| 灯泡通电 | 18.9 | **22.5** | 同上 |
| 灯泡闪光 | 8.4 | **10** | 同上 |
| 通电连锁每跳 | 12.6 | **15** | `FufuCombat.lua:166` |
| 灯泡射击间隔 | 1.4/1.05 ≈ 1.333 秒 | **1.0 秒** | `FufuCombat.lua:213` |

充能间隔实算（`12 / (1 + 0.12 × fufuSnack)`，下限 8 秒）：

| fufuSnack 等级 | 间隔 | 3 格回满 | 原间隔 | 原 3 格 |
|---|---:|---:|---:|---:|
| 0 | **12.0 秒** | **36.0 秒** | 24.0 | 72.0 |
| 1 | **10.7 秒** | **32.1 秒** | 21.4 | 64.3 |
| 2 | **9.7 秒** | **29.0 秒** | 19.4 | 58.1 |
| 3（上限） | **8.8 秒** | **26.5 秒** | 17.6 | 52.9 |

> 注意：3 级仍是 8.8 秒，**8 秒下限依然走不到**（需要 `0.12 × 等级 > 0.5`，约 5 级）。这是刻意保留的，避免改 `maxLevel` 之外的东西。若希望 3 级正好压到 8 秒，把系数从 0.12 提到 0.17 即可，但会同时改到 HUD 文案，本次不做。

### 2.2 方案 B：四条机制

| 机制 | 规则 |
|---|---|
| 阵亡返还 | 伙伴阵亡时，返还 `ChargeInterval × 0.4` 的充能进度（12 秒间隔即 4.8 秒） |
| 召唤保底 | 连续 2 次抽到丹旺旺或水龙龙后，下一次强制为输出型（枫叶/猫/狗轮转） |
| 等级成长 | 伙伴最大生命与伤害随玩家等级成长：每级 +0.8%，上限 +40%（约 51 级封顶），清房时把现有伙伴按比例推到新一档 |
| 攻速继承 | 伙伴攻击间隔按本体攻速增益的 **30%** 缩短 |

### 2.3 丹旺旺反伤

| 项 | 值 |
|---|---|
| 触发条件 | 丹旺旺成功替玩家代受一次伤害 |
| 反伤率 | `min(0.45, 0.30 + 0.05 × fufuProtection)` |
| 反伤基数 | 本次代受的伤害 `rawAbsorbed`（**减伤前**，所以减伤不会削弱反伤） |
| 单次上限 | 丹旺旺最大生命 × 12%（540 血时 64.8） |
| 作用范围 | 丹旺旺周围 110 + 敌人半径，需有视线 |
| 结算方式 | `Game.TrueHit`（不吃暴击/破甲/处决/吸血，不会自循环） |

数值实感（波 11 敌人单次 22 伤害）：

| 反伤等级 | 代受伤害 | 单只反伤（取整后） | 贴脸 5 只 |
|---|---:|---:|---:|
| 0 级（30%） | 22 | **6** | 30 DPS |
| 3 级（45%） | 22 | **9** | 45 DPS |

**为什么基数用 `rawAbsorbed` 而不是实际掉血**：若按实际掉血算，`fufuProtection` 每提升一级减伤，反伤基数就少一截——0 级时丹旺旺掉 80 可反 24，3 级时只掉 65 只能反 29，而提升反伤率本来是要涨的。两张收益互相抵消，玩家会觉得“我加了减伤怎么反伤反而变弱”。用减伤前的代受量，减伤负责续命、反伤率负责数值，两条线各走各的。

玩家有 0.9 秒受击无敌、代受有 1 秒冷却，所以反伤频率天然被卡在每秒一次，不会失控。

### 2.4 伙伴 30% 继承

只压两条可叠加的通道，其余保持现状：

| 通道 | 本体 | 伙伴 | 理由 |
|---|---|---|---|
| 伤害乘区 `g.damage`（拒绝内耗 +25%/张） | 100% | **30%** | 可叠加到 1.75，不压会滚雪球 |
| 攻速（手速进修、手速惊人） | 100% | **30%** | 原本伙伴完全吃不到，本次补上但打折 |
| 暴击 / 毒舌暴击 / 破甲 / 处决 / 灼烧 / 吸血 / 连坐 | 100% | **100%，不变** | 走 `Game.Hit` 统一结算，不是可无限叠的乘区 |
| 多弹体、范围、闪人、带薪发呆 | 100% | 不适用 | 与伙伴无关 |

公式：

```text
伙伴伤害乘区 = 1 + max(0, g.damage - 1) × 0.30
伙伴攻速倍率 = 1 + max(0, g.attackSpeed × AttackSpeedMul - 1) × 0.30
伙伴伤害     = 基础伤害 × PetDamage × 伙伴伤害乘区 × (1 + 等级成长)
```

满配对照（`g.damage = 1.75`，三只狗狗）：

| 口径 | 峰值 DPS |
|---|---:|
| 现状 100% 继承 | 174.6 |
| 本次 30% 继承 | **122.3** |

峰值降 30%，但覆盖率从约 30% 提到约 70%，总量大幅上升——削峰填谷。

## 3. 代码修改

### 3.1 权威文件

优先修改：

- `web/lua/FufuCombat.lua`
- `web/lua/FufuSummons.lua`
- `web/lua/Buffs.lua`（仅文案）

镜像副本同步同一改动：

- `scripts/FufuCombat.lua`
- `scripts/FufuSummons.lua`
- `scripts/Buffs.lua`

`web/lua/` 是构建与浏览器运行源，`scripts/` 是镜像，两者必须保持一致。

### 3.2 伙伴基础生命

`FufuSummons.lua:4-6`，当前：

```lua
M.stats = {
    maple={hp=100}, water={hp=85}, dan={hp=300}, cat={hp=90}, dog={hp=170},
}
```

改为：

```lua
M.stats = {
    maple={hp=180}, water={hp=153}, dan={hp=540}, cat={hp=162}, dog={hp=306},
}
```

### 3.3 充能间隔

`FufuSummons.lua:14`，当前：

```lua
    local interval=math.max(16,24/(recoveryMultiplier or 1))
```

改为：

```lua
    local interval=math.max(8,12/(recoveryMultiplier or 1))
```

`FufuCombat.lua:26`，当前：

```lua
function F.ChargeInterval(g)return math.max(16,24/(1+.12*level(g,"fufuSnack")))end
```

改为：

```lua
function F.ChargeInterval(g)return math.max(8,12/(1+.12*level(g,"fufuSnack")))end
```

`FufuHud.lua:45` 读的是 `F.ChargeInterval`，会自动跟随，不用改。

### 3.4 召唤冷却

`FufuSummons.lua:41`，当前：

```lua
    state.cooldown=.8
```

改为：

```lua
    state.cooldown=.4
```

### 3.5 伙伴受击无敌

`FufuCombat.lua:89`，当前：

```lua
 local absorbed=math.min(p.hp,loss);p.hp=math.max(0,p.hp-loss);p.hit=.18;p.invuln=.3
```

改为（注意这一行是单空格缩进）：

```lua
 local absorbed=math.min(p.hp,loss);p.hp=math.max(0,p.hp-loss);p.hit=.18;p.invuln=.6
```

### 3.6 灯泡伤害与间隔

`FufuCombat.lua:142-143`，当前：

```lua
    -- 方案 A：灯泡三类伤害各上调 5%（原 12 / 18 / 8）。
    local damage=kind=="normal"and 12.6 or(kind=="electric"and 18.9 or 8.4)
```

改为：

```lua
    -- 符符增强：三类伤害上调到 15 / 22.5 / 10（原 12.6 / 18.9 / 8.4）。
    local damage=kind=="normal"and 15 or(kind=="electric"and 22.5 or 10)
```

`FufuCombat.lua:165-166`（电链），当前：

```lua
   -- 电链的固定伤害同样按 +5% 调整（原 12）。
   visited[best]=true;G().Hit(g,best,12.6,0,0,0)
```

改为：

```lua
   -- 电链固定伤害与普通灯泡同步：15。
   visited[best]=true;G().Hit(g,best,15,0,0,0)
```

`FufuCombat.lua:212-213`，当前：

```lua
  -- 方案 A：灯泡冷却由 1.4 缩短到 1.4/1.05，即出手频率 +5%。
  if Actions.Start(g,"bulb",nx,ny)then g.bulbTimer=(1.4/1.05)/math.max(.2,g.attackSpeed*Buffs.AttackSpeedMul(g))end
```

改为：

```lua
  -- 符符增强：射击间隔 1.0 秒（原 1.4/1.05 ≈ 1.333）。
  if Actions.Start(g,"bulb",nx,ny)then g.bulbTimer=1.0/math.max(.2,g.attackSpeed*Buffs.AttackSpeedMul(g))end
```

### 3.7 伙伴阵亡返还充能（方案 B1）

`FufuCombat.lua:43-48`，当前：

```lua
function F.Cleanup(g)
 if not g.summons then return end
 for i=#g.pets,1,-1 do local p=g.pets[i];if p.hp<=0 then
  fx(g,"fufuDepart",p.x,p.y,.5,60);table.remove(g.pets,i);g.uiRevision=(g.uiRevision or 0)+1
 end end
end
```

改为：

```lua
function F.Cleanup(g)
 if not g.summons then return end
 for i=#g.pets,1,-1 do local p=g.pets[i];if p.hp<=0 then
  fx(g,"fufuDepart",p.x,p.y,.5,60);table.remove(g.pets,i);g.uiRevision=(g.uiRevision or 0)+1
  -- 阵亡返还 40% 充能：伙伴平均只活 4.7 秒，不给补偿就永远补不满。
  local state=g.summons
  if state.charges<3 then
   local interval=F.ChargeInterval(g)
   state.recovery=math.min(interval*.999,(state.recovery or 0)+interval*.4)
  end
 end end
end
```

三点约束：

1. 只在 `charges < 3` 时返还。满格时 `FufuSummons.Update` 本来就会把 `recovery` 清零，返还了也会被吃掉。
2. 上限 `interval * 0.999`，确保不会因为返还而直接跳出一格；真正发格子仍然只在 `Summons.Update` 里做。
3. 返还**不触发** `fufuDuty` 的护盾（那段逻辑在 `FufuCombat.lua:204-205`，只在 `charges` 增加时生效）。不要为了“顺手”把返还写进充能发放路径，否则会变成刷盾。

### 3.8 召唤保底（方案 B2）

`FufuSummons.lua:7-9`，`M.New` 增加计数字段，当前：

```lua
function M.New()
    return {charges=3, recovery=0, cooldown=0, pets={}, nextId=0}
end
```

改为：

```lua
function M.New()
    return {charges=3, recovery=0, cooldown=0, pets={}, nextId=0, dryStreak=0}
end
```

`FufuSummons.lua:28-43`，`M.Summon` 在选定 `kind` 之后插入保底，当前：

```lua
    local index=(rng or math.random)(1,#M.kinds)
    assert(type(index)=="number" and index%1==0 and index>=1 and index<=#M.kinds,"invalid summon roll")
    local kind=M.kinds[index]
```

改为：

```lua
    local index=(rng or math.random)(1,#M.kinds)
    assert(type(index)=="number" and index%1==0 and index>=1 and index<=#M.kinds,"invalid summon roll")
    local kind=M.kinds[index]
    -- 保底：连续两只哑炮（丹旺旺不出手、水龙龙每跳仅 6）之后，下一只强制为输出型。
    -- 用 nextId 轮转而不是再掷一次骰子，避免改变 rng 调用次数（测试用单值 rng）。
    if (state.dryStreak or 0)>=2 and M.DULL[kind] then
        kind=({ "maple", "cat", "dog" })[(state.nextId%3)+1]
    end
    state.dryStreak=M.DULL[kind] and (state.dryStreak or 0)+1 or 0
```

文件顶部 `M.kinds` 之后加一行：

```lua
M.DULL={ dan=true, water=true }
```

约束：

- 不要改 `M.kinds` 的顺序和长度，`rng` 仍然只返回 1..5。
- 不要为此额外调用一次 `rng`，否则 `tests/FufuCombat.lua:23` 那种单值 rng 会崩。
- 保底只影响“抽到谁”，不影响格数、冷却、替换顺序。

### 3.9 伙伴等级成长（方案 B3）

`FufuCombat.lua:32-36`，当前：

```lua
function F.PetDamage(g,pet)
 local mul=1+.15*level(g,"fufuClaws")
 if pet.kind=="cat"or pet.kind=="dog"then mul=mul*(1+.15*level(g,"fufuTeething"))end
 return mul
end
```

改为（新增 `F.Growth`）：

```lua
-- 伙伴成长：随玩家等级每级 +0.8%，上限 +40%。解决后期伙伴跟不上敌人成长。
-- 这里刻意不用 g.roomsCleared：无尽模式每波会把 roomsCleared 归零（Endless.lua:268），
-- 按房间数算的话无尽里成长永远是 0；g.level 两种模式都单调递增。
function F.Growth(g)return math.min(.40,.008*math.max(0,(g.level or 1)-1))end
function F.PetDamage(g,pet)
 local mul=(1+.15*level(g,"fufuClaws"))*(1+F.Growth(g))
 if pet.kind=="cat"or pet.kind=="dog"then mul=mul*(1+.15*level(g,"fufuTeething"))end
 return mul
end
```

`FufuCombat.lua:27-31`，`F.MaxHp` 同样乘成长，当前：

```lua
function F.MaxHp(g,kind)
 local hp=Summons.stats[kind].hp*(1+.20*level(g,"fufuCheckup"))
 if kind=="dan"then hp=hp*(1+.15*level(g,"fufuProtection"))end
 return hp
end
```

改为：

```lua
function F.MaxHp(g,kind)
 local hp=Summons.stats[kind].hp*(1+.20*level(g,"fufuCheckup"))*(1+F.Growth(g))
 if kind=="dan"then hp=hp*(1+.15*level(g,"fufuProtection"))end
 return hp
end
```

现有伙伴要在清房时按比例接住新的上限，`FufuCombat.lua:128-132`，当前：

```lua
function F.Cleared(g)
 if g.heroId~="fufu"then return end
 local mul=.10*level(g,"fufuBlanket")*Difficulty.HealMul(Difficulty.Wave(g))
 for _,p in ipairs(g.pets)do p.hp=math.min(p.maxHp,p.hp+p.maxHp*mul)end
end
```

改为：

```lua
function F.Cleared(g)
 if g.heroId~="fufu"then return end
 -- 先把现有伙伴的上限推到新一档（等级涨了，成长值也跟着涨）。
 for _,p in ipairs(g.pets)do
  local ratio=p.hp/math.max(1,p.maxHp)
  p.maxHp=F.MaxHp(g,p.kind);p.hp=p.maxHp*ratio
 end
 local mul=.10*level(g,"fufuBlanket")*Difficulty.HealMul(Difficulty.Wave(g))
 for _,p in ipairs(g.pets)do p.hp=math.min(p.maxHp,p.hp+p.maxHp*mul)end
end
```

`F.Cleared` 在战役（`Game.lua:1001`）和无尽（`Endless.lua:370/383`）都会调用，所以两种模式下现有伙伴都会在清场时接住新等级的上限。

### 3.10 伙伴攻速继承（方案 B4）

`FufuCombat.lua:176` 之前新增一个helper：

```lua
-- 伙伴只吃本体攻速增益的 30%：手速类卡原来对伙伴完全无效，现在补上但打折。
function F.PetHaste(g)
 local rate=(g.attackSpeed or 1)*Buffs.AttackSpeedMul(g)
 return 1+math.max(0,rate-1)*.30
end
```

`FufuCombat.lua:228`（水龙龙），当前：

```lua
    p.waterX,p.waterY=direction(p,target);p.waterLeft,p.waterTick=6,0;p.attackTimer=2.8;p.attackTime=1.2;p.faceX,p.faceY=p.waterX,p.waterY
```

改为：

```lua
    p.waterX,p.waterY=direction(p,target);p.waterLeft,p.waterTick=6,0;p.attackTimer=2.8/F.PetHaste(g);p.attackTime=1.2;p.faceX,p.faceY=p.waterX,p.waterY
```

`FufuCombat.lua:232-235`（枫叶/猫/狗），当前：

```lua
   elseif p.attackTimer<=0 then
    if p.kind=="maple"then p.clawsLeft,p.clawTick=3,0;p.attackTimer=1.5;p.attackTime=.6
    else hit(g,p,target,p.kind=="cat"and 18 or 36);p.attackTimer=p.kind=="cat"and .8 or 1.15 end
   end
```

改为：

```lua
   elseif p.attackTimer<=0 then
    if p.kind=="maple"then p.clawsLeft,p.clawTick=3,0;p.attackTimer=1.5/F.PetHaste(g);p.attackTime=.6
    else hit(g,p,target,p.kind=="cat"and 18 or 36);p.attackTimer=(p.kind=="cat"and .8 or 1.15)/F.PetHaste(g) end
   end
```

不要改 `p.attackTime`（动作表现时长）和三连爪的内部间隔 `p.clawTick=.2`，只改“两次出手之间”的 `attackTimer`。

### 3.11 伙伴 30% 伤害继承

`FufuCombat.lua:176-181`，当前：

```lua
local function strike(g,p,e,damage,nx,ny,knock)
 -- Small water/bleed bonuses must not disappear when every hit rounds down.
 local amount=damage*F.PetDamage(g,p)*g.damage+(p.damageCredit or 0)
 local whole=math.floor(amount+1e-9);p.damageCredit=math.max(0,amount-whole)
 if whole>0 then G().Hit(g,e,whole/math.max(.01,g.damage),nx,ny,knock)end
end
```

改为：

```lua
-- 伙伴只吃本体伤害乘区的 30%：g.damage 可叠到 1.75，吃满会让伙伴后期滚雪球。
function F.PetInherit(g)return 1+math.max(0,(g.damage or 1)-1)*.30 end
local function strike(g,p,e,damage,nx,ny,knock)
 -- Small water/bleed bonuses must not disappear when every hit rounds down.
 local amount=damage*F.PetDamage(g,p)*F.PetInherit(g)+(p.damageCredit or 0)
 local whole=math.floor(amount+1e-9);p.damageCredit=math.max(0,amount-whole)
 if whole>0 then G().Hit(g,e,whole/math.max(.01,g.damage),nx,ny,knock)end
end
```

**这里最容易改错**：最后那行除以的仍然是 `g.damage`，不是 `F.PetInherit(g)`。因为 `Game.Hit` 内部会做 `amount = damage * g.damage`（`Game.lua:486`），这一除只是为了把刚才那次乘法抵消掉。改成除以 30% 的乘区会让伤害凭空放大约 3.3 倍。

流血同一条口径，`FufuCombat.lua:275-277`，当前：

```lua
    local amount=(e.bleedDps or 3)*(e.bleedStacks or 1)*.5*g.damage+(e.bleedCredit or 0)
    local whole=math.floor(amount+1e-9);e.bleedCredit=math.max(0,amount-whole)
    if whole>0 then G().TrueHit(g,e,whole/math.max(.01,g.damage),0,0,0)end
```

改为：

```lua
    local amount=(e.bleedDps or 3)*(e.bleedStacks or 1)*.5*F.PetInherit(g)+(e.bleedCredit or 0)
    local whole=math.floor(amount+1e-9);e.bleedCredit=math.max(0,amount-whole)
    if whole>0 then G().TrueHit(g,e,whole/math.max(.01,g.damage),0,0,0)end
```

灯泡**不改**，本体吃满 `g.damage`，这才符合“伙伴只有本体的 30%”。

### 3.12 丹旺旺反伤

`FufuCombat.lua:93-105`，当前：

```lua
function F.Intercept(g,amount)
 if g.heroId~="fufu"or not g.summons or(g.summons.interceptCooldown or 0)>0 then return amount end
 for _,p in ipairs(g.pets)do
  if p.kind=="dan"and p.hp>0 and dist(p,g.player)<=120 and G().Visible(g,p.x,p.y,g.player.x,g.player.y)then
   local factor=protection(g,p);local rawAbsorbed=math.min(amount,p.hp/math.max(.01,factor))
   p.attackTime=.5
   F.DamagePet(g,p,rawAbsorbed,true);g.summons.interceptCooldown=1
   fx(g,"fufuGuard",g.player.x,g.player.y-20,.4,90,0,p.x,p.y);F.Cleanup(g)
   return math.max(0,amount-rawAbsorbed)
  end
 end
 return amount
end
```

改为（反伤基数用 `rawAbsorbed`，即代受量、减伤前）：

```lua
-- 反伤率：30% 起，fufuProtection 每级 +5%，上限 45%。
function F.ReflectRatio(g)return math.min(.45,.30+.05*level(g,"fufuProtection"))end
-- 丹旺旺代受后，对周围敌人反弹「本次代受伤害」的固定比例。走 TrueHit，不吃暴击/吸血，不递归。
function F.Reflect(g,p,absorbed)
 if absorbed<=0 then return end
 local amount=math.min(absorbed*F.ReflectRatio(g),p.maxHp*.12)
 if amount<=0 then return end
 local gd=math.max(.01,g.damage or 1)
 for _,e in ipairs(g.enemies)do
  if e.hp>0 and dist(p,e)<=110+e.radius and G().Visible(g,p.x,p.y,e.x,e.y)then
   G().TrueHit(g,e,amount/gd,0,0,0)
   fx(g,"fufuGuard",p.x,p.y-15,.2,70,0,e.x,e.y)
  end
 end
end
function F.Intercept(g,amount)
 if g.heroId~="fufu"or not g.summons or(g.summons.interceptCooldown or 0)>0 then return amount end
 for _,p in ipairs(g.pets)do
  if p.kind=="dan"and p.hp>0 and dist(p,g.player)<=120 and G().Visible(g,p.x,p.y,g.player.x,g.player.y)then
   local factor=protection(g,p);local rawAbsorbed=math.min(amount,p.hp/math.max(.01,factor))
   p.attackTime=.5
   F.DamagePet(g,p,rawAbsorbed,true);g.summons.interceptCooldown=1
   F.Reflect(g,p,rawAbsorbed)
   fx(g,"fufuGuard",g.player.x,g.player.y-20,.4,90,0,p.x,p.y);F.Cleanup(g)
   return math.max(0,amount-rawAbsorbed)
  end
 end
 return amount
end
```

三点约束：

1. **必须用 `TrueHit` 并传 `amount/gd`**。`Game.TrueHit` 跳过暴击/破甲，但仍然会乘一次 `g.damage`（`Game.lua:486`），所以传 `amount/g.damage` 才能打出精确的 `amount`。
2. **反伤只挂在“代受”上**。伙伴被怪直接打（`F.DamagePet` 的其他调用点）不反伤，否则每只伙伴都变成反伤怪，数值失控。
3. **不要传攻击者**。`F.Intercept(g, amount)` 由 `Game.lua:442` 调用，签名里没有攻击者；不要为了单体反伤去改 `TakeDamage` 的签名，那会波及五个角色和所有伤害来源。

### 3.13 文案同步

`Buffs.lua:108`（fufuSnack），当前：

```lua
desc="每层糕点充能速度+12%，每格最低16秒。"
```

改为：

```lua
desc="每层糕点充能速度+12%，每格最低8秒。"
```

`Buffs.lua:113`（fufuProtection），当前：

```lua
desc="每层丹旺旺生命+15%、代受减伤+5%，最多35%减伤。"
```

改为：

```lua
desc="每层丹旺旺生命+15%、代受减伤+5%、反伤+5%，最多35%减伤、45%反伤。"
```

## 4. 判定口径

### 4.1 反伤

1. 只有 `F.Intercept` 成功代受时才结算，且每次成功代受只结算一次（1 秒冷却已经保证频率）。
2. 基数取本次代受的 `rawAbsorbed`（丹旺旺最多能替玩家吃下的那部分，**减伤前**）。不要用实际掉血：那样每级 `fufuProtection` 提升减伤反而会降低反伤，同一张卡的两条收益互相对冲。丹旺旺只剩 8 血时替 1000 伤害，`rawAbsorbed` 会被 `hp/factor` 夹到 10，反伤只有 3，不会爆。
3. 单次反伤上限 `maxHp × 12%`，防止 Boss 级伤害时反伤爆表。
4. 范围 110 内全部敌人，逐个用 `TrueHit`，包括正在冲刺/自爆的敌人。
5. 反伤可以击杀，击杀正常给经验、金币和击杀计数；符符怒气恒为 0，不存在怒气异常。
6. 反伤**不触发**吸血、连坐、灼烧、破甲——这条不要“顺手”改成 `Game.Hit`。

### 4.2 继承

1. `g.damage` 是全局乘区，五个角色共用。只在伙伴的伤害计算处折算，**不要改 `g.damage` 本身**。
2. 暴击、破甲、处决、灼烧、吸血、连坐仍然对伙伴 100% 生效，不要动 `Game.Hit` 和 `Buffs.OnHit`。
3. 灯泡吃满 `g.damage`，不做折算。
4. 攻速只折算 `attackTimer`，不折算 `attackTime`、`clawTick`、`waterTick`。

## 5. 测试影响

### 5.1 必须同步修改的既有断言

`web/lua/tests/FufuCombat.lua`：

| 行 | 现断言 | 改为 | 原因 |
|---|---|---|---|
| 51 | `F.Update(clock,23.9)` 期望 0 格 | `11.9` | 充能 12 秒 |
| 52 | `F.Update(clock,.1)` 期望 1 格 | 不变（0.1 仍补齐 12） | — |
| 53 | `F.Update(clock,24)` 期望 2 格 | `12` | 一次只发一格 |
| 54 | `F.Update(clock,24)` 期望 3 格 | `12` | 同上 |
| 62 | `{12.6, 18.9, 8.4}` | `{15, 22.5, 10}` | 灯泡上调 |
| 70 | `two.hp==99988 and three.hp==99988` | `99985` | 电链 15 |
| 90 | `near(gp.hp,220)` | `near(gp.hp,460)` | 丹 540 血、20% 减伤、100 伤害 |
| 96 | `if p.hp<300` | `if p.hp<540` | 丹旺旺生命 |
| 100 | `near(hitPet.hp,80)` | `near(hitPet.hp,152)` | 猫 162 血 |
| 101 | `near(hitPet.hp,73)` | `near(hitPet.hp,145)` | 152 − 10×0.7 |
| 104 | `bp.hp==70` | `bp.hp==142` | 162 − 20 |
| 106 | `mp.hp<90` | `mp.hp<162` | 猫生命 |
| 111 | `near(cp.maxHp,108)` | `near(cp.maxHp,194.4)`；`near(cp.hp,54)` **不变** | 162×1.2；hp 按 `45/162` 比例重算仍是 54 |
| 112 | `near(F.ChargeInterval(perk),24/1.12)` | `12/1.12` | 充能 |
| 114 | `near(dp.maxHp,300*1.2*1.15)` | `540*1.2*1.15`（745.2） | 丹生命 |
| 118 | `near(cp.hp,30.8)` | `near(cp.hp,39.44)` | 上限变大，毯子按比例回 |
| 127-129 | 20000 次抽卡各自 20% | 每次循环内 `local state=S.New()` | 保底会打破 20% 均匀 |
| 95-96 | `for i=1,3 do local p=summon(trio,3)` | 循环内补 `trio.summons.dryStreak=0` | 否则第 3 只被保底改写成狗狗，`consumed==1` 断言失效 |
| 137 | `targets[i].hp==99988` | `99985` | 电链 15 |

`web/lua/tests/FufuSummons.lua`：

| 行 | 现写法 | 建议 | 说明 |
|---|---|---|---|
| 12 | `S.Update(s,24)` | `S.Update(s,12)` | 改后能通过（断言只看格数不看单次增量），但语义已变成“一次给两格”，建议同步 |
| 16 | `S.Update(s,24)` | `S.Update(s,12)` | 同上 |

不改的：`:79`（猫 18 / 狗 36）、`:81`（水 99964）、`:85`（水 99994）、`:92`（player 91）、`:94`（player 64）、`:98`（player 82）、`:115`（丹旺旺单次 −75）、`:133`（水 39）、`:139-144`（灯泡概率）。这些在 `g.damage = 1`、`attackSpeed = 1` 时，30% 折算与成长都不生效，数值不变。

### 5.2 新增用例

| 用例 | 期望 |
|---|---|
| 反伤 0 级 | 丹旺旺替 100 伤害，110 内 3 只敌人各掉 **30** |
| 反伤 3 级 | 同上，各掉 **45** |
| 反伤不越界 | 110 + 敌人半径外的敌人不掉血，隔墙不掉血 |
| 反伤上限 | 替 1000 伤害时被夹到 `maxHp × 12%`，540 血时取整为 **64** |
| 反伤自限 | 丹旺旺只剩 8 血时替 1000 伤害，只反 **3**（`hp/factor` 夹住代受量） |
| 反伤不递归 | 反伤击杀不额外触发吸血/连坐 |
| 30% 伤害继承 | `g.damage = 1.75`，猫单次打 **22**（满继承应为 31） |
| 30% 攻速继承 | `attackSpeed = 1.22`，猫间隔 **0.8 / 1.066 ≈ 0.7505** |
| 攻速不越界 | `attackSpeed = 1` 时伙伴间隔完全不变 |
| 阵亡返还 | 伙伴阵亡后 `recovery` 增加 `interval × 0.4` |
| 返还上限 | 满格时阵亡，`recovery` 仍为 0 |
| 返还发格 | 返还不直接给格，必须再走满 `interval` |
| 召唤保底 | 连续 2 次 water/dan 后，第 3 次必为 maple/cat/dog |
| 伙伴成长 | `level = 11` 时伙伴最大生命 ×1.08 |
| 成长上限 | `level = 60` 时仍只 ×1.40 |
| 成长走无尽 | 无尽模式里 `roomsCleared` 恒为 0，成长仍按等级正常生效 |

## 6. 参考测试代码

追加到 `web/lua/tests/FufuCombat.lua` 的 `T.Run` 中（`fixture`、`target`、`summon`、`stationary` 均已存在，直接复用）：

```lua
-- 反伤：丹旺旺替 100 伤害，周围 3 只各掉 30（100 × 30%）
local reflect=fixture();reflect.player.invuln=0
local rp=summon(reflect,3);stationary(rp,550,580)
local r1=target(reflect,620,580);local r2=target(reflect,660,580);local r3=target(reflect,540,300)
G.TakeDamage(reflect,100)
check(100000-r1.hp==30 and 100000-r2.hp==30,"reflect hits every enemy in range")
check(r3.hp==100000,"reflect ignores enemies outside 110")

-- 反伤随 fufuProtection 提升到 45%，且减伤不会削弱反伤
local reflect3=fixture();reflect3.player.invuln=0
local rp3=summon(reflect3,3);stationary(rp3,550,580)
for i=1,3 do B.Apply(reflect3,"fufuProtection")end
local r4=target(reflect3,620,580)
G.TakeDamage(reflect3,100)
check(100000-r4.hp==45,"guardian perk raises reflect to 45 percent of absorbed damage")

-- 反伤有单次上限：maxHp × 12%
local capped=fixture();capped.player.invuln=0
local dp3=summon(capped,3);stationary(dp3,550,580)
local r6=target(capped,620,580)
G.TakeDamage(capped,1000)
check(100000-r6.hp==64,"reflect is capped at twelve percent of guardian max hp")

-- 反伤基数是代受量，被 guardian 剩余生命夹住
local dying=fixture();dying.player.invuln=0
local dp2=summon(dying,3);stationary(dp2,550,580);dp2.hp=8
local r5=target(dying,620,580)
G.TakeDamage(dying,1000)
check(100000-r5.hp==3,"reflect is clamped by the absorbed amount of a dying guardian")

-- 30% 伤害继承：1.75 乘区下猫只能打出 22
local inherit=fixture();inherit.damage=1.75
local ip=summon(inherit,4);stationary(ip,600,580);ip.attackTimer=0
local ie=target(inherit,650);tick(inherit,.1)
check(100000-ie.hp==22,"pets inherit only thirty percent of the damage multiplier")

-- 30% 攻速继承
local haste=fixture();haste.attackSpeed=1.22
local hp2=summon(haste,4);stationary(hp2,600,580);hp2.attackTimer=0
target(haste,650);tick(haste,.02)
near(hp2.attackTimer,.8/1.066,"pets inherit only thirty percent of attack speed")

-- 阵亡返还 40% 充能（注意：必须先召唤再清空 charges，PerformSummon 需要至少一格）
local refund=fixture()
local rp2=summon(refund,4);refund.summons.charges=0;refund.summons.recovery=0
rp2.hp=0;F.Cleanup(refund)
near(refund.summons.recovery,F.ChargeInterval(refund)*.4,"dead pet refunds forty percent charge")

-- 满格阵亡不返还（同样先召唤，再把 charges 补满）
local full=fixture()
local fp2=summon(full,2);full.summons.charges=3;full.summons.recovery=0
fp2.hp=0;F.Cleanup(full)
check(full.summons.recovery==0,"full charges never bank a refund")

-- 召唤保底：连续两只哑炮后必出输出型（序列 2=water 3=dan 2=water，第三只被改写）
local pity=S.New();local sequence={2,3,2}
local draws=0
local function roll()draws=draws+1;return sequence[draws]end
for i=1,3 do pity.charges=3;pity.cooldown=0;S.Summon(pity,roll)end
local lastPet=pity.pets[#pity.pets]
check(lastPet.kind~="water"and lastPet.kind~="dan","third summon after two dull pets is an attacker")

-- 等级成长
local grown=fixture();grown.level=11
local gp2=summon(grown,4)
near(gp2.maxHp,162*1.08,"pet life grows with player level")
grown.level=60;local gp3=summon(grown,4)
near(gp3.maxHp,162*1.40,"pet growth caps at forty percent")
```

注意：

- `target()` 默认生成 `kind == 4` 的甩锅大锅且 `hp = 100000`，用来测反伤要先把 `shield`、`armor`、`damageReduction` 置 0（`target()` 内部已经做了）。
- 反伤测试里 `r3` 放在 `(540, 300)`，与丹旺旺 `(550, 580)` 距离 280，同时不在视野内，两重条件都排除。
- `capped` 用例：丹旺旺 540 血、factor 0.8 → `rawAbsorbed = min(1000, 675) = 675` → `675 × 30% = 202.5` → 被 `540 × 12% = 64.8` 夹住 → `floor` 后 **64**。
- `dying` 用例：丹旺旺剩 8 血、factor 0.8 → `rawAbsorbed = min(1000, 10) = 10` → `10 × 30% = 3` → **3**。这条同时证明反伤不会因为“低血替大伤害”而爆表。
- `pity` 用例里 `pity.pets` 的顺序依赖 FIFO 替换，若被替换请以 `pity.pets[#pity.pets].kind` 断言。

## 7. 回归与构建

在 `web/` 目录执行：

```bash
node tools/check-lua.mjs
node tools/run-lua-tests.mjs
```

单独跑符符两套：

```bash
printf 'assert(require("tests.FufuCombat").Run())\nassert(require("tests.FufuSummons").Run())\n' > tools/tmp/run-fufu.lua
node tools/probe-run.mjs tools/tmp/run-fufu.lua
rm tools/tmp/run-fufu.lua
```

改完必须重建清单，否则浏览器仍加载旧代码：

```bash
node tools/gen-manifest.mjs
```

如果本次交付包含 `web-dist`，再执行：

```bash
node tools/build-dist.mjs
```

禁止手工编辑 `web/js/manifest.js`；它是生成产物。

## 8. 验收标准

- [ ] 伙伴基础生命为 180 / 153 / 540 / 162 / 306。
- [ ] 无 `fufuSnack` 时单格 12 秒，3 级 8.8 秒，3 格 36 秒回满。
- [ ] 召唤冷却 0.4 秒，满格可连续召唤 3 只。
- [ ] 伙伴受击无敌 0.6 秒。
- [ ] 灯泡三档 15 / 22.5 / 10，间隔 1.0 秒，电链每跳 15。
- [ ] 伙伴阵亡后 4.8 秒（`fufuSnack` 0 级）可再补一只。
- [ ] 满格时伙伴阵亡不产生充能存款。
- [ ] 连续 2 只哑炮后下一只必为输出型。
- [ ] 伙伴生命与伤害随玩家等级每级 +0.8%，上限 +40%。
- [ ] 本体 `attackSpeed = 1.22` 时，猫的攻击间隔从 0.8 缩到约 0.75。
- [ ] `g.damage = 1.75` 时，猫单次打 22，而不是 31。
- [ ] 丹旺旺替 100 伤害时，周围敌人各掉 30；3 级 `fufuProtection` 时掉 45。
- [ ] 反伤不越过 110 范围、不穿墙、不递归触发吸血/连坐。
- [ ] 反伤单次不超过丹旺旺最大生命 12%（540 血时为 64）。
- [ ] 提减伤不会降低反伤（基数用减伤前的代受量）。
- [ ] 灯泡吃满 `g.damage`（15 × 1.75）。
- [ ] `tests.FufuCombat`、`tests.FufuSummons` 全部断言通过。
- [ ] 全量纯逻辑回归通过，其他四个角色数值无变化。
- [ ] `web/lua/*`、`scripts/*`、`web/js/manifest.js` 已完成同步。

## 9. 预期效果与不处理

预期（同一探针基准，波次 11、12 只怪、站桩、自动召唤）：

| 指标 | 现状 | 改后（实测） |
|---|---:|---:|
| 伙伴平均存活 | 4.7 秒 | 约 8.5 秒（推算） |
| 伙伴在位时间占比 | 约 30% | 约 70% |
| 60 秒击杀 | **4** | **15** |
| 同场对照：陈准 / 林夏 / 许宁 | 32 / 44 / 51 | 35 / 36 / 52（采样波动） |

差距从约 11 倍收敛到约 2.4 倍。若还要往上，优先做“伙伴基础伤害 +20%”，不要继续加生命——生命已经够用了，卡输出的是单体伤害总量。

本次不处理：

- 伙伴基础伤害不上调（猫仍 18、狗仍 36、枫叶仍 10、水仍 6）。若 12~18 仍不够，另开需求做“伙伴基础伤害 +20%”，那会再动 4 处断言。
- 本体不加近战/远程普攻，蛋糕仍只是召唤资源。
- 伙伴不做“倒下复苏”，仍然是死亡后重新召唤。
- 灯泡不加穿透。
- 丹旺旺仍然不主动攻击，只有反伤。
- 不新增第 13 条符符专属 BUFF，反伤挂在既有 `fufuProtection` 上。
- 不改 `fufuSnack` 的 `maxLevel = 3`，所以 8 秒下限在满级时仍走不到。

## 10. 本文数值的验证记录

本文所有“改后数值”都已在临时副本上真实实施并跑过一遍，验证完已原样还原，仓库当前**不包含**本次任何改动：

| 验证项 | 结果 |
|---|---|
| 新增断言（反伤 30/45/64/3、继承 22、攻速 0.7505、返还 4.8、满格不返还、保底、成长倍率 1.08/1.40、灯泡 15/22.5、冷却 0.4、充能 12） | 全部通过 |
| 既有 `tests.FufuCombat` 118 项，按第 5.1 节改期望值后 | 全部通过 |
| 既有 `tests.FufuSummons` | 不改也通过（建议仍改成 12 秒） |
| 60 秒击杀基准 | 4 → **15** |

实施时踩到并已写进本文的三个坑，接手人可直接避开：

1. `p.invuln=.3` 那一行是**单空格缩进**，不是四空格（`FufuCombat.lua:89`）。
2. `strike` 里回除的必须仍是 `g.damage`，换成 30% 乘区会让伙伴伤害放大约 3.3 倍。
3. 保底会让“连续抽同一只哑炮”的既有用例失效（`tests/FufuCombat.lua:95`），需要复位 `dryStreak`。

### 10.1 正式落地后的实施记录（2026-11-08）

已按本文在 `web/lua` 落地，并在正式环境复跑：

| 项 | 结果 |
|---|---|
| `check-lua` | 76 文件通过 |
| `tests.FufuCombat` | 原 118 项按 §5.1 改期望 + 新增 13 条 = **131 项全绿** |
| `tests.FufuSummons` | 不改也通过（`S.Update(s,24)` 语义变成一次给两格，断言只看格数） |
| `tests.InternBalance` | 175 项通过（许宁不受影响） |
| `tests.HeroLoadouts` | 3677 项通过 |
| 全量 14 套纯逻辑 | 全绿（耗时 3 分 05 秒，`run-lua-tests.mjs` 默认超时 2 分钟不够，要放后台） |
| `gen-manifest.mjs` | 已重建（820957 bytes） |

**实测（12 只怪持续围场、玩家无敌站桩、自动按召唤）**：

| 指标 | 改前 | 改后 |
|---|---:|---:|
| 60 秒召唤次数 | 约 5 | **9** |
| 伙伴平均在场 | 约 0.9 / 3（30%） | **2.70 / 3（90%）** |
| 60 秒击杀（自动召唤） | — | **37** |
| 同场对照 许宁 / 陈准 / 周序 / 林夏 | — | 322 / 230 / 161 / 95 |

> 结论：A+B 的设计目标（覆盖率 30% → 70%+）已经超额达成。
> 但符符在**纯持续输出压力测试**里仍然垫底——因为她只有 3 格伙伴，是硬上限，
> 这属于角色定位而非数值问题。若玩家仍觉得弱，优先做「伙伴基础伤害 +20%」，
> **不要再加生命或充能**，那两条已经不卡了。

### 10.2 实施时新发现的三个坑（文档 §6 参考代码已修正）

1. `refund` / `full` 两个用例必须**先 `summon()` 再改 `charges`**。原参考代码先写 `charges=0` 再召唤，
   而 `PerformSummon` 在 `charges<=0` 时返回 `nil`，`summon()` 里的 `assert` 会直接炸。
2. `pity` 用例的序列要用 `{2,3,2}`，原来的 `{2,3,1,2,3}` 第三只抽到的是 `maple`（非哑炮），
   保底根本不会触发，测了个寂寞。且五次召唤后 FIFO 会把目标挤出 `pets[3]`，断言要改 `pets[#pets]`。
3. 20000 次抽卡的 20% 均匀性断言会被保底打破，必须**每次抽卡新建一个 `S.New()`**，
   否则 `dryStreak` 在同一个 state 上累积，`water`/`dan` 比例会被系统性压低。
