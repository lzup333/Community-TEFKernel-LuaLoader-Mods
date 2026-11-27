-- 碎晶之链（CrystalShard v1.2.76，作者 Wolkenland）并入合集的入口层
-- ---------------------------------------------------------------------------
-- 定位：**新物品模组**，跟其它内容模组一样常驻加载，没有开关也没有播报。
--   进世界时由合集 main.lua 的 Q("EXT.cr") 调用：
--     cr_setup()     → 注册全部内容（16 物品 / 2 NPC / 8 弹幕 / 1 Buff / 配方）
--     cr_hooks_on()  → 装 11 个行为钩子
--   退出世界时 hooks_off() 全部卸掉（内容注册无法回滚，但下次启动会重新注册，
--   同名同序，ID 不变）。
require("wand_quickapi")
local HB = require("cr_hookbox")

local HOOK_MODS = { "cr_projectiles", "cr_npcs", "cr_equip_effects", "cr_items", "cr_ql" }
local registered = false

local function log(tag, msg)
    pcall(mod.info, "[CR][" .. tostring(tag) .. "] " .. tostring(msg))
end

local function cr_setup()
    if registered then return true end
    local ok, content = pcall(require, "cr_content")
    if not ok then
        log("LOAD_FAILED", content)
        return false
    end
    local ok2, err = pcall(content.register_all)
    if not ok2 then
        log("REGISTER_FAILED", err)
        return false
    end
    registered = true
    log("CONTENT_READY", "内容已注册（无条件，保证 ID 稳定）")

    return true
end

local function cr_hooks_on()
    for _, name in ipairs(HOOK_MODS) do
        local ok, m = pcall(require, name)
        if not ok then
            log("REQUIRE_FAILED", tostring(name) .. ": " .. tostring(m))
        elseif type(m) ~= "table" or type(m.hooks_on) ~= "function" then
            log("NO_HOOKS_ON", tostring(name))
        else
            local ok2, err = pcall(m.hooks_on)
            if not ok2 then log("HOOK_FAILED", tostring(name) .. ": " .. tostring(err)) end
        end
    end
    log("HOOKS_ON", "hooks=" .. tostring(HB.count()))
    return true
end

local function cr_hooks_off()
    local n = HB.off()
    log("HOOKS_OFF", "removed=" .. tostring(n))
    return n
end

return { setup = cr_setup, hooks_on = cr_hooks_on, hooks_off = cr_hooks_off }
