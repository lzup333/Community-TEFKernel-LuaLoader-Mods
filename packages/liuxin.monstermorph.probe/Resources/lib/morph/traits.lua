local T={}
function T.resize(b,player)
    local x,y=b:vec('position',player);local w,h=b:get('Entity','width',player,'int32'),b:get('Entity','height',player,'int32')
    if not b.body_scope then b.body_scope={player=player,width=w,height=h,breath=b:get('Player','breath',player,'int32')};b.last_clear={x=x,y=y}end
    local nw,nh=b.form.width,b.form.height
    if nw and nh then
        b:set_vec('position',player,x+(w-nw)/2,y+h-nh)
        b:set('Entity','width',player,nw,'int32');b:set('Entity','height',player,nh,'int32')
    end
end
function T.apply(b,player)
    local s={player=player,lava=b:get('Player','lavaImmune',player,'bool'),defense=b:get('Player','statDefense',player,'int32'),noFall=b:get('Player','noFallDmg',player,'bool'),buffs={}}
    -- ResetEffects has supplied fresh values; snapshots never contain our previous frame's flags.
    b.trait_scope=s
    b:set('Player','noFallDmg',player,true,'bool')
    b:set('Player','breath',player,b:get('Player','breathMax',player,'int32'),'int32')
    if b.form.lava_immune then b:set('Player','lavaImmune',player,true,'bool')end
    if b.stats_for then b:set('Player','statDefense',player,math.floor(b.stats_for(b.form.key).defense or 0),'int32')end
    local a=b:get('Player','buffImmune',player,'object');s.array=a
    if a then for _,id in ipairs(b.form.immunities or{})do
        if id<b.p.array_length(a)then s.buffs[id]=b.p.array_at(a,id,'bool');b.p.array_set(a,id,true,'bool')end
    end end
    if b.form.swim and b:get('Entity','wet',player,'bool')then b:set('Player','breath',player,b:get('Player','breathMax',player,'int32'),'int32')end
end
function T.move(b,player)
    b.surface_support=false
    if not b.form.buoyant then return end
    local x,y=b:vec('position',player);local w,h=b:get('Entity','width',player,'int32'),b:get('Entity','height',player,'int32')
    local tx,ty=math.floor((x+w/2)/16),math.floor((y+h-2)/16)
    local mx,my=b:get('Main','maxTilesX',nil,'int32'),b:get('Main','maxTilesY',nil,'int32')
    if tx<0 or ty<0 or tx>=mx or ty>=my then return end
    local function liquid(row)
        if row<0 or row>=my then return false end
        return b.p.invoke(b.methods.liquid,tx,row,0)==true or b.p.invoke(b.methods.liquid,tx,row,2)==true
            or(b.form.lava_immune and b.p.invoke(b.methods.liquid,tx,row,1)==true)
    end
    if not liquid(ty)then return end
    local top=ty;for _=1,12 do if not liquid(top-1)then break end;top=top-1 end
    local vx,vy=b:vec('velocity',player);local feet=y+h;local surface=top*16+6
    if vy< -2 then return end -- Keep an intentional jump intact.
    local delta=surface-feet
    b.surface_support=math.abs(delta)<12
    b:set_vec('velocity',player,vx,math.max(-4,math.min(2,delta*.18)))
end
function T.phase_collision(b,player)
    if b.phase_step==b.input_tick then return true end;b.phase_step=b.input_tick
    local x,y=b:vec('position',player);local vx,vy=b:vec('velocity',player)
    local w,h=b:get('Entity','width',player,'int32'),b:get('Entity','height',player,'int32')
    local mx,my=b:get('Main','maxTilesX',nil,'int32')*16,b:get('Main','maxTilesY',nil,'int32')*16
    b:set_vec('position',player,math.max(16,math.min(mx-w-16,x+vx)),math.max(16,math.min(my-h-16,y+vy)))
    return true
