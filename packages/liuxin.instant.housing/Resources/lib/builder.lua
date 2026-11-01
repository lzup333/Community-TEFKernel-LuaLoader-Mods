local planner=require('planner')
local M={}
local function copy(t) local out={};for k,v in pairs(t or {}) do out[k]=v end;return out end
function M.new(adapter)
 local c={a=adapter,state='idle',message='选择房型后直接建造',progress=0,budget=32}
 function c:fail(e) self.command=nil;self.state='error';self.message=tostring(e);self.ops=nil;self.progress=0 end
 function c:build(options,target)
  if self.state=='building' or self.command then return end
  self.command={options=copy(options),target=target};self.state='queued';self.message='等待游戏更新后建造'
 end
 function c:buildAt(options,anchor)
  if self.state=='building' or self.command then return end
  self.command={options=copy(options),target='fixed',anchor=copy(anchor)};self.state='queued';self.message='等待游戏更新后建造'
 end
 function c:cancel() self.command=nil;self.ops=nil;self.state='cancelled';self.message='已取消；已建部分保留';self.progress=0 end
 function c:status() return {state=self.state,message=self.message,progress=self.progress} end
 function c:operations()
  local p,a=self.plan,self.anchor;local ops={}
  local function add(op) ops[#ops+1]=op end
  local b=p.bounds
  for y=b.y1,b.y2 do for x=b.x1,b.x2 do add{kind='clear',x=a.x+x,y=a.y+y} end end
  if p.detailed then
   for _,v in ipairs(p.cells)do if v.group==0 then add{kind='rawCell',x=a.x+v.x,y=a.y+v.y,cell=v.raw}end end
   for _,v in ipairs(p.objects)do add{kind='rawObject',x=a.x+v.left,y=a.y+v.top,w=v.w,h=v.h,cells=v.raw,container=v.container}end
   for _,v in ipairs(p.cells)do
    if v.tile and not v.framed then add{kind='frame',x=a.x+v.x,y=a.y+v.y}end
    if v.wall then add{kind='frameWall',x=a.x+v.x,y=a.y+v.y}end
   end
   for _,v in ipairs(p.cells)do if v.group==0 then add{kind='rawShape',x=a.x+v.x,y=a.y+v.y,cell=v.raw}end end
   return ops
  end
  for _,v in ipairs(p.cells) do if v.tile then add{kind='tile',x=a.x+v.x,y=a.y+v.y,tile=v.tile} end end
  for _,v in ipairs(p.cells) do if v.wall then add{kind='wall',x=a.x+v.x,y=a.y+v.y,wall=v.wall} end end
  for _,v in ipairs(p.objects) do add{kind='object',objectKind=v.kind,x=a.x+v.left,y=a.y+v.top,w=v.w,h=v.h,tile=v.tile,style=v.style} end
  for _,v in ipairs(p.cells) do if v.tile then add{kind='frame',x=a.x+v.x,y=a.y+v.y} end end
  return ops
 end
 function c:tickInternal()
  if not self.command and self.state~='building' then return end
  local s=self.a:snapshot()
  if s.menu or s.multiplayer or s.dead then self:fail('请在单人世界内、角色存活时使用');return end
  if self.state=='building' and self.worldKey~=s.worldKey then self:fail('世界已切换，施工停止');return end
  if self.command then
   local cmd=self.command;self.command=nil
   local p,e=planner.build(cmd.options);if not p then self:fail(e);return end
   self.plan=p;self.anchor=copy(cmd.anchor or (cmd.target=='spawn' and s.spawn or s.playerFeet));self.worldKey=s.worldKey
   local b=p.bounds;local a=self.anchor
   if a.x+b.x1<1 or a.x+b.x2>=s.maxX-1 or a.y+b.y1<1 or a.y+b.y2>=s.maxY-1 then self:fail('建筑超出世界边界');return end
   if self.a.beginBuild then self.a:beginBuild() end
   self.ops=self:operations();self.index=1;self.state='building';self.message='直接建造中'
  end
  for _=1,self.budget do
   local op=self.ops[self.index]
   if not op then self.state='done';self.message='建造完成';self.progress=1;self.ops=nil;return end
   local ok,e=self.a:execute(op);if not ok then self:fail(e or '游戏放置接口执行失败');return end
   self.index=self.index+1
  end
  self.progress=(self.index-1)/#self.ops
 end
 function c:tick() local ok,e=pcall(self.tickInternal,self);if not ok then self:fail(e) end end
 return c
end
return M
