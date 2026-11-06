-- 三种首领外观与第三层场景验收；不影响正式入口。
local Game = require("Game")
local Campaign = require("Campaign")
local newGame = Game.New
local live = newGame()
Game.New = function() live = newGame(); return live end
require("main")
local originalStart = Start
function Start()
    originalStart()
    live.floor, live.rooms = 3, Campaign.Build(3)
    Game.EnterRoom(live, 8)
    live.enemies = {}
    for floor = 1, 3 do
        local enemy = Game.Spawn(live, 5, 190 + floor * 170, 345)
        enemy.bossFloor = floor
    end
    live.player.x, live.player.y, live.player.invuln = 520, 535, 0
    live.announcement, live.announcementTime = "工贼同事 / 秃头主管 / 没良心老板", 60
    Game.Update = function() end
end
