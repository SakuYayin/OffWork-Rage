local UI=require("urhox-libs/UI")
local Skin=require("UISkin")
local Scale=require("InterfaceScale")
local Game=require("Game")
local Upgrade={}
local function Ensure(g)
 if g.upgradeSelectionChoices~=g.choices then g.upgradeSelectionChoices=g.choices;g.upgradeSelectedIndex=1 end
 if not g.choices[g.upgradeSelectedIndex or 1]then g.upgradeSelectedIndex=1 end
 return g.choices[g.upgradeSelectedIndex]
end
function Upgrade.SelectIndex(g,index)
 if g.mode~="upgrade"or not g.choices[index]then return false end
 Ensure(g);g.upgradeSelectedIndex=index;g.uiRevision=(g.uiRevision or 0)+1;return true
end
function Upgrade.Confirm(g)
 if g.mode~="upgrade"then return false end
 local choice=Ensure(g);if not choice then return false end
 Game.Choose(g,g.upgradeSelectedIndex);return g.mode~="upgrade"
end
--- 刷新（reroll）按钮：每局开局的「buff 刷新」次数来自 g.rerollsLeft（Buffs 的 reroll 词条每级补一次）。
--- 文案带剩余次数；次数归零时置灰禁用。真正的扣次数/重摇在 Game.RerollChoices 里，这里只负责调用。
--- 防御式调用：Lead 的 Game.RerollChoices 还没落盘时点按钮不会 nil 崩，只是没反应。
---@param g table
---@param p table Scale.Get() 的返回值
---@param S function p.px
---@param choice table? 当前选中项，nil 表示没有可选项
---@return table
local function BuildFooter(g,p,S,choice)
 local rerolls=math.max(0,math.floor((g.rerollsLeft or 0)+0.5))
 local rerollText=rerolls>0 and("刷新 ↻  剩"..rerolls.."次")or"刷新 ↻  已用完"
 local rerollButton=Skin.Button{id="upgradeReroll",text=rerollText,tone="lilac",ariaLabel="刷新本次增益候选",
  width=p.portrait and"100%"or S(170),height=48,minHeight=44,flexShrink=0,
  onClick=function()if Game.RerollChoices then Game.RerollChoices(g)end end,disabled=rerolls<=0}
 local confirmButton=Skin.Button{id="upgradeConfirm",text="确认选择  ✓",tone="mint",width=p.portrait and"100%"or S(245),height=48,flexShrink=0,onClick=function()Upgrade.Confirm(g)end,disabled=choice==nil}
 if p.portrait then
  -- 竖屏：键盘提示行被 expansion.css 隐藏，footer 拆成上下两行，两个按钮都占满宽度。
  return UI.Panel{width="100%",flexDirection="column",alignItems="stretch",gap=8,children={rerollButton,confirmButton}}
 end
 return UI.Panel{width="100%",flexDirection="row",alignItems="center",gap=12,children={
  Skin.Text("数字键选择 · 回车确认",12,"muted",{className="folder-keyboard-help",flexGrow=1,flexBasis=0,minWidth=0}),
  rerollButton,confirmButton}}
end

function Upgrade.Build(g)
 local p=Scale.Get();local S=p.px;local choice=Ensure(g);local rows={}
 for i,c in ipairs(g.choices)do
  local n=i;local expected=c
  rows[#rows+1]=UI.Button{id="upgradeChoose"..i,ariaLabel="查看"..c.title,className="folder-index-row"..(i==g.upgradeSelectedIndex and" selected"or""),
   width="100%",height=p.portrait and 48 or S(64),minHeight=44,padding=8,gap=8,flexDirection="row",alignItems="center",flexShrink=0,pointerEvents="box-only",
   onClick=function()if g.choices[n]==expected then Upgrade.SelectIndex(g,n)end end,children={
    Skin.Text(tostring(i),12,"muted",{width=18,textAlign="center"}),
    Skin.Icon("buff",c.icon or c.id,p.portrait and 32 or S(38),p.portrait and 32 or S(38)),
    UI.Panel{flexGrow=1,flexBasis=0,minWidth=0,gap=3,pointerEvents="none",children={
     Skin.Text(c.title,p.portrait and 15 or 18,"ink",{className="folder-row-title"}),
     Skin.Text(c.desc or "",12,"muted",{className="folder-row-effect",whiteSpace="nowrap",maxLines=1})}}}}
 end
 local detailKids={}
 if choice then
  detailKids={
   Skin.Icon("buff",choice.icon or choice.id,p.portrait and 58 or S(96),p.portrait and 58 or S(96),"upgradeDetailIcon"),
   Skin.Text(choice.title,p.portrait and 23 or 30,"ink",{id="upgradeDetailTitle",textAlign="center",fontWeight="bold"}),
   Skin.Text(choice.desc or "",p.portrait and 14 or 17,"ink",{id="upgradeDetailEffect",textAlign="center",lineHeight=1.55}),
   Skin.Text(choice.tag or "",12,"muted",{textAlign="center"})}
 end
 return UI.Panel{id="upgradeScreen",className="folder-picker",width=math.min(p.w-24,S(1060)),height=math.min(p.h-24,S(590)),padding=p.portrait and 14 or S(22),gap=12,children={
  Skin.Text("选择一项增益",p.portrait and 24 or 30,"ink",{className="folder-picker-heading"}),
  UI.Panel{className="folder-picker-body",width="100%",flexGrow=1,flexBasis=0,minHeight=0,flexDirection=p.portrait and"column"or"row",gap=p.portrait and 10 or S(20),children={
   UI.ScrollView{id="upgradeIndexScroll",scrollKey=tostring(g.choices),width=p.portrait and"100%"or"48%",height=p.portrait and math.min(250,#rows*50)or"100%",flexShrink=0,minHeight=0,scrollY=true,scrollX=false,children={
    UI.Panel{width="100%",gap=5,children=rows}}},
   UI.ScrollView{id="upgradeDetailScroll",className="folder-detail-scroll",width=p.portrait and"100%"or"50%",flexGrow=1,flexBasis=0,minHeight=0,scrollY=true,scrollX=false,children={
    UI.Panel{width="100%",padding=p.portrait and 6 or S(16),gap=p.portrait and 8 or S(15),alignItems="center",children=detailKids}}}
  }},
  BuildFooter(g,p,S,choice)}}
end
return Upgrade
