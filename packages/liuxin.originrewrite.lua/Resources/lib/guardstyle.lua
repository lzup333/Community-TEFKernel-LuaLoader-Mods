local G={}
function G.clear(r,n,s)
 if s.guardApplied and r:n(n,'defense','int32',0)==s.guardApplied then r.b:set('NPC','defense',n,s.guardBase,'int32')end
 s.guardApplied=nil;s.guardBase=nil;s.guardTicks=nil;s.guardCounter=false
end
function G.start(r,n,s)
 s.guardBase=r:n(n,'defense','int32',0)
 local bonus=s.stage==1 and(s.tier==1 and 2 or 4)or({4,8,12})[s.tier]
 bonus=math.max(1,math.floor(bonus*require('difficulty').get(r.cfg).bonus+.5))
 s.guardApplied=s.guardBase+bonus;s.guardTicks=90;s.phase='guard';s.guardCounter=false
 r.b:set('NPC','defense',n,s.guardApplied,'int32')
 if r.net then r.net:publishNPC(n,s)end
 r.log('GUARD_START','slot='..r:slot(n)..' frames=90 bonus='..bonus)
end
function G.update(r,n,s)
 local actual=r:n(n,'defense','int32',0)
 if actual~=s.guardApplied and actual~=s.guardBase then G.clear(r,n,s);return false end
 r.b:set('NPC','defense',n,s.guardApplied,'int32');s.guardTicks=s.guardTicks-1
 if s.guardTicks>0 then return true end
 G.clear(r,n,s);s.guardCounter=true;s.echoWarning=true;s.phase='telegraph';s.timer=require('difficulty').warning(r.cfg,s)
 if r.net then r.net:publishNPC(n,s)end
 r.log('GUARD_COUNTER','slot='..r:slot(n)..' warning='..s.timer)
 return true
end
return G
