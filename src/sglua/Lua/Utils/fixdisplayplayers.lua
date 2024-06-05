-- if two screens are viewing the same player, lib_iterateDisplayplayers locks up
-- well, unlike the Kart version, this time I'll fix it *without* breaking #displaylplayers
-- same caveat: pray that nobody does the parentheses

local oldindex = getmetatable(displayplayers).__index

getmetatable(displayplayers).__index = function(t, k)
	if k == "iterate" then
		local i = -1
		return function()
			i = i + 1
			if i >= 4 then return end
			return displayplayers[i], i
		end
	else return oldindex(t, k) end
end
