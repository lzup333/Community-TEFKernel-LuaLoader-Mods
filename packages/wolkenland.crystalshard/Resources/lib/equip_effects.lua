-- 饰品效果：原版不认识自定义饰品，属性要靠钩子自己补。
local q = mod.quickapi
local ids = require("ids")

local M = {}

-- 装备栏 0~2 是盔甲，3~9 是饰品槽
local ACCESSORY_FIRST = 3
local ACCESSORY_LAST = 9

local function runtime_id(name)
    local id = q.item_id(name)
    if type(id) == "number" and id > 0 then return id end
    return nil
end

local function has_equipped(player, type_id)
    if not type_id then return false end
    local armor = q.get_object("Terraria", "Player", "armor", player)
    if not armor then return false end
    local last = mod.patch.array_length(armor) - 1
    if last > ACCESSORY_LAST then last = ACCESSORY_LAST end
    for i = ACCESSORY_FIRST, last do
        local item = mod.patch.array_at(armor, i)
        if item and q.get_field_value("Terraria", "Item", "type", item, "int32") == type_id then
            return true
        end
    end
    return false
end

local function add_player_field(player, field, amount, vtype)
    local current = q.get_field_value("Terraria", "Player", field, player, vtype)
    if type(current) ~= "number" then return end
    q.set_field_value("Terraria", "Player", field, player, current + amount, vtype)
end

-- UpdateEquips 每帧从基础值重算属性，在 postfix 里加最稳
local function update_equips_postfix(player)
    if not player then return end
    if has_equipped(player, runtime_id(ids.item.cloak)) then
        add_player_field(player, "moveSpeed", 0.12, "float")
    end
    if has_equipped(player, runtime_id(ids.item.eye)) then
        add_player_field(player, "statManaMax2", 20, "int32")
    end
    if has_equipped(player, runtime_id(ids.item.badge)) then
        add_player_field(player, "maxMinions", 1, "int32")
    end
end

local function weapon_crit_postfix(player, args, result)
    if not player then return nil end
    if not has_equipped(player, runtime_id(ids.item.bracer)) then return nil end
    local base = tonumber(result) or 0
    return base + 8
end

function M.register()
    local ok, err = pcall(q.install_hook_postfix, "Terraria", "Player", "UpdateEquips",
            update_equips_postfix, { argc = 0 })
    if not ok then
        mod.warn("碎晶之链：UpdateEquips 钩子安装失败 " .. tostring(err))
    end

    local ok2, err2 = pcall(q.install_hook_postfix, "Terraria", "Player", "GetWeaponCrit",
            weapon_crit_postfix, { argc = 1, override_result = true })
    if not ok2 then
        mod.warn("碎晶之链：GetWeaponCrit 钩子安装失败 " .. tostring(err2))
    end
end

return M
