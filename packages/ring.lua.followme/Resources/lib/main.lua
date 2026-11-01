-- BulletTracker / main.lua
-- v1.3.1.6
-- 改动：
--   1. speed_multiplier 界面输入值 -1 后才是实际倍率（UI=0/1 均视为不覆写）
--   2. 倍率上限放宽到 131400%
--   3. 新增 speed_override_enable 开关

mod.meta = { pkg_id = "ring.lua.followme", version = "1.3.1.6" }

local patch = mod.patch

-- ========== 顶层：只声明，不调 API ==========
local T_Entity, T_Projectile, T_NPC, T_Main
local F_velocity, F_position, F_width, F_height
local F_p_active, F_p_friendly, F_p_npcProj, F_p_aiStyle, F_p_type
local F_n_active, F_n_chaseable, F_n_friendly
local F_main_npc
local M_p_update
local bullet_hook

local Main_npc_arr
local type_cache = {}
local npc_pos_x, npc_pos_y

local AI_GRAPPLE = 7

local FAST_READ_SIZE = 0xA5
local OFF_VELOCITY   = 0x08
local OFF_WIDTH      = 0x28
local OFF_HEIGHT     = 0x2C
local OFF_ACTIVE     = 0x35
local OFF_TYPE       = 0x50
local OFF_AISTYLE    = 0x84
local OFF_FRIENDLY   = 0xA4

local run_fastpath_check
local write_status

local cfg = {
    enable_tracking           = true,
    target_switch_cooldown    = 30,
    max_turn_angle            = 15,
    turn_cooldown             = 1,
    max_tracking_distance     = 1200,
    max_track_d2              = 1200 * 1200,
    npc_list_refresh_interval = 10,
    use_cached_target_pos     = false,
    speed_override_enable     = true,
    speed_multiplier          = 100,   -- 实际倍率（UI 值 -1 后）
    speed_override_interval   = 1,
    process_every_n_frame     = 20,
    adaptive_frame_skip       = true,
    adaptive_unit             = 200,
    max_checks_per_frame      = 1000,
    use_c_fastpath            = true,
}

local frame_id = 0
local last_proj_idx = 1e9
local frame_callbacks = 0
local last_frame_callbacks = 0
local current_N = 1
local checks_this_frame = 0
local last_status_write_frame = 0

local npc_count = 0
local npc_idx   = {}
local npc_x     = {}
local npc_y     = {}
local npc_last_refresh = -1e9
local proj_state = {}
local stat_tracked  = 0
local stat_switched = 0
local stat_fast_hit = 0
local stat_fast_miss = 0

local fastpath_check_result = "not_run"
local fastpath_calls = 0
local fastpath_check_done = false

