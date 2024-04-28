local disable_ringboxes = CV_RegisterVar({
	name = "disable_ringboxes",
	defaultvalue = "On",
	flags = CV_NETVAR,
	possiblevalue = CV_OnOff,
	description = "Disables ringboxes"
})

-- No ringboxes
addHook("MobjThinker", function(mo)
	if not disable_ringboxes.value then return end

	if mo.state == S_RINGBOX1 or mo.state == S_RINGBOX2  
	or mo.state == S_RINGBOX3  or mo.state == S_RINGBOX4 
	or mo.state == S_RINGBOX5  or mo.state == S_RINGBOX6  
	or mo.state == S_RINGBOX7  or mo.state == S_RINGBOX8 
	or mo.state == S_RINGBOX9  or mo.state == S_RINGBOX10  
	or mo.state == S_RINGBOX11  or mo.state == S_RINGBOX12 then  
		mo.state = S_RANDOMITEM1
	end

end,MT_RANDOMITEM)