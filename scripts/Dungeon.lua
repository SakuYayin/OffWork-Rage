-- 《下班！别拦我》S4 程序化地牢生成器（04-dungeon.md 的减半版）
-- =====================================================================================
-- 契约（Lead 已按此接线，签名与字段一字不能改）：
--   Dungeon.USE_DUNGEON = false                     灰度开关，默认关；验收后才翻 true
--   Dungeon.Generate(floor, seed) -> rooms[]         与 Campaign.Build(floor) 同构的房间数组
--   Dungeon.Count(floor) -> integer                  该层房间数
--   Dungeon.RoomExit(layout) -> exit                 与 Campaign.RoomExit 同构（Campaign 里是 local，这里复制一份）
--   Dungeon.DefaultSeed(floor) -> number             floor 缺省 seed（确定性，不用 math.random）
--   Dungeon.RandomSeed(floor)  -> number             每局不同的 seed（可选，需要每局换图时传它）
--   Dungeon.Probe(floor, seed) -> table               调试统计（房间数/kind 分布/耗时），不缓存
--
-- 房间数（减半口径）：Count(1)=8（tests/Smoke.lua:43 硬断言 #g.rooms==8）、Count(2)=10、
--   Count(3)=12、Count(floor>=4)=min(14, 12+(floor-3)*2)。
--
-- 生成步骤（纯网格运算，不碰碰撞图）：
--   ① 6×3 网格随机生长出 N 个格（起始格 col=1,row=2，62% 概率优先向右扩张）
--   ② 生成树 + 1~2 条回路 → 按 BFS 深度定向成有向图（只允许朝更深的方向走，永不回头）
--   ③ 连通性校验：正向从 1 可达所有房、反向所有房都能走到 Boss；缺边的就地补边后复检
--   ④ Boss = 离起点最远的死路（深度优先，其次树度=1，再其次最右）
--   ⑤ kind 分配：起点 combat、Boss boss、主路径上每隔约 1/3、2/3 放 shop/event、其余 combat，
--      再把 1~2 个 combat 升成 elite
--   ⑥ layout 分配：复用 Campaign.Build 的旧公式（shop=10 / event=11 / boss=11+floor）+
--      战斗房 ((floor-1)*3 + slot - 1) % Campaign.combatLayoutCount + 1
--
-- 硬约束（不要改）：
--   * 禁止调用 Navigation.Graph / Navigation.New / Navigation.Project。实测 Graph 单房 72ms，
--     13 房 940ms，会直接卡死生成。这里的连通性只按网格坐标算。
--   * 禁止依赖 Draw / Art / UI / UISkin / InterfaceScale / Audio（本文件要能在纯 node 里被 require）。
--   * 不用 math.random：Game.lua 刷怪/粒子已占用全局随机态，且会让同 seed 不可复现。
--     这里自带 Park–Miller（全浮点运算，规避 fengari 的 32 位整数回绕）。
--   * exit.y + exit.h == exit.triggerY 必须恒成立（tests/Smoke.lua:135 断言）。
--
-- TODO（本轮不做，接口已预留）：四向门。现在只生成北向单门 side="north"；
--   改四向时给 room 追加 doorway 数组（side 取值 north/south/west/east），
--   exit 仍保留北门那份做兜底，Game.GetExit 优先读 doorway。
-- =====================================================================================
local Campaign = require("Campaign")

local Dungeon = {}

-- 灰度开关：Lead 验收后才翻 true。false 时 Game.BuildRooms 走 Campaign.Build，与原版逐字节一致。
Dungeon.USE_DUNGEON = false

