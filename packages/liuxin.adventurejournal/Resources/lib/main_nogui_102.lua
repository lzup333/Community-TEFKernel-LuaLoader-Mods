mod.on_gui=nil -- Native GUI disabled.
mod.meta={pkg_id='liuxin.adventurejournal',version='1.0.2',version_code=9}
local P=mod.patch
local J=require('journal')
local Settings=require('settings')
local E=require('equipment')
local L=require('locations')
local locationTracker=L.new()
local config=Settings.load()
local pendingSave=false
local runtimeStatus='等待进入单人世界'
local H,hooks={},{}
local journal,key,disabled,frames,previousDead,announced=nil,nil,false,0,false,false
local miningDepth=0
local pickupStack={}
local logLines={}
local logDirty=false
local lastLogSave=os.time()
local function flushLog(force)
 if not logDirty or (not force and os.time()-lastLogSave<10) then return end
 lastLogSave=os.time()
 local ok,saved=pcall(mod.write_file,'adventurejournal_runtime.log',table.concat(logLines,'\n'))
 if ok and saved then logDirty=false end
end
local function log(s,important)
 if not important and not config.debug_log then return end
 logLines[#logLines+1]=s;if #logLines>100 then table.remove(logLines,1) end
 logDirty=true
 mod.info('[冒险手记] '..s)
 flushLog(false)
end
local function read(f,o,t) if f then return P.get_field_value(f,o,t) end end
local function field(t,n,required)
 local f=t and P.get_field(t,n);if required then assert(f,'缺少字段 '..n) end;return f
end
local function getter(t,n)
 local p=t and P.get_property(t,n);return p and P.property_get_method(p)
end
local function say(s)
 if config.announcements and H.chat then
  local h=P.string_create(s);P.invoke(H.chat,h,230,215,165,false)
 end
end
local function save()
 if not journal then return end
 local encoded=J.encode(journal.s)
 -- Keep last valid checkpoint for recovery, never silently replace unreadable data.
 local old=mod.read_file(key..'.lua')
 if old and J.decode(old) then mod.write_file(key..'.bak',old) end
 local ok,e=mod.write_file(key..'.lua',encoded)
 if not ok then log('保存失败 '..tostring(e),true);return false end
 local ok2,e2=mod.write_file(key..'.txt',J.text(journal.s,config.summary_tone))
 if not ok2 then log('文字日志导出失败 '..tostring(e2),true) end
 return true
end
local function safe(fn)
 return function(...)
  if disabled then return false end
  local ok,e=pcall(fn,...)
  if not ok then disabled=true;runtimeStatus='记录已暂停，请查看私有日志';log('回调停用：'..tostring(e),true) end
  return false -- Never skip game behavior or override return values.
 end
end
local function localPlayer(o)
 return journal and o and read(H.p.id,o,'int32')==H.localIndex
end
local function add(k,n) if journal and n>0 then journal:add(k,n) end end
local function hash(s)
 local h=2166136261;for i=1,#s do h=((h~s:byte(i))*16777619)&0xffffffff end
 return string.format('%08x',h)
end
local function zone(o)
 if not config.record_zones then locationTracker:reset();return {} end
 local flags={}
 for _,z in ipairs(H.zones) do
  local ok,value=pcall(P.invoke,z.get,o)
  if ok and type(value)=='boolean' then flags[z.name]=value
  elseif not z.warned then z.warned=true;log('地点属性不可读：'..z.name..'；本项跳过',true) end
 end
 local confirmed=locationTracker:sample(L.resolve(flags))
 for _,name in ipairs(confirmed) do
  if journal:visit(name) then pendingSave=true;log('到访地点：'..name) end
 end
 return confirmed
end
local function scanGear(o,baseline)
 local changed=false
 local seen=journal.s.seenGear
 for _,arrayField in ipairs({H.p.inventory,H.p.armor,H.p.misc}) do
  local a=arrayField and read(arrayField,o,'object')
  if a then
   for i=0,math.min(P.array_length(a)-1,99) do
    local it=P.array_at(a,i)
    if it then
     local id=read(H.i.kind,it,'int32') or 0
     if id>0 and (read(H.i.stack,it,'int32') or 0)>0 and not seen[id] then
      local d={}
      for k,f in pairs(H.gearFields) do d[k]=read(f,it,(k=='accessory' or k=='consumable') and 'bool' or 'int32') end
      local cat=E.category(d)
      if cat then
       seen[id]=true;changed=true
       if not baseline and config.record_rare and E.qualifies(d) then
        local name='物品 #'..id
        if H.itemName then
         local ok,text=pcall(function()
          local value=P.invoke(H.itemName,it)
          if type(value)=='string' then return value end
          if value then return P.string_value(value) end
         end)
         if ok and type(text)=='string' and text~='' then name=text end
        end
        name=name:gsub('[\r\n]',' ')
        add('gear',1)
        local text='首次获得'..cat..'：'..name..'。'
        journal:event('gear:'..id,text,{kind='gear',name=name})
        if config.rare_announcements then say('珍宝入袋 · '..text) end
        log('首次获得装备 ID='..id..' 品质='..tostring(d.rare)..' '..name)
       end
      end
     end
    end
   end
  end
 end
 if changed then pendingSave=true end
end
local function step(o)
 flushLog(false)
 local st
 if H.mobileState then
  local user=read(H.activeUser,nil,'object') or read(H.primaryUser,nil,'object')
  st=user and read(H.gameState,user,'object');if not st then return end
 end
 if read(H.menu,st,'bool')==true then
  if journal then save();journal=nil;key=nil;announced=false end;locationTracker:reset();return
 end
 local index=read(H.myPlayer,st,'int32');if read(H.p.id,o,'int32')~=index then return end
 H.localIndex=index
 -- Multiplayer attribution and world clocks require server support; first version is single-player.
 if read(H.netMode,nil,'int32')~=0 then
  runtimeStatus='联机模式：记录暂停'
  locationTracker:reset()
  if journal then save();journal=nil;key=nil end
  if not H.netWarn then H.netWarn=true;log('联机模式：暂停记录，仅支持单人') end;return
 end
 frames=frames+1
 if frames%120==0 then local updated=Settings.poll();if updated then config=updated;log('已同步TEFManager模组设置') end end
 local worldID=H.worldID and P.invoke(H.worldID) or read(H.worldIDField,nil,'int32')
 assert(type(worldID)=='number','世界ID不可读，停止记录以避免串档')
 local name=read(H.p.name,o,'string') or ''
 local worldName=read(H.worldName,nil,'string') or ''
 local nextKey='journal_'..tostring(worldID)..'_'..hash(worldName..'\0'..name)
 if key~=nextKey then
  if journal then save() end
  key=nextKey;local raw=mod.read_file(key..'.lua');local state=J.decode(raw)
  if raw and not state then
   state=J.decode(mod.read_file(key..'.bak'))
   assert(state,'存档损坏：保留原文件，请查看私有日志')
   log('已从上一个检查点恢复',true)
  end
  journal=J.attach(state or J.new());frames=0;previousDead=read(H.p.dead,o,'bool')==true;announced=false
  locationTracker:reset()
  runtimeStatus=worldName..' / '..name
  journal.s.worldName=worldName;journal.s.playerName=name
  scanGear(o,true);pendingSave=true
  log('开始记录 '..worldName..' / '..name..'；文件 '..key..'.txt')
 end
 local dead=read(H.p.dead,o,'bool')==true
 if dead and not previousDead then
  add('deaths',1);journal:event('death:'..journal.s.day..':'..journal.s.daily.deaths,'死亡一次。',{kind='death'});save()
 end
 previousDead=dead
 if dead then journal:position(0,true);locationTracker:reset() end
 if frames%30~=0 then return end
 local dt=read(H.dayTime,nil,'bool');assert(type(dt)=='boolean','昼夜不可读')
 local day=journal:clock(dt)
 if day then
  save();if config.daily_announcements then say(J.display(day,'记录第'..day.day..'天',config.summary_style,nil,config.summary_tone)) end
 end
 if not announced then say('冒险手记已运行');announced=true end
 if not dead then
  local x,y=P.get_field_vec2(H.p.pos,o)
  local hx,hy=read(H.p.spawnX,o,'int32'),read(H.p.spawnY,o,'int32')
  if not hx or hx<0 or not hy or hy<0 then hx=read(H.spawnX,st,'int32');hy=read(H.spawnY,st,'int32') end
  assert(type(hx)=='number' and type(hy)=='number' and type(x)=='number' and type(y)=='number','位置不可读')
  local distance=math.sqrt((x/16-hx)^2+(y/16-hy)^2)
  -- Include the final observed location before closing and saving the trip.
  local confirmed=zone(o)
  local action,r=journal:position(distance,dead,config)
  if action=='start' then for _,name in ipairs(confirmed) do journal:visit(name) end end
  if action=='end' then save();if config.return_announcements then say(J.display(r,'本次冒险结束',config.summary_style,nil,config.summary_tone)) end elseif action=='start' then log('离家开始冒险');save() end
  if frames%120==0 then scanGear(o,false) end
 end
 if pendingSave then save();pendingSave=false end
 if frames%(math.max(5,config.autosave_seconds or 30)*60)==0 then save() end
end
local coins={[71]=1,[72]=100,[73]=10000,[74]=1000000}
local ores={11,12,13,14,56,116,174,364,365,366,699,700,701,702,880,947,1104,1105,1106}
local oreSet={};for _,n in ipairs(ores) do oreSet[n]=true end
local function itemData(world)
 local inner=world and read(H.inner,world,'object');if not inner then return 0,0 end
 return read(H.i.kind,inner,'int32') or 0,read(H.i.stack,inner,'int32') or 0
end
local function pickupPre(o,args)
 local data=false
 if localPlayer(o) then local id,n=itemData(args[1]);data={id=id,n=n} end
 pickupStack[#pickupStack+1]=data
end
local function pickupPost(o,args)
 local data=table.remove(pickupStack);if not data or not localPlayer(o) then return end
 local id,n=itemData(args[1]);local remain=id==data.id and n or 0
 local gained=math.max(0,data.n-remain)
 if coins[data.id] then add('coins',gained*coins[data.id]) elseif oreSet[data.id] then add('ores',gained) end
end
local function potionCounts(o)
 local counts={};local a=read(H.p.inventory,o,'object');if not a then return counts end
 for i=0,math.min(P.array_length(a)-1,57) do
  local it=P.array_at(a,i)
  if it then
   local id=read(H.i.kind,it,'int32');local n=read(H.i.stack,it,'int32') or 0
   local potion=read(H.i.potion,it,'bool') or (read(H.i.buff,it,'int32') or 0)>0
   local food=H.foodField and read(H.foodField,nil,'object')
   local excluded=food and id and id>0 and id<P.array_length(food) and P.array_at(food,id,'bool')==true
   if id and id>0 and n>0 and potion and not excluded and read(H.i.consumable,it,'bool')==true then counts[id]=(counts[id] or 0)+n end
  end
 end;return counts
end
local potionDepth=0;local potionBefore
local function potionPre(o)
 if not localPlayer(o) then return end
 if potionDepth==0 then potionBefore=potionCounts(o) end;potionDepth=potionDepth+1
end
local function potionPost(o)
 if not localPlayer(o) or potionDepth==0 then return end
 potionDepth=potionDepth-1;if potionDepth>0 then return end
 local after=potionCounts(o);for id,n in pairs(potionBefore or {}) do add('potions',math.max(0,n-(after[id] or 0))) end;potionBefore=nil
end
local bossNames={[4]='克苏鲁之眼',[50]='史莱姆王',[13]='世界吞噬怪',[266]='克苏鲁之脑',[35]='骷髅王',[222]='蜂王',[113]='血肉墙',[125]='双子魔眼',[126]='双子魔眼',[127]='机械骷髅王',[134]='毁灭者',[262]='世纪之花',[245]='石巨人',[370]='猪龙鱼公爵',[398]='月亮领主',[636]='光之女皇',[657]='史莱姆皇后',[668]='独眼巨鹿',[439]='拜月教邪教徒'}
local function loot(o)
 if not journal or read(H.n.life,o,'int32')>0 then return end
 if read(H.n.last,o,'int32')~=H.localIndex or read(H.n.friendly,o,'bool')==true then return end
 -- Segment NPCs do not count as separate enemy kills.
 local real=read(H.n.real,o,'int32');local id=read(H.n.id,o,'int32')
 if real and real>=0 and real~=id then return end
 add('kills',1)
 local kind=read(H.n.kind,o,'int32');local name=bossNames[kind]
 if config.record_boss and (name or read(H.n.boss,o,'bool')==true) then
  -- Twins: only report victory when the partner is gone/dead.
  if kind==125 or kind==126 then
   local arr=read(H.npcs,nil,'object');if arr then
    for i=0,math.min(P.array_length(arr)-1,199) do
     local npc=P.array_at(arr,i)
     if npc and read(H.n.active,npc,'bool')==true and read(H.n.kind,npc,'int32')==251-kind and read(H.n.life,npc,'int32')>0 then return end
    end
   end
  end
  journal:event('boss:'..kind,'击败 '..(name or ('Boss（类型 '..kind..'）'))..'。',{kind='boss',name=name or ('Boss（类型 '..kind..'）')});save()
 end
end
local function install(t,n,count,pre,post,required)
 local m=P.get_method(t,n,count)
 if not m then assert(not required,'缺少方法 '..n);log('接口缺失 '..n,true);return end
 local h=P.install_hook(m,{prefix=pre and safe(pre) or nil,postfix=post and safe(post) or nil})
 assert(h,'Hook失败 '..n);hooks[#hooks+1]=h;log('已安装 '..n)
end
function setup()
 log('v1.0.1 初始化；LuaLoader 1.6.3 / Terraria 1.4.5 系列')
 local ok,e=pcall(function()
  local main=P.get_type('Terraria','Main');local player=P.get_type('Terraria','Player');local npc=P.get_type('Terraria','NPC');local item=P.get_type('Terraria','Item')
  local user=P.get_type('','LocalUser');local users=P.get_type('','UserManagement');local st=P.get_type('','LocalUserGameState')
  H.activeUser=field(user,'Active');H.primaryUser=field(users,'PrimaryPlayer');H.gameState=field(user,'GameState')
  H.mobileState=H.activeUser and H.gameState and st~=nil
  local stateType=H.mobileState and st or main
  H.menu=field(stateType,'gameMenu',true);H.myPlayer=field(stateType,'myPlayer',true)
  H.spawnX=field(stateType,'spawnTileX',true);H.spawnY=field(stateType,'spawnTileY',true)
  H.dayTime=field(main,'dayTime',true);H.worldName=field(main,'worldName',true)
  H.worldID=getter(main,'worldID');H.worldIDField=field(main,'worldID')
  assert(H.worldID or H.worldIDField,'缺少世界ID')
  log(H.mobileState and '使用本地用户状态路径' or '使用Main静态状态路径')
  H.netMode=field(main,'netMode',true);H.npcs=field(main,'npc',true);H.chat=P.get_method(main,'NewText',5)
  H.p={};for k,n in pairs({id='whoAmI',dead='dead',pos='position',name='name',spawnX='SpawnX',spawnY='SpawnY',inventory='inventory'}) do H.p[k]=field(player,n,true) end
  H.p.armor=field(player,'armor');H.p.misc=field(player,'miscEquips')
  H.itemName=getter(item,'Name')
  H.gearFields={}
  for k,n in pairs({rare='rare',accessory='accessory',head='headSlot',body='bodySlot',legs='legSlot',damage='damage',ammo='ammo',consumable='consumable'}) do H.gearFields[k]=field(item,n,true) end
  H.i={};for k,n in pairs({kind='type',stack='stack',potion='potion',buff='buffType',consumable='consumable'}) do H.i[k]=field(item,n,true) end
  H.n={};for k,n in pairs({life='life',last='lastInteraction',friendly='friendly',real='realLife',id='whoAmI',kind='type',boss='boss',active='active'}) do H.n[k]=field(npc,n,true) end
  H.inner=field(P.get_type('Terraria','WorldItem'),'inner')
  local sets=P.get_inner_type(P.get_type('Terraria.ID','ItemID'),'Sets');local food=field(sets,'IsFood')
  H.foodField=food
  H.zones={}
  for _,n in ipairs(L.probes) do
   local g=getter(player,n)
   if g then H.zones[#H.zones+1]={get=g,name=n} else log('地点接口缺失：'..n,true) end
  end
  log('地点识别接口 '..#H.zones..'/'..#L.probes..'，连续约2秒确认到访')
  install(player,'Update',1,nil,step,true)
  if H.inner then install(player,'PickupItem',1,pickupPre,pickupPost,false) else log('本游戏缺少WorldItem接口，钱币与矿石拾取统计不可用',true) end
  install(npc,'NPCLoot',0,loot,nil,true)
  for _,n in ipairs({'ItemCheck','QuickHeal','QuickMana','QuickBuff'}) do install(player,n,0,potionPre,potionPost,true) end
  -- Scope tile drop callbacks to the local player's PickTile call. Natural destruction and explosions excluded.
  install(player,'PickTile',4,function(o) if localPlayer(o) then miningDepth=miningDepth+1 end end,function(o) if localPlayer(o) then miningDepth=math.max(0,miningDepth-1) end end,true)
  local gen=P.get_type('Terraria','WorldGen')
  local stack={}
  install(gen,'KillTile',5,function(_,a)
   stack[#stack+1]=miningDepth>0 and a[3]~=true and a[4]~=true and a[5]~=true
  end,function() table.remove(stack) end,true)
  install(gen,'KillTile_DropItems',4,function() if stack[#stack] then stack[#stack]=false;add('blocks',1) end end,nil,true)
  log('初始化成功；等待进入世界')
 end)
 if not ok then runtimeStatus='初始化失败，请查看私有日志';disabled=true;for _,h in ipairs(hooks) do pcall(function() h:remove() end) end;hooks={};log('初始化失败 '..tostring(e),true) end
end
function mod.cleanup()
 save();disabled=true;for _,h in ipairs(hooks) do pcall(function() h:remove() end) end;hooks={}
 flushLog(true)
end
todo_list={'setup'}

-- GUI only reads plain Lua data. No managed game calls from render thread.
local page='本次冒险'
local historyKind='冒险'
local historyIndex=1
local settingsMessage=''
local function persistSettings()
 config=Settings.normalize(config)
 local ok,e=Settings.save(config)
 settingsMessage=ok and '设置已保存，立即生效。' or ('设置保存失败：'..tostring(e))
end
local function showRecord(g,r,label)
 g.text_wrapped(J.display(r,label,config.summary_style,config.summary_style==3 and #r.events or nil,config.summary_tone))
end
