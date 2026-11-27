-- Stream operations instead of allocating a whole-world construction list.
local M={}
local function integer(n,lo,hi)return type(n)=='number'and n%1==0 and n>=lo and n<=hi end
function M.new(adapter)
 local j={a=adapter,state='idle',progress=0,message='选择平台参数',budget=16}
 function j:busy()return self.state=='queued'or self.state=='building'end
 function j:startAt(options)
  if self:busy()then return false end
  self.command={};for k,v in pairs(options)do self.command[k]=v end
  self.state='queued';self.progress=0;self.message='等待游戏更新后直接铺平台';return true
 end
 function j:start(options)return self:startAt(options)end
 function j:cancel()self.command=nil;self.state='cancelled';self.progress=0;self.message='已取消；已铺平台保留'end
 function j:tickInternal()
  if not self:busy()then return end
  local s=self.a:snapshot();assert(not s.menu and not s.multiplayer and not s.dead,'请在存活的单人世界内使用')
  if self.command then
   local o=self.command;self.command=nil
   assert(o.kind=='hellbridge'or o.kind=='arena'or o.kind=='hellshaft','平台类型无效')
   if o.kind=='hellshaft'then
    assert(integer(o.top,2,s.maxY-4)and integer(o.bottom,o.top+1,s.maxY-3),'竖井范围无效')
    assert(integer(o.x1,2,s.maxX-4)and o.x2==o.x1+2,'竖井宽度无效')
    self.x1=o.x1;self.x2=o.x2;self.top=o.top;self.bottom=o.bottom;self.layers=1;self.gap=0;self.stairs=false
   else
    assert(integer(o.length,0,8400)and (o.length==0 or o.length>=100),'平台长度无效')
    assert(integer(o.clearance,4,24),'净空高度无效')
    local layers=o.kind=='arena'and o.layers or 1;local gap=o.kind=='arena'and o.gap or 5
    assert(integer(layers,1,9)and integer(gap,5,40)and gap%5==0,'平台层数或间距无效')
    self.x1=o.x1 or (o.length==0 and 2 or math.max(2,s.playerFeet.x-o.length//2))
    self.x2=o.x2 or (o.length==0 and s.maxX-3 or math.min(s.maxX-3,s.playerFeet.x-o.length//2+o.length-1))
    self.bottom=o.bottom or s.playerFeet.y;self.top=self.bottom-(layers-1)*gap-o.clearance
    assert(self.top>=2 and self.bottom<=s.maxY-3 and self.x1<=self.x2,'平台超出世界上下边界')
    self.layers=layers;self.gap=gap;self.stairs=o.stairs==true
   end
   self.shaftRope=o.shaftRope~=false
   self.kind=o.kind;self.width=self.x2-self.x1+1;self.height=self.bottom-self.top+1
   self.total=self.kind=='hellshaft' and (self.width+(self.shaftRope and 2 or 0))*self.height or self.width*(self.height+self.layers*(self.stairs and 3 or 2))
   self.completed=0;self.index=0;self.phase='clear';self.worldKey=s.worldKey
   self.a:beginBuild();self.state='building';self.skipped=0
  end
  assert(s.worldKey==self.worldKey,'世界已切换，平台施工停止')
  for _=1,self.budget do
   local op
   if self.kind=='hellshaft'then
    if self.phase=='clear' and self.index>=self.width*self.height then self.phase=self.shaftRope and 'rope' or 'done';self.index=0 end
    if self.phase=='rope' and self.index>=self.height then self.phase='ropeFrame';self.index=0 end
    if self.phase=='done' or (self.phase=='ropeFrame' and self.index>=self.height) then
     self.state='done';self.progress=1;self.message=('地狱竖井完成：深%d格；保留特殊格%d'):format(self.height,self.skipped);return
    end
    local x=self.phase=='clear' and self.x1+self.index%self.width or self.x1+1
    local y=self.top+(self.phase=='clear'and self.index//self.width or self.index)
    op=self.phase=='clear'and {kind='clear',x=x,y=y,drain=true,keepWall=true,clearMode='platform'}
      or {kind=self.phase=='rope'and 'rope'or 'frame',x=x,y=y,tile=213}
   else
   if self.phase=='clear'then
    if self.index>=self.width*self.height then self.phase='platform';self.index=0 end
    if self.phase=='clear'then op={kind='clear',x=self.x1+self.index%self.width,y=self.top+self.index//self.width,drain=true,keepWall=true,clearMode='platform'}end
   end
   if self.phase=='platform'or self.phase=='frame'or self.phase=='stair'then
    if self.index>=self.width*self.layers then
     if self.phase=='platform'then self.phase='frame';self.index=0
     elseif self.phase=='frame' and self.stairs then self.phase='stair';self.index=0
     else self.state='done';self.progress=1;self.message=('平台完成：长%d格 / %d层；保留特殊格%d'):format(self.width,self.layers,self.skipped);return end
    end
    local x=self.x1+self.index%self.width;local y=self.bottom-(self.index//self.width)*self.gap
    -- Obsidian Platform: TileID 19, style 13. Verified in supplied ARM64
    -- Item.SetDefaults2(1457), case 0xF3046C -> 0xF2F6A8 writes createTile/placeStyle.
    op={kind=self.phase=='platform'and 'tile' or self.phase=='stair'and 'stair' or 'frame',x=x,y=y,tile=19,style=13}
   end
   end
   assert(self.a:execute(op),'平台施工接口失败')
   if self.phase=='clear'and self.a.blocked and self.a.blocked[op.x..','..op.y]then self.skipped=self.skipped+1 end
   self.index=self.index+1;self.completed=self.completed+1;self.progress=self.completed/self.total
  end
  self.message=('铺设平台 %d%% · 长%d格 / %d层'):format(math.floor(self.progress*100),self.width,self.layers)
 end
 function j:tick()local ok,e=pcall(self.tickInternal,self);if not ok then self.command=nil;self.state='error';self.message=tostring(e)end end
 return j
end
return M
