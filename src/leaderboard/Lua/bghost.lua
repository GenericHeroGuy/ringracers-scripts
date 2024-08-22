-- binary ghosts

---- Imported functions ----

-- lb_common.lua
local StringReader = lb_string_reader

-----------------------------

local EXP0 = FRACBITS+12
local EXP1 = FRACBITS+8
local EXP2 = FRACBITS+4
local EXP3 = FRACBITS+0
local EXP4 = FRACBITS-4
local EXP5 = FRACBITS-8
local EXP6 = FRACBITS-12
local EXP7 = FRACBITS-16

-- converts fixed to bloat
-- returns bloat, error
local function FixedToBloat(n)
	local sign, exp, mnt, error = n < 0
	if n == INT32_MIN then n = n + 1 end -- AAAAAAAAAAAAA
	n = abs(n)
	if n >= 1 << EXP0 then
		exp = 7
		mnt = (n & 0xf0000000) >> EXP0
		error = n & 0x0fffffff
	elseif n >= 1 << EXP1 then
		exp = 6
		mnt = (n & 0x0f000000) >> EXP1
		error = n & 0x00ffffff
	elseif n >= 1 << EXP2 then
		exp = 5
		mnt = (n & 0x00f00000) >> EXP2
		error = n & 0x000fffff
	elseif n >= 1 << EXP3 then
		exp = 4
		mnt = (n & 0x000f0000) >> EXP3
		error = n & 0x0000ffff
	elseif n >= 1 << EXP4 then
		exp = 3
		mnt = (n & 0x0000f000) >> EXP4
		error = n & 0x00000fff
	elseif n >= 1 << EXP5 then
		exp = 2
		mnt = (n & 0x00000f00) >> EXP5
		error = n & 0x000000ff
	elseif n >= 1 << EXP6 then
		exp = 1
		mnt = (n & 0x000000f0) >> EXP6
		error = n & 0x0000000f
	else--if n >= 1 << EXP7 then
		exp = 0
		mnt = (n & 0x0000000f) >> EXP7
		error = n & 0x00000000
	end

	return (sign and 0x80 or 0x00) | exp<<4 | mnt, sign and -error or error
end

local function BloatToFixed(n)
	local sign, exp, mnt = n & 0x80, n & 0x70, n & 0x0f
	local out
	if exp == 0x70 then
		out = mnt<<EXP0
	elseif exp == 0x60 then
		out = mnt<<EXP1
	elseif exp == 0x50 then
		out = mnt<<EXP2
	elseif exp == 0x40 then
		out = mnt<<EXP3
	elseif exp == 0x30 then
		out = mnt<<EXP4
	elseif exp == 0x20 then
		out = mnt<<EXP5
	elseif exp == 0x10 then
		out = mnt<<EXP6
	elseif exp == 0x00 then
		out = mnt<<EXP7
	end

	if sign then out = -out end
	return out
end

local FS_STND = 0
local FS_STNDL = 1
local FS_STNDR = 2
local FS_WALK = 3
local FS_WALKL = 4
local FS_WALKR = 5
local FS_RUN = 6
local FS_RUNL = 7
local FS_RUNR = 8
local FS_DRIFTL = 9
local FS_DRIFTR = 10
local FS_SPIN = 11
local FS_SQUISH = 12
local FS_POGO = 13

local REALTOFAKE = {
	[S_KART_STND1] = 0,
	[S_KART_STND2] = 0,
	[S_KART_STND1_L] = 1,
	[S_KART_STND2_L] = 1,
	[S_KART_STND1_R] = 2,
	[S_KART_STND2_R] = 2,
	[S_KART_WALK1] = 3,
	[S_KART_WALK2] = 3,
	[S_KART_WALK1_L] = 4,
	[S_KART_WALK2_L] = 4,
	[S_KART_WALK1_R] = 5,
	[S_KART_WALK2_R] = 5,
	[S_KART_RUN1] = 6,
	[S_KART_RUN2] = 6,
	[S_KART_RUN1_L] = 7,
	[S_KART_RUN2_L] = 7,
	[S_KART_RUN1_R] = 8,
	[S_KART_RUN2_R] = 8,
	[S_KART_DRIFT1_L] = 9,
	[S_KART_DRIFT2_L] = 9,
	[S_KART_DRIFT1_R] = 10,
	[S_KART_DRIFT2_R] = 10,
	[S_KART_SPIN] = 11,
	[S_KART_PAIN] = 11,
	[S_KART_SQUISH] = 12,
}

