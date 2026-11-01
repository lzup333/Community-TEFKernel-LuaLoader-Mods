-- ============================================================================
-- 掉落连锁（Lua） v1.4.0   pkg_id = celso.lua.dropchain
-- 适用：Terraria Mobile 1.4.5.8 + TEFKernel + LuaLoader 1.2.0
--
-- 机制
--   1. 在 Terraria.NPC.NPCLoot_DropItems(Player) 上装后置钩子：原版物品掉落结算后执行。
--   2. 记录原版实际生成的物品；命中后用 Item.NewItem 生成额外份数，
--      再把概率乘上衰减系数继续掷骰，
--      直到掷骰失败或达到最大追加次数。
--   3. 只复制本次实际掉出的物品，不会重复死亡播报、Boss 进度标记、旗帜/击杀统计等
--      DoDeathEvents 内容，所以连锁不会额外刷屏或重复推进 Boss 进度。
-- ============================================================================

mod.meta = { pkg_id = "celso.lua.dropchain", version = "1.4.0" }

local patch = mod.patch
local hooks = {}

-- TEFManager 未写配置时的默认值（与 Info.json 中的 defaultValue 保持一致）
local DEFAULTS = {
    chain_chance_percent = 35,    -- 首次连锁概率（%）
    max_extra_rounds = 5,         -- 最多追加掉落次数
    chain_decay_percent = 75,     -- 每次连锁后的概率倍率（%）
    announce_min_rounds = 3,      -- 总掉落次数达到该值才提示
    allow_heavy_targets = false,  -- Boss / 特殊目标是否参与连锁
    allow_statue_targets = false, -- 雕像刷出的怪物是否参与连锁
    require_player_hit = true,    -- 只对玩家攻击过的怪物生效
    chain_sound = true,           -- 连锁成功时播放提示音
}

local config = {}
for key, value in pairs(DEFAULTS) do
    config[key] = value
end
local config_loaded = false

-- 每隔若干秒重读一次 config.json，这样在 TEFManager 里改完设置不用重启游戏
local CONFIG_REFRESH_SECONDS = 5
local FIELD_LOOKUP_DEPTH = 6

-- 1.4.5.8 的 Boss 根 ID：npc.boss 为 false 时的兜底判断
local BOSS_TYPE_IDS = {
    [4] = true, [13] = true, [35] = true, [50] = true, [113] = true,
    [125] = true, [126] = true, [127] = true, [134] = true, [222] = true,
    [245] = true, [262] = true, [266] = true, [370] = true, [392] = true,
    [398] = true, [439] = true, [551] = true, [565] = true, [577] = true,
    [636] = true, [657] = true, [668] = true,
}

-- Terraria.ID.SoundID.CoinPickup
local SOUND_COIN_PICKUP = 38

-- ============================================================================
-- 配置读取
-- ============================================================================

local function read_config()
    -- 首次读取失败时用默认值兜底；已成功读过配置后再读失败（例如 TEFManager
    -- 保存时短暂的删除/重命名窗口）则沿用上一次的有效值，避免设置被打回默认。
    if not config_loaded then
        for key, value in pairs(DEFAULTS) do
            config[key] = value
        end
    end

    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" then
        return false
    end

    local function read_int(key, fallback, minimum, maximum)
        local value = tonumber(raw:match('"' .. key .. '"%s*:%s*(-?%d+)'))
        if not value then
            return fallback
        end
        value = math.floor(value)
        return math.max(minimum, math.min(maximum, value))
    end

    local function read_bool(key, fallback)
        local value = raw:match('"' .. key .. '"%s*:%s*(%a+)')
        if value == "true" then
            return true
        end
        if value == "false" then
            return false
        end
        return fallback
    end

    config.chain_chance_percent = read_int("chain_chance_percent", DEFAULTS.chain_chance_percent, 1, 100)
    config.max_extra_rounds = read_int("max_extra_rounds", DEFAULTS.max_extra_rounds, 1, 8)
    config.chain_decay_percent = read_int("chain_decay_percent", DEFAULTS.chain_decay_percent, 10, 95)
    config.announce_min_rounds = read_int("announce_min_rounds", DEFAULTS.announce_min_rounds, 2, 9)
    config.allow_heavy_targets = read_bool("allow_heavy_targets", DEFAULTS.allow_heavy_targets)
    config.allow_statue_targets = read_bool("allow_statue_targets", DEFAULTS.allow_statue_targets)
    config.require_player_hit = read_bool("require_player_hit", DEFAULTS.require_player_hit)
    config.chain_sound = read_bool("chain_sound", DEFAULTS.chain_sound)
    config_loaded = true
    return true
end

