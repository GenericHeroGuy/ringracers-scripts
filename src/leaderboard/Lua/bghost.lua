-- binary ghosts

---- Imported functions ----

-- lb_common.lua
local StringReader = lb_string_reader
local StringWriter = lb_string_writer
local getThrowDir = lb_throw_dir
local ghost_t = lb_ghost_t

-- lb_store.lua
local ReadGhost = lb_read_ghost
local DeleteGhost = lb_delete_ghost

-----------------------------

local RINGS = VERSION == 2
local BT_CUSTOM1 = RINGS and 1<<13 or BT_CUSTOM1
local BT_CUSTOM2 = RINGS and 1<<14 or BT_CUSTOM2
local BT_CUSTOM3 = RINGS and 1<<15 or BT_CUSTOM3
local TURNING = RINGS and "turning" or "driftturn"
local V_ALLOWLOWERCASE = V_ALLOWLOWERCASE or 0
local FIRSTRAINBOWCOLOR = SKINCOLOR_PINK

local cv_maxsize = CV_RegisterVar({
	name = "lb_ghost_maxsize",
	flags = CV_NETVAR,
	defaultvalue = 50000,
	PossibleValue = { MIN = 0, MAX = 65535 }
})

local recorders = {}

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
-- kart
local FS_SQUISH = 12
local FS_POGO = 13
-- rings
local FS_DRIFTLO = 12
local FS_DRIFTLI = 13
local FS_DRIFTRO = 14
local FS_DRIFTRI = 15

local REALTOFAKE = RINGS and {
	[S_KART_STILL] = FS_STND,
	[S_KART_STILL_L] = FS_STNDL,
	[S_KART_STILL_R] = FS_STNDR,
	[S_KART_STILL_GLANCE_L] = FS_STND,
	[S_KART_STILL_GLANCE_R] = FS_STND,
	[S_KART_STILL_LOOK_L] = FS_STND,
	[S_KART_STILL_LOOK_R] = FS_STND,
	[S_KART_SLOW] = FS_WALK,
	[S_KART_SLOW_L] = FS_WALKL,
	[S_KART_SLOW_R] = FS_WALKR,
	[S_KART_SLOW_GLANCE_L] = FS_WALK,
	[S_KART_SLOW_GLANCE_R] = FS_WALK,
	[S_KART_SLOW_LOOK_L] = FS_WALK,
	[S_KART_SLOW_LOOK_R] = FS_WALK,
	[S_KART_FAST] = FS_RUN,
	[S_KART_FAST_L] = FS_RUNL,
	[S_KART_FAST_R] = FS_RUNR,
	[S_KART_FAST_GLANCE_L] = FS_RUN,
	[S_KART_FAST_GLANCE_R] = FS_RUN,
	[S_KART_FAST_LOOK_L] = FS_RUN,
	[S_KART_FAST_LOOK_R] = FS_RUN,
	[S_KART_DRIFT_L] = FS_DRIFTL,
	[S_KART_DRIFT_L_OUT] = FS_DRIFTLO,
	[S_KART_DRIFT_L_IN] = FS_DRIFTLI,
	[S_KART_DRIFT_R] = FS_DRIFTR,
	[S_KART_DRIFT_R_OUT] = FS_DRIFTRO,
	[S_KART_DRIFT_R_IN] = FS_DRIFTRI,
	[S_KART_SPINOUT] = FS_SPIN,
	[S_KART_DEAD] = FS_SPIN,
} or {
	[S_KART_STND1] = FS_STND,
	[S_KART_STND2] = FS_STND,
	[S_KART_STND1_L] = FS_STNDL,
	[S_KART_STND2_L] = FS_STNDL,
	[S_KART_STND1_R] = FS_STNDR,
	[S_KART_STND2_R] = FS_STNDR,
	[S_KART_WALK1] = FS_WALK,
	[S_KART_WALK2] = FS_WALK,
	[S_KART_WALK1_L] = FS_WALKL,
	[S_KART_WALK2_L] = FS_WALKL,
	[S_KART_WALK1_R] = FS_WALKR,
	[S_KART_WALK2_R] = FS_WALKR,
	[S_KART_RUN1] = FS_RUN,
	[S_KART_RUN2] = FS_RUN,
	[S_KART_RUN1_L] = FS_RUNL,
	[S_KART_RUN2_L] = FS_RUNL,
	[S_KART_RUN1_R] = FS_RUNR,
	[S_KART_RUN2_R] = FS_RUNR,
	[S_KART_DRIFT1_L] = FS_DRIFTL,
	[S_KART_DRIFT2_L] = FS_DRIFTL,
	[S_KART_DRIFT1_R] = FS_DRIFTR,
	[S_KART_DRIFT2_R] = FS_DRIFTR,
	[S_KART_SPIN] = FS_SPIN,
	[S_KART_PAIN] = FS_SPIN,
	[S_KART_SQUISH] = FS_SQUISH,
}

