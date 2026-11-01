-- 更多的栏位 (More Slots) —— v1.1.0
-- 作者：Omni

mod.meta = { pkg_id = "Omni.lua.more_slots", version = "1.1.0" }

local patch = mod.patch

local DEFAULTS = {
    enabled               = true,
    defense_mult          = 100,
    social_acc_enabled    = true,
    vanity_armor_enabled  = true,
    inventory_enabled     = false,
    prefix_enabled        = true,
    vanity_set_enabled    = true,
    inventory_set_enabled = false,
    equip_def_enabled     = true,
    acc_def_enabled       = true,
    inv_def_enabled       = true,
    debug_log             = false,
}
local LIMITS = { defense_mult = { 1, 10000 } }

local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
local last_raw, last_check = nil, 0

local function parse_bool(raw, key, fallback)
    local escaped = key:gsub("([^%w])", "%%%1")
    local text = raw:match('"' .. escaped .. '"%s*:%s*(%a+)')
    if text == "true" then return true end
    if text == "false" then return false end
    local digit = raw:match('"' .. escaped .. '"%s*:%s*(%d+)')
    if digit then return digit ~= "0" end
    return fallback
end

local function parse_int(raw, key, fallback, lo, hi)
    local escaped = key:gsub("([^%w])", "%%%1")
    local value = tonumber(raw:match('"' .. escaped .. '"%s*:%s*(-?%d+)'))
    if not value then return fallback end
    value = math.floor(value)
    if lo and value < lo then value = lo end
    if hi and value > hi then value = hi end
    return value
end

local function read_config()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" or raw == last_raw then return end
    local hits = 0
    for key in pairs(DEFAULTS) do
        if raw:find('"' .. key .. '"', 1, true) then hits = hits + 1 end
    end
    if hits == 0 then return end
    
    for key, default in pairs(DEFAULTS) do
        if type(default) == "boolean" then
            cfg[key] = parse_bool(raw, key, cfg[key])
        else
            local lim = LIMITS[key]
            cfg[key] = parse_int(raw, key, cfg[key], lim and lim[1], lim and lim[2])
        end
    end
    last_raw = raw
end

local T_PLAYER, T_ITEM
local F_armor, F_def_stat, F_stack, F_defense
local F_inventory, F_bank, F_bank2, F_bank3, F_bank4, F_storage_item
local F_headSlot, F_bodySlot, F_legSlot, F_accessory

local M_equip, M_prefix, M_armor, M_updateArmorSets
local ready = false

local SOCIAL_START, SOCIAL_END = 13, 19
local VANITY_START, VANITY_END = 10, 12

local saved_armor_defs = {}

local function item_valid(item)
    if not item then return false end
    local ok, s = pcall(patch.get_field_value, F_stack, item, "int32")
    return ok and s and s > 0
end

local function get_storage_items(container)
    if not container or not F_storage_item then return nil end
    local ok, arr = pcall(patch.get_field_value, F_storage_item, container, "object")
    if ok and arr then return arr end
    return nil
end

local function apply_item_single(player, item, is_acc, is_inv)
    if not item_valid(item) then return end

    local zero_def = false
    local old_def = 0
    if is_inv and not cfg.inv_def_enabled then zero_def = true
    elseif not is_inv and is_acc and not cfg.acc_def_enabled then zero_def = true
    elseif not is_inv and not is_acc and not cfg.equip_def_enabled then zero_def = true
    end

    if zero_def then
        local ok, d = pcall(patch.get_field_value, F_defense, item, "int32")
        if ok and d and d > 0 then
            old_def = d
            pcall(patch.set_field_value, F_defense, item, 0, "int32")
        else
            zero_def = false
        end
    end

    if is_acc then
        pcall(patch.invoke, M_equip, player, 3, item)
    end
    pcall(patch.invoke, M_armor, player, item)
    if cfg.prefix_enabled then
        pcall(patch.invoke, M_prefix, player, item)
    end

    if zero_def then
        pcall(patch.set_field_value, F_defense, item, old_def, "int32")
    end
end

