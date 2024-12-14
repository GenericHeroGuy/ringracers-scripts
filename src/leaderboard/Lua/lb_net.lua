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

-- lb_store.lua
local GetMapRecords = lb_get_map_records
local ReadGhost = lb_read_ghost

----------------------------

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

local cv_log = CV_RegisterVar({
	name = "lb_net_log",
	defaultvalue = "Info",
	possiblevalue = { None = 0, Warn = 1, Info = 2, Verbose = 3, Debug = 4 }
})

local cv_bandwidth = CV_RegisterVar({
	name = "lb_net_bandwidth",
	defaultvalue = 192,
	possiblevalue = { MIN = 16, MAX = 247 }
})

local cv_timeout = CV_RegisterVar({
	name = "lb_net_timeout",
	defaultvalue = TICRATE,
	possiblevalue = { MIN = TICRATE/4, MAX = TICRATE*3 }
})

local cv_droptest = CV_RegisterVar({
	name = "lb_net_droptest",
	defaultvalue = 0,
	possiblevalue = CV_Unsigned
})

local cv_filetransfer = VERSION == 2 and CV_RegisterVar({
	name = "lb_net_filetransfer",
	defaultvalue = "On",
	possiblevalue = CV_OnOff
})

local function warn(s, ...)
	if cv_log.value > 0 then print(("\x82[%d] "..s):format(leveltime, ...)) end
end
local function info(s, ...)
	if cv_log.value > 1 then print(("[%d] "..s):format(leveltime, ...)) end
end
local function verbose(s, ...)
	if cv_log.value > 2 then print(("\x86[%d] "..s):format(leveltime, ...)) end
end
local function debug(s, ...)
	if cv_log.value > 3 then print(("\x83[%d] "..s):format(leveltime, ...)) end
end

local myconnections = {}
local totalconnections = 0
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

