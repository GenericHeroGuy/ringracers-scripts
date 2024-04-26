local cv_noffbounce = CV_RegisterVar {
    name = "nofastfallbounce",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
    description = "Removes bounce from fast fall",
}

addHook("PlayerThink", function(p)
    if cv_noffbounce.value == 0 then return end

    if not p.mo then return end

    p.fastfall = 0

    local onground = P_IsObjectOnGround(p.mo)

    if not onground and ((p.cmd.buttons & BT_BRAKE) or p.fftriggered) then
        p.fastfall = p.mo.momz
        p.fftriggered = true
    elseif onground then
        p.fftriggered = false
    end
end)
