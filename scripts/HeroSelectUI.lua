-- Selection owns widgets only; main.lua owns selectedHeroId and run lifecycle.
local UI = require("urhox-libs/UI")
local Heroes = require("Heroes")
local Skin = require("UISkin")
local HeroSelectUI = {}
local Text = Skin.Text

local function Accent(heroId) return heroId == "female" and "pink" or "teal" end

---@param heroId string
---@param width number|string
---@param height number
---@param id string?
---@return Panel
function HeroSelectUI.Portrait(heroId, width, height, id)
    local hero = Heroes.Get(heroId)
    -- Contain is deliberate: never stretch or crop either character's proportions.
    return UI.Panel { id = id, width = width, height = height, flexShrink = 0,
        backgroundImage = hero.portrait, backgroundFit = "contain", pointerEvents = "none" }
end

local function Metric(label, value, accent, scale)
    return UI.Panel { flexGrow = 1, flexBasis = 0, minWidth = 0, pointerEvents = "none", children = {
        Text(label, 8.25 * scale, "muted", { height = 14 * scale, flexShrink = 0,
            lineHeight = 1, textAlign = "center", verticalAlign = "middle" }),
        Text(value, 13.5 * scale, accent, { height = 22 * scale, flexShrink = 0,
            lineHeight = 1, textAlign = "center", verticalAlign = "middle", fontFamily = "mono", fontWeight = "bold" }),
    } }
end

---@param heroId string
---@param selectedHeroId string
---@param cardWidth number
---@param onSelect fun(heroId: string)
---@return Panel
local function HeroCard(heroId, selectedHeroId, cardWidth, onSelect)
    local hero = Heroes.Get(heroId)
    local chosen = heroId == selectedHeroId
    local accent = Accent(heroId)
    local scale = cardWidth / 320
    -- The complete 600x900 artwork includes the clip and transparent outer margin.
    -- Keep its 2:3 ratio, with no nine-slicing, opaque backing or old portrait frame.
    return UI.Panel {
        id = heroId == "female" and "heroSelectFemale" or "heroSelectMale",
        width = cardWidth, height = cardWidth * 1.5, flexShrink = 0,
        backgroundImage = "image/ui/employee_badge.png", backgroundFit = "contain",
        pointerEvents = "box-only", onClick = function() onSelect(heroId) end,
        children = {
            -- Source-image safe area: x=102..498, y=216..765. All content stays
            -- below the clip and above the printed bottom edge, at every card size.
            UI.Panel { position = "absolute", left = "17%", top = "24%", width = "66%", height = "61%",
                pointerEvents = "none", children = {
                    Text("昧良心科技公司", 12.75 * scale, "ink", {
                        position = "absolute", top = 0, left = 0, width = "100%", height = "9%",
                        fontWeight = "bold", textAlign = "center", verticalAlign = "middle", lineHeight = 1 }),
                    UI.Panel { id = heroId .. "LargePortrait", position = "absolute",
                        top = "12%", left = "27%", width = "46%", height = "40%",
                        backgroundImage = heroId == "female" and "image/ui/female_headshot.png" or "image/ui/male_headshot.png",
                        backgroundFit = "contain", pointerEvents = "none" },
                    Text("姓名：" .. hero.name, 18 * scale, "ink", {
                        position = "absolute", top = "53%", left = 0, width = "100%", height = "11%",
                        fontWeight = "bold", textAlign = "center", verticalAlign = "middle", lineHeight = 1 }),
                    Text(heroId == "female" and "部门：产品运营部" or "部门：技术研发部", 10.5 * scale, accent, {
                        position = "absolute", top = "64%", left = 0, width = "100%", height = "9%",
                        textAlign = "center", verticalAlign = "middle", lineHeight = 1 }),
                    UI.Panel { position = "absolute", top = "77%", left = 0, width = "100%", height = "13%",
                        flexDirection = "row", gap = 4 * scale, pointerEvents = "none", children = {
                            Metric("精力", tostring(hero.maxHp), accent, scale),
                            Metric("速度", tostring(hero.speed), accent, scale),
                            Metric("伤害", string.format("%.0f%%", hero.damage * 100), accent, scale),
                        } },
                    Text(chosen and "[ 已选择 · 本次出勤 ]" or "[ 点击工牌选择 ]", 9 * scale, "muted", {
                        id = heroId .. "SelectionState", position = "absolute",
                        top = "92%", left = 0, width = "100%", height = "8%",
                        backgroundColor = chosen and Skin.Color(accent) or Skin.Color("surface"),
                        fontColor = Skin.Color(chosen and "cream" or "muted"), fontWeight = "bold",
                        textAlign = "center", verticalAlign = "middle", lineHeight = 1 }),
                } },
        },
    }
end

