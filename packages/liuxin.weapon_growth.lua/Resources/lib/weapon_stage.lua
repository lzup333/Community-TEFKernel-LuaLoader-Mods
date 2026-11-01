-- 明确来源优先，其次配方门槛；未知来源不按稀有度强行分期。
local A=require('progression_anchors')
local Reader=require('weapon_reader')
local SourceTags=require('weapon_sources')
local Catalog=require('weapon_catalog')
local RecipeOrigins=require('weapon_recipe_origins')
local M={}
local function integer(n) return type(n)=='number' and n==n and n%1==0 end
function M.solve(recipes,anchors,tiles,souls)
    local stages={}
    for id,stage in pairs(anchors) do stages[id]=stage end
    -- 种子不被循环转换配方反向降低。只传播所有材料都已知的配方。
    for pass=1,64 do
        local changed=false
        for _,r in ipairs(recipes) do
            local candidate=tiles[r.tile]
            local allKnown=candidate~=nil and #r.inputs>0
            local has={}
            for _,id in ipairs(r.inputs) do
                has[id]=true
                local input=stages[id]
                if input==nil then allKnown=false else candidate=math.max(candidate or 0,input) end
            end
            if souls and has[souls[1]] and has[souls[2]] and has[souls[3]] then candidate=math.max(candidate or 0,6) end
            -- 替代组尚未解析：只有全部材料为初期材料的组合可直接确定。
            if r.groups and candidate~=0 then allKnown=false end
            if r.special then allKnown=false end
            if allKnown and not anchors[r.id] and (not stages[r.id] or candidate<stages[r.id]) then
                stages[r.id]=candidate;changed=true
            end
        end
        if not changed then break end
    end
    return stages
