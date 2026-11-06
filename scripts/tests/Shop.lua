-- 商店视觉验收入口。
local Game = require("Game")
local newGame = Game.New
local live = newGame()
Game.New = function() live = newGame(); return live end
require("main")
local originalStart = Start
function Start()
    originalStart()
    Game.Start(live)
    live.coins, live.player.hp = 80, 60
    Game.EnterRoom(live, 4)
    Game.Update = function() end
end
