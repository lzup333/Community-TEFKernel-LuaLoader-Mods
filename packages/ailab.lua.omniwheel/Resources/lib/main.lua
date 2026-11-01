-- ============================================================================
-- 万象轮盘 (OmniWheel) v1.0.0  —— 为 LuaLoader 1.6.1 写的「新 API 展示型」娱乐模组
-- ============================================================================
--
-- 【它做什么】
--   一个会自己转的抽奖轮盘：每隔一段时间从「已开启的转盘」里随机转到一个，
--   当场兑现成看得见的效果，并在聊天栏播报结果（带游戏内中文名）。
--     物品轮 —— 天降随机物品（从天上掉下来）
--     祝福轮 —— 随机增益，带时长
--     弹幕轮 —— 随机弹幕环形齐射（弹幕名只有英文成员名）
--     怪物轮 —— 随机刷怪（默认关闭，可过滤 Boss / 城镇 NPC）
--     治愈轮 —— 按比例回血回蓝
--     大满贯 —— 小概率触发，所有已开启的转盘同时开奖 + 特殊音效
--   另有 18 条聊天指令（!give / !buff / !npc / !find / !set / !api ...）可随时手动开奖、按名字取物、改设置。
--
-- 【为什么它需要 LuaLoader 1.6.1 的新 API】
--   本模组刻意把「名字 ↔ 编号」这件事交给运行时自省，而不是写死一张物品表：
--     * patch.get_fields / field_name / field_is_static / field_is_const
--         → 枚举 Terraria.ID.ItemID / BuffID / NPCID / ProjectileID 的成员名（纯元数据，不读常量值）
--     * patch.get_methods / method_name / method_param_count / method_is_static
--         → 列出一个类型上的全部重载，再挑参数最多的那个（NewProjectile 的 13/12 参之争）
--     * patch.get_method_by_param_types / get_method_by_signature / get_full_name / get_namespace
--         → 重载消歧与自检日志
--     * patch.list_create / list_add / list_get_array / dictionary_create / dictionary_add / ...
--         → !api 指令里做「新 API 体检」，当场验证这些函数在本机可用
--     * patch.struct_arg / invoke_value_args
--         → 「屏幕飘字」实验模块（默认关闭，见设置里的说明）
--   名字词典本身走的是更稳的路：读 Terraria.ID.ItemID.Search（非 const 静态字段）与
--   Lang.GetItemNameValue / Lang.GetBuffName / Lang.GetNPCNameValue 这类「正常」静态方法，
--   分帧扫描建立 编号→本地化名 表，因此不需要去读 const 字面量（那属于未验证路径）。
--
-- 【依赖符号】全部来自工作区已验证集合（symbols.json）与 26 个现成 Mod 的真实调用点：
--   Terraria.Main.player / myPlayer / NewText
--   Terraria.Player.position / width / height / statLife / statLifeMax / statLifeMax2
--                   / statMana / statManaMax2 / whoAmI / AddBuff
--   Terraria.Item.NewItem(9)        Terraria.NPC.NewNPC(10)
--   Terraria.Projectile.NewProjectile(13/12)  Terraria.Audio.SoundEngine.PlaySound(6)
--   Terraria.Chat.ChatCommandProcessor.ProcessIncomingMessage(2)
--   Terraria.Chat.ChatHelper.SendChatMessageFromClient(1)  Terraria.Chat.ChatMessage.get_Text
--   Terraria.Lang.GetItemNameValue / GetBuffName / GetNPCNameValue / GetProjectileName
--   Terraria.ID.{ItemID,BuffID,NPCID,ProjectileID}.Search  (IdDictionary.GetName)
--
-- 【失败策略】任何 get_* 取不到只打日志并关掉对应功能，绝不拿空句柄去 invoke；
--   所有 install_hook 都用 pcall 包住；回调内先判空再干活。
--   ⚠ 本模组为静态分析产物，未在实机上运行过（工作区无法启动游戏），请先只装它试玩。
-- ============================================================================

mod.meta = { pkg_id = "ailab.lua.omniwheel", version = "1.0.1" }

local patch = mod.patch

-- ============================================================================
-- 1. 设置：默认值（必须与 Info.json 的 settings 逐项一致）
-- ============================================================================
local DEFAULTS = {
    -- A. 总控
    enabled = true,
    interval_sec = 20,
    announce = true,
    sound = true,
    jackpot_chance = 5,
    hot_reload = true,
    debug_log = false,
    codex_scan = true,
    codex_en = true,
    diag_log = true,
    -- B. 物品轮
    wheel_item = true,
    item_count = 2,
    item_id_max = 5450,
    -- C. 祝福轮
    wheel_buff = true,
    buff_seconds = 30,
    buff_id_max = 350,
    -- D. 弹幕轮
    wheel_proj = true,
    proj_count = 6,
    proj_id_max = 1000,
    -- E. 怪物轮
    wheel_npc = false,
    npc_count = 1,
    npc_id_max = 400,
    allow_boss = false,
    -- F. 治愈轮
    wheel_heal = true,
    heal_percent = 50,
    -- G. 交互
    chat_cmd = true,
    float_text = false,
    gui_panel = false,
}

-- 取值范围（与 Info.json 的 min/max 一致；读文件时再夹一次，防止手改越界）
local LIMITS = {
    interval_sec = { 5, 600 },
    jackpot_chance = { 0, 50 },
    item_count = { 1, 20 },
    item_id_max = { 10, 6000 },
    buff_seconds = { 3, 600 },
    buff_id_max = { 10, 400 },
    proj_count = { 1, 30 },
    proj_id_max = { 10, 1500 },
    npc_count = { 1, 10 },
    npc_id_max = { 1, 800 },
    heal_percent = { 10, 100 },
}

local cfg = {}
for key, value in pairs(DEFAULTS) do cfg[key] = value end

-- ============================================================================
-- 2. 运行时状态
-- ============================================================================
local ready = false
local reported = {}          -- 一次性日志去重
local T, F, M, FM = {}, {}, {}, {}   -- 类型 / 字段 / 方法 / 方法回退句柄
local hooks = {}
local stats = { spins = 0, jackpot = 0, item = 0, buff = 0, proj = 0, npc = 0, heal = 0 }
local frame_counter = 0
local last_roll_at = 0
local last_config_raw = nil
local gui_error_logged = false
local struct_shape = nil     -- struct_arg 的可用调用形态（!api 探测）
local try_float_text         -- 前置声明：屏幕飘字（实验模块，实现在第 9 节）
local bootstrap_in_world     -- 前置声明：进世界后的第一次杂务（实现在第 13 节 setup 之后）
local bootstrapped = false   -- 是否已经做过进世界引导
local bootstrap_frame = 0    -- 引导发生在第几帧（给图鉴扫描留一段"让游戏先安顿好"的缓冲）
local CODEX_WARMUP_FRAMES = 120   -- 进世界后约 2 秒才开始批量扫描

local TICK_FRAMES = 30       -- 每 30 帧做一次轻量杂务（约 0.5 秒）
local SCAN_BUDGET = 240      -- 每次杂务最多扫多少个编号建词典

-- ---- 时间基准（有 os.time 就用它，没有则按 60fps 估算）----
local has_os_time = (type(os) == "table" and type(os.time) == "function")
local frame_total = 0

local function now_seconds()
    if has_os_time then return os.time() end
    return math.floor(frame_total / 60)
end