-- ========== 配置读取 ==========
local function read_config()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" then
        mod.info("BulletTracker: 无 config.json，使用内置默认")
    else
        local function gi(key, default)
            local v = raw:match('"' .. key .. '"%s*:%s*(-?%d+)')
            return v and tonumber(v) or default
        end
        local function gb(key, default)
            local v = raw:match('"' .. key .. '"%s*:%s*(%a+)')
            if v == "true"  then return true  end
            if v == "false" then return false end
            return default
        end

        cfg.enable_tracking           = gb("enable_tracking",           cfg.enable_tracking)
        cfg.target_switch_cooldown    = gi("target_switch_cooldown",    cfg.target_switch_cooldown)
        cfg.max_turn_angle            = gi("max_turn_angle",            cfg.max_turn_angle)
        cfg.turn_cooldown             = gi("turn_cooldown",             cfg.turn_cooldown)
        cfg.max_tracking_distance     = gi("max_tracking_distance",     cfg.max_tracking_distance)
        cfg.npc_list_refresh_interval = gi("npc_list_refresh_interval", cfg.npc_list_refresh_interval)
        cfg.use_cached_target_pos     = gb("use_cached_target_pos",     cfg.use_cached_target_pos)
        cfg.speed_override_enable     = gb("speed_override_enable",     cfg.speed_override_enable)
        cfg.speed_multiplier          = gi("speed_multiplier",          cfg.speed_multiplier + 1)
        cfg.speed_override_interval   = gi("speed_override_interval",   cfg.speed_override_interval)
        cfg.process_every_n_frame     = gi("process_every_n_frame",     cfg.process_every_n_frame)
        cfg.adaptive_frame_skip       = gb("adaptive_frame_skip",       cfg.adaptive_frame_skip)
        cfg.adaptive_unit             = gi("adaptive_unit",             cfg.adaptive_unit)
        cfg.max_checks_per_frame      = gi("max_checks_per_frame",      cfg.max_checks_per_frame)
        cfg.use_c_fastpath            = gb("use_c_fastpath",            cfg.use_c_fastpath)

        -- 速度覆写：输入值减 1 才是实际倍率
        cfg.speed_multiplier = cfg.speed_multiplier - 1
    end

    -- 夹取
    if cfg.target_switch_cooldown    < 1     then cfg.target_switch_cooldown = 1 end
    if cfg.turn_cooldown             < 0     then cfg.turn_cooldown = 0 end
    if cfg.max_turn_angle            < 0     then cfg.max_turn_angle = 0 end
    if cfg.max_turn_angle           > 180    then cfg.max_turn_angle = 180 end
    if cfg.max_tracking_distance     < 1     then cfg.max_tracking_distance = 1 end
    if cfg.npc_list_refresh_interval < 1     then cfg.npc_list_refresh_interval = 1 end
    if cfg.speed_multiplier          < 0     then cfg.speed_multiplier = 0 end
    if cfg.speed_multiplier         > 131400 then cfg.speed_multiplier = 131400 end
    if cfg.speed_override_interval   < 1     then cfg.speed_override_interval = 1 end
    if cfg.speed_override_interval   > 120   then cfg.speed_override_interval = 120 end
    if cfg.process_every_n_frame     < 1     then cfg.process_every_n_frame = 1 end
    if cfg.process_every_n_frame     > 20    then cfg.process_every_n_frame = 20 end
    if cfg.adaptive_unit             < 1     then cfg.adaptive_unit = 1 end
    if cfg.max_checks_per_frame      < 1     then cfg.max_checks_per_frame = 1 end

    cfg.max_track_d2 = cfg.max_tracking_distance * cfg.max_tracking_distance
end

local function get_npc_arr()
    if Main_npc_arr then return Main_npc_arr end
    return patch.get_field_value(F_main_npc, nil, "object")
end

-- ========== 快 / 慢通道 ==========
local function fast_read(instance)
    if not cfg.use_c_fastpath then return nil end
    if not patch.field_pointer then return nil end

    local ptr = patch.field_pointer(F_position, instance)
    if not ptr then return nil end

    local raw = patch.mem_read(ptr, 0, FAST_READ_SIZE)
    if not raw or #raw < FAST_READ_SIZE then return nil end

    local pos_x, pos_y = string.unpack("<ff", raw, 1)
    local vel_x, vel_y = string.unpack("<ff", raw, OFF_VELOCITY + 1)
    local w   = string.unpack("<i4", raw, OFF_WIDTH + 1)
    local h   = string.unpack("<i4", raw, OFF_HEIGHT + 1)
    local act = string.byte(raw, OFF_ACTIVE + 1) ~= 0
    local typ = string.unpack("<i4", raw, OFF_TYPE + 1)
    local ais = string.unpack("<i4", raw, OFF_AISTYLE + 1)
    local fri = string.byte(raw, OFF_FRIENDLY + 1) ~= 0

    fastpath_calls = fastpath_calls + 1
    return pos_x, pos_y, vel_x, vel_y, w, h, act, typ, ais, fri
end

local function slow_read(instance)
    local pos_x, pos_y = patch.get_field_vec2(F_position, instance)
    local vel_x, vel_y = patch.get_field_vec2(F_velocity, instance)
    local w = patch.get_field_value(F_width, instance, "int32") or 0
    local h = patch.get_field_value(F_height, instance, "int32") or 0
    local act = patch.get_field_value(F_p_active, instance, "bool") or false
    local typ = patch.get_field_value(F_p_type, instance, "int32") or 0
    local ais = F_p_aiStyle and patch.get_field_value(F_p_aiStyle, instance, "int32") or -1
    local fri = patch.get_field_value(F_p_friendly, instance, "bool") or false
    return pos_x, pos_y, vel_x, vel_y, w, h, act, typ, ais, fri