-- ============================================================ 常量（与 Campaign.lua 对齐）
-- 出生点：三张图都可达的固定点，Game.GetSpawn 会再投影一次。
local SPAWN_X, SPAWN_Y = 520, 580
-- 门洞：宽 112 高 160，门槛线 y=174（Campaign.lua:152-156 的 RoomExit 常量）。
local DOOR_W, DOOR_H = 112, 160
local THRESHOLD_Y = 174
-- 14 张布局的北门 x 坐标表（Campaign.lua:137 的 EXIT_X 是 local，这里原样复制，改布局必须两处同步）。
local EXIT_X = { 520, 440, 340, 600, 440, 600, 600, 520, 520, 520, 520, 520, 520, 520 }
-- 特殊房固定布局（Campaign.Build 的特例，照抄，否则美术图对不上）。
local SHOP_LAYOUT, EVENT_LAYOUT, BOSS_LAYOUT_BASE = 10, 11, 11
-- 网格尺寸：CampaignUI.lua:127-131 的路线图锁死 6 列 3 行，超出的 col/row 会把节点画到容器外。
-- Dungeon.RandomSeed 的自增计数（模块级，跨调用递增）
local RUN_SEQ = 0
local GRID_COLS, GRID_ROWS = 6, 3
local START_COL, START_ROW = 1, 2
-- 失败重试：3 次，每次换派生 seed（TryOnce 对同 seed 是确定性的，不换 seed 必重蹈覆辙）。
local MAX_ATTEMPTS = 3
local SEED_STEP = 104729
-- Park–Miller 模数（2^31-1）。求和/取模全程用浮点，避免 int*int 回绕。
local PM_MOD = 2147483647.0

-- 房名池：按 kind 取名，不走索引（因为 id 是 BFS 顺序，与旧固定表不再对应）。
local NAME_POOL = {
    {
        combat = { "打卡大厅", "需求工位", "卷王小组", "打印机走廊", "甩锅专案组", "临时隔间", "加班角" },
        event = "茶水间传闻", boss = "同事考核室",
    },
    {
        combat = { "会议前厅", "周报会议室", "绩效评审室", "线上会议间", "紧急复盘室", "备用会议室" },
        event = "匿名意见箱", boss = "主管办公室",
    },
    {
        combat = { "高层接待厅", "画饼展览室", "融资冲刺组", "资本走廊", "末位淘汰室", "杂物走廊" },
        event = "神秘劳动合同", boss = "老板会客厅",
    },
}
local SHOP_NAME = "摸鱼补给站"

-- ============================================================ 种子随机（Park–Miller）
-- 为什么不用 math.random：① Game.lua:849 刷怪、粒子都在用它，污染全局态；
-- ② 无法做到同 seed 同层一致（回归测试要求可复现）；③ fengari 的 math.random 实现与 PUC 不同。
local function NormalizeSeed(seed)
    local s = tonumber(seed) or 0
    if s ~= s then s = 0 end -- NaN
    s = math.floor(math.abs(s))
    -- 1..2^31-2，避开 0 与全 0 退化态
    return s % 2147483646.0 + 1.0
end

local function RandNew(seed)
    local self = { state = NormalizeSeed(seed) }
    -- 空转 3 次：让相邻 seed（如 floor*1000+12345 的邻居）拉开分布，避免首格雷同。
    for _ = 1, 3 do
        self.state = (self.state * 16807.0) % PM_MOD
    end
    return self
end

local function Next(rand)
    rand.state = (rand.state * 16807.0) % PM_MOD
    return rand.state
end

---@return integer 闭区间 [lo, hi] 内的整数
local function Range(rand, lo, hi)
    local span = hi - lo + 1
    if span <= 1 then return lo end
    local t = Next(rand) - 1.0 -- 0 .. PM_MOD-2
    local v = lo + math.floor(t / PM_MOD * span)
    if v > hi then v = hi end
    return v
end

local function Chance(rand, p)
    return Next(rand) < p * PM_MOD
end

-- ============================================================ 房间数曲线
---@param floor integer
---@return integer
function Dungeon.Count(floor)
    floor = math.floor(tonumber(floor) or 1)
    if floor < 1 then floor = 1 end
    if floor == 1 then return 8 end
    if floor == 2 then return 10 end
    if floor == 3 then return 12 end
    return math.min(14, 12 + (floor - 3) * 2)
end

---@param floor integer
---@return number
function Dungeon.DefaultSeed(floor)
    floor = math.floor(tonumber(floor) or 1)
    if floor < 1 then floor = 1 end
    return floor * 1000 + 12345
end

