# 下班！别挡我 · 全量对话与改动清单

> 取证时间 2026-11-08 21:34 之后 · 数据源：DSH 原始会话存档（jsonl.zstd 解压）+ ms-sync 部署仓库 git + 工作区逐文件比对
> 覆盖两个会话：`session-7850d67c`（旧，11-06 23:21 → 11-08 09:20）与 `session-9e1299d0`（当前，11-08 08:18 起），合计 **84 条真实用户指令**

---

## 0. 一句话摘要（数字）

| 指标 | 数值 |
|---|---|
| 真实用户指令 | **84 条**（旧会话 42 + 当前会话 42） |
| 对话轮次 | 旧 31 轮 + 当前 22 轮 = **53 轮** |
| 魔搭创空间部署 commit | **21 个**（11-06 14:33 → 11-08 17:59） |
| 线上当前版本 | `de8bf1c`（Ship shop rework, reroll quotas and dash travel） |
| 部署仓库文件数 | 88 |
| 游戏 Lua 模块 | 76（其中 33 个测试套件） |
| Lua 总行数 | 上线版 **14334 行** / 工作区 **14597 行**（+263 未上线） |
| 主仓库 OffWork-Rage git | 只有 **7 个 commit**；工作区 **74 已修改 + 112 未跟踪** 全部未提交 |
| 本会话改动落地方式 | 全部直接写工作区 → 同步进 ms-sync → 推送 → 调 OpenAPI 重新部署 |

---

## 1. 对话时间线（84 条指令，逐条）

### 1.1 旧会话 `session-7850d67c`（2026-11-06 23:44 → 11-08 00:10，42 条）

| # | 时间 | 指令（摘要） |
|---|---|---|
| 1 | 11-06 23:44 | 在我的仓库新建一个名字叫 OffWork-Rage 的仓库 |
| 2 | 23:50 | 帮我新建一个 github 的 token |
| 3 | 11-07 00:01 | 帮仓库更新的内容下载下来，解压，阅读项目了解项目类型 |
| 4 | 00:03 | `ghp_wyxFLfoy...` 试试这个 token |
| 5 | 00:22 | 按 modelscope.cn/skills/modelscope/ModelScope-Studio 下载安装配置 skills |
| 6 | 00:27 | `ms-cdd4f0f3-...`（魔搭 token） |
| 7 | 00:29 | 查看下我的空间有啥项目 |
| 8 | 00:37 | 本地仓库是 taptap 引擎 lua 写的，想部署到空间变在线可玩版本：① 探索空间支持的部署形式和技术栈，以浏览器可玩为前提重构 |
| 9 | 00:40 | 为什么选择这个技术栈？先说明后干活 |
| 10 | 00:44 | 性能呢，手机浏览器也要玩，先给方案等我指令 |
| 11 | 00:48 | 开始制作吧，使用多智能体 + 智能体团队，多线程完成开发重构上线全流程 |
| 12–14 | 02:39 / 02:42 / 02:43 | 现在进度如何 / 回答我，现在进度如何 / 继续 |
| 15 | 03:24 | 选女性角色无法选中；选人界面没消失，界面叠加 |
| 16 | 09:53 | 新任务 8 项：大招重制 / 5 武器 + BUFF / 元气骑士式程序化地牢 / 20+ 通用 BUFF 改五选一 / 10+ 随机事件 / 10+ 新怪含冲撞弹幕 / BOSS 机制 / 无尽模式 + 难度曲线 |
| 17 | 09:56 | 先完成代码重读和调研，开发等我指令 |
| 18 | 10:01 | 我不是让你先调研再等我消息吗？你在做啥 |
| 19 | 10:02 | 修的 bug 已经让 gpt 干了，你只负责调研后给方案 |
| 20 | 11:18 | 一个调研需要那么久吗 |
| 21 | 11:30 | 无尽模式与排行榜子智能体为什么卡那么久 |
| 22 | 11:45 | 开发难度大，所有新增内容减半；程序化地图和男女主大招必须做；无尽模式和积分规则先做，接口留好，给切一半的计划表 |
| 23 | 11:49 | 电脑性能最多能带多少个子 AGENT |
| 24–25 | 12:11 / 12:14 | 开始开发 / 继续 |
| 26–28 | 14:01 / 14:02 / 14:06 | 现在进度怎么样 / 子智能体怎么没干活？为什么不派遣 / 为什么部分子智能体完成后你没继续派遣 |
| 29 | 14:09 | 火力全开，把能派的活都派出去，压缩到 1.5 小时 |
| 30 | 14:21 | 汇报进度和实际情况，继续任务，子智能体完工后派新活 |
| 31–35 | 14:59 → 15:40 | 目前什么进度 / 继续任务 / 任务怎么停了 / 继续任务 / 挂了几个子智能体 |
| 36 | 15:59 | 推到创空间，我要测试 |
| 37 | 16:22 | 为什么上传个东西要那么久 |
| 38 | 16:24 | 直 404 了，查看原因并修复 |
| 39 | 16:27 | 你做了什么啊，你他妈不会用 skills 先看一下结构然后推送吗 |
| 40 | 16:37 | 已经好了 |
| 41 | 22:32 | 游戏对移动端非常不友好（无法横屏、摇杆卡住），先找出原因，别动手 |
| 42 | 22:39 | 代码修改量级有多少，会影响电脑端吗 |

