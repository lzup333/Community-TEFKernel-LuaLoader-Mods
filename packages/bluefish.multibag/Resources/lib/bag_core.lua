-- bag_core.lua
-- 多功能大背包 v2.0.0
-- ---------------------------------------------------------------------------
-- 这一版只做三件事：
--   1. 把「多功能大背包」物品注册出来（贴图 / 名字 / 说明）
--   3. 尝试用原版宝箱界面承载容器，看这条路通不通
--
-- 全程 pcall 兜底，任何一步失败都不让游戏崩。
-- ---------------------------------------------------------------------------

local q = mod.quickapi
local patch = mod.patch

local M = {}

local DATA = nil      -- bag_data：容器 + 背包读写 + 分类
local UIMOD = nil     -- bag_ui：面板
local EFFECT = nil    -- bag_effect：四套随身被动效果

-- 面板显隐：按钮 / 使用物品 / 关闭按钮都改这个值
local panel_visible = false
local click_frame = -1          -- 同一帧只在探测点处理一次按钮点击
local prev_visible = false      -- 上一帧面板是否可见（用于切换时收起残留图标）

local ITEM_NAME = "multi_bag"
local ITEM_DISPLAY = "多功能大背包"   -- 列表里显示的名字（不是内部标识）

local my_id  = -1
local lines  = {}

-- 保持容器打开的余量（帧）。
local HOLD_FRAMES = 900
local hold_idx    = -1
local hold_end    = 0
local tick_count  = 0

-- ============================ 小工具 ============================



local function say(text, r, g, b)
    pcall(function()
        q.invoke("Terraria", "Main", "NewText", tostring(text),
                r or 135, g or 206, b or 235, false)
    end)
end

local logs = {}

