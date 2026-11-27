-- afm_item.lua
-- 注册「自动钓鱼机」物品与工作台配方。
-- 物品身份用 Item.value 做稳定标记（注册期 runtime_id 可能还是 -1）。
local U = require("afm_util")
local P = U.P
local M = {}
local SD

local ITEM_NAME = "afm_machine"
local ITEM_MARK = 987700

-- 配方：强化钓竿×1、蠕虫×5、宝箱×1、开关×1、电线×10（工作台）
local RECIPE = {
    materials = {
        { id = 2291, count = 1 },   -- 强化钓竿
        { id = 2002, count = 5 },   -- 蠕虫
        { id = 48,   count = 1 },   -- 宝箱
        { id = 538,  count = 1 },   -- 开关
        { id = 530,  count = 10 },  -- 电线
    },
    station = 18,                   -- 工作台
}

function M.setup(ctx)
    SD = ctx
    SD.S.item_name = ITEM_NAME
    SD.S.mark = ITEM_MARK
end

local function runtime_id()
    if not (mod.item and mod.item.runtime_id) then return -1 end
    local ok, v = pcall(mod.item.runtime_id, ITEM_NAME)
    if ok and type(v) == "number" and v > 0 then return v end
    return -1
end

local function item_spec()
    return {
        name    = ITEM_NAME,
        texture = "afm_machine.png",
        tooltip = true,
        sacrifice = 1,
        defaults = {
            width = 32, height = 32,
            useStyle = 1, useAnimation = 12, useTime = 12,
            autoReuse = false, noMelee = true,
            damage = 0, knockBack = 0,
            maxStack = 99, rare = 2, value = ITEM_MARK,
            melee = false, magic = false, ranged = false,
        },
        language = {
            zh = {
                name = "自动钓鱼机",
                tooltip = "放置在水域附近自动钓鱼，鱼获自动存入钓鱼机内，需投放钓竿和鱼饵；空手靠近钓鱼机会把渔获自动收进背包，空手点击钓鱼机能回收渔具\n"
                       .. "配方：强化钓竿×1 + 蠕虫×5 + 宝箱×1 + 开关×1 + 电线×10，制作站：工作台\n"
                       .. "可投放渔具（靠近后会自动装备手持渔具）：\n"
                       .. "·钓竿：任意钓竿 ×1\n"
                       .. "·鱼饵：任意鱼饵整叠\n"
                       .. "·渔具：钓具箱 / 渔夫耳环 / 优质钓鱼线 / 渔夫工具包 / 防熔岩渔具袋 / 各类钓鱼浮标（各 +10）\n"
                       .. "·渔夫套：渔夫帽 / 背心 / 裤（各 +5）\n"
                       .. "·消耗品：宝匣药水 +15、钓鱼药水 +20（最多累计60分钟）、鱼饵桶 +10（10 分钟）",
            },
            en = {
                name = "Auto Fishing Machine",
                tooltip = "Fishes by itself next to water; catch goes into the machine\n"
                       .. "Needs a pole and bait inserted first\n"
                       .. "Hold tackle and walk close to auto-insert\n"
                       .. "Empty-handed: walk close to collect catch, tap to take back tackle",
            },
        },
        can_use = function() return true end,
    }
end

function M.register()
    if SD.S.reg_tried then return SD.S.item_id end
    SD.S.reg_tried = true
    local existed = runtime_id()
    local id, ok
    if existed > 0 then
        id, ok = existed, true
        U.log_info("[AFM] 物品已注册 id=" .. tostring(existed))
    elseif mod.item and mod.item.register then
        ok, id = pcall(mod.item.register, item_spec())
        if not ok then
            U.log_error("[AFM] 物品注册报错: " .. tostring(id))
            id = nil
        end
    else
        U.log_error("[AFM] mod.item.register 不可用")
        return -1
    end
    if type(id) ~= "number" then
        SD.S.item_id = -1
        SD.S.reg_info = "ret=" .. tostring(id)
        U.log_error("[AFM] 注册返回 " .. tostring(id))
        return -1
    end
    SD.S.item_id = (id > 0) and id or -1
    SD.S.reg_info = string.format("reg=%s runtime=%s", tostring(id), tostring(runtime_id()))
    U.log_info("[AFM] 物品注册 " .. tostring(SD.S.reg_info))
    return SD.S.item_id
end

function M.sync_id()
    local v = runtime_id()
    if v > 0 then
        if SD.S.item_id ~= v then U.log_info(string.format("[AFM] runtime id=%d", v)) end
        SD.S.item_id = v
    end
    return SD.S.item_id
end

-- ==================== 配方 ====================
local R = {}

local function bind_recipe_api()
    local RT = U.try_type("Terraria", "Recipe")
    if not RT then return false, "缺 Recipe 类型" end
    R.f_num   = U.find_field(RT, "numRecipes")
    R.m_setup = U.find_method(RT, "SetupRecipes", 0)
    R.m_quick = U.find_method(RT, "CreateRequiredItemQuickLookups", 0)
    if not (R.f_num and R.m_setup) then return false, "缺 numRecipes / SetupRecipes" end
    return true
end

function M.ensure_recipe()
    if SD.S.recipe_done then return true end

    if not SD.S.recipe_api_ready then
        local ok, why = bind_recipe_api()
        if not ok then
            if not SD.S.recipe_warned then
                SD.S.recipe_warned = true
                U.log_warn("[AFM] 配方 API 不全 (" .. tostring(why) .. ")")
            end
            return false
        end
        SD.S.recipe_api_ready = true
    end

    if not (mod.recipe and type(mod.recipe.add) == "function") then
        if not SD.S.recipe_warned then
            SD.S.recipe_warned = true
            U.log_warn("[AFM] 加载器无 mod.recipe，跳过配方")
        end
        return false
    end

    local id = M.sync_id()
    if id <= 0 then return false end

    local ok, err = pcall(mod.recipe.add, {
        result    = id,
        materials = RECIPE.materials,
        station   = RECIPE.station,
    })
    if not ok then
        if not SD.S.recipe_warned then
            SD.S.recipe_warned = true
            U.log_warn("[AFM] mod.recipe.add 失败: " .. tostring(err))
        end
        return false
    end

    -- numRecipes 归零，避免 SetupRecipes 再追加整套原版配方
    local before = U.gf_int(R.f_num, nil)
    local zeroed = false
    if before > 0 then
        zeroed = pcall(P.set_field_value, R.f_num, nil, 0, "int32")
    end

    local ok2, err2 = pcall(P.invoke, R.m_setup)
    local after = U.gf_int(R.f_num, nil)

    if not ok2 or after <= 0 then
        if zeroed and before > 0 then
            pcall(P.set_field_value, R.f_num, nil, before, "int32")
        end
        if not SD.S.recipe_warned then
            SD.S.recipe_warned = true
            U.log_warn("[AFM] SetupRecipes 失败: " .. tostring(err2))
        end
        return false
    end

    if R.m_quick then pcall(P.invoke, R.m_quick) end

    SD.S.recipe_done = true
    U.log_info(string.format("[AFM] 配方已注册 %s -> %s (result=%d)",
        tostring(before), tostring(after), id))
    return true
end

return M