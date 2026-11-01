-- Additional native interop, resolved once; blueprint data never holds these handles.
local Policy=require('tile_policy')
local Layers=require('paste_layers')
local M={}
local function need(v,msg)assert(v~=nil and v~=false,msg);return v end
local function signed(n)return n>=32768 and n-65536 or n end
function M.extend(a,p,api)
 if a.captureCell then return true end
 for _,n in ipairs{'array_length','array_at_raw','array_set_raw','set_field_value'} do need(p[n],'复制功能缺少接口 '..n) end
 local T,F,Q=api.typ,api.field,api.method
 local TD=T('Terraria','TileData');local OD=T('Terraria.ObjectData','TileObjectData')
 local Main=T('Terraria','Main');local Chest=T('Terraria','Chest');local Sign=T('Terraria','Sign')
 local m={};local meta={}
 m.GetTileData=Q(OD,'GetTileData',{'int32','int32','int32'},{'type','style','alternate'},true)
 for _,n in ipairs{'GetFrameX','GetFrameY','GetBHeader','GetBHeader2','GetBHeader3'} do m[n]=Q(TD,n,{'int32'},{'tileIndex'},true) end
 for _,entry in ipairs{
  {'SetType','uint16','newType'},{'SetSHeader','int16','sHeader'},
  {'SetBHeader','uint8','bHeader'},{'SetBHeader2','uint8','bHeader2'},{'SetBHeader3','uint8','bHeader3'},
  {'SetWall','uint16','wall'},{'SetLiquid','uint8','liquid'},{'SetSearchUID','uint16','value'}
 } do m[entry[1]]=Q(TD,entry[1],{'int32',entry[2]},{'tileIndex',entry[3]},true) end
 m.SetFrameXY=Q(TD,'SetFrameXY',{'int32','int16','int16'},{'tileIndex','frameX','frameY'},true)
 m.SetTileFramed=Q(TD,'SetTileFramed',{'int32','bool'},{'tileIndex','framed'},true)
 for _,n in ipairs{'Width','Height','CoordinateWidth','CoordinatePadding','CoordinateFullWidth','CoordinateFullHeight','CoordinateHeights'} do
  m[n]=Q(OD,'get_'..n,{},nil,false)
 end
 m.createChest=Q(Chest,'CreateChest',{'int32','int32','int32'},{'X','Y','id'},true)
 m.removeChest=Q(Chest,'DestroyChestDirect',{'int32','int32','int32'},{'X','Y','id'},true)
 m.killSign=Q(Sign,'KillSign',{'int32','int32'},{'x','y'},true)
 m.findChest=Q(Chest,'FindChest',{'int32','int32'},{'X','Y'},true)
 m.readSign=Q(Sign,'ReadSign',{'int32','int32','bool'},{'i','j','CreateIfMissing'},true)
 local f={chests=F(Main,'chest',true),signs=F(Main,'sign',true)}
 for _,n in ipairs{'x','y','name','item','maxItems'} do f['chest_'..n]=F(Chest,n,false) end
 for _,n in ipairs{'x','y','text'} do f['sign_'..n]=F(Sign,n,false) end
 local function call(n,...)local r=p.invoke(m[n],...);assert(r~=false,'游戏蓝图接口失败 '..n);return r end
 local function index(x,y)
  local s=need(a.current,'世界尚未就绪');assert(x>=1 and y>=1 and x<s.maxX-1 and y<s.maxY-1,'蓝图坐标越界')
  return y*s.maxX+x
 end
 function a:objectBounds(c,x,y)
  if Policy.tree(c.type)then return end
  if not c.frameImportant and not self:isFramed(c.type)then return end
  local v=meta[c.type]
  if not v then
   local data=p.invoke(m.GetTileData,c.type,0,0)
   if not data then
    local legacy=Policy.origin(c.type)
    if c.type==19 then return {x=x,y=y,width=1,height=1}end
    if legacy then
     return {x=x-(c.fx//18)%legacy[3],y=y-(c.fy//18)%legacy[4],width=legacy[3],height=legacy[4]}
    end
    return nil,'家具缺少放置元数据'
   end
   v={}
   for _,n in ipairs{'Width','Height','CoordinateWidth','CoordinatePadding','CoordinateFullWidth','CoordinateFullHeight'} do v[n]=call(n,data) end
   assert(v.Width>0 and v.Height>0 and v.Width<=64 and v.Height<=64 and v.CoordinateFullWidth>0 and v.CoordinateFullHeight>0,'家具放置元数据异常')
   local heights=call('CoordinateHeights',data);v.heights={}
   for i=0,v.Height-1 do v.heights[i+1]=need(p.array_at(heights,i,'int32'),'家具行高数据不可读') end
   meta[c.type]=v
  end
  local fx=c.fx%v.CoordinateFullWidth;local fy=c.fy%v.CoordinateFullHeight
  local dx=math.floor(fx/(v.CoordinateWidth+v.CoordinatePadding));local dy=0
  for row,h in ipairs(v.heights) do if fy<h+v.CoordinatePadding then dy=row-1;break end;fy=fy-h-v.CoordinatePadding end
  return {x=x-dx,y=y-dy,width=v.Width,height=v.Height}
 end
 function a:captureCell(x,y)
  local base=self:read(x,y);local i=index(x,y)
  local c={type=base.type,wall=base.wall,header=base.header,liquid=base.liquid,frameImportant=base.frameImportant,container=base.container,sign=base.sign}
  c.fx=call('GetFrameX',i);c.fy=call('GetFrameY',i)
  c.b1=call('GetBHeader',i);c.b2=call('GetBHeader2',i);c.b3=call('GetBHeader3',i)
  if not base.active then c.type=0;c.fx=0;c.fy=0;c.header=c.header & 0x8b9f;c.frameImportant=false end
  c.omit=base.active and (Policy.tree(c.type) or Policy.unsupported(c.type) or (c.container and not Policy.container(c.type)))
  return c
 end
 function a:isFramed(id)
  return p.array_at(self.specialTileFlags[1],id,'bool')==true and not Policy.tree(id) and not Policy.unsupported(id) and not (p.array_at(self.specialTileFlags[2],id,'bool')==true and not Policy.container(id))
 end
 function a:clearForPaste(x,y,options)
  if not options.blocks then return true end
  local c=self:captureCell(x,y)
  if (c.header&0x20)~=0 and (Policy.unsupported(c.type)or c.container or c.sign or (c.frameImportant and c.type~=19 and not Policy.tree(c.type)))then
   self.blocked[x..','..y]=true;return true
  end
  return self:writeCell(x,y,Layers.clearBlock(c))
 end
 function a:writeCell(x,y,c)
  local i=index(x,y)
  call('SetType',i,c.type);call('SetSHeader',i,signed(c.header))
  call('SetBHeader',i,c.b1);call('SetBHeader2',i,c.b2);call('SetBHeader3',i,c.b3)
  call('SetFrameXY',i,c.fx,c.fy);call('SetWall',i,c.wall);call('SetLiquid',i,c.liquid)
  call('SetSearchUID',i,0);call('SetTileFramed',i,true)
  return true
 end
 function a:captureEntity(cell,x,y,rect)
  if not cell.container and not cell.sign then return end
  local bounds,why=self:objectBounds(cell,x,y)
  assert(bounds,why or '家具实体位置不可读')
  if bounds.x~=x or bounds.y~=y then return end
  assert(bounds.x>=rect.x and bounds.y>=rect.y and bounds.x+bounds.width<=rect.x+rect.width and bounds.y+bounds.height<=rect.y+rect.height,'选区切到了家具边缘，请扩大选区一格')
  if cell.container then
   assert(Policy.container(cell.type),'当前箱子类型不支持复制')
   local id=call('findChest',x,y);assert(type(id)=='number' and id>=0,'箱子实体不存在')
   local arr=need(p.get_field_value(f.chests,nil,'object'),'箱子列表不可读')
   assert(id<p.array_length(arr),'箱子实体编号越界')
   local chest=need(p.array_at(arr,id),'箱子实体不可读')
   local items=need(p.get_field_value(f.chest_item,chest,'object'),'箱子物品不可读');local count=p.array_length(items)
   assert(count<=200,'箱子物品格数不支持');local raw={}
   for j=0,count-1 do raw[#raw+1]=need(p.array_at_raw(items,j,6),'箱子物品读取失败') end
   return {kind='chest',x=x-rect.x,y=y-rect.y,text=p.get_field_value(f.chest_name,chest,'string') or '',capacity=p.get_field_value(f.chest_maxItems,chest,'int32'),items=table.concat(raw)}
  elseif cell.sign then
   local id=call('readSign',x,y,false);assert(type(id)=='number' and id>=0,'告示牌实体不存在')
   local arr=need(p.get_field_value(f.signs,nil,'object'),'告示牌列表不可读')
   assert(id<p.array_length(arr),'告示牌编号越界')
   local sign=need(p.array_at(arr,id),'告示牌实体不可读')
   return {kind='sign',x=x-rect.x,y=y-rect.y,text=p.get_field_value(f.sign_text,sign,'string') or '',items=''}
  end
 end
 function a:restoreEntity(e,x,y)
  x=x+e.x;y=y+e.y
  if e.kind=='chest' then
   local id=call('findChest',x,y);if id<0 then id=call('createChest',x,y,-1)end;assert(type(id)=='number' and id>=0,'箱子实体创建失败')
   local arr=need(p.get_field_value(f.chests,nil,'object'),'箱子列表不可读');local c=need(p.array_at(arr,id),'箱子实体不存在')
   local items=need(p.get_field_value(f.chest_item,c,'object'),'目标箱子不可读');local count=#e.items//6
   assert(p.array_length(items)>=count,'目标箱子容量不足，未写入物品')
   for i=0,count-1 do assert(p.array_set_raw(items,i,e.items:sub(i*6+1,i*6+6)),'箱子物品还原失败') end
   p.set_field_value(f.chest_maxItems,c,e.capacity or count,'int32')
   p.set_field_value(f.chest_name,c,e.text,'string')
  else
   local id=call('readSign',x,y,true);assert(type(id)=='number' and id>=0,'告示牌实体创建失败')
   local arr=need(p.get_field_value(f.signs,nil,'object'),'告示牌列表不可读');local c=need(p.array_at(arr,id),'告示牌实体不存在')
   p.set_field_value(f.sign_text,c,e.text,'string')
  end
 end
 require('platform_clear').attach(a,p,m)
 return true
end
return M
