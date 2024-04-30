local cv_disable_ringboxes = CV_RegisterVar({
	name = "disable_ringboxes",
	defaultvalue = "On",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff,
	description = "Disables ringboxes",
})

local cv_itembox_fuse = CV_RegisterVar({
    name = "itembox_fuse",
    defaultvalue = TICRATE/4,
    flags = CV_NETVAR,
    possiblevalue = { MIN = 1, MAX = TICRATE },
    description = "Time before ring/item box will respawn after being picked up",
})

local S_RINGBOX1 = S_RINGBOX1
local S_RINGBOX12 = S_RINGBOX12

-- No ringboxes
addHook("MobjThinker", function(mo)
	if cv_disable_ringboxes.value then
        if mo.state >= S_RINGBOX1 and mo.state <= S_RINGBOX12 then
            mo.state = S_RANDOMITEM1
        end
    end

    mo.fuse = min($, cv_itembox_fuse.value)
end, MT_RANDOMITEM)
