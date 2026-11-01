-- blueprint.lua —— 火柴盒房间蓝图（来自 房屋.png，160x112 = 10x7 图格）
--
-- 房屋.png 结构：
--   行0        ：天花板（木块）
--   行1..5     ：室内（木墙），行5放家具
--   行6        ：地板（木块）
--   列0 / 列9  ：左右墙（木块），列0 的行3..5 换成门
--   火把       ：(1,1) 与 (8,1)
--   家具       ：椅子(6,5)、工作台(7,5)-(8,5)
--
-- 所有 ID 均来自 Source-1.4.5.8 的 Terraria.ID/*.cs：
--   TileID.WoodBlock=30  TileID.ClosedDoor=10  TileID.Chairs=15
--   TileID.WorkBenches=18 TileID.Torches=4      WallID.Wood=4
--   ItemID.Wood=9  ItemID.Torch=8  ItemID.WoodenDoor=25
--   ItemID.WoodenChair=34  ItemID.WorkBench=36

local M = {}

M.WIDTH  = 10
M.HEIGHT = 7

-- 图格 ID（TileID.cs）
M.TILE_WOOD  = 30   -- WoodBlock
M.TILE_DOOR  = 10   -- ClosedDoor
M.TILE_CHAIR = 15   -- Chairs
M.TILE_TABLE = 18   -- WorkBenches
M.TILE_TORCH = 4    -- Torches
-- 墙 ID（WallID.cs）
M.WALL_WOOD = 4     -- Wood
-- 物品 ID（ItemID.cs）
M.ITEM_WOOD   = 9
M.ITEM_TORCH  = 8
M.ITEM_DOOR   = 25
M.ITEM_CHAIR  = 34
M.ITEM_TABLE  = 36

M.WORLD_MARGIN = 10
M.ITEM_NAME = "house_wand"
M.WAND_RECIPE = {
    result = 1,
    materials = { { id = M.ITEM_WOOD, count = 20 } },
    station = M.TILE_TABLE,
}

-- 每格消耗的材料：{ 物品ID, 数量 }
M.COST = {
    { id = M.ITEM_WOOD,  count = 34 },  -- 边框 32 + 椅子 2
    { id = M.ITEM_TORCH, count = 2 },
    { id = M.ITEM_DOOR,  count = 1 },
    { id = M.ITEM_TABLE, count = 1 },
}
-- 木墙不消耗物品：背包里的木墙物品是墙纸，真正铺墙用的是
-- WorldGen.PlaceWall（原版锤子敲出来的墙没有物品来源，此处按“免费”处理）。

-- 蓝图格子表。tx/ty 相对房子左上角。
-- 框：行0、行6 全宽；列0、列9（行1..5）
local function compute()
    local cells = {}
    local wall_cells = {}   -- 需要铺木墙的格子（室内 8x5）
    local door_cells = {}   -- 门：左墙 (0,3)(0,4)(0,5)，门顶在 (0,2)
    local torch_cells = { { tx = 1, ty = 1 }, { tx = 8, ty = 1 } }
    local chair_cells = { { tx = 6, ty = 5 } }        -- 锚点 = 座面格
    local table_cells = { { tx = 7, ty = 5 }, { tx = 8, ty = 5 } } -- 锚点 = 左半
    local occupied = {}

    local function mark(x, y)
        occupied[x] = occupied[x] or {}
        occupied[x][y] = true
    end

    -- 天花板 / 地板
    for x = 0, M.WIDTH - 1 do
        cells[#cells + 1] = { tx = x, ty = 0 }
        cells[#cells + 1] = { tx = x, ty = M.HEIGHT - 1 }
        mark(x, 0); mark(x, M.HEIGHT - 1)
    end
    -- 左右墙（左墙留出门洞）
    -- 门占 (0,3)..(0,5) 三格：上方有行0..2三格，下面只剩行6一格。
    -- 门中格锚点为 (0,4)，供 WorldGen.PlaceDoor 使用。
    for y = 1, M.HEIGHT - 2 do
        if y < 3 or y > 5 then          -- (0,3)..(0,5) 留给门
            cells[#cells + 1] = { tx = 0, ty = y }
        end
        cells[#cells + 1] = { tx = M.WIDTH - 1, ty = y }
        mark(0, y); mark(M.WIDTH - 1, y)
    end

    -- 室内墙（只铺在没被占用的格子上）
    for y = 1, M.HEIGHT - 2 do
        for x = 1, M.WIDTH - 2 do
            if not (occupied[x] and occupied[x][y]) then
                wall_cells[#wall_cells + 1] = { tx = x, ty = y }
            end
        end
    end

    for _, c in ipairs(torch_cells) do mark(c.tx, c.ty) end
    for _, c in ipairs(chair_cells) do mark(c.tx, c.ty) end
    for _, c in ipairs(table_cells) do mark(c.tx, c.ty) end
    -- (0,3)..(0,5) 是门洞：从边框与墙里排除
    occupied[0][3] = nil; occupied[0][4] = nil; occupied[0][5] = nil

    return {
        cells = cells,               -- 木块边框
        wall_cells = wall_cells,     -- 木墙
        door = { tx = 0, ty = 4 },   -- 门中格（三格 = ty-1, ty, ty+1 = 行3,4,5）
        door_head = { tx = 0, ty = 4 }, -- 兼容旧名：门中格锚点
        torch_cells = torch_cells,
        chair_cells = chair_cells,
        table_cells = table_cells,
    }
end

local BP = compute()

M.cells      = BP.cells
M.wall_cells = BP.wall_cells
M.door       = BP.door
M.door_head  = BP.door_head
M.torch_cells = BP.torch_cells
M.chair_cells = BP.chair_cells
M.table_cells = BP.table_cells

return M
