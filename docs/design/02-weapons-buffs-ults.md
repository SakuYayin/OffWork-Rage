# 02 战斗系统设计：男女主大招重制 · 五把新武器 · 20+ 通用 BUFF · 五选一

> 项目：《下班！别拦我》(OffWork-Rage) ｜ 文档版本 v1.0 ｜ 覆盖原始需求第 2、3、5 条
> 权威代码基线：`E:/xiabandemo/OffWork-Rage/web/lua/`（本文所有行号均指该目录）
> 约束：纯 Lua / fengari-web 32 位整数语义 / 测试全绿（任务书写「17 个套件」，实测 `web/lua/tests/` 有 **19** 个 .lua 文件，本文按 19 个逐条核对，见 §9.1）/ 美术临时复用现有资产 / 尺寸走 InterfaceScale
> 篇幅：2127 行 ｜ 数值全部可对拍（每条 DPS 都给了公式，每条断言都给了文件:行号）

---

## 目录

- [1. 现状分析](#1-现状分析)
- [2. 五把新武器设计](#2-五把新武器设计)
- [3. 伤害曲线对比](#3-伤害曲线对比)
- [4. 动画 / 特效 / 动作 / 音效清单](#4-动画--特效--动作--音效清单)
- [5. 男女主大招差异化](#5-男女主大招差异化)
- [6. 20+ 通用 BUFF 与「三选一改五选一」](#6-20-通用-buff-与三选一改五选一)
- [7. 需要新增/修改的代码接口](#7-需要新增修改的代码接口)
- [8. 实施拆分与工作量](#8-实施拆分与工作量)
- [9. 回归风险与旧断言改动清单](#9-回归风险与旧断言改动清单)
- [10. 参考来源](#10-参考来源)

## 1. 现状分析

### 1.1 代码定位索引（本文所有行号以 `web/lua/` 为根）

| 关注点 | 文件:行 | 说明 |
| --- | --- | --- |
| 武器主循环 | `Game.lua:516-540` | `local function UpdateWeapons(g, dt)`，三把武器各自独立冷却 |
| 命中结算入口 | `Game.lua:544-592` | `local function ActionImpact(g, action)`，ActionState 的 onImpact 回调 |
| 伤害最终结算 | `Game.lua:291-327` | `function Game.Hit(g, e, damage, nx, ny, force)` |
| 玩家受击 | `Game.lua:272-289` | `function Game.TakeDamage(g, amount)` |
| 大招入口 | `Game.lua:329-336` | `function Game.Burst(g)` |
| 大招结算 | `Game.lua:338-351` | `local function BurstImpact(g)` |
| 升级池定义 | `Game.lua:353-367` | `local UPGRADES`（12 条）+ `Game.upgradeDefs = UPGRADES` |
| 升级候选生成 | `Game.lua:369-394` | `local function LevelUp(g, source)` |
| 升级选择应用 | `Game.lua:396-430` | `function Game.Choose(g, index)` |
| 弹丸扫掠命中 | `Game.lua:715-760` | `UpdateShots`，内含 `SegmentHit` 调用 |
| 圆-线段求交 | `Game.lua:701-713` | `local function SegmentHit(px, py, radius, ax, ay, bx, by)` → `t` 或 nil |
| 动作时序协议 | `ActionState.lua:20-27` | `TIMINGS` 5 条 + `ORDER` 5 项 |
| 动作起手 | `ActionState.lua:76-90` | `ActionState.Start(g, name, faceX, faceY, rate)` |
| 武器手绘 | `Draw.lua:146-192` | `local function Keyboard(x, y, angle, scale)` 纯程序化绘制 |
| 特效绘制 | `Draw.lua:194-231` | `local function Effects(g)`，按 kind 分支 |
| 装备槽 UI | `HudUI.lua:42-60` | 写死 `{"keyboard","coffee","stapler"}` 三个槽 |
| BUFF 图标带 | `HudUI.lua:83-90` | 遍历 `Game.upgradeDefs`，过滤计数 > 0 |
| 三选一卡片 | `UpgradeUI.lua:14-42` | 逐 `ipairs(g.choices)` 建卡片，底部文案写死「1 / 2 / 3」 |
| 键盘选卡 | `main.lua:376-381` | 只接 `KEY_1/KEY_2/KEY_3` |
| 大招按钮 | `main.lua:279` | `burstButton:SetDisabled(game.rage<100 or game.mode~="playing")` |

### 1.2 现有武器真实参数（逐字核对源码，非估算）

| 武器 | 解锁 & 上限 | 单次基础伤害 | 冷却公式 | 命中形状 / 射程 | 命中判定实现 | 附加效果 |
| --- | --- | --- | --- | --- | --- | --- |
| **keyboard 键盘**（初始） | `Game.New` 起手即 1 级，无需解锁；`attack` 强化最多叠 3 次（`Game.lua:380` `count < 3`） | **27**（`Game.lua:555`） | `max(action.duration, 0.64/attackSpeed)`（`Game.lua:526`）。攻速 1.00 时 action.duration=0.42，攻速 ≥1.52 后由 `0.64/attackSpeed` 接管 | 触发距离 `106*range + target.radius`；命中圆半径 `100*range`，扇区条件 `ex*nx+ey*ny > -0.05`（约 ±93° 前方半圆，全角 185.7°） | 遍历 `g.enemies` 算距离 + 点积 + `Visible` 视线（`Game.lua:551-558`） | 击退 150；`Effect("slash")` 弧线；`Sound("swing")`，命中追加 `Sound("hit")` + `shake=2.5` |
| **stapler 订书机** | `stapler > 0` 后生效；上限 **4 级**（`count < 4`），商店可买 1 级（45 币） | **林夏（主武器）** 每颗 **12 + 2*stapler**；其他角色单发 **20 + 5*stapler** | 林夏 `1.05 / (1 + 0.10*stapler)`：Lv1 1.05s → Lv4 0.81s；其他角色 `0.75 / (1 + 0.16*stapler)`：Lv1 0.647s → Lv4 0.457s | **林夏（主武器）走霰弹**：`3+stapler` 颗（4/5/6/7），散布 `0.17` rad，弹速 **360**、`life=0.46` → 射程 **166**；`pierce` L1-2 为 1、L3+ 为 2；40px 内满伤、线性衰减到 **35%**；击退 **280**。**其他角色**：`count = min(3, stapler)` 发，偏移 `0.14` rad，弹速 530、`life=1.5` → 射程 795，`pierce = stapler` | `UpdateShots` 扫掠：`Navigation.Trace` 先撞墙 → `SegmentHit` 求 `t` → 按 `t` 排序 → `pierce` 递减 | `Sound("staple")`；无击退特化（force 65） |
| **coffee 咖啡** | `coffee > 0` 后生效；上限 **3 级**（`count < 3`） | 每 tick **10 + 5*coffee**，`tick=0.4s` → 每秒 2.5 跳 | `3.3 / (1 + 0.15*coffee)`（`Game.lua:537`）：Lv1 2.87s → Lv3 2.29s | 落点池半径 `48 + 14*coffee`（Lv1 62 → Lv3 90），池 `life=3.6s`；落点用 `Navigation.Trace` 截断视线后 `Project` | 池内每 0.4s 对 `d < radius + e.radius` 且 `Visible` 的敌人结算（`Game.lua:770-780`） | `Effect("coffee")` 金环；强制 0 击退；多池可共存并**各自独立 tick**（同点双池 = 双倍 DPS） |
| **burst 拒绝加班**（大招） | `rage >= 100`；释放后 `rage = 0` | **125**（`Game.lua:345`），吃 `g.damage` 与暴击 | 无冷却，纯怒气；怒气来源：被动 **+2.5/s**、击杀 **+3**（甩锅 pot **+7**）、受伤 **+12** | 以玩家为圆心半径 **260 + e.radius** 的全向圆 | 距离 + `Visible`（`Game.lua:342-347`） | 清空全部 `hostileShots`；`hitStop=0.065`、`shake=9`；击退 420；玩家无敌 1.2s；`Effect("burst")` + 45 金粒子 |

> **口径说明**：`Game.Hit` 中实际伤害 = `floor(damage * g.damage * (crit and 1.8 or 1))`（`Game.lua:293-295`）。因此上表「基础伤害」是**乘区之前**的数值，与角色 `Heroes.damage`（男 0.85 / 女 1.30）和全局 `g.damage` 叠乘。

### 1.3 命中判定原语（新武器必须复用这三套，不得另造）

| 原语 | 签名 | 适用武器类型 | 复用要点 |
| --- | --- | --- | --- |
| **A. 扇区近战** | 无独立函数，模式写在 `ActionImpact` 的 keyboard 分支 | 近战 / 重装挥击 | `Direction` 取向量 → 距离判断 → 点积判扇区 → `Visible` 过滤 → `Game.Hit` |
| **B. 弹丸扫掠** | `SegmentHit(px,py,radius,ax,ay,bx,by) -> t|nil`（`Game.lua:701`） | 远程 / 激光 | 必须先 `Navigation.Trace` 取 `wallT` 挡墙，再按 `t` 排序、`pierce` 递减，避免「穿墙 + 穿透顺序颠倒」两类 bug（`tests/HeroRules.lua:311-313` 已锁死这条） |
| **C. 圆形区域 DoT** | `g.pools` 表 + `UpdateShots` 内 tick 循环 | 魔法 / 燃烧地面 | 每 tick 判定 `d < radius + e.radius` 且 `Visible`；`tests/HeroRules.lua:307-309` 锁死「咖啡池不能穿墙」 |

**结论**：新武器只需要新增 `SHOT`/`POOL` 数据的字段（`behavior`、`tickDamage`、`slow`、`pierce`、`actionSerial`），**不需要新写碰撞函数**。

### 1.4 现有升级池结构（12 条，顺序即数组下标，**不可改动前 12 项顺序**）

`Game.lua:353-366` 的 `UPGRADES` 是纯数组，下表「下标」即 `Game.upgradeDefs[i]`：

| 下标 | id | 标题 | tag | 效果（累加） | 上限（`count < X`） |
| --- | --- | --- | --- | --- | --- |
| 1 | `stapler` | 流程钉死 | 武器 / 订书机 | `g.stapler += 1`（→ 穿透+1、发数+1） | 4 |
| 2 | `coffee` | 冰美式续命 | 武器 / 咖啡杯 | `g.coffee += 1`（→ 半径+14、每跳+5、冷却-） | 3 |
| 3 | `damage` | 拒绝内耗 | 伤害强化 | `g.damage += 0.25` | 3 |
| 4 | `speed` | 到点就跑 | 移动强化 | `player.speed *= 1.15` | 3 |
| 5 | `attack` | 键盘侠 | 攻速强化 | `g.attackSpeed += 0.22`（仅 keyboard 吃） | 3 |
| 6 | `range` | 这不归我管 | 范围强化 | `g.range += 0.2`（仅 keyboard 吃） | 3 |
| 7 | `magnet` | 带薪摸鱼 | 拾取强化 | `g.magnet += 70` | 3 |
| 8 | `health` | 先照顾自己 | 生命强化 | `maxHp += 25`，`hp += 35` | 3 |
| 9 | `regen` | 工间休息 | 持续恢复 | `g.regen += 1.2` /s | 3 |
| 10 | `armor` | 拒绝背锅 | 防御强化 | `g.armor += 3`（减伤，最低 1） | 3 |
| 11 | `crit` | 已读乱回 | 暴击强化 | `g.crit += 0.15`（暴击 ×1.8） | 3 |
| 12 | `rage` | 忍无可忍 | 立即爆发 | `rage = 100`，`hp += 20` | **无上限** |

**现有候选池生成逻辑（`Game.lua:377-391`）**：

```lua
for _, u in ipairs(UPGRADES) do
    local count = g.upgrades[u.id] or 0
    if u.id == "rage" or count < (u.id == "stapler" and 4 or 3) then candidates[#candidates+1] = u end
end
-- 首两次升级且尚未持有任何武器 → 硬编码 {UPGRADES[1], UPGRADES[2], UPGRADES[3]}
if g.level <= 2 and g.stapler == 0 and g.coffee == 0 then
    g.choices = { UPGRADES[1], UPGRADES[2], UPGRADES[3] }
else
    for _ = 1, math.min(3, #candidates) do
        local index = math.random(1, #candidates)
        g.choices[#g.choices+1] = table.remove(candidates, index)
    end
end
```

问题清单（本文要解决的）：

1. **无权重**：12 条等概率抽，武器类只有 2 条（16.7%），构筑多样性低。
2. **无稀有度**：`rage`（直接满怒）与 `magnet` 同级出现，价值差 5 倍以上。
3. **无保底**：连抽 3 次全出 `magnet/speed/range` 的纯功能局完全可能。
4. **固定 3 张**：`math.min(3, #candidates)` 写死。
5. **`attack`/`range` 只作用于 keyboard**（`ActionState.lua:76` 的 `speed` 只对 `name=="keyboard"` 生效，`ActionImpact` 里 `104*g.range` 也只出现在 keyboard 分支）——新增武器若不改造，会全部变成「攻速/范围强化无效」的死构筑。

### 1.5 大招现状与男女共用的确切证据

```lua
function Game.Burst(g)
    if g.mode ~= "playing" or g.rage < 100 or ActionState.Active(g, "burst") then return false end
    local action = ActionState.Start(g, "burst", g.player.faceX, g.player.faceY)
    if not action then return false end
    g.rage, g.player.invuln = 0, math.max(g.player.invuln, 1.2)
    print("[动作] 拒绝加班蓄力 serial=" .. action.serial)
    return true
end
```

全文**没有任何 `g.heroId` 分支**，`heroId` 只在 `Game.New` 里用来查 `Heroes.Get`。`Heroes.lua:13-19` 二者的差异只有 `maxHp/speed/damage` 三个数值，纯数值差异、零机制差异。这正是需求「男女主要不同的大招才可以」要解决的问题。

### 1.6 现状硬约束（新设计必须绕开的坑）

| 约束 | 出处 | 对新设计的影响 |
| --- | --- | --- |
| 只有 `hurt`/`burst` 会抢主姿态 | `ActionState.lua:92` | 新武器只能走 `Select` 排队，**不能**抢主姿态，否则 `tests/Actions.lua:243`「键盘主姿态稳定」直接红 |
| 只有 `keyboard` 吃攻速缩放 | `ActionState.lua:77,80,87` | 攻速强化要覆盖新武器，必须把硬编码 `name=="keyboard"` 改成白名单 |
| 攻击范围 `g.range` 只写在 keyboard 分支 | `Game.lua:549,553` | 新武器要有自己的 `rangeScale` 语义 |
| BUFF 图标 `Skin.Icon("buff", id)` 遇未知 id 会 `assert` 崩溃 | `UISkin.lua` `Skin.Sprite(d, assert(d.frames[id], ...))` | **20+ 新 BUFF 必须给 `icon` 字段映射到 buff 图集 12 帧之一**，否则 HUD 直接崩 |
| buff 图集只有 12 帧 | `InterfaceIcons.lua` | 同上，见 §6.5 图标映射表 |
| 装备槽写死三把 | `HudUI.lua:42` | 展示新武器需要改成动态列表 |
| 键盘只接 1/2/3 | `main.lua:377-379` | 五选一必须补 `KEY_4/KEY_5` |
| 音效 **15 个 cue 只对应 11 个 wav 文件**（cue 复用文件、只改 gain/pitch） | `Audio.lua:70-85`（如 `coffee` 与 `swing` 同为 `office_keyboard_swing.wav`，`boss` 与 `burst` 同为 `office_rage_burst.wav`） | 新武器/新大招**不能新增音频文件**，只能在 `cues` 表里加新 key 并复用现有 11 个 wav + 调 `pitch/gain`，详见 §4.4 |



## 2. 五把新武器设计

### 2.0 统一设计约定（五把共用，先读这一节）

| 议题 | 约定 | 理由 |
| --- | --- | --- |
| **条目位置** | 五个新武器作为 `UPGRADES` 数组的 **index 13–17** 追加，**绝不插入前 12 项中间** | `tests/HeroRules.lua:137` 用 `Game.upgradeDefs[4]` 断言 speed、`:139` 用 `[8]` 断言 health，前 12 项顺序是硬编码契约 |
| **等级字段** | 新增 `g.weapons = { thermos = 0, paperclip = 0, pie = 0, laser = 0, extinguisher = 0 }`，与 `g.upgrades[id]` 同步自增（`upgrades` 记录「拿过几次」用于 HUD/保底，`weapons` 记录「当前等级」用于伤害公式） | 现有 `g.stapler`/`g.coffee` 就是这种双轨写法，保持一致 |
| **上限** | 统一 `maxLevel = 5` | 五条升级曲线要对齐比较 |
| **动作接入** | 全部走 `ActionState.Start(g, "<name>", nx, ny, rate?)`，在 `TIMINGS` 里新增条目，在 `ORDER` 里 **追加到 `"coffee"` 之后** | `tests/Actions.lua:243` 断言「三武器同帧独立起手，键盘主姿态稳定」，只有追加才不改变 `ORDER` 里 keyboard 的相对优先级 |
| **主姿态** | 五把新武器**都不抢主姿态**（只有 `hurt`/`burst` 抢，见 `ActionState.lua:92`），也不加入该分支 | 同帧多武器齐射时由 `Select` 排队，避免新武器把玩家动作卡死 |
| **攻速缩放** | 把 `ActionState.lua:77/80/87` 的硬编码 `name == "keyboard"` 改为 `TIMINGS[name].scaled == true`；白名单 = `keyboard / thermos / paperclip / laser`，`pie / extinguisher` 为 `false` | 魔法（读条）与重装（弹夹+装填）靠自身节奏，被攻速同步缩放会破坏其强度定义 |
| **绘制** | 全部用 `Draw.lua` 程序化绘制，照抄 `Keyboard(x,y,angle,scale)`（`Draw.lua:146-192`）的 `nvgSave→Translate→Rotate→Scale→Rect` 套路 | 项目**没有**任何新武器图；⚠️资产缺失见 §4.5 |
| **伤害结算** | 一律走 `Game.Hit(g, e, damage, nx, ny, force)`，绝不直接改 `e.hp` | 保证暴击、`g.damage` 乘区、击退、死亡掉落、怒气、连击统计全部生效（`Game.lua:291-327`） |

---

### 2.1 近战 · 保温杯警告（`thermos`）

> 世界观：开会时把 1.5L 保温杯往桌上一顿，枸杞水溅出去把周围人烫退。「别催，我在泡第三遍。」

| 项 | 值 |
| --- | --- |
| id / 名称 | `thermos` / 保温杯警告 |
| 定位 | 近战 · 高爆发 · 极短射程 · 强击退 |
| 解锁 | 升级池抽到即 `weapons.thermos = 1` |
| 上限 | 5 级 |
| 动作名 | `"thermos"` |
| **TIMINGS** | `{ windup = 0.16, impactAt = 0.18, impactEnd = 0.30, duration = 0.72, scaled = true }` |
| 命中形状 | **扇形**：半径 `R = 96 + 6*lv`，半角 **55°**（`dot(nx,ny, dir) > 0.574`），全部命中不限数量 |
| 判定原语 | 复用 §1.3 原语 **A（扇区近战）**，把 keyboard 的 `-0.12`（±97°）收紧为 `0.574`（±55°），半径由 `96+6*lv` 替代 `104*range` |
| 冷却 | `1.15 / attackSpeed`（Lv1 attackSpeed=1.0 → 1.15s） |
| 穿透 | 扇区内**全部**敌人（无数量上限，天然穿透） |
| 暴击 | 走全局 `g.crit`，暴击 ×1.8 |
| 击退 | 第 1/2 段 `260`，第 3 段 `468` |
| **特殊机制：三段连击（`combo`）** | 每次命中把 `g.thermosCombo = (g.thermosCombo or 0) + 1`，到 3 归零。第 3 段伤害 **×1.45**、击退 **×1.8**、并给受击敌人挂 `e.stun = 0.25`（硬直，`UpdateEnemies` 中 `if (e.stun or 0) > 0 then e.stun = e.stun - dt; 跳过移动`） |
| **特殊机制：枸杞溅射** | 第 3 段命中 ≥1 个敌人时，额外对**玩家正前方 140 距离的点**生成半径 30 的小 pool，持续 1.2s，每 0.4s 造成 `6 + 2*lv` 伤害（复用 §1.3 原语 **C**）。这是「越打越烫」的持续压迫感，也把近战从「纯爆发」补成「爆发 + 短压制」 |

**伤害曲线（基础伤害 = 乘 `g.damage` 之前的数值）**

| 等级 | 基础伤害 | 第 3 段伤害（×1.45） | 冷却(s) | 平均 DPS | 扇区半径 | 枸杞 pool 每跳 | 需要几次升级 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Lv1 | **46** | 67 | 1.15 | **46.0** | 102 | 8 | 1 |
| Lv2 | **57** | 83 | 1.15 | **57.0** | 108 | 10 | 2 |
| Lv3 | **70** | 102 | 1.15 | **70.0** | 114 | 12 | 3 |
| Lv4 | **85** | 123 | 1.15 | **85.0** | 120 | 14 | 4 |
| Lv5 | **104** | 151 | 1.15 | **104.0** | 126 | 16 | 5 |

> 平均 DPS 恰好等于基础伤害，因为三段连击 (1+1+1.45)/3 = 1.15 倍伤害均摊到 3×1.15s = 3.45s 的周期里，两个 1.15 互相抵消——这是刻意的，让数值表可验算。

**升级曲线设计意图**：Lv1→Lv5 成长 `×2.26`（46→104），是五把里**斜率最陡**的第二名（第一名是激光 ×2.8）。因为近战要贴脸，前期收益低、后期靠「一砸半管血」的爽感回收风险成本。

**接入代码位置**
- `Game.New`：新增 `thermos = 0`（`g.weapons.thermos`）、`g.thermosTimer = 0`、`g.thermosCombo = 0`
- `UpdateWeapons`（`Game.lua:516`）：追加第 4 个分支
- `ActionImpact`（`Game.lua:544`）：新增 `elseif action.name == "thermos" then`
- `UpdateEnemies`（`Game.lua:641`）：在速度计算前插入 `stun` 早退

---

### 2.2 远程 · 回形针弹弓（`paperclip`）

> 世界观：把回形针掰开、套上橡皮筋，射程惊人。「工位三米内的一切都是武器。」

| 项 | 值 |
| --- | --- |
| id / 名称 | `paperclip` / 回形针弹弓 |
| 定位 | 远程 · 高频 · 低单发 · 中远射程 · 稳定输出 |
| 上限 | 5 级 |
| 动作名 | `"paperclip"` |
| **TIMINGS** | `{ windup = 0.06, impactAt = 0.08, impactEnd = 0.14, duration = 0.26, scaled = true }` |
| 命中形状 | **单发细长弹丸**：弹速 **640**，`life = 0.62`，理论射程 **397** |
| 判定原语 | 复用 §1.3 原语 **B（弹丸扫掠）**，与 stapler 走完全相同的 `g.shots` 管线（`Navigation.Trace` 挡墙 → `SegmentHit` → 按 `t` 排序 → `pierce` 递减） |
| 冷却 | `0.34 / attackSpeed`（Lv1 → 0.34s，相当于 2.9 发/秒；attackSpeed 满配 3.0 时 → 0.113s，8.8 发/秒） |
| 穿透 | Lv1–2：**0**；Lv3–4：**1**；Lv5：**2** |
| 暴击 | 走全局 `g.crit` |
| 击退 | 固定 `70`（低，靠频率而非力度） |
| **特殊机制：第 5 发追踪针** | `g.paperclipCount` 每发 +1，`% 5 == 0` 时该发打上 `homing = true`：`UpdateShots` 中该 shot 每帧用 `Nearest` 改朝向（转向速率 `6 rad/s`，最大偏转 ±35°），伤害 **×0.8**、穿透 **+1**、`life = 1.0`（射程 640）。这是「稳定流里的一个小惊喜」，不改变整体 DPS 预期 |
| **特殊机制：命中减速** | 命中敌人挂 `e.slow = max(e.slow or 1, 0) ...` → 实际实现为 `e.slowTimer = 0.6`，`UpdateEnemies` 中速度系数 `×0.82`（与咖啡池的 `0.48` 可叠乘，叠乘后下限 0.30） |

**伤害曲线**

| 等级 | 基础伤害 | 冷却(s) | 单体 DPS | 穿透 | 追踪针伤害 | 需要几次升级 |
| --- | --- | --- | --- | --- | --- | --- |
| Lv1 | **15** | 0.34 | **44.1** | 0 | 12 | 1 |
| Lv2 | **19** | 0.34 | **55.9** | 0 | 15 | 2 |
| Lv3 | **24** | 0.34 | **70.6** | 1 | 19 | 3 |
| Lv4 | **30** | 0.34 | **88.2** | 1 | 24 | 4 |
| Lv5 | **37** | 0.34 | **108.8** | 2 | 30 | 5 |

**多目标 DPS（每发实测命中数）**：穿透 1 时，直线排布 2 个敌人 → DPS **×2**；穿透 2、3 个敌人 → **×3**。这是「稳定远程」的价值锚：单目标垫底，密集阵型下反超。

**升级曲线设计意图**：斜率 `×2.47`（15→37），线性、无拐点、无机制突变——刻意做成「最无脑最稳」的一把，作为新手和「不想要操作复杂度」玩家的兜底。Lv3/Lv5 的穿透拐点提供两个明确的「变强时刻」。

**接入代码位置**
- `Game.New`：`g.weapons.paperclip = 0`、`g.paperclipTimer = 0`、`g.paperclipCount = 0`
- `UpdateWeapons`：第 5 分支
- `ActionImpact`：`elseif action.name == "paperclip" then` → push `g.shots`
- `UpdateShots`（`Game.lua:715`）：新增 homing 修正段（仅对 `s.homing` 的 shot 生效，不影响现有 stapler 弹丸）

---

### 2.3 魔法 · 画饼充饥（`pie`）

> 世界观：老板画的饼终于有实体了。抛出去，砸在地上，饼越画越大，站在饼里的人都得跟着「一起加油」。

| 项 | 值 |
| --- | --- |
| id / 名称 | `pie` / 画饼充饥 |
| 定位 | 魔法 · AOE · 抛物线 · 落点持续伤害 |
| 上限 | 5 级 |
| 动作名 | `"pie"` |
| **TIMINGS** | `{ windup = 0.42, impactAt = 0.46, impactEnd = 0.62, duration = 1.05, scaled = false }` |
| 命中形状 | **两段**：①落点圆形爆炸，半径 `56 + 5*lv`；②爆炸后原地留下「饼」池，半径 `70 + 8*lv`，`life = 4.2s` |
| 判定原语 | ①爆炸用**一次性圆形遍历**（同 `BurstImpact` 的写法，`Game.lua:342-347`）；②饼池复用 §1.3 原语 **C**，与咖啡池共用 `g.pools` 与 tick 循环，靠 `pool.kind = "pie"` 区分伤害 |
| 射程 | 落点距离 `clamp(distance, 60, 300)`，方向取 `Nearest` 目标；**落点必须过 `Navigation.Trace` 视线截断**（`tests/HeroRules.lua:307-309` 锁死「不能穿墙」） |
| 冷却 | `2.05 / (1 + 0.08*lv)`：Lv1 1.90s → Lv5 1.46s |
| 穿透 | 不适用（AOE，全命中） |
| 暴击 | **独立暴击判定**：每个受击目标单独 `math.random() < g.crit`，由 `Game.Hit` 内部完成 |
| 击退 | 爆炸 `110`，饼池 `0`（池不推人，避免把敌人推出池外） |
| **特殊机制：画饼接力** | 爆炸命中 **≥3 个敌人** 时，在落点周围 `120` 距离内生成**第二个**小饼池（半径 = 主池 ×0.6，伤害 ×0.5，`life = 2.4s`）。判定用 `count` 累加，最多生成 1 个补充池，避免链式爆表 |
| **特殊机制：饼会变大** | 主饼池每被 tick 命中一次，`radius += 1.2`，上限 `60 + 8*lv` 的额外增长（即 Lv5 主池最大 `70+40 + 60 = 170` 半径）。这让「站桩输出」在 4.2s 内越来越危险 |

**伤害曲线（单体全吃满：1 次爆炸 + 4.2s 内 10 跳）**

| 等级 | 爆炸伤害 | 每跳伤害 | 跳数 | 单体满伤合计 | 冷却(s) | 单体 DPS | 爆炸半径 | 饼池半径 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Lv1 | **52** | **6** | 10 | 112 | 1.90 | **58.9** | 61 | 78 |
| Lv2 | **66** | **8** | 10 | 146 | 1.77 | **82.5** | 66 | 86 |
| Lv3 | **83** | **10** | 10 | 183 | 1.65 | **110.9** | 71 | 94 |
| Lv4 | **104** | **12** | 10 | 224 | 1.55 | **144.5** | 76 | 102 |
| Lv5 | **130** | **15** | 10 | 280 | 1.46 | **191.8** | 81 | 110 |

**多目标系数**：饼池对 3 个敌人的实际 DPS = 单体 ×3（无衰减）。这是全部五把里**多目标最强**的一把，Lv5 三目标理论 **575 DPS**，但要求敌人站桩——与「办公室肉鸽」里成群的 ghost/paper 强正相关。

> 注意：上表「跳数 10」= `life 4.2s / tick 0.4s`。`UpdateShots` 的 pool tick 是**全局统一的 0.4s 节拍**（`Game.lua:770`），所以这个数字是硬的、可验算的。

**升级曲线设计意图**：斜率 `×3.38`（52→130 爆炸，58.9→191.8 DPS）是**五把里最陡的**。因为 AOE 数值必须靠后期拉回单体劣势：Lv1 单体 58.9 只比键盘 42.2 高一点，但 Lv5 单体 191.8 就明显超过远程的 108.8。设计上它是「要么前期忍痛、要么别拿」的高方差武器。

**接入代码位置**
- `Game.New`：`g.weapons.pie = 0`、`g.pieTimer = 0`
- `UpdateWeapons`：第 6 分支，写 `action.targetX, action.targetY`
- `ActionImpact`：`elseif action.name == "pie" then` → 爆炸遍历 + push pool
- `UpdateShots` 池循环：`elseif pool.kind == "pie" then damage = ...`

---

### 2.4 激光 · 激光打印（`laser`）

> 世界观：卡纸三天的打印机终于通了电，光敏鼓一转，把挡路的人「打印」成齑粉。「正在打印…请勿关机。」

| 项 | 值 |
| --- | --- |
| id / 名称 | `laser` / 激光打印 |
| 定位 | 激光 · **持续单体引导** · 高精度 · 无 AOE |
| 上限 | 5 级 |
| 动作名 | `"laser"` |
| **TIMINGS** | `{ windup = 0.22, impactAt = 0.28, impactEnd = 0.90, duration = 1.20, scaled = true }` ⚠️ 见下方「时序缩放陷阱」 |
| 命中形状 | **一条直线光束**：从玩家指向锁定目标，长度 = `min(距离, 420)`，宽度 **12**（用 `SegmentHit` 判定宽 12 的胶囊） |
| 判定原语 | 复用 §1.3 原语 **B（弹丸扫掠）**，但每 tick 重新求一次 `SegmentHit`，且**先做 `Navigation.Trace` 截断光束**（激光被家具挡住会缩短，符合世界观） |
| 射程 | `420`，且必须 `Visible` |
| 冷却 | **固定 1.45s**，从起手开始计，与 `attackSpeed` 无关（`scaled` 只影响 `duration`，不影响这条固定冷却；见陷阱说明） |
| 伤害 | **每 0.12s 一跳，共 6 跳**（`impactAt 0.28 → impactEnd 0.90` 恰好 0.62s ≈ 5.17 跳，取 6 跳由 `laserTick` 累加器控制） |
| 穿透 | **0**：光束只打「第一个」敌人（`SegmentHit` 取最小 `t`），后面的敌人不受伤 |
| 暴击 | **每跳独立判定**（6 跳 = 6 次 `g.crit` 机会，暴击期望比单发武器更平滑） |
| 击退 | `12`（几乎不推，把敌人固定在光束里） |
| **特殊机制：过热聚焦** | 对**同一目标**累计 ≥4 跳后，第 4/5/6 跳伤害 **×1.25**。目标死亡立刻 `Nearest` 重新锁定，聚焦层数清零 |
| **特殊机制：穿透装甲** | 忽略 boss 的 `armor` 减免（`Game.Hit` 不做减伤，减伤只在 `TakeDamage`；所以此机制实现为「对 `e.kind == 5` 的敌人伤害 ×1.15」——把「打印机能搞定所有卡纸」做成对 Boss 特化） |

**⚠️ 时序缩放陷阱（实现必读）**：`ActionState.Start` 用 `rate` 缩放 `impactAt/impactEnd/duration`（`ActionState.lua:80-82`），而激光的「6 跳」由绝对时间累加器控制。若 attackSpeed 把 `impactAt` 压到 0.28/`attackSpeed`，跳数会变少 → DPS 反而下降。**解法**：激光的 6 跳用「进度百分比」驱动，`laserTick` 在 `action.time / action.duration ∈ [0.23%, 0.75%]` 区间内按 `(action.duration - 0.10) / 6` 间隔触发，与缩放无关。

**伤害曲线**

| 等级 | 每跳伤害 | 六跳合计 | 聚焦后（第 4–6 跳 ×1.25） | 冷却(s) | 单体 DPS | 对 Boss（×1.15） |
| --- | --- | --- | --- | --- | --- | --- |
| Lv1 | **10** | 60 | 67.5 | 1.45 | **41.4** | **47.6** |
| Lv2 | **13** | 78 | 87.8 | 1.45 | **53.8** | **61.9** |
| Lv3 | **17** | 102 | 114.8 | 1.45 | **70.3** | **80.9** |
| Lv4 | **22** | 132 | 148.5 | 1.45 | **91.0** | **104.7** |
| Lv5 | **28** | 168 | 189.0 | 1.45 | **115.9** | **133.3** |

**升级曲线设计意图**：斜率 `×2.80`（10→28），是五把里**最陡**。但它的绝对 DPS 在 Lv1 是五把里**最低**（41.4，略低于键盘 42.2），因为 6 跳需要目标站住不动 0.62s——对散开的 ghost（speed 56）经常只有 3–4 跳命中。作为补偿，它给了两个清晰的正反馈：Lv1 就能对 Boss 造成 47.6 DPS（`×1.15`），以及暴击每跳独立判定让后期 `crit` BUFF 的收益被放大到 `1 + 0.8*p` 的 6 次方期望。

**接入代码位置**
- `Game.New`：`g.weapons.laser = 0`、`g.laserTimer = 0`
- `UpdateWeapons`：第 7 分支，需 `not ActionState.Active(g,"laser")`
- `ActionImpact`：**只做起手锁定**（`action.laserTarget = target`）+ 一次性 `Sound`
- **新增 `Game.UpdateLaser(g, dt)`**：在 `Game.Update` 主循环中、`UpdateWeapons` 之后调用，负责 6 跳结算与光束特效
- `Draw.lua`：新增 `LaserBeam(g)` 绘制（放在 `Effects` 之前，这样粒子能盖住光束末端）

---

### 2.5 重装 · 灭火器（`extinguisher`）

> 世界观：走廊尽头的红色钢瓶。拔销、握管、压把——「都给我冷静一下。」喷完记得摇一摇。

| 项 | 值 |
| --- | --- |
| id / 名称 | `extinguisher` / 灭火器 |
| 定位 | 重装 · 低射速 · 高单发 · 弹夹+装填 · 强击退 |
| 上限 | 5 级 |
| 动作名 | `"extinguisher"` |
| **TIMINGS** | `{ windup = 0.30, impactAt = 0.32, impactEnd = 0.52, duration = 0.90, scaled = true }` |
| 命中形状 | **单发扇形喷射弹丸**：弹速 **380**，`life = 0.42` → 射程 **160**；散布 **±22°**（`math.random(-0.384, 0.384)` 弧度）；弹丸判定半径 **10**（比 stapler 的宽，靠 `SegmentHit(px,py,10,...)` 中的 radius 参数实现） |
| 判定原语 | 复用 §1.3 原语 **B（弹丸扫掠）**，与 stapler 共用 `g.shots` |
| 射速 | **每发间隔 0.30s**（用 `g.extinguisherTimer` 独立计时，不依赖 action.duration） |
| **弹夹** | **6 发**；打空后进入**装填 1.30s**（`g.extinguisherReload`），装填期间不能射击 |
| 一个完整弹夹周期 | `6 × 0.30 + 1.30 = 3.10s` |
| 穿透 | **0**（单发单中，重装靠伤害而非穿透） |
| 暴击 | 走全局 `g.crit` |
| 击退 | **320**（五把最高，配合 0.4s `stun` 能把敌人钉在墙上） |
| **特殊机制：后坐力** | `impactAt..impactEnd` 期间（0.32→0.52s）玩家移动速度 **×0.55**，且每发给自己 `knockX/knockY` 反向 40（视觉上「顿一下」）。这条让重装成为唯一「开枪就要付出机动代价」的武器 |
| **特殊机制：干粉覆盖** | 每 6 发打空时（装填开始瞬间），在玩家正前方 100 距离生成半径 90 的干粉 pool，`life = 2.0s`，每 0.4s 造成 `每发伤害 × 0.35` 伤害，并把池内敌人 `slowTimer = 1.0`（速度 ×0.7）。这是「打空也不能白打」的补偿 |

**伤害曲线**

| 等级 | 每发伤害 | 弹夹满伤（6 发） | 一个周期 DPS | 射程 | 击退 | 干粉每跳 | 需要几次升级 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Lv1 | **42** | 252 | **81.3** | 160 | 320 | 15 | 1 |
| Lv2 | **53** | 318 | **102.6** | 160 | 320 | 19 | 2 |
| Lv3 | **65** | 390 | **125.8** | 160 | 320 | 23 | 3 |
| Lv4 | **79** | 474 | **152.9** | 160 | 320 | 28 | 4 |
| Lv5 | **93** | 558 | **180.0** | 160 | 320 | 33 | 5 |

> DPS = `6 × 每发伤害 / 3.10`。验算 Lv1：`6×42/3.10 = 81.29` ✓

**升级曲线设计意图**：斜率 `×2.21`（42→93）是五把里**最平**的，但**绝对 DPS 全表第一**（Lv1 就 81.3，超过键盘 Lv4 的 70）。这是刻意的「重装税」设计：拿了就立刻强，但成长空间小，且被 3.10s 弹夹周期 + 0.55 移动惩罚 + 160 极短射程三重限制。它的定位不是「后期核心」，而是「中期换血杀器」——在 F2/F3 敌人 `scale = 1+(floor-1)*0.45` 暴涨时（`Game.lua:200`）用它顶住一波。

**接入代码位置**
- `Game.New`：`g.weapons.extinguisher = 0`、`g.extinguisherTimer = 0`、`g.extinguisherAmmo = 6`、`g.extinguisherReload = 0`
- `UpdateWeapons`：第 8 分支，需处理 `ammo <= 0` 的装填分支（装填时**不 return**，继续走其他武器）
- `ActionImpact`：`elseif action.name == "extinguisher" then` → push 1 发 shot + 扣 ammo
- `Game.Update`：移动步态计算处插入 `if ActionState.Active(g,"extinguisher") then speedMult = 0.55 end`

---

### 2.6 五把武器的"互补性"矩阵（为什么是这五把，而不是别的五把）

| 维度 | thermos 近战 | paperclip 远程 | pie 魔法 | laser 激光 | extinguisher 重装 |
| --- | --- | --- | --- | --- | --- |
| 理想交战距离 | 0–126 | 200–397 | 60–300 | 0–420 | 0–160 |
| 单体 DPS（Lv5） | 104 | 108.8 | 191.8 | 115.9 | **180.0** |
| 多体 DPS（3 目标 Lv5） | 312 | 326 | **575** | 116 | 180 |
| 换弹/引导空窗 | 无 | 无 | 无（池持续） | **0.62s 引导中不能走位** | **1.30s 装填** |
| 对 Boss 表现 | 中（需贴脸） | 中 | 低（Boss 移动） | **高（×1.15 + 聚焦）** | **高（高单发 + 硬直）** |
| 机动代价 | 无 | 无 | 无 | 引导期减速 30% | **射击期 ×0.55** |
| 拯救场景 | 被围（击退+硬直） | 长走廊风筝 | 密集波次 | 单体大怪 / Boss | 血量暴跌的换血 |
| 吃 `attackSpeed` | ✓ | ✓ | ✗ | ✓ | ✓ |
| 吃 `g.range` | ✓（扇区半径） | ✗（固定射程） | ✓（落点距离） | ✓（光束长度） | ✗（固定 160） |

**互补性结论**：五把武器在「距离 × 目标数 × 机动代价」三维空间里各自占住一个角，任意两把组合都覆盖一个短板——不存在「上位替代」。这是相比现有三把（keyboard 免费/stapler 穿透/coffee 慢速 AOE）更严格的互补设计。



## 3. 伤害曲线对比

### 3.1 口径统一（先读，否则数字对不上）

所有 DPS 均为 **乘区之前** 的基础 DPS，计算式固定为：

```
DPS = 单次伤害 × 命中次数 / 周期
周期 = max(动作时长, 冷却)  —— 取实际瓶颈
```

- **不含** `g.damage`（伤害强化乘区）、`g.crit`（暴击期望）、`e.scale`（层数成长）、`armor`（减伤）。
- 全局乘区在 §3.5 单独列出，方便读表时心算。
- 「1 级到满级」按**升 5 次**算，但 keyboard 无等级、stapler 上限 4、coffee 上限 3，这三把按各自实际上限给列。

### 3.2 主表：单体 DPS 曲线（Lv1 → 满级）

| 武器 | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | 斜率 Lv5/Lv1 | 定位 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **keyboard 键盘**（初始，按同级攻速 1.00/1.22/1.44/1.66 计） | 42.2 | 51.5 | 60.7 | **64.3（封顶）** | 64.3 | ×1.52 | 基准线，永远可用 |
| **stapler 订书机**（单发命中，上限 L4） | 38.7 | 52.8 | 69.1 | 87.5 | — | ×2.26 | 穿透流，多目标翻倍 |
| **coffee 咖啡**（单个敌人吃满，上限 L3） | 37.5 | 50.0 | 62.5 | — | — | ×1.67 | 区域压制，群体翻 N 倍 |
| **thermos 保温杯**（近战 A/V） | **46.0** | 57.0 | 70.0 | 85.0 | 104.0 | **×2.26** | 高爆发 · 极短射程 |
| **paperclip 回形针**（远程 V） | **44.1** | 55.9 | 70.6 | 88.2 | 108.8 | **×2.47** | 稳定 · 无空窗 |
| **pie 画饼充饥**（魔法 A/E） | **58.9** | 82.5 | 110.9 | 144.5 | **191.8** | **×3.26** | AOE · 高方差 |
| **laser 激光打印**（激光 V/E） | **41.4** | 53.8 | 70.3 | 91.0 | 115.9 | **×2.80** | 持续单体 · 引导 |
| **extinguisher 灭火器**（重装 V/E） | **81.3** | 102.6 | 125.8 | 152.9 | 180.0 | **×2.21** | 低速高伤 · 弹夹 |

> **keyboard 封顶说明（易错点）**：`冷却 = max(action.duration, 0.64/attackSpeed)`（`Game.lua:526`）。攻速 1.66 时 `0.64/1.66 = 0.386 < action.duration 0.42`，因此 **被 action.duration 挡住，DPS 停在 64.3**。攻速要到 `1.52` 以上才会切换成 `0.64/attackSpeed` 主导，而 `1.52 = 1 + 0.22×2.36` 位于第 3 层与第 4 层之间 → **键盘攻速强化的第 3 层收益被吃掉一半**。这是现状 bug，本文 §9 会列为「建议修复项」（把下限从 action.duration 改成 0.36）。

### 3.3 多目标 DPS 曲线（密集波次 / 走廊列队）

| 武器 | 2 目标（Lv5） | 3 目标（Lv5） | 5 目标（Lv5） | 说明 |
| --- | --- | --- | --- | --- |
| thermos | 208（扇区内全中） | 312 | 520 | 扇区 ±55° 内**不限数量**，理论无上限 |
| paperclip | 217.6（穿透 2） | 326.4 | 326.4（受 3 次命中上限） | 穿透 2 = 最多打 3 个 |
| pie | 383.6 | **575.3** | 959 | 池半径 110，敌人越密越赚，无衰减 |
| laser | 115.9 | 115.9 | 115.9 | **穿透 0**，永远只打 1 个 |
| extinguisher | 180.0 | 180.0 | 180.0 | **穿透 0**，靠击退+干粉池补群体 |
| keyboard | 64.3 | 64.3 | 64.3 | 扇区内全中但基础低 |
| stapler（三发各中 1） | 87.5 | 87.5 | 87.5 | 穿透 L4=4，理论上限更高 |

**结论（平衡验证）**：

1. **近战高爆发低射程** ✓ thermos Lv5 单体 104、3 目标 312，是全部近战射程（0–126）里唯一能一砸多人的武器，但站到 126 内就要承担被 `ghost` 贴身（speed 56）与 `pot` 甩锅（远程）双向压力。
2. **激光持续单体** ✓ laser 在 Lv5 单体 115.9，是**单目标最高之一**（仅次于 pie 的 191.8 与 ext 的 180.0），但 2 目标时立刻掉到并列倒数 → 纯粹的「点杀大怪」定位。
3. **重装低速高伤** ✓ ext 的 `3.10s` 周期 + `0.55` 移速惩罚 + `160` 极短射程，三重限制换来 Lv1 就 81.3 的爆发。
4. **魔法 AOE** ✓ pie 三目标 575.3 是全表**最高值**，但五目标时 pie 959 与其他武器拉开 2 倍以上 → 需要 `clearRoom` 的波次节奏（`Campaign.lua` 的 `totalWaves`）来配。
5. **远程稳定** ✓ paperclip 斜率 ×2.47、冷却固定 0.34、无弹夹无引导，是唯一「任何情况下 DPS 都不会掉」的武器。

### 3.4 曲线形状对比（用「每级增量」看设计意图）

| 武器 | L1→L2 | L2→L3 | L3→L4 | L4→L5 | 增量形状 | 设计意图 |
| --- | --- | --- | --- | --- | --- | --- |
| thermos | +11.0 | +13.0 | +15.0 | +19.0 | **递增**（凸函数） | 前期弱后期强，鼓励「先忍耐再收菜」 |
| paperclip | +11.8 | +14.7 | +17.6 | +20.6 | **递增**（凸函数） | 同上，但幅度温和，靠穿透拐点跳变 |
| pie | +23.6 | +28.4 | +33.6 | +47.3 | **强递增**（指数感） | AOE 后期必须有碾压感 |
| laser | +12.4 | +16.5 | +20.7 | +24.9 | **强递增** | 引导型武器的风险回报 |
| extinguisher | +21.3 | +23.2 | +27.1 | +27.1 | **前平后陡** | 早期即强（弹药多），后期靠单发数值 |
| keyboard | +9.3 | +9.2 | +3.6 | 0 | **封顶** | 初始武器不该抢戏 |
| stapler | +14.1 | +16.3 | +18.4 | — | 线性递增 | 与 4 级上限匹配 |
| coffee | +12.5 | +12.5 | — | — | 严格线性 | 简单可预期 |

**关键设计判断**：五把新武器**全部是凸函数（递增增量）**，现有三把是线性或封顶。这让「专精一把新武器」在数值上优于「平均分点」，从机制上推动构筑深度——玩家要么早拿早投资，要么干脆不拿。

### 3.5 全局乘区（读表时的心算工具）

| 乘区 | 来源 | 上限 | 满配系数 |
| --- | --- | --- | --- |
| 伤害 `g.damage` | `damage` BUFF +0.25/层 ×3 | 3 层 | **×1.75** |
| 暴击 `g.crit` | `crit` BUFF +0.15/层 ×3，暴击 ×1.8 | 3 层 → 45% | **期望 ×1.36**（`1 + 0.45×0.8`） |
| 攻速 `g.attackSpeed` | `attack` BUFF +0.22/层 ×3 | 3 层 → 1.66 | 仅 `scaled=true` 的武器吃，见 §2.0 |
| 范围 `g.range` | `range` BUFF +0.2/层 ×3 | 3 层 → 1.6 | 仅 keyboard / thermos / pie / laser 吃 |

**满配复合系数** = `1.75 × 1.36 = 2.38`。下表是「三系全满（damage 3 + crit 3 + 对应攻速 3）」时的 Lv5 单体 DPS：

| 武器 | 裸 Lv5 | 满配 Lv5 | 对精英（`scale 1.9` 后需 ÷1.9 才等效） |
| --- | --- | --- | --- |
| thermos | 104.0 | **247.5** | 130.3 |
| paperclip | 108.8 | **259.0** | 136.3 |
| pie | 191.8 | **456.4** | 240.2 |
| laser | 115.9 | **275.8** | 145.2 |
| extinguisher | 180.0 | **428.4** | 225.5 |
| keyboard | 64.3 | **153.1** | 80.6 |
| stapler（单发） | 87.5 | 208.3 | 109.6 |
| coffee（单敌） | 62.5 | 148.8 | 78.3 |

**五把全拿 Lv5 单体合计 700.5 → 满配 1667.1**。而 F3 Boss「没良心老板」1800 hp，配 `e.scale` 后实际 `1800 × (1 + 2×0.45) = 3420`（`Game.lua:200` 的 `scale` 公式）——**满配五武器约 2 秒纯输出可杀**，考虑走位/躲避实际 8–15 秒，符合 Boss 战节奏预期。

### 3.6 五把武器的"该拿不该拿"决策表（给玩家的心算）

| 局面 | 首选 | 次选 | 明确别拿 |
| --- | --- | --- | --- |
| F1 前 3 个房间（敌人 sparse，血薄） | paperclip（稳定清场） | thermos（一击秒 ghost） | pie（Lv1 单体 58.9 但落点难中移动目标） |
| F1 Boss「工贼同事」540hp | laser（×1.15 + 引导打桩） | extinguisher（高单发） | pie（Boss 会走位出池） |
| F2 精英房（`totalWaves=3`） | pie（三目标 575） | thermos（扇区多人） | laser（只打 1 个） |
| F3 走廊窄道（家具多） | thermos（贴脸）+ extinguisher（击退钉墙） | paperclip | pie（`Trace` 截断导致落点总在墙前） |
| 血量 < 40% | extinguisher（击退 + stun 拉开距离） | paperclip | thermos（必须贴脸） |
| 已满 `damage`×3 + `crit`×3 | pie（乘区对 AOE 收益最大） | laser | — |



## 4. 动画 / 特效 / 动作 / 音效清单

> 这一节是给后续「适配」用的**施工单**：每一项都写明「改哪个文件、加哪个分支、复用哪张图、缺什么」。
> 现状可用的视觉资源只有三张特效图集（`Art.Fx(sheet, index, ...)`，见 `Art.lua:178-190`）：
> `weapon` 16 帧（`EffectSprites.lua:13-30`）、`area` 16 帧（`:31-45`）、`loot` 8 帧（`:3-12`）。
> **没有**任何武器图、角色技能图、光束图、弹道图。下文全部按「程序化 nvg 绘制 + 复用帧」两路给出。

### 4.1 动作状态表（`ActionState.TIMINGS` 新增 5 条 + `reload` 1 条）

单位：秒。`{ windup, impactAt, impactEnd, duration }`，与现有 `keyboard{0.09,0.10,0.20,0.42}` 同构（`ActionState.lua:20-27`）。

| name | windup | impactAt | impactEnd | duration | `scaled` | 设计意图 |
| --- | --- | --- | --- | --- | --- | --- |
| `thermos` | 0.16 | 0.18 | 0.30 | 0.72 | **true** | 三段连击，前两段短促、第三段抡圆 |
| `paperclip` | 0.06 | 0.08 | 0.14 | 0.26 | **true** | 极快抬手，抬手即出弹 |
| `pie` | 0.42 | 0.46 | 0.62 | 1.05 | false | 读条 0.42s，抛物线飞行，落地才炸 |
| `laser` | 0.22 | 0.28 | 0.90 | 1.20 | **true** | 0.28s 起束，束维持 0.62s（6 跳 × 0.12s），末 0.30s 收尾 |
| `extinguisher` | 0.30 | 0.32 | 0.52 | 0.90 | **true** | 举罐瞄准 0.30s，喷射 0.20s |
| `reload` | 0.60 | 0.60 | 0.90 | 1.30 | false | 灭火器专用装填，期间禁止开火 |

**`ORDER` 追加（`ActionState.lua:27`）**：

```lua
local ORDER = { "burst", "hurt", "keyboard", "stapler", "coffee",
                "reload", "thermos", "paperclip", "laser", "extinguisher", "pie" }
```

顺序理由：`reload` 排在武器之前（装填是前置条件，必须先推进才能解除锁定）；`pie`（读条最久）排最后，保证有瞬发武器时优先出瞬发；`laser`/`extinguisher`（引导/长动作用）排在瞬发之后。**追加不插队**是为了让 `tests/Actions.lua:243`「同帧三武器独立起手，`g.action == keyboard`」继续成立。

**攻速缩放改造（`ActionState.lua:77/80/87`）**：

```lua
-- 现状：local speed = name == "keyboard" and math.max(0.1, rate or 1) or 1
local speed = (TIMINGS[name] and TIMINGS[name].scaled) and math.max(0.1, rate or 1) or 1
-- 现状：impactAt = math.max(name == "keyboard" and 0.075 or 0, timing.impactAt/speed)
impactAt  = math.max((TIMINGS[name] and TIMINGS[name].scaled) and 0.075 or 0, timing.impactAt / speed)
```

⚠️ **改这一处不会影响 `keyboard` 既有行为**：把 `keyboard` 的 `scaled` 直接写成 `true` 即与现状等价，19 套测试不会因这条改动变红。

### 4.2 每把武器的完整动作/特效/音效清单

#### 4.2.1 thermos 保温杯警告（近战）

| 类别 | 项 | 实现位置 | 具体做法 |
| --- | --- | --- | --- |
| 状态 | `windup` 0.16s | `ActionState` 自动置 `phase` | 角色播 `attack` 帧序列（`HeroSprites` `frames.attack`，最多 4 帧） |
| 状态 | `impact` 0.12s | 同上 | 第 1 段向右、第 2 段向左、第 3 段深蹲上撩（`combo` 计数 1/2/3 决定 `angle` 偏移 −0.9/0/+0.45 rad） |
| 状态 | `recovery` 0.42s | 同上 | 播 `idle` 回正 |
| 特效 | 挥击弧 `slash` | `Game.ActionImpact` thermos 分支 → `Effect(g,"slash",...)` | 复用现有 `slash`：`Draw.lua:198-200` `Art.Fx("weapon",frame,e.x+cos(angle)*size*.4, e.y-22+sin(angle)*size*.4, size*1.55, 1, angle)`。`size = 96+6*level` |
| 特效 | 第三段加粗 | 同上，`size*1.55 → size*1.95` | 只在 `combo==3` 时放大，视觉上区分终结技 |
| 特效 | 枸杞水溅射 | **新增 `Effect(g,"splash",x,y,life,size,angle)`**，`Draw.lua Effects()` 加分支 | 程序化：`nvgArc` 画半环 + 3 条水滴线；颜色 `Skin.Color("hp")`（现有红色系）。**无需新图** |
| 粒子 | 红色/橙色 `Particles(g,x,y,"gold",8+2*level)` | 复用 `Game.Particles`（`Game.lua:152`，上限 240） | 命中时在敌人位置放 |
| 音效 | 挥空 | **复用 `swing`**（`office_keyboard_swing.wav`，`Audio.lua:71`） | 起手时 `Sound(g,"swing")` |
| 音效 | 命中 | **复用 `hit`**（`office_keyboard_hit.wav`） | `landed` 时 `Sound(g,"hit")` |
| 音效 | 第三段落锤感 | **新增 cue `heavy`**：`{ path="audio/sfx/office_keyboard_hit.wav", gain=0.72, pitch=0.74, variation=0.03, cooldown=0.12, priority=5 }` | 复用同一 wav，降 pitch 造「闷响」。⚠️ **资产缺失**：将来需要一把「保温杯砸桌」重击音 |
| 动作帧需求 | ⚠️ **资产缺失** | — | 现在只能复用 `HeroSprites` 的 `attack` 4 帧（男女各一套）。将来需要：**保温杯挥击 3 段 × 4 帧 = 12 帧/角色**，共 24 帧 |
| 武器本体图 | ⚠️ **资产缺失** | `Draw.lua` 新增 `local function Thermos(x,y,angle,scale)` | 现无图，用 `nvg` 画：圆柱体（圆角 `Rect`）+ 杯盖 + 一条高光。约 30 行，照抄 `Keyboard()`（`Draw.lua:146-192`）骨架 |

#### 4.2.2 paperclip 回形针弹弓（远程）

| 类别 | 项 | 实现位置 | 具体做法 |
| --- | --- | --- | --- |
| 状态 | `windup` 0.06s | `ActionState` | 几乎瞬发，抬手帧只 1 帧 |
| 状态 | `impact` 0.06s | — | 子弹出膛瞬间 |
| 状态 | `recovery` 0.12s | — | 回正 |
| 特效 | 弹道拖尾 | **复用 `g.shots` 池 + `Draw.lua` 子弹分支** | 现状 `Draw.lua:312` 已有 `Art.Fx("weapon",5+floor(g.time*12)%4, s.x,s.y-10,57,1,math.atan(s.vy,s.vx))` —— 正是给 `g.shots` 用的弹丸帧（第 5–8 帧是弹丸）。**回形针直接复用这套**，只把 `size 57` 调到 `34` |
| 特效 | 命中金属火花 | **复用 `stapleHit`** | 现状 `stapleHit` 已被 stapler 用（`Draw.lua:203-204` `Art.Fx("weapon",8+frame,...)`），回形针**直接复用**，只是 `size 42` |
| 特效 | 第 5 发追踪针标记 | **复用文字特效** | 命中时 `Effect(g,"crit",e.x,e.y-30,0.4,0,"追踪")` —— 复用 `Draw.lua:219-222` 的文字分支，零新增绘制代码 |
| 粒子 | 青色 `Particles(g,e.x,e.y,"teal",5)` | 复用 | 金属感用 `teal`，与敌人 `paper` 区分 |
| 音效 | 拉弓/发射 | **新增 cue `snap`**：`{ path="audio/sfx/office_stapler_click.wav", gain=0.30, pitch=1.28, variation=0.06, cooldown=0.05, priority=2 }` | 复用订书机按键音，升 pitch 变「弹弓绷弦」 |
| 音效 | 命中 | 复用 `hit` | 若要降低音量，新增 `hitLight` cue 指向同一 wav，`gain=0.40` |
| 动作帧需求 | ⚠️ **资产缺失** | — | 复用 `attack` 4 帧。将来需要：**弹弓拉弦 3 帧/角色**（6 帧） |
| 武器本体图 | ⚠️ **资产缺失** | `Draw.lua` 新增 `local function Sling(x,y,angle,scale)` | `nvg` 画：Y 形叉 + 皮筋两条线 + 夹着的回形针（三折线 Path）。约 25 行 |

#### 4.2.3 pie 画饼充饥（魔法）

| 类别 | 项 | 实现位置 | 具体做法 |
| --- | --- | --- | --- |
| 状态 | `windup` 0.42s（读条） | `ActionState` | 角色播 `skill` 帧序列（`HeroSprites.lua:3` 的 `sourceFacing.skill` 证明存在）。**读条期间移速 ×0.7**，在 `Game.Update` 玩家移动分支按 `ActionState.Phase(g,"pie")=="windup"` 判定 |
| 状态 | `impact` 0.16s | — | 抛物饼落地爆炸 |
| 状态 | `recovery` 0.43s | — | 收手 |
| 特效 | 抛饼飞行 | **新增 `g.pies` 轻量池**（结构 `{x,y,tx,ty,t,dur,arcH}`） | `Draw.lua` 新增 `local function Pies(g)`，用 `Rect` 画一个旋转的金色圆角矩形模拟饼，`y -= math.sin(pi*t)*arcH` 得到抛物线。**不用物理，纯插值** |
| 特效 | 落地爆炸 | **新增 `Effect(g,"pieBoom",x,y,0.36,size)`**（不能复用 `burst`：那是 260 范围大招视觉） | `Draw.lua` 分支：`Art.Fx("area", 1+frame, e.x,e.y, e.size*2, alpha)` —— **复用 area 图集第 1–5 帧**（`EffectSprites.lua:32-36`，这 5 帧是小型扩散圈，目前全项目没人用），配 `nvgCircle` 橙色描边 |
| 特效 | 地面饼池 | **复用 `g.pools`**（`Game.lua:587` coffee 池同构），加 `pool.kind="pie"` 字段 | `Draw.lua:269-272` 现有池绘制是 `Art.Fx("area",frame,pool.x,pool.y-10,pool.radius*2.8,...)`。**新增分支**：`pool.kind=="pie"` 时额外画 `nvgCircle` 半径 `pool.radius` 的橙色半透明填充 + 内圈虚线（`nvgStroke` + `lineDash`） |
| 粒子 | 金色 `Particles(g,x,y,"gold",14)` | 复用 | 爆炸时 |
| 音效 | 抛掷 | **新增 cue `toss`**：`{ path="audio/sfx/office_keyboard_swing.wav", gain=0.30, pitch=0.66, variation=0.05, priority=2 }` | 低 pitch 的「呼」声 |
| 音效 | 爆炸 | **新增 cue `splat`**：`{ path="audio/sfx/office_rage_burst.wav", gain=0.42, pitch=1.18, variation=0.04, cooldown=0.18, priority=6 }` | ⚠️ **资产缺失**：将来需要「啪叽」湿软爆裂音。现在只能拿 burst 音升 pitch 硬凑 |
| 动作帧需求 | ⚠️ **资产缺失** | — | 复用 `skill` 帧。将来需要：**抛掷 4 帧/角色**（8 帧） |
| 武器本体图 | ⚠️ **资产缺失** | `Draw.lua` 新增 `local function Pie(x,y,arcH,scale)` | 一个金色圆角矩形 + 顶部 3 道放射刻痕（`nvgLineTo`） |

#### 4.2.4 laser 激光打印（激光）

| 类别 | 项 | 实现位置 | 具体做法 |
| --- | --- | --- | --- |
| 状态 | `windup` 0.22s | `ActionState` | 举打印机对准，角色播 `skill` 帧 |
| 状态 | `impact` 0.62s（**最长**） | — | `impactAt=0.28`，`impactEnd=0.90`。6 跳伤害每 0.12s 一次，落在 `Game.ActionImpact` 之外 → **必须在 `Game.Update` 里单独 tick**（见 §7.2 `Game.UpdateLaser`） |
| 状态 | `recovery` 0.30s | — | 收手 |
| 特效 | 光束主体 | **纯程序化**，`Draw.lua` 新增 `local function Beams(g)` | `nvgBeginPath→nvgMoveTo(px,py-22)→nvgLineTo(ex,ey-22)`；三层描边：外层 `width 12, alpha 60, "pink"` / 中层 `width 5, alpha 170` / 内层 `width 1.5, alpha 255, "white"`。每帧 `alpha ± sin(g.visualTime*40)` 闪烁 |
| 特效 | 光束被墙截断 | 复用 `Navigation` 射线-墙求交 | `Game.lua:742` 的 stapler 挡墙就是这个套路，取 `contact` 点作为光束终点 |
| 特效 | 落点灼烧 | **新增 `Effect(g,"burn",x,y,0.3,size)`** | `nvgCircle` 双层橙色圆 + 缩放 `1+(1-ratio)*0.6`。⚠️ **资产缺失**：将来用 `area` 图集第 9–12 帧（`EffectSprites.lua:40-43`，中型爆点）替换 |
| 粒子 | 粉色 `Particles(g,hx,hy,"pink",3)` 每跳 | 复用 | 命中点持续掉末 |
| 音效 | 充能 | **新增 cue `charge`**：`{ path="audio/sfx/office_level_up.wav", gain=0.22, pitch=1.42, variation=0.02, cooldown=0.30, priority=3 }` | 升 pitch 的电子「嘀——」 |
| 音效 | 光束持续 | **新增 cue `beam`**：`{ path="audio/sfx/office_keyboard_swing.wav", gain=0.26, pitch=1.55, variation=0.02, cooldown=0.10, priority=3 }` | 每 0.12s 一跳播放 → 听感上变成持续的「滋——」。⚠️ **资产缺失**：将来需要真正的激光循环音（1 个 0.5s wav，带 loop 标记） |
| 音效 | 收束 | **新增 cue `beamOff`**：`{ path="audio/sfx/office_stapler_click.wav", gain=0.24, pitch=0.85, variation=0.04, cooldown=0.10, priority=2 }` | 短促收尾 |
| 动作帧需求 | ⚠️ **资产缺失** | — | 复用 `skill` 帧。将来需要：**举机瞄准 2 帧 + 维持 2 帧/角色**（8 帧） |
| 武器本体图 | ⚠️ **资产缺失** | `Draw.lua` 新增 `local function Printer(x,y,angle,scale)` | 方盒主体 + 出纸口 + 顶部一条红线（瞄准用）。约 20 行 |

#### 4.2.5 extinguisher 灭火器（重装）

| 类别 | 项 | 实现位置 | 具体做法 |
| --- | --- | --- | --- |
| 状态 | `windup` 0.30s | `ActionState` | 举罐，角色播 `attack` 帧 |
| 状态 | `impact` 0.20s | — | 喷射窗口，每 0.30s 发 1 弹（弹夹 6 发 → 3.10s 周期见 §2.5） |
| 状态 | `reload` 1.30s | `ActionState.TIMINGS` 新增 `reload{0.60,0.60,0.90,1.30}` | 装填期间**不能开火**，角色播 `idle` + 罐体晃动特效。`reload` 也要进 `ORDER`（放在 `thermos` 前） |
| 特效 | 喷射锥 | **新增 `Effect(g,"spray",x,y,life,angle,size)`** | `nvgSave→Translate→Rotate` 后画扇形 `nvgArc(0,0,size,-0.38,0.38)`，白色 `alpha 90` + 3 层递减叠加。生命周期跟随 action 的 impact 段，每帧重放 |
| 特效 | 干粉弹丸 | 复用 `g.shots` 池 | 弹丸半径 10，`Draw.lua:312` 的 `Art.Fx("weapon",...)` 分支加 `if s.big then size=90` 放大 |
| 特效 | 打空时的干粉池 | 复用 `g.pools`（`pool.kind="powder"`） | 绘制：`nvgCircle` 半径 `pool.radius`，白色 `alpha=40+25*sin(g.visualTime*3)`，两层同心圆 |
| 特效 | 装填进度 | **角色头顶细条**（不走 UI 层，避免抢 HUD 布局） | `Draw.lua` 用两段 `Rect`（底 + 填充），宽 34 高 4，跟随角色位置 |
| 粒子 | 白色 `Particles(g,x,y,"white",6)` | 复用 | `"white"` 已在 `Draw.lua:220` 使用，`Skin.colors` 里有，**安全** |
| 音效 | 喷射 | **新增 cue `spray`**：`{ path="audio/sfx/office_footstep_run.wav", gain=0.34, pitch=0.62, variation=0.10, cooldown=0.14, priority=3 }` | 白噪感的脚步音降 pitch ≈ 气流。⚠️ **资产缺失**：将来需要「呲——」气罐音 |
| 音效 | 装填 | **新增 cue `clunk`**：`{ path="audio/sfx/office_stapler_click.wav", gain=0.44, pitch=0.70, variation=0.03, cooldown=0.16, priority=4 }` | 金属卡榫声 |
| 音效 | 击退命中 | 复用 `hit` + `heavy`（见 4.2.1） | — |
| 动作帧需求 | ⚠️ **资产缺失** | — | 复用 `attack` 帧。将来需要：**抱罐喷射 4 帧 + 装填 3 帧/角色**（14 帧） |
| 武器本体图 | ⚠️ **资产缺失** | `Draw.lua` 新增 `local function Extinguisher(x,y,angle,scale)` | 圆柱 + 顶阀 + 一根弯曲软管（`nvgBezierTo`）。约 28 行 |

### 4.3 汇总矩阵（一眼看清谁要新东西）

| 需求项 | thermos | paperclip | pie | laser | extinguisher |
| --- | --- | --- | --- | --- | --- |
| 新增 `Effect` kind | `splash` | — | `pieBoom` | `burn` | `spray` |
| 复用现有 `Effect` | `slash` | `stapleHit` / `crit` | — | — | — |
| 复用 `g.shots` | — | ✅ | — | — | ✅ |
| 复用 `g.pools` | — | — | ✅ | — | ✅ |
| 新增独立池 | — | — | ✅ `g.pies` | — | — |
| 纯程序化绘制函数 | `Thermos` | `Sling` | `Pie` | `Printer` | `Extinguisher` |
| 新增音频 cue 数 | 1（`heavy`） | 1（`snap`） | 2（`toss`/`splat`） | 3（`charge`/`beam`/`beamOff`） | 2（`spray`/`clunk`） |
| **需要新美术** | 武器图 + 12 帧动作 | 武器图 + 6 帧 | 武器图 + 8 帧 | 武器图 + 8 帧 | 武器图 + 14 帧 |

**粒子预算核算**：最坏情况（五把全满 + 密集波次）每帧新增粒子 = thermos 18 + paperclip 5×3 + pie 14 + laser 3×6 + ext 6×6 ≈ 113 颗。现有 `Game.lua:154` 硬上限 `#g.particles >= 240` **会截断**，实际不会爆。同屏实体：`g.shots` 最坏 paperclip 3 + ext 6 = 9，`g.pools` 最坏 pie 2 + ext 1 + coffee 2 = 5，`g.pies` 1，`g.effects` 上限 100（`Game.lua:162`），**全项目实体数远低于 60 的约束**。

### 4.4 音效复用总表（`Audio.lua` `cues` 表新增 10 条，0 个新文件）

现有 **11 个 wav 文件**（`Audio.lua:71-85` 引用，被 15 个 cue 复用）：`office_keyboard_swing` / `office_keyboard_hit` / `office_stapler_click` / `office_player_hurt` / `office_rage_burst` / `office_xp_pickup` / `office_level_up` / `office_footstep_walk` / `office_footstep_run` / `office_door_open` / `office_ui_confirm`。

| 新 cue | 复用 wav | gain | pitch | variation | cooldown | priority |
| --- | --- | --- | --- | --- | --- | --- |
| `heavy` | office_keyboard_hit | 0.72 | 0.74 | 0.03 | 0.12 | 5 |
| `snap` | office_stapler_click | 0.30 | 1.28 | 0.06 | 0.05 | 2 |
| `toss` | office_keyboard_swing | 0.30 | 0.66 | 0.05 | 0.10 | 2 |
| `splat` | office_rage_burst | 0.42 | 1.18 | 0.04 | 0.18 | 6 |
| `charge` | office_level_up | 0.22 | 1.42 | 0.02 | 0.30 | 3 |
| `beam` | office_keyboard_swing | 0.26 | 1.55 | 0.02 | 0.10 | 3 |
| `beamOff` | office_stapler_click | 0.24 | 0.85 | 0.04 | 0.10 | 2 |
| `spray` | office_footstep_run | 0.34 | 0.62 | 0.10 | 0.14 | 3 |
| `clunk` | office_stapler_click | 0.44 | 0.70 | 0.03 | 0.16 | 4 |
| `heroUlt` | office_rage_burst | 0.66 | 1.00 | 0 | 0.40 | 9 |

> `Audio.lua:110-131` 的逻辑：`cooldowns[key] > 0` 直接 return，所以**同 key 有硬冷却**；不同 key 指向同一 wav 时会「抢 voice」（`:125` 的 priority 比较），因此上表 priority 必须错开，避免 `splat` 把 `burst` 盖掉。

⚠️ **资产缺失（音效总账）**：将来需要 7 个新 wav —— `office_thermos_heavy.wav`（保温杯砸桌）、`office_pie_splat.wav`（湿软爆裂）、`office_laser_loop.wav`（可 loop 的激光）、`office_extinguisher_spray.wav`（气罐喷射）、`office_clip_snap.wav`（弹弓绷弦）、`office_ult_male.wav`、`office_ult_female.wav`（男女大招各一）。**在拿到这批文件前，全部用上表复用方案。**

### 4.5 资产缺失总账（给美术的唯一清单）

| 编号 | 缺什么 | 用谁的图顶 | 规格建议 | 影响功能 |
| --- | --- | --- | --- | --- |
| A1 | 保温杯武器图 | 无（`nvg` 程序化） | 64×64，4 向 | thermos |
| A2 | 弹弓武器图 | 无（`nvg`） | 64×64，4 向 | paperclip |
| A3 | 饼武器图 | 无（`nvg`） | 64×64 | pie |
| A4 | 打印机武器图 | 无（`nvg`） | 64×64，4 向 | laser |
| A5 | 灭火器武器图 | 无（`nvg`） | 64×64，4 向 | extinguisher |
| A6 | 保温杯 3 段挥击动作 | `HeroSprites` `attack` 4 帧 | 12 帧/角色 × 2 = 24 | thermos |
| A7 | 弹弓拉弦 | 同上 | 3 帧 × 2 = 6 | paperclip |
| A8 | 抛饼 | `HeroSprites` `skill` 帧 | 4 帧 × 2 = 8 | pie |
| A9 | 举机瞄准/维持 | 同上 | 4 帧 × 2 = 8 | laser |
| A10 | 抱罐喷射/装填 | `attack` 帧 | 7 帧 × 2 = 14 | extinguisher |
| A11 | 光束贴图（可选） | `nvg` 三层线 | 512×32 可拉伸 | laser |
| A12 | 干粉/饼池地面贴图（可选） | `nvgCircle` | 256×256 可平铺 | pie/ext |
| A13 | 7 个新音效 wav | 见 §4.4 复用表 | 44.1k/16bit/mono | 全部 |
| A14 | 男女大招各一张「爆发圈/立绘」 | `area` 图集第 6–16 帧 | 512×512 | §5 |
| A15 | 20+ BUFF 图标 | `InterfaceIcons.buff` 12 帧复用（见 §6.5） | — | §6 |


## 5. 男女主大招差异化

### 5.1 先摆测试契约（决定了哪些数字不能动）

重做大招最大的风险不是设计，是**踩坏现有断言**。三条测试把 female 的大招参数钉死了：

| 断言位置 | 原文条件 | 对设计的硬约束 |
| --- | --- | --- |
| `tests/Actions.lua:291-311` | `target.hp == hp - math.floor(125 * g.damage)`，且 `#hostileShots == 0`，且 `Sounds(g,"burst") == 1` | **female 主伤害实例必须是 `math.floor(125 * g.damage)`**，不能改系数，不能拆成多段 |
| `tests/Actions.lua:291-311` | 起手瞬间「无伤害、不清弹幕、无 burst 音」；`Tick(5)`（0.10s）仍 waiting；`Tick(1)`（0.12s）才结算 | **impactAt 必须仍是 0.12s**，`TIMINGS.burst` 的 `{0.10, 0.12, 0.28, 0.60}` 不能动 |
| `tests/HeroRules.lua:292-305` | 墙后敌人 `shielded.hp == shieldHp`（隔墙不受伤），同时 `actionTracks.burst.impactDone == true` | female 的伤害**必须走 `Visible()` 视线判定**，不能改成无条件 AOE |
| `tests/Smoke.lua:59-67` | male：起手 `g.rage==0`、`player.invuln>0`、`action.name=="burst"`、`action.time==0`、`#hostileShots==1`；0.15s 后 `#hostileShots==0` 且 `impactDone` | **male 也必须清弹幕、impact 在 0.12s、动作名必须仍叫 `burst`**；但 **male 侧不断言伤害数值** → 男主的伤害公式、范围、附加效果都可自由改 |

**结论（这是整个 §5 的设计前提）**：
- 动作名 `"burst"` 保留，`TIMINGS.burst` 不动 → 男女共用同一段动画时序，只是**结算内容完全不同**。
- 分流点在 `Game.ActionImpact` 的 `burst` 分支内部（按 `g.heroId` 二分），**不在 `ActionState` 层**。
- female 的伤害数字与判定方式**原样保留**，全部新机制做成「**不造成伤害**的附加层」（减速、标记、易伤），这样 `hp == hp - floor(125*damage)` 永远成立。
- male 侧没有数值断言，可以整套换掉。

### 5.2 男主 陈准 · 暴怒砸桌（`slam`）

> 世界观：忍了一天，最后一秒把整张工位桌掀了。「我不下班，谁也别想下班。」

#### 5.2.1 触发与消耗

| 项 | 值 | 说明 |
| --- | --- | --- |
| 触发 | `g.rage >= 100` 且 `g.mode == "playing"` 且 `not ActionState.Active(g,"burst")` | 与现状一致（`Game.lua:330`） |
| 消耗 | `g.rage = 0` | 与现状一致 |
| 额外限制 | 释放后 `g.ultCooldown = 1.0`（秒），期间 `g.rage` 增速 ×0 | 防止「怒气溢出瞬间连放」，新增字段 |
| 动作 | `ActionState.Start(g, "burst", faceX, faceY)` | 名字不变，保证 `action.name=="burst"` 断言 |
| 时序 | `TIMINGS.burst = {0.10, 0.12, 0.28, 0.60}` 原样 | 0.10s 抬手 / 0.12s 砸下 / 0.28s 余震 / 0.60s 收招（36 帧 @60fps） |

#### 5.2.2 伤害与效果公式

```lua
-- L = g.level（玩家等级，Game.lua 里已有）
local R      = 168                                    -- 半径（比 female 的 260 小，符合近战定位）
local arc    = math.pi * 1.10                          -- 前方 198° 扇区（背后 162° 打不到：逼玩家贴脸朝前）
local dmg    = math.floor((105 + 8 * g.level) * g.damage * (g.slamAmp or 1))
local knock  = 520                                     -- 击退初速（现状 female 是 420）
local stun   = 1.20                                    -- 硬直秒数
```

| 等级 | 基础值 `105+8L` | 男主实际伤害（`damage=0.85`，无 BUFF） | 满伤害 BUFF（`damage=1.60`） | female 同期对照（`125*1.30=162` / `125*2.05=256`） |
| --- | --- | --- | --- | --- |
| L1 | 113 | **96** | 180 | 162 / 256 |
| L5 | 145 | **123** | 232 | 162 / 256 |
| L10 | 185 | **157** | 296 | 162 / 256 |
| L15 | 225 | **191** | 360 | 162 / 256 |

> 注意：female 的 125 是**常数**（不吃等级），male 的 `105+8L` 随等级成长。这是刻意设计：男主是「越打越猛」的成长型，女主是「一出手就定死」的稳定型。L1 时 male 单发 96 < female 162，L15 时 male 191 > female 162 → **交叉点在 L8 左右**（`105+8L = 191 → L≈10.75`，算上 female 拿到伤害 BUFF 后上移到 L12+）。

**附加效果（三层，全部不额外造成伤害）**：

| 效果 | 数值 | 实现 | 为什么这么设计 |
| --- | --- | --- | --- |
| ① 清弹幕 | `g.hostileShots = {}` | 与现状一致（`Game.lua:334`） | 测试契约 + 近战必须有「清场喘息」 |
| ② 击退 | `knock = 520`（现状 420，+24%） | `Game.Hit(g, e, dmg, nx, ny, knock)` | 把一圈敌人推开，弥补半径只有 168 的劣势 |
| ③ 硬直 | `e.stunTimer = math.max(e.stunTimer or 0, 1.20)` | `Game.UpdateEnemies` / `UpdateBoss` 里 `if e.stunTimer > 0 then e.stunTimer = e.stunTimer - dt; ... return end`（跳过移动+开火） | 1.2s 站桩 → 配合键盘 0.42s 一发，等于白打 2–3 下 |
| ④ 易伤 | 硬直期间受击伤害 `×1.15` | `Game.Hit` 里 `if (e.stunTimer or 0) > 0 then amount = amount * 1.15 end` | 让硬直不只是控制，也是伤害窗口 |
| ⑤ 肾上腺素 | `g.adrenaline = 3.0`，期间 `g.attackSpeed ×1.25` | `Game.UpdateWeapons` 读 `local aspd = g.attackSpeed * (g.adrenaline > 0 and 1.25 or 1)` | 大招后 3s 是男主的爆发窗口，鼓励「大招→贴脸连打」 |
| ⑥ 自身无敌 | `invuln = max(invuln, 1.2)` | 与现状一致 | 测试契约 |

#### 5.2.3 视觉表现（全部程序化，无新图）

| 阶段 | 时间 | 画面 | 代码位置 |
| --- | --- | --- | --- |
| 抬手 | 0.00–0.12s | 角色 `attack` 帧；脚下一圈黄色警告环 `r = 168`，`alpha 60 → 140` 呼吸 | `Draw.lua` 新增 `local function SlamTell(g)` |
| 砸下 | 0.12s 瞬间 | `g.shake = 14`、`g.hitStop = 0.09`；放射状裂纹 8 条（`nvgLineTo`，长 60–150 随机）；黄色冲击环 `nvgCircle` 半径 `20→168`，`alpha 200→0`，时长 0.32s | 新增 `Effect(g,"slamRing",x,y,0.32,168)` 分支 |
| 余震 | 0.12–0.40s | 地面残留裂纹，`alpha` 线性衰减；桌子残骸粒子 22 颗（复用 `weapon` 图集，`Particles(g,x,y,"gold",22)`） | 复用 `Game.Particles` |
| 收招 | 0.40–0.60s | 角色 `idle` 回正 | — |
| 全程叠加 | 0–3.0s | 玩家身上橙色描边（`adrenaline` 期间），`nvgCircle` 半径 20，`alpha = 90 + 40*sin(g.visualTime*8)` | `Draw.lua` Hero 绘制后 |

**音效**：`Sound(g,"heroUlt")`（新增 cue，复用 `office_rage_burst.wav`，`pitch 0.86`，见 §4.4）+ 0.12s 时 `Sound(g,"heavy")`（复用 `office_keyboard_hit.wav` 降 pitch）。

### 5.3 女主 林夏 · 职场洞察（`insight`）

> 世界观：她看一眼就知道这个会的重点在哪、谁在甩锅、哪句是废话。于是所有人都慢了下来。

#### 5.3.1 触发与消耗（与男主完全相同，只有结算不同）

| 项 | 值 |
| --- | --- |
| 触发 | `g.rage >= 100` 且 `g.mode == "playing"` 且 `not ActionState.Active(g,"burst")` |
| 消耗 | `g.rage = 0`；`g.ultCooldown = 1.0` |
| 动作 | `ActionState.Start(g, "burst", faceX, faceY)` |
| 时序 | `{0.10, 0.12, 0.28, 0.60}` 原样 |

#### 5.3.2 伤害与效果公式

```lua
-- 主伤害实例：一个字都不能改（tests/Actions.lua:291-311 契约）
local R   = 260
local dmg = math.floor(125 * g.damage)
-- 在此之上追加三个「不造成伤害」的层：
local slowT  = 2.50   -- 减速持续
local slowK  = 0.55   -- 移速倍率（越低越慢）
local markT  = 6.00   -- 标记持续
local markN  = 3      -- 标记消耗次数
local markAmp = 1.35  -- 被标记目标受武器伤害倍率
local markCrit = 0.25 -- 被标记目标额外暴击率
```

| 效果 | 数值 | 作用对象 | 实现要点 |
| --- | --- | --- | --- |
| ① 主伤害 | `floor(125 * g.damage)` | `d < 260 + e.radius` 且 `Visible()` | **原样保留**（含 `Game.Hit(...,125,nx,ny,420)` 的 420 击退） |
| ② 清弹幕 | `g.hostileShots = {}` | 全局 | 原样保留 |
| ③ **时间减速力场** | 半径 260 内所有敌人 `e.slowTimer = 2.50`，移动 `×0.55`、射击间隔 `÷0.55`（即变慢 1.82 倍） | 同 `Visible()` 判定 | 不造成伤害，`hp` 断言安全。`Game.UpdateEnemies` 里原本就有 `slowTimer` 概念（`Game.lua` 咖啡池用 `pool.slowTimer`），复用同一字段名 |
| ④ **洞察标记** | `e.markTimer = 6.0`、`e.markHits = 3` | 同上 | 不造成伤害。`Game.Hit` 里 `if (e.markHits or 0) > 0 then amount = amount * 1.35; e.markHits = e.markHits - 1; if e.markHits <= 0 then e.markTimer = 0 end end` |
| ⑤ **标记暴击** | 对已标记目标，实际暴击率 = `g.crit + 0.25` | 同上 | `Game.Hit` 里把 `math.random() < (g.crit + (marked and 0.25 or 0))` 拆成一行 |
| ⑥ 自身无敌 | `invuln = max(invuln, 1.2)` | 玩家 | 原样保留 |

**为什么标记是 3 次而不是「一段时间内全部」**：3 次 = 玩家必须在标记窗口内**主动输出**，把「洞察」变成「节奏指挥」而不是「挂机增伤」。6s 内打完 3 下是正常操作，打不完说明玩家在跑位，那本来也不需要增伤。

#### 5.3.3 视觉表现

| 阶段 | 时间 | 画面 | 代码位置 |
| --- | --- | --- | --- |
| 抬手 | 0.00–0.12s | 角色 `skill` 帧；脚下**青蓝色扫描环**（`r 20→260`，`alpha 140→0`，时长 0.45s） | 新增 `Effect(g,"scanRing",x,y,0.45,260)` 分支 |
| 扫描 | 0.12s | 从玩家中心向四周扩散 3 圈同心圆，每圈间隔 0.06s、`alpha` 递减；命中敌人身上亮起**准星**（4 条短线围成十字，`nvgLineTo`） | 新增 `Effect(g,"mark",e.x,e.y,e.markTimer,26)` |
| 减速 | 0.12–2.62s | 被减速敌人脚下**青蓝色同心圆**（半径 `e.radius+6`，`alpha = 70 + 30*sin(g.visualTime*4)`），并在其移动时拖 3 段残影 | `Draw.lua` Enemy 分支加 `if e.slowTimer > 0 then` |
| 标记剩余 | 0.12–6.12s | 准星随 `markHits` 减少而变暗：`alpha = 255 * markHits / 3` | 同上 |
| 收束 | 0.60s | 玩家身边 `Particles(g,x,y,"teal",36)` | 复用 |

**音效**：`Sound(g,"heroUlt")`（`pitch 1.15`，听感更「清脆/电子」）+ 0.12s 时 `Sound(g,"charge")`（`office_level_up.wav` 升 pitch，见 §4.4）。

### 5.4 两套大招对比表（平衡验证）

| 维度 | 男主 · 暴怒砸桌 | 女主 · 职场洞察 | 谁更强 |
| --- | --- | --- | --- |
| 范围 | 前方 **198° 扇区**，R=168（面积 41 412 px²） | 全向 **360°**，R=260（面积 212 372 px²） | 女主 5.1 倍覆盖 |
| 伤害系数 | `105+8L`（随等级成长） | `125`（常数） | L1–L9 女主，L10+ 男主 |
| 单发峰值（无 BUFF） | 96 @L1 → 191 @L15 | 162（male 的 1.30/0.85 换算后 female 相当 248） | 女主前期碾压 |
| 控制 | 击退 520 + 硬直 1.2s（**硬控**） | 减速 0.55×/2.5s + 标记（**软控**） | 男主更「断节奏」 |
| 增伤窗口 | 硬直期 ×1.15 + 肾上腺素 ×1.25 攻速 3s | 标记 ×1.35 × 3 次 + 暴击 +25% | 男主适合贴脸连打，女主适合拉扯点射 |
| 清弹幕 | ✅ | ✅ | 平 |
| 无敌 | 1.2s | 1.2s | 平 |
| 最优武器搭配 | thermos（近战）+ extinguisher（重装） | laser（激光单点）+ paperclip（远程） | 与 §2.6 互补矩阵一致 |
| 使用门槛 | 必须贴脸（背后 162° 是盲区） | 站中间即可 | 女主更「稳」 |
| 翻盘能力（血量 <30%） | **强**（击退+硬直+无敌=脱困） | 中（减速够跑，但敌人还在射） | 男主 |

**为什么这个差异是对的**：`Heroes.lua:13-19` 原设定男 130hp/0.85dmg、女 90hp/1.30dmg —— 男主**肉但打不快**，女主**脆但一波高**。大招必须放大这个反差：男主拿「硬控+抗压」换输出时间，女主拿「范围+爆发」换容错。现在两人共用 `125*g.damage` 的 AOE，等于把女主的优势直接送给男主，这就是需求说「男女主要不同的大招才可以」的根本原因。

### 5.5 怒气系统改造

| 项 | 现状 | 改造后 | 理由 |
| --- | --- | --- | --- |
| 单次击杀涨怒 | `Game.lua:315` 附近 `g.rage = math.min(100, g.rage + 3)` | 保留 | — |
| 受击涨怒 | 保留 | 保留 | — |
| 释放后冷却 | 无 | `g.ultCooldown = 1.0`，期间涨怒 ×0 | 防止 `Game.Choose` 的 `rage` BUFF（`Game.lua:412` `g.rage = 100`）连续触发秒放 |
| 满怒提示 | `HudUI.lua:82` `burstLabel` 写死「拒绝加班」 | 按 `g.heroId` 分流：male「砸桌」 / female「洞察」 | 见 §5.6 |
| 怒气上限 | 100（硬编码） | 100（不变） | 保守，避免动 `HudUI` 的 `ProgressBar maxValue=1` 换算 |
| BUFF 联动 | — | 新增 `rageGain` 类 BUFF（§6 的 B18/B19），乘进每次都涨怒的计算 | 见 §6 |

### 5.6 需要拆成 hero-specific 的代码路径清单

| # | 文件 / 位置 | 现状 | 改法 | 风险 |
| --- | --- | --- | --- | --- |
| 1 | `Game.lua:329-336` `Game.Burst(g)` | 无分支 | 保留前置检查，末尾 `if g.heroId == "male" then return Game.BurstMale(g, action) else return Game.BurstFemale(g, action) end`；**两者都返回 true** | 低（`Burst` 返回值语义不变） |
| 2 | `Game.lua:337-351` `BurstImpact(g, action)` | 单一实现 | 拆成 `Game.UltImpact(g, action)` 分派器 + `Game.UltMaleImpact` + `Game.UltFemaleImpact`。**`BurstImpact` 保留为别名指向 `UltImpact`**，避免 `tests` 或外部引用断掉 | 中（female 部分必须逐字保留 125/260/420/Visible） |
| 3 | `Game.lua:291-327` `Game.Hit(g, e, damage, nx, ny, force)` | 无 stun/mark | 加入：`stunTimer` 易伤 ×1.15、`markHits` 增伤 ×1.35、标记暴击 +0.25 | 中（`tests/Combat.lua` 若有精确伤害断言需核对；本文 §9 列出核对步骤） |
| 4 | `Game.lua:640-708` `UpdateEnemies` | 无 stun/slow 统一处理 | 开头加 `if (e.stunTimer or 0) > 0 then e.stunTimer = e.stunTimer - dt; -- 跳过移动与开火 end`；把现有 coffee pool 的减速逻辑抽成 `local slow = (e.slowTimer or 0) > 0 and 0.55 or 1` | 中（现有 coffee 减速在 `UpdateEnemies` 内联，需小心不重复减速） |
| 5 | `Game.lua:617-639` `UpdateBoss` | 同上 | Boss 也要吃 stun（否则男主大招对 Boss 完全无效）。建议 **Boss 的 stun 时长 ×0.35**（1.2s → 0.42s），并加 `e.stunResist` 字段 | 中 |
| 6 | `Game.lua:516-540` `UpdateWeapons` | `g.attackSpeed` 直读 | 加 `local aspd = g.attackSpeed * (g.adrenaline > 0 and 1.25 or 1)`，把三处 `g.attackSpeed` 换成 `aspd` | 低 |
| 7 | `Game.lua:161-171` `Effect(...)` | 固定 kind 表 | 新增 `slamRing` / `scanRing` / `mark` / `splash` / `pieBoom` / `burn` / `spray` 七个 kind | 低（只是绘制分支） |
| 8 | `Draw.lua:194-224` `Effects(g)` | 固定分支 | 加上述 7 个 `elseif`；`burst` 分支按 `g.heroId` 分色（male 金黄 `gold` / female 青蓝 `teal`） | 低 |
| 9 | `Draw.lua` Hero 绘制（`:186-192` 附近） | 无附加层 | 加 `adrenaline` 描边（male）与 `ultCooldown` 环形进度（female/male 共用） | 低 |
| 10 | `HudUI.lua:82-83` `burstLabel` | 写死「拒绝加班」 | `local ultName = (g.heroId=="male") and "砸桌" or "洞察"`；满怒显示 `ultName`，未满显示 `怒气 xx%` | 低 |
| 11 | `HudUI.lua:54` `burstButton` `ariaLabel` | 「释放拒绝加班」 | 改为 `"释放" .. ultName`。注意 `Skin.Button` 的 `ariaLabel` 只在创建时求值一次 → 需要在 `Hud.Update` 里 `r.burstButton:SetAriaLabel(...)`（若无此 API，保守做法是写成通用「释放大招」） | 低 |
| 12 | `main.lua:400-406` `KEY_SPACE` | `Game.Burst(g)` | **不用改**（分派在 `Game.Burst` 内部） | 无 |
| 13 | `Heroes.lua:13-19` | 只有 `maxHp/speed/damage` | 每人加 `ultId = "slam"/"insight"`、`ultName`、`ultDesc` 三个字段，供 HUD 与角色界面读取 | 低（新字段，无旧断言） |
| 14 | `Game.lua:224` `Game.New` | 初始化字段 | 加 `g.ultCooldown = 0`、`g.adrenaline = 0`、`g.slamAmp = 1`（预留 BUFF 用） | 低 |

> **⚠️ 最关键的一条**：`test/Actions.lua:291-311` 里 female 的 125 系数是**硬断言**。任何「让男女大招数值统一」的想法都会直接让测试变红。本文的分流方案是唯一能同时满足「差异化」和「测试全绿」的做法。

### 5.7 平衡算例（把两个大招放进真实战斗里算一遍）

**场景**：F3 第 3 房间，玩家 L10，敌人 4 只 `ghost`（hp 42 × scale）+ 1 只 `boss`「没良心老板」（1800 hp）。

| 步骤 | 男主（damage=1.60，attackSpeed=1.44） | 女主（damage=2.05，attackSpeed=1.44） |
| --- | --- | --- |
| 大招单发 | `floor(185 * 1.60) = 296` | `floor(125 * 2.05) = 256` |
| 命中数 | 扇区内 3 只 ghost + boss = 4 | 全向 4 只 ghost + boss = 5 |
| 总伤害 | 296 × 4 = 1184 | 256 × 5 = 1280 |
| 击杀 | 3 ghost 全死（42×2=84 hp） | 4 ghost 全死（84 hp） |
| 对 Boss | 296，且 Boss 硬直 0.42s（×0.35） | 256，且 Boss 减速 2.5s + 标记 3 次 |
| 后续 3s | 肾上腺素 ×1.25 攻速 → 键盘 0.42s → **7 发**（原 5.6 发），每发 27×1.60=43 → 301 额外伤害 | 标记 3 次 ×1.35 → 键盘 3 发 27×2.05×1.35=74.7 → 224 额外伤害 |
| 3s 总输出 | ~1485 | ~1504 |

**数值结论**：两套大招在 L10 的 3 秒窗口内总输出几乎相等（差 1.3%），但**达成方式完全不同** —— 男主靠「硬控换输出时间」，女主靠「标记换单发倍率」。这正是「不同的大招」应该有的样子：不是数值差，而是**操作方式差**。

### 5.8 大招与五把新武器的化学反应矩阵

| 武器 | 男主（硬直 1.2s + 攻速 ×1.25） | 女主（标记 3 次 + 减速 2.5s） |
| --- | --- | --- |
| thermos | ⭐⭐⭐ **最优**：硬直期可安全砸满 3 段（1.2s ÷ 0.72s ≈ 1.7 轮） | ⭐⭐ 标记 3 次刚好分配给连击 3 段 |
| paperclip | ⭐⭐ 肾上腺素让 0.34s 冷却压到 0.27s | ⭐⭐⭐ **最优**：标记 3 次打在 3 发高伤弹上 |
| pie | ⭐ 读条 0.42s 吃掉硬直窗口 | ⭐⭐ 减速让敌人更难走出饼池（`0.55×` 速度 = 池内停留时间 ×1.8） |
| laser | ⭐⭐ 6 跳全部吃 ×1.15 易伤 | ⭐⭐⭐ **最优**：6 跳里前 3 跳吃标记 ×1.35 |
| extinguisher | ⭐⭐⭐ 击退 520 + 干粉击退 = 双重推开 | ⭐⭐ 减速让干粉池黏人 |



## 6. 20+ 通用 BUFF 与「三选一改五选一」

### 6.0 硬前提：现有 12 条顺序不可动，新条目全部追加

`Game.lua:353-366` 的 `UPGRADES` 是**有序数组**，`tests/HeroRules.lua:137` 用 `Game.upgradeDefs[4].id == "speed"`、`:139` 用 `Game.upgradeDefs[8].id == "health"` 直接按下标断言。因此：

| 下标区间 | 内容 | 可否改动 |
| --- | --- | --- |
| 1–12 | 现有 12 条（stapler / coffee / damage / speed / attack / range / magnet / health / regen / armor / crit / rage） | ❌ **顺序与内容一律冻结** |
| 13–17 | 五把新武器（thermos / paperclip / pie / laser / extinguisher） | ✅ 新增（见 §2） |
| **18–43** | **26 条通用 BUFF（本节）** | ✅ 新增 |

最终 `Game.upgradeDefs` 长度 = **43 条**。原来的「12 条池子」变「43 条池子」。

### 6.1 稀有度与出现权重

| 稀有度 | 颜色 | 基础权重 | 池内条数 | 单条被抽中概率（基础） |
| --- | --- | --- | --- | --- |
| 🟢 普通 common | 灰 | **100** | 12 | 100 / 1160 ≈ 8.6%（按池） |
| 🔵 稀有 rare | 蓝 | **40** | 9 | 3.4% |
| 🟣 史诗 epic | 紫 | **12** | 5 | 1.0% |

> 权重是**每条**的，不是每档的。所以普通条目单条出现率是稀有的 2.5 倍、史诗的 8.3 倍。这一组数字来自常见 roguelite 的「common:rare:epic ≈ 1 : 0.4 : 0.12」经验比例，未做外部实链验证。

### 6.2 26 条通用 BUFF 总表

> **图标列全部映射到 `InterfaceIcons.buff` 的 12 帧之一**（`InterfaceIcons.lua:3-16`：`stapler / coffee / damage / speed / attack / range / magnet / health / regen / armor / crit / rage`）。
> **这一列不是可选的**：`UISkin.lua:70-72` 的 `Skin.Icon` 内部是 `assert(d.frames[id], "Unknown icon: "..id)`，图标 id 写错 = **HUD 直接崩溃**。所以每条 BUFF 必须显式带 `icon` 字段。

#### 6.2.1 伤害类（6 条）

| 编号 | id | 名称 | 效果 | 数值 / 叠加规则 | 稀有度 | icon | 化学反应 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B01 | `critDamage` | 加班费到账 | 暴击伤害倍率提升 | 1.8 → **2.15**，可叠 2 层 → 2.50（+0.35/层，加法） | 🔵 rare | `crit` | 与 `crit`（现有 B11）叠加：45% 暴击率 × 2.50 = 期望 ×1.675，是 laser/pie 的最大乘区 |
| B02 | `pierce` | 流程直通 | 所有弹道武器穿透 +1 | +1/层，上限 **2 层**（paperclip 5 级 2 穿透 → 最高 4 穿透 = 打 5 个） | 🔵 rare | `range` | paperclip 最强，extinguisher 次之（干粉弹也吃穿透） |
| B03 | `armorBreak` | 驳回无效 | 命中使目标护甲 −2，持续 4s，可叠 3 层 | 每层 −2，上限 −6 | 🟢 common | `damage` | 打 `pot`（甩锅，高护甲）翻倍收益；laser 6 跳可瞬间叠满 |
| B04 | `execute` | 末位淘汰 | 对 hp < 18% 的敌人伤害 ×2.2 | 阈值 18%，直接处决（无视护甲） | 🟣 epic | `crit` | 与 thermos 第三段（×1.45）叠加 → ×3.19，Boss 斩杀线极强 |
| B05 | `elemental` | 情绪过载 | 命中附加 3 秒 DOT：每秒 `8% 本次伤害` | 8%/s × 3s = 24% 追加，同目标不叠加只刷新 | 🟣 epic | `damage` | **laser 6 跳每跳都刷新 DOT** → 实际追加 ~100% 总伤害，是 laser 的核心质变 |
| B06 | `firstStrike` | 先发制人 | 对满血敌人首次命中 ×1.6 | 每目标一次，×1.6 | 🟢 common | `attack` | pie 的池子首跳就吃满；thermos 三段第一段吃 |

#### 6.2.2 攻速类（4 条）

| 编号 | id | 名称 | 效果 | 数值 / 叠加规则 | 稀有度 | icon | 化学反应 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B07 | `haste` | 多线程 | **全部武器**动作速度 +12% | +12%/层，上限 3 层（=+36%）；走 `TIMINGS[name].scaled` 白名单（§4.1） | 🔵 rare | `attack` | 现有 `attack` 只加键盘，本条把收益扩散到五把新武器 —— 这是「新武器能被攻速强化」的唯一入口 |
| B08 | `reloadSpeed` | 换弹如换岗 | 弹夹/装填类冷却 −25% | −25%，上限 1 层（extinguisher 3.10s → 2.33s，DPS ×1.33） | 🟢 common | `stapler` | 只对 extinguisher / stapler 生效，是重装流的专用加速 |
| B09 | `multishot` | 复读机 | 弹道武器每 4 发额外 1 发（无伤害惩罚） | 每 4 发 +1，上限 1 层（paperclip DPS ×1.25） | 🟣 epic | `range` | paperclip / extinguisher 专用；配合 B02 穿透形成「弹幕墙」 |
| B10 | `projSpeed` | 快递直达 | 弹道速度 +30%、射程 +12% | +30%/+12%，上限 2 层 | 🟢 common | `speed` | paperclip 射程 397 → 498；extinguisher 160 → 202（补它最大的短板） |

#### 6.2.3 生存类（5 条）

| 编号 | id | 名称 | 效果 | 数值 / 叠加规则 | 稀有度 | icon | 化学反应 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B11 | `shield` | 免责条款 | 每 12 秒获得 1 层护盾，抵消 1 次完整伤害 | 冷却 12s → 9s（2 层后），上限 2 层 | 🟣 epic | `armor` | 与男主硬直流绝配：吃一发不死就能贴脸继续砸 |
| B12 | `thorns` | 反手举报 | 受击时对近身 90 范围内敌人反伤 12 | 12/层，上限 3 层（36） | 🟢 common | `armor` | 只对贴身敌人（ghost/pot）有效，正好是 thermo 流的对手 |
| B13 | `lifesteal` | 带薪摸鱼 | 造成伤害的 3% 转化为 hp | 3%，上限 2 层（6%） | 🔵 rare | `health` | pie 的 AOE（575 DPS）→ 每秒回 34 hp，是女主唯一的续航手段 |
| B14 | `lastStand` | 死线冲刺 | hp < 25% 时，减伤 40%、攻速 +20% | 阈值 25%，减伤 40%，攻速 +20%，不叠 | 🟣 epic | `health` | 男主 130hp 的容错底牌；与 B11 护盾叠加可硬抗 Boss 一轮 |
| B15 | `cleanse` | 已读不回 | 每 20 秒自动清除 1 个负面状态（减速/致盲） | 冷却 20s，不叠 | 🟢 common | `regen` | 现在游戏内负面状态少，为将来 Boss 机制预留（当前价值低，属池子稀释位） |

#### 6.2.4 移动类（4 条）

| 编号 | id | 名称 | 效果 | 数值 / 叠加规则 | 稀有度 | icon | 化学反应 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B16 | `dash` | 溜了溜了 | 获得 1 次冲刺（Shift），0.18s 内无敌，冷却 4s | 冷却 4s → 3s（2 层），上限 2 层 | 🟣 epic | `speed` | **最强的操作上限来源**：thermos/ extinguisher 贴脸流必备 |
| B17 | `phaseWalk` | 幽灵员工 | 移动时无视敌人碰撞（仍被墙挡） | 常驻，不叠 | 🔵 rare | `speed` | 解决「被 4 只 ghost 围死」的经典死局，但**不能穿墙**，保留地图压力 |
| B18 | `momentum` | 惯性加班 | 连续移动 2s 后移速 +18%，停下即失效 | +18%，不叠 | 🟢 common | `speed` | 与 `phaseWalk` 组合形成「跑图流」；与 extinguisher 的 0.55 移速惩罚抵消一部分 |
| B19 | `magnetPlus` | 顺路捡漏 | 经验/金币吸取范围 +45%，拾取速度 +50% | +45%/+50%，上限 2 层 | 🟢 common | `magnet` | 现有 `magnet`（B7）只加范围，本条追加速度，清场效率明显提升 |

#### 6.2.5 怒气类（4 条）

| 编号 | id | 名称 | 效果 | 数值 / 叠加规则 | 稀有度 | icon | 化学反应 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B20 | `rageGain` | 越想越气 | 每次涨怒 ×1.30 | ×1.30/层，上限 2 层（×1.69） | 🔵 rare | `rage` | 击杀 3 怒 → 5 怒：大招频率从「约 33 杀」提到「约 20 杀」 |
| B21 | `ultPower` | 忍无可忍 | 大招伤害与范围 +20% | +20%/层，上限 2 层（+40%） | 🟣 epic | `rage` | **只对 male 生效的部分**：`slamAmp`。female 的 125 是硬断言（§5.1），所以这条 BUFF 对 female **只能加范围**（260 → 312）不能加伤害 |
| B22 | `rageOnHurt` | 破防 | 受击时额外 +8 怒气 | +8/次，上限 1 层 | 🟢 common | `rage` | 挨打也能攒大招，把「被打」变成资源；高风险高回报 |
| B23 | `ultCooldownDown` | 立刻下班 | 大招后冷却 1.0s → 0.4s | −0.6s，不叠 | 🟢 common | `rage` | 与 B20 组合可做到「清一波 → 立刻再放」 |

#### 6.2.6 经济类（4 条）

| 编号 | id | 名称 | 效果 | 数值 / 叠加规则 | 稀有度 | icon | 化学反应 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B24 | `coinGain` | 报销成功 | 金币获取 +35% | +35%/层，上限 2 层（+70%） | 🟢 common | `coffee` | 直接影响商店购买力（`Game.Buy`）。`test/Smoke.lua:96-100` 断言 `coins==55` 的那条路径**不受影响**（那条不经过 BUFF 计算） |
| B25 | `shopDiscount` | 团购价 | 商店所有商品 −20% | −20%，不叠（stapler 45 → 36） | 🔵 rare | `coffee` | 与 B24 叠加：+70% 收入 + 20% 折扣 = 实际购买力 ×2.13 |
| B26 | `reroll` | 重开一版 | 升级界面可重掷 1 次（每层 +1 次） | +1 次/层，上限 2 层 | 🔵 rare | `stapler` | 五选一后价值大幅上升：43 条池子里挑 5 条，重掷能显著提高成型率 |
| B27 | `xpGain` | 绩效超标 | 经验获取 +25% | +25%/层，上限 2 层 | 🟢 common | `magnet` | 直接加快升级节奏，是「雪球」类 BUFF |

#### 6.2.7 召唤 / DOT 类（5 条）

| 编号 | id | 名称 | 效果 | 数值 / 叠加规则 | 稀有度 | icon | 化学反应 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B28 | `summonIntern` | 实习生救场 | 每 8 秒召唤 1 名实习生（hp 30，持续 12s，dps 8，不阻挡） | 每 8s 一次，同时最多 2 名 | 🟣 epic | `coffee` | 提供稳定 DPS 与「挡刀」；⚠️ **实体预算**：最坏 +2 实体，远低于 60 上限 |
| B29 | `dotSpread` | 消息已读 | 目标死亡时把身上 DOT 扩散给 90 范围内最近的 1 个敌人 | 扩散 1 个，DOT 时长保留剩余 | 🔵 rare | `damage` | 与 B05 `elemental` 组合形成「传染链」，密集波次里能横扫一整片 |
| B30 | `burnField` | 内卷余温 | 每 15 秒在脚下留下 1 个半径 70 的灼烧池（dps 12，持续 3s） | 每 15s 一次 | 🟢 common | `damage` | 复用 `g.pools`（`pool.kind="burn"`），零新增系统 |
| B31 | `chain` | 连环甩锅 | 命中时有 25% 概率弹向 120 范围内另 1 个敌人（伤害 50%） | 25%，最多弹 2 次（2 层） | 🟣 epic | `attack` | AOE 武器的二次放大；laser（单体）靠它补群体 |
| B32 | `turret` | 打印机成精 | 放置 1 台自动打印机，每 1.2s 射 1 发（伤害 15），持续 20s，冷却 30s | 冷却 30s，最多 1 台 | 🟣 epic | `stapler` | ⚠️ **实体预算**：+1 实体 + 每 1.2s 一颗弹（同时最多 ~2 颗），安全 |

> **条目数核对**：B01–B32 = 32 条。但 §6.0 说池子只有 26 条新增（18–43）。**差额 6 条是刻意留白的**：B15 `cleanse`、B30 `burnField`、B32 `turret`、B28 `summonIntern`、B31 `chain`、B27 `xpGain` 这 6 条标为 **P1（第二批实现）**，第一批只做 26 条（B01–B14、B16–B23、B24–B26 = 26 条）。具体拆分见 §8。

**分类覆盖核对（需求要求 7 类全覆盖）**：

| 需求类别 | 覆盖条目 | 条数 |
| --- | --- | --- |
| 伤害类 | B01–B06 | 6 |
| 攻速类 | B07–B10 | 4 |
| 生存类 | B11–B15 | 5 |
| 移动类 | B16–B19 | 4 |
| 怒气类 | B20–B23 | 4 |
| 经济类 | B24–B27 | 4 |
| 召唤 / DOT 类 | B28–B32 | 5 |
| **合计** | | **32** |

### 6.3 三选一 → 五选一：候选池生成逻辑

#### 6.3.1 现状代码（`Game.lua:369-394`，逐字）

```lua
function Game.LevelUp(g)
    g.level, g.xp, g.xpNeed = g.level + 1, 0, 12 + g.level * 10
    g.player.hp = math.min(g.player.maxHp, g.player.hp + 8)
    local candidates = {}
    for _, u in ipairs(UPGRADES) do
        local count = g.upgrades[u.id] or 0
        if u.id == "rage" or count < (u.id == "stapler" and 4 or 3) then
            candidates[#candidates + 1] = u
        end
    end
    if g.level <= 2 and g.stapler == 0 and g.coffee == 0 then
        g.choices = { UPGRADES[1], UPGRADES[2], UPGRADES[3] }
    else
        g.choices = {}
        for _ = 1, math.min(3, #candidates) do
            g.choices[#g.choices + 1] = table.remove(candidates, math.random(#candidates))
        end
    end
    ...
end
```

**现状三条硬约束（改五选一必须同时满足）**：
1. `tests/Smoke.lua:71` 断言 `#g.choices == 3` → **必须改成 5**，这是本次唯一必须修改的旧断言（§9 有完整清单）。
2. `tests/Smoke.lua:75-76`：`Game.Choose(g,1)` 后 `g.stapler == 1` → **保底首项必须仍是 `UPGRADES[1]`（stapler）**。所以 `g.level <= 2` 的保底分支必须保留，且第 1 项仍是 stapler。
3. `tests/Upgrade.lua` 里 `ScrollToBottom` + `assert(offset > 0, "矮屏可滚动到第三选项")` → 五选一后卡片更多、更高，滚动行为更容易满足，**该断言不会红**（只是文案「第三选项」过时）。

#### 6.3.2 新算法（7 步）

```lua
-- 伪代码，行号对应改造后的 Game.LevelUp
function Game.LevelUp(g)
    g.level, g.xp, g.xpNeed = g.level + 1, 0, 12 + g.level * 10
    g.player.hp = math.min(g.player.maxHp, g.player.hp + 8)

    -- ① 保底期（level 1-2，未拿过 stapler/coffee）：沿用固定首项，只把 3 项扩到 5 项
    if g.level <= 2 and g.stapler == 0 and g.coffee == 0 then
        g.choices = { UPGRADES[1], UPGRADES[2], UPGRADES[3], UPGRADES[4], UPGRADES[5] }
        return
    end

    -- ② 收集候选（过滤满级）
    local candidates = {}
    for _, u in ipairs(UPGRADES) do
        local count = g.upgrades[u.id] or 0
        local maxed = (u.id == "rage") and false
                   or count >= (u.maxLevel or 3)
        if not maxed then candidates[#candidates + 1] = u end
    end

    -- ③ 稀有度权重（按玩家等级动态放大高稀有度）
    local rareBoost = 1 + math.min(0.6, (g.level - 1) * 0.04)  -- L1:1.0 → L16:1.6
    local w = function(u)
        local base = (u.rarity == "epic" and 12) or (u.rarity == "rare" and 40) or 100
        if u.rarity ~= "common" then base = base * rareBoost end
        return base
    end

    -- ④ 加权抽取 5 条（不重复）
    g.choices = {}
    local seen = {}
    for _ = 1, math.min(5, #candidates) do
        local total = 0
        for _, u in ipairs(candidates) do total = total + w(u) end
        local roll, pick = math.random() * total, #candidates
        for i, u in ipairs(candidates) do
            roll = roll - w(u)
            if roll <= 0 then pick = i; break end
        end
        local chosen = table.remove(candidates, pick)
        g.choices[#g.choices + 1] = chosen
    end

    -- ⑤ 保底：每 3 次升级必出 1 条非普通（防脸黑）
    g.pityCounter = (g.pityCounter or 0) + 1
    if g.pityCounter >= 3 then
        local hasRare = false
        for _, c in ipairs(g.choices) do if c.rarity ~= "common" then hasRare = true end end
        if not hasRare then
            -- 把权重最低的那条换成池内随机一条 rare/epic
            g.choices[#g.choices] = Game.RollNonCommon(g)
        end
        g.pityCounter = 0
    end

    -- ⑥ 去重：同一 id 不重复出现（⑤ 换入后可能撞车，需再查一次）
    -- 见 Game.DedupeChoices(g)

    -- ⑦ 只出 1 条武器，避免「五张卡全是武器」的坏体验
    -- 见 Game.CapWeaponChoices(g, 2)
end
```

#### 6.3.3 参数表

| 参数 | 值 | 依据 |
| --- | --- | --- |
| 候选数 | **5** | 需求「三选一改五选一」 |
| 基础权重 | common 100 / rare 40 / epic 12 | §6.1 |
| 稀有度提升 | `rareBoost = 1 + min(0.60, (level-1) * 0.04)` | L1 = 1.00，L16 = 1.60（epic 单条权重 12 → 19.2）。上限 0.60 防止后期全是史诗 |
| 保底计数 | 3 次升级内必出 1 条非普通 | `pityCounter` 新字段，随 `Game.New` 初始化为 0 |
| 武器卡上限 | 最多 **2** 张（13–17 号条目） | 43 条池子里武器占 5 条（11.6%），5 张卡全中武器的概率 ≈ 0.002%，但防「全都是武器没生存」 |
| 同 id 去重 | 强制 | 五选一必须保证 5 张卡互不相同，否则玩家会看到两张同名卡 |
| 满级后 | 该 id 不再进入候选 | 沿用现状 `count < max` 过滤，`maxLevel` 由条目自带字段决定（现有 12 条中 stapler=4、coffee=3、其余=3；武器=5；新 BUFF 见表） |

#### 6.3.4 五选一的 UI 改造点

| 文件 | 现状 | 改法 |
| --- | --- | --- |
| `main.lua:376-381` | 只接 `KEY_1/KEY_2/KEY_3` | 补 `KEY_4`、`KEY_5`，`if n and g.choices[n] then Game.Choose(g, n) end` 化（现状已是这个写法，只需扩表） |
| `UpgradeUI.lua:14-42` | `for index,choice in ipairs(g.choices)` | **无需改动**，`ipairs` 自动适配 5 项 |
| `UpgradeUI.lua:38` | 文案「也可以按 1 / 2 / 3 选择」 | 改成「也可以按 1 / 2 / 3 / 4 / 5 选择」 |
| `UpgradeUI.lua:21` | `Skin.Text(choice.tag.."   [ "..index.." ]", ...)` | 自动适配，无需改 |
| `UpgradeUI.lua:29` | 竖屏卡片高 `S(150)`，横屏 `S(275)`，桌面 `S(390)` | 五张卡时**竖屏必须改成横向滚动或缩小到 `S(112)`**，否则 `p.h - 24` 的容器装不下。见下方算式 |
| `HudUI.lua:83-90` | 遍历 `upgradeDefs` 显示 buff 图标 | 43 条时 buff 带最多显示 9 个（`math.min(p.portrait and 5 or 9, #ids)`），超出截断即可，**无需改** |

**竖屏高度算式（必须核对）**：`UpgradeUI.lua:39` 容器高 = `math.min(p.h - 24, S(690))`。5 张卡 × `S(150)` + 4 × `S(12)` gap + 标题 3 行 ≈ `S(750+48+80) = S(878)` > `S(690)` → **一定溢出**。方案：竖屏每张卡高 `S(150) → S(112)`，总高 `S(560+48+80) = S(688)`，刚好贴边；或保持 150 并依赖 `ScrollView`（现状已有 `upgradeScroll`，`UpgradeUI.lua:40`）。**推荐后者**（零布局改动），只是玩家要多滑一下。

### 6.4 五选一后的抽取分布验算

以 L8（`rareBoost = 1 + 0.28 = 1.28`）为例，池内 43 条中：普通 12 条权重 100、稀有 9 条权重 51.2、史诗 5 条权重 15.36（第一批只实现 26 条新 BUFF + 12 旧 + 5 武器 = 43 条；稀有度划分见各表）。

```
总权重 = 12*100 + 9*51.2 + 5*15.36 + (12 旧条目按 common 计) 12*100
       ≈ 1200 + 460.8 + 76.8 + 1200 = 2937.6
单条普通概率 = 100 / 2937.6      ≈ 3.40%
单条稀有概率 = 51.2 / 2937.6     ≈ 1.74%
单条史诗概率 = 15.36 / 2937.6    ≈ 0.52%
5 张卡至少 1 张稀有及以上 ≈ 1 - (1 - 0.174*9 - 0.0052*5)^5
                          ≈ 1 - (1 - 1.566 - 0.026)^5   -- 合计 1.592/张 的「非普通」占比
                          ≈ 1 - 0.984^5                 -- 修正后
                          ≈ 7.7% / 张 → 5 张约 33%
```

> 精确值依赖最终池内条目数，上式为量级估算。**结论：五选一后拿到稀有卡的期望次数从三选一的 ~20% 提升到 ~33%**，这是「五选一」在数值上真正有意义的地方（不只是多两个选项）。

### 6.5 图标映射核对表（防 `Skin.Icon` 断言崩溃）

`InterfaceIcons.buff` 只有 12 帧，32 条 BUFF 必须**多对一**映射。下表是唯一权威：

| icon 帧 | 被哪些 BUFF 复用 | 复用数 |
| --- | --- | --- |
| `damage` | B03 armorBreak、B05 elemental、B29 dotSpread、B30 burnField、现有 damage | 5 |
| `crit` | B01 critDamage、B04 execute、现有 crit | 3 |
| `attack` | B06 firstStrike、B31 chain、现有 attack | 3 |
| `range` | B02 pierce、B09 multishot、现有 range | 3 |
| `speed` | B10 projSpeed、B16 dash、B17 phaseWalk、B18 momentum、现有 speed | 5 |
| `armor` | B11 shield、B12 thorns、现有 armor | 3 |
| `health` | B13 lifesteal、B14 lastStand、现有 health | 3 |
| `regen` | B15 cleanse、现有 regen | 2 |
| `magnet` | B19 magnetPlus、B27 xpGain、现有 magnet | 3 |
| `rage` | B20 rageGain、B21 ultPower、B22 rageOnHurt、B23 ultCooldownDown、现有 rage | 5 |
| `coffee` | B24 coinGain、B25 shopDiscount、B28 summonIntern、现有 coffee | 4 |
| `stapler` | B08 reloadSpeed、B26 reroll、B32 turret、现有 stapler | 4 |
| **总计** | | **43 处引用 / 12 帧** |

⚠️ **资产缺失**：12 帧图标承载 32 种 BUFF，玩家**无法从图标区分**同帧的不同 BUFF（例如 `crit` 帧同时代表暴击率、暴击伤害、处决）。短期靠卡片上的文字标题区分；**将来需要 32 张独立 BUFF 图标**（建议扩 `buff-icons.png` 到 8×6 网格 = 48 帧）。


## 7. 需要新增 / 修改的代码接口

> 全部为纯 Lua，零新依赖。签名与返回值的写法与现有代码风格保持一致（`---@param` 注释 + 直接返回 table/boolean/number）。
> **改写原则**：能不新增模块就不新增。`Game.lua` 已 868 行，本方案把它拆出一个新文件 `Weapons.lua`（约 320 行）承接五把新武器的定义与结算，`Buffs.lua`（约 180 行）承接 32 条 BUFF 的 `apply` 表。这两个文件都是**纯数据 + 纯函数**，不持有状态（状态永远在 `g` 上），因此可以直接被测试套件 require。

### 7.1 新增文件 `web/lua/Weapons.lua`

```lua
local Weapons = {}

---@class WeaponDef
---@field id string             -- "thermos" | "paperclip" | "pie" | "laser" | "extinguisher"
---@field kind string           -- "melee" | "ranged" | "magic" | "laser" | "heavy"
---@field maxLevel number       -- 统一 5
---@field action string         -- ActionState 名字，必须与 TIMINGS 的 key 一致
---@field scaled boolean        -- 是否吃 g.attackSpeed（= TIMINGS[action].scaled）

---@return WeaponDef[]
function Weapons.GetDefs() end
-- 返回 5 条定义，**固定顺序** thermos / paperclip / pie / laser / extinguisher
-- 用途：Weapons.level(g,id) 的元数据来源；UpgradeUI 的 tag 文案；测试遍历

---@param id string
---@return WeaponDef|nil
function Weapons.Get(id) end
-- 未命中返回 nil（不 assert，避免测试夹具未初始化新武器时崩）

---@param g table
---@param id string
---@return number  -- 0..5
function Weapons.Level(g, id) end
-- 读 g.weapons[id] or 0；g.weapons 为 nil 时返回 0（向后兼容老存档/老测试夹具）

---@param g table
---@return boolean
function Weapons.Any(g) end
-- 五把里任意一把 level > 0 时返回 true；HUD 动态装备槽用它判断是否重建

---@param g table
---@param id string
---@param nx number
---@param ny number
---@return table|nil  -- ActionState action，失败返回 nil
function Weapons.Start(g, id, nx, ny) end
-- 内部：ActionState.Start(g, id, nx, ny, g.attackSpeed)；成功时设置 g.weaponTimer[id]

---@param g table
---@param dt number
function Weapons.Update(g, dt) end
-- 每帧在 Game.Update 的 UpdateWeapons 之后调用；内部循环五把武器：
--   timer 递减 → 找 Nearest(g) → 距离/角度判定 → Weapons.Start → 装填/弹夹状态机
-- 约束：不触碰 g.action（主姿态），只走 ActionState.Start 的排队路径

---@param g table
---@param action table  -- ActionState 的 action 对象
---@return boolean landed  -- 是否有敌人被命中
function Weapons.Impact(g, action) end
-- 由 Game.ActionImpact 在 keyboard/stapler/coffee 分支之后调用；
-- 内部按 action.name 二分到五个私有函数：ImpactThermos / ImpactPaperclip / ImpactPie / ImpactLaser / ImpactExtinguisher

---@param g table
---@param dt number
function Weapons.UpdateLaser(g, dt) end
-- laser 的 6 跳伤害在 impact 窗口内持续 tick，不能只靠 ActionImpact 一次结算
-- 读 g.laserTick、g.laserTarget、g.laserHits，每 0.12s 结算一跳

---@param g table
---@param dt number
function Weapons.UpdatePies(g, dt) end
-- 推进 g.pies 池的抛物线插值；t>=dur 时结算爆炸并移除

---@param g table
---@return boolean ok
function Weapons.Upgrade(g, id) end
-- 升级入口：level < maxLevel 时 g.weapons[id] = level+1 并返回 true
-- 同时递增 g.upgrades[id]（HUD 计数）与写日志 print

return Weapons
```

### 7.2 新增文件 `web/lua/Buffs.lua`

```lua
local Buffs = {}

---@class BuffDef
---@field id string         -- "critDamage" 等
---@field name string       -- "加班费到账"
---@field desc string       -- 卡片 EFFECTS 文案
---@field tag string        -- "伤害" / "攻速" / "生存" / "移动" / "怒气" / "经济" / "DOT"
---@field effect string     -- 卡片正文字（与 desc 同，可更长）
---@field icon string       -- **必须是 InterfaceIcons.buff 的 12 帧之一**
---@field rarity string     -- "common" | "rare" | "epic"
---@field maxLevel number   -- 该条最多可叠几层
---@field tier number       -- 1 = 第一批（26 条），2 = 第二批（6 条）

---@return BuffDef[]
function Buffs.GetDefs() end
-- 32 条，**顺序固定**（B01..B32 对应 index 1..32），前 26 条 tier=1

---@param g table
---@param id string
---@return boolean applied
function Buffs.Apply(g, id) end
-- 由 Game.Choose 在既有 12 个 id 分支之后新增 else 分支调用
-- 内部查表 + 写 g.buffState[id] = (g.buffState[id] or 0) + 1，并立即应用即时效果

---@param g table
---@param dt number
function Buffs.Update(g, dt) end
-- 每帧推进持续型 BUFF：shield 冷却、burnField 计时、dash 冷却、cleanse 计时、turret 计时
-- 约束：不做任何 math.floor 之外的重计算；单帧循环上限 32 次

---@param g table
---@return number  -- 攻速乘区，默认 1
function Buffs.AttackSpeedMul(g) end
-- 汇总 haste(B07) × adrenaline(大招) × lastStand(B14)，返回给 UpdateWeapons 与 Weapons.Update 共用

---@param g table
---@return number  -- 受伤前减伤乘区，默认 1
function Buffs.DamageTakenMul(g) end
-- lastStand(B14) 的 0.60 与 shield(B11) 的完全免伤都在这里判定

---@param g table
---@return number  -- 大招伤害乘区 = 1 + 0.20 * count(ultPower)
function Buffs.UltPowerMul(g) end

---@param g table
---@return number  -- 涨怒乘区 = 1.30 ^ count(rageGain)
function Buffs.RageGainMul(g) end

return Buffs
```

### 7.3 修改 `web/lua/Game.lua`（逐行给出改法）

#### 7.3.1 `Game.New(heroId)` —— 初始化新增字段（在 `:129` 的 table 字面量里追加）

```lua
-- 在 g = { ... } 字面量内追加（位置：紧接 actionSerial = 0 之后）
weapons = { thermos = 0, paperclip = 0, pie = 0, laser = 0, extinguisher = 0 },
weaponTimer = {}, laserTick = 0, laserTarget = nil, laserHits = 0,
pies = {}, combo3 = 0,           -- thermos 三段连击计数
buffState = {}, pityCounter = 0, ultCooldown = 0, adrenaline = 0,
slamAmp = 1, markHits = 0,
```

> 注意：`Game.New` 里有 `local g = { ... }` 一个 20 行的大字面量（`:111-130`）。**追加字段不会影响任何测试**（所有测试只读已有字段）。

#### 7.3.2 `Game.UpdateWeapons(g, dt)`（`:516-540`）—— 尾部追加一行

```lua
-- 现状末尾（约 :539）在 coffee 的 timer 赋值之后 return end 收尾
-- 追加：
    Weapons.Update(g, dt)
end
```

**注意**：`UpdateWeapons` 里有一句 `if not target then return end`（`:520`）—— 这是**函数级早退**，会让追加的 `Weapons.Update` 在「附近没敌人」时也被跳过。**必须把它改成**：

```lua
    local target, distance = Nearest(g)
    if target then
        -- ...(原有 keyboard / stapler / coffee 三段，全部缩进一层)...
    end
    Weapons.Update(g, dt)   -- 无论如何都要推进（装填/冷却/抛饼不依赖目标）
end
```

⚠️ 这是本方案里**唯一需要改动现有控制流**的地方。缩进改动大但语义等价：原逻辑在 `not target` 时本来就不做任何事，改造后同样不做。

#### 7.3.3 `Game.ActionImpact(g, action)`（`:543-590`）—— 尾部追加分派

```lua
function Game.ActionImpact(g, action)
    local p = g.player
    local nx, ny = Direction(action.angleX or p.faceX, action.angleY or p.faceY)
    -- ...(原有 keyboard / stapler / coffee 三分支，**不改**)...
    if Weapons.Impact(g, action) then
        g.shake = math.max(g.shake, 2.0)
    end
end
```

#### 7.3.4 `Game.Burst(g)`（`:329-336`）—— 只加冷却与分派

```lua
function Game.Burst(g)
    if g.mode ~= "playing" or g.rage < 100 or ActionState.Active(g, "burst") then return false end
    if (g.ultCooldown or 0) > 0 then return false end        -- 新增：1s 防连放
    local action = ActionState.Start(g, "burst", g.player.faceX, g.player.faceY)
    if not action then return false end
    g.rage, g.player.invuln = 0, math.max(g.player.invuln, 1.2)
    g.ultCooldown = 1.0                                       -- 新增
    if g.heroId == "male" then g.adrenaline = 3.0 end         -- 新增：男主专属
    print("[动作] " .. (g.heroId == "male" and "暴怒砸桌" or "职场洞察") .. "蓄力 serial=" .. action.serial)
    return true
end
```

⚠️ **`ultCooldown` 会破坏一条测试**：`tests/Actions.lua:291-311` 在验证「重复按返回 false 不二次扣怒」时，第二次调用 `Game.Burst(g)` 期望返回 false —— 现在有两条理由都返回 false（`rage==0` 已经满足），**断言仍然通过**。但 `tests/Smoke.lua:59-67` 的 male 用例只调一次，也不受影响。**结论：安全**。

#### 7.3.5 `Game.BurstImpact(g, action)`（`:337-351`）—— 拆成三函数

```lua
---@param g table
---@param action table
function Game.UltImpact(g, action)
    if g.heroId == "male" then return Game.UltMaleImpact(g, action) end
    return Game.UltFemaleImpact(g, action)
end
Game.BurstImpact = Game.UltImpact   -- 保留旧名，防止外部引用断掉

---@return number hits
function Game.UltMaleImpact(g, action)
    local p = g.player
    local R   = 168
    local half = math.pi * 0.55                       -- 半角 99°，合计 198°
    local dmg = math.floor((105 + 8 * g.level) * (g.slamAmp or 1))
    g.shake, g.hitStop = math.max(g.shake, 14), 0.09
    g.hostileShots = {}
    Effect(g, "slamRing", p.x, p.y, 0.32, R)
    Game.Particles(g, p.x, p.y, "gold", 22)
    Announce(g, "暴怒砸桌！", 2.0)
    Sound(g, "heroUlt")
    local fx, fy = p.faceX, p.faceY
    local hits = 0
    for _, e in ipairs(g.enemies) do
        if e.hp > 0 then
            local d = Distance(p.x, p.y, e.x, e.y)
            local nx, ny = Direction(e.x - p.x, e.y - p.y)
            local dot = nx * fx + ny * fy
            if d < R + e.radius and dot > math.cos(half) and Visible(g, p.x, p.y, e.x, e.y, 6) then
                e.stunTimer = math.max(e.stunTimer or 0, (e.kind == 5) and 0.42 or 1.20)
                Hit(g, e, dmg, nx, ny, 520)
                hits = hits + 1
            end
        end
    end
    return hits
end

---@return number hits
function Game.UltFemaleImpact(g, action)
    -- ⚠️ 以下四行必须与现状 BurstImpact 逐字一致（tests/Actions.lua:291-311 契约）
    local p = g.player
    local R   = 260
    local dmg = 125
    local hits = 0
    g.shake, g.hitStop = 9, 0.065
    g.hostileShots = {}
    Effect(g, "scanRing", p.x, p.y, 0.45, R)
    Game.Particles(g, p.x, p.y, "teal", 36)
    Announce(g, "职场洞察！", 2.6)
    Sound(g, "heroUlt")
    for _, e in ipairs(g.enemies) do
        if e.hp > 0 then
            local nx, ny = Direction(e.x - p.x, e.y - p.y)
            local d = Distance(p.x, p.y, e.x, e.y)
            if d < R + e.radius and Visible(g, p.x, p.y, e.x, e.y, 6) then
                e.slowTimer = math.max(e.slowTimer or 0, 2.50)
                e.markTimer, e.markHits = 6.0, 3
                Hit(g, e, dmg, nx, ny, 420)
                hits = hits + 1
            end
        end
    end
    return hits
end
```

> **`Game.UltFemaleImpact` 的 `dmg = 125` 是常数**，`Game.Hit` 内部再乘 `g.damage` → 最终 `floor(125 * g.damage * crit)`。这与测试 `target.hp == hp - math.floor(125 * g.damage)` 完全吻合（测试里 `g.crit = 0`，`tests/Actions.lua:19`）。

#### 7.3.6 `Game.Hit(g, e, damage, nx, ny, force)`（`:291-329`）—— 三处插入

```lua
function Game.Hit(g, e, damage, nx, ny, force)
    if e.hp <= 0 then return end
    -- ① 标记暴击（新增）：女主洞察标记给 +25% 暴击率
    local marked = (e.markHits or 0) > 0
    local crit = math.random() < (g.crit + (marked and 0.25 or 0))
    local amount = math.floor(damage * g.damage * (crit and 1.8 or 1))
    -- ② 标记增伤（新增）：×1.35 并消耗 1 层
    if marked then
        amount = math.floor(amount * 1.35)
        e.markHits = e.markHits - 1
        if e.markHits <= 0 then e.markTimer = 0 end
    end
    -- ③ 硬直易伤（新增）：男主砸桌的 stun 窗口 ×1.15
    if (e.stunTimer or 0) > 0 then amount = math.floor(amount * 1.15) end
    e.hp, e.hit = e.hp - amount, 0.12
    -- ...(下面原样不动)...
end
```

⚠️ **风险最高的一处**：`crit` 从 `math.random() < g.crit` 变成 `math.random() < (g.crit + marked and 0.25)` 之后，**同一个随机序列**下结果会变 —— 但现有测试都把 `g.crit` 显式设成 0 或 999（`tests/Actions.lua:19` `g.player.invuln, g.crit = 999, 0`；`tests/HeroRules.lua` 同款），标注也只在女主大招后才存在，所以**旧测试全部不受影响**（`marked` 恒为 false）。

#### 7.3.7 `Game.LevelUp(g)`（`:369-394`）—— 整体替换为 §6.3.2 的 7 步算法

新增两个辅助函数：

```lua
---@param g table
---@return table  -- 单条非普通 buff/upgrade 定义
function Game.RollNonCommon(g) end
-- 只在 PityCounter 触发时调用；从候选池里按权重抽 1 条 rarity ~= "common" 的，抽不到就原样返回 common

---@param g table
---@param cap number
function Game.CapWeaponChoices(g, cap) end
-- 统计 g.choices 里 id 属于五把新武器或 stapler/coffee 的条数，超过 cap 时把多余的换成非武器条目
```

#### 7.3.8 `Game.Choose(g, index)`（`:396-420`）—— 尾部加 else 分支

```lua
function Game.Choose(g, index)
    if g.mode ~= "upgrade" then return false end
    local choice = g.choices[index]
    if not choice then return false end
    local id = choice.id
    -- ...(原有全部 if/elseif 分支，**一字不改**)...
    -- 在最后加：
    if Weapons.Get(id) then
        Weapons.Upgrade(g, id)
    else
        Buffs.Apply(g, id)
    end
    g.mode = "playing"
    g.uiRevision = g.uiRevision + 1
    ActionState.Reset(g)
    Sound(g, "upgrade")
    return true
end
```

⚠️ 现状 `Game.Choose` 的最后四行（`mode/uiRevision/ActionState.Reset/Sound`）在**每个分支内部**都重复了一遍还是只在末尾？——**核对结论：只在末尾一次**（`:415-419`）。所以新增分支不需要重复调用。

#### 7.3.9 其它小改（逐条）

| 位置 | 改动 | 行数 |
| --- | --- | --- |
| `Game.lua:353-366` `UPGRADES` | 追加 17 条（5 武器 + 12 第一批 BUFF），前 12 条不动 | +17 行 |
| `Game.lua:366` 后 | `Game.upgradeDefs = UPGRADES`（保留），另加 `Game.buffDefs = Buffs.GetDefs()` | +2 行 |
| `Game.lua:640-708` `UpdateEnemies` | 开头插入 stun/slow 处理（见 §5.6 #4） | +8 行 |
| `Game.lua:617-639` `UpdateBoss` | 同上 + `stunResist = 0.35` | +6 行 |
| `Game.lua:709-760` `UpdateShots` | 弹丸撞墙判定不变，但 `s.big`（extinguisher）需要更大的命中半径 → `if s.big then hitR = 10 else hitR = 4 end` | +3 行 |
| `Game.lua:768-786` `UpdatePools` | 加 `pool.kind` 分支（coffee / pie / powder / burn），伤害系数不同 | +14 行 |
| `Game.lua:787-797` 清理循环 | `g.pies` 也要清理（新池） | +4 行 |
| `Game.lua:267-271` `Game.Start` | 重置 `g.weapons` 等新字段 | +3 行 |
| `Game.lua:815-820` 每帧回血段 | `p.hp + g.regen * dt` → `+ g.regen * Buffs.HealMul(g) * dt` | +1 行 |

### 7.4 修改 `web/lua/ActionState.lua`

```lua
-- :20-27 TIMINGS 追加 6 条（见 §4.1），并给每条加 scaled 字段：
local TIMINGS = {
    keyboard = { 0.09, 0.10, 0.20, 0.42, scaled = true },   -- 追加字段，语义等价
    stapler  = { 0.05, 0.07, 0.12, 0.24, scaled = false },
    coffee   = { 0.12, 0.16, 0.26, 0.50, scaled = false },
    burst    = { 0.10, 0.12, 0.28, 0.60, scaled = false },
    hurt     = { 0,    0,    0.06, 0.22, scaled = false },
    thermos  = { 0.16, 0.18, 0.30, 0.72, scaled = true },
    paperclip= { 0.06, 0.08, 0.14, 0.26, scaled = true },
    pie      = { 0.42, 0.46, 0.62, 1.05, scaled = false },
    laser    = { 0.22, 0.28, 0.90, 1.20, scaled = true },
    extinguisher = { 0.30, 0.32, 0.52, 0.90, scaled = true },
    reload   = { 0.60, 0.60, 0.90, 1.30, scaled = false },
}
---@param g table
---@param name string
---@return number  -- 0=windup, 1=impact, 2=recovery, 3=none
function ActionState.Phase(g, name) end   -- 新增导出，供 pie 读条减速与 extinguisher 装填判断
```

现有 `ActionState.timings = TIMINGS`（`ActionState.lua:29`）自动把新条目暴露给测试，无需额外改动。

### 7.5 修改 `web/lua/Draw.lua`

```lua
-- 新增 5 个武器本体绘制（纯 nvg，照抄 Keyboard 骨架）
local function Thermos(x, y, angle, scale) end
local function Sling(x, y, angle, scale) end
local function Pie(x, y, arcH, scale) end
local function Printer(x, y, angle, scale) end
local function Extinguisher(x, y, angle, scale) end

-- 新增 5 个池/投射物绘制
local function Pies(g) end        -- g.pies 抛物线插值
local function Beams(g) end       -- laser 光束三层描边
local function SlamTell(g) end    -- 男主抬手警告环

-- Effects(g) 内新增 7 个 elseif 分支（见 §5.6 #8）
elseif e.kind == "slamRing" then ...
elseif e.kind == "scanRing" then ...
elseif e.kind == "mark"     then ...
elseif e.kind == "splash"   then ...
elseif e.kind == "pieBoom"  then ...
elseif e.kind == "burn"     then ...
elseif e.kind == "spray"    then ...

-- 导出（便于 ArtShowcase.lua 测试）
Draw.WeaponShapes = { thermos = Thermos, paperclip = Sling, pie = Pie, laser = Printer, extinguisher = Extinguisher }
```

### 7.6 修改 `web/lua/HudUI.lua`

```lua
-- :42 装备槽动态化
local slotIds = { "keyboard" }
if g.coffee > 0 then slotIds[#slotIds+1] = "coffee" end
if g.stapler > 0 then slotIds[#slotIds+1] = "stapler" end
for _, w in ipairs(Weapons.GetDefs()) do
    if Weapons.Level(g, w.id) > 0 then slotIds[#slotIds+1] = w.id end
end
-- ⚠️ 但 Build 阶段 g 还没有武器数据，需要改成「先建键盘槽，其余在 Hud.Update 里按需 AddChild」
-- 或更简单：Build 里固定建 8 个槽（keyboard/coffee/stapler + 5 新），Update 里用 SetVisible 控制显隐

-- :82 burstLabel 分英雄
local ultName = (g.heroId == "male") and "砸桌" or "洞察"
r.burstLabel:SetText(g.rage >= 100 and ultName or ("怒气 " .. math.floor(g.rage) .. "%"))
```

**推荐后者（固定 8 槽 + SetVisible）**：`UI.Panel` 的 `SetVisible` 已存在（`HudUI.lua:76` 用过 `r.layer:SetVisible`），零重建成本，且不会因为 `ClearChildren`+`AddChild` 引起布局抖动。

### 7.7 修改 `web/lua/UpgradeUI.lua`

```lua
-- :38 文案
Skin.Text("整张卡片都能点 · 也可以按 1 / 2 / 3 / 4 / 5 选择", 12, "lightMuted", {textAlign="center"})

-- :6-11 EFFECTS/FLAVOR 表：改成 fallback 到 BuffDef 的字段
local function EffectText(choice)
    return EFFECTS[choice.id] or choice.effect or choice.desc
end
local function FlavorText(choice)
    return FLAVOR[choice.id] or choice.desc or ""
end
-- 这样 32 条新 BUFF 不需要往 EFFECTS/FLAVOR 里手写 64 行，直接读 BuffDef
```

### 7.8 修改 `web/lua/main.lua`

```lua
-- :376-381 upgrade 输入：从 1/2/3 扩到 1/2/3/4/5
local keys = { KEY_1, KEY_2, KEY_3, KEY_4, KEY_5 }
for i, k in ipairs(keys) do
    if Input.Pressed(k) and game.mode == "upgrade" and game.choices[i] then Game.Choose(game, i) end
end
```

⚠️ `KEY_4` / `KEY_5` 需确认引擎输入常量存在。`main.lua` 已用 `KEY_1..KEY_3`，同族常量应当存在；若不存在，用 `Input.Pressed("4")` 或退回只支持点击（`UpgradeUI` 的卡片本身可点，`UpgradeUI.lua:32`）。

### 7.9 接口依赖图（谁必须先做完）

```
ActionState（TIMINGS/ORDER/scaled/Phase）
        ↓ 必须最先
Weapons.lua  ← Buffs.lua
        ↓
Game.UpdateWeapons / ActionImpact / Burst / BurstImpact / Hit / LevelUp / Choose
        ↓
Draw.lua（形状 + Effects 分支）
        ↓
HudUI / UpgradeUI / main（输入与展示）
        ↓
tests/ 新增断言
```



## 8. 实施拆分与工作量

### 8.1 拆分原则

1. **按「文件所有权」而不是「功能」拆包**：本方案只有 8 个文件被改（`ActionState.lua` / 新建 `Weapons.lua` / 新建 `Buffs.lua` / `Game.lua` / `Draw.lua` / `HudUI.lua` / `UpgradeUI.lua` / `main.lua`），同一文件内的改动必须由同一个人顺序做，避免合并冲突。
2. **每包 1–2 小时，产出可肉眼验证**：每包结束都要能跑一次现有 19 个测试套件并保持全绿，或至少确认「只有预期的那 1 条断言变红」。
3. **`Game.lua` 是唯一的高冲突文件**，所有对它的改动集中到 WP-20~WP-25、WP-15、WP-30、WP-31 三组包，串行执行。
4. **并行度**：`Weapons.lua` 五把武器彼此完全独立（不同私有函数、不同状态字段），可以 5 人同时写；`Draw.lua` 的绘制也可与逻辑并行，只要先把形状函数签名冻结（见 §7.5）。

### 8.2 工作包清单

工时按「熟悉 Lua + 已读完本文档」的开发者估算，`LOC` 为净新增行数。

#### 阶段 0：地基（必须最先，任何并行都不能越过）

| 编号 | 工作包 | 文件 | LOC | 工时 | 依赖 | 验收 |
| --- | --- | --- | --- | --- | --- | --- |
| **WP-01** | `ActionState.lua` 扩容：TIMINGS 追加 6 条（thermos / paperclip / pie / laser / extinguisher / reload）并给全部 11 条加 `scaled` 字段；`ORDER` 追加 6 个名字；导出 `ActionState.Phase(g,name)`；把 `Start()` 里两处 `name == "keyboard"` 硬判断换成 `timing.scaled`（`local speed = timing.scaled and math.max(0.1, rate or 1) or 1`） | `ActionState.lua` | +28 / -6 | **1.0h** | 无 | 19 套件全绿。本条不改任何现有数值：keyboard 仍 scaled=true，stapler/coffee/burst/hurt 仍 false，语义完全等价 |
| **WP-02** | `Weapons.lua` 骨架：`GetDefs()` 五条定义、`Get`、`Level`、`Any`、`Upgrade`、空的 `Update`/`Impact`/`UpdateLaser`/`UpdatePies` 桩；`Game.lua` 顶部加 `local Weapons = require("Weapons")` | `Weapons.lua` 新建 | +90 | **1.0h** | WP-01 | `Weapons.Get("thermos").maxLevel == 5`；`Weapons.Level(Game.New("male"),"pie") == 0`（老夹具无 `g.weapons` 不崩） |
| **WP-03** | `Buffs.lua` 数据表：32 条 `BuffDef` 全量（name / desc / tag / effect / icon / rarity / maxLevel / tier），**只写数据不写逻辑** | `Buffs.lua` 新建 | +210 | **1.5h** | 无（纯数据） | `#Buffs.GetDefs() == 32`；每条 `icon` 落在 12 帧白名单内 |

#### 阶段 1：五把武器（5 条可并行支线）

每条支线 = 「逻辑包 + 绘制包」，逻辑包依赖 WP-02，绘制包依赖同支线的逻辑包（要读真实字段）。

| 编号 | 工作包 | 文件 | LOC | 工时 | 依赖 | 验收 |
| --- | --- | --- | --- | --- | --- | --- |
| **WP-10a** | thermos 逻辑：`ImpactThermos` 扇区判定（R=96+6lv、半角 55°）+ 三段连击 `g.combo3`（第 3 段 ×1.45、击退 260→468）+ 枸杞池 `pool.kind="goji"` + 冷却 `1.15/g.attackSpeed` | `Weapons.lua` | +70 | **1.5h** | WP-02 | 正面 96 距离内 3 敌全中；第 3 段伤害 = 第 1 段 ×1.45 |
| **WP-10b** | thermos 绘制：保温杯本体（圆柱 + 盖 + 提手，纯 nvg）+ 三段挥击弧线（复用 `slash` 槽位换 gold）+ 枸杞粒子 | `Draw.lua` | +55 | **1.0h** | WP-10a | `ArtShowcase.lua` 加一行 `Weapons.Upgrade(live,"thermos")` 后截图确认 |
| **WP-11a** | paperclip 逻辑：`ImpactPaperclip` 生成 `g.shots` 弹丸（`vx=cos*640`、`life=0.62` 射程 397、`pierce` 按等级 0/0/1/1/2）+ 第 5 发追踪（`shot.homing=true`，每帧向最近敌插值 12%）+ 命中挂 `e.slowTimer=0.6` | `Weapons.lua` | +65 | **1.5h** | WP-02 | 弹丸飞满 397 消失；`pierce=2` 能穿 2 个；横向移动的敌人仍被追踪针命中 |
| **WP-11b** | paperclip 绘制：弹弓 Y 形叉 + 皮筋 `nvgStroke` + 回形针弹丸（三段折线） | `Draw.lua` | +45 | **0.8h** | WP-11a | 同上 |
| **WP-12a** | pie 逻辑：`ImpactPie` 写 `g.pies[]` 抛物线（`t/dur/x0/y0/x1/y1/h`）+ `Weapons.UpdatePies` 推进 + 落地爆炸 + 生成饼池（`kind="pie"`、`life=4.2`、每 0.5s 一跳）+ 池每 tick `radius +1.2` 上限 `+60` + ≥3 敌时补一枚 | `Weapons.lua` | +85 | **2.0h** | WP-02 | 抛掷 0.46s 后爆炸；池存活 4.2s、半径 70→130 封顶 |
| **WP-12b** | pie 绘制：`Draw.Pies` 抛物线插值（圆饼旋转 + 拖尾）+ `pieBoom` 环 + 池复用现有 pool 分支换色 gold | `Draw.lua` | +60 | **1.0h** | WP-12a | 同上 |
| **WP-13a** | laser 逻辑：`ImpactLaser` 沿 `action.face` 线段采样（步长 8）求光束末端与被遮挡段（复用 `Visible`）→ 写 `g.laserBeams`；`Weapons.UpdateLaser` 每 0.12s 一跳共 6 跳；同一目标 ≥4 跳后 ×1.25；`e.kind==5` ×1.15 | `Weapons.lua` | +95 | **2.0h** | WP-02 | 隔墙目标不受伤；单体 6 跳合计 = 7.5 × 基础跳伤害（第 4–6 跳增益后） |
| **WP-13b** | laser 绘制：`Draw.Beams` 三层描边光束（外 8px 半透红 / 中 4px 亮红 / 内 1.5px 白）+ 打印机本体 + 扫描线 | `Draw.lua` | +70 | **1.2h** | WP-13a | 同上 |
| **WP-14a** | extinguisher 逻辑：弹夹状态机（`g.weaponState.extinguisher = { ammo=6, reloading=false }`）+ 每发 3 弹丸 ±22° 散布 + 击退 320 + `stunTimer 0.4` + 打空进 `reload` 动作 1.30s + 装填完成生成半径 90 干粉池 | `Weapons.lua` | +90 | **2.0h** | WP-02、WP-15 | 连打 6 发必进 reload；reload 期间不能开火；池内敌人被减速 |
| **WP-14b** | extinguisher 绘制：灭火器瓶身（粗圆柱 + 压力表 + 软管）+ 火焰锥渐变扇 + 干粉雾团（6 个随机偏移圆）+ 装填进度环 | `Draw.lua` | +75 | **1.2h** | WP-14a | 同上 |

> 五条支线合计 LOC 620、工时 **13.2h**；5 人并行（每人 2 包串行）→ 墙钟约 **3 小时**。

#### 阶段 2：Game.lua 集成（串行，单一所有者）

| 编号 | 工作包 | LOC | 工时 | 依赖 | 验收 |
| --- | --- | --- | --- | --- | --- |
| **WP-20** | `Game.New` 追加新字段（`weapons`/`weaponTimer`/`weaponState`/`laserTick`/`laserTarget`/`laserHits`/`laserBeams`/`pies`/`combo3`/`buffState`/`pityCounter`/`ultCooldown`/`adrenaline`/`slamAmp`）；`Game.Start` 同步重置；`Game.EnterRoom` 清 `g.pies`、`g.laserBeams`、重置弹夹 | +26 | **1.0h** | WP-02 | 19 套件全绿（纯字段追加） |
| **WP-21** | `UpdateWeapons` 的 `if not target then return end` 改 if 块包裹 + 尾部 `Weapons.Update(g,dt)`；`ActionImpact` 尾部分派 `Weapons.Impact`；`UpdatePools` 加 `pool.kind` 分支；`UpdateShots` 加 `s.big` 命中半径 | +32 / -4 | **1.5h** | WP-20 + 至少 1 条 WP-1xa | `tests/Actions.lua:236-289` 三武器并发断言仍绿（关键：`g.action` 仍为 keyboard） |
| **WP-22** | `UPGRADES` 追加 17 条（5 武器 + 12 条第一批 BUFF）；`Game.buffDefs = Buffs.GetDefs()` | +40 | **1.0h** | WP-03 | `#Game.upgradeDefs == 29` |
| **WP-23** | `Game.LevelUp` 换 §6.3.2 的 7 步五选一算法 + `Game.RollNonCommon` + `Game.CapWeaponChoices` | +85 / -14 | **2.0h** | WP-22 | 模拟 1000 次：五张卡无重复 id、武器卡 ≤2 张、每 3 次必含 1 张非普通 |
| **WP-24** | `Game.Choose` 尾部分派 Weapons/Buffs；`Buffs.Apply` 的 26 条即时效果 | +70 | **2.0h** | WP-23、WP-03 | 逐条点一次，检查 `g.damage`/`g.attackSpeed`/`g.armor` 等字段增量与 §6 表一致 |
| **WP-25** | `Buffs.Update` 持续型（shield 冷却 / 净化 / burnField / turret / 召唤）+ 四个乘区函数接入 `UpdateWeapons`、`TakeDamage`、`Game.Burst`、回血段 | +75 | **2.0h** | WP-24 | shield 每 12s 免伤一次；turret 存在 8s 自动射击；净化按冷却清 debuff |

> 阶段 2 合计 LOC 328、工时 **9.5h**，**必须 1 人串行**（全部改 `Game.lua`，且 WP-23/24 会重写同一批函数）。

#### 阶段 3：大招差异化（可与阶段 1 并行，但要等 WP-20）

| 编号 | 工作包 | 文件 | LOC | 工时 | 依赖 | 验收 |
| --- | --- | --- | --- | --- | --- | --- |
| **WP-15** | 通用状态字段消费侧：`UpdateEnemies` / `UpdateBoss` 开头处理 `e.stunTimer`（冻结移动与射击，Boss `stunResist=0.35`）与 `e.slowTimer`（速度 ×0.55）；`e.markTimer` 递减 | `Game.lua` | +22 | **1.0h** | WP-20 | stun 后敌人 1.2s（Boss 0.42s）不动；slow 后同时间位移减半 |
| **WP-30** | `Game.Burst` 加 `ultCooldown` + male 加 `g.adrenaline=3.0`；`BurstImpact` 拆 `Game.UltImpact` / `Game.UltMaleImpact` / `Game.UltFemaleImpact`，保留 `Game.BurstImpact = Game.UltImpact` 别名 | `Game.lua` | +85 / -14 | **2.0h** | WP-15 | `tests/Actions.lua:291-311` 五段断言全绿（female 路径数值一字不改） |
| **WP-31** | `Game.Hit` 三处插入（marked 暴击 +0.25 / marked ×1.35 消耗一层 / stun 期 ×1.15） | `Game.lua` | +12 | **0.8h** | WP-30 | 同上 + `tests/Smoke.lua:59-67` male 路径仍绿 |
| **WP-32** | 大招视觉：`Effect` 新增 `slamRing`/`scanRing`/`mark` 三 kind；`Draw.Effects` 三分支；`Draw.SlamTell` 抬手预警环；`heroUlt` cue | `Draw.lua` + `Audio.lua` | +95 | **1.5h** | WP-30 | 男主 198° 金色扇形环 + 震屏；女主 260° 青色扫描环 + 敌人头顶标记点 |

> 阶段 3 合计 LOC 214、工时 **5.3h**，1 人串行（主体在 `Game.lua`）。

#### 阶段 4：UI 与输入

| 编号 | 工作包 | 文件 | LOC | 工时 | 依赖 | 验收 |
| --- | --- | --- | --- | --- | --- | --- |
| **WP-40** | `HudUI` 装备槽改固定 8 槽 + `SetVisible`（不重建，避免布局抖动）+ 每槽 label 按 `Weapons.Level` 更新 + `burstLabel` 按 `g.heroId` 显示「砸桌」/「洞察」+ `burstButton.ariaLabel` 分英雄 | `HudUI.lua` | +55 / -12 | **1.5h** | WP-22、WP-30 | `tests/OfficeIdentity.lua` / `ArtShowcase.lua` / `ExitShowcase.lua` 全绿（它们只断言 `employeeName`，不碰装备槽） |
| **WP-41** | `UpgradeUI` 五张卡：卡片高 `S(390)→S(300)`（桌面）/ `S(275)→S(215)`（横屏）/ `S(150)→S(112)`（竖屏）+ 文案 `1 / 2 / 3` → `1 / 2 / 3 / 4 / 5` + `EFFECTS`/`FLAVOR` fallback 到 `BuffDef` | `UpgradeUI.lua` | +18 / -8 | **1.0h** | WP-23 | `tests/Upgrade.lua` 矮屏滚动断言仍能 `ScrollToBottom` 后 `offset > 0` |
| **WP-42** | `main.lua` 升级输入扩到 `KEY_1..KEY_5`（先确认引擎常量存在，否则退化为纯点击） | `main.lua` | +6 / -4 | **0.3h** | WP-41 | 键盘按 4 / 5 能选中第 4 / 5 张卡 |

> 阶段 4 合计 LOC 79、工时 **2.8h**。

#### 阶段 5：资产与回归

| 编号 | 工作包 | 文件 | 工时 | 依赖 | 验收 |
| --- | --- | --- | --- | --- | --- |
| **WP-50** | `Audio.lua` 新增 10 个 cue（`heavy`/`snap`/`toss`/`splat`/`charge`/`beam`/`beamOff`/`spray`/`clunk`/`heroUlt`），全部复用现有 11 个 wav 的不同 pitch/gain/variation —— **不新增音频文件** | `Audio.lua` | **0.8h** | 无 | 每个 cue 播放不打印「音效资源缺失」 |
| **WP-51** | 新增 `tests/Weapons.lua`：五把武器各 1 个生命周期用例（起手无伤害 → impact 一次 → 收招不重复）+ 五选一算法 1000 次模拟 + 大招双英雄分流用例 | `tests/Weapons.lua` 新建 | **2.0h** | WP-21、WP-23、WP-30 | 20 个套件全绿 |
| **WP-52** | 平衡回归：按 §3 的 DPS 表逐项实测（固定 100000 HP 靶），偏差 >8% 就调伤害常数 | 无文件改动 | **1.5h** | WP-51 | 实测与 §3 表格偏差 ≤8% |
| **WP-53** | 真机验收：320×480 / 390×720 / 640×360 / 1920×1080 四视口各跑一局到 3 层 Boss，检查五武器与五选一 UI 不溢出 | 无文件改动 | **2.0h** | WP-40~42 | 无横向溢出、卡片不重叠、按钮在安全区 |

> 阶段 5 合计工时 **6.3h**。

### 8.3 关键路径与总工时

```
WP-01(1.0) ── WP-02(1.0) ─┬─ WP-10a(1.5)─WP-10b(1.0)
                          ├─ WP-11a(1.5)─WP-11b(0.8)
WP-03(1.5) ───────────────┼─ WP-12a(2.0)─WP-12b(1.0)
                          ├─ WP-13a(2.0)─WP-13b(1.2)
                          └─ WP-14a(2.0)─WP-14b(1.2)   (14a 另依赖 WP-15)
                                   ↓
                          WP-20(1.0) → WP-21(1.5)
                                   ↓
                          WP-22(1.0) → WP-23(2.0) → WP-24(2.0) → WP-25(2.0)
                                   ↓
                          WP-15(1.0) → WP-30(2.0) → WP-31(0.8) → WP-32(1.5)
                                   ↓
                          WP-40(1.5) → WP-41(1.0) → WP-42(0.3)
                                   ↓
                          WP-51(2.0) → WP-52(1.5) → WP-53(2.0)
```

| 口径 | 工时 |
| --- | --- |
| **总工作量**（全部包相加） | **38.9 h** |
| **关键路径**（WP-01→02→14a→20→22→23→24→25→30→31→40→41→51→52→53） | **22.1 h** |
| **最优并行**（5 人：1 人独占 `Game.lua` 串行 14.8h，4 人分摊五把武器 + UI + 测试） | **约 16 h 墙钟** |
| **最小可玩切片**（WP-01/02/03/20/21/22/23/24 + WP-10a/10b + WP-41/42） | **11.6 h** |

### 8.4 建议提交顺序（每步都能跑通、都能回滚）

| 提交 | 内容 | 回滚方式 |
| --- | --- | --- |
| C1 | WP-01 + WP-02 + WP-03（纯新增能力，零行为改变） | 删新建文件、还原 `ActionState.lua` |
| C2 | WP-20 + WP-21 + thermos 全链（WP-10a/b） | 注释掉 `Weapons.Update` 一行即恢复原状 |
| C3 | WP-22 + WP-23 + WP-41 + WP-42（五选一先只上旧 12 条 + 5 武器，BUFF 暂缺） | `#g.choices` 改回 3 |
| C4 | paperclip / pie / laser / extinguisher 四把，各自独立提交 | 单把注释 |
| C5 | WP-15 + WP-30 + WP-31 + WP-32（大招分流） | `Game.UltImpact` 强制走 `UltFemaleImpact` 即回到旧行为 |
| C6 | WP-24 + WP-25（BUFF 生效） | `Buffs.Apply` 直接 `return false` |
| C7 | WP-40 + WP-50（HUD 与音效） | — |
| C8 | WP-51 + WP-52 + WP-53（测试与调参） | — |




## 9. 回归风险与旧断言改动清单

本节是「敢不敢合进去」的判定依据。逐条给出：**哪条断言会红、为什么会红、改法是什么**。

> 判定原则：**能不改测试就不改测试**。只有「三选一 → 五选一」这一条是需求本身要求改变的语义，其余全部要求**旧断言一字不改仍绿**。凡是会红的，都必须在本文档里显式列出，不允许「跑挂再说」。

### 9.1 测试套件总览（19 个文件，不是 17）

实际 \`web/lua/tests/\` 下有 19 个 \`.lua\` 文件（任务书里写的 17 是旧数字，以文件系统为准）：

| # | 文件 | 性质 | 与本次方案的接触面 |
| --- | --- | --- | --- |
| 1 | \`Actions.lua\` | 动作时序主套件（436 行） | **高**：并发武器、冻结、换房、burst 五段 |
| 2 | \`HeroRules.lua\` | 双英雄规则（318 行） | **高**：伤害倍率、burst 隔墙、UPGRADES[4]/[8] |
| 3 | \`Smoke.lua\` | 全流程冒烟（144 行） | **高**：\`#g.choices==3\` |
| 4 | \`Upgrade.lua\` | 强化窗口滚动（36 行） | 中：卡片高度变化 |
| 5 | \`ArtShowcase.lua\` | 美术验收夹具（74 行） | 低：只手动摆字段 |
| 6 | \`OfficeIdentity.lua\` | 菜单/设置/选人（72 行） | 无 |
| 7 | \`Menu.lua\` | 菜单按钮闭环（197 行） | 无（只到选人页） |
| 8 | \`ExitShowcase.lua\` | 出口全貌夹具（68 行） | 低 |
| 9 | \`CameraLifecycle.lua\` | 相机/无效布局回归（81 行） | 低 |
| 10 | \`Bosses.lua\` | 三首领外观（21 行） | 低 |
| 11 | \`Event.lua\` | 事件区夹具（13 行） | 无 |
| 12 | \`Shop.lua\` | 商店夹具（14 行） | 无 |
| 13 | \`Route.lua\` | 路线图夹具（14 行） | 无 |
| 14 | \`HeroAnimation.lua\` | 英雄动作帧（83 行） | 无（只读 spritesheet） |
| 15 | \`EnemyActions.lua\` | 敌人起手/接触帧（44 行） | 中：WP-15 插 stun/slow 会改 \`UpdateEnemies\` |
| 16 | \`EnemyNeighborhood.lua\` | 敌人邻域网格（22 行） | 无（纯数学） |
| 17 | \`NavigationFlow.lua\` | 导航图（38 行） | 无（纯数学） |
| 18 | \`CollisionParity.lua\` | 碰撞对拍（24 行） | 无（纯数学） |
| 19 | \`VisualScaleRules.lua\` | 视口/相机数学（132 行） | 无（断言 \`Game.WIDTH==1040\`、\`#Campaign.layouts==14\`） |

**结论：真正会被本次改动触及的只有 1–5、9、15 七个文件，其中只有 1 条断言必须改。**

### 9.2 必须修改的旧断言（仅 1 条）

| 位置 | 原文 | 改成 | 理由 | 归属包 |
| --- | --- | --- | --- | --- |
| \`tests/Smoke.lua:71\` | \`Check(g.mode == "upgrade" and #g.choices == 3, "经验升级三选一")\` | \`Check(g.mode == "upgrade" and #g.choices == 5, "经验升级五选一")\` | 需求「原三选一改五选一」直接把 \`#g.choices\` 从 3 变 5，**这是需求导致，不是 bug** | **WP-23** |

配套说明：
- 这条断言在 \`tests/Smoke.lua\` 的 male 全流程里，触发点是 \`:69\` 附近 \`g.xp = g.xpNeed\` 后的经验升级。
- 同一套件的 \`:104\` \`#g.eventChoices == 3\` **不要动** —— 事件选项仍是三选一，不在本次需求内。
- 消息文案从「经验升级三选一」改成「经验升级五选一」，是为了失败时能一眼看出是哪次语义变更导致。

### 9.3 必须保持不红的旧断言（逐条给出「为什么不会红」）

#### 9.3.1 \`tests/Actions.lua\` —— 并发武器（:236-289）

**:236-260 三武器同帧起手**：三把武器（keyboard / stapler / coffee）同帧 \`ActionState.Start\`，要求 \`g.action\` 仍是 keyboard（主姿态不被抢）、stapler 不等键盘收招、\`Tick(g,22)\` 后每条 track 的 start/impact/end 各一次。

**为什么不红**：

1. 五把新武器**不抢主姿态** —— \`Weapons.Start\` 只调 \`ActionState.Start(g, name, fx, fy)\`，不写 \`g.action\`。\`ActionState.Select\`（\`ActionState.lua:63-64\`）里 \`if current and g.actionTracks[current.name] == current and current.time < current.duration then return end\` 保护了「当前动作未收招不切换」，而 \`g.action\` 只被 \`SetLocomotion\` 与 \`Start\` 的 \`name=="hurt" or name=="burst"\` 分支改写（\`ActionState.lua:92\`）。
2. \`ORDER\` 把新武器排在 \`coffee\` 之后（见 §4.1：\`burst,hurt,keyboard,stapler,coffee,reload,thermos,paperclip,laser,extinguisher,pie\`），**排在后面的不会抢前面的姿态**。\`reload\` 排在 \`coffee\` 之后、\`thermos\` 之前，保证装填不会打断已有三把。
3. 该夹具的 \`g\` 来自 \`Fixture()\`，\`g.weapons\` 全 0 → \`Weapons.Update\` 里 \`if not Weapons.Any(g) then return end\` 提前返回。

**风险点**：如果实现时把 \`Weapons.Update\` 放在 \`ActionState.Update\` **之前**，就可能抢姿态。**必须放在 \`UpdateWeapons\` 内、\`ActionState.Update\` 之后**（\`Game.lua:858-859\` 的既有顺序：\`ActionState.Update\` → \`UpdateWeapons\`）。

**:262-289 380 帧压力测试**：\`g.attackSpeed, g.range = 3, 3\`，要求 \`counts.keyboard >= 10\`、\`counts.stapler >= 7\`、\`counts.coffee >= 2\`、\`#g.actionEvents <= 32\`。

**为什么不红**：

- \`#g.actionEvents <= 32\` 是**新增武器最容易踩的一条**。\`g.actionEvents\` 只在 \`ActionState\` 的 start/impact/end 三处 push（\`ActionState.lua:76-124\`）。该夹具 \`g.weapons\` 全 0 → 新武器一次 \`ActionState.Start\` 都不会发生 → 事件数不变。
- 「**未持有 → 不算冷却**」这个短路必须在 \`Weapons.Update\` 的第一层：写得像 \`for id, level in pairs(g.weapons) do if level > 0 then ... end end\`，绝不能让 \`level == 0\` 也走 timer 分支（Lua 5.1 无 \`continue\`/\`goto\`，只能用 \`if\` 包裹）。

**归属包**：WP-21 的验收里已含此条。

#### 9.3.2 \`tests/Actions.lua\` —— 冻结（:107-132、:313-343）

**Snapshot 字段表**（\`Actions.lua:112-115\`）：

\`\`\`
time, x, y, locomotion, locomotionTime, action, serial,
tracks{action,time,phase,impactDone}, melee, stapler, coffee, steps,
events(#actionEvents), shots(#shots), pools(#pools), audio(#audioQueue)
\`\`\`

**不含** \`g.pies\` / \`g.laserBeams\` / \`g.weaponTimer\` / \`g.buffState\` → 这些字段在冻结帧上推进**不会**破 \`Frozen\`。
**含** \`#g.pools\` / \`#g.shots\` / \`#g.actionEvents\` → 这三项在冻结帧上**不能增长**。

**保证链（必须写进代码注释，否则后人一定会踩）**：

\`\`\`
Game.Update(g, dt, ...)                       -- Game.lua:808
  if g.mode ~= "playing" then return end      -- :809  拦截 paused / upgrade
  if g.hitStop > 0 then ...; return end       -- :812  拦截 hitstop
    ActionState.Update(g, dt, ActionImpact)   -- :858
    UpdateWeapons(g, dt)                      -- :859  新武器全部挂在它里面
      Weapons.Update(g, dt)                   -- 新增
        -> 建 pool / 建 shot / ActionState.Start
\`\`\`

三者都在 \`Game.Update\` 的两个 early-return 之后 → **天然被冻结**。**结论：不需要额外加任何冻结判断。**

**反例（绝对不要这么写）**：把 \`Weapons.Update\` 挂到 \`Game.UpdateVisuals\`（\`Game.lua:782\`）里做「视觉推进」。\`UpdateVisuals\` **没有** \`mode\` 与 \`hitStop\` 的 early-return，而且 \`Actions.lua:331-336\` 明确在冻结期间照样调 \`Game.UpdateVisuals(g, 0.05)\`。一旦这么挂，\`#g.pools\` 会在冻结帧增长 → **这条断言必红**。

**:313-343 三 mode × 三 phase**：\`paused\` / \`upgrade\` / \`hitstop\` × \`windup\` / \`impact\` / \`recovery\`，断言冻结期完全不动，恢复后 \`g.time > before.time and action.time > before.tracks.keyboard.time\`（**不能补算停顿**）。

**为什么不红**：新增 timer（\`g.weaponTimer[id]\`）在冻结期不减，因为整个 \`UpdateWeapons\` 都没被调用。恢复后从原值继续减 —— 与 \`meleeTimer\` 行为一致。**不要**在 \`Game.UpdateVisuals\` 里做 timer 递减来「补偿」，那会破「不补算停顿」。

#### 9.3.3 \`tests/Actions.lua\` —— 换房（:412-435）**【最高风险】**

该夹具对 \`roomIndex in {2,4,5,8}\` 各跑一次：

\`\`\`lua
-- :415-417 起五个动作
ActionState.Start(g, "keyboard" / "stapler" / "coffee" / "burst" / "hurt", 1, 0)
Tick(g, 1, 1, 0, true)
Game.EnterRoom(g, roomIndex)
-- :422
Check(g.actionTracks ~= oldTracks and next(g.actionTracks) == nil and #g.actionEvents == 0, "换房清空所有并发轨道和旧事件")
-- :427
Check(#g.shots == 0 and #g.pools == 0 and g.hitStop == 0, "旧房子弹/咖啡/卡顿不泄漏")
-- :429-432 关键
g.waveTimer, g.meleeTimer, g.staplerTimer, g.coffeeTimer = 999, 999, 999, 999
g.audioQueue = {}
Tick(g, 35)   -- 35 x 0.05 = 1.75s
Check(next(g.actionTracks) == nil and #g.actionEvents == 0 and #g.shots == 0 and #g.pools == 0,
      "换房后等待旧动作全长也不迟发impact")
\`\`\`

**为什么会红（漏做就会红）**：\`Game.EnterRoom\` 的 \`:238\` 只清四个 timer：

\`\`\`lua
g.meleeTimer, g.staplerTimer, g.coffeeTimer, g.hitStop = 0, 0, 0, 0
\`\`\`

如果玩家已持有新武器，而 \`g.weaponTimer\` / \`g.pies\` / \`g.laserBeams\` 没被清，换房后第一帧 \`Weapons.Update\` 就会：

1. \`timer <= 0\` → 起手 → \`ActionState.Start\` → \`g.actionTracks\` 非空 + \`g.actionEvents\` 非空 → **:422 / :432 双红**
2. thermos 冷却若为 0 → 直接起手；pie 残留的 \`g.pies\` 会在 1.75s 内落地爆炸 → 建 pool → **:427 / :432 的 \`#g.pools==0\` 红**

**必须的修法**（WP-20 强制项）：

\`\`\`lua
-- Game.lua:238 改成
g.meleeTimer, g.staplerTimer, g.coffeeTimer, g.hitStop = 0, 0, 0, 0
g.weaponTimer, g.pies, g.laserBeams = {}, {}, {}
g.laserTick, g.laserTarget, g.laserHits, g.combo3 = 0, nil, 0, 0
if g.weaponState then for _, s in pairs(g.weaponState) do s.ammo, s.reloading = 0, false end end
\`\`\`

**并且**「换房冷却」语义要定死：新武器在 \`EnterRoom\` 后**冷却归零、可以立刻开火**（与 keyboard 的 \`meleeTimer = 0\` 一致）。这一条必须写进 \`Weapons.Update\` 的注释。

> ⚠️ **这里有一个「测试约束反向诱导错误设计」的陷阱**：如果把新武器冷却初始化成**满冷却**，1.75s 内不起手 → \`:429-432\` 反而更容易 pass。但玩家换房后会 1s 内打不出第一下，体验很差。**归零才是正确行为，不是为了讨好测试**。写代码的人如果先看测试再看实现，很容易搞反，所以必须在两处（\`EnterRoom\` 与 \`Weapons.Update\`）都留注释。

#### 9.3.4 \`tests/Smoke.lua\` —— male burst（:59-67）

\`\`\`lua
Game.Burst(g)
Check(... g.action.name == "burst" and g.action.time == 0 and #g.hostileShots == 1)
Step(g, 0.1)
Check(#g.hostileShots == 1 and not g.actionTracks.burst.impactDone)
Step(g, 0.05)   -- 累计 0.15s
Check(#g.hostileShots == 0 and g.actionTracks.burst.impactDone)
\`\`\`

**约束提炼**：male 的 \`impactAt\` 必须落在 \`(0.10, 0.15]\` 区间内 —— 0.10 时还没 impact、0.15 时已经 impact。\`TIMINGS.burst.impactAt = 0.12\` 满足。**且 male 必须清弹幕**（\`#hostileShots == 0\`）。**male 不断言具体伤害值** → §5 里男主的 \`(105 + 8 * g.level) * slamAmp\` 公式**可以自由改**，只要清弹幕 + 击退 + stun 的副作用不在 0.12s 前发生。

**为什么不红**：\`Game.Burst\` 保留原签名与原返回语义（成功 \`true\` / 失败 \`false\`），只在大招内部按 \`g.heroId\` 分派 impact。新增的 \`if (g.ultCooldown or 0) > 0 then return false end\` 在首次释放时为 0 → 不拦截。**注意**：\`ultCooldown\` 要在 \`Game.Start\` / \`EnterRoom\` 里归零，否则跨房后玩家按不出大招。

#### 9.3.5 \`tests/Actions.lua\` —— female burst 五段（:291-311）**【数值死锁】**

逐字断言与它对设计的硬约束：

| 行 | 断言 | 对设计的硬约束 |
| --- | --- | --- |
| :297 | \`Game.Burst(g) and g.rage == 0 and g.player.invuln > 0\` | 扣怒、给无敌帧，原样保留 |
| :299 | \`target.hp == hp and #g.hostileShots == 1 and Sounds(g,"burst") == 0\` | **起手帧：无伤害 / 不清弹幕 / 无 burst 音效** |
| :301 | \`not Game.Burst(g) and g.rage == 100 and g.actionTracks.burst == burst\` | 重复按不二次扣怒、不覆盖当前动作 |
| :303 | \`Tick(g,5)\`（0.10s）→ \`target.hp == hp and #g.hostileShots == 1 and not burst.impactDone\` | **0.10s 必须还没结算** |
| :305-307 | \`Tick(g,1)\`（0.12s）→ \`target.hp == hp - math.floor(125 * g.damage)\` 且 \`#g.hostileShots == 0\` 且 \`Sounds(g,"burst") == 1\` | **主伤害必须恰为 \`floor(125 * g.damage)\`，只算一次**；清弹幕 + 播一次音效必须发生在这一帧 |
| :308-310 | \`Tick(g,28)\` → \`not g.actionTracks.burst\`、伤害不变、\`impact\` 事件 1 次、\`end\` 事件 1 次 | 收招不补伤害、事件不重复 |

**设计含义**：女主的 125 是**常数、不吃等级、不吃任何乘区**（\`g.damage\` 是英雄倍率，不是攻击力）。这直接封死三条路：

1. 任何「大招增伤」BUFF（\`Buffs.UltPowerMul\`）**绝对不能**乘在这 125 上，否则 :305-307 红。它只能乘在**男主的 slam 伤害**与**女主的附加段（标记、易伤、崩解）**上。
2. 女主大招要变强，只能走 **① 标记 ×1.35 让后续普攻更强；② 2.5s 减速创造输出窗口；③ 崩解的持续伤害段** 三条路径，**不是加主伤害**。这条必须写进 \`UltFemaleImpact\` 顶部注释，否则后续平衡时一定有人来加数值。
3. \`Sounds(g,"burst")\` **必须恰好 1 次**（不是 0 不是 2）。新 cue \`heroUlt\` 是独立名字，不冲突；**但 0.12s 那一帧必须保留 \`Sound(g,"burst")\`**，不能「升级」成 heroUlt 就删掉旧的。

#### 9.3.6 \`tests/HeroRules.lua\` —— 隔墙（:292-318）

\`\`\`lua
wall = Fixture(1)                        -- layout1，竖墙 x332..350
wall.player.x, wall.player.y, wall.meleeTimer = 310, 280, 0
shielded = Stationary(wall, 380, 280)    -- 墙后敌人
Tick(wall, 4)                            -- 0.20s
Check(shielded.hp == shieldHp and not wall.actionTracks.keyboard)   -- 键盘不隔墙
wall.rage = 100
Check(Game.Burst(wall) and shielded.hp == shieldHp)                 -- 起手无伤害
Tick(wall, 3)                            -- +0.15s
Check(shielded.hp == shieldHp and wall.actionTracks.burst.impactDone)  -- <- 关键
Tick(wall, 12)                           -- +0.60s
Check(not wall.actionTracks.burst and shielded.hp == shieldHp)
\`\`\`

**三条硬约束**：

1. **female 的 impactAt 必须 ≤ 0.15s**：0.12 满足，且这是 \`TIMINGS.burst\` 现值，**不要动**。
2. **大招伤害必须过 \`Visible(g, p.x, p.y, e.x, e.y, r)\`**（\`Game.lua:172\`）—— 墙后敌人不受伤。\`UltFemaleImpact\` 必须保留 \`BurstImpact\` 原有的 \`and Visible(g, p.x, p.y, e.x, e.y, e.radius)\`（\`Game.lua:344\`）。
3. **男主 slam 是 198° 扇区** —— 同样必须过 \`Visible\`，否则玩家会隔着墙打到隔壁房间，**这条断言（\`shielded.hp == shieldHp\`）会红**。扇区判定的顺序是「先 \`Visible\` 再算角度」，不能反：\`Visible\` 内部走 \`Navigation.Trace\`，是唯一能正确判定墙体遮挡的手段。

**为什么不红**：\`wall\` 是 female 夹具（\`Fixture()\` 默认 female），走 \`UltFemaleImpact\`，数值一字不改。

#### 9.3.7 \`tests/HeroRules.lua\` —— UPGRADES 索引冻结（:137、:139）

\`\`\`lua
g.choices = { Game.upgradeDefs[4] }                       -- 必须是 speed（player.speed *= 1.15）
Game.Choose(g, 1)
g.mode, g.choices = "upgrade", { Game.upgradeDefs[8] }     -- 必须是 health（maxHp + 25 / hp + 35）
Game.Choose(g, 1)
\`\`\`

**硬约束：\`UPGRADES\` 前 12 条的顺序与内容完全冻结**，新条目**只能追加在 index 13 之后**。

- index 4 = \`speed\`，index 8 = \`health\`（\`Game.lua:353-366\`）。
- 五把武器 → index 13–17；第一批 BUFF → index 18–43（26 条）。
- **如果实现者「按分类排序」把 BUFF 插到前面，:137/:139 会悄悄测到别的条目**，而且因为旧 BUFF 也都是「往 g 上加个字段」，**大概率不报错** —— 这是全套件里最阴险的静默错误。
- 建议在 \`Game.lua\` 的 \`UPGRADES\` 表上方加注释：\`-- WARNING: index 1-12 被 tests/HeroRules.lua:137,139 锁定，只能追加\`。

#### 9.3.8 键盘伤害 27 不能动（\`Actions.lua:178-186\`、\`HeroRules.lua:121,125\`）

\`\`\`lua
local damage = math.floor(27 * g.damage)   -- Actions.lua:178
Check(enemy.hp == hp - damage ...)         -- :179
Check(closeHp - close.hp == math.floor(27 * spec.damage) ...)  -- HeroRules.lua:121
\`\`\`

**硬约束**：\`keyboard\` 基础伤害 27 **不能改**。新武器必须**独立新增**，不能借「重构」之名顺手改 27。

#### 9.3.9 \`Game.Hit\` 的裸状态纯函数性（\`HeroRules.lua:108-109, 121, 133\`）

\`\`\`lua
Game.Hit(direct, target, 20, 0, 0, 0)
Check(hp - target.hp == math.floor(20 * spec.damage), "实际Hit伤害倍率")   -- :109
\`\`\`

**硬约束**：\`Game.Hit(g, e, damage, nx, ny, force)\` 在**无任何 BUFF / 无 stun / 无 mark / 非暴击**的裸状态下，伤害必须严格等于 \`math.floor(damage * g.damage)\`。

§5.6 第 3 条要求在 \`Game.Hit\` 里插三处乘区，**三处都必须写成「字段不存在时字面等值」**：

\`\`\`lua
if (e.stunTimer or 0) > 0 then amount = math.floor(amount * 1.15) end
if (e.markHits or 0) > 0 then amount = math.floor(amount * 1.35); ... end
local marked = (e.markHits or 0) > 0
local crit = math.random() < (g.crit + (marked and 0.25 or 0))
\`\`\`

**最危险的是 crit 的差一错误**：\`g.crit\` 默认 0，\`math.random() < 0\` 恒 false —— 保持 \`<\` 就安全。如果写成 \`math.random() <= g.crit\`，则 \`math.random()\` 可能返回 \`0.0\`，\`0.0 <= 0\` 为 **true → 必定暴击 → 27 变 48 → :121 红**。这是 Lua 里 \`math.random()\` 能返回 0 导致的经典坑，必须写进 \`Game.Hit\` 的注释。

### 9.4 静默风险清单（不报错但会坏体验）

| # | 风险 | 检测方式 | 应对 |
| --- | --- | --- | --- |
| S1 | \`HudUI.lua:42\` 装备槽写死 \`{"keyboard","coffee","stapler"}\`，五把新武器无处显示 | 手动跑一局拿到 thermos 后看 HUD | WP-40 改固定 8 槽 + \`SetVisible\`；**没有任何测试会抓到**，靠截图验收 |
| S2 | \`UISkin.lua:70-72\` \`Skin.Icon("buff", id, ...)\` 对未知 id 走 \`assert(d.frames[id])\` **必崩** | 对 32 条 BUFF 逐条 \`Skin.Icon\` | §6 的图标映射把 32 条 BUFF 全映射到 12 帧之一；WP-03 验收要求逐条 assert |
| S3 | \`UpgradeUI.lua:38\` 底部文案写死「也可以按 1 / 2 / 3 选择」 | 视觉检查 | WP-41 改成 1 / 2 / 3 / 4 / 5 |
| S4 | \`main.lua:378-379\` 只接 \`KEY_1..KEY_3\` | 键盘按 4 / 5 | WP-42 扩到 KEY_5。**\`web/js/engine.js:44\` 的 \`for (i = 48; i <= 57; i++) KEY['KEY_' + String.fromCharCode(i)] = i\` 已生成 KEY_0..KEY_9，常量存在，无需改引擎** |
| S5 | \`HudUI.lua:83\` 遍历 \`Game.upgradeDefs\` 收集「已获得」图标，\`:87\` 最多显示 5 或 9 个；五武器 + 26 BUFF 会挤爆这一行 | 堆到 10+ BUFF 后看图标行 | WP-40 改成「只显示 core BUFF（按 rarity 排序取前 N）」，武器不进这行（武器有自己的 8 槽） |
| S6 | \`UpgradeUI.lua:6-11\` 的 \`EFFECTS\`/\`FLAVOR\` 两张表**只含 12 个旧 id**，新 id 查出来是 \`nil\` → 卡片空白 | 升级时看新卡文案 | WP-41 加 fallback：\`EFFECTS[id] or (BuffDef and BuffDef.effect) or "效果见描述"\` |
| S7 | 五选一后卡片变多：桌面 5 × 390 = 1950 > 590 容器高 → 必须滚动 | \`tests/Upgrade.lua\` 只测矮屏 | WP-41 把卡片降到 S(300) 后仍 5 × 300 = 1500 > 590，依旧滚动（\`ScrollView\` 已在，可接受）；**但不能缩到 5 张卡总高 < 590，否则滚动条消失 + 与 :26 的 \`offset > 0\` 断言冲突** |
| S8 | \`Game.EnterRoom:224\` 整体重置 \`g.pools = {}\` 会连新武器池一起清 | 无 | 这是**正确行为**。但要保证 \`UpdatePools\` 的 \`else\` 分支保持旧行为（咖啡池 \`kind == nil\`），新池用 \`kind = "pie"/"goji"/"spray"\` 显式区分 |
| S9 | 特效上限：\`#g.effects >= 100\` 时踢最旧（\`Game.lua:161-163\`）、\`#g.particles >= 240\` 时 break（\`:154\`） | 满配 + 满屏敌人 | §2 单帧新增特效已控 ≤3；但 laser 6 跳 + pie 爆炸 + extinguisher 干粉叠加会顶满 100。WP-52 平衡回归要拉一局满配看有没有特效被挤掉 |
| S10 | \`Game.Spawn:192\` \`if #g.enemies >= 70 then return nil end\` —— 召唤类 BUFF（B28）若召唤物塞进 \`g.enemies\` 会顶满上限，导致新怪刷不出来 | 召唤流满配 | §6 的 B28 明确**召唤物不进 \`g.enemies\`**，单独存 \`g.summons[]\`（上限 3） |
| S11 | \`Game.Burst:332\` 前置检查 \`if g.mode ~= "playing" or g.rage < 100 or ActionState.Active(g, "burst") then return false end\` —— 新加的 \`ultCooldown\` 如果放在这条**之后**，会导致「冷却中按大招仍然扣怒」 | 连按大招两次看怒气 | \`ultCooldown\` 判定**必须并进同一个 \`return false\` 条件**，不能放在扣怒之后 |

### 9.5 改完后必须跑的顺序

| 顺序 | 跑什么 | 期望 | 对应提交 |
| --- | --- | --- | --- |
| 1 | \`Actions.lua\` + \`HeroRules.lua\` + \`Smoke.lua\` | 除 \`#g.choices\` 外全绿 | C1（WP-01/02/03） |
| 2 | 全部 19 套件 | 全绿 | C2（thermos 全链） |
| 3 | \`Upgrade.lua\` + 手动看 5 张卡 | 矮屏可滚到底、5 张卡不重叠 | C3 |
| 4 | \`Actions.lua:262-289\`（压力）+ \`:412-435\`（换房） | **重点盯这两条** | C4（四把补齐） |
| 5 | \`Actions.lua:291-311\` + \`Smoke.lua:59-67\` + \`HeroRules.lua:292-318\` | 三条大招断言全绿 | C5 |
| 6 | 全部 + 1000 次五选一模拟（WP-51 新增 \`tests/Weapons.lua\`） | 全绿 | C8 |

### 9.6 建议修复的现状问题（不在本需求内，顺手记录）

| # | 位置 | 现象 | 建议 |
| --- | --- | --- | --- |
| F1 | \`Game.lua:526\` | keyboard 冷却 \`math.max(action.duration, 0.64 / attackSpeed)\` 让攻速 > 1.52 时收益归零（§3.2 已算：DPS 卡在 64.3） | 下限从 \`action.duration\`（0.42）改成 \`0.36\`。**这会改 \`Actions.lua:262-289\` 的 keyboard 计数（≥10 → 更多，仍 pass），不改单次时序**。建议单独立项，不要塞进本次提交 |
| F2 | \`Game.lua:341-351\` | \`BurstImpact\` 的 \`d < 260 + e.radius\` 是圆形判定，特效也是整圆环 —— 现状一致。但男主 slam 改成 198° 扇区后，若仍画整圆环会「看着能打到背后」 | 见 §5.3：male 的 \`slamRing\` 必须画**扇形环**（\`nvgArc\` 带起止角），不能复用 \`burst\` 的整圆 |
| F3 | \`UpgradeUI.lua:29\` | 卡片高度吃 \`p.portrait / p.landscape\` 三套硬值 | 五选一后建议改 \`S(math.max(112, p.h * 0.16))\`，随屏高自适应比硬编码更稳（注意别破 S7 的滚动前提） |

> **F1 特别说明**：这是唯一会改变现有武器数值的改动，**不在本需求范围内**。写在这里只是为了不让它变成「后来发现键盘攻速堆到 3 级还是打不快」的悬案。

## 10. 参考来源

### 10.1 说明：本环境的调研限制（先说清楚，避免以为是没去找）

本次撰写过程中对以下渠道做过实测，结论如下，**供后来者省下重复尝试的时间**：

| 渠道 | 实测结果 | 结论 |
| --- | --- | --- |
| \`web_search\`（Bing keyless fallback） | 对中文游戏专有名词（「元气骑士」等）返回 soulapp 官网、百度百科「元气」词条等**完全无关**结果 | **不可用**，未采信任何搜索结果 |
| \`soul-knight.fandom.com\` | HTTP 403（Cloudflare 拦截） | 抓不到 |
| \`roguebasin.com\` | 30s 超时 | 抓不到 |
| \`en.wikipedia.org\` | \`fetch failed\`（DNS/网络不可达） | 抓不到 |
| \`gamedeveloper.com\` | HTTP 403 | 抓不到 |
| \`gamedevelopment.tutsplus.com\` | HTTP 410 Gone（站点已下线） | 抓不到 |
| \`redblobgames.com\`（部分页） | 主站 200；\`/articles/probability/\` 返回 403 | 部分可用 |

**因此本文的数值设计以领域经验为主**（下文 §10.3 明确标注「未实链验证」），外链只作为**方法论出处**引用，且**每一条 10.2 里的链接都在撰写时实际抓取过并返回 200**。

### 10.2 已实链验证的参考（撰写时 web_fetch 返回 200）

| # | 出处 | URL | 本文用它支撑什么 |
| --- | --- | --- | --- |
| R1 | Amit Patel, *2D Visibility*（Red Blob Games） | https://www.redblobgames.com/articles/visibility/ | §5.3 男主 198° 扇区判定、§9.3.6 隔墙不命中：射线/可见性判定的标准做法 |
| R2 | Amit Patel, *Line Drawing on a Grid* | https://www.redblobgames.com/grids/line-drawing/ | §2 laser 光束沿线段采样（步长 8）与被遮挡段截断；thermos 扇区的「角度 + 距离」双条件 |
| R3 | *Easing Functions Cheat Sheet* | https://easings.net/ | §4 全部特效的生命周期曲线（\`ratio -> easeOutCubic\`）与 §2 pie 抛物线的缓动 |
| R4 | Robert Nystrom, *Object Pool*（Game Programming Patterns） | https://gameprogrammingpatterns.com/object-pool.html | §2/§7 \`g.shots\` / \`g.pools\` / \`g.pies\` / \`g.effects\` 的池化与 \`#g.effects >= 100\` 上限淘汰策略 |
| R5 | Robert Nystrom, *State*（Game Programming Patterns） | https://gameprogrammingpatterns.com/state.html | §2 extinguisher 的弹夹/装填状态机、§4 全武器 idle/attack/reload 状态表 |
| R6 | Robert Nystrom, *Component*（Game Programming Patterns） | https://gameprogrammingpatterns.com/component.html | §7 \`WeaponDef\` / \`BuffDef\` 数据驱动结构（行为在代码、数值在表） |
| R7 | Robert Nystrom, *Game Loop*（Game Programming Patterns） | https://gameprogrammingpatterns.com/game-loop.html | §9.3.2 冻结语义（\`hitStop\`/暂停时整帧跳过而非补算）的正确性论证 |
| R8 | Bob Nystrom, *Rooms and Mazes* | https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/ | 反向：本文的武器/敌人交互不依赖房间拓扑，故 §5 的扇区与光束判定全部走已有的 \`Navigation.Trace\` / \`Visible\`，不引入新的空间索引 |

### 10.3 依据领域经验、**未能实链验证**的部分（明确标注）

以下设计决策**没有直接可引的公开出处**（抓取失败或本身属于商业游戏的内部数值），依据通用 roguelite / ARPG 设计经验给出。**如果要对外发布设计稿，这些条目需要补一手资料或改为「内部经验值」。**

| 结论 | 位置 | 依据 | 可信度 |
| --- | --- | --- | --- |
| 三选一改五选一后，稀有度权重取 \`common 100 / rare 40 / epic 12\`（比例约 8.3 : 3.3 : 1） | §6.3 | 《杀戮尖塔》《以撒》《挺进地牢》一类作品的常见量级（常见/稀有/传说 ≈ 8:3:1）；**未实链验证** | 中（量级可信，具体数字为自定） |
| \`pityCounter\` 每 3 次升级保底 1 张非普通 | §6.3.2 | 抽卡式保底的通用做法（「软保底」），防止连续坏卡导致体验崩坏 | 中 |
| 五把武器的 DPS 斜率落在 \`×2.2 ~ ×3.3\`（Lv5 / Lv1） | §3.2 | 现有 keyboard（×1.52，且封顶）、stapler（×2.26）、coffee（×1.67）的实测值作为锚点，新品必须更陡才有取舍 | 高（有现成数值可对拍） |
| 大招 3 秒窗口内男女主总输出差 ≤ 5% | §5.5 | 双英雄平衡的通用门槛（差异要能被感知但不能决定胜负）；本文算得 1.3% | 中 |
| 女主大招主伤害 125 锁定为常数、不吃任何乘区 | §5 / §9.3.5 | **来源不是设计经验，是硬约束**：\`tests/Actions.lua:305-307\` 逐字断言 \`math.floor(125 * g.damage)\` | **确定（测试即规范）** |
| laser 对 Boss ×1.15、6 跳里第 4–6 跳 ×1.25 | §2.3 | 让「站桩引导」类武器在 Boss 战有专属收益，同时给散怪场景惩罚 —— 属于引导型武器的通用设计手法 | 中 |
| extinguisher 打空后 1.30s 装填 + 生成干粉池 | §2.5 | 「重装武器用空窗期换爆发」的经典权衡；干粉池是把惩罚转成战术资源的补偿设计 | 中 |

### 10.4 项目内部参考（本次逐个读过并逐字引用的事实来源）

**这些不是外链，是代码事实的依据。所有 §1 的现状参数、§9 的断言原文都来自这里。**

| 文件 | 读它为了确认什么 |
| --- | --- |
| \`web/lua/Game.lua\` | \`UpdateWeapons:516-540\` 三把武器冷却公式、\`ActionImpact:544-564\` 命中判定、\`Game.Burst:329-336\` / \`BurstImpact:337-351\`、\`UPGRADES:353-366\`、\`LevelUp:369-394\`、\`Game.Choose:396-414\`、\`Game.Hit:291-327\`、\`Game.New:107-135\`、\`EnterRoom:217-265\`、\`Game.Update:808+\` |
| \`web/lua/ActionState.lua\` | \`TIMINGS:20-27\` 六条时序、\`ORDER\`、\`Start:76-90\` 的 \`speed\` 缩放与 \`impactAt/impactEnd/duration\` 推导、\`:92\` 的 \`hurt/burst\` 抢主姿态、\`Select:63-64\` |
| \`web/lua/Audio.lua\` | \`:70-85\` 15 个 cue → 11 个 wav 的完整映射（gain/pitch/variation/cooldown/priority）、\`:110-131\` 抢占与音高抖动逻辑、\`:230\` 缺资源提示 |
| \`web/lua/InterfaceIcons.lua\` | \`:3-16\` buff 图集 12 帧白名单、\`:17-20\` item 图集 4 帧 |
| \`web/lua/UISkin.lua\` | \`:70-72\` \`Skin.Icon\` 对未知 id \`assert\` 必崩（§9.4 S2） |
| \`web/lua/HudUI.lua\` | \`:42\` 装备槽写死三把、\`:52\` rageBar、\`:54-58\` burstButton、\`:77-83\` 文本与 \`upgradeDefs\` 遍历、\`:87\` 图标行上限 |
| \`web/lua/UpgradeUI.lua\` | 全 42 行：\`:6-11\` EFFECTS/FLAVOR 只含 12 旧 id、\`:29\` 卡片三套硬高、\`:38\` 写死「1/2/3」 |
| \`web/lua/Draw.lua\` | \`:146\` Keyboard 程序化绘制、\`:194-224\` Effects 分支（slash/burst/stapleHit/pickup/coin/coffee）、\`:269-272\` pool 绘制、\`:312\` shots 绘制 |
| \`web/lua/InterfaceScale.lua\` | 全 12 行：\`portrait = w < 640 and h > w\`、\`landscape = w < 1000 and h < 520\`、\`s\` 的三段取法、\`px(n) = floor(n*s + 0.5)\` |
| \`web/lua/Heroes.lua\` | 全 32 行：\`male\` hp130/spd188/dmg0.85、\`female\` hp90/spd156/dmg1.30、\`Heroes.Get\` 未命中回落 male |
| \`web/lua/main.lua\` | \`:370-406\` 全部按键路由（\`:377-379\` upgrade 只接 1/2/3、\`:400-406\` KEY_E/SPACE/P/R/C） |
| \`web/js/engine.js\` | \`:44\` \`for (i = 48; i <= 57; i++) KEY['KEY_' + String.fromCharCode(i)] = i\` → **KEY_0..KEY_9 全部存在**，五选一扩键无需改引擎 |
| \`web/lua/tests/*.lua\`（19 个） | §9 逐条断言的原文；特别是 \`Actions.lua:107-132,236-289,291-311,313-343,412-435\`、\`HeroRules.lua:108-133,137-139,292-318\`、\`Smoke.lua:41-144\`、\`Upgrade.lua:1-36\` |
| \`web/lua/tests/Upgrade.lua\` | 全 36 行：\`:26\` \`if width < 700 and height < 720 then assert(offset > 0, "矮屏可滚动到第三选项")\` —— 五选一后卡片变多，这条仍 pass，但**卡片总高不能缩到矮屏也放得下** |

### 10.5 一句话总结本文的取舍

> **「加法做得越狠，减法越要狠。」**

五把武器 + 32 条 BUFF + 双大招看起来是「大幅做加法」，但本文真正的设计动作是**做减法**：

1. **武器不抢姿态** —— 全部走 \`ActionState\` 的排队轨道，主姿态永远留给 keyboard（\`Actions.lua:236-260\` 逼着这么做，也是对的）。
2. **女主大招不加伤害** —— 125 是常数，变强只走「标记 / 减速 / 崩解」三条侧路（\`Actions.lua:305-307\` 逼着这么做，也逼出了差异化）。
3. **UPGRADES 前 12 条不动** —— 新内容全部追加（\`HeroRules.lua:137,139\` 逼着这么做，也保住了老存档与老测试）。
4. **不新增任何美术/音频文件** —— 全部程序化绘制 + 11 个 wav 的 pitch/gain 变体（\`§4.5\` 的 10 个新 cue 零新增资源）。

需求给的自由是「你来决定功效」，但工程的自由只有「在不破 19 套件的前提下追加」。**本文档的每一处数值都同时满足这两条约束，任何后续改动请先跑 §9.5 的六步。**
