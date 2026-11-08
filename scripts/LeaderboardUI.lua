-- 《下班！别拦我》：排行榜面板（含昵称）。
-- 设计依据：docs/design/05-endless-leaderboard.md §4.2 榜单面板伪码 / §4.3 结算+昵称键盘。
-- 原生昵称输入支持中文、英文、数字和标点；长昵称在榜单内省略显示。
--
-- 布局：固定高度的 Card 里塞一个 ScrollView（长榜单只滚内容，不撑破外框），
-- 底部三个按钮常驻在滚动区外，任何一档模式都不会消失，只靠 disabled 表达不可用。
local UI = require("urhox-libs/UI")
local Skin = require("UISkin")
local Scale = require("InterfaceScale")
local LeaderboardUI = {}

-- #  昵称  分数  波次  首领  等级
local COLS = { 38, 150, 110, 64, 64, 64 }
local HEAD = { "#", "昵称", "分数", "波次", "首领", "等级" }

-- 只渲染前 10 行：面板高度固定，再多也只是滚动条变长，看不清还不如不看。
local SHOW_ROWS = 10

-- fengari 的整数是 32 位，超界浮点进 string.format("%d") 会直接抛错。
local INT_MAX, INT_MIN = 2147483647, -2147483648

local function safeInt(v, default)
    local n = tonumber(v)
    if type(n) ~= "number" or n ~= n then return default end
    if n >= INT_MAX then return INT_MAX end
    if n <= INT_MIN then return INT_MIN end
    return math.floor(n + 0.0)
end

local function cell(text, w, size, color, align)
    return Skin.Text(tostring(text), size, color, {
        width = w, fontFamily = "mono", textAlign = align or "left",
        whiteSpace = "nowrap", maxLines = 1, className="leaderboard-cell",
    })
end

-- 兼容旧签名：Build(entries, onClose) 与 Build{ entries=..., ... } 都能用。
local function normalizeOpts(a, b)
    if type(a) ~= "table" then return { entries = {}, onClose = b } end
    local looksLikeOpts = a.entries ~= nil or a.mode ~= nil or a.myName ~= nil
        or a.myScore ~= nil or a.syncing ~= nil
        or type(a.onClose) == "function" or type(a.onRefresh) == "function"
        or type(a.onClear) == "function"
    if looksLikeOpts then return a end
    -- 不是 opts 表就当成 entries 数组（旧签名），空表也一样。
    return { entries = a, onClose = b }
end

local function fire(fn)
    if type(fn) == "function" then fn() end
end

