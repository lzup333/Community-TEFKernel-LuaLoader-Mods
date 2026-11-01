-- 我就是哨兵神 v1.2.2 —— 用游戏每帧送来的玩家实例，解开被钉死的抓取冷却
-- 目标版本 1.4.5.8
-- ============================================================================
-- v1.0.8 实测：`问=480 放=0 补=0 清冷=0 拾=120 携=120 距=? 包=?`
--   `距=? 包=?` 说明复核段一次都没跑完 —— 根因是 **local_player() 一直返回 nil**，
--   也就是 `Main.player[Main.myPlayer]` 这条路取不到玩家实例（历史几版都栽在这）。
-- ----------------------------------------------------------------------------
-- 本版换获取实例的方式：
--   hook `Player.Update_SentryBackpack()`（0 参私有方法，Player.Update 里
--   **只对本机玩家**每帧调用一次，Player.cs:24760）——它的 instance 参数就是玩家本人！
--   在这个回调里：
--     · 用 patch.retain 缓存玩家实例（跨帧可用），后面其它钩子直接复用；
--     · 顺手把 accSentryBackpackGrabCooldown 清 0（该字段被携带中的哨兵每帧钉成 2）。
--   同时在 CanGetPickedUpBySentryBackpack 的 prefix 里，再用缓存实例清一次冷却，
--   紧贴判定之前抹掉，避免更新顺序把 2 又写回来。
-- ----------------------------------------------------------------------------
-- 病根回顾：被携带的哨兵每帧调 SetAsSelectedSentryBackpackTarget()，
--   实现是 `Main.player[owner].accSentryBackpackGrabCooldown = 2;`（玩家级字段），
--   于是玩家冷却永远 > 0，CanGetPickedUpBySentryBackpack 直接返回 false，
--   其它哨兵永远捡不起来 —— 这才是"只能带 1 个"的真正原因。
-- 安全：不遍历数组、不按下标读游戏数组；只碰 hook 给的实例。
mod.meta = { pkg_id = "bluefish.sentinelgod", version = "1.2.2", version_code = 15, api_version = 1 }

local patch = mod.patch

local ad_setup, ad_cleanup

do
    local H = {}
    local hooks = {}
    local MODE = "none"

    local ANN_TEXT = "你说着友情啊、羁绊啊、未来啊，带着一堆的器灵过来了(っ`ヮ’c)"
    local ANN_DELAY = 60
    local CARRY_BASE = 58       -- 排在头顶上方多少像素（越大越远）
    local CARRY_ARC  = 10       -- 弧顶额外抬高量（中间比两侧高多少像素）
    local CARRY_GAP  = 32       -- 相邻两个的横向间距（像素）
    local PICK_RANGE = 110

    local ann_main_done = false
    local ann_frames = 0
