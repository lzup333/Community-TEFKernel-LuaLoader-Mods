-- lw_tilefield.lua —— 图格与液体的读写
--
-- 安卓端 `Terraria.Tile` 是「值类型」，Framing.GetTileSafely 按值返回 struct，
-- Lua 拿不到返回值。所以全部走 WorldGen / TileData 的静态接口：
--   TileData.GetType(index)                     读图格类型（0 = 空气）
--   WorldGen.SolidTile(i, j, noDoors)           读是否实心
--   WorldGen.AnyLiquidAt(x, y, liquidType)      读是否有液体（-1 = 任意种类）
--   WorldGen.PlaceLiquid(x, y, type, amount)    写液体（amount 255 = 满格）
--   WorldGen.EmptyLiquid(x, y)                  清掉该格液体
--   TileData.GetLiquid(index) / SetLiquid(index, v)  直接读写液体量（最可靠）
--
-- 清除液体走「主路 + 两级兜底 + 事后复查」：
--   ① TileData.SetLiquid(index, 0)
--   ② WorldGen.EmptyLiquid(x, y)
--   ③ WorldGen.PlaceLiquid(x, y, 0, 0)
-- 每种方式做完都读一次 GetLiquid 确认真的变成 0，才算清除成功。
local q = mod.quickapi
local patch = mod.patch
local geom = require("lw_placement")

local M = {}
local h = {}
local ready = false

local function first_method(class, name, specs)
    for _, spec in ipairs(specs) do
        local m = q.method("Terraria", class, name, spec)
        if m then return m end
    end
    return nil
end

local function ensure()
    if ready then return true end

    h.mGetType = q.method("Terraria", "TileData", "GetType", 1)
    h.fMaxTilesX = q.field("Terraria", "Main", "maxTilesX")

    -- byte 参数在不同构建里可能叫 byte 也可能叫 uint8，逐个候选试
    h.mPlaceLiquid = first_method("WorldGen", "PlaceLiquid", {
        { params = { "int32", "int32", "byte", "byte" } },
        { params = { "int32", "int32", "uint8", "uint8" } },
        { argc = 4 },
    })
    h.mEmptyLiquid = first_method("WorldGen", "EmptyLiquid", {
        { params = { "int32", "int32" } },
        { argc = 2 },
    })
    h.mSolidTile = first_method("WorldGen", "SolidTile", {
        { params = { "int32", "int32", "bool" } },
        { params = { "int32", "int32" } },
        { argc = 3 },
        { argc = 2 },
    })
    h.mAnyLiquid = first_method("WorldGen", "AnyLiquidAt", {
        { params = { "int32", "int32", "int32" } },
        { argc = 3 },
    })

    -- TileData 的液体访问器（静态，index = x + maxTilesX * y）
    h.mGetLiquid = first_method("TileData", "GetLiquid", {
        { params = { "int32" } },
        { argc = 1 },
    })
    h.mSetLiquid = first_method("TileData", "SetLiquid", {
        { params = { "int32", "byte" } },
        { params = { "int32", "uint8" } },
        { argc = 2 },
    })

    if not (h.mGetType and h.fMaxTilesX) then return false end
    ready = true
    return true
end

-- 取 (x, y) 的图格类型；失败返回 -1。
function M.type_at(x, y)
    if not ensure() then return -1 end
    local w = patch.get_field_value(h.fMaxTilesX, nil, "int32")
    if not w then return -1 end
    local t = q.call(h.mGetType, x + w * y)
    if type(t) ~= "number" then return -1 end
    return t
end

-- 图格索引：x + maxTilesX * y
local function tile_index(x, y)
    if not ensure() then return nil end
    local w = patch.get_field_value(h.fMaxTilesX, nil, "int32")
    if not w then return nil end
    return x + w * y
end

-- 读该格液体量（0..255）。读不到返回 -1。
function M.liquid_at(x, y)
    if not h.mGetLiquid then return -1 end
    local idx = tile_index(x, y)
    if not idx then return -1 end
    local v = q.call(h.mGetLiquid, idx)
    if type(v) ~= "number" then return -1 end
    return v
end

-- 是否实心方块（液体进不去）
function M.solid(x, y)
    if not ensure() then return false end
    if not h.mSolidTile then return false end
    return q.call(h.mSolidTile, x, y, false) == true
end

-- 该格是否有液体（任意种类）
--   先读液体量（最准），读不到（-1）才退回 WorldGen.AnyLiquidAt
function M.has_liquid(x, y)
    if not ensure() then return false end
    local v = M.liquid_at(x, y)
    if v > 0 then return true end
    if v == 0 then return false end
    if h.mAnyLiquid then
        return q.call(h.mAnyLiquid, x, y, -1) == true
    end
    return false
end

-- 写液体。type：0 水 / 1 熔岩 / 2 蜂蜜；amount 默认满格。
function M.place_liquid(x, y, liquid_type, amount)
    if not ensure() then return false end
    if not h.mPlaceLiquid then return false end
    local amt = amount or geom.LIQ_FULL
    return q.call(h.mPlaceLiquid, x, y, liquid_type, amt) == true
end

-- 清掉该格的液体。返回 true 表示「事后复查确实是 0」。
function M.clear_liquid(x, y)
    if not ensure() then return false end

    -- ① 主路：TileData.SetLiquid(index, 0)
    if h.mSetLiquid then
        local idx = tile_index(x, y)
        if idx then
            pcall(q.call, h.mSetLiquid, idx, 0)
            if M.liquid_at(x, y) == 0 then return true end
        end
    end

    -- ② 兜底：WorldGen.EmptyLiquid(x, y)
    if h.mEmptyLiquid then
        pcall(q.call, h.mEmptyLiquid, x, y)
        if M.liquid_at(x, y) == 0 then return true end
    end

    -- ③ 再兜底：PlaceLiquid(x, y, 0, 0)（amount = 0 等于清空）
    if h.mPlaceLiquid then
        pcall(q.call, h.mPlaceLiquid, x, y, 0, 0)
        if M.liquid_at(x, y) == 0 then return true end
    end

    return false
end

-- 句柄是否就绪（给外部做一次性提示用）
function M.ready()
    return ensure()
end

return M