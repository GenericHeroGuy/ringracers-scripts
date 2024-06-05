rawset(_G, "CONFIG_Queue", CONFIG_Queue or {})

rawset(_G, "CONFIG_RegisterVar", function(var)
	table.insert(CONFIG_Queue, var)
	return CV_RegisterVar(var)
end)

-- G: altinter has since been merged with neoscoreboard, but figured I should preserve this text

-- Item rolls intermission (presumably) by /vm/ (Fuckal?)
-- Shows the item(s) the user(s) rolled in a round

-- Visually improved by Indev for Sunflower's Garden with suggestions from AnimeSonic/Sunflower#1739
-- Now shows ping as well (flex away!)
-- And no longer pops up if you spectate when you are alone.
-- Not done yet with this when it comes to improvements

-- Drawing system had to be re-done because that shit (v.drawPingNum) doesn't work in v1.6 for whatever reason, so numbers didn't show at all - Now does in Saturn v4!

-- Feel free to take the fork if you like the improvements ;) - AnimeSonic
-- Last update: November 4th, 2023
----------------------------

-- pain time

-- if we're using this heap of shit at all
local hm_itemanalyze = CV_RegisterVar({
	name = "hm_itemanalyze",
	defaultvalue = "On", -- I don't want to deal with complaints
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff
})
-- show sprays
local hm_itemanalyze_spray = CV_RegisterVar({
	name = "hm_itemanalyze_spray",
	defaultvalue = "On",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff
})
-- G from future: this is for the SG meme sprays, not the nontoxic chemical adhesive kind :P
-- (well, this is pretty awkward. not sure what do with those now...)

local hm_scoreboard = CV_RegisterVar({
	name = "hm_scoreboard",
	defaultvalue = "On",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff
})

local hm_scoreboard_local = CONFIG_RegisterVar{
	name = "hm_scoreboard_local",
	defaultvalue = "On",
	possiblevalue = CV_OnOff,

	config_menu = "Hostmod",
	displayname = "Neo Scoreboard",
	config_global = "hm_scoreboard",
	description = "Upgrade your scoreboard with a refreshing new look."
}
local hm_scoreboard_verbosestats = CONFIG_RegisterVar{
	name = "showallstats",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,

	config_menu = "Hostmod",
	displayname = "Show all stats",
	description = "Always show speed/weight on the scoreboard."
}
local hm_scoreboard_longnames = CONFIG_RegisterVar{
	name = "hm_scoreboard_longnames",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,

	config_menu = "Hostmod",
	displayname = "Long names",
	description = "Allow names to extend past the left edge of the screen."
}
local hm_scoreboard_pingdisplay = CONFIG_RegisterVar{
	name = "hm_scoreboard_pingdisplay",
	defaultvalue = "Bars",
	possiblevalue = { Bars = 0, ["Delay tics"] = 1 },

	config_menu = "Hostmod",
	displayname = "Ping display",
	description = "How to display each player's ping."
}
local hm_scoreboard_showminimum = CONFIG_RegisterVar{
	name = "hm_scoreboard_showminimum",
	defaultvalue = "HUD",
	possiblevalue = { Off = 0, HUD = 1, Scoreboard = 2 },

	config_menu = "Hostmod",
	displayname = "Minimum players",
	description = "Show the number of players required to start any active gameplay changes."
}
local hm_scoreboard_highresportrait = CONFIG_RegisterVar{
	name = "hm_scoreboard_highresportrait",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,

	config_menu = "Hostmod",
	displayname = "High Resolution Portrait",
	description = "Use high resolution portrait in scoreboard. Inverted if highresportrait is enabled.",
}
local hm_scoreboard_showmapid = CONFIG_RegisterVar{
	name = "hm_scoreboard_showmapid",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff,

	config_menu = "Hostmod",
	displayname = "Show Map IDs",
	description = "Display map ID near map name.",
}
local hm_scoreboard_showtext = CONFIG_RegisterVar{
	name = "hm_scoreboard_showtext",
	defaultvalue = "On",
	possiblevalue = CV_OnOff,

	config_menu = "Hostmod",
	displayname = "Show Information Text",
	description = "Display server information on the right side of scoreboard.",
}
local hm_scoreboard_scrollspeed = CONFIG_RegisterVar{
	name = "hm_scoreboard_scrollspeed",
	defaultvalue = "4",
	possiblevalue = CV_Natural,

	config_menu = "Hostmod",
	displayname = "Name Scroll Speed",
	description = "Determines how fast scrolling will be in scoreboard.",
}
local hm_scoreboard_silent = CV_RegisterVar({
	name = "hm_scoreboard_silent",
	defaultvalue = "Off",
	possiblevalue = CV_OnOff
})
local hm_inttime = CV_RegisterVar({
	name = "hm_inttime",
	defaultvalue = 10, // Changed to 10 for Sunflower's Garden
	flags = CV_NETVAR,
	possiblevalue = CV_Natural
})
local hm_scoreboard_linespacing = CV_RegisterVar({
	name = "hm_scoreboard_linespacing",
	defaultvalue = "3",
	flags = CV_NETVAR,
	possiblevalue = { MIN = 1, MAX = 10 }
})

