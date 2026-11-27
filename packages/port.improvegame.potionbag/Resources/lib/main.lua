--============================================================================
-- 药水袋（纯 GUI 面板版 v1.3.2 + 角色互通修复）
-- 移植自 ImproveGame 1.4.4 PotionBag.cs，适配 LuaLoader / 泰拉瑞亚 1.4.6（PC+PE 源码核对）
--   1.4.6 适配点：Item 已移除 width/height（本 Mod 未用，不受影响）；
--   反射目标 Item/Player/Main/Lang/BuffID.Sets 逐个对照 1.4.6 源码核实仍在；
--   Player.inventory=59、maxBuffs=44、AddBuff(3参)/ClearBuff 签名与 1.4.5.8 一致。
--
-- 纯面板设计：无自定义物品/配方/贴图。
--   「装填」= 扫背包 0-58 槽，把 buffType>0 && consumable 的药水移进虚拟容器
--   「取出」= 把容器里全部药水放回背包
-- 虚拟容器 bag.entries = {{type,stack,name}}，mod.write_file 存 bag.dat
-- 面板进世界后默认 show（窗口常驻，可拖动/最小化）
--============================================================================

local P = mod.patch

-- 全局共享状态（必须是全局：save_thresh/load_thresh 定义在容器逻辑之前，
-- 早先版本用 local S 声明两次导致这两函数读到 nil S 而每帧抛错）
S = { open = true, pos_set = false, setup_done = false, threshold = 10, page = 1, take_amt = 0 }

------------------------------------------------------------------------------
--- THEME 白金主题（v1.14.1 视觉优化，浅底）
--- 只喂给 g.set_style：内核按【常量指针】把这些色映射到默认面板/标题/边框/
-- （白金=浅底：text 键必须是深墨，否则内核默认按钮/标题文字白底白字）
--- 按钮/文字（gui_window.inc:99-108 themed_color，draw_mod_gui @206 设
--- g_style_window 后才画默认面板、on_gui 在 @310 执行）→ 我们自己的 rect/
--- text_at 色表是字面量、不受影响，保持各画各的。
--- 注意 set_style 每键都 luaL_checktype(TABLE)，THEME 必须是纯色表
--- {r,g,b,a}，不能塞子表（如 border 放 {c=…} 会整帧抛错被 pcall 吞掉）。
local THEME = {
    panel  = {236, 233, 225, 247}, -- 白金底板（暖白）
    title  = {212, 202, 178, 255}, -- 香槟金标题条
    button = {227, 223, 211, 255}, -- 按钮常态（米白）
    hover  = {240, 236, 226, 255}, -- 按钮悬停（更亮）
    active = {204, 195, 174, 255}, -- 按钮按下（压暗）
    border = {166, 156, 136, 255}, -- 描边（浅金灰）
    text   = {44, 41, 36, 255},    -- 文字（深墨，浅底可读）
}
local GOLD  = {176, 132, 32, 255}  -- 深金（浅底可读）
local GREEN = {38, 128, 64, 255}   -- 深绿（浅底可读）
local GRAY  = {118, 114, 104, 255} -- 暖灰（浅底可读）

------------------------------------------------------------------------------
-- 工具
------------------------------------------------------------------------------
local function num(v, d)
    local n = tonumber(v)
    return n and n or (d or 0)
end

local function valid(h)
    if h == nil then return false end
    local ty = type(h)
    if ty == "number" or ty == "string" or ty == "boolean" then return true end
    -- ★关键：IL2CPP 反射句柄（get_type/get_field/get_method 返回）是 userdata（指针），
    --   不是 Lua table。早先 `if ty ~= "table" then return false end` 把所有 userdata
    --   句柄一律判 false → try_type/try_field 全返回 nil → 所有句柄 false → 扫不到药水。
    if ty == "userdata" then
        if P.is_valid then
            local ok, r = pcall(P.is_valid, h)
            if ok then return r == true end
        end
        return true   -- 内核无 is_valid 时，非 nil userdata 视为有效句柄
    end
    if ty ~= "table" then return false end
    if rawget(h, "__invalid") then return false end
    if P.is_valid then
        local ok, r = pcall(P.is_valid, h)
        if ok then return r == true end
    end
    return true
end

local function try_type(ns, cls)
    if not P.get_type then return nil end
    local ok, t = pcall(P.get_type, ns, cls)
    if ok and valid(t) then return t end
    return nil
end

local function try_field(t, name)
    if not t or not P.get_field then return nil end
    local ok, f = pcall(P.get_field, t, name)
    if ok and valid(f) then return f end
    return nil
end

local function try_method(t, name, argc)
    if not t or not P.get_method then return nil end
    local ok, m
    if argc then ok, m = pcall(P.get_method, t, name, argc)
    else         ok, m = pcall(P.get_method, t, name) end
    if ok and valid(m) then return m end
    return nil
end

local function gf(f, inst, ty)
    if not f then return nil end
    local ok, v
    if ty then ok, v = pcall(P.get_field_value, f, inst, ty)
    else       ok, v = pcall(P.get_field_value, f, inst) end
    if ok then return v end
    return nil
end

local function gb(f, inst)
    local v = gf(f, inst, "bool")
    if v == nil then return nil end
    return v == true or v == 1
end

local function gnum(f, inst)
    return math.floor(num(gf(f, inst, "int32"), -1))
end

