local DEBUG = false

freeslot("MT_PLAYER_GHOST")

mobjinfo[MT_PLAYER_GHOST] = {
	-1,			 -- doomednum
	S_KART_STND1,	-- spawnstate
	1,			  -- spawnhealth
	S_KART_WALK1,	-- seestate
	sfx_None,	   -- seesound
	0,			  -- reactiontime
	sfx_thok,	   -- attacksound
	S_KART_PAIN,	-- painstate
	MT_THOK,		-- painchance
	sfx_None,	   -- painsound
	S_NULL,		 -- meleestate
	S_NULL,		 -- missilestate
	S_KART_PAIN,	-- deathstate
	S_NULL,		 -- xdeathstate
	sfx_None,	   -- deathsound
	1,			  -- speed
	16*FRACUNIT,	-- radius
	48*FRACUNIT,	-- height
	0,			  -- display offset
	1000,		   -- mass
	MT_THOK,		-- damage
	sfx_None,	   -- activesound
	MF_NOCLIP,	-- flags
	MT_THOK		-- raisestate
}

local nenc = lb_base62_encode
local ndec = lb_base62_decode
local mapChecksum = lb_map_checksum
local Transmitter = lb_transmitter
local Reciever = lb_reciever

local Player

local Client
local Server

local Index
local Ghost
local Ghosts
local Recording

local PREFIX -- Dir
local INDEX = "ghosts" -- Filename

local cv_disable = CV_RegisterVar({
	name = "lb_ghost_disable",
	defaultvalue = "No",
	flags = CV_NETVAR | CV_CALL,
	PossibleValue = CV_YesNo,
	func = function(v)
		Recording = nil
	end
})

local cv_hide = CV_RegisterVar({
	name = "lb_ghost_hide",
	defaultvalue = "No",
	PossibleValue = CV_YesNo,
})

-- Can't be client cvar since we need to access it as server
COM_AddCommand("lb_ghosts_dontsend", function(p, onoff)
	if onoff == nil then
		CONS_Printf(p, "lb_ghosts_dontsend is "..(p.lb_ghosts_dontsend and "\131On" or "\133Off"))
		return
	end
	
	local conv = {
		on = true,
		["1"] = true,
		yes = true,
	}
	
	p.lb_ghosts_dontsend = conv[onoff:lower()]
	
	CONS_Printf(p, "lb_ghosts_dontsend has been turned "..(p.lb_ghosts_dontsend and "\131On" or "\133Off"))
end)

local function Columns(line, sep)
	local t = {}
	sep = sep or " "
	for str in (line..sep):gmatch("(.-)"..sep) do
		table.insert(t, str)
	end
	return {
		index = 0,
		items = t,
		next = function(this)
			this.index = $ + 1
			return this.items[this.index]
		end
	}
end

local function compareTables(a, b, ...)
	for _, key in ipairs({...}) do
		if a[key] != b[key] then
			return false
		end
	end
	return true
end

local function playerNameEscape(name)
	-- Hope that will suffice
	return name:gsub("[/<>:\\|?*\"]", "_")
end

Ghosts = {
	map,
	players = {},
	headers = {},
	data = {},

	dirty = true,

	getData = function(this, player)
		return this.data[player]
	end,

	set = function(this, header, data)
		if not this.headers[header.player] then
			table.insert(this.players, header.player)
		end

		this.data[header.player] = data
		this.headers[header.player] = header
	end,

	iterate = function(this)
		local i = 0
		local m = #this.players
		local player
		return function()
			i = i + 1
			if i <= m then
				player = this.players[i]
				return i, this.headers[player], this.data[player]
			end
		end
	end,

	init = function(this)
		if this.map == gamemap and not this.dirty then return end
		this:reset()

		local headers = Index:getMap(gamemap, mapChecksum(gamemap))
		local ok, data
		for _, header in ipairs(headers) do
			ok, data = pcall(Ghost.read, header, Ghost.tableReader)
			if not ok then
				print(data)
				print("\x85\ERROR:\x80 invalid ghost data, removing entry")
				Index:remove(header)
				Index:write()
				continue
			end
			this:set(header, data)
		end
	end,

	reset = function(this)
		this.players = {}
		this.headers = {}
		this.data = {}
		this.map = gamemap
		this.dirty = false
	end,

	play = function(this)
		for _, header in pairs(this.headers) do
			local ghost = P_SpawnMobj(0, 0, 0, MT_PLAYER_GHOST)
			ghost.playerName = header.player
			ghost.skin = ((skins[header.skin] ~= nil) and header.skin) or "sonic"
			
			if header.color < MAXSKINCOLORS then
				ghost.color = header.color
			end
		end
	end
}

