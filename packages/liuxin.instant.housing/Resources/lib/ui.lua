local R=require('templates.registry')
local P=require('planner')
local BPPreview=require('blueprint_preview')
local NumberInput=require('number_input')
local SelectionPad=require('selection_pad')
local SelectionView=require('selection_view')
local SlotRail=require('slot_rail')
local BP=require('blueprint')
local M={}
local colors={wood={159,112,67,255},leaf={77,164,81,255},stone={126,139,155,255},wall={68,79,91,255},glass={94,167,193,255},object={231,192,106,255},platform={179,145,89,255}}
function M.new(mod,controller)
 local u={mod=mod,c=controller,page=1,target='player',slotFirst=1,options={kind='prison',size=1,floors=1,rooms=1,theme=1,style=1,mirror=false,furniture=true,decor=true}}
 u.numbers=NumberInput.new();u.pad=SelectionPad.new();u.slotRail=SlotRail.new()
 local raw=mod.read_file and mod.read_file('settings.txt')
 if type(raw)=='string' then
  local kind,size,floors,rooms,theme,style,mirror,furn,decor,target=raw:match('^IH2,(%a+),(%d),(%d),(%d),(%d),(%d),([01]),([01]),([01]),(%a+)$')
  if not kind then
   kind,size,floors,rooms,theme,mirror,furn,decor,target=raw:match('^IH1,(%a+),(%d),(%d),(%d),(%d),([01]),([01]),([01]),(%a+)$')
   style='1'
  end
  if kind then
   local o={kind=kind,size=tonumber(size),floors=tonumber(floors),rooms=tonumber(rooms),theme=tonumber(theme),style=tonumber(style),mirror=mirror=='1',furniture=furn=='1',decor=decor=='1'}
   local t=R.get(o.kind)
   if t then o.floors=math.min(o.floors,t.maxFloors) end
   if t and P.build(o) and (target=='player' or target=='spawn') then u.options=o;u.target='player' end
  end
 end
 function u:layout() return {width=416,height=328} end
 function u:save()
  local o=self.options
  if mod.write_file then mod.write_file('settings.txt',table.concat({'IH2',o.kind,o.size,o.floors,o.rooms,o.theme,o.style,o.mirror and 1 or 0,o.furniture and 1 or 0,o.decor and 1 or 0,self.target},',')) end
 end
 function u:changed()
  self.preview=nil;self.runs=nil
  if self.c.state=='ready' or self.c.state=='queued' or self.c.state=='done' then self.c:cancel() end
  self:save()
 end
 function u:blueprint()
  if self.runs then return end
  local p=P.build(self.options);if not p then return end
  self.preview=p;self.runs={}
  local rows={}
  for _,v in ipairs(p.cells) do
   local color=v.tile and ((v.tile==19 and 'platform') or (v.tile==192 and 'leaf') or ((v.tile==30 or v.tile==191 or v.tile==321 or v.tile==311 or v.tile==124) and 'wood' or 'stone')) or (v.wall==21 and 'glass' or 'wall')
   if v.tile or v.wall then rows[v.y]=rows[v.y] or {};rows[v.y][v.x]=color end
  end
  for y,row in pairs(rows) do
   local first,last,prev
   for x=p.bounds.x1,p.bounds.x2+1 do
    local color=row[x]
    if color~=prev then
     if prev then self.runs[#self.runs+1]={x=first,y=y,w=last-first+1,color=colors[prev]} end
     first=x;prev=color
    end
    last=x
   end
  end
 end
 function u:draw()
  local g=mod.gui;local o=self.options;local c=self.c
  if not self.initialized then
   g.set_title('一键建造','建');g.set_width(416);g.set_pos(28,70)
   g.set_style{panel={33,43,102,245},title={50,60,130,255},button={63,80,150,255},hover={84,109,183,255},text={235,237,229,255}}
   if g.load_image then
    self.pixel=g.load_image('lib/ui/white.png')
    self.roundMask=g.load_image('lib/ui/round_mask.png')
    self.roundButtons={}
    for _,h in ipairs{19,23,25,26,27,28,29,30,32,34,36}do
     self.roundButtons[h]=g.load_image('lib/ui/button_'..h..'.png')
    end
    self.padImage=g.load_image('lib/ui/selection_pad.png')
    self.skinPanel=g.load_image('lib/ui/panel_skin.png')
    self.floatIcon=g.load_image('lib/ui/icon_float.png')
    if self.skinPanel and self.floatIcon and g.set_skin then
     g.set_skin(self.skinPanel,12,self.floatIcon,48,8)
    end
   end
   if g.set_collapsed then g.set_collapsed(true) end
   self.initialized=true
  end
  local function readable(value)return (tostring(value):gsub('^.-%.lua:%d+: ',''))end
  local function text(x,y,value,scale) g.text_at(x,y,readable(value),{235,237,229,255},scale) end
  local app=self.workbench
  local busy=c.state=='building' or c.state=='queued' or (app and app:busy())
  local function rounded(x,y,w,h,color,radius)
   if w<=0 or h<=0 then return end
   if self.roundMask and g.nine_slice then
    g.nine_slice(self.roundMask,x,y,w,h,31,color,math.min(radius or h/2,w/2,h/2))
   else g.rect(x,y,w,h,color)end
  end
  local function button(x,y,w,h,label,allow)
   local image=self.roundButtons and self.roundButtons[h]
   local hit
   if image and g.image_button then hit=g.image_button(image,x,y,w,h,label,math.floor(h/2))
   else hit=g.button_at(x,y,w,h,label)end
   return hit and allow~=false
  end
  local compact=self.page==5 or self.page==7
  g.set_width(compact and 320 or 416)
  if not compact then self.pad:reset()end
  if self.page~=4 then self.slotRail:reset()end
  if not compact then
   for i,label in ipairs{'房型','参数','建造','蓝图库'} do if button((i-1)*96,0,90,34,label) then self.page=i end end
  end
  if self.page==1 then
   text(0,43,'选择独立布局',0.8)
   for i,t in ipairs(R.list()) do
    local x=((i-1)%2)*196;local y=66+math.floor((i-1)/2)*42
    if button(x,y,188,36,(o.kind==t.id and '■ ' or '')..t.name,not busy) then
     o.kind=t.id;o.floors=math.min(o.floors,t.maxFloors);self:changed()
    end
   end
   local count=#R.list();local i=count+1
   if button(((i-1)%2)*196,66+math.floor((i-1)/2)*42,188,36,'平台建造')then self.page=6 end
   if button(0,236,384,29,'下一步：调整参数') then self.page=2 end
  elseif self.page==2 then
   local function cycle(y,label,k,n,names)
    text(0,y+7,label,0.72)
    local value=names and names[o[k]] or tostring(o[k])
    if button(150,y,234,29,value..'  >',not busy) then o[k]=o[k]%n+1;self:changed() end
   end
   if not R.get(o.kind).fixed then
   cycle(43,'尺寸','size',3,{'小型','中型','大型'})
   cycle(76,'层数','floors',R.get(o.kind).maxFloors)
   cycle(109,o.kind=='spawn' and '每翼每层房间' or '每层房间','rooms',3)
   end
   local fixed=R.get(o.kind).fixed
   if fixed then text(0,50,'简洁房型 · 尺寸固定，可镜像',0.68) end
   if o.kind=='prison' then
    cycle(85,'监狱样式','style',3,{'草木横屋','石砖悬屋','暗砖竖屋'})
   else cycle(fixed and 85 or 142,'主体材料','theme',2,{'木质主体','石砖主体'}) end
   local function toggle(x,y,w,label,k)
    if button(x,y,w,28,(o[k] and '[开] ' or '[关] ')..label,not busy) then o[k]=not o[k];self:changed() end
   end
   local ty=fixed and 124 or 178
   toggle(0,ty,122,'镜像','mirror');toggle(130,ty,122,'家具','furniture');toggle(260,ty,124,'装饰','decor')
   text(0,218,'定位：玩家脚下（底部中心）',0.75)
  elseif self.page==3 then
   self:blueprint()
   local p=self.preview
   if p then
    local b=p.bounds;local scale=math.min(376/(b.x2-b.x1+1),96/(b.y2-b.y1+1));local ox=192-(b.x1+b.x2+1)*scale/2;local oy=52-b.y1*scale
    text(0,41,R.get(o.kind).name..' · 布局示意',0.75)
    local function rect(x,y,w,h,color)
     if self.pixel and g.image then g.image(self.pixel,x,y,w,h,color) else g.rect(x,y,w,h,color) end
    end
    for _,r in ipairs(self.runs) do rect(ox+r.x*scale,oy+r.y*scale,r.w*scale,math.max(1,scale),r.color) end
    for _,v in ipairs(p.objects) do rect(ox+v.left*scale,oy+v.top*scale,v.w*scale,v.h*scale,colors.object) end
    text(0,154,('占地宽 %d 格 · 定位：%s'):format(b.x2-b.x1+1,self.target=='spawn' and '世界出生点' or '玩家脚下'),0.68)
    text(0,174,'树木直接清理；保留特殊物件、线路和液体',0.56)
   end
   if button(0,190,185,36,app and app.enabled and '建造（保留撤回点）' or '直接建造',not busy and not c.disabled) then if app and app.enabled then app:buildPlan(o,'player')else c:build(o,'player')end end
   if button(197,190,187,36,'撤回最近建筑',not busy and app and app:canUndo())then app:undoBuild()end
  elseif self.page==4 then
   if not app or not app.enabled then
    text(0,55,'蓝图库暂不可用',0.8)
    text(0,85,self.featureError or (app and app.message) or '请先进入单人世界',0.55)
   else
    local total=app:slotCount();local visible=math.min(5,total);local last=math.max(1,total-visible+1)
    self.slotFirst=math.max(1,math.min(last,self.slotFirst))
    if self.slotLastSelected~=app.slot then
     if app.slot<self.slotFirst then self.slotFirst=app.slot elseif app.slot>=self.slotFirst+visible then self.slotFirst=app.slot-visible+1 end
     self.slotLastSelected=app.slot
    end
    text(0,43,'槽位 '..app.slot..'/'..total..'  '..(app.sample and app.sample.name or '空'),0.66)
    for i=0,visible-1 do
     local slotNumber=self.slotFirst+i
     if slotNumber<=total and button(i*59,70,55,26,(app.slot==slotNumber and '■'..slotNumber or tostring(slotNumber)),not busy)then app:selectTo(slotNumber)end
    end
    if button(300,70,40,26,'+',not busy and app.enabled)then
     local slot=app:newSlot();if slot then self.slotFirst=math.max(1,slot-visible+1);self.slotLastSelected=slot;self.slotRail:reset()end
    end
    if button(344,70,40,26,'-',not busy and app.enabled)then
     local slot=app:deleteSlot();if slot then
      self.slotFirst=math.min(self.slotFirst,math.max(1,app:slotCount()-visible+1))
      self.slotLastSelected=slot;self.previewRunsRevision=nil;self.slotRail:reset()
     end
    end
    local rail={x=0,y=106,w=384,h=10}
    if app.selectionInput and g.get_pos then
     local ok,now,cursors,view=pcall(app.selectionInput.sample,app.selectionInput)
     if ok and view then
      local wx,wy=g.get_pos();local ox,oy=SelectionView.origin(view,wx,wy)
      self.slotFirst=self.slotRail:update(now,cursors,{x=ox+rail.x,y=oy+rail.y,w=rail.w,h=rail.h},total,visible,self.slotFirst,not busy,view.frame)
     else self.slotRail:reset()end
    else self.slotRail:reset()end
    rounded(rail.x,rail.y,rail.w,rail.h,{35,46,104,255})
    local thumb=math.min(rail.w,math.max(38,rail.w*visible/total))
    rounded(rail.x+(self.slotFirst-1)*(rail.w-thumb)/math.max(1,last-1),rail.y,thumb,rail.h,{119,163,236,255})
    local function paint(x,y,w,h,color)
     if self.pixel and g.image then g.image(self.pixel,x,y,w,h,color)else g.rect(x,y,w,h,color)end
    end
    rounded(0,126,156,84,{105,132,207,255},10)
    rounded(1,127,154,82,{28,37,87,255},9)
    if app.sample then
     if self.previewRunsRevision~=app.revision then
      self.previewRunsRevision=app.revision;self.previewRuns=BPPreview.schematic(app.sample)
     end
     local image=self.previewRuns;local scale=math.min(148/image.width,76/image.height)
     local ox=(156-image.width*scale)/2;local oy=126+(84-image.height*scale)/2
     for _,run in ipairs(image.runs)do
      local x=app.pasteMirror and image.width-run.x-run.w or run.x
      paint(ox+x*scale,oy+run.y*scale,math.max(1,run.w*scale),math.max(1,scale),run.color)
     end
    else text(30,160,'空槽位',0.65) end
    for i,item in ipairs{{'blocks','方块'},{'walls','背景墙'},{'wires','线路'},{'liquid','液体'}}do
     if button(168,126+(i-1)*21,216,19,(app.pasteOptions[item[1]] and '[粘贴] 'or '[跳过] ')..item[2],not busy)then app:togglePasteOption(item[1])end
    end
    if button(168,212,216,19,(app.pasteMirror and '[开启] 'or '[关闭] ')..'左右镜像',not busy)then app:togglePasteMirror()end
    if app.draft then
     text(0,237,'复制完成，保存失败',0.52)
     if button(238,234,146,23,'重试保存',not busy)then app:saveDraft()end
    elseif app.sample then
     text(0,237,('%d×%d 格 · 跳过 %d 格'):format(app.sample.width,app.sample.height,app.sample.omitted or 0),0.52)
    end
    if button(0,260,122,30,'粘贴建筑',not busy and app:canPaste())then app:paste()end
    if button(130,260,122,30,'框选复制',not busy)then if app:openSelection()then self.page=5 end end
    if button(260,260,124,30,'撤回',not busy and app:canUndo())then app:undoBuild()end
   end
  elseif self.page==6 and app then
   local opt=app.platformOptions
   if button(0,43,122,30,(opt.kind=='hellbridge'and '■ 'or '')..'地狱长桥',not busy)then opt.kind='hellbridge';app.message='站在要铺设的高度；沿脚下向两侧生成'end
   if button(131,43,122,30,(opt.kind=='arena'and '■ 'or '')..'战斗平台',not busy)then opt.kind='arena';app.message='最底层位于脚下，其他层向上排列'end
   if button(262,43,122,30,(opt.kind=='hellshaft'and '■ 'or '')..'地狱直通车',not busy)then opt.kind='hellshaft';app.message='脚下开凿三格竖井，可选生成锁链；不可撤回'end
   local function cycle(y,label,k,values,names)
    text(0,y+5,label,0.66)
    local index=1;for i,v in ipairs(values)do if opt[k]==v then index=i end end
    if button(150,y,234,25,(names and names[index]or tostring(opt[k]))..'  >',not busy)then opt[k]=values[index%#values+1]end
   end
   if opt.kind=='hellbridge'then
    cycle(82,'平台长度','bridgeLength',{1000,2000,4000,0},{'1000 格','2000 格','4000 格','横贯世界'})
    text(0,120,'黑曜石平台 · 不怕岩浆 · 单层',0.64)
    text(0,154,'强制清除地形、家具、线路与通道液体',0.55)
   elseif opt.kind=='arena'then
    cycle(82,'每层长度','arenaLength',{200,400,800},{'200 格','400 格','800 格'})
    cycle(116,'平台层数','layers',{1,2,3,4,5,6,7,8,9})
    cycle(150,'层间距','gap',{5,10,15,20,25,30,35,40})
   else
    text(0,92,'脚下垂直开凿三格通道，可选中央绳索',0.62)
    text(0,130,'终点在世界底部上方约 180 格；不可撤回',0.58)
    text(0,166,'强制清理方块、家具、线路和液体',0.58)
   end
   if opt.kind=='hellshaft'then
    if button(0,216,384,23,(opt.shaftRope~=false and '[开启] 'or '[关闭] ')..'生成锁链（中央绳索）',not busy)then opt.shaftRope=opt.shaftRope==false end
   end
   if opt.kind~='hellshaft'then
    cycle(184,'顶部净空','clearance',{6,8,12,16},{'6 格','8 格','12 格','16 格'})
    if button(0,216,384,23,(opt.stairs and '[开启] 'or '[关闭] ')..'楼梯状平台（防卡脚）',not busy)then opt.stairs=not opt.stairs end
   end
   if button(0,248,185,27,opt.kind=='hellshaft'and '开凿直通车（不可撤回）'or(app:platformCanUndo()and '铺设平台（可撤回）'or'铺设平台（不可撤回）'),not busy)then app:buildPlatform()end
   if button(197,248,187,27,'撤回最近建筑',not busy and app:canUndo())then app:undoBuild()end
  elseif (self.page==5 or self.page==7)and app then
   local sel=app.selection
   if button(0,0,138,28,'返回图库',not busy)then
    self.page=4;self.pad:reset();self.numbers:cancel()
    g.set_content_height(28);return
   end
   if button(148,0,140,28,'定位脚下',not busy)then app:openSelection();self.pad:reset()end
   if app.overlay then app.overlay:draw(g,self.pixel,320,self.page==5 and 435 or 310)end
   local sizeValues=app:sizeValues()
   if self.page==7 and self.numbers.active then
    self.pad:reset()
    local n=self.numbers
    text(0,37,(n.keyName==1 and '建筑宽度'or '建筑高度')..'（格）',0.65)
    text(0,60,n.buffer==''and '_'or n.buffer,0.9)
    local keys={'1','2','3','4','5','6','7','8','9','清空','0','退格'}
    for i,key in ipairs(keys)do
     if button(((i-1)%3)*98,90+((i-1)//3)*32,90,29,key,not busy)then n:key(key)end
    end
    if button(0,224,138,29,'取消输入',not busy)then n:cancel();self.page=5 end
    if button(148,224,140,29,'确定',not busy)then
     if n.buffer~=''then app:applyDimension(n.keyName,n.buffer);n:cancel();self.page=5
     else app.message='请输入数值'end
    end
   else
    for index,label in ipairs{'宽','高'}do
     local x=(index-1)*148
     text(x+50,30,label,0.45)
     if button(x,40,34,32,'-',not busy)then app:changeSize(index==1 and -1 or 0,index==2 and -1 or 0)end
     if button(x+38,40,64,32,sizeValues[index],not busy)then self.numbers:open(index,sizeValues[index]);self.page=7;self.pad:reset()end
     if button(x+106,40,34,32,'+',not busy)then app:changeSize(index==1 and 1 or 0,index==2 and 1 or 0)end
    end
    local box={x=0,y=88,w=136,h=136}
    if self.page==5 and app.selectionInput then
     local ok,now,cursors,view=pcall(app.selectionInput.sample,app.selectionInput)
     if ok and view and g.get_pos then
      local wx,wy=g.get_pos();local ox,oy=SelectionView.origin(view,wx,wy)
      local screenBox={x=ox+box.x,y=oy+box.y,w=box.w,h=box.h}
      local dx,dy=self.pad:update(now,cursors,screenBox,not busy and sel.visible,view.frame)
      if dx~=0 or dy~=0 then sel:moveWithin(dx,dy,app.adapter.current)end
     else
      self.pad:reset()
      if not ok then app.inputError=tostring(now)end
     end
    else self.pad:reset()end
    local frames={up=1,right=2,down=3,left=4}
    if self.padImage and g.image then
     g.image(self.padImage,box.x,box.y,box.w,box.h,{255,255,255,255},{0,(frames[self.pad.direction]or 0)*180,180,180})
    end
    if button(148,91,140,32,'清理区域',app:canClearSelection())then self.pad:reset();app:clearSelection()end
    if button(148,133,140,32,sel.visible and '隐藏选框'or '显示选框',not busy)then
     self.pad:reset();if sel.visible then sel.visible=false else app:showSelection()end
    end
    if button(148,175,140,32,'重置尺寸',not busy)then
     app:applyDimension(1,'32');app:applyDimension(2,'20');self.pad:reset()
    end
    if button(148,217,140,32,'撤回清理/建造',not busy and app:canUndo())then app:undoBuild()end
    text(7,249,app.inputError and '触摸接口不可用'or '轻点微调 · 长按加速',0.49)
    if busy then
     if button(0,272,288,32,'取消当前任务')then self.pad:reset();c:cancel();app:cancel()end
    elseif button(0,272,288,32,'复制并保存 · 槽位 '..app.slot,sel.visible)then self.pad:reset();app:copy()end
   end
   if self.page==5 then
    text(0,315,'清理选区（独立选择）',0.57)
    local clear={{'blocks','物块/家具'},{'walls','背景墙'},{'wires','电线'},{'liquid','液体'}}
    for i,item in ipairs(clear)do
     local x=((i-1)%2)*148;local y=333+((i-1)//2)*34
     local on=app.clearOptions[item[1]]
     if button(x,y,140,30,(on and '清理 'or '保留 ')..item[2],not busy)then app:toggleClearOption(item[1])end
    end
   end
   if self.page==7 then
    text(0,264,'宽1–'..BP.MAX_W..'格 · 高1–'..BP.MAX_H..'格',0.52)
   else
    local msg=readable(app.message);local cut=utf8.offset(msg,26)
    text(0,411,cut and msg:sub(1,cut-1)or msg,0.49)
   end
   g.set_content_height(self.page==5 and 435 or 310)
   return
  end

  local footerY=(self.page==4 or self.page==6)and 299 or self.page==1 and 281 or 243
  rounded(0,footerY,384,6,{35,46,104,255})
  local barProgress=c.progress or 0
  if app and app.activeWork then barProgress=app:progress() end
  barProgress=math.max(0,math.min(1,barProgress))
  rounded(0,footerY,384*barProgress,6,{119,163,236,255})
  local message=readable((self.page>=4 and app and app.message) or c.message)
  local cut=utf8.offset(message,43)
  local first=cut and message:sub(1,cut-1) or message
  text(0,footerY+10,first,0.58)
  if button(0,footerY+36,185,29,'取消施工',not c.disabled) then c:cancel();if app then app:cancel()end end
  if button(197,footerY+36,187,29,'收起窗口') then g.set_collapsed(true) end
  text(0,footerY+68,'单人 · 取消后保留已建部分',0.55)
  g.set_content_height(footerY+85)
 end
 function u:close()
  self.pad:reset();self.slotRail:reset()
  if mod.gui.release_image then
   for _,id in pairs(self.roundButtons or {})do mod.gui.release_image(id)end
   self.roundButtons=nil
   for _,key in ipairs{'roundMask','skinPanel','floatIcon'}do
    if self[key]then mod.gui.release_image(self[key]);self[key]=nil end
   end
  end
  if self.padImage and mod.gui.release_image then mod.gui.release_image(self.padImage);self.padImage=nil end
  if self.previewImage and mod.gui.release_image then mod.gui.release_image(self.previewImage);self.previewImage=nil end
  if self.pixel and mod.gui.release_image then mod.gui.release_image(self.pixel);self.pixel=nil end end
 return u
end
return M
