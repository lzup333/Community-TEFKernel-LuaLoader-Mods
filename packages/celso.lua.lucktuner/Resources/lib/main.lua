-- LuckTunerLua: adds a configurable bonus to Terraria.Player.luck.
mod.meta = { pkg_id = "celso.lua.lucktuner", version = "1.0.2" }

local patch = mod.patch
local hooks = {}
local player_type
local luck_field
local update_luck_method
local bonus_luck = 0

-- A weak-key table avoids keeping player objects alive after they are released.
local last_written = setmetatable({}, { __mode = "k" })
local last_bonus = setmetatable({}, { __mode = "k" })

local function read_config()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" then
        mod.info("未找到 TEFManager 配置，使用原版幸运值")
        bonus_luck = 0
        return
    end

    -- TEFManager stores setting values under {"values": {...}}. Matching the
    -- key in the complete JSON text also tolerates the same value at top level.
    local value = tonumber(raw:match('"luck_bonus_hundredths"%s*:%s*(-?%d+)'))
    value = value or 0
    value = math.max(-100, math.min(100, math.floor(value + 0.5)))
    bonus_luck = value / 100.0
end

local function get_luck(player)
    local ok, value = pcall(patch.get_field_value, luck_field, player, "float")
    if ok then return tonumber(value) end
    return nil
end

local function set_luck(player, value)
    return pcall(patch.set_field_value, luck_field, player, value, "float")
end

local function update_luck_prefix(player)
    if not player then return false end
    local current = get_luck(player)
    local previous = last_written[player]
    if current and previous and math.abs(current - previous) < 0.0001 then
        -- Remove this mod's prior contribution before the game recalculates luck.
        set_luck(player, current - (last_bonus[player] or 0))
    end
    last_written[player] = nil
    last_bonus[player] = nil
    return false
end

local function update_luck_postfix(player)
    if not player then return end
    local base_luck = get_luck(player)
    if not base_luck then return end

    local adjusted_luck = base_luck + bonus_luck
    local ok, err = set_luck(player, adjusted_luck)
    if not ok then
        mod.warn("写入 Player.luck 失败: ", err)
        return
    end
    last_written[player] = adjusted_luck
    last_bonus[player] = bonus_luck
end

local function install_hook(type_handle, method_name, argc, prefix, postfix)
    if not type_handle then return nil end
    local method = patch.get_method(type_handle, method_name, argc)
    if not method then
        mod.warn("找不到方法，跳过钩子: ", method_name)
        return nil
    end

    local ok, hook = pcall(patch.install_hook, method, {
        prefix = prefix,
        postfix = postfix,
    })
    if not ok then
        mod.warn("安装钩子失败: ", method_name, " ", hook)
        return nil
    end
    hooks[#hooks + 1] = hook
    return method
end

function setup()
    read_config()

    player_type = patch.get_type("Terraria", "Player")
    if not player_type then
        mod.warn("找不到 Terraria.Player，幸运调节未启用")
        return
    end

    luck_field = patch.get_field(player_type, "luck")
    if not luck_field then
        mod.warn("找不到 Player.luck 字段，幸运调节未启用")
        return
    end

    update_luck_method = install_hook(
        player_type,
        "UpdateLuck",
        0,
        update_luck_prefix,
        update_luck_postfix
    )

    if update_luck_method then
        mod.info("幸运调节已加载：额外幸运值 ", bonus_luck)
    else
        mod.warn("Player.UpdateLuck() 钩子未安装")
    end
end

local function cleanup()
    -- Remove our current bonus immediately when the mod is disabled.
    for player, written in pairs(last_written) do
        local current = get_luck(player)
        local applied = last_bonus[player] or 0
        if current and math.abs(current - written) < 0.0001 then
            set_luck(player, current - applied)
        end
        last_written[player] = nil
        last_bonus[player] = nil
    end

    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
end

mod.cleanup = cleanup
todo_list = { "setup" }
