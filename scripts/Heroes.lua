-- 角色只定义初始差异；局内BUFF仍由Game管理，不回写这份共享配置。
---@class HeroDefinition
---@field id string
---@field name string
---@field title string
---@field description string
---@field maxHp number
---@field speed number
---@field damage number
---@field portrait string 原立绘；静态战斗fallback也只使用此完整原图
---@field sprite string? 保留供未来动画播放器接管；独立battle源图不作为身体比例标准
---@type HeroDefinition
local male = { id = "male", name = "陈准", title = "准点行动派",
    description = "脚步更快、精力更足，单次伤害较低。擅长穿过回廊，持续周旋。",
    maxHp = 130, speed = 188, damage = 0.85, portrait = "image/generated/male_portrait.png", sprite = "image/generated/male_battle.png" }
---@type HeroDefinition
local female = { id = "female", name = "林夏", title = "高效反击派",
    description = "脚步稍慢、精力较少，单次伤害更高。善用家具掩体，抓住反击时机。",
    maxHp = 90, speed = 156, damage = 1.30, portrait = "image/generated/female_portrait.png", sprite = "image/generated/female_battle.png" }

local Heroes = { list = { male, female } }

---@param id string?
---@return HeroDefinition
function Heroes.Get(id)
    for _, hero in ipairs(Heroes.list) do
        if hero.id == id then return hero end
    end
    return male
end

return Heroes
