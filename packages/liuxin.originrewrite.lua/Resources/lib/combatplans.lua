-- Independent action/projectile deadlines; a single executor prevents overlapping attacks.
local B={}
local names={dash='冲刺',pounce='扑击',retreat='后撤',guard='架势防御·反击',blink='短距闪现',summon='召唤援兵',illusion='虚影分身'}
local ranges={normal={action={{3.5,5},{2.5,4},{1.8,3}},shot={{10,14},{8,11},{6,9}}},crazy={action={{1.8,2.8},{1.2,1.8},{.8,1.3}},shot={{4.5,6},{3,4},{2,3}}}}
function B.cooldown(r,s,lane)
 local key=r.cfg.remoteDifficulty or r.cfg.difficulty or 'normal'
 local pair=(ranges[key]or ranges.normal)[lane][s.tier]
 local special=lane=='action'and ({blink=true,summon=true,illusion=true})[s.action]
 if special then
  local limits=key=='crazy'and {blink={3,5},summon={8,11},illusion={4,6}}or {blink={5,7},summon={12,16},illusion={6,9}}
  pair=limits[s.action]
 end
 local seconds=pair[1]+r.random()*(pair[2]-pair[1])
 if key=='easy'then seconds=seconds*1.3 end
 if s.stage==1 then seconds=seconds*1.3 end
 return math.floor(seconds*60+.5)
