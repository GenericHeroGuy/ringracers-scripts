-- BREAK THE TARGETS! for Leaderboard

local targetlist, targetsleft, spawnpoint

addHook("MapChange", function()
	targetlist, targetsleft, spawnpoint = nil, nil, nil
end)
addHook("NetVars", function(net)
	targetlist, targetsleft, spawnpoint = net($1, $2, $3)
end)

rawset(_G, "lb_targets_left", function() return targetsleft end)

if CODEBASE >= 220 then
-- Ring Racers already has prison break. just keep count of the targets
addHook("PlayerSpawn", function(p)
	if gametype ~= GT_LEADERBATTLE or targetlist then return end
	targetlist = {}
	for mt in mapthings.iterate do
		local type = mt.type
		if type == mobjinfo[MT_BATTLECAPSULE].doomednum or type == mobjinfo[MT_CDUFO].doomednum then
			table.insert(targetlist, mt)
		end
	end
	targetsleft = #targetlist
end)

local function hitem() if targetlist then targetsleft = $ - 1 end end
addHook("MobjDeath", hitem, MT_BATTLECAPSULE)
addHook("MobjDeath", hitem, MT_CDUFO)

-- that's all we need!
return
end -- if CODEBASE >= 220

addHook("PlayerSpawn", function(p)
	if not LB_IsRunning() or gametype ~= GT_MATCH then
		if not leveltime then hud.enable("gametypeinfo") end
		return
	end
	hud.disable("gametypeinfo")

	if spawnpoint then
		if p.spectator then return end
		local x, y = spawnpoint.x<<FRACBITS, spawnpoint.y<<FRACBITS
		local sec = R_PointInSubsector(x, y).sector
		local floorz = sec.floorheight
		if sec.f_slope then floorz = P_GetZAt(sec.f_slope, x, y) end
		P_SetOrigin(p.mo, x, y, floorz + (spawnpoint.options>>4)*FRACUNIT + (p.kartstuff[k_respawn] and 128*mapobjectscale))
		p.mo.angle = FixedAngle(spawnpoint.angle*FRACUNIT)
		COM_BufInsertText(p, "resetcamera")
	end
end)

addHook("MapLoad", function()
	targetlist = {}
	for mt in mapthings.iterate do
		if mt.type == 2000 then
			table.insert(targetlist, mt)
		end
	end
	if G_BuildMapName() == "MAPS9" then
		table.remove(targetlist, 11) -- a single out of bounds item box in Sunset Park
	end
	targetsleft = #targetlist

	-- match and CTF starts reset their mapthing type to 0 for some reason
	-- hopefully nobody places CTF starts in their battle maps
	local dmstart
	for i = 0, #mapthings - 1 do
		local mt = mapthings[i]
		if mt.type == 1 then
			spawnpoint = mt
			break
		elseif not (mt.type or dmstart) then
			dmstart = mt
		end
	end
	-- if there's a player 1 start in the map, pick that one
	-- otherwise pick the first match start
	spawnpoint = spawnpoint or dmstart

	for p in players.iterate do
		if not p.spectator then p.playerstate = PST_REBORN end
	end
end)

addHook("ThinkFrame", function()
	if not LB_IsRunning() or gametype ~= GT_MATCH then return end
	for p in players.iterate do
		if not p.spectator and p.kartstuff[k_bumper] <= 0 and not (p.pflags & PF_TIMEOVER) then
			-- no SPB attack allowed :^)
			p.pflags = $ | PF_TIMEOVER
			p.lives = 0
			P_DamageMobj(p.mo, nil, nil, 10000)
			K_SetExitCountdown(TICRATE*5)
		end
	end
end)

addHook("TouchSpecial", function(special, toucher)
	if not LB_IsRunning() or gametype ~= GT_MATCH or toucher.player.exiting then return end
	if #targetlist - targetsleft < 3 then
		local p = toucher.player
		-- need pogosprings to beat MAPBO
		p.kartstuff[k_itemtype] = KITEM_POGOSPRING
		p.kartstuff[k_itemamount] = $ + 1
		p.kartstuff[k_itemblink] = TICRATE
	end

	local explode = mobjinfo[special.info.damage].mass
	local z = special.eflags & MFE_VERTICALFLIP
		and special.z + 3*(special.height/4) - FixedMul(mobjinfo[explode].height, special.scale)
		or special.z + special.height/4
	explode = P_SpawnMobj(special.x, special.y, z, explode)
	S_StartSound(explode, special.info.deathsound)
	P_RemoveMobj(special)

	targetsleft = $ - 1
	if targetsleft then return end
	for p in players.iterate do
		if not p.spectator then
			p.kartstuff[k_itemtype] = KITEM_NONE
			p.kartstuff[k_itemamount] = 0
			P_DoPlayerExit(p)
		end
	end
end, MT_RANDOMITEM)

local function drawTargets(v, p, c)
	if SG_BattleFullscreen and SG_BattleFullscreen(p) or p.spectator then return end

	local item = v.cachePatch("RNDMA0")
	local flags = V_HUDTRANS|V_SNAPTOBOTTOM|V_SNAPTOLEFT
	v.draw(9, 171, v.cachePatch("K_STTIME"), flags)
	v.drawScaled((29 + item.width/2/4)*FRACUNIT, 193*FRACUNIT, FRACUNIT/3, item, flags, v.getColormap(TC_BLINK, SKINCOLOR_BLACK))
	v.drawScaled((28 + item.width/2/4)*FRACUNIT, 192*FRACUNIT, FRACUNIT/3, item, flags)
	v.drawKartString(48, 174, ("%2d/%d"):format(targetsleft, #targetlist), flags)

	if SG_GetScreenCoords then
		local patch = v.cachePatch("MMAPWANT")
		local width, height = patch.width*v.dupx(), patch.height*v.dupy()
		local distdiv = FRACUNIT/9
		for i, mt in ipairs(targetlist) do
			local mo = mt.mobj
			if not mo then continue end
			local bx, by = SG_GetScreenCoords(v, p, c, mo, mo.height/2)
			if not bx then continue end
			local distfact = FixedDiv(mapobjectscale, R_PointToDist(mo.x, mo.y)/640)
			local fade = max(0, distfact/distdiv)
			if fade >= 10 then continue end

			local xofs, yofs = width*distfact/2, height*distfact/2
			if v.interpolate then v.interpolate(i) end
			v.drawScaled(bx - xofs, by - yofs, distfact, patch, V_NOSCALESTART | V_10TRANS*fade)
		end
		if v.interpolate then v.interpolate(false) end
	end
end
rawset(_G, "lb_draw_targets", drawTargets)