local function process_container(player, arr)
    if not arr then return end
    local ok, len = pcall(patch.array_length, arr)
    if not ok or type(len) ~= "number" or len <= 0 then return end

    for i = 0, len - 1 do
        local ok2, item = pcall(patch.array_at, arr, i)
        if ok2 and item_valid(item) then
            local is_acc = patch.get_field_value(F_accessory, item, "bool")
            local is_head = (patch.get_field_value(F_headSlot, item, "int32") or -1) >= 0
            local is_body = (patch.get_field_value(F_bodySlot, item, "int32") or -1) >= 0
            local is_leg = (patch.get_field_value(F_legSlot, item, "int32") or -1) >= 0
            
            if is_acc or is_head or is_body or is_leg then
                apply_item_single(player, item, is_acc, true) -- is_inv = true
            end
        end
    end
end

local function find_inv_set(player)
    local h, b, l = nil, nil, nil
    local containers = {
        patch.get_field_value(F_inventory, player, "object"),
        get_storage_items(patch.get_field_value(F_bank, player, "object")),
        get_storage_items(patch.get_field_value(F_bank2, player, "object")),
        get_storage_items(patch.get_field_value(F_bank3, player, "object")),
        get_storage_items(patch.get_field_value(F_bank4, player, "object")),
    }
    
    for _, arr in ipairs(containers) do
        if arr then
            local ok, len = pcall(patch.array_length, arr)
            if ok and type(len) == "number" then
                for i = 0, len - 1 do
                    local ok2, item = pcall(patch.array_at, arr, i)
                    if ok2 and item_valid(item) then
                        if not h and (patch.get_field_value(F_headSlot, item, "int32") or -1) >= 0 then h = item end
                        if not b and (patch.get_field_value(F_bodySlot, item, "int32") or -1) >= 0 then b = item end
                        if not l and (patch.get_field_value(F_legSlot, item, "int32") or -1) >= 0 then l = item end
                        if h and b and l then return h, b, l end
                    end
                end
            end
        end
    end
    return nil
end

local function try_apply_set_bonus(player, equip_index, h, b, l)
    if not h or not b or not l then return end
    local arr = patch.get_field_value(F_armor, player, "object")
    if not arr then return end

    local saved = { patch.array_at(arr, 0), patch.array_at(arr, 1), patch.array_at(arr, 2) }

    pcall(patch.array_set, arr, 0, h)
    pcall(patch.array_set, arr, 1, b)
    pcall(patch.array_set, arr, 2, l)

    pcall(patch.invoke, M_updateArmorSets, player, equip_index)

    pcall(patch.array_set, arr, 0, saved[1])
    pcall(patch.array_set, arr, 1, saved[2])
    pcall(patch.array_set, arr, 2, saved[3])
end

local function on_reset_effects(player, args, result)
    if not ready or not player or not cfg.enabled then return end
    
    local now = os.time()
    if now and (now - last_check) >= 5 then
        last_check = now
        read_config()
    end

    if cfg.social_acc_enabled then
        local arr = patch.get_field_value(F_armor, player, "object")
        if arr then
            for idx = SOCIAL_START, SOCIAL_END do
                apply_item_single(player, patch.array_at(arr, idx), true, false)
            end
        end
    end

    if cfg.vanity_armor_enabled then
        local arr = patch.get_field_value(F_armor, player, "object")
        if arr then
            for idx = VANITY_START, VANITY_END do
                apply_item_single(player, patch.array_at(arr, idx), false, false)
            end
        end
    end

    if cfg.inventory_enabled then
        local inv = patch.get_field_value(F_inventory, player, "object")
        process_container(player, inv)
        
        local banks = { F_bank, F_bank2, F_bank3, F_bank4 }
        for _, bf in ipairs(banks) do
            local chest = patch.get_field_value(bf, player, "object")
            if chest then
                local arr = get_storage_items(chest)
                process_container(player, arr)
            end
        end
    end
end

