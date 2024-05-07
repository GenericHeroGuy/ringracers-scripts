-- HitList! not that this game has many item interactions lol
-- by GenericHeroGuy

local cv_enabled = CV_RegisterVar({
	name = "hitlist",
	defaultvalue = "On",
	possiblevalue = CV_OnOff,
	description = "Show players getting hit." -- the punctuation wars continue
})

local hitlist = {}
local timetolive = TICRATE*3
local check = {}

local function AddHit(hit)
	if not cv_enabled.value then return end

	if hit.icon == nil then
		print(string.format("No icon? inflictor %s source %s", hit.inflictor and hit.inflictor.valid and mobjinfo[hit.inflictor.type].string or "?", hit.source and hit.source.valid and hit.source.name or "?"))
	end

	for _, hit2 in ipairs(hitlist) do
		if hit.source == hit2.source and hit.damagetype == hit2.damagetype then
			-- check for combos
			if hit2.targets[hit.target] then
				hit2.targets[hit.target] = $ + 1
				hit2.timestamp = leveltime
				hit2.timetodie = leveltime + timetolive
				return
			-- check for multihits
			elseif hit.inflictor == hit2.inflictor then
				hit2.targets[hit.target] = 1
				hit2.timestamp = leveltime
				hit2.timetodie = leveltime + timetolive
				return
			end
		end
	end

	-- no combo
	hit.targets = { [hit.target] = 1 }
	hit.timestamp = leveltime
	hit.timetodie = leveltime + timetolive
	table.insert(hitlist, hit)
end

-- I'M TIRED OF PRETENDING THAT THE 8-CHARACTER LIMIT IS STILL A THING AAAAAAAA
local simple = {
	[MT_SSMINE_SHIELD] = "HL_SSMINE",
	[MT_ORBINAUT] = "HL_ORBINAUT",
	[MT_ORBINAUT_SHIELD] = "HL_ORBINAUT",
	[MT_JAWZ] = "HL_JAWZ",
	[MT_JAWZ_SHIELD] = "HL_JAWZ",
	[MT_BANANA] = "HL_BANANA",
	[MT_BANANA_SHIELD] = "HL_BANANA",
	[MT_LANDMINE] = "HL_LANDMINE",
	[MT_BALLHOG] = "HL_BALLHOG",
	[MT_GARDENTOP] = "HL_GARDENTOP",
	[MT_GACHABOM] = "HL_GACHABOM",
	[MT_INSTAWHIP] = "HL_INSTAWHIP",
	[MT_SPB] = "HL_SPB",
}

