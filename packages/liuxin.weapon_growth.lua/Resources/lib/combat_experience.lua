-- 经验只来自带有真实攻击上下文的致死 StrikeNPC；不读取死亡时手持武器。
local M={}
local function clamp(value,low,high) return math.max(low,math.min(high,value)) end
-- 经验按敌人血量计价；Boss 另乘当前世界阶段系数。全部结果为3的倍数，
-- 因而备用同类武器始终能精确获得三分之一经验。
function M.experience(maxLife,isBoss,worldStage)
    if type(maxLife)~='number' or maxLife<=0 then return 0 end
    local estimate=math.floor(math.sqrt(maxLife)+0.5)
    local base=math.max(12,math.floor(estimate/3+0.5)*3)
    if isBoss then
        local stage=clamp(tonumber(worldStage) or 0,0,10)
        base=math.floor(base*(2+0.25*stage)/3+0.5)*3
        return math.min(3000,base)
    end
    return math.min(600,base)
end
function M.install(P,api)
    local object={ready=false,hooks={},sources={},strikes={},deaths={},projectileFrames={},itemFrames={},summonStrikes={}}
    function object:reset() self.sources={};self.strikes={};self.deaths={};self.projectileFrames={};self.itemFrames={};self.summonStrikes={} end
    function object:remove() for _,h in ipairs(self.hooks) do pcall(function() h:remove() end) end;self.hooks={};self.ready=false;self:reset() end
    local function failure(err) object.ready=false;object:reset();api.log('XP_DISABLED',tostring(err),true) end
    local function guard(fn)
        return function(instance,args,result)
            if not object.ready then return false end
            local ok,err=pcall(fn,instance,args or {},result)
            if not ok then failure(err) end
            return false -- 永远不跳过原版执行，也不修改原返回值。
        end
    end
    local ok,err=pcall(function()
        local player=P.get_type('Terraria','Player')
        local proj=P.get_type('Terraria','Projectile')
        local npc=P.get_type('Terraria','NPC')
        local function field(t,name) local f=P.get_field(t,name);assert(f,'缺少经验字段 '..name);return f end
        local pf={};for _,name in ipairs({'owner','friendly','trap','npcProj','melee','ranged','magic','minion','sentry','type'}) do pf[name]=field(proj,name) end
        local nf={};for _,name in ipairs({'whoAmI','life','lifeMax','boss','friendly','townNPC','immortal','dontTakeDamage','chaseable','SpawnedFromStatue','realLife','type'}) do nf[name]=field(npc,name) end
        local playerIndex=field(player,'whoAmI')
        local generation=P.get_property(npc,'generation')
        local getGeneration=generation and P.property_get_method(generation)
        assert(getGeneration,'缺少 NPC.generation，无法保证槽位复用后结算正确')
        local function read(fields,key,instance,kind) return P.get_field_value(fields[key],instance,kind) end
        -- 可选读取游戏自身的射弹类别集合；无预设射弹 ID 清单。
        local projectileID=P.get_type('Terraria.ID','ProjectileID')
        local sets=projectileID and type(P.get_inner_type)=='function' and P.get_inner_type(projectileID,'Sets')
        if sets and not (P.get_field(sets,'MinionShot') and P.get_field(sets,'SentryShot') and P.get_field(sets,'IsAWhip')) then sets=nil end
        local setFields={}
        if sets then for _,key in ipairs({'MinionShot','SentryShot','IsAWhip'}) do setFields[key]=P.get_field(sets,key) end
        else api.log('XP_SUMMON_SETS_UNAVAILABLE','召唤主体/哨兵仍识别；未标记的附属射弹和鞭子来源会跳过',true) end
        local bombSet=sets and P.get_field(sets,'IsABombWithFuse')
        if not bombSet then api.log('XP_BOMB_SET_UNAVAILABLE','无法按原版集合排除炸弹射弹经验',true) end
        local function isSummonShot(instance)
            if read(pf,'minion',instance,'bool')==true or read(pf,'sentry',instance,'bool')==true then return true end
            local id=read(pf,'type',instance,'int32')
            if type(id)~='number' or id<0 then return false end
            for _,f in pairs(setFields) do
                local array=P.get_field_value(f,nil,'object')
                if array and id<P.array_length(array) and P.array_at(array,id,'bool')==true then return true end
            end
            return false
        end
        local function isBombShot(instance)
            if not bombSet then return false end
            local id=read(pf,'type',instance,'int32')
            if type(id)~='number' or id<0 then return false end
            local array=P.get_field_value(bombSet,nil,'object')
            return array~=nil and id<P.array_length(array) and P.array_at(array,id,'bool')==true
        end
        local function source(class,owner,weaponId)
            if not api.active() or owner~=api.localPlayer() then return false end
            local profile=api.profile()
            if not profile or not class then return false end
            return {category=class,owner=owner,profile=profile,weaponId=weaponId}
        end
        local animation=field(player,'itemAnimation')
        local noMelee=field(P.get_type('Terraria','Item'),'noMelee')
        local held=P.get_property(player,'HeldItem')
        local heldGetter=held and P.property_get_method(held)
        local function pushItemCheck(instance)
            local owner=P.get_field_value(playerIndex,instance,'int32')
            local current=false
            if owner==api.localPlayer() and api.active() then
                local key=api.profile()
                if key then current={player=instance,owner=owner,profile=key} end
            end
            object.itemFrames[#object.itemFrames+1]=current
        end
        local function popItemCheck() table.remove(object.itemFrames) end
        local function directMeleeSource()
            -- 必须处于同步 ItemCheck 调用中；任何射弹 Damage 帧都禁止回退归因。
            if #object.projectileFrames>0 or not heldGetter then return false end
            local frame=object.itemFrames[#object.itemFrames]
            if not frame or not api.active() or api.profile()~=frame.profile then return false end
            local value=P.get_field_value(animation,frame.player,'int32')
            if type(value)~='number' or value<=0 then return false end
            local item=P.invoke(heldGetter,frame.player)
            if not item or P.get_field_value(noMelee,item,'bool')~=false then return false end
            local entry=api.identify(item)
            if not entry or entry.category~='melee' then return false end
            return source('melee',frame.owner,entry.id)
        end
        local function pushProjectile(instance)
            local binding=api.projectileSource and api.projectileSource(instance)
            local class
            if read(pf,'friendly',instance,'bool')==true and read(pf,'trap',instance,'bool')==false and read(pf,'npcProj',instance,'bool')==false then
                if isBombShot(instance) then class=nil
                elseif binding and (binding.category=='summon' or binding.category=='melee'
                    or binding.category=='ranged' or binding.category=='magic') then class=binding.category
                elseif isSummonShot(instance) then class='summon'
                else
                    local count=0
                    for _,key in ipairs({'melee','ranged','magic'}) do if read(pf,key,instance,'bool')==true then class=key;count=count+1 end end
                    if count~=1 then class=nil end
                end
            end
            local owner=read(pf,'owner',instance,'int32')
            local weaponId=binding and binding.owner==owner and binding.category==class and binding.weaponId or nil
            local current=weaponId and source(class,owner,weaponId) or false
            object.sources[#object.sources+1]=current
            local damageToken
            object.projectileFrames[#object.projectileFrames+1]={token=damageToken,projectile=instance,
                summon=class=='summon' and owner==api.localPlayer(),weaponId=weaponId}
        end
        local function popSource() object.sources[#object.sources]=nil end
        local function popProjectile(instance)
            local frame=table.remove(object.projectileFrames)
            if frame and frame.token and api.summonDamagePostfix then
                pcall(api.summonDamagePostfix,frame.projectile or instance,frame.token)
            end
            popSource()
        end
        local bossFrames={}
        local function strikeBefore(instance,args)
            local boss=false
            if api.bossKill and api.active() and args[5]~=true and read(nf,'boss',instance,'bool')==true
                and read(nf,'life',instance,'int32')>0 and read(nf,'realLife',instance,'int32')<0 then
                boss={profile=api.profile(),id=read(nf,'type',instance,'int32')}
            end
            bossFrames[#bossFrames+1]=boss
            local summonTrace=false
            local projectile=object.projectileFrames[#object.projectileFrames]
            if projectile and projectile.summon and api.summonStrikeBegin then
                local ok,value=pcall(api.summonStrikeBegin,instance,args,projectile.weaponId)
                if ok and value then summonTrace=value end
            end
            object.summonStrikes[#object.summonStrikes+1]=summonTrace
            local frame=false
            local src=object.sources[#object.sources]
            if #object.sources==0 then src=directMeleeSource() end
            -- 利用已有的纯标量 StrikeNPC Hook 观察异常，不添加碰撞入口 Hook。
            local observedDamage=args[1]
            if type(observedDamage)=='number' and (observedDamage~=observedDamage or observedDamage>=1000000) then
                api.log('STRIKE_DAMAGE_SUSPECT','damage='..tostring(observedDamage)
                    ..' npcSlot='..tostring(read(nf,'whoAmI',instance,'int32'))
                    ..' life='..tostring(read(nf,'life',instance,'int32'))
                    ..' lifeMax='..tostring(read(nf,'lifeMax',instance,'int32'))
                    ..' crit='..tostring(args[4])..' fromNet='..tostring(args[5])
                    ..' owner='..tostring(args[6])..' source='..tostring(src and src.category or 'untracked')
                    ..'；仅记录，不截断伤害',true)
            end
            if src and api.active() then
                local life=read(nf,'life',instance,'int32')
                local max=read(nf,'lifeMax',instance,'int32')
                local damage=args[1]
                local slot=read(nf,'whoAmI',instance,'int32')
                local gen=P.invoke(getGeneration,instance)
                local eligible=type(life)=='number' and life>0 and type(max)=='number' and max>5
                    and type(damage)=='number' and damage>0 and damage<1000000 and args[5]~=true
                    and (args[6]==nil or args[6]==-1 or args[6]==src.owner)
                    and read(nf,'realLife',instance,'int32')<0
                for _,key in ipairs({'friendly','townNPC','immortal','dontTakeDamage','SpawnedFromStatue'}) do eligible=eligible and read(nf,key,instance,'bool')==false end
                eligible=eligible and read(nf,'chaseable',instance,'bool')==true
                if eligible and type(slot)=='number' and type(gen)=='number' and object.deaths[slot]~=gen then
                    frame={slot=slot,generation=gen,life=life,max=max,boss=read(nf,'boss',instance,'bool')==true,source=src}
                end
            end
            object.strikes[#object.strikes+1]=frame
        end
        local function strikeAfter(instance,args,result)
            local boss=table.remove(bossFrames)
            if boss and boss.profile and api.active() and api.profile()==boss.profile and read(nf,'life',instance,'int32')<=0 then
                api.bossKill(boss.profile,boss.id)
            end
            local summonTrace=table.remove(object.summonStrikes)
            if summonTrace and api.summonStrikeEnd then pcall(api.summonStrikeEnd,instance,args,result,summonTrace) end
            local frame=object.strikes[#object.strikes];object.strikes[#object.strikes]=nil
            if not frame or not api.active() or type(result)~='number' or result<=0 then return end
            if api.profile()~=frame.source.profile then return end
            if read(nf,'whoAmI',instance,'int32')~=frame.slot or P.invoke(getGeneration,instance)~=frame.generation then return end
            local life=read(nf,'life',instance,'int32')
            if type(life)~='number' or life>0 or object.deaths[frame.slot]==frame.generation then return end
            object.deaths[frame.slot]=frame.generation
            if frame.source.category=='melee' and #object.projectileFrames==0 then
                api.log('MELEE_XP_CONFIRMED','entry=ItemCheck weapon='..tostring(frame.source.weaponId)
                    ..' npcSlot='..tostring(frame.slot)..' lifeMax='..tostring(frame.max)
                    ..' finalDamage='..tostring(result)..'；同步挥砍致死结算')
            end
            local xp=M.experience(frame.max,frame.boss,api.worldStage and api.worldStage() or 0)
            api.award(frame.source.profile,frame.source.category,xp,frame.source.weaponId,frame.source.owner,frame.boss,frame.max)
        end
        local function hook(t,name,names,prefix,postfix)
            local method=P.get_method_by_names(t,name,names)
            assert(method and P.method_is_instance(method) and P.method_param_count(method)==#names,'经验入口不匹配 '..name)
            local key=name=='Damage' and 'Projectile.Damage()' or 'NPC.StrikeNPC(scalars)'
            local h=P.install_hook(method,{_wg_key=key,prefix=guard(prefix),postfix=guard(postfix)})
            assert(h,'经验 Hook 安装失败 '..name);object.hooks[#object.hooks+1]=h
        end
        -- 保留已实测有效的修复：永不挂接包含按值 Rectangle 的近战入口。
        api.log('MELEE_HOOK_ISOLATED','v1.1 未安装 ItemCheck_MeleeHitNPCs；使用无结构体参数 ItemCheck 作用域',true)
        local installed=false
        if heldGetter then
            for _,names in ipairs({{'i'},{}}) do
                local method=P.get_method_by_names(player,'ItemCheck',names)
                if method and P.method_is_instance(method) and P.method_param_count(method)==#names then
                    local h=P.install_hook(method,{prefix=guard(pushItemCheck),postfix=guard(popItemCheck)})
                    if h then
                        object.hooks[#object.hooks+1]=h;installed=true
                        api.log('MELEE_XP_READY','已挂接 ItemCheck 参数数='..tostring(#names)
                            ..'；仅在同步使用物品流程、近战挥砍动画和非射弹伤害上下文中归因',true)
                        break
                    end
                end
            end
        end
        if not installed then api.log('MELEE_XP_UNAVAILABLE','安全 ItemCheck 入口不可用；仅暂停直接挥砍经验，保留射弹经验与等级加成',true) end
        hook(proj,'Damage',{},pushProjectile,popProjectile)
        hook(npc,'StrikeNPC',{'Damage','knockBack','hitDirection','crit','fromNet','owner'},strikeBefore,strikeAfter)
        object.ready=true;api.log('XP_READY','友方射弹击杀经验已启用；直接挥砍入口状态见 MELEE_XP_READY / MELEE_XP_UNAVAILABLE',true)
    end)
    if not ok then object:remove();api.log('XP_UNAVAILABLE',tostring(err),true) end
    return object
end
return M