### 1.2 当前会话 `session-9e1299d0`（2026-11-08 08:39 → 21:34，42 条）

| # | 时间 | 指令（摘要） |
|---|---|---|
| 1 | 08:39 | 先通读代码，了解项目类型 |
| 2 | 08:48 | 你现在在做什么？为啥那么慢 |
| 3 | 09:21 | 用 ModelScope-Studio skill 阅读已经部署在魔搭创空间的内容，这是最新版的 |
| 4 | 10:00 | 移动端全屏状态无法显示内容（其一）；问题 1 这个 pc 没问题，问题也出现在移动端；2 小问题尝试快速修复；3、4 不需要管 |
| 5 | 10:02 | 全屏主界面应该跟 PC 一样 |
| 6 | 10:10 | 现在是什么情况 |
| 7 | 11:00 | 你在做啥 |
| 8 | 11:02 | 你在修什么？我之前提到的几个点你修了吗？为什么要动那么多东西，不是说很小的问题吗 |
| 9 | 11:05 | 回答我问题！ |
| 10 | 11:13 | 一个多小时究竟在做什么，给完整回复 |
| 11 | 11:15 | 修个问题为什么花一小时 |
| 12 | 11:17 | 为什么修无关紧要的问题 |
| 13 | 11:17 | 那 11 个 fail 是什么 |
| 14 | 11:19 | 跟游戏有关吗 |
| 15 | 11:19 | 同步到魔搭并重新部署，拒绝无意义劳动 |
| 16 | 11:33 | 你在做啥 |
| 17 | 11:38 | 实际效果跟截图一样吗？工牌缩水、文字出格，把工牌恢复成右边的状态 |
| 18–19 | 11:45 / 11:56 | 现在什么情况 / 好了吗 |
| 20 | 12:00 | 给我停一下，你现在在做什么，请停止无意义的额外的工作 |
| 21 | 12:07 | 移动端摇杆向上移动一点（现在位置太靠下很容易卡手）；移动端 boss 血条向上移动，不要在屏幕中间；仅修改我提到的这些 |
| 22 | 12:11 | 先告诉我符符和召唤物数值在哪改，太弱了 |
| 23 | 12:14 | 暂停，先说明你现在改什么、怎么改 |
| 24 | 12:17 | 排两个智能体把血条和摇杆问题修了，你留下跟我探讨符符增强 |
| 25 | 12:43 | 七项需求：波次提示 3 秒 / boss 血条置顶同宽 / boss 延后 1 秒 / 事件页溢出 / 冲撞怪指示器 / 移动端 HP 与召唤物缩小 / 移动端边移动边点大招 / 符符方案 A / 商店改版参考图 4 |
| 26 | 13:18 | 同上完整版 + 剩余怪物数放暂停键下方 + 8~10 个智能体同步开工 |
| 27 | 13:24 | 补充：回形针弹弓削弱，射速、攻击各削弱 10% |
| 28–30 | 14:32 / 14:38 / 15:43 | 现在什么进度 / 还需要多久 / 还需要多久，差多少 |
| 31 | 15:48 | 继续，让我能看到改造进度，不要一头闷着 |
| 32 | 15:50 | 打断，商店补给池都有什么 |
| 33 | 15:56 | 商店池扩展，保留体力恢复，剩下四种从增益池抽取；顺便核实「许宁增益 50%」这条提示是否真的生效，先告诉我结果 |
| 34 | 16:02 | 改，闪避和刷新两个增益未生效要补上；刷新按钮：每局 3 次 buff 刷新、2 次商店刷新、1 次事件刷新 |
| 35 | 16:03 | 把 buff 功能实现派给其他智能体 |
| 36 | 17:08 | 现在进度如何 |
| 37 | 17:19 | 派一个低思考强度智能体快速整理符符机制设定 / 数值 / 专属 buff 成 md |
| 38 | 17:23 | 汇报主线进度，还有多少代码量 |
| 39 | 17:27 | 一个多小时了这点需求都完不成，你好长时间用在多余思考上，不要过度思考 |
| 40 | 18:10 | 目前已经上传到位了 |
| 41 | 18:10 | 我可以正常游玩了 |
| 42 | 21:34 | 给对话 ID，帮我整理所有对话和改动 |

