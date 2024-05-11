-- HitList! not that this game has many item interactions lol
-- by GenericHeroGuy

local cv_enabled = CV_RegisterVar({
	name = "hitlist",
	defaultvalue = "On",
	possiblevalue = CV_OnOff,
	description = "Show players getting hit." -- the punctuation wars continue
})

local hitlist = {}
local timetolive = TICRATE*4
local check = {}

local function AddHit(hit)
	if not cv_enabled.value then return end

	for _, hit2 in ipairs(hitlist) do
		if hit.source == hit2.source then
			-- check for combos
			-- "WHY ARE YOU USING THE ICON!?"
			-- i mean, it effectively doubles as a "hit type"
			-- ...you ARE giving unique icons to everything, right? :)
			if hit2.targets[hit.target] and hit.icon == hit2.icon then
				hit2.targets[hit.target] = $ + 1
				hit2.timestamp = leveltime
				hit2.timetodie = leveltime + timetolive
				return
			-- check for multihits
			elseif hit.inflictor == hit2.inflictor and not hit2.targets[hit.target] then
				-- deaths must occur on the same tic to count
				if not (hit.death and hit2.timestamp ~= leveltime) then
					hit2.targets[hit.target] = 1
					table.insert(hit2.targetorder, hit.target)
					hit2.timestamp = leveltime
					hit2.timetodie = leveltime + timetolive
					return
				end
			end
		end
	end

	-- no combo
	hit.targets = { [hit.target] = 1 }
	hit.targetorder = { [0] = hit.target }
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

-- sinks and death
addHook("MobjDeath", function(target, inflictor, source, damagetype)
	local icon = "HL_DEATH"

	if inflictor then
		if inflictor.type == MT_SINK then
			icon = "HL_KITCHENSINK"
		end
	end

	AddHit({
		death = true,
		target = target.player,
		inflictor = inflictor,
		source = source and source.player,
		icon = icon,
	})
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
		source = master and master.player,
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
			source = thing.target and thing.target.player,
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
freeslot("S_ACTUALLYDAMAGED")

addHook("PlayerSpawn", function(p)
	if p.actuallydamaged and p.actuallydamaged.valid then P_RemoveMobj(p.actuallydamaged) end
	local mo = P_SpawnMobj(p.mo.x, p.mo.y, p.mo.z, MT_THOK)
	mo.flags = $ | MF_NOSECTOR
	mo.state = S_ACTUALLYDAMAGED
	p.actuallydamaged = mo
end)

local function CheckHits()
	while next(check) do
		local hit = table.remove(check, 1)
		if hit.target.mo.flags2 & MF2_ALREADYHIT then
			AddHit(hit)
		end
	end
end

states[S_ACTUALLYDAMAGED] = {
	tics = 1,
	nextstate = S_ACTUALLYDAMAGED,
	action = CheckHits
}

-- need this for the last player
addHook("ThinkFrame", CheckHits)

addHook("MapChange", do hitlist = {} end)

local HEIGHT = 9
local ICONHEIGHT = 8
local ICONOFFSET = FRACUNIT/2
local V_100TRANS = V_50TRANS*2
local FONTHEIGHTS = { thin = 9, small = 4 }

-- somebody disconnected? no problem, just replace them :^)
local function CheckValid(hit)
	if hit.source and not hit.source.valid then
		hit.source = { name = "???", skincolor = 1, valid = true }
	end
	for target, combo in pairs(hit.targets) do
		if not target.valid then
			local dummy = { name = "???", skincolor = 1, valid = true }
			hit.targets[dummy] = combo
			hit.targets[target] = nil
			for i = 0, #hit.targetorder do
				if hit.targetorder[i] == target then hit.targetorder[i] = dummy end
			end
		end
	end
end

local function GetFont(v, name, vflags)
	local font = "thin"
	local width = v.stringWidth(name, vflags, font)
	if width >= 60 then -- too long
		font = "small"
		width = v.stringWidth(name, vflags, font)
	end
	return font, width
end

local function GetOffsets(v, hit, vflags)
	local ox = 0
	local ofs = {}

	ofs.left = ox
	if hit.source and not hit.targets[hit.source] then
		local font, width = GetFont(v, hit.source.name, vflags)
		ofs.sourcefont = font
		ox = $ + width
	end
	ox = $ + (hit.leftpad or 1)

	ofs.icon = ox
	if hit.icon then
		local icon = v.cachePatch(hit.icon)
		local scale = FixedDiv(ICONHEIGHT, max(ICONHEIGHT, icon.height))
		ofs.icon = ox
		ox = $ + (icon.width*scale)>>FRACBITS
	end
	ox = $ + (hit.rightpad or 1)

	ofs.right = ox
	local add = 0
	ofs.targetfont = {}
	for target, combo in pairs(hit.targets) do
		local font, width = GetFont(v, target.name, vflags)
		ofs.targetfont[target] = font
		add = max($, width + (combo > 1 and v.stringWidth("x"..combo, vflags, "thin") + 1 or 0))
	end
	ox = $ + add

	ofs.edge = ox
	return ofs
end

