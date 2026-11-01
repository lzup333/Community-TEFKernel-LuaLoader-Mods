-- 原版聊天网络模块承载有界控制消息；客户端消费隐藏协议，战斗只在服务端运行。
local C=require('netcodec')
local N={};N.__index=N
function N.new(r)return setmetatable({r=r,ready=false,inbox={},peers={},pending={},sent={},sequence=0,serial=0,rate={}},N)end
function N:queue(kind,body,index)
 if #self.inbox>=256 then self.r.log('NET_QUEUE_FULL','dropped control message');return end
 self.inbox[#self.inbox+1]={kind=kind,body=body,index=index,world=self.r:w('worldID','int32',nil)}
end
function N:reset()
 self.r.cfg.remoteDifficulty=nil
 self.serial=self.serial+1;self.inbox={};self.peers={};self.pending={};self.sent={};self.rate={};self.sequence=0;self.connected=false;self.epoch=nil;self.lastSequence=0;self.lastHello=nil;self.lastReceive=nil;self.archiveView=nil;self.contractView=nil;self.contractOffers=nil;self.contractSelected=nil;self.warned=false;self.shots={};self.tombstones={}
 self.nonce=tostring(self.serial)..'_'..tostring(self.r.session)..'_'..tostring(self.r.world or 0)
 if self.r:w('netMode','int32',-1)==2 then self.epoch=tostring(self.r.world)..'_'..self.serial..'_'..tostring(self.r.lastTick or 0)end
 if self.r.coop then self.r.coop:clear()end
end
function N:literal(text)return self.r.b.p.invoke(self.fromLiteral,self.r.b.p.string_create(text))end
function N:fail(reason)
 if self.failing then return false end;self.failing=true
 local r=self.r
 if self.ready and r:w('netMode','int32',-1)==2 then pcall(r.restoreAll,r)end
 self.ready=false;self.connected=false;r.states={};r.helpers={}
 r.log('NET_RUNTIME_DISABLED',tostring(reason)..'; multiplayer changes rolled back')
 self.failing=false;return false
end
function N:chat(text,index,rgb)
 local r=self.r;if not self.ready or r:w('netMode','int32',-1)~=2 then return false end
 local ok,result=pcall(function()
  local p=r.b.p;local nt=self:literal(text);if not nt then return false end
  rgb=rgb or {210,230,255}
  local color=p.struct_arg({'uint32'},{self.colorABGR and(255+rgb[3]*256+rgb[2]*65536+rgb[1]*16777216)or(rgb[1]+rgb[2]*256+rgb[3]*65536+255*16777216)})
  return p.invoke_value_args(index~=nil and self.targetChat or self.broadcast,{nt,color,index or -1})
 end)
 if not ok or result==false then return self:fail('chat: '..tostring(result))end
 return true
end
function N:notify(text,index,rgb,key)
 rgb=rgb or {210,230,255}
 local body=table.concat({C.hex(text),rgb[1],rgb[2],rgb[3],C.hex(key or '')},',')
 return self:send('N',body,index)
end
function N:clearRemote()
 local r=self.r;local arr=r:w('npc','object',nil)
 for slot,s in pairs(r.states)do
  local n=arr and r.b.p.array_at(arr,slot,'object')
  if s.remote and s.base and n and r:n(n,'active')and r:n(n,'type','int32',0)==s.type then
   for _,f in ipairs({{'lifeMax','max','int32'},{'damage','damage','int32'},{'defense','defense','int32'},{'scale','scale','float'},{'knockBackResist','knock','float'}})do r.b:set('NPC',f[1],n,s.base[f[2]],f[3])end
   r.b:set('NPC','alpha',n,s.baseAlpha or 0,'int32')
   if r.nameSetter then r.b.p.invoke(r.nameSetter,n,r.b.p.string_create(s.baseName or ''))end
  end
 end
 r.states={};self.pending={};self.shots={};self.tombstones={}
 if r.shotGuard then r.shotGuard.shots={}end
end
function N:send(kind,body,index)
 self.sequence=self.sequence+1
 local raw=C.pack(self.r.world,self.epoch,self.sequence,kind,body)
 if not raw then self.r.log('NET_OVERSIZE',kind);return false end
 if index~=nil then return self:chat(raw,index)end
 local ok=true;for peer in pairs(self.peers)do if not self:chat(raw,peer)then ok=false end end;return ok
end
function N:native(kind,index,target,number2)
 if self.r:w('netMode','int32',-1)~=2 or not self.ready or self.failing then return false end
 local ok,result=pcall(self.r.b.p.invoke,self.sendData,kind,target or -1,-1,nil,index,number2 or 0,0,0,0,0,0)
 if not ok or result==false then return self:fail('SendData: '..tostring(result))end
 return true
end
function N:syncNPC(n)
 if self.r:w('netMode','int32',-1)~=2 or not self.ready then return end
 self.r.b:set('NPC','netUpdate',n,true,'bool')
 return self:native(23,self.r:slot(n))
end
function N:snapshot(slot,s,n)
 local r=self.r;local ghost=s.ghosts or {}
 local v={slot=slot,type=s.type,generation=s.generation,tier=s.tier or 0,stage=s.stage or 1,
 max=r:n(n,'lifeMax','int32',1),damage=r:n(n,'damage','int32',0),defense=r:n(n,'defense','int32',0),
 scale=r:n(n,'scale','float',1),knock=r:n(n,'knockBackResist','float',0),alpha=r:n(n,'alpha','int32',0),
 headText=s.headText,skillSummary=s.skillSummary,displayName=s.displayName,style=s.style,phase=s.phase,action=s.action,pattern=s.pattern,
 guardCounter=s.guardCounter and 1 or 0,echoWarning=s.echoWarning and 1 or 0,breakable=s.breakable and 1 or 0,helper=s.rejected=='helper'and 1 or 0,
 ghostLeft=math.max(0,math.min(120,(s.ghostUntil or 0)-(r.lastTick or 0))),
 g1x=ghost[1]and math.floor(ghost[1].x)or 0,g1y=ghost[1]and math.floor(ghost[1].y)or 0,
 g2x=ghost[2]and math.floor(ghost[2].x)or 0,g2y=ghost[2]and math.floor(ghost[2].y)or 0}
 return C.encode(v)
end
function N:flushNPCs(target,force)
 local r=self.r;local arr=r:w('npc','object',nil);if not arr then return end
 local alive={}
 for slot,s in pairs(r.states)do
  if s.tier or s.rejected=='helper'then
   local n=r.b.p.array_at(arr,slot,'object')
   if n and r:n(n,'active')and r:n(n,'life','int32',0)>0 and r:n(n,'type','int32',0)==s.type then
    alive[slot]=true;local body=self:snapshot(slot,s,n)
    if body and(force or body~=self.sent[slot])then
     self:syncNPC(n)
     if self:send('S',body,target)and not target then self.sent[slot]=body end
    end
   end
  end
 end
 if not target then
  for slot,body in pairs(self.sent)do if not alive[slot]then
   local old=C.decode(body);self:send('D',slot..','..(old and old.generation or 0));self.sent[slot]=nil
  end end
 end
end
function N:apply(n,v)
 local r=self.r
 if not n or not r:n(n,'active')or r:n(n,'life','int32',0)<=0 or r:n(n,'type','int32',0)~=v.type then return false end
 local old=r.states[v.slot]
 if old and old.remote and old.generation>v.generation then return false end
 local s=old and old.remote and old.generation==v.generation and old or {remote=true,type=v.type,generation=v.generation}
 if not s.base then
  s.base=r:base(n);s.baseAlpha=r:n(n,'alpha','int32',0)
  local name=r.b:get('NPC','_givenName',n,'object',nil);s.baseName=name and r.b.p.string_value(name)or nil
 end
 s.tier=v.tier>0 and v.tier or nil;s.stage=v.stage
 for _,key in ipairs({'headText','skillSummary','displayName','style','phase','action','pattern'})do s[key]=v[key]~=''and v[key]or nil end
 s.guardCounter=v.guardCounter==1;s.echoWarning=v.echoWarning==1;s.breakable=v.breakable==1;s.renamed=s.displayName~=nil
 s.stats={max=v.max,damage=v.damage,defense=v.defense,scale=v.scale,knock=v.knock};s.remoteAlpha=v.alpha
 s.ghosts=nil
 if v.ghostLeft>0 then
  s.ghosts={};if v.g1x~=0 or v.g1y~=0 then s.ghosts[#s.ghosts+1]={x=v.g1x,y=v.g1y}end
  if v.g2x~=0 or v.g2y~=0 then s.ghosts[#s.ghosts+1]={x=v.g2x,y=v.g2y}end
  s.ghostUntil=(r.lastTick or 0)+v.ghostLeft
 end
 if v.helper==1 then s.rejected='helper' end
 r.states[v.slot]=s;self:applyStats(n,s)
 if s.displayName and r.nameSetter then r.b.p.invoke(r.nameSetter,n,r.b.p.string_create(s.displayName))end
 return true
end
function N:applyStats(n,s)
 if not s or not s.remote or not s.stats then return end
 local b=self.r.b
 for _,f in ipairs({{'lifeMax','max','int32'},{'damage','damage','int32'},{'defense','defense','int32'},{'scale','scale','float'},{'knockBackResist','knock','float'}})do b:set('NPC',f[1],n,s.stats[f[2]],f[3])end
 b:set('NPC','alpha',n,s.remoteAlpha or 0,'int32')
end
function N:shot(index,n,s,typeId,target)
 local r=self.r;if r:w('netMode','int32',-1)~=2 or not self.ready then return end
 local arr=r:w('projectile','object',nil);local shot=arr and r.b.p.array_at(arr,index,'object');if not shot then return end
 r.b:set('Projectile','netUpdate',shot,true,'bool');self:native(27,index,target)
 local entry=r.shotGuard and r.shotGuard.shots[index]
 local name=s and(s.displayName or require('core').names[s.tier]..'·怪物#'..s.type)or entry and entry.name or '重构体'
 local skill=s and s.headText or entry and entry.skill or ''
 local body=table.concat({r.b:get('Projectile','identity',shot,'int32',-1),r.b:get('Projectile','owner',shot,'int32',255),typeId,
 r.b:get('Projectile','damage',shot,'int32',0),C.hex(name),C.hex(skill)},',')
 self:send('P',body,target)
end
function N:flushShots(target)
 local r=self.r;local arr=r:w('projectile','object',nil);if not arr or not r.shotGuard then return end
 for index,entry in pairs(r.shotGuard.shots)do
  local p=r.b.p.array_at(arr,index,'object')
  if entry.world==r.world and entry.session==r.session and p and r.b:get('Projectile','active',p,'bool',false)and r.b:get('Projectile','type',p,'int32',0)==entry.type and r.b:get('Projectile','identity',p,'int32',-1)==entry.identity then self:shot(index,nil,nil,entry.type,target)end
 end
end
function N:publishNPC(n,s)
 if self.r:w('netMode','int32',-1)~=2 or not self.ready then return end
 local slot=self.r:slot(n);local body=self:snapshot(slot,s,n)
 if body then self:syncNPC(n);if self:send('S',body)then self.sent[slot]=body end end
end
function N:receive(raw)
 local r=self.r;local w,e,q,k,body=C.unpack(raw)
 if not w or w~=r.world then return end
 if k=='W'then
  local version,nonce,difficulty=body:match('^([^,]+),([^,]+),([%a]+)$')
  if version~=C.version or nonce~=self.nonce or not require('difficulty').valid(difficulty) then return end
  r.cfg.remoteDifficulty=difficulty
  local first=not self.connected or self.epoch~=e
  if self.epoch~=e then self:clearRemote();self.lastSequence=0 end
  self.epoch=e;self.connected=true;if first then r.log('NET_CONNECTED','world='..w..' protocol='..version)end
 end
 if not self.connected or self.epoch~=e or q<=self.lastSequence then return end;self.lastSequence=q;self.lastReceive=r.ticks
 if k=='N'then
  local text,red,green,blue,key=body:match('^([0-9a-f]*),(%d+),(%d+),(%d+),([0-9a-f]*)$')
  text,key=C.unhex(text,1800),C.unhex(key,128);red,green,blue=tonumber(red),tonumber(green),tonumber(blue)
  if not text or not key or not red or red>255 or green>255 or blue>255 or not r.chat or not r.cfg.notices then return end
  if key:match('^boss:')and not r.cfg.bossDialog or key=='environment'and not r.cfg.environmentNotices or key:match('^skill:')and not r.cfg.skillNotices then return end
  if r.cfg.taskDisplay=='gui'and require('notices').task(key)then return end
  local str=r.b.p.string_create(text)
  if r.chatArgs==5 then r.b.p.invoke(r.chat,str,red,green,blue,true)else r.b.p.invoke(r.chat,str,red,green,blue)end
 elseif k=='S'then
  local v=C.decode(body);if not v then r.log('NET_BAD_STATE','rejected');return end
  if v.generation<=(self.tombstones[v.slot]or 0)then return end
  local old=self.pending[v.slot];if not old or old.v.generation<=v.generation then self.pending[v.slot]={v=v,untilTick=r.ticks+300}end
 elseif k=='D'then
  local slot,generation=body:match('^(%d+),(%d+)$');slot,generation=tonumber(slot),tonumber(generation)
  if not slot or slot>199 or not generation then return end
  self.tombstones[slot]=math.max(self.tombstones[slot]or 0,generation)
  local s=r.states[slot];if s and s.remote and s.generation<=generation then r.states[slot]=nil end
  local p=self.pending[slot];if p and p.v.generation<=generation then self.pending[slot]=nil end
 elseif k=='P'then
  local id,owner,kind,damage,name,skill=body:match('^(%d+),(%d+),(%d+),(%d+),([0-9a-f]*),([0-9a-f]*)$')
  id,owner,kind,damage=tonumber(id),tonumber(owner),tonumber(kind),tonumber(damage)
  name,skill=C.unhex(name,768),C.unhex(skill,512)
  if not id or id>2147483647 or not owner or owner>255 or not kind or kind>2000 or not damage or damage>10000000 or not name or not skill then return end
  local key=owner..':'..id;local size=0;for _ in pairs(self.shots)do size=size+1 end
  if size<128 or self.shots[key]then self.shots[key]={id=id,owner=owner,type=kind,damage=damage,name=name,skill=skill,untilTick=r.ticks+240}end
 elseif k=='R'then
  local ticket,owner,data=body:match('^([0-9a-f]+_%d+),([0-9a-f]+),([0-9a-f]+)$')
  data=C.unhex(data,1800)
  local rewards=data and require('statefile').decode(data)
  if not ticket or #ticket>64 or not owner or #owner~=32 or type(rewards)~='table'or #rewards<1 or #rewards>8 then return end
  local ok,status=pcall(function()return r.inventoryReward and r.inventoryReward:apply(ticket,owner,rewards)or'unavailable'end)
  if not ok then r.log('PRIVATE_REWARD_ERROR',tostring(status));status='review'end
  self:request('ORW2:receipt:'..ticket..':'..status)
 elseif k=='U'then
  local index,data=body:match('^([0-3]),([0-9a-f]+)$');index=tonumber(index)
  data=C.unhex(data,1800);local offer=data and require('statefile').decode(data)
  if not index or not require('contract').offerValid(offer)then return end
  if index==0 then self.contractSelected=offer;if self.contractView then self.contractView.selected=offer end
  else self.contractOffers=self.contractOffers or{};self.contractOffers[index]=offer;if self.contractView then self.contractView.offers=self.contractOffers end end
 elseif k=='T'then
  local status,count,goal,seconds,pending,kind,target,reward=body:match('^(%a+),(%d+),(%d+),(%d+),(%d+),(%a*),([0-9a-f]*),([0-9a-f]*)$')
  target,reward=C.unhex(target,512),C.unhex(reward,768);count,goal,seconds,pending=tonumber(count),tonumber(goal),tonumber(seconds),tonumber(pending)
  if status and target and reward and count<=1000000 and goal<=1000000 and seconds<=86400 and pending<=512 and({['']=true,any=true,tier=true,styles=true,nohit=true,extreme=true})[kind]and({idle=true,offered=true,active=true,waiting=true,failed=true})[status]then self.contractView={status=status,count=count,goal=goal,seconds=seconds,pending=pending,kind=kind,target=target,reward=reward,offers=self.contractOffers,selected=self.contractSelected}end
 elseif k=='A'then
  local a,b,c,d=body:match('^(%d+),(%d+),(%d+),(%d+)$')
  if a then self.archiveView={tonumber(a),tonumber(b),tonumber(c),tonumber(d)}end
 elseif k=='X'then self.connected=false;self:clearRemote();r.log('NET_HOST_UNLOAD','remote state cleared')end
end
function N:request(text)
 if not self.ready or self.r:w('netMode','int32',-1)~=1 then return false end
 local msg=self.r.b.p.invoke(self.createMessage,self.processor,self.r.b.p.string_create(text))
 if not msg or msg==false then return false end
 return self.r.b.p.invoke(self.clientChat,msg)~=false
end
function N:inventorySync(slot)
 if not self.ready or self.r:w('netMode','int32',-1)~=1 then return false end
 local r=self.r;return r.b.p.invoke(self.sendData,5,-1,-1,nil,r:w('myPlayer','int32',-1),slot,0,0,0,0,0)~=false
end
function N:clientUpdate()
 local r=self.r
 if self.connected and self.lastReceive and r.ticks-self.lastReceive>900 then self.connected=false;self:clearRemote();r.log('NET_TIMEOUT','awaiting server handshake')end
 if not self.lastHello or r.ticks-self.lastHello>=(self.connected and 600 or 180)then
  self.lastHello=r.ticks
  local profile=r.identity and r.identity:localToken()
  if profile then self:request('ORW2:hello:'..C.version..':'..self.nonce..':'..profile)
  elseif not r.identity then self:request('ORW2:hello:'..C.version..':'..self.nonce..':'..string.rep('a',32))
  else r.log('NET_PROFILE_WAIT','stable identity not saved')end
  if r.ticks>=600 and not self.warned then self.warned=true;r.log('NET_WAITING','server mod/route missing; client remains read-only')end
 end
 local arr=r:w('npc','object',nil)
 for slot,entry in pairs(self.pending)do
  local n=arr and r.b.p.array_at(arr,slot,'object')
  if self:apply(n,entry.v)or r.ticks>entry.untilTick then self.pending[slot]=nil end
 end
 local shots=r:w('projectile','object',nil)
 if shots then
  for key,entry in pairs(self.shots)do
   if r.ticks>entry.untilTick then self.shots[key]=nil
   else
    local from=entry.slot or 0;local to=entry.slot or math.min(999,r.b.p.array_length(shots)-1)
    if entry.slot or r.ticks%6==0 then
    local found=false
    for i=from,to do
     local p=r.b.p.array_at(shots,i,'object')
     if p and r.b:get('Projectile','active',p,'bool',false)and r.b:get('Projectile','identity',p,'int32',-1)==entry.id and r.b:get('Projectile','owner',p,'int32',-1)==entry.owner and r.b:get('Projectile','type',p,'int32',0)==entry.type then
      r.b:set('Projectile','friendly',p,false,'bool');r.b:set('Projectile','hostile',p,true,'bool');r.b:set('Projectile','damage',p,entry.damage,'int32');r.b:set('Projectile','tileCollide',p,true,'bool');r.b:set('Projectile','penetrate',p,1,'int32')
      found=true;entry.slot=i
      if r.shotGuard then r.shotGuard.shots[i]={identity=entry.id,owner=entry.owner,type=entry.type,name=entry.name,skill=entry.skill,tick=r.lastTick or 0,world=r.world,session=r.session}end
      break
     end
    end
    if not found then entry.slot=nil end
    end
   end
  end
 end
end
function N:contractStatus(index,q)
 local o=q.selected;local pending=0;local owner=q.key
 if self.r.store and owner then for _,row in pairs(self.r.store.data.mail)do if row.owner==owner and row.state~='claimed'then pending=pending+1 end end end
 local body=table.concat({q.status,q.count or 0,q.goal or 0,math.max(0,math.ceil((q.remaining or 0)/60)),pending,o and o.kind or '',C.hex(o and o.target or ''),C.hex(o and o.rewardText or '')},',')
 local signature=q.status..':'..(q.count or 0)..':'..(q.goal or 0)..':'..pending
 if q.netSignature~=signature or self.r.ticks%180==0 then
  if self:send('T',body,index)then q.netSignature=signature end
  -- Send bounded individual offers so GUI mode needs no duplicate chat board.
  local function sendOffer(slot,offer)
   if not offer then return end
   local encoded=require('statefile').encode(offer)
   if encoded and #encoded<=1800 then self:send('U',slot..','..C.hex(encoded),index)end
  end
  if q.status=='offered'then for i,offer in ipairs(q.offers or{})do sendOffer(i,offer)end
  elseif q.status=='active'then sendOffer(0,q.selected)end
 end
end
function N:handle(index,text)
 local r=self.r;local arr=r:w('player','object',nil)
 if type(index)~='number'or index<0 or not arr or index>=r.b.p.array_length(arr)then return end
 local p=r.b.p.array_at(arr,index,'object');if not p or not r.b:get('Player','active',p,'bool',false)then return end
 local now=r.ticks;local rate=self.rate[index]or {tick=now,count=0};self.rate[index]=rate
 if now-rate.tick>=60 then rate.tick=now;rate.count=0 end;rate.count=rate.count+1;if rate.count>4 then return end
 if text:match('^%s*/任务%s*$')then text='/or status'elseif text:match('^%s*/同步%s*$')then text='/or sync'end
 local cmd=text:match('^ORW2:command:([123])$');if cmd then text='/'..cmd end
 local control=text:match('^ORW2:control:(%a+)$');if control then text='/or '..control end
 local version,nonce,profile=text:match('^ORW2:hello:([^:]+):([%w_-]+):([0-9a-f]+)$')
 if version then
  if version~=C.version or #nonce>64 or #profile~=32 then self:chat('【起源重构】联机版本不一致，请全员安装 '..C.version,index,{255,150,130});return end
  local raw=r.b:get('Player','name',p,'object',nil);local name=raw and r.b.p.string_value(raw)
  if not name then return end
  for other,peer in pairs(self.peers)do if other~=index and peer.profile==profile then self:chat('【起源重构】同一人物标识已在线；请使用独立人物记录',index,{255,180,130});return end end
  local previous=self.peers[index]
  local fresh=not previous or previous.nonce~=nonce or previous.name~=name or previous.profile~=profile
  if fresh then r.coop:drop(index)end
  self.peers[index]={name=name,nonce=nonce,profile=profile};r.coop:ensure(index)
  if not self:send('W',C.version..','..nonce..','..r.cfg.difficulty,index)then return end
  if not fresh then return end
  self:flushNPCs(index,true);self:flushShots(index)
  r.coop:context(index,function()
   if r.archive then local row=r.archive:bind();if row then self:send('A',table.concat(row,','),index)end end
   local q=r.contract
   if q.status=='idle'then q:update()elseif not previous or previous.nonce~=nonce then q:show()end
  end)
  r.log('NET_JOIN','player='..index..' version='..version)
 elseif self.peers[index]then
  local ticket,status=text:match('^ORW2:receipt:([0-9a-f]+_%d+):(%a+)$')
  if ticket and #ticket<=64 then r.coop:context(index,function()if r.mail then r.mail:ack(ticket,status,r.identity:key())end end);return end
  if text=='ORW2:hurt'then r.coop:context(index,function()r.contract:onHurt()end);return end
  if text=='ORW2:claim'then r.coop:context(index,function()if r.mail then r.mail:claim()end end);return end
  if text:match('^%s*/[123]%s*$')then r.coop:command(index,text)
  elseif text=='/or sync'then self:send('W',C.version..','..self.peers[index].nonce..','..r.cfg.difficulty,index);self:flushNPCs(index,true);self:flushShots(index);r.coop:context(index,function()r.contract:show()end)
  elseif text=='/or status'then self:chat('【起源重构】难度 '..require('difficulty').get(r.cfg).name..'｜服务端权威｜重构体 '..r:count()..'｜版本 '..C.version,index);r.coop:context(index,function()r.contract:show()end)end
 end
end
function N:update()
 local r=self.r;if not self.ready then return end
 local inbox=self.inbox;self.inbox={}
 for _,entry in ipairs(inbox)do
  if entry.world==r.world then
   local ok,err=pcall(function()
    if r:w('netMode','int32',-1)==1 and entry.kind=='server'then self:receive(entry.body)
    elseif r:w('netMode','int32',-1)==2 and entry.kind=='client'then self:handle(entry.index,entry.body)end
   end)
   if not ok then r.log('NET_MESSAGE_ERROR',tostring(err))end
  end
 end
 if not self.ready then return end
 if r:w('netMode','int32',-1)==1 then self:clientUpdate();return end
 if r:w('netMode','int32',-1)~=2 then return end
 local arr=r:w('player','object',nil)
 for index,peer in pairs(self.peers)do
  local p=arr and index<r.b.p.array_length(arr)and r.b.p.array_at(arr,index,'object')
  local raw=p and r.b:get('Player','name',p,'object',nil);local name=raw and r.b.p.string_value(raw)
  if not p or not r.b:get('Player','active',p,'bool',false)or name~=peer.name then r.coop:drop(index);self.peers[index]=nil;self.rate[index]=nil;r.log('NET_LEAVE','player='..index)end
 end
 if r.ticks%6==0 then self:flushNPCs(nil,r.ticks%180==0)end
 r.coop:update()
 if r.ticks%60==0 then r.coop:environment()end
end
function N.install(r)
 local b=r.b;local p=b.p;local n=N.new(r);r.net=n;r.coop=require('cooperative').new(r)
 for key,spec in pairs({ChatHelper={'Terraria.Chat','ChatHelper'},ChatCommandProcessor={'Terraria.Chat','ChatCommandProcessor'},ChatMessage={'Terraria.Chat','ChatMessage'},ChatManager={'Terraria.UI.Chat','ChatManager'},NetworkText={'Terraria.Localization','NetworkText'},NetMessage={'Terraria','NetMessage'},Color={'Microsoft.Xna.Framework.Graphics','Color'}})do b.types[key]=p.get_type(spec[1],spec[2])end
 n.fromLiteral=b:exact('NetworkText','FromLiteral',{'string'},true);n.toString=b:exact('NetworkText','ToString',{},false)
 n.broadcast=b:exact('ChatHelper','BroadcastChatMessage',{{'Terraria.Localization','NetworkText'},{'Microsoft.Xna.Framework.Graphics','Color'},'int32'},true)
 n.targetChat=b:exact('ChatHelper','SendChatMessageToClient',{{'Terraria.Localization','NetworkText'},{'Microsoft.Xna.Framework.Graphics','Color'},'int32'},true)
 n.clientChat=b:exact('ChatHelper','SendChatMessageFromClient',{{'Terraria.Chat','ChatMessage'}},true)
 n.createMessage=b:exact('ChatCommandProcessor','CreateOutgoingMessage',{'string'},false)
 n.sendData=b:exact('NetMessage','SendData',{'int32','int32','int32',{'Terraria.Localization','NetworkText'},'int32','float','float','float','int32','int32','int32'},true)
 local display=b:exact('ChatHelper','DisplayMessage',{{'Terraria.Localization','NetworkText'},{'Microsoft.Xna.Framework.Graphics','Color'},'uint8','bool'},true)or b:exact('ChatHelper','DisplayMessage',{{'Terraria.Localization','NetworkText'},{'Microsoft.Xna.Framework.Graphics','Color'},'uint8'},true)
 local incoming=b:exact('ChatCommandProcessor','ProcessIncomingMessage',{{'Terraria.Chat','ChatMessage'},'int32'},false)
 local color=b:field('Color','packedValue','uint32');local colorOK=color.h and p.field_size and p.field_size(color.h)==4
 if not colorOK then
  colorOK=true;for _,name in ipairs({'A','B','G','R'})do local f=b:field('Color',name,'uint8');if not(f.h and p.field_size and p.field_size(f.h)==1)then colorOK=false end end
  n.colorABGR=colorOK
 end
 local text=b:field('ChatMessage','Text','string')
 for _,key in ipairs({'fromLiteral','toString','broadcast','targetChat','clientChat','createMessage','sendData'})do r.log('NET_MEMBER',key..'='..tostring(n[key]~=nil))end
 r.log('NET_MEMBER','display='..tostring(display~=nil)..' incoming='..tostring(incoming~=nil)..' color='..tostring(colorOK==true))
 local processor=b:get('ChatManager','Commands',nil,'object',nil)
 if processor and p.retain then n.processor=p.retain(processor)end
 local diagnostics={processor=n.processor~=nil,struct_arg=type(p.struct_arg)=='function',invoke_value_args=type(p.invoke_value_args)=='function',text_member=(text.h or text.getter)~=nil,retain=type(p.retain)=='function'}
 for _,key in ipairs({'processor','struct_arg','invoke_value_args','text_member','retain'})do r.log('NET_MEMBER',key..'='..tostring(diagnostics[key]))end
 if not(n.fromLiteral and n.toString and n.broadcast and n.targetChat and n.clientChat and n.createMessage and n.sendData and display and incoming and n.processor and p.struct_arg and p.invoke_value_args and colorOK and(text.h or text.getter))then
  r.log('NET_ROUTE','available=false; critical interface missing; multiplayer gameplay disabled');return n
 end
 local h1=p.install_hook(display,{prefix=function(_,args)
  local ok,raw=pcall(function()local str=p.invoke(n.toString,args[1]);return str and p.string_value(str)end)
  if ok and type(raw)=='string'and raw:sub(1,#C.prefix)==C.prefix then
   if r:w('netMode','int32',-1)==1 and args[3]==255 then n:queue('server',raw)end
   return true
  end
  return false
 end})
 local h2=p.install_hook(incoming,{prefix=function(_,args)
  local raw=b:get('ChatMessage','Text',args[1],'string',nil)
  if type(raw)~='string'and raw then raw=p.string_value(raw)end
  if r:w('netMode','int32',-1)==2 and type(raw)=='string'and(raw:sub(1,5)=='ORW2:'or raw:sub(1,#C.prefix)==C.prefix or raw:match('^%s*/[123]%s*$')or raw:match('^%s*/领取%s*$')or raw:match('^%s*/任务%s*$')or raw:match('^%s*/同步%s*$')or raw:match('^/or '))then
   if #raw<=128 and raw:sub(1,#C.prefix)~=C.prefix then n:queue('client',raw,args[2])end
   return true
  end
  return false
 end})
 if h1 then b.hooks[#b.hooks+1]=h1 end;if h2 then b.hooks[#b.hooks+1]=h2 end
 local busy=false
 local h3=p.install_hook(n.createMessage,{prefix=function(obj,args)
  if busy or r:w('netMode','int32',-1)~=1 then return false end
  local text=args[1];if type(text)~='string'and text then text=p.string_value(text)end
  if type(text)~='string'then return false end
  local claim=text:match('^%s*/领取%s*$');local cmd=text:match('^%s*/([123])%s*$');local control=text:match('^/or (sync)$')or text:match('^/or (status)$')or(text:match('^%s*/同步%s*$')and 'sync')or(text:match('^%s*/任务%s*$')and 'status')
  if not cmd and not control and not claim then return false end
  busy=true;local ok,result=pcall(p.invoke,n.createMessage,obj,p.string_create(claim and 'ORW2:claim'or cmd and 'ORW2:command:'..cmd or 'ORW2:control:'..control));busy=false
  if ok and result and result~=false then return true,result end;return false
 end})
 if h3 then b.hooks[#b.hooks+1]=h3 end
 n.ready=h1~=nil and h2~=nil and h3~=nil;r.log('NET_ROUTE','available='..tostring(n.ready)..' transport=vanilla_chat_module protocol='..C.version)
 return n
end
return N
