-- 沿用 main.lua 的 PixelForge 主题；只构建卡片，不初始化 UI 或接管根控件。
local UI = require("urhox-libs/UI")
local Game = require("Game")
local Campaign = require("Campaign")
local CampaignUI = {}
local Skin = require("UISkin")
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
        text = text, fontSize = size or 10.5, fontColor = COLOR[color or "white"] or COLOR.white,
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
    local cardWidth = math.min(900, math.max(0, width - 32))
    ---@type number
    local cardHeight = math.min(preferredHeight, math.max(0, height - 32))
    ---@type number
    local padding = compact and 12 or (small and 14 or 22)
    local content = UI.Panel {
        width = "100%", padding = padding, paddingRight = padding + 12,
        gap = compact and 8 or 12, flexShrink = 0, minWidth = 0,
    }
    local card = Skin.Card {
        id = id, width = cardWidth, height = cardHeight, maxWidth = math.max(0, width - 32),
        maxHeight = math.max(0, height - 32), padding = 0, gap = 0, flexShrink = 0,
        variant = "outlined", backgroundColor = COLOR.bg, borderColor = COLOR.line,
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
    local stepX, stepY = mapWidth / 6, compact and 80 or 96
    ---@type number, number
    local nodeWidth, nodeHeight = math.min(100, stepX - 8), compact and 66 or 78
    ---@type number
    local top = 26
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

---@param g CampaignUIState
---@return Card
function CampaignUI.Shop(g)
    local width, height = UI.GetViewportSize()
    local card, content, small, compact = Frame("campaignShop", width < 700 and 790 or (height < 600 and 480 or 530))
    local floor, roomId = g.floor, g.roomIndex
    local balance = Label("", 13.5, "gold", { id = "shopBalance", fontFamily = "mono" })
    ---@type Button[]
    local buttons = {}
    ---@type Label[]
    local statuses = {}
    ---@type Widget[]
    local products = {}
    local function Refresh()
        balance:SetText("摸鱼币  " .. tostring(g.coins))
        for index, button in ipairs(buttons) do
            local item = g.shopItems[index]
            if item then
                local affordable = g.coins >= item.price
                local fullHealth = item.id == "heal" and g.player.hp >= g.player.maxHp
                local maxLevel = item.id == "stapler" and g.stapler >= 4
                local unavailable = fullHealth or maxLevel
                local active = g.mode == "shop" and g.floor == floor and g.roomIndex == roomId
                button:SetDisabled(not active or item.sold or unavailable or not affordable)
                button:SetText(item.sold and "已售罄" or (fullHealth and "精力已满" or (maxLevel and "已满级" or (affordable and "买下这份补给" or "余额不足"))))
                local status = statuses[index]
                if status then
                    status:SetText(item.sold and "已购入 / 本房间仅售一份"
                        or (fullHealth and "当前满血，无需恢复 / 不扣币"
                        or (maxLevel and "订书机已达4级 / 不扣币"
                        or (affordable and "余额充足，可以购买" or "还差 " .. (item.price - g.coins) .. " 枚摸鱼币"))))
                    status:SetFontColor((item.sold or unavailable) and COLOR.muted or (affordable and COLOR.teal or COLOR.pink))
                end
            else button:SetDisabled(true) end
        end
    end
    content:AddChild(Label("SUPPLY SHOP  /  " .. FloorText(g), 9, "teal", { fontFamily = "mono" }))
    content:AddChild(Label("摸鱼补给站", compact and 21 or 25.5, "gold", { fontWeight = "bold" }))
    content:AddChild(Label("把劳动所得，花在自己身上。每件限购一次，不想买也能走。", 10.5, "muted"))
    content:AddChild(balance)
    content:AddChild(Rule())
    for index, item in ipairs(g.shopItems) do
        local n = index
        local status = Label("", 9, "muted", { id = "shopStatus" .. n })
        local button = Skin.Button {
            id = "shopBuy" .. n, text = "购买", width = "100%", height = compact and 36 or 44, fontSize = 10.5,
            onClick = function()
                local current = g.shopItems[n]
                if g.mode ~= "shop" or g.floor ~= floor or g.roomIndex ~= roomId
                    or not current or current.sold or g.coins < current.price then
                    print("[商店界面] 取消无效购买：商品=" .. n .. "，模式=" .. g.mode .. "，余额=" .. g.coins)
                    Refresh()
                    return
                end
                print("[商店界面] 购买 " .. current.title .. "，价格=" .. current.price .. "，购买前余额=" .. g.coins)
                Game.Buy(g, n)
                -- Buy 不改变 shop 模式；本地同步全部按钮与余额，不等待外部重建。
                Refresh()
                print("[商店界面] 购买后余额=" .. g.coins .. "，uiRevision=" .. g.uiRevision)
            end,
        }
        buttons[n], statuses[n] = button, status
        products[#products + 1] = OptionCard(small, compact, "gold", {
            Label(string.format("SUPPLY %02d", n), 9, "muted", { fontFamily = "mono" }),
            Label(item.title, 15, "gold", { fontWeight = "bold" }),
            Label(item.desc, 10.5, "white"),
            UI.Panel { minHeight = compact and 0 or 6, flexGrow = 1 },
            Label(item.price .. " 枚摸鱼币", 12, "gold", { fontFamily = "mono" }), status, button,
        })
    end
    content:AddChild(UI.Panel { width = "100%", flexDirection = small and "column" or "row", gap = 10, children = products })
    content:AddChild(Skin.Button {
        id = "shopLeave", text = "补给结束，离开商店  →", width = "100%", height = compact and 38 or 46,
        fontSize = 11, variant = "secondary",
        onClick = function(self)
            if g.mode ~= "shop" or g.floor ~= floor or g.roomIndex ~= roomId then return end
            self:SetDisabled(true)
            print("[商店界面] 离开 F" .. floor .. " 商店，剩余摸鱼币=" .. g.coins)
            Game.LeaveShop(g)
            Refresh()
        end,
    })
    content:AddChild(Label("离开后商店房间完成，上方出口开启。走到出口，再选择下一站；不会直接跳过事件。", 9, "muted"))
    Refresh()
    print("[商店界面] F" .. floor .. "，商品=" .. #products .. "，余额=" .. g.coins .. "，竖排=" .. tostring(small) .. "，紧凑=" .. tostring(compact))
    return card
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
        local button = Skin.Button {
            id = "eventChoose" .. n, text = "选择这份礼物  →", width = "100%", height = compact and 36 or 44,
            fontSize = 10.5, disabled = g.mode ~= "event",
            onClick = function()
                if g.mode ~= "event" or g.floor ~= floor or g.roomIndex ~= roomId or not g.eventChoices[n] then
                    print("[事件界面] 忽略过期选择：选项=" .. n .. "，模式=" .. g.mode)
                    return
                end
                for _, other in ipairs(buttons) do other:SetDisabled(true) end
                print("[事件界面] F" .. floor .. "，选择=" .. n .. " " .. choice.title .. "，效果=" .. choice.desc)
                Game.ResolveEvent(g, n)
            end,
        }
        buttons[n] = button
        choices[#choices + 1] = OptionCard(small, compact, choice.color, {
            Label(string.format("CHOICE %02d", n), 9, choice.color, { fontFamily = "mono" }),
            Label(choice.title, 15, choice.color, { fontWeight = "bold" }),
            Label("立即效果", 9, "muted"), Label(choice.desc, 12, "white"),
            UI.Panel { minHeight = compact and 0 or 6, flexGrow = 1 }, button,
        })
    end
    content:AddChild(UI.Panel { width = "100%", flexDirection = small and "column" or "row", gap = 10, children = choices })
    content:AddChild(Label("这次没有标准答案，选对自己有用的。选择后返回房间，上方出口开启，走到出口继续前进。", 9, "muted"))
    print("[事件界面] F" .. floor .. " " .. g.eventTitle .. "，选项=" .. #choices .. "，竖排=" .. tostring(small) .. "，紧凑=" .. tostring(compact))
    return card
end

return CampaignUI
