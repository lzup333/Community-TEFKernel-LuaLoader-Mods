-- 只统计本模组附加弹幕；不限制原版或其他模组弹幕。
local B={};B.__index=B
function B.new(r)return setmetatable({r=r,entries={},reserved=0},B)end
function B:clear()self.entries={};self.reserved=0 end
function B:active()
 local r=self.r;local arr=r:w('projectile','object',nil);local count=0
 for index,e in pairs(self.entries)do
  local p=arr and r.b.p.array_at(arr,index,'object')
  if not p or not r.b:get('Projectile','active',p,'bool',false)or r.b:get('Projectile','identity',p,'int32',-1)~=e.identity or r.b:get('Projectile','owner',p,'int32',-1)~=e.owner or r.b:get('Projectile','type',p,'int32',0)~=e.type then self.entries[index]=nil
  else count=count+1 end
 end
 return count
end
function B:reserve(wanted)
 local available=math.max(0,(self.r.cfg.globalEchoLimit or 24)-self:active()-self.reserved)
 local granted=math.min(wanted,available);self.reserved=self.reserved+granted
 return granted
end
function B:release(amount)self.reserved=math.max(0,self.reserved-amount)end
function B:track(index,p,typeId)
 self.entries[index]={type=typeId,identity=self.r.b:get('Projectile','identity',p,'int32',-1),owner=self.r.b:get('Projectile','owner',p,'int32',-1)}
end
return B