### 1.3 另有并行会话（旁支，未落地）
`session-e1d9cfc3`（11-08 16:43，245 条记录，4 条指令）：要求出「不降画质、不动架构」的加载 40~60 秒优化方案，明确「不要动代码」「出方案阶段不要动代码」「你等会，我让你直接改我文件了吗」。**方案未落地，加载优化仍是未完成线索。**

---

## 2. 部署历史（ms-sync，master，21 个 commit）

| # | commit | 时间 | 标题 | 规模 |
|---|---|---|---|---|
| 1 | `5c19b1d` | 11-06 14:33 | System update meta information | 2 文件 +73 |
| 2 | `df7dd36` | 11-07 02:50 | Deploy OffWork-Rage browser build | 55 文件 +2525/−73 |
| 3 | `19bd780` | 03:30 | Fix hero panel clicks and replace stale UI roots | 1 文件 +12/−2 |
| 4 | `45f5f84` | 04:01 | Fix high-DPI rendering and reduce combat navigation stalls | 3 文件 +8/−6 |
| 5 | `b1c28ac` | 04:03 | Restore original detailed enemy artwork with load-time transparent bounds | 8 文件 +25/−3 |
| 6 | `1571cc9` | 04:32 | Eliminate wall-contact pathfinding stalls and basic-hit world freezes | 2 文件 +62/−3 |
| 7 | `01bbca9` | 07:32 | Replace combat portraits with animated chibi hero atlases | 6 文件 +375/−7 |
| 8 | `e9bc1a1` | 07:48 | Add front and back idle and walking hero animations | 5 文件 +360/−6 |
| 9 | `1dc1558` | 10:20 | Redesign responsive game UI and animate enemies, loot and combat effects | 23 文件 +2127/−35 |
| 10 | `b72e6e0` | 10:21 | Ship regenerated font subsets only | 6 文件（二进制替换） |
| 11 | `58eaba6` | 16:03 | static site: OffWork-Rage browser build (S0-S5 full feature) | 80 文件 +178/−2831 |
| 12 | `e344884` | 16:26 | fix: static site root - web-dist content at repo root | 52 文件（路径搬迁） |
| 13 | `e8fe451` | 19:40 | Add four hero loadouts, folder upgrade picker and finished combat art | 25 文件 +259/−59 |
| 14 | `d730e46` | 20:37 | Add bounded combat pressure and shared score service | 9 文件 +363/−38（**首次加 server.py + Dockerfile**） |
| 15 | `c069a46` | 20:38 | Keep result content inside stationery borders | 1 文件 +1/−1 |
| 16 | `9f71cbb` | 21:04 | Separate binary and clip projectile impact art | 2 文件 +7/−5 |
| 17 | `17f3e61` | 23:15 | Fix mobile viewport, touch controls and intern reward scaling | 9 文件 +170/−23 |
| 18 | `303c51e` | 23:59 | Launch Fufu with five companions and cake charge gameplay | 17 文件 +39/−19 |
| 19 | `5a1f95e` | 11-08 11:20 | Fix mobile fullscreen HUD mount, roster discoverability and score form initial error | 4 文件 +58/−6 |
| 20 | `287db19` | 11:51 | Restore full-height hero badges on wide windows | 1 文件 +3/−3 |
| 21 | `de8bf1c` | 17:59 | Ship shop rework, reroll quotas and dash travel | 6 文件 +55/−16 |