local FAKEFRAMES = {
	[FS_STND] = { A, B },
	[FS_STNDL] = { C, D },
	[FS_STNDR] = { E, F },
	[FS_WALK] = { J, G },
	[FS_WALKL] = { K, H },
	[FS_WALKR] = { L, I },
	[FS_RUN] = { A, J },
	[FS_RUNL] = { C, K },
	[FS_RUNR] = { E, L },
	[FS_DRIFTL] = { M, N },
	[FS_DRIFTR] = { O, P },
	[FS_SPIN] = { Q },
	[FS_SQUISH] = { R },
	[FS_POGO] = { A, J },
}

local sacache = {}
local function GetSimpleAnimalSequences(defs, skin)
	if not sacache[defs] then
		local int = {}
		for k in pairs(defs) do
			-- avoid animations we don't need
			if k == "goal" or k == "invincible" then continue end
			if skin:sub(1, 8) == "running_" and (k == "walk" or k == "run" or k == "win" or k == "lose" or k:sub(1, 5) == "super") then continue end
			table.insert(int, k)
		end

		if #int > 16 then
			print("WARNING: Too many frames, animations will probably break")
			for i = #int, 17, -1 do
				int[i] = nil
			end
		end

		table.sort(int)
		sacache[defs] = int
	end
	return sacache[defs]
end

-- returns the fakeframe to write for this tic
local function WriteFakeFrame(ghost, player)
	-- an attempt at simple animal interop
	-- only tested with shadowskates and runningchars, your mileage may vary
	local defs = SIMPLE_ANIMAL_DEFINITIONS and SIMPLE_ANIMAL_DEFINITIONS[player.mo.skin]
	if defs then
		local sequences = GetSimpleAnimalSequences(defs, player.mo.skin)
		for k, v in ipairs(sequences) do
			if v == player.mo.Simple_AnimaL_sequence_last then
				return k - 1
			end
		end
		--print("UNKNOWN SEQUENCE!")
		return 0
	else
		local frame = REALTOFAKE[player.mo.state] or 0
		if (flags == FS_DRIFTL or flags == FS_DRIFTR) and player.kartstuff[k_driftend] then
			frame = FS_STND
		elseif player.kartstuff[k_pogospring] then
			frame = FS_POGO
		end
		return frame
	end
end

