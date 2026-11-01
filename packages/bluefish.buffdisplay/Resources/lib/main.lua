-- Buff显示 —— 玩家及 NPC 头顶显示 Buff 图标与剩余时间
-- ============================================================================
-- 绘制方式：
--   SpriteBatch.Draw 需要一个 ref Rectangle 参数。本模组不用 set_field_raw
--   写结构体，而是先拿到一块 Rectangle 的内存地址，用 mem_write_values 直接
--   写 {x,y,w,h}，再拿同一个地址当 ref 传进去。地址来源三级兜底：
--     ① NPC.frame 字段指针    ② NPC.targetRect 字段指针
--     ③ 内建 boxed Rectangle 的 X 字段指针（X/Y/W/H 连续，指向 X 即首址）
--   倒计时用 3×5 点阵数字，逐行合并相邻亮点，一个数字只需 5~7 次 Draw。
-- ============================================================================

mod.meta = { pkg_id = "bluefish.buffdisplay", version = "1.2.4", version_code = 16 }

local P = mod.patch
local H, hooks = {}, {}
local disabled, failures = false, 0

local ANN_TEXT = "我已经看穿你了～（∠·ω< )⌒☆"
local ANN_DELAY = 60
local PLAYER_LIFT = 26        -- 玩家头顶额外抬高（像素）：数字不再被头部挡住

local CFG = {
    show_player = true,
    show_npc    = true,
    only_debuff = false,
    max_icons   = 4,
    show_timer  = true,
}

-- 诊断已移除：正式版只写普通日志，不再往 Download 写文件
local function note(s)
    pcall(mod.info, "[Buff显示] " .. tostring(s))
end

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 1e8
end

local function say(text)
    if not H.chat then
        local ok, m = pcall(P.get_method, P.get_type("Terraria", "Main"), "NewText", 5)
        if ok and m then H.chat = m end
    end
    if not H.chat then return false end
    local s = text
    if P.string_create then
        local okc, r = pcall(P.string_create, text)
        if okc and r then s = r end
    end
    local okc, r = pcall(P.invoke, H.chat, s, 210, 170, 255, false)
    return okc and r ~= false
end

-- ---------------- 配置 ----------------
local function parse_bool(raw, key, def)
    local lit = raw:match('"' .. key .. '"%s*:%s*([%a]+)')
    if lit == "true" then return true end
    if lit == "false" then return false end
    return def
end

local function refresh_config()
    if type(mod.read_file) ~= "function" then return end
    local ok, raw = pcall(mod.read_file, "config.json")
    if not ok or type(raw) ~= "string" then return end
    CFG.show_player = parse_bool(raw, "show_player", CFG.show_player)
    CFG.show_npc    = parse_bool(raw, "show_npc", CFG.show_npc)
    CFG.only_debuff = parse_bool(raw, "only_debuff", CFG.only_debuff)
    CFG.show_timer  = parse_bool(raw, "show_timer", CFG.show_timer)
    local mi = tonumber(raw:match('"max_icons"%s*:%s*"?([%d]+)"?'))
    if mi then
        if mi < 1 then mi = 1 end
        if mi > 10 then mi = 10 end
        CFG.max_icons = mi
    end
end

-- ---------------- 小工具 ----------------
local function value(f, obj, t)
    if not f then return nil end
    local ok, v = pcall(P.get_field_value, f, obj, t)
    if ok then return v end
    return nil
end

local function find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local f = P.get_field(cur, name)
        if f then return f end
        cur = P.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function release_roots()
    if H.gc_free then
        for _, root in ipairs(H.roots or {}) do pcall(P.invoke, H.gc_free, root) end
    end
    H.roots = {}
    H.scratch, H.rect_scratch = nil, nil
end

local function asset_texture(asset)
    if not asset or not H.asset_value then return end
    -- 去 pcall：产出路径每帧几十次，出错由 safe_step 兑底
    return P.get_field_value(H.asset_value, asset, "object")
end

local WHITE  = string.char(255, 255, 255, 255)
local URGENT = string.char(255, 70, 150, 255)
local NORMAL = string.char(255, 235, 235, 235)

-- Rectangle 缓冲（v1.0.3：三级兜底）
local RECT_PTR = nil          -- 结构体起始地址（数字）

