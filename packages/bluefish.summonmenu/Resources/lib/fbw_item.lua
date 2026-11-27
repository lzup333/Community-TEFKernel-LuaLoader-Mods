-- sd_item.lua
-- Registers the wand item and its workbench recipe.
--
-- Item identity uses Item.value as a stable marker: runtime_id may still be -1
-- during registration, and Lang.GetItemNameValue is unreliable on this build.

local U = require("fbw_util")
local P = U.P

local M = {}
local SD

local WAND_NAME = "fabao_wand"
local WAND_MARK = 987655
-- 配方只取 materials / station；result 由 M.sync_id() 在注册时填入真实 ID
local RECIPE = {
    materials = {
        { id = 178, count = 6 },   -- ruby
        { id = 331, count = 10 },  -- jungle spores
        { id = 75,  count = 5 },   -- fallen star
    },
    station = 16,                 -- iron anvil / lead anvil
}

function M.setup(ctx)
    SD = ctx
    SD.S.item_name = WAND_NAME
    SD.S.mark = WAND_MARK
end

local function runtime_id()
    if not (mod.item and mod.item.runtime_id) then return -1 end
    local ok, v = pcall(mod.item.runtime_id, WAND_NAME)
    if ok and type(v) == "number" and v > 0 then return v end
    return -1
end

local function item_spec()
    return {
        name      = WAND_NAME,
        texture   = "fabao_wand.png",
        tooltip   = true,
        sacrifice = 1,
        defaults  = {
            width = 32, height = 32,
            useStyle = 1, useAnimation = 12, useTime = 12,
            autoReuse = false, noMelee = true,
            damage = 0, knockBack = 0,
            maxStack = 1, rare = 4, value = WAND_MARK,
            melee = false, magic = false, ranged = false,
        },
        language = {
            zh = {
                name = "法爆魔杖",
                tooltip = "单击：以准心为中心爆破 5×5 范围\n"
                       .. "拖动框选：最大支持 100×100 范围爆破\n"
                       .. "法爆切换按钮切换爆破模式：物块+墙、仅物块、仅墙",
            },
            en = {
                name = "法爆魔杖",
                tooltip = "单击：以准心为中心爆破 5×5 范围\n"
                       .. "拖动框选：最大支持 100×100 范围爆破\n"
                       .. "法爆切换按钮切换爆破模式：物块+墙、仅物块、仅墙",
            },
        },
        -- 使用行为由 sd_job 在 Player.Update 里处理（看手持状态 + controlUseItem），
        -- 这里只需放行，不挂 use 回调。
        can_use = function() return true end,
    }
end

function M.register()
    if SD.S.reg_tried then return SD.S.item_id end
    SD.S.reg_tried = true
    SD.S.reg_info = "?"

    local existed = runtime_id()
    local id, ok
    if existed > 0 then
        id, ok = existed, true
        U.log_info(string.format("[FBW] item already registered id=%d", existed))
    elseif mod.item and mod.item.register then
        ok, id = pcall(mod.item.register, item_spec())
        if not ok then
            U.log_error("[FBW] item register error: " .. tostring(id))
            id = nil
        end
    else
        U.log_error("[FBW] mod.item.register unavailable")
        return -1
    end

    if type(id) ~= "number" then
        SD.S.item_id = -1
        SD.S.reg_info = "ret=" .. tostring(id)
        U.log_error("[FBW] item register returned " .. tostring(id))
        return -1
    end

    -- -1 during registration is normal; runtime_id fills in after entering a world.
    SD.S.item_id = (id > 0) and id or -1
    SD.S.reg_info = string.format("reg=%s runtime=%s", tostring(id), tostring(runtime_id()))
    U.log_info("[FBW] item registered " .. tostring(SD.S.reg_info))
    return SD.S.item_id
end

function M.sync_id()
    local v = runtime_id()
    if v > 0 then
        if SD.S.item_id ~= v then
            U.log_info(string.format("[FBW] runtime id=%d", v))
        end
        SD.S.item_id = v
    end
    return SD.S.item_id
