local Voices=require('bossvoices')
local D={};D.__index=D
local function key(t)
 if t==14 or t==15 then return 13 elseif t==126 then return 125 else return t end
end
function D.new(r)return setmetatable({r=r,encounters={},counts={},active=false},D)end
function D:clear()self.encounters={};self.active=false;self.wasDead=false end
function D:emit(k,e,event)
 local voice=Voices[k];if not voice then return end
 local counts=self.counts[k] or {spawn=0,kill=0,defeat=0};self.counts[k]=counts
 local idx
 if event=='spawn' then counts.spawn=counts.spawn+1;idx=math.min(4,counts.spawn)
 elseif event=='half' then idx=5
 elseif event=='death' then counts.kill=counts.kill+1;idx=5+math.min(3,counts.kill)
 else counts.defeat=counts.defeat+1;idx=8+math.min(3,counts.defeat)end
 local title=({spawn='领域开启',half='防线瓦解',death='战斗结算',defeat='挑战失利'})[event]
 self.r:notice('【Boss战 · '..title..'】'..e.name..'\n'..voice[idx],{255,160,130},'boss:'..k..':'..event)
 self.r.log('BOSS_DIALOG','type='..k..' event='..event)
end
function D:update()
 local r=self.r
 if not r.cfg.bossDialog then self:clear();return end
 local arr=r:w('npc','object',nil);if not arr then return end
 local groups={}
 for i=0,math.min(199,r.b.p.array_length(arr)-1)do
  local n=r.b.p.array_at(arr,i,'object');local t=n and r:n(n,'type','int32',0) or 0
  local k=key(t)
  if n and r:n(n,'active') and r:n(n,'life','int32',0)>0 and (r:n(n,'boss') or k==13) and Voices[k] then
   local g=groups[k]or {life=0,max=0,n=n};groups[k]=g
   g.life=g.life+r:n(n,'life','int32',0);g.max=g.max+r:n(n,'lifeMax','int32',1)
  end
 end
 local any=false
 for k,g in pairs(groups)do
  any=true;local e=self.encounters[k]
  if not e then
   local name='Boss#'..k
   if r.nameGetter then local raw=r.b.p.invoke(r.nameGetter,g.n);if raw then name=r.b.p.string_value(raw) or name end end
   e={name=name};self.encounters[k]=e
   self:emit(k,e,'spawn')
  end
  if not e.half and g.life/math.max(1,g.max)<=.5 then e.half=true;self:emit(k,e,'half')end
 end
 for k in pairs(self.encounters)do if not groups[k]then self.encounters[k]=nil end end
 if self.active and not any then r.envLabel=nil end
 self.active=any
 local players=r:w('player','object',nil);local index=r:w('myPlayer','int32',-1)
 local player=players and index>=0 and r.b.p.array_at(players,index,'object')
 local dead=player and r.b:get('Player','dead',player,'bool',false)==true
 if r:w('netMode','int32',-1)==2 and players then
  local active,alive=0,0
  for i=0,r.b.p.array_length(players)-1 do local p=r.b.p.array_at(players,i,'object');if p and r.b:get('Player','active',p,'bool',false)then active=active+1;if not r.b:get('Player','dead',p,'bool',true)then alive=alive+1 end end end
  dead=active>0 and alive==0
 end
 if dead and not self.wasDead and any then
  for k,e in pairs(self.encounters)do self:emit(k,e,'defeat')end
 end
 self.wasDead=dead
end
function D:death(n)
 if not self.r.cfg.bossDialog or not self.r:authority() then return end
 local t=self.r:n(n,'type','int32',0);local k=key(t);local e=self.encounters[k]
 if not e or e.killed then return end
 -- Only full encounter completion counts; worm segments and one twin are not victory.
 local arr=self.r:w('npc','object',nil)
 if arr then
  for i=0,math.min(199,self.r.b.p.array_length(arr)-1)do
   local other=self.r.b.p.array_at(arr,i,'object')
   if other and other~=n and key(self.r:n(other,'type','int32',0))==k and self.r:n(other,'active') and self.r:n(other,'life','int32',0)>0 then return end
  end
 end
 if self.r:n(n,'life','int32',1)>0 then return end
 e.killed=true;self:emit(k,e,'death')
end
return D
