-- lw_preview.lua —— 液体魔杖的「范围预览」（半透明色框 + 逐格网格线）
--
-- 参考法爆魔杖的纯几何画法：
--   hook Terraria.Main.Draw(GameTime) postfix
--   → SpriteBatch.Begin(SpriteSortMode, bool)   （PE 只有这个 2 参重载）
--   → Terraria.Utils.DrawLine(sb, v2, v2, Color, Color, width)
--   → SpriteBatch.End()
-- 全部是纯几何绘制，不碰图格数据，也不依赖 TileObjectData。
--
-- 颜色按当前模式取（lw_placement.MODE_COLOR）：
--   生成水 = 蓝 / 生成熔岩 = 红 / 生成蜂蜜 = 黄 / 清除液体 = 紫
--
-- 坐标：世界像素 = 图格 * 16。

local U = require("fbw_util")
local P = U.P
local geom = require("lw_placement")
local state = require("lw_state")

local q = mod.quickapi

local M = {}

local H = {}
local L = {
    hooked     = false,
    no_batch   = false,
    begin_fail = false,
    err_logged = false,
}

local BORDER_W = 3   -- 世界像素，骑在框线上
local GRID_W   = 2

-- 填充 / 边框 / 网格的不透明度
local A_FILL_IDLE = 56
local A_FILL_DRAG = 92
local A_BORDER    = 240
local A_GRID      = 56

-- ==================== 结构体小工具 ====================

-- PE 的 Color 字段顺序是 A,B,G,R（实例布局 4 字节）
local function color_struct(c)
    local a = c[4] or 255
    local function pm(v) return math.floor(v * a / 255 + 0.5) end
    return P.struct_arg({ "uint8", "uint8", "uint8", "uint8" },
            { a, pm(c[3]), pm(c[2]), pm(c[1]) })
end

local function v2(x, y)
    return P.struct_arg({ "float", "float" }, { x, y })
end

local function rect(x, y, w, h)
    return P.struct_arg({ "int32", "int32", "int32", "int32" }, { x, y, w, h })
end

