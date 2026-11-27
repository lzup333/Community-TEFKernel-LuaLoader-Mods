-- main.lua
-- 多功能大背包 / Multi Bag —— 独立模组
-- ---------------------------------------------------------------------------
-- v2.0.0
--   目标只有一个：确认「新物品能不能注册出来」+「100 格界面该怎么做」。
--   同时在聊天栏播报关键结论。拿到结果再决定界面路线。
-- ---------------------------------------------------------------------------

-- LuaLoader 3.x 私有目录布局在不同版本变过，先把常见模块根补进 package.path
pcall(function()
    local roots = {
        mod.mod_dir,
        mod.private_dir,
        (mod.mod_dir or "") .. "/Resources/lib",
        (mod.private_dir or "") .. "/lib",
    }
    local add = ""
    for _, d in ipairs(roots) do
        if type(d) == "string" and d ~= "" then
            local a = d .. "/?.lua"
            if not package.path:find(a, 1, true) then
                add = add .. a .. ";" .. d .. "/?/init.lua;"
            end
        end
    end
    if add ~= "" then package.path = add .. package.path end
end)

local ok_q, err_q = pcall(require, "quickapi")
if not ok_q then
    pcall(mod.error, "[多功能大背包] quickapi 加载失败：" .. tostring(err_q))
end

local BAG = nil
local tick_hook = nil
local booted = false

local function log_info(msg) pcall(mod.info, tostring(msg)) end
local function log_error(msg) pcall(mod.error, tostring(msg)) end

local function install_tick_hook()
    if tick_hook then return true end
    local q = mod.quickapi
    local okh, h = pcall(q.install_hook_postfix, "Terraria", "Player", "Update",
        function(inst, args, result)
            if BAG then pcall(BAG.on_tick, inst) end
        end,
        { argc = 1 })
    if not okh or not h then
        log_error("[多功能大背包] Player.Update 钩子安装失败：" .. tostring(h))
        return false
    end
    tick_hook = h
    return true
end

local function boot()
    if booted then return end
    booted = true

    local ok, err = pcall(function()
        local m = require("bag_core")
        if type(m) ~= "table" then
            error("bag_core 返回 " .. type(m) .. "（缺 return M）")
        end
        BAG = m
        m.setup()
        install_tick_hook()
    end)

    if not ok then
        booted = false
        BAG = nil
        log_error("[多功能大背包] 启动失败：" .. tostring(err))
    else
        log_info("[多功能大背包] 已加载 v3.0.0")
    end
end

local function shutdown()
    if tick_hook then
        pcall(tick_hook.remove, tick_hook)
        tick_hook = nil
    end
    if BAG then
        pcall(BAG.cleanup)
        BAG = nil
    end
    booted = false
end

function mod.init() boot() end
function mod.cleanup() shutdown() end

-- 内核每帧调用一次，用来画屏幕面板（怪物伙伴同款入口）
function mod.on_gui()
    if BAG then pcall(BAG.draw_gui) end
end

boot()
