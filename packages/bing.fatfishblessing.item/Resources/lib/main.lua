require("quickapi")

mod.quickapi.register_item{
    name = "FatFishBlessing",
    -- 【重点修改】：直接用你 Resources/Image 文件夹里自己的图
    texture = "Image/MageStone.png", 
    accessory = true,                
    width = 24, height = 24,
    rare = 5, 
    value = 50000,
    tooltip = true,
    language = {
        zh = { 
            name = "大肥鱼赐福之石", 
            tooltip = "由 bingbingbing 制作。\n蕴含极致的奥术力量。\n释放魔法时，让全屏敌人陷入4秒的烈火与剧毒折磨！" 
        },
    },
    recipe = {
        result = 1,
        materials = { 
            { id = 6167, count = 1 },  -- 碎裂之石
            { id = 186, count = 1 },   -- 魔力水晶
            { id = 75, count = 10 },   -- 坠落之星
            { id = 1339, count = 5 }   -- 小瓶毒液（巫医）
        },
        station = 114,                 -- 工匠作坊
    },
}

local cooldown = 0
local lastMana = 0

local function hasStone(player)
    local accId = mod.quickapi.item_id("FatFishBlessing")
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

mod.quickapi.install_hook("Terraria", "Player", "UpdateEquips", {
    postfix = function(player)
        if cooldown > 0 then
            cooldown = cooldown - 1
        end

        pcall(function()
            local currentMana = mod.quickapi.get_field_value("Terraria", "Player", "statMana", player, "int32") or 0
            if lastMana == 0 then lastMana = currentMana end

            if currentMana < lastMana and hasStone(player) and cooldown <= 0 then
                cooldown = 360 -- 6秒冷却
                
                -- 玩家自身闪烁紫光提示触发
                pcall(function()
                    mod.quickapi.invoke("Terraria", "Player", "AddBuff", player, 153, 60, false) 
                end)

                local npcs = mod.quickapi.get_object("Terraria", "Main", "npc", nil)
                if npcs then
                    local n = mod.patch.array_length(npcs)
                    for i = 0, n - 1 do
                        local npc = mod.patch.array_at(npcs, i)
                        if npc then
                            local active = mod.quickapi.get_field_value("Terraria", "NPC", "active", npc, "bool")
                            local friendly = mod.quickapi.get_field_value("Terraria", "NPC", "friendly", npc, "bool")
                            local life = mod.quickapi.get_field_value("Terraria", "NPC", "life", npc, "int32")
                            
                            if active and not friendly and life and life > 0 then
                                
                                -- 挂满 4 秒（240帧）的顶级持续伤害 Debuff！让原版引擎去扣血，保证掉落！
                                pcall(function() mod.quickapi.invoke("Terraria", "NPC", "AddBuff", npc, 189, 240, false) end) -- 破晓
                                pcall(function() mod.quickapi.invoke("Terraria", "NPC", "AddBuff", npc, 39, 240, false) end)  -- 诅咒地狱
                                pcall(function() mod.quickapi.invoke("Terraria", "NPC", "AddBuff", npc, 153, 240, false) end) -- 暗影焰
                                pcall(function() mod.quickapi.invoke("Terraria", "NPC", "AddBuff", npc, 44, 240, false) end)  -- 霜冻
                                pcall(function() mod.quickapi.invoke("Terraria", "NPC", "AddBuff", npc, 69, 240, false) end)  -- 灵液
                                pcall(function() mod.quickapi.invoke("Terraria", "NPC", "AddBuff", npc, 70, 240, false) end)  -- 毒液
                                pcall(function() mod.quickapi.invoke("Terraria", "NPC", "AddBuff", npc, 20, 240, false) end)  -- 中毒
                            end
                        end
                    end
                end
            end
            
            lastMana = currentMana
        end)
    end,
})