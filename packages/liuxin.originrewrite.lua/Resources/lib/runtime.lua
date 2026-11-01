local C=require('core')
local BossAuto=require('bossauto')
local BossGuard=require('bossguard')
local SpecialActions=require('specialactions')
local Notices=require('notices')
local Echo=require('echo')
local Difficulty=require('difficulty')
local Rewards=require('rewards')
local R={}; R.__index=R
function R.new(b,cfg,log)
 return setmetatable({b=b,cfg=cfg,log=log,states={},ticks=0,session=0,world=nil,random=C.rng(1),generation=0,spawnDepth=0,noticeQueue={},errors={},spawnMisses=0},R)
end
function R:authority()
 local mode=self:w('netMode','int32',-1)
 return mode==0 or(mode==2 and self.net and self.net.ready)
end
function R:w(name,kind,default) return self.b:get('Main',name,nil,kind or 'bool',default) end
function R:n(n,name,kind,default) return self.b:get('NPC',name,n,kind or 'bool',default) end
function R:worldState()
 return {boss1=self.b:get('NPC','downedBoss1',nil,'bool',false),boss2=self.b:get('NPC','downedBoss2',nil,'bool',false),boss3=self.b:get('NPC','downedBoss3',nil,'bool',false),slimeKing=self.b:get('NPC','downedSlimeKing',nil,'bool',false),hard=self:w('hardMode'),moon=self.b:get('NPC','downedMoonlord',nil,'bool',false),
 plantera=self.b:get('NPC','downedPlantBoss',nil,'bool',false),
 mech1=self.b:get('NPC','downedMechBoss1',nil,'bool',false),mech2=self.b:get('NPC','downedMechBoss2',nil,'bool',false),mech3=self.b:get('NPC','downedMechBoss3',nil,'bool',false),
 expert=self:w('expertMode'),master=self:w('masterMode'),zenith=self:w('zenithWorld'),journey=self:w('GameMode','int32',0)==3}
end
function R:notice(text,color,key)
 text=Notices.format(text)
 if self.bossDialog and self.bossDialog.active and not (key and key:match('^boss:'))then return end
 self.log('NOTICE',text)
 -- Remote players choose their own display mode; keep server delivery intact.
 if self.cfg.taskDisplay=='gui'and Notices.task(key)and self.playerOverride==nil then return end
 if not self.cfg.notices then return end
 if key then
  for i=#self.noticeQueue,1,-1 do if self.noticeQueue[i][3]==key and self.noticeQueue[i][4]==self.playerOverride then table.remove(self.noticeQueue,i) end end
  if #self.noticeQueue>=(self:w('netMode','int32',-1)==2 and 96 or 24)then table.remove(self.noticeQueue) end
  local function priorityOf(k)return k and k:match('^boss:') and 4 or k=='environment' and 1 or 0 end
  local priority=priorityOf(key);local i=1
  while i<=#self.noticeQueue and priorityOf(self.noticeQueue[i][3])>=priority do i=i+1 end
  table.insert(self.noticeQueue,i,{text,color or {210,230,255},key,self.playerOverride,self.net and self.net.peers[self.playerOverride]and self.net.peers[self.playerOverride].nonce})
 elseif #self.noticeQueue<(self:w('netMode','int32',-1)==2 and 96 or 24)then self.noticeQueue[#self.noticeQueue+1]={text,color or {210,230,255},nil,self.playerOverride,self.net and self.net.peers[self.playerOverride]and self.net.peers[self.playerOverride].nonce} end