**本次会话（11-08 08:39 起）新增 3 个 commit：`5a1f95e` / `287db19` / `de8bf1c`。**
`git diff --numstat 303c51e HEAD`（上一版线上 → 当前线上）：css/expansion.css +53/−2、js/engine.js +30/−1、js/manifest.js +17/−17、js/ui.js +12/−1、3 个字体 ttf 二进制。

### 主仓库 OffWork-Rage（本地，7 个 commit，本会话改动全未提交）
`1c8b931` Initial commit → `5ef33c2` Add full project assets bundle → `a933cdf` Add full game project → `422a5f1` S0 baseline → `cd87c93` S1 endless + local leaderboard → `fc519dc` S2-S5 combat/enemies/dungeon/events + boss phases + regression infra → `a6cc516` tools: build-dist.mjs（HEAD）。
`git status --porcelain` = **74 M + 112 ??**。

---

## 3. 已上线改动（逐条，de8bf1c = 线上当前）

### 批次 A｜浏览器化移植 + 首版上线（旧会话，commit 2–18）
1. **技术栈定案**：fengari-web 0.1.4（纯 JS Lua 5.3 VM，非 WASM）+ Canvas2D 单画布 + DOM/CSS UI + Python 静态服务 + Docker，部署魔搭创空间（docker SDK，端口 7860）。
2. **Lua 全量内联**：76 个 .lua 模块打进 `js/manifest.js` 的 `DSH.MANIFEST.luaSources`（键为点号模块名），构建链 = gen-manifest.mjs + subset-fonts.py。
3. **高 DPI 渲染修复**（45f5f84）：devicePixelRatio 缩放 + 战斗期导航卡顿削减。
4. **敌人美术恢复**（b1c28ac）：7 张敌人图放大 20 倍 + 载入期透明边界裁剪。
5. **寻路卡顿修复**（1571cc9）：消除贴墙寻路死锁与普攻全屏冻结（engine +58 行）。
6. **英雄改 chibi 动画图集**（01bbca9 / e9bc1a1）：替换静态立绘，加入前/后 idle 与行走帧。
7. **响应式 UI 重设计**（1dc1558）：23 文件 +2127/−35，7 张敌人 atlas + effects/icons + 3 个完整 ttf（6.9MB）。
8. **字体子集化**（b72e6e0）：删 3 个 6.9MB 全量 ttf，只留 subset。
9. **静态站点根目录修正**（58eaba6 / e344884）：`web-dist` 内容搬到仓库根，修 404。
10. **四英雄 loadout + 文件夹升级选择器 + 完成版战斗美术**（e8fe451）：25 文件 +259/−59，expansion 5 张图 + 6 个新怪 + intern/programmer + ui/badge|desk|notes|paper。
11. **战斗压力上限 + 共享积分服务**（d730e46）：新增 `server.py`（235 行）+ `Dockerfile`；engine +79、ui +18。
12. **移动端视口 / 触控 / 实习奖励缩放修复**（17f3e61）：mobile-layout.css +47、mobile-display.js +50、engine +43、ui +24、index +6。
13. **符符上线（5 位同伴 + 蛋糕充能）**（303c51e）：10 张 fufu 图 + manifest +52。

