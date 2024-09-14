-- what characters can we use in command arguments?
-- any 8-bit character except \0, \r, \n, "
-- so.. base 252!
-- actually i'm too stupid for base 252 so i'm going with base 128
-- it's less compact, but i'm not in the mood for bigint math
-- plus it helps to know how long the output will be so you can control the netxcmd bandwidth used

---- Imported functions ----

-- lb_common.lua
local StringReader = lb_string_reader
local StringWriter = lb_string_writer
local djb2 = lb_djb2

-- lb_store.lua
local ReadGhost = lb_read_ghost

----------------------------

local RINGS = VERSION == 2
local V_ALLOWLOWERCASE = V_ALLOWLOWERCASE or 0

local tohex = {}
for i = 0, 255 do
	tohex[string.char(i)] = string.format("%02x_", i)
end

local tins = table.insert
local function base128encode(str)
	local out = {}
	local rest, bits = 0, 0
	for i = 1, #str do
		rest = $ | (str:byte(i) << bits)
		bits = $ + 8
		while bits >= 7 do
			tins(out, string.char(rest & 0x7f | 0x80))
			rest = $ >> 7
			bits = $ - 7
		end
	end
	tins(out, string.char(rest & 0x7f | 0x80))
	return table.concat(out)
end
rawset(_G, "lb_base128_encode", base128encode)

local function base128decode(str)
	local out = {}
	local rest, bits = 0, 0
	for i = 1, #str do
		rest = $ | ((str:byte(i) & 0x7f) << bits)
		bits = $ + 7
		while bits >= 8 do
			tins(out, string.char(rest & 0xff))
			rest = $ >> 8
			bits = $ - 8
		end
	end
	return table.concat(out)
end
rawset(_G, "lb_base128_decode", base128decode)

-- returns the length of a string if it were encoded
local function base128expand(num)
	return 8*num/7 + 1
end

-- returns the length of a string if it were decoded
local function base128shrink(num)
	return 7*num/8
end

-------------------------

local myconnections = {}
local totalconnections = 0
local fmt = string.format
local timeout = {}

local function me()
	if isdedicatedserver then
		return server
	else
		return consoleplayer
	end
end

local sendPacket

local ghostqueue = {} -- if server, the ghosts you are going to send

local cv_debug = CV_RegisterVar({
	name = "lb_comms_debug",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff
})
local function debug(...)
	if cv_debug.value then print(...) end
end

