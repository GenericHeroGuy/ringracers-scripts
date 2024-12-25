-- This file handles the storage and related netvars of the leaderboard

---- Imported functions ----

-- lb_common.lua
local stat_t = lb_stat_t
local lbComp = lb_comp
local score_t = lb_score_t
local player_t = lb_player_t
local mapChecksum = lb_map_checksum
local ParseMapname = lb_parse_mapname
local ticsToTime = lb_TicsToTime
local StringReader = lb_string_reader
local StringWriter = lb_string_writer
local ghost_t = lb_ghost_t
local profile_t = lb_profile_t
local isSameRecord = lb_is_same_record

----------------------------

local RINGS = CODEBASE >= 220
local open = RINGS and function(path, mode) return io.openlocal("client/"..path, mode) end or io.open

local LEADERBOARD_VERSION = 3
local GHOST_VERSION = 1
local MAXPROFILES = 65536
local MAXALIASES = 256

local OLD_STARTTIME = 6*TICRATE + (3*TICRATE/4) -- starttime for version 1 records

local reloadstore = false

local diffcache, deletecache

local cv_directory = CV_RegisterVar({
	name = "lb_directory",
	flags = CV_NETVAR|CV_CALL|CV_NOINIT,
	defaultvalue = "",
	func = function(cv)
		if replayplayback then return end
		reloadstore = true
		print("Store changed to "..cv.string)
		if consoleplayer and lines[0] then
			print("Restart the map to load the store.")
		end
	end
})

-- two methods of addressing records: IDs and map numbers
-- RecByMap is a cache generated with RecByID
local RecByID, RecByMap

-- name of loaded store
local StoreName

-- next available ID for records
local NextID

-- which records are waiting to be written to the coldstore
local Dirty

-- player profiles
local Profiles

-- dirty player profiles :flushed:
local DirtyProfs

local function makeMapCache(store)
	local mapstore = {}
	for id, record in pairs(store) do
		if not mapstore[record._map] then
			mapstore[record._map] = {}
		end
		if not mapstore[record._map][record._checksum] then
			mapstore[record._map][record._checksum] = {}
		end
		table.insert(mapstore[record._map][record._checksum], record)
	end
	return mapstore
end

local function refreshMapCache()
	if not RecByMap then
		RecByMap = makeMapCache(RecByID)
	end
end

local function recordsForMap(mapname, checksum)
	refreshMapCache()
	return RecByMap[mapname] and RecByMap[mapname][checksum]
end

-- try to replace an existing record in a map
-- return true if record was (maybe?) replaced
local function replaceRecord(score, modeSep)
	local dest = recordsForMap(score._map, score._checksum)
	if dest then
		for _, record in ipairs(dest) do
			if isSameRecord(record, score, modeSep) then
				if lbComp(score, record) then
					-- no dupes when moving, thanks
					if score.id then RecByID[score.id] = nil end

					RecByID[record.id] = score
					score.id = record.id
				end
				return true
			end
		end
	end
	return false
end

local function postfix(filename, str)
	local i = #filename - filename:reverse():find(".", 1, true)
	return filename:sub(1, i)..str..filename:sub(i+1)
end

local function write_segmented(filename, data)
	local fnum = 0
	for i = 1, #data, 1048576 do
		local out = assert(
			open(postfix(filename, "_"..fnum), "wb"),
			"Failed to open file for writing: "..filename
		)
		out:write(data:sub(i, i+1048575))
		out:close()
		fnum = $ + 1
	end
	repeat
		local old = open(postfix(filename, "_"..fnum), "rb")
		if old then
			old:close()
			old = open(postfix(filename, "_"..fnum), "wb")
			old:close()
			fnum = $ + 1
		end
	until not old
end

local function read_segmented(filename)
	local fnum = 0
	local data = {}
	while true do
		local f = open(postfix(filename, "_"..fnum), "rb")
		if not (f and f:read(0)) then
			break
		end
		table.insert(data, f:read("*a"))
		f:close()
		fnum = $ + 1
	end
	data = table.concat($)
	return #data and StringReader(data) or nil
