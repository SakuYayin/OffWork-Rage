-- 《下班！别拦我》：独立于渲染的单机玩法逻辑。
local Campaign = require("Campaign")
local Heroes = require("Heroes")
local Navigation = require("Navigation")
local ActionState = require("ActionState")
local EnemyAnimation = require("EnemyAnimation")
local EnemyNeighborhood = require("EnemyNeighborhood")
local Dungeon = require("Dungeon")
local Events = require("Events")
local Endless = require("Endless")
local Weapons = require("Weapons")
local Buffs = require("Buffs")
local Enemies = require("Enemies")
local BossPhases = require("BossPhases")
local Loadout = require("Loadout")
local Difficulty=require("Difficulty")
local Scaling=require("HeroScaling")
local Fufu=require("FufuCombat")
local Game = {}
Game.heroes = Heroes
Game.WIDTH, Game.HEIGHT = 1040, 680
Game.campaign = Campaign

local function Distance(ax, ay, bx, by)
    local x, y = ax - bx, ay - by
    return math.sqrt(x * x + y * y)
end
local function Direction(ax, ay, bx, by)
    local d = math.max(0.001, Distance(ax, ay, bx, by))
    return (bx - ax) / d, (by - ay) / d, d
end
Game.Distance = Distance
-- Every recovery source shares the wave penalty, including items and passive leech.
function Game.Heal(g,amount)
    local p=g.player
    local healed=math.max(0,math.min(p.maxHp-p.hp,amount*Difficulty.HealMul(Difficulty.Wave(g))))
    p.hp=p.hp+healed
    return healed
end

-- 碰撞尺寸/边界ASCII设计见Navigation.lua与Campaign.lua。这里仅管理玩法：
-- 所有kind实体共用障碍数组；移动、投射物、近战、咖啡/经验吸取均不能穿墙。
-- 房间来源唯一入口：开关关着时走 Campaign.Build，与原版逐字节一致。
-- Dungeon.USE_DUNGEON 由 07-halved-plan.md S4 阶段在验收后翻 true。
local function BuildRooms(floor)
    if Dungeon.USE_DUNGEON then
        -- 每局换种子：同层每次不一样，但生成是可复现的（seed 会打印出来供报告）。
        local seed = Dungeon.RandomSeed and Dungeon.RandomSeed(floor) or nil
        local ok, rooms = pcall(Dungeon.Generate, floor, seed)
        if ok and rooms then return rooms end
        print("[地牢] 生成失败，回退手工布局：" .. tostring(rooms))
    end
    return Campaign.Build(floor)
end
Game.BuildRooms = BuildRooms

-- 死亡钩子：main.lua 启动时注入 Endless.OnDeath（模块级变量，避免 Game<->Endless 循环 require）。
Game.deathHook = nil

Game.desks = Campaign.layouts[1]
---@param g table
---@return table[]
function Game.GetDesks(g) return Campaign.Desks(g.room) end
Game.GetObstacles = Game.GetDesks

local function RoomNavigation(g)
    local obstacles = Game.GetObstacles(g)
    if not g.navigation or g.navigation.obstacles ~= obstacles then g.navigation = Navigation.New(obstacles) end
    return g.navigation
end

---@param g table
---@return table
function Game.GetSpawn(g)
    local spawn, nav = g.room.spawn, RoomNavigation(g)
    if g.spawnNavigation == nav and g.spawnRoom == g.room then return spawn end
    local x, y = Navigation.Project(nav, spawn.x, spawn.y, 12, spawn.x, spawn.y)
    assert(x and y, "房间没有可达的玩家入口")
    if x ~= spawn.x or y ~= spawn.y then
        print(string.format("[入口安全投影] F%d-%d (%.0f,%.0f) -> (%.0f,%.0f)",
            g.floor, g.roomIndex, spawn.x, spawn.y, x, y))
        spawn.x, spawn.y = x, y
    end
    g.spawnNavigation, g.spawnRoom = nav, g.room
    return spawn
end

-- 北门净空设计：框宽112，内门洞96，玩家圆r12；采样圆心横跨[-36,+36]。
--       [visual x ................. x+w]
--       +----------triggerY / y+h---------+  <- 阈值与门底边同一条线
--       |   o<------96净空------>o       |  r12脚下检测，不检测角色头部
--       +---------向南48接近区-----------+
-- 擦边、柜间与首领房沿用同一Blocked/Project，不让触发器穿墙吸附。
local function ExitClear(nav, x, y)
    for dy = 0, 48, 8 do
        for dx = -36, 36, 12 do
            if Navigation.Blocked(nav, x + dx, y + dy, 12) then return false end
        end
    end
    return true
end

---@param g table
---@return CampaignExit
function Game.GetExit(g)
    -- 无尽工位的北门是「焊死」的：不出现在可达判定里，视觉仍由 Draw 画成常闭门。
    if g.endless and g.endless.active then return g.room.exit end
    local nav, exit = RoomNavigation(g), g.room.exit
    if g.exitNavigation == nav and g.exitRoom == g.room then return exit end
    local spawn = Game.GetSpawn(g)
    local function Reachable(x, y)
        if not ExitClear(nav, x, y) then return false end
        local safeX, safeY = Navigation.Project(nav, x, y, 12, spawn.x, spawn.y)
        return safeX == x and safeY == y
    end
    if not Reachable(exit.triggerX, exit.triggerY) then
        local thresholdY = Navigation.BOUNDS.top + 32
        local found = false
        for _, x in ipairs({ 520, 440, 600, 340, 700, 240, 800, 140, 900 }) do
            if Reachable(x, thresholdY) then
                print(string.format("[出口安全投影] F%d-%d (%.0f,%.0f) -> (%.0f,%.0f)",
                    g.floor, g.roomIndex, exit.triggerX, exit.triggerY, x, thresholdY))
                exit.triggerX, exit.triggerY, found = x, thresholdY, true
                break
            end
        end
        assert(found, "北侧没有96宽且与入口连通的安全门洞")
    end
    exit.x, exit.y = exit.triggerX - exit.w * 0.5, exit.triggerY - exit.h
    g.exitNavigation, g.exitRoom = nav, g.room
    return exit
end

local ENEMIES = {
    { hp = 26, speed = 56, damage = 9, xp = 3, radius = 12 },
    { hp = 37, speed = 48, damage = 10, xp = 4, radius = 13 },
    { hp = 31, speed = 43, damage = 8, xp = 4, radius = 12 },
    { hp = 76, speed = 34, damage = 14, xp = 7, radius = 17 },
    { hp = 1100, speed = 46, damage = 19, xp = 0, radius = 24 },
}

---@param heroId string?
---@return table
function Game.New(heroId)
    local hero = Heroes.Get(heroId)
    ---@type CampaignRoom[]
    local rooms = BuildRooms(1)
    local g = {
        heroId = hero.id, hero = hero,
        navigation = Navigation.New(Campaign.Obstacles(rooms[1])),
        floor = 1, rooms = rooms, roomIndex = 1, room = rooms[1], coins = 0, roomsCleared = 0,
        roomCleared = false, wave = 0, totalWaves = 2, waveTimer = 0, rewardPending = false,
        upgradeSource = "level", bossName = Campaign.floors[1].boss, bossesDefeated = 0,
        shopItems = {}, eventChoices = {}, eventTitle = "", eventText = "", uiRevision = 0,
        mode = "menu", time = 0, visualTime = 0, kills = 0, level = 1, xp = 0, xpNeed = 10,
        player = { x = rooms[1].spawn.x, y = rooms[1].spawn.y, hp = hero.maxHp, maxHp = hero.maxHp,
            speed = hero.speed, faceX = 1, faceY = 0, radius = 12, invuln = 0, moving = false,
            walking = false, running = false, gait = "idle", stepDistance = 0 },
        enemies = {}, shots = {}, hostileShots = {}, gems = {}, effects = {}, particles = {},
        pools = {}, upgrades = {}, choices = {}, rage = 65, spawnTimer = 1, meleeTimer = 0.15,
        staplerTimer = 0, coffeeTimer = 0, damage = hero.damage, attackSpeed = 1, range = 1,
        stapler = hero.primaryWeapon=="stapler"and 1 or 0, coffee = 0, regen = 0, magnet = 66, armor = 0, crit = 0,
        primaryWeapon=hero.primaryWeapon or "keyboard",secondaryWeapon=nil,primaryTimer=0,
        shield=hero.shield or 0,shieldMax=hero.shield or 0,shieldQuiet=0,binaryCount=0,
        -- S2：三把新武器与 16 条 BUFF 的持有状态。g.upgrades 记「这张卡出过几次」，
        -- g.weapons / g.buffs 记真实生效等级，两者由 Weapons.Upgrade 与 Buffs.Apply 同步。
        weapons = { thermos = 0, paperclip = 0, pie = 0, laser = 0, extinguisher = 0 },
        weaponTimer = { thermos = 0, paperclip = 0, pie = 0, laser = 0, extinguisher = 0 },
        thermosCombo = 0, paperclipCount = 0,
        -- 刷新次数（每局开局固定额度）：增益 3 次、商店 2 次、事件 1 次。商店选中项默认第 1 件。
        buffs = {}, buffState = {}, pityCounter = 0, rerollsLeft = 3,
        shopRerollsLeft = 2, eventRerollsLeft = 1, shopSelectedIndex = 1,
        adrenaline = 0, ultCooldown = 0,
        bossSpawned = false, bossDefeated = false, bossPhase = 0, bossHp = 0, bossMaxHp = 1100,
        bossTimer = 3, bossAttack = 0, dashTimer = 0, dashX = 0, dashY = 0,
        -- 首领登场延后：pendingBoss 指向「已入场但还没登场」的首领实体，bossDelay 是剩余秒数。
        pendingBoss = nil, bossDelay = 0,
        announcement = "17:59，主管说：下班开个小会。", announcementTime = 0,
        shake = 0, flash = 0, hitStop = 0, audioQueue = {}, combo = 0, comboTimer = 0, actionSerial = 0,
    }
    local spawn = Game.GetSpawn(g)
    g.player.x, g.player.y = spawn.x, spawn.y
    ActionState.Reset(g)
    Fufu.Init(g)
    return g
end

function Game.Announce(g, text, seconds)
    g.announcement, g.announcementTime = text, seconds or 3
end

local function Sound(g, name)
    -- 同帧多杀只占一个hit槽，给并发订书器/咖啡/怒气的命中音留位置。
    for _, queued in ipairs(g.audioQueue) do if queued == name then return end end
    if #g.audioQueue >= 8 and name ~= "pickup" and name ~= "step_walk" and name ~= "step_run" then
        for i, queued in ipairs(g.audioQueue) do
            if queued == "pickup" or queued == "step_walk" or queued == "step_run" then table.remove(g.audioQueue, i); break end
        end
    end
    if #g.audioQueue < 8 then g.audioQueue[#g.audioQueue + 1] = name end
end

function Game.Particles(g, x, y, color, count)
    for _ = 1, count do
        if #g.particles >= 240 then break end
        local a, speed = math.random() * math.pi * 2, math.random(25, 130)
        g.particles[#g.particles + 1] = { x = x, y = y, vx = math.cos(a) * speed,
            vy = math.sin(a) * speed, life = 0.35 + math.random() * 0.45, color = color, size = math.random(2, 5) }
    end
end

local function Effect(g, kind, x, y, life, size, angle, text)
    if #g.effects>=100 then table.remove(g.effects,1)end
    g.effects[#g.effects + 1] = { kind = kind, x = x, y = y, life = life, maxLife = life,
        size = size or 0, angle = angle or 0, text = text or "" }
end

local function Blocked(g, x, y, radius)
    return Navigation.Blocked(RoomNavigation(g), x, y, radius)
end
Game.Blocked = Blocked

local function Visible(g, ax, ay, bx, by, radius)
    return Navigation.Visible(RoomNavigation(g), ax, ay, bx, by, radius or 0)
end
Game.Visible = Visible

local function Move(g, entity, dx, dy, radius)
    Navigation.Move(RoomNavigation(g), entity, dx, dy, radius)
end
Game.Move = Move
-- Every world pickup, shop and upgrade uses the same two-slot ownership rule.
function Game.PickWeapon(g,id)
    if not Loadout.CanAcquire(g,id)then return false end
    if not Loadout.Acquire(g,id)then return false end
    if id=="stapler"then g.stapler=math.max(1,g.stapler)
    elseif id=="coffee"then g.coffee=math.max(1,g.coffee)
    elseif Weapons.Get(id)then
        if Weapons.Level(g,id)==0 then Weapons.Upgrade(g,id)end
    end
    g.upgrades[id]=math.max(1,g.upgrades[id]or 0)
    g.uiRevision=g.uiRevision+1
    Game.Announce(g,"拾取「"..Loadout.names[id].."」· 武器栏已满（2/2）",3)
    Sound(g,"choose")
    return true
end

local function Chase(g, entity, targetX, targetY, speed, dt)
    local wx, wy = Navigation.Waypoint(RoomNavigation(g), entity, targetX, targetY, entity.radius, g.time)
    local nx, ny, distance = Direction(entity.x, entity.y, wx, wy)
    local step = math.min(distance, speed * dt)
    Move(g, entity, nx * step, ny * step, entity.radius)