end

-- ==================== 配方：走内核 mod.recipe + 归零重建（v1.1.6）====================
-- 事实来源：TEFKernel src/terraria/common/recipe_manager.c
--   · patchlib_install_prepost_hook(add_recipe, recipe_add_prefix)         // 只做容量兜底
--   · patchlib_install_prepost_hook(setup_recipes, setup_recipes_prefix)   // 关键
--   · setup_recipes_prefix 遍历 g_recipe_callback 逐个调用：
--       每个 callback = terraria_recipe_set_result / set_material / set_station
--                     + terraria_recipe_add()（直接调 AddRecipe 原生指针）
--   · terraria_recipe_manager_register_callback 只是 vector_push_back，**没有去重**
--   · FindRecipes 的 postfix 补扫 [3700, numRecipes)，供超过常量上限的配方进菜单
--
-- 也就是说：Lua 配方只在「Recipe.SetupRecipes 执行之前」被注入，一把一个 callback。
-- 由此可解释前面所有失败：
--   ① 完全不调 SetupRecipes  -> 内核 prefix 没跑，配方永远进不去（v1.1.3 / v1.1.5）
--   ② 调 SetupRecipes 但不清 numRecipes
--                            -> 从当前位置继续追加整套原版配方（v1.1.2 的两份）
--   ③ 自己手动写 currentRecipe + AddRecipe
--                            -> 绕开登记，内核看不到这条配方（v1.1.5 全没了）
--
-- 正解：
--   1. mod.recipe.add 注册（把 callback 塞进内核列表）
--   2. 把 Recipe.numRecipes 写 0
--   3. 调 Recipe.SetupRecipes
--        prefix 阶段：内核遍历 callback，把我们的配方写进索引 0
--        方法体阶段：原版从索引 1 开始写整份配方（覆盖旧数据，不新增）
--        末尾阶段：原版自己跑 CreateRequiredItemQuickLookups()，范围 0..N
--                  正好把我们的配方也包进去 -> 向导/合成判定都能查到
--   4. 再补一次 QuickLookup（幂等，纯保险）
local R = {}

local function bind_recipe_api()
    local RT = U.try_type("Terraria", "Recipe")
    if not RT then return false, "Recipe type missing" end
    R.f_num   = U.find_field(RT, "numRecipes")
    R.m_setup = U.find_method(RT, "SetupRecipes", 0)
    R.m_quick = U.find_method(RT, "CreateRequiredItemQuickLookups", 0)
    if not (R.f_num and R.m_setup) then
        return false, "missing numRecipes / SetupRecipes"
    end
    return true
end

