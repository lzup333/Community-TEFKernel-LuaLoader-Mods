-- Android arm64 only. All hooks below have primitive/reference parameters.
-- In particular, do NOT hook DrawPlayer(... Vector2 ...) through patchlib.
local Bridge={}
Bridge.__index=Bridge
local Forms=require('morph.forms')
local Flight=require('morph.flight')
local Animation=require('morph.animation')
local Melee=require('morph.melee')
local World=require('morph.world')
local Traits=require('morph.traits')
local Combat=require('morph.combat')

local function required(v,name) assert(v,'缺少接口：'..name);return v end

function Bridge.new(p)
    local self=setmetatable({p=p,hooks={},form=Forms[1],charge=0,charging=false,cooldown=0,attack_ticks=0,hits={}},Bridge)
    local function ty(ns,name) return required(p.get_type(ns,name),ns..'.'..name) end
    self.types={Main=ty('Terraria','Main'),Player=ty('Terraria','Player'),
        Entity=ty('Terraria','Entity'),NPC=ty('Terraria','NPC'),
        Source=ty('Terraria.DataStructures','EntitySource_DebugCommand'),
        Renderer=ty('Terraria.Graphics.Renderers','LegacyPlayerRenderer'),
        Mount=ty('Terraria','Mount'),Item=ty('Terraria','Item'),
        Collision=ty('Terraria','Collision'),Controls=ty('','GUIVirtualInputController'),
        Hearts=ty('','GUIHearts'),WorldGen=ty('Terraria','WorldGen'),Projectile=ty('Terraria','Projectile')}
    self.fields={}
    local function fields(group,names)
        self.fields[group]={}
        for name in names:gmatch('%S+') do
            self.fields[group][name]=required(p.get_field(self.types[group],name),group..'.'..name)
        end
    end
    fields('Entity','whoAmI position velocity width height direction wet lavaWet honeyWet')
    fields('Player','active dead ghost statLife statLifeMax statLifeMax2 controlJump controlUseItem controlMount controlQuickHeal controlQuickMana controlQuickBuff controlHook controlInv controlUseTile controlSmart controlTorch jump immune immuneTime gravDir grapCount pulley mount controlUp controlDown controlLeft controlRight gravity noFallDmg endurance maxRunSpeed accRunSpeed runAcceleration SpawnX SpawnY statDefense lavaImmune breath breathMax buffImmune')
    fields('NPC','active type friendly dontTakeDamage dontCountMe aiStyle damage life lifeMax timeLeft netUpdate frameCounter boss townNPC realLife netID defense noGravity noTileCollide lavaImmune buffImmune rotation ai')
    fields('Main','player npc projectile netMode maxTilesX maxTilesY debuff npcFrameCount')
    fields('Projectile','friendly hostile timeLeft')
    fields('Item','accessory type stack damage consumable pick axe hammer createTile createWall')
    fields('Controls','Pressed WasPressed wasFireButtonFiring UseButtonPressed')
    self.readers={}
    for _,name in ipairs({'myPlayer','gameMenu','screenWidth','screenHeight','spawnTileX','spawnTileY'}) do
        local f=p.get_field(self.types.Main,name)
        local getter=not f and p.get_method(self.types.Main,'get_'..name,0)
        required(f or getter,'Main.'..name)
        self.readers[name]={field=f,getter=getter,kind=name=='gameMenu' and 'bool' or 'int32'}
    end
    self.methods={}
    for key,spec in pairs({held_item={'Player','get_HeldItem',0},new={'NPC','NewNPC',10},frame={'NPC','FindFrame',0},
        strike={'NPC','StrikeNPC',6},update={'Player','Update',1},hurt={'Player','Hurt',8},
        kill={'Player','KillMe',4},item={'Player','ItemCheck',0},npc_update={'NPC','UpdateNPC',1},
        draw={'Renderer','DrawPlayers',2},mount_active={'Mount','get_Active',0},source_ctor={'Source','.ctor',0},
        equip_check={'Player','UpdateEquips_CanItemGrantBenefits',2},
        equip_apply={'Player','ApplyEquipFunctional',2},equip_prefix={'Player','GrantPrefixBenefits',1},
        quick_mount={'Player','QuickMount',0},quick_heal={'Player','QuickHeal',0},quick_mana={'Player','QuickMana',0},quick_buff={'Player','QuickBuff',0},quick_grapple={'Player','QuickGrapple',0},hearts={'Hearts','Draw',0},
        projectile_damage={'Projectile','Damage',0},resize={'Player','ResizeHitbox',0},horizontal={'Player','HorizontalMovement',0},dry_collision={'Player','DryCollision',2},wet_collision={'Player','WetCollision',3},slope_collision={'Player','SlopingCollision',2},
        jump_move={'Player','JumpMovement',0},
        controls_update={'Controls','Update',1},ground={'WorldGen','SolidOrSlopedTile',3},
        reset={'Player','ResetEffects',0},new_projectile={'Projectile','NewProjectile',13},world_update={'Main','Update',1}}) do
        self.methods[key]=required(p.get_method(self.types[spec[1]],spec[2],spec[3]),spec[1]..'.'..spec[2])
    end
    World.bind(self)
    return self
