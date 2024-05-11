-- Reverts trick button mechanics back to v2.0-2.1.
-- by haya

local cv_trick_regression = CV_RegisterVar({
    name = "trick_regression",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Reverts tricking back to the one from v2.0-2.1.",
})

local TRICKTHRESHOLD = 800 / 2 -- KART_FULLTURN/2
local TRICKSTATE_READY = 1
local PF_TRICKDELAY = 1<<23

-- Yes, this only works on PreThinkFrame.
addHook("PreThinkFrame", function()
	if cv_trick_regression.value == 0 then return end
	for player in players.iterate do
		if not player.mo then continue end
		
		-- handle regression delay
		player.trickregressiondelay = $ or 0
		
		if player.trickpanel ~= TRICKSTATE_READY then continue end
		
		local cmd = player.cmd
		local aimingcompare = abs(cmd.throwdir) - abs(cmd.turning)
		
		-- we trickin
		if (aimingcompare < -TRICKTHRESHOLD) or (aimingcompare > TRICKTHRESHOLD) then
			cmd.buttons = $ | BT_ACCELERATE
			player.trickregressiondelay = 2
		end
		
		-- intentionally not accelerate here
		if player.trickregressiondelay <= 0 then
			cmd.buttons = $ & ~BT_ACCELERATE
		end
		
		player.trickregressiondelay = max(0, $ - 1)
	end
end)