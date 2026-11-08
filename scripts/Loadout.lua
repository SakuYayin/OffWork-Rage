-- Primary weapon is fixed per hero; one additional weapon can be acquired.
local Loadout={}
Loadout.names={keyboard="机械键盘",stapler="订书器",coffee="咖啡杯",thermos="保温杯",paperclip="回形针弹弓",pie="画饼",folder="文件夹",binary="笔记本电脑",cake="宠物糕点",bulb="灯泡"}
function Loadout.Primary(g)return g.primaryWeapon or "keyboard"end
function Loadout.Has(g,id)return id==Loadout.Primary(g)or id==g.secondaryWeapon end
function Loadout.CanAcquire(g,id)
 if g.heroId=="fufu"then return id=="cake"or id=="bulb"end
 if id=="cake"or id=="bulb"then return false end
 return Loadout.names[id]~=nil and(Loadout.Has(g,id)or not g.secondaryWeapon)
end
function Loadout.Acquire(g,id)
 if not Loadout.CanAcquire(g,id)then return false end
 if not Loadout.Has(g,id)then g.secondaryWeapon=id end
 return true
end
function Loadout.List(g)
 local out={Loadout.Primary(g)};if g.secondaryWeapon then out[#out+1]=g.secondaryWeapon end;return out
end
return Loadout
