local G=require("Game")
local T={}
function T.Run()
 local update
 for i=1,100 do local name,value=debug.getupvalue(G.Update,i);if not name then break end;if name=="UpdateShots"then update=value end end
 assert(update,"actual projectile update available")
 local n=0
 for _,kind in ipairs({"binary","paperclip","staple"})do
  for _,wall in ipairs({false,true})do
   local g=G.New("programmer");g.effects={};g.enemies={};g.crit=0
   -- No geometry, or an explicit wall across the projectile's path.
   g.room.obstacles=wall and{{x=550,y=500,w=20,h=150}}or{}
   g.room.navigation=nil;g.navigation=nil
   if not wall then local e=G.Spawn(g,1,565,580);e.hp=10000;e.maxHp=10000;e.shield=0;e.armor=0 end
   g.shots={{x=520,y=580,vx=640,vy=0,life=1,damage=10,pierce=0,hit={},kind=kind,digit=1}}
   local original=G.GetObstacles
   G.GetObstacles=function()return g.room.obstacles end
   local ok,err=pcall(update,g,.12)
   G.GetObstacles=original
   assert(ok,err)
   local expected=kind=="binary"and"binaryHit"or(kind=="paperclip"and"paperclipHit"or"stapleHit")
   local found=false;for _,fx in ipairs(g.effects)do if fx.kind==expected then found=true end;if kind~="staple"then assert(fx.kind~="stapleHit","foreign stapler FX")end end
   assert(found,kind..(wall and" wall"or" enemy").." impact effect")
   n=n+1
  end
 end
 print("[弹体特效回归] "..n.." checks passed")
 return n
end
return T
