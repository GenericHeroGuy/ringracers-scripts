local cv_fastspindash = CV_RegisterVar {
    name = "fastspindash",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Makes spindash faster if player has less rings"
}

local function rescale(value, oldmin, oldmax, newmin, newmax)
    return newmin + FixedMul(FixedDiv(value - oldmin, oldmax-oldmin), newmax - newmin)
end

local function spindashBonusChargeRate(p)
    return rescale(max(p.rings<<FRACBITS, 0), 0, 20<<FRACBITS, FRACUNIT, 0)
end

local function K_GetSpindashChargeTime(player)
	return ((player.kartspeed + 8) * TICRATE) / 6
end

-- .........................................
local function P_IsDisplayPlayer(player)
	if not player then
		return false
    end

    for dp in displayplayers.iterate do
        -- I should've also checked for freecam but SOMEONE didn't expose that to lua... Again...
        if player == dp then
            return true
        end
    end

	return false
end

-- Kart Krew more like Ew
local cv_reducevfx
local function S_ReducedVFXSound(origin, sfx, player)
    cv_reducevfx = $ or CV_FindVar("reducevfx")

    if cv_reducevfx.value then
        if not P_IsDisplayPlayer(player) then
            return
        end
    end

    S_StartSound(origin, sfx, player)
end

-- Why does it has to be so overcomplicated???
-- Actually dunno if this can be simplified, having too bad concentration for this at this point
local function shouldPlaySpindashSound(chargetime)
    local soundcharge = 0
    local add = 0

    while soundcharge < chargetime do
        add = $ + 1
        soundcharge = $ + add
    end

    return soundcharge == chargetime
end

addHook("PlayerThink", function(p)
    if cv_fastspindash.value and p.spindash and p.rings > 0 then
        local MAXCHARGETIME = K_GetSpindashChargeTime(p)

        p.spindashbonus = ($ or 0) + spindashBonusChargeRate(p)

        -- Sometimes sound gets skipped which feels weird
        local playsound = false

        while p.spindashbonus > FRACUNIT do
            p.spindashbonus = $ - FRACUNIT
            p.spindash = $ + 1

            if shouldPlaySpindashSound(MAXCHARGETIME - p.spindash) then
                playsound = true
            end
        end

        if playsound then
            S_ReducedVFXSound(p.mo, sfx_s3kab, p)
        end
    end
end)