end

local function is_npc_proj(instance, tc)
    if tc.npcProj == nil then
        tc.npcProj = patch.get_field_value(F_p_npcProj, instance, "bool") or false
        if tc.npcProj then tc.excluded = true end
    end
    return tc.npcProj
end

local function npc_center(npc)
    local px, py = patch.get_field_vec2(F_position, npc)
    local w = patch.get_field_value(F_width,  npc, "int32") or 0
    local h = patch.get_field_value(F_height, npc, "int32") or 0
    return px + w * 0.5, py + h * 0.5
end

local function refresh_npc_candidates()
    local arr = get_npc_arr()
    if not arr then npc_count = 0; return end
    local n = patch.array_length(arr)
    if type(n) ~= "number" or n <= 0 then npc_count = 0; return end

    local count = 0
    local new_x, new_y = {}, {}
    for i = 0, n - 1 do
        local npc = patch.array_at(arr, i)
        if npc
           and patch.get_field_value(F_n_active, npc, "bool")
           and not patch.get_field_value(F_n_friendly, npc, "bool")
           and patch.get_field_value(F_n_chaseable, npc, "bool") then
            local nx, ny = npc_center(npc)
            if nx == nx and ny == ny then
                count = count + 1
                npc_idx[count] = i
                npc_x[count]   = nx
                npc_y[count]   = ny
                new_x[i] = nx
                new_y[i] = ny
            end
        end
    end
    for k = count + 1, npc_count do
        npc_idx[k] = nil
        npc_x[k]   = nil
        npc_y[k]   = nil
    end
    npc_count = count
    npc_last_refresh = frame_id
    npc_pos_x, npc_pos_y = new_x, new_y
end

local function pick_target(ref_x, ref_y)
    if npc_count == 0 then return nil, nil end
    local best_idx, best_d2 = nil, math.huge
    for k = 1, npc_count do
        local dx = npc_x[k] - ref_x
        local dy = npc_y[k] - ref_y
        local d2 = dx * dx + dy * dy
        if d2 < best_d2 then
            best_d2 = d2
            best_idx = npc_idx[k]
        end
    end
    return best_idx, best_d2
end

local function steer(vx, vy, dx, dy, max_rad)
    local speed2 = vx * vx + vy * vy
    if speed2 == 0 then return vx, vy end
    if dx * dx + dy * dy == 0 then return vx, vy end

    local cur = math.atan(vy, vx)
    local tgt = math.atan(dy, dx)
    local delta = tgt - cur
    if delta >  math.pi then delta = delta - 2 * math.pi end
    if delta < -math.pi then delta = delta + 2 * math.pi end
    local turn = delta
    if math.abs(delta) > max_rad then
        turn = (delta > 0) and max_rad or -max_rad
    end
    local a = cur + turn
    local speed = math.sqrt(speed2)
    return math.cos(a) * speed, math.sin(a) * speed
end

