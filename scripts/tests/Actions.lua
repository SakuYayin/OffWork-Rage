-- 独立规则测试：require("tests.Actions").Run()；Runtime入口仅在统一build后运行。
-- 沿用scaffold-2d的Start生命周期，不初始化UI/渲染/音频，不评价或生成动作帧。
-- 只驱动真实Game/ActionState，不替换产品函数；所有时长使用游戏时间，不跳过hitstop。
local moduleName = ...
local Game = require("Game")
local Campaign = require("Campaign")
local Navigation = require("Navigation")
local ActionState = require("ActionState")
local Tests = {}
local New = Game.New
local DT = 0.02

local function Near(a, b) return math.abs(a - b) < 0.00001 end

---@param heroId string?
---@return table
local function Fixture(heroId)
    local g = New(heroId or "female")
    g.mode = "playing"
    g.waveTimer, g.meleeTimer, g.staplerTimer, g.coffeeTimer = 999, 999, 999, 999
    g.player.invuln, g.crit = 999, 0
    return g
end

---@param g table
---@param count integer
---@param x number?
---@param y number?
---@param walking boolean?
---@param dt number?
local function Tick(g, count, x, y, walking, dt)
    for _ = 1, count do Game.Update(g, dt or DT, x or 0, y or 0, nil, walking) end
end

---@param g table
---@param x number?
---@param y number?
---@return table
local function Target(g, x, y)
    local enemy = assert(Game.Spawn(g, 4, x or 580, y or 580), "测试目标出生失败")
    enemy.hp, enemy.maxHp, enemy.speed, enemy.shootTimer = 100000, 100000, 0, 999
    return enemy
end

---@param g table
---@param serial integer
---@param kind string
local function Events(g, serial, kind)
    local count = 0
    for _, event in ipairs(g.actionEvents) do
        if event.serial == serial and event.kind == kind then count = count + 1 end
    end
    return count
end

local function Sounds(g, name)
    local count = 0
    for _, sound in ipairs(g.audioQueue) do if sound == name then count = count + 1 end end
    return count
end

-- 独立判定，不拿被测Game.Blocked/Navigation.Trace作为合法性的唯一依据。
-- 碰撞设计：玩家脚下圆r12，家具AABB，外边界[48,992]x[142,628]。
-- 北门内宽96：圆心x=triggerX±36，半径12；向南48为完整接近区。
--   [triggerX-48 ===== 门槛/y+h ===== triggerX+48]
--   [      r12圆心横向±36，向南0..48采样       ]
-- 覆盖擦边/门洞两端/接近区终点，路径逐段采样且用真实Update走到开门。
local function Solid(obstacles, x, y, radius)
    if x < 48 + radius or x > 992 - radius or y < 142 + radius or y > 628 - radius then return true end
    for _, o in ipairs(obstacles) do
        local cx, cy = math.max(o.x, math.min(x, o.x + o.w)), math.max(o.y, math.min(y, o.y + o.h))
        if (x - cx) ^ 2 + (y - cy) ^ 2 < radius * radius - 0.000001 then return true end
    end
    return false
end

local function Clearance(obstacles, exit)
    for dy = 0, 48, 2 do
        for dx = -36, 36, 2 do
            if Solid(obstacles, exit.triggerX + dx, exit.triggerY + dy, 12) then
                return false, string.format("dx=%g dy=%g", dx, dy)
            end
        end
    end
    return true, "96宽/48深圆形净空"
end

