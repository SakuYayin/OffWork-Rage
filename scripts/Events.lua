-- 《下班！别拦我》：随机事件池（S5 实装）。
-- 设计依据：docs/design/06-random-events.md（减半口径见 07-halved-plan.md §2.11）。
-- 减半后实装 8 条新增 + 3 条 legacy = 11 条；新增 Σweight = 127。
--
-- 回归红线：首事件房必须 pin legacy_1，且按钮文案一字不改 ——
-- tests/Menu.lua:162 要求点「选择这份礼物  →」后女主 maxHp 90 → 100。
--
-- 与 Game.ResolveEvent 的契约（Lead 已按此接线）：
--   Events.Apply(g, room) 返回 true 时，g 上一定有这 4 个字段：
--     g.eventTitle : string              事件标题
--     g.eventText  : string              事件描述正文
--     g.eventChoices : EventChoice[]     每项含 text / title / desc / color / apply
--     g.eventId    : string              事件 id
--   Game.ResolveEvent 会优先调用 g.eventChoices[i].apply(g)，没有 apply 才走旧三条分支。
--   CampaignUI.Event 仍会读 choice.title / choice.desc / choice.color，所以每项都补齐了：
--   title 恒等于 text（旧渲染不破），desc 给一句效果摘要（旧渲染里 desc 参与字符串拼接，
--   留 nil 会在点击时抛「attempt to concatenate a nil value」）。
--
-- 纯 Lua 5.3，不 require 任何项目模块；fengari 为 32 位整数，除法一律走浮点（+ 0.0）。
local Events = {}
local Scaling=require("HeroScaling")

-- 灰度开关：S5 已验收（11 条事件 apply 全演练、分层 TIERS 正确、首房 pin legacy_1），转正。
Events.USE_POOL = true

---@class EventChoice
---@field text string   按钮文案（新版渲染读这个）
---@field title string  旧渲染字段，恒等于 text
---@field desc string   效果摘要（旧渲染必读，不能为 nil）
---@field color string  teal / gold / pink / purple
---@field apply fun(g: table)

---@class EventDef
---@field id string
---@field weight integer  0 表示只能被 pin，不参与随机
---@field kind string     bless / curse / swap / gamble
---@field title string
---@field text string
---@field choices EventChoice[]

-- ============================================================================
-- 小工具：所有 apply 都要防御字段缺失（事件可能在半初始化的 g 上被测试调用）。
-- 本项目的「精力」就是玩家血量 hp，「最大精力」就是 maxHp。
-- ============================================================================

--- 复用 Game.Announce 的字段，但不 require Game（只写字段，不起依赖）。
---@param g table
---@param text string
---@param seconds number?
local function Say(g, text, seconds)
    if not g then return end
    if g.heroId=="fufu"then text=text:gsub("怒气满了","补充糕点（最多3格）"):gsub("怒气充满","补充糕点（最多3格）")end
    g.announcement, g.announcementTime = text, seconds or 3
end

---@param g table
---@return integer
local function Coins(g)
    return math.floor((g.coins or 0) + 0.5)
end

---@param g table
---@param amount integer 可为负
local function AddCoins(g, amount)
    g.coins = math.max(0, Coins(g) + (amount or 0))
end

--- 扣币；不够就不扣并返回 false（调用方负责给一句提示）。
---@param g table
---@param cost integer
---@return boolean
local function PayCoins(g, cost)
    if Coins(g) < cost then return false end
    g.coins = Coins(g) - cost
    return true
end

--- 回血，封顶 maxHp，至少留 1。
---@param g table
---@param amount number
local function Heal(g, amount)
    local p = g.player
    if not p then return end
    p.maxHp = p.maxHp or 100
    local game=package.loaded["Game"]
    amount=Scaling.Gain(g,amount or 0)
    if game and game.Heal then game.Heal(g,amount);return end
    p.hp = math.min(p.maxHp, math.max(1, (p.hp or p.maxHp) + amount))
end

--- 代价型掉精力：永远不会把玩家扣进结算（下限 1）。
---@param g table
---@param amount number
local function Cost(g, amount)
    local p = g.player
    if not p then return end
    p.maxHp = p.maxHp or 100
    p.hp = math.max(1, math.min(p.maxHp, (p.hp or p.maxHp) - (amount or 0)))
end

