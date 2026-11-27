-- 向导「材料 → 可制作」补扫。
--
-- 手机端 Recipe.maxRecipes 被编译成常量 3700，内核只补了「合成菜单」的越界配方
-- （FindRecipes 补扫），向导那个界面走的是 Recipe.CollectGuideRecipes，
-- 原版同样只扫前 3700 条。我们的配方永远排在 3700 之后，
-- 所以拿碎晶 / 晶核给向导看时，一个可合成物都不显示。
--
-- 这里在原版扫完之后，自己把 [maxRecipes, numRecipes) 里用到这个材料的配方
-- 补进 Main.availableRecipe。原版那部分不动，只追加我们自己的。
local q = mod.quickapi
local ids = require("ids")
local recipes = require("recipes")
local util = require("util")

local M = {}

local state = {
    hooked = false,      -- 向导补扫钩子装上了没
    via = "",            -- 挂在哪个方法上
    argc = 0,
    candidates = {},     -- 找到的 Guide 相关方法名（诊断用）
    scanned = 0,         -- 上次扫了多少条越界配方
    appended = 0,        -- 上次补进去几条
    item = 0,
    used = 0,            -- 原版列了几条（我们动手之前）
    had = 0,             -- 本模组配方里已经被原版列进去的条数
    total = nil,         -- 配方总数
    capacity = nil,      -- Main.recipe 数组容量
    error = nil,
}

M.state = state

-- 只认我们自己的两种材料：原版材料原版自己会列，不去碰。
local material_ids = {}

-- 慢路径缓存（这些句柄全部按名字解析，缺一个就整体跳过，不崩）
local r = {
    ready = false,
    recipe_type = nil,
    main_type = nil,
    m_add = nil,          -- Recipe.AddToAvailableRecipes(int)
    f_recipe = nil,       -- Main.recipe
    f_create = nil,       -- Recipe.createItem
    f_required = nil,     -- Recipe.requiredItem
    f_type = nil,         -- Item.type
    prop_avail = nil,     -- Main.availableRecipe
    prop_num = nil,       -- Main.numAvailableRecipes
    get_avail = nil,
    get_num = nil,
    get_guide = nil,      -- Main.guideItem getter
    in_guide = nil,       -- Main.InGuideCraftMenu getter
}

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function resolve()
    if r.ready then return r.recipe_type ~= nil end
    r.ready = true

    r.recipe_type = q.type("Terraria", "Recipe")
    r.main_type = q.type("Terraria", "Main")
    if not r.recipe_type or not r.main_type then return false end

    r.m_add = q.method("Terraria", "Recipe", "AddToAvailableRecipes", 1)
            or q.method("Terraria", "Recipe", "AddToAvailableRecipes")
    r.f_recipe = q.field("Terraria", "Main", "recipe")
    r.f_create = q.field("Terraria", "Recipe", "createItem")
    r.f_required = q.field("Terraria", "Recipe", "requiredItem")
    r.f_type = q.field("Terraria", "Item", "type")

    r.prop_avail = q.property("Terraria", "Main", "availableRecipe")
    r.prop_num = q.property("Terraria", "Main", "numAvailableRecipes")
    if r.prop_avail then
        r.get_avail = safe(mod.patch.property_get_method, r.prop_avail)
    end
    if r.prop_num then
        r.get_num = safe(mod.patch.property_get_method, r.prop_num)
    end

    local guide_prop = q.property("Terraria", "Main", "guideItem")
    if guide_prop then r.get_guide = safe(mod.patch.property_get_method, guide_prop) end
    local in_guide_prop = q.property("Terraria", "Main", "InGuideCraftMenu")
    if in_guide_prop then r.in_guide = safe(mod.patch.property_get_method, in_guide_prop) end

    if not (r.m_add and r.f_recipe and r.f_create and r.f_required and r.f_type) then
        return false
    end
    return true
end

local function static_int(class, field)
    local ok, value = pcall(q.get_field_value, "Terraria", class, field, nil, "int32")
    if ok and type(value) == "number" then return value end
    return nil
end

local function call_getter(getter)
    if not getter then return nil end
    local ok, value = pcall(q.call, getter)
    if ok then return value end
    return nil
