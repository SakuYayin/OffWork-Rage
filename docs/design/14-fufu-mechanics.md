# 符符（fufu）机制与数值文档

> 角色 ID：`fufu`　定位：召唤系远程支援
> 本文只描述**代码中真实生效**的规则，每个数值后括注出处（文件:行号）。
> 数据源：`web/lua/FufuCombat.lua`、`FufuSummons.lua`、`FufuHud.lua`、`FufuVisuals.lua`、`Heroes.lua`、`Buffs.lua`、`Loadout.lua`、`Game.lua`、`ActionState.lua`、`Events.lua`。

---

## 1. 角色定位

符符是第五位可选英雄，标题「毛孩子带队派」，官方一句话介绍：「糕点召唤动物伙伴，灯泡慢速远程支援。三格糕点逐格恢复，最多同时三位伙伴。」（web/lua/Heroes.lua:29）

| 维度 | 符符的做法 | 与其他四人的差异 |
| --- | --- | --- |
| 输出主体 | 动物伙伴自动作战，本体不产生任何近战/远程普攻 | 陈准、林夏、许宁、周序的输出都由本体武器打出 |
| 大招资源 | 「糕点」三格，逐格随时间回满，不读怒气 | 其余四人共用怒气 100 的大招（Game.lua:554） |
| 攻击距离 | 本体只放自动灯泡，射程 360（FufuCombat.lua:209） | 陈准/林夏/许宁是近战或中距，周序是高速直线弹 |
| 生存方式 | 靠伙伴分担仇恨、丹旺旺代受伤害 | 许宁靠护盾（100 上限），符符只有 10% 基础免伤 |
| 强化池 | 12 条「符符专属」BUFF，且被剔除怒气/大招伤害类 | 其他人共享通用 BUFF 池 |

一句话：**符符是唯一的召唤系角色，本体弱、伙伴强，玩的是「资源节奏 + 伙伴站位」而不是走位输出**（FufuCombat.lua:1-284）。

---

## 2. 本体基础数值

| 属性 | 数值 | 出处 |
| --- | --- | --- |
| 生命上限 maxHp | 100 | web/lua/Heroes.lua:30 |
| 移动速度 speed | 164 | web/lua/Heroes.lua:30 |
| 伤害系数 damage | 1.00 | web/lua/Heroes.lua:30 |
| 主武器 primaryWeapon | `cake`（宠物糕点） | web/lua/Heroes.lua:30 |
| 副武器 secondaryWeapon | `bulb`（灯泡），由初始化强制写入 | web/lua/FufuCombat.lua:24 |
| 基础免伤 reduction | 0.10（10%） | web/lua/Heroes.lua:30 |
| 初始护盾 | 0（`shieldMax` 也是 0，仅靠 fufuDuty 建立） | web/lua/Game.lua:164 |
| 初始怒气 rage | 0（普通英雄是 65，符符被清零） | web/lua/FufuCombat.lua:24；对比 web/lua/Game.lua:160 |
| 初始糕点 charges | 3（满格开局） | web/lua/FufuSummons.lua:8 |
| 拾取范围 magnet | 66 | web/lua/Game.lua:162 |
| 立绘 / 战斗图集 | `image/fufu/portrait.png` / `image/fufu/fufu.png` | web/lua/Heroes.lua:31 |

五位英雄横向对比（web/lua/Heroes.lua:13-31）：

| 英雄 | 生命 | 速度 | 伤害系数 | 主武器 | 额外 |
| --- | --- | --- | --- | --- | --- |
| 陈准 male | 130 | 188 | 0.85 | keyboard | — |
| 林夏 female | 90 | 156 | 1.30 | stapler | — |
| 许宁 intern | 120 | 130 | 1.125 | folder | 护盾 100、免伤 30% |
| 周序 programmer | 80 | 138 | 0.75 | binary | 自带 1 次穿透 |
| **符符 fufu** | **100** | **164** | **1.00** | **cake** | **免伤 10%、糕点 3 格** |

