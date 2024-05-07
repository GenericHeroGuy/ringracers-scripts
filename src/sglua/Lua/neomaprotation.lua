-- neomaprotation by Indev for Sunflower's Garden
-- Replaces vanilla "random map" rotation with a lua one
-- This allows for customization instead of dealing with a hardcoded one
-- Example: Vanilla random map NEVER rolls hell. This will!
-- Also mappool support! Want specific maps only for Elimination? Now you can.
-- Ideas and polish feedback by Sunflower#1739/AnimeSonic

rawset(_G, "nmr", 1)

local resets = 0
local keep = {}
local maps_to_visit = {}
local hell_maps_to_visit = {}
local remove_maps = {}
local mappool = {}
local mappool_current = nil
local nohell = 0

-- Few things for rng to add more randomness
local rngfactors = {
    leveltime = 0, -- last leveltime value
    players = 0, -- Combination of various values from players, if anyone is ingame
}

-- Timer for IntermissionThinker
-- -2 - map just changed, but MapLoad wasn't called yet, not doing anything (kinda weird fix but ok)
-- -1 - MapLoad has been called
-- 0  - changing map
-- >0 - waiting...
local nextmaptimer = -1
local battle = false

-- Not synced
local hell = false

local cv_nmr_hellchance = CV_RegisterVar({
    name = "nmr_hellchance",
    defaultvalue = "0.01",
    possiblevalue = {
        MIN = 0,
        MAX = FRACUNIT,
    },
    flags = CV_NETVAR | CV_FLOAT,
})

local cv_nmr_enabled = CV_RegisterVar({
    name = "nmr_enabled",
    defaultvalue = "On",
    possiblevalue = CV_OnOff,
    flags = CV_NETVAR,
})

local cv_nmr_nohellrounds = CV_RegisterVar({
    name = "nmr_nohellrounds",
    defaultvalue = "10",
    possiblevalue = CV_Unsigned,
    flags = CV_NETVAR,
})

-- Will use CV_FindVar in MapLoad and NetVars. Why not here? Because when
-- loading addons, it will return nil :/
local cv_advancemap

rawset(_G, "NMR_GetRemovedMaps", function() return remove_maps end)
rawset(_G, "NMR_GetMapPools", function() return mappool end)
rawset(_G, "NMR_GetActiveMapPool", function() return mappool_current end)

local function NMR_RandomFixed()
    local rnd = P_RandomFixed() ^^ rngfactors.leveltime ^^ rngfactors.players

    return rnd & (FRACUNIT-1)
end

local function NMR_RandomRange(a, b)
    if a == b then return a end

    return a + NMR_RandomFixed() % (b - a)
end

local function NMR_RandomChance(a)
    if a >= FRACUNIT then return true end
    if a <= 0 then return false end

    return NMR_RandomFixed() < a
end

local function findAndRemove(list, value)
    for i = 1, #list do
        if list[i] == value then
            table.remove(list, i)
            break
        end
    end
end

local function clearList(list)
    while #list > 0 do
        table.remove(list)
    end
end


local function countPlayers()
    local c = 0

    for player in players.iterate do
        if not player.spectator then
            c = c + 1
        end
    end

    return c
end

local function refillMapsToVisit()
    if not battle then resets = resets + 1 end

    clearList(maps_to_visit)
    clearList(hell_maps_to_visit)

    local function gmcheck(flags)
        if battle then return flags & TOL_BATTLE end
        return flags & TOL_RACE
    end

    for i = 0, #mapheaderinfo do
        if mapheaderinfo[i] ~= nil                                           -- Map exists
            and gmcheck(mapheaderinfo[i].typeoflevel)                        -- Compatible gamemode
            and not remove_maps[i]                                           -- Map is not removed from rotation
            and (mappool_current == nil or mappool[mappool_current][i]) then -- No map pool active or map belongs to current map pool

            if mapheaderinfo[i].menuflags & LF2_HIDEINMENU then
                table.insert(hell_maps_to_visit, i)
            else
                table.insert(maps_to_visit, i)
            end
        end
    end
end

local function addMaps(maplist, othermaplist)
    for _, mapid in ipairs(othermaplist) do
        table.insert(maplist, mapid)
    end
end

local function G_BattleGametype()
    -- TODO - check for gametype rules maybe?
    return gametype == GT_BATTLE
end