end

function Bridge:get(group,name,obj,kind)
    return self.p.get_field_value(self.fields[group][name],obj,kind)
end
function Bridge:set(group,name,obj,value,kind)
    self.p.set_field_value(self.fields[group][name],obj,value,kind)
end
function Bridge:vec(name,obj) return self.p.get_field_vec2(self.fields.Entity[name],obj) end
function Bridge:set_vec(name,obj,x,y) self.p.set_field_vec2(self.fields.Entity[name],obj,x,y) end
function Bridge:main(name)
    local r=self.readers[name]
    if r.field then return self.p.get_field_value(r.field,nil,r.kind) end
    return self.p.invoke(r.getter)
end
function Bridge:local_player()
    local a=self:get('Main','player',nil,'object')
    local i=self:main('myPlayer')
    if not a or type(i)~='number' or i<0 or i>=self.p.array_length(a) then return nil end
    return self.p.array_at(a,i)
end
function Bridge:is_local(player) return player and player==self:local_player() end
function Bridge:single_world()
    return not self:main('gameMenu') and self:get('Main','netMode',nil,'int32')==0
end
function Bridge:valid(player)
    if not self:single_world() or not self:is_local(player) then return false end
    if not self:get('Player','active',player,'bool') or self:get('Player','dead',player,'bool')
        or self:get('Player','ghost',player,'bool') then return false end
    if self:get('Player','gravDir',player,'float')~=1
        or self:get('Player','grapCount',player,'int32')>0
        or self:get('Player','pulley',player,'bool') then return false end
    local mount=self:get('Player','mount',player,'object')
    return not mount or not self.p.invoke(self.methods.mount_active,mount)
end
function Bridge:life(player) return self:get('Player','statLife',player,'int32') end
function Bridge:set_life(player,n) self:set('Player','statLife',player,n,'int32') end
function Bridge:max_life(player) return self:get('Player','statLifeMax2',player,'int32') end
function Bridge:base_life(player) return self:get('Player','statLifeMax',player,'int32') end
function Bridge:block_accessory(player,item,active)
    return active and self:is_local(player) and item~=nil
end
function Bridge:message(text)
    -- Feedback stays in our GUI; no managed text/string invocation in an action callback.
    self.notice=text
end

