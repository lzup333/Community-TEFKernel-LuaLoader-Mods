mod.meta={pkg_id='codex.lua.recipebook',version='0.1.28',version_code=29}
local g=mod.gui;local D=require('data');local P=require('planner');local T=require('text')
local Wiki=require('wiki_data');local WikiPurpose=require('wiki_purpose');local WikiRef=require('wiki_reference');local Atlas=require('atlas');local Search=require('search');local aliases=require('aliases')
local W,H=1080,620
local selected,category,query=5000,'全部',''
local choices,favorites,history={},{},{}
local tab,quantity='合成',1
local scale,nativeScale=1,1
local initialized,frame=false,0
local perfSum,perfPeak,perfFrames=0,0,0
local icons,iconLast,used={},{},{}
local filtered,filterKey,uses,readyGeneration={},nil,{},nil
local categoryIds,searchBuckets={},{}
local lastFilterCategory,lastFilterQuery,lastFilterResults=nil,nil,{}
local leaves,steps,inventory={},{},{}
local searchOpen,confirmRefresh,groupModal=false,false,nil
local inputMode="英文"
local IME=require("ime");local composition="";local candidatePage=1
local blocked,overlay=false,false
local planDirty=true;local bagRead=false
local infoCacheId,infoCacheRecipes,infoCacheRows=nil,nil,nil
local ink={232,241,255,255};local muted={170,194,224,255};local accent={137,202,255,255};local gold={205,227,255,255}
local stations={[18]='工作台',[17]='熔炉',[16]='铁砧／铅砧',[26]='恶魔祭坛／猩红祭坛',[114]='工匠作坊',[134]='秘银砧／山铜砧',[133]='精金熔炉／钛金熔炉',[412]='远古操纵机',[13]='放置的瓶子',[355]='炼药桌',[101]='书架',[125]='水晶球',[106]='锯木机',[86]='织布机',[283]='重型工作台',[228]='自动锤炼机'}
local stationItems={[18]={36},[26]={5532},[77]={221},[17]={33},[16]={35,716},[114]={398},[134]={525,1220},[133]={524,1221},[412]={3549},[13]={31},[355]={3000},[101]={354},[125]={487},[106]={363},[86]={332},[283]={2172},[228]={1551}}
local uiAssets={}
local function uiAsset(name)
 if not uiAssets[name]then uiAssets[name]=g.load_image('lib/ui/'..name..'.png')end
 return uiAssets[name]
end
-- A single shared texture keeps panel and button ordering consistent on PE.
local function card(x,y,w,h,kind)
 local tint=kind=='selected' and {92,157,229,255} or kind=='pane' and {38,62,110,255} or {54,87,146,255}
 g.nine_slice(uiAsset('rounded_shared'),x*scale,y*scale,w*scale,h*scale,12,tint,12*scale)
end
-- LuaLoader already draws an interactive scrollbar for each scroll viewport.
local function drawScrollThumb(x,y,w,h,sy,vh,contentH) end
local function readable(size)
 return math.min(34,math.max(18,size*1.16))
end
local function drawText(x,y,s,size,c,width)
 if width then s=T.fit(s,size,width)end
 T.draw(g,x,y,s,size,c or ink,scale)
end
local function text(x,y,s,size,c,width)
 drawText(x,y,s,readable(size),c,width)
end
local function centered(cx,y,s,size,c,width)
 size=readable(size)
 if width then s=T.fit(s,size,width)end
 drawText(cx-T.width(s,size)/2,y,s,size,c)
end
local function hitRegion(x,y,w,h)
 return g.image_button(uiAsset('hit'),x*scale,y*scale,w*scale,h*scale,'',0)
end
local function button(x,y,w,h,s,active,size,noHit)
 local hit=not noHit and not(blocked and not overlay)and hitRegion(x,y,w,h)or false
 card(x,y,w,h,active and 'selected' or 'card')
 if s and s~=''then size=readable(size or 23);s=T.fit(s,size,w-math.min(20,w*.16));drawText(x+(w-T.width(s,size))/2,y+(h-size)/2,s,size,active and accent or ink)end
 return hit
