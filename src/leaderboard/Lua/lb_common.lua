local RINGS = CODEBASE >= 220

rawset(_G, "lb_score_t", function(flags, time, starttime, splits, players, id)
	return {
		["flags"]  = flags,
		["time"]   = time,
		["starttime"] = starttime,
		["splits"] = splits,
		["players"] = players,
		["id"]     = id,
	}
end)

rawset(_G, "lb_player_t", function(pid, alias, skin, appear, color, stat)
	return {
		["pid"]    = pid,
		["alias"]  = alias,
		["skin"]   = skin,
		["appear"] = appear,
		["color"]  = color,
		["stat"]  = stat,
	}
end)

rawset(_G, "lb_ghost_t", function(data, startofs)
	return {
		["data"]     = data,
		["startofs"] = startofs,
	}
end)

rawset(_G, "lb_profile_t", function(aliases, publickey)
	return {
		["aliases"]   = aliases,
		["publickey"] = publickey,
	}
end)

rawset(_G, "lb_TicsToTime", function(tics, pure)
	if tics == 0 and pure then
		return "-'--\"--"
	end

	return string.format(
		"%d'%02d\"%02d",
		G_TicsToMinutes(tics, true),
		G_TicsToSeconds(tics),
		G_TicsToCentiseconds(tics)
	)
end)

rawset(_G, "lb_ZoneAct", function(map)
	local z = ""
	if map.zonttl != "" then
		z = " " + map.zonttl
	elseif not(map.levelflags & LF_NOZONE) then
		z = " Zone"
	end
	if map.actnum ~= (not RINGS and "" or 0) then
		z = $ + " " + map.actnum
	end

	return z
end)

rawset(_G, "lb_stat_t", function(speed, weight)
	return (speed << 4) | weight
end)

rawset(_G, "lb_flag_spbatk", 0x1)
rawset(_G, "lb_flag_spbjus", 0x2)
rawset(_G, "lb_flag_spbbig", 0x4)
rawset(_G, "lb_flag_spbexp", 0x8)
rawset(_G, "lb_flag_combi", 0x10)
rawset(_G, "lb_flag_hasghost", 0x20)
rawset(_G, "lb_flag_encore", 0x80)
local F_SPBBIG = lb_flag_spbbig
local F_SPBEXP = lb_flag_spbexp

local GAMETYPES = {}
local function gametype_t(name, gt, tol, text, fill, item, start)
	local gtab = {
		enabled = true,
		name = name,
		gametype = gt,
		typeoflevel = tol,
		textcolor = text,
		fillcolor = fill,
		itempatch = item,
		starttime = start,
	}
	CV_RegisterVar({
		name = "lb_gt_"..name:lower(),
		defaultvalue = "On",
		flags = CV_NETVAR | CV_CALL,
		PossibleValue = CV_OnOff,
		func = function(cv)
			gtab.enabled = cv.value
		end
	})
	table.insert(GAMETYPES, gtab)
end

if RINGS then
-- GTR_SPECIALSTART: skip title card, also mutes lap sound, also hides freeplay for some reason
-- GTR_NOPOSITION:   continuous music
G_AddGametype({
	"Leaderboard",
	"LEADERBOARD",
	GTR_CIRCUIT|GTR_ENCORE|GTR_SPECIALSTART|GTR_NOPOSITION,
	TOL_RACE,
	2,
	speed = 2,
})
G_AddGametype({
	"Leaderbattle",
	"LEADERBATTLE",
	GTR_SPHERES|GTR_BUMPERS|GTR_PAPERITEMS|GTR_POWERSTONES|GTR_KARMA|GTR_ITEMARROWS|GTR_PRISONS|GTR_BATTLESTARTS|GTR_POINTLIMIT|GTR_TIMELIMIT|GTR_OVERTIME|GTR_CLOSERPLAYERS|GTR_SPECIALSTART|GTR_NOPOSITION,
	TOL_BATTLE,
	2,
	speed = 0,
})
-- no GT_LEADERSPECIAL because G_SetCustomExitVars always switches to the default gametype

gametype_t("Race",    GT_LEADERBOARD,  TOL_RACE,    V_SKYMAP,    132, "K_ISSHOE", 15*TICRATE)
gametype_t("Battle",  GT_LEADERBATTLE, TOL_BATTLE,  V_REDMAP,    34,  "K_ISGBOM", 5*TICRATE + TICRATE/2)
gametype_t("Special", GT_SPECIAL,      TOL_SPECIAL, V_PURPLEMAP, 194, "K_ISSHOE", 0)
else
gametype_t("Race",   GT_RACE,  TOL_RACE|TOL_SP,    V_SKYMAP, 214, "K_ISSHOE", 6*TICRATE + 3*TICRATE/4)
gametype_t("Battle", GT_MATCH, TOL_MATCH|TOL_COOP, V_REDMAP, 126, "K_ISPOGO", 6*TICRATE + 3*TICRATE/4)
end

