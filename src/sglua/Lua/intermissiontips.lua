-- Intermission tips ported from SG Hostmod
-- Created by Indev for Sunflower's Garden

local inttips_hide = CV_RegisterVar({
	name = "inttips_hide",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,

    description = "Hide tips shown in intermission.",
})

local function colorstr(...)
	if not ... then
		return ""
	end

    local msg_buff = {}

    for _, arg in ipairs {...} do
        local arg_buff = {}

        local pos = 0
        local len = #arg

        while pos <= len do
            local char = string.sub(arg, pos, pos)

            if char == '\\' then
                char = string.char(tonumber(string.sub(arg, pos+1, pos+3)))

                pos = pos + 3
            end

            pos = pos + 1

            table.insert(arg_buff, char)
        end

        table.insert(msg_buff, table.concat(arg_buff, ""))
    end

	return table.concat(msg_buff, " ")
end

COM_AddCommand("__sayinttip", function(p, ...)
	if inttips_hide.value then return end

	local msg = table.concat({...}, " ")

	local ok, msg_colorized = pcall(colorstr, msg)

	if not ok then
		CONS_Printf(p, string.format("Failed to parse colors in message, error: %s\nSending it unparsed anyway", msg_colorized))
		msg_colorized = msg
	end

	chatprint(msg_colorized)
end, COM_ADMIN)

local function dosay(msg)
	COM_BufInsertText(server, string.format("__sayinttip \"%s\"", msg))
	--S_StartSound(nil, sfx_sysmsg)
end

local tips = {}

-- Netvar
local showtip = false

local function addCategory(cvar_name)
    if tips[cvar_name or "default"] ~= nil then return end

    local cvar

    if cvar_name then
        cvar = CV_FindVar(cvar_name)

        if not cvar then
            -- sus?
            print("\130WARNING:\128 cvar "..cvar_name.." not found, adding impostor table")
            cvar = setmetatable({}, {__index = function(self, key)
                if key == "value" then
                    local cvar = CV_FindVar(cvar_name)

                    if cvar then
                        print("Found cvar "..cvar_name..", removing impostor table")
                        tips[cvar_name].cvar = cvar
                        return cvar.value
                    end

                    print("\130WARNING:\128 cvar "..cvar_name.." not found")

                    return 0
                end
            end})
        end
    else
        cvar = {value = 1}
        cvar_name = "default"
    end

    tips[cvar_name] = {
        cvar = cvar,
        tips = {}
    }
end

local function addTip(tiptext, cvar_name)
    assert(tips[cvar_name or "default"] ~= nil)

    table.insert(tips[cvar_name or "default"].tips, tiptext)
end

local function addTips(file, cvar_name)
    addCategory(cvar_name)

    local num = 0

    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$")

        if line:sub(1, 2) == "//" or line:sub(1, 2) == "--" or line:sub(1, 1) == "#" then continue end

        if #line > 0 then
            num = num + 1
            addTip(line, cvar_name)
        end
    end

    return num
end

local function selectRandomTip()
    -- Called by all players so should be fine, synch wise
    local rand1 = P_RandomFixed()
    local rand2 = P_RandomFixed()

    if not isserver then
        return
    end

    local categories = {}

    for _, category in pairs(tips) do
        if category.cvar.value ~= 0 then
            table.insert(categories, category)
        end
    end

    if #categories == 0 then return end

    local category = categories[1+(rand1 % #categories)]

    if #category.tips == 0 then return end

    return category.tips[1+(rand2 % #category.tips)]
end

COM_AddCommand("addinttips", function(p, fn, cvar_name)
    if not isserver then
        CONS_Printf(p, "You aren't server :/")
        return
    end

    if not fn then
        CONS_Printf(p, "Usage: addinttips <file> [cvar]")
        CONS_Printf(p, "Tips are stored in file, one tip per line")
        CONS_Printf(p, "If cvar is specified, tips from file will only appear when it is not Off")
        return
    end

    local file = io.openlocal(fn, 'r')

    if not file then
        CONS_Printf(p, "\130WARNING:\128 can't open file "..fn)
        return
    end

    local num = addTips(file, cvar_name)

    file:close()

    CONS_Printf(p, "Added "..num.." tips from "..fn)
end, COM_LOCAL)

local function doTip()
    local tip = selectRandomTip()

    if tip then
		dosay(tip)
    end
end

COM_AddCommand("forceinttip", doTip, COM_ADMIN)

addHook("MapLoad", function()
    showtip = true
end)

addHook("IntermissionThinker", function()
    if showtip then
        showtip = false
        doTip()
    end
end)

addHook("NetVars", function(net)
    showtip = net(showtip)
end)