--- 每局不同的 seed。缺省 seed（DefaultSeed）是确定性常量，所以同层永远是同一张图——
--- 想要「每把都不一样」就必须由 Game.New 显式传一个随机 seed，这里提供这个值。
--- 只用 os.time + 进程内自增计数，不碰 math.random（避免污染 Game.lua 的刷怪随机态）。
---@param floor integer
---@return number
function Dungeon.RandomSeed(floor)
    floor = math.floor(tonumber(floor) or 1)
    if floor < 1 then floor = 1 end
    RUN_SEQ = RUN_SEQ + 1
    local t = 0
    if os and os.time then
        local ok, v = pcall(os.time)
        if ok and type(v) == "number" then t = v + 0.0 end
    end
    -- 全浮点：t 可到 1.7e9，乘 1.0 后不进 32 位整数域。
    return NormalizeSeed(t * 1.0 + RUN_SEQ * 7919.0 + floor * 104729.0)
end

-- ============================================================ exit 表
-- 与 Campaign.lua:152-156 的 RoomExit 逐字段同构；不同点是 Campaign 里那份是 local，无法复用。
---@param layout integer
---@return table
function Dungeon.RoomExit(layout)
    local x = EXIT_X[layout] or 520
    return {
        x = x - DOOR_W / 2, y = THRESHOLD_Y - DOOR_H, w = DOOR_W, h = DOOR_H,
        triggerX = x, triggerY = THRESHOLD_Y, radius = 30, side = "north", clearance = 96,
    }
end

-- ============================================================ ① 网格生长
-- 6×3=18 格上限，Count 最多 14，一定能放下；生长用前沿扩张，天然保证「每个新格都与已有格相邻」，
-- 所以从起点出发一定连通（BFS 复检只是防御）。
local function CellKey(col, row) return row * 8 + col end -- 8 > GRID_COLS，行间不撞键

local function CellOf(occupied, col, row)
    if col < 1 or col > GRID_COLS or row < 1 or row > GRID_ROWS then return nil end
    return occupied[CellKey(col, row)]
end

