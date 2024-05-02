-- Tweaks for droptarget item

local cv_maxhp = CV_RegisterVar {
    name = "droptarget_maxhealth",
    defaultvalue = "1",
    possiblevalue = { MIN = 1, MAX = 3 },
    flags = CV_NETVAR,
    description = "Amount of hits a Drop Target can do before disappearing",
}

local function height(mo1, mo2)
    return mo1.z + mo1.height < mo2.z or mo2.z + mo2.height < mo1.z
end

local MT_DROPTARGET_SHIELD = MT_DROPTARGET_SHIELD

local function dropTargetCollision(mo1, mo2)
    if height(mo1, mo2) then return end

    mo1.health = min($, cv_maxhp.value)
    mo1.color = SKINCOLOR_LIME
end

addHook("MobjCollide", dropTargetCollision, MT_DROPTARGET)
addHook("MobjMoveCollide", dropTargetCollision, MT_DROPTARGET)
addHook("MobjCollide", dropTargetCollision, MT_DROPTARGET_SHIELD)
addHook("MobjMoveCollide", dropTargetCollision, MT_DROPTARGET_SHIELD)
