-- Supplementary decisions: never writes vanilla AI arrays, combat stats or collision flags.
local B={}
local adapters=require('bossprofiles')
local Late=require('bosslate')
function B.supports(kind)return adapters[kind]~=nil end
local function restore(r,n,state)
 if state.lastAlpha and r:n(n,'alpha','int32',0)==state.lastAlpha then r.b:set('NPC','alpha',n,state.alpha,'int32')end
 state.lastAlpha=nil
end
function B.clear(r,reason)
 local arr=r:w('npc','object',nil)
 for slot,state in pairs(r.bossAutoStates or {})do
  local n=arr and r.b.p.array_at(arr,slot,'object')
  if n==state.handle and state.session==r.session and state.generation==(r.states[slot]and r.states[slot].generation)and r:n(n,'type','int32',0)==state.type then restore(r,n,state)end
  r.log('BOSS_AUTO_CLEANUP','slot='..slot..' reason='..(reason or 'restore_all'))
 end
 r.bossAutoStates={}
end
function B.sweep(r)
 if (r.lastTick or 0)%30~=0 then return end
 local arr=r:w('npc','object',nil)
 for slot,state in pairs(r.bossAutoStates or {})do
  local n=arr and r.b.p.array_at(arr,slot,'object')
  if n~=state.handle or not r:n(n,'active','bool',false)or r:n(n,'life','int32',0)<=0 or state.session~=r.session or state.type~=r:n(n,'type','int32',0)or state.generation~=(r.states[slot]and r.states[slot].generation)then
   r.log('BOSS_AUTO_CLEANUP','slot='..slot..' reason=inactive_or_replaced');r.bossAutoStates[slot]=nil
  end
 end
end
local function release(r,n,state,reason)
 restore(r,n,state);state.phase='idle';state.timer=0;state.due=(r.lastTick or 0)+(({easy=240,normal=180,crazy=135})[r.cfg.difficulty]or 180)+math.floor(r.random()*60);state.paused=0
 if reason then r.log('BOSS_AUTO_CANCEL','npc='..state.type..' reason='..reason)end
end
local function eligible(r,n,a,state,phase,step,target)
 if r:n(n,'timeLeft','int32',750)<=60 then return false end
 if a.kind=='plant' or a.kind=='golem' or a.kind=='walker' then
  if r:n(n,'dontTakeDamage','bool',true) then return false,'native_invulnerable' end
  if r:n(n,'alpha','int32',255)>60 then return false,'native_transparency' end
  if a.kind=='plant' then
   local player=target or r:player(n);if not player then return false,'target_lost' end
   if not r.b:get('Player','ZoneJungle',player,'bool',false) or not (r.b:get('Player','ZoneDirtLayerHeight',player,'bool',false) or r.b:get('Player','ZoneRockLayerHeight',player,'bool',false)) then return false,'outside_underground_jungle' end
   local vx,vy=r.b:vec('NPC','velocity',n)
   return vx~=nil and vx*vx+vy*vy>=.25 and vx*vx+vy*vy<=144,'native_speed_guard'
  end
  if phase~=0 then return false,'native_attack' end
  if a.kind~='walker' and r:n(n,'noTileCollide','bool',true) then return false,'native_phasing' end
  local _,vy=r.b:vec('NPC','velocity',n)
  if a.kind=='golem' and state.phase=='motion' then return true end
  return vy~=nil and (math.abs(vy)<.01 or (r:n(n,'collideY','bool',false) and math.abs(vy)<1)),'not_grounded'
 end
 if a.kind=='bee' or a.kind=='queen' or a.kind=='fish' then
  if r:n(n,'dontTakeDamage','bool',true) or r:n(n,'alpha','int32',255)>60 then return false end
  local player=target or r:player(n);if not player then return false end
  if a.kind=='bee' then
   if not r.b:get('Player','ZoneJungle',player,'bool',false) then return false,'outside_jungle' end
   if not r.cfg.beeSurfaceTest and not (r.b:get('Player','ZoneDirtLayerHeight',player,'bool',false) or r.b:get('Player','ZoneRockLayerHeight',player,'bool',false)) then return false,'requires_underground_jungle' end
   local vx,vy=r.b:vec('NPC','velocity',n)
   if phase~=2 and phase~=3 then return false,'native_attack' end
   if not vx or not vy or vx*vx+vy*vy>=64 then return false,'native_speed_guard' end
   return true
  end
  if a.kind=='fish' then
   if not r.b:get('Player','ZoneBeach',player,'bool',false) then return false,'outside_beach' end
   return phase==0 or phase==5,'native_attack'
  end
  if phase~=0 then return false end
  if r:n(n,'noGravity','bool',false) then
   local vx,vy=r.b:vec('NPC','velocity',n)
   return vx~=nil and vx*vx+vy*vy<100
  end
  if r:n(n,'noTileCollide','bool',true) then return false end
  local _,vy=r.b:vec('NPC','velocity',n)
  return vy~=nil and (state.phase=='motion' or math.abs(vy)<.01 or (r:n(n,'collideY','bool',false) and math.abs(vy)<1))
 end
 if a.kind=='laser' or a.kind=='flame' then
  return not r:w('dayTime','bool',true) and (phase==0 or phase==3) and step==0 and not r:n(n,'dontTakeDamage','bool',true)
 end
 if a.kind=='prime' then return step==0 and not r:w('dayTime','bool',true) end
 if a.kind=='worm' then
  local vx,vy=r.b:vec('NPC','velocity',n)
  return not r:w('dayTime','bool',true) and r:n(n,'alpha','int32',255)==0 and not r:n(n,'dontTakeDamage','bool',true) and vx~=nil and vx*vx+vy*vy>=4
 end
 if a.kind=='eye'then return (phase==0 or phase==3) and step==0 and not r:n(n,'dontTakeDamage','bool',true) end
 if a.kind=='head'then return step==0 and not r:w('dayTime','bool',true)end
 if a.kind=='brain'then return phase==-1 and not r:n(n,'dontTakeDamage','bool',true)and r:n(n,'alpha','int32',255)==0 end
 if a.kind=='jump'then
  if phase>0 or step<0 or step>=5 or r:n(n,'alpha','int32',255)>60 or r:n(n,'dontTakeDamage','bool',true)then return false end
  local _,vy=r.b:vec('NPC','velocity',n)
  return vy~=nil and(state.phase=='motion' or math.abs(vy)<.01 or (r:n(n,'collideY','bool',false) and math.abs(vy)<1))
 end
 return false
