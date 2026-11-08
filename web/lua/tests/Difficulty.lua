local D=require("Difficulty")
local G=require("Game")
local E=require("Endless")
local A=require("HeroAnimation")
local EA=require("EnemyAnimation")
local B=require("Buffs")
local Enemies=require("Enemies")
local T={}
function T.Run()
 local n=0;local function check(v,m)assert(v,m);n=n+1 end
 local function fixture(id,w)
  local g=G.New(id or "male");g.mode="playing";g.waveTimer=999;g.meleeTimer=999;g.primaryTimer=999;g.staplerTimer=999;g.coffeeTimer=999
  g.crit=0;g.player.x=520;g.player.y=580;g.player.invuln=999
  if w then E.Start(g,{seed=12});g.endless.wave=w;g.endless.phase="fighting";g.endless.budget=999;g.endless.spawnTimer=999 end
  return g
 end
 local function enemy(g,x)
  local e=assert(G.Spawn(g,1,x or 570,580));e.hp=100000;e.maxHp=e.hp;e.speed=0;e.attackCooldown=999;e.affix=nil;e.armor=0;e.shield=0;e.damageReduction=0
  return e
 end
 local function tick(g,t)for _=1,math.floor(t/.02+.5)do G.Update(g,.02,0,0)end end
 for _,w in ipairs({1,2,5,10,30,100,1000})do
  check(D.Armor(w)>=0 and D.Armor(w)<=18,"armor bound")
  check(D.ShieldRatio(w)>=0 and D.ShieldRatio(w)<=.30,"shield growth bound")
  check(D.EliteChance(w)>=0 and D.EliteChance(w)<=.32,"elite chance bound")
  check(D.AliveCap(w)>=17 and D.AliveCap(w)<=45,"density bound")
  check(D.BatchGap(w)>=.65 and D.BatchGap(w)<=1.35,"spawn pacing bound")
  check(D.HealMul(w)>=.45 and D.HealMul(w)<=1,"healing bound")
  check(D.XpMul(w)>=.60 and D.XpMul(w)<=1,"experience bound")
  check(D.AttackRate(w)>=1 and D.AttackRate(w)<=1.45,"attack frequency bound")
 end
 local g=fixture();local e=enemy(g)
 G.Hit(g,e,100,1,0,0);local plain=100000-e.hp
 e.hp=100000;e.armor=18;e.damageReduction=.28;G.Hit(g,e,100,1,0,0)
 check(100000-e.hp<plain and e.hp<100000,"armor and guard actually reduce damage")
 e.hp=100000;e.shield=100;G.Hit(g,e,20,1,0,0)
 check(e.hp==100000 and e.shield<100,"enemy shield absorbs damage before hp")
 e.shield=0;e.hp=100000;G.TrueHit(g,e,100,1,0,0)
 check(100000-e.hp==math.floor(100*g.damage),"true damage bypasses armor without reapplying procs")
 for _,w in ipairs({1,50})do
  local h=fixture("male",w);h.player.hp=1;G.Heal(h,20)
  check(math.abs(h.player.hp-(1+20*D.HealMul(w)))<.001,"actual recovery follows wave")
 end
 local saved=math.random
 for i,id in ipairs(D.affixes)do
  local calls=0;math.random=function(a,b)calls=calls+1;if a then return i end;return 0 end
  local x={maxHp=100,hp=100,damage=10,speed=50,xp=10};D.Apply({endless={active=true,wave=30}},x,false)
  math.random=saved
  check(x.elite and x.affix==id and x.maxHp==165,"all six elite mechanics can spawn")
 end
 local r=fixture();local re=enemy(r,570);re.affix="reflect";re.reflectCd=0;r.player.invuln=0;local hp=r.player.hp
 G.Hit(r,re,10,1,0,0);check(re.reflectPending==.35 and r.player.hp==hp,"reflect starts warning, never immediate")
 tick(r,.2);check(r.player.hp==hp,"reflect anticipation is safe")
 tick(r,.2);check(r.player.hp<hp and hp-r.player.hp<=3,"reflect is delayed and capped")
 re.reflectPending=nil;re.reflectCd=0;r.player.invuln=0;G.TrueHit(r,re,10,1,0,0)
 check(re.reflectPending==nil,"DOT and true hits never recursively reflect")
 re.x=850;G.Hit(r,re,10,1,0,0);check(re.reflectPending==nil,"distant ranged player cannot trigger reflect")
 local s=fixture();local se=enemy(s,700);se.affix="shield";se.shieldMax=100;se.shield=0;se.shieldQuiet=0
 tick(s,2);check(se.shield==0,"shield cannot regenerate during quiet delay")
 tick(s,1.5);check(se.shield>0 and se.shield<=100,"shield regeneration starts after three seconds and stays bounded")
 local u=fixture();local ue=enemy(u,700);ue.affix="summon";ue.summonsLeft=3;ue.summonTimer=0
 tick(u,.02);check(ue.summonsLeft==2 and #u.enemies==2,"summoner elite creates an actual child")
 for i=1,3 do ue.summonTimer=0;tick(u,.02)end
 check(ue.summonsLeft==0 and #u.enemies==4,"summoner elite cannot create more than three children")
 local v=fixture();local ve=enemy(v);ve.affix="volatile";v.player.invuln=0;hp=v.player.hp
 tick(v,.02);check(ve.blastTimer>0 and v.player.hp==hp,"volatile elite visibly arms before explosion")
 tick(v,.8);check(ve.hp<=0 and v.player.hp<hp,"volatile elite explodes once and dies")
 for k=1,6 do
  local b=fixture("male",k*3);b.enemies={};E.SpawnBoss(b);local boss=assert(b.enemies[1]);local identity=(k-1)%3+1
  check(boss.bossFloor==identity and b.floor==3,"boss identity is independent of arena floor")
  check(EA.Name(boss)==({"coworker","supervisor","owner"})[identity],"endless boss name maps to matching model")
  check(b.bossName==E.BOSS_NAMES[identity],"endless boss announced identity matches model")
  check(boss.damage==math.floor(19*E.DmgScale(k*3)+.5)and boss.speed==46*E.SpdScale(k*3),"boss actual damage and movement grow with wave")
  if k<=3 then
   b.bossTimer=999;EA.Start(boss,"volley",0,1);tick(b,.34)
   check(identity==1 and #b.hostileShots==3 or identity~=1 and #b.hostileShots>=10,"boss attacks follow identity rather than floor three")
  end
 end
 for identity=1,4 do
  local c=G.New("male");local old=math.random
  math.random=function(a,b)if a==1 and b==4 then return identity end;if a==nil then return old()elseif b==nil then return old(a)else return old(a,b)end end
  G.EnterRoom(c,8);math.random=old;local boss=assert(c.enemies[1])
  check(boss.bossIdentity==identity,"campaign may choose each of four bosses")
  check(EA.Name(boss)==({"coworker","supervisor","owner","printerBoss"})[identity],"campaign boss model matches random identity")
  check(identity~=4 or boss.maxHp==375,"printer boss health adapts to first floor rather than fixed endgame health")
 end
 local cap=fixture("male",100);cap.enemies={};cap.endless.spawnTimer=0;cap.endless.budget=999
 for i=1,20 do cap.endless.spawnTimer=0;E.TickSpawn(cap,.02)end
 check(#cap.enemies==45,"spawning never exceeds late wave density cap")
 local early=fixture("male",1);early.enemies={};early.endless.spawnTimer=0
 E.TickSpawn(early,.02);E.TickSpawn(early,2)
 check(#early.enemies==D.AliveCap(1),"early wave density is deliberately lower")
 local fastEnemy=fixture("male",50);local spitter=assert(G.Spawn(fastEnemy,7,700,580));spitter.ai.fireCd=.3
 Enemies.Step(fastEnemy,spitter,.10);check(#fastEnemy.hostileShots==0,"high pressure keeps an actual attack interval")
 Enemies.Step(fastEnemy,spitter,.12);check(#fastEnemy.hostileShots==3,"enemy attacks genuinely accelerate rather than only its movement")
 local p=fixture("programmer");p.primaryTimer=0;local pe=enemy(p,850);local starts=0;local last=0
 for i=1,150 do G.Update(p,.02,0,0);if p.binaryCount>last then starts=starts+1;last=p.binaryCount end end
 check(starts>=9 and starts<=11,"programmer base shot cadence is reduced to about 3.57 per second")
 p.attackSpeed=100;B.Apply(p,"cacheWarmup");p.overclock=100;local begin=p.binaryCount
 tick(p,2);check(p.binaryCount-begin<=13,"all attack boosts respect 6.25 volleys per second ceiling")
 p.action=nil;p.player.moving=false;p.typingUntil=10;p.time=.17;local state,frame=A.Select(p)
 check(state=="attack"and frame==2,"typing uses global continuous frame rather than shot restart")
 p.time=.33;check(select(2,A.Select(p))==3,"typing loop progresses smoothly between projectiles")
 p.player.moving=true;p.player.faceX=0;p.player.faceY=-1;p.locomotion.faceX=0;p.locomotion.faceY=-1
 check(select(1,A.Select(p))=="upWalk","programmer keeps walk animation while firing on the move")
 print("[难度与平衡回归] "..n.." checks passed")
 return true
end
return T
