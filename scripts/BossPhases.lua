-- BOSS 三阶段推进 / 破防窗口 / 各 BOSS 相位特色参数。
-- 纯逻辑模块：不渲染、不发弹幕、不 Spawn、不改玩家血量、不碰 shake/hitStop。
-- 调用方（Game.UpdateBoss / Game.EnemyImpact）负责：公告播放、EnemyAnimation.Start、
-- HostileShot、Game.Spawn、镜头抖动与顿帧。
--
--   BossPhases.Init(e)                      幂等初始化 e.boss
--   BossPhases.Tick(g,e,dt) -> phase        每帧：推进相位(66%/33% 只升不降)+递减 breakTimer+相位计时器
--   BossPhases.SpeedMul(e) -> number        1.00 / 1.15 / 1.30
--   BossPhases.CooldownMul(e) -> number     1.00 / 0.85 / 0.70
--   BossPhases.DamageMul(e) -> number       1.00 / 1.10 / 1.25
--   BossPhases.BulletCount(e) -> integer    1 / 3 / 5
--   BossPhases.OnPhaseChange(g,e,phase) -> string  相位切换瞬间的中文公告文案
--   BossPhases.BreakWindow(e) -> boolean    破防窗口（BOSS 不动不攻击）
--   BossPhases.OpenBreak(e, seconds) -> number
--   BossPhases.SummonCount(e) -> integer    0 或 2（P3 秃头主管），Spawn 由调用方做
--   BossPhases.SummonKind(e) -> integer     召唤物的 Game.Spawn kind
-- 补充（消费式：读到一次 true 后自动清除，供 UpdateBoss 轮询）：
--   BossPhases.WantsCharge(e) -> boolean    工贼同事 P3：每 6s 一次冲锋到点
--   BossPhases.WantsRing(e) -> boolean      没良心老板 P2/P3：每 5s 环形弹幕到点
local BossPhases = {}

local PHASE_AT = { 0.66, 0.33 }              -- hp/maxHp 落到该比例进入对应相位（只升不降）
local SPEED_MUL = { 1.00, 1.15, 1.30 }
local CD_MUL = { 1.00, 0.85, 0.70 }
local DMG_MUL = { 1.00, 1.10, 1.25 }
local BULLET_COUNT = { 1, 3, 5 }
local CHARGE_EVERY = 6.0                     -- 工贼同事 P3 冲锋间隔（秒）
local RING_EVERY = 5.0                       -- 没良心老板 P2/P3 环形弹幕间隔（秒）
local AUTO_BREAK_EVERY, AUTO_BREAK_TIME = 10.0, 1.2   -- 没良心老板 P3 自动破防

function BossPhases.Init(e)
    if type(e) ~= "table" then return nil end
    local b = e.boss
    if type(b) ~= "table" then
        b = { phase = 1, phaseTime = 0, breakTimer = 0, attackIndex = 0 }
        e.boss = b
        if not BossPhases._logged then
            BossPhases._logged = true
            print("[BossPhases] init phase1")
        end
    end
    if type(b.phase) ~= "number" then b.phase = 1 end
    if type(b.phaseTime) ~= "number" then b.phaseTime = 0 end
    if type(b.breakTimer) ~= "number" then b.breakTimer = 0 end
    if type(b.attackIndex) ~= "number" then b.attackIndex = 0 end
    if type(b.chargeTimer) ~= "number" then b.chargeTimer = 0 end
    if type(b.ringTimer) ~= "number" then b.ringTimer = 0 end
    if type(b.breakCd) ~= "number" then b.breakCd = 0 end
    return b
end

local function PhaseOf(e)
    local b = e and e.boss
    local p = b and b.phase
    if type(p) ~= "number" then return 1 end
    if p < 1 then return 1 end
    if p > 3 then return 3 end
    return math.floor(p)
end

local function FloorOf(e)
    local f = e and e.bossFloor
    if type(f) ~= "number" then return 1 end
    return math.floor(f)
end

