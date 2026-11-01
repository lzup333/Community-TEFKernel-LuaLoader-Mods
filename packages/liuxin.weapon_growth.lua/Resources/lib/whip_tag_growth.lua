-- 单人模式下修改原版鞭子标记对象的整数伤害；不挂接 ref TagDamageChanges 结构体。
-- 保存原值，按最新独立系数重算；关闭、退世界和卸载均还原，绝不逐帧累乘。
local S=require('scaling')
local Catalog=require('weapon_catalog')
local M={}
function M.open(P,log)
    local ok,f=pcall(function()
        local item=P.get_type('Terraria.ID','ItemID')
        local sets=P.get_inner_type(item,'Sets')
        local tag=P.get_type('Terraria.GameContent.Items','WhipTagEffect')
        local array=P.get_field(sets,'UniqueTagEffects');local damage=P.get_field(tag,'TagDamage')
        assert(array and damage,'缺少鞭子标记字段')
        return {array=array,damage=damage}
    end)
    local self={fields=ok and f or nil,cache={}}
    if not ok then log('WHIP_TAG_UNAVAILABLE',tostring(f)..'；标记保持原版，直接命中成长继续',true) end
    function self:restore()
        if not self.fields then return end
        for _,v in pairs(self.cache) do
            pcall(function()
                if P.get_field_value(self.fields.damage,v.object,'int32')==v.applied then
                    P.set_field_value(self.fields.damage,v.object,v.base,'int32')
                end
            end)
        end
        self.cache={};self.revision=nil
    end
    function self:update(coefficient,revision)
        if not self.fields or (revision~=nil and revision==self.revision) then return end
        local ok,err=pcall(function()
            local array=P.get_field_value(self.fields.array,nil,'object')
            if not array then return end
            local length=P.array_length(array)
            for id,s in pairs(Catalog) do
                if s.referenceKey=='summon_whip' and id<length then
                    local object=P.array_at(array,id,'object')
                    if object then
                        local current=P.get_field_value(self.fields.damage,object,'int32')
                        if type(current)=='number' and current>0 and current<=100000 then
                            local v=self.cache[id]
                            if not v then v={object=object,base=current,applied=current};self.cache[id]=v end
                            -- 外部修改时保留外部新值为基值，退出时不覆盖外部后续修改。
                            if current~=v.applied then v.base=current end
                            local multiplier=coefficient(id)
                            if type(multiplier)=='number' and multiplier>0 then
                                local changed=S.damage(v.base,multiplier)
                                if changed~=current then assert(P.set_field_value(self.fields.damage,object,changed,'int32')~=false,'标记伤害写入失败') end
                                v.applied=changed
                            end
                        end
                    end
                end
            end
        end)
        if ok then self.revision=revision end
        if not ok then self:restore();self.fields=nil;log('WHIP_TAG_UNAVAILABLE',tostring(err)..'；已还原标记字段',true) end
    end
    return self
end
return M
