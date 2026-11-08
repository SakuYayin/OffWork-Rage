-- 《下班！别拦我》：无尽模式 + 积分。
-- 设计依据：docs/design/05-endless-leaderboard.md §2.1-§2.8。本文件实现该设计里全部「模型层」：
-- 曲线公式、Boss 轮换、波次状态机、分批刷怪、结算与榜单条目；调用方是 Game.lua 的 P1-P7
-- 七处补丁（Game.Spawn / LevelUp / Update / Hit / TakeDamage）与 main.lua 的结算面板。
--
-- 新平衡规则（2026-11-07，旧成绩由balanceVersion隔离）：
-- Count(w) = min(60,floor(4+2.2w+.1w²)); 每批≤12，同屏17→45，批间隔1.35→.65s。
-- HpScale(w) = 1+.24(w-1)+.016(w-1)²；DmgScale(w)=min(3.6,1+.095(w-1))。
-- SpdScale(w)=1+min(.40,.024(w-1))；不再叠加旧版按游戏时长的1.35倍加速。
-- BossHp(i,k)=round(1350*(1+.38(k-1)+min(16,.012(k-1)²))*HEROISM[i])。
-- Difficulty模块还提供护甲、护盾、精英、恢复与经验递减，避免仅靠数量制造难度。
-- 分数/升级经验需求/Boss技能等级公式保持原样，实际回报和作战压力已改变。
--
-- 【状态机】唯一推进 e.wave 的地方是 TickPhase；Boss 波不推进 e.wave，这样
-- BossFor(floor(w/3)) 永远与波次对齐（第 3 波 k=1、第 6 波 k=2 ……）。
--
--   warmup(2.0) ─► fighting ──budget==0 且 #enemies==0──┬─ wave%3==0 ─► bossIntro(1.5s) ─► boss
--                    ▲                                  └─ 否则 ──────► breather(3.0s) ◄──┐
--                    └───────────────── timer 归零 ◄────────────────────────────────────┘
--   boss ──bossDefeated──► breather(5.0s)        （boss 阶段本身由 Game.UpdateBoss 驱动）
--
-- 【依赖注入】本模块**不得** require("Game"/"Navigation"/"Campaign"/"ActionState")：
-- Game.lua:10 已经 require("Endless")，反向 require 会成环（Lua 会把半张表塞回 package.loaded）。
-- 需要时一律走 package.loaded 惰性取，并且允许取不到（纯 Lua 测试、未来裁剪）——取不到就降级
-- 跳过该步骤，绝不让调用方因为一个可选依赖缺失而崩。
--
-- 【fengari 约束】VM 里 integer 是 32 位：任何可能超过 2^31 的中间值都要混浮点，这里统一用
-- 加 0.0 或 math.floor(n + 0.0) 把结果钉成 double，避免大分数被静默截断；os/io 不保证存在，
-- 凡用到 os.time 的地方都先做 type 检查。
local Endless = {}
local Difficulty=require("Difficulty")

-- ------------------------------------------------------------------ 依赖
-- 惰性取宿主模块。key 一律用字符串下标，不做缓存：require 期间 Game 尚未注册，
-- 而运行期 Game 一定已注册，缓存反而会把「启动时为空」这件事记一辈子。
---@return table
local function deps()
    return {
        Game = package.loaded["Game"],
        Navigation = package.loaded["Navigation"],
        Campaign = package.loaded["Campaign"],
        ActionState = package.loaded["ActionState"],
        Leaderboard = package.loaded["Leaderboard"],
    }
end

-- ------------------------------------------------------------------ 常量
-- 同屏软上限 45：低于 Game.Spawn 的硬顶 70，给 Boss 召唤的小怪留出空间。
Endless.MAX_ONSCREEN = 45
-- 一批 12 只、批间隔 1.2s：避免一帧内生成 60 只把 EnemyNeighborhood.Build 拖到掉帧。
Endless.BATCH_SIZE = 12
Endless.BATCH_INTERVAL = 1.2
-- 每 3 波一个 Boss。
Endless.BOSS_EVERY = 3
-- 等级硬上限：34 只是 BUFF 池被抽干的位置，等级本身继续累加（40*level 分数项仍生效）。
Endless.LEVEL_CAP = 99

