-- main.lua
-- 法爆魔杖 / Demolition Wand
-- Assembles config, reflection binding, the blast queue, the item and the panel.

-- LuaLoader 3.x moved the private layout around; add the usual module roots
-- before the first require. Without this, require("fbw_util") can fail with a
-- "module not found" that looks like the whole mod is broken.
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
    cfg = {},
    C = {},
    S = {
        item_name = "fabao_wand",
        mark = 987655,
        item_id = -1,
        reg_tried = false,
        width = 5,
        height = 5,
        mode = "both",
        drop = true,
        held = false,
        aim_ok = false,
        frame = 0,
        was_world = false,
        job = nil,
        job_status = "",
    },
}
_G.FBW_SD = SD

local M = {}
local booted = false
local B, J, I, PV

local function log_error(msg) pcall(mod.error, tostring(msg)) end
local function log_info(msg) pcall(mod.info, tostring(msg)) end

local function do_tick(player)
    if not (B and J) then return end
    local chw = B.world()
    if not chw then
        if SD.S.was_world then
            SD.S.was_world = false
            SD.S.in_world = false
            SD.S.held = false
            J.reset_drag()
        end
        return
    end

    SD.S.frame = (SD.S.frame or 0) + 1
    SD.S.tick_n = (SD.S.tick_n or 0) + 1
    if not SD.S.was_world then
        SD.S.was_world = true
        SD.S.in_world = true
        if I then
            I.sync_id()
            I.ensure_recipe()
        end
        SD.S.net_mode = B.net_mode()
    end
    if (SD.S.frame % 60) == 0 then
        SD.S.net_mode = B.net_mode()
    end
    if (SD.S.net_mode or 0) ~= 0 then return end

    -- v1.1.7：每帧都尝试一次（recipe_done 之后直接 return，成本只有一次判断）
    if I then I.ensure_recipe() end

    local p = player or B.local_player()
    if not p then return end
    -- 原生按钮的按下检测（mod.controls 不解析 on_press，只能轮询 pressed）
    if I then pcall(I.poll_controls, p) end
    -- 切换提示：状态文字会被原版每帧覆盖，需要持续写回
    if I then pcall(I.pump_status) end
    J.tick(p)
end

M.on_tick = nil   -- boot 之后指向 on_tick

local tick_fail = 0
local function on_tick(...)
    local ok, err = pcall(do_tick, ...)
    if not ok then
        tick_fail = tick_fail + 1
        if tick_fail <= 3 then
            log_error("[FBW] tick error: " .. tostring(err))
        end
    end
end

local function boot()
    if booted then return end
    booted = true
    _G.FBW_SD = SD

    SD.S.boot_stage = "start"
    local ok, err = pcall(function()
        SD.S.boot_stage = "cfg"
        local Cfg = require("fbw_config")
        SD.cfg = Cfg.load()
        SD.S.width = SD.cfg.default_width
        SD.S.height = SD.cfg.default_height
        SD.S.mode = SD.cfg.mode
        SD.S.drop = SD.cfg.drop_items

        SD.S.boot_stage = "bind"
        B = require("fbw_bind")
        SD.bind = B
        B.setup(SD)

        SD.S.boot_stage = "job"
        J = require("fbw_job")
        SD.job = J
        J.setup(SD)

        -- v1.1.8：sd_item 单独 pcall。它挂了也要让后面的 preview / bus 装上，
        --   否则 tick 不跑、面板什么都看不到，错误信息还被路径撑爆看不到行号。
        SD.S.boot_stage = "item"
        local ok_i, mod_i = pcall(require, "fbw_item")
        -- v1.1.9：require 一个忘了写 return M 的模块会返回 true，
        --   后面 I.setup 就变成 true.setup -> "attempt to index a boolean value"，
        --   而且报错时 boot_stage 还停在 item，极难定位。这里显式挡一下。
        if ok_i and type(mod_i) ~= "table" then
            SD.S.item_error = "fbw_item 返回了 " .. type(mod_i) .. "（缺 return M）"
            mod_i = nil
            ok_i = false
        end
        if ok_i and mod_i then
            I = mod_i
            SD.item = I
            local ok_s, err_s = pcall(I.setup, SD)
            if not ok_s then
                SD.S.item_error = tostring(err_s)
            else
                SD.S.boot_stage = "item.register"
                local ok_r, err_r = pcall(I.register, SD)
                if not ok_r then SD.S.item_error = tostring(err_r) end

                SD.S.boot_stage = "item.sync"
                local ok_y, err_y = pcall(I.sync_id)
                if not ok_y then SD.S.item_error = tostring(err_y) end

                SD.S.boot_stage = "item.recipe"
                local ok_c, err_c = pcall(I.ensure_recipe)
                if not ok_c then SD.S.item_error = tostring(err_c) end
            end
        else
            SD.S.item_error = tostring(mod_i)
        end
        SD.S.boot_stage = "switch"
        if I then
            -- 切换按钮：mod.controls 原生触摸按钮
            pcall(I.install_controls)
        end

        SD.S.boot_stage = "preview"
        PV = require("fbw_preview")
        SD.preview = PV
        PV.setup(SD)

        SD.S.boot_stage = "bus"
        -- 主循环钩子由合集总总线（Player.Update）统一派发，这里不再自装

        SD.S.boot_stage = "done"
    end)

    if not ok then
        SD.S.boot_error = tostring(err)
        log_error("[FBW] setup failed at " .. tostring(SD.S.boot_stage) .. ": " .. tostring(err))
    else
        log_info(string.format("[FBW] loaded cfg=%dx%d mode=%s drop=%s item=%s",
            SD.cfg.max_width, SD.cfg.max_height, tostring(SD.cfg.mode),
            tostring(SD.cfg.drop_items), tostring(SD.S.item_id)))
    end
end

function M.setup() boot() end
M.on_tick = on_tick

-- v1.3.0：面板已取消，不注册 mod.on_gui，加载器不会开窗口

local function do_cleanup()
    if PV then pcall(PV.cleanup); PV = nil; SD.preview = nil end
    if I then pcall(I.cleanup_switch) end
    SD.S.recipe_hook = nil
    if SD.S then
        SD.S.job = nil
        SD.S.dragging = false
        SD.S.job_status = ""
        SD.S.held = false
        SD.S.aim_ok = false
        SD.S.was_world = false
    end
    _G.FBW_SD = nil
    booted = false
end

function M.cleanup() do_cleanup() end

return M