local hm_motd_name = CV_RegisterVar({
	name = "hm_motd_name",
	defaultvalue = "",
	flags = CV_NETVAR
})
local hm_motd_contact = CV_RegisterVar({
	name = "hm_motd_contact",
	defaultvalue = "",
	flags = CV_NETVAR
})

local pingtable = { [0] = 1, 1, 2, 2, 3, 3, 3, 4, 4, 4 }
local pingcolors = { SKINCOLOR_CYAN, SKINCOLOR_SWAMP, SKINCOLOR_YELLOW, SKINCOLOR_ROSE }
local scroll, maxscroll = 0, 0
local namescroll, namescrolltimer = 0, TICRATE
local scrollreset = 0

local BASEVIDWIDTH = 320
local BASEVIDHEIGHT = 200
local ITEMLOG_X = BASEVIDWIDTH/2
local STATUS_OFFS = 157
local RANK_OFFS = 29
local ICON_WIDTH = 10
local ITEMLOG_SPACE = 2

local scoreboardmessages = {}
-- mods are now provided by the server host
local balancechanges = {}

local cv_highresportrait
local function useHighresPortrait()
	if cv_highresportrait and cv_highresportrait.value == 1 then
		return cv_highresportrait.value ~= hm_scoreboard_highresportrait.value
	end

	return hm_scoreboard_highresportrait.value == 1
end

local function lookupPortrait()
	if cv_highresportrait then return end
	cv_highresportrait = CV_FindVar("highresportrait")
end

addHook("MapLoad", lookupPortrait)
addHook("NetVars", lookupPortrait)

rawset(_G, "HM_Scoreboard_AddMod", function(fug)
	table.insert(balancechanges, fug)
end)

local function haveItemLogs(p)
	return p.itemlog and next(p.itemlog) and true or false
end

local function isHpmodEliminated(p)
    if not (hpmod and hpmod.running) then return false end
    if p.spectator then return false end
    if p.sinked then return false end
    if not (p.pflags & PF_NOCONTEST) then return false end
    if not (p.hpmod and p.hpmod.deathtimer > 0) then return false end
    
    return true
end

local function isNoContest(p)
    if not (p.pflags & PF_NOCONTEST) then return false end
    if p.sinked then return false end
    if isHpmodEliminated(p) then return false end
    
    return true
end

local function getPlayerRanks(spectators)
    local playerranks = {}

    -- Add players that are alive
    for plr in players.iterate do
        if not (plr.spectator or plr.pflags & PF_NOCONTEST) then
			table.insert(playerranks, plr)
        end
    end

    -- sort 'em
    table.sort(playerranks, function(a, b) return a.position < b.position end)

    -- Add players eliminated in elimination gamemode
    local elimplayers = {}
    for plr in players.iterate do
        if Elimination and Elimination() and plr.elim.iseliminated then
            table.insert(elimplayers, plr)
        end
    end

    -- (eliminatedtime or 0) - juuuust in case player has nil in that field.
    -- Dunno if thats possible but good to have protection just in case
    table.sort(elimplayers, function(a, b) return (a.elim.eliminatedtime or 0) > (b.elim.eliminatedtime or 0) end)

    for i, player in ipairs(elimplayers) do
        table.insert(playerranks, player)
    end

    -- Add players eliminated by kitchen sink
    for plr in players.iterate do
        if not plr.spectator and plr.sinked then
            table.insert(playerranks, plr)
        end
    end

    -- Add players eliminated by hp
    for plr in players.iterate do
        if not plr.spectator and isHpmodEliminated(plr) then
            table.insert(playerranks, plr)
        end
    end

    -- Add NO CONTEST'd players
    for plr in players.iterate do
        if not plr.spectator and isNoContest(plr) then
            table.insert(playerranks, plr)
        end
    end

    -- Add the rest of spectators
    for plr in players.iterate do
        if plr.spectator and not (Elimination and Elimination() and plr.elim.iseliminated) and (spectators or haveItemLogs(plr)) then
            table.insert(playerranks, plr)
        end
    end

    return playerranks
end

local function getTimeoverText(p)
    if p.sinked then
        return "\133SINKED"
    elseif isHpmodEliminated(p) then
        return "\133ELIMINATED"
    end
    
    return "NO CONTEST"
end

local function countPlayers()
	local c = 0

	for p in players.iterate do
		if not p.spectator then c = $ + 1 end
	end

	return c
end

local function countRacingPlayers()
	local c = 0

	for p in players.iterate do
		if not (p.spectator or p.exiting or p.pflags & PF_NOCONTEST) then c = c + 1 end
	end

	return c
end