-- 三位旧首领的「主角光环」系数：工贼 1.25 / 主管 1.00 / 老板 1.15。
-- 主管基准血量本来就低，靠弹幕密度与召唤弥补，所以每轮循环的峰值落在老板、谷值落在主管。
local HEROISM = { 1.25, 1.00, 1.15 }
-- 与 Campaign.floors[i].boss 同名，Game.lua:239 会拿它拼播报文案。
local BOSS_NAMES = { "工贼同事", "秃头主管", "没良心老板" }
-- Boss 弹幕增量：技能等级 1..5 -> 增发弹数（0/4/8/12/16）。
-- Game.lua:675-677 的 EnemyImpact 直接按 skill 索引这张表，改长度会越界。
local VOLLEY_BONUS = { 0, 4, 8, 12, 16 }

Endless.HEROISM = HEROISM
Endless.BOSS_NAMES = BOSS_NAMES
Endless.VOLLEY_BONUS = VOLLEY_BONUS

-- ================================================================== 纯函数
-- 本波总数量。第 16 波触顶 60：此后难度只由血量/伤害/移速/Boss 等级推进。
-- 不加量是刻意的——Game.Spawn 硬顶 70、敌弹上限 110，继续加只会互相挤死。
---@param wave integer
---@return integer
function Endless.Count(wave) return math.min(60, math.floor(4 + 2.2 * wave + 0.1 * wave * wave)) end

-- 血量按二次曲线成长；密度和速度单独封顶，避免靠无限刷怪堆压力。
---@param wave integer
---@return number
function Endless.HpScale(wave) return 1 + 0.24 * (wave - 1) + 0.016 * (wave - 1) * (wave - 1) end

-- 伤害倍率第29波封顶3.6x；精英另外乘1.15，实战触发仍有预警。
---@param wave integer
---@return number
function Endless.DmgScale(wave) return math.min(3.6, 1 + 0.095 * (wave - 1)) end

-- 移速倍率第18波封顶1.40x；不叠加旧版按游戏时长的加速。
---@param wave integer
---@return number
function Endless.SpdScale(wave) return 1 + math.min(0.40, 0.024 * (wave - 1)) end

-- 升级所需经验。二次项在低级几乎无感，越到后期越陡：L1 22 / L30 627 / L99 4432。
---@param level integer
---@return integer
function Endless.XpNeed(level) return 12 + 10 * level + math.floor(0.35 * level * level) end

-- 同波内衰减：一批里越晚刷出的怪血量越低（首只 100%、末只 75%），避免「最后 12 只全是满血精英」。
-- 只作用于 hp，不作用于伤害与移速——伤害必须可预测。
-- total<=1 或 i 越界时返回 1.0（TickSpawn 在批末会把 batchIndex/batchTotal 置 nil，
-- Game.Spawn 用 or 1 兜底，两条路径都必须安全）。
---@param indexInWave integer?
---@param totalInWave integer?
---@return number
function Endless.BatchHpMul(indexInWave, totalInWave)
    if not totalInWave or totalInWave <= 1 then return 1.0 end
    local i = indexInWave or 1
    if i < 1 then i = 1 end
    if i > totalInWave then i = totalInWave end
    return 1.0 - 0.25 * ((i - 1) / (totalInWave - 1))
end

-- 同角色血量单调成长；不同角色有HEROISM系数，轮换仍保留强弱锯齿。
-- 新版基准1350、线性.38、二次.012（仅二次项封顶16），与旧榜隔离。
---@param idx integer 1=工贼 2=主管 3=老板
---@param k integer 第几个 Boss，从 1 起
---@return integer
function Endless.BossHp(idx, k)
    if not k or k < 1 then k = 1 end
    if not idx or idx < 1 or idx > 3 then idx = 1 end
    local base = 1 + 0.38 * (k - 1) + math.min(16.0, 0.012 * (k - 1) * (k - 1) + 0.0)
    return math.floor(1350 * base * HEROISM[idx] + 0.5)
end

-- 技能等级 1..5，每 2 个 Boss 升 1 级，第 9 个 Boss 起封顶。
-- Game.lua:711 用它算冲刺 CD（1.35 - 0.10*(skill-1)），:675 用它算弹幕附加发数。
---@param k integer
---@return integer
function Endless.BossSkill(k) return math.min(5, 1 + math.floor(((k or 1) - 1) / 2)) end

