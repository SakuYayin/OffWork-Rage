# 17 · 林夏（female）霰弹化改造交接文档

> 目标：把林夏从「没有专属机制的高数值点射角色」改造成**低速近战霰弹手**——
> 近距离一枪一个，远距离散射且伤害衰减。
>
> 本文是给实施者的完整交接：所有数值都给了推导过程和替代值，实现只需要动
> `web/lua/Game.lua` 两处 + `web/lua/Heroes.lua` 文案，**不动血量、不动移速、不动大招**。

---

## 1. 现状与问题

### 1.1 她是五个角色里唯一没有专属代码的人

`web/lua/Game.lua` 全文中 `heroId == "female"` 只出现在两处：

- `Game.lua:661-672` 大招的兜底分支：`elseif g.heroId == "male" then BurstImpactMale(g) else BurstImpactFemale(g) end`
- 其余命中全部是立绘、配色、头像资源

对照其他四人：

| 角色 | 专属代码 |
|---|---|
| 陈准 male | `BurstImpactMale` 198° 扇形重击 + 眩晕 + 肾上腺素攻速 |
| 许宁 intern | 护盾系统 + `reduction=.30` + 文件夹重击 + `HeroScaling` 增益减半 |
| 周序 programmer | 二进制子弹 + 自带穿透 + 等级成长 |
| 符符 fufu | `FufuSummons` 召唤 + `FufuCombat` 代受反伤 + 灯泡 |
| **林夏 female** | **无** |

### 1.2 文案承诺了三件不存在的事

`web/lua/Heroes.lua:17-20`：

```lua
local female = { id = "female", name = "林夏", title = "高效反击派",
    description = "脚步稍慢、精力较少，单次伤害更高。善用家具掩体，抓住反击时机。",
    maxHp = 90, speed = 156, damage = 1.30, ... }
```

`掩体 / 反击 / parry / dodge` 在整个 `web/lua/` 里**没有任何实现**。
（Z 瞬步 `Buffs.lua:69` 是五角色通用的 `dash` buff，不是她的。）

### 1.3 面板是诚实的，但结构有洞

订书机现状（`Game.lua:1141-1152`）：

```lua
local count  = Scaling.Count(g,"stapler-count",  Scaling.Growth(g,1,math.min(3,g.stapler)))
local pierce = Scaling.Count(g,"stapler-pierce", Scaling.Growth(g,1,g.stapler))
... vx=cos*530, life=1.5, damage=Scaling.Growth(g,25,20+5*g.stapler), pierce=pierce
```

| | 单发伤害 | 开火间隔 | 单体 DPS | 单次可命中数 |
|---|---|---|---|---|
| 陈准 键盘 | 27×0.85 = 22.95 | 0.64s | 35.9 | 扇形内全部 |
| 周序 二进制 | 12×0.75 = 9 | 0.28s | 32.1 | 1 |
| **林夏 订书机** | 25×1.30 = **32.5** | 0.6466s | **50.3** | **1** |

她单体最高，文案没说谎。问题在最后一列：`Game.lua:1553` 是

```lua
s.pierce = s.pierce - 1
if s.pierce < 0 then s.life, stopT = 0, contact.t; break end
```

`pierce` 就是「能打几只怪」。她 L1 `count=1, pierce=1`，**每 0.65 秒只能钉死一只**，
全部群伤都锁在大招那一个键上。

### 1.4 数值上她不弱，所以不能靠加数值解决

实测基线（裸装，同种子）：

- 60 秒击杀：林夏 **44** / 许宁 51 / 符符改前 4
- 45 秒三层区域清怪：林夏 **37 / 38 / 29** / 周序改后 15 / 21 / 14

给她加伤害等于把周序和符符刚校准好的对照线一起顶高。
**本次改造不加任何面板数值，只改输出形态。**

---

## 2. 定位定稿

> **林夏 = 低速霰弹手（近距离一枪一个，远距离散射+衰减）**

三条设计承诺：

