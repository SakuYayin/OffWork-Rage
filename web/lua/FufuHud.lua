local UI=require("urhox-libs/UI")
local Skin=require("UISkin")
local FufuHud={}
-- petTop：面板顶边由 HudUI 传入（boss 血条移到顶部后，召唤面板必须让出公告条位置）；
-- 旧调用只传 p 时退回历史默认值，保持向后兼容。
function FufuHud.Build(p,petTop)
 local S=p.px;local r={segments={},slots={}}
 local segments={}
 for i=1,3 do
  local bar=UI.ProgressBar{id="fufuCharge"..i,width="100%",height=7,maxValue=1,value=1,fillColor={255,197,107,255},backgroundColor={74,58,74,160},flexGrow=1,flexBasis=0,minWidth=0}
  r.segments[i]=bar;segments[#segments+1]=bar
 end
 r.chargeText=Skin.Text("糕点 3/3",10,"ink",{id="fufuChargeText",textAlign="center",whiteSpace="nowrap"})
 r.chargeBar=UI.Panel{id="fufuChargeMeter",width="100%",gap=4,pointerEvents="none",children={r.chargeText,UI.Panel{width="100%",flexDirection="row",gap=5,children=segments}}}
 local slots={}
 for i=1,3 do
  local slot={}
  slot.icon=UI.Panel{width=20,height=20,alignItems="center",justifyContent="center",pointerEvents="none"}
  slot.name=Skin.Text("待召唤",9,"ink",{id="fufuPetName"..i,textAlign="center",whiteSpace="nowrap"})
  slot.hp=Skin.Text("—",9,"muted",{id="fufuPetHPText"..i,textAlign="center",whiteSpace="nowrap"})
  slot.bar=UI.ProgressBar{id="fufuPetHP"..i,width="100%",height=4,maxValue=1,value=0,fillColor={104,191,162,255},backgroundColor={108,92,91,90}}
  -- 三种排布：竖屏名称+血量同排压成一行（面板上移到 boss 血条下方后不能压到公告条）；
  -- 横屏面板收窄到 S(190) 后单槽仅 ~45px，图标与名称必须上下叠放，否则 20px 图标 + 9px 三字名放不下。
  local content
  if p.portrait then
   content={slot.icon,UI.Panel{flexGrow=1,flexBasis=0,minWidth=0,gap=2,children={
    UI.Panel{width="100%",flexDirection="row",justifyContent="space-between",alignItems="center",gap=4,children={slot.name,slot.hp}},slot.bar}}}
  elseif p.landscape then
   content={slot.icon,slot.name,slot.hp,slot.bar}
  else
   content={UI.Panel{width="100%",flexDirection="row",gap=3,alignItems="center",justifyContent="center",children={slot.icon,slot.name}},slot.hp,slot.bar}
  end
  slots[#slots+1]=UI.Panel{id="fufuPetSlot"..i,className="fufu-pet-slot",width=p.portrait and"100%"or nil,flexGrow=p.portrait and 0 or 1,flexBasis=p.portrait and"auto"or 0,minWidth=0,padding=3,gap=3,flexDirection=p.portrait and"row"or"column",alignItems="center",pointerEvents="none",children=content}
  r.slots[i]=slot
 end
 r.petHint=Skin.Text("最多3位伙伴 · 按召唤加入",10,"muted",{id="fufuPetHint",textAlign="center",whiteSpace=p.portrait and"normal"or"nowrap"})
 r.petPanel=UI.Panel{id="fufuCompanions",className="fufu-companions",position="absolute",left=p.pad,
  top=petTop or(p.portrait and p.pad+82 or(p.pad+S(p.landscape and 82 or 90)+8)),
  width=p.portrait and math.floor(p.w*.4)or S(p.landscape and 190 or 304),padding=5,gap=3,pointerEvents="none",children={
   UI.Panel{width="100%",flexDirection=p.portrait and"column"or"row",gap=4,children=slots},r.petHint}}
 return r
end
function FufuHud.Update(r,g)
 local state=g.summons or{};local pets=state.pets or{};local charges=state.charges or 0
 local interval=require("FufuCombat").ChargeInterval(g)
 local recovery=math.max(0,state.recovery or 0);local remaining=math.max(0,interval-recovery)
 r.chargeText:SetText(charges>=3 and"糕点 3/3 · 已充满"or("糕点 "..charges.."/3 · "..math.ceil(remaining).."秒+1"))
 for i,bar in ipairs(r.segments)do bar:SetValue(i<=charges and 1 or(i==charges+1 and math.min(1,recovery/interval)or 0))end
 for i,slot in ipairs(r.slots)do
  local pet=pets[i];local key=pet and pet.kind or"cake"
  if slot.iconKey~=key then slot.iconKey=key;slot.icon:ClearChildren();slot.icon:AddChild(Skin.Icon("item",key,20,20))end
  slot.name:SetText(pet and((i==1 and"①"or(i==2 and"②"or"③"))..pet.name)or"待召唤")
  slot.hp:SetText(pet and(math.ceil(math.max(0,pet.hp)).."/"..math.ceil(pet.maxHp))or"—")
  slot.bar:SetValue(pet and math.max(0,math.min(1,pet.hp/math.max(1,pet.maxHp)))or 0)
 end
 r.petHint:SetText(#pets>=3 and"已满3位 · 再召唤替换①最早伙伴"or("伙伴 "..#pets.."/3 · 按召唤加入"))
 return charges,(state.cooldown or 0)>0
end
return FufuHud
