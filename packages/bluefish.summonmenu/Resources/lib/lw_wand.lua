-- lw_wand.lua —— 液体魔杖的物品注册、模式按钮、配方与接线
--
-- 物品本身不铺任何图格（createTile = -1），铺放全部由 lw_drag.tick 驱动。
-- 这里只负责：注册物品、注册「液体模式」按钮、注册三个配方、转发 tick。
local M = {}

require("wand_quickapi")
local q = mod.quickapi

local geom = require("lw_placement")
local state = require("lw_state")
local drag = require("lw_drag")
local preview = require("lw_preview")

local CTRL_ID = "liquid_wand_mode"
local ICON_NAME = "liquid_btn.png"
local CFG_NAME  = "liquid_wand_cfg.txt"   -- 记住当前模式，重进游戏不用重设
-- 96×96 圆形按钮图标（以液体魔杖贴图为内容，圆形遮罩 + 紫色渐变底），
-- base64 内嵌：private_dir 在 Android/data 下用户放不进文件，只能自己解码写入。
local ICON_B64 = "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"

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64_decode(s)
    s = s:gsub("[\r\n]", "")
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

-- 返回可用的 icon 相对路径；任何一步失败都返回 nil
-- （icon 解码失败会让内核 luaL_error 把整个 register 弄挂，按钮会消失）
local function prepare_icon()
    local ok = pcall(function()
        local png = b64_decode(ICON_B64)
        if type(png) ~= "string" or #png < 100 then error("decode failed") end
        if png:sub(1, 8) ~= "\137PNG\r\n\26\n" then error("not png") end
        mod.write_file(ICON_NAME, png)
    end)
    if not ok then return nil end
    local e_ok, exists = pcall(mod.file_exists, ICON_NAME)
    if e_ok and exists then return ICON_NAME end
    return nil
end


local my_id = -1
local recipe_added = {}       -- [i] = true
local ctrl_ok = false
local ctrl_visible = nil
local frame_count = 0
local retry_timer = 0

-- ==================== 原版 use 回调 ====================
-- 什么都不做，只清掉本帧挥动动画（createTile = -1 本来也不会放东西，这里是保险）。
local function block_vanilla_use(player)
    if not player then return end
    pcall(q.set_field_value, "Terraria", "Player", "itemAnimation", player, 0, "int32")
end

-- ==================== 运行时 ID ====================
local function runtime_id()
    if my_id > 0 then return my_id end
    if mod.item and type(mod.item.runtime_id) == "function" then
        local ok, v = pcall(mod.item.runtime_id, geom.ITEM_NAME)
        if ok and type(v) == "number" and v > 0 then
            my_id = v
            return v
        end
    end
    return -1
end

-- ==================== 三个配方 ====================
-- 只调 mod.recipe.add 是不够的：那只是把配方塞进内核的回调列表，
-- 而原版合成表在加载世界时就已经生成完毕，界面里不会出现新配方。
-- 必须自己触发一次重建：numRecipes 归零 → SetupRecipes() → QuickLookup()，
-- 内核的 prefix 会在 SetupRecipes 里把我们登记的配方真正注入。
local R = {}          -- Recipe 的句柄
local recipe_done = false
local recipe_warned = false

local function bind_recipe_api()
    if R.m_setup then return true end
    R.f_num   = q.field("Terraria", "Recipe", "numRecipes")
    R.m_setup = q.method("Terraria", "Recipe", "SetupRecipes", 0)
    R.m_quick = q.method("Terraria", "Recipe", "QuickLookup", 0)
    return (R.f_num ~= nil) and (R.m_setup ~= nil)
end

local function rebuild_recipe_table()
    if not bind_recipe_api() then
        return false, "Recipe API 缺失（numRecipes / SetupRecipes）"
    end

    local before = mod.patch.get_field_value(R.f_num, nil, "int32") or 0
    local zeroed = false
    if before > 0 then
        zeroed = pcall(mod.patch.set_field_value, R.f_num, nil, 0, "int32")
    end

    local ok, err = pcall(mod.patch.invoke, R.m_setup)
    local after = mod.patch.get_field_value(R.f_num, nil, "int32") or 0

    if not ok or after <= 0 then
        -- 重建失败就把数量还原，别把原版合成表弄坏
        if zeroed and before > 0 then
            pcall(mod.patch.set_field_value, R.f_num, nil, before, "int32")
        end
        return false, string.format("SetupRecipes 失败 %s->%s (%s)",
                tostring(before), tostring(after), tostring(err))
    end

    -- 索引表再补一次（原版末尾已经跑过，这里纯保险）
    if R.m_quick then pcall(mod.patch.invoke, R.m_quick) end

    mod.info(string.format("[液体魔杖] 配方表重建：numRecipes %d -> %d",
            before, after))
    return true
