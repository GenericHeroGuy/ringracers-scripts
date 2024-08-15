-- what characters can we use in command arguments?
-- any 8-bit character except \0, \r, \n, "
-- so.. base 252!
-- actually i'm too stupid for base 252 so i'm going with base 128
-- it's less compact, but i'm not in the mood for bigint math
-- plus it helps to know how long the output will be so you can control the netxcmd bandwidth used

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

local sendPacket

local packets = {
	{
		name = "start",
		func = function(p, channel, data)
			local target = data:byte(1)
			local length = tonumber(data:sub(2))
			if #consoleplayer == target then
				print("is for me?")
				local rx = {
					data = "",
					state = "receiving",
					channel = channel,
					finallength = length,
				}
				table.insert(myconnections, rx)
				sendPacket("ack", channel, "")
			end
		end,
	},
	{
		name = "ack",
		func = function(p, channel, data)
			for _, tx in ipairs(myconnections) do
				if tx.channel == channel and tx.state == "starting" then
					tx.state = "sending"
				end
			end
		end,
	},
	{
		name = "recvfinish",
		func = function(p, channel, data)
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
			end
			for _, rx in ipairs(myconnections) do
				if rx.channel == channel and rx.state == "receiving" then
					rx.data = $..data
					timeout[p] = 0
					if #rx.data == rx.finallength then
						rx.state = false
						sendPacket("recvfinish", channel, "")
						if rx.callback then
							rx.callback(true, rx.data)
						end
						--[[
						local file = io.open("receive.png", "wb")
						file:write(rx.data)
						file:close()
						--]]
					end
					return
				end
			end
		end,
	},
	{
		name = "getghosts",
		func = function(p, channel, data)
			local target = data:byte()
			local recordid = tonumber(data:sub(2))
			if not recordid then
				print("Corrupted ghost request from "..p.name)
				return
			end
			if #consoleplayer == target then
				print(p.name.." requesting ghost for "..recordid)
				if not isserver then
					-- i'm not the server, i can't give you any ghosts!
					print("not the server")
					return
				end
				local maprecords = lb_get_map_records(gamemap, -1)
				local ghostdata
				for mode, records in pairs(maprecords) do
					for _, record in ipairs(records) do
						if record.id == recordid then
							-- gotcha!
							for _, p in ipairs(record.players) do
								ghostdata = p.ghost
								break
							end
						end
					end
				end
				if not ghostdata then print("no data"); return end
				local tx = {
					data = ghostdata,
					state = "sending",
					channel = channel,
					finallength = #ghostdata,
					who = consoleplayer,
				}
				table.insert(myconnections, tx)
				sendPacket("ghostack", channel, tostring(#ghostdata))
			end
		end,
	},
	{
		name = "ghostack",
		func = function(p, channel, data)
			local ghostlen = tonumber(data)
			for _, rx in ipairs(myconnections) do
				if rx.channel == channel and rx.state == "starting" then
					rx.state = "receiving"
					timeout[p] = 0
					rx.finallength = ghostlen
					rx.who = p
				end
			end
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
	COM_BufAddText(consoleplayer, fmt('\x7f "%s"', base128encode(string.char(ptype, channel)..data)))
end

COM_AddCommand("\x7f", function(p, data)
	data = base128decode(data)
	local ptype = data:byte(1)
	local channel = data:byte(2)
	if not packets[ptype] then
		print("unknown packet type "..tostring(ptype))
		return
	end
	if p ~= consoleplayer then
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

	-- XXX: %c format doesn't handle zeroes. good luck convincing anyone to upgrade to Lua 5.2
	sendPacket(ptype, tx.channel, string.char(#server)..fmt("%d", #data))
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
end

local cv_bandwidth = CV_RegisterVar({
	name = "lb_trn_bandwidth",
	defaultvalue = 192,
	possiblevalue = { MIN = 16, MAX = 247 }
})

local cv_timeout = CV_RegisterVar({
	name = "lb_trn_timeout",
	defaultvalue = TICRATE/3,
	possiblevalue = { MIN = TICRATE/10, MAX = TICRATE }
})

local function transferThinker()
	local sent = false

	for p in pairs(timeout) do
		timeout[p] = ($ or 0) + 1
		if timeout[p] > cv_timeout.value then
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
				local bw = base128shrink(cv_bandwidth.value)
				local chunk = tx.data:sub(1, bw)
				tx.data = tx.data:sub(bw+1)
				sendPacket("send", tx.channel, chunk)
				timeout[tx.who] = 0
				sent = true
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
	startReceiver(string.char(#server)..tostring(id), "getghosts", callback)
end
rawset(_G, "lb_request_ghosts", RequestGhosts)

COM_AddCommand("testtransfer", function(p, data)
	local file, err = io.open("input.png", "rb")
	if not file then return print(err) end
	data = file:read("*a")
	file:close()
	startTransfer(data, "start", function(ok) print("done "..tostring(ok)) end)
end, COM_LOCAL)

hud.add(function(v, p)
	for i, tx in ipairs(myconnections) do
		local str = fmt("%s: %d", tostring(tx.state), #tx.data)
		if tx.finallength then
			str = str..fmt("/%d", tx.finallength)
		end
		v.drawString(32, 32+i*8, str)
	end
end)
