-- Copyright (C) 2026 lzup333
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- 创造模式菜单 (Creative Menu) —— LuaLoader Lua Mod
--
-- 基于 LuaLoader 原生 GUI (mod.gui)。物品/生物的生成方式参考 ChatCommands 模组：
--   * 物品: Android 用 Item.NewItem(9 参)，桌面用 Player.QuickSpawnItem(source=nil,id,stack)
--           —— 直接生成到世界（而不是手工 new Item + SetDefaults 塞背包，那种做法会崩/出错）；
--   * 生物: NPC.NewNPC(source=nil, X, Y, Type, 0, ai0..3, Target)，在玩家脚下生成；
--   * 无敌: 每帧 postfix Hook Player.ResetEffects 强制 creativeGodMode。
--
-- 界面：窗口收起后是一个可拖动的小图标（皮肤图片），点开展开面板；配色走扁平简约风。
-- 搜索：支持汉字 / 全拼 / 首字母，以及**微软双拼**；多音字（行 xing/hang、乐 le/yue …）
--       的全部读音都会参与匹配，可在设置里切换拼音识别方式。
--
-- 目标版本 1.4.5.8（ItemID.Count=6196, NPCID.Count=697 写死）。

mod.meta = { pkg_id = "lzup.lua.creativemenu", version = "1.1.0" }

local patch = mod.patch

local ITEM_COUNT = 6196
local NPC_COUNT  = 697

-- 简约风尺寸
local WIDTH    = 510 -- 窗口宽（窄了会挤，这里留足）
local COLS     = 3
local PER_PAGE = 18

-- ============ 配置 ============
-- 与 Info.json 的 settings / Resources/config.json 保持一致
local DEFAULTS = {
    pinyin_mode = "full", -- full = 全拼，ms = 微软双拼
}

local CONFIG_FILE = "config.json"
local cfg = {}

local function load_config()
    local values = {}
    for k, v in pairs(DEFAULTS) do values[k] = v end
    local ok, dkjson = pcall(require, "dkjson")
    local text = mod.read_file(CONFIG_FILE)
    if ok and type(text) == "string" then
        local raw = dkjson.decode(text)
        local src = raw and raw.values
        if type(src) == "table" then
            for k, default in pairs(DEFAULTS) do
                if type(src[k]) == type(default) then values[k] = src[k] end
            end
        end
    end
    if values.pinyin_mode ~= "full" and values.pinyin_mode ~= "ms" then
        values.pinyin_mode = "full"
    end
    return values
end

--- 在面板里改了设置就写回 config.json（下次启动照旧）
local function save_config()
    local ok, dkjson = pcall(require, "dkjson")
    if not ok then return end
    local ok2, text = pcall(dkjson.encode, { schemaVersion = 1, values = cfg }, { indent = true })
    if ok2 and text then mod.write_file(CONFIG_FILE, text) end
end

-- ============ 拼音 ============
local pinyin = {}
do
    local ok, t = pcall(require, "pinyin")
    if ok and type(t) == "table" then pinyin = t end
end

-- 无声调拼音 → 微软双拼两键（键位取自 RIME 的 double_pinyin_mspy 方案）
local MS_FINAL = {
    a = "a", o = "o", e = "e", i = "i", u = "u", v = "y",
    ai = "l", ei = "z", ao = "k", ou = "b", an = "j", en = "f", ang = "h",
    eng = "g", er = "r",
    ia = "w", ie = "x", iao = "c", iu = "q", ian = "m", iang = "d", iong = "s",
    -- 微软双拼原本把 ing 放在 ';' 上，但 LuaLoader 的虚拟键盘打不出符号，
    -- 所以这里把 in / ing 都放在 n 键上（搜索只做子串匹配，不会因此变差）
    ["in"] = "n", ing = "n",
    ua = "w", uo = "o", uai = "y", ui = "v", uan = "r", un = "p", uang = "d",
    ong = "s",
    ue = "t", ve = "t", van = "r", vn = "p",
}

