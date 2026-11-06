-- 电脑菜单、音频设置与员工工牌的实际控件回归；截图停在选人页。
local UI = require("urhox-libs/UI")
require("main")
local update = HandleUpdate
local tick, passed = 0, 0

local function Check(value, message)
    assert(value, "[工位界面失败] " .. message)
    passed = passed + 1
    print("[工位界面通过] " .. message)
end

---@param id string
---@return Widget
local function Find(id)
    local widget = UI.GetRoot():FindById(id)
    assert(widget, "找不到控件：" .. id)
    return widget
end

local function Click(id)
    local widget = Find(id)
    assert(widget.props.onClick, "控件不可操作：" .. id)
    widget.props.onClick(widget)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    update(eventType, eventData)
    tick = tick + 1
    if tick == 12 then
        Check(UI.GetRoot():FindById("menuHeroPreview") == nil, "电脑菜单移除角色立绘")
        Click("menuSettings")
    elseif tick == 24 then
        Check(Find("menuSettingsTitle").props.text == "工位设置", "设置按钮进入声音设置")
        Check(UI.GetRoot():FindById("menuStart") == nil, "设置页不会误点开始游戏")
        Click("musicToggle")
        Click("sfxToggle")
    elseif tick == 36 then
        Check(Find("musicToggle").props.text == "音乐：关闭", "音乐可关闭")
        Check(Find("sfxToggle").props.text == "音效：关闭", "音效可关闭")
        Click("menuSettingsBack")
    elseif tick == 48 then
        Check(Find("menuTitle").props.text == "下班！别拦我", "设置返回电脑主屏幕")
        Click("menuStart")
    elseif tick == 60 then
        local male = Find("heroSelectMale"):GetAbsoluteLayout()
        local female = Find("heroSelectFemale"):GetAbsoluteLayout()
        print(string.format("[工牌布局] male=%.2fx%.2f female=%.2fx%.2f", male.w, male.h, female.w, female.h))
        Check(math.abs(male.h / male.w - 1.5) < 0.01
            and math.abs(female.h / female.w - 1.5) < 0.01, "工牌2比3等比，无挤压")
        Check(Find("maleLargePortrait").props.backgroundImage == "image/ui/male_headshot.png"
            and Find("femaleLargePortrait").props.backgroundImage == "image/ui/female_headshot.png",
            "使用重新生成的两张正脸免冠照")
        Click("heroSelectFemale")
    elseif tick == 72 then
        Check(Find("heroConfirm").props.text:find("林夏", 1, true) ~= nil, "点击女员工工牌更新确认角色")
        Check(Find("femaleSelectionState").props.text == "[ 已选择 · 本次出勤 ]", "女员工选中标签同步")
        local w = UI.GetViewportSize()
        if w < 760 then
            local scroll = Find("heroSelectScroll") --[[@as ScrollView]]
            scroll:ScrollToBottom()
        end
    elseif tick == 96 then
        local w, h = UI.GetViewportSize()
        local confirm = Find("heroConfirm"):GetAbsoluteLayout()
        Check(confirm.x >= 0 and confirm.y >= 0 and confirm.x + confirm.w <= w + 1
            and confirm.y + confirm.h <= h + 1, "滚动工牌时确认按钮仍在可视安全区")
        print("[工位界面汇总] " .. passed .. " 项全部通过")
    end
end
