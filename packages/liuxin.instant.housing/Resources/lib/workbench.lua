local Selection=require('selection')
local Store=require('blueprint_store')
local Job=require('blueprint_job')
local Preview=require('blueprint_preview')
local Platform=require('platform_job')
local RegionClear=require('region_clear')
local Planner=require('planner')
local Layers=require('paste_layers')
local Mirror=require('blueprint_mirror')
local M={}
function M.new(mod,adapter,builder)
 local a={mod=mod,adapter=adapter,builder=builder,selection=Selection.new(),store=Store.new(mod),job=Job.new(adapter),slot=1,revision=0,message='框选建筑，保存后可在脚下生成'}
 a.pasteOptions=Layers.normalize();a.pasteMirror=false
 a.undoSnapshot=nil;a.pendingBuild=nil;a.undoInProgress=false;a.buildKind=nil;a.copyAtPlayerRequested=false
 a.platformJob=Platform.new(adapter)
 a.regionJob=RegionClear.new(adapter)
 a.clearOptions={blocks=true,walls=false,wires=false,liquid=false}
 -- The manager writes declared settings to the mod's private config.json.
 -- Read only these four known booleans; malformed config keeps safe defaults.
 if type(mod.read_file)=='function'then
  local ok,raw=pcall(mod.read_file,'config.json')
  if ok and type(raw)=='string' and #raw<=65536 then
   local values=raw:match('"values"%s*:%s*{(.-)}')
   if values then for key in pairs(a.clearOptions)do
    local setting='clear'..key:sub(1,1):upper()..key:sub(2)
    local token=values:match('"'..setting..'"%s*:%s*(%a+)')
    if token=='true'or token=='false'then a.clearOptions[key]=token=='true'end
   end end
  end
 end
 a.platformOptions={kind='hellbridge',bridgeLength=2000,arenaLength=200,layers=3,gap=5,clearance=8,stairs=false,shaftRope=true}
 a.traceLines={}
 -- v2.0.0 正式版：诊断日志只留在内存，不写盘。
 function a:trace(message)
  self.traceLines[#self.traceLines+1]=tostring(message)
  if #self.traceLines>24 then table.remove(self.traceLines,1)end
 end
 a.selection.trace=function(message)a:trace(message)end
 local ok,e=pcall(function()adapter:enableBlueprints()end)
 a.enabled=ok;if not ok then a.message='复制功能不可用：'..tostring(e)end
 if ok then
  local good,result=pcall(function()return adapter:enableOverlay(a.selection,function(err)a.overlayError=err;a.message='选区绘制停止：'..err;a:trace(a.message) end)end)
  if good then a.overlay=result else a.overlayError=tostring(result);a:trace('选区初始化失败：'..a.overlayError)end
 end
 if adapter.enableSelectionInput then
  local good,value=pcall(function()return adapter:enableSelectionInput()end)
  if good then a.selectionInput=value else a.inputError=tostring(value);a:trace('圆盘触摸不可用：'..a.inputError)end
 end
 function a:busy()return self.job:busy() or self.platformJob:busy() or self.regionJob:busy() or self.builder.state=='queued' or self.builder.state=='building'end
 function a:progress()
  if self.activeWork=='build'then
   if self.buildKind=='clearRegion'then
    if self.pendingBuild then return 0.2*self.job.progress end
    return 0.2+0.8*self.regionJob.progress
   end
   if self.buildKind=='blueprint'then
    if self.pendingBuild then return 0.2*self.job.progress end
    return 0.2+0.8*self.job.progress
   end
   if self.pendingBuild then return 0.2*self.job.progress end
   local progress
   if self.buildKind=='platform'then
    local state=self.platformJob.state
    if state=='queued'or state=='building'or state=='done'then progress=self.platformJob.progress end
   else
    local state=self.builder.state
    if state=='queued'or state=='building'or state=='done'then progress=self.builder.progress end
   end
   if progress then return 0.2+0.8*progress end
   return 0.2*self.job.progress
  end
  if self.activeWork=='platform'then return self.platformJob.progress end
  return self.job.progress
 end
 function a:buildPlatform()
  if self:busy()then return false end
  local o=self.platformOptions;local snap=self.adapter:snapshot()
  if o.kind=='hellshaft' then
   local top=math.max(2,snap.playerFeet.y);local bottom=snap.maxY-180
   if bottom<=top or snap.playerFeet.x<3 or snap.playerFeet.x>snap.maxX-4 then self.message='当前位置无法向地狱开凿竖井';return false end
   self.undoSnapshot=nil;self.undoInProgress=false;self.activeWork='platform';self.buildKind='platform';self.selection.visible=false
   self.message='地狱直通车为长竖井，本次不可撤回'
   return self.platformJob:start{kind='hellshaft',x1=snap.playerFeet.x-1,x2=snap.playerFeet.x+1,top=top,bottom=bottom,shaftRope=o.shaftRope~=false}
  end
  local length=o.kind=='hellbridge'and o.bridgeLength or o.arenaLength
  local layers=o.kind=='arena'and o.layers or 1;local gap=o.kind=='arena'and o.gap or 6
  local x1=length==0 and 2 or math.max(2,snap.playerFeet.x-length//2)
  local x2=length==0 and snap.maxX-3 or math.min(snap.maxX-3,snap.playerFeet.x-length//2+length-1)
  local bottom=snap.playerFeet.y;local top=bottom-(layers-1)*gap-o.clearance
  local options={kind=o.kind,length=length,layers=layers,gap=gap,clearance=o.clearance,stairs=o.stairs,x1=x1,x2=x2,bottom=bottom}
  local width,height=x2-x1+1,bottom-top+1
  self.centerRequested=false;self.selection.visible=false
  if width<=require('blueprint').MAX_W and height<=require('blueprint').MAX_H then
   return self:beginUndoable({kind='platform',options=options,worldKey=snap.worldKey},{x=x1,y=top,width=width,height=height,worldKey=snap.worldKey})
  end
  self.undoSnapshot=nil;self.undoInProgress=false;self.activeWork='platform'
  self.buildKind='platform'
  self.message='平台超过撤回范围，本次直接施工且不能撤回'
  self:trace('平台超出撤回范围，直接施工：'..o.kind)
  return self.platformJob:start(options)
 end
 function a:load(slot)
  self.slot=slot;self.sample=self.store:load(slot);self.revision=self.revision+1;self.samplePath=nil
  if self.sample then
   local path='blueprints/preview'..slot..'.png'
   if self.mod.write_file(path,Preview.png(self.sample)) then self.samplePath=path end
  end
 end
 function a:slotCount()return self.store:count()end
 function a:newSlot()
  if not self.enabled or self:busy()then return nil end
  local slot,why=self.store:create()
  if not slot then self.message=why;return nil end
  self:load(slot);self.message='已新建空槽位 '..slot;return slot
 end
 function a:deleteSlot()
  if not self.enabled or self:busy()then return nil end
  local removed=self.slot
  local slot,why=self.store:delete(removed)
  if not slot then self.message=why;return nil end
  if self.draftSlot==removed then self.draft=nil;self.draftSlot=nil
  elseif self.draftSlot and self.draftSlot>removed then self.draftSlot=self.draftSlot-1 end
  self:load(slot);self.message=why or '已删除当前槽位';return slot
 end
 function a:select(delta)if not self:busy()then self:load((self.slot-1+delta)%self:slotCount()+1)end end
 function a:selectTo(slot)
  if self:busy()or type(slot)~='number'or slot%1~=0 or slot<1 or slot>self:slotCount() then return false end
  self:load(slot);return true
 end
 function a:openSelection()
  if not self.enabled or self:busy()then return false end
  if self.overlayError then
   self.message='边框不可绘制；仍可按坐标框选复制'
   self:trace('选区边框不可用，继续启用坐标选区：'..self.overlayError)
  end
  self:trace('选区定位请求');self.centerRequested=true;return true
 end
 function a:showSelection()
  if self:busy()then return false end
  local snap=self.adapter.current
  if snap and self.selection:show(snap.worldKey)then return true end
  return self:openSelection()
 end
 function a:applySize(values)
  if self:busy()then return false end
  self.activeWork='idle';self.sizeRequested={table.unpack(values)};return true
 end
 function a:sizeValues()return self.sizeRequested or {tostring(self.selection.width),tostring(self.selection.height)}end
 function a:changeSize(dw,dh)
  local B=require('blueprint');local v=self:sizeValues();return self:applySize{tostring(math.max(1,math.min(B.MAX_W,tonumber(v[1])+dw))),tostring(math.max(1,math.min(B.MAX_H,tonumber(v[2])+dh)))}
 end
 function a:applyDimension(index,value)
  local n=tonumber(value);local B=require('blueprint');local max=index==1 and B.MAX_W or B.MAX_H
  if not n or n%1~=0 or n<1 or n>max then self.message='尺寸超出范围';return false end
  local v=self:sizeValues();return self:applySize{index==1 and tostring(n)or v[1],index==2 and tostring(n)or v[2]}
 end
 function a:togglePasteOption(key)if self:busy()or self.pasteOptions[key]==nil then return false end;self.pasteOptions[key]=not self.pasteOptions[key];return true end
 function a:togglePasteMirror()if self:busy()then return false end;self.pasteMirror=not self.pasteMirror;return true end
 function a:canPaste()return self.enabled and not self:busy()and self.sample~=nil and Layers.any(self.pasteOptions)end
 function a:platformCanUndo()
  local o=self.platformOptions;if o.kind=='hellshaft'then return false end
  local length=o.kind=='hellbridge'and o.bridgeLength or o.arenaLength
  local height=(o.kind=='arena'and(o.layers-1)*o.gap or 0)+o.clearance+1
  local B=require('blueprint');return length>0 and length<=B.MAX_W and height<=B.MAX_H
 end
 function a:toggleClearOption(key)
  if self:busy()or self.clearOptions[key]==nil then return false end
  self.clearOptions[key]=not self.clearOptions[key];return true
 end
 function a:canClearSelection()return self.enabled and self.selection.visible and not self:busy()and Layers.any(self.clearOptions)end
 function a:clearSelection()
  if not self:canClearSelection()then self.message='请显示选区并至少选择一种清理内容';return false end
  local snap=self.adapter:snapshot()
  if snap.menu or snap.multiplayer or snap.dead or not self.selection:bounds(snap)then self.message='选区超出世界边界或当前世界不可用';return false end
  local r=self.selection:rect();local options={}
  for k,v in pairs(self.clearOptions)do options[k]=v end
  return self:beginUndoable({kind='clearRegion',options=options,rect=r},r)
 end
 function a:copy()
  if self:busy()then self.message='当前任务结束后再复制';return false end
  if not self.enabled then self.message='复制功能未初始化，请查看运行日志';return false end
  if not self.selection.visible then self.message='请先显示选区，再复制建筑';return false end
  self.captureSlot=self.slot;self.handled=false
  self.activeWork='blueprint'
  local name='样本'..self.slot..' '..self.selection.width..'×'..self.selection.height
  local queued=self.job:capture(self.selection:rect(),name)
  if queued then self:trace(('复制请求：槽位%d，选区%d×%d'):format(self.slot,self.selection.width,self.selection.height))
  else self.message='复制任务未能排队，请稍后重试'end
  return queued
 end
 function a:copyAtPlayer()
  if not self.enabled or self:busy()then return false end
  self.copyAtPlayerRequested=true
  self.message='正在定位脚下选区'
  return true
 end
 function a:paste()
  if not self:canPaste()then return false end
  local bp=self.sample
  if self.pasteMirror then
   local ok,result=pcall(Mirror.flip,bp,self.adapter)
   if not ok then self.message='镜像失败：'..tostring(result);return false end
   bp=result
  end
  local s=self.adapter:snapshot();local x=s.playerFeet.x-bp.anchorX;local y=s.playerFeet.y-bp.anchorY
  return self:beginUndoable({kind='blueprint',bp=bp,x=x,y=y,worldKey=s.worldKey,options=Layers.normalize(self.pasteOptions)},{x=x,y=y,width=bp.width,height=bp.height,worldKey=s.worldKey})
 end
 function a:beginUndoable(action,rect)
  if self:busy()then return false end
  action.worldKey=rect.worldKey;self.pendingBuild=action;self.activeWork='build';self.selection.visible=action.kind=='clearRegion';self.directPaste=false
  self.buildKind=action.kind
  local ok=self.job:capture(rect,'施工前撤回点',true)
  if not ok then self.pendingBuild=nil;self.activeWork='idle';return false end
  self.message='先保存施工前区域，完成后可撤回';return true
 end
 function a:buildPlan(options,target)
  if not self.enabled or self:busy()then return false end
  local plan,why=Planner.build(options);if not plan then self.message=why;return false end
  local snap=self.adapter:snapshot();local anchor=target=='spawn' and snap.spawn or snap.playerFeet
  local b=plan.bounds;local x=anchor.x+b.x1;local y=anchor.y+b.y1
  -- Snapshot the complete generated footprint, including underground structures.
  local rect={x=x,y=y,width=b.x2-b.x1+1,height=b.y2-b.y1+1,worldKey=snap.worldKey}
  if x<1 or y<1 or x+rect.width>=snap.maxX or y+rect.height>=snap.maxY then self.message='建筑超出世界边界';return false end
  return self:beginUndoable({kind='generated',options=options,anchor=anchor},rect)
 end
 function a:canUndo()
  return self.undoSnapshot~=nil and not self:busy() and not self.undoInProgress
 end
 function a:undoBuild()
  if not self:canUndo()then return false end
  local u=self.undoSnapshot;local s=self.adapter:snapshot()
  if s.worldKey~=u.worldKey then self.message='撤回点来自另一个世界';return false end
  self.undoInProgress=true;self.activeWork='undo'
  if not self.job:pasteAt(u.bp,u.x,u.y,u.worldKey,true)then self.undoInProgress=false;return false end
  self.message='撤回最近一次建筑';return true
 end
 function a:saveDraft()
  if self:busy() or not self.draft then return false end
  local slot,why=self.store:save(self.draft,self.draftSlot)
  if not slot then self.message=why;return false end
  self.draft=nil;self.draftSlot=nil;self:load(slot);self.message='已重新保存槽位 '..slot;return true
 end
 function a:cancel()self.sizeRequested=nil;self.centerRequested=false;self.copyAtPlayerRequested=false;self.pendingBuild=nil;self.undoInProgress=false;self.directPaste=false;self.job:cancel();self.platformJob:cancel();self.regionJob:cancel();self.activeWork='idle';self.message=self.regionJob.message end
 function a:tick()
  if self.sizeRequested then
   local values=self.sizeRequested;self.sizeRequested=nil
   local good,snap=pcall(function()return self.adapter:snapshot()end)
   if good and not snap.menu and not snap.multiplayer and not snap.dead then
    local ok,why=self.selection:setSize(values[1],values[2],snap)
    self.message=ok and '尺寸已应用，底部中心保持不变' or why
   else self.message='请进入存活的单人世界后调整选区'end
  end
  if self.copyAtPlayerRequested then
   self.copyAtPlayerRequested=false
   local good,snap=pcall(function()return self.adapter:snapshot()end)
   if good and not snap.menu and not snap.multiplayer and not snap.dead then
    self.selection:place(snap.playerFeet,snap.worldKey)
    self.selection.renderLogged=false
    self:trace(('脚下复制：%d×%d 格'):format(self.selection.width,self.selection.height))
    self:copy()
   else self.message='请进入存活的单人世界后复制' end
  end
  if self.centerRequested then
   self.centerRequested=false
   local good,snap=pcall(function()return self.adapter:snapshot()end)
   if good and not snap.menu and not snap.multiplayer and not snap.dead then self.selection:place(snap.playerFeet,snap.worldKey);self.selection.renderLogged=false;self:trace('选区定位完成');self.message='绿色框为复制范围；圆盘移动，输入宽高'
   else self.message='请进入存活的单人世界后框选' end
  end
  if self.selection.visible and not self.job:busy()then
   local good,s=pcall(function()return self.adapter:snapshot()end)
   if not good or s.menu or s.multiplayer or s.dead or s.worldKey~=self.selection.worldKey then self.selection.visible=false end
  end
  if self.job:busy()then
   self.job:tick();self.message=(self.directPaste and '不可撤回 · 'or '')..self.job.message
   local r=self.job.rect
   if self.activeWork=='blueprint' and r and (self.job.state=='capturing' or (self.job.state=='done' and self.job.result)) and self.selection.worldKey==r.worldKey and
    (self.selection.x~=r.x or self.selection.y~=r.y or self.selection.width~=r.width or self.selection.height~=r.height) then
    self.selection.x=r.x;self.selection.y=r.y;self.selection.width=r.width;self.selection.height=r.height
    self.selection.visible=true;self.selection.renderLogged=false
    self:trace(('复制选区自动扩展至 %d×%d 格'):format(r.width,r.height))
   end
  end
  if self.regionJob:busy()then self.regionJob:tick();self.message=self.regionJob.message end
  if self.platformJob:busy()then self.platformJob:tick();self.message=(self.undoSnapshot and ''or '不可撤回 · ')..self.platformJob.message end
  local stage=self.job.state..':'..self.platformJob.state..':'..tostring(self.platformJob.phase)
  if stage~=self.lastStage then self.lastStage=stage;self:trace(stage..' '..self.message)end
  if self.job.state=='done' and self.pendingBuild then
   local pending=self.pendingBuild;self.pendingBuild=nil
   self.undoSnapshot={bp=self.job.result,x=self.job.rect.x,y=self.job.rect.y,worldKey=pending.worldKey}
   if pending.kind=='blueprint' then
    assert(self.job:pasteAt(pending.bp,pending.x,pending.y,pending.worldKey,false,pending.options),'建筑任务无法启动')
   elseif pending.kind=='clearRegion' then
    assert(self.regionJob:start(pending.rect,pending.options),'区域清理任务无法启动')
   elseif pending.kind=='platform' then
    self.activeWork='platform'
    assert(self.platformJob:startAt(pending.options),'平台任务无法启动')
   else
    assert(self.builder.buildAt,'当前建造器不支持固定坐标施工')
    self.builder:buildAt(pending.options,pending.anchor)
   end
   self.message='撤回点已保存，开始建造'
  elseif self.job.state=='error' and self.pendingBuild then
   local pending=self.pendingBuild;self.pendingBuild=nil
   if pending.kind=='blueprint' then
    local ok,s=pcall(function()return self.adapter:snapshot()end)
    if ok and not s.menu and not s.multiplayer and not s.dead and s.worldKey==pending.worldKey then
     self.undoSnapshot=nil;self.activeWork='build';self.buildKind='blueprint';self.directPaste=true
     if self.job:pasteAt(pending.bp,pending.x,pending.y,pending.worldKey,false,pending.options)then
      self.message='撤回点超出范围，直接粘贴；本次不可撤回'
     else self.activeWork='idle';self.directPaste=false;self.message='撤回点保存失败，粘贴也未能启动'end
    else self.activeWork='idle';self.message='世界状态已变化，粘贴已停止'end
   else
    self.activeWork='idle'
    if pending.kind=='clearRegion' then self.selection.visible=true;self.message='无法保存撤回点，区域未清理：'..self.job.message end
   end
  elseif self.job.state=='error' and self.undoInProgress then
   self.undoInProgress=false
  elseif self.job.state=='done' and self.undoInProgress then
   self.undoSnapshot=nil;self.undoInProgress=false;self.message='已撤回最近一次建筑'
  elseif self.job.state=='done' and self.job.result and self.activeWork=='blueprint' and not self.handled then
   self.handled=true;local slot,why=self.store:save(self.job.result,self.captureSlot)
   if slot then self:load(slot);self.draft=nil;self.draftSlot=nil;self.message='槽'..slot..'；'..(self.job.omitSummary or ('跳过'..(self.sample.omitted or 0)..'格'))
   else self.message=why;self.draft=self.job.result;self.draftSlot=self.captureSlot end
  end
  if self.activeWork=='build' then
   if self.buildKind=='clearRegion' and not self.pendingBuild and self.regionJob.state~='idle' then self.message=self.regionJob.message
   elseif self.directPaste and self.job.state=='done' then self.message='粘贴完成；本次不可撤回'
   elseif self.directPaste then self.message='不可撤回 · '..self.job.message
   elseif self.builder.state=='building' then self.message=self.builder.message
   elseif self.builder.state=='done' then self.message='建筑完成，可撤回最近一次施工'
   elseif self.builder.state=='error' then self.message='建造中止；仍可撤回已完成部分：'..self.builder.message end
  end
  if self.overlay and self.overlay.updateView then self.overlay:updateView()end
 end
 function a:close()self:cancel();self.selection.visible=false;if self.overlay then self.overlay:close()end end
 a:load(1)
 return a
end
return M
