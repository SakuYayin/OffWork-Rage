# 许宁怒气收益调整修改说明

- 日期：2026-11-08
- 角色：`intern / 许宁`
- 目标：降低许宁的受击怒气、文件夹清场怒气和大招清场补怒
- 状态：可直接按本文实施
- 本次范围：只改许宁，其他角色的受击与击杀怒气保持不变

## 1. 背景

当前许宁的怒气来源主要有三类：

1. 自然恢复：2.5/秒。
2. 受击：每次12点，0.9秒最多触发一次。
3. 击杀：普通敌人3点/只，甩锅大锅7点/只。

许宁拥有100点数值护盾、30%基础免伤和脱战护盾回复，护盾完全吸收伤害、HP没有减少时仍会被判定为一次有效受击，并获得完整12点怒气。

文件夹和大招又都是范围攻击，一次命中多只敌人时，每只击杀都会分别结算击杀怒气，因此清场瞬间会出现大幅度跳条。

本次调整同时处理：

- 受击怒气：许宁改为实际掉血8点、护盾全吸收6点。
- 文件夹清场：文件夹直接击杀怒气按50%结算，普通怪每只 **1.5**。
- 大招补怒：大招直接击杀怒气按90%结算，普通怪每只 **2.7**。
- 其他角色、其他武器击杀、自然恢复、“忍无可忍”均不变。

## 2. 最终数值

### 2.1 受击怒气

| 受击情况 | 当前 | 修改后 |
|---|---:|---:|
| 许宁实际掉血 | 12 | **8** |
| 许宁护盾完全吸收、HP未减少 | 12 | **6** |
| 其他角色实际掉血 | 12 | **12，保持不变** |
| 其他角色护盾完全吸收 | 按现有逻辑 | **保持不变** |

受击频率不变，仍受0.9秒无敌限制：

```text
1 / 0.9 = 1.111 次/秒
```

不考虑“越想越气”：

| 情况 | 单次 | 最高频率 | 每秒受击怒气 | 加自然恢复 |
|---|---:|---:|---:|---:|
| 实际掉血 | 8 | 1.111次/秒 | 8.89 | **11.39/秒** |
| 护盾全吸收 | 6 | 1.111次/秒 | 6.67 | **9.17/秒** |

“越想越气”2级时倍率为1.30：

| 情况 | 单次 | 加自然恢复 |
|---|---:|---:|
| 实际掉血 | **10.4** | 14.06/秒 |
| 护盾全吸收 | **7.8** | 11.17/秒 |

### 2.2 击杀怒气

击杀公式改为：

```text
最终击杀怒气 = 基础击杀怒气 × 来源系数 × 越想越气倍率
```

基础值：

- 普通敌人：3
- 甩锅大锅 `kind == 4`：7

来源系数：

| 致死来源 | 来源系数 | 普通怪 | 甩锅大锅 |
|---|---:|---:|---:|
| 文件夹直接命中 | **0.5** | **1.5** | **3.5** |
| 许宁大招直接命中 | **0.9** | **2.7** | **6.3** |
| 其他武器、灼烧、连锁等 | 1.0 | 3.0 | 7.0 |

“越想越气”叠加后：

| 来源 | 0层普通怪 | 2层普通怪 | 0层大锅 | 2层大锅 |
|---|---:|---:|---:|---:|
| 文件夹 | **1.5** | **1.95** | **3.5** | **4.55** |
| 大招 | **2.7** | **3.51** | **6.3** | **8.19** |
| 其他 | 3.0 | 3.9 | 7.0 | 9.1 |

### 2.3 清场效果示例

不考虑自然恢复和其他怒气来源：

| 场景 | 当前 | 修改后 |
|---|---:|---:|
| 文件夹一次击杀10只普通怪 | +30 | **+15** |
| 文件夹一次击杀20只普通怪 | +60 | **+30** |
| 大招一次击杀30只普通怪 | +90 | **+81** |
| 大招一次击杀10只大锅 | +70 | **+63** |

