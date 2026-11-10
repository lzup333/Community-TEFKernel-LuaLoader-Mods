mod.meta={pkg_id='liuxin.bossbar.classic',version='1.2.2',version_code=15,api_version=1}
local config=require('config')
local encounters=require('bossbar.encounter')
local hooks={}
local assets,renderer,bridge,touch
local failed=false
local first_draw=false
local received_draw=false
local last_encounter_signature
local diagnostic='BossBarClassic 1.0.1\n'
local diagnostic_count=0
local function record(message)
 diagnostic_count=diagnostic_count+1
 if diagnostic_count>200 then return end
 diagnostic=diagnostic..tostring(message)..'\n'
 if mod.write_file then pcall(mod.write_file,'bossbar_runtime.log',diagnostic) end
end
local function stop(reason)
 if failed then return end
 failed=true
 record('fallback: '..tostring(reason))
 mod.error('[BossBarClassic] 已恢复原版血条: '..tostring(reason))
end
local pending
local function release_pending()
 if pending and pending.icon_root then
  pcall(bridge.unroot,bridge,pending.icon_root)
 end
 pending=nil
end
local function capture(_,args)
 if failed or not config.enabled then return false end
 local ok,result=pcall(function()
  if not received_draw then
   received_draw=true
   record('mobile data captured: '..tostring(args[1])..'/'..tostring(args[2]))
  end
  local sb,tracking=bridge:snapshot(args[2])
  if not sb then return false end
  release_pending()
  local icon_root
  if args[3] then icon_root=assert(bridge:root(args[3]),'头像强引用失败') end
  pending={sb=sb,life=args[1],max=args[2],icon=args[3],shield=args[5],shieldmax=args[6],tracking=tracking,icon_root=icon_root}
  return first_draw
 end)
 if not ok then stop(result);release_pending();return false end
 return result==true
end
local function draw_hud()
 if failed or not config.enabled or not pending then if touch then touch.visible=false end; release_pending();return end
 local frame=pending
 local begun=false
 local ok,result=pcall(function()
  assets:prepare(config.style)
  local encounter=encounters.resolve(bridge,frame.tracking)
  if encounter then
   local signature=encounter.family..':'..tostring(frame.tracking.index)..':'..#(encounter.bars or {})..':'..#encounter.parts
   if signature~=last_encounter_signature then
    last_encounter_signature=signature
    record('multi entity frame: '..signature)
   end
  else last_encounter_signature=nil end
  bridge:begin_hud(frame.sb)
  begun=true
  local now=bridge:call(bridge.time)
  local drawn
  if encounter then drawn=renderer:draw_encounter(frame,encounter,now)
  else drawn=renderer:draw(frame.sb,frame.life,frame.max,frame.icon,frame.shield,frame.shieldmax,frame.tracking,now) end
  if drawn and touch then touch:draw(frame.sb,renderer.last_layout) end
  return drawn
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
  record('HUD UI pass submitted after Main.Draw; original mobile bar suppression enabled')
  bridge.trace=nil
 end
end
function setup()
 record('setup '..tostring(mod.platform)..'/'..tostring(mod.arch))
 if mod.platform~='android' or mod.arch~='arm64' then
  mod.warn('[BossBarClassic] 此包仅针对 Android arm64'); return
 end
 local ok,err=pcall(function()
  local p=assert(mod.patch,'缺少 patch 接口')
  for _,name in ipairs({'get_method_by_names','get_method_by_param_types','get_method_by_signature','method_is_static','get_field_raw','object_root','object_unroot','struct_arg','struct_arg_set','invoke_value_args'}) do
   assert(type(p[name])=='function','加载器缺少 '..name)
  end
  bridge=require('bossbar.bridge').new(p)
  bridge.trace=record
  assets=require('bossbar.assets').new(bridge,mod.private_dir,mod.file_exists)
  renderer=require('bossbar.render').new(bridge,assets,config)
  require('bossbar.settings').new(mod,config)
  local touch_ok,touch_result=pcall(require('bossbar.touch').new,mod,bridge,config)
  if touch_ok then touch=touch_result; touch.a=assets; touch.src=bridge:source(0,0,1,1) else record('touch unavailable: '..tostring(touch_result)) end
  local function install(method,callbacks)
   local h=assert(p.install_hook(method,callbacks),'Hook 安装失败')
   hooks[#hooks+1]=h
  end
  install(bridge.draw_main,{prefix=release_pending,postfix=draw_hud})
  install(bridge.draw_mobile,{prefix=capture})
  if touch then
   local update=assert(p.get_method(bridge.main,'Update',1),'缺少 Main.Update')
   install(update,{prefix=function()
    if not failed and touch then
     local ok,err=pcall(touch.update,touch)
     if not ok then record('touch disabled: '..tostring(err)); touch=nil end
    end
    return false
   end})
  end
  record('GUIBossBar data capture and Main.Draw HUD pass registered')
  mod.info('[BossBarClassic] 手机 Boss 血条入口已注册，底部居中')
 end)
 if not ok then
  stop(err)
  for _,h in ipairs(hooks) do pcall(function() h:remove() end) end
  hooks={}
 end
end
function mod.cleanup()
 failed=true
 release_pending()
 for i=#hooks,1,-1 do pcall(function() hooks[i]:remove() end) end
 hooks={}
 if assets then assets:cleanup() end
 assets=nil; renderer=nil; bridge=nil; touch=nil
end
todo_list={'setup'}