end

local function available_len()
    local arr = call_getter(r.get_avail)
    if not arr then return nil end
    local ok, len = pcall(mod.patch.array_length, arr)
    if ok and type(len) == "number" then return len end
    return nil
end

local function available_used()
    local n = call_getter(r.get_num)
    if type(n) == "number" then return n end
    return nil
end

local function item_type_of(item)
    if not item or not r.f_type then return nil end
    local ok, value = pcall(q.get_field_value, "Terraria", "Item", "type", item, "int32")
    if ok and type(value) == "number" then return value end
    return nil
end

local function guide_item_type()
    local item = call_getter(r.get_guide)
    if not item then
        local ok, value = pcall(q.get_field_value, "Terraria", "Main",
                "<guideItem>k__BackingField", nil, "object")
        if ok then item = value end
    end
    if not item then
        local ok, value = pcall(q.get_field_value, "Terraria", "Main", "guideItem", nil, "object")
        if ok then item = value end
    end
    return item_type_of(item)
end

-- 这条配方的材料里有没有 item_type
local function uses_item(recipe, item_type)
    if not recipe then return false end
    local list = q.get_object("Terraria", "Recipe", "requiredItem", recipe)
    if not list then return false end
    local ok, len = pcall(mod.patch.array_length, list)
    if not ok or type(len) ~= "number" then return false end
    for j = 0, len - 1 do
        local entry = mod.patch.array_at(list, j)
        if entry then
            if item_type_of(entry) == item_type then return true end
        end
    end
    return false
end

local function result_type_of(recipe)
    local item = q.get_object("Terraria", "Recipe", "createItem", recipe)
    return item_type_of(item)
end

local function recipe_array()
    local ok, arr = pcall(q.get_object, "Terraria", "Main", "recipe", nil)
    if ok then return arr end
    return nil
end

local function array_len(arr)
    if not arr then return nil end
    local ok, len = pcall(mod.patch.array_length, arr)
    if ok and type(len) == "number" then return len end
    return nil
end

-- 第 i 条配方的产物 id（空配方返回 0）
local function recipe_item_type_at(recipes, i)
    if not recipes then return nil end
    local ok, value = pcall(function()
        local recipe = mod.patch.array_at(recipes, i)
        if not recipe then return nil end
        return result_type_of(recipe)
    end)
    if ok then return value end
    return nil
end

local function property_int(class, name)
    local prop = q.property("Terraria", class, name)
    if not prop then return nil end
    local getter = safe(mod.patch.property_get_method, prop)
    local value = call_getter(getter)
    if type(value) == "number" then return value end
    return nil
end

-- 配方总数：字段 → 属性 → 二分探测 Main.recipe 里最后一条非空配方。
-- 这个 PE 版本上 numRecipes 读不到（实测 nil），所以留了探测这条路。
local function total_recipes()
    local total = static_int("Recipe", "numRecipes") or property_int("Recipe", "numRecipes")
    if total and total > 0 then return total end

    local recipes = recipe_array()
    local cap = array_len(recipes)
    if not recipes or not cap or cap <= 0 then return nil end

    local function filled(i)
        local t = recipe_item_type_at(recipes, i)
        return type(t) == "number" and t > 0
    end
    if not filled(0) then return 0 end
    if filled(cap - 1) then return cap end
    local lo, hi = 0, cap - 1
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if filled(mid) then lo = mid else hi = mid - 1 end
    end
    return lo + 1
end

local function vanilla_max()
    return static_int("Recipe", "maxRecipes")
            or property_int("Recipe", "maxRecipes")
            or 3700
end

local function available_contains(index, used)
    local arr = call_getter(r.get_avail)
    if not arr then return false end
    for i = 0, used - 1 do
        local ok, value = pcall(mod.patch.array_at, arr, i, "int32")
        if ok and value == index then return true end
    end
    return false
end

