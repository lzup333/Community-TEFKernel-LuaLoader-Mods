-- 我就说召神 —— LuaLoader Lua Mod（v1.0.2 正式版）
-- 目标版本 1.4.5.8
-- 功能：装备蛇形手环(6157)/衔尾蛇指环(6162)/德鲁伊蛇纹斗篷(6186) 任意一件后，
--       每挥 3 次鞭子，物品栏里第 2、3、4 条鞭子会一起协同攻击（原版只协同第 2 条）。
-- 实现：原版切鞭逻辑埋在 Player.ItemCheck 大函数内部无法直接改，故
--       1) 在 ItemCheck 的 prefix 读出原版开关 accSnakeBand（三件饰品共用），
--          把它临时关掉，令原版「只协同 1 条」不触发；
--       2) 在 postfix 用原版同一套计数器 repeatWhipSwings 与「挥到动画一半」判断时机，
--          自己扫描物品栏手持之后的前 3 条鞭子，逐条调用游戏自己的 ItemCheck_Shoot
--          让它们协同攻击（传 withAudioVisualFeedback=false，伤害自动为原版 1/3）。
-- 注意：IsAWhip 等「值句柄」是借用的、不能跨帧缓存，故每次判断鞭子前现读。
mod.meta = { pkg_id = "bluefish.snakewhip", version = "1.0.2", version_code = 3, api_version = 1 }
local patch = mod.patch

