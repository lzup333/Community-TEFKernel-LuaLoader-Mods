-- SpawnControlLua: natural spawn multipliers and configurable boss summon count.
-- Settings are stored by TEFManager in the mod private directory/config.json.
mod.meta = { pkg_id = "celso.lua.spawncontrol", version = "1.0.5" }

local patch = mod.patch
local hooks = {}
local spawn_refresh_method
local spawn_on_player_method
local spawn_boss_method
local in_boss_duplicate = false
local boss_entry_depth = 0
local spawn_max_field
local spawn_rate_field
local base_spawn_max
local base_spawn_rate
local applied_multiplier

local config = {
    ordinary_multiplier = 1,
    event_multiplier = 1,
    boss_summon_count = 2,
}

local function read_config()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" then
        mod.info("未找到 TEFManager 配置，使用默认倍率 1×")
        return
    end

    local function read_integer(key, fallback, maximum)
        local escaped = key:gsub("([^%w])", "%%%1")
        local value = tonumber(raw:match('"' .. escaped .. '"%s*:%s*(-?%d+)'))
        if not value then return fallback end
        return math.max(1, math.min(maximum, math.floor(value)))
    end

    config.ordinary_multiplier = read_integer("ordinary_multiplier", 1, 4)
    config.event_multiplier = read_integer("event_multiplier", 1, 4)
    config.boss_summon_count = read_integer("boss_summon_count", 2, 10)
end

local main_type
local npc_type_cache
local dd2_type_cache
local static_field_cache = {}

local function get_static_field(type_handle, name, value_type)
    if not type_handle then return nil end
    local key = tostring(type_handle) .. ":" .. name
    local field = static_field_cache[key]
    if field == false then return nil end
    if not field then
        field = patch.get_field(type_handle, name)
        static_field_cache[key] = field or false
    end
    if not field then return nil end
    local ok, value = pcall(patch.get_field_value, field, nil, value_type)
    if ok then return value end
    return nil
end

local function is_event_active()
    if not main_type then return false end
    local invasion = tonumber(get_static_field(main_type, "invasionType", "int32") or 0) or 0
    if invasion > 0 then return true end

    for _, name in ipairs({ "bloodMoon", "eclipse", "slimeRain", "pumpkinMoon", "snowMoon" }) do
        if get_static_field(main_type, name, "bool") == true then return true end
    end
    if npc_type_cache and get_static_field(npc_type_cache, "LunarApocalypseIsUp", "bool") == true then return true end
    if dd2_type_cache and get_static_field(dd2_type_cache, "Ongoing", "bool") == true then return true end
    return false
end

local function apply_spawn_multiplier()
    if not spawn_max_field or not spawn_rate_field then return end

    local current_max = tonumber(get_static_field(npc_type_cache, "defaultMaxSpawns", "int32"))
    local current_rate = tonumber(get_static_field(npc_type_cache, "defaultSpawnRate", "int32"))
    if not current_max or not current_rate or current_max <= 0 or current_rate <= 0 then return end

    -- Capture the game's vanilla values only after Terraria initializes them.
    -- This mirrors MyriadLife's working mechanism and avoids relying on a
    -- natural-spawn callback that can be inaccessible on this Lua API.
    if not base_spawn_max or not base_spawn_rate then
        base_spawn_max = current_max
        base_spawn_rate = current_rate
    end

    local multiplier = is_event_active() and config.event_multiplier or config.ordinary_multiplier
    multiplier = math.max(1, math.min(4, math.floor(multiplier)))
    local target_max = math.min(999, base_spawn_max * multiplier)
    local target_rate = math.max(1, math.floor(base_spawn_rate / multiplier))

    if current_max ~= target_max then
        local ok, err = pcall(patch.set_field_value, spawn_max_field, nil, target_max, "int32")
        if not ok then mod.warn("写入 NPC.defaultMaxSpawns 失败: ", err) end
    end
    if current_rate ~= target_rate then
        local ok, err = pcall(patch.set_field_value, spawn_rate_field, nil, target_rate, "int32")
        if not ok then mod.warn("写入 NPC.defaultSpawnRate 失败: ", err) end
    end

    if applied_multiplier ~= multiplier then
        applied_multiplier = multiplier
        mod.info("刷怪参数已应用：倍率 ", multiplier, "×，最大生成数 ", target_max,
            "，生成间隔 ", target_rate, "（游戏原值 ", base_spawn_max, "/", base_spawn_rate, "）")
    end
end

local function spawn_settings_refresh_postfix()
    apply_spawn_multiplier()
end

-- Root NPC type IDs from the supplied Terraria 1.4.5.8 NPCID.cs.
-- Kept local because LuaLoader 1.1 exposes get_type but not nested-type lookup.
local boss_type_ids = {
    [4]=true, [13]=true, [35]=true, [50]=true, [113]=true,
    [125]=true, [126]=true, [127]=true, [134]=true, [222]=true,
    [245]=true, [262]=true, [266]=true, [370]=true, [392]=true,
    [398]=true, [439]=true, [551]=true, [565]=true, [577]=true,
    [636]=true, [657]=true, [668]=true,
}

local function is_boss_type(npc_type)
    return type(npc_type) == "number" and boss_type_ids[math.floor(npc_type)] == true
end

local function any_npcs_prefix(_, args)
    if in_boss_duplicate and args and is_boss_type(args[1]) then
        -- Bypass the existing-boss check only for our own extra call. Vanilla
        -- item checks remain intact, preventing held attack from repeatedly
        -- creating another full batch while a boss is already present.
        return true, false
    end
    return false
