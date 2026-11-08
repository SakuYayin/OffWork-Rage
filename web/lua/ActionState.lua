-- 纯玩法时序协议，不生成/加载动画。Draw按time/duration取真实拆帧；不按visualTime推进。
-- g.action是稳定主姿态；g.actionTracks是独立武器层，重叠时不能只画主姿态。
local ActionState = {}

---@class OfficeAction
---@field name string idle/walk/run/keyboard/stapler/coffee/burst/hurt
---@field time number 本次动作的游戏时间（秒）
---@field duration number
---@field windup number 蓄力结束
---@field impactAt number 一次性伤害/发射事件时刻
---@field impactEnd number 有力动作段结束；其后为收招
---@field faceX number 起手锁定朝向
---@field faceY number
---@field serial integer 全局单调动作编号
---@field impactDone boolean
---@field phase string locomotion/windup/impact/recovery
---@field targetX number 咖啡瞄准点，不追踪隔墙敌人
---@field targetY number

-- scaled=true 的动作吃攻速缩放（g.attackSpeed）；以前只有 keyboard 硬编码，S2 改为白名单。
local TIMINGS = {
    summon={windup=.25,impactAt=.35,impactEnd=.45,duration=.6},
    bulb={windup=.12,impactAt=.18,impactEnd=.28,duration=.45},
    folder = {windup=.35,impactAt=.42,impactEnd=.62,duration=1.15,scaled=true},
    binary = {windup=.035,impactAt=.055,impactEnd=.10,duration=.20,scaled=true},
    keyboard = { windup = 0.09, impactAt = 0.10, impactEnd = 0.20, duration = 0.42, scaled = true },
    stapler = { windup = 0.05, impactAt = 0.07, impactEnd = 0.12, duration = 0.24 },
    coffee = { windup = 0.12, impactAt = 0.16, impactEnd = 0.26, duration = 0.50 },
    burst = { windup = 0.10, impactAt = 0.12, impactEnd = 0.28, duration = 0.60 },
    hurt = { windup = 0, impactAt = 0, impactEnd = 0.06, duration = 0.22 },
    -- S2 新武器（02-weapons-buffs-ults.md §4.1）
    thermos = { windup = 0.16, impactAt = 0.18, impactEnd = 0.30, duration = 0.72, scaled = true },
    paperclip = { windup = 0.06, impactAt = 0.08, impactEnd = 0.14, duration = 0.26, scaled = true },
    pie = { windup = 0.42, impactAt = 0.46, impactEnd = 0.62, duration = 1.05 },
    -- 减半后未启用，但定义保留：后续翻开 enabled 即可用（07-halved-plan.md §2.6）
    laser = { windup = 0.22, impactAt = 0.28, impactEnd = 0.90, duration = 1.20, scaled = true },
    extinguisher = { windup = 0.30, impactAt = 0.32, impactEnd = 0.52, duration = 0.90, scaled = true },
    reload = { windup = 0.60, impactAt = 0.60, impactEnd = 0.90, duration = 1.30 },
}
-- 追加不插队：新动作排在咖啡之后，保证既有「同帧三武器独立起手」断言不变。
local ORDER = { "burst", "hurt", "summon", "bulb", "folder", "binary", "keyboard", "stapler", "coffee",
    "reload", "thermos", "paperclip", "laser", "extinguisher", "pie" }
local LOOPS = { idle = 1.2, walk = 0.72, run = 0.48 }
ActionState.timings = TIMINGS

local function Event(g, action, kind)
    -- 有界历史，消费者按serial+kind去重；不会漏掉Update外触发的burst/hurt。
    if #g.actionEvents >= 32 then table.remove(g.actionEvents, 1) end
    g.actionEvents[#g.actionEvents + 1] = { name = action.name, kind = kind, serial = action.serial,
        time = g.time, localTime = action.time, faceX = action.faceX, faceY = action.faceY }
end

local function Serial(g)
    g.actionSerial = (g.actionSerial or 0) + 1
    return g.actionSerial
end

