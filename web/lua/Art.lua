-- 生图美术资源层：句柄只在初始化时创建，退出逐一释放。
-- 菜单立绘与战斗小人独立；主角使用有脚点信息的逐帧图集。
local Art = {}
local Heroes = require("Heroes")
local VisualScale = require("VisualScale")
local HeroSprites = require("HeroSprites")
local HeroAnimation = require("HeroAnimation")
local EnemySprites = require("EnemySprites")
local EnemyAnimation = require("EnemyAnimation")
local InterfaceIcons = require("InterfaceIcons")
local EffectSprites = require("EffectSprites")
local Expansion = require("ExpansionArt")
local FufuArt=require("FufuArt").sheets
local FufuVisuals=require("FufuVisuals")
local PATHS = {
    male = Heroes.Get("male").sprite, female = Heroes.Get("female").sprite,
    maleDirections = HeroSprites.male.directions.path,
    femaleDirections = HeroSprites.female.directions.path,
    coworker = EnemySprites.coworker.path, supervisor = EnemySprites.supervisor.path,
    owner = EnemySprites.owner.path, ghost = EnemySprites.ghost.path,
    paper = EnemySprites.paper.path, message = EnemySprites.message.path,
    pot = EnemySprites.pot.path, floor1 = "image/generated/floor1_wall.png",
    itemIcons = InterfaceIcons.item.path,
    loot = EffectSprites.loot.path, weapon = EffectSprites.weapon.path, area = EffectSprites.area.path,
    floor2 = "image/generated/floor2_wall.png", floor3 = "image/generated/floor3_wall.png",
    desk = "image/generated/desk.png", cabinet = "image/generated/cabinet.png",
    planter = "image/generated/planter.png", server = "image/generated/server.png",
    partition = "image/generated/partition_surface.png",
    exitClosed = "image/generated/exit_closed.png", exitOpen = "image/generated/exit_open.png",
}
for id,d in pairs(Expansion.heroes)do PATHS[id]=d.path end
for id,d in pairs(Expansion.enemies)do PATHS[id]=d.path end
for id,d in pairs(Expansion.effects)do PATHS[id]=d.path end
for id,d in pairs(EffectSprites)do PATHS[id]=d.path end
for id,d in pairs(Expansion.icons)do PATHS[id]=d.path end
for id,d in pairs(Expansion.heroOverrides or {})do PATHS[id]=d.path end
for id,d in pairs(FufuArt)do PATHS[id=="fufu"and"fufu"or"fufu_"..id]=d.path end
---@type NVGContextWrapper?
local context = nil
---@class OfficeArtImage
---@field handle integer
---@field width number
---@field height number
---@type table<string, OfficeArtImage>
local images = {}

---@param ctx NVGContextWrapper
function Art.Init(ctx)
    context = ctx
    local loaded, total = 0, 0
    for name, path in pairs(PATHS) do
        total = total + 1
        local handle = nvgCreateImage(ctx, path, NVG_IMAGE_NEAREST)
        if handle >= 0 then
            local width, height = nvgImageSize(ctx, handle)
            local definition = HeroSprites[name] or EnemySprites[name]
                or Expansion.heroOverrides[name] or Expansion.icons[name] or EffectSprites[name]
                or FufuArt[name=="fufu"and"fufu"or name:match("^fufu_(.+)$")]
                or (name == "maleDirections" and HeroSprites.male.directions)
                or (name == "femaleDirections" and HeroSprites.female.directions)
            if definition then
        assert(width == definition.width and height == definition.height,
                    "主角图集尺寸与拆帧记录不匹配：" .. name)
            end
            images[name] = { handle = handle, width = width, height = height }
            loaded = loaded + 1
        else
            print("[美术错误] 图片加载失败：" .. path)
        end
    end
    print("[美术] 资源加载 " .. loaded .. " / " .. total .. "，主角战斗图集，菜单立绘独立")
end