local function plog(s)
    s = tostring(s)
    logs[#logs + 1] = s
    while #logs > 5 do table.remove(logs, 1) end
end

-- 一次性枚举 Player 上跟 chest / inventory 有关的成员名，直接画到面板上，
-- 好确认 OpenChest 到底叫什么、参数几个，以及 inventory 字段的真实名字。


-- 注册后内核可能延后分配 ID：每次用的时候现查一次，避免拿到 -1
local function rid()
    if my_id > 0 then return my_id end
    local ok, v = pcall(q.item_id, ITEM_NAME)
    if ok and type(v) == "number" and v > 0 then
        my_id = v
        -- 拿到真实 id 就登记名字：列表里显示「多功能大背包」而不是 ID:6196
        pcall(DATA.reg_self, v, ITEM_DISPLAY)
        return v
    end
    return -1
end







-- ============================ 物品发放 ============================

-- 造一个指定 id 的 Item 实例（构造器不给 SetDefaults，这里按重载逐个试）
local function make_item(id)
    local it_t = patch.get_type("Terraria", "Item")
    if not it_t then return nil end
    local ok, inst = pcall(patch.new_instance, it_t)
    if not ok or not inst then return nil end
    -- 1.4.6：Item.SetDefaults(int Type, ItemVariant variant)，两参版第二参要显式传 nil；
    --   1.4.5.8 只有单参版本。两种都试，按 argc 决定补不补第三个别参数。
    for _, argc in ipairs({ 2, 1 }) do
        local okm, m = pcall(patch.get_method, it_t, "SetDefaults", argc)
        if okm and m then
            local okv
            if argc == 2 then
                okv = pcall(patch.invoke, m, inst, id, nil)
            else
                okv = pcall(patch.invoke, m, inst, id)
            end
            if okv then return inst end
        end
    end
    return nil
end

-- 本地玩家判断：联机时 Player.Update 会对每个玩家各跑一次
local function is_local(player)
    local ok, who, my = pcall(function()
        local pt = patch.get_type("Terraria", "Player")
        local mt = patch.get_type("Terraria", "Main")
        return patch.get_field_value(patch.get_field(pt, "whoAmI"), player, "int32"),
               patch.get_field_value(patch.get_field(mt, "myPlayer"), nil, "int32")
    end)
    if not ok then return true end
    if type(who) == "number" and type(my) == "number" then return who == my end
    return true
end

-- 背包里有没有 / 往第一个空槽塞一个
local function ensure_item(player)
    local id = rid()
    if id <= 0 then return end
    local pt = patch.get_type("Terraria", "Player")
    local it_t = patch.get_type("Terraria", "Item")
    if not (pt and it_t) then return end
    local f_inv = patch.get_field(pt, "inventory")
    local f_type = patch.get_field(it_t, "type")
    if not (f_inv and f_type) then return end

    local arr = patch.get_field_value(f_inv, player, "object")
    if not arr then return end
    local n = patch.array_length(arr) or 0

    local empty = -1
    for i = 0, n - 1 do
        local slot = patch.array_at(arr, i)
        if slot then
            local t = patch.get_field_value(f_type, slot, "int32")
            if t == id then return end             -- 已经有了
            if t == 0 and empty < 0 then empty = i end
        end
    end

    if empty < 0 then return end                   -- 背包满了，不管
    local inst = make_item(id)
    if not inst then
        pcall(mod.warn, "[多功能大背包] 造物品失败，无法自动发放")
        return
    end
    pcall(patch.array_set, arr, empty, inst)
    say("[多功能大背包] 已放入背包", 135, 206, 235)
end

-- ============================ 配方 ============================
-- 宝箱×2 + 丝绸×10 + 铁锭/铅锭×10 @ 恶魔祭坛（铁、铅各一条配方）
-- 数值优先按名字从 ItemID / TileID 现查（PE 与 PC 数值不同），查不到才用兜底值。

local function id_by_name(holder, name, fallback)
    local ok, v = pcall(function()
        local t = patch.get_type("Terraria.ID", holder)
        local f = t and patch.get_field(t, name)
        if not f then return nil end
        return patch.get_field_value(f, nil, "int32")
    end)
    if ok and type(v) == "number" and v > 0 then return v end
    return fallback
end

local ID_CHEST = id_by_name("ItemID", "Chest", 48)
local ID_SILK  = id_by_name("ItemID", "Silk", 225)
local ID_IRON  = id_by_name("ItemID", "IronBar", 22)
local ID_LEAD  = id_by_name("ItemID", "LeadBar", 704)
local TILE_DEMON_ALTAR = id_by_name("TileID", "DemonAltar", 26)

local RECIPES = {
    {
        name = "恶魔祭坛·铁锭版",
        materials = {
            { id = ID_CHEST, count = 2 },
            { id = ID_SILK,  count = 10 },
            { id = ID_IRON,  count = 10 },
        },
        station = TILE_DEMON_ALTAR,
    },
    {
        name = "恶魔祭坛·铅锭版",
        materials = {
            { id = ID_CHEST, count = 2 },
            { id = ID_SILK,  count = 10 },
            { id = ID_LEAD,  count = 10 },
        },
        station = TILE_DEMON_ALTAR,
    },
}

local recipe_added = {}
local recipe_done  = false
local recipe_warned = false

-- 原版合成表在加载世界时就生成好了，光登记不会出现在界面上，
-- 必须把 numRecipes 归零后重跑 SetupRecipes，让内核的 prefix 把新配方注进去。
local function rebuild_recipe_table()
    local okb, api = pcall(function()
        local rt = patch.get_type("Terraria", "Recipe")
        return {
            f_num   = patch.get_field(rt, "numRecipes"),
            m_setup = patch.get_method(rt, "SetupRecipes", 0),
            m_quick = patch.get_method(rt, "QuickLookup", 0),
        }
    end)
    if not okb or not api or not api.f_num or not api.m_setup then
        return false, "Recipe API 缺失（numRecipes / SetupRecipes）"
    end

    local before = patch.get_field_value(api.f_num, nil, "int32") or 0
    local zeroed = false
    if before > 0 then
        zeroed = pcall(patch.set_field_value, api.f_num, nil, 0, "int32")
    end

    local ok, err = pcall(patch.invoke, api.m_setup)
    local after = patch.get_field_value(api.f_num, nil, "int32") or 0

    if not ok or after <= 0 then
        if zeroed and before > 0 then
            pcall(patch.set_field_value, api.f_num, nil, before, "int32")
        end
        return false, string.format("SetupRecipes 失败 %s->%s (%s)",
                tostring(before), tostring(after), tostring(err))
    end

    if api.m_quick then pcall(patch.invoke, api.m_quick) end
    return true
end

local function add_recipes()
    if recipe_done then return true end
    if not (mod.recipe and type(mod.recipe.add) == "function") then
        if not recipe_warned then
            recipe_warned = true
            pcall(mod.warn, "[多功能大背包] 加载器没有 mod.recipe.add，配方无法注册")
        end
        return false
    end

    local id = rid()
    if id <= 0 then return false end          -- 等运行时 ID 分配好再来

    for i, r in ipairs(RECIPES) do
        if not recipe_added[i] then
            -- result 是「产物的物品 ID」，不是数量
            local ok, err = pcall(mod.recipe.add, {
                result    = id,
                materials = r.materials,
                station   = r.station,
            })
            if ok then
                recipe_added[i] = true
            else
                pcall(mod.warn, ("[多功能大背包] 配方登记失败 %s：%s"):format(r.name, tostring(err)))
            end
        end
    end

    local all = true
    for i = 1, #RECIPES do
        if not recipe_added[i] then all = false break end
    end
    if not all then return false end

    local ok2, why = rebuild_recipe_table()
    if ok2 then
        recipe_done = true
        return true
    end
    if not recipe_warned then
        recipe_warned = true
        pcall(mod.warn, "[多功能大背包] 配方表重建失败：" .. tostring(why))
    end
    return false
end

-- ============================ 物品使用 ============================

local function open_bag(player)
    if rid() <= 0 then
        plog("物品 ID 还没分配好")
        return
    end
    panel_visible = true
end

local function on_use(player, item)
    pcall(open_bag, player)
end

-- ============================ 屏幕按钮 ============================
-- 与法爆魔杖 / 液体魔杖同款：内核 mod.controls 注册一个屏幕按钮，
-- 手持大背包时才显示，按下就打开容器。

local CTRL_ID   = "multibag_open"
local CTRL_ID_BUFF = "multibag_bufficon"   -- Buff 图标显示开关（屏幕悬浮按钮）
local ctrl_buff_ok = false
local ctrl_buff_visible = nil
local ICON_NAME = "multibag_btn.png"
local ICON_NAME_BUFF = "multibag_buffbtn.png"

local ctrl_ok      = false
local ctrl_visible = nil
local auto_open_count = 0
local heartbeat_said  = false

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64_decode(s)
    s = s:gsub("[\r\n ]", "")
    local out, buf, n = {}, 0, 0
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "=" then break end
        local v = B64_CHARS:find(c, 1, true)
        if v then
            buf = buf * 64 + (v - 1)
            n = n + 1
            if n == 4 then
                out[#out + 1] = string.char(
                    math.floor(buf / 65536) % 256,
                    math.floor(buf / 256) % 256,
                    buf % 256)
                buf, n = 0, 0
            end
        end
    end
    if n == 2 then
        out[#out + 1] = string.char(math.floor(buf / 16) % 256)
    elseif n == 3 then
        out[#out + 1] = string.char(math.floor(buf / 4096) % 256, math.floor(buf / 16) % 256)
    end
    return table.concat(out)
end

-- 图标必须落在 private_dir（模组包内的路径按钮读不到，Android/data 用户又放不进去），
-- 所以 base64 内嵌、运行时解码写文件。任何一步失败都返回 nil，让按钮退回文字。
local function prepare_icon(modname, outname)
    local ok = pcall(function()
        local rok, payload = pcall(require, modname)
        if not rok or type(payload) ~= "string" or #payload < 100 then
            error(tostring(modname) .. " 缺失")
        end
        local png = b64_decode(payload)
        if type(png) ~= "string" or #png < 100 then error("decode failed") end
        if png:sub(1, 8) ~= "\137PNG\r\n\26\n" then error("not png") end
        mod.write_file(outname, png)
    end)
    if not ok then return nil end
    local e_ok, exists = pcall(mod.file_exists, outname)
    if e_ok and exists then return outname end
    return nil
end

local function install_controls()
    if ctrl_ok then return true end
    local mc = mod.controls
    if type(mc) ~= "table" or type(mc.register) ~= "function" then
        pcall(mod.warn, "[多功能大背包] mod.controls 不可用，屏幕按钮跳过")
        return false
    end
    if type(mc.available) == "function" then
        local oka, avail = pcall(mc.available)
        if not oka or not avail then
            pcall(mod.warn, "[多功能大背包] controls.available() = false")
            return false
        end
    end

    local icon = prepare_icon("bag_icon", ICON_NAME)
    local ok, err = pcall(mc.register, {
        id = CTRL_ID,
        name = "大背包",
        icon = icon,
        show_label = (icon == nil),
    })
    if ok then
        ctrl_ok = true
        -- 怪物伙伴的写法：注册后必须显式 enable，否则按钮「可见但点不动」
        if type(mc.set_enabled) == "function" then
            pcall(mc.set_enabled, CTRL_ID, true)
        end

        -- 第二个按钮：Buff 图标显示开关（没有专用贴图，用文字标签）
        local icon2 = prepare_icon("buff_icon", ICON_NAME_BUFF)
        local ok2, res2 = pcall(mc.register, {
            id = CTRL_ID_BUFF,
            name = "Buff显示",
            icon = icon2,
            show_label = (icon2 == nil),
        })
        -- 注意：pcall 的第一个返回值只代表"没抛错"，register 自己也可能返回 false
        if ok2 and res2 ~= false then
            ctrl_buff_ok = true
            if type(mc.set_enabled) == "function" then
                pcall(mc.set_enabled, CTRL_ID_BUFF, true)
            end
        else
            pcall(mod.warn, "[多功能大背包] Buff 开关按钮注册失败：" .. tostring(res2))
        end
        return true
    end
    pcall(mod.warn, "[多功能大背包] 屏幕按钮注册失败：" .. tostring(err))
    return false
end

-- 手持判定：用属性访问器读 Player.HeldItem（比手写 inventory 索引可靠）
local held_type = nil      -- HeldItem.type 的原始读数（nil = 读不到）
local inv_has_flag = false -- 背包里到底有没有这个大背包
local inv_err = ""

local function read_held_type(player)
    local ok, t = pcall(function()
        local pt = patch.get_type("Terraria", "Player")
        local it_t = patch.get_type("Terraria", "Item")
        local prop = patch.get_property(pt, "HeldItem")
        if prop then
            local getter = patch.property_get_method(prop)
            if getter then
                local it = patch.invoke(getter, player)
                if it and it ~= false then
                    return patch.get_field_value(patch.get_field(it_t, "type"), it, "int32")
                end
            end
        end
        -- 兜底：selectedItem + inventory
        local sel = patch.get_field_value(patch.get_field(pt, "selectedItem"), player, "int32")
        if type(sel) ~= "number" then return nil end
        local inv = patch.get_field_value(patch.get_field(pt, "inventory"), player, "object")
        if not inv then return nil end
        local slot = patch.array_at(inv, sel)
        if not slot then return nil end
        return patch.get_field_value(patch.get_field(it_t, "type"), slot, "int32")
    end)
    if ok then return t end
    return nil
end

local function holding_bag(player)
    local id = rid()
    if id <= 0 then return false end
    local t = read_held_type(player)
    held_type = t
    return type(t) == "number" and t == id
end

-- 背包（含装备栏）里是否存在这个大背包
local function inventory_has(player)
    local id = rid()
    if id <= 0 then return false end
    local ok, found = pcall(function()
        local pt = patch.get_type("Terraria", "Player")
        local it_t = patch.get_type("Terraria", "Item")
        local f_type = patch.get_field(it_t, "type")
        local f_inv = patch.get_field(pt, "inventory")
        if not f_inv then inv_err = "字段 inventory 不存在" return false end
        local inv = patch.get_field_value(f_inv, player, "object")
        if not inv then inv_err = "inventory 取值为 nil" return false end
        local n = patch.array_length(inv) or 0
        for i = 0, n - 1 do
            local slot = patch.array_at(inv, i)
            if slot then
                local t = patch.get_field_value(f_type, slot, "int32")
                if t == id then return true end
            end
        end
        return false
    end)
    if ok then return found end
    inv_err = "扫描异常"
    return false
end

local function poll_controls(player)
    if not ctrl_ok then return end
    local mc = mod.controls
    if type(mc) ~= "table" then return end

    if type(mc.set_visible) == "function" and player then
        if (tick_count % 10) == 0 then
            -- 手持大背包时才显示按钮（法爆魔杖同款）
            local want = holding_bag(player)
            if want ~= ctrl_visible then
                local okv = pcall(mc.set_visible, CTRL_ID, want)
                if okv then ctrl_visible = want end
            end
            if type(mc.set_enabled) == "function" then
                pcall(mc.set_enabled, CTRL_ID, true)
            end
        end
    end

    -- Buff 开关按钮：只有"确实有代挂 buff"时才露面，平时不挡屏幕
    if ctrl_buff_ok and type(mc.set_visible) == "function" and (tick_count % 10) == 0 then
        -- 三种情况都显示：手持大背包 / 玩家身上有任意 buff / 我们代挂了 buff
        -- v2.0.3：Buff 显示按钮只在「手持大背包」时出现，平时不占屏幕
        local want = holding_bag(player) or false
        if want ~= ctrl_buff_visible then
            local okv = pcall(mc.set_visible, CTRL_ID_BUFF, want)
            if okv then ctrl_buff_visible = want end
        end
        if type(mc.set_enabled) == "function" then
            pcall(mc.set_enabled, CTRL_ID_BUFF, true)
        end
    end

    pcall(M.poll_button_click)
end

-- 把 mod.controls 的所有成员名打出来（排查 pressed 为什么没响应）

-- ============================ 屏幕面板（mod.gui） ============================
-- mod.controls 的 pressed 一直读不到点击，改用内核的 GUI 回调：
-- mod.on_gui 每帧被调用一次，button_at 直接返回「本帧是否被点」。
-- 怪物伙伴（liuxin.monstermorph.probe）就是这条路线，实测可用。

local gui_ready = false

-- 取本地玩家。参考「类药水袋」的做法：
--   PE/IL2CPP 上 Main.myPlayer 是【属性】不是字段，
--   必须走 get_myPlayer 访问器拿索引，再从 Main.player[idx] 取实例。
--   （直接读字段会拿到无效对象 → 后面读 inventory 拿到错数组 → 扫 0 件）
local function main_index()
    local mt = patch.get_type("Terraria", "Main")
    if not mt then return nil end

    -- ① 属性访问器
    local prop = patch.get_property(mt, "myPlayer")
    if prop then
        local getter = patch.property_get_method(prop)
        if getter then
            local ok, v = pcall(patch.invoke, getter)
            if ok and type(v) == "number" then return v end
        end
    end
    -- ② get_myPlayer 方法
    local m = patch.get_method(mt, "get_myPlayer", 0)
    if m then
        local ok, v = pcall(patch.invoke, m)
        if ok and type(v) == "number" then return v end
    end
    -- ③ 字段兜底
    local f = patch.get_field(mt, "myPlayer")
    if f then
        local ok, v = pcall(patch.get_field_value, f, nil, "int32")
        if ok and type(v) == "number" then return v end
    end
    return nil
end

local function player_array()
    local mt = patch.get_type("Terraria", "Main")
    if not mt then return nil end
    local f = patch.get_field(mt, "player")
    if f then
        local ok, v = pcall(patch.get_field_value, f, nil, "object")
        if ok and v then return v end
    end
    local ok2, v2 = pcall(q.get_object, "Terraria", "Main", "player", nil)
    if ok2 and v2 then return v2 end
    return nil
end

local function local_player()
    local ok, p = pcall(function()
        local idx = main_index()
        if type(idx) ~= "number" or idx < 0 then return nil end
        local arr = player_array()
        if not arr then return nil end
        local n = 0
        local okn, vn = pcall(patch.array_length, arr)
        if okn and type(vn) == "number" then n = vn end
        if n > 0 and idx >= n then return nil end
        local okat, pl = pcall(patch.array_at, arr, idx)
        if okat then return pl end
        return nil
    end)
    if ok then return p end
    return nil
end

function M.draw_gui()
    if not (DATA and UIMOD) then return end
    local g = mod.gui
    if type(g) ~= "table" then return end

    -- 按钮点击检测放在最前面：按钮事件可能只在 GUI 回调这一帧有效，
    -- 放到 Player.Update 里读已经太晚（这就是之前点了没反应的原因）
    pcall(M.poll_button_click)

    pcall(function()
        if not panel_visible then
            -- 隐藏期间也每帧复位折叠态：否则内核会一直认为窗口是「已折叠」，
            -- 从而持续画那个最小化悬浮窗（就是屏幕上那个「包」字方块）
            if type(g.set_collapsed) == "function" then
                pcall(g.set_collapsed, false)
            end
            -- 用 hide() 而不是 set_visible(false)：
            -- set_visible 只切绘制开关，窗口的折叠状态和布局还留着；
            -- hide 才是真正把窗口收起来（鬼妖村正就是这么做的）
            if type(g.hide) == "function" then
                pcall(g.hide)
            else
                pcall(g.set_visible, false)
            end
            prev_visible = false
            return
        end

        -- 标题/皮肤/样式全部交给 bag_ui（它设成空白 + 透明皮肤，去掉内核标题条）

        -- 打开时确保是展开态
        if not prev_visible then
            prev_visible = true
            -- 先 show：hide 过的窗口必须重新 show 才会回到屏幕上
            if type(g.show) == "function" then
                pcall(g.show)
            end
            -- 通知界面层：这是「刚打开」，重置折叠保护期计数
            if type(UIMOD.on_open) == "function" then
                pcall(UIMOD.on_open)
            end
            if type(g.set_collapsed) == "function" then
                local okc, collapsed = pcall(g.is_collapsed)
                if okc and collapsed then
                    pcall(g.set_collapsed, false)
                end
            end
        end

        local okd, errd = pcall(UIMOD.draw, g)
        if not okd then
            pcall(g.text_at, 12, 180, "界面错误: " .. tostring(errd), { 255, 130, 130, 255 }, 0.8)
        end
    end)
end

-- ============================ 按钮点击检测 ============================
-- mod.controls 的事件只活一帧，而且不同内核版本暴露的名字不一定一样，
-- 这里把能想到的几个都试一遍，谁先返回 true 就用谁。
-- 用 click_frame 去重，保证一帧只切换一次（GUI 回调和 Player.Update 都会调）。

local PRESS_API = { "pressed", "was_pressed", "clicked", "is_pressed", "take" }

function M.poll_button_click()
    -- 每 60 帧探一次自注册物品的真实 id（注册阶段拿到的是 -1）
    if not self_id_ok then
        self_id_wait = (self_id_wait or 0) + 1
        if self_id_wait >= 60 then
            self_id_wait = 0
            local v = rid()
            if v > 0 then
                pcall(DATA.reg_self, v, ITEM_DISPLAY)
                self_id_ok = true
                end
        end
    end
    if not ctrl_ok then return end
    if click_frame == tick_count then return end

    local mc = mod.controls
    if type(mc) ~= "table" then return end

    -- Buff 图标开关按钮
    if ctrl_buff_ok then
        for _, name in ipairs(PRESS_API) do
            local fn = mc[name]
            if type(fn) == "function" then
                local ok, hit = pcall(fn, CTRL_ID_BUFF)
                if ok and hit then
                    click_frame = tick_count
                    if EFFECT then
                        EFFECT.icons_hidden = not EFFECT.icons_hidden
                        local msg = "[大背包] Buff 图标" .. (EFFECT.icons_hidden and "已隐藏" or "已显示") ..
                            "（代挂 " .. tostring(EFFECT.active_n or 0) .. " 个）"
                        pcall(mod.info, msg)
                        pcall(say, msg, 135, 206, 235)   -- 聊天栏也报一条，方便确认点到了
                    else
                        pcall(say, "[大背包] 随身效果模块未就绪", 255, 120, 120)
                    end
                    return true
                end
            end
        end
    end

    for _, name in ipairs(PRESS_API) do
        local fn = mc[name]
        if type(fn) == "function" then
            local ok, hit = pcall(fn, CTRL_ID)
            if ok and hit then
                click_frame = tick_count
                panel_visible = not panel_visible
                return true
            end
        end
    end
    return false
end

-- ============================ 药水袋效果 ============================
-- 容器里同种药水 ≥10 瓶 → 每 30 帧刷新一次 buff 时间（治疗/魔力药水在分类时已排除）

-- 药水袋效果已迁到 bag_effect.lua（buffType 直写 + keep_long 不覆盖长 buff）

-- ============================ 生命周期 ============================

function M.setup()
    -- 数据层 / 界面层
    local okd, d = pcall(require, "bag_data")
    if okd and type(d) == "table" then
        DATA = d
        pcall(DATA.load)
    else
        pcall(mod.error, "[多功能大背包] bag_data 加载失败：" .. tostring(d))
    end
    local oku, u = pcall(require, "bag_ui")
    if oku and type(u) == "table" then
        UIMOD = u
        if DATA then
            pcall(UIMOD.init, DATA, local_player, function()
                panel_visible = false
            end, function()
                return EFFECT
            end)
        end
    else
        pcall(mod.error, "[多功能大背包] bag_ui 加载失败：" .. tostring(u))
    end

    local ok, id = pcall(q.register_item, {
        name = ITEM_NAME,
        texture = "bag.png",
        width = 45,
        height = 58,
        maxStack = 1,
        useStyle = 1,          -- 0 = 无使用动作，点了屏幕内核可能根本不发 use 回调
        useTime = 20,
        useAnimation = 20,
        autoReuse = false,
        consumable = false,
        createTile = -1,       -- 不放图格
        noMelee = true,
        damage = 0,
        rare = 1,
        sacrifice = 1,
        tooltip = true,
        language = {
            zh = {
                name = "多功能大背包",
                tooltip = "500 格独立储存空间\n"
                       .. "药水袋 / 旗帜袋 / 增益站 / 制作站\n"
                       .. "单击打开背包",
            },
            en = {
                name = "Multi Bag",
                tooltip = "500 extra slots\n"
                       .. "Potions / Banners / Stations\n"
                       .. "Click to open",
            },
        },
        use = on_use,
    })

    -- 注册返回的是 runtime_id，注册阶段通常还是 -1（内核延后分配），
    -- 所以这里只记日志，真正的 id 由 tick 里的探针补齐（见 sync_self_id）。
    if ok then
        if type(id) == "number" and id > 0 then
            pcall(DATA.reg_self, id, ITEM_DISPLAY)
        end
    else
        pcall(mod.warn, "[多功能大背包] 物品注册失败：" .. tostring(id))
    end

    if not ok then
        pcall(mod.error, "[多功能大背包] 物品注册失败：" .. tostring(id))
        return false
    end

    if type(id) == "number" and id > 0 then
        my_id = id
        if DATA and type(DATA.set_self_item) == "function" then
            pcall(DATA.set_self_item, id)
        end
    else
        pcall(mod.warn, "[多功能大背包] 物品已注册，运行时 ID 尚未分配")
    end

    -- 四套随身被动效果：随身制作站 / 随身增益站 / 药水袋 / 旗帜袋
    local oke, e = pcall(require, "bag_effect")
    if oke and type(e) == "table" then
        EFFECT = e
        local okset, res = pcall(e.setup, DATA)
        if not okset or not res then
            pcall(mod.warn, "[多功能大背包] 随身效果初始化失败：" .. tostring(res))
        end
    else
        pcall(mod.warn, "[多功能大背包] bag_effect 加载失败：" .. tostring(e))
    end
    return true
end

function M.on_tick(player)
    tick_count = tick_count + 1

    -- 屏幕按钮：没注册成功就每两秒重试一次
    if not ctrl_ok and (tick_count % 120) == 1 then
        pcall(install_controls)
    end
    pcall(poll_controls, player)

    -- 心跳：确认聊天栏播报通道本身通不通（只报一次）
    if not heartbeat_said and tick_count == 180 then
        heartbeat_said = true
        say("[多功能大背包] 已就绪", 135, 206, 235)
    end

    -- 配方：运行时 ID 分配好之后登记一次；失败就隔一秒再试
    if not recipe_done and (tick_count % 60) == 0 then
        pcall(add_recipes)
    end

    -- 四套随身被动效果
    if EFFECT then pcall(EFFECT.tick, player) end

    if hold_idx < 0 or tick_count > hold_end then return end

    -- 把箱子维持打开
    pcall(function()
        local pt = patch.get_type("Terraria", "Player")
        local f = patch.get_field(pt, "chest")
        if f then patch.set_field_value(f, player, hold_idx, "int32") end
    end)
end

function M.cleanup()
    hold_idx = -1
    if EFFECT then
        pcall(EFFECT.cleanup)
        EFFECT = nil
    end
end

return M