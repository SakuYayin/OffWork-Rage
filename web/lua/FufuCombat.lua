-- Live host integration for Fufu. Rendering reads state; it never creates damage.
local Summons=require("FufuSummons")
local Navigation=require("Navigation")
local Buffs=require("Buffs")
local Difficulty=require("Difficulty")
local Actions=require("ActionState")
local F={}
local NAMES={maple="枫叶小猫",water="水龙龙",dan="丹旺旺",cat="普通猫猫",dog="普通狗狗"}
local function G()return package.loaded["Game"]end
local function level(g,id)return Buffs.Level(g,id)end
local function dist(a,b)local x,y=a.x-b.x,a.y-b.y;return math.sqrt(x*x+y*y)end
local function direction(a,b)local d=math.max(.001,dist(a,b));return (b.x-a.x)/d,(b.y-a.y)/d,d end
local function fx(g,kind,x,y,life,size,angle,tx,ty)
 if #g.effects>=100 then table.remove(g.effects,1)end
 g.effects[#g.effects+1]={kind=kind,x=x,y=y,life=life,maxLife=life,size=size or 60,angle=angle or 0,targetX=tx,targetY=ty,text=""}
end
local function sound(g,name)
 for _,s in ipairs(g.audioQueue)do if s==name then return end end
 if #g.audioQueue<8 then g.audioQueue[#g.audioQueue+1]=name end
end
function F.Init(g,reset)
 if g.heroId~="fufu"then return end
 if reset or not g.summons then g.summons=Summons.New();g.summons.interceptCooldown=0;g.bulbTimer=.3 end
 g.pets=g.summons.pets;g.primaryWeapon="cake";g.secondaryWeapon="bulb";g.rage=0
end
function F.ChargeInterval(g)return math.max(8,12/(1+.12*level(g,"fufuSnack")))end
-- 伙伴成长：随玩家等级每级 +0.8%，上限 +40%。解决后期伙伴跟不上敌人成长。
-- 刻意不用 g.roomsCleared：无尽模式每波会把 roomsCleared 归零（Endless.lua:268），
-- 按房间数算的话无尽里成长永远是 0；g.level 两种模式都单调递增。
function F.Growth(g)return math.min(.40,.008*math.max(0,(g.level or 1)-1))end
function F.MaxHp(g,kind)
 local hp=Summons.stats[kind].hp*(1+.20*level(g,"fufuCheckup"))*(1+F.Growth(g))
 if kind=="dan"then hp=hp*(1+.15*level(g,"fufuProtection"))end
 return hp
end
function F.PetDamage(g,pet)
 local mul=(1+.15*level(g,"fufuClaws"))*(1+F.Growth(g))
 if pet.kind=="cat"or pet.kind=="dog"then mul=mul*(1+.15*level(g,"fufuTeething"))end
 return mul
end
-- 伙伴只吃本体伤害乘区的 30%：g.damage 可叠到 1.75，吃满会让伙伴后期滚雪球。
function F.PetInherit(g)return 1+math.max(0,(g.damage or 1)-1)*.30 end
-- 伙伴只吃本体攻速增益的 30%：手速类卡原来对伙伴完全无效，现在补上但打折。
function F.PetHaste(g)
 local rate=(g.attackSpeed or 1)*Buffs.AttackSpeedMul(g)
 return 1+math.max(0,rate-1)*.30
end
function F.OnBuff(g,id)
 if g.heroId~="fufu"then return end
 if id=="fufuCheckup"or id=="fufuProtection"then
  for _,p in ipairs(g.pets or {})do local ratio=p.hp/p.maxHp;p.maxHp=F.MaxHp(g,p.kind);p.hp=p.maxHp*ratio end
 elseif id=="fufuDuty"then g.shieldMax=math.max(g.shieldMax or 0,15)end
end
function F.Cleanup(g)
 if not g.summons then return end
 for i=#g.pets,1,-1 do local p=g.pets[i];if p.hp<=0 then
  fx(g,"fufuDepart",p.x,p.y,.5,60);table.remove(g.pets,i);g.uiRevision=(g.uiRevision or 0)+1
  -- 阵亡返还 40% 充能：伙伴平均只活 4.7 秒，不给补偿就永远补不满。
  -- 只在未满格时返还（满格时 Summons.Update 本来就会清零）；上限 interval*0.999，
  -- 确保不会因为返还而直接跳出一格——真正发格子仍然只在 Summons.Update 里做。
  local state=g.summons
  if state.charges<3 then
   local interval=F.ChargeInterval(g)
   state.recovery=math.min(interval*.999,(state.recovery or 0)+interval*.4)
  end
 end end
end
function F.OnRoom(g)
 if g.heroId~="fufu"then return end
 F.Init(g);F.Cleanup(g)
 for i,p in ipairs(g.pets)do
  local x,y=Navigation.Project(g.navigation,g.player.x+(i-2)*28,g.player.y-30,p.radius or 12,g.player.x,g.player.y)
  p.x,p.y=x or g.player.x,y or g.player.y;p.target=nil;p.moving=false;p.navDirect=nil
 end
end
function F.CanSummon(g)
 return g.heroId=="fufu"and g.mode=="playing"and g.summons and g.summons.charges>0
  and g.summons.cooldown<=0 and not Actions.Active(g,"summon")
end
function F.BeginSummon(g)
 if not F.CanSummon(g)then return false end
 return Actions.Start(g,"summon",g.player.faceX or 1,g.player.faceY or 0)~=nil
end
function F.PerformSummon(g,rng)
 if g.heroId~="fufu"or g.mode~="playing"then return nil end
 F.Init(g);F.Cleanup(g)
 -- Find a legal point before spending a charge. Cancellation before impact costs nothing.
 local x,y=Navigation.Project(g.navigation,g.player.x+30,g.player.y-24,12,g.player.x,g.player.y)
 if not x then return nil end
 local p,replaced=Summons.Summon(g.summons,rng)
 if not p then return nil end
 if replaced then fx(g,"fufuDepart",replaced.x,replaced.y,.5,60)end
 p.x,p.y,p.radius,p.name=x,y,12,NAMES[p.kind]
 p.maxHp=F.MaxHp(g,p.kind);p.hp=p.maxHp;p.faceX,p.faceY=1,0
 p.animationTime,p.attackTime,p.attackTimer,p.hit,p.invuln=0,0,.20,0,0
 g.uiRevision=(g.uiRevision or 0)+1
 fx(g,"fufuSummon",x,y,.6,100);sound(g,"choose")
 G().Announce(g,"「"..p.name.."」来帮忙啦！糕点 "..g.summons.charges.."/3",2)
 return p,replaced
end
local function protection(g,p)
 local reduction=p.kind=="dan"and math.min(.35,.20+.05*level(g,"fufuProtection"))or 0
 return (1-reduction)*((p.protection or 0)>0 and .70 or 1)
end
function F.DamagePet(g,p,amount,ignoreInvuln)
 if not p or p.hp<=0 or(not ignoreInvuln and(p.invuln or 0)>0)then return 0 end
 local loss=math.max(0,amount)*protection(g,p)
 local absorbed=math.min(p.hp,loss);p.hp=math.max(0,p.hp-loss);p.hit=.18;p.invuln=.6
 fx(g,"fufuGuard",p.x,p.y-15,.25,45)
 return absorbed
end
-- 反伤率：30% 起，fufuProtection 每级 +5%，上限 45%。
function F.ReflectRatio(g)return math.min(.45,.30+.05*level(g,"fufuProtection"))end
-- 丹旺旺代受后，对周围敌人反弹「本次代受伤害」的固定比例。
-- 基数用 rawAbsorbed（减伤前）：否则每级 fufuProtection 提升减伤反而会降低反伤，两张收益互相对冲。
-- 走 TrueHit：不吃暴击/破甲/处决/吸血，也不会自循环。
function F.Reflect(g,p,absorbed)
 if absorbed<=0 then return end
 local amount=math.min(absorbed*F.ReflectRatio(g),p.maxHp*.12)
 if amount<=0 then return end
 local gd=math.max(.01,g.damage or 1)
 for _,e in ipairs(g.enemies)do
  if e.hp>0 and dist(p,e)<=110+e.radius and G().Visible(g,p.x,p.y,e.x,e.y)then
   G().TrueHit(g,e,amount/gd,0,0,0)
   fx(g,"fufuGuard",p.x,p.y-15,.2,70,0,e.x,e.y)
  end
 end
end
function F.Intercept(g,amount)
 if g.heroId~="fufu"or not g.summons or(g.summons.interceptCooldown or 0)>0 then return amount end
 for _,p in ipairs(g.pets)do
  if p.kind=="dan"and p.hp>0 and dist(p,g.player)<=120 and G().Visible(g,p.x,p.y,g.player.x,g.player.y)then
   local factor=protection(g,p);local rawAbsorbed=math.min(amount,p.hp/math.max(.01,factor))
   p.attackTime=.5
   F.DamagePet(g,p,rawAbsorbed,true);g.summons.interceptCooldown=1
   F.Reflect(g,p,rawAbsorbed)
   fx(g,"fufuGuard",g.player.x,g.player.y-20,.4,90,0,p.x,p.y);F.Cleanup(g)
   return math.max(0,amount-rawAbsorbed)
  end
 end
 return amount
end
function F.EnemyTarget(g,e)
 local best,bestD=g.player,dist(e,g.player)
 if g.heroId=="fufu"then for _,p in ipairs(g.pets or {})do
  if p.hp>0 and dist(e,p)<bestD then best,bestD=p,dist(e,p)end
 end end
 return best
end
function F.EnemyMelee(g,e,damage)
 if g.heroId~="fufu"then return false end
 local target=F.EnemyTarget(g,e)
 if target~=g.player and dist(e,target)<e.radius+36 and G().Visible(g,e.x,e.y,target.x,target.y)then
  F.DamagePet(g,target,damage);F.Cleanup(g);return true
 end
 return false
end
function F.TouchPets(g,e,damage,radius)
 if g.heroId~="fufu"or(e.petTouchCd or 0)>0 then return end
 for _,p in ipairs(g.pets)do if p.hp>0 and dist(e,p)<radius+p.radius and G().Visible(g,e.x,e.y,p.x,p.y)then
  F.DamagePet(g,p,damage);e.petTouchCd=.9
 end end
 F.Cleanup(g)
end
function F.Cleared(g)
 if g.heroId~="fufu"then return end
 -- 先把现有伙伴的上限推到新一档（等级涨了，成长值也跟着涨），按血量比例接住。
 for _,p in ipairs(g.pets)do
  local ratio=p.hp/math.max(1,p.maxHp)
  p.maxHp=F.MaxHp(g,p.kind);p.hp=p.maxHp*ratio
 end
 local mul=.10*level(g,"fufuBlanket")*Difficulty.HealMul(Difficulty.Wave(g))
 for _,p in ipairs(g.pets)do p.hp=math.min(p.maxHp,p.hp+p.maxHp*mul)end
end
function F.BulbProbabilities(g)
 local electric=math.min(.35,.20+.05*level(g,"fufuWaterproof"))
 local flash=math.min(.20,.10+.05*level(g,"fufuBlink"))
 return 1-electric-flash,electric,flash
end
function F.FireBulb(g,action,rng)
 if g.heroId~="fufu"or #g.shots>=128 then return nil end
 local normal,electric=F.BulbProbabilities(g);local roll=(rng or math.random)()
 local kind=roll<normal and"normal"or(roll<normal+electric and"electric"or"flash")
 -- 符符增强：三类伤害上调到 15 / 22.5 / 10（原 12.6 / 18.9 / 8.4）。
 local damage=kind=="normal"and 15 or(kind=="electric"and 22.5 or 10)
 local s={kind="bulb",bulbType=kind,x=g.player.x,y=g.player.y,vx=action.faceX*340,vy=action.faceY*340,
  life=360/340,damage=damage,pierce=0,hit={},actionSerial=action.serial}
 g.shots[#g.shots+1]=s;sound(g,"staple");return s
end
function F.BulbHit(g,e,s)
 local wet=(e.wetTimer or 0)>0
 G().Hit(g,e,s.damage,s.vx/340,s.vy/340,35)
 fx(g,s.bulbType=="normal"and"fufuGlass"or(s.bulbType=="electric"and"fufuElectric"or"fufuFlash"),e.x,e.y-10,.35,70)
 if s.bulbType=="flash"and e.hp>0 then
  if e.kind==5 or e.kind==14 then
   if(e.fufuFlashCd or 0)<=0 then e.stunTimer=math.max(e.stunTimer or 0,.2);e.fufuFlashCd=4 end
  else e.stunTimer=math.max(e.stunTimer or 0,.7)end
 elseif s.bulbType=="electric"and wet then
  local visited={[e]=true};local source=e
  for _=1,math.min(4,2+level(g,"fufuLink"))do
   local best,bestD=nil,160
   for _,other in ipairs(g.enemies)do
    if not visited[other]and other.hp>0 and(other.wetTimer or 0)>0 and dist(source,other)<bestD
     and G().Visible(g,source.x,source.y,other.x,other.y)then best,bestD=other,dist(source,other)end
   end
   if not best then break end
   -- 电链固定伤害与普通灯泡同步：15（原 12.6）。
   visited[best]=true;G().Hit(g,best,15,0,0,0)
   fx(g,"fufuElectric",source.x,source.y-10,.3,60,0,best.x,best.y-10);source=best
  end
 end
end
local function nearest(g,p)
 local best,bestD=nil,math.huge
 for _,e in ipairs(g.enemies)do if e.hp>0 and dist(p,e)<bestD then best,bestD=e,dist(p,e)end end
 return best,bestD
end
local function strike(g,p,e,damage,nx,ny,knock)
 -- Small water/bleed bonuses must not disappear when every hit rounds down.
 local amount=damage*F.PetDamage(g,p)*F.PetInherit(g)+(p.damageCredit or 0)
 local whole=math.floor(amount+1e-9);p.damageCredit=math.max(0,amount-whole)
 -- 回除的必须是 g.damage：Game.Hit 内部还会再乘一次（Game.lua:486），换乘区会把伤害放大 3.3 倍。
 if whole>0 then G().Hit(g,e,whole/math.max(.01,g.damage),nx,ny,knock)end
end
local function hit(g,p,e,damage)
 local nx,ny=direction(p,e);strike(g,p,e,damage,nx,ny,45)
 p.attackTime=.5;p.faceX,p.faceY=nx,ny;fx(g,"fufuClaw",e.x,e.y-18,.25,55,math.atan(ny,nx))
end
local function water(g,p)
 local nx,ny=p.waterX,p.waterY;local ex,ey=p.x+nx*260,p.y+ny*260
 local t=Navigation.Trace(g.navigation,p.x,p.y,ex,ey,6)
 fx(g,"fufuWater",p.x,p.y-10,.23,260,math.atan(ny,nx),p.x+(ex-p.x)*t,p.y+(ey-p.y)*t)
 for _,e in ipairs(g.enemies)do if e.hp>0 then
  local dx,dy=e.x-p.x,e.y-p.y;local along=dx*nx+dy*ny;local across=math.abs(dx*ny-dy*nx)
  if along>=0 and along<260+e.radius and across<18+e.radius and G().Visible(g,p.x,p.y,e.x,e.y,6)then
   strike(g,p,e,6*(1+.10*level(g,"fufuWater")),nx,ny,0)
   e.wetTimer=4+level(g,"fufuWater")
  end
 end end
end
function F.Update(g,dt)
 if g.heroId~="fufu"or g.mode~="playing"then return end
 F.Init(g);F.Cleanup(g)
 local state=g.summons;local before=state.charges
 Summons.Update(state,dt,1+.12*level(g,"fufuSnack"))
 state.interceptCooldown=math.max(0,(state.interceptCooldown or 0)-dt)
 if state.charges>before and level(g,"fufuDuty")>0 then
  g.shieldMax=math.max(15,g.shieldMax or 0);g.shield=math.min(g.shieldMax,(g.shield or 0)+5*level(g,"fufuDuty")*(state.charges-before))
 end
 g.bulbTimer=(g.bulbTimer or 0)-dt
 local enemy,distance=nearest(g,g.player)
 if enemy and distance<=360+enemy.radius and g.bulbTimer<=0 and not Actions.Active(g,"bulb")
  and G().Visible(g,g.player.x,g.player.y,enemy.x,enemy.y)then
  local nx,ny=direction(g.player,enemy)
  -- 符符增强：射击间隔 1.0 秒（原 1.4/1.05 ≈ 1.333）。
  if Actions.Start(g,"bulb",nx,ny)then g.bulbTimer=1.0/math.max(.2,g.attackSpeed*Buffs.AttackSpeedMul(g))end
 end
 for i,p in ipairs(g.pets)do
  p.animationTime=p.animationTime+dt;p.hit=math.max(0,p.hit-dt);p.invuln=math.max(0,p.invuln-dt)
  p.protection=math.max(0,p.protection-dt);p.attackTime=math.max(0,p.attackTime-dt);p.attackTimer=p.attackTimer-dt
  local ox,oy=p.x,p.y
  p.think=(p.think or 0)-dt
  if p.think<=0 or not p.target or p.target.hp<=0 then p.target=nearest(g,p);p.think=.15 end
  local target=p.target
  if p.kind=="dan"or not target or dist(p,g.player)>480 then
   local tx,ty=g.player.x+(i-2)*26,g.player.y-22
   if math.sqrt((p.x-tx)^2+(p.y-ty)^2)>22 then G().Chase(g,p,tx,ty,150,dt)end
  elseif p.kind=="water"then
   if dist(p,target)>230 or not G().Visible(g,p.x,p.y,target.x,target.y)then G().Chase(g,p,target.x,target.y,145,dt)
   elseif p.attackTimer<=0 then
    p.waterX,p.waterY=direction(p,target);p.waterLeft,p.waterTick=6,0;p.attackTimer=2.8/F.PetHaste(g);p.attackTime=1.2;p.faceX,p.faceY=p.waterX,p.waterY
   end
  else
   if dist(p,target)>60+target.radius or not G().Visible(g,p.x,p.y,target.x,target.y)then G().Chase(g,p,target.x,target.y,165,dt)
   elseif p.attackTimer<=0 then
    if p.kind=="maple"then p.clawsLeft,p.clawTick=3,0;p.attackTimer=1.5/F.PetHaste(g);p.attackTime=.6
    else hit(g,p,target,p.kind=="cat"and 18 or 36);p.attackTimer=(p.kind=="cat"and .8 or 1.15)/F.PetHaste(g) end
   end
  end
  if(p.waterLeft or 0)>0 then
   p.waterTick=p.waterTick-dt
   if p.waterTick<=0 then water(g,p);p.waterLeft=p.waterLeft-1;p.waterTick=p.waterTick+.2 end
  end
  if(p.clawsLeft or 0)>0 then
   p.clawTick=p.clawTick-dt
   if p.clawTick<=0 then
    if target and target.hp>0 and dist(p,target)<70+target.radius and G().Visible(g,p.x,p.y,target.x,target.y)then
     hit(g,p,target,10);target.bleedStacks=math.min(3,(target.bleedStacks or 0)+1)
     target.bleedTimer=4;target.bleedDps=(3+2*level(g,"fufuMaple"))*F.PetDamage(g,p);target.bleedTick=target.bleedTick or .5
    end
    p.clawsLeft=p.clawsLeft-1;p.clawTick=p.clawTick+.2
   end
  end
  local dx,dy=p.x-ox,p.y-oy;p.moving=dx*dx+dy*dy>.000001
  if p.moving and p.attackTime<=0 then local d=math.sqrt(dx*dx+dy*dy);p.faceX,p.faceY=dx/d,dy/d end
 end
 for _,e in ipairs(g.enemies)do
  e.petTouchCd=math.max(0,(e.petTouchCd or 0)-dt)
  if e.hp>0 and(e.dashing or(e.ai and e.ai.state=="charge"))then F.TouchPets(g,e,e.damage,e.radius+8)end
  if e.hp>0 and e.kind==11 then
   for _,p in ipairs(g.pets)do if p.hp>0 and dist(e,p)<46 then
    for _,other in ipairs(g.pets)do if dist(e,other)<62 then F.DamagePet(g,other,e.damage)end end
    if dist(e,g.player)<62 then G().TakeDamage(g,e.damage)end
    e.hp=0;break
   end end
  end
 end
 F.Cleanup(g)
end
function F.UpdateEnemies(g,dt)
 if g.heroId~="fufu"then return end
 for _,e in ipairs(g.enemies)do if e.hp>0 then
  e.fufuFlashCd=math.max(0,(e.fufuFlashCd or 0)-dt)
  e.wetTimer=math.max(0,(e.wetTimer or 0)-dt)
  if(e.bleedTimer or 0)>0 then
   e.bleedTimer=math.max(0,e.bleedTimer-dt);e.bleedTick=(e.bleedTick or .5)-dt
   if e.bleedTick<=0 then
    local amount=(e.bleedDps or 3)*(e.bleedStacks or 1)*.5*F.PetInherit(g)+(e.bleedCredit or 0)
    local whole=math.floor(amount+1e-9);e.bleedCredit=math.max(0,amount-whole)
    if whole>0 then G().TrueHit(g,e,whole/math.max(.01,g.damage),0,0,0)end
    e.bleedTick=e.bleedTick+.5
   end
   if e.bleedTimer<=0 then e.bleedStacks=0 end
  end
 end end
end
return F
