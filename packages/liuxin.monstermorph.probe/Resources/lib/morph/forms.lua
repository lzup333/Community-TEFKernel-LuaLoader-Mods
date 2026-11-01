-- Runtime companion registry. A key identifies an individual, never a species.
local Catalog=require('morph.catalog')
local F={}
function F.template(npc)
    for _,d in ipairs(Catalog)do if d.npc==npc and not d.boss then return d end end
end
function F.find(key)for i,d in ipairs(F)do if d.key==key then return d,i end end end
function F.make(pet)
    local d={};local template=F.template(pet.npc)
    if template then for k,v in pairs(template)do d[k]=v end end
    d.key=pet.id;d.species=template and template.key or ('npc_'..pet.npc)
    d.kind=template and template.key or 'ground';d.npc=pet.npc;d.name=pet.name
    d.damage=pet.damage;d.defense=pet.defense;d.netid=pet.netid;d.width=pet.width;d.height=pet.height;d.enabled=true;d.boss=nil
    d.duration=d.duration or 16;d.cooldown=d.cooldown or 40;d.reach=d.reach or 16
    d.rush=d.rush or 6;d.knockback=d.knockback or 4;d.help=d.help or '原生攻击随机使用普攻或可用技能'
    if pet.ai==1 then d.kind='slime';d.movement='charge';d.buoyant=true end
    if pet.ai==16 then d.swim=true;d.flight=false;d.kind='fish'
    elseif pet.nogravity then d.flight=true;d.fly_speed=d.fly_speed or 7;d.anchor='center' end
    if pet.phase then d.phase=true;d.flight=true;d.kind=pet.ai==6 and 'worm' or 'ghost' end
    d.lava_immune=pet.lava;d.immunities=pet.immunities or {};d.parts=pet.parts or {}
    return d
end
function F.populate(pets)
    for i=#F,1,-1 do F[i]=nil end
    for _,pet in ipairs(pets)do F[#F+1]=F.make(pet) end
end
return F
