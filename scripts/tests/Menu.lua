-- 实际main/HeroSelectUI按钮闭环回归；每阶段留足帧数让UI延迟重建。
-- 入口tests/Menu.lua，完整执行需要至少420帧；不作为正式入口。
local UI = require("urhox-libs/UI")
local Game = require("Game")
local Heroes = require("Heroes")
local newGame = Game.New
local live = newGame()
local constructors = 0
---@param heroId string?
Game.New = function(heroId)
    constructors = constructors + 1
    live = newGame(heroId)
    return live
end
require("main")
local originalUpdate = HandleUpdate
local tick, stage, passed = 0, 0, 0
local frozenTime, selectionConstructors = 0, 0
local frozenActionTime, frozenActionSerial, frozenLocomotionTime = 0, 0, 0

local function Check(value, message)
    assert(value, "[界面测试失败] " .. message)
    passed = passed + 1
    print("[界面测试通过] " .. message)
end

---@param widget Widget?
---@param text string
---@return Widget?
local function FindButton(widget, text)
    if not widget then return nil end
    if widget.props.text == text and widget.props.onClick then return widget end
    for _, child in ipairs(widget:GetChildren()) do
        local found = FindButton(child, text)
        if found then return found end
    end
    return nil
end

local function Click(text)
    local button = FindButton(UI.GetRoot(), text)
    Check(button ~= nil, "找到按钮：" .. text)
    if button then button.props.onClick(button) end
end

local function ClickId(id)
    local root = UI.GetRoot()
    local button = root and root:FindById(id)
    Check(button ~= nil and button.props.onClick ~= nil, "找到可操作控件：" .. id)
    if button then button.props.onClick(button) end
end