-- ========== 单个弹幕处理 ==========
local function process_one(instance, proj_idx)
    local pos_x, pos_y, vx, vy, w, h, active, ptype, aiStyle, friendly
        = fast_read(instance)
    if pos_x == nil then
        stat_fast_miss = stat_fast_miss + 1
        pos_x, pos_y, vx, vy, w, h, active, ptype, aiStyle, friendly
            = slow_read(instance)
    else
        stat_fast_hit = stat_fast_hit + 1
    end

    -- 廉价过滤
    if not active then return end
    if not friendly then return end
    if aiStyle == AI_GRAPPLE then return end
    if vx == 0 and vy == 0 then return end

    local tc = type_cache[ptype]
    if not tc then
        tc = { w = w, h = h, excluded = false }
        type_cache[ptype] = tc
    end
    if not tc.excluded then
        if is_npc_proj(instance, tc) then return end
    else
        return
    end

    local px = pos_x + tc.w * 0.5
    local py = pos_y + tc.h * 0.5

    local st = proj_state[proj_idx]
    if st and st.proj_type ~= ptype then st = nil end
    if not st then
        st = {
            target = nil,
            last_switch = -1e9,
            last_turn = -1e9,
            last_speed_override = -1e9,
            proj_type = ptype,
            base_speed = nil,
        }
        proj_state[proj_idx] = st
    end

    if not st.base_speed then
        st.base_speed = math.sqrt(vx * vx + vy * vy)
    end

    -- ===== 目标选择 =====
    local need_reselect = false
    if st.target then
        local arr = get_npc_arr()
        local npc = arr and patch.array_at(arr, st.target)
        if not npc
           or not patch.get_field_value(F_n_active, npc, "bool") then
            st.target = nil
            need_reselect = true
        end
    else
        need_reselect = true
    end
    if frame_id - st.last_switch >= cfg.target_switch_cooldown then
        need_reselect = true
    end

    if need_reselect then
        local new_t, d2 = pick_target(px, py)
        if new_t and d2 and d2 <= cfg.max_track_d2 then
            if new_t ~= st.target then
                stat_switched = stat_switched + 1
            end
            st.target      = new_t
            st.last_switch = frame_id
        elseif new_t == nil then
            st.target = nil
        end
    end

    -- ===== 合并计算新速度：转向 + 速度覆写，最后一次写 =====
    local nvx, nvy = vx, vy
    local changed = false

    -- 转向
    if st.target and frame_id - st.last_turn >= cfg.turn_cooldown then
        local nx, ny
        if cfg.use_cached_target_pos then
            nx = npc_pos_x and npc_pos_x[st.target]
            ny = npc_pos_y and npc_pos_y[st.target]
        end
        if not nx then
            local arr = get_npc_arr()
            local npc = arr and patch.array_at(arr, st.target)
            if npc then
                nx, ny = npc_center(npc)
            else
                st.target = nil
            end
        end
        if nx then
            local dx, dy = nx - px, ny - py
            local d2 = dx * dx + dy * dy
            if d2 <= cfg.max_track_d2 then
                local max_rad = cfg.max_turn_angle * math.pi / 180
                local tvx, tvy = steer(nvx, nvy, dx, dy, max_rad)
                if tvx ~= nvx or tvy ~= nvy then
                    nvx, nvy = tvx, tvy
                    st.last_turn = frame_id
                    stat_tracked = stat_tracked + 1
                    changed = true
                end
            end
        end
    end

    -- 速度覆写（独立开关 + 独立冷却）
    if cfg.speed_override_enable
       and cfg.speed_multiplier > 0
       and cfg.speed_multiplier ~= 100
       and frame_id - st.last_speed_override >= cfg.speed_override_interval then
        local cur_speed = math.sqrt(nvx * nvx + nvy * nvy)
        if cur_speed > 0 and st.base_speed and st.base_speed > 0 then
            local target_speed = st.base_speed * cfg.speed_multiplier / 100
            local factor = target_speed / cur_speed
            nvx = nvx * factor
            nvy = nvy * factor
            st.last_speed_override = frame_id
            changed = true
        end
    end

    if changed then
        patch.set_field_vec2(F_velocity, instance, nvx, nvy)
    end
end

-- ========== Hook 回调 ==========
local function on_projectile_update(instance, args)
    if not fastpath_check_done then
        fastpath_check_done = true
        local borrow = patch.get_field_value(F_main_npc, nil, "object")
        if borrow and not Main_npc_arr then
            local ok_r, retained = pcall(patch.retain, borrow)
            if ok_r and retained then Main_npc_arr = retained end
        end
        pcall(run_fastpath_check)
        pcall(write_status)
    end

    local proj_idx = args and args[1]
    if type(proj_idx) ~= "number" then return end

    if proj_idx < last_proj_idx then
        frame_id = frame_id + 1
        checks_this_frame = 0

        last_frame_callbacks = frame_callbacks
        frame_callbacks = 0

        if cfg.adaptive_frame_skip and cfg.process_every_n_frame > 1 then
            local n = math.ceil(last_frame_callbacks / cfg.adaptive_unit)
            if n < 1 then n = 1 end
            if n > cfg.process_every_n_frame then n = cfg.process_every_n_frame end
            current_N = n
        else
            current_N = cfg.process_every_n_frame
        end

        if frame_id - npc_last_refresh >= cfg.npc_list_refresh_interval then
            pcall(refresh_npc_candidates)
        end

        if frame_id - last_status_write_frame >= 600 then
            last_status_write_frame = frame_id
            pcall(write_status)
        end
    end
    last_proj_idx = proj_idx
    frame_callbacks = frame_callbacks + 1

    if not cfg.enable_tracking then return end

    local N = current_N
    if N > 1 and proj_idx % N ~= frame_id % N then return end

    if checks_this_frame >= cfg.max_checks_per_frame then return end
    checks_this_frame = checks_this_frame + 1

    local ok, err = pcall(process_one, instance, proj_idx)
    if not ok then
        mod.error("BulletTracker on_update: " .. tostring(err))
    end