function Bridge:proxy()
    if not self.proxy_index then return nil end
    local a=self:get('Main','npc',nil,'object')
    if not a or a~=self.proxy_array or self.proxy_index>=self.p.array_length(a) then return nil end
    local n=self.p.array_at(a,self.proxy_index)
    -- The identity is compared only, never dereferenced after leaving its array.
    if n~=self.proxy_identity then return nil end
    if not self:get('NPC','active',n,'bool') or self:get('NPC','type',n,'int32')~=self.proxy_type
        or not self:get('NPC','friendly',n,'bool')
        or not self:get('NPC','dontTakeDamage',n,'bool')
        or not self:get('NPC','dontCountMe',n,'bool')
        or self:get('NPC','aiStyle',n,'int32')~=self.proxy_ai then return nil end
    return n
end
function Bridge:is_appearance(n,index)
    if index==self.proxy_index then return self:proxy()==n end
    local part=self.body_map and self.body_map[index]
    if part and part.object==n and self:get('Main','npc',nil,'object')==part.array then
        return self:get('NPC','active',n,'bool')and self:get('NPC','type',n,'int32')==part.kind and self:get('NPC','friendly',n,'bool')and self:get('NPC','dontTakeDamage',n,'bool')
    end
    return false
end
function Bridge:has_proxy() return self:proxy()~=nil end
function Bridge:remove()
    local boss_error
    if self.boss_runtime then
        local boss=self.boss_runtime;self.boss_runtime=nil
        local ok,err=pcall(boss.cleanup,boss);if not ok then boss_error=err end
    end
    if self.normal_runtime then
        local runtime=self.normal_runtime;self.normal_runtime=nil
        local ok,err=pcall(runtime.cleanup,runtime);if not ok then boss_error=boss_error or err end
    end
    if self.learned then
        local runtime=self.learned;self.learned=nil
        local ok,err=pcall(runtime.cleanup,runtime);if not ok then boss_error=boss_error or err end
    end
    self.learned_requests={};self.hit_form=nil;self.shot_context={}
    Traits.restore(self)
    self:restore_growth()
    Flight.restore(self)
    local n=self:proxy()
    if n then self:set('NPC','active',n,false,'bool') end
    self.proxy_index,self.proxy_array,self.proxy_identity,self.proxy_type=nil,nil,nil,nil
    self.proxy_ai=nil
    self.charging,self.charge,self.last_jump=false,0,false
    self.attack_ticks,self.cooldown,self.touch=0,0,nil
    self.gui_bone,self.gui_skill=false,false
    self.last_use=false
    self.boss_skill_request=false;self.boss_dash_request=false
    self.seen_jump,self.seen_use=false,false
    self.rush_vx,self.rush_vy=nil,nil
    self.hits={}
    if boss_error then error(boss_error) end
