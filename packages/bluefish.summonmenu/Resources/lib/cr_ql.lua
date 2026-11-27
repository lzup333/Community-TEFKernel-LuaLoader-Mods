-- 向导「材料 → 可制作」补写（手机版专用）
--
-- ★ 事实来源（PE 1.4.5.8 dump.cs + 13.8.3 实测）：
--   手机版的向导界面是独立的一套类，跟 PC 完全不同：
--
--     // Namespace: （空）
--     public class GUICraftGuide        // TypeDefIndex 330  ── 材料选择页
--     public class GUICraftGuidePopup   // TypeDefIndex 331  ── 配方列表弹窗
--     {
--         public Item materialToolTip;            0x50   当前选中的材料
--         public int  focusGuideRecipe;           0xCC
--         public int[] availableGuideRecipe;      0xD0   ★ 向导自己的可用配方数组
--         public int  numAvailableGuideRecipes;   0xD8   ★ 向导自己的计数
--         public void FindRecipes() { }                   ★ 向导自己的查找（0x8FF550）
--     }
--
--   所以：
--     · 补 Main.availableRecipe 完全无效 —— 向导不看这个数组
--     · 挂 Recipe.CollectGuideRecipes 无效 —— 手机版向导不调它（实测 calls=0）
--     · 挂 Recipe.FindRecipes 也无效 —— 那是制作界面用的，向导走自己的 FindRecipes
--
--   正解：hook GUICraftGuidePopup.FindRecipes() 的 postfix，
--         回调的 instance 参数就是弹窗实例，直接往它的 availableGuideRecipe 里补。
local q = mod.quickapi
local ok_hb, HB = pcall(require, "cr_hookbox")
if not ok_hb then HB = nil end
local M = {}

local BOOT_MARK = "v16.0.0"
local LOG = "[CRQL]"
local function log(msg)
    pcall(mod.info, LOG .. " " .. tostring(msg))
end

log("顶层已执行 " .. BOOT_MARK)

local CUSTOM_ID_MIN = 6196      -- 自定义物品 id 段起点（原版最大 6195，含 6000~6195 的 1.4.5 新物品）

local state = {
    phase = "init",
    err = nil,
    calls = 0,          -- FindRecipes 被调用次数
    total = 0,          -- numRecipes
    cap = 0,            -- Main.recipe 数组容量
    used = 0,           -- 向导列表当前条数
    popup_cap = 0,      -- availableGuideRecipe 数组容量
    material = 0,       -- 当前材料 id
    mat_src = "-",      -- 材料来源（tooltip / guideItem / none）
    sel = -1,           -- 弹窗 _selectedItem 原值
    infer_best = 0,     -- 反推得到的材料 id
    infer_n = 0,        -- 该材料覆盖的配方数
    infer_total = 0,    -- 参与统计的配方数
    scanned = 0,        -- 扫到的有效配方数
    added = 0,          -- 本次补写条数
    added_total = 0,    -- 累计补写条数
    already = 0,        -- 已列过条数
    mod_seen = 0,       -- 越界段里模组配方条数
    mod_first = -1,     -- 第一条模组配方下标
    type_name = "-",
}
M.state = state

local r = {}
local cached_guide_mat = 0        -- GUICraftGuide.guideItem 最近一次返回的物品类型
local result_type_of
local handle_find = nil
local handle_guide = nil

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function array_len(arr)
    if not arr then return nil end
    local ok, len = pcall(mod.patch.array_length, arr)
    if ok and type(len) == "number" then return len end
    return nil
end

local function item_type_of(item)
    if not item or not r.f_item_type then return nil end
    local ok, value = pcall(mod.patch.get_field_value, r.f_item_type, item, "int32")
    if ok and type(value) == "number" then return value end
    return nil
end