function M.ensure_recipe()
    if SD.S.recipe_done then return true end
    SD.S.recipe_status = SD.S.recipe_status or "初始化中"

    if not SD.S.recipe_api_ready then
        local ok, why = bind_recipe_api()
        if not ok then
            SD.S.recipe_status = "API缺失: " .. tostring(why)
            if not SD.S.recipe_warned then
                SD.S.recipe_warned = true
                U.log_warn("[FBW] recipe API incomplete (" .. tostring(why) .. ")")
            end
            return false
        end
        SD.S.recipe_api_ready = true
        U.log_info("[FBW] recipe API bound (numRecipes / SetupRecipes / quicklookup)")
    end

    if not (mod.recipe and type(mod.recipe.add) == "function") then
        SD.S.recipe_status = "加载器无 mod.recipe"
        if not SD.S.recipe_warned then
            SD.S.recipe_warned = true
            U.log_warn("[FBW] mod.recipe.add unavailable; craft recipe skipped")
        end
        return false
    end

    local id = M.sync_id()
    if id <= 0 then
        SD.S.recipe_status = "等待物品ID"
        return false
    end

    -- ① 注册到内核 callback 列表
    local ok, err = pcall(mod.recipe.add, {
        result    = id,
        materials = RECIPE.materials,
        station   = RECIPE.station,
    })
    if not ok then
        SD.S.recipe_status = "mod.recipe.add 失败"
        if not SD.S.recipe_warned then
            SD.S.recipe_warned = true
            U.log_warn("[FBW] mod.recipe.add failed: " .. tostring(err))
        end
        return false
    end

    -- ② numRecipes 归零，避免 SetupRecipes 追加一整套原版
    local before = U.gf_int(R.f_num, nil)
    local zeroed = false
    if before > 0 then
        zeroed = pcall(P.set_field_value, R.f_num, nil, 0, "int32")
    end

    -- ③ 触发重建：内核 prefix 在这一刻注入我们的配方
    local ok2, err2 = pcall(P.invoke, R.m_setup)
    local after = U.gf_int(R.f_num, nil)

    if not ok2 or after <= 0 then
        SD.S.recipe_status = string.format("重建失败 %s->%s", tostring(before), tostring(after))
        if zeroed and before > 0 then
            pcall(P.set_field_value, R.f_num, nil, before, "int32")
        end
        if not SD.S.recipe_warned then
            SD.S.recipe_warned = true
            U.log_warn("[FBW] SetupRecipes failed: " .. tostring(err2))
        end
        return false
    end

    -- ④ 索引表再补一次（原版末尾已经跑过，这里纯保险）
    local q_ok = false
    if R.m_quick then q_ok = pcall(P.invoke, R.m_quick) end

    SD.S.recipe_done = true
    SD.S.recipe_status = string.format("已注册 %s->%s", tostring(before), tostring(after))
    U.log_info(string.format(
        "[FBW] recipe ok: numRecipes %s -> %s zeroed=%s quicklookup=%s result=%d",
        tostring(before), tostring(after), tostring(zeroed), tostring(q_ok), id))
    return true
end


-- ==================== 拆除模式切换 ====================
-- 三种模式循环：方块+墙 -> 仅方块 -> 仅墙。
-- 模式存在 SD.S.mode，改完写回 config.json，跨会话记住。
local MODE_ORDER = { "both", "tile", "wall" }
local MODE_NAME  = { both = "方块 + 墙", tile = "仅方块", wall = "仅墙" }

