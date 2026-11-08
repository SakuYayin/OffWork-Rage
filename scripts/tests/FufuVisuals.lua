local V=require("FufuVisuals")
local A=require("FufuArt").sheets
local Icons=require("InterfaceIcons")
local M={}
function M.Run()
 local n=0
 local function check(ok)assert(ok,"Fufu visual contract #"..n);n=n+1 end
 local g={heroId="fufu",time=12,player={moving=true,x=520,y=560},locomotion={faceX=0,faceY=-1,time=0,duration=.72},action={phase="locomotion"}}
 for _,face in ipairs({{0,-1},{0,1},{1,0},{-1,0}})do for _,moving in ipairs({true,false})do
  g.player.moving=moving;g.locomotion.faceX,g.locomotion.faceY=face[1],face[2]
  for i=0,72 do g.locomotion.time=i/100;local state,index=V.SelectHero(g);check(A.fufu.frames[state]and index>=1 and index<=#A.fufu.frames[state])end
 end end
 for _,name in ipairs({"summon","bulb","hurt"})do
  g.action={name=name,phase="impact",time=.35,windup=.25,impactAt=.35,impactEnd=.45,duration=.6}
  local state,index=V.SelectHero(g);check(state==(name=="bulb"and"bulbThrow"or name));check(index==3)
 end
 g.action={name="bulb",phase="impact",time=.18,windup=.12,impactAt=.18,impactEnd=.28,duration=.45};local state,index=V.SelectHero(g);check(state=="bulbThrow"and index==3)
 for _,id in ipairs({"fufuSnack","fufuCheckup","fufuClaws","fufuMaple","fufuWater","fufuProtection","fufuTeething","fufuWaterproof","fufuLink","fufuBlink","fufuBlanket","fufuDuty"})do check(Icons.buff.frames[id].sheet.key=="fufu_buffs")end
 for _,id in ipairs({"cake","bulb","electricBulb","flashBulb","maple","water","dan","cat","dog"})do check(Icons.item.frames[id].sheet~=nil)end
 local calls={};local art={Region=function(...)calls[#calls+1]={...};return true end}
 local e={kind="fufuWater",x=100,y=100,targetX=200,targetY=100,size=260,life=.2,maxLife=.23}
 check(V.Effect(art,e,g));check(calls[1][3]==150 and calls[1][4]==100 and calls[1][5]==100);check(e.x==100 and e.targetX==200)
 calls={};V.Status(art,g,{hp=50,wetTimer=1,bleedTimer=1,stunTimer=1,x=100,y=100},80);check(#calls==3)
 calls={};V.Status(art,g,{hp=0,wetTimer=1,x=100,y=100},80);check(#calls==0)
 check(g.player.x==520 and g.player.y==560)
 print("[FufuVisuals] "..n.." checks passed");return n
end
return M
