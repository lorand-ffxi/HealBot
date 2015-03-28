
local Player = {}

function Player.new(pname)
	local this = {}
	this.name = pname
	return setmetatable(this, {__index = Player})
end

function Player:set_job(mj,sj)
	this.main_job = mj
	this.sub_job = sj
end

function Player:mainjob()
	return this.main_job
end

function Player:subjob()
	return this.sub_job
end

function Player:add_buff(buffName, buffInfo)
	this.buffs = this.buffs or T{}
	this.buffs[buffName] = buffInfo
end

function Player:cancel_buff(buffName)
	this:add_buff(buffName, nil)
end

function Player:register_buff(buffName, gain)
	this.buffs = this.buffs or T{}
	if this.buffs[buffName] then
		if gain then
			this.buffs[buffName]['landed'] = os.clock()
		else
			this.buffs[buffName]['landed'] = nil
		end
	end
end

function Player:register_debuff(debuffName, gain)
	this.debuffs = this.debuffs or T{}
	if (debuffName == 'slow') then
		this:register_buff('Haste', false)
		this:register_buff('Flurry', false)
	end
	
	
	
	
	
	
end



return Player

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