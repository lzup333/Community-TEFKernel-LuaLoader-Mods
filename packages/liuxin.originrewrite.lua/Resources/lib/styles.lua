local S={}
S.names={hunter='猎杀',pressure='压制',trick='诡变',guard='守御'}
function S.canMove(r,n)
 return r.empty and r.cfg.actions and not r:n(n,'noTileCollide','bool',true) and r:n(n,'width','int32',100)<=64 and r:n(n,'height','int32',100)<=80
end
function S.assign(r,n,s)
 if not r.cfg.combatStyles then return end
 local roll=r.random()
 s.style=roll<.25 and S.canMove(r,n)and'hunter'or roll<.5 and'pressure'or roll<.75 and'trick'or'guard'
 r.log('COMBAT_STYLE','slot='..r:slot(n)..' style='..s.style)
end
function S.observe(r,s,px,py)
 if s.style~='trick' then return end
 local now=r.lastTick or 0
 if not s.sampleTick or now-s.sampleTick>=30 then
  s.oldAim=s.lastAim;s.lastAim={px,py};s.sampleTick=now
 end
end
function S.ready(s,distance)
 if s.style=='hunter' and s.action~='echo' then return distance<=220*220 end
 if s.style=='pressure' then return distance>=100*100 end
 return true
end
function S.aim(r,s,x,y,px,py,player)
 if s.style=='trick' and s.oldAim then px,py=s.oldAim[1],s.oldAim[2]
 elseif s.style=='pressure' and s.pattern=='封路' then
  local vx=r.b:vec('Player','velocity',player)
  px=px+(vx and math.abs(vx)>.2 and(vx>0 and 72 or -72)or(px>x and 72 or -72))
 end
 return px,py
end
return S
