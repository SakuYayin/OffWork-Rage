-- 固定截图入口：tests/ArtShowcase.lua；无需依赖Runtime未约定的arg透传。
-- 基于现有scaffold-2d/main初始化，不另建UI或绘制管线；不作为美术验收结论。
local UI = require("urhox-libs/UI")
local Game = require("Game")
local Campaign = require("Campaign")
local newGame = Game.New
local live = newGame("female")
---@param heroId string?
Game.New = function(heroId)
    live = newGame(heroId or "female")
    return live
end
require("main")
local originalStart, originalUpdate = Start, HandleUpdate
local tick, stage = 0, 0

local function ClickId(id)
    local root = assert(UI.GetRoot(), "showcase UI未初始化")
    local button = assert(root:FindById(id), "showcase缺少真实控件：" .. id)
    assert(button.props.onClick, "showcase控件不可操作：" .. id)
    button.props.onClick(button)
end

local function FreezeShowcase()
    assert(live.mode == "playing" and live.heroId == "female" and live.selectedHeroId == "female",
        "showcase必须经真实选人确认女主")
    local root = assert(UI.GetRoot())
    local employee = assert(root:FindById("employeeName"))
    assert(employee.props.text == live.hero.name, "showcase HUD身份未真实重建为女主")
    live.floor, live.rooms = 2, Campaign.Build(2)
    Game.EnterRoom(live, 1) -- F2-1为中等复杂双回廊；不改共享Campaign布局。
    live.player.x, live.player.y = 550, 390
    live.player.faceX, live.player.faceY, live.player.invuln = 1, 0, 0
    live.time, live.visualTime, live.level, live.kills = 146, 0, 6, 62
    live.coins, live.rage, live.stapler, live.coffee = 96, 100, 2, 1
    live.wave, live.totalWaves = 2, 2
    live.enemies, live.shots, live.hostileShots = {}, {}, {}
    Game.Spawn(live, 1, 600, 400)
    Game.Spawn(live, 2, 448, 410)
    Game.Spawn(live, 3, 680, 340)
    Game.Spawn(live, 5, 550, 250)
    assert(live.heroId == "female" and live.floor == 2 and #live.enemies == 4, "showcase状态不完整")
    assert(not Game.Blocked(live, live.player.x, live.player.y, live.player.radius), "showcase人物出生入墙")
    for _, enemy in ipairs(live.enemies) do
        assert(not Game.Blocked(live, enemy.x, enemy.y, enemy.radius), "showcase敌人出生入墙")
    end
    live.shots = { { x = 605, y = 390, vx = 530, vy = 0, life = 1.5, damage = 30, pierce = 2, hit = {} } }
    live.effects = { { kind = "slash", x = 550, y = 390, life = 0.16, maxLife = 0.2, size = 104, angle = 0, text = "" } }
    live.announcement, live.announcementTime = "第2层 · 林夏 / 会议回廊与主管对峙", 99
    live.shake, live.flash, live.hitStop, live.audioQueue = 0, 0, 0, {}
    live.uiRevision = live.uiRevision + 1
    -- 固定姿态与特效：加载到截图帧期间不会走掉、挥斩消失或意外伤害。
    Game.Update = function() end
    Game.UpdateVisuals = function() end
    print("[ArtShowcase] female / floor2 layout" .. live.room.layout .. " / enemies1,2,3 + boss / frozen / real female HUD")
end

function Start()
    originalStart()
end

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
    elseif stage == 4 then FreezeShowcase() end
end
