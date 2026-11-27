-- Supplemental movement adapters, not replacements for native attack scripts.
-- Semantic sources: official Terraria Wiki pages Eater_of_Worlds, Wall_of_Flesh,
-- Empress_of_Light, Lunatic_Cultist, Moon_Lord. Idle AI windows are experimental.
local L={}
L.profiles={
 [13]={name='世界吞噬怪',style=6,kind='eater',warning=24,duration=16,min=180,max=620},
 [113]={name='血肉墙',style=27,kind='wall',warning=36,duration=12,min=240,max=660},
 [636]={name='光之女皇',style=120,kind='empress',warning=30,duration=6,min=220,max=620},
 [439]={name='拜月教邪教徒',style=84,kind='cultist',warning=30,duration=8,min=220,max=620},
 [398]={name='月亮领主',style=77,kind='moon',warning=36,duration=10,min=240,max=640},
}
local function release(r,state,reason)
 state.phase='idle';state.timer=0;state.due=(r.lastTick or 0)+(({easy=300,normal=240,crazy=180})[r.cfg.difficulty]or 240)
 if reason then r.log('BOSS_AUTO_CANCEL','npc='..state.type..' reason='..reason)end
end
local function window(r,n,p,a,phase)
 if r:n(n,'timeLeft','int32',750)<=60 then return false,'native_despawn' end
 if r:n(n,'dontTakeDamage','bool',true)then return false,'native_invulnerable' end
 if r:n(n,'alpha','int32',255)>60 then return false,'native_transparency' end
 if a.kind=='eater' and not r.b:get('Player','ZoneCorrupt',p,'bool',false)then return false,'outside_corruption' end
 if a.kind=='wall' and not r.b:get('Player','ZoneUnderworldHeight',p,'bool',false)then return false,'outside_underworld' end
 if a.kind=='empress' and r:w('dayTime','bool',true)then return false,'daytime_native_priority' end
 if (a.kind=='empress' and phase~=1)or ((a.kind=='cultist'or a.kind=='moon')and phase~=0)then return false,'native_attack' end
 local vx,vy=r.b:vec('NPC','velocity',n)
 if not vx or not vy then return false,'velocity_reader_unavailable' end
 local speed=math.sqrt(vx*vx+vy*vy)
 if a.kind=='wall'then return math.abs(vx)>=.5 and math.abs(vx)<=12,'native_speed_guard' end
 if a.kind=='eater'then return speed>=2 and speed<=20,'native_speed_guard' end
 if a.kind=='moon'then return speed>=.3 and speed<=8,'native_speed_guard' end
 return speed<=8,'native_speed_guard'
end
local function write(r,n,state,a,dx,dy)
 local vx,vy=r.b:vec('NPC','velocity',n)
 if not vx or not vy then return false,'velocity_reader_unavailable'end
 if a.kind=='wall'then
  if vx*state.baseVX<=0 then return false,'native_heading_guard'end
  if math.abs(vx)<math.abs(state.baseVX)*.8 then return false,'native_speed_guard'end
  state.vx=(vx<0 and -1 or 1)*math.min(math.abs(vx)+math.min(.25,math.abs(vx)*.04),math.abs(state.baseVX)*1.08)
  state.vy=vy
 elseif a.kind=='eater'or a.kind=='moon'then
  local speed=math.sqrt(vx*vx+vy*vy);local len=math.sqrt(dx*dx+dy*dy)
  if speed<.01 or len<1 then return false,'direction_degenerate'end
  local ux,uy=vx/speed,vy/speed;local tx,ty=dx/len,dy/len
  if ux*tx+uy*ty<-.25 then return false,'native_heading_guard'end
  local ax,ay=ux*.92+tx*.08,uy*.92+ty*.08;local norm=math.sqrt(ax*ax+ay*ay)
  state.vx=ax/norm*speed;state.vy=ay/norm*speed
 else
  -- Short lateral change of position; attack arrays remain untouched.
  local ax,ay=dx*.25+state.side*140,dy-80;local len=math.sqrt(ax*ax+ay*ay)
  if len<1 then return false,'direction_degenerate'end
  state.vx=ax/len*4;state.vy=ay/len*4
 end
 return r.b:putvec('NPC','velocity',n,state.vx,state.vy),nil