end

local function all_recipes_added()
    for i = 1, #geom.RECIPES do
        if not recipe_added[i] then return false end
    end
    return true
end

local function add_recipes()
    if recipe_done then return true end
    if not (mod.recipe and type(mod.recipe.add) == "function") then
        if not recipe_warned then
            recipe_warned = true
            mod.warn("[液体魔杖] 加载器没有 mod.recipe.add，配方无法注册")
        end
        return false
    end

    local id = runtime_id()
    if id <= 0 then return false end        -- 等运行时 ID 分配好再来

    -- ① 先把三个配方都交给内核
    for i, r in ipairs(geom.RECIPES) do
        if not recipe_added[i] then
            -- result 是「合成产物的物品 ID」，不是数量！
            -- 这里必须填本魔杖自己的运行时 ID（id），填 1 会合出 ID 1 的铁镐。
            local ok, err = pcall(mod.recipe.add, {
                result    = id,
                materials = r.materials,
                station   = r.station,
            })
            if ok then
                recipe_added[i] = true
                mod.info(("[液体魔杖] 配方已登记：%s"):format(r.name or ("#" .. i)))
            else
                mod.warn(("[液体魔杖] 配方登记失败 %s：%s"):format(r.name or ("#" .. i), tostring(err)))
            end
        end
    end

    -- ② 全部登记完才重建一次合成表（避免重建三次）
    if not all_recipes_added() then return false end

    local ok2, why = rebuild_recipe_table()
    if ok2 then
        recipe_done = true
        return true
    end
    if not recipe_warned then
        recipe_warned = true
        mod.warn("[液体魔杖] 配方表重建失败：" .. tostring(why))
    end
    return false
end

-- ==================== 模式持久化 ====================
-- 按钮的屏幕位置由内核 button_manager 自己存（Lua 侧没有位置接口），
-- 但「当前是哪种模式」这个状态得我们记，否则每次重进都回到生成水。

local function save_mode(mode)
    if type(mode) ~= "string" then return end
    pcall(mod.write_file, CFG_NAME, mode)
end

local function load_mode()
    local ok, txt = pcall(mod.read_file, CFG_NAME)
    if not ok or type(txt) ~= "string" then return nil end
    local m = txt:match("^%s*([%a_]+)")
    if m and geom.MODE_NAME[m] then return m end
    return nil
end

-- ==================== 模式按钮 ====================
local function switch_mode()
    state.mode = geom.next_mode(state.mode)
    local label = geom.MODE_NAME[state.mode] or state.mode
    -- 切模式后清掉遗留的预览，避免用旧颜色画一帧
    state.preview_on = false
    save_mode(state.mode)
    drag.chat(("液体魔杖：%s"):format(label))
    mod.info(("[液体魔杖] 模式切换 → %s"):format(label))
end

local function install_controls()
    if ctrl_ok then return true end
    local mc = mod.controls
    if type(mc) ~= "table" or type(mc.register) ~= "function" then
        mod.warn("[液体魔杖] mod.controls 不可用，模式按钮跳过")
        return false
    end
    if type(mc.available) == "function" then
        local oka, avail = pcall(mc.available)
        if not oka or not avail then
            mod.warn("[液体魔杖] controls.available() = false")
            return false
        end
    end

    -- 圆形图标（液体魔杖贴图）；图标没准备好时必须留文字，否则按钮全空看不见
    local icon = prepare_icon()
    local ok, err = pcall(mc.register, {
        id = CTRL_ID,
        name = "液体模式",
        icon = icon,
        show_label = (icon == nil),
    })
    if ok then
        ctrl_ok = true
        mod.info("[液体魔杖] 模式按钮已注册（icon=" .. tostring(icon) .. "）")
        return true
    end
    mod.warn("[液体魔杖] 模式按钮注册失败：" .. tostring(err))
    return false
