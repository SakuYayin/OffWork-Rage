-- 办公室动作游戏的模型生成音频；资源根目录已包含 assets，无需重复前缀。
-- 初始化只准备音源；开始游玩、开局或确认操作后才启动背景音乐。
-- 网页自动播放未验证；浏览器和设备的手势解锁由引擎处理。
--
-- cue 对照表（path 均为 audio/sfx/ 下 office_*.wav 复用；g=gain p=pitch v=variation cd=cooldown pri=priority）
-- swing:   keyboard_swing g0.36 p1    v0.06 cd0.10 pri2 | hit:    keyboard_hit  g0.58 p1    v0.07 cd0.055 pri4
-- staple:  stapler_click  g0.40 p1    v0.04 cd0.065 pri3 | hurt:   player_hurt   g0.55 p1    v0.03 cd0.12 pri7
-- burst:   rage_burst     g0.60 p1    v0    cd0.25 pri9 | pickup: xp_pickup     g0.23 p1    v0.07 cd0.065 pri1
-- upgrade: level_up       g0.48 p1    v0    cd0.25 pri8 | walking: footstep_walk g0.24 p1    v0.05 cd0.16 pri0
-- running: footstep_run   g0.30 p1    v0.07 cd0.12 pri0 | door:   door_open     g0.44 p1    v0    cd0.30 pri5
-- choose:  ui_confirm     g0.34 p1    v0    cd0.08 pri5 | coffee: keyboard_swing g0.24 p0.80 v0.03 cd0.15 pri2
-- boss:    rage_burst     g0.52 p0.86 v0    cd0.50 pri9 | start:  door_open     g0.44 p1    v0    cd0.25 pri6
-- win:     level_up       g0.52 p1.05 v0    cd0.35 pri9 |
-- thermosSwing: keyboard_swing g0.72 p0.78 v0.08 cd0.06 pri2 | thermosHit: keyboard_hit g0.85 p0.72 v0.10 cd0.05 pri3
-- paperclipShot: stapler_click g0.5 p1.32 v0.10 cd0.04 pri1 | pieThrow: keyboard_swing g0.6 p0.62 v0.06 cd0.10 pri1
-- pieBoom: rage_burst g0.7 p0.66 v0.05 cd0.12 pri2 | slam: rage_burst g1.0 p0.52 v0.03 cd0.2 pri4
-- scan: level_up g0.55 p1.42 v0.04 cd0.2 pri2 | charge: footstep_run g0.5 p0.70 v0.06 cd0.3 pri1
-- explode: keyboard_hit g0.9 p0.55 v0.08 cd0.15 pri3 | step_walk: footstep_walk g0.24 p1 v0.05 cd0.16 pri0 | step_run: footstep_run g0.30 p1 v0.07 cd0.12 pri0
local Audio = {}

---@class OfficeAudioPlayer
---@field moving boolean?
---@field walking boolean?
---@field running boolean?
---@field gait string?
---@field hp number?
---@class OfficeAudioGame
---@field mode string?
---@field player OfficeAudioPlayer?
---@field audioQueue string[]?
---@field bossSpawned boolean?
---@field bossDefeated boolean?
---@field hitStop number?
---@field paused boolean?

---@class OfficeAudioCue
---@field path string
---@field gain number
---@field pitch number
---@field variation number
---@field cooldown number
---@field priority number

---@class OfficeAudioVoice
---@field source SoundSource
---@field remaining number
---@field priority number
---@field key string

---@class OfficeMusicVoice
---@field source SoundSource
---@field running boolean
---@field gain number
---@field from number
---@field target number
---@field elapsed number
---@field duration number

local SFX_POOL_SIZE = 10
local MUSIC_PATH = "audio/overtime_overdrive.ogg"
---@type Scene?
local audioScene = nil -- 必须强引用场景本身，不能只保留其子节点。
---@type Sound?
local musicSound = nil
---@type OfficeAudioVoice[]
local voices = {}
---@type OfficeMusicVoice[]
local musicVoices = {}
---@type table<string, Sound>
local sounds = {}
---@type table<string, number>
local cooldowns = {}
local musicEnabled, sfxEnabled = true, true
local initialized, stopped, musicArmed = false, false, false
---@type integer
local activeMusic = 1
local musicContext = ""
---@type number
local footClock = 0.0
local footSide = 1
local lastPlaying = false

