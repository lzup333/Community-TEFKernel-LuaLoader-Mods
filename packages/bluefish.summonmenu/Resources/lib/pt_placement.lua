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

-- 火把：图格 4（样式 0 = 普通火把）、物品 8。
-- 起点是第 3 格（phase 从 0 起算 → TORCH_OFFSET = 2），之后每隔 TORCH_STEP(5) 格一个。
-- 即第 3、8、13、18…… 格平台上方有火把。
M.TILE_TORCH = 4
M.TORCH_STYLE = 0
M.TORCH_ID = 8
M.TORCH_STEP = 5
M.TORCH_OFFSET = 2

M.ITEM_NAME = "01_platform_wand"

-- 世界边界安全内缩，避免贴边触发原版越界保护。
M.WORLD_MARGIN = 10

-- 魔杖的合成配方（“特定配方”按需改这里即可）。
M.WAND_RECIPE = {
    result = M.ITEM_NAME,
    materials = {
        { id = M.WOOD_ID,  count = 100 },   -- 木材 ×100
        { id = M.TORCH_ID, count = 20  },   -- 火把 ×20
    },
    station = M.WORKBENCH_TILE,             -- 工作台合成
}

-- 放置方向：向右 +1，向左 -1。
function M.step(dir)
    return (dir or 1) < 0 and -1 or 1
end

return M