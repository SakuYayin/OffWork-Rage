-- Authored effect cells keep fixed scale across each animation.
local definitions = {
loot = {path="image/effects/loot.png", width=1774, height=887, frames={
{x=0, y=0, w=444, h=444, content={x=130, y=123, w=259, h=279}},
{x=444, y=0, w=443, h=444, content={x=512, y=94, w=315, h=309}},
{x=887, y=0, w=444, h=444, content={x=910, y=55, w=364, h=354}},
{x=1331, y=0, w=443, h=444, content={x=1365, y=128, w=295, h=269}},
{x=0, y=444, w=444, h=443, content={x=130, y=519, w=264, h=279}},
{x=444, y=444, w=443, h=443, content={x=541, y=515, w=272, h=280}},
{x=887, y=444, w=444, h=443, content={x=953, y=497, w=278, h=300}},
{x=1331, y=444, w=443, h=443, content={x=1383, y=518, w=263, h=280}},
}},
weapon = {path="image/effects/weapon-fx.png", width=1261, height=1247, frames={
{x=0, y=0, w=315, h=312, content={x=90, y=140, w=203, h=167}},
{x=315, y=0, w=316, h=312, content={x=359, y=106, w=246, h=206}},
{x=631, y=0, w=315, h=312, content={x=661, y=133, w=231, h=169}},
{x=946, y=0, w=315, h=312, content={x=973, y=159, w=180, h=138}},
{x=0, y=312, w=315, h=312, content={x=118, y=464, w=150, h=77}},
{x=315, y=312, w=316, h=312, content={x=384, y=312, w=203, h=229}},
{x=631, y=312, w=315, h=312, content={x=667, y=454, w=191, h=93}},
{x=946, y=312, w=315, h=312, content={x=994, y=469, w=139, h=61}},
{x=0, y=624, w=315, h=311, content={x=119, y=699, w=137, h=141}},
{x=315, y=624, w=316, h=311, content={x=375, y=682, w=213, h=172}},
{x=631, y=624, w=315, h=311, content={x=662, y=693, w=195, h=157}},
{x=946, y=624, w=315, h=311, content={x=993, y=716, w=121, h=109}},
{x=0, y=935, w=315, h=312, content={x=89, y=995, w=204, h=140}},
{x=315, y=935, w=316, h=312, content={x=361, y=952, w=243, h=204}},
{x=631, y=935, w=315, h=312, content={x=661, y=966, w=219, h=169}},
{x=946, y=935, w=315, h=312, content={x=976, y=997, w=185, h=125}},
}},
area = {path="image/effects/area-fx.png", width=1261, height=1247, frames={
{x=0, y=0, w=315, h=312, content={x=108, y=136, w=109, h=82}},
{x=315, y=0, w=316, h=312, content={x=387, y=92, w=159, h=131}},
{x=631, y=0, w=315, h=312, content={x=672, y=94, w=216, h=148}},
{x=946, y=0, w=315, h=312, content={x=987, y=47, w=212, h=195}},
{x=0, y=312, w=315, h=312, content={x=53, y=352, w=211, h=180}},
{x=315, y=312, w=316, h=312, content={x=365, y=336, w=213, h=196}},
{x=631, y=312, w=315, h=312, content={x=676, y=360, w=212, h=264}},
{x=946, y=312, w=315, h=312, content={x=987, y=346, w=212, h=186}},
{x=0, y=624, w=315, h=311, content={x=92, y=679, w=139, h=143}},
{x=315, y=624, w=316, h=311, content={x=342, y=636, w=289, h=221}},
{x=631, y=624, w=315, h=311, content={x=631, y=624, w=285, h=263}},
{x=946, y=624, w=315, h=311, content={x=964, y=631, w=242, h=242}},
{x=0, y=935, w=315, h=312, content={x=96, y=1007, w=123, h=110}},
{x=315, y=935, w=316, h=312, content={x=362, y=960, w=198, h=188}},
{x=631, y=935, w=315, h=312, content={x=701, y=982, w=151, h=145}},
{x=946, y=935, w=315, h=312, content={x=1032, y=1016, w=121, h=88}},
}},
}

for id,d in pairs(require("ExpansionArt").effects)do definitions[id]=d end
definitions.clipProjectile={path="image/expansion/clip-projectile-v2.png",key="clipProjectile",width=1254,height=1254,
    frames={{x=0,y=410,w=1230,h=480}}}
return definitions
