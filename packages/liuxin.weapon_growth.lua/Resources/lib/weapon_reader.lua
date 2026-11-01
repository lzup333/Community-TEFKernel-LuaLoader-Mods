-- ID 只标识物品；类别来自游戏字段，不依赖武器名单或连续 ID 区间。
local M = {}
M.names={melee='近战',ranged='远程',magic='魔法',summon='召唤'}
function M.identify(item)
    if type(item.id)~='number' or item.id<=0 or item.id%1~=0 then return nil,'invalid_id' end
    if type(item.damage)~='number' or item.damage<=0 then return nil,'not_weapon' end
    if type(item.ammo)~='number' or item.ammo<0 then return nil,'invalid_ammo_field' end
    if item.ammo>0 then return nil,'ammunition' end
    if item.bomb==true then return nil,'bomb' end
    for _,key in ipairs({'pick','axe','hammer'}) do
        if type(item[key])~='number' then return nil,'invalid_tool_fields' end
        if item[key]~=0 then return nil,'tool' end
    end
    local category,count=nil,0
    for _,key in ipairs({'melee','ranged','magic','summon'}) do
        if type(item[key])~='boolean' then return nil,'invalid_class_fields' end
        if item[key] then category=key;count=count+1 end
    end
    if count==0 then return nil,'unclassified' end
    if count>1 then return nil,'mixed_class' end
    return {id=item.id,category=category,damage=item.damage,name=M.names[category]..'武器#'..item.id}
end
return M