local packets = {
	{
		name = "send",
		func = function(p, channel, data)
			if p ~= server then
				warn("data from non server")
				return
			end
			if isserver then return end
			for _, rx in ipairs(myconnections) do
				if rx.channel ~= channel or rx.state ~= "receiving" then continue end

				local lo, hi = data:byte(1, 2)
				local pakid = lo | (hi << 8)
				data = $:sub(3)
				debug("pakid = %d", pakid)
				if rx.data[pakid] then
					verbose("Channel %d: Already have packet %d", channel, i)
					return
				end
				rx.data[pakid] = data
				rx.bytecount = $ + #data
				local miss = StringWriter()
				miss:write16(pakid)
				for i = max(1, rx.previd), pakid do
					if not rx.data[i] then
						verbose("Channel %d: Dropped packet %d", channel, i)
						miss:write16(i)
					end
				end
				sendPacket("ack", channel, table.concat(miss))
				rx.previd = pakid
				timeout[p] = 0
				if rx.bytecount == rx.finallength then
					rx.state = false
					if rx.callback then
						rx.callback(true, table.concat(rx.data))
					end
				end
				return
			end
		end,
	},
	{
		name = "filesend",
		func = function(p, channel, data)
			if not cv_filetransfer then
				warn("filesend on kart? no way!")
				return
			end
			if p ~= server then
				warn("filesend from non server")
				return
			end
			if isserver then return end
			for _, rx in ipairs(myconnections) do
				if rx.channel ~= channel or rx.state ~= "receiving" then continue end

				io.open("the filename here doesn't matter.sav2", "rb", function(file, name)
					local data = file:read("*a")
					table.insert(rx.data, data)
					rx.bytecount = $ + #data
					timeout[p] = 0
					if rx.bytecount == rx.finallength then
						rx.state = false
						if rx.callback then
							rx.callback(true, table.concat(rx.data))
						end
					end
				end)
				return
			end
			verbose("ignoring filesend")
			io.open("not for us, but we still need to open it.sav2", "rb", do end)
		end,
	},
	{
		name = "ack",
		func = function(p, channel, data)
			if not isserver then return end

			local ids = StringReader(data)
			local highest = ids:read16()
			local misses = {}
			while not ids:empty() do
				table.insert(misses, ids:read16())
			end
			if #misses then
				verbose("%s dropped packets on channel %d: %s", p.name, channel, table.concat(misses, " "))
			end
			for _, tx in ipairs(myconnections) do
				if tx.channel ~= channel or tx.state ~= "sending" then continue end
				debug("highest = %d/%d", highest, #tx.chunks)
				tx.highest[p] = max($ or 0, highest)
				for _, id in ipairs(misses) do
					table.insert(tx.pakqueue, id)
				end
				return
			end
			debug("highest = %d/?", highest)
			if #misses then verbose("But channel %d is not active!?", channel) end
		end,
	},
	{
		name = "getghosts",
		func = function(p, channel, data)
			if not isserver then return end

			local recordid = tonumber(data)
			if not recordid then
				warn("Corrupted ghost request from %s", p.name)
				return
			end
			info("%s requested ghost %d", p.name, recordid)

			if ghostqueue[recordid] then
				verbose("already sending")
				return
			end

			local maprecords = GetMapRecords(gamemap, -1)
			local ghostdata = StringWriter()
			for mode, records in pairs(maprecords) do
				for _, record in ipairs(records) do
					if record.id ~= recordid then continue end

					-- gotcha!
					local ghosts = ReadGhost(record)
					if not ghosts then
						verbose("no ghosts saved")
						return
					end
					for i, ghost in ipairs(ghosts) do
						ghostdata:write8(i)
						ghostdata:writenum(ghost.startofs)
						ghostdata:writelstr(ghost.data)
					end
				end
			end
			if not #ghostdata then verbose("no data"); return end
			ghostdata = table.concat($)

			local chunks = {}
			local pakqueue = {}
			local bw = base128shrink(cv_bandwidth.value)
			for i = 1, #ghostdata, bw do
				table.insert(chunks, ghostdata:sub(i, i+bw-1))
				table.insert(pakqueue, #chunks)
			end

			local tx = {
				state = "sending",
				channel = totalconnections,
				finallength = #ghostdata,
				who = me(),
				chunks = chunks,
				pakqueue = pakqueue,
				highest = {},
				checktimer = 0,
				checkattempts = 3,
				callback = function(ok) ghostqueue[recordid] = nil end
			}
			totalconnections = ($ + 1) % 256
			table.insert(myconnections, tx)

			local header = StringWriter()
			header:writenum(recordid)
			header:writenum(#ghostdata)
			header:writenum(tx.channel) -- new channel for clients
			header:writenum(#chunks)
			sendPacket("ghostack", channel, table.concat(header))

			ghostqueue[recordid] = true
			verbose("Starting ghost %d on channel %d", recordid, tx.channel)
		end,
	},
	{
		name = "ghostack",
		func = function(p, channel, data)
			if p ~= server then
				warn("ghostack from non server")
				return
			end
			if isserver then return end

			data = StringReader($)
			local recordid = data:readnum()
			local ghostlen = data:readnum()
			local newchannel = data:readnum() -- server decides the channel
			local lastpak = data:readnum()
			for _, rx in ipairs(myconnections) do
				if rx.ghost_recid ~= recordid or rx.state ~= "starting" then continue end

				rx.state = "receiving"
				rx.channel = newchannel
				rx.finallength = ghostlen
				rx.lastpak = lastpak
				timeout[server] = 0
				verbose("Starting download for ghost %d on channel %d", recordid, newchannel)
				return
			end
			verbose("I didn't ask for ghost %d!", recordid)
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
	local send = base128encode(string.char(ptype, channel)..data)
	debug("sending %s channel %d size %d/%d", type, channel, #data, #send)
	COM_BufAddText(me(), ('\x7f "%s"'):format(send))
end

COM_AddCommand("\x7f", function(p, data)
	data = base128decode($)
	local ptype, channel = data:byte(1, 2)
	if not packets[ptype] then
		warn("Unknown packet type %s from %s channel %d", tostring(ptype), p.name, channel)
		return
	end
	if p ~= me() then
		debug("received %s from %s channel %d size %d", packets[ptype].name, p.name, channel, #data)
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

	sendPacket(ptype, tx.channel, tostring(#data))
end

local function startReceiver(data, ptype, callback)
	local rx = {
		data = {},
		state = "starting",
		channel = totalconnections,
		callback = callback,
		who = server,
		bytecount = 0,
		previd = 1,
	}
	totalconnections = ($ + 1) % 256
	table.insert(myconnections, rx)
	timeout[server] = 0

	sendPacket(ptype, rx.channel, data)
	return rx
end

local filesending = false
local function transferThinker()
	for p in pairs(timeout) do
		timeout[p] = ($ or 0) + 1
		-- need extra time after map changes, it takes longer for requests to reach the server
		if timeout[p] > cv_timeout.value + max(TICRATE*3 - leveltime, 0) then
			timeout[p] = nil
			for _, rx in ipairs(myconnections) do
				if not rx.state or rx.who ~= p then continue end

				if rx.pakqueue and not #rx.pakqueue then
					verbose("Closing channel %d", rx.channel)
					if rx.callback then rx.callback(true) end
				else
					warn("Timed out on channel %d", rx.channel)
					if rx.callback then rx.callback(false) end
				end
				rx.state = false
			end
		end
	end

	-- an... attempt at solving the two generals problem
	-- if the highest received pakid is below the total, resend some packets
	for _, tx in ipairs(myconnections) do
		if tx.state ~= "sending" or not (tx.checktimer and tx.checkattempts) then continue end

		tx.checktimer = $ - 1
		if not tx.checktimer then
			-- time's up!
			local resend = INT32_MAX
			for p, max in pairs(tx.highest) do
				if max < #tx.chunks then
					resend = min($, max+1)
				end
			end
			if resend == INT32_MAX then continue end
			tx.checkattempts = $ - 1
			verbose("Channel %d: resending from %d/%d (%d tries left)", tx.channel, resend, #tx.chunks, tx.checkattempts)
			for i = resend, #tx.chunks do
				table.insert(tx.pakqueue, i)
			end
		end
	end

	-- run all senders
	for _, tx in ipairs(myconnections) do
		if tx.state == "sending" and #tx.pakqueue then
			if cv_filetransfer and cv_filetransfer.value then
				if filesending then continue end
				local f = io.openlocal("commstmp.sav2", "wb")
				f:write(table.concat(tx.chunks))
				f:close()
				tx.state = false
				verbose("FILE SEND GO")
				io.open("commstmp.sav2", "rb", function()
					filesending = false
					tx.callback()
				end)
				sendPacket("filesend", tx.channel, "")
				filesending = true
			else
				local dat = StringWriter()
				local pakid = table.remove(tx.pakqueue, 1)
				dat:write16(pakid)
				dat:writeliteral(tx.chunks[pakid])
				if cv_droptest.value and not (leveltime % cv_droptest.value) then continue end
				sendPacket("send", tx.channel, table.concat(dat))
				timeout[tx.who] = 0
				if not #tx.pakqueue then
					verbose("Channel %d finished", tx.channel)
					tx.checktimer = 3*cv_timeout.value/4
				end
			end
			-- one per tic, please!
			return
		end
	end

	-- clear all connections, but only when ALL transfers are done
	-- so the HUD can show the total
	local clear = true
	for i = #myconnections, 1, -1 do
		if myconnections[i].state then
			clear = false
			break
		end
	end
	if clear then myconnections = {} end
end

addHook("ThinkFrame", transferThinker)
addHook("IntermissionThinker", transferThinker)
addHook("VoteThinker", transferThinker)

local function RequestGhosts(id, callback)
	for _, rx in ipairs(myconnections) do
		if rx.ghost_recid == id then
			verbose("Already asked for %d", id)
			return
		end
	end
	info("Requesting ghost %d", id)
	local rec = startReceiver(tostring(id), "getghosts", function(ok, data)
		if ok then
			info("Got ghost %d", id)
		else
			info("Failed to download ghost %d", id)
		end
		callback(ok, data)
	end)
	rec.ghost_recid = id
end
rawset(_G, "lb_request_ghosts", RequestGhosts)

local V_ALLOWLOWERCASE = V_ALLOWLOWERCASE or 0
local function drawTransfers(v)
	for i, tx in ipairs(myconnections) do
		if not tx.state then continue end
		local str = ("[%d/%d] %s: "):format(i, #myconnections, tx.state)

		if tx.finallength and tx.state == "receiving" then
			str = $..("%s%%"):format(100*tx.bytecount/tx.finallength)
		elseif tx.state == "sending" then
			if not #tx.pakqueue then continue end
			str = $..("%s%%"):format(100*(tx.pakqueue[1] or #tx.chunks)/#tx.chunks)
		end

		v.drawString(0, 196, str, V_SNAPTOBOTTOM|V_SNAPTOLEFT|V_ALLOWLOWERCASE|V_40TRANS, "small")
		break
	end
end

hud.add(drawTransfers, "game")
hud.add(drawTransfers, "scores")
pcall(hud.add, drawTransfers, "intermission")
pcall(hud.add, drawTransfers, "vote")