end
function Bridge:spawn(player,form)
    local function mark(s)if self.trace then self.trace('TRANSFORM '..s)end end
    mark('spawn_begin')
    form=form or self.form or Forms[1]
    if form.enabled==false then return false end
    local frame_counts=self:get('Main','npcFrameCount',nil,'object')
    if not frame_counts or form.npc<1 or form.npc>=self.p.array_length(frame_counts)or(form.netid and(form.netid< -66 or form.netid>=self.p.array_length(frame_counts)))then return false end
    local px,py=self:vec('position',player);local pw,ph=self:get('Entity','width',player,'int32'),self:get('Entity','height',player,'int32')
    mark('space_check_begin')
    self.space_trace=mark
    local clear=form.phase or self:space_clear(px+(pw-form.width)/2,py+ph-form.height,form.width,form.height)
    self.space_trace=nil
    if not clear then return false end
    mark('space_check_ready');mark('previous_proxy_remove_begin')
    self:remove();mark('previous_proxy_remove_ready')
    self.form=form
    if form.phase then local x,y=self:vec('position',player);self.last_clear={x=x,y=y}end
    if self.form.boss then
        assert(self.form.boss=='empress','未知 Boss 形态')
        self.boss_runtime=require('morph.bosses.empress').new(self)
    end
    if self.learned_ids then self.learned=require('morph.learned').new(self,self.learned_ids(self.form.key)) end
    if self.form.kind=='skeleton' then self.normal_runtime=require('morph.skeleton').new(self)
    elseif self.form.projectile then self.normal_runtime=require('morph.ranged').new(self) end
    local a=self:get('Main','npc',nil,'object')
    if not a then return false end
    mark('source_construct_begin')
    local source=required(self.p.construct(self.methods.source_ctor),'EntitySource_DebugCommand 实例')
    mark('source_construct_ready')
    local x,y=self:vec('position',player)
    mark('npc_new_begin')
    local index=self.p.invoke(self.methods.new,source,math.floor(x),math.floor(y),self.form.netid or self.form.npc,0,0.0,0.0,0.0,0.0,255)
    mark('npc_new_ready index='..tostring(index))
    -- Index 200 is Terraria's failure sentinel; array may contain that extra slot.
    if type(index)~='number' or index<0 or index>=200 or index>=self.p.array_length(a) then return false end
    local n=self.p.array_at(a,index)
    if not n then return false end
    mark('snapshot_begin')
    self.native_defaults=self:native_snapshot(n);mark('snapshot_ready')
    if self.native_defaults.npc~=self.form.npc or self:is_boss(n)then self:set('NPC','active',n,false,'bool');return false end
    local ok,err=pcall(function()
        for _,name in ipairs({'friendly','dontTakeDamage','dontCountMe'}) do self:set('NPC',name,n,true,'bool') end
        -- Keep the tested slime path. New forms keep the defaults chosen by
        -- the game so FindFrame can select their original animation rules.
        -- UpdateNPC is intercepted for this owned proxy, so its AI never runs.
        if self.form.kind=='slime' then self:set('NPC','aiStyle',n,-1,'int32') end
        self:set('NPC','damage',n,0,'int32')
        self:set('NPC','netUpdate',n,false,'bool')
        self.proxy_index,self.proxy_array,self.proxy_identity=index,a,n
        self.proxy_type=self.form.npc
        self.proxy_ai=self:get('NPC','aiStyle',n,'int32')
        mark('resize_begin');Traits.resize(self,player);mark('resize_ready')
        if self.boss_runtime then self.boss_runtime:configure(n) end
        mark('sync_begin');self.spawn_trace=mark;self:sync(player,0);self.spawn_trace=nil;mark('sync_ready')
    end)
    self.spawn_trace=nil
    if not ok then
        self:set('NPC','active',n,false,'bool')
        self.proxy_index,self.proxy_array,self.proxy_identity,self.proxy_type=nil,nil,nil,nil
        self.proxy_ai=nil
        error(err)
    end
    return true
end
function Bridge:sync(player)
    local n=required(self:proxy(),'史莱姆外观对象')
    local x,y=self:vec('position',player)
    local w,h=self:get('Entity','width',player,'int32'),self:get('Entity','height',player,'int32')
    local nw,nh=self:get('Entity','width',n,'int32'),self:get('Entity','height',n,'int32')
    self:set_vec('position',n,x+(w-nw)/2,self.form.anchor=='center' and y+(h-nh)/2 or y+h-nh)
    local vx,vy=self:vec('velocity',player)
    self:set_vec('velocity',n,vx,vy)
    self:set('Entity','direction',n,self:get('Entity','direction',player,'int32'),'int32')
    self:set('NPC','timeLeft',n,750,'int32')
    if self.boss_runtime then self.boss_runtime:animate(n,player) end
    Animation.step(self,n,self.form,self.attack_ticks>0)
    if self.spawn_trace then self.spawn_trace('frame_invoke_begin')end
    self.p.invoke(self.methods.frame,n)
    if self.spawn_trace then self.spawn_trace('frame_invoke_ready')end
    if self.normal_runtime then self.normal_runtime:animate(n,player) end
    Traits.animate(self,player)