local function GhostTable(header)
	local function frame(this, frameNum)
		return this.frames[frameNum]
	end

	local function append(this, frame)
		table.insert(this.frames, frame)
	end

	-- Calculate the momentum of the last frame
	local function thrust(this, frameNum)
		local a = this:frame(frameNum-1)
		local b = this:frame(frameNum)
		local angle = R_PointToAngle2(a.x, a.y, b.x, b.y)
		local momentum = R_PointToDist2(a.x, a.y, b.x, b.y) / FRACUNIT

		local x = momentum * cos(angle)
		local y = momentum * sin(angle)
		return x, y
	end

	local t = {
		frames = {},
		frame = frame,
		append = append,
		thrust = thrust,
	}

	if header then
		for key, value in pairs(header) do
			t[key] = value
		end
	end

	return t
end

local transProximity = 150
local function calcTrans(mobj)
	local dist = R_PointToDist2(mobj.x, mobj.y, Player.mo.x, Player.mo.y)
	local i = dist / transProximity
	local tr = 9 - min(9, FixedInt(i * 9))
	return tr << FF_TRANSSHIFT
end

CV_RegisterVar({
	name = "lb_ghost_trans_prox",
	defaultvalue = 150,
	flags = CV_CALL,
	PossibleValue = CV_Natural,
	func = function(cv)
		transProximity = cv.value
	end
})

local function ghost_think(mobj)
	if mobj.done then return end
	if leveltime < 1 then return end

	if not Recording then
		P_RemoveMobj(mobj)
		return
	end

	if cv_hide.value == 1 then
		mobj.flags2 = mobj.flags2 | MF2_DONTDRAW
	else
		mobj.flags2 = mobj.flags2 & ~MF2_DONTDRAW
	end

	local ghost = Ghosts:getData(mobj.playerName)
	local frame = ghost:frame(leveltime)
	if frame == nil then
		mobj.done = true
		mobj.state = S_KART_STND1
		mobj.momx, mobj.momy = ghost:thrust(leveltime-1)
		return
	end

	P_MoveOrigin(mobj, frame.x, frame.y, frame.z)
	mobj.angle = frame.angle
	mobj.state = frame.state
	mobj.frame
		= mobj.frame
		& (~FF_TRANSMASK)
		| calcTrans(mobj)

	return true
end
addHook("MobjThinker", ghost_think, MT_PLAYER_GHOST)

local function drawGhostProgress(v)
	local x, y = 0, 0
	local flags = V_SNAPTOTOP | V_SNAPTOLEFT | V_ALLOWLOWERCASE

	local function fmt(rec)
		local stale = rec.tics > (TICRATE * 10) and "(STALE) " or ""
		if not rec.len then return stale.."0%" end
		local n = #rec.packets
		local p = ((n * 100) / rec.len).."%"
		return stale.."Map Ghost "..p
	end

	for _, rec in pairs(Client.data.recievers) do
		v.drawString(x, y, fmt(rec), flags, "small")
		y = y + 5
	end
end

hud.add(function(v)
	if not Recording then return end

	drawGhostProgress(v)

	if cv_hide.value == 1 then return end

	local leveltime = leveltime
	local frame, patch, skin, color
	for i, header, data in Ghosts:iterate() do
		frame = data:frame(leveltime)
		if not frame then continue end

		skin = skins[header.skin] or skins["sonic"]
		patch = v.cachePatch(skin.facemmap)
		color = v.getColormap(skins[header.skin] and header.skin or "sonic", header.color < MAXSKINCOLORS and header.color or SKINCOLOR_WHITE)

		v.drawOnMinimap(frame.x, frame.y, FRACUNIT, patch, color)
	end
end)

if lb_hook then
lb_hook("Finish", function(data)
	if not data.position then
		return
	end

	if data.score.flags & 0x1 then
		Recording = nil
		return
	end

	local score = data.score

	local header = {
		version = 1,
		encoding = "b62",
		player = score.name,
		skin = score.skin,
		color = score.color,
		map = score.map,
		checksum = score.checksum,
		time = score.time,
		flags = score.flags,
	}

    if isserver then
        Ghost.write(header, Ghost.tableWriter(Recording))
        Index:insert(header)
        Index:write()
        Ghosts.dirty = true
    end
    
    Recording = nil
end)
end

--COM_AddCommand("save_ghost", function(player)
--	if not Recording then return end
--
--	print("Saving Ghost")
--
--	local header = {
--		version = 1,
--		encoding = "b62",
--		player = player.name,
--		skin = player.mo.skin,
--		color = player.skincolor,
--		map = gamemap,
--		checksum = mapChecksum(gamemap),
--		time = leveltime,
--		flags = 0,
--	}
--
--	Ghost.write(header, Ghost.tableWriter(Recording))
--	Index:insert(header)
--	Index:write()
--
--	Recording = nil
--end)