rawset(_G, "lb_gametype_for_map", function(mapname)
	local header = mapheaderinfo[lb_mapnum_from_extended(mapname)]
	if not header then return end
	local tol = header.typeoflevel
	for i, gtab in ipairs(GAMETYPES) do
		if tol & gtab.typeoflevel then
			return gtab, i
		end
	end
end)

rawset(_G, "lb_get_gametype", function()
	local gt = gametype
	for i, gtab in ipairs(GAMETYPES) do
		if gtab.gametype == gt then return gtab, i end
	end
end)

rawset(_G, "lb_next_gametype", function(i)
	local start = i
	repeat
		i = (i % #GAMETYPES) + 1
		local gtab = GAMETYPES[i]
		if gtab.enabled then return gtab, i end
	until i == start
end)

-- True if a is better than b
rawset(_G, "lb_comp", function(a, b)
	-- Calculates the difficulty, harder has higher priority
	-- if s is positive then a is harder
	-- if s is negative then b is harder
	-- if s is 0 then compare time
	local s = (a.flags & (F_SPBEXP | F_SPBBIG)) - (b.flags & (F_SPBEXP | F_SPBBIG))
	return s > 0 or not(s < 0 or a.time >= b.time)
end)

rawset(_G, "lb_is_same_record", function(a, b, modeSep)
	if (a.flags & modeSep) ~= (b.flags & modeSep)
	or #a.players ~= #b.players then return false end
	for i = 1, #a.players do
		local pa, pb = a.players[i], b.players[i]
		if pa.pid ~= pb.pid or pa.alias ~= pb.alias then return false end
	end
	return true
end)

local function djb2(message)
	local digest = 5381
	for i = 1, #message do
		digest = ($ * 33) + message:byte(i)
	end

	return digest
end
rawset(_G, "lb_djb2", djb2)

-- Produce a checksum by using the maps title, subtitle and zone
rawset(_G, "lb_map_checksum", function(mapname)
	local mh = mapheaderinfo[lb_mapnum_from_extended(mapname)]
	if not mh then
		return nil
	end

	local digest = string.format("%04x", djb2(mh.lvlttl..(RINGS and mh.menuttl or mh.subttl)..mh.zonttl) & 0xFFFF)
	return digest
end)

rawset(_G, "lb_mapnum_from_extended", function(map)
	if RINGS then
		-- how do you convert a map's lumpname back to a number?
		-- good question...
		if tonumber(map) or not map:find("_", 1, true) then
			return nil
		else
			return G_FindMapByNameOrCode(map), nil
		end
	end

	local p, q, checksum = map:upper():match("MAP(%w)(%w):?(.*)$", 1)
	if not (p and q) then
		return nil
	end

	if #checksum and #checksum ~= 4 or checksum:match("[^0-9A-F]") then
		checksum = false -- malformed
	elseif not #checksum then
		checksum = nil -- missing
	else
		checksum = $:lower()
	end

	local mapnum = 0
	local A = string.byte("A")

	if tonumber(p) != nil then
		-- Non extended map numbers
		if tonumber(q) == nil then
			return nil
		end
		mapnum = tonumber(p) * 10 + tonumber(q)
	else
		--Extended map numbers
		p = string.byte(p) - A
		local qn = tonumber(q)
		if qn == nil then
			qn = string.byte(q) - A + 10
		end

		mapnum = 36 * p + qn + 100
	end

	return mapnum, checksum
end)

rawset(_G, "lb_parse_mapname", function(str)
	str = $:upper()
	local checksum = str:find(":", 1, true)
	if checksum then
		checksum, str = str:sub(checksum+1), str:sub(1, checksum-1)
		checksum = #$ == 4 and $:lower() or false
	end

	if tonumber(str) then
		return G_BuildMapName(str), checksum
	elseif not RINGS and not str:upper():match("MAP%w%w") then
		for i = 1, #mapheaderinfo do
			local map = mapheaderinfo[i]
			if not map then continue end

			local lvlttl = map.lvlttl..lb_ZoneAct(map)

			if lvlttl:upper():find(str:upper()) then
				return G_BuildMapName(i), checksum
			end
		end
	else
		return RINGS and G_BuildMapName(G_FindMap(str)) or str:upper(), checksum
	end
end)

rawset(_G, "lb_mapname_and_checksum", function(map, checksum)
	if RINGS then
		return map
	else
		return ("%s:%s"):format(map, checksum)
	end
end)

-- ...throwdir!? what happened to BT_FORWARD/BT_BACKWARD?
-- well you might be surprised to learn that throwdir exists in both games :^)
-- so it's the least troublesome way to get up/down inputs
-- ^^^ i'm starting to doubt this ^^^
rawset(_G, "lb_throw_dir", function(p)
	if RINGS then
		return max(-1, min(p.cmd.throwdir, 1))
	else
		return p.spectator and max(-1, min(p.cmd.forwardmove, 1)) or p.kartstuff[k_throwdir]
	end
end)


