mod.meta = { pkg_id = "lua.qing.motionplus", version = "1.2.5", version_code = 125, api_version = 1 }
local P = mod.patch
local f
local g_log_h = nil
local function wlog(s)
    pcall(function()
        if not g_log_h then g_log_h = io.open("/sdcard/Download/mp16.log", "a") end
        if g_log_h then g_log_h:write(os.date("%H:%M:%S") .. " " .. tostring(s) .. "\n"); g_log_h:flush() end
    end)
end
local function T(x) return tostring(x) end

-- ===== 状态 =====
local PI = 3.14159265
local MAX_DEG = 60.0
local K_TILT, K_SMOOTH, MAX_STATIC, MAX_TILT = 0.05, 0.45, 0.2618, 0.5236
local K_RETURN = 0.05

local g_rot, g_slime_rot, g_zomb_rot, g_zomb_tgt = 0.0, 0.0, 0.0, 0.0
local g_hr = 0.0
local g_lastX, g_lastY, g_inited = 0.0, 0.0, false
local g_idle_cnt, g_move_cnt, g_using = 0, 0, 0
local g_last_mx, g_last_my, g_mouse_inited = 0, 0, false
local g_rope_hr, g_beyond = 0.0, 0
local g_look_on, g_look_retarget, g_look_wait, g_look_timer = 0, 1, 0, 0
local g_look_world, g_look_hold, g_look_rate = 0.0, 0.0, 0.0
local g_rng = 98765
-- emote
local g_emote_m = nil
local g_emote_cnt = 0
local g_emote_next = 0
local EMOTE_POOL = {0,1,2,3,15,16,17,87,88,89,91,92,93,94,134,135,136,137,138,139}
local g_emote_rng = 24680
local g_idle_3s, g_idle_10s, g_idle_15s = 180, 600, 900
local g_fps_log = 0
local g_idle_secs = 0.0
local g_idle_since = -1
local g_hooks = {}
-- ===== Emote（待机随机表情）=====
local function emote_send()
    if not g_emote_m then return end
    g_emote_rng = (g_emote_rng * 1103515245 + 12345) % 2147483648
    local idx = (math.floor(g_emote_rng / 4096) % #EMOTE_POOL) + 1
    local eid = math.floor(EMOTE_POOL[idx])
    pcall(function() P.invoke(g_emote_m, eid) end)
    wlog("EMOTE send id=" .. tostring(eid))
end

local g_emote_armed = 0
local function emote_step()
    -- 未达标：清空
    if g_idle_secs < 10.0 or g_using ~= 0 then
        g_emote_armed = 0
        g_emote_next = 0
        return
    end
    if not g_emote_m then return end
    -- 刚满 10 秒：立刻发第 1 个
    if g_emote_armed == 0 then
        g_emote_armed = 1
        emote_send()
        g_emote_rng = (g_emote_rng * 1103515245 + 12345) % 2147483648
        g_emote_next = 300 + (math.floor(g_emote_rng / 65536) % 601)
        return
    end
    g_emote_next = g_emote_next - 1
    if g_emote_next > 0 then return end
    emote_send()
    g_emote_rng = (g_emote_rng * 1103515245 + 12345) % 2147483648
    g_emote_next = 300 + (math.floor(g_emote_rng / 65536) % 601)
end


-- ===== 句柄 =====
local F_dp, F_hr, F_dir, F_pos, F_vel, F_fr, F_fo, F_sit, F_w, F_h, F_pulley, F_ani
local F_mount, F_mtype
local g_mt_log, g_mt_last = 0, -999
local M_mx, M_my, M_sw, M_sh, M_gm, F_fps
local F_frame
local g_last_frame = -1
local g_dup = 0
local N_rot, N_vel, N_ai

local function invM(m)
    if not m then return 0 end
    local r = P.invoke(m, nil)
    if r == nil then return 0 end
    return r
end

-- ===== NPC postfix =====
local g_npc_n = 0
local function npc_post(inst, args, result)
    g_npc_n = g_npc_n + 1
    if g_npc_n <= 3 then wlog("npc_post called #" .. g_npc_n .. " inst=" .. tostring(inst)) end
    pcall(function()
        if not inst or not N_rot then return end
        local ai = P.get_field_value(N_ai, inst, "int32") or -1
        if ai == 1 then
            local vx = P.get_field_vec2(N_vel, inst)
            if not vx then return end
            local tgt = vx * 0.75
            if tgt > 0.5236 then tgt = 0.5236 elseif tgt < -0.5236 then tgt = -0.5236 end
            g_slime_rot = g_slime_rot + (tgt - g_slime_rot) * 0.45
            P.set_field_value(N_rot, inst, g_slime_rot, "float")
        elseif ai == 3 then
            local vx = P.get_field_vec2(N_vel, inst)
            if not vx then return end
            local tgt = vx * 0.50
            if tgt > 0.3491 then tgt = 0.3491 elseif tgt < -0.3491 then tgt = -0.3491 end
            if tgt > g_zomb_tgt + 0.06 or tgt < g_zomb_tgt - 0.06 then g_zomb_tgt = tgt end
            g_zomb_rot = g_zomb_rot + (g_zomb_tgt - g_zomb_rot) * 0.12
            P.set_field_value(N_rot, inst, g_zomb_rot, "float")
        end
    end)
end

-- ===== Player Update postfix（写 fullRotation）=====
local g_upd_n = 0
local g_last_frame2 = -1
local function upd_post(inst, args, result)
    g_upd_n = g_upd_n + 1
    if g_upd_n <= 3 then wlog("upd_post called #" .. g_upd_n) end
    local okk, ee = pcall(function()
        if not inst then return end
        -- 菜单
        local gm = invM(M_gm)
        if g_upd_n <= 3 then wlog("  upd_post gm=" .. tostring(gm)) end
        if gm == true then return end
        pcall(emote_step)
        -- 躺床
        local fr = P.get_field_value(F_fr, inst, "float")
        local lying = false
        local sp = P.get_field_value(F_sit, inst, "bool")
        if sp then lying = true end
        if fr and (fr > 1.0 or fr < -1.0) then lying = true end
        -- 爬绳
        local on_rope = false
        local pu = P.get_field_value(F_pulley, inst, "bool")
        if pu then on_rope = true end
        -- 矿车
        local on_cart = false
        pcall(function()
            if F_mount and F_mtype then
                local mo = P.get_field_value(F_mount, inst, "object")
                if mo then
                    local mt = P.get_field_value(F_mtype, mo, "int32")
                    if mt then
                        if mt ~= g_mt_last and g_mt_log < 60 then
                            g_mt_log = g_mt_log + 1; g_mt_last = mt
                            wlog("MOUNT type=" .. T(mt))
                        end
                        if mt >= 7 and mt <= 40 then on_cart = true end
                    end
                end
            end
        end)
        if on_cart then lying = true end
        -- 位置/倾斜
        if not lying then
            local x, y = P.get_field_vec2(F_pos, inst)
            if x then
                if not g_inited then g_lastX, g_lastY, g_inited = x, y, true
                else
                    local dx = x - g_lastX
                    g_lastX, g_lastY = x, y
                    local target
                    if dx > 0.5 or dx < -0.5 then
                        target = dx * K_TILT; g_move_cnt = 10
                    elseif g_move_cnt > 0 then
                        g_move_cnt = g_move_cnt - 1; target = g_rot
                    else
                        local mx = invM(M_mx); local sw = invM(M_sw)
                        local cx = sw * 0.5
                        local r = 0.0
                        if cx > 0 then r = (mx - cx) / cx end
                        if r > 1 then r = 1 elseif r < -1 then r = -1 end
                        if g_idle_secs > 3.0 and g_using == 0 then target = 0.0
                        else target = -r * MAX_STATIC end
                    end
                    if target > MAX_TILT then target = MAX_TILT elseif target < -MAX_TILT then target = -MAX_TILT end
                    local ks = (target == 0.0) and K_RETURN or K_SMOOTH
                    g_rot = g_rot + (target - g_rot) * ks
                end
            end
        end
        -- 写 fullRotation
        if not lying then
            if on_rope then P.set_field_value(F_fr, inst, 0.0, "float")
            else P.set_field_value(F_fr, inst, g_rot, "float") end
            local w = P.get_field_value(F_w, inst, "int32") or 20
            local h = P.get_field_value(F_h, inst, "int32") or 42
            P.set_field_vec2(F_fo, inst, w * 0.5, h)
        end
        -- direction（爬绳不碰）
        if lying or on_rope or g_look_on == 1 then return end
        local mx = invM(M_mx); local sw = invM(M_sw)
        local nd = (mx > sw * 0.5) and 1 or -1
        local cd = P.get_field_value(F_dir, inst, "int32") or 1
        if nd ~= cd then P.set_field_value(F_dir, inst, nd, "int32") end
    end)
    if not okk and g_upd_n <= 3 then wlog("  upd_post ERR=" .. tostring(ee)) end
    if g_upd_n <= 3 then wlog("  upd_post done") end
end

-- ===== Player Update prefix（idle 计数）=====
local g_pre_calls = 0
local g_pre_t0 = 0
local function upd_pre(inst, args, result)
    g_pre_calls = g_pre_calls + 1
    if g_pre_t0 == 0 then g_pre_t0 = os.clock() end
    local el = os.clock() - g_pre_t0
    if el >= 2.0 then
        wlog("PRECALLS " .. g_pre_calls .. " in " .. string.format("%.2f", el) .. "s = " .. string.format("%.0f", g_pre_calls/el) .. "/s")
        g_pre_calls = 0
        g_pre_t0 = os.clock()
    end
    pcall(function()
        if not inst then return false end
        local gm = invM(M_gm)
        if gm and gm ~= 0 then return false end
        if F_fps then
            local fr = P.get_field_value(F_fps, nil, "int32")
            if fr and fr > 20 and fr < 400 then
                g_idle_3s = fr * 3
                g_idle_10s = fr * 10
                g_idle_15s = fr * 15
            end
        end
        local vx, vy = P.get_field_vec2(F_vel, inst)
        local moving = false
        if vx then
            if vx > 0.5 or vx < -0.5 or vy > 0.5 or vy < -0.5 then moving = true end
        end
        -- 准星移动检测：准星动也算"活跃"
        local mx0 = invM(M_mx); local my0 = invM(M_my)
        local mmoving = false
        if mx0 and mx0 > 0 then
            if not g_mouse_inited then g_last_mx, g_last_my, g_mouse_inited = mx0, my0, true
            else
                local ddx, ddy = mx0 - g_last_mx, my0 - g_last_my
                g_last_mx, g_last_my = mx0, my0
                if ddx ~= 0 or ddy ~= 0 then mmoving = true end
            end
        end
        if moving or mmoving then
            g_idle_cnt = 0
            g_idle_since = -1
        else
            if g_idle_since < 0 then g_idle_since = os.clock() end
            g_idle_secs = os.clock() - g_idle_since
            g_fps_log = g_fps_log + 1
            if g_fps_log % 200 == 1 then wlog("IDLE secs=" .. string.format("%.2f", g_idle_secs)) end
        end
        local a = P.get_field_value(F_ani, inst, "int32") or 0
        g_using = (a > 0) and 1 or 0
        if g_using == 1 then g_idle_cnt = 0 end
    end)
    return false
end

-- ===== Head 绘制 =====
local g_hd_n = 0
local g_last_frame3 = -1
local function head_prefix(inst, args)
    g_hd_n = g_hd_n + 1
    if g_hd_n <= 3 then wlog("head_prefix called #" .. g_hd_n .. " args1=" .. tostring(args and args[1])) end
    local okh, eh = pcall(function()
        if not args or not args[1] then return end
        local gm = invM(M_gm)
        if gm and gm ~= 0 then return end
        local ds = args[1]
        local dp = P.get_field_value(F_dp, ds, "object")
        if not dp then return end
        -- 排除人体模型
        local inan = P.get_field_value(F_inan, dp, "bool")
        if inan then return end
        local mx = invM(M_mx); local my = invM(M_my)
        local sw = invM(M_sw); local sh = invM(M_sh)
        local dir = P.get_field_value(F_dir, dp, "int32") or 1
        local dx = mx - sw * 0.5
        local dy = my - sh * 0.5
        local ang = math.atan(dy, dx)
        if dir == -1 then
            ang = ang - PI
            if ang < -PI then ang = ang + 2 * PI end
        end
        local a = ang
        if a > PI then a = a - 2 * PI elseif a < -PI then a = a + 2 * PI end
        local aa = (a < 0) and -a or a
        local limOn = 62.0 * PI / 180.0
        local limOff = 60.0 * PI / 180.0
        if aa > limOn then g_beyond = 1 elseif aa < limOff then g_beyond = 0 end
        local tgt
        if g_idle_secs > 15.0 and g_using == 0 then
            g_look_on = 1
            if g_look_retarget == 1 then
                g_look_retarget = 0
                g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                local rr = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                if rr < 0.5 then
                    g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                    local r2 = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                    g_look_world = (r2 * 2.0 - 1.0) * 40.0 * (PI / 180.0)
                else
                    g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                    local r2 = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                    local s = (r2 < 0.5) and 1.0 or -1.0
                    g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                    local r3 = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                    g_look_world = s * (140.0 + r3 * 40.0) * (PI / 180.0)
                end
                g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                g_look_timer = 90 + (math.floor(g_rng / 256) % 91)
                g_look_wait = 0
                g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                g_look_rate = 1.0 / (18.0 + (math.floor(g_rng / 64) % 19))
            end
            local base = (dir == -1) and PI or 0.0
            local rel = g_look_world - base
            if rel > PI then rel = rel - 2 * PI elseif rel < -PI then rel = rel + 2 * PI end
            if g_look_wait > 0 then
                g_look_wait = g_look_wait - 1
                tgt = g_look_hold
            elseif math.abs(rel) > PI * 0.5 then
                local w = g_look_world
                if w > PI then w = w - 2 * PI elseif w < -PI then w = w + 2 * PI end
                local nd2 = (w > -PI * 0.5 and w < PI * 0.5) and 1 or -1
                P.set_field_value(F_dir, dp, nd2, "int32")
                g_rope_hr = -g_rope_hr
                g_look_hold = g_rope_hr
                dir = nd2
                base = (dir == -1) and PI or 0.0
                rel = g_look_world - base
                if rel > PI then rel = rel - 2 * PI elseif rel < -PI then rel = rel + 2 * PI end
                g_look_wait = 18
                tgt = g_look_hold
            else
                g_look_hold = rel
                tgt = rel
            end
            if g_look_timer > 0 then
                g_look_timer = g_look_timer - 1
                if g_look_timer == 0 then g_look_retarget = 1 end
            end
        else
            g_look_on = 0
            g_look_retarget = 1
            tgt = (g_beyond == 1) and 0.0 or a
            if g_idle_secs > 3.0 and g_idle_secs <= 15.0 and g_move_cnt == 0 then tgt = 0.0 end
        end
        -- 绳上头限制
        local rope_h = false
        local rp = P.get_field_value(F_pulley, dp, "bool")
        if rp then rope_h = true end
        if rope_h then
            local same = (dir == 1) and (dx > 0) or (dx < 0)
            if not same then tgt = 0.0 end
        end
        -- 平滑
        local d = tgt - g_rope_hr
        if g_look_on == 1 and g_look_rate > 0 and g_look_wait == 0 then
            d = d * g_look_rate
        else
            if tgt == 0.0 then d = d * 0.1 else d = d * 0.3 end
        end
        g_rope_hr = g_rope_hr + d
        local out = g_rope_hr
        local lm = MAX_DEG * PI / 180.0
        if out > lm then out = lm elseif out < -lm then out = -lm end
        P.set_field_value(F_hr, dp, out, "float")
        if g_hd_n <= 3 then wlog("  head set ang=" .. string.format("%.3f", out)) end
    end)
    if not okh and g_hd_n <= 3 then wlog("  head ERR=" .. tostring(eh)) end
    return false
end

-- ===== setup =====
function setup()
    wlog("=== SETUP CALLED "..os.date("%H:%M:%S"))
    -- 卸载旧 hook（防重载叠加）
    for i, h in ipairs(g_hooks) do
        pcall(function() if h and h.remove then h:remove() end end)
    end
    g_hooks = {}
    wlog("=== motionplus lua v100 " .. os.date("%H:%M:%S") .. " plat=" .. tostring(mod.platform))
    local ok, err = pcall(function()
        local PLAYER = P.get_type("Terraria", "Player")
        local NPC = P.get_type("Terraria", "NPC")
        local M = P.get_type("Terraria", "Main")
        local DS = P.get_type("Terraria.DataStructures", "PlayerDrawSet")
        local L = P.get_type("Terraria.DataStructures", "PlayerDrawLayers")

        F_pos = P.get_field(PLAYER, "position")
        F_vel = P.get_field(PLAYER, "velocity")
        F_fr = P.get_field(PLAYER, "fullRotation")
        F_fo = P.get_field(PLAYER, "fullRotationOrigin")
        F_dir = P.get_field(PLAYER, "direction")
        F_hr = P.get_field(PLAYER, "headRotation")
        F_sit = P.get_field(PLAYER, "sitting")
        F_w = P.get_field(PLAYER, "width")
        F_h = P.get_field(PLAYER, "height")
        F_pulley = P.get_field(PLAYER, "pulley")
        F_ani = P.get_field(PLAYER, "itemAnimation")
        F_inan = P.get_field(PLAYER, "isDisplayDollOrInanimate")
        pcall(function()
            F_mount = P.get_field(PLAYER, "mount")
            local MNT = P.get_type("Terraria", "Mount")
            if MNT then F_mtype = P.get_field(MNT, "_type") end
            wlog("F_mount=" .. T(F_mount) .. " F_mtype=" .. T(F_mtype))
        end)

        N_rot = P.get_field(NPC, "rotation")
        N_vel = P.get_field(NPC, "velocity")
        N_ai = P.get_field(NPC, "aiStyle")

        M_mx = P.get_method(M, "get_mouseX")
        M_my = P.get_method(M, "get_mouseY")
        M_sw = P.get_method(M, "get_screenWidth")
        M_sh = P.get_method(M, "get_screenHeight")
        M_gm = P.get_method(M, "get_gameMenu")
        F_fps = P.get_field(M, "frameRate")
        pcall(function() F_frame = P.get_field(M, "updatesCountedForFPS") end)
        wlog("F_fps=" .. T(F_fps) .. " F_frame=" .. T(F_frame))

        F_dp = P.get_field(DS, "drawPlayer")

        local EB = P.get_type("Terraria.GameContent.UI", "EmoteBubble")
        if EB then
            g_emote_m = P.get_method(EB, "MakeLocalPlayerEmote", 1)
            wlog("emote_m=" .. T(g_emote_m))
        end

        wlog("pos=" .. T(F_pos) .. " fr=" .. T(F_fr) .. " hr=" .. T(F_hr) .. " vel=" .. T(F_vel))
        wlog("N.rot=" .. T(N_rot) .. " N.vel=" .. T(N_vel) .. " N.ai=" .. T(N_ai))
        wlog("dp=" .. T(F_dp) .. " gm=" .. T(M_gm) .. " mx=" .. T(M_mx))

        local mu = P.get_method(PLAYER, "Update", 1)
        local h1 = P.install_hook(mu, { prefix = upd_pre, postfix = upd_post })
        g_hooks[#g_hooks+1] = h1
        wlog("hook Update=" .. T(h1))

        local mh = P.get_method(L, "DrawPlayer_21_Head", 1)
        local h2 = P.install_hook(mh, { prefix = head_prefix })
        g_hooks[#g_hooks+1] = h2
        wlog("hook Head=" .. T(h2))

        local mu2 = P.get_method(NPC, "UpdateNPC", 1)
        local h3 = P.install_hook(mu2, { postfix = npc_post })
        g_hooks[#g_hooks+1] = h3
        wlog("hook UpdateNPC=" .. T(h3))
    end)
    wlog("=== setup " .. (ok and "OK" or ("ERR " .. T(err))))
end

todo_list = { "setup" }
