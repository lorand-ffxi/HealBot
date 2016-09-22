--======================================================================================================================
--[[
    Author: Ragnarok.Lorand
    HealBot Assertion functions
--]]
--======================================================================================================================

local as = {}

--[[
    Returns true if the given spell/ability has been learned and is available on the current job.
--]]
function as.can_use(spell)
    local player = windower.ffxi.get_player()
    if (player == nil) or (spell == nil) then return false end
    if S{'/magic','/ninjutsu','/song'}:contains(spell.prefix) then
        local learned = windower.ffxi.get_spells()[spell.id]
        if learned then
            local mj_id, sj_id = player.main_job_id, player.sub_job_id
            local jp_spent = player.job_points[player.main_job:lower()].jp_spent
            local mj_req = spell.levels[mj_id]
            local sj_req = spell.levels[sj_id]
            local mainCanCast, subCanCast = false, false
            if mj_req ~= nil then
                mainCanCast = (mj_req <= player.main_job_level) or (mj_req <= jp_spent)
            end
            if sj_req ~= nil then
                subCanCast = (sj_req <= player.sub_job_level)
            end
            return mainCanCast or subCanCast
        else
            if modes.debug then
                atcf('%s has not learned %s', player.name, spell.en)
            end
        end
    elseif S{'/jobability','/pet'}:contains(spell.prefix) then
        local available_jas = S(windower.ffxi.get_abilities().job_abilities)
        return available_jas:contains(spell.id)
    elseif (spell.prefix == '/weaponskill') then
        local available_wss = S(windower.ffxi.get_abilities().weapon_skills)
        return available_wss:contains(spell.id)
    else
        atc(123,'Error: Unknown spell prefix ('..tostring(spell.prefix)..') for '..tostring(spell.en))
    end
    return false
end


--[[
    Returns true if the given spell/ability can be used, and is not on cooldown.
--]]
function as.ready_to_use(spell)
    if (spell ~= nil) and as.can_use(spell) then
        local player = windower.ffxi.get_player()
        if (player == nil) then return false end
        if S{'/magic','/ninjutsu','/song'}:contains(spell.prefix) then
            local rc = windower.ffxi.get_spell_recasts()[spell.recast_id]
            return rc == 0
        elseif S{'/jobability','/pet'}:contains(spell.prefix) then
            local rc = windower.ffxi.get_ability_recasts()[spell.recast_id]
            return rc == 0
        elseif (spell.prefix == '/weaponskill') then
            return (player.status == 1) and (player.vitals.tp > 999)
        end
    end
    return false
end

--[[
    Returns true if the type of the given target is included in the list of valid targets for the given
    spell/ability.
--]]
function as.target_is_valid(action, target)
    if (type(target) == 'string') then
        target = utils.getTarget(target)    --TODO: FIX!! (in HealBot_utils.lua)
    end
    if target == nil then return false end
    local stype = target.spawn_type
    
    local targetType = 'None'
    if target.is_npc and (stype ~= 14) then
        targetType = 'Enemy'
    elseif target.in_alliance then
        if target.in_party then
            targetType = (healer.name == target.name) and 'Self' or 'Party'
        else
            targetType = 'Ally'
        end
    else
        --targetType = 'Player'
        targetType = 'Ally' --Workaround for incorrect entries in resources
    end
    return S(action.targets):contains(targetType)
end

--[[
    Returns true if player/mob with the given name is in casting range.
--]]
function as.in_casting_range(name)
    local target = utils.getTarget(name)
    if (target ~= nil) then
        return math.sqrt(target.distance) < 20.9
    end
    return false
end

--[[
    Returns true if one of the given buffs are currently active.
--]]
function as.buff_active(...)
    local args = S{...}:map(string.lower)
    local player = windower.ffxi.get_player()
    if (player ~= nil) and (player.buffs ~= nil) then
        for _,bid in pairs(player.buffs) do
            local buff = res.buffs[bid]
            if args:contains(buff.en:lower()) then
                return true
            end
        end
    end
    return false
end

function as.follow_target_exists()
    if (settings.follow.target == nil) then return end
    local ft = windower.ffxi.get_mob_by_name(settings.follow.target)
    if settings.follow.active and (ft == nil) then
        settings.follow.pause = true
        settings.follow.active = false
    elseif settings.follow.pause and (ft ~= nil) then
        settings.follow.pause = nil
        settings.follow.active = true
    end
end

return as

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