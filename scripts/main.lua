-- Based on scaffold-2d.lua: init → declarative UI tree → subscribed events.
local UI = require("urhox-libs/UI")
local Game = require("Game")
local Draw = require("Draw")
local CampaignUI = require("CampaignUI")
local Heroes = require("Heroes")
local HeroSelectUI = require("HeroSelectUI")
local MainMenuUI = require("MainMenuUI")
local Skin = require("UISkin")
local Audio = require("Audio")
local VisualScale = require("VisualScale")

local selectedHeroId = "male"
local game = Game.New(selectedHeroId)
game.selectedHeroId = selectedHeroId
---@type Panel?
local root = nil
---@type Panel?
local arena = nil
---@type Panel?
local overlay = nil
---@type Label?
local hpLabel = nil
---@type Label?
local levelLabel = nil
---@type Label?
local timerLabel = nil
---@type Label?
local statusLabel = nil
---@type Label?
local noticeLabel = nil
---@type Label?
local equipmentLabel = nil
---@type Label?
local bossLabel = nil
---@type Label?
local roomLabel = nil
---@type Label?
local coinLabel = nil
---@type ProgressBar?
local hpBar = nil
---@type ProgressBar?
local xpBar = nil
---@type ProgressBar?
local rageBar = nil
---@type ProgressBar?
local timeBar = nil
---@type ProgressBar?
local bossBar = nil
---@type Button?
local burstButton = nil
---@type Button?
local pauseButton = nil
---@type Button?
local routeButton = nil
local musicEnabled, sfxEnabled = true, true
local menuSettingsOpen = false
local hudTimer, lastMode, lastRevision = 0, "", -1
local lastWidth, lastHeight = 0, 0
local touchId = -1
local touchX, touchY, touchStartX, touchStartY = 0, 0, 0, 0
local COLOR = Skin.colors
local Label = Skin.Text
local Rule = Skin.Rule

local function AudioControls(compact)
    return UI.Panel { width = "100%", flexDirection = "row", gap = 8, children = {
        Skin.Button { id = "musicToggle", text = musicEnabled and "音乐：开启" or "音乐：关闭",
            variant = "secondary", flexGrow = 1, flexBasis = 0, minWidth = 0, height = compact and 36 or 42, fontSize = 9,
            onClick = function(self)
                musicEnabled = not musicEnabled
                Audio.SetMusicEnabled(musicEnabled)
                self:SetText(musicEnabled and "音乐：开启" or "音乐：关闭")
                print("[声音] 音乐开关=" .. tostring(musicEnabled))
            end },
        Skin.Button { id = "sfxToggle", text = sfxEnabled and "音效：开启" or "音效：关闭",
            variant = "secondary", flexGrow = 1, flexBasis = 0, minWidth = 0, height = compact and 36 or 42, fontSize = 9,
            onClick = function(self)
                sfxEnabled = not sfxEnabled
                Audio.SetSfxEnabled(sfxEnabled)
                self:SetText(sfxEnabled and "音效：开启" or "音效：关闭")
                print("[声音] 音效开关=" .. tostring(sfxEnabled))
            end },
    } }
end

local function SelectHero(heroId)
    if game.mode ~= "character" then return end
    local hero = Heroes.Get(heroId)
    selectedHeroId = hero.id
    game.selectedHeroId = selectedHeroId
    game.uiRevision = game.uiRevision + 1
    print("[选人] 选择 " .. hero.id .. " / " .. hero.name)
end

local function OpenCharacter(heroId)
    menuSettingsOpen = false
    if heroId then selectedHeroId = Heroes.Get(heroId).id end
    game.selectedHeroId = selectedHeroId
    game.mode = "character"
    game.uiRevision = game.uiRevision + 1
    touchId = -1
    print("[选人] 打开界面，当前角色=" .. selectedHeroId)
end

local function BackToMenu()
    game.mode = "menu"
    game.uiRevision = game.uiRevision + 1
    touchId = -1
end

