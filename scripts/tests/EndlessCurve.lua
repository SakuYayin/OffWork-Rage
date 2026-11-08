-- 无尽模式数值曲线 + 状态机回归（S1）。
-- 依据 docs/design/05-endless-leaderboard.md §2.1-§2.8 的表格与公式：公式即契约，
-- 改任何一个常数都会让这里红。分两段：
--   ① 纯函数（曲线 / Boss / 分数）—— 全是文档表格里的硬数字；
--   ② 有状态流程（Start / Update / TickSpawn / SpawnBoss / OnDeath / BuildEntry）——
--      用真实 Game.New 状态跑，不替换产品函数，断言对象是 g 与 g.endless 的实际字段。
local Endless = require("Endless")
local Game = require("Game")
local Campaign = require("Campaign")

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

local function between(value, low, high, label)
    ok(type(value) == "number" and value >= low and value <= high,
        string.format("%s: got %s 不在 %s..%s", label, tostring(value), tostring(low), tostring(high)))
end

-- ------------------------------------------------------------------ ① 纯函数
local function CurveChecks()
    -- §2.3 每波数量表：第 1..16 波逐格核对，第 16 波触顶
    local counts = { 6, 8, 11, 14, 17, 20, 24, 28, 31, 36, 40, 44, 49, 54, 59, 60 }
    for wave = 1, 16 do eq(Endless.Count(wave), counts[wave], "Count(" .. wave .. ")") end
    eq(Endless.Count(16), 60, "Count(16) 封顶")
    eq(Endless.Count(30), 60, "Count(30) 封顶")
    eq(Endless.Count(99), 60, "Count(99) 封顶")

    -- §2.5 三条倍率：血量不封顶、伤害 30 波封顶、移速 16 波封顶
    near(Endless.HpScale(1), 1.00, 1e-9, "HpScale(1)")
    near(Endless.HpScale(5), 2.216, 1e-9, "HpScale(5)")
    near(Endless.HpScale(30), 21.416, 1e-9, "HpScale(30)")
    eq(math.floor(26 * Endless.HpScale(1)), 26, "第1波 k1 血量")
    eq(math.floor(26 * Endless.HpScale(30)), 556, "第30波 k1 血量")
    eq(math.floor(76 * Endless.HpScale(30)), 1627, "第30波 k4 血量")
    eq(Endless.DmgScale(1), 1.0, "DmgScale(1)")
    eq(Endless.DmgScale(30), 3.6, "DmgScale(30) 封顶")
    eq(Endless.DmgScale(50), 3.6, "DmgScale(50) 封顶")
    near(Endless.DmgScale(10), 1.855, 1e-9, "DmgScale(10)")
    near(Endless.SpdScale(1), 1.00, 1e-9, "SpdScale(1)")
    near(Endless.SpdScale(16), 1.36, 1e-9, "SpdScale(16)")
    near(Endless.SpdScale(30), 1.40, 1e-9, "SpdScale(30) 封顶")
    eq(math.floor(56 * Endless.SpdScale(16)), 76, "第16波 k1 移速")
    eq(math.floor(34 * Endless.SpdScale(16)), 46, "第16波 k4 移速")

    -- §2.5 同波内衰减：首只 100%、末只 75%、线性
    near(Endless.BatchHpMul(1, 1), 1.0, 1e-9, "BatchHpMul(1,1) 单只")
    near(Endless.BatchHpMul(1, 4), 1.0, 1e-9, "BatchHpMul(1,4) 首只")
    near(Endless.BatchHpMul(2, 4), 0.9166666667, 1e-9, "BatchHpMul(2,4) 第二只")
    near(Endless.BatchHpMul(3, 4), 0.8333333333, 1e-9, "BatchHpMul(3,4) 第三只")
    near(Endless.BatchHpMul(4, 4), 0.75, 1e-9, "BatchHpMul(4,4) 末只")
    near(Endless.BatchHpMul(1, 13), 1.0, 1e-9, "BatchHpMul(1,13) 首只")
    near(Endless.BatchHpMul(13, 13), 0.75, 1e-9, "BatchHpMul(13,13) 末只")
    near(Endless.BatchHpMul(99, 4), 0.75, 1e-9, "BatchHpMul 越界钳到末只")
    near(Endless.BatchHpMul(0, 4), 1.0, 1e-9, "BatchHpMul 越界钳到首只")

    -- §2.4 Boss 血量表 k=1..10（含 HEROISM 造成的锯齿，是正常结果不是笔误）
    local bossHp = { 1688,1879,2807,3794,3661,4968,6264,5735,7464,9099 }
    for k = 1, 10 do
        eq(Endless.BossHp((k - 1) % 3 + 1, k), bossHp[k], "BossHp(k=" .. k .. ")")
    end
    eq(Endless.BossHp(1, 1), 1688, "BossHp(1,1) 工贼")
    eq(Endless.BossHp(2, 2), 1879, "BossHp(2,2) 主管")
    eq(Endless.BossHp(1, 10), 9099, "BossHp(1,10)")
    ok(Endless.BossHp(3, 3) > Endless.BossHp(2, 3), "同 k 老板血厚于主管")
    ok(Endless.BossHp(1, 3) > Endless.BossHp(3, 3), "同 k 工贼血最厚（HEROISM 1.25）")
    -- 锯齿是跨角色比的：主管(k=5) 低于工贼(k=4)，因为 HEROISM 1.00 < 1.25
    ok(Endless.BossHp(2, 5) < Endless.BossHp(1, 4), "k=5 主管低于 k=4 工贼（HEROISM 锯齿）")
    ok(Endless.BossHp(2, 8) < Endless.BossHp(1, 7), "k=8 主管低于 k=7 工贼（HEROISM 锯齿）")
    ok(Endless.BossHp(1, 5) > Endless.BossHp(1, 4), "同角色血量单调递增")

    -- §2.4 技能等级 / 二阶段阈值
    eq(Endless.BossSkill(1), 1, "BossSkill(1)")
    eq(Endless.BossSkill(2), 1, "BossSkill(2)")
    eq(Endless.BossSkill(3), 2, "BossSkill(3)")
    eq(Endless.BossSkill(9), 5, "BossSkill(9)")
    eq(Endless.BossSkill(20), 5, "BossSkill(20) 封顶")
    local phaseAt = { 0.62, 0.58, 0.54, 0.50, 0.46, 0.42, 0.38, 0.35, 0.35, 0.35 }
    for k = 1, 10 do near(Endless.BossPhaseAt(k), phaseAt[k], 1e-9, "BossPhaseAt(" .. k .. ")") end
    near(Endless.BossPhaseAt(1), 0.62, 1e-9, "BossPhaseAt(1)")
    near(Endless.BossPhaseAt(20), 0.35, 1e-9, "BossPhaseAt(20) 下限")

    -- §2.4 每 3 波一个 Boss，三位轮换
    eq(Endless.BossFor(1), nil, "BossFor(1) 不是 Boss 波")
    eq(Endless.BossFor(2), nil, "BossFor(2) 不是 Boss 波")
    eq(Endless.BossFor(3).kind, 1, "BossFor(3) 工贼")
    eq(Endless.BossFor(6).kind, 2, "BossFor(6) 主管")
    eq(Endless.BossFor(9).kind, 3, "BossFor(9) 老板")
    eq(Endless.BossFor(12).kind, 1, "BossFor(12) 回环")
    eq(Endless.BossFor(3).k, 1, "BossFor(3).k")
    eq(Endless.BossFor(30).k, 10, "BossFor(30).k=10")
    eq(Endless.BossFor(30).hp, 9099, "BossFor(30).hp 与 BossHp 一致")
    eq(Endless.BossFor(3).name, "工贼同事", "BossFor(3).name")
    eq(Endless.BossFor(6).name, "秃头主管", "BossFor(6).name")
    eq(Endless.BossFor(9).name, "没良心老板", "BossFor(9).name")

    -- §2.6 经验曲线
    eq(Endless.XpNeed(1), 22, "XpNeed(1)")
    eq(Endless.XpNeed(5), 70, "XpNeed(5)")
    eq(Endless.XpNeed(10), 147, "XpNeed(10)")
    eq(Endless.XpNeed(20), 352, "XpNeed(20)")
    eq(Endless.XpNeed(30), 627, "XpNeed(30)")
    eq(Endless.XpNeed(34), 756, "XpNeed(34)")
    eq(Endless.XpNeed(50), 1387, "XpNeed(50)")
    eq(Endless.XpNeed(99), 4432, "XpNeed(99)")
    ok(Endless.XpNeed(30) > 12 + 10 * 30, "无尽曲线末期高于原版线性")

    -- §2.7 十个分数样例 + 天花板
    eq(Endless.Score(1, 6, 1, 0, 72), 1328, "Score#1")
    eq(Endless.Score(3, 25, 4, 1, 216), 5608, "Score#2")
    eq(Endless.Score(5, 56, 5, 1, 360), 8452, "Score#3")
    eq(Endless.Score(10, 195, 11, 3, 720), 19440, "Score#4")
    eq(Endless.Score(15, 441, 18, 5, 1080), 31752, "Score#5")
    eq(Endless.Score(20, 741, 23, 6, 1440), 43132, "Score#6")
    eq(Endless.Score(25, 1041, 27, 8, 1800), 55972, "Score#7")
    eq(Endless.Score(30, 1341, 32, 10, 2160), 68852, "Score#8")
    eq(Endless.Score(35, 1641, 34, 11, 2520), 80112, "Score#9")
    eq(Endless.Score(40, 1941, 38, 13, 2880), 92952, "Score#10")
    eq(Endless.Score(60, 3141, 50, 20, 3600), 140492, "Score 天花板")
    eq(Endless.Score(60, 3141, 50, 20, 9999), 140492, "Score 时间封顶 3600")
    -- 表形态与位置形态必须给同一个数（两条调用约定都被调用方使用）
    local g = { kills = 195, level = 11, time = 720, endless = { wave = 10, bossLevel = 3 } }
    eq(Endless.Score(g), 19440, "Score(table) 与位置参数一致")
    eq(Endless.Score({ kills = 6, level = 1, time = 72, endless = { wave = 1 } }), 1328,
        "Score(table) 缺 bossLevel 时按 0")
    eq(Endless.Score({}), 40, "Score(空表) 只有 40*level(1)")

    -- 常量（调用方已经按这些值写死）
    eq(Endless.LEVEL_CAP, 99, "LEVEL_CAP")
    eq(Endless.MAX_ONSCREEN, 45, "MAX_ONSCREEN")
    eq(Endless.BATCH_SIZE, 12, "BATCH_SIZE")
    near(Endless.BATCH_INTERVAL, 1.2, 1e-9, "BATCH_INTERVAL")
    eq(Endless.BOSS_EVERY, 3, "BOSS_EVERY")
    ok(Endless.MAX_ONSCREEN < 70, "同屏上限必须低于 Game.Spawn 的 70 硬顶")

    -- 刷怪池：波 1 只出 kind1；高波次始终落在 1..4，且四种都会出现
    for _ = 1, 30 do eq(Endless.PickKind(1), 1, "PickKind(1) 只出 kind1") end
    for _ = 1, 30 do eq(Endless.PickKind(2), 1, "PickKind(2) 只出 kind1") end
    local seen = {}
    for _ = 1, 600 do
        local kind = Endless.PickKind(20)
        ok(({[1]=true,[2]=true,[3]=true,[4]=true,[6]=true,[7]=true,[11]=true,[12]=true,[13]=true})[kind], "PickKind(20) 合法怪池")
        ok(kind == math.floor(kind), "PickKind(20) 返回整数")
        seen[kind] = true
    end
    for _,kind in ipairs({1,2,3,4,6,7,11,12,13})do ok(seen[kind] == true, "PickKind(20) 能抽到 kind" .. kind) end
    -- 早波不该出现精英：波 5 只出 1/2
    for _ = 1, 200 do local k=Endless.PickKind(5);ok(k==1 or k==2 or k==3 or k==6 or k==7,"PickKind(5) 早期引入新怪但无召唤护盾怪")end