1. **近距离满伤**：贴脸时全部弹丸命中同一目标，单发即可一枪一个普通怪。
2. **远距离衰减**：飞行距离越远单颗伤害越低，最远处只剩 35%；配合扇形散布，
   远距离实际是「洒一片」而不是「打一个」。
3. **强击退**：一发把贴脸的怪推开，这是她唯一的防御手段，替代「掩体」。

与陈准的区分（陈准 188 移速 / 130 血 / 键盘 104 半径扇形近战）：

| | 陈准 | 林夏（改后） |
|---|---|---|
| 节奏 | 0.64 秒一轮，持续磨 | **1.05 秒一发，打完有空窗** |
| 命中 | 扇形内全部命中 | 弹丸分散，**必须贴脸才集中** |
| 定位 | 突进游击、持续压制 | **站桩爆发、一发定生死** |
| 防御 | 130 血 + 眩晕控场 | **击退**，血更少（90） |

---

## 3. 数值方案

### 3.1 面板：完全不动

```lua
-- web/lua/Heroes.lua:17-22 保持不变
maxHp = 90, speed = 156, damage = 1.30, primaryWeapon = "stapler"
```

**只改 `description`**（第 19 行），把不存在的「掩体」换成真实机制：

```lua
description = "脚步稍慢、精力较少。霰弹近距离一枪一个，远处散射无力——把麻烦逼到面前再解决。",
```

> 这样 `tests/HeroLoadouts.lua:55` 的 `p.player.maxHp<90 and p.player.speed<156`
> 断言不需要改；她的大招数值断言（`tests/Actions.lua:305-307` 逐字节验 `floor(125*g.damage)`）也不受影响。

### 3.2 订书机 → 霰弹（`Game.lua:1141-1152`）

| stapler 等级 | 弹丸数 | 单颗基础 | 单颗实伤（×1.30） | 满命中合计 | 开火间隔 | 贴脸单点 DPS |
|---|---|---|---|---|---|---|
| 1 | 4 | 14 | 18.2 | 72.8 | 1.05s | 69.3 |
| 2 | 5 | 16 | 20.8 | 104.0 | 0.955s | 108.9 |
| 3 | 6 | 18 | 23.4 | 140.4 | 0.875s | 160.5 |
| 4 | 7 | 20 | 26.0 | 182.0 | 0.808s | 225.2 |

公式：

```lua
pellets = 3 + g.stapler                       -- 4 / 5 / 6 / 7
单颗伤害 = 12 + 2 * g.stapler                  -- 14 / 16 / 18 / 20
开火间隔 = 1.05 / ((1 + 0.10*(g.stapler-1)) * rate) -- rate = attackSpeed * AttackSpeedMul
         -- 注意是 (stapler-1)：L1 必须正好 1.05s，否则整张表错一档
pierce  = g.stapler >= 3 and 2 or 1
弹速    = 360
life    = 0.46            -- 射程 = 360 × 0.46 = 165.6px
散布角  = 0.17 rad / 颗   -- count=4 时 ±0.425 rad ≈ ±24°
击退    = 280
```

### 3.3 数值为什么是这些

**「一枪一个」的锚点**：`Enemies.lua:12-17` 基础血量 34 / 44 / 62 / 96 / 110（boss 900）。
第一层第一波 `hp = base × 1.0 × 1.0`。L1 满命中 72.8 → 秒掉 bomber(34)、spitter(44)、charger(62)，
打不死 shieldGuard(96) 和 summoner(110)。**这就是「普通怪一枪一个，精英要两枪」**，
符合霰弹的直觉。

**为什么是 4 颗而不是 8 颗**：`Assets`/`Effect` 每颗弹丸都会触发一次 `stapleHit` 特效与一次
`staple` 音效（`Audio.lua:88`，cd 0.065）。7 颗同帧已经接近音效合并的边界，
再多会让贴脸帧卡顿。4→7 的成长曲线也给了升级手感。

