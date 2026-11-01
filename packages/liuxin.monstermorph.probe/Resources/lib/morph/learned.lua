local Projectiles=require('morph.projectiles')
local Skills=require('morph.skills')
local Learned={}
Learned.__index=Learned
function Learned.new(bridge,ids)
    return setmetatable({b=bridge,ids={ids[1],ids[2]},cooldowns={0,0},shots=Projectiles.new(bridge)},Learned)
end
function Learned:cast(player,slot)
    local d=Skills.by_id[self.ids[slot]]
    if not d or self.cooldowns[slot]>0 then return false end
    local b=self.b;local x,y,aim=b:aim(player);local count=0
    for i=1,d.count do
        local angle=aim+(i-(d.count+1)/2)*.18
        if self.shots:spawn{kind=d.kind,x=x,y=y,vx=math.cos(angle)*d.speed,vy=math.sin(angle)*d.speed,
            warning=0,life=120,damage=d.damage,tileCollide=true} then count=count+1 end
    end
    if count>0 then self.cooldowns[slot]=b:cd(d.cooldown) end
    return count>0
end
function Learned:tick()
    for i=1,2 do self.cooldowns[i]=math.max(0,self.cooldowns[i]-1) end
    self.shots:tick()
end
function Learned:cleanup()self.shots:cleanup();self.cooldowns={0,0}end
return Learned