-- returns the frame to use for ghost, and frame special
local function ReadFakeFrame(framenum, skin)
	local defs = SIMPLE_ANIMAL_DEFINITIONS and SIMPLE_ANIMAL_DEFINITIONS[skin]
	local fspecial = ""
	if defs then
		local sequences = GetSimpleAnimalSequences(defs, skin)
		for k, v in ipairs(sequences) do
			if k == framenum+1 then
				if v == "drift_left" then
					fspecial = "driftl"
				elseif v == "drift_right" then
					fspecial = "driftr"
				elseif v == "bounce" then
					fspecial = "pogo"
				elseif v == "pain" or v == "spin" or v == "spinout" then
					fspecial = "spin"
				end
				local t = defs[v]
				return t[(leveltime % #t) + 1], fspecial
			end
		end
		--print("UNKNOWN SEQUENCE!")
		return 0
	else
		local fs = FAKEFRAMES[framenum]
		if framenum == FS_POGO or framenum == FS_SPIN then
			fspecial = "spin"
		elseif framenum == FS_DRIFTL then
			fspecial = "driftl"
		elseif framenum == FS_DRIFTR then
			fspecial = "driftr"
		end
		return fs[(leveltime % #fs) + 1], fspecial
	end
end

-- ghost specials
local GS_NOSPARKS = 0x81 -- removes drift sparks
local GS_BLUESPARKS = 0x82 -- get blue sparks
local GS_ORANGESPARKS = 0x83 -- get orange sparks
local GS_RAINBOWSPARKS = 0x84 -- get rainbow sparks
local GS_DRIFTBOOST = 0x85 -- get drift boost (implies GS_NOSPARKS)
local GS_SNEAKER = 0x86 -- used sneaker
local GS_STARTBOOST = 0x87 -- start boost

local function WriteGhostTic(ghost, player, x, y, z, angle)
	local flags = WriteFakeFrame(ghost, player)
	local str = ""
	if x or y then
		flags = $ | 0x10
		str = string.char(x, y)
	end
	if z then
		flags = $ | 0x20
		str = $..string.char(z)
	end
	if angle then
		flags = $ | 0x40
		str = $..string.char(angle)
	end

	-- and now, the specials
	local ks = player.kartstuff

	if ks[k_sneakertimer] > ghost.lastsneaker then
		ghost.data = $..string.char(ks[k_sneakertimer] == 69 and GS_STARTBOOST or GS_SNEAKER)
	end
	ghost.lastsneaker = ks[k_sneakertimer]

	if player.playerstate == PST_LIVE then
		local dsv = K_GetKartDriftSparkValue(player)
		if ks[k_driftcharge] >= dsv*4 then
			if ghost.lastspark ~= 3 then ghost.data = $..string.char(GS_RAINBOWSPARKS) end
			ghost.lastspark = 3
		elseif ks[k_driftcharge] >= dsv*2 then
			if ghost.lastspark ~= 2 then ghost.data = $..string.char(GS_ORANGESPARKS) end
			ghost.lastspark = 2
		elseif ks[k_driftcharge] >= dsv then
			if ghost.lastspark ~= 1 then ghost.data = $..string.char(GS_BLUESPARKS) end
			ghost.lastspark = 1
		end
	end
	if ghost.lastspark and (not ks[k_driftcharge] or player.playerstate ~= PST_LIVE) then
		if not (ks[k_spinouttimer] or player.mo.eflags & MFE_JUSTBOUNCEDWALL) and abs(ks[k_drift]) ~= 5 and ks[k_getsparks] and player.playerstate == PST_LIVE then
			ghost.data = $..string.char(GS_DRIFTBOOST)
		else
			ghost.data = $..string.char(GS_NOSPARKS)
		end
		ghost.lastspark = 0
	end

	ghost.data = $..string.char(flags)..str
end

local recorders = {}

-- start recording ghost data for player
local function StartRecording(player)
	recorders[player] = {
		data = "",
		lastsneaker = 0,
		lastspark = 0,

		momlog = { x = 0, y = 0, z = 0, a = 0 },
		errorx = 0,
		errory = 0,
		errorz = 0,
		errora = 0,
		fakemomx = 0,
		fakemomy = 0,
		fakemomz = 0,
		fakemoma = 0,
		fakex = 0,
		fakey = 0,
		fakez = 0,
		fakea = 0,
	}
end
rawset(_G, "lb_ghost_start_recording", StartRecording)

-- stops recording a ghost
-- returns the recorded data
local function StopRecording(player)
	local data = recorders[player].data
	recorders[player] = nil
	return data
end
rawset(_G, "lb_ghost_stop_recording", StopRecording)

addHook("MapChange", function()
	recorders = {}
end)

addHook("ThinkFrame", function()
	if not leveltime then return end
	for player, g in pairs(recorders) do
		if player.spectator then StopRecording(player); continue end

		-- hoooly fuck this is stupid
		-- but after hours and hours of trying random shit until something worked, this is what worked
		-- so just deal with it
		-- i have no clue what to do about the whiplash from teleports

		local mold = g.momlog
		local mnew = { x = player.mo.x - g.fakex, y = player.mo.y - g.fakey, z = player.mo.z - g.fakez, a = player.mo.angle - g.fakea }
		g.momlog = mnew

		local dx, dy, dz, da = mnew.x - mold.x, mnew.y - mold.y, mnew.z - mold.z, mnew.a - mold.a
		local bx, ex = FixedToBloat(dx + g.errorx)
		local by, ey = FixedToBloat(dy + g.errory)
		local bz, ez = FixedToBloat(dz + g.errorz)
		local ba, ea = FixedToBloat(da + g.errora)
		g.errorx, g.errory, g.errorz, g.errora = ex, ey, ez, ea
		WriteGhostTic(g, player, bx, by, bz, ba)
		g.fakemomx = $ + BloatToFixed(bx)
		g.fakemomy = $ + BloatToFixed(by)
		g.fakemomz = $ + BloatToFixed(bz)
		g.fakemoma = $ + BloatToFixed(ba)
		g.fakex = $ + g.fakemomx
		g.fakey = $ + g.fakemomy
		g.fakez = $ + g.fakemomz
		g.fakea = $ + g.fakemoma
	end
end)

----------------------------------------------------------------------

-- players is taken soooo
local replayers = {}
local ghostwatching, ghostcam

-- spawns an mobj that doesn't sync in netgames
local function SpawnLocal(x, y, z, type)
	local oldflags = mobjinfo[type].flags
	mobjinfo[type].flags = $ | MF_NOTHINK
	local mo = P_SpawnMobj(x, y, z, type)
	mobjinfo[type].flags = oldflags
	return mo
end

local F_COMBI = lb_flag_combi

-- spawns a ghost's half of the combi link
local function SpawnCombiLink(r)
	local count = 6/2 --hcombi.cv_ringamount.value/2 -- it's broken anyway
	for i = 1, count do
		local edge = i == 1 --or i == count
		local link = SpawnLocal(r.mo.x, r.mo.y, r.mo.z, MT_THOK)
		link.flags = MF_NOTHINK|MF_NOBLOCKMAP|MF_NOGRAVITY|MF_NOCLIP|MF_NOCLIPTHING|MF_NOCLIPHEIGHT|MF_DONTENCOREMAP
		link.state = edge and S_COMBILINK1 or S_COMBILINK2
		link.scale = mapobjectscale / (edge and 2 or 1)
		link.frame = FF_TRANS60
		r.combilink[i] = link
	end
end

local function PlayGhost(record)
	local ghosts = {}
	for i, recplayer in ipairs(record.players) do
		local mo = SpawnLocal(0, 0, 0, MT_THOK)
		mo.flags = MF_NOTHINK|MF_NOBLOCKMAP|MF_NOGRAVITY|MF_NOCLIP|MF_NOCLIPTHING|MF_NOCLIPHEIGHT|MF_DONTENCOREMAP
		mo.sprite = SPR_PLAY
		mo.skin = recplayer.skin
		mo.color = recplayer.color

		local ghost = setmetatable({
			file = StringReader(recplayer.ghost),
			name = recplayer.name,
			mo = mo,
			gmomx = 0,
			gmomy = 0,
			gmomz = 0,
			gmoma = 0,
			realangle = 0,

			fspecial = 0,
			lastfspecial = 0,
			fakeframe = 0,
			angofs = 0,

			-- combi
			combilink = {},
			combipartner = false,

			-- purely visual, just for showing vfx
			boostflame = false,
			sneakertimer = 0,
			driftspark = 0,
			driftboost = 0,
		}, { __index = do error("no", 2) end, __newindex = do error("no", 2) end })
		table.insert(ghosts, ghost)
		replayers[ghost] = true
	end

	if record.flags & F_COMBI then
		for i, g in ipairs(ghosts) do
			local partner = ghosts[(i % #ghosts)+1]
			g.combipartner = partner.mo
			SpawnCombiLink(g)
		end
	end
end

-- plays the ghost(s) stored in the provided record
local function StartPlaying(record)
	for _, p in ipairs(record.players) do
		if not #p.ghost then
			return false
		end
	end
	PlayGhost(record)
	return true
end
rawset(_G, "lb_ghost_start_playing", StartPlaying)

local function StopWatching()
	ghostwatching = nil
	consoleplayer.awayviewmobj = nil
	consoleplayer.awayviewtics = 0
	-- keep the ghostcam
end

local function NextWatch()
	if ghostwatching then
		ghostwatching = next(replayers, ghostwatching) or next(replayers)
		if not ghostwatching then StopWatching() end
	else
		ghostwatching = next(replayers)
	end
end

local function StopPlaying(replay)
	P_RemoveMobj(replay.mo)
	for _, v in pairs(replay.combilink) do
		P_RemoveMobj(v)
	end
	replayers[replay] = nil
	if ghostwatching == replay then NextWatch() end
end

addHook("MapChange", function()
	replayers = {}
	ghostwatching = nil
end)

local starttime = 6*TICRATE + (3*TICRATE/4)
local ghostcustom2 = 0

local function SpawnDriftSparks(r, direction)
	local pmo = r.mo
	local color
	if r.driftspark == 1 then
		color = SKINCOLOR_SAPPHIRE
	elseif r.driftspark == 2 then
		color = SKINCOLOR_KETCHUP
	else
		color = 1 + (leveltime % (MAXSKINCOLORS-1))
	end
	local travelangle = pmo.angle - ANGLE_45*direction

	for i = 0, 1 do
		local newx = pmo.x + P_ReturnThrustX(travelangle + (i and -1 or 1)*ANGLE_135, 32*pmo.scale)
		local newy = pmo.y + P_ReturnThrustY(travelangle + (i and -1 or 1)*ANGLE_135, 32*pmo.scale)
		local spark = P_SpawnMobj(newx, newy, pmo.z, MT_DRIFTSPARK)

		spark.angle = travelangle - ANGLE_45*direction
		spark.destscale = pmo.scale
		spark.scale = pmo.scale

		spark.momx = r.gmomx/2
		spark.momy = r.gmomy/2
		spark.color = color

		K_MatchGenericExtraFlags(spark, pmo)
		spark.frame = $ | FF_TRANS10
		spark.tics = $ - 1
	end
end

-- yoinked from m_random.c
local randomseed = 0xBADE4404
local function randomrange(a, b)
	local rng = randomseed
	rng = $ ^^ ($ >> 13)
	rng = $ ^^ ($ >> 11)
	rng = $ ^^ ($ << 21)
	randomseed = rng
	rng = (($*36548569) >> 4) & (FRACUNIT-1)
	-- and now the actual range part
	return ((rng * (b-a+1)) >> FRACBITS) + a
end

local function SpawnFastLines(r)
	local fast = P_SpawnMobj(r.mo.x + (randomrange(-36,36) * r.mo.scale),
		r.mo.y + (randomrange(-36,36) * r.mo.scale),
		r.mo.z + (r.mo.height/2) + (randomrange(-20,20) * r.mo.scale),
		MT_FASTLINE)
	fast.angle = R_PointToAngle2(0, 0, r.gmomx, r.gmomy)
	fast.momx = 3*r.gmomx/4
	fast.momy = 3*r.gmomy/4
	fast.momz = 3*r.gmomz/4
	K_MatchGenericExtraFlags(fast, r.mo)
end

local function MoveCombiLink(r)
	local c = r.combipartner
	local length = #r.combilink*2 + 1
	local divx = (c.x - r.mo.x)/length
	local divy = (c.y - r.mo.y)/length
	local divz = (c.z - r.mo.z)/length

	for i, link in ipairs(r.combilink) do
		P_MoveOrigin(link, r.mo.x + divx*i, r.mo.y + divy*i, r.mo.z + divz*i + 18*mapobjectscale)
		link.color = c.color
		-- have to animate it ourselves because NOTHINK
		if link.state == S_COMBILINK2 then
			link.frame = ($ & ~FF_FRAMEMASK) | leveltime/2 % 9
		end
	end
end

addHook("ThinkFrame", function()
	if not leveltime then return end
	--[[
	if not next(replayers) then
		if ghostwatching then
			if consoleplayer.cmd.buttons & BT_CUSTOM1 then
				COM_BufInsertText(server, "map "..gamemap.." -f")
				ghostwatching = nil
			end
		end
		return
	end
	--]]

	if consoleplayer.cmd.buttons & BT_CUSTOM2 then
		ghostcustom2 = $ + 1
	else
		ghostcustom2 = 0
	end

	if ghostcustom2 == 1 then
		if not (ghostcam and ghostcam.valid) then
			ghostcam = P_SpawnMobj(0, 0, 0, MT_THOK)
			ghostcam.flags = MF_NOTHINK|MF_NOSECTOR|MF_NOBLOCKMAP|MF_NOCLIP|MF_NOCLIPHEIGHT|MF_NOCLIPTHING
		end
		NextWatch()
	end

	for r in pairs(replayers) do
		if not r.file:empty() then
			local flags
			repeat -- for all the specials
				flags = r.file:read8()
				if flags == GS_SNEAKER or flags == GS_STARTBOOST then
					r.sneakertimer = flags == GS_SNEAKER and TICRATE + (TICRATE/3) or 70
					if not (r.boostflame and r.boostflame.valid) then
						r.boostflame = P_SpawnMobj(r.mo.x, r.mo.y, r.mo.z, MT_THOK)
						r.boostflame.state = S_BOOSTFLAME
						r.boostflame.scale = r.mo.scale
						r.boostflame.frame = $ | FF_TRANS40
					else
						r.boostflame.state = S_BOOSTFLAME
					end
				elseif flags >= GS_NOSPARKS and flags <= GS_RAINBOWSPARKS then
					r.driftspark = flags - GS_NOSPARKS
				elseif flags == GS_DRIFTBOOST then
					if r.driftspark == 1 then
						r.driftboost = $ < 20 and 20 or 0
					elseif r.driftspark == 2 then
						r.driftboost = $ < 50 and 50 or 0
					else
						r.driftboost = $ < 125 and 125 or 0
					end
					r.driftspark = 0
				end
			until flags & 0x80 == 0

			local dx = (flags & 0x10) and BloatToFixed(r.file:read8())
			local dy = (flags & 0x10) and BloatToFixed(r.file:read8())
			local dz = (flags & 0x20) and BloatToFixed(r.file:read8())
			local da = (flags & 0x40) and BloatToFixed(r.file:read8())
			local frame, fspecial = ReadFakeFrame(flags & 0x0f, r.mo.skin)

			r.fakeframe = flags & 0x0f
			r.fspecial = fspecial
			r.gmomx = $ + dx
			r.gmomy = $ + dy
			r.gmomz = $ + dz
			r.gmoma = $ + da

			P_MoveOrigin(r.mo, r.mo.x + r.gmomx, r.mo.y + r.gmomy, r.mo.z + r.gmomz)
			r.mo.frame = frame | FF_TRANS40
			r.realangle = $ + r.gmoma
			r.mo.angle = r.realangle
			if fspecial == "spin" then
				r.mo.angle = $ + (ANGLE_22h*(leveltime%16))
			end

			if r.boostflame and r.boostflame.valid then
				P_MoveOrigin(r.boostflame, r.mo.x + P_ReturnThrustX(r.realangle+ANGLE_180, r.mo.radius), r.mo.y + P_ReturnThrustY(r.realangle+ANGLE_180, r.mo.radius), r.mo.z)
				r.boostflame.angle = r.realangle
				r.boostflame.scale = r.mo.scale

				if r.boostflame.state == S_BOOSTSMOKESPAWNER then
					local smoke = P_SpawnMobj(r.boostflame.x, r.boostflame.y, r.boostflame.z+(8<<FRACBITS), MT_BOOSTSMOKE)

					smoke.scale = r.mo.scale/2
					smoke.destscale = 3*r.mo.scale/2
					smoke.scalespeed = r.mo.scale/12

					smoke.momx = r.gmomx/2
					smoke.momy = r.gmomy/2
					smoke.momz = r.gmomz/2

					P_Thrust(smoke, r.boostflame.angle+FixedAngle(randomrange(135, 225)<<FRACBITS), randomrange(0, 8) * r.mo.scale)
				end
			end
			if r.driftspark and r.mo.z < r.mo.floorz + mapobjectscale*8 then
				SpawnDriftSparks(r, fspecial == "driftl" and 1 or -1)
			end
			if r.driftboost or r.sneakertimer then
				SpawnFastLines(r)
			end
			r.driftboost = max($ - 1, 0)
			r.sneakertimer = max($ - 1, 0)
		else
			print("Finished")
			StopPlaying(r)
			if not ghostwatching then
				consoleplayer.awayviewtics = 0
				consoleplayer.awayviewmobj = nil
			end
		end
	end

	-- update combi links after all ghosts have moved
	for r in pairs(replayers) do
		if r.combipartner and r.combipartner.valid then
			MoveCombiLink(r)
		end
	end

	if consoleplayer.cmd.buttons & (BT_ACCELERATE|BT_BRAKE|BT_ATTACK|BT_DRIFT) then
		StopWatching()
	end

	local r = ghostwatching
	if r then
		local fspecial = r.fakeframe == FS_POGO and r.lastfspecial or r.fspecial
		r.lastfspecial = fspecial
		if fspecial == "driftl" and r.angofs < ANG2 then
			if r.angofs > -ANG30 then r.angofs = $ - ANG1 end
		elseif fspecial == "driftr" and r.angofs > -ANG2 then
			if r.angofs < ANG30 then r.angofs = $ + ANG1 end
		else
			r.angofs = 3*r.angofs/4
		end

		local inputofs = 0
		if consoleplayer.cmd.driftturn >= 200 then
			inputofs = ANGLE_90
		elseif consoleplayer.cmd.driftturn <= -200 then
			inputofs = -ANGLE_90
		end
		if consoleplayer.cmd.buttons & BT_FORWARD then
			inputofs = inputofs/2
		elseif consoleplayer.cmd.buttons & BT_BACKWARD then
			inputofs = inputofs/2 + ANGLE_180
		end

		local camangle = r.realangle + r.angofs + inputofs
		P_MoveOrigin(ghostcam,
			r.mo.x - P_ReturnThrustX(camangle, 160*mapobjectscale) - P_ReturnThrustX(camangle+ANGLE_90, r.angofs/256),
			r.mo.y - P_ReturnThrustY(camangle, 160*mapobjectscale) - P_ReturnThrustY(camangle+ANGLE_90, r.angofs/256),
			r.mo.z + 75*mapobjectscale
		)
		ghostcam.angle = camangle
		consoleplayer.awayviewmobj = ghostcam
		consoleplayer.awayviewaiming = -ANG10
		consoleplayer.awayviewtics = 2
		if leveltime == starttime then
			S_StopMusic()
		elseif leveltime == (starttime + TICRATE/2) then
			S_ChangeMusic(mapheaderinfo[gamemap].musname, true, consoleplayer)
			S_ShowMusicCredit()
		end
	end
end)

----------------------------------------------------------------------

local function GetKartSpeed(kartspeed, scale)
	local g_cc

	if gamespeed == 0 then
		g_cc = 53248 + 3072
	elseif gamespeed == 2 then
		g_cc = 77824 + 3072
	else
		g_cc = 65536 + 3072
	end

	local k_speed = 150 + kartspeed*3

	return FixedMul(FixedMul(k_speed<<14, g_cc), scale)
end

local function FakeSpeedometer(speed, scale)
	local dp = CV_FindVar("kartdisplayspeed")
	if dp.value == 1 then
		return string.format("%3d KM/H", FixedDiv(FixedMul(speed, 142371), mapobjectscale)/FRACUNIT)
	elseif dp.value == 2 then
		return string.format("%3d MPH", FixedDiv(FixedMul(speed, 88465), mapobjectscale)/FRACUNIT)
	elseif dp.value == 3 then
		return string.format("%3d FU/T", FixedDiv(speed, mapobjectscale)/FRACUNIT)
	else
		return string.format("%3d %%", (FixedDiv(speed, FixedMul(GetKartSpeed(consoleplayer.kartspeed, scale), 62914))*100)/FRACUNIT)
	end
end

hud.add(function(v, p)
	if ghostwatching then
		local flags = V_ALLOWLOWERCASE|V_HUDTRANS
		v.drawString(160, 16, "Watching:", flags, "center")
		v.drawString(160, 24, ghostwatching.name, flags|V_YELLOWMAP, "center")
		local speed = FakeSpeedometer(FixedHypot(ghostwatching.gmomx, ghostwatching.gmomy), ghostwatching.mo.scale)
		local color
		if ghostwatching.driftboost > 50 then
			color = V_PURPLEMAP
		elseif ghostwatching.driftboost > 20 then
			color = V_REDMAP
		elseif ghostwatching.driftboost then
			color = V_BLUEMAP
		end
		flags = $ | V_MONOSPACE
		v.drawString(160, 161, speed, flags, "center")
		if color then
			flags = ($ & ~V_HUDTRANS) | V_HUDTRANSHALF
			v.drawString(160, 161, speed, flags|color, "center")
		end
	end

	if true then return end
	local _, g = next(recorders)
	if g then
		v.drawString(240, 32, "FX: "..(g.fakex/FRACUNIT))
		v.drawString(240, 40, "FY: "..(g.fakey/FRACUNIT))
		v.drawString(240, 48, "FZ: "..(g.fakez/FRACUNIT))
		v.drawString(240, 56, "FA: "..(g.fakea/ANG1))
	end

	local r = next(replayers)
	if r then
		v.drawString(240, 72, "GX: "..(r.mo.x/FRACUNIT))
		v.drawString(240, 80, "GY: "..(r.mo.y/FRACUNIT))
		v.drawString(240, 88, "GZ: "..(r.mo.z/FRACUNIT))
		v.drawString(240, 96, "GA: "..(r.mo.angle/ANG1))
		local patch = v.cachePatch("BLANKLVL")
		v.drawOnMinimap(r.mo.x, r.mo.y, FixedDiv(10, patch.height), patch)
	end
end)