local function canSetClan(fug)
	if not hm_scoreboard.value then
		return false, "This function has been disabled by the server host."
	end

	local lowerfug = fug:lower()
	if fug:len() > 10 then
		return false, "Too long."
	elseif lowerfug:match("staff") or lowerfug:match("admin") or lowerfug:match("krew") or lowerfug:match("~") or lowerfug:match("@") then
		return false, "Nice Try!"
	else
		return true
	end

	return false, "\130WARNING:\128 canSetClan() reached end of function how is that even possible"
end

local function createClanFunction(parseclan, condition)
	return function(p, ...)
		if not ... then
			p.clan = false
			CONS_Printf(p, "Clan tag removed.")
		else
			local failtext = condition and condition(p)

			if failtext then
				CONS_Printf(p, failtext)
				return
			end

			local clan, text = parseclan(...)

			if text then CONS_Printf(p, text) end

			if clan then
				p.clan = clan
			end
		end
	end
end

COM_AddCommand("clan", createClanFunction(function(...)
	local fug = table.concat({...}, " ")

	local can_set_clan, whynot = canSetClan(fug)
	if not can_set_clan then return nil, whynot end

	local lowerfug = fug:lower()

	if lowerfug:match("gang") then
		return fug, 'Tag set to "'..fug..'". :V'
	else
		return fug, 'Tag set to "'..fug..'".'
	end
end))

local cv_rainbowclan_points = CV_RegisterVar({
	name = "hm_rainbowclan_points",
	defaultvalue = "50",
	possiblevalue = CV_Unsigned,
	flags = CV_NETVAR,
})
COM_AddCommand("rainbowclan", createClanFunction(function(...)
		local str = table.concat({...}, " ")

		local can_set_clan, whynot = canSetClan(str)
		if not can_set_clan then return nil, whynot end

		local colors = {'\133', '\135', '\130', '\131', '\136', '\132', '\137'}
		local buff = {}
		local len = #str

		for i = 0, len-1 do
			table.insert(buff, colors[i % 7 + 1])
			table.insert(buff, str:sub(i+1, i+1))
		end

		local result = table.concat(buff, "")

		return result, 'Tag set to "'..result..'\128"'
	end,
	function(player)
		if player.score < cv_rainbowclan_points.value then
			return "You need to have "..cv_rainbowclan_points.value.." points for this"
		end
	end
))

local cv_colorclan_points = CV_RegisterVar({
	name = "hm_colorclan_points",
	defaultvalue = "0",
	possiblevalue = CV_Unsigned,
	flags = CV_NETVAR,
})

COM_AddCommand("colorclan", createClanFunction(function(colornum, ...)
		local color = tonumber(colornum)

		local usage = "Usage: colorclan <colornum> <clantag>\ncolornum is number between 1 and 14"

		if not color or (color < 1 or color > 14) then
			return nil, usage
		end

		local str = table.concat({...}, " ")

		if #str == 0 then return nil, usage end

		local can_set_clan, whynot = canSetClan(str)
		if not can_set_clan then return nil, whynot end

		local colorchar = string.char(string.byte('\128') + color)

		return colorchar..str, 'Tag set to "'..colorchar..str..'\128"'
	end,
	function(player)
		if player.score < cv_colorclan_points.value then
			return "You need to have "..cv_colorclan_points.value.." points for this"
		end
	end
))

-- I KNOW THERE'S A FUCKIN FUNCTION IN SOURCE FOR THIS
-- WHY IS IT NOT EXPOSED TO LUA
-- LAAAAAAAAAAAAAAAAAAAAAAT
local function wrapString(str, width, v, flags, font)
	local linebuffer = ""
	local retlines = {}
	local color = ""
	for word in str:gmatch("%S+%s*") do
		local newlines = 0
		while word:find("\n") do
			word = $:sub(1, -2)
			newlines = $ + 1
		end
		if v.stringWidth(linebuffer..word, flags, font) > width then
			table.insert(retlines, linebuffer)
			linebuffer = color
			newlines = $ - 1
		end
		for c in word:gmatch("[\128-\143]") do
			color = c
		end
		linebuffer = $..word
		for i = 1, newlines do
			table.insert(retlines, linebuffer)
			linebuffer = color
		end
	end
	if linebuffer ~= "" then table.insert(retlines, linebuffer) end
	return retlines
end

COM_AddCommand("hm_scoreboard_addline", function(p, line)
	if not line then
		-- python moment
		CONS_Printf(p, "Usage: hm_scoreboard_addline \"sample text\"",
		               "",
		               "Use \\q to insert double quotes \", \\n to insert new line",
		               "\128\\128\129\\129\130\\130\131\\131\132\\132\133\\133\134\\134\135\\135\136\\136\137\\137\138\\138\139\\139\140\\140\141\\141\142\\142\143\\143")
		return
	end
	line = SG_Escape($).."\n"
	while line ~= "" do
		local _, e = line:find("\n")
		local l = line:sub(1, e-1)
		line = $:sub(e+1)
		table.insert(scoreboardmessages, l)
		if not hm_scoreboard_silent.value then CONS_Printf(p, "Added line "..l) end
	end
end, COM_ADMIN)