end
function Bridge:protect(player)
    self:set('Player','immune',player,true,'bool')
    self:set('Player','immuneTime',player,math.max(60,self:get('Player','immuneTime',player,'int32')),'int32')
end

function Bridge:trace_input(message)
    if self.trace and (self.trace_count or 0)<60 then
        self.trace_count=(self.trace_count or 0)+1
        self.trace(message)
    end
end

function Bridge:input()
    -- Update entry owns timing only. Do not sample or clear this frame's input
    -- before vanilla has populated it inside Player.Update.
    self.input_tick=(self.input_tick or 0)+1
    if self.cooldown>0 then self.cooldown=self.cooldown-1 end
    if self.boss_runtime then self.boss_runtime:tick() end
    if self.normal_runtime then self.normal_runtime:tick() end
    if self.learned then self.learned:tick() end
end

function Bridge:capture_controls(instance)
    local a=self:get('Controls','Pressed',instance,'object')
    if not a or self.p.array_length(a)<=11 then self.touch=nil;return end
    -- GUIVirtualInputController.ControlType from the supplied PE symbols:
    -- Jump=2, Fire=11. Read held state, not JumpTapPressed's pulse.
    local jump=self.p.array_at(a,2,'bool')==true
    local use=self.p.array_at(a,11,'bool')==true
        or self:get('Controls','wasFireButtonFiring',instance,'bool')==true
        or self:get('Controls','UseButtonPressed',instance,'bool')==true
    if not self.touch or self.touch.jump~=jump or self.touch.use~=use then
        self:trace_input('TOUCH jump='..tostring(jump)..' attack='..tostring(use))
    end
    self.touch={jump=jump,use=use,tick=self.input_tick or 0}
end

function Bridge:pressed(player,key,field)
    if self.touch and (self.input_tick or 0)-self.touch.tick<=1 then return self.touch[key] end
    return self:get('Player',field,player,'bool')==true
end

function Bridge:grounded(player,vy)
    if self.surface_support then return true end
    if vy < -0.01 or vy > 1.25 then return false end
    local x,y=self:vec('position',player)
    local w,h=self:get('Entity','width',player,'int32'),self:get('Entity','height',player,'int32')
    local ty=math.floor((y+h+2)/16)
    local maxx,maxy=self:get('Main','maxTilesX',nil,'int32'),self:get('Main','maxTilesY',nil,'int32')
    if ty<0 or ty>=maxy then return false end
    for tx=math.max(0,math.floor((x+2)/16)),math.min(maxx-1,math.floor((x+w-2)/16)) do
        if self.p.invoke(self.methods.ground,tx,ty,true)==true then return true end
    end
    return false
end


function Bridge:resize_player(player)Traits.resize(self,player)end
function Bridge:jump_input(player)
    Traits.move(self,player)
    if self.form.kind=='eye' or self.form.flight or(self.form.swim and self:get('Entity','wet',player,'bool'))then Flight.move(self,player);return true end
    if self.form.kind~='slime' and self.form.movement~='charge' then return false end
    if self:get('Player','controlDown',player,'bool') then
        self.charging,self.charge,self.last_jump=false,0,false
        return false -- Let vanilla perform platform drop-through.
    end
    local jump=self:pressed(player,'jump','controlJump')
    local vx,vy=self:vec('velocity',player)
    local grounded=self:grounded(player,vy)
    if not self.seen_jump then self:trace_input('JUMP_CONSUMER reached');self.seen_jump=true end
    if jump~=self.last_jump then
        self:trace_input('JUMP_SAMPLE held='..tostring(jump)..' ground='..tostring(grounded)..' vy='..string.format('%.2f',vy))
    end
    local launch=not jump and self.last_jump and self.charging
    if jump and grounded then
        if not self.charging then self:trace_input('CHARGE_BEGIN') end
        self.charging=true;self.charge=math.min(45,self.charge+1)
    end
    self.last_jump=jump
    if launch and grounded then
        vy=-(11+6*self.charge/45)
        self:set_vec('velocity',player,vx,vy)
        self:trace_input('JUMP_RELEASE charge='..self.charge..' vy='..string.format('%.2f',vy))
    end
    if not jump or not grounded then self.charge,self.charging=0,false end
    self:set('Player','jump',player,0,'int32')
