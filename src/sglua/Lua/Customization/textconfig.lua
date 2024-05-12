-- A simple config file for Sunflower's Garden
local config_path = "client/SunflowerGarden.cfg"
local server_name = "Sunflower's Garden"

local function loadConfig()
    if replayplayback then return end

    if consoleplayer ~= nil and not consoleplayer.config_loaded then
        print("Trying to load "..config_path.."...")

        local file = io.openlocal(config_path, "r")

        if not file then
            print(config_path.." not found, generating it")

            file = io.openlocal(config_path, "w")

            if not file then
                print("\130WARNING\128: could not generate "..config_path.." config file")
                consoleplayer.config_loaded = true
                return
            else
                file:write("// Config for "..server_name.." server")
                file:close()
                consoleplayer.config_loaded = true
                return
            end
        else
            local line = file:read()

            while line do
                COM_BufAddText(consoleplayer, line)
                line = file:read()
            end

            file:close()
            print("Done!")
        end

        consoleplayer.config_loaded = true
    end
end

addHook("ThinkFrame", loadConfig)
addHook("IntermissionThinker", loadConfig)
addHook("VoteThinker", loadConfig)
