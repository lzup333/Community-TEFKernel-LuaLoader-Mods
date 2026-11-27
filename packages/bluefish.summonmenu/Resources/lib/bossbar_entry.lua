-- ============================================================================
-- Boss 血条（合并自 liuxin.bossbar.classic v1.5.0）
--   相对原版：只保留「简洁战斗」样式、无设置页；四项性能优化（不做头像强引用、
--   多部位扫描降频到 6 帧、屏幕度量缓存、去每帧贴图预热）；诊断日志默认不落盘；
--   多实体签名去抖动；托管字符串 LRU 缓存 8 条。
-- ============================================================================
local config=require('bossbar.config')
local encounters=require('bossbar.encounter')
local hooks={}
local assets,renderer,bridge
local failed=false
local first_draw=false
local received_draw=false

-- ===== v1.2.0 性能优化开关 =====
-- PIN_ICON：是否每帧对头像做 GCHandle 强引用。
--   采集（GUIBossBar.Draw prefix）与绘制（Main.Draw postfix）在同一帧内闭环，
--   托管对象在帧内不会被 GC 回收，因此默认关闭，省掉每帧 2~3 次托管调用与句柄分配。
--   若个别机型出现头像丢失/异常，改回 true 即恢复 v1.1.0 行为。
local PIN_ICON=false
-- SCAN_EVERY：多部位 Boss（双子/骷髅王/机械骷髅王/石巨人/月总/飞碟/荷兰飞盗船）
--   的全量 NPC 扫描间隔（帧）。1=每帧（v1.1.0 行为）；6 帧≈100ms，
--   副血条数值延迟人眼无感，而扫描开销降到 1/6。普通 Boss 不触发扫描。
local SCAN_EVERY=6

-- v6.3.10：诊断记录机制全部移除（不累积字符串、绝不写盘）
local function record() end
local function stop(reason)
 if failed then return end
 failed=true
 record()
 mod.error('[BossBarClassic] 已恢复原版血条: '..tostring(reason))
end
local pending
local function release_pending()
 if pending and pending.icon_root then
  pcall(bridge.call,bridge,bridge.unroot,pending.icon_root)
 end
 pending=nil
end
local function capture(_,args)
 if failed or not config.enabled then return false end
 local ok,result=pcall(function()
  if not received_draw then
   received_draw=true
   record()
  end
  local sb,tracking=bridge:snapshot(args[2])
  if not sb then return false end
  -- v2.17.0: 与 Boss 指针联动 —— 血条捕获帧即「场上确有 Boss」的最强信号，
  -- 置一个全局标志，指针模块待机时读到就立刻点亮（纯 Lua 写，零成本）。
  _G.g_bb_boss_seen=true
  release_pending()
  local icon_root
  if PIN_ICON and args[3] then icon_root=assert(bridge:root(args[3]),'头像强引用失败') end
  pending={sb=sb,life=args[1],max=args[2],icon=args[3],shield=args[5],shieldmax=args[6],tracking=tracking,icon_root=icon_root}
  return first_draw
 end)
 if not ok then stop(result);release_pending();return false end
 return result==true
end
-- 多部位扫描节流：同一目标在 SCAN_EVERY 帧内复用上次结果。
local scan_tick=0
local scan_key=nil
local scan_value=nil
local scan_cached=false
local function resolve_encounter(track)
 if not encounters.family(track.type) then
  scan_key=nil;scan_value=nil;scan_cached=false
  return nil
 end
 scan_tick=scan_tick+1
 if scan_cached and scan_key==track.key and SCAN_EVERY>1 and (scan_tick%SCAN_EVERY)~=0 then
  return scan_value
 end
 local value=encounters.resolve(bridge,track)
 scan_key=track.key;scan_value=value;scan_cached=true
 return value
end
local function draw_hud()
 if failed or not config.enabled or not pending then release_pending();return end
 local frame=pending
 local begun=false
 local ok,result=pcall(function()
  -- 贴图只在未就绪时预热一次；render 内部同样有缓存命中。
  if not assets.ready then assets:prepare(config.style) end
  local encounter=resolve_encounter(frame.tracking)
  bridge:begin_hud(frame.sb)
  begun=true
  local now=bridge:call(bridge.time)
  if encounter then return renderer:draw_encounter(frame,encounter,now) end
  return renderer:draw(frame.sb,frame.life,frame.max,frame.icon,frame.shield,frame.shieldmax,frame.tracking,now)
 end)
 -- 即使文字/布局报错，也关闭自己的批次并恢复临时状态。
 if begun then
  local ended,err=pcall(bridge.end_hud,bridge,frame.sb)
  if not ended then ok=false;result=err end
 end
 release_pending()
 if not ok then stop(result);return end
 if result and not first_draw then
  first_draw=true
  record()
  bridge.trace=nil
 end
end
local function bb_setup()
 record()
 if mod.platform~='android' or mod.arch~='arm64' then
  mod.warn('[BossBarClassic] 此包仅针对 Android arm64'); return
 end
 local ok,err=pcall(function()
  -- v8.9.14 曾在这里停用钩子安装（排查「创建新地图闪退」）。
  --   v8.9.56 恢复：闪退真因是 tg 模块 PlaceTile 的高频跨界读，跟绘制无关。
  -- ===== 原实现（v8.9.56 恢复）=====
  local p=assert(mod.patch,'缺少 patch 接口')
  for _,name in ipairs({'get_method_by_names','get_method_by_param_types','get_method_by_signature','method_is_static','get_field_raw','object_root','object_unroot','struct_arg','struct_arg_set','invoke_value_args'}) do
   assert(type(p[name])=='function','加载器缺少 '..name)
  end
  bridge=require('bossbar.bridge').new(p)
  bridge.trace=record
  assets=require('bossbar.assets').new(bridge,mod.private_dir,mod.file_exists)
  renderer=require('bossbar.render').new(bridge,assets,config)
  local function install(method,callbacks)
   local h=assert(p.install_hook(method,callbacks),'Hook 安装失败')
   hooks[#hooks+1]=h
  end
  local function draw_hud_ext()
   pcall(draw_hud)
   local f=_G.EXT_DH and _G.EXT_DH.main_draw
   if f then pcall(f) end
  end
  install(bridge.draw_main,{prefix=release_pending,postfix=draw_hud_ext})
  if _G.EXT_DH then _G.EXT_DH.main_draw_hosted=true end
  install(bridge.draw_mobile,{prefix=capture})
  record()
  mod.info('[BossBarClassic] 手机 Boss 血条入口已注册，底部居中')
 end)
 if not ok then
  stop(err)
  for _,h in ipairs(hooks) do pcall(function() h:remove() end) end
  hooks={}
 end
end
local function bb_cleanup()
 failed=true
 release_pending()
 for i=#hooks,1,-1 do pcall(function() hooks[i]:remove() end) end
 hooks={}
 if assets then assets:cleanup() end
 assets=nil; renderer=nil; bridge=nil
 scan_cached=false; scan_key=nil; scan_value=nil
end

return bb_setup, bb_cleanup
