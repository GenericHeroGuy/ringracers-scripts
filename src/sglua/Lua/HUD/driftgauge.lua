-- I wanna take a nap
-- splitscreen is unsupported as of yet
-- GenericHeroGuy: now it is! ...sort of
-- G from future: it definitely is now!
-- G from the distant future: it was always broken lmao

-- oh wow, this looks way cooler now
-- thanks Spee! :3

local driftskins = {
	[0] = SKINCOLOR_BLACK,
	SKINCOLOR_SILVER,
	SKINCOLOR_BANANA,
	SKINCOLOR_CREAMSICLE,
	SKINCOLOR_BLUE,
}

local cv_driftgauge = CV_RegisterVar({
	name = "driftgauge",
	defaultvalue = "On",
	possiblevalue = CV_OnOff,
	displayname = "Driftgauge",
	description = "Display your drift level below your character."
})

local cv_driftgaugeofs = CV_RegisterVar({
	name = "driftgaugeoffset",
	defaultvalue = "-20",
	flags = CV_FLOAT,
	possiblevalue = { MIN = -FRACUNIT*128, MAX = FRACUNIT*128 },
	displayname = "Driftgauge offset",
	description = "Vertical offset for driftgauge.",
})

local cv_driftgaugetrans = CV_RegisterVar({
	name = "driftgaugetransparency",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,
	displayname = "Driftgauge transparency",
	description = "Make the driftgauge follow your HUD transparency."
})

local cv_driftgaugecolorized = CV_RegisterVar({
	name = "driftgaugecolorized",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,
	displayname = "Driftgauge color",
	description = "Colorize driftgauge background. Inverted if colorizedhud is enabled."
})

local cv_colorizedhud
local cv_colorizedhudcolor

-- Latest saturn would have better functions for this but before release i do it like that for now
local function useColorizedHud()
    if cv_colorizedhud == nil then
        cv_colorizedhud = CV_FindVar("colorizedhud") or false
        cv_colorizedhudcolor = CV_FindVar("colorizedhudcolor") or false
    end

    if cv_colorizedhud then
        return cv_colorizedhud.value ~= cv_driftgaugecolorized.value
    end

    return cv_driftgaugecolorized.value
end

local function getBackgroundPatch(v)
    return v.cachePatch(useColorizedHud() and "K_DGAUC" or "K_DGAU")
end

local function getBackgroundColormap(v, p)
    if not useColorizedHud() then return end

    return v.getColormap(TC_RAINBOW, cv_colorizedhudcolor and cv_colorizedhudcolor.value or p.skincolor)
end

local function stringdraw(v, x, y, str, flags, colormap)
	for i = 1, #str do
		local char = str:sub(i, i)
		local patch = v.cachePatch(string.format("OPPRF%03d", char:byte()))
		v.drawScaled(x, y, FRACUNIT, patch, flags, colormap)
		x = x + 6*FRACUNIT
	end
end

