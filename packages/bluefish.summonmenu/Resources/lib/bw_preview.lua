-- bw_preview.lua —— 物块魔杖的「框选范围预览」（灰色半透明框 + 逐格网格线）
--
-- 为什么不用 TileObject.DrawPreview：
--   平台魔杖走的是原版家具幽灵那套，而它依赖 TileObjectData。
--   灰砖（图格 38）是普通方块，没有 TileObjectData，native 侧会越界 → 闪退。
--
-- 所以这里照抄法爆魔杖的做法：hook Terraria.Main.Draw(GameTime) postfix，
-- 用 PE 的 2 参 SpriteBatch.Begin(SpriteSortMode, bool) 重新开一个 world batch，
-- 再用 Terraria.Utils.DrawLine 画填充 / 边框 / 网格线，最后 End()。
-- 全部是纯几何绘制，不碰图格数据，任何方块类型都能画。
--
-- 坐标：世界像素 = 图格 * 16。

local U = require("fbw_util")
local P = U.P
local geom = require("bw_placement")
local state = require("bw_state")

local q = mod.quickapi

local M = {}

local H = {}
local L = {
    hooked       = false,
    no_batch     = false,
    begin_fail   = false,
    err_logged   = false,
}

-- 灰色系（顺序 R,G,B,A；写出去时会按 XNA 的预乘 alpha 转换）
local C_FILL_IDLE = { 200, 200, 200,  56 }
local C_FILL_DRAG = { 214, 214, 214,  92 }
local C_BORDER    = { 226, 226, 226, 240 }
local C_GRID      = { 226, 226, 226,  56 }

local BORDER_W = 3   -- 世界像素，骑在框线上
local GRID_W   = 2

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

-- 绘制参数缓存：矩形不变时直接复用上一帧的结构体，避免每帧几十次分配
local C = { key = nil }

local function set_sb(list, sb)
    for _, t in ipairs(list) do t[1] = sb end
end

local function build_args(sb, px, py, pw, ph, fill, fill_key, horizontal)
    local key = string.format("%d,%d,%d,%d,%s,%s", px, py, pw, ph, fill_key,
            horizontal and "h" or "v")
    if C.key == key then
        C.fill[1] = sb
        set_sb(C.edges, sb)
        set_sb(C.gv, sb)
        set_sb(C.gh, sb)
        if C.border then C.border[1] = sb end
        return
    end
    C.key = key

    -- 一条贯穿中线、粗细等于框高的横线 = 实心填充
    C.fill = { sb, v2(px, py + ph * 0.5), v2(px + pw, py + ph * 0.5),
               fill, fill, ph }

    -- 四条边（同色不做渐变，拐角才不会是空心的）
    C.edges = {
        { sb, v2(px, py),      v2(px + pw, py),      H.c_border, H.c_border, BORDER_W },
        { sb, v2(px, py + ph), v2(px + pw, py + ph), H.c_border, H.c_border, BORDER_W },
        { sb, v2(px, py),      v2(px, py + ph),      H.c_border, H.c_border, BORDER_W },
        { sb, v2(px + pw, py), v2(px + pw, py + ph), H.c_border, H.c_border, BORDER_W },
    }

    C.border = { sb, rect(px, py, pw, ph), H.c_border }

    -- 内部逐格网格线，方便数格子
    C.gv, C.gh = {}, {}
    local tw = math.floor(pw / 16)
    local th = math.floor(ph / 16)
    for i = 1, tw - 1 do
        local gx = px + i * 16
        C.gv[i] = { sb, v2(gx, py), v2(gx, py + ph), H.c_grid, H.c_grid, GRID_W }
    end
    for j = 1, th - 1 do
        local gy = py + j * 16
        C.gh[j] = { sb, v2(px, gy), v2(px + pw, gy), H.c_grid, H.c_grid, GRID_W }
    end

    -- 火把位置标记：只在横向（一行）时画。
    -- 相位与 bw_drag.M.place 一致：每 BRICK_STEP(10) 格一组，组内第 TORCH_OFFSET(4) 格。
    -- 位置在砖的上方一格，画一个 8×8 的暖橙小方块表示火把。
end

-- ==================== 初始化 ====================

local function init()
    H.main    = U.try_type("Terraria", "Main")
    H.utils   = U.try_type("Terraria", "Utils")
    H.sb_t    = U.try_type("Microsoft.Xna.Framework.Graphics", "SpriteBatch")
    H.rect_t  = U.try_type("Microsoft.Xna.Framework", "Rectangle")
    H.color_t = U.try_type("Microsoft.Xna.Framework.Graphics", "Color")
    H.vec2_t  = U.try_type("Microsoft.Xna.Framework", "Vector2")
    -- Color 句柄不是必需的：颜色用 struct_arg 直接拼字节，不依赖类型句柄。
    -- （日志里出现过 "Type not found: Microsoft.Xna.Framework.Color"，不能因为这里就整个放弃）
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
    -- 降级：按参数个数找（DrawLine(sb, v2, v2, c, c, w) = 6 参；DrawRect(sb, rect, c) = 3 参）
    if not H.m_line then
        H.m_line = U.find_method(H.utils, "DrawLine", 6)
    end
    if not H.m_rect then
        H.m_rect = U.find_method(H.utils, "DrawRect", 3)
    end
    if not H.m_line and not H.m_rect then
        return false, "no Utils.DrawLine and no Utils.DrawRect"
    end

    H.c_fill_idle = color_struct(C_FILL_IDLE)
    H.c_fill_drag = color_struct(C_FILL_DRAG)
    H.c_border    = color_struct(C_BORDER)
    H.c_grid      = color_struct(C_GRID)
    return true