end

-- Re-enter primitive-only collision methods with the original platform flags.
-- The guard lets that nested call execute native code without recursion.
function Bridge:flight_collision(key,player,args)
    if self.form.phase then return Traits.phase_collision(self,player)end
    if self.collision_override or not (self.form.flight or self.form.kind=='eye') then return false end
    if not self:get('Player','controlDown',player,'bool')
        or self:get('Player','controlUp',player,'bool') or self:pressed(player,'jump','controlJump') then return false end
    self.collision_override=true
    local ok,err=pcall(function()
        local result
        if key=='wet_collision' then result=self.p.invoke(self.methods[key],player,true,true,args[3])
        else result=self.p.invoke(self.methods[key],player,true,true) end
        assert(result~=false,'原版平台碰撞调用失败：'..key)
    end)
    self.collision_override=nil
    if not ok then error(err) end
    return true
end

function Bridge:resist_buff(player,args)
    if self.buff_override or not self.stats_for then return false end
    local a=self:get('Main','debuff',nil,'object');local id=args[1]
    if not a or id<0 or id>=self.p.array_length(a)or not self.p.array_at(a,id,'bool')then return false end
    local factor=self.stats_for(self.form.key).resistance
    if factor<=0 then return false end
    self.buff_override=true
    local ok,err=pcall(self.p.invoke,self.methods.add_buff,player,id,math.max(1,math.floor(args[2]*(1-factor))),args[3])
    self.buff_override=nil;if not ok or err==false then error(ok and'异常抗性调用失败'or err)end;return true
end
function Bridge:cd(ticks,normal)
    local stats=self.stats_for and self.stats_for(self.form.key)
    return math.max(1,math.floor(ticks*(stats and(normal and stats.attack_interval or stats.cooldown)or 1)+.5))
end
function Bridge:restore_growth()
    local s=self.growth_scope;self.growth_scope=nil
    if s and self:local_player()==s.player then self:set('Player','endurance',s.player,s.endurance,'float') end
    self:horizontal_post()
end
function Bridge:horizontal_pre(player)
    if not self.stats_for or self.form.flight or self.form.kind=='eye' then return end
    local factor=self.stats_for(self.form.key).speed
    if self.form.swim and not self:get('Entity','wet',player,'bool')then factor=factor*.25 end
    self.move_scope={player=player}
    for _,key in ipairs({'maxRunSpeed','accRunSpeed','runAcceleration'})do
        local value=self:get('Player',key,player,'float');self.move_scope[key]=value
        self:set('Player',key,player,value*factor,'float')
    end
end
function Bridge:horizontal_post()
    local s=self.move_scope;self.move_scope=nil
    if not s then return end
    for _,key in ipairs({'maxRunSpeed','accRunSpeed','runAcceleration'})do self:set('Player',key,s.player,s[key],'float') end
end
function Bridge:apply_form_effects(player)
    Traits.apply(self,player)
    if self.stats_for then
        local value=self:get('Player','endurance',player,'float')
        self.growth_scope={player=player,endurance=value}
        self:set('Player','endurance',player,math.min(.95,value+(self.stats_for(self.form.key).reduction or 0)),'float')
    end
    if self.form.kind=='eye' or self.form.flight or(self.form.swim and self:get('Entity','wet',player,'bool'))then Flight.apply(self,player,true) end
end

function Bridge:throw_bone(player)
    return self.normal_runtime and self.normal_runtime:throw(player) or false
end

