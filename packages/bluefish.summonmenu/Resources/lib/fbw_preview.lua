-- sd_preview.lua
-- World-space selection preview.
--
-- mod.gui can only paint inside its own window, so the range preview goes
-- through the game's renderer instead — the same recipe as FlightTimeBar:
--   hook Terraria.Main.Draw(GameTime) postfix, reopen the world batch with
--   PE's 2-arg Begin(SpriteSortMode, bool), paint with Terraria.Utils, End().
-- All coordinates are world pixels: tile * 16.
--
-- Primitives (all Utils.* share one coordinate convention: world coords with
-- Main.screenPosition subtracted internally, which is what FlightTimeBar
-- already proved works through this Begin overload):
--   * DrawLine(sb, v2, v2, Color, Color, width)  uniform colour when both
--     colors are equal (num2 collapses to 1 segment) -> solid fill / edges
--   * DrawRect(sb, Rectangle, Color)             fallback border only; its
--     3-arg DrawLine fades along each edge, which would hollow out corners

local U = require("fbw_util")
local P = U.P

local M = {}
local SD

local H = {}
local L = {
    hooked       = false,
    no_batch     = false,
    begin_fail   = false,
    err_logged   = false,
    drawn_logged = false,
}

-- straight RGBA; premultiplied on the way out because XNA's AlphaBlend (the
-- default for Begin) is a premultiplied-alpha blend state.
local C_FILL_IDLE = { 255,  64,  64,  96 }
local C_FILL_DRAG = { 255,  84,  84, 140 }
local C_BORDER    = { 255, 104, 104, 240 }
local C_GRID      = { 255, 104, 104,  64 }

local BORDER_W = 3   -- world px, straddles the box edge
local GRID_W   = 2   -- world px

-- PE's Color field order is A,B,G,R (instance layout: 4 bytes; the other
-- FieldOffsets in Color.cs are static fields and do not count).
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

-- Cached draw-arg tables. The SpriteBatch handle is borrowed (valid only for
-- the current call), so slot [1] is refreshed every frame; struct_arg handles
-- are owned by the Lua GC and reusable, which keeps a 30x30 drag from
-- allocating ~60 structs per frame.
local C = { key = nil }

local function set_sb(list, sb)
    for _, t in ipairs(list) do t[1] = sb end
end

local function build_args(sb, px, py, pw, ph, fill)
    local key = string.format("%d,%d,%d,%d,%s", px, py, pw, ph,
            fill == H.c_fill_drag and "d" or "i")
    if C.key == key then
        C.fill[1] = sb
        set_sb(C.edges, sb)
        set_sb(C.gv, sb)
        set_sb(C.gh, sb)
        if C.border then C.border[1] = sb end
        return
    end
    C.key = key

    -- one horizontal line through the middle, thickness = box height: the
    -- width overload centres the quad on the path, so this covers
    -- [py, py+ph] exactly
    C.fill = { sb, v2(px, py + ph * 0.5), v2(px + pw, py + ph * 0.5),
               fill, fill, ph }

    -- four edges straddling the box boundary (uniform colour, no fade)
    C.edges = {
        { sb, v2(px, py),           v2(px + pw, py),           H.c_border, H.c_border, BORDER_W },
        { sb, v2(px, py + ph),      v2(px + pw, py + ph),      H.c_border, H.c_border, BORDER_W },
        { sb, v2(px, py),           v2(px, py + ph),           H.c_border, H.c_border, BORDER_W },
        { sb, v2(px + pw, py),      v2(px + pw, py + ph),      H.c_border, H.c_border, BORDER_W },
    }

    -- fallback only, used when the width overload is unavailable
    C.border = { sb, rect(px, py, pw, ph), H.c_border }

    -- interior tile grid so the exact range stays readable
    C.gv, C.gh = {}, {}
    local tw, th = math.floor(pw / 16), math.floor(ph / 16)
    for i = 1, tw - 1 do
        local gx = px + i * 16
        C.gv[i] = { sb, v2(gx, py), v2(gx, py + ph), H.c_grid, H.c_grid, GRID_W }
    end
    for j = 1, th - 1 do
        local gy = py + j * 16
        C.gh[j] = { sb, v2(px, gy), v2(px + pw, gy), H.c_grid, H.c_grid, GRID_W }
    end
end

