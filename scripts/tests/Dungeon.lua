-- 地牢生成回归（S4）。契约：Dungeon.lua 头注释硬约束 + docs/design/04-dungeon.md（07-halved-plan.md §2.10）：
--   房间数 count(floor)={8,10,12}[floor]；同 seed 完全一致；exit.y+h==triggerY（tests/Smoke.lua:135 口径）；
--   生成期禁调 Navigation.Graph -> 用耗时 <30ms 代理断言（Dungeon.lua:8 实测 Graph 单房 72.3ms / 13 房 940ms）。
-- 【按最终契约写，允许先红】S4 未落地时 Generate 直通 Campaign.Build（恒 8 间）：
--   层 2/3 房间数两条当前会红，其余断言对直通壳同样成立。
local Dungeon = require("Dungeon")

local M = {}
local pass, fail = 0, 0

local function ok(cond, label)
    if cond then pass = pass + 1
    else
        fail = fail + 1
        print("  FAIL " .. label)
    end
end

local function eq(actual, expected, label)
    if actual == expected then pass = pass + 1
    else
        fail = fail + 1
        print(string.format("  FAIL %s: got %s want %s", label, tostring(actual), tostring(expected)))
    end
end

-- 1/2. 房间数
local function CountChecks()
    eq(#Dungeon.Generate(1, 12345), 8, "Generate(1) 8 间（tests/Smoke.lua:43 口径）")
    -- 最终契约 {8,10,12}[floor]：直通壳恒 8，S4 落地后转绿。
    eq(#Dungeon.Generate(2, 1), 10, "Generate(2) 10 间（最终契约）")
    eq(#Dungeon.Generate(3, 1), 12, "Generate(3) 12 间（最终契约）")
end

-- 3. 同 seed 两次调用逐房间一致
local function DeterminismChecks()
    local a = Dungeon.Generate(1, 12345)
    local b = Dungeon.Generate(1, 12345)
    eq(#a, #b, "同 seed 房间数一致")
    local fields = { "id", "kind", "layout" }
    local n = math.min(#a, #b)
    for i = 1, n do
        for _, f in ipairs(fields) do
            eq(a[i][f], b[i][f], string.format("复现 房%d.%s", i, f))
        end
        local na, nb = a[i].next or {}, b[i].next or {}
        eq(#na, #nb, string.format("复现 房%d.next 长度", i))
        for k = 1, math.min(#na, #nb) do
            eq(na[k], nb[k], string.format("复现 房%d.next[%d]", i, k))
        end
        ok(a[i].exit ~= nil and b[i].exit ~= nil and a[i].exit.triggerX == b[i].exit.triggerX,
            string.format("复现 房%d.exit.triggerX", i))
    end
end

-- 4-7. 结构形状
local function ShapeChecks()
    local rooms = Dungeon.Generate(1, 12345)
    -- 4. 每房有 exit 表，门底边与门槛一致（tests/Smoke.lua:135 同口径）
    for i = 1, #rooms do
        local e = rooms[i].exit
        ok(e ~= nil, string.format("房%d 有 exit 表", i))
        if e ~= nil then
            eq(e.y + e.h, e.triggerY, string.format("房%d exit.y+h==triggerY", i))
        end
    end
    -- 5. 图连通：从 rooms[1] 沿 next 全可达
    local seen = { [1] = true }
    local queue, head = { 1 }, 1
    while queue[head] do
        local room = rooms[queue[head]]
        head = head + 1
        for _, nid in ipairs(room.next or {}) do
            if not seen[nid] then
                seen[nid] = true
                queue[#queue + 1] = nid
            end
        end
    end
    for i = 1, #rooms do
        ok(seen[i] == true, string.format("连通 房%d", i))
    end
    -- 6. kind 组成：恰好 1 boss、>=1 shop、>=1 event
    local boss, shop, event = 0, 0, 0
    for i = 1, #rooms do
        local k = rooms[i].kind
        if k == "boss" then boss = boss + 1
        elseif k == "shop" then shop = shop + 1
        elseif k == "event" then event = event + 1 end
    end
    eq(boss, 1, "恰好 1 个 boss 房")
    ok(shop >= 1, "至少 1 个 shop 房")
    ok(event >= 1, "至少 1 个 event 房")
    -- 7. 所有 next 引用都在 1..#rooms
    for i = 1, #rooms do
        for _, nid in ipairs(rooms[i].next or {}) do
            ok(type(nid) == "number" and nid >= 1 and nid <= #rooms and nid % 1 == 0,
                string.format("房%d.next[%s] 在 1..%d", i, tostring(nid), #rooms))
        end
    end
end

-- 8. 生成耗时（Navigation.Graph 的代理断言）
local function PerfChecks()
    if os and os.clock then
        local t0 = os.clock()
        Dungeon.Generate(2, 7)
        local ms = (os.clock() - t0) * 1000.0
        ok(ms < 30.0, string.format("Generate(2) 耗时 %.2fms < 30ms", ms))
    else
        print("  SKIP 无 os.clock，跳过耗时断言")
    end
end

-- ------------------------------------------------------------------ 入口
function M.Run()
    pass, fail = 0, 0
    CountChecks()
    DeterminismChecks()
    ShapeChecks()
    PerfChecks()
    print(string.format("[Dungeon] %d passed, %d failed", pass, fail))
    if fail > 0 then
        error(string.format("Dungeon: %d assertions failed（含层2/3房间数两条最终契约，S4 落地前预期红）", fail), 0)
    end
    if pass < 60 then error(string.format("Dungeon: 断言数 %d 少于 60", pass), 0) end
    return true
end

local function Start() return M.Run() end
M.Start = Start

return M
