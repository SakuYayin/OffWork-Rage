-- Office stationery skin. PixelForge typography / sharp edges; generated art owns the frame detail.
-- All text and actions remain real UI widgets. Resource roots omit the assets/ prefix.
local UI = require("urhox-libs/UI")
local Skin = {}

Skin.assets = {
    background = "image/ui/menu_background.png",
    panel = "image/ui/panel.png",
    primary = "image/ui/button_primary.png",
    secondary = "image/ui/button_secondary.png",
    portrait = "image/ui/portrait_frame.png",
    computer = "image/ui/computer_bezel.png",
    computerStand = "image/ui/computer_stand.png",
    employeeBadge = "image/ui/employee_badge.png",
}

-- Explicit aliases retain existing gameplay rarity keys without purple/blue slabs.
Skin.colors = {
    bg = { 19, 35, 46, 255 }, navy = { 24, 43, 55, 255 },
    surface = { 239, 226, 197, 255 }, paper = { 247, 237, 215, 255 },
    ink = { 54, 44, 37, 255 }, white = { 54, 44, 37, 255 },
    cream = { 250, 240, 217, 255 }, muted = { 119, 104, 87, 255 },
    line = { 154, 125, 90, 255 }, wood = { 113, 78, 53, 255 },
    teal = { 33, 114, 107, 255 }, pink = { 174, 66, 93, 255 },
    gold = { 151, 101, 39, 255 }, purple = { 51, 78, 92, 255 },
    lightMuted = { 193, 199, 187, 255 },
}

-- Widget:RenderSlicedImage reads indexed {top, right, bottom, left}; named keys are not honored.
local PANEL_SLICE = { 18, 18, 18, 18 }
local BUTTON_SLICE = { 12, 12, 12, 12 }
local FRAME_SLICE = { 12, 12, 12, 12 }

---@param props table?
---@param defaults table
---@return table
local function Merge(props, defaults)
    local result = {}
    for key, value in pairs(defaults) do result[key] = value end
    if props then for key, value in pairs(props) do result[key] = value end end
    return result
end

function Skin.Init()
    local c = Skin.colors
    -- User art direction overrides the stock purple palette; structure still follows PixelForge.
    local theme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/FusionPixel-12px-Prop-zh_hans.ttf",
                bold = "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf",
            } },
            { family = "mono", weights = { normal = "Fonts/FusionPixel-12px-Mono-zh_hans.ttf" } },
        },
        colors = {
            primary = c.teal, primaryHover = { 44, 131, 119, 255 }, primaryPressed = { 25, 90, 86, 255 },
            secondary = c.wood, secondaryHover = { 137, 98, 66, 255 }, secondaryPressed = { 88, 62, 45, 255 },
            background = c.bg, surface = c.surface, surfaceHover = c.paper,
            text = c.ink, textSecondary = c.muted, textDisabled = c.muted,
            border = c.line, borderFocus = c.teal, disabled = { 201, 191, 170, 255 },
            disabledText = { 114, 106, 94, 255 }, success = c.teal, warning = c.gold,
            error = c.pink, info = c.navy, overlay = { 12, 21, 27, 205 },
            heroMale = c.teal, heroFemale = c.pink, heroNavy = c.navy, heroSurface = c.paper,
            heroMaleSurface = { 224, 230, 206, 255 }, heroFemaleSurface = { 241, 219, 206, 255 },
        },
        componentDefaults = { borderRadius = 0 },
        components = {
            Panel = { borderRadius = 0 },
            Button = { borderRadius = 0, height = 46, borderWidth = 0,
                boxShadow = { { x = 2, y = 3, blur = 0, color = { 17, 24, 27, 100 } } },
                pressedBoxShadow = false,
            },
            Card = { borderRadius = 0, borderWidth = 0,
                boxShadow = { { x = 3, y = 4, blur = 0, color = { 12, 23, 30, 115 } } },
            },
            ProgressBar = { borderRadius = 0, height = 7, borderWidth = 1,
                backgroundColor = { 201, 184, 156, 255 }, borderColor = c.wood },
        },
    })
    UI.Init({ theme = theme, scale = UI.Scale.DEFAULT })
    print("[UI皮肤] 米纸/木棕/深海蓝；生成图片九宫格，全控件交互")
end

---@param name string?
---@return table
function Skin.Color(name) return Skin.colors[name or "ink"] or Skin.colors.ink end

---@param text string
---@param size number?
---@param color string?
---@param extra table?
---@return Label
function Skin.Text(text, size, color, extra)
    return UI.Label(Merge(extra, { text = text, fontSize = size or 10.5,
        fontColor = Skin.Color(color), fontFamily = "sans", flexShrink = 1,
        minWidth = 0, pointerEvents = "none" }))
end

---@param props table?
---@return Card
function Skin.Card(props)
    -- Final generated panel keeps brass frame detail and a warm paper-textured center.
    return UI.Card(Merge(props, { variant = "elevated", padding = 20, gap = 12,
        backgroundColor = Skin.colors.surface, backgroundImage = Skin.assets.panel,
        backgroundFit = "sliced", backgroundSlice = PANEL_SLICE }))
end

---@param props table?
---@return Button
function Skin.Button(props)
    local secondary = props and props.variant == "secondary"
    local path = secondary and Skin.assets.secondary or Skin.assets.primary
    return UI.Button(Merge(props, { variant = secondary and "secondary" or "primary",
        backgroundImage = path, backgroundFit = "sliced", backgroundSlice = BUTTON_SLICE,
        -- Hover and disabled opacity give real interaction feedback without synthetic page images.
        hoverBackgroundImage = path, hoverBackgroundImageOpacity = 0.94,
        pressedBackgroundImage = path, pressedBackgroundImageOpacity = 0.78,
        disabledBackgroundImage = path, disabledBackgroundImageOpacity = 0.16,
        backgroundColor = secondary and Skin.colors.wood or Skin.colors.teal,
        disabledBackgroundColor = { 209, 198, 174, 255 },
        textColor = Skin.colors.cream,
        disabledTextColor = { 82, 72, 61, 255 }, fontSize = 10.5, height = 46,
        paddingHorizontal = 14, paddingVertical = 4 }))
end

---@param props table?
---@return Panel
function Skin.PortraitFrame(props)
    return UI.Panel(Merge(props, { backgroundImage = Skin.assets.portrait,
        backgroundFit = "sliced", backgroundSlice = FRAME_SLICE, pointerEvents = "none" }))
end

---@return Panel
function Skin.Rule()
    return UI.Panel { height = 1, width = "100%", backgroundColor = Skin.colors.line,
        opacity = 0.55, pointerEvents = "none" }
end

---@param props table?
---@return Panel
function Skin.Background(props)
    return UI.Panel(Merge(props, { width = "100%", height = "100%",
        backgroundImage = Skin.assets.background, backgroundFit = "cover",
        backgroundColor = Skin.colors.navy, pointerEvents = "none" }))
end

return Skin
