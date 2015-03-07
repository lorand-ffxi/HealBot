--==============================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot cure handling functions
--]]
--==============================================================================

function getPotentialCures()
	local potentialActions = {}
	local c = 1
	local hpTable = getMissingHps()				--Get a table with players' HP info
	
	for name,p in pairs(hpTable) do
		if (p.hpp < 95) then
			local spell = get_cure_to_cast(p.missing)
			if (spell ~= nil) and (not isTooFar(name)) then
				potentialActions[c] = {action=spell,targ_hpp=p.hpp,targetName=name,msg=' ('..p.missing..')'}
				c = c + 1
			end
		end
	end
	return (sizeof(potentialActions) > 0) and potentialActions or nil
end

--[[
	Determines whether or not a Cure spell needs to be cast, and returns a table
	with information about what to cast.
--]]
function cureSomeone()
	local hpTable = getMissingHps()				--Get a table with players' HP info
	local curee = getMemberWithMostHpMissing(hpTable)	--Choose a target
	
	while (curee ~= nil) and (isTooFar(curee.name)) do	--If the player with the most missing HP is too far away
		hpTable[curee.name] = nil				--Remove them from the table
		curee = getMemberWithMostHpMissing(hpTable)		--Pick a new target
	end
	
	if (curee ~= nil) then					--If someone needs a Cure
		local spell = get_cure_to_cast(curee.missing)		--Get the info for the Cure spell to cast
		if (spell ~= nil) then					--If info was received
			local action = {}					--Build the action table
			action.msg = ' ('..curee.missing..')'			--Set the debug message
			action.targetName = curee.name				--The target is the curee
			action.targ_hpp = curee.hpp				--The cure target's HP%
			action.action = spell					--The action is the Cure spell
			return action						--Return the action table to be executed
		end
	end
	return nil						--Return nil if there's nothing to do
end

--[[
	Returns the spell info for the tier of Cure that should/can be used based on
	the amount of HP that the target is missing, the player's current MP, and
	the player's recast timers.
--]]
function get_cure_to_cast(hpMissing)
	local player = windower.ffxi.get_player()			--Get player info
	local tier = get_tier_for_hp(hpMissing)				--Choose Cure tier by hp missing
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
	local tier = maxCureTier				--Set the Cure tier to the maximum castable tier
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
function determineHighestCureTier()
	local highestTier = 0
	for id, avail in pairs(windower.ffxi.get_spells()) do
		if avail then
			local spell = res.spells[id]
			if S(cure_of_tier):contains(spell.en) then
				if canCast(spell) then
					local tier = tier_of_cure[spell.en]
					if tier > highestTier then
						highestTier = tier
					end
				end				
			end
		end
	end
	return highestTier
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