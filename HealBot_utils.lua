--==============================================================================
--[[
    Author: Ragnarok.Lorand
    HealBot utility functions that don't belong anywhere else
--]]
--==============================================================================
--          Input Handling Functions
--==============================================================================

utils = {normalize={}}


function utils.normalize_str(str)
    return str:lower():gsub(' ', '_'):gsub('%.', '')
end


function utils.normalize_action(action, action_type)
    --atcf('utils.normalize_action(%s, %s)', tostring(action), tostring(action_type))
    if istable(action) then return action end
    if action_type == nil then return nil end
    if isstr(action) then
        if tonumber(action) == nil then
            local naction = res[action_type]:with('en', action)
            if naction ~= nil then
                --atcf("res.%s[%s] found for %s", action_type, naction.id, action)
                return naction
            end
            --atcf("Searching resources for normalized name for %s [%s]", action, action_type)
            return res[action_type]:with('enn', utils.normalize_str(action))
        end
        action = tonumber(action) 
    end
    if isnum(action) then
        return res[action_type][action]
    end
    --atcf("Unable to normalize: '%s'[%s] (%s)", tostring(action), type(action), tostring(action_type))
    return nil
end


function utils.strip_roman_numerals(str)
    --return str:sub(1, str:find('I*V?X?I*V?I*$')):trim()
    return str:match('^%s*(.-)%s*I*V?X?I*V?I*$')
end


--[[
    Add an 'enn' (english, normalized) entry to each relevant resource
--]]
local function normalize_action_names()
    local categories = {'spells', 'job_abilities', 'weapon_skills', 'buffs'}
    for _,cat in pairs(categories) do
        for id,entry in pairs(res[cat]) do
            res[cat][id].enn = utils.normalize_str(entry.en)
            res[cat][id].ja = nil
            res[cat][id].jal = nil
        end
    end
end
normalize_action_names()


local txtbox_cmd_map = {
    moveinfo = 'moveInfo',          actioninfo = 'actionInfo',
    showq = 'actionQueue',          showqueue = 'actionQueue',
    queue = 'actionQueue',          monitored = 'montoredBox',
    showmonitored = 'montoredBox',
}

