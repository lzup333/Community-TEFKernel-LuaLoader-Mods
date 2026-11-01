local F=require('morph.forms')
local G=require('morph.growth')
local Skills=require('morph.skills')
local Panel={};Panel.__index=Panel
local white={245,247,255,255};local gold={255,222,140,255}
local function short(s,n)local p=utf8.offset(s,n+1);return p and s:sub(1,p-1)..'…'or s end
function Panel.new(gui,c,b,input)return setmetatable({g=gui,c=c,b=b,input=input,tab='growth',images={},drafts={}},Panel)end
function Panel:toggle()self.pending_toggle=not self.pending_toggle end
function Panel:portrait(form,x,y,w,h)
    local g,b=self.g,self.b;local id=self.images[form.npc]
    if id==nil then id=g.load_image('portraits/NPC_'..form.npc..'.png')or false;self.images[form.npc]=id end
    if not id then return end
    local status,iw,ih=g.image_status(id);if status~='ready'or iw<1 or ih<1 then return end
    local a=b:get('Main','npcFrameCount',nil,'object');local frames=1
    if a and form.npc<b.p.array_length(a)then frames=math.max(1,b.p.array_at(a,form.npc,'int32')or 1)end
    local fh=math.max(1,math.floor(ih/frames));local factor=math.min(w/iw,h/fh)
    local rw,rh=iw*factor,fh*factor
    g.image(id,x+(w-rw)/2,y+(h-rh)/2,rw,rh,white,{0,0,iw,fh})