end
local function writeMotion(r,n,state,a,first)
 if a.kind=='worm' or a.kind=='plant' then
  -- Only main entity velocity is steered; segment links, speed and all AI arrays stay native.
  local vx,vy=r.b:vec('NPC','velocity',n)
  if not vx or not vy then return false,'velocity_reader_unavailable' end
  local speed=math.sqrt(vx*vx+vy*vy)
  if speed<(a.kind=='plant' and .5 or 2) or speed>(a.kind=='plant' and 12 or 40) then return false,'native_speed_guard' end
  local ux,uy=vx/speed,vy/speed
  local dot=ux*state.aimX+uy*state.aimY
  if dot<-.25 then return false,'native_heading_guard' end -- no U-turn when the native worm has passed the target
  local ax,ay=ux*.92+state.aimX*.08,uy*.92+state.aimY*.08
  local len=math.sqrt(ax*ax+ay*ay)
  if len<.01 then return false,'direction_degenerate' end
  state.vx=ax/len*speed;state.vy=ay/len*speed
  return r.b:putvec('NPC','velocity',n,state.vx,state.vy)
 end
 if a.kind=='walker' then
  local _,vy=r.b:vec('NPC','velocity',n);if vy==nil then return false,'velocity_reader_unavailable' end
  state.vy=vy;return r.b:putvec('NPC','velocity',n,state.vx,vy)
 end
 if (a.kind=='jump' or a.kind=='golem' or (a.kind=='queen' and state.stage=='ground'))and not first then
  local _,vy=r.b:vec('NPC','velocity',n);if not vy then return false end
  return r.b:putvec('NPC','velocity',n,state.vx,vy)
 end
 return r.b:putvec('NPC','velocity',n,state.vx,state.vy)