end

-- 每帧调用：按钮显隐（手持才显示）+ 按下检测
local function poll_controls(player)
    if not ctrl_ok then return end
    local mc = mod.controls
    if type(mc) ~= "table" then return end

    if type(mc.set_visible) == "function" and player then
        if (frame_count % 10) == 0 then
            -- 手持判定在 drag 里，这里复用它的结果不做（避免重复读背包）
            -- 直接按“是否手持液体魔杖”判断：读 HeldItem.type
            local want = false
            local item = q.invoke("Terraria", "Player", "get_HeldItem", player)
            if item then
                local t = q.get_field_value("Terraria", "Item", "type", item, "int32")
                local id = runtime_id()
                if type(t) == "number" and id > 0 and t == id then want = true end
            end
            if want ~= ctrl_visible then
                local okv = pcall(mc.set_visible, CTRL_ID, want)
                if okv then ctrl_visible = want end
            end
        end
    end

    -- mod.controls 不解析 on_press，只能每帧轮询 pressed
    if type(mc.pressed) ~= "function" then return end
    local ok, hit = pcall(mc.pressed, CTRL_ID)
    if ok and hit then
        pcall(switch_mode)
    end
end

-- ==================== 注册 ====================
function M.setup()
    local ok_reg, id = pcall(q.register_item, {
        name = geom.ITEM_NAME,
        texture = "liquid_wand.png",
        sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
        width = 32,
        height = 32,
        createTile = -1,          -- 本魔杖不放图格，液体由 tick 写
        useStyle = 1,
        useTime = 30,
        useAnimation = 30,
        maxStack = 1,
        consumable = false,       -- 魔杖本身不消耗
        tooltip = true,
        language = {
            zh = {
                name = "液体魔杖",
                tooltip = ("单击：按当前模式作用 1 格\n"
                        .. "拖动框选：作用整个矩形范围，最大 100×100\n"
                        .. "点「液体模式」按钮切换：生成水、生成熔岩、生成蜂蜜、清除液体"),
            },
            en = {
                name = "液体魔杖",
                tooltip = ("单击：按当前模式作用 1 格\n"
                        .. "拖动框选：作用整个矩形范围，最大 100×100\n"
                        .. "点「液体模式」按钮切换：生成水、生成熔岩、生成蜂蜜、清除液体"),
            },
        },
        use = block_vanilla_use,
    })

    if not ok_reg then
        mod.error("[液体魔杖] 物品注册失败：" .. tostring(id))
        return false
    end
    if type(id) == "number" and id > 0 then
        my_id = id
        drag.set_item_id(id)
        mod.info(("[液体魔杖] 物品已注册 id=%d"):format(id))
    else
        mod.warn("[液体魔杖] 物品已注册，运行时 ID 尚未分配")
    end

    -- 恢复上次用的模式（重进游戏不用重新切）
    local saved = load_mode()
    if saved then
        state.mode = saved
        mod.info(("[液体魔杖] 恢复上次模式：%s"):format(geom.MODE_NAME[saved] or saved))
    end

    -- 模式按钮
    pcall(install_controls)

    -- 配方（ID 可能还没分配，tick 里会重试）
    pcall(add_recipes)

    -- 四色范围预览
    if not preview.install() then
        mod.info("[液体魔杖] 范围预览未启用")
    end

    return true
end

-- ==================== 每帧 ====================
function M.on_tick(player)
    frame_count = frame_count + 1

    -- 配方 / ID 兜底：内核有时延后才分配运行时 ID，这里定期重试
    if not recipe_done then
        retry_timer = retry_timer + 1
        if retry_timer >= 60 then
            retry_timer = 0
            pcall(add_recipes)
        end
    end

    pcall(poll_controls, player)
    pcall(drag.tick, player)
end

function M.cleanup()
    pcall(drag.cleanup)
    pcall(preview.cleanup)
    if ctrl_ok and mod.controls and type(mod.controls.unregister) == "function" then
        pcall(mod.controls.unregister, CTRL_ID)
    end
    ctrl_ok = false
    ctrl_visible = nil
end

return M