-- 二阶段阈值（血量比例）。原版硬编码 0.5，无尽让 Boss 越来越早狂暴：
-- 第 1 个 62% 血就进二阶段，第 9 个起 35% 血进入，玩家在压到最后 1/3 时要面对满强度技能。
---@param k integer
---@return number
function Endless.BossPhaseAt(k) return math.max(0.35, 0.62 - 0.04 * ((k or 1) - 1)) end

-- 这一波该出哪个 Boss。k = floor(wave/3)：wave 3/6/9 -> k=1/2/3，wave 1~2 返回 nil。
-- 因为 TickPhase 在 Boss 波不推进 e.wave，BossFor 的输入永远停在 3 的倍数上。
---@param wave integer
---@return table? nil 表示这一波不是 Boss 波
function Endless.BossFor(wave)
    local k = math.floor((wave or 0) / Endless.BOSS_EVERY)
    if k < 1 then return nil end
    local idx = (k - 1) % 3 + 1
    return {
        kind = idx,
        k = k,
        hp = Endless.BossHp(idx, k),
        skill = Endless.BossSkill(k),
        phaseAt = Endless.BossPhaseAt(k),
        name = BOSS_NAMES[idx],
        wave = k * Endless.BOSS_EVERY,
    }
end

-- ------------------------------------------------------------------ 怪物种类池
-- 五档累积权重表：1~2波保留单一入门怪；3波起引入冲撞与弹幕。
-- 10波起加入护盾与召唤，第15波起新怪总权重70%，九种普通怪均可随机出现。
-- 每行最后一档上界1.00，最终math.huge兜底。
local POOL = {
    { 2, { { 1.00, 1 } } },
    { 5, { { .30,1 },{ .55,2 },{ .70,3 },{ .85,6 },{ 1,7 } } },
    { 9, { { .16,1 },{ .32,2 },{ .44,3 },{ .50,4 },{ .67,6 },{ .84,7 },{ 1,11 } } },
    { 14, { { .10,1 },{ .20,2 },{ .30,3 },{ .36,4 },{ .53,6 },{ .70,7 },{ .84,11 },{ .94,12 },{ 1,13 } } },
    { math.huge, { { .08,1 },{ .16,2 },{ .24,3 },{ .30,4 },{ .47,6 },{ .64,7 },{ .78,11 },{ .90,12 },{ 1,13 } } },
}
Endless.POOL = POOL

