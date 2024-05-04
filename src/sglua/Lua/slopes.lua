local cv_slopehelp = CV_RegisterVar({
    name = "slopehelp",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Give player small boost when going uphill",
})

local cv_slopehelp_speedboost = CV_RegisterVar({
    name = "slopehelp_speedboost",
    defaultvalue = "1.0",
    possiblevalue = CV_Unsigned,
    flags = CV_NETVAR|CV_FLOAT,
    description = "Amount of slopehelp speed boost given when going uphill"
})

local cv_slopehelp_accelboost = CV_RegisterVar({
    name = "slopehelp_accelboost",
    defaultvalue = "1.25",
    possiblevalue = CV_Unsigned,
    flags = CV_NETVAR|CV_FLOAT,
    description = "Amount of slopehelp acceleration boost given when going uphill"
})

addHook("MobjThinker", function(pmo)
    if cv_slopehelp.value == 0 then return end

    local player = pmo.player
    local slope = pmo.standingslope

    if not slope or (player.offroad and not (player.sneakertimer or player.hyudorotimer or player.invincibilitytimer)) then
        return
    end

    local flip = not (pmo.eflags & MFE_VERTICALFLIP)
	local momangle = pmo.angle

    local hillangle = 0

    if ((slope.zangle > 0) and flip) or ((slope.zangle < 0) and (not flip)) then
        hillangle = momangle - slope.xydirection
    else
        hillangle = momangle - (slope.xydirection + ANGLE_180)
    end

    hillangle = max(abs(hillangle) - ANG1*3, 0) -- ANG1*3 somehow fixes some slopes???

    if hillangle >= ANGLE_90 then
        return
    end

    local anglemult = FixedDiv(AngleFixed(ANGLE_90-hillangle), 90*FRACUNIT)
    local slopemult = FixedDiv(AngleFixed(min(abs(slope.zangle)+ANG1*3, ANGLE_90)), 90*FRACUNIT)

    local mult = FixedMul(anglemult, slopemult)

    local speedboost = min(FixedMul(mult, cv_slopehelp_speedboost.value), FRACUNIT)
    local accelboost = FixedMul(mult, cv_slopehelp_accelboost.value)

    player.speedboost = max($, speedboost)
    player.accelboost = max($, accelboost)
end, MT_PLAYER)
