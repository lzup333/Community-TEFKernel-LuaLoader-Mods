mod.meta={pkg_id='liuxin.monstermorph.probe',version='0.11.5',version_code=27,api_version=1}

local bridge,controller,hud,input,panel,credit
local Forms=require('morph.forms')
local Profile=require('morph.profile')
local Controls=require('morph.controls')
local disabled=false
local last_error
local lines={}
local function log(message)
    local line=os.date('%Y-%m-%d %H:%M:%S')..' '..message
    lines[#lines+1]=line
    while #lines>80 do table.remove(lines,1) end
    mod.info('[Morph] '..message)
    mod.write_file('morph_runtime.log',table.concat(lines,'\n')..'\n')
end

local stages={}
local function stage(name)if not stages[name]then stages[name]=true;log('STAGE '..name)end end

local function fail(player,message)
    last_error=tostring(message)
    disabled=true
    if input then pcall(function()input:cleanup()end) end
    if hud and player then pcall(function() hud:restore(player) end) end
    if controller then pcall(function() controller:stop(player,'异常退出变身') end) end
    if bridge then pcall(function() bridge:remove() end) end
    pcall(log,'DISABLED '..last_error)
end

local function guarded(fn)
    return function(player,args,result)
        if disabled then return false end
        local values=table.pack(pcall(fn,player,args,result))
        if not values[1] then
            local local_actor
            if bridge then pcall(function() local_actor=bridge:local_player() end) end
            fail(local_actor,values[2])
            return false
        end
        return table.unpack(values,2,values.n)
    end
end

function mod.init()
    local ok,err=pcall(function()
        assert(mod.platform=='android' and mod.arch=='arm64','验证版仅支持 Android arm64')
        bridge=require('morph.bridge').new(mod.patch)
        local profile=Profile.new(Forms,function(name)
            if not mod.file_exists(name)then return nil end
            local raw,reason=mod.read_file(name);return raw or('READ_ERROR|'..tostring(reason))
        end,
            function(name,data)return mod.write_file(name,data)end)
        controller=require('morph.controller').new(bridge,log,profile)
        bridge.trace=log
        bridge.damage_for=function(key,damage,kind)return controller:damage(key,damage,kind) end
        bridge.stats_for=function(key)return controller:stats(key)end
        bridge.learned_ids=function(key)return controller.profile.growth[key].equipped end
        credit=require('morph.credit').new(bridge,function(key,amount)controller:add_xp(key,amount)end)
        hud=require('morph.hud').new(bridge)
        input=Controls.new(mod.controls,bridge,controller,function(name)if mod.file_exists(name)then return mod.read_file(name)end end,mod.write_file)
        panel=require('morph.panel').new(mod.gui,controller,bridge,input)
        bridge:install({
            world_update=guarded(function()
                bridge.world_tick=(bridge.world_tick or 0)+1
                if not bridge:single_world() and (controller.state.active or controller.state.depth>0 or bridge.boss_runtime) then
                    local p=bridge:local_player()
                    if hud and p then hud:restore(p) end
                    controller:stop(p,'已退出变身：离开单人世界')
                end
            end),
            update_pre=guarded(function(p)
                if bridge:is_local(p) then
                    local in_world=bridge:single_world();if in_world then stage('player_update_begin')end
                    input.bindings:mask(p);if in_world then stage('bindings_mask_ready')end
                    input:poll(p);if in_world then stage('input_poll_ready')end
                    controller:pre_update(p)
                    if in_world then stage('player_update_ready')end
                end
                return false
            end),
            update_post=guarded(function(p)
                if bridge:is_local(p) then controller:post_update(p) end
            end),
            add_buff=guarded(function(p,args)
                if controller.state.active and bridge:is_local(p)then return bridge:resist_buff(p,args)end
                return false
            end),
            resize=guarded(function(p)
                if controller.state.active and bridge:is_local(p)then bridge:resize_player(p);return true end
                return false
            end),
            horizontal_pre=guarded(function(p)
                if controller.state.active and bridge:is_local(p) then bridge:horizontal_pre(p) end
                return false
            end),
            horizontal_post=guarded(function(p)
                if bridge:is_local(p) then bridge:horizontal_post() end
            end),
            npc_spawn=guarded(function(_,args,result)
                if type(result)=='number' and result>=0 and result<200 then credit:spawn(result);if bridge.release_held then bridge.release_held[result]=nil end end
            end),
            strike_pre=guarded(function(n)
                credit:before(n,bridge.hit_form);return false
            end),
            strike_post=guarded(function()credit:after()end),
            shot_pre=guarded(function(shot)
                bridge.shot_context=bridge.shot_context or {}
                bridge.shot_context[#bridge.shot_context+1]=bridge.hit_form or false
                local index=bridge:get('Entity','whoAmI',shot,'int32')
                local entry=bridge.shot_owners and bridge.shot_owners[index]
                bridge.hit_form=entry and not entry.visual and entry.store:same(entry)==shot and entry.form or nil
                return false
            end),
            shot_post=guarded(function()
                local stack=bridge.shot_context or {}
                bridge.hit_form=stack[#stack] or nil;stack[#stack]=nil
            end),
            hurt_pre=guarded(function(p)
                if bridge:is_local(p) then controller:pre_hurt(p) end
                return false
            end),
            hurt_post=guarded(function(p)
                if bridge:is_local(p) then controller:post_hurt(p) end
            end),
            kill=guarded(function(p)
                if bridge:is_local(p) then return controller:kill(p) end
                return false
            end),
            item=guarded(function(p)
                if bridge:is_local(p) and bridge:single_world() then
                    input.bindings:mask(p);return bridge:item_input(p,controller)
                end
                return false
            end),
            jump_move=guarded(function(p)
                if bridge:is_local(p)then input.bindings:mask(p)end
                if controller.state.active and bridge:is_local(p) then
                    return bridge:jump_input(p)~=false
                end
                return false
            end),
            dry_collision=guarded(function(p,args)
                if controller.state.active and bridge:is_local(p) then return bridge:flight_collision('dry_collision',p,args) end
                return false
            end),
            wet_collision=guarded(function(p,args)
                if controller.state.active and bridge:is_local(p) then return bridge:flight_collision('wet_collision',p,args) end
                return false
            end),
            slope_collision=guarded(function(p,args)
                if controller.state.active and bridge:is_local(p) then return bridge:flight_collision('slope_collision',p,args) end
                return false
            end),
            reset=guarded(function(p)
                if controller.state.active and bridge:is_local(p) then
                    bridge:apply_form_effects(p)
                    bridge:set('Player','statLifeMax2',p,controller.state.max,'int32')
                end
            end),
            controls_update=guarded(function(instance)
                if bridge:single_world() then
                    stage('controls_begin');bridge:capture_controls(instance);stage('controls_native_ready')
                    input.bindings:capture(instance,bridge:local_player());stage('controls_bindings_ready')
                else bridge.touch=nil;input.bindings:reset()end
            end),
            npc_update=guarded(function(n,args)
                return bridge:is_appearance(n,args[1])
            end),
            draw=guarded(function()
                -- DrawPlayers has only reference arguments. In single player
                -- this hides the local player without unsafe Vector2 hooks.
                return controller.state.active and bridge:single_world() and bridge:has_proxy()
            end),
            equip_check=guarded(function(p,args)
                if bridge:block_accessory(p,args[2],controller.state.active) then return true,false end
                return false
            end),
            equip_apply=guarded(function(p,args)
                return bridge:block_accessory(p,args[2],controller.state.active) or false
            end),
            equip_prefix=guarded(function(p,args)
                return bridge:block_accessory(p,args[1],controller.state.active) or false
            end),
            quick_mount=guarded(function(p)return bridge:is_local(p)and input.bindings:replace(p,'mount')or false end),
            quick_heal=guarded(function(p)return bridge:is_local(p)and input.bindings:replace(p,'heal')or false end),
            quick_mana=guarded(function(p)return bridge:is_local(p)and input.bindings:replace(p,'mana')or false end),
            quick_buff=guarded(function(p)return bridge:is_local(p)and input.bindings:replace(p,'buff')or false end),
            quick_grapple=guarded(function(p)return bridge:is_local(p)and input.bindings:replace(p,'grapple')or false end),
            hearts_pre=guarded(function()
                if controller.state.active and bridge:single_world() then
                    local p=bridge:local_player()
                    if p then hud:begin(p,controller.state.hp,controller.state.max) end
                end
                return false
            end),
            hearts_post=guarded(function()
                local p=bridge:local_player()
                if p then hud:finish(p) end
            end)
        })
        log('READY v0.11.5 android_arm64 hooks='..#bridge.hooks..' bindings=6 input=gui_and_bindings keys=33 chords=any2 loader_base=1.9.0 boss=suspended pets='..#profile.pets..' capacity=20 team=3 rpg=6stats xp=100/30/30 save=MMP3')
    end)
    if not ok then
        if bridge then bridge:uninstall() end
        fail(nil,err)
    end
end

function mod.on_gui()
    if disabled or not panel then mod.gui.set_visible(false);return end
    local ok,err=pcall(panel.draw,panel)
    if not ok then
        mod.gui.set_visible(false)
        -- A panel error must not disable the gameplay hooks.
        pcall(log,'PANEL_ERROR '..tostring(err));panel=nil
    end
end

function mod.cleanup()
    if input then pcall(function()input:cleanup()end) end
    if controller and bridge then
        if hud then pcall(function() hud:restore(bridge:local_player()) end) end
        pcall(function() controller:stop(bridge:local_player(),'模组卸载') end)
        pcall(function() bridge:remove() end)
        bridge:uninstall()
    end
end
