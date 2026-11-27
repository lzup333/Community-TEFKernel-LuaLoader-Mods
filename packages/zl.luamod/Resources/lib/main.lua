-- 万物随机 (TreeSpawn-Pro) v1.1.0
-- 挖任意方块时，按掉落的物品数量随机生成相应数量的生物。
-- 生成类别可在 TEFManager 启动器的设置里独立开关，另有总开关。
mod.meta = { pkg_id = "zl.luamod", version = "2.4.0", version_code = 15, api_version = 1 }

local patch = mod.patch
local H = {}
local hooks = {}
local in_world = false      -- 进世界后才允许生成，避免加载期 invoke
local debug_once = {}

local config = {
    mod_enabled = true,
    town_npc = true,
    boss = true,
    monster = true,
    animal = true,
    chance_percent = 100,
    town_npc_rate = 10,
    boss_rate = 5,
    monster_rate = 30,
    animal_rate = 20,
}

-- 物品完全随机掉落：本次会话内 tileType -> itemType 的稳定映射，换世界重置
local drop_map = {}

local BOSS = {
    4, 13, 35, 50, 113, 125, 126, 127, 134, 222, 245, 262, 266, 325, 327, 344, 345, 370, 392, 398, 439, 657, 668
}

local TOWN_NPC = {
    17, 18, 19, 20, 22, 38, 54, 107, 108, 124, 142, 160, 178, 207, 208, 209, 227, 228, 229, 353, 368, 441, 453, 588, 663
}

local ANIMAL = {
    46, 55, 74, 148, 299, 300, 355, 356, 358, 359, 361, 362, 442, 443, 445, 448, 608, 611, 615, 616, 625, 626, 627
}

local MONSTER = {
    1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 21, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 36, 37, 39,
    40, 41, 42, 43, 44, 45, 47, 48, 49, 51, 52, 53, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73,
    75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104,
    105, 106, 109, 110, 111, 112, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 128, 129, 130, 131, 132, 133, 135, 136, 137, 138, 139, 140, 141, 143,
    144, 145, 146, 147, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
    176, 177, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206,
    210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 223, 224, 225, 226, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243,
    244, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 263, 264, 265, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276,
    277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 301, 302, 303, 304, 305, 306, 307, 308,
    309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 326, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340,
    341, 342, 343, 346, 347, 348, 349, 350, 351, 352, 354, 357, 360, 363, 364, 365, 366, 367, 369, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381,
    382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 393, 394, 395, 396, 397, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413,
    414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 440, 444, 446, 447, 449,
    450, 451, 452, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480,
    481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510,
    511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540,
    541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570,
    571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601,
    602, 603, 604, 605, 606, 607, 609, 610, 612, 613, 614, 617, 618, 619, 620, 621, 622, 623, 624, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638,
    639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656, 658, 659, 660, 661, 662, 664, 665, 666, 667, 669, 670, 671,
    672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 691, 692, 693, 694, 695, 696
}

-- ============================ 工具 ============================

local function try_method(t, name, argc)
    if not t then return nil end
    local ok, m = pcall(patch.get_method, t, name, argc)
    if ok and m then return m end
    return nil
end

local function log_note(key, msg)
    if debug_once[key] then return end
    debug_once[key] = true
    pcall(mod.info, "[万物随机] " .. msg)
end

-- 世界内聊天播报（加载期不调用，避免 invoke 崩溃）
local function chat(text)
    if not in_world or not H.m_new_text then return end
    local arg = text
    if patch.string_create then
        local oks, h = pcall(patch.string_create, text)
        if oks and h then arg = h end
    end
    if H.new_text_argc == 4 then
        pcall(patch.invoke, H.m_new_text, arg, 255, 210, 70, false)
    else
        pcall(patch.invoke, H.m_new_text, arg, 255, 210, 70)
    end
end

local function tile_type_at(x, y)
    local w = patch.get_field_value(H.f_maxx, nil, "int32")
    if not w or not H.m_get_type then return 0 end
    local idx = x + y * w
    local ok, v = pcall(patch.invoke, H.m_get_type, idx)
    if not ok then return 0 end
    return tonumber(v) or 0
end

-- 原版 NPC.NewNPC(source, X, Y, Type, Start, ai0, ai1, ai2, ai3, Target) —— 共 10 个参数
-- source 不能传 nil：原版内部会解引用它。必须给一个 Terraria.DataStructures.EntitySource_SpawnNPC 实例。
local function make_source()
    if not H.m_source_ctor then return nil end
    local ok, src = pcall(patch.new_instance, H.t_source)
    if ok and src then return src end
    return nil
