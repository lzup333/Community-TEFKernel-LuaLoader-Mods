local B=require('blueprint')
local Layers=require('paste_layers')
local M={}
local function point(bp,i)return (i-1)%bp.width,(i-1)//bp.width end
function M.new(adapter)
 local j={a=adapter,state='idle',message='选择区域后复制',progress=0,budget=32}
 function j:busy()return self.state~='idle' and self.state~='done' and self.state~='error' and self.state~='cancelled'end
 function j:fail(e)
  self.state='error';self.message=tostring(e);self.command=nil;self.bp=nil;self.groups=nil;self.result=nil
  -- A failed capture is terminal; leaving its last percentage visible looks like
  -- the operation is still running and makes retry state ambiguous.
  self.progress=0
 end
 function j:cancel()self.command=nil;self.bp=nil;self.groups=nil;self.result=nil;self.state='cancelled';self.message='已取消；已粘贴部分保留';self.progress=0 end
 function j:capture(rect,name,exact)
  if self:busy() then return false end
  local r={};for k,v in pairs(rect)do r[k]=v end
  self.command={kind='capture',rect=r,name=name,exact=exact==true};self.state='queued';self.result=nil;self.progress=0;self.message='复制任务已排队';return true
 end
 function j:paste(bp,options)
  if self:busy() then return false end
  self.command={kind='paste',bp=B.clone(bp),options=Layers.normalize(options)};self.state='queued';self.result=nil;self.progress=0;self.message='建造任务已排队';return true
 end
 function j:pasteAt(bp,x,y,worldKey,forceClear,options)
  if self:busy() then return false end
  self.command={kind='paste',bp=B.clone(bp),x=x,y=y,worldKey=worldKey,forceClear=forceClear==true,options=Layers.normalize(forceClear and nil or options)}
  self.state='queued';self.result=nil;self.progress=0;self.message=forceClear and '撤回建筑：恢复施工前区域' or '建造任务已排队';return true
 end
 function j:prepareGroups()
  local bp=self.bp;local flags={};self.groups={};self.framed={}
  local byOrigin={}
  for i,c in ipairs(bp.cells)do
   if flags[c.type]==nil then flags[c.type]=self.a:isFramed(c.type)end
   local framed=(not self.options or self.options.blocks) and (c.header & 0x20)~=0 and flags[c.type]
   self.framed[i]=framed
   if framed then
    local x,y=point(bp,i)
    local box,why=self.a:objectBounds(c,self.x+x,self.y+y)
    assert(box,why or '家具边界不可读')
    local key=box.x..','..box.y..':'..c.type
    local group=byOrigin[key]
    if not group then group={};byOrigin[key]=group;self.groups[#self.groups+1]=group end
    group[#group+1]=i
   end
  end
 end
 function j:blocked(i)
  local x,y=point(self.bp,i)
  return self.a.blocked and self.a.blocked[(self.x+x)..','..(self.y+y)]
 end
 function j:write(i)
  local o=self.options
  if self:blocked(i)then self.skipped=self.skipped+1;o=Layers.normalize(o);o.blocks=false end
  local x,y=point(self.bp,i);x=x+self.x;y=y+self.y
  local c=self.bp.cells[i]
  if self.a.captureCell then c=Layers.merge(c,self.a:captureCell(x,y),o)end
  assert(self.a:writeCell(x,y,c),'蓝图写入失败')
 end
 function j:expandCapture(bounds,snapshot)
  local r=self.rect
  local x1=math.min(r.x,bounds.x);local y1=math.min(r.y,bounds.y)
  local x2=math.max(r.x+r.width,bounds.x+bounds.width);local y2=math.max(r.y+r.height,bounds.y+bounds.height)
  local w,h=x2-x1,y2-y1
  assert(w<=B.MAX_W and h<=B.MAX_H,'家具超出选区最大尺寸，无法自动扩展')
  assert(x1>=1 and y1>=1 and x2<snapshot.maxX and y2<snapshot.maxY,'家具超出世界边界，无法自动扩展')
  if x1==r.x and y1==r.y and w==r.width and h==r.height then return false end
  r.x=x1;r.y=y1;r.width=w;r.height=h
  self.bp={name=self.bp.name,width=w,height=h,anchorX=math.floor(w/2),anchorY=h-1,cells={},entities={},omitted=0}
  self.index=1;self.progress=0;self.message='选区已自动扩展以包含完整家具，继续复制'
  return true
 end
 function j:finishCapture()
  local bp=self.bp
  self:validateCaptured();B.validate(bp);self.result=bp;self.bp=nil
  self.state='done';self.progress=1;self.message='复制完成；跳过不支持的特殊格 '..bp.omitted
 end
 function j:validateCaptured()
  if not self.a.objectBounds then return end
  local bp,r=self.bp,self.rect;local entities={};local checked={}
  for _,e in ipairs(bp.entities)do entities[e.x..','..e.y..':'..e.kind]=true end
  for i,c in ipairs(bp.cells)do if (c.header & 0x20)~=0 and not c.omit and c.frameImportant and not require('tile_policy').tree(c.type) then
   local x,y=point(bp,i);local box=assert(self.a:objectBounds(c,r.x+x,r.y+y))
   local left,top=box.x-r.x,box.y-r.y;local key=left..','..top
   if not checked[key..':'..c.type]then
    checked[key..':'..c.type]=true
    for yy=top,top+box.height-1 do for xx=left,left+box.width-1 do
     local other=bp.cells[yy*bp.width+xx+1]
     assert(other and other.type==c.type and (other.header & 0x20)~=0,'复制期间家具不完整，请重新框选复制')
    end end
    local kind=c.container and 'chest' or (c.sign and 'sign')
    if kind then assert(entities[key..':'..kind],'家具实体记录缺失，未保存不完整蓝图')end
   end
  end end
 end
 function j:tickInternal()
  if not self:busy() then return end
  local s=self.a:snapshot()
  assert(not s.menu and not s.multiplayer and not s.dead,'请在存活的单人世界内使用')
  if self.command then
   local cmd=self.command;self.command=nil;self.progress=0;self.index=1
   if cmd.kind=='capture' then
    local r=cmd.rect
    assert(r.worldKey==s.worldKey,'世界已切换，请重新框选')
    assert(type(r.x)=='number' and r.x%1==0 and type(r.y)=='number' and r.y%1==0,'选区坐标无效')
    assert(type(r.width)=='number' and r.width%1==0 and r.width>=1 and r.width<=B.MAX_W and type(r.height)=='number' and r.height%1==0 and r.height>=1 and r.height<=B.MAX_H,'选区尺寸无效')
    assert(r.x>=1 and r.y>=1 and r.x+r.width<s.maxX and r.y+r.height<s.maxY,'选区超出世界边界')
    self.worldKey=s.worldKey;self.rect=r;self.exactCapture=cmd.exact
    self.bp={name=cmd.name,width=r.width,height=r.height,anchorX=math.floor(r.width/2),anchorY=r.height-1,cells={},entities={},omitted=0}
    self.state='capturing';self.message='复制建筑数据中'
   else
    self.bp=cmd.bp;self.worldKey=s.worldKey
    if cmd.worldKey then assert(cmd.worldKey==s.worldKey,'世界已切换，撤回已停止')end
    self.x=cmd.x or (s.playerFeet.x-self.bp.anchorX);self.y=cmd.y or (s.playerFeet.y-self.bp.anchorY);self.forceClear=cmd.forceClear==true
    assert(type(self.x)=='number' and self.x%1==0 and type(self.y)=='number' and self.y%1==0,'建筑坐标无效')
    assert(self.x>=1 and self.y>=1 and self.x+self.bp.width<s.maxX and self.y+self.bp.height<s.maxY,'建筑超出世界边界')
    self.options=Layers.normalize(cmd.options);if self.forceClear then self.options=Layers.normalize()end
    assert(Layers.any(self.options),'请至少选择一种粘贴内容')
    self:prepareGroups();self.a:beginBuild();self.phase='clear';self.skipped=0;self.state='pasting';self.message='直接粘贴：清理普通障碍'
   end
  end
  assert(s.worldKey==self.worldKey,'世界已切换，任务停止')
  local bp=self.bp
  if self.state=='capturing' then
   for _=1,self.budget do
    if self.index>bp.width*bp.height then self:finishCapture();break end
    local x,y=point(bp,self.index);x=x+self.rect.x;y=y+self.rect.y
    local c=self.a:captureCell(x,y)
    -- Exact rollback snapshots retain raw protected cells; entity handling still skips them.
    if self.exactCapture and require('tile_policy').tree(c.type)then c.omit=false end
    if c.omit and not self.exactCapture then
     c.type=0;c.header=0;c.fx=0;c.fy=0;bp.omitted=bp.omitted+1
    elseif (c.header & 0x20)~=0 and not c.omit and c.frameImportant and not require('tile_policy').tree(c.type) and self.a.objectBounds then
     local bounds,why=self.a:objectBounds(c,x,y)
     assert(bounds,why or '家具放置数据不可读')
     if bounds.x<self.rect.x or bounds.y<self.rect.y or bounds.x+bounds.width>self.rect.x+bp.width or bounds.y+bounds.height>self.rect.y+bp.height then
      if self:expandCapture(bounds,s) then bp=self.bp;break end
     end
    end
    if not c.omit and self.a.captureEntity then
     local entity=self.a:captureEntity(c,x,y,self.rect)
     if entity then bp.entities[#bp.entities+1]=entity end
    end
    bp.cells[self.index]=c;self.index=self.index+1
   end
   if self.state=='capturing'then self.progress=math.min(0.9,(self.index-1)/(bp.width*bp.height)*0.9)end
  elseif self.state=='pasting' then
   if self.phase=='clear' then
    for _=1,self.budget do
     if self.index>bp.width*bp.height then self.phase='tiles';self.index=bp.width*bp.height;self.message=self.forceClear and '撤回建筑：恢复方块和墙体' or '直接粘贴：主体和墙体';break end
     local x,y=point(bp,self.index);local ok
     if not self.forceClear and self.a.clearForPaste then ok=self.a:clearForPaste(self.x+x,self.y+y,self.options)else ok=self.a:execute{kind='clear',x=self.x+x,y=self.y+y,force=self.forceClear,clearMode=self.forceClear and 'restore' or nil}end
     assert(ok,'清理失败');self.index=self.index+1
    end
    self.progress=math.min(0.4,(self.index-1)/(bp.width*bp.height)*0.4)
   elseif self.phase=='tiles' then
    for _=1,self.budget do
     if self.index<1 then self.phase='objects';self.index=1;self.message='还原家具帧和朝向';break end
     if not self.framed[self.index] then self:write(self.index)end;self.index=self.index-1
    end
    self.progress=0.4+(bp.width*bp.height-math.max(self.index,0))/(bp.width*bp.height)*0.4
   elseif self.phase=='objects' then
    local group=self.groups[self.index]
    if not group then self.phase='entities';self.index=1;self.message='创建箱子和告示牌实体'
    else
     local blocked=false;for _,i in ipairs(group)do if self:blocked(i) then blocked=true end end
     if blocked then
      for _,i in ipairs(group)do local x,y=point(bp,i);self.a.blocked[(self.x+x)..','..(self.y+y)]=true end
     end
     for _,i in ipairs(group)do self:write(i)end
     self.index=self.index+1
    end
    self.progress=0.8+math.min(1,(self.index-1)/math.max(1,#self.groups))*0.15
   else
    local e=bp.entities[self.index]
    if e then
     if self.options.blocks and not (self.a.blocked and self.a.blocked[(self.x+e.x)..','..(self.y+e.y)])then self.a:restoreEntity(e,self.x,self.y)end
     self.index=self.index+1
    else self.state='done';self.progress=1;self.message='粘贴完成；保留目标特殊格 '..self.skipped;self.bp=nil;self.groups=nil;self.framed=nil end
   end
  end
 end
 function j:tick()local ok,e=pcall(self.tickInternal,self);if not ok then self:fail(e)end end
 return j
end
return M