end
-- Item art uses the original atlas; text and UI are drawn natively.
local function icon(id,x,y,size)
 local a=Atlas[id];if not a then return end
 local page=a[1];used[page]=true;iconLast[page]=frame
 if not icons[page]then icons[page]=g.load_image('lib/icons/page_'..page..'.png')end
 g.image(icons[page],x*scale,y*scale,size*scale,size*scale,nil,{a[2],a[3],64,64})
end
local function lines(s,size,width)
 local rows,line={},''
 for _,cp in utf8.codes(s)do local ch=utf8.char(cp)
  if ch=='\n'or T.width(line..ch,size)>width then rows[#rows+1]=line;line=''end
  if ch~='\n'then line=line..ch end
 end
 if line~=''then rows[#rows+1]=line end;return rows
end
local function wrap(x,y,s,size,width,c)
 local lineHeight=readable(size)+7
 local rows=lines(s,readable(size),width);for i,line in ipairs(rows)do text(x,y+(i-1)*lineHeight,line,size,c)end
 return #rows*lineHeight
end
local function save()
 local ids={};for id in pairs(favorites)do ids[#ids+1]=id end;table.sort(ids)
 for i,id in ipairs(ids)do ids[i]=tostring(id)end;mod.write_file('favorites.txt',table.concat(ids,'\n'))
end
local function resetScroll()if g.scroll_to then g.scroll_to('details',0,0)end end
local function navigate(id,push)
 if id~=selected then if push~=false then history[#history+1]=selected;if #history>64 then table.remove(history,1)end end;selected=id;quantity=1 end
 planDirty=true;resetScroll()
end
local function plan()leaves,steps=P.plan(selected,quantity,D.recipes,choices);planDirty=false end
local function station(r)
 local a={};for _,id in ipairs(r.stations)do a[#a+1]=stations[id]or('制作站 #'..id)end
 return #a==0 and'徒手制作'or table.concat(a,' + ')
end
local function getHave(m)
 if m.unresolved or m.group then return '?'end;return tostring(inventory[m.id]or 0)
end
local function openMaterial(m)if m.group then groupModal=m else navigate(m.id)end end
local function indexUses()uses=WikiRef.uses end
local function rebuildItemIndex()
 lastFilterCategory,lastFilterQuery,lastFilterResults=nil,nil,{}
 categoryIds={['全部']={},['武器']={},['饰品']={},['材料']={},['收藏']={}}
 searchBuckets={}
 for id,item in pairs(D.items)do
  categoryIds['全部'][#categoryIds['全部']+1]=id
  local c=item.category or'材料';categoryIds[c]=categoryIds[c]or{};categoryIds[c][#categoryIds[c]+1]=id
  if favorites[id]then categoryIds['收藏'][#categoryIds['收藏']+1]=id end
  local name=D.name(id)
  for _,ch in ipairs(Search.asciiChars(id,name,aliases[id]))do
   local bucket=searchBuckets[ch]or{};searchBuckets[ch]=bucket;bucket[#bucket+1]=id
  end
 end
 for _,ids in pairs(categoryIds)do table.sort(ids)end
 for _,ids in pairs(searchBuckets)do table.sort(ids)end
end
local function filter()
 local key=category..'/'..query
 if filterKey==key then return end;filterKey=key;filtered={}
 local source=categoryIds[category]or categoryIds['全部']
 local q=Search.normalize(query)
 if q~=''then
  -- Narrow the previous result while typing. This avoids rescanning thousands
  -- of items on every key press on slower mobile devices.
  if q:find('[^%w]') then
   -- Chinese input is UTF-8, so it cannot use the ASCII first-letter bucket.
   -- Search the active category directly and let Search.match check the name.
   source=categoryIds[category]or categoryIds['全部']
  elseif lastFilterCategory==category and lastFilterQuery~='' and q:sub(1,#lastFilterQuery)==lastFilterQuery then
   source=lastFilterResults
  else
   source=searchBuckets[q:sub(1,1)]or{}
  end
 end
 for _,id in ipairs(source)do
  local item=D.items[id]
  if item and(category=='全部'or category=='收藏'or category==item.category)and Search.match(id,D.name(id),aliases[id],q)then filtered[#filtered+1]=id end
 end
 lastFilterCategory,lastFilterQuery,lastFilterResults=category,q,filtered
 if not searchOpen and g.scroll_to then g.scroll_to('items',0,0)end
end
local function itemRow(id,y,w,subtitle)
 local hit=button(0,y,w,66,'',id==selected)
 icon(id,8,y+12,40)
 local textX,textW=40,w-48
 if subtitle then
  centered(textX+textW/2,y+7,D.name(id),22,nil,textW)
  centered(textX+textW/2,y+36,subtitle,17,muted,textW)
 else
  centered(textX+textW/2,y+20,D.name(id),23,nil,textW)
 end
 return hit
end
local function renderDetails()
 local x,w=648,420
 local rs=D.recipes[selected]or{};local ri=math.min(choices[selected]or 1,math.max(1,#rs));local r=rs[ri]
 if planDirty then plan()end
 card(x,8,w,598,'pane');card(x+12,20,82,82,'card');icon(selected,x+19,27,68)
 text(x+105,28,D.name(selected),27,nil,225)
 text(x+105,66,(D.items[selected]and D.items[selected].category or'材料')..'  ID '..selected,18,muted,235)
 if button(x+326,25,80,42,favorites[selected]and'已收藏'or'收藏',favorites[selected],16)then favorites[selected]=not favorites[selected]or nil;rebuildItemIndex();filterKey=nil;save()end
 for i,label in ipairs({'合成','用途','基础','信息'})do
  if button(x+12+(i-1)*100,112,94,40,label,tab==label,19)then tab=label;resetScroll()end
 end
 if tab=='信息' then
  local info=Wiki[selected];local paragraphs={}
  if infoCacheId~=selected or infoCacheRecipes~=D.recipes then
  local purpose=WikiPurpose[selected]
  if WikiRef.uses[selected] and #WikiRef.uses[selected]>0 then
   purpose=(purpose and purpose..'；'or'')..'可用于合成，具体物品见用途页'
  end
  paragraphs[#paragraphs+1]='【有什么用】\n'..(purpose or '暂无可靠用途信息')
  paragraphs[#paragraphs+1]='【怎么获得】\n'..(info and info.methods and #info.methods>0 and table.concat(info.methods,' / ') or '暂无获取方式信息')
  infoCacheRows=lines(table.concat(paragraphs,'\n\n'),readable(17),363);infoCacheId=selected;infoCacheRecipes=D.recipes
  end
  local rows=infoCacheRows
  local content=math.max(345,#rows*28+12)
  local _,sy,_,vh=g.begin_scroll('details',(x+10)*scale,160*scale,398*scale,355*scale,398*scale,content*scale)
  for i=math.max(1,math.floor(sy/(28*scale))+1),math.min(#rows,math.ceil((sy+vh)/(28*scale)))do
   text(6,(i-1)*28,rows[i],17,ink)
  end
  g.end_scroll();drawScrollThumb(x+10,160,398,355,sy/scale,vh/scale,content)
 elseif tab=='合成' and r then
  text(x+12,161,'所需材料',20,gold)
  local batches=math.ceil(quantity/math.max(1,r.output))
  local tail=#r.conditions>0 and('制作条件：'..table.concat(r.conditions,'、'))or''
  local content=math.max(236,#r.materials*62+(tail~=''and 45 or 0))
  local _,sy,_,vh=g.begin_scroll('details',(x+10)*scale,189*scale,398*scale,236*scale,398*scale,content*scale)
  for i,m in ipairs(r.materials)do local y=(i-1)*62
   if (y+58)*scale>=sy and y*scale<=sy+vh then
    if button(0,y,360,56,'')then openMaterial(m)end
    icon(m.id,7,y+5,46);text(61,y+5,m.name or D.name(m.id),19,nil,184)
    text(61,y+31,'已有 '..getHave(m),15,muted,170)
    text(270,y+15,'x '..m.count*batches,19,ink,80)
   end
  end
  if tail~=''then wrap(5,#r.materials*62,tail,16,370,muted)end
  g.end_scroll();drawScrollThumb(x+10,189,398,236,sy/scale,vh/scale,content)
  text(x+12,435,'制作站',20,gold)
  local stationContent=math.max(54,#r.stations*54)
  local _,ss,_,sv=g.begin_scroll('stations',(x+10)*scale,463*scale,398*scale,56*scale,398*scale,stationContent*scale)
  if #r.stations==0 then text(12,16,'徒手制作',18,ink,350)
  else for i,tile in ipairs(r.stations)do local y=(i-1)*54
   if y*scale<=ss+sv and (y+52)*scale>=ss then local ids=stationItems[tile];icon(ids and ids[1]or 36,8,y+4,44);text(62,y+15,stations[tile]or('制作站 #'..tile),18,ink,310)end
  end end;g.end_scroll()
  text(x+12,541,'配方',18,muted)
  if button(x+80,530,45,40,'<',false,20)then choices[selected]=(ri-2)%#rs+1;planDirty=true;resetScroll()end
  centered(x+164,539,ri..' / '..#rs,18,ink,72)
  if button(x+203,530,45,40,'>',false,20)then choices[selected]=ri%#rs+1;planDirty=true;resetScroll()end
 elseif tab=='合成' then
  wrap(x+14,178,'未查到合成配方。',19,385,muted)
 else
  local rows=tab=='用途'and(uses[selected]or{})or leaves
  text(x+12,162,tab=='用途'and'可合成物品（Wiki）'or'基础材料',20,gold)
  local content=math.max(330,#rows*62)
  local _,sy,_,vh=g.begin_scroll('details',(x+10)*scale,190*scale,398*scale,330*scale,398*scale,content*scale)
  for i=math.max(1,math.floor(sy/(62*scale))+1),math.min(#rows,math.ceil((sy+vh)/(62*scale)))do
   local v=rows[i];local id=tab=='用途'and v or v.id;local y=(i-1)*62
   if button(0,y,360,56,'')then if tab=='用途'then navigate(id)else openMaterial(v)end end
   icon(id,7,y+5,46);text(61,y+7,tab=='用途'and D.name(id)or(v.name or D.name(id)),19,ink,245)
   if tab=='基础'then text(61,y+31,'已有 '..getHave(v)..' / 需要 '..tostring(v.quantity),15,muted,290)end
  end
  if #rows==0 then text(10,12,'暂无内容',19,muted)end
  g.end_scroll();drawScrollThumb(x+10,190,398,330,sy/scale,vh/scale,content)
 end
 if button(x+279,531,128,40,'返回',false,18)then local id=table.remove(history);if id then navigate(id,false)end end
end
local function searchModal()
 local function dismiss(x,y,w,h)return hitRegion(x,y,w,h)end
 if dismiss(0,0,W,70) or dismiss(0,570,W,50) or dismiss(0,70,28,500) or dismiss(1052,70,28,500) then
  searchOpen=false;composition='';candidatePage=1;filterKey=nil;return
 end
 card(28,70,1024,500,'pane')
 text(52,83,'搜索物品',24)
 if button(732,80,143,43,inputMode=='英文'and'英文键盘'or'中文拼音',true,18)then
  inputMode=inputMode=='英文'and'中文'or'英文';composition='';candidatePage=1
 end
 if button(884,80,138,43,'返回',false,20)then searchOpen=false;composition='';candidatePage=1;filterKey=nil;return end
 card(52,137,720,50,'card')
 local display=query..(composition~='' and (' ['..composition..']') or '')
 text(67,150,display==''and(inputMode=='中文'and'输入拼音，选择候选字'or'输入拼音或 ID')or display,21,ink,690)
 if button(790,137,232,50,'清空',false,20)then query='';composition='';candidatePage=1;filterKey=nil end
 if inputMode=='中文' and composition~='' then
  local cands=IME.candidates(composition);local perPage=6;local maxPage=math.max(1,math.ceil(#cands/perPage));candidatePage=math.min(candidatePage,maxPage)
  if button(52,196,52,44,'<',false,19)then candidatePage=math.max(1,candidatePage-1)end
  for i=1,perPage do local ch=cands[(candidatePage-1)*perPage+i]
   if ch and button(110+(i-1)*93,196,87,44,ch,false,22)then query=query..ch;composition='';candidatePage=1;filterKey=nil end
  end
  if button(674,196,52,44,'>',false,19)then candidatePage=math.min(maxPage,candidatePage+1)end
  text(748,208,candidatePage..'/'..maxPage,16,muted,65)
  if #cands==0 then text(125,207,'没有候选，试试完整拼音',17,muted,490)end
 else
  filter()
  for i=1,3 do local id=filtered[i];if id then
   if button(52+(i-1)*327,196,312,44,'',false,19)then navigate(id);searchOpen=false;return end
   icon(id,59+(i-1)*327,200,36);text(101+(i-1)*327,207,D.name(id),19,nil,250)
  end end
 end
 local rows={'1234567890','qwertyuiop','asdfghjkl','zxcvbnm'}
 local pressed=nil;local keyW,keyH,gap=69,65,3
 for row,letters in ipairs(rows)do
  local count=#letters;local rowW=count*keyW+(count-1)*gap;local startX=52+(720-rowW)/2
  for col=1,count do
   local x=startX+(col-1)*(keyW+gap);local y=247+(row-1)*72
   local ch=letters:sub(col,col)
   if button(x,y,keyW,keyH,ch,false,29)then pressed=ch end
  end
 end
 if pressed then
  if inputMode=='中文' and pressed:match('[a-z]')then composition=composition..pressed;candidatePage=1
  elseif inputMode=='英文' or composition=='' then query=query..pressed;filterKey=nil end
 end
 if button(790,247,232,65,'删除',false,22)then
  if composition~=''then composition=composition:sub(1,-2);candidatePage=1
  elseif query~=''then query=query:sub(1,(utf8.offset(query,-1)or 1)-1);filterKey=nil end
 end
 if button(790,319,232,65,'清空',false,22)then query='';composition='';candidatePage=1;filterKey=nil end
 if button(790,391,232,130,'完成',true,25)then
  if composition~=''then local cands=IME.candidates(composition);if cands[1]then query=query..cands[1]end;composition='';filterKey=nil
  else searchOpen=false;filterKey=nil end
 end
end
local function modalDraw()
 overlay=true
 if searchOpen then searchModal();return end
 if confirmRefresh then
  card(213,187,660,285,'pane');text(240,212,'重建本地配方缓存？',28)
  wrap(240,263,'更换游戏版本或配方模组后可手动重建。首次整理需要一些时间，收藏会保留。',23,600,muted)
  if button(240,393,280,48,'开始重建',true)then D.rebuild();readyGeneration=nil;inventory={};bagRead=false;confirmRefresh=false;planDirty=true end
  if button(544,393,300,48,'取消')then confirmRefresh=false end
 end
 if groupModal then
  card(213,187,660,285,'pane');text(240,212,'可替代材料',28)
  wrap(240,263,'此处使用材料组，当前显示代表材料：'..D.name(groupModal.id)..'。候选列表暂未读取，库存显示 ?。',23,600,muted)
  if button(240,393,280,48,'查看代表配方',true)then local id=groupModal.id;groupModal=nil;navigate(id)end
  if button(544,393,300,48,'返回')then groupModal=nil end
 end
end
local function mainDraw()
 frame=frame+1;used={}
 if not initialized then
  local txt=mod.read_file('favorites.txt')or'';for id in txt:gmatch('%d+')do favorites[tonumber(id)]=true end
  local panel=uiAsset('rounded_panel');local launcher=uiAsset('launcher')
  g.set_skin(panel,12,launcher,42,12)
  g.set_title('合成图鉴','册');g.set_style({panel={27,45,86,255},title={38,61,111,255},border={38,61,111,255}});g.set_collapsed(true)
  D.init();initialized=true;return
 end
 if g.is_collapsed and g.is_collapsed()then return end
 local sw,sh=D.screen();nativeScale=math.max(1,math.min(2.5,math.min(sw,sh)/720));T.nativeScale=nativeScale
 scale=math.min(1.6,(sw-100-24*nativeScale)/W,(sh-100-56*nativeScale)/H);scale=math.max(.25,scale)
 g.set_width(W*scale+24*nativeScale)
 -- Place the overlay near the top of the screen.
 if frame==2 then g.set_pos((sw-W*scale-24*nativeScale)/2,0)end
 -- Search and category controls occupy the top of the item area.
 if button(12,12,196,48,'',false,18)then searchOpen=true;return end
 text(25,26,query==''and'搜索物品 / ID'or query,18,muted,172)
 local categoryNames={'全部','武器','饰品','材料','收藏'}
 for i,c in ipairs(categoryNames)do
  if button(214+(i-1)*82,12,76,48,c,category==c,19)then category=c;filterKey=nil end
 end
 D.tick()
 if D.error then wrap(24,145,D.error,22,590);return end
 if not D.ready then
  text(24,145,D.waitingWorld and'进入世界后即可整理配方。'or D.cacheStatus=='正在载入本地缓存'and('载入本地配方：'..(D.cacheIndex or 0))or('正在整理游戏配方：'..D.index..' / '..D.total),21,nil,590)
  text(24,182,'首次整理后自动保存，下次优先读取本地缓存。',18,muted,590);return
 end
 if searchOpen or confirmRefresh or groupModal then overlay=true;modalDraw();return end
 if readyGeneration~=D.recipes then readyGeneration=D.recipes;indexUses();rebuildItemIndex();filterKey=nil;planDirty=true end
 if frame%120==0 or not bagRead then inventory=D.inventory();bagRead=true end
 filter()
 card(12,70,620,480,'pane')
 local columns,cell,step=5,108,116
 local totalRows=math.ceil(#filtered/columns);local content=math.max(464,totalRows*step)
 local _,sy,_,vh=g.begin_scroll('items',20*scale,78*scale,604*scale,464*scale,604*scale,content*scale)
 if #filtered==0 then text(12,20,'没有匹配物品。',20,muted)end
 local first=math.max(0,math.floor(sy/(step*scale)))
 local last=math.min(totalRows-1,math.floor((sy+vh-1)/(step*scale)))
 for row=first,last do for col=0,columns-1 do
  local id=filtered[row*columns+col+1]
  if id then local x,y=col*step,row*step
   if button(x,y,cell,cell,'',id==selected)then navigate(id)end
   icon(id,x+17,y+4,74)
   centered(x+cell/2,y+87,D.name(id),17,ink,cell-8)
  end
 end end
 g.end_scroll();drawScrollThumb(20,78,604,464,sy/scale,vh/scale,content)
 if button(20,562,144,40,'重建缓存',false,17)then confirmRefresh=true end
 renderDetails()

end
function on_gui()
 if not g.begin_scroll then g.text('请更新带滑动接口的 LuaLoader 1.9.0');return end
 local started=os.clock()
 blocked=searchOpen or confirmRefresh or groupModal~=nil;overlay=false
 mainDraw()
 g.set_content_height(H*scale)
 local count=0;for _ in pairs(icons)do count=count+1 end
 while count>12 do
  local oldest,age=nil,math.huge
  for page,last in pairs(iconLast)do if icons[page]and not used[page]and last<age then oldest,age=page,last end end
  if not oldest then break end
  g.release_image(icons[oldest]);icons[oldest]=nil;iconLast[oldest]=nil;count=count-1
 end
 local dt=(os.clock()-started)*1000;perfSum=perfSum+dt;perfPeak=math.max(perfPeak,dt);perfFrames=perfFrames+1
 if perfFrames>=180 then
  mod.write_file('recipebook_ui.log',string.format('version=0.1.28\nrenderer=stable-tab-simple-info\nscript_avg_ms=%.3f\nscript_peak_ms=%.3f\ncache=%s\nrecipe_index=%d/%d\n',perfSum/perfFrames,perfPeak,D.cacheStatus or'',D.index or 0,D.total or 0))
  perfSum=0;perfPeak=0;perfFrames=0
 end
end
mod.on_gui=on_gui