end
function M.dps_averages(stages,samples)
    local values={}
    for id,sample in pairs(samples) do
        local stage=stages[id]
        if stage~=nil and type(sample.dps)=='number' and sample.dps>0 and sample.dps<math.huge and Reader.names[sample.category] then
            values[stage]=values[stage] or {}
            local keys={sample.category}
            if sample.referenceKey and sample.referenceKey~=sample.category then keys[#keys+1]=sample.referenceKey end
            for _,key in ipairs(keys) do
                local bucket=values[stage][key] or {};values[stage][key]=bucket
                bucket.sum=(bucket.sum or 0)+sample.dps;bucket.count=(bucket.count or 0)+1
            end
        end
    end
    local averages={}
    for stage,classes in pairs(values) do
        averages[stage]={}
        for category,bucket in pairs(classes) do
            averages[stage][category]={average=bucket.sum/bucket.count,count=bucket.count}
        end
    end
    return averages
end
function M.open(P,log,exclusions)
    local ok,value=pcall(function()
        local main=P.get_type('Terraria','Main')
        local recipe=P.get_type('Terraria','Recipe')
        local item=P.get_type('Terraria','Item')
        local function field(t,name) local f=P.get_field(t,name);assert(f,'缺少配方字段 '..name);return f end
        return {array=field(main,'recipe'),count=field(recipe,'numRecipes'),output=field(recipe,'createItem'),
            inputs=field(recipe,'requiredItem'),tile=field(recipe,'requiredTile'),groups=field(recipe,'acceptedGroups'),
            special=field(recipe,'needMechdusa'),id=field(item,'type')}
    end)
    local self={fields=ok and value or nil,stages={},sourceTags={},samples={},dpsAverages={},count=nil,lastTry=-10}
    if not ok then log('ORIGIN_UNAVAILABLE',tostring(value)..'；未知时期不做时期调整',true) end
    local anchors={};for id,origin in pairs(A.items) do anchors[id]=origin end
    for id,origin in pairs(RecipeOrigins) do anchors[id]=origin end
    local registered=0
    for name,tag in pairs(SourceTags) do
        local id=tag.id
        if integer(id) and id>0 and integer(tag.stage) and tag.stage>=0 and tag.stage<=10 then
            assert(not self.sourceTags[id],'重复来源物品ID '..id)
            anchors[id]=tag.stage;self.sourceTags[id]=tag;registered=registered+1
        else
            log('SOURCE_TAG_INVALID','name='..name..'；标记无效，跳过',true)
        end
    end
    log('SOURCE_TAGS_READY','registered='..registered..'；使用核对后的原版ID，避开Android常量字段指针',true)
    local sampleFields={}
    local statsOK,statsError=pcall(function()
        local item=P.get_type('Terraria','Item')
        for _,name in ipairs({'damage','prefix','ammo','rare','useAnimation','useTime','pick','axe','hammer','melee','ranged','magic','summon'}) do
            sampleFields[name]=P.get_field(item,name);assert(sampleFields[name],'缺少样本字段 '..name)
        end
    end)
    if not statsOK then log('DPS_UNAVAILABLE',tostring(statsError)..'；DPS平衡暂停，来源识别继续',true) end
    -- 离线核对样本补齐掉落武器；不构造原生 Item，避免手机桥接崩溃。
    local verifiedSamples={}
    for id,s in pairs(Catalog) do
        verifiedSamples[id]={damage=s.damage,useTime=s.useTime,dps=s.damage*60/s.useTime,category=s.category,referenceKey=s.referenceKey}
    end
    for id,tag in pairs(self.sourceTags) do
        local s=tag.sample
        if id==3098 then s=nil end -- ButchersChainsaw 是工具，不纳入战斗武器均值
        if s and s.damage>0 and s.useTime>0 and Reader.names[s.category] then
            local base=Catalog[id] or s
            verifiedSamples[id]={damage=base.damage,useTime=base.useTime,dps=base.damage*60/base.useTime,category=base.category,referenceKey=base.referenceKey or base.category}
        end
    end
    self.samples=verifiedSamples
    self.dpsAverages=M.dps_averages(anchors,verifiedSamples)
    local referenceNotices={}
    function self:reference(category,current,exactOnly)
        if not integer(current) or current<0 or current>10 then return nil end
        local last=exactOnly and current or 0
        for sampleStage=current,last,-1 do
            local bucket=self.dpsAverages[sampleStage] and self.dpsAverages[sampleStage][category]
            -- 四柱每职业只有两件主武器，终局召唤也只有两件；完整核对的两件可作均值。
            -- 已核验来源的狭窄时期也可能只有一件（例如地牢时期鞭子）。
            -- 先采用该时期现有均值；只有完全没有武器才回退更早时期。
            local minimum=1
            if bucket and bucket.count>=minimum then
                local key=category..':'..current..':'..tostring(exactOnly)
                if not referenceNotices[key] then
                    referenceNotices[key]=true
                    log('PERIOD_DPS_REFERENCE','class='..category..' requested='..current..' sampleStage='..sampleStage
                        ..' mean='..string.format('%.2f',bucket.average)..' samples='..bucket.count
                        ..'；同原生时期算术平均，未混入全部早期武器',true)
                end
                return bucket.average,bucket.count,sampleStage,'period_average'
            end
        end
        return nil
    end
    function self:baseDamage(id) return self.samples[id] and self.samples[id].damage end
    function self:baseDps(id) return self.samples[id] and self.samples[id].dps end
    function self:origin(id,now,rare)
        if not self.fields then
            local tag=self.sourceTags[id]
            return tag and tag.stage or RecipeOrigins[id],tag and 'explicit' or (RecipeOrigins[id]~=nil and 'verified_recipe' or 'unknown')
        end
        if now-self.lastTry<10 then
            local tag=self.sourceTags[id]
            if tag then return tag.stage,'explicit' end
            local exact=self.stages[id] or RecipeOrigins[id]
            if exact~=nil then return exact,'recipe' end
            return nil,'unknown'
        end
        self.lastTry=now
        local loaded,result=pcall(function()
            local f=self.fields
            local count=P.get_field_value(f.count,nil,'int32')
            assert(integer(count) and count>0 and count<=10000,'配方数量不可用')
            if self.count==count then return nil end
            local array=P.get_field_value(f.array,nil,'object')
            assert(array and P.array_length(array)>=count,'配方数组不可用')
            log('DPS_SCAN_BEGIN','recipes='..count..' source=recipe+verified；原生完整目录桥接已停用',true)
            local rules,samples,seen={},{},{}
            for id,s in pairs(verifiedSamples) do samples[id]=s end
            local function sample(object,id)
                if not statsOK or seen[id] then return end
                local valid,entry=pcall(function()
                    local damage=P.get_field_value(sampleFields.damage,object,'int32')
                    if not integer(damage) or damage<=0 then return nil end
                    if exclusions and exclusions:item_bomb(id)==true then return nil end
                    if P.get_field_value(sampleFields.prefix,object,'uint8')~=0 then return nil end
                    -- 弹药和无法主动使用的材料不作为武器样本。
                    local ammo=P.get_field_value(sampleFields.ammo,object,'int32')
                    local animation=P.get_field_value(sampleFields.useAnimation,object,'int32')
                    if ammo~=0 or not integer(animation) or animation<=0 then return nil end
                    local useTime=P.get_field_value(sampleFields.useTime,object,'int32')
                    if not integer(useTime) or useTime<=0 then useTime=animation end
                    if not integer(useTime) or useTime<=0 then return nil end
                    local snapshot={id=id,damage=damage,ammo=0,bomb=false}
                    for _,name in ipairs({'pick','axe','hammer'}) do snapshot[name]=P.get_field_value(sampleFields[name],object,'int32') end
                    for _,name in ipairs({'melee','ranged','magic','summon'}) do snapshot[name]=P.get_field_value(sampleFields[name],object,'bool') end
                    local classified=Reader.identify(snapshot)
                    local rare=P.get_field_value(sampleFields.rare,object,'int32')
                    return classified and {damage=damage,dps=damage*60/useTime,useTime=useTime,category=classified.category,rare=rare,referenceKey=Catalog[id] and Catalog[id].referenceKey or classified.category} or nil
                end)
                if valid and entry then samples[id]=entry;seen[id]=true end
            end
            for index=0,count-1 do
                local r=P.array_at(array,index,'object');assert(r,'配方为空')
                local output=P.get_field_value(f.output,r,'object');assert(output,'配方产物为空')
                local id=P.get_field_value(f.id,output,'int32')
                local tile=P.get_field_value(f.tile,r,'int32')
                local inputs=P.get_field_value(f.inputs,r,'object');assert(inputs,'材料数组为空')
                local rule={id=id,tile=tile,inputs={}}
                assert(integer(id) and id>0 and integer(tile),'配方字段异常')
                sample(output,id)
                local length=P.array_length(inputs);assert(integer(length) and length<=100,'材料数组异常')
                for i=0,length-1 do
                    local input=P.array_at(inputs,i,'object')
                    local typeId=input and P.get_field_value(f.id,input,'int32') or 0
                    assert(integer(typeId) and typeId>=0,'材料 ID 异常')
                    if typeId>0 then rule.inputs[#rule.inputs+1]=typeId;sample(input,typeId) end
                end
                local groups=P.get_field_value(f.groups,r,'object')
                if groups then
                    local size=P.array_length(groups);assert(integer(size) and size<=100,'替代组数组异常')
                    for i=0,size-1 do
                        local group=P.array_at(groups,i,'int32')
                        assert(integer(group),'替代组异常')
                        if group>=0 then rule.groups=true end
                    end
                end
                local special=P.get_field_value(f.special,r,'bool')
                assert(type(special)=='boolean','特殊条件字段异常');rule.special=special
                rules[#rules+1]=rule
            end
            local stages=M.solve(rules,anchors,A.tiles,A.mechanicalSouls)
            -- 完整目录桥接曾触发手机原生崩溃，仅使用安全配方/材料快照。
            log('DPS_RECIPES_READY','recipes='..count..'；来源阶段与DPS样本来自配方/材料快照及同版核对样本',true)
            return {count=count,stages=stages,samples=samples,averages=M.dps_averages(stages,samples)}
        end)
        if loaded and result then
            self.count=result.count;self.stages=result.stages
            self.samples=result.samples;self.dpsAverages=result.averages;referenceNotices={}
            local known=0;for _ in pairs(self.stages) do known=known+1 end
            log('ORIGIN_READY','recipes='..result.count..' knownItems='..known..'；未知来源不强制分期',true)
            local sampleCount=0
            for id in pairs(self.samples) do if self.stages[id]~=nil then sampleCount=sampleCount+1 end end
            log('DPS_REFERENCE_READY','按类别/阶段/ID去重武器样本='..sampleCount..'；基准为武器估算DPS算术平均（伤害×60/使用时间）',true)
            for sampleStage=0,10 do
                local parts={}
                for _,category in ipairs({'melee','ranged','magic','summon_whip','summon_minion','summon_sentry'}) do
                    local bucket=self.dpsAverages[sampleStage] and self.dpsAverages[sampleStage][category]
                    if bucket then parts[#parts+1]=category..'='..string.format('%.1f',bucket.average)..'/'..bucket.count end
                end
                if #parts>0 then log('DPS_STAGE','stage='..sampleStage..' 平均估算DPS/样本 '..table.concat(parts,' '),true) end
            end
            log('DPS_CATALOG_SAFE','使用配方/材料及同版核对样本计算DPS；明确来源/配方门槛参与分期；稀有度不参与时期系数',true)
        elseif not loaded then
            self.count=nil;self.stages={}
            self.samples=verifiedSamples;self.dpsAverages=M.dps_averages(anchors,verifiedSamples)
            log('ORIGIN_UNAVAILABLE',tostring(result)..'；稍后重试，未知时期暂停时期调整')
        end
        local tag=self.sourceTags[id]
        if tag then return tag.stage,'explicit' end
        local exact=self.stages[id] or RecipeOrigins[id]
        if exact~=nil then return exact,'recipe' end
        return nil,'unknown'
    end
    return self
end
return M
