-- Pure selection logic: frame time follows gameplay actions, so pauses freeze
-- the sprite and attack contact remains aligned with the actual damage event.
local HeroAnimation = {}

-- Diagonals use the nearest cardinal direction; exact diagonals keep the side
-- view. Locomotion retains its last vector after releasing the movement keys.
function HeroAnimation.Direction(x, y)
    if math.abs(y or 0) > math.abs(x or 0) then
        return y < 0 and "up" or "down"
    end
    return "side"
end

local function LocomotionState(g, moving)
    local pose = g.locomotion or g.player
    local direction = HeroAnimation.Direction(pose.faceX, pose.faceY)
    if direction == "side" then return moving and "walk" or "idle" end
    return direction .. (moving and "Walk" or "Idle")
end

function HeroAnimation.Select(g)
    local action = g.action
    -- Keep a steady typing loop across projectile events instead of snapping to frame 1.
    if g.heroId=="programmer"and(g.typingUntil or 0)>(g.time or 0)
        and(not action or action.name=="binary"or action.phase=="locomotion")then
        if g.player.moving then
            local time=g.locomotion and g.locomotion.time or g.time or 0
            return LocomotionState(g,true),math.floor((time%.72)/.18)+1
        end
        return "attack",math.floor(((g.time or 0)%.64)/.16)+1
    end
    if action and action.phase ~= "locomotion" then
        local name = action.name
        if name == "hurt" then return LocomotionState(g, false), 1 end
        local state = (name=="keyboard"or name=="folder"or name=="binary"or(name=="stapler"and g.heroId=="female"))and "attack" or "skill"
        local frame
        if action.time < action.windup then
            frame = action.time < action.windup * 0.5 and 1 or 2
        elseif action.time < action.impactAt then frame = 2
        elseif action.time < action.impactEnd then frame = 3
        else frame = 4 end
        return state, frame
    end
    local locomotion = g.locomotion
    local moving = g.player.moving == true
    local state = LocomotionState(g, moving)
    local time = locomotion and locomotion.time or 0
    local duration = locomotion and locomotion.duration or (moving and 0.72 or 1.2)
    return state, math.min(4, math.floor((time % duration) / duration * 4) + 1)
end

return HeroAnimation
