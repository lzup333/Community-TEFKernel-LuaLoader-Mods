-- tilefield.lua —— 读普通图格的信息 / 摧毁可砍图格。
--
-- 安卓端 `Terraria.Tile` 是「值类型」，Framing.GetTileSafely 按值返回 struct，
-- Lua 拿不到返回值。这里改走 TileData 的坐标索引接口：
--   index = x + maxTilesX * y
--   TileData.GetType(index) -> 图格类型（0 = 空气）
-- 再用 Main.tileCut[type] 判断是不是「剑能砍掉的」（草、藤、花等）。

local q = mod.quickapi
local patch = mod.patch

local M = {}
local h = {}
local ready = false

local function ensure()
    if ready then return true end
    h.mGetType = q.method("Terraria", "TileData", "GetType", 1)
    h.fMaxTilesX = q.field("Terraria", "Main", "maxTilesX")
    h.fTileCut = q.field("Terraria", "Main", "tileCut")
    if h.fTileCut then
        h.arrTileCut = patch.get_field_value(h.fTileCut, nil, "object")
    end
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

local function is_cut(t)
    if not h.arrTileCut then return false end
    local n = patch.array_length(h.arrTileCut) or 0
    if t < 0 or t >= n then return false end
    return patch.array_at(h.arrTileCut, t, "bool") == true
end

-- 分类：
--   "empty" 空格，可放
--   "cut"   可砍图格（草/藤/花等），摧毁后即可放
--   "solid" 硬块 / 需要工具的家具，停止
function M.classify(x, y)
    local t = M.type_at(x, y)
    if t == 0 then return "empty" end
    if t < 0 then return "solid" end
    if is_cut(t) then return "cut" end
    return "solid"
end

-- 摧毁一个可砍图格。
function M.kill(x, y)
    h.mKill = h.mKill or q.method("Terraria", "WorldGen", "KillTile", 5)
    if not h.mKill then return false end
    return q.call(h.mKill, x, y, false, false, false) == true
end

return M