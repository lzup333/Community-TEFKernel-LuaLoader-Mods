require("wand_quickapi")
pcall(mod.info, "================ 灭霸的【力量宝石】(数值爆炸版) 载入成功！ ================")

local q = mod.quickapi
local patch = mod.patch

-- 1. 注册饰品
q.register_item{
    name = "06_PowerStone",
    texture = "Image/Nebula.png", -- 图
    sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
    accessory = true,                
    width = 24, height = 24, 
    rare = 10, 
    value = 1000000,
    tooltip = true,
    language = { 
        zh = { 
            name = "大肥鱼的力量宝石", 
            tooltip = "掌控一切力量与能量。\n【被动】：近战伤害 +25000%。\n【被动】：防御力 +3000。\n【被动】：免疫击退，拥有绝对霸体。\n“它只认可真正的强者。”" 
        },
        en = { 
            name = "大肥鱼的力量宝石", 
            tooltip = "掌控一切力量与能量。\n【被动】：近战伤害 +25000%。\n【被动】：防御力 +3000。\n【被动】：免疫击退，拥有绝对霸体。\n“它只认可真正的强者。”" 
        } 
    },
recipe = {
    result = "06_PowerStone",
    materials = { 
        { id = 3467, count = 10 }, -- 夜明锭 x10
        { id = 490, count = 1 }    -- 战士徽章 x1
    },
    station = 412,                 -- 远古操纵机
},
}

-- 2. 暴力注入核心逻辑
q.install_hook("Terraria", "Player", "UpdateEquips", {
    postfix = function(player)
        pcall(function()
            -- 检查是否装备
            local accId = q.item_id("06_PowerStone")
            local armor = q.get_object("Terraria", "Player", "armor", player)
            local hasStone = false
            if armor and accId then
                for i = 3, 13 do
                    local item = patch.array_at(armor, i)
                    if item then
                        local itemType = q.get_field_value("Terraria", "Item", "type", item, "int32")
                        if itemType == accId then hasStone = true break end
                    end
                end
            end

            -- 如果没装备，直接退出
            if not hasStone then return end

            -- 【灭霸级数值注入】
            -- 近战伤害倍率 = 2500.0 (即增加 250000% 的伤害)
            q.set_field_value("Terraria", "Player", "meleeDamage", player, 2500.0, "float") 
            
            -- 防御力强行增加 3000 (原版怪物打你全是0伤害)
            local baseDef = q.get_field_value("Terraria", "Player", "statDefense", player, "int32") or 0
            q.set_field_value("Terraria", "Player", "statDefense", player, baseDef + 3000, "int32")
            
            -- 免疫击退（霸体）
            q.set_field_value("Terraria", "Player", "noKnockback", player, true, "bool")
        end)
    end,
})