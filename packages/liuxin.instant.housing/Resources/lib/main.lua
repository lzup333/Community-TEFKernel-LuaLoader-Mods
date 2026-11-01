mod.meta={pkg_id='community.instant.housing',version='0.4.8',version_code=37,api_version=1}
local Adapter=require('adapter')
local Builder=require('builder')
local UI=require('ui')
local adapter,controller,ui,workbench
local function readableError(err)
 local message=tostring(err)
 -- Lua adds an absolute private-dir source path to assertion errors. Keep the
 -- actionable part in the narrow in-game status line.
 return message:match('%.lua:%d+: (.+)$') or message
end
function mod.init()
 if controller then return end
 controller=Builder.new({})
 ui=UI.new(mod,controller)
 if mod.platform~='android' or mod.arch~='arm64' then controller.disabled=true;controller:fail('此测试包仅支持 Android ARM64');return end
 local err
 adapter,err=Adapter.new(mod.patch or {})
 if not adapter then
  controller.disabled=true;controller:fail('初始化禁用：'..readableError(err))
  mod.error('[一键建造] '..tostring(err));return
 end
 controller.a=adapter
 local featureOK,feature=pcall(function()return require('workbench').new(mod,adapter,controller)end)
 if featureOK then workbench=feature;ui.workbench=workbench
 else ui.featureError=readableError(feature);mod.error('[一键建造·蓝图库] '..tostring(feature))end
 local ok,e=pcall(function() adapter:attach(function()
  local before=controller.state
  controller:tick()
  if workbench then workbench:tick()end
  if controller.state=='error' and before~='error' then mod.error('[一键建造] '..controller.message) end
 end) end)
 if not ok then
  controller.disabled=true;controller:fail('初始化禁用：'..readableError(e))
  if workbench then workbench:close();workbench=nil;ui.workbench=nil end
  adapter:close();adapter=nil;mod.error('[一键建造] '..tostring(e))
 end
end
function mod.on_gui()
 if not ui then return end
 ui:draw()
end
function mod.cleanup()
 if controller then controller:cancel() end
 if ui then ui:close() end
 if workbench then workbench:close()end
 if adapter then adapter:close() end
 adapter=nil;controller=nil;ui=nil;workbench=nil
end
