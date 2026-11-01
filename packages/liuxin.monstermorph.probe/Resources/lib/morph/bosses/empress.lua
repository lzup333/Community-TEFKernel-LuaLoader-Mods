local Projectiles=require('morph.projectiles')
local Empress={}
Empress.__index=Empress
function Empress.new(bridge)
    local fields={}
    for name in ('boss alpha hide rotation spriteDirection ai localAI'):gmatch('%S+') do
        fields[name]=assert(bridge.p.get_field(bridge.types.NPC,name),'缺少 NPC.'..name)
    end
    assert(type(bridge.p.array_set)=='function','光之女王需要动画数组写入接口')
    return setmetatable({b=bridge,p=bridge.p,fields=fields,projectiles=Projectiles.new(bridge),cooldown=0,ticks=0,dash_ticks=0,dash_cooldown=0},Empress)
end
function Empress:set(name,npc,value,kind)self.p.set_field_value(self.fields[name],npc,value,kind)end
function Empress:array(npc,name,index,value)
    local a=self.p.get_field_value(self.fields[name],npc,'object')
    assert(a and self.p.array_length(a)>index,'光之女王动画数组缺失')
    assert(self.p.array_set(a,index,value,'float'),'光之女王动画写入失败')
end
function Empress:configure(npc)
    self:set('boss',npc,false,'bool');self:set('alpha',npc,0,'int32');self:set('hide',npc,false,'bool')
    self:set('rotation',npc,0.0,'float')
    -- Idle pose only. Never execute AI_120_HallowBoss or its phase/death logic.
    self:array(npc,'ai',0,1.0)
    for i=1,3 do self:array(npc,'ai',i,0.0) end
    self:array(npc,'localAI',0,0.0)
end
function Empress:animate(npc,player)
    self.ticks=self.ticks+1
    -- DrawNPCDirect_HallowBoss reads localAI[0] for its 11-frame wing cycle.
    self:array(npc,'localAI',0,self.ticks%440)
    if player then self:set('spriteDirection',npc,self.b:get('Entity','direction',player,'int32'),'int32') end
end
function Empress:aim(player)
    local b,p=self.b,self.p
    local x,y=b:vec('position',player)
    x,y=x+b:get('Entity','width',player,'int32')/2,y+b:get('Entity','height',player,'int32')/2
    local tx,ty=x+b:get('Entity','direction',player,'int32')*600,y
    local a=b:get('Main','npc',nil,'object');local distance=800*800
    if a then for i=0,math.min(199,p.array_length(a)-1) do
        if i~=b.proxy_index then
            local n=p.array_at(a,i)
            if n and b:get('NPC','active',n,'bool') and not b:get('NPC','friendly',n,'bool')
                and not b:get('NPC','dontTakeDamage',n,'bool') and b:get('NPC','life',n,'int32')>0 then
                local nx,ny=b:vec('position',n)
                nx,ny=nx+b:get('Entity','width',n,'int32')/2,ny+b:get('Entity','height',n,'int32')/2
                local d=(nx-x)^2+(ny-y)^2
                if d<distance then tx,ty,distance=nx,ny,d end
            end
        end
    end end
    return x,y,tx,ty
end
function Empress:cast(player)
    if self.cooldown>0 then return false end
    local x,y,tx,ty=self:aim(player);local count=0
    local dir=self.b:get('Entity','direction',player,'int32')
    for i=-1,1 do
        local sx,sy=x-dir*72,y+i*48
        if self.projectiles:spawn{kind=919,x=sx,y=sy,angle=math.atan(ty-sy,tx-sx),hue=(i+1)/3,
            warning=60,life=120,damage=80} then count=count+1 end
    end
    self.cooldown=count>0 and 150 or 15
    self.b:trace_input('EMPRESS_LANCE count='..count..' target='..math.floor(tx)..','..math.floor(ty))
    return count>0
end
function Empress:dash(player)
    if self.dash_cooldown>0 then return false end
    local b=self.b
    local function down(name)return b:get('Player',name,player,'bool')==true end
    local x=(down('controlRight') and 1 or 0)-(down('controlLeft') and 1 or 0)
    local y=(down('controlDown') and 1 or 0)-((down('controlUp') or b:pressed(player,'jump','controlJump')) and 1 or 0)
    local length=math.sqrt(x*x+y*y)
    if length==0 then x,y,length=b:get('Entity','direction',player,'int32'),0,1 end
    self.dash_vx,self.dash_vy=x*22/length,y*22/length
    self.dash_ticks,self.dash_cooldown=12,120
    b:set_vec('velocity',player,self.dash_vx,self.dash_vy)
    b:trace_input('EMPRESS_DASH')
    return true
end
function Empress:tick()
    self.cooldown=math.max(0,self.cooldown-1)
    self.dash_cooldown=math.max(0,self.dash_cooldown-1)
    self.dash_ticks=math.max(0,self.dash_ticks-1)
    self.projectiles:tick()
end
function Empress:cleanup()
    if self.dash_ticks>0 then
        local player=self.b:local_player()
        if player then
            local vx,vy=self.b:vec('velocity',player)
            local speed=math.sqrt(vx*vx+vy*vy);local limit=self.b.form.fly_speed or 10
            if speed>limit then self.b:set_vec('velocity',player,vx*limit/speed,vy*limit/speed) end
        end
    end
    self.dash_ticks,self.dash_cooldown=0,0
    self.dash_vx,self.dash_vy=nil,nil
    self.projectiles:cleanup();self.cooldown=0;self.ticks=0
end
return Empress
