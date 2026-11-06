-- 独立纯逻辑回归；可 require("tests.HeroRules").Run()，亦可作为 Runtime 入口。
-- 不替换任何玩法函数，不修改共享角色/布局定义；随机种子固定以便复现。
local moduleName = ...
local Game = require("Game")
local Heroes = require("Heroes")
local Campaign = require("Campaign")
local Navigation = require("Navigation")
local Tests = {}
local New = Game.New

local EXPECTED = {
    { id = "male", hp = 130, speed = 188, damage = 0.85 },
    { id = "female", hp = 90, speed = 156, damage = 1.30 },
}

-- 独立圆/AABB判定：不能只用被测 Blocked() 自证移动与出生合法。
local function Solid(obstacles, x, y, radius)
    if x < 48 + radius or x > 992 - radius or y < 142 + radius or y > 628 - radius then return true end
    for _, obstacle in ipairs(obstacles) do
        local cx = math.max(obstacle.x, math.min(x, obstacle.x + obstacle.w))
        local cy = math.max(obstacle.y, math.min(y, obstacle.y + obstacle.h))
        if (x - cx) ^ 2 + (y - cy) ^ 2 < radius * radius - 0.000001 then return true end
    end
    return false
end

---@param layout integer?
---@param heroId string?
local function Fixture(layout, heroId)
    local g = New(heroId or "female")
    local layoutIndex = layout or 1
    local found = false
    for floor = 1, 3 do
        local rooms = Campaign.Build(floor)
        for index, room in ipairs(rooms) do
            if not found and room.layout == layoutIndex then
                g.floor, g.rooms, g.roomIndex, g.room = floor, rooms, index, room
                found = true
            end
        end
    end
    assert(found, "测试布局未绑定实际房间")
    g.mode = "playing"
    local obstacles = assert(Campaign.layouts[layoutIndex], "测试布局不存在")
    g.navigation = Navigation.New(obstacles)
    g.waveTimer, g.meleeTimer, g.staplerTimer, g.coffeeTimer = 999, 999, 999, 999
    g.player.invuln, g.crit = 999, 0
    return g
end

local function Tick(g, count, x, y)
    for _ = 1, count do Game.Update(g, 0.05, x or 0, y or 0) end
end

local function Stationary(g, x, y, kind)
    local enemy = assert(Game.Spawn(g, kind or 4, x, y), "测试敌人无法合法出生")
    enemy.speed, enemy.shootTimer = 0, 999
    return enemy
end

local function Near(a, b) return math.abs(a - b) < 0.00001 end

