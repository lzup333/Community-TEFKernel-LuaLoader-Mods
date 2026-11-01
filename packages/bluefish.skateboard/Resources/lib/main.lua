-- 我的滑板鞋 —— LuaLoader Lua Mod（v1.0.0）
-- 目标版本 1.4.5.8
-- 功能：每次攻击时，向移动方向（仅左右，不含上下）位移三格（48 像素）。
-- 实现：钩 Player.ItemCheck postfix，检测 itemAnimation 上升沿（0→>0 = 一次新攻击），
--       方向取 velocity.X 符号（移动方向，只看左右）；玩家静止时用 direction（面朝方向）兜底；
--       position 增减 48 像素写回（set_field_vec2，与合集死亡回溯/NPC瞬移同族安全写法）。
mod.meta = { pkg_id = "bluefish.skateboard", version = "1.0.2", version_code = 3, api_version = 1 }
local patch = mod.patch

local sk_setup, sk_cleanup
do
    local H = {}          -- 句柄缓存（可跨帧）
    local hook_h = nil
    local prev_anim = 0   -- 上一帧 itemAnimation（上升沿检测）

    -- ---- 进世界播报状态 ----
    local ANN_TEXT = "你的滑板鞋，在光滑的地板上摩擦"
    local ann_done = false      -- 是否已播报过
    local ann_frames = 0        -- 进世界后等待帧数
    local STEP = 96.0     -- 位移距离（像素）：6 格 × 16

    -- 每帧：是否在世界
    local function in_world()
        if not H.f_gamemenu then return true end
        local ok, v = pcall(patch.get_field_value, H.f_gamemenu, nil, "bool")
        if ok and v ~= nil then return (v == false) end
        return true
    end

    -- ---------- 发一条聊天/提示播报 ----------
    local function send_announce(text)
        if not (H.m_newtext5 or H.m_newtext4) then return false end
        local s = nil
        if patch.string_create then
            local okc, r = pcall(patch.string_create, text)
            if okc then s = r end
        end
        if not s then return false end
        if H.m_newtext5 then
            local okc, r = pcall(patch.invoke, H.m_newtext5, s, 140, 200, 255, false)
            if okc and r ~= false then return true end
        end
        if H.m_newtext4 then
            local okc, r = pcall(patch.invoke, H.m_newtext4, s, 140, 200, 255)
            if okc and r ~= false then return true end
        end
        return false
    end

    local function on_postfix(inst)
        if not inst then return end
        if not in_world() then
            prev_anim = 0
            return
        end

        -- ===== 进世界播报（延时 90 帧 ≈ 1.5 秒后发一次） =====
        if not ann_done then
            ann_frames = ann_frames + 1
            if ann_frames >= 90 then
                if send_announce(ANN_TEXT) then
                    ann_done = true
                else
                    ann_frames = 0   -- 发送失败则下轮重试
                end
            end
        end

        if not (H.f_anim and H.f_pos and H.f_vel and H.f_dir) then return end

        -- 1) itemAnimation 上升沿 = 一次新攻击
        local ok_a, anim = pcall(patch.get_field_value, H.f_anim, inst, "int32")
        if not ok_a or anim == nil then return end
        local fired = (prev_anim <= 0 and anim > 0)
        prev_anim = anim
        if not fired then return end

        -- 2) 方向：优先移动方向（velocity.X 符号，只看左右），静止则用面朝方向
        local dir = 0
        local ok_v, vx = pcall(patch.get_field_vec2, H.f_vel, inst)
        if ok_v and vx ~= nil and vx ~= 0.0 then
            dir = (vx > 0.0) and 1 or -1
        else
            local ok_d, d = pcall(patch.get_field_value, H.f_dir, inst, "int32")
            if ok_d and d ~= nil and d ~= 0 then
                dir = (d > 0) and 1 or -1
            end
        end
        if dir == 0 then return end

        -- 3) 位移：position.X 增减 STEP（y 不动，只左右）
        local ok_p, px, py = pcall(patch.get_field_vec2, H.f_pos, inst)
        if not ok_p or px == nil or py == nil then return end
        pcall(patch.set_field_vec2, H.f_pos, inst, px + dir * STEP, py)
    end

    sk_setup = function()
        local ok, err = pcall(function()
            local t_player = patch.get_type("Terraria", "Player")
            local t_main   = patch.get_type("Terraria", "Main")
            local t_int    = patch.get_basic_type("int32")
            local t_bool   = patch.get_basic_type("bool")
            if not (t_player and t_main and t_int and t_bool) then
                error("关键类型缺失")
            end

            H.f_anim     = patch.get_field(t_player, "itemAnimation")
            H.f_pos      = patch.get_field(t_player, "position")
            H.f_vel      = patch.get_field(t_player, "velocity")
            H.f_dir      = patch.get_field(t_player, "direction")
            H.f_gamemenu = patch.get_field(t_main, "gameMenu")

            -- 播报方法（NewText 5 参优先，4 参兜底）
            H.m_newtext5 = patch.get_method(t_main, "NewText", 5)
            H.m_newtext4 = patch.get_method(t_main, "NewText", 4)
            if not (H.f_anim and H.f_pos and H.f_vel and H.f_dir) then
                error("关键字段缺失")
            end

            local m_itemcheck = patch.get_method(t_player, "ItemCheck", 0)
            if not m_itemcheck then error("ItemCheck 方法未找到") end
            local okh, h = pcall(patch.install_hook, m_itemcheck, {
                postfix = on_postfix,
            })
            if not (okh and h) then
                error("ItemCheck 钩子安装失败: " .. tostring(h))
            end
            hook_h = h
        end)
        if not ok then
            mod.warn("[滑板鞋] 初始化失败: " .. tostring(err))
        end
    end

    sk_cleanup = function()
        if hook_h then pcall(function() hook_h:remove() end) hook_h = nil end
    end
end

function setup()
    pcall(sk_setup)
end

function mod.cleanup()
    pcall(sk_cleanup)
end

todo_list = { "setup" }