-- ============================================================================
-- 我就说召神模块（IIFE 作用域隔离；默认常开、无开关）
-- ============================================================================
local sw_setup, sw_cleanup
do
    local H = {}          -- 句柄缓存：type / 字段句柄 / 方法句柄 / 属性getter（这些可跨帧）
    local hook_h = nil    -- ItemCheck 钩子句柄
    local saved_snake = false   -- prefix 暂存的原版开关原值（同帧 prefix设/postfix用）

    -- ---- 进世界播报状态 ----
    local ANN_TEXT = "以前你叫我牢召，我不挑你理，现在你该叫我什么？"
    local ann_done = false      -- 是否已播报过
    local ann_frames = 0        -- 进世界后等待帧数

    -- ---------- 每帧：是否在世界 ----------
    local function in_world()
        if not H.f_gamemenu then return true end
        local ok, v = pcall(patch.get_field_value, H.f_gamemenu, nil, "bool")
        if ok and v ~= nil then return (v == false) end
        return true
    end

    -- ---------- 现读 IsAWhip 数组（不缓存值，只缓存字段句柄） ----------
    local function read_isawhip()
        if not H.f_isawhip then return nil end
        local ok, a = pcall(patch.get_field_value, H.f_isawhip, nil, "object")
        if ok then return a end
        return nil
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
            local okc, r = pcall(patch.invoke, H.m_newtext5, s, 150, 255, 200, false)
            if okc and r ~= false then return true end
        end
        if H.m_newtext4 then
            local okc, r = pcall(patch.invoke, H.m_newtext4, s, 150, 255, 200)
            if okc and r ~= false then return true end
        end
        return false
    end

    -- ---------- prefix：读原版开关并临时关闭 ----------
    local function on_prefix(inst)
        if not inst then return end
        if not in_world() or not H.f_snake then
            saved_snake = false
            return
        end
        local ok, v = pcall(patch.get_field_value, H.f_snake, inst, "bool")
        saved_snake = (ok and v == true)
        if saved_snake then
            pcall(patch.set_field_value, H.f_snake, inst, false, "bool")
        end
    end

    -- ---------- postfix：进世界播报 + 复刻原版时机协同第 2、3、4 条鞭子 ----------
    local function on_postfix(inst)
        if not inst then return end

        -- 恢复原版开关，避免影响其它读取
        if saved_snake and H.f_snake then
            pcall(patch.set_field_value, H.f_snake, inst, true, "bool")
        end

        -- ===== 进世界播报（延时 90 帧 ≈ 1.5 秒后发一次） =====
        if not ann_done then
            if in_world() then
                ann_frames = ann_frames + 1
                if ann_frames >= 90 then
                    if send_announce(ANN_TEXT) then
                        ann_done = true
                    else
                        ann_frames = 0   -- 发送失败则下轮重试
                    end
                end
            else
                ann_frames = 0
            end
        end

        -- ===== 切鞭协同 =====
        if not saved_snake then return end
        if not in_world() then return end

        if not (H.f_repeat and H.f_anim and H.f_animmax and H.f_inv
                and H.f_whoami and H.f_shoot and H.f_isawhip
                and H.m_getsel and H.m_isair
                and H.m_getdamage and H.m_shoot) then
            return
        end

        -- 1) repeatWhipSwings % 3 == 0（每挥 3 次触发一次）
        local ok_sw, swings = pcall(patch.get_field_value, H.f_repeat, inst, "int32")
        if not ok_sw or swings == nil then return end
        if (swings % 3) ~= 0 then return end

        -- 2) 挥鞭动画进行到一半（itemAnimation == itemAnimationMax/2 且 > 0）
        local ok_an, anim = pcall(patch.get_field_value, H.f_anim, inst, "int32")
        local ok_am, animmax = pcall(patch.get_field_value, H.f_animmax, inst, "int32")
        if not ok_an or not ok_am or anim == nil or animmax == nil then return end
        if anim <= 0 then return end
        if anim ~= math.floor(animmax * 0.5) then return end

        -- 3) whoAmI / inventory / selectedItem
        local whoami = nil
        do local ok_w, w = pcall(patch.get_field_value, H.f_whoami, inst, "int32")
           if ok_w then whoami = w end end
        if whoami == nil then return end

        local inv = nil
        do local ok_i, a = pcall(patch.get_field_value, H.f_inv, inst, "object")
           if ok_i then inv = a end end
        if not inv then return end

        local sel = nil
        do local ok_s, s = pcall(patch.invoke, H.m_getsel, inst)
           if ok_s then sel = s end end
        if sel == nil then return end

        -- 现读一次 IsAWhip，本帧内复用
        local arr_whip = read_isawhip()

        local function is_whip(item)
            if not item then return false end
            local ok_a, air = pcall(patch.invoke, H.m_isair, item)
            if ok_a and air == true then return false end
            local ok_sh, shoot = pcall(patch.get_field_value, H.f_shoot, item, "int32")
            if not ok_sh or shoot == nil or shoot <= 0 then return false end
            if not arr_whip then return false end
            local ok_w2, isw = pcall(patch.array_at, arr_whip, shoot, "bool")
            if ok_w2 and isw == true then return true end
            return false
        end

        local held = nil
        do local ok_h, it = pcall(patch.array_at, inv, sel)
           if ok_h then held = it end end
        if not is_whip(held) then return end   -- 手持不是鞭子就不协同

        -- 4) 扫描手持之后的前 3 条鞭子（第 2、3、4 条），逐条协同攻击
        local count = 0
        local n = nil
        do local ok_n, len = pcall(patch.array_length, inv)
           if ok_n then n = len end end
        if not n then n = 50 end
        local last = n - 1
        if last > 49 then last = 49 end

        for k = sel + 1, last do
            local it = nil
            do local ok_a, v = pcall(patch.array_at, inv, k)
               if ok_a then it = v end end
            if it and is_whip(it) then
                local dmg = nil
                do local ok_d, d = pcall(patch.invoke, H.m_getdamage, inst, it)
                   if ok_d then dmg = d end end
                if dmg ~= nil then
                    -- 第 4 参 false => 走原版「协同攻击」分支，伤害自动 1/3、击退 1/4，
                    -- 且不会再次递增计数器（原版只在 true 分支递增），杜绝无限触发。
                    pcall(patch.invoke, H.m_shoot, inst, whoami, it, dmg, false)
                    count = count + 1
                    if count >= 3 then break end
                end
            end
        end
    end

    -- ---------- setup ----------
    sw_setup = function()
        local ok, err = pcall(function()
            local t_player = patch.get_type("Terraria", "Player")
            local t_item   = patch.get_type("Terraria", "Item")
            local t_main   = patch.get_type("Terraria", "Main")
            local t_entity = patch.get_type("Terraria", "Entity")
            local t_projid = patch.get_type("Terraria.ID", "ProjectileID")
            local t_int    = patch.get_basic_type("int32")
            local t_bool   = patch.get_basic_type("bool")
            if not (t_player and t_item and t_main and t_projid and t_int and t_bool) then
                error("关键类型缺失")
            end

            -- 字段句柄（可跨帧缓存）
            H.f_snake    = patch.get_field(t_player, "accSnakeBand")
            H.f_repeat   = patch.get_field(t_player, "repeatWhipSwings")
            H.f_anim     = patch.get_field(t_player, "itemAnimation")
            H.f_animmax  = patch.get_field(t_player, "itemAnimationMax")
            H.f_inv      = patch.get_field(t_player, "inventory")
            H.f_shoot    = patch.get_field(t_item, "shoot")
            H.f_gamemenu = patch.get_field(t_main, "gameMenu")
            H.f_whoami   = (t_entity and patch.get_field(t_entity, "whoAmI"))
                       or patch.get_field(t_player, "whoAmI")

            -- 播报方法（NewText 5 参优先，4 参兜底）
            H.m_newtext5 = patch.get_method(t_main, "NewText", 5)
            H.m_newtext4 = patch.get_method(t_main, "NewText", 4)

            -- IsAWhip 字段句柄（值改为运行时现读）
            local sets = patch.get_inner_type(t_projid, "Sets")
            if sets then
                H.f_isawhip = patch.get_field(sets, "IsAWhip")
            end

            -- 属性 getter
            local p_sel   = patch.get_property(t_player, "selectedItem")
            if p_sel then H.m_getsel = patch.property_get_method(p_sel) end
            local p_isair = patch.get_property(t_item, "IsAir")
            if p_isair then H.m_isair = patch.property_get_method(p_isair) end

            -- 方法
            H.m_getdamage = patch.get_method(t_player, "GetWeaponDamage", 1)
            H.m_shoot = patch.get_method_by_param_types(
                t_player, "ItemCheck_Shoot", { t_int, t_item, t_int, t_bool })
            if not H.m_shoot then
                H.m_shoot = patch.get_method(t_player, "ItemCheck_Shoot", 4)
            end

            -- ItemCheck 钩子
            local m_itemcheck = patch.get_method(t_player, "ItemCheck", 0)
            if not m_itemcheck then error("ItemCheck 方法未找到") end
            local okh, h = pcall(patch.install_hook, m_itemcheck, {
                prefix  = on_prefix,
                postfix = on_postfix,
            })
            if not (okh and h) then
                error("ItemCheck 钩子安装失败: " .. tostring(h))
            end
            hook_h = h
        end)
        if not ok then
            mod.warn("[召神] 初始化失败: " .. tostring(err))
        end
    end

    sw_cleanup = function()
        if hook_h then pcall(function() hook_h:remove() end) hook_h = nil end
    end
end

-- ============================================================================
-- 入口（照合集实测范式：全局 setup + todo_list + mod.cleanup）
-- ============================================================================
function setup()
    pcall(sw_setup)
end

function mod.cleanup()
    pcall(sw_cleanup)
end

todo_list = { "setup" }