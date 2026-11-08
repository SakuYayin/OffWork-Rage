-- Reward magnitudes are separate from ownership and integer card levels.
local S={}
function S.Generic(g)return g and g.heroId=="intern"and .5 or 1 end
function S.Exclusive(g)return g and g.heroId=="intern"and .9 or 1 end
function S.Gain(g,value)return value>0 and value*S.Generic(g)or value end
function S.Growth(g,base,value)return base+(value-base)*S.Generic(g)end
-- Preserve half a projectile/pierce/reroll as credit, not a rounded-away reward.
function S.Count(g,key,value)
 g.scalingCredits=g.scalingCredits or {}
 local total=value+(g.scalingCredits[key]or 0)
 local whole=math.floor(total+1e-9)
 g.scalingCredits[key]=math.max(0,total-whole)
 return whole
end
return S
