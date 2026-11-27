-- lw_placement.lua —— 液体魔杖：常量与几何工具
--
-- 四模式：生成水 / 生成熔岩 / 生成蜂蜜 / 清除液体（含三种液体）
-- 交互：单击铺 1 格（按模式生成或清除），拖动框选铺矩形（上限 100×100）
local M = {}

M.ITEM_NAME = "03_liquid_wand"

-- 框选上限（格）。用户要求最大 100×100。
M.MAX_LEN = 100
M.MAX_H = 100

-- 液体类型（Terraria.Liquid 常量：0 水 / 1 熔岩 / 2 蜂蜜）
M.LIQ_WATER = 0
M.LIQ_LAVA = 1
M.LIQ_HONEY = 2
M.LIQ_FULL = 255          -- 满格液体（满格不会流动，写起来不会卡）

-- 世界边界安全内缩，避免贴边触发原版越界保护。
M.WORLD_MARGIN = 10

-- 判定「在拖」的最小位移（格）。小于它算轻按，只作用于光标那一格。
M.DRAG_THRESHOLD = 1

-- ==================== 四种模式 ====================
M.MODE_WATER = "water"
M.MODE_LAVA = "lava"
M.MODE_HONEY = "honey"
M.MODE_CLEAR = "clear"

-- 按钮每点一次切到下一个
M.MODE_ORDER = { M.MODE_WATER, M.MODE_LAVA, M.MODE_HONEY, M.MODE_CLEAR }

-- 聊天栏播报用的名字
M.MODE_NAME = {
    [M.MODE_WATER] = "生成水",
    [M.MODE_LAVA] = "生成熔岩",
    [M.MODE_HONEY] = "生成蜂蜜",
    [M.MODE_CLEAR] = "清除液体",
}

-- 每种模式对应的液体类型（清除模式不用）
M.MODE_LIQUID = {
    [M.MODE_WATER] = M.LIQ_WATER,
    [M.MODE_LAVA] = M.LIQ_LAVA,
    [M.MODE_HONEY] = M.LIQ_HONEY,
}

-- 预览颜色（RGB）。清除模式用紫色。
M.MODE_COLOR = {
    [M.MODE_WATER] = { 80, 160, 255 },
    [M.MODE_LAVA] = { 255, 80, 40 },
    [M.MODE_HONEY] = { 255, 200, 60 },
    [M.MODE_CLEAR] = { 190, 110, 255 },
}

-- ==================== 配方用到的 ID ====================
-- 数值来自反编译表 Terraria.ID.ItemID / TileID（PE 1.4.5.8），
-- 注意 PE 版和 PC 版数值不同（例：水桶 PE 是 206，PC 是 235）。
M.ITEM_WATER_BUCKET = 206        -- ItemID.WaterBucket
M.ITEM_LAVA_BUCKET = 207         -- ItemID.LavaBucket
M.ITEM_HONEY_BUCKET = 1128       -- ItemID.HoneyBucket
M.ITEM_BRAIN_RELIC = 4926        -- ItemID.BrainofCthulhuMasterTrophy（克苏鲁之脑圣物）
M.ITEM_EATER_RELIC = 4925        -- ItemID.EaterofWorldsMasterTrophy（世界吞噬怪圣物）
M.ITEM_BOTTOMLESS_WATER = 3031   -- ItemID.BottomlessBucket（无底水桶）
M.ITEM_BOTTOMLESS_LAVA = 4820    -- ItemID.BottomlessLavaBucket
M.ITEM_BOTTOMLESS_HONEY = 5302   -- ItemID.BottomlessHoneyBucket

M.TILE_DEMON_ALTAR = 26          -- TileID.DemonAltar（恶魔祭坛）
M.TILE_ANVIL = 16                -- TileID.Anvils（铁砧）

-- 三个配方。mod.recipe.add 一次只吃一个，所以做成数组逐个注册。
-- 注意：每条的 result 不写在这里 —— 注册时必须填「液体魔杖自己的运行时 ID」
-- （见 lw_wand.add_recipes），写成数量会合出别的物品。
M.RECIPES = {
    {
        name = "祭坛·脑圣物",
        materials = {
            { id = M.ITEM_WATER_BUCKET, count = 49 },
            { id = M.ITEM_LAVA_BUCKET,  count = 49 },
            { id = M.ITEM_HONEY_BUCKET, count = 49 },
            { id = M.ITEM_BRAIN_RELIC,  count = 1   },
        },
        station = M.TILE_DEMON_ALTAR,
    },
    {
        name = "祭坛·吞噬怪圣物",
        materials = {
            { id = M.ITEM_WATER_BUCKET, count = 49 },
            { id = M.ITEM_LAVA_BUCKET,  count = 49 },
            { id = M.ITEM_HONEY_BUCKET, count = 49 },
            { id = M.ITEM_EATER_RELIC,  count = 1   },
        },
        station = M.TILE_DEMON_ALTAR,
    },
    {
        name = "铁砧·无底桶",
        materials = {
            { id = M.ITEM_BOTTOMLESS_WATER, count = 1 },
            { id = M.ITEM_BOTTOMLESS_LAVA,  count = 1 },
            { id = M.ITEM_BOTTOMLESS_HONEY, count = 1 },
        },
        station = M.TILE_ANVIL,
    },
}

-- 模式循环到下一个
function M.next_mode(mode)
    for i = 1, #M.MODE_ORDER do
        if M.MODE_ORDER[i] == mode then
            local n = i % #M.MODE_ORDER + 1
            return M.MODE_ORDER[n]
        end
    end
    return M.MODE_ORDER[1]
end

return M