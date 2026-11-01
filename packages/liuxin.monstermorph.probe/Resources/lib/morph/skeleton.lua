local Projectiles=require('morph.projectiles')
local Melee=require('morph.melee')
local Skeleton={}
Skeleton.__index=Skeleton
function Skeleton.new(bridge)
    return setmetatable({b=bridge,shots=Projectiles.new(bridge),
        rotation=assert(bridge.p.get_field(bridge.types.NPC,'rotation'),'缺少 NPC.rotation')},Skeleton)
end
function Skeleton:throw(player)
    local b=self.b;local x,y,angle=b:aim(player)
    local ok=self.shots:spawn{kind=21,x=x,y=y,vx=math.cos(angle)*8.5,vy=math.sin(angle)*8.5,
        warning=0,life=120,damage=26,tileCollide=true}
    if ok then b:trace_input('BONE_THROW') end
    return ok
end
function Skeleton:tick()self.shots:tick()end
function Skeleton:animate(npc,player)
    local b=self.b;local remaining=b.attack_ticks
    local phase=Melee.phase(b.form,remaining)
    local lean=phase=='windup' and -.12 or (phase=='active' and .22 or 0)
    local dir=b:get('Entity','direction',player,'int32')
    b.p.set_field_value(self.rotation,npc,lean*dir,'float')
    if phase=='idle' then self.shots:remove(self.swing);self.swing=nil;return end
    if self.swing and not self.shots:same(self.swing) then self.swing=nil end
    if not self.swing then
        local x,y=b:vec('position',player)
        local ok,entry=self.shots:spawn{kind=21,x=x,y=y,warning=0,life=b.form.duration+2,damage=0,visual=true}
        if ok then self.swing=entry end
    end
    local shot=self.swing and self.shots:same(self.swing)
    if shot then
        local x,y=b:vec('position',player);local angle=Melee.angle(b.form,remaining)
        local w,h=b:get('Entity','width',player,'int32'),b:get('Entity','height',player,'int32')
        local sw,sh=b:get('Entity','width',shot,'int32'),b:get('Entity','height',shot,'int32')
        b:set_vec('position',shot,x+w/2+dir*(5+math.cos(angle)*28)-sw/2,y+h*.35+math.sin(angle)*28-sh/2)
        b:set_vec('velocity',shot,0,0)
    end
end
function Skeleton:cleanup()
    self.swing=nil;self.shots:cleanup()
end
return Skeleton
