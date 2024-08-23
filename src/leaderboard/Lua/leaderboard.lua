-- Leaderboards written by Not
-- Reusable

---------- Imported functions -------------
-- lb_common.lua
local ticsToTime = lb_TicsToTime
local zoneAct = lb_ZoneAct
local stat_t = lb_stat_t
local lbComp = lb_comp
local mapChecksum = lb_map_checksum
local score_t = lb_score_t
local player_t = lb_player_t
local mapnumFromExtended = lb_mapnum_from_extended
local StringReader = lb_string_reader

-- browser.lua
local InitBrowser = InitBrowser
local DrawBrowser = DrawBrowser
local BrowserController = BrowserController

-- lb_store.lua
local GetMapRecords = lb_get_map_records
local SaveRecord = lb_save_record
local MapList = lb_map_list
local MoveRecords = lb_move_records
local WriteMapStore = lb_write_map_store

-- bghost.lua
local GhostStartRecording = lb_ghost_start_recording
local GhostStopRecording = lb_ghost_stop_recording
local GhostStartPlaying = lb_ghost_start_playing
local GhostIsRecording = lb_ghost_is_recording

-- lbcomms.lua
local CommsRequestGhosts = lb_request_ghosts
--------------------------------------------

-- Holds the current maps records table including all modes
local MapRecords = {}

local TimeFinished = 0
local disable = false
local prevLap = 0
local splits = {}
local PATCH = nil
local help = true
local EncoreInitial = nil
local ScoreTable
local BrowserPlayer


-- Text flash on finish
local FlashTics = 0
local FlashRate
local FlashVFlags
local YellowFlash = {
	[0] = V_YELLOWMAP,
	[1] = V_ORANGEMAP,
	[2] = 0
}
local RedFlash = {
	[0] = V_REDMAP,
	[1] = 0
}

local UNCLAIMED = "Unclaimed Record"
local HELP_MESSAGE = "\x88Leaderboard Commands:\n\x89retry exit findmap changelevel spba_clearcheats lb_gui rival scroll encore records levelselect lb_ghost_hide lb_ghost_trans_prox"
local FILENAME = "leaderboard.txt"

-- Retry / changelevel map
local nextMap = nil

local Flags = 0
local F_COMBI = lb_flag_combi
local F_ENCORE = lb_flag_encore

-- SPB flags with the least significance first
local F_SPBATK = lb_flag_spbatk
local F_SPBJUS = lb_flag_spbjus
local F_SPBBIG = lb_flag_spbbig
local F_SPBEXP = lb_flag_spbexp

-- Score table separator
local ST_SEP = F_SPBATK | F_COMBI

local clearcheats = false

local START_TIME = 6 * TICRATE + (3 * TICRATE / 4) + 1
local AFK_TIMEOUT = TICRATE * 5
local AFK_BROWSER = TICRATE * 60 -- Changed from 15 to 60
local AFK_BALANCE = TICRATE * 60
local AFK_BALANCE_WARN = AFK_BALANCE - TICRATE * 10
local PREVENT_JOIN_TIME = START_TIME + TICRATE * 5

local GUI_OFF    = 0x0
local GUI_SPLITS = 0x1
local GUI_ON     = 0x2

-- Draw states
local DS_DEFAULT = 0x0
local DS_SCROLL  = 0x1
local DS_AUTO    = 0x2
local DS_SCRLTO  = 0x4
local DS_BROWSER = 0x8

local drawState = DS_DEFAULT

-- fixed_t scroll position
local scrollY = 50 * FRACUNIT
local scrollAcc = 0

-- functions --

-- patch caching
local cachePatches

local useHighresPortrait

-- clamp(min, v, max)
local clamp

local scroll_to

local allowJoin


-- cvars
local cv_teamchange
local cv_spbatk
local cv_combiactive
local cv_combiminimumplayers

local cv_gui = CV_RegisterVar({
	name = "lb_gui",
	defaultvalue = GUI_ON,
	flags = 0,
	PossibleValue = {Off = GUI_OFF, Splits = GUI_SPLITS, On = GUI_ON}
})

local cv_smallhud = CV_RegisterVar({
	name = "lb_smallhud",
	defaultvalue = "Off",
	flags = 0,
	PossibleValue = CV_OnOff,
})

local cv_lb_highresportrait = CV_RegisterVar({
	name = "lb_highresportrait",
	defaultvalue = "Off",
	flags = 0,
	PossibleValue = CV_OnOff,
})

local cv_antiafk = CV_RegisterVar({
	name = "lb_afk",
	defaultvalue = 1,
	flags = CV_NETVAR | CV_CALL,
	PossibleValue = CV_OnOff,
	func = function(v)
		if v.value then
			for p in players.iterate do
				p.afkTime = leveltime
			end
		end
	end
})

local cv_afk_flashtime = CV_RegisterVar({
	name = "lb_afk_flashtime",
	defaultvalue = 20,
	flags = CV_NETVAR,
	PossibleValue = CV_Unsigned,
})

local cv_enable = CV_RegisterVar({
	name = "lb_enable",
	defaultvalue = 1,
	flags = CV_NETVAR | CV_CALL,
	PossibleValue = CV_OnOff,
	func = function(v)
		disable = $ or not v.value
		if disable then
			allowJoin(true)
		end
	end
})

local cv_saves = CV_RegisterVar({
	name = "lb_save_count",
	defaultvalue = 20,
	flags = CV_NETVAR,
	PossibleValue = CV_Natural
})

local cv_interrupt = CV_RegisterVar({
	name = "lb_interrupt",
	defaultvalue = 0,
	flags = CV_NETVAR | CV_CALL,
	PossibleValue = CV_OnOff,
	func = function(v)
		if v.value then
			COM_BufInsertText(server, "allowteamchange yes")
		end
	end
})