end
function L.update(r,n,s)
 local a=L.profiles[s.type];if not a or not r.cfg.bossAutoAI or r:w('netMode','int32',-1)~=0 then return end
 if r:n(n,'aiStyle','int32',-1)~=a.style then return end
 local slot=r:slot(n);r.bossAutoStates=r.bossAutoStates or {};local states=r.bossAutoStates;local state=states[slot]
 if not state or state.handle~=n or state.generation~=s.generation or state.session~=r.session or state.type~=s.type then
  state={handle=n,type=s.type,generation=s.generation,session=r.session,due=(r.lastTick or 0)+300,phase='idle',side=1};states[slot]=state
  r.log('BOSS_AUTO_BIND','npc='..s.type..' name='..a.name..' mode=experimental_late vanilla_attacks=true')
 end
 if state.tick==r.lastTick then return end;state.tick=r.lastTick
 local ai=r:n(n,'ai','object',nil)
 if not ai or not r.b.p.array_length or r.b.p.array_length(ai)<2 then if state.phase~='idle'then release(r,state,'ai_reader_unavailable')end;return end
 local phase=r.b.p.array_at(ai,0,'float');local step=r.b.p.array_at(ai,1,'float')
 if type(phase)~='number'or type(step)~='number'then if state.phase~='idle'then release(r,state,'invalid_ai_state')end;return end
 if state.native~=phase then state.native=phase;r.log('BOSS_AUTO_PHASE','npc='..s.type..' slot='..slot..' phase='..phase..' step='..step)end
 local stage=a.kind
 if a.kind=='moon'then stage=r:n(n,'dontTakeDamage','bool',true)and 'eyes' or 'core'
 elseif a.kind=='empress'then stage=r:n(n,'life','int32',0)/math.max(1,r:n(n,'lifeMax','int32',1))<=.5 and 'second' or 'first' end
 if stage~=state.stage then if state.stage and state.phase~='idle'then release(r,state,'encounter_stage_change')end;state.stage=stage;r.log('BOSS_AUTO_STAGE','npc='..s.type..' stage='..stage)end
 local p=r:player(n)
 if not p or r.b:get('Player','dead',p,'bool',false)then if state.phase~='idle'then release(r,state,'target_lost')end;return end
 local allowed,reason=window(r,n,p,a,phase)
 if not allowed then
  if state.phase~='idle'then release(r,state,reason)
  elseif (r.lastTick or 0)>=state.due and (not state.blockTick or r.lastTick-state.blockTick>=300)then
   state.blockTick=r.lastTick;r.log('BOSS_AUTO_BLOCK','npc='..s.type..' reason='..reason..' phase='..phase..' step='..step)
  end
  return
 end
 local x,y=r.b:vec('NPC','position',n);local px,py=r.b:vec('Player','position',p)
 if not x or not y or not px or not py then if state.phase~='idle'then release(r,state,'position_reader_unavailable')end;return end
 x=x+r:n(n,'width','int32',100)/2;y=y+r:n(n,'height','int32',100)/2
 px=px+r.b:get('Player','width',p,'int32',20)/2;py=py+r.b:get('Player','height',p,'int32',42)/2
 local dx,dy=px-x,py-y;local distance=math.sqrt(dx*dx+dy*dy)
 if distance>700 then if state.phase~='idle'then release(r,state,'target_out_of_range')end;return end
 if state.phase=='motion'then
  state.timer=state.timer-1
  if state.timer<=0 then release(r,state);r.log('BOSS_AUTO_END','npc='..s.type..' action='..state.action..' reason=duration dx='..string.format('%.1f',x-state.startX)..' dy='..string.format('%.1f',y-state.startY));return end
  local ok,why=write(r,n,state,a,dx,dy);if not ok then release(r,state,why or 'velocity_write_failed')end;return
 end
 if state.phase=='warning'then
  state.timer=state.timer-1
  if state.timer<=0 then
   state.baseVX=select(1,r.b:vec('NPC','velocity',n));state.startX=x;state.startY=y
   local ok,why=write(r,n,state,a,dx,dy)
   if not ok then release(r,state,why or 'velocity_write_failed');return end
   state.phase='motion';state.timer=a.duration
   r.log('BOSS_AUTO_FIRE','npc='..s.type..' action='..state.action..' vx='..state.vx..' vy='..state.vy..' frames='..a.duration)
  end;return
 end
 if r.lastTick<state.due or r.lastTick%15~=slot%15 or distance<a.min or distance>a.max then return end
 -- Only one split Eater head adds movement at a time. Native split AI remains simultaneous.
 if a.kind=='eater'then
  local arr=r:w('npc','object',nil)
  for otherSlot,other in pairs(states)do
   if otherSlot~=slot and other.type==13 and other.phase~='idle' and other.session==r.session then
    local otherNPC=arr and r.b.p.array_at(arr,otherSlot,'object')
    if otherNPC==other.handle and r:n(otherNPC,'active','bool',false)and r:n(otherNPC,'life','int32',0)>0 then return end
   end
  end
 end
 state.side=-state.side;state.action=a.kind=='wall'and 'advance' or (a.kind=='eater'or a.kind=='moon')and 'steer' or 'reposition'
 state.phase='warning';state.timer=a.warning
 r.log('BOSS_AUTO_PREPARE','npc='..s.type..' distance='..math.floor(distance)..' warning='..a.warning..' approach='..state.action)
 r:notice(a.name..(state.action=='advance'and '正在准备短暂推进！'or state.action=='steer'and '正在调整截击路线！'or '正在准备侧向换位！'),{255,160,160},'boss:auto:'..slot)
end
return L
