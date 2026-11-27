-- 内容注册顺序：弹幕 → NPC → 物品 → 饰品钩子 → 配方。
-- （原模组的「向导配方补扫」已整体移除：启动器作者确认为内核限制，等内核侧修）
-- 物品的 shoot 写的是弹幕名，运行期才解析，但先注册弹幕更稳。
local buffs = require("cr_buffs")
local projectiles = require("cr_projectiles")
local npcs = require("cr_npcs")
local items = require("cr_items")
local equip_effects = require("cr_equip_effects")
local recipes = require("cr_recipes")

local function register_all()
    -- 自定义 Buff：按文档在加载阶段登记（只调 register，不查 ID、不挂 Buff）
    buffs.register()
    projectiles.register()
    npcs.register()
    items.register()
    equip_effects.register()
    recipes.register()
end

return { register_all = register_all }