---@param g table
---@param amount number
local function AddMaxHp(g, amount)
    local p = g.player
    if not p then return end
    p.maxHp = (p.maxHp or 100) + Scaling.Gain(g,amount or 0)
    p.hp = math.min(p.maxHp, math.max(1, p.hp or p.maxHp))
end

---@param g table
---@param amount number
local function AddDamage(g, amount)
    g.damage = (g.damage or 1) + Scaling.Gain(g,amount or 0)
end

---@param g table
---@param amount number
local function AddRange(g, amount)
    g.range = (g.range or 1) + Scaling.Gain(g,amount or 0)
end

---@param g table
---@param amount number
local function AddAttackSpeed(g, amount)
    g.attackSpeed = (g.attackSpeed or 1) + Scaling.Gain(g,amount or 0)
end

---@param g table
---@param amount number
local function AddMoveSpeed(g, amount)
    local p = g.player
    if not p then return end
    p.speed = (p.speed or 90) + Scaling.Gain(g,amount or 0)
end

---@param g table
---@param value number
local function SetRage(g, value)
    if g.heroId=="fufu"and g.summons then
        g.summons.charges=math.min(3,g.summons.charges+1)
        if g.summons.charges==3 then g.summons.recovery=0 end
        return
    end
    local current=g.rage or 0
    g.rage=math.max(0,math.min(100,current+Scaling.Gain(g,value-current)))
end

--- 百分比判定：percent = 30 表示 30% 命中。整数比较，避开 32 位除法。
---@param percent integer
---@return boolean
local function Chance(percent)
    return math.random(1, 100) <= percent
end

--- 构造一个选项，保证 text / title / desc / color / apply 五件套齐全。
---@param text string
---@param desc string
---@param color string
---@param apply fun(g: table)
---@return EventChoice
local function Choice(text, desc, color, apply)
    return { text = text, title = text, desc = desc, color = color, apply = apply }
end

-- ============================================================================
-- 11 条事件：3 条 legacy（weight = 0，只供 pin）+ 8 条新增（随机抽取）
-- ============================================================================

