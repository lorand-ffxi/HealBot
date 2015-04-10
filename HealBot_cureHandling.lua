--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot cure handling functions
--]]
--==============================================================================

function getCureQueue()
	local cq = ActionQueue.new()		--Initialize a new ActionQueue
	local hpTable = getMissingHps()		--Fetch a list of monitored players & the amounts of HP they're missing
	local tierReqs = {}			--Initialize a table to store the cure tier required for each
	
	for name,p in pairs(hpTable) do					--Iterate through the missing HP table
		if (p.hpp < 95) then					--Ignore players with HP > 95%
			local tier = CureUtils.get_cure_tier_for_hp(p.missing)
			if (tier >= settings.healing.minCure) then	--Filter out players without enough HP missing
				tierReqs[name] = tier
				local spell = CureUtils.get_usable_cure(tier)	--Edit tier for MP and recast timers
				if (spell ~= nil) then
					cq:enqueue('cure', spell, name, p.hpp, ' ('..p.missing..')')	--Enqueue it
				end
			end
		end
	end
	--If enough members need cures, determine if a Curaga spell should be used
	if (not settings.disable.curaga) and (sizeof(tierReqs) > 2) and (settings.healing.maxCuraga > 0) then
		local spell,targ = get_curaga_to_cast(tierReqs)		--Determine a target and Curaga to cast
		if (spell ~= nil) then					--If Curaga can/should be cast...
			local cgaq = ActionQueue.new()
			local p = hpTable[targ]
			cgaq:enqueue('cure', spell, targ, p.hpp, ' ('..p.missing..')')
			return cgaq:getQueue()				--Return the Curaga spell
		end
	end								--If Curaga isn't necessary / can't be cast...
	return cq:getQueue()						--Return the single target Cure queue instead
end

function get_curaga_to_cast(tierReqs)
	local party = getMainPartyList()
	local positions = {}
	
	local c,tsum = 1,0
	for name,tier in pairs(tierReqs) do
		if party:contains(name) then
			positions[c] = {['name']=name, ['pos']=getPosition(name)}
			c = c + 1
			tsum = tsum + tier
		end
	end
	if (c < 2) then return nil end
	
	local targ,fewestTooFar = 1,1
	local distances = {}
	local found = false
	while (targ < c) and (not found) do
		local tpos = positions[targ].pos
		distances[targ] = {}
		
		local maxdist,tooFar = -1,0
		for i,p in pairs(positions) do
			local dist = tpos:getDistance(p.pos)
			maxdist = (dist > maxdist) and dist or maxdist
			distances[targ][i] = dist
			if (dist > 9.9) then
				tooFar = tooFar + 1
			end
		end
		distances[targ].tooFarCount = tooFar
		
		if (distances[fewestTooFar].tooFarCount > tooFar) then
			fewestTooFar = targ
		end
		if (maxdist < 10) then
			found = true
		end
		targ = targ + 1
	end
	
	if ((c - distances[fewestTooFar].tooFarCount) == 1) then
		return nil	--Everyone is too far apart for a curaga
	end
	
	local cgaTier = round(tsum / c) - 1
	cgaTier = (cgaTier > settings.healing.maxCuraga) and settings.healing.maxCuraga or cgaTier
	cgaTier = (cgaTier < 1) and 1 or cgaTier
	local player = windower.ffxi.get_player()
	local recasts = windower.ffxi.get_spell_recasts()
	local spell = res.spells:with('en', curaga_of_tier[cgaTier])
	local rctime = recasts[spell.recast_id] or 0
	local mpMult = CureUtils.get_multiplier()
	local mpTooLow = (spell.mp_cost * mpMult) > player.vitals.mp
	
	if not ((rctime > 0) or mpTooLow) then
		return spell, positions[fewestTooFar].name
	end
	return nil
end

--[[
	Returns a table with party members and how much hp they are missing
--]]
function getMissingHps()
	local targets = getMonitoredPlayers()				--Get list of players to analyze
	local hpTable = {}						--Initialize table to store their info
	for _,trg in pairs(targets) do					--Iterate through the list of players
		local hpMissing = 0						--Default to 0 HP missing
		if (trg.hp ~= nil) then						--If the player has a valid hp attribute
			hpMissing = math.ceil((trg.hp/(trg.hpp/100))-trg.hp)		--Calculate how much HP they are missing
		else								--Otherwise, if the hp attribute cannot be accessed
			hpMissing = 1500 - math.ceil((trg.hpp/100)*1500)		--Guesstimate how much HP they are missing
		end
		hpTable[trg.name] = {['missing']=hpMissing, ['hpp']=trg.hpp}	--Store their info in the table
	end
	return hpTable							--Return the table with players' HP info
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