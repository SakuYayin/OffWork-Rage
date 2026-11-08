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
local HudUI = require("HudUI")
local UpgradeUI = require("UpgradeUI")
local InterfaceScale = require("InterfaceScale")
local Endless = require("Endless")
local Leaderboard = require("Leaderboard")
local LeaderboardUI = require("LeaderboardUI")
local ResultsUI = require("ResultsUI")
local Loadout=require("Loadout")
-- engine.js 只注入 KEY_1..KEY_3；五选一升级卡需要 KEY_4/KEY_5，按 ASCII 码回退（只读检查确认缺失）。
local K1, K2, K3 = KEY_1 or 49, KEY_2 or 50, KEY_3 or 51
local K4, K5 = KEY_4 or 52, KEY_5 or 53
-- 闪避键：KEY_SHIFT 已被「慢走」占用、KEY_SPACE 是大招，所以闪避用 Z（engine.js 已注入 KEY_A..KEY_Z）。
local ZKey = KEY_Z or 90
-- 死亡钩子注入点：Game -> Endless 不能互相 require，main 是唯一装配者。
Game.deathHook = Endless.OnDeath
local hud = nil
local exitConfirm = false

local selectedHeroId = "male"
local pendingEndless=false
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
-- 最近一帧的移动输入（键盘或摇杆归一化前的原始值）：闪避方向要用它，静止时交给 Buffs 退回朝向。
local moveX, moveY = 0, 0
-- 前向声明：BuildUI / RefreshOverlay 里的闭包要先拿到这些名字，实体在文件后半段。
local OpenLeaderboard, LeaderboardPanel, EndlessResultCard
local NickPush, NickBack, SubmitEndlessScore
-- 昵称键盘的瞬时状态：StartEndless 要重置它们，所以必须声明在所有使用者之前。
local nickBusy = false
local nickMessage, nickMessageColor = "", "muted"
-- 只有玩家主动点过「提交」才允许把服务端错误显示成红字：
-- 后台排行榜轮询失败不该污染结算页首屏（曾经一进结算页就红字）。
local nickSubmitPending = false
-- engine.js 只回稳定错误码，中文文案在这里落地：字体子集只扫 Lua 源码，
-- 写在 JS 里的中文会变成方框。
local SCORE_ERROR_TEXT = {
    timeout = "提交超时，请检查网络后重试。",
    network_error = "网络连接失败，请检查网络后重试。",
    rate_limited = "操作太频繁，请稍后再试。",
    stale_ruleset = "排行榜规则已更新，请刷新页面后再试。",
    invalid_payload = "成绩数据无效，无法提交。",
    invalid_mode = "排行榜模式无效。",
    invalid_entry = "成绩数据无效，无法提交。",
    storage_unavailable = "排行榜暂时不可用，请稍后重试。",
    not_found = "排行榜服务未就绪，请稍后重试。",
    invalid_name = "昵称不符合要求，请换一个再试。",
    invalid_run_id = "本局成绩编号无效，请重新开局。",
    invalid_mode_or_hero = "成绩模式或角色无效，无法提交。",
    score_mismatch = "分数与战绩不匹配，本次成绩未记录。",
    run_id_conflict = "这局成绩已经提交过了。",
    length_required = "提交内容为空，请稍后重试。",
    body_too_large = "提交内容过大，无法记录。",
    unsupported_media_type = "提交格式不受支持，请稍后重试。",
}
local function ScoreErrorText(code)
    if type(code) ~= "string" or code == "" then return "提交失败，请稍后重试。" end
    return SCORE_ERROR_TEXT[code] or "提交失败，请稍后重试。"
end
local COLOR = Skin.colors
local Label = Skin.Text
local Rule = Skin.Rule

