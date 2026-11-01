-- Only projectiles created by this runtime are modified or removed.
-- PE 1.4.5.8 Projectile.key is a four-byte ProjectileKey, not an object reference.
local Projectiles={}
Projectiles.__index=Projectiles
function Projectiles.new(bridge)
    local p=bridge.p
    assert(type(p.get_field_raw)=='function','技能需要 ProjectileKey 原始字段接口')
    local fields={}
    for name in ('active type owner key friendly hostile damage timeLeft penetrate tileCollide noDropItem extraUpdates bonusCritChance'):gmatch('%S+') do
        fields[name]=assert(p.get_field(bridge.types.Projectile,name),'缺少 Projectile.'..name)
    end
    return setmetatable({b=bridge,p=p,fields=fields,shots={}},Projectiles)
end
function Projectiles:get(name,obj,kind)return self.p.get_field_value(self.fields[name],obj,kind)end
function Projectiles:set(name,obj,value,kind)self.p.set_field_value(self.fields[name],obj,value,kind)end
function Projectiles:same(entry)
    local a=self.b:get('Main','projectile',nil,'object')
    if a~=entry.array or entry.index>=self.p.array_length(a) then return nil end
    local shot=self.p.array_at(a,entry.index)
    if shot~=entry.object or not self:get('active',shot,'bool')
        or self:get('type',shot,'int32')~=entry.kind or self:get('owner',shot,'int32')~=entry.owner
        or self.p.get_field_raw(self.fields.key,shot,4)~=entry.key then return nil end
    return shot
end
function Projectiles:spawn(spec)
    if #self.shots>=12 then return false end
    local total=0;for _ in pairs(self.b.shot_owners or {})do total=total+1 end
    if total>=12 then return false end
    local b,p=self.b,self.p
    local damage=spec.damage
    if damage>0 and b.damage_for then damage=b.damage_for(b.form.key,damage,spec.kind) end
    local source=assert(p.construct(b.methods.source_ctor),'形态弹幕来源创建失败')
    local owner=b:main('myPlayer')
    -- Start harmless: native warning visuals must not damage an NPC.
    local index=p.invoke(b.methods.new_projectile,source,spec.x,spec.y,spec.vx or 0.0,spec.vy or 0.0,spec.kind,
        (spec.warning or 0)>0 and 0 or damage,3.0,owner,spec.angle or 0.0,spec.hue or 0.0,0.0,nil)
    local a=b:get('Main','projectile',nil,'object')
    if type(index)~='number' or index<0 or index>=1000 or not a or index>=p.array_length(a) then return false end
    local shot=p.array_at(a,index);if not shot then return false end
    local entry={array=a,index=index,object=shot,kind=spec.kind,owner=owner,age=0,
        warning=spec.warning or 0,life=spec.life,damage=damage,visual=spec.visual==true,form=b.form and b.form.key,store=self}
    local ok,err=pcall(function()
        entry.key=p.get_field_raw(self.fields.key,shot,4)
        assert(type(entry.key)=='string' and #entry.key==4,'无法读取 形态弹幕唯一标识')
        self:set('friendly',shot,not entry.visual,'bool');self:set('hostile',shot,false,'bool')
        self:set('damage',shot,entry.warning>0 and 0 or entry.damage,'int32');self:set('timeLeft',shot,spec.life,'int32')
        self:set('penetrate',shot,1,'int32');self:set('tileCollide',shot,spec.tileCollide==true,'bool')
        self:set('noDropItem',shot,true,'bool');self:set('extraUpdates',shot,0,'int32');self:set('bonusCritChance',shot,-1000,'int32')
    end)
    if not ok then pcall(self.set,self,'active',shot,false,'bool');error(err) end
    self.shots[#self.shots+1]=entry
    b.shot_owners=b.shot_owners or {};b.shot_owners[index]=entry
    return true,entry
end
function Projectiles:remove(entry)
    if not entry then return end
    local shot=self:same(entry)
    if shot then self:set('active',shot,false,'bool') end
    if self.b.shot_owners and self.b.shot_owners[entry.index]==entry then self.b.shot_owners[entry.index]=nil end
    for i=#self.shots,1,-1 do if self.shots[i]==entry then table.remove(self.shots,i);break end end
end
function Projectiles:tick()
    for i=#self.shots,1,-1 do
        local entry=self.shots[i];local shot=self:same(entry)
        if not shot then
            if self.b.shot_owners and self.b.shot_owners[entry.index]==entry then self.b.shot_owners[entry.index]=nil end
            table.remove(self.shots,i)
        else
            entry.age=entry.age+1
            if entry.age>=entry.life then self:remove(entry)
            else
                self:set('friendly',shot,not entry.visual,'bool');self:set('hostile',shot,false,'bool')
                self:set('damage',shot,entry.age>=entry.warning and entry.damage or 0,'int32')
                self:set('timeLeft',shot,math.min(self:get('timeLeft',shot,'int32'),entry.life-entry.age),'int32')
            end
        end
    end
end
function Projectiles:cleanup()
    local first_error
    for _,entry in ipairs(self.shots) do
        local ok,err=pcall(function()local shot=self:same(entry);if shot then self:set('active',shot,false,'bool') end end)
        if not ok then first_error=first_error or err end
    end
    for _,entry in ipairs(self.shots)do if self.b.shot_owners and self.b.shot_owners[entry.index]==entry then self.b.shot_owners[entry.index]=nil end end
    self.shots={}
    if first_error then error(first_error) end
end
return Projectiles