end

-- ========== 快慢通道一致性校验 ==========
run_fastpath_check = function()
    if not cfg.use_c_fastpath then
        fastpath_check_result = "disabled"
        return
    end
    if not patch.field_pointer then
        fastpath_check_result = "no_field_pointer_api"
        return
    end

    local arr = get_npc_arr()
    if not arr then
        fastpath_check_result = "no_npc_arr"
        return
    end

    local n = patch.array_length(arr)
    if type(n) ~= "number" or n <= 0 then
        fastpath_check_result = "empty_npc_arr"
        return
    end

    for i = 0, n - 1 do
        local npc = patch.array_at(arr, i)
        if npc and patch.get_field_value(F_n_active, npc, "bool") then
            local ptr = patch.field_pointer(F_position, npc)
            if not ptr then
                fastpath_check_result = "field_pointer_nil"
                return
            end
            local raw = patch.mem_read(ptr, 0, 0x30)
            if not raw or #raw < 0x30 then
                fastpath_check_result = "mem_read_short"
                return
            end
            local fp_x, fp_y = string.unpack("<ff", raw, 1)
            local fv_x, fv_y = string.unpack("<ff", raw, 0x08 + 1)
            local fw = string.unpack("<i4", raw, 0x28 + 1)
            local fh = string.unpack("<i4", raw, 0x2C + 1)

            local sp_x, sp_y = patch.get_field_vec2(F_position, npc)
            local sv_x, sv_y = patch.get_field_vec2(F_velocity, npc)
            local sw = patch.get_field_value(F_width, npc, "int32") or 0
            local sh = patch.get_field_value(F_height, npc, "int32") or 0

            local dx = math.abs(fp_x - sp_x) + math.abs(fp_y - sp_y)
                     + math.abs(fv_x - sv_x) + math.abs(fv_y - sv_y)
                     + math.abs(fw - sw) + math.abs(fh - sh)

            if dx < 0.001 then
                fastpath_check_result = "OK"
            else
                fastpath_check_result = ("MISMATCH dx=%.4f"):format(dx)
            end
            return
        end
    end
    fastpath_check_result = "no_active_npc"
end

