-- 使用 Terraria 自身语义集合识别炸弹，弹药按 Item.ammo 字段识别。
local M={}
function M.open(P,log)
    local itemBombs
    pcall(function()
        local itemId=P.get_type('Terraria.ID','ItemID')
        local sets=itemId and P.get_inner_type(itemId,'Sets')
        local field=sets and P.get_field(sets,'ItemsThatCountAsBombsForDemolitionistToSpawn')
        if field then itemBombs=field end
    end)
    if not itemBombs then log('ITEM_BOMB_SET_UNAVAILABLE','无法读取原版炸弹集合；弹药字段仍会排除箭和子弹',true) end
    local function marked(field,id)
        if not field or type(id)~='number' or id<0 then return nil end
        local array=P.get_field_value(field,nil,'object')
        if not array or id>=P.array_length(array) then return false end
        local value=P.array_at(array,id,'bool')
        return type(value)=='boolean' and value or false
    end
    return {
        item_bomb=function(_,id) return marked(itemBombs,id) end,
    }
end
return M