---

## 3. 核心机制

### 3.1 糕点充能系统

| 项 | 规则 | 出处 |
| --- | --- | --- |
| 格数上限 | 3 格 | web/lua/FufuSummons.lua:8、13 |
| 单格恢复时间 | 24 秒 | web/lua/FufuSummons.lua:14 |
| 充能速度加成 | `1 + 0.12 × fufuSnack 等级` | web/lua/FufuCombat.lua:202 |
| 实际间隔 | `max(16, 24 / (1 + 0.12 × 等级))` | web/lua/FufuCombat.lua:26；web/lua/FufuSummons.lua:14 |
| 满格行为 | 恢复进度清零并停止累计 | web/lua/FufuSummons.lua:13、20 |
| 一次召唤消耗 | 1 格 | web/lua/FufuSummons.lua:40 |
| 召唤后冷却 | 0.8 秒内不能再召唤 | web/lua/FufuSummons.lua:41 |

充能间隔实算：

| fufuSnack 等级 | 间隔 | 3 格回满耗时 |
| --- | --- | --- |
| 0 | 24.0 秒 | 72.0 秒 |
| 1 | 21.4 秒 | 64.3 秒 |
| 2 | 19.4 秒 | 58.1 秒 |
| 3（上限） | 17.6 秒 | 52.9 秒 |

> 注意：文案写「每格最低 16 秒」，但 16 秒下限需要 `0.12 × 等级 > 0.5`（约 5 级）才触发；`fufuSnack` 的 `maxLevel = 3`（web/lua/Buffs.lua:105），所以**实战最短间隔是 17.6 秒，16 秒下限在当前配置下永远走不到**。

HUD 表现：三格独立进度条 + 文本「糕点 X/3 · N秒+1」，满格显示「糕点 3/3 · 已充满」（web/lua/FufuHud.lua:9-14、47-48）。

### 3.2 召唤（Burst）流程

| 步骤 | 行为 | 出处 |
| --- | --- | --- |
| 按键 | 空格触发 `Game.Burst` | web/lua/main.lua:673 |
| 分流 | `heroId == "fufu"` 时直接走 `Fufu.BeginSummon`，**不检查怒气 100** | web/lua/Game.lua:553 |
| 前置条件 | 游戏中、糕点 > 0、冷却 ≤ 0、当前无召唤动作 | web/lua/FufuCombat.lua:57-60 |
| 动作时长 | 起手 0.25 / 判定 0.35 / 收招 0.45 / 总 0.6 秒 | web/lua/ActionState.lua:22 |
| 消耗时机 | 只在判定帧（impact）才真正消耗糕点并生成伙伴；此前取消不扣格 | web/lua/FufuCombat.lua:65-72、web/lua/Game.lua:1002 |
| 入场位置 | 玩家右上方 (x+30, y-24)，经导航投影到合法点 | web/lua/FufuCombat.lua:69 |
| 伙伴种类 | 每次独立 `random(1,5)`，各 20%，允许重复 | web/lua/FufuSummons.lua:3、31 |
| 同时上限 | 3 位 | web/lua/FufuSummons.lua:35 |
| 满员替换 | 移除 `pets[1]`（最早召唤的存活伙伴），新伙伴入队尾 | web/lua/FufuSummons.lua:35 |
| 播报 | 「「XX」来帮忙啦！糕点 N/3」 | web/lua/FufuCombat.lua:79 |

补充规则：

- 死掉的伙伴每帧被 `Cleanup` 移除（web/lua/FufuCombat.lua:43-48），因此「第 4 位替换第 1 位」实际替换的是**队列中最老的存活伙伴**。
- 换房间时保留身份、生命与顺序，只把位置重排到玩家身边 (i-2)×28、(y-30)（web/lua/FufuCombat.lua:49-56）。
- 事件/旧系统的「怒气充满」选项对符符改为 **+1 格糕点，最多 3 格**（web/lua/Events.lua:52、139-142；web/lua/Game.lua:864）。