-- GUICraftGuidePopup 在全局命名空间（Namespace 为空），保险起见多试几个
local NAMESPACES = { "", "Terraria", "Terraria.UI", "Terraria.GameContent.UI" }
local function find_type(cls)
    for i = 1, #NAMESPACES do
        local ok, t = pcall(q.type, NAMESPACES[i], cls)
        if ok and t then return t, NAMESPACES[i] end
    end
    return nil, nil
end

local function resolve()
    if r.popup_type and r.f_avail and r.f_num then return true end
    if not r.popup_type then
        r.popup_type, r.ns = find_type("GUICraftGuidePopup")
    end
    if not r.popup_type then return false end
    if not r.f_avail then
        r.f_avail = safe(mod.patch.get_field, r.popup_type, "availableGuideRecipe")
    end
    if not r.f_num then
        r.f_num = safe(mod.patch.get_field, r.popup_type, "numAvailableGuideRecipes")
    end
    if not r.f_mat then
        r.f_mat = safe(mod.patch.get_field, r.popup_type, "materialToolTip")
    end
    if not r.f_sel then
        r.f_sel = safe(mod.patch.get_field, r.popup_type, "_selectedItem")
    end
    if not r.f_item_type then
        r.f_item_type = safe(q.field, "Terraria", "Item", "type")
    end
    -- v13.36.0：手机版真正的「当前选中材料」在 GUICraftGuide.guideItem 属性上
    --   （dump.cs：public Item guideItem { get; } → get_guideItem 0x8FE928）
    --   弹窗那边的 materialToolTip 只是「鼠标悬停的提示物」，不一定是当前材料。
    --   这里挂 getter 的 postfix，把每次返回的 Item 类型缓存下来，当成第一来源。
    if not r.guide_type then
        r.guide_type = find_type("GUICraftGuide")
    end
    if r.guide_type and not r.m_guide then
        r.m_guide = safe(mod.patch.get_method, r.guide_type, "get_guideItem", 0)
    end
    -- v13.37.0：dump.cs 里 GUIInstance 有 `public static GUIInstance Active;`（0x0），
    --   里面挂着 `public GUICraftGuide GUICraftGuide;`（0xC8）。
    --   顺着这条路能实时拿到向导主界面的实例，再调它的 guideItem 属性，
    --   这是「当前选中材料」最权威、也不会有缓存过期的读法。
    if not r.guiinst_type then
        r.guiinst_type = find_type("GUIInstance")
    end
    if r.guiinst_type and not r.f_guide_inst then
        r.f_guide_inst = safe(mod.patch.get_field, r.guiinst_type, "GUICraftGuide")
    end
    return (r.f_avail ~= nil) and (r.f_num ~= nil)
end

-- 当前选中的材料 id：三个来源依次尝试，取第一个非 0 的
--   ① 弹窗的 materialToolTip（0x50）—— 指向当前材料
--   ② Main.guideItem 属性      —— 手机版选材料时原版会写这里
--   ③ 弹窗的 _selectedItem（0xC4）—— 材料网格里的索引
-- v13.37.0：实时读「向导当前选中的材料」。
--   路线：GUIInstance.Active → .GUICraftGuide → 调 get_guideItem() → Item.type
--   每次都现读，不存在缓存过期的问题。
local function live_material()
    if not (r.guiinst_type and r.f_guide_inst and r.m_guide) then return 0 end
    local active = safe(q.get_object, "", "GUIInstance", "Active", nil)
    if not active then return 0 end
    local guide = safe(mod.patch.get_field_value, r.f_guide_inst, active, "object")
    if not guide then return 0 end
    local ok, item = pcall(mod.patch.invoke, r.m_guide, guide)
    if not ok or not item then return 0 end
    local t = item_type_of(item)
    if t and t > 0 then return t end
    return 0
end

