-- dr_cfg.lua
-- 设置项与存档。只有五项：开关 / 模式 / 概率 / 数量最小 / 数量最大。
-- 存档格式（单行）：
--   DR1 <on> <mode> <chance> <min> <max>
local U = require("dr_util")

local M = {}
local FILE = "randomdrop.cfg"

local cfg = {
    on = false,        -- 总开关
    mode = "full",     -- 目前只有完全随机
    chance = 100,      -- 掉落概率 %
    min = 1,           -- 数量下限
    max = 1,           -- 数量上限
}
M.cfg = cfg

function M.serialize()
    return string.format("DR1 %d %s %d %d %d\n",
        cfg.on and 1 or 0, cfg.mode, cfg.chance, cfg.min, cfg.max)
end

function M.save()
    pcall(mod.write_file, FILE, M.serialize())
end

function M.load()
    local ok, txt = pcall(mod.read_file, FILE)
    if not ok or type(txt) ~= "string" or txt == "" then return false end
    local on, mode, ch, mn, mx = txt:match("DR1 (%d) (%a+) (%d+) (%d+) (%d+)")
    if not on then return false end
    cfg.on = on == "1"
    cfg.mode = "full"
    cfg.chance = U.clamp(tonumber(ch) or 100, 1, 100)
    cfg.min = U.clamp(tonumber(mn) or 1, 1, 99)
    cfg.max = U.clamp(tonumber(mx) or 1, 1, 99)
    if cfg.max < cfg.min then cfg.max = cfg.min end
    return true
end

return M
