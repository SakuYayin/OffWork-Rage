local Art=require("ExpansionArt")
local Heroes=require("HeroSprites")
local Enemies=require("EnemySprites")
local Icons=require("InterfaceIcons")
local Tests={}
function Tests.Run()
 local count=0;local function check(v,m)assert(v,m);count=count+1 end
 for _,group in ipairs({Art.heroes,Art.enemies})do for id,d in pairs(group)do
  check(d.referenceHeight>0,id.." reference height")
  for state,frames in pairs(d.frames)do check(#frames==4,id..state.." four authored frames")
   for _,f in ipairs(frames)do
    check(f.x>=0 and f.y>=0 and f.w>0 and f.h>0 and f.x+f.w<=d.width and f.y+f.h<=d.height,id..state.." frame in PNG")
    check(f.anchorX>=0 and f.anchorX<=f.w,id..state.." foot anchor in frame")
   end
  end
 end end
 for _,id in ipairs({"intern","programmer"})do check(Heroes[id].directions==Heroes[id],id.." shared directional sheet")end
 local staple=Art.heroOverrides.femaleStapler
 check(Heroes.female.frames.attack==staple.frames.attack,"female primary uses authored stapler poses")
 for _,f in ipairs(staple.frames.attack)do check(f.sheet==staple and staple.referenceHeight>0,"stapler override carries its own scale")end
 for _,id in ipairs({"charger","spitter","bomber","shieldGuard","summoner","printerBoss"})do check(Enemies[id]==Art.enemies[id],id.." registered")end
 for id,d in pairs(Art.icons)do for key,f in pairs(d.frames)do
  local bucket=id=="itemsExpansion"and Icons.item or Icons.buff
  check(bucket.frames[key]==f,key.." real unique icon")
  check(f.sheet==d,key.." resolves original PNG")
 end end
 print("[扩展美术回归] "..count.." checks passed");return count
end
return Tests
