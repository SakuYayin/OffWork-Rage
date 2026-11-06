-- 门全貌/门槛/导航箭头截图夹具；仅统一build后由主代理运行，不作为渲染验收结论。
-- 基于scaffold-2d/main现有初始化；真实menuStart→女主→确认，避免HUD角色不一致。
local UI = require("urhox-libs/UI")
local Game = require("Game")
local Campaign = require("Campaign")
local newGame = Game.New
local live = newGame()
---@param heroId string?
Game.New = function(heroId)
    live = newGame(heroId)
    return live
end
require("main")
local originalStart, originalUpdate = Start, HandleUpdate
local tick, stage = 0, 0

local function ClickId(id)
    local root = assert(UI.GetRoot(), "exit showcase UI未初始化")
    local button = assert(root:FindById(id), "exit showcase缺少真实控件：" .. id)
    assert(button.props.onClick, "exit showcase控件不可操作：" .. id)
    button.props.onClick(button)
end

local function FreezeExit()
    assert(live.mode == "playing" and live.heroId == "female", "exit showcase未真实确认女主")
    local root = assert(UI.GetRoot())
    local employee = assert(root:FindById("employeeName"))
    assert(employee.props.text == live.hero.name, "exit showcase HUD角色不一致")
    live.floor, live.rooms = 1, Campaign.Build(1)
    Game.EnterRoom(live, 3) -- F1-3 layout3，偏移出口x340；不能用旧520,160。
    assert(live.room.layout == 3, "exit showcase布局发生变化")
    live.enemies, live.wave = {}, live.totalWaves
    Game.Update(live, 0.02, 0, 0) -- 真正清房结算，不能手工冒充已领奖。
    assert(live.mode == "upgrade" and live.rewardPending and not live.roomCleared, "exit showcase未出现房间BUFF")
    Game.Choose(live, 1)
    assert(live.mode == "playing" and live.roomCleared and not live.rewardPending, "exit showcase必须真正领奖开门")
    local exit = Game.GetExit(live)
    live.player.x, live.player.y, live.player.invuln = exit.triggerX, exit.triggerY + 105, 99
    live.player.faceX, live.player.faceY = 0, -1
    live.locomotion.faceX, live.locomotion.faceY = 0, -1
    live.xp, live.hitStop, live.shake, live.flash = 0, 0, 0, 0
    live.shots, live.hostileShots, live.pools, live.effects, live.particles, live.audioQueue = {}, {}, {}, {}, {}, {}
    assert(exit.y + exit.h == exit.triggerY and exit.clearance == 96, "exit showcase门数据不统一")
    assert(not Game.Blocked(live, live.player.x, live.player.y, live.player.radius), "exit showcase门前站位入墙")
    assert(Game.Visible(live, live.player.x, live.player.y, exit.triggerX, exit.triggerY, live.player.radius), "exit showcase门前接近路线受阻")
    live.announcement, live.announcementTime = "已领取区域奖励 · 沿箭头走入门槛前进", 99
    live.uiRevision = live.uiRevision + 1
    Game.Update = function() end
    Game.UpdateVisuals = function() end
    print(string.format("[ExitShowcase] F1-3 layout3 female reward claimed; player=(%.0f,%.0f); door=(%.0f,%.0f,%.0f,%.0f); threshold=(%.0f,%.0f); clearance=96; frozen",
        live.player.x, live.player.y, exit.x, exit.y, exit.w, exit.h, exit.triggerX, exit.triggerY))
end

function Start() originalStart() end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if live.mode == "playing" then live.player.invuln = 99 end
    originalUpdate(eventType, eventData)
    tick = tick + 1
    if tick % 4 ~= 0 or stage >= 4 then return end
    stage = stage + 1
    if stage == 1 then ClickId("menuStart")
    elseif stage == 2 then ClickId("heroSelectFemale")
    elseif stage == 3 then ClickId("heroConfirm")
    elseif stage == 4 then FreezeExit() end
end
