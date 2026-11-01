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
 if r.empty and require('styles').canMove(r,n)then
  local left,top=r.b:vec('NPC','position',n)
  if left then blocked=not require('actions').clear(r,n,left+(px>=x and 24 or -24)+1,top+1,math.max(1,w-2),math.max(1,h-3))end
 end
 return {dx=px-x,dy=py-y,distance=math.sqrt((px-x)^2+(py-y)^2),blocked=blocked,stuck=(c.still or 0)>=3,hurt=c.hurtClock and c.clock-c.hurtClock<120,weak=life/math.max(1,r:n(n,'lifeMax','int32',1))<.6,ground=not r:n(n,'noGravity','bool',true)}
end
function D.score(action,ctx,r,s)
 local distance=ctx.distance
 if action=='echo'then return distance>=70 and 55 or 30
 elseif action=='dash'then return not ctx.blocked and distance>=80 and distance<=420 and math.abs(ctx.dy)<100 and 65 or nil
 elseif action=='pounce'then return not ctx.blocked and distance>=70 and distance<=360 and ctx.dy<90 and(ctx.dy<-40 and 85 or 58)or nil
 elseif action=='retreat'then return distance<180 and(ctx.hurt and 95 or 75)or nil
 elseif action=='guard'then return distance<=260 and(ctx.hurt or ctx.weak or distance<180)and(ctx.hurt and 85 or 50)or nil
 elseif action=='blink'then return (ctx.blocked or ctx.stuck or distance>280 or distance<100)and 80 or nil
 elseif action=='illusion'then return distance<420 and(ctx.hurt and 90 or 60)or nil
 elseif action=='summon'then
  local total,own=0,0
  for _,entry in pairs(r.helpers or {})do total=total+1;if entry.parent==r:slot(n)and entry.parentGeneration==s.generation then own=own+1 end end
  return total<4 and own<2 and distance>=90 and 70 or nil
 end
end
function D.choose(r,n,s,x,y,px,py)
 local c=s.combat
 if c.clock<(c.nextDecision or 0)then return false end
 c.nextDecision=c.clock+12+(r:slot(n)%6)
 if c.clock<(c.lockUntil or 0)then return false end
 local ctx=D.context(r,n,s,x,y,px,py);local best,score
 for _,key in ipairs({'action','shot'})do
  local lane=c[key]
  if lane and lane.due<=c.clock then
   for index,recipeIndex in ipairs(lane.indices)do
    local recipe=s.recipes[recipeIndex]
    local blocked=recipe.action=='echo'and recipe.echo and r.collector and r.collector.blocked[recipe.echo.key]
    if not recipe.disabled and not blocked and c.clock>=((c.failUntil or {})[recipeIndex]or 0)then
     local value=D.score(recipe.action,ctx,r,s)
     if value then
      value=value+math.min(25,(c.clock-lane.due)/30)+r.random()*15
      if c.lastRecipe==recipeIndex then value=value-15 end
      if c.lastLane=='action'and key=='shot'then value=value+15 end
      if not score or value>score then score=value;best={key=key,index=index,recipe=recipeIndex}end
     end
    end
   end
  end
 end
 if not best then return false end
 c.active=best.key;c[best.key].index=best.index
 require('echo').activate(s,best.recipe);require('combatplans').refresh(s)
 if not c.lastDecisionLog or c.clock-c.lastDecisionLog>=300 then
  c.lastDecisionLog=c.clock;r.log('AI_DECISION','slot='..r:slot(n)..' action='..s.action..' distance='..math.floor(ctx.distance)..' blocked='..tostring(ctx.blocked))
 end
 return true
end
return D