end
function R:tick()
 local menu=self:w('gameMenu','bool',true); local net=self:w('netMode','int32',-1)
 if (menu and not(net==2 and self:w('dedServ','bool',false)))or(net~=0 and net~=1 and net~=2)then
  if self.world~=nil then
   if self:authority() and self:w('worldID','int32',nil)==self.world then self:restoreAll() end
   if self.net then self.net:reset()end
   self.bossAutoStates={};self.sessionNet=nil;self.helpers={};self.states={}; self.world=nil; self.spawnMisses=0; self.noticeQueue={};if self.bossDialog then self.bossDialog:clear()end
   if self.archive then self.archive:clear()end;if self.contract then self.contract:clear()end
  end
  return false
 end
 local id=self:w('worldID','int32',nil)
 if id==nil then return false end
 if self.world~=id or self.sessionNet~=net then
  -- 世界ID已变时旧数组可能已经替换，不能把旧属性写入新世界同槽位。
  if self.archive then self.archive:clear()end;if self.contract then self.contract:clear()end
  if next(self.bossAutoStates or {})then self.log('BOSS_AUTO_CLEANUP','reason=world_change discard=true')end
  self.bossAutoStates={};self.helpers={};self.states={}; self.world=id; self.session=self.session+1; self.ticks=0;self.rejects={};self.sessionChecks=0;self.spawnMisses=0
  if self.bossDialog then self.bossDialog:clear()end
  self.lastTick=nil; self.envLabel=nil; self.envNotice=nil; self.noticeQueue={}
  self.random=C.rng(id);self.sessionNet=net
  if self.net then self.net:reset()end
  if self.shotGuard then self.shotGuard.shots={}end
  if self.budget then self.budget:clear()end
  self.log('WORLD','id='..id..' session='..self.session)
 end
 local tick=self:w('GameUpdateCount','uint32',nil) or self:w('gameUpdateCount','uint32',nil)
 if tick~=nil and self.lastTick==tick then return true end
 self.lastTick=tick; self.ticks=self.ticks+1
 if self.net then self.net:update()end
 if net==1 then return true end
 if not self:authority()then return true end
 SpecialActions.update(self)
 BossAuto.sweep(self)
 if net==0 and self.archive and self.cfg.archive and (self.ticks==1 or self.ticks%300==0)then
  local ok,err=pcall(function()self.archive:bind();self.archive:save()end);if not ok then self.log('ARCHIVE_ERROR',tostring(err))end
 end
 if net==0 and self.contract then local ok,err=pcall(self.contract.update,self.contract);if not ok then self.contract.status='failed';self.log('CONTRACT_ERROR',tostring(err))end end
 if self.bossDialog and self.ticks%15==1 then
  local ok,err=pcall(self.bossDialog.update,self.bossDialog)
  if not ok then self.bossDialog:clear();self.bossDialog=nil;self.log('BOSS_DIALOG_DISABLED',tostring(err))end
 end
 if self.collector and self.ticks%300==0 then self.collector:save()end
 if self.store and self.store.dirty and self.ticks%300==0 and self.store:save()then self.store.dirty=false end
 if self.ticks%600==0 then
  self.log('HEARTBEAT','world='..self.world..' ticks='..self.ticks..' elites='..self:count()..' generations='..self.generation)
  local summary={};for reason,count in pairs(self.rejects or {}) do summary[#summary+1]=reason..'='..count end
  table.sort(summary);self.log('SPAWN_SUMMARY',table.concat(summary,' '))
 end
 if net==0 and(self.ticks==1 or self.ticks%60==0)then self:environment(nil,true)end
 if self.ticks%60==0 then
  local arr=self:w('npc','object',nil)
  if arr then
   for slot,s in pairs(self.states) do
    local n=self.b.p.array_at(arr,slot,'object')
    if not n or not self:n(n,'active') then self.states[slot]=nil end
   end
  end
 end
 if #self.noticeQueue>0 and self.ticks%(net==2 and 5 or 45)==0 and (self.chat or(net==2 and self.net and self.net.ready)) and (not(self.bossDialog and self.bossDialog.active)or(self.noticeQueue[1][3]or''):match('^boss:'))then
  local message=table.remove(self.noticeQueue,1)
  local text=self.b.p.string_create(message[1]); local rgb=message[2]
  if net==2 then
   local peer=message[4]~=nil and self.net.peers[message[4]]
   if message[4]~=nil and(not peer or peer.nonce~=message[5])then return true end
   local ok,err=pcall(self.net.notify,self.net,message[1],message[4],rgb,message[3])
   if not ok or err==false then self.log('NET_NOTICE_FAILED',tostring(err))end
   return true
  end
  local ok,result
  if self.chatArgs==5 then ok,result=pcall(self.b.p.invoke,self.chat,text,rgb[1],rgb[2],rgb[3],true)
  else ok,result=pcall(self.b.p.invoke,self.chat,text,rgb[1],rgb[2],rgb[3]) end
  if not ok or result==false then self.log('CHAT_DISABLED','invoke failed: '..tostring(result)); self.chat=nil
  elseif not self.chatConfirmed then self.chatConfirmed=true;self.log('CHAT_SENT','first notice delivered; args='..tostring(self.chatArgs)) end
 end
 return true
end
function R:player(n)
 local arr=self:w('player','object',nil);if not arr then return end
 local function living(index)
  if not index or index<0 or index>=self.b.p.array_length(arr)then return end
  local p=self.b.p.array_at(arr,index,'object')
  if p and self.b:get('Player','active',p,'bool',false)and not self.b:get('Player','dead',p,'bool',true)then return p end
 end
 if self.playerOverride~=nil then return living(self.playerOverride)end
 local index=n and self:n(n,'target','int32',-1)or self:w('myPlayer','int32',-1)
 local p=living(index);if p then return p end
 if self:w('netMode','int32',-1)~=2 then return living(self:w('myPlayer','int32',-1))end
 local x,y;if n then x,y=self.b:vec('NPC','position',n)end
 local best,distance
 for i=0,self.b.p.array_length(arr)-1 do
  local candidate=living(i)
  if candidate then
   local px,py=self.b:vec('Player','position',candidate);local d=x and px and(px-x)^2+(py-y)^2 or i
   if not distance or d<distance then best=candidate;distance=d end
  end
 end
 return best
end
function R:environment(n,announce)
 local p=self:player(n); local e={hard=self:w('hardMode'),night=not self:w('dayTime'),blood=self:w('bloodMoon'),eclipse=self:w('eclipse')}
 local function zone(k) return p and self.b:get('Player',k,p,'bool',false) end
 e.underground=zone('ZoneDirtLayerHeight') or zone('ZoneRockLayerHeight'); e.hell=zone('ZoneUnderworldHeight')
 e.biome='forest'
 for _,v in ipairs({{'ZoneDesert','desert'},{'ZoneSnow','snow'},{'ZoneJungle','jungle'},{'ZoneHallow','hallow'},{'ZoneCorrupt','corrupt'},{'ZoneCrimson','crimson'}}) do if zone(v[1]) then e.biome=v[2] end end
 e.special=zone('ZoneDungeon') and '地牢' or zone('ZoneBeach') and '海洋' or zone('ZoneGlowshroom') and '蘑菇洞' or zone('ZoneSkyHeight') and '天空' or ''
 e.storm=zone('ZoneSandstorm'); e.wind=math.abs(self:w('windSpeedCurrent','float',0))>.6
 e.rain=self:w('raining'); e.snowMoon=self:w('snowMoon'); e.pumpkinMoon=self:w('pumpkinMoon'); e.slimeRain=self:w('slimeRain')
 e.weather=e.rain or e.storm or e.wind or e.blood or e.eclipse or e.snowMoon or e.pumpkinMoon or e.slimeRain
 local label,text=Notices.environment(e)
 if announce and self.cfg.environmentNotices~=false and p and label~=self.envLabel and (not self.envNotice or self.ticks-self.envNotice>=self.cfg.terrainNoticeTicks) then
  self.envLabel=label; self.envNotice=self.ticks; self:notice(text,{200,240,210},'environment')
 end
 return e
end
function R:count()
 local count=0; for _,s in pairs(self.states) do if s.tier then count=count+1 end end; return count
end
function R:slot(n) return self:n(n,'whoAmI','int32',-1) end
function R:sameSlot(n,slot)
 local arr=self:w('npc','object',nil)
 if not arr or slot<0 or slot>=self.b.p.array_length(arr) then return false end
 local obj=self.b.p.array_at(arr,slot,'object')
 local f=self.b:field('NPC','whoAmI','int32').h
 return obj and self.b.p.field_pointer(f,obj)==self.b.p.field_pointer(f,n)
end
function R:defaults(n)
 local slot=self:slot(n)
 if self:sameSlot(n,slot)then
  local old=self.states[slot]
  if self.net and old then
   if self:w('netMode','int32',-1)==1 and old.remote then
    self.net.tombstones[slot]=math.max(self.net.tombstones[slot]or 0,old.generation)
    local pending=self.net.pending[slot];if pending and pending.v.generation<=old.generation then self.net.pending[slot]=nil end
   elseif self:w('netMode','int32',-1)==2 and self.net.ready and(old.tier or old.rejected=='helper')then self.net:send('D',slot..','..old.generation);self.net.sent[slot]=nil end
  end
  self.states[slot]=nil
 end
end
function R:eligible(n)
 if BossGuard.isBoss(self,n) then return false,'boss' end
 for _,key in ipairs({'friendly','townNPC','boss','SpawnedFromStatue'}) do if self:n(n,key) then return false,key end end
 if not self:n(n,'active') then return false,'inactive' end
 if self:n(n,'realLife','int32',-1)>=0 then return false,'segment' end
 if self:n(n,'lifeMax','int32',0)<=5 then return false,'tiny_life' end
 if self:n(n,'damage','int32',0)<=0 then return false,'no_damage' end
 -- 原版蠕虫、分裂/群体/事件/召唤类保守排除。
 local style=self:n(n,'aiStyle','int32',0)
 if style==6 or style==37 or style==27 then return false,'excluded_style' end
 -- Cache only positive sightings. Never cache absence: a boss can spawn later
 -- in the same frame, and its minions must immediately stay out of elite rolls.
 if self.lastTick~=nil and self.bossSeenTick==self.lastTick and self.bossSeenSession==self.session then return false,'boss_battle' end
 local arr=self:w('npc','object',nil)
 if arr then
  for i=0,self.b.p.array_length(arr)-1 do
   local obj=self.b.p.array_at(arr,i,'object')
   if obj and self:n(obj,'active') and BossGuard.isBoss(self,obj) then
    self.bossSeenTick=self.lastTick;self.bossSeenSession=self.session
    return false,'boss_battle'
   end
  end
 end
 return true
end
function R:reject(s,reason,slot)
 s.rejected=reason;self.rejects=self.rejects or {};self.rejects[reason]=(self.rejects[reason] or 0)+1
 if (self.sessionChecks or 0)<=40 then
  self.log('SPAWN_REJECT','slot='..slot..' npc='..s.type..' reason='..reason..' total='..self.rejects[reason])
 end
 return s
end
function R:base(n)
 return {max=self:n(n,'lifeMax','int32',1),life=self:n(n,'life','int32',1),damage=self:n(n,'damage','int32',0),defense=self:n(n,'defense','int32',0),value=self:n(n,'value','float',0),scale=self:n(n,'scale','float',1),knock=self:n(n,'knockBackResist','float',0)}
end
function R:apply(n,stats)
 for _,v in ipairs({{'lifeMax','max','int32'},{'life','life','int32'},{'damage','damage','int32'},{'defense','defense','int32'},{'value','value','float'},{'scale','scale','float'},{'knockBackResist','knock','float'}}) do
  if not self.b:set('NPC',v[1],n,stats[v[2]],v[3]) then error('写入失败 '..v[1]) end
 end
 if self:n(n,'lifeMax','int32',0)~=stats.max or self:n(n,'damage','int32',0)~=stats.damage then error('属性回读不一致') end
end
function R:commit(n,slot)
 if not self:authority()then return {type=self:n(n,'type','int32',0),rejected='not_authority'}end
 self.generation=self.generation+1
 self.sessionChecks=(self.sessionChecks or 0)+1
 local s={type=self:n(n,'type','int32',0),generation=self.generation}; self.states[slot]=s
 if not self.cfg.enabled then return self:reject(s,'disabled',slot) end
 if self.spawnDepth>0 then return self:reject(s,'summoned',slot) end
 if self:count()>=Difficulty.cap(self.cfg) then return self:reject(s,'active_limit',slot) end
 local eligible,reason=self:eligible(n)
 if not eligible then return self:reject(s,reason,slot) end
 local w=self:worldState(); local stage,mode=C.stage(w),C.mode(w)
 local protection=require('protection').profile(w)
 if protection and self:count()>=math.min(Difficulty.cap(self.cfg),protection.cap)then return self:reject(s,'early_limit',slot)end
 if protection and require('protection').nearSpawn(self,n)then return self:reject(s,'spawn_protection',slot)end
 local e=self:environment(n); local m=C.modifiers()
 local baseChance=math.min(1,Difficulty.chance(self.cfg,stage,protection)*m.chance)
 local chance,limit=C.spawnChance(baseChance,self.spawnMisses or 0);if Difficulty.get(self.cfg).name=='疯狂'then chance=math.min(.60,chance)end;local roll=self.random()
 if self.sessionChecks<=40 then self.log('SPAWN_ROLL',('slot=%d npc=%d mode=%d roll=%.4f chance=%.4f'):format(slot,s.type,mode,roll,chance)) end
 if chance<=0 or roll>chance then
  if baseChance>0 then self.spawnMisses=math.min(limit,(self.spawnMisses or 0)+1)end
  self.log('SPAWN_PITY','misses='..(self.spawnMisses or 0)..' limit='..limit..' chance='..chance)
  return self:reject(s,'chance',slot)
 end
 local tier=Difficulty.tier(self.random,stage,self.cfg,protection); local base=self:base(n)
 s.base=base; s.stage=stage; s.mode=mode; s.environment=e; s.modifiers=m
 s.stats=Difficulty.stats(base,protection and require('protection').stats(base,tier)or C.stats(base,tier,stage,mode,m),self.cfg,tier)
 if protection then self.log('EARLY_PROTECTION','slot='..slot..' cap='..math.min(Difficulty.cap(self.cfg),protection.cap)..' chance='..chance..' tier2='..protection.tier2)end
 local ok,err=pcall(function() self:apply(n,s.stats) end)
 if not ok then pcall(function() self:apply(n,base) end); self.log('COMMIT_FAILED',tostring(err)); return s end
 self.log('SPAWN_PITY_SUCCESS','misses='..(self.spawnMisses or 0)..' limit='..limit..' difficulty='..self.cfg.difficulty)
 self.spawnMisses=0
 s.tier=tier; s.phase='ready'; s.timer=0
 s.immunity=self:n(n,'dontTakeDamage','bool',false)
 s.action='echo';s.alpha=self:n(n,'alpha','int32',0)
 if self.cfg.ai then require('styles').assign(self,n,s);s.echo=Echo.choose(self.random,s.type,self.collector,stage);Echo.assign(self,n,s) end
 if s.echo then self.log('ECHO_ASSIGN','slot='..slot..' donor='..s.echo.name..' projectile='..s.echo.projectile)
 else self.log('ECHO_UNAVAILABLE','all eligible recipes quarantined') end
 -- Initial wait also follows the selected difficulty (75%-125% of cooldown).
 if not s.combat then s.timer=math.floor(Echo.cooldown(self,s)*(.75+self.random()*.5))end
 local originalName='怪物#'..s.type
 if self.nameGetter then local text=self.b.p.invoke(self.nameGetter,n);if text then originalName=self.b.p.string_value(text) or originalName end end
 local name=self.b:get('NPC','_givenName',n,'object',nil)
 s.name=name and self.b.p.string_value(name) or nil
 if self.nameSetter and self.nameGetter then
  local ok,err=pcall(function()
   local original=self.b.p.invoke(self.nameGetter,n)
   original=original and self.b.p.string_value(original)
   if original and original~='' then
    s.displayName=C.displayName(tier,original,false)
    local result=self.b.p.invoke(self.nameSetter,n,self.b.p.string_create(s.displayName))
    s.renamed=result~=false
    if s.renamed then self.log('NAME_WRITE','slot='..slot..' color='..C.nameColors[tier]..' original='..original) end
   end
  end)
  if not ok then self.nameSetter=nil; self.log('NAME_DISABLED',tostring(err)) end
 end
 self.log('COMMIT',('slot=%d generation=%d tier=%d stage=%d action=%s life=%d damage=%d'):format(slot,s.generation,tier,stage,s.action,s.stats.max,s.stats.damage))
 if s.echo then self.log('ECHO_TIMING','slot='..slot..' tier='..tier..' initial='..s.timer..' cooldown='..(s.combat and 'independent' or Echo.cooldown(self,s))..(s.combat and (' action_initial='..tostring(s.combat.action and s.combat.action.due or 'none')..' shot_initial='..tostring(s.combat.shot and s.combat.shot.due or 'none'))or '')..' warning='..Difficulty.warning(self.cfg,s))end
 if self.cfg.skillNotices and s.headText then
  self:notice(Notices.skill(tier,originalName,s.skillSummary or s.headText,nil,s.style),{tier==3 and 255 or 170,tier==3 and 150 or 210,255},'skill:'..slot..':'..s.generation)
 elseif tier>=2 then self:notice(C.names[tier]..'出现！',{tier==3 and 255 or 170,tier==3 and 150 or 210,255},'skill:'..slot..':'..s.generation)end
 if self.net then self.net:publishNPC(n,s)end
 return s
end
function R:ai(n,s)
 if s.tier then Echo.update(self,n,s) end
 if s.contactUntil and(self.lastTick or 0)<s.contactUntil then self.b:set('NPC','damage',n,math.max(1,math.floor(s.contactDamage*.3)),'int32')end
end
function R:onAI(n)
 if not self:tick() or not self:n(n,'active') or self:n(n,'life','int32',0)<=0 then return end
 local slot=self:slot(n); if slot<0 or not self:sameSlot(n,slot) then return end
 local s=self.states[slot]
 if self:w('netMode','int32',-1)==1 then
  if s and s.remote and s.type==self:n(n,'type','int32',0)then self.net:applyStats(n,s)end
  return
 end
 if not self:authority()then return end
 if not s or s.type~=self:n(n,'type','int32',0) then s=self:commit(n,slot)end
 if not self:authority()then return end
 if self.cfg.bossAutoAI and BossAuto.supports(s.type) then
  local ok,err=pcall(BossAuto.update,self,n,s)
  if not ok then pcall(BossAuto.clear,self);self.cfg.bossAutoAI=false;self.log('BOSS_AUTO_DISABLED',tostring(err))end
  return
 end
 if not s.tier or s.aiFailed then return end
 local ok,err=pcall(function() self:ai(n,s) end)
 if not ok then
  local isolated=pcall(Echo.fail,self,n,s,err)
  if not isolated then s.aiFailed=true;s.echoFailed=true end
  if s.phase=='motion' then self.b:putvec('NPC','velocity',n,0,0) end
  if s.echoWarning then self.b:set('NPC','alpha',n,s.alpha or 0,'int32');s.echoWarning=false end
  self.log(isolated and 'AI_RECIPE_ERROR' or 'AI_DISABLED',tostring(err))
 end
end
function R:loot(n)
 if not self:authority()then return end
 local s=self.states[self:slot(n)]
 if not s or not s.tier or s.settled or s.type~=self:n(n,'type','int32',0) then return end
 s.settled=true
 if self:n(n,'life','int32',1)<=0 and self:sameSlot(n,self:slot(n))then
  local localIndex=self:w('myPlayer','int32',-1)
  local interactions=self:n(n,'playerInteraction','object',nil)
  local credited=localIndex>=0 and localIndex<255 and(self:n(n,'lastInteraction','int32',-1)==localIndex or(interactions and localIndex<self.b.p.array_length(interactions)and self.b.p.array_at(interactions,localIndex,'bool')==true))
  if self:w('netMode','int32',-1)==2 and self.coop then self.coop:kill(n,s)
  elseif credited then
   if self.archive then local ok,err=pcall(self.archive.kill,self.archive,s);if not ok then self.log('ARCHIVE_ERROR',tostring(err))end end
   if self.contract then local ok,err=pcall(self.contract.kill,self.contract,s);if not ok then self.contract.status='failed';self.log('CONTRACT_ERROR',tostring(err))end end
  end
 end
 if not self.cfg.extraLoot or not self.item then return end
 local id,stack,kind=Rewards.choose(self.random,s.tier,s.stage,s.modifiers,s.environment or {},self.cfg); if not id then return end
 local x,y=self.b:vec('NPC','position',n); local arr=self:w('item','object',nil); if not x or not arr then return end
 self:giveItem(id,stack,x,y,self:n(n,'width','int32',16),self:n(n,'height','int32',16),kind)
end
function R:giveItem(id,stack,x,y,width,height,kind)
 if not self:authority()or not self.item then return false end
 local arr=self:w('item','object',nil);if not arr then return false end
 local index=self.b.p.invoke(self.item,math.floor(x),math.floor(y),width,height,id,stack,false,0,self.itemOwnership and 0 or 255)
 if type(index)~='number' or index<0 or index>=self.b.p.array_length(arr) then self.item=nil; self.log('LOOT_DISABLED','invalid slot'); return false end
 local item=self.b.p.array_at(arr,index,'object')
 if item and self.worldItems then item=self.b:get('WorldItem','inner',item,'object',nil) end
 local actualType=item and self.b:get('Item','type',item,'int32',0) or -1
 local actualStack=item and self.b:get('Item','stack',item,'int32',0) or -1
 if actualType~=id or actualStack<stack then
  self.item=nil; self.log('LOOT_DISABLED',('readback slot=%d expected=%d/%d actual=%s/%s route=%s'):format(index,id,stack,tostring(actualType),tostring(actualStack),self.worldItems and 'WorldItem.inner' or 'Item')); return false
 end
 if self.net then self.net:native(21,index)end
 self.log('LOOT','slot='..index..' item='..id..' stack='..stack..' kind='..tostring(kind))
 return true
end
function R:restore(n,s)
 require('guardstyle').clear(self,n,s)
 if not s.tier or not s.base then return end
 local ratio=self:n(n,'life','int32',0)/math.max(1,self:n(n,'lifeMax','int32',1))
 local base={}; for k,v in pairs(s.base) do base[k]=v end; base.life=math.max(1,math.floor(base.max*ratio+.5))
 self:apply(n,base)
 if s.phase=='motion' then self.b:putvec('NPC','velocity',n,0,0) end
 if s.alpha~=nil then self.b:set('NPC','alpha',n,s.alpha,'int32') end
 if s.renamed and self.nameSetter then self.b.p.invoke(self.nameSetter,n,self.b.p.string_create(s.name or '')) end
end
function R:restoreAll()
 BossAuto.clear(self)
 if not self:authority()then self.states={};self.helpers={};return end
 SpecialActions.clear(self)
 if self.shotGuard then self.shotGuard:clear()end
 if self.budget then self.budget:clear()end
 if self.heads then self.heads:clear() end
 local arr=self:w('npc','object',nil); if not arr then return end
 for slot,s in pairs(self.states) do
  local n=self.b.p.array_at(arr,slot,'object')
  if n and self:n(n,'active') and self:n(n,'type','int32',0)==s.type then pcall(function() self:restore(n,s);if self.net then self.net:syncNPC(n)end end) end
 end
end
return R
