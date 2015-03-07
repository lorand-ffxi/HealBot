--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot buff handling functions
--]]
--==============================================================================

debuffList = debuffList or {}
buffList = buffList or {}

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

function buffActive(...)
	local args = S{...}:map(string.lower)
	local player = windower.ffxi.get_player()
	if (player ~= nil) and (player.buffs ~= nil) then
		for _,bid in pairs(player.buffs) do
			local buff = res.buffs[bid]
			if args:contains(buff.en:lower()) then
				return buff
			end
		end
	end
	return nil
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
		local checklist = buffList[player.name]
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
	local buff = res.buffs:with('en', buffName)
	if (activeBuffIds:contains(buff.id)) then
		registerBuff(player.name, buffName, true)
	end
end

--==============================================================================
--			Monitored Player Buff Checking
--==============================================================================

function checkBuffs()
	local potentialActions = {}
	local c = 1
	local now = os.clock()
	for targ, buffs in pairs(buffList) do
		if not isTooFar(targ) then
			for buff, info in pairs(buffs) do
				if (targ == myName) then checkOwnBuff(buff) end
				local action = info.action
				if (info.landed == nil) then
					if (info.attempted == nil) or ((now - info.attempted) >= 3) then
						if (getRecast(action) == 0) then
							potentialActions[c] = {['action']=action, ['targetName']=targ, ['buffName']=buff}
							c = c + 1
						end
					end
				end
			end
		end
	end
	return (sizeof(potentialActions) > 0) and potentialActions or nil
end

function getRecast(action)
	if (action.type == 'JobAbility') then
		return windower.ffxi.get_ability_recasts()[action.recast_id]
	else
		return windower.ffxi.get_spell_recasts()[action.recast_id]
	end
end

function checkDebuffs()
	local potentialActions = {}
	local c = 1
	local now = os.clock()
	for targ, debuffs in pairs(debuffList) do
		if not isTooFar(targ) then
			for debuff, info in pairs(debuffs) do
				local removalSpellName = debuff_map[debuff]
				if removalSpellName ~= nil then
					if (info.attempted == nil) or ((now - info.attempted) >= 3) then
						local spell = res.spells:with('en', removalSpellName)
						if (getRecast(spell) == 0) then
							potentialActions[c] = {['action']=spell, ['targetName']=targ, ['msg']=' ('..debuff..')', ['debuffName']=debuff}
							c = c + 1
						end
					end
				else
					debuffList[targ][debuff] = nil
				end
			end
		end
	end
	return (sizeof(potentialActions) > 0) and potentialActions or nil
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
	if not validTarget(action, target) then
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
		if (targetType == 'Self') then
			checkOwnBuff(bname)
		end
	else
		buffList[target.name][bname] = nil
		atc('Will no longer maintain buff: '..action.en..' '..rarr..' '..target.name)
	end
end

function getTarget(targetName)
	local me = windower.ffxi.get_player()
	local target = windower.ffxi.get_mob_by_name(targetName)
	if (target == nil) then
		if (targetName == '<t>') then
			target = windower.ffxi.get_mob_by_target()
		elseif S{'<me>','me'}:contains(targetName) then
			target = windower.ffxi.get_mob_by_id(me.id)
		end
	end
	return target
end

function getAction(actionName, target)
	local me = windower.ffxi.get_player()
	local action = nil
	local spell = res.spells:with('en', actionName)
	if (spell ~= nil) and canCast(spell) then
		action = spell
	elseif (target ~= nil) and (target.id == me.id) then
		local abil = res.job_abilities:with('en', actionName)
		if (abil ~= nil) then
			action = abil
		end
	end
	return action
end

function validTarget(action, target)
	local me = windower.ffxi.get_player()
	local targetType = 'None'
	if (target.in_alliance) then
		if (target.in_party) then
			if (me.name == target.name) then
				targetType = 'Self'
			else
				targetType = 'Party'
			end
		else
			targetType = 'Ally'
		end
	end
	return S(action.targets):contains(targetType)
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
	if debuffList[targetName] == nil then
		debuffList[targetName] = {}
	end
	if (debuffName == 'slow') then
		registerBuff(targetName, 'Haste', false)
		registerBuff(targetName, 'Flurry', false)
	end
	
	if gain then
		local ignoreList = ignoreDebuffs[debuffName]
		local pmInfo = partyMemberInfo[targetName]
		if (ignoreList ~= nil) and (pmInfo ~= nil) then
			if ignoreList:contains(pmInfo.job) and ignoreList:contains(pmInfo.subjob) then
				atc('Ignoring '..debuffName..' on '..targetName..' because of their job')
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
	if buffList[targetName] == nil then
		buffList[targetName] = {}
	end
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

-----------------------------------------------------------------------------------------------------------
--[[
Copyright © 2015, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of healBot nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]
-----------------------------------------------------------------------------------------------------------