local cv_kartdriftgauge = nil -- Check for hardcode driftgauge
local afterval = {}
local aftertime = {}
local V_100TRANS = V_50TRANS*2
local lineofs = { 0, 0, 2, 2, 0, 0 }
local colors = { 100, 100, 97, 97, 100, 100 }
local BAR_WIDTH = 46
local clipcounts = { 0, 1, 2, 7 }
hud.add(function(v, p, c)
    if cv_kartdriftgauge == nil then
        cv_kartdriftgauge = CV_FindVar("kartdriftgauge") or false
    end

    if cv_kartdriftgauge and cv_kartdriftgauge.value then return end

	if not (p.mo and c.chase and cv_driftgauge.value and p.playerstate == PST_LIVE) then return end

	local result = K_ObjectTracking(v, p, c, { x = p.mo.x, y = p.mo.y, z = p.mo.z + FixedMul(cv_driftgaugeofs.value, cv_driftgaugeofs.value > 0 and p.mo.scale or mapobjectscale) }, false)
	local basex, basey = result.x, result.y

	local drifttrans = 0
	if string.find(VERSIONSTRING:lower(), "saturn") and cv_driftgaugetrans.value then -- only use this in saturn since other clients dont support translucent drawfill or stuff will look off!
		drifttrans = v.localTransFlag()
	end

	-- afterimage
	if aftertime[p] then
		if aftertime[p] <= leveltime then aftertime[p] = 0; return end
		local trans = V_100TRANS - (V_10TRANS * (aftertime[p] - leveltime))
		stringdraw(v, basex + 4*FRACUNIT, basey + 6*FRACUNIT, afterval[p], trans, v.getColormap(TC_RAINBOW, SKINCOLOR_SUPERSILVER1))
		return
	elseif not p.drift then
		return
	end

	local driftval = K_GetKartDriftSparkValue(p)
	local driftcharge = min(driftval*4, p.driftcharge)
	local rainbow = driftcharge >= driftval*4

	-- the little MT_DRIFTCLIPs
	local clip = v.getSpritePatch(SPR_DBCL, rainbow and K or C)
	local clipcount = clipcounts[driftcharge/driftval] or 0
	for i = 0, clipcount-1 do
		v.drawScaled(basex + FRACUNIT - i*FRACUNIT*3, sin(leveltime*ANG20*clipcount + i*ANGLE_22h)*2 + basey + 9*FRACUNIT, FRACUNIT/3, clip, drifttrans)
	end

	-- the base graphic
	v.drawScaled(basex, basey, FRACUNIT, getBackgroundPatch(v), drifttrans, getBackgroundColormap(v, p))
	if rainbow then
		-- HOT HOT HOT HOT HOOOOOOOT AAAAIIIIIIIIEEEEEEEEEEEEEEEEE
		local trans = abs(sin(leveltime*ANGLE_22h)/(4*FRACUNIT/10))
		v.drawScaled(basex, basey, FRACUNIT, getBackgroundPatch(v), V_90TRANS - V_10TRANS*trans, v.getColormap(TC_BLINK, SKINCOLOR_RED))
	end

	local barx = basex - 22*FRACUNIT
	local bary = basey + FRACUNIT*2

	local width = ((driftcharge % driftval) * BAR_WIDTH) / driftval
	local level = (driftcharge / driftval) + 1
	local patch = "~%03d"

	local cmap = v.getColormap(TC_RAINBOW, driftskins[level])
	local cmap2 = v.getColormap(TC_RAINBOW, driftskins[level-1])
	if rainbow then
		cmap = v.getColormap(TC_RAINBOW, 1 + (leveltime % FIRSTSUPERCOLOR - 1))
		cmap2 = cmap
	end
	for i = 0, #lineofs - 1 do
		local ofs = lineofs[i+1]*FRACUNIT/2
		local x = barx + ofs
		local y = bary+i*FRACUNIT/2
		local w = (max(0, min(width*FRACUNIT - ofs, BAR_WIDTH*FRACUNIT - ofs*2))) / 64
		local h = FRACUNIT/128
		-- back
		v.drawStretched(x, y, (BAR_WIDTH*FRACUNIT - ofs*2)/64, h, v.cachePatch(patch:format(colors[i+1] + (level == 1 and 8 or 0))), drifttrans, cmap2)
		-- front
		if not rainbow then
			v.drawStretched(x, y, w, h, v.cachePatch(patch:format(colors[i+1])), drifttrans, cmap)
		end
	end

	-- right, also draw a cool number
	local charge = string.format("%03d", driftcharge*100 / driftval)
	stringdraw(v, basex + 4*FRACUNIT, basey + 6*FRACUNIT, charge, drifttrans, cmap)

	-- and trigger the afterimage
	if p.pflags & PF_DRIFTEND then
		afterval[p] = charge
		aftertime[p] = leveltime + 10
	else
		aftertime[p] = 0
	end
end)