---@param selectedHeroId string
---@param onSelect fun(heroId: string)
---@param onConfirm fun()
---@param onBack fun()
---@return Panel
function HeroSelectUI.Build(selectedHeroId, onSelect, onConfirm, onBack)
    local width, height = UI.GetViewportSize()
    local insets = UI.GetSafeAreaInsets()
    local screenWidth = math.max(1, math.min(width - insets.left - insets.right - 28, 1000))
    local availableHeight = math.max(1, height - insets.top - insets.bottom - 28)
    local screenHeight = math.min(availableHeight, 850)
    local mobile = screenWidth < 760
    local compact = height < 650
    local hero = Heroes.Get(selectedHeroId)
    local padding = compact and 10 or 16
    local cardGap = mobile and 12 or 20
    local contentWidth = math.max(1, screenWidth - padding * 2)
    -- Cards do not flex/stretch. Short desktop windows scroll instead of flattening
    -- the badge; narrow screens use the same artwork in one centered column.
    local cardWidth = mobile and math.min(340, contentWidth)
        or math.min(350, (contentWidth - cardGap) / 2, math.max(300, (screenHeight - 220) / 1.5))
    print(string.format("[选人UI] 员工工牌 %dx%d，竖排=%s，卡片=%.0fx%.0f，资源contain",
        math.floor(width), math.floor(height), tostring(mobile), cardWidth, cardWidth * 1.5))
    return UI.Panel { id = "heroSelectScreen", width = screenWidth,
        height = screenHeight, maxHeight = availableHeight, padding = 0, gap = 0,
        children = {
            UI.Panel { width = "100%", paddingHorizontal = padding, paddingVertical = compact and 8 or 12,
                gap = 3, flexShrink = 0, children = {
                    Text("EMPLOYEE ID / 17:59", 8.25, "lightMuted", { fontFamily = "mono", letterSpacing = 1 }),
                    Text("今天，谁来准点下班？", mobile and 19.5 or 25.5, "cream", {
                        fontWeight = "bold", whiteSpace = "normal" }),
                } },
            UI.ScrollView { id = "heroSelectScroll", width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
                scrollX = false, scrollY = true, showScrollbar = true, bounces = false, children = {
                    UI.Panel { width = "100%", paddingHorizontal = padding, paddingTop = 2, paddingBottom = 12,
                        flexDirection = mobile and "column" or "row", alignItems = "center", justifyContent = "center",
                        gap = cardGap, flexShrink = 0, children = {
                            HeroCard("male", selectedHeroId, cardWidth, onSelect),
                            HeroCard("female", selectedHeroId, cardWidth, onSelect),
                        } },
                } },
            -- Fixed footer is outside ScrollView: confirmation never scrolls out of reach on a phone.
            UI.Panel { width = "100%", padding = padding, gap = compact and 5 or 8, flexShrink = 0,
                backgroundColor = Skin.Color("paper"), children = {
                    Skin.Rule(),
                    Text("本次出勤  /  " .. hero.name .. " · " .. hero.title, 10.5, Accent(selectedHeroId), {
                        id = "heroSelectedSummary", fontWeight = "bold", whiteSpace = "normal" }),
                    UI.Panel { width = "100%", flexDirection = "row", gap = 12, children = {
                        Skin.Button { id = "heroBack", text = mobile and "返回" or "返回菜单  [ ESC ]", variant = "secondary",
                            width = mobile and 88 or 184, height = 48, fontSize = 10.5, onClick = onBack },
                        Skin.Button { id = "heroConfirm", text = "确认出勤 · " .. hero.name .. (mobile and "" or "  [ ENTER ]"),
                            flexGrow = 1, flexBasis = 0, minWidth = 0, height = 48, fontSize = 12, onClick = onConfirm },
                    } },
                    Text(mobile and "上下滑动查看 · 点击工牌切换" or "[ 1 ] 陈准   /   [ 2 ] 林夏   ·   [ ENTER ] 确认",
                        8.25, "muted", { textAlign = "center", whiteSpace = "normal" }),
                } },
        } }
end

---@param onSelect fun(heroId: string)
---@param compact boolean
---@return Panel
function HeroSelectUI.Preview(onSelect, compact)
    local _, height = UI.GetViewportSize()
    local artHeight = compact and math.min(300, math.max(220, height * 0.36)) or math.min(640, height - 110)
    local tiles = {}
    for _, heroId in ipairs({ "male", "female" }) do
        local id = heroId
        local hero = Heroes.Get(id)
        tiles[#tiles + 1] = UI.Panel { id = id .. "MenuPortrait", flexGrow = 1, flexBasis = 0, minWidth = 0,
            height = artHeight, pointerEvents = "box-only", onClick = function() onSelect(id) end, children = {
                HeroSelectUI.Portrait(id, "100%", artHeight - 50, id .. "MenuArt"),
                Skin.Card { width = compact and 118 or 156, height = 48, padding = { 10, 12 }, gap = 0,
                    backgroundSlice = { 6, 8, 6, 8 }, justifyContent = "center", alignItems = "center",
                    alignSelf = "center", pointerEvents = "none", children = {
                        Text(hero.name .. " / " .. (id == "female" and "02" or "01"), 10.5, Accent(id), {
                            width = "100%", height = 24, flexShrink = 0, fontWeight = "bold",
                            textAlign = "center", verticalAlign = "middle" }),
                    } },
            } }
    end
    return UI.Panel { id = "menuHeroPreview", width = "100%", height = artHeight, flexDirection = "row", gap = compact and 0 or 6,
        pointerEvents = "box-none", children = tiles }
end

return HeroSelectUI
