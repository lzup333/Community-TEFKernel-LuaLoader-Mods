-- 私人奖励仅写对应本地人物背包；预检空位、持久化收据并回读，绝不落成共享物品。
local D={};D.__index=D
function D.new(r)
 local b=r.b;local method,argc,variantOnly
 for _,spec in ipairs({{2,{'int32',{'Terraria.GameContent.Items','ItemVariant'}},true},{2,{'int32',{'Terraria.GameContent.ItemVariants','ItemVariant'}},true},{3,{'int32','bool',{'Terraria.GameContent.ItemVariants','ItemVariant'}}},{2,{'int32','bool'}},{1,{'int32'}}})do
  method=b:exact('Item','SetDefaults',spec[2],false);if method then argc=spec[1];variantOnly=spec[3]==true;break end
 end
 local ready=method and b.p.new_instance and b.p.retain
 r.log('PRIVATE_REWARD_ROUTE','available='..tostring(ready~=nil and ready~=false)..' defaults_args='..tostring(argc)..' variant_only='..tostring(variantOnly))
 return setmetatable({r=r,method=method,argc=argc,variantOnly=variantOnly,ready=ready~=nil and ready~=false},D)
end
function D:defaults(item,id)
 local p=self.r.b.p
 local result
 if self.variantOnly then result=p.invoke(self.method,item,id,nil)
 elseif self.argc==3 then result=p.invoke(self.method,item,id,false,nil)
 elseif self.argc==2 then result=p.invoke(self.method,item,id,false)
 else result=p.invoke(self.method,item,id)end
 return result~=false
end
function D:plan(rewards)
 local r=self.r;local p=r:player();if not p then return nil,'dead'end
 local inv=r.b:get('Player','inventory',p,'object',nil);if not inv then return nil,'unavailable'end
 local plan,slots={},{};local limit=math.min(49,r.b.p.array_length(inv)-1)
 for slot=0,limit do
  local item=r.b.p.array_at(inv,slot,'object')
  if item then slots[slot]={item=item,type=r.b:get('Item','type',item,'int32',0),stack=r.b:get('Item','stack',item,'int32',0),max=r.b:get('Item','maxStack',item,'int32',0),prefix=r.b:get('Item','prefix',item,'uint8',0)}end
 end
 for _,reward in ipairs(rewards)do
  if type(reward.id)~='number'or reward.id%1~=0 or reward.id<1 or reward.id>10000 or type(reward.stack)~='number'or reward.stack%1~=0 or reward.stack<1 or reward.stack>99999 then return nil,'invalid'end
  local sample=r.b.p.new_instance(r.b.types.Item);if not sample then return nil,'unavailable'end;sample=r.b.p.retain(sample)
  if not self:defaults(sample,reward.id)or r.b:get('Item','type',sample,'int32',0)~=reward.id then return nil,'unavailable'end
  local max=r.b:get('Item','maxStack',sample,'int32',0);if max<1 or max>99999 then return nil,'unavailable'end
  local left=reward.stack
  -- 先合并无前缀的同种物品，再使用普通背包空格；不改已有物品属性。
  for pass=1,2 do
   for slot=0,limit do
    local v=slots[slot]
    local empty=v and(v.type==0 or v.stack<=0)
    local same=v and v.type==reward.id and v.prefix==0 and v.stack>0 and math.min(max,v.max)>v.stack
    if v and((pass==1 and same)or(pass==2 and empty))then
     local cap=empty and max or math.min(max,v.max);local amount=math.min(left,cap-(empty and 0 or v.stack))
     if amount>0 then
      if not v.entry then v.entry={slot=slot,id=reward.id,oldType=v.type,oldStack=v.stack,oldPrefix=v.prefix,initialize=empty};plan[#plan+1]=v.entry end
      v.type=reward.id;v.stack=(empty and 0 or v.stack)+amount;v.max=cap;v.prefix=0;v.entry.stack=v.stack;left=left-amount
     end
     if left==0 then break end
    end
   end
   if left==0 then break end
  end
  if left>0 then return nil,'full'end
 end
 return plan
end
function D:apply(ticket,owner,rewards)
 local r=self.r;if not r.store or not self.ready then return 'unavailable'end
 if owner~=r.identity:localToken()then return 'invalid'end
 local old=r.store.data.receipts[ticket]
 if old then return old.owner==owner and(old.state=='applied'and 'ok'or'review')or'invalid'end
 local count=0;for _ in pairs(r.store.data.receipts)do count=count+1 end;if count>=8192 then return 'full'end
 local ok,plan,reason=pcall(self.plan,self,rewards)
 if not ok then r.log('PRIVATE_REWARD_ERROR',tostring(plan));return 'unavailable'end
 if not plan then return reason end
 local receipt={owner=owner,world=r.world,state='prepared',plan=plan}
 r.store.data.receipts[ticket]=receipt
 if not r.store:save()then r.store.data.receipts[ticket]=nil;return 'storage'end
 local player=r:player();local inv=player and r.b:get('Player','inventory',player,'object',nil)
 local changed={}
 local applied,err=pcall(function()
  for _,entry in ipairs(plan)do
   local item=inv and r.b.p.array_at(inv,entry.slot,'object');if not item or r.b:get('Item','type',item,'int32',0)~=entry.oldType or r.b:get('Item','stack',item,'int32',0)~=entry.oldStack or r.b:get('Item','prefix',item,'uint8',0)~=entry.oldPrefix then error('inventory changed')end
   changed[#changed+1]=entry
   if(entry.initialize and not self:defaults(item,entry.id))or not r.b:set('Item','stack',item,entry.stack,'int32')or r.b:get('Item','type',item,'int32',0)~=entry.id or r.b:get('Item','stack',item,'int32',0)~=entry.stack then error('inventory readback')end
  end
 end)
 if not applied then
  local restored=true
  for _,entry in ipairs(changed)do
   local item=inv and r.b.p.array_at(inv,entry.slot,'object')
   local success=pcall(function()assert(item);if entry.initialize then assert(self:defaults(item,entry.oldType))end;assert(r.b:set('Item','stack',item,entry.oldStack,'int32'));assert(r.b:get('Item','type',item,'int32',-1)==entry.oldType)end)
   restored=restored and success
  end
  if restored then r.store.data.receipts[ticket]=nil;if not r.store:save()then r.store.data.receipts[ticket]=receipt;restored=false end end
  r.log('PRIVATE_REWARD_ROLLBACK',tostring(err)..' restored='..tostring(restored));return restored and 'unavailable'or'review'
 end
 receipt.state='applied';receipt.plan=nil
 if not r.store:save()then receipt.state='prepared';receipt.plan=plan;r.log('PRIVATE_REWARD_REVIEW','receipt save failed after inventory write');return 'review'end
 if r.net and r:w('netMode','int32',-1)==1 then
  for _,entry in ipairs(plan)do local ok,result=pcall(r.net.inventorySync,r.net,entry.slot);if not ok or result==false then r.log('PRIVATE_REWARD_SYNC_RETRY','inventory will use native resync')end end
 end
 r.log('PRIVATE_REWARD_APPLIED','ticket='..ticket..' slots='..#plan)
 return 'ok'
end
return D
