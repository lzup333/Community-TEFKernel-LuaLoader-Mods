local Projectiles=require('morph.projectiles')
local Ranged={}
Ranged.__index=Ranged
function Ranged.new(bridge)return setmetatable({b=bridge,shots=Projectiles.new(bridge)},Ranged)end
function Ranged:cast(player)
    local b=self.b;local f=b.form
    local x,y,aim=b:aim(player);local count=0
    for i=1,f.skill_count do
        local angle=aim+(i-(f.skill_count+1)/2)*.18
        if self.shots:spawn{kind=f.projectile,x=x,y=y,vx=math.cos(angle)*f.skill_speed,vy=math.sin(angle)*f.skill_speed,
            warning=0,life=90,damage=f.skill_damage,tileCollide=true} then count=count+1 end
    end
    b:trace_input('FORM_SKILL '..f.key..' count='..count)
    return count>0
end
function Ranged:animate()end
function Ranged:tick()self.shots:tick()end
function Ranged:cleanup()self.shots:cleanup()end
return Ranged
