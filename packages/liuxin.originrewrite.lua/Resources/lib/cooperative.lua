-- 每个已握手玩家独立契约；档案仍按世界ID+人物名保存于房主。
local M={};M.__index=M
function M.new(r)return setmetatable({r=r,players={}},M)end
function M:drop(index)
 local e=self.players[index];if e then e.contract:checkpoint(true);self.players[index]=nil end
end
function M:clear()for index in pairs(self.players)do self:drop(index)end end
function M:context(index,fn)
 local r=self.r;local old=r.playerOverride;local prior=r.contract;local priorProfile=r.profileOverride
 r.playerOverride=index
 local entry=self.players[index];if entry then r.contract=entry.contract;r.profileOverride=entry.identity end
 local ok,err=xpcall(fn,debug.traceback)
 r.playerOverride=old;r.contract=prior;r.profileOverride=priorProfile
 if not ok then r.log('COOP_ERROR','player='..index..' '..tostring(err))end
 return ok
end
function M:ensure(index)
 local r=self.r;local arr=r:w('player','object',nil)
 if not arr or index<0 or index>=r.b.p.array_length(arr)then return end
 local p=r.b.p.array_at(arr,index,'object');if not p or not r.b:get('Player','active',p,'bool',false)then return end
 local raw=r.b:get('Player','name',p,'object',nil);local name=raw and r.b.p.string_value(raw)
 if not name or #name==0 or #name>256 then return end
 local e=self.players[index]
 local peer=r.net and r.net.peers[index];local identity=peer and peer.profile
 if not e or e.name~=name or e.identity~=identity then
  if e then self:drop(index)end
  e={name=name,identity=identity,contract=require('contract').new(r)};e.contract.inputAvailable=true;self.players[index]=e
 end
 return e
end
function M:update()
 local r=self.r
 for i in pairs(self.players)do
  if not self:ensure(i)or not r.net.peers[i]then self:drop(i)
  else self:context(i,function()r.contract:update();r.net:contractStatus(i,r.contract)end)end
 end
 if r.archive and r.ticks%300==0 then r.archive:save()end
end
function M:environment()
 local r=self.r
 for i,e in pairs(self.players)do
  local label,notice=r.envLabel,r.envNotice
  r.envLabel=e.envLabel;r.envNotice=e.envNotice
  self:context(i,function()r:environment(nil,true)end)
  e.envLabel,e.envNotice=r.envLabel,r.envNotice;r.envLabel,r.envNotice=label,notice
 end
end
function M:command(index,text)
 if not self:ensure(index)then return end
 self:context(index,function()self.r.contract:command(text)end)
end
function M:kill(n,s)
 local r=self.r;local arr=r:w('player','object',nil);if not arr then return end
 local interactions=r:n(n,'playerInteraction','object',nil);local last=r:n(n,'lastInteraction','int32',-1)
 for i in pairs(self.players)do
  local credited=i==last or(interactions and i<r.b.p.array_length(interactions)and r.b.p.array_at(interactions,i,'bool')==true)
  if credited and self:ensure(i)then self:context(i,function()
   if r.archive then r.archive:bind();r.archive:kill(s)end
   self.r.contract:kill(s)
  end)end
 end
end
return M
