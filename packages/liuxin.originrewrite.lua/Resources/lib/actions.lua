local A={}
function A.install(r)
 local b=r.b;local p=b.p
 b.types.Collision=p.get_type('Terraria','Collision')
 r.empty=b:exact('Collision','EmptyTile',{'int32','int32','bool'},true)
 r.solid=nil;r.wet=nil
 r.log('ACTION_ROUTE','empty_tile='..tostring(r.empty~=nil)..' motion=vanilla_collision scalar_only=true')
end
function A.clear(r,n,x,y,w,h)
 if not r.empty then return false end
 local xmax=r:w('maxTilesX','int32',0)*16;local ymax=r:w('maxTilesY','int32',0)*16
 if x<32 or y<32 or x+w>xmax-32 or y+h>ymax-32 then return false end
 local p=r.b.p
 -- EmptyTile返回true才允许通过，避免SolidCollision调用失败也返回false的歧义。
 for tx=math.floor(x/16),math.floor((x+w-1)/16) do
  for ty=math.floor(y/16),math.floor((y+h-1)/16) do if p.invoke(r.empty,tx,ty,false)~=true then return false end end
 end
 return true
end
function A.prepare(r,n,s,x,y,px,py)
 local w=r:n(n,'width','int32',16);local h=r:n(n,'height','int32',16)
 s.tx=px+(x<px and -110 or 110)-w/2;s.ty=py-h/2
 if s.action=='blink'or s.action=='illusion'or s.action=='summon'then return true end
 return true
end
function A.start(r,n,s)
 if s.action=='blink'or s.action=='illusion'or s.action=='summon'then local success,reason=require('specialactions').start(r,n,s);if not success then r.log('SPECIAL_CANCEL','slot='..r:slot(n)..' action='..s.action..' reason='..tostring(reason or 'unknown'))end;return false,success end
 s.phase='motion';s.motionTicks=0;s.motionLimit=24;s.motionEndReason=nil
 s.motionStartX,s.motionStartY=r.b:vec('NPC','position',n)
 s.motionX=math.cos(s.echoAngle)*(s.stage==1 and 6 or 8)
 s.motionY=s.action=='pounce' and(s.stage==1 and -6 or -8)or r:n(n,'noGravity','bool',false) and math.sin(s.echoAngle)*(s.stage==1 and 6 or 8) or 0
 -- Ground pounce must retain horizontal reach even when aiming up/down.
 if s.action=='pounce' then
  s.motionX=(math.cos(s.echoAngle)<0 and -1 or 1)*(s.stage==1 and 6 or 8)
 end
 if s.action=='retreat'then s.motionX=(math.cos(s.echoAngle)<0 and 1 or -1)*(s.stage==1 and 6 or 8);s.motionY=0;s.motionLimit=20 end
 -- Ground dash uses horizontal direction, not the vertical aim projection.
 if s.action=='dash' and not r:n(n,'noGravity','bool',false) then
  local speed=s.stage==1 and 8 or 10
  s.motionX=(math.cos(s.echoAngle)<0 and -1 or 1)*speed
  s.motionY=0;s.motionLimit=32
 end
 s.motionLastX,s.motionLastY=s.motionStartX,s.motionStartY;s.motionStall=0
 r.b:putvec('NPC','velocity',n,s.motionX,s.motionY)
 r.log('ACTION_FIRE','slot='..r:slot(n)..' action='..s.action..' vx='..s.motionX..' vy='..s.motionY..' frames='..s.motionLimit)
 return true
end
function A.update(r,n,s)
 local x,y=r.b:vec('NPC','position',n)
 s.motionTicks=s.motionTicks+1
 if not x or not y then s.motionEndReason='position_missing';return false end
 if s.motionTicks>(s.motionLimit or 24)then s.motionEndReason='duration';return false end
 local dx=s.motionLastX and x-s.motionLastX or 0;local dy=s.motionLastY and y-s.motionLastY or 0
 s.motionLastX,s.motionLastY=x,y
 -- Observe the engine's actual displacement instead of rejecting occupied tile rectangles.
 if s.motionTicks>1 then
  s.motionStall=dx*dx+dy*dy<2.25 and ((s.motionStall or 0)+1)or 0
  if s.motionStall>=4 then s.motionEndReason=r:n(n,'collideX','bool',false)and 'wall_collision'or 'movement_stalled';return false end
 end
 if s.action=='pounce'then s.motionY=math.min(9,s.motionY+.45)
 elseif not r:n(n,'noGravity','bool',false)then
  local _,vy=r.b:vec('NPC','velocity',n);s.motionY=vy or s.motionY or 0
 end
 if s.motionTicks==6 then r.log('ACTION_PROGRESS','slot='..r:slot(n)..' action='..s.action..' dx='..(x-(s.motionStartX or x))..' dy='..(y-(s.motionStartY or y))..' route=vanilla_collision')end
 r.b:putvec('NPC','velocity',n,s.motionX,s.motionY)
 return true
end
return A
