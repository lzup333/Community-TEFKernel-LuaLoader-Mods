local E={}
local Actions=require('actions')
local Styles=require('styles')
function E.activate(s,index)
 s.recipeIndex=index;if s.combat then s.combat.textPhase=nil end;local recipe=s.recipes[index]
 s.echo=recipe.echo;s.action=recipe.action;s.pattern=recipe.pattern
 if not recipe.headText then s.headText=nil;return end
 s.headText=(s.style and(require('styles').names[s.style]..' ')or'')..(#s.recipes>1 and (index..'/'..#s.recipes..' ') or '')..recipe.headText
end
function E.assign(r,n,s)
 return require('combatplans').assign(r,n,s)
end
-- ID来自目标版本ProjectileID/NPCID；仅移植附加招式，不替换整个NPC.AI。
E.moves=require('catalog')
function E.choose(random,npcType,collector,stage,exclude)
 stage=stage or 5
 local all={};local seen={}
 for _,m in ipairs(E.moves) do all[#all+1]=m;seen[m.donor..':'..m.projectile]=true end
 if collector then for _,m in ipairs(collector.moves) do if not seen[m.donor..':'..m.projectile] then all[#all+1]=m;seen[m.donor..':'..m.projectile]=true end end end
 local pool={};for _,m in ipairs(all) do if (not exclude or m.projectile~=exclude.projectile) and m.donor~=npcType and (m.minStage or 1)<=stage and not (collector and collector.blocked[m.key or (m.donor..':'..m.projectile)]) then pool[#pool+1]=m end end
 if #pool==0 then return nil end
 return pool[math.min(#pool,1+math.floor(random()*#pool))]
end
function E.next(s,collector)
 if not s.recipes then return false end
 for offset=1,#s.recipes do
  local index=((s.recipeIndex or 1)-1+offset)%#s.recipes+1;local recipe=s.recipes[index]
  local blocked=recipe.action=='echo' and recipe.echo and collector and collector.blocked[recipe.echo.key]
  if not recipe.disabled and not blocked then E.activate(s,index);return true end
 end
 return false
end
function E.cooldown(r,s)
 return require('difficulty').cooldown(r.cfg,s)
end
local function reset(r,n,s,completed)
 require('guardstyle').clear(r,n,s)
 if s.phase=='motion' then
  local x,y=r.b:vec('NPC','position',n)
  r.log('ACTION_END','slot='..r:slot(n)..' action='..tostring(s.action)..' ticks='..tostring(s.motionTicks)..' dx='..tostring(x and s.motionStartX and x-s.motionStartX)..' dy='..tostring(y and s.motionStartY and y-s.motionStartY)..' reason='..tostring(s.motionEndReason or 'reset'))
  r.b:putvec('NPC','velocity',n,0,0)
  s.motionEndReason=nil
 end
 s.secondShot=false;s.breakable=false
 if s.echoWarning then r.b:set('NPC','alpha',n,s.alpha or 0,'int32') end
 s.echoWarning=false;s.phase='cooldown'
 if s.combat then require('combatplans').finish(r,s,completed);return end
 if completed and not s.combat and s.recipes and #s.recipes>1 then E.next(s,r.collector);r.log('ECHO_ROTATE','slot='..r:slot(n)..' next='..s.recipeIndex) end
 s.timer=E.cooldown(r,s)
end
function E.interrupt(r,n,s)
 s.motionEndReason='interrupted';reset(r,n,s,true);s.phase='recover';s.timer=s.combat and(require('difficulty').get(r.cfg).name=='疯狂'and 30 or 45)or 90;s.breakable=false
end
function E.fail(r,n,s,reason)
 local recipe=s.recipes and s.recipes[s.recipeIndex or 1]
 local failedAction=s.action;local failedMove=s.echo
 if recipe then recipe.disabled=true end
 if failedAction=='echo'and failedMove and r.collector then r.collector:disable(failedMove)end
 reset(r,n,s,false)
 if not s.combat then s.echoFailed=not E.next(s,r.collector);s.timer=E.cooldown(r,s)end
 r.log('RECIPE_DISABLED','slot='..r:slot(n)..' all_disabled='..tostring(s.echoFailed)..' reason='..tostring(reason))
end

function E.fire(r,n,s,x,y)
 local arr=r:w('projectile','object',nil);if not arr or not r.projectile then return false end
 local source
 if r.projectileModern then
  source=r.b.p.invoke(r.projectileSource,n)
  if not source or source==false then r.log('ECHO_FAILED','source unavailable');return false end
 end
 local move=s.echo;local sourceDamage=r:n(n,'damage','int32',0)
 local damage=math.max(1,math.floor(sourceDamage*(s.stage==1 and require('difficulty').get(r.cfg).earlyProjectile or require('difficulty').get(r.cfg).projectile)/100))
 if sourceDamage<=0 then return false end
 local count=(s.shotSingle or s.pattern=='单发') and 1 or math.min(2,move.count)
 if s.pattern=='夹击' or s.pattern=='封路'then count=2 end
 damage=math.max(1,math.floor(damage/(s.pattern=='逐次锁定' and 2 or count)))
 local reserved=r.budget and r.budget:reserve(count)or count
 if reserved==0 then return false,'budget'end
 count=reserved
 local ok,result,reason=pcall(function()
 for i=1,count do
  local sx,sy=x,y
  local angle=s.echoAngle+(i-(count+1)/2)*(s.pattern=='封路'and .28 or move.spread)
  if s.pattern=='夹击' then
   local side=i==1 and -1 or 1
   sx=x-math.sin(s.echoAngle)*side*48;sy=y+math.cos(s.echoAngle)*side*48
   if r.empty and not Actions.clear(r,n,sx-4,sy-4,8,8) then sx,sy=x,y end
   angle=math.atan(s.aimY-sy,s.aimX-sx)
  end
  local vx,vy=math.cos(angle)*move.speed,math.sin(angle)*move.speed
  local index
  if r.projectileModern then index=r.b.p.invoke(r.projectile,source,sx,sy,vx,vy,move.projectile,damage,0,255,0,0,0,nil)
  else index=r.b.p.invoke(r.projectile,sx,sy,vx,vy,move.projectile,damage,0,255,0,0) end
  if type(index)~='number' or index<0 or index>=r.b.p.array_length(arr) then r.log('ECHO_FAILED','invalid slot='..tostring(index));return false end
  local shot=r.b.p.array_at(arr,index,'object')
  if not shot or r.b:get('Projectile','type',shot,'int32',0)~=move.projectile then r.log('ECHO_FAILED','projectile readback');return false end
  r.b:set('Projectile','friendly',shot,false,'bool');r.b:set('Projectile','hostile',shot,true,'bool')
  r.b:set('Projectile','damage',shot,damage,'int32')
  r.b:set('Projectile','tileCollide',shot,true,'bool')
  r.b:set('Projectile','penetrate',shot,1,'int32');r.b:set('Projectile','timeLeft',shot,180,'int32')
  if r.b:get('Projectile','damage',shot,'int32',-1)~=damage then r.b:set('Projectile','active',shot,false,'bool');r.log('ECHO_FAILED','damage readback; shot removed');return false end
  if r.budget then r.budget:track(index,shot,move.projectile)end
  if r.shotGuard then r.shotGuard:register(index,n,s,move.projectile)end
  if r.net then r.net:shot(index,n,s,move.projectile)end
 end
 if (s.echoLogs or 0)<3 then
  s.echoLogs=(s.echoLogs or 0)+1;r.log('ECHO_FIRE','slot='..r:slot(n)..' donor='..move.name..' projectile='..move.projectile..' count='..count..' source_damage='..sourceDamage..' damage='..damage..' cooldown='..(s.combat and 'see_SKILL_COOLDOWN' or E.cooldown(r,s))..' kind='..(move.kind or '自动招式')..' pattern='..(s.pattern or '原始'))
 end
 return true
 end)
 if r.budget then r.budget:release(reserved)end
 if not ok then error(result)end
 return result,reason
end
function E.update(r,n,s)
 s.action=s.action or 'echo'
 if (not s.echo and s.action=='echo') or s.echoFailed then return end
 if s.action=='echo' and r.collector and s.echo and r.collector.blocked[s.echo.key] then E.fail(r,n,s,'quarantined');return end
 -- NPC可能一帧执行多次AI，附加招式只按世界帧更新一次。
 if s.echoTick==r.lastTick then return end;s.echoTick=r.lastTick
 if s.combat then s.combat.clock=s.combat.clock+1;require('combatplans').refresh(s)end
 if s.phase=='recover'then s.timer=s.timer-1;if s.timer<=0 then reset(r,n,s,false)end;return end
 if s.breakable and(r.lastTick or 0)>(s.breakUntil or 0)then s.breakable=false end
 if not r.cfg.ai or (s.action~='echo' and not r.cfg.actions) or (s.action=='echo' and not r.projectile) then
  reset(r,n,s)
  if not r.projectile and not s.echoUnavailable then s.echoUnavailable=true;r.log('ECHO_UNAVAILABLE','projectile factory unavailable') end
  return
 end
 local p=r:player(n);local x,y=r.b:vec('NPC','position',n)
 local px,py
 if p then px,py=r.b:vec('Player','position',p) end
 if not x or not px or (px-x)^2+(py-y)^2>math.min(800,r.cfg.echoRange or 640)^2 then
  if s.echoWarning or s.phase=='motion'or s.phase=='guard'then
   s.motionEndReason='target_missing_or_out_of_range';reset(r,n,s)
  else s.timer=math.max(0,(s.timer or 0)-1)end
  if (s.action=='blink'or s.action=='summon'or s.action=='illusion')and(not s.specialWaitTick or (r.lastTick or 0)-s.specialWaitTick>=300)then
   s.specialWaitTick=r.lastTick or 0;r.log('SPECIAL_WAIT','slot='..r:slot(n)..' action='..s.action..' reason=target_out_of_range remaining='..tostring(s.timer))
  end
  return
 end
 x=x+r:n(n,'width','int32',16)/2;y=y+r:n(n,'height','int32',16)/2
 px=px+r.b:get('Player','width',p,'int32',20)/2;py=py+r.b:get('Player','height',p,'int32',42)/2
 Styles.observe(r,s,px,py)
 if s.phase=='guard'then
  if not require('guardstyle').update(r,n,s)then reset(r,n,s,false)end
  return
 end
 if s.phase=='motion' then
  if not Actions.update(r,n,s) then reset(r,n,s,s.motionEndReason=='duration'or(s.motionTicks or 0)>4) end
  return
 end
 s.timer=s.timer-1
 if s.echoWarning then
  r.b:set('NPC','alpha',n,math.min(180,(s.alpha or 0)+(math.floor(s.timer/8)%2)*90),'int32')
  if s.timer<=0 then
   r.b:set('NPC','alpha',n,s.alpha or 0,'int32');s.echoWarning=false
   if s.action=='guard'and not s.guardCounter then require('guardstyle').start(r,n,s);return end
   if s.action~='echo'and s.action~='guard' then
    local moving,success=Actions.start(r,n,s)
    if not moving then reset(r,n,s,success~=false) end
    return
   end
   s.shotSingle=s.pattern=='逐次锁定'
   r.echoGenerating=true
   local ok,result,reason=pcall(E.fire,r,n,s,x,y)
   r.echoGenerating=false
   if ok and not result and reason=='budget'then reset(r,n,s,false);s.timer=30;if not s.budgetWarning then s.budgetWarning=true;r.log('ECHO_BUDGET','slot='..r:slot(n)..' global_limit='..r.cfg.globalEchoLimit)end;return end
   s.budgetWarning=false
   if not ok or not result then E.fail(r,n,s,result);return end
   if ok and result and s.pattern=='逐次锁定' and not s.secondShot then
    s.secondShot=true;s.echoAngle=math.atan(py-y,px-x);s.aimX=px;s.aimY=py
    s.echoWarning=true;s.phase='telegraph';s.timer=45
   else s.secondShot=false;reset(r,n,s,ok and result) end
  end
 elseif s.timer<=0 then
  if s.combat then
   if not require('decision').choose(r,n,s,x,y,px,py)then s.timer=1;return end
  elseif not Styles.ready(s,(px-x)^2+(py-y)^2)then s.timer=15;return end
  -- 蓄势开始锁定方向，之后不追着玩家转，玩家可侧移躲避。
  if s.action~='echo' and not Actions.prepare(r,n,s,x,y,px,py) then reset(r,n,s);return end
  px,py=Styles.aim(r,s,x,y,px,py,p)
  s.aimX=px;s.aimY=py;s.echoAngle=math.atan(py-y,px-x);s.echoWarning=true;s.phase='telegraph'
  s.timer=require('difficulty').warning(r.cfg,s)
  if s.action=='blink'or s.action=='summon'or s.action=='illusion'then r.log('SPECIAL_PREPARE','slot='..r:slot(n)..' action='..s.action..' warning='..s.timer)end
  s.breakable=r.cfg.breakWindow and r.breaker and r.breaker.available and(s.action=='dash'or s.action=='pounce')or false
  s.breakUntil=(r.lastTick or 0)+(s.combat and require('difficulty').breakFrames(r.cfg,s)or s.timer)
  if s.action=='dash'or s.action=='pounce'then
   r.log('BREAK_WINDOW','slot='..r:slot(n)..' action='..s.action..' available='..tostring(s.breakable)..' frames='..((s.breakUntil or 0)-(r.lastTick or 0))..' warning='..s.timer..' headText='..tostring(r.cfg.headText))
  end
 end
end
return E
