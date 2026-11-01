mod.meta = { pkg_id = "lua.example.dailymechants", version = "1.0.0" }

local patch = mod.patch

-- ============ 配置 ============
local CONFIG = {
    travel_enabled              = true,
    skeleton_enabled            = true,
    skeleton_require_cavern     = true,
    skeleton_scan_radius_tiles  = 120,
}
local CONFIG_REFRESH_SECONDS = 3
local last_config_check = -math.huge

local function load_config()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" then return end
    local function rb(key, fb)
        local v = raw:match('"' .. key .. '"%s*:%s*(%a+)')
        if v == "true" then return true end
        if v == "false" then return false end
        return fb
    end
    local function ri(key, fb, lo, hi)
        local v = tonumber(raw:match('"' .. key .. '"%s*:%s*(-?%d+)'))
        if not v then return fb end
        v = math.floor(v)
        if v < lo then v = lo end
        if v > hi then v = hi end
        return v
    end
    CONFIG.travel_enabled             = rb("travel_enabled", CONFIG.travel_enabled)
    CONFIG.skeleton_enabled           = rb("skeleton_enabled", CONFIG.skeleton_enabled)
    CONFIG.skeleton_require_cavern    = rb("skeleton_require_cavern", CONFIG.skeleton_require_cavern)
    CONFIG.skeleton_scan_radius_tiles = ri("skeleton_scan_radius_tiles",
                                           CONFIG.skeleton_scan_radius_tiles, 20, 500)
end

local function tick_config()
    local now = os.time and os.time() or os.clock()
    if now - last_config_check < CONFIG_REFRESH_SECONDS then return end
    last_config_check = now
    pcall(load_config)
end

-- ============ 常量 ============
local SKELETON_MERCHANT_TYPE  = 453   -- 骷髅商人 NPC ID
local SPAWN_OFFSET_TILES      = 20    -- 骷髅商人相对玩家偏移

-- ============ 句柄 ============
local T_Main, T_Player, T_NPC, T_Entity, T_WorldGen
local F_time, F_dayTime, F_rockLayer
local F_main_npc, F_main_player, F_main_myPlayer
local F_pos, F_width, F_height
local F_npc_active, F_npc_type, F_npc_position
local M_spawn_travel
local M_new_npc
local M_reset_effects
local M_get_myplayer

-- ============ 状态 ============
local prev_day = nil
local ready = false

-- ============ 通用工具 ============
local function find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local f = patch.get_field(cur, name)
        if f then return f end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function get_int(f, inst, d)
    if not f then return d end
    local v = patch.get_field_value(f, inst, "int32")
    if v == nil then return d end
    return v
end

local function get_bool(f, inst, d)
    if not f then return d end
    local v = patch.get_field_value(f, inst, "bool")
    if v == nil then return d end
    return v
end

local function get_vec2(f, inst)
    if not f then return nil, nil end
    local x, y = patch.get_field_vec2(f, inst)
    if type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
    return x, y
end

local function local_player()
    if not F_main_player or not F_main_myPlayer then return nil end
    local idx = patch.get_field_value(F_main_myPlayer, nil, "int32")
    if idx == nil and M_get_myplayer then
        local r = patch.invoke(M_get_myplayer)
        if type(r) == "number" then idx = r end
    end
    if not idx or idx < 0 then return nil end
    local arr = patch.get_field_value(F_main_player, nil, "object")
    if not arr then return nil end
    if idx >= patch.array_length(arr) then return nil end
    return patch.array_at(arr, idx)
end

local function safe_hook(method, spec, label)
    if not method then
        mod.error("安装钩子失败(" .. label .. ")：方法为空")
        return false
    end
    local ok, err = pcall(patch.install_hook, method, spec)
    if not ok then
        mod.error("安装钩子失败(" .. label .. ")：" .. tostring(err))
        return false
    end
    return true
end

-- ============ 旅行商人 ============
local function traveling_merchant_exists()
    local arr = patch.get_field_value(F_main_npc, nil, "object")
    if not arr then return false end
    local len = patch.array_length(arr)
    for i = 0, len - 1 do
        local npc = patch.array_at(arr, i)
        if npc and get_bool(F_npc_active, npc, false) then
            if get_int(F_npc_type, npc, -1) == 368 then
                return true
            end
        end
    end
    return false
end

local function handle_travel_merchant(player)
    if not CONFIG.travel_enabled then return end
    if not M_spawn_travel then return end
    if traveling_merchant_exists() then return end
    pcall(patch.invoke, M_spawn_travel)
end

-- ============ 骷髅商人 ============
local function is_in_cavern(player)
    if not CONFIG.skeleton_require_cavern then return true end
    if not F_rockLayer then return true end
    local rock = patch.get_field_value(F_rockLayer, nil, "double")
    if type(rock) ~= "number" then return true end
    local _, py = get_vec2(F_pos, player)
    if not py then return true end
    return (py / 16.0) > rock
end