**为什么开火间隔从 0.65 拉长到 1.05**：贴脸满命中是 72.8 而不是 32.5，如果保持 0.65 秒，
单体 DPS 会从 50 直接跳到 112（+124%）。拉到 1.05 秒后贴脸 DPS 是 69.3（+38%），
**多出来的这 38% 就是「贴脸」这件事的风险溢价**。同时 1.05 秒的空窗是她的弱点，
也是和陈准「持续磨」的核心差异。

**为什么击退是 280**：`Game.lua:1461-1462` 的击退衰减是 `decay = 1 - dt*9`，
总位移 ≈ `force / 9`。当前 65 → 约 7px（几乎没有），280 → **约 31px**（推得开一个身位），
和许宁文件夹 280（`Game.lua:1108`）同档，低于保温杯第三段 468（`Game.lua:1173`）。

**为什么射程是 166 而不是更长**：见 §7 的风险清单，这是一个刻意的取舍。

### 3.4 距离衰减（新增机制）

**规则**：

- 飞行距离 ≤ 40px：全额伤害
- 40px → 166px：线性衰减
- ≥ 166px（弹丸生命耗尽前的最远处）：**35%**

| 命中距离 | 衰减系数 | 单颗实伤（L1） | 4 颗全中 |
|---|---|---|---|
| 30px（贴脸） | 1.00 | 18.2 | 72.8 |
| 80px | 0.79 | 14.4 | 57.6 |
| 120px | 0.59 | 10.7 | 42.9 |
| 166px（极限） | 0.35 | 6.4 | 25.5 |

远距离还有第二重惩罚：散布角固定，166px 处最外侧弹丸偏离轴线 166×tan(0.425) ≈ **73px**，
4 颗弹丸几乎不可能落在同一只半径 13 的怪身上。
**所以「远距离散射伤害较低」是衰减系数 + 弹道发散共同作用的结果，不需要额外机制。**

---

## 4. 实现

### 4.1 发射段（`web/lua/Game.lua:1141-1152` 整段替换）

**关键设计决定：霰弹形态只属于「主武器是订书机」的角色（即林夏）。**
其他角色拾取订书机时走原来的单发钉书钉分支。

理由：`tests/InternBalance.lua` 末尾有一段**许宁拾取订书机**的断言
（`damage==27.5`、弹丸 1→2、穿透 1→2，共 159 项里的一部分）。
如果霰弹对全员生效，这套断言会连带崩掉，而且许宁的「增量减半」口径要重新配基准值。
用主武器门禁可以把改动面压到最小，也符合本作「每个角色的主武器都是专属形态」的既有约定
（陈准键盘是近战扇形、许宁文件夹是 AoE、周序二进制是穿透连发）。

```lua
    elseif action.name == "stapler" then
        if g.primaryWeapon == "stapler" then
            -- 林夏霰弹：近距离满伤、远距离散射衰减、强击退。见 docs/design/17-female-shotgun.md
            local pellets = 3 + g.stapler
            local pierce = g.stapler >= 3 and 2 or 1
            local pelletDamage = 12 + 2 * g.stapler
            for i = 1, pellets do
                if #g.shots >= 128 then break end
                local angle = math.atan(ny, nx) + (i - (pellets + 1) / 2) * 0.17
                g.shots[#g.shots + 1] = { x = p.x, y = p.y, vx = math.cos(angle) * 360,
                    vy = math.sin(angle) * 360, life = 0.46, damage = pelletDamage,
                    pierce = pierce, hit = {}, actionSerial = action.serial,
                    knock = 280,
                    -- 距离衰减：<=40px 全额，>=166px 剩 35%（fo* 前缀避免与旧字段冲突）
                    foNear = 40, foRange = 126, foMin = 0.35, foTraveled = 0 }
            end
        else
            -- 其他角色拾取订书机：保持原有单发钉书钉，口径不变。
            local count = Scaling.Count(g, "stapler-count", Scaling.Growth(g, 1, math.min(3, g.stapler)))
            local pierce = Scaling.Count(g, "stapler-pierce", Scaling.Growth(g, 1, g.stapler))
            for i = 1, count do
                local angle = math.atan(ny, nx) + (i - (count + 1) / 2) * 0.14
                g.shots[#g.shots + 1] = { x = p.x, y = p.y, vx = math.cos(angle) * 530,
                    vy = math.sin(angle) * 530, life = 1.5, damage = Scaling.Growth(g, 25, 20 + 5 * g.stapler),
                    pierce = pierce, hit = {}, actionSerial = action.serial }
            end
        end
```

