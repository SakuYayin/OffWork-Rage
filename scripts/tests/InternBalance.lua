local G=require("Game")
local B=require("Buffs")
local W=require("Weapons")
local S=require("HeroScaling")
local A=require("ActionState")
local Events=require("Events")
local T={}
function T.Run()
 local n=0;local function check(v,m)assert(v,m);n=n+1 end
 local function near(a,b,m)check(math.abs(a-b)<1e-7,m..": "..tostring(a).." vs "..tostring(b))end
 local function fixture(id)
  local g=G.New(id or "intern");g.mode="playing";g.waveTimer=999;g.meleeTimer=999;g.staplerTimer=999;g.coffeeTimer=999;g.primaryTimer=999
  g.xpNeed=999999;g.crit=0;g.player.invuln=999;g.player.x=520;g.player.y=580
  return g
 end
 local function target(g,x)
  local e=assert(G.Spawn(g,4,x or 570,580));e.hp=1000000;e.maxHp=e.hp;e.speed=0;e.attackCooldown=999;e.shield=0;e.armor=0;e.damageReduction=0;return e
 end
 local function tick(g,count)for i=1,count do G.Update(g,.02,0,0)end end
 local function choose(g,id)
  g.mode="upgrade";g.upgradeSource="level";g.choices={{id=id,title=id}};G.Choose(g,1)
 end
 local g=fixture();check(g.player.maxHp==120 and g.player.speed==130,"intern base health and speed use latest request")
 near(g.damage,1.125,"initial damage reduced ten percent exactly once")
 check(g.shieldMax==100 and g.hero.reduction==.30,"base shield and reduction mechanisms retained")
 for _,id in ipairs({"male","female","programmer"})do check(S.Generic(fixture(id))==1,"other heroes retain full generic effects")end
 for _,id in ipairs({"folderReinforced","internProtection","internTempo"})do
  local u=fixture();for level=1,3 do
   check(B.Apply(u,id)==level and B.Level(u,id)==level,"exclusive ownership uses whole levels")
   near(B.EffectLevel(u,id),level*.9,"exclusive effects ninety percent, never multiplied by generic fifty percent")
  end
 end
 local folder=fixture();local fe=target(folder);B.Apply(folder,"folderReinforced");A.Start(folder,"folder",1,0);tick(folder,23)
 check(fe.hp==1000000-math.floor(110*1.225*1.125),"real folder impact applies exclusive twenty two point five percent and new base damage once")
 local size;for _,fx in ipairs(folder.effects)do if fx.kind=="folderSlam"then size=fx.size end end
 near(size,(118+10.8)*2,"real folder impact radius uses exclusive ten point eight increase")
 local tempo=fixture();target(tempo);tempo.primaryTimer=0;B.Apply(tempo,"internTempo");tick(tempo,1)
 near(tempo.primaryTimer,2.4/1.108,"real folder cadence uses ten point eight percent")
 local protect=fixture();protect.shield=0;B.Apply(protect,"internProtection")
 near(protect.shieldMax,127,"exclusive capacity +27");near(protect.shield,27,"exclusive instant shield +27")
 tick(protect,1);near(protect.shieldMax,127,"per-frame shield capacity does not restore old +30")
 protect.shield=0;protect.player.invuln=0;G.TakeDamage(protect,100)
 check(protect.player.hp==55,"exclusive damage reduction is thirty plus five point four percent")
 for _,spec in ipairs({{"damage",.125},{"attack",.11},{"range",.10},{"magnet",35},{"regen",.6},{"armor",1.5},{"crit",.075}})do
  local u=fixture();local key=({attack="attackSpeed"})[spec[1]]or spec[1];local before=u[key]
  choose(u,spec[1]);near(u[key]-before,spec[2],"upgrade "..spec[1].." gives half increment")
 end
 local speed=fixture();choose(speed,"speed");near(speed.player.speed,139.75,"movement upgrade multiplies by 1.075")
 local hp=fixture();hp.player.hp=20;choose(hp,"health")
 near(hp.player.maxHp,132.5,"health cap upgrade keeps half points without early rounding")
 near(hp.player.hp,37.5,"health card recovery is halved once")
 local rage=fixture();rage.rage=20;rage.player.hp=20;choose(rage,"rage")
 near(rage.rage,60,"rage card fills half the remaining meter");near(rage.player.hp,30,"rage card healing is halved once")
 local passive=fixture();passive.player.hp=20;choose(passive,"regen");tick(passive,50)
 near(passive.player.hp,20.6,"passive recovery is not halved a second time")
 local ordinary=fixture();ordinary.player.hp=20;G.Heal(ordinary,10);near(ordinary.player.hp,30,"ordinary recovery is not a generic BUFF")
 local perk=fixture();B.Apply(perk,"critDamage");near(B.CritMul(perk),1.975,"critical bonus half, base multiplier retained")
 B.Apply(perk,"haste");near(B.AttackSpeedMul(perk),1.06,"haste six percent")
 B.Apply(perk,"lastStand");perk.player.hp=20
 near(B.AttackSpeedMul(perk),1.06*1.10,"last stand attack bonus half")
 near(B.DamageTakenMul(perk),.8,"last stand twenty percent reduction")
 B.Apply(perk,"execute");near(B.ExecuteMul(perk,{hp=17,maxHp=100}),1.6,"execute bonus half")
 near(B.ExecuteMul(perk,{hp=19,maxHp=100}),1,"execute condition unchanged")
 B.Apply(perk,"rageGain");near(B.RageMul(perk),1.15,"rage gain fifteen percent")
 B.Apply(perk,"coinGain");near(B.CoinMul(perk),1.175,"coin gain seventeen point five percent")
 local total=0;for i=1,40 do total=total+B.CoinReward(perk,3)end;check(total==141,"fractional currency credits preserve exact long run half bonus")
 B.Apply(perk,"ultPower");near(B.UltPower(perk),1.1,"ultimate damage ten percent")
 near(B.UltRadius(perk),1.1,"ultimate range ten percent")
 local magnet=fixture();local before=magnet.magnet;B.Apply(magnet,"magnetPlus");near(magnet.magnet-before,35,"magnet perk half")
 B.Apply(magnet,"magnetPlus");B.Apply(magnet,"magnetPlus");near(magnet.magnet-before,70,"max level cannot regrant an immediate bonus")
 local shield=fixture();shield.shield=0;shield.player.invuln=0;B.Apply(shield,"shield");B.Update(shield,.02)
 G.TakeDamage(shield,40);check(shield.player.hp==106 and B.ShieldCount(shield)==0,"one generic shield charge absorbs half the incoming hit before base reduction")
 local dash=fixture();dash.player.invuln=0;B.Apply(dash,"dash");check(B.StartDash(dash,1,0),"dash unlock still works")
 near(dash.player.dashTimer,.09,"dash travel time halved");near(dash.player.invuln,.09,"dash invulnerability halved")
 B.Apply(dash,"dash");dash.buffState.dash.cooldown=0;B.StartDash(dash,1,0);near(dash.buffState.dash.cooldown,3.6,"second dash level cooldown improvement half")
 local rolls=fixture();B.Apply(rolls,"reroll");check(B.RerollGrant(rolls)==0 and B.RerollGrant(rolls)==1,"half reroll retained for next upgrade")
 B.Apply(rolls,"reroll");check(B.RerollGrant(rolls)==1,"two reroll levels grant one whole reroll")
 local multi=fixture();B.Apply(multi,"multishot");local extra=0;for i=1,16 do extra=extra+B.ExtraProjectiles(multi)end
 check(extra==2,"multishot half extra projectile cadence, no chance-based loss")
 local dots=fixture();local e=target(dots);dots.player.hp=20;B.Apply(dots,"elemental");B.Apply(dots,"lifesteal");B.Apply(dots,"armorBreak")
 B.OnHit(dots,e,100,false);near(e.dotDps,4,"burn damage four percent");near(dots.player.hp,21.5,"lifesteal one point five percent")
 near(e.armorBreak,1,"armor break stacks remain whole");local old=e.hp;G.Hit(dots,e,20,0,0,0)
 check(old-e.hp==23,"armor break adds one rather than two damage per stack")
 local chained=fixture();local from=target(chained,565);local to=target(chained,585);B.Apply(chained,"chain")
 local saved=math.random;math.random=function()return 0 end;B.OnHit(chained,from,100,false);math.random=saved
 check(to.hp==1000000-math.floor(25*chained.damage),"chain damage half while trigger chance and reach stay unchanged")
 local shop=fixture();shop.mode="shop";shop.coins=100;shop.player.hp=20;shop.shopItems={{id="damage",price=10},{id="heal",price=10}}
 check(G.Buy(shop,1),"shop damage path purchases normally");near(shop.damage,1.25,"shop damage reward halved")
 G.Buy(shop,2);near(shop.player.hp,42.5,"shop recovery halved once")
 local event=fixture();event.player.hp=20;Events.Get("legacy_1").choices[1].apply(event)
 near(event.player.maxHp,125,"event max health half");near(event.player.hp,40,"event recovery half once")
 Events.Get("bl_2").choices[2].apply(event);near(event.attackSpeed,1.075,"event attack gain half")
 Events.Get("sw_1").choices[2].apply(event);near(event.player.speed,139,"event movement gain half")
 near(event.player.hp,25,"negative event cost not reduced")
 event.rage=20;Events.Get("legacy_3").choices[1].apply(event);near(event.damage,1.225,"event damage gain half");near(event.rage,60,"event rage half missing meter")
 Events.Get("legacy_2").choices[1].apply(event);check(event.coins==50,"base event currency is not halved a second time")
 for _,row in ipairs({{"thermos",W.ThermosDamage},{"thermos",W.ThermosPoolDamage},{"thermos",W.ThermosRadius},{"paperclip",W.PaperclipDamage},{"paperclip",W.PaperclipPierce},{"pie",W.PieDamage},{"pie",W.PiePoolDamage},{"pie",W.PiePoolRadius},{"pie",W.PieExplodeRadius}})do
  local u=fixture();check(G.PickWeapon(u,row[1]),"secondary unlock retains full eligibility")
  near(row[2](1,u),row[2](1),"level one weapon baseline intact")
  for level=2,5 do W.Upgrade(u,row[1]);near(row[2](level,u),row[2](1)+(row[2](level)-row[2](1))*.5,"weapon stat growth halves actual table increments")end
  check(W.Level(u,row[1])==5,"weapon levels and ownership are not fractional")
 end
 local cup=fixture();G.PickWeapon(cup,"thermos");for i=1,4 do W.Upgrade(cup,"thermos")end
 local ce=target(cup);A.Start(cup,"thermos",1,0);tick(cup,10)
 check(ce.hp==1000000-math.floor(75*cup.damage),"real level five thermos deals halfway growth damage rather than half a level")
 local coffee=fixture();G.PickWeapon(coffee,"coffee");choose(coffee,"coffee");choose(coffee,"coffee")
 local enemy=target(coffee,600);local a=A.Start(coffee,"coffee",1,0);a.targetX=600;a.targetY=580;tick(coffee,9)
 near(coffee.pools[1].radius,76,"actual coffee pool level growth halved")
 check(enemy.hp==1000000-math.floor(20*coffee.damage),"actual coffee pool damage growth halved once")
 local ult=fixture();local ue=target(ult);B.Apply(ult,"ultPower");G.BurstImpact(ult)
 check(ue.hp==1000000-math.floor(150*1.1*1.125),"generic ultimate perk actually works at ten percent on intern")
 local shots=fixture();G.PickWeapon(shots,"stapler");choose(shots,"stapler");target(shots,850)
 local counts,pierces={},{}
 for i=1,2 do
  A.Reset(shots);shots.shots={};A.Start(shots,"stapler",1,0);tick(shots,4)
  counts[i]=#shots.shots;pierces[i]=shots.shots[1].pierce;near(shots.shots[1].damage,27.5,"stapler damage growth half")
 end
 check(counts[1]==1 and counts[2]==2,"stapler half additional bullet alternates whole projectiles")
 check(pierces[1]==1 and pierces[2]==2,"half penetration alternates whole penetration counts")
 for _,id in ipairs({"male","female","programmer"})do
  local other=fixture(id);B.Apply(other,"haste");near(B.AttackSpeedMul(other),1.12,"other hero haste unchanged")
  choose(other,"damage");near(other.damage-other.hero.damage,.25,"other hero upgrade unchanged")
 end
 -- 怒气口径（docs/design/15-intern-rage-tuning.md）
 local hurt=fixture();hurt.rage=0;hurt.shield=0;hurt.player.invuln=0
 G.TakeDamage(hurt,10);near(hurt.rage,8,"intern hp loss grants 8 rage")
 local blocked=fixture();blocked.rage=0;blocked.shield=100;blocked.shieldMax=100;blocked.player.invuln=0
 G.TakeDamage(blocked,10);near(blocked.rage,6,"intern full shield hit grants 6 rage")
 check(blocked.player.hp==120,"full shield hit does not damage hp")
 local partial=fixture();partial.rage=0;partial.shield=3;partial.shieldMax=100;partial.player.invuln=0
 G.TakeDamage(partial,100);near(partial.rage,8,"partial shield with hp loss grants 8 rage")
 local buffed=fixture();buffed.rage=0;buffed.shield=0;buffed.player.invuln=0
 B.Apply(buffed,"rageGain");G.TakeDamage(buffed,10)
 near(buffed.rage,9.2,"one rageGain stack multiplies 8 by 1.15")
 local capped=fixture();capped.rage=98;capped.shield=0;capped.player.invuln=0
 G.TakeDamage(capped,10);check(capped.rage==100,"hurt rage still caps at 100")
 local otherMale=G.New("male");otherMale.mode="playing";otherMale.rage=0;otherMale.player.invuln=0
 G.TakeDamage(otherMale,10);near(otherMale.rage,12,"other heroes keep 12 hurt rage")
 local function victim(g,kind)
  local e=assert(G.Spawn(g,kind or 1,570,580))
  e.hp,e.maxHp,e.speed,e.damage,e.attackCooldown,e.shield,e.armor=1,1,0,0,999,0,0
  return e
 end
 local folderKill=fixture();folderKill.rage=0
 G.Hit(folderKill,victim(folderKill,1),100,1,0,280,{rageScale=0.5})
 near(folderKill.rage,1.5,"folder direct normal kill grants 1.5")
 local folderPot=fixture();folderPot.rage=0
 G.Hit(folderPot,victim(folderPot,4),100,1,0,280,{rageScale=0.5})
 near(folderPot.rage,3.5,"folder direct pot kill grants 3.5")
 local ultKill=fixture();ultKill.rage=0
 G.Hit(ultKill,victim(ultKill,1),100,1,0,280,{rageScale=0.9})
 near(ultKill.rage,2.7,"intern ultimate direct normal kill grants 2.7")
 local ultPot=fixture();ultPot.rage=0
 G.Hit(ultPot,victim(ultPot,4),100,1,0,280,{rageScale=0.9})
 near(ultPot.rage,6.3,"intern ultimate direct pot kill grants 6.3")
 local plainKill=fixture();plainKill.rage=0
 G.Hit(plainKill,victim(plainKill,1),100,1,0,280)
 near(plainKill.rage,3,"unmarked normal kill keeps 3")
 local plainPot=fixture();plainPot.rage=0
 G.Hit(plainPot,victim(plainPot,4),100,1,0,280)
 near(plainPot.rage,7,"unmarked pot kill keeps 7")
 local stackKill=fixture();stackKill.rage=0;B.Apply(stackKill,"rageGain");B.Apply(stackKill,"rageGain")
 G.Hit(stackKill,victim(stackKill,1),100,1,0,280,{rageScale=0.5})
 near(stackKill.rage,1.95,"two rageGain stacks turn 1.5 into 1.95")
 -- 真实清场：文件夹与零击杀基线对比，自然恢复相互抵消，差值就是纯击杀部分。
 local function folderSweep(n)
  local g=fixture();g.rage=0
  for i=1,n do local e=assert(G.Spawn(g,1,560+(i-1)*2,580));e.hp,e.maxHp,e.speed,e.attackCooldown=1,1,0,999 end
  A.Start(g,"folder",1,0);tick(g,23)
  return g.rage
 end
 near(folderSweep(10)-folderSweep(0),15,"folders ten kills contribute exactly fifteen rage")
 -- 真实大招：3 只 1 血怪在大招范围内，直接被 direct 命中击杀。
 local burst=fixture();burst.rage=0
 for i=1,3 do local e=assert(G.Spawn(burst,1,520+40*i,580));e.hp,e.maxHp,e.speed,e.attackCooldown=1,1,0,999 end
 G.BurstImpact(burst)
 near(burst.rage,8.1,"ultimate direct kills grant 2.7 each through the real burst path")
 print("[许宁削弱回归] "..n.." checks passed")
 return true
end
return T
