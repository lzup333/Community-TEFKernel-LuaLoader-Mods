local W={}
local Catalog=require('morph.catalog')
function W.bind(b)
    local p=b.p
    for key,spec in pairs({tile_type={'WorldGen','TileType',2},liquid={'WorldGen','AnyLiquidAt',3},
        kill_tile={'WorldGen','KillTile',5},check_spawn={'Player','CheckSpawn',2},add_buff={'Player','AddBuff',3}})do
        if key~='liquid'then b.methods[key]=assert(p.get_method(b.types[spec[1]],spec[2],spec[3]),spec[2])end
    end
    local npc_id=assert(p.get_type('Terraria.ID','NPCID'),'NPCID')
    local sets=assert(p.get_inner_type(npc_id,'Sets'),'NPCID.Sets')
    b.boss_head_field=assert(p.get_field(sets,'BossHeadTextures'),'NPCID.Sets.BossHeadTextures')
    local int=p.get_basic_type('int32')
    local boolean=p.get_basic_type('bool')
    b.methods.ground=assert(p.get_method_by_param_types(b.types.WorldGen,'SolidOrSlopedTile',{int,int,boolean}),'SolidOrSlopedTile(int,int,bool)')
    b.methods.liquid=assert(p.get_method_by_param_types(b.types.WorldGen,'AnyLiquidAt',{int,int,int}),'AnyLiquidAt(int,int,int)')
    b.methods.can_hit=assert(p.get_method_by_param_types(b.types.Collision,'CanHit',{b.types.Entity,b.types.Entity}),'CanHit(Entity,Entity)')
end
function W:at_base(player)
    if not self:single_world() or not player then return false end
    local sx,sy=self:get('Player','SpawnX',player,'int32'),self:get('Player','SpawnY',player,'int32')
    if sx<0 or sy<0 or self.p.invoke(self.methods.check_spawn,sx,sy)~=true then sx,sy=self:main('spawnTileX'),self:main('spawnTileY')end
    local x,y=self:vec('position',player);x=x+self:get('Entity','width',player,'int32')/2;y=y+self:get('Entity','height',player,'int32')
    return(x-sx*16)^2+(y-sy*16)^2<=(15*16)^2