end
function B.gap(r)return (r.cfg.remoteDifficulty or r.cfg.difficulty)=='crazy'and 24 or 60 end
function B.refresh(s)
 local c=s.combat
 local ai=c.action and c.action.index;local si=c.shot and c.shot.index
 if c.textAction==ai and c.textShot==si and c.textActive==c.active and c.textPhase==s.phase and c.textCounter==s.guardCounter then return end
 c.textAction=ai;c.textShot=si;c.textActive=c.active;c.textPhase=s.phase;c.textCounter=s.guardCounter
 local lines={}
 for _,key in ipairs({'action','shot'})do
  local lane=c[key]
  if lane and #lane.indices>0 then
   local recipe=s.recipes[lane.indices[lane.index]]
   local status=c.active==key and(s.phase=='telegraph'and '蓄力'or s.phase=='motion'and '执行中'or s.phase=='guard'and '防御中'or s.guardCounter and '反击'or '')or ''
   lines[#lines+1]=(key=='action'and '行动：'or '弹幕：')..(#lane.indices>1 and lane.index..'/'..#lane.indices..' 'or '')..recipe.headText..(status~=''and ' · '..status or '')
  end
 end
 s.headText=table.concat(lines,'\n')
end
function B.select(r,s)
 local c=s.combat;local chosen
 for _,key in ipairs({'action','shot'})do
  local lane=c[key]
  if lane then
   for _=1,#lane.indices do
    local recipe=s.recipes[lane.indices[lane.index]]
    if not recipe.disabled and not(recipe.echo and recipe.action=='echo'and r.collector and r.collector.blocked[recipe.echo.key])then break end
    lane.index=lane.index%#lane.indices+1
   end
   local candidate=s.recipes[lane.indices[lane.index]]
   local blocked=candidate.echo and candidate.action=='echo'and r.collector and r.collector.blocked[candidate.echo.key]
   if not candidate.disabled and not blocked and(not chosen or lane.due<c[chosen].due)then chosen=key end
  end
 end
 if not chosen then s.echoFailed=true;return end
 c.active=chosen;require('echo').activate(s,c[chosen].indices[c[chosen].index])
 s.phase='cooldown';s.timer=math.max(1,c[chosen].due-c.clock,(c.lockUntil or 0)-c.clock);B.refresh(s)
end
function B.finish(r,s,completed)
 local c=s.combat;local lane=c[c.active]
 c.lastLane=c.active;c.lastRecipe=s.recipeIndex
 if not completed then c.failUntil=c.failUntil or {};c.failUntil[s.recipeIndex]=c.clock+90 end
 local delay=completed and B.cooldown(r,s,c.active)or 30
 lane.due=c.clock+delay
 r.log('SKILL_COOLDOWN','lane='..c.active..' action='..s.action..' frames='..delay..' seconds='..string.format('%.2f',delay/60)..' completed='..tostring(completed==true))
 if completed then lane.index=lane.index%#lane.indices+1 end
 c.lockUntil=c.clock+B.gap(r)
 -- Guard's counter is a projectile attack too: enforce the projectile deadline.
 if s.action=='guard'and completed and c.shot then c.shot.due=math.max(c.shot.due,c.clock+B.cooldown(r,s,'shot'));r.log('SKILL_COOLDOWN','lane=shot reason=guard_counter frames='..(c.shot.due-c.clock))end
 B.select(r,s)
end
function B.assign(r,n,s)
 local Echo=require('echo');s.recipes={};s.combat={clock=0}
 local movable=require('styles').canMove(r,n)
 local ground=not r:n(n,'noGravity','bool',true)
 local choices=movable and(ground and {'dash','pounce','retreat','guard'}or {'dash','retreat','guard'})or {'guard'}
 local special={}
 if s.stage>=2 and s.tier>=2 then
  if movable then special[#special+1]='blink' end
  if r.empty and r.npcFactory and r.npcSource then special[#special+1]='summon' end
  if r.empty and r.cfg.visuals~=false and r.heads and r.heads.ghostAvailable then special[#special+1]='illusion' end
 end
 if s.stage>=2 and s.tier>=2 then r.log('SPECIAL_POOL','slot='..r:slot(n)..' eligible='..(#special>0 and table.concat(special,',')or 'none')..' movable='..tostring(movable==true)..' factory='..tostring(r.npcFactory~=nil and r.npcSource~=nil)..' ghosts='..tostring(r.heads~=nil and r.heads.ghostAvailable==true))end
 local baseChoices={};for _,action in ipairs(choices)do baseChoices[#baseChoices+1]=action end
 for _,action in ipairs(special)do choices[#choices+1]=action end
 local function choose()
  if #special>0 and r.random()<(s.tier==3 and .4 or .25)then return special[math.min(#special,1+math.floor(r.random()*#special))]end
  if #baseChoices==4 then local x=r.random();return x<.3 and 'dash'or x<.6 and 'pounce'or x<.8 and 'retreat'or 'guard'end
  return baseChoices[math.min(#baseChoices,1+math.floor(r.random()*#baseChoices))]
 end
 if r.cfg.actions then
  local lane={indices={},index=1,due=(r.cfg.difficulty=='crazy'and 60 or 90)+math.floor(r.random()*(r.cfg.difficulty=='crazy'and 60 or 90))};s.combat.action=lane
  local first=choose();local count=s.tier==3 and #choices>1 and 2 or 1
  for i=1,count do
   local action=first
   if i==2 then local different={};for _,a in ipairs(choices)do if a~=first then different[#different+1]=a end end;action=different[math.min(#different,1+math.floor(r.random()*#different))]end
   s.recipes[#s.recipes+1]={action=action,echo=s.echo,pattern='单发',headText=names[action]};lane.indices[#lane.indices+1]=#s.recipes
  end
 end
 if s.echo then
  local lane={indices={},index=1,due=360+math.floor(r.random()*120)};s.combat.shot=lane
  local count=s.tier==3 and 2 or 1;local move=s.echo
  for i=1,count do
   if i==2 then move=Echo.choose(r.random,s.type,r.collector,s.stage,move)end
   if move then
    local patterns={'单发','扇射','夹击'};local pattern=s.tier==1 and '单发'or patterns[math.min(3,1+math.floor(r.random()*3))]
    s.recipes[#s.recipes+1]={action='echo',echo=move,pattern=pattern,headText=move.name..'·'..pattern};lane.indices[#lane.indices+1]=#s.recipes
   end
  end
 end
 local summaries={};for _,recipe in ipairs(s.recipes)do summaries[#summaries+1]=recipe.headText end;s.skillSummary=table.concat(summaries,' ↔ ')
 B.select(r,s);r.log('COMBAT_LOADOUT','slot='..r:slot(n)..' skills='..s.skillSummary..' independent_cooldowns=true')
end
return B
