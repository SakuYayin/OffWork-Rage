-- 《下班！别拦我》：排行榜数据层。
-- 设计依据：docs/design/05-endless-leaderboard.md §3.2 / §4.2；接入契约见 07-halved-plan.md §3。
--
-- 本地预览与在线部署使用不同的数据源：
--   Leaderboard.MODE = "local"  -> localStorage（默认，零部署）
--   Leaderboard.MODE = "server" -> 异步 fetch /api/leaderboard，逐帧只读缓存
--
-- 存储桥由 engine.js 提供：StorageGet(key) / StorageSet(key, value) / StorageRemove(key)
-- 与 ScoreRefresh / ScoreSubmit / ScorePoll。纯本地预览使用模块内存表 MEM，
-- 因此纯 Lua 命令行测试（无任何全局桥）也能跑完整逻辑。
--
-- 序列化不引入 JSON 库（fengari 里没有）：管道分隔文本，一条一段，段尾分号。
--   name|score|wave|boss|level|kills|time|ts;
local Leaderboard = {}

Leaderboard.MODE = "local"
Leaderboard.MAX_ENTRIES = 20
Leaderboard.MAX_SCORE = 2147483647
Leaderboard.VERSION="office-expansion-v3"
Leaderboard.RULESET="balance-2026-11-07-v2"
Leaderboard.KEY = "offwork-rage.leaderboard."..Leaderboard.VERSION.."."..Leaderboard.RULESET
Leaderboard.NAME_KEY = Leaderboard.KEY .. ":name"
Leaderboard.URL = "/api/leaderboard"
Leaderboard.Fields = { "name", "score", "wave", "boss", "level", "kills", "time", "ts" }

-- fengari 的整数是 32 位：超过上限的浮点转整数会让 string.format("%d") 直接抛错，
-- 所以凡是要落盘 / 要格式化的数，先 floor 再钳进 int32。
local INT_MAX, INT_MIN = 2147483647, -2147483648

---@param v any
---@param default any
---@return integer|any
local function clampInt(v, default)
    local n = tonumber(v)
    if type(n) ~= "number" or n ~= n then return default end -- nil / NaN
    if n >= INT_MAX then return INT_MAX end
    if n <= INT_MIN then return INT_MIN end
    return math.floor(n + 0.0)
end

local DEFAULT = { score = 0, wave = 0, boss = 0, level = 1, kills = 0, time = 0, ts = 0 }

-- ------------------------------------------------------------------ 存储桥
-- 桥抛错不能崩游戏：全部包 pcall，读失败回内存表，写失败也留内存表。
local MEM = {}

local function storeGet(key)
    local f = rawget(_G, "StorageGet")
    if type(f) == "function" then
        local ok, v = pcall(f, key)
        if ok and type(v) == "string" then return v end
    end
    return MEM[key]
end

local function storeSet(key, value)
    MEM[key] = value
    local f = rawget(_G, "StorageSet")
    if type(f) == "function" then pcall(f, key, value) end
    return true
end

local function storeRemove(key)
    MEM[key] = nil
    local f = rawget(_G, "StorageRemove")
    if type(f) == "function" then pcall(f, key) end
    return true
end

-- engine.js 的 NetGet / NetPost 经 makeTrampoline 展开成两个返回值：(ok, payload)。
-- 也容忍它们被换成返回单个 table / string 的写法。
local function netCall(name, ...)
    local f = rawget(_G, name)
    if type(f) ~= "function" then return false, nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return false, nil end
    if type(a) == "boolean" then return a, b end
    if type(a) == "table" then return a.ok ~= false, a.body or a.payload end
    if type(a) == "string" then return true, a end
    return false, nil
end