伤害产生的怒气仍保留小数，**不要取整**。例如1.5、2.7、3.51都必须原样累加，再由100上限截断。

## 3. 受击判定口径

必须按以下顺序判断：

1. 玩家处于无敌帧时，直接返回，不回怒。
2. “带薪发呆”次数盾若完整吃掉伤害，按现有逻辑直接返回，不回怒。
3. 计算基础免伤、“实习生保护期”免伤、护甲。
4. 再扣除许宁的数值护盾。
5. **扣除数值护盾后 `loss == 0`，视为“护盾完全吸收”，给6点。**
6. **`loss > 0`，包括护盾只挡住一部分后仍掉血，给8点。**
7. 其他角色仍给12点。

注意：

- 判断依据是数值护盾结算后的 `loss`，不是原始伤害。
- 不能因为护盾吸收就完全跳过回怒；本次明确保留该收益。
- 受击频率仍由现有0.9秒无敌限制，不要额外增加或减少无敌时间。
- 不回怒的无敌帧逻辑保持不变。

## 4. 击杀来源判定口径

击杀归属以**造成致死伤害的那一次 `Game.Hit` 调用**为准。

- 文件夹动作的伤害调用：来源系数0.5。
- 许宁大招 `BurstImpact` 的伤害调用：来源系数0.9。
- 灼烧、连坐、其他武器或其他没有标记来源的伤害：来源系数1.0。
- 同一敌人先被大招打伤、随后被灼烧烧死：致死伤害属于灼烧，按1.0结算，不按大招0.9。
- 连锁击杀由 `Buffs.OnHit` 走 `TrueHit`，没有来源标记，按1.0结算。
- 当前只要求文件夹和大招的**直接命中击杀**打折，不要为连锁/灼烧额外传递来源系数。

来源系数只影响**击杀怒气**，不影响：

- 实际伤害。
- 受击怒气。
- 自然恢复。
- “忍无可忍”补怒。
- 金币、经验或掉落。

## 5. 代码修改

### 5.1 权威文件

优先修改：

`web/lua/Game.lua`

镜像文件同步同一改动：

`scripts/Game.lua`

`web/lua/Game.lua` 是构建与浏览器运行源；`scripts/Game.lua` 是镜像副本，两者必须保持一致。

### 5.2 受击怒气

函数：`Game.TakeDamage`

当前代码：

```lua
    p.hp = math.max(0, p.hp - loss)
    p.invuln, g.shake, g.flash = 0.9, 5, 0.16
    g.rage = math.min(100, g.rage + 12 * Buffs.RageMul(g))
```

建议改为：

```lua
    p.hp = math.max(0, p.hp - loss)
    p.invuln, g.shake, g.flash = 0.9, 5, 0.16
    local hitRage = 12
    if g.heroId == "intern" then
        hitRage = loss > 0 and 8 or 6
    end
    g.rage = math.min(100, g.rage + hitRage * Buffs.RageMul(g))
```

建议增加常量，方便后续调参：

```lua
local INTERN_HURT_RAGE = 8
local INTERN_SHIELD_RAGE = 6
local DEFAULT_HURT_RAGE = 12
```

然后：

```lua
    local hitRage = DEFAULT_HURT_RAGE
    if g.heroId == "intern" then
        hitRage = loss > 0 and INTERN_HURT_RAGE or INTERN_SHIELD_RAGE
    end
```

### 5.3 击杀怒气与来源系数

函数：`Game.Hit`

建议增加常量：

```lua
local FOLDER_KILL_RAGE_SCALE = 0.5
local ULT_KILL_RAGE_SCALE = 0.9
```

函数签名注释同步扩展：

```lua
---@param opts table? { noMult = boolean, rageScale = number }
function Game.Hit(g, e, damage, nx, ny, force, opts)
```

在函数开头读取来源系数：

```lua
    local rageScale = (opts and opts.rageScale) or 1
```

击杀结算当前代码：

