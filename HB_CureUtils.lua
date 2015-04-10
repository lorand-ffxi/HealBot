--======================================================================================================================
--[[
	Author: Ragnarok.Lorand
	HealBot cure handling functions
	
	Currently transitioning between HealBot_cureHandling.lua and this file.  This one will fully replace it soon.
--]]
--======================================================================================================================

local cu = {}

--======================================================================================================================
--					Static Cure Information
--======================================================================================================================
cu.cure = {
	[1] = {id=1,	en='Cure',		res=res.spells[1],		hp=94},
	[2] = {id=2,	en='Cure II',		res=res.spells[2],		hp=207},
	[3] = {id=3,	en='Cure III',		res=res.spells[3],		hp=469},
	[4] = {id=4,	en='Cure IV',		res=res.spells[4],		hp=880},
	[5] = {id=5,	en='Cure V',		res=res.spells[5],		hp=1110},
	[6] = {id=6,	en='Cure VI',		res=res.spells[6],		hp=1395}
}
cu.curaga = {
	[1] = {id=7,	en='Curaga',		res=res.spells[7],		hp=150},
	[2] = {id=8,	en='Curaga II',		res=res.spells[8],		hp=313},
	[3] = {id=9,	en='Curaga III',	res=res.spells[9],		hp=636},
	[4] = {id=10,	en='Curaga IV',		res=res.spells[10],		hp=1125},
	[5] = {id=11,	en='Curaga V',		res=res.spells[11],		hp=1510}
}
cu.waltz = {
	[1] = {id=190,	en='Curing Waltz',	res=res.job_abilities[190],	hp=157},
	[2] = {id=191,	en='Curing Waltz II',	res=res.job_abilities[191],	hp=325},
	[3] = {id=192,	en='Curing Waltz III',	res=res.job_abilities[192],	hp=581},
	[4] = {id=193,	en='Curing Waltz IV',	res=res.job_abilities[193],	hp=887},
	[5] = {id=311,	en='Curing Waltz V',	res=res.job_abilities[311],	hp=1156},
}
cu.waltzga = {
	[1] = {id=195,	en='Divine Waltz',	res=res.job_abilities[195],	hp=160},
	[2] = {id=262,	en='Divine Waltz II',	res=res.job_abilities[262],	hp=521},
}

--======================================================================================================================
--						Helper Functions
--======================================================================================================================

local function get_recast_timers(waltz)
	if waltz then
		return windower.ffxi.get_ability_recasts()
	else
		return windower.ffxi.get_spell_recasts()
	end
end

function cu.get_multiplier(waltz)
	local mult = 1
	if waltz then
		if Assert.buff_active('Trance') then
			mult = 0
		end
	else
		local p = windower.ffxi.get_player()
		if (p.job == 'BLM') and Assert.buff_active('Manafont') then
			mult = 0
		elseif Assert.buff_active('Manawell') then
			mult = 0
		elseif S{p.job, p.sub_job}:contains('SCH') then
			if Assert.buff_active('Light Arts','Addendum: White') then
				mult = Assert.buff_active('Penury') and 0.5 or 0.9
			elseif Assert.buff_active('Dark Arts','Addendum: Black') then
				mult = 1.1
			end
		end
	end
	return mult
end

--======================================================================================================================
--						Tier Determining Functions
--======================================================================================================================

--[[
	Determines the tier of single target cure that should be used for the given amount of missing HP.
	Works for both Cure spells and Curing Waltzes.
--]]
function cu.get_cure_tier_for_hp(hp_missing, waltz)
	local ctable = waltz and cu.waltz or cu.cure
	local tier = waltz and settings.healing.maxWaltz or settings.healing.maxCure
	while (tier > 1) do
		local potency = ctable[tier].hp			--Retrieve the potency for the current tier
		local pdelta = potency - ctable[tier].hp	--Calculate the difference from the next lowest tier
		local threshold = potency - (pdelta * 0.5)	--Calculate the value to compare to hp_missing
		
		if (hp_missing < threshold) then		--If the current tier is higher than necessary
			tier = tier - 1				--Then decrement the tier
		else						--Otherwise
			break					--Use the current tier
		end
	end
	return tier						--Return the tier that should be used
