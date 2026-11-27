-- main.lua
-- 自动钓鱼机 / Auto Fishing Machine
-- 组装：反射绑定 → 物品与配方注册 → 钓鱼机循环。
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

local SD = {
    S = {
        item_name = "afm_machine",
        mark = 987700,
        item_id = -1,
        reg_tried = false,
        recipe_done = false,
        frame = 0,
        was_world = false,
        net_mode = 0,
        probe = {},
    },
}
_G.AFM_SD = SD

local M = {}
local booted = false
local U, P, B, I, MC
local tick_hook = nil
local last_press = false

local function log_error(msg) pcall(mod.error, tostring(msg)) end
local function log_info(msg) pcall(mod.info, tostring(msg)) end

U = require("afm_util")
P = U.P

local function net_mode()
    if mod.net and type(mod.net.mode) == "function" then
        local ok, m = pcall(mod.net.mode)
        if ok and type(m) == "number" then return m end
    end
    return 0
end

local function do_tick(player)
    if not (B and MC) then return end
    local inw = B.world()
    if not inw then
        if SD.S.was_world then
            SD.S.was_world = false
            pcall(MC.save)
        end
        return
    end

    SD.S.frame = (SD.S.frame or 0) + 1

    if not SD.S.was_world then
        SD.S.was_world = true
        SD.S.net_mode = net_mode()
        if B and B.invalidate_player then B.invalidate_player() end
        if I then
            I.sync_id()
            I.ensure_recipe()
        end
        if MC then pcall(MC.load) end
    end

    -- 配方每帧试探一次，成功后自己 return（成本只有一次 bool 判断）
    if I then I.ensure_recipe() end

    if (SD.S.net_mode or 0) ~= 0 then return end

    local p = player or B.local_player()
    if not p then return end
    local pressed = B.use_state(p)
    local edge = pressed and (not last_press)
    last_press = pressed
    MC.tick(p, edge)
end

local tick_fail = 0
local function on_tick(...)
    local ok, err = pcall(do_tick, ...)
    if not ok then
        tick_fail = tick_fail + 1
        if tick_fail <= 3 then log_error("[AFM] tick 出错: " .. tostring(err)) end
    end
end

local function boot()
    if booted then return end
    booted = true
    SD.S.boot_stage = "start"
    local ok, err = pcall(function()
        SD.S.boot_stage = "bind"
        B = require("afm_bind")
        local okb = B.setup(SD)
        if not okb then
            log_error("[AFM] 绑定失败，功能可能不完整")
        end

        SD.S.boot_stage = "item"
        local ok_i, mod_i = pcall(require, "afm_item")
        if ok_i and type(mod_i) == "table" then
            I = mod_i
            I.setup(SD)
            pcall(I.register)
            pcall(I.sync_id)
            pcall(I.ensure_recipe)
        else
            SD.S.item_error = tostring(mod_i)
            log_error("[AFM] 物品模块加载失败: " .. tostring(mod_i))
        end

        SD.S.boot_stage = "machine"
        MC = require("afm_machine")
        MC.setup(SD, B)

        SD.S.boot_stage = "done"
    end)
    if not ok then
        SD.S.boot_error = tostring(err)
        log_error("[AFM] 初始化失败于 " .. tostring(SD.S.boot_stage) .. ": " .. tostring(err))
    else
        log_info(string.format("[AFM] 已加载 item=%s recipe=%s",
            tostring(SD.S.item_id), tostring(SD.S.recipe_done)))
    end
end

-- v2.1.7：拆机不再掉宝箱 —— 两道源头拦截 + 一道事后兜底
--   钓鱼机本体是箱子图格（21），挖掉时原版会按箱子规则掉一个「宝箱」物品（48）。
--   笔记 60.5 的结论是「别掉出来再扫，要在源头拦」，但 v2.1.6 只挂了
--   KillTile_DropItems，实测仍会掉 —— 补两道：
--     守卫一（最精准）WorldGen.GetItemDrop_Chests(int x, int y, int type)
--        返回值就是「这个箱子该掉什么」。prefix 返回 (true, 0) 即「跳过原方法、
--        返回值取 0」→ 这一格不掉任何东西，且完全不影响别的方块。
--     守卫二（保险）WorldGen.KillTile_DropItems 整方法跳过，坐标在机器 3 格内。
--   两道都没装上的机型，退回拆除时的事后清理（afm_bind.clear_drops_near，
--   已按笔记 60.3 改成读 WorldItem.inner + TurnToAir 的正确写法）。
local drop_guard = nil
local drop_guard2 = nil

