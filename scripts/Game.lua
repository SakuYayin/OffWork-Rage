-- 《下班！别拦我》：独立于渲染的单机玩法逻辑。
local Campaign = require("Campaign")
local Heroes = require("Heroes")
local Navigation = require("Navigation")
local ActionState = require("ActionState")
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

-- 碰撞尺寸/边界ASCII设计见Navigation.lua与Campaign.lua。这里仅管理玩法：
-- 所有kind实体共用障碍数组；移动、投射物、近战、咖啡/经验吸取均不能穿墙。
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
    local x, y = Navigation.Project(nav, spawn.x, spawn.y, 12, spawn.x, spawn.y)
    assert(x and y, "房间没有可达的玩家入口")
    if x ~= spawn.x or y ~= spawn.y then
        print(string.format("[入口安全投影] F%d-%d (%.0f,%.0f) -> (%.0f,%.0f)",
            g.floor, g.roomIndex, spawn.x, spawn.y, x, y))
        spawn.x, spawn.y = x, y
    end
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
    local rooms = Campaign.Build(1)
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
        stapler = 0, coffee = 0, regen = 0, magnet = 66, armor = 0, crit = 0,
        bossSpawned = false, bossDefeated = false, bossPhase = 0, bossHp = 0, bossMaxHp = 1100,
        bossTimer = 3, bossAttack = 0, dashTimer = 0, dashX = 0, dashY = 0,
        announcement = "17:59，主管说：下班开个小会。", announcementTime = 0,
        shake = 0, flash = 0, hitStop = 0, audioQueue = {}, combo = 0, comboTimer = 0, actionSerial = 0,
    }
    local spawn = Game.GetSpawn(g)
    g.player.x, g.player.y = spawn.x, spawn.y
    ActionState.Reset(g)
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

local function Chase(g, entity, targetX, targetY, speed, dt)
    local wx, wy = Navigation.Waypoint(RoomNavigation(g), entity, targetX, targetY, entity.radius, g.time)
    local nx, ny, distance = Direction(entity.x, entity.y, wx, wy)
    local step = math.min(distance, speed * dt)
    Move(g, entity, nx * step, ny * step, entity.radius)
end
Game.Chase = Chase