end
Game.Chase = Chase

-- 首领登场延后（task-4）：进 boss 房时首领实体立刻入场（供碰撞、测试与击杀结算使用），
-- 但「登场」本身——bossSpawned、血条、登场播报、首招计时——推迟 BOSS_APPEAR_DELAY 秒。
-- 首招计时同步后移（2.6 - delay），因此对外的战斗时间线与延前完全一致。
local BOSS_APPEAR_DELAY = 1.0
Game.BOSS_APPEAR_DELAY = BOSS_APPEAR_DELAY

local function ActivateBoss(g, e)
    g.bossSpawned = true
    g.bossHp = math.max(0, e.hp)
    local subtitle = e.kind == 14 and "纸不够了？那就拿你来打印。" or Campaign.floors[e.bossFloor].subtitle
    Game.Announce(g, g.bossName .. "：" .. subtitle, 4)
    Sound(g, "boss")
    print("[首领] " .. g.bossName .. "登场，生命=" .. e.hp .. "，玩家等级=" .. g.level)
end

function Game.Spawn(g, kind, x, y, bossIdentity, deferBoss)
    -- S3：kind 6+ 的数值定义在 Enemies.lua，kind 1..5 仍用本地 ENEMIES（数值一个字都没动）。
    local def = ENEMIES[kind] or Enemies.Get(kind)
    if not def or #g.enemies >= 70 then return nil end
    local nav = RoomNavigation(g)
    if not x or not y then
        x, y = Navigation.SpawnPoint(nav, g.player.x, g.player.y, def.radius, 240)
    else
        -- 指定出生也必须合法：Boss召唤点和测试设置不能绕过墙体/连通性检查。
        x, y = Navigation.Project(nav, x, y, def.radius, g.player.x, g.player.y)
    end
    if not x or not y then return nil end
    local scale = 1 + (g.floor - 1) * 0.45 + (g.room.kind == "elite" and 0.35 or 0)
    -- 打印机Boss按所在层首领基准的1250/1800缩放，随机到首层也不会套末层血量。
    local hp = kind == 5 and Campaign.floors[g.floor].hp
        or (kind == 14 and math.floor(Campaign.floors[g.floor].hp*1250/1800+.5))
        or math.floor(def.hp * scale)
    local speed, damage = def.speed, def.damage + (g.floor - 1) * 3
    -- P2：无尽模式三条独立倍率（05 §2.5）。血量吃同波衰减，伤害与移速各自封顶，Boss 血量由 Endless.SpawnBoss 覆写。
    if g.endless and g.endless.active and kind ~= 5 and kind ~= 14 then
        local wave = g.endless.wave or 1
        hp = math.floor(def.hp * Endless.HpScale(wave)
            * Endless.BatchHpMul(g.endless.batchIndex or 1, g.endless.batchTotal or 1) + 0.5)
        speed = def.speed * Endless.SpdScale(wave)
        damage = math.floor(def.damage * Endless.DmgScale(wave) + 0.5)
    elseif kind~=5 and kind~=14 then
        local pressure=Difficulty.Wave(g)-1
        hp=math.floor(hp*(1+pressure*.075)+.5)
        damage=math.floor(damage*math.min(2.2,1+pressure*.035)+.5)
        speed=def.speed*math.min(1.35,1+pressure*.018)
    end
    local e = { x = x, y = y, hp = hp, maxHp = hp, speed = speed, damage = damage,
        xp = def.xp, radius = def.radius, kind = kind, bossFloor = bossIdentity==4 and 3 or(bossIdentity or g.floor),bossIdentity=bossIdentity, hit = 0, knockX = 0, knockY = 0,
        shootTimer = 1 + math.random() * 2, seed = math.random() * 10,
        faceX=1,faceY=0,animationTime=0,attackCooldown=0,moving=false }
    Difficulty.Apply(g,e,kind==5 or kind==14)
    -- S3：新怪的状态机字段由 Enemies.Init 建（kind 1..5 没有 ai 表，行为完全走原逻辑）。
    if kind >= 6 then Enemies.Init(e, kind) end
    g.enemies[#g.enemies + 1] = e
    if kind == 14 then g.bossName = "打印机巨兽" end
    if kind == 5 or kind == 14 then
        -- 血量上限立刻生效（血条数值与测试断言都读 bossHp），登场动作另算。
        g.bossHp, g.bossMaxHp = e.hp, e.hp
        if deferBoss then
            g.bossSpawned = false
            g.bossTimer = 2.6 - BOSS_APPEAR_DELAY
            g.pendingBoss, g.bossDelay = e, BOSS_APPEAR_DELAY
        else
            g.bossSpawned, g.bossTimer = true, 2.6
            ActivateBoss(g, e)
        end
    end
    return e
end

-- 商店池：第 1 件固定是体力恢复，其余 4 件从 16 条通用 BUFF 里随机抽（按稀有度定价）。
-- 红线：BUFF 的 icon 必须来自 InterfaceIcons.buff 图集，Skin.Icon 拿到未知帧只会画空白。
local SHOP_PRICE = { common = 30, rare = 45, epic = 60 }
local SHOP_BUFF_COUNT = 4

local function RollShopBuff(g, taken)
    local candidates = {}
    for _, def in ipairs(Buffs.LIST) do
        if not def.hero and not taken[def.id] and Buffs.CanLevel(g, def) then
            candidates[#candidates + 1] = def
        end
    end
    if #candidates == 0 then return nil end
    local def = candidates[math.random(#candidates)]
    taken[def.id] = true
    local rarity = def.rarity or "common"
    return { title = def.title, desc = Buffs.Description(g, def), price = SHOP_PRICE[rarity] or 30,
        id = def.id, sold = false, buff = true, iconKind = "buff", icon = def.icon, rarity = rarity }
end

---造一货架补给：1 件恢复 + 4 件随机通用增益。EnterRoom 与 Game.RerollShop 共用。
local function BuildShopItems(g)
    local items = {
        { title = "热乎饭团", desc = "恢复45点精力。", price = 30, id = "heal", sold = false,
          iconKind = "item", icon = "riceball", rarity = "common" },
    }
    local taken = {}
    for _ = 1, SHOP_BUFF_COUNT do
        local item = RollShopBuff(g, taken)
        if item then items[#items + 1] = item end
    end
    if g.heroId == "intern" then
        items[1].desc = items[1].desc .. "（许宁：恢复量50%。）"
    end
    return items
end

function Game.EnterRoom(g, index)
    local room = g.rooms[index]
    if not room then return false end
    g.roomIndex, g.room, room.visited = index, room, true
    g.navigation = Navigation.New(Campaign.Obstacles(room))
    g.mode, g.roomCleared, g.rewardPending = "playing", false, false
    g.wave, g.totalWaves, g.waveTimer = 0, room.kind == "elite" and 3 or 2, 0.8
    g.enemies, g.shots, g.hostileShots, g.pools, g.gems, g.effects, g.particles = {}, {}, {}, {}, {}, {}, {}
    g.defeated={}
    g.bossSpawned, g.bossDefeated, g.bossPhase, g.bossAttack, g.dashTimer = false, false, 0, 0, 0
    g.pendingBoss, g.bossDelay = nil, 0
    g.bossName, g.bossMaxHp, g.bossHp = Campaign.floors[g.floor].boss, Campaign.floors[g.floor].hp, 0
    local spawn, exit = Game.GetSpawn(g), Game.GetExit(g)
    -- Prepare collision-clearance graphs at room entry, before the first wave
    -- or pickup can trigger a large synchronous build in the middle of combat.
    if room.kind == "boss" then
        for _, radius in ipairs({ 4, 24 }) do Navigation.Graph(g.navigation, radius) end
    elseif room.kind == "combat" or room.kind == "elite" then
        for _, radius in ipairs({ 4, 16, 20 }) do Navigation.Graph(g.navigation, radius) end
    end
    g.player.x, g.player.y, g.player.invuln, g.player.moving = spawn.x, spawn.y, 1.5, false
    g.player.walking, g.player.running, g.player.gait, g.player.stepDistance = false, false, "idle", 0
    g.meleeTimer, g.staplerTimer, g.coffeeTimer, g.hitStop = 0, 0, 0, 0
    g.primaryTimer=0
    -- 新武器的冷却同样必须换房清零，否则上一间的余温会带进下一间（tests/Actions.lua:420 换房断言）。
    Weapons.ResetTimers(g)
    ActionState.Reset(g)
    Fufu.OnRoom(g)
    print(string.format("[门数据] F%d-%d spawn=(%.0f,%.0f) exit=(%.0f,%.0f) visualBottom=%.0f",
        g.floor, index, spawn.x, spawn.y, exit.triggerX, exit.triggerY, exit.y + exit.h))
    g.uiRevision = g.uiRevision + 1
    if room.kind == "boss" then
        -- 战役每层均从四种首领随机抽取；身份与场地层数分别保存。
        local identity=math.random(1,4)
        local names={"工贼同事","秃头主管","没良心老板","打印机巨兽"}
        g.bossName=names[identity]
        -- 第 6 参 deferBoss：实体立刻入场（碰撞/测试/击杀结算不变），登场状态延后 1 秒。
        local boss=Game.Spawn(g,identity==4 and 14 or 5,520,230,identity,true)
        if boss then boss.bossFloor=identity==4 and 3 or identity;boss.bossIdentity=identity end
    elseif room.kind == "shop" then
        g.shopItems = BuildShopItems(g)
        g.shopSelectedIndex = 1
        g.mode = "shop"
    elseif room.kind == "event" then
        -- S5 事件池已验收（11 条 apply 全演练通过、首房 pin legacy_1 红线由 Events.lua:453 保证），
        -- 灰度开关按 07-halved-plan.md 的阶段约定转正。
        if Events.USE_POOL and Events.Apply then
            local dealt = Events.Apply(g, room)
            if dealt then
                g.mode = "event"
                Game.Announce(g, string.format("第%d层 · %s / %s", g.floor, Campaign.floors[g.floor].name, room.name), 4)
                print("[区域] 进入F" .. g.floor .. "-" .. index .. " " .. room.name .. "(" .. room.kind .. ")")
                return
            end
        end
        local titles = { "茶水间的秘密纸条", "匿名意见箱", "劳动合同的最后一页" }
        local texts = { "一位摸鱼前辈留下了补给。怎么使用，由你决定。", "有人在箱底藏了三份礼物。这次没有正确答案。", "你找到一条被折起的条款：员工有权拥有自己的时间。" }
        g.eventTitle, g.eventText = titles[g.floor], texts[g.floor]
        g.eventChoices = {
            { title = "先照顾自己", desc = "恢复40精力，上限+10。", color = "teal" },
            { title = "拿回劳动所得", desc = "获得50枚摸鱼币。", color = "gold" },
            { title = "签下拒绝承诺", desc = "伤害+20%，怒气充满。", color = "pink" },
        }
        g.mode = "event"
    end
    Game.Announce(g, string.format("第%d层 · %s / %s", g.floor, Campaign.floors[g.floor].name, room.name), 4)
    print("[区域] 进入F" .. g.floor .. "-" .. index .. " " .. room.name .. "(" .. room.kind .. ")")
end

function Game.Start(g)
    Game.EnterRoom(g, 1)
    Game.Announce(g, "清理房间 → 领取BUFF → 上方出口选择路线。", 5)
    Sound(g, "start")
    print("[玩法] 三层区域闯关开始，每层含商店、事件和独立首领")
end

-- 许宁怒气口径（docs/design/15-intern-rage-tuning.md §2）：只动许宁，其他角色保持 12。
-- 击杀来源系数只作用于「击杀怒气」，不影响伤害、受击怒气、自然恢复与「忍无可忍」补怒。
local DEFAULT_HURT_RAGE = 12
local INTERN_HURT_RAGE = 8
local INTERN_SHIELD_RAGE = 6
local FOLDER_KILL_RAGE_SCALE = 0.5
local ULT_KILL_RAGE_SCALE = 0.9

local function TakeDamage(g, amount)
    local p = g.player
    if p.invuln > 0 or g.mode ~= "playing" then return end
    amount=Fufu.Intercept(g,amount)
    if amount<=0 then return end
    -- B11 带薪发呆：整次伤害被护盾吃掉，既不进怒气也不触发受击动作（02 §6.2）。
    if Buffs.ConsumeShield(g) then
        Effect(g, "hurt", p.x, p.y - 36, 0.5, 0, 0, "护盾")
        g.shake = math.max(g.shake, 2)
        Sound(g, "choose")
        amount=amount*(1-Buffs.Scale(g,"shield"))
        if amount<=0 then return end
    end
    -- B14 困兽之斗在算护甲之前乘，保证「减伤 40%」对高伤一击也成立。
    local reduction=(g.hero.reduction or 0)+.06*Buffs.EffectLevel(g,"internProtection")
    local loss = math.max(1, math.floor(amount * Buffs.DamageTakenMul(g)*(1-math.min(.60,reduction)) - g.armor + 0.5))
    g.shieldQuiet=0
    if(g.shield or 0)>0 then
        local absorbed=math.min(g.shield,loss);g.shield=g.shield-absorbed;loss=loss-absorbed
        Effect(g,"shieldImpact",p.x,p.y-35,.3,75)
    end
    p.hp = math.max(0, p.hp - loss)
    p.invuln, g.shake, g.flash = 0.9, 5, 0.16
    -- 判定依据是数值护盾结算后的 loss：loss==0 视为护盾完全吸收。
    local hitRage = DEFAULT_HURT_RAGE
    if g.heroId == "intern" then
        hitRage = loss > 0 and INTERN_HURT_RAGE or INTERN_SHIELD_RAGE
    end
    g.rage = math.min(100, g.rage + hitRage * Buffs.RageMul(g))
    Effect(g, "hurt", p.x, p.y - 36, 0.7, 0, 0, loss==0 and "护盾吸收"or("-"..loss))
    ActionState.Start(g, "hurt", p.faceX, p.faceY)
    Sound(g, "hurt")
    if p.hp <= 0 then
        -- P4：无尽模式阵亡先进结算（把成绩算出来），再切 endlessResult，玩家才提交得了。
        if g.endless and g.endless.active then
            if Game.deathHook then pcall(Game.deathHook, g) end
            g.mode = "endlessResult"
            Game.Announce(g, "下班未遂，但绝不认输。", 3)
        else
            g.mode = "lost"
            Game.Announce(g, "下班未遂，但绝不认输。", 20)
        end
        print("[玩法] 本局结束，存活=" .. math.floor(g.time) .. "秒，击退=" .. g.kills)
    end
end
Game.TakeDamage = TakeDamage

---@param opts table? { noMult = true, rageScale = number } noMult 跳过暴击/处决/破甲/标记等乘区，仅吃 g.damage；rageScale 只缩放「击杀怒气」
function Game.Hit(g, e, damage, nx, ny, force, opts)
    if e.hp <= 0 then return end
    local noMult = opts and opts.noMult
    local rageScale = (opts and opts.rageScale) or 1
    local crit = (not noMult) and math.random() < g.crit
    local amount = damage * g.damage
    if crit then amount = amount * Buffs.CritMul(g) end
    if not noMult then
        -- B04 处决 / 女主大招标记：都在 Game.Hit 里统一乘，武器侧不需要各写一遍。
        amount = amount * Buffs.ExecuteMul(g, e)
        if (e.markHits or 0) > 0 then
            amount = amount * 1.35
            e.markHits = e.markHits - 1
            if e.markHits <= 0 then e.markHits, e.markTimer = nil, nil end
        end
        -- B03 破甲：固定 +2/层，放在乘区之后加，避免被 crit 放大成滚雪球。
        amount = amount + 2 * (e.armorBreak or 0)*Buffs.Scale(g,"armorBreak")
    end
    amount = math.floor(amount + 0.000001)
    -- S3 保安：正面 120° 减伤 70%，只在玩家命中结算侧生效（Enemies.ShieldMul 返回 0.3）。
    if e.ai and not noMult then
        local shieldMul = Enemies.ShieldMul(e, nx or 0, ny or 0)
        if shieldMul < 1 then amount = math.max(1, math.floor(amount * shieldMul + 0.5)) end
    end
    if not noMult then amount=Difficulty.Mitigate(e,amount)end
    local absorbed=math.min(e.shield or 0,amount)
    e.shield=math.max(0,(e.shield or 0)-absorbed)
    amount=math.max(0,amount-absorbed);e.shieldQuiet=0
    e.hp, e.hit = e.hp - amount, 0.12
    e.knockX, e.knockY = nx * (force or 95), ny * (force or 95)
    Effect(g, crit and "crit" or "damage", e.x + math.random(-9, 9), e.y - 30, 0.6, 0, 0, amount>0 and tostring(amount)or "护盾吸收")
    if not noMult and e.affix=="reflect"and(e.reflectCd or 0)<=0
        and Distance(e.x,e.y,g.player.x,g.player.y)<180 then
        e.reflectCd,e.reflectPending=1.2,.35
        Effect(g,"warning",e.x,e.y,.35,180,0)
    end
    -- BUFF 侧结算（吸血/灼烧/连坐）必须在死亡分支之前：连坐要能顺着还活着的目标跳。
    if not noMult then Buffs.OnHit(g, e, amount, crit) end
    if e.kind == 5 or e.kind == 14 then g.bossHp = math.max(0, e.hp) end
    if e.hp > 0 then return end
    g.defeated=g.defeated or {}
    if #g.defeated>=24 then table.remove(g.defeated,1)end
    g.defeated[#g.defeated+1]={x=e.x,y=e.y,kind=e.kind,bossFloor=e.bossFloor,faceX=e.faceX,faceY=e.faceY,deathTime=0,hit=0}
    g.kills, g.combo, g.comboTimer = g.kills + 1, g.combo + 1, 2.5
    -- 不取整：1.5 / 2.7 / 3.51 必须原样累加，再由 100 上限截断。
    local killRage = (e.kind == 4 and 7 or 3) * rageScale
    g.rage = math.min(100, g.rage + killRage * Buffs.RageMul(g))
    Game.Particles(g, e.x, e.y - 10, e.kind == 2 and "paper" or "teal", e.kind == 5 and 65 or 9)
    if e.kind == 5 or e.kind == 14 then
        g.bossDefeated, g.bossesDefeated = true, g.bossesDefeated + 1
        -- 待登场期就被打死（高伤害/爆发）：立刻取消登场倒计时，免得 1 秒后再播一次登场。
        if g.pendingBoss == e then g.pendingBoss, g.bossDelay = nil, 0 end
        g.hostileShots = {}
        for _, other in ipairs(g.enemies) do other.hp = 0 end
        if g.endless and g.endless.active then
            -- P5：无尽里 Boss 死亡不结束本局，改为给满一管经验 + 累计击杀数，并把临时借用的 F3 配色还回去。
            g.xp = g.xp + math.floor(g.xpNeed*Difficulty.XpMul(Difficulty.Wave(g))+.5)
            g.endless.bossLevel = (g.endless.bossLevel or 0) + 1
            g.floor = 1
            Game.Announce(g, g.bossName .. "已被击破！喘口气，下一波更狠。", 5)
        else
            Game.Announce(g, g.bossName .. "已被击败！领取BUFF后前往电梯。", 8)
        end
        Sound(g, "win")
        print("[首领] " .. g.bossName .. "已击败，等待房间结算")
    else
        -- B24 报销高手：金币乘区，仅影响掉落，不影响商店定价与事件奖励。
        g.coins = g.coins + Buffs.CoinReward(g,e.kind == 4 and 5 or 3)
        Effect(g,"coin",e.x,e.y-18,.65,25)
        local nav = RoomNavigation(g)
        local gx, gy = Navigation.Project(nav, e.x, e.y, 4, g.player.x, g.player.y)
        if gx and gy then g.gems[#g.gems + 1] = { x = gx, y = gy, value = e.xp, heal = false, radius = 4 } end
        if g.kills % 17 == 0 then
            local hx, hy = Navigation.Project(nav, e.x + 12, e.y, 4, g.player.x, g.player.y)
            if hx and hy then g.gems[#g.gems + 1] = { x = hx, y = hy, value = 0, heal = true, radius = 4 } end
        end
    end
    if g.kills>=5 and not g.firstWeaponDrop and not g.secondaryWeapon then
        local nav=RoomNavigation(g)
        local x,y=Navigation.Project(nav,e.x,e.y,6,g.player.x,g.player.y)
        if x and y then
            local pool={};for _,id in ipairs({"stapler","coffee","thermos","paperclip","pie"})do
                if id~=Loadout.Primary(g)then pool[#pool+1]=id end
            end
            g.gems[#g.gems+1]={x=x,y=y,value=0,heal=false,radius=6,weapon=pool[math.random(1,#pool)]}
            g.firstWeaponDrop=true
            Game.Announce(g,"掉落了一件办公武器，靠近即可装备副武器。",4)
        end
    end
    if g.combo % 15 == 0 then
        local words = { "拒绝背锅！", "停止内耗！", "这不归我管！", "已读不回！" }
        Game.Announce(g, words[math.random(1, #words)] .. "  " .. g.combo .. " 连击", 1.7)
    end
    Sound(g, "hit")
end

-- 真伤/无乘区命中：DOT、连坐、女主大招都走这里，不吃暴击/处决/破甲/标记，也不触发 BUFF 回调（防递归）。
function Game.TrueHit(g, e, damage, nx, ny, force)
    if type(e) ~= "table" or (e.hp or 0) <= 0 then return end
    Game.Hit(g, e, damage, nx or 0, ny or 0, force or 0, { noMult = true })
end

-- B16 闪人：瞬步。位移在 Game.Update 的移动段结算，这里只负责起手与冷却。
function Game.Dash(g, nx, ny)
    if g.mode ~= "playing" then return false end
    return Buffs.StartDash(g, nx or g.player.faceX or 1, ny or g.player.faceY or 0)
end

function Game.Burst(g)
    if g.heroId=="fufu"then return Fufu.BeginSummon(g)end
    if g.mode ~= "playing" or g.rage < 100 or ActionState.Active(g, "burst") then return false end
    local action = ActionState.Start(g, "burst", g.player.faceX, g.player.faceY)
    if not action then return false end
    g.rage, g.player.invuln = 0, math.max(g.player.invuln, 1.2)
    print("[动作] 拒绝加班蓄力 serial=" .. action.serial)
    return true
end

-- ============================================================ 男女主大招分流（S2 §5）
-- 分流点只有一个：ActionImpact 的 burst 分支。ActionState 层完全不知道英雄是谁，
-- TIMINGS.burst = {0.10, 0.12, 0.28, 0.60} 与 impactAt=0.12 对两人完全一致（tests/Actions.lua:291-311 锁死）。
--
-- 【女主 林夏 · 职场洞察】必须保持 math.floor(125 * g.damage) 真伤：
-- 不吃暴击、不吃处决、不吃破甲、不吃标记，也不能拆多段——tests/Actions.lua:305-307 逐字节断言。
-- 所以走 Game.TrueHit（noMult），标记在伤害结算**之后**才挂，避免自己吃自己那 1.35 倍。
-- 女主只吃 Buffs.UltRadius 的范围加成，不吃 UltPower 的伤害加成。
--
-- 【男主 陈准 · 暴怒砸桌】原版对男主伤害数值没有任何断言（tests/Smoke.lua:59-67 只验时机），
-- 因此整套换成 198° 扇形重击：范围收窄、击退拉满、附带眩晕与肾上腺素攻速，换掉原来的全向爆破。
local function InsightMark(g, e)
    -- 3 层标记，每层让后续命中 ×1.35（Game.Hit 里消耗），持续 6 秒。
    e.markHits, e.markTimer = 3, 6.0
end

local function BurstImpactFemale(g)
    local p = g.player
    g.shake, g.hitStop, g.hostileShots = 9, 0.065, {}
    local radius = 260 * Buffs.UltRadius(g)
    Effect(g, "burst", p.x, p.y, 0.65, radius)
    Game.Particles(g, p.x, p.y, "gold", 45)
    for _, e in ipairs(g.enemies) do
        local nx, ny, d = Direction(p.x, p.y, e.x, e.y)
        if d < radius + e.radius and Visible(g, p.x, p.y, e.x, e.y) then
            -- 真伤：noMult 跳过全部乘区，唯一保留 g.damage 这个角色基础系数。
            Game.TrueHit(g, e, 125, nx, ny, 420)
            if e.hp > 0 then
                InsightMark(g, e)
                e.slowTimer = 2.5
            end
        end
    end
    Game.Announce(g, "职场洞察！  你所有的借口，我都记下了。", 2.6)
    Sound(g, "burst")
    print("[动作] 职场洞察命中，清空弹幕")
end

local function BurstImpactMale(g)
    local p = g.player
    g.shake, g.hitStop, g.hostileShots = 11, 0.075, {}
    local radius = 168 * Buffs.UltRadius(g)
    local nx, ny = p.faceX or 1, p.faceY or 0
    Effect(g, "slamRing", p.x, p.y, 0.6, radius, math.atan(ny, nx))
    Game.Particles(g, p.x, p.y, "gold", 40)
    -- 198° 扇区 = 半角 99°，dot > cos(99°) ≈ -0.156 之外全打，身后留一条窄缝。
    local landed = false
    for _, e in ipairs(g.enemies) do
        local ex, ey, d = Direction(p.x, p.y, e.x, e.y)
        if d < radius + e.radius and ex * nx + ey * ny > -0.156
            and Visible(g, p.x, p.y, e.x, e.y) then
            Game.Hit(g, e, (105 + 8 * g.level) * (g.slamAmp or 1) * Buffs.UltPower(g), ex, ey, 520)
            if e.hp > 0 then e.stunTimer = math.max(e.stunTimer or 0, 1.2) end
            landed = true
        end
    end
    -- 肾上腺素：1.2 秒攻速 ×1.25（UpdateWeapons 里读 g.adrenaline）。
    g.adrenaline = math.max(g.adrenaline or 0, 1.2)
    if landed then g.player.invuln = math.max(g.player.invuln, 0.6) end
    Game.Announce(g, "暴怒砸桌！  这个需求，我当场掀了。", 2.6)
    Sound(g, "slam")
    print("[动作] 暴怒砸桌命中，清空弹幕")
end

local function BurstImpact(g)
    if g.heroId=="intern"then
        g.shield=g.shieldMax;g.player.invuln=math.max(g.player.invuln,2)
        g.hostileShots={};Effect(g,"shieldImpact",g.player.x,g.player.y-30,.6,220)
        for _,e in ipairs(g.enemies)do local nx,ny,d=Direction(g.player.x,g.player.y,e.x,e.y)
            if d<180*Buffs.UltRadius(g)+e.radius and Visible(g,g.player.x,g.player.y,e.x,e.y)then Game.Hit(g,e,150*Buffs.UltPower(g),nx,ny,350,
                { rageScale = ULT_KILL_RAGE_SCALE })end
        end
        Game.Announce(g,"实习生也有底气！护盾全满，2秒免疫伤害。",3);Sound(g,"burst")
    elseif g.heroId=="programmer"then
        g.overclock=4;g.hostileShots={};Effect(g,"codeCast",g.player.x,g.player.y-30,.4,160)
        Game.Announce(g,"全核启动！4秒发射频率+80%，每次额外1弹。",3);Sound(g,"burst")
    elseif g.heroId == "male" then BurstImpactMale(g) else BurstImpactFemale(g) end
end
Game.BurstImpact = BurstImpact
Game.UltImpact = BurstImpact

local UPGRADES = {
    { id = "stapler", title = "流程钉死", tag = "武器 / 订书机", desc = "解锁订书机；已拥有则强化弹丸数量与穿透。", color = "teal" },
    { id = "coffee", title = "冰美式续命", tag = "武器 / 咖啡杯", desc = "向敌群泼洒咖啡，持续伤害并减速。", color = "gold" },
    { id = "damage", title = "拒绝内耗", tag = "伤害强化", desc = "所有武器伤害 +25%。少想一点，多打一点。", color = "pink" },
    { id = "speed", title = "到点就跑", tag = "移动强化", desc = "移动速度 +15%，不再慢吞吞地假装忙碌。", color = "teal" },
    { id = "attack", title = "手速进修", tag = "攻速强化", desc = "武器攻击频率 +22%，输出全靠手速。", color = "purple" },
    { id = "range", title = "这不归我管", tag = "范围强化", desc = "近战武器范围 +20%，把麻烦推远一点。", color = "gold" },
    { id = "magnet", title = "带薪摸鱼", tag = "拾取强化", desc = "经验吸取范围 +70，顺手收下摸鱼能量。", color = "teal" },
    { id = "health", title = "先照顾自己", tag = "生命强化", desc = "生命上限 +25，立即恢复35点生命。", color = "pink" },
    { id = "regen", title = "工间休息", tag = "持续恢复", desc = "每秒恢复1.2点生命，喘口气再继续。", color = "teal" },
    { id = "armor", title = "拒绝背锅", tag = "防御强化", desc = "每次受到的伤害 -3，黑锅原路退回。", color = "purple" },
    { id = "crit", title = "已读乱回", tag = "暴击强化", desc = "暴击率 +15%，暴击造成1.8倍伤害。", color = "gold" },
    { id = "rage", title = "忍无可忍", tag = "立即爆发", desc = "立即充满怒气，并恢复20点生命。", color = "pink" },
}
Game.upgradeDefs = UPGRADES

-- ============================================================ 抽卡（S2 §6.3 五选一）
-- 池子 = 12 条旧 UPGRADES（common，权重 100）
--      + 16 条 Buffs.LIST（common 100 / rare 40 / epic 12，读 def.rarity）
--      + 3 把启用中的新武器（rare，权重 40）
-- 稀有度不是纯随机：每次升级给非 common 一个 rareBoost（等级越高越容易出好东西），
-- 并且 pityCounter 每 3 次升级强制塞一张非 common（软保底，03 §6 的「不要连着给垃圾」）。
local CHOICE_COUNT = 5
local WEIGHT = { common = 100, rare = 40, epic = 12 }
local INTERN_UPGRADES={
 damage="所有武器伤害强化+12.5%。",speed="移动速度+7.5%。",attack="武器攻击频率+11%。",
 range="近战武器范围+10%。",magnet="经验吸取范围+35。",health="精力上限+12.5，立即回复17.5点精力。",
 regen="每秒回复0.6点精力。",armor="每次受到伤害-1.5。",crit="暴击率+7.5%。",
 rage="补充当前缺少怒气的一半，并回复10点精力。",
 stapler="解锁订书器；后续伤害、连发、穿透和射速强化增量仅50%。",
 coffee="解锁咖啡杯；后续伤害、范围和射速强化增量仅50%。",
}

local function EntryWeight(g, entry)
    local base = entry.weight or WEIGHT[entry.rarity or "common"] or 100
    if base < 100 then
        -- 稀有度越高，等级加成越明显（每级 +4%，最多 +60%）。
        base = base * (1 + math.min(0.6, (g.level - 1) * 0.04))
    end
    return base
end

local function BuildPool(g)
    local pool = {}
    -- ① 旧 12 条：上限逻辑原样保留（stapler 4、其余 3、rage 无限）。
    for _, u in ipairs(UPGRADES) do
        local count = u.id=="stapler"and g.stapler or(g.upgrades[u.id]or 0)
        local useful=u.id~="range"or Loadout.Has(g,"keyboard")or Loadout.Has(g,"folder")or Loadout.Has(g,"thermos")
        if useful and(g.heroId~="fufu"or u.id~="rage")and(u.id~="stapler"and u.id~="coffee"or Loadout.CanAcquire(g,u.id))and(u.id == "rage" or count < (u.id == "stapler" and 4 or 3))then
            pool[#pool + 1] = { id = u.id, title = u.title, tag = u.tag, desc = u.desc, color = u.color,
                icon = u.id, rarity = "common", weight = 100, kind = "upgrade" }
            if g.heroId=="intern"then pool[#pool].desc=(INTERN_UPGRADES[u.id]or pool[#pool].desc).."（许宁：通用增益效果50%。）"end
        end
    end
    -- ② 16 条新 BUFF：满级的不再出现。
    for _, def in ipairs(Buffs.LIST) do
        if (not def.hero or def.hero==g.heroId)and(g.heroId~="fufu"or(def.id~="rageGain"and def.id~="ultPower"))and Buffs.CanLevel(g, def) then
            pool[#pool + 1] = { id = def.id, title = def.title, tag = def.tag, desc = Buffs.Description(g,def),
                color = def.color, icon = def.icon, rarity = def.rarity or "common", kind = "buff" }
        end
    end
    -- ③ 3 把启用中的新武器：满 5 级不再出现。
    for _, def in ipairs(Weapons.EnabledList()) do
        if Loadout.CanAcquire(g,def.id)and Weapons.Level(g, def.id) < (def.maxLevel or 5) then
            pool[#pool + 1] = { id = def.id, title = def.title, tag = def.tag, desc = def.desc,
                color = def.color, icon = def.icon, rarity = "rare", kind = "weapon" }
            if g.heroId=="intern"then pool[#pool].desc=pool[#pool].desc.."（许宁：首次解锁完整，后续等级强化增量50%。）"end
        end
    end
    return pool
end

local function WeightedPick(g, pool)
    local total = 0
    for _, entry in ipairs(pool) do total = total + EntryWeight(g, entry) end
    if total <= 0 then return table.remove(pool, 1) end
    local roll = math.random() * total
    for i, entry in ipairs(pool) do
        roll = roll - EntryWeight(g, entry)
        if roll <= 0 then return table.remove(pool, i) end
    end
    return table.remove(pool, 1)
end

---抽出本次升级的 5 个选项。公开给 Endless / 测试复用。
function Game.RollChoices(g)
    local pool = BuildPool(g)
    local choices = {}
    if #pool == 0 then return choices end
    -- 软保底：连续 3 次升级没出非 common，则本次第一张必为 rare/epic。
    g.pityCounter = (g.pityCounter or 0) + 1
    if g.pityCounter >= 3 then
        local rareIndex = nil
        for i, entry in ipairs(pool) do
            if (entry.rarity or "common") ~= "common" then rareIndex = i; break end
        end
        if rareIndex then
            choices[#choices + 1] = table.remove(pool, rareIndex)
            g.pityCounter = 0
        end
    end
    while #choices < CHOICE_COUNT and #pool > 0 do
        choices[#choices + 1] = WeightedPick(g, pool)
    end
    -- 只要出了非 common 就把保底计数清零。
    for _, entry in ipairs(choices) do
        if (entry.rarity or "common") ~= "common" then g.pityCounter = 0; break end
    end
    return choices
end

local function LevelUp(g, source)
    g.upgradeSource = source or "level"
    if g.upgradeSource == "level" then
        g.xp, g.level = g.xp - g.xpNeed, g.level + 1
        if g.endless and g.endless.active then
            -- P1：无尽用二次曲线，把「BUFF 池毕业」推到第 33 波（05 §2.6）。
            g.xpNeed = Endless.XpNeed(g.level)
        else
            g.xpNeed = 12 + g.level * 10
        end
    end
    g.mode = "upgrade"
    Game.Heal(g,8)
    -- 第一次升级（Lv1/2）保证出现两把新武器，尽早展示构筑差异（旧行为保留）。
    g.choices = Game.RollChoices(g)
    -- B26 reroll：每级补充可重掷次数（不累加，取较大值，避免无限刷）。
    local rerolls = Buffs.RerollGrant(g)
    if rerolls > 0 then g.rerollsLeft = math.max(g.rerollsLeft or 0, rerolls) end
    Sound(g, "upgrade")
    print("[玩法] 升至等级" .. g.level .. "，暂停并等待五选一（选项 " .. #g.choices .. " 张）")
end
-- 导出给无尽模式做连锁升级（Endless.Update 会主动调用；见 07-halved-plan.md S0-3）
Game.LevelUp = LevelUp

function Game.Choose(g, index)
    if g.mode ~= "upgrade" or not g.choices[index] then return end
    local choice = g.choices[index]
    local id = choice.id
    if Loadout.names[id]and not Loadout.CanAcquire(g,id)then return end
    if(id=="stapler"or id=="coffee"or Weapons.Get(id))and not Loadout.Acquire(g,id)then return end
    local buff=Buffs.Get(id)
    if buff and buff.hero and buff.hero~=g.heroId then return end
    g.upgrades[id] = (g.upgrades[id] or 0) + 1
    if id == "stapler" then g.stapler = math.min(4,g.stapler + 1)
    elseif id == "coffee" then g.coffee = g.coffee + 1
    elseif id == "damage" then g.damage = g.damage + Scaling.Gain(g,.25)
    elseif id == "speed" then g.player.speed = g.player.speed * (1+Scaling.Gain(g,.15))
    elseif id == "attack" then g.attackSpeed = g.attackSpeed + Scaling.Gain(g,.22)
    elseif id == "range" then g.range = g.range + Scaling.Gain(g,.2)
    elseif id == "magnet" then g.magnet = g.magnet + Scaling.Gain(g,70)
    elseif id == "health" then
        g.player.maxHp = g.player.maxHp + Scaling.Gain(g,25)
        Game.Heal(g,Scaling.Gain(g,35))
    elseif id == "regen" then g.regen = g.regen + Scaling.Gain(g,1.2)
    elseif id == "armor" then g.armor = g.armor + Scaling.Gain(g,3)
    elseif id == "crit" then g.crit = g.crit + Scaling.Gain(g,.15)
    elseif id == "rage" then g.rage = g.rage+Scaling.Gain(g,100-g.rage); Game.Heal(g,Scaling.Gain(g,20))
    elseif Buffs.Get(id) then
        -- S2 十六条新 BUFF：等级与一次性效果都在 Buffs.Apply 里，这里只管发卡。
        Buffs.Apply(g, id)
    elseif Weapons.Get(id) and Weapons.Get(id).enabled then
        -- S2 三把新武器：g.weapons 是唯一等级源，g.upgrades 只记「出过几次」（上面已加）。
        Weapons.Upgrade(g, id)
    end
    g.mode = "playing"
    if g.upgradeSource == "room" then
        g.rewardPending, g.roomCleared = false, true
        Game.Announce(g, "获得「" .. g.choices[index].title .. "」！前往上方出口，或按 E 选择路线。", 7)
    else Game.Announce(g, "获得「" .. g.choices[index].title .. "」", 2) end
    g.choices = {}
    Sound(g, "choose")
    print("[玩法] 已选择升级=" .. id .. "，来源=" .. g.upgradeSource)
end

local function CompleteSafeRoom(g)
    if not g.room.cleared then g.roomsCleared = g.roomsCleared + 1 end
    g.room.cleared, g.roomCleared, g.mode = true, true, "playing"
    Game.Announce(g, "整顿完毕。前往上方出口，或按 E 打开路线图。", 7)
    g.uiRevision = g.uiRevision + 1
end

function Game.Buy(g, index)
    if g.mode ~= "shop" then return false end
    local item = g.shopItems[index]
    if not item or item.sold or g.coins < item.price then return false end
    if Loadout.names[item.id]and not Loadout.CanAcquire(g,item.id)then return false end
    if item.id == "stapler" and g.stapler >= 4 then return false end
    if item.id=="stapler"and not Loadout.CanAcquire(g,"stapler")then return false end
    if item.id == "heal" and g.player.hp >= g.player.maxHp then return false end
    if item.buff then
        local def = Buffs.Get(item.id)
        if not def or not Buffs.CanLevel(g, def) then return false end
    end
    g.coins, item.sold = g.coins - item.price, true
    if item.id == "heal" then Game.Heal(g,Scaling.Gain(g,45))
    elseif item.buff then Buffs.Apply(g, item.id)
    elseif item.id == "stapler" then Loadout.Acquire(g,"stapler");g.stapler = g.stapler + 1; g.upgrades.stapler = g.stapler
    elseif item.id == "damage" then g.damage = g.damage + Scaling.Gain(g,.25) end
    g.uiRevision = g.uiRevision + 1
    Sound(g, "choose")
    print("[商店] 购买=" .. item.id .. "，余额=" .. g.coins)
    return true
end

function Game.LeaveShop(g)
    if g.mode ~= "shop" then return end
    CompleteSafeRoom(g)
end

---选中商店里的一件补给（双栏界面右侧预览用）。不消耗任何资源。
function Game.ShopSelect(g, index)
    if g.mode ~= "shop" or not g.shopItems[index] then return false end
    if g.shopSelectedIndex == index then return true end
    g.shopSelectedIndex = index
    g.uiRevision = g.uiRevision + 1
    return true
end

---商店刷新：消耗 1 次额度，重掷 4 件随机增益（已售出的体力恢复保留原状态）。
function Game.RerollShop(g)
    if g.mode ~= "shop" then return false end
    if (g.shopRerollsLeft or 0) <= 0 then return false end
    local healed = g.shopItems[1]
    if healed and healed.id ~= "heal" then healed = nil end
    g.shopRerollsLeft = g.shopRerollsLeft - 1
    local fresh = BuildShopItems(g)
    if healed then
        fresh[1] = healed
    else
        table.remove(fresh, 1)
    end
    g.shopItems = fresh
    local sel = math.min(math.max(1, g.shopSelectedIndex or 1), #g.shopItems)
    g.shopSelectedIndex = sel
    g.uiRevision = g.uiRevision + 1
    Sound(g, "choose")
    print("[商店] 刷新补给，剩余 " .. g.shopRerollsLeft .. " 次")
    return true
end

---事件刷新：消耗 1 次额度，换一条事件（收益与代价一起换）。
function Game.RerollEvent(g)
    if g.mode ~= "event" then return false end
    if (g.eventRerollsLeft or 0) <= 0 then return false end
    if not (Events.Reroll and Events.Reroll(g, g.room)) then return false end
    g.eventRerollsLeft = g.eventRerollsLeft - 1
    g.uiRevision = g.uiRevision + 1
    Sound(g, "choose")
    print("[事件] 刷新事件，剩余 " .. g.eventRerollsLeft .. " 次")
    return true
end

---增益刷新：消耗 1 次 buff 额度，重掷本次升级的 5 个候选（选择页刷新按钮）。
function Game.RerollChoices(g)
    if g.mode ~= "upgrade" then return false end
    if (g.rerollsLeft or 0) <= 0 then return false end
    local fresh = Game.RollChoices(g)
    if #fresh == 0 then return false end
    g.rerollsLeft = g.rerollsLeft - 1
    g.choices = fresh
    g.upgradeSelectedIndex = 1
    g.upgradeSelectionChoices = fresh
    g.uiRevision = g.uiRevision + 1
    Sound(g, "choose")
    print("[玩法] 刷新增益候选，剩余 " .. g.rerollsLeft .. " 次")
    return true
end

function Game.ResolveEvent(g, index)
    if g.mode ~= "event" or not g.eventChoices[index] then return false end
    local choice = g.eventChoices[index]
    -- S5：事件池（Events.lua）的每个选项自带 apply(g)；旧三条写死事件没有 apply，走下面的老分支。
    if type(choice.apply) == "function" then
        choice.apply(g)
        CompleteSafeRoom(g)
        Sound(g, "choose")
        print("[事件] " .. tostring(g.eventTitle) .. "，选择=" .. index .. "（事件池）")
        return true
    end
    if index == 1 then
        g.player.maxHp = g.player.maxHp + Scaling.Gain(g,10)
        Game.Heal(g,Scaling.Gain(g,40))
    elseif index == 2 then g.coins = g.coins + 50
    else
        g.damage=g.damage+Scaling.Gain(g,.2)
        if g.heroId=="fufu"then g.summons.charges=math.min(3,g.summons.charges+1)
        else g.rage=g.rage+Scaling.Gain(g,100-g.rage)end
    end
    CompleteSafeRoom(g)
    Sound(g, "choose")
    print("[事件] " .. g.eventTitle .. "，选择=" .. index)
    return true
end

function Game.OpenRoute(g)
    if g.mode ~= "playing" or not g.roomCleared then return false end
    if g.room.kind == "boss" then
        if g.floor == 3 then
            g.mode = "won"
            Sound(g, "win")
            print("[通关] 三层首领全部击败，下班成功")
        else
            g.floor = g.floor + 1
            g.rooms = BuildRooms(g.floor)
            Game.Heal(g,30)
            Game.EnterRoom(g, 1)
        end
    else g.mode = "route" end
    return true
end

function Game.Travel(g, index)
    if g.mode ~= "route" then return false end
    for _, nextIndex in ipairs(g.room.next) do
        if nextIndex == index then Game.EnterRoom(g, index); return true end
    end
    return false
end

local function ClearRoom(g)
    if g.room.cleared or g.mode ~= "playing" then return end
    g.room.cleared, g.rewardPending = true, true
    g.roomsCleared = g.roomsCleared + 1
    Fufu.Cleared(g)
    g.coins = g.coins + (g.room.kind == "boss" and 70 or (g.room.kind == "elite" and 40 or 20))
    for _, gem in ipairs(g.gems) do
        if gem.weapon then Game.PickWeapon(g,gem.weapon)
        elseif gem.heal then Game.Heal(g,22)
        else g.xp = g.xp + (gem.value or 0) end
    end
    g.gems, g.hostileShots, g.shots, g.pools = {}, {}, {}, {}
    LevelUp(g, "room")
    print("[区域] 清理完成，发放金币与三选一BUFF；累计=" .. g.roomsCleared)
end

local function Nearest(g)
    local nearest, distance = false, math.huge
    for _, e in ipairs(g.enemies) do
        local d = Distance(g.player.x, g.player.y, e.x, e.y)
        if e.hp > 0 and d < distance and Visible(g, g.player.x, g.player.y, e.x, e.y, 4) then
            nearest, distance = e, d
        end
    end
    return nearest, distance
end

local function UpdateWeapons(g, dt)
    g.primaryTimer=(g.primaryTimer or 0)-dt
    -- 冷却各自独立；一个武器的完整收招不会吞掉另一武器的到期发射。
    g.meleeTimer, g.staplerTimer, g.coffeeTimer = g.meleeTimer - dt, g.staplerTimer - dt, g.coffeeTimer - dt
    -- S2：三把新武器各有独立计时器，统一走 Weapons.Timer/SetTimer。
    Weapons.SetTimer(g, "thermos", Weapons.Timer(g, "thermos") - dt)
    Weapons.SetTimer(g, "paperclip", Weapons.Timer(g, "paperclip") - dt)
    Weapons.SetTimer(g, "pie", Weapons.Timer(g, "pie") - dt)
    -- B07 手速 + B14 困兽之斗 + 男主大招肾上腺素都进同一条攻速乘区。
    local rate = g.attackSpeed * Buffs.AttackSpeedMul(g)
    if (g.adrenaline or 0) > 0 then rate = rate * 1.25 end
    local p = g.player
    local target, distance = Nearest(g)
    if not target then return end
    local nx, ny = Direction(p.x, p.y, target.x, target.y)
    if Loadout.Has(g,"keyboard")and g.meleeTimer <= 0 and distance < 106 * g.range + target.radius and not ActionState.Active(g, "keyboard") then
        local action = ActionState.Start(g, "keyboard", nx, ny, rate)
        if action then
            g.meleeTimer = math.max(action.duration, 0.64 / rate) + math.max(-dt, g.meleeTimer)
        end
    end
    if Loadout.Has(g,"stapler")and g.stapler > 0 and g.staplerTimer <= 0 and not ActionState.Active(g, "stapler") then
        local action = ActionState.Start(g, "stapler", nx, ny)
        if action then
            -- 林夏霰弹节奏更慢（1.05s 起、每级 -10%）；其他人保持原订书机 0.75s 起、每级 -16%。
            -- 用 (stapler-1) 而不是 stapler，保证 L1 就是 1.05s（§3.2 的 DPS 推导按这个口径写的）。
            local shotgun = g.primaryWeapon == "stapler"
            local base = shotgun and 1.05 or 0.75
            local growth = shotgun and (1 + (g.stapler - 1) * .10) or (1 + g.stapler * .16)
            g.staplerTimer = base / (Scaling.Growth(g, 1.16, growth) * rate) + math.max(-dt, g.staplerTimer)
        end
    end
    if Loadout.Has(g,"coffee")and g.coffee > 0 and g.coffeeTimer <= 0 and not ActionState.Active(g, "coffee") then
        local action = ActionState.Start(g, "coffee", nx, ny)
        if action then
            action.targetX, action.targetY = target.x, target.y
            g.coffeeTimer = 3.3 / (Scaling.Growth(g,1.15,1+.15*g.coffee)*rate) + math.max(-dt, g.coffeeTimer)
        end
    end
    -- S2 保温杯：近战三段，扇区半径 96+6L，只打面前 ±97°，第三段额外击退+眩晕+枸杞池。
    local thermosLevel = Weapons.Level(g, "thermos")
    if Loadout.Has(g,"thermos")and thermosLevel > 0 and Weapons.Timer(g, "thermos") <= 0
        and distance < Weapons.ThermosRadius(thermosLevel,g) * g.range + target.radius
        and not ActionState.Active(g, "thermos") then
        local action = ActionState.Start(g, "thermos", nx, ny, rate)
        if action then
            Weapons.SetTimer(g, "thermos", Weapons.ThermosCooldown(rate) + math.max(-dt, Weapons.Timer(g, "thermos")))
        end
    end
    -- S2 回形针弹弓：远程穿透，弹速 640、life 0.62，每5发追加一枚强化直线弹。
    local clipLevel = Weapons.Level(g, "paperclip")
    if Loadout.Has(g,"paperclip")and clipLevel > 0 and Weapons.Timer(g, "paperclip") <= 0 and not ActionState.Active(g, "paperclip") then
        local action = ActionState.Start(g, "paperclip", nx, ny, rate)
        if action then
            Weapons.SetTimer(g, "paperclip", Weapons.PaperclipCooldown(rate) + math.max(-dt, Weapons.Timer(g, "paperclip")))
        end
    end
    -- S2 画饼充饥：抛物线爆炸 + 落点饼池，射程夹 60..300。
    local pieLevel = Weapons.Level(g, "pie")
    if Loadout.Has(g,"pie")and pieLevel > 0 and Weapons.Timer(g, "pie") <= 0 and not ActionState.Active(g, "pie") then
        local action = ActionState.Start(g, "pie", nx, ny, rate)
        if action then
            action.targetX, action.targetY = target.x, target.y
            Weapons.SetTimer(g, "pie", Weapons.PieCooldown(pieLevel,g)/rate + math.max(-dt, Weapons.Timer(g, "pie")))
        end
    end
    if Loadout.Has(g,"folder")and g.primaryTimer<=0 and distance<145*g.range+target.radius then
        local a=ActionState.Start(g,"folder",nx,ny,rate)
        if a then g.primaryTimer=2.4/(rate*(1+.12*Buffs.EffectLevel(g,"internTempo")))end
    elseif Loadout.Has(g,"binary")and g.primaryTimer<=0 then
        local a=ActionState.Start(g,"binary",nx,ny,rate)
        if a then
            g.primaryTimer=math.max(.16,.28/(rate*(1+.10*Buffs.Level(g,"cacheWarmup"))*((g.overclock or 0)>0 and 1.35 or 1)))
            g.typingUntil=g.time+.45
        end
    end
end

---@param g table
---@param action OfficeAction
local function ActionImpact(g, action)
    local p = g.player
    local firstShot=#g.shots+1
    local nx, ny = action.faceX, action.faceY
    if action.name=="summon"then Fufu.PerformSummon(g)
    elseif action.name=="bulb"then Fufu.FireBulb(g,action)
    elseif action.name=="folder"then
        local radius=(118+12*Buffs.EffectLevel(g,"folderReinforced"))*g.range
        local x,y=p.x+nx*55,p.y+ny*55
        Effect(g,"folderSlam",x,y,.4,radius*2,math.atan(ny,nx))
        for _,e in ipairs(g.enemies)do if e.hp>0 and Distance(x,y,e.x,e.y)<radius+e.radius and Visible(g,x,y,e.x,e.y)then
            Game.Hit(g,e,110*(1+.25*Buffs.EffectLevel(g,"folderReinforced")),nx,ny,280,
                { rageScale = FOLDER_KILL_RAGE_SCALE })
        end end
        g.shake=math.max(g.shake,4);Sound(g,"hit")
    elseif action.name=="binary"then
        g.binaryCount=(g.binaryCount or 0)+1
        local count=1+Buffs.Level(g,"parallelThreads")+((g.overclock or 0)>0 and 1 or 0)
        -- 周序专精：子弹随等级成长（每级 +0.9 基础伤害），并且自带 1 次穿透。
        -- 敌人血量按波次指数上涨，固定 9 点单发到中期会直接失去清场能力（实测 F3 清怪 4 只）。
        local bullet=12+3*Buffs.Level(g,"codeExploit")+math.floor((g.level-1)*.9)
        for i=1,count do if #g.shots>=128 then break end;local a=math.atan(ny,nx)+(i-(count+1)/2)*.10
            g.shots[#g.shots+1]={x=p.x,y=p.y,vx=math.cos(a)*650,vy=math.sin(a)*650,life=1,damage=bullet,
                pierce=1+Buffs.Level(g,"codeExploit"),hit={},kind="binary",digit=g.binaryCount%2,actionSerial=action.serial}
        end
        Effect(g,"codeCast",p.x+nx*15,p.y-28,.12,45,math.atan(ny,nx));Sound(g,"staple")
    elseif action.name == "keyboard" then
        -- 圆r(100*range)+朝向扇区；蓄力锁向，命中以此刻脚下位置判定；墙体先过滤。
        -- 扇区由 ±97°（dot > -0.12）收到 ±93°（dot > -0.05），射程 104→100，整体覆盖面积 -11.4%。
        Effect(g, "slash", p.x, p.y, action.impactEnd - action.impactAt, 100 * g.range, math.atan(ny, nx))
        local landed = false
        for _, e in ipairs(g.enemies) do
            local ex, ey, d = Direction(p.x, p.y, e.x, e.y)
            if e.hp > 0 and d < 100 * g.range + e.radius and ex * nx + ey * ny > -0.05
                and Visible(g, p.x, p.y, e.x, e.y) then
                Game.Hit(g, e, 27, ex, ey, 150)
                landed = true
            end
        end
        Sound(g, "swing")
        if landed then
            -- Basic hits keep their impact feedback without freezing movement
            -- and every enemy/projectile on two consecutive display frames.
            g.shake = math.max(g.shake, 2.5)
            Sound(g, "hit")
        end
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
        Sound(g, "staple")
    elseif action.name == "coffee" then
        -- 蓄力期间移动到墙后时，落点沿可见线截断；不隔墙追踪敌人。
        local nav = RoomNavigation(g)
        local t, blocked = Navigation.Trace(nav, p.x, p.y, action.targetX, action.targetY, 4)
        local safeT = blocked and math.max(0, t - 0.02) or 1
        local targetX = p.x + (action.targetX - p.x) * safeT
        local targetY = p.y + (action.targetY - p.y) * safeT
        local x, y = Navigation.Project(nav, targetX, targetY, 4, p.x, p.y)
        if x and y and Visible(g, p.x, p.y, x, y, 4) then
            g.pools[#g.pools + 1] = { x = x, y = y, radius = Scaling.Growth(g,62,48+g.coffee*14), life = 3.6, tick = 0,
                actionSerial = action.serial }
            Effect(g, "coffee", x, y, 0.4, 50)
            Sound(g, "coffee")
        end
    elseif action.name == "thermos" then
        -- S2 保温杯：扇区 96+6L，只打面前 ±97°，第三段 ×1.45 + 468 击退 + 0.25 眩晕 + 枸杞池。
        local level = Weapons.Level(g, "thermos")
        g.thermosCombo = ((g.thermosCombo or 0) % 3) + 1
        local third = g.thermosCombo == 3
        local radius = Weapons.ThermosRadius(level,g) * g.range
        local damage = Weapons.ThermosDamage(level,g) * (third and 1.45 or 1)
        local knock = third and 468 or 260
        Effect(g, "thermosSmash", p.x, p.y, action.impactEnd - action.impactAt, radius, math.atan(ny, nx))
        local landed = false
        for _, e in ipairs(g.enemies) do
            local ex, ey, d = Direction(p.x, p.y, e.x, e.y)
            if e.hp > 0 and d < radius + e.radius and ex * nx + ey * ny > -0.12
                and Visible(g, p.x, p.y, e.x, e.y) then
                Game.Hit(g, e, damage, ex, ey, knock)
                if e.hp > 0 and third then e.stunTimer = math.max(e.stunTimer or 0, 0.25) end
                landed = true
            end
        end
        if third then
            -- 第三段砸碎地板：脚下留一圈枸杞池（pool.kind = "thermos"），持续 3.0 秒。
            g.pools[#g.pools + 1] = { x = p.x, y = p.y, radius = 64, life = 3.0, tick = 0,
                kind = "thermos", poolDamage = Weapons.ThermosPoolDamage(level,g), actionSerial = action.serial }
            g.thermosCombo = 0
        end
        Sound(g, "thermosSwing")
        if landed then g.shake = math.max(g.shake, third and 5 or 2.5); Sound(g, "thermosHit") end
    elseif action.name == "paperclip" then
        -- 回形针直线穿透；每第5发追加更强的直线弹，不含追踪或减速。
        local level = Weapons.Level(g, "paperclip")
        Effect(g,"paperclipCast",p.x+nx*18,p.y-25,.18,42,math.atan(ny,nx))
        local angle = math.atan(ny, nx)
        local damage = Weapons.PaperclipDamage(level,g)
        local pierce = Scaling.Count(g,"paperclip-pierce",Weapons.PaperclipPierce(level,g))
        g.paperclipCount = (g.paperclipCount or 0) + 1
        g.shots[#g.shots + 1] = { x = p.x, y = p.y, vx = math.cos(angle) * 640, vy = math.sin(angle) * 640,
            life = 0.62, damage = damage, pierce = pierce, hit = {}, kind = "paperclip", actionSerial = action.serial }
        if g.paperclipCount % 5 == 0 then
            -- 第五发：正前方再补一发射速略高的大号回形针。
            g.shots[#g.shots + 1] = { x = p.x, y = p.y, vx = math.cos(angle) * 700, vy = math.sin(angle) * 700,
                life = 0.62, damage = math.floor(damage * 1.4), pierce = pierce + 1, hit = {},
                kind = "paperclip", actionSerial = action.serial }
        end
        Sound(g, "paperclipShot")
    elseif action.name == "pie" then
        -- S2 画饼：抛物线飞向锁定的落点（射程夹 60..300），命中即爆炸并留下饼池。
        local level = Weapons.Level(g, "pie")
        local nav = RoomNavigation(g)
        local distance = math.max(0.001, Distance(p.x, p.y, action.targetX or p.x, action.targetY or p.y))
        local travel = Weapons.PieRange(distance)
        local tx = p.x + nx * travel
        local ty = p.y + ny * travel
        local t, blocked = Navigation.Trace(nav, p.x, p.y, tx, ty, 4)
        local safeT = blocked and math.max(0, t - 0.02) or 1
        local x, y = Navigation.Project(nav, p.x + (tx - p.x) * safeT, p.y + (ty - p.y) * safeT, 4, p.x, p.y)
        if x and y then
            -- flight 是初始寿命：Draw 用它算抛物线进度 t = 1 - life/flight，
            -- 少了这个字段 Draw 只能按 life 从 1.0 起算，饼会从半空画起。
            g.shots[#g.shots + 1] = { x = p.x, y = p.y, vx = (x - p.x) / 0.45, vy = (y - p.y) / 0.45,
                life = 0.45, flight = 0.45, damage = Weapons.PieDamage(level,g), pierce = 9, hit = {},
                kind = "pie", explode = true, level = level, actionSerial = action.serial }
        end
        Sound(g, "pieThrow")
    elseif action.name == "burst" then BurstImpact(g) end
    if(action.name=="stapler"or action.name=="paperclip"or action.name=="binary"or action.name=="bulb")and g.shots[firstShot]then
        local extra=Buffs.ExtraProjectiles(g)
        for i=1,extra do if #g.shots>=128 then break end
            local copy={};for k,v in pairs(g.shots[firstShot])do copy[k]=v end;copy.hit={};g.shots[#g.shots+1]=copy
        end
    end
end

-- S3：第 7 参双口径。旧调用传 kind（1=ranged、2=环形），伤害写死在 UpdateShots 里；
-- Enemies.lua 传的是伤害值（11/13/15/21/22，必然 >= 3），此时写入 s.damage 并清空 kind。
local function HostileShot(g, x, y, nx, ny, speed, kind)
    if #g.hostileShots >= 110 or Blocked(g, x, y, 6) then return end
    local shot = { x = x, y = y, vx = nx * speed, vy = ny * speed, life = 7, kind = kind }
    if type(kind) == "number" and kind >= 3 then
        shot.kind, shot.damage = nil, kind
    end
    g.hostileShots[#g.hostileShots + 1] = shot
end
Game.HostileShot = HostileShot

local function EnemyImpact(g,e,a)
    local nx,ny=a.faceX,a.faceY
    local bossFloor=e.bossFloor or g.floor
    -- S3：相位越高伤害越高（BossPhases.DamageMul：1.00/1.10/1.25），对小怪恒为 1。
    local dmgMul = BossPhases.DamageMul(e)
    if a.kind=="melee" then
        if Fufu.EnemyMelee(g,e,e.damage*dmgMul)then return
        elseif Distance(e.x,e.y,g.player.x,g.player.y)<e.radius+36 and Visible(g,e.x,e.y,g.player.x,g.player.y)then
            TakeDamage(g,e.damage*dmgMul)
        end
    elseif a.kind=="ranged" then
        local victim=Fufu.EnemyTarget(g,e)
        if Visible(g,e.x,e.y,victim.x,victim.y,6)then
            HostileShot(g,e.x,e.y,nx,ny,130,math.floor(e.damage*dmgMul+0.5))
        end
    elseif a.kind=="volley"then
        -- S3：弹数由相位决定（P1=1段基础弹幕 / P2=3 / P3=5 的倍率），F1 扇形、F2/F3 环形。
        local phaseBullets = BossPhases.BulletCount(e)
        if bossFloor==1 then
            local base = phaseBullets > 1 and 5 or 3
            local count = base + (phaseBullets - 1) * 2
            for i=1,count do local angle=math.atan(ny,nx)+(i-(count+1)/2)*.22
                HostileShot(g,e.x,e.y,math.cos(angle),math.sin(angle),145,math.floor(e.damage*dmgMul+0.5))end
        else
            local base = phaseBullets > 1 and 18 or 12
            local count = base + (phaseBullets - 1) * 3
            local skill = (g.endless and g.endless.active) and (g.endless.bossSkill or 1) or 0
            if skill>0 then count = count + ({0,4,8,12,16})[skill] end
            if count > 70 then count = 70 end
            local start=math.atan(ny,nx)
            for i=2,count-1 do local angle=start+i/count*math.pi*2
                HostileShot(g,e.x,e.y,math.cos(angle),math.sin(angle),bossFloor==3 and 120 or 100,math.floor(e.damage*dmgMul+0.5))end
            -- 秃头主管 P3 召唤：数量与种类都由 BossPhases 决定（F2 P3 = 2 只 kind 2）。
            local summons = BossPhases.SummonCount(e)
            if summons > 0 and #g.enemies < 6 then
                local summonKind = BossPhases.SummonKind(e)
                for s = 1, summons do
                    Game.Spawn(g, summonKind, 110 + (s - 1) * 820, 200)
                end
            end
            if bossFloor==3 and phaseBullets > 1 and #g.enemies<6 then
                Game.Spawn(g,1,110,200)
                if skill>=4 then Game.Spawn(g,1,930,200) else Game.Spawn(g,2,930,200) end
                if skill>=5 then Game.Spawn(g,2,760,200) end
            end
        end
    end
end

local function UpdateBoss(g,e,dt)
    local nx,ny=Direction(e.x,e.y,g.player.x,g.player.y)
    local bossFloor=e.bossFloor or g.floor
    local endlessBoss = g.endless and g.endless.active
    -- S3：三阶段状态机全部交给 BossPhases（66%/33% 只升不降，同时镜像 g.bossPhase 给血条文案）。
    -- 无尽模式沿用 05 的 phaseAt 阈值下压：先按 phaseAt 把相位预推到 P2，Tick 只升不降不会回退。
    local b = BossPhases.Init(e)
    if endlessBoss and (e.maxHp or 0) > 0 and b.phase < 2 then
        local phaseAt = g.endless.phaseAt or 0.5
        if e.hp < e.maxHp * phaseAt then b.phase = 2 end
    end
    local before = b.phase
    local phase = BossPhases.Tick(g, e, dt)
    if phase > before then
        Game.Announce(g, BossPhases.OnPhaseChange(g, e, phase), 3)
        Sound(g, "boss")
        -- 换阶段的瞬间给一个破防窗口，让玩家把攒着的输出打进去（03 §4.0）。
        if phase >= 2 then BossPhases.OpenBreak(e, phase >= 3 and 1.2 or 0.8) end
    end
    g.bossHp = math.max(0, e.hp)
    if BossPhases.BreakWindow(e) then
        -- 破防：站桩、不冲刺、不补弹，只把攻击计时压住不倒扣。
        e.dashing = false
        if g.bossTimer < 0 then g.bossTimer = 0 end
        return
    end
    local cdMul = BossPhases.CooldownMul(e)/(e.attackRate or 1)
    local speedMul = BossPhases.SpeedMul(e)
    g.bossTimer=g.bossTimer-dt
    e.dashing=false
    -- F1 工贼同事 P3：每 6s 一次到点冲锋（消费式，读一次即清）。
    if BossPhases.WantsCharge(e) and not e.enemyAction then
        EnemyAnimation.Start(e,"dash",nx,ny)
        g.dashTimer,g.dashX,g.dashY=1.0,nx,ny
        Effect(g,"warning",e.x,e.y,.85,500,math.atan(ny,nx))
    end
    if g.dashTimer>0 then
        g.dashTimer=math.max(0,g.dashTimer-dt)
        if g.dashTimer<.5 then
            e.dashing=true;Move(g,e,g.dashX*310*dt,g.dashY*310*dt,e.radius)
        end
    elseif not e.enemyAction then Chase(g,e,g.player.x,g.player.y,e.speed*speedMul,dt)end
    if g.bossTimer<=0 and not e.enemyAction then
        -- 相位越高出招越密：P2/P3 的出手间隔按 CooldownMul 缩短。
        g.bossTimer=((BossPhases.BulletCount(e) > 1) and 2.5 or 3.4) * cdMul
        g.bossAttack=g.bossAttack+1
        if bossFloor~=1 and g.bossAttack%(bossFloor==3 and 2 or 3)==0 then
            EnemyAnimation.Start(e,"dash",nx,ny)
            local dashCd = 1.35
            if endlessBoss then dashCd = math.max(0.6, 1.35 - 0.10 * ((g.endless.bossSkill or 1) - 1)) end
            g.dashTimer,g.dashX,g.dashY=dashCd,nx,ny
            Effect(g,"warning",e.x,e.y,.85,500,math.atan(ny,nx))
        else EnemyAnimation.Start(e,"volley",nx,ny)end
    end
end

-- S3 波次投放表：{累积权重上界, kind} 数组，最后一项必须是 1.00 兜底。
-- 第一层起引入冲撞/弹幕/自爆，第二层加入护盾和召唤；新怪占比32%/60%/70%。
-- 无尽模式另用Endless.PickKind的按波权重。
local WAVE_POOL = {
    { { .22,1 },{ .44,2 },{ .60,3 },{ .68,4 },{ .81,6 },{ .94,7 },{ 1,11 } },
    { { .12,1 },{ .24,2 },{ .34,3 },{ .40,4 },{ .57,6 },{ .74,7 },{ .86,11 },{ .94,12 },{ 1,13 } },
    { { .08,1 },{ .16,2 },{ .24,3 },{ .30,4 },{ .47,6 },{ .64,7 },{ .78,11 },{ .90,12 },{ 1,13 } },
}

-- 按层抽一个 kind。floor > 3（程序化地牢更深层预留）沿用第 3 层配置。
local function WaveKind(g)
    local row = WAVE_POOL[g.floor] or WAVE_POOL[3]
    local r = math.random()
    for _, entry in ipairs(row) do
        if r <= entry[1] then return entry[2] end
    end
    return row[#row][2]
end
Game.WaveKind = WaveKind

local function UpdateEnemies(g,dt)
    local neighborhoods=#g.enemies>16 and EnemyNeighborhood.Build(g.enemies)or nil
    for i=#g.enemies,1,-1 do
        local e=g.enemies[i]
        if e.hp<=0 then table.remove(g.enemies,i)
        else
            local oldX,oldY=e.x,e.y
            e.hit,e.shootTimer=math.max(0,e.hit-dt),e.shootTimer-dt
            if g.heroId~="fufu"or(e.stunTimer or 0)<=0 then EnemyAnimation.Step(g,e,dt,EnemyImpact)end
            local nx,ny,dist=Direction(e.x,e.y,g.player.x,g.player.y)
            e.reflectCd=math.max(0,(e.reflectCd or 0)-dt)
            if e.reflectPending then
                e.reflectPending=e.reflectPending-dt
                if e.reflectPending<=0 then
                    e.reflectPending=nil
                    if dist<180 and Visible(g,e.x,e.y,g.player.x,g.player.y)then TakeDamage(g,math.min(3,e.damage*.15))end
                end
            end
            e.shieldQuiet=(e.shieldQuiet or 0)+dt
            if e.affix=="shield"and e.shieldQuiet>3 then e.shield=math.min(e.shieldMax,e.shield+e.shieldMax*.12*dt)end
            if e.affix=="summon"and(e.summonsLeft or 0)>0 then
                e.summonTimer=e.summonTimer-dt
                if e.summonTimer<=0 and #g.enemies<Difficulty.AliveCap(Difficulty.Wave(g))then
                    e.summonTimer=4.5;e.summonsLeft=e.summonsLeft-1
                    local child=Game.Spawn(g,1,e.x+35,e.y)
                    if child then child.affix=nil;child.elite=false end
                end
            end
            if e.affix=="volatile"then
                if not e.blastTimer and dist<80 then e.blastTimer=.7;Effect(g,"warning",e.x,e.y,.7,90,0)end
                if e.blastTimer then
                    e.blastTimer=e.blastTimer-dt
                    if e.blastTimer<=0 then
                        if dist<90 and Visible(g,e.x,e.y,g.player.x,g.player.y)then TakeDamage(g,e.damage*1.3)end
                        e.affix=nil;e.shield=0;e.stunTimer=1;Game.TrueHit(g,e,e.hp/math.max(.01,g.damage)+1,0,0,0)
                    end
                end
            end
            local slow=1
            -- 减速只认咖啡池（kind == nil）：枸杞池和饼池是伤害池，不该顺手减速。
            for _,pool in ipairs(g.pools)do
                if pool.kind == nil and Distance(e.x,e.y,pool.x,pool.y)<pool.radius
                    and Visible(g,pool.x,pool.y,e.x,e.y)then slow=.48;break end
            end
            -- S2 眩晕：男大招（1.2s）与保温杯三段（0.25s）会写 e.stunTimer。
            -- 眩晕期间 AI 与移动全部冻结，只保留下面的击退位移；计时在本帧统一递减一次，
            -- 因此 kind >= 6 的 Enemies.Step 只在非眩晕帧调用（它内部那行递减此时是空转）。
            local stunned = (e.stunTimer or 0) > 0
            if stunned then e.stunTimer = math.max(0, e.stunTimer - dt) end
            -- S3：kind >= 6 的新怪走 Enemies.Step；返回 true 表示它已自行接管移动与攻击，跳过默认 AI。
            if stunned then
                -- 冻结帧：不移动、不出招，等 stunTimer 走完。
            elseif e.kind >= 6 and e.kind ~= 14 and Enemies.Step and Enemies.Step(g, e, dt, slow) then
                -- 已接管：只保留击退与朝向同步，避免重复 Move。
            -- 待登场首领（进 boss 房后 1 秒内）不出招、不移动、不推进相位：登场动作与首招计时一起延后。
            elseif e.kind==5 or e.kind==14 then if g.pendingBoss ~= e then UpdateBoss(g,e,dt) end
            else
                local victim=Fufu.EnemyTarget(g,e)
                nx,ny,dist=Direction(e.x,e.y,victim.x,victim.y)
                local speed=math.min(120,e.speed)*slow
                local lineOfFire=e.kind==3 and Visible(g,e.x,e.y,victim.x,victim.y,6)
                if not e.enemyAction then
                    if e.kind==3 and lineOfFire and e.shootTimer<=0 and dist<480 then
                        e.shootTimer=2.6/(e.attackRate or 1);EnemyAnimation.Start(e,"ranged",nx,ny)
                    elseif e.kind~=3 and dist<e.radius+30 and(e.attackCooldown or 0)<=0
                        and Visible(g,e.x,e.y,victim.x,victim.y)then
                        e.attackCooldown=.95/(e.attackRate or 1);EnemyAnimation.Start(e,"melee",nx,ny)
                    else
                        if e.kind==3 and lineOfFire and dist<230 then speed=dist<150 and -speed*.7 or 0 end
                        if speed>0 then Chase(g,e,victim.x,victim.y,speed,dt)
                        else Move(g,e,nx*speed*dt,ny*speed*dt,e.radius)end
                    end
                end
                local nearby=neighborhoods and EnemyNeighborhood.Candidates(neighborhoods,e.x,e.y,i)or nil
                for candidate=1,nearby and #nearby or math.min(i-1,70)do
                    local j=nearby and nearby[candidate]or candidate
                    local other=g.enemies[j];local dx,dy=e.x-other.x,e.y-other.y
                    local minDist=e.radius+other.radius-3
                    if math.abs(dx)<minDist and math.abs(dy)<minDist and dx*dx+dy*dy<minDist*minDist then
                        local separation=math.sqrt(dx*dx+dy*dy)
                        local sx,sy=separation<.01 and 1 or dx/math.max(.001,separation),separation<.01 and 0 or dy/math.max(.001,separation)
                        Move(g,e,sx*22*dt,sy*22*dt,e.radius)
                    end
                end
            end
            if math.abs(e.knockX)+math.abs(e.knockY)>1 then
                Move(g,e,e.knockX*dt,e.knockY*dt,e.radius)
                local decay=math.max(0,1-dt*9);e.knockX,e.knockY=e.knockX*decay,e.knockY*decay
            end
            local dx,dy=e.x-oldX,e.y-oldY;e.moving=dx*dx+dy*dy>.000001
            if not e.enemyAction then
                if e.moving then local n=math.sqrt(dx*dx+dy*dy);e.faceX,e.faceY=dx/n,dy/n end
            end
            if (e.kind==5 or e.kind==14) and e.dashing
                and Distance(e.x,e.y,g.player.x,g.player.y)<e.radius+12 then TakeDamage(g,e.damage)end
        end
    end
    -- S2：破甲计时 / DOT 跳伤 / 标记计时都在敌侧推进，必须每帧跑一次。
    Buffs.UpdateEnemies(g, dt)
    Fufu.UpdateEnemies(g,dt)
end

local function SegmentHit(px, py, radius, ax, ay, bx, by)
    local dx, dy, ox, oy = bx - ax, by - ay, ax - px, ay - py
    local c = ox * ox + oy * oy - radius * radius
    if c <= 0 then return 0 end
    local a = dx * dx + dy * dy
    if a < 0.000001 then return nil end
    local b = ox * dx + oy * dy
    local discriminant = b * b - a * c
    if discriminant < 0 then return nil end
    local t = (-b - math.sqrt(discriminant)) / a
    if t >= 0 and t <= 1 then return t end
    return nil
end

-- S2 画饼爆炸：以落点为心，爆炸半径内的敌人一起吃伤害，然后原地留一圈饼池。
-- pool.kind = "pie" 让 Draw 用金色池 + 快速淡出，也让下方池子伤害段走 poolDamage 而不是咖啡公式。
local function PieExplode(g, x, y, levelBytes)
    local p = g.player
    -- 向后兼容：level 走数值（Weapons.Level(g,"pie")），不信任弹体里缓存的旧值。
    local level = Weapons.Level(g, "pie")
    if level < 1 then level = 1 end
    local radius = Weapons.PieExplodeRadius(level,g)
    Effect(g, "pieBoom", x, y, 0.42, radius)
    g.shake = math.max(g.shake, 4)
    for _, e in ipairs(g.enemies) do
        local nx, ny, d = Direction(x, y, e.x, e.y)
        if e.hp > 0 and d < radius + e.radius and Visible(g, x, y, e.x, e.y) then
            Game.Hit(g, e, Weapons.PieDamage(level,g), nx, ny, 110)
        end
    end
    g.pools[#g.pools + 1] = { x = x, y = y, radius = Weapons.PiePoolRadius(level,g),
        life = Weapons.PiePoolLife or 4.2, tick = 0, kind = "pie",
        poolDamage = Weapons.PiePoolDamage(level,g) }
    Sound(g, "pieBoom")
    Game.Particles(g, x, y, "gold", 24)
end
Game.PieExplode = PieExplode

local function UpdateShots(g, dt)
    local nav = RoomNavigation(g)
    for i = #g.shots, 1, -1 do
        local s = g.shots[i]
        local ox, oy = s.x, s.y
        local bx, by = ox + s.vx * dt, oy + s.vy * dt
        local segLen = math.sqrt((bx - ox) * (bx - ox) + (by - oy) * (by - oy))
        local wallT, wallHit = Navigation.Trace(nav, ox, oy, bx, by, 4)
        local hits = {}
        local minX,maxX,minY,maxY=math.min(ox,bx),math.max(ox,bx),math.min(oy,by),math.max(oy,by)
        for _, e in ipairs(g.enemies) do
            local radius=e.radius+4
            if e.hp > 0 and not s.hit[e] and e.x>=minX-radius and e.x<=maxX+radius
                and e.y>=minY-radius and e.y<=maxY+radius then
                local t = SegmentHit(e.x, e.y, e.radius + 4, ox, oy, bx, by)
                if t and (not wallHit or t < wallT) then hits[#hits + 1] = { enemy = e, t = t } end
            end
        end
        table.sort(hits, function(a, b) return a.t < b.t end)
        s.life = s.life - dt
        local stopT = wallT
        local explodeAtT = nil
        for _, contact in ipairs(hits) do
            local e = contact.enemy
            s.hit[e] = true
            local nx, ny = Direction(ox, oy, bx, by)
            -- 画饼是爆炸弹：命中即引爆，不做单体直伤，避免同一只怪被炸两次。
            if s.explode then
                s.life, stopT, explodeAtT = 0, contact.t, contact.t
                break
            end
            -- 回形针击退更小（70）但穿透更强；纸钉保持原 65。
            if s.kind=="bulb"then Fufu.BulbHit(g,e,s)
            else
                local mul = 1
                if s.foMin then
                    local traveled = (s.foTraveled or 0) + contact.t * segLen
                    local k = math.max(0, math.min(1, (traveled - s.foNear) / s.foRange))
                    mul = 1 - k * (1 - s.foMin)
                end
                Game.Hit(g, e, s.damage * mul, nx, ny, s.knock or 65)
                local hitFx=s.kind=="binary"and"binaryHit"or(s.kind=="paperclip"and"paperclipHit"or"stapleHit")
                Effect(g,hitFx,ox+(bx-ox)*contact.t,oy+(by-oy)*contact.t-10,.24,s.kind=="binary"and 38 or(s.kind=="paperclip"and 32 or 65),0,tostring(s.digit or 0))
            end
            s.pierce = s.pierce - 1
            if s.pierce < 0 then s.life, stopT = 0, contact.t; break end
        end
        s.foTraveled = (s.foTraveled or 0) + segLen
        s.x, s.y = ox + (bx - ox) * stopT, oy + (by - oy) * stopT
        if s.explode and (explodeAtT or wallHit or s.life <= 0) then
            PieExplode(g, s.x, s.y)
            s.life = 0
        elseif wallHit then
            s.life = 0
            local hitFx=s.kind=="bulb"and"fufuGlass"or(s.kind=="binary"and"binaryHit"or(s.kind=="paperclip"and"paperclipHit"or"stapleHit"))
            Effect(g,hitFx,s.x,s.y,.2,s.kind=="binary"and 32 or(s.kind=="paperclip"and 28 or 42),0,tostring(s.digit or 0))
        end
        if s.life <= 0 then table.remove(g.shots, i) end
    end
    for i = #g.hostileShots, 1, -1 do
        local s = g.hostileShots[i]
        local ox, oy = s.x, s.y
        local bx, by = ox + s.vx * dt, oy + s.vy * dt
        local wallT, wallHit = Navigation.Trace(nav, ox, oy, bx, by, 6)
        local playerT = SegmentHit(g.player.x, g.player.y, 18, ox, oy, bx, by)
        local petT,pet
        for _,p in ipairs(g.pets or {})do if p.hp>0 then
            local t=SegmentHit(p.x,p.y,(p.radius or 12)+6,ox,oy,bx,by)
            if t and(not petT or t<petT)then petT,pet=t,p end
        end end
        s.life = s.life - dt
        if petT and(not wallHit or petT<wallT)and(not playerT or petT<playerT)then
            Fufu.DamagePet(g,pet,s.damage or(s.kind==2 and 12 or 8));s.life=0;wallT=petT;Fufu.Cleanup(g)
        elseif playerT and (not wallHit or playerT < wallT) then
            -- S3：新怪的弹幕把伤害写在 s.damage 上（HostileShot 第 7 参）；旧弹幕保持 kind 硬编码口径。
            TakeDamage(g, s.damage or (s.kind == 2 and 12 or 8))
            s.life = 0
        end
        s.x, s.y = ox + (bx - ox) * wallT, oy + (by - oy) * wallT
        if wallHit then s.life = 0 end
        if s.life <= 0 then table.remove(g.hostileShots, i) end
    end
    for i = #g.pools, 1, -1 do
        local pool = g.pools[i]
        pool.life, pool.tick = pool.life - dt, pool.tick - dt
        if pool.tick <= 0 then
            pool.tick = 0.4
            -- S2：池子按 kind 分派伤害。kind 为 nil 的是咖啡池（旧行为，一滴一口咖啡公式）。
            for _, e in ipairs(g.enemies) do
                if e.hp > 0 and Distance(pool.x, pool.y, e.x, e.y) < pool.radius + e.radius
                    and Visible(g, pool.x, pool.y, e.x, e.y) then
                    local poolDamage = pool.poolDamage or Scaling.Growth(g,15,10+g.coffee*5)
                    Game.Hit(g, e, poolDamage, 0, 0, 0)
                end
            end
        end
        if pool.life <= 0 then table.remove(g.pools, i) end
    end
end

function Game.UpdateVisuals(g, dt)
    if g.mode=="paused"then return end
    -- Room clear and upgrade screens stop combat, but defeated actors still
    -- finish their cosmetic animation. Pausing the game freezes both clocks.
    local defeated=g.defeated or {}
    for i=#defeated,1,-1 do
        defeated[i].deathTime=defeated[i].deathTime+dt
        if defeated[i].deathTime>=.48 then table.remove(defeated,i)end
    end
    g.visualTime = g.visualTime + dt
    g.shake, g.flash = math.max(0, g.shake - dt * 24), math.max(0, g.flash - dt)
    if g.announcementTime > 0 then g.announcementTime = math.max(0, g.announcementTime - dt) end
    for i = #g.effects, 1, -1 do
        local e = g.effects[i]
        e.life = e.life - dt
        if e.life <= 0 then table.remove(g.effects, i) end
    end
    for i = #g.particles, 1, -1 do
        local p = g.particles[i]
        p.life, p.x, p.y = p.life - dt, p.x + p.vx * dt, p.y + p.vy * dt
        p.vy = p.vy + dt * 65
        if p.life <= 0 then table.remove(g.particles, i) end
    end
end

-- 第5参预留；第6参walking=true为Shift走，false强制跑，nil按摇杆幅度判断。
-- WASD/方向键幅度>=1默认跑；摇杆(0.05,.65)走，>=.65跑，速度仍保留模拟量。
---@param g table
---@param dt number
---@param moveX number
---@param moveY number
---@param _reserved any
---@param walking boolean?
function Game.Update(g, dt, moveX, moveY, _reserved, walking)
    if g.mode ~= "playing" then return end
    dt = math.max(0, math.min(dt, 0.05))
    if dt <= 0 then return end
    if g.hitStop > 0 then g.hitStop = math.max(0, g.hitStop - dt); return end
    -- P3：无尽模式自己推进波次与相位（warmup/breather/bossIntro），必须先于一切实体逻辑。
    -- 连锁升级会把 mode 切到 upgrade，这里必须立刻收手，不能让本帧剩余的实体逻辑再跑一遍。
    if g.endless and g.endless.active then
        Endless.Update(g, dt)
        if g.mode ~= "playing" then return end
    end
    g.time = g.time + dt
    -- 首领登场倒计时：进 boss 房后 1 秒才算「登场」（播报/血条/首招计时一起解冻）。
    -- 倒计时期间实体已在 enemies 里（碰撞、击杀结算、测试字段假设都不变），但不出招也不推进相位。
    if g.pendingBoss then
        g.bossDelay = (g.bossDelay or 0) - dt
        if g.bossDelay <= 0 then
            local boss = g.pendingBoss
            g.pendingBoss, g.bossDelay = nil, 0
            if boss and boss.hp > 0 and not g.bossDefeated then ActivateBoss(g, boss) end
        end
    end
    -- S2：BUFF 侧计时（护盾充能、冲刺 CD、困兽之斗判定）与男主大招肾上腺素衰减。
    Buffs.Update(g, dt)
    g.overclock=math.max(0,(g.overclock or 0)-dt)
    if g.heroId=="intern"then
        g.shieldMax=(g.hero.shield or 100)+30*Buffs.EffectLevel(g,"internProtection")
        g.shieldQuiet=(g.shieldQuiet or 0)+dt
        if g.shieldQuiet>=4 then g.shield=math.min(g.shieldMax,(g.shield or 0)+dt*12)end
    end
    if (g.adrenaline or 0) > 0 then g.adrenaline = math.max(0, g.adrenaline - dt) end
    local p = g.player
    p.invuln = math.max(0, p.invuln - dt)
    Game.Heal(g,g.regen*dt)
    g.rage = math.min(100, g.rage + dt * 2.5)
    local magnitude = math.sqrt(moveX * moveX + moveY * moveY)
    local wantsWalk = walking == true or (walking == nil and magnitude < 0.65)
    local oldX, oldY, faceX, faceY = p.x, p.y, g.locomotion.faceX, g.locomotion.faceY
    if (p.dashTimer or 0) > 0 then
        -- 瞬步位移：0.18 秒内沿 dashDir 高速前冲，摇杆不参与（无敌帧由 Buffs.StartDash 给）。
        local dashX, dashY = p.dashDirX or 1, p.dashDirY or 0
        Move(g, p, dashX * p.speed * 4.2 * dt, dashY * p.speed * 4.2 * dt, p.radius)
        faceX, faceY = dashX, dashY
    elseif magnitude > 0.05 then
        local divisor, speedScale = math.max(1, magnitude), wantsWalk and 0.55 or 1
        Move(g, p, moveX / divisor * p.speed * speedScale * dt, moveY / divisor * p.speed * speedScale * dt, p.radius)
        faceX, faceY = moveX / magnitude, moveY / magnitude
    end
    local moved = Distance(oldX, oldY, p.x, p.y)
    p.moving = moved > 0.001 -- 顶墙不播放原地滑步；攻击不会取消位移。
    p.walking, p.running = p.moving and wantsWalk, p.moving and not wantsWalk
    p.gait = p.moving and (wantsWalk and "walk" or "run") or "idle"
    ActionState.SetLocomotion(g, p.gait, faceX, faceY)
    if p.moving then
        p.stepDistance = p.stepDistance + moved
        local stride = wantsWalk and 28 or 40
        if p.stepDistance >= stride then p.stepDistance = p.stepDistance % stride; Sound(g, wantsWalk and "step_walk" or "step_run") end
    else p.stepDistance = 0 end
    g.comboTimer = math.max(0, g.comboTimer - dt)
    if g.comboTimer <= 0 then g.combo = 0 end
    Fufu.Update(g,dt)
    if g.mode~="playing"then return end
    if g.roomCleared then
        ActionState.Update(g, dt, ActionImpact)
        if g.xp >= g.xpNeed then LevelUp(g, "level"); return end
        local exit = Game.GetExit(g)
        if Distance(p.x, p.y, exit.triggerX, exit.triggerY) <= exit.radius
            and Visible(g, p.x, p.y, exit.triggerX, exit.triggerY, p.radius) then Game.OpenRoute(g) end
        return
    end
    -- P3b：无尽模式的分批刷怪会让 #g.enemies 短暂回 0，原版在此间隙自增 g.wave 并 ClearRoom，
    -- 必须整段跳过；波次推进完全交给 Endless.Update。
    if not (g.endless and g.endless.active) then
        if not g.bossSpawned and #g.enemies == 0 then
            if g.wave >= g.totalWaves then ClearRoom(g); return end
            g.waveTimer = g.waveTimer - dt
            if g.waveTimer <= 0 then
                g.wave = g.wave + 1
                local count = math.min(28,Difficulty.SpawnCount(g)+(g.room.enemyBonus or 0))
                for _ = 1, count do Game.Spawn(g, WaveKind(g)) end
                g.waveTimer = 1.2
                Game.Announce(g, g.room.name .. "  第" .. g.wave .. "/" .. g.totalWaves .. "波", 3)
                print("[波次] F" .. g.floor .. "-" .. g.roomIndex .. " wave=" .. g.wave .. " 数量=" .. #g.enemies)
            end
        elseif g.bossDefeated then ClearRoom(g); return end
    end
    ActionState.Update(g, dt, ActionImpact)
    UpdateWeapons(g, dt)
    UpdateEnemies(g, dt)
    if g.mode ~= "playing" then return end
    UpdateShots(g, dt)
    if g.mode ~= "playing" then return end
    for i = #g.gems, 1, -1 do
        local gem = g.gems[i]
        local d = Distance(gem.x, gem.y, p.x, p.y)
        local canTake=not gem.weapon or Loadout.CanAcquire(g,gem.weapon)
        if canTake and d < (gem.heal and 44 or g.magnet) then gem.attracted = true end
        if canTake and gem.attracted then
            local wx, wy = Navigation.Waypoint(RoomNavigation(g), gem, p.x, p.y, 4, g.time)
            local nx, ny, waypointDistance = Direction(gem.x, gem.y, wx, wy)
            local step = math.min(waypointDistance, (250 + math.max(0, 1 - d / math.max(1, g.magnet)) * 350) * dt)
            Move(g, gem, nx * step, ny * step, 4)
            if Distance(gem.x, gem.y, p.x, p.y) < 16 and Visible(g, gem.x, gem.y, p.x, p.y, 4) then
                if gem.weapon then Game.PickWeapon(g,gem.weapon)
                elseif gem.heal then Game.Heal(g,22); Sound(g, "choose")
                else g.xp = g.xp + (gem.value or 0); Sound(g, "pickup") end
                Effect(g,"pickup",p.x,p.y-14,.25,32)
                table.remove(g.gems, i)
            end
        end
    end
    if g.xp >= g.xpNeed then LevelUp(g) end
end

return Game