COM_AddCommand("hm_scoreboard_addmod", function(p, mod, cvar, minplayers, shortname, checkvar)
	if not mod then
		CONS_Printf(p, "Usage: hm_scoreboard_addmod \"mod title\" <cvar> <minplayers> <shortname> <checkvar>",
		               "",
		               "minplayers cvar is used to display player count on scoreboard",
		               "shortname, if provided, allows displaying minplayers on game HUD",
		               "checkvar is name of global Lua variable to check if mod is active",
		               "Use \\q to insert double quotes \"", -- please don't use newlines :(
		               "\128\\128\129\\129\130\\130\131\\131\132\\132\133\\133\134\\134\135\\135\136\\136\137\\137\138\\138\139\\139\140\\140\141\\141\142\\142\143\\143")
		return
	end

	mod = SG_Escape($)

	table.insert(balancechanges, { disp = mod, var = cvar, minplayers = minplayers, shortname = shortname, checkvar = checkvar })
	if not hm_scoreboard_silent.value then CONS_Printf(p, "Added mod "..mod..(cvar and ("\128, with cvar "..cvar) or "")) end
end, COM_ADMIN)

COM_AddCommand("hm_scoreboard_clearlines", function(p)
	scoreboardmessages = {}
	CONS_Printf(p, "Cleared all lines")
end, COM_ADMIN)

COM_AddCommand("hm_scoreboard_clearmods", function(p)
	balancechanges = {}
	CONS_Printf(p, "Cleared all mods")
end, COM_ADMIN)

addHook("NetVars", function(sync)
	scoreboardmessages = sync($)
	balancechanges = sync($)
end)

addHook("ThinkFrame", function()
	if leveltime == 0 then return end
	
	scrollreset = $ + 1
	
	if scrollreset == 2 then
		scroll = 0
	end

	-- "Do not alter player_t in HUD rendering code!" :nerd:
	--[[ G from future: oh yeah, remember when you had to pull this shit?
	for p in players.iterate do
		local oldspec = p.spectator
		p.spectator = false
		-- start simple, just scoreboard for now...
		p.hostmod.skin = p.mo.localskin or p.mo.skin
		p.hostmod.color = p.mo.color
		p.hostmod.colorized = p.mo.colorized
		p.spectator = oldspec
	end
	--]]

	--[[
	if not hm_itemanalyze.value or FRIENDMOD_Active then return end

	-- Why would you need timestring if alt intermission isn't even shown
	if countRacingPlayers() == 0 then
		-- Also run finish check here
		if countPlayers() > 1 then
			local intermissiontime = hm_inttime.value*TICRATE
			K_SetExitCountdown((TICRATE*2) + intermissiontime)

			if not server.hmfinishstate then
				server.hmfinishtimer = intermissiontime + TICRATE/4 --  enough time for you to get a drink or two
			end

			server.hmfinishstate = true

			for p in players.iterate do
				if not (p.spectator or p.pflags & PF_NOCONTEST) then
					p.exiting = 8
					p.powers[pw_nocontrol] = intermissiontime + TICRATE/4
				end
			end
		end
	end

	if server.hmfinishstate then
		server.hmfinishtimer = $ - 1
		if not server.hmfinishtimer and countPlayers() then
			G_ExitLevel()
		end
	end
	--]]
end)

addHook("PlayerThink", function(p)
	local log = p.itemlog

	local rolleditem = p.itemtype
	if rolleditem > 0 and log.lastrolled ~= rolleditem then
		log[rolleditem] = ($ or 0) + max(1, p.itemamount)
	end
	log.lastrolled = rolleditem
end)

addHook("MapLoad", function()
	for p in players.iterate do
		p.itemlog = {}
	end

	scroll = maxscroll
	--server.hmfinishstate = false

	--scoreboardmessages = SG_Archive($)
	--balancechanges = SG_Archive($)
end)

local cv_menuhighlight -- :^)
local function getHighlightColor()
	if cv_menuhighlight == nil then
		cv_menuhighlight = CV_FindVar("menuhighlight") or false
	end
	return cv_menuhighlight and cv_menuhighlight.value or (modeattackaing and V_ORANGEMAP or (gametype == GT_RACE and V_SKYMAP or V_REDMAP))
end

local faketimer = 0

