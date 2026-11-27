-- Stream a selected rectangle after its exact undo snapshot is saved.
local M={}
local clock=os and os.clock
local SLICE=0.007
function M.new(adapter)
 local j={a=adapter,state='idle',progress=0,message='等待清理区域',budget=160}
 function j:busy()return self.state=='queued' or self.state=='building'end
 function j:start(rect,options)
  if self:busy()then return false end
  self.rect={x=rect.x,y=rect.y,width=rect.width,height=rect.height,worldKey=rect.worldKey}
  self.options={blocks=options.blocks,walls=options.walls,wires=options.wires,liquid=options.liquid}
  self.index=0;self.skipped=0;self.progress=0;self.state='queued';self.message='等待游戏更新后清理';return true
 end
 function j:cancel()
  self.state='cancelled';self.message='清理已取消；已清理部分可撤回'
 end
 function j:tickInternal()
  if not self:busy()then return end
  local s=self.a:snapshot();assert(not s.menu and not s.multiplayer and not s.dead and s.worldKey==self.rect.worldKey,'世界状态已变化，清理停止')
  local r=self.rect
  assert(r.x>=1 and r.y>=1 and r.x+r.width<s.maxX and r.y+r.height<s.maxY,'选区超出世界边界')
  if self.state=='queued'then self.a:beginBuild();self.state='building'end
  local total=r.width*r.height
  local dl=clock and (clock()+SLICE) or 0
  for _=1,self.budget do
   if clock and clock()>dl then break end
   if self.index>=total then break end
   local x=r.x+self.index%r.width;local y=r.y+self.index//r.width
   assert(self.a:execute{kind='clear',clearMode='selection',x=x,y=y,options=self.options},'区域清理接口失败')
   if self.a.blocked and self.a.blocked[x..','..y]then self.skipped=self.skipped+1 end
   self.index=self.index+1
  end
  self.progress=self.index/total
  if self.index>=total then self.state='done';self.message=('区域清理完成；保留特殊格%d，可撤回'):format(self.skipped)
  else self.message=('清理区域 %d%%'):format(math.floor(self.progress*100))end
 end
 function j:tick()local ok,e=pcall(self.tickInternal,self);if not ok then self.state='error';self.message=tostring(e)..'；已清理部分可撤回'end end
 return j
end
return M
