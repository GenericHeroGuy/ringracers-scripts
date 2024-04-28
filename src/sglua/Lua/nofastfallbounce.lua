local cv_noffbounce = CV_RegisterVar {
    name = "nofastfallbounce",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Removes bounce from fast fall",
}

addHook("PlayerThink", function(p)
    if cv_noffbounce.value == 0 then return end

    -- the actual bounce is delayed by a tic for some reason, so this works
    if p.mo and p.mo.eflags & MFE_JUSTHITFLOOR then
        p.fastfall = 0
    end
end)
