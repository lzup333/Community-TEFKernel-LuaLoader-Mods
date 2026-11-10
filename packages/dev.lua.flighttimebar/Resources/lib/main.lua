--[[
    FlightBar —— 在玩家头顶显示飞行时间条（LuaLoader / Terraria PE 1.4.5）

    绘制路线：
      * 钩 Main.Draw(GameTime) 的 postfix：此时游戏自己的批次已经 End。
      * 用 PE 的 SpriteBatch.Begin(SpriteSortMode, deferredBatch)（2 参）重新开批次。
        这个重载在 PE 上会带上世界相机变换（LuaLoader 源码注释里写明），
        所以直接按「世界坐标」画，不需要自己算屏幕坐标。
      * 用 Utils.DrawRect(SpriteBatch, Rectangle, Color) 画实心矩形。
      * SpriteBatch.End()。

    PS：8 参 Begin 的 Matrix? 参数在 patchlib 里不是 PATCH_STRUCT，
        没法用 struct_arg 传，所以不走单位矩阵 + 屏幕坐标那条路。

    数据来源（PE 1.4.5 字段）：
      Player.wingTime      float  剩余翅膀飞行时间（帧）
      Player.wingTimeMax   int    最大翅膀飞行时间（装备翅膀时 = WingStats.FlyTime）
      Player.rocketTime    int    剩余火箭靴时间
      Player.rocketTimeMax int    最大火箭靴时间
]]

local P   = mod.patch
local cfg = require("config")

local M = {}                 -- 反射句柄缓存
local S = {                  -- 运行状态
    ready              = false,
    no_batch_logged    = false,
    draw_error_logged  = false,
    begin_fail_logged  = false,
    first_call_logged  = false,
    first_stats_logged = false,
    first_draw_logged  = false,
}

local function err(msg)
    mod.error("[flightbar] " .. tostring(msg))
end

--- {R,G,B,A} -> 结构体参数；PE 的 Color 字段顺序是 A,B,G,R
local function color_struct(c)
    return P.struct_arg(
            { "uint8", "uint8", "uint8", "uint8" },
            { c[4] or 255, c[3] or 0, c[2] or 0, c[1] or 0 })
end

local function init()
    -- 类型
    M.main     = P.get_type("Terraria", "Main")
    M.player   = P.get_type("Terraria", "Player")
    M.utils    = P.get_type("Terraria", "Utils")
    M.sb_type  = P.get_type("Microsoft.Xna.Framework.Graphics", "SpriteBatch")
    M.rect_type = P.get_type("Microsoft.Xna.Framework", "Rectangle")
    M.color_type = P.get_type("Microsoft.Xna.Framework.Graphics", "Color")

    if not (M.main and M.player and M.utils and M.sb_type and M.rect_type and M.color_type) then
        return false, "缺少类型 Main / Player / Utils / SpriteBatch / Rectangle / Color"
    end

    -- Main 成员
    M.f_sb      = P.get_field(M.main, "spriteBatch")
    M.f_players = P.get_field(M.main, "player")

    local prop_menu = P.get_property(M.main, "gameMenu")
    if prop_menu then M.m_game_menu = P.property_get_method(prop_menu) end

    local prop_my = P.get_property(M.main, "myPlayer")
    if prop_my then M.m_my_player = P.property_get_method(prop_my) end

    if not (M.f_sb and M.f_players and M.m_game_menu and M.m_my_player) then
        return false, "Main 的 spriteBatch / player / gameMenu / myPlayer 有缺失"
    end

    -- Player 成员（position/velocity/width 在父类 Entity 上，get_field 会向上找）
    local player_fields = {
        pos         = "position",
        vel         = "velocity",
        width       = "width",
        dead        = "dead",
        wing_time   = "wingTime",
        wing_max    = "wingTimeMax",
        rocket_time = "rocketTime",
        rocket_max  = "rocketTimeMax",
    }
    for key, name in pairs(player_fields) do
        M["f_" .. key] = P.get_field(M.player, name)
        if not M["f_" .. key] then
            return false, "Player." .. name .. " 缺失"
        end
    end

    -- PE 专用的 2 参 Begin(SpriteSortMode, deferredBatch)：带世界相机变换
    M.m_begin = P.get_method(M.sb_type, "Begin", 2)
    M.m_end   = P.get_method(M.sb_type, "End", 0)
    if not (M.m_begin and M.m_end) then
        return false, "SpriteBatch.Begin(2 参) / End 缺失"
    end
    M.f_begin_called = P.get_field(M.sb_type, "_beginCalled")

    -- Utils.DrawRect(SpriteBatch, Rectangle, Color)（同名 3 参重载还有 Vector2 版，按类型选）
    M.m_draw_rect = P.get_method_by_param_types(M.utils, "DrawRect",
            { M.sb_type, M.rect_type, M.color_type })
    if not M.m_draw_rect then
        return false, "Utils.DrawRect(SpriteBatch, Rectangle, Color) 缺失"
    end

    -- 预建颜色结构体
    M.c_outline = color_struct(cfg.colors.outline)
    M.c_empty   = color_struct(cfg.colors.empty)
    M.c_high    = color_struct(cfg.colors.high)
    M.c_mid     = color_struct(cfg.colors.mid)
    M.c_low     = color_struct(cfg.colors.low)

    return true
end

