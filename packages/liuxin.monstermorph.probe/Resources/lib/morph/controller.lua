local State=require('morph.state')
local F=require('morph.forms')
local Profile=require('morph.profile')
local G=require('morph.growth')
local Skills=require('morph.skills')
local C={};C.__index=C
function C.new(b,log,profile)
    local self=setmetatable({b=b,log=log,profile=profile or Profile.new(F),states={},by_id={},tick=0,last_combat=0,
        status='伙伴库20只，出战最多3只；出生点调整队伍与复活'},C)
    self:rebuild();return self
end
function C:rebuild()
    local old=self.by_id;self.states={};self.by_id={}
    for i,f in ipairs(F)do
        local s=old[f.key] or State.new(self:stats(f.key,f.damage).max_life)
        s.max=self:stats(f.key,f.damage).max_life;s.hp=math.min(s.max,self.profile.hp[f.key] or s.max)
        self.states[i]=s;self.by_id[f.key]=s
    end
    local _,index=F.find(self.profile.selected);self.index=index or 0
    self.state=self.states[self.index] or State.new(1)
end
function C:form()return F[self.index]end
function C:notify(s)if self.b.message then pcall(self.b.message,self.b,s)end end
function C:save()if self.profile.dirty then return self.profile:save()end;return true end
function C:sync_profile()
    for key,s in pairs(self.by_id)do self.profile.hp[key]=s.hp;self.profile.max[key]=s.max end
    self.profile.dirty=true
end
function C:stats(key,damage)
    local p=self.profile:pet(key)
    if not p then return G.stats({},100,damage or 0,0,1)end
    return G.stats(self.profile.growth[key],p.life,damage or p.damage,p.defense,G.level(self.profile.xp[key]))
end
function C:damage(key,base,kind)
    local s=self:stats(key,base);local value=(kind==44 or kind==174 or kind==176) and s.magic_damage or s.damage
    if (self.random or math.random)()<s.crit then value=math.floor(value*s.crit_damage+.5)end
    return value
end
function C:refresh_growth(key)
    local s=self.by_id[key];if not s then return end
    s.max=self:stats(key).max_life;s.hp=math.min(s.hp,s.max)
    self.profile.max[key],self.profile.hp[key]=s.max,s.hp
end
function C:add_xp(key,amount)
    if not self.state.active or not self:form() or self:form().key~=key or amount<=0 then return end
    amount=math.floor(amount);self.last_combat=self.tick
    local leveled=false
    local function award(id,n)
        local old=G.level(self.profile.xp[id]);self.profile.xp[id]=math.min(G.threshold(30),self.profile.xp[id]+n)
        if G.level(self.profile.xp[id])>old then self:refresh_growth(id);leveled=true end
    end
    award(key,amount)
    for _,id in ipairs(self.profile.equipped)do
        if id~=key and self.by_id[id] and self.by_id[id].hp>0 then
            local p=self.profile:pet(id);local share=(p.share or 0)+amount*3
            award(id,math.floor(share/10));p.share=share%10
        end
    end
    self.profile.dirty=true
    if leveled then self.status='伙伴升级，有新的属性点或技能可领取';self:notify(self.status);self:sync_profile();self:save()end
end
function C:apply_points(key,draft)
    if self.state.active or not self.profile:pet(key)then return false end
    local clean=G.clean(draft,self.profile.xp[key]);local data=self.profile.growth[key]
    for _,k in ipairs(G.keys)do if draft[k]~=clean[k]then return false end end
    for _,k in ipairs(G.keys)do data[k]=clean[k]end
    self:refresh_growth(key);self.profile.dirty=true
    self.status=self:save()and'培养已保存'or'保存失败，稍后重试';return true
end
function C:choose_skill(key,stage,id)
    if self.state.active or not self.profile:pet(key)or not Skills.choose(key,self.profile.growth[key],self.profile.xp[key],stage,id)then return false end
    self.profile.dirty=true;self.status=self:save()and'技能已学习'or'保存失败，稍后重试';return true
end
function C:equip_skill(key,slot,id)
    if self.state.active or not self.profile:pet(key)or(slot~=1 and slot~=2)then return false end
    local g=self.profile.growth[key];local learned=false
    for i=1,3 do if g.choices[i]==id then learned=true end end;if not learned then return false end
    for i=1,2 do if g.equipped[i]==id then g.equipped[i]=nil end end
    g.equipped[slot]=id;self.profile.dirty=true;self:save();return true
end
function C:capture_input(player)
    local held=self.b:get('Player','controlDown',player,'bool')and self.b:pressed(player,'use','controlUseItem')
    if held and not self.capture_held and(self.capture_cooldown or 0)==0 then self.capture_held=true;self.capture_cooldown=30;self:capture_nearby(player);return true end
    self.capture_held=held;return false
