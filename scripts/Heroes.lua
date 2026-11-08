-- 角色只定义初始差异；局内BUFF仍由Game管理，不回写这份共享配置。
---@class HeroDefinition
---@field id string
---@field name string
---@field title string
---@field description string
---@field maxHp number
---@field speed number
---@field damage number
---@field portrait string 菜单/员工资料立绘
---@field sprite string 战斗小人动画图集
---@type HeroDefinition
local male = { id = "male", name = "陈准", title = "准点行动派",
    description = "脚步更快、精力更足，单次伤害较低。擅长穿过回廊，持续周旋。",
    maxHp = 130, speed = 188, damage = 0.85, portrait = "image/generated/male_portrait.png", sprite = "image/sprites/male_chibi_atlas.png" }
---@type HeroDefinition
local female = { id = "female", name = "林夏", title = "高效反击派",
    description = "脚步稍慢、精力较少。霰弹近距离一枪一个，远处散射无力——把麻烦逼到面前再解决。",
    maxHp = 90, speed = 156, damage = 1.30, portrait = "image/generated/female_portrait.png", sprite = "image/sprites/female_chibi_atlas.png" }

male.primaryWeapon="keyboard"
female.primaryWeapon="stapler"
local intern={id="intern",name="许宁",title="稳稳接住派",description="眼镜妹实习生，靠文件夹重击和护盾顶住麻烦。专属增益效果降低10%，通用增益效果只有50%。",
 maxHp=120,speed=130,damage=1.125,primaryWeapon="folder",shield=100,reduction=.30,
 portrait="image/sprites/intern.png",sprite="image/sprites/intern.png"}
local programmer={id="programmer",name="周序",title="二进制输出派",description="低体力、慢脚步，靠笔记本持续高速输出0和1；等级越高，子弹越狠。",
 maxHp=80,speed=138,damage=.75,primaryWeapon="binary",
 portrait="image/sprites/programmer.png",sprite="image/sprites/programmer.png"}
local fufu={id="fufu",name="符符",title="毛孩子带队派",description="糕点召唤动物伙伴，灯泡慢速远程支援。三格糕点逐格恢复，最多同时三位伙伴。",
 maxHp=100,speed=164,damage=1,primaryWeapon="cake",reduction=.10,
 portrait="image/fufu/portrait.png",sprite="image/fufu/fufu.png"}
local Heroes = { list = { male, female, intern, programmer, fufu } }

---@param id string?
---@return HeroDefinition
function Heroes.Get(id)
    for _, hero in ipairs(Heroes.list) do
        if hero.id == id then return hero end
    end
    return male
end

return Heroes
