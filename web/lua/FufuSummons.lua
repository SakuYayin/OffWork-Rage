-- 符符的召唤储备与伙伴顺序；战斗行为由宿主调用方负责。
local M = {}
M.kinds = {"maple", "water", "dan", "cat", "dog"}
-- 哑炮：丹旺旺不主动出手、水龙龙每跳仅 6 点，连续抽到它们会让整条召唤线空转。
M.DULL = { dan = true, water = true }
M.stats = {
    maple={hp=180}, water={hp=153}, dan={hp=540}, cat={hp=162}, dog={hp=306},
}
function M.New()
    return {charges=3, recovery=0, cooldown=0, pets={}, nextId=0, dryStreak=0}
end
function M.Update(state, dt, recoveryMultiplier)
    dt=math.max(0,dt or 0)
    state.cooldown=math.max(0,state.cooldown-dt)
    if state.charges>=3 then state.recovery=0; return end
    local interval=math.max(8,12/(recoveryMultiplier or 1))
    state.recovery=state.recovery+dt
    while state.charges<3 and state.recovery>=interval do
        state.recovery=state.recovery-interval
        state.charges=state.charges+1
    end
    if state.charges==3 then state.recovery=0 end
end
function M.RemoveDead(state)
    for i=#state.pets,1,-1 do
        if state.pets[i].hp<=0 then table.remove(state.pets,i) end
    end
end
-- rng must implement math.random(1,5); each draw is independent.
function M.Summon(state, rng)
    M.RemoveDead(state)
    if state.charges<=0 or state.cooldown>0 then return nil end
    local index=(rng or math.random)(1,#M.kinds)
    assert(type(index)=="number" and index%1==0 and index>=1 and index<=#M.kinds,"invalid summon roll")
    local kind=M.kinds[index]
    -- 保底：连续两只哑炮之后，下一只强制为输出型。
    -- 用 nextId 轮转而不是再掷一次骰子，避免改变 rng 调用次数（测试用单值 rng）。
    if (state.dryStreak or 0)>=2 and M.DULL[kind] then
        kind=({ "maple", "cat", "dog" })[(state.nextId%3)+1]
    end
    state.dryStreak=M.DULL[kind] and (state.dryStreak or 0)+1 or 0
    local replaced
    if #state.pets>=3 then replaced=table.remove(state.pets,1) end
    state.nextId=state.nextId+1
    local hp=M.stats[kind].hp
    local pet={id=state.nextId,kind=kind,hp=hp,maxHp=hp,protection=3}
    state.pets[#state.pets+1]=pet
    state.charges=state.charges-1
    state.cooldown=.4
    return pet,replaced
end
return M
