-- 沿用 main.lua 的 PixelForge 主题；只构建卡片，不初始化 UI 或接管根控件。
local UI = require("urhox-libs/UI")
local Game = require("Game")
local Campaign = require("Campaign")
local CampaignUI = {}
local Skin = require("UISkin")
local Scale = require("InterfaceScale")
local COLOR = Skin.colors

---@class CampaignUIRoom
---@field id integer
---@field name string
---@field kind string
---@field next integer[]
---@field col integer
---@field row integer
---@field visited boolean
---@field cleared boolean

---@class CampaignUIShopItem
---@field title string
---@field desc string
---@field price integer
---@field id string
---@field sold boolean
---@field iconKind string|nil
---@field icon string|nil

---@class CampaignUIEventChoice
---@field title string
---@field desc string
---@field color string

---@class CampaignUIState
---@field mode string
---@field floor integer
---@field rooms CampaignUIRoom[]
---@field room CampaignUIRoom
---@field roomIndex integer
---@field coins integer
---@field player { hp: number, maxHp: number }
---@field stapler integer
---@field shopItems CampaignUIShopItem[]
---@field eventTitle string
---@field eventText string
---@field eventChoices CampaignUIEventChoice[]
---@field uiRevision integer

local function Label(text, size, color, extra)
    local props = {
        text = text, fontSize = Scale.Get().px(math.max(12,size or 14)), fontColor = COLOR[color or "white"] or COLOR.white,
        fontFamily = "sans", flexShrink = 0, minWidth = 0, whiteSpace = "normal", lineHeight = 1.5,
    }
    if extra then for key, value in pairs(extra) do props[key] = value end end
    return UI.Label(props)
end

local function Rule()
    return UI.Panel { width = "100%", height = 1, backgroundColor = COLOR.line, pointerEvents = "none" }
end

-- 受约束的 Card 是 ScrollView 的明确 height 父；不能仅设置 maxHeight。
-- 标题、选项及底部说明同处滚动内容，极矮屏也不会把操作裁出视口。
local function Frame(id, preferredHeight)
    local width, height = UI.GetViewportSize()
    local small, compact = width < 700, height < 600
    local cardWidth = math.min(Scale.Get().px(1025), math.max(0, width - 32))
    ---@type number
    local cardHeight = math.min(Scale.Get().px(preferredHeight), math.max(0, height - 32))
    ---@type number
    local padding = compact and 12 or (small and 14 or 22)
    local content = UI.Panel {
        width = "100%", padding = padding, paddingRight = padding + 12,
        gap = compact and 8 or 12, flexShrink = 0, minWidth = 0,
    }
    local card = Skin.Card {
        id = id, width = cardWidth, height = cardHeight, maxWidth = math.max(0, width - 32),
        maxHeight = math.max(0, height - 32), padding = 0, gap = 0, flexShrink = 0,
        variant = "outlined", backgroundColor = COLOR.surface, borderColor = COLOR.line,
        children = { UI.ScrollView {
            id = id .. "Scroll", width = "100%", height = "100%", flexGrow = 1, flexBasis = 0,
            minHeight = 0, scrollX = false, scrollY = true, showScrollbar = true, bounces = false,
            children = { content },
        } },
    }
    -- 两侧 padding + 额外滚动条留白 + Card 两侧各 2px 主题边框。
    return card, content, small, compact, math.max(0, cardWidth - padding * 2 - 16)
end

---@param g CampaignUIState
local function FloorText(g)
    local floor = Campaign.floors[g.floor]
    return string.format("F%02d / 03  ·  %s", g.floor, floor and floor.name or "下班路线")
end

---@param g CampaignUIState
---@param roomId integer
local function CanTravel(g, roomId)
    if g.mode ~= "route" or roomId == g.roomIndex then return false end
    for _, id in ipairs(g.room.next) do
        if id == roomId then return true end
    end
    return false
end

---@param g CampaignUIState
---@param room CampaignUIRoom
local function RoomStatus(g, room)
    if room.id == g.roomIndex then return room.cleared and "当前/完成" or "当前", "gold" end
    if room.cleared then return "已完成", "teal" end
    if CanTravel(g, room.id) then return "可前往", "teal" end
    return room.visited and "已到访" or "不可达", "muted"
end

