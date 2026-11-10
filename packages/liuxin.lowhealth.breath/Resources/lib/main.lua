mod.meta={pkg_id='liuxin.lowhealth.breath',version='1.0.2',version_code=7,api_version=1}
local bridge,hook,texture,owned,failed,logged
local threshold=0.30
local function pin(obj,unity)
 assert(obj,'贴图对象为空')
 local root=assert(bridge:root(obj),'无法持有纹理')
 owned[#owned+1]={object=obj,root=root,unity=unity}
 return obj
end
local function load_border()
 assert(not mod.file_exists or mod.file_exists('lib/ui/border.png'),'找不到边框 PNG')
 local bytes=pin(bridge:call(bridge.read_bytes,mod.private_dir..'/lib/ui/border.png'))
 local u=pin(bridge:construct(bridge.unity_ctor,2,2,4,false),true)
 assert(bridge:call(bridge.load_png,u,bytes,false)==true,'PNG 解码失败')
 bridge:call(bridge.filter,u,1)
 bridge:call(bridge.wrap,u,1)
 return pin(bridge:construct(bridge.xna_ctor,u))
end
local function draw()
 if failed then return end
 local p=bridge.p
 local ok,err=pcall(function()
  if p.invoke(bridge.game_menu)==true then return end
  local index=bridge:call(bridge.my_player)
  local players=p.get_field_value(bridge.players,nil,'object')
  if not players or type(index)~='number' or index<0 or index>=p.array_length(players) then return end
  local player=p.array_at(players,index)
  if not player or p.get_field_value(bridge.dead,player,'bool') or not p.get_field_value(bridge.active_player,player,'bool') then return end
  local life=p.get_field_value(bridge.player_life,player,'int32')
  local maximum=p.get_field_value(bridge.player_max,player,'int32')
  if not life or not maximum or maximum<=0 or life<=0 or life/maximum>threshold then return end
  local sb=p.get_field_value(bridge.sprite_batch,nil,'object')
  if not sb then return end
  local w,h=bridge:dimensions()
  if not w or not h or w<=0 or h<=0 then return end
  if not logged then
   logged=true
   local ok1,uw=pcall(p.invoke,bridge.unity_width);local ok2,uh=pcall(p.invoke,bridge.unity_height)
   local message=('Main.screen=%sx%s; Unity.Screen=%sx%s'):format(tostring(w),tostring(h),ok1 and tostring(uw) or '?',ok2 and tostring(uh) or '?')
   mod.info('[残血边框诊断] '..message)
   if mod.write_file then pcall(mod.write_file,'lowhealth_screen_diagnostic.txt',message) end
  end
  if not texture then texture=load_border() end
  local uw=p.invoke(bridge.unity_width);local uh=p.invoke(bridge.unity_height)
  if type(uw)~='number' or type(uh)~='number' or uw<=0 or uh<=0 then return end
  local x1,y1=bridge:adjust_screen(bridge.adjust_ui,0,0)
  local x2,y2=bridge:adjust_screen(bridge.adjust_ui,uw,uh)
  if type(x1)~='number' or type(y1)~='number' or type(x2)~='number' or type(y2)~='number' then return end
  local left,top=math.min(x1,x2),math.min(y1,y2)
  local width,height=math.abs(x2-x1),math.abs(y2-y1)
  if width<1 or height<1 or width>w*5 or height>h*5 then return end
  local t=bridge:call(bridge.time) or 0
  local intensity=0.48+0.52*(0.5-0.5*math.cos(t*2*math.pi/1.92))
  local alpha=math.floor(255*intensity+0.5)
  local begun=false
  local draw_ok,draw_err=pcall(function()
   bridge:begin_hud(sb);begun=true
   bridge:draw_sprite(sb,texture,left,top,width,height,bridge:source(0,0,1920,1080),bridge:color(alpha,alpha,alpha,alpha))
  end)
  if begun then local end_ok,end_err=pcall(bridge.end_hud,bridge,sb);if not end_ok then error(end_err) end end
  if not draw_ok then error(draw_err) end
 end)
 if not ok then failed=true;mod.error('[残血呼吸边框] 已停用：'..tostring(err)) end
end
function setup()
 if mod.platform~='android' or mod.arch~='arm64' then mod.warn('[残血呼吸边框] 仅支持 Android ARM64');return end
 local ok,err=pcall(function()
  local p=assert(mod.patch)
  for _,name in ipairs({'object_root','object_unroot','struct_arg','struct_arg_set','invoke_value_args'}) do
   assert(type(p[name])=='function','LuaLoader 3.1+ 缺少 '..name)
  end
  bridge=require('bossbar.bridge').new(p);owned={}
  local player=assert(p.get_type('Terraria','Player'))
  local function field(t,n) return assert(p.get_field(t,n),'缺少字段 '..n) end
  local function getter(t,n) return assert(p.get_method(t,'get_'..n,0),'缺少属性 '..n) end
  bridge.game_menu=getter(bridge.main,'gameMenu');bridge.my_player=getter(bridge.main,'myPlayer')
  local screen=assert(p.get_type('UnityEngine','Screen'));bridge.unity_width=getter(screen,'width');bridge.unity_height=getter(screen,'height')
  local runner=assert(p.get_type('','XNAUnityRunner'));bridge.adjust_ui=assert(p.get_method(runner,'AdjustRealScreenForUI',1),'缺少屏幕坐标转换')
  bridge.players=field(bridge.main,'player');bridge.player_life=field(player,'statLife');bridge.player_max=field(player,'statLifeMax2')
  bridge.active_player=field(player,'active');bridge.dead=field(player,'dead')
  hook=assert(p.install_hook(bridge.draw_main,{postfix=draw}),'无法安装绘制钩子')
  mod.info('[残血呼吸边框] 已启用：生命值不高于 30% 时显示')
 end)
 if not ok then failed=true;mod.error('[残血呼吸边框] 初始化失败：'..tostring(err)) end
end
function mod.cleanup()
 failed=true
 if hook then pcall(function() hook:remove() end);hook=nil end
 if bridge and owned then for i=#owned,1,-1 do local e=owned[i];if e.unity then pcall(bridge.call,bridge,bridge.destroy,e.object) end;pcall(bridge.unroot,bridge,e.root) end end
 owned={};texture=nil
end
todo_list={'setup'}






