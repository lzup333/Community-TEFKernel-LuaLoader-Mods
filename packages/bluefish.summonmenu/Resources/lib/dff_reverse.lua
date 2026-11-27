require("wand_quickapi")
pcall(mod.info, "================ 大肥鱼的反转术式（真·面板增伤版） 载入成功！ ================")

mod.quickapi.register_item{
    name = "07_ReverseCursed", 
    texture = "Image/dff_reverse_hate.png",
    sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
    accessory = true,                
    width = 18, height = 12, 
    rare = -13, 
    value = 125000,
    tooltip = true,
    language = { 
        zh = { 
            name = "大肥鱼的反转术式", 
            tooltip = "根据世界进度自动进化：\n【肉山前】少量回血，免死冷却30秒。\n【肉山后】回血加快，面板法伤+15%，冷却20秒。\n【世花后】回血更快，面板法伤+30%，冷却15秒。\n【月总后】极致反转，面板法伤+50%，冷却10秒。\n【术式限制】：仅法师武器生效，魔力病状态下失效。" 
        },
        en = { 
            name = "大肥鱼的反转术式", 
            tooltip = "根据世界进度自动进化：\n【肉山前】少量回血，免死冷却30秒。\n【肉山后】回血加快，面板法伤+15%，冷却20秒。\n【世花后】回血更快，面板法伤+30%，冷却15秒。\n【月总后】极致反转，面板法伤+50%，冷却10秒。\n【术式限制】：仅法师武器生效，魔力病状态下失效。" 
        } 
    },
    recipe = {
        result = "07_ReverseCursed",
        materials = { 
            { id = 29, count = 1 },   -- 生命水晶
            { id = 109, count = 2 },  -- 魔力水晶
            { id = 154, count = 20 }, -- 骨头
            { id = 175, count = 10 }  -- 狱石锭
        },
        station = 114,                -- 工匠作坊
    },
}

local lastMana = 0
local lastLife = 0
local cooldown = 0 

local function hasBlessing(player)
    local accId = mod.quickapi.item_id("07_ReverseCursed")
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

-- 【新增】：检查手里拿的是不是魔法武器
local function isHoldingMagicWeapon(player)
    local isMagic = false
    pcall(function()
        local inv = mod.quickapi.get_object("Terraria", "Player", "inventory", player)
        local selected = mod.quickapi.get_field_value("Terraria", "Player", "selectedItem", player, "int32") or 0
        if inv then
            local currentItem = mod.patch.array_at(inv, selected)
            if currentItem then
                isMagic = mod.quickapi.get_field_value("Terraria", "Item", "magic", currentItem, "bool") or false
            end
        end
    end)
    return isMagic
end

local function hasManaSickness(player)
    local hasDebuff = false
    pcall(function()
        local buffs = mod.quickapi.get_object("Terraria", "Player", "buffType", player)
        if buffs then
            for i = 0, 21 do
                local b = mod.patch.array_at(buffs, i)
                if b and tonumber(b) == 94 then
                    hasDebuff = true
                    break
                end
            end
        end
    end)
    return hasDebuff
end

mod.quickapi.install_hook("Terraria", "Player", "UpdateEquips", {
    postfix = function(player)
        pcall(function()
            if cooldown > 0 then cooldown = cooldown - 1 end
            
            if hasBlessing(player) then
                local currentMana = mod.quickapi.get_field_value("Terraria", "Player", "statMana", player, "int32") or 0
                local currentLife = mod.quickapi.get_field_value("Terraria", "Player", "statLife", player, "int32") or 100
                local maxLife = mod.quickapi.get_field_value("Terraria", "Player", "statLifeMax2", player, "int32") or 100

                if lastMana == 0 then lastMana = currentMana end
                if lastLife == 0 then lastLife = currentLife end

                -- 扣除魔力上限代价
                local baseManaMax = mod.quickapi.get_field_value("Terraria", "Player", "statManaMax2", player, "int32") or 100
                mod.quickapi.set_field_value("Terraria", "Player", "statManaMax2", player, math.floor(baseManaMax * 0.9), "int32")

                -- 【读取世界进度】
                local hardMode = mod.quickapi.get_field_value("Terraria", "Main", "hardMode", nil, "bool") or false
                local downedPlant = mod.quickapi.get_field_value("Terraria", "NPC", "downedPlantBoss", nil, "bool") or false
                local downedMoon = mod.quickapi.get_field_value("Terraria", "NPC", "downedMoonlord", nil, "bool") or false

                -- 【动态设定属性】
                local healDivisor = 4    
                local cdMax = 1800       
                local damageBonus = 0.0  -- 默认无增伤

                if downedMoon then
                    healDivisor, cdMax, damageBonus = 1, 600, 0.50   -- 月总后：+50%面板伤害
                elseif downedPlant then
                    healDivisor, cdMax, damageBonus = 2, 900, 0.30   -- 世花后：+30%面板伤害
                elseif hardMode then
                    healDivisor, cdMax, damageBonus = 3, 1200, 0.15 -- 肉山后：+15%面板伤害
                end

                -- 【核心修复】：强行增加面板伤害！
                if damageBonus > 0 then
                    local currentMagicDmg = mod.quickapi.get_field_value("Terraria", "Player", "magicDamage", player, "float") or 1.0
                    -- 只有在拿着魔法武器时，才把面板伤害加上去
                    if isHoldingMagicWeapon(player) then
                        mod.quickapi.set_field_value("Terraria", "Player", "magicDamage", player, currentMagicDmg + damageBonus, "float")
                    end
                end

                local isSick = hasManaSickness(player)
                local holdingMagic = isHoldingMagicWeapon(player) -- 【严格限制】：必须是法师武器
                
                if not isSick and holdingMagic then
                    -- 【1. 术式顺转：回血】
                    if currentMana < lastMana and currentLife < maxLife then
                        local manaSpent = lastMana - currentMana
                        local healAmount = math.floor(manaSpent / healDivisor)
                        if healAmount > 0 then
                            mod.quickapi.set_field_value("Terraria", "Player", "statLife", player, math.min(maxLife, currentLife + healAmount), "int32")
                        end
                    end

                    -- 【2. 术式反转：免死】
                    if currentLife < lastLife then
                        if currentLife <= (maxLife * 0.15) and cooldown <= 0 and currentMana >= 50 then
                            mod.quickapi.set_field_value("Terraria", "Player", "statMana", player, currentMana - 50, "int32")
                            mod.quickapi.set_field_value("Terraria", "Player", "statLife", player, math.min(maxLife, currentLife + math.floor(maxLife * 0.2)), "int32")
                            mod.quickapi.set_field_value("Terraria", "Player", "immune", player, true, "bool")
                            mod.quickapi.set_field_value("Terraria", "Player", "immuneTime", player, 90, "int32")
                            cooldown = cdMax
                            mod.quickapi.invoke("Terraria", "Player", "AddBuff", player, 153, 60, false) 
                        end
                    end
                end
                
                lastMana = mod.quickapi.get_field_value("Terraria", "Player", "statMana", player, "int32") or 0
                lastLife = mod.quickapi.get_field_value("Terraria", "Player", "statLife", player, "int32") or 100
            end
        end)
    end,
})