hud.add(function(v, p)
	for i = #hitlist, 1, -1 do
		if leveltime >= hitlist[i].timetodie then
			-- "Time to die, I guess!"
			table.remove(hitlist, i)
		end
	end

	local hy = 4
	local tallest = 64

	for i, hit in ipairs(hitlist) do
		CheckValid(hit)

		local hx = 56
		-- TODO: V_SPLITSCREEN is broken (r_splitscreen never gets updated in HUD hooks)
		local vflags = V_SNAPTOTOP|V_SNAPTOLEFT|V_SPLITSCREEN|(V_10TRANS*max(0, leveltime - hit.timetodie + 10))

		local multiheight = -HEIGHT
		for _ in pairs(hit.targets) do multiheight = $ + HEIGHT end

		local light = hit.source == p or hit.targets[p]
		if splitscreen and not light then continue end

		local offsets = GetOffsets(v, hit, vflags)
		local cmap = v.getColormap(TC_DEFAULT, light and SKINCOLOR_WHITE or SKINCOLOR_BLACK)
		local bg = v.cachePatch(light and "HLLBG" or "HLDBG")
		local corner = v.cachePatch(light and "HLLCORNER" or "HLDCORNER")
		local top = v.cachePatch(light and "HLLTOP" or "HLDTOP")
		local side = v.cachePatch(light and "HLLSIDE" or "HLDSIDE")

		-- background/corner/side widths/heights
		local bw = FixedDiv(offsets.edge, bg.width)
		local bh = FixedDiv(HEIGHT + multiheight, bg.height)
		local cw = offsets.edge + corner.width
		local ch = HEIGHT + multiheight
		local sw = FixedDiv(offsets.edge, top.width)
		local sh = FixedDiv(HEIGHT + multiheight, side.height)

		hy = $ + 1 + max(corner.height, top.height)*2

		-- background
		v.drawStretched(hx*FRACUNIT, hy*FRACUNIT, bw, bh, bg, vflags, cmap)

		-- top, bottom, left, right
		v.drawStretched(hx*FRACUNIT, (hy - top.height)*FRACUNIT, sw, FRACUNIT, top, vflags, cmap)
		v.drawStretched(hx*FRACUNIT, hy*FRACUNIT + sh*side.height, sw, FRACUNIT, top, vflags | V_VFLIP, cmap)
		-- XXX: on OpenGL, if the hscale is exactly FRACUNIT, the vertical scale just doesn't work?????
		v.drawStretched((hx - side.width)*FRACUNIT, hy*FRACUNIT, FRACUNIT+1, sh, side, vflags, cmap)
		v.drawStretched((hx + side.width)*FRACUNIT + sw*top.width + 1, hy*FRACUNIT, FRACUNIT+1, sh, side, vflags | V_FLIP, cmap)

		-- top left, top right, bottom left, bottom right
		v.draw(hx - corner.width, hy - corner.height, corner, vflags, cmap)
		v.draw(hx + cw, hy - corner.height, corner, vflags | V_FLIP, cmap)
		v.draw(hx - corner.width, hy + ch, corner, vflags, cmap)
		v.draw(hx + cw, hy + ch, corner, vflags | V_FLIP | V_VFLIP, cmap)

		-- source
		if hit.source and not hit.targets[hit.source] then
			local color = skincolors[hit.source.skincolor].chatcolor
			local font = offsets.sourcefont
			local fofs = (HEIGHT - FONTHEIGHTS[font])/2
			v.drawString(hx + offsets.left, hy + multiheight/2 + fofs, hit.source.name, vflags | color, font)
		end

		-- icon
		if hit.icon then
			local icon = v.cachePatch(hit.icon)
			local scale = FixedDiv(ICONHEIGHT, max(ICONHEIGHT, icon.height))
			local cmap = v.getColormap(TC_DEFAULT, light and SKINCOLOR_BLACK or SKINCOLOR_WHITE)
			v.drawScaled((hx + offsets.icon)*FRACUNIT, (hy+multiheight/2)*FRACUNIT + ICONOFFSET, scale, icon, vflags, cmap)
		end

		-- target(s)
		-- for target, combo in pairs(hit.targets) do
		for i = 0, #hit.targetorder do
			local target = hit.targetorder[i]
			local combo = hit.targets[target]
			local color = skincolors[target.skincolor].chatcolor
			local font = offsets.targetfont[target]
			local fofs = (HEIGHT - FONTHEIGHTS[font])/2
			v.drawString(hx + offsets.right, hy+i*HEIGHT + fofs, target.name, vflags | color, font)
			if combo > 1 then
				local nameofs = v.stringWidth(target.name, vflags, offsets.targetfont[target]) + 1
				local color = (leveltime - hit.timestamp < TICRATE/3) and leveltime & 1 and V_ORANGEMAP or V_YELLOWMAP
				v.drawString(hx + offsets.right + nameofs, hy+i*HEIGHT, "x"..combo, vflags | color, "thin")
			end
		end

		-- extra drawing function
		if hit.extrafunc then
			hit.extrafunc(v, hit, offsets, hx, hy, vflags)
		end

		hy = $ + HEIGHT + multiheight
		if hy >= tallest then return end
	end
end)
