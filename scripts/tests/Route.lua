-- 路线图视觉验收入口。
local Game = require("Game")
local newGame = Game.New
local live = newGame()
Game.New = function() live = newGame(); return live end
require("main")
local originalStart = Start
function Start()
    originalStart()
    Game.Start(live)
    live.room.cleared, live.roomCleared, live.mode = true, true, "route"
    live.coins = 62
    Game.Update = function() end
end
