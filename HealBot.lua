_addon.name = 'HealBot'
_addon.author = 'Lorand'
_addon.command = 'hb'
_addon.version = '2.13.1'
_addon.lastUpdate = '2016.10.31.0'

--[[
TODO:
- Global action queue instead of rebuilding every cycle
- Action sets that must be performed together (e.g., Snake Eye, then Double Up)
- GEO
- COR
    - Rolled # detection
--]]


require('luau')
require('lor/lor_utils')
_libs.lor.include_addon_name = true
_libs.lor.req('all', {n='packets',v='2016.10.27.0'})
_libs.req('queues')
lor_settings = _libs.lor.settings
serialua = _libs.lor.serialization

hb = {}
healer = {indi={},geo={}}

res = require('resources')
config = require('config')
texts = require('texts')
packets = require('packets')
files = require('files')

require 'HealBot_statics'
require 'HealBot_utils'

Assert =    require('HB_Assertion')
CureUtils = require('HB_CureUtils')
offense = require('HB_Offense')
actions = require('HB_Actions')

buffs = require('HealBot_buffHandling')
require('HealBot_followHandling')
require('HealBot_packetHandling')
require('HealBot_queues')


local _events = {}
local ipc_req = serialua.encode({method='GET', pk='buff_ids'})
local can_act_statuses = S{0,1,5,85}    --0/1/5/85 = idle/engaged/chocobo/other_mount
local dead_statuses = S{2,3}
local pt_keys = {'party1_count','party2_count','party3_count'}
local pm_keys = {
    {'p0','p1','p2','p3','p4','p5'},
    {'a10','a11','a12','a13','a14','a15'},
    {'a20','a21','a22','a23','a24','a25'}
}


_events['load'] = windower.register_event('load', function()
    if not _libs.lor then
        windower.add_to_chat(39,'ERROR: .../Windower/addons/libs/lor/ not found! Please download: https://github.com/lorand-ffxi/lor_libs')
    end
    atcc(262,'Welcome to HealBot! To see a list of commands, type //hb help')
    atcc(39,'=':rep(80))
    atcc(261,'WARNING: I switched the config files from XMLs to lua files.')
    atcc(261,'You will need to update the lua files with any custom settings you had in your XMLs!')
    atcc(261,'I apologize for the inconvenience; this makes many things easier behind the scenes.')
    atcc(39,'=':rep(80))

    local now = os.clock()
    healer.zone_enter = now - 25
    healer.zone_wait = false
    healer.lastMoveCheck = now
    healer.last_ipc_sent = now
    healer.ipc_delay = 2
    
    local player = windower.ffxi.get_player()
    healer.name = player and player.name or 'Player'
    healer.job = player.main_job
    healer.id = player.id
    healer.actor = _libs.lor.actor.Actor.new(healer.id)
    
    modes = {['showPacketInfo']=false,['debug']=false,['mob_debug']=false}
    _libs.lor.debug = modes.debug
    active = false
    partyMemberInfo = {}
    
    ignoreList = S{}
    extraWatchList = S{}
    
    configs_loaded = false
    load_configs()
    CureUtils.init_cure_potencies()
end)


_events['unload'] = windower.register_event('unload', function()
    for _,event in pairs(_events) do
        windower.unregister_event(event)
    end
end)


_events['logout'] = windower.register_event('logout', function()
    windower.send_command('lua unload healBot')
end)


_events['zone'] = windower.register_event('zone change', function(new_id, old_id)
    healer.zone_enter = os.clock()
    local zone_info = windower.ffxi.get_info()
    if zone_info ~= nil then
        if zone_info.zone == 131 then
            windower.send_command('lua unload healBot')
        elseif zone_info.mog_house == true then
            active = false
        elseif indoor_zones:contains(zone_info.zone) then
            active = false
        end
    end
end)


_events['job'] = windower.register_event('job change', function()
    active = false
    local player = windower.ffxi.get_player()
    healer.job = player.main_job
    printStatus()
end)

_events['inc'] = windower.register_event('incoming chunk', handle_incoming_chunk)
_events['cmd'] = windower.register_event('addon command', processCommand)


--[[
    Executes before each frame is rendered for display.
    Acts as the run() method of a threaded application.
--]]
_events['render'] = windower.register_event('prerender', function()
    local now = os.clock()
    local moving = hb.isMoving()
    local acting = hb.isPerformingAction(moving)
    local player = windower.ffxi.get_player()
    healer.name = player and player.name or 'Player'
    if (player ~= nil) and can_act_statuses:contains(player.status) then
        local partner,targ = offense.assistee_and_target()
        Assert.follow_target_exists()   --Attempts to prevent autorun problems
        if (settings.follow.active or offense.assist.active) and ((now - healer.lastMoveCheck) > settings.follow.delay) then
            local should_move = false
            if (targ ~= nil) and (player.target_index == partner.target_index) then
                if offense.assist.engage and (partner.status == 1) then
                    if needToMove(targ.id, 3) then
                        should_move = true
                        moveTowards(targ.id)
                    end
                end
            end
            if (not should_move) and settings.follow.active and needToMove(settings.follow.target, settings.follow.distance) then
                should_move = true
                moveTowards(settings.follow.target)
            end
            if (not should_move) then
                if settings.follow.active then
                    windower.ffxi.run(false)
                end
            else
                moving = true
            end
            healer.lastMoveCheck = now      --Refresh stored movement check time
        end
        
        if active and not (moving or acting) then
            --active = false    --Quick stop when debugging
            if healer.actor:action_delay_passed() then
                healer.actor.last_action = now              --Refresh stored action check time
                actions.take_action(player, partner, targ)
            end
        end
        
        if active and ((now - healer.last_ipc_sent) > healer.ipc_delay) then
            windower.send_ipc_message(ipc_req)
            healer.last_ipc_sent = now
        end
    end
end)


