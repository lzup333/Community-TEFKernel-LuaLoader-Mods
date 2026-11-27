-- Shared context scoring for assigned skills; no per-NPC AI replacement.
local D={}
function D.context(r,n,s,x,y,px,py)
 local c=s.combat;local life=r:n(n,'life','int32',0)
 if c.observedLife and life<c.observedLife then c.hurtClock=c.clock end
 c.observedLife=life
 if c.observedX then c.still=((x-c.observedX)^2+(y-c.observedY)^2<4)and ((c.still or 0)+1)or 0 end
 c.observedX=x;c.observedY=y
 local w=r:n(n,'width','int32',16);local h=r:n(n,'height','int32',16)
 local blocked=false
 if r.empty and require('ori_styles').canMove(r,n)then
  local left,top=r.b:vec('NPC','position',n)
  if left then blocked=not require('ori_actions').clear(r,n,left+(px>=x and 24 or -24)+1,top+1,math.max(1,w-2),math.max(1,h-3))end
 end
 return {style=s.style,dx=px-x,dy=py-y,distance=math.sqrt((px-x)^2+(py-y)^2),blocked=blocked,stuck=(c.still or 0)>=3,hurt=c.hurtClock and c.clock-c.hurtClock<120,weak=life/math.max(1,r:n(n,'lifeMax','int32',1))<.6,ground=not r:n(n,'noGravity','bool',true)}
end
function D.score(action,ctx,r,s,n)
 if action=='summon'then
  local total,own=0,0
  for _,entry in pairs(r.helpers or{})do total=total+1;if entry.parent==r:slot(n)and entry.parentGeneration==s.generation then own=own+1 end end
  return total<4 and own<2 and ctx.distance>=90 and 70 or nil
 end
 return require('ori_native_backend').score(action,ctx)
end
function D.choose(r,n,s,x,y,px,py)
 local c=s.combat
 if c.clock<(c.nextDecision or 0)then return false end
 c.nextDecision=c.clock+12+(r:slot(n)%6)
 if c.clock<(c.lockUntil or 0)then return false end
 local ctx=D.context(r,n,s,x,y,px,py)
 local slot=r:slot(n);ctx.helperTotal=0;ctx.helperOwn=0
 for _,entry in pairs(r.helpers or{})do
  ctx.helperTotal=ctx.helperTotal+1
  if entry.parent==slot and entry.parentGeneration==s.generation then ctx.helperOwn=ctx.helperOwn+1 end
 end
 local best=require('ori_native_backend').choose(c,s.recipes,r.collector and r.collector.blocked or{},r.random,ctx)
 if not best then return false end
 c.active=best.key;c[best.key].index=best.index
 require('ori_echo').activate(s,best.recipe);require('ori_combatplans').refresh(s)
 if not c.lastDecisionLog or c.clock-c.lastDecisionLog>=300 then
  c.lastDecisionLog=c.clock;r.log('AI_DECISION','slot='..r:slot(n)..' action='..s.action..' distance='..math.floor(ctx.distance)..' blocked='..tostring(ctx.blocked))
 end
 return true
end
return D
