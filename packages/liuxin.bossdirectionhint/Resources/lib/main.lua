-- Boss方向提示 v3.0 / Terraria Android 1.4.5.8 + LuaLoader 1.5.0+（兼容1.6.0）
-- 仅调用 ref 参数绘制重载，不调用 DrawBuffIcon、不写玩家 buff、不激活 CombatText。
-- 按完整参数类型选择 ref Draw；不绑定版本相关的元数据 Token。
mod.meta = {pkg_id='liuxin.bossdirectionhint', version='3.0', version_code=34}
local P = mod.patch
local H, hooks = {}, {}
local disabled, failures, frames, announced = false, 0, 0, false
local target, previous_target
local RADIUS, MAX_BUFFS = 160, 4
local distance_pointer_enabled = true
local pointer_style=1
local refresh_pointer
local POINTER_FILES={'pointer.png','pointers/leaf.png','pointers/squid.png','pointers/block.png','pointers/purple.png','pointers/chevrons.png'}
local function log(s)
    mod.info('[Boss方向提示 v3.0] '..s)
    if type(mod.write_file)=='function' then
        H.log = (H.log or '') .. s .. '\n'
        if #H.log>16000 then H.log=H.log:sub(-12000) end
        pcall(mod.write_file,'bossdirection_runtime.log',H.log)
    end
end
local function finite(n)
    return type(n)=='number' and n==n and math.abs(n)<1e8
end
-- TEFManager将设置保存到模组private_dir/config.json；加载器read_file读取此目录。
local function refresh_config()
    if type(mod.read_file)~='function' then return end
    local ok,raw=pcall(mod.read_file,'config.json')
    if not ok or type(raw)~='string' then return end
    -- 只读取本模组的布尔及整数设置，不执行配置内容。
    local literal=raw:match('"distance_pointer_enabled"%s*:%s*([%a]+)')
    local enabled
    if literal=='true' then enabled=true elseif literal=='false' then enabled=false end
    if enabled~=nil and enabled~=distance_pointer_enabled then
        distance_pointer_enabled=enabled
        log('距离指针设置：'..(enabled and '开启' or '关闭'))
    end
    local selected=tonumber(raw:match('"pointer_style"%s*:%s*([%-]?[%d%.]+)'))
    if selected and selected%1==0 and POINTER_FILES[selected] and selected~=pointer_style then
        pointer_style=selected
        log('指针样式设置：'..selected)
        if refresh_pointer then refresh_pointer() end
    end
end
local function pointer_radius(distance)
    if not distance_pointer_enabled then return RADIUS end
    if not finite(distance) or distance<0 then return RADIUS end
    -- 0至60格（960像素）映射到48至160像素，贴近时保留角色周围空间。
    return 48+(RADIUS-48)*math.min(distance/960,1)
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
local function reset()
    frames, announced, target, previous_target = 0, false, nil, nil
end
local function center(obj,fields)
    local x,y=P.get_field_vec2(fields.pos,obj)
    local w,h=value(fields.w,obj,'int32'),value(fields.h,obj,'int32')
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    return x+w/2,y+h/2,x,y,w,h
end
local function pick_boss(arr,px,py)
    local best,dist=nil,math.huge
    for i=0,199 do
        local n=P.array_at(arr,i)
        if n and value(H.n.active,n,'bool')==true and value(H.n.life,n,'int32')>0
           and value(H.n.friendly,n,'bool')~=true then
            local boss=value(H.n.boss,n,'bool')==true
            -- 世吞头/体/尾在各版本的 boss 标记不一致；不把任意 realLife NPC 当 Boss。
            local nt=value(H.n.kind,n,'int32')
            if nt==13 or nt==14 or nt==15 then boss=true end
            if boss then
                local x,y=center(n,H.n)
                if x then
                    local d=(x-px)^2+(y-py)^2
                    if d<dist then best,dist=i,d end
                end
            end
        end
    end
    return best
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
        P.field_pointer(H.scratch_pos,H.scratch),
        P.field_pointer(H.scratch_rect,H.rect_scratch),
        P.field_pointer(H.scratch_color,H.scratch))
    if result==false then error('ref Draw 调用失败') end
    return true
