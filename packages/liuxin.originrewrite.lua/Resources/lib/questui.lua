-- Ivory parchment quest panel. Draw only queues actions; Main.Update executes them.
local U={};U.__index=U
local titles={any='异化清剿',tier='灾变猎手',styles='风格追猎',nohit='无伤挑战',extreme='极限挑战'}
local ink={62,43,27,255};local teal={24,107,117,255};local muted={126,106,76,255}
function U.new(r,g)return setmetatable({r=r,g=g,tab=1,index=1,page=1,rewardPage=1,dark=mod and mod.read_file and mod.read_file('quest_ui_theme.txt')=='dark' or false,ready=false},U)end
function U:queue(kind,index,offer)
 if self.pending or(self.cooldown or 0)>0 then return end
 self.pending={kind=kind,index=index,offer=offer,world=self.r.world,session=self.r.session,key=self.r.contract.key}
end
function U:update()
 self.cooldown=math.max(0,(self.cooldown or 0)-1)
 local a=self.pending;if not a then return end;self.pending=nil;self.cooldown=30
 local r=self.r;local q=r.contract
 if a.world~=r.world or a.session~=r.session or a.key~=q.key or r.world==nil or not r.cfg.enabled or not r.cfg.huntContract then return end
 if r:w('netMode','int32',-1)==1 then
  if r.net and r.net.connected then r.net:request(a.kind=='claim'and'ORW2:claim'or'ORW2:command:'..a.index)end
 elseif a.kind=='accept'then
  if q.status=='offered'and q.offers and q.offers[a.index]==a.offer then q:command('/'..a.index);if q.status=='active'then self.tab=2;self.index=1 end end
 elseif r.inventoryReward and r.inventoryReward.ready then q:command('/领取')end