function wcmd(prefix, action, target)
    healer.actor:send_cmd('input %s "%s" "%s"':format(prefix, action, target))
end


function hb.activate()
    local player = windower.ffxi.get_player()
    if player ~= nil then
        settings.healing.max = {}
        for _,cure_type in pairs({'cure','waltz','curaga','waltzga'}) do
            settings.healing.max[cure_type] = CureUtils.highest_tier(cure_type)
        end
        if (settings.healing.max.cure == 0) then
            disableCommand('cure', true)
        end
        active = true
    end
    printStatus()
end


function hb.addPlayer(list, player)
    if (player == nil) or list:contains(player.name) or ignoreList:contains(player.name) then return end
    local is_trust = player.mob and player.mob.spawn_type == 14 or false    --13 = players; 14 = Trust NPC
    if (settings.ignoreTrusts and is_trust and (not extraWatchList:contains(player.name))) then return end
    local status = player.mob and player.mob.status or player.status
    if dead_statuses:contains(status) or (player.hpp <= 0) then
        --Player is dead.  Reset their buff/debuff lists and don't include them in monitored list
        buffs.resetDebuffTimers(player.name)
        buffs.resetBuffTimers(player.name)
    else
        player.trust = is_trust
        list[player.name] = player
    end
end


local function _getMonitoredPlayers()
    local pt = windower.ffxi.get_party()
    local my_zone = pt.p0.zone
    local targets = S{}
    for p = 1, #pt_keys do
        for m = 1, pt[pt_keys[p]] do
            local pt_member = pt[pm_keys[p][m]]
            if my_zone == pt_member.zone then
                if p == 1 or extraWatchList:contains(pt_member.name) then
                    hb.addPlayer(targets, pt_member)
                end
            end
        end
    end
    for extraName,_ in pairs(extraWatchList) do
        hb.addPlayer(targets, windower.ffxi.get_mob_by_name(extraName))
    end
    txts.montoredBox:text(getPrintable(targets, true))
    txts.montoredBox:visible(settings.textBoxes.montoredBox.visible)
    return targets
end
hb.getMonitoredPlayers = _libs.lor.advutils.tcached(1, _getMonitoredPlayers)


local function _getMonitoredIds()
    local ids = S{}
    for name, player in pairs(hb.getMonitoredPlayers()) do
        local id = player.mob and player.mob.id or player.id or utils.get_player_id[name]
        if id ~= nil then
            ids[id] = true
        end
    end
    return ids
end
hb.getMonitoredIds = _libs.lor.advutils.tcached(1, _getMonitoredIds)


function hb.isMoving()
    local timeAtPos = healer.actor:time_at_pos()
    if timeAtPos == nil then
        txts.moveInfo:hide()
        return true
    end
    local moving = healer.actor:is_moving()
    txts.moveInfo:text('Time @ %s: %.1fs':format(healer.actor:pos():toString(), timeAtPos))
    txts.moveInfo:visible(settings.textBoxes.moveInfo.visible)
    return moving
end


function hb.isPerformingAction(moving)
    local acting = healer.actor:is_acting()
    local status = 'is %s':format(acting and 'performing an action' or (moving and 'moving' or 'idle'))
    
    if (os.clock() - healer.zone_enter) < 25 then
        acting = true
        status = 'zoned recently'
        healer.zone_wait = true
    elseif healer.zone_wait then
        healer.zone_wait = false
        buffs.resetBuffTimers('ALL', S{'Protect V','Shell V'})
    elseif Assert.buff_active('Sleep','Petrification','Charm','Terror','Lullaby','Stun','Silence','Mute') then
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
    
    local hb_status = active and '\\cs(0,0,255)[ON]\\cr' or '\\cs(255,0,0)[OFF]\\cr'
    txts.actionInfo:text(' %s %s %s':format(hb_status, healer.name, status))
    txts.actionInfo:visible(settings.textBoxes.actionInfo.visible)
    return acting
end


function hb.process_ipc(msg)
    local loaded = serialua.decode(msg)
    if loaded == nil then
        atc(53, 'Received nil IPC message')
    elseif type(loaded) ~= 'table' then
        atcfs(264, 'IPC message: %s', loaded)
    elseif loaded.method == 'GET' then
        if loaded.pk ~= nil then        
            if loaded.pk == 'buff_ids' then
                local player = windower.ffxi.get_player()
                local response = {
                    method='POST', pk='buff_ids', val=player.buffs,
                    pid=player.id, name=player.name, stype=player.spawn_type
                }
                local encoded = serialua.encode(response)
                windower.send_ipc_message(encoded)
            else
                atcfs(123, 'Invalid pk for GET request: %s', loaded.pk)
            end
        else
            atcfs(123, 'Invalid GET request: %s', msg)
        end
    elseif loaded.method == 'POST' then
        if loaded.pk ~= nil then        
            if loaded.pk == 'buff_ids' then
                if loaded.name ~= nil then                
                    local player = windower.ffxi.get_mob_by_name(loaded.name)
                    player = player or {id=loaded.pid,name=loaded.name,spawn_type=loaded.stype}
                    buffs.review_active_buffs(player, loaded.val)
                else
                    atcfs(123, 'Missing name in POST message: %s', msg)
                end
            else
                atcfs(123, 'Invalid pk for POST message: %s', loaded.pk)
            end
        else
            atcfs(123, 'Invalid POST message: %s', msg)
        end
    else
        atcfs(123, 'Invalid IPC message: %s', msg)
    end
end

_events['ipc'] = windower.register_event('ipc message', hb.process_ipc)


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
