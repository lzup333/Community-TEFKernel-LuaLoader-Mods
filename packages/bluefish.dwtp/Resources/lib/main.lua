-- main.lua
-- 定位传送 v0.2.2
--   复刻 TShock 插件 DwTP：微光湖 / 神庙 / 花苞 / 地牢
--
--   原理：PE 图格是「坐标 → 定义槽位 → 类型」三级结构
--         TileLookup[坐标] = 槽位号（覆盖全图，已验证 3/3 抽查处有值）
--         TileType[槽位]   = 方块类型（槽位池只有几千个，整块读进内存）
--     所以：先筛出目标槽位号，再去 46MB 的 TileLookup 里搜这些号码，
--           命中的位置就是坐标。
--
--   v0.2.1 关键改动：不再依赖 Player.Update 钩子。
--     扫描的主驱动放在 mod.on_gui 里（面板可见时每帧都被调用），
--     每帧只扫一小段，几帧扫完，不卡。
--     取玩家改用 Main.player[Main.myPlayer]。

local patch = mod.patch
local M = {}

local SD = {
    status = "待命",
    inited = false,
    defs = nil, slot_count = 0,
    arrLookup = nil, mx = 0, my = 0,
    scan = nil, progress = 0,
    diag = "",
}
_G.DWTP_SD = SD

-- 句柄
local T_Main, T_TileData, T_Player
local h_NewText, h_gameMenu, h_GetType, h_Teleport
local F_maxTX, F_maxTY, F_TileType, F_TileLiquid, F_TileBHeader, F_TileLookup, F_TotalCount
local F_pos, F_vel, F_playerArr, F_myPlayer, F_dungeonX, F_worldSurface

-- 目标方块 ID
local ID_TEMPLE = 237     -- 神庙砖
local ID_BUD = 238        -- 世纪之花花苞
local NAMES = { wg = "微光湖", sm = "神庙", hb = "花苞", dl = "地牢" }
local MAX_SLOT = 200000   -- TileBufferSize
local SCAN_PER_FRAME = 4000  -- 每帧读多少块 4KB（4000≈16MB）

local function log(msg) pcall(mod.info, "[DwTP] " .. tostring(msg)) end

local function say(text, r, g, b)
    log(text)
    if not h_NewText then return end
    local ok, hs = pcall(patch.string_create, text)
    if not ok or not hs then
        pcall(patch.invoke, h_NewText, text, r or 190, g or 225, b or 255, false)
        return
    end
    pcall(patch.invoke, h_NewText, hs, r or 190, g or 225, b or 255, false)
end

local function type_of(ns, cls)
    local ok, t = pcall(patch.get_type, ns, cls)
    if ok and t then return t end
    if patch.get_type_by_name then
        local ok2, t2 = pcall(patch.get_type_by_name, ns .. "." .. cls)
        if ok2 and t2 then return t2 end
    end
    return nil
end

local function field_int(f)
    if not f then return nil end
    local ok, v = pcall(patch.get_field_value, f, nil, "int32")
    if ok and type(v) == "number" then return v end
    return nil
end

-- 读一块内存。签名 (ptr, offset, size)：第 1 参必须是指针，size 上限 4096
local function read_mem(ptr, offset, size)
    if type(patch.mem_read) ~= "function" then return nil end
    local ok, v = pcall(patch.mem_read, ptr, offset, size)
    if not ok then return nil end
    if type(v) == "string" then return v end
    return nil
end

-- 静态裸指针字段 → 真正的数组指针
local function array_ptr(field)
    if not field then return nil end
    if type(patch.field_pointer) ~= "function" or type(patch.ptr_deref) ~= "function" then return nil end
    local ok, fp = pcall(patch.field_pointer, field, nil)
    if not ok or not fp then return nil end
    local ok2, arr = pcall(patch.ptr_deref, fp, 0)
    if not ok2 or not arr then return nil end
    return arr
end

