-- UI-only diagnostic: gacha UI has no game-state or item-creation calls.
mod.meta = {pkg_id='celso.weapon_growth.lua',version='1.7.1',version_code=80} -- 优化版：I/O出栈，钩子零文件读写
local S = require('scaling')
local GachaUI=require('weapon_gacha_ui')
local gachaUiReady=GachaUI.install(mod)
local GachaRuntime=require('weapon_gacha_runtime')
local gachaRuntime,gachaReadFile
local Suppression=require('suppression')
local MultiplayerProbe=require('multiplayer_probe')
local multiplayerProbe
local sessionMode=0
local GrowthProfiles=require('weapon_growth_profiles')
local LegacyClasses=require('legacy_weapon_classes')
local migratedProfiles={}
local Reader = require('weapon_reader')
local ProgressStore = require('progress_store')
local StageCaps=require('stage_level_caps')
local Combat = require('combat_experience')
local WeaponStage = require('weapon_stage')
local ProjectileSources = require('projectile_sources')
local ItemExclusions = require('item_exclusions')
local WhipTagGrowth=require('whip_tag_growth')
local whipTags
local refreshWhipTags
local projectileSources
local store,combat,profileReader,readLocalPlayer,weaponStages,itemExclusions,heldItemGetter
local maintenanceActive=true
local cachedProgress,cachedProfile=false,nil
local refreshProfile,maintenance
local maintenanceLast,lastCompatSummary=-1,-1
local modeNames={world='世界进度模式',kill='打怪升级',mixed='成长混合模式'}
local P = require('hook_router').open(mod.patch,mod.warn)
local hooks,fields = {},{}
local ensureClassMigration
local function defaultSettings()
    return {enabled=true,growth_mode='world',suppress_ahead_weapons=true,debug_log=false,kill_xp_log=false,multiplayer_mode='diagnostic'}
end
local settings=defaultSettings()
-- 正常伤害倍率参数固定为原设置默认值，不再向玩家开放。
local growthStrength,maxMultiplier=0.8,1.6
local nonGrowingConsumables={}
local function hasKillGrowth() return sessionMode==0 and (settings.growth_mode=='kill' or settings.growth_mode=='mixed') end
local function worldGrowthAllowed() return sessionMode~=0 or settings.growth_mode~='kill' end
local alive,ready = true,false
local configText,lastConfig,lastStageCheck = nil,-1,-1
local configLoaded=false
local stage,world,lastMenu,gameMode = 0,nil,true,0
local lastReadWeapon=nil
local lastNotice,lines,lastSave = {},{},-1
local ammoCostStacks,shotSpeedStacks={},{}
local summonDamageFrames={}
local sourceEntryCache={}
local panelNativeDepth=0
local lastTraceTimes={}
local status = '等待初始化'
local clock = function() return os.time() end
-- 【优化版 v1.7.1】文件 I/O 出栈：钩子内的写操作全部进入内存队列，读操作走只读缓存；
-- 真实落盘由 on_gui（加载器渲染回调，不在游戏钩子栈）与 60 秒兜底脉冲执行。
-- 根治 v1.7 单开必崩（SIGABRT/JniAbort/cp_call_open）：崩溃源是钩子栈内每分钟 600+ 次 fopen。
local pendingWrite,readCache={},{}
local function deferredRead(name,mapEmpty)
    local v=pendingWrite[name];if v~=nil then return v end
    local c=readCache[name];if c~=nil then return c or nil end
    local d=mod.read_file(name)
    if d==nil and mapEmpty and type(mod.file_exists)=='function' and mod.file_exists(name) then d='' end
    readCache[name]=d or false -- 负缓存：本模组私有目录内文件只由本模组创建
    return d
end
local function deferredWrite(name,data)
    if type(name)~='string' or type(data)~='string' then return false end
    pendingWrite[name]=data;readCache[name]=data;return true
end
local logDirty=false
local killLogFlushInterval=10
local function saveLog()
    local ok,err=deferredWrite('weapon_growth_runtime.log',table.concat(lines,'\n')..'\n')
    if not ok then mod.warn('[WG][LOG_WRITE_FAILED] '..tostring(err)) end
    lastSave=clock()
    if ok then logDirty=false end
end
local function flushPendingLog()
    if logDirty and clock()-lastSave>=killLogFlushInterval then saveLog() end