-- 完整路径使用字面量，便于增强引用构建发现音频资源。
---@type table<string, OfficeAudioCue>
local cues = {
    swing = { path = "audio/sfx/office_keyboard_swing.wav", gain = 0.36, pitch = 1, variation = 0.06, cooldown = 0.10, priority = 2 },
    hit = { path = "audio/sfx/office_keyboard_hit.wav", gain = 0.58, pitch = 1, variation = 0.07, cooldown = 0.055, priority = 4 },
    staple = { path = "audio/sfx/office_stapler_click.wav", gain = 0.40, pitch = 1, variation = 0.04, cooldown = 0.065, priority = 3 },
    hurt = { path = "audio/sfx/office_player_hurt.wav", gain = 0.55, pitch = 1, variation = 0.03, cooldown = 0.12, priority = 7 },
    burst = { path = "audio/sfx/office_rage_burst.wav", gain = 0.60, pitch = 1, variation = 0, cooldown = 0.25, priority = 9 },
    pickup = { path = "audio/sfx/office_xp_pickup.wav", gain = 0.23, pitch = 1, variation = 0.07, cooldown = 0.065, priority = 1 },
    upgrade = { path = "audio/sfx/office_level_up.wav", gain = 0.48, pitch = 1, variation = 0, cooldown = 0.25, priority = 8 },
    walking = { path = "audio/sfx/office_footstep_walk.wav", gain = 0.24, pitch = 1, variation = 0.05, cooldown = 0.16, priority = 0 },
    running = { path = "audio/sfx/office_footstep_run.wav", gain = 0.30, pitch = 1, variation = 0.07, cooldown = 0.12, priority = 0 },
    door = { path = "audio/sfx/office_door_open.wav", gain = 0.44, pitch = 1, variation = 0, cooldown = 0.30, priority = 5 },
    choose = { path = "audio/sfx/office_ui_confirm.wav", gain = 0.34, pitch = 1, variation = 0, cooldown = 0.08, priority = 5 },
    coffee = { path = "audio/sfx/office_keyboard_swing.wav", gain = 0.24, pitch = 0.80, variation = 0.03, cooldown = 0.15, priority = 2 },
    boss = { path = "audio/sfx/office_rage_burst.wav", gain = 0.52, pitch = 0.86, variation = 0, cooldown = 0.50, priority = 9 },
    start = { path = "audio/sfx/office_door_open.wav", gain = 0.44, pitch = 1, variation = 0, cooldown = 0.25, priority = 6 },
    win = { path = "audio/sfx/office_level_up.wav", gain = 0.52, pitch = 1.05, variation = 0, cooldown = 0.35, priority = 9 },
    thermosSwing = { path = "audio/sfx/office_keyboard_swing.wav", gain = 0.72, pitch = 0.78, variation = 0.08, cooldown = 0.06, priority = 2 },
    thermosHit = { path = "audio/sfx/office_keyboard_hit.wav", gain = 0.85, pitch = 0.72, variation = 0.10, cooldown = 0.05, priority = 3 },
    paperclipShot = { path = "audio/sfx/office_stapler_click.wav", gain = 0.5, pitch = 1.32, variation = 0.10, cooldown = 0.04, priority = 1 },
    pieThrow = { path = "audio/sfx/office_keyboard_swing.wav", gain = 0.6, pitch = 0.62, variation = 0.06, cooldown = 0.10, priority = 1 },
    pieBoom = { path = "audio/sfx/office_rage_burst.wav", gain = 0.7, pitch = 0.66, variation = 0.05, cooldown = 0.12, priority = 2 },
    slam = { path = "audio/sfx/office_rage_burst.wav", gain = 1.0, pitch = 0.52, variation = 0.03, cooldown = 0.2, priority = 4 },
    scan = { path = "audio/sfx/office_level_up.wav", gain = 0.55, pitch = 1.42, variation = 0.04, cooldown = 0.2, priority = 2 },
    charge = { path = "audio/sfx/office_footstep_run.wav", gain = 0.5, pitch = 0.70, variation = 0.06, cooldown = 0.3, priority = 1 },
    explode = { path = "audio/sfx/office_keyboard_hit.wav", gain = 0.9, pitch = 0.55, variation = 0.08, cooldown = 0.15, priority = 3 },
    step_walk = { path = "audio/sfx/office_footstep_walk.wav", gain = 0.24, pitch = 1, variation = 0.05, cooldown = 0.16, priority = 0 },
    step_run = { path = "audio/sfx/office_footstep_run.wav", gain = 0.30, pitch = 1, variation = 0.07, cooldown = 0.12, priority = 0 },
}

---@param voice OfficeMusicVoice
---@param target number
---@param duration number
local function FadeMusic(voice, target, duration)
    voice.from, voice.target = voice.gain, target
    voice.elapsed, voice.duration = 0, duration
end

local function StopFootsteps()
    footClock = 0
    for _, voice in ipairs(voices) do
        if voice.key == "walking" or voice.key == "running" then
            voice.source:Stop()
            voice.remaining, voice.priority, voice.key = 0, 0, ""
        end
    end
end