end
function Panel:draw()
    local g,c,b=self.g,self.c,self.b;local player=b:local_player();local valid=player and b:valid(player)
    if not self.initialized then g.set_title('怪物伙伴','伴');g.set_collapsed(not(self.input and self.input.legacy));self.initialized=true end
    if self.pending_toggle then g.toggle_collapsed();self.pending_toggle=false end
    g.set_visible(valid==true);if not valid or g.is_collapsed()then return end
    local sw,sh=b:main('screenWidth'),b:main('screenHeight')
    local scale=math.min(1.55,(sw-80)/860,(sh-100)/440);scale=math.max(.55,scale)
    local native=math.max(1,math.min(2.5,math.min(sw,sh)/720))
    local legacy=self.input and self.input.legacy
    if legacy and not self.manage_open then
        if self.layout_mode~='bar'then
            g.set_pos(self.bar_x or math.max(5,(sw-420*scale)/2),self.bar_y or math.max(5,sh-110*scale-60*native))
            self.layout_mode='bar';self.layout_w=nil
        end
        self.input:draw_bar(g,scale,native,function()
            self.bar_x,self.bar_y=g.get_pos();self.manage_open=true;self.layout_mode='manage'
        end)
        return
    end
    if legacy then g.set_title('怪物伙伴','伴')end
    g.set_width(860*scale);g.set_content_height(425*scale)
    if self.layout_w~=sw or self.layout_h~=sh then
        g.set_pos(math.max(5,(sw-860*scale)/2),math.max(5,(sh-425*scale-60*native)/2))
        self.layout_w,self.layout_h=sw,sh
    end
    local function text(x,y,s,highlight,size)g.text_at(x*scale,y*scale,s,highlight and gold or white,(size or .76)*scale/native)end
    self.skins=self.skins or{}
    local function skin(name)
        if self.skins[name]==nil then self.skins[name]=g.load_image('ui/'..name..'.png')or false end
        local id=self.skins[name];if id and g.image_status(id)=='ready'then return id end
    end
    local function card(x,y,w,h,selected)
        local id=skin(selected and'selected'or'card')
        if id then g.nine_slice(id,x*scale,y*scale,w*scale,h*scale,12,white,12*scale)
        else g.rect(x*scale,y*scale,w*scale,h*scale,{35,43,85,255})end
    end
    local function button(x,y,w,label,action,selected)
        local id=skin(selected and'selected'or'button');local clicked
        if id then clicked=g.image_button(id,x*scale,y*scale,w*scale,30*scale,'',12)
        else clicked=g.button_at(x*scale,y*scale,w*scale,30*scale,'')end
        local units=0;for _,ch in utf8.codes(label)do units=units+(ch<128 and 10 or 20)end
        local size=math.min(.74,(w-16)/math.max(1,units))
        text(x+(w-units*size)/2,y+(30-28*size)/2,label,selected,size)
        if clicked then action()end
    end
    if legacy then button(807,0,45,'收起',function()self.manage_open=false end)end
    local home=b:at_base(player)
    text(5,5,home and'出生点' or'野外',home)
    for slot=1,3 do
        local id=c.profile.equipped[slot];local f,index;if id then f,index=F.find(id)end;local s=id and c.by_id[id]
        local label=slot..'：'..(f and short(f.name,6)or'空槽')
        if s then label=label..(s.hp<=0 and' 倒下'or(c.state.active and c:form().key==id and' 变身'or' 待命'))end
        button(105+(slot-1)*235,0,225,label,function()
            if not f or s.hp<=0 then return end
            local active=c.state.active;if active then c:stop(player,'切换伙伴')end
            c:select(index);if active then c:enter(player)end
        end)
    end
    g.rect(0,40*scale,175*scale,360*scale,{30,35,75,180})
    g.rect(183*scale,40*scale,217*scale,360*scale,{30,35,75,180})
    g.rect(408*scale,40*scale,412*scale,360*scale,{30,35,75,180})
    text(8,47,'伙伴 '..#F..'/20',true)
    if not F.find(self.view)then self.view=F[1]and F[1].key end
    local _,scroll_y,_,view_h=g.begin_scroll('partners',5*scale,77*scale,165*scale,310*scale,165*scale,math.max(310,#F*68)*scale)
    scroll_y=(scroll_y or 0)/scale;view_h=(view_h or 310*scale)/scale
    for index,f in ipairs(F)do
        local y=(index-1)*68
        if y+64>scroll_y and y<scroll_y+view_h then
            local state=c.states[index];local selected=self.view==f.key
            card(0,y,153,62,selected)
            -- One hit area covers both the name and life row; dragging cancels clicks natively.
            local id=skin(selected and'selected'or'button')
            local clicked
            if id then clicked=g.image_button(id,0,y*scale,153*scale,62*scale,'',12)
            else clicked=g.button_at(0,y*scale,153*scale,62*scale,'')end
            if clicked then self.view=f.key;self.pending_skill=nil;self.release_confirm=nil end
            text(9,y+6,(c.profile:pet(f.key).favorite and'* 'or'')..short(f.name,8),selected,.73)
            text(9,y+34,'Lv.'..G.level(c.profile.xp[f.key])..'  '..state.hp..'/'..state.max,false,.65)
        end
    end
    g.end_scroll()
    button(186,359,100,'变身/解除',function()c:request('toggle')end)
    button(294,359,101,'捕获',function()if not c.state.active and(c.capture_cooldown or 0)==0 then c.capture_cooldown=30;c:request('capture')end end)
    local function draw_binding_settings()
        local config=self.input.bindings;local B=require('morph.bindings')
        local popup=self.binding_menu
        -- 1.9 draws all text in a final pass: never emit underlying labels for a popup.
        if not popup then
            text(420,82,'动作             按键一         按键二',true,.66)
            for row,a in ipairs(B.actions)do
                local y=111+(row-1)*38;local modifier,key=B.parts(config:get(a[1]))
                if self.binding_mods and self.binding_mods[a[1]]then modifier=self.binding_mods[a[1]]end
                local mn,kn='无','不替换'
                for _,m in ipairs(B.modifiers)do if m[1]==modifier then mn=m[2]end end
                for _,k in ipairs(B.keys)do if k[1]==key then kn=k[2]end end
                text(420,y+5,a[2],false,.65)
                button(512,y,135,mn..' v',function()self.binding_menu={action=a[1],kind='modifier',row=row}end)
                button(655,y,142,kn..' v',function()self.binding_menu={action=a[1],kind='key',row=row}end)
            end
            text(420,350,'例：捕获伙伴 → 下 + 跳跃',true,.67)
            text(420,374,'先按住按键一，再按按键二；组合优先',false,.61)
        end
        if popup then
            local action_name=popup.action
            for _,a in ipairs(B.actions)do if a[1]==popup.action then action_name=a[2]end end
            text(420,84,action_name..' · '..(popup.kind=='modifier'and'按键一'or'按键二'),true,.76)
            local options=popup.kind=='modifier'and B.modifiers or B.keys
            local x,w,y=420,378,118
            card(x-4,y-4,w+8,260,true)
            local _,sy,_,vh=g.begin_scroll('binding_options',x*scale,y*scale,w*scale,220*scale,w*scale,#options*34*scale)
            sy=(sy or 0)/scale;vh=(vh or 220*scale)/scale
            for n,option in ipairs(options)do local oy=(n-1)*34
                if oy+30>sy and oy<sy+vh then
                    button(0,oy,w-12,option[2],function()
                        local modifier,key=B.parts(config:get(popup.action))
                        self.binding_mods=self.binding_mods or{}
                        modifier=self.binding_mods[popup.action]or modifier
                        if popup.kind=='modifier'then modifier=option[1]else key=option[1]end
                        if key=='none'and popup.kind=='modifier'then
                            self.binding_mods[popup.action]=modifier;self.binding_menu=nil;c.status='请选择按键二';return
                        end
                        local ok,message=config:set(popup.action,modifier,key);c.status=message
                        if ok then self.binding_menu=nil;self.binding_mods[popup.action]=nil end
                    end)
                end
            end
            g.end_scroll()
            button(x,y+222,w, '关闭',function()self.binding_menu=nil end)
        end
    end
    local tabs={{'growth','培养'},{'skills','技能'},{'manage','管理'}}
    if self.input then tabs[#tabs+1]={'bindings','按键'}end
    local tw=396/#tabs
    for n,tab in ipairs(tabs)do
        button(415+(n-1)*tw,45,tw-6,tab[2],function()self.tab=tab[1];self.release_confirm=nil;self.binding_menu=nil end,self.tab==tab[1])
    end
    local f,index=F.find(self.view)
    if not f then
        if self.tab=='bindings'and self.input then draw_binding_settings();text(5,405,short(c.status,43),false,.62);return end
        text(198,90,c.profile.load_error and'档案异常，已停止覆盖保存' or'暂无伙伴')
        text(198,125,'靠近残血敌怪后捕获')
        text(5,405,short(c.status,42));return
    end
    local p=c.profile:pet(f.key);local state=c.states[index];local stats=c:stats(f.key,f.damage);local level=G.level(c.profile.xp[f.key])
    text(195,48,short(p.name,10),true)
    self:portrait(f,265*scale,73*scale,65*scale,36*scale)
    text(195,118,'Lv.'..level..' 生命 '..state.hp..'/'..state.max)
    text(195,145,'普攻 '..stats.damage..'  法术 '..stats.magic_damage)
    text(195,172,string.format('防御 %.1f  暴击 %.1f%%',stats.defense,stats.crit*100))
    text(195,199,string.format('移速 +%.1f%%',(stats.speed-1)*100))
    text(195,226,f.buoyant and'特性：液面浮力'or(f.swim and'特性：水生移动'or(f.phase and'特性：穿墙移动'or(f.flight and'特性：飞行'or'特性：地面移动'))))
    text(195,253,f.lava_immune and'熔岩免疫' or'熔岩不免疫')
    text(195,280,'基础生命 '..p.life..'  攻击 '..p.damage,false,.64)
    text(195,307,'基础防御 '..p.defense..(p.native and''or' · 待校正'),false,.64)
    if self.tab=='growth'then
        local xp=c.profile.xp[f.key];local gdata=c.profile.growth[f.key]
        text(420,82,level==30 and'满级 · 累计87点'or('经验 '..(xp-G.threshold(level))..'/'..(G.threshold(level+1)-G.threshold(level))))
        local draft=self.drafts[f.key]
        if not draft then draft={};for _,k in ipairs(G.keys)do draft[k]=gdata[k]end;self.drafts[f.key]=draft end
        text(420,109,'剩余属性点 '..G.points(xp,draft),true)
        local preview=G.stats(draft,p.life,f.damage,p.defense,level)
        local hints={str='每点：物理伤害 +1.5% · 击退 +1%',agi='每点：移速 +0.5% · 普攻间隔 -0.3%',
            vit='每点：最大生命 +6 · 防御 +0.5',int='每点：法术伤害 +1.5%',
            spi='每点：技能冷却 -0.4% · 异常时长 -0.5%',luk='每点：暴击率 +0.2% · 暴击伤害 +0.5%'}
        local rows={
            str={{'普攻',stats.damage,preview.damage},{'击退%',stats.knockback*100,preview.knockback*100}},
            agi={{'移速%',stats.speed*100,preview.speed*100},{'普攻间隔%',stats.attack_interval*100,preview.attack_interval*100}},
            vit={{'最大生命',stats.max_life,preview.max_life},{'防御',stats.defense,preview.defense}},
            int={{'法术伤害',stats.magic_damage,preview.magic_damage}},
            spi={{'冷却时间%',stats.cooldown*100,preview.cooldown*100},{'异常持续%',(1-stats.resistance)*100,(1-preview.resistance)*100}},
            luk={{'暴击率%',stats.crit*100,preview.crit*100},{'暴击伤害%',stats.crit_damage*100,preview.crit_damage*100}}}
        local _,sy,_,vh=g.begin_scroll('growth_'..f.key,415*scale,138*scale,395*scale,201*scale,395*scale,6*130*scale)
        sy=(sy or 0)/scale;vh=(vh or 201*scale)/scale
        for row,key in ipairs(G.keys)do
            local y=(row-1)*130
            if y+122>sy and y<sy+vh then
                card(0,y,383,122)
                text(12,y+9,G.labels[row]..'  '..draft[key],true,.80)
                button(287,y+7,36,'+',function()if not c.state.active and G.points(xp,draft)>0 then draft[key]=draft[key]+1 end end)
                button(333,y+7,36,'-',function()if not c.state.active and draft[key]>0 then draft[key]=draft[key]-1 end end)
                text(12,y+43,hints[key],false,.65)
                for n,r in ipairs(rows[key])do
                    text(12,y+66+(n-1)*24,string.format('%s  %.1f → %.1f',r[1],r[2],r[3]),r[2]~=r[3],.73)
                end
            end
        end
        g.end_scroll()
        button(420,349,180,'确认加点',function()if c:apply_points(f.key,draft)then self.drafts[f.key]=nil end end)
        button(612,349,180,'洗点',function()local clean={};for _,k in ipairs(G.keys)do clean[k]=0 end;if c:apply_points(f.key,clean)then self.drafts[f.key]=nil end end)
        text(420,380,c.state.active and'解除变身后可培养' or'上下滑动查看属性；确认后保存',false,.64)
    elseif self.tab=='bindings'and self.input then draw_binding_settings()
    elseif self.tab=='skills'then
        self.skill_stage=self.skill_stage or 1
        for stage,lv in ipairs(G.levels)do button(420+(stage-1)*130,83,120,lv..'级',function()self.skill_stage=stage;self.pending_skill=nil end)end
        local data=c.profile.growth[f.key];local stage=self.skill_stage;local id=data.choices[stage]
        if id then
            text(420,125,Skills.by_id[id].name,true)
            local d=Skills.by_id[id];local ss=c:stats(f.key,d.damage)
            text(420,145,string.format('伤害 %d  冷却 %.2f秒',(d.kind==44 or d.kind==174)and ss.magic_damage or ss.damage,d.cooldown*ss.cooldown/60),false,.64)
            button(420,159,175,'装备技能一',function()c:equip_skill(f.key,1,id)end)
            button(607,159,175,'装备技能二',function()c:equip_skill(f.key,2,id)end)
        elseif level<G.levels[stage]then text(420,130,'达到'..G.levels[stage]..'级后选择')
        else
            for row,option in ipairs(Skills.options(f.key,data,stage))do
                button(420,120+(row-1)*32,383,Skills.by_id[option].name,function()self.pending_skill={key=f.key,stage=stage,id=option}end)
            end
            local chosen=self.pending_skill
            if chosen and chosen.key==f.key and chosen.stage==stage then
                text(420,222,'待选 '..Skills.by_id[chosen.id].name,false,.66)
                button(420,247,170,'确认学习',function()if c:choose_skill(f.key,stage,chosen.id)then self.pending_skill=nil end end)
            end
        end
        for slot=1,2 do
            local name=data.equipped[slot]and Skills.by_id[data.equipped[slot]].name or'未装备'
            text(420,300+(slot-1)*28,'技能'..slot..' '..name,false,.66)
        end
        text(420,365,'攻击时随机释放；也可使用独立技能键',false,.64)
    else
        button(420,86,180,c.profile:is_equipped(f.key)and'移出出战队伍'or'加入出战队伍',function()c:equip(index,not c.profile:is_equipped(f.key))end)
        button(612,86,170,'选为变身伙伴',function()c:select(index)end)
        button(420,122,180,'复活这只伙伴',function()c:rescue(index)end)
        button(612,122,170,'复活全部伙伴',function()c:rescue_all()end)
        button(420,158,180,p.favorite and'取消收藏'or'收藏防止误放生',function()c:favorite(index)end)
        button(612,158,170,'改名',function()self.rename_target=f.key;self.rename_draft=p.name end)
        if self.rename_target==f.key then
            g.begin_scroll('rename',420*scale,200*scale,380*scale,80*scale,380*scale,80*scale)
            g.set_cursor(0,0);self.rename_draft=g.input_text('名称',self.rename_draft)
            g.end_scroll()
            button(420,290,150,'保存名字',function()
                local name=self.rename_draft or''
                if #name>0 and #name<=64 and not name:find('%c')and utf8.len(name)and utf8.len(name)<=16 then p.name=name;f.name=name;c.profile.dirty=true;c:save();self.rename_target=nil end
            end)
        else
            button(420,200,180,'放生',function()self.release_confirm=f.key end)
            if self.release_confirm==f.key then
                text(420,242,'放生将删除这只伙伴的培养记录',true,.49)
                button(420,272,180,'确认放生',function()if c:release(index)then self.release_confirm=nil;self.view=nil end end)
                button(612,272,170,'取消',function()self.release_confirm=nil end)
            end
        end
        text(420,345,home and'位于出生点，可换队和复活'or'返回出生点后才能换队与复活',false,.64)
        text(420,369,'携带3只 · 经验100% / 30% / 30%',false,.64)
    end
    text(5,405,short(c.status,43),false,.62)
end
return Panel
