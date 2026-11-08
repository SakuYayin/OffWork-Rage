-- Enemy clocks advance only in Game.Update. Rendering never creates damage.
local Animation={}
local NAMES={"ghost","paper","message","pot"}
function Animation.Name(e)
    if e.kind==5 then return e.bossFloor==1 and "coworker"or(e.bossFloor==2 and "supervisor"or"owner")end
    if e.kind>=6 then return require("Enemies").NAME(e.kind) end
    return NAMES[e.kind]
end
function Animation.Start(e,kind,nx,ny)
    if e.enemyAction then return false end
    local dash=kind=="dash";local boss=kind=="volley"
    e.enemyAction={kind=kind,time=0,duration=dash and 1.35 or(boss and .85 or .60),
        impactAt=dash and .85 or(boss and .32 or .24),impactEnd=dash and 1.25 or(boss and .53 or .36),
        faceX=nx,faceY=ny,impactDone=false}
    e.faceX,e.faceY=nx,ny
    return true
end
function Animation.Step(g,e,dt,onImpact)
    e.animationTime=(e.animationTime or 0)+dt
    e.attackCooldown=math.max(0,(e.attackCooldown or 0)-dt)
    local a=e.enemyAction;if not a then return end
    a.time=math.min(a.duration,a.time+dt)
    if not a.impactDone and a.time+1e-6>=a.impactAt then
        a.impactDone=true;onImpact(g,e,a)
    end
    if a.time+1e-6>=a.duration then e.enemyAction=nil end
end
function Animation.Select(g,e)
    if e.deathTime then return "defeat",math.min(4,math.floor(e.deathTime/.48*4)+1),(e.faceX or 1)<0 end
    local a=e.enemyAction
    if a then
        local index=a.time<a.impactAt*.5 and 1 or(a.time<a.impactAt and 2 or(a.time<a.impactEnd and 3 or 4))
        return "attack",index,a.faceX<0
    end
    if (e.hit or 0)>0 then return "defeat",1,(e.faceX or 1)<0 end
    -- New AI brains keep their own gameplay timers. Reading those clocks here
    -- plays the authored attack poses without adding or advancing damage.
    local ai=e.ai
    if ai then
        local flip=(e.faceX or 1)<0
        if ai.state=="windup"then return "attack",(ai.t or 0)<(ai.windup or .6)*.5 and 1 or 2,flip end
        if ai.state=="charge"then return "attack",3,flip end
        if ai.state=="recover"then return "attack",4,flip end
        local cd=ai.brain=="spitter"and ai.fireCd or(ai.brain=="summoner"and ai.summonCd or nil)
        local period=ai.brain=="spitter"and 1.8 or 5
        if cd and cd<.3 then return "attack",cd>.15 and 1 or 2,flip end
        if cd and cd>period-.16 then return "attack",cd>period-.08 and 3 or 4,flip end
    end
    local x,y=e.faceX or 1,e.faceY or 0
    local direction=math.abs(y)>math.abs(x) and(y<0 and "upWalk"or"downWalk")or"walk"
    local moving=e.moving==true
    local time=g.mode=="menu" and g.visualTime or(e.animationTime or 0)
    local duration=moving and .72 or 1.2
    local index=moving and math.floor((time+(e.seed or 0))%duration/duration*4)+1 or 1
    -- Standing front/back preserves direction by holding the matching walk pose.
    if not moving and direction=="walk"then direction="idle";index=math.floor(time%duration/duration*4)+1 end
    return direction,index,direction~="upWalk"and direction~="downWalk"and x<0
end
return Animation
