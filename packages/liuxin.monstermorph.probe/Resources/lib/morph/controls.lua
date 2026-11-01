-- Shared actions: native editor when available, mod-owned bar on LuaLoader 1.9.
local Forms=require('morph.forms')
local Controls={}
Controls.__index=Controls
local definitions={{id='transform',name='怪物变身'},{id='cycle',name='切换怪物'},
    {id='capture',name='捕获怪物'},{id='skill',name='怪物技能'},
    {id='learned_1',name='学习技能一'},{id='learned_2',name='学习技能二'}}
for _,definition in ipairs(definitions) do
    definition.icon='icons/'..definition.id..'.png';definition.show_label=true
end
function Controls.new(api,bridge,controller,read,write)
    local legacy=not(api and type(api.available)=='function')
    if legacy then
        local entries={}
        api={available=function()return true end}
        function api.register(d)entries[d.id]={visible=false,enabled=true}end
        function api.unregister(id)entries[id]=nil end
        function api.set_visible(id,value)local e=entries[id];if e then e.visible=value;if not value then e.pending=false end end end
        function api.set_enabled(id,value)local e=entries[id];if e then e.enabled=value;if not value then e.pending=false end end end
        function api.pressed(id)local e=entries[id];if not e then return false end;local hit=e.pending and e.visible and e.enabled;e.pending=false;return hit or false end
        function api.trigger(id)local e=entries[id];if e and e.visible and e.enabled then e.pending=true;return true end;return false end
        function api.state(id)return entries[id]end
    end
    local ok,reason=api.available();assert(ok,'原版按键接口不可用：'..tostring(reason))
    local self=setmetatable({api=api,b=bridge,c=controller,registered={},legacy=legacy,images={},bindings=require('morph.bindings').new(bridge,read,write)},Controls)
    local registered,err=pcall(function()
        for _,definition in ipairs(definitions) do api.register(definition);self.registered[#self.registered+1]=definition.id end
    end)
    if not registered then self:cleanup();error(err) end
    return self
end
function Controls:poll(player)
    local api,c=self.api,self.c
    local valid=self.b:valid(player)
    for _,definition in ipairs(definitions) do api.set_visible(definition.id,valid) end
    if not valid then self.bindings:reset();return end
    local function pressed(id)local hit=api.pressed(id);return self.bindings:take(id)or hit end
    api.set_enabled('capture',not c.state.active and (c.capture_cooldown or 0)==0)
    api.set_enabled('skill',c.state.active and (self.b.cooldown or 0)==0)
    for slot=1,2 do
        local id='learned_'..slot;local runtime=self.b.learned
        api.set_enabled(id,c.state.active and runtime~=nil and runtime.ids[slot]~=nil and runtime.cooldowns[slot]==0)
        if pressed(id) and c.state.active and runtime and runtime.ids[slot] and runtime.cooldowns[slot]==0 then
            self.b.learned_requests=self.b.learned_requests or {};self.b.learned_requests[slot]=true
        end
    end
    if pressed('transform') then self.b:trace_input('ACTION_PRESS transform');c:request(not c.state.active and c.state.hp<=0 and 'recover' or 'toggle') end
    if pressed('cycle') then self.b:trace_input('ACTION_PRESS cycle');c:request('next') end
    if pressed('capture') and not c.state.active and (c.capture_cooldown or 0)==0 then self.b:trace_input('ACTION_PRESS capture');c:request('capture');c.capture_cooldown=30 end
    if pressed('skill') and c.state.active and (self.b.cooldown or 0)==0 then
        if Forms[c.index]and Forms[c.index].kind=='skeleton' then self.b.gui_bone=true else self.b.gui_skill=true end
    end
end
-- LuaLoader 1.9 has image widgets but no mod.controls registration API.
-- GUI events enqueue the same action IDs; gameplay consumes them on the next update.
function Controls:draw_bar(g,scale,native,open)
    g.set_title('伙伴动作','伴');g.set_width(420*scale);g.set_content_height(96*scale)
    local labels={self.c.state.active and'解除'or'变身','切换','捕获','技能','技能一','技能二'}
    local function image(path)
        if self.images[path]==nil then self.images[path]=g.load_image(path)or false end
        local id=self.images[path];if id and g.image_status(id)=='ready'then return id end
    end
    local bg=image('ui/button.png')
    for i,d in ipairs(definitions)do
        local x=5+(i-1)*56;local entry=self.api.state(d.id);local enabled=entry and entry.enabled
        local clicked
        if bg then clicked=g.image_button(bg,x*scale,2*scale,48*scale,44*scale,'',12)
        else clicked=g.button_at(x*scale,2*scale,48*scale,44*scale,'')end
        local icon=image(d.icon);if icon then g.image(icon,(x+6)*scale,6*scale,36*scale,36*scale,enabled and{255,255,255,255}or{100,110,140,255})end
        local cooldown=i==4 and(self.b.cooldown or 0)or(i>=5 and self.b.learned and self.b.learned.cooldowns[i-4]or 0)
        local label=cooldown and cooldown>0 and tostring(math.ceil(cooldown/60))..'s'or labels[i]
        g.text_at((x+6)*scale,48*scale,label,enabled and{245,247,255,255}or{135,145,175,255},.60*scale/native)
        if clicked then self.api.trigger(d.id)end
    end
    local clicked
    if bg then clicked=g.image_button(bg,345*scale,9*scale,65*scale,40*scale,'',12)
    else clicked=g.button_at(345*scale,9*scale,65*scale,40*scale,'')end
    g.text_at(354*scale,18*scale,'伙伴',{255,222,140,255},.76*scale/native)
    if clicked then open()end
    local notice=self.c.status or'';local cut=utf8.offset(notice,27);if cut then notice=notice:sub(1,cut-1)..'…'end
    g.text_at(5*scale,74*scale,notice,{255,222,140,255},.60*scale/native)
end
function Controls:cleanup()
    self.bindings:reset()
    for _,id in ipairs(self.registered) do pcall(self.api.unregister,id) end
    self.registered={}
end
return Controls
