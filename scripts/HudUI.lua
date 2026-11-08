local UI=require("urhox-libs/UI")
local Skin=require("UISkin")
local Scale=require("InterfaceScale")
local Heroes=require("Heroes")
local Loadout=require("Loadout")
local Buffs=require("Buffs")
local FufuHud=require("FufuHud")
local Hud={}
-- onLeaderboard 是第 5 参（S1 新增）：只有无尽模式传入，主界面「撤回工位」按钮改跳排行榜。
-- 旧调用传 nil 时 onClick 原样是 onRoute，零回归。
-- onDash 是第 6 参（S3 新增）：「闪人」增益的闪避回调，未传时按钮仍建但点击无效。
function Hud.Build(g,onPause,onBurst,onRoute,onLeaderboard,onDash)
    local p=Scale.Get();local S=p.px;local r={};local children={}
    local function Add(w)children[#children+1]=w;return w end
    local compact=p.portrait or p.landscape
    -- 移动端 HP 卡收窄：横屏 290→170（≈136px）、竖屏 min(232,p.w-144)→min(200,p.w-150)，
    -- 卡高 82/74→66，头像 64→48，避免横屏时右边界顶到居中的 boss 血条。
    local cardW=p.portrait and math.min(200,p.w-150) or S(p.landscape and 170 or 304)
    local cardH=p.portrait and 66 or S(p.landscape and 66 or 90)
    local avatar= p.portrait and (p.w<370 and 42 or 50) or S(p.landscape and 48 or 64)
    -- 顶部条带几何（一处定义、两处复用）：波次提示与 boss 血条同宽；boss 血条贴屏幕最上面，
    -- 竖屏让到 HP 卡下方；room-status 与召唤物面板顺次下移，保证互不叠压。
    local noticeW=p.portrait and p.w-40 or math.min(p.w-40,S(480))
    local bossTop=p.portrait and(p.pad+cardH+6+(g.heroId=="intern"and 30 or 0))or p.pad
    local bossBlockH=38
    local hero=Heroes.Get(g.heroId)
    -- 横屏 HP 卡收窄到 S(170) 后右列只剩 ~70px：血量字号降到 11，否则 scrollWidth 溢出。
    r.hpLabel=Skin.Text("",p.landscape and 11 or(compact and 13 or 16),"cream",{id="hudHPText",fontFamily="mono",whiteSpace="nowrap"})
    r.levelLabel=Skin.Text("",11,"cream",{id="hudLevel",position="absolute",left=0,bottom=0,width="100%",textAlign="center",backgroundColor=Skin.Color("navy")})
    r.hpBar=UI.ProgressBar{id="hudHP",className="health-track",width="100%",height=compact and 10 or S(12),maxValue=1,value=1,fillColor=Skin.Color("hp"),backgroundColor={23,27,50,255},pointerEvents="none"}
    r.xpBar=UI.ProgressBar{id="hudXP",width="100%",height=4,maxValue=1,value=0,fillColor=Skin.Color("xp"),backgroundColor={20,27,50,255},pointerEvents="none"}
    Add(Skin.Panel{id="employeeIdentity",className="game-panel vitals",position="absolute",left=p.pad,top=p.pad,width=cardW,height=cardH,
        padding=compact and 8 or S(10),gap=compact and 8 or S(12),flexDirection="row",alignItems="center",pointerEvents="none",children={
            UI.Panel{width=avatar,height=cardH-16,flexShrink=0,backgroundColor={91,107,154,255},children={Skin.Avatar(g.heroId,avatar,avatar,"employeePortrait"),r.levelLabel}},
            UI.Panel{flexGrow=1,flexBasis=0,minWidth=0,gap=compact and 5 or S(8),children={
                UI.Panel{width="100%",flexDirection="row",justifyContent="space-between",alignItems="center",gap=3,children={Skin.Text(hero.name,compact and 14 or 16,"cream",{id="employeeName",whiteSpace="nowrap"}),r.hpLabel}},
                r.hpBar,r.xpBar
            }}
        }} )
    r.roomLabel=Skin.Text("",14,"cream",{id="hudRoom",textAlign="center"})
    r.statusLabel=Skin.Text("",compact and 18 or 22,"cream",{id="hudStatus",textAlign="center",className="world-text"})
    r.timeBar=UI.ProgressBar{width="100%",height=3,maxValue=1,fillColor=Skin.Color("yellow"),backgroundColor={137,147,176,100}}
    local fufuPortrait=p.portrait and g.heroId=="fufu"
    local statusLeft=fufuPortrait and(p.pad+math.floor(p.w*.4)+10)or(p.portrait and 20 or p.w*.32)
    Add(UI.Panel{className="room-status",position="absolute",left=statusLeft,top=bossTop+bossBlockH+8,
        width=fufuPortrait and(p.w-statusLeft-p.pad)or(p.portrait and p.w-40 or p.w*.36),gap=S(8),alignItems="center",pointerEvents="none",children={r.roomLabel,r.statusLabel,UI.Panel{width=S(92),children={r.timeBar}}}})
    r.timerLabel=Skin.Text("",compact and 19 or 23,"cream",{id="hudTimer",fontFamily="mono",textAlign="right",whiteSpace="nowrap"})
    r.coinLabel=Skin.Text("",compact and 13 or 15,"yellow",{id="hudCoins",textAlign="right",whiteSpace="nowrap"})
    r.pauseButton=Skin.Button{id="pauseButton",text="Ⅱ",variant="secondary",ariaLabel="暂停游戏",width=math.max(44,S(48)),height=math.max(44,S(48)),className="game-button secondary pause-control",fontSize=S(24),onClick=onPause}
    Add(UI.Panel{position="absolute",right=p.pad,top=p.pad,width=p.portrait and 108 or S(150),gap=compact and 8 or S(16),flexDirection="row",alignItems="flex-start",children={
        UI.Panel{flexGrow=1,flexBasis=0,minWidth=0,gap=6,pointerEvents="none",children={r.timerLabel,
            UI.Panel{width="100%",flexDirection="row",justifyContent="flex-end",gap=4,alignItems="center",children={Skin.Icon("item","coin",compact and 17 or S(20),compact and 17 or S(20)),r.coinLabel}}}},r.pauseButton}})
    -- 剩余怪物数：文案由 main.lua 填（本文件只建元素，初始为空串）。
    -- top 取「暂停区实际高度」而非固定 48：桌面端右上列是 timer(23)+gap6+coin(15)≈57px，
    -- 比暂停按钮高，用 48 会让文本压住金币行；紧凑端仍为 44。
    local topStackH=math.max(44,S(48))
    if not compact then topStackH=math.max(topStackH,math.ceil(S(23)*1.35)+6+math.ceil(S(15)*1.35)) end
    r.enemiesLeft=Add(Skin.Text("",compact and 11 or 13,"cream",{id="hudEnemiesLeft",position="absolute",right=p.pad,top=p.pad+topStackH+8,textAlign="right",whiteSpace="nowrap",pointerEvents="none"}))
    if not compact then
        r.routeProgress=Skin.Text("",12,"cream",{id="hudRouteProgress"})
        Add(Skin.Panel{position="absolute",right=p.pad,top=S(118),width=S(190),padding=S(14),gap=S(8),pointerEvents="none",children={Skin.Text("下班路线",12,"lightMuted"),r.routeProgress}})
    end
    local equipment={}
    -- Fixed primary plus one acquired weapon; every weapon has its own generated icon.
    local EQUIP_ORDER=Loadout.List(g)
    local NO_ICON={}
    for _,id in ipairs(EQUIP_ORDER)do
        -- S3：thermos/paperclip/pie 的等级走 Weapons.Upgrade→g.weapons（恒同步）；g.upgrades[id] 是兜底路径，
        -- 因为 Game.Choose 目前只写 g.upgrades 不调 Weapons.Upgrade——卡出过就该显示，避免等级表断链时槽位永久隐藏。
        local lvl=math.max((g.weapons and(g.weapons[id]or 0)or 0),(g.upgrades and(g.upgrades[id]or 0)or 0))
        local unlocked=Loadout.Has(g,id)
        if unlocked then
            local label=Skin.Text("",compact and(g.heroId=="fufu"and 9 or 11)or 12,"cream",{id="equipment_"..id,textAlign="center",whiteSpace="nowrap"})
            r[id.."Level"]=r[id.."Level"]or label
            local slotChildren
            if NO_ICON[id] then
                slotChildren={label}
            else
                slotChildren={Skin.Icon("item",id,compact and 40 or S(58),compact and 34 or S(46)),label}
            end
            equipment[#equipment+1]=Skin.Panel{id="slot_"..id,className="game-panel equipment-slot",
                width=NO_ICON[id]and(compact and 44 or S(56))or(compact and 51 or S(76)),
                height=compact and 58 or S(80),
                padding=3,gap=2,alignItems="center",pointerEvents="none",children=slotChildren}
        end
    end
    Add(UI.Panel{position="absolute",left=p.landscape and 135 or p.pad,bottom=p.portrait and 134 or(p.landscape and 17 or S(50)),
        flexDirection=p.portrait and g.heroId~="fufu"and"column"or"row",gap=S(8),pointerEvents="none",children=equipment})
    r.loadoutKey=table.concat(EQUIP_ORDER,",")
    if g.heroId=="intern"then
        r.shieldLabel=Skin.Text("",11,"teal",{id="hudShieldText"})
        r.shieldBar=UI.ProgressBar{id="hudShield",width="100%",height=5,maxValue=1,fillColor={76,203,184,255},backgroundColor={38,65,72,255}}
        Add(UI.Panel{id="internShieldHud",className="shield-meter",position="absolute",left=p.pad,top=p.pad+cardH+6,width=cardW,
            pointerEvents="none",children={r.shieldLabel,r.shieldBar}})
    end
    r.buffBelt=Add(UI.Panel{id="hudBuffs",position="absolute",left=p.landscape and 135 or p.pad,
        bottom=p.portrait and(g.heroId=="fufu"and 195 or 338)or(p.landscape and 87 or S(145)),flexDirection="row",gap=S(6),pointerEvents="none"})
    r.rageBar=UI.ProgressBar{id="hudRage",visible=g.heroId~="fufu",width="100%",height=5,maxValue=1,fillColor=Skin.Color("yellow"),backgroundColor={137,147,176,100}}
    -- 召唤面板顶边：横屏/桌面让到 HP 卡下方（卡高已缩小），竖屏让到 boss 血条下方。
    local petTop=(p.landscape or not p.portrait)and(p.pad+cardH+8)or(bossTop+bossBlockH+8)
    if g.heroId=="fufu"then r.fufu=FufuHud.Build(p,petTop);Add(r.fufu.petPanel)end
    r.burstLabel=Skin.Text("",compact and 17 or 20,"ink",{id="burstLabel",whiteSpace="nowrap"})
    r.burstHint=Skin.Text(g.heroId=="fufu"and(compact and"点按召唤"or"空格召唤")or(compact and"点击释放"or"空格释放"),11,"ink")
    r.burstButton=Skin.Button{id="burstButton",ariaLabel=g.heroId=="fufu"and"使用糕点召唤伙伴"or"释放拒绝加班",width=p.portrait and(p.w<370 and 110 or 137)or S(203),height=p.portrait and 76 or S(70),padding=6,
        flexDirection="row",gap=S(6),alignItems="center",justifyContent="center",onClick=onBurst,children={
            Skin.Icon(g.heroId=="fufu"and"item"or"buff",g.heroId=="fufu"and"cake"or"rage",compact and 38 or S(47),compact and 45 or S(53)),
            UI.Panel{gap=5,minWidth=0,pointerEvents="none",children={r.burstLabel,r.burstHint}}
        }}
    Add(UI.Panel{position="absolute",right=p.pad,bottom=p.portrait and 32 or (p.landscape and 17 or S(35)),gap=S(8),children={r.fufu and r.fufu.chargeBar or r.rageBar,r.burstButton}})
    -- 闪避（「闪人」增益）：元素常建、按增益有无切换 visible——因为拿到增益只走 UpdateHUD，
    -- 不会重建 HUD，若按「有增益才建」实现，中途拿到闪人后按钮要等到旋转屏幕才出现。
    -- 独立定位在爆发面板上方一档：爆发面板底边 32/17/S(35) + 高约 89/67/83，故取 130/104/S(126)；
    -- 右侧竖列不与左侧装备槽、buff 栏、摇杆（左下）以及底部居中的全屏按钮相交。
    r.dashLabel=Skin.Text("闪避",compact and 13 or 15,"cream",{id="dashLabel",whiteSpace="nowrap",textAlign="center"})
    r.dashButton=Skin.Button{id="dashButton",tone="mint",ariaLabel="闪避",width=compact and 96 or S(120),height=compact and 44 or S(44),
        padding=4,flexDirection="row",gap=S(6),alignItems="center",justifyContent="center",onClick=onDash,
        visible=Buffs.Level(g,"dash")>0,
        children={Skin.Icon("buff","speed",compact and 26 or 30,compact and 26 or 30),r.dashLabel}}
    -- 外层不能设 pointerEvents="none"：那会让整块区域点不到按钮（canvas 抢走指针）。
    Add(UI.Panel{position="absolute",right=p.pad,bottom=p.portrait and 130 or(p.landscape and 104 or S(126)),children={r.dashButton}})
    r.routeButton=Skin.Button{id="roomExitButton",position="absolute",left=p.portrait and 20 or p.w/2-S(140),bottom=p.portrait and 245 or S(110),
        width=p.portrait and p.w-40 or S(280),text="",visible=false,
        onClick=function() if g.endless and g.endless.active and onLeaderboard then onLeaderboard() else onRoute() end end}
    Add(r.routeButton)
    r.noticeLabel=Add(Skin.Text("",compact and 13 or 17,"cream",{id="hudAnnouncement",className="game-notice",position="absolute",
        left=p.portrait and 20 or (p.w-noticeW)/2,top=p.portrait and(g.heroId=="intern"and 227 or(g.heroId=="fufu"and 285 or 187))or(g.heroId=="fufu"and p.landscape and 230 or S(175)),width=noticeW,
        padding=S(10),textAlign="center",backgroundColor=Skin.Color("navy"),visible=false,pointerEvents="none"}))
    r.bossLabel=Skin.Text("",18,"cream",{textAlign="center"})
    r.bossBar=UI.ProgressBar{width="100%",height=7,maxValue=1,fillColor=Skin.Color("hp"),backgroundColor={23,27,50,255}}
    -- boss 血条：全部视口贴屏幕最上面，宽度与波次提示一致（noticeW）并水平居中；
    -- 竖屏放到 HP 卡下方（intern 再让出护盾条 30px）。可见性仍由 main.lua 控制。
    local bossLeft=p.portrait and 20 or (p.w-noticeW)/2
    Add(UI.Panel{id="bossHud",position="absolute",left=bossLeft,top=bossTop,width=noticeW,gap=6,visible=false,pointerEvents="none",children={r.bossLabel,r.bossBar}})
    Add(Skin.Text("WASD 移动     Shift 慢走     Z 闪避     Esc 暂停",11,"lightMuted",{id="movementHelp",position="absolute",left=p.w/2-S(220),bottom=S(20),width=S(440),textAlign="center",visible=not compact,pointerEvents="none"}))
    -- 摇杆上移 28px 只在横屏生效：竖屏（390x844）bottom=52 会让顶边 698 压住装备槽底边 710（重叠 12px），
    -- 竖屏保持 24（顶边 726，与装备槽留 16px 间隙）；横屏 52 后顶边 244、底边距屏幕底 52。
    if compact then Add(UI.Panel{id="joystick",className="touch-joystick",position="absolute",left=24,bottom=p.landscape and 52 or 24,width=94,height=94,pointerEvents="none",children={
        UI.Panel{id="joystickKnob",className="touch-knob",position="absolute",left=24,top=24,width=44,height=44,pointerEvents="none"}}}) end
    r.layer=UI.Panel{id="hudLayer",width="100%",height="100%",position="absolute",top=0,left=0,pointerEvents="box-none",children=children}
    return r
end
function Hud.Update(r,g)
    r.layer:SetVisible(g.mode~="menu" and g.mode~="character")
    local endless = g.endless and g.endless.active
    for _,id in ipairs(Loadout.List(g))do
        local label=r[id.."Level"]
        if label then
            local level=id=="keyboard"and 1+(g.upgrades.attack or 0)or(id=="stapler"and g.stapler or(id=="coffee"and g.coffee or math.max(1,g.weapons and g.weapons[id]or 0)))
            if g.heroId=="fufu"and(id=="cake"or id=="bulb")then label:SetText((id=="cake"and"糕点"or"灯泡").."·固定")
            else label:SetText((Loadout.names[id]or id).." "..level)end
        end
    end
    if r.shieldLabel then
        r.shieldLabel:SetText("护盾 "..math.ceil(g.shield or 0).." / "..math.floor(g.shieldMax or 100))
        r.shieldBar:SetValue(math.max(0,math.min(1,(g.shield or 0)/math.max(1,g.shieldMax or 100))))
    end
    -- S2：槽位动态化后 coffee/stapler 未解锁时无槽，需判空。
    if r.coffeeLevel then r.coffeeLevel:SetText(g.coffee>0 and "咖啡 "..g.coffee or "未解锁")end
    if r.staplerLevel then r.staplerLevel:SetText(g.stapler>0 and "订书机 "..g.stapler or "未解锁")end
    if r.routeProgress then
        if endless then
            -- 无尽：榜按钮常驻（不依赖 roomCleared），文案跟着局内状态走。
            r.routeProgress:SetText("加班无尽 · 已击破 "..(g.endless.bossLevel or 0).." 名首领")
        else
            r.routeProgress:SetText("第 "..g.floor.." 层 · 已清理 "..g.roomsCleared.." 区")
        end
    end
    local p=Scale.Get();local tiny=p.portrait and p.w<370
    if r.fufu then
        local charges,cooling=FufuHud.Update(r.fufu,g)
        r.burstLabel:SetText((p.portrait or p.landscape)and"召唤"or"召唤伙伴")
        r.burstHint:SetText(cooling and"稍等片刻"or((p.portrait or p.landscape)and"点按召唤"or"空格召唤"))
        r.burstButton:SetDisabled(charges<=0 or cooling)
    else
        r.burstLabel:SetText(g.rage>=100 and(tiny and "爆发"or"拒绝加班")or((tiny and ""or"怒气 ")..math.floor(g.rage).."%"))
    end
    -- 闪避按钮：文案/可用性都从 Buffs.DashState 只读快照取，不推进任何计时。
    -- 就绪→「闪避」可点；冲刺中→「闪避中」；冷却→「闪避 2.3」并置灰。
    if r.dashButton then
        local dash=Buffs.DashState(g)
        r.dashButton:SetVisible(dash.level>0)
        r.dashButton:SetDisabled(not dash.ready or g.mode~="playing")
        r.dashLabel:SetText(dash.active and"闪避中"or(dash.ready and"闪避"or string.format("闪避 %.1f",dash.cooldown)))
    end
    local ids={};for _,d in ipairs(require("Game").upgradeDefs)do if(g.upgrades[d.id]or 0)>0 then ids[#ids+1]=d.id end end
    -- Buff order and artwork follow actual definitions, including hero-specific buffs.
    for _,def in ipairs(Buffs.LIST)do if(g.buffs and(g.buffs[def.id]or 0)>0)then ids[#ids+1]=def.id end end
    local key=table.concat(ids,",")
    if key~=r.buffKey then
        r.buffKey=key;r.buffBelt:ClearChildren()
        local p=Scale.Get();local cap=p.portrait and 5 or 9
        local shown=math.min(cap,#ids)
        for i=1,shown do
            r.buffBelt:AddChild(Skin.Icon("buff",ids[i],p.px(30),p.px(30),"buffIcon_"..ids[i]))
        end
        if #ids>shown then r.buffBelt:AddChild(Skin.Text("+"..(#ids-shown),11,"lightMuted",{width=p.px(30)}))end
    end
end
return Hud