local function init()
    H.main    = U.try_type("Terraria", "Main")
    H.utils   = U.try_type("Terraria", "Utils")
    H.sb_t    = U.try_type("Microsoft.Xna.Framework.Graphics", "SpriteBatch")
    H.rect_t  = U.try_type("Microsoft.Xna.Framework", "Rectangle")
    H.color_t = U.try_type("Microsoft.Xna.Framework.Graphics", "Color")
    H.vec2_t  = U.try_type("Microsoft.Xna.Framework", "Vector2")
    if not (H.main and H.utils and H.sb_t and H.rect_t and H.color_t and H.vec2_t) then
        return false, "missing types Main/Utils/SpriteBatch/Rectangle/Color/Vector2"
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

    H.m_line = try_call(P.get_method_by_param_types, H.utils, "DrawLine",
            { H.sb_t, H.vec2_t, H.vec2_t, H.color_t, H.color_t, float_t })
    H.m_rect = try_call(P.get_method_by_param_types, H.utils, "DrawRect",
            { H.sb_t, H.rect_t, H.color_t })

    if not H.m_line and not H.m_rect then
        return false, "no Utils.DrawLine(width) and no Utils.DrawRect"
    end
    if not H.m_line then
        U.log_warn("[FBW] preview: DrawLine(width) missing, outline only via DrawRect")
    end

    H.c_fill_idle = color_struct(C_FILL_IDLE)
    H.c_fill_drag = color_struct(C_FILL_DRAG)
    H.c_border    = color_struct(C_BORDER)
    H.c_grid      = color_struct(C_GRID)
    return true
end

local function draw()
    local S = SD.S
    if not S or not S.held then return end
    if (S.net_mode or 0) ~= 0 then return end
    if not SD.bind or not SD.bind.world() then return end
    if not SD.job or not SD.job.preview_rect then return end

    -- exactly the rect the blast would cover
    local x1, y1, x2, y2 = SD.job.preview_rect()
    if not x1 then return end

    local sb = P.get_field_value(H.f_sb, nil, "object")
    if not sb then return end

    -- the game's own batch is still open: skip, never double-Begin
    if H.f_begun and P.get_field_value(H.f_begun, sb, "bool") == true then
        if not L.no_batch then
            L.no_batch = true
            U.log_warn("[FBW] preview: batch still Begin at Main.Draw end, skipping frame")
        end
        return
    end

    local px, py = x1 * 16, y1 * 16
    local pw, ph = (x2 - x1 + 1) * 16, (y2 - y1 + 1) * 16

    local began = P.invoke(H.m_begin, sb, 0, true)
    if began == false then
        if not L.begin_fail then
            L.begin_fail = true
            U.log_error("[FBW] preview: SpriteBatch.Begin(SpriteSortMode, bool) failed")
        end
        return
    end

    -- Everything below runs inside pcall and End is always called: a throw
    -- between Begin and End would leave the batch open and every later frame
    -- would be rejected by the _beginCalled guard above.
    local errs = {}
    local ok, exc = pcall(function()
        local fill = S.dragging and H.c_fill_drag or H.c_fill_idle
        build_args(sb, px, py, pw, ph, fill)

        -- each step is isolated: a broken fill must not cost us the outline
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
            -- interior grid is cosmetic: a failure here must not sink the box
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
            U.log_error("[FBW] preview: draw exception: " .. tostring(exc))
        end
        return
    end

    if #errs > 0 then
        if not L.err_logged then
            L.err_logged = true
            U.log_error("[FBW] preview: draw failed: " .. table.concat(errs, " | "))
        end
        return
    end

    if not L.drawn_logged then
        L.drawn_logged = true
        U.log_info(string.format("[FBW] preview: first draw rect=%d,%d..%d,%d (%dx%d tiles)",
            x1, y1, x2, y2, x2 - x1 + 1, y2 - y1 + 1))
    end
end

local function frame()
    if not L.hooked then return end
    local ok, err = pcall(draw)
    if not ok and not L.err_logged then
        L.err_logged = true
        U.log_error("[FBW] preview: exception: " .. tostring(err))
    end
end

function M.setup(ctx)
    SD = ctx
    if type(P.struct_arg) ~= "function" or type(P.invoke_value_args) ~= "function" then
        U.log_error("[FBW] preview: kernel lacks struct_arg/invoke_value_args, preview disabled")
        return false
    end

    local ok, a, b = pcall(init)
    if not ok then
        U.log_error("[FBW] preview: init exception: " .. tostring(a))
        return false
    end
    if not a then
        U.log_error("[FBW] preview: " .. tostring(b))
        return false
    end

    local m = U.find_method(H.main, "Draw", 1)
    if not m then
        U.log_error("[FBW] preview: Main.Draw(GameTime) not found")
        return false
    end

    local okh, h = pcall(P.install_hook, m, { postfix = frame })
    if not okh or not h then
        U.log_error("[FBW] preview: hook install failed: " .. tostring(h))
        return false
    end

    H.hook = h
    L.hooked = true
    U.log_info("[FBW] preview: ready (world batch after Main.Draw, translucent red box)")
    return true
end

function M.cleanup()
    if H.hook then
        pcall(H.hook.remove, H.hook)
        H.hook = nil
    end
    L.hooked = false
end

function M.ready() return L.hooked end

return M