end
-- 此手机版Color内存布局由上传源码确认：A B G R。
local WHITE=string.char(255,255,255,255)
local DARK=string.char(255,15,15,15)
local URGENT=string.char(255,60,140,255)
-- 图片独立保存为main.lua旁的pointer.png，尖端朝右、背景透明。
local PNG=require('pointer_png')
local pointer_image
-- 文件损坏或缺失时的简单后备箭头，避免中断Boss/Buff显示。
do
    local pixels={}
    for y=0,23 do for x=0,31 do
        local visible=(x>=8 and math.abs(y-11.5)<=(31-x)*0.5) or (x<12 and math.abs(y-11.5)<3)
        pixels[#pixels+1]=visible and {255,216,83,255} or {0,0,0,0}
    end end
    pointer_image={width=32,height=24,pixels=pixels}
end
local pointer_cache,pointer_order={},{}
local previous_png,failed_png,previous_path,failed_path
refresh_pointer=function()
    local path=(mod.mod_dir or '.')..'/'..POINTER_FILES[pointer_style]
    local ok,data=pcall(function()
        local f=io.open(path,'rb');if not f then return nil end
        local bytes=f:read(2097153);f:close();return bytes
    end)
    if not ok or not data then
        if failed_png~='missing' or failed_path~=path then failed_png='missing';failed_path=path;log('未能读取指针图片，保留当前指针：'..POINTER_FILES[pointer_style]) end
        return
    end
    if (path==previous_path and data==previous_png) or (path==failed_path and data==failed_png) then return end
    local decoded,img=pcall(PNG.decode,data)
    if not decoded then
        failed_png=data;failed_path=path;log('指针图片读取失败，保留当前指针：'..tostring(img));return
    end
    pointer_image=img;previous_png=data;previous_path=path;failed_png=nil;failed_path=nil
    pointer_cache,pointer_order={},{}
    log(POINTER_FILES[pointer_style]..'已加载 '..img.width..'x'..img.height)
end
local ZERO={0,0,0,0}
local function pixel_at(x,y)
    local im=pointer_image
    if x<0 or y<0 or x>=im.width or y>=im.height then return ZERO end
    return im.pixels[y*im.width+x+1]
end
local function pointer_pixels(angle,size)
    -- 指针图标保持正立，只根据 Boss 在玩家左侧/右侧做水平镜像。
    -- 旧版按角度逐帧旋转整张图片，会让人物/图案在上下方向倒转。
    size=math.max(0.5,math.min(1,size or 1))
    local size_key=math.floor(size*64+0.5)
    local mirror=math.cos(angle)<0
    local key=(mirror and 100000 or 0)+size_key
    if pointer_cache[key] then return pointer_cache[key] end
    local cells={};local im=pointer_image
    -- 大图自动缩小到60像素；小图保留原尺寸。
    local scale=math.min(1,60/math.max(im.width,im.height))*(size_key/64)
    local bound=math.ceil(math.sqrt(im.width^2+im.height^2)*scale/2)+1
    for y=-bound,bound do
        for x=-bound,bound do
            local sx=(im.width-1)/2+(mirror and -x or x)/scale
            local sy=(im.height-1)/2+y/scale
            local ix,iy=math.floor(sx),math.floor(sy)
            local fx,fy=sx-ix,sy-iy
            local p,q,r,t=pixel_at(ix,iy),pixel_at(ix+1,iy),pixel_at(ix,iy+1),pixel_at(ix+1,iy+1)
            local w1,w2,w3,w4=(1-fx)*(1-fy),fx*(1-fy),(1-fx)*fy,fx*fy
            local aa=math.floor(p[4]*w1+q[4]*w2+r[4]*w3+t[4]*w4+0.5)
            if aa>3 then
                local function channel(i) return math.min(aa,math.max(0,math.floor(p[i]*w1+q[i]*w2+r[i]*w3+t[i]*w4+0.5))) end
                cells[#cells+1]={x=x,y=y,color=string.char(aa,channel(3),channel(2),channel(1))}
            end
        end
    end
    if #pointer_order>=64 then pointer_cache[table.remove(pointer_order,1)]=nil end
    pointer_order[#pointer_order+1]=key;pointer_cache[key]=cells
    return cells
end

local function block(batch,pixel,x,y,color)
    local w,h=H.pixel_w,H.pixel_h
    w,h=math.min(2,w),math.min(2,h)
    -- 1x1贴图时平铺补齐2x2，所有源矩形都在真实贴图范围内。
    for dy=0,2-h,h do
        for dx=0,2-w,w do draw_tex(batch,pixel,x+dx,y+dy,w,h,color) end
    end
end
local function ring(batch,pixel,cx,cy,angle,distance)
    local ux,uy=math.cos(angle),math.sin(angle)
    local radius=pointer_radius(distance)
    local x,y=math.floor(cx+ux*radius+0.5),math.floor(cy+uy*radius+0.5)
    -- 与收拢半径同步：最近半尺寸，最远完整尺寸；关闭距离变化时保持原大小。
    local size=0.5+0.5*math.max(0,math.min(1,(radius-48)/(RADIUS-48)))
    for _,cell in ipairs(pointer_pixels(angle,size)) do
        draw_tex(batch,pixel,x+cell.x,y+cell.y,1,1,cell.color)
    end
end
-- 用同一个已在真机生效的ref贴图通道绘制秒数，不调用按值DrawString。
local DIGITS={
 ['0']={'111','101','101','101','111'}, ['1']={'010','110','010','010','111'},
 ['2']={'111','001','111','100','111'}, ['3']={'111','001','111','001','111'},
 ['4']={'101','101','111','001','001'}, ['5']={'111','100','111','001','111'},
 ['6']={'111','100','111','101','111'}, ['7']={'111','001','010','010','010'},
 ['8']={'111','101','111','101','111'}, ['9']={'111','101','111','001','111'},
 ['s']={'011','100','010','001','110'},
}
local function timer(batch,pixel,cx,y,seconds)
    local text=tostring(seconds)..'s'
    local x0=cx-(#text*8-2)/2
    local color=seconds<=5 and URGENT or WHITE
    for i=1,#text do
        local rows=DIGITS[text:sub(i,i)]
        if rows then
            for row=1,5 do
                for col=1,3 do
                    if rows[row]:sub(col,col)=='1' then
                        local x=x0+(i-1)*8+(col-1)*2
                        local yy=y+(row-1)*2
                        block(batch,pixel,x+1,yy+1,DARK)
                        block(batch,pixel,x,yy,color)
                    end
                end
            end
        end
    end
end
local function debuffs(npc)
    local result={}
    local types=value(H.n.buff,npc,'object')
    local times=value(H.n.time,npc,'object')
    local flags=value(H.debuff,nil,'object')
    if not (types and times and flags) then return result end
    local n=P.array_length(types)
    if not finite(n) or n<=0 then n=20 end -- 此手机版 NPC 的20格；不探测越界元素
    n=math.min(n,20)
    for i=0,n-1 do
        local id=P.array_at(types,i,'int32')
        local time=P.array_at(times,i,'int32')
        if finite(id) and id>0 and id<H.buff_limit and finite(time) and time>0
           and P.array_at(flags,id,'bool')==true then
            result[#result+1]={id=id,seconds=math.ceil(time/60)}
            if #result==MAX_BUFFS then break end
        end
    end
    return result
end
local function step(_,args)
    if disabled then return end
    if args and args[1]==true then return end -- 只在前景 NPC 绘制完成后画一次
    local user=value(H.active_user,nil,'object') or value(H.primary_user,nil,'object')
    local state=user and value(H.user_state,user,'object')
    if not state then
        if not H.state_warning then H.state_warning=true;log('等待本地用户GameState') end
        return
    end
    if value(H.menu,state,'bool')==true then reset(); return end
    local players=value(H.players,nil,'object')
    local idx=value(H.my_player,state,'int32')
    if not players or not finite(idx) or idx<0 or idx>254 then return end
    local player=P.array_at(players,idx)
    if not player or value(H.p.active,player,'bool')~=true then return end
    local px,py=center(player,H.p)
    if not px then return end
    local sx,sy=P.get_field_vec2(H.camera,state)
    if not (finite(sx) and finite(sy)) then return end
    frames=frames+1
    if frames%120==1 then refresh_config() end
    if frames%300==1 then refresh_pointer() end
    if not announced and frames>=30 then
        local s=P.string_create('boss指针已运行')
        if H.chat and s and P.invoke(H.chat,s,255,210,70,false)~=false then
            announced=true; log('进入世界，聊天提示已发送')
        end
    end
    local batch=value(H.batch,nil,'object')
    if not batch or value(H.begun,batch,'bool')~=true then
        if not H.batch_warning then H.batch_warning=true;log('等待有效 SpriteBatch.Begin') end
        return
    end
    local npcs=value(H.npcs,nil,'object')
    if not npcs then return end
    if frames%10==1 then target=pick_boss(npcs,px,py) end
    if target==nil then
        if previous_target then log('Boss消失，停止绘制');previous_target=nil end
        return
    end
    local npc=P.array_at(npcs,target)
    if not npc or value(H.n.active,npc,'bool')~=true or value(H.n.life,npc,'int32')<=0 then
        target=nil;return
    end
    local bx,by,nx,ny,nw,nh=center(npc,H.n)
    if not bx then target=nil;return end
    -- 原生指针不能作为跨帧保活引用；先通过GCHandle取出仍存活的对象。
    H.scratch=P.invoke(H.gc_target,H.scratch_root)
    H.rect_scratch=P.invoke(H.gc_target,H.rect_root)
    assert(H.scratch and H.rect_scratch,'绘制缓冲GCHandle失效')
    local pixel=asset_texture(value(H.pixel,nil,'object'))
    if not pixel then return end
    H.pixel_w,H.pixel_h=value(H.tex_w,pixel,'int32'),value(H.tex_h,pixel,'int32')
    assert(finite(H.pixel_w) and finite(H.pixel_h) and H.pixel_w>0 and H.pixel_h>0,'MagicPixel尺寸无效')
    if not H.draw_started then
        H.draw_started=true
        log('开始首轮指针绘制；缓冲GC保活已确认')
    end
    ring(batch,pixel,px-sx,py-sy,math.atan(by-py,bx-px),math.sqrt((bx-px)^2+(by-py)^2))
    if previous_target~=target then
        previous_target=target;log('锁定Boss槽位 '..target..'，指针绘制已执行')
    end
    local ids=debuffs(npc)
    if H.last_buff_count~=#ids then H.last_buff_count=#ids;log('Boss负面Buff数量 '..#ids) end
    local textures=value(H.buff_textures,nil,'object')
    if not textures then return end
    local top=ny
    local raw=P.get_field_raw(H.n.frame,npc,16)
    local _,_,_,fh=string.unpack('<i4i4i4i4',raw)
    local scale=value(H.n.scale,npc,'float')
    if finite(fh) and fh>0 and fh<4096 and finite(scale) and scale>0 and scale<20 then
        top=math.min(top,ny+nh-fh*scale,by-fh*scale/2)
    end
    for i,buff in ipairs(ids) do
        local id=buff.id
        if H.load_buff then P.invoke(H.load_buff,id) end
        local texture=asset_texture(P.array_at(textures,id))
        if texture then
            local w,h=value(H.tex_w,texture,'int32'),value(H.tex_h,texture,'int32')
            if finite(w) and finite(h) and w>0 and h>0 and w<=256 and h<=256 then
                local icon_x=bx-sx-(#ids-1)*24-w/2+(i-1)*48
                local icon_y=top-sy-h-32
                draw_tex(batch,texture,icon_x,icon_y,w,h,WHITE)
                timer(batch,pixel,icon_x+w/2,icon_y+h+4,buff.seconds)
            end
        elseif not H.missing_icons[id] then
            H.missing_icons[id]=true;log('Buff贴图未就绪 ID='..id)
        end
    end
    if not H.draw_completed then H.draw_completed=true;log('首轮指针及Buff处理结束') end
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
function setup()
    refresh_pointer()
    refresh_config()
    log('初始化 v3.0；需要 Android Terraria 1.4.5.8 / LuaLoader 1.5.0+（兼容1.6.0）')
    if type(P.get_method_by_param_types)~='function'
       or type(P.make_generic_type)~='function' or type(P.field_pointer)~='function' then
        log('加载器缺少绘制接口，请升级到 LuaLoader 1.5.0+（兼容1.6.0）；未挂载游戏钩子')
        return
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
        H.begun=field(sb,'_beginCalled');H.debuff=field(main,'debuff')
        H.pixel=field(assets,'MagicPixel');H.buff_textures=field(assets,'Buff')
        H.buff_limit=401 -- 上传的 Terraria 1.4.5.8 BuffID.Count
        H.missing_icons={}
        H.chat=P.get_method(main,'NewText',5)
        H.load_buff=P.get_method(main,'LoadBuff',1) -- 某些版本在资源加载时已初始化全部Buff
        local function entity(t)
            return {pos=field(t,'position'),w=field(t,'width'),h=field(t,'height'),active=field(t,'active')}
        end
        H.p=entity(pt);H.n=entity(nt)
        for key,name in pairs({life='life',friendly='friendly',boss='boss',kind='type',
            buff='buffType',time='buffTime',frame='frame',scale='scale'}) do H.n[key]=field(nt,name) end
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
        assert(P.field_pointer(H.scratch_pos,H.scratch),'仅支持Android字段指针')
        log('两个绘制缓冲已注册GC强引用')
        local method=P.get_method(main,'DrawNPCs',1)
        assert(method,'缺少 Main.DrawNPCs')
        local h=P.install_hook(method,{postfix=safe_step})
        assert(h,'钩子安装失败');hooks[#hooks+1]=h
        log('初始化成功：ref贴图绘制、真实相机、独立缓冲；没有战斗文字槽位写入')
    end)
    if not ok then disabled=true;release_roots();log('初始化失败: '..tostring(e)) end
end
function cleanup()
    disabled=true
    for _,h in ipairs(hooks) do pcall(function() h:remove() end) end
    hooks={};release_roots();log('已卸载，GC强引用已释放')
end
todo_list={'setup'}
