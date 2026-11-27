-- bw_state.lua —— 物块魔杖的共享状态
--
-- 为什么要单独一个模块：
--   bw_drag（判断与铺放）和 bw_preview（绘制预览）是两个独立文件，
--   preview 每帧都要知道「手上有没有魔杖、拖到哪了」，所以把状态放到这里共享。
--
-- 坐标含义：
--   sx/sy = 按下那一帧的光标格（起点）
--   ex/ey = 当前光标格（终点）
--   框选只铺「一条线」：横拖取起点那一行，竖拖取起点那一列（见下面的 M.rect）。
local M = {}

M.MAX_LEN = 200          -- 横拖的长度上限（格）
M.MAX_H = 200            -- 竖拖的长度上限（格）。竖向分支要用它，
                         -- 漏定义会让整帧 tick 抛错 → 竖直框选完全没反应。
M.dragging = false

-- 预览范围（由 bw_drag.tick 每帧写入，bw_preview 只负责画）
M.preview_on = false
M.px1, M.px2, M.py1, M.py2 = nil, nil, nil, nil

M.sx = 0
M.sy = 0
M.ex = 0
M.ey = 0

-- 当前框选结果，返回 x1, x2, y1, y2（都含端点，x1 <= x2，y1 <= y2）。
-- 没在拖动时返回 nil。
--
-- 规则：框选只铺「一条线」，不铺矩形。
--   宽 >= 高 → 横向：只取起点那一行（y1 = y2 = sy）
--   高 >  宽 → 竖向：只取起点那一列（x1 = x2 = sx）
-- 这样横拖出来是一排，竖拖出来是一竖排；火把只在横向放（竖向时 tx 恒定，
-- 相位永远落不到火把位置，天然就不会放）。
function M.rect()
    if not M.dragging then return nil end

    local dx = math.abs(M.ex - M.sx)
    local dy = math.abs(M.ey - M.sy)

    if dx >= dy then
        -- 横向
        local x1, x2 = M.sx, M.ex
        if x1 > x2 then x1, x2 = x2, x1 end
        if x2 - x1 + 1 > M.MAX_LEN then
            if M.ex >= M.sx then x2 = x1 + M.MAX_LEN - 1 else x1 = x2 - M.MAX_LEN + 1 end
        end
        return x1, x2, M.sy, M.sy
    end

    -- 竖向
    local y1, y2 = M.sy, M.ey
    if y1 > y2 then y1, y2 = y2, y1 end
    if y2 - y1 + 1 > M.MAX_H then
        if M.ey >= M.sy then y2 = y1 + M.MAX_H - 1 else y1 = y2 - M.MAX_H + 1 end
    end
    return M.sx, M.sx, y1, y2
end

function M.reset_drag()
    M.dragging = false
end

return M