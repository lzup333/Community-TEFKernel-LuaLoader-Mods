-- Native calls run only from the existing Player.Update callback. GUI reads a cached view.
local Store=require('weapon_gacha_store')
local Cache=require('weapon_gacha_cache')
local Names=require('weapon_gacha_names')
local M={}
function M.open(P,env)
 local self={view={tickets=0,owned=0,total=0,remaining=0,status='等待进入单人世界',ready=false},catalog={complete=false}}
 local store=Store.open(env.read,env.write,env.log)
 local pending,key,lastTick,lastCollect,lastGift=nil,nil,-1,-1,-1
 local sequence,receipt=0,nil
 local cursor,sampleCount,scanFailed=0,0,false
 local locations={}
 local names,nameIds,nameCursor,lastNameSave=nil,nil,1,-1
 local cacheChecked=false
 local enteredAt=nil
 local onlineAt,onlineKey=nil,nil
 local phases={}
 local function mark(name)
  if not phases[name] then phases[name]=true;env.log('GACHA_STEP',name)end
 end
 local sampleReported=false
 local types,fs={},{banks={}}
 local function field(t,n) return t and P.get_field(t,n) end
 local function get(f,o,k) return f and P.get_field_value(f,o,k or 'object') end
 local function setup()
  types.item=P.get_type('Terraria','Item');types.player=P.get_type('Terraria','Player')
  types.main=P.get_type('Terraria','Main')
  types.recipe=P.get_type('Terraria','Recipe')
  types.chest=P.get_type('Terraria','Chest')
  fs.recipes=field(types.main,'recipe')
  fs.recipeCount=field(types.recipe,'numRecipes')
  fs.output=field(types.recipe,'createItem')
  fs.inputs=field(types.recipe,'requiredItem')
  fs.itemType=field(types.item,'type');fs.stack=field(types.item,'stack')
  fs.inventory=field(types.player,'inventory');fs.chestItems=field(types.chest,'item')
  fs.banks={};for _,n in ipairs({'bank','bank2','bank3','bank4'})do fs.banks[n]=field(types.player,n)end
  self.clone=types.item and P.get_method_by_param_types(types.item,'Clone',{})
  if self.clone and (not P.method_is_instance(self.clone) or P.method_param_count(self.clone)~=0)then self.clone=nil end
  names=Names.open(P,env,types.item)
  env.log('GACHA_API','recipePool=true clone='..tostring(self.clone~=nil)..'；不访问ContentSamples或TimeSpan')
 end
 local ok,err=pcall(setup)
 if not ok then self.error=tostring(err);env.log('GACHA_API_UNAVAILABLE',self.error)end
 local function samples()
  if not fs.recipes or not fs.recipeCount or not fs.output or not fs.inputs then return nil end
  return get(fs.recipes,nil)
 end
 local function addSample(it,recipeIndex,inputSlot)
  if not it then return end
  local id=get(fs.itemType,it,'int32')
  if type(id)~='number' or id<=0 then return end
  local e=env.identify(it,id)
  if e then
   self.catalog[id]={category=e.category,categories=e.categories,name=e.name or ('武器#'..id)}
   -- Recipe outputs and ingredients remain rooted by Main.recipe.
   locations[id]={recipe=recipeIndex,slot=inputSlot}
  end
 end
 local function scan(arr)
  if scanFailed then return end
  mark('recipe_count_read')
  local count=get(fs.recipeCount,nil,'int32')
  mark('recipe_count_ok')
  if type(count)~='number' or count<1 or count>10000 or P.array_length(arr)<count then return end
  if sampleCount>0 and sampleCount~=count then
   self.catalog={complete=false};locations={};nameIds=nil;nameCursor=1;cursor=0;cacheChecked=false
  end
  sampleCount=count
  if not cacheChecked then
   cacheChecked=true
   local c,l,n=Cache.load(env.read,count)
   if c then self.catalog=c;locations=l;cursor=count;env.log('GACHA_CACHE_HIT','本地奖池武器='..n..'；跳过完整配方扫描');return end
   env.log('GACHA_CACHE_MISS','首次建立或缓存失效，分批扫描后保存')
  end
  if self.catalog.complete then return end
  local last=math.min(count-1,cursor+95)
  for i=cursor,last do
   mark('recipe_first_object')
   local r=P.array_at(arr,i,'object')
   if r then
    mark('recipe_output_read')
    addSample(get(fs.output,r),i,-1)
    mark('recipe_output_ok')
    local inputs=get(fs.inputs,r)
    if inputs then
     local n=P.array_length(inputs)
     if n>=0 and n<=100 then for j=0,n-1 do addSample(P.array_at(inputs,j,'object'),i,j)end end
    end
   end
  end
  cursor=last+1
  if cursor>=count then
   local n=0;for id in pairs(self.catalog)do if type(id)=='number'then n=n+1 end end
   self.catalog.complete=n>0;scanFailed=n==0
   if n>0 then env.log('GACHA_CACHE_SAVE',Cache.save(env.write,env.read,count,self.catalog,locations)and '奖池缓存已保存并校验' or '缓存保存失败，下次启动重新建立')end
   env.log('GACHA_CATALOG_READY','配方武器='..n..'；当前为兼容奖池，非完整原版奖池')
  end
 end
 local function recordArray(arr,k)
  if not arr then return end
  for i=0,P.array_length(arr)-1 do
   local it=P.array_at(arr,i,'object')
   if it then local id=get(fs.itemType,it,'int32');if type(id)=='number' and id>0 and env.identify(it,id)then store:addOwned(k,id)end end
  end
 end
 local function collect(p,k)
  recordArray(get(fs.inventory,p),k)
  for _,f in pairs(fs.banks)do local chest=get(f,p);if chest then recordArray(get(fs.chestItems,chest),k)end end
 end
 -- Per-character plain text: 0 = unclaimed, 1 = claimed.
 -- Keep the existing checked ticket ledger as the authority after interruption.
 -- Per-character plain text: 0 = unclaimed, 1 = claimed.
 -- Keep the existing checked ticket ledger as the authority after interruption.
 local function gift(k)
  local suffix=(k:gsub('.',function(c)return string.format('%02x',c:byte())end))
  local name='weapon_gacha_gift_'..suffix..'.txt'
  local value=env.read(name)
  local flag=value and value:match('^%s*([01])%s*$')
  local state=store:load(k)
  if not state then return '赠券存档不可用'end
  if value~=nil and not flag then
   env.log('GACHA_GIFT_RECORD_INVALID','数字记录异常，停止赠券以避免重复')
   return '赠券记录异常'
  end
  if state.newgift then
   if flag~='1' then env.write(name,'1\n')end
   return nil
  end
  if flag=='1' then
   -- Honor a previous claim even when importing an older ticket ledger.
   state.newgift=true;state.dirty=true;store:save(k)
   return nil
  end
  if value==nil then
   local ok=env.write(name,'0\n')
   if not ok or env.read(name)~='0\n' then return '赠券数字记录写入失败'end
  end
  env.log('GACHA_GIFT_BEGIN','纯文本数字记录；不读取角色游戏时间')
  -- Zero is an eligibility constant, not a native playtime read.
  local awarded=store:giftNew(k,0)
  if not awarded then return '赠券保存失败，稍后重试'end
  local ok=env.write(name,'1\n')
  if not ok or env.read(name)~='1\n' then
   env.log('GACHA_GIFT_RECORD_RETRY','券账已保存，数字标记稍后补写')
  end
  env.log('GACHA_NEW_CHARACTER_GIFT','首次本地记录赠送10券；已保存，避免重复领取')
  return nil
 end
 local function emptySlots(p)
  local arr=get(fs.inventory,p);local slots={}
  if arr then for i=0,math.min(49,P.array_length(arr)-1)do
   local it=P.array_at(arr,i,'object');if it and get(fs.itemType,it,'int32')==0 then slots[#slots+1]=i end
  end end
  return arr,slots
 end
 local function sourceAt(dict,id)
  local loc=locations[id];local recipe=loc and P.array_at(dict,loc.recipe,'object')
  if not recipe then return nil end
  local it
  if loc.slot==-1 then it=get(fs.output,recipe)
  else local arr=get(fs.inputs,recipe);if arr and loc.slot<P.array_length(arr)then it=P.array_at(arr,loc.slot,'object')end end
  return it and get(fs.itemType,it,'int32')==id and it or nil
 end
 local function updateNames(dict,now)
  if not names or not names.getter or not self.catalog.complete then return end
  if not nameIds then
   nameIds={};for id in pairs(locations)do nameIds[#nameIds+1]=id end;table.sort(nameIds);nameCursor=1
  end
  for i=1,16 do
   local id=nameIds[nameCursor];if not id then break end
   if not names:cached(id)then names:resolve(sourceAt(dict,id),id)end
   nameCursor=nameCursor+1
  end
  if now-lastNameSave>=5 then names:save();lastNameSave=now end
 end
 local function itemView(id)
  local e=self.catalog[id]
  return {id=id,name=names and names:cached(id)or ('物品#'..id),category=e and e.category}
 end
 local function historyView(s)
  local list={}
  for _,record in ipairs(s.history or {})do
   local r={time=record.time,items={},ok=true}
   for _,id in ipairs(record.ids)do r.items[#r.items+1]=itemView(id)end
   list[#list+1]=r
  end
  return list
 end
 local function deliver(dict,inv,slots)
  local used=0
  return function(id)
   local ok,result,why=pcall(function()
   local source=sourceAt(dict,id)
   if not source or get(fs.itemType,source,'int32')~=id then
    self.catalog={complete=false};locations={};nameIds=nil;nameCursor=1;cursor=0;scanFailed=false
    -- Deliberately bypass the same stale disk cache on the rebuild.
    cacheChecked=true
    env.log('GACHA_CACHE_STALE','配方位置与ID不符，取消本次发放并重新建立奖池')
    return false,'奖池缓存已过期，正在重建；未发放部分不扣券'
   end
   if names then names:resolve(source,id)end
   mark('clone_before id='..id)
   local obj=P.invoke(self.clone,source)
   mark('clone_after id='..id)
   if obj==source then return false,'Clone返回原对象，取消发奖'end
   if not obj or obj==false or get(fs.itemType,obj,'int32')~=id then return false,'原版Clone未返回正确物品'end
   P.set_field_value(fs.stack,obj,1,'int32')
   local slot=slots[used+1];if not slot then return false,'背包空位不足'end
   mark('inventory_write id='..id)
   if not P.array_set(inv,slot,obj,'object')then return false,'写入背包失败'end
   local inserted=P.array_at(inv,slot,'object')
   if not inserted or get(fs.itemType,inserted,'int32')~=id then return false,'背包回读失败'end
   used=used+1;return true
   end)
   if not ok then return false,tostring(result)end
   return result,why
  end
 end
 function self:tick(p)
  if self.error then self.view.status='抽奖接口初始化失败';self.view.ready=false;return end
  local now=env.clock()
  if now==lastTick then return end -- one batch per second; no extra native hook
  lastTick=now
  if not enteredAt then enteredAt=now;mark('world_enter_delay');return end
  if now-enteredAt<3 then return end
  mark('profile')
  local k=env.profile()
  mark('profile_ok')
  if not k then self.view={tickets=0,owned=0,total=0,remaining=0,status='角色存档未就绪',ready=false};pending=nil;key=nil;return end
  if key~=k then key=k;pending=nil;receipt=nil;lastCollect=-1;lastGift=-1 end
  mark('store_load')
  local s=store:load(k);if not s then self.view.status='抽奖存档校验失败';self.view.ready=false;return end
  local delta=onlineKey==k and onlineAt and now-onlineAt or 0
  onlineKey=k;onlineAt=now
  -- Long pauses, menus and app background time never earn online tickets.
  if delta<0 or delta>5 then delta=0 end
  local today=tonumber(os.date('%Y%m%d',now))
  if s.day and today>s.day then delta=0 end
  store:online(k,today,delta)
  mark('recipe_array')
  local dict=samples()
  mark('recipe_array_ok')
  if not sampleReported then
   sampleReported=true
   env.log('GACHA_SAMPLES','配方数组='..tostring(dict~=nil))
  end
  mark('recipe_scan_begin')
  if dict then scan(dict);updateNames(dict,now)end
  mark('recipe_batch_ok')
  if now-lastCollect>=2 or pending then mark('collection_begin');collect(p,k);mark('collection_ok');lastCollect=now end
  local giftStatus
  if now-lastGift>=5 then mark('gift_begin');giftStatus=gift(k);mark('gift_ok');lastGift=now end
  store:save(k)
  mark('store_save_ok')
  local canGive=self.catalog.complete and self.clone~=nil and fs.stack~=nil and dict~=nil
  local status=self.error or giftStatus or (not self.catalog.complete and ('奖池加载 '..math.min(cursor,sampleCount)..'/'..sampleCount))or (not canGive and '发奖接口不可用')or '兼容奖池：未收集配方武器'
  if pending then
   local request=pending;pending=nil
   receipt={serial=request.serial,profile=k,items={},ok=false}
   if request.key~=k or now-request.at>5 then status='角色切换或请求超时，已取消'
   elseif not canGive then status='奖池或发奖接口未就绪'
   else
    local inv,slots=emptySlots(p)
    if #slots<request.count then status='请先留出'..request.count..'个背包空位'
    else
     -- Persist collection/check writeability before touching inventory.
     s.dirty=true
     if not store:save(k)then status='存档写入失败，取消抽取'
     else
      local result,why=store:draw(k,request.count,request.class,self.catalog,math.random,deliver(dict,inv,slots))
      if result then
       receipt.ok=true
       for _,id in ipairs(result)do receipt.items[#receipt.items+1]=itemView(id)end
       receipt.time=now
       if names then names:save()end
       status='获得 '..#result..' 件武器';env.log('GACHA_DRAW','ids='..table.concat(result,',')..' '..tostring(why or '成功'))
      else status=why or '抽取失败'end
     end
    end
   end
   receipt.status=status
   self.lastResult=status;self.resultUntil=now+10
  end
  if self.lastResult and now<(self.resultUntil or 0)then status=self.lastResult end
  local owned,total=store:count(k,self.catalog)
  canGive=self.catalog.complete and self.clone~=nil and fs.stack~=nil and dict~=nil
  self.view={tickets=s.tickets,owned=owned,total=total,remaining=math.max(0,total-owned),pity=s.pity,status=status,ready=canGive,newgift=s.newgift,profile=k,receipt=receipt,history=historyView(s),daily=s.daily or 0,dailyRemaining=20-(s.daily or 0),nextTicket=120-(s.seconds or 0)}
 end
 function self:suspend() onlineAt=nil;onlineKey=nil end
 function self:boss(k,id) return store:boss(k,id)end
 function self.state()return self.view end
 function self.draw(count,class)
  if count~=1 and count~=10 then return '抽取数量无效'end
  if class and not Store.classes[class]then return '职业无效'end
  if pending then return '抽取处理中'end
  if not key or not self.view.ready then return self.view.status or '角色未就绪'end
  sequence=sequence+1
  pending={key=key,count=count,class=class,at=env.clock(),serial=sequence};return '正在抽取…',sequence
 end
 function self:save()if names then names:save()end;if key then return store:save(key)end end
 return self
end
return M
