-- 仅挂接引用/标量参数入口。射弹按 owner+identity+slot 保存来源，绝不按最近武器猜测。
local M={}
function M.install(P,api)
    local self={ready=false,hooks={},bindings={},shots={},parents={},spawnFrames={},damageFrames={},hitFrames={},notices={}}
    function self:reset() self.bindings={};self.shots={};self.parents={};self.spawnFrames={};self.damageFrames={};self.hitFrames={};self.notices={} end
    function self:remove() for _,h in ipairs(self.hooks) do pcall(function() h:remove() end) end;self.hooks={};self.ready=false;self:reset() end
    local f={}
    local identityKind='int32'
    local function read(key,obj,kind)
        local value=P.get_field_value(f[key],obj,kind or (key=='identity' and identityKind or 'int32'))
        if key=='identity' then
            assert(type(value)=='number' and value==value and value%1==0,'射弹身份数值不可读')
        end
        return value
    end
    local function same(b,proj)
        return b and b.owner==read('owner',proj) and b.identity==read('identity',proj)
            and b.type==read('type',proj) and b.slot==read('whoAmI',proj)
    end
    function self:lookup(proj)
        if not self.ready or not proj or read('active',proj,'bool')~=true then return nil end
        local slot=read('whoAmI',proj)
        local b=self.bindings[slot]
        if same(b,proj) then return b.source end
        self.bindings[slot]=nil
        return nil
    end
    local snapshotSummons,bindShotSummons
    function self:beginShot(player,item)
        local source=false
        if self.ready and player and item then
            local ok,value=pcall(api.capture,player,item)
            if ok and value then source=value end
        end
        local snapshot
        if source and source.category=='summon' and not (source.entry and source.entry.isWhip) and type(source.projectileType)=='number' and source.projectileType>0 and snapshotSummons then
            local ok,value=pcall(snapshotSummons)
            if ok then snapshot=value else api.log('SUMMON_SNAPSHOT_UNAVAILABLE',tostring(value),true) end
        end
        self.shots[#self.shots+1]={source=source,snapshot=snapshot}
    end
    function self:endShot()
        local frame=table.remove(self.shots)
        if self.ready and frame and frame.snapshot then
            local ok,err=pcall(bindShotSummons,frame.source,frame.snapshot)
            if not ok then self.ready=false;self:reset();api.log('PROJECTILE_SOURCE_DISABLED',tostring(err),true) end
        end
    end
    function self:beginDamage(proj,token,confirmed)
        local source
        if confirmed~=nil then source=confirmed else source=self:lookup(proj) end
        local current=self.damageFrames[#self.damageFrames]
        if source then
            local copied={};for k,v in pairs(source) do copied[k]=v end
            if token then copied.embeddedCoefficient=token.coefficient
            elseif current and current.slot==copied.slot and current.identity==copied.identity then
                copied.embeddedCoefficient=current.embeddedCoefficient
            end
            source=copied
        end
        self.damageFrames[#self.damageFrames+1]=source or false
    end
    function self:endDamage() table.remove(self.damageFrames) end
    local function notice(tag,msg,key)
        key=key or tag
        if self.notices[key] then return end
        self.notices[key]=true;api.log(tag,msg)
    end
    local function guard(fn)
        return function(instance,args,result)
            if not self.ready then return false end
            local ok,err=pcall(fn,instance,args or {},result)
            if not ok then self.ready=false;self:reset();api.log('PROJECTILE_SOURCE_DISABLED',tostring(err),true) end
            return false
        end
    end
    local ok,err=pcall(function()
        local proj=P.get_type('Terraria','Projectile')
        local main=P.get_type('Terraria','Main')
        for _,key in ipairs({'whoAmI','owner','type','active'}) do f[key]=P.get_field(proj,key);assert(f[key],'缺少射弹来源字段 '..key) end
        f.identity=P.get_field(proj,'identity')
        local identityMode='identity_int32'
        if not f.identity then
            -- 1.4.5 Projectile.key 是显式布局的4字节 ProjectileKey，bits/floatBits同偏移0。
            -- 只读取这4字节身份位；不调用结构体getter/转换方法，也不使用硬编码对象偏移。
            f.identity=P.get_field(proj,'key');identityKind='uint32';identityMode='key_uint32'
        end
        assert(f.identity,'缺少射弹身份字段 identity/key')
        api.log('PROJECTILE_IDENTITY_READY','mode='..identityMode..'；槽位复用按原版代际身份重新校验',true)
        local arrayField=P.get_field(main,'projectile');assert(arrayField,'缺少 Main.projectile')
        for _,key in ipairs({'friendly','trap','npcProj'}) do f[key]=P.get_field(proj,key);assert(f[key],'缺少射弹归因字段 '..key) end
        local function array()
            local value=P.get_field_value(arrayField,nil,'object')
            local count=value and P.array_length(value)
            assert(type(count)=='number' and count>=0 and count<=5000,'射弹数组异常')
            return value,count
        end
        local function bind(source,object,slot,via)
            if not source or not object or read('active',object,'bool')~=true then return end
            local owner=read('owner',object)
            if owner~=source.owner or read('friendly',object,'bool')~=true
                or read('trap',object,'bool')~=false or read('npcProj',object,'bool')~=false then return end
            local captured={};for k,v in pairs(source) do captured[k]=v end
            captured.embeddedCoefficient=captured.embeddedCoefficient or 1
            captured.slot=slot;captured.identity=read('identity',object)
            local projectileType=read('type',object)
            self.bindings[slot]={slot=slot,owner=owner,identity=captured.identity,type=projectileType,source=captured}
            if source.category=='summon' then
                notice('SUMMON_SOURCE_BOUND','item='..source.weaponId..' slot='..slot..' identity='..captured.identity
                    ..' type='..projectileType..' via='..via..'；发射来源已绑定',
                    'summon:'..source.weaponId..':'..projectileType..':'..via)
            else
                notice('PROJECTILE_SOURCE_BOUND','item='..source.weaponId..' class='..source.category
                    ..' slot='..slot..' identity='..captured.identity..' type='..projectileType..' via='..via,
                    'shot:'..source.weaponId..':'..projectileType..':'..via)
            end
        end
        snapshotSummons=function()
            local objects,count=array()
            local snapshot={}
            for slot=0,count-1 do
                local object=P.array_at(objects,slot,'object')
                if object and read('active',object,'bool')==true then
                    snapshot[slot]={owner=read('owner',object),identity=read('identity',object),type=read('type',object)}
                end
            end
            return snapshot -- 只保存数字，原生对象句柄不跨帧缓存。
        end
        bindShotSummons=function(source,snapshot)
            local objects,count=array()
            for slot=0,count-1 do
                local object=P.array_at(objects,slot,'object')
                if object and read('active',object,'bool')==true then
                    local before=snapshot[slot]
                    local isNew=not before or before.owner~=read('owner',object)
                        or before.identity~=read('identity',object) or before.type~=read('type',object)
                    -- 内层发射或标量入口已确认的绑定优先，不被外层物品覆盖。
                    if isNew and read('type',object)==source.projectileType and not same(self.bindings[slot],object) then
                        bind(source,object,slot,'shoot_scope')
                    end
                end
            end
        end
        local function pushParent(instance) self.parents[#self.parents+1]=self:lookup(instance) or false end
        local function popParent() table.remove(self.parents) end
        local ai=P.get_method_by_names(proj,'AI',{})
        assert(ai and P.method_is_instance(ai) and P.method_param_count(ai)==0,'Projectile.AI 签名不可用')
        local h=P.install_hook(ai,{prefix=guard(pushParent),postfix=guard(popParent)})
        assert(h,'Projectile.AI 来源 Hook 未安装');self.hooks[#self.hooks+1]=h
        -- 独立于经验系统和人物路径，所有已确认职业射弹均可重算倍率。
        local damageMethod=P.get_method_by_names(proj,'Damage',{})
        assert(damageMethod and P.method_is_instance(damageMethod) and P.method_param_count(damageMethod)==0,'Projectile.Damage 签名不可用')
        local damageHook=P.install_hook(damageMethod,{_wg_key='Projectile.Damage()',
            prefix=function(instance)
                local token,confirmed=nil,false
                if self.ready then
                    local ok,b=pcall(function() return self:lookup(instance) end)
                    if ok then confirmed=b or false end
                    if ok and b and api.damagePrefix then
                        local success,value=pcall(api.damagePrefix,instance,b.owner,b.weaponId,b)
                        if success then token=value else api.log('PROJECTILE_DAMAGE_ERROR',tostring(value),true) end
                    end
                end
                self.hitFrames[#self.hitFrames+1]={token=token}
                local ok,err=pcall(function() self:beginDamage(instance,token,confirmed) end)
                if not ok then api.log('PROJECTILE_CONTEXT_ERROR',tostring(err),true) end
                return false
            end,
            postfix=function(instance)
                local frame=table.remove(self.hitFrames)
                self:endDamage()
                if frame and frame.token and api.damagePostfix then
                    local ok,err=pcall(api.damagePostfix,instance,frame.token)
                    if not ok then api.log('PROJECTILE_RESTORE_ERROR',tostring(err),true) end
                end
                return false
            end,
        })
        assert(damageHook,'Projectile.Damage Hook 未安装');self.hooks[#self.hooks+1]=damageHook
        api.log('PROJECTILE_DAMAGE_READY','全职业确认来源射弹倍率校正独立于经验；子弹幕继承实际应用系数',true)
        local scalarOK,scalarError=pcall(function()
            -- 按类型和参数个数双重验证，禁止 Vector2 重载。
            local scalar=P.get_basic_type and P.get_basic_type('float')
            local int=P.get_basic_type and P.get_basic_type('int32')
            local sourceType=P.get_type('Terraria.DataStructures','IEntitySource')
            assert(scalar and int and sourceType,'缺少 NewProjectile 标量签名类型')
            local method
            local modifier=P.get_type('Terraria','NewProjectileModifier')
            for _,n in ipairs({13,12,11}) do
                local types={sourceType,scalar,scalar,scalar,scalar,int,int,scalar,int,scalar,scalar}
                if n>=12 then types[12]=scalar end
                if n==13 then types[13]=modifier end
                local m=(n~=13 or modifier) and P.get_method_by_param_types(proj,'NewProjectile',types)
                if m and P.method_is_static(m) and P.method_param_count(m)==n then method=m;break end
            end
            assert(method,'无安全 NewProjectile 标量重载，拒绝挂接结构体重载')
            local function spawnBefore()
                -- 已绑定父射弹优先；父帧存在但未知时，不得借用外层手持武器。
                local source
                if #self.damageFrames>0 then source=self.damageFrames[#self.damageFrames]
                elseif #self.parents>0 then source=self.parents[#self.parents]
                else local shot=self.shots[#self.shots];source=shot and shot.source end
                self.spawnFrames[#self.spawnFrames+1]=source or false
            end
            local function spawnAfter(_,args,result)
                local source=table.remove(self.spawnFrames)
                if type(result)~='number' or result%1~=0 or result<0 then return end
                self.bindings[result]=nil -- 槽位复用必须先清掉旧绑定。
                if not source then return end
                local array=P.get_field_value(arrayField,nil,'object')
                if not array or result>=P.array_length(array) then return end
                local object=P.array_at(array,result,'object')
                if not object or read('active',object,'bool')~=true then return end
                bind(source,object,result,'scalar_spawn')
            end
            h=P.install_hook(method,{prefix=guard(spawnBefore),postfix=guard(spawnAfter)})
            assert(h,'NewProjectile 来源 Hook 未安装');self.hooks[#self.hooks+1]=h
            api.log('PROJECTILE_SPAWN_READY','NewProjectile 参数数='..P.method_param_count(method)..'；仅引用/标量参数',true)
        end)
        if not scalarOK then
            api.log('PROJECTILE_SCALAR_UNAVAILABLE',tostring(scalarError)..'；主召唤物仍可通过安全发射作用域绑定，子射弹继承暂停',true)
        end
        self.ready=true
        api.log('PROJECTILE_SOURCE_READY','shootScope=true scalarSpawn='..tostring(scalarOK)..'；未知来源不猜测；不挂结构体参数Hook',true)
    end)
    if not ok then self:remove();api.log('PROJECTILE_SOURCE_UNAVAILABLE',tostring(err)..'；未知召唤来源暂不加成，请检查日志',true) end
    return self
end
return M