local function on_update_equips_prefix(player, args, result)
    if not ready or not player or not cfg.enabled then return end
    saved_armor_defs = {}

    local arr = patch.get_field_value(F_armor, player, "object")
    if not arr then return end

    local function zero_def(idx)
        local ok, item = pcall(patch.array_at, arr, idx)
        if ok and item_valid(item) then
            local ok2, d = pcall(patch.get_field_value, F_defense, item, "int32")
            if ok2 and d and d > 0 then
                saved_armor_defs[#saved_armor_defs + 1] = { item = item, def = d }
                pcall(patch.set_field_value, F_defense, item, 0, "int32")
            end
        end
    end

    if not cfg.equip_def_enabled then
        for i = 0, 2 do zero_def(i) end
        for i = 10, 12 do zero_def(i) end
    end

    if not cfg.acc_def_enabled then
        for i = 3, 9 do zero_def(i) end
        for i = 13, 19 do zero_def(i) end
    end
end

local function on_update_equips_postfix(player, args, result)
    if not ready or not player or not cfg.enabled then return end

    for _, data in ipairs(saved_armor_defs) do
        pcall(patch.set_field_value, F_defense, data.item, data.def, "int32")
    end
    saved_armor_defs = {}

    local equip_index = 0
    if args and type(args[1]) == "number" then equip_index = args[1] end

    if cfg.vanity_set_enabled then
        local arr = patch.get_field_value(F_armor, player, "object")
        if arr then
            local h = patch.array_at(arr, VANITY_START)
            local b = patch.array_at(arr, VANITY_START + 1)
            local l = patch.array_at(arr, VANITY_START + 2)
            try_apply_set_bonus(player, equip_index, h, b, l)
        end
    end

    if cfg.inventory_set_enabled then
        local h, b, l = find_inv_set(player)
        try_apply_set_bonus(player, equip_index, h, b, l)
    end

    if cfg.defense_mult ~= 100 then
        local cur_def = patch.get_field_value(F_def_stat, player, "int32") or 0
        local new_def = math.floor(cur_def * cfg.defense_mult / 100 + 0.5)
        pcall(patch.set_field_value, F_def_stat, player, new_def, "int32")
    end
end

function setup()
    read_config()

    T_PLAYER = patch.get_type("Terraria", "Player")
    T_ITEM   = patch.get_type("Terraria", "Item")
    if not T_PLAYER or not T_ITEM then
        mod.error("获取类型失败")
        return
    end

    F_armor    = patch.get_field(T_PLAYER, "armor")
    F_def_stat = patch.get_field(T_PLAYER, "statDefense")
    F_inventory= patch.get_field(T_PLAYER, "inventory")
    F_bank     = patch.get_field(T_PLAYER, "bank")
    F_bank2    = patch.get_field(T_PLAYER, "bank2")
    F_bank3    = patch.get_field(T_PLAYER, "bank3")
    F_bank4    = patch.get_field(T_PLAYER, "bank4")

    F_stack    = patch.get_field(T_ITEM, "stack")
    F_defense  = patch.get_field(T_ITEM, "defense")
    F_accessory= patch.get_field(T_ITEM, "accessory")
    F_headSlot = patch.get_field(T_ITEM, "headSlot")
    F_bodySlot = patch.get_field(T_ITEM, "bodySlot")
    F_legSlot  = patch.get_field(T_ITEM, "legSlot")

    local T_STORAGE = patch.get_type("Terraria", "InventoryStorage") or patch.get_type("Terraria", "Chest")
    if T_STORAGE then
        F_storage_item = patch.get_field(T_STORAGE, "item")
    end

    if not F_armor or not F_inventory or not F_defense then
        mod.error("获取核心字段失败")
        return
    end

    M_equip  = patch.get_method(T_PLAYER, "ApplyEquipFunctional", 2) or patch.get_method(T_PLAYER, "ApplyEquipFunctional")
    M_prefix = patch.get_method(T_PLAYER, "GrantPrefixBenefits", 1) or patch.get_method(T_PLAYER, "GrantPrefixBenefits")
    M_armor  = patch.get_method(T_PLAYER, "GrantArmorBenefits", 1) or patch.get_method(T_PLAYER, "GrantArmorBenefits")
    M_updateArmorSets = patch.get_method(T_PLAYER, "UpdateArmorSets", 1) or patch.get_method(T_PLAYER, "UpdateArmorSets")

    if not (M_equip and M_prefix and M_armor and M_updateArmorSets) then
        mod.error("关键方法未解析")
        return
    end

    local reset = patch.get_method(T_PLAYER, "ResetEffects", 0) or patch.get_method(T_PLAYER, "ResetEffects")
    local update = patch.get_method(T_PLAYER, "UpdateEquips", 1) or patch.get_method(T_PLAYER, "UpdateEquips")

    if not reset or not update then
        mod.error("Hook 目标方法缺失")
        return
    end

    ready = true
    pcall(patch.install_hook, reset, { postfix = on_reset_effects })
    pcall(patch.install_hook, update, { 
        prefix = on_update_equips_prefix,
        postfix = on_update_equips_postfix 
    })

    mod.info("更多的栏位 已加载 (v1.1.0, Omni)")
end

function cleanup()
    ready = false
    mod.info("更多的栏位 已卸载")
end

todo_list = { "setup" }