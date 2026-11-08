local UI=require("urhox-libs/UI")
local Skin=require("UISkin")
local Scale=require("InterfaceScale")
local Results={}
function Results.Build(o)
 local p=Scale.Get();local S=p.px;local sheetH=math.min(p.h-24,S(660))
 local stats={}
 for _,row in ipairs(o.stats or{})do stats[#stats+1]=UI.Panel{className="result-stat",width="100%",flexDirection="row",gap=10,justifyContent="space-between",children={
  Skin.Text(row[1],14,"muted",{flexGrow=1,flexBasis=0,minWidth=0}),Skin.Text(tostring(row[2]),16,"ink",{fontWeight="bold",textAlign="right"})}}end
 local form={Skin.Text("留下昵称，记录这次成绩",17,"ink",{fontWeight="bold"})}
 if not o.submitted then
  form[#form+1]=UI.TextInput{id="scoreNameInput",className="score-name-input",width="100%",height=48,minHeight=48,value=o.name or"",
   placeholder="输入你的昵称",ariaLabel="排行榜昵称，支持中文英文数字",onChange=o.onNameChange}
  form[#form+1]=Skin.Text("支持中文、英文、数字和常用符号。",12,"muted")
  form[#form+1]=Skin.Button{id="scoreSubmit",text=o.busy and"正在提交…"or"确认昵称并提交",tone="mint",width="100%",height=48,disabled=o.busy,onClick=o.onSubmit}
 end
 if o.message and o.message~=""then form[#form+1]=Skin.Text(o.message,14,o.error and"pink"or"teal",{id="scoreSubmitMessage",className="result-message",whiteSpace="normal"})end
 if o.submitted then form[#form+1]=Skin.Text(o.name or"",19,"ink",{className="result-player-name",textAlign="center"})end
 return Skin.Card{id="resultSheet",className="game-card result-sheet",width=math.min(p.w-24,S(850)),height=sheetH,padding=0,gap=0,children={
  UI.Panel{className="result-header",width="100%",paddingHorizontal=S(28),paddingTop=math.floor(sheetH*.145),paddingBottom=S(12),gap=5,children={
   Skin.Text(o.title or"本次成绩",p.portrait and 26 or 32,"ink",{id="resultTitle",textAlign="center",fontWeight="bold"}),
   Skin.Text(o.subtitle or"",13,"muted",{textAlign="center"})}},
  UI.ScrollView{id="resultBodyScroll",width="100%",flexGrow=1,flexBasis=0,minHeight=0,scrollY=true,scrollX=false,children={
   UI.Panel{className="result-content",width="100%",padding=S(24),gap=S(20),flexDirection=p.portrait and"column"or"row",children={
    UI.Panel{className="result-statistics",width=p.portrait and"100%"or"47%",gap=12,children={
     UI.Panel{className="result-score",width="100%",padding=S(14),alignItems="center",gap=3,children={Skin.Text("总分",12,"muted"),Skin.Text(tostring(o.score or 0),34,"ink",{id="resultScore",fontFamily="mono"})}},
     UI.Panel{width="100%",gap=10,children=stats}}},
    UI.Panel{className="result-name-form",width=p.portrait and"100%"or"49%",gap=12,children=form}}
   }}},
  UI.Panel{className="result-actions",width="100%",paddingHorizontal=S(24),paddingVertical=S(18),gap=10,flexDirection="row",children={
   Skin.Button{id="endlessLeaderboard",text="查看排行榜",tone="lilac",flexGrow=1,flexBasis=0,minWidth=0,height=48,onClick=o.onLeaderboard},
   Skin.Button{id=o.againId or"heroReplay",text="再战一局",tone="yellow",flexGrow=1,flexBasis=0,minWidth=0,height=48,onClick=o.onAgain},
   Skin.Button{id="endlessMenu",text="回到主菜单",tone="coral",flexGrow=1,flexBasis=0,minWidth=0,height=48,onClick=o.onMenu}}}
 }}
end
return Results
