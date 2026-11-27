-- ============================================================================
--  config.lua —— 读 Resources/config.json
--  只保留两个开关：播报总开关、最短间隔。
-- ============================================================================

local C = {}

C.DEFAULTS = {
    enabled         = true,
    report_interval = 3,
}

local function clamp_int(v, lo, hi)
    v = math.floor(tonumber(v) or lo)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function C.load(read_file)
    local cfg = {}
    for k, v in pairs(C.DEFAULTS) do cfg[k] = v end

    local raw = nil
    if type(read_file) == "function" then
        local ok, data = pcall(read_file, "config.json")
        if ok and type(data) == "string" then raw = data end
    end

    if raw then
        local m = raw:match('"enabled"%s*:%s*"?(%a+)"?')
        if m then cfg.enabled = (m == "true") end
        local n = raw:match('"report_interval"%s*:%s*"?(%d+)"?')
        if n then cfg.report_interval = tonumber(n) or cfg.report_interval end
    end

    cfg.report_interval = clamp_int(cfg.report_interval, 1, 30)
    return cfg
end

return C