---@param g CampaignUIState
---@param roomId integer
---@param floor integer
---@param origin integer
local function Travel(g, roomId, floor, origin)
    -- 再校验实时状态，防止旧卡片、快速连点或外部状态切换造成越级进入。
    if g.floor ~= floor or g.roomIndex ~= origin or not CanTravel(g, roomId) then
        print("[路线界面] 忽略过期选择：F" .. floor .. "-" .. roomId .. "，当前模式=" .. g.mode)
        return
    end
    print("[路线界面] 前往 F" .. floor .. "-" .. roomId .. "，起点=" .. origin)
    Game.Travel(g, roomId)
end

-- 6列×3行，所有线段、节点和文字均为 UI 组件，无自定义绘制。
---@param g CampaignUIState
local function RouteMap(g, mapWidth, compact)
    local S=Scale.Get().px
    local stepX, stepY = mapWidth / 6, S(compact and 80 or 96)
    ---@type number, number
    local nodeWidth, nodeHeight = math.min(S(110), stepX - 8), S(compact and 66 or 78)
    ---@type number
    local top = S(26)
    local floor, origin = g.floor, g.roomIndex
    ---@type table<number, CampaignUIRoom?>
    local roomsById = {}
    ---@type Widget[]
    local children = {}
    for _, room in ipairs(g.rooms) do roomsById[room.id] = room end

    local function Segment(x, y, width, height, color)
        children[#children + 1] = UI.Panel {
            position = "absolute", left = x, top = y, width = math.max(2, width), height = math.max(2, height),
            backgroundColor = COLOR[color], pointerEvents = "none",
        }
    end
    for col = 1, 6 do
        children[#children + 1] = Label(string.format("%02d", col), 8.25, "muted", {
            position = "absolute", left = (col - 1) * stepX, top = 0, width = stepX,
            textAlign = "center", fontFamily = "mono", whiteSpace = "nowrap",
        })
    end
    -- 连线先入树，节点后入树：线不遮字，也不接收点击。
    for _, room in ipairs(g.rooms) do
        for _, nextId in ipairs(room.next) do
            local target = roomsById[nextId]
            if target then
                local x1 = (room.col - 0.5) * stepX + nodeWidth / 2
                local x2 = (target.col - 0.5) * stepX - nodeWidth / 2
                local y1 = top + (room.row - 1) * stepY + nodeHeight / 2
                local y2 = top + (target.row - 1) * stepY + nodeHeight / 2
                local mid = (x1 + x2) / 2
                local color = room.id == origin and CanTravel(g, nextId) and "gold"
                    or (room.cleared and target.visited and "teal" or "line")
                Segment(x1, y1 - 1, mid - x1, 2, color)
                Segment(mid - 1, math.min(y1, y2), 2, math.abs(y2 - y1), color)
                Segment(mid, y2 - 1, x2 - mid, 2, color)
            end
        end
    end
    for _, room in ipairs(g.rooms) do
        local id = room.id
        local _, color = RoomStatus(g, room)
        local reachable = CanTravel(g, id)
        -- 小格只展示编号、房型和状态；完整房名及明确的前往按钮在地图下方。
        children[#children + 1] = Skin.Button {
            id = "routeNode" .. id, position = "absolute",
            left = (room.col - 0.5) * stepX - nodeWidth / 2, top = top + (room.row - 1) * stepY,
            width = math.max(1, nodeWidth), minWidth = 0, height = nodeHeight,
            paddingHorizontal = 1, paddingVertical = 4, gap = 0, alignItems = "center", justifyContent = "center",
            disabled = not reachable, backgroundColor = COLOR.surface, disabledBackgroundColor = COLOR.surface,
            backgroundImage = Skin.assets.panel, hoverBackgroundImage = Skin.assets.panel,
            pressedBackgroundImage = Skin.assets.panel, disabledBackgroundImage = Skin.assets.panel,
            backgroundSlice = { 12, 12, 12, 12 }, disabledBackgroundImageOpacity = 0.72,
            borderColor = COLOR[color], pointerEvents = "box-only",
            children = {
                Label(string.format("%02d", id), 8.25, color, { fontFamily = "mono", textAlign = "center" }),
                Label(Campaign.kindNames[room.kind] or room.kind, 9, reachable and "white" or color, { textAlign = "center" }),
                Label(room.id == origin and "当前" or (room.cleared and "完成" or (reachable and "可达" or "未达")), 8.25, color, { textAlign = "center", whiteSpace = "nowrap" }),
            },
            onClick = function() Travel(g, id, floor, origin) end,
        }
    end
    return UI.Panel {
        id = "routeMap", width = "100%", height = top + stepY * 2 + nodeHeight + 4,
        flexShrink = 0, pointerEvents = "box-none", children = children,
    }