> 因为走的是门禁而不是 `Scaling.Growth` 的减半基准，所以**不需要**为许宁配新的 base 值，
> `Scaling.Count` 的半分信用语义也完全不动。

### 4.2 开火间隔（`web/lua/Game.lua:1045-1048`）

```lua
    if Loadout.Has(g,"stapler")and g.stapler > 0 and g.staplerTimer <= 0 and not ActionState.Active(g, "stapler") then
        local action = ActionState.Start(g, "stapler", nx, ny)
        if action then
            -- 林夏霰弹节奏更慢（1.05s 起、每级 -10%）；其他人保持原订书机 0.75s 起、每级 -16%。
            local shotgun = g.primaryWeapon == "stapler"
            local base = shotgun and 1.05 or 0.75
            -- 用 (stapler-1) 而不是 stapler，保证 L1 就是 1.05s（§3.2 的 DPS 推导按这个口径写的）。
            local growth = shotgun and (1 + (g.stapler - 1) * .10) or (1 + g.stapler * .16)
            g.staplerTimer = base / (Scaling.Growth(g, 1.16, growth) * rate) + math.max(-dt, g.staplerTimer)
        end
    end
```

`Scaling.Growth(g, 1.16, growth)` 对林夏（`Generic == 1`）原样返回 `growth`，
对许宁走减半口径，**与改动前逐字等价**。

### 4.3 衰减结算（`web/lua/Game.lua:1518-1556` 子弹碰撞循环）

三处改动，**未设置 `fo*` 字段的弹体会走 `mul = 1` 的老路径，其他武器零影响**。

① 在 `local bx, by = ox + s.vx * dt, oy + s.vy * dt` 之后加：

```lua
        local segLen = math.sqrt((bx - ox) * (bx - ox) + (by - oy) * (by - oy))
```

② 把 `Game.lua:1548` 的

```lua
                Game.Hit(g, e, s.damage, nx, ny, s.knock or 65)
```

改成：

```lua
                local mul = 1
                if s.foMin then
                    local traveled = (s.foTraveled or 0) + contact.t * segLen
                    local k = math.max(0, math.min(1, (traveled - s.foNear) / s.foRange))
                    mul = 1 - k * (1 - s.foMin)
                end
                Game.Hit(g, e, s.damage * mul, nx, ny, s.knock or 65)
```

③ 在 `for _, contact in ipairs(hits) do ... end` 循环**之后**、`s.x, s.y = ...` 之前加：

```lua
        s.foTraveled = (s.foTraveled or 0) + segLen
```

> ⚠️ 顺序很重要：`contact.t * segLen` 必须用**本帧累计之前的** `foTraveled`，
> 所以累加必须放在循环外、循环后。放在循环里会让同一帧的多段命中距离错位。

### 4.4 文案（一处）

**`web/lua/Game.lua:678`** 升级卡（这张卡五角色共用，改成语义对两边都成立的写法）：

```lua
{ id = "stapler", title = "流程钉死", tag = "武器 / 订书机", desc = "解锁订书机；已拥有则强化弹丸数量与穿透。", color = "teal" },
```

**`web/lua/Game.lua:706`（许宁口径）不改。** 因为门禁方案下许宁的订书机行为完全没变，
「后续伤害、连发、穿透和射速强化增量仅50%」仍然准确。

### 4.5 不改的东西（重要）