function Art.Image(name, x, y, width, height, alpha, tint)
    local image = images[name]
    if not context or not image then return false end
    nvgBeginPath(context)
    nvgRect(context, x, y, width, height)
    if tint then
        nvgFillPaint(context, nvgImagePatternTinted(context, x, y, width, height, 0, image.handle, tint))
    else
        nvgFillPaint(context, nvgImagePattern(context, x, y, width, height, 0, image.handle, alpha or 1))
    end
    nvgFill(context)
    return true
end

-- 完整资源等比缩放到矩形内，以底边对齐真实门槛，绝不分别拉伸X/Y。
function Art.Contain(name, x, y, width, height, alpha)
    local image = images[name]
    if not image then return false end
    local scale = math.min(width / image.width, height / image.height)
    local drawW, drawH = image.width * scale, image.height * scale
    return Art.Image(name, x + (width - drawW) / 2, y + height - drawH, drawW, drawH, alpha or 1)
end

-- Compatibility entry point for props; gameplay actors use Hero/Enemy frames below.
---@param name string
---@param x number
---@param y number
---@param height number
---@param flip boolean
---@param phase number?
---@param moving boolean?
---@param hit boolean?
---@param alpha number?
function Art.Actor(name, x, y, height, flip, phase, moving, hit, alpha)
    local image = images[name]
    if not context or not image then return false end
    local width, drawHeight = VisualScale.ActorSize(image.width, image.height, height)
    nvgSave(context)
    nvgTranslate(context, x, y)
    nvgScale(context, flip and -1 or 1, 1)
    local tint = hit and nvgRGBA(255, 105, 123, math.floor((alpha or 1) * 255)) or nil
    Art.Image(name, -width / 2, -drawHeight, width, drawHeight, alpha or 1, tint)
    nvgRestore(context)
    return true
end