local function CheckHero(id, message)
    local hero = Heroes.Get(id)
    Check(live.heroId == id and live.player.hp == hero.maxHp and live.player.maxHp == hero.maxHp
        and live.player.speed == hero.speed and math.abs(live.damage - hero.damage) < 0.00001, message)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    -- 只隔离随机战斗伤害；模式切换、真实Game.Update和所有UI回调仍原样执行。
    if live.mode == "playing" then live.player.invuln = 99 end
    originalUpdate(eventType, eventData)
    tick = tick + 1
    if tick % 12 ~= 0 or stage >= 34 then return end
    stage = stage + 1
    if stage == 1 then
        Check(live.mode == "menu", "正式入口显示开始菜单")
        local menuRoot = UI.GetRoot()
        Check(menuRoot:FindById("menuComputer") ~= nil and menuRoot:FindById("menuHeroPreview") == nil,
            "主菜单是电脑屏幕且不显示男女立绘")
        local time = menuRoot:FindById("menuTimeBar"):GetAbsoluteLayout()
        local title = menuRoot:FindById("menuTitle"):GetAbsoluteLayout()
        local start = menuRoot:FindById("menuStart"):GetAbsoluteLayout()
        local settings = menuRoot:FindById("menuSettings"):GetAbsoluteLayout()
        Check(time.y + time.h <= title.y + 1 and title.y + title.h <= start.y + 1
            and start.y + start.h <= settings.y + 1, "电脑屏幕顺序为时间、标题、开始、设置")
        CheckHero("male", "默认角色完整男主属性")
        selectionConstructors = constructors
        ClickId("menuStart")
    elseif stage == 2 then
        Check(live.mode == "character" and constructors == selectionConstructors, "开始先进入选人而非直接开局")
        local selectRoot = UI.GetRoot()
        local maleCard = selectRoot:FindById("heroSelectMale"):GetAbsoluteLayout()
        local femaleCard = selectRoot:FindById("heroSelectFemale"):GetAbsoluteLayout()
        Check(math.abs(maleCard.h / maleCard.w - 1.5) < 0.01
            and math.abs(femaleCard.h / femaleCard.w - 1.5) < 0.01, "两张员工工牌始终保持2比3比例")
        local malePhoto = selectRoot:FindById("maleLargePortrait")
        local femalePhoto = selectRoot:FindById("femaleLargePortrait")
        Check(malePhoto.props.backgroundImage == "image/ui/male_headshot.png"
            and femalePhoto.props.backgroundImage == "image/ui/female_headshot.png", "工牌使用独立模型证件照而非原立绘截图")
        frozenTime = live.time
        ClickId("heroSelectFemale")
    elseif stage == 3 then
        Check(live.selectedHeroId == "female" and live.mode == "character"
            and live.time == frozenTime and constructors == selectionConstructors, "女主选择不提前创建/推进游戏")
        ClickId("heroBack")
    elseif stage == 4 then
        Check(live.mode == "menu" and constructors == selectionConstructors, "返回按钮安全回主菜单")
        ClickId("menuStart")
    elseif stage == 5 then
        Check(live.mode == "character" and live.selectedHeroId == "female", "返回重进保留未确认选择")
        ClickId("heroSelectMale")
    elseif stage == 6 then
        Check(live.selectedHeroId == "male" and live.mode == "character", "男主卡片可切换")
        ClickId("heroSelectFemale")
    elseif stage == 7 then
        Check(live.selectedHeroId == "female", "可再次切换女主")
        ClickId("heroConfirm")
        Check(live.mode == "playing" and constructors == selectionConstructors + 1, "确认后才创建所选角色新局")
        CheckHero("female", "确认女主真实90血156速度130%伤害")
    elseif stage == 8 then
        live.rage = 100
        Check(Game.Burst(live) and live.action.name == "burst" and live.action.time == 0, "UI暂停夹具启动真实爆发蓄力")
        Click("II")
        frozenTime = live.time
        frozenActionTime, frozenActionSerial, frozenLocomotionTime = live.action.time, live.action.serial, live.locomotion.time
    elseif stage == 9 then
        Check(live.mode == "paused" and live.time == frozenTime, "暂停按钮冻结游戏")
        Check(live.action.serial == frozenActionSerial and live.action.time == frozenActionTime
            and live.locomotion.time == frozenLocomotionTime and not live.actionTracks.burst.impactDone,
            "暂停UI也冻结真实爆发及locomotion，不因界面刷新越过命中")
        Click("继续逃离  [ P ]")
    elseif stage == 10 then
        Check(live.mode == "playing", "继续按钮恢复游戏")
        live.xp = live.xpNeed
    elseif stage == 11 then
        Check(live.mode == "upgrade", "经验满足后显示升级弹窗")
        Click("选择  [ 1 ]")
    elseif stage == 12 then
        Check(live.mode == "playing" and live.stapler == 1, "升级按钮生效并关闭弹窗")
        live.mode = "won"
    elseif stage == 13 then
        ClickId("heroReplay")
        Check(live.mode == "playing" and live.level == 1 and live.stapler == 0 and live.coins == 0, "胜利原角色重开清空构筑")
        CheckHero("female", "胜利重开保留女主并恢复女主满血")
    elseif stage == 14 then
        live.player.hp, live.mode = 0, "lost"
    elseif stage == 15 then
        ClickId("heroReplay")
        Check(live.mode == "playing" and live.floor == 1, "失败页原角色重开")
        CheckHero("female", "失败重开仍为女主90血而非旧100血")
    elseif stage == 16 then
        live.room.cleared, live.roomCleared, live.mode = true, true, "route"
    elseif stage == 17 then
        Check(live.mode == "route", "路线图正确显示")
        ClickId("routeTravel2")
    elseif stage == 18 then
        Check(live.roomIndex == 2 and live.mode == "playing" and live.heroId == "female", "路线按钮切换区域并保留女主")
        live.coins, live.player.hp = 100, 40
        Game.EnterRoom(live, 4)
    elseif stage == 19 then
        Click("买下这份补给")
        Check(live.coins == 70 and live.player.hp == 85, "商店按钮扣币并回血")
    elseif stage == 20 then
        Click("补给结束，离开商店  →")
        Check(live.roomCleared, "离开商店打开出口")
        Game.EnterRoom(live, 5)
    elseif stage == 21 then
        Click("选择这份礼物  →")
        Check(live.mode == "playing" and live.player.maxHp == 100 and live.heroId == "female", "事件使女主上限90增加10且保留角色")
    elseif stage == 22 then
        live.mode = "lost"
    elseif stage == 23 then
        selectionConstructors = constructors
        ClickId("heroReselect")
        Check(live.mode == "character" and constructors == selectionConstructors, "失败结果页可重选且未提前重开")
    elseif stage == 24 then
        ClickId("heroSelectMale")
    elseif stage == 25 then
        Check(live.selectedHeroId == "male", "结果重选可换男主")
        ClickId("heroConfirm")
        CheckHero("male", "重选确认实际男主130血188速度85%伤害")
    elseif stage == 26 then
        live.mode = "won"
    elseif stage == 27 then
        ClickId("heroReplay")
        Check(live.mode == "playing" and live.level == 1, "男主结果重开进入新局")
        CheckHero("male", "男主重开保留完整角色属性")
    elseif stage == 28 then
        live.mode = "won"
    elseif stage == 29 then
        ClickId("heroReselect")
        Check(live.mode == "character", "胜利结果页同样允许重选")
    elseif stage == 30 then
        ClickId("heroSelectFemale")
    elseif stage == 31 then
        ClickId("heroConfirm")
        CheckHero("female", "胜利重选可重新出勤女主")
    elseif stage == 32 then
        live.floor, live.bossesDefeated = 3, 3
        live.mode, live.time, live.kills, live.level = "won", 483, 168, 11
    elseif stage == 34 then
        print("[界面测试汇总] " .. passed .. "项断言全部通过；34阶段实际UI回调闭环完成")
    end
end