local function read_whole(field, bytes)
    local arr = array_ptr(field)
    if not arr then return nil end
    local parts, off = {}, 0
    while off < bytes do
        local sz = math.min(4096, bytes - off)
        local b = read_mem(arr, off, sz)
        if not b or #b == 0 then break end
        parts[#parts + 1] = b
        off = off + #b
    end
    if #parts == 0 then return nil end
    return table.concat(parts)
end

-- ============ 初始化 ============
local function ensure_handles()
    if T_Main then return true end
    T_Main = type_of("Terraria", "Main")
    T_TileData = type_of("Terraria", "TileData")
    T_Player = type_of("Terraria", "Player")
    if not T_Main or not T_TileData then return false end

    F_maxTX = patch.get_field(T_Main, "maxTilesX")
    F_maxTY = patch.get_field(T_Main, "maxTilesY")
    F_playerArr = patch.get_field(T_Main, "player")
    F_myPlayer = patch.get_field(T_Main, "myPlayer")
    F_dungeonX = patch.get_field(T_Main, "dungeonX")
    F_worldSurface = patch.get_field(T_Main, "worldSurface")
    F_TileType = patch.get_field(T_TileData, "TileType")
    F_TileLiquid = patch.get_field(T_TileData, "TileLiquid")
    F_TileBHeader = patch.get_field(T_TileData, "TileBHeader")
    F_TileLookup = patch.get_field(T_TileData, "TileLookup")
    F_TotalCount = patch.get_field(T_TileData, "TotalTileCount")
    h_NewText = patch.get_method(T_Main, "NewText", 5)
    h_gameMenu = patch.get_method(T_Main, "get_gameMenu")
    h_GetType = patch.get_method(T_TileData, "GetType", 1)
    if T_Player then
        F_pos = patch.get_field(T_Player, "position")
        F_vel = patch.get_field(T_Player, "velocity")
        h_Teleport = patch.get_method(T_Player, "Teleport", 3)
    end
    SD.mx = field_int(F_maxTX) or 0
    SD.my = field_int(F_maxTY) or 0
    return true
end

local function in_world()
    if h_gameMenu then
        local ok, v = pcall(patch.invoke, h_gameMenu)
        if ok and type(v) == "boolean" then return v == false end
    end
    return SD.mx > 100
end

local function get_player()
    if not F_playerArr then return nil end
    local ok, arr = pcall(patch.get_field_value, F_playerArr, nil, "object")
    if not ok or not arr then return nil end
    local idx = field_int(F_myPlayer) or 0
    local ok2, p = pcall(patch.array_at, arr, idx)
    if ok2 and p then return p end
    return nil
end

local function build_defs()
    if SD.defs then return true end
    -- 关键：槽位号散布在 0..199999 的整个缓冲区里，不是从 0 连续排的。
    -- TotalTileCount 只是「当前有效定义数」（例：6790），必须按缓冲区全长读。
    local valid = field_int(F_TotalCount) or 0
    local t = read_whole(F_TileType, MAX_SLOT * 2)
    if not t then return false end
    local h = read_whole(F_TileBHeader, MAX_SLOT)
    SD.defs = { n = MAX_SLOT, valid = valid, type = t, bhead = h }
    SD.slot_count = valid
    return true
end

local function ensure_init()
    if SD.inited then return true end
    if not ensure_handles() then
        SD.diag = "类型缺失"
        return false
    end
    if not in_world() then
        SD.diag = "不在世界里 mx=" .. tostring(SD.mx)
        return false
    end
    SD.arrLookup = array_ptr(F_TileLookup)
    if not SD.arrLookup then
        SD.diag = "TileLookup 指针拿不到"
        return false
    end
    if not build_defs() then
        SD.diag = "定义池读取失败"
        return false
    end
    SD.inited = true
    SD.status = string.format("就绪｜定义 %d 种｜世界 %dx%d", SD.slot_count, SD.mx, SD.my)
    SD.diag = ""
    say(string.format("[定位传送] %s", SD.status), 150, 255, 180)
    return true
end

-- ============ 定义池查询 ============
local function def_type(slot)
    local d = SD.defs
    if not d or slot < 0 or slot >= d.n then return nil end
    local ok, v = pcall(string.unpack, "<I2", d.type, slot * 2 + 1)
    if ok then return v end
    return nil
end

local function def_bhead(slot)
    local d = SD.defs
    if not d or not d.bhead or slot < 0 or slot >= d.n then return nil end
    return string.byte(d.bhead, slot + 1)
end

-- 返回 槽位集合, 说明文字
local function pick_slots(kind)
    local set, counted = {}, 0
    local d = SD.defs
    if not d then return set, 0 end
    for slot = 0, d.n - 1 do
        local ty = def_type(slot)
        local hit = false
        if kind == "temple" then
            hit = (ty == ID_TEMPLE)
        elseif kind == "bud" then
            hit = (ty == ID_BUD)
        elseif kind == "shimmer" then
            -- 液体类型 = (bHeader & 0x60) >> 5，微光 = 3 → bit5/bit6 都置位
            local bh = def_bhead(slot)
            hit = (bh ~= nil and bh >= 96 and bh < 128)
        end
        if hit then
            set[slot] = true
            counted = counted + 1
        end
    end
    return set, counted
end

-- ============ 扫描（分帧） ============
local function start_scan(kind)
    if not ensure_init() then
        SD.status = "未就绪：" .. SD.diag
        return
    end
    if not SD.defs then return end
    local set, count = pick_slots(kind)
    local pats = {}
    for s in pairs(set) do pats[#pats + 1] = string.pack("<I4", s) end
    if count == 0 then
        SD.status = string.format("%s：%d 个槽位里都没有", NAMES[kind] or kind, SD.defs.n)
        say("[定位传送] " .. SD.status, 255, 200, 120)
        return
    end
    SD.scan = {
        kind = kind, pats = pats, n = count,
        off = 0, total = SD.mx * SD.my * 4,
    }
    SD.progress = 0
    SD.status = string.format("扫描中 0%%（%d 种定义）", count)
end

local function teleport_to(tx, ty)
    local p = get_player()
    if not p then return false, "取不到玩家" end
    local wx, wy = tx * 16 + 8, ty * 16 + 8
    if h_Teleport and type(patch.struct_arg) == "function" and type(patch.invoke_value_args) == "function" then
        local ok = pcall(patch.invoke_value_args, h_Teleport, p, {
            patch.struct_arg({ "float", "float" }, { wx, wy }), 1, 0,
        })
        if ok then return true, "teleport" end
    end
    if F_pos then
        local ok = pcall(patch.set_field_vec2, F_pos, p, wx, wy)
        if ok then
            if F_vel then pcall(patch.set_field_vec2, F_vel, p, 0, 0) end
            return true, "setpos"
        end
    end
    return false, "两个方法都失败"
end

-- 用游戏自己的 GetType 复核命中格，避免槽位共享 / 定义池错位导致的误判
local function verify_hit(x, y, kind)
    if not h_GetType then return true end
    if kind == "shimmer" then return true end  -- 液体格的 GetType 恒为 0，没法用类型复核
    if x < 1 or y < 1 or x >= SD.mx - 1 or y >= SD.my - 1 then return false end
    local lg = x + SD.mx * y
    local ok, v = pcall(patch.invoke, h_GetType, lg)
    if not ok or type(v) ~= "number" then return true end
    if kind == "temple" then return v == ID_TEMPLE end
    if kind == "bud" then return v == ID_BUD end
    return true
end

local function finish(kind, x, y, err)
    SD.scan = nil
    SD.progress = 0
    local name = NAMES[kind] or kind
    if not x then
        SD.status = string.format("%s：%s", name, tostring(err))
        say("[定位传送] " .. SD.status, 255, 200, 120)
        return
    end
    local tx, ty
    if kind == "sm" then tx, ty = x + 6, math.max(1, y - 3)
    else tx, ty = x, math.max(1, y - 3) end
    local ok, how = teleport_to(tx, ty)
    SD.status = string.format("%s %d,%d %s", name, x, y, ok and "已传送" or how)
    say("[定位传送] " .. SD.status, ok and 150 or 255, ok and 255 or 180, ok and 180 or 130)
end

local function step_scan()
    local s = SD.scan
    if not s then return end
    local budget = 0
    while s.off < s.total and budget < SCAN_PER_FRAME do
        local sz = math.min(4096, s.total - s.off)
        local b = read_mem(SD.arrLookup, s.off, sz)
        if not b or #b == 0 then
            finish(s.kind, nil, nil, "读取中断")
            return
        end
        for i = 1, #s.pats do
            local pos = 1
            local tries = 0
            while tries < 400 do
                local p = string.find(b, s.pats[i], pos, true)
                if not p then break end
                tries = tries + 1
                local byteoff = s.off + p - 1
                if byteoff % 4 == 0 then
                    local lg = byteoff // 4
                    local yy = lg // SD.mx
                    local xx = lg % SD.mx
                    if verify_hit(xx, yy, s.kind) then
                        finish(s.kind, xx, yy, nil)
                        return
                    end
                end
                pos = p + 1
            end
        end
        s.off = s.off + #b
        budget = budget + 1
    end
    if s.off >= s.total then
        finish(s.kind, nil, nil, "全图扫完没找到")
        return
    end
    SD.progress = s.off / s.total
    SD.status = string.format("扫描中 %d%%（%s）", math.floor(SD.progress * 100), NAMES[s.kind] or s.kind)
end

-- ============ 地牢（Main.dungeonX 地表入口） ============
local function do_dungeon()
    local dx = field_int(F_dungeonX)
    if not dx or dx <= 1 or dx >= SD.mx - 1 then
        SD.status = string.format("地牢：dungeonX 读不到（%s）", tostring(dx))
        say("[定位传送] " .. SD.status, 255, 200, 120)
        return
    end
    local ok, sy = pcall(patch.get_field_value, F_worldSurface, nil, "double")
    if not ok or type(sy) ~= "number" or sy <= 0 then sy = SD.my * 0.3 end
    local ty = math.max(1, math.floor(sy) - 3)
    local sok, how = teleport_to(dx, ty)
    SD.status = string.format("地牢 %d,%d（地表入口）%s", dx, ty, sok and "已传送" or how)
    say("[定位传送] " .. SD.status, sok and 150 or 255, sok and 255 or 180, sok and 180 or 130)
end

-- ============ 面板（主驱动） ============
function M.on_gui()
    local g = mod.gui
    if not g or type(g.text) ~= "function" or type(g.button) ~= "function" then return end

    g.text("定位传送")

    -- 驱动：初始化 + 扫描推进（放在按钮之前，保证一帧内就能开始）
    if not SD.inited then ensure_init() end
    if SD.scan then step_scan() end

    g.separator()
    if SD.scan then
        g.text("扫描中…")
    else
        if g.button("微光湖") then start_scan("shimmer") end
        if g.button("神庙") then start_scan("temple") end
        if g.button("花苞") then start_scan("bud") end
        if g.button("地牢") then do_dungeon() end
    end
    g.separator()
    g.text("状态：" .. tostring(SD.status))
    if not SD.inited and SD.diag ~= "" then
        g.text("诊断：" .. SD.diag)
    end
end
mod.on_gui = M.on_gui