function BossPhases.Tick(g, e, dt)
    local b = BossPhases.Init(e)
    if not b then return 1 end
    dt = tonumber(dt) or 0
    if dt < 0 then dt = 0 end
    b.phaseTime = b.phaseTime + dt

    -- ① 按血量推进相位，只升不降；maxHp 缺失时不推进
    local maxHp = tonumber(e.maxHp) or 0
    if maxHp > 0 then
        local ratio = (tonumber(e.hp) or maxHp) / maxHp
        local p = b.phase
        if p < 2 and ratio <= PHASE_AT[1] then p = 2 end
        if p < 3 and ratio <= PHASE_AT[2] then p = 3 end
        b.phase = p
    end

    -- ② 破防窗口倒计时
    if b.breakTimer > 0 then
        b.breakTimer = b.breakTimer - dt
        if b.breakTimer < 0 then b.breakTimer = 0 end
    end

    -- ③ 各 BOSS 的相位计时器（只记时，不产生效果）
    local phase, floor = b.phase, FloorOf(e)
    if phase >= 3 and floor == 1 then
        b.chargeTimer = b.chargeTimer + dt
        if b.chargeTimer >= CHARGE_EVERY then
            b.chargeTimer = b.chargeTimer - CHARGE_EVERY
            b.chargeReady = true
        end
    end
    if phase >= 2 and floor == 3 then
        b.ringTimer = b.ringTimer + dt
        if b.ringTimer >= RING_EVERY then
            b.ringTimer = b.ringTimer - RING_EVERY
            b.ringReady = true
        end
    end
    if phase >= 3 and floor == 3 and b.breakTimer <= 0 then
        b.breakCd = b.breakCd + dt
        if b.breakCd >= AUTO_BREAK_EVERY then
            b.breakCd = b.breakCd - AUTO_BREAK_EVERY
            b.breakTimer = AUTO_BREAK_TIME
        end
    end

    -- 兼容镜像：main.lua 的 BOSS 血条文案与旧 EnemyImpact 仍读 g.bossPhase（P1=0/P2=1/P3=2）
    if type(g) == "table" then g.bossPhase = phase - 1 end
    return phase
end

function BossPhases.SpeedMul(e) return SPEED_MUL[PhaseOf(e)] + 0.0 end
function BossPhases.CooldownMul(e) return CD_MUL[PhaseOf(e)] + 0.0 end
function BossPhases.DamageMul(e) return DMG_MUL[PhaseOf(e)] + 0.0 end
function BossPhases.BulletCount(e) return BULLET_COUNT[PhaseOf(e)] end

-- 文案自带 Boss 名时以 g.bossName 为准，改名后公告自动同步
local PHASE_LINES = {
    [1] = { [2] = "这活儿我顺手就帮你做了！", [3] = "这批需求我全接了，你别想跑！" },
    [2] = { [2] = "你这个月的绩效我重新看了。", [3] = "全组都留下，陪我一起加班。" },
    [3] = { [2] = "公司就是你们的家，住下吧。", [3] = "不服从的，明天不用来了。" },
}

function BossPhases.OnPhaseChange(g, e, phase)
    local floor = FloorOf(e)
    local p = math.floor(tonumber(phase) or 1)
    if p < 1 then p = 1 elseif p > 3 then p = 3 end
    local tail = PHASE_LINES[floor] and PHASE_LINES[floor][p] or "最后再补充一点！"
    local name = type(g) == "table" and g.bossName or nil
    if type(name) == "string" and name ~= "" then return name .. "：" .. tail end
    return tail
end

function BossPhases.BreakWindow(e)
    local b = type(e) == "table" and e.boss or nil
    if type(b) ~= "table" then return false end
    return (tonumber(b.breakTimer) or 0) > 0
end

-- 只延长不缩短：同一帧多次调用不会把长窗口改短
function BossPhases.OpenBreak(e, seconds)
    local b = BossPhases.Init(e)
    if not b then return 0 end
    local t = tonumber(seconds)
    if not t or t <= 0 then t = AUTO_BREAK_TIME end
    if t > b.breakTimer then b.breakTimer = t end
    return b.breakTimer
end

-- 秃头主管 P3：环形弹幕同时召 2 只 kind=2；其它 BOSS/相位不召唤
function BossPhases.SummonCount(e)
    if FloorOf(e) == 2 and PhaseOf(e) >= 3 then return 2 end
    return 0
end

function BossPhases.SummonKind(e)
    if FloorOf(e) == 2 then return 2 end
    return 1
end

function BossPhases.WantsCharge(e)
    local b = BossPhases.Init(e)
    if not b or not b.chargeReady then return false end
    b.chargeReady = false
    return true
end

function BossPhases.WantsRing(e)
    local b = BossPhases.Init(e)
    if not b or not b.ringReady then return false end
    b.ringReady = false
    return true
end

return BossPhases
