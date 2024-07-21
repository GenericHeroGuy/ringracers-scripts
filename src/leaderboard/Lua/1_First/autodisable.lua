local cvars_to_disable = {
    { name = "frontrun_enabled", cv = nil, },
    { name = "elimination", cv = nil, },

    { name = "hpmod_enabled", cv = nil, },

    { name = "fr_enabled", cv = nil, }, -- Friendmod
    
    { name = "juicebox", cv = nil, },

    { name = "allrestat", cv = nil, },
    
    { name = "weathermod", cv = nil, },
    { name = "as_wildtricks", cv = nil, }, -- Acrobasic Wild Tricks
    { name = "as_wildspeed", cv = nil, }, -- Acrobasic Wild Speed
    { name = "paraglider_debug_faytwantedthis", cv = nil, }, -- I don't know but I just added it anyway
    { name = "paraglider_debug_deployanywhere", cv = nil, }, -- Always allow using paragliders
    { name = "paraglider_fullhoryzontalcontrol", cv = nil, }, -- Full control of the paraglider
    { name = "paraglider_fullvertcontrol", cv = nil, }, -- Full control of the paraglider
}

addHook("ThinkFrame", function()
    if not LB_IsRunning() then return end
    
    local should_disable = replayplayback
    
    for i = 1, #cvars_to_disable do
        local vardata = cvars_to_disable[i]
    
        local cv = vardata.cv
        
        if cv and cv.value then
            should_disable = true
            break
        end
    end
    
    if should_disable then
        LB_Disable()
    end
end)

local function cvarLookup()
    for _, vardata in ipairs(cvars_to_disable) do
        if not vardata.cv then
            vardata.cv = CV_FindVar(vardata.name)
        end
    end
end

addHook("MapLoad", cvarLookup)
addHook("NetVars", cvarLookup)