### 批次 B｜全屏 / 工牌 / 结算红字（当前会话 10:00–12:00，commit 19–20）
14. **移动端全屏无内容**（5a1f95e，5 文件 +97/−9）
    - `web/js/ui.js` `canvasHost()`：优先返回 `document.getElementById("ui-root")`，回退 `state.canvas || document.body` → `#officeRoot` 进入 `requestFullscreen(#app)` 子树。
    - `web/js/engine.js` `attachDom`：加 `fullscreenchange` / `webkitfullscreenchange` → `resizeSoon()`（resize + 下一帧 rAF resize）+ `new ResizeObserver(resize)`；`detachDom` 对称清理。
    - `web/lua/main.lua`：新增 `nickSubmitPending` 标志 + `SCORE_ERROR_TEXT`（18 条服务端错误码→中文）+ `ScoreErrorText(code)`，修结算页首屏红字。
    - `web/lua/HeroSelectUI.lua`：hint 恒显示「共 N 位同事 · 上下滑动查看全部」（原 `visible=p.portrait or p.landscape` 在 1280x800 恒 false）。
    - `web/css/expansion.css`：`.hero-badge-grid` 两列 `minmax(0,1fr)`、`>=900px` 三列、`#heroBadgeScroll` `overflow-x:hidden` + `padding:0 8px`（`.employee-badge` `rotate(-3deg)` 造成 7px 横向溢出）。
15. **工牌缩水 / 文字出格回退**（287db19，css +3/−3）：删掉 `height:257px!important` 强制值，宽窗口恢复全高。
16. **探针页 11 个 FAIL 判定为探针自身缺陷并回退**：三类原因 —— ①套件在模块顶层写 `local originalStart = Start`，探针先清空全局导致 `attempt to call a nil value (upvalue 'originalStart')`；②Menu/OfficeIdentity 只定义 `HandleUpdate` 无 `.Run()`/`Start()`；③HeroRules:72 跨套污染。**与游戏无关，未改任何游戏代码。**

