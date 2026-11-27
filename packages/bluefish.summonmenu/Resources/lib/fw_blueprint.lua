-- fw_blueprint.lua —— 悬空小屋蓝图（宽 6 × 高 10）
--
-- 严格按用户给的布局表（1 起编号）逐行绘制：
--
--   列:       1    2    3    4    5    6
--   行1:     块   块   块   块   块   块    ← 块：木材
--   行2:     块   火*  墙   墙   墙   块    ← *火把，火把后面有墙
--   行3:     块   墙   墙   墙   墙   块    ← 墙：木墙
--   行4:     块   墙   墙   墙   墙   块
--   行5:     块   墙   台   台   椅   块    ← 台/椅：工作台、木椅，后面有墙
--   行6:     块   墙   块   块   块   块
--   行7:     平   墙   墙   墙   墙   平
--   行8:     平   墙   墙   墙   墙   平
--   行9:     平   墙   墙   墙   墙   平
--   行10:    平   平   平   平   平   平    ← 平：木平台
--
-- 代码里统一用 0 起坐标：列 0..5 对应上表列 1..6，行 0..9 对应上表行 1..10。
-- 字符含义：W = 木块  P = 木平台  w = 木墙（背景）  . = 空
--
-- 所有 ID 来自 Source-1.4.5.8 的 Terraria.ID/*.cs：
--   TileID.WoodBlock=30  TileID.Platforms=19  TileID.Chairs=15
--   TileID.WorkBenches=18 TileID.Torches=4    WallID.Wood=4
--   ItemID.Wood=9  ItemID.Torch=8
local M = {}

M.WIDTH  = 6
M.HEIGHT = 10

M.TILE_WOOD     = 30   -- WoodBlock
M.TILE_PLATFORM = 19   -- Platforms（木平台）
M.TILE_CHAIR    = 15   -- Chairs
M.TILE_TABLE    = 18   -- WorkBenches
M.TILE_TORCH    = 4    -- Torches

M.WALL_WOOD = 4        -- Wood

M.ITEM_WOOD  = 9
M.ITEM_TORCH = 8

M.WORLD_MARGIN = 10
M.ITEM_NAME    = "02_house_wand"
M.WAND_RECIPE = {
    result = M.ITEM_NAME,
    materials = { { id = M.ITEM_WOOD, count = 100 } },
    station = M.TILE_TABLE,
}

-- 材料：只要背包里有 47 个木材 + 1 个火把就能直接建
-- （工作台 / 椅子 / 平台 / 木墙都不单独要物品，都算在 47 木材里）
M.COST = {
    { id = M.ITEM_WOOD,  count = 47 },
    { id = M.ITEM_TORCH, count = 1 },
}

-- 逐行布局表（每行 6 个字符，对应列 1..6，即代码里的 0..5）
local ROWS = {
    "WWWWWW",   -- 行1：顶部横梁，6 格木材
    "WwwwwW",   -- 行2：第 2 格是木墙 + 火把（火把后面有墙）
    "WwwwwW",   -- 行3
    "WwwwwW",   -- 行4
    "WwwwwW",   -- 行5：第 3/4 格放工作台、第 5 格放木椅，这三格都铺木墙
    "WwWWWW",   -- 行6：第 2 格留木墙，3~6 格是木材地板
    "PwwwwP",   -- 行7：两端木平台，中间木墙
    "PwwwwP",   -- 行8
    "PwwwwP",   -- 行9
    "PPPPPP",   -- 行10：底部整排木平台
}

local function compute()
    local cells       = {}   -- 要放的方块（含平台），每格带 tile 字段
    local wall_cells  = {}   -- 需要铺木墙的格子
    -- 火把：上表「行2 / 列2」→ 0 起坐标 (1, 1)
    local torch_cells = { { tx = 1, ty = 1 } }
    -- 椅子：上表「行5 / 列5」→ 0 起坐标 (4, 4)，锚点 = 座面，占 (4,3)(4,4)
    local chair_cells = { { tx = 4, ty = 4 } }
    -- 工作台：上表「行5 / 列3、列4」→ 0 起坐标 (2, 4)，锚 = 左半格，占 (2,4)(3,4)
    local table_cells = { { tx = 2, ty = 4 }, { tx = 3, ty = 4 } }

    for ty, line in ipairs(ROWS) do
        local row = ty - 1     -- 行号从 0 开始（对应上表行号 - 1）
        for tx = 0, M.WIDTH - 1 do
            local ch = line:sub(tx + 1, tx + 1)
            if ch == "W" then
                cells[#cells + 1] = { tx = tx, ty = row, tile = M.TILE_WOOD }
            elseif ch == "P" then
                cells[#cells + 1] = { tx = tx, ty = row, tile = M.TILE_PLATFORM }
            elseif ch == "w" then
                wall_cells[#wall_cells + 1] = { tx = tx, ty = row }
            end
        end
    end

    return {
        cells       = cells,
        wall_cells  = wall_cells,
        torch_cells = torch_cells,
        chair_cells = chair_cells,
        table_cells = table_cells,
    }
end

local BP = compute()
M.cells       = BP.cells
M.wall_cells  = BP.wall_cells
M.torch_cells = BP.torch_cells
M.chair_cells = BP.chair_cells
M.table_cells = BP.table_cells
-- 本样式没有门：door / door_head 不再提供
M.door      = nil
M.door_head = nil

return M