end

local function writeRecord(f, record)
	f:writenum(record.id)
	f:writenum(record.flags)
	f:writenum(record.time)
	f:writenum(record.starttime)
	f:write8(#record.splits)
	for _, v in ipairs(record.splits) do
		f:writenum(v)
	end
	f:write8(#record.players)
	for _, p in ipairs(record.players) do
		f:writepid(p)
		f:writestr(p.skin)
		f:writestr(p.appear)
		f:write8(p.color)
		f:write8(p.stat)
	end
end

local function writeCount(f, table)
	local count = 0
	for _ in pairs(table) do
		count = $ + 1
	end
	f:writenum(count)
end

local function writeMapStore(f, store)
	local mapstore = makeMapCache(store)
	writeCount(f, mapstore)
	for map, checksums in pairs(mapstore) do
		f:writestr(map)
		writeCount(f, checksums)
		for checksum, records in pairs(checksums) do
			f:write16(tonumber(checksum, 16))
			f:writenum(#records)
			for _, record in ipairs(records) do
				writeRecord(f, record)
			end
		end
	end
end

-- why do a gsub function call for every pair of digits when you can make a lookup table?
local hex2char = {}
for i = 0, 255 do
	hex2char[("%02X"):format(i)] = string.char(i)
end

local function writeProfiles(f, profiles, cold)
	writeCount(f, profiles)
	for i, prof in (cold and pairs or ipairs)(profiles) do
		if cold then f:writenum(i) end
		f:write8(#prof.aliases)
		for _, alias in ipairs(prof.aliases) do
			f:writestr(alias)
		end
		f:writestr(prof.publickey:gsub("%x%x", hex2char))
	end
end

local function writeGhost(record, ghosts)
	local f = StringWriter()
	f:writeliteral("GHOST")
	f:write8(GHOST_VERSION)

	f:write8(#ghosts)
	for _, ghost in ipairs(ghosts) do
		f:writenum(ghost.startofs)
		f:writelstr(ghost.data)
	end

	local out = open(string.format("Leaderboard/%s/g%d.sav2", StoreName, record.id), "wb")
	out:write(table.concat(f))
	out:close()
end
rawset(_G, "lb_write_ghost", writeGhost)

local function readGhost(record)
	local f = StringReader(open(string.format("Leaderboard/%s/g%d.sav2", StoreName, record.id), "rb"))
	if not f or f:empty() then return nil end

	if f:readliteral(5) ~= "GHOST" then
		error("Failed to read ghost: bad magic", 2)
	end
	local version = f:read8()
	if version > GHOST_VERSION then
		error(string.format("Failed to read ghost: version %d not supported (highest is %d)", version, GHOST_VERSION), 2)
	end

	local ghosts = {}
	local numplayers = f:read8()
	for i = 1, numplayers do
		local startofs = f:readnum()
		local data = f:readlstr()
		ghosts[i] = ghost_t(data, startofs)
	end

	return ghosts
end
rawset(_G, "lb_read_ghost", readGhost)

-- can't delete a file, so best we can do is truncate it
local function deleteGhost(id)
	local f = open(string.format("Leaderboard/%s/g%d.sav2", StoreName, id), "rb")
	if f then
		f:close()
		f = open(string.format("Leaderboard/%s/g%d.sav2", StoreName, id), "wb")
		f:close()
	end
end
rawset(_G, "lb_delete_ghost", deleteGhost)

local function clearcache()
	diffcache, deletecache = nil, nil
end

-- delete unused profiles and aliases
local function cleanprofiles()
	if not (isserver and RecByID and Profiles) then return end

	-- pass 1: get status of all profiles/aliases
	local seen = {}
	for id, record in pairs(RecByID) do
		for _, p in ipairs(record.players) do
			seen[p.pid] = $ or {}
			seen[p.pid][p.alias] = true
		end
	end

	--[[
	print("SEEN")
	for pid, aliases in pairs(seen) do
		print(("p %d %s"):format(pid, Profiles[pid].publickey:sub(1, 16)))
		for alias in pairs(aliases) do
			print(("a %d %s"):format(alias, Profiles[pid].aliases[alias]))
		end
	end
	--]]

	-- initialize translation table from old to new IDs
	local pidtrans, aliastrans = {}, {}
	local proflen, aliaslen = #Profiles, {}
	for i, prof in ipairs(Profiles) do
		pidtrans[i] = i
		if seen[i] then
			aliastrans[i] = {}
			aliaslen[i] = #prof.aliases
			for j in ipairs(prof.aliases) do
				aliastrans[i][j] = j
			end
		end
	end

	-- pass 2: delete profiles/aliases, and adjust translations
	for i, prof in ipairs(Profiles) do
		if not seen[i] then
			table.remove(Profiles, i)
			DirtyProfs[i] = nil
			for o = i, proflen do
				pidtrans[o] = $ - 1
			end
		else
			local aliases = prof.aliases
			for j in ipairs(aliases) do
				if not seen[i][j] then
					table.remove(aliases, j)
					for o = j, aliaslen[i] do
						aliastrans[i][o] = $ - 1
					end
				end
			end
		end
	end

	--[[
	print("TRANS")
	for old, new in pairs(pidtrans) do
		print(("p %d %d"):format(old, new))
	end

	print("ALIASTRANS")
	for pid, aliases in pairs(aliastrans) do
		for old, new in pairs(aliases) do
			print(("a%d %d %d"):format(pid, old, new))
		end
	end
	--]]

	-- pass 3: translate to new IDs in the store
	for id, record in pairs(RecByID) do
		for _, p in ipairs(record.players) do
			p.alias = aliastrans[p.pid][$]
			p.pid = pidtrans[$]
		end
	end
end

local function writeColdStore(store, profs)
	local f = StringWriter()
	f:writestr(StoreName)
	writeProfiles(f, profs, true)
	writeMapStore(f, store)
	return table.concat(f)
end

local function dumpStoreToFile()
	local f = StringWriter()
	f:writeliteral("LEADERBOARD")
	f:write8(LEADERBOARD_VERSION)

	f:writenum(NextID)

	writeCount(f, Dirty)
	for id in pairs(Dirty) do
		f:writenum(id)
	end

	writeCount(f, DirtyProfs)
	for id in pairs(DirtyProfs) do
		f:write16(id)
	end

	writeProfiles(f, Profiles, false)
	writeMapStore(f, RecByID)

	write_segmented(string.format("Leaderboard/%s/store.sav2", StoreName), table.concat(f))
end

local function recordsIdentical(a, b)
	if --[[a.id ~= b.id or]] a.flags ~= b.flags or a.time ~= b.time or #a.players ~= #b.players then return false end
	for i, s in ipairs(a.splits) do
		if s ~= b.splits[i] then return false end
	end
	for i, p in ipairs(a.players) do
		local bp = b.players[i]
		if p.pid ~= bp.pid or p.alias ~= bp.alias or p.skin ~= bp.skin or p.color ~= bp.color or p.stat ~= bp.stat then return false end
	end
	return true
end

local function mergeStore(other, deletelist, othernext)
	-- check the ids of the other store's records to see if anything moved
	for id = 1, max(NextID, othernext) do
		local my, ot = RecByID[id], other[id]
		if not ot or deletelist[id] then
			-- server doesn't have record anymore
			RecByID[id] = nil
			--print(string.format("delete %d", id))
		elseif not my and ot then
			-- server has a record we don't have
			RecByID[id] = ot
			--print(string.format("add %d %d", ot._map, id))
		elseif my and ot and (not recordsIdentical(my, ot) or my._map ~= ot._map or my._checksum ~= ot._checksum) then
			-- replace our record with the server's, wiping the ghost
			RecByID[id] = ot
			--print(string.format("overwrite %d %d", my._map, id))
		else
			--print(string.format("passthrough %d %d", ot._map, id))
			continue
		end
		-- if we didn't continue, something's changed. wipe the ghosts
		deleteGhost(id)
	end

	Dirty = {} -- you won't be needing this anymore
	RecByMap = nil
	dumpStoreToFile()
end

-- GLOBAL
-- Returns a list of all maps with records
local function MapList()
	local maplist = {}
	refreshMapCache()
	for mapid, checksums in pairs(RecByMap) do
		table.insert(maplist, mapid)
	end
	table.sort(maplist)

	return maplist
end
rawset(_G, "lb_map_list", MapList)

-- GLOBAL
-- Construct the leaderboard table of the supplied mapid
local function GetMapRecords(map, modeSep, checksum)
	local mapRecords = {}
	if not RecByID then return mapRecords end

	local store = recordsForMap(map, checksum or mapChecksum(map))
	if not store then return mapRecords end

	for _, record in ipairs(store) do
		local mode = record.flags & modeSep
		mapRecords[mode] = $ or {}
		table.insert(mapRecords[mode], record)
	end

	-- Sort records
	for _, records in pairs(mapRecords) do
		table.sort(records, lbComp)
	end

	return mapRecords
end
rawset(_G, "lb_get_map_records", GetMapRecords)

-- GLOBAL
-- Save a record to the LiveStore and write to disk
-- SaveRecord will replace the record holders previous record
local function SaveRecord(score, map, modeSep, ghosts)
	if not RecByID then
		-- TODO perhaps a more prominent warning that nothing's being saved
		print("Can't save records, please set a server directory! (lb_directory)")
		return
	end
	score._map = map
	score._checksum = mapChecksum(map)

	if not replaceRecord(score, modeSep) then
		score.id = NextID
		RecByID[NextID] = score
		NextID = $ + 1
	end

	RecByMap = nil -- TODO just cause of one record???

	print("Saving score ("..score.id..")")
	if isserver then
		Dirty[score.id] = true
		if ghosts then
			writeGhost(score, ghosts)
		else
			deleteGhost(score.id)
		end
		dumpStoreToFile()
		clearcache()
	end
end
rawset(_G, "lb_save_record", SaveRecord)

local getProfile = RINGS and function(player)
	for i, prof in ipairs(Profiles) do
		if prof.publickey == player.publickey then
			return i
		end
	end
end or function(player)
	for i, prof in ipairs(Profiles) do
		if prof.aliases[1] == player.name then
			return i
		end
	end
end
rawset(_G, "lb_get_profile", getProfile)

local function getAlias(name, pid)
	for i, alias in ipairs(Profiles[pid].aliases) do
		if alias == name then
			return i
		end
	end
end
rawset(_G, "lb_get_alias", getAlias)

local function newProfile(player)
	local aliases = { player.name }
	local prof = profile_t(aliases, RINGS and player.publickey or "")
	if #Profiles >= MAXPROFILES then
		error("TOO MANY PROFILES!?")
	end
	table.insert(Profiles, prof)
	DirtyProfs[#Profiles] = true
	print("Added new profile "..#Profiles)
	return #Profiles
end
rawset(_G, "lb_new_profile", newProfile)

local newAlias = RINGS and function(name, pid)
	local prof = Profiles[pid]
	if #prof.aliases >= MAXALIASES then
		error("TOO MANY ALIASES!?")
	end
	DirtyProfs[pid] = true
	table.insert(prof.aliases, name)
	print("Added new alias "..name)
	return #prof.aliases
end or function()
	error("Can't make new aliases in Kart!")
end
rawset(_G, "lb_new_alias", newAlias)

local function recordName(p)
	return Profiles[p.pid].aliases[p.alias]
end
rawset(_G, "lb_record_name", recordName)

local function profileKey(p)
	return Profiles[p.pid].publickey
end
rawset(_G, "lb_profile_key", profileKey)

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
	-- thanks windows
	checksum = $:sub(1, 4)

	local fakep = { name = t[2] }
	return score_t(
		flags,
		tonumber(t[5]),	-- Time
		OLD_STARTTIME,
		splits,
		{
			player_t(
				getProfile(fakep) or newProfile(fakep),
				1, -- Name
				t[3], -- Skin
				"",
				tonumber(t[4]), -- Color
				stats
			)
		}
	), tonumber(t[1]), checksum
end
rawset(_G, "lb_parse_score", oldParseScore)

local function parseScoreBinary(f, version)
	local id = f:readnum()
	local flags = f:readnum()
	local time = f:readnum()
	local starttime = OLD_STARTTIME
	if version >= 2 then
		starttime = f:readnum()
	end

	local splits = {}
	local numsplits = f:read8()
	for i = 1, numsplits do
		table.insert(splits, f:readnum())
	end

	local players = {}
	local numplayers = f:read8()
	for i = 1, numplayers do
		local pid, alias
		if version >= 3 then
			pid, alias = f:readpid()
		else
			alias = f:readstr() -- will be converted later
		end
		local skin = f:readstr()
		local appear = ""
		if version >= 2 then
			appear = f:readstr()
		end
		local color = f:read8()
		local stats = f:read8()
		table.insert(players, player_t(pid, alias, skin, appear, color, stat_t(stats >> 4, stats & 0xf)))
	end

	return score_t(
		flags,
		time,
		starttime,
		splits,
		players,
		id
	)
end

local function loadMapStore(f, version)
	local store = {}
	for _ = 1, f:readnum() do
		local mapname = f:readstr()
		local numchecksums = f:readnum()
		for i = 1, numchecksums do
			local checksum = ("%04x"):format(f:read16())
			local numrecords = f:readnum()
			for j = 1, numrecords do
				local score = parseScoreBinary(f, version)
				score._map = mapname
				score._checksum = checksum
				store[score.id] = score
			end
		end
	end
	return store
end

local keyfmt = ("%02X"):rep(32)
local function loadProfiles(f, cold)
	local profs = {}
	for i = 1, f:readnum() do
		if cold then i = f:readnum() end
		local numalias = f:read8()
		local aliases = {}
		for j = 1, numalias do
			aliases[j] = f:readstr()
		end
		local key = f:readstr()
		local publickey = #key and keyfmt:format(key:byte(1, -1)) or ""
		profs[i] = profile_t(aliases, publickey)
	end
	return profs
end

local function loadColdStore(f)
	local directory = f:readstr()
	local profs = loadProfiles(f, true)
	local store = loadMapStore(f, LEADERBOARD_VERSION)

	return store, directory, profs
end

local function getColdStoreDir(f)
	return f:readstr()
end

-- Read and parse a store file
local function loadStoreFile(directory)
	print("Loading store "..directory)
	StoreName = directory
	RecByID = {}
	RecByMap = nil
	Dirty = {}
	NextID = 1
	Profiles = {}
	DirtyProfs = {}

	local f = read_segmented(string.format("Leaderboard/%s/store.sav2", StoreName))
	if not f then
		-- empty store, start a new one
		return
	end

	if f:readliteral(11) ~= "LEADERBOARD" then
		error("Failed to read store: bad magic", 2)
	end
	local version = f:read8()
	if version > LEADERBOARD_VERSION then
		error(string.format("Failed to read store: version %d not supported (highest is %d)", version, LEADERBOARD_VERSION), 2)
	end

	NextID = f:readnum()
	for _ = 1, f:readnum() do
		Dirty[f:readnum()] = true
	end

	if version >= 3 then
		for _ = 1, f:readnum() do
			DirtyProfs[f:read16()] = true
		end
		Profiles = loadProfiles(f, false)
	end

	RecByID = loadMapStore(f, version)

	if version < 3 then -- convert names to profiles?
		for id, record in pairs(RecByID) do
			for _, p in ipairs(record.players) do
				local fakep = { name = p.alias }
				p.pid = getProfile(fakep) or newProfile(fakep)
				p.alias = 1
			end
		end
	end

	cleanprofiles()
	clearcache()
end

local coldloaded

local function AddColdStoreBinary(str)
	if replayplayback then return end
	coldloaded = lb_base128_decode(str)
	-- pre-emptively load the store to reduce join lag
	local dir = getColdStoreDir(StringReader(coldloaded))
	loadStoreFile(dir)
end
rawset(_G, "lb_add_coldstore_binary", AddColdStoreBinary)

local function getRecordByID(id)
	local record = RecByID[id]
	return record, record._map, record._checksum
end
rawset(_G, "lb_rec_by_id", getRecordByID)

local function getIdsForMap(map, checksum)
	local ret = {}
	local store = recordsForMap(map, checksum)
	if store then
		for _, record in ipairs(store) do
			ret[record.id] = true
		end
	end
	return ret
end
rawset(_G, "lb_ids_for_map", getIdsForMap)

-- GLOBAL
-- Command for moving records from one map to another
-- if targetmap is -1, deletes records
local function moveRecords(sourcemap, sourcesum, sourceids, targetmap, targetsum, modeSep)
	local store = recordsForMap(sourcemap, sourcesum)
	if not store then
		return 0
	end

	local delete = targetmap == -1

	local moved = 0
	for _, score in ipairs(store) do
		if not sourceids[score.id] then continue end
		if isserver then Dirty[score.id] = true end
		deleteGhost(score.id)
		if delete then
			RecByID[score.id] = nil
		else
			score._map = targetmap
			score._checksum = targetsum
			if replaceRecord(score, modeSep) then
				-- replaced id should be dirty too
				if isserver then Dirty[score.id] = true end
			end
		end
		moved = $ + 1
	end

	RecByMap = nil

	cleanprofiles()
	if isserver then
		dumpStoreToFile()
		clearcache()
	end

	return moved
end
rawset(_G, "lb_move_records", moveRecords)

-- if we've got a coldstore loaded, apply the server's diff onto it
local function applyDiff(diff, diffprof)
	local coldstore, directory, coldprofs = loadColdStore(StringReader(coldloaded))
	if directory ~= StoreName then
		return diff, coldprofs
	end
	for id, record in pairs(diff) do
		coldstore[id] = record
	end
	for i, prof in pairs(diffprof) do
		if #prof.aliases then
			coldprofs[i] = prof
		end
	end
	return coldstore, coldprofs
end

-- makes a diff to send to clients, and saves it
local function makecache()
	if diffcache and deletecache or not (isserver and RecByID) then
		return
	end

	local send = {}
	local highest = 0
	for id, record in pairs(RecByID) do
		if Dirty[id] then
			send[id] = record
		end
		highest = max($, id)
	end
	-- need this in case the very latest records are deleted
	for i in pairs(Dirty) do
		highest = max($, i)
	end

	local sendprof = {}
	for i, prof in ipairs(Profiles) do
		sendprof[i] = DirtyProfs[i] and prof or nil
	end

	local deleted = StringWriter()
	for i = 1, highest do
		if not send[i] and Dirty[i] then
			deleted:writenum(i)
		end
	end

	diffcache, deletecache = writeColdStore(send, sendprof), table.concat(deleted)
end

-- wait until netvars/mapchange so the savegame has a chance to set cv_directory
-- also in RR, maps are most likely not loaded yet, so we can't get their numbers
local function loadit()
	if reloadstore then
		reloadstore = false
		-- if we already have the right store, don't reload it
		if StoreName ~= cv_directory.string then
			loadStoreFile(cv_directory.string)
		end
	end
	-- might as well make a cache now instead of in netvars
	makecache()
end
addHook("MapChange", function()
	if not replayplayback then loadit() end
end)

local function netvars(net)
	if replayplayback then return end
	if isserver then
		makecache()
		net(diffcache, deletecache, NextID)
	else
		loadit()
		local diff, _, diffprof = loadColdStore(StringReader(net("Yes I would like uhhh")))
		local deleted = StringReader(net("two strings please"))
		local deletions = {}
		while not deleted:empty() do
			deletions[deleted:readnum()] = true
		end
		if coldloaded then
			diff, diffprof = applyDiff($1, $2)
		end
		local nextid = net("oh and a number")
		Profiles = diffprof
		mergeStore(diff, deletions, nextid)
		NextID = nextid
	end
end
addHook("NetVars", netvars)

COM_AddCommand("lb_write_coldstore", function(player, filename)
	if not filename then
		CONS_Printf(player, "Usage: lb_write_coldstore <filename>")
		return
	end

	if filename:sub(#filename-3) != ".txt" then
		filename = $..".txt"
	end

	cleanprofiles()

	local dat = writeColdStore(RecByID, Profiles)
	--[[
	local f = open("coldstore.sav2", "wb")
	f:write(dat)
	f:close()
	--]]

	-- B-B-BUT WHAT ABOUT PLAYER NAMES?
	-- right now we use base128 encoding, which doesn't have ] in its character set so that's not an issue
	-- if base252 ever becomes real we'll have to make it base251 and exclude ]
	write_segmented(filename, "lb_add_coldstore_binary[["..lb_base128_encode(dat).."]]")

	print("Cold store script written to "..filename.." (rename to "..filename:gsub(".txt", ".lua").."!)")
	Dirty = {}
	DirtyProfs = {}
	dumpStoreToFile()
	clearcache()
end, COM_LOCAL)

COM_AddCommand("lb_known_maps", function(player, map)
	local mapname = G_BuildMapName(gamemap)
	if map then
		mapname = ParseMapname(map)
		if not mapname then
			print(("invalid map '%s'"):format(map))
			return
		end
	end

	local known = {}

	refreshMapCache()
	if RecByMap[mapname] then
		for checksum, records in pairs(RecByMap[mapname]) do
			known[checksum] = #records
		end
	end

	print("Map	Chck	Records")
	for checksum, count in pairs(known) do
		print(string.format("%s	%s	%d", mapname, checksum, count))
	end
end, COM_LOCAL)

COM_AddCommand("lb_statistics", function(player)
	local numrecords = 0
	for _ in pairs(RecByID) do
		numrecords = $ + 1
	end
	local prof = getProfile(player) and Profiles[getProfile(player)]
	print(
		("Number of records:  %d\n"):format(numrecords)..
		("Number of profiles: %d/%d\n"):format(#Profiles, MAXPROFILES)..
		("Your aliases:       %d/%d\n"):format(prof and #prof.aliases or 0, MAXALIASES)..
		("Size of diff:       %d bytes"):format(diffcache and #diffcache + #deletecache or 0)
	)
end, COM_LOCAL)

if not RINGS then
COM_AddCommand("lb_convert_to_binary", function(player, filename)
	filename = $ or "leaderboard.coldstore.txt"
	local f = open(filename)
	if not f then
		print("Can't open "..filename)
		return
	end
	print("Converting "..filename.." to binary")
	RecByID = {}
	RecByMap = nil
	Profiles = {}
	NextID = 1
	for l in f:lines() do
		local score, map, checksum = oldParseScore(l)
		score.id = NextID
		score._map = G_BuildMapName(map)
		score._checksum = checksum
		RecByID[NextID] = score
		deleteGhost(NextID)
		NextID = $ + 1
	end
	f:close()
	Dirty = {}
	DirtyProfs = {}

	dumpStoreToFile()
	clearcache()
	print("Conversion succeeded")
end, COM_LOCAL)
end -- if not RINGS