### 批次 C｜HUD / 逻辑 / 事件 / 商店 / 指示器 / 数值（当前会话 12:07–17:59，12 张共享任务卡，全部 completed）
17. **task-1 移动端摇杆上移**：`web/lua/HudUI.lua:104-107`，横屏 `bottom=52`（原 24），**竖屏保持 24**（52 会让顶边 698 压住装备槽底边 710，重叠 12px）。
18. **task-2 移动端 boss 血条上移**：`web/lua/HudUI.lua:102-106`，脱离屏幕竖直中部。
19. **task-3 HUD 布局重构**（`HudUI.lua` +82/−31 与 `FufuHud.lua`）：boss 血条 `bossLeft=p.portrait and 20 or (p.w-noticeW)/2` + `width=noticeW`（与波次提示同宽贴顶）；移动端 HP 卡缩小；召唤物面板缩小。
20. **task-4 游戏逻辑**（`Game.lua` + `main.lua`）：波次提示显示 3 秒后隐藏（末参 2→3）；新增 `hudEnemiesLeft` 元素，文案「剩余 N 个怪物」，放暂停键下方、复用波次提示底框且尺寸更小；boss 先提示波次、1 秒后与血条同时出现（`BOSS_APPEAR_DELAY=1.0`，`Game.lua:259-260`、:316-317）；移动端多点触控（`ui.js` `wireButtonStates` 加 `pointerdown` + `!e.isPrimary` 直接 `fireClick`，实现边移动边点大招）。
21. **task-5 事件页文字与选项框溢出**（`CampaignUI.Event`）：真因是 `web/css/game.css:119` 的 `#officeRoot .game-card>[data-kind=ScrollView]>[data-kind=Panel]{padding:64px 38px 28px!important}` 带 `!important`，把 Lua 算的 `paddingRight=padding+12` 整条覆盖。
22. **task-6 / task-12 商店改版（参考图 4，folder-picker 双栏）**：`web/lua/CampaignUI.lua` 468→568 行（+189/−79），`CampaignUI.Shop` 整体重写 `:329-511`（5 行 folder-picker + 右侧大预览 + `shopBuyConfirm`/`shopReroll`/`shopLeave`）；`web/css/expansion.css` 117→128 行新增 `#campaignShop` 收口；复用 buff 素材。
23. **task-7 机制怪指示器**（只改 `web/lua/Draw.lua`）：新增 `ChargeLane` helper（:76-102）+ 6 处分支，修冲撞怪长条与本体脱节；自爆危险圈 `Stroke(e.x,e.y,ai.blastRadius or 62,…)`；spitter 青带 / printerBoss 金带同步。**关键约束：gfx.js 没导出 `nvgMoveTo/nvgLineTo`，斜向长条只能 `nvgSave + nvgTranslate + nvgRotate`。**
24. **task-8 符符增强（方案 A）**：`FufuSummons.lua` 丹旺旺 hp 280→300；`FufuCombat.lua` 灯泡伤害与频率各 +5%；`Heroes.lua` 符符 maxHp 90→100 + `reduction=.10`。
25. **task-9 回形针弹弓削弱**：`Weapons.lua:34` damage `{15,19,24,30,37}`→`{13.5,17.1,21.6,27,33.3}`；`:140` `Scaling.Growth(g,13.5,…)`；`:142` 冷却 `0.34→0.374`（射速与攻击各 −10%）。
26. **task-10 闪避增益「闪人」落地**：Z 键 / HUD 按钮触发，`Game.Dash` 真正产生位移（实测 x 520→572→651，冷却 3.53s），0.18 秒无敌 + 残影；`main.lua:24` `ZKey`、`:202` `TriggerDash()`、`HudUI.lua:115` `dashButton` + `:179-182` 每帧 visible/disabled/文案。
27. **task-11 刷新增益「重开一版」落地**：升级页刷新按钮（`UpgradeUI.lua:28-31` `BuildFooter`/`upgradeReroll`，文案「刷新 ↻  剩 N 次」）+ 事件刷新 API（`Events.lua:461` `CopyChoices`、`:515` `Events.Reroll`、`:525`）；R 键分发 `main.lua:647/660/668`。
28. **刷新配额与商店池扩展**：`Game.lua:172` `shopRerollsLeft=2, eventRerollsLeft=1`、`:170` `rerollsLeft=3`（每局 3 次 buff / 2 次商店 / 1 次事件）；`:328` `SHOP_PRICE={common=30,rare=45,epic=60}`、`:329` `SHOP_BUFF_COUNT=4`、`:331` `RollShopBuff`、`:347` `BuildShopItems`（保留体力恢复，其余从增益池抽取）；`:914` `Game.RerollShop`、`:936` `RerollEvent`、`:948` `RerollChoices`；次数用尽文案「刷新 ↻  已用完」+ disabled。
29. **波次播报时长**：`Game.lua:1772` seconds 2→3。
30. **字体子集重生成**：因新增字符（↻ U+21BB 等），3 个 ttf 从 255720/259768/256360 → 259680/263764/260320 字节。

