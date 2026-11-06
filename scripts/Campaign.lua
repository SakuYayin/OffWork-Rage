-- 三层区域：保留必经商店/事件/BUFF/首领的有向路线，复杂度来自实体子区。
local Campaign = {}
Campaign.floors = {
    { name = "加班工位层", boss = "工贼同事", subtitle = "我自愿加班，你们也别走。", hp = 540, color = "teal" },
    { name = "无尽会议层", boss = "秃头主管", subtitle = "最后五分钟，我再补充一点。", hp = 1100, color = "purple" },
    { name = "老板专属层", boss = "没良心老板", subtitle = "公司就是你的家，工资以后再谈。", hp = 1800, color = "gold" },
}

-- 碰撞/布局设计（沿用1040x680设计坐标，不改变相机；不是引擎米制坐标）：
--      x=48          北门：room.exit.triggerX / y174           x=992
-- y142 +---------------------------E-----------------------------+
--      |  办公子区   [实体隔断]   回廊/门洞   [实体隔断]  办公子区  |
--      |  desk/server          +-----------+          cabinet    |
--      |                       |会议/档案区|                     |
--      |       <----双向绕行----+  开口     +----双向绕行---->      |
--      |                  出生(520,580)                          |
-- y628 +---------------------------------------------------------+
-- 所有矩形{x,y,w,h,kind}都是实心；绘制与碰撞读取同一稳定数组。
-- 玩家r12、敌人r12~17、Boss r24；主门洞>=80，回廊可双向通行。
-- 出生/出口保留圆形净空；安全房中轴开放，Boss中轴x360..680不设障碍。
-- 细隔断厚18；连续移动/投射物做扫掠，不能靠高速度越过。
local function Obstacle(kind, x, y, w, h)
    return { kind = kind, x = x, y = y, w = w, h = h }
end
local function Desk(x, y, w, h) return Obstacle("desk", x, y, w, h) end
local function Wall(x, y, w, h) return Obstacle("partition", x, y, w, h) end
local function Cabinet(x, y, w, h) return Obstacle("cabinet", x, y, w, h) end
local function Plant(x, y, w, h) return Obstacle("planter", x, y, w, h) end
local function Server(x, y, w, h) return Obstacle("server", x, y, w, h) end