```lua
    g.rage = math.min(100, g.rage + (e.kind == 4 and 7 or 3) * Buffs.RageMul(g))
```

改为：

```lua
    local killRage = (e.kind == 4 and 7 or 3) * rageScale
    g.rage = math.min(100, g.rage + killRage * Buffs.RageMul(g))
```

不要对 `killRage` 做 `floor`，否则1.5会变成1，2.7会变成2。

### 5.4 文件夹来源标记

位置：`ActionImpact` 的 `action.name == "folder"` 分支。

当前：

```lua
Game.Hit(g,e,110*(1+.25*Buffs.EffectLevel(g,"folderReinforced")),nx,ny,280)
```

改为：

```lua
Game.Hit(g,e,110*(1+.25*Buffs.EffectLevel(g,"folderReinforced")),nx,ny,280,
    { rageScale = FOLDER_KILL_RAGE_SCALE })
```

### 5.5 大招来源标记

位置：`BurstImpact` 的许宁分支。

当前：

```lua
if d<180*Buffs.UltRadius(g)+e.radius and Visible(g,g.player.x,g.player.y,e.x,e.y)then
    Game.Hit(g,e,150*Buffs.UltPower(g),nx,ny,350)
end
```

改为：

```lua
if d<180*Buffs.UltRadius(g)+e.radius and Visible(g,g.player.x,g.player.y,e.x,e.y)then
    Game.Hit(g,e,150*Buffs.UltPower(g),nx,ny,350,
        { rageScale = ULT_KILL_RAGE_SCALE })
end
```

### 5.6 不要改的地方

- 不要全局把受击12改成8；`TakeDamage` 为五个角色共用。
- 不要修改基础击杀值 `3 / 7`。
- 不要修改自然恢复 `dt * 2.5`。
- 不要修改“忍无可忍”的补怒公式。
- 不要修改 `Buffs.RageMul` 或“越想越气”的15%/层。
- 不要修改0.9秒受击无敌。
- 不要修改护盾上限、护盾回复速度或30%基础免伤。
- 不要为连锁、灼烧额外增加来源系数。

## 6. 必测用例

建议把以下断言加入 `web/lua/tests/InternBalance.lua`，并同步 `scripts/tests/InternBalance.lua`。

### 6.1 受击怒气

| 用例 | 初始条件 | 期望 |
|---|---|---:|
| 许宁实际掉血 | `shield=0, rage=0, invuln=0`，受到10伤害 | 怒气 **8** |
| 许宁护盾全吸收 | `shield=100, rage=0, invuln=0`，受到10伤害 | 怒气 **6**，HP不变 |
| 许宁护盾只挡一部分 | `shield=3`，受到100伤害 | 怒气 **8** |
| 越想越气1级掉血 | 持1层，实际掉血 | 怒气 **9.2** |
| 越想越气1级护盾吸收 | 持1层，护盾全吸收 | 怒气 **6.9** |
| 越想越气2级掉血 | 持2层，实际掉血 | 怒气 **10.4** |
| 越想越气2级护盾吸收 | 持2层，护盾全吸收 | 怒气 **7.8** |
| 无敌帧 | `invuln=0.9`，受到攻击 | 怒气不变 |
| 怒气封顶 | `rage=98`，触发8点受击怒气 | 怒气 **100** |
| 其他角色对照 | `male`，`rage=0, invuln=0`，受到10伤害 | 怒气 **12** |

### 6.2 击杀怒气

| 用例 | 期望 |
|---|---:|
| 文件夹系数击杀普通怪 | **1.5** |
| 文件夹系数击杀大锅 | **3.5** |
| 大招系数击杀普通怪 | **2.7** |
| 大招系数击杀大锅 | **6.3** |
| 无来源系数击杀普通怪 | **3.0** |
| 无来源系数击杀大锅 | **7.0** |
| 文件夹系数加2层越想越气 | **1.95** |
| 大招系数加2层越想越气 | **3.51** |
| 文件夹实际一击10杀 | 怒气增量约 **15 + 自然恢复** |
| 大招实际清30只普通怪 | 怒气约 **81 + 自然恢复** |