local function Grow(rand, target)
    local cells, occupied = {}, {}
    local function Add(col, row, from)
        if col < 1 or col > GRID_COLS or row < 1 or row > GRID_ROWS then return nil end
        local k = CellKey(col, row)
        if occupied[k] then return nil end
        local idx = #cells + 1
        occupied[k] = idx
        cells[idx] = { col = col, row = row, parent = from }
        return idx
    end
    Add(START_COL, START_ROW, 0)
    local dirs = { { 1, 0 }, { 0, 1 }, { 0, -1 }, { -1, 0 } }
    while #cells < target do
        -- 前沿：与已占格四邻、且未占用的格子
        local cands, bestCol = {}, 0
        for i = 1, #cells do
            local c = cells[i]
            for d = 1, 4 do
                local nc, nr = c.col + dirs[d][1], c.row + dirs[d][2]
                if nc >= 1 and nc <= GRID_COLS and nr >= 1 and nr <= GRID_ROWS and not occupied[CellKey(nc, nr)] then
                    cands[#cands + 1] = { nc, nr, i }
                    if nc > bestCol then bestCol = nc end
                end
            end
        end
        if #cands == 0 then break end
        local pool = cands
        -- 向右推进：62% 概率只在「最靠右的候选列」里挑，让 Boss 自然落在右侧
        if bestCol > 0 and Chance(rand, 0.62) then
            pool = {}
            for i = 1, #cands do
                if cands[i][1] == bestCol then pool[#pool + 1] = cands[i] end
            end
        end
        local pick = pool[Range(rand, 1, #pool)]
        Add(pick[1], pick[2], pick[3])
    end
    return cells, occupied
end

-- ============================================================ ② 图结构：树 + 回路
local function Has(list, v)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

local function BuildAdjacency(rand, cells, occupied)
    local n = #cells
    local adj, treeDeg = {}, {}
    for i = 1, n do adj[i], treeDeg[i] = {}, 0 end
    local function Join(a, b)
        if Has(adj[a], b) then return end
        adj[a][#adj[a] + 1] = b
        adj[b][#adj[b] + 1] = a
        treeDeg[a], treeDeg[b] = treeDeg[a] + 1, treeDeg[b] + 1
    end
    for i = 2, n do Join(cells[i].parent, i) end
    -- 回路候选：相邻但树上没直连的格子（只查右/下两个方向，避免重复）
    local cands = {}
    for i = 1, n do
        local c = cells[i]
        local right = CellOf(occupied, c.col + 1, c.row)
        local down = CellOf(occupied, c.col, c.row + 1)
        if right and not Has(adj[i], right) then cands[#cands + 1] = { i, right } end
        if down and not Has(adj[i], down) then cands[#cands + 1] = { i, down } end
    end
    local loops = math.min(#cands, Range(rand, 1, 2))
    for _ = 1, loops do
        if #cands == 0 then break end
        local k = Range(rand, 1, #cands)
        Join(cands[k][1], cands[k][2])
        table.remove(cands, k)
    end
    return adj, treeDeg
end

-- 按 BFS 深度定向：只允许走向深度更大的格（同深度按 col/row 字典序），保证永不回头、无环。
local function Orient(n, adj, depth, cells)
    local out, inn = {}, {}
    for i = 1, n do out[i], inn[i] = {}, {} end
    for i = 1, n do
        for _, j in ipairs(adj[i]) do
            if i < j then
                local a, b = i, j
                local swap = depth[a] > depth[b]
                if depth[a] == depth[b] then
                    if cells[a].col > cells[b].col
                        or (cells[a].col == cells[b].col and cells[a].row > cells[b].row) then swap = true end
                end
                if swap then a, b = b, a end
                out[a][#out[a] + 1] = b
                inn[b][#inn[b] + 1] = a
            end
        end
    end
    return out, inn
end

local function Bfs(n, adj, startId)
    local depth, order, parent = {}, {}, {}
    depth[startId] = 0
    order[1] = startId
    local head = 1
    while head <= #order do
        local id = order[head]
        head = head + 1
        for _, nb in ipairs(adj[id]) do
            if depth[nb] == nil then
                depth[nb] = depth[id] + 1
                parent[nb] = id
                order[#order + 1] = nb
            end
        end
    end
    return depth, order, parent
end

-- Boss：离起点最远；同深度优先死路（树度=1），再其次最右、最上。
local function PickBoss(n, cells, depth, treeDeg)
    local best, bestScore = nil, -1
    for i = 2, n do
        local d = depth[i] or 0
        local score = d * 1000 + (treeDeg[i] == 1 and 100 or 0) + cells[i].col * 10 - cells[i].row
        if score > bestScore then best, bestScore = i, score end
    end
    return best
end

-- 收口（Bridge）：保证「每个房间都能走到 Boss」。
-- 为什么必须有这一步：按深度定向只能保证「起点能到所有房」（每条树边都从浅指向深），
-- 但走到底可能停在一条岔路的尽头——那是死路而不是 Boss 房，玩家会卡死。
-- 做法：所有没有出边的非 Boss 房，补一条直通 Boss 的边。
-- 为什么不会成环：定向用的键是 (depth, col, row) 的严格字典序，越走键越大，本身就是 DAG；
-- 而 Boss 恒为汇点（出边被清空），所以任何「x → Boss」都不可能被 Boss 反向走到。
local function Bridge(n, out, inn, bossId, cells, depth)
    local added = 0
    for i = 1, n do
        if i ~= bossId and #out[i] == 0 then
            -- 优先连「深一层里离自己最近」的房，路线图上的连线才短；找不到才直连 Boss。
            local best, bestDist
            local want = (depth[i] or 0) + 1
            for j = 1, n do
                if j ~= i and j ~= bossId and (depth[j] or 0) == want and not Has(out[j], i) then
                    local d = math.abs(cells[j].col - cells[i].col) + math.abs(cells[j].row - cells[i].row)
                    if not bestDist or d < bestDist then best, bestDist = j, d end
                end
            end
            local target = best or bossId
            out[i][#out[i] + 1] = target
            inn[target][#inn[target] + 1] = i
            added = added + 1
        end
    end
    return added <= n
end

-- ============================================================ ⑤ kind 分配
local function AssignKinds(rand, n, bossId, path, depth)
    local kinds = {}
    for i = 1, n do kinds[i] = "combat" end
    kinds[bossId] = "boss"
    local L = #path
    local onPath = {}
    for _, id in ipairs(path) do onPath[id] = true end

    -- shop / event 优先放主路径（保证从起点一定经过），主路径太短就退回「离起点最近的空房」。
    local function Place(kind, ratio)
        if L >= 4 then
            local idx = math.floor(L * ratio + 0.5)
            for step = 0, L do
                local a, b = idx + step, idx - step
                if a >= 2 and a <= L - 1 and kinds[path[a]] == "combat" then kinds[path[a]] = kind; return true end
                if b >= 2 and b <= L - 1 and kinds[path[b]] == "combat" then kinds[path[b]] = kind; return true end
            end
        end
        local best, bestScore
        for i = 2, n do
            if i ~= bossId and kinds[i] == "combat" then
                local score = -((depth[i] or 0) * 10 + (onPath[i] and 5 or 0))
                if not bestScore or score > bestScore then best, bestScore = i, score end
            end
        end
        if best then kinds[best] = kind; return true end
        return false
    end
    Place("shop", 0.32)
    Place("event", 0.66)

    -- elite：优先分支房（非主路径），数量随房间数 1~2
    local pool = {}
    for i = 2, n do
        if kinds[i] == "combat" then pool[#pool + 1] = i end
    end
    table.sort(pool, function(a, b)
        local oa, ob = onPath[a] and 1 or 0, onPath[b] and 1 or 0
        if oa ~= ob then return oa < ob end
        local da, db = depth[a] or 0, depth[b] or 0
        if da ~= db then return da > db end
        return a < b
    end)
    local elites = n >= 10 and 2 or 1
    for i = 1, math.min(elites, #pool) do kinds[pool[i]] = "elite" end
    return kinds, onPath
end

-- ============================================================ ⑥ layout / 房名
local function AssignLayout(rand, floor, room, used)
    if room.kind == "shop" then
        room.layout = SHOP_LAYOUT
    elseif room.kind == "event" then
        room.layout = EVENT_LAYOUT
    elseif room.kind == "boss" then
        -- 旧公式 11+floor，floor>=4 会越过 14 张表，夹紧
        room.layout = math.min(#Campaign.layoutNames, BOSS_LAYOUT_BASE + floor)
    else
        -- 战斗/精英：沿用「(floor-1)*3 + slot - 1 再绕回 9 张」的旧公式骨架，
        -- 但 slot 改由 used 计数决定：优先挑这一层用得最少的布局，同层重复度从最坏 6 次降到 ≤2 次。
        local slots = Campaign.combatLayoutCount or 9
        local base = ((floor - 1) * 3) % slots
        local best, bestUse = nil, nil
        for k = 0, slots - 1 do
            local cand = (base + k) % slots + 1
            local use = used[cand] or 0
            if not bestUse or use < bestUse then best, bestUse = cand, use end
        end
        -- 平手时用随机数挑一个，避免每层都是同一顺序
        if best then
            local ties = {}
            for k = 0, slots - 1 do
                local cand = (base + k) % slots + 1
                if (used[cand] or 0) == bestUse then ties[#ties + 1] = cand end
            end
            best = ties[Range(rand, 1, #ties)]
        end
        room.layout = best or (base + 1)
        used[room.layout] = (used[room.layout] or 0) + 1
    end
    if type(room.layout) ~= "number" then room.layout = 1 end
    room.layout = math.floor(room.layout)
    if room.layout < 1 then room.layout = 1 end
    room.layoutName = Campaign.layoutNames[room.layout] or Campaign.layoutNames[1]
    room.exit = Dungeon.RoomExit(room.layout)
end

-- 战斗/精英共用名字池，用计数器顺序取，保证同一层内不重名（同名房间在路线图与小地图上无法区分）。
local function AssignName(floor, room, counters)
    local pool = NAME_POOL[math.min(floor, #NAME_POOL)]
    if room.kind == "shop" then
        room.name = SHOP_NAME
    elseif room.kind == "event" then
        room.name = pool.event
    elseif room.kind == "boss" then
        room.name = pool.boss
    else
        local list = pool.combat
        counters.combat = (counters.combat or 0) + 1
        -- 房间数超过池子（14 房最多 11 个战斗房，池子 6~7 条）时加序号后缀，仍然可区分。
        local idx = (counters.combat - 1) % #list + 1
        local round = math.floor((counters.combat - 1) / #list)
        room.name = round > 0 and (list[idx] .. tostring(round + 1)) or list[idx]
    end
end

-- ============================================================ 编号对齐旧约定
-- Campaign.Build 的固定编号是「4=商店、5=事件、末位=首领」，main.lua/CampaignUI 的文案与
-- tests/Menu.lua:152、tests/Smoke.lua:103 的 Travel 索引都按这个约定写的。
-- 这里做一次纯重标号（只改 id 与 next 里的引用，拓扑一字不动），把 shop 指派到 4、event 指派到 5，
-- 把翻灰度开关时要改的旧测试降到最少。n 恒 >= 8，4/5 一定存在。
local function RemapLegacy(rooms, n)
    local perm = {}
    for i = 1, n do perm[i] = i end
    local function holderOf(newId)
        for o = 1, n do if perm[o] == newId then return o end end
    end
    local function assign(oldId, wantNew)
        if not oldId or wantNew > n then return end
        local cur = perm[oldId]
        if cur == wantNew then return end
        local holder = holderOf(wantNew)
        perm[oldId], perm[holder] = wantNew, cur
    end
    local function findKind(kind)
        for i = 1, n do if rooms[i].kind == kind then return i end end
    end
    assign(findKind("shop"), 4)
    assign(findKind("event"), 5)
    local out = {}
    for oldId = 1, n do out[perm[oldId]] = rooms[oldId] end
    for newId = 1, n do
        local room = out[newId]
        room.id = newId
        local nextIds = {}
        for _, old in ipairs(room.next) do nextIds[#nextIds + 1] = perm[old] end
        table.sort(nextIds)
        room.next = nextIds
    end
    return out, perm
end

-- ============================================================ 校验
local function Verify(rooms, bossId)
    local n = #rooms
    if n < 2 or not rooms[bossId] then return false end
    local inn = {}
    for i = 1, n do inn[i] = {} end
    for i = 1, n do
        local room = rooms[i]
        if type(room.next) ~= "table" or type(room.exit) ~= "table" then return false end
        if room.exit.y + room.exit.h ~= room.exit.triggerY then return false end
        if room.exit.side ~= "north" then return false end
        if room.kind ~= "combat" and room.kind ~= "elite" and room.kind ~= "shop"
            and room.kind ~= "event" and room.kind ~= "boss" then return false end
        if room.kind == "boss" and i ~= bossId then return false end
        for _, id in ipairs(room.next) do
            if not rooms[id] or id == i then return false end
            inn[id][#inn[id] + 1] = i
        end
    end
    if #rooms[bossId].next ~= 0 then return false end
    -- 正向：1 号可达全部
    local seen, queue, head = { [1] = true }, { 1 }, 1
    while head <= #queue do
        local id = queue[head]
        head = head + 1
        for _, nx in ipairs(rooms[id].next) do
            if not seen[nx] then seen[nx] = true; queue[#queue + 1] = nx end
        end
    end
    if #queue ~= n then return false end
    -- 反向：全部可达 Boss
    local reach, stack = { [bossId] = true }, { bossId }
    while #stack > 0 do
        local id = table.remove(stack)
        for _, p in ipairs(inn[id]) do
            if not reach[p] then reach[p] = true; stack[#stack + 1] = p end
        end
    end
    for i = 1, n do if not reach[i] then return false end end
    return true
end

-- ============================================================ 单次生成（确定性）
---@return table[]|nil
local function TryOnce(floor, seed)
    local target = Dungeon.Count(floor)
    local rand = RandNew(seed)
    local cells, occupied = Grow(rand, target)
    local n = #cells
    if n < target then return nil end

    local adj, treeDeg = BuildAdjacency(rand, cells, occupied)
    local depth, order, parent = Bfs(n, adj, 1)
    if #order ~= n then return nil end -- 防御：生长天然连通，这里不会触发

    local bossCell = PickBoss(n, cells, depth, treeDeg)
    if not bossCell or bossCell == 1 then return nil end

    -- 重新编号为 id = BFS 顺序（id 1 = 起点，深度大致递增，路线图连线更好看）；
    -- 再把 Boss 挪到末位，与 Campaign.Build 的「第 8 间是首领」口径一致。
    local idOrder = {}
    for pos = 1, n do
        if order[pos] ~= bossCell then idOrder[#idOrder + 1] = order[pos] end
    end
    idOrder[#idOrder + 1] = bossCell
    local idOf = {}
    for pos = 1, n do idOf[idOrder[pos]] = pos end
    order = idOrder

    local out, inn = Orient(n, adj, depth, cells)
    if not Bridge(n, out, inn, bossCell, cells, depth) then return nil end
    -- Boss 必须是终点：同深度回路边可能从 Boss 指出去（Orient 的同深度字典序规则），
    -- 这里硬性剥掉，语义上 Boss 房也确实没有下一站。
    for _, j in ipairs(out[bossCell]) do
        for k = #inn[j], 1, -1 do
            if inn[j][k] == bossCell then table.remove(inn[j], k) end
        end
    end
    out[bossCell] = {}

    -- 主路径：从 Boss 沿 BFS 父指针回溯到起点，反转
    local path = {}
    local cur = bossCell
    while cur and cur ~= 0 do
        path[#path + 1] = cur
        cur = parent[cur]
    end
    for i = 1, math.floor(#path / 2) do
        path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
    end
    if path[1] ~= 1 then return nil end

    local kinds = AssignKinds(rand, n, bossCell, path, depth)
    local bossId = idOf[bossCell]

    local rooms, used = {}, {}
    for pos = 1, n do
        local cellIdx = order[pos]
        local nextIds = {}
        for _, c in ipairs(out[cellIdx]) do nextIds[#nextIds + 1] = idOf[c] end
        table.sort(nextIds)
        local cell = cells[cellIdx]
        local room = {
            id = pos,
            name = "",
            kind = kinds[cellIdx],
            next = nextIds,
            col = cell.col,
            row = cell.row,
            layout = 1,
            layoutName = Campaign.layoutNames[1],
            exit = nil,
            spawn = { x = SPAWN_X, y = SPAWN_Y },
            visited = false,
            cleared = false,
        }
        AssignLayout(rand, floor, room, used)
        rooms[pos] = room
    end
    -- 重标号（4=商店 / 5=事件），Boss 仍在末位；bossId 跟着映射一起换。
    local perm
    rooms, perm = RemapLegacy(rooms, n)
    bossId = perm[bossId] or n

    -- 房名单独一轮（rooms 已按 id 排好，计数器天然递增；放在同轮里会因为 rand 消耗顺序不同而不稳）。
    local counters = {}
    for pos = 1, n do
        AssignName(floor, rooms[pos], counters)
    end

    if not Verify(rooms, bossId) then return nil end
    return rooms
end

-- ============================================================ 对外入口
--- 程序化生成一层地牢。同 (floor, seed) 必返回完全相同的房间表。
--- 失败最多重试 3 次（每次换派生 seed），仍失败回退 Campaign.Build，绝不抛异常。
---@param floor integer
---@param seed number? 省略时用 Dungeon.DefaultSeed(floor)
---@return table[] rooms 与 Campaign.Build(floor) 同构
function Dungeon.Generate(floor, seed)
    floor = math.floor(tonumber(floor) or 1)
    if floor < 1 then floor = 1 end
    local base = NormalizeSeed(seed ~= nil and seed or Dungeon.DefaultSeed(floor))
    for attempt = 0, MAX_ATTEMPTS - 1 do
        local rooms = TryOnce(floor, base + attempt * SEED_STEP)
        if rooms then return rooms end
    end
    -- 兜底：Campaign.Build 只认 1..3 层，更高层用它也没意义，直接给第 3 层保证不报错。
    local ok, fallback = pcall(Campaign.Build, floor)
    if ok and fallback then return fallback end
    local ok2, safe = pcall(Campaign.Build, 3)
    if ok2 and safe then return safe end
    return Campaign.Build(1)
end

--- 调试用：返回一次性统计（房间数 / kind 分布 / 生成耗时），不缓存、不影响 Generate。
---@param floor integer
---@param seed number?
---@return table
function Dungeon.Probe(floor, seed)
    local t0 = os.clock()
    local rooms = Dungeon.Generate(floor, seed)
    local scale = { combat = 0, elite = 0, shop = 0, event = 0, boss = 0 }
    local edges = 0
    for _, room in ipairs(rooms) do
        scale[room.kind] = (scale[room.kind] or 0) + 1
        edges = edges + #room.next
    end
    return {
        floor = floor, count = #rooms, ms = (os.clock() - t0) * 1000,
        combat = scale.combat, elite = scale.elite, shop = scale.shop,
        event = scale.event, boss = scale.boss, edges = edges,
    }
end

return Dungeon