---@param key string
---@param pan number?
local function PlayCue(key, pan)
    if not sfxEnabled then return end
    local cue = cues[key]
    local sound = sounds[key]
    if not cue or not sound or (cooldowns[key] or 0) > 0 then return end
    ---@type OfficeAudioVoice?
    local selected = nil
    for _, voice in ipairs(voices) do
        if voice.remaining <= 0 or not voice.source:IsPlaying() then
            selected = voice
            break
        end
        if not selected or voice.priority < selected.priority
            or (voice.priority == selected.priority and voice.remaining < selected.remaining) then
            selected = voice
        end
    end
    if not selected or (selected.remaining > 0 and selected.priority > cue.priority) then return end
    -- 播放频率单位是绝对赫兹，不能直接传音高倍率。
    local pitch = cue.pitch + (math.random() - 0.5) * cue.variation
    selected.source:Play(sound, sound:GetFrequency() * pitch, cue.gain, pan or 0)
    selected.remaining = sound.length / pitch
    selected.priority, selected.key = cue.priority, key
    cooldowns[key] = cue.cooldown
end

---@param g OfficeAudioGame
---@return string, number
local function MusicMix(g)
    local mode = g.mode or "menu"
    if g.paused or mode == "paused" then return "paused", 0.065 end
    if mode == "menu" then return "menu", 0.10 end
    if mode == "character" then return "character", 0.12 end
    if mode == "shop" then return "shop", 0.14 end
    if mode == "event" then return "event", 0.13 end
    if mode == "upgrade" or mode == "route" then return mode, 0.12 end
    if mode == "lost" then return "lost", 0.055 end
    if mode == "won" then return "won", 0.18 end
    if mode == "playing" and g.bossSpawned and not g.bossDefeated then return "boss", 0.41 end
    if mode == "playing" then return "battle", 0.29 end
    return mode, 0.10
end

---@param context string
---@param gain number
---@param restart boolean
local function SelectMusic(context, gain, restart)
    if not musicSound or not musicEnabled or not musicArmed then return end
    local old = musicVoices[activeMusic]
    if context == musicContext and old and old.running and not restart then
        if old.target ~= gain then FadeMusic(old, gain, 0.45) end
        return
    end
    local position = 0.0
    if old and old.running and not restart then position = old.source:GetTimePosition() end
    ---@type integer
    local nextIndex = 1
    if activeMusic == 1 then nextIndex = 2 end
    local nextVoice = musicVoices[nextIndex]
    if not nextVoice then return end
    -- 两路音源对齐播放位置后交叉淡化，避免切换场景时重启旋律。
    nextVoice.source:Stop()
    nextVoice.source:Play(musicSound, 0, 0)
    if position > 0 and position < musicSound.length then nextVoice.source:Seek(position) end
    nextVoice.running, nextVoice.gain = true, 0
    local fadeTime = restart and 0.40 or 0.65
    FadeMusic(nextVoice, gain, fadeTime)
    if old and old.running then FadeMusic(old, 0, fadeTime) end
    activeMusic, musicContext = nextIndex, context
    local labels = { paused = "暂停", menu = "主菜单", character = "角色选择", shop = "商店", event = "事件", upgrade = "升级", route = "路线选择", lost = "失败", won = "胜利", boss = "首领战", battle = "战斗" }
    print(string.format("[声音] 音乐状态=%s，增益=%.3f，淡化=%.2f秒", labels[context] or "其他界面", gain, fadeTime))
end

---@param dt number
local function UpdateMusic(dt)
    for _, voice in ipairs(musicVoices) do
        if voice.running then
            voice.elapsed = math.min(voice.duration, voice.elapsed + dt)
            local t = voice.duration > 0 and voice.elapsed / voice.duration or 1
            local smooth = t * t * (3 - 2 * t)
            voice.gain = voice.from + (voice.target - voice.from) * smooth
            voice.source.gain = voice.gain
            if t >= 1 and voice.target <= 0 then
                voice.source:Stop()
                voice.running, voice.gain = false, 0
            end
        end
    end
end

-- 文件缺失或不可用时，资源查询可能返回空值。
---@param path string
---@return Sound?
local function LoadSound(path)
    return cache:GetResource("Sound", path)
end