local function has_skeleton_merchant_nearby(px, py)
    local arr = patch.get_field_value(F_main_npc, nil, "object")
    if not arr then return false end
    local len = patch.array_length(arr)
    local r = CONFIG.skeleton_scan_radius_tiles * 16
    local r2 = r * r
    for i = 0, len - 1 do
        local npc = patch.array_at(arr, i)
        if npc and get_bool(F_npc_active, npc, false) then
            if get_int(F_npc_type, npc, -1) == SKELETON_MERCHANT_TYPE then
                local nx, ny = get_vec2(F_npc_position, npc)
                if nx then
                    local dx, dy = nx - px, ny - py
                    if dx * dx + dy * dy <= r2 then return true end
                end
            end
        end
    end
    return false
end

local function spawn_skeleton_merchant(player)
    if not M_new_npc then return false end
    local px, py = get_vec2(F_pos, player)
    if not px then return false end
    local w = get_int(F_width, player, 20)
    local h = get_int(F_height, player, 42)
    local dir = (math.random(0, 1) == 0) and -1 or 1
    local sx = math.floor(px + w * 0.5 + dir * SPAWN_OFFSET_TILES * 16)
    local sy = math.floor(py + h * 0.5 - SPAWN_OFFSET_TILES * 16)
    local ok, r = pcall(patch.invoke, M_new_npc, nil,
        sx, sy, SKELETON_MERCHANT_TYPE, 0,
        0.0, 0.0, 0.0, 0.0, 255)
    return ok and type(r) == "number" and r >= 0
end

local function handle_skeleton_merchant(player)
    if not CONFIG.skeleton_enabled then return end
    if not is_in_cavern(player) then return end
    local px, py = get_vec2(F_pos, player)
    if not px then return end
    if has_skeleton_merchant_nearby(px, py) then return end
    spawn_skeleton_merchant(player)
end

-- ============ 黎明触发 ============
-- 只在“本地玩家”的 ResetEffects 上做事；其他玩家的 ResetEffects 也会触发，
-- 用 local_player() 过滤。
local function on_reset_effects(instance, args, result)
    if not ready or not instance then return end
    tick_config()

    local lp = local_player()
    if lp and lp ~= instance then return end

    local day = get_bool(F_dayTime, nil, false)
    if prev_day == nil then
        prev_day = day
        return
    end

    local is_dawn = (day == true and prev_day == false)
    prev_day = day
    if not is_dawn then return end

    -- 黎明瞬间：两个功能各检查一次
    if CONFIG.travel_enabled then
        pcall(handle_travel_merchant, instance)
    end
    if CONFIG.skeleton_enabled then
        pcall(handle_skeleton_merchant, instance)
    end
end

-- ============ 生命周期 ============
function setup()
    load_config()

    T_Main     = patch.get_type("Terraria", "Main")
    T_Player   = patch.get_type("Terraria", "Player")
    T_NPC      = patch.get_type("Terraria", "NPC")
    T_Entity   = patch.get_type("Terraria", "Entity")
    T_WorldGen = patch.get_type("Terraria", "WorldGen")
    if not T_Main or not T_Player or not T_NPC or not T_Entity or not T_WorldGen then
        mod.error("获取类型失败")
        return
    end

    F_time          = patch.get_field(T_Main, "time")
    F_dayTime       = patch.get_field(T_Main, "dayTime")
    F_rockLayer     = patch.get_field(T_Main, "rockLayer")
    F_main_npc      = patch.get_field(T_Main, "npc")
    F_main_player   = patch.get_field(T_Main, "player")
    F_main_myPlayer = patch.get_field(T_Main, "myPlayer")

    F_pos    = find_field(T_Entity, "position")
    F_width  = find_field(T_Entity, "width")
    F_height = find_field(T_Entity, "height")

    F_npc_active   = find_field(T_NPC, "active")
    F_npc_type     = find_field(T_NPC, "type")
    F_npc_position = find_field(T_Entity, "position")

    M_get_myplayer = patch.get_method(T_Main, "get_myPlayer", 0)
        or patch.get_method(T_Main, "get_myPlayer")

    M_spawn_travel = patch.get_method(T_WorldGen, "SpawnTravelNPC", 0)
        or patch.get_method(T_WorldGen, "SpawnTravelNPC")

    M_new_npc = patch.get_method(T_NPC, "NewNPC", 10)
        or patch.get_method(T_NPC, "NewNPC")

    M_reset_effects = patch.get_method(T_Player, "ResetEffects", 0)
        or patch.get_method(T_Player, "ResetEffects")

    if not F_dayTime or not F_main_npc or not F_npc_type
       or not F_npc_active or not F_pos or not F_rockLayer then
        mod.error("关键字段获取失败")
        return
    end
    if not M_spawn_travel then
        mod.warn("WorldGen.SpawnTravelNPC 获取失败，旅行商人功能不可用")
    end
    if not M_new_npc then
        mod.warn("NPC.NewNPC 获取失败，骷髅商人功能不可用")
    end
    if not M_reset_effects then
        mod.error("Player.ResetEffects 获取失败")
        return
    end

    if not safe_hook(M_reset_effects, { postfix = on_reset_effects }, "Player.ResetEffects") then
        return
    end

    prev_day = patch.get_field_value(F_dayTime, nil, "bool")
    ready = true
    mod.info("每日商人刷新已启用：旅行商人=%s 骷髅商人=%s",
        tostring(CONFIG.travel_enabled), tostring(CONFIG.skeleton_enabled))
end

todo_list = { "setup" }