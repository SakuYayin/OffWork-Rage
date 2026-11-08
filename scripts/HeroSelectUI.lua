local UI=require("urhox-libs/UI")
local Skin=require("UISkin")
local Heroes=require("Heroes")
local Scale=require("InterfaceScale")
local Loadout=require("Loadout")
local Select={}
local IDs={male="Male",female="Female",intern="Intern",programmer="Programmer",fufu="Fufu"}
local Departments={male="技术研发部",female="产品运营部",intern="综合事务部 · 实习",programmer="信息技术部",fufu="伙伴支援部"}
function Select.Portrait(id,w,h,widgetId)return Skin.Hero(id,w,h,widgetId)end
function Select.Build(selected,onSelect,onConfirm,onBack)
 local p=Scale.Get();local S=p.px;local cards={}
 local panelH=math.min(p.h-20,S(770));local pad=p.portrait and 10 or S(18)
 local gridRoom=panelH-2*pad-22-S(42)-S(18)-math.max(44,S(52))-40
 local badgeH=math.max(p.portrait and 210 or S(210),math.min(p.portrait and 235 or S(265),math.floor((gridRoom-12)/2)))
 for _,hero in ipairs(Heroes.list)do
  local id=hero.id;local chosen=id==selected
  cards[#cards+1]=UI.Panel{id="heroSelect"..(IDs[id]or id),className="employee-badge expanded-badge "..id..(chosen and" selected"or""),
   width="48%",height=badgeH,flexShrink=0,pointerEvents="box-only",onClick=function()onSelect(id)end,
   backgroundImage="image/ui/badge.png",backgroundFit="contain",children={
    UI.Panel{className="badge-face",children={
     Skin.Text("瞎良心科技公司",12,"ink",{className="badge-company",textAlign="center"}),
     UI.Panel{className="badge-profile",flexDirection="row",gap=10,alignItems="center",children={
      UI.Panel{className="badge-photo",width="36%",alignItems="center",children={Skin.Avatar(id,p.portrait and 55 or S(76),p.portrait and 59 or S(82),id.."LargePortrait")}},
      UI.Panel{className="badge-stats",gap=3,children={
       Skin.Text(hero.name,p.portrait and 20 or 25,"ink",{fontWeight="bold"}),
       Skin.Text(Departments[id]or"员工",11,id=="female"and"purple"or"teal"),
       Skin.Text("精力 "..hero.maxHp.." · 移速 "..hero.speed,12,"ink"),
       Skin.Text("武器 "..(Loadout.names[hero.primaryWeapon]or""),12,"ink",{className="badge-weapon"}),
       Skin.Text(hero.title,11,"muted",{className="badge-description"})}}}},
     Skin.Text(chosen and"✓ 本次出勤"or"点击工牌选择",11,chosen and"teal"or"muted",{id=id.."SelectionState",className="badge-stamp",textAlign="center"})}}}}
 end
 return UI.Panel{id="heroSelectScreen",className="cork-selection four-hero-selection",width=math.min(p.w-20,S(1050)),height=panelH,padding=pad,gap=10,children={
  Skin.Text("选好搭档，打卡下班！",p.portrait and 23 or 30,"cream",{className="selection-heading",textAlign="center"}),
  Skin.Text("共"..#Heroes.list.."位同事 · 上下滑动查看全部",11,"cream",{className="badge-scroll-hint",textAlign="center"}),
  UI.ScrollView{id="heroBadgeScroll",scrollKey="hero-badges-"..#Heroes.list,width="100%",flexGrow=1,flexBasis=0,minHeight=0,scrollY=true,scrollX=false,children={
   UI.Panel{className="hero-badge-grid",width="100%",flexDirection="row",flexWrap="wrap",gap=12,children=cards}}},
  Skin.Text("本次出勤 / "..Heroes.Get(selected).name,13,"cream",{id="heroSelectedSummary",textAlign="center"}),
  UI.Panel{width="100%",flexDirection="row",gap=12,children={
   Skin.Button{id="heroBack",text="← 返回",tone="coral",width=p.portrait and 80 or S(110),onClick=onBack},
   Skin.Button{id="heroConfirm",text="✓ 确认出勤",tone="yellow",flexGrow=1,flexBasis=0,minWidth=0,onClick=onConfirm}}}
 }}
end
function Select.Preview()return UI.Panel{width=0,height=0}end
return Select
