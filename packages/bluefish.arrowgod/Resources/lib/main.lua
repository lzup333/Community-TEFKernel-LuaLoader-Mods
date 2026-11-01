-- 我就是箭神 v1.0.7 —— 鸟妖附身符系列「追踪箭」冷却强化（定稿）
-- 目标版本 1.4.5.8
-- ============================================================================
-- 原版机制（源码 Terraria.Player 核实）：
--   装备 鸟妖附身符(6166) / 炽天使项链(6180) / 凤凰箭袋(6181) 任意一件，
--   都会置 Player.accHarpyCharm = true，之后每帧走 Update_HarpyCharm()：
--     · accHarpyCharmCooldown > 0 每帧递减 1；
--     · 归零才调 HarpyCharmEffect()，扫 1000 支箭，挑离玩家 400~1200 像素、
--       能看见目标的那一支，把朝向掰向目标；
--     · 命中一次后 cooldown = 90 帧（1.5 秒；炽天使项链 ×0.8 = 72 帧）。
--   本模组把该冷却钳到 6 帧（0.1 秒），三件饰品统一生效。
-- ============================================================================
-- 写法照「我就是召神」范式：setup 一次取句柄 + 全 pcall + string_create 播报
--   + 进世界延时重试播报 + 入口三件套（setup / mod.cleanup / todo_list）。
-- 双挂点（幂等，重复钳制无害）：
--   主：hook Player.Update_HarpyCharm（0 参，只对本机玩家每帧一次）
--   备：hook Main.Update 轮询 myPlayer（防私有方法被内联/取不到）
-- v1.0.4：去掉诊断刷屏，只保留进世界播报一次。
-- v1.0.5：换成女仆箭手立绘图标；播报文案改为 face 版。
-- v1.0.6：进世界播报延时 1.5 秒 -> 1 秒；文案改为 (¬_¬)。
-- v1.0.7：播报文案去掉表情，只留「我已经锁定你了」。
mod.meta = { pkg_id = "bluefish.arrowgod", version = "1.0.7", version_code = 8, api_version = 1 }

local patch = mod.patch

local ad_setup, ad_cleanup

do
    local H = {}                          -- 句柄缓存（类型/字段/方法，可跨帧）
    local hooks = {}                      -- 钩子句柄
    local MODE = "none"
    local CD_FRAMES = 6                   -- 6 帧 = 0.1 秒（原版 90 帧 = 1.5 秒）
    local ANN_TEXT = "我已经锁定你了"
    local ANN_DELAY = 60                    -- 进世界后等待帧数：60 帧 = 1 秒
    local ann_done, ann_frames = false, 0
    local status = "(未初始化)"

    -- ---------- 安全读写 ----------
    local function rd(field, inst, ty)
        if not field then return nil end
        local ok, v = pcall(patch.get_field_value, field, inst, ty)
        if ok then return v end
        return nil
    end
    local function wr(field, inst, value, ty)
        if not field then return false end
        local ok, r = pcall(patch.set_field_value, field, inst, value, ty)
        return ok and r ~= false
    end

    -- ---------- 是否在世界内 ----------
    local function in_world()
        if not H.f_gamemenu then return true end
        local v = rd(H.f_gamemenu, nil, "bool")
        if v == nil then return true end
        return v == false
    end

    -- ---------- 播报（string_create 造托管字符串） ----------
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

    -- ---------- 进世界播报（延时 60 帧 = 1 秒，失败下轮重试） ----------
    local function tick_announce()
        if ann_done then return end
        if not in_world() then
            ann_frames = 0
            return
        end
        ann_frames = ann_frames + 1
        if ann_frames >= ANN_DELAY then
            if say(ANN_TEXT) then
                ann_done = true
            else
                ann_frames = ANN_DELAY - 30          -- 未成功，留一点余量下一帧继续试
            end
        end
    end

    -- ---------- 核心：把本机玩家的追踪箭冷却钳到 CD_FRAMES ----------
    local function process(inst)
        if inst and H.f_cd then
            local cd = rd(H.f_cd, inst, "int32")
            if type(cd) == "number" and cd > CD_FRAMES then
                wr(H.f_cd, inst, CD_FRAMES, "int32")
            end
        end
        tick_announce()
    end

    -- ---------- 主挂点：Player.Update_HarpyCharm postfix ----------
    local function on_harpy(inst)
        process(inst)
    end

    -- ---------- 备挂点：Main.Update 轮询 myPlayer ----------
    local function on_main_update()
        if not in_world() then return end
        local idx = rd(H.f_myplayer, nil, "int32")
        if type(idx) ~= "number" or idx < 0 then return end
        local arr = rd(H.f_playerarr, nil, "object")
        if not arr then return end
        local okA, player = pcall(patch.array_at, arr, idx)
        if okA and player then process(player) end
    end

    -- ---------- setup ----------
    ad_setup = function()
        local ok, err = pcall(function()
            local t_main   = patch.get_type("Terraria", "Main")
            local t_player = patch.get_type("Terraria", "Player")
            if not (t_main and t_player) then
                error("关键类型缺失 Main/Player")
            end
            H.f_gamemenu  = patch.get_field(t_main, "gameMenu")
            H.f_myplayer  = patch.get_field(t_main, "myPlayer")
            H.f_playerarr = patch.get_field(t_main, "player")
            H.f_cd        = patch.get_field(t_player, "accHarpyCharmCooldown")
            H.m_newtext5  = patch.get_method(t_main, "NewText", 5)
            H.m_newtext4  = patch.get_method(t_main, "NewText", 4)
            status = string.format("cd=%s 数组=%s 播报=%s/%s",
                tostring(H.f_cd ~= nil), tostring(H.f_playerarr ~= nil),
                tostring(H.m_newtext5 ~= nil), tostring(H.m_newtext4 ~= nil))

            -- 主挂点
            local m_harpy = patch.get_method(t_player, "Update_HarpyCharm", 0)
            if m_harpy then
                local okh, h = pcall(patch.install_hook, m_harpy, { postfix = on_harpy })
                if okh and h then
                    hooks[#hooks + 1] = h
                    MODE = "harpy"
                end
            end
            -- 备挂点（与主挂点并存，幂等）
            local m_up = patch.get_method(t_main, "Update", 1)
                or patch.get_method(t_main, "Update", 0)
            if m_up then
                local okh, h = pcall(patch.install_hook, m_up, { postfix = on_main_update })
                if okh and h then
                    hooks[#hooks + 1] = h
                    MODE = (MODE == "harpy") and "harpy+main" or "main"
                end
            end
            if MODE == "none" then
                error("两个挂点都没装上")
            end
            status = status .. " 挂点=" .. MODE
        end)
        if not ok then
            mod.warn("[箭神] 初始化失败: " .. tostring(err))
        end
        mod.info("[箭神] 自检 " .. status)
    end

    ad_cleanup = function()
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
    end
end

-- ============================================================================
-- 入口（照合集/召神实测范式：全局 setup + todo_list + mod.cleanup）
-- ============================================================================
function setup()
    pcall(ad_setup)
end

function mod.cleanup()
    pcall(ad_cleanup)
end

todo_list = { "setup" }