end

---@param g CampaignUIState
---@return Card
function CampaignUI.Route(g)
    local width, height = UI.GetViewportSize()
    local card, content, small, compact, mapWidth = Frame("campaignRoute", height < 600 and 530 or 640)
    local floor, origin = g.floor, g.roomIndex
    content:AddChild(Label("ROUTE SELECT  /  " .. FloorText(g), 9, "teal", { fontFamily = "mono" }))
    content:AddChild(Label("下一站，离下班更近一点", compact and 18 or 22.5, "white", { fontWeight = "bold" }))
    content:AddChild(Label("当前：" .. g.room.name .. (g.room.cleared and "  /  已完成" or "  /  尚未完成"), 10.5, "gold"))
    content:AddChild(RouteMap(g, mapWidth, compact))
    content:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 10,
        children = {
            Label("金框：当前", 9, "gold"), Label("已完成：已清理", 9, "teal"),
            Label("可前往：可点击", 9, "teal"), Label("不可达：未连接/已错过", 9, "muted"),
        },
    })
    content:AddChild(Rule())
    ---@type Widget[]
    local choices = {}
    local reachableCount = 0
    for _, room in ipairs(g.rooms) do
        if CanTravel(g, room.id) then
            local id = room.id
            local color = Campaign.kindColors[room.kind] or "teal"
            reachableCount = reachableCount + 1
            choices[#choices + 1] = Skin.Card {
                width = small and "100%" or nil, flexGrow = small and 0 or 1, flexBasis = small and "auto" or 0,
                minWidth = 0, padding = compact and 10 or 12, gap = 6,
                variant = "outlined", backgroundColor = COLOR.surface, borderColor = COLOR[color],
                children = {
                    Label(string.format("%02d  /  %s", id, Campaign.kindNames[room.kind] or room.kind), 9, color),
                    Label(room.name, 13.5, "white", { fontWeight = "bold" }),
                    Skin.Button { id = "routeTravel" .. id, text = "前往这里  →", width = "100%", height = compact and 36 or 44,
                        fontSize = 10.5, onClick = function() Travel(g, id, floor, origin) end },
                },
            }
        end
    end
    if reachableCount == 0 then choices[1] = Label("当前没有可前往的房间。", 10.5, "muted") end
    content:AddChild(UI.Panel { width = "100%", flexDirection = small and "column" or "row", gap = 10, children = choices })
    content:AddChild(Label("路线说明", 10.5, "gold", { fontWeight = "bold" }))
    content:AddChild(Label("从左向右推进，只能选择当前房间直接连接的下一站。普通战斗与精英路线二选一，之后汇入商店和事件；每层最后一站是首领。", 9, "muted"))
    content:AddChild(Label("清理房间 → 领取强化 → 从上方出口选择路线。已完成房间不能重走，未选分支不能回头补逛。", 9, "muted"))
    print(string.format("[路线界面] F%d-%d，下一站=%d，视口=%dx%d，竖排=%s，紧凑=%s",
        floor, origin, reachableCount, math.floor(width), math.floor(height), tostring(small), tostring(compact)))
    return card
end

local function OptionCard(small, compact, color, children)
    return Skin.Card {
        width = small and "100%" or nil, minWidth = 0,
        flexGrow = small and 0 or 1, flexBasis = small and "auto" or 0,
        minHeight = small and (compact and 148 or 168) or (compact and 218 or 260),
        padding = compact and 10 or 16, gap = compact and 6 or 10,
        variant = "outlined", backgroundColor = COLOR.surface, borderColor = COLOR[color] or COLOR.line,
        children = children,
    }
end

-- ============================================================================
-- 事件界面专用辅助（只服务 CampaignUI.Event，Shop / Route 继续用 OptionCard）
-- ============================================================================

