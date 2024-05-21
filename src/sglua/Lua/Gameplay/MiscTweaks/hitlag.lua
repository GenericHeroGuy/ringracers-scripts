local cv_hitlag = CV_RegisterVar({
	name = "hitlag_multiplier",
	defaultvalue = "0",
	flags = CV_FLOAT|CV_NETVAR,
	description = "Multiplier for player hitlag",
	possiblevalue = { MIN = 0, MAX = FRACUNIT*9001 } -- WHAT! NINE THOUSAND!?
})

local cv_tricklag = CV_RegisterVar({
	name = "tricklag_multiplier",
	defaultvalue = "0",
	flags = CV_FLOAT|CV_NETVAR,
	description = "Multiplier for trick hitlag",
	possiblevalue = { MIN = 0, MAX = FRACUNIT*9001 }
})

local cv_hyudorolag = CV_RegisterVar({
	name = "hyudorolag_multiplier",
	defaultvalue = "0",
	flags = CV_FLOAT|CV_NETVAR,
	description = "Multiplier for hyudoro hitlag",
	possiblevalue = { MIN = 0, MAX = FRACUNIT*9001 }
})

local cv_triplag = CV_RegisterVar({
	name = "tripwirelag_multiplier",
	defaultvalue = "0",
	flags = CV_FLOAT|CV_NETVAR,
	description = "Multiplier for tripwire hitlag",
	possiblevalue = { MIN = 0, MAX = FRACUNIT*9001 }
})

local TRICKSTATE_READY = 1
local TRIPSTATE_NONE = 0
local MFE_PAUSED = 1<<15

local tagged = {}
local tricking = {}

local iskartitem = { MT_POGOSPRING = true, MT_EGGMANITEM = true, MT_EGGMANITEM_SHIELD = true, MT_BANANA = true, MT_BANANA_SHIELD = true, MT_ORBINAUT = true, MT_ORBINAUT_SHIELD = true, MT_JAWZ = true, MT_JAWZ_SHIELD = true, MT_SSMINE = true, MT_SSMINE_SHIELD = true, MT_LANDMINE = true, MT_DROPTARGET = true, MT_DROPTARGET_SHIELD = true, MT_BALLHOG = true, MT_SPB = true, MT_BUBBLESHIELDTRAP = true, MT_GARDENTOP = true, MT_HYUDORO = true, MT_SINK = true, MT_GACHABOM = true }

local function P_FlashingException(player, inflictor)
	return not (not inflictor or inflictor.type == MT_SSMINE or inflictor.type == MT_SPB or (not iskartitem[inflictor.type] and inflictor.type ~= MT_PLAYER) or not P_PlayerInPain(player))
end

addHook("MobjDamage", function(target, inflictor, source, _, damagetype)
	if not (gametyperules & GTR_BUMPERS) and damagetype & DMG_STEAL then return end

	-- handle combos, they do not skip MobjDamage
	local type = damagetype & DMG_TYPEMASK
	local hardhit = type == DMG_EXPLODE or type == DMG_KARMA or type == DMG_TUMBLE
	local allowcombo = (hardhit or type == DMG_STUMBLE or type == DMG_WHUMBLE) == ((damagetype & DMG_WOMBO) == 0)

	if type == DMG_TUMBLE then
		if target.player.tumblebounces == 1 and P_MobjFlip(target)*target.momz > 0 then
			allowcombo = false
		end
	elseif type == DMG_STUMBLE or type == DMG_WHUMBLE then
		if target.player.tumblebounces == 3-1 and P_MobjFlip(target)*target.momz > 0 then
			if type == DMG_STUMBLE then return end
			allowcombo = false
		end
	end

	if not allowcombo and (target.eflags & MFE_PAUSED) then return end

	if (target.hitlag == 0 or not allowcombo) and target.player.flashing > 0 and type ~= DMG_EXPLODE and type ~= DMG_STUMBLE and type ~= DMG_WHUMBLE and not P_FlashingException(target.player, inflictor) then return end
	if target.flags2 & MF2_ALREADYHIT then return end

	if target.player then tagged[target.player] = true end
	if inflictor and inflictor.player then tagged[inflictor.player] = true end
end, MT_PLAYER)

SG_AddHook("DropTargetHit", function(thing, tmthing)
	if thing.player then tagged[thing.player] = true end
	if tmthing.player then tagged[tmthing.player] = true end
end)

local function setlag(p, mult)
	p.mo.hitlag = FixedMul($, mult.value)

	-- handle delayed ring burst. doesn't run if there's zero hitlag
	if p.mo.hitlag == 0 and p.ringburst > 0 then
		P_PlayerRingBurst(p, p.ringburst)
		P_PlayRinglossSound(p.mo, nil)
		p.ringburst = 0
	end
end

addHook("PreThinkFrame", function()
	for p in players.iterate do
		tricking[p] = p.trickpanel == TRICKSTATE_READY
	end
end)

addHook("PostThinkFrame", function()
	for p in players.iterate do
		-- damage hook or items or whatever
		if tagged[p] then
			setlag(p, cv_hitlag)
			tagged[p] = false
		end

		-- tricks
		if tricking[p] and p.trickpanel ~= TRICKSTATE_READY then
			setlag(p, cv_tricklag)
		end

		-- hyudoro
		-- BUG: game writes 14*TICRATE (or 490) to an SINT8, which overflows to -22
		if p.stealingtimer == -22 then
			setlag(p, cv_hyudorolag)
		end

		-- tripwire
		if p.tripwirestate ~= TRIPSTATE_NONE then
			setlag(p, cv_triplag)
		end
	end
end)

addHook("PlayerQuit", function(p)
	-- in a break from tradition, don't leak memory, no matter how small
	tagged[p] = nil
	tricking[p] = nil
end)
