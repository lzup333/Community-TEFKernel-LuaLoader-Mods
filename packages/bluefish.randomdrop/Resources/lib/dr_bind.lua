-- dr_bind.lua
-- 反射绑定：NPC / Item / Lang 的字段与方法，随机掉落的生成与物品名。
-- 一切防御式：缺什么只关掉对应功能，不往钩子里抛错。
local U = require("dr_util")
local M = {}

local P = U.P
local C = {}
M.C = C

local ITEM_MAX_FALLBACK = 6195


function M.setup()
    C.NPCT    = U.try_type("Terraria", "NPC")
    C.ItemT   = U.try_type("Terraria", "Item")
    C.LangT   = U.try_type("Terraria", "Lang")
    if not (C.NPCT and C.ItemT) then
        U.log_error("[DR] 缺少 Terraria.NPC / Item")
        return false
    end

    -- NPC：type / netID / position / width / height
    C.f_type    = U.find_field(C.NPCT, "type")
    C.f_netID   = U.find_field(C.NPCT, "netID")
    C.f_pos     = U.find_field(C.NPCT, "position")
    C.f_width   = U.find_field(C.NPCT, "width")
    C.f_height  = U.find_field(C.NPCT, "height")
    C.f_active  = U.find_field(C.NPCT, "active")

    -- 掉落入口
    C.m_npcLoot = U.find_method(C.NPCT, "NPCLoot", 0)

    -- Item.NewItem(X, Y, Width, Height, Type, Stack, noBroadcast, pfix, ownership)
    C.m_newItem = U.find_method(C.ItemT, "NewItem", 9)
    if not C.m_newItem and type(P.get_method_by_names) == "function" then
        local ok, m = pcall(P.get_method_by_names, C.ItemT, "NewItem",
            { "X", "Y", "Width", "Height", "Type", "Stack", "noBroadcast", "pfix", "ownership" })
        if ok and m then C.m_newItem = m end
    end

    -- Main / Player：进世界判断与聊天栏播报
    C.MainT   = U.try_type("Terraria", "Main")
    C.PlayerT = U.try_type("Terraria", "Player")
    if C.MainT then
        C.m_gameMenu  = U.prop_getter(C.MainT, "gameMenu")
        C.f_gameMenu  = U.find_field(C.MainT, "gameMenu")
        C.m_newText5  = U.find_method(C.MainT, "NewText", 5)
        C.m_newText4  = U.find_method(C.MainT, "NewText", 4)
    end
    if C.PlayerT then
        C.m_playerUpdate = U.find_method(C.PlayerT, "Update", 1)
    end

    -- 不依赖名字的探测路径：Item.SetDefaults(id) 后读 type 是否被接受
    C.m_setDef = U.find_method(C.ItemT, "SetDefaults", 2)
        or U.find_method(C.ItemT, "SetDefaults", 1)
    if type(P.new_instance) == "function" then
        local okn, inst = pcall(P.new_instance, C.ItemT)
        if okn and inst then C.itemTmp = inst end
    end

    -- 物品名与上限
    if C.LangT then
        C.m_itemName      = U.find_method(C.LangT, "GetItemNameValue", 1)
        C.m_itemName2     = U.find_method(C.LangT, "GetItemName", 1)
        C.f_itemNameCache = U.find_field(C.LangT, "_itemNameCache")
    end
    -- LocalizedText.Value
    local LTT = U.try_type("Terraria.Localization", "LocalizedText")
    if LTT then
        C.m_ltValue = U.find_method(LTT, "get_Value", 0) or U.find_method(LTT, "GetValue", 0)
        C.f_ltValue = U.find_field(LTT, "_value") or U.find_field(LTT, "value")
    end

    local missing = {}
    local function need(n, v) if not v then missing[#missing + 1] = n end end
    need("NPC.type", C.f_type)
    need("NPC.position", C.f_pos)
    need("NPC.NPCLoot", C.m_npcLoot)
    need("Item.NewItem(9)", C.m_newItem)
    if #missing > 0 then
        U.log_error("[DR] 绑定缺失: " .. table.concat(missing, ","))
        return false
    end
    return true
end

-- ---------- 物品上限 ----------
local item_max = nil

function M.item_max()
    if item_max then return item_max end
    item_max = ITEM_MAX_FALLBACK

    -- ① 最准：Lang._itemNameCache 数组长度 - 1（1.4.5.8 原版 = 6195）
    if C.f_itemNameCache and type(P.array_length) == "function" then
        local ok, arr = pcall(P.get_field_value, C.f_itemNameCache, nil, "object")
        if ok and arr then
            local ok2, len = pcall(P.array_length, arr)
            if ok2 and type(len) == "number" and len > 1000 and len < 30000 then
                item_max = len - 1
                return item_max
            end
        end
    end

    -- ② 备选：ItemID.Count 常量
    local idt = U.try_type("Terraria.ID", "ItemID")
    if idt then
        local f = U.find_field(idt, "Count")
        if f then
            local v = U.gf_int(f, nil)
            if type(v) == "number" and v > 1000 and v < 30000 then
                item_max = v - 1
                return item_max
            end
        end
    end

    return item_max
end

-- 物品名：两路
--   ① Lang.GetItemNameValue(int) → string
--   ② Lang.GetItemName(int) → LocalizedText，再取 Value / _value
local function to_lua_string(h)
    if h == nil or h == false then return nil end
    if type(h) == "string" then
        return (h ~= "") and h or nil
    end
    if type(P.string_value) == "function" then
        local ok, s = pcall(P.string_value, h)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

local function localized_text(h)
    if h == nil or h == false then return nil end
    if C.m_ltValue then
        local ok, s = pcall(P.invoke, C.m_ltValue, h)
        if ok then
            local v = to_lua_string(s)
            if v then return v end
        end
    end
    if C.f_ltValue then
        local ok, s = pcall(P.get_field_value, C.f_ltValue, h, "string")
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

function M.item_name(itype)
    if type(itype) ~= "number" or itype <= 0 then return nil end
    -- ①
    if C.m_itemName then
        local ok, h = pcall(P.invoke, C.m_itemName, itype)
        if ok then
            local s = to_lua_string(h)
            if s then return s end
        end
    end
    -- ②
    if C.m_itemName2 then
        local ok, h = pcall(P.invoke, C.m_itemName2, itype)
        if ok then
            local s = localized_text(h)
            if s then return s end
        end
    end
    return nil
end

-- ---------- 世界判断 ----------
function M.world()
    if C.m_gameMenu then
        local v = U.call_bool(C.m_gameMenu, nil)
        if v ~= nil then return v == false end
    end
    if C.f_gameMenu then return not U.gf_bool(C.f_gameMenu, nil) end
    return false
end


-- ---------- 有效物品索引 ----------
-- 从 1 往上扫 Lang.GetItemNameValue：有名字的才算有效物品。
-- 这样模组新增的物品（ID 超过 6195）只要设了名字就会被收进来，
-- 同时天然跳过空 ID / 未定义 ID，不会掉空气。
local idx, idx_ready = nil, false

function M.build_index()
    if idx_ready then return idx end
    idx_ready = true
    if not C.m_itemName then
        U.log_warn("[DR] 没有 Lang.GetItemNameValue，跳过物品索引")
        return nil
    end
    local base = M.item_max()
    local limit = base + 800
    if limit > 12000 then limit = 12000 end
    local list = {}
    local empty_run = 0
    local t0 = os.clock()
    for id = 1, limit do
        local name = M.item_name(id)
        if name and name ~= "" then
            list[#list + 1] = id
            empty_run = 0
        else
            empty_run = empty_run + 1
            -- 原版区段之后连续 150 个空名字 → 认为到头了
            if empty_run >= 150 and id > 5000 then break end
        end
        if os.clock() - t0 > 4.0 then
            U.log_warn("[DR] 物品索引扫描超时，先用了已收集的部分")
            break
        end
    end
    local src = (C.m_itemName and "GetItemNameValue")
        or (C.m_itemName2 and "GetItemName")
        or "无"

    -- 名字路径几乎没结果 → 改用 SetDefaults 探测（更慢但不依赖语言表）
    if #list < 100 then
        local alt = M.build_index_by_defaults(limit)
        if alt and #alt > #list then
            list = alt
            src = src .. "+SetDefaults"
        end
    end

    idx = list
    return idx
end

-- 完全不用名字：逐个 SetDefaults(id)，type 被接受就算有效物品
function M.build_index_by_defaults(limit)
    local tmp = C.itemTmp
    if not (tmp and C.m_setDef) then
        U.log_warn("[DR] 无法用 SetDefaults 探测（缺实例或方法）")
        return nil
    end
    local list = {}
    local empty_run = 0
    local t0 = os.clock()
    for id = 1, limit do
        local ok = pcall(P.invoke, C.m_setDef, tmp, id)
        local t = ok and U.gf_int(C.f_type, tmp) or 0
        if t == id then
            list[#list + 1] = id
            empty_run = 0
        else
            empty_run = empty_run + 1
            if empty_run >= 200 and id > 5000 then break end
        end
        if os.clock() - t0 > 12.0 then
            U.log_warn("[DR] SetDefaults 探测超时，先用已收集部分")
            break
        end
    end
    return list
end

-- 从有效物品里随机取一个；索引没建好就返回 nil
function M.pick_pool()
    if idx and #idx > 0 then return idx[M.rand_int(1, #idx)] end
    return nil
end

-- ---------- NPC 信息 ----------
function M.npc_info(npc)
    if not npc then return nil end
    local x, y = U.read_vec2_field(C.f_pos, npc)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local w = U.gf_int(C.f_width, npc)
    local h = U.gf_int(C.f_height, npc)
    local t = U.gf_int(C.f_type, npc)
    if w <= 0 then w = 16 end
    if h <= 0 then h = 16 end
    local netid = t
    if C.f_netID then
        local n = U.gf_int(C.f_netID, npc)
        if type(n) == "number" and n >= 0 then netid = n end
    end
    return {
        x = x, y = y, w = w, h = h,
        type = t, netid = netid,
        cx = x + w / 2, cy = y + h / 2,
    }
end

-- ---------- 生成掉落 ----------
function M.spawn(x, y, w, h, itype, stack)
    if not (C.m_newItem and type(itype) == "number" and itype > 0) then return false end
    stack = math.floor(stack or 1)
    if stack < 1 then stack = 1 end
    local ok = pcall(P.invoke, C.m_newItem,
        math.floor(x), math.floor(y), math.floor(w), math.floor(h),
        math.floor(itype), stack, false, 0, 0)
    return ok
end

-- ---------- 随机数 ----------
function M.rand_int(lo, hi)
    lo = math.floor(lo or 1)
    hi = math.floor(hi or lo)
    if hi <= lo then return lo end
    return lo + math.floor(math.random() * (hi - lo + 1))
end

-- 百分比判定
function M.chance(pct)
    pct = tonumber(pct) or 0
    if pct >= 100 then return true end
    if pct <= 0 then return false end
    return math.random() * 100 < pct
end

return M