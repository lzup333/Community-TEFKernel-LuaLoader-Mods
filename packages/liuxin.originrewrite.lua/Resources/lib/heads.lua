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
local Native=require('nativeheads')
local G=require('headglyphs')
local FootVariants=require('footart')
local QualityFoot=require('footartquality')
local cached={};local order={}
local colors={string.char(255,80,190,75),string.char(255,255,145,60),string.char(255,65,60,230)}
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
local function readable(s)
 if s.action=='guard'then return s.phase=='guard'and '〔守御〕'or s.guardCounter and '〔守御·反击〕'or '〔守御·防御〕'end
 if s.breakable then return '〔破招〕'end
 local text=s.breakable and '破招 '..(s.headText or '')or(s.headText or '')
 for _,cp in utf8.codes(text) do
  if not G[utf8.char(cp)] then
   text=(s.breakable and '破招 'or'')..(s.style and require('styles').names[s.style]..' 'or'')..(#(s.recipes or {})>1 and (s.recipeIndex..'/'..#s.recipes..' ') or '')..'怪物'..tostring(s.echo and s.echo.donor or s.type)..'·'..(s.pattern or '单发')
   break
  end
 end
 return '〔'..text..'〕'
end
local function fullText(s)
 if s.combat or(s.headText or ''):find('\n',1,true)then return s.headText end
 local text=s.headText or ''
 if s.action=='guard' then
  local phase=s.phase=='guard'and '防御中'or s.guardCounter and '反击预警'or '待机'
  text=text..' · '..phase
 end
 return '〔'..(s.breakable and '破招 'or '')..text..'〕'
end
local function draw_glyph(batch,texture,x,y,source,color)
 P.set_field_vec2(H.scratch_pos,H.scratch,x,y);P.set_field_raw(H.scratch_rect,H.rect_scratch,source);P.set_field_raw(H.scratch_color,H.scratch,color)
 assert(P.invoke(H.draw,batch,texture,H.posPointer,H.rectPointer,H.colorPointer)~=false,'ref glyph draw failed')
end
local function step(_,args)
 if disabled or not runtime.cfg.enabled then return end
 if not runtime.cfg.footEffects and not (runtime.cfg.ai and runtime.cfg.headText)then return end
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
 local performance=runtime.cfg.performance or 'standard'
 local maxTargets=performance=='quality'and 16 or performance=='minimal'and 1 or performance=='low'and 2 or 4
 local totalBudget=performance=='quality'and 40000 or 6000
 local variants=performance=='quality'and QualityFoot or FootVariants
 local shadow=performance~='minimal'

 local pixel=asset_texture(value(H.pixel,nil,'object'));if not pixel then return end
 H.pixel_w,H.pixel_h=value(H.tex_w,pixel,'int32'),value(H.tex_h,pixel,'int32')
 assert(finite(H.pixel_w) and finite(H.pixel_h) and H.pixel_w>0 and H.pixel_h>0,'MagicPixel尺寸无效')
 local sw=runtime:w('screenWidth','int32',1280);local sh=runtime:w('screenHeight','int32',720)
 local Foot=variants[performance=='quality'and 3 or (({small=1,standard=2,large=3})[runtime.cfg.effectSize] or 2)]
 if H.native and H.native.available then
  local ok,err=pcall(H.native.pump,H.native,performance=='quality'and 256 or performance=='standard'and 128 or 32)
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
     if runtime.cfg.ai and runtime.cfg.headText and s.headText and not s.aiFailed and not s.echoFailed then
      if H.native and H.native.available then
       local text=fullText(s)
       local ok,value=pcall(H.native.label,H.native,text)
       if ok then label=value else H.native.available=false;runtime.log('HEAD_NATIVE_DISABLED','atlas layout: '..tostring(value));label=layout(readable(s))end
      else label=layout(readable(s))end
     end
     local lx=x-sx-(label and label.width/2 or Foot[s.tier].width/2);local ly=ny-sy-32-(label and math.max(0,(label.height or 24)-24)or 0)
     if lx+(label and label.width or Foot[s.tier].width)>=0 and lx<sw and ny+nh-sy>=0 and ly<sh then
      targets[#targets+1]={s=s,label=label,x=math.floor(lx),y=math.floor(ly),fx=math.floor(x-sx-Foot[s.tier].anchorX),fy=math.floor(ny+nh-sy-Foot[s.tier].anchorY),cx=x-sx,ground=ny+nh-sy,wx=x,wy=ny+nh,d=(x-sx-sw/2)^2+(y-sy-sh/2)^2}
     end
    end
   end
  end
 end
 table.sort(targets,function(a,b)return a.d<b.d end)
 -- Two sprite-only decoys per visible caster, no NPC/entity creation.
 local ghostCount=0
 if runtime.cfg.visuals~=false and H.npcTextures and P.mem_read then
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
 local headBudget=performance=='quality'and (10000-ghostCount)or math.min(3000,(runtime.cfg.footEffects and H.brightness and 3000 or 6000)-ghostCount)
 local drawn,feet,compact,small=0,0,0,0;local used=ghostCount
 for i=1,math.min(maxTargets,#targets)do
  local t=targets[i];local label=t.label
  if label then
   if label.text then
    if H.native:render(batch,label,t.cx,t.y,t.s.breakable and string.char(255,100,220,255)or colors[t.s.tier],draw_glyph,shadow)then drawn=drawn+1;used=used+#label.glyphs*(shadow and 2 or 1) end
   else
   local amount=cost(label.runs,2)
   if amount>headBudget/(math.min(maxTargets,#targets)-i+1)then
    local text=(#(t.s.recipes or {})>1 and ((t.s.recipeIndex or 1)..'/'..#t.s.recipes..' ')or'')..(t.s.style and require('styles').names[t.s.style]..' 'or'')..(t.s.breakable and '破招 'or'')..(t.s.pattern or '单发')
    label=layout('〔'..text..'〕');amount=cost(label.runs,2)
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
 -- Unused text allowance is available to feet; the combined hard ceiling remains 6000.
 local footBudget=totalBudget-used
 if runtime.cfg.footEffects and performance~='minimal' and H.brightness then
  local sizeIndex=performance=='quality'and 3 or (({small=1,standard=2,large=3})[runtime.cfg.effectSize]or 2)
  for i=1,math.min(maxTargets,#targets)do
   local t=targets[i];local bright=P.invoke(H.brightness,math.floor(t.wx/16),math.floor(t.wy/16))
   if finite(bright)and bright>.04 then
    bright=math.min(1,math.max(0,bright));local art,amount,selected
    for size=sizeIndex,1,-1 do
     local candidate=variants[size][t.s.tier];local n=cost(candidate.runs,1,performance=='low'and 2 or nil)
     if n<=footBudget then art=candidate;amount=n;selected=size;break end
    end
    if art then
     footBudget=footBudget-amount;used=used+amount
     local fx=math.floor(t.cx-art.anchorX);local fy=math.floor(t.ground-art.anchorY)
     for runIndex,run in ipairs(art.runs)do
      if performance~='low'or runIndex%2==1 then
      local color=string.char(math.floor(run[4]*bright),math.floor(run[5]*bright),math.floor(run[6]*bright),math.floor(run[7]*bright))
      local xx=fx+run[1];local left=run[3]
      while left>0 do local width=math.min(left,H.pixel_w);draw_tex(batch,pixel,xx,fy+run[2],width,1,color);left=left-width;xx=xx+width end
      end
     end
     feet=feet+1;if selected<sizeIndex then small=small+1 end
     if not H.foot_confirmed then H.foot_confirmed=true;runtime.log('FOOT_DRAW','tier='..t.s.tier..' lighting=true route=ref_texture')end
    end
   end
  end
 end
 frames=frames+1
 if (drawn>0 or feet>0)and(not H.draw_completed or frames%300==1)then
  H.draw_completed=true;runtime.log('HEAD_DRAW','count='..drawn..' feet='..feet..' compact='..compact..' reduced='..small..' total_used='..used..' performance='..performance..' route='..(H.native and H.native.available and 'font_atlas'or 'bounded_fallback'))
 end

end
local function safe_step(instance,args)
    if disabled then return end
    local started
    if H.clock and H.frequency then local clockOK,value=pcall(P.invoke,H.clock);if clockOK then started=value else H.clock=nil end end
    local ok,e=xpcall(function() step(instance,args) end,function(e)
        return debug and debug.traceback and debug.traceback(tostring(e),2) or tostring(e)
    end)
    if type(started)=='number' and H.frequency then
     local clockOK,ended=pcall(P.invoke,H.clock);local elapsed=clockOK and type(ended)=='number'and(ended-started)*1000/H.frequency or 0;if not clockOK then H.clock=nil end
     H.samples=(H.samples or 0)+1;H.elapsed=(H.elapsed or 0)+elapsed;H.peak=math.max(H.peak or 0,elapsed)
     if H.samples>=300 then runtime.log('HEAD_PERF',('samples=%d avg_ms=%.3f max_ms=%.3f route=%s'):format(H.samples,H.elapsed/H.samples,H.peak,H.native and H.native.available and 'font_atlas'or'bounded_fallback'));H.samples=0;H.elapsed=0;H.peak=0 end
    end
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
        pcall(function()local clock=P.get_type('System.Diagnostics','Stopwatch');local method=clock and P.get_method(clock,'GetTimestamp',0);local frequency=clock and P.get_field(clock,'Frequency');local rate=frequency and P.get_field_value(frequency,nil,'int64');if method and type(rate)=='number'and rate>0 then H.clock=method;H.frequency=rate end end)
        runtime.log('HEAD_PERF_ROUTE','available='..tostring(H.clock~=nil))
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