local function current_material(inst)
    -- ① 实时读向导主界面（最准）
    local live = live_material()
    if live > 0 then
        state.sel = live
        return live, "live"
    end
    -- ② 弹窗的 materialToolTip（0x50）—— 原版在这里放当前材料
    local item = safe(mod.patch.get_field_value, r.f_mat, inst, "object")
    if item then
        local t = item_type_of(item)
        if t and t > 0 then
            state.sel = t
            return t, "tooltip"
        end
    end
    -- ③ GUICraftGuide.guideItem 的缓存（getter 钩子存下的上一手值）
    if cached_guide_mat > 0 then
        state.sel = cached_guide_mat
        return cached_guide_mat, "guideItem"
    end
    -- ② 弹窗的 _selectedItem（0xC4）—— 材料网格索引
    if r.f_sel then
        local sel = safe(mod.patch.get_field_value, r.f_sel, inst, "int32")
        if type(sel) == "number" and sel >= 0 then state.sel = sel end
    end
    return 0, "none"
end

-- ---------- 配方表 ----------
local function recipe_array()
    local ok, arr = pcall(q.get_object, "Terraria", "Main", "recipe", nil)
    if ok and arr then return arr end
    return nil
end

local function total_recipes()
    local ok, v = pcall(q.get_field_value, "Terraria", "Recipe", "numRecipes", nil, "int32")
    if ok and type(v) == "number" and v > 0 then return v end
    return 0
end

result_type_of = function(recipe)
    if not recipe then return nil end
    local item = safe(q.get_object, "Terraria", "Recipe", "createItem", recipe)
    return item_type_of(item)
end

-- 材料读不到时的兜底：用「原版已经填好的配方列表」反推当前选中的材料。
-- 原理：向导列出的每条配方都必然用到当前材料，所以「出现在所有已列配方里」
-- 的那个物品，就是当前选中的材料。
local function infer_material(avail, num)
    if not avail or num <= 0 then return 0 end
    local arr = recipe_array()
    if not arr then return 0 end
    local limit = num - 1
    if limit > 199 then limit = 199 end      -- 最多统计 200 条已列配方
    local count, total = {}, 0
    for k = 0, limit do
        local idx = safe(mod.patch.array_at, avail, k, "int32")
        if type(idx) == "number" then
            local recipe = mod.patch.array_at(arr, idx)
            if recipe then
                total = total + 1
                local list = safe(q.get_object, "Terraria", "Recipe", "requiredItem", recipe)
                local len = list and array_len(list) or 0
                local seen = {}
                for j = 0, len - 1 do
                    local e = mod.patch.array_at(list, j)
                    local t = item_type_of(e)
                    if t and t > 0 and not seen[t] then
                        seen[t] = true
                        count[t] = (count[t] or 0) + 1
                    end
                end
            end
        end
    end
    if total == 0 then return 0 end
    local best, best_n = 0, 0
    for t, n in pairs(count) do
        if n > best_n then best, best_n = t, n end
    end
    state.infer_best = best
    state.infer_n = best_n
    state.infer_total = total
    -- 至少覆盖 80% 的已列配方，才认定它是当前选中的材料
    if best_n >= math.ceil(total * 0.8) then return best end
    return 0
end

-- ---------- 配方索引缓存（v13.35.0） ----------
-- 白名单 = main.lua 里 RCP 表登记过的产物 id ∪ 自定义物品段（>=6000）。
-- 这样向导列出的内容与配方表同源，不会出现「表里有、向导没有」。
local want_set = nil
local want_count = 0
local index_cache = { key = "", entries = {} }

local function wants()
    if want_set then return want_set, want_count end
    local set = {}
    local n = 0
    local list = rawget(_G, "ms_rcp_list")
    if type(list) == "table" then
        for i = 1, #list do
            local row = list[i]
            local id = type(row) == "table" and row.result or nil
            if type(id) == "number" and id > 0 and not set[id] then
                set[id] = true
                n = n + 1
            end
        end
    end
    -- 拿不到配方表就不缓存，下次调用再试（避免首次时机太早导致白名单永远是空的）
    if n > 0 then
        want_set = set
        want_count = n
    end
    return set, n
