--======================================================================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot action handling functions
--]]
--======================================================================================================================

--[[
	Builds an action queue for defensive actions.  Returns the action deemed most important at the time.
--]]
function getActionToPerform()
	local queue = L({})
	local action = {}
	
	if (not settings.disable.cure) then
		local cureq = getCureQueue()
		while (not cureq:empty()) do
			local cact = cureq:pop()
			queue:append(tostring(cact.action.en)..' → '..tostring(cact.name))
			if (action.cure == nil) and Assert.in_casting_range(cact.name) then
				action.cure = cact
			end
		end
	end
	if (not settings.disable.na) then
		local dbuffq = getDebuffQueue()
		while (not dbuffq:empty()) do
			local dbact = dbuffq:pop()
			queue:append(tostring(dbact.action.en)..' → '..tostring(dbact.name))
			if (action.debuff == nil) and Assert.in_casting_range(dbact.name) and Assert.ready_to_use(dbact.action) then
				action.debuff = dbact
			end
		end
	end
	if (not settings.disable.buff) then
		local buffq = getBuffQueue()
		while (not buffq:empty()) do
			local bact = buffq:pop()
			queue:append(tostring(bact.action.en)..' → '..tostring(bact.name))
			if (action.buff == nil) and Assert.in_casting_range(bact.name) and Assert.ready_to_use(bact.action) then
				action.buff = bact
			end
		end
	end
	
	txts.actionQueue:text(getPrintable(queue))
	txts.actionQueue:visible(settings.textBoxes.actionQueue.visible)
	
	if (action.cure ~= nil) then
		if (action.debuff ~= nil) and (action.debuff.action.en == 'Paralyna') and (action.debuff.name == myName) then
			return action.debuff
		elseif (action.debuff ~= nil) and (action.debuff.prio < action.cure.prio) then
			return action.debuff
		elseif (action.buff ~= nil) and (action.buff.prio < action.cure.prio) then
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

--[[
	Builds an action queue for offensive actions.  Returns the action deemed most important at the time.
	
	TODO: Expand
	
	
	settings.nuke.active
	settings.nuke.name
	
--]]
function getOffensiveAction()
	local me = windower.ffxi.get_player()
	local target = windower.ffxi.get_mob_by_target()
	if (target ~= nil) then
		-- enemyInfo = enemyInfo or {}
		-- if (target.id ~= enemyInfo.id) then
			-- enemyInfo = {lastCast={}}
			-- enemyInfo.id = target.id
			-- enemyInfo.lastCast['Dia III'] = os.clock()
			-- return {action=getActionFor('Dia III'),name='<t>'}
		-- end
		
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
			if (me.vitals.mp >= spell.mp_cost) and (target.hpp > 0) and Assert.ready_to_use(spell) and Assert.in_casting_range('<t>') then
				return {action=spell,name='<t>'}
			end
		end
	end
	return nil
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