local function try_call(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- 绘制参数缓存：矩形 + 模式不变时直接复用上一帧的结构体
local C = { key = nil }

local function set_sb(list, sb)
    for _, t in ipairs(list) do t[1] = sb end
end

local function build_args(sb, mode, px, py, pw, ph, framing)
    local key = string.format("%d,%d,%d,%d,%s,%s", px, py, pw, ph, mode,
            framing and "d" or "i")
    if C.key == key then
        C.fill[1] = sb
        set_sb(C.edges, sb)
        set_sb(C.gv, sb)
        set_sb(C.gh, sb)
        if C.border then C.border[1] = sb end
        return
    end
    C.key = key

    local c_fill = framing and H.fill_drag[mode] or H.fill_idle[mode]
    local c_border = H.border[mode]
    local c_grid = H.grid[mode]

    -- 一条贯穿中线、粗细等于框高的横线 = 实心填充
    C.fill = { sb, v2(px, py + ph * 0.5), v2(px + pw, py + ph * 0.5),
               c_fill, c_fill, ph }

    -- 四条边（同色不做渐变，拐角才不会是空心的）
    C.edges = {
        { sb, v2(px, py),      v2(px + pw, py),      c_border, c_border, BORDER_W },
        { sb, v2(px, py + ph), v2(px + pw, py + ph), c_border, c_border, BORDER_W },
        { sb, v2(px, py),      v2(px, py + ph),      c_border, c_border, BORDER_W },
        { sb, v2(px + pw, py), v2(px + pw, py + ph), c_border, c_border, BORDER_W },
    }

    C.border = { sb, rect(px, py, pw, ph), c_border }

    -- 内部逐格网格线，方便数格子
    C.gv, C.gh = {}, {}
    local tw = math.floor(pw / 16)
    local th = math.floor(ph / 16)
    for i = 1, tw - 1 do
        local gx = px + i * 16
        C.gv[i] = { sb, v2(gx, py), v2(gx, py + ph), c_grid, c_grid, GRID_W }
    end
    for j = 1, th - 1 do
        local gy = py + j * 16
        C.gh[j] = { sb, v2(px, gy), v2(px + pw, gy), c_grid, c_grid, GRID_W }
    end
end

-- ==================== 初始化 ====================

local function init()
    H.main   = U.try_type("Terraria", "Main")
    H.utils  = U.try_type("Terraria", "Utils")
    H.sb_t   = U.try_type("Microsoft.Xna.Framework.Graphics", "SpriteBatch")
    H.rect_t = U.try_type("Microsoft.Xna.Framework", "Rectangle")
    H.color_t = U.try_type("Microsoft.Xna.Framework.Graphics", "Color")
    H.vec2_t = U.try_type("Microsoft.Xna.Framework", "Vector2")
    -- Color 句柄不是必需的：颜色用 struct_arg 直接拼字节。
    if not (H.main and H.utils and H.sb_t and H.rect_t and H.vec2_t) then
        return false, "missing types Main/Utils/SpriteBatch/Rectangle/Vector2"
    end

    H.f_sb    = U.find_field(H.main, "spriteBatch")
    H.m_begin = U.find_method(H.sb_t, "Begin", 2)
    H.m_end   = U.find_method(H.sb_t, "End", 0)
    H.f_begun = U.find_field(H.sb_t, "_beginCalled")
    if not (H.f_sb and H.m_begin and H.m_end) then
        return false, "Main.spriteBatch / SpriteBatch.Begin(2) / End missing"
    end

    local float_t = try_call(P.get_basic_type, "float")
    if not float_t then return false, "float basic type missing" end

    if H.color_t then
        H.m_line = try_call(P.get_method_by_param_types, H.utils, "DrawLine",
                { H.sb_t, H.vec2_t, H.vec2_t, H.color_t, H.color_t, float_t })
        H.m_rect = try_call(P.get_method_by_param_types, H.utils, "DrawRect",
                { H.sb_t, H.rect_t, H.color_t })
    end
    -- 降级：按参数个数找（DrawLine = 6 参；DrawRect = 3 参）
    if not H.m_line then H.m_line = U.find_method(H.utils, "DrawLine", 6) end
    if not H.m_rect then H.m_rect = U.find_method(H.utils, "DrawRect", 3) end
    if not H.m_line and not H.m_rect then
        return false, "no Utils.DrawLine and no Utils.DrawRect"
    end

    -- 四种模式各一套颜色
    H.fill_idle, H.fill_drag, H.border, H.grid = {}, {}, {}, {}
    for _, mode in ipairs(geom.MODE_ORDER) do
        local c = geom.MODE_COLOR[mode]
        H.fill_idle[mode] = color_struct({ c[1], c[2], c[3], A_FILL_IDLE })
        H.fill_drag[mode] = color_struct({ c[1], c[2], c[3], A_FILL_DRAG })
        H.border[mode]    = color_struct({ c[1], c[2], c[3], A_BORDER })
        H.grid[mode]      = color_struct({ c[1], c[2], c[3], A_GRID })
    end
    return true
end

-- ==================== 取范围 ====================

-- 范围由 lw_drag.tick 每帧算好后写进 state，这里只负责画。
local function current_rect()
    if not state.preview_on then return nil end
    local x1, x2, y1, y2 = state.px1, state.px2, state.py1, state.py2
    if type(x1) ~= "number" or type(x2) ~= "number" then return nil end
    if type(y1) ~= "number" or type(y2) ~= "number" then return nil end
    return x1, x2, y1, y2
end

-- ==================== 每帧绘制 ====================

local function draw()
    local x1, x2, y1, y2 = current_rect()
    if not x1 then return end

    local mode = state.preview_mode or state.mode
    if not H.border[mode] then mode = geom.MODE_WATER end

    local width = q.get_field_value("Terraria", "Main", "maxTilesX", nil, "int32")
    local height = q.get_field_value("Terraria", "Main", "maxTilesY", nil, "int32")
    if type(width) ~= "number" or type(height) ~= "number" then return end
    local margin = geom.WORLD_MARGIN
    if x1 < margin then x1 = margin end
    if x2 >= width - margin then x2 = width - margin - 1 end
    if y1 < margin then y1 = margin end
    if y2 >= height - margin then y2 = height - margin - 1 end
    if x1 > x2 or y1 > y2 then return end

    local sb = P.get_field_value(H.f_sb, nil, "object")
    if not sb then return end

    -- 原版 batch 还没 End：直接跳过这一帧，绝不重复 Begin
    if H.f_begun and P.get_field_value(H.f_begun, sb, "bool") == true then
        if not L.no_batch then
            L.no_batch = true
            U.log_warn("[液体魔杖] 预览：Main.Draw 结束时 batch 仍处于 Begin，跳过该帧")
        end
        return
    end

    local px, py = x1 * 16, y1 * 16
    local pw, ph = (x2 - x1 + 1) * 16, (y2 - y1 + 1) * 16

    local began = P.invoke(H.m_begin, sb, 0, true)
    if began == false then
        if not L.begin_fail then
            L.begin_fail = true
            U.log_error("[液体魔杖] 预览：SpriteBatch.Begin(SpriteSortMode, bool) 失败")
        end
        return
    end

    local errs = {}
    local ok, exc = pcall(function()
        -- 多于一格就算「在框」，用深一点的填充
        local framing = (x2 > x1) or (y2 > y1)
        build_args(sb, mode, px, py, pw, ph, framing)

        local function step(what, m, args)
            local ok2, r = pcall(P.invoke_value_args, m, args)
            if not ok2 then
                errs[#errs + 1] = what .. ": " .. tostring(r)
            elseif r == false then
                errs[#errs + 1] = what .. ": returned false"
            end
        end

        if H.m_line then
            step("fill", H.m_line, C.fill)
            for _, t in ipairs(C.edges) do step("edge", H.m_line, t) end
            -- 网格线只是装饰，画不出来不影响主体
            local gerr = #errs
            for _, t in ipairs(C.gv) do step("grid", H.m_line, t) end
            for _, t in ipairs(C.gh) do step("grid", H.m_line, t) end
            for _ = #errs, gerr + 1, -1 do table.remove(errs) end
        else
            step("border", H.m_rect, C.border)
        end
    end)

    pcall(P.invoke, H.m_end, sb)

    if not ok then
        if not L.err_logged then
            L.err_logged = true
            U.log_error("[液体魔杖] 预览：绘制异常：" .. tostring(exc))
        end
        return
    end
    if #errs > 0 then
        if not L.err_logged then
            L.err_logged = true
            U.log_error("[液体魔杖] 预览：绘制失败：" .. table.concat(errs, " | "))
        end
        return
    end
end

local function frame()
    if not L.hooked then return end
    local ok, err = pcall(draw)
    if not ok and not L.err_logged then
        L.err_logged = true
        U.log_error("[液体魔杖] 预览：异常：" .. tostring(err))
    end
end

-- ==================== 安装 ====================

function M.install()
    if L.hooked then return true end
    if type(P.struct_arg) ~= "function" or type(P.invoke_value_args) ~= "function" then
        U.log_error("[液体魔杖] 预览：内核缺少 struct_arg/invoke_value_args，预览不可用")
        return false
    end

    local ok, a, b = pcall(init)
    if not ok then
        U.log_error("[液体魔杖] 预览：init 异常：" .. tostring(a))
        return false
    end
    if not a then
        U.log_error("[液体魔杖] 预览：" .. tostring(b))
        return false
    end

    local m = U.find_method(H.main, "Draw", 1)
    if not m then
        U.log_error("[液体魔杖] 预览：找不到 Main.Draw(GameTime)")
        return false
    end

    local okh, h = pcall(P.install_hook, m, { postfix = frame })
    if not okh or not h then
        U.log_error("[液体魔杖] 预览：钩子安装失败：" .. tostring(h))
        return false
    end

    H.hook = h
    L.hooked = true
    U.log_info("[液体魔杖] 预览：已就绪（四色范围框）")
    return true
end

function M.cleanup()
    if H.hook then
        pcall(H.hook.remove, H.hook)
        H.hook = nil
    end
    L.hooked = false
end

return M