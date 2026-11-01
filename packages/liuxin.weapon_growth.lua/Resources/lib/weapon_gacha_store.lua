-- Per-character collection, tickets and unique weapon draws.
local M={classes={melee=true,ranged=true,magic=true,summon=true}}
local function checksum(s) local n=0;for i=1,#s do n=(n*131+s:byte(i))%2147483647 end;return n end
local function hex(s) return (s:gsub('.',function(c)return string.format('%02x',c:byte())end)) end
local function encode(s,generation)
 local ids={};for id in pairs(s.owned) do ids[#ids+1]=id end;table.sort(ids)
 local body='tickets|'..s.tickets..'\nnewgift|'..(s.newgift and 1 or 0)..'\n'
 for _,id in ipairs(ids) do body=body..'weapon|'..id..'\n' end
 body=body..'pity|'..s.pity..'\n'
 body=body..'online|'..(s.day or 0)..':'..(s.daily or 0)..':'..(s.seconds or 0)..'\n'
 local bosses={};for id in pairs(s.bosses or {})do bosses[#bosses+1]=id end;table.sort(bosses)
 for _,id in ipairs(bosses)do body=body..'boss|'..id..'\n'end
 for _,r in ipairs(s.history or {})do body=body..'draw|'..r.time..':'..table.concat(r.ids,',')..'\n'end
 generation=generation or 1
 return 'WGACHA|1|'..generation..'|'..checksum(tostring(generation)..'\n'..body)..'\n'..body
end
local function decode(s)
 if type(s)~='string' or #s>262144 then return nil end
 local gen,sum,body=s:match('^WGACHA|1|(%d+)|(%d+)\n(.*)$');gen=tonumber(gen)
 if not gen or gen>1000000000 or tonumber(sum)~=checksum(tostring(gen)..'\n'..body) then return nil end
 local out={tickets=0,newgift=false,owned={},pity=0,history={}}
 for line in body:gmatch('([^\n]+)\n') do
  local k,v=line:match('^([^|]+)|([^|]+)$');if k=='tickets' then out.tickets=tonumber(v) elseif k=='newgift' then out.newgift=v=='1' elseif k=='weapon' then local id=tonumber(v);if not id or id<1 or id%1~=0 then return nil end;out.owned[id]=true elseif k=='pity' then out.pity=tonumber(v)
  elseif k=='online' then
   local d,n,t=v:match('^(%d+):(%d+):(%d+)$');d,n,t=tonumber(d),tonumber(n),tonumber(t)
   if not d or d>99999999 or n>20 or t>=120 then return nil end
   out.day=d;out.daily=n;out.seconds=t
  elseif k=='boss' then
   local id=tonumber(v);if not id or id<1 or id>20000 or id%1~=0 then return nil end
   out.bosses=out.bosses or {};out.bosses[id]=true
  elseif k=='draw' then
   local when,ids=v:match('^(%d+):([%d,]+)$');local record={time=tonumber(when),ids={}}
   if not record.time or record.time>9999999999 then return nil end
   for token in ids:gmatch('%d+')do local id=tonumber(token);if id<1 or id>20000 then return nil end;record.ids[#record.ids+1]=id end
   if #record.ids<1 or #record.ids>10 or #out.history>=20 then return nil end
   out.history[#out.history+1]=record
  end
 end
 if not out.tickets or out.tickets<0 or out.tickets>10000 or out.tickets%1~=0 or not out.pity or out.pity<0 or out.pity>100000 then return nil end
 out.generation=gen;return out
end
function M.open(read,write,report)
 local state={profiles={},blocked={}}
 function state:load(key)
  if type(key)~='string' or #key==0 or #key>4096 then return nil end
  if self.profiles[key] then return self.profiles[key] end
  local a,b=read('weapon_gacha_a_'..hex(key)..'.dat'),read('weapon_gacha_b_'..hex(key)..'.dat')
  local x,y=a and decode(a),b and decode(b)
  if not x and not y and (a~=nil or b~=nil) then self.blocked[key]=true;report('GACHA_SAVE_BLOCKED','角色抽奖档案校验失败，已停止写入');return nil end
  local s,slot
  if x and y then if x.generation>=y.generation then s,slot=x,1 else s,slot=y,2 end
  elseif x then s,slot=x,1 elseif y then s,slot=y,2 else s,slot={tickets=0,newgift=false,owned={},pity=0,history={},generation=0},nil end
  s.slot=slot;s.dirty=false;self.profiles[key]=s;return s
 end
 function state:save(key)
  local s=self.profiles[key];if not s or not s.dirty or self.blocked[key] then return s~=nil end
  local slot=s.slot==1 and 2 or 1;local name='weapon_gacha_'..(slot==1 and 'a' or 'b')..'_'..hex(key)..'.dat';local data=encode(s,(s.generation or 0)+1)
  local ok,err=write(name,data);if not ok or read(name)~=data then report('GACHA_SAVE_FAILED',tostring(err or '回读校验失败'));return false end
  s.slot=slot;s.generation=(s.generation or 0)+1;s.dirty=false;return true
 end
 function state:addOwned(key,id)
  local s=self:load(key);if not s or type(id)~='number' or id<1 or id%1~=0 or s.owned[id] then return false end
  s.owned[id]=true;s.dirty=true;return true
 end
 function state:ticket(key,n)
  local s=self:load(key);if not s or type(n)~='number' or n%1~=0 then return false end
  s.tickets=math.max(0,math.min(10000,s.tickets+n));s.dirty=true;return self:save(key)
 end
 function state:giftNew(key,playtime)
  local s=self:load(key);if not s or s.newgift then return false end
  s.tickets=s.tickets+10;s.newgift=true;s.dirty=true;return self:save(key)
 end
 -- Pure memory changes; the maintenance callback performs persistence.
 function state:online(key,day,elapsed)
  local s=self:load(key);if not s then return end
  if not s.day or day>s.day then s.day=day;s.daily=0;s.seconds=0;s.dirty=true end
  s.daily=s.daily or 0;s.seconds=s.seconds or 0
  if s.daily>=20 then return end
  local n=math.max(0,math.min(5,math.floor(elapsed or 0)))
  if n==0 then return end
  s.seconds=s.seconds+n;s.dirty=true
  if s.seconds>=120 then
   s.seconds=s.seconds-120;s.daily=s.daily+1;s.tickets=math.min(10000,s.tickets+1)
  end
 end
 function state:boss(key,id)
  local s=self.profiles[key] -- Never load files inside combat callbacks.
  if not s or self.blocked[key] or type(id)~='number' or id<1 or id>20000 or id%1~=0 then return false end
  -- Treat the Twins as one boss and all Eater segments as one boss.
  if id==126 then id=125 elseif id==14 or id==15 then id=13 end
  s.bosses=s.bosses or {};if s.bosses[id]then return false end
  s.bosses[id]=true;s.tickets=math.min(10000,s.tickets+10);s.dirty=true;return true
 end
 local function remember(s,ids)
  s.history=s.history or {};local copy={};for _,id in ipairs(ids)do copy[#copy+1]=id end
  s.history[#s.history+1]={time=os.time(),ids=copy}
  if #s.history>20 then table.remove(s.history,1)end
 end
 function state:draw(key,count,class,catalog,random,give)
  local s=self:load(key);if not s or self.blocked[key] then return nil,'存档不可用' end
  if count~=1 and count~=10 then return nil,'抽取数量无效' end
  if class and not M.classes[class] then return nil,'职业筛选无效' end
  if s.tickets<count then return nil,'抽奖券不足' end
  if not catalog.complete then return nil,'奖池索引尚未完成' end
  local pool={};for id,entry in pairs(catalog) do if id~='complete' and not s.owned[id] and (not class or entry.category==class or (entry.categories and entry.categories[class])) then pool[#pool+1]=id end end
  table.sort(pool);if #pool<count then return nil,'未收集奖池不足以完成本次抽取' end
  local staged={};for i=1,count do local j=random(i,#pool);pool[i],pool[j]=pool[j],pool[i];staged[i]=pool[i] end
  local granted={}
  for _,id in ipairs(staged) do local ok,err=give(id);if not ok then
    if #granted>0 then
     s.tickets=s.tickets-#granted;for _,given in ipairs(granted) do s.owned[given]=true end
     s.pity=(s.pity or 0)+#granted;remember(s,granted);s.dirty=true;self:save(key)
     return granted,'部分发放：'..tostring(err)
    end
    return nil,'发放失败：'..tostring(err)
  end;granted[#granted+1]=id end
  s.tickets=s.tickets-count
  for _,id in ipairs(staged) do s.owned[id]=true end
  s.pity=(s.pity or 0)+count;remember(s,staged);s.dirty=true
  if not self:save(key) then return staged,'已发放；存档稍后重试' end
  return staged
 end
 function state:count(key,catalog,class)
  local s=self:load(key);if not s then return 0,0 end
  local total,owned=0,0
  for id,e in pairs(catalog) do if id~='complete' and (not class or e.category==class or (e.categories and e.categories[class])) then total=total+1;if s.owned[id] then owned=owned+1 end end end
  return owned,total
 end
 return state
end
return M