-- ItemCheck also handles summons, potions, placement and utility items.
-- Only a non-consumable weapon (or empty hand) is replaced by a form attack.
function Bridge:vanilla_item(player)
    local item=self.p.invoke(self.methods.held_item,player)
    if not item or self:get('Item','type',item,'int32')<=0 or self:get('Item','stack',item,'int32')<=0 then return false end
    if self:get('Item','consumable',item,'bool') or self:get('Item','damage',item,'int32')<=0 then return true end
    for _,name in ipairs({'pick','axe','hammer'}) do
        if self:get('Item',name,item,'int32')>0 then return true end
    end
    return self:get('Item','createTile',item,'int32')>=0 or self:get('Item','createWall',item,'int32')>=0
end
function Bridge:item_input(player,controller)
    local vanilla=self:vanilla_item(player)
    if controller.state.active then
        self:use_input(player,not vanilla)
        return not vanilla
    end
    if vanilla then return false end
    return false -- Capture now follows the explicit action binding, not a hidden Down+attack shortcut.
end
function Bridge:use_input(player,allow_native)
    if self.learned then
        for slot=1,2 do
            if self.learned_requests and self.learned_requests[slot] then self.learned:cast(player,slot) end
        end
    end
    self.learned_requests={}
    if self.boss_runtime then
        local requested,dash=self.boss_skill_request,self.boss_dash_request
        self.boss_skill_request,self.boss_dash_request=false,false
        if dash then self.boss_runtime:dash(player) end
        if requested or (allow_native~=false and self:pressed(player,'use','controlUseItem')) then self.boss_runtime:cast(player) end
        return
    end
    if not self.seen_use then self:trace_input('ATTACK_CONSUMER reached');self.seen_use=true end
    local gui_bone=self.gui_bone
    local gui_skill=self.gui_skill
    self.gui_bone,self.gui_skill=false,false
    if gui_bone and self.form.kind=='skeleton' and self.cooldown==0 then
        self.cooldown=self:throw_bone(player) and self:cd(40) or 8
        return
    end
    if gui_skill and self.normal_runtime and self.normal_runtime.cast and self.cooldown==0 then
        self.cooldown=self.normal_runtime:cast(player) and self:cd(self.form.skill_cooldown) or 8
        return
    end
    local use=gui_skill or (allow_native~=false and self:pressed(player,'use','controlUseItem'))
    if use~=self.last_use then self:trace_input('ATTACK_SAMPLE pressed='..tostring(use));self.last_use=use end
    if use and self.cooldown==0 then
        if not gui_skill and Combat.random_skill(self,player)then return end
        if self.form.kind=='skeleton' and self:get('Player','controlUp',player,'bool') then
            self.cooldown=self:throw_bone(player) and self:cd(40) or 8
            return
        end
        self.attack_ticks,self.cooldown,self.hits=self.form.duration,math.max(self.form.duration,self:cd(self.form.cooldown,true)),{}
        self.pots_broken=false
        local vx,vy=self:vec('velocity',player)
        local dir=self:get('Entity','direction',player,'int32')
        if self.form.kind=='eye' or self.form.flight then
            local length=math.sqrt(vx*vx+vy*vy)
            if length<0.5 then vx,vy=dir,0;length=1 end
            self.rush_vx,self.rush_vy=vx*self.form.rush/length,vy*self.form.rush/length
            self:set_vec('velocity',player,self.rush_vx,self.rush_vy)
        elseif self.form.rush>0 then
            self:set_vec('velocity',player,dir*self.form.rush,math.min(vy,-2.5))
        end
        self:trace_input('ATTACK_START form='..self.form.key..' dir='..dir)
    end
