-- Generated original PNG regions. Times are supplied by actual game simulation.
local definitions = {
ghost = { path = "image/sprites/enemies/ghost.png", width = 1024, height = 1536, referenceHeight = 223, frames = {
idle = {
{ x=43, y=25, w=164, h=224, anchorX=72 },
{ x=301, y=19, w=164, h=226, anchorX=72 },
{ x=555, y=26, w=164, h=222, anchorX=82 },
{ x=809, y=27, w=166, h=220, anchorX=73.5 },
},
walk = {
{ x=44, y=271, w=166, h=221, anchorX=78 },
{ x=301, y=270, w=165, h=222, anchorX=68 },
{ x=556, y=271, w=167, h=223, anchorX=74.5 },
{ x=814, y=274, w=161, h=219, anchorX=70.5 },
},
upWalk = {
{ x=44, y=523, w=163, h=226, anchorX=74 },
{ x=308, y=525, w=156, h=224, anchorX=71.5 },
{ x=560, y=526, w=161, h=223, anchorX=80 },
{ x=821, y=528, w=151, h=222, anchorX=76 },
},
downWalk = {
{ x=43, y=779, w=165, h=227, anchorX=72.5 },
{ x=299, y=778, w=165, h=227, anchorX=76.5 },
{ x=552, y=782, w=169, h=221, anchorX=80.5 },
{ x=814, y=780, w=162, h=225, anchorX=71 },
},
attack = {
{ x=37, y=1040, w=166, h=214, anchorX=82.5 },
{ x=277, y=1031, w=177, h=222, anchorX=91.5 },
{ x=538, y=1047, w=230, h=207, anchorX=75 },
{ x=768, y=1042, w=232, h=211, anchorX=148 },
},
defeat = {
{ x=39, y=1294, w=172, h=212, anchorX=81.5 },
{ x=285, y=1326, w=195, h=184, anchorX=81.5 },
{ x=543, y=1335, w=191, h=176, anchorX=93 },
{ x=808, y=1335, w=158, h=172, anchorX=91 },
},
}},
paper = { path = "image/sprites/enemies/paper.png", width = 1024, height = 1536, referenceHeight = 178, frames = {
idle = {
{ x=34, y=40, w=192, h=183, anchorX=96.5 },
{ x=294, y=38, w=185, h=175, anchorX=92.5 },
{ x=544, y=45, w=199, h=176, anchorX=100.5 },
{ x=805, y=46, w=187, h=176, anchorX=94 },
},
walk = {
{ x=37, y=289, w=184, h=188, anchorX=90 },
{ x=303, y=284, w=175, h=192, anchorX=82.5 },
{ x=556, y=289, w=181, h=186, anchorX=85.5 },
{ x=810, y=292, w=182, h=180, anchorX=82.5 },
},
upWalk = {
{ x=39, y=542, w=183, h=186, anchorX=88 },
{ x=293, y=540, w=180, h=185, anchorX=88.5 },
{ x=550, y=542, w=184, h=185, anchorX=94 },
{ x=810, y=544, w=175, h=180, anchorX=86 },
},
downWalk = {
{ x=30, y=800, w=191, h=189, anchorX=94.5 },
{ x=292, y=797, w=187, h=188, anchorX=89 },
{ x=547, y=798, w=185, h=190, anchorX=94 },
{ x=805, y=802, w=183, h=184, anchorX=91 },
},
attack = {
{ x=17, y=1069, w=198, h=167, anchorX=96 },
{ x=273, y=1048, w=210, h=189, anchorX=95 },
{ x=521, y=1058, w=247, h=176, anchorX=123.5 },
{ x=768, y=1058, w=224, h=175, anchorX=88 },
},
defeat = {
{ x=26, y=1315, w=196, h=182, anchorX=102 },
{ x=271, y=1357, w=223, h=144, anchorX=114 },
{ x=526, y=1353, w=217, h=150, anchorX=109 },
{ x=780, y=1345, w=211, h=147, anchorX=116.5 },
},
}},
message = { path = "image/sprites/enemies/message.png", width = 1024, height = 1536, referenceHeight = 209, frames = {
idle = {
{ x=24, y=23, w=203, h=214, anchorX=100.5 },
{ x=282, y=20, w=202, h=208, anchorX=100.5 },
{ x=543, y=33, w=193, h=206, anchorX=92.5 },
{ x=793, y=38, w=205, h=206, anchorX=101.5 },
},
walk = {
{ x=17, y=278, w=205, h=202, anchorX=106 },
{ x=283, y=275, w=195, h=189, anchorX=103 },
{ x=541, y=284, w=200, h=189, anchorX=97 },
{ x=797, y=289, w=196, h=195, anchorX=95 },
},
upWalk = {
{ x=26, y=538, w=201, h=200, anchorX=104.5 },
{ x=295, y=531, w=188, h=194, anchorX=94.5 },
{ x=536, y=538, w=211, h=200, anchorX=104 },
{ x=800, y=545, w=198, h=193, anchorX=98 },
},
downWalk = {
{ x=28, y=788, w=197, h=202, anchorX=101.5 },
{ x=282, y=786, w=203, h=201, anchorX=105.5 },
{ x=543, y=795, w=196, h=199, anchorX=99.5 },
{ x=796, y=795, w=201, h=199, anchorX=101.5 },
},
attack = {
{ x=15, y=1047, w=241, h=193, anchorX=91 },
{ x=256, y=1037, w=256, h=195, anchorX=104 },
{ x=512, y=1042, w=243, h=190, anchorX=59.5 },
{ x=783, y=1047, w=191, h=193, anchorX=97.5 },
},
defeat = {
{ x=24, y=1297, w=199, h=193, anchorX=83 },
{ x=281, y=1296, w=188, h=191, anchorX=93.5 },
{ x=539, y=1313, w=178, h=175, anchorX=81 },
{ x=811, y=1326, w=142, h=154, anchorX=69 },
},
}},
pot = { path = "image/sprites/enemies/pot.png", width = 1024, height = 1536, referenceHeight = 197, frames = {
idle = {
{ x=36, y=29, w=183, h=199, anchorX=91 },
{ x=295, y=41, w=180, h=187, anchorX=90 },
{ x=549, y=28, w=182, h=200, anchorX=90.5 },
{ x=805, y=25, w=182, h=203, anchorX=90 },
},
walk = {
{ x=39, y=284, w=179, h=204, anchorX=88.5 },
{ x=295, y=282, w=179, h=202, anchorX=84.5 },
{ x=552, y=282, w=177, h=203, anchorX=90.5 },
{ x=808, y=284, w=178, h=200, anchorX=87.5 },
},
upWalk = {
{ x=39, y=540, w=178, h=205, anchorX=92 },
{ x=296, y=540, w=177, h=201, anchorX=86 },
{ x=551, y=541, w=178, h=204, anchorX=91.5 },
{ x=807, y=541, w=178, h=201, anchorX=86.5 },
},
downWalk = {
{ x=35, y=796, w=184, h=202, anchorX=89 },
{ x=293, y=794, w=184, h=203, anchorX=93.5 },
{ x=549, y=797, w=182, h=201, anchorX=90.5 },
{ x=804, y=795, w=183, h=203, anchorX=95 },
},
attack = {
{ x=38, y=1054, w=179, h=197, anchorX=87.5 },
{ x=281, y=1056, w=201, h=195, anchorX=98.5 },
{ x=537, y=1039, w=219, h=210, anchorX=77.5 },
{ x=813, y=1057, w=177, h=192, anchorX=67 },
},
defeat = {
{ x=28, y=1311, w=197, h=197, anchorX=115 },
{ x=276, y=1368, w=220, h=140, anchorX=110.5 },
{ x=528, y=1354, w=224, h=159, anchorX=116.5 },
{ x=820, y=1383, w=159, h=130, anchorX=82.5 },
},
}},
coworker = { path = "image/sprites/enemies/coworker.png", width = 1254, height = 1254, referenceHeight = 191, frames = {
idle = {
{ x=101, y=18, w=153, h=191, anchorX=67 },
{ x=408, y=17, w=157, h=192, anchorX=73.5 },
{ x=721, y=19, w=156, h=190, anchorX=74 },
{ x=1035, y=19, w=157, h=190, anchorX=74 },
},
walk = {
{ x=101, y=221, w=154, h=191, anchorX=66.5 },
{ x=415, y=221, w=152, h=192, anchorX=63.5 },
{ x=726, y=221, w=156, h=189, anchorX=70.5 },
{ x=1045, y=221, w=149, h=192, anchorX=63 },
},
upWalk = {
{ x=97, y=427, w=148, h=190, anchorX=67 },
{ x=412, y=426, w=147, h=191, anchorX=64.5 },
{ x=728, y=427, w=145, h=190, anchorX=67.5 },
{ x=1042, y=426, w=144, h=191, anchorX=65 },
},
downWalk = {
{ x=102, y=630, w=148, h=195, anchorX=67.5 },
{ x=416, y=630, w=146, h=195, anchorX=66 },
{ x=726, y=630, w=149, h=195, anchorX=69.5 },
{ x=1043, y=630, w=148, h=195, anchorX=68 },
},
attack = {
{ x=91, y=843, w=163, h=186, anchorX=74.5 },
{ x=361, y=841, w=182, h=188, anchorX=90.5 },
{ x=665, y=845, w=246, h=184, anchorX=75 },
{ x=996, y=839, w=228, h=190, anchorX=67.5 },
},
defeat = {
{ x=64, y=1048, w=181, h=186, anchorX=98 },
{ x=336, y=1075, w=231, h=153, anchorX=107 },
{ x=637, y=1112, w=280, h=111, anchorX=146.5 },
{ x=962, y=1104, w=258, h=118, anchorX=149 },
},
}},
supervisor = { path = "image/sprites/enemies/supervisor.png", width = 1024, height = 1536, referenceHeight = 211, frames = {
idle = {
{ x=48, y=28, w=189, h=211, anchorX=84 },
{ x=306, y=28, w=185, h=211, anchorX=83.5 },
{ x=563, y=28, w=185, h=211, anchorX=82.5 },
{ x=819, y=30, w=184, h=209, anchorX=82 },
},
walk = {
{ x=59, y=285, w=181, h=210, anchorX=72.5 },
{ x=316, y=281, w=168, h=213, anchorX=61.5 },
{ x=571, y=285, w=177, h=210, anchorX=70 },
{ x=825, y=283, w=170, h=211, anchorX=70.5 },
},
upWalk = {
{ x=53, y=539, w=164, h=210, anchorX=70 },
{ x=319, y=538, w=156, h=211, anchorX=67 },
{ x=574, y=539, w=158, h=210, anchorX=66 },
{ x=830, y=539, w=156, h=209, anchorX=65 },
},
downWalk = {
{ x=54, y=791, w=175, h=214, anchorX=72 },
{ x=313, y=792, w=171, h=213, anchorX=68.5 },
{ x=569, y=792, w=174, h=213, anchorX=70 },
{ x=825, y=792, w=173, h=210, anchorX=71 },
},
attack = {
{ x=53, y=1052, w=172, h=202, anchorX=63 },
{ x=285, y=1052, w=176, h=203, anchorX=89.5 },
{ x=537, y=1055, w=221, h=199, anchorX=67 },
{ x=820, y=1052, w=177, h=202, anchorX=70.5 },
},
defeat = {
{ x=25, y=1309, w=189, h=201, anchorX=121.5 },
{ x=263, y=1307, w=223, h=204, anchorX=111.5 },
{ x=526, y=1327, w=216, h=179, anchorX=103 },
{ x=806, y=1341, w=182, h=157, anchorX=90.5 },
},
}},
owner = { path = "image/sprites/enemies/owner.png", width = 1024, height = 1536, referenceHeight = 197, frames = {
idle = {
{ x=33, y=35, w=201, h=196, anchorX=85 },
{ x=293, y=25, w=192, h=206, anchorX=76 },
{ x=543, y=38, w=200, h=193, anchorX=78 },
{ x=794, y=38, w=203, h=193, anchorX=76.5 },
},
walk = {
{ x=26, y=276, w=207, h=207, anchorX=78 },
{ x=305, y=277, w=179, h=207, anchorX=59.5 },
{ x=532, y=278, w=215, h=205, anchorX=98 },
{ x=823, y=280, w=177, h=204, anchorX=60 },
},
upWalk = {
{ x=33, y=534, w=185, h=209, anchorX=68.5 },
{ x=295, y=535, w=176, h=208, anchorX=65 },
{ x=551, y=534, w=173, h=209, anchorX=59.5 },
{ x=809, y=535, w=172, h=208, anchorX=58.5 },
},
downWalk = {
{ x=32, y=791, w=204, h=209, anchorX=70.5 },
{ x=291, y=791, w=194, h=209, anchorX=70 },
{ x=540, y=791, w=206, h=211, anchorX=87.5 },
{ x=802, y=793, w=196, h=207, anchorX=68 },
},
attack = {
{ x=30, y=1054, w=200, h=196, anchorX=83 },
{ x=274, y=1047, w=197, h=203, anchorX=96 },
{ x=515, y=1066, w=246, h=184, anchorX=115 },
{ x=801, y=1052, w=197, h=198, anchorX=75.5 },
},
defeat = {
{ x=34, y=1302, w=203, h=211, anchorX=82.5 },
{ x=266, y=1304, w=246, h=207, anchorX=127.5 },
{ x=512, y=1334, w=242, h=177, anchorX=121 },
{ x=789, y=1320, w=216, h=194, anchorX=107.5 },
},
}},
}

for id,d in pairs(require("ExpansionArt").enemies)do definitions[id]=d end
return definitions
