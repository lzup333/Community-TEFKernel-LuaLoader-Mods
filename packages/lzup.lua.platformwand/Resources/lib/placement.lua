-- 平台魔杖：共用常量与几何工具。
-- 纯 Lua 坐标/方向约定，方便单测；图格读写见 tilefield.lua。

local M = {}

-- 一次最多铺放的格数。
M.LENGTH = 100

-- 木平台 = 图格 19（样式 0 = 木质）；木平台物品 = 94；木材物品 = 9；工作台 = 图格 18。
M.TILE_PLATFORM = 19
M.PLACE_STYLE = 0
M.PLATFORM_ITEM_ID = 94
M.WOOD_ID = 9
M.WORKBENCH_TILE = 18

M.ITEM_NAME = "platform_wand"

-- 世界边界安全内缩，避免贴边触发原版越界保护。
M.WORLD_MARGIN = 10

-- 魔杖的合成配方（“特定配方”按需改这里即可）。
M.WAND_RECIPE = {
    result = 1,
    materials = { { id = M.WOOD_ID, count = 20 } },
    station = M.WORKBENCH_TILE,
}

-- 放置方向：向右 +1，向左 -1。
function M.step(dir)
    return (dir or 1) < 0 and -1 or 1
end

-- 沿 dir 方向的坐标表（只含 X）。
function M.tiles(x, y, dir, len)
    local step = M.step(dir)
    local out = {}
    for i = 0, len - 1 do
        out[i + 1] = x + i * step
    end
    return out
end

return M