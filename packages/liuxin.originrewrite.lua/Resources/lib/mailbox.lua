local M={};M.__index=M
function M.new(r)
 local self=setmetatable({r=r},M)
 if r.store and not r.store.data.hostId then r.store.data.hostId=require('statefile').token();r.store:save()end
 return self
end
function M:complete(q)
 local r=self.r;local key=q.key;local store=r.store
 if not store or not key then return nil end
 local oldStatus,oldRemaining,oldTicket=q.status,q.remaining,q.ticket
 local nextSerial=store.data.serial+1;local ticket=store.data.hostId..'_'..nextSerial
 local size=0;local settled={}
 for id,row in pairs(store.data.mail)do size=size+1;if row.state=='claimed'then settled[#settled+1]={id=id,serial=row.serial or 0}end end
 table.sort(settled,function(a,b)return a.serial<b.serial end)
 while size>=512 and #settled>0 do store.data.mail[table.remove(settled,1).id]=nil;size=size-1 end
 if size>=512 then r.log('MAIL_FULL','claim outstanding rewards first');return nil end
 local row={owner=key,world=r.world,serial=nextSerial,state='pending',rewards=require('statefile').clone(q.selected.rewards),text=q.selected.rewardText}
 store.data.mail[ticket]=row;local oldSerial=store.data.serial;store.data.serial=nextSerial
 q.status='waiting';q.remaining=(r.cfg.contractRefreshMinutes or 3)*3600;q.ticket=ticket;q.rewardClaimed=false
 local prior=store.data.contracts[key];store.data.contracts[key]=q:export()
 if not store:save()then
  store.data.mail[ticket]=nil;store.data.serial=oldSerial;store.data.contracts[key]=prior
  q.status,q.remaining,q.ticket=oldStatus,oldRemaining,oldTicket;return nil
 end
 return ticket
end
function M:oldest(owner)
 local id,best
 for ticket,row in pairs(self.r.store.data.mail)do
  if row.owner==owner and row.state~='claimed'and(not best or row.serial<best.serial)then id,best=ticket,row end
 end
 return id,best
end
function M:claim()
 local r=self.r;if not r.store or not r.identity or not r:authority()or not r:player()then return false end
 local key=r.identity:key();local ticket,row
 if key then ticket,row=self:oldest(key)end
 if not row then r:notice('【个人奖励】没有待领取奖励',{180,230,255},'mail');return true end
 if row.state=='review'then r:notice('【个人奖励】上次发放异常中断，已保留待核对记录，暂不重复发放。请提供日志。',{255,180,130},'mail');return true end
 local previous=row.state;row.state='issued'
 if not r.store:save()then row.state=previous;r:notice('【个人奖励】存档写入失败，奖励保留待领',{255,180,130},'mail');return true end
 if r:w('netMode','int32',-1)==2 then
  if r.playerOverride==nil or not r.net or not r.net.peers[r.playerOverride]then return false end
  local token=r.identity:token();local payload=ticket..','..token..','..require('netcodec').hex(require('statefile').encode(row.rewards))
  r.net:send('R',payload,r.playerOverride)
 else
  local status=r.inventoryReward:apply(ticket,r.identity:token(),row.rewards)
  self:ack(ticket,status,key)
 end
 return true
end
function M:ack(ticket,status,owner)
 local r=self.r;local row=r.store and r.store.data.mail[ticket]
 if not row or row.owner~=owner or row.world~=r.world or row.state=='claimed'then return end
 if row.state~='issued'then return end
 if status=='ok'then row.state='claimed'
 elseif status=='review'then row.state='review'
 elseif({full=true,dead=true,unavailable=true,storage=true,invalid=true})[status]then row.state='pending'
 else return end
 if not r.store:save()then r.log('MAIL_ACK_SAVE_FAILED','ticket='..ticket);return end
 local message=status=='ok'and '奖励已进入个人背包，其他玩家无法抢走。'or status=='full'and '背包空位不足，奖励保留。腾出空位后输入 /领取。'or status=='review'and '发放中断，保留待核对记录，暂不重复发放。'or '当前发放接口或存档不可用，奖励保留待领。'
 r:notice('【个人奖励】'..message,{180,230,255},'mail')
 r.log('MAIL_ACK','ticket='..ticket..' status='..status)
end
return M
