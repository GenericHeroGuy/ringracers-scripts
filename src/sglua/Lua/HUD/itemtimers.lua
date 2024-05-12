-- Item duration indicator
-- Shows duration of grow, hyudoro, invincible, rocket sneakers, and sneakers on the bottom of the screen
-- Originally found in KL_BoostChaining_Speedboost_1.pk3 by Home
-- Forked and improved by Indev for Sunflower's Garden
-- Added HP mod support, moved the timers slightly, added a cvar to disable it, and more
-- Ported to Ring Racers
local cv_showitemtimers = CV_RegisterVar({
    name = "showitemtimers",
    defaultvalue = "Yes",
    possiblevalue = CV_YesNo,

    description = "Show Item Timers.",
})

local cv_showstack = CV_RegisterVar({
    name = "timers_showstack",
    defaultvalue = "Yes",
    possiblevalue = CV_YesNo,

    description = "Show amount of stacked boosts."
})

local cv_sort = CV_RegisterVar({
    name = "timers_sort",
    defaultvalue = "Time",
    possiblevalue = { Time = 1, Name = 2 },

    description = "Change ordering of timers.",
})

local cv_sort_invert = CV_RegisterVar({
    name = "timers_sort_invert",
    defaultvalue = "Off",
    possiblevalue = CV_OnOff,

    description = "Invert ordering of timers.",
})

local sortfuncs = {
    [1] = function(a, b, cmp) return cmp(a.timer, b.timer) end,
    [2] = function(a, b, cmp) return cmp(a.name, b.name) end,
}

local function gt(a, b) return a > b end
local function lt(a, b) return a < b end

local function sort(a, b)
    return sortfuncs[cv_sort.value](a, b, cv_sort_invert.value and lt or gt)
end

----------------------------------------------------------------------------------------------------
-- SPB Timer stuff
----------------------------------------------------------------------------------------------------
local havespb = false

local function setSpbTimer(p, value)
    if p.spbtimer == nil then
        p.spbtimer = value
    else
        p.spbtimer = min(p.spbtimer, value)
    end
end

local function getBestRank()
    local best = 255

    for player in players.iterate do
        if not (player.spectator or player.exiting) and player.position < best then
            best = player.position
        end
    end

    return best
end

local function spbTimer(actor)
    havespb = true

    if actor.tracer and actor.tracer.player then
        local p = actor.tracer.player
        local bestrank = getBestRank()

        if p.position > bestrank then
            setSpbTimer(p, actor.extravalue2)

            for player in players.iterate do
                if player.position == bestrank then
                    setSpbTimer(player, actor.extravalue2)
                elseif player ~= p then
                    player.spbtimer = nil
                end
            end
        else
            for player in players.iterate do
                player.spbtimer = nil
            end
        end
    end
end

addHook("MobjThinker", spbTimer, MT_SPB)

addHook("ThinkFrame", function()
    if havespb then
        havespb = false -- Spb thinker have to set this to true this every frame
        return
    end

    for player in players.iterate do
        player.spbtimer = nil
    end
end)

----------------------------------------------------------------------------------------------------
-- Misc/Utility
----------------------------------------------------------------------------------------------------
local function K_RainbowColor(time)
    -- Yes KK didn't expose that :AAAAAAAAAAAA:
    local FIRSTRAINBOWCOLOR = SKINCOLOR_PINK

    return FIRSTRAINBOWCOLOR + (time % (FIRSTSUPERCOLOR - FIRSTRAINBOWCOLOR))
end

local cache = {}

local function cachePatches(v, name, patches)
    cache[name] = {}

    for i = 1, #patches do
        table.insert(cache[name], v.cachePatch(patches[i]))
    end

    return cache[name]
end

