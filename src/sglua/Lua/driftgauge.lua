-- I wanna take a nap
-- splitscreen is unsupported as of yet
-- GenericHeroGuy: now it is! ...sort of
-- G from future: it definitely is now!
-- G from the distant future: it was always broken lmao

local fovvars
local function R_FOV(num)
	if not fovvars then
		fovvars = { [0] = CV_FindVar("fov"), CV_FindVar("fov2"), CV_FindVar("fov3"), CV_FindVar("fov4") }
	end
	return fovvars[num].value
end
local function AngleDeltaSigned(a1, a2)
	return a1 - a2
end

// This version of the function was prototyped in Lua by Nev3r ... a HUGE thank you goes out to them!
-- if only it was exposed
local baseFov = 90*FRACUNIT
local BASEVIDWIDTH = 320
local BASEVIDHEIGHT = 200
local function K_ObjectTracking(v, p, c, point, reverse)
	local cameraNum = c.pnum - 1

	// Initialize defaults
	local result = {}
	result.x, result.y = 0, 0
	result.scale = FRACUNIT
	result.onScreen = false

	// Take the view's properties as necessary.
	local viewpointAngle, viewpointAiming, viewpointRoll
	if reverse then
		viewpointAngle = (c.angle + ANGLE_180)
		viewpointAiming = InvAngle(c.aiming)
		viewpointRoll = p.viewrollangle
	else
		viewpointAngle = c.angle
		viewpointAiming = c.aiming
		viewpointRoll = InvAngle(p.viewrollangle)
	end

	-- the curse of libsg
	local viewx, viewy, viewz
	if p.awayviewtics then
		viewx = p.awayviewmobj.x
		viewy = p.awayviewmobj.y
		viewz = p.awayviewmobj.z
	elseif c.chase then
		viewx = c.x
		viewy = c.y
		viewz = c.z + (p.mo.eflags & MFE_VERTICALFLIP and c.height)
	else
		viewx = p.mo.x
		viewy = p.mo.y
		viewz = p.viewz
	end

	// Calculate screen size adjustments.
	local screenWidth = v.width()/v.dupx()
	local screenHeight = v.height()/v.dupy()

	-- what's the difference between this and r_splitscreen?
	if splitscreen >= 2 then
		// Half-wide screens
		screenWidth = $ >> 1
	end

	if splitscreen >= 1 then
		// Half-tall screens
		screenHeight = $ >> 1
	end

	local screenHalfW = (screenWidth >> 1) << FRACBITS
	local screenHalfH = (screenHeight >> 1) << FRACBITS

	// Calculate FOV adjustments.
	local fovDiff = R_FOV(cameraNum) - baseFov
	local fov = ((baseFov - fovDiff) / 2) - (p.fovadd / 2)
	local fovTangent = tan(FixedAngle(fov))

	if splitscreen == 1 then
		// Splitscreen FOV is adjusted to maintain expected vertical view
		fovTangent = 10*fovTangent/17
	end

	local fg = (screenWidth >> 1) * fovTangent

	// Determine viewpoint factors.
	local h = R_PointToDist2(point.x, point.y, viewx, viewy)
	local da = AngleDeltaSigned(viewpointAngle, R_PointToAngle2(viewx, viewy, point.x, point.y))
	local dp = AngleDeltaSigned(viewpointAiming, R_PointToAngle2(0, 0, h, viewz))

	if reverse then da = -da end

	// Set results relative to top left!
	result.x = FixedMul(tan(da), fg)
	result.y = FixedMul((tan(viewpointAiming) - FixedDiv((point.z - viewz), 1 + FixedMul(cos(da), h))), fg)

	result.angle = da
	result.pitch = dp
	result.fov = fg

	// Rotate for screen roll...
	if viewpointRoll then
		local tempx = result.x
		result.x = FixedMul(cos(viewpointRoll), tempx) - FixedMul(sin(viewpointRoll), result.y)
		result.y = FixedMul(sin(viewpointRoll), tempx) + FixedMul(cos(viewpointRoll), result.y)
	end

	// Flipped screen?
	if encoremode then result.x = -result.x end

	// Center results.
	result.x = $ + screenHalfW
	result.y = $ + screenHalfH

	result.scale = FixedDiv(screenHalfW, h+1)

	result.onScreen = not ((abs(da) > ANG60) or (abs(AngleDeltaSigned(viewpointAiming, R_PointToAngle2(0, 0, h, (viewz - point.z)))) > ANGLE_45))

	// Cheap dirty hacks for some split-screen related cases
	if result.x < 0 or result.x > (screenWidth << FRACBITS) then
		result.onScreen = false
	end

	if result.y < 0 or result.y > (screenHeight << FRACBITS) then
		result.onScreen = false
	end

	// adjust to non-green-resolution screen coordinates
	result.x = $ - ((v.width()/v.dupx()) - BASEVIDWIDTH)<<(FRACBITS-(splitscreen >= 2 and 2 or 1))
	result.y = $ - ((v.height()/v.dupy()) - BASEVIDHEIGHT)<<(FRACBITS-(splitscreen >= 1 and 2 or 1))
	return result