local function singlePlayer()
	local player
	for p in players.iterate do
		if p.valid and not p.spectator then
			if player then
				return nil
			end
			player = p
		end
	end

	return player
end

addHook("ThinkFrame", function()
	if not Recording then return end

	Player = singlePlayer()
	local p = Player
	if not p then
		Server:stop()
		Client:stop()
		Recording = nil
		return
	end

	local frame = {
		x = p.mo.x,
		y = p.mo.y,
		z = p.mo.z,
		angle = p.frameangle,
		state = p.mo.state
	}

	Recording:append(frame)
end)

Server = {
	header = {
		transmitter,
		send = function(this)
			if this.transmitter
			or #Server.command.transmitters
			then
				return
			end

			this.transmitter = Transmitter("GM", {free = this.free, handle = this})
			local mapindex = Index:getMap(gamemap, mapChecksum(gamemap))

			local s = ""
			for _, header in ipairs(mapindex) do
				s = s..Index.headerFmt(header)
			end

			this.transmitter:transmit(s)
		end,

		free = function(tr, this)
			this.transmitter = nil
		end,

		stop = function(this)
			if this.transmitter then
				this.transmitter:close()
			end
		end
	},

	command = {
		reciever,
		listen = function(this)
			if this.reciever then return end
			this.reciever = Reciever("GC", this.callback, {stream = true, handle = this})
			this.reciever:listen()
		end,

		transmitters = {},
		callback = function(cmd, handle)
			if handle.transmitters[cmd] then
				return
			end

			local mapindex = Index:getMap(gamemap, mapChecksum(gamemap))
			local header = assert(mapindex[tonumber(cmd)])
			local data = Ghost.read(header, Ghost.stringReader)

			local tr = Transmitter(
				"GC"..cmd,
				{
					free = handle.free,
					handle = {
						this = handle,
						cmd = cmd
					}
				}
			)
			handle.transmitters[cmd] = tr
			tr:transmit(data)
		end,

		free = function(tr, handle)
			handle.this.transmitters[handle.cmd] = nil
		end,

		stop = function(this)
			for _, tr in pairs(this.transmitters) do
				tr:close()
			end
		end
	},

	stop = function(this)
		this.header:stop()
		this.command:stop()
	end
}

Client = {
	header = {
		reciever,
		listen = function(this)
			if this.reciever then return end
			this.reciever = Reciever(
				"GM",
				this.callback,
				{
					free = this.free,
					handle = this
				}
			)
			this.reciever:listen()
		end,

		callback = function(data, this)
			local header, storedHeader
			local cmd = 1
			for str in data:gmatch("(.-)\n") do
				if Client.data:busy(cmd) then
					continue
				end

				header = Index.parseHeader(str)
				storedHeader = Index:find(header)
				if not (
					storedHeader
					and compareTables(
						header,
						storedHeader,
						"time",
						"flags",
						"skin",
						"color"
					)
				) then
					local tr = Transmitter("GC", {stream = true})
					tr:transmit(cmd)
					Client.data:listen(header, cmd)
				end
				cmd = $ + 1
			end
		end,

		free = function(rc, handle)
			handle.reciever = nil
		end,

		stop = function(this)
			if this.reciever then
				this.reciever:close()
			end
		end
	},

	data = {
		recievers = {},
		listen = function(this, header, cmd)
			local rc = Reciever(
				"GC"..cmd,
				this.callback,
				{
					free = this.free,
					handle = {
						this = this,
						header = header,
						cmd = cmd
					},
				}
			)

			this.recievers[cmd] = rc
			rc:listen()
		end,

		callback = function(data, handle)
			Ghost.write(handle.header, Ghost.stringWriter(data))
			Index:insert(handle.header)
			Index:write()

			Ghosts.dirty = true
		end,

		free = function(rc, handle)
			handle.this.recievers[handle.cmd] = nil
		end,

		busy = function(this, cmd)
			for com in pairs(this.recievers) do
				if com == cmd then return true end
			end
		end,

		stop = function(this)
			for _, rec in pairs(this.recievers) do
				rec:close()
			end
		end
	},

	stop = function(this)
		this.header:stop()
		this.data:stop()
	end
}

