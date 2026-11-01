local Flight={}
function Flight.apply(b,player,reset)
    -- ResetEffects has just produced this frame's vanilla baseline.
    if reset or not b.flight_scope then
        b.flight_scope={player=player,gravity=b:get('Player','gravity',player,'float'),
            noFall=b.trait_scope and b.trait_scope.player==player and b.trait_scope.noFall or b:get('Player','noFallDmg',player,'bool')}
    end
    if b.trait_scope and b.trait_scope.player==player then b.flight_scope.noFall=b.trait_scope.noFall end
    b:set('Player','gravity',player,0,'float')
    b:set('Player','noFallDmg',player,true,'bool')
end
function Flight.restore(b)
    local s=b.flight_scope;b.flight_scope=nil
    if s and b:local_player()==s.player then
        b:set('Player','gravity',s.player,s.gravity,'float')
        b:set('Player','noFallDmg',s.player,s.noFall,'bool')
    end
end
function Flight.move(b,player)
    Flight.apply(b,player)
    local function down(name)return b:get('Player',name,player,'bool')==true end
    local x=(down('controlRight') and 1 or 0)-(down('controlLeft') and 1 or 0)
    local y=(down('controlDown') and 1 or 0)-((down('controlUp') or b:pressed(player,'jump','controlJump')) and 1 or 0)
    local length=math.sqrt(x*x+y*y)
    local speed=b.form and b.form.fly_speed or 7
    if b.stats_for then speed=speed*b.stats_for(b.form.key).speed end
    if length>0 then x,y=x*speed/length,y*speed/length end
    if b.form.fly_accel then
        local vx,vy=b:vec('velocity',player)
        local dx,dy=x-vx,y-vy;local delta=math.sqrt(dx*dx+dy*dy)
        local step=b.form.fly_accel
        if delta>step then x,y=vx+dx*step/delta,vy+dy*step/delta end
        local magnitude=math.sqrt(x*x+y*y)
        if magnitude>speed then x,y=x*speed/magnitude,y*speed/magnitude end
    end
    local boss=b.boss_runtime
    if boss and boss.dash_ticks>0 then x,y=boss.dash_vx,boss.dash_vy
    elseif b.attack_ticks>0 and b.rush_vx then x,y=b.rush_vx,b.rush_vy end
    b:set_vec('velocity',player,x,y)
    if x~=0 then b:set('Entity','direction',player,x<0 and -1 or 1,'int32') end
end
return Flight