---@return boolean
function Audio.Init()
    if initialized then return true end
    stopped = false
    audioScene = Scene()
    for i = 1, SFX_POOL_SIZE do
        local source = audioScene:CreateChild("OfficeSFX" .. i):CreateComponent("SoundSource")
        source.soundType, source.autoRemoveMode = SOUND_EFFECT, REMOVE_DISABLED
        source.declickEnabled = true
        voices[i] = { source = source, remaining = 0, priority = 0, key = "" }
    end
    for i = 1, 2 do
        local source = audioScene:CreateChild("OfficeMusic" .. i):CreateComponent("SoundSource")
        source.soundType, source.autoRemoveMode = SOUND_MUSIC, REMOVE_DISABLED
        source.declickEnabled = true
        musicVoices[i] = { source = source, running = false, gain = 0, from = 0, target = 0, elapsed = 0, duration = 0 }
    end
    local loaded = {}
    for key, cue in pairs(cues) do
        local sound = loaded[cue.path]
        if not sound then
            sound = LoadSound(cue.path)
            if sound then sound.looped = false; loaded[cue.path] = sound end
        end
        if sound then sounds[key] = sound
        else print("[声音] 音效资源缺失：" .. cue.path) end
    end
    musicSound = LoadSound(MUSIC_PATH)
    if musicSound then musicSound.looped = true
    else print("[声音] 背景音乐资源缺失：" .. MUSIC_PATH) end
    initialized = true
    print("[声音] 已就绪：10路音效池、2路音乐音源；已载入模型纯音乐和11项模型音效")
    return true
end

---@param g OfficeAudioGame
---@param dt number
function Audio.Update(g, dt)
    if stopped then
        if g.audioQueue then for i = #g.audioQueue, 1, -1 do g.audioQueue[i] = nil end end
        return
    end
    if not initialized then Audio.Init() end
    dt = math.max(0, math.min(dt or 0, 0.10))
    for key, left in pairs(cooldowns) do cooldowns[key] = math.max(0, left - dt) end
    for _, voice in ipairs(voices) do voice.remaining = math.max(0, voice.remaining - dt) end
    local playing = g.mode == "playing" and not g.paused
    if not playing and lastPlaying then StopFootsteps() end
    lastPlaying = playing
    local restart = false
    local explicitStep = false
    local seen = {}
    local queue = g.audioQueue or {}
    for _, queuedKey in ipairs(queue) do
        -- 先统一玩法层的步点事件名称，再做去重和显式步频判断。
        local key = queuedKey
        if key == "step_walk" then key = "walking"
        elseif key == "step_run" then key = "running" end
        if key == "start" then musicArmed, restart = true, true end
        if key == "choose" then musicArmed = true end
        if key == "walking" or key == "running" then
            explicitStep = true
            if playing and not seen[key] then
                PlayCue(key, footSide * 0.08)
                footSide = -footSide
                footClock = key == "walking" and 0.42 or 0.28
            end
        elseif not seen[key] then
            PlayCue(key)
        end
        seen[key] = true
    end
    -- 即使静音也原地消费队列，防止重新开启后补播积压音效。
    for i = #queue, 1, -1 do queue[i] = nil end
    if playing then musicArmed = true end
    local context, gain = MusicMix(g)
    SelectMusic(context, gain, restart)
    UpdateMusic(dt)

    local player = g.player
    if playing and player and player.moving and (player.hp or 1) > 0 and (g.hitStop or 0) <= 0 then
        -- 新玩法层按真实移动距离发出步点；仅旧状态缺少步态字段时启用自动节拍。
        if not explicitStep and player.gait == nil then
            footClock = footClock - dt
            if footClock <= 0 then
                local walking = player.walking == true and player.running ~= true
                PlayCue(walking and "walking" or "running", footSide * 0.08)
                footSide = -footSide
                footClock = walking and 0.42 or 0.28
            end
        end
    else
        footClock = 0
    end
end

---@param enabled boolean
function Audio.SetMusicEnabled(enabled)
    musicEnabled = enabled == true
    if musicEnabled then
        musicArmed, musicContext = true, ""
    else
        for _, voice in ipairs(musicVoices) do
            if voice.running then FadeMusic(voice, 0, 0.20) end
        end
        musicContext = ""
    end
    print("[声音] 背景音乐：" .. (musicEnabled and "开启" or "关闭"))
end

---@param enabled boolean
function Audio.SetSfxEnabled(enabled)
    sfxEnabled = enabled == true
    if not sfxEnabled then
        for _, voice in ipairs(voices) do
            voice.source:Stop()
            voice.remaining, voice.priority, voice.key = 0, 0, ""
        end
    end
    footClock = 0
    print("[声音] 动作音效：" .. (sfxEnabled and "开启" or "关闭"))
end

---@return boolean
function Audio.GetMusicEnabled() return musicEnabled end
---@return boolean
function Audio.GetSfxEnabled() return sfxEnabled end

function Audio.Stop()
    for _, voice in ipairs(voices) do voice.source:Stop() end
    for _, voice in ipairs(musicVoices) do voice.source:Stop() end
    voices, musicVoices, sounds, cooldowns = {}, {}, {}, {}
    musicSound = nil
    if audioScene then audioScene:Dispose(); audioScene = nil end
    initialized, stopped, musicArmed = false, true, false
    musicContext, footClock, lastPlaying = "", 0, false
    print("[声音] 已停止并释放音频场景")
end

return Audio