addHook("MobjDamage", function(target, inflictor, source, damage, damagetype)
	local type = damagetype & DMG_TYPEMASK
	if type == DMG_STING then return end

	if target.flags2 & MF2_ALREADYHIT then return end
	if not (inflictor and source and source.player) then return end

	local icon

	if inflictor.type == MT_PLAYER then
		local player = inflictor.player
		-- chances of this are next to none,
		-- but if someone with a lightning shield has invinc at the same time...
		if player.curshield == KSHIELD_LIGHTNING
		and damagetype == DMG_VOLTAGE|DMG_CANTHURTSELF|DMG_WOMBO then
			icon = "HL_LIGHTNINGSHIELD"
		-- K_PvPTouchDamage
		elseif player.invincibilitytimer > 0 then
			icon = "HL_INVINCIBILITY"
		elseif player.flamedash > 0 and player.itemtype == KITEM_FLAMESHIELD then
			icon = "HL_FLAMESHIELD"
		elseif player.bubbleblowup > 0 then
			icon = "HL_BUBBLESHIELD"
		elseif player.sneakertimer > 0 and not P_PlayerInPain(player) and player.flashing == 0 then
			icon = "HL_SNEAKER"
		else
			print("uhhh what kinda player attack is this")
			return
		end
	elseif inflictor.type == MT_SPBEXPLOSION then
		icon = inflictor.threshold == KITEM_EGGMAN and "HL_EGGMAN" or "HL_SPB"
	else
		icon = simple[inflictor.type]
	end

	local hit = {
		target = target.player,
		inflictor = inflictor,
		source = source.player,
		icon = icon,
	}

	-- NOT SO FAST!
	-- this is MobjDamage, we don't actually know if the hit goes through
	-- so put it in a "check" table for now and wait until ThinkFrame (he doesn't know)
	-- to see if the damage actually went through
	table.insert(check, hit)
end, MT_PLAYER)

-- hyudoro
addHook("TouchSpecial", function(special, toucher)
	if special.extravalue1 ~= 0 then return end -- HYU_PATROL

	// Cannot hit its master
	--                     center             center master
	local master = special.target and special.target.target or nil
	if toucher == master then return end

	// Don't punish a punished player
	if toucher.player.hyudorotimer then return end

	// NO ITEM?
	if not toucher.player.itemamount then return end

	AddHit({
		target = toucher.player,
		inflictor = special,
		source = master.player,
		icon = "HL_HYUDORO",
		rightpad = 7,

		hyuitem = K_GetItemPatch(toucher.player.itemtype, true),
		extrafunc = function(v, hit, ofs, hx, hy, vflags)
			local icon = v.cachePatch(hit.hyuitem)
			local scale = FixedDiv(8, max(8, icon.height/2))
			hx = $ + ofs.icon
			v.drawScaled((hx+3)*FRACUNIT, (hy-3)*FRACUNIT, scale, icon, vflags, cmap)
		end
	})
end, MT_HYUDORO)

-- drop target
-- yoinked from hitlag
-- i really need to make a new libsg
local function height(thing, tmthing)
	return tmthing.z > thing.z + thing.height or tmthing.z + tmthing.height < thing.z
end
local function droptarget(thing, tmthing)
	if height(thing, tmthing) then return end
	if (thing.target == tmthing or thing.target == tmthing.target) and ((thing.threshold > 0 and tmthing.player) or (not tmthing.player and tmthing.threshold > 0)) then return end
	if thing.health <= 0 or tmthing.health <= 0 then return end
	if tmthing.player and (tmthing.player.hyudorotimer or tmthing.player.justbumped) then return end

	if tmthing.player then
		AddHit({
			target = tmthing.player,
			inflictor = thing,
			source = thing.target.player,
			icon = "HL_DROPTARGET",
		})
	end
end
addHook("MobjCollide", droptarget, MT_DROPTARGET)
addHook("MobjMoveCollide", droptarget, MT_DROPTARGET)

-- WHAT THE FUCK AM I LOOKING AT!?
-- ok so the problem with abusing MF2_ALREADYHIT is that if the player that gets hit
-- runs its mobj thinker after the source/inflictor, then the player will immediately
-- clear MF2_ALREADYHIT, which makes the hit fail to register
-- the solution? forcibly insert an extra thinker between players which checks if the flag is set :))))))))))
-- brought to you by a lack of PlayerSpin
freeslot("MT_MOBJACTUALLYDAMAGED")
mobjinfo[MT_MOBJACTUALLYDAMAGED] = { flags = MF_NOBLOCKMAP|MF_NOSECTOR, spawnstate = S_INVISIBLE }
addHook("PlayerSpawn", function(p)
	if p.actuallydamaged and p.actuallydamaged.valid then P_RemoveMobj(p.actuallydamaged) end
	p.actuallydamaged = P_SpawnMobj(p.mo.x, p.mo.y, p.mo.z, MT_MOBJACTUALLYDAMAGED)
end)

local function CheckHits()
	while next(check) do
		local hit = table.remove(check, 1)
		if hit.target.mo.flags2 & MF2_ALREADYHIT then
			AddHit(hit)
		end
	end
end

addHook("MobjThinker", CheckHits, MT_MOBJACTUALLYDAMAGED)
addHook("ThinkFrame", CheckHits) -- need this for player 0

addHook("MapChange", function()
	hitlist = {}
end)

local iconheight = 8
local HEIGHT = 9
local padding = 3
local iconoffset = FRACUNIT/2
local font = "thin"
local vflags = V_SNAPTOTOP|V_SNAPTOLEFT

-- TODO: rip this shit out and use GetOffsets
local function HitWidth(v, hit, vflags, font)
	local w = 0

	if hit.source and not hit.targets[hit.source] then
		w = $ + v.stringWidth(hit.source.name, vflags, font)
	end
	w = $ + (hit.leftpad or 1)

	if hit.icon then
		local icon = v.cachePatch(hit.icon)
		local scale = FixedDiv(iconheight, max(iconheight, icon.height))
		w = $ + (hit.iconpadleft or 1)
		w = $ + (icon.width*scale)>>FRACBITS + (hit.iconpadright or 1)
	end
	w = $ + (hit.rightpad or 1)

	local add = 0
	for target, combo in pairs(hit.targets) do
		add = max($, v.stringWidth(target.name, vflags, font) + (combo > 1 and v.stringWidth(string.format("x%d", combo), vflags, font) + 1 or 0))
	end
	w = $ + add

	return w
