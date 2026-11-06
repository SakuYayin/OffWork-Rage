-- 真实渲染回归：注入未就绪布局，验证无效帧不进入NanoVG，恢复后继续绘制。
local UI = require("urhox-libs/UI")
local Draw = require("Draw")
local Game = require("Game")
local VisualScale = require("VisualScale")
local ScaleTests = require("tests.VisualScaleRules")
require("main")
local originalStart, originalRender = Start, HandleOfficeRender
local phase, passed = 0, 0
local testGame = Game.New("male")

local function Check(value, message)
    assert(value, "[镜头回归失败] " .. message)
    passed = passed + 1
end

function Start()
    originalStart()
    local count = ScaleTests.Run()
    print("[镜头回归] 尺度回归通过：" .. count)
end

function HandleOfficeRender()
    local root = UI.GetRoot()
    local arena = root and root:FindById("combatArena")
    if not arena then return end
    local layout = arena:GetAbsoluteLayout()
    if not VisualScale.IsPositiveSize(layout.w) or not VisualScale.IsPositiveSize(layout.h) then
        originalRender()
        return
    end
    if phase >= 12 then originalRender(); return end
    phase = phase + 1
    local oldBegin, oldEnd = nvgBeginFrame, nvgEndFrame
    local begins, ends = 0, 0
    nvgBeginFrame = function(context, width, height, dpr)
        Check(VisualScale.IsPositiveSize(width) and VisualScale.IsPositiveSize(height)
            and VisualScale.IsPositiveSize(dpr), "NanoVG只接收有限正尺寸")
        begins = begins + 1
        oldBegin(context, width, height, dpr)
    end
    nvgEndFrame = function(context)
        ends = ends + 1
        oldEnd(context)
    end
    local originalLayout = arena.GetAbsoluteLayout
    local ok, err = pcall(function()
        local nan = 0 / 0
        local invalid = { 0, -1, nan, math.huge, -math.huge }
        -- 模拟布局重建产生的无效宽高；真实调用main入口，不能仅测Camera纯函数。
        for _, value in ipairs(invalid) do
            arena.GetAbsoluteLayout = function()
                return { x = layout.x, y = layout.y, w = value, h = layout.h }
            end
            originalRender()
            arena.GetAbsoluteLayout = function()
                return { x = layout.x, y = layout.y, w = layout.w, h = value }
            end
            originalRender()
        end
        arena.GetAbsoluteLayout = originalLayout
        -- 外部调用Draw也必须安全：UI缩放、位置、极值运算均不可污染渲染状态。
        for _, value in ipairs(invalid) do
            Draw.Render(testGame, layout, value)
        end
        for _, value in ipairs({ nan, math.huge, -math.huge }) do
            Draw.Render(testGame, { x = value, y = layout.y, w = layout.w, h = layout.h }, 1)
            Draw.Render(testGame, { x = layout.x, y = value, w = layout.w, h = layout.h }, 1)
        end
        Draw.Render(testGame, { x = 0, y = 0, w = 1e308, h = 1e308 }, 1e308)
        Check(begins == 0 and ends == 0, "异常布局与缩放不开始半截NanoVG帧")
        originalRender()
        Check(begins == 1 and ends == 1, "恢复真实布局后同帧正常完成绘制")
    end)
    arena.GetAbsoluteLayout = originalLayout
    nvgBeginFrame, nvgEndFrame = oldBegin, oldEnd
    assert(ok, err)
    if phase == 12 then
        print("[镜头回归汇总] " .. passed .. "项断言通过；12轮异常布局注入后均恢复；无半截NanoVG帧")
    end
end