end

local function spawn_npc(npc_type, px, py)
    if not npc_type or npc_type <= 0 then return nil end
    if not H.m_new_npc then return nil end
    local src = make_source()
    local ok, id = pcall(patch.invoke, H.m_new_npc,
        src, px, py, npc_type, 0, 0.0, 0.0, 0.0, 0.0, 255)
    if not ok or type(id) ~= "number" then return nil end
    return id
end

local function pick(pool)
    if not pool or #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

-- ============================ 设置 ============================

local function read_config()
    local raw = mod.read_file("config.json")
    if not raw or type(raw) ~= "string" or #raw == 0 then return false end
    local function gb(key, def)
        local v = raw:match('"' .. key .. '"%s*:%s*(%a+)')
        if v == "true" then return true elseif v == "false" then return false end
        return def
    end
    local function gi(key, def)
        local v = raw:match('"' .. key .. '"%s*:%s*(%-?%d+)')
        return v and tonumber(v) or def
    end
    config.mod_enabled    = gb("mod_enabled", true)
    config.town_npc       = gb("town_npc", true)
    config.boss           = gb("boss", true)
    config.monster        = gb("monster", true)
    config.animal         = gb("animal", true)
    local c = gi("chance_percent", 100)
    if c < 1 then c = 1 elseif c > 100 then c = 100 end
    config.chance_percent = c
    config.town_npc_rate = gi("town_npc_rate", 10)
    config.boss_rate     = gi("boss_rate", 5)
    config.monster_rate  = gi("monster_rate", 30)
    config.animal_rate   = gi("animal_rate", 20)
    return true
end

-- ============================ 掉落统计 ============================

-- 统计 Main.item 里当前激活的物品堆叠总数
local function alive_stack_sum()
    if not H.f_items then return 0 end
    local ok, items = pcall(patch.get_field_value, H.f_items, nil, "object")
    if not ok or not items then return 0 end
    local ok2, n = pcall(patch.array_length, items)
    if not ok2 or not n then return 0 end
    local total = 0
    for i = 0, n - 1 do
        local ok3, it = pcall(patch.array_at, items, i)
        if ok3 and it and patch.is_valid(it) then
            local ok4, act = pcall(patch.invoke, H.m_wi_active, it)
            if ok4 and act == true then
                local ok5, st = pcall(patch.get_field_value, H.f_stack, it, "int32")
                if ok5 and type(st) == "number" and st > 0 then total = total + st end
            end
        end
    end
    return total
end

-- ============================ 生成 ============================

