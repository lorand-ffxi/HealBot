--======================================================================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot follow handling functions
--]]
--======================================================================================================================

local Pos = require('position')
local quadrants = {NW={-1,1},SW={1,-1},NE={0,-1},SE={0,1}}
local compass = {N=-math.pi/2,S=math.pi/2,E=0,W=math.pi,NW=-math.pi*3/4,NE=-math.pi*1/4,SW=math.pi*3/4,SE=math.pi*1/4}

function needToMove(targ, dist)
	local shouldMove = false
	local target = getTarget(targ)
	if (target ~= nil) then
		shouldMove = math.sqrt(target.distance) > dist
	end
	return shouldMove
end

function moveTowards(targ)
	local target = getTarget(targ)
	if (target ~= nil) then
		windower.ffxi.run(getDirRadian(getPosition(), getPosition(target)))
	end
end

--[[
	Get the position of the entity with the given name, or own
	position if no name is given.
--]]
function getPosition(targ)
	local mob = getTarget(targ and targ or 'me')
	if (mob ~= nil) then
		return Pos.new(mob.x, mob.y, mob.z)
	end
	return nil
end

--[[
	Returns the direction in radians to face pos2 given pos1
--]]
function getDirRadian(pos1, pos2)
	if (not pos1) or (not pos2) then return nil end
	local dx = pos1:x() - pos2:x()
	local dy = pos1:y() - pos2:y()
	local quad = getQuadrant(dx, dy)
	local theta = math.atan(math.abs(dy)/math.abs(dx))
	local phi = (math.pi * quadrants[quad][1]) + (theta * quadrants[quad][2])
	return phi
end

--[[
	Returns the quandrant in which the given point lies
--]]
function getQuadrant(x, y)
	if (not x) or (not y) then return nil end
	local quad = (y > 0 and 'S' or 'N')
	quad = quad .. (x > 0 and 'W' or 'E')
	return quad
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