local function find_any_method(t, name, argcs)
    if not t then return nil end
    for _, argc in ipairs(argcs) do
        local ok, mm = pcall(P.get_method, t, name, argc)
        if ok and mm then return mm end
    end
    return nil
end

local function start_drop_guard()
    if drop_guard or drop_guard2 then return true end
    local WG = U and U.try_type and U.try_type("Terraria", "WorldGen")
    if not WG then
        SD.S.guard = "notype"
        log_error("[AFM] 缺 WorldGen 类型，宝箱掉落守卫未安装")
        return false
    end
    -- 守卫一：箱子掉落物取值（private static int GetItemDrop_Chests(int x,int y,int type)）
    local m1 = find_any_method(WG, "GetItemDrop_Chests", { 3, 2, 4 })
    if m1 then
        local ok, h = pcall(P.install_hook, m1, {
            prefix = function(inst, args)
                if not (MC and MC.near_machine) then return false end
                local x, y = args[1], args[2]
                if type(x) ~= "number" or type(y) ~= "number" then return false end
                if MC.near_machine(x, y, 3) or
                    MC.near_machine(math.floor(x / 16), math.floor(y / 16), 3) then
                    return true, 0          -- 跳过原方法，返回值 0 = 不掉东西
                end
                return false
            end,
        })
        if ok and h then
            drop_guard = h
            log_info("[AFM] 守卫一已挂载（GetItemDrop_Chests）")
        else
            log_error("[AFM] 守卫一安装失败: " .. tostring(h))
        end
    else
        log_error("[AFM] GetItemDrop_Chests 未找到")
    end
    -- 守卫二：整个掉落方法跳过
    local m2 = find_any_method(WG, "KillTile_DropItems", { 4, 3, 2, 1, 0 })
    if m2 then
        local ok, h = pcall(P.install_hook, m2, {
            prefix = function(inst, args)
                if not (MC and MC.near_machine) then return false end
                local x, y = args[1], args[2]
                if type(x) ~= "number" or type(y) ~= "number" then return false end
                if MC.near_machine(x, y, 3) or
                    MC.near_machine(math.floor(x / 16), math.floor(y / 16), 3) then
                    return true
                end
                return false
            end,
        })
        if ok and h then
            drop_guard2 = h
            log_info("[AFM] 守卫二已挂载（KillTile_DropItems）")
        else
            log_error("[AFM] 守卫二安装失败: " .. tostring(h))
        end
    else
        log_error("[AFM] KillTile_DropItems 未找到")
    end
    if drop_guard or drop_guard2 then
        SD.S.guard = "on"
        return true
    end
    SD.S.guard = "fail"
    return false
end
local function start_tick_hook()
    if tick_hook then return true end
    local PlayerT = U.try_type("Terraria", "Player")
    if not PlayerT then
        log_error("[AFM] 缺 Player 类型，主循环未启动")
        return false
    end
    local m = U.find_method(PlayerT, "Update", 1)
    if not m then
        log_error("[AFM] Player.Update(int) 未找到，主循环未启动")
        return false
    end
    local ok, h = pcall(P.install_hook, m, {
        postfix = function(inst) on_tick(inst) end,
    })
    if not ok or not h then
        log_error("[AFM] Player.Update 钩子安装失败: " .. tostring(h))
        return false
    end
    tick_hook = h
    log_info("[AFM] 主循环已挂载（Player.Update postfix）")
    return true
end

function M.setup()
    boot()
    start_tick_hook()
    start_drop_guard()
end

local function do_cleanup()
    if MC then pcall(MC.save) end
    if tick_hook then
        pcall(tick_hook.remove, tick_hook)
        tick_hook = nil
    end
    if drop_guard then
        pcall(drop_guard.remove, drop_guard)
        drop_guard = nil
    end
    if drop_guard2 then
        pcall(drop_guard2.remove, drop_guard2)
        drop_guard2 = nil
    end
    _G.AFM_SD = nil
    booted = false
end

function M.cleanup() do_cleanup() end

function mod.init() M.setup() end
function mod.cleanup() M.cleanup() end

M.setup()
return M