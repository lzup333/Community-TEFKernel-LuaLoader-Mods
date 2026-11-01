-- MoreWeapons —— 最小示例：QuickAPI + 自定义物品 + 自定义弹幕
--
-- 物品：MySword，10 木材在工作台合成；使用后发射 MyBolt。
-- 弹幕：MyBolt，使用 QuickAPI 的 projectile_move 做最简直线 AI。
--
-- 想改成追踪弹幕，把 ai 换成：
--   local npc = mod.quickapi.find_nearest_npc(p, 900)
--   if npc then
--       local nx, ny = mod.quickapi.vec.get("Terraria", "NPC", "position", npc)
--       mod.quickapi.projectile_homing(p, nx, ny, 0.18)
--   end
--   mod.quickapi.projectile_move(p)

require("quickapi")

function mod.init()

    mod.quickapi.register_item{
        name     = "BlueArrowSword",
        tooltip  = true,
        maxStack = 9999,

        -- Item.SetDefaults 字段，直接平铺
        width    = 32,
        height   = 32,
        damage   = 36,
        useTime  = 15,
        useAnimation = 20,
        useStyle = 1,
        melee    = true,
        sacrifice = 1, --研究数量
        shoot       = 173,   
        shootSpeed  = 10.0,
        use_sound   = "Item1",    -- 设置声音
        texture = "BlueArrowSword",

        language = {
            en = {
                name    = "Blue Arrow Sword",
                tooltip = "Shoots an enchanted sword beam",
            },
            zh = {
                name    = "蓝矢剑",
                tooltip = "发射附魔剑矢",
            },
        },

        -- 附魔剑 + 蓝玉
        recipe = {
            result    = 1,
            materials = { { id = 989, count = 1 },{ id = 177 , count = 10 } },
            station   = 16,
        },
    }
end
