-- Created by Indev and GenericHeroGuy for Sunflower's Garden
-- Normal value for advancemap
local hostmod_advancemap_default = CV_RegisterVar({
	name = "hm_advancemap_default",
	defaultvalue = "Random",
	flags = CV_NETVAR,
	possiblevalue = {Same = 0, Next = 1, Random = 2, Vote = 3},
})

-- Switches to this randomly
local hostmod_advancemap_random = CV_RegisterVar({
	name = "hm_advancemap_random",
	defaultvalue = "Vote",
	flags = CV_NETVAR,
	possiblevalue = {Same = 0, Next = 1, Random = 2, Vote = 3},
})

local hostmod_advancemap_randomchance = CV_RegisterVar({
	name = "hm_advancemap_randomchance",
	defaultvalue = "0.1",
	flags = CV_NETVAR|CV_FLOAT,
	possiblevalue = {MIN = 0, MAX = FRACUNIT},
})

local hostmod_encorechance = CV_RegisterVar({
	name = "hm_encore",
	defaultvalue = "0.01",
	flags = CV_NETVAR|CV_FLOAT,
	possiblevalue = {MIN = 0, MAX = FRACUNIT}
})

addHook("MapLoad", function()
	local pcount = 0
	for p in players.iterate do
		if not p.spectator then pcount = $ + 1 end
	end

	-- RNG first, cvar setting later. don't desync clients (and replays)
	local encore = P_RandomFixed() < hostmod_encorechance.value and 1 or 0
	local advance = hostmod_advancemap_default.value
	-- force advancemap to default in TA
	if P_RandomFixed() < hostmod_advancemap_randomchance.value and pcount >= 2 then
		advance = hostmod_advancemap_random.value
	end

	if isserver and not replayplayback then
		if pcount >= 2 then
			CV_StealthSet(CV_FindVar("encore"), encore)
		end
		CV_StealthSet(CV_FindVar("advancemap"), advance)
	end
end)
