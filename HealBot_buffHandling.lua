--==============================================================================
--[[
    Author: Ragnarok.Lorand
    HealBot buff handling functions
--]]
--==============================================================================

local buffs = {
    debuffList = {},
    buffList = {},
    ignored_debuffs = {}
}

--==============================================================================
--          Local Player Buff Checking
--==============================================================================

function buffs.checkOwnBuffs()
	local player = windower.ffxi.get_player()
	if (player ~= nil) and (player.buffs ~= nil) then
		--Register everything that's actually active
		for _,bid in pairs(player.buffs) do
			local buff = res.buffs[bid]
			if (enfeebling:contains(bid)) then
				buffs.registerDebuff(player.name, buff.en, true)
			else
				buffs.registerBuff(player.name, buff.en, true)
			end
		end
		--Double check the list of what should be active
		local checklist = buffs.buffList[player.name] or {}
		local active = S(player.buffs)
		for bname,binfo in pairs(checklist) do
			if not (active:contains(binfo.buff.id)) then
				buffs.registerBuff(player.name, bname, false)
			end
		end
	end
end

function buffs.checkOwnBuff(buffName)
    local player = windower.ffxi.get_player()
    local activeBuffIds = S(player.buffs)
    local buff = res.buffs:with('en', buffName) or {}
    if (activeBuffIds:contains(buff.id)) then
        buffs.registerBuff(player.name, buffName, true)
    end
end

--==============================================================================
--          Monitored Player Buff Checking
--==============================================================================

function buffs.getBuffQueue()
    local bq = ActionQueue.new()
    local now = os.clock()
    for targ, buffset in pairs(buffs.buffList) do
        for buff, info in pairs(buffset) do
            if (targ == myName) then
                buffs.checkOwnBuff(buffs.getBuffNameForAction(info.action.en))
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

function buffs.getDebuffQueue()
    local dbq = ActionQueue.new()
    local now = os.clock()
    for targ, debuffs in pairs(buffs.debuffList) do
        for debuff, info in pairs(debuffs) do
            local removalSpellName = debuff_map[debuff]
            if (removalSpellName ~= nil) then
                if (info.attempted == nil) or ((now - info.attempted) >= 3) then
                    local spell = res.spells:with('en', removalSpellName)
                    if Assert.can_use(spell) and Assert.target_is_valid(spell, targ) then
                        local ign = buffs.ignored_debuffs[debuff]
                        if not ((ign ~= nil) and ((ign.all == true) or ((ign[targ] ~= nil) and (ign[targ] == true)))) then
                            dbq:enqueue('buff', spell, targ, debuff, ' ('..debuff..')')
                        end
                    end
                end
            else
                buffs.debuffList[targ][debuff] = nil
            end
        end
    end
    return dbq:getQueue()
end

--==============================================================================
--          Input Handling Functions
--==============================================================================

function buffs.registerNewBuff(args, use)
    local targetName = args[1] and args[1] or ''
    table.remove(args, 1)
    local arg_string = table.concat(args,' ')
    local snames = arg_string:split(',')
    for index,sname in pairs(snames) do
        if (tostring(index) ~= 'n') then
            buffs.registerNewBuffName(targetName, sname:trim(), use)
        end
    end
end

function buffs.registerNewBuffName(targetName, bname, use)
    local spellName = formatSpellName(bname)
    if (spellName == nil) then
        atc('Error: Unable to parse spell name')
        return
    end
    
    local me = windower.ffxi.get_player()
    local target = getTarget(targetName)
    if (target == nil) then
        atc('Unable to find buff target: '..targetName)
        return
    end
    local action = buffs.getAction(spellName, target)
    if (action == nil) then
        atc('Unable to cast or invalid: '..spellName)
        return
    end
    if not Assert.target_is_valid(action, target) then
        atc(target.name..' is an invalid target for '..action.en)
        return
    end
    
    local monitoring = hb.getMonitoredPlayers()
    if (not (monitoring[target.name])) then
        monitorCommand('watch', target.name)
    end
    
    buffs.buffList[target.name] = buffs.buffList[target.name] or {}
    local bname = buffs.getBuffNameForAction(action)
    local buff = res.buffs:with('en',bname)
    if (buff == nil) then
        atc('Unable to match the buff name to an actual buff: '..bname)
        return
    end
    
    if (use) then
        buffs.buffList[target.name][bname] = {['action']=action, ['maintain']=true, ['buff']=buff}
        atc('Will maintain buff: '..action.en..' '..rarr..' '..target.name)
    else
        buffs.buffList[target.name][bname] = nil
        atc('Will no longer maintain buff: '..action.en..' '..rarr..' '..target.name)
    end
