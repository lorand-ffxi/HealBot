--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot buff handling functions
--]]
--==============================================================================

debuffList = {}
buffList = {}
ignored_debuffs = {}

--==============================================================================
--			Local Player Buff Checking
--==============================================================================

function get_active_buffs()
	local activeBuffs = S{}
	local player = windower.ffxi.get_player()
	if (player ~= nil) then
		for _,bid in pairs(player.buffs) do
			local bname = res.buffs[bid]
			activeBuffs[bid] = bname
			activeBuffs[bname] = bid
		end
	end
	return activeBuffs
end

function checkOwnBuffs()
	local player = windower.ffxi.get_player()
	if (player ~= nil) and (player.buffs ~= nil) then
		--Register everything that's actually active
		for _,bid in pairs(player.buffs) do
			local buff = res.buffs[bid]
			if (enfeebling:contains(bid)) then
				registerDebuff(player.name, buff.en, true)
			else
				registerBuff(player.name, buff.en, true)
			end
		end
		--Double check the list of what should be active
		local checklist = buffList[player.name] or {}
		local active = S(player.buffs)
		for bname,binfo in pairs(checklist) do
			if not (active:contains(binfo.buff.id)) then
				registerBuff(player.name, bname, false)
			end
		end
	end
end

function checkOwnBuff(buffName)
	local player = windower.ffxi.get_player()
	local activeBuffIds = S(player.buffs)
	local buff = res.buffs:with('en', buffName) or {}
	if (activeBuffIds:contains(buff.id)) then
		registerBuff(player.name, buffName, true)
	end
end

--==============================================================================
--			Monitored Player Buff Checking
--==============================================================================

function getBuffQueue()
	local bq = ActionQueue.new()
	local now = os.clock()
	for targ, buffs in pairs(buffList) do
		for buff, info in pairs(buffs) do
			if (targ == myName) then
				checkOwnBuff(getBuffNameForAction(info.action.en))
			end
			local action = info.action
			if (info.landed == nil) then
				if (info.attempted == nil) or ((now - info.attempted) >= 3) then
					bq:enqueue('buff', action, targ, buff, nil)
				end
			end
		end
	end
	return bq:getQueue()
end

function getDebuffQueue()
	local dbq = ActionQueue.new()
	local now = os.clock()
	for targ, debuffs in pairs(debuffList) do
		for debuff, info in pairs(debuffs) do
			local removalSpellName = debuff_map[debuff]
			if (removalSpellName ~= nil) then
				if (info.attempted == nil) or ((now - info.attempted) >= 3) then
					local spell = res.spells:with('en', removalSpellName)
					if Assert.can_use(spell) and Assert.target_is_valid(spell, targ) then
						local ign = ignored_debuffs[debuff]
						if not ((ign ~= nil) and ((ign.all == true) or ((ign[targ] ~= nil) and (ign[targ] == true)))) then
							dbq:enqueue('buff', spell, targ, debuff, ' ('..debuff..')')
						end
					end
				end
			else
				debuffList[targ][debuff] = nil
			end
		end
	end
	return dbq:getQueue()
end

--==============================================================================
--			Input Handling Functions
--==============================================================================

function registerNewBuff(args, use)
	local targetName = args[1] and args[1] or ''
	table.remove(args, 1)
	local arg_string = table.concat(args,' ')
	local snames = arg_string:split(',')
	for index,sname in pairs(snames) do
		if (tostring(index) ~= 'n') then
			registerNewBuffName(targetName, sname:trim(), use)
		end
	end
end

function registerNewBuffName(targetName, bname, use)
	local spellName = formatSpellName(bname)
	if (spellName == nil) then
		atc('Error: Unable to parse spell name')
		return
	end
	
	local me = windower.ffxi.get_player()
	local target = getTarget(targetName)
	if (target == nil) then
		atc('Invalid buff target: '..targetName)
		return
	end
	local action = getAction(spellName, target)
	if (action == nil) then
		atc('Unable to cast or invalid: '..spellName)
		return
	end
	if not Assert.target_is_valid(action, target) then
		atc(target.name..' is an invalid target for '..action.en)
		return
	end
	
	local monitoring = getMonitoredPlayers()
	if (not (monitoring[target.name])) then
		monitorCommand('watch', target.name)
	end
	
	buffList[target.name] = buffList[target.name] or {}
	local bname = getBuffNameForAction(action)
	local buff = res.buffs:with('en',bname)
	if (buff == nil) then
		atc('Unable to match the buff name to an actual buff: '..bname)
		return
	end
	
	if (use) then
		buffList[target.name][bname] = {['action']=action, ['maintain']=true, ['buff']=buff}
		atc('Will maintain buff: '..action.en..' '..rarr..' '..target.name)
	else
		buffList[target.name][bname] = nil
		atc('Will no longer maintain buff: '..action.en..' '..rarr..' '..target.name)
	end