local packets = {
	{
		-- FIXME: this is pointless, just one client sending this is enough
		-- get rid of this or actually handle dropped packets
		-- plus the timeout tends to bug out if the server never gets this
		name = "recvfinish",
		func = function(p, channel, data)
			if not isserver then return end
			for _, tx in ipairs(myconnections) do
				if tx.channel == channel then
					if tx.callback then tx.callback(true) end
					tx.state = false
					return
				end
			end
		end,
	},
	{
		name = "send",
		func = function(p, channel, data)
			if p ~= server then
				print("data from non server")
				return
			end
			if isserver then return end
			for _, rx in ipairs(myconnections) do
				if rx.channel == channel and rx.state == "receiving" then
					rx.data = $..data
					timeout[p] = 0
					if #rx.data == rx.finallength then
						rx.state = false
						sendPacket("recvfinish", channel, "")
						if rx.ghost_checksum ~= nil and abs(djb2(rx.data)) ~= rx.ghost_checksum then
							print("Checksum FAILED! Oh dear... better check server logs")
							if rx.callback then
								rx.callback(false)
							end
						elseif rx.callback then
							rx.callback(true, rx.data)
						end
					end
					return
				end
			end
		end,
	},
	{
		name = "filesend",
		func = function(p, channel, data)
			if not RINGS then
				print("filesend on kart? no way!")
				return
			end
			if p ~= server then
				print("filesend from non server")
				return
			end
			if isserver then return end
			for _, rx in ipairs(myconnections) do
				if rx.channel == channel and rx.state == "receiving" then
					io.open("the filename here doesn't matter.sav2", "rb", function(file, name)
						local data = file:read("*a")
						rx.data = $..data
						timeout[p] = 0
						if #rx.data == rx.finallength then
							rx.state = false
							sendPacket("recvfinish", channel, "")
							if rx.callback then
								rx.callback(true, rx.data)
							end
						end
					end)
					return
				end
			end
			debug("ignoring filesend")
			io.open("not for us, but we still need to open it.sav2", "rb", do end)
		end,
	},
	{
		name = "getghosts",
		func = function(p, channel, data)
			if not isserver then return end

			local recordid = tonumber(data)
			if not recordid then
				print("Corrupted ghost request from "..p.name)
				return
			end
			print(p.name.." requesting ghost for "..recordid)

			if ghostqueue[recordid] then
				debug("already waiting")
				return
			end

			local maprecords = lb_get_map_records(gamemap, -1)
			local ghostdata = StringWriter()
			for mode, records in pairs(maprecords) do
				for _, record in ipairs(records) do
					if record.id == recordid then
						-- gotcha!
						local ghosts = ReadGhost(record)
						if not ghosts then
							debug("no ghosts saved")
							return
						end
						for i, ghost in ipairs(ghosts) do
							ghostdata:write8(i)
							ghostdata:writenum(ghost.startofs)
							ghostdata:writelstr(ghost.data)
						end
					end
				end
			end
			if not #ghostdata then debug("no data"); return end
			ghostdata = table.concat($)

			local tx = {
				data = ghostdata,
				state = "sending",
				channel = totalconnections,
				finallength = #ghostdata,
				who = me(),
				callback = function(ok)
					debug(fmt("transfer finished for %d, result %s", recordid, tostring(ok)))
					ghostqueue[recordid] = false
				end
			}
			totalconnections = ($ + 1) % 256
			table.insert(myconnections, tx)

			local header = StringWriter()
			header:writenum(recordid)
			header:writenum(#ghostdata)
			header:writenum(tx.channel) -- new channel for clients
			header:writenum(abs(djb2(ghostdata))) -- checksum. why? well kart itself isn't gonna corrupt the data,
			                                      -- but this spaghetti monster might... had an incident on day 1
			                                      -- where i received a ghost with 1.5 packets worth of data?????
			sendPacket("ghostack", channel, table.concat(header))

			ghostqueue[recordid] = true
			debug(fmt("starting ghost %d on channel %d", recordid, tx.channel))
		end,
	},
	{
		name = "ghostack",
		func = function(p, channel, data)
			if p ~= server then
				print("ghostack from non server")
				return
			end
			if isserver then return end

			data = StringReader($)
			local recordid = data:readnum()
			local ghostlen = data:readnum()
			local newchannel = data:readnum() -- server decides the channel
			local checksum = data:readnum()
			for _, rx in ipairs(myconnections) do
				if rx.ghost_recid == recordid and rx.state == "starting" then
					debug("look! it's "..recordid)
					rx.state = "receiving"
					rx.channel = newchannel
					rx.finallength = ghostlen
					rx.ghost_checksum = checksum
					timeout[server] = 0
					debug("switching to channel "..newchannel)
					return
				end
			end
			debug("i don't need "..recordid)
		end,
	},
}

function sendPacket(type, channel, data)
	local ptype
	for k, v in pairs(packets) do
		if v.name == type then
			ptype = k
			break
		end
	end
	--print(fmt("sending %s channel %d", type, channel))
	COM_BufAddText(me(), fmt('\x7f "%s"', base128encode(string.char(ptype, channel)..data)))
end

COM_AddCommand("\x7f", function(p, data)
	data = base128decode($)
	local ptype, channel = data:byte(1, 2)
	if not packets[ptype] then
		print("unknown packet type "..tostring(ptype))
		return
	end
	if p ~= me() then
		--print(fmt("received %s from %s channel %d", k, p.name, channel))
	end
	packets[ptype].func(p, channel, data:sub(3))
end)

local function startTransfer(data, ptype, callback)
	local tx = {
		data = data,
		state = "starting",
		channel = totalconnections,
		callback = callback,
		who = server,
	}
	totalconnections = ($ + 1) % 256
	table.insert(myconnections, tx)
	timeout[server] = 0

	sendPacket(ptype, tx.channel, fmt("%d", #data))
end

local function startReceiver(data, ptype, callback)
	local rx = {
		data = "",
		state = "starting",
		channel = totalconnections,
		callback = callback,
		who = server,
	}
	totalconnections = ($ + 1) % 256
	table.insert(myconnections, rx)
	timeout[server] = 0

	sendPacket(ptype, rx.channel, data)
	return rx
end

local cv_bandwidth = CV_RegisterVar({
	name = "lb_comms_bandwidth",
	defaultvalue = 192,
	possiblevalue = { MIN = 16, MAX = 247 }
})

local cv_timeout = CV_RegisterVar({
	name = "lb_comms_timeout",
	defaultvalue = TICRATE/2,
	possiblevalue = { MIN = TICRATE/4, MAX = TICRATE*5 }
})

local cv_filetransfer
if RINGS then
	cv_filetransfer = CV_RegisterVar({
		name = "lb_comms_filetransfer",
		defaultvalue = "On",
		possiblevalue = CV_OnOff
	})
end

local filesending = false
local function transferThinker()
	local sent = false

	for p in pairs(timeout) do
		timeout[p] = ($ or 0) + 1
		-- need extra time after map changes, it takes longer for requests to reach the server
		if timeout[p] > cv_timeout.value + max(TICRATE - leveltime, 0) then
			timeout[p] = nil
			for _, rx in ipairs(myconnections) do
				if rx.who == p then
					print("timed out")
					if rx.callback then rx.callback(false) end
					rx.state = false
				end
			end
		end
	end

	for _, tx in ipairs(myconnections) do
		if not tx.state then continue end

		if tx.state == "sending" then
			-- send a slice
			if sent then
			elseif #tx.data then
				if cv_filetransfer and cv_filetransfer.value then
					if filesending then continue end
					local f = io.openlocal("commstmp.sav2", "wb")
					f:write(tx.data)
					f:close()
					tx.state = false
					debug("FILE SEND GO")
					io.open("commstmp.sav2", "rb", function()
						filesending = false
						tx.callback()
					end)
					sendPacket("filesend", tx.channel, "")
					filesending = true
				else
					local bw = base128shrink(cv_bandwidth.value)
					local chunk = tx.data:sub(1, bw)
					tx.data = tx.data:sub(bw+1)
					sendPacket("send", tx.channel, chunk)
					timeout[tx.who] = 0
					sent = true
				end
			else
				tx.state = "recvack"
			end
		end
	end

	for i = #myconnections, 1, -1 do
		if not myconnections[i].state then
			table.remove(myconnections, i)
		end
	end
end

addHook("ThinkFrame", transferThinker)

local function RequestGhosts(id, callback)
	for _, rx in ipairs(myconnections) do
		if rx.ghost_recid == id then
			debug("Already asked for "..id)
			return
		end
	end
	debug("Requesting ghost "..id)
	local rec = startReceiver(tostring(id), "getghosts", callback)
	rec.ghost_recid = id
end
rawset(_G, "lb_request_ghosts", RequestGhosts)

hud.add(function(v, p)
	for i, tx in ipairs(myconnections) do
		local str = fmt("%s: ", tostring(tx.state))
		if tx.finallength then
			str = str..fmt("%d%%", (#tx.data*100)/tx.finallength)
		else
			str = str..fmt("%d", #tx.data)
		end
		v.drawString(0, 200-i*4, str, V_SNAPTOBOTTOM|V_SNAPTOLEFT|V_ALLOWLOWERCASE|V_50TRANS, "small")
		break
	end
end)