-- ============================================================================
-- 3. 日志 / 聊天输出
-- ============================================================================
-- 诊断日志：既写加载器日志，也把最近若干行落到模组私有目录的 omniroulette.log。
-- 实机崩溃时进程会直接死掉，加载器日志未必刷得出来，这份文件是"死前遗言"。
local LOG_RING = {}
local LOG_FILE = "omniroulette.log"
local function log_ring_add(text)
    if not cfg.diag_log then return end
    LOG_RING[#LOG_RING + 1] = string.format("[%s] %s", tostring(now_seconds()), tostring(text))
    while #LOG_RING > 60 do table.remove(LOG_RING, 1) end
    pcall(mod.write_file, LOG_FILE, table.concat(LOG_RING, "\n"))
end

local function log_line(text)
    mod.info("%s", tostring(text))
    log_ring_add(text)
end

local function log_warn(text)
    mod.warn("%s", tostring(text))
    log_ring_add("WARN " .. tostring(text))
end

local function log_error(text)
    mod.error("%s", tostring(text))
    log_ring_add("ERROR " .. tostring(text))
end

local function log_once(tag, text)
    if reported[tag] then return end
    reported[tag] = true
    log_line(text)
end

local function log_debug(text)
    if cfg.debug_log then log_line(text) end
end

-- Main.NewText(string, r, g, b[, onlyCurrentPlayer])
-- ★ 实机教训：必须"按已解析句柄自己的参数个数"调用，宁可少传、绝不多传 ——
--   给 4 参重载多传一个实参，在 IL2CPP 侧就是实参错位。
local function show_chat(text, r, g, b)
    if not M.new_text or type(text) ~= "string" then return false end
    local argc = M.new_text_argc
    if type(argc) ~= "number" or argc < 3 then return false end
    local s = patch.string_create(text)
    if not s then return false end
    local ok = pcall(function()
        if argc >= 5 then
            patch.invoke(M.new_text, s, r or 255, g or 255, b or 255, false)
        elseif argc == 4 then
            patch.invoke(M.new_text, s, r or 255, g or 255, b or 255)
        else
            patch.invoke(M.new_text, s)
        end
    end)
    if not ok then log_once("newtext_fail", "万象轮盘：Main.NewText 调用失败，之后不再尝试播报") end
    return ok
end

local function announce(text, r, g, b)
    log_debug(text)
    if cfg.announce then show_chat("[万象轮盘] " .. text, r, g, b) end
    if try_float_text then try_float_text(text, r, g, b) end
end

-- ============================================================================
-- 4. 反射工具（含 1.6.1 新 API 的能力探测与多级回退）
-- ============================================================================
local API = {
    get_fields               = type(patch.get_fields) == "function",
    field_name               = type(patch.field_name) == "function",
    field_is_static          = type(patch.field_is_static) == "function",
    field_is_const           = type(patch.field_is_const) == "function",
    get_methods              = type(patch.get_methods) == "function",
    method_name              = type(patch.method_name) == "function",
    method_param_count       = type(patch.method_param_count) == "function",
    method_is_static         = type(patch.method_is_static) == "function",
    get_full_name            = type(patch.get_full_name) == "function",
    get_namespace            = type(patch.get_namespace) == "function",
    get_method_by_param_types= type(patch.get_method_by_param_types) == "function",
    get_method_by_signature  = type(patch.get_method_by_signature) == "function",
    list_create              = type(patch.list_create) == "function",
    list_add                 = type(patch.list_add) == "function",
    list_get_array           = type(patch.list_get_array) == "function",
    dictionary_create        = type(patch.dictionary_create) == "function",
    dictionary_add           = type(patch.dictionary_add) == "function",
    dictionary_get_value     = type(patch.dictionary_get_value) == "function",
    dictionary_length        = type(patch.dictionary_length) == "function",
    struct_arg               = type(patch.struct_arg) == "function",
    invoke_value_args        = type(patch.invoke_value_args) == "function",
    get_basic_type           = type(patch.get_basic_type) == "function",
}

local function api_count()
    local n, total = 0, 0
    for _, v in pairs(API) do total = total + 1; if v then n = n + 1 end end
    return n, total
end

-- pcall 包装：失败一律返回 nil，绝不把异常抛给调用者
local function safe_call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    return a
end

-- 沿父类链找字段
local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local f = safe_call(patch.get_field, cur, name)
        if f then return f end
        cur = safe_call(patch.get_parent, cur)
        guard = guard + 1
    end
    return nil
end

local function type_of(ns, name)
    return safe_call(patch.get_type, ns, name) or safe_call(patch.get_type, name)
end

-- 用 1.6.1 的 get_methods 列出某个名字的全部重载
local function list_overloads(type_handle, name)
    local out = {}
    if not (API.get_methods and API.method_name) or not type_handle then return out end
    local list = safe_call(patch.get_methods, type_handle, true)
    if type(list) ~= "table" then return out end
    for i = 1, #list do
        local m = list[i]
        if m then
            local nm = safe_call(patch.method_name, m)
            if nm == name then
                out[#out + 1] = { method = m, argc = safe_call(patch.method_param_count, m) }
            end
        end
    end
    return out
end

-- 多级回退的方法解析：参数类型 → 参数名 → 参数个数 → 不消歧 → get_methods 扫描
local function resolve_method(type_handle, name, spec)
    spec = spec or {}
    if not type_handle then return nil end

    if spec.param_types and API.get_method_by_param_types then
        local m = safe_call(patch.get_method_by_param_types, type_handle, name, spec.param_types)
        if m then return m, "param_types" end
    end
    if spec.signature and API.get_method_by_signature then
        local m = safe_call(patch.get_method_by_signature, type_handle, spec.signature)
        if m then return m, "signature" end
    end
    if spec.param_names and type(patch.get_method_by_names) == "function" then
        local m = safe_call(patch.get_method_by_names, type_handle, name, spec.param_names)
        if m then return m, "param_names" end
    end
    if spec.arities then
        for i = 1, #spec.arities do
            local m = safe_call(patch.get_method, type_handle, name, spec.arities[i])
            if m then return m, "argc=" .. tostring(spec.arities[i]) end
        end
    end
    local m = safe_call(patch.get_method, type_handle, name)
    if m then return m, "any" end
    local ov = list_overloads(type_handle, name)
    local best, best_c = nil, -1
    for i = 1, #ov do
        local c = ov[i].argc or -1
        if c > best_c then best, best_c = ov[i].method, c end
    end
    if best then return best, "scan=" .. tostring(best_c) end
    return nil, nil
end

-- 枚举一个类型的成员名（1.6.1 的 get_fields + field_name，纯元数据、不读值）
local function collect_field_names(type_handle, include_inherited)
    local names = {}
    if not (API.get_fields and API.field_name) or not type_handle then return names end
    local list = safe_call(patch.get_fields, type_handle, include_inherited and true or false)
    if type(list) ~= "table" then return names end
    for i = 1, #list do
        local nm = safe_call(patch.field_name, list[i])
        if type(nm) == "string" and nm ~= "" then names[#names + 1] = nm end
    end
    return names
end

local FIELD_NAMES = {}   -- 各 ID 类的成员名清单（!codex / !fields 用）

-- 把 invoke 返回的字符串句柄转成 Lua 字符串（两种形态都认）
local function to_lua_string(v)
    if type(v) == "string" then return v end
    if v == nil then return nil end
    local s = safe_call(patch.string_value, v)
    if type(s) == "string" then return s end
    return nil
end

-- ============================================================================
-- 5. 设置文件：读（TEFManager 写在私有目录的 config.json，形如 {"values":{...}}）
-- ============================================================================
local function parse_int(raw, key, fallback, lo, hi)
    local escaped = key:gsub("([^%w])", "%%%1")
    local value = tonumber(raw:match('"' .. escaped .. '"%s*:%s*(-?%d+)'))
    if not value then return fallback end
    value = math.floor(value)
    if lo and value < lo then value = lo end
    if hi and value > hi then value = hi end
    return value
end

local function parse_bool(raw, key, fallback)
    local escaped = key:gsub("([^%w])", "%%%1")
    local text = raw:match('"' .. escaped .. '"%s*:%s*(%a+)')
    if text == "true" then return true end
    if text == "false" then return false end
    local digit = raw:match('"' .. escaped .. '"%s*:%s*(%d+)')
    if digit then return digit ~= "0" end
    return fallback
end

local function load_config_from(raw)
    local hits = 0
    for key in pairs(DEFAULTS) do
        if raw:find('"' .. key .. '"', 1, true) then hits = hits + 1 end
    end
    if hits == 0 then return false end      -- 截断/放错文件：沿用上一次的有效值
    for key, default in pairs(DEFAULTS) do
        if type(default) == "boolean" then
            cfg[key] = parse_bool(raw, key, cfg[key])
        else
            local lim = LIMITS[key]
            cfg[key] = parse_int(raw, key, cfg[key], lim and lim[1], lim and lim[2])
        end
    end
    return true
end

local function read_config()
    local raw = mod.read_file and mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then return false end
    if not load_config_from(raw) then return false end
    last_config_raw = raw
    return true
end

-- 把当前设置写回 config.json（!save / 面板按钮），格式与 TEFManager 一致
local function save_config()
    local parts = {}
    for key, default in pairs(DEFAULTS) do
        local v = cfg[key]
        if type(v) == "boolean" then
            parts[#parts + 1] = string.format('"%s":%s', key, v and "true" or "false")
        else
            parts[#parts + 1] = string.format('"%s":%d', key, math.floor(v))
        end
    end
    table.sort(parts)
    local text = '{"values":{' .. table.concat(parts, ",") .. '}}'
    local ok = pcall(mod.write_file, "config.json", text)
    if ok then
        last_config_raw = text
        announce("设置已写回 config.json", 150, 220, 255)
    else
        announce("写回 config.json 失败（只读权限？）设置仍在本次游戏中生效", 255, 160, 120)
    end
    return ok
end

local function cfg_summary_line()
    local on = {}
    if cfg.wheel_item then on[#on + 1] = "物品" end
    if cfg.wheel_buff then on[#on + 1] = "祝福" end
    if cfg.wheel_proj then on[#on + 1] = "弹幕" end
    if cfg.wheel_npc then on[#on + 1] = "怪物" end
    if cfg.wheel_heal then on[#on + 1] = "治愈" end
    if #on == 0 then return "所有转盘都关着（用 !set wheel_item on 打开）" end
    return string.format("转盘：%s · 间隔 %d 秒 · 大满贯 %d%%",
        table.concat(on, "/"), math.floor(cfg.interval_sec), math.floor(cfg.jackpot_chance))
end

-- ============================================================================
-- 6. 万象图鉴：编号 ↔ 名字
--    英文名来自 patch.get_fields 枚举出的成员名清单（1.6.1 新 API，纯元数据）；
--    游戏内名字来自 Lang.GetItemNameValue / GetBuffName / GetNPCNameValue 的分帧扫描。
-- ============================================================================
local CODEX = {
    item = { label = "物品", zh = {}, en = {}, zh_index = {}, en_index = {}, ids = {},
             scanned = 0, max = 0, done = false, search_field = "Search", active = false },
    buff = { label = "增益", zh = {}, en = {}, zh_index = {}, en_index = {}, ids = {},
             scanned = 0, max = 0, done = false, search_field = "Search", active = false },
    npc  = { label = "生物", zh = {}, en = {}, zh_index = {}, en_index = {}, ids = {},
             scanned = 0, max = 0, done = false, search_field = "Search", active = false },
    -- 弹幕没有本地化名（Lang.GetProjectileName 返回 LocalizedText，本版不做那一跳取值），
    -- 但 IdDictionary.GetName 能给英文成员名，所以它只有 en 索引。
    proj = { label = "弹幕", zh = {}, en = {}, zh_index = {}, en_index = {}, ids = {},
             scanned = 0, max = 0, done = false, search_field = "Search", active = false, en_only = true },
}
local SCAN_ORDER = { "item", "buff", "npc", "proj" }

-- ============================================================================
-- 编号上限：ItemID / BuffID / NPCID / ProjectileID 的 Count 是 static readonly
-- （不是 const），所以可以安全读。读不到就用下面的保守值 —— 这一步是必须的：
--   * Lang.GetBuffName(id) 内部是 _buffNameCache[id].Value，**没有越界检查**；
--   * Player.AddBuff(type,..) 第一句就是 buffImmune[type]，**也没有越界检查**；
--   即 buff 编号一旦超出 BuffID.Count-1，就会在游戏侧抛 IndexOutOfRange（可能直接崩）。
-- ============================================================================
-- 保守兜底（1.4.4 实测 Count-1 = 5455/354/687/1021，这里全部取更小的安全值）
local ID_CEILING = { item = 5450, buff = 350, npc = 680, proj = 1000 }
local CEIL_CACHE = {}

local function read_ceiling(kind)
    local c = CEIL_CACHE[kind]
    if not c then
        c = { value = ID_CEILING[kind], locked = false }
        CEIL_CACHE[kind] = c
    end
    if c.locked then return c.value end

    -- ★ 实测教训：ItemID.Count / NPCID.Count / ProjectileID.Count 在手机版上是 **const** 字面量，
    --   内核读它们会打 "Cannot get pointer to const field"，拿不到值，而且属于工作区明令避免的
    --   "读 const 字段"路径（§15.3）。所以这里只在能**确证它不是 const** 时才读一次；
    --   问不出来（老加载器没有 field_is_const）就永远用保守兜底值 —— 兜底值本来就安全。
    local f = F["count_" .. kind]
    if not (f and API.field_is_const) then
        c.locked = true
        return c.value
    end
    local is_const = safe_call(patch.field_is_const, f)
    if is_const ~= false then          -- true 或 nil（判断不出来）都不读
        c.locked = true
        log_debug("万象轮盘：" .. kind .. ".Count 是 const/无法判定，改用保守上限 " .. tostring(c.value))
        return c.value
    end
    c.locked = true
    local v = safe_call(patch.get_field_value, f, nil, (kind == "buff") and "int32" or "int16")
    if type(v) == "number" and v > 1 and v <= 30000 then
        c.value = v - 1
        log_line(string.format("万象轮盘：%s 运行时上限 = %d（读自 Count，已确认非 const）", kind, c.value))
    end
    return c.value
end

-- 随机抽取用：取「设置值」与「运行时上限」的较小者
local function id_max(kind, configured)
    local ceil = read_ceiling(kind)
    local m = math.floor(configured or ceil)
    if m > ceil then m = ceil end
    if m < 1 then m = 1 end
    return m
end

-- 玩家手打编号用：只夹到运行时上限，不受设置里的"随机范围"限制
local function clamp_id(kind, id)
    id = math.floor(tonumber(id) or 0)
    if id < 1 then return nil end
    local ceil = read_ceiling(kind)
    if id > ceil then id = ceil end
    return id
end


-- 名字里的占位符（没翻译的键）不算有效名字
local function valid_name(nm)
    if type(nm) ~= "string" or nm == "" then return false end
    if nm:find("Name%.", 1) then return false end          -- ItemName.123 / BuffName.x
    if nm:find("^%s*$") then return false end
    return true
end

local function search_object(kind)
    local c = CODEX[kind]
    if not c or not F["search_" .. kind] then return nil end
    local obj = safe_call(patch.get_field_value, F["search_" .. kind], nil, "object")
    return obj
end

-- 编号 → 游戏内名字（走 Lang；失败返回 nil）
local function lang_name(kind, id)
    local m
    if kind == "item" then m = M.get_item_name
    elseif kind == "buff" then m = M.get_buff_name
    elseif kind == "npc" then m = M.get_npc_name
    else return nil end
    if not m then return nil end
    local ok, v = pcall(patch.invoke, m, id)
    if not ok then return nil end
    return to_lua_string(v)
end

-- 编号 → 英文成员名（走 IdDictionary.GetName）
local function english_name(kind, id)
    -- 弹幕只有英文名这条路，所以不受 codex_en 开关限制
    local cc = CODEX[kind]
    if not ((cfg.codex_en or (cc and cc.en_only)) and M.search_get_name) then return nil end
    local obj = search_object(kind)
    if not obj then return nil end
    local ok, v = pcall(patch.invoke, M.search_get_name, obj, id)
    if not ok then return nil end
    return to_lua_string(v)
end

local function codex_record(kind, id, nm)
    local c = CODEX[kind]
    if not valid_name(nm) then return end
    c.zh[id] = nm
    local key = nm:lower()
    if c.zh_index[key] == nil then c.zh_index[key] = id end
    c.ids[#c.ids + 1] = id
end

-- 分帧扫描：每次杂务最多处理 SCAN_BUDGET 个编号，避免卡顿
local function codex_step()
    local active = {}
    for i = 1, #SCAN_ORDER do
        local c = CODEX[SCAN_ORDER[i]]
        if c.active and not c.done then active[#active + 1] = SCAN_ORDER[i] end
    end
    if #active == 0 then return end
    local per = math.max(1, math.floor(SCAN_BUDGET / #active))
    for i = 1, #active do
        local kind = active[i]
        local c = CODEX[kind]
        local step = 0
        while step < per do
            c.scanned = c.scanned + 1
            if c.scanned > c.max then c.done = true; break end
            local id = c.scanned
            local zh = lang_name(kind, id)
            local en = english_name(kind, id)
            -- 本地化名优先；只有英文名（弹幕）时拿英文名当记录名
            local rec = valid_name(zh) and zh or (valid_name(en) and en or nil)
            if rec then codex_record(kind, id, rec) end
            if valid_name(en) then
                c.en[id] = en
                local k2 = en:lower()
                if c.en_index[k2] == nil then c.en_index[k2] = id end
            end
            step = step + 1
        end
    end
end

local function codex_start()
    if CODEX.item.active or CODEX.buff.active or CODEX.npc.active then return end   -- 已经在扫了
    if not cfg.codex_scan then
        log_once("codex_off", "万象轮盘：图鉴扫描已关闭（设置里的「建立名称词典」）——按名字取物不可用，仍可用编号")
        return
    end
    if not M.get_item_name then
        log_once("codex_nolang", "万象轮盘：取不到 Lang.GetItemNameValue，名称词典不可用（按编号玩不受影响）")
        return
    end
    -- ★ 实测教训：Lang 的名字缓存是启动后由 InitializeLegacyLocalization() 填的，
    --   没填之前 _buffNameCache[id] 还是 null，读它 = NullReferenceException。
    --   所以批量扫描前先用几个"必然存在"的编号探一下，拿不到名字就下一帧再试。
    local probe_ok = false
    local probes = { "item", "buff", "npc" }
    for i = 1, #probes do
        local k = probes[i]
        local cand = (k == "item") and { 2, 1, 3 } or ((k == "buff") and { 1, 2 } or { 1, 3 })
        for j = 1, #cand do
            if valid_name(lang_name(k, cand[j])) then probe_ok = true; break end
        end
        if probe_ok then break end
    end
    if not probe_ok then
        log_once("lang_not_ready", "万象轮盘：游戏名字表还没就绪，名称词典推迟（下一帧再试）")
        return
    end

    CODEX.item.active = true
    CODEX.item.max = id_max("item", cfg.item_id_max)
    CODEX.buff.active = true
    CODEX.buff.max = id_max("buff", cfg.buff_id_max)     -- ★ 必须先夹：GetBuffName 无越界检查
    CODEX.npc.active = true
    CODEX.npc.max = id_max("npc", cfg.npc_id_max)
    CODEX.proj.active = true
    CODEX.proj.max = id_max("proj", cfg.proj_id_max)
    log_line(string.format("万象轮盘：开始建立名称词典（物品 %d / 增益 %d / 生物 %d / 弹幕 %d，分帧进行）",
        CODEX.item.max, CODEX.buff.max, CODEX.npc.max, CODEX.proj.max))
end

local function codex_progress()
    local done, total = 0, 0
    for i = 1, #SCAN_ORDER do
        local c = CODEX[SCAN_ORDER[i]]
        done = done + math.min(c.scanned, c.max)
        total = total + c.max
    end
    if total <= 0 then return 100 end
    return math.floor(done * 100 / total)
end

local function codex_summary()
    local parts = {}
    for i = 1, #SCAN_ORDER do
        local c = CODEX[SCAN_ORDER[i]]
        parts[#parts + 1] = string.format("%s %d/%d", c.label, #c.ids, c.max)
    end
    return string.format("%s（%d%%）", table.concat(parts, " · "), codex_progress())
end

local function display_name(kind, id)
    local c = CODEX[kind]
    if c then
        local nm = c.zh[id]
        if valid_name(nm) then return nm end
        local en = c.en[id]
        if valid_name(en) then return en end
    end
    return "#" .. tostring(id)
end

local function display_name_both(kind, id)
    local c = CODEX[kind]
    local zh, en = "#" .. tostring(id), nil
    if c then
        if valid_name(c.zh[id]) then zh = c.zh[id] end
        if valid_name(c.en[id]) then en = c.en[id] end
    end
    if en and en ~= zh then return string.format("%s（%s）", zh, en) end
    return zh
end

-- 抽一个编号：词典就绪后从「有名字的有效编号」里抽，否则退化为范围内随机
local function pick_id(kind, min_id, max_id)
    local c = CODEX[kind]
    if c and #c.ids > 0 then
        return c.ids[math.random(1, #c.ids)]
    end
    return math.random(min_id or 1, math.max(min_id or 1, max_id or 100))
end

-- 精确/模糊查找：支持 名字（游戏内语言）/ 英文成员名 / 纯数字
local function find_id(kind, query)
    local c = CODEX[kind]
    if not c or type(query) ~= "string" or query == "" then return nil, nil end
    local num = tonumber(query)
    if num and num >= 1 then return math.floor(num), "编号" end
    local key = query:lower()
    if c.zh_index[key] then return c.zh_index[key], "名字" end
    if c.en_index[key] then return c.en_index[key], "英文名" end
    -- 模糊：唯一命中才算
    local hit, count = nil, 0
    for i = 1, #c.ids do
        local id = c.ids[i]
        local nm = c.zh[id] or ""
        local en = c.en[id] or ""
        if nm:lower():find(key, 1, true) or en:lower():find(key, 1, true) then
            count = count + 1
            if count == 1 then hit = id end
            if count > 1 then break end
        end
    end
    if count == 1 then return hit, "模糊" end
    return nil, (count > 1) and "多义" or nil
end

local function find_matches(kind, query, limit)
    local c = CODEX[kind]
    local out = {}
    if not c or type(query) ~= "string" or query == "" then return out end
    local key = query:lower()
    for i = 1, #c.ids do
        local id = c.ids[i]
        local nm = c.zh[id] or ""
        local en = c.en[id] or ""
        if nm:lower():find(key, 1, true) or en:lower():find(key, 1, true) then
            out[#out + 1] = { id = id, name = nm, en = en }
            if #out >= (limit or 6) then break end
        end
    end
    return out
end

-- 怪物轮的安全网：默认挡掉 Boss 与城镇 NPC（中英双语关键词）
local NPC_BLOCK = {
    "克苏鲁之眼", "世界吞噬", "骷髅王", "血肉墙", "双子", "毁灭者", "机械骷髅", "史莱姆王",
    "蜂后", "世纪之花", "石巨人", "月亮领主", "光之女皇", "猪龙鱼", "史莱姆之神", "教徒",
    "鹿角怪", "冰雪女王", "南瓜王", "哀木", "荷兰飞人", "火星", "贝琪", "暗黑魔法师", "食人魔",
    "天界柱", "日耀柱", "星旋柱", "星云柱", "星尘柱", "向导", "商人", "护士", "军火商",
    "爆破专家", "染料商", "渔夫", "酒馆老板", "机械师", "哥布林", "巫医", "巫师", "蒸汽朋克",
    "圣诞老人", "公主", "动物学家", "高尔夫", "税收官", "油漆工", "派对女孩", "发型师",
    "服装商", "海盗", "机器人", "树妖", "旅商", "骷髅商人", "老人",
    "Eye of Cthulhu", "Eater of Worlds", "Skeletron", "Wall of Flesh", "Retinazer",
    "Spazmatism", "Destroyer", "King Slime", "Queen Bee", "Plantera", "Golem", "Moon Lord",
    "Empress of Light", "Duke Fishron", "Lunatic Cultist", "Deerclops", "Queen Slime",
    "Pumpking", "Mourning Wood", "Ice Queen", "Santa-NK1", "Everscream", "Flying Dutchman",
    "Martian", "Betsy", "Dark Mage", "Ogre", "Pillar", "Guide", "Merchant", "Nurse",
    "Arms Dealer", "Demolitionist", "Dye Trader", "Angler", "Tavernkeep", "Mechanic",
    "Goblin", "Witch Doctor", "Wizard", "Steampunker", "Santa Claus", "Princess", "Zoologist",
    "Golfer", "Tax Collector", "Painter", "Party Girl", "Stylist", "Clothier", "Pirate",
    "Cyborg", "Dryad", "Traveling", "Skeleton Merchant", "Old Man",
}

local function npc_allowed(id)
    if cfg.allow_boss then return true end
    local name = display_name("npc", id)
    for i = 1, #NPC_BLOCK do
        if name:find(NPC_BLOCK[i], 1, true) then return false end
    end
    return true
end

-- 抽一个「被允许的」怪物编号（最多试 24 次，避免死循环）
local function pick_npc_id()
    for _ = 1, 24 do
        local id = pick_id("npc", 1, id_max("npc", cfg.npc_id_max))
        if npc_allowed(id) then return id end
    end
    return nil
end

-- ============================================================================
-- 7. 玩家 / 生成 / 反馈：全部沿用 26 个现成 Mod 已验证过的调用形态
-- ============================================================================
local function my_player_index()
    if F.my_player then
        local v = safe_call(patch.get_field_value, F.my_player, nil, "int32")
        if v ~= nil then return v end
    end
    if M.get_my_player then
        local v = safe_call(patch.invoke, M.get_my_player)
        if type(v) == "number" then return v end
    end
    return -1
end

local function local_player()
    if not F.main_player then return nil end
    local idx = my_player_index()
    if idx == nil or idx < 0 then return nil end
    local arr = safe_call(patch.get_field_value, F.main_player, nil, "object")
    if not arr then return nil end
    local n = safe_call(patch.array_length, arr)
    if type(n) ~= "number" or idx >= n then return nil end
    return safe_call(patch.array_at, arr, idx)
end

-- 是否已经进入世界（Main.gameMenu == false）。字段取不到时不拦（宁可照常跑）
local T_BOOL_STYLE = (mod.platform == "android") and "uint8" or "int32"
local function in_world()
    if not F.game_menu then return true end
    local v = safe_call(patch.get_field_value, F.game_menu, nil, T_BOOL_STYLE)
    if type(v) ~= "number" then return true end
    return v == 0
end

local function is_local_player(instance)
    if not instance or not F.who_am_i then return false end
    local who = safe_call(patch.get_field_value, F.who_am_i, instance, "int32")
    if who == nil then return false end
    return who == my_player_index()
end

local function player_xy(p)
    -- 注意：get_field_vec2 返回两个值，不能走 safe_call（它只回传第一个返回值）
    if not (p and F.pos) then return nil end
    local ok, x, y = pcall(patch.get_field_vec2, F.pos, p)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end

-- 给物品：Android 走 Item.NewItem(9)，桌面走 Player.QuickSpawnItem(3)
local function spawn_item(x, y, id, stack)
    id, stack = math.floor(id), math.max(1, math.floor(stack or 1))
    if mod.platform == "android" then
        if not M.new_item then return false end
        return pcall(patch.invoke, M.new_item, math.floor(x), math.floor(y), 16, 16,
            id, stack, false, 0, 0)
    end
    local p = local_player()
    if not (p and M.quick_spawn) then return false end
    return pcall(patch.invoke, M.quick_spawn, p, nil, id, stack)
end

-- 生成生物：NPC.NewNPC(10) = (source=nil, X, Y, Type, Start, ai0..3, Target)
local function spawn_npc(x, y, id)
    if not M.new_npc then return false end
    return pcall(patch.invoke, M.new_npc, nil, math.floor(x), math.floor(y), math.floor(id), 0,
        0.0, 0.0, 0.0, 0.0, 255)
end

-- 生成弹幕：实参表必须与「已解析句柄自身的参数个数」严格一致 ——
-- 1.4.4 源码里同时存在两个重载：
--   12 参 float 版 (IEntitySource, float X, float Y, float SpeedX, float SpeedY, int Type,
--                    int Damage, float KnockBack, int Owner, float ai0, float ai1, float ai2)
--   10 参 Vector2 版 (IEntitySource, Vector2 position, Vector2 velocity, int Type, int Damage,
--                    float KnockBack, int Owner, float ai0, float ai1, float ai2)
-- 往 Vector2 版里塞 float 是"实参类型错位"，可能直接崩，所以只认确定的 float 形态。
local function build_proj_args(argc, x, y, sx, sy, id, owner)
    if argc == 12 then          -- 带 source 的 float 版（1.4.4 手机/桌面都是这个）
        return { nil, x, y, sx, sy, id, 0, 0.0, owner, 0.0, 0.0, 0.0 }, 12
    elseif argc == 8 then       -- 老的无 source float 版 (X,Y,SpeedX,SpeedY,Type,Damage,KnockBack,Owner)
        return { x, y, sx, sy, id, 0, 0.0, owner }, 8
    elseif argc == 9 then       -- 无 source + ai0
        return { x, y, sx, sy, id, 0, 0.0, owner, 0.0 }, 9
    end
    return nil
end

local function spawn_projectile(x, y, sx, sy, id, owner)
    if not M.new_projectile then return false end
    local argc = M.new_projectile_argc
    if type(argc) ~= "number" then return false end
    local args, n = build_proj_args(argc, x, y, sx, sy, id, owner)
    if not args then return false end
    if n ~= argc then return false end        -- 自校验：实参个数必须等于形参个数
    return pcall(patch.invoke, M.new_projectile, table.unpack(args, 1, n))
end

-- 播放音效：SoundEngine.PlaySound(type, x, y, style, volume, pitch)
local function play_sound(id, pitch)
    if not M.play_sound then return false end
    return pcall(patch.invoke, M.play_sound, math.floor(id), -1, -1, 1, 1.0, pitch or 0.0)
end

-- 加增益：Player.AddBuff(type, time_frames, fromNetPvP)，时间按帧（60 帧 = 1 秒）
local function add_buff(id, seconds)
    local p = local_player()
    if not (p and M.add_buff) then return false end
    local frames = math.floor(seconds * 60)
    -- AddBuff 在 1.4.4 是 4 参（type, timeToAdd, quiet, foodHack）；按 get_methods 数出来的真实个数调用
    if (M.add_buff_argc or 3) >= 4 then
        return pcall(patch.invoke, M.add_buff, p, math.floor(id), frames, false, false)
    end
    return pcall(patch.invoke, M.add_buff, p, math.floor(id), frames, false)
end

local function wheel_label(kind, id, extra)
    local nm = display_name(kind, id)
    if nm:match("^#%d+$") then
        if kind == "item" then nm = string.format("[i:%d]", id) end
    end
    if extra then return string.format("%s %s", nm, extra) end
    return nm
end

-- ============================================================================
-- 8. 五个转盘
-- ============================================================================
local function fire_item(scale)
    local p = local_player()
    if not p then return false end
    local px, py = player_xy(p)
    if not px then return false end
    local count = math.max(1, math.floor(cfg.item_count * (scale or 1)))
    local first_id
    for i = 1, count do
        local id = pick_id("item", 1, id_max("item", cfg.item_id_max))
        local stack = math.random(1, math.max(1, math.min(5, math.floor(cfg.item_count))))
        if not spawn_item(px + math.random(-70, 70), py - 200 - (i - 1) * 26, id, stack) then
            log_once("item_fail", "万象轮盘：生成物品失败（Item.NewItem 句柄不可用）")
            return false
        end
        if i == 1 then first_id = id end
    end
    stats.item = stats.item + 1
    announce("天降好物：" .. wheel_label("item", first_id) ..
        (count > 1 and string.format(" 等 %d 件", count) or ""), 255, 214, 96)
    return true
end

local function fire_buff(scale)
    local id = pick_id("buff", 1, id_max("buff", cfg.buff_id_max))
    local secs = math.max(3, math.floor(cfg.buff_seconds * (scale or 1)))
    if not add_buff(id, secs) then
        log_once("buff_fail", "万象轮盘：加增益失败（Player.AddBuff 句柄不可用）")
        return false
    end
    stats.buff = stats.buff + 1
    announce(string.format("随机祝福：%s（%d 秒）", wheel_label("buff", id), secs), 150, 255, 170)
    return true
end

local function fire_proj(scale)
    local p = local_player()
    if not p then return false end
    local px, py = player_xy(p)
    if not px then return false end
    local count = math.max(1, math.floor(cfg.proj_count * (scale or 1)))
    local id = pick_id("proj", 1, id_max("proj", cfg.proj_id_max))
    local owner = my_player_index()
    if owner < 0 then owner = 255 end
    local speed = 7.0
    for i = 1, count do
        local ang = (i - 1) / count * math.pi * 2
        if not spawn_projectile(px, py - 16, math.cos(ang) * speed, math.sin(ang) * speed, id, owner) then
            log_once("proj_fail", "万象轮盘：生成弹幕失败（Projectile.NewProjectile 句柄不可用）")
            return false
        end
    end
    stats.proj = stats.proj + 1
    announce(string.format("弹幕齐射：%s ×%d", wheel_label("proj", id), count), 255, 150, 210)
    return true
end

local function fire_npc(scale)
    local p = local_player()
    if not p then return false end
    local px, py = player_xy(p)
    if not px then return false end
    local count = math.max(1, math.floor(cfg.npc_count * (scale or 1)))
    local first_id
    for i = 1, count do
        local id = pick_npc_id()
        if not id then
            announce("怪物轮：抽不到安全的生物编号（可调高 npc_id_max 或打开 allow_boss）", 255, 160, 120)
            return false
        end
        if not spawn_npc(px + math.random(-120, 120), py - 60 - (i - 1) * 24, id) then
            log_once("npc_fail", "万象轮盘：生成生物失败（NPC.NewNPC 句柄不可用）")
            return false
        end
        if i == 1 then first_id = id end
    end
    stats.npc = stats.npc + 1
    announce("怪物来袭：" .. wheel_label("npc", first_id) ..
        (count > 1 and string.format(" 等 %d 只", count) or ""), 255, 120, 120)
    return true
end

local function fire_heal(scale)
    local p = local_player()
    -- 字段句柄必须存在才读：空句柄进 IL2CPP 可能直接 abort（工作区血泪教训）
    if not p or not F.stat_life then return false end
    local percent = math.min(100, math.max(10, math.floor(cfg.heal_percent * (scale or 1))))
    local life = safe_call(patch.get_field_value, F.stat_life, p, "int32")
    local life_max = nil
    if F.stat_life_max2 then life_max = safe_call(patch.get_field_value, F.stat_life_max2, p, "int32") end
    if type(life_max) ~= "number" and F.stat_life_max then
        life_max = safe_call(patch.get_field_value, F.stat_life_max, p, "int32")
    end
    if type(life) ~= "number" or type(life_max) ~= "number" or life_max <= 0 then return false end
    local add = math.floor(life_max * percent / 100)
    local target = math.min(life_max, life + add)
    if not pcall(patch.set_field_value, F.stat_life, p, target, "int32") then
        log_once("heal_fail", "万象轮盘：写入 statLife 失败，治愈轮停用")
        return false
    end
    if F.stat_mana then
        local mana = safe_call(patch.get_field_value, F.stat_mana, p, "int32")
        local mana_max = nil
        if F.stat_mana_max2 then mana_max = safe_call(patch.get_field_value, F.stat_mana_max2, p, "int32") end
        if type(mana_max) ~= "number" and F.stat_mana_max then
            mana_max = safe_call(patch.get_field_value, F.stat_mana_max, p, "int32")
        end
        if type(mana) == "number" and type(mana_max) == "number" and mana_max > 0 then
            pcall(patch.set_field_value, F.stat_mana, p, math.min(mana_max, mana + add), "int32")
        end
    end
    stats.heal = stats.heal + 1
    announce(string.format("治愈之泉：生命 +%d（%d/%d）", target - life, target, life_max), 140, 230, 255)
    return true
end

-- 抽取音效：优先用 SoundID 里的抽奖感音效，失败就用已验证的 38（金币）
local SOUND_CANDIDATES = { 38, 12, 29, 35, 46, 55, 60, 65, 77, 84, 93, 105 }

local function fire_sound(jackpot)
    if not cfg.sound then return end
    if jackpot then
        play_sound(SOUND_CANDIDATES[math.random(1, #SOUND_CANDIDATES)], 0.8)
        play_sound(SOUND_CANDIDATES[math.random(1, #SOUND_CANDIDATES)], 0.2)
    else
        play_sound(SOUND_CANDIDATES[math.random(1, #SOUND_CANDIDATES)], math.random() * 0.5)
    end
end

local WHEELS = {
    item = fire_item,
    buff = fire_buff,
    proj = fire_proj,
    npc  = fire_npc,
    heal = fire_heal,
}

local function enabled_wheels()
    local out = {}
    if cfg.wheel_item then out[#out + 1] = "item" end
    if cfg.wheel_buff then out[#out + 1] = "buff" end
    if cfg.wheel_proj then out[#out + 1] = "proj" end
    if cfg.wheel_npc then out[#out + 1] = "npc" end
    if cfg.wheel_heal then out[#out + 1] = "heal" end
    return out
end

-- force: nil = 自动转盘；"all" = 全部开奖；其它 = 指定转盘
local function do_roll(force, quiet)
    if not ready then return end
    if not cfg.enabled then
        if force and not quiet then announce("总开关关着（设置里的 enabled）", 200, 200, 200) end
        return
    end
    local list = enabled_wheels()
    if #list == 0 then
        if force and not quiet then announce("所有转盘都关着，先开一个", 255, 160, 120) end
        return
    end

    if force and force ~= "all" and force ~= "auto" then
        local fn = WHEELS[force]
        if not fn then announce("没有这个转盘：" .. tostring(force), 255, 160, 120); return end
        stats.spins = stats.spins + 1
        fire_sound(false)
        fn(1)
        return
    end

    stats.spins = stats.spins + 1
    local jackpot = (force == "all") or (math.random(1, 100) <= math.floor(cfg.jackpot_chance))
    if jackpot then
        stats.jackpot = stats.jackpot + 1
        announce("大满贯！所有转盘同时开奖", 255, 240, 120)
        fire_sound(true)
        for i = 1, #list do WHEELS[list[i]](1) end
    else
        fire_sound(false)
        local kind = list[math.random(1, #list)]
        WHEELS[kind](1)
    end

    if cfg.debug_log then
        log_line(string.format("万象轮盘：转动 #%d（%s）%s", stats.spins,
            jackpot and "大满贯" or "单转", cfg_summary_line()))
    end
end

-- ============================================================================
-- 9. !api —— 1.6.1 新 API 体检（全部只读/自建对象，不动游戏状态）
-- ============================================================================
local function api_test_list()
    if not (API.list_create and API.list_add and API.get_basic_type) then return "不可用" end
    local int_type = safe_call(patch.get_basic_type, "int32")
    if not int_type then return "get_basic_type 失败" end
    local list = safe_call(patch.list_create, int_type, 4)
    if not list then return "list_create 失败" end
    local a = safe_call(patch.list_add, list, 7) and 1 or 0
    local b = safe_call(patch.list_add, list, 9) and 1 or 0
    local arr = safe_call(patch.list_get_array, list)
    local first = arr and safe_call(patch.array_at, arr, 0) or nil
    return string.format("可用（add %d/2，回读 %s）", a + b, tostring(first))
end

local function api_test_dict()
    if not (API.dictionary_create and API.dictionary_add and API.dictionary_get_value) then
        return "不可用"
    end
    local kt = type_of("System", "String") or safe_call(patch.get_basic_type, "string")
    local vt = safe_call(patch.get_basic_type, "int32")
    if not (kt and vt) then return "缺 System.String / int32 类型句柄" end
    local d = safe_call(patch.dictionary_create, kt, vt, 4)
    if not d then return "dictionary_create 失败" end
    local key = patch.string_create("omniwheel")
    if not key then return "string_create 失败" end
    safe_call(patch.dictionary_add, d, key, 42)
    local v = safe_call(patch.dictionary_get_value, d, key)
    local n = safe_call(patch.dictionary_length, d)
    return string.format("可用（回读 %s，长度 %s）", tostring(v), tostring(n))
end

-- struct_arg 的调用形态未验证：挨个试，谁先返回非 nil 句柄就用谁
local STRUCT_BUILDER = nil

local function probe_struct_arg()
    if not API.struct_arg then return nil, nil end
    local rt = type_of("Microsoft.Xna.Framework", "Rectangle")
    local candidates = {}
    if rt then
        candidates[#candidates + 1] = { name = "类型+序列表", fn = function(t, seq) return patch.struct_arg(t, seq) end }
        candidates[#candidates + 1] = { name = "类型+键值表", fn = function(t, kv) return patch.struct_arg(t, kv) end }
    end
    candidates[#candidates + 1] = { name = "序列表", fn = function(t, seq) return patch.struct_arg(seq) end }
    candidates[#candidates + 1] = { name = "四个数值", fn = function(t, seq) return patch.struct_arg(seq[1], seq[2], seq[3], seq[4]) end }
    for i = 1, #candidates do
        local ok, v = pcall(candidates[i].fn, rt, { 0, 0, 8, 8 }, { x = 0, y = 0, width = 8, height = 8 })
        if ok and v ~= nil then return candidates[i].fn, candidates[i].name end
    end
    return nil, nil
end

local function struct_build(ns, name, seq, kv)
    if not STRUCT_BUILDER then return nil end
    local t = type_of(ns, name)
    if not t then return nil end
    local ok, v = pcall(STRUCT_BUILDER, t, seq, kv)
    if ok then return v end
    return nil
end

-- 屏幕飘字：CombatText.NewText(Rectangle, Color, string, bool, bool)
-- 全程 pcall；任何一步失败就自动关掉这个实验模块，不再重试
try_float_text = function(text, r, g, b)
    if not cfg.float_text then return end
    if not (M.combat_text and STRUCT_BUILDER and API.invoke_value_args) then return end
    local p = local_player()
    local px, py = player_xy(p)
    if not px then return end
    local rect = struct_build("Microsoft.Xna.Framework", "Rectangle",
        { math.floor(px) - 30, math.floor(py) - 60, 60, 20 },
        { x = math.floor(px) - 30, y = math.floor(py) - 60, width = 60, height = 20 })
    local color = struct_build("Microsoft.Xna.Framework", "Color", { r, g, b, 255 },
        { r = r, g = g, b = b, a = 255 })
    local s = patch.string_create(text)
    if not (rect and color and s) then
        cfg.float_text = false
        log_warn("万象轮盘：struct_arg 造不出 Rectangle/Color，屏幕飘字已自动关闭")
        return
    end
    local argc = M.combat_text_argc or 5
    local ok = pcall(function()
        if argc >= 5 then
            patch.invoke_value_args(M.combat_text, rect, color, s, false, false)
        elseif argc == 4 then
            patch.invoke_value_args(M.combat_text, rect, color, s, false)
        else
            patch.invoke_value_args(M.combat_text, rect, color, s)
        end
    end)
    if not ok then
        cfg.float_text = false
        log_warn("万象轮盘：CombatText.NewText 调用失败，屏幕飘字已自动关闭（详情见日志）")
    end
end

-- 功能自检：把"哪个转盘因为缺句柄而不可用"一次说清楚
local function feature_report()
    local missing = {}
    if not (M.new_item or M.quick_spawn) then missing[#missing + 1] = "给物品" end
    if not M.add_buff then missing[#missing + 1] = "加增益" end
    if not M.new_projectile then missing[#missing + 1] = "生成弹幕" end
    if not M.new_npc then missing[#missing + 1] = "生成生物" end
    if not F.stat_life then missing[#missing + 1] = "治愈" end
    if not M.new_text then missing[#missing + 1] = "聊天播报" end
    if not M.play_sound then missing[#missing + 1] = "音效" end
    if #missing == 0 then
        return "功能自检：全部可用（物品 / 祝福 / 弹幕 / 怪物 / 治愈 / 播报 / 音效）"
    end
    return "功能自检：缺少 " .. table.concat(missing, "、") .. "（对应转盘会自动跳过，不影响游戏）"
end

local function api_report()
    local n, total = api_count()
    local lines = { string.format("1.6.1 新 API 体检：%d/%d 项探测可用（本模组用到的子集）", n, total) }

    if API.get_fields and T.item_id then
        FIELD_NAMES.item = FIELD_NAMES.item or collect_field_names(T.item_id, false)
        FIELD_NAMES.buff = FIELD_NAMES.buff or collect_field_names(T.buff_id, false)
        FIELD_NAMES.npc = FIELD_NAMES.npc or collect_field_names(T.npc_id, false)
        FIELD_NAMES.proj = FIELD_NAMES.proj or collect_field_names(T.proj_id, false)
        lines[#lines + 1] = string.format("get_fields：ItemID %d / BuffID %d / NPCID %d / ProjectileID %d 个成员名",
            #FIELD_NAMES.item, #FIELD_NAMES.buff, #FIELD_NAMES.npc, #FIELD_NAMES.proj)
    else
        lines[#lines + 1] = "get_fields：不可用（旧加载器？）"
    end

    if T.proj and API.get_methods then
        local ov = list_overloads(T.proj, "NewProjectile")
        local argc_text = {}
        for i = 1, math.min(#ov, 6) do argc_text[#argc_text + 1] = tostring(ov[i].argc) end
        lines[#lines + 1] = string.format("get_methods：NewProjectile 重载 %d 个（参数个数 %s）",
            #ov, #argc_text > 0 and table.concat(argc_text, "/") or "无")
    end

    lines[#lines + 1] = "list_create：" .. api_test_list()
    lines[#lines + 1] = "dictionary：" .. api_test_dict()

    if not struct_shape then
        STRUCT_BUILDER, struct_shape = probe_struct_arg()
    end
    lines[#lines + 1] = "struct_arg：" .. (struct_shape and ("可用（形态：" .. struct_shape .. "）") or "不可用/未探测到可用形态")
    lines[#lines + 1] = "invoke_value_args：" .. (API.invoke_value_args and "存在" or "不存在")
    lines[#lines + 1] = string.format("图鉴词典：%s", codex_summary())

    lines[#lines + 1] = feature_report()
    for i = 1, #lines do
        log_line("万象轮盘：" .. lines[i])
        if cfg.announce then show_chat("[万象轮盘] " .. lines[i], 200, 220, 255) end
    end
end

-- ============================================================================
-- 10. 聊天指令（前缀 !，共 18 条，含 !help）
-- ============================================================================
local KIND_ALIAS = {
    ["物品"] = "item", ["item"] = "item", ["道具"] = "item",
    ["增益"] = "buff", ["buff"] = "buff", ["祝福"] = "buff",
    ["生物"] = "npc", ["npc"] = "npc", ["怪物"] = "npc",
    ["弹幕"] = "proj", ["proj"] = "proj", ["projectile"] = "proj",
}

local last_cmd_text, last_cmd_at = nil, -10   -- 同一条指令 1 秒内只处理一次

local function split_words(text)
    local out = {}
    for w in tostring(text):gmatch("%S+") do out[#out + 1] = w end
    return out
end

local function parse_name_count(rest, default_count)
    local head, tail = tostring(rest):match("^(.-)%s+(%d+)$")
    if head and head ~= "" then return head, tonumber(tail) end
    return tostring(rest), default_count
end

local function reply(text, r, g, b)
    show_chat("[万象轮盘] " .. text, r or 230, g or 230, b or 230)
    log_debug(text)
end

local function cmd_help()
    reply("指令一览（前缀 !）", 255, 240, 160)
    reply("!roll [物品|祝福|弹幕|怪物|治愈|all] —— 立刻转一次", 215, 215, 215)
    reply("!give <名字|编号> [数量] · !buff <名字|编号> [秒]", 215, 215, 215)
    reply("!npc <名字|编号> [数量] · !proj <名字|编号> [数量] · !sound <编号>", 215, 215, 215)
    reply("!find <关键词> [物品|增益|生物] —— 按名字搜索", 215, 215, 215)
    reply("!fields <关键词> —— 搜索英文成员名（1.6.1 新 API）", 215, 215, 215)
    reply("!auto on|off · !stat · !codex · !cfg · !set <键> <值> · !save · !reload", 215, 215, 215)
    reply("!api —— 新 API 体检 · !gui on|off —— 游戏内面板（实验性）", 215, 215, 215)
end

local function cmd_find(kind, query)
    local hits = find_matches(kind, query, 6)
    if #hits == 0 then
        reply(string.format("没找到含「%s」的%s（词典 %s）", query, CODEX[kind].label, codex_summary()), 255, 180, 150)
        return
    end
    reply(string.format("含「%s」的%s（最多列 6 条）：", query, CODEX[kind].label), 200, 230, 255)
    for i = 1, #hits do
        local h = hits[i]
        if h.en ~= "" and h.en ~= h.name then
            reply(string.format("· %s（%s）→ 编号 %d", h.name, h.en, h.id), 210, 210, 210)
        else
            reply(string.format("· %s → 编号 %d", h.name, h.id), 210, 210, 210)
        end
    end
end

local function cmd_fields(query)
    if not (API.get_fields and API.field_name) then
        reply("本加载器没有 patch.get_fields（1.6.1 才有），无法搜索成员名", 255, 180, 150)
        return
    end
    FIELD_NAMES.item = FIELD_NAMES.item or collect_field_names(T.item_id, false)
    FIELD_NAMES.buff = FIELD_NAMES.buff or collect_field_names(T.buff_id, false)
    FIELD_NAMES.npc = FIELD_NAMES.npc or collect_field_names(T.npc_id, false)
    local key = tostring(query):lower()
    local shown = 0
    for _, pair in ipairs({ { "ItemID", FIELD_NAMES.item }, { "BuffID", FIELD_NAMES.buff }, { "NPCID", FIELD_NAMES.npc } }) do
        local label, list = pair[1], pair[2]
        for i = 1, #list do
            if list[i]:lower():find(key, 1, true) then
                reply(string.format("· %s.%s", label, list[i]), 210, 210, 210)
                shown = shown + 1
                if shown >= 8 then return end
                break
            end
        end
    end
    if shown == 0 then reply("成员名里没有含「" .. tostring(query) .. "」的（这是 1.6.1 get_fields 扫出来的英文名）", 255, 180, 150) end
end

local function cmd_set(key, value)
    if not key or DEFAULTS[key] == nil then
        reply("未知设置项：" .. tostring(key) .. "（用 !cfg 看全部键名）", 255, 180, 150)
        return
    end
    if type(DEFAULTS[key]) == "boolean" then
        local v = tostring(value or ""):lower()
        if v == "on" or v == "true" or v == "1" or v == "开" then cfg[key] = true
        elseif v == "off" or v == "false" or v == "0" or v == "关" then cfg[key] = false
        else reply("这个开关只认 on/off", 255, 180, 150); return end
    else
        local n = tonumber(value)
        if not n then reply("这个设置要填数字", 255, 180, 150); return end
        local lim = LIMITS[key]
        n = math.floor(n)
        if lim then n = math.max(lim[1], math.min(lim[2], n)) end
        cfg[key] = n
    end
    reply(string.format("已设置 %s = %s（!save 可写回文件）", key, tostring(cfg[key])), 150, 255, 170)
end

local function cmd_cfg()
    reply("当前设置（!set <键> <值> 可改）", 255, 240, 160)
    reply(string.format("enabled=%s interval_sec=%d jackpot_chance=%d announce=%s sound=%s",
        tostring(cfg.enabled), math.floor(cfg.interval_sec), math.floor(cfg.jackpot_chance),
        tostring(cfg.announce), tostring(cfg.sound)), 210, 210, 210)
    reply(string.format("wheel_item=%s(%d个) wheel_buff=%s(%d秒) wheel_proj=%s(%d发)",
        tostring(cfg.wheel_item), math.floor(cfg.item_count), tostring(cfg.wheel_buff),
        math.floor(cfg.buff_seconds), tostring(cfg.wheel_proj), math.floor(cfg.proj_count)), 210, 210, 210)
    reply(string.format("wheel_npc=%s(%d只,上限%d) allow_boss=%s wheel_heal=%s(%d%%)",
        tostring(cfg.wheel_npc), math.floor(cfg.npc_count), math.floor(cfg.npc_id_max),
        tostring(cfg.allow_boss), tostring(cfg.wheel_heal), math.floor(cfg.heal_percent)), 210, 210, 210)
    reply(string.format("codex_scan=%s codex_en=%s hot_reload=%s gui_panel=%s debug_log=%s",
        tostring(cfg.codex_scan), tostring(cfg.codex_en), tostring(cfg.hot_reload),
        tostring(cfg.gui_panel), tostring(cfg.debug_log)), 210, 210, 210)
end

local function cmd_stat()
    reply(string.format("已转动 %d 次（大满贯 %d 次）· 物品 %d / 祝福 %d / 弹幕 %d / 怪物 %d / 治愈 %d",
        stats.spins, stats.jackpot, stats.item, stats.buff, stats.proj, stats.npc, stats.heal), 255, 240, 160)
    reply("图鉴：" .. codex_summary(), 210, 210, 210)
end

local function cmd_give(rest)
    local name, count = parse_name_count(rest, 1)
    count = math.max(1, math.min(999, math.floor(count or 1)))
    local id, how = find_id("item", name)
    if id then id = clamp_id("item", id) end
    if not id then
        reply(string.format("找不到物品「%s」（%s；用 !find 搜名字，或直接给编号）", name,
            how == "多义" and "有多个同名候选" or "词典 " .. codex_summary()), 255, 180, 150)
        return
    end
    local p = local_player()
    local px, py = player_xy(p)
    if not px then reply("取不到玩家坐标", 255, 180, 150); return end
    if not spawn_item(px, py - 40, id, count) then reply("生成物品失败（NewItem 句柄不可用）", 255, 180, 150); return end
    reply(string.format("已给予 %s ×%d（%s命中）", display_name_both("item", id), count, tostring(how)), 150, 255, 170)
end

local function cmd_buff(rest)
    local name, secs = parse_name_count(rest, math.floor(cfg.buff_seconds))
    secs = math.max(1, math.min(36000, math.floor(secs or 30)))
    local id, how = find_id("buff", name)
    if not id then reply(string.format("找不到增益「%s」（用 !find %s 增益）", name, name), 255, 180, 150); return end
    id = clamp_id("buff", id)
    if not id then reply("增益编号无效或超出运行时上限", 255, 180, 150); return end
    if not add_buff(id, secs) then reply("加增益失败（AddBuff 句柄不可用）", 255, 180, 150); return end
    reply(string.format("已添加 %s，%d 秒（%s命中）", display_name_both("buff", id), secs, tostring(how)), 150, 255, 170)
end

local function cmd_npc(rest)
    local name, count = parse_name_count(rest, 1)
    count = math.max(1, math.min(20, math.floor(count or 1)))
    local id, how = find_id("npc", name)
    if not id then reply(string.format("找不到生物「%s」（用 !find %s 生物）", name, name), 255, 180, 150); return end
    id = clamp_id("npc", id)
    if not id then reply("生物编号无效或超出运行时上限", 255, 180, 150); return end
    if not cfg.allow_boss and not npc_allowed(id) then
        reply("这个生物在 Boss/城镇名单里，被 allow_boss=off 挡下了（!set allow_boss on 可放行）", 255, 180, 150)
        return
    end
    local p = local_player()
    local px, py = player_xy(p)
    if not px then reply("取不到玩家坐标", 255, 180, 150); return end
    for i = 1, count do
        if not spawn_npc(px + (i - 1) * 24 - 24, py - 40, id) then
            reply("生成生物失败（NewNPC 句柄不可用）", 255, 180, 150); return
        end
    end
    reply(string.format("已生成 %s ×%d（%s命中）", display_name_both("npc", id), count, tostring(how)), 150, 255, 170)
end

local function cmd_proj(rest)
    local name, count = parse_name_count(rest, 4)
    count = math.max(1, math.min(40, math.floor(count or 4)))
    local id, how = find_id("proj", name)
    if not id then
        reply(string.format("找不到弹幕「%s」（弹幕只有英文成员名；可用 !find %s 弹幕 搜，或直接给编号）",
            name, name), 255, 180, 150)
        return
    end
    local p = local_player()
    local px, py = player_xy(p)
    if not px then reply("取不到玩家坐标", 255, 180, 150); return end
    local owner = my_player_index()
    if owner < 0 then owner = 255 end
    for i = 1, count do
        local ang = (i - 1) / count * math.pi * 2
        spawn_projectile(px, py - 16, math.cos(ang) * 7.0, math.sin(ang) * 7.0, math.floor(id), owner)
    end
    reply(string.format("已发射 %s ×%d（%s命中）", display_name_both("proj", id), count, tostring(how)), 150, 255, 170)
end

local function handle_command(raw)
    if type(raw) ~= "string" then return end
    local text = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, 1) ~= "!" then return end
    local body = text:sub(2)
    local cmd, rest = body:match("^(%S+)%s*(.*)$")
    if not cmd then return end
    cmd = cmd:lower()
    rest = rest or ""

    -- 同一条指令 1 秒内只处理一次（单机 + 多人两个 Hook 可能都触发）
    local now = now_seconds()
    if last_cmd_text == text and (now - last_cmd_at) <= 1 then return end
    last_cmd_text, last_cmd_at = text, now

    if cmd == "help" or cmd == "h" or cmd == "?" then cmd_help()
    elseif cmd == "roll" or cmd == "r" then
        local arg = rest ~= "" and (KIND_ALIAS[rest:lower()] or rest:lower()) or nil
        do_roll(arg or "auto")
    elseif cmd == "auto" then
        local v = rest:lower()
        if v == "on" or v == "开" then cfg.enabled = true
        elseif v == "off" or v == "关" then cfg.enabled = false end
        reply("自动转盘：" .. (cfg.enabled and "开" or "关") .. "（" .. cfg_summary_line() .. "）", 150, 255, 170)
    elseif cmd == "stat" then cmd_stat()
    elseif cmd == "codex" then
        reply("图鉴：" .. codex_summary(), 200, 230, 255)
        reply(string.format("成员名清单（1.6.1 get_fields）：ItemID %d / BuffID %d / NPCID %d / ProjectileID %d",
            #(FIELD_NAMES.item or {}), #(FIELD_NAMES.buff or {}), #(FIELD_NAMES.npc or {}), #(FIELD_NAMES.proj or {})), 200, 230, 255)
        reply("用 !find <关键词> 按游戏内名字搜索，用 !fields <关键词> 搜英文成员名", 200, 230, 255)
    elseif cmd == "find" then
        local words = split_words(rest)
        if #words == 0 then reply("用法：!find <关键词> [物品|增益|生物]", 255, 180, 150); return end
        local kind = KIND_ALIAS[words[#words]:lower()]
        if kind and #words > 1 then table.remove(words) end
        cmd_find(kind or "item", table.concat(words, " "))
    elseif cmd == "fields" then
        if rest == "" then reply("用法：!fields <关键词>（搜 ItemID/BuffID/NPCID 的英文成员名）", 255, 180, 150); return end
        cmd_fields(rest)
    elseif cmd == "give" or cmd == "item" then cmd_give(rest)
    elseif cmd == "buff" then cmd_buff(rest)
    elseif cmd == "npc" or cmd == "spawn" then cmd_npc(rest)
    elseif cmd == "proj" then cmd_proj(rest)
    elseif cmd == "sound" then
        local id = tonumber(rest)
        if not id then reply("用法：!sound <编号>", 255, 180, 150); return end
        play_sound(id, 0.0)
        reply("已播放音效 " .. math.floor(id), 150, 255, 170)
    elseif cmd == "cfg" then cmd_cfg()
    elseif cmd == "set" then
        local key, value = rest:match("^(%S+)%s*(%S*)$")
        cmd_set(key, value)
    elseif cmd == "save" then save_config()
    elseif cmd == "reload" then
        if read_config() then reply("已重读设置：" .. cfg_summary_line(), 150, 255, 170)
        else reply("没有读到 config.json（用 TEFManager 的设置页改完再试）", 255, 180, 150) end
    elseif cmd == "api" then
        api_report()
        if API.get_method_by_param_types and T.player then
            local probes = { { "Int32", "Int32", "Boolean" }, { "System.Int32", "System.Int32", "System.Boolean" }, { "int", "int", "bool" } }
            local hit = nil
            for i = 1, #probes do
                if safe_call(patch.get_method_by_param_types, T.player, "AddBuff", probes[i]) then
                    hit = table.concat(probes[i], ","); break
                end
            end
            reply("get_method_by_param_types：" .. (hit and ("可用（AddBuff 类型串 " .. hit .. "）") or "存在但类型串未命中（不影响功能）"), 200, 230, 255)
        end
        if API.get_method_by_signature and T.proj then
            local probes = { "NewProjectile", "Projectile.NewProjectile" }
            local hit = nil
            for i = 1, #probes do
                if safe_call(patch.get_method_by_signature, T.proj, probes[i]) then hit = probes[i]; break end
            end
            reply("get_method_by_signature：" .. (hit and ("可用（命中 " .. hit .. "）") or "存在但签名串未命中（不影响功能）"), 200, 230, 255)
        end
        if API.get_full_name then
            reply(string.format("get_full_name/get_namespace：%s / %s",
                tostring(safe_call(patch.get_full_name, T.player)), tostring(safe_call(patch.get_namespace, T.player))), 200, 230, 255)
        end
    elseif cmd == "gui" then
        local v = rest:lower()
        if v == "on" then cfg.gui_panel = true
        elseif v == "off" then cfg.gui_panel = false end
        reply("游戏内面板：" .. (cfg.gui_panel and "开（实验性，若闪退请 !set gui_panel off）" or "关"), 150, 255, 170)
    else
        reply("未知指令 !" .. cmd .. "（!help 看全部）", 255, 180, 150)
    end
end

local function read_message_text(message)
    if not message then return nil end
    if M.get_text then
        local s = safe_call(patch.invoke, M.get_text, message)
        local v = to_lua_string(s)
        if v then return v end
    end
    if F.msg_text then
        return safe_call(patch.get_field_value, F.msg_text, message, "string")
    end
    return nil
end

local function on_process_incoming(instance, args, result)
    if not ready or not cfg.chat_cmd or not args then return end
    local my = my_player_index()
    local cid = args[2]
    if my >= 0 and type(cid) == "number" and cid ~= my then return end
    local text = read_message_text(args[1])
    if text then handle_command(text) end
end

local function on_send_from_client(instance, args, result)
    if not ready or not cfg.chat_cmd or not args then return end
    local text = read_message_text(args[1])
    if text then handle_command(text) end
end

-- ============================================================================
-- 11. 逐帧杂务：设置热重载 / 图鉴分帧扫描 / 自动转盘
-- ============================================================================
local scan_done_logged = false

local function on_reset_effects(instance, args, result)
    if not ready or not instance then return end
    frame_total = frame_total + 1

    -- ★ 实测教训：模组是在游戏启动早期加载的，那时聊天系统等都还没建好。
    --   所以在"进入世界"之前一个游戏方法都不调用；进世界后的第一帧才做首次引导。
    if not in_world() then return end
    if not bootstrapped then bootstrap_in_world(); return end

    if F.who_am_i and not is_local_player(instance) then return end

    frame_counter = frame_counter + 1
    if frame_counter < TICK_FRAMES then return end
    frame_counter = 0

    -- 1) 设置热重载
    if cfg.hot_reload then
        local raw = mod.read_file and mod.read_file("config.json")
        if type(raw) == "string" and raw ~= "" and raw ~= last_config_raw then
            if load_config_from(raw) then
                last_config_raw = raw
                announce("设置已更新：" .. cfg_summary_line(), 150, 220, 255)
            end
        end
    end

    -- 2) 图鉴分帧扫描（进世界后先空转约 2 秒让游戏安顿好；没在扫就补启动）
    if cfg.codex_scan and frame_total >= bootstrap_frame + CODEX_WARMUP_FRAMES then
        if not (CODEX.item.active or CODEX.buff.active or CODEX.npc.active) then codex_start() end
        codex_step()
        local all_done = CODEX.item.done and CODEX.buff.done and CODEX.npc.done
        if all_done and not scan_done_logged then
            scan_done_logged = true
            log_line("万象轮盘：名称词典建立完成 —— " .. codex_summary())
        end
    end

    -- 3) 自动转盘
    if cfg.enabled then
        local now = now_seconds()
        if last_roll_at == 0 then last_roll_at = now end
        if now - last_roll_at >= math.floor(cfg.interval_sec) then
            last_roll_at = now
            do_roll(nil, true)
        end
    else
        last_roll_at = now_seconds()
    end
end

-- ============================================================================
-- 12. 游戏内面板（mod.gui，1.4.2 起就有但 26 个现成 Mod 都没用过 —— 实验性，默认关）
-- ============================================================================
local function gui_bool(g, label, key)
    if type(g.checkbox) ~= "function" then return end
    local ok, v = pcall(g.checkbox, label, cfg[key])
    if ok and type(v) == "boolean" then cfg[key] = v end
end

local function gui_int(g, label, key, lo, hi)
    if type(g.slider) ~= "function" then return end
    local ok, v = pcall(g.slider, label, cfg[key], lo, hi)
    if ok and type(v) == "number" then cfg[key] = math.max(lo, math.min(hi, math.floor(v))) end
end

local function gui_same_line(g)
    if type(g.same_line) == "function" then pcall(g.same_line) end
end

function on_gui()
    if not ready or not cfg.gui_panel then return end
    local g = mod.gui
    if type(g) ~= "table" then return end
    local ok, err = pcall(function()
        if type(g.text) == "function" then g.text("万象轮盘 v" .. tostring(mod.meta.version)) end
        if type(g.text) == "function" then
            g.text(string.format("转动 %d 次 · 大满贯 %d · 物品%d 祝福%d 弹幕%d 怪物%d 治愈%d",
                stats.spins, stats.jackpot, stats.item, stats.buff, stats.proj, stats.npc, stats.heal))
        end
        gui_bool(g, "总开关（自动转盘）", "enabled")
        gui_bool(g, "物品轮", "wheel_item"); gui_same_line(g)
        gui_bool(g, "祝福轮", "wheel_buff")
        gui_bool(g, "弹幕轮", "wheel_proj"); gui_same_line(g)
        gui_bool(g, "怪物轮（危险）", "wheel_npc")
        gui_bool(g, "治愈轮", "wheel_heal"); gui_same_line(g)
        gui_bool(g, "聊天栏播报", "announce")
        gui_int(g, "间隔（秒）", "interval_sec", 5, 600)
        gui_int(g, "大满贯概率（%）", "jackpot_chance", 0, 50)
        gui_int(g, "物品数量", "item_count", 1, 20)
        gui_int(g, "祝福时长（秒）", "buff_seconds", 3, 600)
        gui_int(g, "弹幕数量", "proj_count", 1, 30)
        gui_int(g, "治愈比例（%）", "heal_percent", 10, 100)
        gui_bool(g, "允许 Boss 级生物", "allow_boss")
        if type(g.separator) == "function" then pcall(g.separator) end
        if type(g.button) == "function" then
            local ok1, b1 = pcall(g.button, "立刻转一次")
            if ok1 and b1 then do_roll("all") end
            gui_same_line(g)
            local ok2, b2 = pcall(g.button, "保存设置")
            if ok2 and b2 then save_config() end
            gui_same_line(g)
            local ok3, b3 = pcall(g.button, "重读设置")
            if ok3 and b3 then read_config() end
        end
        if type(g.text) == "function" then g.text("图鉴：" .. codex_summary()) end
        if type(g.progress_bar) == "function" then pcall(g.progress_bar, codex_progress() / 100) end
    end)
    if not ok and not gui_error_logged then
        gui_error_logged = true
        cfg.gui_panel = false
        log_warn("万象轮盘：mod.gui 调用出错，面板已自动关闭（" .. tostring(err) .. "）")
    end
end

mod.on_gui = on_gui

-- ============================================================================
-- 13. 句柄解析 + 生命周期
-- ============================================================================
-- Projectile.NewProjectile 的 float 版形参类型串（加载器认哪种拼写未知，逐个试）
local PROJ_FLOAT_TYPES = {
    { "IEntitySource", "Single", "Single", "Single", "Single", "Int32", "Int32", "Single", "Int32", "Single", "Single", "Single" },
    { "Terraria.DataStructures.IEntitySource", "System.Single", "System.Single", "System.Single", "System.Single",
      "System.Int32", "System.Int32", "System.Single", "System.Int32", "System.Single", "System.Single", "System.Single" },
    { "IEntitySource", "float", "float", "float", "float", "int", "int", "float", "int", "float", "float", "float" },
}

local function save_hook(method, spec, label)
    if not method then
        log_warn("万象轮盘：钩子未安装(" .. label .. ")：方法句柄为空")
        return false
    end
    local ok, hook = pcall(patch.install_hook, method, spec)
    if not ok then
        log_warn("万象轮盘：钩子未安装(" .. label .. ")：" .. tostring(hook))
        return false
    end
    hooks[#hooks + 1] = { label = label, handle = hook }
    return true
end

local function resolve_all()
    T.player = type_of("Terraria", "Player")
    T.main = type_of("Terraria", "Main")
    T.item = type_of("Terraria", "Item")
    T.npc = type_of("Terraria", "NPC")
    T.proj = type_of("Terraria", "Projectile")
    T.sound = type_of("Terraria.Audio", "SoundEngine")
    T.lang = type_of("Terraria", "Lang")
    T.chat_msg = type_of("Terraria.Chat", "ChatMessage")
    T.chat_proc = type_of("Terraria.Chat", "ChatCommandProcessor")
    T.chat_helper = type_of("Terraria.Chat", "ChatHelper")
    T.combat_text = type_of("Terraria", "CombatText")
    -- IdDictionary 在 ReLogic.Reflection（ItemID.cs 头部就是 using ReLogic.Reflection;），
    -- 顺手也试 Terraria.ID 以防不同版本搬家
    T.iddict = type_of("ReLogic.Reflection", "IdDictionary") or type_of("Terraria.ID", "IdDictionary")
    T.item_id = type_of("Terraria.ID", "ItemID")
    T.buff_id = type_of("Terraria.ID", "BuffID")
    T.npc_id = type_of("Terraria.ID", "NPCID")
    T.proj_id = type_of("Terraria.ID", "ProjectileID")

    if T.main then
        F.main_player = find_field(T.main, "player")
        F.my_player = find_field(T.main, "myPlayer")
        F.game_menu = find_field(T.main, "gameMenu")
        M.get_my_player = resolve_method(T.main, "get_myPlayer", { arities = { 0 } })
        -- 只挑"我们确定能按正确个数调用"的重载；平台偏好在前，但实参个数一律等于句柄的形参个数
        local order = (mod.platform == "android") and { 5, 4, 3 } or { 4, 5, 3 }
        for i = 1, #order do
            local m = safe_call(patch.get_method, T.main, "NewText", order[i])
            if m then M.new_text, M.new_text_argc = m, order[i]; break end
        end
        if not M.new_text then
            local any = safe_call(patch.get_method, T.main, "NewText")
            if any then
                M.new_text = any
                local c = safe_call(patch.method_param_count, any)
                M.new_text_argc = (type(c) == "number" and c) or 4
            end
        end
        if M.new_text then
            log_debug(string.format("Main.NewText：按 %d 参调用（重载 %d 个）",
                M.new_text_argc or -1, #list_overloads(T.main, "NewText")))
        end
    end
    if T.player then
        F.pos = find_field(T.player, "position")
        F.width = find_field(T.player, "width")
        F.height = find_field(T.player, "height")
        F.who_am_i = find_field(T.player, "whoAmI")
        F.stat_life = find_field(T.player, "statLife")
        F.stat_life_max = find_field(T.player, "statLifeMax")
        F.stat_life_max2 = find_field(T.player, "statLifeMax2")
        F.stat_mana = find_field(T.player, "statMana")
        F.stat_mana_max = find_field(T.player, "statManaMax")
        F.stat_mana_max2 = find_field(T.player, "statManaMax2")
        M.add_buff = resolve_method(T.player, "AddBuff", { arities = { 4, 3 } })
        do
            local ov = list_overloads(T.player, "AddBuff")
            local best = -1
            for i = 1, #ov do
                local c = ov[i].argc or -1
                if c > best and c <= 4 then best = c end
            end
            if best >= 3 then M.add_buff_argc = best end
        end
        M.quick_spawn = resolve_method(T.player, "QuickSpawnItem",
            { param_names = { "source", "item", "stack" }, arities = { 3 } })
    end
    if T.item then
        M.new_item = resolve_method(T.item, "NewItem", { arities = { 9 } })
    end
    if T.npc then
        M.new_npc = resolve_method(T.npc, "NewNPC", {
            arities = { 10 },
            param_names = { "source", "X", "Y", "Type", "Start", "ai0", "ai1", "ai2", "ai3", "Target" },
        })
    end
    if T.proj then
        -- 一律以「句柄自身的参数个数」为准，绝不拿别的来源的数字去拼实参表
        local ov = list_overloads(T.proj, "NewProjectile")
        local counts = {}
        for i = 1, #ov do counts[#counts + 1] = tostring(ov[i].argc) end
        local pinned = nil
        if API.get_method_by_param_types then
            for i = 1, #PROJ_FLOAT_TYPES do
                local m = safe_call(patch.get_method_by_param_types, T.proj, "NewProjectile", PROJ_FLOAT_TYPES[i])
                if m then
                    local c = safe_call(patch.method_param_count, m)
                    if type(c) == "number" and build_proj_args(c, 0, 0, 0, 0, 1, 0) then
                        pinned, M.new_projectile_argc = m, c
                        log_line(string.format("万象轮盘：Projectile.NewProjectile 用类型串钉死为 %d 参 float 版", c))
                        break
                    end
                end
            end
        end
        if not pinned then
            for _, argc in ipairs({ 12, 8, 9 }) do
                if build_proj_args(argc, 0, 0, 0, 0, 1, 0) then
                    local m = safe_call(patch.get_method, T.proj, "NewProjectile", argc)
                    if m then pinned, M.new_projectile_argc = m, argc; break end
                end
            end
        end
        M.new_projectile = pinned
        if pinned then
            log_debug(string.format("Projectile.NewProjectile：按 %d 参调用（同名重载 %d 个：%s）",
                M.new_projectile_argc, #ov, table.concat(counts, "/")))
        else
            -- 参数个数不认识（例如只有 10 参 Vector2 版）→ 宁可不生成，也不乱传实参
            log_warn("万象轮盘：Projectile.NewProjectile 只找到参数个数 " ..
                (#counts > 0 and table.concat(counts, "/") or "未知") ..
                " 的重载，形态无法确定 —— 弹幕轮与 !proj 自动关闭（其余功能不受影响）")
        end
    end
    if T.sound then
        M.play_sound = resolve_method(T.sound, "PlaySound", { arities = { 6 } })
    end
    if T.lang then
        M.get_item_name = resolve_method(T.lang, "GetItemNameValue", { arities = { 1 } })
        M.get_buff_name = resolve_method(T.lang, "GetBuffName", { arities = { 1 } })
        M.get_npc_name = resolve_method(T.lang, "GetNPCNameValue", { arities = { 1 } })
    end
    if T.iddict then
        M.search_get_name = resolve_method(T.iddict, "GetName", { arities = { 1 } })
    end
    if T.combat_text then
        M.combat_text = resolve_method(T.combat_text, "NewText", { arities = { 5, 4, 3 } })
        local ov = list_overloads(T.combat_text, "NewText")
        local best = -1
        for i = 1, #ov do
            local c = ov[i].argc or -1
            if c > best and c <= 5 then best = c end
        end
        if best >= 3 then M.combat_text_argc = best end
    end
    if T.chat_msg then
        M.get_text = resolve_method(T.chat_msg, "get_Text", { arities = { 0 } })
        F.msg_text = find_field(T.chat_msg, "<Text>k__BackingField")
    end
    -- 四个 ID 类的 Search（非 const 静态字段，指向 IdDictionary）
    if T.item_id then F.search_item = find_field(T.item_id, "Search"); F.count_item = find_field(T.item_id, "Count") end
    if T.buff_id then F.search_buff = find_field(T.buff_id, "Search"); F.count_buff = find_field(T.buff_id, "Count") end
    if T.npc_id then F.search_npc = find_field(T.npc_id, "Search"); F.count_npc = find_field(T.npc_id, "Count") end
    if T.proj_id then F.search_proj = find_field(T.proj_id, "Search"); F.count_proj = find_field(T.proj_id, "Count") end
end

function setup()
    log_line("万象轮盘：阶段 1/4 —— 读设置（config.json）")
    read_config()
    if has_os_time then pcall(math.randomseed, os.time()) end

    log_line("万象轮盘：阶段 2/4 —— 解析类型/字段/方法句柄（只做元数据查询，不调用任何游戏方法）")
    resolve_all()

    if not T.player or not T.main then
        log_error("万象轮盘：找不到 Terraria.Player / Terraria.Main，模组未启用")
        return
    end
    if not F.main_player then
        log_error("万象轮盘：找不到 Main.player，模组未启用")
        return
    end
    if not M.new_text then
        log_warn("万象轮盘：Main.NewText 解析失败，聊天栏播报与指令回执不可用")
    end

    log_line("万象轮盘：阶段 3/4 —— 安装钩子")
    -- 聊天指令：单机走 ProcessIncomingMessage，多人再挂一个 SendChatMessageFromClient
    -- （钩子常驻，回调里按 cfg.chat_cmd 早退，于是 !set chat_cmd on/off 能当场生效）
    local proc = T.chat_proc and resolve_method(T.chat_proc, "ProcessIncomingMessage", { arities = { 2 } })
    if not save_hook(proc, { postfix = on_process_incoming }, "ChatCommandProcessor.ProcessIncomingMessage") then
        log_warn("万象轮盘：聊天指令 Hook 未挂上，聊天指令不可用（自动转盘不受影响）")
    end
    local send = T.chat_helper and resolve_method(T.chat_helper, "SendChatMessageFromClient", { arities = { 1 } })
    save_hook(send, { postfix = on_send_from_client }, "ChatHelper.SendChatMessageFromClient")

    -- 逐帧：热重载 + 图鉴扫描 + 自动转盘
    local tick_ok = save_hook(resolve_method(T.player, "ResetEffects", { arities = { 0 } }),
        { postfix = on_reset_effects }, "Player.ResetEffects")

    ready = true

    local n, total = api_count()
    log_line(string.format("万象轮盘 v%s 加载完成（新 API %d/%d，钩子 %d 个）：%s",
        tostring(mod.meta.version), n, total, #hooks, cfg_summary_line()))
    if not tick_ok then
        log_warn("万象轮盘：Player.ResetEffects 未挂上 —— 自动转盘/热重载不可用，!roll 手动开奖仍可用")
    end
    log_line("万象轮盘：阶段 4/4 —— 等待进入世界。" ..
        "（播报、图鉴扫描、生成类调用一律推迟到进世界后的第一帧，避免在游戏还没准备好时调用游戏方法）")
end

-- 进世界后的第一次杂务：到这里才碰游戏方法（Main.NewText / Lang.* / 生成类）
bootstrap_in_world = function()
    if bootstrapped or not ready then return end
    bootstrapped = true
    bootstrap_frame = frame_total
    log_line("万象轮盘：已进入世界 —— 首次播报，图鉴扫描约 2 秒后开始")
    last_roll_at = now_seconds()
    if cfg.announce and M.new_text then
        show_chat(string.format("[万象轮盘] 已就绪：%s（!help 看指令）", cfg_summary_line()), 255, 240, 160)
    end
end

function cleanup()
    ready = false
    for i = #hooks, 1, -1 do
        local h = hooks[i]
        hooks[i] = nil
        if h and h.handle then pcall(h.handle.remove, h.handle) end
    end
    T, F, M, FM = {}, {}, {}, {}
    for i = 1, #SCAN_ORDER do
        local c = CODEX[SCAN_ORDER[i]]
        c.zh, c.en, c.zh_index, c.en_index, c.ids = {}, {}, {}, {}, {}
        c.scanned, c.done, c.active = 0, false, false
    end
    frame_counter, frame_total, last_roll_at = 0, 0, 0
    bootstrapped = false
    bootstrap_frame = 0
    for k in pairs(CEIL_CACHE) do CEIL_CACHE[k] = nil end
    LOG_RING = {}
    log_line("万象轮盘：已卸载")
end

mod.cleanup = cleanup
todo_list = { "setup" }