end

function registerIgnoreDebuff(args, ignore)
	local targetName = args[1] and args[1] or ''
	table.remove(args, 1)
	local arg_string = table.concat(args,' ')
	
	local msg = ignore and 'ignore' or 'stop ignoring'
	
	local dbname = debuff_casemap[arg_string:lower()]
	if (dbname ~= nil) then
		if S{'always','everyone','all'}:contains(targetName) then
			ignored_debuffs[dbname] = {['all']=ignore}
			atc('Will now '..msg..' '..dbname..' on everyone.')
		else
			local trgname = getPlayerName(targetName)
			if (trgname ~= nil) then
				ignored_debuffs[dbname] = ignored_debuffs[dbname] or {['all']=false}
				if (ignored_debuffs[dbname].all == ignore) then
					local msg2 = ignore and 'ignoring' or 'stopped ignoring'
					atc('Ignore debuff settings unchanged. Already '..msg2..' '..dbname..' on everyone.')
				else
					ignored_debuffs[dbname][trgname] = ignore
					atc('Will now '..msg..' '..dbname..' on '..trgname)
				end
			else
				atc(123,'Error: Invalid target for ignore debuff: '..targetName)
			end
		end
	else
		atc(123,'Error: Invalid debuff name to '..msg..': '..arg_string)
	end
end

function getAction(actionName, target)
	local me = windower.ffxi.get_player()
	local action = nil
	local spell = res.spells:with('en', actionName)
	if (spell ~= nil) and Assert.can_use(spell) then
		action = spell
	elseif (target ~= nil) and (target.id == me.id) then
		local abil = res.job_abilities:with('en', actionName)
		if (abil ~= nil) and Assert.can_use(abil) then
			action = abil
		end
	end
	return action
end

function getBuffNameForAction(action)
	local spellName = action
	if type(action) == 'table' then
		if (action.type == 'JobAbility') then
			return action.en
		end
		spellName = action.en
	end
	if (buff_map[spellName] ~= nil) then
		return buff_map[spellName]
	else
		local buffName = spellName
		local spLoc = spellName:find(' ')
		if (spLoc ~= nil) then
			buffName = spellName:sub(1, spLoc-1)
		end
		return buffName
	end
end

--==============================================================================
--			Buff Tracking Functions
--==============================================================================

function registerDebuff(targetName, debuffName, gain)
	debuffList[targetName] = debuffList[targetName] or {}
	if (debuffName == 'slow') then
		registerBuff(targetName, 'Haste', false)
		registerBuff(targetName, 'Flurry', false)
	end
	
	if gain then
		local ignoreList = ignoreDebuffs[debuffName]
		local pmInfo = partyMemberInfo[targetName]
		if (ignoreList ~= nil) and (pmInfo ~= nil) then
			if ignoreList:contains(pmInfo.job) and ignoreList:contains(pmInfo.subjob) then
				--atc('Ignoring '..debuffName..' on '..targetName..' because of their job')
				return
			end
		end
		
		debuffList[targetName][debuffName] = {['landed']=os.clock()}
		atcd('Detected debuff: '..debuffName..' '..rarr..' '..targetName)	
	else
		debuffList[targetName][debuffName] = nil
		atcd('Detected debuff: '..debuffName..' wore off '..targetName)
	end
end

function registerBuff(targetName, buffName, gain)
	buffList[targetName] = buffList[targetName] or {}
	if buffList[targetName][buffName] ~= nil then
		if gain then
			buffList[targetName][buffName]['landed'] = os.clock()
			atcd("Detected buff: "..buffName.." "..rarr.." "..targetName)
		else
			buffList[targetName][buffName]['landed'] = nil
			atcd("Detected buff: "..buffName.." wore off "..targetName)
		end
	end
end

function resetDebuffTimers(player)
	debuffList[player] = {}
end

function resetBuffTimers(player, exclude)
	if (player == nil) then
		atc(123,'Error: Invalid player name passed to resetBuffTimers.')
		return
	elseif (player == 'ALL') then
		for p,l in pairs(buffList) do
			resetBuffTimers(p)
		end
		return
	end
	buffList[player] = buffList[player] or {}
	for buffName,_ in pairs(buffList[player]) do
		if exclude ~= nil then
			if not (exclude:contains(buffName)) then
				buffList[player][buffName]['landed'] = nil
			end
		else
			buffList[player][buffName]['landed'] = nil
		end
	end
	atcd('Notice: Buff timers for '..player..' were reset.')
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