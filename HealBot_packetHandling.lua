--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot packet handling functions
--]]
--==============================================================================

--[[
	Analyze the data contained in incoming packets for useful info.
	@param id packet ID
	@param data raw packet contents
--]]
function handle_incoming_chunk(id, data)
	if S{0x28,0x29}:contains(id) then	--Action / Action Message
		local monitoring = getMonitoredPlayers()
		local ai = get_action_info(id, data)
		local actor = windower.ffxi.get_mob_by_id(ai.actor_id)
		
		if id == 0x28 then
			processAction(ai, actor, monitoring)
		elseif id == 0x29 then
			processMessage(ai, actor, monitoring)
		end
	elseif (id == 0x0DD) then			--Party member update
		local parsed = packets.parse('incoming', data)
		local pmName = parsed.Name
		local pmJobId = parsed['Main job']
		local pmSubJobId = parsed['Sub job']
		partyMemberInfo[pmName] = partyMemberInfo[pmName] or {}
		partyMemberInfo[pmName].job = res.jobs[pmJobId].ens
		partyMemberInfo[pmName].subjob = res.jobs[pmSubJobId].ens
		--atc('Caught party member update packet for '..parsed.Name..' | '..parsed.ID)
	elseif (id == 0x0DF) then
		local player = windower.ffxi.get_player()
		local parsed = packets.parse('incoming', data)
		if (player ~= nil) and (player.id ~= parsed.ID) then
			local person = windower.ffxi.get_mob_by_id(parsed.ID)
			--atc('Caught char update packet for '..person.name)
		end
	end
end

--[[
	Process the information that was parsed from an action packet
	@param ai action info
	@param actor the PC/NPC initiating the action
	@param monitoring the list of PCs that are being monitored
--]]
function processAction(ai, actor, monitoring)
	if (actor == nil) then return end
	local aname = actor.name
	for _,targ in pairs(ai.targets) do
		local target = windower.ffxi.get_mob_by_id(targ.id)
		if (target == nil) then return end
		local tname = target.name
		
		if (monitoring[aname] or monitoring[tname]) then
			for _,tact in pairs(targ.actions) do
				if not (messages_blacklist:contains(tact.message_id)) then
					if modes.showPacketInfo then
						local msg = res.action_messages[tact.message_id] or {en='???'}
						atc('[0x28]Action('..tact.message_id..'): '..aname..' { '..ai.param..' } '..rarr..' '..tname..' { '..tact.param..' } | '..msg.en)
					end
					
					if windower.ffxi.get_player().name == aname then
						if messages_initiating:contains(tact.message_id) then
							actionStart = os.clock()
						elseif messages_completing:contains(tact.message_id) then
							actionEnd = os.clock()
						end
					end
					
					registerEffect(ai, tact, aname, tname, monitoring)
				end--/message ID not on blacklist
			end--/loop through targ's actions
		end--/monitoring actor or target
	end--/loop through action's targets
end

--[[
	Process the information that was parsed from an action message packet
	@param ai action info
	@param actor the PC/NPC initiating the action
	@param monitoring the list of PCs that are being monitored
--]]
function processMessage(ai, actor, monitoring)
	local aname = actor.name
	local target = windower.ffxi.get_mob_by_id(ai.target_id)
	local tname = target.name
	if (monitoring[aname] or monitoring[tname]) then
		if not (messages_blacklist:contains(ai.message_id)) then
			if modes.showPacketInfo then
				local msg = res.action_messages[ai.message_id] or {en='???'}
				local params = tostring(ai.param_1)..', '..tostring(ai.param_2)..', '..tostring(ai.param_3)
				atc('[0x29]Message('..ai.message_id..'): '..aname..' { '..params..' } '..rarr..' '..tname..' | '..msg.en)
			end
			
			--Track whether or not the local player is performing an action
			if windower.ffxi.get_player().name == aname then
				if messages_initiating:contains(ai.message_id) then
					actionStart = os.clock()
				elseif messages_completing:contains(ai.message_id) then
					actionEnd = os.clock()
				end
			end
			
			if messages_wearOff:contains(ai.message_id) then
				local buff = res.buffs[ai.param_1]
				if enfeebling:contains(ai.param_1) then
					registerDebuff(tname, buff.en, false)
				else
					registerBuff(tname, buff.en, false)
				end
			end--/message ID checks
		end--/message ID not on blacklist
	end--/monitoring actor or target
