rawset(_G, "lb_score_t", function(map, checksum, flags, time, splits, players, id)
	return {
		["map"]    = map,
		["checksum"] = checksum,
		["flags"]  = flags,
		["time"]   = time,
		["splits"] = splits,
		["players"] = players,
		["id"]     = id,
	}
end)

rawset(_G, "lb_player_t", function(name, skin, color, stat, ghost)
	return {
		["name"]   = name,
		["skin"]   = skin,
		["color"]  = color,
		["stat"]  = stat,
		["ghost"] = ghost,
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
	if map.actnum != "" then
		z = $ + " " + map.actnum
	end

	return z
end)

rawset(_G, "lb_stat_t", function(speed, weight)
	return (speed << 4) | weight
end)


local F_SPBBIG = 0x4
local F_SPBEXP = 0x8
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
	for c in message:gmatch(".") do
		digest = (($ << 5) + $) + string.byte(c)
	end

	return digest
end

-- Produce a checksum by using the maps title, subtitle and zone
rawset(_G, "lb_map_checksum", function(mapnum)
	local mh = mapheaderinfo[mapnum]
	if not mh then
		return nil
	end

	local digest = string.format("%04x", djb2(mh.lvlttl..mh.subttl..mh.zonttl))
	return string.sub(digest, #digest - 3)
end)

rawset(_G, "lb_mapnum_from_extended", function(map)
	local p, q = map:upper():match("MAP(%w)(%w)$", 1)
	if not (p and q) then
		return nil
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

	return mapnum
end)

local eventHandler = {}

rawset(_G, "lb_hook", function(event, callback)
	local handle = eventHandler[event] or {}
	table.insert(handle, callback)
	eventHandler[event] = handle
end)

rawset(_G, "lb_fire_event", function(event, ...)
	local handle = eventHandler[event]
	if not handle then return end

	for _, callback in ipairs(handle) do
		pcall(callback, ...)
	end
end)

local b62 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function base62_encode(n)
	if n <= 0 then return "0" end
	local b62 = b62
	local q = n
	local r = ""
	local t
	while q > 0 do
		t = q % 62 + 1
		r = b62:sub(t, t)..r
		q = q / 62
	end
	return r
end

local function base62_decode(s)
	local n = b62:find(s:sub(1,1)) - 1
	for i = 2, #s do
		n = n * 62 + b62:find(s:sub(i, i)) - 1
	end

	return n
end

local function neg_base62_encode(n)
	if n == INT32_MIN then
		return "-2lkCB2"
	end

	if n < 0 then return "-"..base62_encode(abs(n)) end
	return base62_encode(n)
end

local function neg_base62_decode(s)
	if s:sub(1, 1) == "-" then return -base62_decode(s:sub(2)) end
	return base62_decode(s)
end

rawset(_G, "lb_base62_encode", neg_base62_encode)
rawset(_G, "lb_base62_decode", neg_base62_decode)
