--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot action handling functions
--]]
--==============================================================================

function getActionToPerform()
	local actions = {}
	actions.cure = getPotentialCures()
	actions.debuffs = checkDebuffs()
	actions.buffs = checkBuffs()
	
	local queue = L({})
	
	local danger = {60,40,20}
	local cact = {id=-1,pp=9,hpp=100}
	if (actions.cure ~= nil) then
		for ci,cure_act in pairs(actions.cure) do
			queue:append(tostring(cure_act.action.en)..' → '..tostring(cure_act.targetName))
			if (cure_act.targetName == nil) then
				--{action=spell,targ_hpp=p.hpp,targetName=p.name,msg=' ('..p.missing..')'}
				atc(123, '['..ci..']'..tostring(cure_act.action.en)..sparr..tostring(cure_act.targetName)..tostring(cure_act.msg))
			end
			
			local ca = {}
			ca.pp = getPlayerPriority(cure_act.targetName)
			ca.hpp = cure_act.targ_hpp
			if (ca.pp > cact.pp) then						--current is a lower priority
				if (cact.hpp < danger[1]) and (ca.hpp < danger[1]) then			--both members are in danger
					if (ca.hpp < danger[2]) then					--current is in critical danger
						if (cact.hpp > danger[2]) then				--stored isn't in critical danger
							cact.id = ci
							cact.pp = ca.pp
							cact.hpp = ca.hpp
						else							--stored is in critical danger
							if (ca.hpp < danger[3]) then			--current is in extreme danger
								if (cact.hpp > danger[3]) then		--stored isn't in extreme danger
									cact.id = ci
									cact.pp = ca.pp
									cact.hpp = ca.hpp
								end
							end
						end
					end
				end
			elseif (ca.pp < cact.pp) then						--current is a higher priority
				if (cact.hpp < danger[1]) and (ca.hpp < danger[1]) then			--both are in danger
					if (cact.hpp > danger[2]) then					--stored is not in critical danger
						cact.id = ci
						cact.pp = ca.pp
						cact.hpp = ca.hpp
					else								--stored is in critical danger
						if (ca.hpp < danger[2]) then				--current is in critical danger
							if (cact.hpp > danger[3]) then			--stored is not in extreme danger
								cact.id = ci
								cact.pp = ca.pp
								cact.hpp = ca.hpp
							else						--stored is in extreme danger
								if (ca.hpp < danger[3]) then		--current is in extreme danger
									cact.id = ci
									cact.pp = ca.pp
									cact.hpp = ca.hpp
								end
							end
						end
					end
				else									--current or neither is in danger
					cact.id = ci
					cact.pp = ca.pp
					cact.hpp = ca.hpp
				end
			else									--both have same priority
				if (ca.hpp < cact.hpp) then						--current has less hp than stored
					cact.id = ci
					cact.pp = ca.pp
					cact.hpp = ca.hpp
				end
			end
		end
	end
	
	local nact = {id=-1,ap=9,pp=9}
	if (actions.debuffs ~= nil) then
		for ni,na_act in pairs(actions.debuffs) do
			if (na_act.targetName == nil) then
				--{action=spell,targ_hpp=p.hpp,targetName=p.name,msg=' ('..p.missing..')'}
				atc(123, '['..ni..']'..tostring(na_act.action.en)..sparr..tostring(na_act.targetName)..tostring(na_act.msg))
			end
			
			local target = getTarget(na_act.targetName)
			local action = getAction(na_act.action.en)
			if (target ~= nil) and (action ~= nil) and validTarget(action, target) then
				queue:append(tostring(na_act.action.en)..' → '..tostring(na_act.targetName))
				local na = {}
				na.pp = getPlayerPriority(na_act.targetName)
				na.ap = getRemovalPriority(na_act.debuffName)
				if (na.pp > nact.pp) then	--current player is lower priority
					if (na.ap > nact.ap) then	--current debuff has lower priority
					elseif (na.ap < nact.ap) then	--current debuff has higher priority
						if ((nact.ap - na.ap) > 1) then
							nact.id = ni
							nact.ap = na.ap
							nact.pp = na.pp
						end
					else				--current debuff has same priority
					end
				elseif (na.pp < nact.pp) then	--current player is higher priority
					if (na.ap > nact.ap) then	--current debuff has lower priority
						if ((nact.ap - na.ap) == 1) then
							nact.id = ni
							nact.ap = na.ap
							nact.pp = na.pp
						end
					elseif (na.ap < nact.ap) then	--current debuff has higher priority
						nact.id = ni
						nact.ap = na.ap
						nact.pp = na.pp
					else				--current debuff has same priority
						nact.id = ni
						nact.ap = na.ap
						nact.pp = na.pp
					end
				else				--both players have same priority
					if (na.ap > nact.ap) then	--current debuff has lower priority
					elseif (na.ap < nact.ap) then	--current debuff has higher priority
						nact.id = ni
						nact.ap = na.ap
						nact.pp = na.pp
					else				--current debuff has same priority
					end
				end
			end
		end
	end
	
	local bact = {id=-1,ap=9,pp=9}
	if (actions.buffs ~= nil) then
		for bi,buff_act in pairs(actions.buffs) do
			queue:append(tostring(buff_act.action.en)..' → '..tostring(buff_act.targetName))
			if (buff_act.targetName == nil) then
				--{action=spell,targ_hpp=p.hpp,targetName=p.name,msg=' ('..p.missing..')'}
				atc(123, '['..bi..']'..tostring(buff_act.action.en)..sparr..tostring(buff_act.targetName)..tostring(buff_act.msg))
			end
			
			local ba = {}
			ba.pp = getPlayerPriority(buff_act.targetName)
			ba.ap = getBuffPriority(buff_act.buffName)
			if (ba.pp > bact.pp) then	--current player is lower priority
				if (ba.ap > bact.ap) then	--current buff has lower priority
				elseif (ba.ap < bact.ap) then	--current buff has higher priority
					if ((bact.ap - ba.ap) > 1) then
						bact.id = bi
						bact.ap = ba.ap
						bact.pp = ba.pp
					end
				else				--current buff has same priority
				end
			elseif (ba.pp < bact.pp) then	--current player is higher priority
				if (ba.ap > bact.ap) then	--current buff has lower priority
					if ((bact.ap - ba.ap) == 1) then
						bact.id = bi
						bact.ap = ba.ap
						bact.pp = ba.pp
					end
				elseif (ba.ap < bact.ap) then	--current buff has higher priority
					bact.id = bi
					bact.ap = ba.ap
					bact.pp = ba.pp
				else				--current buff has same priority
					bact.id = bi
					bact.ap = ba.ap
					bact.pp = ba.pp
				end
			else				--both players have same priority
				if (ba.ap > bact.ap) then	--current buff has lower priority
				elseif (ba.ap < bact.ap) then	--current buff has higher priority
					bact.id = bi
					bact.ap = ba.ap
					bact.pp = ba.pp
				else				--current buff has same priority
				end
			end
		end
	end
	
	actionQueue:text(getPrintable(queue))
	actionQueue:visible(modes.showActionQueue)
	
	if (cact.id ~= -1) then							--There's an available cure action
		if (cact.hpp > 80) then						--The target's hp > 80%
			if (nact.id ~= -1) and (nact.pp < cact.pp) then		--There's an available debuff removal action with higher priority
				debuffList[actions.debuffs[nact.id].targetName][actions.debuffs[nact.id].debuffName].attempted = os.clock()
				return actions.debuffs[nact.id]
			elseif (bact.id ~= -1) and (bact.pp < cact.pp) then		--There's an available buff action with higher priority
				buffList[actions.buffs[bact.id].targetName][actions.buffs[bact.id].buffName].attempted = os.clock()
				return actions.buffs[bact.id]
			end
		end
		return actions.cure[cact.id]
	elseif (nact.id ~= -1) then						--There's an available debuff removal action
		if (bact.id ~= -1) and (bact.pp < bact.pp)then			--There's an available buff action with higher priority
			buffList[actions.buffs[bact.id].targetName][actions.buffs[bact.id].buffName].attempted = os.clock()
			return actions.buffs[bact.id]
		end
		debuffList[actions.debuffs[nact.id].targetName][actions.debuffs[nact.id].debuffName].attempted = os.clock()
		return actions.debuffs[nact.id]
	elseif (bact.id ~= -1) then						--There's an available buff action
		buffList[actions.buffs[bact.id].targetName][actions.buffs[bact.id].buffName].attempted = os.clock()
		return actions.buffs[bact.id]
	end
	return nil
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