end

--[[
	Register the effects that were discovered in an action packet
	@param tact the subaction on a target
	@param aname the name of the PC/NPC initiating the action
	@param tname the name of the PC that is the target of the action
	@param monitoring the list of PCs that are being monitored
--]]
function registerEffect(ai, tact, aname, tname, monitoring)
	if monitoring[tname] then
		if messages_magicDamage:contains(tact.message_id) then		--ai.param: spell; tact.param: damage
			local spell = res.spells[ai.param]
			if S{230,231,232,233,234}:contains(ai.param) then
				registerDebuff(tname, 'Bio', true)
			elseif S{23,24,25,26,27,33,34,35,36,37}:contains(ai.param) then
				registerDebuff(tname, 'Dia', true)
			end
		elseif messages_gainEffect:contains(tact.message_id) then	--ai.param: spell; tact.param: buff/debuff
			--{tname} gains the effect of {buff} / {tname} is {debuff}ed
			local buff = res.buffs[tact.param]
			if enfeebling:contains(tact.param) then
				registerDebuff(tname, buff.en, true)
			else
				registerBuff(tname, buff.en, true)
			end
		elseif messages_loseEffect:contains(tact.message_id) then	--ai.param: spell; tact.param: buff/debuff
			--{tname}'s {buff} wore off
			local buff = res.buffs[tact.param]
			if enfeebling:contains(tact.param) then
				registerDebuff(tname, buff.en, false)
			else
				registerBuff(tname, buff.en, false)
			end
		elseif messages_noEffect:contains(tact.message_id) then		--ai.param: spell; tact.param: buff/debuff
			--Spell had no effect on {tname}
			local spell = res.spells[ai.param]
			if (spell ~= nil) then
				if spells_statusRemoval:contains(spell.id) then
					--The debuff must have worn off or have been removed already
					local debuffs = removal_map[spell.en]
					if (debuffs ~= nil) then
						for _,debuff in pairs(debuffs) do
							registerDebuff(tname, debuff, false)
						end
					end
				elseif spells_buffs:contains(spell.id) then
					--The buff must already be active, or there must be some debuff preventing the buff from landing
					local bname = getBuffNameForAction(spell.en)
					if (bname == nil) then
						atc(123, 'ERROR: No buff found for spell: '..spell.en)
					else
						registerBuff(tname, bname, false)
						if S{'Haste','Flurry'}:contains(bname) then
							registerDebuff(tname, 'slow', true)
						end
					end
				end
			end
		elseif messages_nonGeneric:contains(tact.message_id) then
			if S{142,144,145}:contains(tact.message_id) then--${target} receives the effect of Accuracy Down and Evasion Down.
				registerDebuff(tname, 'Accuracy Down', true)
				registerDebuff(tname, 'Evasion Down', true)
			elseif S{329}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s STR is drained
				registerDebuff(tname, 'STR Down', true)
			elseif S{330}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s DEX is drained
				registerDebuff(tname, 'DEX Down', true)
			elseif S{331}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s VIT is drained
				registerDebuff(tname, 'VIT Down', true)
			elseif S{332}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s AGI is drained
				registerDebuff(tname, 'AGI Down', true)
			elseif S{333}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s INT is drained
				registerDebuff(tname, 'INT Down', true)
			elseif S{334}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s MND is drained
				registerDebuff(tname, 'MND Down', true)
			elseif S{335}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s CHR is drained
				registerDebuff(tname, 'CHR Down', true)
			elseif S{351}:contains(tact.message_id) then	--The remedy removes ${target}'s status ailments.
				registerDebuff(tname, 'blindness', false)
				registerDebuff(tname, 'paralysis', false)
				registerDebuff(tname, 'poison', false)
				registerDebuff(tname, 'silence', false)
			elseif S{359}:contains(tact.message_id) then	--${target} narrowly escapes impending doom.
				registerDebuff(tname, 'doom', false)
			elseif S{519}:contains(tact.message_id) then	--${actor} uses ${ability}.${lb}${target} is afflicted with Lethargic Daze (lv.${number}).
				--registerDebuff(tname, 'Lethargic Daze', true)
			elseif S{520}:contains(tact.message_id) then	--${actor} uses ${ability}.${lb}${target} is afflicted with Sluggish Daze (lv.${number}).
				--registerDebuff(tname, 'Sluggish Daze', true)
			elseif S{521}:contains(tact.message_id) then	--${actor} uses ${ability}.${lb}${target} is afflicted with Weakened Daze (lv.${number}).
				--registerDebuff(tname, 'Weakened Daze', true)
			elseif S{533}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s Accuracy is drained.
				registerDebuff(tname, 'Accuracy Down', true)
			elseif S{534}:contains(tact.message_id) then	--${actor} casts ${spell}.${lb}${target}'s Attack is drained.
				registerDebuff(tname, 'Attack Down', true)
			elseif S{591}:contains(tact.message_id) then	--${actor} uses ${ability}.${lb}${target} is afflicted with Bewildered Daze (lv.${number}).
				--registerDebuff(tname, 'Bewildered Daze', true)
			end
		elseif S{185}:contains(tact.message_id) then	--${actor} uses ${weapon_skill}.${lb}${target} takes ${number} points of damage.
			local mabil = res.monster_abilities[ai.param]
			if (mabil ~= nil) then
				if (mobAbils[mabil.en] ~= nil) then
					for dbf,_ in pairs(mobAbils[mabil.en]) do
						registerDebuff(tname, dbf, true)
					end
				end
			end
		end--/message ID checks
	end--/monitoring target of action
	
	if monitoring[aname] then
		if messages_paralyzed:contains(tact.message_id) then
			registerDebuff(aname, 'paralysis', true)
		end
	end--/monitoring actor