end
function T.animate(b,player)
    if b.body_scope then
        local x,y=b:vec('position',player);local w,h=b:get('Entity','width',player,'int32'),b:get('Entity','height',player,'int32')
        local human=b.body_scope
        local px,py=x+(w-human.width)/2,y+h-human.height
        if b:space_clear(px,py,human.width,human.height)then b.last_clear={x=px,y=py}end
    end
    if #(b.form.parts or{})==0 then return end
    if not b.body_proxies then
        b.body_proxies={};b.body_map={};b.trail={};local source=assert(b.p.construct(b.methods.source_ctor));local x,y=b:vec('position',player)
        for _,kind in ipairs(b.form.parts)do
            local index=b.p.invoke(b.methods.new,source,math.floor(x),math.floor(y),kind,0,0.0,0.0,0.0,0.0,255)
            local a=b:get('Main','npc',nil,'object')
            if type(index)~='number'or index<0 or index>=200 or not a or index>=b.p.array_length(a)then break end
            local n=b.p.array_at(a,index)
            for _,flag in ipairs({'friendly','dontTakeDamage','dontCountMe'})do b:set('NPC',flag,n,true,'bool')end
            b:set('NPC','aiStyle',n,-1,'int32');b:set('NPC','damage',n,0,'int32')
            local part={index=index,object=n,array=a,kind=kind};b.body_proxies[#b.body_proxies+1]=part;b.body_map[index]=part
        end
    end
    local x,y=b:vec('position',player);local previous=b.trail[1]
    if not previous or(x-previous.x)^2+(y-previous.y)^2>=16 then table.insert(b.trail,1,{x=x,y=y})end
    if #b.trail>240 then table.remove(b.trail)end
    local path=0;local point=1;local last={x=x,y=y}
    for i,part in ipairs(b.body_proxies)do
        local desired=i*16
        while point<#b.trail and path<desired do
            local a,c=b.trail[point],b.trail[point+1];path=path+math.sqrt((a.x-c.x)^2+(a.y-c.y)^2);point=point+1
        end
        local pos=b.trail[point]or last
        if path<desired then pos={x=pos.x-(desired-path)*b:get('Entity','direction',player,'int32'),y=pos.y}end
        local n=b.p.array_at(part.array,part.index)
        if b:is_appearance(n,part.index)then
            b:set_vec('position',n,pos.x,pos.y);b:set('NPC','timeLeft',n,750,'int32')
            b:set('NPC','rotation',n,math.atan(last.y-pos.y,last.x-pos.x)+math.pi/2,'float')
            b.p.invoke(b.methods.frame,n)
        end
        last=pos
    end
end
function T.restore(b)
    local s=b.trait_scope;b.trait_scope=nil
    if s and b:local_player()==s.player then
        b:set('Player','lavaImmune',s.player,s.lava,'bool');b:set('Player','statDefense',s.player,s.defense,'int32');b:set('Player','noFallDmg',s.player,s.noFall,'bool')
        if s.array==b:get('Player','buffImmune',s.player,'object')then for id,value in pairs(s.buffs)do b.p.array_set(s.array,id,value,'bool')end end
    end
    for _,part in ipairs(b.body_proxies or{})do
        local a=b:get('Main','npc',nil,'object')
        if a==part.array then local n=b.p.array_at(a,part.index);if b:is_appearance(n,part.index)then b:set('NPC','active',n,false,'bool')end end
    end
    b.body_proxies=nil;b.body_map=nil;b.trail=nil;b.phase_step=nil;b.surface_support=false
    local body=b.body_scope;b.body_scope=nil
    if body and b:local_player()==body.player then
        local x,y=b:vec('position',body.player);local w,h=b:get('Entity','width',body.player,'int32'),b:get('Entity','height',body.player,'int32')
        b:set_vec('position',body.player,x+(w-body.width)/2,y+h-body.height)
        b:set('Entity','width',body.player,body.width,'int32');b:set('Entity','height',body.player,body.height,'int32')
        if body.breath then b:set('Player','breath',body.player,math.min(body.breath,b:get('Player','breathMax',body.player,'int32')),'int32')end
    end
    if body then
        local p=b:local_player()
        if p then
            local x,y=b:vec('position',p);local w,h=b:get('Entity','width',p,'int32'),b:get('Entity','height',p,'int32')
            if not b:space_clear(x,y,w,h)then
                local sx,sy=b:find_space(p,w,h)
                if not sx and b.last_clear then sx,sy=b.last_clear.x,b.last_clear.y end
                if sx then b:set_vec('position',p,sx,sy);b:set_vec('velocity',p,0,0)end
            end
        end
    end
    b.last_clear=nil
end
return T
