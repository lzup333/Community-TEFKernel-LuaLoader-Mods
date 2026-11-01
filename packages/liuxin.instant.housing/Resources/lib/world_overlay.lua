-- Queue world selection through the loader's working UI rendering pass.
-- No extra Main.Draw hook, SpriteBatch.Begin, or managed drawing from Lua.
local View=require('selection_view')
local M={}
function M.new(a,p,api,selection,onError)
 local T,F=api.typ,api.field
 local Main=T('Terraria','Main');local State=T('','LocalUserGameState');local User=T('','LocalUser')
 local Runner=T('','XNAUnityRunner');local UI=T('','XNAUICameraSettings');local World=T('','XNAWorldCameraSettings')
 local f={active=F(User,'Active',true),state=F(User,'GameState',false),instance=F(State,'Instance',true),
  position=F(State,'screenPosition',false,8),width=F(State,'screenWidth',false,4),height=F(State,'screenHeight',false,4),
  runner=F(Runner,'_instance',true),ui=F(Runner,'UICameraSettings',false),world=F(Runner,'WorldCameraSettings',false),
  uw=F(UI,'realVirtualScreenWidth',false,4),uh=F(UI,'realVirtualScreenHeight',false,4),
  ox=F(UI,'realVirtualScreenOffsetX',false,4),oy=F(UI,'realVirtualScreenOffsetY',false,4),
  ww=F(World,'_cameraWidth',false,4),wh=F(World,'_cameraHeight',false,4)}
 local overlay={}
 local function get(k,o,ty)return p.get_field_value(f[k],o,ty or 'object')end
 local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e9 end
 function overlay:updateView()
  if not selection.visible then return false end
  local ok,v=pcall(function()
   if not a.current or a.current.worldKey~=selection.worldKey or a:get('gameMenu')then return end
   local user=get('active');local state=user and get('state',user)or get('instance')
   local runner=get('runner');if not state or not runner then return end
   local ui,world=get('ui',runner),get('world',runner);if not ui or not world then return end
   local x,y=p.get_field_vec2(f.position,state)
   local v={x=x,y=y,width=get('width',state,'int32'),height=get('height',state,'int32'),
    uiWidth=get('uw',ui,'int32'),uiHeight=get('uh',ui,'int32'),offsetX=get('ox',ui,'int32'),offsetY=get('oy',ui,'int32'),
    worldWidth=get('ww',world,'int32'),worldHeight=get('wh',world,'int32')}
   for k,n in pairs(v)do assert(finite(n),'视口字段无效 '..k)end
   for _,k in ipairs{'width','height','uiWidth','uiHeight','worldWidth','worldHeight'}do assert(v[k]>0 and v[k]<=32768,'视口尺寸无效')end
   return v
  end)
  selection.screenView=ok and v or nil
  if not ok and self.lastError~=v then self.lastError=v;onError(tostring(v))end
  return ok and v~=nil
 end
 function overlay:draw(g,pixel,panelWidth,contentHeight)
  if not selection.visible then return end
  -- Read current render-frame camera, not a potentially stale Update snapshot.
  if not self:updateView()or not pixel or not g.get_pos or not g.image then return end
  local v=selection.screenView;local wx,wy=g.get_pos();local ox,oy=View.origin(v,wx,wy)
  local mask
  if panelWidth and contentHeight then
   local scale=math.max(1,math.min(2.5,math.min(v.width,v.height)/720))
   mask={x=wx-3,y=wy-3,w=panelWidth+6,h=contentHeight+56*scale+6}
  end
  local function paint(x,y,w,h,color)
   for _,b in ipairs(View.subtract({x,y,w,h},mask))do g.image(pixel,b[1]-ox,b[2]-oy,b[3],b[4],color)end
  end
  local r=View.project(selection,v)
  local function bands(box,t,color)
   for _,b in ipairs(View.bands(box,v.width,v.height,t))do paint(b[1],b[2],b[3],b[4],color)end
  end
  bands({x=r.x-2,y=r.y-2,w=r.w+4,h=r.h+4},7,{10,18,24,255})
  bands(r,3,{76,255,142,255})
  local clipped=r.x<0 or r.y<0 or r.x+r.w>v.width or r.y+r.h>v.height
  if clipped then
   local msg=('选区 %d×%d · %s%s%s%s'):format(selection.width,selection.height,r.x<0 and '左超出 'or '',r.y<0 and '上超出 'or '',r.x+r.w>v.width and '右超出 'or '',r.y+r.h>v.height and '下超出 'or '')
   local x=math.max(4,math.min(v.width-280,r.x));local y=math.max(4,math.min(v.height-24,r.y))
   if not mask or x+280<mask.x or x>mask.x+mask.w or y+24<mask.y or y>mask.y+mask.h then g.text_at(x-ox,y-oy,msg,{76,255,142,255},0.55)end
  end
  if not selection.renderLogged then
   selection.renderLogged=true
   if selection.trace then selection.trace(('UI队列选框：%.1f,%.1f %.1fx%.1f；映射%.3f/%.3f'):format(r.x,r.y,r.w,r.h,v.uiWidth/v.worldWidth,v.uiHeight/v.worldHeight))end
  end
 end
 function overlay:close()selection.screenView=nil end
 return overlay
end
return M
