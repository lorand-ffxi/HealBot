_addon.name = 'HealBot'
_addon.author = 'Lorand'
_addon.command = 'hb'
_addon.version = '2.9.8'
_addon.lastUpdate = '2015.05.10'

_libs = _libs or {}
_libs.luau = _libs.luau or require('luau')
_libs.queues = _libs.queues or require('queues')

res = require('resources')
config = require('config')
texts = require('texts')
packets = require('packets')
files = require('files')

require 'HealBot_statics'
require 'HealBot_utils'

Assert =	require 'HB_Assertion'
CureUtils =	require 'HB_CureUtils'

require 'HealBot_buffHandling'
require 'HealBot_cureHandling'
require 'HealBot_followHandling'
require 'HealBot_packetHandling'
require 'HealBot_actionHandling'
require 'HealBot_queues'

info = import('../info/info_share.lua')	--Load addons\info\info_share.lua for functions to print info from windower

windower.register_event('load', function()
	atcc(262,'Welcome to HealBot! To see a list of commands, type //hb help')
	atcc(261,'Curaga use is in beta testing! If it causes issues, you can disable it via //hb disable curaga, or in your settings xml')
	configs_loaded = false
	load_configs()
	
	zone_enter = os.clock()-25
	zone_wait = false
	
	trusts = populateTrustList()
	ignoreList = S{}
	extraWatchList = S{}
	
	lastAction = os.clock()
	lastMoveCheck = os.clock()
	actionStart = os.clock()
	actionEnd = actionStart + 0.1
	
	local player = windower.ffxi.get_player()
	myName = player and player.name or 'Player'
	
	modes = {['showPacketInfo']=false,['ignoreTrusts']=true,['debug']=false}
	active = false
	lastActingState = false
	partyMemberInfo = {}
end)

windower.register_event('logout', function()
	windower.send_command('lua unload healBot')
end)

windower.register_event('zone change', function(new_id, old_id)
	zone_enter = os.clock()
end)

windower.register_event('job change', function()
	active = false
	printStatus()
end)

windower.register_event('incoming chunk', handle_incoming_chunk)
windower.register_event('addon command', processCommand)

function get_assist_targets()
	if settings.assist.active and (settings.assist.name ~= nil) then
		local partner = windower.ffxi.get_mob_by_name(settings.assist.name)
		if (partner ~= nil) then
			local targ = windower.ffxi.get_mob_by_index(partner.target_index)
			if (targ ~= nil) and targ.is_npc then
				return partner,targ
			end
		end
	end
	return nil
end

--[[
	Executes before each frame is rendered for display.
	Acts as the run() method of a threaded application.
--]]
windower.register_event('prerender', function()
	local now = os.clock()						--Record the current time
	local moving = isMoving()					--Determine player's movement status
	local acting = isPerformingAction(moving)			--Determine player's action status
	local player = windower.ffxi.get_player()			--Retrieve player info from windower
	if (player ~= nil) and S{0,1}:contains(player.status) then	--Assert player is idle or engaged
		Assert.follow_target_exists()				--Try to prevent autorun problems
		if (settings.follow.active or settings.assist.active) and ((now - lastMoveCheck) > settings.follow.delay) then
			local should_move = false
			local partner,targ = get_assist_targets()
			if (targ ~= nil) and (player.target_index == partner.target_index) then
				if settings.assist.engage and (partner.status == 1) then
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
			lastMoveCheck = now				--Refresh stored movement check time
		end
		
		
		-- if settings.follow.active and ((now - lastFollowCheck) > settings.follow.delay) then
			-- if not needToMove(settings.follow.target, settings.follow.distance) then
				-- windower.ffxi.run(false)		--Stop if movement isn't necessary
			-- else
				-- moveTowards(settings.follow.target)	--Move towards follow target
				-- moving = true				--Prevent an action if player needs to move
			-- end
			-- lastMoveCheck = now				--Refresh stored movement check time
		-- end
		
		local busy = moving or acting				--Player is busy if moving or acting
		if active and (not busy) and ((now - lastAction) > settings.actionDelay) then	--If acting is possible
			checkOwnBuffs()
			local action = getActionToPerform()		--Pick an action to perform
			if (action ~= nil) then				--If there's a defensive action to perform
				local act = action.action
				local tname = action.name
				local msg = action.msg or ''
				
				--Record attempt time for buffs/debuffs
				buffList[tname] = buffList[tname] or {}
				if (action.type == 'buff') and (buffList[tname][action.buff]) then
					buffList[tname][action.buff].attempted = os.clock()
				elseif (action.type == 'debuff') then
					debuffList[tname][action.debuff].attempted = os.clock()
				end
				
				atcd(act.en..sparr..tname..msg)			--Debug message
				wcmd(act.prefix, act.en, tname)			--Send command to windower
			else						--Otherwise, there may be an offensive action
				local partner,targ = get_assist_targets()
				if (targ ~= nil) then
					local partner_engaged = (partner.status == 1)
					local self_engaged = (player.status == 1)
					if (player.target_index == partner.target_index) then
						if settings.assist.engage and partner_engaged and (not self_engaged) then
							windower.send_command('input /attack on')
							settings.actionDelay = 0.6
						else
							local action = getOffensiveAction()
							if (action ~= nil) then
								local act = action.action
								local tname = action.name
								local msg = action.msg or ''
								
								atcd(act.en..sparr..tname..msg)	--Debug message
								wcmd(act.prefix, act.en, tname)	--Send cmd to windower
							end
						end
					else							--Different targets
						if partner_engaged and (not self_engaged) then
							windower.send_command('input /as '..settings.assist.name)
							settings.actionDelay = 0.6
						end
					end
				end
			end
			lastAction = now				--Refresh stored action check time
		end
	end
end)