end
function Bridge:attack(player)
    if self.attack_ticks<=0 then return end
    local phase=Melee.phase(self.form,self.attack_ticks)
    self.attack_ticks=self.attack_ticks-1
    if phase~='active' then return end
    if not self.pots_broken then self:break_pots(player);self.pots_broken=true end
    local a=self:get('Main','npc',nil,'object')
    if not a then return end
    local x,y=self:vec('position',player)
    local w,h=self:get('Entity','width',player,'int32'),self:get('Entity','height',player,'int32')
    local dir=self:get('Entity','direction',player,'int32')
    for i=0,math.min(199,self.p.array_length(a)-1) do
        if i~=self.proxy_index and not self.hits[i] then
            local n=self.p.array_at(a,i)
            if n and self:get('NPC','active',n,'bool') and not self:get('NPC','friendly',n,'bool')
                and not self:get('NPC','dontTakeDamage',n,'bool') and self:get('NPC','life',n,'int32')>0 then
                local nx,ny=self:vec('position',n)
                local nw,nh=self:get('Entity','width',n,'int32'),self:get('Entity','height',n,'int32')
                local left=dir<0 and self.form.reach or 8
                local right=dir>0 and self.form.reach or 8
                if x-left<nx+nw and x+w+right>nx and y-4<ny+nh and y+h+4>ny then
                    self.hits[i]=true
                    local previous=self.hit_form;self.hit_form=self.form.key
                    local damage=self.damage_for and self.damage_for(self.form.key,self.form.damage) or self.form.damage
                    local ok,err=pcall(self.p.invoke,self.methods.strike,n,damage,self.form.knockback*(self.stats_for and self.stats_for(self.form.key).knockback or 1),dir,false,false,self:main('myPlayer'))
                    self.hit_form=previous
                    if not ok then error(err) end
                end
            end
        end
    end
end

function Bridge:install(callbacks)
    local function hook(key,opts)
        local h=required(self.p.install_hook(self.methods[key],opts),'安装 '..key..' 钩子')
        self.hooks[#self.hooks+1]=h
    end
    local ok,err=pcall(function()
        hook('update',{prefix=callbacks.update_pre,postfix=callbacks.update_post})
        hook('hurt',{prefix=callbacks.hurt_pre,postfix=callbacks.hurt_post})
        hook('kill',{prefix=callbacks.kill})
        hook('item',{prefix=callbacks.item})
        hook('npc_update',{prefix=callbacks.npc_update})
        hook('draw',{prefix=callbacks.draw})
        hook('equip_check',{prefix=callbacks.equip_check})
        hook('equip_apply',{prefix=callbacks.equip_apply})
        hook('equip_prefix',{prefix=callbacks.equip_prefix})
        hook('quick_mount',{prefix=callbacks.quick_mount})
        for _,key in ipairs({'quick_heal','quick_mana','quick_buff','quick_grapple'})do hook(key,{prefix=callbacks[key]})end
        hook('hearts',{prefix=callbacks.hearts_pre,postfix=callbacks.hearts_post})
        hook('jump_move',{prefix=callbacks.jump_move})
        hook('add_buff',{prefix=callbacks.add_buff})
        hook('resize',{prefix=callbacks.resize})
        hook('horizontal',{prefix=callbacks.horizontal_pre,postfix=callbacks.horizontal_post})
        hook('projectile_damage',{prefix=callbacks.shot_pre,postfix=callbacks.shot_post})
        hook('strike',{prefix=callbacks.strike_pre,postfix=callbacks.strike_post})
        hook('new',{postfix=callbacks.npc_spawn})
        for _,key in ipairs({'dry_collision','wet_collision','slope_collision'}) do hook(key,{prefix=callbacks[key]}) end
        hook('controls_update',{postfix=callbacks.controls_update})
        hook('reset',{postfix=callbacks.reset})
        hook('world_update',{postfix=callbacks.world_update})
    end)
    if not ok then self:uninstall();error(err) end
end
function Bridge:uninstall()
    for i=#self.hooks,1,-1 do pcall(function() self.hooks[i]:remove() end) end
    self.hooks={}
end

for name,fn in pairs(World)do if name~='bind'then Bridge[name]=fn end end
return Bridge
