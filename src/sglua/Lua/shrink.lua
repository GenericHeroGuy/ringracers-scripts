-- Created by Indev for Sunflower's Garden
local cv_shrinktime = CV_RegisterVar({
    name = "shrinktime",
    defaultvalue = "10",
    possiblevalue = { MIN = 1, MAX = 30 },
    flags = CV_NETVAR,
    description = "Shrink item duration"
})

addHook("MobjThinker", function(mo)
    mo.reactiontime = min($, cv_shrinktime.value*TICRATE)
end, MT_SHRINK_POHBEE)