- ❌ `BurstImpactFemale`（`Game.lua:613-634`）**完全不动**。半径 260、`floor(125*g.damage)` 真伤、
  3 层 `InsightMark`、2.5 秒减速全部保留，`tests/Actions.lua:305-307` 的逐字节断言不受影响。
- ❌ 血量 90 / 移速 156 / `damage` 1.30 不动。
- ❌ `ActionState.lua:27` 的 `stapler = { windup=.05, impactAt=.07, duration=.24 }` 不动
  （0.24 秒收招 < 1.05 秒间隔，不会自锁）。
- ❌ 敌人（`Enemies.lua`）、`Difficulty.lua` 一概不动。

---

## 5. 与大招的联动（顺带变强，需知情）

`Game.lua:491-494` 里，命中带 `markHits` 的目标会消耗一层并 ×1.35：

```lua
if (e.markHits or 0) > 0 then ... amount = amount * 1.35; e.markHits = e.markHits - 1 ... end
```

改前她一次只有 1 颗弹丸，3 层标记要打 3 枪才吃完。**改后一枪 4~7 颗，一层标记一颗弹丸，
一枪就把 3 层吃满。** 于是出现一个新的爆发窗口：

> 开大（挂 3 层标记）→ 贴脸一枪 → 3 颗弹丸各吃 ×1.35

L1 期望额外收益 ≈ `3 × 18.2 × 0.35 = 19.1` 点/次开大。这是可接受的赠品，
但如果实测发现 Boss 战过快，**第一个该收紧的就是这里**（把标记改成每枪最多消耗 1 层）。

---

## 6. 受影响的测试断言（必须同步改）

> **先说清楚哪些不用改**：因为 §4.1 用了「主武器门禁」，下面这些**全部原样通过、一个字都不要改**——
>
> - `tests/InternBalance.lua` 末尾许宁拾取订书机的断言（`damage==27.5`、弹丸 `1→2`、穿透 `1→2`）
> - `tests/InternBalance.lua:39` 文件夹伤害 `math.floor(110*1.225*1.125)`
> - `tests/Actions.lua:213-234` `stapler single volley level 1 / 3`（用 `Fixture()` → 陈准，走 else 分支）
> - `tests/Actions.lua:250-276` `repeated cooldowns do not starve`（同上，陈准）
> - `tests/Actions.lua:305-307` 林夏大招 `floor(125*g.damage)` 逐字节断言
> - `tests/HeroLoadouts.lua:55` 的 `maxHp<90 and speed<156`（面板没动）
>
> **结论：门禁方案下，现有断言一个都不会失败。** 本次只需要**新增**林夏专项断言。

### 6.1 为什么原来那两条会失败、现在不会了

原方案（霰弹对全员生效）会撞上两处：

| 用例 | 原断言 | 霰弹生效后的值 | 结果 |
|---|---|---|---|
| `Actions.lua:217` `stapler single volley level 1/3` | 弹丸 `1 / 3` | `4 / 6` | ❌ 崩 |
| `Actions.lua:250-276` `repeated cooldowns` | `counts.stapler >= 7` | 间隔 0.318s → 约 20 次 | ✅ 仍过 |
| `InternBalance.lua` 末尾 | `damage==27.5`、弹丸 `1→2`、穿透 `1→2` | `17`、`3→3`、`1→1` | ❌ 崩 |

加上主武器门禁后，前面这些用例的 fixture 都是**陈准**（`Fixture()` 默认 `male`）
或**许宁**（secondary 订书机），全部走 else 老分支，因此**逐字不变**。

> ⚠️ 如果后续决定让霰弹对全员生效，就必须同时改这三处期望值，
> 并且要给许宁重新配 `Scaling.Growth` 的减半基准。**不建议。**

### 6.2 `web/lua/tests/HeroRules.lua:120-126`（**会失败，实施时踩到了**）

这是实施时唯一一条漏掉的断言，跑全量回归才暴露：

