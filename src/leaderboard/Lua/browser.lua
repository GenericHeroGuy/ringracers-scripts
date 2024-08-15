local MapRecords
local maps
local mapIndex = 1
local scrollPos = 1
local modes = nil
local mode = 1
local prefMode = nil
local ModeSep

---- Imported functions ----

-- lb_common.lua
local ZoneAct = lb_ZoneAct
local TicsToTime = lb_TicsToTime

-- lb_store.lua
local GetMapRecords = lb_get_map_records

-----------------------------

local cv_kartencore

local cv_highresportrait
local cv_lb_highresportrait -- Eee maybe need to share it between lb modules somehow?
local function useHighresPortrait()
	if cv_highresportrait then
		return cv_highresportrait.value ~= cv_lb_highresportrait.value
	end
	
	return cv_lb_highresportrait and cv_lb_highresportrait.value
end

local function lookupCvars()
	if not cv_highresportrait then
		cv_highresportrait = CV_FindVar("highresportrait")
	end
	
	if not cv_lb_highresportrait then
		cv_lb_highresportrait = CV_FindVar("lb_highresportrait")
	end
end

addHook("MapLoad", lookupCvars)
addHook("NetVars", lookupCvars)

local function mapIndexOffset(n)
	return (mapIndex + n + #maps - 1) % #maps + 1
end

local function getMap(offset)
	return maps[mapIndexOffset(offset or 0)]
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

	MapRecords = GetMapRecords(maps[mapIndex], ModeSep)

	updateModes()
end

local scalar = 2
local hlfScrnWdth = 320 / 2
local mappY = 26
local ttlY = mappY + FixedMul(30, FRACUNIT / scalar)
local scoresY =  ttlY + 16

local sin = sin
local function drawMapPatch(v, offset)
	local scale = FRACUNIT / (abs(offset) + scalar)
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
		cv_kartencore = CV_FindVar("kartencore")
	end

	if not cv_kartencore.value then
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
	[0] = 0,
	[1] = 215
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
	v.drawString(
		hlfScrnWdth + titleWidth / 2 - zoneWidth,
		ttlY + 8,
		map.subttl,
		V_MAGENTAMAP,
		"small-right"
	)

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

local F_SPBATK = 0x1
local F_SPBJUS = 0x2
local F_SPBBIG = 0x4
local F_SPBEXP = 0x8
local F_COMBI = 0x10
local F_ENCORE = 0x80

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
	if stats
		and not (s
		and s.kartspeed == (stats & MSK_SPEED) >> 4
		and s.kartweight == stats & MSK_WEIGHT
		) then
		v.drawString(x-2, y-2, (stats & MSK_SPEED) >> 4, V_ALLOWLOWERCASE, "thin")
		v.drawString(x + 13, y + 9, stats & MSK_WEIGHT, V_ALLOWLOWERCASE, "thin")
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

local norank
local function drawScore(v, i, pos, score, player)
	local y = scoresY + i * 18
	local textFlag = colorFlags[pos%2]
	local ofs = 0

	if not norank then
		norank = v.cachePatch("M_NORANK")
	end

	-- position
	v.drawNum(column[1], y, pos)

	-- facerank
	for i, p in ipairs(score.players) do
		local skin = skins[p.skin]
		local facerank = skin and v.cachePatch(useHighresPortrait() and skin.facewant or skin.facerank) or norank
		local downscale = (facerank ~= norank and useHighresPortrait()) and 2 or 1
		local color = p.color < MAXSKINCOLORS and p.color or 0
		v.drawScaled((column[1] + ofs)<<FRACBITS, y<<FRACBITS, FRACUNIT/downscale, facerank, 0, v.getColormap(TC_DEFAULT, color))

		-- chili
		if player.name == p.name then
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
	v.drawString(column[2] + ofs, y, score.players[(leveltime / (TICRATE*5) % #score.players) + 1].name, V_ALLOWLOWERCASE | textFlag)
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
	ModeSep = modeSep

	-- set mapIndex to current map
	for i, m in ipairs(maps) do
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

-- initialize maps with racemaps only
local function loadMaps()
	maps = {}
	local hell = {}
	for i = 0, #mapheaderinfo do
		local map = mapheaderinfo[i]
		if map and map.typeoflevel & TOL_RACE then
			if map.menuflags & LF2_HIDEINMENU then
				table.insert(hell, i)
			else
				table.insert(maps, i)
			end
		end
	end

	-- append hell maps
	for _, map in ipairs(hell) do
		table.insert(maps, map)
	end
end
addHook("MapLoad", loadMaps)

local repeatCount = 0
local keyRepeat = 0

local function updateKeyRepeat()
	S_StartSound(nil, 143)
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

local ValidButtons = BT_ACCELERATE | BT_BRAKE | BT_FORWARD | BT_BACKWARD | BT_DRIFT | BT_ATTACK

-- return value indicates we want to exit the browser
local function controller(player)
	keyRepeat = max(0, $ - 1)

	if not (player.cmd.driftturn or player.cmd.buttons) then
		resetKeyRepeat()
	end

	local cmd = player.cmd
	if not keyRepeat then
		if not (cmd.buttons & ValidButtons or cmd.driftturn) then
			return
		end

		updateKeyRepeat()

		if cmd.buttons & BT_BRAKE then
			S_StartSound(nil, 115)
			return true
		elseif cmd.buttons & BT_ACCELERATE then
			COM_BufInsertText(player, "changelevel "..G_BuildMapName(maps[mapIndex]))
			return true
		elseif cmd.buttons & BT_ATTACK then
			COM_BufInsertText(player, "encore")
		elseif cmd.driftturn then
			local dir = cmd.driftturn > 0 and -1 or 1

			if encoremode then
				updateMapIndex(-dir)
			else
				updateMapIndex(dir)
			end
		elseif cmd.buttons & BT_FORWARD then
			scrollPos = $ - 1
		elseif cmd.buttons & BT_BACKWARD then
			scrollPos = $ + 1
		elseif cmd.buttons & BT_DRIFT then
			scrollPos = 1
			if modes and #modes then
				mode = $ % #modes + 1
				prefMode = modes[mode]
			end
		end
	end
end
rawset(_G, "BrowserController", controller)

local function netvars(net)
	maps = net($)
	mapIndex = net($)
	modes = net($)
	mode = net($)
	prefMode = net($)
	scrollPos = net($)
	MapRecords = net($)
	ModeSep = net($)
end
addHook("NetVars", netvars)
