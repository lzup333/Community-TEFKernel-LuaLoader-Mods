local X={}
local A=require('actions')
function X.install(r)
 r.helpers={}
 r.npcSource=r.b:exact('NPC','GetSpawnSourceForNPCFromNPCAI',{},false)
 r.npcFactory=r.b:exact('NPC','NewNPC',{{'Terraria.DataStructures','IEntitySource'},'int32','int32','int32','int32','float','float','float','float','int32'},true)
 r.log('SPECIAL_ROUTE','teleport='..tostring(r.empty~=nil)..' summon='..tostring(r.npcFactory~=nil and r.npcSource~=nil))
end
function X.valid(r,slot,entry)
 local s=r.states[slot];local arr=r:w('npc','object',nil)
 local n=arr and r.b.p.array_at(arr,slot,'object')
 return s and s.generation==entry.generation and s.type==entry.type and n and r:n(n,'type','int32',0)==entry.type and n or nil
end
function X.owned(r,n)
 local slot=r:slot(n);local e=r.helpers and r.helpers[slot]
 return e and X.valid(r,slot,e)and r:sameSlot(n,slot)or false
end
function X.update(r)
 local now=r.lastTick or 0
 for slot,e in pairs(r.helpers or {})do
  local n=X.valid(r,slot,e);local parent=r.states[e.parent]
  local arr=r:w('npc','object',nil);local owner=arr and r.b.p.array_at(arr,e.parent,'object')
  if not n or not r:n(n,'active')or r:n(n,'life','int32',0)<=0 then r.helpers[slot]=nil
  elseif now>=e.untilTick or not parent or parent.generation~=e.parentGeneration or not owner or not r:n(owner,'active')or r:n(owner,'life','int32',0)<=0 then
   r.b:set('NPC','active',n,false,'bool');if r.net then r.net:syncNPC(n)end;r.helpers[slot]=nil
  end
 end
 for slot,s in pairs(r.states)do
  if s.ghosts and(now>=(s.ghostUntil or 0))then s.ghosts=nil;s.ghostUntil=nil end
  if s.contactUntil and now>=s.contactUntil then
   local arr=r:w('npc','object',nil);local n=arr and r.b.p.array_at(arr,slot,'object')
   if n and r:n(n,'type','int32',0)==s.type and r:n(n,'active')then r.b:set('NPC','damage',n,s.contactDamage,'int32');if r.net then r.net:publishNPC(n,s)end end
   s.contactUntil=nil;s.contactDamage=nil
  end
 end
end
function X.clear(r)
 for slot,e in pairs(r.helpers or {})do local n=X.valid(r,slot,e);if n then r.b:set('NPC','active',n,false,'bool');if r.net then r.net:syncNPC(n)end end end
 r.helpers={}
 for _,state in pairs(r.states)do state.ghosts=nil;state.ghostUntil=nil end
end
function X.destination(r,n,px,py,distance)
 local w=r:n(n,'width','int32',16);local h=r:n(n,'height','int32',16)
 for _,dx in ipairs({distance,-distance,distance+64,-distance-64})do
  for _,dy in ipairs({0,-32,32,-64,64})do
   local x=px+dx-w/2;local y=py+dy-h/2
   if A.clear(r,n,x,y,w,h)and(r:n(n,'noGravity','bool',false)or not A.clear(r,n,x,y+16,w,h))then return x,y end
  end
 end