rawset(_G, "lb_draw_num", function(v, x, y, num, flags)
	if RINGS then
		num = tostring($)
		for i = #num, 1, -1 do
			local char = v.cachePatch(string.format("MDFN%03d", num:byte(i)))
			x = $ - char.width
			v.draw(x, y, char, flags)
		end
	else
		v.drawNum(x, y, num, flags) -- Fun Fact: This function instantly segfaults in Dr. Robotnik's Ring Racers!
	end
end)

local cv_lb_highresportrait = CV_RegisterVar({
	name = "lb_highresportrait",
	defaultvalue = "Off",
	flags = 0,
	PossibleValue = CV_OnOff,
})
local norank, appear, cv_highresportrait
rawset(_G, "lb_get_portrait", function(v, p) -- player_t, not the userdata!
	if not norank then
		norank = v.cachePatch("M_NORANK")
		appear = APPEAR_HUD
		cv_highresportrait = CV_FindVar("highresportrait") or { value = 0 }
	end

	local hires = cv_highresportrait.value ~= cv_lb_highresportrait.value
	if p.faker then
		return norank, 1
	elseif RINGS then
		local k = hires and B or A
		return v.getSprite2Patch(p.skin, SPR2_XTRA, k), k+1
	else
		local k = hires and "facewant" or "facerank"
		local pskin = p.appear ~= "" and appear and appear[p.skin] and appear[p.skin][p.appear] or skins[p.skin]
		return pskin and v.cachePatch(pskin[k]) or norank, pskin and hires and 2 or 1
	end
end)

-- ok, this is a fucking eyesore... but integer keys are faster than string keys
-- and i do NOT want any lag spikes when reading from ~~files~~ strings, so, sigh
-- [1] = the string, [2] = position, [3] = length of string

local reader = { __index = {
	read8 = function(self)
		local p = self[2]
		local num = self[1]:byte(p)
		self[2] = p + 1
		return num
	end,
	read16 = function(self)
		local p = self[2]
		local lo, hi = self[1]:byte(p, p + 1)
		self[2] = p + 2
		return lo | (hi << 8)
	end,
	readnum = function(self)
		local num = 0
		local s, p = self[1], self[2]
		for i = 0, 7*(5-1), 7 do
			local c = s:byte(p)
			p = p + 1
			num = num | ((c & 0x7f) << i)
			if not (c & 0x80) then
				self[2] = p
				return num
			end
		end
		error("Overlong number at "..(p - 5))
	end,
	readstr = function(self)
		local s, p = self[1], self[2]
		local len = s:byte(p)
		p = p + 1 + len
		self[2] = p
		return s:sub(p - len, p - 1)
	end,
	readlstr = function(self)
		local s, p = self[1], self[2]
		local ll, lh = s:byte(p, p + 1)
		local len = ll | (lh << 8)
		p = p + 2 + len
		self[2] = p
		return s:sub(p - len, p - 1)
	end,
	readliteral = function(self, len)
		local p = self[2]
		p = p + len
		self[2] = p
		return self[1]:sub(p - len, p - 1)
	end,
	readpid = function(self)
		local p = self[2]
		local lo, hi, alias = self[1]:byte(p, p + 2)
		self[2] = p + 3
		return lo | (hi << 8), alias
	end,
	empty = function(self)
		return self[2] > self[3]
	end,
	tell = function(self)
		return self[2]
	end,
	seek = function(self, ofs)
		self[2] = ofs
	end,
} }

rawset(_G, "lb_string_reader", function(data)
	local str = data
	if not str then return end
	if type(data) == "userdata" then
		-- oh it's a file!
		str = data:read("*a")
		data:close()
	end
	return setmetatable({ str, 1, #str }, reader)
end)

-- write functions go into a string buffer, not a file
-- if something goes wrong, you won't end up with a half-written file
-- these functions are intentionally written to trigger overflows on bad input

local tins = table.insert
local schar = string.char
local writer = { __index = {
	write8 = function(self, num)
		tins(self, schar(num))
	end,
	write16 = function(self, num)
		tins(self, schar(num & 0xff, num >> 8))
	end,
	writenum = function(self, num)
		if num < 0 then
			error("Cannot write negative numbers", 2)
		end
		repeat
			tins(self, schar((num >= 128 and 0x80 or 0x00) | (num & 0x7f)))
			num = num >> 7
		until not num
	end,
	writestr = function(self, str)
		tins(self, schar(#str))
		tins(self, str)
	end,
	writelstr = function(self, str)
		local len = #str
		tins(self, schar(len & 0xff, len >> 8))
		tins(self, str)
	end,
	writeliteral = function(self, str)
		tins(self, str)
	end,
	writepid = function(self, prof)
		tins(self, schar(prof.pid & 0xff, prof.pid >> 8, prof.alias))
	end,
} }

rawset(_G, "lb_string_writer", function()
	return setmetatable({}, writer)
end)
