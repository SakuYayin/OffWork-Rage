-- Original generated PNG atlas regions, measured during approved UI prototype.
local definitions = {
 buff = {path = "image/icons/buff-icons.png", width = 1448, height = 1086, frames = {
 stapler = { x = 24, y = 61, w = 312, h = 283 },
 coffee = { x = 384, y = 33, w = 321, h = 317 },
 damage = { x = 730, y = 34, w = 318, h = 309 },
 speed = { x = 1102, y = 54, w = 323, h = 273 },
 attack = { x = 12, y = 404, w = 344, h = 261 },
 range = { x = 380, y = 388, w = 337, h = 292 },
 magnet = { x = 736, y = 380, w = 327, h = 301 },
 health = { x = 1103, y = 383, w = 322, h = 294 },
 regen = { x = 9, y = 736, w = 345, h = 299 },
 armor = { x = 375, y = 724, w = 339, h = 313 },
 crit = { x = 735, y = 740, w = 351, h = 286 },
 rage = { x = 1086, y = 724, w = 348, h = 328 },
 } },
 item = {path = "image/icons/item-icons.png", width = 1774, height = 887, frames = {
 keyboard = { x = 17, y = 81, w = 427, h = 363 },
 coffee = { x = 526, y = 24, w = 295, h = 420 },
 stapler = { x = 887, y = 80, w = 396, h = 347 },
 badge = { x = 1343, y = 23, w = 414, h = 421 },
 coin = { x = 37, y = 513, w = 358, h = 334 },
 riceball = { x = 464, y = 513, w = 364, h = 329 },
 headphones = { x = 887, y = 486, w = 364, h = 380 },
 phone = { x = 1331, y = 487, w = 431, h = 372 },
 } },
}

for group,d in pairs(require("ExpansionArt").icons)do local target=group=="itemsExpansion"and definitions.item or definitions.buff for id,f in pairs(d.frames)do f.sheet=d;target.frames[id]=f end end
local fufu=require("FufuArt").sheets
local function fufuFrame(d,frame)
 local sheet={path=d.path,key="fufu_"..d.key,width=d.width,height=d.height}
 local f={};for k,v in pairs(frame)do f[k]=v end;f.sheet=sheet;return f
end
for _,kind in ipairs({"maple","water","dan","cat","dog"})do definitions.item.frames[kind]=fufuFrame(fufu[kind],fufu[kind].portraitRegion)end
local itemMap={cake="item01",bulb="item05",electricBulb="item05",flashBulb="item08"}
for id,source in pairs(itemMap)do definitions.item.frames[id]=fufuFrame(fufu.items,fufu.items.frames[source])end
for id,frame in pairs(fufu.buffs.frames)do definitions.buff.frames[id]=fufuFrame(fufu.buffs,frame);definitions.buff.frames["fufu_"..id]=fufuFrame(fufu.buffs,frame)end
local fufuBuffIds={fufuSnack="snack",fufuCheckup="checkup",fufuClaws="claws",fufuMaple="maple",fufuWater="livingWater",fufuProtection="protection",fufuTeething="teething",fufuWaterproof="waterproof",fufuLink="link",fufuBlink="blink",fufuBlanket="blanket",fufuDuty="onDuty"}
for id,source in pairs(fufuBuffIds)do definitions.buff.frames[id]=fufuFrame(fufu.buffs,fufu.buffs.frames[source])end
return definitions
