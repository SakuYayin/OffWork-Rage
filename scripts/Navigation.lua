-- 无引擎依赖：统一障碍查询、连续碰撞、网格寻路与可达出生点。
--
--    圆心路径 A -------------> B           墙/家具 AABB
--                         r  +--------------------+
--    扫掠先碰外扩边界          | x,y       w        | h
--                            +--------------------+
-- 设计：玩家r12，普通敌人r12/13/17，Boss r24，经验r4，子弹r4/6。
-- 固定边界[48,992]x[142,628]；细墙18，门洞>=80。移动按轴做圆/AABB
-- 连续截断，再以<=6的小步滑动；极端击退/冲刺也不能跳过薄墙。
-- 射线用圆/AABB精确扫掠（条带+圆角），先判墙再按距离顺序判实体命中。
-- 网格20，按半径分桶；邻边必须有净空，禁止对角切墙角。
-- 玩家处于大敌人不可贴近的墙边时，目标投影到合法网格，不把敌人塞墙。
-- 反向BFS按目标格缓存，全体同半径敌人共享；近处视线畅通直接走。
local Navigation = {}
Navigation.CELL = 20
Navigation.BOUNDS = { left = 48, right = 992, top = 142, bottom = 628 }

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function Squared(ax, ay, bx, by) return (ax - bx) ^ 2 + (ay - by) ^ 2 end

---@param obstacles table[]
---@return table
function Navigation.New(obstacles)
    return { obstacles = obstacles, graphs = {}, fields = {}, fieldBuilds = 0, lineChecks = 0 }
end

function Navigation.Blocked(nav, x, y, radius)
    local b = Navigation.BOUNDS
    if x < b.left + radius or x > b.right - radius or y < b.top + radius or y > b.bottom - radius then return true end
    for _, obstacle in ipairs(nav.obstacles) do
        local cx, cy = Clamp(x, obstacle.x, obstacle.x + obstacle.w), Clamp(y, obstacle.y, obstacle.y + obstacle.h)
        if radius <= 0 then
            if x >= obstacle.x and x <= obstacle.x + obstacle.w and y >= obstacle.y and y <= obstacle.y + obstacle.h then return true end
        elseif Squared(x, y, cx, cy) < radius * radius - 0.000001 then return true end
    end
    return false
end

local function Slab(position, delta, low, high, enter, leave)
    if math.abs(delta) < 0.0000001 then
        if position < low or position > high then return false, enter, leave end
        return true, enter, leave
    end
    local first, last = (low - position) / delta, (high - position) / delta
    if first > last then first, last = last, first end
    local nextEnter, nextLeave = math.max(enter, first), math.min(leave, last)
    return nextEnter <= nextLeave, nextEnter, nextLeave
end

-- 返回[0,1]首次接触比例，无遮挡为1；同时返回是否真的接触，区分终点恰好撞墙。
function Navigation.Trace(nav, ax, ay, bx, by, radius)
    local b = Navigation.BOUNDS
    local dx, dy, earliest, hit = bx - ax, by - ay, 1, false
    if ax < b.left + radius or ax > b.right - radius or ay < b.top + radius or ay > b.bottom - radius then return 0, true end
    local limits = { { ax, dx, b.left + radius, b.right - radius }, { ay, dy, b.top + radius, b.bottom - radius } }
    for _, limit in ipairs(limits) do
        local endValue = limit[1] + limit[2]
        if endValue < limit[3] or endValue > limit[4] then
            local edge = endValue < limit[3] and limit[3] or limit[4]
            earliest, hit = math.min(earliest, (edge - limit[1]) / limit[2]), true
        end
    end
    local function Rectangle(left, top, right, bottom)
        local okX, enterX, leaveX = Slab(ax, dx, left, right, 0, earliest)
        if not okX then return end
        local okY, enterY = Slab(ay, dy, top, bottom, enterX, leaveX)
        if okY and enterY <= earliest then earliest, hit = math.max(0, enterY), true end
    end
    local function Corner(cx, cy)
        local ox, oy = ax - cx, ay - cy
        local c, a = ox * ox + oy * oy - radius * radius, dx * dx + dy * dy
        if c < 0 then earliest, hit = 0, true; return end
        if a < 0.0000001 then return end
        local dot = ox * dx + oy * dy
        local discriminant = dot * dot - a * c
        if discriminant < 0 then return end
        local t = (-dot - math.sqrt(discriminant)) / a
        if t >= 0 and t <= earliest then earliest, hit = t, true end
    end
    for _, obstacle in ipairs(nav.obstacles) do
        local left, top, right, bottom = obstacle.x, obstacle.y, obstacle.x + obstacle.w, obstacle.y + obstacle.h
        -- 圆/AABB的Minkowski和：两个条带+四个圆，而非四角过大的外扩矩形。
        Rectangle(left - radius, top, right + radius, bottom)
        Rectangle(left, top - radius, right, bottom + radius)
        if radius > 0 then Corner(left, top); Corner(right, top); Corner(left, bottom); Corner(right, bottom) end
    end
    return Clamp(earliest, 0, 1), hit
