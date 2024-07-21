local MSG = "<<~"
local CHN = "~>>"

local PACKET_MAX_SIZE = 200
local MAX_TICS = TICRATE * 2

local function encode(data)
	data = string.gsub(data, "\n", "\\n")
	data = string.gsub(data, "\t", "\\t")
	return data
end

local function decode(data)
	data = string.gsub(data, "\\n", "\n")
	data = string.gsub(data, "\\t", "\t")
	return data
end

local transmitters = {}

local function Transmitter(channel, opts)
	assert(channel, "Transmitter: channel is required")
	opts = $ or {}

	return {
		packets = {},

		push = function(this, packet)
			table.insert(this.packets, MSG..channel..CHN..packet)
		end,

		pop = function(this)
			return table.remove(this.packets)
		end,

		sendPacket = function(this)
			local sender = consoleplayer or server
			-- G: use console command
			-- use BufAddText because TryRunTics might do two tics in one go, which would overflow the netxcmd buffer if using BufInsertText
			COM_BufAddText(sender, 'lb_transfer "'..this:pop()..'"; wait')
			--COM_BufInsertText(sender, "say \""..this:pop().."\"")
			return not #this.packets
		end,

		writeHeader = function(this)
			this:push(#this.packets)
		end,

		close = function(this)
			for i, tr in ipairs(transmitters) do
				if tr == this then
					table.remove(transmitters, i)
					break
				end
			end

			if opts.free then
				opts.free(this, opts.handle)
			end
		end,

		enqueue = function(this)
			table.insert(transmitters, this)
		end,

		transmit = function(this, data)
			assert(data, "Transmitter: nil data")

			data = encode(data)

			if opts.stream then
				assert(
					#data < PACKET_MAX_SIZE,
					"Transmitter: data packet too large for stream"
				)

				this:push(data)
				this:enqueue()
				return
			end

			local sub
			for i = 1, #data, PACKET_MAX_SIZE do
				sub = data:sub(i, min(#data, i + PACKET_MAX_SIZE-1))
				this:push(sub)
			end

			this:writeHeader()
			this:enqueue()
		end
	}
end
rawset(_G, "lb_transmitter", Transmitter)

addHook("ThinkFrame", function()
	if not (#transmitters and leveltime) then return end

	local index = (leveltime % #transmitters) + 1
	local transmitter = transmitters[index]

	if transmitter:sendPacket() then
		transmitter:close()
	end
end)

local Channels = {
	channel = {},

	add = function(this, ch, reciever)
		this.channel[ch] = $ or {}
		table.insert(this.channel[ch], reciever)
	end,

	chan = function(this, ch)
		local c = this.channel[ch]
		local i = c and #c + 1 or 0
		return function()
			if i > 1 then
				i = i - 1
				return i, c[i]
			end
		end
	end,

	remove = function(this, ch, index)
		table.remove(this.channel[ch], index)
	end,

	recieve = function(this)
		return function(packet, ch)
			for i, reciever in this:chan(ch) do
				if reciever:push(packet) then
					reciever:close()
				end
			end
		end
	end
}

addHook("ThinkFrame", function()
	for _, ch in pairs(Channels.channel) do
		for _, rec in pairs(ch) do
			if rec:tick() then
				rec:close()
			end
		end
	end
end)

local function Reciever(channel, callback, opts)
	assert(callback, "Reciever: callback is required")
	opts = $ or {}

	local ticker, pusher
	local MAX_TICS = MAX_TICS
	if opts.stream then
		ticker = function(this) end

		pusher = function(this, packet)
			callback(decode(packet), opts.handle)
		end
	else
		ticker = function(this)
			this.tics = $ + 1
			return this.tics > MAX_TICS
		end

		pusher = function(this, packet)
			if not this.len then
				this:recieveHeader(packet)
				return
			end

			table.insert(this.packets, packet)

			if opts.progress then
				opts.progress(#this.packets, this.len, opts.handle)
			end

			if #this.packets >= this.len then
				this:finish()
				return true
			end

			this.tics = 0
		end
	end

	return {
		len,
		packets = {},
		tics = 0,
		tick = ticker,

		close = function(this)
			for i, rec in Channels:chan(channel) do
				if rec == this then
					Channels:remove(channel, i)
					if opts.free then
						opts.free(this, opts.handle)
					end
					return
				end
			end
		end,

		push = pusher,

		recieveHeader = function(this, header)
			local len = tonumber(header)
			-- G: if someone joins mid-transmission and the map changes,
			-- the receiver will spam the console with invalid header errors.
			-- close the channel if an invalid header is received
			--[[
			assert(len ~= nil,
				"Reciever: invalid header '"..(header or "nil").."'")
			--]]
			if len == nil then
				this:close()
				return
			end
			this.len = len
		end,

		listen = function(this)
			Channels:add(channel, this)
		end,

		pop = function(this)
			return table.remove(this.packets)
		end,

		finish = function(this)
			local data = ""

			local s = this:pop()
			while s do
				data = $..s
				s = this:pop()
			end

			callback(decode(data), opts.handle)
		end
	}
end
rawset(_G, "lb_reciever", Reciever)

local function scan(sym, msg, fn)
	if msg:find(sym) == 1 then
		msg = msg:sub(#sym+1)
		local chi = msg:find(CHN)
		local ch = msg:sub(1, chi-1)
		msg = msg:sub(chi+#CHN)
		fn(msg, ch)
		return true
	end
end

-- G: using console commands to avoid conflicts with other chat scripts (greentext)
COM_AddCommand("lb_transfer", function(p, msg)
	scan(MSG, msg, Channels:recieve())
end)

--[[
addHook("PlayerMsg", function(source, type, target, msg)
	return scan(MSG, msg, Channels:recieve())
end)
--]]
