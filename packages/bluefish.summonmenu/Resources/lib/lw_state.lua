-- lw_state.lua —— 液体魔杖的共享状态
--
-- 为什么要单独一个模块：
--   lw_drag（判断与铺放）和 lw_preview（绘制预览）是两个独立文件，
--   preview 每帧都要知道「手上有没有魔杖、当前什么模式、拖到哪了」，
--   所以把状态放到这里共享。
local M = {}

local geom = require("lw_placement")

M.MAX_LEN = geom.MAX_LEN
M.MAX_H = geom.MAX_H

-- 当前模式（按钮切换后写这里）
M.mode = geom.MODE_WATER

M.dragging = false

-- 预览范围（由 lw_drag.tick 每帧写入，lw_preview 只负责画）
M.preview_on = false
M.preview_mode = geom.MODE_WATER
M.px1, M.px2, M.py1, M.py2 = nil, nil, nil, nil

-- 拖动起终点（光标格）
M.sx = 0
M.sy = 0
M.ex = 0
M.ey = 0

-- 当前框选矩形，返回 x1, x2, y1, y2（都含端点，x1 <= x2，y1 <= y2）。
-- 没在拖动时返回 nil。
function M.rect()
    if not M.dragging then return nil end

    local x1, x2 = M.sx, M.ex
    if x1 > x2 then x1, x2 = x2, x1 end
    local y1, y2 = M.sy, M.ey
    if y1 > y2 then y1, y2 = y2, y1 end

    if x2 - x1 + 1 > M.MAX_LEN then
        if M.ex >= M.sx then x2 = x1 + M.MAX_LEN - 1 else x1 = x2 - M.MAX_LEN + 1 end
    end
    if y2 - y1 + 1 > M.MAX_H then
        if M.ey >= M.sy then y2 = y1 + M.MAX_H - 1 else y1 = y2 - M.MAX_H + 1 end
    end

    return x1, x2, y1, y2
end

function M.reset_drag()
    M.dragging = false
end

return M