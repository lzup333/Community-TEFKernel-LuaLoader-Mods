mod.meta = { pkg_id = 'terraria.lua.mapteleport', version = '1.0.1' }
local diag = require('diagnostics')
local p, core = mod.patch, require('map_core')
local taps = core.new()
local h, active, last_frame, pending, map_instance = {}, nil, -1, nil, nil

local function type_(ns, name)
    local t = p.get_type(ns, name)
    if not t then error('missing type '..ns..'.'..name) end
    return t
end
local function field(t, name)
    while t do
        local f = p.get_field(t, name)
        if f then return f end
        t = p.get_parent(t)
    end
    error('missing field '..name)
end
local function method(t, name, n)
    local m = p.get_method(t, name, n)
    if not m then error('missing method '..name) end
    return m
end
local function get(f, obj, ty) return p.get_field_value(f, obj, ty) end
local function call(m, ...) return p.invoke(m, ...) end
local function rect(ctx)
    local has = p.mem_read_values(ctx,16,1,'uint8')[1]
    if has == 0 then return nil end
    local v = p.mem_read_values(ctx,20,4,'int32')
    if not v or v[3]<=0 or v[4]<=0 then return nil end
    return {x=v[1],y=v[2],w=v[3],h=v[4]}
end
local function projection(ctx)
    local v=p.mem_read_values(ctx,0,4,'float')
    local scale=p.mem_read_values(ctx,36,1,'float')[1]
    if not scale or scale~=scale or scale<0.01 or scale>100 then return end
    for i=1,4 do if not v[i] or v[i]~=v[i] or math.abs(v[i])>1e7 then return end end
    return {mx=v[1],my=v[2],ox=v[3],oy=v[4],scale=scale}
end
local function cursor_xy(c)
    local x,y=p.get_field_vec2(h.cursor_pos,c)
    local runner=get(h.runner_instance,nil,'object')
    if not runner then return end
    local cam=get(h.ui_camera,runner,'object')
    if not cam then return end
    local sw,sh=call(h.screen_width),call(h.screen_height)
    local vw,vh=get(h.vw,cam,'int32'),get(h.vh,cam,'int32')
    if not sw or not sh or sw<=0 or sh<=0 or not vw or not vh or vw<=0 or vh<=0 then return end
    local ox,oy=get(h.vx,cam,'int32'),get(h.vy,cam,'int32')
    return math.floor(x*vw/sw)+ox, math.floor((sh-y)*vh/sh)+oy, vw, vh
end
local function reset_touch() active=nil; taps:clear() end
local function poll_map(ctx)
    if not ctx or not map_instance then diag.changed('地图回调异常','上下文或地图对象为空'); return end
    if call(h.game_menu) or get(h.net_mode,nil,'int32')~=0 then diag.changed('地图状态','菜单或联机，已暂停'); reset_touch(); return end
    local fullscreen=call(h.fullscreen)
    local clip=rect(ctx)
    local frame=get(h.frame,nil,'int32')
    diag.sample('地图上下文', '全屏='..tostring(fullscreen)..' 裁剪='..tostring(clip~=nil),frame,120)
    if (fullscreen and clip) or (not fullscreen and not clip) then diag.sample('地图不匹配','全屏状态与地图范围不匹配',frame,120); return end
    diag.changed('地图匹配','通过')
    if frame==last_frame then return end
    last_frame=frame
    local camera=projection(ctx)
    local manager=get(h.cursor_manager,nil,'object')
    if not camera or not manager then diag.changed('地图数据','坐标参数或触摸管理器不可用'); reset_touch(); return end
    diag.sample('地图数据',string.format('位置=%.2f,%.2f 偏移=%.2f,%.2f 缩放=%.3f',camera.mx,camera.my,camera.ox,camera.oy,camera.scale),frame,120)
    local count=call(h.cursor_count,manager)
    diag.changed('触点数量',count)
    if not count or count>1 then reset_touch(); return end
    if count==0 then active=nil; return end
    local c=call(h.cursor_at,manager,0)
    if not c then reset_touch(); return end
    local x,y,vw,vh=cursor_xy(c)
    if not x or not y then diag.changed('触摸坐标','无法转换'); reset_touch(); return end
    local down=get(h.cursor_down,c,'bool')
    local was=get(h.cursor_was,c,'bool')
    local id=get(h.cursor_id,c,'int32')
    local kind=fullscreen and 'full' or 'mini'
    local within = fullscreen and x>=0 and y>=0 and x<vw and y<vh or
                   (not fullscreen and core.inside(clip,x,y))
    if fullscreen and within and call(h.map_controls,map_instance,c) then within=false end
    local radius=math.max(18, math.min(vw,vh)*0.035)
    if down~=was then diag.log('触摸变化',string.format('地图=%s 帧=%d 按下=%s 上帧=%s 坐标=%.1f,%.1f 范围内=%s id=%s',kind,frame,tostring(down),tostring(was),x,y,tostring(within),tostring(id))) end
    if down and not was then
        if within then diag.log('点击开始',kind); active={id=id,x=x,y=y,frame=frame,kind=kind,drag=false}
        else active=nil; taps:clear() end
    elseif active and active.id==id and active.kind==kind then
        if (x-active.x)^2+(y-active.y)^2>radius*radius then active.drag=true end
        if not down and was then
            local a=active; active=nil
            if within and not a.drag and frame>=a.frame and frame-a.frame<=24 then
                local double=taps:tap(frame,x,y,kind,radius)
                diag.log('点击结束','双击='..tostring(double)..' 地图='..kind)
                if double then
                    local tx,ty=core.to_world(camera,x,y)
                    local maxx,maxy=get(h.max_x,nil,'int32'),get(h.max_y,nil,'int32')
                    if tx==tx and ty==ty and maxx and maxy and tx>=2 and ty>=2 and tx<maxx-2 and ty<maxy-2 then
                        pending={x=tx*16,y=ty*16}
                        diag.log('传送已排队',string.format('地图格=%.2f,%.2f 世界像素=%.1f,%.1f',tx,ty,pending.x,pending.y))
                    else diag.log('传送拒绝','目标超出世界范围或坐标无效') end
                end
            else diag.log('点击取消','超时、拖动或离开地图范围'); taps:clear() end
        end
    elseif not down then active=nil end