### 3.3 伙伴列表

基础生命来自 `FufuSummons.stats`（web/lua/FufuSummons.lua:4-6），名字来自 `NAMES`（web/lua/FufuCombat.lua:8）。

| id | 名字 | 基础生命 | 攻击方式 | 攻击间隔 | 单次伤害 | 特殊效果 |
| --- | --- | --- | --- | --- | --- | --- |
| maple | 枫叶小猫 | 100 | 近战三连爪 | 一套 1.5 秒，三爪每 0.2 秒 | 每爪 10 | 每爪叠 1 层流血，最多 3 层；流血 4 秒，每秒 `3 + 2×fufuMaple`（FufuCombat.lua:233、245-246、248） |
| water | 水龙龙 | 85 | 直线水流，长 260、宽 18 | 施放 1.2 秒（六跳，每 0.2 秒），冷却 2.8 秒 | 每跳 `6 × (1 + 0.10×fufuWater)` | 命中附加潮湿 `4 + fufuWater` 秒；追击距离 230、速度 145（FufuCombat.lua:186-197、225-229） |
| dan | 丹旺旺 | 300 | **不攻击**，只跟随 | — | 0 | 玩家 120 内且有视线时代受伤害，减伤 `min(0.35, 0.20 + 0.05×fufuProtection)`，每次代受后 1 秒冷却（FufuCombat.lua:82-85、93-105） |
| cat | 普通猫猫 | 90 | 近战单击 | 0.8 秒 | 18 | 无（FufuCombat.lua:234） |
| dog | 普通狗狗 | 170 | 近战单击 | 1.15 秒 | 36（恒为猫猫 2 倍） | 无（FufuCombat.lua:234） |

伙伴通用 AI：

- 追击速度：近战 165，水龙龙 145，回归玩家身边 150（web/lua/FufuCombat.lua:224、226、231）。
- 近战出手距离 `60 + 目标半径`；离玩家超过 480 会放弃追击回家（web/lua/FufuCombat.lua:222、231）。
- 目标刷新节流 0.15 秒，选最近的敌人（web/lua/FufuCombat.lua:220、171-175）。
- 伤害走 `strike`：`damage × PetDamage × g.damage`，小数部分用 `damageCredit` 累计到下一击，避免每跳向下取整吃掉增益（web/lua/FufuCombat.lua:176-181）。

伙伴伤害倍率 `PetDamage`：

```
PetDamage = (1 + 0.15 × fufuClaws) × (猫/狗 ? (1 + 0.15 × fufuTeething) : 1)
```
（web/lua/FufuCombat.lua:32-36）

伙伴最大生命 `MaxHp`：

```
MaxHp = 基础生命 × (1 + 0.20 × fufuCheckup) × (丹旺旺 ? (1 + 0.15 × fufuProtection) : 1)
```
（web/lua/FufuCombat.lua:27-31）

满强化示例（fufuCheckup 3 + fufuProtection 3）：丹旺旺 300 × 1.6 × 1.45 = **696**；猫猫 90 × 1.6 = 144；狗狗 170 × 1.6 = 272。

### 3.4 伙伴的承伤与保护

| 机制 | 规则 | 出处 |
| --- | --- | --- |
| 新伙伴护体 | 出生前 3 秒所有承伤额外 ×0.70 | web/lua/FufuSummons.lua:38；web/lua/FufuCombat.lua:84 |
| 受击间隔 | 受击后 0.3 秒无敌，避免同帧重复扣血 | web/lua/FufuCombat.lua:89 |
| 仇恨 | 敌人近战/远程都会选**最近的伙伴**为目标 | web/lua/FufuCombat.lua:106-112；web/lua/Game.lua:1159、1330 |
| 近战结算 | 伙伴在 `敌人半径 + 36` 内且可见时吃这一击 | web/lua/FufuCombat.lua:113-120 |
| 冲撞/自爆 | 冲刺或蓄力状态撞到伙伴时结算，每次 0.9 秒节流 | web/lua/FufuCombat.lua:121-127、254-256 |
| 自爆怪（kind 11） | 贴身 46 内触发，对 62 内全部伙伴与玩家造成伤害后自毁 | web/lua/FufuCombat.lua:257-263 |
| 敌方弹幕 | 沿线碰撞先撞伙伴，扣伙伴生命并消耗弹体 | web/lua/Game.lua:1477 |
| 清房回复 | 每次清房回复 `10% × fufuBlanket` 最大生命，并乘治疗衰减 | web/lua/FufuCombat.lua:128-132 |

