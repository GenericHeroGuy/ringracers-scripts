local cv_itembox_fuse = CV_RegisterVar({
    name = "itembox_fuse",
    defaultvalue = TICRATE/4,
    flags = CV_NETVAR,
    possiblevalue = { MIN = 1, MAX = TICRATE },
    description = "Time before ring/item box will respawn after being picked up",
})

local cv_itembox_ringboxtime = CV_RegisterVar({
    name = "itembox_ringboxtime",
    defaultvalue = "1.5",
    flags = CV_NETVAR|CV_FLOAT,
    possiblevalue = { MIN = 0, MAX = 3*FRACUNIT },
    description = "Time before ring box becomes item box again"
})

local S_RINGBOX1 = S_RINGBOX1
local S_RINGBOX12 = S_RINGBOX12

local function FixedTics(fixed)
    return fixed*TICRATE/FRACUNIT
end

-- No ringboxes
addHook("MobjThinker", function(mo)
    if mo.state >= S_RINGBOX1 and mo.state <= S_RINGBOX12 then
        if cv_itembox_ringboxtime.value == 0 then
            mo.state = S_RANDOMITEM1
        else
            mo.extravalue1 = max($, 3*TICRATE-FixedTics(cv_itembox_ringboxtime.value))
        end
    end

    mo.fuse = min($, cv_itembox_fuse.value)
end, MT_RANDOMITEM)
