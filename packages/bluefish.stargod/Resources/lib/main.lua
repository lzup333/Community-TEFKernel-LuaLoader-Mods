-- ============================================================================
-- 我就是星神  v1.0.3
-- pkg: bluefish.stargod    author: 蓝色大肥鱼
-- 星星斗篷系列受击后落星数量 3 颗 → 300 颗
--
-- 源码定位（PC 1.4.5.8，Player.cs:38725）
--   if (starCloakItem != null && !starCloakItem.IsAir)
--   {
--       int num15 = 3;                    ← 数量是**局部变量**，没有字段可改
--       int type = 726;                   ← 星星斗篷
--       蜜蜂斗篷 724 / 魔力斗篷 723 / 蛇纹斗篷 1133 / 星星面纱 725
--       for (int num17 = 0; num17 < num15; num17++)
--           Projectile.NewProjectile(..., type, num16, 5f, whoAmI, 0f, position.Y);
--   }
--
-- 由于 num15 改不到，只能补发：
--   一次受击会连续调用 NewProjectile 共 3 次（循环 3 次），
--   所以每「一次调用」补发 99 颗 → 3 × 99 + 原版 3 = 300 颗。
-- ============================================================================

mod.meta = { pkg_id = "bluefish.stargod", version = "1.0.3", version_code = 103, api_version = 1 }

local patch = mod.patch

-- 正式版：不写任何文件（logf 保留为空实现，需要排查时再恢复落盘）
local function logf(_) end

-- ============ 常量 ============
local ECHO_TEXT      = "300颗够吗？(*^▽^*)"
local ECHO_DELAY     = 60      -- 进世界满 60 帧（约 1 秒）后播报
local EXTRA_PER_CALL = 99      -- 原版每次调用发 1 颗、共调用 3 次 → 每次补 99，合计 300

-- 斗篷落星的射弹 ID（Player.cs 里这套分支专用的 5 个）
local CLOAK_STARS = {
    [726]  = true,   -- StarCloakStar       星星斗篷
    [724]  = true,   -- BeeCloakStar        蜜蜂斗篷
    [723]  = true,   -- ManaCloakStar       魔力斗篷
    [1133] = true,   -- SnakeBandStarCloakTinkerStar  德鲁伊蛇纹斗篷
    [725]  = true,   -- StarVeilStar        星星面纱（星星斗篷升级版）
}

-- ============ 句柄 ============
local T_Main, T_Player, T_Proj
local m_newproj
local m_newtext
local m_get_gamemenu
local f_main_gamemenu

-- ============ 状态 ============
local ready      = false
local reenter    = false
local echo_frames = 0
local echo_done   = false

-- ============ 工具 ============
local function find_field(t, name)
    if not t then return nil end
    local ok, f = pcall(patch.get_field, t, name)
    if ok and f then return f end
    return nil
end

local function get_b(f, inst, dft)
    if not f then return dft end
    local ok, v = pcall(patch.get_field_value, f, inst, "bool")
    if ok and type(v) == "boolean" then return v end
    return dft
end

-- 播报颜色（RGB）：天蓝色 Sky Blue #87CEEB
local ECHO_COLOR = { 135, 206, 235 }

local function say(s)
    if not m_newtext then return end
    -- PE 1.4.5.8 的 NewText：
    --   (string, Color, bool)                      3 参
    --   (string, byte R, byte G, byte B, bool)     5 参  ← 用这个
    -- 没有 4 参重载；若按 4 参找会退回到 (string, Color, bool)，
    -- 把 135 当 Color 结构体指针传进去，颜色就丢了（表现为黑色）
    pcall(patch.invoke, m_newtext, patch.string_create(s),
        ECHO_COLOR[1], ECHO_COLOR[2], ECHO_COLOR[3], false)
end

local function in_world()
    if m_get_gamemenu then
        local ok, r = pcall(patch.invoke, m_get_gamemenu)
        if ok and type(r) == "boolean" then return not r end
    end
    if f_main_gamemenu then
        local v = get_b(f_main_gamemenu, nil, nil)
        if type(v) == "boolean" then return not v end
    end
    return true      -- 取不到就当在世界里（Player.Update 基本只在世界里跑）