function wcmd(prefix, action, target)
	windower.send_command('input '..prefix..' "'..action..'" '..target)
	settings.actionDelay = 0.6
end

function activate()
	local player = windower.ffxi.get_player()
	if player ~= nil then
		settings.healing.maxCure = CureUtils.highest_cure_tier()
		settings.healing.maxWaltz = CureUtils.highest_waltz_tier()
		settings.healing.maxCuraga = CureUtils.highest_curaga_tier()
		settings.healing.maxWaltzga = CureUtils.highest_waltzga_tier()
		if (settings.healing.maxCure == 0) then
			disableCommand('cure', true)
		end
		active = true
	end
	printStatus()
end

function addPlayer(list, player)
	if (player ~= nil) and (not (ignoreList:contains(player.name))) then
		if (modes.ignoreTrusts and trusts:contains(player.name) and (not extraWatchList:contains(player.name))) then return end
		local status = player.mob and player.mob.status or player.status
		if (S{2,3}:contains(status)) or (player.hpp <= 0) then
			--Player is dead.  Reset their buff/debuff lists and don't include them in monitored list
			resetDebuffTimers(player.name)
			resetBuffTimers(player.name)
		else
			list[player.name] = player
		end
	end
end

function getMonitoredPlayers()
	local pt = windower.ffxi.get_party()
	local me = pt.p0
	local targets = S{}
	
	local pty = {pt.p0,pt.p1,pt.p2,pt.p3,pt.p4,pt.p5}
	for _,player in pairs(pty) do
		if (me.zone == player.zone) then
			addPlayer(targets, player)
		end
	end
	
	local alliance = {pt.a10,pt.a11,pt.a12,pt.a13,pt.a14,pt.a15,pt.a20,pt.a21,pt.a22,pt.a23,pt.a24,pt.a25}
	for _,ally in pairs(alliance) do
		if (ally ~= nil) and (extraWatchList:contains(ally.name)) and (me.zone == ally.zone) then
			addPlayer(targets, ally)
		end
	end
	
	for extraName,_ in pairs(extraWatchList) do
		local extraPlayer = windower.ffxi.get_mob_by_name(extraName)
		if (extraPlayer ~= nil) and (not targets:contains(extraPlayer.name)) then
			addPlayer(targets, extraPlayer)
		end
	end
	txts.montoredBox:text(getPrintable(targets, true))
	txts.montoredBox:visible(settings.textBoxes.montoredBox.visible)
	return targets
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
	txts.moveInfo:visible(settings.textBoxes.moveInfo.visible)
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
			settings.actionDelay = 2.75			--Set a longer delay
			lastAction = os.clock()			--The delay will be from this time
		else					--If no action was being performed
			settings.actionDelay = 0.1			--Set a short delay
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
	elseif Assert.buff_active('Sleep','Petrification','Charm','Terror','Lullaby','Stun','Silence','Mute') then
		acting = true
		status = ' is disabled'
	end
	
	local player = windower.ffxi.get_player()
	if (player ~= nil) then
		local mpp = player.vitals.mpp
		if (mpp <= 10) then
			status = status..' | \\cs(255,0,0)LOW MP\\cr'
		end
	end
	
	local hb = active and ' \\cs(0,0,255)[ON]\\cr ' or ' \\cs(255,0,0)[OFF]\\cr '
	txts.actionInfo:text(hb..myName..status)
	txts.actionInfo:visible(settings.textBoxes.actionInfo.visible)
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