end

local function GetOffsets(v, hit, vflags, font)
	local w = 0
	local ofs = {}

	ofs.left = w
	if hit.source and not hit.targets[hit.source] then
		w = $ + v.stringWidth(hit.source.name, vflags, font)
	end
	w = $ + (hit.leftpad or 1)

	ofs.icon = w
	if hit.icon then
		local icon = v.cachePatch(hit.icon)
		local scale = FixedDiv(iconheight, max(iconheight, icon.height))
		w = $ + (hit.iconpadleft or 1)
		w = $ + (icon.width*scale)>>FRACBITS + (hit.iconpadright or 1)
	end
	w = $ + (hit.rightpad or 1)

	ofs.right = w
	local add = 0
	for target, combo in pairs(hit.targets) do
		add = max($, v.stringWidth(target.name, vflags, font) + (combo > 1 and v.stringWidth(string.format("x%d", combo), vflags, font) + 1 or 0))
	end
	w = $ + add

	ofs.edge = w
	return ofs
end

hud.add(function(v, p)
	for i = #hitlist, 1, -1 do
		if leveltime >= hitlist[i].timetodie then
			-- "Time to die, I guess!"
			table.remove(hitlist, i)
		end
	end

	local hy = 0
	local tallest = HEIGHT*5
	for i, hit in ipairs(hitlist) do
		local hx = 56
		local basehx = hx

		hy = $ + HEIGHT + padding
		local multiheight = -HEIGHT
		for _ in pairs(hit.targets) do multiheight = $ + HEIGHT end

		local width = HitWidth(v, hit, vflags, font)
		local bg = v.cachePatch(hit.source == p and "~100" or "~104")
		local cmap = v.getColormap(TC_DEFAULT, hit.source == p and SKINCOLOR_WHITE or SKINCOLOR_BLACK)
		v.drawStretched((hx-1)*FRACUNIT, (hy-1)*FRACUNIT, FixedDiv(width+2, bg.width), FixedDiv(HEIGHT+multiheight+2, bg.height), bg, vflags, cmap)

		if hit.source and not hit.targets[hit.source] then
			v.drawString(hx, hy + multiheight/2, hit.source.name, vflags, font)
			hx = $ + v.stringWidth(hit.source.name, vflags, font)
		end
		hx = $ + (hit.leftpad or 1)

		if hit.icon then
			local icon = v.cachePatch(hit.icon)
			local scale = FixedDiv(iconheight, max(iconheight, icon.height))
			local cmap = v.getColormap(TC_DEFAULT, hit.source == p and SKINCOLOR_BLACK or SKINCOLOR_WHITE)
			hx = $ + (hit.iconpadleft or 1)
			v.drawScaled(hx*FRACUNIT, (hy+multiheight/2)*FRACUNIT + iconoffset, scale, icon, vflags, cmap)
			hx = $ + (icon.width*scale)>>FRACBITS + (hit.iconpadright or 1)
		end
		hx = $ + (hit.rightpad or 1)

		local add = 0
		local i = 0
		for target, combo in pairs(hit.targets) do
			local new = 0
			v.drawString(hx, hy+i*HEIGHT, target.name, vflags, font)
			new = v.stringWidth(target.name, vflags, font)
			if combo > 1 then
				local color = (leveltime - hit.timestamp < TICRATE/3) and leveltime & 1 and V_ORANGEMAP or V_YELLOWMAP
				v.drawString(hx+new+1, hy+i*HEIGHT, string.format("x%d", combo), vflags | color, font)
				new = $ + v.stringWidth(string.format("x%d", combo), vflags | color, font)
			end
			add = max($, new)
			i = $ + 1
		end
		hx = $ + add

		-- extra drawing function
		local ofs = GetOffsets(v, hit, vflags, font)
		if hit.extrafunc then
			hit.extrafunc(v, hit, ofs, basehx, hy, vflags)
		end

		hy = $ + multiheight
		if hy >= tallest then return end
	end
end)