Events.LIST = {
    -- ---------------------------------------------------------------- legacy
    {
        id = "legacy_1", weight = 0, kind = "bless",
        title = "同事的善意",
        text = "加班到十点，隔壁工位的前辈把最后一盒关东煮推了过来：「年轻人，先活着。」"
            .. "保温箱还热着，你忽然有点想哭——原来这个点还有人记得你没吃饭。",
        choices = {
            Choice("选择这份礼物  →", "精力恢复40，最大精力+10。", "teal", function(g)
                local p = g.player
                if not p then return end
                AddMaxHp(g,10)
                Heal(g,40)
                Say(g, "关东煮下肚，你又能扛了。", 2.5)
            end),
        },
    },
    {
        id = "legacy_2", weight = 0, kind = "bless",
        title = "匿名意见箱",
        text = "意见箱里塞满没署名的纸条，最底下那张只写了六个字：「记得要加班费。」"
            .. "旁边还压着一个信封，鼓鼓的。",
        choices = {
            Choice("收下信封  →", "获得50枚摸鱼币。", "gold", function(g)
                AddCoins(g, 50)
                Say(g, "信封里是50枚摸鱼币，有零有整。", 2.5)
            end),
        },
    },
    {
        id = "legacy_3", weight = 0, kind = "bless",
        title = "劳动合同的最后一页",
        text = "你翻到劳动合同最后一页，某条被折起的条款写着：员工有权拥有自己的时间。"
            .. "签名栏是空的，像是在等你自己填。",
        choices = {
            Choice("签下拒绝承诺  →", "伤害+20%，怒气充满。", "pink", function(g)
                AddDamage(g, 0.2)
                SetRage(g, 100)
                Say(g, "你把名字签在最下面，笔尖戳破了纸。", 2.5)
            end),
        },
    },

    -- ---------------------------------------------------------------- bless
    {
        id = "bl_1", weight = 20, kind = "bless",
        title = "白嫖加班费",
        text = "财务系统抽风，把上个月的加班费打了两遍。群里没人吱声，"
            .. "只有你在工位上听见了自己的心跳——上报，还是装死？",
        choices = {
            Choice("闷声收下60币  →", "获得60枚摸鱼币，不留痕迹。", "gold", function(g)
                AddCoins(g, 60)
                Say(g, "钱到账了。你把短信删得很干净。", 2.5)
            end),
            Choice("上交换调休  →", "放弃这笔钱，最大精力+8。", "teal", function(g)
                AddMaxHp(g, 8)
                Heal(g, 8)
                Say(g, "主管愣了半秒，批了你半天假。", 2.5)
            end),
        },
    },
    {
        id = "bl_2", weight = 18, kind = "bless",
        title = "天降咖啡",
        text = "甲方寄来一整箱挂耳咖啡，说是「一点心意」。同事围过来分赃，"
            .. "你抢到最后一包，深烘，包装上写着 triple shot。",
        choices = {
            Choice("一口闷  →", "怒气瞬间充满。", "pink", function(g)
                SetRage(g, 100)
                Say(g, "心跳快得像刚跑完八百米，怒气满了。", 2.5)
            end),
            Choice("留着慢慢喝  →", "攻速+0.15。", "teal", function(g)
                AddAttackSpeed(g, 0.15)
                Say(g, "手速上来了，键盘声都变密了。", 2.5)
            end),
        },
    },

    -- ---------------------------------------------------------------- curse
    {
        id = "cur_1", weight = 16, kind = "curse",
        title = "绩效背锅",
        text = "季度复盘会上，主管把那张错的报表推到你面前，压低声音：「小问题，你担一下。」"
            .. "会议室里所有人的目光都落在你身上，空调声突然很大。",
        choices = {
            Choice("背下这口锅  →", "精力-15，摸鱼币+80。", "gold", function(g)
                Cost(g, 15)
                AddCoins(g, 80)
                Say(g, "锅背走了，钱到账了，谁也没赢。", 2.5)
            end),
            Choice("当场把话说明白  →", "拒绝背锅，精力-8。", "teal", function(g)
                Cost(g, 8)
                Say(g, "会议延长了四十分钟，但锅不是你的了。", 2.5)
            end),
        },
    },
    {
        id = "cur_2", weight = 16, kind = "curse",
        title = "通宵代价",
        text = "为了赶今早的交付，你通了个整夜。天亮了，代码跑通了，"
            .. "镜子里那个人眼白泛黄，手却稳得可怕。",
        choices = {
            Choice("把状态调到极限  →", "精力-20，伤害+0.3。", "pink", function(g)
                Cost(g, 20)
                AddDamage(g, 0.3)
                Say(g, "你的手在抖，但伤害真的变高了。", 2.5)
            end),
            Choice("准时下班补觉  →", "什么都不改变。", "teal", function(g)
                Say(g, "你关掉电脑，第一次在九点前离开。", 2.5)
            end),
        },
    },

    -- ---------------------------------------------------------------- swap
    {
        id = "sw_1", weight = 15, kind = "swap",
        title = "换岗",
        text = "HR 发来一张岗位调整意向表：前排近战，还是后排风筝？"
            .. "两种都要加班，区别只是加班时你在哪个位置挨打。",
        choices = {
            Choice("转前排  →", "精力-15，射程+0.2。", "purple", function(g)
                Cost(g, 15)
                AddRange(g, 0.2)
                Say(g, "工位挪到了过道，手更长，也更显眼。", 2.5)
            end),
            Choice("转后台  →", "精力-15，移速+18。", "teal", function(g)
                Cost(g, 15)
                AddMoveSpeed(g, 18)
                Say(g, "你学会了贴着墙根走。", 2.5)
            end),
        },
    },
    {
        id = "sw_2", weight = 14, kind = "swap",
        title = "对赌",
        text = "组里流行对赌：拿这个月的补贴押下个季度的项目奖金。"
            .. "老王去年赢了两次，今年已经换了新键盘。",
        choices = {
            Choice("押上40币赌一把  →", "50%概率拿回100币，否则血本无归。", "pink", function(g)
                if not PayCoins(g, 40) then
                    Say(g, "钱包比脸还干净，赌局没你位置。", 2.5)
                    return
                end
                if Chance(50) then
                    AddCoins(g, 100)
                    Say(g, "开奖了：100币到账，老王想请你吃饭。", 3)
                else
                    Say(g, "开奖了：40币没了，键盘还是旧的。", 3)
                end
            end),
            Choice("不赌，稳妥过日子  →", "保留40枚摸鱼币。", "teal", function(g)
                Say(g, "你把钱转进了余额宝，年化1.6%。", 2.5)
            end),
        },
    },

    -- ---------------------------------------------------------------- gamble
    {
        id = "gb_1", weight = 14, kind = "gamble",
        title = "抽奖",
        text = "行政在群里发了个抽奖链接，奖品是公司周边和一点现金。"
            .. "抽一次三十币，说明里写着「中奖率高达三成」——注意是「高达」。",
        choices = {
            Choice("花30币抽一次  →", "30%得100币，否则只回10币。", "gold", function(g)
                if not PayCoins(g, 30) then
                    Say(g, "摸鱼币不够30，抽奖按钮灰了。", 2.5)
                    return
                end
                if Chance(30) then
                    AddCoins(g, 100)
                    Say(g, "一等奖！你截图发群里，没人回。", 3)
                else
                    AddCoins(g, 10)
                    Say(g, "谢谢参与，返你10币安慰奖。", 3)
                end
            end),
            Choice("走开  →", "不抽，不亏。", "teal", function(g)
                Say(g, "你关掉了链接，也关掉了同事的劝说。", 2.5)
            end),
        },
    },
    {
        id = "gb_2", weight = 14, kind = "gamble",
        title = "梭哈",
        text = "年终奖到账那晚，群里有人晒出梭哈翻倍的截图。"
            .. "你盯着余额看了很久，手指悬在确认键上。",
        choices = {
            Choice("全部押上  →", "40%概率翻倍，否则全部亏光。", "pink", function(g)
                local bet = Coins(g)
                if bet <= 0 then
                    Say(g, "你连一个币都没有，梭哪门子哈。", 2.5)
                    return
                end
                if Chance(40) then
                    g.coins = bet * 2
                    Say(g, "翻倍了！你截图的手在抖。", 3)
                else
                    g.coins = 0
                    Say(g, "归零。你安静地关掉了群聊。", 3)
                end
            end),
            Choice("保住这笔钱  →", "什么都不做，币还在。", "teal", function(g)
                Say(g, "你把余额截图存进相册，然后锁屏。", 2.5)
            end),
        },
    },
}