-- draw players and separators
local function drawBaseHud(v, spectators, extrafunc)
	-- FIXME - 'spectators' condition is used to detect item intermission. If it ever changes to
	-- display spectators, it would break!
	local morespace = (not hm_scoreboard_showtext.value) and spectators

	-- store highlight colour here for use in the hud throughout
	local hilicol = getHighlightColor()

	-- scroll the whole thing
	if not replayplayback then
		if consoleplayer.spectator then
			scroll = $ + ((consoleplayer.cmd.forwardmove > 0) and hm_scoreboard_scrollspeed.value or 0)
			scroll = $ - ((consoleplayer.cmd.forwardmove < 0) and hm_scoreboard_scrollspeed.value or 0)
		else
			scroll = $ + ((consoleplayer.cmd.buttons & BT_BRAKE) and hm_scoreboard_scrollspeed.value or 0)
			scroll = $ - ((consoleplayer.cmd.buttons & BT_ATTACK) and hm_scoreboard_scrollspeed.value or 0)
		end
	end
	scroll = min(0, max($, maxscroll))

	local scrwidth = gamestate == GS_LEVEL and v.width()/v.dupx() or 320

	-- draw line between players and info
	local duptweak = (scrwidth - 320)/2 -- BASEDVIDWIDTH = 320 (based on what?)
	v.drawFill(1-duptweak, scroll+26, scrwidth-2, 1, 0) -- horizontal
	
	if not morespace then
		v.drawFill(160, scroll+26, 1, 162+(-scroll), 0) -- vertical
	end

	local playerranks = getPlayerRanks(spectators)

	local rightclipped = false

	-- draw players
	for rank, p in ipairs(playerranks) do
		local hy = 28 + scroll + (rank-1)*10
		local eliminated = Elimination and p.elim.iseliminated
		local specflag = ((p.spectator or p.rs_check2) and not eliminated) and V_50TRANS or 0
		local color = 0

		-- status
		local status = ""
		if p.spectator then
			if eliminated then
				status = "ELIMINATED"
				color = V_REDMAP
			elseif p.pflags & PF_WANTSTOJOIN then
				status = "WAIT"
			else
				status = "SPEC"
			end
		elseif Elimination and p.elim.isplaying and p.exiting then
			status = "SURVIVED"
			color = V_GREENMAP
		elseif p.rs_check2 then
			status = "RAGE"
			color = V_REDMAP
		elseif p.pflags & PF_NOCONTEST then
			status = getTimeoverText(p)
		elseif gametype == GT_BATTLE then
			status = p.roundscore
		elseif not p.exiting then
			status = "LAP "..p.laps
		else
			local t = p.realtime
			status = (t/(60*TICRATE)).."' "..string.format("%02d", (t/TICRATE)%60)..'" '..string.format("%02d", G_TicsToCentiseconds(t))
		end
		if p.exiting and not color then color = hilicol end
		v.drawString(morespace and 295 or 157, hy, status, V_6WIDTHSPACE|specflag|color, "thin-right")
		local statuswidth = v.stringWidth(status, V_6WIDTHSPACE, "thin")

		-- player name
		local clan = p.clan and "\134"..p.clan.."\128 " or "" 
		local clanwidth = v.stringWidth(clan, V_6WIDTHSPACE, "thin")
		local fugname = p.name

		local clipwidth = 117 - statuswidth - clanwidth
		local clipname = false
		local pushx, leftscr = 0, 0
		local namescr = namescroll

		if v.stringWidth(fugname, V_6WIDTHSPACE, "thin") > clipwidth then
			local wideclip = hm_scoreboard_longnames.value and (max(0, scrwidth - 320) / 2) or 0
			if v.stringWidth(fugname, V_6WIDTHSPACE, "thin") <= clipwidth + wideclip then
				pushx = v.stringWidth(fugname, V_6WIDTHSPACE, "thin") - clipwidth
			else
				pushx = wideclip
				clipwidth = $ + pushx
				clipname = true
			end
		end

		if clipname then
			-- scroll stop
			if v.stringWidth(fugname, V_6WIDTHSPACE, "thin") - namescr < clipwidth then
				namescr = v.stringWidth(fugname, V_6WIDTHSPACE, "thin") - clipwidth + 1
			end

			-- cut right end
			while v.stringWidth(fugname, V_6WIDTHSPACE, "thin") - namescr >= clipwidth do
				fugname = $:sub(1, -2)
				if fugname == "" then break end
				rightclipped = true
			end

			-- cut left end
			local snip = ""
			while v.stringWidth(snip, V_6WIDTHSPACE, "thin") < namescr do
				snip = $..fugname:sub(1, 1)
				fugname = $:sub(2)
				if fugname == "" then break end
			end
			leftscr = v.stringWidth(snip, V_6WIDTHSPACE, "thin")
		end

		-- highlight displayplayer names
		for dp in displayplayers.iterate do
			if dp == p then
				fugname = string.char(128 + (skincolors[p.skincolor].chatcolor >> V_CHARCOLORSHIFT))..$
				break
			end
		end

		-- scroll name, push clan to the left
		if clipname then
			v.drawString(39 - pushx, hy, clan, V_6WIDTHSPACE|specflag, "thin")
			v.drawString(clanwidth + 39 - pushx - namescr + leftscr, hy, fugname, V_6WIDTHSPACE|specflag, "thin")
		else
			v.drawString(39 - pushx, hy, clan..fugname, V_6WIDTHSPACE|specflag, "thin")
		end

		-- icon
		local pp = v.getSprite2Patch(p.skin, SPR2_XTRA, useHighresPortrait() and 1 or 0)
		
		-- TODO - better check maybe?
		if APPEAR_GetAppearance and APPEAR_GetAppearance(p, p.skin) ~= "default" then
			pp = useHighresPortrait() and APPEAR_GetWantedGFX(p, p.skin) or APPEAR_GetRankGFX(p, p.skin) or pp
		end
		
		local downscale = useHighresPortrait() and 2 or 1

		local cmap
		if gamestate == GS_LEVEL and p.mo then
			cmap = v.getColormap(p.mo.colorized and TC_RAINBOW or p.mo.skin, p.mo.color)
		else
			cmap = v.getColormap(p.skin, p.skincolor)
		end
		local dieflag = 0

		if gamestate == GS_LEVEL and gametype == GT_BATTLE and p.mo.health <= 0 then
			cmap = v.getColormap(TC_RAINBOW, SKINCOLOR_GREY)
			dieflag = V_50TRANS
		end

		v.drawScaled((30-pushx)<<FRACBITS, (hy+1)<<FRACBITS, FRACUNIT/2/downscale, pp, specflag|dieflag, cmap)

		-- highlight consoleplayer
		if not replayplayback and p == consoleplayer and splitscreen == 0 then
			v.drawScaled((30-pushx)<<FRACBITS, (hy+1)<<FRACBITS, FRACUNIT/2, v.cachePatch("k_chili"..((faketimer / 4) % 8)+1), specflag|dieflag)
		end

		-- restat
		if (p.hostmod and p.hostmod.restat) or hm_scoreboard_verbosestats.value then
			local restatflag = (hm_scoreboard_verbosestats.value and p.hostmod.restat) and V_YELLOWMAP or 0
			v.drawString(29-pushx, hy, p.kartspeed, restatflag, "small")
			v.drawString(39-pushx, hy+6, p.kartweight, restatflag, "small-right")
		end

		-- rank
		if (not p.spectator) or eliminated then
			local pos = eliminated and p.elim.eliminatedpos or p.position
			v.drawString(29-pushx, hy+1, pos, 0, "right")
		end

		-- ping
		if (p ~= server and netgame) or p._finallatency then
			local ping = max(p.ping, p._finallatency or 0)
			if hm_scoreboard_pingdisplay.value and ping < 10 then
				local cmap = v.getColormap(TC_RAINBOW, pingcolors[pingtable[ping]])
				v.draw(3-pushx, hy+1, v.cachePatch("PINGD"), specflag, cmap)
				v.draw(7-pushx, hy+1, v.cachePatch("PINGN"..ping), specflag, cmap)
			else
				v.draw(3-pushx, hy, v.cachePatch("PINGGFX"..(pingtable[ping] or 5)), specflag)
			end
		end

		-- extra function
		if extrafunc then extrafunc(v, p, hy) end
	end

	-- scroll names if they're getting clipped
	if namescrolltimer == 0 and rightclipped then
		namescroll = $ + 1
		namescrolltimer = 3
	end

	namescrolltimer = $ - 1

	-- if not, reset scrolling after a while
	if namescrolltimer == -TICRATE then
		namescroll = 0
		namescrolltimer = TICRATE
	end
	
	-- Reset it every frame when it gets drawn, so when you close tab screen for 2 tics
	-- namescroll gets reset
	scrollreset = 0

	-- max scroll
	return (#playerranks - 16) * -10
end

local function getMapTitle()
	return G_BuildMapTitle(gamemap)..(hm_scoreboard_showmapid.value and " - "..G_BuildMapName(gamemap) or "")
end

-- hacked-up TSR scoreboard, WHEEEEEEEEEEEEEEE
-- thanks snu
local speeds = { [0] = "Gear 1", "Gear 2", "Gear 3" }
local fourthgear
hud.add(function(v)
	if not (hm_scoreboard.value and hm_scoreboard_local.value) then
		hud.enable("intermissiontally") -- = rankings
		return
	end
	hud.disable("intermissiontally") -- = rankings

	faketimer = $ + 1

	-- XXX: you cannot access NOSHOWHELP vars at all
	--if not fourthgear then fourthgear = CV_FindVar("4thgear") end

	local hilicol = getHighlightColor()

	v.fadeScreen(0xFF00, 16)

	-- draw the base HUD and get the max scroll for players
	local pscroll = drawBaseHud(v, true)

	-- draw lap count and game speed
	if gametype == GT_RACE then
		if gametyperules & GTR_CIRCUIT then
			v.drawString(64, scroll+8, "LAPS", 0, "center")
			v.drawString(64, scroll+16, numlaps, hilicol, "center")
		end
		v.drawString(256, scroll+8, "GAME SPEED", 0, "center")
		v.drawString(256, scroll+16, --[[fourthgear.value and "4th Gear" or--]] speeds[gamespeed], hilicol, "center")
	else
		local timelimitintics = timelimit
		if timelimitintics > 0 then
			if leveltime <= timelimitintics + starttime then
				v.drawString(64, scroll+8, "TIME LEFT", 0, "center")
				v.drawString(64, scroll+16, min(timelimitintics, timelimitintics + starttime + 1 - leveltime) / TICRATE, hilicol, "center")
			-- don't mind the usage of consoleplayer here, it's vanilla behavior
			elseif (consoleplayer.valid and not consoleplayer.exiting) and leveltime > timelimitintics + starttime + TICRATE/2 and CV_FindVar("overtime").value then
				v.drawString(64, scroll+8, "TIME LEFT", 0, "center")
				v.drawString(64, scroll+16, "OVERTIME", hilicol, "center")
			end
		end
		if pointlimit > 0 then
			v.drawString(256, scroll+8, "POINT LIMIT", 0, "center")
			v.drawString(256, scroll+16, pointlimit, hilicol, "center")
		end
	end

	-- draw right pane
	local fy = 28+scroll
	local fx = 163
	local off = 0 -- right pane line offset OH GOD this code is everywhere

	if hm_scoreboard_showtext.value then
		if hm_motd_name.string ~= "" then
			v.drawString(fx, fy, SG_Escape(hm_motd_name.string), 0, "thin")
			v.drawString(fx, fy+10, "\134Contact: "..SG_Escape(hm_motd_contact.string), 0, "small")
			off = $ + 20
		end

		if #scoreboardmessages > 0 then
			for _, line in ipairs(scoreboardmessages) do
				v.drawString(fx, fy+off, line, 0, "small")
				off = $ + (line == " " and hm_scoreboard_linespacing.value or 5)
			end
			off = $ + 2
		end

		-- gameplay changes
		local drew = false
		local pcount = 0
		if hm_scoreboard_showminimum.value == 2 then
			for p in players.iterate do
				if (not p.spectator) or p.pflags & PF_WANTSTOJOIN then
					pcount = $ + 1
				end
			end
		end

		local right = false
		for _, mod in ipairs(balancechanges) do
			local cvar = mod.var and CV_FindVar(mod.var)
			if not cvar or (cvar and cvar.value) then
				if not drew then
					v.drawString(fx, fy+off, "\131Gameplay \128/ \134Balance Changes:", 0, "thin")
					off = $ + 10
				end
				drew = true

				local display = mod.disp

				if hm_scoreboard_showminimum.value == 2 then
					local minp = mod.minplayers and CV_FindVar(mod.minplayers)
					if minp then
						if pcount < minp.value then
							display = $.." \128("..pcount.."/"..minp.value..")"
						elseif rawget(_G, mod.checkvar) == false then
							display = $.." \128(WAIT)"
						end
					end
				end

				v.drawString(fx+(right and 77 or 0), fy+off, display, 0, "small")

				local long = v.stringWidth(display, 0, "small") > 80 -- SG fast respawn is too long lol
				if long or right then
					off = $ + 5
					right = false
				else
					right = true
				end
			end
		end
		if drew then off = ($ / 2) + ($ % 2) + 5 end
	end

	-- draw map title
	v.drawString(4, 188, getMapTitle() --[[.." - "..mapheaderinfo[gamemap].subttl--]], V_SNAPTOBOTTOM|V_SNAPTOLEFT, "thin")

	-- calculate max scroll
	maxscroll = min(pscroll, -off + 162)
end, "scores")

-- good ol' SG elim-style player counts
hud.add(function(v, p)
	if hm_scoreboard_showminimum.value ~= 1 or p ~= displayplayers[splitscreen] or SG_HideHud then return end

	local display = ""
	local pcount = 0
	for p in players.iterate do
		if (not p.spectator) or p.pflags & PF_WANTSTOJOIN then
			pcount = $ + 1
		end
	end

	local sortedmods = {}
	for _, mod in ipairs(balancechanges) do
		if mod.var and mod.minplayers and mod.shortname then
			local cvar = CV_FindVar(mod.var)
			local minp = CV_FindVar(mod.minplayers)
			if not cvar or (cvar and cvar.value and minp) then
				table.insert(sortedmods, { name = mod.shortname, value = minp.value, check = rawget(_G, mod.checkvar) })
			end
		end
	end

	table.sort(sortedmods, function(a, b) return a.value < b.value end)

	-- first, find the mod with the lowest min players count
	local numdots = #players
	for _, smod in ipairs(sortedmods) do
		if smod.value < numdots and pcount < smod.value and not smod.check then
			numdots = smod.value
			display = smod.name.." "
		elseif smod.value == numdots and not smod.check then
			display = $..smod.name.." "
		end
	end

	-- if there's nothing to show, show waiting mod(s)
	local waiting = false
	if display == "" then
		waiting = true
		numdots = 0
		for _, smod in ipairs(sortedmods) do
			if pcount >= smod.value and smod.check == false then
				display = $..smod.name.." "
				numdots = max($, smod.value)
			end
		end
	end

	-- still nothing? then give up
	if display == "" then return end

	local flags = V_SNAPTOTOP | V_SNAPTORIGHT | (waiting and V_HUDTRANS or V_HUDTRANSHALF)
	if not (waiting and (leveltime % TICRATE) < TICRATE/2) then
		v.drawString(320 - 8 - numdots*7, 35, display, flags|(waiting and V_GREENMAP or V_REDMAP), "right")
	end

	-- dots
	local x = 320 - 8 - numdots*7
	for i = 1, numdots do
		local dot = i > pcount and v.cachePatch("K_SDOT0") or v.cachePatch("K_SDOT1")
		v.draw(x, 36, dot, flags)
		x = $ + 7
	end
end)
	

-- v.drawPingNum is broken so i'm making my own
-- (actually it is almost exact copy of V_DrawPingNum from kart source, no idea why is it broken)
local num_patches = nil
local function drawPingNum(v, x, y, num, flags)
	x = x - 3 -- Idk why i have to do this but without that numbers have weird offset

	if not num_patches then
		num_patches = {}

		for i = 0, 9 do
			num_patches[i] = v.cachePatch("PINGN"..i)
		end
	end

	local w = num_patches[0].width

	if num == 0 then
		v.drawScaled(x<<FRACBITS, y<<FRACBITS, FRACUNIT, num_patches[0], flags)
	else
		if num < 0 then num = -num end

		while num ~= 0 do
			local digit = num % 10
			num = num / 10

			v.drawScaled(x<<FRACBITS, y<<FRACBITS, FRACUNIT, num_patches[digit], flags)
			x = x - (w-1)
		end
	end
end

local miniitemgfx
local sadface
local INVFRAMES = { [0] = "K_ISINV1", "K_ISINV2", "K_ISINV3", "K_ISINV4", "K_ISINV5", "K_ISINV6" }

hud.add(function(v)
	if not (hm_scoreboard.value and hm_scoreboard_local.value) then
		hud.enable("intermissionmessages") -- = intermissiontally
		return
	end
	hud.disable("intermissionmessages") -- = intermissiontally

	faketimer = $ + 1

	if not miniitemgfx then
		miniitemgfx = {}
		for i = 1, NUMKARTITEMS do
			miniitemgfx[i] = v.cachePatch(K_GetItemPatch(i, true))
		end
		sadface = v.cachePatch(K_GetItemPatch(KITEM_SAD, true))
	end
	-- animate invincibility
	miniitemgfx[KITEM_INVINCIBILITY] = v.cachePatch(INVFRAMES[faketimer % (3 * #INVFRAMES) / 3])

	--[[
	if not hm_itemanalyze.value
	or FRIENDMOD_Active
	or (driftmodData and driftmodData.isOn) -- why would you need this in nitro
	or (countRacingPlayers() > 0) -- There are still racing players
	or not (p.exiting or (p.pflags & PF_NOCONTEST) or (p.spectator and countRacingPlayers() == 0 and countPlayers() > 0)) -- not even finishing
	or (server.SPBAdone and countPlayers() < 2)
	or not (intertype == int_race or intertype == int_match) then
		return
	end
	--]]

	maxscroll = drawBaseHud(v, false, function(v, p, y)
		local log = p.itemlog
		if not log then return end

		local dx = ITEMLOG_X+4

		-- draw item icons
		for itype = 1, NUMKARTITEMS do
			local irolls = log[itype]
			if irolls then
				v.drawScaled((dx<<FRACBITS) - (25*FRACUNIT/4), (y<<FRACBITS) - (25*FRACUNIT/4), FRACUNIT/2, miniitemgfx[itype] or sadface)
				dx = $ + 10 + max(0, (#tostring(irolls)*5)-5) + ITEMLOG_SPACE
			end
		end

		dx = ITEMLOG_X+4

		-- draw item amounts
		for itype = 1, NUMKARTITEMS do
			local irolls = log[itype]
			if irolls then
				local ir_length = #tostring(irolls)
				drawPingNum(v, dx+8+(max(0, ir_length - 1)*5), y+2, irolls, 0)
				dx = $ + 10 + max(0, (ir_length*5)-5) + ITEMLOG_SPACE
			end
		end

		-- draw spray
		if hm_itemanalyze_spray.value and p.spray then
			v.drawScaled((dx+12)<<FRACBITS, (y)<<FRACBITS, FRACUNIT/2, v.cachePatch("SPRAYCAN"), 0, v.getColormap(TC_DEFAULT, p.skincolor))
		end
	end)

	-- add a notch to the top separator
	v.drawFill(160, scroll+14, 1, 12, 0)

	-- draw level name
	v.drawString(BASEVIDWIDTH/2, scroll+4, (encoremode and "* \129ENCORE\128 " or "* ")..getMapTitle().." *", 0, "center")

	local hilicol = getHighlightColor()
	v.drawString(RANK_OFFS, scroll+16, "#", hilicol, "right")
	v.drawString(RANK_OFFS+10, scroll+16, "Name", hilicol)
	v.drawString(STATUS_OFFS, scroll+16, "Time", hilicol, "right")
	v.drawString(ITEMLOG_X+4, scroll+16, "Rolls", hilicol)

	--[[
	if server.hmfinishtimer ~= nil then
		v.drawString(4, 188, "Exiting this screen in "..(server.hmfinishtimer / TICRATE).." seconds.", hilicol|V_SNAPTOBOTTOM|V_SNAPTOLEFT, "thin")
	end
	--]]
end, "intermission")