end
function W:native_snapshot(n)
    local function get(k,t)return self:get('NPC',k,n,t or'int32')end
    local kind=get('type');local id=get('netID');if id==0 then id=kind end
    local name
    for _,form in ipairs(Catalog)do if form.npc==kind then name=form.name;break end end
    local immune={};local a=get('buffImmune','object')
    if a then for i=0,math.min(499,self.p.array_length(a)-1)do if self.p.array_at(a,i,'bool')then immune[#immune+1]=i end end end
    return{npc=kind,netid=id,name=name or('怪物 #'..kind),life=math.max(1,get('lifeMax')),hp=math.max(0,get('life')),damage=math.max(1,get('damage')),defense=math.max(0,get('defense')),
        ai=get('aiStyle'),width=self:get('Entity','width',n,'int32'),height=self:get('Entity','height',n,'int32'),
        nogravity=get('noGravity','bool'),phase=get('noTileCollide','bool'),lava=get('lavaImmune','bool'),immunities=immune,parts={},native=true}
end
function W:is_boss(n)
    if self:get('NPC','boss',n,'bool')then return true end
    local kind=self:get('NPC','type',n,'int32')
    local heads=self.boss_head_field and self.p.get_field_value(self.boss_head_field,nil,'object')
    if heads and kind>=0 and kind<self.p.array_length(heads)then
        local icon=self.p.array_at(heads,kind,'int32');return type(icon)=='number'and icon>=0
    end
    return false
end
function W:scan_capture(player)
    local a=self:get('Main','npc',nil,'object');if not a then return nil,nil,'empty'end
    local x,y=self:vec('position',player);x=x+self:get('Entity','width',player,'int32')/2;y=y+self:get('Entity','height',player,'int32')/2
    local best,distance,high,boss,far,released=nil,160*160,false,false,false,false
    for i=0,math.min(199,self.p.array_length(a)-1)do
        local n=self.p.array_at(a,i)
        if n and not self:is_appearance(n,i)and self:get('NPC','active',n,'bool')and not self:get('NPC','friendly',n,'bool')and not self:get('NPC','townNPC',n,'bool')then
            local nx,ny=self:vec('position',n);nx=nx+self:get('Entity','width',n,'int32')/2;ny=ny+self:get('Entity','height',n,'int32')/2
            local d=(nx-x)^2+(ny-y)^2
            if d<=480*480 then
                local root=n;local root_index=i;local real=self:get('NPC','realLife',n,'int32')
                if real>=0 and real<200 and real<self.p.array_length(a)then root=self.p.array_at(a,real);root_index=real end
                if root and self:get('NPC','active',root,'bool')then
                    if d<=160*160 then
                        if self:is_boss(root)then boss=true
                        elseif not self:get('NPC','dontTakeDamage',root,'bool')then
                            local held=self.release_held and self.release_held[root_index]
                            local life,max=self:get('NPC','life',root,'int32'),self:get('NPC','lifeMax',root,'int32')
                            if held and held.object==root and held.until_tick>(self.world_tick or 0)then released=true
                            elseif life>0 and max>0 and life<=max*.25 then
                                if d<=distance then best={array=a,index=root_index,object=root,kind=self:get('NPC','type',root,'int32')};distance=d end
                            elseif life>0 then high=true end
                        end
                    else far=true end
                end
            end
        end
    end
    if not best then return nil,nil,released and'released'or(high and'health'or(boss and'boss'or(far and'distance'or'empty')))end
    local snapshot=self:native_snapshot(best.object);best.parts={}
    for i=0,math.min(199,self.p.array_length(a)-1)do
        if i~=best.index then
            local n=self.p.array_at(a,i)
            if n and self:get('NPC','active',n,'bool')and self:get('NPC','realLife',n,'int32')==best.index and not self:get('NPC','boss',n,'bool')then
                best.parts[#best.parts+1]={object=n,index=i,kind=self:get('NPC','type',n,'int32')}
                if #snapshot.parts<32 then snapshot.parts[#snapshot.parts+1]=self:get('NPC','type',n,'int32')end
            end
        end
    end
    if snapshot.ai==6 and #best.parts>0 then
        local remaining={};for _,part in ipairs(best.parts)do remaining[part.index]=part end
        local ordered={};local current=best.object
        for _=1,#best.parts do
            local ai=self:get('NPC','ai',current,'object')
            if not ai or self.p.array_length(ai)<1 then break end
            local next_index=self.p.array_at(ai,0,'float');local part=remaining[next_index]
            if not part then break end
            ordered[#ordered+1]=part;remaining[part.index]=nil;current=part.object
        end
        for _,part in ipairs(best.parts)do if remaining[part.index]then ordered[#ordered+1]=part end end
        best.parts=ordered;snapshot.parts={}
        for i=1,math.min(32,#ordered)do snapshot.parts[i]=ordered[i].kind end
    end
    return snapshot,best
end
function W:consume_capture(token)
    local a=self:get('Main','npc',nil,'object')
    if a~=token.array or self.p.array_at(a,token.index)~=token.object or not self:get('NPC','active',token.object,'bool')or self:get('NPC','type',token.object,'int32')~=token.kind then return false end
    self:set('NPC','active',token.object,false,'bool')
    for _,part in ipairs(token.parts)do
        local n=self.p.array_at(a,part.index)
        if n==part.object and self:get('NPC','active',n,'bool')and self:get('NPC','type',n,'int32')==part.kind and self:get('NPC','realLife',n,'int32')==token.index then self:set('NPC','active',n,false,'bool')end
    end
    return true
end
function W:space_clear(x,y,w,h)
    local mx,my=self:get('Main','maxTilesX',nil,'int32'),self:get('Main','maxTilesY',nil,'int32')
    if x<32 or y<32 or x+w>mx*16-32 or y+h>my*16-32 then return false end
    for tx=math.floor(x/16),math.floor((x+w-1)/16)do for ty=math.floor(y/16),math.floor((y+h-1)/16)do
        if self.space_budget then self.space_budget=self.space_budget-1;if self.space_budget<0 then return false end end
        if self.space_trace then self.space_trace('space_collision_begin tile='..tx..','..ty)end
        -- Reuse the existing grounded() primitive path; false excludes platforms.
        -- The device trace stops inside WorldGen.SolidTile, before its return.
        local solid=self.p.invoke(self.methods.ground,tx,ty,false)==true
        if self.space_trace then self.space_trace('space_collision_ready result='..tostring(solid))end
        if solid then return false end
        if self.space_trace then self.space_trace('lava_begin')end
        local lava=self.p.invoke(self.methods.liquid,tx,ty,1)==true
        if self.space_trace then self.space_trace('lava_ready result='..tostring(lava))end
        if lava then return false end
    end end;return true
end
function W:find_space(player,w,h)
    self.space_budget=8192
    local x,y=self:vec('position',player)
    for radius=0,12 do
        for dx=-radius,radius do for dy=-radius,radius do if radius==0 or math.abs(dx)==radius or math.abs(dy)==radius then
            local px,py=x+dx*16,y+dy*16
            if self:space_clear(px,py,w,h)then self.space_budget=nil;return px,py end
            if self.space_budget<0 then self.space_budget=nil;return nil end
        end end end
    end
    self.space_budget=nil
end
function W:release_pet(player,pet)
    local counts=self:get('Main','npcFrameCount',nil,'object')
    if not counts or type(pet.npc)~='number'or type(pet.netid)~='number'or pet.npc<1 or pet.npc>=self.p.array_length(counts)or pet.netid< -66 or pet.netid>=self.p.array_length(counts)then return nil end
    local x,y=self:find_space(player,pet.width,pet.height);if not x then return nil end
    local source=assert(self.p.construct(self.methods.source_ctor))
    local index=self.p.invoke(self.methods.new,source,math.floor(x+pet.width/2),math.floor(y+pet.height),pet.netid,0,0.0,0.0,0.0,0.0,255)
    local a=self:get('Main','npc',nil,'object')
    if type(index)~='number'or index<0 or index>=200 or not a or index>=self.p.array_length(a)then return nil end
    local n=self.p.array_at(a,index);if not n then return nil end
    if self:get('NPC','type',n,'int32')~=pet.npc or self:is_boss(n)then self:set('NPC','active',n,false,'bool');return nil end
    local w,h=self:get('Entity','width',n,'int32'),self:get('Entity','height',n,'int32')
    if not self:space_clear(x,y,w,h)then self:set('NPC','active',n,false,'bool');return nil end
    self:set_vec('position',n,x,y)
    self.release_held=self.release_held or{};self.release_held[index]={object=n,until_tick=(self.world_tick or 0)+600}
    return{array=a,index=index,object=n,kind=pet.npc}
end
function W:undo_release(token)
    local a=self:get('Main','npc',nil,'object')
    if a==token.array and self.p.array_at(a,token.index)==token.object and self:get('NPC','type',token.object,'int32')==token.kind then self:set('NPC','active',token.object,false,'bool')end
end
function W:nearest_target(player)
    local x,y=self:vec('position',player);x=x+self:get('Entity','width',player,'int32')/2;y=y+self:get('Entity','height',player,'int32')/2
    local tx,ty,best=nil,nil,800*800;local a=self:get('Main','npc',nil,'object')
    if a then for i=0,math.min(199,self.p.array_length(a)-1)do
        local n=self.p.array_at(a,i)
        if n and not self:is_appearance(n,i)and self:get('NPC','active',n,'bool')and not self:get('NPC','friendly',n,'bool')and not self:get('NPC','dontTakeDamage',n,'bool')and self:get('NPC','life',n,'int32')>0 then
            local nx,ny=self:vec('position',n);nx=nx+self:get('Entity','width',n,'int32')/2;ny=ny+self:get('Entity','height',n,'int32')/2
            local d=(nx-x)^2+(ny-y)^2
            if d<best and self.p.invoke(self.methods.can_hit,player,n)==true then tx,ty,best=nx,ny,d end
        end
    end end
    return tx,ty,x,y
end
function W:aim(player)
    local tx,ty,x,y=self:nearest_target(player)
    if not tx then tx,ty=x+self:get('Entity','direction',player,'int32')*600,y end
    return x,y,math.atan(ty-y,tx-x)
end
function W:break_pots(player)
    local x,y=self:vec('position',player);local w,h=self:get('Entity','width',player,'int32'),self:get('Entity','height',player,'int32')
    local dir=self:get('Entity','direction',player,'int32');local left=x-(dir<0 and self.form.reach or 8);local right=x+w+(dir>0 and self.form.reach or 8)
    local mx,my=self:get('Main','maxTilesX',nil,'int32'),self:get('Main','maxTilesY',nil,'int32')
    for tx=math.max(0,math.floor(left/16)),math.min(mx-1,math.floor(right/16))do for ty=math.max(0,math.floor((y-4)/16)),math.min(my-1,math.floor((y+h+4)/16))do
        if self.p.invoke(self.methods.tile_type,tx,ty)==28 then self.p.invoke(self.methods.kill_tile,tx,ty,false,false,false)end
    end end
end
return W
