-- 头顶招式与脚下特效 2.4.1 / Terraria Android 1.4.5.8 + LuaLoader 1.5.0+（兼容1.6.0）
-- 仅调用 ref 参数绘制重载，不调用 DrawBuffIcon、不写玩家 buff、不激活 CombatText。
-- 按完整参数类型选择 ref Draw；不绑定版本相关的元数据 Token。
local M={}
local runtime
local P
local H, hooks = {}, {}
local disabled, failures, frames = false, 0, 0
local function log(s) runtime.log('HEAD_ROUTE',s) end
local function finite(n)
    return type(n)=='number' and n==n and math.abs(n)<1e8
end
local function value(f,obj,t)
    if not f then return nil end
    return P.get_field_value(f,obj,t)
end
local function rect(x,y,w,h) return string.pack('<i4i4i4i4',x,y,w,h) end
local function release_roots()
    if H.gc_free then
        for _,root in ipairs(H.roots or {}) do pcall(P.invoke,H.gc_free,root) end
    end
    H.roots={}
    H.scratch,H.rect_scratch=nil,nil
end
local function center(obj,fields)
    local x,y=P.get_field_vec2(fields.pos,obj)
    local w,h=value(fields.w,obj,'int32'),value(fields.h,obj,'int32')
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    return x+w/2,y+h/2,x,y,w,h
end
local function asset_texture(asset)
    if not asset then return end
    return value(H.asset_value,asset,'object')
end
local function draw_tex(batch,texture,x,y,w,h,color)
    if not texture or not (finite(x) and finite(y)) then return false end
    -- 独立对象只是 ref 参数缓冲区，未放入游戏的 NPC / CombatText 数组。
    P.set_field_vec2(H.scratch_pos,H.scratch,x,y)
    P.set_field_raw(H.scratch_rect,H.rect_scratch,rect(0,0,w,h))
    P.set_field_raw(H.scratch_color,H.scratch,color)
    local result=P.invoke(H.draw,batch,texture,
        H.posPointer,
        H.rectPointer,
        H.colorPointer)
    if result==false then error('ref Draw 调用失败') end
    return true