local function pickMap(hell, recursion)
    if not battle and G_BattleGametype() or battle and not G_BattleGametype() then
        battle = G_BattleGametype()

        if keep[1] ~= nil then
            print("Game mode changed, restoring old maplist")
            keep[1], maps_to_visit = maps_to_visit, keep[1]
            keep[2], hell_maps_to_visit = hell_maps_to_visit, keep[2]
        else
            print("Game mode changed, refilling map lists...")
            keep = { maps_to_visit, hell_maps_to_visit }
            maps_to_visit = {}
            hell_maps_to_visit = {}
            refillMapsToVisit()
        end
    end

    local maplist = maps_to_visit

    if hell then maplist = hell_maps_to_visit end

    if #maplist == 0 then
        print("Run out of maps for random rotation, refilling map lists...")
        refillMapsToVisit()
    end

    local cv_elim = CV_FindVar("elimination")

    local nosprint = cv_elim and cv_elim.value and (countPlayers() >= CV_FindVar("elim_minplayers").value)

    if nosprint then
        local i = NMR_RandomRange(1, #maplist)
        local mapid = maplist[i]
        local checked = {}

        while #maplist and mapheaderinfo[maplist[i]].levelflags & LF_SECTIONRACE do
            table.insert(checked, maplist[i])
            table.remove(maplist, i)
            i = NMR_RandomRange(1, #maplist)
            mapid = maplist[i]
        end

        if not #maplist then
            if recursion then -- Well we tried. Will return sprint map then
                print("\130WARNING:\128 Couldn't find any non-sprint maps")
                addMaps(maplist, checked) -- Re-add all checked maps
            else
                -- Try to refill map lists and find non-sprint map again, but only once
                return pickMap(maplist, true)
            end
        else
            -- Non-sprint map found. Add checked maps back and return found map
            addMaps(maplist, checked)
            return mapid
        end
    end

    return maplist[NMR_RandomRange(1, #maplist)]
end

local function pickNormalMap()
    return pickMap(false)
end

local function pickHellMap()
    return pickMap(true)
end

local function pickRandomMap()
    if (nohell == 0) and NMR_RandomChance(cv_nmr_hellchance.value) then
        nohell = cv_nmr_nohellrounds.value
        return pickHellMap()
    else
        if nohell then nohell = nohell - 1 end
        return pickNormalMap()
    end
end

local function changeLevel(mapid)
    local name = G_BuildMapName(mapid)

    print("[nmr] Change level to "..name)

    COM_BufInsertText(server, "map "..name)
end

addHook("MapLoad", function(mapid)
    -- Don't do anything in replays :3
    if replayplayback then return end

    if not cv_advancemap then cv_advancemap = CV_FindVar("advancemap") end

    nextmaptimer = -1

    local active_players = 0

    for player in players.iterate do active_players = active_players + 1 end

    if active_players < 2 then return end

    if mapheaderinfo[mapid].menuflags & LF2_HIDEINMENU then
        findAndRemove(hell_maps_to_visit, mapid)
    else
        findAndRemove(maps_to_visit, mapid)
    end

end)

addHook("ThinkFrame", function()
    -- Don't do anything in replays :3
    if replayplayback then return end

    if leveltime == 2 then
        if hell then S_StartSound(nil, sfx_noooo1) end
        hell = false
    end

    rngfactors.leveltime = leveltime

    local pfactor = 0

    for player in players.iterate do
        if not player.spectator then
            local pmo = player.mo

            pfactor = pfactor ^^ pmo.x ^^ pmo.y ^^ pmo.z
            pfactor = pfactor ^^ pmo.angle
            pfactor = pfactor ^^ (#skins[pmo.skin])
            pfactor = pfactor ^^ player.skincolor
        end
    end

    rngfactors.players = pfactor
end)

addHook("NetVars", function(net)
    if not cv_advancemap then cv_advancemap = CV_FindVar("advancemap") end

    resets = net(resets)
    keep = net(keep)
    maps_to_visit = net(maps_to_visit)
    hell_maps_to_visit = net(hell_maps_to_visit)
    remove_maps = net(remove_maps)
    mappool = net(mappool)
    mappool_current = net(mappool_current)
    nextmaptimer = net(nextmaptimer)
    nohell = net(nohell)
    battle = net(battle)
    rngfactors = net(rngfactors)
end)

addHook("IntermissionThinker", function()
    -- Don't do anything in replays :3
    if replayplayback then return end

    -- 2 for advancemap is Random
    if not cv_nmr_enabled.value or (cv_advancemap and cv_advancemap.value ~= 2) then return end

    if nextmaptimer == -1 then
        -- Timer set to end few frames earlier so vote screen/default map change
        -- doesn't happen
        nextmaptimer = CV_FindVar("inttime").value*TICRATE - 5
    elseif nextmaptimer > 0 then
        --print("CAN'T WAIT FOR NEXT MAP!!!")
        nextmaptimer = nextmaptimer - 1
    elseif nextmaptimer == 0 then
        --print("NEXT MAP!!!")
        local mapid = pickRandomMap()
        hell = mapheaderinfo[mapid].menuflags & LF2_HIDEINMENU
        changeLevel(mapid)
        nextmaptimer = -2
    end
end)

COM_AddCommand("nmr_randommap", function(player, ...)
    local args = {...}
    local mapid

    for _, arg in ipairs(args) do
        if arg == "-nohell" then
            mapid = pickNormalMap()
            break
        elseif arg == "-hell" then
            mapid = pickHellMap()
            hell = true
            break
        end
    end

    if mapid == nil then
        mapid = pickRandomMap()
        hell = mapheaderinfo[mapid].menuflags & LF2_HIDEINMENU
    end

    CONS_Printf(player, "Change level to map "..G_BuildMapName(mapid).." (#"..mapid..")")

    changeLevel(mapid)
end, COM_ADMIN)

COM_AddCommand("nmr_refresh", function(player)
    refillMapsToVisit()

    CONS_Printf(player, "Map lists updated, found "..(#maps_to_visit).." normal maps and "..(#hell_maps_to_visit).." hell maps")
end, COM_ADMIN)

COM_AddCommand("nmr_removemap", function(player, name)
    if not name then
        CONS_Printf(player, "Usage: nmr_removemap <map>\nFor example, nmr_removemap MAP01")
        return
    end

    local mapid = G_FindMapByNameOrCode(name)

    if not mapid then
        CONS_Printf(player, "\133Error:\128 map "..name.." cannot be found")
        return
    end

    remove_maps[mapid] = true

    CONS_Printf(player, "Remove map "..name.." (#"..mapid..") from rotation")

    if mapheaderinfo[mapid].menuflags & LF2_HIDEINMENU then
        findAndRemove(hell_maps_to_visit, mapid)
    else
        findAndRemove(maps_to_visit, mapid)
    end
end, COM_ADMIN)

COM_AddCommand("nmr_addtomappool", function(player, poolname, mapname)
    if not poolname or not mapname then
        CONS_Printf(player, "Usage: nmr_addtomappool <poolname> <map>")
        CONS_Printf(player, "For example, nmr_addtomappool elim MAPHI")
        return
    end

    poolname = poolname:lower()

    local mapid = getMapId(mapname)

    mappool[poolname] = mappool[poolname] or {}

    mappool[poolname][mapid] = true
end, COM_ADMIN)

COM_AddCommand("nmr_setmappool", function(player, poolname)
    if not poolname then
        local refresh = mappool_current ~= nil

        mappool_current = nil

        CONS_Printf(player, "Map pool disabled")

        if refresh then
            refillMapsToVisit()
            CONS_Printf(player, "Map lists updated")
        end
    elseif mappool[poolname] then
        local refresh = mappool_current ~= poolname

        mappool_current = poolname

        CONS_Printf(player, "Map pool '"..poolname.."' selected")

        if refresh then
            refillMapsToVisit()
            CONS_Printf(player, "Map lists updated")
        end
    else
        CONS_Printf(player, "No map pool named "..poolname.." found")
    end
end, COM_ADMIN)

COM_AddCommand("nmr_mapinfo", function(player, name)
    if not name then
        CONS_Printf(player, "Usage: nmr_mapinfo <map>\nFor example, nmr_mapinfo MAPHI")
        return
    end

    local mapid = getMapId(name)

    if mapheaderinfo[mapid] == nil then
        CONS_Printf(player, "Map "..name.." does not exist")
    elseif remove_maps[mapid] then
        CONS_Printf(player, "Map "..name.." is removed from rotation")
    elseif mapheaderinfo[mapid].menuflags & LF2_HIDEINMENU then
        CONS_Printf(player, "Map "..name.." is a hell map")
    else
        CONS_Printf(player, "Map "..name.." is a regular map")
    end
end)

COM_AddCommand("nmr_printremoved", function(player)
    CONS_Printf(player, "Maps removed from rotation:")

    local buff = {}

    for mapid, _ in pairs(remove_maps) do
        table.insert(buff, G_BuildMapName(mapid))
    end

    CONS_Printf(player, table.concat(buff, " "))
end)

COM_AddCommand("nmr_numresets", function(player)
    CONS_Printf(player, string.format("List of maps has been reset %d times this session", resets))
end)