local cv_spb_separate = CV_RegisterVar({
	name = "lb_spb_combined",
	defaultvalue = 1,
	flags = CV_NETVAR | CV_CALL | CV_NOINIT,
	PossibleValue = CV_YesNo,
	func = function(v)
		if v.value then
			ST_SEP = F_SPBATK | F_COMBI
		else
			ST_SEP = F_SPBATK | F_COMBI | F_SPBBIG | F_SPBEXP
		end
	end
})

rawset(_G, "LB_Disable", function()
	disable = true
end)

rawset(_G, "LB_IsRunning", function()
	return not disable
end)

local MSK_SPEED = 0xF0
local MSK_WEIGHT = 0xF

function allowJoin(v)
	if not cv_interrupt.value then
		local y
		if v then
			y = "yes"
			hud.enable("freeplay")
		else
			y = "no"
			hud.disable("freeplay")
		end

		COM_BufInsertText(server, "allowteamchange " + y)
	end
end

local function canstart()
	if cv_combiactive == nil then
		cv_combiactive = CV_FindVar("combi_active") or false
		cv_combiminimumplayers = CV_FindVar("combi_minimumplayers") or false
	end

	local combi = cv_combiactive and cv_combiactive.value and cv_combiminimumplayers.value <= 2

	local n = 0
	for p in players.iterate do
		if p.valid and not p.spectator then
			n = $ + 1
			if n > (combi and 2 or 1) then
				return false
			end
		end
	end
	if combi and n == 1 then return false end
	return true
end

-- Returns true if there is a single player ingame
local function singleplayer()
	local n = 0
	for p in players.iterate do
		if p.valid and not p.spectator then
			n = $ + 1
			if n > 1 then
				return false
			end
		end
	end
	return true
end

local function initLeaderboard(player)
	if disable and leveltime < START_TIME then
		disable = not canstart()
	else
		disable = disable or not canstart()
	end
	disable = $ or not cv_enable.value or not (maptol & (TOL_SP | TOL_RACE))

	-- Restore encore mode to initial value
	if disable and EncoreInitial != nil then
		COM_BufInsertText(server, string.format("kartencore %d", EncoreInitial))
		EncoreInitial = nil
	end

	player.afkTime = leveltime

	if not (player.spectator or disable) then
		MapRecords = GetMapRecords(gamemap, ST_SEP)
	end

	-- if combi is active, disable will be true for the first player but not the second
	-- so player 2 has to start ghost recording for both players
	-- bleh
	for p in players.iterate do
		if (p.spectator or disable) then
			if GhostIsRecording(p) then GhostStopRecording(p) end
		elseif not (p.spectator or GhostIsRecording(p)) then
			GhostStartRecording(p)
		end
	end
end
addHook("PlayerSpawn", initLeaderboard)

local function doyoudare(player)
	if not canstart() or player.spectator then
		CONS_Printf(player, "How dare you")
		return false
	end
	return true
end

COM_AddCommand("retry", function(player)
	if doyoudare(player) then
		-- Verify valid race level
		if not (mapheaderinfo[gamemap].typeoflevel & (TOL_SP | TOL_RACE)) then
			CONS_Printf(player, "Battle maps are not supported")
			return
		end

		-- Prevents bind crash
		if leveltime < 20 then
			return
		end
		nextMap = G_BuildMapName(gamemap)
	end
end)

COM_AddCommand("exit", function(player)
	if doyoudare(player) then
		G_ExitLevel()
	end
end)

COM_AddCommand("levelselect", function(player)
	if not doyoudare(player) then return end

	-- TODO: allow in battle
	if mapheaderinfo[gamemap].typeoflevel & TOL_MATCH then
		CONS_Printf(player, "Please exit battle first")
		return
	end

	if not InitBrowser then
		print("Browser is not loaded")
		return
	end

	InitBrowser(ST_SEP)
	drawState = DS_BROWSER
	BrowserPlayer = player

	player.afkTime = leveltime
end)

COM_AddCommand("findmap", function(player, search)
	local hell = "\x85HELL"
	local tol = {
		[TOL_SP] = "\x81Race\x80", -- Nuked race maps
		[TOL_COOP] = "\x8D\Battle\x80", -- Nuked battle maps
		[TOL_RACE] = "\x88Race\x80",
		[TOL_MATCH] = "\x87\Battle\x80"
	}
	local lvltype, map, lvlttl

	for i = 1, #mapheaderinfo do
		map = mapheaderinfo[i]
		if map == nil then
			continue
		end

		lvlttl = map.lvlttl + zoneAct(map)

		if not search or lvlttl:lower():find(search:lower()) then
			-- Only care for up to TOL_MATCH (0x10)
			lvltype = tol[map.typeoflevel & 0x1F] or map.typeoflevel

			-- If not battle print numlaps
			lvltype = (map.typeoflevel & (TOL_MATCH | TOL_COOP) and lvltype)
				or string.format("%s \x82%-2d\x80", lvltype, map.numlaps)


			print(string.format(
					"%s%s (#%s) %-9s %-30s - %s\t%s",
					G_BuildMapName(i),
					(player == server or IsPlayerAdmin(player)) and "\x86:"..mapChecksum(i).."\x80" or "",
					i,
					lvltype,
					lvlttl,
					map.subttl,
					(map.menuflags & LF2_HIDEINMENU and hell) or ""
			))
		end
	end
end, COM_LOCAL)

local SPBModeSym = {
	[F_SPBEXP] = "X",
	[F_SPBBIG] = "B",
	[F_SPBJUS] = "J",
}