end
function C:capture_nearby(player)
    if self.state.active then return false end
    if #self.profile.pets>=20 then self.status='伙伴已满20只，请先放生';self:notify(self.status);return false end
    self.log('CAPTURE scan_begin')
    local snapshot,token,reason=self.b:scan_capture(player)
    self.log('CAPTURE scan_ready result='..tostring(reason or(snapshot and snapshot.npc)))
    if not snapshot then
        local messages={health='目标血量需在25%以内',distance='请靠近到160像素内',boss='Boss暂不开放捕获',empty='附近没有可捕获敌怪',released='刚放生的怪物暂时不能捕获'}
        self.status=messages[reason]or messages.empty;self:notify(self.status);return false
    end
    self:sync_profile();local pet=self.profile:add(snapshot);self:rebuild();self.log('CAPTURE profile_ready')
    if not self.profile:save()then self.profile:remove(pet.id);self:rebuild();self.status='保存失败，目标未被移除';return false end
    self.log('CAPTURE saved')
    if not self.b:consume_capture(token)then self.profile:remove(pet.id);self:rebuild();self.profile:save();self.status='目标状态改变，捕获取消';return false end
    self.log('CAPTURE consumed')
    self.status='捕获成功：'..pet.name..'（'..#self.profile.pets..'/20）';self:notify(self.status);return true
end
function C:select(index)
    local f=F[index]
    if not f or self.state.active or not self.profile:is_equipped(f.key)then return false end
    self.index=index;self.state=self.states[index];self.profile.selected=f.key;self.profile.dirty=true;self:save();return true
end
function C:equip(index,enabled)
    local player=self.b:local_player();local f=F[index]
    if not f or self.state.active or not player or not self.b:at_base(player)then self.status='只能在出生点解除变身后调整队伍';return false end
    if enabled and self.states[index].hp<=0 then self.status='请先在出生点复活这只伙伴';return false end
    if not self.profile:set_equipped(f.key,enabled)then self.status='出战队伍最多3只';return false end
    self:sync_profile();self:rebuild();self:save();return true
end
function C:rescue(index)
    local player=self.b:local_player();local f=F[index]
    if not f or self.state.active or not player or not self.b:at_base(player)then self.status='请回出生点解除变身后复活';return false end
    local s=self.states[index];if s.hp>0 then return false end
    s.hp=s.max;self.profile:pet(f.key).heal=0;self:sync_profile();self:save();self.status='伙伴已复活并恢复满血';return true
end
function C:rescue_all()
    local n=0;for i,s in ipairs(self.states)do if s.hp<=0 and self:rescue(i)then n=n+1 end end;return n
end
function C:release(index)
    local f=F[index];if not f then return false end
    local pet=self.profile:pet(f.key);if pet.favorite then self.status='请先取消收藏';return false end
    local player=self.b:local_player();if not player or not self.b:valid(player)then return false end
    if self.state.active then self:stop(player,'放生前恢复人形')end
    local token=self.b:release_pet(player,pet)
    if not token then self.status='没有安全位置或怪物槽位，伙伴保留';return false end
    self:sync_profile();self.profile:flush()
    local oldpets={};for i,p in ipairs(self.profile.pets)do oldpets[i]=p end
    local oldteam={};for i,id in ipairs(self.profile.equipped)do oldteam[i]=id end
    local selected=self.profile.selected
    self.profile:remove(pet.id);self:rebuild()
    if not self.profile:save()then
        self.b:undo_release(token);self.profile.pets=oldpets;self.profile.equipped=oldteam;self.profile.selected=selected
        self.profile:rebuild();self:rebuild();self.status='保存失败，放生已撤销';return false
    end
    self.status='已放生 '..pet.name;return true
end
function C:favorite(index)
    local f=F[index];if not f then return end
    local p=self.profile:pet(f.key);p.favorite=not p.favorite;self.profile.dirty=true;self:save()
end
function C:enter(player)
    local f=self:form()
    if not f or not self.profile:is_equipped(f.key)then self.status='请在出生点配置出战伙伴';return end
    if self.state.hp<=0 then self.status='伙伴倒下，请回出生点复活';return end
    self.log('TRANSFORM begin id='..f.key..' npc='..f.npc)
    if not self.b:spawn(player,f)then self.status='变身失败，伙伴已保留';return end
    self.log('TRANSFORM proxy_ready')
    local pet=self.profile:pet(f.key)
    if not pet.native and self.b.native_snapshot then
        local raw=self.b.native_defaults
        if raw then
            local ratio=self.state.hp/math.max(1,self.state.max)
            for _,k in ipairs({'life','damage','defense','ai','width','height','nogravity','phase','lava','immunities'})do pet[k]=raw[k]end
            pet.native=true;self.profile.base[f.key]=pet.life;self.profile:flush()
            self.profile:rebuild();self:rebuild();self.state.hp=math.max(1,math.floor(self.state.max*ratio))
            self.profile.hp[pet.id]=self.state.hp;self.b:remove()
            self.log('TRANSFORM normalized_respawn_begin')
            if not self.b:spawn(player,self:form())then self.status='外观初始化失败';return end
        end
    end
    self.log('TRANSFORM activate')
    self.state:activate();self.status='变身：'..self:form().name;self:sync_profile();self:save()
