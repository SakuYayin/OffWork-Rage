local UI=require("urhox-libs/UI")
local Skin=require("UISkin")
local Scale=require("InterfaceScale")
local Menu={}
function Menu.Build(settingsOpen,onStart,onSettings,onBack,audioControls,onEndless,onLeaderboard)
 local p=Scale.Get();local S=p.px
 if settingsOpen then return Skin.Card{id="mainMenu",className="game-card settings-paper",width=math.min(p.w-28,S(470)),padding=S(32),gap=S(20),children={
  Skin.Text("工位声音管理",13,"teal"),Skin.Text("耳朵也要下班",28,"ink"),Skin.Text("音乐和音效，各管各的。",14,"muted"),audioControls(false),
  Skin.Button{id="menuSettingsBack",text="收好设置，回桌面",width="100%",tone="coral",onClick=onBack}}}end
 local function Note(id,title,detail,icon,tone,fn)
  return Skin.Button{id=id,className="game-button memo-button memo-"..tone,tone=tone,width="48%",height=p.portrait and 108 or S(p.landscape and 98 or 143),
   padding=S(22),gap=S(8),flexDirection="row",alignItems="center",onClick=fn,children={
    Skin.Icon("item",icon,S(p.landscape and 38 or 48),S(p.landscape and 38 or 52)),
    UI.Panel{flexGrow=1,flexBasis=0,minWidth=0,gap=5,pointerEvents="none",children={
     Skin.Text(title,p.portrait and 19 or 25,"ink",{className="memo-title"}),Skin.Text(detail,12,"ink",{className="memo-detail"})}}}}
 end
 return UI.Panel{id="mainMenu",className="main-menu desk-menu",width="100%",height="100%",backgroundImage="image/ui/desk.png",backgroundFit="cover",children={
  UI.Panel{className="desk-photo-caption",children={Skin.Text("今日目标",14,"ink"),Skin.Text("不加班，准点走！",24,"ink")}},
  UI.Panel{id="menuCopy",className="desk-menu-copy",gap=S(18),children={
   Skin.Text("已完成今天的工作 · 剩下的明天再说",12,"ink",{className="desk-eyebrow"}),
   UI.Panel{className="desk-title",children={Skin.Text("下班！",58,"yellow",{id="menuTitle",className="menu-title gold-title"}),
    Skin.Text("别挡我！",58,"purple",{className="menu-title violet-title"})}},
   UI.Panel{className="memo-grid",width="100%",flexDirection="row",flexWrap="wrap",gap=S(12),children={
    Note("menuStart","打卡下班","闯过办公室  ↗","badge","yellow",onStart),
    Note("menuEndless","加班无尽","看看能撑多久  ∞","coffee","coral",onEndless),
    Note("menuLeaderboard","排行榜","翻翻下班成绩单","coin","mint",onLeaderboard),
    Note("menuSettings","声音设置","让耳朵歇一会儿","headphones","lilac",onSettings)}},
   Skin.Text(p.portrait and "轻推走 · 拖远跑 · 自动攻击"or"WASD 移动 · 自动攻击 · 空格释放大招",12,"ink",{className="desk-controls"})}},
  Skin.Text("17:59  /  今天的时间，留给自己。",12,"ink",{className="desk-footer"})}}
end
return Menu