end
function X.start(r,n,s)
 local p=r:player(n);if not p then return false,'no_player' end
 local px,py=r.b:vec('Player','position',p);if not px then return false,'player_position_missing' end
 px=px+r.b:get('Player','width',p,'int32',20)/2;py=py+r.b:get('Player','height',p,'int32',40)/2
 local x,y=r.b:vec('NPC','position',n)
 if not x or not y then return false,'npc_position_missing' end
 if s.action=='illusion'then
  if not r.heads or not r.heads.ghostAvailable then return false,'ghost_renderer_unavailable' end
  s.ghosts={};local w=r:n(n,'width','int32',16);local h=r:n(n,'height','int32',16)
  for _,dx in ipairs({-96,96})do if A.clear(r,n,x+dx,y,w,h)then s.ghosts[#s.ghosts+1]={x=x+dx,y=y}end end
  if #s.ghosts==0 then return false,'no_ghost_space' end
  s.ghostDrawLogged=false;s.ghostUntil=(r.lastTick or 0)+120
  r.log('ILLUSION_FIRE','slot='..r:slot(n)..' count='..#s.ghosts..' frames=120');return true
 elseif s.action=='blink'then
  local tx,ty=X.destination(r,n,px,py,192)
  if not tx then r.log('TELEPORT_CANCEL','no safe landing');return false,'no_safe_landing' end
  if not r.b:putvec('NPC','position',n,tx,ty)then return false,'position_write_failed' end
  r.b:putvec('NPC','velocity',n,0,0)
  s.contactDamage=s.contactDamage or r:n(n,'damage','int32',1)
  s.contactUntil=(r.lastTick or 0)+45
  r.b:set('NPC','damage',n,math.max(1,math.floor(s.contactDamage*.3)),'int32')
  if r.net then r.net:publishNPC(n,s)end
  r.log('TELEPORT_FIRE','slot='..r:slot(n)..' contact_frames=45 damage='..math.max(1,math.floor(s.contactDamage*.3)));return true
 elseif s.action=='summon'then
  if not(r.npcFactory and r.npcSource)then return false,'npc_factory_unavailable' end
  local count,own=0,0;for _,entry in pairs(r.helpers or {})do count=count+1;if entry.parent==r:slot(n)and entry.parentGeneration==s.generation then own=own+1 end end
  if count>=4 or own>=2 then return false,'helper_cap' end
  local source=r.b.p.invoke(r.npcSource,n);if not source then return false,'source_unavailable' end
  local wanted=math.min(s.tier==3 and 2 or 1,4-count,2-own);local created=0
  for i=1,wanted do
   -- Flying vanilla Demon Eyes avoid inherited boss AI and fragile terrain assumptions.
   local tx=x+(i==1 and -96 or 96);local ty=y-48
   if A.clear(r,n,tx,ty,30,30)then
    r.spawnDepth=r.spawnDepth+1
    local ok,index=pcall(r.b.p.invoke,r.npcFactory,source,math.floor(tx),math.floor(ty),2,0,0,0,0,0,r:n(n,'target','int32',0))
    r.spawnDepth=r.spawnDepth-1
    local arr=r:w('npc','object',nil);local child=ok and type(index)=='number'and index>=0 and index<r.b.p.array_length(arr)and r.b.p.array_at(arr,index,'object')
    if child and r:n(child,'type','int32',0)==2 and r:sameSlot(child,index)then
     if not r.states[index]then r.generation=r.generation+1;r.states[index]={generation=r.generation,type=2,rejected='helper'}end
     local state=r.states[index];state.tier=nil;state.rejected='helper'
     r.b:set('NPC','SpawnedFromStatue',child,true,'bool');r.b:set('NPC','value',child,0,'float')
     r.b:set('NPC','damage',child,math.max(1,math.min(r:n(child,'damage','int32',1),math.floor(r:n(n,'damage','int32',1)*.2))),'int32')
     r.helpers[index]={generation=state.generation,type=2,parent=r:slot(n),parentGeneration=s.generation,untilTick=(r.lastTick or 0)+900}
     if r.net then r.net:publishNPC(child,state)end
     created=created+1
    end
   end
  end
  r.log('SUMMON_FIRE','slot='..r:slot(n)..' count='..created..' lifetime=900');return created>0,created==0 and 'no_spawn_space_or_creation' or nil
 end
 return false
end
return X
