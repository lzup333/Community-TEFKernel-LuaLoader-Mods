-- Owned projectile attribution only; retain primitive snapshots, never borrowed NPC handles.
local G={};G.__index=G
function G.new(r)return setmetatable({r=r,shots={},busy=false},G)end
function G:forget(index)if type(index)=='number'then self.shots[index]=nil end end
function G:register(index,n,s,typeId)
 local name=s.displayName
 if not name and self.r.nameGetter then
  local raw=self.r.b.p.invoke(self.r.nameGetter,n);if raw then name=self.r.b.p.string_value(raw)end
 end
 local arr=self.r:w('projectile','object',nil);local shot=arr and self.r.b.p.array_at(arr,index,'object')
 self.shots[index]={identity=shot and self.r.b:get('Projectile','identity',shot,'int32',-1),owner=shot and self.r.b:get('Projectile','owner',shot,'int32',-1),type=typeId,name=name or(require('core').names[s.tier or 1]..'·怪物#'..s.type),skill=s.headText,tick=self.r.lastTick or 0,world=self.r.world,session=self.r.session}
end
function G:resolve(reason)
 local r=self.r;if not reason or r:w('netMode','int32',-1)~=0 and r:w('netMode','int32',-1)~=1 then return end
 local slot=r.b:get('DeathReason','_sourceProjectileLocalIndex',reason,'int32',-1)
 local entry=self.shots[slot];if not entry or entry.world~=r.world or entry.session~=r.session then return end
 if (r.lastTick or 0)-entry.tick>240 then self.shots[slot]=nil;return end
 local arr=r:w('projectile','object',nil);local shot=arr and r.b.p.array_at(arr,slot,'object')
 if not shot or r.b:get('Projectile','type',shot,'int32',-1)~=entry.type then self.shots[slot]=nil;return end
 if entry.identity~=nil and(r.b:get('Projectile','identity',shot,'int32',-1)~=entry.identity or r.b:get('Projectile','owner',shot,'int32',-1)~=entry.owner)then self.shots[slot]=nil;return end
 return entry
end
function G:clear()
 local r=self.r;local arr=r:w('projectile','object',nil)
 if arr and r:authority()then
  for index,entry in pairs(self.shots)do
   local shot=r.b.p.array_at(arr,index,'object')
   if shot and entry.world==r.world and entry.session==r.session and r.b:get('Projectile','active',shot,'bool',false)and r.b:get('Projectile','type',shot,'int32',0)==entry.type and r.b:get('Projectile','identity',shot,'int32',-1)==entry.identity and r.b:get('Projectile','owner',shot,'int32',-1)==entry.owner then
    r.b:set('Projectile','active',shot,false,'bool')
    if r.net then r.net:native(29,entry.identity,nil,entry.owner)end
   end
  end
 end
 self.shots={}
end
function G:label(player,reason,entry,death)
 if not self.r.cfg.correctDeathSource then return end
 local name=self.r.b:get('Player','name',player,'object',nil)
 name=name and self.r.b.p.string_value(name)or'玩家'
 local message=name..'被'..entry.name..'击败了。'
 self.r.b:set('DeathReason','_sourceCustomReason',reason,self.r.b.p.string_create(message),'object')
 if death then self.r.log('DEATH_SOURCE','attacker='..entry.name..' skill='..tostring(entry.skill))end
end
function G:limit(player,damage)
 local max=self.r.b:get('Player','statLifeMax2',player,'int32',0)
 if max<=0 or not self.r.cfg.echoHitProtection then return damage end
 return math.min(damage,math.max(1,math.floor(max*(not self.r:w('hardMode','bool',false)and require('difficulty').get(self.r.cfg).earlyHitCap or require('difficulty').get(self.r.cfg).hitCap)/100)))
end
function G.install(r)
 local b=r.b;b.types.DeathReason=b.p.get_type('Terraria.DataStructures','PlayerDeathReason')
 local g=G.new(r);r.shotGuard=g
 local defaults=b:exact('Projectile','SetDefaults',{'int32'},false)
 if defaults then b:hook(defaults,function(shot)
  local slot=b:get('Projectile','whoAmI',shot,'int32',-1);local arr=r:w('projectile','object',nil)
  if slot>=0 and arr and b.p.array_at(arr,slot,'object')==shot then g:forget(slot)end
 end,true)end
 local hurt=b:exact('Player','Hurt',{{'Terraria.DataStructures','PlayerDeathReason'},'int32','int32','bool','bool','bool','int32','bool'},false)
 if hurt then
  local hook=b.p.install_hook(hurt,{prefix=function(player,args)
   if g.busy then return false end
   local entry=g:resolve(args[1]);if not entry then return false end
   g:label(player,args[1],entry)
   local damage=g:limit(player,args[2]);if damage==args[2]then return false end
   local copy={};for i=1,8 do copy[i]=args[i]end;copy[2]=damage
   g.busy=true;local ok,result=pcall(b.p.invoke,hurt,player,table.unpack(copy,1,8));g.busy=false
   if not ok or type(result)~='number' then r.log('HIT_GUARD_FAILED',tostring(result));return false end
   r.log('HIT_GUARD','incoming='..args[2]..' limited='..damage..' attacker='..entry.name)
   return true,result
  end})
  if hook then b.hooks[#b.hooks+1]=hook end
 end
 local observed=0
 if hurt then
  local stack={}
  local watch=b.p.install_hook(hurt,{prefix=function(player)stack[#stack+1]=b:get('Player','statLife',player,'int32',nil)or false;return false end,postfix=function(player)
   local before=table.remove(stack);local after=b:get('Player','statLife',player,'int32',nil)
   if before and after and after<before then
    local index=b:get('Player','whoAmI',player,'int32',-1)
    if r:w('netMode','int32',-1)==1 and index==r:w('myPlayer','int32',-1)and r.net and r.net.connected and r.net.contractView and r.net.contractView.status=='active'and r.net.contractView.kind=='nohit'and r.lastHurtReport~=r.lastTick then r.lastHurtReport=r.lastTick;r.net:request('ORW2:hurt')
    elseif r:w('netMode','int32',-1)==2 and r.coop and r.coop.players[index]then r.coop:context(index,function()r.contract:onHurt()end)
    elseif r:w('netMode','int32',-1)==0 and r.contract then r.contract:onHurt()end
   end
  end})
  if watch then b.hooks[#b.hooks+1]=watch;observed=1 end
 end
 r.hurtObserved=observed==1
 local kill=b:exact('Player','KillMe',{{'Terraria.DataStructures','PlayerDeathReason'},'double','int32','bool'},false)
 if kill then b:hook(kill,function(player,args)local entry=g:resolve(args[1]);if entry then g:label(player,args[1],entry,true)end end,true)end
 r.log('SHOT_GUARD_ROUTE','hurt='..tostring(hurt~=nil)..' death='..tostring(kill~=nil))
 return g
end
return G