function Art.Hero(g, height, alpha)
    local name = g.heroId or "male"
    local definition, image = HeroSprites[name], images[name]
    if not definition or not image then return false end
    local state, index
    if name=="fufu"then state,index=FufuVisuals.SelectHero(g)else state,index=HeroAnimation.Select(g)end
    local directional = definition.frames[state] == nil
    if directional then definition, image = definition.directions, images[name .. "Directions"] end
    if not definition or not image then return false end
    local row=definition.frames[state]
    local frame = row[1+(index-1)%#row]
    if frame.sheet then image=images[frame.sheet.key];definition=frame.sheet end
    local scale = height / definition.referenceHeight
    local width, drawHeight = frame.w * scale, frame.h * scale
    local x, y = -frame.anchorX * scale, -drawHeight
    local action = g.action or g.locomotion
    local facingLeft = action and action.faceX < 0 or false
    local cardinal=state:find("^up")or state:find("^down")
    local flip = not directional and not cardinal and (facingLeft ~= ((definition.sourceFacing[state]or 1) < 0))
    local tint = action and action.name == "hurt" and nvgRGBA(255, 105, 123, 190) or nil
    nvgSave(context)
    nvgTranslate(context, g.player.x, g.player.y)
    nvgScale(context, flip and -1 or 1, 1)
    if type(nvgDrawSpriteFrame) == "function" then
        nvgDrawSpriteFrame(context, image.handle, frame.x, frame.y, frame.w, frame.h,
            x, y, width, drawHeight, alpha or 1, tint)
    else
        -- Native NanoVG fills only the path; the pattern locates the atlas cell.
        nvgBeginPath(context)
        nvgRect(context, x, y, width, drawHeight)
        nvgFillPaint(context, nvgImagePattern(context, x - frame.x * scale, y - frame.y * scale,
            image.width * scale, image.height * scale, 0, image.handle, alpha or 1))
        nvgFill(context)
    end
    nvgRestore(context)
    return true
end

function Art.Enemy(g,e)
    local name=EnemyAnimation.Name(e)
    local definition,image=EnemySprites[name],images[name]
    if not definition or not image then return false end
    local state,index,flip=EnemyAnimation.Select(g,e)
    local frame=definition.frames[state][index]
    local scale=VisualScale.ActorHeight(name)/definition.referenceHeight
    local w,h=frame.w*scale,frame.h*scale
    local alpha=e.deathTime and math.max(0,1-e.deathTime/.55)or 1
    local tint=(e.hit or 0)>0 and nvgRGBA(255,105,123,235)or nil
    nvgSave(context);nvgTranslate(context,e.x,e.y);nvgScale(context,flip and -1 or 1,1)
    if type(nvgDrawSpriteFrame)=="function"then
        nvgDrawSpriteFrame(context,image.handle,frame.x,frame.y,frame.w,frame.h,-frame.anchorX*scale,-h,w,h,alpha,tint)
    else
        nvgBeginPath(context);nvgRect(context,-frame.anchorX*scale,-h,w,h)
        nvgFillPaint(context,nvgImagePattern(context,-frame.anchorX*scale-frame.x*scale,-h-frame.y*scale,
            image.width*scale,image.height*scale,0,image.handle,alpha));nvgFill(context)
    end
    nvgRestore(context);return true
end

function Art.Item(id,x,y,width,height)
    local d=InterfaceIcons.item;local f=d.frames[id]
    d=f and f.sheet or d
    local im=images[d.key or "itemIcons"]
    if not f or not im then return false end
    local scale=math.min(width/f.w,height/f.h);local w,h=f.w*scale,f.h*scale
    if type(nvgDrawSpriteFrame)=="function"then
        nvgDrawSpriteFrame(context,im.handle,f.x,f.y,f.w,f.h,x-w/2,y-h/2,w,h,1,nil)
    else
        nvgBeginPath(context);nvgRect(context,x-w/2,y-h/2,w,h)
        nvgFillPaint(context,nvgImagePattern(context,x-w/2-f.x*scale,y-h/2-f.y*scale,
            im.width*scale,im.height*scale,0,im.handle,1));nvgFill(context)
    end
    return true
end

-- Fixed source cells preserve the growth of authored effects; loot uses its measured silhouette.
function Art.Fx(sheet,index,x,y,size,alpha,angle,crop)
    local d,im=EffectSprites[sheet],images[sheet]
    if not d or not im then return false end
    local frame=d.frames[index];if not frame then return false end
    local f=crop and frame.content or frame
    local scale=size/math.max(f.w,f.h);local w,h=f.w*scale,f.h*scale
    nvgSave(context);nvgTranslate(context,x,y);if angle then nvgRotate(context,angle)end
    if type(nvgDrawSpriteFrame)=="function"then
        nvgDrawSpriteFrame(context,im.handle,f.x,f.y,f.w,f.h,-w/2,-h/2,w,h,alpha or 1,nil)
    else
        nvgBeginPath(context);nvgRect(context,-w/2,-h/2,w,h)
        nvgFillPaint(context,nvgImagePattern(context,-w/2-f.x*scale,-h/2-f.y*scale,
            im.width*scale,im.height*scale,0,im.handle,alpha or 1));nvgFill(context)
    end
    nvgRestore(context);return true
end

-- Centered crop renderer shared by independent actor/effect adapters.
function Art.Region(name,f,x,y,width,height,alpha,angle,tint)
 local im=images[name];if not context or not im or not f then return false end
 nvgSave(context);nvgTranslate(context,x,y);if angle then nvgRotate(context,angle)end
 if type(nvgDrawSpriteFrame)=="function"then
  nvgDrawSpriteFrame(context,im.handle,f.x,f.y,f.w,f.h,-width/2,-height/2,width,height,alpha or 1,tint)
 else
  nvgBeginPath(context);nvgRect(context,-width/2,-height/2,width,height)
  nvgFillPaint(context,nvgImagePattern(context,-width/2-f.x*width/f.w,-height/2-f.y*height/f.h,im.width*width/f.w,im.height*height/f.h,0,im.handle,alpha or 1));nvgFill(context)
 end
 nvgRestore(context);return true
end

function Art.Stop()
    if context then
        for _, image in pairs(images) do nvgDeleteImage(context, image.handle) end
    end
    images, context = {}, nil
end
return Art
