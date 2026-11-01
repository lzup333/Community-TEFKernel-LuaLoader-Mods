local B=require('blueprint')
local M={}
function M.flip(source,adapter)
 local bp=B.clone(source)
 local w,h=bp.width,bp.height
 local cells={}
 for y=0,h-1 do for x=0,w-1 do
  local c=bp.cells[y*w+x+1]
  cells[y*w+(w-1-x)+1]=c
  -- Platform stairs use fixed frame columns 8/10 for opposite directions.
  if c.type==19 then if c.fx==144 then c.fx=180 elseif c.fx==180 then c.fx=144 end end
 end end
 local groups={}
 for y=0,h-1 do for x=0,w-1 do
  local c=bp.cells[y*w+x+1]
  if (c.header&0x20)~=0 and adapter:isFramed(c.type) and c.type~=19 then
   local box,why=adapter:objectBounds(c,x,y)
   assert(box,why or '镜像家具边界不可读')
   assert(box.x>=0 and box.y>=0 and box.x+box.width<=w and box.y+box.height<=h,'镜像家具超出蓝图')
   groups[box.x..','..box.y..':'..c.type]=box
  end
 end end
 local origins={}
 for _,box in pairs(groups)do
  local nx=w-box.x-box.width
  origins[box.x..','..box.y]=nx
  for dy=0,box.height-1 do for dx=0,box.width-1 do
   cells[(box.y+dy)*w+nx+dx+1]=bp.cells[(box.y+dy)*w+box.x+dx+1]
  end end
 end
 bp.cells=cells;bp.anchorX=w-1-bp.anchorX
 for _,e in ipairs(bp.entities)do e.x=origins[e.x..','..e.y] or w-1-e.x end
 return bp
end
return M
