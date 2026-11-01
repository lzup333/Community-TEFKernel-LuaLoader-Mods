local Q={};Q.__index=Q
local C=require('core')
local titles={any='清剿',styles='追猎',tier='镇压',nohit='无伤',extreme='极限'}
local styles={hunter=true,pressure=true,trick=true,guard=true}
function Q.new(r)return setmetatable({r=r,status='idle',count=0,remaining=0,styles={}},Q)end
local function offerValid(o)
 if type(o)~='table'or not titles[o.kind]or type(o.goal)~='number'or o.goal%1~=0 or o.goal<1 or o.goal>100 or type(o.seconds)~='number'or o.seconds<60 or o.seconds>86400 or type(o.target)~='string'or #o.target>512 or type(o.rewardText)~='string'or #o.rewardText>768 or type(o.rewards)~='table'or #o.rewards<1 or #o.rewards>8 then return false end
 for _,v in ipairs(o.rewards)do if type(v)~='table'or type(v.id)~='number'or v.id%1~=0 or v.id<1 or v.id>10000 or type(v.stack)~='number'or v.stack%1~=0 or v.stack<1 or v.stack>99999 then return false end end
 return true
end
Q.offerValid=offerValid
function Q:export()
 local kinds={};for k,v in pairs(self.styles or {})do if styles[k]and v==true then kinds[k]=true end end
 return {status=self.status,offers=self.offers or {},selected=self.selected or false,count=self.count or 0,goal=self.goal or 0,remaining=math.max(0,self.remaining or 0),styles=kinds,rewardClaimed=self.rewardClaimed==true,ticket=self.ticket or false}
end
function Q:restore(row)
 if type(row)~='table'or not({idle=true,offered=true,active=true,waiting=true})[row.status]or type(row.remaining)~='number'or row.remaining<0 or row.remaining>5184000 or type(row.count)~='number'or row.count%1~=0 or row.count<0 or row.count>100 or type(row.goal)~='number'or row.goal<0 or row.goal>100 then return false end
 if row.status=='offered'then if type(row.offers)~='table'or #row.offers~=3 then return false end;for _,o in ipairs(row.offers)do if not offerValid(o)then return false end end end
 if row.status=='active'and not offerValid(row.selected)then return false end
 self.status=row.status;self.offers=type(row.offers)=='table'and row.offers or nil;self.selected=type(row.selected)=='table'and row.selected or nil
 self.count=row.count;self.goal=row.goal;self.remaining=row.remaining;self.rewardClaimed=row.rewardClaimed==true;self.ticket=type(row.ticket)=='string'and row.ticket or nil
 self.styles={};if type(row.styles)=='table'then for k,v in pairs(row.styles)do if styles[k]and v==true then self.styles[k]=true end end end
 self.lastLife=nil;self.settleDeadline=nil;self.finishAttempt=nil;return true
end
function Q:bind()
 local r=self.r;if not r.store or not r.identity then return true end
 local key=r.identity:key();if not key then return false end
 if self.key==key then return true end
 if self.key then self:checkpoint(true)end
 self.key=key;self.status='idle';self.offers=nil;self.selected=nil;self.count=0;self.goal=0;self.remaining=0;self.styles={};self.ticket=nil;self.lastLife=nil
 local row=r.store.data.contracts[key]
 if row and self:restore(require('statefile').clone(row))then r.log('CONTRACT_RESUME','status='..self.status..' count='..self.count..' ticks='..self.remaining);self:show()end
 return true
end
function Q:checkpoint(force)
 local r=self.r;if not r.store or not self.key then return false end
 if not force and self.savedTick and r.ticks-self.savedTick<300 then return true end
 r.store.data.contracts[self.key]=self:export()
 if not force then r.store.dirty=true;self.savedTick=r.ticks;return true end
 local ok=r.store:save();if ok then self.savedTick=r.ticks end;return ok
