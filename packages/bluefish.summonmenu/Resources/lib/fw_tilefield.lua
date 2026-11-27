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
    h.mSolidTile = try(q.method, "Terraria", "WorldGen", "SolidTile", 2)
    h.mGetSHeader = try(q.method, "Terraria", "TileData", "GetSHeader", 1)
    h.mGetFrameX  = try(q.method, "Terraria", "TileData", "GetFrameX", 1)
    h.mGetFrameY  = try(q.method, "Terraria", "TileData", "GetFrameY", 1)
    h.mGetBHeader = try(q.method, "Terraria", "TileData", "GetBHeader", 1)
    h.mGetBHeader2 = try(q.method, "Terraria", "TileData", "GetBHeader2", 1)
    h.mGetBHeader3 = try(q.method, "Terraria", "TileData", "GetBHeader3", 1)
    h.mGetLiquid  = try(q.method, "Terraria", "TileData", "GetLiquid", 1)
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

-- 导出坐标索引（TileData 全套接口都用它：x + maxTilesX * y）
function M.index_of(x, y)
    if not ensure() then return nil end
    return index_of(x, y)
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
--   "cut"   可以清掉再放的图格（草/藤/花，以及「土块」）
--   "solid" 硬块 / 已有家具，停止
--   "error" 读取失败（句柄没解析好），不能当“实心”处理
--
-- 注意：TileID 0 = Dirt（土块），不是空气！
-- 空气同样报 type 0，所以「type == 0」不能直接当空地。
-- 必须再用 WorldGen.SolidTile 判一次实心：
--   实心 → 是土块，按 "cut" 处理（可清掉再建）
--   非实心 → 真空地
function M.classify(x, y)
    if not ensure() then return "error" end
    local t = M.type_at(x, y)
    if t < 0 then return "error" end
    if t ~= 0 then
        if is_cut(t) then return "cut" end
        return "solid"
    end
    if h.mSolidTile then
        local s = try(q.call, h.mSolidTile, x, y)
        if s == true then return "cut" end   -- 土块：清掉就能放
        if s == nil then return "error" end
    end
    return "empty"
end

-- 摧毁一个可砍图格。
function M.kill(x, y)
    h.mKill = h.mKill or try(q.method, "Terraria", "WorldGen", "KillTile", 5)
    if not h.mKill then return false end
    return try(q.call, h.mKill, x, y, false, false, true) == true
end

-- 该格是否为实心（WorldGen.SolidTile）。用于区分「木块」和「土块占位」。
function M.solid_at(x, y)
    if not ensure() then return nil end
    if not h.mSolidTile then return nil end
    local r = try(q.call, h.mSolidTile, x, y)
    if r == true then return true end
    if r == false then return false end
    return nil
end

-- 读取某格的完整字段快照（供 SetEverything 手工构造同款图格）。
function M.snapshot(idx)
    if not ensure() then return nil end
    if not idx then return nil end
    local function g(m)
        if not m then return nil end
        return try(q.call, m, idx)
    end
    local sh = g(h.mGetSHeader)
    local fx = g(h.mGetFrameX)
    local fy = g(h.mGetFrameY)
    local b1 = g(h.mGetBHeader)
    if type(sh) ~= "number" or type(fx) ~= "number" or type(fy) ~= "number"
            or type(b1) ~= "number" then
        return nil
    end
    return {
        sh  = sh,
        fx  = fx,
        fy  = fy,
        b1  = b1,
        b2  = g(h.mGetBHeader2) or 0,
        b3  = g(h.mGetBHeader3) or 0,
        liq = g(h.mGetLiquid) or 0,
    }
end

return M
