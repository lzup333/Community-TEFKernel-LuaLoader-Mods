-- Portable values only: no managed handles, pointers, executable Lua or palette indices.
local M={GAME='Terraria-1.4.5.8',MAX_W=256,MAX_H=128,MAX_CELLS=32768,MAX_BYTES=4*1024*1024}
local function int(n,lo,hi) return type(n)=='number' and n%1==0 and n>=lo and n<=hi end
function M.checksum(s)
 local v=2166136261
 for i=1,#s do v=((v ~ s:byte(i))*16777619)&0xffffffff end
 return v
end
function M.validate(b)
 assert(type(b)=='table' and type(b.name)=='string' and #b.name<=120,'蓝图名称无效')
 assert((not b.gameVersion) or b.gameVersion==M.GAME,'蓝图游戏版本不支持')
 assert(int(b.width,1,M.MAX_W) and int(b.height,1,M.MAX_H) and b.width*b.height<=M.MAX_CELLS,'蓝图尺寸超限')
 assert(int(b.anchorX,0,b.width-1) and int(b.anchorY,0,b.height-1),'蓝图落点无效')
 assert(type(b.cells)=='table' and #b.cells==b.width*b.height,'蓝图格子数量错误')
 for _,c in ipairs(b.cells) do
  for _,k in ipairs{'type','wall','header'} do assert(int(c[k],0,65535),'蓝图字段错误 '..k) end
  for _,k in ipairs{'fx','fy'} do assert(int(c[k],-32768,32767),'蓝图帧错误') end
  for _,k in ipairs{'b1','b2','b3','liquid'} do assert(int(c[k],0,255),'蓝图状态错误') end
 end
 assert(type(b.entities)=='table' and #b.entities<=1000,'实体数量超限')
 for _,e in ipairs(b.entities) do
  assert(e.kind=='chest' or e.kind=='sign','实体类型不支持')
  assert(int(e.x,0,b.width-1) and int(e.y,0,b.height-1),'实体位置错误')
  assert(type(e.text)=='string' and #e.text<=8192,'实体文字过长')
  assert(type(e.items)=='string' and #e.items<=1200 and #e.items%6==0,'箱子物品数据错误')
  if e.kind=='chest' then
   assert(int(e.capacity or (#e.items//6),1,#e.items//6),'箱子容量错误')
   for i=1,#e.items,6 do local ty,stack,_,fav=string.unpack('<i2i2BB',e.items,i);assert(ty>=0 and stack>=0 and fav<=1,'箱子物品字段无效')end
  end
 end
 assert(int(b.omitted or 0,0,M.MAX_CELLS),'跳过数量错误')
 return true
end
function M.encode(b)
 M.validate(b)
 local parts={string.pack('<s1s2I2I2I2I2I4',M.GAME,b.name,b.width,b.height,b.anchorX,b.anchorY,b.omitted or 0)}
 local previous,count
 local function emit() if previous then parts[#parts+1]=string.pack('<I2',count)..previous end end
 for _,c in ipairs(b.cells) do
  local cell=string.pack('<I2I2I2i2i2BBBB',c.type,c.wall,c.header,c.fx,c.fy,c.b1,c.b2,c.b3,c.liquid)
  if cell==previous and count<65535 then count=count+1 else emit();previous=cell;count=1 end
 end
 emit();parts[#parts+1]=string.pack('<I2',0)..string.pack('<I2',#b.entities)
 for _,e in ipairs(b.entities) do parts[#parts+1]=string.pack('<BI2I2I2s2s2',e.kind=='chest' and 1 or 2,e.x,e.y,e.capacity or (#e.items//6),e.text,e.items) end
 local payload=table.concat(parts)
 return 'IHB2'..string.pack('<I4',M.checksum(payload))..payload
end
function M.decode(raw)
 local ok,result=pcall(function()
  assert(type(raw)=='string' and #raw<=M.MAX_BYTES and raw:sub(1,4)=='IHB2','蓝图格式不支持')
  assert(string.unpack('<I4',raw,5)==M.checksum(raw:sub(9)),'蓝图校验失败')
  local b={cells={},entities={}};local pos
  b.gameVersion,b.name,b.width,b.height,b.anchorX,b.anchorY,b.omitted,pos=string.unpack('<s1s2I2I2I2I2I4',raw,9)
  assert(b.width>=1 and b.width<=M.MAX_W and b.height>=1 and b.height<=M.MAX_H and b.width*b.height<=M.MAX_CELLS,'蓝图尺寸错误')
  while true do
   local n;n,pos=string.unpack('<I2',raw,pos);if n==0 then break end
   assert(#b.cells+n<=b.width*b.height,'蓝图格子过多')
   local c={};c.type,c.wall,c.header,c.fx,c.fy,c.b1,c.b2,c.b3,c.liquid,pos=string.unpack('<I2I2I2i2i2BBBB',raw,pos)
   for _=1,n do local copy={};for k,v in pairs(c) do copy[k]=v end;b.cells[#b.cells+1]=copy end
  end
  local n;n,pos=string.unpack('<I2',raw,pos);assert(n<=1000,'实体过多')
  for _=1,n do
   local kind,x,y,capacity,text,items;kind,x,y,capacity,text,items,pos=string.unpack('<BI2I2I2s2s2',raw,pos)
   assert(kind==1 or kind==2,'未知实体')
   b.entities[#b.entities+1]={kind=kind==1 and 'chest' or 'sign',x=x,y=y,capacity=capacity,text=text,items=items}
  end
  assert(pos==#raw+1,'蓝图尾部数据错误');M.validate(b);return b
 end)
 if ok then return result end
 return nil,tostring(result)
end
function M.clone(b) return assert(M.decode(M.encode(b))) end
return M
