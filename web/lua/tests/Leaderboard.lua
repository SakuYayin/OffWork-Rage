-- 排行榜数据层单测。
-- 跑法：cd web && node tools/run-lua-tests.mjs Leaderboard
-- 本套件天然在「无存储桥」环境跑（run-lua-tests.mjs 的沙箱只有 console/定时器），
-- 所以内存表降级路径每次都在被验证。
local Leaderboard = require("Leaderboard")

local M = {}
local checks = 0

local function Check(cond, msg)
    checks = checks + 1
    if not cond then error(tostring(msg or "check") .. " (failed check #" .. checks .. ")", 2) end
end

local function Eq(got, want, msg)
    checks = checks + 1
    if got ~= want then
        error(string.format("%s: expected %s, got %s (failed check #%d)",
            tostring(msg or "eq"), tostring(want), tostring(got), checks), 2)
    end
end

local function MakeEntry(name, score, wave, time, level)
    return { name = name, score = score, wave = wave or 0, boss = 0, level = level or 1,
        kills = 0, time = time or 0, ts = 0 }
end

function M.Run()
    checks = 0

    ---------------------------------------------------------------- 常量契约
    Eq(Leaderboard.MODE, "local", "MODE 默认值")
    Eq(Leaderboard.MAX_ENTRIES, 20, "MAX_ENTRIES")
    Eq(Leaderboard.MAX_SCORE, 2147483647, "MAX_SCORE")
    Eq(Leaderboard.KEY, "offwork-rage.leaderboard.office-expansion-v3.balance-2026-11-07-v2", "KEY")
    Eq(#Leaderboard.Fields, 8, "Fields 长度")
    Eq(Leaderboard.Fields[1], "name", "Fields[1]")
    Eq(Leaderboard.Fields[8], "ts", "Fields[8]")

    ---------------------------------------------------------------- SanitizeName
    Eq(Leaderboard.SanitizeName("  abc  "), "abc", "SanitizeName 去首尾空格并大写")
    Eq(Leaderboard.SanitizeName("陈准"), "陈准", "SanitizeName 过滤中文")
    Eq(Leaderboard.SanitizeName("A-B_C!"), "A-B_C!", "SanitizeName 过滤标点下划线")
    Eq(Leaderboard.SanitizeName("ABCDEFGHIJKLMNOPQRST"), "ABCDEFGHIJKLMNOPQRST", "SanitizeName 截断 12")
    Eq(#Leaderboard.SanitizeName("ABCDEFGHIJKLMNOPQRST"), 20, "SanitizeName 超长长度 == 12")
    Eq(Leaderboard.SanitizeName("A   B"), "A   B", "SanitizeName 压缩连续空格")
    Eq(Leaderboard.SanitizeName("  a  b  "), "a  b", "SanitizeName 压缩+去首尾")
    Eq(Leaderboard.SanitizeName(""), "", "SanitizeName 空串")
    Eq(Leaderboard.SanitizeName(nil), "", "SanitizeName nil 不崩")
    Eq(Leaderboard.SanitizeName(12345), "", "SanitizeName 非字符串不崩")
    Eq(Leaderboard.SanitizeName("chen zhun"), "chen zhun", "SanitizeName 保留内部空格")

    ---------------------------------------------------------------- ValidName
    Check(Leaderboard.ValidName("ABC") == true, "ValidName(ABC)")
    Check(Leaderboard.ValidName("") == false, "ValidName(空串) == false")
    Check(Leaderboard.ValidName("  ") == false, "ValidName(全空格) == false")
    Check(Leaderboard.ValidName("ABC DEF") == true, "ValidName(带空格) == true")
    Check(Leaderboard.ValidName("abcdef") == true, "ValidName(小写未大写化) == false")
    Check(Leaderboard.ValidName("A1") == true, "ValidName(字母数字) == true")
    Check(Leaderboard.ValidName("ABCDEFGHIJKL") == true, "ValidName(12 字) == true")
    Check(Leaderboard.ValidName("ABCDEFGHIJKLM") == true, "ValidName(13 字) == false")
    Check(Leaderboard.ValidName(nil) == false, "ValidName(nil) == false")
    Check(Leaderboard.ValidName("AB-C") == true, "ValidName(带标点) == false")

    ---------------------------------------------------------------- Encode / Decode 往返
    Leaderboard.ClearLocal()
    local src = {
        MakeEntry("CHEN", 92952, 61, 300, 9),
        MakeEntry("A B", 1328, 5, 42, 3),
        MakeEntry("Z9", 500000, 200, 3600, 20),
    }
    local text = Leaderboard.Encode(src)
    Check(type(text) == "string" and #text > 0, "Encode 产出非空字符串")
    Check(string.sub(text, -1) == ";", "Encode 段尾是分号")
    Check(string.find(text, "|", 1, true) ~= nil, "Encode 用管道分隔")
    local back = Leaderboard.Decode(text)
    Eq(#back, 3, "Decode 条数")
    for i = 1, 3 do
        for k = 1, 8 do
            local key = Leaderboard.Fields[k]
            Eq(back[i][key], src[i][key], "往返字段 " .. key .. " #" .. i)
        end
    end
    Eq(Leaderboard.Encode(nil), "", "Encode(nil) == 空串")
    Eq(Leaderboard.Encode({}), "", "Encode({}) == 空串")

    ---------------------------------------------------------------- Decode 容错
    local junk = Leaderboard.Decode("垃圾数据")
    Eq(type(junk), "table", "Decode(垃圾) 返回 table")
    Eq(#junk, 0, "Decode(垃圾) 条数为 0")
    Eq(#Leaderboard.Decode(nil), 0, "Decode(nil) 不抛错")
    Eq(#Leaderboard.Decode(""), 0, "Decode(空串) 不抛错")
    Eq(#Leaderboard.Decode("A|abc|0|0|0|0|0|0;"), 0, "Decode 分数非数字整条跳过")
    Eq(#Leaderboard.Decode("A|1|2|3"), 0, "Decode 字段不足整条跳过")
    Eq(#Leaderboard.Decode(text .. "垃圾数据;"), 3, "Decode 好数据+坏数据只留好的")
    local partial = Leaderboard.Decode("GOOD|100|2|0|3|4|50|7;BAD|xx|0|0|0|0|0|0;")
    Eq(#partial, 1, "Decode 混合数据保留条数")
    Eq(partial[1] and partial[1].name, "GOOD", "Decode 混合数据保留内容")

    ---------------------------------------------------------------- Sort 三重键
    local list = {
        MakeEntry("LOW", 1000, 5, 100),
        MakeEntry("HIGH", 9000, 5, 100),
        MakeEntry("SAME_LOW_WAVE", 5000, 3, 100),
        MakeEntry("SAME_HIGH_WAVE", 5000, 9, 100),
        MakeEntry("SAME_WAVE_SLOW", 5000, 9, 900),
        MakeEntry("SAME_WAVE_FAST", 5000, 9, 10),
    }
    Leaderboard.Sort(list)
    Eq(#list, 6, "Sort 不丢条目")
    Eq(list[1].name, "HIGH", "Sort 分数降序第一位")
    Eq(list[6].name, "LOW", "Sort 分数降序末位")
    -- 5000 分组：wave 9 的三人 time 升序为 FAst(10) -> HIGH_WAVE(100) -> SLOW(900)，最后才是 wave 3
    Eq(list[2].name, "SAME_WAVE_FAST", "Sort 同分同波用时升序")
    Eq(list[3].name, "SAME_HIGH_WAVE", "Sort 同分同波次者")
    Eq(list[4].name, "SAME_WAVE_SLOW", "Sort 同分同波慢者靠后")
    Eq(list[5].name, "SAME_LOW_WAVE", "Sort 同分波次小者后")
    Check(list[2].time < list[3].time and list[3].time < list[4].time, "Sort 同组内 time 升序")

    ---------------------------------------------------------------- CanRank
    Check(Leaderboard.CanRank(1328) == true, "CanRank(1328) == true")
    Check(Leaderboard.CanRank(0) == false, "CanRank(0) == false")
    Check(Leaderboard.CanRank(2147483648) == false, "CanRank(2147483648) == false")
    Check(Leaderboard.CanRank(500000) == true, "CanRank(MAX_SCORE) == true")
    Check(Leaderboard.CanRank(-5) == false, "CanRank(负数) == false")
    Check(Leaderboard.CanRank(nil) == false, "CanRank(nil) == false")
    Check(Leaderboard.CanRank(0 / 0) == false, "CanRank(NaN) == false")

    ---------------------------------------------------------------- SubmitLocal / LoadLocal
    Leaderboard.ClearLocal()
    Eq(#Leaderboard.LoadLocal(), 0, "Clear 后 LoadLocal 为空")

    local r1 = Leaderboard.SubmitLocal(MakeEntry("AAA", 1000, 1))
    Eq(r1, 1, "首次提交名次为 1")
    local r2 = Leaderboard.SubmitLocal(MakeEntry("BBB", 5000, 3))
    Eq(r2, 1, "更高分抢到第 1")
    local r3 = Leaderboard.SubmitLocal(MakeEntry("CCC", 3000, 2))
    Eq(r3, 2, "中间分排第 2")
    local r4 = Leaderboard.SubmitLocal(MakeEntry("DDD", 2000, 2))
    Eq(r4, 3, "低分排第 3")
    local r5 = Leaderboard.SubmitLocal(MakeEntry("EEE", 4000, 2))
    Eq(r5, 2, "插入第 2")
    local r6 = Leaderboard.SubmitLocal(MakeEntry("FFF", 500, 1))
    Eq(r6, 6, "最低分排第 6")

    local after = Leaderboard.LoadLocal()
    Eq(#after, 6, "6 次提交后 LoadLocal 条数")
    Eq(after[1].name, "BBB", "第 1 名是最高分")
    Eq(after[1].score, 5000, "第 1 名分数")
    Eq(after[6].name, "FFF", "末位是最低分")
    Eq(after[2].name, "EEE", "第 2 名")
    Eq(after[5].name, "AAA", "第 5 名")

    ---------------------------------------------------------------- 非法提交
    Eq(Leaderboard.SubmitLocal(MakeEntry("", 1000, 1)), 0, "空名字不记榜")
    Eq(Leaderboard.SubmitLocal(MakeEntry("ZZZ", 0, 1)), 0, "0 分不记榜")
    Eq(Leaderboard.SubmitLocal(MakeEntry("ZZZ", 2147483648, 1)), 0, "超上限分不记榜")
    Eq(Leaderboard.SubmitLocal(nil), 0, "nil entry 不崩")
    Eq(#Leaderboard.LoadLocal(), 6, "非法提交没有污染榜单")

    ---------------------------------------------------------------- RankOf
    local entries = Leaderboard.LoadLocal()
    Eq(Leaderboard.RankOf(entries, entries[1]), 1, "RankOf 同一引用第 1 名")
    Eq(Leaderboard.RankOf(entries, entries[3]), 3, "RankOf 同一引用第 3 名")
    local clone = {}
    for i = 1, 8 do
        local key = Leaderboard.Fields[i]
        clone[key] = entries[2][key]
    end
    Eq(Leaderboard.RankOf(entries, clone), 2, "RankOf 按字段匹配第 2 名")
    Eq(Leaderboard.RankOf(entries, MakeEntry("NOPE", 7, 0)), #entries + 1, "RankOf 未找到返回 #+1")
    Eq(Leaderboard.RankOf({}, MakeEntry("NOPE", 7, 0)), 1, "RankOf 空榜返回 1")

    ---------------------------------------------------------------- 截断到 MAX_ENTRIES
    Leaderboard.ClearLocal()
    for i = 1, 25 do
        Leaderboard.SubmitLocal(MakeEntry("P" .. i, i * 1000, i))
    end
    local capped = Leaderboard.LoadLocal()
    Eq(#capped, Leaderboard.MAX_ENTRIES, "超过 MAX_ENTRIES 截断到 20")
    Eq(capped[1].score, 25000, "截断后最高分仍在首位")
    Eq(capped[20].score, 6000, "截断后最低分是第 6 名档")
    Eq(Leaderboard.RankOf(capped, capped[20]), 20, "截断后末位名次")

    ---------------------------------------------------------------- FetchTop / Local 别名
    local top3 = Leaderboard.FetchTopLocal(3)
    Eq(#top3, 3, "FetchTopLocal(3) 条数")
    Eq(top3[1].score, 25000, "FetchTopLocal 首位")
    Eq(#Leaderboard.Local.FetchTop(2), 2, "Local.FetchTop 别名")
    Eq(type(Leaderboard.Local.Load), "function", "Local.Load 别名")
    Eq(type(Leaderboard.Local.Submit), "function", "Local.Submit 别名")
    Eq(type(Leaderboard.Local.Clear), "function", "Local.Clear 别名")
    Eq(type(Leaderboard.Local.Save), "function", "Local.Save 别名")

    ---------------------------------------------------------------- ClearLocal
    Check(Leaderboard.ClearLocal() == true, "ClearLocal 返回 true")
    Eq(#Leaderboard.LoadLocal(), 0, "ClearLocal 后榜单为空")
    Eq(#Leaderboard.FetchTopLocal(10), 0, "ClearLocal 后 FetchTop 为空")

    ---------------------------------------------------------------- 昵称
    Eq(Leaderboard.SetName("abc"), "abc", "SetName 大写化并返回")
    Eq(Leaderboard.GetName(), "abc", "GetName 与 SetName 一致")
    Eq(Leaderboard.SetName("  chen zhun  "), "chen zhun", "SetName 补空格与截断")
    Eq(Leaderboard.GetName(), "chen zhun", "GetName 覆盖旧值")
    Leaderboard.SetName("")
    Eq(Leaderboard.GetName(), "", "SetName('') 清空昵称")

    ---------------------------------------------------------------- Save / Store 适配层
    Leaderboard.ClearLocal()
    local seed = { MakeEntry("S1", 9000, 9), MakeEntry("S2", 3000, 3) }
    Check(Leaderboard.SaveLocal(seed) == true, "SaveLocal 返回 true")
    Eq(#Leaderboard.LoadLocal(), 2, "SaveLocal 落盘条数")
    Eq(Leaderboard.LoadLocal()[1].name, "S1", "SaveLocal 已排序")
    Check(Leaderboard.Store.Save(seed) == true, "Store.Save(table[]) 兼容")
    Check(Leaderboard.Store.Save({ entries = seed }) == true, "Store.Save{entries=} 兼容")
    Eq(#Leaderboard.Store.Load(), 2, "Store.Load 条数")
    Eq(#Leaderboard.Store.FetchTop(1), 1, "Store.FetchTop 条数")
    Check(Leaderboard.Store.Clear() == true, "Store.Clear 返回 true")
    Eq(#Leaderboard.LoadLocal(), 0, "Store.Clear 后为空")

    -- 在线榜不混入本地成绩，异步状态只在桥完成后改变。
    local originalPoll,originalSubmit,originalRefresh=ScorePoll,ScoreSubmit,ScoreRefresh
    local revision,state,wire=1,"idle",""
    ScorePoll=function()return revision,state,7,"",wire,true end
    ScoreSubmit=function(body)
        Check(body:find('许宁',1,true)~=nil,"提交保留中文")
        Check(body:find('\\"',1,true)~=nil,"JSON引号转义")
        state="submitting";revision=revision+1;return true
    end
    ScoreRefresh=function(mode)Eq(mode,"campaign","模式传给桥");state="loading";revision=revision+1;return true end
    Leaderboard.Poll()
    Eq(Leaderboard.MODE,"server","在线桥切到server")
    Eq(#Leaderboard.Store.Load(),0,"在线榜不混本地")
    Check(Leaderboard.SubmitAsync({name='许宁"|;%测试',score=4000,mode="campaign"}),"异步提交已启动")
    local changed,status=Leaderboard.Poll()
    Check(changed,"异步提交有状态变化");Eq(status,"submitting","请求中不算成功")
    wire=Leaderboard.Encode({MakeEntry('许宁"|;%测试',4000,4)})
    state="success";revision=revision+1
    local _,success,rank=Leaderboard.Poll()
    Eq(success,"success","提交完成");Eq(rank,7,"服务端名次")
    Eq(Leaderboard.Store.FetchTop(10)[1].name,'许宁"|;%测试',"中文分隔符往返")
    Leaderboard.Refresh("campaign");Leaderboard.Poll()
    state="idle";revision=revision+1
    local _,idle=Leaderboard.Poll();Eq(idle,"idle","刷新完成不会误判提交成功")
    ScorePoll,ScoreSubmit,ScoreRefresh=originalPoll,originalSubmit,originalRefresh
    Leaderboard.MODE="local"
    Check(not Leaderboard.ValidName("A\nB"),"禁止控制字符")

    ---------------------------------------------------------------- 大数据不崩
    Leaderboard.ClearLocal()
    Eq(Leaderboard.SubmitLocal(MakeEntry("BIG", 3000000000, 1)), 0, "超 int32 的分数被拒")
    Eq(#Leaderboard.LoadLocal(), 0, "超 int32 分数未污染榜单")

    Leaderboard.ClearLocal()
    Leaderboard.SetName("")
    print("[Leaderboard] " .. checks .. " checks passed")
    return checks
end

function Start()
    return M.Run()
end

return M