---@param wave integer
---@return integer kind 1..4
function Endless.PickKind(wave)
    local w = wave or 1
    local r = math.random()
    for _, row in ipairs(POOL) do
        if w <= row[1] then
            for _, b in ipairs(row[2]) do
                if r < b[1] then return b[2] end
            end
            return row[2][#row[2]][2]
        end
    end
    return 1
end

-- ================================================================== 分数
-- 双调用约定（两条都被调用方使用，签名不得收敛成一种）：
--   Endless.Score(g)                                —— main.lua:307 / OnDeath 里用整张状态表
--   Endless.Score(wave, kills, level, boss, secs)   —— 测试与离线演算用裸数字
-- 波次是绝对主项（第 30 波一局 43.6%），Boss 与击杀次之，等级几乎不影响（防刷级），
-- 时间只占 9.4% 且有 3600s 封顶（防挂机刷时）。
---@param a table|integer 状态表 g，或波次
---@param b integer? 击杀
---@param c integer? 等级
---@param d integer? 已杀 Boss 数
---@param e number? 秒
---@return integer
function Endless.Score(a, b, c, d, e)
    local wave, kills, level, boss, secs
    if type(a) == "table" then
        local g = a
        local en = g.endless or {}
        wave = en.wave or 0
        boss = en.bossLevel or 0
        kills = g.kills or 0
        level = g.level or 1
        secs = g.time or 0
    else
        wave, kills, level, boss, secs = a or 0, b or 0, c or 1, d or 0, e or 0
    end
    if secs > 3600 then secs = 3600 end
    if secs < 0 then secs = 0 end
    local n = 1000 * wave + 1500 * boss + 12 * kills + 40 * level + 3 * secs
    return math.floor(n + 0.0)
end

-- ================================================================== 场地
-- 「地图全程不动」：只在开局建一次房间表，之后 Update 再也不碰 g.room / g.navigation。
-- 用 Campaign.layouts[12..14]（三张首领掩体场）轮换，理由：
--   ① 中轴 x∈[360,680] 无遮挡，是 14 张布局里唯一为「大体积 Boss + 召唤小怪」设计的开阔区；
--   ② 四周留出 112 宽门洞的环绕走道，贴合 BOUNDS = {48,992,142,628}；
--   ③ 没有工位矩阵那种家具密集区，45~60 只怪不会卡在桌椅缝里；
--   ④ 三张轮换避免每局视觉雷同。
-- 字段对齐 Campaign.Build 产出的 CampaignRoom（只多不少），因为 Game.GetSpawn/GetExit、
-- Draw.Background、CampaignUI 都按这套字段读：
--   exit  —— Game.lua:90 无尽分支直接 return g.room.exit（缺了 Draw 每帧崩）；
--   spawn —— Game.GetSpawn 的投影源，必须是 (520,580) 这个三张图都可达的点；
--   layoutName —— Draw.lua:133 世界左下角的房间名牌。
---@param g table
---@return table
function Endless.BuildArena(g)
    local seed = (g.endless and g.endless.runSeed) or 1
    local idx = 12 + (seed % 3)
    local d = deps()
    local layoutName = "无尽工位"
    if d.Campaign and d.Campaign.layoutNames and d.Campaign.layoutNames[idx] then
        layoutName = d.Campaign.layoutNames[idx]
    end
    return {
        index = 1,
        layout = idx,
        layoutName = layoutName,
        kind = "boss",
        name = "无尽工位",
        cleared = false,
        rewardPending = false,
        next = {},
        visited = true,
        spawn = { x = 520, y = 580 },
        -- 北门保留几何但不存在于运行时：无尽模式没有「出口」这个概念，
        -- Game.GetExit 直接返回它、永不参与可达判定；Draw 按 roomCleared==false 画成常闭门。
        exit = { x = 464, y = 14, w = 112, h = 160, triggerX = 520, triggerY = 174,
            radius = 30, side = "north", clearance = 96 },
    }
end

-- ================================================================== 开局
-- 不进 Game.EnterRoom（Game.lua:246）的三条理由：
--   ① 它按房间种类预建导航并直接 Game.Spawn(g,5,520,230) 放 Boss —— 第 1 波不该有 Boss；
--   ② 它用 Campaign.floors[g.floor].hp 覆写 bossMaxHp —— 与 Endless.BossHp 冲突；
--   ③ 它每次都 Navigation.New 重建碰撞图 —— 与「地图全程不动」矛盾，还会丢掉已建好的
--      视线缓存（{4,24} 两档预建约 30 ms）。
-- 代价是这十几行重置逻辑重复了一遍；收益是原函数一个字不改，19 套既有测试零风险。
---@param g table
---@param opts table? { seed = number }
---@return table g.endless
function Endless.Start(g, opts)
    opts = opts or {}
    g.mode, g.floor, g.roomsCleared = "playing", 1, 0
    g.endless = {
        active = true,
        wave = 0,           -- 当前波次（唯一推进点是 TickPhase）
        budget = 0,         -- 本波尚未刷出的数量
        bossLevel = 0,      -- 已击杀 Boss 数（分数项；Boss 波进行中不递增）
        bossSkill = 1,      -- 1..5，Game.UpdateBoss/EnemyImpact 直接读
        phaseAt = 0.5,      -- 二阶段阈值，SpawnBoss 时被 BossFor 覆写
        phase = "warmup",
        timer = 2.0,        -- 开局 2s 让玩家看清地图
        spawnTimer = 0,
        runSeed = opts.seed or math.random(1, 99999),
        best = 0,           -- 本局最高分（OnDeath 里更新，跨局不持久化）
        result = nil,       -- OnDeath 写入的结算快照
    }

    g.room = Endless.BuildArena(g)
    g.rooms = { g.room }     -- 只留一间：OpenRoute/Travel 永远找不到下一间
    g.roomIndex = 1

    -- 导航只建一次。Campaign.Obstacles 返回的是 Campaign.layouts[idx] 这张表的**同一引用**，
    -- 所以之后 Game.RoomNavigation 的 obstacles 身份比较恒为 false，不会重建。
    local d = deps()
    g.navigation = nil
    g.spawnNavigation, g.spawnRoom = nil, nil
    g.exitNavigation, g.exitRoom = nil, nil
    if d.Navigation and d.Campaign and d.Campaign.Obstacles then
        local ok, nav = pcall(d.Navigation.New, d.Campaign.Obstacles(g.room))
        if ok and nav then
            g.navigation = nav
            -- 与 Game.EnterRoom 里 boss 房同样的两档预建：玩家 r12 与 Boss r24。
            for _, radius in ipairs({ 4, 24 }) do pcall(d.Navigation.Graph, nav, radius) end
        end
    end

    g.roomCleared, g.rewardPending = false, false
    g.enemies, g.shots, g.hostileShots = {}, {}, {}
    g.pools, g.gems, g.effects, g.particles, g.defeated = {}, {}, {}, {}, {}
    g.bossSpawned, g.bossDefeated = false, false
    g.bossPhase, g.bossAttack, g.dashTimer = 0, 0, 0
    -- 血条兜底：main.lua:534 每帧算 bossHp/bossMaxHp，bossMaxHp 为 0 会画出 NaN。
    g.bossName, g.bossHp, g.bossMaxHp, g.bossTimer = "无尽工位", 0, 1, 3
    if g.player then
        g.player.x, g.player.y = 520, 580
        g.player.invuln = 1.5
    end
    g.meleeTimer, g.staplerTimer, g.coffeeTimer, g.hitStop = 0, 0, 0, 0
    -- 等级不继承：从 1 级起（§2.6）。Game.New 给的是 xpNeed = 10 的普通曲线，
    -- 无尽曲线第 1 级是 22，必须在这里换掉，否则第一只怪就能升级。
    g.level, g.xp = 1, 0
    g.xpNeed = Endless.XpNeed(1)
    -- 纯本局统计，重开一局必须从 0 起（Score 直接读 kills/time）。
    g.kills, g.time = 0, 0
    g.combo, g.comboTimer = 0, 0

    if d.ActionState and d.ActionState.Reset then pcall(d.ActionState.Reset, g) end
    local fufu=package.loaded["FufuCombat"]
    if fufu and g.heroId=="fufu"then fufu.Init(g,true);fufu.OnRoom(g)end
    g.uiRevision = (g.uiRevision or 0) + 1
    print(string.format("[无尽] 开局 seed=%s layout=%d 等级=%d 经验需求=%d",
        tostring(g.endless.runSeed), g.room.layout, g.level, g.xpNeed))
    return g.endless
end

-- ================================================================== 状态机
-- 唯一推进 e.wave 的地方。warmup/breather -> 开新波；bossIntro -> 放 Boss 并切 boss。
---@param g table
function Endless.TickPhase(g)
    local e = g.endless
    if not e then return end
    if e.phase == "bossIntro" then
        Endless.SpawnBoss(g)
        e.phase = "boss"
        return
    end
    e.wave = e.wave + 1
    e.budget, e.spawnTimer, e.phase = Endless.Count(e.wave), 0, "fighting"
    -- 批末清空，避免上一波残留的 batchTotal 影响 Game.Spawn 的血量衰减。
    e.batchIndex, e.batchTotal = nil, nil
    print(string.format("[无尽] 第 %d 波 预算 %d", e.wave, e.budget))
end

-- 主循环。插入点是 Game.Update 的 P3（g.time 累加之前），所以这里读到的时间还没被本帧推进。
-- 连锁升级必须放最后：Boss 击杀会白送一级（P5 里 g.xp = g.xp + g.xpNeed），一波清完可能
-- 同帧跨 2~3 级；Game.Choose 末尾不递归判级，只有这里能把它逐级消化掉。
---@param g table
---@param dt number
function Endless.Update(g, dt)
    local e = g.endless
    if not e or not e.active then return end

    -- warmup / breather / bossIntro：只走倒计时，不刷怪、不判波次。
    if e.phase ~= "fighting" and e.phase ~= "boss" then
        e.timer = (e.timer or 0) - dt
        if e.timer <= 0 then Endless.TickPhase(g) end
        return
    end

    -- boss：战果由 Game.UpdateBoss 写进 g.bossDefeated，这里只负责收尾。
    if e.phase == "boss" then
        if g.bossDefeated then
            local fufu=package.loaded["FufuCombat"]
            if fufu then fufu.Cleared(g)end
            -- g.floor 在 SpawnBoss 里被临时改成 3（骗过 Spawn 的 boss 血量分支与 UpdateBoss
            -- 的弹幕形态）。Game.lua:361 的 P5 已经还原过一次，这里再兜一次：
            -- 普通波次的 Game.Spawn 会用 g.floor 算 scale/damage，残留 3 会让第 4 波直接翻倍。
            g.floor = 1
            e.phase, e.timer, g.hostileShots = "breather", 5.0, {}
        end
        return
    end

    Endless.TickSpawn(g, dt)
    if (e.budget or 0) <= 0 and #g.enemies == 0 then
        local fufu=package.loaded["FufuCombat"]
        if fufu then fufu.Cleared(g)end
        e.phase = (e.wave % Endless.BOSS_EVERY == 0) and "bossIntro" or "breather"
        e.timer = (e.phase == "bossIntro") and 1.5 or 3.0
        -- Boss 登场前清掉残留敌弹：前摇 1.5s 里被屏幕外的旧弹打死体验极差。
        if e.phase == "bossIntro" then g.hostileShots = {} end
    end

    if g.mode == "playing" and g.xp >= g.xpNeed and g.level < Endless.LEVEL_CAP then
        local Game = deps().Game
        if Game and Game.LevelUp then Game.LevelUp(g, "level") end
    end
end

-- ================================================================== 刷怪
-- 分批刷新：每批最多 BATCH_SIZE 只、批间隔 BATCH_INTERVAL 秒，同屏不超过 MAX_ONSCREEN。
-- batchIndex/batchTotal 在每只怪刷出前设一次，批末置 nil —— Game.Spawn 的 P2 分支用
-- or 1 兜底读它们算 BatchHpMul，所以置 nil 比留着旧值更安全（旧值会让下一批全体吃到衰减）。
---@param g table
---@param dt number
function Endless.TickSpawn(g, dt)
    local e = g.endless
    if not e or not e.active then return end
    e.spawnTimer = (e.spawnTimer or 0) - dt
    local cap=math.min(Endless.MAX_ONSCREEN,Difficulty.AliveCap(e.wave or 1))
    if (e.budget or 0) <= 0 or e.spawnTimer > 0 or #g.enemies >= cap then return end
    local Game = deps().Game
    if not Game or not Game.Spawn then return end
    local n = math.min(Endless.BATCH_SIZE, e.budget, cap - #g.enemies)
    if n <= 0 then return end
    for i = 1, n do
        e.batchIndex, e.batchTotal = i, n
        Game.Spawn(g, Endless.PickKind(e.wave))   -- 内部 70 硬顶 / 投影失败会返回 nil
    end
    e.batchIndex, e.batchTotal = nil, nil
    -- 即便个别 Spawn 返回 nil 也照扣预算：宁可本波总量略少，也不能让预算卡住不动。
    e.budget = e.budget - n
    e.spawnTimer = Difficulty.BatchGap(e.wave or 1)
end

-- ================================================================== 首领
-- 放 Boss 并覆写四处血量。必须同时改 boss.hp / boss.maxHp / g.bossMaxHp / g.bossHp：
-- Game.Spawn 的 boss 分支（Game.lua:222/238）是从 Campaign.floors[g.floor].hp 拷出来的
-- 同一个值，只改全局字段会得到「血条 6449 / 实体 1800」的分裂状态——Boss 秒死但血条不动。
-- 场地floor暂设3只用于几何与基础数据；bossFloor独立绑定身份，模型与攻击不再串号。
---@param g table
function Endless.SpawnBoss(g)
    local e = g.endless
    if not e then return end
    local b = Endless.BossFor(e.wave)
    if not b then return end
    e.bossSkill, e.phaseAt = b.skill, b.phaseAt
    g.bossDefeated, g.bossPhase, g.hostileShots = false, 0, {}
    g.floor = 3
    g.bossName = BOSS_NAMES[b.kind]     -- Spawn 里会拼 "名字：Campaign.floors[3].subtitle"
    local Game = deps().Game
    if not Game or not Game.Spawn then
        g.floor, g.bossDefeated = 1, true
        return
    end
    local boss = Game.Spawn(g, 5, 520, 230,b.kind)
    if not boss then
        -- 70 硬顶或投影失败：跳过这个 Boss，否则 e.phase 会永远停在 boss。
        print("[无尽] Boss 生成失败，跳过本个首领")
        g.floor, g.bossDefeated = 1, true
        return
    end
    boss.hp, boss.maxHp = b.hp, b.hp
    boss.damage=math.floor(19*Endless.DmgScale(e.wave)+.5)
    boss.speed=46*Endless.SpdScale(e.wave)
    boss.bossFloor,boss.bossIdentity=b.kind,b.kind
    -- Entity identity drives both its atlas and attack patterns; arena floor is geometry only.
    boss.armor=Difficulty.Armor(e.wave)
    boss.shieldMax=math.floor(b.hp*Difficulty.ShieldRatio(e.wave));boss.shield=boss.shieldMax
    g.bossMaxHp, g.bossHp, g.bossTimer = b.hp, b.hp, 2.6
    if Game.Announce then Game.Announce(g, g.bossName .. " Lv." .. b.skill .. " 登场", 3) end
    print(string.format("[无尽] Boss k=%d %s hp=%d skill=%d 阈值=%.2f",
        b.k, g.bossName, b.hp, b.skill, b.phaseAt))
end

-- ================================================================== 结算
-- 阵亡（Game.TakeDamage 的 deathHook）与「主动下班」（main.lua:476）都走这里。
-- 幂等：第二次调用不重算，直接返回上一次的快照（避免暂停菜单里连点两次改写时间戳）。
---@param g table
---@return table?
function Endless.OnDeath(g)
    local e = g.endless
    if not e then return nil end
    if e.result then
        e.active = false
        return e.result
    end
    -- fengari 不保证有 os 库：拿不到时间戳就写 0，Leaderboard.Store.Submit 会自己补。
    local now = 0
    if type(os) == "table" and type(os.time) == "function" then now = os.time() end
    e.result = {
        score = Endless.Score(g),
        wave = e.wave or 0,
        boss = e.bossLevel or 0,
        kills = g.kills or 0,
        level = g.level or 1,
        time = math.floor((g.time or 0) + 0.0),   -- 秒；结算面板按 mm:ss 显示
        ts = now,
    }
    e.active = false
    g.nickDraft = ""
    -- 昵称从排行榜适配层回填；Leaderboard.lua 还是空壳时必须静默跳过（不能 pcall 失败就崩）。
    local LB = deps().Leaderboard
    if LB and type(LB.GetName) == "function" then
        local ok, name = pcall(LB.GetName)
        if ok and type(name) == "string" then g.nickDraft = name end
    end
    if e.result.score > (e.best or 0) then e.best = e.result.score end
    print(string.format("[无尽] 结算 波次=%d 首领=%d 等级=%d 击杀=%d 用时=%d 分数=%d",
        e.result.wave, e.result.boss, e.result.level, e.result.kills, e.result.time, e.result.score))
    return e.result
end

-- 排行榜条目：8 个字段与 Leaderboard.Encode 的顺序一一对应
-- （name|score|wave|boss|level|kills|time|ts;）。缺字段时逐项回落到 g 的当前值，
-- 这样即便 OnDeath 没跑（例如热重载后直接结算）也能提交出一个合法条目。
---@param g table
---@param name string?
---@return table
function Endless.BuildEntry(g, name)
    local e = g.endless
    local r = (e and e.result) or Endless.OnDeath(g) or {}
    local nm = name
    if nm == nil then nm = g.nickDraft or "" end
    return {
        name = nm,
        score = r.score or Endless.Score(g),
        wave = r.wave or (e and e.wave) or 0,
        boss = r.boss or (e and e.bossLevel) or 0,
        level = r.level or g.level or 1,
        kills = r.kills or g.kills or 0,
        time = r.time or math.floor((g.time or 0) + 0.0),
        ts = r.ts or 0,
    }
end

return Endless