end
function C:cycle(player)
    local active=self.state.active;if active then self:stop(player,'切换伙伴')end
    local team=self.profile.equipped;local start=0
    for i,id in ipairs(team)do if id==self.profile.selected then start=i end end
    for step=1,#team do
        local id=team[(start+step-1)%#team+1];local _,index=F.find(id)
        if index and self.states[index].hp>0 then self:select(index);if active then self:enter(player)end;return end
    end
    self.status='携带伙伴均已倒下，请返回出生点'
end
function C:restore_human_max(player)
    if self.human_max and self.max_player==player then self.b:set('Player','statLifeMax2',player,self.human_max,'int32')end
    self.human_max,self.max_player=nil,nil
end
function C:stop(player,reason)
    local human=self.state:cancel();if human and player then self.b:set_life(player,human)end
    self:restore_human_max(player);self.b:remove();self.command=nil;self.status=reason or'已恢复人形'
    self:sync_profile();self:save()
end
function C:begin(player)
    if self.state.depth==0 then self.human_max=self.b:max_life(player);self.max_player=player end
    self.b:set('Player','statLifeMax2',player,self.state.max,'int32')
    local hp=self.state:begin(self.b:life(player));if hp then self.b:set_life(player,hp)end
end
function C:finish(player)
    if self.state.depth==0 then return end
    local human,broken=self.state:finish(self.b:life(player));if human then self.b:set_life(player,human)end
    if self.state.depth==0 then self:restore_human_max(player)end
    local f=self:form();if f then self.profile.hp[f.key]=self.state.hp end
    if broken then self.b:remove();self.b:protect(player);self.status='伙伴倒下，请回出生点复活';self:sync_profile();self:save()end
end
function C:recovery(player)
    local home=self.b:at_base(player);local rested=self.tick-self.last_combat>=300
    for _,p in ipairs(self.profile.pets)do
        local s=self.by_id[p.id];local rate=0
        if s.hp>0 and s.hp<s.max then
            if home then rate=50 elseif rested and self.profile:is_equipped(p.id)then rate=self.state.active and self:form().key==p.id and 5 or 10 end
            if rate>0 then
                p.heal=(p.heal or 0)+s.max*rate;local gain=math.floor(p.heal/1000);p.heal=p.heal%1000
                s.hp=math.min(s.max,s.hp+gain);self.profile.hp[p.id]=s.hp;self.profile.dirty=true
            end
        else p.heal=0 end
    end
end
function C:pre_update(player)
    self.update_valid=false
    self.capture_cooldown=math.max(0,(self.capture_cooldown or 0)-1)
    if not self.b:valid(player)then if self.state.active or self.state.depth>0 then self:stop(player,'已退出变身')end;self.command=nil;return end
    self.update_valid=true;self.tick=self.tick+1
    -- Never allocate a temporary NPC during world entry/Player.Update.
    -- Legacy defaults are read from the actual proxy only after explicit transform.
    if self.state.active and not self.b:has_proxy()then self:stop(player,'外观失效，恢复人形');return end
    local command=self.command;self.command=nil
    if command=='next'then self:cycle(player)
    elseif command=='toggle'then if self.state.active then self:stop(player)else self:enter(player)end
    elseif command=='capture'and not self.state.active then self:capture_nearby(player)
    elseif command=='recover'then self:rescue(self.index)end
    if self.state.active then self:begin(player);self.b:input()end
end
function C:post_update(player)
    self:finish(player)
    if not self.update_valid then return end
    if self.state.active then self.b:sync(player,self.tick);self.b:attack(player,self.tick)end
    if self.tick%60==0 then self:recovery(player)end
    if self.tick%300==0 and self.profile.dirty then self:sync_profile();self:save()end
end
function C:pre_hurt(player)if self.state.active then self.last_combat=self.tick;self:begin(player)end end
function C:post_hurt(player)self:finish(player)end
function C:kill(player)
    if not self.state.active then return false end
    self.state:defeat();if self.state.depth>0 then self.b:set_life(player,0)else self:stop(player,'伙伴倒下');self.b:protect(player)end;return true
end
function C:request(command)self.command=command end
return C