end

local function duplicate_boss(method, args)
    if in_boss_duplicate or config.boss_summon_count <= 1 or not method or not args then return end
    local npc_type
    if method == spawn_on_player_method then
        npc_type = args[2]
    elseif method == spawn_boss_method then
        npc_type = args[3]
    end
    if not is_boss_type(npc_type) then return end

    in_boss_duplicate = true
    for _ = 2, config.boss_summon_count do
        local ok, err
        if method == spawn_on_player_method then
            ok, err = pcall(patch.invoke, method, args[1], args[2], args[3], args[4], args[5], args[6])
        else
            ok, err = pcall(patch.invoke, method, args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8])
        end
        if not ok then
            mod.warn("Boss 追加召唤失败: ", err)
            break
        end
    end
    in_boss_duplicate = false
end

local function spawn_on_player_postfix(_, args)
    if boss_entry_depth == 1 then duplicate_boss(spawn_on_player_method, args) end
    boss_entry_depth = math.max(0, boss_entry_depth - 1)
end

local function spawn_boss_postfix(_, args)
    if boss_entry_depth == 1 then duplicate_boss(spawn_boss_method, args) end
    boss_entry_depth = math.max(0, boss_entry_depth - 1)
end

local function boss_entry_prefix()
    boss_entry_depth = boss_entry_depth + 1
end

local function install_hook(type_handle, method_name, argc, callback)
    if not type_handle then return nil end
    local method = patch.get_method(type_handle, method_name, argc)
    if not method then
        mod.warn("找不到方法，跳过钩子: ", method_name)
        return nil
    end
    local ok, hook = pcall(patch.install_hook, method, { postfix = callback })
    if not ok then
        mod.warn("安装钩子失败: ", method_name, " ", hook)
        return nil
    end
    hooks[#hooks + 1] = hook
    return method
end

local function install_prefix_postfix(type_handle, method_name, argc, prefix, postfix)
    if not type_handle then return nil end
    local method = patch.get_method(type_handle, method_name, argc)
    if not method then
        mod.warn("找不到方法，跳过钩子: ", method_name)
        return nil
    end
    local ok, hook = pcall(patch.install_hook, method, { prefix = prefix, postfix = postfix })
    if not ok then
        mod.warn("安装钩子失败: ", method_name, " ", hook)
        return nil
    end
    hooks[#hooks + 1] = hook
    return method
end

local function install_boss_presence_hook(npc_type)
    local any_npcs_method = npc_type and patch.get_method(npc_type, "AnyNPCs", 1)
    if not any_npcs_method then
        mod.warn("找不到 NPC.AnyNPCs；额外 Boss 召唤可能受原版已有 Boss 检查阻挡")
        return
    end
    local ok, any_hook = pcall(patch.install_hook, any_npcs_method, { prefix = any_npcs_prefix })
    if not ok then
        mod.warn("安装已有 Boss 检查钩子失败: ", any_hook)
        return
    end
    hooks[#hooks + 1] = any_hook
end

function setup()
    read_config()

    npc_type_cache = patch.get_type("Terraria", "NPC")
    main_type = patch.get_type("Terraria", "Main")
    dd2_type_cache = patch.get_type("Terraria.GameContent.Events", "DD2Event")

    -- Use Terraria's spawn cap and interval values, as MyriadLife does,
    -- instead of trying to duplicate individual NPC.NewNPC calls.
    spawn_max_field = npc_type_cache and patch.get_field(npc_type_cache, "defaultMaxSpawns")
    spawn_rate_field = npc_type_cache and patch.get_field(npc_type_cache, "defaultSpawnRate")
    spawn_refresh_method = install_hook(npc_type_cache, "UpdateFoundActiveNPCs", 0,
        spawn_settings_refresh_postfix)
    if not spawn_max_field or not spawn_rate_field then
        mod.warn("找不到 NPC.defaultMaxSpawns/defaultSpawnRate；普通与事件倍率无法应用")
    end
    if not spawn_refresh_method then
        mod.warn("找不到 NPC.UpdateFoundActiveNPCs；将只在加载时尝试应用倍率")
    end
    apply_spawn_multiplier()

    -- Boss entry points used by vanilla summon items. The boss-type set prevents
    -- duplicating ordinary NPC/event spawns that happen to use these APIs.
    -- Some vanilla paths call SpawnOnPlayer and then SpawnBoss; only the outer
    -- entry point duplicates so one item use cannot turn 2 into 4 bosses.
    if config.boss_summon_count > 1 then
        install_boss_presence_hook(npc_type_cache)
        spawn_on_player_method = install_prefix_postfix(npc_type_cache, "SpawnOnPlayer", 6,
            boss_entry_prefix, spawn_on_player_postfix)
        spawn_boss_method = install_prefix_postfix(npc_type_cache, "SpawnBoss", 8,
            boss_entry_prefix, spawn_boss_postfix)
    end

    mod.info("生成倍率已加载：普通 ", config.ordinary_multiplier, "×，事件 ", config.event_multiplier,
        "×，Boss 召唤数量 ", config.boss_summon_count, " 只")
end

function cleanup()
    if spawn_max_field and base_spawn_max then
        pcall(patch.set_field_value, spawn_max_field, nil, base_spawn_max, "int32")
    end
    if spawn_rate_field and base_spawn_rate then
        pcall(patch.set_field_value, spawn_rate_field, nil, base_spawn_rate, "int32")
    end
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
end
mod.cleanup = cleanup

todo_list = { "setup" }