local function cycle_mode()
    local cur = SD.S.mode or "both"
    local idx = 1
    for i = 1, #MODE_ORDER do
        if MODE_ORDER[i] == cur then idx = i break end
    end
    local nxt = MODE_ORDER[(idx % #MODE_ORDER) + 1]
    SD.S.mode = nxt
    local ok, Cfg = pcall(require, "fbw_config")
    if ok and Cfg and Cfg.save_mode then pcall(Cfg.save_mode, nxt) end
    M.switch_hint(nxt)
    return nxt
end

function M.cycle_mode() return cycle_mode() end

-- ==================== 原生触摸按钮 ====================
-- 依据 LuaLoader 3.x src/controls.cpp 与 TEFKernel button_manager.h：
--   @ register 只解析 id / name / icon / show_label 四个字段，
--     on_press / on_release / enabled 一律不读，
--     所以按下状态只能用 mod.controls.pressed(id) 每帧轮询。
--   @ icon 必须是「相对 mod.private_dir 的 PNG 路径」，
--     解码失败会 luaL_error 把整个 register 弄失败（按钮会消失），
--     所以图片先落盘、file_exists 确认后再传。
--   @ private_dir 在 Android/data 下用户无法放文件，
--     因此把 96×96 红底圆盘 base64 内嵌，启动时自己解码写入。
--   @ 内核把图标缩放到按钮的 3/4（button_manager.c:2523），
--     所以圆形图标直径最多是按钮的 75%，这是内核限制。
local CTRL_ID = "fabao_switch"
local ICON_NAME = "fabao_btn.png"
local ICON_B64 = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAAETklEQVR42u1dPWgUQRT+ZjgQrMyBISKx8ERIc7WFtYWFHJYiYmEhYiVaCRZpA6nCYWFhESyPQySFtQELq2uuSYJExBAhKVUQYhFX95bdvfndmTf7XpdcNnf3/bz35s3ejQCBOBgMTkyuWxqPRezvTaQCNlVSRBtAj5kM0TbQYyNDUAD+aHfX6Lm6vV70RIgYgTcF3CUhTREhYgDeF+AuCPFNhGgj8DERIUKAHwvwukT4IEE0CX6swOsQ4ZoEwcCHJUL4BJ8q8KpEuCBBMvjmbbGLxaRk8MOSIFyCnyLwqinJNB1JBt+NG0ydIBn8sCRIBj8sCZLBD0uCdPnETIKnGhDb5gmFUMVMmvwjVr+7VCQY/NNYeXYeAPDj3FUAwOfn242sEaQtyxx2GImU1J+peLr2ncxKuUNZ/UXAVYB/8G0ZAPDqwhevLlDdf5bc9YTtijpU1a+i+Ezt+bi5ePvvY6PSa/LOsCnMqi6QrP6wLuhQVb+K8jO1P3pxFwAwXN1E/1J/zrWjf0747zCzoq7iAsnqD+sCUfcgNfVXKT8fH15PSq+d7M/+futw5KxTKrog35JK1mTYENTUX7fYyhzwbuM0jy/cOAMAOH7/S9sJLh1Q5wJ2QODoUHvBKqvd4ermaQ2Aeg0INeIQVd0PpQJcLL7FVvP6/b42+JP9CbYOR87GFlXzIZlK7x97VGHaSeHNZQotjhcyJ+gq30cRVh5FcDQbTEBoAqivfinXgYPB4CSJGnDn+CsA4CyWS/P5vAFc2SiCUxAvxOgoP4uXG78BAA8fj2bWBXl1Z26oUnzW+2+v/8R0jR3ADqCg/muXu7VOqFN61ZqiCfWTJKAO+GJkRNx7+ikHPIzHCz5mQpyCOAWZFdy8+vtXFgEAw+HezN983Dua+fnNwkUA5uMFH9NQdgA7wF75k51DBeVHOopgDbIDtJWfqZ+y8tkBkUTplmTIieg85T+5tQIAWH87Jaf8sjsj2AFcA9RWuZSVzzWAmgO6vV6jdUBX+UX1U1B+1V3SQW9NrCu4qQBfV4A5BbW1CKuMF+qUT7Xg1hbh4scoTb72l0Mv/TTugLaMF5y1oewCf91PqQOWxmPRxOfEypQPzI6VU1V+MdVLWwY57LDrlDHU9Kcl26D8MvUrrwPYBX7UX0lAqOM8iqvc1NWv1Ya6nA8V00xqKUcnY0hdxjjcqV97IWbrgtQWUS7qpdRljguyHvjzMok0sQ+T4AZ85TaU64HbvK9NAK8N/GEhbRhlEuzPEpC2tmozCS4OctBOQUyCO/CNa0DbSXB5hIlVd9OmQ3zqRGbTJVrdFVH1xCm6wddZYta3pbSBBJ8HufFRhob9fVRHGaZGBMnDPFVJiJmIJI6zVSUhJiKSO9CZChFJH2luQoRvQnQ6s6YmwI2PmU1ueTElxKQVbnr0HmzOH9s3tYfa84hioyUUGTFsNEW30+WbjNh290hsNZqSQmEr9Q+j+JT4tvQv9gAAAABJRU5ErkJggg=="

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

-- 返回可用的 icon 相对路径；任何一步失败都返回 nil（不能让 register 抛错）
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

function M.install_controls()
    if SD.S.ctrl_ok then return true end
    local mc = mod.controls
    if type(mc) ~= "table" or type(mc.register) ~= "function" then
        U.log_warn("[FBW] mod.controls unavailable; switch button skipped")
        return nil
    end
    if type(mc.available) == "function" then
        local oka, avail = pcall(mc.available)
        if not oka or not avail then
            U.log_warn("[FBW] controls.available() = false")
            return nil
        end
    end
    local icon = prepare_icon()
    local ok, err = pcall(mc.register, {
        id = CTRL_ID,
        name = "法爆切换",
        icon = icon,
        -- 有图标只显示图标；图标没准备好必须留文字，否则按钮全空看不见
        show_label = (icon == nil),
        -- 内核按钮描述符没有 key 字段，传了只会让它去存按键绑定（日志里 binding save failed）
    })
    if ok then
        SD.S.ctrl_ok = true
        U.log_info("[FBW] switch button registered (icon=" .. tostring(icon) .. ")")
        return true
    end
    U.log_warn("[FBW] controls.register failed: " .. tostring(err))
    return nil
end

function M.poll_controls(player)
    if not SD.S.ctrl_ok then return end
    local mc = mod.controls
    if type(mc) ~= "table" then return end

    -- ① 可见性：只在手持法爆魔杖时显示按钮，没手持就隐藏。
    --    controls.cpp 里 set_visible(id, bool) -> terraria_button_manager_set_visible，
    --    按钮没注册时会 luaL_error，所以外面必须 pcall，并且先确认 ctrl_ok。
    --    每 10 帧判一次手持状态即可（背包切换不需要逐帧响应），省掉每帧读背包的开销。
    if type(mc.set_visible) == "function" and player then
        local f = SD.S.frame or 0
        if (f % 10) == 0 then
            local B = SD.bind
            local want = false
            if B and type(B.holding_wand) == "function" then
                local okh, h = pcall(B.holding_wand, player)
                want = (okh and h == true) and true or false
            end
            if want ~= SD.S.ctrl_visible then
                local okv = pcall(mc.set_visible, CTRL_ID, want)
                if okv then SD.S.ctrl_visible = want end
            end
        end
    end

    -- ② 按下检测（mod.controls 不解析 on_press，只能每帧轮询 pressed）
    if type(mc.pressed) ~= "function" then return end
    local ok, hit = pcall(mc.pressed, CTRL_ID)
    if ok and hit then
        pcall(M.switch_mode_here)
    end
end

function M.cleanup_controls()
    if not SD.S.ctrl_ok then return end
    pcall(function()
        if mod.controls and type(mod.controls.unregister) == "function" then
            mod.controls.unregister(CTRL_ID)
        end
    end)
    SD.S.ctrl_ok = nil
    SD.S.ctrl_visible = nil
end

-- ==================== 切换提示 ====================
--   ① Main.NewText 聊天栏（主路）
--   ② 聊天栏失败时退回 Main.statusText 屏幕中央文字
local HINT_FRAMES = 180   -- 状态文字保留 3 秒

function M.switch_hint(mode)
    local name = MODE_NAME[mode] or tostring(mode)
    local msg = "法爆魔杖：" .. name
    -- ① 聊天栏（主路）
    local okc, ret = pcall(SD.bind.notify, msg)
    if okc and ret then return name end
    -- ② 聊天栏失败才退回屏幕中央状态文字（避免两处重复）
    SD.S.status_msg = msg
    SD.S.status_until = (SD.S.frame or 0) + HINT_FRAMES
    return name
end

-- 每帧调用：状态文字会被原版每帧覆盖，所以要持续写
function M.pump_status()
    local msg = SD.S.status_msg
    if not msg then return end
    local f = SD.S.frame or 0
    local C = SD.bind and SD.bind.C
    if f > (SD.S.status_until or 0) then
        SD.S.status_msg = nil
        if C and C.f_statusText then
            pcall(P.set_field_value, C.f_statusText, nil, "", "string")
        end
        return
    end
    if C and C.f_statusText then
        pcall(P.set_field_value, C.f_statusText, nil, msg, "string")
    end
end

-- ==================== 切换动作 ====================
function M.switch_mode_here()
    return cycle_mode()
end


function M.cleanup_switch()
    pcall(M.cleanup_controls)
end

return M