丹旺旺代受公式（web/lua/FufuCombat.lua:93-105）：

1. 玩家受击时先调 `Fufu.Intercept`，若 1 秒冷却已好、丹旺旺存活、距离 ≤ 120 且有视线；
2. 计算 `rawAbsorbed = min(伤害, 丹旺旺生命 / 减伤系数)`，即丹旺旺最多替玩家扛到「自己被打死」为止；
3. 超出部分**回落给玩家本体**；
4. 触发后 1 秒内不再代受。

### 3.5 灯泡（bulb）

| 项 | 规则 | 出处 |
| --- | --- | --- |
| 触发方式 | 自动索敌，玩家 360 + 敌人半径内、有视线、冷却好了就出手 | web/lua/FufuCombat.lua:208-214 |
| 射击间隔 | `(1.4 / 1.05) / max(0.2, attackSpeed × 攻速倍率)` ≈ 1.333 秒 | web/lua/FufuCombat.lua:213 |
| 动作时长 | 起手 0.12 / 判定 0.18 / 收招 0.28 / 总 0.45 秒 | web/lua/ActionState.lua:23 |
| 弹速 | 340 | web/lua/FufuCombat.lua:144 |
| 射程（弹体寿命） | `360 / 340` 秒 ≈ 1.06 秒，正好飞 360 | web/lua/FufuCombat.lua:145 |
| 穿透 | 0（命中即消失） | web/lua/FufuCombat.lua:145 |
| 弹体总量上限 | 128，达到后不再发射 | web/lua/FufuCombat.lua:139 |

三档概率与伤害（web/lua/FufuCombat.lua:133-143）：

| 档位 | 基础概率 | 满强化概率 | 伤害 | 效果 |
| --- | --- | --- | --- | --- |
| 普通 normal | 70% | 45% | 12.6 | 纯伤害 |
| 通电 electric | 20% | 35% | 18.9 | 目标处于潮湿时连锁 |
| 闪光 flash | 10% | 20% | 8.4 | 硬直：普通怪 0.7 秒，Boss 0.2 秒 |

- 概率公式：`electric = min(0.35, 0.20 + 0.05×fufuWaterproof)`，`flash = min(0.20, 0.10 + 0.05×fufuBlink)`，`normal = 1 - electric - flash`（web/lua/FufuCombat.lua:133-137）。强化从普通概率里扣，不会溢出。
- 伤害注释写明为「方案 A：三类各上调 5%」，原值 12 / 18 / 8（web/lua/FufuCombat.lua:142-143、165）。

通电连锁（web/lua/FufuCombat.lua:156-169）：

| 项 | 规则 |
| --- | --- |
| 触发条件 | 命中时目标 `wetTimer > 0`（潮湿由水龙龙水流施加） |
| 跳数 | `min(4, 2 + fufuLink 等级)` → 0 级 2 跳、1 级 3 跳、2 级 4 跳 |
| 搜索半径 | 160，只跳向**潮湿**目标，需有视线 |
| 每跳伤害 | 12.6（固定，不随链衰减） |
| 约束 | 不回跳（visited 表）、不递归、每次从上一个目标继续找最近的 |

闪光硬直（web/lua/FufuCombat.lua:152-155）：