--- 事件卡片：尺寸 / 间距 / 配色与 OptionCard(:251-260) 逐字段一致，但独立实现。
--- 复制而非复用的原因：OptionCard 同时被 Shop(:324) 与 Route 使用，改它会波及两个界面。
---@param small boolean
---@param compact boolean
---@param color string|table|nil 主题色，允许颜色表；非法名输出 COLOR.line 边框
---@param children Widget[]
---@return Card
local function EventOptionCard(small, compact, color, children)
    local border = type(color) == "table" and color or (COLOR[color] or COLOR.line)
    return Skin.Card {
        width = small and "100%" or nil, minWidth = 0, maxWidth = "100%",
        flexGrow = small and 0 or 1, flexBasis = small and "auto" or 0,
        minHeight = small and (compact and 148 or 168) or (compact and 218 or 260),
        padding = compact and 10 or 16, gap = compact and 6 or 10,
        variant = "outlined", backgroundColor = COLOR.surface, borderColor = border,
        children = children,
    }
end

--- 选项主题色：字符串名统一过 Skin.Color（nil / 非法名回退 ink，绝不抛异常），已是颜色表则原样返回。
---@param choice table|nil
---@return Color
local function EventAccent(choice)
    local color = type(choice) == "table" and choice.color or nil
    if type(color) == "table" then return color end
    return Skin.Color(color)
end

--- 与 Label(:47-54) 等价，但直接吃颜色表：选项配色已经过 Skin.Color 归一化。
---@param text string
---@param size number
---@param accent Color
---@param extra table?
---@return Label
local function EventLabel(text, size, accent, extra)
    local props = {
        text = text, fontSize = Scale.Get().px(math.max(12, size or 14)), fontColor = accent or COLOR.white,
        fontFamily = "sans", flexShrink = 0, minWidth = 0, maxWidth = "100%",
        whiteSpace = "normal", lineHeight = 1.5,
    }
    if extra then for key, value in pairs(extra) do props[key] = value end end
    return UI.Label(props)
end

--- 选项按钮文案。取法：新式事件的 choice.text → choice.title → 旧串。
--- 回归红线：legacy 三条写死事件（Game.lua:307-311 那批只有 title/desc/color、没有 apply）
--- 必须原样输出「选择这份礼物  →」，tests/Menu.lua:161 依赖它把女主 maxHp 90 -> 100。
--- 新式事件（Events.lua 的 Choice 工厂，一定带 apply）才会把 title 当按钮文案。
---@param choice table|nil
---@return string
local function EventButtonText(choice)
    if type(choice) ~= "table" then return "选择这份礼物  →" end
    if type(choice.text) == "string" and choice.text ~= "" then return choice.text end
    if type(choice.apply) == "function" and type(choice.title) == "string" and choice.title ~= "" then
        return choice.title
    end
    return "选择这份礼物  →"
end

