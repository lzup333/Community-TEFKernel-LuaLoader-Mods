-- sd_job.lua
-- Drag capture and the tile-removal queue. Work is spread over frames so a
-- 20x20 blast never blocks the main thread in a single tick.

local U = require("fbw_util")
local P = U.P

local M = {}
local SD

local PER_FRAME = 24

function M.setup(ctx)
    SD = ctx
    SD.S.job = nil
    SD.S.job_status = ""
    SD.S.dragging = false
    SD.S.drag_mode = nil
end

function M.reset_drag()
    SD.S.dragging = false
    SD.S.drag_mode = nil
    SD.S.sx, SD.S.sy = nil, nil
    SD.S.ex, SD.S.ey = nil, nil
end

local function mode_for_press(base, right)
    if right then
        if base == "tile" then return "tile" end
        return "wall"
    end
    return base
end

-- Normalise an arbitrary tile rect: order it, cap it to the configured max
-- size, clamp it into the world. Returns minx,miny,maxx,maxy or nil.
-- Shared by the blast queue and the world-space preview so that what the
-- player sees is exactly what gets removed.
local function norm_rect(x1, y1, x2, y2)
    local B = SD.bind
    local cfg = SD.cfg
    local maxw = cfg.max_width or 20
    local maxh = cfg.max_height or 20

    local minx, maxx = math.min(x1, x2), math.max(x1, x2)
    local miny, maxy = math.min(y1, y2), math.max(y1, y2)

    if maxx - minx + 1 > maxw then maxx = minx + maxw - 1 end
    if maxy - miny + 1 > maxh then maxy = miny + maxh - 1 end

    minx, miny = B.clamp_tile(minx, miny)
    maxx, maxy = B.clamp_tile(maxx, maxy)

    if minx > maxx or miny > maxy then return nil end
    return minx, miny, maxx, maxy
end

