-- "I want momentum"
-- Adds additional momenum from fastfall while in wallride state

-- NEEDS TO BE ADDED BEFORE NOFASTFALLBOUNCE.LUA

local MFE_JUSTHITFLOOR = MFE_JUSTHITFLOOR
local ANGLE_180 = ANGLE_180
local ANGLE_45 = ANGLE_45
local KSHIELD_BUBBLE = KSHIELD_BUBBLE
local FRACUNIT = FRACUNIT

local cv_wallboost_enabled = CV_RegisterVar {
    name = "walllaunch_boost",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Enables wall launch fastfall cancel and increased slope boost.",
}

local cv_wallboost = CV_RegisterVar {
    name = "walllaunch_boost_multiplier",
    defaultvalue = "1.5",
    possiblevalue = { MIN = 0, MAX = FRACUNIT*9001 },
    flags = CV_NETVAR|CV_FLOAT,
    description = "Wall launch slope land boost multiplier.",
}

local function DeterminedInvAngle(angle)
	return angle < ANGLE_180 and angle or InvAngle(angle)
end

-- map specific wallboosts
local wallboost_map = nil
addHook("MapLoad", function()
	wallboost_map = tonumber(mapheaderinfo[gamemap].wallboost_map)
end)
addHook("NetVars", function(net) wallboost_map = net($) end)

addHook("PlayerThink", function(p)
	-- let the map handle wallboosts if applicable.
	if wallboost_map ~= nil or cv_wallboost_enabled.value == 0 then return end

    -- the actual bounce is delayed by a tic for some reason, so this works
    if p.mo and p.mo.eflags & MFE_JUSTHITFLOOR and p.curshield ~= KSHIELD_BUBBLE then
		if p.fastfall and p.mo.standingslope ~= nil then
			-- print("fastfall....")
			-- make sure the slope is actually APPLICABLE for it.
			local slope = p.mo.standingslope
			local zangle = DeterminedInvAngle(slope.zangle)
			-- only on 45 degrees and above...
			if abs(zangle) >= ANGLE_45 then
				-- xydirection is weird....
				local flip = p.mo.eflags & MFE_VERTICALFLIP
				local thrustangle = 0
				if ((slope.zangle > 0) and flip) or ((slope.zangle < 0) and (not flip)) then
					thrustangle = slope.xydirection
				else
					thrustangle = (slope.xydirection + ANGLE_180)
				end
				P_InstaThrust(p.mo, thrustangle, abs(FixedMul(p.mo.lastmomz, cv_wallboost.value)))
				p.fastfall = 0
			end
		end
		-- the game will do a normal fast fall bounce if the above conditions arent met
    end
end)

addHook("PreThinkFrame", function()
	if wallboost_map ~= nil or cv_wallboost_enabled.value == 0 then return end
	
	for p in players.iterate do
		if p.mo.momz ~= 0 then
			-- landing will result in this becoming zero by the time we check, soooo
			p.mo.lastmomz = p.mo.momz
		end
	end
end)