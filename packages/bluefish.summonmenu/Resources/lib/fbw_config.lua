-- sd_config.lua
-- v1.3.0：取消模组设置页，参数全部写死；只把「当前拆除模式」持久化到 config.json
--   最大框选 100×100、轻点 5×5、固定产生掉落物

local M = {}

local DEFAULTS = {
    max_width     = 100,
    max_height    = 100,
    default_width = 5,
    default_height = 5,
    drop_items    = true,
    mode          = "both",   -- both / tile / wall
}

local MODES = { both = true, tile = true, wall = true }

function M.load()
    local cfg = {}
    for k, v in pairs(DEFAULTS) do cfg[k] = v end

    -- 只读 mode：点「法爆切换」按钮切换后的状态要跨会话记住
    local ok, txt = pcall(mod.read_file, "fabao_config.json")
    if ok and type(txt) == "string" and #txt > 0 then
        local m = txt:match('"mode"%s*:%s*"([%w_]+)"')
        if m and MODES[m] then cfg.mode = m end
    end
    return cfg
end

function M.save_mode(mode)
    if not MODES[mode] then return end
    local s = string.format(
        '{\n  "schemaVersion": 1,\n  "values": {\n    "mode": "%s"\n  }\n}\n',
        mode)
    pcall(mod.write_file, "fabao_config.json", s)
end

return M