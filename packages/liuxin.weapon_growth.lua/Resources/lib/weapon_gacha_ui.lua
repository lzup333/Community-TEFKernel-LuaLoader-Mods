-- Parchment mystery wheel. Rendering never reads native game objects or grants items.
local M={}
local Labels=require('weapon_gacha_labels')
local LabelAtlas=require('weapon_gacha_label_atlas')
local Atlas=require('weapon_gacha_atlas')
local textures={}
local spriteQueue,textQueue={},{}
local function queue(target,method,...)target[#target+1]={method=method,args=table.pack(...)}end
local function flush(g,q)for _,cmd in ipairs(q)do g[cmd.method](table.unpack(cmd.args,1,cmd.args.n))end end
local service
local init=false
local skin,disc,hit,chest
local selected=nil
local phase='idle'
local frame,angle,reveal=0,0,0
local request,profile,result,message
local history={}
local historyPage,historyDetail=0,false

local ink={73,43,23,255}
local gold={245,206,113,255}
local light={253,232,185,255}
local classes={{nil,'随机'},{'melee','近战'},{'ranged','远程'},{'magic','魔法'},{'summon','召唤'}}
local palette={panel={0,0,0,0},title={0,0,0,0},button={91,61,39,255},hover={148,99,49,255},border={0,0,0,0},text={87,54,29,255}}
local function short(t,n)
 t=tostring(t or '');local len=utf8.len(t)
 if not len or len<=n then return t end
 return t:sub(1,utf8.offset(t,n+1)-1)..'…'
end
local function width(t,f)
 local n=0;for _,c in utf8.codes(t)do n=n+(c<128 and 10 or 20)end;return n*(f or 1)
end
local function asset(g,n)
 if not textures[n] then textures[n]=g.load_image('lib/ui/'..n..'.png')end
 return textures[n]
end
local function text(g,t,x,y,w,h,f,c)
 t=tostring(t)
 local label=Labels[t]
 if label then
  local variant=(c==gold and 'gold')or ((c==ink or not c)and 'ink')or 'light'
  local key=label[1]..'_'..variant
  local region=LabelAtlas[key];local texture=asset(g,'labels_atlas')
  if region and texture then
   local tw,th=label[2]*f,label[3]*f
   local fit=math.min(1,(w-4)/tw,(h+5)/th);tw=tw*fit;th=th*fit
   queue(textQueue,'image',texture,x+(w-tw)/2,y+(h-th)/2,tw,th,nil,region)
   return
  end
 end
 f=math.min(f,(w-8)/math.max(1,width(t,1)))
 queue(textQueue,'text_at',x+(w-width(t,f))/2,y+(h-28*f)/2,t,c or ink,f)
end
local function plate(g,n,x,y,w,h)
 local id=asset(g,n)
 if not id then return end
 if type(g.nine_slice)=='function'then g.nine_slice(id,x,y,w,h,10,nil,7)
 else g.image(id,x,y,w,h)end
end
local function panel(g,x,y,w,h)plate(g,'card',x,y,w,h)end
local function click(g,x,y,w,h)
 return hit and g.image_button(hit,x,y,w,h,'',0)
end
local function button(g,t,x,y,w,h,on)
 plate(g,on and 'button_gold' or 'button',x,y,w,h)
 text(g,t,x,y,w,h,.78,light)
 return click(g,x,y,w,h)
end
local function emblem(g,x,y,size,lit)
 text(g,lit and '◆' or '?',x,y,size,size,lit and .9 or .85,lit and {255,218,126,255}or {124,77,32,255})
end
local function weapon(g,item,x,y,w,h)
 local r=Atlas.items[item.id]
 local texture=r and asset(g,'items_atlas_'..r[1])
 if texture then
  local scale=math.min(w/r[4],h/r[5])
  local dw,dh=r[4]*scale,r[5]*scale
  -- Preserve the exact original sprite and queue the atlas draw even while pending.
  queue(spriteQueue,'image',texture,x+(w-dw)/2,y+(h-dh)/2,dw,dh,nil,{r[2],r[3],r[4],r[5]})
 else panel(g,x,y,w,h);text(g,'#'..item.id,x,y,w,h,.62,light)end
end
local function effect(g,n,x,y,size)
 local id=asset(g,n);if id then queue(spriteQueue,'image_fit',id,x-size/2,y-size/2,size,size,'contain')end
end
local function spinFX(g,cx,cy,step)
 effect(g,'glow',cx,cy,144+18*math.sin(step*.14))
 -- Three moving comet heads with short image-only trails.
 for head=1,3 do
  for tail=0,3 do
   local a=angle+head*math.pi*2/3-tail*.13
   effect(g,'spark',cx+91*math.cos(a),cy+91*math.sin(a),34-tail*7)
  end
 end
 -- A bounded set of deterministic particles spirals toward the sealed chest.
 for i=1,10 do
  local t=((step+i*13)%90)/90
  local a=i*2.4+step*.07
  local radius=94*(1-t)
  effect(g,'spark',cx+radius*math.cos(a),cy+radius*math.sin(a),7+10*t)
 end
end
local function revealFX(g,cx,cy,step,size)
 if step>45 then return end
 local t=step/45
 effect(g,'glow',cx,cy,size*(1.5-.5*t))
 for i=1,10 do
  local a=i*math.pi/5
  effect(g,'spark',cx+size*.65*t*math.cos(a),cy+size*.65*t*math.sin(a),18*(1-t)+3)
 end
end
local function start(stats,n)
 if phase=='spinning' or phase=='waiting' then return end
 if not service then message='等待进入单人世界';return end
 if not stats or not stats.ready then message=stats and stats.status or '奖池尚未就绪';return end
 if (stats.tickets or 0)<n then message='抽奖券不足';return end
 local msg,serial=service.draw(n,selected)
 message=msg
 if serial then historyDetail=false;request=serial;profile=stats.profile;frame=0;angle=0;result=nil;reveal=0;phase='spinning'end
end
function M.install(target)
 if not target or not target.gui then return false end
 target.on_gui=function()
  local g=target.gui;if not g then return end
  spriteQueue,textQueue={},{}
  for _,n in ipairs({'image','image_fit','image_button','load_image','text_at','rect','set_title','set_width','set_content_height','set_style','set_pos','set_collapsed'})do if type(g[n])~='function'then return end end
  g.set_title(' ','召');g.set_width(676);g.set_content_height(316);g.set_style(palette)
  if not skin then skin=g.load_image('lib/ui/parchment_skin.png')end
  if not disc then disc=g.load_image('lib/ui/seal_disc.png')end
  if not hit then hit=g.load_image('lib/ui/transparent.png')end
  if not chest then chest=g.load_image('lib/ui/sealed_chest.png')end
  -- Let the loader paint one window skin, including its native draggable header.
  if type(g.set_skin)=='function' and skin then g.set_skin(skin,38,chest,42,12)end
  if not init then init=true;g.set_pos(20,20);g.set_collapsed(true);return end
  local stats=service and service.state()or {}
  if profile and stats.profile~=profile then
   phase='idle';request=nil;result=nil;message=nil;history={};historyPage=0;historyDetail=false;profile=stats.profile
  end
  if not profile and stats.profile then profile=stats.profile end
  if stats.history then history=stats.history end
  local busy=phase=='spinning'or phase=='waiting'
  if busy then
   frame=frame+1
   local t=math.min(1,frame/150)
   angle=math.pi*12*(1-(1-t)^3)
   if stats.receipt and stats.receipt.serial==request then result=stats.receipt end
   if frame>=150 then
    if result then
     if result.ok and #result.items>0 then
      phase='result';frame=0;reveal=0
      if not stats.history then
       history[#history+1]=result
       if #history>20 then table.remove(history,1)end
      end
      message=nil
     else phase='idle';message=result.status or '抽取失败';request=nil end
    else phase='waiting';message='等待发奖确认…'end
   end
  elseif phase=='result' then
   frame=frame+1;reveal=math.min(#result.items,math.floor(frame/22)+1)
  end
  busy=phase=='spinning'or phase=='waiting'
  text(g,'封印召集',24,-34,220,30,.90,ink)
  -- No second title, nested frame, stretched portrait art, or duplicated background.
  if type(g.set_skin)~='function' and skin then g.image_fit(skin,0,0,652,316,'cover')end
  panel(g,6,5,247,34)
  text(g,'券 '..(stats.tickets or 0)..'   收集 '..(stats.owned or 0)..' / '..(stats.total or 0),6,5,247,34,.73,light)
  if button(g,'×',608,-33,30,27,false)then g.set_collapsed(true)end
  for i,c in ipairs(classes)do
   local x=266+(i-1)*76
   if button(g,c[2],x,5,70,34,selected==c[1])and not busy and phase~='result'then selected=c[1];message=nil end
  end
  if phase=='result' and result then
   panel(g,6,47,640,32)
   text(g,'封印已解 · 奖励已放入背包',12,47,628,32,.82,light)
   local n=#result.items
   for i,item in ipairs(result.items)do
    local w=n==1 and 186 or 118;local h=n==1 and 166 or 84
    local x=n==1 and 233 or 15+((i-1)%5)*125
    local y=n==1 and 86 or 86+math.floor((i-1)/5)*90
    panel(g,x,y,w,h)
    if i<=reveal then
     revealFX(g,x+w/2,y+(n==1 and 57 or 31),math.max(0,frame-(i-1)*22),n==1 and 90 or 45)
     weapon(g,item,x+w/2-(n==1 and 42 or 24),y+7,n==1 and 84 or 48,n==1 and 92 or 48)
     text(g,short(item.name,n==1 and 12 or 8),x+3,y+(n==1 and 110 or 59),w-6,20,n==1 and .78 or .59,light)
     if n==1 then text(g,'首次收集',x,y+139,w,20,.65,gold)end
    else emblem(g,x+w/2-18,y+14,36,false)end
    if click(g,x,y,w,h)then reveal=math.max(reveal,i);frame=math.max(frame,i*22)end
   end
   if button(g,'全部揭晓',156,270,162,36,false)then frame=10000;reveal=#result.items end
   if button(g,historyDetail and '返回记录' or '收下奖励',334,270,162,36,true)then phase=historyDetail and 'history'or 'idle';historyDetail=false;request=nil;result=nil;message='奖励已放入背包'end
  elseif phase=='history' then
   panel(g,6,45,640,30)
   text(g,'最近召集记录',10,45,630,30,.84,gold)
   local pages=math.max(1,math.ceil(#history/3))
   historyPage=math.min(historyPage,pages-1)
   if #history==0 then panel(g,6,82,640,174);text(g,'暂无记录',16,120,620,50,.8,light)end
   for row=1,3 do
    local index=#history-historyPage*3-row+1
    local record=history[index]
    if record then
     local y=81+(row-1)*58
     panel(g,6,y,640,53)
     local timestamp=record.time and os.date('%m-%d %H:%M',record.time)or ''
     if #record.items==1 then
      weapon(g,record.items[1],17,y+4,45,45)
      text(g,record.items[1].name,74,y+3,440,27,.76,light)
      text(g,timestamp,74,y+30,440,18,.54,gold)
     else
      text(g,timestamp,13,y+3,132,20,.53,gold)
      text(g,#record.items..' 件武器',13,y+26,132,21,.62,light)
      for j,item in ipairs(record.items)do weapon(g,item,151+(j-1)*39,y+7,36,36)end
     end
     text(g,'查看详情',557,y+9,82,33,.58,gold)
     if click(g,6,y,640,53)then result=record;phase='result';historyDetail=true;frame=10000;reveal=#record.items end
    end
   end
   if button(g,'上一页',6,270,110,36,false)then historyPage=math.max(0,historyPage-1)end
   if button(g,'返回召集',241,270,170,36,true)then phase='idle'end
   if button(g,'下一页',536,270,110,36,false)then historyPage=math.min(pages-1,historyPage+1)end
   text(g,(historyPage+1)..' / '..pages,122,270,110,36,.62,ink)
  else
   if disc then g.image_fit(disc,6,46,247,247,'contain')end
   local cx,cy=129.5,169.5
   for i=1,8 do
    local a=-math.pi/2+(i-1)*math.pi/4+angle
    emblem(g,cx+81*math.cos(a)-14,cy+81*math.sin(a)-14,28,busy and i==1)
   end
   if busy then spinFX(g,cx,cy,frame)end
   local pulse=busy and 1+.065*math.sin(frame*.25) or 1
   if chest then queue(spriteQueue,'image_fit',chest,cx-57*pulse,cy-52*pulse,114*pulse,104*pulse,'contain')end
   panel(g,266,52,374,146)
   text(g,busy and '正在唤醒封印…' or '未知的馈赠',278,62,350,32,.99,gold)
   local sec=stats.nextTicket or 120
   text(g,(stats.daily or 0)>=20 and '今日在线券已领满 20/20' or ('下张券 '..string.format('%02d:%02d',math.floor(sec/60),sec%60)..'  ·  每2分钟1张'),278,99,350,28,.67,light)
   text(g,short(message or stats.status or '等待进入单人世界',24),278,136,350,30,.66,light)
   if busy then
    if button(g,'跳过动画',266,208,180,34,false)then frame=150 end
    panel(g,458,208,182,34);text(g,'发奖确认后揭晓',458,208,182,34,.68,light)
   else
    if button(g,'召集记录',266,208,180,34,false)then historyPage=0;phase='history'end
    if button(g,'玩法说明',458,208,182,34,false)then message='首次使用送10券；每种Boss首杀10券；在线每日20券'end
   end
   if button(g,busy and '召集中…' or '单抽 ×1',266,254,180,44,false)and not busy then start(stats,1)end
   if button(g,busy and '请稍候' or '十连抽 ×10',458,254,182,44,true)and not busy then start(stats,10)end
   panel(g,6,289,247,25)
   text(g,'今日在线 '..(stats.daily or 0)..'/20  还能领 '..(stats.dailyRemaining or 20)..' 张',9,290,241,23,.54,light)
   text(g,'未收集武器等概率召集',266,300,374,18,.58,ink)
  end
  -- Unity may regroup draws by texture. Submit all foreground textures only after every plate.
  flush(g,spriteQueue)
  flush(g,textQueue)
 end
 return true
end
function M.bind(api)service=api end
return M