-- ------------------------------------------------------------------ 昵称
---@param s any
---@return string 去首尾空格，保留中文、大小写和标点
function Leaderboard.SanitizeName(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param s any
---@return boolean 非空且无控制字符
function Leaderboard.ValidName(s)
    if type(s) ~= "string" then return false end
    return Leaderboard.SanitizeName(s)~=""and not s:find("[%z\1-\31\127]")
end

---@return string
function Leaderboard.GetName()
    local v = storeGet(Leaderboard.NAME_KEY)
    if type(v) ~= "string" then return "" end
    return v
end

---@param s string
---@return string 实际存下的名字
function Leaderboard.SetName(s)
    local name = Leaderboard.SanitizeName(s)
    storeSet(Leaderboard.NAME_KEY, name)
    return name
end

-- ------------------------------------------------------------------ 编码
---@param entries table[]
---@return string
function Leaderboard.Encode(entries)
    local buf = {}
    if type(entries) ~= "table" then return "" end
    for i = 1, #entries do
        local e = entries[i]
        if type(e) == "table" then
            local fields = {}
            for k = 1, 8 do
                local key = Leaderboard.Fields[k]
                if key == "name" then
                    -- Unicode 名字保持原样，转义分隔符及百分号。
                    fields[k] = ((tostring(e.name or "")):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(";", "%%3B"))
                else
                    fields[k] = tostring(clampInt(e[key], DEFAULT[key] or 0))
                end
            end
            buf[#buf + 1] = table.concat(fields, "|") .. ";"
        end
    end
    return table.concat(buf)
end

-- 手写切分：不用 gmatch("[^|]*")，那个在空段上会额外吐出空匹配。
local function splitPipes(chunk)
    local out, i = {}, 1
    while true do
        local at = string.find(chunk, "|", i, true)
        if not at then
            out[#out + 1] = string.sub(chunk, i)
            return out
        end
        out[#out + 1] = string.sub(chunk, i, at - 1)
        i = at + 1
    end
end

---@param text string?
---@return table[] 坏记录逐条跳过，绝不抛错
function Leaderboard.Decode(text)
    local entries = {}
    if type(text) ~= "string" or text == "" then return entries end
    for chunk in text:gmatch("[^;]+") do
        local f = splitPipes(chunk)
        if #f >= 8 then
            local score = tonumber(f[2])
            if score then
                entries[#entries + 1] = {
                    name = f[1]:gsub("%%(%x%x)",function(hex)return string.char(tonumber(hex,16))end),
                    score = clampInt(score, 0),
                    wave = clampInt(f[3], 0),
                    boss = clampInt(f[4], 0),
                    level = clampInt(f[5], 1),
                    kills = clampInt(f[6], 0),
                    time = clampInt(f[7], 0),
                    ts = clampInt(f[8], 0),
                }
            end
        end
    end
    return entries
end

-- ------------------------------------------------------------------ 排序
-- 三重键：分数降序 -> 同分波次降序 -> 再同则用时升序（给速通一个隐性荣誉）。
-- 第四、第五键只为了让 table.sort 的输出稳定（同分同波同用时时按提交时间、名字）。
local function before(a, b)
    local as, bs = tonumber(a.score) or 0, tonumber(b.score) or 0
    if as ~= bs then return as > bs end
    local aw, bw = tonumber(a.wave) or 0, tonumber(b.wave) or 0
    if aw ~= bw then return aw > bw end
    local at, bt = tonumber(a.time) or 0, tonumber(b.time) or 0
    if at ~= bt then return at < bt end
    local ats, bts = tonumber(a.ts) or 0, tonumber(b.ts) or 0
    if ats ~= bts then return ats < bts end
    return tostring(a.name or "") < tostring(b.name or "")
end

---@param entries table[]
---@return table[] 同一张表（原地排序），返回值只是为了链式调用方便
function Leaderboard.Sort(entries)
    local list = {}
    if type(entries) == "table" then
        for i = 1, #entries do
            if type(entries[i]) == "table" then list[#list + 1] = entries[i] end
        end
        table.sort(list, before)
        for i = 1, #list do entries[i] = list[i] end
        for i = #list + 1, #entries do entries[i] = nil end
        return entries
    end
    return list
end

local function sameEntry(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for i = 1, 8 do
        local key = Leaderboard.Fields[i]
        if key == "name" then
            if tostring(a.name or "") ~= tostring(b.name or "") then return false end
        elseif (tonumber(a[key]) or 0) ~= (tonumber(b[key]) or 0) then
            return false
        end
    end
    return true
end

---@param entries table[]
---@param entry table
---@return integer 1 基名次；没找到返回 #entries + 1
function Leaderboard.RankOf(entries, entry)
    local list = type(entries) == "table" and entries or {}
    if entry == nil then return #list + 1 end
    for i = 1, #list do
        if list[i] == entry then return i end
    end
    for i = 1, #list do
        if sameEntry(list[i], entry) then return i end
    end
    return #list + 1
end

---@param score any
---@return boolean 合法分数：0 < score <= MAX_SCORE，且不是 NaN / inf
function Leaderboard.CanRank(score)
    local n = tonumber(score)
    if type(n) ~= "number" or n ~= n then return false end
    if n == math.huge or n == -math.huge then return false end
    return n > 0 and n <= Leaderboard.MAX_SCORE
end

-- ------------------------------------------------------------------ 本地榜
---@return table[] 已排序
function Leaderboard.LoadLocal()
    return Leaderboard.Sort(Leaderboard.Decode(storeGet(Leaderboard.KEY)))
end

---@param entries table[]
---@return boolean
function Leaderboard.SaveLocal(entries)
    local list = {}
    if type(entries) == "table" then
        for i = 1, #entries do
            if type(entries[i]) == "table" then list[#list + 1] = entries[i] end
        end
    end
    Leaderboard.Sort(list)
    while #list > Leaderboard.MAX_ENTRIES do table.remove(list) end
    return storeSet(Leaderboard.KEY, Leaderboard.Encode(list))
end

---@param n integer?
---@return table[]
function Leaderboard.FetchTopLocal(n)
    local limit = clampInt(n, 10)
    if limit < 0 then limit = 0 end
    local list = Leaderboard.LoadLocal()
    local out = {}
    for i = 1, math.min(limit, #list) do out[i] = list[i] end
    return out
end

---@param entry table
---@return integer 名次；0 表示没进榜（名字/分数不合法或掉出前 MAX_ENTRIES）
function Leaderboard.SubmitLocal(entry)
    if type(entry) ~= "table" then return 0 end
    local name = tostring(entry.name or "")
    if not Leaderboard.ValidName(name) then return 0 end
    local score = tonumber(entry.score)
    if not Leaderboard.CanRank(score) then return 0 end

    local mine = {
        name = name,
        score = clampInt(score, 0),
        wave = clampInt(entry.wave, 0),
        boss = clampInt(entry.boss, 0),
        level = clampInt(entry.level, 1),
        kills = clampInt(entry.kills, 0),
        time = clampInt(entry.time, 0),
        ts = clampInt(entry.ts, 0),
    }
    if mine.ts == 0 and type(os) == "table" and type(os.time) == "function" then
        local ok, now = pcall(os.time)
        if ok then mine.ts = clampInt(now, 0) end
    end

    local list = Leaderboard.LoadLocal()
    list[#list + 1] = mine
    Leaderboard.Sort(list)
    local rank = Leaderboard.RankOf(list, mine) -- 同一个引用，第一轮就能命中
    while #list > Leaderboard.MAX_ENTRIES do table.remove(list) end
    Leaderboard.SaveLocal(list)
    if rank > Leaderboard.MAX_ENTRIES then rank = 0 end
    return rank
end

---@return boolean
function Leaderboard.ClearLocal()
    return storeRemove(Leaderboard.KEY)
end

-- ------------------------------------------------------------------ 异步服务端桥
-- JSON 只负责发请求；服务端榜单使用转义管道文本，避免 Lua 猜测 JSON 字符串。
local function jsonString(value)
    local s=tostring(value or "")
    return '"'..s:gsub('[%z\1-\31\\"]',function(c)
        if c=='"'then return '\\"' end
        if c=='\\'then return '\\\\' end
        return string.format('\\u%04x',string.byte(c))
    end)..'"'
end
local function encodeEntryJson(e)
    local pieces={}
    for _,key in ipairs({"name","mode","hero","run_id"})do
        pieces[#pieces+1]=jsonString(key)..":"..jsonString(e[key])
    end
    for _,key in ipairs({"score","wave","boss","level","kills","time"})do
        pieces[#pieces+1]=jsonString(key)..":"..tostring(clampInt(e[key],DEFAULT[key]or 0))
    end
    return "{"..table.concat(pieces,",").."}"
end
local remote, lastRevision={}, -1
local localState,localRank,localError="idle",0,""
local localRevision=0
local fallbackRun=0
function Leaderboard.NewRunId()
    local f=rawget(_G,"ScoreNewRunId")
    if type(f)=="function"then local ok,id=pcall(f);if ok then return id end end
    fallbackRun=fallbackRun+1
    return string.format("00000000-0000-4000-8000-%012d",fallbackRun)
end
function Leaderboard.Poll()
    local f=rawget(_G,"ScorePoll")
    if type(f)=="function"then
        local ok,revision,state,rank,err,wire,online=pcall(f)
        if ok and online then
            Leaderboard.MODE="server"
            local changed=revision~=lastRevision
            if changed then remote=Leaderboard.Decode(wire);lastRevision=revision end
            return changed,state,rank,err
        end
        if ok then Leaderboard.MODE="local"end
    end
    local changed=lastRevision~=localRevision
    lastRevision=localRevision
    return changed,localState,localRank,localError
end
function Leaderboard.Refresh(mode)
    Leaderboard.Poll()
    if Leaderboard.MODE=="server"then
        local ok,started=netCall("ScoreRefresh",mode or"endless")
        return ok and started~=false
    end
    localState="idle";localRevision=localRevision+1
    return true
end
function Leaderboard.SubmitAsync(entry)
    Leaderboard.Poll()
    if type(entry)~="table"or not Leaderboard.ValidName(entry.name)or not Leaderboard.CanRank(entry.score)then return false end
    if Leaderboard.MODE=="server"then
        local ok,started=netCall("ScoreSubmit",encodeEntryJson(entry))
        return ok and started~=false
    end
    localRank=Leaderboard.SubmitLocal(entry)
    localState=localRank>0 and"success"or"error"
    localError=localRank>0 and""or"invalid_entry"
    localRevision=localRevision+1
    return true
end
Leaderboard.Store={}
function Leaderboard.Store.Load()
    if Leaderboard.MODE=="server"then return remote end
    return Leaderboard.LoadLocal()
end
function Leaderboard.Store.Save(entries)
    if type(entries)=="table"and type(entries.entries)=="table"then entries=entries.entries end
    return Leaderboard.SaveLocal(entries)
end
-- Compatibility for local tools; online callers must use SubmitAsync + Poll.
function Leaderboard.Store.Submit(entry)
    if Leaderboard.MODE=="server"then Leaderboard.SubmitAsync(entry);return 0 end
    return Leaderboard.SubmitLocal(entry)
end
function Leaderboard.Store.FetchTop(n)
    local list=Leaderboard.Store.Load();local out={}
    for i=1,math.min(math.max(0,clampInt(n,10)),#list)do out[i]=list[i]end
    return out
end
function Leaderboard.Store.Clear()return Leaderboard.ClearLocal()end

-- 别名表：Store 的 local 实现，方便一行切换后端。
Leaderboard.Local = {
    Load = function() return Leaderboard.LoadLocal() end,
    Save = function(entries) return Leaderboard.SaveLocal(entries) end,
    Submit = function(entry) return Leaderboard.SubmitLocal(entry) end,
    Clear = function() return Leaderboard.ClearLocal() end,
    FetchTop = function(n) return Leaderboard.FetchTopLocal(n) end,
}

return Leaderboard