local function ResetRun()
    local hero = Heroes.Get(selectedHeroId)
    game = Game.New(selectedHeroId)
    game.selectedHeroId = selectedHeroId
    Game.Start(game)
    touchId, lastMode, lastWidth = -1, "", 0
    print(string.format("[开局] %s / %s，精力=%d，速度=%d，伤害=%.0f%%",
        hero.id, hero.name, hero.maxHp, hero.speed, hero.damage * 100))
end

local function TogglePause()
    if game.mode == "playing" then game.mode = "paused"
    elseif game.mode == "paused" then game.mode = "playing" end
    touchId = -1
end

local function StatRow(left, right, color)
    return UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", gap = 10, children = {
        Label(left, 10.5, "muted"), Label(right, 10.5, color or "ink", { fontFamily = "mono" }),
    } }
end

local function EmployeeCard(compact)
    local hero = Heroes.Get(game.heroId)
    local viewportWidth = UI.GetViewportSize()
    local cardWidth = compact and math.max(180, math.floor((viewportWidth - 72) * 0.56)) or 388
    local portraitWidth = compact and 35 or 44
    -- Explicit border-box math prevents maxWidth auto-fix and keeps values 16px inside the frame.
    local contentWidth = cardWidth - 32 - portraitWidth - 10
    hpLabel = Label("130 / 130", 8.25, "pink", { id = "hudHPText", fontFamily = "mono",
        width = 78, flexShrink = 0, textAlign = "right" })
    levelLabel = Label("LV.01", 8.25, "teal", { id = "hudLevel", fontFamily = "mono",
        width = 46, flexShrink = 0, textAlign = "right" })
    hpBar = UI.ProgressBar { id = "hudHP", value = 1, height = 6, fillColor = COLOR.pink, pointerEvents = "none" }
    xpBar = UI.ProgressBar { id = "hudXP", value = 0, height = 4, fillColor = COLOR.teal, pointerEvents = "none" }
    rageBar = UI.ProgressBar { id = "hudRage", value = 0.65, height = 4, fillColor = COLOR.gold, pointerEvents = "none" }
    return Skin.Card { id = "employeeIdentity", width = cardWidth, flexGrow = 0, flexShrink = 0,
        height = compact and 86 or 88, paddingHorizontal = 16, paddingVertical = 12, gap = 10,
        flexDirection = "row", alignItems = "center", pointerEvents = "none", children = {
            UI.Panel { width = portraitWidth, height = 58, flexShrink = 0, children = {
                Skin.PortraitFrame { position = "absolute", top = 0, left = 0, right = 0, bottom = 0, backgroundSlice = { 6, 6, 6, 6 } },
                HeroSelectUI.Portrait(hero.id, portraitWidth, 58, "employeePortrait"),
            } },
            UI.Panel { width = contentWidth, flexShrink = 0, minWidth = 0, gap = 2, children = {
                UI.Panel { width = contentWidth, flexDirection = "row", justifyContent = "space-between", alignItems = "center", gap = 6, children = {
                    Label(hero.name, compact and 9.75 or 10.5, "ink", { id = "employeeName", fontWeight = "bold" }), levelLabel,
                } },
                UI.Panel { width = contentWidth, flexDirection = "row", justifyContent = "space-between", children = {
                    Label("精力", 8.25, "muted"), hpLabel,
                } }, hpBar,
                UI.Panel { width = contentWidth, flexDirection = "row", alignItems = "center", gap = 3, children = {
                    Label("EXP", 7.5, "teal", { width = 22, flexShrink = 0 }),
                    UI.Panel { flexGrow = 1, flexBasis = 0, minWidth = 0, children = { xpBar } },
                    Label("怒气", 7.5, "gold", { width = 24, flexShrink = 0 }),
                    UI.Panel { flexGrow = 1, flexBasis = 0, minWidth = 0, children = { rageBar } },
                } },
            } },
        } }
end