local function LegalPath(obstacles, path, spawn, exit)
    if #path < 2 then return false end
    local first, last = path[1], path[#path]
    if not Near(first.x, spawn.x) or not Near(first.y, spawn.y)
        or not Near(last.x, exit.triggerX) or not Near(last.y, exit.triggerY) then return false end
    for index, point in ipairs(path) do
        if Solid(obstacles, point.x, point.y, 12) then return false end
        if index > 1 then
            local prev = path[index - 1]
            local samples = math.max(1, math.ceil(Game.Distance(prev.x, prev.y, point.x, point.y) / 2))
            for step = 0, samples do
                local t = step / samples
                if Solid(obstacles, prev.x + (point.x - prev.x) * t, prev.y + (point.y - prev.y) * t, 12) then return false end
            end
        end
    end
    return true
end

local function Snapshot(g)
    local tracks = {}
    for name, action in pairs(g.actionTracks) do
        tracks[name] = { action = action, time = action.time, phase = action.phase, impactDone = action.impactDone }
    end
    return { time = g.time, x = g.player.x, y = g.player.y, locomotion = g.locomotion,
        locomotionTime = g.locomotion.time, action = g.action, serial = g.actionSerial, tracks = tracks,
        melee = g.meleeTimer, stapler = g.staplerTimer, coffee = g.coffeeTimer, steps = g.player.stepDistance,
        events = #g.actionEvents, shots = #g.shots, pools = #g.pools, audio = #g.audioQueue }
end

local function Frozen(g, before)
    if g.time ~= before.time or g.player.x ~= before.x or g.player.y ~= before.y
        or g.locomotion ~= before.locomotion or g.locomotion.time ~= before.locomotionTime
        or g.action ~= before.action or g.actionSerial ~= before.serial
        or g.meleeTimer ~= before.melee or g.staplerTimer ~= before.stapler or g.coffeeTimer ~= before.coffee
        or g.player.stepDistance ~= before.steps or #g.actionEvents ~= before.events
        or #g.shots ~= before.shots or #g.pools ~= before.pools or #g.audioQueue ~= before.audio then return false end
    for name, old in pairs(before.tracks) do
        local action = g.actionTracks[name]
        if action ~= old.action or action.time ~= old.time or action.phase ~= old.phase
            or action.impactDone ~= old.impactDone then return false end
    end
    for name in pairs(g.actionTracks) do if not before.tracks[name] then return false end end
    return true
end

---@param externalCheck fun(value: any, message: string)?
---@return integer, table
function Tests.Run(externalCheck)
    math.randomseed(20261020)
    local report = { assertions = 0, passed = 0, failed = 0, cases = {}, failures = {}, errors = {},
        doors = 0, offsetDoorControls = 0, pathUpdates = 0, runtimeExecuted = false }
    local caseName = ""
    local function Check(value, message)
        report.assertions = report.assertions + 1
        local full = caseName .. " / " .. message
        if value then report.passed = report.passed + 1
        else
            report.failed = report.failed + 1
            report.failures[#report.failures + 1] = { case = caseName, assertion = report.assertions, message = message }
        end
        if externalCheck then externalCheck(value, full) end
    end
    local function Case(name, body)
        caseName = name
        local start, failed = report.assertions, report.failed
        local ok, message = pcall(body)
        if not ok then report.errors[#report.errors + 1] = { case = name, message = tostring(message) } end
        report.cases[#report.cases + 1] = { name = name, assertions = report.assertions - start,
            passed = ok and report.failed == failed, error = not ok and tostring(message) or false }
        print(string.format("[动作测试] %s / %s / %d assertions", name,
            ok and report.failed == failed and "PASS" or "FAIL", report.assertions - start))
    end

    for _, heroId in ipairs({ "male", "female" }) do
        Case("keyboard lifecycle " .. heroId, function()
            local g = Fixture(heroId)
            local enemy = Target(g)
            local hp = enemy.hp
            g.meleeTimer = 0
            Tick(g, 1)
            local action = g.actionTracks.keyboard --[[@as OfficeAction]]
            assert(action, "没有真实键盘起手")
            Check(g.action == action and action.time == 0 and action.phase == "windup", "起手time0只建立稳定主姿态")
            Check(enemy.hp == hp and Events(g, action.serial, "impact") == 0 and Sounds(g, "swing") == 0, "起手伤害/命中事件/挥击声音均为零")
            Check(Near(action.impactAt, 0.10) and Near(action.duration, 0.42), "真实键盘时序符合规格")
            g.meleeTimer = 999
            Tick(g, 4)
            Check(Near(action.time, 0.08) and enemy.hp == hp and not action.impactDone, "跨四帧蓄力仍然零伤害")
            Tick(g, 1)
            local damage = math.floor(27 * g.damage)
            Check(enemy.hp == hp - damage and action.impactDone and action.phase == "impact", "到0.10才按角色倍率命中一次")
            Check(Events(g, action.serial, "start") == 1 and Events(g, action.serial, "impact") == 1, "单serial起手与命中各一次")
            Check(Sounds(g, "swing") == 1 and g.hitStop > 0, "命中有一次挥击音效及真实hitstop")
            Tick(g, 11)
            Check(action.phase == "recovery" and g.actionTracks.keyboard == action
                and enemy.hp == hp - damage, "完整收招期间保持轨道且不重复伤害")
            Tick(g, 12)
            Check(not g.actionTracks.keyboard and g.action == g.locomotion and enemy.hp == hp - damage, "收招结束回到移动层不补伤害")
            Check(Events(g, action.serial, "impact") == 1 and Events(g, action.serial, "end") == 1
                and Sounds(g, "swing") == 1, "完整生命周期命中/结束/声音均唯一")
        end)
    end

    Case("keyboard rate and locked facing", function()
        for _, rate in ipairs({ 0.5, 1, 5, 100 }) do
            local g = Fixture()
            local a = assert(ActionState.Start(g, "keyboard", 3, 4, rate))
            Check(a.impactAt >= 0.075 and a.impactEnd >= a.impactAt + 0.05
                and a.duration >= a.impactEnd + 0.10 and a.windup >= 0.045, "攻速" .. rate .. "保留最低命中/有力段/收招")
            Check(Near(a.faceX, 0.6) and Near(a.faceY, 0.8), "锁向向量归一化")
            Check(ActionState.Start(g, "keyboard", -1, 0, rate) == nil and g.actionTracks.keyboard == a, "同武器活动中不重启或覆盖轨道")
        end
        local g = Fixture()
        Target(g)
        g.meleeTimer = 0
        Tick(g, 1)
        local action = assert(g.actionTracks.keyboard)
        local x = g.player.x
        Tick(g, 3, -1, 0)
        Check(g.player.x < x and g.locomotion.name == "run" and g.locomotion.faceX == -1, "攻击不取消实际向后跑动")
        Check(g.action == action and action.faceX == 1 and Near(action.faceY, 0) and g.player.faceX == 1, "完整主姿态保持起手方向不被移动抢夺")
    end)

    for _, level in ipairs({ 1, 3 }) do
        Case("stapler single volley level" .. level, function()
            local g = Fixture()
            Target(g, 800, 580)
            g.stapler, g.staplerTimer = level, 0
            Tick(g, 1)
            local action = assert(g.actionTracks.stapler)
            Check(action.time == 0 and #g.shots == 0 and Sounds(g, "staple") == 0, "起手蓄力不发弹")
            g.staplerTimer = 999
            Tick(g, 3)
            Check(Near(action.time, 0.06) and #g.shots == 0 and not action.impactDone, "0.07命中线前仍未发弹")
            Tick(g, 1)
            local valid = #g.shots == math.min(3, level)
            for _, shot in ipairs(g.shots) do valid = valid and shot.actionSerial == action.serial end
            Check(valid and action.impactDone and Sounds(g, "staple") == 1, "越过命中线只发一次对应等级弹丸组")
            Check(Events(g, action.serial, "impact") == 1, "发射由唯一impact事件驱动")
            Tick(g, 4)
            Check(action.phase == "recovery" and g.actionTracks.stapler == action and Sounds(g, "staple") == 1, "收招不重复发射")
            Tick(g, 5)
            Check(not g.actionTracks.stapler and Events(g, action.serial, "end") == 1
                and Sounds(g, "staple") == 1, "轨道结束仍仅一次发射音效")
        end)
    end

    Case("independent overlapping weapons", function()
        local g = Fixture()
        Target(g)
        g.stapler, g.coffee = 1, 1
        g.meleeTimer, g.staplerTimer, g.coffeeTimer = 0, 0, 0
        Tick(g, 1)
        local keyboard, stapler, coffee = assert(g.actionTracks.keyboard), assert(g.actionTracks.stapler), assert(g.actionTracks.coffee)
        Check(g.action == keyboard and keyboard.serial ~= stapler.serial and coffee.serial ~= stapler.serial, "三武器同帧独立起手，键盘主姿态稳定")
        Check(keyboard.time == 0 and stapler.time == 0 and coffee.time == 0 and #g.shots == 0 and #g.pools == 0, "所有武器起手均无提前impact")
        g.meleeTimer, g.staplerTimer, g.coffeeTimer = 999, 999, 999
        Tick(g, 4)
        Check(stapler.impactDone and not keyboard.impactDone and not coffee.impactDone
            and g.action == keyboard and #g.shots > 0, "订书机不等键盘收招就独立发射")
        Tick(g, 1)
        Check(keyboard.impactDone and g.action == keyboard, "键盘独立命中且不抢掉其他轨道")
        Tick(g, 8)
        Check(coffee.impactDone and #g.pools == 1 and g.pools[1].actionSerial == coffee.serial
            and g.action == keyboard, "咖啡同样不被稳定主姿态饿死")
        Tick(g, 22)
        for _, action in ipairs({ keyboard, stapler, coffee }) do
            Check(Events(g, action.serial, "start") == 1 and Events(g, action.serial, "impact") == 1
                and Events(g, action.serial, "end") == 1 and not g.actionTracks[action.name],
                action.name .. "独立完整结束，各时序事件唯一")
        end
    end)

    Case("repeated cooldowns do not starve", function()
        local g = Fixture()
        local target = Target(g)
        g.stapler, g.coffee, g.attackSpeed, g.range = 1, 1, 3, 3
        g.meleeTimer, g.staplerTimer, g.coffeeTimer = 0, 0, 0
        local seen, counts, unique, bounded = {}, {}, true, true
        for _ = 1, 380 do
            -- 静止木桩：仅复位木桩击退，产品攻击/时序/冷却/子弹/咖啡均真实运行。
            target.x, target.y, target.knockX, target.knockY = 580, 580, 0, 0
            Tick(g, 1)
            local frameKeys = {}
            for _, event in ipairs(g.actionEvents) do
                local key = event.serial .. ":" .. event.kind
                if frameKeys[key] then unique = false end
                frameKeys[key] = true
                if not seen[key] then
                    seen[key] = true
                    if event.kind == "impact" then counts[event.name] = (counts[event.name] or 0) + 1 end
                end
            end
            bounded = bounded and #g.actionEvents <= 32
            g.audioQueue = {} -- 模拟消费者排空，不覆盖任何音效生产函数。
        end
        Check((counts.keyboard or 0) >= 10, "高攻速键盘持续工作而非串行等待")
        Check((counts.stapler or 0) >= 7, "多轮重叠中订书机冷却独立")
        Check((counts.coffee or 0) >= 2, "长冷却咖啡也有第二次真实impact")
        Check(unique and bounded, "32项滚动历史同serial+kind永不重复")
    end)

    Case("burst windup impact recovery", function()
        local g = Fixture()
        local target = Target(g)
        local hp = target.hp
        g.rage = 100
        g.hostileShots = { { x = 100, y = 580, vx = 0, vy = 0, life = 10, kind = 1 } }
        Check(Game.Burst(g) and g.rage == 0 and g.player.invuln > 0, "起手只扣怒气并提供无敌")
        local burst = assert(g.actionTracks.burst)
        Check(target.hp == hp and #g.hostileShots == 1 and Sounds(g, "burst") == 0, "起手无伤害/清弹幕/爆发声音")
        g.rage = 100
        Check(not Game.Burst(g) and g.rage == 100 and g.actionTracks.burst == burst, "重复按爆发不覆盖当前动作或二次扣怒气")
        Tick(g, 5)
        Check(target.hp == hp and #g.hostileShots == 1 and not burst.impactDone, "0.10仍在等待0.12命中")
        Tick(g, 1)
        local damage = math.floor(125 * g.damage)
        Check(target.hp == hp - damage and #g.hostileShots == 0 and burst.impactDone
            and Sounds(g, "burst") == 1, "0.12真实impact一次伤害并清弹幕")
        Tick(g, 28)
        Check(not g.actionTracks.burst and target.hp == hp - damage
            and Events(g, burst.serial, "impact") == 1 and Events(g, burst.serial, "end") == 1, "完整收招不重复爆发")
    end)

    for _, mode in ipairs({ "paused", "upgrade", "hitstop" }) do
        for _, phase in ipairs({ "windup", "impact", "recovery" }) do
            Case(mode .. " freezes " .. phase, function()
                local g = Fixture()
                Target(g)
                g.stapler, g.coffee = 1, 1
                g.meleeTimer, g.staplerTimer, g.coffeeTimer = 0, 0, 0
                Tick(g, 1)
                local action = assert(g.actionTracks.keyboard)
                g.meleeTimer, g.staplerTimer, g.coffeeTimer = 999, 999, 999
                local limit = 0
                while (action.phase ~= phase or (phase == "windup" and action.time == 0) or g.hitStop > 0) and limit < 40 do
                    Tick(g, 1); limit = limit + 1
                end
                Check(action.phase == phase and g.hitStop == 0, "真实推进到待冻结的" .. phase)
                local before = Snapshot(g)
                if mode == "hitstop" then
                    g.hitStop = 0.11
                    for _ = 1, 3 do Game.UpdateVisuals(g, 0.05); Tick(g, 1, 1, 0, true, 0.05) end
                    Check(g.hitStop == 0 and Frozen(g, before), "hitstop倒数归零该帧仍冻结全部轨道/移动/冷却/事件")
                else
                    g.mode = mode == "paused" and "paused" or "upgrade"
                    for _ = 1, 10 do Game.UpdateVisuals(g, 0.05); Tick(g, 1, 1, 0, true, 0.05) end
                    Check(Frozen(g, before), mode .. "冻结动作及locomotion，不受visualTime影响")
                    g.mode = "playing"
                end
                Tick(g, 1)
                Check(g.time > before.time and action.time > before.tracks.keyboard.time, "恢复后从原游戏时间继续而非补算停顿")
            end)
        end
    end

    for _, heroId in ipairs({ "male", "female" }) do
        Case("walk run speed " .. heroId, function()
            local run, walk, forced = Fixture(heroId), Fixture(heroId), Fixture(heroId)
            Tick(run, 5, 1, 0)
            Tick(walk, 5, 1, 0, true)
            Tick(forced, 5, 1, 0, false)
            local speed = run.player.speed
            Check(Near(run.player.x - 520, speed * 0.1) and run.player.gait == "run"
                and run.player.running and not run.player.walking, "默认键盘满幅度跑")
            Check(Near(walk.player.x - 520, speed * 0.1 * 0.55) and walk.player.gait == "walk"
                and walk.player.walking and not walk.player.running, "第6参Shift走严格为0.55倍")
            Check(Near(forced.player.x, run.player.x) and forced.player.running, "第6参false明确跑")
            Check(run.locomotion.name == "run" and Near(run.locomotion.duration, 0.48)
                and walk.locomotion.name == "walk" and Near(walk.locomotion.duration, 0.72), "走跑分别驱动正确locomotion循环")
            local diagonal = Fixture(heroId)
            Tick(diagonal, 5, 1, -1, true)
            Check(Near(Game.Distance(520, 580, diagonal.player.x, diagonal.player.y), speed * 0.1 * 0.55), "Shift斜向走也归一化")
        end)
    end

    Case("analog thresholds and deadzone", function()
        for _, spec in ipairs({ { value = 0, gait = "idle", scale = 0 }, { value = 0.05, gait = "idle", scale = 0 },
            { value = 0.06, gait = "walk", scale = 0.06 * 0.55 }, { value = 0.64, gait = "walk", scale = 0.64 * 0.55 },
            { value = 0.65, gait = "run", scale = 0.65 }, { value = 0.9, gait = "run", scale = 0.9 },
            { value = 2, gait = "run", scale = 1 } }) do
            local g = Fixture()
            Tick(g, 1, spec.value, 0)
            Check(g.player.gait == spec.gait and Near(g.player.x - 520, g.player.speed * DT * spec.scale),
                "摇杆幅度" .. spec.value .. "保留模拟量及边界语义")
        end
        local forced = Fixture()
        Tick(forced, 1, 0.3, 0, false)
        Check(forced.player.running and Near(forced.player.x - 520, forced.player.speed * DT * 0.3), "false可覆盖小幅度自动走")
        local idle = Fixture()
        Tick(idle, 70)
        Check(idle.locomotion.name == "idle" and Near(idle.locomotion.duration, 1.2)
            and idle.locomotion.time >= 0 and idle.locomotion.time < 1.2, "idle循环有界，不靠visualTime推进")
    end)

    Case("steps enqueue only with actual motion", function()
        for _, walking in ipairs({ false, true }) do
            local g = Fixture()
            local name, other, stride = walking and "step_walk" or "step_run", walking and "step_run" or "step_walk", walking and 28 or 40
            g.player.stepDistance = stride - 0.5
            Tick(g, 1, 1, 0, walking)
            Check(g.player.moving and Sounds(g, name) == 1 and Sounds(g, other) == 0, name .. "只由真实位移累计产生")
            g.audioQueue = {}
            Tick(g, 5)
            Check(not g.player.moving and g.player.gait == "idle" and g.player.stepDistance == 0
                and Sounds(g, name) == 0 and Sounds(g, other) == 0, "停止输入不排入假脚步")
            -- r12贴在竖墙左侧x332-12=320；连续输入只能顶墙，不能积累输入距离。
            g.player.x, g.player.y, g.player.stepDistance = 320, 280, stride - 0.001
            Tick(g, 30, 1, 0, walking)
            Check(Near(g.player.x, 320) and Near(g.player.y, 280) and not g.player.moving
                and not g.player.walking and not g.player.running and g.locomotion.name == "idle"
                and g.player.stepDistance == 0 and Sounds(g, name) == 0, "顶墙30帧无假步态/假步伐/步行音效")
            Tick(g, 1, 1, 1, walking)
            Check(Near(g.player.x, 320) and g.player.y > 280 and g.player.moving
                and g.player.gait == (walking and "walk" or "run"), "沿墙真实滑动仍有正确移动步态")
        end
        local g = Fixture()
        g.player.x, g.player.y, g.player.stepDistance = 980, 616, 39.99
        Tick(g, 20, 1, 1, false)
        Check(g.player.x == 980 and g.player.y == 616 and g.player.gait == "idle"
            and Sounds(g, "step_run") == 0, "外边界角落双轴受阻也没有假跑步")
    end)

    for _, roomIndex in ipairs({ 2, 4, 5, 8 }) do
        Case("room reset tracks " .. roomIndex, function()
            local g = Fixture()
            for _, name in ipairs({ "keyboard", "stapler", "coffee", "burst", "hurt" }) do
                assert(ActionState.Start(g, name, 1, 0), "重置夹具动作未启动")
            end
            Tick(g, 1, 1, 0, true)
            g.player.stepDistance = 27.9
            local serial, oldTracks = g.actionSerial, g.actionTracks
            Game.EnterRoom(g, roomIndex)
            Check(g.actionTracks ~= oldTracks and next(g.actionTracks) == nil and #g.actionEvents == 0, "换房清空所有并发轨道和旧事件")
            Check(g.action == g.locomotion and g.action.name == "idle" and g.action.time == 0
                and g.action.serial > serial, "换房重置idle，serial保持全局单调")
            Check(not g.player.moving and not g.player.walking and not g.player.running
                and g.player.gait == "idle" and g.player.stepDistance == 0, "换房步态和累计脚程归零")
            Check(#g.shots == 0 and #g.pools == 0 and g.hitStop == 0, "旧房子弹/咖啡/卡顿不泄漏")
            if g.mode == "playing" then
                g.waveTimer, g.meleeTimer, g.staplerTimer, g.coffeeTimer = 999, 999, 999, 999
                g.audioQueue = {}
                Tick(g, 35)
                Check(next(g.actionTracks) == nil and #g.actionEvents == 0 and #g.shots == 0 and #g.pools == 0, "换房后等待旧动作全长也不迟发impact")
            end
        end)
    end

    ---@type number[]
    local exitXs = { 520, 440, 340, 600, 440, 600, 600, 520, 520, 520, 520, 520, 520, 520 }
    for floor = 1, 3 do
        for roomIndex = 1, 8 do
            Case(string.format("door F%d-%d", floor, roomIndex), function()
                local g = Fixture()
                g.floor, g.rooms = floor, Campaign.Build(floor)
                Check(#g.rooms == 8, "本层恰好8房")
                Game.EnterRoom(g, roomIndex)
                local room = g.room --[[@as CampaignRoom]]
                local spawn, exit = Game.GetSpawn(g), Game.GetExit(g)
                local obstacles = Campaign.Obstacles(room)
                report.doors = report.doors + 1
                Check(exit == room.exit and exit == Game.GetExit(g) and spawn == room.spawn, "门/入口API读取同一稳定房间数据")
                Check(exit.w == 112 and exit.h == 160 and exit.clearance == 96 and exit.side == "north"
                    and exit.radius == 30 and exit.triggerX == exitXs[room.layout] and exit.triggerY == 174, "门框/门洞/触发器匹配独立规格")
                Check(Near(exit.y + exit.h, exit.triggerY) and Near(exit.x + exit.w / 2, exit.triggerX), "门底边严格等于triggerY且水平中心一致")
                Check(not Solid(obstacles, spawn.x, spawn.y, 12), "入口玩家脚下不入墙")
                local clear, detail = Clearance(obstacles, exit)
                Check(clear, "96净宽及南侧48接近区独立圆/AABB密集采样：" .. detail)
                local path = Navigation.FindPath(g.navigation, spawn.x, spawn.y, exit.triggerX, exit.triggerY, 12)
                Check(LegalPath(obstacles, path, spawn, exit), "入口到本房门槛整条路径独立2单位净空采样")

                -- 站到真实门槛也不能越过尚未完成的战斗/商店/事件结算。
                g.player.x, g.player.y, g.player.invuln = exit.triggerX, exit.triggerY, 999
                local mode = g.mode
                Check(not Game.OpenRoute(g) and not g.roomCleared, "未完成房间不能手动开门")
                Tick(g, 1)
                Check(g.floor == floor and g.roomIndex == roomIndex and g.mode == mode, "未完成房间进入门槛也不能自动前进")
                if room.kind == "shop" then
                    Game.LeaveShop(g)
                    Check(g.roomCleared and g.mode == "playing", "商店确认补给结束才开门")
                elseif room.kind == "event" then
                    Check(Game.ResolveEvent(g, 2) and g.roomCleared and g.mode == "playing", "事件领奖后才开门")
                else
                    if room.kind == "boss" then
                        local boss = assert(g.enemies[1], "首领未生成")
                        Game.Hit(g, boss, 100000, 0, 0, 0)
                    else
                        -- 只设定最终波已击杀的边界输入；完整波次覆盖仍保留在Smoke。
                        g.enemies, g.wave = {}, g.totalWaves
                    end
                    Tick(g, 1)
                    Check(g.mode == "upgrade" and g.rewardPending and not g.roomCleared, "清房只发BUFF弹窗，不提前解锁门")
                    local frozen = g.time
                    Tick(g, 5, 0, -1)
                    Check(not Game.OpenRoute(g) and g.mode == "upgrade" and g.time == frozen
                        and g.floor == floor and g.roomIndex == roomIndex, "未领奖站在门内也不开门且动作冻结")
                    Game.Choose(g, 1)
                    Check(g.roomCleared and not g.rewardPending and g.mode == "playing", "领取BUFF才解除门锁")
                end
                g.player.x, g.player.y = spawn.x, spawn.y
                g.xp, g.hitStop = 0, 0
                if Game.Distance(520, 160, exit.triggerX, exit.triggerY) > exit.radius then
                    g.player.x, g.player.y = 520, 160
                    Tick(g, 1)
                    Check(g.mode == "playing" and g.floor == floor and g.roomIndex == roomIndex, "旧520,160不再是偏移门的假出口")
                    report.offsetDoorControls = report.offsetDoorControls + 1
                    g.player.x, g.player.y = spawn.x, spawn.y
                end
                -- 沿已独立验证的路点真实行走；不传送到门、不直接调用OpenRoute。
                local legal, transitioned, nearDoor = true, false, false
                local updates = 0
                for _, point in ipairs(path) do
                    while Game.Distance(g.player.x, g.player.y, point.x, point.y) > 0.01 and updates < 5000 do
                        local dx, dy = point.x - g.player.x, point.y - g.player.y
                        local distance = math.sqrt(dx * dx + dy * dy)
                        local dt = math.min(0.05, distance / g.player.speed)
                        local px, py = g.player.x, g.player.y
                        Game.Update(g, dt, dx / distance, dy / distance, nil, false)
                        updates = updates + 1
                        if g.mode ~= "playing" or g.floor ~= floor or g.roomIndex ~= roomIndex then
                            transitioned = true
                            nearDoor = Game.Distance(px, py, exit.triggerX, exit.triggerY) <= exit.radius + g.player.speed * dt + 0.01
                            break
                        end
                        if Solid(obstacles, g.player.x, g.player.y, 12) then legal = false; break end
                        if Game.Distance(px, py, g.player.x, g.player.y) < 0.00001 then legal = false; break end
                        g.audioQueue = {}
                    end
                    if transitioned or not legal then break end
                end
                report.pathUpdates = report.pathUpdates + updates
                Check(legal and transitioned and nearDoor and updates > 0 and updates < 5000, "真实Update从入口绕家具走入门才触发前进")
                if room.kind ~= "boss" then
                    Check(g.mode == "route" and g.floor == floor and g.roomIndex == roomIndex, "普通/安全房进入对应路线图")
                elseif floor < 3 then
                    Check(g.mode == "playing" and g.floor == floor + 1 and g.roomIndex == 1, "本层电梯实际换层并重置房间")
                else Check(g.mode == "won" and g.floor == 3, "第三层进入老板门才获胜") end
            end)
        end
    end
    Case("campaign door coverage", function()
        Check(report.doors == 24, "3层×8房=24个真实门全部覆盖")
        Check(report.offsetDoorControls > 0 and report.pathUpdates > 24, "包含偏移门旧坐标负对照及真实行走而非只比较表")
    end)
    Tests.lastReport = report
    print(string.format("[动作规则汇总] %d/%d assertions passed; failed=%d errors=%d; doors=%d; pathUpdates=%d",
        report.passed, report.assertions, report.failed, #report.errors, report.doors, report.pathUpdates))
    if not externalCheck then
        assert(report.failed == 0 and #report.errors == 0, "动作规则失败，详情见tests.Actions.lastReport")
    end
    return report.passed, report
end

if moduleName == nil then
    function Start() Tests.Run() end
end

return Tests
