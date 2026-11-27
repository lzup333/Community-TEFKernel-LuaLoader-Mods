-- sd_util.lua
-- Small reflection / text helpers shared by the other modules.
-- Everything here is defensive: a missing optional API must only disable one
-- feature, never raise into a hook callback.

local M = {}
local P = mod.patch
M.P = P

local function ok_handle(v)
    return v ~= nil and v ~= false
end

function M.try_type(ns, cls)
    if type(P.get_type) ~= "function" then return nil end
    local ok, t = pcall(P.get_type, ns, cls)
    if ok and ok_handle(t) then return t end
    if type(P.get_type_by_name) == "function" then
        local full = (ns and #ns > 0) and (ns .. "." .. cls) or cls
        local ok2, t2 = pcall(P.get_type_by_name, full)
        if ok2 and ok_handle(t2) then return t2 end
    end
    return nil
end

local function parent_of(t)
    if type(P.get_parent) ~= "function" then return nil end
    local ok, p = pcall(P.get_parent, t)
    if ok and ok_handle(p) then return p end
    return nil
end

function M.find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local ok, f = pcall(P.get_field, cur, name)
        if ok and ok_handle(f) then return f end
        local ok2, fb = pcall(P.get_field, cur, "<" .. name .. ">k__BackingField")
        if ok2 and ok_handle(fb) then return fb end
        cur = parent_of(cur)
        guard = guard + 1
    end
    return nil
end

function M.find_method(t, name, argc)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local ok, m
        if argc ~= nil then
            ok, m = pcall(P.get_method, cur, name, argc)
        else
            ok, m = pcall(P.get_method, cur, name)
        end
        if ok and ok_handle(m) then return m end
        cur = parent_of(cur)
        guard = guard + 1
    end
    return nil
end

-- Prefer the compiled getter (get_X), then the property handle. Backing fields
-- are handled by find_field for callers that read fields directly.
function M.prop_getter(t, name)
    local m = M.find_method(t, "get_" .. name, 0)
    if m then return m end
    if type(P.get_property) == "function" and type(P.property_get_method) == "function" then
        local ok, p = pcall(P.get_property, t, name)
        if ok and ok_handle(p) then
            local ok2, g = pcall(P.property_get_method, p)
            if ok2 and ok_handle(g) then return g end
        end
    end
    return nil
end

-- Invoke a zero-argument getter. inst is nil for static properties.
function M.call_int(m, inst)
    if not m then return nil end
    local ok, v
    if inst ~= nil then ok, v = pcall(P.invoke, m, inst)
    else ok, v = pcall(P.invoke, m) end
    if ok and type(v) == "number" and v == v then return v end
    return nil
end

function M.call_float(m, inst)
    return M.call_int(m, inst)
end

function M.call_bool(m, inst)
    if not m then return nil end
    local ok, v
    if inst ~= nil then ok, v = pcall(P.invoke, m, inst)
    else ok, v = pcall(P.invoke, m) end
    if not ok then return nil end
    if v == true then return true end
    if v == false then return false end
    if type(v) == "number" then return v ~= 0 end
    return nil
end

-- Read an integer field without trusting the declared width. On this mobile
-- build Item.type / Item.stack / Item.createTile are 2-byte fields, and a blind
-- "int32" read silently eats the neighbouring field.
function M.gf_int(field, inst)
    if not field then return 0 end
    if type(P.get_field_raw) == "function" then
        local ok, raw = pcall(P.get_field_raw, field, inst)
        if ok and type(raw) == "string" and #raw >= 1 and #raw <= 8 then
            local pok, v = pcall(string.unpack, "<i" .. #raw, raw)
            if pok and type(v) == "number" then return v end
        end
    end
    local ok2, v2 = pcall(P.get_field_value, field, inst)
    if ok2 and type(v2) == "number" then return v2 end
    local ok3, v3 = pcall(P.get_field_value, field, inst, "int32")
    if ok3 and type(v3) == "number" then return v3 end
    return 0
end

function M.gf_float(field, inst)
    if not field then return 0 end
    if type(P.get_field_raw) == "function" then
        local ok, raw = pcall(P.get_field_raw, field, inst)
        if ok and type(raw) == "string" and #raw == 4 then
            local pok, v = pcall(string.unpack, "<f", raw)
            if pok and type(v) == "number" then return v end
        end
    end
    local ok2, v2 = pcall(P.get_field_value, field, inst, "float")
    if ok2 and type(v2) == "number" then return v2 end
    return 0
end

function M.gf_bool(field, inst)
    if not field then return false end
    local ok, v = pcall(P.get_field_value, field, inst, "bool")
    if ok then
        if v == true then return true end
        if v == false then return false end
        if type(v) == "number" then return v ~= 0 end
    end
    if type(P.get_field_raw) == "function" then
        local ok2, raw = pcall(P.get_field_raw, field, inst)
        if ok2 and type(raw) == "string" and #raw >= 1 then
            return raw:byte(1) ~= 0
        end
    end
    return false
end

function M.read_vec2_field(field, inst)
    if not field then return nil end
    if type(P.get_field_vec2) == "function" then
        local ok, x, y = pcall(P.get_field_vec2, field, inst)
        if ok and type(x) == "number" and type(y) == "number" then return x, y end
    end
    if type(P.get_field_raw) == "function" then
        local ok, raw = pcall(P.get_field_raw, field, inst)
        if ok and type(raw) == "string" and #raw >= 8 then
            local pok, x, y = pcall(string.unpack, "<ff", raw)
            if pok and type(x) == "number" and type(y) == "number" then return x, y end
        end
    end
    return nil
end

local VEC2

local function vec2_xy(obj)
    if type(obj) == "table" then
        local x = obj.X or obj.x or obj[1]
        local y = obj.Y or obj.y or obj[2]
        if type(x) == "number" and type(y) == "number" then return x, y end
        return nil
    end
    if not VEC2 then
        VEC2 = M.try_type("Microsoft.Xna.Framework", "Vector2")
    end
    if VEC2 and obj then
        local fx = M.find_field(VEC2, "X")
        local fy = M.find_field(VEC2, "Y")
        if fx and fy then
            local okx, x = pcall(P.get_field_value, fx, obj, "float")
            local oky, y = pcall(P.get_field_value, fy, obj, "float")
            if okx and oky and type(x) == "number" and type(y) == "number" then return x, y end
        end
    end
    return nil
end

-- Read a Vector2-returning getter. Some kernels marshal the struct as two
-- return values, some return a boxed object, some a plain table.
function M.read_vec2_getter(m, inst)
    if not m then return nil end
    local ok, a, b
    if inst ~= nil then ok, a, b = pcall(P.invoke, m, inst)
    else ok, a, b = pcall(P.invoke, m) end
    if not ok then return nil end
    if type(a) == "number" and type(b) == "number" then return a, b end
    return vec2_xy(a)
end

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

function M.char_px(ch, gs, scale)
    return ((#ch == 1) and 10 or 20) * gs * (scale or 1)
end

function M.text_px(s, gs, scale)
    local w = 0
    for ch in tostring(s):gmatch(UTF8_CHAR) do w = w + M.char_px(ch, gs, scale) end
    return math.floor(w)
end

function M.fit_text(s, maxpx, gs, scale)
    s = tostring(s)
    if maxpx <= 0 then return "" end
    if M.text_px(s, gs, scale) <= maxpx then return s end
    local ell = M.char_px("…", gs, scale)
    local w, parts = 0, {}
    for ch in s:gmatch(UTF8_CHAR) do
        local cw = M.char_px(ch, gs, scale)
        if w + cw + ell > maxpx then break end
        parts[#parts + 1] = ch
        w = w + cw
    end
    if #parts == 0 then return "…" end
    return table.concat(parts) .. "…"
end

function M.ui_scale(sw, sh)
    if type(sw) ~= "number" or type(sh) ~= "number" or sw <= 0 or sh <= 0 then return 1.0 end
    local s = math.min(sw, sh) / 720.0
    if s < 1.0 then s = 1.0 end
    if s > 2.5 then s = 2.5 end
    return s
end

function M.clamp(v, lo, hi)
    if type(v) ~= "number" or v ~= v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.log_info(msg) pcall(mod.info, tostring(msg)) end
function M.log_warn(msg) pcall(mod.warn, tostring(msg)) end
function M.log_error(msg) pcall(mod.error, tostring(msg)) end

return M