---@param externalCheck fun(value: any, message: string)?
---@return integer
function Tests.Run(externalCheck)
    math.randomseed(20261019)
    local passed = 0
    local function Check(value, message)
        if externalCheck then externalCheck(value, message)
        else
            assert(value, "[角色布局测试失败] " .. message)
            print("[角色布局测试通过] " .. message)
        end
        passed = passed + 1
    end

    Check(#Heroes.list == 2 and Heroes.list[1].id ~= Heroes.list[2].id, "两位独立可选角色")
    Check(Heroes.Get().id == "male" and Heroes.Get("not-a-hero").id == "male", "角色查询默认与非法ID回退男主")
    for _, id in ipairs({ false, "not-a-hero" }) do
        local g = New(id or nil)
        Check(g.heroId == "male" and g.player.hp == 130 and g.player.speed == 188 and Near(g.damage, 0.85),
            "Game.New默认/非法ID保留完整男主属性：" .. tostring(id))
    end

    for _, spec in ipairs(EXPECTED) do
        local hero, g = Heroes.Get(spec.id), New(spec.id)
        local label = spec.id .. " / "
        Check(hero.maxHp == spec.hp and hero.speed == spec.speed and Near(hero.damage, spec.damage), label .. "配置符合独立规格")
        Check(g.heroId == spec.id and g.hero == hero and g.player.hp == spec.hp and g.player.maxHp == spec.hp
            and g.player.speed == spec.speed and Near(g.damage, spec.damage), label .. "新局实际血量速度伤害")
        Game.Start(g)
        Check(g.heroId == spec.id and g.player.hp == spec.hp and g.player.maxHp == spec.hp
            and g.player.speed == spec.speed and Near(g.damage, spec.damage), label .. "开始不覆盖角色属性")
        g.waveTimer, g.meleeTimer = 999, 999
        local ox, oy = g.player.x, g.player.y
        Tick(g, 2, 1, 0)
        Check(Near(g.player.x - ox, spec.speed * 0.1) and Near(g.player.y, oy), label .. "实际水平移动速度")
        g.player.x, g.player.y = 520, 580
        Tick(g, 2, 1, -1)
        Check(Near(Game.Distance(520, 580, g.player.x, g.player.y), spec.speed * 0.1), label .. "实际斜向移动归一化")
        g.player.invuln = 0
        Game.TakeDamage(g, 10)
        Check(g.player.hp == spec.hp - 10, label .. "角色实际精力可受伤")

        local direct = Fixture(1, spec.id)
        local target = Stationary(direct, 570, 580)
        local hp = target.hp
        Game.Hit(direct, target, 20, 0, 0, 0)
        Check(hp - target.hp == math.floor(20 * spec.damage), label .. "实际Hit伤害倍率")

        local melee = Fixture(1, spec.id)
        local close = Stationary(melee, 570, 580)
        local closeHp = close.hp
        melee.meleeTimer = 0
        Tick(melee, 1)
        Check(close.hp == closeHp and melee.action.name == "keyboard" and melee.action.time == 0,
            label .. "真实键盘起手仅蓄力不提前伤害")
        Tick(melee, 1)
        Check(close.hp == closeHp and not melee.actionTracks.keyboard.impactDone, label .. "键盘命中前伤害为零")
        Tick(melee, 1)
        Check(closeHp - close.hp == math.floor(27 * spec.damage) and melee.actionTracks.keyboard.impactDone,
            label .. "真实键盘命中时刻应用角色伤害倍率")
        melee.meleeTimer = 999 -- 只隔离下一轮自动起手，不跳过当前收招或hitstop。
        Tick(melee, 10)
        Check(closeHp - close.hp == math.floor(27 * spec.damage) and not melee.actionTracks.keyboard,
            label .. "键盘收招结束不重复命中")

        local ranged = Fixture(1, spec.id)
        local distant = Stationary(ranged, 560, 580)
        local distantHp = distant.hp
        ranged.shots = { { x = 520, y = 580, vx = 530, vy = 0, life = 1.5, damage = 25, pierce = 0, hit = {} } }
        Tick(ranged, 1)
        Check(distantHp - distant.hp == math.floor(25 * spec.damage), label .. "真实订书机弹丸伤害")

        -- 用真正的强化、房间切换、Boss结算与电梯进入下一层，不只比对配置。
        g.mode, g.upgradeSource = "upgrade", "level"
        g.choices = { Game.upgradeDefs[4] }
        Game.Choose(g, 1)
        g.mode, g.choices = "upgrade", { Game.upgradeDefs[8] }
        Game.Choose(g, 1)
        local maxHp, speed, damage = g.player.maxHp, g.player.speed, g.damage
        Game.EnterRoom(g, 2)
        Check(g.heroId == spec.id and g.hero == hero and g.player.maxHp == maxHp
            and Near(g.player.speed, speed) and Near(g.damage, damage), label .. "跨房保留角色及构筑")
        for floor = 1, 2 do
            Game.EnterRoom(g, 8)
            local boss = assert(g.enemies[1], "Boss未生成")
            Game.Hit(g, boss, 100000, 0, 0, 0)
            Tick(g, 1)
            Check(g.mode == "upgrade" and g.bossDefeated, label .. "F" .. floor .. "真实Boss清房结算")
            Game.Choose(g, 1)
            local hpBefore, maxBefore, speedBefore, damageBefore, coinsBefore =
                g.player.hp, g.player.maxHp, g.player.speed, g.damage, g.coins
            Check(Game.OpenRoute(g) and g.floor == floor + 1 and g.roomIndex == 1, label .. "F" .. floor .. "电梯跨层")
            Check(g.heroId == spec.id and g.hero == hero and g.player.maxHp == maxBefore
                and g.player.hp == math.min(maxBefore, hpBefore + 30) and Near(g.player.speed, speedBefore)
                and Near(g.damage, damageBefore) and g.coins == coinsBefore, label .. "F" .. floor .. "跨层保留角色与强化")
        end
        local replay = New(g.heroId)
        Game.Start(replay)
        Check(replay.heroId == spec.id and replay.player.hp == spec.hp and replay.player.maxHp == spec.hp
            and replay.player.speed == spec.speed and Near(replay.damage, spec.damage) and replay.floor == 1
            and replay.coins == 0 and replay.level == 1 and replay.stapler == 0, label .. "原角色新局重置构筑而非换角色")
        Check(hero.maxHp == spec.hp and hero.speed == spec.speed and Near(hero.damage, spec.damage), label .. "强化不污染共享角色配置")
    end

    Check(Campaign.combatLayoutCount == 9 and #Campaign.layouts == 14, "九套战斗加商店事件及三套Boss共十四套布局")
    local signatures, kinds = {}, {}
    for layout, obstacles in ipairs(Campaign.layouts) do
        local g = Fixture(layout)
        local prefix = "布局" .. layout .. " / "
        Check(#obstacles >= (layout <= 9 and 10 or 6), prefix .. "实体障碍数明显多于旧2至4件：" .. #obstacles)
        Check(Game.GetDesks(g) == obstacles and Game.GetObstacles(g) == obstacles
            and Game.GetDesks(g) == Game.GetDesks(g), prefix .. "绘制与碰撞共用稳定完整障碍数组")
        local signature = {}
        local valid = true
        for _, o in ipairs(obstacles) do
            valid = valid and o.w > 0 and o.h > 0 and o.x >= 48 and o.y >= 142
                and o.x + o.w <= 992 and o.y + o.h <= 628
            signature[#signature + 1] = string.format("%s:%g,%g,%g,%g", o.kind, o.x, o.y, o.w, o.h)
            kinds[o.kind] = true
        end
        local key = table.concat(signature, ";")
        Check(valid and not signatures[key], prefix .. "尺寸合法且不是复用同一实体布局")
        signatures[key] = true
        local exit = Game.GetExit(g)
        Check(not Solid(obstacles, 520, 580, 24)
            and not Solid(obstacles, exit.triggerX, exit.triggerY, 12)
            and not Solid(obstacles, exit.triggerX, exit.triggerY + 4, 24)
            and exit.y + exit.h == exit.triggerY, prefix .. "出生Boss净空与真实门槛合法")

        for _, kind in ipairs({ 1, 2, 4, 5 }) do
            local enemy = assert(Game.Spawn(g, kind, obstacles[1].x + obstacles[1].w / 2, obstacles[1].y + obstacles[1].h / 2))
            local radius, nav = enemy.radius, g.navigation
            local suffix = prefix .. "半径" .. radius .. " / "
            local field, graph = Navigation.Field(nav, 520, 580, radius)
            local reachable, nodesLegal = 0, true
            for id, node in pairs(graph.nodes) do
                if field.distance[id] ~= nil then reachable = reachable + 1 end
                nodesLegal = nodesLegal and not Solid(obstacles, node.x, node.y, radius)
            end
            Check(graph.count > 100 and graph.componentCount == 1 and reachable == graph.count and nodesLegal,
                suffix .. "整张导航图连通且节点无穿墙")
            local exitY = math.max(exit.triggerY, 142 + radius + 2)
            local path = Navigation.FindPath(nav, 520, 580, exit.triggerX, exitY, radius)
            local pathLegal = #path >= 2
            for i, point in ipairs(path) do
                pathLegal = pathLegal and not Solid(obstacles, point.x, point.y, radius)
                if i > 1 then
                    local previous = path[i - 1]
                    local samples = math.max(1, math.ceil(Game.Distance(previous.x, previous.y, point.x, point.y) / 2))
                    for step = 0, samples do
                        local t = step / samples
                        pathLegal = pathLegal and not Solid(obstacles, previous.x + (point.x - previous.x) * t,
                            previous.y + (point.y - previous.y) * t, radius)
                    end
                end
            end
            local tail = path[#path]
            Check(pathLegal and tail and Near(tail.x, exit.triggerX) and Near(tail.y, exitY), suffix .. "出生至真实门槛整条路径实际净空")
            Check(not Solid(obstacles, enemy.x, enemy.y, radius)
                and #Navigation.FindPath(nav, enemy.x, enemy.y, 520, 580, radius) > 1, suffix .. "指定墙内出生被投影为合法可达点")
            local randomLegal = true
            for _ = 1, 6 do
                local x, y = Navigation.SpawnPoint(nav, 520, 580, radius, 240)
                randomLegal = randomLegal and x ~= nil and y ~= nil
                if x and y then
                    randomLegal = randomLegal and not Solid(obstacles, x, y, radius)
                        and Game.Distance(x, y, 520, 580) >= 240
                        and #Navigation.FindPath(nav, x, y, 520, 580, radius) > 1
                end
            end
            Check(randomLegal, suffix .. "六次随机出生均合法可达且满足安全距离")

            -- 实体从被隔断遮挡的最远可达点追击静止玩家；完整跑真实Game.Update。
            local farthest = { x = 0, y = 0 }
            local found, farDistance = false, -1
            for id, distance in pairs(field.distance) do
                local node = graph.nodes[id]
                if distance > farDistance and not Navigation.Visible(nav, node.x, node.y, 520, 580, radius) then
                    farthest.x, farthest.y = node.x, node.y
                    found, farDistance = true, distance
                end
            end
            Check(found, suffix .. "存在必须绕行的真实复杂隔断")
            if found then
                g.enemies = { enemy }
                enemy.x, enemy.y = farthest.x, farthest.y
                enemy.knockX, enemy.knockY, enemy.shootTimer = 0, 0, 999
                enemy.navSightAt, enemy.navDirect = 0, false
                g.player.x, g.player.y, g.player.invuln = 520, 580, 999
                g.meleeTimer, g.bossTimer, g.hitStop, g.waveTimer = 999, 999, 0, 999
                g.bossDefeated, g.roomCleared, g.mode = false, false, "playing"
                local legal, reached = true, false
                for _ = 1, 2400 do
                    Game.Update(g, 0.05, 0, 0)
                    if Solid(obstacles, enemy.x, enemy.y, radius) then legal = false; break end
                    if Game.Distance(enemy.x, enemy.y, 520, 580) < radius + 27 then reached = true; break end
                end
                Check(legal and reached, suffix .. "敌人实际绕复杂墙体追到玩家且全程不入墙")
            end
            g.enemies, g.hostileShots, g.effects, g.particles = {}, {}, {}, {}
            g.bossSpawned, g.bossDefeated = false, false
        end
    end
    Check(kinds.desk and kinds.partition and kinds.cabinet and kinds.planter and kinds.server, "五类实体家具全部参与布局")
    local assigned = {}
    for floor = 1, 3 do
        local rooms = Campaign.Build(floor)
        for _, room in ipairs(rooms) do assigned[room.layout] = true end
        Check(rooms[4].layout == 10 and rooms[5].layout == 11 and rooms[8].layout == 11 + floor,
            "F" .. floor .. "商店事件Boss绑定独立实体布局")
    end
    local assignedCount = 0
    for _ in pairs(assigned) do assignedCount = assignedCount + 1 end
    Check(assignedCount == 14, "十四套布局全部实际出现在三层路线")

    -- 碰撞夹具：layout1，竖墙x332..350/y232..356，横墙x148..350/y394..412。
    -- 角色r12在(310,280)，敌人r17在(380,280)，距离70但被18厚墙隔开。
    -- x370虽几何不入墙但保守导航桶会投影；x380保留准确原点且同样隔墙。
    -- 大步/高速弹丸必须先撞墙；同侧命中对照防止测试因武器未更新而假通过。
    local moved = Fixture(1)
    moved.player.x, moved.player.y = 310, 280
    Game.Move(moved, moved.player, 500, 0, 12)
    Check(moved.player.x <= 320.00001 and not Solid(Game.GetDesks(moved), moved.player.x, moved.player.y, 12),
        "高速水平移动不能穿过18厚隔断")
    moved.player.x, moved.player.y = 200, 360
    Game.Move(moved, moved.player, 0, 300, 12)
    Check(moved.player.y <= 382.00001 and not Solid(Game.GetDesks(moved), moved.player.x, moved.player.y, 12),
        "高速纵向移动不能穿过横隔断")

    local wall = Fixture(1)
    wall.player.x, wall.player.y, wall.meleeTimer = 310, 280, 0
    local shielded = Stationary(wall, 380, 280)
    local shieldHp = shielded.hp
    Check(Near(shielded.x, 380) and Near(shielded.y, 280) and not Game.Visible(wall, 310, 280, 380, 280),
        "墙两侧近战夹具合法且确有视线遮挡")
    Tick(wall, 4)
    Check(shielded.hp == shieldHp and not wall.actionTracks.keyboard, "隔墙目标不启动假键盘命中")
    wall.rage = 100
    Check(Game.Burst(wall) and shielded.hp == shieldHp, "怒气起手蓄力没有伤害")
    Tick(wall, 3)
    Check(shielded.hp == shieldHp and wall.actionTracks.burst.impactDone, "真实怒气命中后范围伤害仍不能穿墙")
    Tick(wall, 12)
    Check(not wall.actionTracks.burst and shielded.hp == shieldHp, "隔墙怒气完成收招也不补伤害")
    wall.hitStop, wall.meleeTimer = 0, 999
    wall.pools = { { x = 310, y = 280, radius = 90, life = 3, tick = 0 } }
    Tick(wall, 1)
    Check(shielded.hp == shieldHp, "咖啡持续伤害不能穿墙")
    wall.pools = {}
    wall.shots = { { x = 310, y = 280, vx = 2400, vy = 0, life = 1, damage = 25, pierce = 3, hit = {} } }
    Tick(wall, 1)
    Check(shielded.hp == shieldHp and #wall.shots == 0, "高速玩家弹丸扫掠先撞墙而非墙后敌人")
    wall.player.invuln = 0
    local playerHp = wall.player.hp
    wall.hostileShots = { { x = 370, y = 280, vx = -2400, vy = 0, life = 1, kind = 1 } }
    Tick(wall, 1)
    Check(wall.player.hp == playerHp and #wall.hostileShots == 0, "高速敌方弹丸不能隔墙命中玩家")

    local control = Fixture(1)
    control.player.x, control.player.y, control.meleeTimer = 310, 280, 0
    local visible = Stationary(control, 290, 280)
    local visibleHp = visible.hp
    Tick(control, 1)
    Check(visible.hp == visibleHp and control.action.name == "keyboard", "同侧键盘对照起手只蓄力")
    Tick(control, 2)
    Check(visibleHp - visible.hp == math.floor(27 * 1.30) and control.actionTracks.keyboard.impactDone,
        "同侧近战对照确实推进到命中而非空跑")
    control.meleeTimer = 999
    Tick(control, 10)
    Check(visibleHp - visible.hp == math.floor(27 * 1.30) and not control.actionTracks.keyboard,
        "同侧近战收招不重复伤害")
    local shotControl = Fixture(1)
    local openTarget = Stationary(shotControl, 560, 580)
    local openHp = openTarget.hp
    shotControl.shots = { { x = 520, y = 580, vx = 2400, vy = 0, life = 1, damage = 25, pierce = 0, hit = {} } }
    Tick(shotControl, 1)
    Check(openHp - openTarget.hp == math.floor(25 * 1.30), "开放通道高速玩家弹丸扫掠命中对照")
    shotControl.player.invuln = 0
    local beforeHp = shotControl.player.hp
    shotControl.hostileShots = { { x = 580, y = 580, vx = -2400, vy = 0, life = 1, kind = 1 } }
    Tick(shotControl, 1)
    Check(shotControl.player.hp == beforeHp - 8, "开放通道敌方弹丸命中对照")

    print("[角色布局测试汇总] " .. passed .. "项断言全部通过；14布局×4半径真实追击完成")
    return passed
end

if moduleName == nil then
    function Start() Tests.Run() end
end

return Tests
