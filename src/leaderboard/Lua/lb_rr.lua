-- LEADERBOARD RR STUFF (formerly online TA)
-- ONLY FOR Dr Robotnik's Ring Racers(tm)
if VERSION ~= 2 then return end

---- Imported functions ----

-- lb_common.lua
local GetGametype = lb_get_gametype

-----------------------------

local BT_RESPAWN = 1<<6

local cv_ringboxes = CV_RegisterVar({
	name = "lb_ringboxes",
	flags = CV_NETVAR,
	defaultvalue = "TA",
	possiblevalue = { Sneakers = 0, Multiplayer = 1, TA = 2 }
})

local faultstart
local fuseset

-- fault starts change their mapthing type to 0 after being processed
-- so, sigh... here we go...
local loading = false
local oldrings = {}
addHook("MapChange", do
	loading = true
	faultstart = nil
	fuseset = false
	oldrings = {}
end)

addHook("MobjSpawn", function()
	if not faultstart then
		for mt in mapthings.iterate do
			if mt.type == 36 then
				faultstart = mt
			end
		end
		faultstart = $ or true
	end
end)

addHook("MobjThinker", function(mo)
	if gametype == GT_LEADERBOARD and cv_ringboxes.value then
		mo.extravalue1 = 0
	end
end, MT_RANDOMITEM)

addHook("ThinkFrame", function()
	local starttime = LB_StartTime()

	-- hide/show item boxes in battle
	if gametype == GT_LEADERBATTLE then
		if not leveltime then
			for mo in mobjs.iterate() do
				if mo.type == MT_RANDOMITEM then
					mo.renderflags = $ | RF_ADD|RF_TRANS30
					mo.flags = $ | MF_NOCLIPTHING|MF_NOBLOCKMAP
				end
			end
		elseif leveltime == starttime then
			for mo in mobjs.iterate() do
				if mo.type == MT_RANDOMITEM then
					mo.renderflags = $ & ~(RF_ADD|RF_TRANS30)
					mo.flags = $ & ~(MF_NOCLIPTHING|MF_NOBLOCKMAP)
				end
			end
		end
	end

	if starttime then
		for p in players.iterate do
			if leveltime < starttime and p.rings <= 0 then
				-- if only instawhipchargelockout was exposed
				p.defenselockout = 1
			end
		end

		local countdown = starttime - leveltime
		if countdown == 3*TICRATE
		or countdown == 2*TICRATE
		or countdown == 1*TICRATE then
			S_StartSound(nil, sfx_s3ka7)
		elseif not countdown then
			S_StartSound(nil, sfx_s3kad)
		end
	end
end)

addHook("MapLoad", do
	loading = false
	fuseset = true -- not after loading!
end)

addHook("PlayerSpawn", function(p)
	if gametype == GT_LEADERBOARD and not fuseset and cv_ringboxes.value then
		fuseset = true
		for mo in mobjs.iterate() do
			if mo.type == MT_RANDOMITEM then
				-- i'm not entirely sure about the implications of turning everything into
				-- perma ringboxes since it affects anticheese
				-- for now i'll just stick to the tried-and-true resetting of extravalue1
				--mo.flags2 = $ | MF2_BOSSDEAD
				-- do set fuse though so it doesn't immediately transform back
				mo.fuse = 1
			end
		end
	end

	if GetGametype() and not p.spectator then
		if gametype == GT_LEADERBOARD then p.rings = 20 end
		if faultstart ~= true then
			local fx, fy, fz = faultstart.x<<FRACBITS, faultstart.y<<FRACBITS, faultstart.z<<FRACBITS
			local sec = R_PointInSubsector(fx, fy).sector
			local floorz
			if sec.f_slope then
				floorz = P_GetZAt(sec.f_slope, fx, fy)
			else
				floorz = sec.floorheight
			end
			P_SetOrigin(p.mo, fx, fy, P_FloorzAtPos(fx, fy, floorz + fz, 0))
			p.mo.angle = faultstart.angle*ANG1
		end
	end
end)

addHook("PreThinkFrame", function()
	if GetGametype() then
		for p in players.iterate do
			local old = oldrings[p]
			if not old then
				old = {}
				oldrings[p] = old
			end
			old.delay = p.ringboxdelay
			old.award = p.ringboxaward
			old.super = p.superring
		end
	end
end)