function processCommand(command,...)
    command = command and command:lower() or 'help'
    local args = map(windower.convert_auto_trans, {...})
    
    if S{'reload','unload'}:contains(command) then
        windower.send_command('lua %s %s':format(command, _addon.name))
    elseif command == 'refresh' then
        load_configs()
    elseif S{'start','on'}:contains(command) then
        hb.activate()
    elseif S{'stop','end','off'}:contains(command) then
        active = false
        printStatus()
    elseif S{'disable'}:contains(command) then
        if not validate(args, 1, 'Error: No argument specified for Disable') then return end
        disableCommand(args[1]:lower(), true)
    elseif S{'enable'}:contains(command) then
        if not validate(args, 1, 'Error: No argument specified for Enable') then return end 
        disableCommand(args[1]:lower(), false)
    elseif S{'assist','as'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (offense.assist.active and 'off' or 'resume')
        if S{'off','end','false','pause'}:contains(cmd) then
            offense.assist.active = false
            atc('Assist is now off.')
        elseif S{'resume'}:contains(cmd) then
            if (offense.assist.name ~= nil) then
                offense.assist.active = true
                atc('Now assisting '..offense.assist.name..'.')
            else
                atc(123,'Error: Unable to resume assist - no target set')
            end
        elseif S{'attack','engage'}:contains(cmd) then
            local cmd2 = args[2] and args[2]:lower() or (offense.assist.engage and 'off' or 'resume')
            if S{'off','end','false','pause'}:contains(cmd2) then
                offense.assist.engage = false
                atc('Will no longer enagage when assisting.')
            else
                offense.assist.engage = true
                atc('Will now enagage when assisting.')
            end
        else    --args[1] is guaranteed to have a value if this is reached
            offense.register_assistee(args[1])
        end
    elseif S{'ws','weaponskill'}:contains(command) then
        local lte,gte = string.char(0x81, 0x85),string.char(0x81, 0x86)
        local cmd = args[1] and args[1] or ''
        settings.ws = settings.ws or {}
        if (cmd == 'waitfor') then      --another player's TP
            local partner = utils.getPlayerName(args[2])
            if (partner ~= nil) then
                local partnertp = tonumber(args[3]) or 1000
                settings.ws.partner = {name=partner,tp=partnertp}
                atc("Will weaponskill when "..partner.."'s TP is "..gte.." "..partnertp)
            else
                atc(123,'Error: Invalid argument for ws waitfor: '..tostring(args[2]))
            end
        elseif (cmd == 'nopartner') then
            settings.ws.partner = nil
            atc('Weaponskill partner removed.')
        elseif (cmd == 'hp') then       --Target's HP
            local sign = S{'<','>'}:contains(args[2]) and args[2] or nil
            local hp = tonumber(args[3])
            if (sign ~= nil) and (hp ~= nil) then
                settings.ws.sign = sign
                settings.ws.hp = hp
                atc("Will weaponskill when the target's HP is "..sign.." "..hp.."%")
            else
                atc(123,'Error: Invalid arguments for ws hp: '..tostring(args[2])..', '..tostring(args[3]))
            end
        else
            if S{'use','set'}:contains(cmd) then    -- ws name
                table.remove(args, 1)
            end
            utils.register_ws(args)
        end
    elseif S{'spam','nuke'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (settings.nuke.active and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            settings.nuke.active = true
            if (settings.nuke.name ~= nil) then
                atc('Spell spamming is now on. Spell: '..settings.nuke.name)
            else
                atc('Spell spamming is now on. To set a spell to use: //hb spam use <spell>')
            end
        elseif S{'off','false'}:contains(cmd) then
            settings.nuke.active = false
            atc('Spell spamming is now off.')
        else
            if S{'use','set'}:contains(cmd) then
                table.remove(args, 1)
            end
            utils.register_spam_spell(args)
        end
    elseif S{'debuff', 'db'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (offense.debuffing_active and 'off' or 'on')
        if S{'on','true'}:contains(cmd) then
            offense.debuffing_active = true
            atc('Debuffing is now on.')
        elseif S{'off','false'}:contains(cmd) then
            offense.debuffing_active = false
            atc('Debuffing is now off.')
        elseif S{'rm','remove'}:contains(cmd) then
            utils.register_offensive_debuff(table.slice(args, 2), true)
        elseif S{'ls','list'}:contains(cmd) then
            pprint_tiered(offense.debuffs)
        else
            if S{'use','set'}:contains(cmd) then
                table.remove(args, 1)
            end
            utils.register_offensive_debuff(args, false)
        end
    elseif command == 'mincure' then
        if not validate(args, 1, 'Error: No argument specified for minCure') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 6) then
            settings.healing.min.cure = val
            atc('Minimum cure tier set to '..val)
        else
            atc('Error: Invalid argument specified for minCure')
        end
    elseif command == 'mincuraga' then
        if not validate(args, 1, 'Error: No argument specified for minCure') then return end
        local val = tonumber(args[1])
        if (val ~= nil) and (1 <= val) and (val <= 6) then
            settings.healing.min.curaga = val
            atc('Minimum curaga tier set to '..val)
        else
            atc('Error: Invalid argument specified for minCure')
        end
    elseif command == 'reset' then
        if not validate(args, 1, 'Error: No argument specified for reset') then return end
        local rcmd = args[1]:lower()
        local b,d = false,false
        if S{'all','both'}:contains(rcmd) then
            b,d = true,true
        elseif (rcmd == 'buffs') then
            b = true
        elseif (rcmd == 'debuffs') then
            d = true
        else
            atc('Error: Invalid argument specified for reset: '..arg[1])
            return
        end
        
        local resetTarget
        if (args[2] ~= nil) and (args[3] ~= nil) and (args[2]:lower() == 'on') then
            local pname = utils.getPlayerName(args[3])
            if (pname ~= nil) then
                resetTarget = pname
            else
                atc(123,'Error: Invalid name provided as a reset target: '..tostring(args[3]))
                return
            end
        end
        resetTarget = resetTarget or 'ALL' 
        local rtmsg = resetTarget or 'all monitored players'
        if b then
            buffs.resetBuffTimers(resetTarget)
            atc('Buff timers for %s were reset.':format(rtmsg))
        end
        if d then
            buffs.resetDebuffTimers(resetTarget)
            atc('Debuffs detected for %s were reset.':format(rtmsg))
        end
    elseif command == 'buff' then
        buffs.registerNewBuff(args, true)
    elseif S{'cancelbuff','nobuff'}:contains(command) then
        buffs.registerNewBuff(args, false)
    elseif S{'bufflist','bl'}:contains(command) then
        if not validate(args, 1, 'Error: No argument specified for BuffList') then return end
        utils.apply_bufflist(args)
    elseif command == 'bufflists' then
        pprint(hb_config.buff_lists)
    elseif command == 'ignore_debuff' then
        buffs.registerIgnoreDebuff(args, true)
    elseif command == 'unignore_debuff' then
        buffs.registerIgnoreDebuff(args, false)
    elseif S{'follow','f'}:contains(command) then
        local cmd = args[1] and args[1]:lower() or (settings.follow.active and 'off' or 'resume')
        if S{'off','end','false','pause'}:contains(cmd) then
            settings.follow.active = false
        elseif S{'distance', 'dist', 'd'}:contains(cmd) then
            local dist = tonumber(args[2])
            if (dist ~= nil) and (0 < dist) and (dist < 45) then
                settings.follow.distance = dist
                atc('Follow distance set to '..settings.follow.distance)
            else
                atc('Error: Invalid argument specified for follow distance')
            end
        elseif S{'resume'}:contains(cmd) then
            if (settings.follow.target ~= nil) then
                settings.follow.active = true
                atc('Now following '..settings.follow.target..'.')
            else
                atc(123,'Error: Unable to resume follow - no target set')
            end
        else    --args[1] is guaranteed to have a value if this is reached
            local pname = utils.getPlayerName(args[1])
            if (pname ~= nil) then
                settings.follow.target = pname
                settings.follow.active = true
                atc('Now following '..settings.follow.target..'.')
            else
                atc(123,'Error: Invalid name provided as a follow target: '..tostring(args[1]))
            end
        end
    elseif S{'ignore', 'unignore', 'watch', 'unwatch'}:contains(command) then
        monitorCommand(command, args[1])
    elseif command == 'ignoretrusts' then
        utils.toggleX(settings, 'ignoreTrusts', args[1], 'Ignoring of Trust NPCs', 'IgnoreTrusts')
    elseif command == 'packetinfo' then
        toggleMode('showPacketInfo', args[1], 'Packet info display', 'PacketInfo')
    elseif command == 'debug' then
        toggleMode('debug', args[1], 'Debug mode', 'debug mode')
    elseif txtbox_cmd_map[command] ~= nil then
        local boxName = txtbox_cmd_map[command]
        if utils.posCommand(boxName, args) then
            utils.refresh_textBoxes()
        else
            utils.toggleVisible(boxName, args[1])
        end
    elseif S{'help','--help'}:contains(command) then
        help_text()
    elseif command == 'settings' then
        for k,v in pairs(settings) do
            local kstr = tostring(k)
            local vstr = (type(v) == 'table') and tostring(T(v)) or tostring(v)
            atc(kstr:rpad(' ',15)..': '..vstr)
        end
    elseif command == 'status' then
        printStatus()
    elseif command == 'info' then
        if not _libs.lor.exec then
            atc(3,'Unable to parse info.  Windower/addons/libs/lor/lor_exec.lua was unable to be loaded.')
            atc(3,'If you would like to use this function, please visit https://github.com/lorand-ffxi/lor_libs to download it.')
            return
        end
        local cmd = args[1]     --Take the first element as the command
        table.remove(args, 1)   --Remove the first from the list of args
        _libs.lor.exec.process_input(cmd, args)
    else
        atc('Error: Unknown command')
    end
end


local function _get_player_id(player_name)
    local player_mob = windower.ffxi.get_mob_by_name(player_name)
    if player_mob then
        return player_mob.id
    end
    return nil
end
utils.get_player_id = _libs.lor.advutils.scached(_get_player_id)


function utils.register_offensive_debuff(args, cancel)
    local argstr = table.concat(args,' ')
    local spell_name = utils.formatSpellName(argstr)
    local spell = getActionFor(spell_name)
    if (spell ~= nil) then
        if Assert.can_use(spell) then
            offense.maintain_debuff(spell, cancel)
        else
            atc(123,'Error: Unable to cast '..spell.en)
        end
    else
        atc(123,'Error: Invalid spell name: '..spell_name)
    end
end


function utils.register_spam_spell(args)
    local argstr = table.concat(args,' ')
    local spell_name = utils.formatSpellName(argstr)
    local spell = getActionFor(spell_name)
    if (spell ~= nil) then
        if Assert.can_use(spell) then
            settings.nuke.name = spell.en
            atc('Will now spam '..settings.nuke.name)
        else
            atc(123,'Error: Unable to cast '..spell.en)
        end
    else
        atc(123,'Error: Invalid spell name: '..spell_name)
    end
end


function utils.register_ws(args)
    local argstr = table.concat(args,' ')
    local wsname = utils.formatSpellName(argstr)
    local ws = getActionFor(wsname)
    if (ws ~= nil) then
        settings.ws.name = wsname
        atc('Will now use '..wsname)
    else
        atc(123,'Error: Invalid weaponskill name: '..wsname)
    end
end


function utils.apply_bufflist(args)
    local mj = windower.ffxi.get_player().main_job
    local sj = windower.ffxi.get_player().sub_job
    local job = '%s/%s':format(mj, sj) 
    local bl_name = args[1]
    local bl_target = args[2]
    if bl_target == nil and bl_name == 'self' then
        bl_target = 'me'
    end
    local buff_list = table.get_nested_value(hb_config.buff_lists, {job, job:lower(), mj, mj:lower()}, bl_name)
    
    buff_list = buff_list or hb_config.buff_lists[bl_name]
    if buff_list ~= nil then
        for _,buff in pairs(buff_list) do
            buffs.registerNewBuff({bl_target, buff}, true)
        end
    else
        atc('Error: Invalid argument specified for BuffList: '..bl_name)
    end
end


function utils.posCommand(boxName, args)
    if (args[1] == nil) or (args[2] == nil) then return false end
    local cmd = args[1]:lower()
    if not S{'pos','posx','posy'}:contains(cmd) then
        return false
    end
    local x,y = tonumber(args[2]),tonumber(args[3])
    if (cmd == 'pos') then
        if (x == nil) or (y == nil) then return false end
        settings.textBoxes[boxName].x = x
        settings.textBoxes[boxName].y = y
    elseif (cmd == 'posx') then
        if (x == nil) then return false end
        settings.textBoxes[boxName].x = x
    elseif (cmd == 'posy') then
        if (y == nil) then return false end
        settings.textBoxes[boxName].y = y
    end
    return true
end

function utils.toggleVisible(boxName, cmd)
    cmd = cmd and cmd:lower() or (settings.textBoxes[boxName].visible and 'off' or 'on')
    if (cmd == 'on') then
        settings.textBoxes[boxName].visible = true
    elseif (cmd == 'off') then
        settings.textBoxes[boxName].visible = false
    else
        atc(123,'Invalid argument for changing text box settings: '..cmd)
    end
end

function utils.toggleX(tbl, field, cmd, msg, msgErr)
    if (tbl[field] == nil) then
        atcf(123, 'Error: Invalid mode to toggle: %s', field)
        return
    end
    cmd = cmd and cmd:lower() or (tbl[field] and 'off' or 'on')
    if (cmd == 'on') then
        tbl[field] = true
        atc(msg..' is now on.')
    elseif (cmd == 'off') then
        tbl[field] = false
        atc(msg..' is now off.')
    else
        atc(123,'Invalid argument for '..msgErr..': '..cmd)
    end
end

function toggleMode(mode, cmd, msg, msgErr)
    utils.toggleX(modes, mode, cmd, msg, msgErr)
    _libs.lor.debug = modes.debug
end

function disableCommand(cmd, disable)
    local msg = ' is now '..(disable and 'disabled.' or 're-enabled.')
    if S{'cure','cures','curing'}:contains(cmd) then
        if (not disable) then
            if (settings.maxCureTier == 0) then
                settings.disable.cure = true
                atc(123,'Error: Unable to enable curing because you have no Cure spells available.')
                return
            end
        end
        settings.disable.cure = disable
        atc('Curing'..msg)
    elseif S{'curaga'}:contains(cmd) then
        settings.disable.curaga = disable
        atc('Curaga use'..msg)
    elseif S{'na','heal_debuff','cure_debuff'}:contains(cmd) then
        settings.disable.na = disable
        atc('Removal of status effects'..msg)
    elseif S{'buff','buffs','buffing'}:contains(cmd) then
        settings.disable.buff = disable
        atc('Buffing'..msg)
    elseif S{'debuff','debuffs','debuffing'}:contains(cmd) then
        settings.disable.debuff = disable
        atc('Debuffing'..msg)
    elseif S{'nuke','nukes','nuking'}:contains(cmd) then
        settings.disable.nuke = disable
        atc('Nuking'..msg)
    elseif S{'ws','weaponskill','weaponskills','weaponskilling'}:contains(cmd) then
        settings.disable.ws = disable
        atc('Weaponskilling'..msg)
    else
        atc(123,'Error: Invalid argument for disable/enable: '..cmd)
    end
end

function monitorCommand(cmd, pname)
    if (pname == nil) then
        atc('Error: No argument specified for '..cmd)
        return
    end
    local name = utils.getPlayerName(pname)
    if cmd == 'ignore' then
        if (not ignoreList:contains(name)) then
            ignoreList:add(name)
            atc('Will now ignore '..name)
            if extraWatchList:contains(name) then
                extraWatchList:remove(name)
            end
        else
            atc('Error: Already ignoring '..name)
        end
    elseif cmd == 'unignore' then
        if (ignoreList:contains(name)) then
            ignoreList:remove(name)
            atc('Will no longer ignore '..name)
        else
            atc('Error: Was not ignoring '..name)
        end
    elseif cmd == 'watch' then
        if (not extraWatchList:contains(name)) then
            extraWatchList:add(name)
            atc('Will now watch '..name)
            if ignoreList:contains(name) then
                ignoreList:remove(name)
            end
        else
            atc('Error: Already watching '..name)
        end
    elseif cmd == 'unwatch' then
        if (extraWatchList:contains(name)) then
            extraWatchList:remove(name)
            atc('Will no longer watch '..name)
        else
            atc('Error: Was not watching '..name)
        end
    end
end

function validate(args, numArgs, message)
    for i = 1, numArgs do
        if (args[i] == nil) then
            atc(message..' ('..i..')')
            return false
        end
    end
    return true
end

function utils.getPlayerName(name)
    local trg = utils.getTarget(name)
    if (trg ~= nil) then
        return trg.name
    end
    return nil
end

function utils.getTarget(targ)
    if targ == nil then
        return nil
    elseif istable(targ) then
        return targ
    elseif tonumber(targ) and (tonumber(targ) > 255) then
        return windower.ffxi.get_mob_by_id(tonumber(targ))
    elseif S{'<me>','me'}:contains(targ) then
        return windower.ffxi.get_mob_by_target('me')
    elseif (targ == '<t>') then
        return windower.ffxi.get_mob_by_target()
    elseif isstr(targ) then
        local target = windower.ffxi.get_mob_by_name(targ)
        return target or windower.ffxi.get_mob_by_name(targ:ucfirst())
    end
    return nil
end

function getPartyMember(name)
    local party = windower.ffxi.get_party()
    for _,pmember in pairs(party) do
        if (type(pmember) == 'table') and (pmember.name == name) then
            return pmember
        end
    end
    return nil
end

function utils.getMainPartyList()
    local pt = windower.ffxi.get_party()
    local pty = {pt.p0,pt.p1,pt.p2,pt.p3,pt.p4,pt.p5}
    local party = S{}
    for _,pm in pairs(pty) do
        if (pm ~= nil) then
            party:add(pm.name)
        end
    end
    return party
end

--[[
    Returns the resource information for the given spell or ability name
--]]
function getActionFor(actionName)
    local spell = res.spells:with('en', actionName)
    local abil = res.job_abilities:with('en', actionName)
    local ws = res.weapon_skills:with('en', actionName)
    
    local found = spell or abil or ws or nil
    if found ~= nil then
        return found
    end
    
    local lower_name = actionName:lower()
    for _,ws in pairs(res.weapon_skills) do
        if ws.en:lower() == lower_name then
            return ws
        end
    end
    return nil
end

--==============================================================================
--          String Formatting Functions
--==============================================================================

function utils.formatSpellName(text)
    if (type(text) ~= 'string') or (#text < 1) then return nil end
    
    local fromAlias = hb_config.aliases[text]
    if (fromAlias ~= nil) then
        return fromAlias
    end
    
    local spell_from_lc = lc_spells[text:lower()]
    if spell_from_lc ~= nil then
        return spell_from_lc.en
    end
    
    local parts = text:split(' ')
    if #parts >= 2 then
        local name = formatName(parts[1])
        for p = 2, #parts do
            local part = parts[p]
            local tier = toRomanNumeral(part) or part:upper()
            if (roman2dec[tier] == nil) then
                name = name..' '..formatName(part)
            else
                name = name..' '..tier
            end
        end
        return name
    else
        local name = formatName(text)
        local tier = text:sub(-1)
        local rnTier = toRomanNumeral(tier)
        if (rnTier ~= nil) then
            return name:sub(1, #name-1)..' '..rnTier
        else
            return name
        end
    end
end


function formatName(text)
    if (text ~= nil) and (type(text) == 'string') then
        return text:lower():ucfirst()
    end
    return text
end

function toRomanNumeral(val)
    if type(val) ~= 'number' then
        if type(val) == 'string' then
            val = tonumber(val)
        else
            return nil
        end
    end
    return dec2roman[val]
end

--==============================================================================
--          Output Handling Functions
--==============================================================================

function printStatus()
    windower.add_to_chat(1, 'HealBot is now '..(active and 'active' or 'off')..'.')
end

--==============================================================================
--          Initialization Functions
--==============================================================================

function load_configs()
    local defaults = {
        textBoxes = {
            actionQueue={x=-125,y=300,font='Arial',size=10,visible=true},
            moveInfo={x=0,y=18,visible=false},
            actionInfo={x=0,y=0,visible=true},
            montoredBox={x=-150,y=600,font='Arial',size=10,visible=true}
        },
        nuke = {name='Stone'},
        healing = {min={cure=3,curaga=1,waltz=2,waltzga=1},curaga_min_targets=2},
        disable = {curaga=false},
        ignoreTrusts=true
    }
    local loaded = lor_settings.load('data/settings.lua', defaults)
    update_settings(loaded)
    utils.refresh_textBoxes()
    
    local cure_potency_defaults = {
        cure = {94,207,469,880,1110,1395},  curaga = {150,313,636,1125,1510},
        waltz = {157,325,581,887,1156},     waltzga = {160,521}
    }
    local buff_lists_defaults = {       self = {'Haste II','Refresh II'},
        whm = {self={'Haste','Refresh'}}, rdm = {self={'Haste II','Refresh II'}}
    }
    
    hb_config = {
        aliases = config.load('../shortcuts/data/aliases.xml'),
        mabil_debuffs = lor_settings.load('data/mabil_debuffs.lua'),
        buff_lists = lor_settings.load('data/buffLists.lua', buff_lists_defaults),
        priorities = lor_settings.load('data/priorities.lua'),
        cure_potency = lor_settings.load('data/cure_potency.lua', cure_potency_defaults)
    }
    hb_config.priorities.players =        hb_config.priorities.players or {}
    hb_config.priorities.jobs =           hb_config.priorities.jobs or {}
    hb_config.priorities.status_removal = hb_config.priorities.status_removal or {}
    hb_config.priorities.buffs =          hb_config.priorities.buffs or {}
    hb_config.priorities.debuffs =        hb_config.priorities.debuffs or {}
    hb_config.priorities.dispel =         hb_config.priorities.dispel or {}     --not implemented yet
    hb_config.priorities.default =        hb_config.priorities.default or 5
    
    --process_mabil_debuffs()
    local msg = configs_loaded and 'Rel' or 'L'
    configs_loaded = true
    atcc(262, msg..'oaded config files.')
end


function process_mabil_debuffs()
    local debuff_names = table.keys(hb_config.mabil_debuffs)
    for _,abil_raw in pairs(debuff_names) do
        local abil_fixed = abil_raw:gsub('_',' '):capitalize()
        hb_config.mabil_debuffs[abil_fixed] = S{}
        local debuffs = hb_config.mabil_debuffs[abil_raw]
        for _,debuff in pairs(debuffs) do
            hb_config.mabil_debuffs[abil_fixed]:add(debuff)
        end
        hb_config.mabil_debuffs[abil_raw] = nil
    end
    hb_config.mabil_debuffs:save()
end


function update_settings(loaded)
    settings = settings or {}
    for key,val in pairs(loaded) do
        if istable(val) then
            settings[key] = settings[key] or {}
            for skey,sval in pairs(val) do
                settings[key][skey] = sval
            end
        else
            settings[key] = settings[key] or val
        end
    end
    table.update_if_not_set(settings, {
        disable = {},
        follow = {delay = 0.08, distance = 3},
        healing = {minCure = 3, minCuraga = 1, minWaltz = 2, minWaltzga = 1},
        nuke = {}
    })
end

function utils.refresh_textBoxes()
    local boxes = {'actionQueue','moveInfo','actionInfo','montoredBox'}
    txts = txts or {}
    for _,box in pairs(boxes) do
        local bs = settings.textBoxes[box]
        local bst = {pos={x=bs.x, y=bs.y}}
        bst.flags = {right=(bs.x < 0), bottom=(bs.y < 0)}
        if (bs.font ~= nil) then
            bst.text = {font=bs.font}
        end
        if (bs.size ~= nil) then
            bst.text = bst.text or {}
            bst.text.size = bs.size
        end
        
        if (txts[box] ~= nil) then
            txts[box]:destroy()
        end
        txts[box] = texts.new(bst)
    end
end


--==============================================================================
--          Table Functions
--==============================================================================

function getPrintable(list, inverse)
    local qstring = ''
    for index,line in pairs(list) do
        local check = index
        local add = line
        if (inverse) then
            check = line
            add = index
        end
        if (tostring(check) ~= 'n') then
            if (#qstring > 1) then
                qstring = qstring..'\n'
            end
            qstring = qstring..add
        end
    end
    return qstring
end

--======================================================================================================================
--                      Misc.
--======================================================================================================================

function help_text()
    local t = '    '
    local ac,cc,dc = 262,263,1
    atcc(262,'HealBot Commands:')
    local cmds = {
        {'on | off','Activate / deactivate HealBot (does not affect follow)'},
        {'reload','Reload HealBot, resetting everything'},
        {'refresh','Reloads settings XMLs in addons/HealBot/data/'},
        {'fcmd','Sets a player to follow, the distance to maintain, or toggles being active with no argument'},
        {'buff <player> <spell>[, <spell>[, ...]]','Sets spell(s) to be maintained on the given player'},
        {'cancelbuff <player> <spell>[, <spell>[, ...]]','Un-sets spell(s) to be maintained on the given player'},
        {'blcmd','Sets the given list of spells to be maintained on the given player'},
        {'bufflists','Lists the currently configured spells/abilities in each bufflist'},
        {'spam [use <spell> | <bool>]','Sets the spell to be spammed on assist target\s enemy, or toggles being active (default: Stone, off)'},
        {'dbcmd','Add/remove debuff spell to maintain on assist target\'s enemy, toggle on/off, or list current debuffs to maintain'},
        {'mincure <number>','Sets the minimum cure spell tier to cast (default: 3)'},
        {'disable <action type>','Disables actions of a given type (cure, buff, na)'},
        {'enable <action type>','Re-enables actions of a given type (cure, buff, na) if they were disabled'},
        {'reset [buffs | debuffs | both [on <player>]]','Resets the list of buffs/debuffs that have been detected, optionally for a single player'},
        {'ignore_debuff <player/always> <debuff>','Ignores when the given debuff is cast on the given player or everyone'},
        {'unignore_debuff <player/always> <debuff>','Stops ignoring the given debuff for the given player or everyone'},
        {'ignore <player>','Ignores the given player/npc so they will not be healed'},
        {'unignore <player>','Stops ignoring the given player/npc (=/= watch)'},
        {'watch <player>','Monitors the given player/npc so they will be healed'},
        {'unwatch <player>','Stops monitoring the given player/npc (=/= ignore)'},
        {'ignoretrusts <on/off>','Toggles whether or not Trust NPCs should be ignored (default: on)'},
        {'ascmd','Sets a player to assist, toggles whether or not to engage, or toggles being active with no argument'},
        {'wscmd1','Sets the weaponskill to use'},
        {'wscmd2','Sets when weaponskills should be used according to whether the mob HP is < or > the given amount'},
        {'wscmd3','Sets a weaponskill partner to open skillchains for, and the TP that they should have'},
        {'wscmd4','Removes a weaponskill partner so weaponskills will be performed independently'},
        {'queue [pos <x> <y> | on | off]','Moves action queue, or toggles display with no argument (default: on)'},
        {'actioninfo [pos <x> <y> | on | off]','Moves character status info, or toggles display with no argument (default: on)'},
        {'moveinfo [pos <x> <y> | on | off]','Moves movement status info, or toggles display with no argument (default: off)'},
        {'monitored [pos <x> <y> | on | off]','Moves monitored player list, or toggles display with no argument (default: on)'},
        {'help','Displays this help text'}
    }
    local acmds = {
        ['fcmd']='f':colorize(ac,cc)..'ollow [<player> | dist <distance> | off | resume]',
        ['ascmd']='as':colorize(ac,cc)..'sist [<player> | attack | off | resume]',
        ['wscmd1']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill use <ws name>',
        ['wscmd2']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill hp <sign> <mob hp%>',
        ['wscmd3']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill waitfor <player> <tp>',
        ['wscmd4']='w':colorize(ac,cc)..'eapon'..'s':colorize(ac,cc)..'kill nopartner',
        ['dbcmd']='d':colorize(ac,cc)..'e'..'b':colorize(ac,cc)..'uff [(use | rm) <spell> | on | off | ls]',
        ['blcmd']='b':colorize(ac,cc)..'uff'..'l':colorize(ac,cc)..'ist <list name> (<player>)',
    }
    
    for _,tbl in pairs(cmds) do
        local cmd,desc = tbl[1],tbl[2]
        local txta = cmd
        if (acmds[cmd] ~= nil) then
            txta = acmds[cmd]
        else
            txta = txta:colorize(cc)
        end
        local txtb = desc:colorize(dc)
        atc(txta)
        atc(t..txtb)
    end
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