local function modeToString(mode)
	local modestr = "Time Attack"
	if mode & F_SPBATK then
		modestr = "SPB"
		for k, v in pairs(SPBModeSym) do
			if mode & k then
				modestr = $ + v
			end
		end
	end
	if mode & F_COMBI then
		modestr = modestr == "Time Attack" and "Combi" or $.." + Combi"
	end

	return modestr
end

COM_AddCommand("records", function(_, mapid)
	local mapnum = gamemap
	local checksum

	if mapid then
		mapnum, checksum = mapnumFromExtended(mapid)
		if not mapnum then
			print(string.format("Invalid map name: %s", mapid))
			return
		end
	end

	local mapRecords = GetMapRecords(mapnum, ST_SEP, checksum or nil)
	if next(mapRecords) == nil then
		print(string.format(
			checksum == false and "Invalid checksum for %s"
			or "No records found for %s"..(checksum == nil and ", please provide a checksum (hint: lb_known_maps)" or ""),
			mapid or G_BuildMapName()
		))
		return
	end

	local map = mapheaderinfo[mapnum]
	if map then
		print(string.format(
			"\x83%s%8s",
			map.lvlttl,
			(map.menuflags & LF2_HIDEINMENU) and "\x85HELL" or ""
		))

		local zoneact = zoneAct(map)
		-- print the zone/act on the right hand size under the title
		print(string.format(
			string.format("\x83%%%ds%%s\x80 - \x88%%s", #map.lvlttl - #zoneact / 2 - 1),
			" ",
			zoneAct(map),
			map.subttl
		))
	else
		print("\x85UNKNOWN MAP")
	end

	for mode, records in pairs(mapRecords) do
		print("")
		print(modeToString(mode))

		-- don't print flags for time attack
		for i, score in ipairs(records) do
			local names = {}
			for _, p in ipairs(score.players) do
				table.insert(names, (SG_Color2Chat and SG_Color2Chat[p.color] or "")..p.name)
			end
			print(string.format(
				"[%5d] %2d %-21s \x89%s"..(mode and " \x80%s" or ""),
				score.id,
				i,
				names[1],
				ticsToTime(score["time"]),
				mode and modeToString(score["flags"]) or nil
			))
			for i = 2, #names do
				print(string.format(
					"           & %s",
					names[i]
				))
			end
		end
	end
end, COM_LOCAL)

COM_AddCommand("changelevel", function(player, map)
	if not doyoudare(player) or leveltime < 20 then
		return
	end

	if map == nil then
		CONS_Printf(player, "Usage: changelevel MAPXX")
		return
	end

	local mapnum = mapnumFromExtended(map)
	if not mapnum then
		CONS_Printf(player, string.format("Invalid map name: %s", map))
	end

	if mapheaderinfo[mapnum] == nil then
		CONS_Printf(player, string.format("Map doesn't exist: %s", map:upper()))
		return
	end

	-- Verify valid race level
	if not (mapheaderinfo[mapnum].typeoflevel & (TOL_SP | TOL_RACE)) then
		CONS_Printf(player, "Battle maps are not supported")
		return
	end

	nextMap = G_BuildMapName(mapnum)
end)

COM_AddCommand("encore", function(player)
	if not doyoudare(player) then
		return
	end

	local enc = CV_FindVar("kartencore")
	if EncoreInitial == nil then
		EncoreInitial = enc.value
	end

	if enc.value then
		COM_BufInsertText(server, "kartencore off")
	else
		COM_BufInsertText(server, "kartencore on")
	end
end)

COM_AddCommand("spba_clearcheats", function(player)
	if not player.spectator then
		clearcheats = true
		CONS_Printf(player, "SPB Attack cheats will be cleared on next round")
	end
end)

COM_AddCommand("scroll", function(player)
	if not doyoudare(player) then return end

	if drawState == DS_DEFAULT then
		scroll_to(player)
	else
		drawState = DS_DEFAULT
	end
end)

COM_AddCommand("rival", function(player, rival, page)
	page = (tonumber(page) or 1) - 1

	if rival == nil then
		print("Print the times of your rival.\nUsage: rival <playername> <page>")
		return
	end

	local colors = {
		[1] = "\x85",
		[0] = "\x89",
		[-1] = "\x88"
	}

	local sym = {
		[true] = "-",
		[false] = "",
	}

	local scores = {}
	local totalScores = 0
	local totalDiff = 0

	print(string.format("\x89%s's times:", rival))
	print("MAP\tTime\tDiff    \tMode")

	local maplist = MapList()
	for i = 1, #maplist do
		local mapRecords = GetMapRecords(maplist[i], ST_SEP)

		for mode, records in pairs(mapRecords) do
			scores[mode] = $ or {}

			local yourScore, rivalScore

			for _, score in ipairs(records) do
				for _, p in ipairs(score.players) do
					if p.name == player.name then
						yourScore = score
					elseif p.name == rival then
						rivalScore = score
					end
					if rivalScore and yourScore then
						break
					end
				end
			end

			if rivalScore and yourScore then
				totalDiff = totalDiff + yourScore.time - rivalScore.time
			end

			if rivalScore then
				totalScores = totalScores + 1
				table.insert(
					scores[mode],
					{
						rival = rivalScore,
						your = yourScore
					}
				)
			end
		end
	end

	local i = 0
	local stop = 19
	local o = page * stop

	local function sortf(a, b)
		return a["rival"]["map"] < b["rival"]["map"]
	end

	for mode, tbl in pairs(scores) do
		if i >= stop then break end

		table.sort(tbl, sortf)

		for _, score in ipairs(tbl) do
			if o then
				o = o - 1
				continue
			end
			if i >= stop then break end
			i = i + 1

			local modestr = modeToString(score["rival"]["flags"])

			local diff, color
			if score["your"] then
				diff = score["your"]["time"] - score["rival"]["time"]
				color = colors[clamp(-1, diff, 1)]
			end

			print(string.format(
				"%s\t%s\t%s%8s\t\x80%s",
				G_BuildMapName(score.rival.map),
				ticsToTime(score.rival.time),
				color or "",
				diff ~= nil and sym[diff<0] + ticsToTime(abs(diff)) or ticsToTime(0, true),
				modestr
			))
		end
	end

	print(string.format(
		"Your score = %s%s%s",
		colors[clamp(-1, totalDiff, 1)],
		sym[totalDiff<0],
		ticsToTime(abs(totalDiff))
	))

	print(string.format(
		"Page %d out of %d",
		page + 1,
		totalScores / stop + 1
	))
end, COM_LOCAL)

COM_AddCommand("lb_move_records", function(player, from, to)
	if not (from and to) then
		CONS_Printf(player,
			"\x82Usage:\x80 lb_move_records <from> <to>\n"..
			"\x82Summary:\x80 Move records from one map to another.\n"..
			"If no checksum is supplied for <to>, the loaded map's checksum is used.\n"..
			"To\x85 DELETE\x80 records, write /dev/null in <to>.\n"..
			"\x82Hint:\x80 Use lb_known_maps to find checksums"
		)
		return
	end

	local sourcemap, sourcesum = mapnumFromExtended(from)
	local targetmap, targetsum = mapnumFromExtended(to)

	if to == "/dev/null" then
		targetmap = -1
	end

	if not sourcemap then
		CONS_Printf(player, string.format("error: invalid map %s", from:upper()))
		return
	end
	if not targetmap then
		CONS_Printf(player, string.format("error: invalid map %s", to:upper()))
		return
	end

	if not sourcesum then
		CONS_Printf(player, string.format("error: %s checksum for %s", sourcesum == false and "invalid" or "missing", from:upper()))
		return
	end

	if targetmap ~= -1 then
		if targetsum == nil then targetsum = mapChecksum(targetmap) end
		if targetsum == false then
			CONS_Printf(player, string.format("error: invalid checksum for %s", to:upper()))
			return
		elseif not targetsum then
			CONS_Printf(player, string.format("error: %s is not loaded; provide checksum to continue", to:upper()))
			return
		end
	end

	local recordCount = MoveRecords(sourcemap, sourcesum, targetmap, targetsum, ST_SEP)

	CONS_Printf(
		player,
		string.format(
			"%d records have been moved from\x82 %s\x80 to\x88 %s",
			recordCount,
			from,
			to
		)
	)
end, COM_ADMIN)

addHook("MapLoad", function()
	TimeFinished = 0
	splits = {}
	prevLap = 0
	drawState = DS_DEFAULT
	scrollY = 50 * FRACUNIT
	scrollAcc = 0
	FlashTics = 0

	allowJoin(true)

	if disable then return end

	for mode, records in pairs(MapRecords) do
		if mode & ST_SEP ~= Flags & ST_SEP then continue end
		for _, score in ipairs(records) do
			-- TODO if not (score.flags & F_HASGHOST) then continue end
			if not (GhostStartPlaying(score) or isserver) then
				local map = gamemap
				CommsRequestGhosts(score.id, function(ok, data)
					if not ok then
						print("Ghost download failed "..score.id)
						return
					end
					-- yay upvalues!
					print("Got ghost for "..score.id)
					local ghosts = {}
					data = StringReader(data)
					while not data:empty() do
						local i = data:read8()
						ghosts[i] = data:readlstr()
					end
					for i, p in ipairs(score.players) do
						p.ghost = ghosts[i]
					end
					WriteMapStore(map)
				end)
			end
		end
	end
end)

-- now with an S!
local function getGamers()
	local gamers = {}
	for p in players.iterate do
		if p.valid and not p.spectator then
			table.insert(gamers, p)
		end
	end
	table.sort(gamers, function(a, b) return a.name < b.name end)
	return gamers
end

-- Item patches have the amazing property of being displaced 12x 13y pixels
local iXoffset = 13 * FRACUNIT
local iYoffset = 12 * FRACUNIT
local function drawitem(v, x, y, scale, itempatch, vflags)
	v.drawScaled(
		x * FRACUNIT - FixedMul(iXoffset, scale),
		y * FRACUNIT - FixedMul(iYoffset, scale),
		scale,
		itempatch,
		vflags
	)
end

local modePatches = {
	[F_SPBATK] = "SPB",
	[F_SPBJUS] = "HYUD",
	[F_SPBBIG] = "BIG",
	[F_SPBEXP] = "INV"
}

local function modePatch(flag)
	if flag == F_SPBEXP then
		return PATCH[modePatches[flag]][(leveltime / 3) % 6]
	end
	return PATCH[modePatches[flag]]
end

local cursors = {
	[1] = ". ",
	[2] = " ."
}
local function marquee(text, maxwidth)
	if #text <= maxwidth then
		return text
	end

	local shift = 16

	-- Creates an index range ranging from -shift to #text + shift
	local pos = ((leveltime / 16) % (#text - maxwidth + shift * 2)) + 1 - shift

	local cursor = ""
	if pos < #text - maxwidth + 1 then
		cursor = cursors[((leveltime / 11) % #cursors) + 1]
	end

	-- The pos is the index going from -shift to #text + shift
	-- It's clamped within the text boundaries ie.
	-- 0 < pos < #text - maxwidth
	pos = min(max(pos, 1), #text - maxwidth + 1)
	return text:sub(pos, pos + maxwidth - 1) + cursor
end

-- Bats on ...
local bodium = {V_YELLOWMAP, V_GRAYMAP, V_BROWNMAP, 0}

local splitColor = {
	[-1] = V_SKYMAP,
	[0] = V_PURPLEMAP,
	[1] = V_REDMAP
}
local splitSymbol = {
	[-1] = "-",
	[0] = "",
	[1] = "+"
}

local showSplit = 0
local VFLAGS = V_SNAPTOLEFT
local FACERANK_DIM = 16
local FACERANK_SPC = FACERANK_DIM + 4

local function scaleHud(value)
	if not cv_smallhud.value then return value end

	return 9*value/10
end

local function drawScore(v, player, pos, x, y, gui, score, drawPos, textVFlags)
	textVFlags = textVFlags or V_HUDTRANSHALF

	local hudscale = scaleHud(FRACUNIT)
	local frdim = scaleHud(FACERANK_DIM)

	-- from left to right

	-- Position
	if drawPos then
		v.drawNum(x, y + 3, pos, textVFlags | VFLAGS)
	end

	--draw Patch/chili
	for i, p in ipairs(score.players) do
		local faceRank = PATCH[useHighresPortrait() and "FACEWANT" or "FACERANK"][p.skin] or PATCH["NORANK"]
		local facedownscale = (faceRank ~= PATCH["NORANK"] and useHighresPortrait()) and 2 or 1
		local color = p.color < MAXSKINCOLORS and p.color or 0
		v.drawScaled(x<<FRACBITS, y<<FRACBITS, hudscale/facedownscale, faceRank, V_HUDTRANS | VFLAGS, v.getColormap(TC_DEFAULT, color))

		if player.name == p.name then
			v.drawScaled(x<<FRACBITS, y<<FRACBITS, hudscale, PATCH["CHILI"][(leveltime / 4) % 8], V_HUDTRANS | VFLAGS)
		end

		-- draw a tiny little dot so you know which player's name is being shown
		if #score.players > 1 and (leveltime / (TICRATE*5) % #score.players) + 1 == i then
			v.drawFill(x, y, 1, 1, 128)
		end

		x = x + 17
	end
	x = x - 17

	-- Encore
	if score["flags"] & F_ENCORE then
		local ruby_scale = scaleHud(FRACUNIT/6)

		local bob = sin((leveltime + i * 5) * (ANG10))
		v.drawScaled(
			x * FRACUNIT,
			bob + (y + frdim/2) << FRACBITS,
			ruby_scale,
			PATCH["RUBY"],
			V_HUDTRANS | VFLAGS
		)
	end

	-- SPB
	if score["flags"] & F_SPBATK then
		local scale = scaleHud(FRACUNIT / 4)

		drawitem(
			v,
			x - 2,
			y - 2,
			scale,
			modePatch(F_SPBATK),
			V_HUDTRANS | VFLAGS
		)
		if score["flags"] & F_SPBEXP then
			drawitem(
				v,
				x + frdim - 4,
				y - 2,
				scale,
				modePatch(F_SPBEXP),
				V_HUDTRANS | VFLAGS
			)
		end
		if score["flags"] & F_SPBBIG then
			drawitem(
				v,
				x - 2,
				y + frdim - 4,
				scale,
				modePatch(F_SPBBIG),
				V_HUDTRANS | VFLAGS
			)
		end
		if score["flags"] & F_SPBJUS then
			drawitem(
				v,
				x + frdim - 4,
				y + frdim - 4,
				scale,
				modePatch(F_SPBJUS),
				V_HUDTRANS | VFLAGS
			)
		end
	end

	-- Stats
	local stat = score["stat"]
	local pskin = score["skin"] and skins[score["skin"]]
	if stat and not (
			pskin
			and pskin.kartweight == stat & MSK_WEIGHT
			and pskin.kartspeed == (stat & MSK_SPEED) >> 4
		) then

		local spd_yoff = 4
		local acc_yoff = 8

		if cv_smallhud.value then
			spd_yoff = 3
			acc_yoff = 8
		end

		v.drawString(x + frdim - 2, y + spd_yoff, (stat & MSK_SPEED) >> 4, V_HUDTRANS | VFLAGS, "small")
		v.drawString(x + frdim - 2, y + acc_yoff, stat & MSK_WEIGHT, V_HUDTRANS | VFLAGS, "small")
	end

	if gui == GUI_ON or (gui == GUI_SPLITS and showSplit) then
		local name = score.players[(leveltime / (TICRATE*5) % #score.players) + 1].name

		-- Shorten long names
		local stralign = "left"
		local MAXWIDTH = 70
		local px = 2
		local py = 0

		if cv_smallhud.value then
			stralign = "small"
			px = 3
			py = 1
		elseif v.stringWidth(name) > MAXWIDTH then
			stralign = "thin"
			py = -1
			if v.stringWidth(name, 0, "thin") > MAXWIDTH then
				stralign = "small"
				py = 2
				if v.stringWidth(name, 0, "small") > MAXWIDTH then
					name = marquee(name, 15)
				end
			end
		end

		local flashV = 0
		local me = true
		local gamers = getGamers()
		for i, p in ipairs(gamers) do
			local sp = score.players[i]
			if sp and p.name ~= sp.name then
				me = false
				break
			end
		end
		if me and FlashTics > leveltime then
			flashV = FlashVFlags[leveltime / FlashRate % (#FlashVFlags + 1)]
		end

		v.drawString(
			x + frdim + px,
			y + py,
			name,
			textVFlags | V_ALLOWLOWERCASE | VFLAGS | flashV,
			stralign
		)

		local time_yoff = frdim/2

		if cv_smallhud.value then
			time_yoff = frdim - 4
		end

		-- Draw splits
		if showSplit and score["splits"] and score["splits"][prevLap] != nil then
			local split = splits[prevLap] - score["splits"][prevLap]
			v.drawString(
				x + px + frdim,
				y + time_yoff,
				splitSymbol[clamp(-1, split, 1)] + ticsToTime(abs(split)),
				textVFlags | splitColor[clamp(-1, split, 1)] | VFLAGS,
				cv_smallhud.value and "small" or nil
			)
		else
			v.drawString(
				x + px + frdim,
				y + time_yoff,
				ticsToTime(score["time"], true),
				textVFlags | bodium[min(pos, 4)] | VFLAGS | flashV,
				cv_smallhud.value and "small" or nil
			)
		end
	end
end

local function drawDefault(v, player, scoreTable, gui)
	local yoffset = (200 / 4) + 4
	local x = cv_smallhud.value and 10 or 4

	local frspc = scaleHud(FACERANK_SPC)

	-- Draw placeholder score
	if scoreTable == nil then
		drawScore(v, player, 1, x, y, gui, {["players"] = { { name = UNCLAIMED, color = 0 } }, ["time"] = 0, ["flags"] = 0})
	else
		for pos, score in ipairs(scoreTable) do
			if pos > 5 then break end

			local y = yoffset + (frspc) * (pos - 1)
			drawScore(
				v, player, pos,
				x, y,
				gui, score
			)
		end
	end
end

local function drawScroll(v, player, scoreTable, gui)
	local frspc = scaleHud(FACERANK_SPC)
	local frdim = scaleHud(FACERANK_DIM)

	if scoreTable then
		scrollY = scrollY + FixedMul(1 * FRACUNIT, scrollAcc)

		local minim = -((#scoreTable - 1) * frspc * FRACUNIT)
		local maxim = (200 - frdim) * FRACUNIT

		scrollY = clamp(minim, scrollY, maxim)

		-- Bounceback
		if scrollY == minim or scrollY == maxim then
			scrollAcc = -FixedMul(scrollAcc, FRACUNIT / 3)
		end

		local x = 10
		if #scoreTable >= 10 then
			x = x + 8
			if #scoreTable >= 100 then
				x = x + 8
			end
		end

		local y = FixedInt(scrollY)

		for pos, score in ipairs(scoreTable) do
			drawScore(
				v, player, pos,
				x, y + ((pos - 1) * frspc),
				gui, score,
				true,
				V_HUDTRANS
			)
		end
	end
end
local function drawAuto(v, player, scoreTable, gui)
end

local scrollToPos = nil
local function drawScrollTo(v, player, scoreTable, gui)
	local frspc = scaleHud(FACERANK_SPC)

	drawState = DS_SCROLL
	if scrollToPos == nil then return end

	scrollY = (-(scrollToPos * frspc) + (100 - frspc / 2)) * FRACUNIT
	scrollToPos = nil
	drawScroll(v, player, scoreTable, gui)
end

local function drawBrowser(v, player)
	DrawBrowser(v, player)

	if not singleplayer() then
		v.drawString(0, 191, (SG_Color2Chat and SG_Color2Chat[BrowserPlayer.skincolor] or "")..BrowserPlayer.name.."\x80 is in control", V_20TRANS|V_ALLOWLOWERCASE|V_6WIDTHSPACE, "thin")
	end
end

local stateFunctions = {
	[DS_DEFAULT] = drawDefault,
	[DS_SCROLL] = drawScroll,
	[DS_AUTO] = drawAuto,
	[DS_SCRLTO] = drawScrollTo,
	[DS_BROWSER] = drawBrowser
}

-- Draw mode and return pos + 1 if success
local function drawMode(v, pos, flag)
	if not (Flags & flag) then return pos end

	drawitem(v, pos * 6 + 1, 194, FRACUNIT / 4, modePatch(flag), V_SNAPTOBOTTOM | V_SNAPTOLEFT)
	return pos + 1
end

local function drawScoreboard(v, player)
	if disable then return end
	if player != displayplayers[0] then return end

	cachePatches(v)

	local gui = cv_gui.value or drawState == DS_BROWSER

	-- Force enable gui at start and end of the race
	if leveltime < START_TIME or player.exiting or player.lives == 0 then
		gui = GUI_ON
	end

	if gui then
		stateFunctions[drawState](v, player, ScoreTable, gui)

		local pos = 0
		-- Draw current active modes bottom left
		pos = drawMode(v, pos, F_SPBJUS)
		pos = drawMode(v, pos, F_SPBBIG)
		pos = drawMode(v, pos, F_SPBEXP)
	end
end
hud.add(drawScoreboard, "game")

function cachePatches(v)
	if PATCH == nil then
		PATCH = {}

		PATCH["CHILI"] = {}
		for i = 1, 8 do
			PATCH["CHILI"][i-1] = v.cachePatch("K_CHILI" + i)
		end

		PATCH["NORANK"] = v.cachePatch("M_NORANK")

		PATCH["FACERANK"] = {}
		PATCH["FACEWANT"] = {}
		for skin in skins.iterate do
			PATCH["FACERANK"][skin.name] = v.cachePatch(skin.facerank)
			PATCH["FACEWANT"][skin.name] = v.cachePatch(skin.facewant)
		end

		PATCH["SPB"] = v.cachePatch("K_ISSPB")
		PATCH["INV"] = {}
		for i = 1, 6 do
			PATCH["INV"][i - 1] = v.cachePatch("K_ISINV" + i)
		end
		PATCH["BIG"] = v.cachePatch("K_ISGROW")
		PATCH["HYUD"] = v.cachePatch("K_ISHYUD")
		PATCH["RUBY"] = v.cachePatch("RUBYICON")
	end
end

-- Find location of player and scroll to it
function scroll_to(player)
	local m = ScoreTable or {}

	scrollToPos = 2
	for pos, score in ipairs(m) do
		if player.name == score["name"] then
			scrollToPos = max(2, pos - 1)
			break
		end
	end

	drawState = DS_SCRLTO
end

-- Write skin stats to each score where there are none
--local function writeStats()
--	for _, t in pairs(lb) do
--		for _, scoreTable in pairs(t) do
--			for _, score in ipairs(scoreTable) do
--				local skin = skins[score["skin"]]
--				if skin and not score["stat"] then
--					local stats = stat_t(skin.kartspeed, skin.kartweight)
--					score["stat"] = stats
--				end
--			end
--		end
--	end
--end

local function checkFlags(p)
	local flags = 0

	-- Encore
	if encoremode then
		flags = $ | F_ENCORE
	end

	if not cv_spbatk then
		cv_spbatk = CV_FindVar("spbatk")
	end

	if cv_combiactive == nil then
		cv_combiactive = CV_FindVar("combi_active") or false
		cv_combiminimumplayers = CV_FindVar("combi_minimumplayers") or false
	end

	-- SPBAttack
	if server.SPBArunning and cv_spbatk.value then
		flags = $ | F_SPBATK

		if server.SPBAexpert then
			flags = $ | F_SPBEXP
		end
		if p.SPBAKARTBIG then
			flags = $ | F_SPBBIG
		end
		if p.SPBAjustice then
			flags = $ | F_SPBJUS
		end
	end

	-- Combi
	if cv_combiactive and cv_combiactive.value and cv_combiminimumplayers.value <= 2 then
		flags = $ | F_COMBI
	end

	return flags
end

local function isSameRecord(a, b, modeSep)
	if (a.flags & modeSep) ~= (b.flags & modeSep)
	or #a.players ~= #b.players then return false end
	for i = 1, #a.players do
		if a.players[i].name ~= b.players[i].name then return false end
	end
	return true
end

local function saveTime(player)
	-- Disqualify if the flags changed mid trial.
	if checkFlags(player) != Flags then
		print("Game mode change detected! Time has been disqualified.")
		S_StartSound(nil, 110)
		return
	end

	ScoreTable = $ or {}

	local players = {}
	local gamers = getGamers()
	for _, p in ipairs(gamers) do
		local pskin = skins[p.mo.skin]
		table.insert(players, player_t(
			p.name,
			p.mo.skin,
			p.skincolor,
			stat_t(p.HMRs or pskin.kartspeed, p.HMRw or pskin.kartweight),
			GhostStopRecording(p)
		))
	end

	local newscore = score_t(
		gamemap,
		Flags,
		TimeFinished,
		splits,
		players
	)

	-- Check if you beat your previous best
	for i, score in ipairs(ScoreTable) do
		if isSameRecord(newscore, score, 0) and not lbComp(newscore, score) then
			-- You suck lol
			S_StartSound(nil, 201)
			FlashTics = leveltime + TICRATE * 3
			FlashRate = 3
			FlashVFlags = RedFlash
			scroll_to(player)
			return
		end
	end

	-- Save the record
	SaveRecord(newscore, gamemap, ST_SEP)

	-- Set players text flash and play chime sfx
	S_StartSound(nil, 130)
	FlashTics = leveltime + TICRATE * 3
	FlashRate = 1
	FlashVFlags = YellowFlash

	-- Reload the MapRecords
	MapRecords = GetMapRecords(gamemap, ST_SEP)

	-- Set the updated ScoreTable
	ScoreTable = MapRecords[ST_SEP & Flags]

	-- Scroll the gui to the player entry
	scroll_to(player)
end

-- DEBUGGING
local function saveLeaderboard(player, time)
	TimeFinished = tonumber(time or player.realtime)
	splits = {1000, 2000, 3000}
	saveTime(player)
end
COM_AddCommand("save", saveLeaderboard)

local function regLap(player)
	if player.laps > prevLap and TimeFinished == 0 then
		prevLap = player.laps
		table.insert(splits, player.realtime)
		showSplit = 5 * TICRATE
	end
end

local function changeMap()
	COM_BufInsertText(server, "map " + nextMap + " -force -gametype race")
	nextMap = nil
end

local function removePlayerItems(player)
	if player.mo then
		local item = player.mo.hnext
		local nextitem

		while item and item.valid do
			nextitem = item.hnext

			P_RemoveMobj(item)

			item = nextitem
		end

		K_StripItems(player)
	end
end

local function think()
	if nextMap then changeMap() end

	-- O p t i m i z a t i o n
	local leveltime = leveltime

	if disable then
		hud.enable("minirankings")
		if cv_antiafk.value and not G_BattleGametype() then
			if not singleplayer() then
				for p in players.iterate do
					if p.valid and not p.spectator and not p.exiting and p.lives > 0 then
						if p.cmd.buttons or p.cmd.driftturn then
							p.afkTime = max(TICRATE*8, leveltime)
						end

						--Away from kart
						if p.afkTime + cv_afk_flashtime.value * TICRATE <= leveltime then
							if p.afkTime + cv_afk_flashtime.value * TICRATE == leveltime then
								chatprintf(p, "[AFK] \x89You went invisible due to inactivity. You will become visible again upon driving.")
							end

							removePlayerItems(p)
							p.kartstuff[k_hyudorotimer] = 2
						end
						if p.afkTime + AFK_BALANCE_WARN == leveltime then
							chatprintf(p, "[AFK] \x89You will be moved to spectator in 10 seconds!", false)
							S_StartSound(nil, 26, p)
						end
						if p.afkTime + AFK_BALANCE < leveltime then
							p.spectator = true
							chatprint("\x89" + p.name + " was moved to spectator due to inactivity.", true)
						end
					end
				end
			else
				for p in players.iterate do
					if p.valid and not p.spectator then
						p.afkTime = leveltime
					end
				end
			end
		end

		help = true
		return
	end

	showSplit = max(0, showSplit - 1)

	if not cv_teamchange then
		cv_teamchange = CV_FindVar("allowteamchange")
	end

	local gamers = getGamers()

	hud.disable("minirankings")

	if leveltime < START_TIME then
		-- Help message
		if leveltime == START_TIME - TICRATE * 3 then
			if help then
				help = false
				chatprint(HELP_MESSAGE, true)
			else
				help = true
			end
		end

		-- Autospec
		if leveltime == 1 then
			for s in players.iterate do
				if s.valid and s.spectator then
					COM_BufInsertText(s, string.format("view \"%d\"", #gamers[1]))
				end
			end
		end

		if leveltime > START_TIME - (3 * TICRATE) / 2 then
			if clearcheats then
				clearcheats = false
				for _, p in pairs(gamers) do
					p.SPBAKARTBIG = false
					p.SPBAjustice = false
					p.SPBAshutup = false
				end
			end

			Flags = checkFlags(gamers[1])

			-- make sure the spb actually spawned
			if server.SPBArunning and leveltime == START_TIME - 1 then
				if not (server.SPBAbomb and server.SPBAbomb.valid) then
					-- it didn't spawn, clear spb flags
					Flags = $ & !(F_SPBATK | F_SPBEXP | F_SPBBIG | F_SPBJUS)
				end
			end
		else
			hud.enable("freeplay")
		end
	elseif #gamers < ((Flags & F_COMBI) and 2 or 1) then
		if Flags & F_COMBI then disable = true end -- not taking any risks
		if cv_teamchange.value == 0 then
			allowJoin(true)
		end
		return
	end

	ScoreTable = MapRecords[ST_SEP & Flags]

	for _, p in ipairs(gamers) do
		-- must be done before browser control
		if p.laps >= mapheaderinfo[gamemap].numlaps and TimeFinished == 0 then
			TimeFinished = p.realtime
			saveTime(p)
		end

		if p.cmd.buttons or p.cmd.driftturn then
			p.afkTime = leveltime
		end

		regLap(p)
	end

	-- Scroll controller
	-- Spectators can't input buttons so let the gamer do it
	if drawState == DS_SCROLL then
		-- TODO nice port priority
		if gamers[1].cmd.buttons & BT_BACKWARD then
			scrollAcc = scrollAcc - FRACUNIT / 3
		elseif gamers[1].cmd.buttons & BT_FORWARD then
			scrollAcc = scrollAcc + FRACUNIT / 3
		else
			scrollAcc = FixedMul(scrollAcc, (FRACUNIT * 90) / 100)
			if scrollAcc < FRACUNIT and scrollAcc > -FRACUNIT then
				scrollAcc = 0
			end
		end
	elseif drawState == DS_BROWSER then
		if BrowserController(BrowserPlayer) then
			drawState = DS_DEFAULT
		end

		-- prevent intermission while browsing
		for _, p in pairs(gamers) do
			if p.exiting then
				p.exiting = $ + 1
			end
		end

		-- disable spba hud
		if server.SPBArunning and server.SPBAdone then
			server.SPBArunning = false
			BrowserPlayer.pflags = $ & !(PF_TIMEOVER)
			BrowserPlayer.exiting = 100
		end

		-- prevent softlocking the server
		if BrowserPlayer.afkTime + AFK_BROWSER < leveltime then
			drawState = DS_DEFAULT
			S_StartSound(nil, 100)
		end
	elseif gamers[1].lives == 0 then
		drawState = DS_SCROLL
	end

	if not replayplayback then
		local afktime = 0
		for _, p in ipairs(gamers) do
			afktime = max($, p.afkTime)
		end
		if leveltime > PREVENT_JOIN_TIME and afktime + AFK_TIMEOUT > leveltime then
			if cv_teamchange.value then
				allowJoin(false)
			end
		elseif afktime + AFK_TIMEOUT < leveltime then
			if not cv_teamchange.value then
				allowJoin(true)
			end
		end
	end
end
addHook("ThinkFrame", think)

-- WELCOME BACK NEOROULETTE
-- combi is strictly sneakers only... from item boxes
local preroulette
addHook("PreThinkFrame", function()
	if not disable then
		for p in players.iterate do
			preroulette[p] = p.kartstuff[k_itemroulette]
		end
	end
end)
addHook("PlayerThink", function(p)
	if not disable and preroulette[p] and not p.kartstuff[k_itemroulette] and not p.kartstuff[k_eggmanexplode] then
		p.kartstuff[k_itemtype] = KITEM_SNEAKER
		p.kartstuff[k_itemamount] = 1
	end
end)
addHook("MapChange", function() preroulette = {} end)

local function interThink()
	if nextMap then changeMap() end

	if not cv_teamchange then
		cv_teamchange = CV_FindVar("allowteamchange")
	end

	if not cv_teamchange.value then
		allowJoin(true)
	end
end
addHook("IntermissionThinker", interThink)
addHook("VoteThinker", interThink)

local cv_highresportrait
function useHighresPortrait()
	if cv_higresportrait == nil then
		cv_highresportrait = CV_FindVar("highresportrait") or false
	end
	if cv_highresportrait then
		return cv_highresportrait.value ~= cv_lb_highresportrait.value
	end

	return cv_lb_highresportrait.value
end

-- Returns the values clamed between min, max
function clamp(min_v, v, max_v)
	return max(min_v, min(v, max_v))
end

local function netvars(net)
	Flags = net($)
	splits = net($)
	prevLap = net($)
	drawState = net($)
	EncoreInitial = net($)
	MapRecords = net($)
	TimeFinished = net($)
	clearcheats = net($)
	BrowserPlayer = net($)
	preroulette = net($)
end
addHook("NetVars", netvars)