end

-- 扫整个配方数组，只留「产物在白名单里」的条目：{ idx, result, mats }
local function recipe_index(arr, limit)
    local w, wn = wants()
    local key = tostring(limit) .. "/" .. tostring(wn)
    if index_cache.key == key and #index_cache.entries > 0 then
        return index_cache.entries
    end
    local out = {}
    for i = 0, limit - 1 do
        local recipe = mod.patch.array_at(arr, i)
        if recipe then
            local rt = result_type_of(recipe)
            -- 只认白名单产物；白名单拿不到时也只认自定义 id 段，
            -- 绝不退化成「所有配方」——否则选一个材料会把全表塞进向导。
            if rt and rt > 0 and (w[rt] or rt >= CUSTOM_ID_MIN) then
                local mats = {}
                local list = safe(q.get_object, "Terraria", "Recipe", "requiredItem", recipe)
                local n = list and array_len(list) or 0
                for j = 0, n - 1 do
                    local it = mod.patch.array_at(list, j)
                    local t = item_type_of(it)
                    if t and t > 0 then mats[t] = true end
                end
                out[#out + 1] = { idx = i, result = rt, mats = mats }
            end
        end
    end
    index_cache.entries = out
    index_cache.key = key
    log(("索引重建：白名单 %d 个产物，命中 %d 条配方，上限 %d"):format(want_count, #out, limit))
    return out
end

-- ---------- 核心：往向导弹窗自己的列表里补 ----------
local function fill_popup(inst)
    if not resolve() then
        state.err = "GUICraftGuidePopup 接口缺失"
        return 0
    end
    if not inst then
        state.err = "回调没给到实例"
        return 0
    end
    local avail = safe(mod.patch.get_field_value, r.f_avail, inst, "object")
    if not avail then
        state.err = "availableGuideRecipe 读不到"
        return 0
    end
    local cap = array_len(avail) or 0
    state.popup_cap = cap
    local num = safe(mod.patch.get_field_value, r.f_num, inst, "int32") or 0
    if type(num) ~= "number" or num < 0 then num = 0 end
    if cap > 0 and num > cap then num = cap end
    state.used = num

    -- 当前选中的材料（多来源）
    local ok_m, mat, mat_src = pcall(current_material, inst)
    if not ok_m then
        state.err = "材料读取异常: " .. tostring(mat)
        mat, mat_src = 0, "error"
    end
    if (not mat or mat == 0) then
        local ok_i, m2 = pcall(infer_material, avail, num)
        if ok_i and type(m2) == "number" and m2 > 0 then
            mat, mat_src = m2, "inferred"
        elseif not ok_i then
            state.err = "反推异常: " .. tostring(m2)
        end
    end
    state.material = mat or 0
    state.mat_src = mat_src or "-"
    -- 材料没确定就绝不补写：否则「所有模组配方」都会被塞进向导列表
    if not mat or mat == 0 then
        if not state.err then state.err = "材料未确定，跳过本轮" end
        return 0
    end

    local arr = recipe_array()
    if not arr then
        state.err = "Main.recipe 读不到"
        return 0
    end
    local reported = total_recipes()
    local arr_cap = array_len(arr) or 0
    -- v13.36.0：上限优先用 numRecipes（真实条数），再留 200 条余量兜住
    -- 「数组写了但计数没加」的情况；绝不按数组容量全扫（容量可能是条数的好几倍）。
    local limit = reported + 200
    if arr_cap > 0 and limit > arr_cap then limit = arr_cap end
    if limit <= 0 then limit = arr_cap end
    state.total = reported
    state.cap = arr_cap
    if limit <= 0 then
        state.err = "配方数组为空"
        return 0
    end

    -- 已列出的下标集合
    local exists = {}
    for i = 0, num - 1 do
        local ok, v = pcall(mod.patch.array_at, avail, i, "int32")
        if ok and type(v) == "number" then exists[v] = true end
    end

    local added, scanned, already = 0, 0, 0
    local mod_seen, mod_first = 0, -1
    -- v13.35.0：改成「白名单 + 索引缓存」。
    --   · 白名单 = RCP 表里登记过的产物 id ∪ 自定义物品段(>=6000)
    --   · 首次扫一遍配方数组，把命中的条目记成 { idx, result, mats }，
    --     之后每次点材料只遍历这份缓存 —— 不再用固定下标起点、
    --     也不再因为连续空槽提前退出，所以不会再漏配方。
    local entries = recipe_index(arr, limit)
    scanned = #entries
    for k = 1, #entries do
        local e = entries[k]
        local i = e.idx
        if e.result >= CUSTOM_ID_MIN then
            mod_seen = mod_seen + 1
            if mod_first < 0 or i < mod_first then mod_first = i end
        end
        if e.mats[mat] then
            if exists[i] then
                already = already + 1
            elseif cap > 0 and num >= cap then
                state.err = "向导列表已满"
                break
            else
                local ok_w = pcall(mod.patch.array_set, avail, num, i, "int32")
                if ok_w then
                    exists[i] = true
                    num = num + 1
                    added = added + 1
                end
            end
        end
    end

    state.scanned = scanned
    state.already = already
    state.mod_seen = mod_seen
    state.mod_first = mod_first
    if added > 0 then
        pcall(mod.patch.set_field_value, r.f_num, inst, num, "int32")
        state.added = added
        state.added_total = state.added_total + added
        state.err = nil
    else
        state.added = 0
    end
    return added
end
M.fill_popup = fill_popup

-- ---------- 钩子 ----------
-- GUICraftGuidePopup.FindRecipes() 是实例方法，回调 (instance, args, result)
local function on_find(instance, args, result)
    state.calls = state.calls + 1
    pcall(function()
        fill_popup(instance)
    end)
end

function M.register()
    -- 没有内容要注册
end

function M.hooks_on()
    state.phase = "hooks_on 进入"
    local ok_res = resolve()

    -- v13.36.0：先挂 GUICraftGuide.guideItem 的 postfix，缓存「当前选中材料」。
    --   只读不写，拿不到返回值也没有副作用。
    if r.m_guide and not handle_guide then
        local okg, hg = pcall(mod.patch.install_hook, r.m_guide, {
            postfix = function(self, args, result)
                local t = item_type_of(result)
                if t and t > 0 then cached_guide_mat = t end
            end,
        })
        if okg and hg then
            if HB then pcall(HB.add, hg) end
            handle_guide = hg
        end
    end
    state.type_name = r.popup_type and "GUICraftGuidePopup" or "未找到"
    state.phase = "resolve ok=" .. tostring(ok_res) .. " type=" .. state.type_name
    if not r.popup_type then
        state.err = "找不到 GUICraftGuidePopup 类"
        return false
    end

    local m = safe(mod.patch.get_method, r.popup_type, "FindRecipes", 0)
    if not m then
        state.err = "找不到 GUICraftGuidePopup.FindRecipes()"
        return false
    end
    local ok, h = pcall(mod.patch.install_hook, m, { postfix = on_find })
    if ok and h then
        if HB then pcall(HB.add, h) end
        handle_find = h
        state.phase = "hooks_on 完成 FindRecipes 钩子已装"
        state.err = nil
    else
        state.phase = "hooks_on 完成 但钩子安装失败"
        state.err = "install_hook 失败: " .. tostring(h)
    end
    log("hooks_on 完成 handle=" .. tostring(handle_find ~= nil))
    return handle_find ~= nil
end

function M.report()
    return ("calls=%d used=%d added_total=%d mod=%d first=%d"):format(
            state.calls, state.used, state.added_total, state.mod_seen, state.mod_first)
end

return M