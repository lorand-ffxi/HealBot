_addon.name = 'HealBot'
_addon.author = 'Lorand'
_addon.command = 'hb'
_addon.version = '2.9.0'
_addon.lastUpdate = '2015.04.02'

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
require 'HealBot_Assert'
require 'HealBot_buffHandling'
require 'HealBot_cureHandling'
require 'HealBot_followHandling'
require 'HealBot_packetHandling'
require 'HealBot_actionHandling'
require 'HealBot_queues'

info = import('../info/info_share.lua')	--Load addons\info\info_share.lua for functions to print info from windower

windower.register_event('load', function()
	atcc(262,'Welcome to HealBot! To see a list of commands, type //hb help')
	configs_loaded = false
	load_configs()
	
	zone_enter = os.clock()-25
	zone_wait = false
	
	trusts = populateTrustList()
	ignoreList = S{}
	extraWatchList = S{}
	
	lastAction = os.clock()
	lastFollowCheck = os.clock()
	actionStart = os.clock()
	actionEnd = actionStart + 0.1
	
	local player = windower.ffxi.get_player()
	myName = player and player.name or 'Player'
	
	modes = {['showPacketInfo']=false,['showMoveInfo']=false,['showActionInfo']=true,['showActionQueue']=true,['showMonitored']=true,['ignoreTrusts']=true}
	debugMode = false
	active = false
	actionDelay = 0.08
	minCureTier = 3
	lastActingState = false
	partyMemberInfo = {}
	assist = false
end)

windower.register_event('logout', function()
	windower.send_command('lua unload healBot')
end)

windower.register_event('zone change', function(new_id, old_id)
	zone_enter = os.clock()
end)

windower.register_event('incoming chunk', handle_incoming_chunk)
windower.register_event('addon command', processCommand)

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
		assertFollowTargetExistence()		--Assert follow target is valid to prevent autorun problems
		if follow and ((now - lastFollowCheck) > followDelay) then	--If following & enough time has passed
			if not needToMove(followTarget) then
				windower.ffxi.run(false)		--Stop if movement isn't necessary
			else
				moveTowards(followTarget)		--Move towards follow target
				moving = true				--Prevent an action if player needs to move
			end
			lastFollowCheck = now				--Refresh stored movement check time
		end
		
		local busy = moving or acting				--Player is busy if moving or acting
		if active and (not busy) and ((now - lastAction) > actionDelay) then	--If acting is possible
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
				if assist and (assistTarget ~= nil) then
					local atarg = windower.ffxi.get_mob_by_name(assistTarget)
					if (atarg ~= nil) then
						local targ = windower.ffxi.get_mob_by_index(atarg.target_index)
						if (targ ~= nil) and targ.is_npc then
							if (player.target_index == atarg.target_index) then	--Same targets
								local action = getOffensiveAction()
								if (action ~= nil) then
									local act = action.action
									local tname = action.name
									local msg = action.msg or ''
									
									atcd(act.en..sparr..tname..msg)	--Debug message
									wcmd(act.prefix, act.en, tname)	--Send cmd to windower
								end
							else
								local at_engaged = (atarg.status == 1)
								local self_engaged = (player.status == 1)
								if at_engaged and (not self_engaged) then	--Should assist
									assistAttack = assistAttack and assistAttack or false
									local attcmd = assistAttack and ';wait 0.8;input /attack on' or ''
									windower.send_command('input /as '..assistTarget..attcmd)
								end
							end
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
	actionDelay = 0.6
end

function activate()
	local player = windower.ffxi.get_player()
	if player ~= nil then
		maxCureTier = determineHighestCureTier()
		active = (maxCureTier > 0)
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
	txts.montoredBox:visible(modes.showMonitored)
	return targets
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