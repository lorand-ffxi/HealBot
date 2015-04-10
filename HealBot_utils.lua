--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot utility functions that don't belong anywhere else
--]]
--==============================================================================
--			Input Handling Functions
--==============================================================================

function processCommand(command,...)
	command = command and command:lower() or 'help'
	local args = {...}
	
	if command == 'reload' then
		windower.send_command('lua reload healBot')
	elseif command == 'unload' then
		windower.send_command('lua unload healBot')
	elseif command == 'refresh' then
		load_configs()
	elseif S{'start','on'}:contains(command) then
		activate()
	elseif S{'stop','end','off'}:contains(command) then
		active = false
		printStatus()
	elseif S{'disable'}:contains(command) then
		if not validate(args, 1, 'Error: No argument specified for Disable') then return end
		disableCommand(args[1]:lower(), true)
	elseif S{'enable'}:contains(command) then
		if not validate(args, 1, 'Error: No argument specified for Enable') then return end	
		disableCommand(args[1]:lower(), false)
	elseif S{'assist','as'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (settings.assist.active and 'off' or 'resume')
		if S{'off','end','false','pause'}:contains(cmd) then
			settings.assist.active = false
			atc('Assist is now off.')
		elseif S{'resume'}:contains(cmd) then
			if (settings.assist.name ~= nil) then
				settings.assist.active = true
				atc('Now assisting '..settings.assist.name..'.')
			else
				atc(123,'Error: Unable to resume assist - no target set')
			end
		elseif S{'attack','engage'}:contains(cmd) then
			local cmd2 = args[2] and args[2]:lower() or (settings.assist.engage and 'off' or 'resume')
			if S{'off','end','false','pause'}:contains(cmd2) then
				settings.assist.engage = false
				atc('Will no longer enagage when assisting.')
			else
				settings.assist.engage = true
				atc('Will now enagage when assisting.')
			end
		else	--args[1] is guaranteed to have a value if this is reached
			local pname = getPlayerName(args[1])
			if (pname ~= nil) then
				settings.assist.name = pname
				settings.assist.active = true
				atc('Now assisting '..settings.assist.name..'.')
			else
				atc(123,'Error: Invalid name provided as an assist target: '..tostring(args[1]))
			end
		end
	elseif S{'ws','weaponskill'}:contains(command) then
		local lte,gte = string.char(0x81, 0x85),string.char(0x81, 0x86)
		local cmd = args[1] and args[1] or ''
		settings.ws = settings.ws or {}
		if S{'use','set'}:contains(cmd) then	-- ws name
			table.remove(args, 1)
			local argstr = table.concat(args,' ')
			local wsname = formatSpellName(argstr)
			local ws = getActionFor(wsname)
			if (ws ~= nil) then
				settings.ws.name = wsname
				atc('Will now use '..wsname)
			else
				atc(123,'Error: Invalid weaponskill name: '..wsname)
			end
		elseif (cmd == 'waitfor') then		--another player's TP
			local partner = getPlayerName(args[2])
			if (partner ~= nil) then
				local partnertp = tonumber(args[3]) or 1000
				settings.ws.partner = {name=partner,tp=partnertp}
				atc("Will weaponskill when "..partner.."'s TP is "..gte.." "..partnertp)
			else
				atc(123,'Error: Invalid argument for ws waitfor: '..tostring(args[2]))
			end
		elseif (cmd == 'nopartner') then
			settings.ws.partner = nil
			atc('Weaponskill partner removed.')
		elseif (cmd == 'hp') then		--Target's HP
			local sign = S{'<','>'}:contains(args[2]) and args[2] or nil
			local hp = tonumber(args[3])
			if (sign ~= nil) and (hp ~= nil) then
				settings.ws.sign = sign
				settings.ws.hp = hp
				atc("Will weaponskill when the target's HP is "..sign.." "..hp.."%")
			else
				atc(123,'Error: Invalid arguments for ws hp: '..tostring(args[2])..', '..tostring(args[3]))
			end
		end
	elseif S{'spam','nuke'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (settings.nuke.active and 'off' or 'on')
		if S{'on','true'}:contains(cmd) then
			settings.nuke.active = true
			if (settings.nuke.name ~= nil) then
				atc('Spell spamming is now on. Spell: '..settings.nuke.name)
			else
				atc('Spell spamming is now on. To set a spell to use: //hb spam use <spell>')
			end
		elseif S{'off','false'}:contains(cmd) then
			settings.nuke.active = false
			atc('Spell spamming is now off.')
		elseif S{'use','set'}:contains(cmd) then
			table.remove(args, 1)
			local argstr = table.concat(args,' ')
			local spell_name = formatSpellName(argstr)
			local spell = getActionFor(spell_name)
			if (spell ~= nil) then
				if Assert.can_use(spell) then
					settings.nuke.name = spell.en
					atc('Will now spam '..settings.nuke.name)
				else
					atc(123,'Error: Unable to cast '..spell.en)
				end
			else
				atc(123,'Error: Invalid spell name: '..spell_name)
			end
		end
	elseif command == 'mincure' then
		if not validate(args, 1, 'Error: No argument specified for minCure') then return end
		local val = tonumber(args[1])
		if (val ~= nil) and (1 <= val) and (val <= 6) then
			minCureTier = val
			atc('Minimum cure tier set to '..minCureTier)
		else
			atc('Error: Invalid argument specified for minCure')
		end
	elseif command == 'reset' then
		if not validate(args, 1, 'Error: No argument specified for reset') then return end
		local rcmd = args[1]:lower()
		local b,d = false,false
		if S{'all','both'}:contains(rcmd) then
			b,d = true,true
		elseif (rcmd == 'buffs') then
			b = true
		elseif (rcmd == 'debuffs') then
			d = true
		else
			atc('Error: Invalid argument specified for reset: '..arg[1])
			return
		end
		
		local resetTarget
		if (args[2] ~= nil) and (args[3] ~= nil) and (args[2]:lower() == 'on') then
			local pname = getPlayerName(args[3])
			if (pname ~= nil) then
				resetTarget = pname
			else
				atc(123,'Error: Invalid name provided as a reset target: '..tostring(args[3]))
				return
			end
		end
		
		if b then
			if (resetTarget ~= nil) then
				resetBuffTimers(resetTarget)
				atc('Buffs registered for '..resetTarget..' were reset.')
			else
				for player,_ in pairs(buffList) do
					resetBuffTimers(player)
				end
				atc('Buffs registered for all monitored players were reset.')
			end
		end
		if d then
			if (resetTarget ~= nil) then
				debuffList[resetTarget]= {}
				atc('Debuffs registered for '..resetTarget..' were reset.')
			else
				debuffList = {}
				atc('Debuffs registered for all monitored players were reset.')
			end
		end
	elseif command == 'buff' then
		registerNewBuff(args, true)
	elseif command == 'cancelbuff' then
		registerNewBuff(args, false)
	elseif command == 'bufflist' then
		if not validate(args, 1, 'Error: No argument specified for BuffList') then return end
		local blist = defaultBuffs[args[1]]
		if blist ~= nil then
			for _,buff in pairs(blist) do
				registerNewBuff({args[2], buff}, true)
			end
		else
			atc('Error: Invalid argument specified for BuffList: '..args[1])
		end
	elseif command == 'ignore_debuff' then
		registerIgnoreDebuff(args, true)
	elseif command == 'unignore_debuff' then
		registerIgnoreDebuff(args, false)
	elseif S{'follow','f'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (settings.follow.active and 'off' or 'resume')
		if S{'off','end','false','pause'}:contains(cmd) then
			settings.follow.active = false
		elseif S{'distance', 'dist', 'd'}:contains(cmd) then
			local dist = tonumber(args[2])
			if (dist ~= nil) and (0 < dist) and (dist < 45) then
				settings.follow.distance = dist
				atc('Follow distance set to '..settings.follow.distance)
			else
				atc('Error: Invalid argument specified for follow distance')
			end
		elseif S{'resume'}:contains(cmd) then
			if (settings.follow.target ~= nil) then
				settings.follow.active = true
				atc('Now following '..settings.follow.target..'.')
			else
				atc(123,'Error: Unable to resume follow - no target set')
			end
		else	--args[1] is guaranteed to have a value if this is reached
			local pname = getPlayerName(args[1])
			if (pname ~= nil) then
				settings.follow.target = pname
				settings.follow.active = true
				atc('Now following '..settings.follow.target..'.')
			else
				atc(123,'Error: Invalid name provided as a follow target: '..tostring(args[1]))
			end
		end
	elseif S{'ignore', 'unignore', 'watch', 'unwatch'}:contains(command) then
		monitorCommand(command, args[1])
	elseif command == 'ignoretrusts' then
		toggleMode('ignoreTrusts', args[1], 'Ignoring of Trust NPCs', 'IgnoreTrusts')
	elseif command == 'packetinfo' then
		toggleMode('showPacketInfo', args[1], 'Packet info display', 'PacketInfo')
	elseif command == 'moveinfo' then
		if posCommand('moveInfo', args) then
			refresh_textBoxes()
		else
			toggleVisible('moveInfo', args[1])
		end
	elseif command == 'actioninfo' then
		if posCommand('actionInfo', args) then
			refresh_textBoxes()
		else
			toggleVisible('actionInfo', args[1])
		end
	elseif S{'showq','showqueue','queue'}:contains(command) then
		if posCommand('actionQueue', args) then
			refresh_textBoxes()
		else
			toggleVisible('actionQueue', args[1])
		end
	elseif S{'monitored','showmonitored'}:contains(command) then
		if posCommand('montoredBox', args) then
			refresh_textBoxes()
		else
			toggleVisible('montoredBox', args[1])
		end
	elseif S{'help','--help'}:contains(command) then
		help_text()
	elseif command == 'settings' then
		for k,v in pairs(settings) do
			local kstr = tostring(k)
			local vstr = (type(v) == 'table') and tostring(T(v)) or tostring(v)
			atc(kstr:rpad(' ',15)..': '..vstr)
		end
	elseif command == 'status' then
		printStatus()
	elseif command == 'info' then
		if info == nil then
			atc(3,'Unable to parse info.  Windower/addons/info/info_shared.lua was unable to be loaded.')
			atc(3,'If you would like to use this function, please visit https://github.com/lorand-ffxi/addons to download it.')
			return
		end
		local cmd = args[1]	--Take the first element as the command
		table.remove(args, 1)	--Remove the first from the list of args
		info.process_input(cmd, args)
	else
		atc('Error: Unknown command')
	end
end

function posCommand(boxName, args)
	if (args[1] == nil) or (args[2] == nil) then return false end
	local cmd = args[1]:lower()
	if not S{'pos','posx','posy'}:contains(cmd) then
		return false
	end
	local x,y = tonumber(args[2]),tonumber(args[3])
	if (cmd == 'pos') then
		if (x == nil) or (y == nil) then return false end
		settings.textBoxes[boxName].x = x
		settings.textBoxes[boxName].y = y
	elseif (cmd == 'posx') then
		if (x == nil) then return false end
		settings.textBoxes[boxName].x = x
	elseif (cmd == 'posy') then
		if (y == nil) then return false end
		settings.textBoxes[boxName].y = y
	end
	return true
end

function toggleVisible(boxName, cmd)
	cmd = cmd and cmd:lower() or (settings.textBoxes[boxName].visible and 'off' or 'on')
	if (cmd == 'on') then
		settings.textBoxes[boxName].visible = true
	elseif (cmd == 'off') then
		settings.textBoxes[boxName].visible = false
	else
		atc(123,'Invalid argument for changing text box settings: '..cmd)
	end
end

function toggleMode(mode, cmd, msg, msgErr)
	if (modes[mode] == nil) then
		atc(123,'Error: Invalid mode to toggle: '..tostring(mode))
		return
	end
	cmd = cmd and cmd:lower() or (modes[mode] and 'off' or 'on')
	if (cmd == 'on') then
		modes[mode] = true
		atc(msg..' is now on.')
	elseif (cmd == 'off') then
		modes[mode] = false
		atc(msg..' is now off.')
	else
		atc(123,'Invalid argument for '..msgErr..': '..cmd)
	end
end

function disableCommand(cmd, disable)
	local msg = ' is now '..(disable and 'disabled.' or 're-enabled.')
	if S{'cure','cures','curing'}:contains(cmd) then
		if (not disable) then
			if (settings.maxCureTier == 0) then
				settings.disable.cure = true
				atc(123,'Error: Unable to enable curing because you have no Cure spells available.')
				return
			end
		end
		settings.disable.cure = disable
		atc('Curing'..msg)
	elseif S{'curaga'}:contains(cmd) then
		settings.disable.curaga = disable
		atc('Curaga use'..msg)
	elseif S{'na','heal_debuff','cure_debuff'}:contains(cmd) then
		settings.disable.na = disable
		atc('Removal of status effects'..msg)
	elseif S{'buff','buffs','buffing'}:contains(cmd) then
		settings.disable.buff = disable
		atc('Buffing'..msg)
	elseif S{'debuff','debuffs','debuffing'}:contains(cmd) then
		settings.disable.debuff = disable
		atc('Debuffing'..msg)
	elseif S{'nuke','nukes','nuking'}:contains(cmd) then
		settings.disable.nuke = disable
		atc('Nuking'..msg)
	elseif S{'ws','weaponskill','weaponskills','weaponskilling'}:contains(cmd) then
		settings.disable.ws = disable
		atc('Weaponskilling'..msg)
	else
		atc(123,'Error: Invalid argument for disable/enable: '..cmd)
	end
end

function monitorCommand(cmd, pname)
	if (pname == nil) then
		atc('Error: No argument specified for '..cmd)
		return
	end
	local name = getPlayerName(pname)
	if cmd == 'ignore' then
		if (not ignoreList:contains(name)) then
			ignoreList:add(name)
			atc('Will now ignore '..name)
			if extraWatchList:contains(name) then
				extraWatchList:remove(name)
			end
		else
			atc('Error: Already ignoring '..name)
		end
	elseif cmd == 'unignore' then
		if (ignoreList:contains(name)) then
			ignoreList:remove(name)
			atc('Will no longer ignore '..name)
		else
			atc('Error: Was not ignoring '..name)
		end
	elseif cmd == 'watch' then
		if (not extraWatchList:contains(name)) then
			extraWatchList:add(name)
			atc('Will now watch '..name)
			if ignoreList:contains(name) then
				ignoreList:remove(name)
			end
		else
			atc('Error: Already watching '..name)
		end
	elseif cmd == 'unwatch' then
		if (extraWatchList:contains(name)) then
			extraWatchList:remove(name)
			atc('Will no longer watch '..name)
		else
			atc('Error: Was not watching '..name)
		end
	end
end

function validate(args, numArgs, message)
	for i = 1, numArgs do
		if (args[i] == nil) then
			atc(message..' ('..i..')')
			return false
		end
	end
	return true
end

function getPlayerName(name)
	local trg = getTarget(name)
	if (trg ~= nil) then
		return trg.name
	end
	return nil
end

function getTarget(targ)
	local target = nil
	if targ and tonumber(targ) and (tonumber(targ) > 255) then
		target = windower.ffxi.get_mob_by_id(tonumber(targ))
	elseif targ and S{'<me>','me'}:contains(targ) then
		target = windower.ffxi.get_mob_by_target('me')
	elseif targ and (targ == '<t>') then
		target = windower.ffxi.get_mob_by_target()
	elseif targ and (type(targ) == 'string') then
		target = windower.ffxi.get_mob_by_name(targ)
	elseif targ and (type(targ) == 'table') then
		target = targ
	end
	return target
end

function getPartyMember(name)
	local party = windower.ffxi.get_party()
	for _,pmember in pairs(party) do
		if (type(pmember) == 'table') and (pmember.name == name) then
			return pmember
		end
	end
	return nil
end

function getMainPartyList()
	local pt = windower.ffxi.get_party()
	local pty = {pt.p0,pt.p1,pt.p2,pt.p3,pt.p4,pt.p5}
	local party = S{}
	for _,pm in pairs(pty) do
		if (pm ~= nil) then
			party:add(pm.name)
		end
	end
	return party
end

--[[
	Returns the resource information for the given spell or ability name
--]]
function getActionFor(actionName)
	local spell = res.spells:with('en', actionName)
	local abil = res.job_abilities:with('en', actionName)
	local ws = res.weapon_skills:with('en', actionName)
	
	return spell or abil or ws or nil
end

--==============================================================================
--			String Formatting Functions
--==============================================================================

function formatSpellName(text)
	if (type(text) ~= 'string') or (#text < 1) then return nil end
	
	local fromAlias = aliases[text]
	if (fromAlias ~= nil) then
		return fromAlias
	end
	
	local parts = text:split(' ')
	if #parts >= 2 then
		local name = formatName(parts[1])
		for p = 2, #parts do
			local part = parts[p]
			local tier = toRomanNumeral(part) or part:upper()
			if (roman2dec[tier] == nil) then
				name = name..' '..formatName(part)
			else
				name = name..' '..tier
			end
		end
		return name
	else
		local name = formatName(text)
		local tier = text:sub(-1)
		local rnTier = toRomanNumeral(tier)
		if (rnTier ~= nil) then
			return name:sub(1, #name-1)..' '..rnTier
		else
			return name
		end
	end
end

function formatName(text)
	if (text ~= nil) and (type(text) == 'string') then
		return text:lower():ucfirst()
	end
	return text
end

function toRomanNumeral(val)
	if type(val) ~= 'number' then
		if type(val) == 'string' then
			val = tonumber(val)
		else
			return nil
		end
	end
	return dec2roman[val]
end

--==============================================================================
--			Output Handling Functions
--==============================================================================

function atc(c, msg)
	if (type(c) == 'string') and (msg == nil) then
		msg = c
		c = 0
	end
	windower.add_to_chat(c, '[HealBot]'..msg)
end

function atcc(c,msg)
	if (type(c) == 'string') and (msg == nil) then
		msg = c
		c = 0
	end
	local hbmsg = '[HealBot]'..msg
	windower.add_to_chat(0, hbmsg:colorize(c))
end

function atcd(c, msg)
	if modes.debug then atc(c, msg) end
end

--[[
	Convenience wrapper for echoing a message in the Windower console.
--]]
function echo(msg)
	if (msg ~= nil) then
		windower.send_command('echo [HealBot]'..msg)
	end
end

function print_table_keys(t, prefix)
	prefix = prefix or ''
	local msg = ''
	for k,v in pairs(t) do
		if #msg > 0 then msg = msg..', ' end
		msg = msg..k
	end
	if #msg == 0 then msg = '(none)' end
	atc(prefix..msg)
end

function printPairs(tbl, prefix)
	if prefix == nil then prefix = '' end
	for k,v in pairs(tbl) do
		atc(prefix..tostring(k)..' : '..tostring(v))
		if type(v) == 'table' then
			printPairs(v, prefix..'    ')
		end
	end
end

function printStatus()
	windower.add_to_chat(1, 'HealBot is now '..(active and 'active' or 'off')..'.')
end

function colorFor(col)
	local cstr = ''
	if not ((S{256,257}:contains(col)) or (col<1) or (col>511)) then
		if (col <= 255) then
			cstr = string.char(0x1F)..string.char(col)
		else
			cstr = string.char(0x1E)..string.char(col - 256)
		end
	end
	return cstr
end

function string.colorize(str, new_col, reset_col)
	new_col = new_col or 1
	reset_col = reset_col or 1
	return colorFor(new_col)..str..colorFor(reset_col)
end

--==============================================================================
--			Initialization Functions
--==============================================================================

function import(path)
	local fcontents = files.read(path)
	if (fcontents ~= nil) then
		return loadstring(fcontents)()
	end
	return nil
end

function load_configs()
	local defaults = {
		textBoxes = {
			actionQueue={x=-125,y=300,font='Arial',size=10,visible=true},
			moveInfo={x=0,y=18,visible=false},
			actionInfo={x=0,y=0,visible=true},
			montoredBox={x=-150,y=600,font='Arial',size=10,visible=true}
		},
		nuke = {name='Stone'}
	}
	local loaded = config.load('data/settings.xml', defaults)
	update_settings(loaded)
	refresh_textBoxes()
	
	aliases = config.load('../shortcuts/data/aliases.xml')
	mabil_debuffs = config.load('data/mabil_debuffs.xml')
	defaultBuffs = config.load('data/buffLists.xml')
	
	priorities = config.load('data/priorities.xml')
	priorities.players = priorities.players or {}
	priorities.jobs = priorities.jobs or {}
	priorities.status_removal = priorities.status_removal or {}
	priorities.buffs = priorities.buffs or {}
	priorities.default = priorities.default or 5
	
	mobAbils = process_mabil_debuffs()
	local msg = configs_loaded and 'Rel' or 'L'
	configs_loaded = true
	atcc(262, msg..'oaded config files.')
end

function update_settings(loaded)
	settings = settings or {}
	for key,vals in pairs(loaded) do
		settings[key] = settings[key] or {}
		for vkey,val in pairs(vals) do
			settings[key][vkey] = val
		end
	end
	settings.actionDelay = settings.actionDelay or 0.08
	settings.assist = settings.assist or {}
	settings.assist.active = settings.assist.active or false
	settings.assist.engage = settings.assist.engage or false
	settings.disable = settings.disable or {}
	settings.follow = settings.follow or {}
	settings.follow.delay = settings.follow.delay or 0.08
	settings.follow.distance = settings.follow.distance or 3
	settings.healing = settings.healing or {}
	settings.healing.minCure = settings.healing.minCure or 3
	settings.healing.minCuraga = settings.healing.minCuraga or 1
	settings.healing.minWaltz = settings.healing.minWaltz or 2
	settings.healing.minWaltzga = settings.healing.minWaltzga or 1
	settings.nuke = settings.nuke or {}
end

function refresh_textBoxes()
	local boxes = {'actionQueue','moveInfo','actionInfo','montoredBox'}
	txts = txts or {}
	for _,box in pairs(boxes) do
		local bs = settings.textBoxes[box]
		local bst = {pos={x=bs.x, y=bs.y}}
		bst.flags = {right=(bs.x < 0), bottom=(bs.y < 0)}
		if (bs.font ~= nil) then
			bst.text = {font=bs.font}
		end
		if (bs.size ~= nil) then
			bst.text = bst.text or {}
			bst.text.size = bs.size
		end
		
		if (txts[box] ~= nil) then
			txts[box]:destroy()
		end
		txts[box] = texts.new(bst)
	end
end

function populateTrustList()
	local trusts = S{}
	for _,spell in pairs(res.spells) do
		if (spell.type == 'Trust') then
			trusts:add(spell.en)
		end
	end
	return trusts
end

function process_mabil_debuffs()
	local mabils = S{}
	for abil_raw,debuffs in pairs(mabil_debuffs) do
		local aname = abil_raw:gsub('_',' '):capitalize()
		mabils[aname] = S{}
		for _,debuff in pairs(debuffs) do
			mabils[aname]:add(debuff)
		end
	end
	return mabils
end

--==============================================================================
--			Table Functions
--==============================================================================

function sizeof(tbl)
	local c = 0
	for _,_ in pairs(tbl) do c = c + 1 end
	return c
end

function getPrintable(list, inverse)
	local qstring = ''
	for index,line in pairs(list) do
		local check = index
		local add = line
		if (inverse) then
			check = line
			add = index
		end
		if (tostring(check) ~= 'n') then
			if (#qstring > 1) then
				qstring = qstring..'\n'
			end
			qstring = qstring..add
		end
	end
	return qstring
end

--======================================================================================================================
--						Misc.
--======================================================================================================================

--[[
	Rounds a float to the given number of decimal places.
	Note: math.round is only for rounding to the nearest integer
--]]
function round(num, dec_places)
	local mult = 10^(dec_places or 0)
	return math.floor(num * mult + 0.5) / mult
end

function help_text()
	local t = '    '
	local ac,cc,dc = 262,263,1
	atcc(262,'HealBot Commands:')
	local cmds = {
		{'on | off','Activate / deactivate HealBot (does not affect follow)'},
		{'reload','Reload HealBot, resetting everything'},
		{'refresh','Reloads settings XMLs in addons/HealBot/data/'},
		{'fcmd','Sets a player to follow, the distance to maintain, or toggles being active with no argument'},
		{'buff <player> <spell>[, <spell>[, ...]]','Sets spell(s) to be maintained on the given player'},
		{'cancelbuff <player> <spell>[, <spell>[, ...]]','Un-sets spell(s) to be maintained on the given player'},
		{'bufflist <list name> <player>','Sets the given list of spells to be maintained on the given player'},
		{'spam [use <spell> | <bool>]','Sets the spell to be spammed, or toggles being active (default: Stone, off) [Requires an assist target to activate]'},
		{'mincure <number>','Sets the minimum cure spell tier to cast (default: 3)'},
		{'disable <action type>','Disables actions of a given type (cure, buff, na)'},
		{'enable <action type>','Re-enables actions of a given type (cure, buff, na) if they were disabled'},
		{'reset [buffs | debuffs | both [on <player>]]','Resets the list of buffs/debuffs that have been detected, optionally for a single player'},
		{'ignore_debuff <player/always> <debuff>','Ignores when the given debuff is cast on the given player or everyone'},
		{'unignore_debuff <player/always> <debuff>','Stops ignoring the given debuff for the given player or everyone'},
		{'ignore <player>','Ignores the given player/npc so they will not be healed'},
		{'unignore <player>','Stops ignoring the given player/npc (=/= watch)'},
		{'watch <player>','Monitors the given player/npc so they will be healed'},
		{'unwatch <player>','Stops monitoring the given player/npc (=/= ignore)'},
		{'ignoretrusts <on/off>','Toggles whether or not Trust NPCs should be ignored (default: on)'},
		{'ascmd','Sets a player to assist, toggles whether or not to engage, or toggles being active with no argument'},
		{'wscmd1','Sets the weaponskill to use'},
		{'wscmd2','Sets when weaponskills should be used according to whether the mob HP is < or > the given amount'},
		{'wscmd3','Sets a weaponskill partner to open skillchains for, and the TP that they should have'},
		{'wscmd4','Removes a weaponskill partner so weaponskills will be performed independently'},
		{'queue [pos <x> <y> | on | off]','Moves action queue, or toggles display with no argument (default: on)'},
		{'actioninfo [pos <x> <y> | on | off]','Moves character status info, or toggles display with no argument (default: on)'},
		{'moveinfo [pos <x> <y> | on | off]','Moves movement status info, or toggles display with no argument (default: off)'},
		{'monitored [pos <x> <y> | on | off]','Moves monitored player list, or toggles display with no argument (default: on)'},
		{'disable curaga','In addons/HealBot/data/settings.xml:\n<settings>\n  <global>\n    ...\n    <disable>\n      <curaga>true</curaga>\n    </disable>\n    ...\n  </global>\n</settings>'},
		{'help','Displays this help text'}
	}
	local acmds = {
		['fcmd']='f':colorize(ac,cc)..'ollow [<player> | dist <distance> | off | resume]',
		['ascmd']='as':colorize(ac,cc)..'sist [<player> | attack | off | resume]',
		['wscmd1']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill use <ws name>',
		['wscmd2']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill hp <sign> <mob hp%>',
		['wscmd3']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill waitfor <player> <tp>',
		['wscmd4']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill nopartner',
	}
	
	for _,tbl in pairs(cmds) do
		local cmd,desc = tbl[1],tbl[2]
		local txta = cmd
		if (acmds[cmd] ~= nil) then
			txta = acmds[cmd]
		else
			txta = txta:colorize(cc)
		end
		local txtb = desc:colorize(dc)
		atc(txta)
		atc(t..txtb)
	end
end

--======================================================================================================================
--[[
Copyright © 2015, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
following conditions are met:
	* Redistributions of source code must retain the above copyright notice, this list of conditions and the
	  following disclaimer.
	* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
	  following disclaimer in the documentation and/or other materials provided with the distribution.
	* Neither the name of ffxiHealer nor the names of its contributors may be used to endorse or promote products
	  derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
--]]
--======================================================================================================================