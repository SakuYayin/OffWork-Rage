local UI = require("urhox-libs/UI")
local Scale = require("InterfaceScale")
local Icons = require("InterfaceIcons")
local HeroSprites = require("HeroSprites")
local Skin = {}
Skin.colors = {
    bg = { 17, 26, 46, 225 }, navy = { 38, 43, 67, 240 },
    surface = { 255, 240, 213, 255 }, paper = { 255, 245, 222, 255 },
    ink = { 62, 53, 87, 255 }, white = { 62, 53, 87, 255 },
    cream = { 255, 240, 207, 255 }, muted = { 117, 102, 125, 255 },
    line = { 156, 141, 177, 255 }, wood = { 78, 84, 132, 255 },
    teal = { 39, 114, 161, 255 }, pink = { 183, 64, 100, 255 },
    gold = { 166, 96, 39, 255 }, purple = { 117, 96, 173, 255 },
    lightMuted = { 204, 211, 231, 255 }, hp = { 255, 107, 133, 255 },
    xp = { 101, 217, 255, 255 }, yellow = { 255, 207, 103, 255 },
}
Skin.assets = {} -- Kept for campaign compatibility; no old brass frame images.
Skin.uiAssets={paper="image/ui/paper.png",notes="image/ui/notes.png",badge="image/ui/badge.png",desk="image/ui/desk.png"}
-- Semantic accents for the office stationery theme; gameplay warning colors stay distinct.
Skin.colors.ink={66,42,61,255};Skin.colors.muted={113,79,90,255}
Skin.colors.surface={255,244,218,255};Skin.colors.paper={255,248,229,255}
Skin.colors.teal={19,116,112,255};Skin.colors.pink={188,59,83,255}
Skin.colors.gold={151,85,17,255};Skin.colors.purple={111,62,155,255}
Skin.colors.line={186,135,103,255}
function Skin.Init()
    UI.Init({ scale = UI.Scale.DEFAULT, theme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        fonts = {
            {family="sans",weights={normal="Fonts/FusionPixel-12px-Prop-zh_hans.ttf",bold="Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf"}},
            {family="mono",weights={normal="Fonts/FusionPixel-12px-Mono-zh_hans.ttf"}},
        },
        colors = { text = Skin.colors.ink, surface = Skin.colors.surface, primary = Skin.colors.yellow },
        componentDefaults = { borderRadius = 0 },
    }) })
end
function Skin.Color(name) return Skin.colors[name or "ink"] or Skin.colors.ink end
local function Merge(props, defaults)
    local r = {}; for k,v in pairs(defaults) do r[k] = v end
    if props then for k,v in pairs(props) do r[k] = v end end; return r
end
function Skin.Text(text, size, color, extra)
    local props=Merge(extra, { text = text, fontSize = Scale.Get().px(size or 16),
        fontColor = Skin.Color(color), fontFamily = "sans", flexShrink = 0,
        minWidth = 0, whiteSpace = "normal", lineHeight = 1.35 })
    props.className=(props.className or "").." text-"..(color or "ink")
    return UI.Label(props)
end
function Skin.Card(props)
    return UI.Card(Merge(props, { className = "game-card", padding = Scale.Get().px(22), gap = Scale.Get().px(12),
        backgroundColor = Skin.colors.surface, borderWidth = 2, borderColor = Skin.colors.line }))
end
function Skin.Panel(props)
    return UI.Panel(Merge(props, { className = "game-panel", backgroundColor = Skin.colors.navy,
        borderWidth = 2, borderColor = {129,139,181,255} }))
end
function Skin.Button(props)
    local secondary = props and props.variant == "secondary"
    local p = Scale.Get()
    local id=props and props.id or ""
    local tone=props and props.tone
    if not tone then
        if id:find("Back")or id:find("back")or id:find("Cancel")or id:find("Clear")or id:find("Leave")then tone="coral"
        elseif id:find("music")or id:find("Buy")or id:find("Refresh")or id:find("Resume")then tone="mint"
        elseif secondary or id:find("sfx")then tone="lilac"else tone="yellow"end
    end
    local result=Merge(props, { className = secondary and "game-button secondary" or "game-button primary",
        backgroundColor = secondary and Skin.colors.wood or Skin.colors.yellow,
        fontColor = secondary and Skin.colors.cream or Skin.colors.ink,
        fontSize = p.px(18), height = math.max(44,p.px(52)),
        paddingHorizontal = p.px(16), paddingVertical = p.px(6) })
    if result.fontSize<=12 then result.fontSize=p.px(14)end
    result.fontSize=math.max(13,result.fontSize)
    if result.height<=48 then result.height=math.max(44,p.px(result.height))end
    result.className=(result.className or "game-button").." stationery-button tone-"..tone
    return UI.Button(result)
end
-- Region cropping reads the unchanged generated PNG; no per-frame UI canvas.
function Skin.Sprite(definition, frame, width, height, id)
    local s = math.min(width / frame.w, height / frame.h)
    return UI.Panel { id = id, width = width, height = height, flexShrink = 0,
        pointerEvents = "none", alignItems = "center", justifyContent = "center", children = {
            UI.Panel { width = frame.w * s, height = frame.h * s, pointerEvents = "none",
                backgroundImage = definition.path, backgroundFit = "contain",
                backgroundFrame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h,
                    atlasW = definition.width, atlasH = definition.height } },
        } }
end
function Skin.Icon(kind, id, width, height, widgetId)
    local d = assert(Icons[kind], "Unknown icon kind")
    local frame = d.frames[id]
    if not frame then
        -- S2 防御：未知帧降级为空 Panel（不再 assert 崩 HUD）。
        return UI.Panel { id = widgetId, width = width, height = height, flexShrink = 0, pointerEvents = "none" }
    end
    return Skin.Sprite(frame.sheet or d, frame, width, height, widgetId)
end
function Skin.Hero(id, width, height, widgetId)
    local d = HeroSprites[id].directions
    return Skin.Sprite(d,d.frames.downIdle[1],width,height,widgetId)
end
function Skin.Avatar(id,width,height,widgetId)
    if id=="fufu"then local d=require("FufuArt").sheets.portrait;return Skin.Sprite(d,d.portraitRegion,width,height,widgetId)end
    local d=HeroSprites[id].directions;local f=d.frames.downIdle[1]
    return Skin.Sprite(d,{x=f.x,y=f.y,w=f.w,h=math.floor(f.h*.56)},width,height,widgetId)
end
function Skin.PortraitFrame(props) return Skin.Panel(props) end
function Skin.Rule() return UI.Panel { width = "100%", height = 1, backgroundColor = Skin.colors.line, pointerEvents = "none" } end
function Skin.Background(props) return UI.Panel(Merge(props,{width="100%",height="100%",pointerEvents="none"})) end
return Skin
