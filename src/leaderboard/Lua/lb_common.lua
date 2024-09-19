local RINGS = VERSION == 2

rawset(_G, "lb_score_t", function(flags, time, splits, players, id)
	return {
		["flags"]  = flags,
		["time"]   = time,
		["splits"] = splits,
		["players"] = players,
		["id"]     = id,
	}
end)

rawset(_G, "lb_player_t", function(name, skin, color, stat)
	return {
		["name"]   = name,
		["skin"]   = skin,
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

-- True if a is better than b
rawset(_G, "lb_comp", function(a, b)
	-- Calculates the difficulty, harder has higher priority
	-- if s is positive then a is harder
	-- if s is negative then b is harder
	-- if s is 0 then compare time
	local s = (a.flags & (F_SPBEXP | F_SPBBIG)) - (b.flags & (F_SPBEXP | F_SPBBIG))
	return s > 0 or not(s < 0 or a.time >= b.time)
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
rawset(_G, "lb_map_checksum", function(mapnum)
	local mh = mapheaderinfo[mapnum]
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

rawset(_G, "lb_mapname_and_checksum", function(map, checksum)
	if RINGS then
		return G_BuildMapName(map)
	else
		return string.format("%s:%s", G_BuildMapName(map), checksum)
	end
end)

-- ...throwdir!? what happened to BT_FORWARD/BT_BACKWARD?
-- well you might be surprised to learn that throwdir exists in both games :^)
-- so it's the least troublesome way to get up/down inputs
rawset(_G, "lb_throw_dir", function(p)
	if RINGS then
		return p.throwdir
	else
		return p.kartstuff[k_throwdir]
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
	empty = function(self)
		return self[2] > self[3]
	end
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
	end
} }

rawset(_G, "lb_string_writer", function()
	return setmetatable({}, writer)
end)
