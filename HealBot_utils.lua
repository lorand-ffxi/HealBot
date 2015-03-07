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
		local b = false
		local d = false
		if (args[1] == nil) then
			b = true
			d = true
		elseif (args[1]:lower() == 'buffs') then
			b = true
		elseif (args[1]:lower() == 'debuffs') then
			d = true
		else
			atc('Error: Invalid argument specified for reset: '..arg[1])
		end
		if (b) then
			for player,_ in pairs(buffList) do
				resetBuffTimers(player)
			end
		end
		if (d) then
			debuffList = {}
		end
		checkOwnBuffs()
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
	elseif S{'follow','f'}:contains(command) then
		local cmd = args[1] and args[1]:lower() or (follow and 'off' or 'resume')
		if S{'off','end','false','pause'}:contains(cmd) then
			follow = false
		elseif S{'distance', 'dist', 'd'}:contains(cmd) then
			local dist = tonumber(args[2])
			if (dist ~= nil) and (0 < dist) and (dist < 45) then
				followDist = dist
				atc('Follow distance set to '..followDist)
			else
				atc('Error: Invalid argument specified for follow distance')
			end
		elseif S{'resume'}:contains(cmd) then
			if (followTarget ~= nil) then
				follow = true
				atc('Now following '..followTarget..'.')
			else
				atc(123,'Error: Unable to resume follow - no target set')
			end
		else
			local name = args[1]
			if name == '<t>' then
				name = windower.ffxi.get_mob_by_target().name
			end
			followTarget = formatName(name)
			follow = true
			atc('Now following '..followTarget..'.')
		end
	elseif S{'ignore', 'unignore', 'watch', 'unwatch'}:contains(command) then
		monitorCommand(command, args[1])
	elseif command == 'moveinfo' then
		toggleMode('showMoveInfo', args[1], 'Movement info', 'MoveInfo')
	elseif command == 'packetinfo' then
		toggleMode('showPacketInfo', args[1], 'Packet info display', 'PacketInfo')
	elseif command == 'actioninfo' then
		toggleMode('showActionInfo', args[1], 'Action info display', 'ActionInfo')
	elseif command == 'ignoretrusts' then
		toggleMode('ignoreTrusts', args[1], 'Ignoring of Trust NPCs', 'IgnoreTrusts')
	elseif S{'showq','showqueue','queue'}:contains(command) then
		toggleMode('showActionQueue', args[1], 'Action queue', 'ShowQueue')
	elseif S{'monitored','showmonitored'}:contains(command) then
		toggleMode('showMonitored', args[1], 'Monitored players list', 'ShowMonitored')
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

function monitorCommand(cmd, pname)
	if (pname == nil) then
		atc('Error: No argument specified for '..cmd)
		return
	end
	local name = formatName(pname)
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
	windower.add_to_chat(c, '[healBot]'..msg)
end

function atcd(c, msg)
	if debugMode then atc(c, msg) end
end

--[[
	Convenience wrapper for echoing a message in the Windower console.
--]]
function echo(msg)
	if (msg ~= nil) then
		windower.send_command('echo [healBot]'..msg)
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

--==============================================================================
--			Initialization Functions
--==============================================================================

function load_configs()
	aliases = config.load('..\\shortcuts\\data\\aliases.xml')
	mabil_debuffs = config.load('data/mabil_debuffs.xml')
	defaultBuffs = config.load('data/buffLists.xml')
	priorities = config.load('data/priorities.xml')
	mobAbils = process_mabil_debuffs()
	local msg = configs_loaded and 'Rel' or 'L'
	configs_loaded = true
	atc(15, msg..'oaded config files.')
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
		local aname = mabilName(abil_raw)
		mabils[aname] = S{}
		for _,debuff in pairs(debuffs) do
			mabils[aname]:add(debuff)
		end
	end
	return mabils
end

function mabilName(rawName)
	local parts = rawName:split('_')
	local rebuilt = ''
	for _,part in pairs(parts) do
		if rawName:contains(part) then
			if rebuilt:length() > 1 then
				rebuilt = rebuilt..' '
			end
			rebuilt = rebuilt..formatName(part)
		end
	end
	return rebuilt
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

-----------------------------------------------------------------------------------------------------------
--[[
Copyright © 2015, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of ffxiHealer nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]
-----------------------------------------------------------------------------------------------------------