-- 本模组的配方是最后登记的 N 条：按下标验证产物 id 再补，不用扫全表。
local function append_known(item_type)
    local want = recipes.result_ids()
    local n = #want
    if n == 0 then return 0, 0, 0 end

    local total = total_recipes()
    if not total or total < n then return 0, 0, 0 end

    local arr = recipe_array()
    if not arr then return 0, 0, 0 end

    local capacity = available_len() or 3700
    local used = available_used() or 0
    local added, checked, already = 0, 0, 0
    for k = 1, n do
        local index = total - n + (k - 1)
        local got = recipe_item_type_at(arr, index)
        if want[k] and got == want[k] then
            checked = checked + 1
            if available_contains(index, used) then
                already = already + 1          -- 原版自己已经列进去了
            elseif (used + added) < capacity then
                local recipe = mod.patch.array_at(arr, index)
                local okr, hit = pcall(uses_item, recipe, item_type)
                if okr and hit then
                    local okc = pcall(q.call, r.m_add, index)
                    if okc then added = added + 1 end
                end
            end
        end
    end
    return added, checked, already
end

-- 兜底：按 [maxRecipes, total) 扫一遍（配方不在末尾时用）
local function append_by_scan(item_type)
    local total = total_recipes()
    local start = vanilla_max()
    if not total or total <= start then return 0, 0, 0 end

    local recipes_arr = recipe_array()
    if not recipes_arr then return 0, 0, 0 end
    local len = array_len(recipes_arr)
    if len and len < total then total = len end

    local capacity = available_len() or 3700
    local used = available_used() or 0
    local added, scanned, already = 0, 0, 0
    for i = start, total - 1 do
        if (used + added) >= capacity then break end
        scanned = scanned + 1
        local recipe = mod.patch.array_at(recipes_arr, i)
        if recipe then
            local okr, hit = pcall(uses_item, recipe, item_type)
            if okr and hit and recipe_item_type_at(recipes_arr, i) then
                if available_contains(i, used) then goto skip end
                local okc = pcall(q.call, r.m_add, i)
                if okc then added = added + 1 end
            end
            ::skip::
        end
    end
    return added, scanned, already
end

local function append_for(item_type)
    if not item_type or item_type <= 0 then return 0 end
    if not resolve() then return 0 end

    state.total = total_recipes()
    state.capacity = array_len(recipe_array())

    -- 只在「下标校验整批失败」时才退回全表扫描；
    -- added==0 但 checked>0 说明配方已经列过了，不能再扫一遍（会重复）
    state.used = available_used() or 0

    local added, checked, already = append_known(item_type)
    if checked == 0 then
        added, checked, already = append_by_scan(item_type)
    end

    state.scanned = checked or 0
    state.appended = added
    state.had = already or 0
    state.item = item_type
    return added
end

-- 从钩子参数里拿材料 id：可能是 int，也可能是 Item 句柄
local function item_from_args(args)
    if not args then return nil end
    local first = args[1]
    if type(first) == "number" then return first end
    if first ~= nil then
        local ok, valid = pcall(mod.patch.is_valid, first)
        if ok and valid then
            local value = item_type_of(first)
            if value then return value end
        end
    end
    return guide_item_type()
end

local function on_collect(instance, args, result)
    local ok, err = pcall(function()
        local item_type = item_from_args(args)
        state.item = item_type or 0
        if item_type and material_ids[item_type] then
            append_for(item_type)
            return
        end
        -- 读不到向导物品类型时退一步：只要人确实在向导合成界面里，
        -- 就把两种材料的配方都补上（宁可多列，也别又给一片空白）
        if item_type == 0 and call_getter(r.in_guide) then
            for id in pairs(material_ids) do append_for(id) end
        end
    end)
    if not ok then state.error = tostring(err) end
end

-- 兜底路径：万一是 FindRecipes 里直接内联的向导逻辑，就在它返回后补。
local function on_find_recipes(instance, args, result)
    local ok, err = pcall(function()
        local in_guide = call_getter(r.in_guide)
        if not in_guide then return end
        local item_type = guide_item_type()
        if not item_type or not material_ids[item_type] then return end
        append_for(item_type)
    end)
    if not ok then state.error = tostring(err) end
end

