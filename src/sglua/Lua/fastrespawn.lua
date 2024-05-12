local cv_fastrespawn = CV_RegisterVar {
    name = "fastrespawn",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Toggle faster respawning for people behind",
}

addHook("PlayerThink", function(p)
    if p.respawn.state then
        if not p.fastrespawn then
            if p.position == 1 then
                -- Not exposed to lua but this is vanilla respawn time. No bonuses for frontrunner
                p.fastrespawn = 48
            elseif not K_IsPlayerLosing(p) then
                p.fastrespawn = 3*TICRATE/4
            else
                p.fastrespawn = TICRATE/3
            end
        end

        p.respawn.timer = min($, p.fastrespawn)
    else
        p.fastrespawn = nil
    end
end)