local g_player = nil                   -- 缓存的玩家实例（retain 过）
    local cur_set, prev_list, prev_idx = {}, {}, {}   -- 本帧登记 / 上一帧排序名单

    local c_ask, c_force, c_carry, c_cd = 0, 0, 0, 0
    local last_carry = 0
    local status = "(未初始化)"

    -- ---------- 诊断文件 ----------
    local DIAG_PATH = "/sdcard/Download/模组加工厂/项目-我就是哨兵神/sentinel_diag.txt"
    local diag_first = true
    local diag_n = 0
    local function diag(s)
        if diag_n > 2000 then return end
        diag_n = diag_n + 1
        pcall(function()
            local f = io.open(DIAG_PATH, diag_first and "w" or "a")
            diag_first = false
            if f then
                f:write(tostring(os.date("%H:%M:%S")) .. "  " .. s .. "\n")
                f:close()
            end
        end)
    end

    local function find_field(type_handle, name)
        local cur, guard = type_handle, 0
        while cur and guard < 16 do
            local f = patch.get_field(cur, name)
            if f then return f end
            cur = patch.get_parent(cur)
            guard = guard + 1
        end
        return nil
    end

    local function rd(field, inst, ty)
        if not field then return nil end
        local ok, v = pcall(patch.get_field_value, field, inst, ty)
        if ok then return v end
        return nil
    end

    local function wr(field, inst, v, ty)
        if not field then return false end
        local ok, r = pcall(patch.set_field_value, field, inst, v, ty)
        return ok and r ~= false
    end

    local function in_world()
        if H.m_game_menu then
            local ok, v = pcall(patch.invoke, H.m_game_menu)
            if ok and type(v) == "boolean" then return (v == false) end
        end
        if H.f_gamemenu then
            local v = rd(H.f_gamemenu, nil, "bool")
            if v == true then return false end
            if v == false then return true end
        end
        return true
    end

    local function say(text)
        if type(text) ~= "string" then return false end
        local s = text
        if patch.string_create then
            local okc, r = pcall(patch.string_create, text)
            if okc and r then s = r end
        end
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

    -- ---------- 缓存玩家实例（retain 后可跨帧） ----------
    local function cache_player(inst)
        if g_player or not inst then return end
        if patch.retain then
            local ok, p = pcall(patch.retain, inst)
            if ok and p then
                g_player = p
                return
            end
        end
        g_player = inst
    end

    -- ---------- 主挂点：Player.Update_SentryBackpack（只对本机玩家每帧一次） ----------
    local function on_sentry_bag(inst)
        if not inst then return end
        cache_player(inst)
        if rd(H.f_bag, inst, "bool") ~= true then return end
        local cd = rd(H.f_cd, inst, "int32")
        if type(cd) == "number" and cd > 0 then
            if wr(H.f_cd, inst, 0, "int32") then
                c_cd = c_cd + 1
            end
        end
    end

    -- ---------- 捡起判定：prefix 紧贴判定前清冷却 ----------
    local function on_can_pick_pre(inst, args, result)
        local player = g_player
        if not player then return false end
        if rd(H.f_bag, player, "bool") ~= true then return false end
        local cd = rd(H.f_cd, player, "int32")
        if type(cd) == "number" and cd > 0 then
            if wr(H.f_cd, player, 0, "int32") then
                c_cd = c_cd + 1
            end
        end
        return false
    end

    -- ---------- 捡起判定：postfix 统计 + 兜底放行 ----------
    local function on_can_pick(inst, args, result)
        c_ask = c_ask + 1
        if result == true then return nil end
        if not inst then return nil end
        local player = g_player
        if not player then return nil end
        if rd(H.f_bag, player, "bool") ~= true then return nil end

        local okA, px, py = pcall(patch.get_field_vec2, H.f_player_pos, player)
        local okB, qx, qy = pcall(patch.get_field_vec2, H.f_proj_pos, inst)
        if not (okA and okB) then return nil end
        if type(px) ~= "number" or type(qx) ~= "number" then return nil end

        local pwid = rd(H.f_player_w, player, "int32") or 20
        local phei = rd(H.f_player_h, player, "int32") or 42
        local qwid = rd(H.f_proj_w, inst, "int32") or 16
        local qhei = rd(H.f_proj_h, inst, "int32") or 16
        local dx = (qx + qwid * 0.5) - (px + pwid * 0.5)
        local dy = (qy + qhei * 0.5) - (py + phei * 0.5)
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist <= PICK_RANGE then
            c_force = c_force + 1
            return true
        end
        return nil
    end

    -- 每个哨兵按自身编号固定占一个位次，整齐排在头顶上方，中间略高（刃杖式）
    local function on_reposition(inst)
        if not inst then return end
        -- 只处理「哨兵本体」：月亮传送门法杖(type 641)这类武器有配套的攻击体(type 642)，
        --   那个攻击体每帧先 base.Center = 父哨兵.Center，再调一次本方法做上移跟随。
        --   若按它自己的 whoAmI 派位，就会与本体错开 —— 表现为攻击偏移。
        --   sentry=false 的一律不碰；字段取不到时不做这项过滤，保持原行为。
        if H.f_proj_sentry and rd(H.f_proj_sentry, inst, "bool") ~= true then return end
        c_carry = c_carry + 1

        local player = g_player
        if not player then return end
        local who = rd(H.f_proj_who, inst, "int32")
        if type(who) ~= "number" then return end

        -- 登记进本帧名单，用来推算"一共几个、我排第几"
        if not cur_set[who] then cur_set[who] = true end

        local n = #prev_list
        local idx = prev_idx[who]
        if not idx then
            -- 名单还没建立（极端兜底）：先按"只有我一个"排在正上方，避免乱摆
            n = 1
            idx = 1
        end

        local half = (n - 1) * 0.5
        local k = idx - 1 - half                       -- -half .. +half，居中对称
        local t = 0
        if half > 0.001 then
            t = k / half
            if t > 1 then t = 1 elseif t < -1 then t = -1 end
        end

        local off_x = k * CARRY_GAP
        local off_y = -(CARRY_BASE + CARRY_ARC * (1 - t * t))   -- 中间高、两侧低

        local okP, px, py = pcall(patch.get_field_vec2, H.f_player_pos, player)
        if not okP or type(px) ~= "number" or type(py) ~= "number" then return end

        local pw = rd(H.f_player_w, player, "int32") or 20
        local ph = rd(H.f_player_h, player, "int32") or 42
        local qw = rd(H.f_proj_w, inst, "int32") or 16
        local qh = rd(H.f_proj_h, inst, "int32") or 16

        local cx = px + pw * 0.5 + off_x
        local cy = py + ph * 0.5 + off_y
        pcall(patch.set_field_vec2, H.f_proj_pos, inst, cx - qw * 0.5, cy - qh * 0.5)
    end

    -- 每帧末尾整理名单：把本帧登记到的哨兵按编号排好，供下一帧分位次
    local function rebuild_list()
        local arr = {}
        for who in pairs(cur_set) do arr[#arr + 1] = who end
        table.sort(arr)
        local ix = {}
        for i = 1, #arr do ix[arr[i]] = i end
        prev_list, prev_idx = arr, ix
        cur_set = {}
    end

    local function on_main_update()
        rebuild_list()
        if not in_world() then
            ann_frames = 0
            return
        end
        ann_frames = ann_frames + 1

        if not ann_main_done then
            if ann_frames >= ANN_DELAY then
                if say(ANN_TEXT) then ann_main_done = true end
            end
            return
        end

        if ann_frames % 120 == 0 then
            if c_carry > 0 and c_carry ~= last_carry then
                last_carry = c_carry
                diag(string.format("携带=%d 问=%d 补=%d 清冷=%d",
                    c_carry, c_ask, c_force, c_cd))
            end
            c_ask, c_force, c_carry, c_cd = 0, 0, 0, 0
        end
    end

    -- ---------- setup ----------
    ad_setup = function()
        local ok, err = pcall(function()
            local t_main   = patch.get_type("Terraria", "Main")
            local t_player = patch.get_type("Terraria", "Player")
            local t_proj   = patch.get_type("Terraria", "Projectile")
            if not (t_main and t_player and t_proj) then
                error("关键类型缺失")
            end
            H.f_gamemenu   = patch.get_field(t_main, "gameMenu")
            H.m_game_menu  = patch.get_method(t_main, "get_gameMenu", 0)
            H.f_myplayer   = patch.get_field(t_main, "myPlayer")
            H.f_playerarr  = patch.get_field(t_main, "player")
            H.f_bag        = find_field(t_player, "accSentryBackpack")
            H.f_cd         = find_field(t_player, "accSentryBackpackGrabCooldown")
            H.f_player_pos = find_field(t_player, "position")
            H.f_player_w   = find_field(t_player, "width")
            H.f_player_h   = find_field(t_player, "height")
            H.f_proj_pos   = find_field(t_proj, "position")
            H.f_proj_w     = find_field(t_proj, "width")
            H.f_proj_h     = find_field(t_proj, "height")
            H.f_proj_who   = find_field(t_proj, "whoAmI")
            H.f_proj_sentry = find_field(t_proj, "sentry")
            H.m_newtext5   = patch.get_method(t_main, "NewText", 5)
            H.m_newtext4   = patch.get_method(t_main, "NewText", 4)
            status = string.format("背包=%s 冷却=%s 位置=%s/%s retain=%s",
                tostring(H.f_bag ~= nil), tostring(H.f_cd ~= nil),
                tostring(H.f_player_pos ~= nil), tostring(H.f_proj_pos ~= nil),
                tostring(patch.retain ~= nil))

            -- 主挂点：Update_SentryBackpack（每帧对本机玩家一次）
            local m_bag = patch.get_method(t_player, "Update_SentryBackpack", 0)
            if m_bag then
                local okh, h = pcall(patch.install_hook, m_bag, { postfix = on_sentry_bag })
                if okh and h then
                    hooks[#hooks + 1] = h
                    MODE = "sentrybag"
                end
            end
            -- 捡起判定
            local m_can = patch.get_method(t_proj, "CanGetPickedUpBySentryBackpack", 0)
            if m_can then
                local okh, h = pcall(patch.install_hook, m_can, {
                    prefix = on_can_pick_pre,
                    postfix = on_can_pick,
                    override_result = true,
                })
                if okh and h then
                    hooks[#hooks + 1] = h
                    MODE = MODE .. "+canpick"
                end
            end
            local m_repo = patch.get_method(t_proj, "AI_Sentries_HeavySlingReposition", 0)
            if m_repo then
                local okh, h = pcall(patch.install_hook, m_repo, { postfix = on_reposition })
                if okh and h then
                    hooks[#hooks + 1] = h
                    MODE = MODE .. "+reposition"
                end
            end
            local m_up = patch.get_method(t_main, "Update", 1)
                or patch.get_method(t_main, "Update", 0)
            if m_up then
                local okh, h = pcall(patch.install_hook, m_up, { postfix = on_main_update })
                if okh and h then
                    hooks[#hooks + 1] = h
                    MODE = MODE .. "+main"
                end
            end
            status = status .. " 挂点=" .. MODE
        end)
        if not ok then
            status = status .. " setup异常:" .. tostring(err)
            mod.warn("[哨兵神] 初始化失败: " .. tostring(err))
        end
        diag("setup " .. status)
        mod.info("[哨兵神] 自检 " .. status)
    end

    ad_cleanup = function()
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
        g_player = nil
    end
end

function setup()
    pcall(ad_setup)
end

function mod.cleanup()
    pcall(ad_cleanup)
end

todo_list = { "setup" }