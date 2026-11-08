local Animation = require("HeroAnimation")
local Sprites = require("HeroSprites")
local ActionState = require("ActionState")
local Tests = {}

function Tests.Run()
    local count = 0
    local function Check(value, message) assert(value, message); count = count + 1 end
    for _, id in ipairs({ "male", "female", "intern", "programmer" }) do
        local atlas = assert(Sprites[id])
        Check(atlas.referenceHeight > 0, "reference height")
        for _, state in ipairs({ "idle", "walk", "attack", "skill" }) do
            Check(#atlas.frames[state] == 4, id .. " four real frames per state")
            for _, frame in ipairs(atlas.frames[state]) do
                local sheet=frame.sheet or atlas
                Check(frame.w > 0 and frame.h > 0, "nonempty frame")
                Check(frame.x >= 0 and frame.y >= 0 and frame.x + frame.w <= sheet.width
                    and frame.y + frame.h <= sheet.height, "frame inside atlas")
                Check(frame.anchorX >= 0 and frame.anchorX <= frame.w, "foot pivot inside frame")
            end
        end
        local directions = assert(atlas.directions)
        for _, state in ipairs({ "upIdle", "upWalk", "downIdle", "downWalk" }) do
            Check(#directions.frames[state] == 4, "four directional frames")
            for _, frame in ipairs(directions.frames[state]) do
                Check(frame.w > 0 and frame.h > 0 and frame.x >= 0 and frame.y >= 0
                    and frame.x + frame.w <= directions.width and frame.y + frame.h <= directions.height,
                    "directional frame inside atlas")
                Check(frame.anchorX >= 0 and frame.anchorX <= frame.w, "directional foot anchor")
            end
        end
    end
    local g = { player = { x = 0, y = 0, faceX = 1, faceY = 0, moving = false }, mode = "playing", time = 0 }
    ActionState.Reset(g)
    for i = 0, 3 do
        g.locomotion.time = g.locomotion.duration * i / 4
        local state, frame = Animation.Select(g)
        Check(state == "idle" and frame == i + 1, "idle cycle")
    end
    g.player.moving = true
    ActionState.SetLocomotion(g, "walk", 1, 0)
    for i = 0, 3 do
        g.locomotion.time = g.locomotion.duration * i / 4
        local state, frame = Animation.Select(g)
        Check(state == "walk" and frame == i + 1, "walk cycle")
    end
    local action = ActionState.Start(g, "keyboard", -1, 0)
    for _, sample in ipairs({ { 0, 1 }, { action.windup * 0.7, 2 }, { action.impactAt, 3 }, { action.impactEnd + 0.01, 4 } }) do
        action.time = sample[1]
        local state, frame = Animation.Select(g)
        Check(state == "attack" and frame == sample[2], "keyboard frame matches real timing")
    end
    g.mode = "paused"
    local before = action.time
    ActionState.Update(g, 0.1, function() error("paused impact") end)
    Check(action.time == before, "paused action frame freezes")
    action.time = action.duration
    g.action = g.locomotion
    g.player.moving = false
    Check(Animation.Select(g) == "idle", "stopped movement returns to idle")
    g.actionTracks = {}
    g.mode = "playing"
    for _, sample in ipairs({ { 0, -1, "up" }, { 0, 1, "down" }, { 0.3, -1, "up" },
        { -0.3, 1, "down" }, { 1, -1, "side" }, { -1, 1, "side" } }) do
        for _, moving in ipairs({ true, false }) do
            g.player.moving = moving
            ActionState.SetLocomotion(g, moving and "walk" or "idle", sample[1], sample[2])
            local expected = sample[3] == "side" and (moving and "walk" or "idle")
                or sample[3] .. (moving and "Walk" or "Idle")
            Check(Animation.Select(g) == expected, "cardinal/diagonal movement and stopped facing")
        end
    end
    g.player.moving = true
    ActionState.SetLocomotion(g, "run", 0, -1)
    for i = 0, 3 do
        g.locomotion.time = g.locomotion.duration * i / 4
        local state, frame = Animation.Select(g)
        Check(state == "upWalk" and frame == i + 1, "upward run cycles four frames")
    end
    print("[主角动画回归] " .. count .. " checks passed")
    return count
end

return Tests