local function draw_rect(sb, x, y, w, h, color)
    if w <= 0 or h <= 0 then return true end
    local rect = P.struct_arg(
            { "int32", "int32", "int32", "int32" },
            { x, y, w, h })
    local ok = P.invoke_value_args(M.m_draw_rect, { sb, rect, color })
    if ok == false and not S.draw_error_logged then
        S.draw_error_logged = true
        err("invoke_value_args(Utils.DrawRect) 失败，可能是内核按值结构体调用不可用")
    end
    return ok
end

local function draw()
    local first_call = not S.first_call_logged
    if first_call then S.first_call_logged = true end

    local sb = P.get_field_value(M.f_sb, nil, "object")
    if not sb then
        if first_call then mod.warn("[flightbar] 首次回调：拿不到 Main.spriteBatch") end
        return
    end

    -- 保险：如果游戏批次还没 End，就不去重复 Begin
    if M.f_begin_called and P.get_field_value(M.f_begin_called, sb, "bool") == true then
        if not S.no_batch_logged then
            S.no_batch_logged = true
            mod.warn("[flightbar] Main.Draw 结束时批次仍处于 Begin，跳过本帧")
        end
        return
    end

    if P.invoke(M.m_game_menu) then
        if first_call then mod.info("[flightbar] 首次回调：处于主菜单，跳过") end
        return
    end

    local idx = P.invoke(M.m_my_player)
    if type(idx) ~= "number" or idx < 0 then return end

    local players = P.get_field_value(M.f_players, nil, "object")
    if not players then return end
    if idx >= P.array_length(players) then return end

    local p = P.array_at(players, idx)
    if not p or not P.is_valid(p) then return end
    if P.get_field_value(M.f_dead, p, "bool") then return end

    local px, py = P.get_field_vec2(M.f_pos, p)
    if not px then return end
    local _, vy = P.get_field_vec2(M.f_vel, p)
    local pw = P.get_field_value(M.f_width, p, "int32") or 0

    local wmax = P.get_field_value(M.f_wing_max, p, "int32") or 0
    local rmax = P.get_field_value(M.f_rocket_max, p, "int32") or 0

    if not S.first_stats_logged then
        S.first_stats_logged = true
        mod.info("[flightbar] 首次读到玩家：wingMax=" .. tostring(wmax) ..
                " rocketMax=" .. tostring(rmax) .. " vy=" .. tostring(vy) ..
                " worldPos=" .. tostring(px) .. "," .. tostring(py))
    end

    local cur, max
    if wmax > 0 then
        cur, max = (P.get_field_value(M.f_wing_time, p, "float") or 0), wmax
    elseif cfg.show_rocket and rmax > 0 then
        cur, max = (P.get_field_value(M.f_rocket_time, p, "int32") or 0), rmax
    else
        return
    end

    local airborne = (vy or 0) ~= 0
    if not (cfg.show_when_full or airborne or cur < max - 0.01) then return end

    local ratio = cur / max
    if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end

    -- 直接用世界坐标（2 参 Begin 的批次带世界相机变换）
    local bw, bh = cfg.bar_width, cfg.bar_height
    local x = math.floor(px + pw * 0.5 - bw * 0.5 + cfg.offset_x)
    local y = math.floor(py - cfg.gap - bh + cfg.offset_y)

    local fill = M.c_high
    if ratio <= 0.2 then fill = M.c_low
    elseif ratio <= 0.5 then fill = M.c_mid end

    -- 开批次（S Mode 0 = Deferred，deferredBatch = true）
    local began = P.invoke(M.m_begin, sb, 0, true)
    if began == false then
        if not S.begin_fail_logged then
            S.begin_fail_logged = true
            err("SpriteBatch.Begin(SpriteSortMode, bool) 调用失败")
        end
        return
    end

    local drew_ok = pcall(function()
        local o = cfg.outline
        if o > 0 then
            draw_rect(sb, x - o, y - o, bw + o * 2, bh + o * 2, M.c_outline)
        end
        draw_rect(sb, x, y, bw, bh, M.c_empty)
        local filled = math.floor(bw * ratio + 0.5)
        if filled > 0 then
            draw_rect(sb, x, y, filled, bh, fill)
        end
    end)

    pcall(function() P.invoke(M.m_end, sb) end)

    if not drew_ok then
        err("绘制矩形时出错")
        return
    end

    if not S.first_draw_logged then
        S.first_draw_logged = true
        mod.info("[flightbar] 开始绘制：世界坐标 x=" .. tostring(x) .. " y=" .. tostring(y) ..
                " ratio=" .. tostring(ratio))
    end
end

local function on_draw()
    local ok, e = pcall(draw)
    if not ok and not S.draw_error_logged then
        S.draw_error_logged = true
        err("绘制异常: " .. tostring(e))
    end
end

local function start()
    local ok, why = init()
    if not ok then
        err("初始化失败: " .. tostring(why))
        return
    end

    local method = P.get_method(M.main, "Draw", 1)
    if not method then
        err("找不到 Main.Draw(GameTime)")
        return
    end

    M.hook = P.install_hook(method, { postfix = on_draw })
    if not M.hook then
        err("安装绘制钩子失败")
        return
    end

    S.ready = true
    mod.info("[flightbar] 就绪：Main.Draw 后重开世界批次（世界坐标）")
end

function setup()
    local ok, e = pcall(start)
    if not ok then err("setup 异常: " .. tostring(e)) end
end

function cleanup()
    if M.hook then
        pcall(function() M.hook:remove() end)
        M.hook = nil
    end
    S.ready = false
end

mod.meta = { pkg_id = "dev.lua.flighttimebar", version = "1.2.0" }

todo_list = { "setup" }
