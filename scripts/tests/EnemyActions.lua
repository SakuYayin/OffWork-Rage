local Game=require("Game")
local Animation=require("EnemyAnimation")
local Sprites=require("EnemySprites")
local Tests={}
function Tests.Run()
    local n=0;local function Check(v,m)assert(v,m);n=n+1 end
    for _,id in ipairs({"ghost","paper","message","pot","coworker","supervisor","owner"})do
        local d=assert(Sprites[id])
        for _,state in ipairs({"idle","walk","upWalk","downWalk","attack","defeat"})do
            Check(#d.frames[state]==4,"four authored frames")
            for _,f in ipairs(d.frames[state])do
                Check(f.x>=0 and f.y>=0 and f.x+f.w<=d.width and f.y+f.h<=d.height,"frame stays in atlas")
                Check(f.anchorX>=0 and f.anchorX<=f.w,"foot pivot inside frame")
            end
        end
    end
    for _,kind in ipairs({"melee","ranged","volley","dash"})do
        local e={kind=1,animationTime=0,faceX=1,faceY=0,hit=0}
        Animation.Start(e,kind,-1,0);local action=e.enemyAction;local hits=0
        for i=1,math.floor((action.impactAt-.02)/.01)do Animation.Step({},e,.01,function()hits=hits+1 end)end
        Check(hits==0,"anticipation never deals early damage")
        for i=1,150 do Animation.Step({},e,.01,function()hits=hits+1 end)end
        Check(hits==1 and not e.enemyAction,"impact happens once, recovery completes")
    end
    local function Fixture()
        local g=Game.New("male");g.mode="playing";g.waveTimer=999;g.meleeTimer=999;g.staplerTimer=999;g.coffeeTimer=999
        g.player.x,g.player.y,g.player.invuln=520,580,0
        return g
    end
    local g=Fixture();local e=assert(Game.Spawn(g,1,550,580));e.speed=0
    local hp=g.player.hp
    Game.Update(g,.02,0,0)
    Check(e.enemyAction and g.player.hp==hp,"close enemy starts a visible windup")
    for i=1,9 do Game.Update(g,.02,0,0)end
    Check(g.player.hp==hp,"player unharmed before melee contact frame")
    g.mode="paused";local time=e.enemyAction.time
    for i=1,20 do Game.UpdateVisuals(g,.05);Game.Update(g,.05,0,0)end
    Check(e.enemyAction.time==time and g.player.hp==hp,"pause freezes enemy attack and damage")
    g.mode="playing";for i=1,4 do Game.Update(g,.02,0,0)end
    Check(g.player.hp<hp,"damage lands on actual attack contact")
    local g2=Fixture();local e2=assert(Game.Spawn(g2,1,550,580));e2.speed=0
    Game.Update(g2,.02,0,0);g2.player.x=430;local hp2=g2.player.hp
    for i=1,30 do Game.Update(g2,.02,0,0)end
    Check(g2.player.hp==hp2,"moving away during windup evades melee")
    local g3=Fixture();local shooter=assert(Game.Spawn(g3,3,650,580));shooter.speed=0;shooter.shootTimer=0
    Game.Update(g3,.02,0,0)
    Check(shooter.enemyAction and #g3.hostileShots==0,"ranged enemy telegraphs before emitting projectile")
    for i=1,9 do Game.Update(g3,.02,0,0)end
    Check(#g3.hostileShots==0,"no ranged projectile before contact")
    for i=1,5 do Game.Update(g3,.02,0,0)end
    Check(#g3.hostileShots==1,"ranged contact emits one projectile")
    local g4=Fixture();local target=assert(Game.Spawn(g4,1,550,580));g4.crit=0
    Game.Hit(g4,target,999,1,0,0)
    Check(#g4.defeated==1 and g4.defeated[1].deathTime==0,"death spawns one bounded visual record")
    for i=1,30 do Game.Update(g4,.02,0,0);Game.UpdateVisuals(g4,.02)end
    Check(#g4.defeated==0,"defeat animation expires without blocking room clear")
    for _,kind in ipairs({1,5})do
        local last=Fixture();local victim=assert(Game.Spawn(last,kind,550,580));Game.Hit(last,victim,999999,1,0,0)
        last.mode="upgrade";for i=1,30 do Game.UpdateVisuals(last,.02)end
        Check(#last.defeated==0,"last enemy and boss expire during reward overlay")
        last.defeated={{deathTime=0}};last.mode="playing";last.roomCleared=true
        for i=1,30 do Game.UpdateVisuals(last,.02)end
        Check(#last.defeated==0,"cleared room cannot retain last corpse")
        last.defeated={{deathTime=0}};last.mode="paused";Game.UpdateVisuals(last,1)
        Check(last.defeated[1].deathTime==0,"manual pause freezes death animation")
    end
    print("[怪物动作回归] "..n.." checks passed");return n
end
return Tests
