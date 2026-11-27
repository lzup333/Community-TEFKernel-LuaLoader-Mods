-- The only module touching the loader's patch API. No game addresses or offsets.
local M={}
local Policy=require('tile_policy')
local function need(v,label) assert(v~=nil and v~=false,'缺少接口：'..label);return v end
local function integer(v,label) assert(type(v)=='number' and v%1==0,'读取失败：'..label);return v end
function M.new(p)
 local ok,result=pcall(function()
  for _,k in ipairs{'get_type','get_basic_type','get_method_by_signature','method_is_static','get_field','field_is_static','field_size','invoke','get_field_value','get_field_vec2','field_pointer','ptr_deref','install_hook','array_at'} do need(p[k],k) end
  local function typ(ns,n) return need(p.get_type(ns,n),ns..'.'..n) end
  local function method(t,n,types,names,static)
   local args={};for i,v in ipairs(types) do args[i]=type(v)=='string' and need(p.get_basic_type(v),v) or v end
   local m=need(p.get_method_by_signature(t,n,args,names),n)
   assert(p.method_is_static(m)==static,'方法静态属性不匹配：'..n);return m
  end
  local function field(t,n,static,size)
   local f=need(p.get_field(t,n),n);assert(p.field_is_static(f)==static,'字段属性不匹配：'..n)
   if size then
    -- The matching loader returns zero when the kernel omits its optional size export.
    -- Exact field names/layouts come from the supplied 1.4.5.8 source; reject a known mismatch.
    local actual=p.field_size(f)
    assert(actual==0 or actual==size,'字段大小不匹配：'..n)
   end
   return f
  end
  local Main=typ('Terraria','Main');local Player=typ('Terraria','Player');local Entity=typ('Terraria','Entity')
  local WG=typ('Terraria','WorldGen');local TD=typ('Terraria','TileData')

  local a={p=p,m={},f={},properties={},shape={}}
  for _,n in ipairs{'worldID','myPlayer','spawnTileX','spawnTileY','gameMenu'} do a.properties[n]=method(Main,'get_'..n,{},nil,true) end
  for _,n in ipairs{'maxTilesX','maxTilesY','netMode'} do a.f[n]=field(Main,n,true,4) end
  a.f.worldName=field(Main,'worldName',true);a.f.player=field(Main,'player',true)
  a.f.tileFrameImportant=field(Main,'tileFrameImportant',true)
  a.f.tileContainer=field(Main,'tileContainer',true)
  a.f.tileSign=field(Main,'tileSign',true)
  a.f.tileSolid=field(Main,'tileSolid',true)
  a.f.active=field(Player,'active',false,1);a.f.dead=field(Player,'dead',false,1)
  a.f.position=field(Entity,'position',false,8);a.f.width=field(Entity,'width',false,4);a.f.height=field(Entity,'height',false,4)
  a.f.lookup=field(TD,'TileLookup',true)
  a.m.tile=method(WG,'PlaceTile',{'int32','int32','int32','bool','bool','int32','int32'},{'i','j','Type','mute','forced','plr','style'},true)
  a.m.object=method(WG,'PlaceObject',{'int32','int32','int32','bool','int32','int32','int32','int32'},
   {'x','y','type','mute','style','alternate','random','direction'},true)
  a.m.wall=method(WG,'PlaceWall',{'int32','int32','int32','bool'},{'i','j','type','mute'},true)
  a.m.chest=method(WG,'PlaceChest',{'int32','int32','uint16','bool','int32'},{'x','y','type','notNearOtherChests','style'},true)
  a.m.kill=method(WG,'KillTile',{'int32','int32','bool','bool','bool'},{'i','j','fail','effectOnly','noItem'},true)
  a.m.squareWall=method(WG,'SquareWallFrame',{'int32','int32','bool'},{'i','j','resetFrame'},true)
  a.m.frame=method(WG,'SquareTileFrame',{'int32','int32','bool'},{'i','j','resetFrame'},true)
  a.m.update=method(Main,'Update',{typ('Microsoft.Xna.Framework','GameTime')},{'gameTime'},false)
  for _,n in ipairs{'GetType','GetWall','GetLiquid','GetSHeader'} do a.m[n]=method(TD,n,{'int32'},{'tileIndex'},true) end
  a.m.setLiquid=method(TD,'SetLiquid',{'int32','uint8'},{'tileIndex','liquid'},true)
  a.m.setWall=method(TD,'SetWall',{'int32','uint16'},{'tileIndex','wall'},true)
  a.m.setType=method(TD,'SetType',{'int32','uint16'},{'tileIndex','newType'},true)
  a.m.setHeader=method(TD,'SetSHeader',{'int32','int16'},{'tileIndex','sHeader'},true)
  a.m.setFrameXY=method(TD,'SetFrameXY',{'int32','int16','int16'},{'tileIndex','frameX','frameY'},true)
  a.m.setFramed=method(TD,'SetTileFramed',{'int32','bool'},{'tileIndex','framed'},true)
  for _,entry in ipairs{{'SetBHeader','bHeader'},{'SetBHeader2','bHeader2'},{'SetBHeader3','bHeader3'}} do
   a.m[entry[1]]=method(TD,entry[1],{'int32','uint8'},{'tileIndex',entry[2]},true)
  end
  function a:get(n)
   if self.properties[n] then return p.invoke(self.properties[n]) end
   return p.get_field_value(self.f[n],nil,n=='worldName' and 'string' or 'int32')
  end
  function a:snapshot()
   local menu=self:get('gameMenu');assert(type(menu)=='boolean','无法读取菜单状态')
   if menu then return {menu=true} end
   local sx=integer(self:get('maxTilesX'),'世界宽度');local sy=integer(self:get('maxTilesY'),'世界高度')
   assert(sx>100 and sy>100,'世界未就绪')
   local lookup=need(p.ptr_deref(p.field_pointer(self.f.lookup,nil),0),'TileLookup')
   local snap={menu=false,multiplayer=integer(self:get('netMode'),'netMode')~=0,maxX=sx,maxY=sy,
    worldKey=tostring(self:get('worldID'))..':'..tostring(self:get('worldName'))..':'..tostring(lookup),
    spawn={x=integer(self:get('spawnTileX'),'出生点X'),y=integer(self:get('spawnTileY'),'出生点Y')}}
   if snap.multiplayer then return snap end
   local arr=need(p.get_field_value(self.f.player,nil,'object'),'玩家数组')
   self.solidTiles=need(p.get_field_value(self.f.tileSolid,nil,'object'),'实心方块标记')
   self.specialTileFlags={
    need(p.get_field_value(self.f.tileFrameImportant,nil,'object'),'特殊方块标记'),
    need(p.get_field_value(self.f.tileContainer,nil,'object'),'容器标记'),
    need(p.get_field_value(self.f.tileSign,nil,'object'),'告示牌标记')
   }
   local me=need(p.array_at(arr,integer(self:get('myPlayer'),'玩家编号')),'玩家')
   snap.dead=p.get_field_value(self.f.dead,me,'bool') or not p.get_field_value(self.f.active,me,'bool')
   local px,py=p.get_field_vec2(self.f.position,me)
   local w=integer(p.get_field_value(self.f.width,me,'int32'),'玩家宽度');local h=integer(p.get_field_value(self.f.height,me,'int32'),'玩家高度')
   assert(type(px)=='number' and type(py)=='number','玩家位置不可读')
   snap.playerFeet={x=math.floor((px+w/2)/16),y=math.floor((py+h+0.01)/16)}
   snap.playerBox={x1=math.floor(px/16),x2=math.floor((px+w-0.01)/16),y1=math.floor(py/16),y2=math.floor((py+h-0.01)/16)}
   self.current=snap;return snap
  end
  function a:read(x,y)
   local s=need(self.current,'世界快照');assert(x>=0 and y>=0 and x<s.maxX and y<s.maxY,'坐标越界')
   -- TileData getters accept the coordinate offset, and resolve TileLookup themselves.
   -- Verified in the supplied ARM64 get_Item/GetType/Tile flag getter instructions.
   local index=y*s.maxX+x
   local header=integer(p.invoke(self.m.GetSHeader,index),'方块状态') & 0xffff
   local active=(header & 0x20)~=0
   local inactive=(header & 0x40)~=0
   local wires=(header & 0x8b80)~=0 -- wires 1..4 and actuator
   local ty=integer(p.invoke(self.m.GetType,index),'方块类型')
   local special=false;local flagsByKind={}
   for i,flags in ipairs(self.specialTileFlags or {}) do
    local marked=p.array_at(flags,ty,'bool')
    assert(type(marked)=='boolean','特殊方块标记不可读')
    flagsByKind[i]=marked;special=special or marked
   end
   local solid=p.array_at(self.solidTiles,ty,'bool')
   assert(type(solid)=='boolean','实心方块标记不可读')
   local slope=(header >> 12) & 7
   return {active=active,type=ty,wall=integer(p.invoke(self.m.GetWall,index),'墙体'),liquid=integer(p.invoke(self.m.GetLiquid,index),'液体'),
    header=header,frameImportant=flagsByKind[1],container=flagsByKind[2],sign=flagsByKind[3],
    wires=wires,protected=inactive,special=active and special and not Policy.tree(ty),solid=active and not inactive and solid,uneven=slope~=0 or (header & 0x400)~=0}
  end
  function a:objectShape(o)
   local v=Policy.origin(o.tile)
   assert(v and o.w==v[3] and o.h==v[4] and o.style==0,'内置家具类型或尺寸不支持：'..tostring(o.kind))
   return {x=v[1],y=v[2]}
  end
  function a:removeWall(x,y)
   local index=y*self.current.maxX+x
   assert(p.invoke(self.m.setWall,index,0)~=false,'清理墙体失败')
   assert(p.invoke(self.m.squareWall,x,y,true)~=false,'刷新墙体失败')
  end
  function a:writeFramedObject(op)
   for yy=0,op.h-1 do
    for xx=0,op.w-1 do
     local x,y=op.x+xx,op.y+yy
     local index=y*self.current.maxX+x
     local wall=p.invoke(self.m.GetWall,index)
     local liquid=p.invoke(self.m.GetLiquid,index)
     assert(p.invoke(self.m.setType,index,op.tile)~=false,'写入家具类型失败')
     assert(p.invoke(self.m.setHeader,index,0x20)~=false,'写入家具状态失败')
     assert(p.invoke(self.m['SetBHeader'],index,0)~=false,'写入家具数据失败')
     assert(p.invoke(self.m['SetBHeader2'],index,0)~=false,'写入家具数据失败')
     assert(p.invoke(self.m['SetBHeader3'],index,0)~=false,'写入家具数据失败')
     assert(p.invoke(self.m.setFrameXY,index,xx*18,yy*18)~=false,'写入家具帧失败')
     assert(p.invoke(self.m.setWall,index,wall)~=false,'保留墙体失败')
     assert(p.invoke(self.m.setLiquid,index,liquid)~=false,'保留液体失败')
     assert(p.invoke(self.m.setFramed,index,true)~=false,'标记家具失败')
    end
   end
   return true
  end
  function a:beginBuild() self.blocked={} end
  function a:execute(op)
   local ret
   local key=op.x..','..op.y
   self.blocked=self.blocked or {}
   if self.blocked[key] then return true end
   if op.kind=='clear' then
    if op.clearMode then
     assert(self.clearDestination,'缺少平台清除接口')
     return self:clearDestination(op)
    end
    local c=self:read(op.x,op.y)
    -- Recheck immediately before destructive edits; never clear a newly placed object.
    local safe=require('validator').safe
    local liquid=c.liquid
    if op.force then
     -- Undo may remove the ordinary framed furniture installed by the mod, but
     -- must stop if the user has since added liquid, wiring, or protected tiles.
     if liquid~=0 or c.wires or c.protected then self.blocked[key]=true;return true end
     if c.active and Policy.tree(c.type)then self.blocked[key]=true;return true end
     if c.active then ret=p.invoke(self.m.kill,op.x,op.y,false,false,true);assert(ret~=false,'撤回清理方块失败') end
     if c.wall~=0 then self:removeWall(op.x,op.y) end
     return true
    end
    if op.drain then c.liquid=0 end
    if not safe(c) then self.blocked[key]=true;return true end
    if op.drain and liquid~=0 then assert(p.invoke(self.m.setLiquid,op.y*self.current.maxX+op.x,0)~=false,'清理通道液体失败')end
    if c.active then ret=p.invoke(self.m.kill,op.x,op.y,false,false,true);assert(ret~=false,'清理方块失败') end
    if c.wall~=0 and not op.keepWall then self:removeWall(op.x,op.y) end
   elseif op.kind=='rawCell' then
    assert(self.writeCell and self:writeCell(op.x,op.y,op.cell),'逐格蓝图写入失败')
   elseif op.kind=='rawShape' then
    local c=self:captureCell(op.x,op.y);local source=op.cell
    c.header=(c.header&0x8bc0)|(source.header&0x743f)
    c.b1=(c.b1&0xe0)|(source.b1&0x1f)
    c.b3=(c.b3&0x0f)|(source.b3&0xf0)
    assert(self:writeCell(op.x,op.y,c),'恢复斜坡与涂色失败')
   elseif op.kind=='frameWall' then
    assert(p.invoke(self.m.squareWall,op.x,op.y,true)~=false,'刷新蓝图墙体失败')
   elseif op.kind=='rawObject' then
    local blocked=false
    for yy=0,op.h-1 do for xx=0,op.w-1 do if self.blocked[(op.x+xx)..','..(op.y+yy)]then blocked=true end end end
    if blocked then
     for yy=0,op.h-1 do for xx=0,op.w-1 do self.blocked[(op.x+xx)..','..(op.y+yy)]=true end end
    else
     for yy=0,op.h-1 do for xx=0,op.w-1 do assert(self:writeCell(op.x+xx,op.y+yy,op.cells[yy*op.w+xx+1]),'家具完整帧写入失败')end end
     if op.container then
      self:restoreEntity({kind='chest',x=0,y=0,text='',capacity=40,items=string.rep(string.pack('<i2i2BB',0,0,0,0),40)},op.x,op.y)
     end
    end
   elseif op.kind=='tile' then

    ret=p.invoke(self.m.tile,op.x,op.y,op.tile,true,true,-1,op.style or 0);assert(ret==true,'放置方块失败')
   elseif op.kind=='wall' then

    ret=p.invoke(self.m.wall,op.x,op.y,op.wall,true);assert(ret~=false,'放置墙体失败')
   elseif op.kind=='object' then
    for x=op.x,op.x+op.w-1 do for y=op.y,op.y+op.h-1 do if self.blocked[x..','..y] then return true end end end
    if op.objectKind=='torch' then ret=p.invoke(self.m.tile,op.x,op.y,op.tile,true,false,-1,op.style);assert(ret==true,'放置照明失败')
    else
     local origin=self:objectShape{tile=op.tile,style=op.style,w=op.w,h=op.h,kind=op.objectKind}
     if op.objectKind=='chest' then ret=p.invoke(self.m.chest,op.x+origin.x,op.y+origin.y,op.tile,false,op.style);assert(type(ret)=='number' and ret>=0,'放置箱子失败')
     else
      -- Native PlaceObject rejects doors and several legacy furniture types on
      -- Android. The floor and walls are already present at this phase, so write
      -- the framed cells directly, matching the proven blueprint paste path.
      self:writeFramedObject(op)
     end
    end
   elseif op.kind=='rope' then
    local old=self:captureCell(op.x,op.y)
    assert(self:writeCell(op.x,op.y,{type=213,wall=old.wall,liquid=0,header=0x20,
      fx=0,fy=0,b1=0,b2=0,b3=0}),'绳索写入失败')
   elseif op.kind=='stair' then
    -- Terraria platform stair frame columns: 8 climbs right, 10 climbs left.
    -- Preserve Obsidian Platform style row 13 after the ordinary framing pass.
    if not self.blocked[key] then
     local index=op.y*self.current.maxX+op.x
     assert(p.invoke(self.m.setFrameXY,index,8*18,(op.style or 0)*18)~=false,'楼梯平台帧写入失败')
     assert(p.invoke(self.m.setFramed,index,true)~=false,'楼梯平台标记失败')
    end
   elseif op.kind=='frame' then ret=p.invoke(self.m.frame,op.x,op.y,true);assert(ret~=false,'刷新失败')
   else error('未知施工操作') end
   return true
  end
  function a:enableBlueprints()
   return require('blueprint_adapter').extend(self,p,{typ=typ,method=method,field=field})
  end
  function a:enableOverlay(selection,onError)
   return require('world_overlay').new(self,p,{typ=typ,method=method,field=field},selection,onError)
  end
  function a:enableSelectionInput()
   return require('selection_input').new(p,{typ=typ,method=method,field=field})
  end
  function a:attach(callback)
   if self.hook then return self.hook end
   self.hook=need(p.install_hook(self.m.update,{postfix=function() callback() end}),'游戏更新钩子');return self.hook
  end
  function a:close()
   if self.hook then self.hook:remove();self.hook=nil end
   self.current=nil;self.shape={}
  end
  return a
 end)
 if ok then return result end
 return nil,tostring(result)
end
return M
