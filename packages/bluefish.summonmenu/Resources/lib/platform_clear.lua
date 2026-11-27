-- Dedicated destructive corridor/rollback policy. Ordinary house placement
-- retains its existing protection rules. Unknown tile entities stay intact.
local Policy=require('tile_policy')
local Layers=require('paste_layers')
local zero={type=0,wall=0,liquid=0,header=0,fx=0,fy=0,b1=0,b2=0,b3=0}
local M={}
function M.attach(a,p,m)
 function a:clearDestination(op)
  local c=self:read(op.x,op.y);local key=op.x..','..op.y
  local selection=op.clearMode=='selection'
  local options=selection and op.options
  if selection and not options.blocks then
   local old=self:captureCell(op.x,op.y)
   assert(self:writeCell(op.x,op.y,Layers.merge(zero,old,options)),'清理墙体、线路或液体失败')
   return true
  end
  if selection then
   -- v1.2.9：框选清理一律清干净。先让游戏自己拆（能正确处理多格家具、箱子内容、
   -- 告示牌和展示类实体），拆不掉的再按勾选的层强制写空。
   -- v1.3.2：普通方块直接写空；只有家具、容器、牌子和特殊方块才交给游戏拆。
   if c.active and self.m and self.m.kill and (c.frameImportant or c.container or c.sign or Policy.unsupported(c.type))then
    pcall(p.invoke,self.m.kill,op.x,op.y,false,false,true)
   end
   local old=self:captureCell(op.x,op.y)
   assert(self:writeCell(op.x,op.y,Layers.merge(zero,old,options)),'强制清理格子失败')
   return true
  end
  local function block()self.blocked[key]=true;return true end
  if c.active and (Policy.unsupported(c.type)or(c.container and not Policy.container(c.type)))then return block()end
  local box={x=op.x,y=op.y,width=1,height=1}
  if c.active and c.frameImportant and not Policy.tree(c.type)then
   local framed=self:captureCell(op.x,op.y)
   local shape=self:objectBounds(framed,op.x,op.y)
   if shape then box=shape
   elseif not c.container and not c.sign and self.m and self.m.kill then
    -- Some legacy decorative tiles have no TileObjectData. Let the game's
    -- own multi-tile teardown resolve these before writing an empty cell.
    assert(p.invoke(self.m.kill,op.x,op.y,false,false,true)~=false,'清除原版装饰失败')
    if self:read(op.x,op.y).active then return block()end
   else return block()end
  end
  local s=self.current
  if box.x<1 or box.y<1 or box.x+box.width>=s.maxX or box.y+box.height>=s.maxY then return block()end
  -- Validate a complete footprint before any entity or tile is removed.
  for y=box.y,box.y+box.height-1 do for x=box.x,box.x+box.width-1 do
   local v=self:read(x,y)
   if v.active and (v.type~=c.type or Policy.unsupported(v.type))then return block()end
  end end
  if c.active and c.container then
   local id=p.invoke(m.findChest,box.x,box.y)
   assert(type(id)=='number','读取待清理箱子失败')
   if id>=0 then assert(p.invoke(m.removeChest,box.x,box.y,id)~=false,'清理箱子实体失败')end
  elseif c.active and c.sign then
   assert(p.invoke(m.killSign,box.x,box.y)~=false,'清理告示牌实体失败')
  end
  for y=box.y,box.y+box.height-1 do for x=box.x,box.x+box.width-1 do
   local old=self:captureCell(x,y)
   -- Raw TileData writes bypass mining restrictions without spawning drops.
   -- Outside the corridor only remove the intersecting object's tile state;
   -- preserve its wall/liquid and unrelated wiring.
   local at=x==op.x and y==op.y
   local drain=op.drain or op.clearMode=='restore'
   local header=at and 0 or (old.header & 0x8b80)
   local result
   if selection then result=Layers.merge(zero,old,at and options or {blocks=true,walls=false,wires=false,liquid=false})
   else result={type=0,wall=(op.keepWall or not at)and old.wall or 0,
    liquid=(drain and at)and 0 or old.liquid,header=header,fx=0,fy=0,b1=at and 0 or old.b1,b2=at and 0 or old.b2,b3=at and 0 or old.b3}end
   assert(self:writeCell(x,y,result),'强制清理格子失败')
   assert(not self:read(x,y).active,'方块清除后仍然存在')
  end end
  return true
 end
end
return M