```lua
Tick(melee,5)
local expected=math.floor((primary=="keyboard"and 27 or 25)*spec.damage)
Check(closeHp-close.hp==expected,label.."初始专属武器命中应用角色倍率")
```

两个问题叠在一起：

1. **tick 不够**。木桩在 50px 外，霰弹速度 360，飞行 `50/360 ≈ 0.139s`，加上 0.07s 起手需要约 **11 tick**。
   原用例只跑 `1 + 5 = 6` tick（0.12s），弹丸还在半路，伤害是 **0**。
2. **期望值口径变了**。原来是「单发 25」，现在是「4 颗 × 单颗 14」。

改成：

```lua
Tick(melee,12)
-- 林夏的订书机已改成霰弹：4 颗弹丸 × 单颗 14，50px 处命中点在 40px 满伤区内，
-- 逐颗 floor 后合计 4 × floor(14 × damage)。
local expected
if primary=="stapler" then
    expected=4*math.floor(14*spec.damage)
else
    expected=math.floor((primary=="keyboard"and 27 or 25)*spec.damage)
end
Check(closeHp-close.hp==expected,label.."初始专属武器命中应用角色倍率")
```

> **为什么 50px 还能吃到满伤**：`SegmentHit` 用的是 `e.radius + 4` 的碰撞圆，
> 木桩半径约 15，命中判定发生在弹丸中心距 **31px** 时就成立，仍在 40px 满伤区内。
> 所以这一发是 `4 × floor(14 × 1.30) = 72`，实测一致。
>
> 后面 `HeroRules.lua:133-135` 那条手工构造的 `{damage=25, vx=530}` 弹丸没有 `fo*` 字段，
> 走 `mul = 1` 老路径，**不用改**。

### 6.3 `web/lua/tests/HeroLoadouts.lua:45-47`（通过，无需改）

```lua
local normal,fast=fixture("female"),fixture("female");fast.attackSpeed=2
check(impacts(fast,4)>impacts(normal,4),"attack speed actually accelerates stapler")
```

这个用例**用的是林夏**，会走新分支。
`impacts` 统计的是 `#g.shots`（弹丸总数）。改后单轮 4 颗、间隔 1.05s；攻速翻倍 → 轮次翻倍 → 弹丸数翻倍，
`>` 仍成立 ✅。但要注意 `tick(g,4)` 用的是 `G.Update(g, .02, …)`，即每 tick 20ms，4 tick = 80ms
> 命中线 70ms —— 刚好越过，仍会发弹。**实测若发现 `impacts(normal,4)==0`，把 4 改成 6。**

### 6.4 `web/lua/tests/ProjectileFx.lua:8-22`（应通过）

该用例手工构造 `{vx=…, kind="staple"}` 的弹体，没有 `fo*` 字段 → 走 `mul=1` 老路径 ✅。

### 6.5 `web/lua/tests/ArtShowcase.lua:47`（不涉及战斗，忽略）

写死了 `vx = 530, life = 1.5, damage = 30`，是纯展示数据，无需同步。

### 6.6 需要新增的断言（建议加在 `tests/Actions.lua`）

**签名已核对**：`Actions.lua` 的 `Fixture(heroId)` / `Target(g, x, y)` 用的是**绝对坐标**，
且 `Fixture` 没有覆写玩家坐标（玩家停在 `rooms[1].spawn`）。
所以断言里必须**先手动把玩家钉到 (520, 580)**，再按偏移放木桩——
这正是 `tests/HeroLoadouts.lua:10-13` 的做法，照抄即可。

