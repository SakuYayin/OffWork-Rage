-- Generated alpha bounds; cell foot pivots avoid sliding and frame-dependent scaling.
local definitions = {
    male = { path = "image/sprites/male_chibi_atlas.png", width = 1254, height = 1254, referenceHeight = 280, sourceFacing = { idle = 1, walk = 1, attack = 1, skill = 1 }, frames = {
        idle = {
            { x = 85, y = 22, w = 155, h = 277, anchorX = 83 },
            { x = 395, y = 18, w = 160, h = 283, anchorX = 87 },
            { x = 707, y = 15, w = 163, h = 284, anchorX = 88.5 },
            { x = 1024, y = 23, w = 158, h = 276, anchorX = 85 },
        },
        walk = {
            { x = 80, y = 336, w = 158, h = 272, anchorX = 83 },
            { x = 395, y = 333, w = 159, h = 271, anchorX = 72.5 },
            { x = 707, y = 336, w = 159, h = 272, anchorX = 81.5 },
            { x = 1023, y = 336, w = 157, h = 269, anchorX = 69.5 },
        },
        attack = {
            { x = 81, y = 653, w = 165, h = 268, anchorX = 78.5 },
            { x = 370, y = 641, w = 185, h = 280, anchorX = 98 },
            { x = 690, y = 647, w = 226, h = 271, anchorX = 75.5 },
            { x = 1015, y = 651, w = 173, h = 270, anchorX = 80 },
        },
        skill = {
            { x = 81, y = 964, w = 161, h = 271, anchorX = 85.5 },
            { x = 389, y = 967, w = 166, h = 268, anchorX = 87.5 },
            { x = 699, y = 967, w = 180, h = 268, anchorX = 73.5 },
            { x = 1018, y = 965, w = 162, h = 270, anchorX = 85 },
        },
    }, directions = { path = "image/sprites/male_directions_atlas.png", width = 1254, height = 1254, referenceHeight = 272, sourceFacing = { downIdle = 1, downWalk = 1, upIdle = 1, upWalk = 1 }, frames = {
        downIdle = {
            { x = 85, y = 25, w = 154, h = 273, anchorX = 79 },
            { x = 398, y = 26, w = 154, h = 272, anchorX = 79 },
            { x = 711, y = 28, w = 155, h = 270, anchorX = 80 },
            { x = 1025, y = 27, w = 154, h = 271, anchorX = 78.5 },
        },
        downWalk = {
            { x = 85, y = 337, w = 154, h = 275, anchorX = 76.5 },
            { x = 398, y = 339, w = 154, h = 272, anchorX = 76.5 },
            { x = 712, y = 339, w = 154, h = 272, anchorX = 79.5 },
            { x = 1025, y = 339, w = 154, h = 272, anchorX = 79 },
        },
        upIdle = {
            { x = 84, y = 653, w = 155, h = 274, anchorX = 78 },
            { x = 398, y = 651, w = 154, h = 274, anchorX = 77.5 },
            { x = 711, y = 655, w = 155, h = 272, anchorX = 78 },
            { x = 1025, y = 652, w = 154, h = 273, anchorX = 77.5 },
        },
        upWalk = {
            { x = 84, y = 966, w = 155, h = 273, anchorX = 80 },
            { x = 397, y = 966, w = 155, h = 273, anchorX = 77.5 },
            { x = 711, y = 968, w = 155, h = 272, anchorX = 77 },
            { x = 1025, y = 966, w = 154, h = 273, anchorX = 74.5 },
        },
    } } },
    female = { path = "image/sprites/female_chibi_atlas.png", width = 1254, height = 1254, referenceHeight = 293, sourceFacing = { idle = -1, walk = -1, attack = 1, skill = 1 }, frames = {
        idle = {
            { x = 79, y = 10, w = 173, h = 294, anchorX = 89.5 },
            { x = 394, y = 9, w = 177, h = 295, anchorX = 88.5 },
            { x = 709, y = 17, w = 169, h = 287, anchorX = 87.5 },
            { x = 1018, y = 10, w = 173, h = 294, anchorX = 91.5 },
        },
        walk = {
            { x = 79, y = 324, w = 174, h = 292, anchorX = 85 },
            { x = 392, y = 320, w = 175, h = 296, anchorX = 92 },
            { x = 704, y = 325, w = 177, h = 291, anchorX = 90.5 },
            { x = 1020, y = 324, w = 174, h = 292, anchorX = 89.5 },
        },
        attack = {
            { x = 69, y = 645, w = 201, h = 284, anchorX = 102.5 },
            { x = 354, y = 636, w = 225, h = 293, anchorX = 126.5 },
            { x = 665, y = 646, w = 276, h = 283, anchorX = 109 },
            { x = 941, y = 641, w = 259, h = 288, anchorX = 165.5 },
        },
        skill = {
            { x = 70, y = 954, w = 183, h = 286, anchorX = 100.5 },
            { x = 368, y = 955, w = 207, h = 285, anchorX = 111.5 },
            { x = 665, y = 956, w = 239, h = 284, anchorX = 119.5 },
            { x = 1010, y = 953, w = 182, h = 287, anchorX = 99.5 },
        },
    }, directions = { path = "image/sprites/female_directions_atlas.png", width = 1254, height = 1254, referenceHeight = 292, sourceFacing = { downIdle = 1, downWalk = 1, upIdle = 1, upWalk = 1 }, frames = {
        downIdle = {
            { x = 85, y = 12, w = 168, h = 292, anchorX = 85 },
            { x = 397, y = 10, w = 169, h = 294, anchorX = 87 },
            { x = 711, y = 16, w = 170, h = 288, anchorX = 87 },
            { x = 1025, y = 12, w = 169, h = 292, anchorX = 85.5 },
        },
        downWalk = {
            { x = 83, y = 324, w = 170, h = 289, anchorX = 83.5 },
            { x = 398, y = 324, w = 169, h = 289, anchorX = 87 },
            { x = 711, y = 327, w = 169, h = 286, anchorX = 86.5 },
            { x = 1025, y = 324, w = 169, h = 290, anchorX = 88 },
        },
        upIdle = {
            { x = 87, y = 640, w = 167, h = 290, anchorX = 82.5 },
            { x = 401, y = 640, w = 166, h = 290, anchorX = 82 },
            { x = 714, y = 646, w = 167, h = 284, anchorX = 83 },
            { x = 1029, y = 642, w = 165, h = 288, anchorX = 82 },
        },
        upWalk = {
            { x = 86, y = 958, w = 168, h = 284, anchorX = 81.5 },
            { x = 401, y = 954, w = 166, h = 287, anchorX = 83.5 },
            { x = 714, y = 963, w = 167, h = 278, anchorX = 81 },
            { x = 1029, y = 958, w = 165, h = 283, anchorX = 83 },
        },
    } } },
}

for id,d in pairs(require("ExpansionArt").heroes)do d.directions=d;definitions[id]=d end
local stapler=require("ExpansionArt").heroOverrides.femaleStapler
for _,f in ipairs(stapler.frames.attack)do f.sheet=stapler end
definitions.female.frames.attack=stapler.frames.attack
local fufu=require("FufuArt").sheets.fufu
fufu.directions=fufu;fufu.sourceFacing={};fufu.frames.downIdle=fufu.frames.idle
definitions.fufu=fufu
return definitions