end
function Q:clear()
 if self.key then self:checkpoint(true)end
 self.key=nil;self.status='idle';self.offers=nil;self.selected=nil;self.rewardClaimed=false;self.ticket=nil;self.count=0;self.goal=0;self.remaining=0;self.styles={};self.lastLife=nil;self.savedTick=nil;self.settleDeadline=nil;self.finishAttempt=nil
end
function Q:wait(reason)
 self.status='waiting';self.remaining=(self.r.cfg.contractRefreshMinutes or 3)*3600;self.lastLife=nil;self:checkpoint(true)
 self.r:notice('【契约结束】'..reason..'；无惩罚，3分钟后刷新',{255,205,130},'contract')
end
function Q:generate()
 local r=self.r;local w=r:worldState();local mode=C.mode(w);local stage=C.stage(w)
 local base=({3,4,5,6,3})[mode];local minutes=({6,7,8,9,6})[mode]
 self.offers={};self.selected=nil;self.goal=0;self.status='offered';self.remaining=3*3600;self.count=0;self.styles={};self.rewardClaimed=false;self.ticket=nil;self.lastLife=nil;self.finishAttempt=nil;self.mailWarning=nil;self.settleDeadline=nil
 local used={}
 for i=1,3 do
  local pool=stage>1 and {'tier','styles','nohit','extreme'}or {'tier','styles','nohit'}
  if stage==1 and require('protection').profile(w).tier2==0 then pool={'any','nohit'}end
  if not r.hurtObserved then for j=#pool,1,-1 do if pool[j]=='nohit'then table.remove(pool,j)end end end
  local kind=i==1 and 'any'or pool[math.min(#pool,1+math.floor(r.random()*#pool))]
  if kind=='styles'and not r.cfg.combatStyles then kind='any'end
  if i==3 and kind==self.offers[2].kind and #pool>1 then for _,k in ipairs(pool)do if k~=kind then kind=k;break end end end
  local tier=stage>1 and i==3 and r.random()<.3 and 3 or 2
  local goal=kind=='any'and base+i-1+math.floor(r.random()*2)or kind=='tier'and math.max(1,math.floor(base/2)+i-2)or kind=='nohit'and math.min(4,base)or 2
  if kind=='tier'and tier==3 then goal=1 end
  local seconds=(minutes+(stage==1 and 2 or 0)+(i-1)*2)*60
  if kind=='extreme'then seconds=(4+(mode==5 and 0 or mode-1))*60;goal=2;tier=2 end
  local target=kind=='any'and('击败'..goal..'只任意重构体')or kind=='tier'and('击败'..goal..'只'..(tier==3 and'终焉体'or'灾变体'))or kind=='styles'and'击败2种不同战斗风格的重构体'or kind=='nohit'and('全程无伤击败'..goal..'只重构体（Boss战暂停）')or('限时击败'..goal..'只灾变体及以上；死亡失败')
  local o={kind=kind,goal=goal,tier=tier,seconds=seconds,target=target,letter=tostring(i)}
  o.rewards,o.rewardText,o.risk,o.rewardKind=require('contractrewards').generate(r.random,o,mode,stage,used)
  self.offers[i]=o;r.log('CONTRACT_REWARD','choice='..i..' kind='..kind..' risk='..o.risk..' reward='..o.rewardText)
 end
 self:checkpoint(true);self:show()
end
function Q:show()
 local r=self.r
 if self.status=='offered'and self.offers then
  local rows={};for i,o in ipairs(self.offers)do rows[#rows+1]='['..i..'] '..(titles[o.kind]or'猎杀')..'｜'..o.target..'\n'..math.floor(o.seconds/60)..'分钟 · '..({'低风险','中风险','高风险'})[o.risk or 1]..'｜奖励：'..o.rewardText end
  r:notice('【个人猎杀契约】\n'..table.concat(rows,'\n')..'\n/1、/2、/3 接取 · /领取 领取已完成奖励',{255,205,130},'contract:board')
 elseif self.status=='active'and self.selected then r:notice('【个人猎杀契约】'..self.selected.target..'\n进度 '..self.count..'/'..self.goal..'｜剩余 '..math.ceil(self.remaining/3600)..'分钟',{255,205,130},'contract')
 else r:notice('【个人猎杀契约】等待下一次刷新；/领取 领取已完成奖励',{255,205,130},'contract')end
end
function Q:command(text)
 if type(text)~='string'then return false end
 local r=self.r
 if text:match('^%s*/帮助%s*$')then r:notice('【起源重构】/1 /2 /3 接取契约；/任务 查看进度；/领取 领取奖励；/同步 联机补同步',{180,230,255},'help');return true end
 if text:match('^%s*/任务%s*$')then if r:w('netMode','int32',-1)==1 then return false end;if self:bind()then self:show()end;return true end
 if text:match('^%s*/同步%s*$')then if r:w('netMode','int32',-1)==1 then return false end;r:notice('【同步】单机无需联机同步',{180,230,255},'sync');return true end
 local key=text:match('^%s*/([123])%s*$');local claim=text:match('^%s*/领取%s*$')
 if not key and not claim then return false end
 if not r.cfg.enabled or not r.cfg.huntContract or not r:authority()or(r:w('netMode','int32',-1)==2 and r.playerOverride==nil)or r.world==nil then return false end
 if not self:bind()then return false end
 if claim then if r.mail then r.mail:claim()end;return true end
 if self.status~='offered'then self:show();return true end
 if not r:player()then return true end
 local o=self.offers[tonumber(key)];if not o then return true end
 self.selected=o;self.goal=o.goal;self.count=0;self.styles={};self.remaining=o.seconds*60;self.status='active';self.rewardClaimed=false;self.ticket=nil;self.lastLife=nil;self.finishAttempt=nil;self.mailWarning=nil;self.settleDeadline=nil
 self:checkpoint(true)
 r:notice('【已接取 '..o.letter..'】'..o.target..'\n时限：'..math.floor(o.seconds/60)..'分钟\n奖励：'..o.rewardText,{150,255,180},'contract')
 return true
end
function Q:health()
 local r=self.r;local arr=r:w('player','object',nil);local index=r.playerOverride or r:w('myPlayer','int32',-1)
 local p=arr and index>=0 and index<r.b.p.array_length(arr)and r.b.p.array_at(arr,index,'object')
 if not p or not r.b:get('Player','active',p,'bool',false)then return end
 return r.b:get('Player','statLife',p,'int32',nil),r.b:get('Player','dead',p,'bool',false)
end
function Q:onHurt()
 if self.status=='active'and self.selected and self.selected.kind=='nohit'and not self.r:w('gamePaused','bool',false)and not(self.r.bossDialog and self.r.bossDialog.active)then self:wait('无伤挑战中受到伤害')end
end
function Q:finish()
 local r=self.r
 if self.selected and(self.selected.kind=='nohit'or self.selected.kind=='extreme')then
  if not self.settleDeadline then self.settleDeadline=r.ticks+60;self:checkpoint(true);return false end
  if r.ticks<self.settleDeadline then return false end
 end
 if self.finishAttempt and r.ticks-self.finishAttempt<300 then return false end;self.finishAttempt=r.ticks
 if r.mail and self.key and r.cfg.contractRewards then
  local ticket=r.mail:complete(self)
  if not ticket then if not self.mailWarning then self.mailWarning=true;r:notice('【契约完成待保存】奖励和进度暂保留，正在等待存档恢复',{255,180,130},'contract')end;return false end
  if r.archive then r.archive:complete()end
  r:notice('【契约完成】'..self.selected.rewardText..'已记入个人待领奖励；输入 /领取。',{150,255,180},'contract');r.log('CONTRACT_COMPLETE','ticket='..ticket)
  return true
 end
 if r.store or r:w('netMode','int32',-1)==2 then
  if r.cfg.contractRewards then r.log('CONTRACT_SAVE_REQUIRED','reward retained');return false end
  self.status='waiting';self.remaining=(r.cfg.contractRefreshMinutes or 3)*3600;self:checkpoint(true);if r.archive then r.archive:complete()end;return true
 end
 self.status='waiting';self.remaining=(r.cfg.contractRefreshMinutes or 3)*3600
 if r.archive then r.archive:complete()end
 if r.cfg.contractRewards and not self.rewardClaimed then self.rewardClaimed=true;local p=r:player();local x,y=r.b:vec('Player','position',p);for _,v in ipairs(self.selected.rewards)do if x then r:giveItem(v.id,v.stack,x,y,20,40,'contract')end end end
 return true
end
function Q:update()
 local r=self.r;if not self:bind()then return end
 if not r.cfg.huntContract then self:clear();return end
 local life,dead=self:health()
 if self.status=='active'and self.selected and self.selected.kind=='nohit'and not r.hurtObserved then
  if not self.noHitInterfaceWarning then self.noHitInterfaceWarning=true;r:notice('【契约暂停】无伤判定接口暂不可用，进度已保留',{255,180,130},'contract')end
  return
 end
 if r:w('gamePaused','bool',false)or(r.bossDialog and r.bossDialog.active)then self.lastLife=life;return end
 if self.status=='active'and self.selected then
  if (self.selected.kind=='nohit'or self.selected.kind=='extreme')and dead then self:wait('挑战期间死亡');return end
  if self.selected.kind=='nohit'and life and self.lastLife and life<self.lastLife then self:onHurt();self.lastLife=life;return end
  self.lastLife=life
  if self.count>=self.goal then self:finish();return end
 end
 if self.status=='idle'then if r:player()and(self.inputAvailable~=false or(r.questUI and r.questUI.ready)) then self:generate()end;return end
 if not r:player()then return end
 self.remaining=self.remaining-1
 if self.remaining<=0 then
  if self.status=='waiting'or self.status=='offered'then self:generate()else self:wait('任务到期 '..self.count..'/'..self.goal)end
 elseif r.ticks%300==0 then self:checkpoint(false)end
end
function Q:kill(s)
 local r=self.r;local o=self.selected
 if not r.cfg.huntContract or self.status~='active'or not o or not r:player()or r:w('gamePaused','bool',false)or(r.bossDialog and r.bossDialog.active)then return end
 if o.kind=='nohit'or o.kind=='extreme'then
  local life,dead=self:health()
  if dead then self:wait('挑战期间死亡');return end
  if o.kind=='nohit'and life and self.lastLife and life<self.lastLife then self:onHurt();return end
  self.lastLife=life
 end
 if o.kind=='tier'and s.tier~=o.tier or o.kind=='extreme'and(s.tier or 0)<2 then return end
 if o.kind=='styles'then if not s.style or self.styles[s.style]then return end;self.styles[s.style]=true end
 self.count=math.min(self.goal,self.count+1)
 if self.count>=self.goal then self:finish()else self:checkpoint(true);r:notice('【猎杀契约】进度 '..self.count..'/'..self.goal,{255,205,130},'contract')end
end
function Q.installInput(r)
 local b=r.b;local p=b.p;local q=r.contract
 b.types.ChatCommandProcessor=p.get_type('Terraria.Chat','ChatCommandProcessor');b.types.ChatMessage=p.get_type('Terraria.Chat','ChatMessage')
 local method=b:exact('ChatCommandProcessor','CreateOutgoingMessage',{'string'},false)
 local consume=b:exact('ChatMessage','Consume',{},false)
 if not method or not consume then q.inputAvailable=false;r.log('CONTRACT_INPUT','available=false');return end
 local hook=p.install_hook(method,{postfix=function(_,args,result)
  local ok,err=pcall(function()
   local text=args[1];if type(text)~='string'and p.string_value then text=p.string_value(text)end
   if result and q:command(text)then b:set('ChatMessage','Text',result,'','string');p.invoke(consume,result)end
  end)
  if not ok then r.log('CONTRACT_INPUT_ERROR',tostring(err))end
 end})
 q.inputAvailable=hook~=nil;if hook then b.hooks[#b.hooks+1]=hook end
 r.log('CONTRACT_INPUT','available='..tostring(q.inputAvailable))
end
return Q