local function probe_rect_buffer(nt, rect_t)
    for _, nm in ipairs({ "frame", "targetRect" }) do
        local f = find_field(nt, nm)
        if f then
            local okp, p = pcall(P.field_pointer, f, H.rect_scratch)
            if okp and p then
                RECT_PTR = p
                return nm
            end
        end
    end
    if rect_t then
        local okn, box = pcall(P.new_instance, rect_t)
        if okn and box then
            local fx = P.get_field(rect_t, "X")
            if fx then
                local okp, p = pcall(P.field_pointer, fx, box)
                if okp and p then
                    local okr, root = pcall(P.invoke, H.gc_alloc, box, nil, 2)
                    if okr and root and root ~= false then
                        H.rect_box_root = root   -- 保活：boxed Rectangle 的 GC 根，丢掉会被回收
                        RECT_PTR = p
                        return "boxed"
                    end
                end
            end
        end
    end
    return nil
end

local function set_rect_src(x, y, w, h)
    if not RECT_PTR then return false end
    -- 不再包 pcall：RECT_PTR 在 setup 里已验证可用，出错由 safe_step 的 xpcall 兑底
    P.mem_write_values(RECT_PTR, 0, { x, y, w, h }, "int32")
    return true
end

local function draw_tex(batch, texture, x, y, w, h, color)
    if not texture or not (finite(x) and finite(y)) then return false end
    if not set_rect_src(0, 0, w, h) then error("矩形缓冲写入失败") end
    P.set_field_vec2(H.scratch_pos, H.scratch, x, y)
    P.set_field_raw(H.scratch_color, H.scratch, color)
    -- 指针只算一次：H.scratch 整个模组生命周期固定，地址不会变
    local pos_ptr, col_ptr = H.pos_ptr, H.col_ptr
    if not pos_ptr then
        pos_ptr = P.field_pointer(H.scratch_pos, H.scratch)
        col_ptr = P.field_pointer(H.scratch_color, H.scratch)
        H.pos_ptr, H.col_ptr = pos_ptr, col_ptr
    end
    local result = P.invoke(H.draw, batch, texture, pos_ptr, RECT_PTR, col_ptr)
    if result == false then error("ref Draw 调用失败") end
    return true
end


local frames = 0

-- 3×5 点阵数字
local DIGITS = {
    ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
    ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
    ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
    ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "010", "010", "010" },
    ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
}