end
-- 此手机版Color内存布局由上传源码确认：A B G R。
local WHITE=string.char(255,255,255,255)
local DARK=string.char(255,15,15,15)
local URGENT=string.char(255,60,140,255)
local Native=require('ori_nativeheads')
local G=require('ori_headglyphs')
local cached={};local order={}
-- 与彩色名称同色：异化绿 #4CAF50 / 灾变蓝 #3D8DFF / 终焉红 #E53935（Color 布局 A B G R）
local colors={string.char(255,80,175,76),string.char(255,255,141,61),string.char(255,53,57,229)}
local shade=string.char(255,18,14,12)
local function layout(text)
 if cached[text] then return cached[text] end
 local result={width=0,runs={}};local x=0
 for _,cp in utf8.codes(text) do
  local glyph=G[utf8.char(cp)] or G['?']
  for _,run in ipairs(glyph.runs) do result.runs[#result.runs+1]={x+run[1],run[2],run[3]} end
  x=x+glyph.width+1
 end
 result.width=x
 if #order>=64 then cached[table.remove(order,1)]=nil end
 cached[text]=result;order[#order+1]=text;return result
end
-- 精简版：头顶只显示「重构体名称」，与彩色名称同色
local function headName(s)
 if s.displayName and s.displayName~='' then return s.displayName end
 local Cn=require('ori_core')
 return (Cn.names[s.tier or 1] or '异化体')..'·怪物'..tostring(s.type or 0)
end
local function readable(s) return '〔'..headName(s)..'〕' end
local function fullText(s) return '〔'..headName(s)..'〕' end
local function draw_glyph(batch,texture,x,y,source,color)
 P.set_field_vec2(H.scratch_pos,H.scratch,x,y);P.set_field_raw(H.scratch_rect,H.rect_scratch,source);P.set_field_raw(H.scratch_color,H.scratch,color)
 assert(P.invoke(H.draw,batch,texture,H.posPointer,H.rectPointer,H.colorPointer)~=false,'ref glyph draw failed')
end
local function step(_,args)
 if disabled or not runtime.cfg.enabled then return end
 if not runtime.cfg.headText then return end
 if runtime.player and not runtime:player()then return end
 if args and args[1]==true then return end
 if runtime.world==nil or runtime:w('netMode','int32',-1)==2 then return end
 local user=value(H.active_user,nil,'object') or value(H.primary_user,nil,'object')
 local state=user and value(H.user_state,user,'object');if not state or value(H.menu,state,'bool')==true then return end
 local sx,sy=P.get_field_vec2(H.camera,state);if not(finite(sx) and finite(sy))then return end
 local batch=value(H.batch,nil,'object');if not batch or value(H.begun,batch,'bool')~=true then return end
 H.scratch=P.invoke(H.gc_target,H.scratch_root);H.rect_scratch=P.invoke(H.gc_target,H.rect_root)
 assert(H.scratch and H.rect_scratch,'绘制缓冲GCHandle失效')
 H.posPointer=P.field_pointer(H.scratch_pos,H.scratch);H.rectPointer=P.field_pointer(H.scratch_rect,H.rect_scratch);H.colorPointer=P.field_pointer(H.scratch_color,H.scratch)
 -- 精简版：固定标准档（4 个标签 / 无脚下特效 / 无幻影）
 local maxTargets=4
 local shadow=true

 local pixel=asset_texture(value(H.pixel,nil,'object'));if not pixel then return end
 H.pixel_w,H.pixel_h=value(H.tex_w,pixel,'int32'),value(H.tex_h,pixel,'int32')
 assert(finite(H.pixel_w) and finite(H.pixel_h) and H.pixel_w>0 and H.pixel_h>0,'MagicPixel尺寸无效')
 local sw=runtime:w('screenWidth','int32',1280);local sh=runtime:w('screenHeight','int32',720)
 if H.native and H.native.available then
  local ok,err=pcall(H.native.pump,H.native,128)
  if not ok then H.native.available=false;runtime.log('HEAD_NATIVE_DISABLED',tostring(err))end
 end
 local targets={};local arr=value(H.npcs,nil,'object');if not arr then return end
 for slot,s in pairs(runtime.states) do
  if s.tier then
   local n=P.array_at(arr,slot)
   if n and value(H.n.active,n,'bool')==true and value(H.n.life,n,'int32')>0 and value(H.n.kind,n,'int32')==s.type then
    local x,y,nx,ny,nw,nh=center(n,H.n)
    if x and x-sx>=-512 and x-sx<=sw+512 and ny+nh-sy>=0 and ny-sy<sh+64 then
     local label
     if runtime.cfg.headText and s.tier and not s.aiFailed and not s.echoFailed then
      if H.native and H.native.available then
       local text=fullText(s)
       local ok,value=pcall(H.native.label,H.native,text)
       if ok then label=value else H.native.available=false;runtime.log('HEAD_NATIVE_DISABLED','atlas layout: '..tostring(value));label=layout(readable(s))end
      else label=layout(readable(s))end
     end
     local lx=x-sx-(label and label.width/2 or 0);local ly=ny-sy-32-(label and math.max(0,(label.height or 24)-24)or 0)
     if lx+(label and label.width or 0)>=0 and lx<sw and ny+nh-sy>=0 and ly<sh then
      targets[#targets+1]={s=s,label=label,x=math.floor(lx),y=math.floor(ly),cx=x-sx,ground=ny+nh-sy,wx=x,wy=ny+nh,d=(x-sx-sw/2)^2+(y-sy-sh/2)^2}
     end
    end
   end
  end
 end
 table.sort(targets,function(a,b)return a.d<b.d end)
 -- 幻影分身贴图：只画 sprite，不创建 NPC/实体
 local ghostCount=0
 if H.npcTextures and P.mem_read then
  for i=1,math.min(maxTargets,#targets)do
   local state=targets[i].s
   if state.ghosts and(runtime.lastTick or 0)<(state.ghostUntil or 0)then
    local ok,err=pcall(function()
     local n
     for slot,v in pairs(runtime.states)do if v==state then n=P.array_at(arr,slot);break end end
     local textures=value(H.npcTextures,nil,'object');local texture=textures and asset_texture(P.array_at(textures,state.type))
     if not n or not texture then return end
     local nx,ny=P.get_field_vec2(H.n.pos,n)
     local bright=H.brightness and P.invoke(H.brightness,math.floor(nx/16),math.floor(ny/16))or 1
     if not finite(bright)or bright<=.04 then return end
     local alpha=math.floor(100*math.min(1,bright))
     local frame=P.mem_read(P.field_pointer(H.n.frame,n),0,16)
     local _,_,fw,fh=string.unpack('<i4i4i4i4',frame)
     if fw<=0 or fh<=0 or fw>256 or fh>256 then return end
     for _,g in ipairs(state.ghosts)do
      local gx=g.x-sx+(value(H.n.w,n,'int32')-fw)/2;local gy=g.y-sy+value(H.n.h,n,'int32')-fh
      if gx+fw>=0 and gx<sw and gy+fh>=0 and gy<sh then
       P.set_field_vec2(H.scratch_pos,H.scratch,gx,gy);P.set_field_raw(H.scratch_rect,H.rect_scratch,frame)
       P.set_field_raw(H.scratch_color,H.scratch,string.char(alpha,math.floor(alpha*.8),math.floor(alpha*.6),math.floor(alpha*.8)))
       P.invoke(H.draw,batch,texture,H.posPointer,H.rectPointer,H.colorPointer)
       ghostCount=ghostCount+1
       if not state.ghostDrawLogged then state.ghostDrawLogged=true;runtime.log('ILLUSION_DRAW','type='..state.type..' sprite_only=true')end
      end
     end
    end)
    if not ok then state.ghosts=nil;runtime.log('ILLUSION_DRAW_ERROR',tostring(err))end
   else state.ghosts=nil end
  end
 end
 local function cost(runs,multiplier,stride)
  local n=0;for index,run in ipairs(runs)do if not stride or (index-1)%stride==0 then n=n+multiplier*math.ceil(run[3]/H.pixel_w)end end;return n
 end
 local headBudget=3000-ghostCount
 local drawn,compact=0,0;local used=ghostCount
 for i=1,math.min(maxTargets,#targets)do
  local t=targets[i];local label=t.label
  if label then
   if label.text then
    if H.native:render(batch,label,t.cx,t.y,t.s.breakable and string.char(255,100,220,255)or colors[t.s.tier],draw_glyph,shadow)then drawn=drawn+1;used=used+#label.glyphs*(shadow and 2 or 1) end
   else
   local amount=cost(label.runs,2)
   if amount>headBudget/(math.min(maxTargets,#targets)-i+1)then
    label=layout('〔'..headName(t.s)..'〕');amount=cost(label.runs,2)
    if amount<=headBudget then compact=compact+1 end
   end
   if amount<=headBudget then
    headBudget=headBudget-amount;used=used+amount
    local x=math.floor(t.cx-label.width/2)
    for _,run in ipairs(label.runs)do
     local left=run[3];local xx=x+run[1]
     while left>0 do
      local width=math.min(left,H.pixel_w)
      draw_tex(batch,pixel,xx+1,t.y+run[2]+1,width,1,shade)
      draw_tex(batch,pixel,xx,t.y+run[2],width,1,t.s.breakable and string.char(255,100,220,255)or colors[t.s.tier])
      left=left-width;xx=xx+width
     end
    end
    drawn=drawn+1
   end
   end
  end
 end
 frames=frames+1

end
local function safe_step(instance,args)
    if disabled then return end
    local ok,e=xpcall(function() step(instance,args) end,function(e)
        return debug and debug.traceback and debug.traceback(tostring(e),2) or tostring(e)
    end)
    if ok then failures=0;return end
    failures=failures+1;log('绘制错误 '..failures..': '..tostring(e))
    if failures>=3 then disabled=true;log('已停用回调；不在回调内卸载钩子') end
end
local function field(t,name)
    local f=P.get_field(t,name)
    assert(f,'缺少字段 '..name)
    return f
end
local function setup()
    
    log('初始化头顶文字 2.4.1；需要 Android Terraria 1.4.5.8 / LuaLoader 1.5.0+（兼容1.6.0）')
    if type(P.get_method_by_param_types)~='function'
       or type(P.make_generic_type)~='function' or type(P.field_pointer)~='function' then
        log('加载器缺少绘制接口，请升级到 LuaLoader 1.5.0+（兼容1.6.0）；未挂载游戏钩子')
        disabled=true;return
    end
    local ok,e=pcall(function()
        local main=P.get_type('Terraria','Main')
        local nt=P.get_type('Terraria','NPC')
        local pt=P.get_type('Terraria','Player')
        local st=P.get_type('','LocalUserGameState')
        local sb=P.get_type('Microsoft.Xna.Framework.Graphics','SpriteBatch')
        local tx=P.get_type('Microsoft.Xna.Framework.Graphics','Texture2D')
        local assets=P.get_type('Terraria.GameContent','TextureAssets')
        local generic=P.get_type('ReLogic.Content','Asset`1')
        assert(main and nt and pt and st and sb and tx and assets and generic,'游戏类型不匹配')
        H.asset_value=field(P.make_generic_type(generic,{tx}),'Value')
        local vec=P.get_type('Microsoft.Xna.Framework','Vector2')
        local rectangle=P.get_type('Microsoft.Xna.Framework','Rectangle')
        local color=P.get_type('Microsoft.Xna.Framework.Graphics','Color')
        assert(vec and rectangle and color,'缺少绘制参数类型')
        -- 内核将 ref 参数解析为它对应的类；Rectangle? 为另一个类，不会匹配。
        -- 四参重载以 Color 与 VertexColors 区分，不能只按参数数量选择。
        H.draw=P.get_method_by_param_types(sb,'Draw',{tx,vec,rectangle,color})
        assert(H.draw,'找不到 Draw(Texture2D,ref Vector2,ref Rectangle,ref Color)')
        log('参数类型匹配绘制方法成功')
        H.tex_w=field(tx,'Width')
        H.tex_h=field(tx,'Height')
        assert(H.tex_w and H.tex_h,'缺少贴图尺寸接口')
        local user_t=P.get_type('','LocalUser')
        local users_t=P.get_type('','UserManagement')
        assert(user_t and users_t,'缺少本地用户类型')
        H.active_user=field(user_t,'Active')
        H.primary_user=field(users_t,'PrimaryPlayer')
        H.user_state=field(user_t,'GameState')
        -- Instance是ThreadStatic；当前加载器字段指针接口不支持，不能读取它。
        H.menu=field(st,'gameMenu');H.my_player=field(st,'myPlayer');H.camera=field(st,'screenPosition')
        H.players=field(main,'player');H.npcs=field(main,'npc');H.batch=field(main,'spriteBatch')
        H.begun=field(sb,'_beginCalled')
        H.pixel=field(assets,'MagicPixel');H.npcTextures=field(assets,'Npc')
        local lighting=P.get_type('Terraria','Lighting');local integer=P.get_basic_type and P.get_basic_type('int32')
        H.brightness=lighting and integer and P.get_method_by_param_types(lighting,'Brightness',{integer,integer})
        log('脚下光照接口='..tostring(H.brightness~=nil)..'；不可用时不绘制脚下特效')
        local function entity(t)
            return {pos=field(t,'position'),w=field(t,'width'),h=field(t,'height'),active=field(t,'active')}
        end
        H.p=entity(pt);H.n=entity(nt)
        for key,name in pairs({life='life',friendly='friendly',boss='boss',kind='type',
            frame='frame',scale='scale'}) do H.n[key]=field(nt,name) end
        local ct=P.get_type('Terraria','CombatText')
        local gc=P.get_type('System.Runtime.InteropServices','GCHandle')
        assert(gc,'缺少GCHandle类型')
        local gc_alloc=P.get_method(gc,'GetTargetHandle',3)
        H.gc_target=P.get_method(gc,'GetTarget',1)
        H.gc_free=P.get_method(gc,'FreeHandle',1)
        assert(gc_alloc and H.gc_target and H.gc_free,'缺少GCHandle保活接口')
        H.roots={}
        local function rooted(t)
            local obj=P.new_instance(t)
            assert(obj,'无法分配独立绘制缓冲')
            -- GetTargetHandle返回IntPtr，避开GCHandle值类型返回的ABI编组。
            -- 2=Normal强引用；Boehm GC不移动对象，不需要Pinned。
            local root=P.invoke(gc_alloc,obj,nil,2)
            assert(root and root~=false,'GCHandle保活分配失败')
            H.roots[#H.roots+1]=root
            return obj,root
        end
        H.scratch,H.scratch_root=rooted(ct)
        H.rect_scratch,H.rect_root=rooted(nt)
        H.scratch_pos=field(ct,'position');H.scratch_color=field(ct,'color');H.scratch_rect=H.n.frame
        H.posPointer=P.field_pointer(H.scratch_pos,H.scratch)
        H.rectPointer=P.field_pointer(H.scratch_rect,H.rect_scratch)
        H.colorPointer=P.field_pointer(H.scratch_color,H.scratch)
        assert(H.posPointer and H.rectPointer and H.colorPointer,'绘制缓冲字段指针不可用')
        log('两个绘制缓冲已注册GC强引用')
        H.native=Native.new(P,runtime.log)
        local method=P.get_method(main,'DrawNPCs',1)
        assert(method,'缺少 Main.DrawNPCs')
        local h=P.install_hook(method,{postfix=safe_step})
        assert(h,'钩子安装失败');hooks[#hooks+1]=h
        log('初始化成功：ref贴图绘制、真实相机、独立缓冲；没有战斗文字槽位写入')
    end)
    if not ok then disabled=true;release_roots();log('初始化失败: '..tostring(e)) end
end
local function dispose()
    disabled=true
    for _,h in ipairs(hooks) do pcall(function() h:remove() end) end
    hooks={};if H.native then H.native:clear()end;release_roots();log('已卸载，GC强引用已释放')
end
function M.install(r)
 disabled=false;failures=0;frames=0;H={};hooks={};cached={};order={}
 runtime=r;P=r.b.p;setup()
 if disabled then return nil end
 return {ghostAvailable=H.npcTextures~=nil and P.mem_read~=nil,clear=function() cached={};order={};if H.native then H.native:clear()end end,update=function()end,dispose=dispose}
end
M.readable=readable;M.layout=layout;M.fullText=fullText
return M
