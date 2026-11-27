require("wand_quickapi")
pcall(mod.info, "================ 大肥鱼的纯爱之戒 (真·复活防崩版) 载入成功！ ================")

local q = mod.quickapi
local patch = mod.patch

-- 1. 注册饰品
q.register_item{
    name = "05_PureLoveRing",
    texture = "Image/PureLove.png", 
    sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
    accessory = true,                
    width = 24, height = 24, 
    rare = -13, 
    value = 100000,
    tooltip = true,
    language = { 
        zh = { 
            name = "大肥鱼的纯爱戒指", 
            tooltip = "【外置咒力】：极速回蓝，魔力锁定。\n【共享视野】：周期性获得危险感知与狩猎效果。\n【里香的庇护】：血量低于5%或受致命伤时，消耗50魔力强行复活满血(冷却20秒，显示为魔力病)。\n“我们可是纯爱啊！”" 
        },
        en = { 
            name = "大肥鱼的纯爱戒指", 
            tooltip = "【外置咒力】：极速回蓝，魔力锁定。\n【共享视野】：周期性获得危险感知与狩猎效果。\n【里香的庇护】：血量低于5%或受致命伤时，消耗50魔力强行复活满血(冷却20秒，显示为魔力病)。\n“我们可是纯爱啊！”" 
        } 
    },
    recipe = {
        result = "05_PureLoveRing",
        materials = {
            { id = 29,   count = 1 },   -- 生命水晶
            { id = 109,  count = 2 },   -- 魔力水晶
            { id = 2352, count = 1 },   -- 爱情药水
        },
        station = 114,                  -- 工匠作坊
    },
    defaults = { magicDamage = 0.8 }
}

local tick = 0
local accId = -1

local function checkEquipped(player)
    if accId == -1 then accId = q.item_id("05_PureLoveRing") end
    if accId == -1 then return false end
    local armor = q.get_object("Terraria", "Player", "armor", player)
    if armor then
        for i = 3, 13 do
            local item = patch.array_at(armor, i)
            if item then
                local itemType = q.get_field_value("Terraria", "Item", "type", item, "int32")
                if itemType == accId then return true end
            end
        end
    end
    return false
end

-- 【神级设计】：用原版的“魔力病” (ID 94) 当作冷却计时器
local function hasCooldown(player)
    local buffs = q.get_object("Terraria", "Player", "buffType", player)
    if buffs then
        for i = 0, 21 do
            local b = patch.array_at(buffs, i)
            if b and tonumber(b) == 94 then return true end
        end
    end
    return false
end

-- 2. 主循环逻辑
q.install_hook("Terraria", "Player", "UpdateEquips", {
    postfix = function(player)
        pcall(function()
            if not checkEquipped(player) then return end

            tick = tick + 1
            -- 魔力与视野
            if tick >= 120 then
                tick = 0
                q.invoke("Terraria", "Player", "AddBuff", player, 111, 180, false) -- 危险感知
                q.invoke("Terraria", "Player", "AddBuff", player, 17, 180, false)  -- 狩猎
                
                local maxMana = q.get_field_value("Terraria", "Player", "statManaMax2", player, "int32") or 100
                q.set_field_value("Terraria", "Player", "statMana", player, maxMana, "int32")
                q.set_field_value("Terraria", "Player", "manaRegenDelay", player, 0, "int32")
            end

            -- 庇护触发
            local currentLife = q.get_field_value("Terraria", "Player", "statLife", player, "int32") or 100
            local maxLife = q.get_field_value("Terraria", "Player", "statLifeMax2", player, "int32") or 100
            local currentMana = q.get_field_value("Terraria", "Player", "statMana", player, "int32") or 0
            local isDead = q.get_field_value("Terraria", "Player", "dead", player, "bool") or false
            
            -- 如果没有冷却，并且（血量<=5% 或 已经死了），并且蓝量够
            if not hasCooldown(player) and (currentLife <= math.floor(maxLife * 0.05) or isDead) and currentMana >= 50 then
                
                -- 1. 强行抹除死亡状态 (如果是被秒杀，直接原地复活)
                q.set_field_value("Terraria", "Player", "dead", player, false, "bool")
                
                -- 2. 扣除 50 蓝
                q.set_field_value("Terraria", "Player", "statMana", player, currentMana - 50, "int32")
                -- 3. 瞬间满血
                q.set_field_value("Terraria", "Player", "statLife", player, maxLife, "int32")
                
                -- 4. 控脑术反击闪避
                q.invoke("Terraria", "Player", "AddBuff", player, 321, 180, false)
                -- 5. 1.5秒无敌
                q.set_field_value("Terraria", "Player", "immune", player, true, "bool")
                q.set_field_value("Terraria", "Player", "immuneTime", player, 90, "int32") 
                
                -- 🔥【核心】：挂上 1200 帧 (20秒) 的魔力病作为冷却标记！
                q.invoke("Terraria", "Player", "AddBuff", player, 94, 1200, false)
            end
        end)
    end,
})