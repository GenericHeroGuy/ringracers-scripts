-- This file handles the storage and related netvars of the leaderboard

---- Imported functions ----

-- lb_common.lua
local stat_t = lb_stat_t
local lbComp = lb_comp
local score_t = lb_score_t
local player_t = lb_player_t
local mapChecksum = lb_map_checksum
local mapnumFromExtended = lb_mapnum_from_extended

----------------------------

local LEADERBOARD_FILE = "leaderboard.sav2"
local LEADERBOARD_FILE_OLD = "leaderboard.txt"
local COLDSTORE_FILE = "leaderboard.coldstore.sav2"
local LEADERBOARD_VERSION = 1

-- ColdStore are records loaded from lua addons
-- this table should never be modified outside of the AddColdStore function
local ColdStore = {}

-- Livestore are new records nad records loaded from leaderboard.txt file
local LiveStore = {}

-- parse score function
local parseScore

local MSK_SPEED = 0xF0
local MSK_WEIGHT = 0xF
local function stat_str(stat)
	if stat then
		return string.format("%d%d", (stat & MSK_SPEED) >> 4, stat & MSK_WEIGHT)
	end

	return "0"
end

local function isSameRecord(a, b, modeSep)
	if (a.flags & modeSep) ~= (b.flags & modeSep)
	or #a.players ~= #b.players then return false end
	for i = 1, #a.players do
		if a.players[i].name ~= b.players[i].name then return false end
	end
	return true
end

-- insert or replace the score in dest
local function insertOrReplace(dest, score, modeSep)
	for i, record in ipairs(dest) do
		if isSameRecord(record, score, modeSep) then
			if lbComp(score, record) then
				dest[i] = score
			end
			return
		end
	end

	table.insert(dest, score)
end

local function READ8(f)
	return f:read(1):byte()
end
local function READ16(f)
	local nl, nh = f:read(2):byte(1, 2)
	return nl | (nh << 8)
end
local function READNUM(f)
	local num = 0
	for i = 0, 7*(5-1), 7 do
		local c = f:read(1):byte()
		num = num | (c & 0x7f) << i
		if not (c & 0x80) then return num end
	end
	error("Overlong number at "..f:seek("cur", 0), 2)
end
local function READSTR(f)
	local len = f:read(1):byte()
	return f:read(len)
end

-- write functions go into a string buffer, not a file
-- if something goes wrong, you won't end up with a half-written file
local tins = table.insert
local function WRITE8(f, num)
	tins(f, string.char(num))
end
local function WRITE16(f, num)
	tins(f, string.char(num & 0xffff00ff, (num & 0xffffff00) >> 8))
end
local function WRITENUM(f, num)
	if num < 0 then
		error("Cannot write negative numbers", 2)
	end
	repeat
		tins(f, string.char((num >= 128 and 0x80 or 0x00) | (num & 0x7f)))
		num = num >> 7
	until not num