### 6.3 参考测试代码

```lua
local hurt=fixture();hurt.rage=0;hurt.shield=0;hurt.player.invuln=0
G.TakeDamage(hurt,10);near(hurt.rage,8,"intern hp loss grants 8 rage")

local blocked=fixture();blocked.rage=0;blocked.shield=100;blocked.shieldMax=100;blocked.player.invuln=0
G.TakeDamage(blocked,10);near(blocked.rage,6,"intern full shield hit grants 6 rage")
check(blocked.player.hp==120,"full shield hit does not damage hp")

local partial=fixture();partial.rage=0;partial.shield=3;partial.shieldMax=100;partial.player.invuln=0
G.TakeDamage(partial,100);near(partial.rage,8,"partial shield with hp loss grants 8 rage")

local buffed=fixture();buffed.rage=0;buffed.shield=0;buffed.player.invuln=0
B.Apply(buffed,"rageGain");G.TakeDamage(buffed,10)
near(buffed.rage,9.2,"one rageGain stack multiplies 8 by 1.15")

local capped=fixture();capped.rage=98;capped.shield=0;capped.player.invuln=0
G.TakeDamage(capped,10);check(capped.rage==100,"hurt rage still caps at 100")

local male=G.New("male");male.mode="playing";male.rage=0;male.player.invuln=0
G.TakeDamage(male,10);near(male.rage,12,"other heroes keep 12 hurt rage")

local function victim(g,kind)
    local e=assert(G.Spawn(g,kind or 1,570,580))
    e.hp,e.maxHp,e.speed,e.damage,e.attackCooldown,e.shield,e.armor=1,1,0,0,999,0,0
    return e
end

local folderKill=fixture();folderKill.rage=0
G.Hit(folderKill,victim(folderKill,1),100,1,0,280,{rageScale=0.5})
near(folderKill.rage,1.5,"folder direct normal kill grants 1.5")

local folderPot=fixture();folderPot.rage=0
G.Hit(folderPot,victim(folderPot,4),100,1,0,280,{rageScale=0.5})
near(folderPot.rage,3.5,"folder direct pot kill grants 3.5")

local ultKill=fixture();ultKill.rage=0
G.Hit(ultKill,victim(ultKill,1),100,1,0,280,{rageScale=0.9})
near(ultKill.rage,2.7,"intern ultimate direct normal kill grants 2.7")

local ultPot=fixture();ultPot.rage=0
G.Hit(ultPot,victim(ultPot,4),100,1,0,280,{rageScale=0.9})
near(ultPot.rage,6.3,"intern ultimate direct pot kill grants 6.3")

local plainKill=fixture();plainKill.rage=0
G.Hit(plainKill,victim(plainKill,1),100,1,0,280)
near(plainKill.rage,3,"unmarked normal kill keeps 3")

local plainPot=fixture();plainPot.rage=0
G.Hit(plainPot,victim(plainPot,4),100,1,0,280)
near(plainPot.rage,7,"unmarked pot kill keeps 7")
```

注意：

- 现有 `InternBalance` 的 `fixture()` 会把 `player.invuln` 设为999，受击测试前必须显式置0。
- 现有 `target()` 生成的是 `kind == 4` 的甩锅大锅，不能拿它测试“普通怪3点”；普通怪必须用 `G.Spawn(g, 1, ...)`。
- 文件夹和大招的实际清场测试会同时获得自然恢复，不能直接断言15或81整值；应断言“击杀部分”或允许自然恢复误差。

## 7. 回归与构建

在 `web/` 目录执行：

```bash
node tools/check-lua.mjs
node tools/run-lua-tests.mjs
```

运行许宁专项测试：

```bash
printf 'assert(require("tests.InternBalance").Run())\n' > tools/tmp/run-intern.lua
node tools/probe-run.mjs tools/tmp/run-intern.lua
rm tools/tmp/run-intern.lua
```

