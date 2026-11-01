mod.meta={pkg_id='liuxin.lua.bosschecklist',version='1.0.11',version_code=17}
local bosses=require('bosses')
local reader=require('world_reader')
local catalog=require('catalog')
local atlas=require('icon_atlas')
local detail=require('detail_view')
local themes=require('themes')
local font=require('font_atlas')
local ui_scale=0.75
local g,p=mod.gui,mod.patch
local assets,state,favorites={},{},{}
local initialized=false
local selected,page,filter,tab=1,1,1,1
local next_poll=0
local status='等待进入世界'
local gold=themes.night.text
local muted=themes.night.muted
local green=themes.night.green
local theme_mode,applied_theme='auto',nil
local world_day=nil
local palette=themes.night
local labels={'全部','肉前','肉后','事件','未完成','收藏'}
local last_diagnostic=''
local function diagnostic(message)
 if message==last_diagnostic then return end
 last_diagnostic=message
 local line=os.date('%Y-%m-%d %H:%M:%S')..' '..message
 mod.info('[BossChecklist] '..line)
 mod.write_file('bosschecklist_runtime.log',line..'\n')
end
local function apply_theme()
 local key=theme_mode=='auto' and (world_day==true and 'day' or 'night') or theme_mode
 if key==applied_theme then return end
 palette=themes[key];gold=palette.text;muted=palette.muted;green=palette.green
 assets.panel=assets['panel_'..key];assets.button=assets['button_'..key]
 g.set_style({text=gold,panel=palette.bg,title=palette.title,button=palette.bg,hover=palette.title})
 if assets.panel and assets.icon then g.set_skin(assets.panel,48,assets.icon,40,27) end
 applied_theme=key
 diagnostic('v1.0.11 theme='..key..' text=precolored-image-atlas')
end
local function cycle_theme()
 theme_mode=theme_mode=='auto' and 'day' or theme_mode=='day' and 'night' or 'auto'
 local ok=mod.write_file('theme_mode.txt',theme_mode)
 if not ok then mod.warn('[BossChecklist] 皮肤选择保存失败') end