function Game.Spawn(g, kind, x, y)
    local def = ENEMIES[kind]
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
    local hp = kind == 5 and Campaign.floors[g.floor].hp or math.floor(def.hp * scale)
    local e = { x = x, y = y, hp = hp, maxHp = hp, speed = def.speed, damage = def.damage + (g.floor - 1) * 3,
        xp = def.xp, radius = def.radius, kind = kind, bossFloor = g.floor, hit = 0, knockX = 0, knockY = 0,
        shootTimer = 1 + math.random() * 2, seed = math.random() * 10 }
    g.enemies[#g.enemies + 1] = e
    if kind == 5 then
        g.bossSpawned, g.bossHp, g.bossMaxHp, g.bossTimer = true, e.hp, e.hp, 2.6
        Game.Announce(g, g.bossName .. "：" .. Campaign.floors[g.floor].subtitle, 4)
        Sound(g, "boss")
        print("[首领] " .. g.bossName .. "登场，生命=" .. e.hp .. "，玩家等级=" .. g.level)
    end
    return e
end

function Game.EnterRoom(g, index)
    local room = g.rooms[index]
    if not room then return false end
    g.roomIndex, g.room, room.visited = index, room, true
    g.navigation = Navigation.New(Campaign.Obstacles(room))
    g.mode, g.roomCleared, g.rewardPending = "playing", false, false
    g.wave, g.totalWaves, g.waveTimer = 0, room.kind == "elite" and 3 or 2, 0.8
    g.enemies, g.shots, g.hostileShots, g.pools, g.gems, g.effects, g.particles = {}, {}, {}, {}, {}, {}, {}
    g.bossSpawned, g.bossDefeated, g.bossPhase, g.bossAttack, g.dashTimer = false, false, 0, 0, 0
    g.bossName, g.bossMaxHp, g.bossHp = Campaign.floors[g.floor].boss, Campaign.floors[g.floor].hp, 0
    local spawn, exit = Game.GetSpawn(g), Game.GetExit(g)
    g.player.x, g.player.y, g.player.invuln, g.player.moving = spawn.x, spawn.y, 1.5, false
    g.player.walking, g.player.running, g.player.gait, g.player.stepDistance = false, false, "idle", 0
    g.meleeTimer, g.staplerTimer, g.coffeeTimer, g.hitStop = 0, 0, 0, 0
    ActionState.Reset(g)
    print(string.format("[门数据] F%d-%d spawn=(%.0f,%.0f) exit=(%.0f,%.0f) visualBottom=%.0f",
        g.floor, index, spawn.x, spawn.y, exit.triggerX, exit.triggerY, exit.y + exit.h))
    g.uiRevision = g.uiRevision + 1
    if room.kind == "boss" then
        Game.Spawn(g, 5, 520, 230)
    elseif room.kind == "shop" then
        g.shopItems = {
            { title = "热乎饭团", desc = "恢复45点精力。", price = 30, id = "heal", sold = false },
            { title = "订书机改装", desc = "订书机等级+1，最多4级。", price = 45, id = "stapler", sold = false },
            { title = "拒绝内耗手册", desc = "所有武器伤害+25%。", price = 55, id = "damage", sold = false },
        }
        g.mode = "shop"
    elseif room.kind == "event" then
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

local function TakeDamage(g, amount)
    local p = g.player
    if p.invuln > 0 or g.mode ~= "playing" then return end
    p.hp = math.max(0, p.hp - math.max(1, amount - g.armor))
    p.invuln, g.shake, g.flash = 0.9, 5, 0.16
    g.rage = math.min(100, g.rage + 12)
    Effect(g, "hurt", p.x, p.y - 36, 0.7, 0, 0, "-" .. math.max(1, amount - g.armor))
    ActionState.Start(g, "hurt", p.faceX, p.faceY)
    Sound(g, "hurt")
    if p.hp <= 0 then
        g.mode = "lost"
        Game.Announce(g, "下班未遂，但绝不认输。", 20)
        print("[玩法] 本局结束，存活=" .. math.floor(g.time) .. "秒，击退=" .. g.kills)
    end
end
Game.TakeDamage = TakeDamage

function Game.Hit(g, e, damage, nx, ny, force)
    if e.hp <= 0 then return end
    local crit = math.random() < g.crit
    local amount = math.floor(damage * g.damage * (crit and 1.8 or 1))
    e.hp, e.hit = e.hp - amount, 0.12
    e.knockX, e.knockY = nx * (force or 95), ny * (force or 95)
    Effect(g, crit and "crit" or "damage", e.x + math.random(-9, 9), e.y - 30, 0.6, 0, 0, tostring(amount))
    if e.kind == 5 then g.bossHp = math.max(0, e.hp) end
    if e.hp > 0 then return end
    g.kills, g.combo, g.comboTimer = g.kills + 1, g.combo + 1, 2.5
    g.rage = math.min(100, g.rage + (e.kind == 4 and 7 or 3))
    Game.Particles(g, e.x, e.y - 10, e.kind == 2 and "paper" or "teal", e.kind == 5 and 65 or 9)
    if e.kind == 5 then
        g.bossDefeated, g.bossesDefeated = true, g.bossesDefeated + 1
        g.hostileShots = {}
        for _, other in ipairs(g.enemies) do other.hp = 0 end
        Game.Announce(g, g.bossName .. "已被击败！领取BUFF后前往电梯。", 8)
        Sound(g, "win")
        print("[首领] " .. g.bossName .. "已击败，等待房间结算")
    else
        g.coins = g.coins + (e.kind == 4 and 5 or 3)
        local nav = RoomNavigation(g)
        local gx, gy = Navigation.Project(nav, e.x, e.y, 4, g.player.x, g.player.y)
        if gx and gy then g.gems[#g.gems + 1] = { x = gx, y = gy, value = e.xp, heal = false, radius = 4 } end
        if g.kills % 17 == 0 then
            local hx, hy = Navigation.Project(nav, e.x + 12, e.y, 4, g.player.x, g.player.y)
            if hx and hy then g.gems[#g.gems + 1] = { x = hx, y = hy, value = 0, heal = true, radius = 4 } end
        end
    end
    if g.combo % 15 == 0 then
        local words = { "拒绝背锅！", "停止内耗！", "这不归我管！", "已读不回！" }
        Game.Announce(g, words[math.random(1, #words)] .. "  " .. g.combo .. " 连击", 1.7)
    end
    Sound(g, "hit")
end

function Game.Burst(g)
    if g.mode ~= "playing" or g.rage < 100 or ActionState.Active(g, "burst") then return false end
    local action = ActionState.Start(g, "burst", g.player.faceX, g.player.faceY)
    if not action then return false end
    g.rage, g.player.invuln = 0, math.max(g.player.invuln, 1.2)
    print("[动作] 拒绝加班蓄力 serial=" .. action.serial)
    return true
end

local function BurstImpact(g)
    g.shake, g.hitStop, g.hostileShots = 9, 0.065, {}
    Effect(g, "burst", g.player.x, g.player.y, 0.65, 260)
    Game.Particles(g, g.player.x, g.player.y, "gold", 45)
    for _, e in ipairs(g.enemies) do
        local nx, ny, d = Direction(g.player.x, g.player.y, e.x, e.y)
        if d < 260 + e.radius and Visible(g, g.player.x, g.player.y, e.x, e.y) then
            Game.Hit(g, e, 125, nx, ny, 420)
        end
    end
    Game.Announce(g, "拒绝加班！  你的时间，不属于老板。", 2.6)
    Sound(g, "burst")
    print("[动作] 拒绝加班命中，清空弹幕")
end

local UPGRADES = {
    { id = "stapler", title = "流程钉死", tag = "武器 / 订书机", desc = "解锁订书机；已拥有则增加穿透与连发。", color = "teal" },
    { id = "coffee", title = "冰美式续命", tag = "武器 / 咖啡杯", desc = "向敌群泼洒咖啡，持续伤害并减速。", color = "gold" },
    { id = "damage", title = "拒绝内耗", tag = "伤害强化", desc = "所有武器伤害 +25%。少想一点，多打一点。", color = "pink" },
    { id = "speed", title = "到点就跑", tag = "移动强化", desc = "移动速度 +15%，不再慢吞吞地假装忙碌。", color = "teal" },
    { id = "attack", title = "键盘侠", tag = "攻速强化", desc = "键盘攻击速度 +22%，输出全靠手速。", color = "purple" },
    { id = "range", title = "这不归我管", tag = "范围强化", desc = "键盘攻击范围 +20%，把麻烦推远一点。", color = "gold" },
    { id = "magnet", title = "带薪摸鱼", tag = "拾取强化", desc = "经验吸取范围 +70，顺手收下摸鱼能量。", color = "teal" },
    { id = "health", title = "先照顾自己", tag = "生命强化", desc = "生命上限 +25，立即恢复35点生命。", color = "pink" },
    { id = "regen", title = "工间休息", tag = "持续恢复", desc = "每秒恢复1.2点生命，喘口气再继续。", color = "teal" },
    { id = "armor", title = "拒绝背锅", tag = "防御强化", desc = "每次受到的伤害 -3，黑锅原路退回。", color = "purple" },
    { id = "crit", title = "已读乱回", tag = "暴击强化", desc = "暴击率 +15%，暴击造成1.8倍伤害。", color = "gold" },
    { id = "rage", title = "忍无可忍", tag = "立即爆发", desc = "立即充满怒气，并恢复20点生命。", color = "pink" },
}
Game.upgradeDefs = UPGRADES

local function LevelUp(g, source)
    g.upgradeSource = source or "level"
    if g.upgradeSource == "level" then
        g.xp, g.level = g.xp - g.xpNeed, g.level + 1
        g.xpNeed = 12 + g.level * 10
    end
    g.mode = "upgrade"
    g.player.hp = math.min(g.player.maxHp, g.player.hp + 8)
    local candidates = {}
    for _, u in ipairs(UPGRADES) do
        local count = g.upgrades[u.id] or 0
        if u.id == "rage" or count < (u.id == "stapler" and 4 or 3) then candidates[#candidates + 1] = u end
    end
    g.choices = {}
    -- 第一次升级保证出现两种新武器，尽早展示构筑差异。
    if g.level <= 2 and g.stapler == 0 and g.coffee == 0 then
        g.choices = { UPGRADES[1], UPGRADES[2], UPGRADES[3] }
    else
        for _ = 1, math.min(3, #candidates) do
            local index = math.random(1, #candidates)
            g.choices[#g.choices + 1] = table.remove(candidates, index)
        end
    end
    Sound(g, "upgrade")
    print("[玩法] 升至等级" .. g.level .. "，暂停并等待三选一")
end

function Game.Choose(g, index)
    if g.mode ~= "upgrade" or not g.choices[index] then return end
    local id = g.choices[index].id
    g.upgrades[id] = (g.upgrades[id] or 0) + 1
    if id == "stapler" then g.stapler = g.stapler + 1
    elseif id == "coffee" then g.coffee = g.coffee + 1
    elseif id == "damage" then g.damage = g.damage + 0.25
    elseif id == "speed" then g.player.speed = g.player.speed * 1.15
    elseif id == "attack" then g.attackSpeed = g.attackSpeed + 0.22
    elseif id == "range" then g.range = g.range + 0.2
    elseif id == "magnet" then g.magnet = g.magnet + 70
    elseif id == "health" then
        g.player.maxHp = g.player.maxHp + 25
        g.player.hp = math.min(g.player.maxHp, g.player.hp + 35)
    elseif id == "regen" then g.regen = g.regen + 1.2
    elseif id == "armor" then g.armor = g.armor + 3
    elseif id == "crit" then g.crit = g.crit + 0.15
    elseif id == "rage" then g.rage = 100; g.player.hp = math.min(g.player.maxHp, g.player.hp + 20)
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
    if item.id == "stapler" and g.stapler >= 4 then return false end
    if item.id == "heal" and g.player.hp >= g.player.maxHp then return false end
    g.coins, item.sold = g.coins - item.price, true
    if item.id == "heal" then g.player.hp = math.min(g.player.maxHp, g.player.hp + 45)
    elseif item.id == "stapler" then g.stapler = g.stapler + 1; g.upgrades.stapler = g.stapler
    elseif item.id == "damage" then g.damage = g.damage + 0.25 end
    g.uiRevision = g.uiRevision + 1
    Sound(g, "choose")
    print("[商店] 购买=" .. item.id .. "，余额=" .. g.coins)
    return true
end

function Game.LeaveShop(g)
    if g.mode ~= "shop" then return end
    CompleteSafeRoom(g)
end

function Game.ResolveEvent(g, index)
    if g.mode ~= "event" or not g.eventChoices[index] then return false end
    if index == 1 then
        g.player.maxHp = g.player.maxHp + 10
        g.player.hp = math.min(g.player.maxHp, g.player.hp + 40)
    elseif index == 2 then g.coins = g.coins + 50
    else g.damage, g.rage = g.damage + 0.2, 100 end
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
            g.rooms = Campaign.Build(g.floor)
            g.player.hp = math.min(g.player.maxHp, g.player.hp + 30)
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
    g.coins = g.coins + (g.room.kind == "boss" and 70 or (g.room.kind == "elite" and 40 or 20))
    for _, gem in ipairs(g.gems) do
        if gem.heal then g.player.hp = math.min(g.player.maxHp, g.player.hp + 22)
        else g.xp = g.xp + gem.value end
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
    -- 冷却各自独立；一个武器的完整收招不会吞掉另一武器的到期发射。
    g.meleeTimer, g.staplerTimer, g.coffeeTimer = g.meleeTimer - dt, g.staplerTimer - dt, g.coffeeTimer - dt
    local p = g.player
    local target, distance = Nearest(g)
    if not target then return end
    local nx, ny = Direction(p.x, p.y, target.x, target.y)
    if g.meleeTimer <= 0 and distance < 110 * g.range + target.radius and not ActionState.Active(g, "keyboard") then
        local action = ActionState.Start(g, "keyboard", nx, ny, g.attackSpeed)
        if action then
            g.meleeTimer = math.max(action.duration, 0.64 / g.attackSpeed) + math.max(-dt, g.meleeTimer)
        end
    end
    if g.stapler > 0 and g.staplerTimer <= 0 and not ActionState.Active(g, "stapler") then
        local action = ActionState.Start(g, "stapler", nx, ny)
        if action then g.staplerTimer = 0.75 / (1 + g.stapler * 0.16) + math.max(-dt, g.staplerTimer) end
    end
    if g.coffee > 0 and g.coffeeTimer <= 0 and not ActionState.Active(g, "coffee") then
        local action = ActionState.Start(g, "coffee", nx, ny)
        if action then
            action.targetX, action.targetY = target.x, target.y
            g.coffeeTimer = 3.3 / (1 + 0.15 * g.coffee) + math.max(-dt, g.coffeeTimer)
        end
    end
end

---@param g table
---@param action OfficeAction
local function ActionImpact(g, action)
    local p = g.player
    local nx, ny = action.faceX, action.faceY
    if action.name == "keyboard" then
        -- 圆r(104*range)+朝向扇区；蓄力锁向，命中以此刻脚下位置判定；墙体先过滤。
        Effect(g, "slash", p.x, p.y, action.impactEnd - action.impactAt, 104 * g.range, math.atan(ny, nx))
        local landed = false
        for _, e in ipairs(g.enemies) do
            local ex, ey, d = Direction(p.x, p.y, e.x, e.y)
            if e.hp > 0 and d < 104 * g.range + e.radius and ex * nx + ey * ny > -0.12
                and Visible(g, p.x, p.y, e.x, e.y) then
                Game.Hit(g, e, 27, ex, ey, 150)
                landed = true
            end
        end
        Sound(g, "swing")
        if landed then
            g.shake, g.hitStop = math.max(g.shake, 2.5), math.max(g.hitStop, 0.025)
            Sound(g, "hit")
        end
    elseif action.name == "stapler" then
        local count = math.min(3, g.stapler)
        for i = 1, count do
            local angle = math.atan(ny, nx) + (i - (count + 1) / 2) * 0.14
            -- 从脚下碰撞圆心出发，枪口只用于表现；移动中仍用起手锁定的方向。
            g.shots[#g.shots + 1] = { x = p.x, y = p.y, vx = math.cos(angle) * 530,
                vy = math.sin(angle) * 530, life = 1.5, damage = 20 + 5 * g.stapler,
                pierce = g.stapler, hit = {}, actionSerial = action.serial }
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
            g.pools[#g.pools + 1] = { x = x, y = y, radius = 48 + g.coffee * 14, life = 3.6, tick = 0,
                actionSerial = action.serial }
            Effect(g, "coffee", x, y, 0.4, 50)
            Sound(g, "coffee")
        end
    elseif action.name == "burst" then BurstImpact(g) end
end

local function HostileShot(g, x, y, nx, ny, speed, kind)
    if #g.hostileShots >= 110 or Blocked(g, x, y, 6) then return end
    g.hostileShots[#g.hostileShots + 1] = { x = x, y = y, vx = nx * speed, vy = ny * speed, life = 7, kind = kind }
end

local function UpdateBoss(g, e, dt)
    local nx, ny = Direction(e.x, e.y, g.player.x, g.player.y)
    if e.hp < e.maxHp * 0.5 and g.bossPhase == 0 then
        g.bossPhase = 1
        Game.Announce(g, g.bossName .. (g.floor == 1 and "：我要向老板举报你！" or (g.floor == 2 and "：最后再补充一点！" or "：谁允许你下班了！")), 3)
        Sound(g, "boss")
    end
    g.bossTimer = g.bossTimer - dt
    if g.dashTimer > 0 then
        g.dashTimer = g.dashTimer - dt
        if g.dashTimer < 0.5 then Move(g, e, g.dashX * 310 * dt, g.dashY * 310 * dt, e.radius) end
    else
        Chase(g, e, g.player.x, g.player.y, e.speed, dt)
    end
    if g.bossTimer <= 0 then
        g.bossTimer = g.bossPhase == 1 and 2.5 or 3.4
        g.bossAttack = g.bossAttack + 1
        if g.floor == 1 then
            -- 工贼同事：朝玩家扔三连周报，半血后五连，侧移即可避开。
            local count = g.bossPhase == 1 and 5 or 3
            for i = 1, count do
                local a = math.atan(ny, nx) + (i - (count + 1) / 2) * 0.22
                HostileShot(g, e.x, e.y, math.cos(a), math.sin(a), 145, 1)
            end
        elseif g.bossAttack % (g.floor == 3 and 2 or 3) == 0 then
            g.dashTimer, g.dashX, g.dashY = 1.35, nx, ny
            Effect(g, "warning", e.x, e.y, 0.85, 500, math.atan(ny, nx))
        else
            local count = g.bossPhase == 1 and 18 or 12
            local start = math.atan(ny, nx)
            for i = 1, count do
                local a = start + i / count * math.pi * 2
                -- 留出固定缺口，弹幕可躲，不做封死全屏的伤害。
                if i ~= count and i ~= 1 then HostileShot(g, e.x, e.y, math.cos(a), math.sin(a), g.floor == 3 and 120 or 100, 2) end
            end
            if g.floor == 3 and g.bossPhase == 1 and #g.enemies < 6 then
                Game.Spawn(g, 1, 110, 200)
                Game.Spawn(g, 2, 930, 200)
            end
        end
    end
end

local function UpdateEnemies(g, dt)
    for i = #g.enemies, 1, -1 do
        local e = g.enemies[i]
        if e.hp <= 0 then table.remove(g.enemies, i)
        else
            e.hit, e.shootTimer = math.max(0, e.hit - dt), e.shootTimer - dt
            local nx, ny, dist = Direction(e.x, e.y, g.player.x, g.player.y)
            local slow = 1
            for _, pool in ipairs(g.pools) do
                if Distance(e.x, e.y, pool.x, pool.y) < pool.radius and Visible(g, pool.x, pool.y, e.x, e.y) then
                    slow = 0.48; break
                end
            end
            if e.kind == 5 then UpdateBoss(g, e, dt)
            else
                local speed = e.speed * (1 + math.min(0.35, g.time / 400)) * slow
                local lineOfFire = e.kind == 3 and Visible(g, e.x, e.y, g.player.x, g.player.y, 6)
                if e.kind == 3 and lineOfFire and dist < 230 then speed = dist < 150 and -speed * 0.7 or 0 end
                if speed > 0 then Chase(g, e, g.player.x, g.player.y, speed, dt)
                else Move(g, e, nx * speed * dt, ny * speed * dt, e.radius) end
                if e.kind == 3 and lineOfFire and e.shootTimer <= 0 and dist < 480 then
                    e.shootTimer = 2.6
                    HostileShot(g, e.x, e.y, nx, ny, 130, 1)
                end
                -- 近邻分离避免成团重叠，敌人数量被限制在70以内。
                for j = 1, math.min(i - 1, 70) do
                    local other = g.enemies[j]
                    local sx, sy, separation = Direction(other.x, other.y, e.x, e.y)
                    local minDist = e.radius + other.radius - 3
                    if separation < minDist then
                        if separation < 0.01 then sx, sy = 1, 0 end
                        Move(g, e, sx * 22 * dt, sy * 22 * dt, e.radius)
                    end
                end
            end
            if math.abs(e.knockX) + math.abs(e.knockY) > 1 then
                Move(g, e, e.knockX * dt, e.knockY * dt, e.radius)
                local decay = math.max(0, 1 - dt * 9)
                e.knockX, e.knockY = e.knockX * decay, e.knockY * decay
            end
            if Distance(e.x, e.y, g.player.x, g.player.y) < e.radius + 12 then TakeDamage(g, e.damage) end
        end
    end
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

local function UpdateShots(g, dt)
    local nav = RoomNavigation(g)
    for i = #g.shots, 1, -1 do
        local s = g.shots[i]
        local ox, oy = s.x, s.y
        local bx, by = ox + s.vx * dt, oy + s.vy * dt
        local wallT, wallHit = Navigation.Trace(nav, ox, oy, bx, by, 4)
        local hits = {}
        for _, e in ipairs(g.enemies) do
            if e.hp > 0 and not s.hit[e] then
                local t = SegmentHit(e.x, e.y, e.radius + 4, ox, oy, bx, by)
                if t and (not wallHit or t < wallT) then hits[#hits + 1] = { enemy = e, t = t } end
            end
        end
        table.sort(hits, function(a, b) return a.t < b.t end)
        s.life = s.life - dt
        local stopT = wallT
        for _, contact in ipairs(hits) do
            local e = contact.enemy
            s.hit[e] = true
            local nx, ny = Direction(ox, oy, bx, by)
            Game.Hit(g, e, s.damage, nx, ny, 65)
            s.pierce = s.pierce - 1
            if s.pierce < 0 then s.life, stopT = 0, contact.t; break end
        end
        s.x, s.y = ox + (bx - ox) * stopT, oy + (by - oy) * stopT
        if wallHit then s.life = 0 end
        if s.life <= 0 then table.remove(g.shots, i) end
    end
    for i = #g.hostileShots, 1, -1 do
        local s = g.hostileShots[i]
        local ox, oy = s.x, s.y
        local bx, by = ox + s.vx * dt, oy + s.vy * dt
        local wallT, wallHit = Navigation.Trace(nav, ox, oy, bx, by, 6)
        local playerT = SegmentHit(g.player.x, g.player.y, 18, ox, oy, bx, by)
        s.life = s.life - dt
        if playerT and (not wallHit or playerT < wallT) then
            TakeDamage(g, s.kind == 2 and 12 or 8)
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
            for _, e in ipairs(g.enemies) do
                if e.hp > 0 and Distance(pool.x, pool.y, e.x, e.y) < pool.radius + e.radius
                    and Visible(g, pool.x, pool.y, e.x, e.y) then Game.Hit(g, e, 10 + g.coffee * 5, 0, 0, 0) end
            end
        end
        if pool.life <= 0 then table.remove(g.pools, i) end
    end
end

function Game.UpdateVisuals(g, dt)
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
    g.time = g.time + dt
    local p = g.player
    p.invuln = math.max(0, p.invuln - dt)
    p.hp = math.min(p.maxHp, p.hp + g.regen * dt)
    g.rage = math.min(100, g.rage + dt * 2.5)
    local magnitude = math.sqrt(moveX * moveX + moveY * moveY)
    local wantsWalk = walking == true or (walking == nil and magnitude < 0.65)
    local oldX, oldY, faceX, faceY = p.x, p.y, g.locomotion.faceX, g.locomotion.faceY
    if magnitude > 0.05 then
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
    if g.roomCleared then
        ActionState.Update(g, dt, ActionImpact)
        if g.xp >= g.xpNeed then LevelUp(g, "level"); return end
        local exit = Game.GetExit(g)
        if Distance(p.x, p.y, exit.triggerX, exit.triggerY) <= exit.radius
            and Visible(g, p.x, p.y, exit.triggerX, exit.triggerY, p.radius) then Game.OpenRoute(g) end
        return
    end
    if not g.bossSpawned and #g.enemies == 0 then
        if g.wave >= g.totalWaves then ClearRoom(g); return end
        g.waveTimer = g.waveTimer - dt
        if g.waveTimer <= 0 then
            g.wave = g.wave + 1
            local count = 3 + g.floor + (g.room.kind == "elite" and 2 or 0) + (g.wave - 1)
            for _ = 1, count do Game.Spawn(g, math.random(1, math.min(4, 2 + g.floor))) end
            g.waveTimer = 1.2
            Game.Announce(g, g.room.name .. "  第" .. g.wave .. "/" .. g.totalWaves .. "波", 2)
            print("[波次] F" .. g.floor .. "-" .. g.roomIndex .. " wave=" .. g.wave .. " 数量=" .. #g.enemies)
        end
    elseif g.bossDefeated then ClearRoom(g); return end
    ActionState.Update(g, dt, ActionImpact)
    UpdateWeapons(g, dt)
    UpdateEnemies(g, dt)
    if g.mode ~= "playing" then return end
    UpdateShots(g, dt)
    if g.mode ~= "playing" then return end
    for i = #g.gems, 1, -1 do
        local gem = g.gems[i]
        local d = Distance(gem.x, gem.y, p.x, p.y)
        if d < (gem.heal and 44 or g.magnet) then gem.attracted = true end
        if gem.attracted then
            local wx, wy = Navigation.Waypoint(RoomNavigation(g), gem, p.x, p.y, 4, g.time)
            local nx, ny, waypointDistance = Direction(gem.x, gem.y, wx, wy)
            local step = math.min(waypointDistance, (250 + math.max(0, 1 - d / math.max(1, g.magnet)) * 350) * dt)
            Move(g, gem, nx * step, ny * step, 4)
            if Distance(gem.x, gem.y, p.x, p.y) < 16 and Visible(g, gem.x, gem.y, p.x, p.y, 4) then
                if gem.heal then p.hp = math.min(p.maxHp, p.hp + 22); Sound(g, "choose")
                else g.xp = g.xp + gem.value; Sound(g, "pickup") end
                table.remove(g.gems, i)
            end
        end
    end
    if g.xp >= g.xpNeed then LevelUp(g) end
end

return Game