-- 预先编译成矩形段 {dx, dy, w}：同一行相邻亮点合并成一条，
-- 一个数字只需 5~7 次 Draw（老的写法是每个亮点 4 次，一个数字 44 次）
local DIGIT_SEGS = {}
for k, rows in pairs(DIGITS) do
    local segs = {}
    for row = 1, 5 do
        local line = rows[row]
        local c = 1
        while c <= 3 do
            if line:sub(c, c) == "1" then
                local run = 1
                while c + run <= 3 and line:sub(c + run, c + run) == "1" do run = run + 1 end
                segs[#segs + 1] = { (c - 1) * 2, (row - 1) * 2, run * 2 }
                c = c + run
            else
                c = c + 1
            end
        end
    end
    DIGIT_SEGS[k] = segs
end

-- 倒计时：3×5 点阵数字，超出 99 封顶为 99
local function timer(batch, pixel, cx, y, seconds)
    local txt = tostring(math.min(99, math.max(0, math.floor(seconds))))
    local color = (seconds <= 5) and URGENT or NORMAL
    local x0 = math.floor(cx - (#txt * 8 - 2) / 2 + 0.5)
    for i = 1, #txt do
        local segs = DIGIT_SEGS[txt:sub(i, i)]
        if segs then
            local ox = x0 + (i - 1) * 8
            for q = 1, #segs do
                local g = segs[q]
                draw_tex(batch, pixel, ox + g[1], y + g[2], g[3], 2, color)
            end
        end
    end
end

-- ---------------- Buff 收集 ----------------
local load_tried = {}

-- 复用缓冲：每帧不再新建表，避免 Lua GC 周期性回收造成的帧数尖峰
local CB_ID, CB_SEC, CB_N = {}, {}, 0

local function collect_buffs(types, times, limit, flags)
    CB_N = 0
    if not types or not times then return 0 end
    local n = P.array_length(types)
    if not finite(n) or n <= 0 then n = 20 end
    n = math.min(n, 22)
    for i = 0, n - 1 do
        -- 先只读 id：绝大多数槽位是 0，不必为它再读一次时间
        local id = P.array_at(types, i, "int32")
        if finite(id) and id > 0 and id < H.buff_limit then
            local t = P.array_at(times, i, "int32")
            if finite(t) and t > 0 then
                local isdeb = (flags and P.array_at(flags, id, "bool") == true) or false
                if (not CFG.only_debuff) or isdeb then
                    CB_N = CB_N + 1
                    CB_ID[CB_N] = id
                    CB_SEC[CB_N] = math.ceil(t / 60)
                    if CB_N >= limit then break end
                end
            end
        end
    end
    return CB_N
end

local ICON_W, ICON_H = 0, 0   -- Buff 图标尺寸（同尺寸，读一次就够）

local function draw_row(batch, pixel, textures, sx, top_y, types, times, flags)
    local n = collect_buffs(types, times, CFG.max_icons, flags)
    if n == 0 then return 0 end

    local ICON, GAP = 32, 2
    local total = n * ICON + (n - 1) * GAP
    local x0 = math.floor(sx - total / 2 + 0.5)
    local y = math.floor(top_y - ICON - 8 + 0.5)
    local drawn = 0

    for i = 1, n do
        local id = CB_ID[i]
        local tex = asset_texture(P.array_at(textures, id))
        if not tex and H.load_buff and not load_tried[id] then
            load_tried[id] = true
            pcall(P.invoke, H.load_buff, id)
            tex = asset_texture(P.array_at(textures, id))
        end
        if tex then
            if ICON_W == 0 then
                local w0 = value(H.tex_w, tex, "int32")
                local h0 = value(H.tex_h, tex, "int32")
                if finite(w0) and finite(h0) and w0 > 0 and h0 > 0 then
                    ICON_W, ICON_H = w0, h0
                end
            end
            local w, h = ICON_W, ICON_H
            if w > 0 and h > 0 and w <= 256 and h <= 256 then
                local ix = x0 + (i - 1) * (ICON + GAP)
                draw_tex(batch, tex, ix, y, w, h, WHITE)
                if CFG.show_timer then
                    timer(batch, pixel, ix + w / 2, y + h + 2, CB_SEC[i])
                end
                drawn = drawn + 1
            end
        end
    end
    return drawn
end

local function head_top_y(npc, ny, nh, sy)
    local top = ny
    if H.n_frame then
        local ok, raw = pcall(P.get_field_raw, H.n_frame, npc, 16)
        if ok and raw then
            local _, _, _, fh = string.unpack("<i4i4i4i4", raw)
            local scale = value(H.n_scale, npc, "float")
            if finite(fh) and fh > 0 and fh < 4096 and finite(scale) and scale > 0 and scale < 20 then
                top = math.min(top, ny + nh - fh * scale, ny + nh / 2 - fh * scale / 2)
            end
        end
    end
    return top - sy
end

-- ---------------- 主回调 ----------------
local reported = false

-- 性能：候选槽位缓存 + 全扫间隔（每 SCAN_EVERY 帧完整扫描一次 200 槽，其余帧只复查上次命中项）
local cand = {}
local scan_tick = 0
local SCAN_EVERY = 4

local function step(_, args)
    if disabled then return end
    if args and args[1] == true then return end

    local user = value(H.active_user, nil, "object") or value(H.primary_user, nil, "object")
    local state = user and value(H.user_state, user, "object")
    if not state then return end
    if value(H.menu, state, "bool") == true then frames = 0 return end

    local batch = value(H.batch, nil, "object")
    if not batch or value(H.begun, batch, "bool") ~= true then
        return
    end

    local sx, sy = P.get_field_vec2(H.camera, state)
    if not (finite(sx) and finite(sy)) then return end

    if not H.scr_w or frames % 300 == 0 then
        H.scr_w = value(H.screen_w, nil, "int32") or H.scr_w or 1920
        H.scr_h = value(H.screen_h, nil, "int32") or H.scr_h or 1080
    end
    local sw = H.scr_w
    local sh = H.scr_h
    local MARGIN = 96

    local pixel = asset_texture(value(H.pixel, nil, "object"))
    if not pixel then return end
    local pw = value(H.tex_w, pixel, "int32")
    local ph = value(H.tex_h, pixel, "int32")
    if not (finite(pw) and finite(ph) and pw > 0 and ph > 0) then
        return
    end

    local textures = value(H.buff_textures, nil, "object")
    if not textures then return end
    local debuffs = value(H.debuff, nil, "object")

    H.scratch = P.invoke(H.gc_target, H.scratch_root)
    if not H.scratch then return end

    frames = frames + 1
    -- 配置轮询：从每 2 秒改成每 30 秒（主线程读文件会造成帧率尖峰，实测表现为帧数锯齿）
    if frames % 1800 == 1 then refresh_config() end

    local entities, icons = 0, 0

    local npcs = value(H.npcs, nil, "object")
    if CFG.show_npc and npcs then
        scan_tick = scan_tick + 1
        local full = (scan_tick % SCAN_EVERY == 1)
        local list = cand
        local k = 0
        local hi = 199
        if not full then hi = #list end
        for j = 0, hi do
            local idx = j
            if not full then
                idx = list[j + 1]
                if idx == nil then break end
            end
            local n = P.array_at(npcs, idx)
            -- active 必须包 pcall：部分槽位的对象读字段会抛错，裸调用会每帧抛异常（实测导致 15 帧）
            if n and value(H.n.active, n, "bool") == true then
                local nx, ny = P.get_field_vec2(H.n.pos, n)
                local nw = value(H.n.w, n, "int32")
                local nh = value(H.n.h, n, "int32")
                if finite(nx) and finite(ny) and finite(nw) and finite(nh) then
                    local csx = nx + nw / 2 - sx
                    local csy = ny + nh / 2 - sy
                    if csx > -MARGIN and csx < sw + MARGIN and csy > -MARGIN and csy < sh + MARGIN then
                        entities = entities + 1
                        k = k + 1
                        list[k] = idx
                        local types = value(H.n.buff, n, "object")
                        local times = value(H.n.time, n, "object")
                        local top = head_top_y(n, ny, nh, sy)
                        icons = icons + draw_row(batch, pixel, textures, csx, top, types, times, debuffs)
                    end
                end
            end
        end
        local len = #list
        if k < len then
            for m = k + 1, len do list[m] = nil end
        end
    end

    if CFG.show_player then
        local players = value(H.players, nil, "object")
        local idx = value(H.my_player, state, "int32")
        if players and finite(idx) and idx >= 0 and idx <= 254 then
            local pl = P.array_at(players, idx)
            if pl and value(H.p.active, pl, "bool") == true then
                local px, py = P.get_field_vec2(H.p.pos, pl)
                local pw = value(H.p.w, pl, "int32")
                local ph = value(H.p.h, pl, "int32")
                if finite(px) and finite(py) and finite(pw) and finite(ph) then
                    entities = entities + 1
                    local top = py - sy - PLAYER_LIFT
                    local types = value(H.p.buff, pl, "object")
                    local times = value(H.p.time, pl, "object")
                    icons = icons + draw_row(batch, pixel, textures, px + pw / 2 - sx, top, types, times, debuffs)
                end
            end
        end
    end

    if not reported and frames >= ANN_DELAY then
        reported = true
        say(ANN_TEXT)
    end
end

local function safe_step(instance, args)
    if disabled then return end
    local ok, e = xpcall(function() step(instance, args) end, function(e)
        return tostring(e)
    end)
    if ok then failures = 0 return end
    failures = failures + 1
    if failures <= 2 then
        note("绘制错误 " .. failures .. ": " .. tostring(e))
    end
end

local function chk(cond, name)
    if not cond then error(name, 2) end
    return cond
end

local function field(t, name)
    return chk(P.get_field(t, name), "缺少字段 " .. name)
end

function setup()
    refresh_config()

    if type(P.get_method_by_param_types) ~= "function"
        or type(P.make_generic_type) ~= "function"
        or type(P.field_pointer) ~= "function" then
        note("初始化失败: 加载器缺少绘制接口")
        disabled = true
        return
    end

    local ok, e = pcall(function()
        local main   = chk(P.get_type("Terraria", "Main"), "缺少类型 Main")
        local nt     = chk(P.get_type("Terraria", "NPC"), "缺少类型 NPC")
        local pt     = chk(P.get_type("Terraria", "Player"), "缺少类型 Player")
        local st     = chk(P.get_type("", "LocalUserGameState"), "缺少类型 LocalUserGameState")
        local sb     = chk(P.get_type("Microsoft.Xna.Framework.Graphics", "SpriteBatch"), "缺少 SpriteBatch")
        local tx     = chk(P.get_type("Microsoft.Xna.Framework.Graphics", "Texture2D"), "缺少 Texture2D")
        local assets = chk(P.get_type("Terraria.GameContent", "TextureAssets"), "缺少 TextureAssets")
        local generic = chk(P.get_type("ReLogic.Content", "Asset`1"), "缺少 Asset`1")
        local rect_t = P.get_type("Microsoft.Xna.Framework", "Rectangle")

        H.asset_value = chk(field(P.make_generic_type(generic, { tx }), "Value"), "Asset`1.Value 缺失")

        local vec = chk(P.get_type("Microsoft.Xna.Framework", "Vector2"), "缺少 Vector2")
        local rectangle = chk(P.get_type("Microsoft.Xna.Framework", "Rectangle"), "缺少 Rectangle")
        local color = chk(P.get_type("Microsoft.Xna.Framework.Graphics", "Color"), "缺少 Color")

        H.draw = chk(P.get_method_by_param_types(sb, "Draw", { tx, vec, rectangle, color }),
            "找不到 Draw(Texture2D,ref Vector2,ref Rectangle,ref Color)")
        H.tex_w = field(tx, "Width")
        H.tex_h = field(tx, "Height")

        local user_t  = chk(P.get_type("", "LocalUser"), "缺少 LocalUser")
        local users_t = chk(P.get_type("", "UserManagement"), "缺少 UserManagement")
        H.active_user  = field(user_t, "Active")
        H.primary_user = field(users_t, "PrimaryPlayer")
        H.user_state   = field(user_t, "GameState")
        H.menu      = field(st, "gameMenu")
        H.my_player = field(st, "myPlayer")
        H.camera    = field(st, "screenPosition")

        H.players = field(main, "player")
        H.npcs    = field(main, "npc")
        H.batch   = field(main, "spriteBatch")
        H.begun   = field(sb, "_beginCalled")
        H.debuff  = field(main, "debuff")
        H.pixel   = field(assets, "MagicPixel")
        H.buff_textures = field(assets, "Buff")
        H.screen_w = P.get_field(main, "screenWidth")
        H.screen_h = P.get_field(main, "screenHeight")
        H.buff_limit = 401
        H.chat = P.get_method(main, "NewText", 5)
        H.load_buff = P.get_method(main, "LoadBuff", 1)

        local function entity(t)
            return { pos = field(t, "position"), w = field(t, "width"), h = field(t, "height"),
                     active = field(t, "active") }
        end
        H.p = entity(pt)
        H.n = entity(nt)
        H.n.life   = field(nt, "life")
        H.n.buff   = field(nt, "buffType")
        H.n.time   = field(nt, "buffTime")
        H.n_frame  = find_field(nt, "frame")
        H.n_scale  = find_field(nt, "scale")
        H.p.buff   = field(pt, "buffType")
        H.p.time   = field(pt, "buffTime")

        local gc = chk(P.get_type("System.Runtime.InteropServices", "GCHandle"), "缺少 GCHandle")
        H.gc_alloc  = chk(P.get_method(gc, "GetTargetHandle", 3), "缺少 GetTargetHandle")
        H.gc_target = chk(P.get_method(gc, "GetTarget", 1), "缺少 GetTarget")
        H.gc_free   = chk(P.get_method(gc, "FreeHandle", 1), "缺少 FreeHandle")

        local ct = chk(P.get_type("Terraria", "CombatText"), "缺少 CombatText")
        H.roots = {}
        local function rooted(t)
            local obj = chk(P.new_instance(t), "无法分配绘制缓冲")
            local root = P.invoke(H.gc_alloc, obj, nil, 2)
            chk(root and root ~= false, "GCHandle 保活失败")
            H.roots[#H.roots + 1] = root
            return obj, root
        end
        H.scratch, H.scratch_root = rooted(ct)
        H.rect_scratch = select(1, rooted(nt))
        H.scratch_pos   = field(ct, "position")
        H.scratch_color = field(ct, "color")
        chk(P.field_pointer(H.scratch_pos, H.scratch), "字段地址接口不可用")
        local rect_how = probe_rect_buffer(nt, rect_t)
        chk(rect_how, "矩形缓冲不可用")
        local method = chk(P.get_method(main, "DrawNPCs", 1), "缺少 Main.DrawNPCs")
        local h = chk(P.install_hook(method, { postfix = safe_step }), "钩子安装失败")
        hooks[#hooks + 1] = h
        note(string.format("就绪 矩形缓冲=%s 钩子=%d", tostring(rect_how), #hooks))
    end)

    if not ok then
        disabled = true
        note("初始化失败: " .. tostring(e))
        release_roots()
    end
end

function cleanup()
    disabled = true
    for _, h in ipairs(hooks) do pcall(function() h:remove() end) end
    hooks = {}
    release_roots()
    note("cleanup")
end

todo_list = { "setup" }