end

function buffs.registerIgnoreDebuff(args, ignore)
    local targetName = args[1] and args[1] or ''
    table.remove(args, 1)
    local arg_string = table.concat(args,' ')
    
    local msg = ignore and 'ignore' or 'stop ignoring'
    
    local dbname = debuff_casemap[arg_string:lower()]
    if (dbname ~= nil) then
        if S{'always','everyone','all'}:contains(targetName) then
            buffs.ignored_debuffs[dbname] = {['all']=ignore}
            atc('Will now '..msg..' '..dbname..' on everyone.')
        else
            local trgname = getPlayerName(targetName)
            if (trgname ~= nil) then
                buffs.ignored_debuffs[dbname] = buffs.ignored_debuffs[dbname] or {['all']=false}
                if (buffs.ignored_debuffs[dbname].all == ignore) then
                    local msg2 = ignore and 'ignoring' or 'stopped ignoring'
                    atc('Ignore debuff settings unchanged. Already '..msg2..' '..dbname..' on everyone.')
                else
                    buffs.ignored_debuffs[dbname][trgname] = ignore
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

function buffs.getAction(actionName, target)
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

function buffs.getBuffNameForAction(action)
    local spellName = action
    if type(action) == 'table' then
        if (action.type == 'JobAbility') then
            return action.en
        end
        spellName = action.en
    end
    
    if (buff_map[spellName] ~= nil) then
        return buff_map[spellName]
    elseif spellName:match('^Protectr?a?%s?I*V?$') then
        return 'Protect'
    elseif spellName:match('^Shellr?a?%s?I*V?$') then
        return 'Shell'
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
--          Buff Tracking Functions
--==============================================================================

function buffs.registerDebuff(targetName, debuffName, gain)
    buffs.debuffList[targetName] = buffs.debuffList[targetName] or {}
    if (debuffName == 'slow') then
        buffs.registerBuff(targetName, 'Haste', false)
        buffs.registerBuff(targetName, 'Flurry', false)
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
        
        buffs.debuffList[targetName][debuffName] = {['landed']=os.clock()}
        atcd('Detected debuff: '..debuffName..' '..rarr..' '..targetName)   
    else
        buffs.debuffList[targetName][debuffName] = nil
        atcd('Detected debuff: '..debuffName..' wore off '..targetName)
    end
end

function buffs.registerBuff(targetName, buffName, gain)
    buffs.buffList[targetName] = buffs.buffList[targetName] or {}
    if buffs.buffList[targetName][buffName] ~= nil then
        if gain then
            buffs.buffList[targetName][buffName]['landed'] = os.clock()
            atcd("Detected buff: "..buffName.." "..rarr.." "..targetName)
        else
            buffs.buffList[targetName][buffName]['landed'] = nil
            atcd("Detected buff: "..buffName.." wore off "..targetName)
        end
    end
end

function buffs.resetDebuffTimers(player)
    if (player == nil) then
        atc(123,'Error: Invalid player name passed to buffs.resetDebuffTimers.')
    elseif (player == 'ALL') then
        buffs.debuffList = {}
    else
        buffs.debuffList[player] = {}
    end
end

function buffs.resetBuffTimers(player, exclude)
    if (player == nil) then
        atc(123,'Error: Invalid player name passed to buffs.resetBuffTimers.')
        return
    elseif (player == 'ALL') then
        for p,l in pairs(buffs.buffList) do
            buffs.resetBuffTimers(p)
        end
        return
    end
    buffs.buffList[player] = buffs.buffList[player] or {}
    for buffName,_ in pairs(buffs.buffList[player]) do
        if exclude ~= nil then
            if not (exclude:contains(buffName)) then
                buffs.buffList[player][buffName]['landed'] = nil
            end
        else
            buffs.buffList[player][buffName]['landed'] = nil
        end
    end
end

return buffs

--======================================================================================================================
--[[
Copyright © 2015-2016, Lorand
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