---@return OfficeAction
local function Locomotion(g, name)
    return { name = name, time = 0, duration = LOOPS[name] or 1.2, windup = 0, impactAt = 0, impactEnd = 0,
        faceX = g.player.faceX, faceY = g.player.faceY, serial = Serial(g), impactDone = true,
        phase = "locomotion", targetX = g.player.x, targetY = g.player.y }
end

function ActionState.Reset(g)
    g.actionTracks, g.actionEvents = {}, {}
    g.locomotion = Locomotion(g, "idle")
    g.action = g.locomotion
end

function ActionState.Active(g, name)
    return g.actionTracks[name] ~= nil
end

local function Select(g)
    local current = g.action
    -- 开始后完整播完蓄力/命中/收招；其他武器只走独立层，不每帧争抢主姿态。
    if current and g.actionTracks[current.name] == current and current.time < current.duration then return end
    for _, name in ipairs(ORDER) do
        if g.actionTracks[name] then g.action = g.actionTracks[name]; return end
    end
    g.action = g.locomotion
end

---@param g table
---@param name string
---@param faceX number
---@param faceY number
---@param rate number? 仅键盘受攻速缩放，保留最低命中帧和收招
---@return OfficeAction?
function ActionState.Start(g, name, faceX, faceY, rate)
    local timing = TIMINGS[name]
    if not timing or ActionState.Active(g, name) then return nil end
    local scaled = timing.scaled == true
    local speed = scaled and math.max(0.1, rate or 1) or 1
    local impactAt = math.max(scaled and 0.075 or 0, timing.impactAt / speed)
    local impactEnd = math.max(impactAt + 0.05, timing.impactEnd / speed)
    local duration = math.max(impactEnd + 0.10, timing.duration / speed)
    if name=="binary"then
        impactAt=math.max(.035,timing.impactAt/speed)
        impactEnd=math.max(impactAt+.03,timing.impactEnd/speed)
        duration=math.max(.16,impactEnd+.06,timing.duration/speed)
    end
    local length = math.sqrt(faceX * faceX + faceY * faceY)
    if length < 0.001 then faceX, faceY, length = 1, 0, 1 end
    ---@type OfficeAction
    local action = { name = name, time = 0, duration = duration,
        windup = math.min(impactAt, math.max(scaled and 0.045 or 0, timing.windup / speed)),
        impactAt = impactAt, impactEnd = impactEnd, faceX = faceX / length, faceY = faceY / length,
        serial = Serial(g), impactDone = name == "hurt", phase = "windup",
        targetX = g.player.x, targetY = g.player.y }
    g.actionTracks[name] = action
    if name == "hurt" or name == "burst" then g.action = action else Select(g) end
    g.player.faceX, g.player.faceY = g.action.faceX, g.action.faceY
    Event(g, action, "start")
    if name == "hurt" then action.phase = "impact"; Event(g, action, "impact") end
    return action
end

function ActionState.SetLocomotion(g, name, faceX, faceY)
    if g.locomotion.name ~= name then g.locomotion = Locomotion(g, name) end
    g.locomotion.faceX, g.locomotion.faceY = faceX, faceY
    Select(g)
    g.player.faceX, g.player.faceY = g.action.faceX, g.action.faceY
end

---@param g table
---@param dt number
---@param onImpact fun(g: table, action: OfficeAction)
function ActionState.Update(g, dt, onImpact)
    if g.mode ~= "playing" or dt <= 0 then return end
    g.locomotion.time = (g.locomotion.time + dt) % g.locomotion.duration
    for _, name in ipairs(ORDER) do
        local action = g.actionTracks[name]
        if action then
            action.time = math.min(action.duration, action.time + dt)
            if action.time < action.impactAt then action.phase = "windup"
            elseif action.time < action.impactEnd then action.phase = "impact"
            else action.phase = "recovery" end
            if not action.impactDone and action.time + 0.000001 >= action.impactAt then
                action.impactDone = true -- 先置位，伤害/事件回调不会重复触发。
                Event(g, action, "impact")
                onImpact(g, action)
            end
            if action.time + 0.000001 >= action.duration then
                Event(g, action, "end")
                g.actionTracks[name] = nil
            end
        end
    end
    Select(g)
    g.player.faceX, g.player.faceY = g.action.faceX, g.action.faceY
end

return ActionState