end

local driftcolors = {
	-- TODO: pick better colors
	-- top  --  bottom --
	{  0,   4,   8,  12}, -- no drift
	{ 72,  74,  76,  78}, -- yellow
	{ 50,  52,  54,  56}, -- orange
	{146, 148, 150, 152}, -- blue
}

local driftskins = {
	SKINCOLOR_NONE,
	SKINCOLOR_YELLOW,
	SKINCOLOR_ORANGE,
	SKINCOLOR_BLUE,
}

local driftrainbow = {
	-- TODO: new palette
	0, 31, 47, 63, 79, 95, 111, 119, 127, 143, 159, 175, 183, 191, 199, 207, 223, 247
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

local cv_kartdriftgauge = nil -- Check for hardcode driftgauge
hud.add(function(v, p, c)
    if cv_kartdriftgauge == nil then
        cv_kartdriftgauge = CV_FindVar("kartdriftgauge") or false
    end

    if cv_kartdriftgauge and cv_kartdriftgauge.value then return end

	if not (p.mo and c.chase and p.drift and cv_driftgauge.value and p.playerstate == PST_LIVE) then return end

	local driftval = K_GetKartDriftSparkValue(p)
	local driftcharge = min(driftval*4, p.driftcharge)

	local result = K_ObjectTracking(v, p, c, { x = p.mo.x, y = p.mo.y, z = p.mo.z + FixedMul(cv_driftgaugeofs.value, cv_driftgaugeofs.value > 0 and p.mo.scale or mapobjectscale) }, false)
	local basex, basey = result.x, result.y
	local dup = 1--v.dupx()

	local drifttrans

	if string.find(VERSIONSTRING:lower(), "saturn") and cv_driftgaugetrans.value then -- only use this in saturn since other clients dont support translucent drawfill or stuff will look off!
		drifttrans = v.localTransFlag()
	else
		drifttrans = 0
	end

	v.drawScaled(basex, basey, FRACUNIT, getBackgroundPatch(v), drifttrans, getBackgroundColormap(v, p))

	local barx = (basex>>FRACBITS) - dup*23
	local bary = (basey>>FRACBITS) - dup*2
	local BAR_WIDTH = 47--*dup

	local width = ((driftcharge % driftval) * BAR_WIDTH) / driftval
	local level = (driftcharge / driftval) + 1

	-- TODO: some function to translate fractional coords to V_NOSCALESTART for drawfill
	local cmap
	if driftcharge >= driftval*4 then -- rainbow sparks
		cmap = v.getColormap(TC_RAINBOW, 1 + leveltime % (MAXSKINCOLORS-1))
		for i = 1, 4 do
			v.drawFill(barx, bary+dup*i, BAR_WIDTH, dup, (driftrainbow[(leveltime % #driftrainbow) + 1] + i*2) | drifttrans)
		end
	else -- none/yellow/orange/blue
		cmap = v.getColormap(TC_RAINBOW, driftskins[level])
		for i = 1, 4 do
			if driftcharge >= driftval then
				v.drawFill(barx, bary+dup*i, BAR_WIDTH, dup, driftcolors[level-1][i] | drifttrans)
			end
			v.drawFill(barx, bary+dup*i, width, dup, driftcolors[level][i] | drifttrans)
		end
	end

	-- right, also draw a cool number
	v.drawPingNum(basex + (dup*32), basey, driftcharge*100 / driftval, drifttrans, cmap)
end)
