-- 三选一窗口的视觉验证入口。
local UI = require("urhox-libs/UI")
local Game = require("Game")
local newGame = Game.New
local live = newGame()
Game.New = function() live = newGame(); return live end
require("main")
local originalStart = Start
local originalUpdate = Game.Update
local originalHandleUpdate = HandleUpdate
local ticks = 0
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    originalHandleUpdate(eventType, eventData)
    ticks = ticks + 1
    if ticks == 35 then
        local scroll = UI.GetRoot():FindById("upgradeScroll") --[[@as ScrollView?]]
        assert(scroll, "强化滚动容器存在")
        scroll:ScrollToBottom()
    elseif ticks == 45 then
        local scroll = UI.GetRoot():FindById("upgradeScroll") --[[@as ScrollView?]]
        assert(scroll, "强化滚动容器存在")
        local _, offset = scroll:GetScroll()
        local width, height = UI.GetViewportSize()
        if width < 700 and height < 720 then assert(offset > 0, "矮屏可滚动到第三选项") end
        print("[界面测试通过] 强化列表可滚动到底部，offset=" .. offset)
    end
end
function Start()
    originalStart()
    Game.Start(live)
    live.xp = live.xpNeed
    originalUpdate(live, 0.05, 0, 0)
    Game.Update = function() end
end
