--======================================================================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot follow handling functions
--]]
--======================================================================================================================

local Pos = _libs.lor.position

function needToMove(targ, dist)
	local shouldMove = false
	local target = utils.getTarget(targ)
	if (target ~= nil) then
		shouldMove = math.sqrt(target.distance) > dist
	end
	return shouldMove
end

function moveTowards(targ)
	local target = utils.getTarget(targ)
	if (target ~= nil) then
        local my_pos = getPosition()
        if my_pos ~= nil then
            windower.ffxi.run(my_pos:getDirRadian(getPosition(target)))
        end
	end
end

--[[
	Get the position of the entity with the given name, or own
	position if no name is given.
--]]
function getPosition(targ)
	local mob = utils.getTarget(targ and targ or 'me')
	if (mob ~= nil) then
		return Pos.new(mob.x, mob.y, mob.z)
	end
	return nil
end


--======================================================================================================================
--[[
Copyright © 2016, Lorand
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