-- Rendering-only adapter for the approved Fufu atlases. Never mutates game state.
local V={}
local A=require("FufuArt").sheets
local H=require("HeroAnimation")
local effects={fufuSummon="summon",fufuClaw="claw",fufuWater="water",fufuElectric="electric",fufuFlash="flash",fufuGlass="glass",fufuGuard="guard",fufuDepart="depart"}
local function Frames(d,state)return d.frames[state]or d.frames.idle end
function V.SelectHero(g)
 local action=g.action
 if action and action.phase~="locomotion"then
  local state=action.name=="summon"and"summon"or(action.name=="bulb"and"bulbThrow"or(action.name=="hurt"and"hurt"or nil))
  if state then
   local time=action.time or 0
   if action.impactAt and action.impactEnd and action.windup then
    local frame=time<action.windup and(time<action.windup*.5 and 1 or 2)or(time<action.impactAt and 2 or(time<action.impactEnd and 3 or 4))
    return state,frame
   end
   return state,math.min(4,1+math.floor(time/math.max(.01,action.duration or(action.name=="summon"and .6 or .45))*4))
  end
 end
 local p=g.locomotion or g.player
 local direction=H.Direction(p.faceX or 1,p.faceY or 0)
 local moving=g.player.moving==true
 local state=direction=="up"and(moving and"upWalk"or"upIdle")or(direction=="down"and(moving and"downWalk"or"idle")or(moving and"walk"or"idle"))
 local count=#Frames(A.fufu,state)
 local duration=p.duration or(moving and .72 or 1.2)
 return state,math.min(count,1+math.floor(((p.time or g.time or 0)%duration)/duration*count))
end
local function Actor(Art,ctx,d,key,frame,x,y,height,left,alpha,tint)
 local scale=height/d.referenceHeight
 nvgSave(ctx);nvgTranslate(ctx,x,y);nvgScale(ctx,left and -1 or 1,1)
 Art.Region(key,frame,(frame.w/2-frame.anchorX)*scale,-frame.h*scale/2,frame.w*scale,frame.h*scale,alpha,nil,tint)
 nvgRestore(ctx)
end
function V.Pet(Art,ctx,g,pet)
 local d=A[pet.kind];if not d then return end
 local direction=H.Direction(pet.faceX or 1,pet.faceY or 0)
 local state=(pet.attackTime or 0)>0 and(pet.kind=="dan"and"guard"or"attack")or(pet.moving and(direction=="up"and"upWalk"or(direction=="down"and"downWalk"or"walk"))or"idle")
 local frames=Frames(d,state)
 local index=1+math.floor((pet.animationTime or g.time or 0)*8)%#frames
 local height=pet.kind=="dan"and 48 or 43
 -- Shadows and health bars are geometry; the creature and protection glow use generated art.
 nvgBeginPath(ctx);nvgEllipse(ctx,pet.x,pet.y,16,5);nvgFillColor(ctx,nvgRGBA(8,15,24,95));nvgFill(ctx)
 if(pet.protection or 0)>0 then V.Effect(Art,{kind="fufuGuard",x=pet.x,y=pet.y-20,size=60,life=.7,maxLife=1},g)end
 Actor(Art,ctx,d,"fufu_"..pet.kind,frames[index],pet.x,pet.y,height,direction=="side"and(pet.faceX or 1)<0,1,(pet.hit or 0)>0 and nvgRGBA(255,120,145,230)or nil)
 if pet.hp and pet.maxHp and pet.hp<pet.maxHp then
  nvgBeginPath(ctx);nvgRect(ctx,pet.x-17,pet.y-height-9,34,4);nvgFillColor(ctx,nvgRGBA(22,29,43,220));nvgFill(ctx)
  nvgBeginPath(ctx);nvgRect(ctx,pet.x-16,pet.y-height-8,32*math.max(0,pet.hp/pet.maxHp),2);nvgFillColor(ctx,nvgRGBA(109,222,174,255));nvgFill(ctx)
 end
end
-- Scale all four frames in a row against one row envelope, retaining authored growth.
local envelope={}
local function Fx(Art,state,index,x,y,size,alpha,angle,sheet)
 sheet=sheet or"effects";local d=A[sheet];local list=d.frames[state];if not list then return false end
 local f=list[index]or list[1];local key=sheet..":"..state
 if not envelope[key]then local w,h=0,0;for _,q in ipairs(list)do w=math.max(w,q.w);h=math.max(h,q.h)end;envelope[key]=math.max(w,h)end
 local scale=size/envelope[key]
 return Art.Region("fufu_"..sheet,f,x,y,f.w*scale,f.h*scale,alpha,angle)
end
function V.Effect(Art,e,g)
 local state=effects[e.kind];if not state then return false end
 local ratio=math.max(0,math.min(1,(e.life or 0)/math.max(.001,e.maxLife or 1)))
 local frame=math.min(4,1+math.floor((1-ratio)*4))
 if(e.kind=="fufuWater"or e.kind=="fufuElectric")and e.targetX and e.targetY then
  local dx,dy=e.targetX-e.x,e.targetY-e.y
  local distance=math.sqrt(dx*dx+dy*dy)
  if distance>.1 then
   local f=A.effects.frames[state][frame]
   return Art.Region("fufu_effects",f,(e.x+e.targetX)/2,(e.y+e.targetY)/2,distance,e.kind=="fufuWater"and 26 or 16,math.min(1,ratio*3),math.atan(dy,dx))
  end
 end
 return Fx(Art,state,frame,e.x,e.y-8,e.size or 56,math.min(1,ratio*3),e.angle)
end
function V.Bulb(Art,s,g)
 local kind=s.bulbType or"normal"
 local f=A.items.frames[kind=="flash"and"item08"or"item05"]
 local size=25/math.max(f.w,f.h)
 Art.Region("fufu_items",f,s.x,s.y-12,f.w*size,f.h*size,1,(g.time or 0)*5)
 if kind=="electric"then Fx(Art,"electric",1+math.floor((g.time or 0)*12)%4,s.x,s.y-12,39,.95,math.atan(s.vy or 0,s.vx or 1))
 elseif kind=="flash"then Fx(Art,"flash",1+math.floor((g.time or 0)*12)%4,s.x,s.y-12,31,.85)end
 return true
end
function V.Status(Art,g,e,height)
 if(e.hp or 0)<=0 or((e.wetTimer or 0)<=0 and(e.bleedTimer or 0)<=0 and(e.stunTimer or 0)<=0)then return end
 local states={}
 if(e.wetTimer or 0)>0 then states[#states+1]="wet"end
 if(e.bleedTimer or 0)>0 then states[#states+1]="bleed"end
 if(e.stunTimer or 0)>0 then states[#states+1]="stun"end
 for i,state in ipairs(states)do Fx(Art,state,1+math.floor((g.time or 0)*6)%4,e.x+(i-(#states+1)/2)*15,e.y-height-12,14,1,nil,"status")end
end
return V
