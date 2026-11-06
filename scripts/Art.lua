-- 生图美术资源层：句柄只在初始化时创建，退出逐一释放。
-- 静态主角直接使用选人原立绘：battle源图的身材不同，等比缩放也不能修复。
local Art = {}
local Heroes = require("Heroes")
local VisualScale = require("VisualScale")
local PATHS = {
    male = Heroes.Get("male").portrait, female = Heroes.Get("female").portrait,
    coworker = "image/generated/boss_coworker.png", supervisor = "image/generated/boss_supervisor.png",
    owner = "image/generated/boss_owner.png", ghost = "image/generated/enemy_overtime.png",
    paper = "image/generated/enemy_report.png", message = "image/generated/enemy_message.png",
    pot = "image/generated/enemy_blame.png", floor1 = "image/generated/floor1_wall.png",
    floor2 = "image/generated/floor2_wall.png", floor3 = "image/generated/floor3_wall.png",
    desk = "image/generated/desk.png", cabinet = "image/generated/cabinet.png",
    planter = "image/generated/planter.png", server = "image/generated/server.png",
    partition = "image/generated/partition_surface.png",
    exitClosed = "image/generated/exit_closed.png", exitOpen = "image/generated/exit_open.png",
}
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
            images[name] = { handle = handle, width = width, height = height }
            loaded = loaded + 1
        else
            print("[美术错误] 图片加载失败：" .. path)
        end
    end
    print("[美术] 资源加载 " .. loaded .. " / " .. total .. "，主角原立绘静态fallback，等比脚点对齐")
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

-- 静态fallback，不模拟走路/呼吸：phase、moving仅保留旧调用兼容。
-- 主角严格取原立绘；未来动画播放器可替换此绘制入口，但须遵循同一身高与脚点。
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

function Art.Stop()
    if context then
        for _, image in pairs(images) do nvgDeleteImage(context, image.handle) end
    end
    images, context = {}, nil
end
return Art