end

--[[
	Determines the tier of single target cure that should be used given the player's current state.
	Works for both Cure spells and Curing Waltzes.
--]]
function cu.get_usable_cure(orig_tier, waltz)
	local minTier = waltz and settings.healing.minWaltz or settings.healing.minCure
	if (orig_tier < minTier) then return nil end			--Return nil if not enough HP is missing
	
	local ctable = waltz and cu.waltz or cu.cure
	local player = windower.ffxi.get_player()
	local player_p = waltz and player.vitals.tp or player.vitals.mp	--Player's amount of mp/tp
	local recasts = get_recast_timers(waltz)			--Cooldown timers for spells/abilities
	local mult = cu.get_multiplier(waltz)				--Multiplier for MP/TP based on active buffs
	
	local tier = orig_tier
	while (tier > 1) do
		local spell = ctable[tier].res
		local rctime = recasts[spell.recast_id] or 0		--Cooldown remaining for current tier
		local cost = waltz and spell.tp_cost or spell.mp_cost	--Cost of current tier in MP/TP
		
		if ((cost * mult) > player_p) or (rctime > 0) then	--If not enough MP/TP or waiting on cooldown
			tier = tier - 1					--Then decrement the tier
		else							--Otherwise
			break						--Use the current tier
		end
	end
	return ctable[tier].res						--Return the resource info for the cure
end

--[[
	Determines the tier of multi target cure that should be used for the given amounts of missing HP.
	Works for both Curaga spells and Divine Waltzes.
--]]
--[[
function cu.get_curaga_tier_for_hp(hps_missing, waltz)
	local ctable = waltz and cu.waltzga or cu.curaga
	local tier = waltz and settings.healing.maxWaltzga or settings.healing.maxCuraga
end
--]]

--[[
	Determines the tier of multi target cure that should be used given the player's current state.
	Works for both Cure spells and Curing Waltzes.
--]]
--[[
function cu.get_usable_curaga(orig_tier, waltz)
	local minTier = waltz and settings.healing.minWaltzga or settings.healing.minCuraga
	if (orig_tier < minTier) then return nil end			--Return nil if not enough HP is missing
	
	local ctable = waltz and cu.waltzga or cu.curaga
	local player = windower.ffxi.get_player()
	local player_p = waltz and player.vitals.tp or player.vitals.mp	--Player's amount of mp/tp
	local recasts = get_recast_timers(waltz)			--Cooldown timers for spells/abilities
	local mult = cu.get_multiplier(waltz)				--Multiplier for MP/TP based on active buffs
	
	local tier = orig_tier
	while (tier > 1) do
		local spell = ctable[tier].res
		local rctime = recasts[spell.recast_id] or 0		--Cooldown remaining for current tier
		local cost = waltz and spell.tp_cost or spell.mp_cost	--Cost of current tier in MP/TP
		
		if ((cost * mult) > player_p) or (rctime > 0) then	--If not enough MP/TP or waiting on cooldown
			tier = tier - 1					--Then decrement the tier
		else							--Otherwise
			break						--Use the current tier
		end
	end
	return ctable[tier].res						--Return the resource info for the cure
end
--]]

--======================================================================================================================
--			Functions for determining which Cure spells & abilities are available
--======================================================================================================================

local function get_highest(tbl)
	local highest = 0
	for tier,spell in pairs(tbl) do
		if Assert.can_use(spell.res) then
			highest = (tier > highest) and tier or highest
		end
	end
	return highest
end

function cu.highest_cure_tier()
	return get_highest(cu.cure)
end
function cu.highest_curaga_tier()
	return get_highest(cu.curaga)
end
function cu.highest_waltz_tier()
	return get_highest(cu.waltz)
end
function cu.highest_waltzga_tier()
	return get_highest(cu.waltzga)
end

--======================================================================================================================

return cu

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