addHook("MapLoad", function(num)
	local singleplayer = singlePlayer()

	if cv_disable.value
        or not singleplayer
        or not LB_IsRunning()
	then
		Recording = nil
		return
	end

	Recording = GhostTable()
	
	-- Don't send ghosts if ta'ing client doesn't want us to
	-- (prevents spectators from downloading ghosts too but can't do much about it)
	if singleplayer.lb_ghosts_dontsend then return end

	if netgame and isserver then
		Server.header:send()
		Server.command:listen()

		if isdedicatedserver then return end
	end

	Ghosts:init()
    
    if netgame then
        Client.header:listen()
	end
    
    Ghosts:play()
end)

local function open(filename, mode, fn)
	local f, err = io.open(filename, mode)
	if err then
		return nil, err
	end

	local ok, err = pcall(fn, f)
	f:close()

	if not ok then
		err = string.format("%s\n(\x82%s\x80 (%s))", err, filename, mode)
	end

	return ok, err
end

Index = {
	headers,

	insert = function(this, header)
		local map = this:getMap(header.map, header.checksum)
		for i, h in ipairs(map) do
			if h.player == header.player then
				map[i] = header
				this:setMap(header.map, header.checksum, map)
				return
			end
		end

		table.insert(map, header)
		this:setMap(header.map, header.checksum, map)
	end,

	remove = function(this, header)
		local map = this:getMap(header.map, header.checksum)
		for i, h in ipairs(map) do
			if h.player == header.player then
				map[i] = nil
				this:setMap(header.map, header.checksum, map)
				return
			end
		end
	end,

	find = function(this, header)
		local index = this:getMap(header.map, header.checksum)
		for i, h in ipairs(index) do
			if h.player == header.player then
				return h
			end
		end
	end,

	join = function(sep, ...)
		local t = {...}
		local ret = ""..t[1]
		local v
		for i = 2, #t do
			v = t[i]
			ret = $..sep..(v ~= nil and v or "")
		end
		return ret
	end,

	headerFmt = function(h)
		return Index.join(
			"\t",
			h.version,
			h.encoding,
			h.map,
			h.checksum,
			h.player,
			h.time,
			h.flags or "0",
			h.skin,
			h.color or "0"
		).."\n"
	end,

	parseHeader = function(line)
		local c = Columns(line, "\t")
		return {
			version = c:next(),
			encoding = c:next(),
			map = c:next(),
			checksum = c:next(),
			player = c:next(),
			time = tonumber(c:next()),
			flags = tonumber(c:next()),
			skin = c:next(),
			color = tonumber(c:next())
		}
	end,

	filename = function(prefix, filename)
		return string.format(
			"%s/%s.txt",
			prefix,
			filename
		)
	end,

	write = function(this)
		local filename = this.filename(PREFIX, INDEX)
		assert(open(filename, "w", function(f)
			for _, map in pairs(this.headers) do
				for _, header in ipairs(map) do
					f:write(this.headerFmt(header))
				end
			end
		end))
	end,

	read = function(this)
		local filename = this.filename(PREFIX, INDEX)
		this.headers = {}
		assert(open(filename, "r", function(f)
			for line in f:lines() do
				this:insert(
					this.parseHeader(line)
				)
			end
		end))
	end,

	getMap = function(this, map, checksum)
		if not this.headers then
			this:read()
		end

		return this.headers[map..checksum] or {}
	end,

	setMap = function(this, map, checksum, entry)
		assert(this.headers, "Index: header unread")
		this.headers[map..checksum] = entry
	end
}

Ghost = {
	stringReader = function(f)
		return f:read("*a")
	end,

	tableReader = function(f)
		local data = GhostTable(header)
		local c
		f:read() -- skip first frame
		for line in f:lines() do
			c = Columns(line)
			data:append({
				state = ndec(c:next()),
				angle = ndec(c:next()),
				x = ndec(c:next()),
				y = ndec(c:next()),
				z = ndec(c:next()),
			})
		end
		return data
	end,

	filename = function(prefix, header)
		return string.format(
			"%s/%d_%s_%s.txt",
			prefix,
			header.map,
			header.checksum,
			playerNameEscape(header.player)
		)
	end,

	read = function(header, reader)
		local filename = Ghost.filename(PREFIX, header)
		local data
		assert(open(filename, "r", function(f)
			data = reader(f)
		end))

		return data
	end,

	stringWriter = function(dataStr)
		return function(f)
			f:setvbuf("full")
			f:write(dataStr)
		end
	end,

	frameFmt = function(frame)
		return string.format(
			"%s %s %s %s %s\n",
			nenc(frame.state),
			nenc(frame.angle),
			nenc(frame.x),
			nenc(frame.y),
			nenc(frame.z)
		)
	end,

	tableWriter = function(data)
		return function(f)
			f:setvbuf("line")
			for _, frame in ipairs(data.frames) do
				f:write(Ghost.frameFmt(frame))
			end
		end
	end,

	write = function(header, writer)
		local filename = Ghost.filename(PREFIX, header)
		assert(open(filename, "w", writer))
	end,
}

local cv_prefix = CV_RegisterVar({
	name = "lb_ghost_dir",
	defaultvalue = "ghosts",
	flags = CV_CALL | CV_NETVAR,
	func = function(cv)
		PREFIX = cv.string
		if DEBUG and not isserver then
			PREFIX = $.."_client"
		end
		Index.headers = nil
	end
})