----------------------------------------------------------------------------------------------------
-- Main hud hook
----------------------------------------------------------------------------------------------------
hud.add(function(v, p, c)
    if not p.spectator and cv_showitemtimers.value then
        -- name - for cache
        -- timer - timer to use
        -- patches - list of patch names
        -- anim_frames - frames for 1 animation step (used only for invincibility, in fact)
        local timerTable = {
            {
                name = "shoe",
                timer = p.sneakertimer or 0,
                patches = {"K_ISSHOE"},
                anim_frames = 1,
            },
            {
                name = "invincible",
                timer = p.invincibilitytimer,
                patches = {"K_ISINV1", "K_ISINV2", "K_ISINV3", "K_ISINV4", "K_ISINV5", "K_ISINV6"},
                anim_frames = 3,
            },
            {
                name = "grow",
                timer = max(p.growshrinktimer, 0),
                patches = {"K_ISGROW"},
                anim_frames = 1,
            },
            {
                name = "rocketsneakers",
                timer = p.rocketsneakertimer,
                patches = {"K_ISRSHE"},
                anim_frames = 1
            },
            {
                name = "hyudoro",
                timer = p.hyudorotimer,
                patches = {"K_ISHYUD"},
                anim_frames = 1,
            },
            {
                name = "driftsparkboost",
                timer = p.driftboost,
                patches = {"DRSP1", "DRSP2"},
                anim_frames = 2,
            },
            {
                name = "startboost",
                timer = p.startboost,
                patches = {"K_ISSTB"},
                anim_frames = 1,
            },
            {
                name = "ringboost",
                timer = p.ringboost,
                patches = {"K_ISRNG"},
                anim_frames = 1,
            },
            {
                name = "spindash",
                timer = p.spindashboost,
                patches = {"SPNDSH1", "SPNDSH2", "SPNDSH3", "SPNDSH4"},
                anim_frames = 3,
            },
            {
                name = "wavedash",
                timer = p.wavedashboost,
                patches = {"WAVDSH1", "WAVDSH2", "WAVDSH3"},
                anim_frames = 1,
            },
        }
        -- sort table

        table.sort(timerTable, function(a, b) if(a.timer ~= nil and b.timer ~= nil) then return sort(a, b) end end)

        -- This one always should be at end
        if cv_showstack.value == 1 then
            table.insert(timerTable, {
                name = "stackedboost",
                timer = p.numboosts,
                patches = {"DRSP1", "DRSP2"},
                anim_frames = 2,
            })
        end

        -- Ditto
        table.insert(timerTable, {
            name = "spbtimer",
            timer = p.spbtimer,
            patches = {"K_ISSPB"},
            anim_frames = 1,
        })

        -- ^
        table.insert(timerTable, {
            name = "spinout",
            timer = max(p.spinouttimer, p.wipeoutslow),
            patches = {"DIZZA0", "DIZZB0", "DIZZC0", "DIZZD0"},
            anim_frames = 3,
        })

        -- ^
        table.insert(timerTable, {
            name = "shrink",
            timer = max(-p.growshrinktimer, 0),
            patches = {"K_ISSHRK"},
            anim_frames = 1,
        })

        local iconX = 150
        local iconY = 170
        local iconFlags = V_SNAPTOBOTTOM
        local splitnum = c.pnum - 1
        local stepX = 30

        if splitscreen == 1 then
            if splitnum == 0 then
                iconY = 70
                iconFlags = 0
            end
        elseif splitscreen > 1 then
            stepX = 26 -- Make them a bit more compact

            if splitnum % 2 == 0 then -- p1 and p3
                iconX = 50
            else -- p2 and p4
                iconX = 250
            end

            if splitnum < 2 then -- p1 and p2
                iconY = 70
                iconFlags = 0
            else -- p3 and p4
                iconY = 170
            end
        end

        iconFlags = $|V_HUDTRANS

        local iconXOffset = -stepX
        for i, icon in ipairs(timerTable) do
            if(icon.timer and icon.timer > 0) then
                iconXOffset = $ + stepX
            end
        end

        iconX = $ - (iconXOffset/2)
        local hasBeenOffset = false
        for i, icon in ipairs(timerTable) do
            -- Draw icon/relevant timer
            local timer

            if icon.timer and icon.timer > 0 then

                timer = icon.timer

                local seconds = G_TicsToSeconds(timer)
                local centiseconds = G_TicsToCentiseconds(timer)

                local timerstring = seconds .. "." .. (centiseconds < 9 and "0" or "") .. centiseconds

                local patches = cache[icon.name]

                if patches == nil then
                    patches = cachePatches(v, icon.name, icon.patches)
                end

                local patch_num = (leveltime % (icon.anim_frames * #patches) / icon.anim_frames) + 1

                local cmap = nil

                if icon.name == "driftsparkboost" then
                    if icon.timer > 85 then -- Rainbow
                        cmap = v.getColormap(TC_DEFAULT, K_RainbowColor(leveltime))
                    elseif icon.timer > 50 then -- Blue
                        cmap = v.getColormap(TC_DEFAULT, SKINCOLOR_BLUE)
                    elseif icon.timer > 20 then -- Orange
                        cmap = v.getColormap(TC_DEFAULT, SKINCOLOR_KETCHUP)
                    else -- Yellow
                        cmap = v.getColormap(TC_DEFAULT, SKINCOLOR_GOLD)
                    end
                end

                if icon.name == "stackedboost" then
                    timerstring = tostring(icon.timer)
                end

                -- Bad stuffs, they are red
                if icon.name == "spinout" or icon.name == "shrink" or (icon.name == "spbtimer" and p.position == getBestRank()) then
                    timerstring = "\133"..timerstring
                end

                v.drawScaled(iconX*FRACUNIT, iconY*FRACUNIT, 6*FRACUNIT/10, patches[patch_num], iconFlags, cmap)
                v.drawString(iconX + 7, iconY + 15, timerstring, iconFlags, "thin")

                iconX = $ + stepX
            end
        end
    end
end)
