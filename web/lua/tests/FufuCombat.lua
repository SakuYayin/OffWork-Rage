local G=require("Game")
local F=require("FufuCombat")
local S=require("FufuSummons")
local B=require("Buffs")
local L=require("Loadout")
local A=require("ActionState")
local E=require("Endless")
local Events=require("Events")
local D=require("Difficulty")
local T={}
function T.Run()
 local n=0;local function check(v,m)assert(v,m);n=n+1 end
 local function near(a,b,m)check(math.abs(a-b)<1e-6,m.." "..tostring(a).." vs "..tostring(b))end
 local function fixture()
  local g=G.New("fufu");g.mode="playing";g.waveTimer=999;g.bulbTimer=999;g.xpNeed=1000000;g.player.invuln=999;g.crit=0
  g.player.x,g.player.y=520,580;return g
 end
 local function tick(g,seconds)for i=1,math.floor(seconds/.02+.5)do G.Update(g,.02,0,0)end end
 local function target(g,x,y,kind)
  local e=assert(G.Spawn(g,kind or 4,x or 750,y or 580));e.hp=100000;e.maxHp=e.hp;e.speed=0;e.attackCooldown=999;e.shootTimer=999;e.shield=0;e.armor=0;e.damageReduction=0;return e
 end
 local function summon(g,id)
  g.summons.cooldown=0;return assert(F.PerformSummon(g,function()return id end))
 end
 local function stationary(p,x,y)p.x,p.y=x,y;p.attackTimer=999;p.protection=0;p.invuln=0 end
 local g=fixture()
 check(g.heroId=="fufu"and g.player.maxHp==100 and g.player.speed==164 and g.damage==1 and g.hero.reduction==.10,"fifth hero is actually initialized")
 check(g.summons and g.summons.charges==3 and g.pets==g.summons.pets,"three full charges and shared live pet array")
 check(L.Primary(g)=="cake"and g.secondaryWeapon=="bulb"and #L.List(g)==2,"both fixed weapon slots initialized")
 for _,id in ipairs({"keyboard","stapler","coffee","thermos","paperclip","pie"})do
  check(not L.CanAcquire(g,id)and not G.PickWeapon(g,id),"third weapon and replacement rejected")
  g.mode="upgrade";g.choices={{id=id,title=id}};G.Choose(g,1);check(g.mode=="upgrade","stale upgrade cannot replace fixed slots")
  g.mode="playing"
 end
 g.mode="shop";g.coins=100;g.shopItems={{id="stapler",price=1}};check(not G.Buy(g,1),"shop respects locked slots");g.mode="playing"
 local victim=target(g,550);tick(g,.5);check(victim.hp==100000,"body and cake have no melee damage")
 check(G.Burst(g),"real Game.Burst accepts charged summon without rage")
 tick(g,.32);check(g.summons.charges==3 and #g.pets==0,"summon windup costs no charge")
 tick(g,.04);check(g.summons.charges==2 and #g.pets==1,"real action impact creates a pet and consumes one charge")
 check(not G.Burst(g),"continuous summon cooldown enforced")
 local cancel=fixture();check(G.Burst(cancel),"cancel fixture starts a real summon");A.Reset(cancel);tick(cancel,.5)
 check(cancel.summons.charges==3 and #cancel.pets==0,"cancel before impact never consumes cake")
 local seq=fixture();local first=summon(seq,1);summon(seq,2);summon(seq,3)
 check(#seq.pets==3 and seq.pets[1]==first,"first three fills retain order")
 seq.summons.charges=1;local newest,replaced=F.PerformSummon(seq,function()return 5 end)
 check(newest==nil,"cooldown checked even with manually restored charge")
 seq.summons.cooldown=0;newest,replaced=F.PerformSummon(seq,function()return 5 end)
 check(replaced==first and seq.pets[1].kind=="water"and seq.pets[3].kind=="dog","fourth summon replaces oldest alive pet FIFO")
 seq.pets[2].hp=0;F.Cleanup(seq);check(#seq.pets==2,"dead pet frees slot immediately")
 seq.summons.charges=1;seq.summons.cooldown=0;summon(seq,4);check(#seq.pets==3 and seq.pets[1].kind=="water","dead slot filled without replacing surviving oldest")
 local clock=fixture();clock.summons.charges=0;F.Update(clock,11.9);check(clock.summons.charges==0,"charge not granted before twelve seconds")
 F.Update(clock,.2);check(clock.summons.charges==1,"first charge at twelve seconds")
 F.Update(clock,12);check(clock.summons.charges==2,"charges refill sequentially not all at once")
 F.Update(clock,12);check(clock.summons.charges==3 and clock.summons.recovery==0,"charge cap three")
 local pause=fixture();local pp=summon(pause,3);pause.summons.recovery=3;pause.mode="paused"
 tick(pause,1);near(pause.summons.recovery,3,"pause freezes recovery");near(pp.protection,3,"pause freezes pet protection")
 pause.mode="upgrade";tick(pause,1);near(pause.summons.recovery,3,"upgrade screen freezes recharge")
 local follow=fixture();local fp=summon(follow,4);fp.hp=37;G.EnterRoom(follow,2)
 check(#follow.pets==1 and follow.pets[1].id==fp.id and fp.hp==37,"cross-room follows with actual health and identity retained")
 check(G.Distance(fp.x,fp.y,follow.player.x,follow.player.y)<100,"cross-room pet position is near new owner spawn")
 local bulb=fixture();local a={faceX=1,faceY=0,serial=1}
 for _,row in ipairs({{.1,"normal",15},{.8,"electric",22.5},{.95,"flash",10}})do
  local s=F.FireBulb(bulb,a,function()return row[1]end);check(s.kind=="bulb"and s.bulbType==row[2]and s.damage==row[3],"bulb types use distinct real projectile damage")
 end
 local live=fixture();local le=target(live,750);live.bulbTimer=0;tick(live,1.5)
 check(le.hp<100000 and not live.actionTracks.keyboard,"automatic slow bulb damages an actual enemy, no melee track")
 local wet=fixture();local one=target(wet,580);local two=target(wet,650);local three=target(wet,720);local dry=target(wet,780)
 one.wetTimer,two.wetTimer,three.wetTimer=4,4,4
 F.BulbHit(wet,one,{bulbType="electric",damage=18,vx=340,vy=0})
 check(one.hp==99982 and two.hp==99985 and three.hp==99985 and dry.hp==100000,"electric chains only to two other wet enemies without recursive or dry hits")
 F.BulbHit(wet,dry,{bulbType="flash",damage=8,vx=340,vy=0});near(dry.stunTimer,.7,"flash stuns ordinary enemy point seven seconds")
 local boss=target(wet,850,580,5);F.BulbHit(wet,boss,{bulbType="flash",damage=8,vx=340,vy=0})
 near(boss.stunTimer,.2,"boss flash only point two seconds");boss.stunTimer=0
 F.BulbHit(wet,boss,{bulbType="flash",damage=8,vx=340,vy=0});check(boss.stunTimer==0,"same boss cannot be restunned inside four seconds")
 F.UpdateEnemies(wet,4);F.BulbHit(wet,boss,{bulbType="flash",damage=8,vx=340,vy=0});near(boss.stunTimer,.2,"boss flash recovers after four seconds")
 for id,kind in ipairs(S.kinds)do
  local pets=fixture();local p=summon(pets,id);stationary(p,600,580);p.attackTimer=0;local e=target(pets,650)
  if kind=="dan"then tick(pets,1);check(e.hp==100000,"dan never attacks")
  elseif kind=="cat"or kind=="dog"then tick(pets,.1);check(100000-e.hp==(kind=="cat"and 18 or 36),"ordinary cat and dog use eighteen versus thirty six damage")
  elseif kind=="maple"then tick(pets,.6);check(e.bleedStacks==3 and e.hp<99970,"maple executes three real claws plus stacking bleed")
  else tick(pets,1.2);check(e.wetTimer>0 and e.hp==99964,"water emits exactly six real piercing ticks")end
 end
 local piercing=fixture();local wp=summon(piercing,2);stationary(wp,540,580);wp.attackTimer=0
 local w1=target(piercing,650);local w2=target(piercing,750);tick(piercing,.1)
 check(w1.hp==99994 and w2.hp==99994 and w1.wetTimer>0 and w2.wetTimer>0,"water pierces multiple enemies in one line")
 local walls=fixture();local wallPet=summon(walls,2);stationary(wallPet,310,280);wallPet.attackTimer=0;wallPet.waterX,wallPet.waterY=1,0;wallPet.waterLeft=1;wallPet.waterTick=0
 local behind=target(walls,380,280);F.Update(walls,.02)
 check(behind.hp==100000 and not behind.wetTimer,"water cannot damage or wet an enemy across a wall")
 local guard=fixture();guard.player.invuln=0;local gp=summon(guard,3);stationary(gp,550,580)
 G.TakeDamage(guard,100);near(gp.hp,460,"dan intercept uses its twenty percent reduction")
 near(guard.player.hp,100,"intercept keeps owner unharmed for fully absorbed hit")
 guard.player.invuln=0;G.TakeDamage(guard,10);near(guard.player.hp,91,"shared cooldown prevents repeat interception")
 local overflow=fixture();overflow.player.invuln=0;local small=summon(overflow,3);stationary(small,550,580);small.hp=8
 G.TakeDamage(overflow,50);check(small.hp==0 and #overflow.pets==0 and overflow.player.hp==64,"guardian dies and raw overflow returns forty damage to owner")
 local trio=fixture();for i=1,3 do trio.summons.dryStreak=0;local p=summon(trio,3);stationary(p,550+i*4,580)end
 trio.player.invuln=0;G.TakeDamage(trio,20);local consumed=0;for _,p in ipairs(trio.pets)do if p.hp<540 then consumed=consumed+1 end end
 check(consumed==1,"three guardians share a single intercept per cooldown")
 trio.player.invuln=0;G.TakeDamage(trio,20);check(trio.player.hp==82,"three guardians do not produce unlimited immunity")
 local damage=fixture();local hitPet=summon(damage,4);stationary(hitPet,600,580)
 F.DamagePet(damage,hitPet,10);near(hitPet.hp,152,"pet loses real health to incoming damage")
 hitPet.invuln=0;hitPet.protection=3;F.DamagePet(damage,hitPet,10);near(hitPet.hp,145,"first three seconds grant thirty percent reduction")
 local projectile=fixture();local bp=summon(projectile,4);stationary(bp,600,580)
 projectile.hostileShots={{x=650,y=580,vx=-500,vy=0,life=1,damage=20}}
 tick(projectile,.2);check(bp.hp==142 and #projectile.hostileShots==0,"actual hostile projectile collides with pet and consumes bullet")
 local melee=fixture();local mp=summon(melee,4);stationary(mp,610,580);local me=target(melee,645,580,1);me.attackCooldown=0
 tick(melee,.4);check(mp.hp<162,"real enemy melee windup can target and damage pet")
 local kill=fixture();local kp=summon(kill,4);stationary(kp,600,580);kp.attackTimer=0;local ke=target(kill,640);ke.hp=10;local before=kill.kills
 tick(kill,.1);check(kill.kills==before+1 and #kill.gems>0,"pet kill credits owner kills and real loot")
 local perks={"fufuSnack","fufuCheckup","fufuClaws","fufuMaple","fufuWater","fufuProtection","fufuTeething","fufuWaterproof","fufuLink","fufuBlink","fufuBlanket","fufuDuty"}
 for _,id in ipairs(perks)do local p=fixture();check(B.Apply(p,id)==1 and B.Level(p,id)==1,"all twelve exclusives are obtainable");local other=G.New("male");check(B.Apply(other,id)==0,"fufu exclusive rejected for other hero")end
 local perk=fixture();local cp=summon(perk,4);cp.hp=45;B.Apply(perk,"fufuCheckup");near(cp.maxHp,194.4,"checkup expands real hp cap");near(cp.hp,54,"checkup preserves hp ratio")
 B.Apply(perk,"fufuSnack");near(F.ChargeInterval(perk),12/1.12,"snack speeds actual charge interval")
 B.Apply(perk,"fufuClaws");B.Apply(perk,"fufuTeething");near(F.PetDamage(perk,cp),1.15*1.15,"damage exclusives stack on output pets")
 local dp=summon(perk,3);B.Apply(perk,"fufuProtection");near(dp.maxHp,540*1.2*1.15,"guardian life exclusives apply live")
 local guards=dp.hp;dp.protection=0;dp.invuln=0;F.DamagePet(perk,dp,100);near(guards-dp.hp,75,"guardian perk improves actual mitigation")
 for i=1,3 do B.Apply(perk,"fufuWaterproof")end;for i=1,2 do B.Apply(perk,"fufuBlink")end
 local normal,electric,flash=F.BulbProbabilities(perk);near(normal,.45,"normal absorbs probability changes");near(electric,.35,"electric cap thirty five percent");near(flash,.20,"flash cap twenty percent")
 B.Apply(perk,"fufuBlanket");cp.hp=20;F.Cleared(perk);near(cp.hp,39.44,"blanket heals actual ten percent pet max hp at early wave")
 B.Apply(perk,"fufuDuty");perk.summons.charges=0;perk.summons.recovery=0;F.Update(perk,F.ChargeInterval(perk))
 near(perk.shield,5,"completed charge gives actual owner shield");B.Apply(perk,"fufuDuty");F.Update(perk,F.ChargeInterval(perk));near(perk.shield,15,"duty shield cap fifteen")
 local event=fixture();event.summons.charges=0;Events.Get("bl_2").choices[1].apply(event);check(event.summons.charges==1,"rage event gives one cake to fufu")
 event.summons.charges=3;Events.Get("bl_2").choices[1].apply(event);check(event.summons.charges==3,"event cake reward respects cap")
 local endless=fixture();E.Start(endless,{seed=12});local ep=summon(endless,4);ep.hp=20;B.Apply(endless,"fufuBlanket")
 endless.endless.wave=5;endless.endless.phase="fighting";endless.endless.budget=0;endless.enemies={}
 E.Update(endless,.02);near(ep.hp,20+ep.maxHp*.1*D.HealMul(5),"blanket also triggers through actual endless wave-clear transition")
 local healed=ep.hp;E.Update(endless,.02);near(ep.hp,healed,"endless breather never repeats clear healing")
 local counts={maple=0,water=0,dan=0,cat=0,dog=0};math.randomseed(20261107)
 -- 保底会打破 20% 均匀，所以每次抽卡都用一个全新 state，不累积 dryStreak。
 for i=1,20000 do local state=S.New();state.charges=3;state.cooldown=0;local p=S.Summon(state);counts[p.kind]=counts[p.kind]+1 end
 for _,kind in ipairs(S.kinds)do check(counts[kind]>3700 and counts[kind]<4300,"twenty thousand draws support independent equal twenty percent "..kind)end
 local maple=fixture();B.Apply(maple,"fufuMaple");local cat=summon(maple,1);stationary(cat,600,580);cat.attackTimer=0;local bleeding=target(maple,650);tick(maple,.1)
 near(bleeding.bleedDps,5,"maple exclusive increases real bleed from three to five")
 local upgradedWater=fixture();B.Apply(upgradedWater,"fufuWater");local waterPet=summon(upgradedWater,2);stationary(waterPet,600,580);waterPet.attackTimer=0;local drenched=target(upgradedWater,650);tick(upgradedWater,1.2)
 check(100000-drenched.hp==39 and drenched.wetTimer>4,"water exclusive increases real six tick damage with fractional credit and wet duration")
 local links=fixture();B.Apply(links,"fufuLink");B.Apply(links,"fufuLink");local targets={}
 for i=1,5 do targets[i]=target(links,530+i*70);targets[i].wetTimer=4 end
 F.BulbHit(links,targets[1],{bulbType="electric",damage=18,vx=340,vy=0})
 for i=2,5 do check(targets[i].hp==99985,"link exclusive reaches all four secondary targets exactly once")end
 local bulbs=fixture();B.Apply(bulbs,"fufuBlink");B.Apply(bulbs,"fufuBlink")
 check(F.FireBulb(bulbs,a,function()return .82 end).bulbType=="flash","flash probability perk changes actual projectile selection")
 local electrical=fixture();for i=1,3 do B.Apply(electrical,"fufuWaterproof")end
 check(F.FireBulb(electrical,a,function()return .6 end).bulbType=="electric","electric perk changes actual projectile selection without summon probability changes")
 local bulbCounts={normal=0,electric=0,flash=0};local prob=fixture()
 for i=1,10000 do prob.shots={};local s=F.FireBulb(prob,a);bulbCounts[s.bulbType]=bulbCounts[s.bulbType]+1 end
 check(bulbCounts.normal>6750 and bulbCounts.normal<7250 and bulbCounts.electric>1800 and bulbCounts.electric<2200 and bulbCounts.flash>850 and bulbCounts.flash<1150,"ten thousand real bulb generations support seventy twenty ten")
 -- 丹旺旺反伤：替 100 伤害，周围每只各掉 30（100 × 30%）
 local reflect=fixture();reflect.player.invuln=0
 local rp=summon(reflect,3);stationary(rp,550,580)
 local r1=target(reflect,620,580);local r2=target(reflect,660,580);local r3=target(reflect,540,300)
 G.TakeDamage(reflect,100)
 check(100000-r1.hp==30 and 100000-r2.hp==30,"reflect hits every enemy in range")
 check(r3.hp==100000,"reflect ignores enemies outside 110")
 -- 反伤率随 fufuProtection 提到 45%，且减伤不会削弱反伤（基数取减伤前的代受量）
 local reflect3=fixture();reflect3.player.invuln=0
 local rp3=summon(reflect3,3);stationary(rp3,550,580)
 for i=1,3 do B.Apply(reflect3,"fufuProtection")end
 local r4=target(reflect3,620,580)
 G.TakeDamage(reflect3,100)
 check(100000-r4.hp==45,"guardian perk raises reflect to 45 percent of absorbed damage")
 -- 单次上限：maxHp × 12%
 local reflectCap=fixture();reflectCap.player.invuln=0
 local dcap=summon(reflectCap,3);stationary(dcap,550,580)
 local r6=target(reflectCap,620,580)
 G.TakeDamage(reflectCap,1000)
 check(100000-r6.hp==64,"reflect is capped at twelve percent of guardian max hp")
 -- 基数是代受量，会被丹旺旺剩余生命夹住（满血替大伤害不爆表）
 local dying=fixture();dying.player.invuln=0
 local dp2=summon(dying,3);stationary(dp2,550,580);dp2.hp=8
 local r5=target(dying,620,580)
 G.TakeDamage(dying,1000)
 check(100000-r5.hp==3,"reflect is clamped by the absorbed amount of a dying guardian")
 -- 30% 伤害继承：1.75 乘区下猫只能打出 22（满继承应为 31）
 local inherit=fixture();inherit.damage=1.75
 local ip=summon(inherit,4);stationary(ip,600,580);ip.attackTimer=0
 local ie=target(inherit,650);tick(inherit,.1)
 check(100000-ie.hp==22,"pets inherit only thirty percent of the damage multiplier")
 -- 30% 攻速继承
 local hasteP=fixture();hasteP.attackSpeed=1.22
 local hp2=summon(hasteP,4);stationary(hp2,600,580);hp2.attackTimer=0
 target(hasteP,650);tick(hasteP,.02)
 near(hp2.attackTimer,.8/1.066,"pets inherit only thirty percent of attack speed")
 -- 攻速不越界：本体 1.0 时伙伴间隔完全不变
 local plain=fixture()
 local pp2=summon(plain,4);stationary(pp2,600,580);pp2.attackTimer=0
 target(plain,650);tick(plain,.02)
 near(pp2.attackTimer,.8,"unhasted owner leaves pet cadence untouched")
 -- 阵亡返还 40% 充能（先召唤再清空，PerformSummon 需要至少一格）
 local refund=fixture()
 local rp2=summon(refund,4);refund.summons.charges=0;refund.summons.recovery=0
 rp2.hp=0;F.Cleanup(refund)
 near(refund.summons.recovery,F.ChargeInterval(refund)*.4,"dead pet refunds forty percent charge")
 -- 满格阵亡不产生存款
 local full=fixture()
 local fp2=summon(full,2);full.summons.charges=3;full.summons.recovery=0
 fp2.hp=0;F.Cleanup(full)
 check(full.summons.recovery==0,"full charges never bank a refund")
 -- 召唤保底：连续两只哑炮（水位/丹旺旺）后必出输出型
 local pity=S.New();local sequence={2,3,2};local draws=0
 local function roll()draws=draws+1;return sequence[draws]end
 for i=1,3 do pity.charges=3;pity.cooldown=0;S.Summon(pity,roll)end
 local lastPet=pity.pets[#pity.pets]
 check(lastPet.kind~="water"and lastPet.kind~="dan","third summon after two dull pets is an attacker")
 -- 等级成长：11 级 ×1.08，60 级封顶 ×1.40
 local grown=fixture();grown.level=11
 local gp2=summon(grown,4)
 near(gp2.maxHp,162*1.08,"pet life grows with player level")
 grown.level=60;local gp3=summon(grown,4)
 near(gp3.maxHp,162*1.40,"pet growth caps at forty percent")
 print("[符符完整玩法回归] "..n.." checks passed; summonSamples=20000 bulbSamples=10000")
 return true
end
return T
