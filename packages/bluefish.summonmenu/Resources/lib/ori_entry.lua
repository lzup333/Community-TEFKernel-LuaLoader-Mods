local okBackend,Native=pcall(require,'ori_native_backend')
if not okBackend then pcall(mod.error,'[OR_LUA] backend 加载失败: '..tostring(Native)); Native={version='missing'} end
local cfg=require('ori_config'); local Bridge=require('ori_bridge'); local Runtime=require('ori_runtime')
local b,r
-- 调试期日志只走 mod.info（加载器自己的日志通道），不写任何文件
-- 正式版：只输出启动摘要与错误类日志，其余调试标签全部静默
local KEEP={READY=true,START_FAILED=true,UNLOAD=true,WORLD=true,CAP=true,DIFFICULTY=true,HOOK_ERROR=true}
local function log(tag,text)
 if not KEEP[tag] and not tag:find('_FAILED$') and not tag:find('_ERROR$')
    and not tag:find('_DISABLED$') and not tag:find('_UNAVAILABLE$') and not tag:find('_CANCEL$') then return end
 mod.info('[OR_LUA]['..tag..'] '..tostring(text))
end
local function flush() end
local function om_setup()
 local ok,err=xpcall(function()
  if mod.platform~='android' or mod.arch~='arm64' then error('本包当前仅面向 Android ARM64') end
  cfg.load(mod,log)
  log('DIFFICULTY',cfg.difficulty..' name='..require('ori_difficulty').get(cfg).name)
  b=Bridge.new(mod.patch,log);r=Runtime.new(b,cfg,log)
  r.store=require('ori_statefile').new(mod,log);r.budget=require('ori_shotbudget').new(r)
  log('NATIVE_CORE',Native.version..'; scalar/vector field bridge, RNG, NPC stats, AI scoring and quest kill matching')
  for _,spec in ipairs({{'Main','gameMenu','bool'},{'Main','netMode','int32'},{'Main','worldID','int32'},{'Main','npc','object'},
   {'NPC','whoAmI','int32'},{'NPC','type','int32'},{'NPC','active','bool'},{'NPC','life','int32'},{'NPC','lifeMax','int32'},{'NPC','damage','int32'},{'NPC','defense','int32'},
   {'NPC','value','float'},{'NPC','scale','float'},{'NPC','knockBackResist','float'},{'NPC','friendly','bool'},{'NPC','townNPC','bool'},{'NPC','boss','bool'},
   {'NPC','realLife','int32'},{'NPC','SpawnedFromStatue','bool'},{'NPC','alpha','int32'},{'NPC','position','object'},{'NPC','velocity','object'}}) do b:field(spec[1],spec[2],spec[3],true) end
  if not mod.patch.field_pointer or not mod.patch.get_method_by_param_types then error('LuaLoader 缺少必要接口，请更新加载器') end
  local clock=b:field('Main','GameUpdateCount','uint32')
  local clockAlt=b:field('Main','gameUpdateCount','uint32')
  if not (clock.h or clock.getter or clockAlt.h or clockAlt.getter) then error('无法读取游戏帧计数，停止启用') end
  local ai=b:exact('NPC','AI',{},false); if not ai then error('NPC.AI() 不可用') end
  -- 用精确参数类型句柄选重载，绝不凭参数个数猜接口。
  r.item=b:exact('Item','NewItem',{'int32','int32','int32','int32','int32','int32','bool','int32',{'Terraria','NewItemOwnership'}},true)
    or b:exact('Item','NewItem',{'int32','int32','int32','int32','int32','int32','bool','int32','int32'},true)
  r.itemOwnership=r.item and b:exact('Item','NewItem',{'int32','int32','int32','int32','int32','int32','bool','int32',{'Terraria','NewItemOwnership'}},true)~=nil
  -- 1.4.5.8 的地面物品是 WorldItem 包装，不能用 Item 字段直接读它。
  r.worldItems=r.itemOwnership and b.types.WorldItem~=nil and b:field('WorldItem','inner','object').h~=nil
  local privateOK,privateReward=pcall(require('ori_inventoryreward').new,r)
  r.inventoryReward=privateOK and privateReward or {ready=false}
  if not privateOK then log('PRIVATE_REWARD_DISABLED',tostring(privateReward))end
  log('LOOT_ROUTE','readback='..(r.worldItems and 'WorldItem.inner' or 'Item')..' ownership='..(r.itemOwnership and 'None' or 'legacy'))
  r.projectile=b:exact('Projectile','NewProjectile',{'float','float','float','float','int32','int32','float','int32','float','float'},true)
  r.projectileSource=b:exact('NPC','GetSpawnSource_ForProjectile',{},false)
  if not r.projectile and r.projectileSource then
   r.projectile=b:exact('Projectile','NewProjectile',{{'Terraria.DataStructures','IEntitySource'},'float','float','float','float','int32','int32','float','int32','float','float','float',{'Terraria','NewProjectileModifier'}},true)
   r.projectileModern=r.projectile~=nil
  end
  local getterProp=b.p.get_property(b.types.NPC,'FullName')
  local setterProp=b.p.get_property(b.types.NPC,'GivenName')
  r.nameGetter=getterProp and b.p.property_get_method(getterProp)
  r.nameSetter=setterProp and b.p.property_set_method(setterProp)
  r.nameColor=require('ori_namecolor').install(b,r)
  local actionOK,actionErr=pcall(require('ori_actions').install,r)
  if not actionOK then r.solid=nil;r.empty=nil;r.log('ACTION_DISABLED',tostring(actionErr)) end
  local headOK,headResult=pcall(require('ori_heads').install,r)
  if headOK then r.heads=headResult else log('HEAD_DISABLED',tostring(headResult)) end
  local guardOK,guardErr=pcall(require('ori_shotguard').install,r)
  if not guardOK then log('SHOT_GUARD_DISABLED',tostring(guardErr))end
  require('ori_specialactions').install(r)
  local breakOK,breakErr=pcall(require('ori_breakwindow').install,r);if not breakOK then log('BREAK_ROUTE',tostring(breakErr))end
  local netOK,netErr=pcall(require('ori_network').install,r)
  if not netOK then if r.net then r.net.ready=false end;log('NET_DISABLED',tostring(netErr))end
  local defaults=b:exact('NPC','SetDefaults',{'int32','pointer'},false)
    or b:exact('NPC','SetDefaults',{'int32',{'Terraria','NPCSpawnParams'}},false)
    or b:exact('NPC','SetDefaults',{'int32'},false)
  if not defaults then error('无法精确匹配NPC.SetDefaults，停止启用以避免槽位复用污染') end
  if not b:hook(defaults,function(n) r:defaults(n) end,true) then error('SetDefaults Hook 安装失败') end
  r.collector=require('ori_collector').new(r,mod);r.collector:load()
  log('ECHO_BUILTIN','templates='..#require('ori_catalog'))
  local aiHook=mod.patch.install_hook(ai,{
   prefix=function(n)
    local ok,err=pcall(r.collector.enter,r.collector,n)
    if not ok then r.collector.stack[#r.collector.stack+1]=false;log('COLLECTOR_ERROR',tostring(err)) end
    return false
   end,
   postfix=function(n)
    r.collector:leave()
    local ok,err=xpcall(function()r:onAI(n)end,debug.traceback)
    if not ok then log('HOOK_ERROR',err) end
   end,
  })
  if not aiHook then error('AI Hook 安装失败') end;b.hooks[#b.hooks+1]=aiHook
  local collectHook=r.projectile and b:hook(r.projectile,function(_,args,index)if r.shotGuard then r.shotGuard:forget(index)end;r.collector:observe(args,index)end)
  log('ECHO_COLLECT_ROUTE','available='..tostring(collectHook==true)..' mode=NPC.AI_context samples=3')
  local loot=b:exact('NPC','NPCLoot',{},false)
  local lootHook=loot and mod.patch.install_hook(loot,{
   prefix=function(n)return require('ori_specialactions').owned(r,n)and true or false end,
   postfix=function(n)
    if require('ori_specialactions').owned(r,n)then return end
    r:loot(n)
   end,
  })
  if lootHook then b.hooks[#b.hooks+1]=lootHook;r.helperLootSafe=true else r.item=nil;r.npcFactory=nil end

  local update=b:exact('Main','Update',{{'Microsoft.Xna.Framework','GameTime'}},false)
  if not update or not b:hook(update,function()
   local running=r:tick()
   if r.heads then
    local headOK,headErr=pcall(r.heads.update,r.heads)
    if not headOK then r.heads:clear();r.heads.disabled=true;log('HEAD_DISABLED',tostring(headErr)) end
   end

  end) then
   error('Main.Update(GameTime) 不可用，停止启用以保证世界生命周期清理')
  end
  log('CAP',('loot=%s echo_projectile=%s name=%s'):format(tostring(r.item~=nil),tostring(r.projectile~=nil),tostring(r.nameSetter~=nil)))
  log('READY','v3.0.0 精简定制版; normal-only; no quests; name-only head text; cap 8; boss auto kept'); flush()
 end,debug.traceback)
 if not ok then
  if r then if r.coop then r.coop:clear()end;if r.heads then r.heads:dispose() end;r:restoreAll() end; if b then b:remove() end
  log('START_FAILED',err); flush()
 end
end
local function om_cleanup()
 if r and r.net and r:w('netMode','int32',-1)==1 then pcall(r.net.clearRemote,r.net)end
 if r then if r.coop then r.coop:clear()end;if r.heads then r.heads:dispose() end;if r.collector then r.collector:save() end;r:restoreAll() end; if b then b:remove() end
 if r and r.net and r.net.ready and r:w('netMode','int32',-1)==2 then pcall(r.net.send,r.net,'X','')end
 log('UNLOAD','hooks removed and live NPC stats restored'); flush()
end

return { setup = om_setup, cleanup = om_cleanup }