-- ============================================================================
-- 句柄缓存
-- ============================================================================

local npc_type, main_type, item_type, world_item_type
local f_npc_type, f_npc_statue, f_npc_boss, f_npc_friendly, f_npc_town
local f_npc_position, f_main_net_mode, f_main_max_tiles_x, f_world_velocity
local m_npc_loot_items, m_npc_interactions, m_new_text, m_play_sound
local f_main_item, f_world_inner, f_item_type, f_item_stack, m_item_new
local m_world_combine
local in_chain = false

local field_cache = {}

-- 字段可能声明在父类上（例如 position 在 Terraria.Entity 上），逐层查找。
local function find_field(type_handle, name)
    if not type_handle then
        return nil
    end
    local cache_key = tostring(type_handle) .. "." .. name
    local cached = field_cache[cache_key]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local current = type_handle
    for _ = 1, FIELD_LOOKUP_DEPTH do
        if not current then
            break
        end
        local field = patch.get_field(current, name)
        if field then
            field_cache[cache_key] = field
            return field
        end
        current = patch.get_parent(current)
    end

    field_cache[cache_key] = false
    return nil
end

local function field_bool(field, instance)
    if not field then
        return nil
    end
    return patch.get_field_value(field, instance, "bool")
end

local function field_int(field, instance)
    if not field then
        return nil
    end
    local value = patch.get_field_value(field, instance, "int32")
    if value == nil then
        return nil
    end
    return tonumber(value)
end

-- Vector2 字段（两个 float）
local function field_vec2(field, instance)
    if not field then
        return nil, nil
    end
    return patch.get_field_vec2(field, instance)
end

-- Terraria 1.4.5.8 的 Main.item 是 WorldItem[]，其 inner 才是 Item。
local function item_snapshot()
    local result = {}
    if not (f_main_item and f_world_inner and f_item_type and f_item_stack) then
        return nil
    end
    local array = patch.get_field_value(f_main_item, nil, "object")
    if not array then return nil end
    local count = math.min(patch.array_length(array), 600)
    for index = 0, count - 1 do
        local world_item = patch.array_at(array, index)
        if world_item then
            local inner = patch.get_field_value(f_world_inner, world_item, "object")
            if inner then
                local kind = field_int(f_item_type, inner)
                local stack = field_int(f_item_stack, inner)
                if kind and kind > 0 and stack and stack > 0 then
                    result[index] = { kind = kind, stack = stack }
                end
            end
        end
    end
    return result
end

