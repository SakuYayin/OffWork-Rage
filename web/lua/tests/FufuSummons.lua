local S=require("FufuSummons")
local T={}
function T.Run()
    local s=S.New()
    for i=1,3 do
        local pet=S.Summon(s,function() return i end)
        assert(pet and pet.kind==S.kinds[i])
        assert(not S.Summon(s,function() return 1 end))
        S.Update(s,.8)
    end
    assert(s.charges==0 and #s.pets==3)
    S.Update(s,24)
    local pet,replaced=S.Summon(s,function() return 4 end)
    assert(pet.kind=="cat" and replaced.kind=="maple" and #s.pets==3)
    s.pets[1].hp=0
    S.Update(s,24)
    local _,removed=S.Summon(s,function() return 5 end)
    assert(not removed and #s.pets==3 and s.pets[3].kind=="dog")
    s.charges=1; s.cooldown=0
    local before=s.charges
    local ok=pcall(S.Summon,s,function() return 6 end)
    assert(not ok and s.charges==before)
    return true
end
return T