local FAKEFRAMES = RINGS and {
	[FS_STND] = SPR2_STIN,
	[FS_STNDL] = SPR2_STIL,
	[FS_STNDR] = SPR2_STIR,
	[FS_WALK] = SPR2_SLWN,
	[FS_WALKL] = SPR2_SLWL,
	[FS_WALKR] = SPR2_SLWR,
	[FS_RUN] = SPR2_FSTN,
	[FS_RUNL] = SPR2_FSTL,
	[FS_RUNR] = SPR2_FSTR,
	[FS_DRIFTL] = SPR2_DRLN,
	[FS_DRIFTLO] = SPR2_DRLO,
	[FS_DRIFTLI] = SPR2_DRLI,
	[FS_DRIFTR] = SPR2_DRRN,
	[FS_DRIFTRO] = SPR2_DRRO,
	[FS_DRIFTRI] = SPR2_DRRI,
	[FS_SPIN] = SPR2_SPIN,
} or {
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
			print(string.format("\x82WARNING:\x80 SA skin %s has too many frames, animations will probably break", skin))
			for i = #int, 17, -1 do
				int[i] = nil
			end
		end

		table.sort(int)
		sacache[defs] = int
	end
	return sacache[defs]
end

local function translate(p, str)
	if RINGS then
		if str == "driftend" then
			return p.pflags & PF_DRIFTEND
		elseif str == "getsparks" then
			return p.pflags & PF_GETSPARKS
		elseif str == "aizdriftstrat" then
			return p.aizdriftstraft -- the gunching of 2021 and its consequences
		else
			return p[str]
		end
	else
		return p.kartstuff[_G["k_"..str]]
	end
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
		if (flags == FS_DRIFTL or flags == FS_DRIFTR) and translate(player, "driftend") then
			frame = FS_STND
		elseif not RINGS and player.kartstuff[k_pogospring] then
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
		if (not RINGS and framenum == FS_POGO) or framenum == FS_SPIN then
			fspecial = "spin"
		elseif framenum == FS_DRIFTL or RINGS and (framenum == FS_DRIFTLO or framenum == FS_DRIFTLI) then
			fspecial = "driftl"
		elseif framenum == FS_DRIFTR or RINGS and (framenum == FS_DRIFTRO or framenum == FS_DRIFTRI) then
			fspecial = "driftr"
		end
		if RINGS then
			return fs, fspecial
		else
			return fs[(leveltime % #fs) + 1], fspecial
		end
	end
end

-- ghost specials
--local GS_NOP = 0x80
local GS_SPARKS0 = 0x81 -- RR gray sparks
local GS_NOSPARKS = 0x82 -- removes drift sparks
local GS_SPARKS1 = 0x83 -- kart blue sparks, RR yellow sparks
local GS_SPARKS2 = 0x84 -- kart red sparks, RR orange sparks
local GS_SPARKS3 = 0x85 -- RR blue sparks
local GS_SPARKS4 = 0x86 -- kart rainbow sparks, RR rainbow sparks
local GS_DRIFTBOOST = 0x87 -- get drift boost (implies GS_NOSPARKS)
local GS_BOOSTFLAME = 0x88 -- boostflame (formerly sneaker boost)
local GS_NOITEM = 0x89 -- lost item
local GS_ROULETTE = 0x8a -- started item roulette
local GS_GETITEM = 0x8b -- rolled an item
local GS_USESNEAKER = 0x8c -- combo of BOOSTFLAME and NOITEM
local GS_RESPAWN = 0x8d -- respawn lasers AKA lightsnake
local GS_SLIPTIDE = 0x8e -- you're slippin' an' tidin'!
local GS_USERING = 0x8f -- yummy!
local GS_SPINDASH = 0x90 -- RR charging spindash
local GS_WAVEDASH = 0x91 -- RR wavedash charged
local GS_FASTFALL = 0x92 -- RR fastfall
local GS_TRICKED = 0x93 -- CATHOLOCISM BLAST!
local GS_TRICKCHARGE = 0x94 -- RR trick charge
local GS_DEATH = 0x95 -- RR death sprite (i'm outta fakestates so...)
local GS_ACROTRICK = 0x96 -- acrobasics trick spin
local GS_FAILSAFEBOOST = 0x97 -- RR failsafe boost
local GS_RINGBOX = 0x98 -- RR ringbox roulette
local GS_GETBAR = 0x99 -- BAR
local GS_GETBAR2 = 0x9a -- BAR2
local GS_GETBAR3 = 0x9b -- BAR3
local GS_GETRING = 0x9c -- RING
local GS_GETSEVEN = 0x9d -- 7
local GS_GETJACKPOT = 0x9e -- JACKPOT!
local GS_SUPERRING = 0x9f -- RR ring award (1 parameter byte)
local GS_GRAVFLIP = 0xa0 -- gravity flip

local GSB_FASTLINES = 0x40 -- go fast

local tins = table.insert
local pickupring
local pickupbox
local pickupfailsafe -- this name doesn't even make sense but might as well follow the theme

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
	str = string.char(flags)..$

	-- and now, the specials
	local specials = {}
	local ks = player.kartstuff

	local function testspec(special, current, last)
		-- type issues.......
		if (current and not last) or (not current and last) then
			tins(specials, special)
		end
	end

	if ghost.boostflame and ghost.boostflame.valid then
		if ghost.boostflame.movecount > ghost.lastsneaker then
			tins(specials, GS_BOOSTFLAME)
		end
		ghost.lastsneaker = ghost.boostflame.movecount
	end

	local drift, driftcharge = translate(player, "drift"), translate(player, "driftcharge")
	if player.playerstate == PST_LIVE then
		local dsv = K_GetKartDriftSparkValue(player)
		if driftcharge >= dsv*4 then
			if ghost.lastspark ~= 4 then tins(specials, GS_SPARKS4) end
			ghost.lastspark = 4
		elseif RINGS and driftcharge >= dsv*3 then
			if ghost.lastspark ~= 3 then tins(specials, GS_SPARKS3) end
			ghost.lastspark = 3
		elseif driftcharge >= dsv*2 then
			if ghost.lastspark ~= 2 then tins(specials, GS_SPARKS2) end
			ghost.lastspark = 2
		elseif driftcharge >= dsv then
			if ghost.lastspark ~= 1 then tins(specials, GS_SPARKS1) end
			ghost.lastspark = 1
		elseif driftcharge < 0 then
			if ghost.lastspark ~= -1 then tins(specials, GS_SPARKS0) end
			ghost.lastspark = -1
		end
	end
	if ghost.lastspark and (not driftcharge or player.playerstate ~= PST_LIVE) then
		local spinout
		if RINGS then
			spinout = P_PlayerInPain(player)
		else
			spinout = ks[k_spinouttimer] or ks[k_squishedtimer]
		end
		local getsparks = translate(player, "getsparks")
		if not spinout -- can't be damaged
		   and abs(drift) ~= 5 -- must have released it
		   and player.playerstate == PST_LIVE -- must be alive
		   and (RINGS or not (player.mo.eflags & MFE_JUSTBOUNCEDWALL)) -- in kart, can't touch a wall
		   and (RINGS or getsparks) -- in kart, must be able to build sparks
		   and (not RINGS or drift) then -- in RR, can't have lost it due to zero speed
		                                 -- (in kart, releasing drift in midair resets k_drift)
			tins(specials, GS_DRIFTBOOST)
		else
			tins(specials, GS_NOSPARKS)
		end
		ghost.lastspark = 0
	end

	local fastlines
	if RINGS then
		fastlines = (player.sneakertimer or player.ringboost or player.driftboost --[[or player.startboost lmao]]
		             or player.eggmanexplode or player.trickboost or player.gateboost or player.wavedashboost)
		            and player.speed > 0
	else
		fastlines = (ks[k_sneakertimer] or ks[k_driftboost] or ks[k_startboost])
		            and player.speed > 0
	end
	local dofastlines = (fastlines and not ghost.lastfastlines) or (not fastlines and ghost.lastfastlines)
	ghost.lastfastlines = fastlines

	local respawn
	if RINGS then
		respawn = player.respawn.state and player.respawn.timer > 0
	else
		respawn = ks[k_respawn] > 1
	end
	testspec(GS_RESPAWN, respawn, ghost.lastrespawn)
	ghost.lastrespawn = respawn

	local roulette = not RINGS and ks[k_itemroulette]
	if roulette and not ghost.lastroulette then
		tins(specials, GS_ROULETTE)
	end
	local itemtype, itemamount = translate(player, "itemtype"), translate(player, "itemamount")
	local havesneaker = itemtype == KITEM_SNEAKER and itemamount > 0
	if havesneaker and not ghost.havesneaker then
		tins(specials, GS_GETITEM)
	elseif not havesneaker and ghost.havesneaker then
		local combined = false
		for i, v in ipairs(specials) do
			if v == GS_BOOSTFLAME then
				specials[i] = GS_USESNEAKER
				combined = true
				break
			end
		end
		if not combined then
			tins(specials, GS_NOITEM)
		end
	end
	ghost.lastroulette = roulette
	ghost.havesneaker = havesneaker

	local aizdriftstrat = translate(player, "aizdriftstrat")
	local sliptide = aizdriftstrat and not drift and P_IsObjectOnGround(player.mo) and player.playerstate == PST_LIVE
	testspec(GS_SLIPTIDE, sliptide, ghost.lastsliptide)
	ghost.lastsliptide = sliptide

	if RINGS then
		local usedring = pickupring[player]
		if usedring then
			tins(specials, GS_USERING)
		end

		local spindash = player.spindash
		testspec(GS_SPINDASH, spindash, ghost.lastspindash)
		ghost.lastspindash = spindash

		local trick = player.trickpanel > 1 -- TRICKSTATE_READY
		testspec(GS_TRICKED, trick, ghost.lasttrickpanel)
		ghost.lasttrickpanel = trick

		local trickcharge = player.trickcharge
		testspec(GS_TRICKCHARGE, trickcharge, ghost.lasttrickcharge)
		ghost.lasttrickcharge = trickcharge

		local death = player.mo.state == S_KART_DEAD
		testspec(GS_DEATH, death, ghost.lastdeath)
		ghost.lastdeath = death

		local wavedash = player.wavedash > 60 -- HIDEWAVEDASHCHARGE
		testspec(GS_WAVEDASH, wavedash, ghost.lastwavedash)
		ghost.lastwavedash = wavedash

		local fastfall = player.fastfall
		testspec(GS_FASTFALL, fastfall, ghost.lastfastfall)
		ghost.lastfastfall = fastfall

		local gotbox = pickupbox[player]
		if gotbox == true then
			tins(specials, GS_ROULETTE)
		end
		if gotbox == false then
			tins(specials, GS_RINGBOX)
		end

		local delay = player.ringboxdelay
		if delay and not ghost.lastringboxdelay then
			tins(specials, GS_GETBAR + player.ringboxaward)
		end
		ghost.lastringboxdelay = delay

		local superring = player.superring
		if superring > ghost.lastsuperring then
			if superring > 255 then
				print("That's a lot of rings! How am I supposed to fit that in just a byte???")
			else
				tins(specials, GS_SUPERRING)
				tins(specials, superring)
			end
		end
		ghost.lastsuperring = superring

		local usedfailsafe = pickupfailsafe[player]
		if usedfailsafe then
			tins(specials, GS_FAILSAFEBOOST)
		end

		-- XXX: there is literally no way to tell if the roulette gets cancelled
	end

	-- acro support!
	-- boy am i glad i kept this variable after the refactor
	local tricked = player.hastricked
	testspec(GS_ACROTRICK, tricked, ghost.lasttricked)
	ghost.lasttricked = tricked

	local gravflip = player.mo.eflags & MFE_VERTICALFLIP
	testspec(GS_GRAVFLIP, gravflip, ghost.lastgravflip)
	ghost.lastgravflip = gravflip

	if dofastlines then
		if specials[1] then
			specials[1] = $ | GSB_FASTLINES
		else
			tins(specials, 0x80 | GSB_FASTLINES)
		end
	end

	str = string.char(unpack(specials))..$
	if #ghost.data + #str > cv_maxsize.value then
		print("\x82WARNING:\x80 Ghost is too long! Stopping recording")
		recorders[player] = nil
	else
		ghost.data = $..str
	end
end

if RINGS then
-- oh boy, gotta detect ring usage
local maybering
-- and air failsafes
local maybefailsafe
local prevfailsafe = {}
addHook("PreThinkFrame", function()
	if not LB_IsRunning() then return end
	maybering = nil
	maybefailsafe = nil
	pickupring = {}
	-- and item box pops
	pickupbox = {}
	pickupfailsafe = {}
	for p in players.iterate do
		prevfailsafe[p] = p.pflags & PF_AIRFAILSAFE
	end
end)
addHook("MobjSpawn", function(mo)
	maybering = mo
end, MT_RING)
addHook("MobjSpawn", function(mo)
	maybefailsafe = mo
end, MT_DRIFTEXPLODE)
addHook("PlayerThink", function(p)
	if not LB_IsRunning() then return end
	if maybering and maybering.extravalue2 == 1 and maybering.state == S_FASTRING1 then
		pickupring[p] = true
	end
	if maybefailsafe and maybefailsafe.extravalue1 == 0 and not (p.pflags & PF_AIRFAILSAFE) and prevfailsafe[p] then
		pickupfailsafe[p] = true
	end
	maybering = nil
	maybefailsafe = nil
end)

local function P_IsPickupCheesy(player, type)
	if CV_FindVar("debugcheese").value then
		return false
	end

	if gametyperules & GTR_CATCHER then
		return false
	end

	if player.lastpickupdistance and player.lastpickuptype == type then
		-- unsigned? no thanks, i'll just skip ringbox specials
		if player.distancetofinish < 0 or player.lastpickupdistance < 0 then
			return true
		end
		local distancedelta = player.lastpickupdistance - player.distancetofinish
		if distancedelta < 2500
			return true
		end
	end
	return false
end
addHook("TouchSpecial", function(special, toucher)
	if not LB_IsRunning() then return end
	local player = toucher.player
	local cheesetype = (special.flags2 & MF2_BOSSDEAD) and 2 or 1 // perma ring box

	if not P_CanPickupItem(player, 1) then
		return
	end
	if P_IsPickupCheesy(player, cheesetype) then
		return
	end

	local specialstate = special.state
	pickupbox[player] = specialstate >= S_RANDOMITEM1 and specialstate <= S_RANDOMITEM12
end, MT_RANDOMITEM)
end -- if RINGS

-- start recording ghost data for player
local function StartRecording(player)
	recorders[player] = {
		data = "",
		startofs = leveltime,
		lastsneaker = 0,
		lastspark = 0,
		lastfastlines = false,
		lastrespawn = false,
		lastroulette = false,
		havesneaker = false,
		lastsliptide = false,
		lastspindash = 0,
		lasttrickpanel = 0,
		lasttrickcharge = false,
		lastdeath = false,
		lasttricked = false,
		lastsuperring = 0,
		lastringboxdelay = 0,
		lastgravflip = 0,

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
	local startofs = recorders[player].startofs
	recorders[player] = nil
	return ghost_t(data, startofs)
end
rawset(_G, "lb_ghost_stop_recording", StopRecording)

-- returns true if a ghost is being recorded for the player
local function IsRecording(player)
	return recorders[player] ~= nil
end
rawset(_G, "lb_ghost_is_recording", IsRecording)

addHook("MapChange", function()
	recorders = {}
end)

-- can't rely on sneakertimer alone to check for boostflames...
-- and well, GS_SNEAKER is only used for the boostflame now anyways, so fuck it
addHook("MobjThinker", function(mo)
	local player = mo.target and mo.target.player
	if recorders[player] then
		recorders[player].boostflame = mo
	end
end, MT_BOOSTFLAME)

addHook("ThinkFrame", function()
	if defrosting then return end
	for player, g in pairs(recorders) do
		if not player.valid or player.spectator then StopRecording(player); continue end

		-- hoooly fuck this is stupid
		-- but after hours and hours of trying random shit until something worked, this is what worked
		-- so just deal with it
		-- i have no clue what to do about the whiplash from teleports

		local mold = g.momlog
		local angle = player.mo.angle
		if RINGS and player.respawn.state == 1 then
			angle = player.drawangle
		end
		local mnew = { x = player.mo.x - g.fakex, y = player.mo.y - g.fakey, z = player.mo.z - g.fakez, a = angle - g.fakea }
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
local ghostwatching, ghostcam, ghostmenu, ghostmenusel

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

-- plays the ghost(s) stored in the provided record
local function StartPlaying(record)
	if isdedicatedserver then
		return true
	end

	local ghosts = ReadGhost(record)
	if not ghosts then
		return false
	end
	if #record.players ~= #ghosts then
		error("Player count doesn't match ghost count")
	end
	local reps = {}
	for i, recplayer in ipairs(record.players) do
		local mo = SpawnLocal(0, 0, 0, MT_THOK)
		mo.flags = MF_NOTHINK|MF_NOSECTOR|MF_NOBLOCKMAP|MF_NOGRAVITY|MF_NOCLIP|MF_NOCLIPTHING|MF_NOCLIPHEIGHT|MF_DONTENCOREMAP
		mo.sprite = SPR_PLAY
		mo.skin = recplayer.skin
		mo.color = recplayer.color

		local rep = setmetatable({
			file = StringReader(ghosts[i].data),
			name = recplayer.name,
			startofs = ghosts[i].startofs,
			starttime = record.starttime,
			curtic = 0, -- ghost's leveltime
			paused = false,
			startpaused = false,
			fastforward = false,
			doforward = false,
			rewinding = false,
			dorewind = false,
			ticlog = {},
			mo = mo,
			gmomx = 0,
			gmomy = 0,
			gmomz = 0,
			gmoma = 0,
			realangle = 0,
			recid = record.id,

			fspecial = 0,
			lastfspecial = 0,
			fakeframe = 0,
			angofs = 0,

			-- combi
			combilink = {},
			combipartner = false,

			-- purely visual, just for showing vfx
			boostflame = false,
			driftspark = 0,
			drifthilite = 0,
			drifthilitecolor = 0,
			fastlines = false,
			respawning = false,
			hasitem = 0,
			sliptiding = false,
			driftdir = 0,
			sliptilt = 0,
			spindashing = false,
			wavedashing = false,
			wavedashspin = false,
			fastfalling = false,
			fastfallwave = false,
			tricking = false,
			trickcharged = false,
			trickaura = false,
			dead = false,
			acrotrick = false,
			-- i don't like making assumptions, but i don't have much better options
			-- for showing ring awards, so... lua scripts be damned
			ringaward = 0,
			nextringaward = 0,
			fakeawardtimer = 0,
			gravityflip = false,
		}, { __index = do error("no", 2) end, __newindex = do error("no", 2) end })
		table.insert(reps, rep)
		replayers[rep] = true
	end

	if record.flags & F_COMBI then
		for i, g in ipairs(reps) do
			local partner = reps[(i % #reps)+1]
			g.combipartner = partner.mo
			SpawnCombiLink(g)
		end
	end

	return true
end
rawset(_G, "lb_ghost_start_playing", function(record)
	local ok, ret = pcall(StartPlaying, record)
	if not ok then
		print("\x82WARNING:\x80 Failed to start ghost", ret)
		if record and record.id ~= nil then
			print("Deleting ghost "..record.id)
			DeleteGhost(record.id)
		end
		return false -- download again I guess
	else
		return ret
	end
end)

local function StopWatching(change)
	if ghostwatching == nil then return end
	ghostwatching = nil
	if not change then
		consoleplayer.awayviewmobj = nil
		consoleplayer.awayviewtics = 0
	end
	hud.enable("time")
	hud.enable("textspectator")
	-- keep the ghostcam
end

local function NextWatch()
	local ghost = ghostwatching
	local start = ghost
	repeat
		if (ghost and not start) or not replayers[ghost] then start = next(replayers) end -- no infinite loops please
		ghost = next(replayers, ghost) or next(replayers) -- loop de loop
		if ghost and ghost.curtic >= ghost.startofs then
			ghostwatching = ghost
			return
		end
	until ghost == ghostwatching or not ghost or ghost == start
	-- nothing appropriate.
	ghostwatching = nil
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
	StopWatching(true)
end)

local function SpawnDriftSparks(r, direction)
	if leveltime % 2 == 1 then
		return
	end
	if not RINGS then
		if r.mo.eflags & MFE_VERTICALFLIP and r.mo.z + r.mo.height < r.mo.ceilingz - mapobjectscale*8 then
			return
		elseif not (r.mo.eflags & MFE_VERTICALFLIP) and r.mo.z > r.mo.floorz + mapobjectscale*8 then
			return
		end
	end

	local pmo = r.mo
	local color
	if r.driftspark == 1 then
		color = RINGS and SKINCOLOR_GOLD or SKINCOLOR_SAPPHIRE
	elseif r.driftspark == 2 then
		color = SKINCOLOR_KETCHUP
	elseif r.driftspark == 3 then
		color = SKINCOLOR_BLUE
	elseif r.driftspark == 4 then
		color = RINGS and FIRSTRAINBOWCOLOR + (leveltime % (FIRSTSUPERCOLOR - FIRSTRAINBOWCOLOR)) or 1 + (leveltime % (MAXSKINCOLORS-1))
	elseif r.driftspark == -1 then
		color = SKINCOLOR_SILVER
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
		P_SetOrigin(spark, spark.x, spark.y, spark.z) -- interp moment
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
		r.mo.z + (r.mo.height/2 + (randomrange(-20,20) * r.mo.scale))*P_MobjFlip(r.mo),
		MT_FASTLINE)
	fast.angle = R_PointToAngle2(0, 0, r.gmomx, r.gmomy)
	fast.momx = 3*r.gmomx/4
	fast.momy = 3*r.gmomy/4
	fast.momz = 3*r.gmomz/4
	K_MatchGenericExtraFlags(fast, r.mo)
	P_SetOrigin(fast, fast.x, fast.y, fast.z) -- interp moment
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

local function SpawnAIZDust(r, direction)
	if leveltime % 2 == 1 then
		return
	end

	local travelangle = R_PointToAngle2(0, 0, r.gmomx, r.gmomy)
	local stratangle = ANGLE_45*direction

	local newx = r.mo.x + P_ReturnThrustX(travelangle - stratangle, 24*r.mo.scale)
	local newy = r.mo.y + P_ReturnThrustY(travelangle - stratangle, 24*r.mo.scale)
	local spark = P_SpawnMobj(newx, newy, r.mo.z, MT_AIZDRIFTSTRAT)

	spark.angle = travelangle + stratangle*2
	spark.scale = 3*r.mo.scale/4

	spark.momx = 6*r.gmomx/5
	spark.momy = 6*r.gmomy/5
	//spark.momz = r.gmomz/2

	K_MatchGenericExtraFlags(spark, r.mo)
	P_SetOrigin(spark, spark.x, spark.y, spark.z) -- interp moment
end

local function SpawnSpindashDust(r)
	local rad = FixedDiv(FixedHypot(r.mo.radius, r.mo.radius), r.mo.scale)

	for i = 0, 1 do
		local hmomentum = randomrange(6, 12) * r.mo.scale
		local vmomentum = randomrange(2, 6) * r.mo.scale

		local ang = r.mo.angle + ANGLE_180

		if i & 1 then
			ang = $ - ANGLE_45
		else
			ang = $ + ANGLE_45
		end

		local dust = P_SpawnMobjFromMobj(r.mo,
			FixedMul(rad, cos(ang)),
			FixedMul(rad, sin(ang)),
			0, MT_SPINDASHDUST
		)

		dust.momx = FixedMul(hmomentum, cos(ang))
		dust.momy = FixedMul(hmomentum, sin(ang))
		dust.momz = vmomentum * P_MobjFlip(dust)
	end
end

local function SpawnDEZLasers(r)
	if RINGS and FixedHypot(FixedHypot(r.gmomx, r.gmomy), r.gmomz) > mapobjectscale*32 then
		-- i guess i COULD read ahead of the ghost data to spawn the particles ahead of you...
		-- but that's a can of worms i'm not gonna open tonight
		local mo = P_SpawnMobj(r.mo.x, r.mo.y, r.mo.z, MT_DEZLASER)
		mo.state = S_DEZLASER_TRAIL3
		if r.mo.eflags & MFE_VERTICALFLIP then
			mo.eflags = $ | MFE_VERTICALFLIP
		end
		mo.target = r.mo
		mo.angle = R_PointToAngle2(0, 0, r.gmomx, r.gmomy) + ANGLE_90
	elseif not (leveltime % 8) then
		for i = 0, 7 do
			local newangle = ANGLE_45*i
			local newx = r.mo.x + P_ReturnThrustX(newangle, 31*mapobjectscale)
			local newy = r.mo.y + P_ReturnThrustY(newangle, 31*mapobjectscale)
			local newz = r.mo.z + (r.mo.eflags & MFE_VERTICALFLIP and r.mo.height or 0)

			local mo = P_SpawnMobj(newx, newy, newz, MT_DEZLASER)
			if r.mo.eflags & MFE_VERTICALFLIP then
				mo.eflags = $ | MFE_VERTICALFLIP
			end
			mo.target = r.mo
			mo.angle = newangle+ANGLE_90
			mo.momz = (8*mapobjectscale) * P_MobjFlip(r.mo)
		end
	end
end

local SpawnRing

-- need a state to cycle sprite2 frames in ring racers
freeslot("S_LBGHOST")
local S_LBGHOST = S_LBGHOST
local ghoststate = states[S_LBGHOST]
ghoststate.sprite = SPR_PLAY
ghoststate.tics = -1 -- easy to forget

local booleans = {
	[GS_RESPAWN] = "respawning",
	[GS_SLIPTIDE] = "sliptiding",
	[GS_SPINDASH] = "spindashing",
	[GS_WAVEDASH] = "wavedashing",
	[GS_FASTFALL] = "fastfalling",
	[GS_TRICKED] = "tricking",
	[GS_TRICKCHARGE] = "trickcharged",
	[GS_DEATH] = "dead",
	[GS_ACROTRICK] = "acrotrick",
	[GS_GRAVFLIP] = "gravityflip",
}

local function PlayGhostTic(r)
	if r.curtic < r.startofs then
		r.curtic = $ + 1
		return
	elseif r.curtic == r.startofs then
		r.mo.flags = $ & ~MF_NOSECTOR
	end

	local flags
	while true do -- for all the specials
		flags = r.file:read8()
		if not (flags & 0x80) then break end
		if flags & GSB_FASTLINES then
			r.fastlines = not $
			flags = $ & ~GSB_FASTLINES
		end
		if flags >= GS_SPARKS0 and flags <= GS_SPARKS4 then
			r.driftspark = flags - GS_NOSPARKS
		elseif flags == GS_DRIFTBOOST then
			r.drifthilite = 0
			r.drifthilitecolor = r.driftspark
			r.driftspark = 0
		elseif flags == GS_BOOSTFLAME or flags == GS_USESNEAKER then
			if not (r.boostflame and r.boostflame.valid) then
				r.boostflame = P_SpawnMobj(r.mo.x, r.mo.y, r.mo.z, MT_THOK)
				r.boostflame.scale = r.mo.scale
			end
			r.boostflame.state = S_BOOSTFLAME
			r.boostflame.frame = $ | FF_TRANS40
			if flags == GS_USESNEAKER then
				r.hasitem = 0
			end
		elseif flags == GS_USERING then
			SpawnRing(r, true)
		elseif flags >= GS_NOITEM and flags <= GS_GETITEM then
			r.hasitem = flags - GS_NOITEM
		elseif flags >= GS_RINGBOX and flags <= GS_GETJACKPOT then
			r.hasitem = GS_RINGBOX - flags - 1 -- we're going negative folks!
			r.fakeawardtimer = TICRATE
		elseif flags == GS_SUPERRING then
			r.ringaward = r.file:read8()
		elseif flags == GS_FAILSAFEBOOST then
			local dust = P_SpawnMobj(r.mo.x, r.mo.y, r.mo.z, MT_DRIFTDUST)
			dust.colorized = true
			dust.color = SKINCOLOR_MOSS
			dust.momz = 8*mapobjectscale
			dust.scale = 2*mapobjectscale
		elseif flags ~= 0x80 then
			local var = booleans[flags]
			r[var] = not $
		end
	end

	local dx = (flags & 0x10) and BloatToFixed(r.file:read8())
	local dy = (flags & 0x10) and BloatToFixed(r.file:read8())
	local dz = (flags & 0x20) and BloatToFixed(r.file:read8())
	local da = (flags & 0x40) and BloatToFixed(r.file:read8())
	local frame, fspecial = ReadFakeFrame(flags & 0x0f, r.mo.skin)
	if r.dead then frame, fspecial = SPR2_DEAD, "" end
	if RINGS and frame == SPR2_STIL and not P_IsValidSprite2(r.mo, frame) then
		frame = spr2defaults[frame]
	end

	r.fakeframe = flags & 0x0f
	r.fspecial = fspecial
	r.gmomx = $ + dx
	r.gmomy = $ + dy
	r.gmomz = $ + dz
	r.gmoma = $ + da

	P_MoveOrigin(r.mo, r.mo.x + r.gmomx, r.mo.y + r.gmomy, r.mo.z + r.gmomz)
	if RINGS then
		ghoststate.frame = frame | FF_TRANS40
		r.mo.state = S_LBGHOST
	else
		r.mo.frame = frame | FF_TRANS40
	end
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
	local dir = 0
	if fspecial == "driftl" then
		dir = 1
	elseif fspecial == "driftr" then
		dir = -1
	end
	r.driftdir = dir or $ -- for sliptide
	if r.driftspark then
		SpawnDriftSparks(r, r.driftdir)
	end
	if r.fastlines then
		SpawnFastLines(r)
	end
	if r.sliptiding then
		SpawnAIZDust(r, r.driftdir)
	end
	if r.respawning then
		SpawnDEZLasers(r)
	end

	if RINGS then
		if dir then -- drawangle offset for drifting
			r.mo.angle = $ + ANGLE_45*dir
		end

		if r.tricking then
			-- i might have to rethink frame specials
			r.mo.angle = $ + (ANGLE_22h*(leveltime%16))
		end

		if r.trickcharged then
			local aura = r.trickaura
			if not aura then
				aura = SpawnLocal(r.mo.x, r.mo.y, r.mo.z + r.mo.height/2, MT_THOK)
				aura.state = S_CHARGEAURA
				aura.renderflags = RF_PAPERSPRITE|RF_FULLBRIGHT|RF_ADD
				r.trickaura = aura
			end
			P_MoveOrigin(aura, r.mo.x, r.mo.y, r.mo.z + r.mo.height/2)
			aura.frame = (leveltime/2)%5
			aura.angle = leveltime*ANG10
		elseif r.trickaura then
			P_RemoveMobj(r.trickaura)
			r.trickaura = false
		end

		if r.spindashing then
			SpawnSpindashDust(r)
			r.mo.spritexoffset = (leveltime & 1 or -1)*FRACUNIT
			r.mo.spriteyoffset = 3*(leveltime % 3 - 1)*FRACUNIT/2
		else
			r.mo.spritexoffset = 0
			r.mo.spriteyoffset = 0
		end

		if r.sliptiding then
			if abs(r.sliptilt) < ANGLE_22h then
				r.sliptilt = (abs($) + ANGLE_11hh/4)*r.driftdir
			end
		else
			r.sliptilt = $ - $/4
			if abs(r.sliptilt) < ANGLE_11hh / 4 then
				r.sliptilt = 0
			end
		end
		local angle = R_PointToAngle(r.mo.x, r.mo.y) - r.mo.angle
		r.mo.rollangle = FixedMul(r.sliptilt, sin(abs(angle))) + FixedMul(r.sliptilt, cos(angle))
		--r.mo.angle = $ + r.sliptilt*4

		if r.fastfalling then
			if not r.fastfallwave then
				r.fastfallwave = SpawnLocal(r.mo.x, r.mo.y, r.mo.z, MT_THOK)
				r.fastfallwave.state = S_SOFTLANDING1
				r.fastfallwave.flags = $ & ~MF_NOCLIPHEIGHT
				r.fastfallwave.renderflags = RF_NOSPLATBILLBOARD|RF_OBJECTSLOPESPLAT
			end
			local wave = r.fastfallwave
			wave.frame = ($ & ~FF_FRAMEMASK) | (leveltime/4)%5

			if leveltime % 2 then
				wave.renderflags = $ | RF_DONTDRAW
			else
				wave.renderflags = $ & ~RF_DONTDRAW
			end

			// Cast like a shadow on the ground
			P_MoveOrigin(wave, r.mo.x, r.mo.y, r.mo.floorz)
			--wave.standingslope = r.mo.standingslope
			P_TryMove(wave, wave.x, wave.y)

			if r.gmomz < -24 * mapobjectscale then
				// Going down, falling through hoops
				local ghost = P_SpawnGhostMobj(wave)
				-- bruh
				P_SetOrigin(ghost, wave.x, wave.y, wave.z+1)

				ghost.z = r.mo.z
				ghost.momz = -r.gmomz
				--ghost.standingslope = nil
				P_TryMove(ghost, ghost.x, ghost.y)

				ghost.renderflags = wave.renderflags
				ghost.fuse = 16
				ghost.extravalue1 = 1
				ghost.extravalue2 = 0
			end
		elseif r.fastfallwave then
			P_RemoveMobj(r.fastfallwave)
			r.fastfallwave = false
		end

		if r.wavedashing then
			if not r.wavedashspin then
				r.wavedashspin = SpawnLocal(r.mo.x, r.mo.y, r.mo.z, MT_WAVEDASH)
				r.wavedashspin.frame = FF_PAPERSPRITE|FF_TRANS40|H -- H
			end
			local mo = r.wavedashspin
			local angle = R_PointToAngle2(0, 0, r.gmomx, r.gmomy)
			P_MoveOrigin(mo, r.mo.x - FixedMul(40*mapobjectscale, cos(angle)),
			                 r.mo.y - FixedMul(40*mapobjectscale, sin(angle)),
			                 r.mo.z + r.mo.height/2)
			mo.angle = angle + ANGLE_90
			mo.scale = 3*r.mo.scale/2
			mo.rollangle = $ + ANGLE_22h
		elseif r.wavedashspin then
			P_RemoveMobj(r.wavedashspin)
			r.wavedashspin = false
		end

		if r.ringaward then
			r.nextringaward = $ + 1
			local ringrate = 3 - min(2, r.ringaward / 20) // Used to consume fat stacks of cash faster.
			if r.nextringaward >= ringrate then
				SpawnRing(r, false)
				r.nextringaward = 0
				r.ringaward = $ - 1
			end
		end
	end

	if r.acrotrick then
		-- i REALLY need to rethink frame specials
		r.mo.angle = $ + (ANG30*(leveltime%12))
	end

	if r.gravityflip then
		r.mo.eflags = $ | MFE_VERTICALFLIP
	else
		r.mo.eflags = $ & ~MFE_VERTICALFLIP
	end

	r.curtic = $ + 1
end

local errorghost
local function RunGhosts()
	errorghost = nil
	for r in pairs(replayers) do
		errorghost = r
		if RINGS then
			-- pause when ghost touches finish line at the start
			if r.curtic == r.starttime and not r.startpaused then
				r.startpaused = true
				r.paused = true
			end

			-- race started, fast-forward to starttime
			if consoleplayer.onlineta.started and r.curtic <= r.starttime and r.paused then
				r.paused = false
				while r.curtic < r.starttime do
					if r.file:empty() then
						error("Ghost ends before starttime")
					end
					PlayGhostTic(r)
				end
			end
		end
		if not r.paused or r.doforward or r.dorewind then
			if r.doforward and not r.paused then
				r.fastforward = not $
			end

			local numtics = r.fastforward and not r.paused and 3 or 1
			for i = 1, numtics do
				if r.file:empty() then
					StopPlaying(r)
					if not ghostwatching then
						consoleplayer.awayviewtics = 0
						consoleplayer.awayviewmobj = nil
					end
					break
				end

				-- flip the playback direction
				local flip = r.dorewind or r.rewinding and not r.curtic
				if r.paused then
					if r.rewinding then
						flip = r.doforward or not r.curtic
					else
						flip = r.dorewind
					end
				end
				if flip then
					r.dorewind = false
					if r.rewinding then
						r.file:seek(r.ticlog[r.curtic])
					end
					r.rewinding = not $
					P_SetOrigin(r.mo, r.mo.x - r.gmomx, r.mo.y - r.gmomy, r.mo.z - r.gmomz)
					r.realangle = $ - r.gmoma
					r.gmomx = -$
					r.gmomy = -$
					r.gmomz = -$
					r.gmoma = -$
				end

				if r.rewinding then
					r.curtic = $ - 1
					r.file:seek(r.ticlog[r.curtic])
				elseif not r.ticlog[r.curtic] then
					-- log the offsets of all tics for rewinding
					-- should've used a RISC architecture for ghost files :^)
					r.ticlog[r.curtic] = r.file:tell()
				end

				PlayGhostTic(r)
				if r.rewinding then
					r.curtic = $ - 1
				end
			end
			r.doforward = false
			r.dorewind = false
		end
	end

	-- update combi links after all ghosts have moved
	for r in pairs(replayers) do
		errorghost = r
		if r.combipartner and r.combipartner.valid then
			MoveCombiLink(r)
		end
	end
	errorghost = nil -- no more error handling
end

local ghostcustom1 = 0
local ghostcustom2 = 0
local inputleft = 0
local inputright = 0
local inputup = 0
local inputdown = 0

local function menusound()
	S_StartSound(nil, sfx_menu1)
end

local menuoptions = {
	{
		label = function() return "Player" end,
		draw = function(v, x, y, flags, cmap)
			v.draw(x, y, v.cachePatch("M_PNVIEW"), flags, cmap)
		end,
		change = function() NextWatch() end,
	},
	{
		label = function() return ghostwatching.paused and "Resume" or "Pause" end,
		draw = function(v, x, y, flags, cmap)
			v.draw(x, y, v.cachePatch(ghostwatching.paused and "M_PRESUM" or "M_PPAUSE"), flags, cmap)
		end,
		change = function() ghostwatching.paused = not $ end,
	},
	{
		label = function() return ghostwatching.paused and "Play one tic" or "Fast Forward" end,
		draw = function(v, x, y, flags, cmap)
			if ghostwatching.fastforward then
				cmap = v.getColormap(TC_RAINBOW, SKINCOLOR_JAWZ)
			end
			v.draw(x, y, v.cachePatch(ghostwatching.paused and "M_PFADV" or "M_PFFWD"), flags, cmap)
		end,
		change = function() ghostwatching.doforward = true end,
	},
	{
		label = function() return ghostwatching.paused and "Rewind one tic" or "Rewind" end,
		draw = function(v, x, y, flags, cmap)
			if ghostwatching.rewinding then
				cmap = v.getColormap(TC_RAINBOW, SKINCOLOR_JAWZ)
			end
			v.draw(x, y, v.cachePatch(ghostwatching.paused and "M_PSTEPB" or "M_PREW"), flags, cmap)
		end,
		change = function() ghostwatching.dorewind = true end,
	},
}

addHook("ThinkFrame", function()
	if defrosting then return end
	if not consoleplayer or (not isserver and consoleplayer == server) then return end -- joining a server
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

	if consoleplayer.cmd.buttons & BT_CUSTOM1 then
		ghostcustom1 = $ + 1
	else
		ghostcustom1 = 0
	end
	if consoleplayer.cmd.buttons & BT_CUSTOM2 then
		ghostcustom2 = $ + 1
	else
		ghostcustom2 = 0
	end
	if consoleplayer.cmd[TURNING] >= 200 then
		inputright = $ + 1
	else
		inputright = 0
	end
	if consoleplayer.cmd[TURNING] <= -200 then
		inputleft = $ + 1
	else
		inputleft = 0
	end
	local throwdir = getThrowDir(consoleplayer)
	if throwdir == 1 then
		inputup = $ + 1
	else
		inputup = 0
	end
	if throwdir == -1 then
		inputdown = $ + 1
	else
		inputdown = 0
	end

	if ghostcustom1 == 1 then
		ghostmenu = not $
		if ghostmenusel == nil then ghostmenusel = 1 end
	end

	if ghostcustom2 == 1 then
		if not (ghostcam and ghostcam.valid) then
			ghostcam = SpawnLocal(0, 0, 0, MT_THOK)
			ghostcam.flags = MF_NOTHINK|MF_NOSECTOR|MF_NOBLOCKMAP|MF_NOCLIP|MF_NOCLIPHEIGHT|MF_NOCLIPTHING
		end
		NextWatch()
	end

	local ok, err = pcall(RunGhosts)
	if not ok then
		print("\x82WARNING:\x80 Ghost playback error", err)
		if not errorghost then
			print("...but which one was it!?")
			return
		end
		local id = errorghost.recid
		print("Deleting ghost "..id)
		DeleteGhost(id)

		StopPlaying(errorghost)
		if not ghostwatching then
			consoleplayer.awayviewtics = 0
			consoleplayer.awayviewmobj = nil
		end
	end

	if consoleplayer.cmd.buttons & (BT_ACCELERATE|BT_BRAKE|BT_ATTACK|BT_DRIFT) then
		StopWatching()
	end

	local r = ghostwatching
	if r then
		hud.disable("time")
		hud.disable("textspectator")
		local fspecial = not RINGS and r.fakeframe == FS_POGO and r.lastfspecial or r.fspecial
		r.lastfspecial = fspecial
		if fspecial == "driftl" and r.angofs < ANG2 then
			if r.angofs > -ANG30 then r.angofs = $ - ANG1 end
		elseif fspecial == "driftr" and r.angofs > -ANG2 then
			if r.angofs < ANG30 then r.angofs = $ + ANG1 end
		else
			r.angofs = 3*r.angofs/4
		end

		local dist = 170*mapobjectscale
		local height = 80*mapobjectscale

		local inputofs = 0
		if ghostmenu then
			if inputright == 1 then menusound(); ghostmenusel = $ == 1 and #menuoptions or $ - 1 end
			if inputleft == 1 then menusound(); ghostmenusel = $ % #menuoptions + 1 end
			if inputup == 1 then menusound(); menuoptions[ghostmenusel].change(1) end
			if inputdown == 1 then menusound(); menuoptions[ghostmenusel].change(-1) end
		else
			if inputright then
				inputofs = ANGLE_90
			elseif inputleft then
				inputofs = -ANGLE_90
			end
			if inputup then
				if inputofs then
					inputofs = inputofs/2
				else
					height = $ + 200*mapobjectscale
					dist = $ + 50*mapobjectscale
				end
			elseif inputdown then
				inputofs = inputofs/2 + ANGLE_180
			end
		end
		if r.gravityflip then height = -$ end

		local camangle = r.realangle + r.angofs + inputofs
		P_MoveOrigin(ghostcam,
			r.mo.x - P_ReturnThrustX(camangle, dist) - P_ReturnThrustX(camangle+ANGLE_90, FixedMul(r.angofs, mapobjectscale/128)),
			r.mo.y - P_ReturnThrustY(camangle, dist) - P_ReturnThrustY(camangle+ANGLE_90, FixedMul(r.angofs, mapobjectscale/128)),
			r.mo.z + height - (not RINGS and 20*FRACUNIT or 0) + r.mo.height/2
		)
		ghostcam.angle = camangle
		consoleplayer.awayviewmobj = ghostcam
		local pitch = -R_PointToAngle2(0, 0, dist, height/2)
		if RINGS then
			ghostcam.pitch = pitch
		else
			consoleplayer.awayviewaiming = pitch
		end

		-- any higher than 1 and the game segfaults in R_SetupFrame
		-- the camera mobj is client-sided, so if someone joins while you're watching a ghost, you're cooked
		consoleplayer.awayviewtics = 1
	end
end)

if RINGS then
local ringthinkers = {}

function SpawnRing(r, used)
	local ring = SpawnLocal(r.mo.x, r.mo.y, r.mo.z + (used and r.mo.height or 0), MT_THOK)
	ring.state = used and S_FASTRING1 or S_RING
	ring.target = r.mo
	ring.extravalue1 = 1
	ring.frame = $ | FF_TRANS40
	ringthinkers[ring] = used
	if not used then
		ring.angle = r.realangle
	end
end

addHook("ThinkFrame", function()
	for mo, used in pairs(ringthinkers) do
		if not mo.valid then
			ringthinkers[mo] = nil
			continue
		end
		if not mo.target or mo.extravalue1 >= (used and 21 or 16) then
			P_RemoveMobj(mo) -- doesn't invalidate, because it's NOTHINK
			ringthinkers[mo] = nil
			continue
		end

		local target = mo.target
		if used then
			local hop = FixedMul(80*target.scale, sin(FixedAngle((90 - (9 * abs(10 - mo.extravalue1))) << FRACBITS)))
			K_MatchGenericExtraFlags(mo, target)
			P_MoveOrigin(mo, target.x, target.y, target.z + (target.height + hop) * P_MobjFlip(target))
			local frame = (mo.extravalue1 - 1) * 2 % 24
			mo.frame = ($ & ~FF_FRAMEMASK) | frame
		else
			mo.scale = mapobjectscale - (mapobjectscale/14) * mo.extravalue1
			mo.z = target.z
			K_MatchGenericExtraFlags(mo, target)
			local dist = (4*target.scale) * (16 - mo.extravalue1)
			P_MoveOrigin(mo,
				target.x + FixedMul(dist, cos(mo.angle)),
				target.y + FixedMul(dist, sin(mo.angle)),
				mo.z + target.scale * 24 * P_MobjFlip(mo)
			)
			mo.angle = $ + ANG30
		end
		mo.extravalue1 = $ + 1
	end
end)
end -- if RINGS

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
	local dp = CV_FindVar(RINGS and "speedometer" or "kartdisplayspeed")
	local value = dp.value - (RINGS and 1 or 0)
	if value == 1 then
		return string.format("%3d KM/H", FixedDiv(FixedMul(speed, 142371), mapobjectscale)/FRACUNIT)
	elseif value == 2 then
		return string.format("%3d MPH", FixedDiv(FixedMul(speed, 88465), mapobjectscale)/FRACUNIT)
	elseif value == 3 then
		return string.format("%3d FU/T", FixedDiv(speed, mapobjectscale)/FRACUNIT)
	else
		return string.format("%3d %%", (FixedDiv(speed, FixedMul(GetKartSpeed(consoleplayer.kartspeed, scale), 62914))*100)/FRACUNIT)
	end
end

local ringbox = {
	[-1] = "K_SBBG",
	[-2] = "K_SBBAR",
	[-3] = "K_SBBAR2",
	[-4] = "K_SBBAR3",
	[-5] = "K_SBRING",
	[-6] = "K_SBSEV",
	[-7] = "K_SBJACK",
}

hud.add(function(v, p)
	if ghostwatching then
		local flags = V_ALLOWLOWERCASE|V_SNAPTOTOP
		local trans = V_HUDTRANS
		v.drawString(160, 16, "Watching:", flags|trans, "center")
		v.drawString(160, 24, ghostwatching.name, flags|trans|V_YELLOWMAP, "center")

		local speed = FakeSpeedometer(FixedHypot(ghostwatching.gmomx, ghostwatching.gmomy), ghostwatching.mo.scale)
		flags = ($ & ~V_SNAPTOTOP) | V_MONOSPACE|V_SNAPTOBOTTOM
		v.drawString(160, 161, speed, flags|trans, "center")

		local time = max(0, ghostwatching.curtic - ghostwatching.starttime)
		v.drawKartString(205, RINGS and 8 or 12, string.format("%02d'%02d\"%02d", time/TICRATE/60, time/TICRATE%60, G_TicsToCentiseconds(time)), flags|trans)

		if ghostwatching.drifthilitecolor then
			local color
			if ghostwatching.drifthilitecolor == 1 then
				color = RINGS and V_YELLOWMAP or V_BLUEMAP
			elseif ghostwatching.drifthilitecolor == 2 then
				color = V_REDMAP
			elseif ghostwatching.drifthilitecolor == 3 then
				color = V_BLUEMAP
			elseif ghostwatching.drifthilitecolor == 4 then
				color = V_PURPLEMAP
			else
				color = V_GRAYMAP
			end
			trans = V_10TRANS * (ghostwatching.drifthilite / 2)
			v.drawString(160, 161, speed, flags|trans|color, "center")
			ghostwatching.drifthilite = $ + 1
			if ghostwatching.drifthilite == 2*10 then
				ghostwatching.drifthilitecolor = 0
			end
		end

		if ghostwatching.hasitem == 1 then
			trans = V_HUDTRANSHALF
			v.draw(142, 142, v.cachePatch("K_ISSHOE"), flags|trans, v.getColormap(TC_RAINBOW, ghostwatching.mo.color))
		elseif ghostwatching.hasitem == 2 then
			trans = V_HUDTRANS
			v.draw(142, 142, v.cachePatch("K_ISSHOE"), flags|trans)
		elseif ghostwatching.hasitem < 0 and (ghostwatching.hasitem == -1 or ghostwatching.fakeawardtimer) then
			trans = V_HUDTRANS
			v.draw(142, 142, v.cachePatch(ringbox[ghostwatching.hasitem]), flags|trans)
			ghostwatching.fakeawardtimer = $ - 1
		end
	end

	if ghostwatching and ghostmenu then
		local flags = V_SNAPTOTOP
		local cmap = v.getColormap(TC_RAINBOW, SKINCOLOR_GOLD)
		for i, opt in ipairs(menuoptions) do
			opt.draw(v, i*16+32, 0, flags, i == ghostmenusel and cmap or nil)
		end
		v.drawString(48 + 16*#menuoptions/2, 16, menuoptions[ghostmenusel].label(), flags|V_ALLOWLOWERCASE, "center")
	end

	--[[
	local i = 0
	for p in pairs(recorders) do
		v.drawString(100, 80+i, "Recording "..p.name, 0, "thin")
		i = i + 8
	end

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
		v.drawString(240, 104, "PA: "..tostring(r.paused))
		local patch = v.cachePatch("BLANKLVL")
		v.drawOnMinimap(r.mo.x, r.mo.y, FixedDiv(10, patch.height), patch)
	end
	--]]
end)