local function new_drops(before, after)
    local drops = {}
    if not before or not after then return drops end
    for index, item in pairs(after) do
        local old = before[index]
        local increase = (old and old.kind == item.kind) and (item.stack - old.stack) or item.stack
        if increase > 0 then
            drops[#drops + 1] = { index = index, kind = item.kind, stack = increase }
        end
    end
    return drops
end

-- RPG 式近距离“爆材料”：在怪物周围一小圈抛出，而不是铺满屏幕。
local BURST = {
    { -46, -22, -2.2, -3.0 },
    {  46, -22,  2.2, -3.0 },
    { -30, -58, -1.8, -4.0 },
    {  30, -58,  1.8, -4.0 },
    {   0, -85,  0.8, -4.5 },
}

local function burst_position(x, y, serial)
    local slot = BURST[((serial - 1) % #BURST) + 1]
    local layer = math.floor((serial - 1) / #BURST)
    local dx = slot[1] + (slot[1] < 0 and -12 or 12) * layer
    local dy = slot[2] - 12 * layer
    local world_tiles = field_int(f_main_max_tiles_x, nil)
    local world_width = world_tiles and world_tiles * 16 or nil
    local px = math.max(24, x + dx)
    if world_width then px = math.min(world_width - 24, px) end
    return px, math.max(24, y + dy), slot[3], slot[4]
end

local protected_items = {}

local function world_item_at(index)
    local array = patch.get_field_value(f_main_item, nil, "object")
    if not array then return nil end
    return patch.array_at(array, index)
end

local function protect_item(index)
    local item = world_item_at(index)
    if item then protected_items[tostring(item)] = os.time() + 3 end
    return item
end

local function on_combine(instance)
    if in_chain then return true end
    if not instance then return false end
    local key = tostring(instance)
    local until_time = protected_items[key]
    if not until_time then return false end
    if os.time() <= until_time then return true end
    protected_items[key] = nil
    return false
end

local function push_spawned_item(index, vx, vy)
    local item = protect_item(index)
    if item and f_world_velocity then
        pcall(patch.set_field_vec2, f_world_velocity, item, vx, vy)
    end
end

-- ============================================================================
-- 反馈
-- ============================================================================

local function announce(rounds, x, y)
    if config.chain_sound and m_play_sound then
        -- 连锁越长音调越高，形成“叮—叮—叮”的反馈
        local pitch = math.min(0.6, 0.08 * (rounds - 2))
        pcall(patch.invoke, m_play_sound, SOUND_COIN_PICKUP,
            math.floor(x or -1), math.floor(y or -1), 1, 1.0, pitch)
    end

    if rounds < config.announce_min_rounds or not m_new_text then
        return
    end

    pcall(function()
        local text = patch.string_create(string.format("掉落连锁！ ×%d", rounds))
        if text then
            patch.invoke(m_new_text, text, 255, 205, 70, false)
        end
    end)
end

-- ============================================================================
-- NPCLoot_DropItems 后置钩子
-- ============================================================================

local last_config_check = -math.huge
local warned_invoke_failure = false
local hook_hits = 0
local extra_drops = 0
local spawned_items = 0
local observed_original_items = 0
local before_items, before_instance

local function write_status(state)
    pcall(mod.write_file, "dropchain_status.txt", string.format(
        "version=1.4.0\nstate=%s\nhook_hits=%d\nextra_rounds=%d\nobserved_original_items=%d\nspawned_items=%d\n",
        state, hook_hits, extra_drops, observed_original_items, spawned_items))
end

local function skip(reason)
    if hook_hits <= 3 then
        write_status(reason)
    end
end

local function before_npc_loot(instance)
    if in_chain or not instance then return false end
    before_instance = instance
    before_items = item_snapshot()
    return false
end

local function on_npc_loot(instance, _args, _result)
    if in_chain or not instance then
        return
    end
    hook_hits = hook_hits + 1
    if hook_hits <= 3 then
        write_status("drop_hook_called")
        mod.info("掉落钩子已触发，第 ", hook_hits, " 次")
    end

    local now = os.clock()
    if now - last_config_check >= CONFIG_REFRESH_SECONDS then
        last_config_check = now
        pcall(read_config)
    end

    -- 只在单机 / 主机侧结算，客户端不重复掉落
    local net_mode = field_int(f_main_net_mode, nil)
    if net_mode == 1 then
        skip("client_side")
        return
    end

    -- 友好 NPC、城镇 NPC 不参与
    if field_bool(f_npc_friendly, instance) == true or field_bool(f_npc_town, instance) == true then
        skip("friendly_npc")
        return
    end

    -- 雕像刷出的怪物掉落被原版限制，默认不参与连锁
    if not config.allow_statue_targets and field_bool(f_npc_statue, instance) == true then
        skip("statue_npc")
        return
    end

    local npc_kind = field_int(f_npc_type, instance)
    if not npc_kind then
        skip("npc_type_unavailable")
        return
    end

    -- Boss 与特殊目标的掉落常含一次性物品（奖杯、宝藏袋等），默认跳过
    if not config.allow_heavy_targets then
        if field_bool(f_npc_boss, instance) == true or BOSS_TYPE_IDS[math.floor(npc_kind)] == true then
            skip("special_npc")
            return
        end
    end

    -- 只对玩家打过的怪物生效：避免岩浆、陷阱、坠落等“白捡”连锁
    if config.require_player_hit and m_npc_interactions then
        local ok, interacted = pcall(patch.invoke, m_npc_interactions, instance)
        if not ok or interacted ~= true then
            skip("player_interaction_unconfirmed")
            return
        end
    end

    -- 连掷：命中一次就多结算一轮掉落，概率逐次递减
    local chance = config.chain_chance_percent / 100
    local decay = config.chain_decay_percent / 100
    local extra = 0
    while extra < config.max_extra_rounds and math.random() < chance do
        extra = extra + 1
        chance = chance * decay
    end
    if extra <= 0 then
        skip("chance_missed")
        return
    end

    local drop_method = m_npc_loot_items
    if not drop_method or not m_item_new then
        skip("drop_method_missing")
        return
    end

    local x, y = field_vec2(f_npc_position, instance)

    local original_drops = new_drops(before_instance == instance and before_items or nil,
        item_snapshot())
    before_items, before_instance = nil, nil
    observed_original_items = observed_original_items + #original_drops
    if #original_drops == 0 then
        write_status("no_original_items_observed")
        return
    end

    for _, item in ipairs(original_drops) do protect_item(item.index) end

    in_chain = true
    local succeeded = 0
    local failure = nil
    local spawn_serial = 0
    for round = 1, extra do
        local made_any = false
        for _, item in ipairs(original_drops) do
            spawn_serial = spawn_serial + 1
            local spawn_x, spawn_y, vx, vy = burst_position(x or 0, y or 0, spawn_serial)
            local ok, index = pcall(patch.invoke, m_item_new,
                math.floor(spawn_x), math.floor(spawn_y), 20, 20,
                item.kind, item.stack, false, 0, 0)
            if ok and type(index) == "number" and index >= 0 then
                push_spawned_item(index, vx, vy)
                made_any = true
                spawned_items = spawned_items + 1
            else
                failure = ok and "Item.NewItem 返回失败" or tostring(index)
            end
        end
        if not made_any then break end
        succeeded = succeeded + 1
    end
    in_chain = false
    extra_drops = extra_drops + succeeded
    write_status(failure and "invoke_failed" or "extra_drop_complete")

    if succeeded == 0 then
        if not warned_invoke_failure then
            warned_invoke_failure = true
            mod.warn("掉落连锁结算失败，已停止连锁: ", failure)
        end
        return
    end

    -- 只按真正成功的次数提示，避免“报喜但没掉”
    announce(succeeded + 1, x, y)
end

-- ============================================================================
-- 生命周期
-- ============================================================================

local function install_hook(method, callbacks)
    if not method then
        return nil
    end
    local ok, hook = pcall(patch.install_hook, method, callbacks)
    if not ok then
        mod.warn("安装钩子失败: ", hook)
        return nil
    end
    hooks[#hooks + 1] = hook
    return hook
end

function setup()
    read_config()

    npc_type = patch.get_type("Terraria", "NPC")
    main_type = patch.get_type("Terraria", "Main")
    item_type = patch.get_type("Terraria", "Item")
    world_item_type = patch.get_type("Terraria", "WorldItem")
    local sound_engine_type = patch.get_type("Terraria.Audio", "SoundEngine")

    if not npc_type or not main_type then
        mod.warn("找不到 Terraria.NPC / Terraria.Main，掉落连锁未启用")
        return
    end

    f_npc_type = find_field(npc_type, "type")
    f_npc_statue = find_field(npc_type, "SpawnedFromStatue")
    f_npc_boss = find_field(npc_type, "boss")
    f_npc_friendly = find_field(npc_type, "friendly")
    f_npc_town = find_field(npc_type, "townNPC")
    f_npc_position = find_field(npc_type, "position")

    f_main_net_mode = find_field(main_type, "netMode")
    f_main_max_tiles_x = find_field(main_type, "maxTilesX")
    f_main_item = find_field(main_type, "item")
    f_world_inner = find_field(world_item_type, "inner")
    f_world_velocity = find_field(world_item_type, "velocity")
    f_item_type = find_field(item_type, "type")
    f_item_stack = find_field(item_type, "stack")

    m_npc_loot_items = patch.get_method(npc_type, "NPCLoot_DropItems", 1)
    m_npc_interactions = patch.get_method(npc_type, "AnyInteractions", 0)
    m_item_new = item_type and patch.get_method(item_type, "NewItem", 9) or nil
    m_world_combine = world_item_type and
        patch.get_method(world_item_type, "TryCombiningIntoNearbyItems", 0) or nil
    m_new_text = patch.get_method(main_type, "NewText", 5)
    m_play_sound = sound_engine_type and patch.get_method(sound_engine_type, "PlaySound", 6) or nil

    if not m_npc_loot_items then
        mod.warn("找不到 NPC.NPCLoot_DropItems，掉落连锁未启用")
        write_status("drop_method_missing")
        return
    end
    if not f_npc_type then
        mod.warn("找不到 NPC.type，掉落连锁未启用")
        return
    end
    if not (f_main_item and f_world_inner and f_item_type and f_item_stack and m_item_new) then
        mod.warn("找不到世界物品字段或 Item.NewItem，掉落连锁未启用")
        write_status("item_api_missing")
        return
    end

    local hook = install_hook(m_npc_loot_items,
        { prefix = before_npc_loot, postfix = on_npc_loot })
    if not hook then
        write_status("hook_install_failed")
        return
    end
    if m_world_combine then
        install_hook(m_world_combine, { prefix = on_combine })
    end
    write_status("hook_installed")

    mod.info("掉落连锁已加载：首次概率 ", config.chain_chance_percent, "%，最多追加 ",
        config.max_extra_rounds, " 次，每次概率 ×", config.chain_decay_percent / 100,
        "，Boss ", config.allow_heavy_targets and "参与" or "跳过",
        "，雕像怪 ", config.allow_statue_targets and "参与" or "跳过")
end

local function cleanup()
    for index = #hooks, 1, -1 do
        pcall(function()
            hooks[index]:remove()
        end)
        hooks[index] = nil
    end
    in_chain = false
    protected_items = {}
end

mod.cleanup = cleanup
todo_list = { "setup" }