end
function B.update(r,n,s)
 if Late.profiles[s.type] then return Late.update(r,n,s) end
 if not r.cfg.bossAutoAI or r:w('netMode','int32',-1)~=0 then return end
 local a=adapters[s.type];if not a or not r:n(n,'boss','bool',false)then return end
 if a.style and (r:n(n,'aiStyle','int32',-1)~=a.style or (a.kind~='worm' and r:n(n,'realLife','int32',-1)>=0)) then return end
 r.bossAutoStates=r.bossAutoStates or {};local slot=r:slot(n);local states=r.bossAutoStates;local state=states[slot]
 if not state or state.handle~=n or state.type~=s.type or state.generation~=s.generation or state.session~=r.session then
  state={handle=n,type=s.type,generation=s.generation,session=r.session,due=(r.lastTick or 0)+300+(s.type==126 and 90 or 0),phase='idle',timer=0};states[slot]=state
  r.log('BOSS_AUTO_BIND','npc='..s.type..' name='..a.name..' mode=profile_decision vanilla_phases=true')
 end
 if a.kind=='bee' and r.cfg.beeSurfaceTest and not state.testLogged then
  state.testLogged=true;r.log('BOSS_AUTO_TEST','npc='..s.type..' surface=true vanilla_enrage_unchanged=true')
 end
 if state.tick==r.lastTick then return end;state.tick=r.lastTick
 if a.night and r:w('dayTime','bool',true) then
  if state.phase~='idle' then release(r,n,state,'daytime_native_priority') end
  return
 end
 local ai=r:n(n,'ai','object',nil)
 if not ai or not r.b.p.array_length or r.b.p.array_length(ai)<2 then
  if state.phase~='idle'then release(r,n,state,'ai_reader_unavailable')end
  if not state.unavailable then state.unavailable=true;r.log('BOSS_AUTO_SKIP','npc='..s.type..' ai state reader unavailable')end;return
 end
 local phase=r.b.p.array_at(ai,0,'float');local step=r.b.p.array_at(ai,1,'float')
 if type(phase)~='number'or type(step)~='number'then if state.phase~='idle'then release(r,n,state,'invalid_ai_state')end;return end
 local observed=(a.kind=='head'or a.kind=='prime'or a.kind=='jump')and step or phase
 if state.vanillaPhase~=observed then
  state.vanillaPhase=observed;r.log('BOSS_AUTO_PHASE','npc='..s.type..' slot='..slot..' phase='..phase..' step='..step)
 end
 local stage=adapters.stage(a.kind,phase,step,r,n)
 if state.stage~=stage then
  if state.stage and state.phase~='idle' then release(r,n,state,'encounter_stage_change') end
  state.stage=stage;r.log('BOSS_AUTO_STAGE','npc='..s.type..' stage='..stage)
 end
 local target=r:player(n)
 if not target or r.b:get('Player','dead',target,'bool',false) then
  if state.phase~='idle' then release(r,n,state,'target_lost') end;return
 end
 local allowed,blockReason=eligible(r,n,a,state,phase,step,target)
 if not allowed then
  if state.phase=='idle' and (r.lastTick or 0)>=state.due and (not state.lastBlockLog or (r.lastTick or 0)-state.lastBlockLog>=300) then
   state.lastBlockLog=r.lastTick;local vx,vy=r.b:vec('NPC','velocity',n)
   r.log('BOSS_AUTO_BLOCK','npc='..s.type..' reason='..(blockReason or 'native_window')..' phase='..phase..' step='..step..' alpha='..r:n(n,'alpha','int32',-1)..' vy='..tostring(vy))
  end
  -- Suspend a warning through native teleport/jump/spin, without writing velocity.
  -- Executing motion always yields immediately to native special actions.
  if state.phase=='warning' then
   if blockReason=='outside_beach' or blockReason=='outside_jungle' or blockReason=='requires_underground_jungle' or blockReason=='outside_underground_jungle' then release(r,n,state,blockReason);return end
   if a.kind=='laser' or a.kind=='flame' or a.kind=='prime' or a.kind=='bee' or a.kind=='walker' then
    release(r,n,state,'native_window_closed');state.due=(r.lastTick or 0)+30;return
   end
   restore(r,n,state);state.paused=(state.paused or 0)+1
   if a.kind=='jump' or a.kind=='golem' or a.kind=='fish' or (a.kind=='queen' and state.stage=='ground') then state.timer=math.max(0,state.timer-1) end
   if state.paused==1 then r.log('BOSS_AUTO_WAIT','npc='..s.type..' reason=native_action stage='..stage) end
   if state.paused>180 or (r.lastTick or 0)>(state.warningDeadline or math.huge) then release(r,n,state,'warning_timeout') end
  elseif state.phase=='motion' then release(r,n,state,'native_action_priority') end
  return
 end
 if (a.kind=='laser' or a.kind=='flame') and state.phase=='idle' then
  local arr=r:w('npc','object',nil)
  for otherSlot,other in pairs(states) do
   if otherSlot~=slot and (other.type==125 or other.type==126) and other.phase~='idle' and other.session==r.session then
    local partner=arr and r.b.p.array_at(arr,otherSlot,'object')
    if partner==other.handle and r:n(partner,'active','bool',false) and r:n(partner,'life','int32',0)>0 then return end
   end
  end
 end
 if state.phase=='warning' and (state.paused or 0)>0 then
  r.log('BOSS_AUTO_RESUME','npc='..s.type..' waited='..state.paused)
  state.paused=0;if a.kind=='fish' then state.timer=math.max(state.timer,6) elseif a.kind~='jump' and a.kind~='golem' and a.kind~='walker' and not (a.kind=='queen' and state.stage=='ground') then state.timer=math.max(state.timer,18) end
 end
 local player=target;local x,y=r.b:vec('NPC','position',n);local px,py
 if player and not r.b:get('Player','dead',player,'bool',false) then px,py=r.b:vec('Player','position',player)end
 if not x or not px then if state.phase~='idle'then release(r,n,state,'target_lost')end;return end
 x=x+r:n(n,'width','int32',110)/2;y=y+r:n(n,'height','int32',110)/2
 px=px+r.b:get('Player','width',player,'int32',20)/2;py=py+r.b:get('Player','height',player,'int32',42)/2
 local dx,dy=px-x,py-y;local distance=math.sqrt(dx*dx+dy*dy)
 if distance>700 then if state.phase~='idle'then release(r,n,state,'target_out_of_range')end;return end
 if state.phase=='motion'then
  state.timer=state.timer-1
  local collision=(a.kind=='jump' or a.kind=='golem' or a.kind=='walker' or (a.kind=='queen' and state.stage=='ground'))and r:n(n,'collideX','bool',false)
  if state.timer<=0 or collision then
   local mx,my=x-(state.startX or x),y-(state.startY or y);release(r,n,state)
   r.log('BOSS_AUTO_END','npc='..s.type..' action='..state.approach..' reason='..(collision and 'wall_collision'or 'duration')..' dx='..string.format('%.1f',mx)..' dy='..string.format('%.1f',my));return
  end
  if (a.kind=='worm' or a.kind=='plant') and distance>=1 then state.aimX=dx/distance;state.aimY=dy/distance end
  local ok,reason=writeMotion(r,n,state,a,false)
  if not ok then release(r,n,state,reason or 'velocity_write_failed') end;return
 elseif state.phase=='warning'then
  if (r.lastTick or 0)>state.warningDeadline then release(r,n,state,'warning_timeout');return end
  if a.kind=='jump' or a.kind=='golem' or a.kind=='fish' or (a.kind=='queen' and state.stage=='ground') then state.timer=math.max(0,state.timer-1) else state.timer=state.timer-1 end
  -- Only Eye uses alpha flashing; other bosses retain their native teleport transparency.
  if a.kind=='eye'then state.lastAlpha=state.timer%12<6 and 70 or state.alpha;r.b:set('NPC','alpha',n,state.lastAlpha,'int32')end
  if state.timer<=0 then
   restore(r,n,state)
   if a.kind~='jump' and a.kind~='golem' and a.kind~='walker' and not (a.kind=='queen' and state.stage=='ground') then
    local ax,ay=dx,dy
    local pvx,pvy=r.b:vec('Player','velocity',player)
    local lead=state.approach=='intercept' and 10 or 0
    ax=ax+math.max(-80,math.min(80,(pvx or 0)*lead));ay=ay+math.max(-60,math.min(60,(pvy or 0)*lead))
    if state.approach=='retreat' then ax=-dx;ay=-dy
    elseif state.approach=='flank' or state.approach=='reposition' then ax=dx*.35+state.side*160;ay=dy-120 end
    local len=math.sqrt(ax*ax+ay*ay)
    if len<1 then release(r,n,state,'target_overlap');return end
    state.vx=ax/len*state.speed;state.vy=ay/len*state.speed;state.aimX=ax/len;state.aimY=ay/len
   end
   state.phase='motion';state.timer=a.duration;state.startX=x;state.startY=y
   local ok,reason=writeMotion(r,n,state,a,true)
   if not ok then release(r,n,state,reason or 'velocity_write_failed');return end
   r.log('BOSS_AUTO_FIRE','npc='..s.type..' action='..state.approach..' vx='..state.vx..' vy='..state.vy..' frames='..a.duration)
  end
  return
 end
 if (r.lastTick or 0)<state.due or (a.kind~='jump' and a.kind~='golem' and a.kind~='walker' and not (a.kind=='queen' and state.stage=='ground') and (r.lastTick or 0)%15~=slot%15) then return end
 if distance<a.min or distance>a.max then
  if not state.lastRangeLog or (r.lastTick or 0)-state.lastRangeLog>=300 then
   state.lastRangeLog=r.lastTick;r.log('BOSS_AUTO_BLOCK','npc='..s.type..' reason=distance distance='..math.floor(distance))
  end
  return
 end
 if a.kind=='worm' or a.kind=='plant' then
  local vx,vy=r.b:vec('NPC','velocity',n);local speed=vx and vy and math.sqrt(vx*vx+vy*vy) or 0
  if speed<(a.kind=='plant' and .5 or 2) or speed>(a.kind=='plant' and 12 or 40) or (vx*dx+vy*dy)/(speed*distance)<-.25 then return end
 end
 local speed=a.speed*(({easy=.8,normal=1,crazy=1.22})[r.cfg.difficulty]or 1)
 state.charges=(state.charges or 0)+1;local side=state.charges%2==1 and 1 or -1;state.approach='direct';state.side=side;state.speed=speed
 if a.kind=='jump' or a.kind=='golem' or a.kind=='walker' or (a.kind=='queen' and state.stage=='ground')then
  if math.abs(dx)<80 or math.abs(dy)>180 then return end
  state.approach='jump';state.vx=(dx<0 and -1 or 1)*speed
  state.vy=a.kind=='walker' and 0 or -(a.jumpVY or (({easy=7,normal=8,crazy=9})[r.cfg.difficulty]or 8))
  if a.kind=='walker' then state.approach='pressure' end
 else
  if a.kind=='worm' or a.kind=='plant' then state.approach='steer'
  elseif a.kind=='bee' or a.kind=='queen' then
   dx=dx*.35+side*160;dy=dy-100;state.approach='reposition'
  elseif (a.kind=='brain'or a.kind=='head'or a.kind=='prime'or a.kind=='laser')and distance<180 then dx=-dx;dy=-dy;state.approach='retreat'
  elseif a.kind=='laser' then
   dx=dx*.35+side*180;dy=dy-150;state.approach='reposition'
  elseif a.kind=='prime' then
   dx=dx*.35+side*180;dy=dy-120;state.approach='reposition'
  elseif a.kind=='head' or (a.kind=='brain' and state.lastApproach~='flank')then
   dx=dx*.35+side*160;dy=dy-120;state.approach=a.kind=='head' and 'reposition' or 'flank'
  elseif math.abs(dx)<100 and math.abs(dy)>180 then
   dx=side*math.max(140,math.abs(dy)*.55);state.approach='flank'
  end
  if state.approach=='direct' then state.approach=a.kind=='worm' and 'steer' or 'intercept' end
  local length=math.sqrt(dx*dx+dy*dy);if length<1 then return end
  state.vx=dx/length*speed;state.vy=dy/length*speed
 end
 state.lastApproach=state.approach
 state.alpha=r:n(n,'alpha','int32',0);state.phase='warning';state.timer=math.max(24,a.warning-(r.cfg.difficulty=='crazy' and 8 or 0));state.paused=0;state.warningDeadline=(r.lastTick or 0)+360
 r.log('BOSS_AUTO_PREPARE','npc='..s.type..' distance='..math.floor(distance)..' warning='..state.timer..' approach='..state.approach)
 local text=state.approach=='pressure' and '正在准备逼近！' or state.approach=='steer' and '正在调整截击路线！' or state.approach=='flank' and '正在准备侧袭！' or state.approach=='jump'and '正在蓄势跳跃！'or state.approach=='retreat'and '正在准备撤离！'or state.approach=='reposition'and '正在准备侧向换位！'or '正在蓄势追击！'
 r:notice(a.name..text,{255,160,160},'boss:auto:'..slot)
end
return B
