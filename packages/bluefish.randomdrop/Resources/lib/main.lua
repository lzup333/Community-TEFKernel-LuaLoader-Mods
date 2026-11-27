-- main.lua
-- 死亡随机掉落 / Random Death Drop
-- 怪物死亡时额外掉落一件随机物品（完全随机 / 概率 / 数量范围）。
-- 参考 TShock 插件「死亡随机掉落」：从全部物品里摇一个 ID，按概率与数量范围掉出来。
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

local U = require("dr_util")
local B = require("dr_bind")
local Cfg = require("dr_cfg")

local SD = { S = { boot = "start", tick_fail = 0 } }

local M = {}
local GUI
local loot_hook = nil
local world_hook = nil

local function log_error(m) pcall(mod.error, tostring(m)) end
local function log_warn(m) pcall(mod.warn, tostring(m)) end

-- 真正生成一次掉落
local function do_drop(info)
    local c = Cfg.cfg
    if not c.on then return 0 end
    if not B.chance(c.chance) then return 0 end
    local id = B.pick_pool()
    if not id then
        local maxid = B.item_max()
        if maxid < 1 then return 0 end
        id = B.rand_int(1, maxid)
    end
    local stack = B.rand_int(c.min, c.max)
    B.spawn(info.cx, info.cy, info.w, info.h, id, stack)
end

-- NPCLoot 钩子：原版掉落照旧，我们额外再掉一件随机物品
local function on_npc_loot(inst)
    local ok, err = pcall(function()
        if not inst then return end
        local info = B.npc_info(inst)
        if not info then return end
        do_drop(info)
    end)
    if not ok then
        SD.S.tick_fail = (SD.S.tick_fail or 0) + 1
        if SD.S.tick_fail <= 3 then log_error("[DR] 掉落出错: " .. tostring(err)) end
    end
    return false
end

local function install_hook()
    if loot_hook then return true end
    local P = U.P
    local meth = B.C.m_npcLoot
    if not meth then
        SD.S.boot = "nohook"
        return false
    end
    if type(P.install_hook) ~= "function" then
        SD.S.boot = "noapi"
        return false
    end
    local ok, h = pcall(P.install_hook, meth, {
        prefix = function(inst, args) return on_npc_loot(inst) end,
    })
    if ok and h then
        loot_hook = h
        B.hook_ok = true
        SD.S.boot = "ok"
        return true
    end
    SD.S.boot = "hookfail"
    log_error("[DR] NPCLoot 钩子安装失败")
    return false
end

-- ==================== 进世界初始化 ====================
-- v1.1.14：聊天栏播报已删；这里只负责进世界建一次物品索引
local world_ready = false
local index_built = false

local function on_player_update(inst)
    local ok = pcall(function()
        if not B.world() then
            world_ready = false
            return
        end
        if world_ready then return end
        -- 进世界后才建物品索引：模组加载时语言表还没就绪，读名字会全空
        if not index_built then
            index_built = true
            pcall(B.build_index)
        end
        world_ready = true
    end)
    if not ok then world_ready = true end
end

local function start_world_hook()
    if world_hook then return true end
    local P = U.P
    local meth = B.C.m_playerUpdate
    if not (meth and type(P.install_hook) == "function") then
        log_warn("[DR] 进世界钩子安装失败（缺 Player.Update）")
        return false
    end
    local ok, h = pcall(P.install_hook, meth, {
        postfix = function(inst) on_player_update(inst) end,
    })
    if ok and h then
        world_hook = h
        return true
    end
    log_warn("[DR] 进世界钩子安装失败")
    return false
end

function M.setup()
    SD.S.boot = "bind"
    local okb = B.setup()
    if not okb then
        SD.S.boot = "bindfail"
        log_error("[DR] 绑定失败，功能不可用")
        return
    end
    pcall(Cfg.load)
    install_hook()
    start_world_hook()
end

function mod.on_gui()
    if not GUI then
        local ok, m = pcall(require, "dr_gui")
        if not ok or type(m) ~= "table" then
            pcall(mod.gui.text, "死亡随机掉落：面板未就绪")
            return
        end
        GUI = m
    end
    local ok, err = pcall(GUI.draw, B)
    if not ok then pcall(mod.gui.text, "面板出错：" .. tostring(err)) end
end

function M.on_world_load()
    if not loot_hook then install_hook() end
end

local function do_cleanup()
    if loot_hook then
        pcall(loot_hook.remove, loot_hook)
        loot_hook = nil
    end
    if world_hook then
        pcall(world_hook.remove, world_hook)
        world_hook = nil
    end
    pcall(Cfg.save)
end

function mod.init() M.setup() end
function mod.cleanup() do_cleanup() end
if type(mod.on_world_load) ~= "function" then mod.on_world_load = M.on_world_load end
M.setup()

return M
