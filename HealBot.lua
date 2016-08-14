_addon.name = 'HealBot'
_addon.author = 'Lorand'
_addon.command = 'hb'
_addon.version = '2.10.6'
_addon.lastUpdate = '2016.08.14.1'

require('luau')
require('lor/lor_utils')
_libs.lor.include_addon_name = true
_libs.lor.req('all', {n='tables',v='2016.07.24.1'}, {n='chat',v='2016.07.30'})
_libs.req('queues')
lor_settings = _libs.lor.settings

healer = {}

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

hb = {}

windower.register_event('load', function()
    if not _libs.lor then
        windower.add_to_chat(39,'ERROR: .../Windower/addons/libs/lor/ not found! Please download: https://github.com/lorand-ffxi/lor_libs')
    end
    atcc(262,'Welcome to HealBot! To see a list of commands, type //hb help')
    atcc(39,'=':rep(80))
    atcc(261,'WARNING: I switched the config files from XMLs to lua files.')
    atcc(261,'You will need to update the lua files with any custom settings you had in your XMLs!')
    atcc(261,'I apologize for the inconvenience; this makes many things easier behind the scenes.')
    atcc(39,'=':rep(80))

    healer.zone_enter = os.clock()-25
    healer.zone_wait = false
    healer.lastAction = os.clock()
    healer.lastMoveCheck = os.clock()
    healer.actionStart = os.clock()
    healer.actionEnd = healer.actionStart + 0.1
    
    local player = windower.ffxi.get_player()
    healer.name = player and player.name or 'Player'
    
    modes = {['showPacketInfo']=false,['debug']=false,['mob_debug']=false}
    _libs.lor.debug = modes.debug
    active = false
    lastActingState = false
    partyMemberInfo = {}
    
    trusts = populateTrustList()
    ignoreList = S{}
    extraWatchList = S{}
    
    configs_loaded = false
    load_configs()
    CureUtils.init_cure_potencies()
end)

windower.register_event('logout', function()
    windower.send_command('lua unload healBot')
end)

windower.register_event('zone change', function(new_id, old_id)
    healer.zone_enter = os.clock()
end)

windower.register_event('job change', function()
    active = false
    printStatus()
end)

windower.register_event('incoming chunk', handle_incoming_chunk)
windower.register_event('addon command', processCommand)


--[[
    Executes before each frame is rendered for display.
    Acts as the run() method of a threaded application.
--]]
windower.register_event('prerender', function()
    local now = os.clock()
    local moving = hb.isMoving(now)
    local acting = hb.isPerformingAction(moving)
    local player = windower.ffxi.get_player()
    healer.name = player and player.name or 'Player'
    if (player ~= nil) and S{0,1,5}:contains(player.status) then    --0/1/5 = idle/engaged/chocobo
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
            if (now - healer.lastAction) > settings.actionDelay then
                actions.take_action(player, partner, targ)
                healer.lastAction = now     --Refresh stored action check time
            end
        end
    end
end)

function wcmd(prefix, action, target)
    windower.send_command('input %s "%s" "%s"':format(prefix, action, target))
    settings.actionDelay = 0.6
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
    if (player ~= nil) and (not (ignoreList:contains(player.name))) then
        local is_trust = player.mob and player.mob.spawn_type == 14 or false    --13 = players; 14 = Trust NPC
        if (settings.ignoreTrusts and is_trust and (not extraWatchList:contains(player.name))) then return end
        local status = player.mob and player.mob.status or player.status
        if (S{2,3}:contains(status)) or (player.hpp <= 0) then
            --Player is dead.  Reset their buff/debuff lists and don't include them in monitored list
            buffs.resetDebuffTimers(player.name)
            buffs.resetBuffTimers(player.name)
        else
            player.trust = is_trust
            list[player.name] = player
        end
    end
end

function hb.getMonitoredPlayers()
    local pt = windower.ffxi.get_party()
    local me = pt.p0
    local targets = S{}
    
    local pty = {pt.p0,pt.p1,pt.p2,pt.p3,pt.p4,pt.p5}
    for _,player in pairs(pty) do
        if (me.zone == player.zone) then
            hb.addPlayer(targets, player)
        end
    end
    
    local alliance = {pt.a10,pt.a11,pt.a12,pt.a13,pt.a14,pt.a15,pt.a20,pt.a21,pt.a22,pt.a23,pt.a24,pt.a25}
    for _,ally in pairs(alliance) do
        if (ally ~= nil) and (extraWatchList:contains(ally.name)) and (me.zone == ally.zone) then
            hb.addPlayer(targets, ally)
        end
    end
    
    for extraName,_ in pairs(extraWatchList) do
        local extraPlayer = windower.ffxi.get_mob_by_name(extraName)
        if (extraPlayer ~= nil) and (not targets:contains(extraPlayer.name)) then
            hb.addPlayer(targets, extraPlayer)
        end
    end
    txts.montoredBox:text(getPrintable(targets, true))
    txts.montoredBox:visible(settings.textBoxes.montoredBox.visible)
    return targets
end

function hb.isMoving(now)
    if (getPosition() == nil) then
        txts.moveInfo:hide()
        return true
    end
    healer.lastPos = healer.lastPos or getPosition()
    healer.posArrival = healer.posArrival or os.clock()
    local currentPos = getPosition()
    local moving = true
    local timeAtPos = math.floor((now - healer.posArrival)*10)/10
    if (healer.lastPos:equals(currentPos)) then
        moving = (timeAtPos < 0.5)
    else
        healer.lastPos = currentPos
        healer.posArrival = now
    end
    if math.floor(timeAtPos) == timeAtPos then
        timeAtPos = timeAtPos..'.0'
    end
    txts.moveInfo:text('Time @ '..currentPos:toString()..': '..timeAtPos..'s')
    txts.moveInfo:visible(settings.textBoxes.moveInfo.visible)
    return moving
end

function hb.isPerformingAction(moving)
    if (os.clock() - healer.actionStart) > 8 then
        --Precaution in case an action completion isn't registered for a long time
        healer.actionEnd = os.clock()
    end
    
    local acting = (healer.actionEnd < healer.actionStart)
    local status = acting and 'performing an action' or (moving and 'moving' or 'idle')
    status = 'is '..status
    
    if (lastActingState ~= acting) then --If the current acting state is different from the last one
        if lastActingState then         --If an action was being performed
            settings.actionDelay = 2.75         --Set a longer delay
            healer.lastAction = os.clock()      --The delay will be from this time
        else                    --If no action was being performed
            settings.actionDelay = 0.1          --Set a short delay
        end
        lastActingState = acting        --Refresh the last acting state
    end
    
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
    
    local hb = active and '\\cs(0,0,255)[ON]\\cr' or '\\cs(255,0,0)[OFF]\\cr'
    txts.actionInfo:text(' %s %s %s':format(hb, healer.name, status))
    txts.actionInfo:visible(settings.textBoxes.actionInfo.visible)
    return acting
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
