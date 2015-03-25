--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot action queue building & handling functions
--]]
--==============================================================================

ActionQueue = {}

function ActionQueue.new()
	local self = {queue=Q({})}
	return setmetatable(self, {__index = ActionQueue})
end

function ActionQueue:getQueue()
	return self.queue
end

local compFunc = {}

function ActionQueue:enqueue(actionType, action, name, secondary, msg)
	local secLabel = (actionType == 'cure') and 'hpp' or actionType
	local pprio = getPlayerPriority(name)
	local qable = {['type']=actionType,['action']=action,['name']=name,[secLabel]=secondary,['msg']=msg,['prio']=pprio}
	if self.queue:empty() then
		self.queue:insert(1,qable)
	else
		local highestAbove = 999
		for index = 1, self.queue:length() do
			local qi = self.queue[index]
			local qprio = getPlayerPriority(qi.name)
			local higher = compFunc[actionType](-1, pprio, secondary, index, qprio, qi[secLabel])
			if (higher == -1) and (index < highestAbove) then
				highestAbove = index
			end
		end
		if (highestAbove ~= 999) then
			self.queue:insert(highestAbove,qable)
		else
			local last = self.queue:length()+1
			self.queue:insert(last,qable)
		end
	end
end

local getDangerLevel
function getDangerLevel(hpp)
	if (hpp <= 20) then
		return 3
	elseif (hpp <= 40) then
		return 2
	elseif (hpp <= 60) then
		return 1
	end
	return 0
end

function compFunc.default(index1, pa1, pb1, index2, pa2, pb2)
	if (pa1 < pa2) then		--p1 is higher priority
		if (pb2 < pb1) then	--action 2 is higher priority
			return index2
		else			--action 2 is same or lower priority
			return index1
		end
	elseif (pa1 > pa2) then		--p2 is higher priority
		if (pb1 < pb2) then	--action 1 is higher priority
			return index1
		else			--action 1 is same or lower priority
			return index2
		end
	else				--same priority
		if (pb2 < pb1) then	--action 2 is higher priority
			return index2
		else			--action 2 is same or lower priority
			return index1
		end
	end
end

function compFunc.buff(index1, prio1, buff1, index2, prio2, buff2)
	local bp1 = getBuffPriority(buff1)
	local bp2 = getBuffPriority(buff2)
	return compFunc.default(index1, prio1, bp1, index2, prio2, bp2)
end

function compFunc.debuff(index1, prio1, debuff1, index2, prio2, debuff2)
	local rp1 = getRemovalPriority(debuff1)
	local rp2 = getRemovalPriority(debuff2)
	return compFunc.default(index1, prio1, rp1, index2, prio2, rp2)
end

function compFunc.cure(index1, prio1, hpp1, index2, prio2, hpp2)
	local d1 = getDangerLevel(hpp1)
	local d2 = getDangerLevel(hpp2)
	if (prio1 < prio2) then		--p1 is higher priority
		if (d2 > d1) then	--p2 is in more danger
			return index2
		else			--p2 is in same or less danger
			return index1
		end
	elseif (prio1 > prio2) then	--p2 is higher priority
		if (d1 > d2) then	--p1 is in more danger
			return index1
		else			--p1 is in same or less danger
			return index2
		end
	else				--same priority
		if (d2 > d1) then	--p2 is in more danger
			return index2
		elseif (d1 > d2) then	--p1 is in more danger
			return index1
		else			--same danger
			if (hpp1 < hpp2) then
				return index1
			else
				return index2
			end
		end
	end
end

function getPlayerPriority(tname)
	if (tname == myName) then
		return 1
	elseif trusts:contains(tname) then
		return priorities.default + 2
	end
	local pmInfo = partyMemberInfo[tname]
	local jobprio = (pmInfo ~= nil) and priorities.jobs[pmInfo.job:lower()] or priorities.default
	local playerprio = priorities.players[tname:lower()] or priorities.default
	return math.min(jobprio, playerprio)
end

function getBuffPriority(buff_name)
	local bnamef = buff_name:gsub(' ','_'):lower()
	return priorities.buffs[bnamef] or priorities.default
end

function getRemovalPriority(ailment)
	local ailmentf = ailment:gsub(' ','_'):lower()
	return priorities.status_removal[ailmentf] or priorities.default
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