addHook("PlayerThink", function(p)
	-- do NOT check LB_IsRunning so this works in replays
	if p.spectator or not GetGametype() then return end

	local old = oldrings[p]
	if cv_ringboxes.value == 2 -- TA mode ringboxes
	and p.ringboxdelay == 0 and old.delay == 1 then
		local award = 5*old.award + 10
		if not CV_FindVar("thunderdome").value then
			award = 3 * award / 2
		end

		if false--modeattacking & ATTACKING_SPB then
			// SPB Attack is hard.
			award = award / 2
		else
			// At high distance values, the power of Ring Box is mainly an extra source of speed, to be
			// stacked with power items (or itself!) during the payout period.
			// Low-dist Ring Box follows some special rules, to somewhat normalize the reward between stat
			// blocks that respond to rings differently; here, variance in payout period counts for a lot!

			local accel = 10-p.kartspeed
			local weight = p.kartweight

			// Fixed point math can suck a dick.

			if accel > weight then
				accel = $ * 10
				weight = $ * 3
			else
				accel = $ * 3
				weight = $ * 10
			end

			award = (110 + accel + weight) * award / 120
		end

		-- minus 1?
		-- in P_PlayerThink, K_MoveKartPlayer runs which does the superring reward
		-- THEN K_KartPlayerThink runs, which adds the ringboost and decrements superring
		-- but we're running after all that so a single ring has already been given to the player
		-- ...love how I just randomly wrote a long comment for a single - 1 kek
		local superring = old.super + award - 1

		/* check if not overflow */
		if superring > old.super then
			p.superring = superring
		end
	end

	-- roulette isn't exposed, and item capsules besides rings are disabled in TA, so...
	if gametype == GT_LEADERBOARD then
		if p.itemtype and p.itemtype ~= KITEM_SNEAKER then
			p.itemtype = KITEM_SNEAKER
			p.itemamount = 1
		end
	end

	if gametype == GT_SPECIAL and p.exiting then
		G_SetCustomExitVars(gamemap, 2) -- where do you think you're going?
	end

	if p.cmd.buttons & BT_RESPAWN then
		COM_BufAddText(p, "retry")
	end
end)

freeslot("S_FAKEUFOPOD")

addHook("MobjThinker", function(mo)
	if not mo.lbufofix then
		-- the pod piece calls RNG based on S_SoundPlaying which causes desynchs
		-- so we'll have to substitute it with an impostor...
		local piece = mo.hnext
		while piece.extravalue1 ~= 0 do -- UFO_PIECE_TYPE_POD
			piece = piece.hnext
		end
		piece.type = MT_RAY -- oh yeah, this thing exists
		piece.state = S_FAKEUFOPOD
		mo.lbufofix = true
	end
end, MT_SPECIAL_UFO)

states[S_FAKEUFOPOD] = {
	sprite = SPR_UFOB,
	tics = 1,
	nextstate = S_FAKEUFOPOD,
	action = function(actor, var1, var2)
		local ufo = actor.target
		if not ufo then
			P_RemoveMobj(actor)
			return
		end
		if not actor.health then
			actor.fuse = actor.tics
			return
		end

		actor.scalespeed = ufo.scalespeed
		actor.destscale = 3 * ufo.destscale / 2
		actor.momx = ufo.x - actor.x
		actor.momy = ufo.y - actor.y
		actor.momz = ufo.z + 132*actor.scale - actor.z
		-- doesn't line up otherwise
		P_MoveOrigin(actor, ufo.x, ufo.y, ufo.z + 132*actor.scale)

		if ufo.watertop > 70*FRACUNIT then
			local fast = P_SpawnMobjFromMobj(ufo,
				P_RandomRange(-120, 120) * FRACUNIT,
				P_RandomRange(-120, 120) * FRACUNIT,
				(ufo.info.height / 2) + (P_RandomRange(-24, 24) * FRACUNIT),
				MT_FASTLINE
			)
			fast.scale = $ * 3
			fast.target = ufo
			--fast.angle = K_MomentumAngle(ufo)
			if FixedHypot(ufo.momx, ufo.momy) > 6*ufo.scale then
				fast.angle = R_PointToAngle2(0, 0, ufo.momx, ufo.momy)
			else
				fast.angle = ufo.angle // default to facing angle, rather than 0
			end
			fast.color = SKINCOLOR_WHITE
			fast.colorized = true
			K_MatchGenericExtraFlags(fast, ufo)
		end
	end
}

addHook("IntermissionThinker", function()
	if not LB_IsRunning() then return end

	for p in players.iterate do
		if p.spectator then continue end
		p.exiting = 0 -- don't use bot ticcmds in intermission!
		if p.cmd.buttons & BT_RESPAWN then
			COM_BufAddText(p, "retry")
		end
	end
end)