end

-- ============ 补发落星 ============
-- 原版一次受击会走 3 次 NewProjectile（循环 3 次），这里每次补 99 颗。
-- reenter 守卫生效期间的内层调用会直接放行，不会递归。
local function newproj_prefix(inst, args, result)
    if reenter or not ready then return false end
    if not args or not m_newproj then return false end
    local t = args[6]
    if not CLOAK_STARS[t] then return false end

    local sx, sy = args[2], args[3]
    local vx, vy = args[4], args[5]
    if type(sx) ~= "number" or type(sy) ~= "number" then return false end
    if type(vx) ~= "number" or type(vy) ~= "number" then return false end

    reenter = true
    for _ = 1, EXTRA_PER_CALL do
        -- 起点在玩家上方 500~800 像素、水平 ±400 内随机，和原版同一个落星范围
        local nx = sx + (math.random() - 0.5) * 400
        local ny = sy - math.random(500, 800)
        -- 方向沿用原速度，加一点抖动，让 300 颗呈扇形而不是一条线
        local nvx = vx + (math.random() - 0.5) * 3.0
        local nvy = vy + (math.random() - 0.5) * 1.5
        pcall(patch.invoke, m_newproj,
            args[1], nx, ny, nvx, nvy,
            args[6], args[7], args[8], args[9],
            args[10], args[11], args[12], args[13])
    end
    reenter = false
    return false        -- 放行原版那 1 颗
end

-- ============ 进世界播报 ============
local function update_postfix(inst, args, result)
    if not ready or echo_done then return end
    if in_world() then
        echo_frames = echo_frames + 1
        if echo_frames >= ECHO_DELAY then
            echo_done = true
            say(ECHO_TEXT)
            logf("[echo] 播报于第 " .. echo_frames .. " 帧")
        end
    else
        echo_frames = 0
    end
end

-- ============ 钩子安装 ============
local function hook(method, spec, label)
    if not method then
        logf("[hook] MISSING " .. label)
        mod.error("[星神] 缺少方法：" .. label)
        return false
    end
    local ok, err = pcall(patch.install_hook, method, spec)
    if not ok then
        logf("[hook] FAIL " .. label .. " : " .. tostring(err))
        mod.error("[星神] 挂钩失败 " .. label .. "：" .. tostring(err))
        return false
    end
    logf("[hook] OK " .. label)
    return true
end

function setup()
    logf("platform=" .. tostring(mod.platform))

    T_Main   = patch.get_type("Terraria", "Main")
    T_Player = patch.get_type("Terraria", "Player")
    T_Proj   = patch.get_type("Terraria", "Projectile")
    logf(string.format("types: Main=%s Player=%s Proj=%s",
        tostring(T_Main), tostring(T_Player), tostring(T_Proj)))
    if not (T_Main and T_Player and T_Proj) then
        mod.error("[星神] 类型获取失败")
        return
    end

    m_newproj        = patch.get_method(T_Proj, "NewProjectile", 13) or patch.get_method(T_Proj, "NewProjectile")
    m_newtext        = patch.get_method(T_Main, "NewText", 5) or patch.get_method(T_Main, "NewText", 4)
    m_get_gamemenu   = patch.get_method(T_Main, "get_gameMenu")
    f_main_gamemenu  = find_field(T_Main, "gameMenu")

    logf(string.format("methods: newproj=%s newtext=%s gamemenu=%s",
        tostring(m_newproj), tostring(m_newtext), tostring(m_get_gamemenu)))
    if not m_newproj then
        mod.error("[星神] 取不到 Projectile.NewProjectile，落星补发无法工作")
        return
    end

    local ok = true
    ok = hook(m_newproj,
        { prefix = newproj_prefix }, "Projectile.NewProjectile") and ok
    ok = hook(
        patch.get_method(T_Player, "Update", 1) or patch.get_method(T_Player, "Update"),
        { postfix = update_postfix }, "Player.Update") and ok

    ready = ok
    logf("ready=" .. tostring(ready))
    if ready then
        mod.info("[星神] 已启用")
    else
        mod.error("[星神] 部分钩子未装上，功能可能不完整")
    end
end

todo_list = { "setup" }