Campaign.layoutNames = {
    "四区协作工位", "回字会议环廊", "交错档案走廊", "双回廊办公翼", "双马蹄会议区",
    "错层十字分区", "服务器巡检区", "分布式接待中庭", "高层档案迷廊",
    "补给柜台与休息角", "阅读区与茶水角", "同事考核掩体场", "主管会议掩体场", "老板会客掩体场",
}
Campaign.combatLayoutCount = 9
Campaign.layouts = {
    -- 1. 四个工位子区，横向开口88；中央长桌迫使左右绕行。
    {
        Wall(332,232,18,124), Wall(332,444,18,92), Wall(690,232,18,124), Wall(690,444,18,92),
        Wall(148,394,202,18), Wall(690,394,202,18),
        Desk(152,260,104,56), Desk(152,464,104,56), Desk(784,260,104,56), Desk(784,464,104,56),
        Desk(446,334,148,64), Plant(408,224,36,36), Plant(596,496,36,36),
    },
    -- 2. 真正的回字外环+南侧144宽门洞，内会议区仍可进入，不做封闭装饰假房。
    {
        Wall(340,244,360,18), Wall(340,244,18,248), Wall(682,244,18,248),
        Wall(340,474,108,18), Wall(592,474,108,18), Desk(436,334,168,56),
        Desk(150,270,96,56), Desk(794,270,96,56), Desk(150,466,96,56), Desk(794,466,96,56),
        Server(850,382,56,44), Cabinet(134,382,56,44), Plant(600,548,36,36),
    },
    -- 3. 两道错位横墙，必须在档案带之间换道；不是旋转同一张工位图。
    {
        Wall(120,294,464,18), Wall(456,454,464,18),
        Cabinet(152,210,136,40), Cabinet(392,210,136,40), Server(768,200,80,48),
        Cabinet(176,374,96,38), Cabinet(732,374,100,38),
        Cabinet(168,542,144,36), Cabinet(728,542,144,36),
        Plant(624,214,36,36), Plant(352,374,36,36), Plant(608,374,36,36),
    },
    -- 4. 东西长隔断+中央断墙组成双回廊，联络口宽88，顶部/底部均可迂回。
    {
        Wall(288,226,18,310), Wall(496,226,18,132), Wall(496,446,18,90), Wall(734,226,18,310),
        Wall(288,382,128,18), Wall(616,382,136,18),
        Desk(122,260,96,54), Desk(122,452,96,54), Desk(578,270,76,58), Desk(578,460,76,50),
        Cabinet(372,280,48,90), Cabinet(372,450,48,54), Desk(824,306,94,54), Server(824,466,60,60),
    },
    -- 5. 两个向中庭开放的马蹄会议间，中间双桌形成左右支路。
    {
        Wall(140,230,248,18), Wall(140,230,18,260), Wall(140,472,248,18),
        Wall(652,230,248,18), Wall(882,230,18,260), Wall(652,472,248,18),
        Desk(230,326,140,56), Desk(670,326,140,56), Desk(470,280,100,52), Desk(470,430,100,52),
        Plant(432,526,32,32), Plant(576,190,32,32),
    },
    -- 6. T形错层办公室，80宽中央门洞；左下与右上需要不同绕行策略。
    {
        Wall(224,304,344,18), Wall(648,304,192,18), Wall(424,322,18,200),
        Wall(648,214,18,90), Wall(648,446,204,18),
        Desk(148,214,136,52), Desk(390,214,130,52), Server(760,218,76,54),
        Desk(160,422,154,52), Cabinet(514,420,44,82), Desk(750,526,132,44),
        Plant(868,350,40,40), Plant(340,542,40,40),
    },
    -- 7. 三列长机柜形成纵向巡检通道，错位端头连接上下横廊。
    {
        Server(260,242,60,222), Server(480,306,64,182), Server(704,222,64,242),
        Wall(384,222,160,18), Wall(608,530,236,18), Wall(132,506,188,18),
        Cabinet(108,314,60,76), Cabinet(856,314,60,76),
        Plant(380,430,40,40), Plant(596,276,40,40), Cabinet(606,410,36,46),
    },
    -- 8. 门厅/接待台/边侧小室组成中庭；四个入口彼此连通。
    {
        Wall(200,242,18,132), Wall(200,462,18,72), Wall(420,242,200,18),
        Wall(822,242,18,132), Wall(822,462,18,72), Wall(328,420,112,18), Wall(600,420,112,18),
        Plant(480,340,80,60), Desk(92,284,76,58), Desk(92,490,76,44),
        Desk(872,284,76,58), Desk(872,490,76,44),
        Cabinet(310,272,64,52), Cabinet(666,272,64,52), Desk(454,510,132,42),
    },
    -- 9. 档案边室+中央折返会议桌，底部门洞116，与顶部出口的路径绕过中央岛。
    {
        Wall(264,236,18,120), Wall(264,444,18,96), Wall(756,236,18,120), Wall(756,444,18,96),
        Wall(360,278,316,18), Wall(360,498,108,18), Wall(584,498,92,18), Desk(438,372,164,48),
        Cabinet(132,246,60,92), Cabinet(132,460,60,62), Cabinet(848,246,60,92), Cabinet(848,460,60,62),
        Server(664,194,64,44), Plant(332,550,36,36), Plant(676,550,36,36), Desk(340,194,104,28),
    },
    -- 10. 商店仍是安全房，但柜台、后侧隔断与边角补给柜都是实体。
    {
        Desk(150,258,208,58), Cabinet(136,416,100,92), Wall(386,232,18,144),
        Desk(704,266,172,58), Cabinet(778,440,104,52), Plant(280,536,40,40), Plant(720,536,40,40),
    },
    -- 11. 事件安全房：阅读区/茶水角，保持出口中轴开放。
    {
        Cabinet(164,236,56,168), Desk(298,282,134,60), Wall(298,432,134,18),
        Cabinet(820,236,56,168), Desk(608,282,134,60), Wall(608,432,134,18),
        Plant(252,512,40,40), Plant(748,512,40,40),
    },
    -- 12~14. 三个首领有不同边角掩体；不封死冲刺与弹幕的中轴。
    {
        Wall(144,264,128,18), Wall(144,264,18,124), Cabinet(182,446,96,58),
        Wall(768,264,128,18), Wall(878,264,18,124), Cabinet(762,446,96,58),
        Plant(306,216,36,36), Plant(698,532,36,36),
    },
    {
        Desk(144,266,150,64), Desk(746,266,150,64),
        Wall(280,414,18,112), Wall(742,414,18,112),
        Cabinet(144,468,78,52), Cabinet(818,468,78,52),
        Plant(310,202,36,36), Plant(694,202,36,36),
    },
    {
        Server(144,248,64,124), Server(832,248,64,124),
        Wall(208,354,112,18), Wall(720,354,112,18),
        Desk(166,474,146,56), Desk(728,474,146,56),
        Plant(310,212,36,36), Plant(694,212,36,36), Cabinet(126,552,60,30), Cabinet(854,552,60,30),
    },
}