local function ms_syllable(py)
    if py:match("^[aoe]") then
        return "o" .. (MS_FINAL[py] or py:sub(1, 1)) -- 零声母统一加 o
    end
    local initial, final
    local two = py:sub(1, 2)
    if two == "zh" or two == "ch" or two == "sh" then
        initial, final = ({ zh = "v", ch = "i", sh = "u" })[two], py:sub(3)
    else
        initial, final = py:sub(1, 1), py:sub(2)
    end
    -- ju/qu/xu/yu 的 u 其实读 ü
    if final == "u" and (initial == "j" or initial == "q" or initial == "x" or initial == "y") then
        final = "v"
    end
    local key = MS_FINAL[final]
    if not key then key = final ~= "" and final:sub(1, 1) or "" end
    return initial .. key
end

--- 一个汉字的全部读音（返回数组；非汉字返回 nil）
local function readings_of(cp)
    local v = pinyin[cp]
    if type(v) == "string" then return { v } end
    if type(v) == "table" then return v end
    return nil
end

local MAX_VARIANTS = 8

--- 名字 → 三串候选（以 \1 分隔）：全拼 / 首字母 / 微软双拼
local function to_keys(name)
    local variants = { { p = "", i = "", s = "" } }
    local ok, iter, st, var = pcall(utf8.codes, name)
    if not ok then return "", "", "" end

    for _, cp in iter, st, var do
        local list = readings_of(cp)
        if list then
            local next_variants = {}
            for _, v in ipairs(variants) do
                for _, py in ipairs(list) do
                    next_variants[#next_variants + 1] = {
                        p = v.p .. py,
                        i = v.i .. py:sub(1, 1),
                        s = v.s .. ms_syllable(py),
                    }
                end
            end
            variants = next_variants
            for k = MAX_VARIANTS + 1, #variants do variants[k] = nil end
        else
            local ch = utf8.char(cp)
            for _, v in ipairs(variants) do
                v.p, v.i, v.s = v.p .. ch, v.i .. ch, v.s .. ch
            end
        end
    end

    local ps, is, ss = {}, {}, {}
    for _, v in ipairs(variants) do
        ps[#ps + 1], is[#is + 1], ss[#ss + 1] = v.p, v.i, v.s
    end
    local function join(list)
        local seen, out = {}, {}
        for _, s in ipairs(list) do
            if not seen[s] then seen[s] = true; out[#out + 1] = s end
        end
        return table.concat(out, "\1")
    end
    return join(ps), join(is), join(ss)
end

local function matches(needle, name, py, ini, ms)
    if needle == "" then return true end
    if name:lower():find(needle, 1, true) then return true end
    if ini and ini:find(needle, 1, true) then return true end
    if cfg.pinyin_mode == "ms" then
        return ms ~= nil and ms:find(needle, 1, true) ~= nil
    end
    return py ~= nil and py:find(needle, 1, true) ~= nil
end

-- ============ 类型 / 句柄 ============
local T_main, T_player, T_item, T_npc, T_lang

local F_main_player, F_my_player, M_get_my_player
local F_pos, F_width, F_height
local F_stat_life, F_stat_life_max, F_stat_mana, F_stat_mana_max
local F_creative_god
local F_day_time, F_time, F_raining, F_rain_time, F_blood_moon, F_eclipse, F_slime_rain

local M_new_text
local M_new_item         -- Android: Item.NewItem(9)
local M_quick_spawn      -- 桌面: Player.QuickSpawnItem(source,item,stack)
local M_new_npc          -- NPC.NewNPC(10)
local M_get_item_name, M_get_npc_name
local M_reset_effects

local god_mode = false
local ready = false

-- ============ 状态 ============
local tab = 1
local item_filter, item_page, item_stack = "", 0, 1
local npc_filter, npc_page, npc_count = "", 0, 1
local item_names, item_py, item_ini, item_ms
local npc_names, npc_py, npc_ini, npc_ms
local item_filter_cache, item_list_cache
local npc_filter_cache, npc_list_cache
local dirty = true -- 需要重建列表

-- ============ 工具 ============
--- patch.get_method_by_names 在老加载器上可能没有；取不到就返回 nil，别让 setup 崩
local function method_by_names(type_handle, name, param_names)
    if not patch.get_method_by_names then return nil end
    local ok, m = pcall(patch.get_method_by_names, type_handle, name, param_names)
    return ok and m or nil
end

local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local f = patch.get_field(cur, name)
        if f then return f end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function get_i32(field, inst, default)
    if not field then return default end
    local v = patch.get_field_value(field, inst, "int32")
    return v == nil and default or v
end

local function get_bool(field, inst, default)
    if not field then return default end
    local v = patch.get_field_value(field, inst, "bool")
    return v == nil and default or v
end

local function set_bool(field, inst, value)
    if field then patch.set_field_value(field, inst, value and true or false, "bool") end
end

local function set_i32(field, inst, value)
    if field then patch.set_field_value(field, inst, value, "int32") end
end

local function set_double(field, inst, value)
    if field then patch.set_field_value(field, inst, value, "double") end
end

local function my_player_index()
    if M_get_my_player then
        local v = patch.invoke(M_get_my_player)
        if type(v) == "number" then return v end
    end
    if F_my_player then
        local v = patch.get_field_value(F_my_player, nil, "int32")
        if type(v) == "number" then return v end
    end
    return -1
end

local function local_player()
    if not F_main_player then return nil end
    local idx = my_player_index()
    if idx < 0 then return nil end
    local arr = patch.get_field_value(F_main_player, nil, "object")
    if not arr then return nil end
    local n = patch.array_length(arr)
    if idx >= n then return nil end
    return patch.array_at(arr, idx)
end

local function notify(msg)
    if not M_new_text then return end
    pcall(function()
        local s = patch.string_create(msg)
        if not s then return end
        if mod.platform == "android" then
            patch.invoke(M_new_text, s, 255, 220, 120, false)
        else
            patch.invoke(M_new_text, s, 255, 220, 120)
        end
    end)
end

-- ============ 给予物品（参考 ChatCommands） ============
local function give_item(player, id, stack)
    if not player then return false end
    -- 这些调用跨到托管侧，包一层 pcall：失败只提示，不让异常从 GUI 回调里抛出去
    local ok = pcall(function()
        if mod.platform == "android" then
            if not M_new_item then error("no NewItem") end
            local px, py = patch.get_field_vec2(F_pos, player)
            if not px then error("no position") end
            local w = get_i32(F_width, player, 0)
            local h = get_i32(F_height, player, 0)
            -- NewItem(X, Y, Width, Height, Type, Stack, noBroadcast, pfix, ownership)
            patch.invoke(M_new_item, math.floor(px), math.floor(py), math.floor(w),
                math.floor(h), id, stack, false, 0, 0)
        else
            -- 桌面: Player.QuickSpawnItem(source, item, stack)，source 传 nil 安全
            if not M_quick_spawn then error("no QuickSpawnItem") end
            patch.invoke(M_quick_spawn, player, nil, id, stack)
        end
    end)
    return ok
end

-- ============ 召唤生物（参考 ChatCommands） ============
local function summon_npc(player, id, count)
    if not player or not M_new_npc then return false end
    return pcall(function()
        local px, py = patch.get_field_vec2(F_pos, player)
        if not px then error("no position") end
        local w = get_i32(F_width, player, 0)
        local h = get_i32(F_height, player, 0)
        local bx = math.floor(px) + math.floor(w / 2)
        local by = math.floor(py) + math.floor(h)
        for i = 0, count - 1 do
            local sx = bx + (i % 8) * 24 - 84
            local sy = by + math.floor(i / 8) * 24
            patch.invoke(M_new_npc, nil, sx, sy, id, 0, 0.0, 0.0, 0.0, 0.0, 255)
        end
    end)
end

-- ============ 世界 / 玩家 ============
local function set_time(day, t)
    set_bool(F_day_time, nil, day)
    set_double(F_time, nil, t)
end

local function heal()
    local p = local_player()
    if not p then return end
    set_i32(F_stat_life, p, get_i32(F_stat_life_max, p, 100))
    set_i32(F_stat_mana, p, get_i32(F_stat_mana_max, p, 20))
end

-- ============ 名称缓存 ============
local function lang_name(method, id)
    if not method then return nil end
    local ok, h = pcall(patch.invoke, method, id)
    if not ok or not h or h == false then return nil end
    local ok2, s = pcall(patch.string_value, h)
    if ok2 and type(s) == "string" then return s end
    return nil
end

local function build_names(names, py, ini, ms, method, maxid)
    if not method then return end
    local started, count = os.clock(), 0
    for id = 1, maxid do
        local name = lang_name(method, id)
        if name and name ~= "" then
            names[id] = name
            local p, i, s = to_keys(name)
            py[id], ini[id], ms[id] = p, i, s
            count = count + 1
        end
    end
    mod.info(string.format("建立名称索引：%d 项，用时 %.2fs", count, os.clock() - started))
end

local function build_item_names()
    if item_names then return end
    item_names, item_py, item_ini, item_ms = {}, {}, {}, {}
    build_names(item_names, item_py, item_ini, item_ms, M_get_item_name, ITEM_COUNT - 1)
end

local function build_npc_names()
    if npc_names then return end
    npc_names, npc_py, npc_ini, npc_ms = {}, {}, {}, {}
    build_names(npc_names, npc_py, npc_ini, npc_ms, M_get_npc_name, NPC_COUNT - 1)
end

local function compute_list(names, py, ini, ms, filter, maxid)
    local list = {}
    local needle = filter:lower()
    if needle == "" then
        for id = 1, maxid do
            if names[id] then list[#list + 1] = id end
        end
    else
        for id, name in pairs(names) do
            if matches(needle, name, py[id], ini[id], ms[id]) then list[#list + 1] = id end
        end
    end
    table.sort(list)
    return list
end

-- ============ GUI ============
--
-- 只使用内置即时模式控件（它们共用一个布局光标，不会互相叠），用 same_line 让下一个控件
-- 同行；不再自己算坐标摆控件（之前两套坐标混用导致控件叠在一起）。
-- 当前页签用方括号标出，也就不用为了高亮去做自定义绘制。

local g -- mod.gui（每帧刷新引用）
local images = {} -- 皮肤图片（面板底 + 收起入口图标）

--- 按「显示宽度」截断，保证网格里的按钮宽度接近
local function fit_label(s, cells)
    local out, width = {}, 0
    local ok, iter, st, var = pcall(utf8.codes, s)
    if not ok then return s end
    for _, cp in iter, st, var do
        local w = cp > 0x2E7F and 2 or 1
        if width + w > cells then return table.concat(out) .. "…" end
        out[#out + 1] = utf8.char(cp)
        width = width + w
    end
    local text = table.concat(out)
    return text .. string.rep(" ", math.max(0, cells - width))
end

--- 顶栏页签
local function draw_tabs()
    local tabs = { "物品", "生物", "世界", "玩家" }
    for i, name in ipairs(tabs) do
        if i > 1 then g.same_line() end
        local label = (i == tab) and ("[" .. name .. "]") or name
        if g.button(label) and i ~= tab then
            tab, dirty = i, true
        end
    end
end

--- 一行分页：‹ 上页 / 下页 › / 计数
local function draw_pager(page, pages, total)
    if g.button("‹") and page > 0 then page = page - 1 end
    g.same_line()
    if g.button("›") and page < pages - 1 then page = page + 1 end
    g.same_line()
    g.text(string.format("  %d/%d · 共 %d 项", page + 1, pages, total))
    return page
end

--- 结果网格：每行 COLS 个按钮
local function draw_grid(names, list, page, on_click)
    local start = page * PER_PAGE
    for i = 1, PER_PAGE do
        local id = list[start + i]
        if not id then break end
        if g.button(fit_label(names[id] or ("#" .. id), 10)) then on_click(id) end
        if (i % COLS) ~= 0 and list[start + i + 1] then g.same_line() end
    end
end

local function gui_items()
    build_item_names()

    item_filter = g.input_text("搜索", item_filter)
    item_stack = math.floor(g.slider("生成数量", item_stack, 1, 999))

    if item_filter ~= item_filter_cache or dirty then
        item_filter_cache = item_filter
        item_list_cache = compute_list(item_names, item_py, item_ini, item_ms, item_filter,
            ITEM_COUNT - 1)
        item_page = 0
        dirty = false
    end

    local list = item_list_cache or {}
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    if item_page > pages - 1 then item_page = pages - 1 end

    g.separator()
    item_page = draw_pager(item_page, pages, #list)
    g.separator()

    local player = local_player()
    draw_grid(item_names, list, item_page, function(id)
        if give_item(player, id, item_stack) then
            notify("生成 " .. (item_names[id] or ("#" .. id)) .. " x" .. item_stack)
        else
            notify("生成物品失败")
        end
    end)

end

local function gui_npcs()
    build_npc_names()

    npc_filter = g.input_text("搜索", npc_filter)
    npc_count = math.floor(g.slider("召唤数量", npc_count, 1, 50))

    if npc_filter ~= npc_filter_cache or dirty then
        npc_filter_cache = npc_filter
        npc_list_cache = compute_list(npc_names, npc_py, npc_ini, npc_ms, npc_filter,
            NPC_COUNT - 1)
        npc_page = 0
        dirty = false
    end

    local list = npc_list_cache or {}
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    if npc_page > pages - 1 then npc_page = pages - 1 end

    g.separator()
    npc_page = draw_pager(npc_page, pages, #list)
    g.separator()

    local player = local_player()
    draw_grid(npc_names, list, npc_page, function(id)
        if summon_npc(player, id, npc_count) then
            notify("召唤 " .. (npc_names[id] or ("#" .. id)) .. " x" .. npc_count)
        else
            notify("召唤失败")
        end
    end)
end

local function gui_world()
    g.text("时间")
    if g.button("黎明") then set_time(true, 0) end
    g.same_line()
    if g.button("正午") then set_time(true, 27000) end
    g.same_line()
    if g.button("黄昏") then set_time(false, 0) end
    g.same_line()
    if g.button("午夜") then set_time(false, 16200) end

    g.separator()
    g.text("天气 / 事件")

    local blood = get_bool(F_blood_moon, nil, false)
    local nb = g.checkbox("血月", blood)
    if nb ~= blood then set_bool(F_blood_moon, nil, nb) end

    local eclipse = get_bool(F_eclipse, nil, false)
    local ne = g.checkbox("日食", eclipse)
    if ne ~= eclipse then set_bool(F_eclipse, nil, ne) end

    local rain = get_bool(F_raining, nil, false)
    local nr = g.checkbox("下雨", rain)
    if nr ~= rain then
        set_bool(F_raining, nil, nr)
        if F_rain_time then set_i32(F_rain_time, nil, nr and 3600 or 0) end
    end

    local slime = get_bool(F_slime_rain, nil, false)
    local ns = g.checkbox("史莱姆雨", slime)
    if ns ~= slime then set_bool(F_slime_rain, nil, ns) end
end

local function gui_player()
    local p = local_player()

    local ng = g.checkbox("创造无敌", god_mode)
    if ng ~= god_mode then
        god_mode = ng
        if p then set_bool(F_creative_god, p, god_mode) end
    end

    g.separator()
    if p then
        g.text(string.format("生命 %d/%d   法力 %d/%d",
            get_i32(F_stat_life, p, 0), get_i32(F_stat_life_max, p, 0),
            get_i32(F_stat_mana, p, 0), get_i32(F_stat_mana_max, p, 0)))
    else
        g.text("未找到本地玩家")
    end

    if g.button("回满生命与法力") then heal() end

    g.separator()
    g.text("拼音识别方式（搜索时生效）")
    if g.button(cfg.pinyin_mode == "full" and "[全拼]" or "全拼") then
        if cfg.pinyin_mode ~= "full" then
            cfg.pinyin_mode, dirty = "full", true
            save_config()
        end
    end
    g.same_line()
    if g.button(cfg.pinyin_mode == "ms" and "[微软双拼]" or "微软双拼") then
        if cfg.pinyin_mode ~= "ms" then
            cfg.pinyin_mode, dirty = "ms", true
            save_config()
        end
    end
    g.text(cfg.pinyin_mode == "ms"
        and "例：行 = xn (xing) / hh (hang)，木剑 = mujm"
        or "例：行 = xing / hang，木剑 = mujian 或首字母 mj")
end

function mod.on_gui()
    g = mod.gui
    g.set_title("创造模式", "创")
    g.set_width(WIDTH)
    g.set_style({
        panel = { 26, 28, 32, 238 },
        title = { 38, 41, 46, 255 },
        button = { 44, 47, 53, 255 },
        hover = { 60, 64, 72, 255 },
        active = { 74, 80, 90, 255 },
        border = { 14, 15, 18, 255 },
        text = { 228, 231, 236, 255 },
    })
    if not images.loaded then
        images.loaded = true
        local panel = g.load_image("lib/ui/panel.png")
        local icon = g.load_image("lib/ui/icon.png")
        if panel and icon then
            -- 收起后就是这个图标（可拖动，点一下展开）
            g.set_skin(panel, 6, icon, 40)
        end
    end

    if not ready then
        g.text("初始化失败：缺少关键类型/字段，请查看日志。")
        return
    end

    draw_tabs()
    g.separator()

    if tab == 1 then gui_items()
    elseif tab == 2 then gui_npcs()
    elseif tab == 3 then gui_world()
    else gui_player() end
end

-- ============ 钩子: 每帧维持无敌 ============
local function on_reset_effects(instance, args, result)
    if not god_mode or not instance or not F_creative_god then return end
    patch.set_field_value(F_creative_god, instance, true, "bool")
end

-- ============ 初始化 ============
function setup()
    cfg = load_config()

    T_main = patch.get_type("Terraria", "Main")
    T_player = patch.get_type("Terraria", "Player")
    T_item = patch.get_type("Terraria", "Item")
    T_npc = patch.get_type("Terraria", "NPC")
    T_lang = patch.get_type("Terraria", "Lang")
    if not T_main or not T_item or not T_npc or not T_lang then
        mod.error("获取类型失败 (Main/Item/NPC/Lang)")
        return
    end

    F_main_player = find_field(T_main, "player")
    F_my_player   = find_field(T_main, "myPlayer")
    if not F_my_player then F_my_player = find_field(T_main, "<myPlayer>k__BackingField") end

    F_day_time   = find_field(T_main, "dayTime")
    F_time       = find_field(T_main, "time")
    F_raining    = find_field(T_main, "raining")
    F_rain_time  = find_field(T_main, "rainTime")
    F_blood_moon = find_field(T_main, "bloodMoon")
    F_eclipse    = find_field(T_main, "eclipse")
    F_slime_rain = find_field(T_main, "slimeRain")

    F_pos    = find_field(T_player, "position")
    F_width  = find_field(T_player, "width")
    F_height = find_field(T_player, "height")
    F_stat_life     = find_field(T_player, "statLife")
    F_stat_life_max = find_field(T_player, "statLifeMax")
    F_stat_mana     = find_field(T_player, "statMana")
    F_stat_mana_max = find_field(T_player, "statManaMax")
    F_creative_god  = find_field(T_player, "creativeGodMode")

    local my_prop = patch.get_property(T_main, "myPlayer")
    if my_prop then M_get_my_player = patch.property_get_method(my_prop) end
    if not M_get_my_player then M_get_my_player = patch.get_method(T_main, "get_myPlayer", 0) end

    M_get_item_name = patch.get_method(T_lang, "GetItemNameValue", 1)
    M_get_npc_name  = patch.get_method(T_lang, "GetNPCNameValue", 1)

    if mod.platform == "android" then
        M_new_text = patch.get_method(T_main, "NewText", 5) or patch.get_method(T_main, "NewText")
        M_new_item = patch.get_method(T_item, "NewItem", 9) or patch.get_method(T_item, "NewItem")
    else
        M_new_text = patch.get_method(T_main, "NewText", 4) or patch.get_method(T_main, "NewText")
        M_quick_spawn = method_by_names(T_player, "QuickSpawnItem", { "source", "item", "stack" })
            or patch.get_method(T_player, "QuickSpawnItem", 3)
            or patch.get_method(T_player, "QuickSpawnItem")
    end

    M_new_npc = patch.get_method(T_npc, "NewNPC", 10)
        or method_by_names(T_npc, "NewNPC",
            { "source", "X", "Y", "Type", "Start", "ai0", "ai1", "ai2", "ai3", "Target" })
        or patch.get_method(T_npc, "NewNPC")

    M_reset_effects = patch.get_method(T_player, "ResetEffects", 0)
        or patch.get_method(T_player, "ResetEffects")

    if not (F_main_player and F_pos and (M_new_item or M_quick_spawn) and M_new_npc) then
        mod.error(string.format(
            "关键句柄缺失: player=%s pos=%s newItem=%s quickSpawn=%s newNpc=%s",
            tostring(F_main_player ~= nil), tostring(F_pos ~= nil),
            tostring(M_new_item ~= nil), tostring(M_quick_spawn ~= nil), tostring(M_new_npc ~= nil)))
        return
    end

    if M_reset_effects then
        local ok = pcall(patch.install_hook, M_reset_effects, { postfix = on_reset_effects })
        if not ok then mod.warn("ResetEffects 钩子安装失败(无敌仍需每次手动点)") end
    end

    ready = true
    mod.info("创造模式菜单已启用（拼音识别："
        .. (cfg.pinyin_mode == "ms" and "微软双拼" or "全拼") .. "）")
end

function mod.cleanup()
    god_mode = false
end

todo_list = { "setup" }