local function spawn_batch(n, px, py)
    -- 按各自刷新率作为权重，收集启用中的池子
    local pools, weights, total = {}, {}, 0
    local function add(pool, on, rate)
        if on and pool and #pool > 0 and rate > 0 then
            pools[#pools + 1] = pool
            weights[#weights + 1] = rate
            total = total + rate
        end
    end
    add(TOWN_NPC, config.town_npc, config.town_npc_rate)
    add(BOSS,     config.boss,     config.boss_rate)
    add(MONSTER,  config.monster,  config.monster_rate)
    add(ANIMAL,   config.animal,   config.animal_rate)
    if total <= 0 then return 0 end

    local made = 0
    for _ = 1, n do
        -- 加权轮盘
        local r = math.random() * total
        local chosen = pools[#pools]
        for k = 1, #pools do
            r = r - weights[k]
            if r <= 0 then chosen = pools[k]; break end
        end
        if spawn_npc(pick(chosen), px, py) then made = made + 1 end
    end
    return made
end

-- ============================ 物品完全随机掉落 ============================
-- 规则：同一种方块在一局世界内固定掉同一样物品，换世界后全部重新随机。
-- 为什么不 hook Item.NewItem：方块掉落走的是 12 参的 IEntitySource 重载，
-- 拦住 9 参版本不会触发。改为在 KillTile 前后对比 Main.item 的激活槽位，
-- 挖完新出现的那些掉落物就是本次产物，直接改写它们的 inner.type。

local function active_slot_set()
    local set = {}
    if not H.f_items then return set end
    local ok, items = pcall(patch.get_field_value, H.f_items, nil, "object")
    if not ok or not items then return set end
    local ok2, n = pcall(patch.array_length, items)
    if not ok2 or not n then return set end
    for i = 0, n - 1 do
        local ok3, it = pcall(patch.array_at, items, i)
        if ok3 and it and patch.is_valid(it) then
            local ok4, act = pcall(patch.invoke, H.m_wi_active, it)
            if ok4 and act == true then set[i] = true end
        end
    end
    return set
end

local function new_random_item()
    local maxid = H.item_count or 6196
    local id = math.random(1, maxid - 1)
    if id <= 0 then id = 1 end
    return id
end

-- 进入世界即重掷掉落表。
-- 本函数由 Main.DoUpdateInWorld.prefix 在世界内每帧调用；
-- DoUpdateInWorld 只在「已经在世界里」时执行，所以：
--   · worldID 与上次不同（换世界 / 重进同名世界）→ 重掷
--   · 检测到「曾经离开世界」（两次调用间隔很大）→ 重掷
local last_world_id = nil
local last_tick_ms = nil

local function check_world_changed()
    -- 1) worldID 比对（最可靠：重进同名世界 worldID 也会变）
    if H.m_world_id then
        local ok, wid = pcall(patch.invoke, H.m_world_id)
        if ok and type(wid) == "number" then
            if last_world_id == nil then
                last_world_id = wid
                in_world = true
                log_note("world_init", "世界 " .. tostring(wid) .. " 就绪")
            elseif wid ~= last_world_id then
                last_world_id = wid
                drop_map = {}
                in_world = true
                log_note("world_reset", "进入世界 " .. tostring(wid) .. "，掉落表已重掷")
            else
                in_world = true
            end
            return
        end
    end

    -- 2) worldID 取不到时退化：用调用间隔判断（离开世界后该函数不再被调用）
    local now = os.time and os.time() or 0
    if now > 0 then
        if last_tick_ms == nil then
            last_tick_ms = now
            in_world = true
        else
            if now - last_tick_ms > 5 then      -- 超过 5 秒没跑过 → 刚从菜单进世界
                drop_map = {}
                log_note("world_reenter", "重新进入世界，掉落表已重掷")
            end
            last_tick_ms = now
            in_world = true
        end
    end
end

local function item_for_key(key)
    local cached = drop_map[key]
    if cached then return cached end
    local t = new_random_item()
    drop_map[key] = t
    return t
end

local function rewrite_new_drops(before_set, fallback_key)
    if not H.f_items or not H.f_inner or not H.f_item_type then
        log_note("rw_missing", "替换不可用：Main.item/WorldItem.inner/Item.type 有缺失")
        return 0
    end

    local ok, items = pcall(patch.get_field_value, H.f_items, nil, "object")
    if not ok or not items then
        log_note("rw_noitems", "替换失败：读不到 Main.item")
        return 0
    end
    local ok2, n = pcall(patch.array_length, items)
    if not ok2 or not n then
        log_note("rw_nolen", "替换失败：Main.item 长度读不到")
        return 0
    end

    local changed = 0
    for i = 0, n - 1 do
        if not before_set[i] then
            local ok3, it = pcall(patch.array_at, items, i)
            if ok3 and it and patch.is_valid(it) then
                local ok4, act = pcall(patch.invoke, H.m_wi_active, it)
                if ok4 and act == true then
                    local ok5, inner = pcall(patch.get_field_value, H.f_inner, it, "object")
                    if ok5 and inner and patch.is_valid(inner) then
                        local ok6, cur = pcall(patch.get_field_value, H.f_item_type, inner, "int32")
                        cur = ok6 and tonumber(cur) or nil
                        if cur then
                            local target = item_for_key(cur)
                            if target ~= cur then
                                -- 先记下堆叠数：SetDefaults 会把它重置为 1
                                local okst, keep_stack = pcall(patch.get_field_value, H.f_stack, inner, "int32")
                                keep_stack = (okst and type(keep_stack) == "number" and keep_stack > 0) and keep_stack or 1

                                -- 关键：必须走 SetDefaults(target)。
                                -- 它内部会 type = target，并重算 createTile / width / height /
                                -- useStyle 等全部派生字段。只写 type 会导致：
                                --   · 贴图变了，但 createTile 还是旧的 → 放地上变回原方块
                                --   → 这正是"贴图是剑、放地上却变泥土"的原因。
                                local okw = false
                                if H.m_set_defaults then
                                    -- variant 是引用类型，传 nil 走 SelectVariant 默认逻辑
                                    okw = pcall(patch.invoke, H.m_set_defaults, inner, target, nil)
                                else
                                    okw = pcall(patch.set_field_value, H.f_item_type, inner, target, "int32")
                                end

                                if okw then
                                    -- 还原堆叠数，避免变成 1 个
                                    if keep_stack > 1 and H.f_stack then
                                        pcall(patch.set_field_value, H.f_stack, inner, keep_stack, "int32")
                                    end
                                    changed = changed + 1
                                    -- 同步到服务端与其它客户端（消息号 21 = 物品格同步）
                                    if H.m_send then
                                        pcall(patch.invoke, H.m_send, 21, -1, -1, nil, i)
                                    end
                                else
                                    log_note("rw_writefail", "SetDefaults 改写失败")
                                end

                            end
                        else
                            log_note("rw_nocur", "读不到掉落物 Item.type")
                        end
                    else
                        log_note("rw_noinner", "读不到 WorldItem.inner")
                    end
                else
                    log_note("rw_noactive", "读不到 WorldItem.active")
                end
            end
        end
    end

    if changed > 0 then
        log_note("rw_ok", "物品替换成功 " .. changed .. " 个")
    elseif not debug_once.rw_nodrop then
        debug_once.rw_nodrop = true
        pcall(mod.info, "[万物随机] 本次挖掉没有检测到新掉落物（可能是 noItem 或被其它 mod 接管）")
    end
    return changed
end

-- 以下变量被 Hook 段引用，先声明（local 只在其后可见）
local pending_tile = nil
local pending_set = nil
local pending_x, pending_y = nil, nil

-- ============================ Hook ============================

-- 记录「本次正在被挖」的方块：挖掉后图格就变 0 了，
-- 物品替换和刷怪都靠它判断掉落来自哪种方块。

local function on_kill_prefix(inst, args)
    if not in_world or not config.mod_enabled then return false end
    if args[3] or args[4] then return false end   -- fail / effectOnly
    H.prev_stack = alive_stack_sum()
    pending_x, pending_y = args[1], args[2]
    pending_tile = tile_type_at(args[1], args[2])
    pending_set = active_slot_set()
    return false
end

local function on_kill_postfix(inst, args)
    if not in_world or not config.mod_enabled then return end
    local i, j = args[1], args[2]
    if args[3] or args[4] then return end

    -- 先把本次新掉的物品改写成「该方块在这局世界对应的随机物品」
    -- 物品完全随机掉落：常开（设置里已移除该开关）
    rewrite_new_drops(pending_set or {}, pending_tile)

    -- 本次新掉的堆叠数 = 后 - 前（至少 1）
    local after = alive_stack_sum()
    local n = after - (H.prev_stack or 0)
    if n < 1 then n = 1 end
    if n > 20 then n = 20 end          -- 防爆保护

    if config.chance_percent < 100 then
        if math.random(100) > config.chance_percent then return end
    end

    local made = spawn_batch(n, i * 16 + 8, j * 16)
    if made > 0 then
        log_note("first_spawn", "首次触发成功：掉落堆叠 " .. n .. " -> 生成 " .. made .. " 只")
    end
end

-- ============================ 初始化 ============================

function setup()
    local ok, err = pcall(function()
        local T_WG   = patch.get_type("Terraria", "WorldGen")
        local T_TD   = patch.get_type("Terraria", "TileData")
        local T_NPC  = patch.get_type("Terraria", "NPC")
        local T_Main = patch.get_type("Terraria", "Main")
        local T_Item = patch.get_type("Terraria", "Item")
        local T_WI   = patch.get_type("Terraria", "WorldItem")
        local T_Ply  = patch.get_type("Terraria", "Player")
        local T_Src  = patch.get_type("Terraria.DataStructures", "EntitySource_SpawnNPC")
        local T_ItemID = patch.get_type("Terraria.ID", "ItemID")
        if not (T_WG and T_TD and T_NPC and T_Main) then error("核心类型缺失") end

        H.m_kill_tile = try_method(T_WG, "KillTile", 5)
        H.m_get_type  = try_method(T_TD, "GetType", 1)
        -- 关键修正：NewNPC 有 10 个参数
        H.m_new_npc   = try_method(T_NPC, "NewNPC", 10)
        H.m_new_text  = try_method(T_Main, "NewText", 5) or try_method(T_Main, "NewText", 4)
        H.t_source    = T_Src
        H.m_source_ctor = T_Src and true or false
        local p_menu = patch.get_property(T_Main, "gameMenu")
        if p_menu then H.m_game_menu = patch.property_get_method(p_menu) end
        local p_wid = patch.get_property(T_Main, "worldID")
        if p_wid then H.m_world_id = patch.property_get_method(p_wid) end
        local T_NM = patch.get_type("Terraria", "NetMessage")
        if T_NM then H.m_send = try_method(T_NM, "SendData", 5) end
        if T_WI then
            H.f_inner = patch.get_field(T_WI, "inner")
            -- WorldItem.active / WorldItem.type 是【属性】不是字段，
            -- 用 get_field 取不到（会得到 nil，导致替换整段静默跳过）。
            local p_active = patch.get_property(T_WI, "active")
            if p_active then H.m_wi_active = patch.property_get_method(p_active) end
        end
        H.f_item_type  = patch.get_field(T_Item, "type")
        H.f_w          = patch.get_field(T_Item, "width")
        H.f_h          = patch.get_field(T_Item, "height")
        H.m_set_defaults = try_method(T_Item, "SetDefaults", 2) or try_method(T_Item, "SetDefaults", 1)
        if not H.m_set_defaults then log_note("no_setdefaults", "未找到 Item.SetDefaults，物品替换会退化为只改 type") end
        H.f_maxx      = patch.get_field(T_Main, "maxTilesX")
        H.f_items     = patch.get_field(T_Main, "item")
        if T_Item then H.f_stack = patch.get_field(T_Item, "stack") end

        if not H.m_kill_tile then error("WorldGen.KillTile 缺失") end
        if not H.m_get_type  then error("TileData.GetType 缺失") end
        if not H.m_new_npc   then error("NPC.NewNPC(10参) 缺失") end
        if not H.f_maxx      then error("Main.maxTilesX 缺失") end
        if not H.f_items     then error("Main.item 缺失") end
        if not H.f_stack     then error("Item.stack 缺失") end
        if not H.f_item_type then error("Item.type 缺失") end
        if not H.f_inner     then error("WorldItem.inner 缺失") end
        if T_ItemID then
            local okc, cnt = pcall(function()
                local f = patch.get_field(T_ItemID, "Count")
                return patch.get_field_value(f, nil, "int16")
            end)
            if okc and type(cnt) == "number" and cnt > 0 then H.item_count = cnt end
        end

        read_config()

        local okh, h = pcall(patch.install_hook, H.m_kill_tile,
            { prefix = on_kill_prefix, postfix = on_kill_postfix })
        if not okh or not h then error("KillTile 挂钩失败: " .. tostring(h)) end
        hooks[#hooks + 1] = h

        -- 首选：Player.Hooks.EnterWorld(int) —— 这是「进入世界」的准确事件。
        -- 它是嵌套类型里的静态方法，用 get_inner_type 取。
        local hooked_enter = false
        if T_Ply then
            local ok_in, T_Hooks = pcall(patch.get_inner_type, T_Ply, "Hooks")
            if ok_in and T_Hooks then
                local m_enter = try_method(T_Hooks, "EnterWorld", 1)
                if m_enter then
                    local function on_enter_world(inst, args)
                        drop_map = {}
                        in_world = true
                        log_note("enter_world", "进入世界（EnterWorld），掉落表已重掷")
                    end
                    local oke, he = pcall(patch.install_hook, m_enter, { prefix = on_enter_world })
                    if oke and he then
                        hooks[#hooks + 1] = he
                        hooked_enter = true
                        log_note("enter_hook_ok", "已挂上 Player.Hooks.EnterWorld")
                    end
                end
            end
        end
        if not hooked_enter then
            log_note("enter_hook_fail", "EnterWorld 挂钩不可用，退回 worldID 检测")
        end

        -- 兜底：DoUpdateInWorld 每帧都跑。
        -- 用它的 prefix 检测「从菜单进世界」的边沿，重置物品掉落表。
        local m_do_upd = try_method(T_Main, "DoUpdateInWorld", 0)
        if m_do_upd then
            local function on_do_update_prefix(inst)
                check_world_changed()
                return false
            end
            local ok2, h2 = pcall(patch.install_hook, m_do_upd, { prefix = on_do_update_prefix })
            if ok2 and h2 then hooks[#hooks + 1] = h2 end
        else
            log_note("do_upd_missing", "未找到 Main.DoUpdateInWorld，世界切换重置不可用")
        end

        pcall(mod.info, string.format(
            "[万物随机] v2.4.0 已加载 总开关=%s 物品=%s 城镇=%s Boss=%s 小怪=%s 动物=%s 概率=%d%%",
            tostring(config.mod_enabled), "常开", tostring(config.town_npc),
            tostring(config.boss), tostring(config.monster), tostring(config.animal),
            config.chance_percent))
    end)
    if not ok then pcall(mod.error, "[万物随机] 初始化失败: " .. tostring(err)) end
end

function mod.cleanup()
    for k = #hooks, 1, -1 do
        pcall(function() hooks[k]:remove() end)
        hooks[k] = nil
    end
end

todo_list = { "setup" }
