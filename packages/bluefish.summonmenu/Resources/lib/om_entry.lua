-- 起源重构（拟态）装配层：默认关闭，开关落盘 om_en.txt
--   独立模组「拟态·起源重构 v3.0.0」并入合集；全部逻辑在 ori_* 模块里，
--   这里只负责「按需加载 / 卸载 / 记住开关」。
local M = {}
local active = false
local impl = nil
local function note(tag, msg) pcall(mod.info, '[OM][' .. tostring(tag) .. '] ' .. tostring(msg)) end
local function read_on()
    local ok, raw = pcall(mod.read_file, 'om_en.txt')
    if not ok or type(raw) ~= 'string' or raw == '' then return false end
    return raw:match('^%s*1') ~= nil
end
local function write_on(v) pcall(mod.write_file, 'om_en.txt', v and '1' or '0') end
local function ensure()
    if impl then return impl end
    local ok, res = pcall(require, 'ori_entry')
    if ok and type(res) == 'table' then impl = res; return impl end
    note('LOAD_FAILED', res)
    return nil
end
function M.is_enabled() return active end
function M.set_enabled(v)
    v = v and true or false
    write_on(v)
    note('SWITCH', v and '请求开启' or '请求关闭')
    if v == active then note('STATE', '状态未变'); return true end
    if v then
        local mod_impl = ensure()
        if not mod_impl then return false end
        local ok, err = pcall(mod_impl.setup)
        if not ok then
            note('START_FAILED', err)
            pcall(mod_impl.cleanup)
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
    note('UNLOAD', '随游戏卸载')
    if active and impl then pcall(impl.cleanup) end
    active = false
end
return M
