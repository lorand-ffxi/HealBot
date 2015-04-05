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
	
	for name,p in pairs(hpTable) do				--Iterate through the missing HP table
		if (p.hpp < 95) then				--Ignore players with HP > 95%
			local tier = get_tier_for_hp(p.missing)	--Pick a cure tier based on the amount of HP missing
			if (tier >= minCureTier) then		--Filter out players without enough HP missing
				tierReqs[name] = tier	
				local spell = get_cure_to_cast(p.missing, tier)	--Edit tier for MP and recast timers
				if (spell ~= nil) then
					cq:enqueue('cure', spell, name, p.hpp, ' ('..p.missing..')')	--Enqueue it
				end
			end
		end
	end
	--If enough members need cures, determine if a Curaga spell should be used
	if (not settings.disable.curaga) and (sizeof(tierReqs) > 2) and (settings.maxCuragaTier > 0) then
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
		else
			atc('Not in party: '..tostring(name))
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
	cgaTier = (cgaTier > settings.maxCuragaTier) and settings.maxCuragaTier or cgaTier
	cgaTier = (cgaTier < 1) and 1 or cgaTier
	local player = windower.ffxi.get_player()
	local recasts = windower.ffxi.get_spell_recasts()
	local spell = res.spells:with('en', curaga_of_tier[cgaTier])
	local rctime = recasts[spell.recast_id] or 0
	local mpMult = cureCostMod()
	local mpTooLow = (spell.mp_cost * mpMult) > player.vitals.mp
	
	if not ((rctime > 0) or mpTooLow) then
		return spell, positions[fewestTooFar].name
	end
	return nil
end

--[[
	Returns the spell info for the tier of Cure that should/can be used based on
	the amount of HP that the target is missing, the player's current MP, and
	the player's recast timers.
--]]
function get_cure_to_cast(hpMissing, baseTier)
	local player = windower.ffxi.get_player()			--Get player info
	local tier = baseTier						--Choose Cure tier by hp missing
	if (tier < minCureTier) then return nil end			--Return nil if not enough is missing
	
	local recasts = windower.ffxi.get_spell_recasts()		--Get recast timers
	local spell = res.spells:with('en', cure_of_tier[tier])		--Get info for chosen Cure spell
	local rctime = recasts[spell.recast_id] or 0			--Get time left before chosen Cure can be cast
	local mpMult = cureCostMod()					--Get the Cure cost multiplier
	local mpTooLow = (spell.mp_cost * mpMult) > player.vitals.mp	--Determine if player has enough MP
	
	while (tier > 1) and (mpTooLow or (rctime > 0)) do		--Iterate while the chosen spell can't be cast
		tier = tier - 1							--Decrement the tier
		spell = res.spells:with('en', cure_of_tier[tier])		--Get info for the new tier of Cure
		rctime = recasts[spell.recast_id] or 0				--Get time left before the new tier of Cure can be cast
		mpTooLow = (spell.mp_cost * mpMult) > player.vitals.mp		--Determine if player has enough MP for the new Cure tier
	end
	return spell							--Return the spell info for the chosen Cure spell
end

--[[
	Returns the tier of Cure that should be used given the amount of HP that
	the target is missing.
--]]
function get_tier_for_hp(hpMissing)
	local tier = settings.maxCureTier			--Set the Cure tier to the maximum castable tier
	local potency = cure_potencies[tier]			--Retrieve the Cure potency for the given tier
	local pdelta = potency - cure_potencies[tier-1]		--Calculate the potency difference between this tier and the next lowest tier
	local threshold = potency - (pdelta * 0.5)		--Calculate the value to compare the amount of missing HP to
	while hpMissing < threshold do				--Iterate while the current Cure tier is higher than necessary
		tier = tier - 1						--Decrement the tier
		if tier > 1 then					--If the tier is high enough
			potency = cure_potencies[tier]				--Retrieve the Cure potency for the new tier
			pdelta = potency - cure_potencies[tier-1]		--Recalculate the potency difference
			threshold = potency - (pdelta * 0.5)			--Recalculate the comparison value
		else							--Otherwise
			threshold = 0						--Break out of the loop
		end
	end
	return tier						--Return the tier of Cure that should be cast
end

--[[
	Returns the multiplier for the MP cost of Cure based on the player's job.
--]]
function cureCostMod()
	local p = windower.ffxi.get_player()			--Get player info
	local mpMult = 1					--Default multiplier is 1
	if S{p.job, p.sub_job}:contains('SCH') then		--If SCH is main or sub job
		if buffActive('Light Arts','Addendum: White') then	--If Light Arts is active
			mpMult = 0.9						--MP cost is 10% lower
			if buffActive('Penury') then				--If Penury is active
				mpMult = 0.5						--MP cost is halved
			end
		elseif buffActive('Dark Arts','Addendum: Black') then	--If Dark Arts is active
			mpMult = 1.1						--MP cost is 10% higher
		end
	end
	return mpMult						--Return the MP mutiplier
end

--[[
	Returns info about the player with the most HP missing from the given
	set of players.
--]]
function getMemberWithMostHpMissing(party)
	local curee = {['missing']=0}				--Initialize table where info will be stored
	for name,p in pairs(party) do				--Iterate through the given set of players
		if (p.missing > curee.missing) and (p.hpp < 95) then	--If pc is missing more HP than the stored one
			curee.name = name					--Store their name
			curee.missing = p.missing				--And store the amount of HP they're missing
			curee.hpp = p.hpp
		end
	end
	if curee.missing > 0 then				--If someone is missing some HP
		return curee						--Return their info
	else							--Otherwise, if no one is missing HP
		return nil						--Return nil
	end
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

--[[
	Returns the tier of the highest potency Cure spell that the player is
	currently able to cast.
--]]
function determineHighestCureTiers()
	local highestCure,highestCuraga = 0,0
	for id, avail in pairs(windower.ffxi.get_spells()) do
		if avail then
			local spell = res.spells[id]
			if S(cure_of_tier):contains(spell.en) then
				if canCast(spell) then
					local tier = tier_of_cure[spell.en]
					if tier > highestCure then
						highestCure = tier
					end
				end
			elseif S(curaga_of_tier):contains(spell.en) then
				if canCast(spell) then
					local tier = tier_of_curaga[spell.en]
					if tier > highestCuraga then
						highestCuraga = tier
					end
				end
			end
		end
	end
	
	settings.maxCureTier = highestCure
	settings.maxCuragaTier = highestCuraga
	if (settings.maxCureTier == 0) then
		disableCommand('cure', true)
	end
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