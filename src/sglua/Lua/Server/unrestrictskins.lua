-- restrictskinchange? cheat? on by default?
-- nuh uh

-- we have to not confuse this with an actual team change
local skins = {}
addHook("PostThinkFrame", function()
	for p in players.iterate do
		skins[#p] = p.skin
	end
end)

-- this is crossing tic boundaries, so we have to sync it
addHook("NetVars", function(sync)
	skins = sync($)
end)

-- hope this works... o_o
addHook("TeamSwitch", function(p, newteam, fromspectators, tryingautobalance, tryingscramble)
	if newteam == 0 and not (fromspectators or tryingautobalance or tryingscramble) then
		if skins[#p] ~= p.skin then
			return false
		end
	end
end)
