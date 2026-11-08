local G=require("Game")
local L=require("Loadout")
local B=require("Buffs")
local W=require("Weapons")
local E=require("Endless")
local A=require("HeroAnimation")
local T={}
function T.Run()
 local n=0;local function check(v,m)assert(v,m);n=n+1 end
 local function fixture(id)
  local g=G.New(id);g.mode="playing";g.waveTimer=999;g.player.x=520;g.player.y=580;g.player.invuln=999;g.crit=0
  return g
 end
 local function target(g,x)
  local e=assert(G.Spawn(g,4,x or 570,580));e.hp=1000000;e.maxHp=e.hp;e.speed=0;e.attackCooldown=999;return e
 end
 local function tick(g,count)
  for i=1,count do G.Update(g,.02,0,0);G.UpdateVisuals(g,.02)end
 end
 for _,row in ipairs({{"male","keyboard"},{"female","stapler"},{"intern","folder"},{"programmer","binary"}})do
  for _,endless in ipairs({false,true})do
   local g=fixture(row[1]);if endless then E.Start(g)end
   check(L.Primary(g)==row[2]and #L.List(g)==1,"one correct primary in each mode")
   check(L.Acquire(g,"coffee")and #L.List(g)==2,"one additional slot")
   check(not L.Acquire(g,"thermos")and W.Upgrade(g,"thermos")==0,"third weapon rejected by slot and upgrade API")
   check(L.Acquire(g,"coffee")and #L.List(g)==2,"existing weapon may be reinforced")
   for i=1,30 do for _,c in ipairs(G.RollChoices(g))do
    check(not L.names[c.id]or L.Has(g,c.id),"full loadout offers no third weapon")
    check(c.id~="range"or L.Has(g,"keyboard")or L.Has(g,"folder")or L.Has(g,"thermos"),"range only offered to a melee loadout")
    local d=B.Get(c.id);check(not d or not d.hero or d.hero==row[1],"exclusive buffs stay with owner")
   end end
   g.mode="upgrade";g.choices={{id="thermos"}};G.Choose(g,1)
   check(g.mode=="upgrade"and W.Level(g,"thermos")==0,"stale third weapon card cannot bypass limit")
   g.mode="shop";g.coins=100;g.shopItems={{id="stapler",price=10}};local owned=L.Has(g,"stapler")
   check(G.Buy(g,1)==owned,"shop obeys two-slot rule")
  end
 end
 local f=fixture("female");target(f);tick(f,45)
 check(f.stapler==1 and not f.actionTracks.keyboard,"female starts ranged and has no keyboard")
 local function impacts(g,seconds)
  local count,seen=0,{};local dummy=target(g,g.heroId=="programmer"and 850 or nil)
  for i=1,math.floor(seconds/.02)do dummy.x,dummy.y,dummy.knockX,dummy.knockY=g.heroId=="programmer"and 850 or 570,580,0,0;tick(g,1);for _,e in ipairs(g.actionEvents)do
   if e.kind=="impact"and not seen[e.serial]then seen[e.serial]=true;count=count+1 end
  end end;return count
 end
 local normal,fast=fixture("female"),fixture("female");fast.attackSpeed=2
 check(impacts(fast,4)>impacts(normal,4),"attack speed actually accelerates stapler")
 local g=fixture("intern");local one=target(g,565);local two=target(g,590);g.primaryTimer=0
 tick(g,20);check(one.hp==1000000 and two.hp==1000000,"heavy folder has real anticipation")
 tick(g,5);check(one.hp<999900 and two.hp<999900,"folder damages multiple nearby enemies")
 check(g.action and select(1,A.Select(g))=="attack","folder uses its authored attack state")
 local p=fixture("programmer");local fired=impacts(p,2);check(fired>=6 and fired<=8,"binary remains fast at a bounded 3.57 volleys per second")
 local digits={};for _,s in ipairs(p.shots)do if s.kind=="binary"then digits[s.digit]=true;check(s.damage==12,"binary has low base damage")end end
 check(digits[0]and digits[1],"binary alternates zero and one")
 check(p.player.maxHp<90 and p.player.speed<156,"programmer low health and move speed")
 local shield=fixture("intern");shield.player.invuln=0;local hp=shield.player.hp
 G.TakeDamage(shield,100);check(shield.player.hp==hp and shield.shield==30,"shield absorbs reduced hit")
 check(shield.effects[#shield.effects].text=="护盾吸收","fully absorbed hit has shield feedback instead of minus zero")
 shield.player.invuln=0;G.TakeDamage(shield,100);check(shield.player.hp==hp-40 and shield.shield==0,"shield overflow reaches health with thirty percent reduction")
 shield.player.invuln=999;tick(shield,260);check(shield.shield>0,"quiet period regenerates intern shield")
 B.Apply(shield,"internProtection");check(shield.shieldMax==127,"protection raises actual shield capacity")
 check(B.Apply(p,"internProtection")==0 and not p.buffs.internProtection,"exclusive buff refuses wrong hero")
 local base=fixture("intern");local boosted=fixture("intern");B.Apply(boosted,"internTempo")
 check(impacts(boosted,12)>impacts(base,12),"intern tempo increases real swing cadence")
 local threaded=fixture("programmer");B.Apply(threaded,"parallelThreads");target(threaded);tick(threaded,5)
 check(#threaded.shots==2,"parallel threads emits additional projectile")
 local exploit=fixture("programmer");B.Apply(exploit,"codeExploit");target(exploit);tick(exploit,5)
 check(exploit.shots[1].damage==15 and exploit.shots[1].pierce==2,"exploit damage and pierce both apply")
 for _,id in ipairs({"intern","programmer"})do local u=fixture(id);u.rage=100;check(G.Burst(u),"new hero starts own ultimate");tick(u,10)
  check(id=="intern"and u.shield==u.shieldMax and u.player.invuln>1 or id=="programmer"and(u.overclock or 0)>3,"new ultimate effect")
 end
 local drop=fixture("male");drop.meleeTimer=999;drop.xpNeed=999999
 for i=1,5 do local e=target(drop,570);G.Hit(drop,e,9999999,0,0,0)end
 local pack,total
 total=0;for _,gem in ipairs(drop.gems)do if gem.weapon then pack=gem;total=total+1 end end
 check(pack and total==1 and drop.firstWeaponDrop,"fifth cumulative kill drops one actual weapon pack")
 drop.player.x,drop.player.y=pack.x,pack.y;tick(drop,1)
 check(drop.secondaryWeapon==pack.weapon and #L.List(drop)==2,"world pickup equips secondary")
 check(pack.weapon=="stapler"and drop.stapler==1 or pack.weapon=="coffee"and drop.coffee==1 or W.Level(drop,pack.weapon)==1,"picked weapon has real active level")
 for i=1,6 do local e=target(drop,570);G.Hit(drop,e,9999999,0,0,0)end
 total=0;for _,gem in ipairs(drop.gems)do if gem.weapon then total=total+1 end end
 check(total==0,"weapon packs cannot farm indefinitely")
 local full=fixture("male");G.PickWeapon(full,"coffee");full.gems={{x=520,y=580,weapon="stapler",value=0}}
 tick(full,2);check(#full.gems==1 and full.stapler==0 and full.secondaryWeapon=="coffee","full slots leave third weapon on ground")
 local clear=fixture("male");clear.wave=clear.totalWaves;clear.gems={{x=520,y=580,weapon="stapler"}}
 tick(clear,1);check(clear.secondaryWeapon=="stapler"and clear.mode=="upgrade","room clear safely collects weapon with no XP value")
 print("[四角色双武器回归] "..n.." checks passed");return n
end
return T