local function BuildUI()
    local width, height = UI.GetViewportSize()
    local compact = width < 700
    lastWidth, lastHeight = width, height
    timerLabel = Label("00:00", compact and 10.5 or 13.5, "ink", { id = "hudTimer", fontFamily = "mono" })
    roomLabel = Label("F1 / 打卡大厅", compact and 9 or 12, "ink", { id = "hudRoom", fontWeight = "bold", maxLines = 1 })
    statusLabel = Label("波次 1 / 3", 8.25, "teal", { id = "hudStatus", maxLines = 1 })
    coinLabel = Label("币 0", 9, "gold", { id = "hudCoins", fontFamily = "mono" })
    timeBar = UI.ProgressBar { id = "hudCampaignProgress", value = 0, height = 3, fillColor = COLOR.teal, pointerEvents = "none" }
    equipmentLabel = Label("键盘 Lv.1", 8.25, "lightMuted", { id = "hudEquipment", maxLines = 1 })
    pauseButton = Skin.Button { id = "pauseButton", text = "II", width = 38, height = 42, paddingHorizontal = 4, fontSize = 12, variant = "secondary", onClick = TogglePause }
    local header = UI.Panel { width = "100%", height = compact and 86 or 88, flexDirection = "row", gap = compact and 6 or 10,
        alignItems = "center", pointerEvents = "box-none", children = {
            EmployeeCard(compact),
            Skin.Card { flexGrow = 1, flexBasis = 0, minWidth = 0, height = "100%", padding = compact and 9 or 12, gap = 4, pointerEvents = "none", children = {
                UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", gap = 6, children = { roomLabel, timerLabel } },
                UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", gap = 6, children = { statusLabel, coinLabel } },
                timeBar,
            } }, pauseButton,
        } }
    arena = UI.Panel { id = "combatArena", width = "100%", height = "100%", pointerEvents = "none" }
    noticeLabel = Label("", 9, "cream", { id = "hudAnnouncement", position = "absolute",
        bottom = 8, left = "12%", right = "12%", textAlign = "center",
        backgroundColor = { 24, 43, 55, 213 }, padding = 6, whiteSpace = "normal" })
    bossLabel = Label("五分钟主管", 10.5, "cream", { textAlign = "center" })
    bossBar = UI.ProgressBar { value = 1, height = 6, fillColor = COLOR.pink }
    local body = UI.Panel { width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0, pointerEvents = "box-none", children = {
        arena,
        UI.Panel { id = "bossHud", position = "absolute", top = 8, left = "28%", right = "28%",
            gap = 3, visible = false, pointerEvents = "none", children = { bossLabel, bossBar } }, noticeLabel,
    } }
    routeButton = Skin.Button { id = "roomExitButton", text = "清怪后前进", width = compact and 154 or 184, height = 40,
        fontSize = 10.5, visible = false, onClick = function() Game.OpenRoute(game) end }
    burstButton = Skin.Button { id = "burstButton", text = "积攒怒气中", width = compact and 116 or 150, height = 42, fontSize = 10.5,
        onClick = function() Game.Burst(game) end }
    local footer = UI.Panel { width = "100%", height = 51, flexDirection = "row", alignItems = "center",
        justifyContent = "space-between", gap = 8, pointerEvents = "box-none", children = {
            UI.Panel { flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 2, pointerEvents = "box-none", children = {
                routeButton,
                Label(compact and "轻推走 / 拖远跑 / 自动攻击" or "WASD 跑动 / SHIFT 走 / P 暂停", 8.25, "lightMuted", { id = "movementHelp" }),
            } },
            UI.Panel { flexGrow = compact and 0 or 1, flexBasis = compact and "auto" or 0, minWidth = 0, visible = not compact,
                alignItems = "center", pointerEvents = "none", children = { equipmentLabel } },
            burstButton,
        } }
    local content = UI.SafeAreaView { width = "100%", height = "100%", nativeMenuInset = true, pointerEvents = "box-none", children = {
        UI.Panel { width = "100%", height = "100%", paddingHorizontal = compact and 8 or 14, paddingTop = 8,
            gap = 6, pointerEvents = "box-none", children = { header, body, footer } },
    } }
    overlay = UI.Panel { id = "gameOverlay", position = "absolute", top = 0, left = 0, width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center", pointerEvents = "auto" }
    -- Root must stay transparent: Draw renders the arena before the widget tree.
    root = UI.Panel { width = "100%", height = "100%", pointerEvents = "box-none", children = { content, overlay } }
    UI.SetRoot(root, true)
    lastMode = ""
    print(string.format("[界面] %dx%d；紧凑顶部员工卡，无右侧栏，战斗空间优先", math.floor(width), math.floor(height)))
end

local function StartCard()
    return MainMenuUI.Build(menuSettingsOpen, function() OpenCharacter() end,
        function()
            menuSettingsOpen = true
            game.uiRevision = game.uiRevision + 1
        end,
        function()
            menuSettingsOpen = false
            game.uiRevision = game.uiRevision + 1
        end, AudioControls)
end

local function UpgradeCard()
    local width, height = UI.GetViewportSize()
    local small = width < 700
    local cards = {}
    for index, choice in ipairs(game.choices) do
        local n = index
        cards[#cards + 1] = Skin.Card { width = small and "100%" or nil, flexGrow = small and 0 or 1,
            flexBasis = small and "auto" or 0, minWidth = 0, minHeight = small and 168 or 264, padding = small and 14 or 20,
            gap = 8, children = {
                Label("PERK / 0" .. index .. "   " .. choice.tag, 8.25, "muted", { fontFamily = "mono" }),
                Label(choice.title, 18, choice.color, { fontWeight = "bold", whiteSpace = "normal" }),
                Rule(), Label(choice.desc, 10.5, "muted", { whiteSpace = "normal", lineHeight = 1.5, minHeight = small and 36 or 66 }),
                UI.Panel { flexGrow = 1, minHeight = 0 },
                Skin.Button { id = "upgradeChoose" .. index, text = "选择  [ " .. index .. " ]", width = "100%", height = 42,
                    onClick = function() Game.Choose(game, n) end },
            } }
    end
    return Skin.Card { id = "upgradeScreen", width = math.max(1, math.min(width - 28, 920)),
        height = math.max(1, math.min(height - 28, small and 740 or 472)), padding = 0, gap = 0, children = {
            UI.ScrollView { id = "upgradeScroll", width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
                scrollY = true, scrollX = false, bounces = false, children = {
                    UI.Panel { width = "100%", padding = 22, gap = 14, children = {
                        Label(game.upgradeSource == "room" and "ROOM CLEAR / 区域奖励" or ("LEVEL UP / LV." .. game.level), 9, "teal", { fontFamily = "mono" }),
                        Label("少点内耗，多点本事", 22.5, "ink", { fontWeight = "bold", whiteSpace = "normal" }),
                        UI.Panel { width = "100%", flexDirection = small and "column" or "row", gap = 12, children = cards },
                        Label("选择一项强化 · 时间已暂停", 9, "muted", { textAlign = "center" }),
                    } },
                } },
        } }
end

local function ResultCard(won)
    local _, height = UI.GetViewportSize()
    local hero = Heroes.Get(game.heroId)
    return Skin.Card { width = "92%", maxWidth = 490, height = math.max(1, math.min(height - 28, 660)), padding = 0, gap = 0, children = {
        UI.ScrollView { id = "resultScroll", width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
            scrollX = false, scrollY = true, bounces = false, children = {
                UI.Panel { width = "100%", padding = 24, gap = 12, children = {
                    Label(won and "CLOCKED OUT / 下班凭证" or "TRY AGAIN / 明天也不加班", 9, won and "teal" or "pink", { textAlign = "center", fontFamily = "mono" }),
                    Label(won and "下班成功！" or "下班未遂", 30, won and "teal" or "pink", { textAlign = "center", fontWeight = "bold" }),
                    UI.Panel { width = "100%", height = 130, alignItems = "center", children = { HeroSelectUI.Portrait(hero.id, 110, 130) } },
                    Label(hero.name .. " · " .. hero.title, 12, hero.id == "female" and "pink" or "teal", { textAlign = "center" }),
                    Label(won and "今天，你的时间属于自己。" or "可以倒下，但别习惯加班。", 10.5, "ink", { textAlign = "center", whiteSpace = "normal" }), Rule(),
                    StatRow("本次奋战", string.format("%02d:%02d", math.floor(game.time / 60), math.floor(game.time % 60))),
                    StatRow("已拒绝的麻烦", tostring(game.kills), "gold"),
                    StatRow("已清理区域", tostring(game.roomsCleared), "teal"),
                    StatRow("已击败首领", game.bossesDefeated .. " / 3", "gold"),
                } },
            } },
        UI.Panel { width = "100%", paddingHorizontal = 24, paddingBottom = 20, paddingTop = 8, gap = 8, children = {
            Skin.Button { id = "heroReplay", text = "原角色重开 · " .. hero.name, width = "100%", height = 48, fontSize = 11, onClick = ResetRun },
            Skin.Button { id = "heroReselect", text = "重新选人", width = "100%", height = 44, variant = "secondary", onClick = function() OpenCharacter() end },
        } },
    } }
end

local function RefreshOverlay()
    if not overlay then return end
    overlay:ClearChildren()
    touchId = -1
    if game.mode == "playing" then overlay:Hide(); return end
    overlay:Show()
    overlay:SetStyle({ backgroundColor = game.mode == "menu" and { 0, 0, 0, 0 } or { 12, 23, 30, 210 } })
    if game.mode == "menu" then overlay:AddChild(StartCard()); return end
    local safe = UI.SafeAreaView { width = "100%", height = "100%", nativeMenuInset = true,
        alignItems = "center", justifyContent = "center", pointerEvents = "box-none" }
    overlay:AddChild(safe)
    if game.mode == "character" then safe:AddChild(HeroSelectUI.Build(selectedHeroId, SelectHero, ResetRun, BackToMenu))
    elseif game.mode == "upgrade" then safe:AddChild(UpgradeCard())
    elseif game.mode == "route" then safe:AddChild(CampaignUI.Route(game --[[@as CampaignUIState]]))
    elseif game.mode == "shop" then safe:AddChild(CampaignUI.Shop(game --[[@as CampaignUIState]]))
    elseif game.mode == "event" then safe:AddChild(CampaignUI.Event(game --[[@as CampaignUIState]]))
    elseif game.mode == "won" or game.mode == "lost" then safe:AddChild(ResultCard(game.mode == "won"))
    elseif game.mode == "paused" then
        safe:AddChild(Skin.Card { width = "90%", maxWidth = 400, padding = 28, gap = 18, children = {
            Label("BREAK TIME / 17:59", 9, "teal", { textAlign = "center", fontFamily = "mono" }),
            Label("工间休息", 27, "ink", { textAlign = "center", fontWeight = "bold" }), Rule(),
            Skin.Button { id = "pauseResume", text = "继续逃离  [ P ]", width = "100%", onClick = TogglePause },
            AudioControls(false),
        } })
    end
    print("[界面] 皮肤弹层=" .. game.mode)
end

local function UpdateHUD()
    local p = game.player
    if hpLabel then hpLabel:SetText(math.ceil(p.hp) .. " / " .. p.maxHp) end
    if hpBar then hpBar:SetValue(p.hp / p.maxHp) end
    if levelLabel then levelLabel:SetText(string.format("LV.%02d", game.level)) end
    if xpBar then xpBar:SetValue(game.xp / game.xpNeed) end
    if rageBar then rageBar:SetValue(game.rage / 100) end
    if timeBar then timeBar:SetValue(game.roomsCleared / 18) end
    if roomLabel then roomLabel:SetText("F" .. game.floor .. " / " .. game.room.name) end
    if coinLabel then coinLabel:SetText("币 " .. game.coins) end
    if routeButton then
        routeButton:SetVisible(game.mode == "playing" and game.roomCleared)
        routeButton:SetText(game.room.kind == "boss" and (game.floor == 3 and "下班！ [ E ]" or "进入下一层 [ E ]") or "选择下一区 [ E ]")
    end
    if timerLabel then timerLabel:SetText(string.format("%02d:%02d", math.floor(game.time / 60), math.floor(game.time % 60))) end
    if statusLabel then
        local text = game.room.kind == "boss" and game.bossName or ("波次 " .. game.wave .. "/" .. game.totalWaves .. " · 敌 " .. #game.enemies)
        if game.roomCleared then
            local exit = Game.GetExit(game)
            local dx, dy = exit.triggerX - p.x, exit.triggerY - p.y
            local direction = math.abs(dx) <= exit.radius and math.abs(dy) <= exit.radius and "门前"
                or (math.abs(dx) > math.abs(dy) and (dx > 0 and "向右 →" or "← 向左") or (dy > 0 and "向下 ↓" or "向上 ↑"))
            text = "出口 " .. direction .. " · E 前进"
        end
        statusLabel:SetText(text)
    end
    if noticeLabel then
        noticeLabel:SetVisible(game.mode == "playing" and game.announcementTime > 0)
        noticeLabel:SetText(game.announcement)
    end
    if burstButton then
        burstButton:SetText(game.rage >= 100 and "拒绝加班！" or "怒气 " .. math.floor(game.rage) .. "%")
        burstButton:SetDisabled(game.rage < 100 or game.mode ~= "playing")
    end
    if pauseButton then pauseButton:SetDisabled(game.mode ~= "playing" and game.mode ~= "paused") end
    if equipmentLabel then
        local text = "键盘 Lv." .. (1 + (game.upgrades.attack or 0))
        if game.stapler > 0 then text = text .. "  /  订书机 Lv." .. game.stapler end
        if game.coffee > 0 then text = text .. "  /  咖啡 Lv." .. game.coffee end
        equipmentLabel:SetText(text)
    end
    if root then
        local bossHud = root:FindById("bossHud")
        if bossHud then bossHud:SetVisible(game.bossSpawned and not game.bossDefeated and game.mode == "playing") end
        local movementHelp = root:FindById("movementHelp")
        if movementHelp then movementHelp:SetVisible(not game.roomCleared) end
    end
    if bossBar then bossBar:SetValue(game.bossHp / game.bossMaxHp) end
    if bossLabel then bossLabel:SetText(game.bossName .. (game.bossPhase == 1 and " / 怒气失控" or " / 区域首领")) end
end

function Start()
    graphics.windowTitle = "下班！别拦我"
    input.mouseMode = MM_ABSOLUTE
    local drawContext = Draw.Init()
    Skin.Init()
    Audio.Init()
    musicEnabled, sfxEnabled = Audio.GetMusicEnabled(), Audio.GetSfxEnabled()
    Game.Spawn(game, 1, 363, 323)
    Game.Spawn(game, 2, 698, 370)
    Game.Spawn(game, 3, 650, 561)
    Game.Spawn(game, 4, 119, 410)
    BuildUI()
    RefreshOverlay()
    UpdateHUD()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("InputFocus", "HandleInputFocus")
    SubscribeToEvent(drawContext, "NanoVGRender", "HandleOfficeRender")
    print("[启动] 立绘办公室UI就绪；单机模式，等待出勤")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = math.min(0.05, eventData:GetFloat("TimeStep"))
    local width, height = UI.GetViewportSize()
    if math.abs(width - lastWidth) > 1 or math.abs(height - lastHeight) > 1 then BuildUI() end
    if game.mode ~= lastMode or game.uiRevision ~= lastRevision then
        lastMode, lastRevision = game.mode, game.uiRevision
        RefreshOverlay()
        UpdateHUD()
    end
    local mx, my = 0, 0
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then mx = mx - 1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then mx = mx + 1 end
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then my = my - 1 end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then my = my + 1 end
    ---@type boolean?
    local walking = input:GetKeyDown(KEY_SHIFT) or input:GetKeyDown(KEY_LSHIFT) or input:GetKeyDown(KEY_RSHIFT)
    if touchId >= 0 then
        mx, my = (touchX - touchStartX) / 45, (touchY - touchStartY) / 45
        walking = nil -- Game chooses walk below 0.65 joystick magnitude, run above it.
    end
    Game.UpdateVisuals(game, dt)
    Game.Update(game, dt, mx, my, nil, walking)
    Audio.Update(game, dt)
    hudTimer = hudTimer - dt
    if hudTimer <= 0 then hudTimer = 0.09; UpdateHUD() end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    if eventData:GetBool("Repeat") then return end
    local key = eventData:GetInt("Key")
    if game.mode == "menu" and menuSettingsOpen then
        if key == KEY_ESCAPE then
            menuSettingsOpen = false
            game.uiRevision = game.uiRevision + 1
        end
        return
    end
    if game.mode == "character" then
        if key == KEY_1 then SelectHero("male")
        elseif key == KEY_2 then SelectHero("female")
        elseif key == KEY_RETURN then ResetRun()
        elseif key == KEY_ESCAPE then BackToMenu() end
        return
    end
    if game.mode == "upgrade" then
        if key == KEY_1 then Game.Choose(game, 1)
        elseif key == KEY_2 then Game.Choose(game, 2)
        elseif key == KEY_3 then Game.Choose(game, 3) end
        return
    end
    if game.mode == "route" then
        local selected = key == KEY_1 and 1 or (key == KEY_2 and 2 or 0)
        for order, nextId in ipairs(game.room.next) do
            if order == selected then Game.Travel(game, nextId); break end
        end
        return
    elseif game.mode == "event" then
        if key == KEY_1 then Game.ResolveEvent(game, 1)
        elseif key == KEY_2 then Game.ResolveEvent(game, 2)
        elseif key == KEY_3 then Game.ResolveEvent(game, 3) end
        return
    elseif game.mode == "shop" then
        if key == KEY_1 then Game.Buy(game, 1)
        elseif key == KEY_2 then Game.Buy(game, 2)
        elseif key == KEY_3 then Game.Buy(game, 3)
        elseif key == KEY_E or key == KEY_RETURN then Game.LeaveShop(game) end
        return
    end
    if key == KEY_E then Game.OpenRoute(game)
    elseif key == KEY_RETURN and game.mode == "menu" then OpenCharacter()
    elseif key == KEY_RETURN and (game.mode == "won" or game.mode == "lost") then ResetRun()
    elseif key == KEY_R and (game.mode == "won" or game.mode == "lost") then ResetRun()
    elseif key == KEY_C and (game.mode == "won" or game.mode == "lost") then OpenCharacter()
    elseif key == KEY_SPACE then Game.Burst(game)
    elseif key == KEY_P or key == KEY_ESCAPE then TogglePause() end
end

function HandleTouchBegin(eventType, eventData)
    if game.mode ~= "playing" or touchId >= 0 then return end
    local dpr = math.max(1, graphics:GetDPR())
    local x, y = eventData:GetInt("X") / dpr, eventData:GetInt("Y") / dpr
    if x > graphics:GetWidth() / dpr * 0.55 or y < 100 then return end
    touchId = eventData:GetInt("TouchID")
    touchX, touchY, touchStartX, touchStartY = x, y, x, y
end

function HandleTouchMove(eventType, eventData)
    if eventData:GetInt("TouchID") ~= touchId then return end
    local dpr = math.max(1, graphics:GetDPR())
    touchX, touchY = eventData:GetInt("X") / dpr, eventData:GetInt("Y") / dpr
end

function HandleTouchEnd(eventType, eventData)
    if eventData:GetInt("TouchID") == touchId then touchId = -1 end
end

function HandleInputFocus(eventType, eventData)
    if not eventData:GetBool("Focus") and game.mode == "playing" then game.mode = "paused"; touchId = -1 end
end

function HandleOfficeRender()
    if not arena then return end
    local layout = arena:GetAbsoluteLayout()
    if not VisualScale.IsPositiveSize(layout.w) or not VisualScale.IsPositiveSize(layout.h) then return end
    local uiWidth = UI.GetViewportSize()
    if not VisualScale.IsPositiveSize(uiWidth) then return end
    Draw.Render(game, layout, graphics:GetWidth() / uiWidth)
end

function Stop()
    UnsubscribeFromAllEvents()
    UI.Shutdown()
    Draw.Stop()
    Audio.Stop()
    print("[退出] 界面、绘制和声音已释放")
end
