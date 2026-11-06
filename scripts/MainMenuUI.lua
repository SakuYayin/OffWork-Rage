-- 电脑屏幕只负责呈现；开始、返回和音频状态仍由 main 管理。
local UI = require("urhox-libs/UI")
local Skin = require("UISkin")
local Text = Skin.Text
local MainMenuUI = {}

---@param settingsOpen boolean
---@param onStart fun()
---@param onSettings fun()
---@param onBack fun()
---@param audioControls fun(compact: boolean): Panel
---@return Panel
function MainMenuUI.Build(settingsOpen, onStart, onSettings, onBack, audioControls)
    local width, height = UI.GetViewportSize()
    local narrow = width < 760
    local screenWidth = math.max(1, math.min(width - 32, 1060))
    local screenHeight = math.max(360, math.min(height - 124, narrow and 670 or 570))
    local innerWidth = math.max(1, screenWidth - 88)
    local buttonWidth = math.min(320, innerWidth - 32)
    local content = {}
    if settingsOpen then
        content = {
            Text("SYSTEM / 声音设置", 9, "lightMuted", { fontFamily = "mono", textAlign = "center" }),
            Text("工位设置", narrow and 24 or 30, "cream", {
                id = "menuSettingsTitle", textAlign = "center", fontWeight = "bold" }),
            Text("音乐与音效可以独立开关", 10.5, "lightMuted", { textAlign = "center", whiteSpace = "normal" }),
            UI.Panel { width = math.min(430, innerWidth - 24), children = { audioControls(false) } },
            Skin.Button { id = "menuSettingsBack", text = "返回主菜单", width = buttonWidth,
                height = 48, variant = "secondary", onClick = onBack },
        }
    else
        content = {
            UI.Panel { id = "menuTimeBar", width = "88%", alignItems = "center", gap = 3,
                paddingVertical = 8, backgroundColor = { 16, 49, 57, 230 }, children = {
                    Text("距 离 下 班", 8.25, "lightMuted", { textAlign = "center" }),
                    Text("17:59", narrow and 27 or 33, "cream", {
                        id = "menuClock", fontFamily = "mono", textAlign = "center" }),
                } },
            Text("下班！别拦我", narrow and 24 or 36, "cream", {
                id = "menuTitle", width = "100%", fontWeight = "bold", textAlign = "center",
                whiteSpace = "normal", lineHeight = 1.25 }),
            Skin.Button { id = "menuStart", text = "开始游戏", width = buttonWidth,
                height = 52, fontSize = 13.5, onClick = onStart },
            Skin.Button { id = "menuSettings", text = "设置", width = buttonWidth,
                height = 48, fontSize = 12, variant = "secondary", onClick = onSettings },
        }
    end
    print(string.format("[电脑菜单] 屏幕 %.0fx%.0f，设置=%s，无主菜单人物立绘",
        screenWidth, screenHeight, tostring(settingsOpen)))
    return UI.Panel { id = "mainMenu", width = "100%", height = "100%", children = {
        Skin.Background { position = "absolute", top = 0, left = 0, right = 0, bottom = 0 },
        UI.Panel { position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 8, 18, 27, 155 }, pointerEvents = "none" },
        UI.SafeAreaView { width = "100%", height = "100%", nativeMenuInset = true, children = {
            UI.ScrollView { id = "menuScroll", width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
                scrollX = false, scrollY = true, showScrollbar = false, bounces = false, children = {
                    UI.Panel { width = "100%", minHeight = math.max(1, height - 32),
                        paddingVertical = 12, alignItems = "center", justifyContent = "center", children = {
                            UI.Panel { id = "menuComputer", width = screenWidth, height = screenHeight,
                                flexShrink = 0, backgroundImage = Skin.assets.computer,
                                backgroundFit = "sliced", backgroundSlice = { 37, 39, 44, 39 },
                                paddingTop = 42, paddingBottom = 52, paddingHorizontal = 44, children = {
                                    UI.ScrollView { id = "computerScreen", width = "100%", flexGrow = 1,
                                        flexBasis = 0, minHeight = 0, scrollX = false, scrollY = true,
                                        showScrollbar = false, bounces = false, children = {
                                            UI.Panel { id = "menuCopy", width = "100%",
                                                minHeight = math.max(310, screenHeight - 94), padding = 16,
                                                gap = narrow and 16 or 20, alignItems = "center",
                                                justifyContent = "center", children = content },
                                        } },
                                } },
                            UI.Panel { width = screenWidth * 0.58, height = math.min(110, screenWidth * 0.16),
                                marginTop = -2, backgroundImage = Skin.assets.computerStand,
                                backgroundFit = "contain", pointerEvents = "none" },
                        } },
                } },
        } },
    } }
end

return MainMenuUI
