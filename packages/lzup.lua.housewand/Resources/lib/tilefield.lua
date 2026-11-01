-- tilefield.lua —— 读普通图格信息（改编自平台魔杖）
--
-- 安卓端 Terraria.Tile 是值类型，Framing.GetTileSafely 按值返回 struct，
-- Lua 拿不到返回值。改走 TileData 的坐标索引接口：
--   index = x + maxTilesX * y
--   TileData.GetType(index) -> 图格类型（0 = 空气）

local q = mod.quickapi
local patch = mod.patch

local M = {}
local h = {}
local ready = false
local warned = false

local function warn_once(msg)
    if warned then return end
    warned = true
    if mod.warn then mod.warn("[房屋魔杖] tilefield: " .. tostring(msg)) end
end

local function try(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

local function ensure()
    if ready then return true end
    h.mGetType = try(q.method, "Terraria", "TileData", "GetType", 1)
    h.mGetWall = try(q.method, "Terraria", "TileData", "GetWall", 1)
    h.fMaxTilesX = try(q.field, "Terraria", "Main", "maxTilesX")
    h.fTileCut = try(q.field, "Terraria", "Main", "tileCut")
    if h.fTileCut then
        h.arrTileCut = try(patch.get_field_value, h.fTileCut, nil, "object")
    end
    if not (h.mGetType and h.fMaxTilesX) then
        warn_once("找不到 TileData.GetType / Main.maxTilesX")
        return false
    end
    ready = true
    return true
end

local function index_of(x, y)
    local w = try(patch.get_field_value, h.fMaxTilesX, nil, "int32")
    if not w or type(w) ~= "number" then return nil end
    return x + w * y
end

-- 取 (x, y) 的图格类型；失败返回 -1。il2cpp 调用全程 pcall 防崩。
function M.type_at(x, y)
    if not ensure() then return -1 end
    local idx = index_of(x, y)
    if not idx then return -1 end
    local t = try(q.call, h.mGetType, idx)
    if type(t) ~= "number" then return -1 end
    return t
end

-- 取 (x, y) 的墙类型；失败返回 -1。
function M.wall_at(x, y)
    if not ensure() then return -1 end
    if not h.mGetWall then return -1 end
    local idx = index_of(x, y)
    if not idx then return -1 end
    local t = try(q.call, h.mGetWall, idx)
    if type(t) ~= "number" then return -1 end
    return t
end

local function is_cut(t)
    if not h.arrTileCut then return false end
    local n = patch.array_length(h.arrTileCut) or 0
    if t < 0 or t >= n then return false end
    return patch.array_at(h.arrTileCut, t, "bool") == true
end

-- 分类：
--   "empty" 空格，可放
--   "cut"   可砍图格（草/藤/花等），摧毁后即可放
--   "solid" 硬块 / 已有家具，停止
--   "error" 读取失败（句柄没解析好），不能当“实心”处理
function M.classify(x, y)
    if not ensure() then return "error" end
    local t = M.type_at(x, y)
    if t < 0 then return "error" end
    if t == 0 then return "empty" end
    if is_cut(t) then return "cut" end
    return "solid"
end

-- 摧毁一个可砍图格。
function M.kill(x, y)
    h.mKill = h.mKill or try(q.method, "Terraria", "WorldGen", "KillTile", 5)
    if not h.mKill then return false end
    return try(q.call, h.mKill, x, y, false, false, false) == true
end

return M