local function AudioControls(compact)
    local p=InterfaceScale.Get()
    return UI.Panel { width = "100%", flexDirection = "row", gap = 8, children = {
        Skin.Button { id = "musicToggle", text = musicEnabled and "音乐：开启" or "音乐：关闭",
            variant = "secondary", flexGrow = 1, flexBasis = 0, minWidth = 0, height = math.max(44,p.px(46)), fontSize = p.px(14),
            onClick = function(self)
                musicEnabled = not musicEnabled
                Audio.SetMusicEnabled(musicEnabled)
                self:SetText(musicEnabled and "音乐：开启" or "音乐：关闭")
                print("[声音] 音乐开关=" .. tostring(musicEnabled))
            end },
        Skin.Button { id = "sfxToggle", text = sfxEnabled and "音效：开启" or "音效：关闭",
            variant = "secondary", flexGrow = 1, flexBasis = 0, minWidth = 0, height = math.max(44,p.px(46)), fontSize = p.px(14),
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
    exitConfirm,menuSettingsOpen=false,false
    game = Game.New(selectedHeroId)
    game.selectedHeroId=selectedHeroId
    Game.Spawn(game,1,363,323);Game.Spawn(game,2,698,370)
    Game.Spawn(game,3,650,561);Game.Spawn(game,4,119,410)
    if input.ResetGameKeys then input:ResetGameKeys() end
    game.mode = "menu"
    game.uiRevision = game.uiRevision + 1
    touchId = -1
end

local function ResetRun()
    local hero = Heroes.Get(selectedHeroId)
    game = Game.New(selectedHeroId)
    game.leaderboardRunId=Leaderboard.NewRunId and Leaderboard.NewRunId()or nil
    nickBusy=false;nickMessage,nickMessageColor="","muted"
    exitConfirm=false
    if input.ResetGameKeys then input:ResetGameKeys() end
    game.selectedHeroId = selectedHeroId
    Game.Start(game)
    touchId, lastMode, lastWidth = -1, "", 0
    print(string.format("[开局] %s / %s，精力=%d，速度=%d，伤害=%.0f%%",
        hero.id, hero.name, hero.maxHp, hero.speed, hero.damage * 100))
end

local function TogglePause()
    if game.mode == "playing" then game.mode = "paused"
    elseif game.mode == "paused" then game.mode = "playing" end
    exitConfirm=false
    touchId = -1
end

local function StatRow(left, right, color)
    return UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", gap = 10, children = {
        Label(left, 14, "muted"), Label(right, 14, color or "ink", { fontFamily = "mono" }),
    } }
end

-- 闪避（「闪人」增益）：方向取当前移动输入；静止时 Game.Dash 会退回角色朝向。
-- 音效用 Audio 表里一直没人调用的 charge（跑动脚步），去重后入 audioQueue（上限 8 条，与 FufuCombat 同规则）。
local function TriggerDash()
    if not Game.Dash(game, moveX, moveY) then return end
    local queue = game.audioQueue
    if not queue then queue = {}; game.audioQueue = queue end
    for _, s in ipairs(queue) do if s == "charge" then return end end
    if #queue < 8 then queue[#queue + 1] = "charge" end
end

local function BuildUI()
    local width,height=UI.GetViewportSize()
    lastWidth,lastHeight=width,height
    hud=HudUI.Build(game,TogglePause,function()Game.Burst(game)end,
        -- HudUI 的按钮闭包捕获的是 Build 时的 game 值，无尽开局后 game 已被替换成新对象，
        -- 所以这里必须放一个动态分发器，而不是直接绑 Game.OpenRoute。
        function() if (game.endless ~= nil) then OpenLeaderboard() else Game.OpenRoute(game) end end,
        function()OpenLeaderboard()end,
        function()TriggerDash()end)
    hpLabel,levelLabel,timerLabel,statusLabel,noticeLabel=hud.hpLabel,hud.levelLabel,hud.timerLabel,hud.statusLabel,hud.noticeLabel
    hpBar,xpBar,rageBar,timeBar=hud.hpBar,hud.xpBar,hud.rageBar,hud.timeBar
    roomLabel,coinLabel,bossLabel,bossBar=hud.roomLabel,hud.coinLabel,hud.bossLabel,hud.bossBar
    pauseButton,burstButton,routeButton=hud.pauseButton,hud.burstButton,hud.routeButton
    arena=UI.Panel{id="combatArena",position="absolute",left=0,top=0,width="100%",height="100%",pointerEvents="none"}
    overlay=UI.Panel{id="gameOverlay",position="absolute",left=0,top=0,width="100%",height="100%",
        alignItems="center",justifyContent="center",pointerEvents="auto"}
    root=UI.Panel{id="officeRoot",width="100%",height="100%",pointerEvents="box-none",children={arena,hud.layer,overlay}}
    UI.SetRoot(root,true)
    lastMode=""
end

--- 无尽模式：从主菜单直接开一局「加班无尽」。不进选人流程，沿用当前角色。
local function StartEndless()
    local hero = Heroes.Get(selectedHeroId)
    game = Game.New(selectedHeroId)
    game.leaderboardRunId=Leaderboard.NewRunId and Leaderboard.NewRunId()or nil
    game.selectedHeroId = selectedHeroId
    Endless.Start(game)
    -- 结算态字段每次开局重置，否则第二局会带着上一局的提交状态。
    local savedName = Leaderboard.GetName()
    game.nickDraft = savedName
    game.scoreSubmitted, game.scoreRank = false, 0
    game.returnMode = nil
    nickMessage, nickMessageColor = "", "muted"
    nickSubmitPending = false
    exitConfirm, menuSettingsOpen = false, false
    if input.ResetGameKeys then input:ResetGameKeys() end
    touchId, lastMode, lastWidth = -1, "", 0
    game.uiRevision = game.uiRevision + 1
    print(string.format("[无尽] 开局 %s / %s，精力=%d", hero.id, hero.name, hero.maxHp))
end
local menuOnEndless = function()pendingEndless=true;OpenCharacter()end
local function StartCard()
    return MainMenuUI.Build(menuSettingsOpen, function() pendingEndless=false;OpenCharacter() end,
        function()
            menuSettingsOpen = true
            game.uiRevision = game.uiRevision + 1
        end,
        function()
            menuSettingsOpen = false
            game.uiRevision = game.uiRevision + 1
        end, AudioControls, menuOnEndless, function()OpenLeaderboard()end)
end

local function UpgradeCard() return UpgradeUI.Build(game) end

-- ------------------------------------------------------------------ 排行榜
-- Native text input keeps the draft intact while IME composition is active.
local function ScoreEntry()
 if game.scoreEntry then return game.scoreEntry end
 local endless=game.endless~=nil
 local r=endless and(game.endless.result or Endless.OnDeath(game))or{
  wave=game.roomsCleared or 0,boss=game.bossesDefeated or 0,level=game.level,kills=game.kills,time=math.floor(game.time)}
 r.time=math.floor(r.time or 0);r.score=Endless.Score(r.wave,r.kills,r.level,r.boss,r.time)
 game.leaderboardRunId=game.leaderboardRunId or(Leaderboard.NewRunId and Leaderboard.NewRunId()or tostring(os.time()))
 game.scoreEntry={mode=endless and"endless"or"campaign",version="office-expansion-v3",hero=game.heroId,run_id=game.leaderboardRunId,
  wave=r.wave,boss=r.boss,level=r.level,kills=r.kills,time=r.time,score=r.score}
 return game.scoreEntry
end
function SubmitEndlessScore()
 if game.scoreSubmitted or nickBusy then return end
 local draft=(game.nickDraft or""):gsub("^%s+",""):gsub("%s+$","")
 if not Leaderboard.ValidName(draft)then nickMessage,nickMessageColor="请输入昵称，昵称不能只有空格或控制字符。","pink";game.uiRevision=game.uiRevision+1;return end
 game.nickDraft=draft
 local entry=ScoreEntry();entry.name=draft
 Leaderboard.SetName(draft)
 if Leaderboard.SubmitAsync then
  nickBusy=Leaderboard.SubmitAsync(entry);nickSubmitPending=nickBusy
  nickMessage,nickMessageColor=nickBusy and"正在提交成绩…"or"暂时无法提交，请稍后重试。",nickBusy and"muted"or"pink"
 else
  local rank=Leaderboard.Store.Submit(entry);game.scoreSubmitted=true;game.scoreRank=rank
  nickMessage,nickMessageColor=rank and rank>0 and("已记录 · 第 "..rank.." 名")or"成绩已记录","teal"
 end
 game.uiRevision=game.uiRevision+1
end
local function BuildResult(won)
 local entry=ScoreEntry();local hero=Heroes.Get(game.heroId)
 if game.nickDraft==nil then game.nickDraft=Leaderboard.GetName()end
 return ResultsUI.Build{
  title=game.endless and"本次加班成绩"or(won and"下班成功！"or"下班未遂"),
  subtitle=hero.name.." · "..(game.endless and"无尽模式"or"战役模式"),
  stats={{game.endless and"坚持波次"or"清理区域",entry.wave},{"击破首领",entry.boss},{"等级","L"..entry.level},{"击退麻烦",entry.kills},
   {"奋战时间",string.format("%02d:%02d",math.floor(entry.time/60),math.floor(entry.time%60))}},
  score=entry.score,name=game.nickDraft or"",submitted=game.scoreSubmitted==true,busy=nickBusy,message=nickMessage,error=nickMessageColor=="pink",
  againId=game.endless and"endlessAgain"or"heroReplay",
  onNameChange=function(_,value)game.nickDraft=value end,onSubmit=SubmitEndlessScore,
  onLeaderboard=function()OpenLeaderboard()end,onAgain=function()if game.endless then StartEndless()else ResetRun()end end,onMenu=BackToMenu
 }
end
function EndlessResultCard()return BuildResult(false)end

--- 排行榜面板
function LeaderboardPanel()
    local entries = Leaderboard.Store.FetchTop(10)
    return LeaderboardUI.Build {
        entries = entries,
        myName = Leaderboard.GetName(),
        myScore = game.scoreEntry and game.scoreEntry.score or nil,
        mode = Leaderboard.MODE,
        syncing = nickBusy or game.leaderboardBusy,
        onClose = function()
            local back = game.returnMode
            if back ~= "endlessResult" and back ~= "paused" and back ~= "won" and back ~= "lost" then back = "menu" end
            game.returnMode = nil
            game.mode = back
            game.uiRevision = game.uiRevision + 1
        end,
        scope=game.leaderboardMode or"endless",
        onMode=function(mode)game.leaderboardMode=mode;if Leaderboard.Refresh then Leaderboard.Refresh(mode)end;game.uiRevision=game.uiRevision+1 end,
        onRefresh = function() if Leaderboard.Refresh then Leaderboard.Refresh(game.leaderboardMode or"endless")end;game.uiRevision = game.uiRevision + 1 end,
        onClear = function()
            Leaderboard.Store.Clear()
            nickMessage, nickMessageColor = "本地记录已清空", "muted"
            game.uiRevision = game.uiRevision + 1
        end,
    }
end

function OpenLeaderboard()
    if game.mode ~= "leaderboard" then game.returnMode = game.mode end
    game.leaderboardMode=game.endless and"endless"or((game.mode=="won"or game.mode=="lost")and"campaign"or(game.leaderboardMode or"endless"))
    if Leaderboard.Refresh then Leaderboard.Refresh(game.leaderboardMode)end
    game.mode = "leaderboard"
    game.uiRevision = game.uiRevision + 1
    print("[排行榜] 打开，MODE=" .. tostring(Leaderboard.MODE))
end

local function ResultCard(won)return BuildResult(won)end

local function RefreshOverlay()
    if not overlay then return end
    overlay:ClearChildren()
    touchId = -1
    if game.mode == "playing" then overlay:Hide(); return end
    overlay:Show()
    local clearBg = (game.mode == "menu" and not menuSettingsOpen) or game.mode == "leaderboard"
    overlay:SetStyle({ backgroundColor = clearBg and { 0, 0, 0, 0 } or { 17, 26, 48, 220 } })
    if game.mode == "menu" then overlay:AddChild(StartCard()); return end
    local safe = UI.SafeAreaView { width = "100%", height = "100%", nativeMenuInset = true,
        alignItems = "center", justifyContent = "center", pointerEvents = "box-none" }
    overlay:AddChild(safe)
    if game.mode == "character" then safe:AddChild(HeroSelectUI.Build(selectedHeroId, SelectHero, function()if pendingEndless then StartEndless()else ResetRun()end end, BackToMenu))
    elseif game.mode == "upgrade" then safe:AddChild(UpgradeCard())
    elseif game.mode == "route" then safe:AddChild(CampaignUI.Route(game --[[@as CampaignUIState]]))
    elseif game.mode == "shop" then safe:AddChild(CampaignUI.Shop(game --[[@as CampaignUIState]]))
    elseif game.mode == "event" then safe:AddChild(CampaignUI.Event(game --[[@as CampaignUIState]]))
    elseif game.mode == "won" or game.mode == "lost" then safe:AddChild(ResultCard(game.mode == "won"))
    elseif game.mode == "endlessResult" then
        safe:AddChild(EndlessResultCard())
    elseif game.mode == "leaderboard" then safe:AddChild(LeaderboardPanel())
    elseif game.mode == "paused" then
        local p=InterfaceScale.Get();local S=p.px
        if exitConfirm then
            safe:AddChild(UI.ScrollView{id="exitConfirm",className="game-panel pause-panel pause-scroll",width=math.min(p.w-32,S(480)),scrollY=true,children={UI.Panel{className="pause-content",width="100%",padding=S(28),gap=S(20),children={
                Label("这次先到这里？",14,"yellow"),Label("要结束本局吗？",27,"cream"),
                Label("返回主菜单后，这次突围会结束。",15,"lightMuted"),
                UI.Panel{width="100%",flexDirection="row",gap=S(12),children={
                    Skin.Button{id="exitCancel",text="继续这局",variant="secondary",flexGrow=1,flexBasis=0,minWidth=0,
                        onClick=function()exitConfirm=false;game.uiRevision=game.uiRevision+1 end},
                    Skin.Button{id="exitConfirmMenu",text="返回主菜单",flexGrow=1,flexBasis=0,minWidth=0,onClick=BackToMenu}
                }}
            }}}})
        else
            local pauseKids = {
                Label("暂时离开工位",13,"yellow",{textAlign="center"}),Label("歇口气，再下班。",27,"cream",{textAlign="center"}),
                Label("办公室安静了，时间也停下了。",14,"lightMuted",{textAlign="center"}),
                Skin.Button{id="pauseResume",text="继续突围  [ Esc ]",width="100%",onClick=TogglePause},AudioControls(false),
                Skin.Button{id="pauseBackToMenu",text="回到主菜单  ↗",width="100%",variant="secondary",onClick=function()exitConfirm=true;game.uiRevision=game.uiRevision+1 end}
            }
            if (game.endless ~= nil) then
                pauseKids[#pauseKids+1]=Skin.Button{id="pauseLeaderboard",text="查看加班排行榜  ★",width="100%",variant="secondary",onClick=function()OpenLeaderboard()end}
                pauseKids[#pauseKids+1]=Skin.Button{id="pauseCashOut",text="结算并退出本局",width="100%",variant="secondary",onClick=function()
                    Endless.OnDeath(game)
                    game.mode="endlessResult"
                    game.uiRevision=game.uiRevision+1
                end}
            else
                pauseKids[#pauseKids+1]=Label("返回主菜单将结束本局",12,"lightMuted",{textAlign="center"})
            end
            safe:AddChild(UI.ScrollView{id="pauseScreen",className="game-panel pause-panel pause-scroll",width=math.min(p.w-32,S(430)),scrollY=true,children={UI.Panel{className="pause-content",width="100%",padding=S(p.landscape and 20 or 30),gap=S(p.landscape and 12 or 18),children=pauseKids}}})
        end
    end
    print("[界面] 皮肤弹层=" .. game.mode)
end

-- 注意：Endless.OnDeath 会把 g.endless.active 置 false，但结算/排行榜界面仍属无尽局，
-- 所以这里的判定统一用「有没有 g.endless」这个表本身，不用 active（Game.lua 里才用 active）。
local function UpdateHUD()
    if hud then HudUI.Update(hud,game) end
    -- 无尽结算/排行榜时 game.endless.result 已定稿，HUD 仍在后台，别让血条跟着旧值抖
    local p = game.player
    if hpLabel then hpLabel:SetText(math.ceil(p.hp) .. " / " .. p.maxHp) end
    if hpBar then hpBar:SetValue(p.hp / p.maxHp) end
    if levelLabel then levelLabel:SetText(string.format("LV.%02d", game.level)) end
    if xpBar then xpBar:SetValue(game.xp / game.xpNeed) end
    if rageBar then rageBar:SetValue(game.rage / 100) end
    if timeBar then
        if (game.endless ~= nil) then
            -- 无尽：波次进度条=本波已清理比例（预算+同屏合计为分母）
            local e = game.endless
            local total = Endless.Count(e.wave)
            local alive = #game.enemies + (e.budget or 0)
            if e.phase == "boss" or e.phase == "bossIntro" then
                timeBar:SetValue(game.bossMaxHp > 0 and (game.bossHp / game.bossMaxHp) or 0)
            elseif alive <= 0 or total <= 0 then
                timeBar:SetValue(1)
            else
                timeBar:SetValue(1 - math.min(1, alive / total))
            end
        else
            -- 分母必须读实际房数：程序化地牢是 8/10/12/14 间，写死 18 会让进度条永远到不了满格。
            timeBar:SetValue(math.min(1, game.roomsCleared / math.max(1, #(game.rooms or {}))))
        end
    end
    if roomLabel then
        if (game.endless ~= nil) then
            roomLabel:SetText("无尽工位 / 第 " .. game.endless.wave .. " 波")
        else
            roomLabel:SetText("F" .. game.floor .. " / " .. game.room.name)
        end
    end
    if coinLabel then coinLabel:SetText(tostring(game.coins)) end
    if routeButton then
        if (game.endless ~= nil) then
            -- 无尽没有出口，这个按钮永不出现；排行榜入口收进暂停面板，避免压住战场
            routeButton:SetVisible(false)
        else
            routeButton:SetVisible(game.mode == "playing" and game.roomCleared)
            routeButton:SetText(game.room.kind == "boss" and (game.floor == 3 and "下班！ [ E ]" or "进入下一层 [ E ]") or "选择下一区 [ E ]")
        end
    end
    if timerLabel then timerLabel:SetText(string.format("%02d:%02d", math.floor(game.time / 60), math.floor(game.time % 60))) end
    if statusLabel then
        local text
        if (game.endless ~= nil) then
            local e = game.endless
            if e.phase == "warmup" then
                text = "准备迎接加班潮…"
            elseif e.phase == "breather" then
                text = "喘息中 · 下一波即将来袭"
            elseif e.phase == "bossIntro" then
                text = "首领正在靠近…"
            elseif e.phase == "boss" then
                text = "首领战 · " .. tostring(game.bossName)
            else
                text = "第 " .. e.wave .. " 波 · 还剩 " .. (#game.enemies + (e.budget or 0)) .. " 个麻烦"
            end
        elseif game.room.kind == "boss" then
            text = "最后一关，打完下班！"
        elseif game.wave == 0 then
            text = "准备突围"
        else
            text = "第 " .. game.wave .. "/" .. game.totalWaves .. " 波 · 还有 " .. #game.enemies .. " 个麻烦"
        end
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
        if game.heroId=="fufu"then burstButton:SetDisabled(not require("FufuCombat").CanSummon(game))
        else burstButton:SetDisabled(game.rage < 100 or game.mode ~= "playing")end
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
        -- 剩余怪物数：元素由 HudUI 建（id=hudEnemiesLeft），文案在这里填。
        -- 元素还没建出来时静默跳过，不影响其它 HUD。
        local enemiesLeft = root:FindById("hudEnemiesLeft")
        if enemiesLeft then
            if game.mode ~= "playing" then
                enemiesLeft:SetVisible(false)
            else
                -- 无尽模式分批刷怪，未刷出的配额在 e.budget 里，必须一起算进「剩余」。
                local remaining = #game.enemies
                local e = game.endless
                if e ~= nil and e.phase == "fighting" then remaining = remaining + (e.budget or 0) end
                enemiesLeft:SetVisible(true)
                enemiesLeft:SetText("剩余 " .. remaining .. " 个怪物")
            end
        end
        local movementHelp = root:FindById("movementHelp")
        local profile=InterfaceScale.Get()
        if movementHelp then movementHelp:SetVisible(not game.roomCleared and not profile.portrait and not profile.landscape) end
    end
    if bossBar then bossBar:SetValue(game.bossHp / game.bossMaxHp) end
    if bossLabel then bossLabel:SetText(game.bossName .. (game.bossPhase == 1 and " / 怒气失控" or " / 区域首领")) end
end

function Start()
    graphics.windowTitle = "下班！别挡我"
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
    if Leaderboard.Poll then
        local changed,state,rank,err=Leaderboard.Poll()
        if changed then
            nickBusy=state=="submitting";game.leaderboardBusy=state=="loading" or state=="submitting"
            if state=="success"then game.scoreSubmitted=true;game.scoreRank=rank;nickSubmitPending=false
                nickMessage,nickMessageColor=rank and rank>0 and("已上榜 · 第 "..rank.." 名")or"成绩已记录","teal"
            elseif state=="error"then
                -- 轮询（ScoreRefresh）失败也会走到这里，那只是后台刷新失败，
                -- 不该在结算页显示成「提交失败」。只有提交请求的失败才提示。
                if nickSubmitPending then
                    nickSubmitPending=false
                    nickMessage,nickMessageColor=ScoreErrorText(err),"pink"
                end
            end
            game.uiRevision=game.uiRevision+1
        end
    end
    local width, height = UI.GetViewportSize()
    if ((not UI.IsKeyboardOpen or not UI.IsKeyboardOpen())and(math.abs(width - lastWidth) > 1 or math.abs(height - lastHeight) > 1))
        or(hud and hud.loadoutKey~=table.concat(Loadout.List(game),","))then BuildUI()end
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
    moveX, moveY = mx, my -- 闪避方向要用本帧最终输入（摇杆覆盖键盘之后）。
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
    -- R8：无尽结算与排行榜必须先接管，否则 RETURN/ESC 会落到下面的重开分支。
    if game.mode == "endlessResult" or game.mode=="won" or game.mode=="lost" then
        if key==KEY_ESCAPE then BackToMenu()end
        return
    end
    if game.mode == "leaderboard" then
        if key == KEY_ESCAPE or key == KEY_RETURN then
            local back = game.returnMode
            if back ~= "endlessResult" and back ~= "paused" and back ~= "won" and back ~= "lost" then back = "menu" end
            game.returnMode = nil
            game.mode = back
            game.uiRevision = game.uiRevision + 1
        elseif key == KEY_R then
            Leaderboard.Store.Clear()
            game.uiRevision = game.uiRevision + 1
        end
        return
    end
    if game.mode=="paused" and exitConfirm then
        if key==KEY_ESCAPE then exitConfirm=false;game.uiRevision=game.uiRevision+1
        elseif key==KEY_RETURN then BackToMenu()end
        return
    end
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
        elseif key == KEY_3 then SelectHero("intern")
        elseif key == K4 then SelectHero("programmer")
        elseif key == K5 then SelectHero("fufu")
        elseif key == KEY_RETURN then if pendingEndless then StartEndless()else ResetRun()end
        elseif key == KEY_ESCAPE then BackToMenu() end
        return
    end
    if game.mode == "upgrade" then
        local keys = { K1, K2, K3, K4, K5 }
        for i = 1, math.min(#keys, #(game.choices or {})) do
            if key == keys[i] then UpgradeUI.SelectIndex(game, i); break end
        end
        if key==KEY_RETURN then UpgradeUI.Confirm(game)end
        if key==KEY_R then Game.RerollChoices(game)end
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
        elseif key == KEY_3 then Game.ResolveEvent(game, 3)
        elseif key == KEY_R then Game.RerollEvent(game) end
        return
    elseif game.mode == "shop" then
        -- 数字键沿用旧语义：选中并直接买下（probe-final.html 的 Digit1 买 + KeyE 离开是红线）。
        local keys = { K1, K2, K3, K4, K5 }
        for i = 1, math.min(#keys, #(game.shopItems or {})) do
            if key == keys[i] then Game.Buy(game, i); break end
        end
        if key == KEY_R then Game.RerollShop(game)
        elseif key == KEY_E or key == KEY_RETURN then Game.LeaveShop(game) end
        return
    end
    if key == KEY_E then Game.OpenRoute(game)
    elseif key == KEY_RETURN and game.mode == "menu" then OpenCharacter()
    elseif key == KEY_RETURN and (game.mode == "won" or game.mode == "lost") then ResetRun()
    elseif key == KEY_R and (game.mode == "won" or game.mode == "lost") then ResetRun()
    elseif key == KEY_C and (game.mode == "won" or game.mode == "lost") then OpenCharacter()
    elseif key == ZKey and game.mode == "playing" then TriggerDash()
    elseif key == KEY_SPACE then Game.Burst(game)
    elseif key == KEY_P or key == KEY_ESCAPE then TogglePause() end
end

-- 摇杆手指独立跟踪：只认领「第一根落在左 55%、y>=100」的手指，之后只处理这一根的
-- Move/End。其它手指（右手点大招按钮、双指乱按）的事件在这里全部安全忽略，
-- 既不会抢走摇杆，也不会因为第二根手指而把摇杆松掉。
local function JoystickKnob()
    return root and root:FindById("joystickKnob")
end

local function ResetJoystick()
    touchId = -1
    local knob = JoystickKnob()
    if knob then knob:SetStyle({left=24,top=24})end
end

function HandleTouchBegin(eventType, eventData)
    if game.mode ~= "playing" then return end
    local id = eventData:GetInt("TouchID")
    -- 摇杆已经被别的手指占住：这根手指属于按钮区，直接放过（DOM 按钮自己会收到事件）。
    if touchId >= 0 then return end
    local dpr = math.max(1, graphics:GetDPR())
    local x, y = eventData:GetInt("X") / dpr, eventData:GetInt("Y") / dpr
    if x > graphics:GetWidth() / dpr * 0.55 or y < 100 then return end
    touchId = id
    touchX, touchY, touchStartX, touchStartY = x, y, x, y
end

function HandleTouchMove(eventType, eventData)
    if touchId < 0 or eventData:GetInt("TouchID") ~= touchId then return end
    local dpr = math.max(1, graphics:GetDPR())
    touchX, touchY = eventData:GetInt("X") / dpr, eventData:GetInt("Y") / dpr
    local knob=JoystickKnob()
    if knob then
        local dx,dy=touchX-touchStartX,touchY-touchStartY
        local length=math.max(1,math.sqrt(dx*dx+dy*dy)/24)
        knob:SetStyle({left=24+dx/length,top=24+dy/length})
    end
end

function HandleTouchEnd(eventType, eventData)
    if touchId < 0 or eventData:GetInt("TouchID") ~= touchId then return end
    ResetJoystick()
end

function HandleInputFocus(eventType, eventData)
    if not eventData:GetBool("Focus") and input.ResetGameKeys then input:ResetGameKeys() end
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
