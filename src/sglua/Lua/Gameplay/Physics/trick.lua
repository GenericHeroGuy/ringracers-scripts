-- Reverts trick button mechanics back to v2.0-2.1.
-- by haya

local cv_trick_regression_enabled = CV_RegisterVar({
    name = "trick_regression_enabled",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Allows reverting tricking back to the one from v2.0-2.1.",
})

local CONFIG_FILENAME = "client/trickregression.cfg"

local function updateConfig(p)
    local file, err = io.openlocal(CONFIG_FILENAME, "w")

    if not file then
        CONS_Printf("\130WARNING:\128 failed to open config for writing: "..err)
        return
    end

    file:write("trickregression "..(p.trickregression and "Yes" or "No").."\n")
    file:close()
end

local function readConfig(p)
    p.trickregression_config_loaded = true

    local file = io.openlocal(CONFIG_FILENAME, "r")

    if not file then return end

    for line in file:lines() do
        COM_BufAddText(p, line)
    end

    file:close()
end

local function yesno(str)
    str = str:lower()

    local CONVERT = {
        yes = true,
        on = true,
        ["1"] = true,
    }

    return CONVERT[str] or false
end

COM_AddCommand("trickregression", function(p, arg)
    if not arg then
        CONS_Printf(p, "Usage: trickregression yes/no")
        CONS_Printf(p, "pre-v2.2 trick behavior is "..(p.trickregression and "\131enabled" or "\133disabled"))
        return
    end

    p.trickregression = yesno(arg)

    CONS_Printf(p, "pre-v2.2 trick behavior is now "..(p.trickregression and "\131enabled" or "\133disabled"))

    if cv_trick_regression_enabled.value == 0 then
        CONS_Printf(p, "\131NOTICE:\128 trick.lua is disabled by host")
    end

    if p == consoleplayer and p.trickregression_config_loaded then
        updateConfig(p)
    end
end)

local TRICKTHRESHOLD = 800 / 2 -- KART_FULLTURN/2
local TRICKSTATE_READY = 1
local PF_TRICKDELAY = 1<<23

-- Yes, this only works on PreThinkFrame.
addHook("PreThinkFrame", function()
	if cv_trick_regression_enabled.value == 0 then return end

	for player in players.iterate do
		if not player.trickregression then continue end
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

addHook("ThinkFrame", function()
    if consoleplayer and not consoleplayer.trickregression_config_loaded then
        readConfig(consoleplayer)
    end
end)
