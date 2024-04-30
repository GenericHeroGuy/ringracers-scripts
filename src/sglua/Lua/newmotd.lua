local newmotd = CV_RegisterVar({
    name = "newmotd",
    defaultvalue = '',
    flags = CV_NETVAR,
})

local MOTDTIMER = 3*TICRATE

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

local function newMOTDThink()
    if newmotd.value == '' then return end
    if not consoleplayer then return end
    if consoleplayer.newmotdsent then return end

    if consoleplayer.newmotdtimer == nil then
        consoleplayer.newmotdtimer = MOTDTIMER
    end

    consoleplayer.newmotdtimer = $ - 1

    if consoleplayer.newmotdtimer > 0 then return end

    local text = colorstr(newmotd.string)

    chatprintf(consoleplayer, text)
    consoleplayer.newmotdsent = true
end

addHook("ThinkFrame", newMOTDThink)
addHook("VoteThinker", newMOTDThink)
addHook("IntermissionThinker", newMOTDThink)
