local registry=require('templates.registry')
local BP=require('blueprint')
local C=require('templates.common')
local M={}
local function key(x,y) return x..','..y end
function M.build(options)
 local o={kind='prison',size=1,floors=1,rooms=1,theme=1,style=1,mirror=false,furniture=true,decor=true}
 for k,v in pairs(options or {}) do if o[k]~=nil then o[k]=v end end
 local t=registry.get(o.kind)
 if not t then return nil,'未知房型' end
 for k,max in pairs{size=3,floors=3,rooms=3,theme=2,style=3} do
  if type(o[k])~='number' or o[k]%1~=0 or o[k]<1 or o[k]>max then return nil,'参数超出范围：'..k end
 end
 -- Fixed structures ignore old configurable dimensions while preserving saved settings.
 o.size=1;o.floors=1;o.rooms=1
 if o.kind~='prison' then o.style=1 end
 for _,k in ipairs{'mirror','furniture','decor'} do if type(o[k])~='boolean' then return nil,'参数类型错误：'..k end end
 local material={block=t.block,wall=t.wall,roof=t.roof,beam=t.beam}
 if o.theme==2 then material.block=38;material.wall=5 end
 local b={map={},objects={},stations={},occupied={}}
 function b:tile(x,y,id)
  local c=self.map[key(x,y)] or {x=x,y=y};c.tile=id;self.map[key(x,y)]=c
 end
 function b:wall(x,y,id)
  local c=self.map[key(x,y)] or {x=x,y=y};c.wall=id;self.map[key(x,y)]=c
 end
 function b:erase(x,y) local c=self.map[key(x,y)];if c then c.tile=nil end end
 function b:freeObject(x,y,w,h,floor)
  for yy=y,y+h-1 do for xx=x,x+w-1 do
   if (self.map[key(xx,yy)] or {}).tile or self.occupied[key(xx,yy)] then return false end
  end end
  if floor then for xx=x,x+w-1 do local ft=(self.map[key(xx,y+h)] or {}).tile;if not ft or ft==19 then return false end end end
  return true
 end
 function b:object(kind,x,y,w,h,id)
  self.objects[#self.objects+1]={kind=kind,left=x,top=y,w=w,h=h,tile=id,style=0}
  for yy=y,y+h-1 do for xx=x,x+w-1 do self.occupied[key(xx,yy)]=true end end
 end
 require('templates.'..o.kind)(b,o,material)
 C.furnish(b,o,material)
 local names={'草木横屋','石砖悬屋','暗砖竖屋'}
 local layout=o.kind=='prison' and ('参考图片：'..names[o.style]) or t.layout
 local plan={cells={},objects={},solid={},options=o,bounds={x1=0,x2=0,y1=0,y2=0},baseTile=38,layout=layout}
 local function bound(x,y)
  local q=plan.bounds;q.x1=math.min(q.x1,x);q.x2=math.max(q.x2,x);q.y1=math.min(q.y1,y);q.y2=math.max(q.y2,y)
 end
 for _,c in pairs(b.map) do
  if o.mirror then c.x=-c.x end
  plan.cells[#plan.cells+1]=c
  if c.tile then plan.solid[key(c.x,c.y)]=c.tile end
  bound(c.x,c.y)
 end
 for _,obj in ipairs(b.objects) do
  if o.mirror then obj.left=-(obj.left+obj.w-1) end
  plan.objects[#plan.objects+1]=obj
  bound(obj.left,obj.top);bound(obj.left+obj.w-1,obj.top+obj.h-1)
 end
 local occupied={}
 for _,obj in ipairs(plan.objects) do
  for y=obj.top,obj.top+obj.h-1 do for x=obj.left,obj.left+obj.w-1 do
   local k=key(x,y)
   if occupied[k] then return nil,'家具重叠：'..obj.kind end
   if plan.solid[k] then return nil,'家具空间被占用：'..obj.kind end
   occupied[k]=true
  end end
  if obj.kind=='door' and not plan.solid[key(obj.left,obj.top-1)] then return nil,'门缺少门楣' end
  if obj.kind~='torch' then
   for x=obj.left,obj.left+obj.w-1 do
    local floor=plan.solid[key(x,obj.top+obj.h)]
    if not floor then return nil,'家具缺少支撑：'..obj.kind end
    -- Furnishings only use full blocks, avoiding platform style and slope anchoring assumptions.
    if floor==19 then return nil,'家具支撑不是实心地板：'..obj.kind end
   end
  else
   local wx=o.mirror and -obj.left or obj.left
   if not (b.map[key(wx,obj.top)] or {}).wall then return nil,'火把缺少背景墙' end
  end
 end
 if plan.bounds.x2-plan.bounds.x1>=BP.MAX_W or plan.bounds.y2-plan.bounds.y1>=BP.MAX_H then return nil,'结构超出安全范围' end
 table.sort(plan.cells,function(a,c) if a.y~=c.y then return a.y>c.y end return a.x<c.x end)
 return plan
end
return M
