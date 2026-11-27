-- 碎晶之链并入合集后的钩子收集器：内容注册永远执行（保证 ID 稳定），
-- 行为钩子跟随设置页开关装卸。
local M = { list = {} }

function M.add(h)
    if h then M.list[#M.list + 1] = h end
    return h
end

function M.off()
    local n = 0
    for i = #M.list, 1, -1 do
        local h = M.list[i]
        M.list[i] = nil
        if h and h.remove then
            local ok = pcall(function() h:remove() end)
            if ok then n = n + 1 end
        end
    end
    return n
end

function M.count() return #M.list end

return M