local function find_guide_method()
    local found = {}
    local ok, list = pcall(mod.patch.get_methods, r.recipe_type, true)
    if not ok or type(list) ~= "table" then return found end
    for i = 1, #list do
        local m = list[i]
        if m then
            local okn, name = pcall(mod.patch.method_name, m)
            if okn and type(name) == "string" and name:lower():find("guide") then
                local argc = 0
                local oka, n = pcall(mod.patch.method_param_count, m)
                if oka and type(n) == "number" then argc = n end
                found[#found + 1] = { name = name, argc = argc, method = m }
            end
        end
    end
    -- 优先名字里同时带 recipe 的（CollectGuideRecipes）
    for i = 1, #found do
        if found[i].name:lower():find("recipe") then return found, found[i] end
    end
    return found, found[1]
end

function M.register()
    if not resolve() then
        mod.warn("碎晶之链：找不到 Recipe 接口，向导合成提示不可用")
        return
    end

    local shard = q.item_id(ids.item.shard)
    local core = q.item_id(ids.item.core)
    if shard then material_ids[shard] = true end
    if core then material_ids[core] = true end

    local all, best = find_guide_method()
    for i = 1, #all do
        state.candidates[#state.candidates + 1] = all[i].name .. "/" .. all[i].argc
    end

    local installed = {}
    if best then
        local ok = pcall(q.install_hook_postfix, "Terraria", "Recipe", best.method, on_collect)
        if ok then
            installed[#installed + 1] = best.name
            state.argc = best.argc
        end
    end

    -- 顺手也挂 FindRecipes：万一向导内部不走 CollectGuideRecipes，
    -- 这里还能补；重复追加由 append_known 的去重挡住。
    local find_recipes = q.method("Terraria", "Recipe", "FindRecipes", 1)
    if find_recipes then
        local ok = pcall(q.install_hook_postfix, "Terraria", "Recipe", find_recipes, on_find_recipes)
        if ok then installed[#installed + 1] = "FindRecipes" end
    end

    state.via = table.concat(installed, "+")
    state.hooked = #installed > 0
    if not state.hooked then
        mod.warn("碎晶之链：向导合成补扫钩子安装失败，/crystal guide 仍可查")
    end
end

-- 聊天指令用：某个材料能做什么（按我们自己的配方表算，不依赖界面）
function M.uses_of(item_type)
    local out = {}
    if not item_type or item_type <= 0 then return out end
    if not resolve() then return out end

    local total = static_int("Recipe", "numRecipes") or 0
    local recipes = q.get_object("Terraria", "Main", "recipe", nil)
    if not recipes or total <= 0 then return out end
    for i = 0, total - 1 do
        local recipe = mod.patch.array_at(recipes, i)
        if recipe and uses_item(recipe, item_type) then
            out[#out + 1] = { index = i, result = result_type_of(recipe) }
        end
    end
    return out
end

-- 诊断用：配方总数 / 手机端扫描上限 / Main.recipe 数组容量
function M.stats()
    return total_recipes() or 0, vanilla_max() or 0, array_len(recipe_array()) or 0
end

-- 诊断用：材料标记。原版向导要求材料在 ItemID.Sets.IsAMaterial 里为 true。
function M.is_material(item_id)
    if not item_id or item_id <= 0 then return nil end
    local ok, value = pcall(function()
        local item_id_type = q.type("Terraria.ID", "ItemID")
        if not item_id_type then return nil end
        local sets = mod.patch.get_inner_type(item_id_type, "Sets")
        if not sets then return nil end
        local field = mod.patch.get_field(sets, "IsAMaterial")
        if not field then return nil end
        local arr = mod.patch.get_field_value(field, nil, "object")
        if not arr then return nil end
        return mod.patch.array_at(arr, item_id, "bool")
    end)
    if ok then return value end
    return nil
end



-- 一条配方的可读行：名字 xN ← 材料x数量 · 站台
local function recipe_line(arr, index, name)
    local recipe = mod.patch.array_at(arr, index)
    if not recipe then return nil end

    local result = q.get_object("Terraria", "Recipe", "createItem", recipe)
    local stack = 1
    if result then
        local ok, value = pcall(q.get_field_value, "Terraria", "Item", "stack", result, "int32")
        if ok and type(value) == "number" and value > 0 then stack = value end
    end

    local parts = {}
    local list = q.get_object("Terraria", "Recipe", "requiredItem", recipe)
    local n = array_len(list) or 0
    for j = 0, math.min(n, 4) - 1 do
        local item = mod.patch.array_at(list, j)
        if item then
            local t = item_type_of(item)
            if t and t > 0 then
                local count = 1
                local ok, value = pcall(q.get_field_value, "Terraria", "Item", "stack", item, "int32")
                if ok and type(value) == "number" and value > 0 then count = value end
                parts[#parts + 1] = ("%sx%d"):format(
                        util.item_name(t) or ("#" .. tostring(t)), count)
            end
        end
    end

    local station = nil
    local okt, tiles = pcall(q.get_field_value, "Terraria", "Recipe", "requiredTile", recipe)
    if okt and tiles then
        local ok2, tile = pcall(mod.patch.array_at, tiles, 0, "int32")
        if ok2 and type(tile) == "number" and tile >= 0 then station = tile end
    end

    local line = ("%s x%d ← %s"):format(name, stack, table.concat(parts, " "))
    if station then
        line = line .. " · " .. (recipes.station(station) or ("#" .. tostring(station)))
    end
    return line
end

-- 在整张配方表里按「成品名」搜（原版物品也能查）
function M.search(query, limit)
    local out = {}
    if type(query) ~= "string" or query == "" then return out end
    local needle = query:lower()
    local total = total_recipes()
    local arr = recipe_array()
    if not total or not arr then return out end
    local max = array_len(arr) or total
    if max > total then max = total end

    local cap = limit or 4
    for i = 0, max - 1 do
        local t = recipe_item_type_at(arr, i)
        if t and t > 0 then
            local name = util.item_name(t)
            if name and name:lower():find(needle, 1, true) then
                local ok, line = pcall(recipe_line, arr, i, name)
                if ok and line then out[#out + 1] = line end
                if #out >= cap then break end
            end
        end
    end
    return out
end

-- 诊断用：把「配方落在哪、材料长什么样、原版列了几条」一次性说清
local function recipe_mats(recipe, limit)
    local parts = {}
    local list = q.get_object("Terraria", "Recipe", "requiredItem", recipe)
    local n = array_len(list) or 0
    for j = 0, math.min(n, limit or 3) - 1 do
        local item = mod.patch.array_at(list, j)
        if item then
            local t = item_type_of(item)
            local stack = nil
            local ok, value = pcall(q.get_field_value, "Terraria", "Item", "stack", item, "int32")
            if ok then stack = value end
            parts[#parts + 1] = ("%sx%s"):format(tostring(t), tostring(stack))
        end
    end
    return table.concat(parts, " ")
end

function M.dump()
    local lines = {}
    local total, max, size = M.stats()
    lines[#lines + 1] = ("配方%s 上限%s 数组%s"):format(
            tostring(total), tostring(max), tostring(size))

    local want = recipes.result_ids()
    local arr = recipe_array()
    local first, last
    if total and arr and #want > 0 then
        for i = math.max(0, total - #want - 16), total - 1 do
            local t = recipe_item_type_at(arr, i)
            if t then
                for k = 1, #want do
                    if want[k] and t == want[k] then
                        if not first then first = i end
                        last = i
                        break
                    end
                end
            end
        end
    end

    if first then
        lines[#lines + 1] = ("本模组配方下标 %d-%d"):format(first, last)
        local ok, recipe = pcall(mod.patch.array_at, arr, first)
        if ok and recipe then
            local okm, mats = pcall(recipe_mats, recipe, 3)
            if okm and mats and mats ~= "" then
                lines[#lines + 1] = "首条材料 " .. mats
            end
        end
    else
        lines[#lines + 1] = "Main.recipe 里没找到本模组配方"
    end

    lines[#lines + 1] = ("向导 物品=%d 列表=%d 已有=%d 补=%d"):format(
            state.item or 0, state.used or 0, state.had or 0, state.appended or 0)
    return lines
end

function M.debug_line()
    return ("物品=%d 补=%d 扫=%d 挂=%s(%d)")
            :format(state.item or 0, state.appended or 0, state.scanned or 0,
                    tostring(state.via), state.argc or 0)
end

function M.capacity()
    return state.capacity or array_len(recipe_array())
end

return M