```lua
Case("shotgun pellet count and spread", function()
    local g = Fixture("female")
    g.player.x, g.player.y = 520, 580
    Target(g, 580, 580)                       -- 距玩家 60px，贴脸
    g.stapler, g.staplerTimer = 1, 0
    Tick(g, 5)                                -- 命中线 0.07s ≈ 第 5 帧
    Check(#g.shots == 4, "level1 shotgun fires four pellets")
    local angles = {}
    for _, s in ipairs(g.shots) do angles[#angles + 1] = math.atan(s.vy, s.vx) end
    table.sort(angles)
    Check(math.abs((angles[4] - angles[1]) - 3 * 0.17) < 0.01, "pellets fan out at 0.17 rad")
    for _, s in ipairs(g.shots) do
        Check(s.damage == 14 and s.foMin == 0.35 and s.knock == 280,
            "shotgun pellet carries falloff and knock")
    end
end)

Case("shotgun falls off with distance", function()
    local near = Fixture("female")
    near.player.x, near.player.y = 520, 580
    local close = Target(near, 580, 580)      -- 60px
    near.stapler, near.staplerTimer = 1, 0
    Tick(near, 20)                            -- 60px / 360 ≈ 10 帧 + 5 帧起手，留余量

    local far = Fixture("female")
    far.player.x, far.player.y = 520, 580
    local distant = Target(far, 670, 580)     -- 150px，仍在 166px 射程内
    far.stapler, far.staplerTimer = 1, 0
    Tick(far, 35)                             -- 150px / 360 ≈ 25 帧 + 5 帧起手

    Check(close.hp < distant.hp, "closer target takes more shotgun damage")
end)
```

> **为什么贴脸用例里 4 颗都会命中**：60px 处弹丸横向偏移是 `±0.255 rad × 60 ≈ ±15px`，
> 小于木桩碰撞半径（`e.radius + 4`），所以 4 颗全部落在同一目标上，合计 72.8。
> 150px 处横向偏移拉开到 `±37px`，只有中间 1~2 颗能中，再叠加 0.43 倍衰减，
> 两者差额足够大，`close.hp < distant.hp` 不会因为取整而翻车。

---

## 7. 风险清单（实施前必读）

### 7.1 ⚠️ 远程敌人 spitter（最高风险）

`Enemies.lua:139-150`：spitter **保持 180~260 距离**，射程 **420**，每 1.8 秒三连发。
林夏射程 166 → **她打不到 spitter，spitter 打得到她**。

**为什么仍然认为可接受**：spitter 移速只有 26，林夏 156（**6 倍**）。
追进 166px 只需要 `100 / (156-26) ≈ 0.77 秒`，而 spitter 1.8 秒才射一轮。
所以正确处理方式是「压上去」而不是「对射」，**这恰好是她该有的玩法**。

**如果实测发现 F3 之后被放风筝放死**，按顺序尝试：
1. 射程 166 → 190（life 0.46 → 0.53），仅一步
2. 给霰弹加「命中后 1 秒内移速 +15%」（追击奖励）
3. 最后才考虑改 spitter 的保持距离（**会牵连全体角色，尽量不碰**）

### 7.2 ⚠️ 自爆怪 bomber

`Enemies.lua:132-137`：距离 < 46 自爆，半径 62 内 22 伤害。林夏 90 血 → 4 次就死。
她射程 166，理论上应该在 100px 外先手打死（一枪 72.8 > 34hp），
但**贴脸满伤是这次改造的卖点，会诱导玩家往 46px 以内站**。

**缓解**：击退 280（约 31px）本身就是解——一枪把 bomber 推离自爆圈。
需要在实测里验证「贴脸打 bomber 后是否能被推开到 > 46px」。

### 7.3 与陈准的重叠（已确认可接受，不作为风险）

陈准和林夏本来就是开发初期同一角色的男女分支，后来才拆开，**设定上重叠是历史包袱，不是缺陷**。
所以这里不追求「必须拉开」，只保证一件事：**手感上能分辨**——

- 陈准：188 移速、0.64 秒一轮、扇形内全部命中 → 突进、连续、贴脸磨
- 林夏：156 移速、1.05 秒一发、弹丸集中才见效 → 站桩、断奏、一发定生死

如果实测下来两人手感仍然太像，**优先拉开的是开火节奏（1.05 vs 0.64）**，
其次才是弹道形态；**不要靠继续加伤害来制造差异**。