-- ========== 状态落盘 ==========
write_status = function()
    local s = {}
    local function W(x) s[#s + 1] = tostring(x) end
    W("=== BulletTracker status ===")
    W("version=1.3.1.6")
    W("platform="    .. tostring(mod.platform) .. " arch=" .. tostring(mod.arch))
    W("private_dir=" .. tostring(mod.private_dir))
    W("Main_npc_arr=" .. tostring(Main_npc_arr ~= nil))
    W("M_p_update="   .. tostring(M_p_update ~= nil))
    W("hook="         .. tostring(bullet_hook ~= nil))
    W("AI_GRAPPLE="   .. tostring(AI_GRAPPLE))
    W("fastpath_check=" .. tostring(fastpath_check_result))
    W("fastpath_calls=" .. tostring(fastpath_calls))
    W("stat_fast_hit="  .. tostring(stat_fast_hit))
    W("stat_fast_miss=" .. tostring(stat_fast_miss))
    W("stat_tracked="   .. tostring(stat_tracked))
    W("stat_switched="  .. tostring(stat_switched))
    W("frame_id="       .. tostring(frame_id))
    W("npc_count="      .. tostring(npc_count))
    W("cfg.enable_tracking="           .. tostring(cfg.enable_tracking))
    W("cfg.target_switch_cooldown="    .. tostring(cfg.target_switch_cooldown))
    W("cfg.max_turn_angle="            .. tostring(cfg.max_turn_angle))
    W("cfg.turn_cooldown="             .. tostring(cfg.turn_cooldown))
    W("cfg.max_tracking_distance="     .. tostring(cfg.max_tracking_distance))
    W("cfg.npc_list_refresh_interval=" .. tostring(cfg.npc_list_refresh_interval))
    W("cfg.use_cached_target_pos="     .. tostring(cfg.use_cached_target_pos))
    W("cfg.speed_override_enable="     .. tostring(cfg.speed_override_enable))
    W("cfg.speed_multiplier="          .. tostring(cfg.speed_multiplier) .. " (actual, UI-1)")
    W("cfg.speed_override_interval="   .. tostring(cfg.speed_override_interval))
    W("cfg.process_every_n_frame="     .. tostring(cfg.process_every_n_frame))
    W("cfg.adaptive_frame_skip="       .. tostring(cfg.adaptive_frame_skip))
    W("cfg.adaptive_unit="             .. tostring(cfg.adaptive_unit))
    W("cfg.max_checks_per_frame="      .. tostring(cfg.max_checks_per_frame))
    W("cfg.use_c_fastpath="            .. tostring(cfg.use_c_fastpath))
    pcall(mod.write_file, "status.txt", table.concat(s, "\n"))
end

-- ========== setup ==========
function setup()
    read_config()

    T_Entity     = patch.get_type("Terraria", "Entity")
    T_Projectile = patch.get_type("Terraria", "Projectile")
    T_NPC        = patch.get_type("Terraria", "NPC")
    T_Main       = patch.get_type("Terraria", "Main")
    if not (T_Entity and T_Projectile and T_NPC and T_Main) then
        mod.error("BulletTracker: 类型查找失败")
        write_status()
        return
    end

    F_velocity = patch.get_field(T_Entity, "velocity")
    F_position = patch.get_field(T_Entity, "position")
    F_width    = patch.get_field(T_Entity, "width")
    F_height   = patch.get_field(T_Entity, "height")

    F_p_active   = patch.get_field(T_Projectile, "active")
    F_p_friendly = patch.get_field(T_Projectile, "friendly")
    F_p_npcProj  = patch.get_field(T_Projectile, "npcProj")
    F_p_aiStyle  = patch.get_field(T_Projectile, "aiStyle")
    F_p_type     = patch.get_field(T_Projectile, "type")

    F_n_active    = patch.get_field(T_NPC, "active")
    F_n_chaseable = patch.get_field(T_NPC, "chaseable")
    F_n_friendly  = patch.get_field(T_NPC, "friendly")

    F_main_npc = patch.get_field(T_Main, "npc")

    if not (F_velocity and F_position and F_width and F_height
            and F_p_active and F_p_friendly and F_p_type and F_main_npc
            and F_n_friendly) then
        mod.error("BulletTracker: 关键字段查找失败")
        write_status()
        return
    end

    local ok_retain, arr = pcall(function()
        local borrow = patch.get_field_value(F_main_npc, nil, "object")
        if not borrow then return nil end
        return patch.retain(borrow)
    end)
    if ok_retain and arr then
        Main_npc_arr = arr
    end

    M_p_update = patch.get_method(T_Projectile, "Update", 1)
    if not M_p_update then
        mod.error("BulletTracker: Projectile.Update(int) 未找到")
        write_status()
        return
    end

    local ok, hook = pcall(patch.install_hook, M_p_update,
        { postfix = on_projectile_update })
    if not ok or not hook then
        mod.error("BulletTracker: install_hook 失败: " .. tostring(hook))
        write_status()
        return
    end
    bullet_hook = hook

    write_status()
    mod.info("BulletTracker loaded")
end

-- ========== cleanup ==========
local function cleanup()
    if bullet_hook then
        pcall(function() bullet_hook:remove() end)
        bullet_hook = nil
    end
    proj_state = {}
    npc_idx, npc_x, npc_y = {}, {}, {}
    type_cache = {}
    npc_pos_x, npc_pos_y = nil, nil
    Main_npc_arr = nil
    npc_count = 0
    mod.info("BulletTracker unloaded")
end

mod.cleanup = cleanup
todo_list  = { "setup" }