-- ============================================================================
-- 查询
-- ============================================================================

local index, indexedCount = nil, -1

local function BuildIndex()
    index, indexedCount = {}, #Events.LIST
    for _, def in ipairs(Events.LIST) do
        if def and def.id then index[def.id] = def end
    end
end

---@param id string
---@return EventDef?
function Events.Get(id)
    if type(id) ~= "string" then return nil end
    -- 运行时可能有人往 LIST 末尾塞测试事件，长度变了就重建索引（不碰已有条目）。
    if not index or indexedCount ~= #Events.LIST then BuildIndex() end
    local def = index[id]
    if def then return def end
    for _, item in ipairs(Events.LIST) do
        if item.id == id then return item end
    end
    return nil
end

-- 分层：F1 只出温和的 bless / swap；F2 加入 gamble；F3 起四类全开（含 curse）。
-- 表里没有的层（F4+ 无尽模式）直接放开，避免后期事件池干涸。
local TIERS = {
    [1] = { bless = true, swap = true },
    [2] = { bless = true, swap = true, gamble = true },
}

---@param floor integer
---@param kind string
---@return boolean
local function KindAllowed(floor, kind)
    local tier = TIERS[floor]
    if not tier then return true end
    return tier[kind] == true
end

-- ============================================================================
-- 抽取
-- ============================================================================

