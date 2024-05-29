-- tumbletech by GenericHeroGuy
freeslot("sfx_tekyes")

local cv_tumbletech = CV_RegisterVar {
	name = "tumbletech",
	defaultvalue = "On",
	possiblevalue = CV_OnOff,
	flags = CV_NETVAR,
	description = "Cancel tumbling by pressing Accel on landing.",
}

local tumbled = {}

addHook("PreThinkFrame", function()
	if not cv_tumbletech.value then return end

	for p in players.iterate do
		tumbled[p] = not p.markedfordeath and p.tumblebounces or 0
	end
end)

local function SpawnTechStars(mo, count)
	for i = 1, count do
		local star = P_SpawnMobj(mo.x, mo.y, mo.z, MT_KARMAFIREWORK)
		star.momx = P_RandomRange(-mapobjectscale*20, mapobjectscale*20)
		star.momy = P_RandomRange(-mapobjectscale*20, mapobjectscale*20)
		star.momz = P_RandomRange(0, mapobjectscale*5)*P_MobjFlip(mo)
		star.flags = $ | MF_NOGRAVITY
		star.color = mo.color
		star.fuse = TICRATE/3
		star.scale = mo.scale
		star.destscale = 0
		star.scalespeed = mapobjectscale/20
	end
end

addHook("PlayerSpawn", function(p)
	p.tumbletech = { lockout = 0, press = 0, cantech = false, firstrelease = false }
end)

addHook("PlayerThink", function(p)
	local tt = p.tumbletech
	if not tt and cv_tumbletech.value then return end

	if p.cmd.buttons & BT_ACCELERATE then
		tt.press = max($ + 1, 1)
	else
		tt.press = min($ - 1, 0)
		if tt.press == 0 and tt.firstrelease then
			tt.lockout = TICRATE/4
		end
		tt.firstrelease = true
	end

	tt.cantech = tumbled[p] and tumbled[p] < 3 and p.playerstate == PST_LIVE
	-- landed?
	if tt.cantech and tumbled[p] == p.tumblebounces - 1 then
		if tt.lockout then
			-- mashing...!
			tt.lockout = 0
			tt.firstrelease = false
			S_StartSound(p.mo, sfx_s231)
		elseif tt.press > 0 then
			-- no idea how to cope with lag tbh...
			-- just give them more leniency
			local lag = p.cmd.latency/2
			if tt.press <= TICRATE/15 then
				-- perfect!
				p.mo.momz = 0
				p.tumblebounces = 0
				p.mo.hitlag = 0
				SpawnTechStars(p.mo, 20)
				S_StartSound(p.mo, sfx_tekyes)
				S_StartSound(p.mo, sfx_s3k46)
			elseif tt.press <= TICRATE/5 + lag then
				-- nice!
				if p.tumblebounces >= 3 then
					p.mo.momz = 3*mapobjectscale
				else
					p.mo.momz = 7*mapobjectscale
				end
				p.mo.momx = $/2
				p.mo.momy = $/2
				p.tumblebounces = 0
				p.mo.hitlag = 0
				SpawnTechStars(p.mo, 10)
				S_StartSound(p.mo, sfx_tekyes)
			elseif tt.press <= TICRATE/2 + lag then
				-- meh
				p.mo.momz = max(10*mapobjectscale, min($, 40*mapobjectscale))
				p.mo.momx = $/3
				p.mo.momy = $/3
				p.tumblebounces = 4
				p.tumbleheight = 10
				p.pflags = $ | PF_TUMBLELASTBOUNCE
				p.mo.hitlag = 0
				SpawnTechStars(p.mo, 5)
				S_StartSound(p.mo, sfx_kc40)
			end
		end
	end

	if not tumbled[p] then
		tt.firstrelease = false
	end
	if tt.lockout then
		tt.lockout = $ - 1
	end
end)

hud.add(function(v, p, c)
	if not cv_tumbletech.value then return end
	local tt = p.tumbletech

	if tt and tt.cantech then
		-- predict when the player is going to land
		-- and show the timing for a nice! tech
		local mz = p.mo.z
		local momz = p.mo.momz
		local lag = p.cmd.latency/2
		for i = 2, TICRATE/5 + lag do
			momz = $ + P_GetMobjGravity(p.mo)
			mz = $ + momz
		end
		local res = SG_ObjectTracking(v, p, c, { x = p.mo.x, y = p.mo.y, z = p.mo.z + p.mo.height*P_MobjFlip(p.mo) }, false)
		local patch
		if mz <= p.mo.floorz then
			patch = "TLB_AB"
			if not tt.lockout then
				v.drawString(res.x/FRACUNIT + 9, res.y/FRACUNIT - 11, "GO!", V_ORANGEMAP|V_SPLITSCREEN)
			end
		else
			patch = "TLB_A"
		end
		v.drawScaled(res.x - 7*FRACUNIT, res.y - FRACUNIT*16, FRACUNIT, v.cachePatch(patch), V_SPLITSCREEN)
		if tt.lockout then
			v.drawScaled(res.x - 23*FRACUNIT/2, res.y - FRACUNIT*20, FRACUNIT, v.cachePatch("K_NOBLNS"), V_SPLITSCREEN)
		end
	end
--[[
	v.drawString(64, 64, tostring(tt.press))
	v.drawString(64, 72, tostring(tt.lockout))
	v.drawString(64, 80, tostring(tt.firstrelease))
	v.drawString(64, 88, tostring(p.tumblebounces))
	v.drawString(64, 96, tostring(p.markedfordeath))
--]]
end)