end
local function poll()
 state={}
 if not p or not p.get_type or not p.get_field or not p.get_field_value then
  status='缺少字段读取API';diagnostic(status);return
 end
 -- 类型/字段是反射元数据，不作为实例对象做is_valid/retain过滤。
 -- 每次刷新取得元数据并立即使用，不跨回调保存借用句柄。
 local main=p.get_type('Terraria','Main')
 local npc=p.get_type('Terraria','NPC')
 if not main then status='未找到 Terraria.Main';diagnostic(status);return end
 if not npc then status='未找到 Terraria.NPC';diagnostic(status);return end
 local in_menu,menu_source=reader.read(p,main,'gameMenu','bool')
 if in_menu==nil then
  status='菜单状态读取失败（详见日志）'
  local found={}
  if p.get_fields and p.field_name then
   for _,f in ipairs(p.get_fields(main,true) or {}) do
    local name=p.field_name(f)
    if name and (name:lower():find('menu') or name:lower():find('world')) then found[#found+1]='field:'..name end
   end
  end
  if p.get_properties and p.property_name then
   for _,prop in ipairs(p.get_properties(main,true) or {}) do
    local name=p.property_name(prop)
    if name and (name:lower():find('menu') or name:lower():find('world')) then found[#found+1]='property:'..name end
   end
  end
  diagnostic('gameMenu='..menu_source..' candidates='..table.concat(found,','));return
 end
 if in_menu==true then world_day=nil;status='主菜单：请进入世界';return end
 world_day=reader.read(p,main,'dayTime','bool')
 local n,known,missing=0,0,{}
 for _,b in ipairs(bosses) do
  local v,source=reader.read(p,b.flag=='hardMode' and main or npc,b.flag,'bool')
  if type(v)=='boolean' then
   state[b.id]=v;known=known+1;if v then n=n+1 end
  else missing[#missing+1]=b.flag..':'..source end
 end
 status='当前世界完成 '..n..' / '..#bosses
 if known<#bosses then status=status..'（未知 '..(#bosses-known)..'）' end
 diagnostic('Main=OK NPC=OK gameMenu='..menu_source..' known='..known..' completed='..n..' missing='..table.concat(missing,','))
end
local function save()
 local ids={}
 for i=1,#bosses do if favorites[i] then ids[#ids+1]=tostring(i) end end
 local ok=mod.write_file('favorites.txt',table.concat(ids,','))
 if not ok then mod.warn('[BossChecklist] 收藏保存失败') end
end
local function load()
 local mode=mod.read_file('theme_mode.txt')
 if mode=='auto' or mode=='day' or mode=='night' then theme_mode=mode end
 local raw=mod.read_file('favorites.txt') or ''
 for s in raw:gmatch('%d+') do local i=tonumber(s);if bosses[i] then favorites[i]=true end end
end
local function text(x,y,s,c,scale)
 local col=c or gold;local size=(scale or 0.7)*ui_scale
 if not font.draw(g,applied_theme or 'night',palette,x*ui_scale,y*ui_scale,s,col,size)then
  g.text_at(x*ui_scale,y*ui_scale,s,col,size)
 end
end
local function width(s,scale)
 return font.measure(s)*scale
end
local function fill(x,y,w,h,color)
 if assets.white then g.image(assets.white,x*ui_scale,y*ui_scale,w*ui_scale,h*ui_scale,color) end
end
local function button(x,y,w,h,s,active)
 local clicked
 if assets.button then clicked=g.image_button(assets.button,x*ui_scale,y*ui_scale,w*ui_scale,h*ui_scale,'',9)
 else clicked=g.button_at(x*ui_scale,y*ui_scale,w*ui_scale,h*ui_scale,'') end
 if active then fill(x+8,y+h-5,w-16,2,palette.accent) end
 local scale=math.min(0.68,(w-20)/math.max(1,width(s,1)))
 text(x+(w-width(s,scale))/2,y+(h-32*scale)/2,s,gold,scale)
 return clicked
end
local function icon(key,x,y,w,h)
 local sprite=atlas.icons[key]
 if not sprite or not assets['icons_'..sprite.page] then return end
 local src=sprite.source
 local factor=math.min(w/src[3],h/src[4])
 local iw,ih=src[3]*factor,src[4]*factor
 g.image(assets['icons_'..sprite.page],(x+(w-iw)/2)*ui_scale,(y+(h-ih)/2)*ui_scale,iw*ui_scale,ih*ui_scale,{255,255,255,255},src)
end
local function row(b,y)
 local clicked=button(16,y,238,38,'',selected==b.id)
 local v=state[b.id]
 local event=b.group==3
 local mark=v==true and (event and '已完成' or '已击杀') or v==false and (event and '未完成' or '未击杀') or '未知'
 local tone=v==true and green or v==false and palette.unbeaten or muted
 text(28,y+(38-32*0.66)/2,mark,tone,0.66)
 icon(catalog[b.id].icon,90,y+7,24,24)
 local scale=math.min(0.68,126/math.max(1,width(b.name,1)))
 text(120,y+(38-32*scale)/2,b.name,selected==b.id and gold or palette.row,scale)
 return clicked
end
local function block(x,y,s,maxchars)
 local line,n,line_width='',0,0
 for _,code in utf8.codes(s) do
  line=line..utf8.char(code);n=n+1;line_width=line_width+font.advance(code)*0.62
  if n>=maxchars or line_width>=288 then text(x,y,line,gold,0.62);y=y+24;line='';n=0;line_width=0 end
 end
 if line~='' then text(x,y,line,gold,0.62);y=y+24 end
 return y
end
local function list()
 local out={}
 for _,b in ipairs(bosses) do
  if filter==1 or (filter>=2 and filter<=4 and b.group==filter-1) or
   (filter==5 and state[b.id]==false) or (filter==6 and favorites[b.id]) then out[#out+1]=b end
 end
 return out
end
function on_gui()
 if not g or not g.text_at then return end
 if not initialized then
  g.set_title(' ','册');g.set_pos(60,70);g.set_width(480)
  g.set_style({text=gold,panel={24,25,28,255},title={33,31,29,255}})
  if g.load_image and (g.image_api_version or 0)>=2 then
   for key,t in pairs(themes) do
    assets['panel_'..key]=g.load_image('lib/ui/'..t.panel)
    assets['button_'..key]=g.load_image('lib/ui/'..t.button)
   end
   font.load(g)
   assets.icon=g.load_image('lib/ui/launcher_slime.png')
   assets.white=g.load_image('lib/ui/white.png')
   for i=1,atlas.pages do assets['icons_'..i]=g.load_image('lib/ui/icons_'..i..'.png') end
  end
  load();initialized=true;g.set_collapsed(true)
 end
 local now=os.time()
 if now>=next_poll then
  next_poll=now+2
  local ok,err=pcall(poll)
  if not ok then state={};status='进度读取异常，请查看日志';diagnostic('exception: '..tostring(err));mod.warn('[BossChecklist] '..tostring(err)) end
 end
 apply_theme()
 if g.is_collapsed() then return end
 font.prepare(g,applied_theme)
 font.begin_frame()
 text(48,-34,'Boss 清单 1.0.11',gold,0.88)
 text(16,5,status,muted,0.65)
 local skin_label=theme_mode=='auto' and (world_day==nil and '皮肤：自动' or world_day and '自动·白天' or '自动·夜晚') or theme_mode=='day' and '皮肤：白天' or '皮肤：夜晚'
 if button(396,0,118,28,skin_label) then cycle_theme();apply_theme() end
 if button(522,0,70,28,'收起') then g.set_collapsed(true) end
 for i,name in ipairs(labels) do
  if button(16+(i-1)*97,36,91,31,name,filter==i) then filter=i;page=1 end
 end
 local items=list()
 local pages=math.max(1,math.ceil(#items/5));page=math.min(page,pages)
 if #items==0 then text(18,99,'暂无条目',muted) end
 for j=1,5 do
  local b=items[(page-1)*5+j]
  if b then
   if row(b,82+(j-1)*43) then selected=b.id;tab=1;detail.reset() end
  end
 end
 if button(16,304,62,30,'上页') then page=math.max(1,page-1) end
 local page_label=page..' / '..pages
 text(135-width(page_label,0.65)/2,310,page_label,muted,0.65)
 if button(192,304,62,30,'下页') then page=math.min(pages,page+1) end
 if assets.white then g.image(assets.white,268*ui_scale,82*ui_scale,1,292*ui_scale,palette.line) end
 local b=bosses[selected]
 local entry=catalog[b.id]
 icon(entry.icon,282,84,26,26)
 text(320,89,b.name,gold,math.min(0.78,186/math.max(1,width(b.name,1))))
 local done=state[b.id]
 text(282,119,done==true and (b.group==3 and '本世界：已完成' or '本世界：已击杀') or done==false and (b.group==3 and '本世界：未完成' or '本世界：未击杀') or '本世界：状态未知',done==true and green or muted,0.65)
 if button(520,84,72,28,favorites[b.id] and '已收藏' or '收藏',favorites[b.id]) then favorites[b.id]=not favorites[b.id];save() end
 for i,name in ipairs({'召唤','掉落','攻略','材料'}) do
  if button(282+(i-1)*78,144,72,30,name,tab==i) then tab=i;detail.reset() end
 end
 detail.draw({icon=icon,text=text,button=button,block=block,fill=fill,gold=gold,muted=muted},b,entry,tab)
 if b.flag=='downedBoss2' then text(16,346,'邪恶Boss共用进度标记',muted,0.58)
 else text(16,346,'点击图标卡查看详情',muted,0.58) end
 text(16,370,'召唤及掉落条件可能随版本变化；本图鉴不统计物品收集状态。',muted,0.52)
 if not assets.panel then text(16,395,'当前加载器不支持图片皮肤',muted,0.6)
 elseif g.image_status then
  local s=g.image_status(assets.panel)
  if s:sub(1,6)=='failed' then text(16,395,'皮肤加载失败：请检查加载器日志',muted,0.6) end
 end
 font.flush(g)
 g.set_content_height(406*ui_scale)
end
mod.on_gui=on_gui