- 普通怪：`stunTimer = max(现有, 0.7)`。
- Boss（`e.kind == 5` 或 `14`）：只 `0.2` 秒，且同一 Boss 有 4 秒免疫窗口（`fufuFlashCd = 4`）。
- 硬直期间敌人动作计时也被冻结（web/lua/Game.lua:1281 跳过 `EnemyAnimation.Step`）。

状态图标：潮湿/流血/硬直三种状态在敌人头顶显示（web/lua/FufuVisuals.lua:82-89）。

### 3.6 护盾与减伤

| 来源 | 规则 | 出处 |
| --- | --- | --- |
| 本体基础免伤 | 10% | web/lua/Heroes.lua:30 |
| 伤害结算顺序 | 先伙伴代受 → 再护盾 → 再乘减伤与护甲 | web/lua/Game.lua:404-424 |
| 减伤上限 | `min(0.60, reduction)` | web/lua/Game.lua:419 |
| 护盾来源 | 仅 `fufuDuty`：每格充能完成 +5×等级护盾，护盾上限至少 15 | web/lua/FufuCombat.lua:41、204-205 |
| 护盾特性 | 有盾时伤害先扣盾，扣盾瞬间重置「安静计时」 | web/lua/Game.lua:420-423 |

符符拿不到 `internProtection`（该 BUFF 锁定 `hero="intern"`，web/lua/Buffs.lua:100），所以她的减伤固定为 10%，护盾完全依赖 fufuDuty。

---

## 4. 十二条专属 BUFF 全表

全部注册在 `HERO_BUFFS`，`tag = "符符专属"`，只对 `heroId == "fufu"` 入池（web/lua/Buffs.lua:105-116；过滤逻辑见 web/lua/Game.lua:698、784）。

| id | 中文名 | tag | 每级效果 | 稀有度 | 最大等级 | 图标 | 点评 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| fufuSnack | 加餐时间 | 符符专属 | 糕点充能速度 +12%（每格最低 16 秒） | rare | 3 | `snack` | 节奏核心，3 级把 24 秒压到 17.6 秒 |
| fufuCheckup | 毛孩子体检 | 符符专属 | 伙伴最大生命 +20%，现有生命按比例同步 | common | 3 | `checkup` | 白卡但收益稳定，直接拉长伙伴存活 |
| fufuClaws | 爪牙保养 | 符符专属 | 输出伙伴伤害 +15%（丹旺旺仍不攻击） | rare | 3 | `claws` | 全体输出乘区，猫狗再叠磨牙棒 |
| fufuMaple | 枫叶抓痕 | 符符专属 | 枫叶小猫每层流血每秒伤害 +2 | rare | 3 | `maple` | 只对枫叶生效；3 级单层 9/秒，3 层约 27/秒（未计爪牙保养） |
| fufuWater | 活水饮水机 | 符符专属 | 潮湿持续 +1 秒，水流伤害 +10% | common | 3 | `livingWater` | 水龙龙专用，同时拉长通电连锁窗口 |
| fufuProtection | 守护小保镖 | 符符专属 | 丹旺旺生命 +15%、代受减伤 +5%（上限 35%） | rare | 3 | `protection` | 把丹旺旺变成 696 血的肉盾 |
| fufuTeething | 双倍磨牙棒 | 符符专属 | 普通猫猫与狗狗伤害同时 +15% | rare | 3 | `teething` | 只强化猫狗，狗始终是猫的 2 倍 |
| fufuWaterproof | 防水接线板 | 符符专属 | 通电灯泡概率 +5 个百分点（上限 35%） | rare | 3 | `waterproof` | 需要潮湿目标才有连锁收益 |
| fufuLink | 串联电路 | 符符专属 | 通电连锁次级目标 +1（最多 4 个） | epic | 2 | `link` | 链长从 2 跳到 4 跳，清群质变 |
| fufuBlink | 眨眼别怕 | 符符专属 | 闪光灯泡概率 +5 个百分点（上限 20%） | rare | 2 | `blink` | 偏控制，Boss 硬直仍只有 0.2 秒 |
| fufuBlanket | 回家小毯子 | 符符专属 | 清房时伙伴回复最大生命 10% | common | 2 | `blanket` | 续航卡，受逐波治疗衰减影响 |
| fufuDuty | 值班小闹钟 | 符符专属 | 每格充能完成恢复 5 护盾（最多 15） | epic | 2 | `onDuty` | 符符唯一的护盾来源，2 级满 10 点 |