end
local function teleport(player)
    if not pending then return end
    diag.changed('传送处理','等待本地玩家更新')
    if call(h.game_menu) or get(h.net_mode,nil,'int32')~=0 then pending=nil; return end
    if get(h.who,player,'int32')~=call(h.my_player) then return end
    if get(h.dead,player,'bool') then diag.log('传送取消','玩家死亡'); pending=nil; return end
    local dest=pending; pending=nil
    local width=get(h.width,player,'int32')
    local height=get(h.height,player,'int32')
    if not width or not height or width<=0 or height<=0 then return end
    local result=p.invoke_value_args(h.teleport,player,{p.struct_arg({'float','float'},{dest.x-width/2,dest.y-height/2}),0,0})
    diag.log('传送调用','返回='..tostring(result)..' 目标='..dest.x..','..dest.y)
    p.set_field_vec2(h.velocity,player,0,0)
end
local function initialize()
    diag.log('初始化','开始解析接口')
    local main=type_('Terraria','Main')
    local player=type_('Terraria','Player')
    local map=type_('','GUIMap')
    local layer=type_('Terraria.Map','PingMapLayer')
    local cursor=type_('','Cursor')
    local cm=type_('','CursorManager')
    local runner=type_('','XNAUnityRunner')
    local camera=type_('','XNAUICameraSettings')
    local screen=type_('UnityEngine','Screen')
    h.game_menu=method(main,'get_gameMenu',0); h.fullscreen=method(main,'get_mapFullscreen',0)
    h.my_player=method(main,'get_myPlayer',0); h.net_mode=field(main,'netMode')
    h.max_x=field(main,'maxTilesX'); h.max_y=field(main,'maxTilesY')
    h.frame=field(runner,'_frame'); h.runner_instance=field(runner,'_instance')
    h.ui_camera=field(runner,'UICameraSettings')
    h.vw=field(camera,'realVirtualScreenWidth'); h.vh=field(camera,'realVirtualScreenHeight')
    h.vx=field(camera,'realVirtualScreenOffsetX'); h.vy=field(camera,'realVirtualScreenOffsetY')
    h.screen_width=method(screen,'get_width',0); h.screen_height=method(screen,'get_height',0)
    h.cursor_manager=field(cm,'Instance'); h.cursor_count=method(cm,'GetNumCursors',0)
    h.cursor_at=method(cm,'GetCursor',1); h.cursor_pos=field(cursor,'Position')
    h.cursor_down=field(cursor,'Down'); h.cursor_was=field(cursor,'WasDown'); h.cursor_id=field(cursor,'Id')
    h.map_controls=method(map,'IsCursorOverFullScreenMapControls',1)
    h.who=field(player,'whoAmI'); h.dead=field(player,'dead')
    h.width=field(player,'width'); h.height=field(player,'height'); h.velocity=field(player,'velocity')
    h.teleport=method(player,'Teleport',3)
    diag.log('初始化','接口解析完成，安装地图钩子')
    h.map_hook=p.install_hook(method(map,'DrawMap',0),{
        prefix=function(instance) map_instance=instance; diag.changed('地图绘制','已触发') end,
        postfix=function() map_instance=nil end
    })
    diag.log('初始化','地图绘制钩子安装成功')
    h.layer_hook=p.install_hook(method(layer,'Draw',2),{
        prefix=function(_,args) diag.changed('地图图层','已触发'); diag.guard('地图输入',poll_map,args and args[1]) end
    })
    diag.log('初始化','地图图层钩子安装成功')
    h.player_hook=p.install_hook(method(player,'ResetEffects',0),{postfix=function(player) diag.guard('玩家传送',teleport,player) end})
    diag.log('初始化','玩家钩子安装成功')
    mod.info('双击地图传送已加载（单人模式）')
end
function setup()
    local ok,err=xpcall(initialize,debug.traceback)
    if not ok then
        diag.log('初始化失败',err)
        mod.error('[地图传送诊断] 初始化失败: '..tostring(err))
        for _,key in ipairs({'player_hook','layer_hook','map_hook'}) do
            local hook=h[key]
            if hook then pcall(function() hook:remove() end); h[key]=nil end
        end
    end
end
todo_list={'setup'}
