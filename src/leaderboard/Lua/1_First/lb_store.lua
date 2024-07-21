-- This file handles the storage and related netvars of the leaderboard

---- Imported functions ----

-- lb_common.lua
local stat_t = lb_stat_t
local lbComp = lb_comp
local score_t = lb_score_t
local mapChecksum = lb_map_checksum
local mapnumFromExtended = lb_mapnum_from_extended

----------------------------

local LEADERBOARD_FILE = "leaderboard.txt"
local COLDSTORE_FILE = "leaderboard.coldstore.txt"

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
	return a.name == b.name and (a.flags & modeSep) == (b.flags & modeSep)
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

local function dumpStoreToFile(filename, store)
	local f = assert(
		io.open(filename, "w"),
		"Failed to open file for writing: "..filename
	)

	f:setvbuf("line")

	for mapid, checksums in pairs(store) do
		for checksum, records in pairs(checksums) do
			for _, record in ipairs(records) do
				if not record.checksum or record.checksum == "" then
					record.checksum = mapChecksum(record.map) or ""
				end

				f:write(
					mapid, "\t",
					record.name, "\t",
					record.skin, "\t",
					record.color, "\t",
					record.time, "\t",
					table.concat(record.splits, " "), "\t",
					record.flags, "\t",
					stat_str(record.stat), "\t",
					record.checksum, "\n"
				)
			end
		end
	end

	f:close()
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

-- GLOBAL
-- Function for adding a single record in string form from lua
local function AddColdStoreString(record)
	AddColdStore(parseScore(record))
end
rawset(_G, "lb_add_coldstore_record_string", AddColdStoreString)

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
		local players = {}
		local i = 1
		while i <= #records do
			if players[records[i].name] then
				table.remove(records, i)
			else
				players[records[i].name] = true
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

function parseScore(str)
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
		t[2],		-- Name
		t[3],		-- Skin
		t[4],		-- Color
		tonumber(t[5]),	-- Time
		splits,
		flags,
		stats,
		checksum:lower()
	)
end
rawset(_G, "lb_parse_score", parseScore)

-- Read and parse a store file
local function loadStoreFile(filename)
	local f = assert(
		io.open(filename, "r"),
		"Failed to open file for reading: "..filename
	)

	local store = {}

	for l in f:lines() do
		local score = parseScore(l)
		store[score.map] = $ or {}
		store[score.map][score.checksum] = $ or {}
		table.insert(store[score.map][score.checksum], score)
	end

	f:close()

	return store
end

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

	if filename:sub(#filename-3) != ".txt" then
		filename = $..".txt"
	end
	dumpStoreToFile(filename, LiveStore)
end, COM_LOCAL)

-- Load the livestore
if isserver then
	LiveStore = loadStoreFile(LEADERBOARD_FILE)
end