end

-- ------------------------------------------------------------------ ② 有状态流程
local function StateChecks()
    local g = Game.New("female")
    local before = g.uiRevision
    local e = Endless.Start(g, { seed = 12 })

    -- Start：房间与命名空间
    eq(g.mode, "playing", "Start 后 mode=playing")
    eq(g.floor, 1, "Start 后 floor=1")
    eq(g.roomsCleared, 0, "Start 后 roomsCleared=0")
    eq(e, g.endless, "Start 返回 g.endless")
    eq(g.endless.active, true, "endless.active")
    eq(g.endless.wave, 0, "endless.wave 从 0 起")
    eq(g.endless.budget, 0, "endless.budget 从 0 起")
    eq(g.endless.bossLevel, 0, "endless.bossLevel 从 0 起")
    eq(g.endless.phase, "warmup", "endless.phase=warmup")
    near(g.endless.timer, 2.0, 1e-9, "warmup 计时 2.0")
    eq(g.endless.runSeed, 12, "opts.seed 生效")
    eq(g.uiRevision, before + 1, "Start 撞一次 uiRevision")

    -- Start：竞技场（12 + seed%3 = 12），字段必须能被 Draw/GetSpawn/GetExit 读
    eq(g.room.layout, 12, "BuildArena 用 seed%3 选图")
    eq(g.room.name, "无尽工位", "房间名")
    eq(g.room.kind, "boss", "房间类型恒 boss")
    eq(g.room.index, 1, "房间 index")
    eq(g.room.cleared, false, "房间未通关（北门常闭）")
    eq(#g.room.next, 0, "没有下一间房")
    eq(#g.rooms, 1, "只留一间房")
    ok(g.room.exit ~= nil and g.room.exit.triggerX == 520, "房间带北门几何")
    ok(g.room.spawn ~= nil and g.room.spawn.x == 520 and g.room.spawn.y == 580, "房间带入 口")
    eq(Game.GetExit(g), g.room.exit, "Game.GetExit 直接返回 g.room.exit")
    local spawn = Game.GetSpawn(g)
    ok(spawn.x == 520 and spawn.y == 580, "出生点 (520,580) 可达不需投影")
    ok(g.navigation ~= nil and g.navigation.obstacles == Campaign.Obstacles(g.room),
        "导航复用 Campaign.layouts 同一张障碍表（不重建）")
    local nav = g.navigation
    ok(Game.GetSpawn(g) ~= nil and g.navigation == nav, "RoomNavigation 不会重建碰撞图")

    -- Start：战斗状态清空 + 血条兜底
    ok(#g.enemies == 0 and #g.shots == 0 and #g.hostileShots == 0, "Start 清空实体")
    ok(#g.gems == 0 and #g.effects == 0 and #g.pools == 0 and #g.particles == 0, "Start 清空特效池")
    eq(g.bossSpawned, false, "Start 后 bossSpawned=false")
    eq(g.bossDefeated, false, "Start 后 bossDefeated=false")
    ok(g.bossMaxHp > 0, "bossMaxHp 不能为 0（main.lua:534 会除它）")
    eq(g.roomCleared, false, "roomCleared=false")
    eq(g.rewardPending, false, "rewardPending=false")
    eq(g.player.x, 520, "玩家复位 x")
    eq(g.player.y, 580, "玩家复位 y")
    near(g.player.invuln, 1.5, 1e-9, "开局 1.5s 无敌")
    eq(g.meleeTimer, 0, "meleeTimer 归零")
    eq(g.staplerTimer, 0, "staplerTimer 归零")
    eq(g.coffeeTimer, 0, "coffeeTimer 归零")
    eq(g.hitStop, 0, "hitStop 归零")
    eq(g.level, 1, "等级从 1 起（不继承）")
    eq(g.xp, 0, "经验清零")
    eq(g.xpNeed, Endless.XpNeed(1), "经验需求换成无尽曲线")
    ok(g.locomotion ~= nil and g.action ~= nil, "ActionState.Reset 已跑")

    -- Update：warmup 2s 后进第 1 波
    Endless.Update(g, 1.0)
    eq(g.endless.phase, "warmup", "warmup 未到点仍等")
    near(g.endless.timer, 1.0, 1e-6, "warmup 倒计时")
    Endless.Update(g, 1.0)
    eq(g.endless.phase, "fighting", "warmup 结束进 fighting")
    eq(g.endless.wave, 1, "TickPhase 推进到第 1 波")
    eq(g.endless.budget, Endless.Count(1), "第 1 波预算 = Count(1)")
    eq(#g.enemies, 0, "TickPhase 本身不刷怪")

    -- TickSpawn：一批刷完、预算清零、批标记还原
    Endless.TickSpawn(g, 0.02)
    eq(#g.enemies, 6, "第 1 波共 6 只")
    eq(g.endless.budget, 0, "预算扣到 0")
    near(g.endless.spawnTimer, require("Difficulty").BatchGap(1), 1e-9, "批间隔随波次递减")
    eq(g.endless.batchIndex, nil, "批末 batchIndex 置 nil")
    eq(g.endless.batchTotal, nil, "批末 batchTotal 置 nil")
    eq(g.enemies[1].hp, 26, "首只满血（HpScale(1)=1）")
    eq(g.enemies[6].hp, 20, "末只吃 75% 衰减（26*0.75）")
    ok(g.enemies[1].hp > g.enemies[6].hp, "同波内血量递减")
    eq(g.enemies[1].damage, 9, "第 1 波伤害不变")
    eq(g.enemies[1].speed, 56, "第 1 波移速不变")

    -- Update：清空后进 bossIntro（第 3 波是 Boss 波，先跳到第 3 波验证）
    g.enemies, g.endless.budget, g.endless.wave = {}, 0, 3
    g.hostileShots = { { x = 0, y = 0, vx = 0, vy = 0, life = 1 } }
    Endless.Update(g, 0.02)
    eq(g.endless.phase, "bossIntro", "第 3 波清完进 bossIntro")
    near(g.endless.timer, 1.5, 1e-9, "Boss 前摇 1.5s")
    eq(#g.hostileShots, 0, "bossIntro 清残留敌弹")

    -- bossIntro 走完 -> SpawnBoss
    Endless.Update(g, 1.6)
    eq(g.endless.phase, "boss", "bossIntro 结束进 boss")
    eq(#g.enemies, 1, "场上有且只有 Boss")
    local boss = g.enemies[1]
    eq(boss.kind, 5, "Boss 用 kind=5")
    eq(boss.hp, 1688, "Boss 实体血量 = BossHp(1,1)")
    eq(boss.maxHp, 1688, "Boss 实体 maxHp 同值")
    eq(g.bossMaxHp, 1688, "血条上限同值（防血条分裂）")
    eq(g.bossHp, 1688, "血条当前值同值")
    eq(g.bossName, "工贼同事", "Boss 名按 kind 轮换")
    eq(g.floor, 3, "SpawnBoss 期间 floor 临时设 3")
    eq(g.bossDefeated, false, "Boss 未死")
    eq(g.bossPhase, 0, "Boss 未进二阶段")
    eq(g.endless.bossSkill, 1, "bossSkill 写入（k=1）")
    near(g.endless.phaseAt, 0.62, 1e-9, "phaseAt 写入（k=1）")

    -- Boss 死亡 -> breather 5s，并把 floor 还原成 1
    g.bossDefeated = true
    g.hostileShots = { { x = 0, y = 0, vx = 0, vy = 0, life = 1 } }
    Endless.Update(g, 0.02)
    eq(g.endless.phase, "breather", "Boss 死后进 breather")
    near(g.endless.timer, 5.0, 1e-9, "Boss 后喘息 5s")
    eq(g.floor, 1, "Boss 死后 floor 还原为 1（否则普通波次伤害翻倍）")
    eq(#g.hostileShots, 0, "Boss 死后清敌弹")

    -- breather 走完进第 4 波（Boss 波不推进 e.wave）
    g.enemies = {}
    Endless.Update(g, 5.1)
    eq(g.endless.phase, "fighting", "breather 结束回 fighting")
    eq(g.endless.wave, 4, "第 3 波 Boss 波不额外推进波次")
    eq(g.endless.budget, Endless.Count(4), "第 4 波预算")

    -- 连锁升级：经验溢出时调 Game.LevelUp（用 pcall 兜住 upgrade 面板）
    eq(g.mode, "playing", "升级前仍在 playing")
    g.xp, g.xpNeed, g.level = 100, 1, 1
    Endless.Update(g, 0.001)
    ok(g.mode == "upgrade" or g.level > 1, "连锁升级被触发")
    eq(g.xpNeed, Endless.XpNeed(g.level), "升级后换无尽经验曲线")

    -- LEVEL_CAP：到顶后不再升级
    g.mode, g.level, g.xp, g.xpNeed = "playing", Endless.LEVEL_CAP, 999999, 1
    local levelBefore = g.level
    Endless.Update(g, 0.001)
    eq(g.level, levelBefore, "到 LEVEL_CAP 后不再升级")
end

-- ------------------------------------------------------------------ ③ 结算与榜单条目
local function ResultChecks()
    local g = Game.New("male")
    Endless.Start(g, { seed = 13 })
    eq(g.room.layout, 13, "seed=13 选到 13 号图")
    g.endless.wave, g.endless.bossLevel = 30, 10
    g.kills, g.level, g.time = 1341, 32, 2160
    g.nickDraft = "OLD"

    local r = Endless.OnDeath(g)
    ok(type(r) == "table", "OnDeath 返回 result 表")
    eq(r.score, 68852, "结算分数与 Score 公式一致")
    eq(r.wave, 30, "result.wave")
    eq(r.boss, 10, "result.boss")
    eq(r.kills, 1341, "result.kills")
    eq(r.level, 32, "result.level")
    eq(r.time, 2160, "result.time 取整秒")
    ok(type(r.ts) == "number", "result.ts 是数字（无 os 时为 0）")
    eq(g.endless.active, false, "结算后 active=false")
    eq(g.endless.result, r, "result 挂在 g.endless.result")
    eq(g.nickDraft, "", "结算后昵称草稿被清空")
    ok(g.endless.best >= r.score, "best 记录本局最高分")

    -- 幂等：再调一次不改写快照
    g.time = 3000
    local again = Endless.OnDeath(g)
    eq(again, r, "OnDeath 幂等（返回同一张快照）")
    eq(again.score, 68852, "幂等时不重算分数")

    -- BuildEntry：8 字段 + 编码顺序
    local entry = Endless.BuildEntry(g, "WORKER01")
    eq(entry.name, "WORKER01", "BuildEntry.name")
    eq(entry.score, 68852, "BuildEntry.score")
    eq(entry.wave, 30, "BuildEntry.wave")
    eq(entry.boss, 10, "BuildEntry.boss")
    eq(entry.level, 32, "BuildEntry.level")
    eq(entry.kills, 1341, "BuildEntry.kills")
    eq(entry.time, 2160, "BuildEntry.time")
    ok(type(entry.ts) == "number", "BuildEntry.ts")
    eq(Endless.BuildEntry(g).name, g.nickDraft, "BuildEntry 缺省用 nickDraft")

    -- 主动下班（未阵亡）：同样产出可提交的条目
    local h = Game.New("female")
    Endless.Start(h, { seed = 14 })
    eq(h.room.layout, 14, "seed=14 选到 14 号图")
    h.endless.wave, h.endless.bossLevel = 5, 1
    h.kills, h.level, h.time = 56, 5, 360
    local entry2 = Endless.BuildEntry(h, "NIGHT")
    eq(entry2.score, 8452, "主动下班也能算分")
    eq(entry2.time, 360, "时间向下取整")
    -- Score 用原始秒数（3*360.8=1082.4 -> floor），time 字段才取整：两者刻意不同
    local f = Game.New("female")
    Endless.Start(f, { seed = 15 })
    f.endless.wave, f.endless.bossLevel = 5, 1
    f.kills, f.level, f.time = 56, 5, 360.8
    eq(Endless.Score(f), 8454, "Score 用未取整的秒数")
    eq(Endless.BuildEntry(f, "NIGHT").time, 360, "条目里的时间取整秒")
    eq(h.endless.active, false, "BuildEntry 触发结算后 active=false")
end

-- ------------------------------------------------------------------ 入口
function M.Run()
    pass, fail = 0, 0
    CurveChecks()
    StateChecks()
    ResultChecks()
    print(string.format("[EndlessCurve] %d passed, %d failed", pass, fail))
    if fail > 0 then error(string.format("EndlessCurve: %d assertions failed", fail), 0) end
    if pass < 60 then error(string.format("EndlessCurve: 断言数 %d 少于 60", pass), 0) end
    return true
end

local function Start() return M.Run() end
M.Start = Start

return M