### 上线验证（de8bf1c 实测）
- 线上 `js/manifest.js` 878740 = 本地 878740 **rawEq true**；`css/expansion.css` 10644 = 10644 **rawEq true**；`js/ui.js` live 28695 vs local 29335（normalize 后相等，差异纯 CRLF）。
- `/api/health` = `{"ok":true,"storage":"sqlite","version":"office-expansion-v3","ruleset":"balance-2026-11-07-v2"}`。
- manifest 内含全部新符号：`shopRerollsLeft` / `eventRerollsLeft` / `RerollShop` / `RerollEvent` / `RerollChoices` / `SHOP_BUFF_COUNT` / `upgradeReroll` / `eventReroll` / `campaignShop`。
- 浏览器实测：`#menuStart` → `#heroConfirm`（5 张 `.employee-badge` + hint 文案）→ canvas 1440x900，HUD id 齐全，`pageErrors=[]`。
- 功能探针：shop `mode=shop items=5`、5 个 `.folder-index-row`；买 → coins 300→270、buffs 1；刷新 2→1 且保留 heal；用尽后按钮 disabled。upgrade 刷新 3→2 且候选项更换。dash 位移真实生效。

---

## 4. 未上线改动（工作区已写、线上 de8bf1c 没有）

**判定依据**：`OffWork-Rage/ms-sync/js/manifest.js`（878740B）vs `OffWork-Rage/web/js/manifest.js`（893443B），76 个模块中 **10 个不同**，其余 66 个逐字节相同；css/expansion.css、css/game.css、js/ui.js、js/engine.js、index.html **全部逐字节相同**。
**来源**：另一条工作线（用户与另一个 agent 的会话），mtime 11-08 20:28–21:17，用户尚未要求上线。

| # | 模块 | 行数变化 | 改了什么 |
|---|---|---|---|
| 1 | `Heroes.lua` | 44 → 44 | 周序 programmer `maxHp=65,speed=128` → **`maxHp=80,speed=138`**；description「等级越高，子弹越狠」；林夏改霰弹口径描述 |
| 2 | `FufuSummons.lua` | 45 → 53 | 血量全体 ×1.8：maple 100→**180**、water 85→**153**、dan 300→**540**、cat 90→**162**、dog 170→**306**；新增 `M.DULL={dan=true,water=true}` 哑炮标记 + `dryStreak` 保底（连两只哑炮强制 `{"maple","cat","dog"}[(nextId%3)+1]`）；`ChargeInterval` `max(16,24/…)`→**`max(8,12/…)`**；`state.cooldown` .8→.4 |
| 3 | `FufuCombat.lua` | 285 → 328 | 新增 `F.Growth(g)=min(.40,.008*max(0,g.level-1))`（伙伴随等级 +0.8%/级，上限 +40%；刻意不用 roomsCleared 因 `Endless.lua:268` 每波归零）、`F.PetInherit(g)=1+max(0,g.damage-1)*.30`、`F.PetHaste(g)`、`F.ReflectRatio(g)=min(.45,.30+.05*level(fufuProtection))` + `F.Reflect` 走 `TrueHit` 上限 `p.maxHp*.12`、阵亡返还 40% 充能、`p.invuln` .3→.6；灯泡伤害 **12.6/18.9/8.4 → 15/22.5/10**；电链 12.6→15；射击间隔 **1.333 → 1.0 秒** |
| 4 | `Game.lua` | 1753 → 1806 | 许宁怒气口径 `DEFAULT_HURT_RAGE=12`/`INTERN_HURT_RAGE=8`/`INTERN_SHIELD_RAGE=6`/`FOLDER_KILL_RAGE_SCALE=0.5`/`ULT_KILL_RAGE_SCALE=0.9`，`Game.Hit` 新增 `opts.rageScale`；林夏霰弹 `shotgun=g.primaryWeapon=="stapler"`，节奏 1.05s 起每级 −10%（其他角色仍 0.75s/−16%），`pellets=3+g.stapler`、`pierce=g.stapler>=3 and 2 or 1`、`pelletDamage=12+2*g.stapler`、扩散 0.17rad、速度 360、life 0.46、`knock=280`、衰减 `foNear=40,foRange=126,foMin=0.35`；周序子弹 `12+3*level(codeExploit)+floor((g.level-1)*.9)` + 自带 1 次穿透；机械键盘扇区 ±97°→±93°、射程 104→100（覆盖面积 −11.4%） |
| 5 | `Buffs.lua` | 417 → 417 | `codeExploit` desc → 「二进制自带1次穿透；每层基础伤害+3、穿透+1」；`fufuSnack` 「每格最低16秒」→**「最低8秒」**；`fufuProtection` 增反伤 +5%（上限 45%） |
| 6 | `tests.FufuCombat` | 149 → 213 | 充能 24→12 秒、伤害 15/22.5/10、丹旺旺 540、哑炮保底每次用新 state |
| 7 | `tests.InternBalance` | 128 → 182 | +54 行怒气全口径断言（8/6/1.5/3.5/2.7/6.3） |
| 8 | `tests.Actions` | 536 → 570 | +34 行霰弹弹丸数（4 颗）与距离衰减 |
| 9 | `tests.HeroLoadouts` | 90 → 90 | binary 9→12、exploit 11→15 且 pierce 1→2 |
| 10 | `tests.HeroRules` | 357 → 364 | 林夏 4 颗 × 14 |

