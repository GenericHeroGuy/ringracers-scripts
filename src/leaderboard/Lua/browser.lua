local MapRecords
local maps
local mapIndex = 1
local scrollPos = 1
local modes = nil
local mode = 1
local prefMode = nil
local ModeSep
local gtselect

---- Imported functions ----

-- lb_common.lua
local ZoneAct = lb_ZoneAct
local TicsToTime = lb_TicsToTime
local drawNum = lb_draw_num
local getThrowDir = lb_throw_dir
local getPortrait = lb_get_portrait

-- lb_store.lua
local GetMapRecords = lb_get_map_records
local GetProfile = lb_get_profile
local RecordName = lb_record_name

-----------------------------

local RINGS = VERSION == 2
local TURNING = RINGS and "turning" or "driftturn"
local V_ALLOWLOWERCASE = V_ALLOWLOWERCASE or 0
local TOL_BATTLE = TOL_BATTLE or TOL_MATCH
local BT_CUSTOM1 = BT_CUSTOM1 or 1<<13

local cv_showallstats = CV_RegisterVar({
	name = "lb_showallstats",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,
})

rawset(_G, "lb_cv_showallstats", cv_showallstats)

local cv_kartencore

local function mapIndexOffset(n)
	return (mapIndex + n + #maps[gtselect] - 1) % #maps[gtselect] + 1
end

local function getMap(offset)
	return maps[gtselect][mapIndexOffset(offset or 0)]
end

local function updateModes()
	-- set available modes for this map
	modes = {}
	for mode, _ in pairs(MapRecords) do
		table.insert(modes, mode)
	end
	table.sort(modes)

	mode = 1
	-- select pref mode
	for i, m in ipairs(modes) do
		if m == prefMode then
			mode = i
			break
		end
	end
end

local function updateMapIndex(n)
	mapIndex = mapIndexOffset(n)
	scrollPos = 1

	MapRecords = GetMapRecords(getMap(), ModeSep)

	updateModes()
end

-- initialize map lists
local function loadMaps()
	maps = {}
	local hell = {}
	for i = 0, #mapheaderinfo do
		local map = mapheaderinfo[i]
		if map then
			local tol = map.typeoflevel & (TOL_RACE|TOL_BATTLE)
			if not (tol == TOL_RACE or tol == TOL_BATTLE) then continue end
			if map.menuflags & LF2_HIDEINMENU then
				if not hell[tol] then hell[tol] = {} end
				table.insert(hell[tol], i)
			else
				if not maps[tol] then maps[tol] = {} end
				table.insert(maps[tol], i)
			end
		end
	end

	-- append hell maps
	for tol, set in pairs(hell) do
		for _, map in ipairs(set) do
			table.insert(maps[tol], map)
		end
	end
end
addHook("MapLoad", function()
	maps = nil
	MapRecords = nil
	modes = nil
end)

local scalar = 2
local hlfScrnWdth = 320 / 2
local mappY = 26
local ttlY = mappY + FixedMul(30, FRACUNIT / scalar)
local scoresY =  ttlY + 16

local sin = sin
local function drawMapPatch(v, offset)
	local scale = FRACUNIT / (abs(offset) + scalar) / (RINGS and 2 or 1)
	local mapName = G_BuildMapName(getMap(offset))
	local patchName = mapName.."P"
	local mapp = v.patchExists(patchName) and v.cachePatch(patchName) or v.cachePatch("BLANKLVL")

	local scaledWidth = FixedMul(mapp.width, scale)
	local scaledHeight = FixedMul(mapp.height, scale)

	v.drawScaled(
		(hlfScrnWdth + offset * scaledWidth - scaledWidth / 2) * FRACUNIT,
		(mappY - scaledHeight / 2) * FRACUNIT,
		scale,
		mapp
	)

end

local function drawEncore(v)
	if not cv_kartencore then
		cv_kartencore = CV_FindVar(RINGS and "encore" or "kartencore")
	end

	if cv_kartencore.value ~= 1 then
		return
	end

	local rubyp = v.cachePatch("RUBYICON")
	local bob = sin(leveltime * ANG10) * 2
	v.drawScaled(
		hlfScrnWdth * FRACUNIT,
		mappY * FRACUNIT + bob,
		FRACUNIT,
		rubyp
	)
end

local colors = {
	[0] = RINGS and 1 or 0, -- TIL indices 0-6 are brighter in 2.2
	[1] = RINGS and 133 or 215
}
local function drawMapBorder(v)
	local mapWidth = FixedMul(160, FRACUNIT / scalar)
	local mapHeight = FixedMul(100, FRACUNIT / scalar)
	v.drawFill(
		hlfScrnWdth - mapWidth / 2 - 1,
		mappY - mapHeight / 2 -1,
		mapWidth + 2,
		mapHeight + 2,
		colors[leveltime / 4 % 2]
	)
end

local function drawMapStrings(v)
	local map = mapheaderinfo[getMap()]
	local titleWidth = v.stringWidth(map.lvlttl)

	-- title
	v.drawString(
		hlfScrnWdth,
		ttlY,
		map.lvlttl,
		V_SKYMAP,
		"center"
	)

	-- zone/act
	local zone = ZoneAct(map)
	local zoneWidth = v.stringWidth(zone)
	v.drawString(
		hlfScrnWdth + titleWidth / 2,
		ttlY + 8,
		zone,
		V_SKYMAP,
		"right"
	)

	-- subtitle
	if not RINGS then
		v.drawString(
			hlfScrnWdth + titleWidth / 2 - zoneWidth,
			ttlY + 8,
			map.subttl,
			V_MAGENTAMAP,
			"small-right"
		)
	end

	-- hell
	if map.menuflags & LF2_HIDEINMENU then
		v.drawString(
			300,
			ttlY + 16,
			"HELL",
			V_REDMAP,
			"right"
		)
	end

    if nmr and NMR_GetRemovedMaps()[getMap()] then
        v.drawString(
			300,
			ttlY + 24,
			"NOT IN ROTATION",
			V_PURPLEMAP,
			"right"
		)
    end
end

local F_SPBATK = lb_flag_spbatk
local F_SPBJUS = lb_flag_spbjus
local F_SPBBIG = lb_flag_spbbig
local F_SPBEXP = lb_flag_spbexp
local F_COMBI = lb_flag_combi
local F_ENCORE = lb_flag_encore

local function drawGamemode(v)
	local m = modes[mode] or 0

	local modeX = 20
	local modeY = scoresY
	local scale = FRACUNIT / 2

	if m == 0 then
		local clockp = v.cachePatch("K_LAPE02")
		v.drawScaled(
			modeX * FRACUNIT,
			modeY * FRACUNIT,
			scale,
			clockp
		)

		v.drawString(
			modeX,
			modeY,
			"Time Attack!"
		)
	elseif m & F_SPBATK then
		local scaledHalf = FixedMul(50 * FRACUNIT, scale) / 2
		local xoff = 0
		if m & F_SPBBIG then
			xoff = $ + scaledHalf
		end
		if m & F_SPBEXP then
			xoff = $ + scaledHalf
		end

		if m & F_SPBBIG then
			local growp = v.cachePatch("K_ITGROW")
			v.drawScaled(
				modeX * FRACUNIT - scaledHalf + xoff,
				modeY * FRACUNIT - scaledHalf,
				scale,
				growp
			)

			xoff = $ - scaledHalf
		end

		if m & F_SPBEXP then
			local invp = v.cachePatch("K_ITINV"..(leveltime / 3 % 7 + 1))
			v.drawScaled(
				modeX * FRACUNIT - scaledHalf + xoff,
				modeY * FRACUNIT - scaledHalf,
				scale,
				invp
			)
		end

		local spbp = v.cachePatch("K_ITSPB")
		v.drawScaled(
			modeX * FRACUNIT - scaledHalf,
			modeY * FRACUNIT - scaledHalf,
			scale,
			spbp
		)

		v.drawString(
			modeX,
			modeY,
			"SPB Attack!"
		)
	elseif m & F_COMBI then
		local combip = v.cachePatch("HEART4")
		v.drawScaled(
			modeX * FRACUNIT - 19*scale,
			modeY * FRACUNIT - 23*scale,
			scale,
			combip
		)

		v.drawString(
			modeX,
			modeY,
			"Combi Ring!"
		)
	end
end

local function drawFlags(v, x, y, flags)
	local nx = x * FRACUNIT
	local ny = y * FRACUNIT + 2 * FRACUNIT
	local margin = 4 * FRACUNIT
	if flags & F_ENCORE then
		local encp = v.cachePatch("RUBYICON")
		v.drawScaled(
			nx,
			ny + 2 * FRACUNIT,
			FRACUNIT / 5,
			encp
		)
		nx = $ + margin
	end
	if flags & F_SPBATK then
		local scale = FRACUNIT / 3
		local shift = 6 * FRACUNIT
		nx = $ - shift
		ny = $ - shift
		if flags & F_SPBJUS then
			local hyup = v.cachePatch("K_ISHYUD")
			v.drawScaled(nx, ny, scale, hyup)
			nx = $ + margin
		end
		if flags & F_SPBBIG then
			local growp = v.cachePatch("K_ISGROW")
			v.drawScaled(nx - FRACUNIT / 2, ny, scale, growp)
			nx = $ + margin
		end
		if flags & F_SPBEXP then
			local invp = v.cachePatch("K_ISINV"..(leveltime / 3 % 6 + 1))
			v.drawScaled(nx, ny, scale, invp)
			nx = $ + margin
		end
	end
end

local MSK_SPEED = 0xF0
local MSK_WEIGHT = 0xF

local function drawStats(v, x, y, skin, stats)
	local s = skins[skin]

	local color = ""

	if not stats and cv_showallstats.value and s then
		stats = (s.kartspeed<<4) | s.kartweight
	end

	local matchskinstats = stats and s and (s.kartspeed == (stats & MSK_SPEED) >> 4) and (s.kartweight == stats & MSK_WEIGHT)

	-- Highlight restat if all stats are shown
	if cv_showallstats.value and not matchskinstats then
		color = "\130"
    end

	if stats
		and (not matchskinstats
			or cv_showallstats.value) then
		v.drawString(x-2, y-2, color..((stats & MSK_SPEED) >> 4), V_ALLOWLOWERCASE, "thin")
		v.drawString(x + 13, y + 9, color..(stats & MSK_WEIGHT), V_ALLOWLOWERCASE, "thin")
	end
end

-- draw in columns
-- pos, facerank, name, time, flags
-- ______________________________________________
-- | 3|[O]|InsertNameHere     | 01:02:03 | EXB |
-- ----------------------------------------------
-- defined are widths of each column, x value is calculated below
local column = {
	[1] = 18,   -- facerank, pos, drawNum is right aligned
	[2] = 170,  -- name
	[3] = 60, -- time
	[4] = 0  -- flags
}
do
	local w = 32 -- starting offset
	local t
	for i = 1, #column do
		t = column[i]
		column[i] = w
		w = $ + t
	end
end

local colorFlags = {
	[0] = V_SKYMAP,
	[1] = 0
}

local function drawScore(v, i, pos, score, player)
	local y = scoresY + i * 18
	local textFlag = colorFlags[pos%2]
	local ofs = 0
	local mypid = GetProfile(player)

	-- position
	drawNum(v, column[1], y, pos)

	-- facerank
	for i, p in ipairs(score.players) do
		local facerank, downscale = getPortrait(v, p)
		local color = p.color < MAXSKINCOLORS and p.color or 0
		v.drawScaled((column[1] + ofs)<<FRACBITS, y<<FRACBITS, FRACUNIT/downscale, facerank, 0, v.getColormap(TC_DEFAULT, color))

		-- chili
		if mypid == p.pid then
			local chilip = v.cachePatch("K_CHILI"..leveltime/4%8+1)
			v.draw(column[1], y, chilip)
			textFlag = V_YELLOWMAP
		end

		-- draw a tiny little dot so you know which player's name is being shown
		if #score.players > 1 and (leveltime / (TICRATE*5) % #score.players) + 1 == i then
			v.drawFill(column[1] + ofs, y, 1, 1, 128)
		end

		-- stats
		drawStats(v, column[1] + ofs, y, p.skin, p.stat)
		ofs = ofs + 17
	end

	-- name
	local sp = score.players[(leveltime / (TICRATE*5) % #score.players) + 1]
	v.drawString(column[2] + ofs, y, RecordName(sp), V_ALLOWLOWERCASE | textFlag)
	-- time
	v.drawString(column[3], y, TicsToTime(score["time"]), textFlag)
	-- flags
	drawFlags(v, column[4], y, score["flags"])
end

local function drawBrowser(v, player)
	if not MapRecords then return end

	v.fadeScreen(0xFF00, 16)

	-- previous, next maps
	for i = 5, 1, -1 do
		drawMapPatch(v, -i)
		drawMapPatch(v, i)
	end

	-- draw map border
	drawMapBorder(v)

	-- current map
	drawMapPatch(v, 0)
	drawEncore(v)
	drawMapStrings(v)
	drawGamemode(v)

	if not modes then return end

	local records = MapRecords[modes[mode]]
	if not records then return end

	local record_count = #records
	scrollPos = max(min(scrollPos, record_count - 3), 1)
	local endi = min(scrollPos + 7, record_count)
	for i = scrollPos, endi do
		drawScore(v, i - scrollPos + 1, i, records[i], player)
	end
end
rawset(_G, "DrawBrowser", drawBrowser)

local function initBrowser(modeSep)
	if not maps then loadMaps() end

	ModeSep = modeSep
	gtselect = mapheaderinfo[gamemap].typeoflevel & (TOL_RACE|TOL_BATTLE)

	-- set mapIndex to current map
	for i, m in ipairs(maps[gtselect]) do
		if m == gamemap then
			mapIndex = i
			break
		end
	end

	-- initialize MapRecords
	MapRecords = GetMapRecords(gamemap, ModeSep)

	scrollPos = 1
	updateModes()
end
rawset(_G, "InitBrowser", initBrowser)

local repeatCount = 0
local keyRepeat = 0

local function updateKeyRepeat()
	S_StartSound(nil, sfx_ptally)
	if repeatCount < 1 then
		keyRepeat = TICRATE / 4
	else
		keyRepeat = TICRATE / 15
	end
	repeatCount = $ + 1
end

local function resetKeyRepeat()
	keyRepeat = 0
	repeatCount = 0
end

local ValidButtons = BT_ACCELERATE | BT_BRAKE | BT_DRIFT | BT_ATTACK | BT_CUSTOM1

-- return value indicates we want to exit the browser
local function controller(player)
	-- mid-game join
	if not maps then loadMaps() end
	if not MapRecords then MapRecords = GetMapRecords(getMap(), ModeSep) end
	if not modes then updateModes() end

	keyRepeat = max(0, $ - 1)
	local throwdir = getThrowDir(player)

	if not (player.cmd[TURNING] or player.cmd.buttons or throwdir) then
		resetKeyRepeat()
	end

	local cmd = player.cmd
	if not keyRepeat then
		if not (cmd.buttons & ValidButtons or cmd[TURNING] or throwdir) then
			return
		end

		updateKeyRepeat()

		if cmd.buttons & BT_BRAKE then
			S_StartSound(nil, sfx_pop)
			return true
		elseif cmd.buttons & BT_ACCELERATE then
			COM_BufInsertText(player, "changelevel "..G_BuildMapName(getMap()))
			return true
		elseif cmd.buttons & BT_ATTACK then
			COM_BufInsertText(player, "lb_encore")
		elseif cmd[TURNING] then
			local dir = cmd[TURNING] > 0 and -1 or 1

			if encoremode then
				updateMapIndex(-dir)
			else
				updateMapIndex(dir)
			end
		elseif throwdir == 1 then -- BT_FORWARD
			scrollPos = $ - 1
		elseif throwdir == -1 then -- BT_BACKWARD
			scrollPos = $ + 1
		elseif cmd.buttons & BT_DRIFT then
			scrollPos = 1
			if modes and #modes then
				mode = $ % #modes + 1
				prefMode = modes[mode]
			end
		elseif cmd.buttons & BT_CUSTOM1 then
			gtselect = gtselect == TOL_RACE and TOL_BATTLE or TOL_RACE
			updateMapIndex(0)
		end
	end
end
rawset(_G, "BrowserController", controller)

local function netvars(net)
	mapIndex = net($)
	mode = net($)
	prefMode = net($)
	scrollPos = net($)
	ModeSep = net($)
end
addHook("NetVars", netvars)