end
local function log(tag,message,force,deferSave)
    if not force and not settings.debug_log then return end
    local now=clock()
    if not force and lastNotice[tag] and now-lastNotice[tag]<3 then return end
    lastNotice[tag]=now
    local line=os.date('%Y-%m-%d %H:%M:%S')..' [WG]['..tag..'] '..message
    lines[#lines+1]=line
    logDirty=true
    if #lines>128 then table.remove(lines,1) end
    if settings.debug_log then mod.info(line)end
end
-- 【优化版 v1.7.1】文件 I/O 出栈（上半段：队列与缓存，saveLog 之前定义）。
local ioLastFlush=-1
local function flushPendingIO(minGap,force)
    local now=clock()
    if not force and now-ioLastFlush<(minGap or 10) then return end
    ioLastFlush=now
    if logDirty then saveLog() end -- 先把日志内容编入队列（纯内存）
    -- 配置文件由管理器外部写入：仅在落盘窗口从磁盘刷新缓存（钩子内永远只读缓存）
    local cfgText=mod.read_file('config.json')
    readCache['config.json']=cfgText~=nil and cfgText or false
    if next(pendingWrite)~=nil then
        local list={}for n in pairs(pendingWrite)do list[#list+1]=n end
        for _,n in ipairs(list)do
            local data=pendingWrite[n]
            local ok,err=mod.write_file(n,data)
            if ok and mod.read_file(n)~=data then ok,err=false,'回读校验不一致' end
            if ok then pendingWrite[n]=nil else log('IO_FLUSH_RETRY',n..'：'..tostring(err)) end
        end
    end
end
-- 包装 gacha 窗口的 on_gui：窗口展开时每帧由加载器回调（钩子栈外），10秒节拍顺带落盘
local prevOnGui=mod.on_gui
if type(prevOnGui)=='function' then
    mod.on_gui=function() prevOnGui() flushPendingIO(10) end
end
local function config()end -- hot hooks consume cached settings only
local function refreshConfig()
    flushPendingLog()
    local now=clock()
    if now-lastConfig<2 then return end
    lastConfig=now
    local text=deferredRead('config.json') -- 优化版：钩子内只读缓存，落盘窗口刷新
    if not text then
        -- 管理器删除旧配置到原子移动之间可能短暂读不到；保留上次配置，不写回覆盖。
        if configLoaded then log('CONFIG_READ_FAILED','配置暂不可读，保留当前模式及参数');return end
        text='{"enabled":true,"growth_mode":"world","debug_log":false}\n'
    end
    if type(text)~='string' or not text:match('^%s*{.*}%s*$') then
        log('CONFIG_READ_FAILED','配置为空或不完整，保留当前模式及参数');return
    end
    if text==configText then return end
    configLoaded=true
    configText=text
    local nextSettings=defaultSettings()
    for _,key in ipairs({'enabled','debug_log','kill_xp_log','suppress_ahead_weapons'}) do
        local value=text:match('"'..key..'"%s*:%s*(%a+)')
        if value=='false' then nextSettings[key]=false
        elseif value=='true' then nextSettings[key]=true
        elseif value and value~='true' then log('CONFIG_INVALID',key..' 使用默认值',true) end
    end
    local mode=text:match('"growth_mode"%s*:%s*"([^"]+)"')
    if mode=='world' or mode=='kill' or mode=='mixed' then nextSettings.growth_mode=mode
    elseif mode then log('CONFIG_INVALID','growth_mode 使用世界进度模式',true) end
    local mp=text:match('"multiplayer_mode"%s*:%s*"([^"]+)"')
    if mp=='off' or mp=='diagnostic' or mp=='world_experimental' then nextSettings.multiplayer_mode=mp end
    local previousMode=settings.growth_mode
    if previousMode~=nextSettings.growth_mode then
        if store and store.dirty and not store:save() then
            nextSettings.growth_mode=settings.growth_mode;configText=nil
            log('MODE_SWITCH_BLOCKED','待保存经验写入失败，保持当前模式并稍后重试',true)
        else
            lastReadWeapon=nil;lastStageCheck=-1
        end
    end
    sourceEntryCache={}
    settings=nextSettings
    if previousMode~=settings.growth_mode then
        log('MODE_SWITCH',previousMode..'→'..settings.growth_mode..'；武器经验保留，世界状态重新读取',true)
    end
    log('CONFIG','mode='..settings.growth_mode..' enabled='..tostring(settings.enabled)..' suppressAhead='..tostring(settings.suppress_ahead_weapons)..' strength='..growthStrength..' cap='..maxMultiplier,true)
end
local function field(t,name)
    local f=P.get_field(t,name)
    if not f then error('缺少字段 '..name) end
    return f
end
local function accessor(t,name,kind)
    local f=P.get_field(t,name)
    if f then
        if P.field_is_instance(f) then
            -- 当前 dump 中 Main.gameMenu 是实例字段，读取 Main.instance 上的值。
            local singleton=field(t,'instance')
            return function()
                local instance=P.get_field_value(singleton,nil,'object')
                if not instance then return nil end
                return P.get_field_value(f,instance,kind)
            end
        end
        return function() return P.get_field_value(f,nil,kind) end
    end
    local prop=P.get_property(t,name)
    local get=prop and P.property_get_method(prop)
    if not get then error('缺少静态状态 '..name) end
    return function() return P.invoke(get) end
end
local readMenu,readWorld,readGameMode
local weaponDamageMethod
local function clearWorld()
    if whipTags then whipTags:restore() end
    stage=0; world=nil; lastStageCheck=-1; lastReadWeapon=nil
    summonDamageFrames={};lastTraceTimes={};sourceEntryCache={}
    if multiplayerProbe then multiplayerProbe:reset() end
    if combat then combat:reset() end
    if projectileSources then projectileSources:reset() end
    cachedProfile=nil
end
local function progress()return cachedProgress end
local function refreshProgress()
    local menu=readMenu()
    if type(menu)~='boolean' then error('gameMenu 返回值异常') end
    if menu then
        if not lastMenu then clearWorld() end
        lastMenu=true; return false
    end
    local mode=P.get_field_value(fields.netMode,nil,'int32')
    if sessionMode~=mode then clearWorld();lastMenu=true;sessionMode=mode
        log('NETWORK_ROLE','netMode='..tostring(mode)..' multiplayerMode='..settings.multiplayer_mode,true)
    end
    if mode~=0 and ((mode~=1 and mode~=3) or settings.multiplayer_mode~='world_experimental') then
        if not lastMenu then clearWorld();lastMenu=true end
        log('MULTIPLAYER_DIAGNOSTIC','只记录联机日志，不修改伤害或经验；服务端不应用客户端倍率');return false
    end
    local modeValue=readGameMode()
    if type(modeValue)~='number' or not S.modeNames[modeValue] then error('GameMode 返回值异常') end
    gameMode=modeValue
    local id=readWorld()
    if type(id)~='number' then error('worldID 返回值异常') end
    if lastMenu or world~=id then
        clearWorld(); world=id; lastMenu=false
        log('WORLD','world='..tostring(id),true)
    end
    local now=clock()
    if now-lastStageCheck>=1 then
        lastStageCheck=now
        local function flag(name)
            local value=P.get_field_value(fields[name],nil,'bool')
            if type(value)~='boolean' then error('进度字段异常 '..name) end
            return value
        end
        local newStage=0
        if flag('downedBoss1') then newStage=1 end
        if flag('downedBoss2') then newStage=2 end
        if flag('downedBoss3') then newStage=3 end
        if flag('hardMode') then newStage=4 end
        local m1,m2,m3=flag('downedMechBoss1'),flag('downedMechBoss2'),flag('downedMechBoss3')
        if m1 or m2 or m3 then newStage=5 end
        if m1 and m2 and m3 then newStage=6 end
        if flag('downedPlantBoss') then newStage=7 end
        if flag('downedGolemBoss') then newStage=8 end
        for _,name in ipairs({'downedAncientCultist','downedTowerSolar','downedTowerVortex','downedTowerNebula','downedTowerStardust'}) do
            if fields[name] and P.get_field_value(fields[name],nil,'bool')==true then newStage=math.max(newStage,9) end
        end
        if flag('downedMoonlord') then newStage=10 end
        if newStage~=stage then
            stage=newStage
            log('STAGE',tostring(stage)..' '..S.names[stage],true)
            sourceEntryCache={}
            log('LEVEL_CAP_UNLOCK','worldStage='..stage..' cap='..StageCaps.cap(stage)..'；有效等级上限更新，原有职业经验保留',true)
            log('WORLD_PERIOD_REFRESH','world='..tostring(world)..' stage='..stage..'；时期系数按本世界重算，职业等级经验独立保留',true)
        end
    end
    return true
end
local function identifyWeapon(item,id)
    if type(id)~='number' or id<=0 then return nil,'invalid_id' end
    local ammo=P.get_field_value(fields.ammo,item,'int32')
    local bomb=itemExclusions and itemExclusions:item_bomb(id)
    local damage=P.get_field_value(fields.damage,item,'int32')
    local snapshot={id=id,damage=damage,ammo=ammo,bomb=bomb==true}
    for _,key in ipairs({'melee','ranged','magic','summon'}) do
        snapshot[key]=P.get_field_value(fields[key],item,'bool')
    end
    for _,key in ipairs({'pick','axe','hammer'}) do
        snapshot[key]=P.get_field_value(fields[key],item,'int32')
    end
    local entry,reason=Reader.identify(snapshot)
    if entry then
        for _,name in ipairs({'noMelee','channel','sentry','consumable'}) do
            if fields[name] then local ok,value=pcall(P.get_field_value,fields[name],item,'bool');if ok then entry[name]=value end end
        end
        for _,name in ipairs({'shoot','useTime','useAmmo'}) do
            if fields[name] then local ok,value=pcall(P.get_field_value,fields[name],item,'int32');if ok then entry[name]=value end end
        end
        if fields.isAWhipSet and type(entry.shoot)=='number' and entry.shoot>=0 then
            local ok,value=pcall(function()
                local set=P.get_field_value(fields.isAWhipSet,nil,'object')
                return set and entry.shoot<P.array_length(set) and P.array_at(set,entry.shoot,'bool')==true
            end)
            entry.isWhip=ok and value==true
        end
        entry.growthDisabled=entry.consumable==true and (entry.category=='ranged' or entry.category=='melee')
        nonGrowingConsumables[id]=entry.growthDisabled or nil
        entry.growthKind,entry.growthLabel=GrowthProfiles.kind(entry)
        if entry.growthDisabled then entry.growthLabel='消耗投掷物（仅压制）' end
    end
    return entry,reason
end
local function resolveWeapon(item,id)
    local entry,reason=identifyWeapon(item,id)
    if not entry then return nil,reason end
    if entry and weaponStages then
        local rarity=P.get_field_value(fields.rare,item,'int32')
        local prefix=P.get_field_value(fields.prefix,item,'uint8')
        entry.origin,entry.originSource=weaponStages:origin(id,clock(),rarity)
        entry.average,entry.sampleCount,entry.referenceStage,entry.referenceKind=weaponStages:reference(entry.category=='summon' and entry.growthKind or entry.category,stage)
        entry.originAverage,entry.originSampleCount=weaponStages:reference(entry.category=='summon' and entry.growthKind or entry.category,entry.origin,true)
        entry.baseDamage=weaponStages:baseDamage(id)
        if not entry.baseDamage and prefix==0 then entry.baseDamage=entry.damage end
        entry.baseDps=weaponStages:baseDps(id)
        if not entry.baseDps and entry.baseDamage then
            local useTime=fields.useTime and P.get_field_value(fields.useTime,item,'int32') or nil
            if type(useTime)~='number' or useTime<=0 then useTime=fields.useAnimation and P.get_field_value(fields.useAnimation,item,'int32') or nil end
            if type(useTime)=='number' and useTime>0 then entry.baseDps=entry.baseDamage*60/useTime end
        end
    end
    return entry,reason
end
local function profile() return cachedProfile end
refreshProfile=function()
 if not profileReader then cachedProfile=nil;return end
 local ok,key=pcall(profileReader)
 cachedProfile=ok and type(key)=='string' and key~='' and key or nil
 if not cachedProfile then log('CHARACTER_UNAVAILABLE','未取得人物存档路径，暂停职业经验与抽奖')end
end
local function classProgress(entry)
    if sessionMode~=0 or entry.growthDisabled then return nil end
    local key=profile()
    if key and store and ensureClassMigration then ensureClassMigration(key) end
    local xp=key and store and store:getClass(key,entry.category,entry.id)
    if xp==nil then return nil end
    return StageCaps.progress(xp,stage)
end
local function classGrowthActive()
    return alive and ready and settings.enabled and progress() and hasKillGrowth()
end
local function meleeCandidate(item)
    if not item then return false end
    local ok,value=pcall(function()
        return P.get_field_value(fields.melee,item,'bool')==true
            or P.get_field_value(fields.axe,item,'int32')>0
            or P.get_field_value(fields.pick,item,'int32')>0
            or P.get_field_value(fields.hammer,item,'int32')>0
    end)
    return ok and value==true
end
local function traceValue(fieldHandle,instance,kind)
    if not fieldHandle then return nil end
    local ok,value=pcall(P.get_field_value,fieldHandle,instance,kind)
    if ok then return value end
    return nil
end
local function shouldTraceWeapon(id,channel)
    if not settings.debug_log or type(id)~='number' then return false end
    local now=clock()
    local key=tostring(channel or 'general')..':'..tostring(id)
    if now-(lastTraceTimes[key] or -1000)<3 then return false end
    lastTraceTimes[key]=now
    return true
end
local function killEntry(item)
    if not classGrowthActive() then return nil end
    local id=P.get_field_value(fields.itemType,item,'int32')
    local entry=identifyWeapon(item,id)
    if entry and entry.growthDisabled then return nil end
    return entry
end
local function skillLevel(item,category)
    local entry=killEntry(item)
    if not entry or (category and entry.category~=category) then return nil,nil end
    local level=classProgress(entry)
    return level,entry
end
local function weaponCrit(player,args,result)
    if type(result)~='number' or not args or not args[1] then return nil end
    local level,entry=skillLevel(args[1])
    if not level or (entry.category~='melee' and entry.category~='ranged' and entry.category~='magic') then return nil end
    local bonus=GrowthProfiles.attributes(level,entry).crit or 0
    if bonus<=0 then return nil end
    return result+bonus
end
local function weaponKnockback(player,args,result)
    if type(result)~='number' or not args or not args[1] then return nil end
    local level,entry=skillLevel(args[1])
    if not level then return nil end
    local bonus=GrowthProfiles.attributes(level,entry).knockback or 0
    if bonus<=0 then return nil end
    return result+bonus
end
local function manaCost(player,args,result)
    if type(result)~='number' or not args or not args[1] then return nil end
    local level,entry=skillLevel(args[1],'magic')
    if not level or level<=0 then return nil end
    local reduced=math.max(0,math.floor(result*(1-(GrowthProfiles.attributes(level,entry).manaCost or 0))+0.5))
    return reduced
end
local function heldItem(player)
    if not heldItemGetter or not player then return nil end
    local ok,item=pcall(P.invoke,heldItemGetter,player)
    return ok and item or nil
end
local function heldEntry(player)
    local item=heldItem(player)
    if not item then return nil,nil end
    local id=P.get_field_value(fields.itemType,item,'int32')
    return identifyWeapon(item,id),item
end
ensureClassMigration=function(key)
    if not store or migratedProfiles[key] then return end
    local categories={};for id,class in pairs(LegacyClasses) do categories[id]=class end
    if weaponStages then
        for id,sample in pairs(weaponStages.samples) do categories[id]=sample.category end
    end
    if store:migrateClasses(key,categories) then
        migratedProfiles[key]=true
        log('CLASS_XP_READY','职业共享经验已读取；旧武器取最高值，未识别记录保留至首次使用',true)
    end
end
local function attackSpeed(player,args,result)
    if type(result)~='number' or result<=0 or not classGrowthActive() then return nil end
    local entry=heldEntry(player)
    if not entry then return nil end
    local level=classProgress(entry)
    if not level or level<=0 then return nil end
    local attrs=GrowthProfiles.attributes(level,entry)
    if attrs.attackSpeed and attrs.attackSpeed>0 then return result*(1+attrs.attackSpeed) end
    local useTime=attrs.useTime or attrs.castSpeed or 0
    if useTime<=0 then return nil end
    return result/(1-useTime)
end
local function meleeScale(player,args,result)
    if type(result)~='number' or not args or not args[1] then return nil end
    local item=args[1]
    if meleeCandidate(item) then
        local id=traceValue(fields.itemType,item,'int32')
        if shouldTraceWeapon(id,'scale') then
            local level,entry=skillLevel(item,'melee')
            local size=level and GrowthProfiles.attributes(level,entry).size or 0
            local adjusted=classGrowthActive() and size>0 and result*(1+size) or result
            log('MELEE_SCALE_TRACE','item='..tostring(id)..' originalScale='..tostring(result)
                ..' level='..tostring(level or 0)..' sizeBonus='..tostring(size or 0)
                ..' adjustedScale='..tostring(adjusted)..' class='..tostring(entry and entry.category or 'unclassified'),true)
        end
    end
    if not classGrowthActive() then return nil end
    local id=P.get_field_value(fields.itemType,args[1],'int32')
    local entry=resolveWeapon(args[1],id)
    if not entry or entry.category~='melee' then return nil end
    local level=classProgress(entry)
    if not level then return nil end
    local size=GrowthProfiles.attributes(level,entry).size or 0
    if size<=0 then return nil end
    return result*(1+size)
end
local gachaGuardsLogged={}
local function gachaGuardMark(name)
 if not gachaGuardsLogged[name] then gachaGuardsLogged[name]=true;log('GACHA_GUARD',name,true)end
end
local manaRegenRemainder=0
local function updateClassAttributes(player)
    if not classGrowthActive() or not fields.playerIndex or not fields.manaRegen or not fields.manaRegenCount then manaRegenRemainder=0;return end
    local localPlayer=readLocalPlayer and readLocalPlayer()
    local playerIndex=P.get_field_value(fields.playerIndex,player,'int32')
    if playerIndex~=localPlayer then return end
    local entry,item=heldEntry(player)
    if not entry then manaRegenRemainder=0;return end
    local level=classProgress(entry)
    if not level or level<=0 then manaRegenRemainder=0;return end
    if entry.category=='magic' then
        local regen=P.get_field_value(fields.manaRegen,player,'int32') or 0
        local numerator=(GrowthProfiles.attributes(level,entry).manaRegen or 0)*regen*200
        manaRegenRemainder=manaRegenRemainder+numerator
        local extra=math.floor(manaRegenRemainder/200) -- 根据当前武器成长路线增加回复量
        manaRegenRemainder=manaRegenRemainder%200
        if extra>0 then
            local count=P.get_field_value(fields.manaRegenCount,player,'int32') or 0
            P.set_field_value(fields.manaRegenCount,player,count+extra,'int32')
        end
    else manaRegenRemainder=0 end
end
local function applySummonMilestones(player)
    -- 平衡版取消职业满级额外召唤栏，不改原版装备提供的召唤栏。
end
local function playerKey(player)
    return (fields.playerIndex and P.get_field_value(fields.playerIndex,player,'int32')) or player
end
local function shotSpeedPrefix(player,args)
    config();progress()
    if projectileSources then projectileSources:beginShot(player,args and args[2]) end
    local key=playerKey(player);local stack=shotSpeedStacks[key] or {};shotSpeedStacks[key]=stack
    -- 每次调用都有栈帧；内层无加成时也不能弹出外层保存的值。
    stack[#stack+1]=false
    if not args or not args[2] then return end
    if not settings.enabled or not progress() then return end
    local item=args[2]
    local id=P.get_field_value(fields.itemType,item,'int32')
    local entry=identifyWeapon(item,id)
    if not classGrowthActive() then return end
    if not entry then return end
    local level=classProgress(entry)
    if not level or level<=0 then return end
    local bonus=GrowthProfiles.attributes(level,entry).projectileSpeed or 0
    if bonus<=0 then return end
    local old=P.get_field_value(fields.shootSpeed,item,'float')
    if type(old)~='number' or old<=0 then return end
    stack[#stack]={item=item,value=old}
    P.set_field_value(fields.shootSpeed,item,old*(1+bonus),'float')
end
local function shotSpeedPostfix(player,args)
    if projectileSources then projectileSources:endShot() end
    local key=playerKey(player);local stack=shotSpeedStacks[key]
    if not stack or #stack==0 then return end
    local saved=table.remove(stack)
    if saved and saved.item then P.set_field_value(fields.shootSpeed,saved.item,saved.value,'float') end
    if #stack==0 then shotSpeedStacks[key]=nil end
end
local function ammoCostPrefix(player,args)
    local key=playerKey(player);local stack=ammoCostStacks[key] or {};ammoCostStacks[key]=stack
    stack[#stack+1]=false
    if not classGrowthActive() or not args or not args[1] or args[8]==true then return end
    local item=args[1]
    local id=P.get_field_value(fields.itemType,item,'int32')
    local entry=identifyWeapon(item,id)
    if not entry or entry.category~='ranged' then return end
    local level=classProgress(entry)
    if not level or level<=0 then return end
    local desired=GrowthProfiles.attributes(level,entry).ammoSave or 0
    if desired<=0 then return end
    local old80=P.get_field_value(fields.ammoCost80,player,'bool')==true
    local old75=P.get_field_value(fields.ammoCost75,player,'bool')==true
    if old80 or old75 then return end
    -- ammoCost75 是原版25%保留判定；按比例触发可精确实现成长提供的节省率。
    if math.random()<math.min(1,desired/0.25) then
        stack[#stack]={old80=old80,old75=old75}
        P.set_field_value(fields.ammoCost75,player,true,'bool')
    end
end
local function ammoCostPostfix(player)
    local key=playerKey(player);local stack=ammoCostStacks[key]
    if not stack or #stack==0 then return end
    local saved=table.remove(stack)
    if saved then
        P.set_field_value(fields.ammoCost80,player,saved.old80,'bool')
        P.set_field_value(fields.ammoCost75,player,saved.old75,'bool')
    end
    if #stack==0 then ammoCostStacks[key]=nil end
end
local function growthMultiplier(entry)
    local levelCoefficient=1
    if hasKillGrowth() then
        local level=classProgress(entry)
        entry.hasKillGrowth=level~=nil and level>0
        if level then
            levelCoefficient=S.kill_damage_multiplier(level,entry.category)
            -- 基础伤害按职业共享等级增长；武器特色只分配有效属性。
        end
    end
    local period,kind,stageCoefficient,extraCoefficient=Suppression.calculate(stage,entry.origin,entry.id,settings.suppress_ahead_weapons)
    if type(entry.origin)=='number' and entry.origin<stage then
        period,kind=S.world_growth(stage,entry.origin,worldGrowthAllowed() and not entry.growthDisabled)
    end
    entry.stageCoefficient=stageCoefficient;entry.extraCoefficient=extraCoefficient
    if shouldTraceWeapon(entry.id,'suppression') then
        log('SUPPRESSION_RULE','item='..entry.id..' worldStage='..stage..' origin='..tostring(entry.origin)
            ..' stageMultiplier='..tostring(stageCoefficient)..' extraMultiplier='..tostring(extraCoefficient)
            ..' tags='..Suppression.tags(entry.id)..' reason='..kind,true)
    end
    if kind=='unknown_source' and not lastNotice['unknown:'..entry.id] then
        lastNotice['unknown:'..entry.id]=true
        log('SUPPRESSION_SOURCE_UNKNOWN','item='..entry.id..'；来源待补，不伪报为当前时期，不按稀有度猜测',true)
    end
    entry.levelCoefficient=levelCoefficient
    entry.periodCoefficient=period
    entry.worldMultiplier=math.max(1,period)
    entry.suppressionCoefficient=math.min(1,period)
    entry.balanceKind=kind
    entry.limit=period
    entry.finalCoefficient=S.combine_coefficients(period,levelCoefficient,maxMultiplier)
    return entry.finalCoefficient
end
refreshWhipTags=function(player)
    if not whipTags then return end
    if not alive or not ready or not settings.enabled or sessionMode~=0 then whipTags:restore();return end
    if not fields.playerIndex or P.get_field_value(fields.playerIndex,player,'int32')~=readLocalPlayer() then return end
    config()
    if not settings.enabled or not progress() or sessionMode~=0 then whipTags:restore();return end
    local levelCoefficient,xp,key=1,0,'world'
    if hasKillGrowth() then
        key=profile()
        if key and store then
            ensureClassMigration(key);xp=store:getClass(key,'summon')
            if xp then levelCoefficient=S.kill_damage_multiplier(StageCaps.progress(xp,stage),'summon') end
        end
    end
    local revision=table.concat({tostring(world),tostring(stage),settings.growth_mode,tostring(key),tostring(xp),tostring(settings.suppress_ahead_weapons)},':')
    whipTags:update(function(id)
        local origin=weaponStages:origin(id,clock(),nil)
        local average=weaponStages:reference('summon_whip',stage)
        local originAverage=weaponStages:reference('summon_whip',origin,true)
        local period=Suppression.calculate(stage,origin,id,settings.suppress_ahead_weapons)
        if type(origin)=='number' and origin<stage then
            period=S.world_growth(stage,origin,worldGrowthAllowed())
        end
        return S.combine_coefficients(period,levelCoefficient,maxMultiplier)
    end,revision)
end
local function refreshSourceEntry(binding)
    if not binding or not binding.entry then return nil end
    local now=clock()
    local cached=sourceEntryCache[binding.weaponId]
    if cached and cached.time==now and cached.stage==stage and cached.world==world then return cached.entry,cached.multiplier end
    local entry={};for k,v in pairs(binding.entry) do entry[k]=v end
    if weaponStages then
        entry.origin,entry.originSource=weaponStages:origin(entry.id,clock(),nil)
        entry.average,entry.sampleCount,entry.referenceStage,entry.referenceKind=weaponStages:reference(entry.category=='summon' and entry.growthKind or entry.category,stage)
        entry.originAverage,entry.originSampleCount=weaponStages:reference(entry.category=='summon' and entry.growthKind or entry.category,entry.origin,true)
    end
    local multiplier=growthMultiplier(entry)
    sourceEntryCache[binding.weaponId]={time=now,stage=stage,world=world,entry=entry,multiplier=multiplier}
    return entry,multiplier
end
local function summonDamagePrefix(projectile,owner,weaponId,binding)
    config()
    if not alive or not ready or not settings.enabled or not progress() then return nil end
    if type(owner)~='number' or not readLocalPlayer or owner~=readLocalPlayer() then return nil end
    local entry,multiplier=refreshSourceEntry(binding)
    if not entry or entry.id~=weaponId then
        if shouldTraceWeapon(owner,'summon-unbound') then
            log('SUMMON_SOURCE_UNKNOWN','owner='..owner..'；无确认来源，不按最近武器猜测倍率；请重召唤',true)
        end
        return nil
    end
    if type(multiplier)~='number' or multiplier<=0 then return nil end
    local damageField=fields.projectileDamage
    if not damageField then return nil end
    local original=P.get_field_value(damageField,projectile,'int32')
    if type(original)~='number' or original<=0 then return nil end
    local key=tostring(owner)..':'..tostring(binding.slot)..':'..tostring(binding.identity)
    if summonDamageFrames[key] then return nil end
    local embedded=binding.embeddedCoefficient or 1
    if type(embedded)~='number' or embedded<=0 then embedded=1 end
    local applied=multiplier/embedded
    local adjusted=S.damage(original,applied)
    if original*applied<1 and shouldTraceWeapon(weaponId,'damage-floor') then
        log('DAMAGE_FLOOR','item='..weaponId..' expected='..tostring(original*applied)..' actual=1；最低伤害限制，继续降低倍率可能无效',true)
    end
    if shouldTraceWeapon(weaponId,'summon-hit') then
        log('PROJECTILE_HIT_SCALE','item='..weaponId..' projectileBase='..original
            ..' period='..string.format('%.4f',entry.periodCoefficient)..' level='..string.format('%.4f',entry.levelCoefficient)
            ..' total='..string.format('%.4f',multiplier)..' inherited='..string.format('%.4f',embedded)..' applied='..string.format('%.4f',applied)..' hitDamage='..adjusted..' changed='..tostring(adjusted~=original),true)
    end
    if adjusted==original then return nil end
    summonDamageFrames[key]=true
    P.set_field_value(damageField,projectile,adjusted,'int32')
    return {original=original,key=key,coefficient=multiplier}
end
local function summonDamagePostfix(projectile,token)
    if token and fields.projectileDamage then
        P.set_field_value(fields.projectileDamage,projectile,token.original,'int32')
        summonDamageFrames[token.key]=nil
    end
end
local function scaleDamage(player,args,result)
    if not alive or not ready or panelNativeDepth>0 then return nil end
    local ok,value=pcall(function()
        config()
        local item=args and args[1]
        if not item then return nil end
        local id=P.get_field_value(fields.itemType,item,'int32')
        local meleeDebug=meleeCandidate(item) and progress() and settings.enabled
        local emitDamageTrace=meleeDebug and shouldTraceWeapon(id,'damage')
        if emitDamageTrace then
            local category,reason=identifyWeapon(item,id)
            log('MELEE_WEAPON_DAMAGE_TRACE','item='..tostring(id)..' category='..tostring(category and category.category or 'unclassified')
                ..' reason='..tostring(reason or 'classified')..' itemDamage='..tostring(traceValue(fields.damage,item,'int32'))
                ..' getWeaponDamage='..tostring(result)..' mode='..settings.growth_mode..' stage='..stage,true)
        end
        if meleeCandidate(item) and (type(result)~='number' or result<=0 or result~=result or result==math.huge) then
            if shouldTraceWeapon(id,'damage-suspect') then
                log('MELEE_DAMAGE_SUSPECT','item='..tostring(id)..' invalid GetWeaponDamage result='..tostring(result)
                    ..' itemDamage='..tostring(traceValue(fields.damage,item,'int32')),true)
            end
            return nil
        end
        if not progress() or not settings.enabled then return nil end
        if sessionMode~=0 and (not player or P.get_field_value(fields.playerIndex,player,'int32')~=readLocalPlayer()) then return nil end
        if type(result)~='number' or result<=0 or result~=result then return nil end
        local entry,reason=resolveWeapon(item,id)
        if not entry then log('UNSUPPORTED','item='..tostring(id)..' reason='..tostring(reason)); return nil end
        -- 召唤武器的真实命中伤害在 Projectile.Damage 内缩放；这里仅供面板/说明展示，避免生成召唤物时重复加成。
        if entry.category=='summon' then return nil end
        local identity=tostring(id)..':'..entry.category
        if lastReadWeapon~=identity then
            lastReadWeapon=identity
            log('WEAPON_READ','item='..id..' class='..entry.category..' growthMode='..settings.growth_mode..' mode='..gameMode..' stage='..stage..' origin='..tostring(entry.origin)..' originSource='..tostring(entry.originSource)..' cap='..maxMultiplier)
        end
        local multiplier=growthMultiplier(entry)
        status=entry.name..'｜'..(S.names[stage] or '未知时期')..'｜'..S.modeNames[gameMode]..'｜倍率×'..string.format('%.2f',multiplier)
        if multiplier==1 then
            log('UNCHANGED','item='..id..' origin='..tostring(entry.origin)..' worldStage='..stage..' reason='..tostring(entry.balanceKind)..' '..status)
            return nil
        end
        local damage=S.damage(result,multiplier)
        if entry.balanceKind=='period_suppression' then
            local tag=hasKillGrowth() and multiplier>=1 and 'GROWTH_WITH_SUPPRESSION' or 'SUPPRESSED'
            log(tag,'item='..id..' class='..entry.category..' growthMode='..settings.growth_mode..' worldStage='..stage..' origin='..tostring(entry.origin)..' weaponDps='..tostring(entry.baseDps)..' referenceStage='..tostring(entry.referenceStage)..' referenceKind='..tostring(entry.referenceKind)..' referenceDps='..tostring(entry.average)..' samples='..tostring(entry.sampleCount)..' suppression='..string.format('%.3f',entry.limit or 1)..' final='..string.format('%.3f',multiplier)..' '..result..'→'..damage)
        end
        log('COEFFICIENTS','item='..id..' origin='..tostring(entry.origin)..' worldStage='..stage..' period='..string.format('%.4f',entry.periodCoefficient)..' level='..string.format('%.4f',entry.levelCoefficient)..' final='..string.format('%.4f',multiplier))
        log('DAMAGE','world='..tostring(world)..' mode='..gameMode..' stage='..stage..' growthMode='..settings.growth_mode..' class='..entry.category..' item='..id..' '..entry.name..' original='..result..' multiplier='..string.format('%.3f',multiplier)..' result='..damage)
        return damage
    end)
    if not ok then
        ready=false; status='运行错误，成长已停用'
        log('RUNTIME_DISABLED',tostring(value),true)
        return nil
    end
    return value
end
-- 只显示当前等级的非零加成，每行最多三项，避免手机面板横向溢出。
local function compactAttributes(entry,level)
    if not level or level<=0 then return '' end
    local a=GrowthProfiles.attributes(level,entry)
    local parts={}
    local function add(label,value,percent,negative)
        if type(value)~='number' or value<=0 then return end
        local amount=percent and value*100 or value
        local number=string.format('%.2f',amount):gsub('0+$',''):gsub('%.$','')
        parts[#parts+1]=label..(negative and '-' or '+')..number..(percent and '%' or '')
    end
    add('伤害',(entry.levelCoefficient or 1)-1,true)
    if entry.category=='melee' then
        add('暴击',a.crit and a.crit/100,true)
        add('攻速',a.attackSpeed,true);add('击退',a.knockback)
        add('尺寸',a.size,true);add('弹速',a.projectileSpeed,true)
    elseif entry.category=='ranged' then
        add('暴击',a.crit and a.crit/100,true)
        add('攻速',a.useTime and a.useTime/(1-a.useTime),true)
        add('弹速',a.projectileSpeed,true);add('省弹',a.ammoSave,true);add('击退',a.knockback)
    elseif entry.category=='magic' then
        add('暴击',a.crit and a.crit/100,true)
        add('施速',a.castSpeed and a.castSpeed/(1-a.castSpeed),true)
        add('耗蓝',a.manaCost,true,true);add('回蓝',a.manaRegen,true);add('弹速',a.projectileSpeed,true)
    elseif entry.category=='summon' then
        add('攻速',a.attackSpeed,true);add('击退',a.knockback)
        local shoot=entry.shoot
        if fields.isAWhipSet and type(shoot)=='number' and shoot>=0 then
            local set=P.get_field_value(fields.isAWhipSet,nil,'object')
            if set and shoot<P.array_length(set) and P.array_at(set,shoot,'bool')==true then add('鞭长',a.whipRange,true) end
        end
    end
    local rows={}
    for i=1,#parts,3 do
        local row={}
        for j=i,math.min(i+2,#parts) do row[#row+1]=parts[j] end
        rows[#rows+1]=table.concat(row,' ')
    end
    return #rows>0 and ('\n'..table.concat(rows,'\n')) or ''
end
-- MouseText_DrawItemTooltip_GetLinesInfo 构造最终伤害面板的字符串数组；
-- ItemTooltip.GetLine 只负责描述文本，不能可靠改变面板中的伤害数值。
local function updateDamagePanel(main,args)
    if not alive or not ready then return nil end
    local ok,err=pcall(function()
        config()
        if not settings.enabled or not progress() then return end
        local item=args and args[1]
        local lineArray=args and args[7]
        if not item or not lineArray then return end
        local id=P.get_field_value(fields.itemType,item,'int32')
        local entry=resolveWeapon(item,id)
        if not entry then return end
        local original=P.get_field_value(fields.damage,item,'int32')
        if type(original)~='number' or original<=0 then return end
        local multiplier=growthMultiplier(entry)
        local length=P.array_length(lineArray)
        for index=0,length-1 do
            local raw=P.array_at(lineArray,index,'string')
            local line=P.string_value(raw)
            local lowered=type(line)=='string' and line:lower() or ''
            local isDamageLine=type(line)=='string' and line:match('^%s*%d+')~=nil and not (line:find('标记',1,true) or lowered:find('tag damage',1,true)) and (line:find('伤害',1,true)~=nil or lowered:find('damage',1,true)~=nil or line:find('ダメージ',1,true)~=nil)
            if isDamageLine then
                local marker=line:find('\n（成长',1,true) or line:find('\n（压制',1,true)
                    or line:find('（成长×',1,true) or line:find('（压制×',1,true)
                if marker then line=line:sub(1,marker-1) end
                local nativeDamage
                if weaponDamageMethod then
                    local players=P.get_field_value(fields.playerArray,nil,'object')
                    local index=readLocalPlayer and readLocalPlayer()
                    local player=players and type(index)=='number' and index>=0 and index<P.array_length(players) and P.array_at(players,index,'object')
                    if player then
                        -- invoke 可能经过 Hook，也可能直接到原方法；两种情况都只获取原版伤害。
                        panelNativeDepth=panelNativeDepth+1
                        local success,value=pcall(P.invoke,weaponDamageMethod,player,item)
                        panelNativeDepth=panelNativeDepth-1
                        if success and type(value)=='number' and value>0 and value<math.huge then nativeDamage=value end
                    end
                end
                -- 重用已改写的字符串时必须重取原版值，不能把上次结果再乘一次。
                if marker and not nativeDamage then
                    log('PANEL_BASE_UNAVAILABLE','item='..id..'；缓存面板无法取得原版伤害，跳过重复缩放')
                    return
                end
                local changed=false
                local shownDamage,adjustedDamage
                local output=line:gsub('%d+',function(token)
                    local value=tonumber(token)
                    if not changed and value and value>0 then
                        changed=true
                        shownDamage=value
                        adjustedDamage=S.damage(nativeDamage or value,multiplier)
                        return tostring(adjustedDamage)
                    end
                    return token
                end,1)
                if changed then
                    local label=multiplier<1 and '压制' or '成长'
                    output=output..'（'..label..'×'..string.format('%.2f',multiplier)..'）'
                    local sourceName=S.names[entry.origin] or '来源待核对'
                    output=output..'\n来源：'..sourceName..'｜世界：'..(S.names[stage] or '?')
                    output=output..'\n世界成长+'..string.format('%.0f',((entry.worldMultiplier or 1)-1)*100)..'% 职业成长+'..string.format('%.0f',((entry.levelCoefficient or 1)-1)*100)..'%'
                    if (entry.suppressionCoefficient or 1)<1 then output=output..' 压制×'..string.format('%.3f',entry.suppressionCoefficient) end
                    output=output..'\n'..(entry.growthLabel or Reader.names[entry.category])
                    if entry.growthDisabled then
                        output=output..'\n不享受成长属性、不获取职业经验'
                    elseif hasKillGrowth() then
                        local level,current,need,stored,cap=classProgress(entry)
                        local progressText=level and (need==0 and (cap==20 and '满级' or '已达当前世界上限') or ('经验 '..current..'/'..need)) or '经验暂不可读'
                        entry.shoot=fields.shoot and P.get_field_value(fields.shoot,item,'int32')
                        output=output..'\n'..Reader.names[entry.category]..' Lv.'..tostring(level or '?')..'/'..tostring(cap or StageCaps.cap(stage))..'｜'..progressText
                        if stored and level and stored>level then output=output..'\n存档 Lv.'..stored..'｜当前生效 Lv.'..level end
                        output=output..compactAttributes(entry,level)
                    else
                        output=output..'\n世界进度模式｜等级成长关闭'
                    end
                    if P.array_set(lineArray,index,output,'string') then
                        log('PANEL_DAMAGE','item='..id..' line='..index..' mode=explicit_once base='..tostring(nativeDamage or shownDamage)..' shown='..shownDamage..' result='..adjustedDamage..' multiplier='..string.format('%.4f',multiplier))
                    end
                    return
                end
            end
        end
        log('PANEL_LINE_MISSING','item='..id..' damage='..original)
    end)
    if not ok then log('PANEL_SKIPPED',tostring(err)) end
    return nil
end
function setup()
    local ok,err=pcall(function()
        -- Load historical log before appending this session's messages.
        -- 跨重启保留最近记录，避免切换现场在下一次 INIT 时丢失。
        local previous=mod.read_file('weapon_growth_runtime.log')
        if type(previous)=='string' and #previous<=524288 then
            for line in previous:gmatch('[^\r\n]+') do
                if line:find('[WG]',1,true) then
                    lines[#lines+1]=line
                    if #lines>512 then table.remove(lines,1) end
                end
            end
        end
        log('INIT','v'..tostring(mod.meta and mod.meta.version or 'unknown')..' platform='..tostring(mod.platform)..' arch='..tostring(mod.arch),true)
        log('GACHA_DEFERRED','抽奖任务移至独立低频维护入口；保留本地图集、名称、券账及历史',true)
        refreshConfig()
        store=ProgressStore.open(function(name) return deferredRead(name,true) end,deferredWrite,function(tag,message) log(tag,message,true) end)
        for _,name in ipairs({'get_type','get_field','get_property','property_get_method','get_field_value','get_inner_type','field_is_instance','get_method_by_param_types','get_method_by_names','install_hook','method_is_instance','method_param_count','array_length','array_at','array_set','string_value'}) do
            if type(P[name])~='function' then error('LuaLoader 能力缺失 '..name) end
        end
        local player=P.get_type('Terraria','Player')
        local item=P.get_type('Terraria','Item')
        local main=P.get_type('Terraria','Main')
        local npc=P.get_type('Terraria','NPC')
        if not player or not item or not main or not npc then error('游戏类型不完整') end
        readMenu=accessor(main,'gameMenu','bool'); readWorld=accessor(main,'worldID','int32'); readGameMode=accessor(main,'GameMode','int32')
        fields.netMode=field(main,'netMode');fields.hardMode=field(main,'hardMode')
        for _,name in ipairs({'downedBoss1','downedBoss2','downedBoss3','downedMechBoss1','downedMechBoss2','downedMechBoss3','downedPlantBoss','downedGolemBoss','downedMoonlord'}) do fields[name]=field(npc,name) end
        for _,name in ipairs({'downedAncientCultist','downedTowerSolar','downedTowerVortex','downedTowerNebula','downedTowerStardust'}) do fields[name]=P.get_field(npc,name) end
        fields.itemType=field(item,'type')
        fields.playerArray=field(main,'player')
        fields.damage=field(item,'damage')
        fields.useAnimation=P.get_field(item,'useAnimation')
        fields.useTime=P.get_field(item,'useTime')
        fields.npcWhoAmI=field(npc,'whoAmI')
        fields.npcLife=field(npc,'life')
        fields.shoot=P.get_field(item,'shoot')
        for _,name in ipairs({'melee','ranged','magic','summon','pick','axe','hammer','ammo','rare','prefix'}) do fields[name]=field(item,name) end
        fields.consumable=field(item,'consumable');fields.noMelee=P.get_field(item,'noMelee');fields.shootSpeed=P.get_field(item,'shootSpeed')
        for _,name in ipairs({'channel','sentry','useAmmo'}) do fields[name]=P.get_field(item,name) end
        fields.playerIndex=P.get_field(player,'whoAmI')
        fields.manaRegen=P.get_field(player,'manaRegen')
        fields.manaRegenCount=P.get_field(player,'manaRegenCount')
        fields.whipRangeMultiplier=P.get_field(player,'whipRangeMultiplier')
        fields.maxMinions=P.get_field(player,'maxMinions')
        fields.ammoCost80=P.get_field(player,'ammoCost80');fields.ammoCost75=P.get_field(player,'ammoCost75')
        local projectileID=P.get_type('Terraria.ID','ProjectileID')
        local projectileType=P.get_type('Terraria','Projectile')
        fields.projectileDamage=projectileType and P.get_field(projectileType,'damage')
        local projectileSets=projectileID and P.get_inner_type(projectileID,'Sets')
        fields.isAWhipSet=projectileSets and P.get_field(projectileSets,'IsAWhip')
        local heldProperty=P.get_property(player,'HeldItem')
        heldItemGetter=heldProperty and P.property_get_method(heldProperty)
        if not heldItemGetter then log('HELD_ITEM_UNAVAILABLE','持有武器成长属性暂不可用',true) end
        itemExclusions=ItemExclusions.open(P,log)
        weaponStages=WeaponStage.open(P,log,itemExclusions)
        -- 名称和参数类型均核对，避免命中不同重载。
        local byType=P.get_method_by_param_types(player,'GetWeaponDamage',{item})
        local byName=P.get_method_by_names(player,'GetWeaponDamage',{'sItem'})
        if not byType or not byName then error('缺少 GetWeaponDamage(Item sItem)') end
        if P.method_param_count(byType)~=1 or not P.method_is_instance(byType) then error('GetWeaponDamage 签名不符') end
        weaponDamageMethod=byType
        local hook=P.install_hook(byType,{_wg_key='Player.GetWeaponDamage(Item)',postfix=scaleDamage,override_result=true})
        if not hook then error('伤害 Hook 安装失败') end
        hooks[#hooks+1]=hook;ready=true
        local function addAttributeHook(name,parameterNames,callback,isStatic)
            local method=P.get_method_by_names(player,name,parameterNames)
            if method and P.method_is_static(method)==(isStatic==true) then
                local attributeHook=P.install_hook(method,{postfix=callback,override_result=true})
                if attributeHook then hooks[#hooks+1]=attributeHook;return true end
            end
            log('ATTRIBUTE_HOOK_UNAVAILABLE',name..' 属性成长不可用',true)
            return false
        end
        addAttributeHook('GetWeaponCrit',{'sItem'},weaponCrit,false)
        addAttributeHook('GetWeaponKnockback',{'sItem','KnockBack'},weaponKnockback,false)
        addAttributeHook('ItemCheck_PayMana_GetManaCostToPay',{'sItem','altFire'},manaCost,true)
        local speedMethod=P.get_method_by_names(player,'TurnAttackSpeedToUseTimeMultiplier',{'speed'})
        if speedMethod and not P.method_is_static(speedMethod) then
            local speedHook=P.install_hook(speedMethod,{postfix=attackSpeed,override_result=true})
            if speedHook then hooks[#hooks+1]=speedHook else log('ATTRIBUTE_HOOK_UNAVAILABLE','攻速属性 Hook 安装失败',true) end
        else log('ATTRIBUTE_HOOK_UNAVAILABLE','攻速转换方法不可用',true) end
        addAttributeHook('GetAdjustedItemScale',{'item'},meleeScale,false)
        local shootMethod=P.get_method_by_names(player,'ItemCheck_Shoot',{'i','sItem','weaponDamage','withAudioVisualFeedback'})
        if shootMethod and P.method_is_instance(shootMethod) and fields.shootSpeed then
            local shootHook=P.install_hook(shootMethod,{prefix=shotSpeedPrefix,postfix=shotSpeedPostfix})
            if shootHook then hooks[#hooks+1]=shootHook else log('ATTRIBUTE_HOOK_UNAVAILABLE','射弹速度 Hook 安装失败',true) end
        else log('ATTRIBUTE_HOOK_UNAVAILABLE','ItemCheck_Shoot 射弹速度 Hook 不可用',true) end
        local ammoMethod=P.get_method_by_names(player,'PickAmmo',{'sItem','projToShoot','speed','canShoot','Damage','KnockBack','usedAmmoItemId','dontConsume'})
        if ammoMethod and P.method_is_instance(ammoMethod) and fields.ammoCost80 and fields.ammoCost75 then
            local ammoHook=P.install_hook(ammoMethod,{prefix=ammoCostPrefix,postfix=ammoCostPostfix})
            if ammoHook then hooks[#hooks+1]=ammoHook else log('ATTRIBUTE_HOOK_UNAVAILABLE','弹药节省 Hook 安装失败',true) end
        else log('ATTRIBUTE_HOOK_UNAVAILABLE','PickAmmo 弹药节省 Hook 不可用',true) end
        local updateMethod=P.get_method(player,'Update',1)
        if updateMethod and P.method_is_instance(updateMethod) then
            local manaHook=P.install_hook(updateMethod,{postfix=updateClassAttributes})
            if manaHook then hooks[#hooks+1]=manaHook else log('ATTRIBUTE_HOOK_UNAVAILABLE','魔力回复 Hook 安装失败',true) end
        else log('ATTRIBUTE_HOOK_UNAVAILABLE','Player.Update Hook 不可用',true) end
        local resetMethod=P.get_method(player,'ResetEffects',0)
        if resetMethod and P.method_is_instance(resetMethod) then
            local summonHook=P.install_hook(resetMethod,{postfix=function(player) refreshWhipTags(player);applySummonMilestones(player) end})
            if summonHook then hooks[#hooks+1]=summonHook else log('ATTRIBUTE_HOOK_UNAVAILABLE','召唤里程碑 Hook 安装失败',true) end
        else log('ATTRIBUTE_HOOK_UNAVAILABLE','ResetEffects Hook 不可用',true) end
        whipTags=WhipTagGrowth.open(P,log)
        local identityOK,identityErr=pcall(function()
            local readFile=accessor(main,'ActivePlayerFileData','object')
            gachaReadFile=readFile
            readLocalPlayer=accessor(main,'myPlayer','int32')
            local fileType=P.get_type('Terraria.IO','FileData')
            local pathProperty=fileType and P.get_property(fileType,'Path')
            local cloudProperty=fileType and P.get_property(fileType,'IsCloudSave')
            local pathGetter=pathProperty and P.property_get_method(pathProperty)
            local cloudGetter=cloudProperty and P.property_get_method(cloudProperty)
            assert(pathGetter and cloudGetter,'缺少人物存档路径读取接口')
            profileReader=function()
                local file=readFile();if not file then return nil end
                local value=P.invoke(pathGetter,file)
                local path=type(value)=='string' and value or (value and P.string_value(value))
                local cloud=P.invoke(cloudGetter,file)
                if type(path)~='string' or path=='' or type(cloud)~='boolean' then return nil end
                return (cloud and 'cloud:' or 'local:')..path
            end
        end)
        if not identityOK then log('CHARACTER_UNAVAILABLE',tostring(identityErr),true) end
        gachaRuntime=GachaRuntime.open(P,{
            read=function(name) return deferredRead(name,true) end,
            write=deferredWrite,clock=os.time,
            log=function(tag,msg)log(tag,msg,true)end,
            profile=profile,file=function()return gachaReadFile and gachaReadFile()end,
            identify=function(it,id)
                local entry,reason=identifyWeapon(it,id)
                if entry then entry.categories={[entry.category]=true};return entry end
                if reason~='mixed_class' then return nil end
                local categories={};local first
                for _,c in ipairs({'melee','ranged','magic','summon'})do
                    if P.get_field_value(fields[c],it,'bool')==true then categories[c]=true;first=first or c end
                end
                return first and {category=first,categories=categories,name='混合武器#'..id} or nil
            end,
        })
        if gachaUiReady then GachaUI.bind(gachaRuntime)end

        projectileSources=ProjectileSources.install(P,{
            log=log,
            damagePrefix=summonDamagePrefix,damagePostfix=summonDamagePostfix,
            capture=function(player,item)
                config()
                if not alive or not ready or not settings.enabled or not progress() then return nil end
                local owner=P.get_field_value(fields.playerIndex,player,'int32')
                if owner~=readLocalPlayer() then return nil end
                local id=P.get_field_value(fields.itemType,item,'int32')
                local entry=resolveWeapon(item,id)
                if not entry then return nil end
                local coefficient=growthMultiplier(entry)
                return {owner=owner,weaponId=id,category=entry.category,entry=entry,
                    embeddedCoefficient=entry.category=='summon' and 1 or coefficient,
                    projectileType=fields.shoot and P.get_field_value(fields.shoot,item,'int32')}
            end,
        })
        if identityOK then
            combat=Combat.install(P,{
                log=log,profile=profile,localPlayer=readLocalPlayer,
                active=function() config();return alive and ready and settings.enabled and progress() end,
                bossKill=function(key,id)if gachaRuntime then gachaRuntime:boss(key,id)end end,
                worldStage=function() return stage end,
                identify=function(weapon)
                    local id=P.get_field_value(fields.itemType,weapon,'int32')
                    return identifyWeapon(weapon,id)
                end,
                projectileSource=function(projectile) return projectileSources and projectileSources:lookup(projectile) end,
                summonStrikeBegin=function(npc,args,weaponId)
                    if not settings.enabled or not shouldTraceWeapon(weaponId or -1,'summon-strike') then return nil end
                    return {weaponId=weaponId or 'unknown',damage=args[1],crit=args[4],
                        slot=traceValue(fields.npcWhoAmI,npc,'int32'),life=traceValue(fields.npcLife,npc,'int32')}
                end,
                summonStrikeEnd=function(npc,args,result,trace)
                    log('SUMMON_STRIKE','item='..trace.weaponId..' npcSlot='..tostring(trace.slot)
                        ..' damageArg='..tostring(trace.damage)..' returnDamage='..tostring(result)
                        ..' crit='..tostring(trace.crit)..' life='..tostring(trace.life)..'→'
                        ..tostring(traceValue(fields.npcLife,npc,'int32')),true)
                end,
                award=function(key,class,xp,sourceId,owner,isBoss,maxLife)
                    if not hasKillGrowth()then return end
                    if nonGrowingConsumables[sourceId] then return end
                    if type(xp)~='number' or xp<=0 then return end
                    ensureClassMigration(key)
                    local currentXP=store:getClass(key,class,sourceId)
                    if currentXP==nil then return end
                    xp=StageCaps.allowed(currentXP,xp,stage)
                    if xp<=0 then return end
                    local result,saved=store:awardClass(key,class,xp)
                    if not result then return end
                    sourceEntryCache={} -- 等级变动后下一次命中立即重算。
                    local beforeLevel=ProgressStore.level(result.total-result.added)
                    local after=ProgressStore.level(result.total)
                    if settings.kill_xp_log then
                        log('KILL_XP','source='..tostring(sourceId)..' class='..class..' +'..result.added..' total='..result.total..' shared=true boss='..tostring(isBoss)..' saved='..tostring(saved),true,true)
                    end
                    if after>beforeLevel then
                        log('LEVEL_UP',Reader.names[class]..'熟练度 '..beforeLevel..'→'..after..'；同职业武器共享',true,true)
                    end
                    -- Experience stays dirty until the maintenance autosave.
                end
            })
        end
        local panelMethod=P.get_method(main,'MouseText_DrawItemTooltip_GetLinesInfo',12)
        if panelMethod and P.method_is_static(panelMethod) then
            local panelHook=P.install_hook(panelMethod,{postfix=updateDamagePanel})
            if panelHook then hooks[#hooks+1]=panelHook;log('PANEL_READY','已挂接最终伤害面板行',true)
            else log('PANEL_UNAVAILABLE','面板行 Hook 未安装',true) end
        else log('PANEL_UNAVAILABLE','面板行方法不可用',true) end
        log('TOOLTIP_READY','简洁面板：最终倍率、获取时期/攻击方式、当前模式或职业经验；标记行不重复缩放',true)
        multiplayerProbe=MultiplayerProbe.install(P,{
            log=log,mode=function() return P.get_field_value(fields.netMode,nil,'int32') end,
            localPlayer=readLocalPlayer,
            enabled=function() return alive and sessionMode~=0 and settings.multiplayer_mode~='off' end,
        })
        local playersField=field(main,'player')
        maintenance=function()
            local now=clock()
            if not alive or now-maintenanceLast<2 then return end
            maintenanceLast=now;maintenanceActive=true
            local ok,err=pcall(function()
                refreshConfig()
                cachedProgress=refreshProgress()
                refreshProfile()
                if gachaRuntime and cachedProgress and sessionMode==0 and cachedProfile then
                    local players=P.get_field_value(playersField,nil,'object')
                    local index=readLocalPlayer()
                    if players and type(index)=='number' and index>=0 and index<P.array_length(players)then
                        local player=P.array_at(players,index,'object')
                        if player then gachaRuntime:tick(player)elseif gachaRuntime then gachaRuntime:suspend()end
                    end
                elseif gachaRuntime then gachaRuntime:suspend()end
                if store and store.dirty then store:save()end
                if now-lastCompatSummary>=60 then
                    lastCompatSummary=now
                    local st=P._compat_stats
                    if st then log('COMPAT_HEALTH','nativeHooks='..st.native..' callbacks='..st.callbacks..' errors='..st.errors..' maxDepth='..st.maxDepth,true)end
                end
if logDirty then saveLog()end
                 -- 优化版兜底：60秒一次真实落盘（on_gui 不可用/窗口收起时仍保证存档不丢）
                 flushPendingIO(60)
             end)
            maintenanceActive=false
            if not ok then cachedProgress=false;log('MAINTENANCE_FAILED',tostring(err),true)end
        end
        local heartbeat=P.get_method_by_param_types(main,'UpdateTime',{})
        if heartbeat and P.method_is_static(heartbeat) and P.method_param_count(heartbeat)==0 then
            local h=P.install_hook(heartbeat,{postfix=maintenance})
            assert(h,'独立维护钩子安装失败');hooks[#hooks+1]=h
            log('MAINTENANCE_READY','Main.UpdateTime()；2秒维护；伤害/射击/经验Hook只读内存配置、进度和角色键',true)
        else
            assert(updateMethod and P.method_is_instance(updateMethod),'缺少安全的维护入口')
            local h=P.install_hook(updateMethod,{postfix=function(player)
                if P.get_field_value(fields.playerIndex,player,'int32')==readLocalPlayer()then maintenance()end
            end})
            assert(h,'标量玩家维护入口安装失败');hooks[#hooks+1]=h
            log('MAINTENANCE_FALLBACK','Main.UpdateTime不可用，复用Player.Update(int)本地玩家总线；每2秒维护，不挂结构体Main.Update',true)
        end
        maintenanceActive=false
        log('SUPPRESSION_LIMITS','阶段压制不依赖DPS；特殊q默认1待实测；独立DOT、弹药组合门槛、爆竹派生贡献尚未覆盖；最低伤害不取消',true)
        status='已安装：实时读取物品 ID 与近战／远程／魔法／召唤类别，识别不依赖预设名单'
        log('READY',status..'；职业共享熟练度；有效成长属性按武器攻击方式分配，时期系数独立',true)
    end)
    if not ok then maintenanceActive=false;ready=false;status='初始化失败';log('INIT_FAILED',tostring(err),true) end
end
todo_list={'setup'}
function mod.cleanup()
    if gachaRuntime then gachaRuntime:save()end
    if store then store:save() end
    if multiplayerProbe then multiplayerProbe:remove() end
    if combat then combat:remove() end
    if projectileSources then projectileSources:remove() end
    alive=false;ready=false
    for _,hook in ipairs(hooks) do pcall(function() hook:remove() end) end
    hooks={};clearWorld()
    log('CLEANUP','已卸载；物品基础属性未改写，命中临时缩放已结束',true)
    if logDirty then saveLog()end
    flushPendingIO(0,true) -- 终刷：卸载前把队列里的全部写盘
end