### 7.4 承伤上升

她原本在 300~700px 输出，改后在 100~166px，承受伤害会显著上升。
**这是设计意图**，但需要实测存活时间。若 F1 存活 < 25 秒：
1. 先确认击退生效（打日志看 `e.knockX`）
2. 再考虑 `maxHp 90 → 105`（会动 `HeroLoadouts.lua:55` 的 `<90` 断言，需同步改）

---

## 8. 回归与实测命令

```bash
cd web

# 语法（76 文件）
node tools/check-lua.mjs

# 单套
node tools/run-lua-tests.mjs Actions
node tools/run-lua-tests.mjs HeroLoadouts

# 全量 14 套（必须在 web/ 目录下跑，仓库根跑会 SIGTERM）
node tools/run-lua-tests.mjs

# 重建清单（由主控统一执行，实施者不要跑）
node tools/gen-manifest.mjs
```

**探针路径注意**：`probe-run.mjs` 内部会 `process.chdir("web")`，
所以探针文件要写成 `tools/tmp/xxx.lua`，**不能**写 `web/tools/tmp/xxx.lua`。

实测探针骨架（贴脸 vs 远距各开一枪，读 `e.hp` 差值）：

```lua
local G = require("Game")
local g = G.New("female")
g.mode = "playing"; g.waveTimer = 999; g.meleeTimer = 999; g.coffeeTimer = 999
g.stapler, g.staplerTimer = 1, 0
-- 木桩：距离 60（贴脸）与 150（远距），注意 Target 要带 y
-- 循环前设一次 e.hp = 1e9，不要在循环里重置（会把伤害抹掉）
```

---

## 9. 验收清单

- [ ] `Heroes.lua:19` description 已改为霰弹表述，面板 90/156/1.30 未变
- [ ] `Game.lua:1141-1152` 发射段已替换为 4 颗弹丸 + 0.17 散布 + `fo*` 衰减字段
- [ ] `Game.lua:1047` 开火间隔已改为 `1.05 / (…*rate)`
- [ ] `Game.lua` 碰撞循环三处改动到位，`s.foTraveled` 累加在循环**外**
- [ ] `Game.lua:678` 升级卡文案已更新；`:706`（许宁口径）**保持不变**
- [ ] `BurstImpactFemale` **一个字都没改**（`tests/Actions.lua:305-307` 必须原样通过）
- [ ] `tests/Actions.lua:217` **保持原样**（门禁后仍走老分支，`math.min(3, level)` 不变）
- [ ] 新增两条霰弹断言（弹丸数/散布 + 距离衰减）
- [ ] `check-lua.mjs` 通过
- [ ] 全量 `run-lua-tests.mjs` 14 套全绿
- [ ] `scripts/` 镜像与 `web/lua/` 逐字一致（`diff` 校验）
- [ ] 实测记录：F1 / F3 贴脸一枪的击杀数、存活秒数、45 秒清怪数
- [ ] 实测记录：贴脸打 bomber 后是否被击退到 46px 之外
- [ ] **未执行** `gen-manifest.mjs`（由主控统一重建）

---

## 10. 实测记录（实施后填写）

| 项目 | 改前 | 改后 | 备注 |
|---|---|---|---|
| L1 贴脸单发合计 | 32.5 | | 目标 ≈72.8 |
| L1 单体 DPS（贴脸） | 50.3 | | 目标 ≈69.3 |
| L4 贴脸单发合计 | 130（3×4 pierce） | | 目标 182 |
| 60 秒击杀 | 44 | | 目标 ≥44，不要求更高 |
| 45 秒三层清怪 | 37 / 38 / 29 | | 允许下降，但不能低于周序改后（15/21/14）的 1.5 倍 |
| F1 存活秒数 | | | 目标 ≥30 |
| 贴脸打 bomber 击退距离 | ~7px | | 目标 ≥31px，需 > 46px 脱出自爆圈 |