end
local function WRITESTR(f, str)
	if #str > 255 then
		error("String too long", 2)
	end
	tins(f, string.char(#str))
	tins(f, str)
end

local function dumpStoreToFile(filename, store)
	local f = { "LEADERBOARD", string.char(LEADERBOARD_VERSION) }

	for mapid, checksums in pairs(store) do
		for checksum, records in pairs(checksums) do
			WRITENUM(f, mapid)
			WRITENUM(f, #records)
			for _, record in ipairs(records) do
				WRITE16(f, tonumber(record.checksum, 16))
				WRITENUM(f, record.flags)
				WRITENUM(f, record.time)
				WRITE8(f, #record.splits)
				for _, v in ipairs(record.splits) do
					WRITENUM(f, v)
				end
				WRITE8(f, #record.players)
				for _, p in ipairs(record.players) do
					WRITESTR(f, p.name)
					WRITESTR(f, p.skin)
					WRITE8(f, p.color)
					WRITE8(f, p.stat)
				end
			end
		end
	end

	local out = assert(
		io.open(filename, "wb"),
		"Failed to open file for writing: "..filename
	)
	out:write(table.concat(f))
	out:close()
end

-- GLOBAL
-- Returns a list of all maps with records
local function MapList()
	local maps = {}
	for mapid, checksums in pairs(ColdStore) do
		maps[mapid] = $ or {}
		for checksum in pairs(checksums) do
			maps[mapid][checksum] = true
		end
	end
	for mapid, checksums in pairs(LiveStore) do
		maps[mapid] = $ or {}
		for checksum in pairs(checksums) do
			maps[mapid][checksum] = true
		end
	end

	local maplist = {}
	for mapid, checksums in pairs(maps) do
		for checksum in pairs(checksums) do
			table.insert(maplist, {["id"] = mapid, ["checksum"] = checksum})
		end
	end
	table.sort(maplist, function(a, b) return a.id < b.id end)

	return maplist
end
rawset(_G, "lb_map_list", MapList)

-- GLOBAL
-- Function for adding a single record from lua
local function AddColdStore(record)
	ColdStore[record.map] = $ or {}
	ColdStore[record.map][record.checksum] = $ or {}

	table.insert(ColdStore[record.map][record.checksum], record)
end
rawset(_G, "lb_add_coldstore_record", AddColdStore)

-- Insert mode separated records from the flat sourceTable into dest
local function insertRecords(dest, sourceTable, checksum, modeSep)
	if not sourceTable then return end
	if not sourceTable[checksum] then return end

	local mode = nil
	for _, record in ipairs(sourceTable[checksum]) do
		mode = record.flags & modeSep
		dest[mode] = $ or {}
		table.insert(dest[mode], record)
	end
end

-- GLOBAL
-- Construct the leaderboard table of the supplied mapid
-- combines the ColdStore and LiveStore records
local function GetMapRecords(map, checksum, modeSep)
	local mapRecords = {}

	-- Insert ColdStore records
	insertRecords(mapRecords, ColdStore[map], checksum, modeSep)

	-- Insert LiveStore records
	insertRecords(mapRecords, LiveStore[map], checksum, modeSep)

	-- Sort records
	for _, records in pairs(mapRecords) do
		table.sort(records, lbComp)
	end

	-- Remove duplicate entries
	for _, records in pairs(mapRecords) do
		local seen = {}
		local i = 1
		while i <= #records do
			local namestr = ""
			for _, p in ipairs(records[i].players) do
				namestr = $..p.name.."\x00" -- need a separator to avoid wacky stuff
			end
			if seen[namestr] then
				table.remove(records, i)
			else
				seen[namestr] = true
				i = i + 1
			end
		end
	end

	return mapRecords
end
rawset(_G, "lb_get_map_records", GetMapRecords)

-- GLOBAL
-- Save a record to the LiveStore and write to disk
-- SaveRecord will replace the record holders previous record
local function SaveRecord(score, map, modeSep)
	local checksum = mapChecksum(map)
	LiveStore[map] = $ or {}
	LiveStore[map][checksum] = $ or {}
	insertOrReplace(LiveStore[map][checksum], score, modeSep)

	print("Saving score")
	if isserver then 
		dumpStoreToFile(LEADERBOARD_FILE, LiveStore)
	end
end
rawset(_G, "lb_save_record", SaveRecord)

local function netvars(net)
	LiveStore = net($)
end

addHook("NetVars", netvars)

local function oldParseScore(str)
	-- Leaderboard is stored in the following tab separated format
	-- mapnum, name, skin, color, time, splits, flags, stat
	local t = {}
	for word in (str.."\t"):gmatch("(.-)\t") do
		table.insert(t, word)
	end

	local splits = {}
	if t[6] != nil then
		for str in t[6]:gmatch("([^ ]+)") do
			table.insert(splits, tonumber(str))
		end
	end

	local flags = 0
	if t[7] != nil then
		flags = tonumber(t[7])
	end

	local stats = nil
	if t[8] != nil then
		if #t[8] >= 2 then
			local speed = tonumber(string.sub(t[8], 1, 1))
			local weight = tonumber(string.sub(t[8], 2, 2))
			stats = stat_t(speed, weight)
		end
	end

	local checksum = t[9] or ""

	return score_t(
		tonumber(t[1]), -- Map
		checksum:lower(),
		flags,
		tonumber(t[5]),	-- Time
		splits,
		{
			player_t(
				t[2], -- Name
				t[3], -- Skin
				tonumber(t[4]), -- Color
				stats
			)
		}
	)
end
rawset(_G, "lb_parse_score", oldParseScore)

local function convertToBinary(f)
	print("Converting "..LEADERBOARD_FILE_OLD.." to binary")
	local output = {}
	local store = {}
	for l in f:lines() do
		local score = oldParseScore(l)
		store[score.map] = $ or {}
		store[score.map][score.checksum] = $ or {}
		table.insert(store[score.map][score.checksum], score)
	end

	dumpStoreToFile(LEADERBOARD_FILE, store)
end

local function parseScoreBinary(f, map)
	local checksum = string.format("%04x", READ16(f))
	local flags = READNUM(f)
	local time = READNUM(f)

	local splits = {}
	local numsplits = READ8(f)
	for i = 1, numsplits do
		table.insert(splits, READNUM(f))
	end

	local players = {}
	local numplayers = READ8(f)
	for i = 1, numplayers do
		local name = READSTR(f)
		local skin = READSTR(f)
		local color = READ8(f)
		local stats = READ8(f)
		table.insert(players, player_t(name, skin, color, stat_t(stats >> 4, stats & 0xf)))
	end

	return score_t(
		map,
		checksum,
		flags,
		time,
		splits,
		players
	)
end

local function loadStore(f, filename)
	local store = {}

	if f:read(11) ~= "LEADERBOARD" then
		error(string.format("Failed to read %s: bad magic", filename), 2)
	end
	local version = READ8(f)
	if version > LEADERBOARD_VERSION then
		error(string.format("Failed to read %s: version %d not supported (highest is %d)", filename, version, LEADERBOARD_VERSION), 2)
	end

	while f:read(0) do
		local map = READNUM(f)
		local numrecords = READNUM(f)
		for i = 1, numrecords do
			local score = parseScoreBinary(f, map)
			if score then
				store[score.map] = $ or {}
				store[score.map][score.checksum] = $ or {}
				table.insert(store[score.map][score.checksum], score)
			end
		end
	end

	f:close()

	return store
end

-- Read and parse a store file
local function loadStoreFile(filename)
	local f = assert(
		io.open(filename, "rb"),
		"Failed to open file for reading: "..filename
	)

	return loadStore(f, filename)
end

local function AddColdStoreBinary(str)
	local f = {
		lb_base128_decode(str), 1,
		-- sorry, gotta keep it high-performance
		read = function(self, num)
			if not num then return #self[1] > self[2] end
			local s = self[1]:sub(self[2], self[2]+num-1)
			self[2] = $ + num
			return s
		end,
		close = do end
	}
	ColdStore = loadStore(f)
end
rawset(_G, "lb_add_coldstore_binary", AddColdStoreBinary)

-- GLOBAL
-- Command for moving records from one map to another
local function moveRecords(from, to, modeSep)
	local function moveRecordsInStore(store)
		if not (store[from.id] and store[from.id][from.checksum]) then
			return 0
		end

		store[to.id] = $ or {}
		store[to.id][to.checksum] = $ or {}
		for i, score in ipairs(store[from.id][from.checksum]) do
			score.map = to.id
			score.checksum = to.checksum
			insertOrReplace(store[to.id][to.checksum], score, modeSep)
		end

		-- Destroy the original table
		store[from.id][from.checksum] = nil
	end

	-- move livestore records and write to disk
	moveRecordsInStore(LiveStore)

	if isserver then
		dumpStoreToFile(LEADERBOARD_FILE, LiveStore)

		-- move coldstore records
		local ok, coldstore = pcall(loadStoreFile, COLDSTORE_FILE)
		if ok and coldstore then
			moveRecordsInStore(coldstore)
			dumpStoreToFile(COLDSTORE_FILE, coldstore)
		end
	end
end
rawset(_G, "lb_move_records", moveRecords)

COM_AddCommand("lb_write_coldstore", function(player, filename)
	if not filename then
		CONS_Printf(player, "Usage: lb_write_coldstore <filename>")
		return
	end

	if filename:sub(#filename-3) != ".txt" then
		filename = $..".txt"
	end

	local store = {}
	for map, checksums in pairs(ColdStore) do
		store[map] = $ or {}
		for checksum, records in pairs(checksums) do
			store[map][checksum] = $ or {}
			for _, record in ipairs(records) do
				insertOrReplace(store[map][checksum], record, -1)
			end
		end
	end
	for map, checksums in pairs(LiveStore) do
		store[map] = $ or {}
		for checksum, records in pairs(checksums) do
			store[map][checksum] = $ or {}
			for _, record in ipairs(records) do
				insertOrReplace(store[map][checksum], record, -1)
			end
		end
	end

	dumpStoreToFile(COLDSTORE_FILE, store)
	print("Cold store written to "..COLDSTORE_FILE)

	local f = io.open(COLDSTORE_FILE, "rb")
	local out = io.open(filename, "wb")
	-- B-B-BUT WHAT ABOUT PLAYER NAMES?
	-- right now we use base128 encoding, which doesn't have ] in its character set so that's not an issue
	-- if base252 ever becomes real we'll have to make it base251 and exclude ]
	out:write("lb_add_coldstore_binary[[")
	out:write(lb_base128_encode(f:read("*a")))
	out:write("]]")
	out:close()
	f:close()
	print("Cold store script written to "..filename.." (rename to "..filename:gsub(".txt", ".lua").."!)")

	print("You may now delete "..LEADERBOARD_FILE)
end, COM_LOCAL)

-- Helper function for those upgrading from 1.2 to 1.3
COM_AddCommand("lb_write_checksums", function(player)
	local count = 0
	local moved = {}

	-- Gather movable records (no checksum, map loaded)
	for map, checksums in pairs(LiveStore) do
		for checksum, records in pairs(checksums) do
			if checksum == "" then
				local sum = mapChecksum(map)

				if not sum then continue end

				moved[map] = {}
				moved[map][sum] = {}

				for i, record in ipairs(records) do
					record.checksum = sum
					table.insert(moved[map][sum], record)
				end
			end
		end
	end

	-- Write moved to livestore
	for map, checksums in pairs(moved) do
		LiveStore[map] = $ or {}
		for checksum, records in pairs(checksums) do
			LiveStore[map][checksum] = $ or {}
			for i, score in ipairs(records) do
				table.insert(LiveStore[map][checksum], score)
			end
			count = $ + #records
		end
		LiveStore[map][""] = nil
	end

	if isserver then
		dumpStoreToFile(LEADERBOARD_FILE, LiveStore)
	end

	CONS_Printf(player, string.format("Successful operation on %d records", count))
end, COM_ADMIN)

COM_AddCommand("lb_known_maps", function(player, map)
	local mapnum = gamemap
	if map then
		mapnum = mapnumFromExtended(map)
		if not mapnum then
			CONS_Printf(player, string.format("invalid map '%s'", map))
			return
		end
	end

	local known = {}

	if LiveStore[mapnum] then
		for checksum, records in pairs(LiveStore[mapnum]) do
			known[checksum] = #records
		end
	end
	if ColdStore[mapnum] then
		for checksum, records in pairs(ColdStore[mapnum]) do
			known[checksum] = $ or 0 + #records
		end
	end

	CONS_Printf(player, "Map     Chck   Records")
	for checksum, count in pairs(known) do
		CONS_Printf(player, string.format("%s   %s   %d", G_BuildMapName(mapnum), checksum, count))
	end
end)

COM_AddCommand("lb_download_live_records", function(player, filename)
	if not filename then
		CONS_Printf(player, "Usage: lb_download_live_records <filename>")
		return
	end

	if filename:sub(#filename-4) != ".sav2" then
		filename = $..".sav2"
	end
	dumpStoreToFile(filename, LiveStore)
end, COM_LOCAL)

-- Load the livestore
if isserver then
	local f = io.open(LEADERBOARD_FILE_OLD)
	local b = io.open(LEADERBOARD_FILE)
	if f and not b then
		convertToBinary(f)
		f:close()
	end
	LiveStore = loadStoreFile(LEADERBOARD_FILE)
end