-- 移植 SpaceWand blk_core.lua：IL2CPP 反射读/写 int 走【原始字节】，
-- 比 get_field_value(f,inst,"int32") 可靠（后者在此内核读 buffType/type 可能失败）。
-- 先 get_field_raw 拿字节 → string.unpack("<i"..n) 小端解；失败才回退 get_field_value。
local function gf_int(f, inst)
    if not f then return nil end
    if P.get_field_raw then
        local ok, raw = pcall(P.get_field_raw, f, inst)
        if ok and type(raw) == "string" and #raw > 0 then
            local ok2, v = pcall(string.unpack, "<i" .. #raw, raw)
            if ok2 then return v end
        end
    end
    local ok, v = pcall(P.get_field_value, f, inst, "int32")
    if ok then return v end
    return nil
end

-- 写 int：取字段字节宽 → string.pack("<i"..n,v) → set_field_raw；失败回退 set_field_value
local function sf_int(f, inst, v)
    if not f then return end
    if P.set_field_raw then
        local ok, raw = pcall(P.get_field_raw, f, inst)
        if ok and type(raw) == "string" and #raw > 0 then
            local okp, packed = pcall(string.pack, "<i" .. #raw, v)
            if okp then
                local oks = pcall(P.set_field_raw, f, inst, packed)
                if oks then return end
            end
        end
    end
    pcall(P.set_field_value, f, inst, v, "int32")
end

-- 写 bool：与 sf_int 同思路——raw 按字段字节宽 pack（1 字节 bool → <i1），
-- 失败回退 set_field_value(..., "bool")。v1.12.0：取出写回/清槽时纠正 consumable。
local function sf_bool(f, inst, v)
    if not f then return end
    local iv = (v and 1 or 0)
    if P.set_field_raw then
        local ok, raw = pcall(P.get_field_raw, f, inst)
        if ok and type(raw) == "string" and #raw > 0 then
            local okp, packed = pcall(string.pack, "<i" .. #raw, iv)
            if okp then
                local oks = pcall(P.set_field_raw, f, inst, packed)
                if oks then return end
            end
        end
    end
    pcall(P.set_field_value, f, inst, v and true or false, "bool")
end

local warn_seen = {}
local function warn_once(key, msg)
    if warn_seen[key] then return end
    warn_seen[key] = true
    local w = (type(mod) == "table" and type(mod.warn) == "function") and mod.warn or print
    w(msg)
end

local function log(msg)
    -- v1.5：日志改走 mod.warn（WARNING 级），确保过 logger 级别阈值。
    -- 注意（关键）：内核 mod.* 日志 tag=mod_id（port.improvegame.potionbag），
    -- 不是 "LuaLoader"。logcat 需按此 tag 过滤或 grep "药水袋" 才能看到，
    -- 按 tag=LuaLoader 过滤会漏掉所有 mod 自身日志（那是引擎 tag）。
    local l = (type(mod) == "table" and type(mod.warn) == "function") and mod.warn or print
    l(msg)
end

local function save_txt(name, s)
    if mod.write_file then pcall(mod.write_file, name, s) end
end

local function load_txt(name)
    if mod.read_file then
        local ok, r = pcall(mod.read_file, name)
        if ok and type(r) == "string" then return r end
    end
    return nil
end

-- 档位持久化（bag.cfg）
function save_thresh()
    save_txt("bag.cfg", string.format("%d|%d", S.threshold, S.take_amt or 0))
end

local function load_thresh()
    local s = load_txt("bag.cfg") or ""
    local th, amt = s:match("(%d+)|(%d+)")
    if not th then th = s:match("%d+") end          -- 兼容旧格式（纯数字）
    local n = tonumber(th)
    if n and n >= 1 and n <= 30 then S.threshold = math.floor(n) end
    local a = tonumber(amt)
    if a and a >= 0 then S.take_amt = math.floor(a) end
end

------------------------------------------------------------------------------
-- 反射绑定：只绑定面板所需原版类型（Item / Player / Main）
------------------------------------------------------------------------------
local C = {}

local function bind_reflection()
    -- 探针：打印 get_type 原始返回的 type()，确认句柄是 userdata（valid 曾把它判 false 的根因）
    if P.get_type then
        local ok, t = pcall(P.get_type, "Terraria", "Item")
        log(string.format("[药水袋·bind] get_type(Terraria,Item) ok=%s type=%s", tostring(ok), type(t)))
    end
    C.ItemT = try_type("Terraria", "Item")
    C.f_type      = try_field(C.ItemT, "type")
    C.f_stack     = try_field(C.ItemT, "stack")
    C.f_buffType  = try_field(C.ItemT, "buffType")
    C.f_consumable = try_field(C.ItemT, "consumable")
    C.f_maxStack   = try_field(C.ItemT, "maxStack")
    C.f_damage     = try_field(C.ItemT, "damage")   -- ★v1.14.7 召唤杖拦截：武器类 damage>0
    -- ★v1.14.9：PE/PC 真实签名 SetDefaults(int Type, ItemVariant variant = null) 是 2 参，
    --   旧代码按 1 参找 → 永远找不到（真机诊断 m_setDefaults=false），自修/探针/体检全死。
    C.m_setDefaults = try_method(C.ItemT, "SetDefaults", 2)
    C.setDefaults_argc = 2
    if not C.m_setDefaults then
        C.m_setDefaults = try_method(C.ItemT, "SetDefaults", 1)
        C.setDefaults_argc = 1
    end
    log(string.format("[药水袋·bind] SetDefaults=%s argc=%s",
        tostring(C.m_setDefaults ~= nil), tostring(C.setDefaults_argc)))
    if P.get_property and C.ItemT then
        local ok, p = pcall(P.get_property, C.ItemT, "name")
        if ok and valid(p) then C.p_name = p end
        -- 1.4.6 适配：Item 显示名属性是 Name（PC Item.cs:331 / PE dump 均为 Name），
        -- 小写 name 拿不到时回退大写，避免 Lang 路径失效时物品名退化成 "物品#N"
        if not C.p_name then
            local ok2, p2 = pcall(P.get_property, C.ItemT, "Name")
            if ok2 and valid(p2) then C.p_name = p2 end
        end
    end
    if not C.p_name then C.f_name = try_field(C.ItemT, "name") end
    if not C.p_name and not C.f_name then C.f_name = try_field(C.ItemT, "Name") end

    C.PlayerT = try_type("Terraria", "Player")
    C.f_inventory = try_field(C.PlayerT, "inventory")

    C.MainT = try_type("Terraria", "Main")
    C.f_localPlayer = try_field(C.MainT, "LocalPlayer")
    -- SpaceWand 玩家获取三件套（PE 上 Main.LocalPlayer 是属性非字段，直接读拿不到）：
    C.f_playerArr   = try_field(C.MainT, "player")             -- Main.player 静态数组
    C.f_myPlayer    = try_field(C.MainT, "myPlayer")           -- 当前玩家索引
    C.m_getMyPlayer = try_method(C.MainT, "get_myPlayer", 0)   -- PE 上 myPlayer 是属性，走访问器
    -- v1.14.0 任务2：进/退世界判定（只解析句柄不执行 → bind 阶段安全；调用全在 on_gui+pcall）
    --   Main.gameMenu：true=主菜单。PE 上是属性 → 走 get_gameMenu 访问器（同 get_myPlayer 模式）；
    --   有的版本是静态字段 → try_field 兜底。Main.worldName：进世界后非空（第二信号）。
    C.m_gameMenu  = try_method(C.MainT, "get_gameMenu", 0)
    C.f_gameMenu  = try_field(C.MainT, "gameMenu")
    C.f_worldName = try_field(C.MainT, "worldName")
    log(string.format("[药水袋·bind] 世界判定: gameMenu(getter)=%s gameMenu(field)=%s worldName=%s",
        tostring(C.m_gameMenu ~= nil), tostring(C.f_gameMenu ~= nil), tostring(C.f_worldName ~= nil)))
    -- AddBuff 实际签名 AddBuff(int buffType, int buffTime, bool quiet=false, bool visible=true)，
    -- IL 层可能是 2 参或 4 参重载；逐个试，存下命中的参数个数供 invoke 用。
    C.addBuff_argc = 2
    C.m_addBuff = try_method(C.PlayerT, "AddBuff", 2)
    if not C.m_addBuff then C.m_addBuff = try_method(C.PlayerT, "AddBuff", 4); C.addBuff_argc = 4 end
    if not C.m_addBuff then C.m_addBuff = try_method(C.PlayerT, "AddBuff", 3); C.addBuff_argc = 3 end
    log(string.format("[药水袋·bind] AddBuff=%s argc=%s", tostring(C.m_addBuff ~= nil), tostring(C.addBuff_argc)))
    -- 需求1：Lang.GetItemNameValue(int) 静态方法（Lang.cs:220），返回本地化物品名（含 mod 物品）
    C.LangT = try_type("Terraria", "Lang")
    C.m_getItemNameValue = try_method(C.LangT, "GetItemNameValue", 1)
    log(string.format("[药水袋·bind] Lang=%s GetItemNameValue=%s",
        tostring(C.LangT ~= nil), tostring(C.m_getItemNameValue ~= nil)))
    -- ★需求6：Player.ClearBuff(int buffType) 按类型立即消除（Player.cs:102384）
    C.m_clearBuff = try_method(C.PlayerT, "ClearBuff", 1)
    log(string.format("[药水袋·bind] ClearBuff=%s", tostring(C.m_clearBuff ~= nil)))
    -- ★需求1(永久buff)：纯数据写，不 hook 任何方法（零闪退风险）：
    --   ① Main.buffNoTimeDisplay[bt]=true → TryGetBuffTime 返回 false → DrawBuffIcon 不画读秒
    --      （Main.cs:44079 `!buffNoTimeDisplay[num]` 是显示门；游戏对 19/27/28 等 buff 本就这么干）
    --   ② BuffID.Sets.TimeLeftDoesNotDecrease[bt]=true → UpdateBuffs 不 buffTime--（Player.cs:9958）
    --   ③ 兜底：直接 array_set 写玩家 buffTime[槽]=大值（绕开每帧 AddBuff 刷新不可靠的问题）
    C.f_pBuffType    = try_field(C.PlayerT, "buffType")            -- Player.buffType int[]
    C.f_pBuffTime    = try_field(C.PlayerT, "buffTime")            -- Player.buffTime int[]
    C.f_noTimeDisplay = try_field(C.MainT, "buffNoTimeDisplay")    -- Main.buffNoTimeDisplay static bool[]
    -- BuffID.Sets 是嵌套类：Android/PE 上不能 get_type("Terraria.ID","BuffID.Sets")，必须外层→get_inner_type
    local buffIDT = try_type("Terraria.ID", "BuffID")
    local setsT = nil
    if buffIDT and P.get_inner_type then
        local ok, s = pcall(P.get_inner_type, buffIDT, "Sets")
        if ok then setsT = s end
    end
    C.f_noDecr = try_field(setsT, "TimeLeftDoesNotDecrease")
    if not C.f_noDecr then
        -- 备选：个别内核支持直接按全名取嵌套类
        local ok, s = pcall(P.get_type, "Terraria.ID", "BuffID.Sets")
        if ok and valid(s) then C.f_noDecr = try_field(s, "TimeLeftDoesNotDecrease") end
    end
    log(string.format("[药水袋·bind] 永久buff: pBuffType=%s pBuffTime=%s buffNoTimeDisplay=%s TimeLeftDoesNotDecrease=%s",
        tostring(C.f_pBuffType ~= nil), tostring(C.f_pBuffTime ~= nil),
        tostring(C.f_noTimeDisplay ~= nil), tostring(C.f_noDecr ~= nil)))
    local n = 0
    for _, v in pairs(C) do if v ~= nil then n = n + 1 end end
    log(string.format("[药水袋·bind] 绑定完成：C 中非 nil 句柄数=%d | ItemT=%s f_type=%s f_buffType=%s f_inventory=%s f_playerArr=%s f_myPlayer=%s",
        n, tostring(C.ItemT ~= nil), tostring(C.f_type ~= nil), tostring(C.f_buffType ~= nil),
        tostring(C.f_inventory ~= nil), tostring(C.f_playerArr ~= nil), tostring(C.f_myPlayer ~= nil)))
end

local function player_by_index(idx)
    if not C.f_playerArr or type(idx) ~= "number" or idx < 0 then return nil end
    local ok, arr = pcall(P.get_field_value, C.f_playerArr, nil, "object")
    if not ok or not valid(arr) then return nil end
    local ok2, pl = pcall(P.array_at, arr, math.floor(idx))
    if ok2 and valid(pl) then return pl end
    return nil
end

local lp_dbg = false   -- 由 collect_all 临时打开，让 local_player 打印每步尝试结果

local function local_player()
    -- 移植 SpaceWand blk_core.lua:255-264：PE/IL2CPP 上 Main.myPlayer 是【属性】，
    -- 必须先走 get_myPlayer 访问器拿索引，再从 Main.player[idx] 取玩家实例；
    -- 直接读 Main.LocalPlayer 静态字段会拿到无效对象 → 后续读 inventory 得到错数组 → 扫 0 瓶。
    if C.m_getMyPlayer then
        local ok, v = pcall(P.invoke, C.m_getMyPlayer)
        if lp_dbg then log(string.format("[药水袋·lp] getMyPlayer ok=%s v=%s", tostring(ok), tostring(v))) end
        if ok and type(v) == "number" and v >= 0 then
            local pl = player_by_index(v)
            if lp_dbg then log(string.format("[药水袋·lp] player_by_index(%s) -> %s", tostring(v), tostring(pl ~= nil))) end
            if pl then return pl end
        end
    elseif lp_dbg then log("[药水袋·lp] m_getMyPlayer=nil") end
    local idx = gf_int(C.f_myPlayer, nil)
    if lp_dbg then log(string.format("[药水袋·lp] f_myPlayer idx=%s", tostring(idx))) end
    if type(idx) == "number" and idx >= 0 then
        local pl = player_by_index(idx)
        if lp_dbg then log(string.format("[药水袋·lp] player_by_index(%s) -> %s", tostring(idx), tostring(pl ~= nil))) end
        if pl then return pl end
    end
    -- 最后兜底：部分内核 Main.LocalPlayer 可直接读
    if C.f_localPlayer then
        local pl = gf(C.f_localPlayer, nil, "object")
        if lp_dbg then log(string.format("[药水袋·lp] f_localPlayer -> valid=%s", tostring(valid(pl)))) end
        if valid(pl) then return pl end
    elseif lp_dbg then log("[药水袋·lp] f_localPlayer=nil") end
    return nil
end

local function inventory_of(pl)
    if not C.f_inventory or not valid(pl) then return nil, 0 end
    local inv = gf(C.f_inventory, pl, "object")
    if not valid(inv) then return nil, 0 end
    local len = 0
    if P.array_length then
        local ok, n = pcall(P.array_length, inv)
        if ok then len = math.floor(num(n, 0)) end
    end
    return inv, len
end

local function arr_at(arr, i)
    if not arr or not P.array_at then return nil end
    local ok, v = pcall(P.array_at, arr, i)
    if ok and valid(v) then return v end
    return nil
end

-- 读物品名：Item.name 属性/字段；失败建临时实例 SetDefaults(type) 读原版名
-- 把反射读到的"字符串"归一成 Lua string：PE/IL2CPP 上字符串常是 userdata 句柄，
-- 要经 P.string_value 转换；直接是 string 就用。读不出返回 nil。
local function to_str(v)
    if type(v) == "string" then return (v ~= "" and v or nil) end
    if v ~= nil and P.string_value then
        local ok, s = pcall(P.string_value, v)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

-- 方案D：常见药水 ID→中文名 内置映射（PE 上反射读 Item.name 常失败，兜底查表）
local NAME_MAP = {
    [28]   = "次级治疗药水", [189]  = "魔力药水",   [295]  = "次级恢复药水",
    [296]  = "探矿药水",     [297]  = "隐身药水",   [298]  = "发光药水",
    [299]  = "夜枭药水",     [300]  = "战斗药水",   [301]  = "荆棘药水",
    [302]  = "水行药水",     [303]  = "黑曜石皮肤药水", [304] = "再生药水",
    [305]  = "迅捷药水",     [306]  = "鳃药水",     [307]  = "铁皮药水",
    [308]  = "魔力再生药水", [309]  = "魔法力量药水", [310] = "落羽药水",
    [311]  = "狩猎药水",     [312]  = "羽落药水",   [313]  = "暗影药水",
    [315]  = "危险摆锤药水", [316]  = "拾心药水",   [317]  = "死灵药水",
    [318]  = "泰拉闪耀药水", [319]  = "危险追踪药水", [320] = "危险粉红凝胶药水",
    [2322] = "强效治疗药水", [2323] = "强效魔力药水", [2324] = "强效恢复药水",
    [2325] = "强效魔力再生药水", [2326] = "强效魔法力量药水",
    [2327] = "强效再生药水", [2328] = "召唤药水",   [2329] = "强效铁皮药水",
    [2330] = "强效迅捷药水", [2331] = "强效羽落药水", [2335] = "强效魔力再生药水",
}

local function item_name(it, t)
    -- 需求1：优先 Lang.GetItemNameValue(type)——本地化名，原版+mod 物品全覆盖（Lang.cs:220）
    if C.m_getItemNameValue then
        local ok, v = pcall(P.invoke, C.m_getItemNameValue, t)
        if ok then
            local s = to_str(v)
            -- 过滤未翻译键/占位（"ItemName.xxx"、空、"???"）
            if s and not s:match("^ItemName%.") and s ~= "???" then return s end
        end
    end
    if it and C.p_name then
        local ok, n = pcall(P.get_property, C.p_name, it)
        if ok then local s = to_str(n); if s then return s end end
    end
    if it and C.f_name then
        local s = to_str(gf(C.f_name, it, "object"))
        if s then return s end
    end
    if C.ItemT and C.m_setDefaults then
        local ok, tmp = pcall(P.new_instance, C.ItemT)
        if ok and valid(tmp) then
            pcall(P.invoke, C.m_setDefaults, tmp, t)
            if C.p_name then
                local ok2, n2 = pcall(P.get_property, C.p_name, tmp)
                if ok2 then local s = to_str(n2); if s then return s end end
            end
            if C.f_name then
                local s = to_str(gf(C.f_name, tmp, "object"))
                if s then return s end
            end
        end
    end
    -- 反射三条路径都失败 → 查内置映射表（方案D）
    if NAME_MAP[t] then return NAME_MAP[t] end
    return ("物品#" .. tostring(t))
end

------------------------------------------------------------------------------
-- 虚拟容器（移植 ImproveGame ItemIntoContainer / MeetEntryCriteria）
------------------------------------------------------------------------------
local CFG = {
    BAG_FILE    = "bag.dat",
    MAX_ENTRIES = 200,     -- 移植 ItemIntoContainer 容量上限
    INV_SLOTS   = 59,      -- 玩家背包 0-58 槽（SpaceWand INV_SCAN_MAX=59 全扫）
    STACK_MAX   = 9999,    -- 每格最大堆叠（用户实测本药水 maxStack=9999；原 99 导致只取 99 就 room=0 break）
    THRESH_FILE = "bag.cfg",   -- 档位存档
    WORMHOLE    = { [2997] = true },   -- ★需求4：虫洞药水（无常规 buff 也能入袋）
}

local bag = { entries = {} }     -- {{type,stack,name}}

-- 入袋判定（移植 MeetEntryCriteria：buffType>0 且 consumable）
-- ★v1.14.9 类型级探针基础设施 --------------------------------------------
-- 真机根因：槽位 consumable 不可信（旧版 take_all 强写过 true，宠物也被写成 true → 直通放行）；
-- 且旧绑定按 1 参找 SetDefaults 找不到（真实签名 2 参）→ 一切自修/探针都是死的。
local PROBE_CACHE = {}
local PROBE_DEAD = false
-- 槽位级 SetDefaults：2 参/1 参两种 invoke 都试（pcall 兜底）
local function do_set_defaults(inst, ty)
    if not C.m_setDefaults or not inst or not ty or ty <= 0 then return false end
    if pcall(P.invoke, C.m_setDefaults, inst, ty, nil) then return true end
    if pcall(P.invoke, C.m_setDefaults, inst, ty) then return true end
    return false
end
-- 槽位修复：SetDefaults 方法体里有 stack=0，调用前后保护 stack 不被清
local function repair_slot(it, ty)
    local st0 = num(gf_int(C.f_stack, it), 0)
    local ok = do_set_defaults(it, ty)
    if ok and st0 > 0 then
        local st1 = num(gf_int(C.f_stack, it), 0)
        if st1 ~= st0 then sf_int(C.f_stack, it, st0) end
    end
    return ok
end
-- 类型级探针：全新实例跑 SetDefaults，读"该物品类型"的真实 consumable。
--   药水/食物/药剂（含 DefaultToFood/DefaultToBuff 助手设置的）= true → 收；
--   宠物/照明宠物/召唤杖等非消耗品 = false → 拦。按类型缓存。
local function probe_type_consumable(ty)
    if not C.ItemT or not C.m_setDefaults then return nil end
    local ok, tmp = pcall(P.new_instance, C.ItemT)
    if not ok or not valid(tmp) then return nil end
    if not do_set_defaults(tmp, ty) then return nil end
    local c = gb(C.f_consumable, tmp)
    if c == nil then return nil end
    return c
end
local function is_potion(it, slot)
    if not it or not valid(it) then
        if slot then log(string.format("[药水袋·装填] slot=%d 被拦：句柄无效(arr_at/valid)", slot)) end
        return false
    end
    local bt = num(gf_int(C.f_buffType, it), 0)
    -- ★需求4：虫洞药水等无 buff 特例白名单（虫洞药水 type=2997，不带常规 buff）
    local ty = num(gf_int(C.f_type, it), 0)
    if CFG.WORMHOLE[ty] then return true end
    if bt <= 0 then return false end          -- 核心信号：带 buff 的物品才是药水
    -- ★v1.14.7 召唤杖/武器快路径：杖类 damage>0（药水/食物/宠物=0/-1）→ 必拦
    local dmg_r = gf_int(C.f_damage, it)
    if dmg_r and dmg_r > 0 then
        log(string.format("[药水袋·装填 type=%d] slot=%s 被拦：damage=%d（武器/召唤杖类，非药水）",
            ty, tostring(slot), dmg_r))
        return false
    end
    local ms_r = gf_int(C.f_maxStack, it)
    if ms_r and ms_r <= 1 then
        log(string.format("[药水袋·装填 type=%d] slot=%s 被拦：maxStack=%d 不可堆叠（非药水）",
            ty, tostring(slot), ms_r))
        return false
    end
    -- ★v1.14.9 主修复：类型级探针。槽位 consumable 不可信（旧版取出强写过 true，
    --   宠物槽也是 true → 旧逻辑直通放行）。用全新实例 SetDefaults 得到类型真实 consumable。
    local p = PROBE_CACHE[ty]
    if p == nil then
        p = probe_type_consumable(ty)
        if p ~= nil then
            PROBE_CACHE[ty] = p
        elseif not PROBE_DEAD then
            PROBE_DEAD = true
            log("[药水袋·装填] 类型探针不可用（new_instance/SetDefaults 失败）→ 退回槽位判定（宠物可能仍会误收）")
        end
    end
    if p == false then
        -- 宠物/照明宠物/非消耗品：必拦，并顺手把槽位字段修回原版（旧版强写坏的）
        if ty > 0 then repair_slot(it, ty) end
        log(string.format("[药水袋·装填 type=%d] slot=%s 被拦：类型探针 consumable=false（宠物/照明宠物/非消耗品）",
            ty, tostring(slot)))
        return false
    end
    if p == true then
        -- 药水/食物/药剂：放行；槽位字段脏则纠正（保证游戏里可正常使用）
        local sc = gb(C.f_consumable, it)
        if sc ~= true then sf_bool(C.f_consumable, it, true) end
        log(string.format("[药水袋·装填 type=%d] slot=%s 类型探针 consumable=true → 放行（槽位 consumable=%s）",
            ty, tostring(slot), tostring(sc)))
        return true
    end
    -- 探针不可用 → v1.12 槽位老路（自修 + 可堆叠兜底），保证不比旧版差
    local cons = gb(C.f_consumable, it)
    if cons ~= true then
        if ty > 0 then repair_slot(it, ty) end
        cons = gb(C.f_consumable, it)
        if cons ~= true then
            local ms = num(gf_int(C.f_maxStack, it), 0)
            local st = num(gf_int(C.f_stack, it), 0)
            if ms > 1 or st > 1 then
                log(string.format("[药水袋·装填 type=%d] slot=%s 探针不可用，按可堆叠兜底放行 maxStack=%d stack=%d 并纠正字段",
                    ty, tostring(slot), ms, st))
                sf_bool(C.f_consumable, it, true)
                return true
            end
            log(string.format("[药水袋·装填 type=%d] slot=%s 被拦：consumable=false 且不可堆叠 maxStack=%d stack=%d（疑宠物/坐骑类）",
                ty, tostring(slot), ms, st))
            return false
        end
        log(string.format("[药水袋·装填 type=%d] slot=%s 槽位自修成功 consumable=%s → 放行",
            ty, tostring(slot), tostring(cons)))
    end
    return true
end

-- 合并进容器（同类先合并，未满则追加，上限 200）
local function store_into(t, s, nm, bt)
    if t <= 0 or s <= 0 then return 0 end
    for _, e in ipairs(bag.entries) do
        if e.type == t then
            e.stack = e.stack + s
            if bt and bt > 0 then e.buffType = bt end
            return s
        end
    end
    if #bag.entries < CFG.MAX_ENTRIES then
        bag.entries[#bag.entries + 1] = { type = t, stack = s, name = nm, buffType = bt or 0 }
        return s
    end
    return 0
end

-- ★需求5：按玩家角色分档存档，文件名带玩家名，切角色不串档
local function player_file()
    -- ★v1.9.2 防闪退：setup/init 阶段 Main.player 未就绪，若此刻解析玩家名会 native
    -- invoke(get_myPlayer + array_at) 抛 IL2CPP 异常逃逸(pcall 挡不住 native)→ SIGABRT。
    -- world 就绪前一律用全局档 bag.dat；首帧 on_gui 置 world_ready 后才解析玩家档。
    if not S.world_ready then return CFG.BAG_FILE end
    local nm = nil
    local pl = local_player()
    if pl and C.PlayerT then
        if not C.f_plName and P.get_property then
            local okp, pp = pcall(P.get_property, C.PlayerT, "name")
            if okp and valid(pp) then C.f_plName = pp end
        end
        if not C.f_plName then C.f_plName = try_field(C.PlayerT, "name") end
        if C.f_plName then
            local okv, vv = pcall(gf, C.f_plName, pl, "object")
            if okv then nm = to_str(vv) end
        end
    end
    if nm and nm ~= "" then
        return "bag_" .. nm:gsub("[^%w_]", "_") .. ".dat"
    end
    return CFG.BAG_FILE
end

local function save_bag_now(file_override)
    -- ★v1.14.6 写前必须知道写进哪个档（诊断静默覆盖）
    -- ★v1.3.1 支持显式指定文件名，切档/卸载时用，避免 player_file() 解析失败写错档
    local pf = file_override
    if not pf then
        local okp, p = pcall(player_file)
        if okp and p then pf = p else pf = CFG.BAG_FILE end
    end
    local lines = {}
    for _, e in ipairs(bag.entries) do
        local nm = (e.name or ""):gsub("[|\r\n]", " ")
        lines[#lines + 1] = string.format("%d|%d|%d|%d|%s", e.type, e.stack, e.buffType or 0,
            (e.buff_on == false) and 0 or 1, nm)
    end
    local txt = table.concat(lines, "\n")
    save_txt(pf, txt)
    log(string.format("[药水袋·存档] 保存 -> %s（%d 条 / %dB）", pf, #bag.entries, #txt))
end

-- ★v1.14.7 存档体检：判断条目是否"像药水"（旧版存档可能遗留召唤杖/宠物等）。
-- 只诊断不删——条目是用户物品的唯一副本，删了就没了；用户点「取出」放回背包。
local function entry_looks_potion(ty)
    if CFG.WORMHOLE[ty] then return true end
    if not C.ItemT or not C.m_setDefaults then return true end   -- 绑定失败不误杀
    local ok, tmp = pcall(P.new_instance, C.ItemT)
    if not ok or not valid(tmp) then return true end
    local oki = do_set_defaults(tmp, ty)
    if not oki then return true end              -- SetDefaults 调不动 → 不误杀
    local dmg = num(gf_int(C.f_damage, tmp), 0)
    local ms  = num(gf_int(C.f_maxStack, tmp), 0)
    if dmg > 0 then return false end
    if ms <= 1 then return false end
    -- ★v1.14.8：干净跑完 SetDefaults 仍 consumable=false → 宠物/照明宠物/非消耗品
    if gb(C.f_consumable, tmp) == false then return false end
    return true
end


local function load_bag(file_override)
    local pf = file_override
    if not pf then
        local okp, p = pcall(player_file)
        pf = (okp and p) or CFG.BAG_FILE
    end
    local s = load_txt(pf)
    -- ★v1.3.1 角色互通修复：空档必须清空，否则会继承上一个角色的条目
    if not s or s == "" then bag.entries = {}; return end
    bag.entries = {}
    bag.entries = {}
    for line in s:gmatch("[^\r\n]+") do
        local t, st, bt, bon, nm = line:match("^(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
        if not t then                      -- 兼容旧 4 字段格式 type|stack|buffType|name
            t, st, bt, nm = line:match("^(%d+)|(%d+)|(%d+)|(.*)$")
            if t then bon = 1 end
        end
        if not t then                      -- 兼容旧 3 字段格式 type|stack|name
            t, st, nm = line:match("^(%d+)|(%d+)|(.*)$")
            bt = 0; bon = 1
        end
        if t and st and #bag.entries < CFG.MAX_ENTRIES then
            local bo = tonumber(bon or "1")
            bag.entries[#bag.entries + 1] =
                { type = tonumber(t), stack = tonumber(st), buffType = tonumber(bt) or 0,
                  buff_on = (bo == 1), name = nm }
        end
    end
    -- ★v1.14.7 载入体检：只报不删（条目是用户物品的唯一副本）
    local bad = {}
    for _, e in ipairs(bag.entries) do
        if not entry_looks_potion(e.type) then bad[#bad + 1] = e.type end
    end
    if #bad > 0 then
        local show = {}
        for k = 1, math.min(#bad, 8) do show[#show + 1] = tostring(bad[k]) end
        log(string.format("[药水袋·存档] 载入 %d 条，其中 %d 条疑似非药水（type=%s%s），点「取出」放回背包",
            #bag.entries, #bad, table.concat(show, ","), (#bad > 8 and "…" or "")))
    end
end

-- 「装填」：扫背包把所有药水移进容器，并清空背包该槽
local function collect_all()
    log("[药水袋·诊断] collect_all 进入（按钮已触发）")
    -- ★ 句柄状态总览：放在任何 early-return 之前，保证一定输出（不依赖后续流程）
    log(string.format(
        "[药水袋·诊断] 句柄: f_playerArr=%s f_myPlayer=%s getMyPlayer=%s f_localPlayer=%s f_inventory=%s f_type=%s f_stack=%s f_buffType=%s f_consumable=%s f_maxStack=%s m_setDefaults=%s",
        tostring(C.f_playerArr ~= nil), tostring(C.f_myPlayer ~= nil),
        tostring(C.m_getMyPlayer ~= nil), tostring(C.f_localPlayer ~= nil),
        tostring(C.f_inventory ~= nil), tostring(C.f_type ~= nil),
        tostring(C.f_stack ~= nil), tostring(C.f_buffType ~= nil),
        tostring(C.f_consumable ~= nil), tostring(C.f_maxStack ~= nil),
        tostring(C.m_setDefaults ~= nil)))
    lp_dbg = true
    local pl = local_player()
    lp_dbg = false
    if not pl then
        log("[药水袋] 取不到本地玩家（getMyPlayer/myPlayer/LocalPlayer 三种方式都失败）")
        return 0
    end
    log("[药水袋·诊断] local_player OK")
    local inv, len = inventory_of(pl)
    if not inv or len <= 0 then
        log(string.format("[药水袋] 取不到背包数组 inv=%s len=%s", tostring(inv), tostring(len)))
        return 0
    end

    -- 诊断①：inv长度 + 句柄（能走到这说明玩家+背包都拿到了）
    log(string.format(
        "[药水袋·诊断] 玩家+背包 OK inv长度=%d | f_type=%s f_stack=%s f_buffType=%s f_playerArr=%s f_myPlayer=%s getMyPlayer=%s",
        len, tostring(C.f_type ~= nil), tostring(C.f_stack ~= nil),
        tostring(C.f_buffType ~= nil), tostring(C.f_playerArr ~= nil),
        tostring(C.f_myPlayer ~= nil), tostring(C.m_getMyPlayer ~= nil)))

    -- 诊断②：无条件 dump 前 10 槽（全 0 也打，才能看出 array_at/字段读是否失败）
    local dbg_end = math.min(len, 10) - 1
    for i = 0, dbg_end do
        local it = arr_at(inv, i)
        local tv = gf_int(C.f_type, it)
        local bv = gf_int(C.f_buffType, it)
        local sv = gf_int(C.f_stack, it)
        log(string.format("[药水袋·dump] slot=%d it=%s valid=%s type=%s buffType=%s stack=%s",
            i, tostring(it), tostring(it ~= nil and valid(it)),
            tostring(tv), tostring(bv), tostring(sv)))
    end
    -- 诊断③：扫全背包找任何 buffType>0 的槽
    for i = 0, math.min(len, CFG.INV_SLOTS) - 1 do
        local it = arr_at(inv, i)
        local bv = gf_int(C.f_buffType, it)
        if bv and bv > 0 then
            local tv = gf_int(C.f_type, it)
            log(string.format("[药水袋·dump] 发现药水 slot=%d type=%s buffType=%s name=%s",
                i, tostring(tv), tostring(bv), tostring(item_name(it, num(tv, 0)))))
        end
    end

    if len > CFG.INV_SLOTS then len = CFG.INV_SLOTS end
    local moved = 0
    for i = 0, len - 1 do
        local it = arr_at(inv, i)
        if it then
            -- ★v1.12.0 装填诊断：候选槽（buffType>0 或虫洞白名单）入判前拍全字段快照，
            -- 一行看全 valid/stack/maxStack/consumable/容器数——直接区分
            --   根因A "consumable=false 被 is_potion 拦" vs 根因B "stack<=0 被数量守卫拦"。
            local ty0 = num(gf_int(C.f_type, it), 0)
            local bt0 = num(gf_int(C.f_buffType, it), 0)
            if bt0 > 0 or CFG.WORMHOLE[ty0] then
                log(string.format(
                    "[药水袋·装填 type=%d] slot=%d valid=%s buffType=%d stack=%d maxStack=%d consumable=%s damage=%d 容器=%d/%d",
                    ty0, i, tostring(it ~= nil and valid(it)), bt0,
                    num(gf_int(C.f_stack, it), 0),
                    num(gf_int(C.f_maxStack, it), 0),
                    tostring(gb(C.f_consumable, it)),
                    num(gf_int(C.f_damage, it), 0),
                    #bag.entries, CFG.MAX_ENTRIES))
            end
            if is_potion(it, i) then
                local t  = num(gf_int(C.f_type, it), -1)
                local s  = num(gf_int(C.f_stack, it), 0)
                local bt = num(gf_int(C.f_buffType, it), 0)   -- 记录 buffType，存进条目供永久buff直用
                local nm = item_name(it, t)
                if t >= 0 and s > 0 then
                    if store_into(t, s, nm, bt) > 0 then
                        -- 根因1：清槽必须连 buffType/buffTime 一起归零，否则槽残留 buffType>0
                        -- 下次扫到 type=0/buffType=9 被误判为药水（v1.6.0 二次装填 0 个的元凶）。
                        pcall(P.invoke, C.m_setDefaults, it, 0)   -- SetDefaults(0)=Air，整体复位
                        sf_int(C.f_type, it, 0)
                        sf_int(C.f_stack, it, 0)
                        sf_int(C.f_buffType, it, 0)
                        moved = moved + s
                    else
                        log(string.format("[药水袋·装填 type=%d] slot=%d 被拦：store_into=0（容器 %d/%d stack=%d）",
                            t, i, #bag.entries, CFG.MAX_ENTRIES, s))
                    end
                else
                    -- 数量守卫分支（根因B 检测点）：is_potion 已过但 type<0 或 stack<=0
                    log(string.format("[药水袋·装填] slot=%d 被拦：数量守卫 t=%d s=%d（type/buffType 残留而 stack<=0=幽灵槽）",
                        i, t, s))
                end
            end
        end
    end
    if moved > 0 then save_bag_now() end
    return moved
end

-- 找背包可堆叠槽 / 空槽（堆叠优先）
local function find_slot(inv, len, t)
    local empty, stackable = -1, -1
    for i = 0, len - 1 do
        local it = arr_at(inv, i)
        if it and valid(it) then
            local bt = num(gf_int(C.f_type, it), -1)
            if bt == 0 then
                if empty < 0 then empty = i end
            elseif bt == t then
                -- 只有还有空余（cur<STACK_MAX）才算可堆叠槽；满槽返回它会让 room=0 直接 break
                local cur = num(gf_int(C.f_stack, it), 0)
                if cur >= 0 and cur < CFG.STACK_MAX and stackable < 0 then stackable = i end
            end
        end
    end
    if stackable >= 0 then return stackable end
    return empty
end

-- 取出：把容器药水放回背包（优先同类型堆叠，其次空槽）。
-- only_type=nil 取全部；only_type=t 只取该种（列表单条「取出」按钮用）。
-- amt: 本次最多取回数量（nil/0=全部，需求6 单次取出数量调节）
local function take_all(only_type, amt)
    local pl = local_player()
    if not pl then log("[药水袋] 取不到本地玩家（take_all）"); return 0 end
    local inv, len = inventory_of(pl)
    if not inv or len <= 0 then log("[药水袋] 取不到背包数组（take_all）"); return 0 end
    if len > CFG.INV_SLOTS then len = CFG.INV_SLOTS end

    local moved, keep = 0, {}
    local cap = (amt and amt > 0) and amt or nil   -- 需求6：单次取出数量上限（nil=全部）
    for _, e in ipairs(bag.entries) do
        if (only_type == nil or e.type == only_type) and (cap == nil or moved < cap) then
            local left = e.stack
            local orig = e.stack
            while left > 0 do
                local slot = find_slot(inv, len, e.type)
                if slot < 0 then
                    log(string.format("[药水袋·take] type=%d 背包无空槽且无可堆叠槽 → 保留剩余 %d（清背包后再取）", e.type, left))
                    break
                end
                local it = arr_at(inv, slot)
                local cur = num(gf_int(C.f_stack, it), 0)
                if cur < 0 then cur = 0 end
                local room = CFG.STACK_MAX - cur
                if room <= 0 then break end
                local put = (left < room) and left or room
                if cap and moved + put > cap then put = cap - moved end
                if put <= 0 then break end
                -- 写入前先 SetDefaults(e.type) 让该槽成为正确物品（maxStack/buff 等复位）
                pcall(P.invoke, C.m_setDefaults, it, e.type)
                sf_int(C.f_type,  it, e.type)
                sf_int(C.f_stack, it, cur + put)
                if e.buffType and e.buffType > 0 then sf_int(C.f_buffType, it, e.buffType) end
                -- ★v1.12.0 装填根因修复：SetDefaults 是 pcall，静默失败时槽的 consumable
                -- 保留旧值——写进"从没装过药水的槽"=false，下轮装填在 is_potion 的
                -- `cons==false` 处被永久拦截（真机 slot44 type=297 / slot58 type=303 元凶）。
                -- 袋中只有药水 → 写回时强制 consumable=true、maxStack=STACK_MAX(9999)，
                -- 保证"取出后再装填"必过；写后回读，失败则记日志（诊断）。
                sf_bool(C.f_consumable, it, true)
                sf_int(C.f_maxStack, it, CFG.STACK_MAX)
                local cons_w = gb(C.f_consumable, it)
                if cons_w ~= true then
                    log(string.format("[药水袋·take] consumable 写后=%s（sf_bool/SetDefaults 失败？）type=%d slot=%d",
                        tostring(cons_w), e.type, slot))
                end
                -- ★需求3：回读实际写入量，只扣真正放进去的；写失败立即 break 保留剩余，绝不丢
                local after = num(gf_int(C.f_stack, it), -1)
                local placed = (after > cur) and (after - cur) or 0
                if placed <= 0 then
                    log(string.format("[药水袋·take] 写入失败 type=%d slot=%d cur=%d after=%d → 保留剩余 %d",
                        e.type, slot, cur, after, left))
                    break
                end
                if placed > put then placed = put end
                left = left - placed
                moved = moved + placed
            end
            log(string.format("[药水袋·take] type=%d 取出前stack=%d 本次取回=%d 取出后剩余=%d",
                e.type, orig, orig - left, left))
            if left > 0 then
                e.stack = left
                keep[#keep + 1] = e
            end
        else
            keep[#keep + 1] = e
        end
    end
    bag.entries = keep
    if moved > 0 then save_bag_now() end
    return moved
end

-- 单条取出（列表行按钮）；透传 S.take_amt（需求6，0=全部）
local function take_one(t)
    return take_all(t, S.take_amt)
end

-- buffType 缓存：药水 type -> buffType（用临时实例 SetDefaults 读一次即缓存）
local buff_cache = {}
local function potion_buff(t)
    if buff_cache[t] ~= nil then return buff_cache[t] end
    local bt = 0
    if C.ItemT and C.m_setDefaults then
        local f_bt = try_field(C.ItemT, "buffType")
        local ok, tmp = pcall(P.new_instance, C.ItemT)
        if ok and valid(tmp) then
            pcall(P.invoke, C.m_setDefaults, tmp, t)
            bt = num(gf(f_bt, tmp, "int32"), 0)
        end
    end
    buff_cache[t] = bt
    return bt
end

-- 永久 buff：某药水在容器里攒到档位 N 瓶后，每帧 AddBuff(buffType, 3600) 续期，
-- ★永久 buff（重写）：原实现每 15 帧 AddBuff(bt,3600) 续期，但 PE 上刷新实际不生效
-- （日志 invoke=true 只反映 pcall 成功，P.invoke 的 false 返回被丢弃）→ HUD 一直读秒、buff 照掉。
-- 新实现三步纯数据写，不 hook 任何方法（不碰 Player.Update/Main.Update，零闪退风险）：
--   1) 无槽才 AddBuff 占槽（老路径，已验证能把 buff 加上）
--   2) array_set 直写 buffTime[槽]：TimeLeftDoesNotDecrease 生效时只补 >0；否则补 2^30 大值
--   3) Main.buffNoTimeDisplay[bt]=true 关掉 HUD 读秒（显示门 Main.cs:44079 → 44105 不再取时间）
-- 不再达标（取出/低于阈值）→ 撤开关 + buffTime 归 3600 → 60 秒内自然到期（保持原行为）。
local PERM_TIME = 1073741823   -- 2^30 帧 ≈ 200 天；留余量，且 buffTime+AddBuff 不会 int 溢出
local perm_flags = {}          -- bt -> {noHud=bool, noDecr=bool}
local apply_tick = 0

-- 读 int[] 元素：array_at_raw 优先（内核读 int 数组更稳），回退 array_at "int32"
local function arr_int(arr, i)
    if not arr or not valid(arr) then return nil end
    if P.array_at_raw then
        local ok, raw = pcall(P.array_at_raw, arr, i, 4)
        if ok and type(raw) == "string" and #raw == 4 then
            local ok2, v = pcall(string.unpack, "<i4", raw)
            if ok2 then return v end
        end
    end
    local ok, v = pcall(P.array_at, arr, i, "int32")
    if ok and type(v) == "number" then return v end
    return nil
end

-- 玩家 buffType 数组里 bt 所在槽位；无槽返回 -1
local function find_buff_slot(pl, bt)
    if not C.f_pBuffType or not pl or not valid(pl) then return -1 end
    local ok, arr = pcall(P.get_field_value, C.f_pBuffType, pl, "object")
    if not ok or not valid(arr) then return -1 end
    local okn, n = pcall(P.array_length, arr)
    if not okn or type(n) ~= "number" then return -1 end
    for i = 0, n - 1 do
        if arr_int(arr, i) == bt then return i end
    end
    return -1
end

-- 每个 bt 只写一次的两个开关（写成功才缓存，失败下个周期重试；array_set 幂等）
local function ensure_perm_flags(bt)
    local st = perm_flags[bt]
    if not st then st = { noHud = false, noDecr = false }; perm_flags[bt] = st end
    if not st.noHud and C.f_noTimeDisplay then
        local ok, arr = pcall(P.get_field_value, C.f_noTimeDisplay, nil, "object")
        if ok and valid(arr) then
            local okw, r = pcall(P.array_set, arr, bt, true, "bool")
            st.noHud = (okw and r) and true or false
        end
    end
    if not st.noDecr and C.f_noDecr then
        local ok, arr = pcall(P.get_field_value, C.f_noDecr, nil, "object")
        if ok and valid(arr) then
            local okw, r = pcall(P.array_set, arr, bt, true, "bool")
            st.noDecr = (okw and r) and true or false
        end
    end
    return st
end

-- 不再达标：撤掉两个开关 + buffTime 归 3600 → 按原行为 ~60 秒自然到期
local function release_perm_flags(pl, bt, time_arr)
    local st = perm_flags[bt]
    if not st then return end
    if st.noDecr and C.f_noDecr then
        local ok, arr = pcall(P.get_field_value, C.f_noDecr, nil, "object")
        if ok and valid(arr) then pcall(P.array_set, arr, bt, false, "bool") end
    end
    if st.noHud and C.f_noTimeDisplay then
        local ok, arr = pcall(P.get_field_value, C.f_noTimeDisplay, nil, "object")
        if ok and valid(arr) then pcall(P.array_set, arr, bt, false, "bool") end
    end
    if time_arr then
        local slot = find_buff_slot(pl, bt)
        if slot >= 0 then pcall(P.array_set, time_arr, slot, 3600, "int32") end
    end
    perm_flags[bt] = nil
end

local function apply_permanent_buffs()
    apply_tick = apply_tick + 1
    if apply_tick % 15 ~= 0 then return end        -- 每 15 帧检查一次，省反射开销
    local pl = local_player()
    if not pl then return end
    local time_arr = nil                           -- Player.buffTime int[]，按需取一次
    if C.f_pBuffTime then
        local ok, a = pcall(P.get_field_value, C.f_pBuffTime, pl, "object")
        if ok and valid(a) then time_arr = a end
    end
    local dbg, any = {}, false
    local active = {}                              -- 本周期达标的 bt 集合
    for _, e in ipairs(bag.entries) do
        -- 需求4：e.buff_on 开关控制单条续期（默认开）
        if e.stack >= S.threshold and e.buff_on ~= false then
            -- 优先用装填时记录的 buffType（e.buffType），避免 potion_buff 临时实例读失败=0
            local bt = e.buffType or 0
            if bt <= 0 then bt = potion_buff(e.type) end
            if bt > 0 then
                any = true
                active[bt] = true
                local slot = find_buff_slot(pl, bt)
                local add = "skip"
                if slot < 0 and C.m_addBuff then
                    -- 无槽：先 AddBuff 占槽（老路径）
                    local ok
                    if C.addBuff_argc == 4 then
                        ok = pcall(P.invoke, C.m_addBuff, pl, bt, 3600, false, true)
                    elseif C.addBuff_argc == 3 then
                        ok = pcall(P.invoke, C.m_addBuff, pl, bt, 3600, false)
                    else
                        ok = pcall(P.invoke, C.m_addBuff, pl, bt, 3600)
                    end
                    add = tostring(ok)
                    slot = find_buff_slot(pl, bt)
                end
                -- 有槽才写开关：避免 buff 不在身上的时候污染全局标志
                local st = nil
                if slot >= 0 then st = ensure_perm_flags(bt) end
                local t = nil
                if slot >= 0 and time_arr then
                    t = arr_int(time_arr, slot)
                    if st and st.noDecr then
                        -- 已禁递减：只要保持 >0 就永不掉（Player.cs:9958 不再 --）
                        if not t or t < 3600 then
                            pcall(P.array_set, time_arr, slot, 3600, "int32")
                            t = 3600
                        end
                    elseif not t or t < PERM_TIME then
                        -- 禁递减写失败的兜底：直写大值，每 15 帧补一次，永不到 0
                        pcall(P.array_set, time_arr, slot, PERM_TIME, "int32")
                        t = PERM_TIME
                    end
                end
                if #dbg < 3 then
                    dbg[#dbg + 1] = string.format("bt=%d slot=%d time=%s add=%s noHud=%d noDecr=%d",
                        bt, slot, tostring(t), add,
                        (st and st.noHud) and 1 or 0, (st and st.noDecr) and 1 or 0)
                end
            elseif #dbg < 3 then
                -- stack 达标但读不到 buffType：也要暴露，否则误判成"没达到档位"
                dbg[#dbg + 1] = string.format("type=%d stack=%d thr=%d bt=0(buffType读不到)",
                    e.type, e.stack, S.threshold)
            end
        end
    end
    -- 不再达标的 bt：撤开关 + 时间归 3600（pairs 中清 nil = Lua 允许的"清除已有字段"）
    for bt in pairs(perm_flags) do
        if not active[bt] then release_perm_flags(pl, bt, time_arr) end
    end
    -- 诊断：每隔约 5 秒（75 次检查）打一次
    if any and (apply_tick % (15 * 75) == 0) then
        log("[药水袋·buff] 永久化 | " .. table.concat(dbg, " ; "))
    elseif (not any) and (apply_tick % (15 * 75) == 0) and #bag.entries > 0 then
        -- 打出每条实际 stack/buffType，定位是"没达到"还是"buffType读不到"
        local parts = {}
        for _, e in ipairs(bag.entries) do
            parts[#parts + 1] = string.format("t%d:stack=%d/bt=%d", e.type, e.stack, e.buffType or -1)
        end
        log(string.format("[药水袋·buff] 未续期（threshold=%d，容器%d条）| %s",
            S.threshold, #bag.entries, table.concat(parts, " ; ")))
    end
end

-- 移植 SortContainer：type 升序，其次 stack 升序
local function sort_bag()
    table.sort(bag.entries, function(a, b)
        if a.type ~= b.type then return a.type < b.type end
        return a.stack < b.stack
    end)
    save_bag_now()
end

local function clear_bag()
    bag.entries = {}
    save_bag_now()
end

------------------------------------------------------------------------------
-- GUI 面板（mod.gui 即时模式）
------------------------------------------------------------------------------

-- text_at 第4参必须是颜色表 {r,g,b,a}：内核 lua_color 用 luaL_checktype(TABLE) 校验，
-- 缺参会抛错被 pcall 吞掉 → 文本根本不绘制（v1.3.0 档位数字"看不见"就是这个原因）。
local COL_W = {44, 41, 36, 255}   -- 白金主题：正文改深墨（原纯白，浅底不可见）
local COL_DIM = GRAY   -- v1.14.0 统一到主题灰（原 {180,180,180,255}）

local PER_PAGE = 6   -- 需求3：每页条目数设小
local function draw_list(g, y0)
    local n = #bag.entries
    y0 = y0 or 0
    if n == 0 then
        pcall(g.text_at, 0, y0 + 6, "（空）点「装填」收纳背包药水", GREEN, 1.0)
        return y0 + 24
    end
    -- 需求3：分页（上/下一页 + 页码），每页只画 PER_PAGE 条
    local pages = math.ceil(n / PER_PAGE)
    if S.page > pages then S.page = pages end
    if S.page < 1 then S.page = 1 end
    local first = (S.page - 1) * PER_PAGE
    local rowh = 22   -- ★需求2：缩小行距
    local yy = y0
    for i = first, math.min(n - 1, first + PER_PAGE - 1) do
        local e = bag.entries[i + 1]
        if e then
            -- v1.14.0 主题化：buff 关闭（不参与续期）的条目降为灰字，开启为白字
            pcall(g.text_at, 0, yy + 4,
                  string.format("%s x%d", e.name or ("物品#" .. e.type), e.stack),
                  e.buff_on == false and GRAY or COL_W, 1.0)
            -- 需求4：单条 buff 开关（点了才参与续期，状态随存档保存）
            local on = (e.buff_on ~= false)
            if g.button_at(196, yy, 56, 20, on and "buff开" or "buff关") then
                e.buff_on = not on
                save_bag_now()
                -- ★需求6：关闭时立即消除该 buff（不等自然读秒结束）
                if e.buff_on == false and C.m_clearBuff and e.buffType and e.buffType > 0 then
                    local pl2 = local_player()
                    if pl2 then
                        local okc, errc = pcall(P.invoke, C.m_clearBuff, pl2, e.buffType)
                        log(string.format("[药水袋] 立即消除 buff type=%d bt=%d ok=%s %s",
                            e.type, e.buffType, tostring(okc), tostring(errc)))
                    end
                end
                log(string.format("[药水袋] buff开关 type=%d -> %s（状态已存档）",
                    e.type, on and "关" or "开"))
            end
            -- 单条取出（C）
            if g.button_at(258, yy, 62, 20, "取出") then
                local m = take_one(e.type)
                log(string.format("[药水袋] 单取 type=%d 放回=%d（剩 %d 条，单次上限 %d）",
                    e.type, m, #bag.entries, S.take_amt))
            end
        end
        yy = yy + rowh
    end
    -- 翻页按钮行
    if g.button_at(0, yy, 70, 24, "上一页") then
        S.page = math.max(1, S.page - 1)
    end
    pcall(g.text_at, 84, yy + 5, string.format("第 %d/%d 页", S.page, pages), COL_W, 1.0)
    if g.button_at(250, yy, 70, 24, "下一页") then
        S.page = math.min(pages, S.page + 1)
    end
    yy = yy + 32
    return yy
end

local function draw_panel(g)
    local W, btn_h, gap = 276, 28, 5   -- ★需求2：缩小面板减少挡屏
    local y = 0
    -- 全部用绝对坐标 API（button_at/text_at），每行独立 y，不用 same_line/即时 place()，
    -- 与参考 mod SpaceWand 一致（已验证此内核上可点）。即时模式 button 因 same_line 挤行溢出窗口→点不到。
    if g.button_at(0, y, W, btn_h, "装填（背包→药水袋）") then
        log("[药水袋·click] 装填按钮返回 true")
        local m = collect_all()
        log(string.format("[药水袋] 装填：%d 个药水入袋（共 %d 条）", m, #bag.entries))
    end
    y = y + btn_h + gap

    if g.button_at(0, y, W, btn_h, "一键取出（药水袋→背包）") then
        local m = take_all()
        log(string.format("[药水袋] 一键取出：%d 个药水放回背包（剩 %d 条）", m, #bag.entries))
    end
    y = y + btn_h + gap

    if g.button_at(0, y, W, btn_h, "排序") and #bag.entries > 1 then
        pcall(sort_bag)
    end
    y = y + btn_h + gap

    -- 档位 -/+（绝对坐标，替代即时 slider 以免 place() 游标与绝对坐标冲突重叠）
    if g.button_at(0, y, 44, btn_h, "-") then
        S.threshold = math.max(1, S.threshold - 1); save_thresh()
    end
    pcall(g.text_at, 50, y + 9, string.format("永久 buff 档位：%d 瓶", S.threshold), COL_W, 1.0)
    if g.button_at(W - 44, y, 44, btn_h, "+") then
        S.threshold = math.min(30, S.threshold + 1); save_thresh()
    end
    y = y + btn_h + gap

    -- 需求6：单次取出数量调节（0=全部，1/10/100 循环档）
    if g.button_at(0, y, 44, btn_h, "-") then
        if S.take_amt >= 100 then S.take_amt = 10
        elseif S.take_amt >= 10 then S.take_amt = 1
        else S.take_amt = 0 end
        save_thresh()
    end
    pcall(g.text_at, 50, y + 9,
        string.format("单次取出：%s", S.take_amt == 0 and "全部" or tostring(S.take_amt) .. " 瓶"),
        COL_W, 1.0)
    if g.button_at(W - 44, y, 44, btn_h, "+") then
        if S.take_amt <= 0 then S.take_amt = 1
        elseif S.take_amt < 10 then S.take_amt = 10
        else S.take_amt = 100 end
        save_thresh()
    end
    y = y + btn_h + gap

    pcall(g.text_at, 0, y + 6, string.format("已收纳 %d 条药水", #bag.entries), GOLD, 1.0)
    -- v1.11.0 关闭/收起入口：切到图标态（大窗口→袋子图标，点图标恢复面板）
    if g.button_at(W - 56, y, 56, 24, "收起") then
        S.open = false
        log("[药水袋·icon] 点「收起」→ 图标态（袋子图标）")
    end
    y = y + 26
    local yend = draw_list(g, y)
    pcall(g.set_content_height, yend + 12)
end

------------------------------------------------------------------------------
-- v1.11.0 图标态：面板"关闭/收起"后用 PotionBag.png 袋子图标替代大窗口
--
-- 状态机（单标志 S.open，on_gui 每帧读写）：
--   S.open = true  → 展开态：窗口宽 316，画 draw_panel（原有面板，逻辑不动）
--   S.open = false → 图标态：窗口仍 visible 且未 collapsed，缩成只装一个
--                     袋子图标的迷你窗（点图标恢复面板）。
-- 为什么"收起"不能用 hide/set_collapsed（内核源码 gui_window.inc 实测）：
--   :222-246 collapsed 态直接 return，on_gui 根本不回调；
--   :210-219 visible=false 时虽回调 on_gui 但 g_ctx=nil，一切绘制被跳过。
--   所以图标必须画在"可见 + 未收起"的小窗口里。
-- 进入图标态：面板内「收起」按钮（draw_panel 末尾，S.open=false）。
-- 退出图标态：点袋子 image_button（S.open=true）。
-- 标题栏原生 "v" 收起按钮（gui_window.inc:269）由内核独占处理，点击后
--   on_gui 不再回调、Lua 无法拦截；该路径显示原生方块（启动器文字已设为
--   "袋"），点方块即由内核恢复展开——与本图标态并存，互不冲突。
------------------------------------------------------------------------------
local ICON_W, ICON_H = 56, 64   -- 28x32 源图 2 倍整数缩放（像素风不糊）
local WIN_ICON_W = 80           -- 图标态窗口宽（56 + 左右 pad 12*2；set_width 下限 60）
local IMG_ICON_ID, IMG_ICON_TRIED, IMG_ICON_ALT = nil, false, false

-- v1.14.0 任务1：贴图路径 = lib/ui/PotionBag.png
--   root 是 mod 的 private_dir（= Resources，doc/gui.md:67「PNG 放 Resources/lib/ui/，
--   路径写 lib/ui/x.png」）；zip 内 arcname 必须是 Resources/lib/ui/PotionBag.png。
--   上一版查的 Image/ 与 Resources/Image/ 两处都没有文件 → 贴图没显示的根因。
-- 注意 load_image 只登记路径不解码，首次 image 才触发解码，image_status 会一直
-- 返回 pending——所以不能"等 ready 再画"，必须照常调 image_button（见 draw_icon）。
local function bag_image(g)
    if not IMG_ICON_TRIED then
        IMG_ICON_TRIED = true
        local ok, id = pcall(g.load_image, "lib/ui/PotionBag.png")
        if ok and id then
            IMG_ICON_ID = id
            log("[药水袋·icon] load_image(lib/ui/PotionBag.png) -> " .. tostring(id))
        else
            log("[药水袋·icon] load_image 主路径失败：" .. tostring(id))
        end
    end
    -- 主路径文件缺失会在首次绘制后变成 "failed:..."，此时回退旧包位置
    if IMG_ICON_ID and not IMG_ICON_ALT then
        local oks, st = pcall(g.image_status, IMG_ICON_ID)
        if oks and type(st) == "string" and st:sub(1, 6) == "failed" then
            IMG_ICON_ALT = true
            local ok2, id2 = pcall(g.load_image, "Image/PotionBag.png")
            if ok2 and id2 then
                log("[药水袋·icon] 主路径 failed，回退 load_image(Image/PotionBag.png) -> " .. tostring(id2))
                return id2
            end
        end
    end
    return IMG_ICON_ID
end

-- v1.14.0 任务1：set_skin —— 收起入口显示袋子图标（内核 gui_lua.inc:533-541）。
-- 只能在 on_gui 上下文调（set_skin 要 current_window()，on_gui 里 g_current_mod
-- 已设）；S.skin_done 守卫只调一次，全部 pcall。load_image 虽是异步登记，但
-- set_skin 只存 ID 不要求 ready（内核绘制时才查 status）。
local function ensure_images(g)
    if S.skin_done then return end
    if type(g.load_image) ~= "function" or type(g.set_skin) ~= "function" then
        S.skin_done = true
        log("[药水袋·skin] 图片 API 不可用（load_image/set_skin 缺失），跳过 set_skin")
        return
    end
    local id = bag_image(g)
    if not id then
        S.skin_done = true
        log("[药水袋·skin] load_image 未返回 ID，跳过 set_skin")
        return
    end
    -- set_skin 要求 panel 与 icon 都是本 mod 的图片 ID（image_owned 只查前缀，
    -- gui_lua.inc:475 + 537 的 guards）。用户只给了 PotionBag.png 一张图 →
    -- panel 传同前缀的占位 ID：内核 draw_image 缓存未命中静默 return、
    -- status→"invalid" → custom_panel=false → 面板仍走默认配色（不硬造面板
    -- 皮肤），而 icon 是真图 → 收起入口画袋子图标。border=10 size=48 edge=0
    -- （guards: border>0 且 24<=size<=128）。
    local pid = tostring(id):gsub("#.*$", "#__panel_default__")
    local ok, err = pcall(g.set_skin, pid, 10, id, 48, 0)
    S.skin_done = true
    log(string.format("[药水袋·skin] set_skin(panel=%s,border=10,icon=%s,size=48,edge=0) ok=%s %s",
        tostring(pid), tostring(id), tostring(ok), tostring(err or "")))
end

-- 图标态绘制：窗口内容只有一个袋子图标，点击恢复面板
local function draw_icon(g)
    pcall(g.set_content_height, ICON_H)
    -- 占位底块：贴图 pending/failed 时也有可见目标（解码是异步的）；用主题青色
    pcall(g.rect, 0, 0, ICON_W, ICON_H, THEME.title)
    local id = bag_image(g)
    local clicked = false
    if id then
        local oks, st = pcall(g.image_status, id)
        local ready = oks and st == "ready"
        -- pending/failed 时带 label="袋" 兜底文字；ready 时纯图不压字
        -- （不能写成 ready and nil or "袋"：nil 会被 or 吞掉，恒为 "袋"）
        local label = "袋"
        if ready then label = nil end
        local okb, c = pcall(g.image_button, id, 0, 0, ICON_W, ICON_H, label)
        clicked = okb and c == true
        if oks and type(st) == "string" and st:sub(1, 6) == "failed"
           and not S.icon_fail_logged then
            S.icon_fail_logged = true
            log("[药水袋·icon] 贴图加载失败（将显示「袋」字按钮兜底）：" .. tostring(st))
        end
    else
        -- 贴图完全不可用时的最后兜底：文本按钮，保证总能点回面板
        clicked = g.button_at(0, 0, ICON_W, ICON_H, "袋") == true
    end
    if clicked then
        S.open = true
        log("[药水袋·icon] 点袋子图标 → 展开面板")
    end
end

-- v1.14.0 任务2：是否在世界里（主菜单 gameMenu=true → 不弹窗）
-- 只读 bind_reflection 已解析的句柄，全部 pcall，只在 on_gui 上下文执行。
local function in_world()
    -- ① Main.gameMenu（true=主菜单）：PE 上是属性 → get_gameMenu getter，
    --    invoke 静态 getter 无实例参（l_patch_invoke sig.is_instance=false）
    if C.m_gameMenu then
        local ok, v = pcall(P.invoke, C.m_gameMenu)
        if ok and type(v) == "boolean" then return not v end
    end
    -- ② 兜底：有的版本 gameMenu 是静态字段
    if C.f_gameMenu then
        local v = gf(C.f_gameMenu, nil, "bool")
        if type(v) == "boolean" then return not v end
    end
    -- ③ 再兜底：Main.worldName 非空 = 已进世界
    if C.f_worldName then
        local v = gf(C.f_worldName, nil, "string")
        if type(v) == "string" then return v ~= "" end
    end
    return false
end

function mod.on_gui()
    local g = mod.gui
    if not g then return end

    if not S.setup_done then pcall(setup) end

    -- v1.14.0 视觉优化：主题配色（内核默认面板/标题/边框/按钮/文字，
    -- gui_window.inc:99-108 按常量指针映射，g_style_window @206 已指向本窗口）
    pcall(g.set_style, THEME)

    -- v1.14.0 任务1：贴图注册 + set_skin（收起入口显示袋子图标），skin_done 守卫
    pcall(ensure_images, g)

    -- v1.14.0 任务2：进/退世界瞬间强制收起成小图标（只在 w 变化的那一帧触发
    -- 一次 → 手动展开后不会被反复收回）。用 S.open=false 图标态而不是
    -- g.set_collapsed(true)：源码定论 collapsed 态 on_gui 直接 return 不回调
    -- （gui_window.inc:222-246 / 295-298），会连带停掉永久 buff 续期与本检测。
    -- v1.14.1 修复：S.last_in_world 初值 nil 会让首帧 false~=nil 恒真，
    -- 主菜单误弹图标窗。改为首帧只定基线不动作；句柄缺失(w=nil)退化为常显；
    -- 仅在真正 进/出世界 那一帧收成图标。
    local det = (C.m_gameMenu or C.f_gameMenu or C.f_worldName) and true or false
    local w = nil
    if det then w = in_world() end   -- ★修 or 吞坑：菜单的 false 不能被 or 吞成 nil
    if w ~= nil then
        if S.last_in_world == nil then
            S.last_in_world = w
            log("[药水袋·world] 初始在世界=" .. tostring(w))
            if w == false then
                -- 启动即在主菜单：收起一次（此后不动，展开由用户自己点）
                pcall(g.set_collapsed, true)
                log("主菜单初始 -> collapsed=true")
            end
        elseif w ~= S.last_in_world then
            S.last_in_world = w
            if w == false then
                -- ★只在「进入主菜单」这一帧收一次（参考代码同思路，边沿触发）
                -- 之后用户手动展开 → 不再有任何收起逻辑 → 永不被强收
                pcall(g.set_collapsed, true)
                log("WORLD CHANGE -> false collapsed=true (只收这一次)")
            else
                -- 进世界：不收（收了会把用户已展开的面板强行收回）
                log("WORLD CHANGE -> true (保持当前展开状态)")
            end
        end
    end
    S.in_menu = (w == false)

    -- v1.5 恢复拖动（照 SpaceWand:3468 模式）：标题/可见/宽度每帧设，
    -- set_pos 只在首次设一次（panel_pos_done 守卫），之后原生拖动自由更新 rect。
    -- point_in_gui 用 ws.x/y/w/h 判触摸，拖动时原生同步该矩形，故无需每帧钉死。
    -- v1.11.0：按状态机切标题/宽度——展开态原样（316 宽），图标态缩成袋子小窗。
    -- 第2参=原生收起点的启动器文字（gui_window.inc:241），原生收起时方块显示"袋"。
    if S.open then
        pcall(g.set_title, "药水袋", "袋")
    else
        pcall(g.set_title, "袋", "袋")       -- 窄窗只放得下一个字
    end
    pcall(g.set_visible, true)   -- 常可见：主菜单收起后显示袋子图标入口
    -- ★不再每帧 set_collapsed(false)：那会把用户手动展开的窗口下一帧强收回去
    -- （m01964 红线：打开之后不会被强制收回）。收起只发生在进主菜单那一帧。
    pcall(g.set_width, S.open and 316 or WIN_ICON_W) -- 每帧设宽（★需求2 缩小 / 图标态 80）
    if not S.pos_set then
        S.pos_set = true
        pcall(g.set_pos, 200, 140)   -- 仅首次设位置，之后可自由拖动
    end

    if not S.hb_logged then
        S.hb_logged = true
        log("[药水袋·on_gui] 运行中（心跳：on_gui 已启动，窗口 rect 每帧强制）")
    end

    -- 需求2根因：续期绝不能绑在面板可见性上——关面板也要每帧跑，buff 才真永久
    -- ★v1.14.6 修「关模组重开后药水全丢」：world_ready 改为进世界后才置位，
    -- 角色档重载不再只有首帧一次机会——首帧在主菜单时玩家名解析不出
    -- (pf==bag.dat)，旧逻辑跳过重载而 world_ready 已为 true 永不再试，
    -- 袋子只剩 setup 载入的空全局档，再点装填/取出就把空数据写回好档。
    if w == true then
        if not S.world_ready then
            S.world_ready = true
            log("[药水袋·存档] world_ready=1（进世界，player_file 开始解析玩家名）")
        end
        local okp, pf = pcall(player_file)
        if okp and pf and pf ~= S.loaded_pf then
            -- ★v1.3.1 角色互通修复
            -- 1) 先把当前袋子的内容写回「上一个角色」的档，避免丢失
            if S.loaded_pf then
                pcall(save_bag_now, S.loaded_pf)
                log("[药水袋·存档] 切档前已保存 " .. S.loaded_pf .. "（" .. #bag.entries .. " 条）")
            end
            -- 2) 关键：无论如何先清空，绝不让上一个角色的药水残留到新角色
            bag.entries = {}
            S.loaded_pf = pf
            local s2 = load_txt(pf)
            if s2 and s2 ~= "" then
                pcall(load_bag, pf)
                log("[药水袋·存档] 载入角色档 " .. pf .. "，条目=" .. #bag.entries)
            else
                log("[药水袋·存档] 角色档 " .. tostring(pf) ..
                    " 不存在/为空，已置空袋子（不继承其它角色）")
            end
        end
    end

    pcall(apply_permanent_buffs)     -- 永久 buff 续期（每 15 帧检查一次，与面板开关无关）
    if S.open then
        draw_panel(g)
    else
        draw_icon(g)                 -- v1.11.0 图标态：袋子图标即"恢复按钮"
    end
end

------------------------------------------------------------------------------
-- 生命周期
------------------------------------------------------------------------------
function setup()
    if S.setup_done then return end

    local bok, berr = pcall(bind_reflection)
    if not bok then log("[药水袋] bind_reflection 异常：" .. tostring(berr)) end

    pcall(load_bag)
    pcall(load_thresh)
    log(string.format("[药水袋·存档] setup 初始载入：档=%s 条目=%d threshold=%s",
        CFG.BAG_FILE, #bag.entries, tostring(S.threshold)))

    S.open = true                          -- 纯面板：进世界默认显示
    if type(mod.gui) == "table" and type(mod.gui.show) == "function" then
        pcall(mod.gui.show)
    end

    -- ★需求1（v1.9.1 修复闪退）：移除 Main.Update 每帧钩子——它跑在游戏主循环里，
    -- 反射调用在 Update 上下文不安全，导致 v1.9.0 闪退。改回 v1.8.0 的安全方式：
    -- 续期由 mod.on_gui 每帧 pcall(apply_permanent_buffs) 承担（on_gui 隐藏时仍回调，
    -- gui_window.inc:210-215 已确认），与 S.open 无关，关面板照样续期。
    log("[药水袋·bind] 已移除 Main.Update 钩子（防闪退），续期走 on_gui 每帧")

    S.setup_done = true
    log(string.format("[药水袋] 面板已加载（纯面板版 v1.9，容器 %d 条）", #bag.entries))
end

todo_list = { "setup" }

function mod.init()
    pcall(setup)
end

function mod.cleanup()
    -- ★v1.3.1 角色互通修复：卸载时写回「当前已确认的角色档」。
    -- 此时多半已回到主菜单，player_file() 解析不出玩家名会落到全局 bag.dat，
    -- 造成多角色共用一份数据。
    if S.loaded_pf then
        pcall(save_bag_now, S.loaded_pf)
    else
        pcall(save_bag_now)
    end
end