end

-- ==================== 取坐标 ====================

-- 范围由 bw_drag.tick 每帧算好后写进 state，这里只负责画。
-- 不在预览里重复做手持判定/坐标计算：那部分逻辑只保留一份，少一处出错的地方。
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

    -- 裁到地图内（图格编号）
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
            U.log_warn("[物块魔杖] 预览：Main.Draw 结束时 batch 仍处于 Begin，跳过该帧")
        end
        return
    end

    local px, py = x1 * 16, y1 * 16
    local pw, ph = (x2 - x1 + 1) * 16, (y2 - y1 + 1) * 16

    local began = P.invoke(H.m_begin, sb, 0, true)
    if began == false then
        if not L.begin_fail then
            L.begin_fail = true
            U.log_error("[物块魔杖] 预览：SpriteBatch.Begin(SpriteSortMode, bool) 失败")
        end
        return
    end

    local errs = {}
    local ok, exc = pcall(function()
        -- 多于一格就算「在框」，用深一点的填充
        local framing = (x2 > x1) or (y2 > y1)
        local fill = framing and H.c_fill_drag or H.c_fill_idle
        build_args(sb, px, py, pw, ph, fill, framing and "d" or "i", y1 == y2)

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
            U.log_error("[物块魔杖] 预览：绘制异常：" .. tostring(exc))
        end
        return
    end
    if #errs > 0 then
        if not L.err_logged then
            L.err_logged = true
            U.log_error("[物块魔杖] 预览：绘制失败：" .. table.concat(errs, " | "))
        end
        return
    end

end

local function frame()
    if not L.hooked then return end
    local ok, err = pcall(draw)
    if not ok and not L.err_logged then
        L.err_logged = true
        U.log_error("[物块魔杖] 预览：异常：" .. tostring(err))
    end
end

-- ==================== 安装 ====================

-- ==================== 火把幽灵（借平台魔杖的钩子环境） ====================
-- 为什么不在 Main.Draw 里顺手画：
-- 原版 TileObject.DrawPreview 的 position 语义是「渲染图格那一刻的 Main.screenPosition」，
-- 而 Main.Draw 阶段 screenPosition 已经是别的值了，照抄会整体偏移——上一版就是这么歪的。
-- 所以火把必须和平台魔杖在同一个钩子里画。
--
-- 为什么不自己再挂一个 TileDrawing.Draw 后缀：
-- 同一方法挂两次后置钩子可能互相覆盖，把平台魔杖自己的预览挤掉。
-- 这里改成回调：pt_preview 的钩子在画完自己的幽灵后顺带调我们。

-- 收集本帧要画的火把格。只看物块魔杖自己的 state。
local function collect_torches()
    if not state or not state.preview_on then return nil end
    local x1, x2 = state.px1, state.px2
    local y1, y2 = state.py1, state.py2
    if type(x1) ~= "number" or type(x2) ~= "number" then return nil end
    if type(y1) ~= "number" or type(y2) ~= "number" then return nil end

    -- 只有一行（横向）时才有火把；竖向不画，与铺放逻辑一致。
    if y1 ~= y2 then return nil end
    if y1 - 1 < 0 then return nil end

    local list = {}
    for tx = x1, x2 do
        if (tx - x1) % geom.BRICK_STEP == geom.TORCH_OFFSET then
            list[#list + 1] = { tx = tx, ty = y1 - 1 }
        end
    end
    if #list == 0 then return nil end
    return list
end

-- pt_preview 的钩子每帧调这个（在实心层那次 Draw 之后）
local function draw_torches_here()
    local list = collect_torches()
    if not list then return end
    local ok, PT = pcall(require, "pt_preview")
    if not ok or type(PT) ~= "table" then return end
    if type(PT.frame_ctx) ~= "function" then return end
    local sb, op, dargs = PT.frame_ctx()
    if not sb then return end
    PT.draw_torches_in_batch(list, sb, op, dargs)
end

function M.install()
    if L.hooked then return true end
    if type(P.struct_arg) ~= "function" or type(P.invoke_value_args) ~= "function" then
        U.log_error("[物块魔杖] 预览：内核缺少 struct_arg/invoke_value_args，预览不可用")
        return false
    end

    local ok, a, b = pcall(init)
    if not ok then
        U.log_error("[物块魔杖] 预览：init 异常：" .. tostring(a))
        return false
    end
    if not a then
        U.log_error("[物块魔杖] 预览：" .. tostring(b))
        return false
    end

    local m = U.find_method(H.main, "Draw", 1)
    if not m then
        U.log_error("[物块魔杖] 预览：找不到 Main.Draw(GameTime)")
        return false
    end

    local okh, h = pcall(P.install_hook, m, { postfix = frame })
    if not okh or not h then
        U.log_error("[物块魔杖] 预览：钩子安装失败：" .. tostring(h))
        return false
    end

    H.hook = h
    L.hooked = true

    -- 火把幽灵：挂到平台魔杖的 TileDrawing.Draw 钩子上（环境一致，位置才对）
    local okp, PT = pcall(require, "pt_preview")
    if okp and type(PT) == "table" then
        PT.on_draw_extra = draw_torches_here
        U.log_info("[物块魔杖] 预览：已就绪（灰色范围框 + 火把幽灵）")
    else
        U.log_info("[物块魔杖] 预览：已就绪（灰色范围框，火把幽灵不可用）")
    end
    return true
end

function M.cleanup()
    local okp, PT = pcall(require, "pt_preview")
    if okp and type(PT) == "table" then PT.on_draw_extra = nil end
    if H.hook then
        pcall(H.hook.remove, H.hook)
        H.hook = nil
    end
    L.hooked = false
end

return M