---@param opts table {entries, myName, myScore, mode, syncing, onClose, onRefresh, onClear}
---@param onClose function? 旧签名 Build(entries, onClose) 的第二个参数
---@return table UI 面板
function LeaderboardUI.Build(opts, onClose)
    opts = normalizeOpts(opts, onClose)
    local p = Scale.Get()
    local S = p.px
    local C = Skin.colors
    local entries = type(opts.entries) == "table" and opts.entries or {}
    local myName = tostring(opts.myName or "")
    local myScore = tonumber(opts.myScore)
    local syncing = opts.syncing == true
    local mode = opts.mode or "local"

    local widths = {}
    for i = 1, 6 do widths[i] = S(COLS[i]) end
    if p.portrait then widths={24,p.w<370 and 65 or 85,65,32,0,0}end

    local function row(cells, colors, bg)
        local kids = {}
        for i = 1, p.portrait and 4 or 6 do
            kids[#kids + 1] = cell(cells[i] == nil and "" or cells[i], widths[i],
                i == 1 and 15 or 13, colors[i] or "cream", i >= 3 and "right" or "left")
        end
        return UI.Panel { width = "100%", flexDirection = "row", gap = S(4),
            paddingVertical = S(6), paddingHorizontal = S(4),
            backgroundColor = bg or { 0, 0, 0, 0 }, children = kids }
    end

    local rows = {}
    rows[#rows + 1] = row(HEAD, { "muted", "muted", "muted", "muted", "muted", "muted" },
        { 0, 0, 0, 0 })
    rows[#rows + 1] = Skin.Rule()

    local shown = math.min(SHOW_ROWS, #entries)
    for i = 1, shown do
        local e = entries[i]
        if type(e) == "table" then
            local name = tostring(e.name or "")
            local score = safeInt(e.score, 0)
            -- mine：名字与分数同时吻合才算自己（同名不同分会误亮整行）。
            local mine = myName ~= "" and name == myName and myScore ~= nil and score == myScore
            local rankColor = (i == 1 and "gold") or (i == 2 and "wood") or (i == 3 and "pink") or "muted"
            -- 自己那行底色是 teal，金/木/粉在蓝底上会糊掉，统一提亮成 cream。
            if mine then rankColor = "cream" end
            local textColor = mine and "cream" or "ink"
            rows[#rows + 1] = row(
                { tostring(i), name == "" and "???" or name,
                    string.format("%d", score),
                    tostring(safeInt(e.wave, 0)), tostring(safeInt(e.boss, 0)),
                    tostring(safeInt(e.level, 1)) },
                { rankColor, textColor, textColor, mine and "cream" or "ink", mine and "cream" or "ink", mine and "cream" or "ink" },
                mine and {180,235,216,255} or { 0, 0, 0, 0 })
        end
    end
    if shown == 0 then
        rows[#rows + 1] = UI.Panel { width = "100%", paddingVertical = S(40), alignItems = "center",
            children = { Skin.Text("还没有人上榜 —— 去加个班？", 14, "muted", { textAlign = "center" }) } }
    end

    local refreshText = syncing and "同步中…" or "刷新"
    local clearDisabled = mode ~= "local"

    -- 高度按实际行数收缩：空榜/短榜不要留一大片空白。
    -- 底部按钮块固定 184，滚动区内容 = 上下 padding 48 + 标题 32 + 副标题 15
    -- + 三处 gap 36 + 表头 21 + 每行 34（空榜额外 70）。
    local bodyH = S(184 + 48 + 32 + 15 + 36 + 21) + shown * S(34) + (shown == 0 and S(70) or 0)
    local cardH = math.max(S(330), math.min(p.h - S(28), math.min(S(690), bodyH)))

    return Skin.Card { id = "leaderboardPanel",className="game-card leaderboard-sheet", width = "92%",
        maxWidth = math.min(S(620), p.w - S(32)),
        height = math.min(p.h-24,cardH),
        padding = 0, gap = 0, flexShrink = 0, children = {
            UI.ScrollView { id = "lbScroll", width = "100%", flexGrow = 1, flexBasis = 0,
                minHeight = 0, scrollX = false, scrollY = true, bounces = false, children = {
                    UI.Panel { width = "100%", padding = S(24), gap = S(12), children = {
                        Skin.Text("加 班 排 行 榜", 24, "ink",
                            { textAlign = "center", fontWeight = "bold" }),
                        UI.Panel{width="100%",flexDirection="row",gap=8,children={
                            Skin.Button{id="lbEndlessTab",text="无尽榜",disabled=syncing,tone=opts.scope=="endless"and"mint"or"lilac",height=44,flexGrow=1,flexBasis=0,minWidth=0,onClick=function()if opts.onMode then opts.onMode("endless")end end},
                            Skin.Button{id="lbCampaignTab",text="战役榜",disabled=syncing,tone=opts.scope=="campaign"and"mint"or"lilac",height=44,flexGrow=1,flexBasis=0,minWidth=0,onClick=function()if opts.onMode then opts.onMode("campaign")end end}}},
                        Skin.Text(mode == "local" and "本地记录 · 换浏览器即失" or "在线榜单",
                            11, "muted", { textAlign = "center", whiteSpace = "normal" }),
                        UI.Panel { width = "100%", gap = S(2), children = rows },
                    } },
                } },
            UI.Panel { className="leaderboard-actions",width = "100%", paddingHorizontal = S(24), paddingBottom = S(20),
                paddingTop = S(8), gap = S(8), children = {
                    Skin.Button { id = "lbClose", text = "返回", width = "100%", height = 48,
                        onClick = function() fire(opts.onClose) end },
                    Skin.Button { id = "lbRefresh", text = refreshText, width = "100%", height = 48,
                        variant = "secondary", disabled = syncing,
                        onClick = function() if not syncing then fire(opts.onRefresh) end end },
                    Skin.Button { id = "lbClear", text = "清空本地记录", width = "100%", height = 44,
                        variant = "secondary", disabled = clearDisabled,
                        onClick = function() if not clearDisabled then fire(opts.onClear) end end },
                } },
        } }
end

return LeaderboardUI
