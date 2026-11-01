-- 我就是协击神 v1.0.2 —— 碎裂之石系列「协同攻击」冷却强化
-- 目标版本 1.4.5.8
-- ============================================================================
-- 需求：碎裂之石(SnappingStone 6167) / 毁灭臂环(ArmletOfRuin 6179) /
--       火山碎屑石(Pyroclast 6178) 的协同攻击周期由 6 秒缩到 0.1 秒。
-- ----------------------------------------------------------------------------
-- 机制（Player.cs / Projectile.cs 核实）：
--   命中 NPC 时游戏会调 Projectile.TryMakingSnappingStoneStrike(...)，开头是
--       if (owner != Main.myPlayer || Main.player[owner].accSnappingStoneCooldown > 0)
--           return;
--   触发成功后写回：
--       Main.player[owner].accSnappingStoneCooldown = 360;   // ← 6 秒 = 360 帧
--   ⇒ 三件饰品共用这**一个玩家级字段**，改它就等于三件一起改。
--   另外 Player.Update_SnappingStone() 每帧把该值减 1，减到 0 时按身上那件
--   播一次「充能完成」粒子（SnappingStone / PyroclasticStone / ArmletOfRuin）。
-- ----------------------------------------------------------------------------
-- 本模组：把 accSnappingStoneCooldown 钳到 6 帧（0.1 秒），幂等 —— 只往下压，
--   不会把已经更小的值抬上去，也不碰其它任何字段。
--   360 → 6 后，攻击命中后只要 0.1 秒就能再次触发协同攻击。
-- 挂点：
--   ① 主：Player.Update_SnappingStone(0) postfix —— 只对本机玩家每帧一次，
--          instance 就是玩家本人，直接钳。
--   ② 备：Player.ResetEffects(0) postfix —— 主挂点装不上时用（实例同样是玩家）。
-- 安全：不遍历数组、不按下标读游戏数组，只用 hook 给的实例。
-- ============================================================================
mod.meta = { pkg_id = "bluefish.synergystone", version = "1.0.2", version_code = 3, api_version = 1 }

local patch = mod.patch

local ad_setup, ad_cleanup

do
    local H = {}
    local hooks = {}
    local MODE = "none"

    local ANN_TEXT = "这就是我们的频率啊(~_~)"
    local ANN_DELAY = 60        -- 进世界 60 帧 = 1 秒后播报
    local CD_FRAMES = 6         -- 6 帧 = 0.1 秒（原版 360 帧 = 6 秒）

    local ann_main_done = false
    local ann_frames = 0
    local c_clamp = 0
    local status = "(未初始化)"

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

    -- 幂等钳制：只在比目标值大时写回
    local function clamp(inst)
        if not inst then return end
        local cd = rd(H.f_cd, inst, "int32")
        if type(cd) ~= "number" then return end
        if cd > CD_FRAMES then
            if wr(H.f_cd, inst, CD_FRAMES, "int32") then
                c_clamp = c_clamp + 1
                if c_clamp % 60 == 1 then
                    mod.info("[协击神] 冷却已 -" .. tostring(cd) .. " -> " .. tostring(CD_FRAMES))
                end
            end
        end
    end

    -- ① 主挂点
    local function on_snapping(inst)
        clamp(inst)
    end

    -- ② 备挂点
    local function on_reset(inst)
        clamp(inst)
    end

    local function on_main_update()
        if not in_world() then
            ann_frames = 0
            return
        end
        ann_frames = ann_frames + 1
        if not ann_main_done then
            if ann_frames >= ANN_DELAY then
                if say(ANN_TEXT) then ann_main_done = true end
            end
        end
    end

    -- ---------- setup ----------
    ad_setup = function()
        local ok, err = pcall(function()
            local t_player = patch.get_type("Terraria", "Player")
            local t_main   = patch.get_type("Terraria", "Main")
            if not (t_player and t_main) then
                error("关键类型缺失")
            end
            H.f_cd        = find_field(t_player, "accSnappingStoneCooldown")
            H.f_gamemenu  = patch.get_field(t_main, "gameMenu")
            H.m_game_menu = patch.get_method(t_main, "get_gameMenu", 0)
            H.m_newtext5  = patch.get_method(t_main, "NewText", 5)
            H.m_newtext4  = patch.get_method(t_main, "NewText", 4)
            if not H.f_cd then
                error("找不到 Player.accSnappingStoneCooldown")
            end

            local m1 = patch.get_method(t_player, "Update_SnappingStone", 0)
            if m1 then
                local okh, h = pcall(patch.install_hook, m1, {
                    postfix = function(inst) on_snapping(inst) end,
                })
                if okh and h then
                    hooks[#hooks + 1] = h
                    MODE = "snapping"
                end
            end
            if MODE == "none" then
                local m2 = patch.get_method(t_player, "ResetEffects", 0)
                if m2 then
                    local okh, h = pcall(patch.install_hook, m2, {
                        postfix = function(inst) on_reset(inst) end,
                    })
                    if okh and h then
                        hooks[#hooks + 1] = h
                        MODE = "reseteffects"
                    end
                end
            end
            if MODE == "none" then
                error("两个冷却挂点都没装上")
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
            status = "冷却字段=有 挂点=" .. MODE
        end)
        if not ok then
            status = status .. " setup异常:" .. tostring(err)
            mod.warn("[协击神] 初始化失败: " .. tostring(err))
        end
        mod.info("[协击神] 自检 " .. status)
    end

    ad_cleanup = function()
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
    end
end

function setup()
    pcall(ad_setup)
end

function mod.cleanup()
    pcall(ad_cleanup)
end

todo_list = { "setup" }