稀有度权重：common 100 / rare 40 / epic 12（web/lua/Buffs.lua:30；web/lua/Game.lua:665）。

补充说明：

- 拿卡时 `Buffs.Apply` 会二次校验 `def.hero ~= g.heroId` 直接拒绝（web/lua/Buffs.lua:176），并在生效后回调 `Fufu.OnBuff`：体检/守护会按比例重算现有伙伴生命，值班会初始化 `shieldMax`（web/lua/Buffs.lua:190-191；web/lua/FufuCombat.lua:37-42）。
- `INTERN_DESCS` 只有 16 条通用 BUFF 的许宁改写文案，**没有 fufu 项**；`Buffs.Description` 也只对 intern 特殊处理，因此符符面板直接显示 `def.desc` 原文（web/lua/Buffs.lua:132-153）。
- 图标名虽与「12 帧 buff 图集」注释不符，但 `InterfaceIcons` 已把 `fufu.buffs` 图集按 `fufuBuffIds` 映射注册进 `definitions.buff.frames`，所以能正常显示（web/lua/InterfaceIcons.lua:38-40）。

---

## 5. 武器限制

| 规则 | 内容 | 出处 |
| --- | --- | --- |
| 符符可获取 | 仅 `cake` 与 `bulb` | web/lua/Loadout.lua:7 |
| 其他英雄可获取 | **不能**拿 `cake` 或 `bulb` | web/lua/Loadout.lua:8 |
| 初始装备 | 主武器 `cake` + 副武器 `bulb`，开局即双持 | web/lua/FufuCombat.lua:24 |
| 装备栏文案 | 显示「糕点·固定」「灯泡·固定」 | web/lua/HudUI.lua:149 |
| 掉落过滤 | 地面武器宝石先判 `Loadout.CanAcquire`，不合法不吸附 | web/lua/Game.lua:1628 |
| 选卡过滤 | 抽到武器卡但不可获得时直接拒绝 | web/lua/Game.lua:781 |
| 写入规则 | `Acquire` 只有副武器槽为空时才写入 | web/lua/Loadout.lua:11-15 |
| 补满双持 | 若副武器槽为空（例如测试构造），拾到 `cake` 或 `bulb` 会补进副武器槽 | web/lua/Loadout.lua:9、13 |

为什么这样设计：

1. 符符的两把武器不是「可选装备」，而是**机制载体**——糕点=召唤资源，灯泡=本体唯一输出（web/lua/Loadout.lua:1-10 注释：主武器按英雄固定，只能再获得一把）。
2. 因此 `CanAcquire` 对符符走白名单（`id == "cake" or id == "bulb"`），对其他英雄走黑名单，保证她既不会丢掉糕点/灯泡，也不会捡到第三把武器。
3. 双持是硬编码结果：主武器槽固定 `cake`，副武器槽固定 `bulb`，`Loadout.List` 长度恒为 2（web/lua/tests/FufuCombat.lua:29）。
4. 这两把武器**不产生普攻**：`UpdateWeapons` 里所有分支都要求 `Loadout.Has(g, "keyboard"/"stapler"/...)`，符符都不满足，所以本体近战输出为 0（web/lua/Game.lua:925-997）。

---

## 6. 数值汇总表