修改 `web/lua/Game.lua` 后必须重建清单，否则浏览器仍加载旧代码：

```bash
node tools/gen-manifest.mjs
```

如果本次交付包含 `web-dist`，再执行：

```bash
node tools/build-dist.mjs
```

禁止手工编辑 `web/js/manifest.js`；它是生成产物。

## 8. 验收标准

- [ ] 许宁实际掉血受击一次，怒气增加8。
- [ ] 许宁护盾完全吸收一次，HP不变，怒气增加6。
- [ ] 护盾部分吸收且仍掉血时，怒气增加8。
- [ ] 其他角色受击仍是12。
- [ ] “越想越气”叠加后分别约9.2/6.9、10.4/7.8。
- [ ] 文件夹直接击杀普通怪给1.5，大锅给3.5。
- [ ] 大招直接击杀普通怪给2.7，大锅给6.3。
- [ ] 无来源标记的击杀仍为3/7。
- [ ] 文件夹一次10杀，击杀怒气部分为15。
- [ ] 大招一次30杀，击杀怒气部分为81。
- [ ] 1.5、2.7、3.51等小数不被取整。
- [ ] 无敌帧仍不加怒，怒气仍封顶100。
- [ ] 自然恢复仍为2.5/秒。
- [ ] `tests.InternBalance` 原有159项断言继续通过。
- [ ] 全量纯逻辑回归通过。
- [ ] `web/lua/Game.lua`、`scripts/Game.lua`、`web/js/manifest.js` 已完成同步。

## 9. 本次不处理

- 其他武器击杀仍为普通怪3、大锅7。
- 连锁、灼烧造成的二次击杀仍为普通怪3、大锅7。
- “忍无可忍”仍无持有上限。
- 设计文档中的大招后1秒怒气锁仍未实装。
- 单次攻击的击杀数没有硬上限；大招清30只仍会瞬间补回81怒气。
- 文件夹清20只仍会瞬间补回30怒气。

如果上述清场跳条仍然过强，应另开需求处理“单次攻击击杀回怒上限”，不要在本单中继续压低受击数值。

## 10. 实施记录（已完成）

本单已按本文落地，实施者可直接对照核对：

| 项 | 落地情况 |
|---|---|
| `Game.lua` 常量 | 已加 `DEFAULT_HURT_RAGE / INTERN_HURT_RAGE / INTERN_SHIELD_RAGE / FOLDER_KILL_RAGE_SCALE / ULT_KILL_RAGE_SCALE`，放在 `TakeDamage` 之前 |
| 受击怒气 | `TakeDamage` 里按护盾结算后的 `loss` 分流，`loss>0` 给 8，`loss==0` 给 6，其他角色 12 |
| 击杀怒气 | `Game.Hit` 新增 `opts.rageScale`（默认 1），`local killRage = (e.kind==4 and 7 or 3) * rageScale`，**不取整** |
| 文件夹系数 | folder 分支的 `Game.Hit(...,280,{rageScale=FOLDER_KILL_RAGE_SCALE})` |
| 大招系数 | intern 大招分支的 `Game.Hit(...,350,{rageScale=ULT_KILL_RAGE_SCALE})` |
| `scripts/Game.lua` | 已同步（`diff` 一致） |
| `tests/InternBalance.lua` | 新增 16 条断言，**175 项全绿**（原 159） |
| 全量回归 | `check-lua` 76 文件通过；14 套纯逻辑全绿；`HeroLoadouts` 3677 项通过 |
| `web/js/manifest.js` | 已重建（820957 bytes） |

新增的 16 条里，两条是**走真实代码路径**的端到端验证，不只是单测 `Game.Hit`：

- `folderSweep(10) - folderSweep(0)`：同一段 0.46 秒文件夹动作，10 杀与 0 杀的怒气差值 **恰好 15**（自然恢复在两次运行里完全相同，相减抵消）。
- `G.BurstImpact(g)` 打 3 只 1 血怪，怒气 **恰好 8.1**，证明大招分支真的传了 0.9。