-- 门洞内净宽96，视觉外框112；门底边就是脚下触发线，不再另放假门。
-- y174..222为接近区：布局3从档案柜间104宽通道接近，其余沿各自北侧横廊。
local EXIT_X = { 520, 440, 340, 600, 440, 600, 600, 520, 520, 520, 520, 520, 520, 520 }

---@class CampaignExit
---@field x number 视觉外框左上角
---@field y number 视觉外框左上角
---@field w number
---@field h number
---@field triggerX number 门槛圆心；玩家脚下坐标
---@field triggerY number 门槛圆心，同时等于y+h
---@field radius number
---@field side string
---@field clearance number 内门洞净宽

---@param layout integer
---@return CampaignExit
local function RoomExit(layout)
    local x, thresholdY = EXIT_X[layout] or 520, 174
    return { x = x - 56, y = thresholdY - 160, w = 112, h = 160,
        triggerX = x, triggerY = thresholdY, radius = 30, side = "north", clearance = 96 }
end

---@class CampaignRoom
---@field exit CampaignExit
---@field spawn {x: number, y: number}
---@field id integer
---@field name string
---@field kind string
---@field next integer[]
---@field col integer
---@field row integer
---@field layout integer
---@field layoutName string
---@field visited boolean
---@field cleared boolean

---@param floor integer
---@return CampaignRoom[]
function Campaign.Build(floor)
    local names = {
        { "打卡大厅", "需求工位", "卷王小组", "摸鱼补给站", "茶水间传闻", "打印机走廊", "甩锅专案组", "同事考核室" },
        { "会议前厅", "周报会议室", "绩效评审室", "摸鱼补给站", "匿名意见箱", "线上会议间", "紧急复盘室", "主管办公室" },
        { "高层接待厅", "画饼展览室", "融资冲刺组", "摸鱼补给站", "神秘劳动合同", "资本走廊", "末位淘汰室", "老板会客厅" },
    }
    local kinds = { "combat", "combat", "elite", "shop", "event", "combat", "elite", "boss" }
    local links = { { 2, 3 }, { 4 }, { 4 }, { 5 }, { 6, 7 }, { 8 }, { 8 }, {} }
    local cols, rows = { 1, 2, 2, 3, 4, 5, 5, 6 }, { 2, 1, 3, 2, 2, 1, 3, 2 }
    local slots = { 1, 2, 3, 1, 1, 4, 5, 1 }
    local rooms = {}
    for i = 1, 8 do
        local layout = ((floor - 1) * 3 + slots[i] - 1) % Campaign.combatLayoutCount + 1
        if kinds[i] == "shop" then layout = 10
        elseif kinds[i] == "event" then layout = 11
        elseif kinds[i] == "boss" then layout = 11 + floor end
        rooms[i] = { id = i, name = names[floor][i], kind = kinds[i], next = links[i],
            col = cols[i], row = rows[i], layout = layout, layoutName = Campaign.layoutNames[layout],
            exit = RoomExit(layout), spawn = { x = 520, y = 580 }, visited = false, cleared = false }
    end
    return rooms
end

-- 保留旧名：并非只含桌子，供旧绘制方兼容；不要按房间种类返回临时空数组。
---@param room CampaignRoom
---@return table[]
function Campaign.Desks(room)
    return Campaign.layouts[room.layout] or Campaign.layouts[1]
end
Campaign.Obstacles = Campaign.Desks
Campaign.kindNames = { combat = "战斗", elite = "精英", shop = "商店", event = "事件", boss = "首领" }
Campaign.kindColors = { combat = "teal", elite = "pink", shop = "gold", event = "purple", boss = "pink" }
return Campaign
