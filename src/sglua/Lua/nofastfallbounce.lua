local cv_noffbounce = CV_RegisterVar {
    name = "nofastfallbounce_enabled",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Removes bounce from fast fall",
}

local CONFIG_FILENAME = "fastfallbounce.cfg"

local function updateConfig(p)
    local file, err = io.openlocal(CONFIG_FILENAME, "w")

    if not file then
        CONS_Printf("\130WARNING:\128 failed to open config for writing: "..err)
        return
    end

    file:write("fastfallbounce "..(p.fastfallbounce and "Yes" or "No").."\n")
    file:close()
end

local function readConfig(p)
    p.fastfallbounce_config_loaded = true

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

COM_AddCommand("fastfallbounce", function(p, arg)
    if not arg then
        CONS_Printf(p, "Usage: fastfallbounce yes/no")
        CONS_Printf(p, "Fast fall bounce is "..(p.fastfallbounce and "\131enabled" or "\133disabled"))
        return
    end

    p.fastfallbounce = yesno(arg)

    CONS_Printf(p, "Fast fall bounce is now "..(p.fastfallbounce and "\131enabled" or "\133disabled"))

    if cv_noffbounce.value == 0 then
        CONS_Printf(p, "\131NOTICE:\128 nofastfallbounce.lua is disabled by host")
    end

    if p == consoleplayer and p.fastfallbounce_config_loaded then
        updateConfig(p)
    end
end)

addHook("PlayerThink", function(p)
    if cv_noffbounce.value == 0 or p.fastfallbounce then return end

    -- the actual bounce is delayed by a tic for some reason, so this works
    if p.mo and p.mo.eflags & MFE_JUSTHITFLOOR and p.curshield ~= KSHIELD_BUBBLE then
        p.fastfall = 0
    end
end)

addHook("ThinkFrame", function()
    if consoleplayer and not consoleplayer.fastfallbounce_config_loaded then
        readConfig(consoleplayer)
    end
end)
