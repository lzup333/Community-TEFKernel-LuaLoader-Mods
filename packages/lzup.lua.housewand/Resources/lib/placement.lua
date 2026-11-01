local M = {}

M.WIDTH = 15
M.HEIGHT = 8
M.LENGTH = 1
M.WORLD_MARGIN = 10
M.WOOD_ID = 9
M.WORKBENCH_TILE = 18
M.WOOD_BLOCK = 30
M.PREVIEW_TILE = 19
M.WOOD_WALL = 4
M.TORCH = 4
M.ITEM_NAME = "house_wand"

function M.cells(x, y)
    local out = {}
    for dx = 0, M.WIDTH - 1 do
        for dy = 0, M.HEIGHT - 1 do
            local edge = dx == 0 or dx == M.WIDTH - 1 or dy == 0 or dy == M.HEIGHT - 1
            local door = dx == 0 and dy >= 2 and dy <= 5
            if edge and not door then out[#out + 1] = { x + dx, y - dy } end
        end
    end
    return out
end

function M.all_cells(x, y)
    local out = {}
    for dx = 0, M.WIDTH - 1 do
        for dy = 0, M.HEIGHT - 1 do out[#out + 1] = { x + dx, y - dy } end
    end
    return out
end

function M.wall_cells(x, y)
    local out = {}
    for dx = 1, M.WIDTH - 2 do
        for dy = 1, M.HEIGHT - 2 do
            -- Image reference has the wooden wall texture only within the room.
            out[#out + 1] = { x + dx, y - dy }
        end
    end
    return out
end

return M
