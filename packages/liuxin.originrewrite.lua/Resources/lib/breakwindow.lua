local W={};W.__index=W
function W.new(r)return setmetatable({r=r,stack={}},W)end
function W:hit(n,args,result,record)
 local r=self.r
 if not record or not r.cfg.breakWindow or not r.cfg.ai or not r:authority() then return end
 local slot=r:slot(n);local s=r.states[slot]
 if not s or s.generation~=record.generation or r.session~=record.session or not r:sameSlot(n,slot)then return end
 if not s.breakable or not s.echoWarning or s.phase~='telegraph' or(r.lastTick or 0)>(s.breakUntil or 0)then return end
 local life=r:n(n,'life','int32',0)
 if life<=0 or not r:n(n,'active')then return end
 local damage=math.max(0,record.life-life)
 if type(result)=='number'then damage=math.max(damage,result)end
 if damage<math.max(1,math.floor((s.base and s.base.max or 100)*.01))then return end
 local localIndex=r:w('myPlayer','int32',-1);local owner=args[6]
 if r:w('netMode','int32',-1)==2 then
  local players=r:w('player','object',nil);local credit=type(owner)=='number'and owner>=0 and owner or r:n(n,'lastInteraction','int32',-1)
  if not players or credit<0 or credit>=r.b.p.array_length(players)then return end
 else
  if localIndex<0 or args[5]==true then return end
  if type(owner)=='number'and owner>=0 then if owner~=localIndex then return end
  elseif r:n(n,'lastInteraction','int32',-1)~=localIndex then return end
 end
 require('echo').interrupt(r,n,s)
 r:notice('【破招成功】'..(s.displayName or '重构体')..'的蓄势被打断',{255,215,110},'break:'..slot)
 r.log('BREAK_SUCCESS','slot='..slot..' damage='..damage)
end
function W.install(r)
 local w=W.new(r);r.breaker=w
 local b=r.b
 local method=b:exact('NPC','StrikeNPC',{'int32','float','int32','bool','bool','int32'},false)
 if not method then r.log('BREAK_ROUTE','available=false');return w end
 local hook=b.p.install_hook(method,{
  prefix=function(n)
   local s=r.states[r:slot(n)]
   w.stack[#w.stack+1]=s and s.breakable and {generation=s.generation,session=r.session,life=r:n(n,'life','int32',0)}or false
   return false
  end,
  postfix=function(n,args,result)
   local record=table.remove(w.stack)
   local ok,err=pcall(w.hit,w,n,args,result,record)
   if not ok then r.log('BREAK_ERROR',tostring(err))end
  end,
 })
 if hook then b.hooks[#b.hooks+1]=hook end
 w.available=hook~=nil;r.log('BREAK_ROUTE','available='..tostring(w.available))
 return w
end
return W