| 分类 | 项 | 数值 | 出处 |
| --- | --- | --- | --- |
| 本体 | 生命 | 100 | Heroes.lua:30 |
| 本体 | 速度 | 164 | Heroes.lua:30 |
| 本体 | 伤害系数 | 1.00 | Heroes.lua:30 |
| 本体 | 基础免伤 | 10% | Heroes.lua:30 |
| 本体 | 减伤上限 | 60% | Game.lua:419 |
| 糕点 | 格数 | 3 | FufuSummons.lua:8 |
| 糕点 | 单格恢复 | 24 秒（最短 17.6 秒） | FufuSummons.lua:14；FufuCombat.lua:26 |
| 糕点 | 召唤消耗 | 1 格 | FufuSummons.lua:40 |
| 糕点 | 召唤冷却 | 0.8 秒 | FufuSummons.lua:41 |
| 召唤 | 动作时长 | 0.6 秒（判定 0.35 秒） | ActionState.lua:22 |
| 召唤 | 同时上限 | 3 位 | FufuSummons.lua:35 |
| 召唤 | 种类概率 | 五种各 20% | FufuSummons.lua:31 |
| 召唤 | 出生护体 | 3 秒承伤 ×0.70 | FufuSummons.lua:38；FufuCombat.lua:84 |
| 伙伴 | 受击无敌 | 0.3 秒 | FufuCombat.lua:89 |
| 伙伴 | 近战出手距离 | 60 + 目标半径 | FufuCombat.lua:231 |
| 伙伴 | 离队阈值 | 480 | FufuCombat.lua:222 |
| 伙伴 | 追击速度 | 165（近战）/ 145（水龙龙）/ 150（回归） | FufuCombat.lua:224、226、231 |
| 枫叶 | 每爪伤害 / 间隔 | 10 / 0.2 秒，三爪后 1.5 秒一套 | FufuCombat.lua:233、245、248 |
| 枫叶 | 流血 | 每秒 `3 + 2×等级`，4 秒，最多 3 层 | FufuCombat.lua:245-246 |
| 水龙龙 | 水流 | 六跳 × 0.2 秒，长 260，宽 18 | FufuCombat.lua:192、228、237-239 |
| 水龙龙 | 每跳伤害 | `6 × (1 + 0.10×等级)` | FufuCombat.lua:193 |
| 水龙龙 | 潮湿时长 | `4 + 等级` 秒 | FufuCombat.lua:194 |
| 丹旺旺 | 生命 | 300（满强化 696） | FufuSummons.lua:5；FufuCombat.lua:27-31 |
| 丹旺旺 | 代受范围 / 冷却 | 120 / 1 秒 | FufuCombat.lua:96、99 |
| 丹旺旺 | 代受减伤 | `min(35%, 20% + 5%×等级)` | FufuCombat.lua:83 |
| 猫猫 / 狗狗 | 伤害 / 间隔 | 18 / 0.8 秒；36 / 1.15 秒 | FufuCombat.lua:234 |
| 灯泡 | 射击间隔 | ≈1.333 秒 ÷ 攻速 | FufuCombat.lua:213 |
| 灯泡 | 射程 / 弹速 | 360 / 340 | FufuCombat.lua:145、209 |
| 灯泡 | 伤害 | 12.6 / 18.9 / 8.4 | FufuCombat.lua:143 |
| 灯泡 | 概率（基础 → 满强化） | 70/20/10 → 45/35/20 | FufuCombat.lua:134-136 |
| 灯泡 | 连锁 | 半径 160，`min(4, 2+等级)` 跳，每跳 12.6 | FufuCombat.lua:158-166 |
| 灯泡 | 硬直 | 普通 0.7 秒 / Boss 0.2 秒（4 秒免疫） | FufuCombat.lua:154-155 |
| 灯泡 | 弹体上限 | 128 | FufuCombat.lua:139 |
| 护盾 | fufuDuty | 每格 +5，上限 15 | FufuCombat.lua:41、205 |
| 清房 | fufuBlanket 回复 | 每层 10% 最大生命 × 治疗衰减 | FufuCombat.lua:130 |
| 治疗衰减 | HealMul | `max(0.45, 1 - 0.018×(波数-1))` | Difficulty.lua:12 |
| 抽卡 | 稀有度权重 | common 100 / rare 40 / epic 12 | Buffs.lua:30；Game.lua:665 |

