mod.meta = {pkg_id='loot.burst.effects', version='0.1.7'}
local hooks, stack, npc_stack = {}, {}, {}
local P=mod.patch
local f={}
local lines={}
local trace_count=0
local function record(message)
    lines[#lines+1]=message
    if #lines>80 then table.remove(lines,1) end
    pcall(mod.write_file, 'loot_burst.log', table.concat(lines,'\n') .. '\n')
    mod.info('[LootBurst] '..message)
end
local function push_open(kind)
    return {prefix=function(player,args)
        local ok, id = pcall(P.get_field_value,f.who,player,'int32')
        stack[#stack+1]={kind=kind, player=ok and id or nil, count=0}
        return false
    end, postfix=function() stack[#stack]=nil end}
end
local function scatter(player,args)
    local ctx=stack[#stack]
    if not ctx then return false end
    local ok, result=pcall(function()
        if P.get_field_value(f.net,nil,'int32') ~= 0 then return false end
        local id=P.get_field_value(f.who,player,'int32')
        if ctx.player == nil or id ~= ctx.player then return false end
        local typ,amount=args[2],args[3]
        if type(typ)~='number' or typ<=0 or type(amount)~='number' or amount<=0 then return false end
        local x,y=P.get_field_vec2(f.position,player)
        local width=P.get_field_value(f.width,player,'int32')
        local height=P.get_field_value(f.height,player,'int32')
        local items=P.get_field_value(f.items,nil,'object')
        if not x or not y or not width or not height or not items then return false end
        local len=P.array_length(items)
        if not len or len<=1 then return false end
        local function location(n)
            local side=(n%2==0) and -1 or 1
            local lane=math.floor(n/2)+1
            return side,lane,side*math.min(12+lane*9,90)
        end
        local function create(n, quantity)
            local _,_,dx=location(n)
            return P.invoke(f.newitem,math.floor(x+width/2+dx),math.floor(y+height/2),0,0,typ,quantity,false,0,0)
        end
        local function valid(index)
            return type(index)=='number' and index>=0 and index<len and index<400
        end
        local function animate(index,n)
            local item=P.array_at(items,index)
            if item then
                local side,lane=location(n)
                P.set_field_vec2(f.velocity,item,side*math.min(2.2+lane*0.85,8),-4.5-(lane%3)*0.65)
                P.set_field_value(f.grabdelay,item,120,'int32')
                P.set_field_value(f.grabplayer,item,id,'int32')
            end
        end
        local n=ctx.count
        local index=create(n,amount)
        if not valid(index) then return false end
        -- Once the initial stack exists, do not call original QuickSpawnItem.
        ctx.count=n+1
        pcall(animate,index,n)
        -- Keep the original stack as a reserve; transfer one unit per successful spawn.
        -- A failed spawn restores the reserved unit before returning.
        pcall(function()
            local first=P.array_at(items,index)
            local inner=first and P.get_field_value(f.inner,first,'object')
            if not inner then return end
            for _=1,math.min(amount-1,7) do
                local remaining=P.get_field_value(f.stack,inner,'int32')
                if not remaining or remaining<=1 then break end
                P.set_field_value(f.stack,inner,remaining-1,'int32')
                local next_n=ctx.count
                local made, next_index=pcall(create,next_n,1)
                if not made or not valid(next_index) then
                    P.set_field_value(f.stack,inner,remaining,'int32')
                    break
                end
                ctx.count=next_n+1
                pcall(animate,next_index,next_n)
            end
        end)
        return true
    end)
    if not ok then record('fallback: '..tostring(result)); return false end
    return result
end
-- Compare free slots around the original loot routine; existing drops are untouched.
local function slot_empty(items,i)
    local w=P.array_at(items,i)
    local inner=w and P.get_field_value(f.inner,w,'object')
    if not inner then return true end
    local typ=P.get_field_value(f.type,inner,'int32')
    local amount=P.get_field_value(f.stack,inner,'int32')
    return not typ or typ<=0 or not amount or amount<=0
end
local function loot_begin(npc)
    local entry={enabled=false}
    trace_count=trace_count+1
    entry.trace=trace_count<=20
    if entry.trace then record('npc begin '..trace_count) end
    npc_stack[#npc_stack+1]=entry
    local ok,err=pcall(function()
        local net=P.get_field_value(f.net,nil,'int32')
        if net~=0 then if entry.trace then record('npc skipped net='..tostring(net)) end; return end
        local items=P.get_field_value(f.items,nil,'object')
        if not items then if entry.trace then record('npc items unavailable') end; return end
        local n=math.min(P.array_length(items),400)
        local vx,vy=P.get_field_vec2(f.velocity,npc)
        entry.vx=math.max(-4,math.min(4,(vx or 0)*0.45))
        entry.vy=math.max(-2,math.min(1,(vy or 0)*0.2))
        local got_player,player_index=pcall(P.invoke,f.myplayer)
        if got_player and type(player_index)=='number' and player_index>=0 and player_index<255 then entry.player=player_index end
        entry.free={}
        for i=0,n-1 do if slot_empty(items,i) then entry.free[#entry.free+1]=i end end
        entry.enabled=true
        if entry.trace then record('npc snapshot slots='..n..' free='..#entry.free..' vx='..entry.vx..' vy='..entry.vy) end
    end)
    if not ok then record('npc scan: '..tostring(err)) end
    return false
end
local function loot_end()
    local entry=npc_stack[#npc_stack]
    npc_stack[#npc_stack]=nil
    if not entry or not entry.enabled then return end
    local ok,err=pcall(function()
        local items=P.get_field_value(f.items,nil,'object')
        if not items then return end
        local count=0
        for _,i in ipairs(entry.free) do
            if not slot_empty(items,i) then
                local item=P.array_at(items,i)
                count=count+1
                local side=count%2==1 and -1 or 1
                local spread=3.2+((count-1)%4)*0.55
                local influence=math.max(-0.6,math.min(0.6,side*entry.vx*0.2))
                local x=side*(spread+influence)
                local y=entry.vy-5.2-((count-1)%3)*0.4
                P.set_field_vec2(f.velocity,item,x,y)
                if entry.player then
                    P.set_field_value(f.grabdelay,item,60,'int32')
                    P.set_field_value(f.grabplayer,item,entry.player,'int32')
                end
                if entry.trace and count<=3 then
                    local actual_x,actual_y=P.get_field_vec2(f.velocity,item)
                    record('npc velocity index='..i..' actual='..tostring(actual_x)..','..tostring(actual_y)..' delay_player='..tostring(entry.player))
                end
            end
        end
        if entry.trace then record('npc end new_items='..count) end
    end)
    if not ok then record('npc scatter: '..tostring(err)) end
end
local function install(method, callbacks)
    hooks[#hooks+1]=P.install_hook(assert(method),callbacks)
end
function setup()
    local ok,err=pcall(function()
        local player=assert(P.get_type('Terraria','Player'))
        local main=assert(P.get_type('Terraria','Main'))
        local world=assert(P.get_type('Terraria','WorldItem'))
        local item=assert(P.get_type('Terraria','Item'))
        f.newitem=assert(P.get_method_by_names(item,'NewItem',{'X','Y','Width','Height','Type','Stack','noBroadcast','pfix','ownership'}), 'Item.NewItem overload unavailable')
        f.who=assert(P.get_field(player,'whoAmI'))
        f.position=assert(P.get_field(player,'position'))
        f.width=assert(P.get_field(player,'width'))
        f.height=assert(P.get_field(player,'height'))
        f.net=assert(P.get_field(main,'netMode'))
        f.items=assert(P.get_field(main,'item'))
        f.myplayer=P.get_method(main,'get_myPlayer',0)
        f.velocity=assert(P.get_field(world,'velocity'))
        f.inner=assert(P.get_field(world,'inner'))
        f.stack=assert(P.get_field(item,'stack'))
        f.type=assert(P.get_field(item,'type'))
        f.grabdelay=assert(P.get_field(world,'grabDelayTime'))
        f.grabplayer=assert(P.get_field(world,'grabDelayPlayer'))
        local bag=assert(P.get_method(player,'OpenBossBag',1))
        local crate=assert(P.get_method(player,'OpenFishingCrate',1))
        local quick=assert(P.get_method_by_names(player,'QuickSpawnItem',{'source','item','stack'}))
        install(bag,push_open('bag'))
        install(crate,push_open('crate'))
        install(quick,{prefix=scatter})
        local npc_ok,npc_err=pcall(function()
            local npc=assert(P.get_type('Terraria','NPC'))
            local loot=assert(P.get_method(npc,'NPCLoot',0), 'NPC.NPCLoot unavailable')
            install(loot,{prefix=loot_begin,postfix=loot_end})
        end)
        if npc_ok then record('ready: single-player, bags, crates and NPC loot')
        else record('NPC loot hook unavailable: '..tostring(npc_err)) end
    end)
    if not ok then
        for i=#hooks,1,-1 do pcall(function()hooks[i]:remove()end) end
        hooks={}; record('initialization failed: '..tostring(err))
    end
end
function mod.cleanup()
    for i=#hooks,1,-1 do pcall(function()hooks[i]:remove()end) end
    hooks={};stack={};npc_stack={}
end
todo_list={'setup'}
