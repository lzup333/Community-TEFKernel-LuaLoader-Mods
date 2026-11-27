-- Read the same raw Cursor data used by LuaLoader's own Android GUI.
-- Scalar math mirrors PE AdjustRealScreenForUI (0xE940FC in supplied binary),
-- avoiding an unsupported Vector2 return through the generic Lua invoker.
local M={}
function M.new(p,api)
 local T,F,Q=api.typ,api.field,api.method
 local CM=T('','CursorManager');local Cursor=T('','Cursor')
 local Main=T('Terraria','Main');local Screen=T('UnityEngine','Screen');local Time=T('UnityEngine','Time')
 local Runner=T('','XNAUnityRunner');local UI=T('','XNAUICameraSettings')
 local f={instance=F(CM,'Instance',true),position=F(Cursor,'Position',false,8),
  down=F(Cursor,'Down',false,1),wasDown=F(Cursor,'WasDown',false,1),id=F(Cursor,'Id',false,4),dead=F(Cursor,'Dead',false,1),
  runner=F(Runner,'_instance',true),ui=F(Runner,'UICameraSettings',false),
  uw=F(UI,'realVirtualScreenWidth',false,4),uh=F(UI,'realVirtualScreenHeight',false,4),
  ox=F(UI,'realVirtualScreenOffsetX',false,4),oy=F(UI,'realVirtualScreenOffsetY',false,4)}
 local m={count=Q(CM,'GetNumCursors',{},nil,false),cursor=Q(CM,'GetCursor',{'int32'},{'index'},false),
  width=Q(Screen,'get_width',{},nil,true),height=Q(Screen,'get_height',{},nil,true),
  time=Q(Time,'get_realtimeSinceStartup',{},nil,true),frame=Q(Time,'get_frameCount',{},nil,true),
  guiW=Q(Main,'get_screenWidth',{},nil,true),guiH=Q(Main,'get_screenHeight',{},nil,true)}
 local input={}
 local function get(k,o,ty)return p.get_field_value(f[k],o,ty or 'object')end
 function input:sample()
  local now=p.invoke(m.time);assert(type(now)=='number'and now==now,'触摸计时不可读')
  local cm,runner=get('instance'),get('runner');if not cm or not runner then return now,{}end
  local ui=get('ui',runner);if not ui then return now,{}end
  local w,h=p.invoke(m.width),p.invoke(m.height)
  local uw,uh=get('uw',ui,'int32'),get('uh',ui,'int32');local ox,oy=get('ox',ui,'int32'),get('oy',ui,'int32')
  assert(type(w)=='number'and type(h)=='number'and w>0 and h>0 and uw>0 and uh>0,'触摸视口无效')
  local count=p.invoke(m.count,cm);assert(type(count)=='number'and count>=0 and count<=32,'触摸数量无效')
  local out={}
  for i=0,count-1 do
   local c=p.invoke(m.cursor,cm,i)
   if c and not get('dead',c,'bool')then
    local down=get('down',c,'bool')
    if down then
     local x,y=p.get_field_vec2(f.position,c)
     assert(type(x)=='number'and type(y)=='number'and x==x and y==y,'触摸位置无效')
     out[#out+1]={id=get('id',c,'int32'),down=true,wasDown=get('wasDown',c,'bool'),
      x=math.floor(x*uw/w)+ox,y=math.floor((h-y)*uh/h)+oy}
    end
   end
  end
  return now,out,{width=p.invoke(m.guiW),height=p.invoke(m.guiH),frame=p.invoke(m.frame)}
 end
 return input
end
return M