end

function Navigation.Visible(nav, ax, ay, bx, by, radius)
    nav.lineChecks = nav.lineChecks + 1
    local _, hit = Navigation.Trace(nav, ax, ay, bx, by, radius or 0)
    return not hit
end

-- 固定另一轴，圆与矩形的精确接触边：角部使用sqrt(r²-垂距²)，不是矩形假圆。
local function AxisMove(nav, position, cross, delta, radius, horizontal)
    local b = Navigation.BOUNDS
    local target = Clamp(position + delta, (horizontal and b.left or b.top) + radius, (horizontal and b.right or b.bottom) - radius)
    for _, obstacle in ipairs(nav.obstacles) do
        local side, depth = horizontal and obstacle.y or obstacle.x, horizontal and obstacle.h or obstacle.w
        local gap = math.abs(cross - Clamp(cross, side, side + depth))
        if gap < radius then
            local padding = math.sqrt(math.max(0, radius * radius - gap * gap))
            local low = (horizontal and obstacle.x or obstacle.y) - padding
            local high = (horizontal and obstacle.x + obstacle.w or obstacle.y + obstacle.h) + padding
            if delta > 0 and position <= low + 0.00001 and target > low then target = low
            elseif delta < 0 and position >= high - 0.00001 and target < high then target = high end
        end
    end
    return target
end

function Navigation.Move(nav, entity, dx, dy, radius)
    local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / 6))
    local stepX, stepY = dx / steps, dy / steps
    for _ = 1, steps do
        entity.x = AxisMove(nav, entity.x, entity.y, stepX, radius, true)
        entity.y = AxisMove(nav, entity.y, entity.x, stepY, radius, false)
    end
end

local function Bucket(radius) return math.max(4, math.ceil(radius / 4) * 4) end

