-- 内容注册顺序：弹幕 → NPC → 物品 → 饰品钩子 → 配方。
-- 物品的 shoot 写的是弹幕名，运行期才解析，但先注册弹幕更稳。
local buffs = require("buffs")
local projectiles = require("projectiles")
local npcs = require("npcs")
local items = require("items")
local equip_effects = require("equip_effects")
local chatcmd = require("chatcmd")
local recipes = require("recipes")
local guide = require("guide")

local function register_all()
    -- 自定义 Buff：按文档在加载阶段登记（只调 register，不查 ID、不挂 Buff）
    buffs.register()
    projectiles.register()
    npcs.register()
    items.register()
    equip_effects.register()
    chatcmd.register()
    recipes.register()
    guide.register()   -- 向导「材料→可制作」补扫，必须在配方登记之后
end

return { register_all = register_all }