---@param g CampaignUIState
---@return Panel
function CampaignUI.Shop(g)
    local p = Scale.Get()
    local S = p.px
    local items = g.shopItems or {}
    local count = #items
    -- 选中项夹在有效区间内：刷新商品后索引可能落在末尾之外。
    local sel = math.min(math.max(1, g.shopSelectedIndex or 1), math.max(1, count))
    local cur = items[sel]
    -- 图标一律取 Game.lua 下发的 iconKind/icon；旧版 3 件商品没有这两个字段，
    -- 这里只做等价兜底（heal -> item/riceball，其余 -> buff/<id>），不按 id 猜新数据。
    local function ItemIcon(item)
        local kind = item.iconKind or (item.id == "heal" and "item" or "buff")
        local frame = item.icon or (item.id == "heal" and "riceball" or item.id)
        return kind, frame
    end
    local rowH = p.portrait and 48 or S(64)
    local rowGap = 5
    local rowStep = rowH + rowGap
    ---@type Widget[]
    local rows = {}
    for index, item in ipairs(items) do
        local n, expected = index, item
        local kind, frame = ItemIcon(item)
        rows[#rows + 1] = UI.Button {
            id = "shopBuy" .. n, ariaLabel = "查看" .. tostring(item.title),
            className = "folder-index-row" .. (n == sel and " selected" or ""),
            width = "100%", height = rowH, minHeight = 44,
            padding = 8, gap = 8, flexDirection = "row", alignItems = "center",
            flexShrink = 0, pointerEvents = "box-only",
            onClick = function()
                if g.shopItems[n] ~= expected then return end
                if Game.ShopSelect then Game.ShopSelect(g, n) end
            end,
            children = {
                Skin.Text(tostring(n), 12, "muted", { width = 18, textAlign = "center" }),
                Skin.Icon(kind, frame, p.portrait and 32 or S(38), p.portrait and 32 or S(38)),
                UI.Panel { flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 3, pointerEvents = "none", children = {
                    Skin.Text(item.title, p.portrait and 15 or 18, "ink", { className = "folder-row-title" }),
                    Skin.Text(item.sold and "已售罄" or (tostring(item.price) .. " 枚摸鱼币"), 12, "muted",
                        { className = "folder-row-effect", whiteSpace = "nowrap", maxLines = 1 }),
                } },
            },
        }
    end
    ---@type Widget[]
    local detailKids
    ---@type Button
    local buyButton
    if cur then
        local sold = cur.sold == true
        local hp = g.player and g.player.hp or 0
        local maxHp = g.player and g.player.maxHp or 0
        local fullHealth = cur.id == "heal" and hp >= maxHp
        local affordable = (g.coins or 0) >= (cur.price or 0)
        local canBuy = g.mode == "shop" and not sold and not fullHealth and affordable
        local statusText, statusColor
        if sold then
            statusText, statusColor = "已购入 / 本房间仅售一份", "muted"
        elseif fullHealth then
            statusText, statusColor = "当前满血，无需恢复 / 不扣币", "muted"
        elseif not affordable then
            statusText, statusColor = "还差 " .. tostring((cur.price or 0) - (g.coins or 0)) .. " 枚摸鱼币", "pink"
        else
            statusText, statusColor = "余额充足，可以购买", "teal"
        end
        local kind, frame = ItemIcon(cur)
        -- 详情大图尺寸必须由 Lua 决定：Skin.Sprite 的内层是按这里传入的宽高算出的
        -- 固定像素盒，外层若再用 CSS !important 缩小，内层仍停在旧尺寸（实测
        -- 844x390 时外层 55px / 内层 77px → scrollWidth 66 > clientWidth 55）。
        local detailIcon = p.portrait and 46 or (p.landscape and S(64) or S(96))
        detailKids = {
            Skin.Icon(kind, frame, detailIcon, detailIcon, "shopDetailIcon"),
            Skin.Text(cur.title, p.portrait and 21 or 30, "gold",
                { id = "shopDetailTitle", textAlign = "center", fontWeight = "bold" }),
            Skin.Text(cur.desc or "", p.portrait and 13.5 or 17, "ink",
                { id = "shopDetailEffect", textAlign = "center", lineHeight = 1.55 }),
            Skin.Text(tostring(cur.price or 0) .. " 枚摸鱼币", 13, "gold", { fontFamily = "mono", textAlign = "center" }),
            Skin.Text(statusText, 12, statusColor, { id = "shopStatus", textAlign = "center" }),
        }
        -- 购买按钮不放滚动区：详情区在横屏/矮屏只有 ~120px，按钮会被挤到折叠线以下，
        -- 主操作必须始终可见（tests/Menu.lua:154 也依赖它可点）。
        buyButton = Skin.Button {
            id = "shopBuyConfirm", text = "买下这份补给", tone = "mint",
            width = p.portrait and "100%" or S(245),
            height = 48, minHeight = 44, flexShrink = 0, disabled = not canBuy,
            onClick = function()
                if not canBuy then return end
                print("[商店界面] 购买 " .. tostring(cur.title) .. "，价格=" .. tostring(cur.price)
                    .. "，购买前余额=" .. tostring(g.coins))
                Game.Buy(g, sel)
            end,
        }
    else
        detailKids = { Skin.Text("本房间没有可购买的商品。", 14, "muted", { textAlign = "center" }) }
    end
    local rerolls = math.max(0, math.floor((g.shopRerollsLeft or 0) + 0.5))
    local rerollButton = Skin.Button {
        id = "shopReroll",
        text = rerolls > 0 and ("刷新 ↻  剩" .. rerolls .. "次") or "刷新 ↻  已用完",
        tone = "lilac", width = p.portrait and "100%" or S(200), height = 48, minHeight = 44, flexShrink = 0,
        fontSize = p.portrait and p.px(13) or nil,
        -- 竖屏与「离开」并排各占一半：flex 参数必须在这里给，UI.Button 返回的是已落地的
        -- Widget，事后改字段不会再进 applyProps（实测会退化成两个 336px 并排 → 溢出 684px）。
        flexGrow = p.portrait and 1 or nil, flexBasis = p.portrait and 0 or nil,
        disabled = rerolls <= 0,
        onClick = function() if Game.RerollShop then Game.RerollShop(g) end end,
    }
    local leaveButton = Skin.Button {
        id = "shopLeave", text = "补给结束，离开商店  →", tone = "coral",
        width = p.portrait and "100%" or S(300), height = 48, minHeight = 44, flexShrink = 0,
        fontSize = p.portrait and p.px(13) or nil,
        flexGrow = p.portrait and 1 or nil, flexBasis = p.portrait and 0 or nil,
        onClick = function()
            if g.mode ~= "shop" then return end
            print("[商店界面] 离开 F" .. g.floor .. " 商店，剩余摸鱼币=" .. tostring(g.coins))
            Game.LeaveShop(g)
        end,
    }
    ---@type Widget[]
    local footerKids
    if p.portrait then
        -- 竖屏把「刷新 / 离开」并排放一行（各占一半），省下的 60px 全给详情区；
        -- 购买按钮单独占一行，避免主操作掉进滚动区。
        footerKids = { rerollButton, leaveButton }
    else
        footerKids = {
            Skin.Text("数字键选择 · R 刷新 · E 离开", 12, "muted",
                { className = "folder-keyboard-help", flexGrow = 1, flexBasis = 0, minWidth = 0 }),
            buyButton, rerollButton, leaveButton,
        }
    end
    print("[商店界面] F" .. g.floor .. "，商品=" .. count .. "，余额=" .. tostring(g.coins))
    -- 根容器子节点按视口分支组装：竖屏多一行「购买」主操作，横屏把购买并进底栏。
    ---@type Widget[]
    local rootKids = {
        Skin.Text("摸鱼补给站", p.portrait and 24 or 30, "ink", { className = "folder-picker-heading" }),
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                Skin.Text("SUPPLY SHOP  /  " .. FloorText(g), 9, "teal", { fontFamily = "mono" }),
                Skin.Text("摸鱼币  " .. tostring(g.coins), 13.5, "gold", { id = "shopBalance", fontFamily = "mono" }),
            },
        },
        UI.Panel {
            className = "folder-picker-body", width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
            flexDirection = p.portrait and "column" or "row", gap = p.portrait and 10 or S(20),
            children = {
                UI.ScrollView {
                    id = "shopIndexScroll", scrollKey = tostring(count),
                    width = p.portrait and "100%" or "48%",
                    -- 竖屏左栏高度按整行对齐：168px 会露出半行，看起来像被裁掉。
                    height = p.portrait and math.min(#rows,
                        math.max(3, math.floor((math.max(130, math.floor(p.h * 0.20)) + rowGap) / rowStep))) * rowStep - rowGap or "100%",
                    flexShrink = 0, minHeight = 0, scrollY = true, scrollX = false,
                    children = { UI.Panel { width = "100%", gap = rowGap, children = rows } },
                },
                UI.ScrollView {
                    id = "shopDetailScroll", className = "folder-detail-scroll",
                    width = p.portrait and "100%" or "50%", flexGrow = 1, flexBasis = 0, minHeight = 0,
                    scrollY = true, scrollX = false,
                    children = { UI.Panel {
                        width = "100%", padding = p.portrait and 6 or S(16),
                        gap = p.portrait and 6 or S(15), alignItems = "center", children = detailKids,
                    } },
                },
            },
        },
    }
    if p.portrait and buyButton then
        rootKids[#rootKids + 1] = UI.Panel { width = "100%", children = { buyButton } }
    end
    rootKids[#rootKids + 1] = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", gap = 12, children = footerKids,
    }
    return UI.Panel {
        id = "campaignShop", className = "folder-picker",
        width = math.min(p.w - 24, S(1060)), height = math.min(p.h - 24, S(590)),
        padding = p.portrait and 14 or S(22), gap = 12,
        children = rootKids,
    }
end

---@param g CampaignUIState
---@return Card
function CampaignUI.Event(g)
    local width, height = UI.GetViewportSize()
    local card, content, small, compact = Frame("campaignEvent", width < 700 and 730 or (height < 600 and 450 or 510))
    local floor, roomId = g.floor, g.roomIndex
    ---@type Button[]
    local buttons = {}
    ---@type Widget[]
    local choices = {}
    content:AddChild(Label("OFFICE EVENT  /  " .. FloorText(g), 9, "purple", { fontFamily = "mono" }))
    content:AddChild(Label(g.eventTitle, compact and 19.5 or 24, "white", { fontWeight = "bold" }))
    content:AddChild(Label(g.eventText, 10.5, "muted"))
    content:AddChild(Label("三选一 / 效果立即生效，只能领取一份。", 10.5, "gold"))
    content:AddChild(Rule())
    for index, choice in ipairs(g.eventChoices) do
        local n = index
        -- 每个选项一个主题色：choice.color 走 Skin.Color 归一化，非法名回退 ink 而不是崩。
        local accent = EventAccent(choice)
        local title = type(choice) == "table" and choice.title or nil
        local desc = type(choice) == "table" and choice.desc or nil
        local button = Skin.Button {
            id = "eventChoose" .. n, text = EventButtonText(choice), width = "100%", height = compact and 36 or 44,
            fontSize = 10.5, disabled = g.mode ~= "event",
            onClick = function()
                if g.mode ~= "event" or g.floor ~= floor or g.roomIndex ~= roomId or not g.eventChoices[n] then
                    print("[事件界面] 忽略过期选择：选项=" .. n .. "，模式=" .. g.mode)
                    return
                end
                for _, other in ipairs(buttons) do other:SetDisabled(true) end
                print("[事件界面] F" .. floor .. "，选择=" .. n .. " " .. tostring(title) .. "，效果=" .. tostring(desc))
                Game.ResolveEvent(g, n)
            end,
        }
        buttons[n] = button
        local children = {
            EventLabel(string.format("CHOICE %02d", n), 9, accent, { fontFamily = "mono" }),
            Skin.Icon(n==2 and "item"or"buff",n==1 and "health"or(n==2 and "coin"or"damage"),Scale.Get().px(78),Scale.Get().px(64)),
            EventLabel(tostring(title or ""), 15, accent, { fontWeight = "bold" }),
            EventLabel("立即效果", 9, COLOR.muted),
        }
        -- desc 缺失时不留空行；有 desc 的旧事件与旧渲染逐字段一致。
        if type(desc) == "string" and desc ~= "" then children[#children + 1] = EventLabel(desc, 12, COLOR.white) end
        children[#children + 1] = UI.Panel { minHeight = compact and 0 or 6, flexGrow = 1 }
        children[#children + 1] = button
        choices[#choices + 1] = EventOptionCard(small, compact, accent, children)
    end
    content:AddChild(UI.Panel { width = "100%", flexDirection = small and "column" or "row", gap = 10, children = choices })
    content:AddChild(UI.Panel { width = "100%", flexDirection = small and "column" or "row",
        alignItems = small and "stretch" or "center", gap = small and 6 or 12, children = {
        Skin.Button {
            id = "eventReroll",
            text = ((g.eventRerollsLeft or 0) > 0)
                and ("刷新 ↻  剩" .. math.floor(g.eventRerollsLeft) .. "次") or "刷新 ↻  已用完",
            tone = "lilac", width = small and "100%" or Scale.Get().px(200), height = 44, minHeight = 44,
            flexShrink = 0, disabled = (g.eventRerollsLeft or 0) <= 0,
            onClick = function() if Game.RerollEvent then Game.RerollEvent(g) end end,
        },
        Label("刷新会换一条事件，代价与收益一起换。", 9, "muted", { flexShrink = 1 }),
    } })
    content:AddChild(Label("这次没有标准答案，选对自己有用的。选择后返回房间，上方出口开启，走到出口继续前进。", 9, "muted"))
    print("[事件界面] F" .. floor .. " " .. g.eventTitle .. "，选项=" .. #choices .. "，竖排=" .. tostring(small) .. "，紧凑=" .. tostring(compact))
    return card
end

return CampaignUI
