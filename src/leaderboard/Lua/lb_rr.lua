-- LEADERBOARD RR STUFF (formerly online TA)
-- ONLY FOR Dr Robotnik's Ring Racers(tm)
if VERSION ~= 2 then return end

local BT_RESPAWN = 1<<6

G_AddGametype({
	name = "Leaderboard",
	identifier = "ONLINETA",
	rules = GTR_CIRCUIT|GTR_ENCORE
	-- skip title card, also mutes lap sound, also hides freeplay for some reason
	|GTR_SPECIALSTART
	-- continuous music
	|GTR_NOPOSITION,
	typeoflevel = TOL_RACE,
	speed = 2,
	intermissiontype = 2,
})

G_AddGametype({
	name = "Leaderbattle",
	identifier = "LEADERBATTLE",
	rules = GTR_SPHERES|GTR_BUMPERS|GTR_PAPERITEMS|GTR_POWERSTONES|GTR_KARMA|GTR_ITEMARROWS|GTR_PRISONS|GTR_BATTLESTARTS|GTR_POINTLIMIT|GTR_TIMELIMIT|GTR_OVERTIME|GTR_CLOSERPLAYERS
	-- skip title card, also mutes lap sound, also hides freeplay for some reason
	|GTR_SPECIALSTART
	-- continuous music
	|GTR_NOPOSITION,
	typeoflevel = TOL_BATTLE,
	speed = 0,
	intermissiontype = 2,
})

local cv_ringboxes = CV_RegisterVar({
	name = "lb_ringboxes",
	flags = CV_NETVAR,
	defaultvalue = "TA",
	possiblevalue = { Sneakers = 0, Multiplayer = 1, TA = 2 }
})

local faultstart
local musicchanged = false
local fuseset

local function checkmusic()
	if musicchanged then
		COM_BufInsertText(consoleplayer, "tunes -default")
		musicchanged = false
	end
end

-- fault starts change their mapthing type to 0 after being processed
-- so, sigh... here we go...
local loading = false
addHook("MapChange", do
	loading = true
	faultstart = nil
	fuseset = false
	checkmusic()
end)
addHook("GameQuit", checkmusic)
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
	if gametype == GT_ONLINETA and cv_ringboxes.value then
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

	if gametype == GT_ONLINETA or gametype == GT_LEADERBATTLE then
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
	if not fuseset and gametype == GT_ONLINETA and cv_ringboxes.value then
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

	if gametype == GT_ONLINETA and not p.spectator then
		p.rings = 20
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
		p.onlineta = {
			exittimer = 0,
			finished = false,
		}
	else
		p.onlineta = nil
	end
end)

addHook("PlayerThink", function(p)
	local ot = p.onlineta
	if not ot then return end

	if ot.finished then
		ot.exittimer = $ - 1
		if not ot.exittimer then
			local oldinttime = CV_FindVar("inttime").value
			COM_BufInsertText(consoleplayer, "tunes racent")
			musicchanged = true
			COM_BufInsertText(server, "inttime 1000; exitlevel; wait 2; inttime "..oldinttime)
		end
	end

	if cv_ringboxes.value == 2 -- TA mode ringboxes
	and p.ringboxdelay == 0 and ot.lastringboxdelay == 1 then
		local award = 5*ot.lastringboxaward + 10
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
		local superring = ot.lastsuperring + award - 1

		/* check if not overflow */
		if superring > ot.lastsuperring then
			p.superring = superring
		end
	end
	ot.lastringboxdelay = p.ringboxdelay
	ot.lastsuperring = p.superring
	ot.lastringboxaward = p.ringboxaward

	-- roulette isn't exposed, and item capsules besides rings are disabled in TA, so...
	if p.itemtype and p.itemtype ~= KITEM_SNEAKER then
		p.itemtype = KITEM_SNEAKER
	end
	if p.itemamount and p.itemamount ~= 1 then
		p.itemamount = 1
	end

	if p.cmd.buttons & BT_RESPAWN then
		COM_BufAddText(p, "retry")
	end
end)
