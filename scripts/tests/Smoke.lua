-- 三层闯关规则回归及固定战斗截图入口；正式入口仍为main.lua。
local Game = require("Game")
local Campaign = require("Campaign")
local HeroTests = require("tests.HeroRules")
local moduleName = ...
local originalNew = Game.New
local live = originalNew()
if moduleName == nil then
    ---@param heroId string?
    Game.New = function(heroId) live = originalNew(heroId); return live end
    require("main")
end
local originalStart, originalUpdate = Start, Game.Update
local passed = 0
local function Check(value, text)
    assert(value, "[测试失败] " .. text)
    passed = passed + 1
    print("[测试通过] " .. text)
end
local function Step(g, seconds, x, y)
    for _ = 1, math.floor(seconds / 0.05) do
        Game.UpdateVisuals(g, 0.05)
        originalUpdate(g, 0.05, x or 0, y or 0)
    end
end
local function KillAll(g)
    for _, e in ipairs(g.enemies) do if e.hp > 0 then Game.Hit(g, e, 100000, 0, 1, 0) end end
end
local function Clear(g)
    for _ = 1, 120 do
        if g.mode == "upgrade" then
            if g.upgradeSource == "room" then return end
            Game.Choose(g, 1)
        end
        KillAll(g)
        g.player.invuln, g.hitStop = 99, 0
        Step(g, 0.1)
    end
    error("房间未能完成")
