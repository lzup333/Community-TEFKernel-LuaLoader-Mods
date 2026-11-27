-- bw_placement.lua —— 物块魔杖：共用常量与几何工具。
-- 结构与 pt_placement（平台魔杖）完全一致，只换「铺什么」。
--
-- 铺设样式（纵向看是一行）：
--        火                                  火
--   砖砖砖砖砖砖砖砖砖空砖砖砖砖砖砖砖砖砖空
--   砖 = 灰砖；空 = 每隔 9 块灰砖空出一格；火 = 每个循环的第 5 块灰砖上方一个火把
local M = {}

-- 一次最多铺放的格数（平台魔杖是 108，物块魔杖是 100）。
M.LENGTH = 100

-- 灰砖：图格 38（GrayBrick），物品 129（GrayBrick）。
M.TILE_BRICK = 38
M.BRICK_STYLE = 0
M.BRICK_ITEM_ID = 129

-- 火把：图格 4（样式 0 = 普通火把）、物品 8。
M.TILE_TORCH = 4
M.TORCH_STYLE = 0
M.TORCH_ID = 8

-- 周期：每 BRICK_STEP 格为一个循环，其中前 BRICK_GAP 格铺砖，最后一格空着。
--   周期 10 = 铺 9 块砖 + 空 1 格
M.BRICK_STEP = 10
M.BRICK_GAP = 9          -- phase == 9 → 空格
M.TORCH_OFFSET = 4       -- phase == 4 → 第 5 块砖上方放火把

-- 配方用到的物品：石块 = 3，工作台图格 = 18。
M.STONE_ID = 3
M.WORKBENCH_TILE = 18
M.ITEM_NAME = "02_brick_wand"

-- 世界边界安全内缩，避免贴边触发原版越界保护。
M.WORLD_MARGIN = 10

-- 魔杖的合成配方：石块 ×100 + 火把 ×10，工作台合成。
M.WAND_RECIPE = {
    result = M.ITEM_NAME,
    materials = {
        { id = M.STONE_ID, count = 100 },   -- 石块 ×100
        { id = M.TORCH_ID, count = 10  },   -- 火把 ×10
    },
    station = M.WORKBENCH_TILE,
}

-- 放置方向：向右 +1，向左 -1。
function M.step(dir)
    return (dir or 1) < 0 and -1 or 1
end

return M