end

--[[
	Parse the given packet and construct a table to make its contents useful.
	Based on the 'incoming chunk' function in the Battlemod addon (thanks to Byrth / SnickySnacks)
	@param id packet ID
	@param data raw packet contents
	@return a table representing the given packet's data
--]]
function get_action_info(id, data)
    local pref = data:sub(1,4)
    local data = data:sub(5)
    if id == 0x28 then			-------------- ACTION PACKET ---------------
        local act = {}
        act.do_not_need	= get_bit_packed(data,0,8)
        act.actor_id	= get_bit_packed(data,8,40)
        act.target_count= get_bit_packed(data,40,50)
        act.category	= get_bit_packed(data,50,54)
        act.param	= get_bit_packed(data,54,70)
        act.unknown	= get_bit_packed(data,70,86)
        act.recast	= get_bit_packed(data,86,118)
        act.targets = {}
        local offset = 118
        for i = 1, act.target_count do
            act.targets[i] = {}
            act.targets[i].id = get_bit_packed(data,offset,offset+32)
            act.targets[i].action_count = get_bit_packed(data,offset+32,offset+36)
            offset = offset + 36
            act.targets[i].actions = {}
            for n = 1,act.targets[i].action_count do
                act.targets[i].actions[n] = {}
                act.targets[i].actions[n].reaction	= get_bit_packed(data,offset,offset+5)
                act.targets[i].actions[n].animation	= get_bit_packed(data,offset+5,offset+16)
                act.targets[i].actions[n].effect	= get_bit_packed(data,offset+16,offset+21)
                act.targets[i].actions[n].stagger	= get_bit_packed(data,offset+21,offset+27)
                act.targets[i].actions[n].param		= get_bit_packed(data,offset+27,offset+44)
                act.targets[i].actions[n].message_id	= get_bit_packed(data,offset+44,offset+54)
                act.targets[i].actions[n].unknown	= get_bit_packed(data,offset+54,offset+85)
                act.targets[i].actions[n].has_add_efct	= get_bit_packed(data,offset+85,offset+86)
                offset = offset + 86
                if act.targets[i].actions[n].has_add_efct == 1 then
                    act.targets[i].actions[n].has_add_efct		= true
                    act.targets[i].actions[n].add_efct_animation	= get_bit_packed(data,offset,offset+6)
                    act.targets[i].actions[n].add_efct_effect		= get_bit_packed(data,offset+6,offset+10)
                    act.targets[i].actions[n].add_efct_param		= get_bit_packed(data,offset+10,offset+27)
                    act.targets[i].actions[n].add_efct_message_id	= get_bit_packed(data,offset+27,offset+37)
                    offset = offset + 37
                else
                    act.targets[i].actions[n].has_add_efct		= false
                    act.targets[i].actions[n].add_efct_animation	= 0
                    act.targets[i].actions[n].add_efct_effect		= 0
                    act.targets[i].actions[n].add_efct_param		= 0
                    act.targets[i].actions[n].add_efct_message_id	= 0
                end
                act.targets[i].actions[n].has_spike_efct = get_bit_packed(data,offset,offset+1)
                offset = offset + 1
                if act.targets[i].actions[n].has_spike_efct == 1 then
                    act.targets[i].actions[n].has_spike_efct		= true
                    act.targets[i].actions[n].spike_efct_animation	= get_bit_packed(data,offset,offset+6)
                    act.targets[i].actions[n].spike_efct_effect		= get_bit_packed(data,offset+6,offset+10)
                    act.targets[i].actions[n].spike_efct_param		= get_bit_packed(data,offset+10,offset+24)
                    act.targets[i].actions[n].spike_efct_message_id	= get_bit_packed(data,offset+24,offset+34)
                    offset = offset + 34
                else
                    act.targets[i].actions[n].has_spike_efct		= false
                    act.targets[i].actions[n].spike_efct_animation	= 0
                    act.targets[i].actions[n].spike_efct_effect		= 0
                    act.targets[i].actions[n].spike_efct_param		= 0
                    act.targets[i].actions[n].spike_efct_message_id	= 0
                end
            end
        end
        return act
    elseif id == 0x29 then		----------- ACTION MESSAGE ------------
		local am = {}
		am.actor_id	= get_bit_packed(data,0,32)
		am.target_id	= get_bit_packed(data,32,64)
		am.param_1	= get_bit_packed(data,64,96)
		am.param_2	= get_bit_packed(data,96,106)	-- First 6 bits
		am.param_3	= get_bit_packed(data,106,128)	-- Rest
		am.actor_index	= get_bit_packed(data,128,144)
		am.target_index	= get_bit_packed(data,144,160)
		am.message_id	= get_bit_packed(data,160,175)	-- Cut off the most significant bit, hopefully
		return am
	end
end

function get_bit_packed(dat_string,start,stop)
	--Copied from Battlemod; thanks to Byrth / SnickySnacks
	local newval = 0   
	local c_count = math.ceil(stop/8)
	while c_count >= math.ceil((start+1)/8) do
		local cur_val = dat_string:byte(c_count)
		local scal = 256
		if c_count == math.ceil(stop/8) then
			cur_val = cur_val%(2^((stop-1)%8+1))
		end
		if c_count == math.ceil((start+1)/8) then
			cur_val = math.floor(cur_val/(2^(start%8)))
			scal = 2^(8-start%8)
		end
		newval = newval*scal + cur_val
		c_count = c_count - 1
	end
	return newval
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