**新增设计文档（工作区 docs/design/，均未跟踪）**：
`11-pressure-balance.md`(5194B)、`14-fufu-mechanics.md`(23146B)、`15-intern-rage-tuning.md`(15664B)、`16-fufu-buff-plan.md`(37106B)、`17-female-shotgun.md`(26737B)；`02-weapons-buffs-ults.md` 于 21:01 改写（165687B）。

---

## 5. 数据统计

### 5.1 Lua 规模
| 口径 | 模块数 | 测试套件 | 总行数 | 字节 |
|---|---|---|---|---|
| 线上 de8bf1c（manifest 内联） | 76 | 33 | **14334** | 820851 |
| 工作区（未上线） | 76 | 33 | **14597** | 835730 |
| 303c51e → de8bf1c 增量 | 76 | 33 | **+553** | — |

### 5.2 关键文件大小（线上 = 工作区，仅 manifest 不同）
| 文件 | 线上 ms-sync | 工作区 web |
|---|---|---|
| js/manifest.js | 878740 | 893443 |
| js/engine.js | 45892 | 45892 |
| js/ui.js | 29335 | 29335 |
| css/expansion.css | 10644 | 10644 |

### 5.3 12 张共享任务卡（全部 completed）
task-1 摇杆上移｜task-2 boss 血条上移｜task-3 HUD 布局｜task-4 游戏逻辑｜task-5 事件溢出｜task-6 商店改版｜task-7 指示器｜task-8 符符方案 A｜task-9 弹弓削弱｜task-10 闪避落地｜task-11 刷新落地｜task-12 商店 folder-picker + 刷新按钮

---

## 6. 未完成 / 遗留线索

1. **加载 40~60 秒优化**：用户抱怨过，旁支会话出过方案，但 11-08 17:00 被叫停（「你等会，我让你直接改我文件了吗」），**未落地**。
2. **工作区 10 个模块的平衡改动未上线**（第 4 节全部内容），用户尚未要求部署。
3. **主仓库 OffWork-Rage 未提交**：74 M + 112 ??，本会话全部改动只存在于工作区与 ms-sync。
4. **`Dungeon.USE_DUNGEON = false`**：程序化地牢已实现但灰度关闭，线上走 Campaign 手写 3 层。
5. **`Weapons.DEFS` 中 `laser` 激光打印、`extinguisher` 灭火器 `enabled=false`**，desc 明写「当前版本未启用」。
