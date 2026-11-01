-- ============================================================
-- 鲸屿小物（WhaleByMySide）v2.0.0
-- 目标：LuaLoader 2.1.0-dev（这一个预览版才有 mod.item）
--
-- 为什么砍了东西：
--   1.9.0 没有 mod.item / mod.projectile / mod.buff / mod.npc，
--   一件自定义物品都建不出来；2.1.0-dev 只有 mod.item，
--   自定义弹幕和 Buff 到最新预览版都还没放出来。
--   所以这一版只做「两件物品 + 配方」，其它等上游支持了再加回来。
--
-- 诊断照旧：每一步都写进 <private_dir>/诊断.txt。
-- ============================================================

mod.meta = {
    pkg_id = "jingjing.lua.whale",
    version = "2.0.0",
    version_code = 202610290,
    api_version = 1,
}

-- ---------------------------------------------------------------- 诊断

local DIAG_FILE = "诊断.txt"
local diag_lines = {}

local function diag(fmt, ...)
    local text
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        text = ok and s or tostring(fmt)
    else
        text = tostring(fmt)
    end
    diag_lines[#diag_lines + 1] = "[" .. os.date("%H:%M:%S") .. "] " .. text
end

local function dump_diag()
    if type(mod.write_file) ~= "function" then return end
    pcall(function()
        mod.write_file(DIAG_FILE, table.concat(diag_lines, "\n") .. "\n")
    end)
end

-- ---------------------------------------------------------------- 环境

local function has(t, k)
    return type(t) == "table" and type(t[k]) == "function"
end

local function report_env()
    diag("=== 鲸屿小物 v2.0.0 启动 ===")
    diag("加载器版本=%s | %s/%s", tostring(mod.version), tostring(mod.platform), tostring(mod.arch))
    diag("private_dir=%s", tostring(mod.private_dir))
    diag("API：item=%s projectile=%s buff=%s npc=%s patch=%s write_file=%s",
            tostring(has(mod.item, "register")),
            tostring(type(mod.projectile) == "table"),
            tostring(type(mod.buff) == "table"),
            tostring(type(mod.npc) == "table"),
            tostring(type(mod.patch) == "table"),
            tostring(type(mod.write_file) == "function"))
end

-- ---------------------------------------------------------------- 注册物品

local ITEMS = {}

local function reg(label, spec)
    if not has(mod.item, "register") then
        diag("%s：mod.item.register 不存在，跳过", label)
        return nil
    end
    local ok, res = pcall(mod.item.register, spec)
    if ok then
        diag("%s → 返回 %s", label, tostring(res))
        ITEMS[#ITEMS + 1] = spec.name
    else
        diag("%s → 失败：%s", label, tostring(res))
    end
    return ok and res or nil
end

local function register_all()

    -- 鲸歌杖：魔法武器，靠属性砍（这一版没有自定义弹幕）
    reg("物品 whale_wand", {
        name = "whale_wand",
        texture = "whale_wand.png",
        tooltip = true,
        sacrifice = 1,
        defaults = {
            damage = 32, knockBack = 6.0,
            useStyle = 1, useTime = 16, useAnimation = 16,
            autoReuse = true, magic = true, melee = false,
            width = 32, height = 32,
            maxStack = 1, rare = 2, value = 12000,
        },
        language = {
            zh = { name = "鲸歌杖", tooltip = "挥一下，听得到海。26 点伤害，能连打。" },
            en = { name = "Whale Song Staff", tooltip = "Swing it and you can hear the sea." },
        },
        recipe = {
            result = 1,
            materials = {
                { id = 9,  count = 12 },    -- 木材
                { id = 22, count = 3 },     -- 铁锭
                { id = 23, count = 5 },     -- 凝胶
            },
            station = 18,                    -- 工作台
        },
    })

    -- 潮汐护符：这一版没有 Buff API，暂时只是个能拿在手上的饰品状物品
    reg("物品 whale_totem", {
        name = "whale_totem",
        texture = "whale_totem.png",
        tooltip = true,
        sacrifice = 1,
        defaults = {
            width = 24, height = 24,
            useStyle = 2, useTime = 30, useAnimation = 30,
            maxStack = 1, rare = 1, value = 5000,
        },
        language = {
            zh = { name = "潮汐护符", tooltip = "一颗挂着浪的珠子。效果等加载器支持 Buff 再加。" },
            en = { name = "Tide Totem", tooltip = "A bead with a wave in it. Effect comes later." },
        },
        recipe = {
            result = 1,
            materials = {
                { id = 23, count = 8 },     -- 凝胶
                { id = 9,  count = 6 },     -- 木材
            },
            station = 18,
        },
    })
end

-- ---------------------------------------------------------------- 进世界诊断

local world_checked = false

local function item_id(name)
    if has(mod.item, "runtime_id") then
        local ok, id = pcall(mod.item.runtime_id, name)
        if ok then return id end
        return "出错:" .. tostring(id)
    end
    return "无此接口"
end

local function player_ready()
    if type(mod.patch) ~= "table" then return false end
    local ok, menu = pcall(function()
        local t = mod.patch.get_type("Terraria", "Main")
        if not t then return true end
        local f = mod.patch.get_field(t, "gameMenu")
        if not f then return true end
        return mod.patch.get_field_value(f, nil, "bool")
    end)
    if not ok then return true end
    return menu ~= true
end

local function on_tick()
    if world_checked then return end
    if not player_ready() then return end
    world_checked = true

    diag("进世界了")
    for _, name in ipairs(ITEMS) do
        diag("运行时 id：%s = %s", name, tostring(item_id(name)))
    end

    if ITEMS[1] and type(item_id(ITEMS[1])) == "number" and item_id(ITEMS[1]) >= 0 then
        diag("注册成功了：物品 id 有效，合成表里应该能看到")
    else
        diag("物品 id 还是空/负数：注册有问题")
    end

    dump_diag()
end

local function install_tick_hook()
    if type(mod.patch) ~= "table" or type(mod.patch.install_hook) ~= "function" then
        diag("没有 mod.patch.install_hook，进世界诊断没挂上")
        return
    end
    local ok, err = pcall(function()
        local t = mod.patch.get_type("Terraria", "Player")
        local m = mod.patch.get_method(t, "Update", 1)
        if not m then error("找不到 Player.Update") end
        mod.patch.install_hook(m, { postfix = on_tick })
    end)
    diag("进世界诊断：%s", ok and "挂上了" or ("失败 " .. tostring(err)))
end

-- ---------------------------------------------------------------- 入口

function setup()
    local ok, err = pcall(function()
        report_env()
        register_all()
        install_tick_hook()
    end)
    if not ok then
        diag("setup 崩了：%s", tostring(err))
    end
    dump_diag()
    mod.info("[鲸屿小物] v2.0.0 启动，诊断见 private_dir/" .. DIAG_FILE)
end

todo_list = { "setup" }
