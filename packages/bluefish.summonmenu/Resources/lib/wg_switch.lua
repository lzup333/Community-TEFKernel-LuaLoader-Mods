-- 全武器成长（世界进度成长）装配层：默认关闭，开关落盘 wg_en.txt
--   独立模组「全武器成长 v2.1.0」并入合集；逻辑全在 wg_* 模块里，
--   这里只负责按需加载 / 卸载 / 记住开关。
local M = {}
local active = false
local impl = nil
local function note(tag, msg) pcall(mod.info, '[WG][' .. tostring(tag) .. '] ' .. tostring(msg)) end
local function read_on()
    local ok, raw = pcall(mod.read_file, 'wg_en.txt')
    if not ok or type(raw) ~= 'string' or raw == '' then return false end
    return raw:match('^%s*1') ~= nil
end
local function write_on(v) pcall(mod.write_file, 'wg_en.txt', v and '1' or '0') end
local function ensure()
    if impl then return impl end
    local ok, res = pcall(require, 'wg_entry')
    if ok and type(res) == 'table' then impl = res; return impl end
    note('LOAD_FAILED', res)
    return nil
end
function M.is_enabled() return active end
function M.set_enabled(v)
    v = v and true or false
    write_on(v)
    if v == active then return true end
    if v then
        local m = ensure()
        if not m then return false end
        local ok, err = pcall(m.setup)
        if not ok then
            note('START_FAILED', err)
            pcall(m.cleanup)
            active = false
            return false
        end
        active = true
    else
        if impl then pcall(impl.cleanup) end
        active = false
    end
    return true
end
function M.setup() if read_on() then return M.set_enabled(true) end return false end
function M.cleanup()
    if active and impl then pcall(impl.cleanup) end
    active = false
end
return M
