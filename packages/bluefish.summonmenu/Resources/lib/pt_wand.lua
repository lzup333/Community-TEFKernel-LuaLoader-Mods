-- pt_wand.lua —— 平台魔杖
--
-- 铺放由 pt_drag.tick 每帧驱动（轻按铺 geom.LENGTH 格 / 拖动框选一条线），
-- 不挂在物品的 use 回调上：这台内核会把多个自定义物品的 use 回调串在一起。
-- 这里 use 只负责把本帧动作压掉，避免原版按 createTile(19) 自己在光标处放一块平台。
local M = {}

require("wand_quickapi")
local q = mod.quickapi
local geom = require("pt_placement")
local drag = require("pt_drag")
local preview = require("pt_preview")

-- 原版 use 回调：什么都不铺，只清掉本帧挥动动画。
local function block_vanilla_use(player)
    if not player then return end
    pcall(q.set_field_value, "Terraria", "Player", "itemAnimation", player, 0, "int32")
end

function M.setup()
    q.register_item{
        name = geom.ITEM_NAME,
        texture = "platform_wand.png",
        sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
        width = 24,
        height = 14,
        createTile = geom.TILE_PLATFORM,
        placeStyle = geom.PLACE_STYLE,
        useStyle = 1,
        useTime = 30,
        useAnimation = 30,
        maxStack = 1,
        consumable = false,       -- 魔杖本身不消耗，消耗的是背包里的木平台
        tooltip = true,
        language = {
            zh = {
                name = "平台魔杖",
                tooltip = "单击：一次性铺设100格平台，每5格生成一支火把，支持无火把时只生成平台\n"
                       .. "拖动框选：支持单横排和单竖排铺设",
            },
            en = {
                name = "平台魔杖",
                tooltip = "单击：一次性铺设100格平台，每5格生成一支火把，支持无火把时只生成平台\n"
                       .. "拖动框选：支持单横排和单竖排铺设",
            },
        },
        recipe = geom.WAND_RECIPE,
        use = block_vanilla_use,
    }

    -- 启用「图格预览」（复用原版家具幽灵的绘制，仅 Android 生效）。
    if not preview.install() then
        mod.info("平台魔杖：图格预览未启用（需要 Android 内核的按值结构体调用）")
    end
end

-- 每帧：拖动状态机 + 铺放（由 main.lua 的 pu_reg_post 总线驱动）
function M.on_tick(player)
    pcall(drag.tick, player)
end

function M.cleanup()
    pcall(drag.cleanup)
    pcall(preview.cleanup)
end

return M
