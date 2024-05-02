local disable_ringsting = CV_RegisterVar({
	name = "disable_ringsting",
	defaultvalue = "On",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff,
	description = "Disables the Ring Sting mechanic if on."
})

local disable_ringdebt = CV_RegisterVar({
	name = "disable_ringdebt",
	defaultvalue = "On",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff,
	description = "Disables Ring debt if on."
})

local disable_spindash_overcharge = CV_RegisterVar({
	name = "disable_spindash_overcharge",
	defaultvalue = "On",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff,
	description = "Disables Spindash overcharge if on."
})

local disable_ooooimtumbling = CV_RegisterVar({
	name = "disable_tumble",
	defaultvalue = "Off",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff,
	description = "Disables Tumble if on."
})

local disable_stumble = CV_RegisterVar({
	name = "stumble_type",
	defaultvalue = "Stumble",
	flags = CV_NETVAR,
	possiblevalue = {Crusher = 0, Spinout = 1, Stumble = 2},
	description = "Changes the stumble type. Defaults with no changes."
})

-- spindash overcharge stuff
local function K_GetSpindashChargeTime(player)
	return ((player.kartspeed + 8) * TICRATE) / 6
end

local INSTAWHIP_RINGDRAINEVERY = TICRATE/2
local INSTAWHIP_CHARGETIME = 3*TICRATE/4

-- normal playr thinker hererer
local function unfuckhitlag(player)
	-- put the no ring debt here
	if disable_ringdebt.value then
		player.rings = max($, 0)
		-- silence instawhip ring drain
		if player.rings <= 0 and player.instawhipcharge > INSTAWHIP_CHARGETIME and leveltime % INSTAWHIP_RINGDRAINEVERY == 0 then
			S_StopSoundByID(player.mo, sfx_antiri)
		end
	end
	
	-- spindash overcharge
	if disable_spindash_overcharge.value then
		player.spindash = min($, K_GetSpindashChargeTime(player) + 1)
	end
end

addHook("PlayerThink", unfuckhitlag)

-- danm
local DMG_NORMAL = 0
local DMG_TUMBLE = 3
local DMG_STING = 4
local DMG_STUMBLE = 7
local DMG_WHUMBLE = 8
local DMG_CRUSHED = DMG_CRUSHED

addHook("MobjDamage", function(mo, inf, src, dmg, dtype)
	-- get type
	local dmgtype = (dtype & DMG_TYPEMASK)
	--print("DMG TYPE: " + tostring(dmgtype))
	-- this is the if statement ever
	if dmgtype == DMG_TUMBLE and disable_ooooimtumbling.value then
		-- redirect
		-- print("oooo im tumbling")
		P_DamageMobj(mo, inf, src, dmg, DMG_NORMAL)
		return true
	-- dumb hack
	elseif (dmgtype == DMG_STUMBLE or dmgtype == DMG_WHUMBLE or 
		src and src.valid and src.player and src.player.valid 
		and src.player.growshrinktimer > 0) and disable_stumble.value != 2 then
		-- redirects
		-- print("oooo im stumbling")
		-- normal spinout
		if disable_stumble.value == 1 then
			P_DamageMobj(mo, inf, src, dmg, DMG_NORMAL)
		-- crusher-style
		else
			P_DamageMobj(mo, inf, src, dmg, DMG_CRUSHED)
		end
		return true
	elseif (dmgtype == DMG_STING) and disable_ringsting.value then
		-- redirect
		-- print("dammit ring sting")
		return true
	end
end, MT_PLAYER)

-- remove collision on tumble invinc damage when tumbling is disabled
-- as well as ring loss
local function unfuckinvincandringloss(mo, mo2)
	-- make sure they are both players....
	if not (mo.type == MT_PLAYER and mo2.type == MT_PLAYER) return end
	
	local pone = mo.player
	local ptwo = mo2.player
	
	-- this is kinda funky as hell lmao
	-- remove rings on collision to prevent the ring drop
	-- then put back the rings on a thinkframe
	-- it works, but its kinda stupid
	if disable_ringsting.value then
		if pone.rings > 0 then
			pone.nrs_rings = pone.rings
			pone.rings = 0
		end
		if ptwo.rings > 0 then
			ptwo.nrs_rings = ptwo.rings
			ptwo.rings = 0
		end
		-- collision should still happen here....
	end
	
-- 	-- TODO: Bogus solution, come back to this later -haya
-- 	if disable_ooooimtumbling.value and pone.invincibilitytimer > 0 or ptwo.invincibilitytimer > 0 then
-- 		if pone.invincibilitytimer > 0 then
-- 			P_DamageMobj(mo2, mo, mo, 1)
-- 		elseif ptwo.invincibilitytimer > 0 then
-- 			P_DamageMobj(mo, mo2, mo2, 1)
-- 		end
-- 		return false
-- 	end
-- 	-- stumble
-- 	if disable_stumble.value == 1 and (pone.growshrinktimer > 0 or ptwo.growshrinktimer > 0) then
-- 		if pone.growshrinktimer > 0 then
-- 			P_DamageMobj(mo2, mo, mo, 1)
-- 		elseif ptwo.growshrinktimer > 0 then
-- 			P_DamageMobj(mo, mo2, mo2, 1)
-- 		end
-- 		return false
-- 	end
end

addHook("MobjCollide", unfuckinvincandringloss, MT_PLAYER)
addHook("MobjMoveCollide", unfuckinvincandringloss, MT_PLAYER)

-- nrs_rings haha
addHook("ThinkFrame", function()
	for p in players.iterate do
		p.nrs_rings = $ or 0
		if p.nrs_rings > 0 then
			p.rings = p.nrs_rings
			p.nrs_rings = 0
		end
	end
end)

addHook("MapLoad", function()
	for p in players.iterate do
		p.nrs_rings = 0
	end
end)