---

## 7. 与设计文档 13-fufu-live.md 的差异

| 项 | 13-fufu-live.md 写法 | 代码实际 | 结论 |
| --- | --- | --- | --- |
| 精力（生命） | 「精力 90」（13-fufu-live.md:7） | `maxHp = 100`（web/lua/Heroes.lua:30） | **不一致**，代码已上调到 100 |
| 丹旺旺基础生命 | 280（13-fufu-live.md:21） | `dan = 300`（web/lua/FufuSummons.lua:5） | **不一致**，代码为 300 |
| 灯泡单发伤害 | 正常 12 / 通电 18 / 闪光 8（13-fufu-live.md:35-37） | 12.6 / 18.9 / 8.4（web/lua/FufuCombat.lua:143） | **不一致**，代码整体 +5%（方案 A） |
| 通电连锁每跳 | 12（13-fufu-live.md:36） | 12.6（web/lua/FufuCombat.lua:166） | **不一致**，同样 +5% |
| 灯泡射击间隔 | 1.4 秒（13-fufu-live.md:33） | `1.4/1.05 ≈ 1.333` 秒（web/lua/FufuCombat.lua:213） | **不一致**，代码出手频率 +5% |
| 召唤动作时长 | 0.35 秒（13-fufu-live.md:10） | 总 0.6 秒，判定帧 0.35 秒（web/lua/ActionState.lua:22） | 表述差异，0.35 是判定时刻而非总长 |
| 单格充能 | 24 秒，最低 16 秒（13-fufu-live.md:11） | 24 秒，实际最低 17.6 秒（3 级上限） | 16 秒下限在 maxLevel=3 下不可达 |
| 糕点格数 / 上限 | 3 格 / 3 位伙伴（13-fufu-live.md:8、15） | 一致（web/lua/FufuSummons.lua:8、35） | 一致 |
| 五种伙伴概率 | 每次独立 20%（13-fufu-live.md:15） | 一致（web/lua/FufuSummons.lua:31） | 一致 |
| 出生护体 | 前 3 秒减伤 30%（13-fufu-live.md:25） | 承伤 ×0.70（web/lua/FufuCombat.lua:84） | 一致（等价写法） |
| 丹旺旺代受 | 减伤 20% 起，最多 35%（13-fufu-live.md:21、52） | `min(0.35, 0.20+0.05×等级)`（web/lua/FufuCombat.lua:83） | 一致 |
| 满强化概率 | 45/35/20（13-fufu-live.md:39） | 一致（web/lua/FufuCombat.lua:134-136） | 一致 |
| 连锁上限 | 最多 4 个次级目标（13-fufu-live.md:55） | `min(4, 2+等级)`（web/lua/FufuCombat.lua:158） | 一致 |
| 弹体上限 | 128（13-fufu-live.md:75） | 一致（web/lua/FufuCombat.lua:139） | 一致 |
| 伙伴受击间隔 | 0.3 秒（13-fufu-live.md:27） | 一致（web/lua/FufuCombat.lua:89） | 一致 |
| 十二项 BUFF | 全部列出（13-fufu-live.md:45-58） | 12 条与 `HERO_BUFFS` 完全对应（web/lua/Buffs.lua:105-116） | 一致 |

未在代码中找到对应实现的 13 文档描述：无。13 文档中的渲染接口（`g.summons` 字段、pet 字段、效果名）均可在 web/lua/FufuCombat.lua、FufuVisuals.lua 中一一对应。

---

## 附：一句话上手建议

开局 3 格糕点别急着交，先让第一只伙伴成型；优先拿 `fufuSnack`（节奏）与 `fufuCheckup`（续航），有丹旺旺时补 `fufuProtection` 做肉盾，拿到 `fufuWater` + `fufuLink` 后水龙龙 + 通电灯泡是主要清群手段。