local function build_cells(x1, y1, x2, y2)
    local minx, miny, maxx, maxy = norm_rect(x1, y1, x2, y2)
    if not minx then return {} end

    local cells = {}
    for x = minx, maxx do
        for y = miny, maxy do
            cells[#cells + 1] = { x = x, y = y }
        end
    end
    return cells
end

-- Tile rect the next blast would cover, or nil when nothing is selected.
-- Mirrors finish_drag(): a real drag shows the drag rect, a single-tap drag
-- (or no drag at all) shows the default box around the aim tile.
function M.preview_rect()
    local S = SD.S
    if not S.held then return nil end

    if S.dragging and S.sx and S.ex then
        if S.sx ~= S.ex or S.sy ~= S.ey then
            return norm_rect(S.sx, S.sy, S.ex, S.ey)
        end
        -- single-cell drag == tap: fall through to the default box
    end

    if not S.aim_ok or type(S.aim_x) ~= "number" then
        -- no aim (e.g. aim source lost mid-tap): finish_drag() falls back to
        -- the drag start, so the preview must show the same box
        if type(S.sx) ~= "number" then return nil end
        local w = U.clamp(S.width or 5, 1, SD.cfg.max_width or 20)
        local h = U.clamp(S.height or 5, 1, SD.cfg.max_height or 20)
        local x1 = S.sx - math.floor((w - 1) / 2)
        local y1 = S.sy - math.floor((h - 1) / 2)
        return norm_rect(x1, y1, x1 + w - 1, y1 + h - 1)
    end

    local w = U.clamp(S.width or 5, 1, SD.cfg.max_width or 20)
    local h = U.clamp(S.height or 5, 1, SD.cfg.max_height or 20)
    local x1 = S.aim_x - math.floor((w - 1) / 2)
    local y1 = S.aim_y - math.floor((h - 1) / 2)
    return norm_rect(x1, y1, x1 + w - 1, y1 + h - 1)
end

function M.start(mode, x1, y1, x2, y2)
    local B = SD.bind
    local C = B.C
    local cells = build_cells(x1, y1, x2, y2)
    if #cells == 0 then
        SD.S.job_status = "范围无效"
        return false
    end
    if not C.m_killTile and not C.m_killWall then
        SD.S.job_status = "缺少拆除接口"
        U.log_error("[FBW] no KillTile/KillWall handle")
        return false
    end

    if mode ~= "wall" and not C.m_killTile then mode = "wall" end
    if mode ~= "tile" and not C.m_killWall then mode = "tile" end

    -- 拆除能力同步：取背包里最好的镐与锤（一次采样，整个爆破期间不变）
    -- 树一律允许拆，不检查任何工具
    local player = B.local_player()
    local bp, bh = B.best_tools(player)

    SD.S.job = {
        cells = cells,
        i = 1,
        total = #cells,
        mode = mode,
        tiles = 0,
        walls = 0,
        noitem = not SD.S.drop,
        t0 = os.clock(),
        player = player,
        tool_pick = bp,       -- 背包最高镐力：决定能拆哪些方块
        tool_hammer = bh,     -- 背包最高锤力：只用于恶魔祭坛
        mine_cache = {},      -- [图格类型] = 挖得动吗（每种类型只问一次原版）
    }
    SD.S.job_status = string.format("爆破中 0/%d", #cells)
    U.log_info(string.format(
        "[FBW] blast mode=%s rect=%d,%d..%d,%d cells=%d drop=%s tools=pick%d/hammer%d",
        tostring(mode), x1, y1, x2, y2, #cells, tostring(SD.S.drop), bp, bh))
    return true
end

function M.finish_drag()
    local S = SD.S
    if not S.dragging then return end
    local x1, y1, x2, y2 = S.sx, S.sy, S.ex, S.ey
    local mode = S.drag_mode or S.mode

    local moved = (x1 ~= nil and x2 ~= nil and (x1 ~= x2 or y1 ~= y2))
    if not moved then
        -- A tap is a blast of the configured default box around the cursor.
        local w = U.clamp(S.width or 5, 1, SD.cfg.max_width or 20)
        local h = U.clamp(S.height or 5, 1, SD.cfg.max_height or 20)
        local cx, cy = S.aim_x, S.aim_y
        if type(cx) ~= "number" then cx = x1 end
        if type(cy) ~= "number" then cy = y1 end
        if type(cx) ~= "number" then
            M.reset_drag()
            return
        end
        x1 = cx - math.floor((w - 1) / 2)
        y1 = cy - math.floor((h - 1) / 2)
        x2 = x1 + w - 1
        y2 = y1 + h - 1
        U.log_info(string.format("[FBW] tap blast %dx%d at %d,%d", w, h, cx, cy))
    end

    M.reset_drag()
    M.start(mode, x1, y1, x2, y2)
end

-- 这一格允许拆吗？
-- 用背包里最高的镐力去问原版（Player.HasEnoughPickPowerToHurtTile），
-- 结果按图格类型缓存 —— 一次爆破里同种方块只问一次，100×100 也只有几次调用。
-- 判不出来（返回 nil）一律放行，避免功能变砖。
local ALTAR_TILE = 26          -- 恶魔祭坛 / 猩红祭坛（同一图格，只是样式不同）
local ALTAR_HAMMER_POWER = 80  -- 80% 锤力：Wiki 里困难模式下的最低要求（神锤正好 80%）

-- 树无条件放行：不检查任何工具
local TREE_TILES = {
    [5]   = true,   -- 普通树 Trees
    [72]  = true,   -- 巨型发光蘑菇 MushroomTrees
    [170] = true,   -- 松树 PineTree
    [323] = true,   -- 棕榈树 PalmTree
    [596] = true,   -- 樱花树 VanityTreeSakura
    [616] = true,   -- 黄柳树 VanityTreeYellowWillow
    [634] = true,   -- 白蜡树 TreeAsh
    [583] = true, [584] = true, [585] = true,   -- 宝石树：黄玉 / 紫水晶 / 蓝玉
    [586] = true, [587] = true, [588] = true, [589] = true, -- 翡翠 / 红玉 / 钻石 / 琥珀
}

local function tile_allowed(job, x, y)
    local B = SD.bind
    local ttype = B.tile_type(x, y)
    if ttype == nil or ttype == 0 then return true end

    -- 树：无条件放行
    if TREE_TILES[ttype] then return true end

    -- 祭坛（恶魔 / 猩红）：锤力 ≥ 80% 且世界已进入困难模式才允许拆。
    -- 依据 Wiki：困难模式后任何 80% 以上锤力的锤都能砸；困难模式前砸只会掉一半血、
    -- 祭坛不受影响，所以这里直接跳过、不模拟掉血。
    if ttype == ALTAR_TILE then
        if (job.tool_hammer or 0) < ALTAR_HAMMER_POWER then return false end
        local hard = B.hard_mode()
        if hard == false then return false end   -- 明确没进困难模式：不拆
        return true                              -- 困难模式，或读不到标志：放行（只受锤力限制）
    end

    if not job.tool_pick then return true end
    local cached = job.mine_cache[ttype]
    if cached ~= nil then return cached end
    local can = B.can_mine_with(job.player or B.local_player(), x, y, job.tool_pick)
    if can == nil then return true end
    job.mine_cache[ttype] = can
    return can
end

-- 这一面墙允许拆吗？
--   地牢墙（蓝/绿/粉及其板砖、花砖）：必须击败骷髅王（NPC.downedBoss3）
--   其它墙：不设门槛（锤力只用于恶魔祭坛）
local function wall_allowed(job, x, y)
    local B = SD.bind
    local w = B.wall_type(x, y)
    if w == nil or w == 0 then return true end
    if not B.is_dungeon_wall(w) then return true end
    local downed = B.downed_boss3()
    if downed == nil then return true end
    return downed
end

function M.step()
    local S = SD.S
    local job = S.job
    if not job then return end
    local C = SD.bind.C
    local n = 0

    while n < PER_FRAME and job.i <= job.total do
        local c = job.cells[job.i]
        job.i = job.i + 1
        n = n + 1
        local x, y = c.x, c.y

        if job.mode ~= "wall" and C.m_killTile then
            local can = true
            if C.m_canKillTile then
                local okc, canv = pcall(P.invoke, C.m_canKillTile, x, y)
                if okc then can = (canv == true) end
            end
            if can then can = tile_allowed(job, x, y) end
            if can then
                local ok, res = pcall(P.invoke, C.m_killTile, x, y, false, false, job.noitem)
                if ok and res ~= false then job.tiles = job.tiles + 1 end
            end
        end

        -- 墙：锤力不再设门槛，只有地牢墙要求打过骷髅王
        if job.mode ~= "tile" and C.m_killWall and wall_allowed(job, x, y) then
            local ok, res = pcall(P.invoke, C.m_killWall, x, y, false)
            if ok and res ~= false then job.walls = job.walls + 1 end
        end
    end

    if job.i > job.total then
        local dt = os.clock() - (job.t0 or os.clock())
        S.job = nil
        S.job_status = string.format("完成：方块 %d / 墙 %d", job.tiles, job.walls)
        S.last_result = S.job_status
        U.log_info(string.format("[FBW] blast done cells=%d tiles=%d walls=%d %.2fs",
            job.total, job.tiles, job.walls, dt))
    else
        S.job_status = string.format("爆破中 %d/%d", job.i - 1, job.total)
    end
end

function M.tick(player)
    local S = SD.S
    local B = SD.bind

    M.step()
    if S.job then return end -- do not start a second blast while one is running

    local held = B.holding_wand(player)
    S.held = held
    if not held then
        M.reset_drag()
        S.aim_ok = false
        return
    end

    local ax, ay, src = B.aim(player)
    S.aim_x, S.aim_y, S.aim_src = ax, ay, src
    S.aim_ok = (src ~= "none")

    local left, right = B.use_state(player)
    if B.inventory_open() then
        left, right = false, false
        if S.dragging then M.reset_drag() end
    end

    if left or right then
        if not S.dragging then
            if S.aim_ok then
                S.dragging = true
                S.sx, S.sy = ax, ay
                S.ex, S.ey = ax, ay
                S.drag_mode = mode_for_press(S.mode, right)
                S.drag_frame = S.frame
            end
        elseif S.aim_ok then
            S.ex, S.ey = ax, ay
        end
    elseif S.dragging then
        M.finish_drag()
    end
end

function M.cancel()
    SD.S.job = nil
    SD.S.job_status = "已取消"
end

return M
