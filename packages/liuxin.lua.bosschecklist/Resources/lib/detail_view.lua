local M={page=1,mode=1,item=nil,info_page=1}
local modes={'全部','常规','专家','大师'}
local function brief(s)
 local t={}
 for _,c in utf8.codes(s) do t[#t+1]=utf8.char(c) end
 if #t>8 then return table.concat(t,'',1,7)..'…' end
 return s
end
local function chunks(s,n)
 local pages,line={},''
 local count=0
 for _,c in utf8.codes(s or '') do
  line=line..utf8.char(c);count=count+1
  if count>=n then pages[#pages+1]=line;line='';count=0 end
 end
 if line~='' then pages[#pages+1]=line end
 if #pages==0 then pages[1]='暂无补充说明。' end
 return pages
end
function M.reset() M.page=1;M.item=nil;M.info_page=1 end
local function info(c,s,y,chars)
 local pages=chunks(s,chars or 115)
 M.info_page=math.min(M.info_page,#pages)
 c.block(282,y,pages[M.info_page],23)
 if #pages>1 then
  if c.button(282,346,60,28,'上页') then M.info_page=math.max(1,M.info_page-1) end
  c.text(366,352,M.info_page..' / '..#pages,c.muted,0.6)
  if c.button(532,346,60,28,'下页') then M.info_page=math.min(#pages,M.info_page+1) end
 end
end
function M.draw(c,b,entry,tab)
 if M.item then
  local item=M.item
  c.icon('item:'..item.id,282,184,44,44)
  c.block(336,184,item.name,12)
  c.text(336,236,'ID '..item.id..' · '..item.tag,c.muted,0.58)
  local body=item.note~='' and item.note or '可获得物品。随机掉落并不保证每次获得，条件随游戏版本、世界类型与难度变化。'
  info(c,body,268,69)
  if c.button(510,182,82,30,'返回列表') then M.item=nil;M.info_page=1 end
  return
 end
 if tab==1 then
  if #entry.summons>0 then
   local item=entry.summons[1]
   c.icon('item:'..item.id,282,184,30,30)
   c.text(320,188,item.name,c.gold,0.68)
   if c.button(510,182,82,30,'查看物品') then M.item=item;M.info_page=1 end
  else
   c.text(282,190,'环境触发 · 无常规召唤物',c.muted,0.64)
  end
  info(c,entry.recipe,225,92)
 elseif tab==2 then
  for i,label in ipairs(modes) do
   if c.button(282+(i-1)*78,182,72,27,label,M.mode==i) then M.mode=i;M.page=1 end
  end
  local out={}
  for _,item in ipairs(entry.drops) do
   if M.mode==1 or M.mode==2 and (item.tag=='常规' or item.tag=='药水') or M.mode==3 and item.tag=='专家及以上' or M.mode==4 and item.tag=='大师' then out[#out+1]=item end
  end
  M.cards(c,out,218)
 elseif tab==3 then
  info(c,b.tip..' '..entry.environment..' '..entry.note,190,138)
 else
  if #entry.materials>0 then
   c.text(282,187,'召唤材料 · 点击查看',c.muted,0.64)
   M.cards(c,entry.materials,218)
  else
   info(c,entry.environment..' '..entry.recipe,190,138)
  end
 end
end
function M.cards(c,items,y)
 local pages=math.max(1,math.ceil(#items/6));M.page=math.min(M.page,pages)
 if #items==0 then c.text(282,y+12,'此分类暂无物品',c.muted,0.65) end
 for j=1,6 do
  local item=items[(M.page-1)*6+j]
  if item then
   local x=282+(j-1)%2*158
   local yy=y+math.floor((j-1)/2)*41
   if c.button(x,yy,152,37,'') then M.item=item;M.info_page=1 end
   c.icon('item:'..item.id,x+5,yy+5,26,26)
   c.text(x+36,yy+3,brief(item.name),c.gold,0.6)
   c.text(x+36,yy+22,item.tag,c.muted,0.44)
  end
 end
 if c.button(282,346,60,28,'上页') then M.page=math.max(1,M.page-1) end
 c.text(362,352,M.page..' / '..pages..' · '..#items..'项',c.muted,0.58)
 if c.button(532,346,60,28,'下页') then M.page=math.min(pages,M.page+1) end
end
return M