end
local function TestRules()
    local g = originalNew()
    Check(g.mode == "menu" and g.floor == 1 and #g.rooms == 8, "新局创建三层区域入口")
    Game.Start(g)
    Check(g.mode == "playing" and g.roomIndex == 1 and g.player.y == 580, "从首区下方出生")
    Check(not Game.OpenRoute(g) and not Game.Travel(g, 8), "战斗未完成不能越级前进")
    Step(g, 0.9)
    Check(g.wave == 1 and #g.enemies == 4, "区域有限波次生成")
    local ox, oy = g.player.x, g.player.y
    Step(g, 0.1, 1, -1)
    Check(math.abs(Game.Distance(ox, oy, g.player.x, g.player.y) - g.player.speed * 0.1) < 0.2, "斜向移动按当前角色速度归一化")
    local d = Game.GetDesks(g)[1]
    Check(Game.Blocked(g, d.x + 10, d.y + 10, 12), "当前区域工位碰撞")
    Check(not Game.Blocked(g, 520, 580, 12), "出生通道不被障碍覆盖")
    g.player.invuln = 0
    local hp = g.player.hp
    Game.TakeDamage(g, 10); Game.TakeDamage(g, 10)
    Check(g.player.hp == hp - 10, "无敌帧阻止重复受伤")
    g.rage = 100
    g.hostileShots = { { x = 100, y = 580, vx = 0, vy = 0, life = 10, kind = 1 } }
    Check(Game.Burst(g) and g.rage == 0 and g.player.invuln > 0
        and g.action.name == "burst" and g.action.time == 0 and #g.hostileShots == 1,
        "爆发起手扣怒气并无敌，但蓄力不提前清弹幕")
    Step(g, 0.1)
    Check(#g.hostileShots == 1 and not g.actionTracks.burst.impactDone, "爆发命中前保留弹幕")
    Step(g, 0.05)
    Check(#g.hostileShots == 0 and g.actionTracks.burst.impactDone, "爆发越过命中时刻才清弹幕")
    g.hitStop = 0
    g.xp = g.xpNeed
    Step(g, 0.05)
    Check(g.mode == "upgrade" and #g.choices == 3, "经验升级三选一")
    local before = g.time
    Step(g, 1)
    Check(g.time == before, "强化弹窗冻结时间")
    Game.Choose(g, 1)
    Check(g.stapler == 1 and g.mode == "playing", "首次升级解锁订书机")
    Clear(g)
    Check(g.mode == "upgrade" and g.upgradeSource == "room" and g.rewardPending, "清怪必发房间BUFF")
    Check(not g.roomCleared and not Game.OpenRoute(g), "未领取BUFF不能打开出口")
    local cleared = g.roomsCleared
    Game.Choose(g, 1)
    Check(g.roomCleared and not g.rewardPending, "领取后开门")
    g.xp = g.xpNeed
    Step(g, 0.05)
    Check(g.mode == "upgrade" and g.upgradeSource == "level", "清房经验仍可触发独立升级")
    Game.Choose(g, 1)
    Check(g.mode == "playing" and g.roomCleared, "经验升级不会再次锁住清房出口")
    g.xp = 0
    Step(g, 0.1)
    Check(g.roomsCleared == cleared, "清理奖励不会重复结算")
    Game.OpenRoute(g)
    Check(g.mode == "route" and not Game.Travel(g, 8), "路线图拒绝未连接节点")
    Check(Game.Travel(g, 3) and g.room.kind == "elite" and g.totalWaves == 3, "可以选择精英分支")
    Clear(g); Game.Choose(g, 1); Game.OpenRoute(g); Game.Travel(g, 4)
    Check(g.mode == "shop" and #g.shopItems == 3 and #g.enemies == 0, "商店是独立安全房间")
    g.coins, g.stapler = 0, 0
    Check(not Game.Buy(g, 2), "余额不足不能购买")
    g.coins = 100
    Check(Game.Buy(g, 2) and g.coins == 55 and g.stapler == 1, "商店扣币并强化武器")
    Check(not Game.Buy(g, 2) and g.coins == 55, "同一商品不能重复购买")
    Game.LeaveShop(g)
    Check(g.roomCleared and g.mode == "playing", "不强制消费也能离开商店")
    Game.OpenRoute(g); Game.Travel(g, 5)
    Check(g.mode == "event" and #g.eventChoices == 3, "每层包含事件区")
    local coins = g.coins
    Check(Game.ResolveEvent(g, 2) and g.coins == coins + 50, "事件奖励正确发放")
    Check(not Game.ResolveEvent(g, 2) and g.coins == coins + 50, "事件不能重复领取")
    Game.OpenRoute(g); Game.Travel(g, 6)
    g.xp = 0
    Clear(g); Game.Choose(g, 1); Game.OpenRoute(g); Game.Travel(g, 8)
    Check(g.bossName == "工贼同事" and g.bossHp == 540 and #Game.GetDesks(g) >= 6
        and Game.GetDesks(g) == Campaign.layouts[12] and Game.Visible(g, 520, 580, 520, 190, 24),
        "首层独立首领带实体掩体且中轴连通")
    for floor = 1, 3 do
        if floor > 1 then
            -- 后两层跳到Boss房做状态隔离，路线完整性另有图遍历测试。
            Game.EnterRoom(g, 8)
        end
        ---@type table
        local boss = g.enemies[1]
        g.xp, g.crit = 0, 0
        g.player.invuln, g.meleeTimer, g.stapler, g.coffee = 99, 99, 0, 0
        Step(g, 3)
        Check(g.bossAttack >= 1 and #g.hostileShots > 0, "第" .. floor .. "层首领发出独立弹幕")
        Game.Hit(g, boss, boss.hp * 0.6 / g.damage, 0, 1, 0)
        Step(g, 0.05)
        Check(g.bossPhase == 1, "第" .. floor .. "层首领半血强化")
        Game.Hit(g, boss, 100000, 0, 1, 0)
        Step(g, 0.1)
        Check(g.mode == "upgrade" and g.bossDefeated, "第" .. floor .. "层首领结算BUFF")
        Game.Choose(g, 1)
        g.stapler = 2
        local oldCoins, oldDamage = g.coins, g.damage
        local exit = Game.GetExit(g)
        Check(exit == g.room.exit and exit.y + exit.h == exit.triggerY, "第" .. floor .. "层电梯门底边与门槛一致")
        g.player.x, g.player.y = exit.triggerX, exit.triggerY + exit.radius + 5
        Step(g, 0.05, 0, -1) -- 实际走进本房间的门，而非旧固定坐标。
        Step(g, 0.05)
        if floor < 3 then
            Check(g.floor == floor + 1 and g.roomIndex == 1 and g.mode == "playing", "电梯进入下一层")
            Check(g.stapler == 2 and g.coins == oldCoins and g.damage == oldDamage, "跨层保留装备BUFF与金币")
            Check(not g.bossDefeated and g.wave == 0 and #g.hostileShots == 0, "跨层重置战斗状态")
        else Check(g.mode == "won" and g.bossesDefeated == 3, "第三层老板后抵达出口才通关") end
    end
    for floor = 1, 3 do
        local rooms = Campaign.Build(floor)
        local paths = 0
        local function Walk(id, shop, event)
            local room = rooms[id]
            shop, event = shop or room.kind == "shop", event or room.kind == "event"
            if room.kind == "boss" then
                Check(shop and event, "F" .. floor .. "路线必经商店和事件")
                paths = paths + 1
            end
            for _, nextId in ipairs(room.next) do Walk(nextId, shop, event) end
        end
        Walk(1, false, false)
        Check(paths == 4, "F" .. floor .. "包含四条可通关分支组合")
    end
    local loss = originalNew(); Game.Start(loss); loss.player.invuln = 0; Game.TakeDamage(loss, 999)
    Check(loss.mode == "lost", "生命归零失败")
    local fresh = originalNew()
    Check(fresh.coins == 0 and fresh.floor == 1 and fresh.bossesDefeated == 0 and fresh.stapler == 0, "重开清除本次构筑与楼层")
    HeroTests.Run(Check)
    print("[测试汇总] " .. passed .. "项三层闯关与角色布局断言全部通过")
    return passed
end

if moduleName ~= nil then return { Run = TestRules } end

function Start()
    originalStart()
    TestRules()
    Game.Start(live)
    live.room.layout = 1
    live.enemies, live.time, live.level, live.kills, live.rage = {}, 58, 5, 47, 100
    live.player.x, live.player.y, live.player.invuln = 520, 390, 0
    live.stapler, live.coffee, live.coins = 2, 1, 88
    for _, point in ipairs({ {1,405,345}, {2,637,356}, {3,710,415}, {4,330,440}, {1,593,421}, {2,422,400}, {3,825,347}, {1,226,350} }) do
        Game.Spawn(live, point[1], point[2], point[3])
    end
    live.meleeTimer = 0
    originalUpdate(live, 0.05, 0, 0)
    live.announcement, live.announcementTime = "清理区域，领取BUFF，选择你的下班路线。", 60
    Game.Update = function() end
end
