-- Bounded combat pressure: stronger waves, never unbounded density or movement.
local D={}
function D.Wave(g)
 if g.endless and g.endless.active then return math.max(1,g.endless.wave or 1)end
 return math.max(1,((g.floor or 1)-1)*5+math.floor((g.roomsCleared or 0)/2)+(g.wave or 0)+1)
end
function D.Armor(w)return math.min(18,math.floor(math.max(0,w-1)*.45))end
function D.ShieldRatio(w)return math.min(.30,math.max(0,w-2)*.012)end
function D.EliteChance(w)return math.min(.32,math.max(0,w-2)*.014)end
function D.AliveCap(w)return math.min(45,16+math.floor(w*1.4))end
function D.BatchGap(w)return math.max(.65,1.35-math.max(0,w-1)*.025)end
function D.HealMul(w)return math.max(.45,1-math.max(0,w-1)*.018)end
function D.XpMul(w)return math.max(.60,1-math.max(0,w-1)*.012)end
function D.AttackRate(w)return math.min(1.45,1+math.max(0,w-1)*.015)end
function D.SpawnCount(g)return math.min(28,4+g.floor+math.floor(D.Wave(g)*.8)+(g.room.kind=="elite"and 3 or 0))end
D.affixes={"guard","reflect","shield","summon","haste","volatile"}
function D.Apply(g,e,boss)
 local w=D.Wave(g);e.pressureWave=w;e.armor=D.Armor(w);e.attackRate=D.AttackRate(w)
 e.shieldMax=math.floor(e.maxHp*D.ShieldRatio(w));e.shield=e.shieldMax
 e.xp=(e.xp or 0)>0 and math.max(1,math.floor(e.xp*D.XpMul(w)+.5))or 0
 if not boss and math.random()<D.EliteChance(w)then
  e.elite=true;e.affix=D.affixes[math.random(1,#D.affixes)]
  e.maxHp=math.floor(e.maxHp*1.65);e.hp=e.maxHp;e.damage=math.floor(e.damage*1.15+.5)
  if e.affix=="guard"then e.damageReduction=.28
  elseif e.affix=="reflect"then e.reflectCd=0
  elseif e.affix=="shield"then e.shieldMax=math.floor(e.maxHp*.40);e.shield=e.shieldMax
  elseif e.affix=="summon"then e.summonTimer=4.5;e.summonsLeft=3
  elseif e.affix=="haste"then e.speed=math.min(120,e.speed*1.3)
  elseif e.affix=="volatile"then e.blastTimer=nil end
 end
 return e
end
-- Damage mitigation never removes a low-damage build's ability to hurt armor.
function D.Mitigate(e,amount)
 if amount<=0 then return 0 end
 return math.max(1,math.floor(amount/(1+(e.armor or 0)*.06)*(1-math.min(.6,e.damageReduction or 0))+.5))
end
return D
