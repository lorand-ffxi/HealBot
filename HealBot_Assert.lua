--======================================================================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot cure handling functions
--]]
--======================================================================================================================

function assertFollowTargetExistence()
	if (followTarget == nil) then return end
	local ft = windower.ffxi.get_mob_by_name(followTarget)
	if follow and (ft == nil) then
		followPause = true
		follow = false
	elseif followPause and (ft ~= nil) then
		followPause = nil
		follow = true
	end
end

function canCast(spell)
	local player = windower.ffxi.get_player()
	if (player == nil) or (spell == nil) then return false end
	if (spell.prefix == '/magic') then
		local mainCanCast = (spell.levels[player.main_job_id] ~= nil) and (spell.levels[player.main_job_id] <= player.main_job_level)
		local subCanCast = (spell.levels[player.sub_job_id] ~= nil) and (spell.levels[player.sub_job_id] <= player.sub_job_level)
		local spellAvailable = windower.ffxi.get_spells()[spell.id]
		return spellAvailable and (mainCanCast or subCanCast)
	end
	return true
end

function isTooFar(name)
	local target = windower.ffxi.get_mob_by_name(name)
	if target ~= nil then
		return math.sqrt(target.distance) > 20.8
	end
	return true
end

function isMoving()
	if (getPosition() == nil) then
		txts.moveInfo:hide()
		return true
	end
	lastPos = lastPos and lastPos or getPosition()
	posArrival = posArrival and posArrival or os.clock()
	local currentPos = getPosition()
	local now = os.clock()
	local moving = true
	local timeAtPos = math.floor((now - posArrival)*10)/10
	if (lastPos:equals(currentPos)) then
		moving = (timeAtPos < 0.5)
	else
		lastPos = currentPos
		posArrival = now
	end
	if math.floor(timeAtPos) == timeAtPos then
		timeAtPos = timeAtPos..'.0'
	end
	txts.moveInfo:text('Time @ '..currentPos:toString()..': '..timeAtPos..'s')
	txts.moveInfo:visible(modes.showMoveInfo)
	return moving
end

function isPerformingAction(moving)
	if (os.clock() - actionStart) > 8 then
		--Precaution in case an action completion isn't registered for a long time
		actionEnd = os.clock()
	end
	
	local acting = (actionEnd < actionStart)
	local status = acting and 'performing an action' or (moving and 'moving' or 'idle')
	status = ' is '..status
	
	if (lastActingState ~= acting) then	--If the current acting state is different from the last one
		if lastActingState then			--If an action was being performed
			actionDelay = 2.75			--Set a longer delay
			lastAction = os.clock()			--The delay will be from this time
		else					--If no action was being performed
			actionDelay = 0.1			--Set a short delay
		end
		lastActingState = acting		--Refresh the last acting state
	end
	
	if (os.clock() - zone_enter) < 25 then
		acting = true
		status = ' zoned recently'
		zone_wait = true
	elseif zone_wait then
		zone_wait = false
		resetBuffTimers('ALL', S{'Protect V','Shell V'})
	elseif (buffActive('Sleep', 'Petrification', 'Charm', 'Terror', 'Lullaby', 'Stun', 'Silence', 'Mute') ~= nil) then
		acting = true
		status = 'is disabled'
	end
	
	local player = windower.ffxi.get_player()
	if (player ~= nil) then
		local mpp = player.vitals.mpp
		if (mpp <= 10) then
			status = status..' | \\cs(255,0,0)LOW MP\\cr'
		end
	end
	
	txts.actionInfo:text(myName..status)
	txts.actionInfo:visible(modes.showActionInfo)
	return acting
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