--- 按权重抽一条，排除 exclude 里的 id。
---@param floor integer
---@param exclude table?  { [id] = true }
---@return EventDef?
function Events.Pick(floor, exclude)
    local level = math.floor(tonumber(floor) or 1)
    local blocked = exclude or {}
    local pool, total = {}, 0
    for _, def in ipairs(Events.LIST) do
        local weight = def.weight or 0
        if weight > 0 and not blocked[def.id] and def.choices and #def.choices > 0
            and KindAllowed(level, def.kind) then
            total = total + weight
            pool[#pool + 1] = { def = def, weight = weight }
        end
    end
    if total <= 0 then return nil end
    -- 浮点游标：fengari 里整数除法会被截断，这里全程走浮点。
    local roll, cursor = math.random() * (total + 0.0), 0.0
    for _, item in ipairs(pool) do
        cursor = cursor + (item.weight + 0.0)
        if roll < cursor then return item.def end
    end
    return pool[#pool].def -- 浮点误差兜底，绝不返回 nil
end

-- ============================================================================
-- 接管事件房
-- ============================================================================

--- 把 def 的选项数组拷贝一份，并按当前英雄改写描述文案。
--- Apply 与 Reroll 共用这一份逻辑，保证「刷新出来的事件」和「新进事件房」文案完全一致。
--- 红线：除 fufu / intern 外必须直接引用 Events.LIST 里的原对象（tests/FufuCombat、tests/InternBalance
--- 会直接取 Events.Get(id).choices[i].apply，任何就地改写都会污染静态定义）。
---@param g table
---@param def EventDef
---@return EventChoice[]
local function CopyChoices(g, def)
    local choices = {}
    for i, choice in ipairs(def.choices)do
        if g.heroId=="fufu"then
            local copy={};for k,v in pairs(choice)do copy[k]=v end
            copy.desc=copy.desc:gsub("怒气瞬间充满","补充1格糕点，最多3格"):gsub("怒气充满","补充1格糕点，最多3格")
            choices[i]=copy
        elseif g.heroId=="intern"then
            local copy={};for k,v in pairs(choice)do copy[k]=v end
            copy.desc=copy.desc.."（许宁：属性、回复和怒气增益50%；代价与基础金币不变。）"
            choices[i]=copy
        else choices[i]=choice end
    end
    return choices
end

--- 接管一次事件房：返回 true 表示已把标题/描述/选项写进 g，false 表示不接管。
---@param g table
---@param room table
---@return boolean
function Events.Apply(g, room)
    if not Events.USE_POOL then return false end
    if type(g) ~= "table" then return false end
    g.eventSeen = g.eventSeen or {}

    local def
    if g.floor == 1 and (g.roomsCleared or 0) == 0 then
        -- 回归红线：首事件房固定 legacy_1，tests/Menu.lua:162 依赖它把女主 maxHp 90 -> 100。
        def = Events.Get("legacy_1")
    else
        def = Events.Pick(g.floor, g.eventSeen)
    end
    if not def or not def.choices or #def.choices == 0 then return false end

    g.eventId, g.eventTitle, g.eventText = def.id, def.title, def.text
    -- 拷贝一份数组，避免上层（存档/UI/测试）就地改动把 Events.LIST 的静态定义污染掉。
    g.eventChoices = CopyChoices(g, def)
    g.eventSeen[def.id] = true

    if room then
        print("[事件池] " .. tostring(def.id) .. " 接管事件房：" .. tostring(room.name))
    end
    return true
end

--- 刷新当前事件房（「重开一版」）：换一条事件重新接管。
--- 与 Apply 的区别只有「抽哪条」：
---   * Apply 会把首个事件房 pin 成 legacy_1；Reroll 永远走权重池。
---   * Reroll 用 g.eventSeen 排除看过的事件，保证不会刷出同一条。
--- 红线：不写 g.mode / 不扣次数 —— 次数与 uiRevision 由 Game.RerollEvent 负责，
--- 这样 UI 只依赖 Game 的一处状态机，Events 保持纯抽卡。
---@param g table
---@param room table?  事件房，仅用于日志，可为 nil
---@return boolean true 表示已换了一条；false 表示不在事件页或池子已空
function Events.Reroll(g, room)
    if not Events.USE_POOL then return false end
    if type(g) ~= "table" then return false end
    if g.mode ~= "event" then return false end
    g.eventSeen = g.eventSeen or {}

    local def = Events.Pick(g.floor, g.eventSeen)
    if not def or not def.choices or #def.choices == 0 then return false end

    g.eventId, g.eventTitle, g.eventText = def.id, def.title, def.text
    g.eventChoices = CopyChoices(g, def)
    g.eventSeen[def.id] = true

    if room then
        print("[事件池] " .. tostring(def.id) .. " 刷新事件房：" .. tostring(room.name))
    end
    return true
end

--- 只读调试：当前权重与分层下的可选条目（给 Lead 验收用，不参与运行时）。
---@param floor integer
---@return table
function Events.Available(floor)
    local level = math.floor(tonumber(floor) or 1)
    local out = {}
    for _, def in ipairs(Events.LIST) do
        if (def.weight or 0) > 0 and KindAllowed(level, def.kind) then
            out[#out + 1] = def.id
        end
    end
    return out
end

return Events
