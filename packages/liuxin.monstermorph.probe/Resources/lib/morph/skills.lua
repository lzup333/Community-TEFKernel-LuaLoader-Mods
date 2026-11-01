-- Original enemy attacks only; IDs checked against the supplied Android ID tables.
local G=require('morph.growth')
local Forms=require('morph.forms')
local function origin(key)local f=Forms.find(key);return f and f.species or key end
local S={order={'bone','stinger','feather','sickle','arrow','ice_spike'},by_id={}}
local definitions={
    {id='bone',name='骷髅投骨',source='skeleton',npc=21,kind=21,count=1,speed=8.5,vy=-4,damage=26,cooldown=40},
    {id='stinger',name='黄蜂毒刺',source='hornet',npc=42,kind=55,count=1,speed=9,damage=22,cooldown=50},
    {id='feather',name='鸟妖羽毛',source='harpy',npc=48,kind=38,count=3,speed=10,damage=24,cooldown=70},
    {id='sickle',name='恶魔镰刀',source='demon',npc=62,kind=44,count=3,speed=9,damage=30,cooldown=90},
    {id='arrow',name='骷髅弓手射箭',source='skeleton_archer',npc=110,kind=81,count=1,speed=10,damage=26,cooldown=55},
    {id='ice_spike',name='尖刺冰雪史莱姆冰刺',source='spiked_ice_slime',npc=184,kind=174,count=3,speed=9,damage=24,cooldown=75},
}
for _,d in ipairs(definitions)do S.by_id[d.id]=d end
function S.options(key,data,stage)
    local eligible={};local used={}
    for i=1,3 do if data.choices[i] then used[data.choices[i]]=true end end
    for _,id in ipairs(S.order)do
        if S.by_id[id].source~=origin(key) and not used[id] then eligible[#eligible+1]=id end
    end
    local out={}
    for i=1,math.min(3,#eligible)do out[i]=eligible[((stage-1)*2+i-1)%#eligible+1] end
    return out
end
function S.sanitize(key,data,xp)
    local used={}
    for i=1,3 do
        local id=data.choices[i];local d=S.by_id[id]
        if G.level(xp)<G.levels[i] or not d or d.source==origin(key) or used[id] then data.choices[i]=nil
        else used[id]=true end
    end
    local equipped={}
    for i=1,2 do
        local id=data.equipped[i]
        if not used[id] or equipped[id] then data.equipped[i]=nil else equipped[id]=true end
    end
    return data
end
function S.choose(key,data,xp,stage,id)
    if not G.levels[stage] or G.level(xp)<G.levels[stage] or data.choices[stage] then return false end
    for _,option in ipairs(S.options(key,data,stage))do
        if option==id then data.choices[stage]=id
            for slot=1,2 do if not data.equipped[slot] then data.equipped[slot]=id;break end end
            return true
        end
    end
    return false
end
return S