end
function U:mailRows()
 local r=self.r;local rows={}
 if r.store and r.contract.key then for id,row in pairs(r.store.data.mail or{})do if row.owner==r.contract.key and row.state~='claimed'then rows[#rows+1]={id=id,row=row}end end end
 table.sort(rows,function(a,b)return(a.row.serial or 0)<(b.row.serial or 0)end);return rows
end
function U:draw()
 local g=self.g;local r=self.r;if not g then return end
 local visible=r.world~=nil and not r:w('gameMenu','bool',true) and r.cfg.enabled and r.cfg.huntContract and r.cfg.taskDisplay~="notice"
 g.set_visible(visible);if not visible then return end
 if not g.load_image or not g.image_button or not g.set_skin or(g.image_api_version or 0)<2 then
  g.set_title('猎杀契约','卷');g.text('羊皮纸界面需要支持图片接口的 LuaLoader。');g.text('/1 /2 /3 接取；/任务 查看；/领取 领奖。');return
 end
 if not self.images then
  self.images={};for _,name in ipairs({'panel','icon','card','selected','button','disabled','pixel','font'})do self.images[name]=g.load_image('lib/ui/'..name..'.png')end
  self.font=require('questfont');g.set_title(' ','卷');g.set_style({text=ink})
  g.set_pos(24,24)
 end
 local im=self.images
 if not self.extraImages then
  self.extraImages={};for _,name in ipairs({'panel_dark','card_dark','selected_dark','button_dark','disabled_dark','items','sun','moon'})do self.extraImages[name]=g.load_image('lib/ui/'..name..'.png')end
  self.itemAtlas=require('questitems')
 end
 for name,id in pairs(self.extraImages)do im[name]=id end
 -- LuaLoader defers decode/upload until a recorded draw is flushed.
 -- Queue every pending texture before returning; status polling alone cannot load it.
 local pending=false;local failures={};self.imageStates=self.imageStates or{}
 for _,name in ipairs({'panel','icon','card','selected','button','disabled','pixel','font','panel_dark','card_dark','selected_dark','button_dark','disabled_dark','items','sun','moon'})do
  local id=im[name];local status=id and g.image_status(id)or'invalid: no image handle'
  if self.imageStates[name]~=status then self.imageStates[name]=status;r.log('QUEST_UI_IMAGE',name..' '..tostring(status))end
  if status=='pending'then
   g.image(id,0,0,1,1,{255,255,255,0});pending=true
  elseif status~='ready'then failures[#failures+1]=name..': '..tostring(status)end
 end
 if #failures>0 then
  self.ready=false;g.set_title('猎杀契约','卷')
  g.text('卷轴图片加载失败：');for _,reason in ipairs(failures)do g.text(reason)end
  g.text('详情已写入模组日志；/1 /2 /3 接取，/领取 领奖。');return
 end
 if pending then g.text('正在载入契约卷轴…');return end
 self.ready=true
 local sw=r:w('screenWidth','int32',1280);local sh=r:w('screenHeight','int32',720)
 local ink=self.dark and{246,233,201,255}or{62,43,27,255}
 local teal=self.dark and{128,225,223,255}or{24,107,117,255}
 local muted=self.dark and{203,182,143,255}or{126,106,76,255}
 -- Theme-specific textures, no per-pixel editing of the parchment at runtime.
 local im={};for name,id in pairs(self.images)do im[name]=id end
 for _,name in ipairs({'panel','card','selected','button','disabled'})do if self.dark then im[name]=self.images[name..'_dark']end end
 local foreground={}

 local s=math.max(.3,math.min(.78,(sw*.56)/850,(sh*.72-60)/550));g.set_width(850*s);g.set_skin(im.panel,120,im.icon,48,54*s)
 -- GUI coordinates start after LuaLoader's 12px scaled content padding.
 local loaderScale=math.max(1,math.min(2.5,math.min(sw,sh)/720))
 local footerX=(850-242)/2-12*loaderScale/s
 if not self.initialized then self.initialized=true;r.log('QUEST_UI_READY','all 16 textures ready; parchment panel enabled')end
 local function box(id,x,y,w,h,c)g.image(id,x*s,y*s,w*s,h*s,c or{255,255,255,255})end
 local function text(str,x,y,size,color,width,lines)
  local xx,yy=x,y;local n=1;local f=self.font;local h=(size or 19)*1.35
  for ch in tostring(str or''):gmatch('[%z\1-\127\194-\244][\128-\191]*')do
   local metric=f[ch]or f['?'];local advance=(metric and metric[3]or 32)*h/36
   if ch=='\n'or(width and xx+advance>x+width)then xx=x;yy=yy+h*1.4;n=n+1;if lines and n>lines then return end end
   if ch~='\n'and metric then foreground[#foreground+1]={xx*s,yy*s,40*h/36*s,48*h/36*s,color or ink,{metric[1],metric[2],40,48}};xx=xx+advance end
  end
 end
 local function button(id,x,y,w,h,label,on)
  local clicked=false
  if on then clicked=g.image_button(id,x*s,y*s,w*s,h*s,'',12)else box(im.disabled,x,y,w,h)end
  local metrics=self.font;local labelWidth=0;for ch in label:gmatch('[%z\1-\127\194-\244][\128-\191]*')do local m=metrics[ch]or metrics['?'];labelWidth=labelWidth+(m and m[3]or 32)*19*1.35/36 end
  text(label,x+math.max(8,(w-labelWidth)/2),y+4,19,on and(id==im.card and ink or{250,240,212,255})or muted,w-16,1);return clicked
 end
 local function centered(label,x,y,w,size,color)
  local width=0;for ch in label:gmatch('[%z\1-\127\194-\244][\128-\191]*')do local m=self.font[ch]or self.font['?'];width=width+(m and m[3]or 32)*size*1.35/36 end
  text(label,x+math.max(0,(w-width)/2),y,size,color,w,1)
 end
 centered('猎杀契约',50,0,730,28,ink)
 local themeIcon=self.dark and im.sun or im.moon
 if g.image_button(themeIcon,651*s,0,44*s,44*s,'',0)then
  self.dark=not self.dark;if mod and mod.write_file then mod.write_file('quest_ui_theme.txt',self.dark and'dark'or'light')end
 end
 if button(im.button,716,0,48,44,'×',true)then g.set_collapsed(true)end
 for i,label in ipairs({'可接任务','进行中','待领奖励'})do
  if button(i==self.tab and im.button or im.card,50+(i-1)*242,53,230,43,label,true)then self.tab=i;self.index=1;self.page=1;self.rewardPage=1 end
 end
 local remote=r:w('netMode','int32',-1)==1;local q=remote and r.net and r.net.contractView or r.contract
 local mails=self:mailRows();local rows={}
 if q then
  if self.tab==1 and q.status=='offered'then
   if remote then for i=1,3 do local o=q.offers and q.offers[i];rows[i]={title=o and(titles[o.kind]or'猎杀契约')or('契约 '..i),target=o and o.target or'正在同步任务详情',offer=o,index=i}end
   else for i,o in ipairs(q.offers or{})do rows[i]={title=titles[o.kind]or'猎杀契约',target=o.target,offer=o,index=i}end end
  elseif self.tab==2 and q.status=='active'then local o=remote and(q.selected or{kind=q.kind,target=q.target,rewardText=q.reward,seconds=q.seconds})or q.selected;if o then rows[1]={title=titles[o.kind]or'进行中',target=o.target,offer=o}end
  elseif self.tab==3 then if remote and(q.pending or 0)>0 then rows[1]={title='个人待领奖励',target='待领 '..q.pending..' 份',remote=true}else for i,m in ipairs(mails)do rows[i]={title='契约奖励',target='已完成契约，奖励已保存',mail=m,index=i}end end end
 end
 local pages=math.max(1,math.ceil(#rows/3));self.page=math.min(self.page,pages);self.index=math.min(math.max(self.index,1),math.max(1,#rows))
 for slot=1,3 do local i=(self.page-1)*3+slot;local row=rows[i];if row then
  local id=i==self.index and im.selected or im.card
  if g.image_button(id,50*s,(112+(slot-1)*96)*s,282*s,86*s,'',14)then self.index=i;self.rewardPage=1 end
  centered(row.title,65,132+(slot-1)*96,252,23,teal)
 end end
 if pages>1 then
  if button(im.button,50,407,90,36,'上一页',self.page>1)then self.page=self.page-1;self.index=(self.page-1)*3+1 end
  text(self.page..' / '..pages,164,415,17)
  if button(im.button,240,407,92,36,'下一页',self.page<pages)then self.page=self.page+1;self.index=(self.page-1)*3+1 end
 end
 box(im.pixel,351,114,1,280,{178,150,100,180})
 local row=rows[self.index]
 if row then
  text(row.title,380,112,27,teal,398,1);text(row.target,380,157,20,ink,395,2)
  local o=row.offer
  if self.tab==2 then
   local count,goal=q.count or 0,q.goal or 0;local seconds=remote and(q.seconds or 0)or math.floor((q.remaining or 0)/60)
   text('任务进度 '..count..' / '..goal,380,243,19)
   box(im.pixel,380,276,380,12,{188,166,126,255});box(im.pixel,380,276,380*math.min(1,count/math.max(1,goal)),12,teal)
   text(('剩余 %02d:%02d'):format(math.floor(seconds/60),seconds%60),380,281,18,teal)
  elseif self.tab==1 and o then text('时限 '..math.floor(o.seconds/60)..' 分钟 · '..({'低风险','中风险','高风险'})[o.risk or 1],380,249,18,muted)end
  local reward=o and o.rewardText or row.mail and row.mail.row.text or row.remote and '奖励由房主存档发放' or'奖励详情见任务播报'
  text('任务奖励',380,326,19,teal)
  local rewards=o and o.rewards or row.mail and row.mail.row.rewards
  if rewards and #rewards>0 then
   local pages=math.max(1,math.ceil(#rewards/3));self.rewardPage=math.min(self.rewardPage,pages)
   local columns=math.min(3,#rewards-(self.rewardPage-1)*3);local cell=395/columns
   for j=1,columns do local v=rewards[(self.rewardPage-1)*3+j];if v then
    local x=380+(j-1)*cell;local a=self.itemAtlas[v.id]
    if a then local scale=math.min(36/a[3],36/a[4]);local w,h=a[3]*scale,a[4]*scale
     g.image(im.items,(x+(36-w)/2)*s,(363+(36-h)/2)*s,w*s,h*s,{255,255,255,255},a)
    else text('?',x,365,25,muted);r.log('QUEST_UI_ITEM_MISSING',tostring(v.id))end
    text('× '..v.stack,x+44,364,columns==3 and 19 or 21,ink,cell-46,1);centered(v.name or('物品 '..v.id),x,403,cell-4,columns==3 and 15.5 or 18,ink)
   end end
   if pages>1 and button(im.button,637,324,140,36,self.rewardPage..'/'..pages..' ›',true)then self.rewardPage=self.rewardPage%pages+1 end
  else text(reward,380,365,19,ink,395,2)end
  if self.tab==1 then if button(im.button,footerX,448,242,52,'接取契约',(not remote or o~=nil)and not self.pending and(self.cooldown or 0)==0)then self:queue('accept',row.index,o)end
  elseif self.tab==3 then
   local state=row.mail and row.mail.row.state
   local enabled=(remote and r.net and r.net.connected)or(not remote and self.index==1 and state=='pending'and r.inventoryReward and r.inventoryReward.ready)
   if button(im.button,footerX,448,242,52,'领取奖励',enabled and not self.pending and(self.cooldown or 0)==0)then self:queue('claim')end
   if state=='review'then text('发放记录待核对，请提供日志',380,285,17,muted,395,2)elseif not remote and self.index~=1 then text('请先领取最早的一份奖励',380,285,17,muted,395,2)end
  end
 else
  text(self.tab==1 and'暂无可接任务'or self.tab==2 and'尚未接取契约'or'暂无待领奖励',390,178,26,teal,380,2)
  if not q then text('正在等待房主同步',390,246,19,muted)elseif q.status=='waiting'then local sec=remote and(q.seconds or 0)or math.floor((q.remaining or 0)/60);text('下次刷新约 '..math.ceil(sec/60)..' 分钟',390,246,19,muted)end
 end
 if r:w('gamePaused','bool',false)or(r.bossDialog and r.bossDialog.active)then text('暂停计时',650,506,17,muted)end
 -- Submit the entire font atlas as the last texture group. Android's deferred
 -- renderer otherwise batches early glyphs behind subsequently drawn cards.
 for _,cmd in ipairs(foreground)do g.image(im.font,cmd[1],cmd[2],cmd[3],cmd[4],cmd[5],cmd[6])end
 g.set_content_height(550*s)
end
return U
