--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot action handling functions
--]]
--==============================================================================

local actions = {queue=L()}


local function local_queue_reset()
    actions.queue = L()
end

local function local_queue_insert(action, target)
    actions.queue:append(tostring(action)..' → '..tostring(target))
end

local function local_queue_disp()
    txts.actionQueue:text(getPrintable(actions.queue))
	txts.actionQueue:visible(settings.textBoxes.actionQueue.visible)
end


--[[
	Builds an action queue for defensive actions.  Returns the action deemed most important at the time.
--]]
function actions.get_defensive_action()
	local action = {}
	
	if (not settings.disable.cure) then
		local cureq = CureUtils.get_cure_queue()
		while (not cureq:empty()) do
			local cact = cureq:pop()
            local_queue_insert(cact.action.en, cact.name)
			if (action.cure == nil) and Assert.in_casting_range(cact.name) then
				action.cure = cact
			end
		end
	end
	if (not settings.disable.na) then
		local dbuffq = buffs.getDebuffQueue()
		while (not dbuffq:empty()) do
			local dbact = dbuffq:pop()
            local_queue_insert(dbact.action.en, dbact.name)
			if (action.debuff == nil) and Assert.in_casting_range(dbact.name) and Assert.ready_to_use(dbact.action) then
				action.debuff = dbact
			end
		end
	end
	if (not settings.disable.buff) then
		local buffq = buffs.getBuffQueue()
		while (not buffq:empty()) do
			local bact = buffq:pop()
            local_queue_insert(bact.action.en, bact.name)
			if (action.buff == nil) and Assert.in_casting_range(bact.name) and Assert.ready_to_use(bact.action) then
				action.buff = bact
			end
		end
	end
	
	local_queue_disp()
	
	if (action.cure ~= nil) then
		if (action.debuff ~= nil) and (action.debuff.action.en == 'Paralyna') and (action.debuff.name == healer.name) then
			return action.debuff
		elseif (action.debuff ~= nil) and ((action.debuff.prio + 2) < action.cure.prio) then
			return action.debuff
		elseif (action.buff ~= nil) and ((action.buff.prio + 2) < action.cure.prio) then
			return action.buff
		end
		return action.cure
	elseif (action.debuff ~= nil) then
		if (action.buff ~= nil) and (action.buff.prio < action.debuff.prio) then
			return action.buff
		end
		return action.debuff
	elseif (action.buff ~= nil) then
		return action.buff
	end
	return nil
end


function actions.take_action(player, partner, targ)
    buffs.checkOwnBuffs()
    local_queue_reset()
    local action = actions.get_defensive_action()
    if (action ~= nil) then         --If there's a defensive action to perform
        local act = action.action
        local target_name = action.name
        local msg = action.msg or ''
        
        --Record attempt time for buffs/debuffs
        buffs.buffList[target_name] = buffs.buffList[target_name] or {}
        if (action.type == 'buff') and (buffs.buffList[target_name][action.buff]) then
            buffs.buffList[target_name][action.buff].attempted = os.clock()
        elseif (action.type == 'debuff') then
            buffs.debuffList[target_name][action.debuff.id].attempted = os.clock()
        end
        
        atcd(act.en..sparr..target_name..msg)         --Debug message
        wcmd(act.prefix, act.en, target_name)         --Send command to windower
    else                        --Otherwise, there may be an offensive action
        if (targ ~= nil) then
            local partner_engaged = (partner.status == 1)
            local self_engaged = (player.status == 1)
            if (player.target_index == partner.target_index) then
                if offense.assist.engage and partner_engaged and (not self_engaged) then
                    healer.actor:send_cmd('input /attack on')
                else
                    local action = actions.get_offensive_action()
                    if (action ~= nil) then
                        local act = action.action
                        local target_name = action.name
                        local msg = action.msg or ''
                        
                        atcd(act.en..sparr..target_name..msg) --Debug message
                        wcmd(act.prefix, act.en, '<t>') --Send cmd to windower
                    end
                end
            else                            --Different targets
                if partner_engaged and (not self_engaged) then
                    healer.actor:send_cmd('input /as '..offense.assist.name)
                end
            end
            offense.cleanup()
        end
    end
end


--[[
	Builds an action queue for offensive actions.
    Returns the action deemed most important at the time.
--]]
function actions.get_offensive_action()
	local player = windower.ffxi.get_player()
	local target = windower.ffxi.get_mob_by_target()
    if target == nil then return nil end
    local action = {}
    
    --Prioritize debuffs over nukes/ws for now
    local dbuffq = offense.getDebuffQueue(player, target)
    while not dbuffq:empty() do
        local dbact = dbuffq:pop()
        local_queue_insert(dbact.action.en, target.name)
        if (action.db == nil) and Assert.in_casting_range(target) and Assert.ready_to_use(dbact.action) then
            action.db = dbact
        end
    end
    
    local_queue_disp()
    if action.db ~= nil then
        return action.db
    end
    
    if (not settings.disable.ws) and (settings.ws ~= nil) and Assert.ready_to_use(getActionFor(settings.ws.name)) then
        local sign = settings.ws.sign or '>'
        local hp = settings.ws.hp or 0
        local hp_ok = ((sign == '<') and (target.hpp <= hp)) or ((sign == '>') and (target.hpp >= hp))
        
        local partner_ok = true
        if (settings.ws.partner ~= nil) then
            local pname = settings.ws.partner.name
            local partner = getPartyMember(pname)
            if (partner ~= nil) then
                partner_ok = partner.tp >= settings.ws.partner.tp
            else
                partner_ok = false
                atc(123,'Unable to locate weaponskill partner '..pname)
            end
        end
        
        if (hp_ok and partner_ok) then
            return {action=getActionFor(settings.ws.name),name='<t>'}
        end
    elseif (not settings.disable.nuke) and settings.nuke.active and (settings.nuke.name ~= nil) then
        local spell = getActionFor(settings.nuke.name)
        if (player.vitals.mp >= spell.mp_cost) and (target.hpp > 0) and Assert.ready_to_use(spell) and Assert.in_casting_range('<t>') then
            return {action=spell,name='<t>'}
        end
    end
	return nil
end

return actions

--==============================================================================
--[[
Copyright © 2016, Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of ffxiHealer nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]
--==============================================================================
