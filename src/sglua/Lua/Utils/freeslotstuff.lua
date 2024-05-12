-- freeslot globalization by GenericHeroGuy

local firstsfx, firstspr, firststate, firstmt

local realfreeslot = freeslot
rawset(_G, "freeslot", function(...)
	local ret = {}
	for _, v in ipairs{...} do
		if pcall(do if _G[v] == nil then error() end end) then
			print(v.." already exists")
			table.insert(ret, _G[v])
			continue
		end
		local r = realfreeslot(v)
		rawset(_G, v, _G[v])
		table.insert(ret, r)
	end
	return unpack(ret)
end)

-- fun fact: skins actually have 33 sounds: 21 unused sounds from vanilla SRB2, plus 12 new sounds for ring racers
-- both of these are counted in NUMSKINSOUNDS, which means the game allocates 8415 freeslots for skinsounds, rather than the 3060 it actually needs
-- so technically, you actually have 6955 freeslots dedicated to SFX rather than 1600

COM_AddCommand("listfreeslots", function(p)
	local numsfx = 0
	for i = firstsfx, #sfxinfo - 1 do
		if sfxinfo[i].priority ~= 0 then
			numsfx = $ + 1
		else
			break
		end
	end

	local numspr = 0
	for i = firstspr, #sprnames - 1 do
		if tonumber(sprnames[i]) == nil then
			numspr = $ + 1
		else
			break
		end
	end

	local numstate = 0
	for i = firststate, #states - 1 do
		local s = states[i]
		if s.string then
			numstate = $ + 1
		else
			break
		end
	end

	local nummt = 0
	for i = firstmt, #mobjinfo - 1 do
		local mt = mobjinfo[i]
		if mt.string then
			nummt = $ + 1
		else
			break
		end
	end

	print("Freeslot usage:")
	print("SFX: "..numsfx.."/"..(#sfxinfo - firstsfx))
	print("Sprites: "..numspr.."/"..(#sprnames - firstspr))
	print("States: "..numstate.."/"..(#states - firststate))
	print("Mobjs: "..nummt.."/"..(#mobjinfo - firstmt))
end, COM_LOCAL)

-- globalize and count SFX
print("Counting SFX")
for i = 1, #sfxinfo - 1 do
	local sfx = sfxinfo[i]
	--print(string.format("%s %05d %05d %05d %05d %s %s", tostring(sfx.singular), sfx.priority, sfx.flags, sfx.volume, sfx.skinsound, sfx.name, sfx.caption))
	if sfx.priority ~= 0 then
		firstsfx = i + 1
		--print(i..": sfx_"..sfx.name)
		if _G["sfx_"..sfx.name] == i then
			rawset(_G, "sfx_"..sfx.name, i)
		else
			print("WTF")
		end
	elseif firstsfx then
		break
	end
end

-- globalize and count sprites
print("Counting sprites")
for i = 0, #sprnames - 1 do
	local name = sprnames[i]
	if tonumber(name) == nil then
		--print(i..": SPR_"..name)
		if _G["SPR_"..name] == i then
			rawset(_G, "SPR_"..name, i)
			firstspr = i + 1
		else
			print("SPR_"..name.." is supposed to have ID "..i.." but it's actually "..tostring(_G["SPR_"..name])..". Dupe?")
		end
	else
		break
	end
end

-- globalize and count mobjs
print("Counting mobjs")
for i = 0, #mobjinfo - 1 do
	local mt = mobjinfo[i]
	if mt.string then
		if _G["MT_"..mt.string] == i then
			rawset(_G, "MT_"..v, i)
			firstmt = i + 1
		else
			print("MT_"..mt.string.." is supposed to have ID "..i.." but it's actually "..tostring(_G["MT_"..mt.string])..". Dupe?")
		end
	else
		break
	end
end

-- globalize and count states
print("Counting states")
for i = 0, #states - 1 do
	local s = states[i]
	if s.string then
		if _G["S_"..s.string] == i then
			rawset(_G, "S_"..v, i)
			firststate = i + 1
		else
			print("S_"..s.string.." is supposed to have ID "..i.." but it's actually "..tostring(_G["S_"..s.string])..". Dupe?")
		end
	else
		break
	end
end
