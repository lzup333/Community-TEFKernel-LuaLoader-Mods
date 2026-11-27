-- bw_wand.lua —— 物块魔杖（灰砖版）
--
-- 铺放不挂在物品的 use 回调上，而是由 bw_drag.tick 每帧检测使用键来驱动。
-- 原因：这台内核会把多个自定义物品的 use 回调串在一起（拿物块魔杖跑平台魔杖的代码），
--       表现就是「切到框选还是铺平台」「播报还在说平台魔杖」。
--       绕开 use 之后，物块魔杖的行为完全由自己这条 tick 决定。
--
-- 这里 use 只负责把本帧动作压掉，避免原版按 createTile(38) 自己在光标处放一块砖。
local M = {}

require("wand_quickapi")
local q = mod.quickapi
local geom = require("bw_placement")
local drag = require("bw_drag")
local preview = require("bw_preview")


-- 原版 use 回调：什么都不铺，只清掉本帧挥动动画。
local function block_vanilla_use(player)
    if not player then return end
    pcall(q.set_field_value, "Terraria", "Player", "itemAnimation", player, 0, "int32")
end

function M.setup()
    q.register_item{
        name = geom.ITEM_NAME,
        texture = "brick_wand.png",
        sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
        width = 24,
        height = 14,
        createTile = geom.TILE_BRICK,
        placeStyle = geom.BRICK_STYLE,
        useStyle = 1,
        useTime = 30,
        useAnimation = 30,
        maxStack = 1,
        consumable = false,       -- 魔杖本身不消耗，消耗的是背包里的灰砖 / 石块
        tooltip = true,
        language = {
            zh = {
                name = "物块魔杖",
                tooltip = ("单击：一次性铺设 %d 格灰砖，每 %d 格生成一支火把，尾部镂空，"
                        .. "支持无火把时只生成物块\n"
                        .. "拖动框选：支持单横排和单竖排铺设"):format(
                        geom.LENGTH, geom.BRICK_STEP),
            },
            en = {
                name = "物块魔杖",
                tooltip = ("单击：一次性铺设 %d 格灰砖，每 %d 格生成一支火把，尾部镂空，"
                        .. "支持无火把时只生成物块\n"
                        .. "拖动框选：支持单横排和单竖排铺设"):format(
                        geom.LENGTH, geom.BRICK_STEP),
            },
        },
        recipe = geom.WAND_RECIPE,
        use = block_vanilla_use,
    }

    -- 范围预览：灰色半透明框 + 逐格网格线（hook Main.Draw，纯几何绘制，不依赖 TileObjectData）
    -- 火把位置另画原版幽灵（借 pt_preview 的 TileDrawing.Draw 钩子环境）。
    if not preview.install() then
        mod.info("物块魔杖：范围预览未启用")
    end

    -- 没有模式按钮：轻按铺固定长度、拖动只铺拖出的那一条，靠位移自动判断。
end

-- 每帧：轻按/拖动判断 + 铺放 + 预览状态写入（由 main.lua 的 pu_reg_post 总线驱动）
function M.on_tick(player)
    pcall(drag.tick, player)
end

function M.cleanup()
    pcall(drag.cleanup)
    pcall(preview.cleanup)
end

return M
