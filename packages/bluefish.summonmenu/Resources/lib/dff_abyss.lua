require("wand_quickapi")
pcall(mod.info, "================ 法师专属混沌诅咒 载入成功！ ================")

-- 注册饰品
mod.quickapi.register_item{
    name = "09_ChaosBlessing", 
    texture = "Image/dff_abyss_hate.png", -- 用你那张 18x12 的图
    sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
    accessory = true,                
    width = 18, height = 12, 
    rare = -13, 
    value = 125000,
    tooltip = true,
    language = { 
        zh = { 
            name = "大肥鱼的深渊诅咒", 
            tooltip = "最大生命值降低 30%\n魔法伤害提升 220%（仅限法师）\n“接受我的诅咒，换取无上的魔力。”" 
        },
        en = { 
            name = "大肥鱼的深渊诅咒", 
            tooltip = "最大生命值降低 30%\n魔法伤害提升 220%（仅限法师）\n“接受我的诅咒，换取无上的魔力。”" 
        } 
    },
    recipe = {
        result = "09_ChaosBlessing",
        materials = { 
            { id = 521, count = 5 },   -- 暗影之魂
            { id = 175, count = 10 },  -- 狱石锭
            { id = 154, count = 20 },  -- 骨头
            { id = 29, count = 1 }     -- 生命水晶
        },
        station = 114,                 -- 工匠作坊
    },
}

-- 检查是否装备了它
local function hasBlessing(player)
    local accId = mod.quickapi.item_id("09_ChaosBlessing")
    if not accId or accId < 0 then return false end
    local armor = mod.quickapi.get_object("Terraria", "Player", "armor", player)
    if not armor then return false end
    for i = 3, 13 do 
        local item = mod.patch.array_at(armor, i)
        if item then
            local itemType = mod.quickapi.get_field_value("Terraria", "Item", "type", item, "int32")
            if itemType == accId then return true end
        end
    end
    return false
end

-- 核心逻辑：血量扣除与法师专属伤害暴增
mod.quickapi.install_hook("Terraria", "Player", "UpdateEquips", {
    postfix = function(player)
        pcall(function()
            if hasBlessing(player) then
                -- 【1. 法师专属增强】：只提升魔法伤害到 2.2 (220%)
                mod.quickapi.set_field_value("Terraria", "Player", "magicDamage", player, 2.2, "float")

                -- 【2. 扣除 30% 生命上限】
                local baseMax = mod.quickapi.get_field_value("Terraria", "Player", "statLifeMax", player, "int32") or 100
                local newMax = math.floor(baseMax * 0.7)
                
                mod.quickapi.set_field_value("Terraria", "Player", "statLifeMax2", player, newMax, "int32")

                -- 【3. 防止扣除上限后当场暴毙】
                local currentLife = mod.quickapi.get_field_value("Terraria", "Player", "statLife", player, "int32") or 100
                if currentLife > newMax then
                    mod.quickapi.set_field_value("Terraria", "Player", "statLife", player, newMax, "int32")
                end
            end
        end)
    end,
})