-- 邻接关系只在进房/该半径首次使用时生成；实体障碍数组永不逐帧复制。
function Navigation.Graph(nav, radius)
    local key = Bucket(radius)
    if nav.graphs[key] then return nav.graphs[key] end
    local b, cell = Navigation.BOUNDS, Navigation.CELL
    local cols, rows = math.ceil((b.right - b.left) / cell), math.ceil((b.bottom - b.top) / cell)
    local graph = { radius = key, cols = cols, rows = rows, nodes = {}, component = {}, count = 0 }
    for row = 1, rows do
        for col = 1, cols do
            local x, y = b.left + (col - 0.5) * cell, b.top + (row - 0.5) * cell
            local id = (row - 1) * cols + col
            if not Navigation.Blocked(nav, x, y, key + 1) then
                graph.nodes[id] = { x = x, y = y, links = {} }
                graph.count = graph.count + 1
            end
        end
    end
    for id, node in pairs(graph.nodes) do
        local col = (id - 1) % cols + 1
        local candidates = { id - cols, id + cols }
        if col > 1 then candidates[#candidates + 1] = id - 1 end
        if col < cols then candidates[#candidates + 1] = id + 1 end
        for _, neighborId in ipairs(candidates) do
            local neighbor = graph.nodes[neighborId]
            if neighbor and Navigation.Visible(nav, node.x, node.y, neighbor.x, neighbor.y, key) then
                node.links[#node.links + 1] = neighborId
            end
        end
    end
    local componentCount = 0
    for id in pairs(graph.nodes) do
        if not graph.component[id] then
            componentCount = componentCount + 1
            local queue, head = { id }, 1
            graph.component[id] = componentCount
            while head <= #queue do
                local current = queue[head]
                head = head + 1
                for _, neighborId in ipairs(graph.nodes[current].links) do
                    if not graph.component[neighborId] then
                        graph.component[neighborId] = componentCount
                        queue[#queue + 1] = neighborId
                    end
                end
            end
        end
    end
    graph.componentCount = componentCount
    nav.graphs[key] = graph
    return graph
end

-- 常态只看周围5x5网格；只有非法目标/远离网格的窄边缘才做全图投影。
local function CellAt(nav, graph, x, y, component, requireVisible, visibilityRadius)
    local clearance = visibilityRadius or graph.radius
    local b, cell = Navigation.BOUNDS, Navigation.CELL
    local col, row = math.floor((x - b.left) / cell) + 1, math.floor((y - b.top) / cell) + 1
    local best, bestDistance = false, math.huge
    for offsetY = -2, 2 do
        for offsetX = -2, 2 do
            local c, r = col + offsetX, row + offsetY
            if c >= 1 and c <= graph.cols and r >= 1 and r <= graph.rows then
                local id = (r - 1) * graph.cols + c
                local node = graph.nodes[id]
                if node and (not component or graph.component[id] == component) then
                    local d = Squared(x, y, node.x, node.y)
                    if d < bestDistance and (not requireVisible or Navigation.Visible(nav, x, y, node.x, node.y, clearance)) then
                        best, bestDistance = id, d
                    end
                end
            end
        end
    end
    if best then return best end
    for id, node in pairs(graph.nodes) do
        if not component or graph.component[id] == component then
            local d = Squared(x, y, node.x, node.y)
            if d < bestDistance and (not requireVisible or Navigation.Visible(nav, x, y, node.x, node.y, clearance)) then
                best, bestDistance = id, d
            end
        end
    end
    return best
end

function Navigation.Field(nav, x, y, radius)
    local graph = Navigation.Graph(nav, radius)
    local field = nav.fields[graph.radius]
    if field and field.sourceX == x and field.sourceY == y then return field, graph end
    local target = CellAt(nav, graph, x, y, false, not Navigation.Blocked(nav, x, y, graph.radius))
    if not target then target = CellAt(nav, graph, x, y, false, false) end
    if field and field.target == target then field.sourceX, field.sourceY = x, y; return field, graph end
    field = { target = target, distance = {}, next = {}, sourceX = x, sourceY = y }
    nav.fieldBuilds = nav.fieldBuilds + 1
    if target then
        local queue, head = { target }, 1
        field.distance[target] = 0
        while head <= #queue do
            local id = queue[head]
            head = head + 1
            for _, neighborId in ipairs(graph.nodes[id].links) do
                if not field.distance[neighborId] then
                    field.distance[neighborId] = field.distance[id] + 1
                    field.next[neighborId] = id
                    queue[#queue + 1] = neighborId
                end
            end
        end
    end
    nav.fields[graph.radius] = field
    return field, graph
end

function Navigation.Project(nav, x, y, radius, anchorX, anchorY)
    local graph = Navigation.Graph(nav, radius)
    local anchor = CellAt(nav, graph, anchorX or 520, anchorY or 580, false, false)
    local component = anchor and graph.component[anchor] or false
    local original = not Navigation.Blocked(nav, x, y, radius) and CellAt(nav, graph, x, y, component, true)
    if original then return x, y end
    local id = CellAt(nav, graph, x, y, component, false)
    if not id then return nil, nil end
    return graph.nodes[id].x, graph.nodes[id].y
end

function Navigation.SpawnPoint(nav, playerX, playerY, radius, minimumDistance)
    local field, graph = Navigation.Field(nav, playerX, playerY, radius)
    local choices = {}
    for id in pairs(field.distance) do
        local node = graph.nodes[id]
        if Squared(node.x, node.y, playerX, playerY) >= minimumDistance * minimumDistance then choices[#choices + 1] = id end
    end
    if #choices == 0 then return nil, nil end
    local node = graph.nodes[choices[math.random(1, #choices)]]
    return node.x, node.y
end

-- 返回可见航点。entity缓存视线；流场按目标网格共享，不卡单障碍的贪心死路。
function Navigation.Waypoint(nav, entity, targetX, targetY, radius, now)
    if now >= (entity.navSightAt or 0) or Squared(targetX, targetY, entity.navTargetX or -1000, entity.navTargetY or -1000) > 100 then
        entity.navDirect = Navigation.Visible(nav, entity.x, entity.y, targetX, targetY, math.max(0, radius - 0.001))
        entity.navSightAt, entity.navTargetX, entity.navTargetY = now + 0.16, targetX, targetY
    end
    if entity.navDirect then return targetX, targetY end
    local field, graph = Navigation.Field(nav, targetX, targetY, radius)
    local component = field.target and graph.component[field.target] or false
    local id = CellAt(nav, graph, entity.x, entity.y, component, true, math.max(0, radius - 0.001))
    if not id or not field.distance[id] then return entity.x, entity.y end
    local nextId = field.next[id]
    local waypoint = graph.nodes[id]
    for _ = 1, 6 do
        if not nextId then break end
        local candidate = graph.nodes[nextId]
        if not Navigation.Visible(nav, entity.x, entity.y, candidate.x, candidate.y, math.max(0, radius - 0.001)) then break end
        waypoint, nextId = candidate, field.next[nextId]
    end
    return waypoint.x, waypoint.y
end

-- 调试/测试用：所有相邻点都在该半径净空内，不产生墙内传送点。
function Navigation.FindPath(nav, ax, ay, bx, by, radius)
    local field, graph = Navigation.Field(nav, bx, by, radius)
    local component = field.target and graph.component[field.target] or false
    local id = CellAt(nav, graph, ax, ay, component, true)
    if not id or not field.distance[id] then return {} end
    local path = { { x = ax, y = ay } }
    while id do
        local node = graph.nodes[id]
        path[#path + 1] = { x = node.x, y = node.y }
        id = field.next[id]
    end
    local tail = path[#path]
    if Navigation.Visible(nav, tail.x, tail.y, bx, by, radius) then path[#path + 1] = { x = bx, y = by } end
    return path
end

return Navigation
