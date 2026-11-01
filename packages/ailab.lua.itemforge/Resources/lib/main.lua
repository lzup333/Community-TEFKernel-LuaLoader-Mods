-- ============================================================================
-- 属性工坊 (ItemForge)  v2.0.0          pkg_id = ailab.lua.itemforge
-- 适用：Terraria Mobile 1.4.5.8 + TEFKernel + LuaLoader 1.6.3
--
-- 功能：在 TEFManager 的「模组设置」里，按物品分类调整各项属性的倍率。
--
--   分类（按优先级判定，一个物品只属于一类）：
--     镐子 / 斧头 / 锤子 / 放置类 / 近战 / 远程(含弹药) / 魔法 / 召唤 / 钓竿 / 其他
--   属性（能调的分类才出现对应设置项）：
--     使用速度 useTime + useAnimation 同步缩放（越大越快，受 min_use_time 下限保护）
--     伤害 damage / 击退 knockBack / 暴击 crit / 大小 scale / 弹速 shootSpeed
--     魔力消耗 mana / 工具力 pick·axe·hammer / 钓鱼力 fishingPole / 放置范围 tileBoost
--     弹幕体型（近战·远程·魔法·召唤武器射出的弹幕，按「物品→弹幕类型」映射）
--     经济：堆叠上限 maxStack / 售价 value / 稀有度 rare（全物品倍率）
--     自动连用 autoReuse（工具/武器/放置类各一个总开关）
--     无限使用 consumable=false（放置类 + 药水/炸弹/召唤物/材料/其他五个分类开关）
--     最高词缀（best_prefix，调 Item.Prefix(最后一档前缀)）
--     研究自动解锁（research_unlock，走 ItemsSacrificedUnlocksTracker）
--
-- 【为什么这样最快】只在**物品被创建**时改写字段，游戏过程中零逐帧读写：
--   * Hook Item.SetDefaults / Item.netDefaults 的 postfix。这两条路径覆盖了
--     进世界读档(DeserializeFrom → netDefaults)、捡起、合成、商店、开箱、
--     重铸(Prefix → ResetPrefix → Refresh → netDefaults)、网络同步等全部来源。
--   * 每个 Item.type 只做一次分类 + 记录原版基础值，同类型物品共用一份改写计划。
--   * 写入是**幂等**的：当前值 == 原版值 → 写入目标值；当前值 == 我们上次写的值
--     → 只在目标变化时重写；其它情况（被前缀/别的模组改过）一律不碰。
--     所以不会叠加、不会把「传奇」前缀的加成洗掉，改设置也不会越改越离谱。
--   * 逐帧钩子（Player.ResetEffects postfix）只做可放宽的工作（设置比对、netMode
--     缓存、兜底扫描计数、背包刷新、进世界首帧自检播报、研究解锁分帧），
--     并按 tick_interval 分桶平摊到各帧。
--
-- ★ 2.0.0 核心修复：鞭子类武器跳过攻速改写（§3.4）
--   根因（PC 1.4.5.8 Projectile.cs:49179 FillWhipControlPoints）：
--     鞭长 ∝ ContentSamples.ItemsByType[heldItem.type].useAnimation。
--     原版给鞭子加速只动 Player.itemAnimationMax（Player.cs:4459-4461
--     ApplyItemAnimation → SetItemAnimation），**从不动 Item.useAnimation**。
--     我们过去直接缩放 Item.useTime/useAnimation，于是攻速拉高 → 鞭长被吃掉。
--   修法：判定为鞭子时**跳过 useTime/useAnimation 的改写**，只保留伤害/击退/大小；
--     判定优先级（每层都有命中计数与失败分支）：
--       ① Item.summon == true 且 ItemID.Sets.SummonerWeaponThatScalesWithAttackSpeed[type]
--          （bool[]，手机版 TSV「ItemID.Sets」行 0x1A8，需 get_inner_type(ItemID,"Sets")）
--       ② 取不到集合时：Item.shoot 落在内置鞭子弹幕编号表（来源见 WHIP_PROJ 注释）
--       ③ 再取不到：只打日志，按普通近战处理（等价旧行为）
--
-- 【联机】host_only（默认开）：Main.netMode == 1（客机）时只读不写、不介入游戏数据；
--   netMode 在 1.4.5.8 手机版是 Main 上的 public static int 字段，用缓存
--   （跟设置重读同节拍刷新），绝不逐帧反射读；取不到句柄时退化为「不限制」。
--
-- 【日志】write_log（默认关）：关闭时除 setup() 阶段一次性「符号取不到」的 warn 与
--   聊天栏播报外，不执行任何 mod.info/warn/error，也不写任何日志文件。
--
-- 【依赖符号】逐条对着 参考库/符号/官方源码-{字段,方法}.tsv（1.4.5.8 手机版）核对；
--   取不到就跳过对应功能（只打一条日志）：
--   Item 字段: type damage useTime useAnimation knockBack crit scale shootSpeed mana
--              pick axe hammer fishingPole tileBoost autoReuse consumable shoot ammo
--              melee ranged magic summon createTile createWall maxStack value rare
--              potion healLife healMana buffType makeNPC(short) material prefix(byte)
--   Item 方法: SetDefaults(int,ItemVariant) / netDefaults(int) / Prefix(int) /
--              GetRollablePrefixes() （★ prefix 是 byte → 必须用 "uint8" 读写）
--   ItemID.Sets: SummonerWeaponThatScalesWithAttackSpeed bool[]（嵌套类型）
--   Player: inventory(Item[]) whoAmI ResetEffects()
--   Main: netMode(int 静态字段) player projectile gameMenu(属性) myPlayer(属性)
--         NewText(string,byte,byte,byte,bool) 5 参 / get_LocalPlayerCreativeTracker(0 参静态属性)
--   Projectile: type friendly scale；NewProjectile 只挂 13 参重载
--   Chat（仅「聊天指令」设置项打开时才解析，默认完全禁用）:
--         Commands.SayChatCommand.ProcessIncomingMessage(string,byte) 2 参实例
--         ★ 唯一的聊天文本入口；它注册为 _defaultCommand，普通聊天与未知 /命令的原文
--           都会送到这里。**绝不触达 Terraria.Chat 的消息对象类型**（实机 SIGABRT 点，
--           见 开发文档/05-写法与陷阱.md §5.2 与 12-下一版通用约定.md §9）。
--   Creative: CreativeUnlocksTracker.ItemSacrifices → ItemsSacrificedUnlocksTracker
--             .RegisterItemSacrifice(int,int,string) 3 参
--
-- 【失败策略】任何符号取不到都只打日志、放弃对应功能，绝不影响游戏运行；
--   安装 Hook 全部用 pcall 包住，回调内先判空再早退。
-- ★ 未经实机验证：本工作区无法启动游戏，全部结论为静态分析产物。
-- ============================================================================

mod.meta = { pkg_id = "ailab.lua.itemforge", version = "2.1.3" }

local patch = mod.patch

-- ============================================================================
-- 1. 设置默认值（必须与 Info.json 里每项 settings 的 defaultValue 完全一致）
-- ============================================================================
local DEFAULTS = {
    -- A. 总控
    enabled = true,                 -- 总开关
    global_percent = 100,           -- 全局倍率（%）
    hot_reload = true,              -- 是否自动重读设置（总闸）
    config_reload_sec = 5,          -- 自动重读设置的间隔（秒，1~60）
    tick_interval = 10,             -- 非关键项刷新间隔（帧，1~60；1 = 逐帧）
    host_only = true,               -- 联机：仅房主生效
    write_log = false,              -- 日志总开关（关掉后连日志文件都不写）
    refresh_inventory = true,       -- 改设置后立即刷新背包
    debug_log = false,              -- 详细日志（仅在 write_log 打开时才有意义）
    -- A2. §4.6 诊断（5 模组统一契约）
    self_check = true,              -- 进世界首帧播报各功能域装载状态
    diag_report_cmd = "forge stat", -- 触发详细报告的聊天命令（仅 chat_cmd 打开时可用）
    diag_slow_ms = 50,              -- 单域平均耗时超过该毫秒数就标 SLOW（1~1000）
    -- A3. §9 聊天安全（v2.0.0 整改）
    chat_cmd = false,               -- 聊天指令总开关：默认关闭 = 不碰任何 Chat 类型、不装聊天钩子
    import_string = "",            -- 默认（零聊天依赖）导入通道：把设置串粘贴到这里
    -- B. 一键开关
    tool_auto = false,
    weapon_auto = false,
    place_auto = false,
    place_infinite = false,         -- 放置类不消耗
    inf_potion = false,             -- 药水 / 增益类不消耗
    inf_bomb = false,               -- 炸弹 / 投掷物不消耗
    inf_summon = false,             -- 召唤物不消耗
    inf_material = false,           -- 材料不消耗
    inf_other = false,              -- 其它消耗品不消耗
    best_prefix = false,            -- 所有可附词缀物品默认最高词缀
    research_unlock = false,        -- 研究（旅程模式）自动解锁
    -- B2. 作用范围
    id_whitelist = "",              -- 只改这些物品 ID（逗号/空格分隔，空 = 全部）
    id_blacklist = "",              -- 排除这些物品 ID（优先级高于白名单）
    min_use_time = 3,               -- 使用时间下限（帧，1~60）
    -- B3. 经济类倍率
    maxstack_mult = 100,            -- 堆叠上限倍率
    value_mult = 100,               -- 售价倍率
    rare_mult = 100,                -- 稀有度倍率
    -- C. 镐子
    pick_speed = 100,
    pick_power = 100,
    pick_damage = 100,
    pick_range = 100,
    -- D. 斧头
    axe_speed = 100,
    axe_power = 100,
    axe_damage = 100,
    axe_range = 100,
    -- E. 锤子
    hammer_speed = 100,
    hammer_power = 100,
    hammer_damage = 100,
    hammer_range = 100,
    -- F. 放置类
    place_speed = 100,
    place_range = 100,
    -- G. 近战
    melee_speed = 100,
    melee_damage = 100,
    melee_knockback = 100,
    melee_crit = 100,
    melee_scale = 100,
    melee_proj_scale = 100,
    -- H. 远程（含弹药）
    ranged_speed = 100,
    ranged_damage = 100,
    ranged_knockback = 100,
    ranged_crit = 100,
    ranged_velocity = 100,
    ranged_proj_scale = 100,
    -- I. 魔法
    magic_speed = 100,
    magic_damage = 100,
    magic_knockback = 100,
    magic_crit = 100,
    magic_velocity = 100,
    magic_mana = 100,
    magic_proj_scale = 100,
    -- J. 召唤
    summon_speed = 100,
    summon_damage = 100,
    summon_knockback = 100,
    summon_scale = 100,
    summon_proj_scale = 100,
    -- K. 钓竿
    fish_speed = 100,
    fish_power = 100,
    -- L. 其他（手雷、爆炸物等即不属于上面任何一类的可用物品）
    other_speed = 100,
    other_damage = 100,
    -- M. 面板（v2.1.0，19 章 §1.7）
    gui_enable = true,              -- 图形面板总开关（关掉后 on_gui 直接 return；靠设置页开回来）
    gui_layout = "滚动",           -- 面板布局：滚动 / 分页（老加载器没有 begin_scroll 时强制分页）
}

-- 允许范围（与 Info.json 的 min/max 一致；读取时再夹一次，防止手改文件越界）
-- ★ v2.0.0 按 §3.2 把「倍率 / 百分比」类上限统一放宽到 10000（= 100 倍），默认仍 100；
--   非倍率类（秒 / 帧 / 数量上限）保持原上限不变。
--   游戏对很多数值有硬性夹取，滑块调得再高也未必带来对应效果；上限只是行程。
local LIMITS = {
    -- 总控的间隔类：1~60（帧 / 秒）
    tick_interval = { 1, 60 },
    config_reload_sec = { 1, 60 },
    -- 诊断：单域耗时阈值（毫秒）与使用时间下限（帧）
    diag_slow_ms = { 1, 1000 },
    min_use_time = { 1, 60 },
    -- 百分比 / 倍率类：100 = 原版，上限 10000
    global_percent = { 1, 10000 },
    maxstack_mult = { 1, 10000 }, value_mult = { 1, 10000 }, rare_mult = { 1, 10000 },
    pick_speed = { 1, 10000 }, pick_power = { 1, 10000 }, pick_damage = { 1, 10000 }, pick_range = { 1, 10000 },
    axe_speed = { 1, 10000 }, axe_power = { 1, 10000 }, axe_damage = { 1, 10000 }, axe_range = { 1, 10000 },
    hammer_speed = { 1, 10000 }, hammer_power = { 1, 10000 }, hammer_damage = { 1, 10000 }, hammer_range = { 1, 10000 },
    place_speed = { 1, 10000 }, place_range = { 1, 10000 },
    melee_speed = { 1, 10000 }, melee_damage = { 1, 10000 }, melee_knockback = { 1, 10000 },
    melee_crit = { 1, 10000 }, melee_scale = { 10, 10000 }, melee_proj_scale = { 10, 10000 },
    ranged_speed = { 1, 10000 }, ranged_damage = { 1, 10000 }, ranged_knockback = { 1, 10000 },
    ranged_crit = { 1, 10000 }, ranged_velocity = { 1, 10000 }, ranged_proj_scale = { 10, 10000 },
    magic_speed = { 1, 10000 }, magic_damage = { 1, 10000 }, magic_knockback = { 1, 10000 },
    magic_crit = { 1, 10000 }, magic_velocity = { 1, 10000 }, magic_mana = { 1, 10000 }, magic_proj_scale = { 10, 10000 },
    summon_speed = { 1, 10000 }, summon_damage = { 1, 10000 }, summon_knockback = { 1, 10000 },
    summon_scale = { 10, 10000 }, summon_proj_scale = { 10, 10000 },
    fish_speed = { 1, 10000 }, fish_power = { 1, 10000 },
    other_speed = { 1, 10000 }, other_damage = { 1, 10000 },
}

-- 没有 CHOICE 类设置项；保留空表以便 build_mod.py 的契约检查与将来扩展
local CHOICES = {
    gui_layout = { "滚动", "分页" },
}

-- ============ 运行时状态 ============
local cfg = {}
for key, value in pairs(DEFAULTS) do cfg[key] = value end
local config_loaded = false
local last_config_raw = nil

local ready = false
local pending_sweep = true          -- 进世界后先扫一次背包（兜底）

local hooks = {}                    -- 已安装的钩子，卸载时逐个 remove

-- 每个物品类型一份改写计划： [type] = { cat, entries = {...}, n, dirty, ... }
local item_info = {}
-- 物品射出的弹幕类型 → 物品分类（用于弹幕体型倍率）
local proj_cat = {}
-- 弹幕体型是否有任何一项被调过（false 时弹幕 Hook 直接早退）
local proj_active = false

local RANGE_BASE = 5                -- 原版放置/挖掘基础范围（格），用于「范围倍率」的基准
local MAX_SWEEP_SLOTS = 200         -- 背包扫描上限（原版背包 59 格，留足余量）
-- 研究解锁扫描的物品 ID 上限：ItemID.Count 是 **const**（不能读），值取自已核实的
-- 编译期常数列 —— 参考库/符号/官方源码-字段.tsv:32545 行：`Terraria.ID.ItemID Count short
-- public const 是 是 6196`。抄常数是硬规则 #2 规定的做法。
local ITEM_CEILING = 6196

local reported = {}                 -- 一次性日志标记

-- 运行期命中计数（聊天栏 /forge stat 可查；热路径只做 table 自增）
local STAT = {
    item_calls = 0, item_writes = 0, item_errs = 0,
    proj_calls = 0, proj_hits = 0, proj_errs = 0,
    frame_calls = 0, sweep_calls = 0, sweep_items = 0,
    whip_set_ok = 0, whip_set_miss = 0, whip_proj_ok = 0, whip_proj_miss = 0,
    whip_skipped = 0, whip_unknown = 0,
    speed_clamped = 0,
    prefix_calls = 0, prefix_hits = 0, prefix_errs = 0,
    research_done = 0, research_errs = 0, research_finished = false,
    id_denied = 0,
    chat_in = 0, chat_cmds = 0,
    self_check_runs = 0,
    econ_writes = 0,
    cons_writes = 0,
}

-- ============================================================================
-- 2. 设置解析（与既有官方 Mod 相同的做法：正则匹配 config.json 里的键）
--    设置由 TEFManager 写在模组私有目录的 config.json，形如 {"values":{...}}
-- ============================================================================
-- 日志总闸（v1.1.0 起）
--   write_log = false 时，除 setup() 阶段一次性「符号取不到」的 warn 外，
--   任何 mod.info/warn/error 都不执行（逐帧 / 每物品的高频路径更是一条都不打）。
-- 最近日志缓冲（面板「关于」页用；只在内存里留 40 行，不落盘、不受 write_log 影响）
local LOG_RING, LOG_RING_MAX = {}, 40
local function ring_push(text)
    LOG_RING[#LOG_RING + 1] = tostring(text)
    while #LOG_RING > LOG_RING_MAX do table.remove(LOG_RING, 1) end
end

local function log_info(text)
    ring_push("I " .. tostring(text))
    if cfg.write_log then mod.info(text) end
end

local function log_debug(text)
    if cfg.write_log and cfg.debug_log then
        ring_push("D " .. tostring(text))
        mod.info(text)
    end
end

-- 运行期告警：受 write_log 门控，同一 tag 只打一次
local function log_warn_once(tag, text)
    if not cfg.write_log or reported[tag] then return end
    reported[tag] = true
    ring_push("W " .. tostring(text))
    mod.warn(text)
end

-- setup() 阶段「符号取不到」专用：write_log 关着也允许打一次
--（这是玩家排查「某项功能为什么没生效」的唯一线索）
local function log_symbol(tag, text, is_error)
    if reported[tag] then return end
    reported[tag] = true
    ring_push((is_error and "E " or "W ") .. tostring(text))
    if is_error then mod.error(text) else mod.warn(text) end
end

local function parse_int(raw, key, fallback, lo, hi)
    local escaped = key:gsub("([^%w])", "%%%1")
    local value = tonumber(raw:match('"' .. escaped .. '"%s*:%s*(-?%d+)'))
    if not value then return fallback end
    value = math.floor(value)
    -- ★ v1.0.1 起：只夹下限（挡住 0/负数这类无意义输入），不夹上限 ——
    --   滑块的上限只是行程，手改 config.json 想填多大就多大。
    if lo and value < lo then value = lo end
    return value
end

local function parse_bool(raw, key, fallback)
    local escaped = key:gsub("([^%w])", "%%%1")
    -- TEFManager 存的是 JSON 的 true/false；万一存成 1/0 也能认
    local text = raw:match('"' .. escaped .. '"%s*:%s*(%a+)')
    if text == "true" then return true end
    if text == "false" then return false end
    local digit = raw:match('"' .. escaped .. '"%s*:%s*(%d+)')
    if digit then return digit ~= "0" end
    return fallback
end

-- STRING 类（v2.0.0：id_whitelist / id_blacklist / diag_report_cmd / import_string）
local function parse_str(raw, key, fallback)
    local escaped = key:gsub("([^%w])", "%%%1")
    local v = raw:match('"' .. escaped .. '"%s*:%s*"([^"]*)"')
    if v == nil then return fallback end
    return v
end

local read_config, recompute_all, settings_summary

-- ---- 物品 ID 白名单 / 黑名单（§4.3-3）----
-- 语义：黑名单优先排除；白名单非空时只改白名单内的物品。
local id_whitelist_set, id_blacklist_set = nil, nil
local id_filter_stat = { wl = 0, bl = 0 }

local function parse_id_list(text)
    if type(text) ~= "string" or text == "" then return nil end
    local set, n = {}, 0
    for tok in text:gmatch("[^%s,;，、]+") do
        local v = tonumber(tok)
        if v then
            v = math.floor(v)
            if v > 0 and not set[v] then set[v] = true n = n + 1 end
        end
    end
    if n == 0 then return nil end
    return set
end

local function rebuild_id_filters()
    id_whitelist_set = parse_id_list(cfg.id_whitelist)
    id_blacklist_set = parse_id_list(cfg.id_blacklist)
    id_filter_stat.wl = 0
    id_filter_stat.bl = 0
    if id_whitelist_set then for _ in pairs(id_whitelist_set) do id_filter_stat.wl = id_filter_stat.wl + 1 end end
    if id_blacklist_set then for _ in pairs(id_blacklist_set) do id_filter_stat.bl = id_filter_stat.bl + 1 end end
end

-- 失败分支：两个列表都是空 → 放开全部（等价旧行为）
local function id_allowed(itype)
    if id_blacklist_set and id_blacklist_set[itype] then return false end
    if id_whitelist_set then return id_whitelist_set[itype] == true end
    return true
end

local function load_config_from(raw)
    -- 文件存在但里面没有任何本模组的键（TEFManager 正在写的中间态/截断/放错文件）
    -- → 当作读取失败，沿用上一次的有效值，避免玩家的设置被打回默认。
    local hits = 0
    for key in pairs(DEFAULTS) do
        if raw:find('"' .. key .. '"', 1, true) then hits = hits + 1 end
    end
    if hits == 0 then return false end

    for key, default in pairs(DEFAULTS) do
        local t = type(default)
        if t == "boolean" then
            cfg[key] = parse_bool(raw, key, cfg[key])
        elseif t == "string" then
            cfg[key] = parse_str(raw, key, cfg[key])
        else
            local lim = LIMITS[key]
            cfg[key] = parse_int(raw, key, cfg[key], lim and lim[1], lim and lim[2])
        end
    end
    -- ★ 总控的几个间隔项必须夹两端：0 / 超大值会让分桶与重读节拍失效
    cfg.tick_interval = math.max(1, math.min(60, math.floor(cfg.tick_interval or 10)))
    cfg.config_reload_sec = math.max(1, math.min(60, math.floor(cfg.config_reload_sec or 5)))
    cfg.min_use_time = math.max(1, math.min(60, math.floor(cfg.min_use_time or 3)))
    cfg.diag_slow_ms = math.max(1, math.min(1000, math.floor(cfg.diag_slow_ms or 50)))
    rebuild_id_filters()
    config_loaded = true
    return true
end

read_config = function()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then
        config_loaded = true
        return false
    end
    if not load_config_from(raw) then
        config_loaded = true
        return false
    end
    last_config_raw = raw
    return true
end

-- ============================================================================
-- 3. 分类与属性表
-- ============================================================================
local CAT = {
    PICK = 1, AXE = 2, HAMMER = 3, PLACE = 4, MELEE = 5,
    RANGED = 6, MAGIC = 7, SUMMON = 8, FISH = 9, OTHER = 10,
}
local CAT_NAME = {
    [CAT.PICK] = "镐子", [CAT.AXE] = "斧头", [CAT.HAMMER] = "锤子", [CAT.PLACE] = "放置类",
    [CAT.MELEE] = "近战", [CAT.RANGED] = "远程", [CAT.MAGIC] = "魔法", [CAT.SUMMON] = "召唤",
    [CAT.FISH] = "钓竿", [CAT.OTHER] = "其他",
}

-- 属性规格表
--   setting : Info.json 里的设置键
--   field   : Item 上的字段名（已与手机版 TSV 核对）
--   kind    : int / float / short / byte
--   mode    : mul   = 乘倍率
--             speed = 速度倍率（越大越快 → 字段 = 原值 × 100 / 倍率，再夹 min_use_time 下限）
--             range = 以原版 5 格基础范围为基准的倍率
--   lo/hi   : 写入前的硬性夹取（防止极端值把游戏搞坏；hi 仅用于经济类）
--   only_positive : 原值为 0/负数时跳过（例如非武器物品的 damage = -1）
local SPECS = {
    [CAT.PICK] = {
        { setting = "pick_speed",  field = "useTime",      kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "pick_speed",  field = "useAnimation", kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "pick_power",  field = "pick",         kind = "int", mode = "mul",   lo = 0, hi = 1000 },
        { setting = "pick_damage", field = "damage",       kind = "int", mode = "mul",   lo = 1, hi = 1000000, only_positive = true },
        { setting = "pick_range",  field = "tileBoost",    kind = "int", mode = "range", lo = 0, hi = 100 },
    },
    [CAT.AXE] = {
        { setting = "axe_speed",  field = "useTime",      kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "axe_speed",  field = "useAnimation", kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "axe_power",  field = "axe",          kind = "int", mode = "mul",   lo = 0, hi = 1000 },
        { setting = "axe_damage", field = "damage",       kind = "int", mode = "mul",   lo = 1, hi = 1000000, only_positive = true },
        { setting = "axe_range",  field = "tileBoost",    kind = "int", mode = "range", lo = 0, hi = 100 },
    },
    [CAT.HAMMER] = {
        { setting = "hammer_speed",  field = "useTime",      kind = "int",   mode = "speed", lo = 1, hi = 100000 },
        { setting = "hammer_speed",  field = "useAnimation", kind = "int",   mode = "speed", lo = 1, hi = 100000 },
        { setting = "hammer_power",  field = "hammer",       kind = "int",   mode = "mul",   lo = 0, hi = 1000 },
        { setting = "hammer_damage", field = "damage",       kind = "int",   mode = "mul",   lo = 1, hi = 1000000, only_positive = true },
        { setting = "hammer_range",  field = "tileBoost",    kind = "int",   mode = "range", lo = 0, hi = 100 },
    },
    [CAT.PLACE] = {
        { setting = "place_speed", field = "useTime",      kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "place_speed", field = "useAnimation", kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "place_range", field = "tileBoost",    kind = "int", mode = "range", lo = 0, hi = 100 },
    },
    [CAT.MELEE] = {
        { setting = "melee_speed",     field = "useTime",      kind = "int",   mode = "speed", lo = 1,   hi = 100000 },
        { setting = "melee_speed",     field = "useAnimation", kind = "int",   mode = "speed", lo = 1,   hi = 100000 },
        { setting = "melee_damage",    field = "damage",       kind = "int",   mode = "mul",   lo = 1,   hi = 1000000, only_positive = true },
        { setting = "melee_knockback", field = "knockBack",    kind = "float", mode = "mul",   lo = 0,   hi = 100 },
        { setting = "melee_crit",      field = "crit",         kind = "int",   mode = "mul",   lo = 0,   hi = 100 },
        { setting = "melee_scale",     field = "scale",        kind = "float", mode = "mul",   lo = 0.05, hi = 12, only_positive = true },
    },
    [CAT.RANGED] = {
        { setting = "ranged_speed",     field = "useTime",      kind = "int",   mode = "speed", lo = 1,   hi = 100000 },
        { setting = "ranged_speed",     field = "useAnimation", kind = "int",   mode = "speed", lo = 1,   hi = 100000 },
        { setting = "ranged_damage",    field = "damage",       kind = "int",   mode = "mul",   lo = 1,   hi = 1000000, only_positive = true },
        { setting = "ranged_knockback", field = "knockBack",    kind = "float", mode = "mul",   lo = 0,   hi = 100 },
        { setting = "ranged_crit",      field = "crit",         kind = "int",   mode = "mul",   lo = 0,   hi = 100 },
        { setting = "ranged_velocity",  field = "shootSpeed",   kind = "float", mode = "mul",   lo = 0.1, hi = 100, only_positive = true },
    },
    [CAT.MAGIC] = {
        { setting = "magic_speed",     field = "useTime",      kind = "int",   mode = "speed", lo = 1,    hi = 100000 },
        { setting = "magic_speed",     field = "useAnimation", kind = "int",   mode = "speed", lo = 1,    hi = 100000 },
        { setting = "magic_damage",    field = "damage",       kind = "int",   mode = "mul",   lo = 1,    hi = 1000000, only_positive = true },
        { setting = "magic_knockback", field = "knockBack",    kind = "float", mode = "mul",   lo = 0,    hi = 100 },
        { setting = "magic_crit",      field = "crit",         kind = "int",   mode = "mul",   lo = 0,    hi = 100 },
        { setting = "magic_velocity",  field = "shootSpeed",   kind = "float", mode = "mul",   lo = 0.1,  hi = 100, only_positive = true },
        { setting = "magic_mana",      field = "mana",         kind = "int",   mode = "mul",   lo = 0,    hi = 9999 },
    },
    [CAT.SUMMON] = {
        { setting = "summon_speed",     field = "useTime",      kind = "int",   mode = "speed", lo = 1,   hi = 100000 },
        { setting = "summon_speed",     field = "useAnimation", kind = "int",   mode = "speed", lo = 1,   hi = 100000 },
        { setting = "summon_damage",    field = "damage",       kind = "int",   mode = "mul",   lo = 1,   hi = 1000000, only_positive = true },
        { setting = "summon_knockback", field = "knockBack",    kind = "float", mode = "mul",   lo = 0,   hi = 100 },
        { setting = "summon_scale",     field = "scale",        kind = "float", mode = "mul",   lo = 0.05, hi = 12, only_positive = true },
    },
    [CAT.FISH] = {
        { setting = "fish_speed", field = "useTime",      kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "fish_speed", field = "useAnimation", kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "fish_power", field = "fishingPole",  kind = "int", mode = "mul",   lo = 0, hi = 1000 },
    },
    [CAT.OTHER] = {
        { setting = "other_speed",  field = "useTime",      kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "other_speed",  field = "useAnimation", kind = "int", mode = "speed", lo = 1, hi = 100000 },
        { setting = "other_damage", field = "damage",       kind = "int", mode = "mul",   lo = 1, hi = 1000000, only_positive = true },
    },
}

-- ★ 鞭子类跳过攻速改写（§3.4）——这些 spec 的 field 名就是这个集合
local SPEED_FIELDS = { useTime = true, useAnimation = true }

-- 经济类倍率（§4.3-4）：对所有物品生效，不分类别。
--   ★ Item.value / Item.rare / Item.maxStack 都是 int，改前先在 build_info 里读原版基础值，
--     再由 apply_info 做幂等写入（当前值 != 原版 且 不是我们写的 → 不碰）。
--   rare 的 lo = -1：原版 rare = -1 表示灰色，夹到 0 会把所有灰色物品改掉。
local ECO_SPECS = {
    { setting = "maxstack_mult", field = "maxStack", kind = "int", mode = "mul", lo = 1,   hi = 9999 },
    { setting = "value_mult",    field = "value",    kind = "int", mode = "mul", lo = 0,   hi = 1000000000 },
    { setting = "rare_mult",     field = "rare",     kind = "int", mode = "mul", lo = -1,  hi = 11 },
}

-- 自动连用：分类 → 一键开关
local AUTO_SWITCH = {
    [CAT.PICK] = "tool_auto", [CAT.AXE] = "tool_auto", [CAT.HAMMER] = "tool_auto", [CAT.FISH] = "tool_auto",
    [CAT.MELEE] = "weapon_auto", [CAT.RANGED] = "weapon_auto",
    [CAT.MAGIC] = "weapon_auto", [CAT.SUMMON] = "weapon_auto",
    [CAT.PLACE] = "place_auto",
}

-- 弹幕体型：分类 → 设置键
local PROJ_SCALE = {
    [CAT.MELEE] = "melee_proj_scale",
    [CAT.RANGED] = "ranged_proj_scale",
    [CAT.MAGIC] = "magic_proj_scale",
    [CAT.SUMMON] = "summon_proj_scale",
}

-- 需要解析的全部 Item 字段（分类 + 改写目标 + 弹幕映射 + 消耗品分类 + 词缀/研究）
local FIELD_NAMES = {
    "type", "damage", "useTime", "useAnimation", "knockBack", "crit", "scale", "shootSpeed",
    "mana", "pick", "axe", "hammer", "fishingPole", "tileBoost", "autoReuse", "consumable",
    "shoot", "ammo", "melee", "ranged", "magic", "summon", "createTile", "createWall",
    "maxStack", "value", "rare",
    "potion", "healLife", "healMana", "buffType", "makeNPC", "material", "prefix",
}

-- 解析后的字段句柄：FIELDS["damage"] = 句柄（取不到就是 nil，对应功能自动跳过）
local FIELDS = {}

-- ============================================================================
-- 4. 基础工具（字段读写 / 数值比较 / 父类链查找）
-- ============================================================================
local HAS_PACK = (type(string.pack) == "function") and (type(string.unpack) == "function")

-- 把 double 截成 float32：游戏里的 float 字段会丢掉精度，写入前先对齐，
-- 否则「读回来的值」和「我们记下的值」永远不相等，幂等判断就失效了。
local function f32(x)
    if HAS_PACK then
        local ok, v = pcall(string.unpack, "f", string.pack("f", x))
        if ok and type(v) == "number" then return v end
    end
    return x
end

-- 相等判断：整数严格相等；浮点给 1e-5 的相对容差（float32 往返 + 前缀取整）
local function same(a, b)
    if a == b then return true end
    local ta, tb = type(a), type(b)
    if ta ~= "number" or tb ~= "number" then return false end
    local d = a - b
    if d < 0 then d = -d end
    local m = (b < 0) and -b or b
    if m < 1 then m = 1 end
    return d <= m * 1e-5
end

-- ★ kind → IL2CPP 取值类型字符串。Android 上 short/byte 字段必须按真实宽度读，
--   用 int32 读 makeNPC(short) 会读到相邻字节，用 int32 读 prefix(byte) 同理。
--   来源：参考库/符号/类型字符串.tsv（int16 / uint8 均为实证类型字符串）
local FIELD_TYPE = { int = "int32", float = "float", bool = "bool", short = "int16", byte = "uint8" }

local function read_field(field, inst, kind)
    if not field or not inst then return nil end
    local v = patch.get_field_value(field, inst, FIELD_TYPE[kind] or "int32")
    if v == nil then return nil end
    if kind == "bool" then
        if v == true or v == 1 then return true end
        if v == false or v == 0 then return false end
        return nil
    end
    local n = tonumber(v)
    if not n then return nil end
    if kind == "float" then return f32(n) end
    if n < 0 then return math.floor(n - 0.5) end
    return math.floor(n + 0.5)
end

local function write_field(field, inst, value, kind)
    if not field or not inst then return false end
    return patch.set_field_value(field, inst, value, FIELD_TYPE[kind] or "int32") and true or true
end

-- 沿父类链查字段（Entity.position 这类字段不在自身类型上）
local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local ok, field = pcall(patch.get_field, cur, name)
        if ok and field then return field end
        local ok2, parent = pcall(patch.get_parent, cur)
        if not ok2 then return nil end
        cur = parent
        guard = guard + 1
    end
    return nil
end

local function safe_get_method(type_handle, name, argc)
    if not type_handle then return nil end
    local ok, m = pcall(patch.get_method, type_handle, name, argc)
    if ok and m then return m end
    return nil
end

-- ============================================================================
-- 5. 诊断域注册表（§4.6-1，5 模组统一契约）
--    安装期登记一次：fields / methods / hooks = "ok" | "partial" | "fail"
--    运行期只做 d.calls / d.hits 自增（把 d 缓存成 upvalue，一次 table 写）
-- ============================================================================
local DIAG = {}
local DIAG_BY_NAME = {}

local function reg_domain(name)
    local d = {
        name = name, fields = "fail", methods = "fail", hooks = "fail",
        calls = 0, hits = 0, errs = 0, last_err = nil, t_total = 0, enabled = true,
    }
    DIAG[#DIAG + 1] = d
    DIAG_BY_NAME[name] = d
    return d
end

local function diag_note(d, ok, partial)
    if not d then return end
    if ok then d.fields = "ok" elseif partial then d.fields = "partial" end
end

-- 纯字段 / 纯方法级的域：不需要钩子，hooks 标 "n/a"，避免自检误报「已停用」
local function diag_no_hook(d, ok)
    if not d then return end
    d.fields = ok and "ok" or "fail"
    d.methods = d.fields
    d.hooks = "n/a"
    if not ok then d.enabled = false end
end

local function diag_fail(d, err)
    if not d then return end
    d.errs = d.errs + 1
    d.last_err = tostring(err)
end

local D_ITEM    = reg_domain("物品创建改写")
local D_PROJ    = reg_domain("弹幕体型")
local D_FRAME   = reg_domain("逐帧/热重载")
local D_WHIP    = reg_domain("鞭子判定")
local D_SPEED   = reg_domain("使用时间下限")
local D_ECON    = reg_domain("经济倍率")
local D_CONS    = reg_domain("消耗品不消耗")
local D_ID      = reg_domain("ID 白/黑名单")
local D_PREFIX  = reg_domain("最高词缀")
local D_RESEARCH= reg_domain("研究解锁")
local D_CHAT    = reg_domain("聊天命令")
local D_SWEEP   = reg_domain("背包刷新")

-- ============================================================================
-- 6. 改写计划：算目标值 / 幂等写入
-- ============================================================================
local function compute_targets(info)
    local on = cfg.enabled and true or false
    local g = on and ((cfg.global_percent or 100) / 100) or 1
    local dirty = false
    local allowed = on and id_allowed(info.itype)
    local min_use = math.floor(tonumber(cfg.min_use_time) or 3)
    if min_use < 1 then min_use = 1 end
    if min_use > 60 then min_use = 60 end
    local clamped_here = 0

    for i = 1, info.n do
        local e = info.entries[i]
        local sp = e.sp
        local target

        if (not on) or (not allowed) then
            -- 总开关关闭 或 物品不在白名单内 / 被黑名单排除 → 一律回到原版值
            -- （e.last 非 nil 时会让 dirty 变 true，于是已被改写过的物品会被还原）
            target = e.base
        elseif sp.mode == "force_true" then
            target = cfg[sp.setting] and true or e.base
        elseif sp.mode == "force_false" then
            -- 注意：不能写 `cfg[x] and false or e.base`（Lua 里 true and false or v == v）
            if cfg[sp.setting] then target = false else target = e.base end
        else
            local pct = cfg[sp.setting] or 100
            local eff = pct * g                     -- 有效百分比（100 = 原版）
            if eff == 100 then
                target = e.base
            else
                local t
                if sp.mode == "speed" then
                    -- 速度倍率：200% = 耗时减半
                    t = e.base * 100 / eff
                elseif sp.mode == "range" then
                    -- 范围倍率：以原版 5 格基础范围为基准
                    t = (e.base + RANGE_BASE) * eff / 100 - RANGE_BASE
                else
                    t = e.base * eff / 100
                end
                if sp.kind == "int" or sp.kind == "short" or sp.kind == "byte" then
                    t = math.floor(t + 0.5)
                end
                -- ★ §3.5：所有 useTime / useAnimation 的写入点统一走 min_use_time 下限
                --   （含工具/放置类：镐子在 1 帧时挖不动方块）
                if sp.mode == "speed" and t < min_use then
                    t = min_use
                    e.clamped = true
                    clamped_here = clamped_here + 1
                end
                if sp.lo and t < sp.lo then t = sp.lo end
                if sp.hi and t > sp.hi then t = sp.hi end
                if sp.kind == "float" then t = f32(t) end
                target = t
            end
        end

        e.target = target
        if not same(target, e.base) then dirty = true end
        if e.last ~= nil and not same(e.last, target) then dirty = true end
    end

    if clamped_here > 0 then
        info.clamped = true
        STAT.speed_clamped = STAT.speed_clamped + clamped_here
    end
    info.dirty = dirty
end

-- 幂等写入：只有「当前值 == 原版值」或「当前值是我们写过的某个值」时才动手。
-- 被前缀/其它模组改过的值一律不碰，因此不会叠加，也不会洗掉前缀加成。
--
-- ★ 为什么记「一小段历史」而不是只记上一个值：计划是按 Item.type 共享的，而同一个
--   类型可能有多个实例（背包里两把同样的剑）。它们在改设置时可能各自停在不同档位，
--   只记一个 last 会让第二个副本被判定为「被别的模组改过」而被漏掉。
local KNOWN_MAX = 8

local function value_is_ours(e, v)
    if e.last ~= nil and same(v, e.last) then return true end
    local h = e.hist
    if h then
        for i = 1, #h do
            if same(v, h[i]) then return true end
        end
    end
    return false
end

local function remember_value(e, v)
    e.last = v
    local h = e.hist
    if not h then h = {} e.hist = h end
    for i = 1, #h do
        if same(v, h[i]) then return end
    end
    if #h >= KNOWN_MAX then table.remove(h, 1) end
    h[#h + 1] = v
end

-- forward：分类与计划构建（在下面定义，apply_info 之后才用）
local build_info

local function apply_info(item, info)
    if not info.dirty then return 0 end
    local writes = 0
    for i = 1, info.n do
        local e = info.entries[i]
        local cur = read_field(e.field, item, e.sp.kind)
        if cur ~= nil then
            if same(cur, e.base) or value_is_ours(e, cur) then
                if not same(e.target, cur) then
                    write_field(e.field, item, e.target, e.sp.kind)
                    writes = writes + 1
                    local sk = e.sp.setting
                    if sk == "maxstack_mult" or sk == "value_mult" or sk == "rare_mult" then
                        STAT.econ_writes = STAT.econ_writes + 1
                    elseif sk == "place_infinite" or sk == "inf_potion" or sk == "inf_bomb"
                        or sk == "inf_summon" or sk == "inf_material" or sk == "inf_other" then
                        STAT.cons_writes = STAT.cons_writes + 1
                    end
                end
                remember_value(e, e.target)
            end
        end
    end
    return writes
end

-- ============================================================================
-- 7. 分类（一个物品只属于一类，按优先级判定）
-- ============================================================================
local function classify(item)
    local v = read_field(FIELDS.pick, item, "int")
    if v and v > 0 then return CAT.PICK end
    v = read_field(FIELDS.axe, item, "int")
    if v and v > 0 then return CAT.AXE end
    v = read_field(FIELDS.hammer, item, "int")
    if v and v > 0 then return CAT.HAMMER end
    v = read_field(FIELDS.fishingPole, item, "int")
    if v and v > 0 then return CAT.FISH end
    if read_field(FIELDS.melee, item, "bool") then return CAT.MELEE end
    if read_field(FIELDS.ranged, item, "bool") then return CAT.RANGED end
    if read_field(FIELDS.magic, item, "bool") then return CAT.MAGIC end
    if read_field(FIELDS.summon, item, "bool") then return CAT.SUMMON end
    v = read_field(FIELDS.ammo, item, "int")
    if v and v ~= 0 then return CAT.RANGED end          -- 弹药归入远程
    v = read_field(FIELDS.createTile, item, "int")
    if v and v >= 0 then return CAT.PLACE end
    v = read_field(FIELDS.createWall, item, "int")
    if v and v >= 0 then return CAT.PLACE end
    return CAT.OTHER
end

-- ---- 消耗品分类（§4.3-5）----
--   放置类仍走老的 place_infinite；其余按 药水 → 召唤物 → 炸弹 → 材料 → 其他 的优先级。
local CONS_SETTING = {
    potion = "inf_potion", bomb = "inf_bomb", summon = "inf_summon",
    material = "inf_material", other = "inf_other",
}

local function consumable_setting(cat, item)
    if cat == CAT.PLACE then return "place_infinite" end
    if read_field(FIELDS.consumable, item, "bool") ~= true then return nil end
    if read_field(FIELDS.potion, item, "bool") == true then return CONS_SETTING.potion end
    if (read_field(FIELDS.healLife, item, "int") or 0) > 0 then return CONS_SETTING.potion end
    if (read_field(FIELDS.healMana, item, "int") or 0) > 0 then return CONS_SETTING.potion end
    if (read_field(FIELDS.buffType, item, "int") or 0) > 0 then return CONS_SETTING.potion end
    if (read_field(FIELDS.makeNPC, item, "short") or 0) > 0 then return CONS_SETTING.summon end
    local sh = read_field(FIELDS.shoot, item, "int") or 0
    local dmg = read_field(FIELDS.damage, item, "int") or -1
    local is_weapon = read_field(FIELDS.melee, item, "bool")
        or read_field(FIELDS.ranged, item, "bool")
        or read_field(FIELDS.magic, item, "bool")
        or read_field(FIELDS.summon, item, "bool")
    if sh > 0 and dmg > 0 and not is_weapon then return CONS_SETTING.bomb end
    if read_field(FIELDS.material, item, "bool") == true then return CONS_SETTING.material end
    return CONS_SETTING.other
end

-- ============================================================================
-- 8. 鞭子判定（§3.4-1）
--  ① ItemID.Sets.SummonerWeaponThatScalesWithAttackSpeed（bool[]）
--     来源：参考库/符号/官方源码-字段.tsv —— 类型列写的是「ItemID.Sets」，
--     字段名 SummonerWeaponThatScalesWithAttackSpeed，bool[]，public static，偏移 0x1A8，
--     readonly=是、const 空（可读）。嵌套类型必须 get_inner_type(ItemID,"Sets")。
--     内容与 PC 1.4.5.8 一致：
--     PC-1.4.5.8/Terraria.ID/ItemID.cs:262
--       Factory.CreateBoolSet(4672,4679,4680,4678,4913,4912,4911,4914,5074,
--                             5473,5474,5475,5476,5477,5478,5479,5480,5688)
--  ② 兜底：Item.shoot 落在内置鞭子弹幕编号表 WHIP_PROJ。
--     来源：PC-1.4.5.8/Terraria.ID/ProjectileID.cs:35
--       public static bool[] IsAWhip = Factory.CreateBoolSet(false,
--         847,841,848,849,912,913,914,915,952,1028,1029,1030,1031,1032,1033,1034,1035,1104)
--     逐个核对过 Item.cs 的 DefaultToWhip(<弹幕ID>, ...) 调用：
--       Item.cs:38512 case 4672 → 841；:38540 4678 → 847；:38544 4679 → 848；:38549 4680 → 849
--              :39833 4911 → 912；:39837 4912 → 913；:39841 4913 → 914；:39845 4914 → 915
--              :40681 5074 → 952；:43162 5473 → 1028；:43166 5474 → 1029；:43170 5475 → 1030
--              :43174 5476 → 1031；:43178 5477 → 1032；:43182 5478 → 1033；:43186 5479 → 1034
--              :43190 5480 → 1035；:44693 5688 → 1104
--  ③ 两者都取不到 → 只打日志（whip_unknown 计数），按普通近战/召唤处理（等价旧行为）
-- ============================================================================
local WHIP_PROJ = {
    [841] = true, [847] = true, [848] = true, [849] = true,
    [912] = true, [913] = true, [914] = true, [915] = true, [952] = true,
    [1028] = true, [1029] = true, [1030] = true, [1031] = true,
    [1032] = true, [1033] = true, [1034] = true, [1035] = true, [1104] = true,
}

-- 句柄：ItemID.Sets.SummonerWeaponThatScalesWithAttackSpeed（setup 里解析）
local T_ITEMID_SETS, F_WHIP_SET = nil, nil
local whip_set_failed = false       -- ③ 分支标记

-- 判定一个 item 实例是否是鞭子。返回 "set" / "proj" / nil
local function whip_kind(item, itype)
    if F_WHIP_SET then
        local ok, arr = pcall(patch.get_field_value, F_WHIP_SET, nil, "object")
        if ok and arr then
            local ok2, n = pcall(patch.array_length, arr)
            if ok2 and type(n) == "number" and itype >= 0 and itype < n then
                local ok3, v = pcall(patch.array_at, arr, itype, "bool")
                if ok3 then
                    if v == true or v == 1 then
                        STAT.whip_set_ok = STAT.whip_set_ok + 1
                        return "set"
                    end
                    STAT.whip_set_miss = STAT.whip_set_miss + 1
                    return nil
                end
            end
        end
        -- 集合句柄在，但这次读不出来 → 落到 ② 兜底
        STAT.whip_set_miss = STAT.whip_set_miss + 1
    end
    if FIELDS.shoot then
        local s = read_field(FIELDS.shoot, item, "int")
        if s and WHIP_PROJ[s] then
            STAT.whip_proj_ok = STAT.whip_proj_ok + 1
            return "proj"
        end
        STAT.whip_proj_miss = STAT.whip_proj_miss + 1
        return nil
    end
    -- ③ 两个来源都拿不到
    STAT.whip_unknown = STAT.whip_unknown + 1
    if not whip_set_failed then
        whip_set_failed = true
        log_warn_once("whip_unknown",
            "属性工坊：ItemID.Sets 与 Item.shoot 都取不到，鞭子类攻速改写无法豁免（按普通召唤/近战处理）")
    end
    return nil
end

-- 每个物品类型只建一次计划：分类 + 记录原版基础值 + 登记「物品→弹幕」映射
build_info = function(item, itype)
    local cat = classify(item)
    local info = { itype = itype, cat = cat, entries = {}, n = 0, dirty = false }
    local specs = SPECS[cat]

    -- ★ 鞭子判定（只承认 summon 类物品；判定结果按类型缓存）
    local is_whip = false
    if cat == CAT.SUMMON and read_field(FIELDS.summon, item, "bool") == true then
        is_whip = (whip_kind(item, itype) ~= nil)
        if is_whip then STAT.whip_skipped = STAT.whip_skipped + 1 end
    end
    info.is_whip = is_whip

    if specs then
        for i = 1, #specs do
            local sp = specs[i]
            -- ★ 命中鞭子时跳过 useTime / useAnimation 的攻速改写（范围项本来也不碰它们）
            if not (is_whip and SPEED_FIELDS[sp.field]) then
                local fh = FIELDS[sp.field]
                if fh then
                    local base = read_field(fh, item, sp.kind)
                    local ok = base ~= nil
                    if ok and sp.only_positive then
                        ok = (type(base) == "number") and base > 0
                    end
                    if ok then
                        info.n = info.n + 1
                        info.entries[info.n] = { sp = sp, field = fh, base = base, target = base, last = nil }
                    end
                end
            end
        end
    end

    -- 经济类倍率（所有物品）
    for i = 1, #ECO_SPECS do
        local sp = ECO_SPECS[i]
        local fh = FIELDS[sp.field]
        if fh then
            local base = read_field(fh, item, sp.kind)
            if base ~= nil then
                info.n = info.n + 1
                info.entries[info.n] = { sp = sp, field = fh, base = base, target = base, last = nil }
            end
        end
    end

    -- 自动连用（force_true）
    local auto = AUTO_SWITCH[cat]
    if auto and FIELDS.autoReuse then
        local base = read_field(FIELDS.autoReuse, item, "bool")
        if base ~= nil then
            info.n = info.n + 1
            info.entries[info.n] = {
                sp = { setting = auto, kind = "bool", mode = "force_true" },
                field = FIELDS.autoReuse, base = base, target = base, last = nil,
            }
        end
    end

    -- 无限使用（force_false）：放置类走老开关，其余走分类开关
    local cons = consumable_setting(cat, item)
    if cons and FIELDS.consumable then
        local base = read_field(FIELDS.consumable, item, "bool")
        if base ~= nil then
            info.cons_setting = cons
            info.n = info.n + 1
            info.entries[info.n] = {
                sp = { setting = cons, kind = "bool", mode = "force_false" },
                field = FIELDS.consumable, base = base, target = base, last = nil,
            }
        end
    end

    -- 「物品 → 弹幕类型」映射（弹幕体型倍率用；同类型弹幕以后登记者为准）
    if PROJ_SCALE[cat] and FIELDS.shoot then
        local s = read_field(FIELDS.shoot, item, "int")
        if s and s > 0 then proj_cat[s] = cat end
    end

    compute_targets(info)
    return info
end

-- ============================================================================
-- 9. 句柄（setup 里解析一次）
-- ============================================================================
local F_type, F_inventory, F_who_am_i, F_my_player, F_main_player
local F_main_projectile, F_proj_type, F_proj_friendly, F_proj_scale
local F_net_mode                    -- Main.netMode（1.4.5.8 手机版：public static int 字段）
local M_get_my_player               -- Main.get_myPlayer（手机版 myPlayer 是属性，没有字段）
local M_get_game_menu                -- Main.get_gameMenu（手机版 gameMenu 是属性）
local M_new_text, new_text_args      -- Main.NewText（5 参优先，其次 4 参）
local M_chat_say                      -- SayChatCommand.ProcessIncomingMessage(string,byte)
local chat_hooked = 0                 -- 已装上的聊天钩子数（聊天指令关闭时必须为 0）
local chat_hook_fail = nil            -- 装钩子失败的原因（诊断用）
local SLUG = "itemforge"
local EXPORT_FILE = "forge_export.txt"
local SHARD_BODY = 320
local import_active = nil             -- 正在应用的那条设置串（导入并发保护）
local import_seen_raw = nil           -- 已处理过的 import_string 原文（防重复应用）
local import_pending_msg = nil        -- 非世界内导入的结果，等进世界后补播
-- ★ 这三个必须声明在「会读它们的函数」之前：Lua 的 local 作用域从声明行开始，
--   写在使用点之后会静默变成全局（nil），表现为「进世界后播报全哑」。
local in_world = false                -- 进世界边沿标记（进世界首帧播报的门控）
local import_cache = nil              -- 聊天分片缓存
local self_check_count = 0            -- 自检播报次数
local M_item_prefix, M_get_rollable  -- Item.Prefix(int) / Item.GetRollablePrefixes()
local M_get_tracker                  -- Main.get_LocalPlayerCreativeTracker()
local F_tracker_sacrifices           -- CreativeUnlocksTracker.ItemSacrifices
local M_register_sacrifice           -- ItemsSacrificedUnlocksTracker.RegisterItemSacrifice(int,int,string)

local net_mode_cache = 0            -- netMode 缓存，跟设置重读同节拍刷新（不逐帧反射读）
local net_mode_ready = false        -- 第一次写入口之前必须先确证一次联机身份
local item_hooked = 0
local debug_types_logged = 0
local logged_first_apply = false
local whip_set_ok_count = 0

-- 调静态方法的唯一入口：先核形参个数再传（传多传少都会崩），并 pcall 包住。
local function invoke_static(m, ...)
    if not m then return nil end
    local n = select("#", ...)
    if patch.method_param_count then
        local okc, cnt = pcall(patch.method_param_count, m)
        if okc and tonumber(cnt) and tonumber(cnt) ~= n then return nil end
    end
    local ok, v = pcall(patch.invoke, m, ...)
    if not ok or v == false then return nil end
    return v
end

-- 调实例方法的唯一入口：实参个数 = 形参个数（实例槽位不算）。
local function invoke_inst(m, inst, ...)
    if not m or not inst then return nil end
    local n = select("#", ...)
    if patch.method_param_count then
        local okc, cnt = pcall(patch.method_param_count, m)
        if okc and tonumber(cnt) and tonumber(cnt) ~= n then return nil end
    end
    local ok, v = pcall(patch.invoke, m, inst, ...)
    if not ok then return nil end
    return v
end

-- 手机版把 Main.myPlayer / Main.gameMenu 改成了属性：优先属性桥接，其次 get_X 方法。
local function resolve_static_getter(type_handle, prop_name, getter_name)
    if not type_handle then return nil end
    if patch.get_property and patch.property_get_method then
        local okp, prop = pcall(patch.get_property, type_handle, prop_name)
        if okp and prop then
            local okg, g = pcall(patch.property_get_method, prop)
            if okg and g then return g end
        end
    end
    return safe_get_method(type_handle, getter_name, 0)
end

-- netMode：0 = 单机、1 = 客机、2 = 服务器。取不到句柄就退化成「不限制」。
local function refresh_net_mode()
    net_mode_ready = true
    if not F_net_mode then net_mode_cache = 0 return end
    local ok, v = pcall(patch.get_field_value, F_net_mode, nil, "int32")
    if ok and type(v) == "number" then
        net_mode_cache = math.floor(v)
    else
        net_mode_cache = 0
    end
end

local function ensure_net_mode()
    if not net_mode_ready then refresh_net_mode() end
end

-- 联机「仅房主生效」：客机（netMode == 1）只读不写、不介入游戏数据
local function is_client()
    return cfg.host_only ~= false and net_mode_cache == 1
end

-- ============================================================================
-- 10. 最高词缀（§4.3-6）
--   核查结论（可行）：手机版 TSV 有
--     Terraria.GameContent.Prefixes.PrefixLegacy（类型表 :2577）+ 嵌套类
--       PrefixLegacy.ItemSets（:2576，含 SwordsHammersAxesPicks / Magic / Summon /
--         GunsBows / SpearsMacesChainsawsDrillsPunchCannon / BoomerangsChakrums /
--         ItemsThatCanHaveLegendary2，全是 bool[]）
--       PrefixLegacy.Prefixes（:2575，含 PrefixesForSwords / ... 全是 int[]）
--     字段偏移见 官方源码-字段.tsv:41543-41558（readonly=是、const 空 → 可读）。
--   但**不需要**在 Lua 里重写 PC 的 GetRollablePrefixes() 分类逻辑：
--     手机版 Item.GetRollablePrefixes()（0 参，方法表）直接返回该物品可附前缀的 int[]，
--     而 PC PrefixLegacy.cs 里每个数组都是按品质升序排列、最后一档就是该类的最高词缀
--     （Swords→81 Legendary，GunsBows→82 Unreal，Magic→83 Mythical，
--       BoomeransAndChakrums_TerrarianYoyo→84，Summons→39 Ruthless）。
--   所以：best_prefix = 取数组最后一个元素 → Item.Prefix(int)。
--   幂等：只在 Item.prefix == 0（还没有词缀）时动作，绝不覆盖玩家已有的词缀。
-- ============================================================================
local prefix_busy = false

local function apply_best_prefix(item)
    if prefix_busy then return false end
    if not (cfg.best_prefix and M_item_prefix and M_get_rollable and FIELDS.prefix) then return false end
    STAT.prefix_calls = STAT.prefix_calls + 1
    local cur = read_field(FIELDS.prefix, item, "byte")
    if cur == nil or cur ~= 0 then return false end       -- 已有词缀 → 不碰
    local ok, arr = pcall(patch.invoke, M_get_rollable, item)
    if not ok then
        D_PREFIX.errs = D_PREFIX.errs + 1
        return false
    end
    if not arr or arr == false then return false end      -- 该物品不可附词缀
    local okn, n = pcall(patch.array_length, arr)
    if not okn or type(n) ~= "number" or n <= 0 then return false end
    local okv, best = pcall(patch.array_at, arr, n - 1, "int32")
    if not okv or type(best) ~= "number" or best <= 0 then return false end
    prefix_busy = true
    local okp = pcall(patch.invoke, M_item_prefix, item, best)
    prefix_busy = false
    if okp then
        STAT.prefix_hits = STAT.prefix_hits + 1
        D_PREFIX.hits = D_PREFIX.hits + 1
        return true
    end
    STAT.prefix_errs = STAT.prefix_errs + 1
    D_PREFIX.errs = D_PREFIX.errs + 1
    return false
end

-- ============================================================================
-- 11. 研究自动解锁（§4.3-9）
--   核查结论（可行，走标量参方法）：
--     手机版 TSV 有 Main.get_LocalPlayerCreativeTracker（0 参公共静态属性 getter，
--     字段表「Terraria.Main LocalPlayerCreativeTracker ... [属性] readonly=是」），
--     CreativeUnlocksTracker.ItemSacrifices（官方源码-字段.tsv:43997，0x10），
--     ItemsSacrificedUnlocksTracker.RegisterItemSacrifice(int,int,string)
--     （官方源码-方法.tsv:24679，3 参、全标量/引用，可 invoke）。
--   RegisterItemSacrifice 自身幂等（PC ItemsSacrificedUnlocksTracker.cs:116-137：
--     `if (value3 >= amountNeeded) return;`），所以重复调用安全。
--   amount 用 POSITIVE_SACRIFICE_COUNT_CAP（const，值 9999，取自字段表
--     「...POSITIVE_SACRIFICE_COUNT_CAP int public const 是 是 9999」—— 抄值不读字段）。
--   teammateName 传空托管字符串（本代无法安全传 null；副作用只是把
--     AnyNewUnlocksFromTeammates 置 true，属于 UI 上的小提示，不影响解锁）。
--   分帧执行：每次桶访问处理 RESEARCH_BATCH 个物品 ID，避免一帧里跑满 6200 次调用。
--   图鉴（Bestiary）解锁**未实现**：入口 BestiaryUnlocksTracker.Kills 需要
--     NPCKillsTracker.RegisterKill(NPC) —— 必须真的构造/持有一个 NPC 实例，
--     代价与风险都过高，见 README「为什么这几个功能做不到」。
-- ============================================================================
local RESEARCH_BATCH = 200
local research_cursor = 1
local research_obj = nil
local str_empty = nil

local function research_step()
    if not cfg.research_unlock or STAT.research_finished then return end
    if not (M_get_tracker and F_tracker_sacrifices and M_register_sacrifice) then return end
    local t0 = os.clock and os.clock() or 0
    if not research_obj then
        local tracker = invoke_static(M_get_tracker)
        if tracker then
            local ok, obj = pcall(patch.get_field_value, F_tracker_sacrifices, tracker, "object")
            if ok and obj then research_obj = obj end
        end
        if not research_obj then
            D_RESEARCH.errs = D_RESEARCH.errs + 1
            D_RESEARCH.last_err = "拿不到 ItemSacrifices 实例"
            STAT.research_errs = STAT.research_errs + 1
            return
        end
    end
    if not str_empty and patch.string_create then
        local ok, s = pcall(patch.string_create, "")
        if ok and s then str_empty = s end
    end
    if not str_empty then return end
    local last = research_cursor + RESEARCH_BATCH - 1
    if last > ITEM_CEILING then last = ITEM_CEILING end
    for id = research_cursor, last do
        local ok = pcall(patch.invoke, M_register_sacrifice, research_obj, id, 9999, str_empty)
        if ok then
            STAT.research_done = STAT.research_done + 1
            D_RESEARCH.hits = D_RESEARCH.hits + 1
        else
            D_RESEARCH.errs = D_RESEARCH.errs + 1
            STAT.research_errs = STAT.research_errs + 1
        end
    end
    research_cursor = last + 1
    if os.clock then D_RESEARCH.t_total = D_RESEARCH.t_total + (os.clock() - t0) end
    if research_cursor > ITEM_CEILING then
        STAT.research_finished = true
        log_info(string.format("属性工坊：研究自动解锁完成（共请求 %d 个物品 ID）", STAT.research_done))
    end
end

-- ============================================================================
-- 12. 核心：一个物品实例的处理
-- ============================================================================
local function apply_item(instance, force)
    -- ★ 写入口第一件事：联机客机只读不写（host_only 关掉时不限制）
    ensure_net_mode()
    if is_client() then return end
    if (not ready and not force) or not instance then return end
    local itype = read_field(F_type, instance, "int")
    if not itype or itype <= 0 then return end

    D_ITEM.calls = D_ITEM.calls + 1
    STAT.item_calls = STAT.item_calls + 1
    -- 诊断耗时（/forge stat 的 SLOW 判定用）；os.clock 缺失时自动跳过
    local t0 = os.clock and os.clock() or nil

    local info = item_info[itype]
    if not info then
        info = build_info(instance, itype)
        item_info[itype] = info
        if cfg.write_log and cfg.debug_log and debug_types_logged < 40 then
            debug_types_logged = debug_types_logged + 1
            log_debug(string.format("属性工坊：物品类型 %d 归入「%s」（%d 项属性%s）",
                itype, CAT_NAME[info.cat] or "?", info.n, info.is_whip and "，鞭子：跳过攻速" or ""))
        end
    end

    local did = false
    if info.dirty then
        local ok, writes = pcall(apply_info, instance, info)
        if not ok then
            D_ITEM.errs = D_ITEM.errs + 1
            D_ITEM.last_err = tostring(writes)
            STAT.item_errs = STAT.item_errs + 1
            log_warn_once("apply_error", "属性工坊：改写物品字段失败（已忽略该次）：" .. tostring(writes))
        elseif writes and writes > 0 then
            did = true
            STAT.item_writes = STAT.item_writes + writes
            D_ITEM.hits = D_ITEM.hits + 1
            if not logged_first_apply then
                logged_first_apply = true
                log_info("属性工坊：属性倍率已生效")
            end
        end
    end

    -- 最高词缀（只在开启且物品还没有词缀时动手；异常单独计数，不影响上面）
    if cfg.best_prefix then
        local okp, r = pcall(apply_best_prefix, instance)
        if okp and r then did = true end
    end
    if t0 and os.clock then D_ITEM.t_total = D_ITEM.t_total + (os.clock() - t0) end
    return did
end

-- 物品创建的两个入口（postfix 回调签名统一为 instance, args, result）
local function on_set_defaults(instance, args, result)
    apply_item(instance, false)
end

local function on_net_defaults(instance, args, result)
    apply_item(instance, false)
end

-- ============================================================================
-- 13. 背包刷新（进世界后的兜底 + 改设置后的即时生效）
-- ============================================================================
local function read_static_int(field)
    if not field then return nil end
    local ok, v = pcall(patch.get_field_value, field, nil, "int32")
    if not ok then return nil end
    return tonumber(v)
end

-- Main.myPlayer：手机版是属性（get_myPlayer），字段取不到就走 getter
local function read_my_player()
    local v = read_static_int(F_my_player)
    if v ~= nil then return v end
    if M_get_my_player then
        local r = invoke_static(M_get_my_player)
        if type(r) == "number" then return r end
    end
    return nil
end

local function sweep_inventory(player)
    if not F_inventory or not player then return 0 end
    local ok, arr = pcall(patch.get_field_value, F_inventory, player, "object")
    if not ok or not arr then return 0 end
    local ok2, n = pcall(patch.array_length, arr)
    if not ok2 or type(n) ~= "number" or n <= 0 then return 0 end
    if n > MAX_SWEEP_SLOTS then n = MAX_SWEEP_SLOTS end

    local touched = 0
    D_SWEEP.calls = D_SWEEP.calls + 1
    STAT.sweep_calls = STAT.sweep_calls + 1
    for i = 0, n - 1 do
        local ok3, item = pcall(patch.array_at, arr, i)
        if ok3 and item then
            if pcall(apply_item, item, true) then touched = touched + 1 end
        end
    end
    STAT.sweep_items = STAT.sweep_items + touched
    D_SWEEP.hits = D_SWEEP.hits + touched
    return touched
end

-- 没有玩家实例时（例如卸载时）从 Main.player[Main.myPlayer] 取本机玩家
local function sweep_main_player()
    if not F_main_player or not F_inventory then return false end
    local my = read_my_player()
    if my == nil then return false end
    local ok, arr = pcall(patch.get_field_value, F_main_player, nil, "object")
    if not ok or not arr then return false end
    local ok2, player = pcall(patch.array_at, arr, my)
    if not ok2 or not player then return false end
    sweep_inventory(player)
    return true
end

local function is_local_player(player)
    if not F_who_am_i then return true end   -- 取不到就按单机处理
    local who = read_field(F_who_am_i, player, "int")
    local my = read_my_player()
    if who == nil or my == nil then return true end
    return who == my
end

-- ============================================================================
-- 14. 聊天栏（§4.6 输出统一走 chat_print）
-- ============================================================================
-- ★ §9：聊天指令总开关。关闭时全模组不碰任何 Chat 类型、不装聊天钩子。
local function chat_cmd_on()
    return cfg.chat_cmd == true
end

-- ★ 前置声明：chat_print 在下面才定义，而 chat_print_result 要引用它 ——
--   local 的作用域从声明行开始，不前置声明会静默变成全局（nil）。
local chat_print

-- 导入/导出结果的播报入口：只在游戏内（收到命令 / 进世界首帧）才真的打印，
-- 否则缓存到 import_pending_msg，等进世界首帧补播一次 —— setup() 里零 invoke。
local function chat_print_result(text)
    if type(text) ~= "string" or text == "" then return end
    if not in_world then
        -- 主菜单/装载期的结果缓存下来，等进世界首帧补播（setup 阶段零 invoke）
        import_pending_msg = text
        return
    end
    chat_print(text)
end

chat_print = function(text)
    if type(text) ~= "string" or text == "" then return false end
    if not M_new_text or new_text_args == 0 then return false end
    local arg = text
    if patch.string_create then
        local oks, h = pcall(patch.string_create, text)
        if oks and h then arg = h end
    end
    local ok
    if new_text_args == 5 then
        ok = pcall(patch.invoke, M_new_text, arg, 255, 210, 70, false)
    else
        ok = pcall(patch.invoke, M_new_text, arg, 255, 210, 70)
    end
    if not ok then
        M_new_text, new_text_args = nil, 0
        log_warn_once("newtext_fail", "属性工坊：Main.NewText 调用失败，已关闭聊天栏播报")
        return false
    end
    return true
end

-- ============================================================================
-- 15. 自检播报 / 详细报告（§4.6-1、§4.6-2）
-- ============================================================================
local MOD_TAG = "[属性工坊]"

local function mark(flag)
    if flag == "ok" then return "✅" end
    if flag == "partial" then return "⚠️" end
    if flag == "n/a" then return "—" end     -- 该域不需要钩子（纯字段/方法级）
    return "❌"
end

-- 进世界首帧播报：每个功能域一行，最多 12 行，超出折叠
local function run_self_check()
    STAT.self_check_runs = STAT.self_check_runs + 1
    self_check_count = self_check_count + 1
    local okf, okh = 0, 0
    for i = 1, #DIAG do
        if DIAG[i].fields == "ok" then okf = okf + 1 end
        if DIAG[i].hooks == "ok" then okh = okh + 1 end
    end
    chat_print(string.format("%s 启动自检（第 %d 次）：共 %d 个功能域，句柄 %d✅ / 钩子 %d✅",
        MOD_TAG, self_check_count, #DIAG, okf, okh))
    local shown = 0
    for i = 1, #DIAG do
        local d = DIAG[i]
        if shown < 12 then
            if not d.enabled then
                chat_print(string.format("%s 域 %s：句柄%s 钩子%s 已停用", MOD_TAG, d.name, mark(d.fields), mark(d.hooks)))
            else
                chat_print(string.format("%s 域 %s：句柄%s 钩子%s 本帧命中 %d 次",
                    MOD_TAG, d.name, mark(d.fields), mark(d.hooks), d.hits))
            end
            shown = shown + 1
        end
    end
    if #DIAG > shown then
        chat_print(string.format("%s …… 其余 %d 个域已折叠（输入 /forge stat 查看）", MOD_TAG, #DIAG - shown))
    end
    chat_print(string.format("%s 输入 /forge help 查看命令；/forge stat 看详细统计", MOD_TAG))
    D_FRAME.hits = D_FRAME.hits + 1
end

local function report_domain_slow(d)
    local slow_ms = math.floor(tonumber(cfg.diag_slow_ms) or 50)
    if not d.calls or d.calls <= 0 then return "" end
    local avg = (d.t_total / d.calls) * 1000
    if avg >= slow_ms then return string.format(" SLOW(%.2fms)", avg) end
    return ""
end

local function report()
    chat_print(string.format("%s 统计：物品创建 %d 次 / 写入 %d 项 / 失败 %d 次",
        MOD_TAG, STAT.item_calls, STAT.item_writes, STAT.item_errs))
    for i = 1, #DIAG do
        local d = DIAG[i]
        local avg = (d.calls > 0) and (d.t_total / d.calls) * 1000 or 0
        chat_print(string.format("%s 域 %s：句柄%s 钩子%s calls=%d hits=%d errs=%d avg=%.3fms%s",
            MOD_TAG, d.name, mark(d.fields), mark(d.hooks), d.calls, d.hits, d.errs, avg, report_domain_slow(d)))
        if d.last_err then
            chat_print(string.format("%s   最近错误：%s", MOD_TAG, tostring(d.last_err)))
        end
    end
    chat_print(string.format("%s 鞭子判定：集合命中 %d / 集合未命中 %d / 弹幕表命中 %d / 弹幕表未命中 %d / 判定失败 %d / 跳过攻速 %d",
        MOD_TAG, STAT.whip_set_ok, STAT.whip_set_miss, STAT.whip_proj_ok, STAT.whip_proj_miss,
        STAT.whip_unknown, STAT.whip_skipped))
    chat_print(string.format("%s 使用时间下限夹取 %d 次（min_use_time=%d）；经济写入 %d 次；消耗品写入 %d 次",
        MOD_TAG, STAT.speed_clamped, math.floor(tonumber(cfg.min_use_time) or 3), STAT.econ_writes, STAT.cons_writes))
    chat_print(string.format("%s ID 过滤：白名单 %d 项 / 黑名单 %d 项；被拒绝改写 %d 次；背包刷新 %d 次 / %d 件",
        MOD_TAG, id_filter_stat.wl, id_filter_stat.bl, STAT.id_denied, STAT.sweep_calls, STAT.sweep_items))
    chat_print(string.format("%s 词缀：尝试 %d 次 / 成功 %d 次 / 失败 %d 次；研究解锁：已请求 %d 个 ID（%s）",
        MOD_TAG, STAT.prefix_calls, STAT.prefix_hits, STAT.prefix_errs, STAT.research_done,
        STAT.research_finished and "已完成" or "进行中"))
    chat_print(string.format("%s 弹幕体型：回调 %d 次 / 命中 %d 次 / 失败 %d 次；聊天收包 %d 次 / 命令 %d 次",
        MOD_TAG, STAT.proj_calls, STAT.proj_hits, STAT.proj_errs, STAT.chat_in, STAT.chat_cmds))
    chat_print(string.format("%s 设置：%s", MOD_TAG, settings_summary()))
end

-- ============================================================================
-- 16. 设置串导出 / 导入（§3.1 方案 B + §3 分片格式）
-- ============================================================================

local function esc_val(s)
    local out = tostring(s):gsub("([;|=%%])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return out
end

local function unesc_val(s)
    local out = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return out
end

local function checksum_of(text)
    local sum = 0
    for i = 1, #text do sum = (sum + text:byte(i)) % 65521 end
    return sum
end

-- 拼出完整设置串（不带分片头）
local function build_export_string(all)
    local parts, n = {}, 0
    for key, default in pairs(DEFAULTS) do
        local v = cfg[key]
        if all or v ~= default then
            local lit
            local t = type(default)
            if t == "boolean" then
                lit = v and "true" or "false"
            elseif t == "string" then
                lit = esc_val(v)
            else
                lit = tostring(math.floor(tonumber(v) or 0))
            end
            n = n + 1
            parts[n] = key .. "=" .. lit
        end
    end
    table.sort(parts)
    local body = "forge:" .. SLUG .. "|" .. table.concat(parts, ";")
    return body .. "|#" .. string.format("%x", checksum_of(body))
end

-- 导出：**始终**把整串落到模组私有目录的 forge_export.txt，然后在游戏内播报一次。
--   ★ 不依赖聊天输入，单机与客机都可用（§9.3）。聊天分片只是给 chat_cmd 打开时的便利。
--   （全局函数：导出通道本身与聊天无关，测试也直接按名字调用它）
function do_export_all(arg)
    local all = (arg == "all")
    local full = build_export_string(all)
    local n = 0
    for _ in full:gmatch("[^;]+") do n = n + 1 end
    local ok = mod.write_file(EXPORT_FILE, full)
    local parts, total = {}, 0
    if chat_cmd_on() then
        local i = 1
        while i <= #full do
            total = total + 1
            parts[total] = full:sub(i, i + SHARD_BODY - 1)
            i = i + SHARD_BODY
        end
        if total == 0 then total = 1 parts[1] = "" end
    end
    if not ok then
        chat_print_result(string.format("%s 导出失败：写 %s 出错（模组私有目录不可写）", MOD_TAG, EXPORT_FILE))
        return false, parts, total
    end
    chat_print_result(string.format("%s 已导出 %d 项到模组私有目录 %s%s",
        MOD_TAG, n, EXPORT_FILE, all and "（全量）" or "（只含与默认值不同的项）"))
    return true, parts, total
end

-- 聊天侧的导出：文件落盘 + 逐片打印（分片只为方便在聊天栏里复制）
local function do_export(arg)
    local ok, parts, total = do_export_all(arg)
    if not ok then return end
    if total <= 1 then
        chat_print(string.format("%s 设置串（%s，%d 字符，未分片）：", MOD_TAG,
            (arg == "all") and "全部" or "仅非默认项", #(parts[1] or "")))
        chat_print(parts[1] or "")
        return
    end
    chat_print(string.format("%s 串较长，分 %d 片（按顺序复制后执行 /forge import <片>）；"
        .. "也可以直接把整串粘贴进设置项 import_string", MOD_TAG, total))
    for i = 1, total do
        chat_print(string.format("[%d/%d] %s", i, total, parts[i]))
    end
end

-- 只替换该 key 的值，绝不整文件重写（未知 key 与 schemaVersion 原样保留）
local function rewrite_config(raw, key, default, lit)
    local esc = key:gsub("([^%w])", "%%%1")
    local t = type(default)
    local pat
    if t == "boolean" then
        pat = '("' .. esc .. '"%s*:%s*)(%a+)'
    elseif t == "string" then
        pat = '("' .. esc .. '"%s*:%s*)("[^"]*")'
    else
        pat = '("' .. esc .. '"%s*:%s*)(-?%d+)'
    end
    local out, cnt = raw:gsub(pat, function(a) return a .. lit end)
    if cnt > 0 then return out, true end
    -- config.json 里还没有这个 key（例如从未改过它）→ 补进 values 对象
    local json_lit
    if t == "boolean" or t == "string" then
        json_lit = '"' .. esc .. '":' .. ((t == "string") and ('"' .. lit .. '"') or lit)
    else
        json_lit = '"' .. esc .. '":' .. lit
    end
    local ok, patched = pcall(string.gsub, out, '("values"%s*:%s*{)', function(a) return a .. json_lit .. "," end, 1)
    if ok and patched and patched ~= out then return patched, true end
    return out, false
end

local function apply_import_pairs(pairs_tbl)
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then
        chat_print(MOD_TAG .. " 导入失败：读不到 config.json")
        return false
    end
    local changed, ignored, bad_type, bad_write = 0, 0, 0, 0
    for key, lit in pairs(pairs_tbl) do
        local default = DEFAULTS[key]
        if default == nil then
            ignored = ignored + 1
        else
            local t = type(default)
            local new_lit, ok_type = nil, false
            if t == "boolean" then
                if lit == "true" or lit == "false" then new_lit, ok_type = lit, true end
            elseif t == "string" then
                if not lit:find('"', 1, true) then new_lit, ok_type = lit, true end
            else
                local v = tonumber(lit)
                if v then
                    local lim = LIMITS[key]
                    v = math.floor(v)
                    if lim then
                        if v < lim[1] then v = lim[1] end
                        if v > lim[2] then v = lim[2] end
                    end
                    new_lit, ok_type = tostring(v), true
                end
            end
            if not ok_type then
                bad_type = bad_type + 1
            else
                local out, okw = rewrite_config(raw, key, default, new_lit)
                if okw then raw = out changed = changed + 1 else bad_write = bad_write + 1 end
            end
        end
    end
    if changed == 0 then
        return false, string.format("%s 导入失败：%d 项值非法 / %d 项未知键 / %d 项写入失败（未改动任何设置）",
            MOD_TAG, bad_type, ignored, bad_write)
    end
    local okw = mod.write_file("config.json", raw)
    if not okw then
        return false, MOD_TAG .. " 导入失败：写 config.json 出错（未改动任何设置）"
    end
    if load_config_from(raw) then
        last_config_raw = raw
        recompute_all()
        pending_sweep = true
    end
    return true, string.format("%s 已导入 %d 项（未知键 %d / 值非法 %d / 写入失败 %d）；设置：%s",
        MOD_TAG, changed, ignored, bad_type, bad_write, settings_summary())
end

-- 纯导入：给一条完整设置串就校验 + 应用，返回 (ok, 消息)。不主动播报 ——
--   聊天通道与 import_string 通道共用这一条实现（§3.3）。
--   返回的第三个值 other_slug=true 表示「这是别的模组的串」，聊天侧要静默忽略。
local function import_from_string(arg)
    if type(arg) ~= "string" or arg == "" then
        return false, MOD_TAG .. " 导入失败：设置串为空", false
    end
    local slug, payload, sum = arg:match("^forge:(%w+)%|(.*)%|#(%x+)$")
    if not slug then
        return false, MOD_TAG .. " 导入失败：串格式不对（应为 forge:<slug>|<k>=<v>;…|#<sum>）", false
    end
    if slug ~= SLUG then
        return false, nil, true         -- 别的模组的串：静默忽略
    end
    local want = tonumber(sum, 16)
    local body = "forge:" .. slug .. "|" .. payload
    if want ~= checksum_of(body) then
        return false, MOD_TAG .. " 导入失败：校验和不匹配（串被截断或改坏了）", false
    end
    local pairs_tbl, n = {}, 0
    for kv in payload:gmatch("[^;]+") do
        local k, v = kv:match("^([%w_]+)=(.*)$")
        if k then n = n + 1 pairs_tbl[k] = unesc_val(v) end
    end
    if n == 0 then
        return false, MOD_TAG .. " 导入失败：串里没有任何设置项", false
    end
    local ok, msg = apply_import_pairs(pairs_tbl)
    return ok, msg, false
end

-- 聊天通道（支持 [i/n] 分片 + reset）
local function do_import(arg)
    if arg == nil or arg == "" then
        chat_print(MOD_TAG .. " 用法：/forge import <设置串>（或 /forge import reset 放弃已缓存分片）")
        return
    end
    if arg:lower() == "reset" then
        local had = import_cache and true or false
        import_cache = nil
        chat_print(MOD_TAG .. (had and " 已放弃缓存的分片" or " 本来就没有缓存的分片"))
        return
    end
    local idx, total, piece = arg:match("^%[(%d+)%s*/%s*(%d+)%]%s*(.*)$")
    if idx then
        idx, total = tonumber(idx), tonumber(total)
        if not import_cache or import_cache.total ~= total then
            import_cache = { total = total, parts = {} }
        end
        import_cache.parts[idx] = piece
        local have = 0
        for i = 1, total do if import_cache.parts[i] then have = have + 1 end end
        if have < total then
            for i = 1, total do
                if not import_cache.parts[i] then
                    chat_print(string.format("%s 已收 %d/%d 片，缺第 %d 片", MOD_TAG, have, total, i))
                    return
                end
            end
            return
        end
        local buf = {}
        for i = 1, total do buf[i] = import_cache.parts[i] end
        import_cache = nil
        arg = table.concat(buf)
    end
    local ok, msg, other = import_from_string(arg)
    if other then return end            -- 别的模组的串：静默忽略
    if msg then chat_print(msg) end
    if not ok then D_CHAT.errs = D_CHAT.errs + 1 end
end

-- ============================================================================
-- 17.1 默认（零聊天依赖）导入通道：设置项 import_string（§9.3）
--      玩家把整串粘贴进 TEFManager 设置界面即可；应用后立刻清空该项并播报结果。
-- ============================================================================
local function find_value_span(raw, key)
    local esc = key:gsub("([^%w])", "%%%1")
    local ks, ke = raw:find('"' .. esc .. '"%s*:%s*', 1)
    if not ks then return nil end
    local vs = ke + 1
    local rest = raw:sub(vs)
    local off
    if rest:sub(1, 1) == '"' then
        local st = vs + 1
        local i = 1
        while i <= #rest do
            local c = rest:byte(i)
            if c == 92 then i = i + 2          -- 反斜杠：跳过被转义的字符
            elseif c == 34 then break          -- 字符串结束
            else i = i + 1 end
        end
        return st, vs + i - 1
    end
    off = rest:find("[,%}%s]")
    return vs, off and (vs + off - 2) or #raw
end

-- 就地清空 import_string（只替换这一个字面量，其它一个字符都不动）
local function clear_import_string()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then return false end
    local vs, ve = find_value_span(raw, "import_string")
    if vs then
        local out = raw:sub(1, vs - 1) .. '""' .. raw:sub(ve + 1)
        if out ~= raw then return mod.write_file("config.json", out) and true or false end
    end
    return false
end

-- 检查 import_string 是否被粘贴了新串；是就校验 + 应用 + 清空 + 播报。
--   由逐帧钩子按 config_reload_sec 的节拍调用（不依赖聊天输入，单机/客机都可用）。
local function tick_import_string()
    local raw = tostring(cfg.import_string or "")
    if raw == "" then
        import_seen_raw = raw
        return
    end
    if raw == import_seen_raw then return end       -- 已经处理过这条（含清空后的空串）
    if import_active then return end
    import_active = true
    import_seen_raw = raw
    local ok, msg, other = import_from_string(raw)
    if not other then
        if not ok then
            chat_print_result((msg or (MOD_TAG .. " 导入失败")) .. "（import_string 中的串未生效）")
            D_CHAT.errs = D_CHAT.errs + 1
        else
            clear_import_string()                   -- 成功才清空，失败留着让玩家改
            last_config_raw = mod.read_file("config.json") or last_config_raw
            chat_print_result((msg or "") .. "；已清空设置项 import_string")
        end
    end
    import_active = nil
end

-- ============================================================================
-- 17. 聊天命令入口（§2 + §9.2）
--     ★ 聊天文本只从 SayChatCommand.ProcessIncomingMessage(string,byte) 读；
--       get_type/get_method 只碰 Terraria.Chat.Commands.SayChatCommand 这一个类型，
--       绝不触达 Terraria.Chat 的消息对象类型（实机 SIGABRT 点，见开发文档 05 §5.2）。
-- ============================================================================
local FORGE_CMDS = {
    help = true, stat = true, check = true, export = true, import = true,
}

-- 解析一条聊天文本，三态返回 (state, cmd, arg)：
--   state == "ours"      → 本模组认识、要处理（拦截，不当普通聊天广播）
--   state == "unknown"   → 是 /forge 命名空间，但不认识这个小命令（提示 + 拦截）
--   state == "other"     → 与本模组无关（返回 nil，让原版照常当普通聊天处理）
local function recognized_cmd(text)
    if type(text) ~= "string" then return "other" end
    local t = (text:gsub("^%s*/?%s*", ""):gsub("%s+$", ""))
    if t == "" then return "other" end
    -- ★ 括号不能省：gsub 返回 (串, 替换次数)，漏掉会污染后面的比较
    local extra = (tostring(cfg.diag_report_cmd or ""):gsub("^%s*/?%s*", ""):gsub("%s+$", ""))
    if extra ~= "" and t:lower() == extra:lower() then return "ours", "\0diag", "" end
    local head, rest = t:match("^(%S+)%s*(.*)$")
    if not head or head:lower() ~= "forge" then return "other" end
    rest = rest or ""
    local cmd, arg = rest:match("^(%S*)%s*(.*)$")
    cmd = cmd or ""
    if cmd == "" then return "ours", "help", arg or "" end
    if FORGE_CMDS[cmd:lower()] then return "ours", cmd:lower(), arg or "" end
    return "unknown", cmd, arg or ""
end

local function handle_command(text)
    local state, cmd, arg = recognized_cmd(text)
    if state == "other" then return false end
    if state == "unknown" then
        STAT.chat_cmds = STAT.chat_cmds + 1
        chat_print(MOD_TAG .. " 未知命令：" .. cmd .. "（试试 /forge help）")
        return true
    end
    if cmd == "\0diag" then
        STAT.chat_cmds = STAT.chat_cmds + 1
        report()
        return true
    end
    STAT.chat_cmds = STAT.chat_cmds + 1
    if cmd == "" or cmd == "help" then
        chat_print(MOD_TAG .. " 可用命令（需要设置项「聊天指令」chat_cmd 打开）：")
        chat_print("  /forge help          本帮助")
        chat_print("  /forge stat          诊断统计（每域 calls/hits/errs、鞭子判定、夹取次数）")
        chat_print("  /forge check         重跑一次启动自检并播报")
        chat_print("  /forge export        导出设置串（同时落盘 forge_export.txt）")
        chat_print("  /forge export all    导出全部设置项")
        chat_print("  /forge import <串>   导入设置串（支持 [i/n] 分片）")
        chat_print("  /forge import reset  放弃已缓存的分片")
        chat_print("  ★ 客机上自己的聊天先送服务器，命令可能收不到；")
        chat_print("    请优先用设置项 import_string 粘贴导入、用 forge_export.txt 导出。")
    elseif cmd == "stat" then
        report()
    elseif cmd == "check" then
        run_self_check()
    elseif cmd == "export" then
        do_export(arg or "")
    elseif cmd == "import" then
        do_import(arg or "")
    end
    return true
end

-- 唯一的聊天文本入口（§9.2）：
--   Terraria.Chat.Commands.SayChatCommand.ProcessIncomingMessage(string text, byte clientId)
--   它是 ChatInitializer 注册的 _defaultCommand —— 普通聊天与任何「未知 /命令」的**原文**
--   都会原样送到这里；参数全是标量（string + byte），不碰任何 Chat 消息对象。
local function on_say_chat(instance, args, result)
    if not args then return nil end
    local text = args[1]
    if type(text) ~= "string" then return nil end
    STAT.chat_in = STAT.chat_in + 1
    D_CHAT.calls = D_CHAT.calls + 1
    -- 只处理本机玩家。args[2] 是 clientId（byte），Main.myPlayer 是属性 → 走 getter。
    local my = read_my_player()
    local sender_ok = false
    local id = args[2]
    if type(id) == "number" and my ~= nil then
        sender_ok = (math.floor(id) == math.floor(my))
        if not sender_ok then return nil end               -- 别人的消息：一个字都不动
    end
    if not sender_ok then
        -- 身份取不到（退化）时宁可不动：只有明确带本模组命令名才继续
        if not (text:match("^%s*/?%s*forge[%s/]") or text:match("^%s*/?%s*forge$")
                or text:match("^%s*/?%s*forge:")) then
            return nil
        end
    end
    if not handle_command(text) then return nil end
    -- ★ prefix 返回 true = 跳过原方法 → 顺手阻止这串被原版当普通聊天广播出去
    return true
end

-- ============================================================================
-- 18. 逐帧钩子：进世界门控 + 设置热重载 + 分桶工作
-- ============================================================================
local fallback_counter = 0
local frame_counter = 0             -- 帧号（1 起）
local last_reload_check = 0         -- 上一次「设置比对 + netMode 刷新」的时间戳（秒）

local function invoke_static_raw(m, ...)
    if not m then return nil end
    local n = select("#", ...)
    if patch.method_param_count then
        local okc, cnt = pcall(patch.method_param_count, m)
        if okc and tonumber(cnt) and tonumber(cnt) ~= n then return nil end
    end
    local ok, v = pcall(patch.invoke, m, ...)
    if not ok then return nil end
    return v
end

-- Main.gameMenu：手机版是属性 → 走 get_gameMenu；取不到返回 nil（按「已进世界」处理）
local function read_game_menu()
    if not M_get_game_menu then return nil end
    local v = invoke_static_raw(M_get_game_menu)
    if v == true then return true end
    if v == false then return false end
    return nil
end

local function on_reset_effects(instance, args, result)
    if not ready or not instance then return end
    frame_counter = frame_counter + 1
    D_FRAME.calls = D_FRAME.calls + 1
    STAT.frame_calls = STAT.frame_calls + 1

    local interval = math.floor(tonumber(cfg.tick_interval) or 10)
    if interval < 1 then interval = 1 end

    -- 桶 0：进世界门控（§4.3）。还没进世界时逐帧查一次，进世界后只在桶 1 里查退出。
    if not in_world then
        local menu = read_game_menu()
        if menu ~= true then
            in_world = true
            import_cache = nil
            if cfg.self_check then
                local ok = pcall(run_self_check)
                if not ok then D_FRAME.errs = D_FRAME.errs + 1 end
            end
            -- 进世界首帧补播一次「导出/粘贴导入」的结果（setup/主菜单里不能 invoke）
            if cfg.self_check and import_pending_msg then
                local msg = import_pending_msg
                import_pending_msg = nil
                chat_print(msg)
            end
        end
    end

    -- 桶 1：设置比对 + netMode 缓存刷新 + 退出世界检测（再受 config_reload_sec 的秒节拍限制）
    if (frame_counter - 1) % interval == 0 then
        ensure_net_mode()       -- 第一帧就确证联机身份（只读一次，之后走缓存）
        if in_world and read_game_menu() == true then
            in_world = false    -- 退出世界：下次进来要重新播报自检
            import_cache = nil
        end
        local now = os.time()
        if type(now) == "number" and (now - last_reload_check) >= cfg.config_reload_sec then
            last_reload_check = now
            refresh_net_mode()
            -- ★ 无论 hot_reload 开不开，都要读一次 config.json：
            --   ① hot_reload=true  → 设置热生效（老行为）；
            --   ② import_string 通道（§9.3）必须独立生效，否则玩家关掉「自动重读设置」
            --      后粘贴进来的串永远不会被看到。
            local raw = mod.read_file("config.json")
            if type(raw) == "string" and raw ~= "" and raw ~= last_config_raw then
                if load_config_from(raw) then
                    last_config_raw = raw
                    if cfg.hot_reload then
                        recompute_all()
                        pending_sweep = true
                        log_info("属性工坊：设置已更新（" .. settings_summary() .. "）")
                    end
                end
            end
            local ok_imp = pcall(tick_import_string)
            if not ok_imp then D_FRAME.errs = D_FRAME.errs + 1 end
        end
    end

    -- 桶 2：没有挂上物品创建钩子时的兜底扫描计数（降级模式）
    if (frame_counter - 2) % interval == 0 and item_hooked == 0 then
        fallback_counter = fallback_counter + 1
        if fallback_counter >= 20 then
            fallback_counter = 0
            pending_sweep = true
        end
    end

    -- 桶 3：背包刷新（客机模式下我们本来就不写，直接消掉待办）
    if (frame_counter - 3) % interval == 0 and pending_sweep then
        if is_client() or not cfg.refresh_inventory then
            pending_sweep = false
        elseif is_local_player(instance) then
            pending_sweep = false
            local t0 = os.clock and os.clock() or 0
            local n = sweep_inventory(instance)
            if os.clock then D_SWEEP.t_total = D_SWEEP.t_total + (os.clock() - t0) end
            if n >= 0 then
                log_debug(string.format("属性工坊：背包刷新完成（扫描 %d 格）", n))
            end
        end
    end

    -- 桶 4：研究自动解锁（分帧，每次最多 RESEARCH_BATCH 个 ID）
    if (frame_counter - 4) % interval == 0 and cfg.research_unlock then
        research_step()
    end
end

-- ============================================================================
-- 19. 弹幕钩子：弹幕体型倍率（只处理玩家自己射出、且能对上武器分类的弹幕）
-- ============================================================================
local function get_projectile_at(idx)
    if not F_main_projectile then return nil end
    local ok, arr = pcall(patch.get_field_value, F_main_projectile, nil, "object")
    if not ok or not arr then return nil end
    local ok2, proj = pcall(patch.array_at, arr, idx)
    if not ok2 then return nil end
    return proj
end

local function on_new_projectile(instance, args, result)
    -- ★ 写入口第一件事：联机客机只读不写
    ensure_net_mode()
    if is_client() then return end
    if not ready or not proj_active then return end
    if type(result) ~= "number" or result < 0 then return end
    STAT.proj_calls = STAT.proj_calls + 1
    D_PROJ.calls = D_PROJ.calls + 1
    local t0 = os.clock and os.clock() or nil

    local proj = get_projectile_at(result)
    if not proj then return end

    local ptype = read_field(F_proj_type, proj, "int")
    if not ptype or ptype <= 0 then return end
    local cat = proj_cat[ptype]
    if not cat then return end

    local setting = PROJ_SCALE[cat]
    if not setting then return end
    local pct = cfg[setting] or 100
    local eff = pct * (cfg.global_percent or 100) / 100
    if eff == 100 then return end

    if F_proj_friendly and read_field(F_proj_friendly, proj, "bool") ~= true then return end

    local base = read_field(F_proj_scale, proj, "float")
    if not base or base <= 0 then return end

    local target = base * eff / 100
    if target < 0.05 then target = 0.05 end
    if target > 1000000 then target = 1000000 end   -- 只防极端溢出，不是功能上限
    target = f32(target)
    if same(target, base) then return end

    local ok = pcall(write_field, F_proj_scale, proj, target, "float")
    if ok then
        STAT.proj_hits = STAT.proj_hits + 1
        D_PROJ.hits = D_PROJ.hits + 1
    else
        STAT.proj_errs = STAT.proj_errs + 1
        D_PROJ.errs = D_PROJ.errs + 1
    end
    if t0 and os.clock then D_PROJ.t_total = D_PROJ.t_total + (os.clock() - t0) end
    if ok and cfg.write_log and cfg.debug_log and not reported.proj then
        reported.proj = true
        log_debug(string.format("属性工坊：弹幕体型已改写（类型 %d，%.2f → %.2f）", ptype, base, target))
    end
end

-- ============================================================================
-- 20. 汇总 / 重算 / 安装 / 生命周期
-- ============================================================================
-- 只影响模组自身行为的「总控」项：它们不会改动游戏数值，摘要里不算「改动过」
local CONTROL_ONLY = {
    write_log = true, debug_log = true, hot_reload = true, refresh_inventory = true,
    host_only = true, tick_interval = true, config_reload_sec = true,
    self_check = true, diag_report_cmd = true, diag_slow_ms = true,
    chat_cmd = true, import_string = true,
}

settings_summary = function()
    local changed = {}
    for key, default in pairs(DEFAULTS) do
        if not CONTROL_ONLY[key] and cfg[key] ~= default then changed[#changed + 1] = key end
    end
    if #changed == 0 then return "全部设置均为默认值（模组不改动任何数值）" end
    table.sort(changed)
    if #changed <= 6 then return table.concat(changed, ", ") end
    local head = {}
    for i = 1, 6 do head[i] = changed[i] end
    return string.format("%s 等 %d 项", table.concat(head, ", "), #changed)
end

-- 设置变化后重算所有已缓存物品的目标值（不重新采集原版基础值）
recompute_all = function()
    proj_active = false
    if cfg.enabled then
        if (cfg.global_percent or 100) ~= 100 then proj_active = true end
        for _, setting in pairs(PROJ_SCALE) do
            if (cfg[setting] or 100) ~= 100 then proj_active = true end
        end
    end
    local denied = 0
    for _, info in pairs(item_info) do
        if cfg.enabled and not id_allowed(info.itype) then denied = denied + 1 end
        compute_targets(info)
    end
    STAT.id_denied = denied
end

local function get_type(namespace, name)
    local ok, t = pcall(patch.get_type, namespace, name)
    if ok then return t end
    return nil
end

-- 嵌套类型：只用 get_inner_type（get_type 取不到嵌套类）
local function nested_type(outer_ns, outer_name, inner_name)
    if not patch.get_inner_type then return nil end
    local outer = get_type(outer_ns, outer_name)
    if not outer then return nil end
    local ok, t = pcall(patch.get_inner_type, outer, inner_name)
    if ok and t then return t end
    return nil
end

local function try_hook(method, spec, label)
    if not method then return false end
    local ok, hook = pcall(patch.install_hook, method, spec)
    if not ok then
        log_warn_once("hookfail_" .. label, "属性工坊：安装钩子失败(" .. label .. ")：" .. tostring(hook))
        return false
    end
    hooks[#hooks + 1] = hook
    return true
end

function setup()
    -- ★ 初始化这些「进世界边沿」状态：既保证重载后自检会再播一次，也避免上一次
    --   装载遗留的 in_world 让新一次 setup 完全静默（假内核里每个用例都会重新 setup）。
    in_world = false
    import_cache = nil
    import_pending_msg = nil
    import_active = nil
    rebuild_id_filters()
    read_config()
    recompute_all()

    local T_ITEM = get_type("Terraria", "Item")
    local T_PLAYER = get_type("Terraria", "Player")
    local T_MAIN = get_type("Terraria", "Main")
    local T_PROJ = get_type("Terraria", "Projectile")

    if not T_ITEM then
        log_symbol("no_item", "属性工坊：找不到 Terraria.Item，模组未启用", true)
        D_ITEM.enabled = false
        return
    end

    -- 核心字段：没有它就无法识别物品，直接停手（只打日志，不影响游戏）
    F_type = find_field(T_ITEM, "type")
    if not F_type then
        log_symbol("no_item_type", "属性工坊：找不到 Item.type，模组未启用", true)
        D_ITEM.enabled = false
        return
    end

    -- 其余字段：缺哪个就跳过哪个功能
    local missing = {}
    for i = 1, #FIELD_NAMES do
        local name = FIELD_NAMES[i]
        local fh = find_field(T_ITEM, name)
        FIELDS[name] = fh
        if not fh then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        log_symbol("fields_missing",
            "属性工坊：Item 字段未找到（对应功能自动跳过）：" .. table.concat(missing, ", "))
    end
    D_ITEM.fields = (#missing == 0) and "ok" or "partial"

    -- ★ 鞭子集合（嵌套类型）：ItemID.Sets.SummonerWeaponThatScalesWithAttackSpeed
    T_ITEMID_SETS = nested_type("Terraria.ID", "ItemID", "Sets")
    if not T_ITEMID_SETS then T_ITEMID_SETS = nested_type("Terraria", "ItemID", "Sets") end
    if T_ITEMID_SETS then
        F_WHIP_SET = find_field(T_ITEMID_SETS, "SummonerWeaponThatScalesWithAttackSpeed")
    end
    if F_WHIP_SET then
        D_WHIP.fields = "ok"
    else
        D_WHIP.fields = "partial"
        log_symbol("whip_set_missing",
            "属性工坊：ItemID.Sets.SummonerWeaponThatScalesWithAttackSpeed 取不到，"
            .. "鞭子改用内置鞭子弹幕编号表兜底（841/847/848/849/912-915/952/1028-1035/1104）")
    end
    if FIELDS.shoot then D_WHIP.methods = "ok" else D_WHIP.methods = "partial" end

    -- 玩家 / 世界侧（背包刷新与弹幕体型用；取不到只是这两项功能失效）
    if T_PLAYER then
        F_inventory = find_field(T_PLAYER, "inventory")
        F_who_am_i = find_field(T_PLAYER, "whoAmI")
    end
    if T_MAIN then
        -- ★ 1.4.5.8 手机版：Main.netMode 是 public static int 字段（可读）
        F_net_mode = find_field(T_MAIN, "netMode")
        if not F_net_mode then
            log_symbol("netmode_missing",
                "属性工坊：找不到 Main.netMode，「联机：仅房主生效」退化为不限制")
        end
        F_main_player = find_field(T_MAIN, "player")
        F_main_projectile = find_field(T_MAIN, "projectile")
        -- ★ 手机版 Main.myPlayer 是**属性**（没有字段）→ 字段取不到就走 get_myPlayer
        F_my_player = find_field(T_MAIN, "myPlayer")
        if not F_my_player then
            M_get_my_player = resolve_static_getter(T_MAIN, "myPlayer", "get_myPlayer")
            if not M_get_my_player then
                log_symbol("myplayer_missing",
                    "属性工坊：Main.myPlayer 字段与 get_myPlayer 都取不到，多玩家过滤退化为不过滤")
            end
        end
        -- ★ Main.gameMenu 也是属性（官方源码-字段.tsv：gameMenu bool public static [属性] readonly=是）
        M_get_game_menu = resolve_static_getter(T_MAIN, "gameMenu", "get_gameMenu")
        -- 聊天播报：5 参优先（手机版），其次 4 参（旧桌面端），3 参需要 Color 结构体 → 放弃
        M_new_text = safe_get_method(T_MAIN, "NewText", 5)
        new_text_args = 5
        if not M_new_text then
            M_new_text = safe_get_method(T_MAIN, "NewText", 4)
            new_text_args = 4
        end
        if not M_new_text then
            new_text_args = 0
            log_symbol("newtext_missing", "属性工坊：Main.NewText 取不到，聊天栏播报与诊断输出不可用")
        end
        M_get_tracker = safe_get_method(T_MAIN, "get_LocalPlayerCreativeTracker", 0)
    end
    if T_PROJ then
        F_proj_type = find_field(T_PROJ, "type")
        F_proj_friendly = find_field(T_PROJ, "friendly")
        F_proj_scale = find_field(T_PROJ, "scale")
    end

    -- 最高词缀（§4.3-6）：Item.Prefix(int) + Item.GetRollablePrefixes() + Item.prefix(byte)
    M_item_prefix = safe_get_method(T_ITEM, "Prefix", 1)
    M_get_rollable = safe_get_method(T_ITEM, "GetRollablePrefixes", 0)
    if M_item_prefix and M_get_rollable and FIELDS.prefix then
        diag_no_hook(D_PREFIX, true)
    else
        diag_no_hook(D_PREFIX, false)
        log_symbol("prefix_missing",
            "属性工坊：Item.Prefix(int) / GetRollablePrefixes() / Item.prefix 不齐，「最高词缀」不可用")
    end

    -- 研究解锁（§4.3-9）：Main.LocalPlayerCreativeTracker → .ItemSacrifices → RegisterItemSacrifice
    local T_TRACKER = get_type("Terraria.GameContent.Creative", "CreativeUnlocksTracker")
    local T_SAC = get_type("Terraria.GameContent.Creative", "ItemsSacrificedUnlocksTracker")
    if T_TRACKER then F_tracker_sacrifices = find_field(T_TRACKER, "ItemSacrifices") end
    if T_SAC then M_register_sacrifice = safe_get_method(T_SAC, "RegisterItemSacrifice", 3) end
    if M_get_tracker and F_tracker_sacrifices and M_register_sacrifice then
        diag_no_hook(D_RESEARCH, true)
    else
        diag_no_hook(D_RESEARCH, false)
        local miss = {}
        if not M_get_tracker then miss[#miss + 1] = "Main.get_LocalPlayerCreativeTracker" end
        if not F_tracker_sacrifices then miss[#miss + 1] = "CreativeUnlocksTracker.ItemSacrifices" end
        if not M_register_sacrifice then miss[#miss + 1] = "RegisterItemSacrifice(int,int,string)" end
        log_symbol("research_missing",
            "属性工坊：研究解锁符号不全（" .. table.concat(miss, ", ") .. "），该项不可用")
    end

    -- 物品创建：SetDefaults 按 3/2/1 参逐个尝试（★ 1.4.5.8 手机版只有
    -- SetDefaults(int, ItemVariant) 2 参这一个重载，另外两个取不到就返回 nil、无害），
    -- 外加 netDefaults(1)
    -- （进世界读档走 DeserializeFrom → netDefaults；重铸走 Prefix → Refresh → netDefaults）
    local arities = { 3, 2, 1 }
    for i = 1, #arities do
        local argc = arities[i]
        if try_hook(safe_get_method(T_ITEM, "SetDefaults", argc),
                { postfix = on_set_defaults }, "Item.SetDefaults/" .. argc) then
            item_hooked = item_hooked + 1
        end
    end
    if try_hook(safe_get_method(T_ITEM, "netDefaults", 1),
            { postfix = on_net_defaults }, "Item.netDefaults") then
        item_hooked = item_hooked + 1
    end
    D_ITEM.hooks = (item_hooked > 0) and "ok" or "fail"

    -- 逐帧：进世界门控 + 设置热重载 + 背包刷新
    local tick_ok = false
    if T_PLAYER then
        tick_ok = try_hook(safe_get_method(T_PLAYER, "ResetEffects", 0),
                    { postfix = on_reset_effects }, "Player.ResetEffects")
            or try_hook(safe_get_method(T_PLAYER, "ResetEffects"),
                    { postfix = on_reset_effects }, "Player.ResetEffects(*)")
    end
    D_FRAME.hooks = tick_ok and "ok" or "fail"

    -- 弹幕生成：弹幕体型倍率（没开这项设置时回调里第一步就返回）
    if T_PROJ then
        -- ★ 只认 13 参重载：1.4.5.8 手机版另一个重载是 11 参，前 3 个形参里带 Vector2
        --   **按值结构体**，本加载器的 hook 只支持标量参数（05 §4.3），挂它可能崩 ——
        --   所以这里**不做**「按个数/按名字回退」（回退会选到 11 参那个）。
        local m = safe_get_method(T_PROJ, "NewProjectile", 13)
        if try_hook(m, { postfix = on_new_projectile }, "Projectile.NewProjectile") then
            D_PROJ.hooks = "ok"
        end
    end

    -- 聊天命令（§9.2）：**默认关闭**。聊天指令关闭时这里一行都不执行 ——
    --   不 get_type、不 get_method、不装钩子，运行期统计里聊天钩子数必须为 0。
    if chat_cmd_on() then
        local t_say = get_type("Terraria.Chat.Commands", "SayChatCommand")
        if not t_say then t_say = get_type("Terraria.Chat", "SayChatCommand") end
        if t_say then
            M_chat_say = safe_get_method(t_say, "ProcessIncomingMessage", 2)
        end
        if M_chat_say and try_hook(M_chat_say, { prefix = on_say_chat },
                "SayChatCommand.ProcessIncomingMessage") then
            chat_hooked = chat_hooked + 1
            D_CHAT.fields, D_CHAT.methods = "ok", "ok"
            D_CHAT.hooks = "ok"
            log_info("属性工坊：聊天指令已启用（SayChatCommand.ProcessIncomingMessage）")
        else
            chat_hook_fail = "SayChatCommand.ProcessIncomingMessage(string,byte) 取不到或装不上"
            D_CHAT.fields, D_CHAT.methods = "fail", "fail"
            D_CHAT.hooks = "fail"
            D_CHAT.enabled = false
            log_symbol("chat_hook_fail",
                "属性工坊：聊天指令已打开但装不上（" .. chat_hook_fail .. "）；"
                .. "请改用设置项 import_string 粘贴导入、forge_export.txt 导出")
        end
    else
        D_CHAT.fields, D_CHAT.methods, D_CHAT.hooks = "n/a", "n/a", "n/a"
        D_CHAT.enabled = false
    end

    -- 纯字段 / 纯方法级的域：不需要钩子 → hooks 标 "n/a"（自检里显示 —，不误报停用）
    if FIELDS.useTime and FIELDS.useAnimation then diag_no_hook(D_SPEED, true)
    else diag_no_hook(D_SPEED, false) end
    if FIELDS.maxStack or FIELDS.value or FIELDS.rare then diag_no_hook(D_ECON, true)
    else diag_no_hook(D_ECON, false) end
    if FIELDS.consumable then diag_no_hook(D_CONS, true) else diag_no_hook(D_CONS, false) end
    diag_no_hook(D_ID, true)
    if F_inventory then
        D_SWEEP.fields = "ok" D_SWEEP.methods = "ok" D_SWEEP.hooks = "n/a"
    else
        D_SWEEP.fields = "fail" D_SWEEP.methods = "fail" D_SWEEP.hooks = "n/a" D_SWEEP.enabled = false
    end
    -- 逐帧/热重载域：句柄状态看 gameMenu / netMode 能不能取到
    if M_get_game_menu or F_net_mode then D_FRAME.fields = "ok" else D_FRAME.fields = "partial" end
    D_FRAME.methods = D_FRAME.fields

    last_reload_check = os.time() or 0
    ready = true

    if item_hooked == 0 then
        D_ITEM.hooks = "fail"
        log_symbol("no_item_hook",
            "属性工坊：物品创建钩子一个都没挂上，进入降级模式（定期扫背包，兜底生效）")
    end
    if not tick_ok then
        log_symbol("no_tick_hook",
            "属性工坊：Player.ResetEffects 未挂上；设置热重载与启动自检不可用，重进世界后生效")
    end
    log_info(string.format("属性工坊 v%s 已加载（物品钩子 %d 个，功能域 %d 个）；设置：%s",
        tostring(mod.meta.version), item_hooked, #DIAG, settings_summary()))
end

function cleanup()
    -- 1) 目标值全部改回原版，并尽量把本机玩家背包里已改写的物品还原
    cfg.enabled = false
    cfg.best_prefix = false
    for _, info in pairs(item_info) do
        compute_targets(info)
    end
    -- 客机模式下我们从未写过任何东西，不做还原写入
    if not is_client() then pcall(sweep_main_player) end

    -- 2) 摘掉所有钩子
    for i = #hooks, 1, -1 do
        local hook = hooks[i]
        hooks[i] = nil
        if hook then pcall(hook.remove, hook) end
    end

    ready = false
    pending_sweep = false
    frame_counter = 0
    fallback_counter = 0
    in_world = false
    import_cache = nil
    M_chat_say = nil
    chat_hooked = 0
    chat_hook_fail = nil
    import_active = nil
    import_seen_raw = nil
    import_pending_msg = nil
    research_obj = nil
    item_info = {}
    proj_cat = {}
    proj_active = false
    log_info("属性工坊：已卸载")
end

mod.cleanup = cleanup
todo_list = { "setup" }

-- ============================================================================
-- 21. 游戏内图形面板（LuaLoader 1.9.0 的 mod.gui / mod.on_gui）
-- ----------------------------------------------------------------------------
-- 只做面板，不改任何游戏逻辑；**面板只改运行时 cfg，绝不写 TEFManager 设置**，
-- 需要记住的东西写自己的状态文件 itemforge-gui.txt。
--
-- 纪律（19 章 §1.3 的 21 条 + 16 章 §3）：
--   · 每帧第一行 set_content_height（陷阱 27：写晚了+中间抛错 = 面板缩成一条）；
--   · 首帧不 set_pos（gui_layout.json 会覆盖），第 2 帧起再探测屏幕；
--   · 根上下文**不发任何流式控件**：滚动模式下长内容全在 begin_scroll 里，
--     分页模式（老加载器无 begin_scroll）只用绝对布局；
--   · 颜色永远是真表，文字一律 fit() 截断（游戏字体不能按像素裁，边缘不完整会整行隐藏）；
--   · ★ 宽度：窗口宽 = min(470*g, 屏宽*0.94)，所有行宽都从 body_w 推，
--     任何控件都不许越过 body_w（这是本模组返工率最高的一条）。
--   · 数值项一律纯数字输入（自带数字键盘，不依赖系统输入法；滑块输不进 0）。
--   · 物品库只做检索与名单编辑，**禁止任何生成类方法**（Item.NewItem 等）。
-- ============================================================================

-- ★ 整个面板装进一个函数：主 chunk 的 local 已接近 Lua 的 200 个上限，
--   面板自己的 90 多个 local 必须留在子作用域里（否则真机加载直接报错）。
local function itemforge_gui_install()
local GUI = {}                  -- 诊断/测试句柄（只读；面板本身只改 cfg）
ITEMFORGE_GUI = GUI

local GUI_STATE_FILE = "itemforge-gui.txt"
local GUI_PAGES = { "状态", "参数", "物品库", "一键", "关于" }
local GUI_LIB_PER = 18          -- 物品库每页 18 行
local GUI_BIG = 999999.0

-- 羊皮纸底 + 本模组强调色：铜橙（worldforge 朱红 / buffstack 紫罗兰 / 本模组铜橙）
local GC = {
    panel  = { 240, 228, 200, 246 },
    title  = { 236, 222, 194, 255 },
    button = { 214, 194, 158, 255 },
    hover  = { 234, 216, 176, 255 },
    active = { 176, 142, 92, 255 },
    border = { 74, 46, 20, 255 },
    text   = { 58, 38, 18, 255 },
    accent = { 176, 92, 36, 255 },
    gold   = { 156, 112, 44, 255 },
    muted  = { 108, 86, 58, 255 },
    ok     = { 74, 108, 46, 255 },
    warn   = { 168, 40, 32, 255 },
    white  = { 255, 255, 255, 255 },
    invis  = { 255, 255, 255, 0 },
    row_a  = { 228, 214, 184, 255 },
    row_b  = { 236, 224, 198, 255 },
    dim    = { 0, 0, 0, 150 },
}

-- 参数页的分组（6 组，键必须把所有 DEFAULTS 恰好覆盖一次；测试会核对）
local GUI_GROUPS = {
    { name = "通用总控", keys = {
        "enabled", "global_percent", "hot_reload", "config_reload_sec", "tick_interval",
        "host_only", "write_log", "refresh_inventory", "debug_log", "self_check",
        "diag_report_cmd", "diag_slow_ms", "chat_cmd", "import_string",
        "gui_enable", "gui_layout",
    } },
    { name = "无限与消耗", keys = {
        "tool_auto", "weapon_auto", "place_auto", "place_infinite",
        "inf_potion", "inf_bomb", "inf_summon", "inf_material", "inf_other",
    } },
    { name = "词缀与研究", keys = {
        "best_prefix", "research_unlock", "id_whitelist", "id_blacklist",
        "min_use_time", "maxstack_mult", "value_mult", "rare_mult",
    } },
    { name = "工具", keys = {
        "pick_speed", "pick_power", "pick_damage", "pick_range",
        "axe_speed", "axe_power", "axe_damage", "axe_range",
        "hammer_speed", "hammer_power", "hammer_damage", "hammer_range",
        "place_speed", "place_range",
    } },
    { name = "战斗职业", keys = {
        "melee_speed", "melee_damage", "melee_knockback", "melee_crit", "melee_scale", "melee_proj_scale",
        "ranged_speed", "ranged_damage", "ranged_knockback", "ranged_crit", "ranged_velocity", "ranged_proj_scale",
        "magic_speed", "magic_damage", "magic_knockback", "magic_crit", "magic_velocity", "magic_mana", "magic_proj_scale",
        "summon_speed", "summon_damage", "summon_knockback", "summon_scale", "summon_proj_scale",
        "fish_speed", "fish_power",
    } },
    { name = "其它", keys = { "other_speed", "other_damage" } },
}

-- 名称/单位（由 Info.json 的 title/unit 生成；测试断言覆盖所有 DEFAULTS 键）
local GUI_META = {
    enabled = { "总开关", "" },
    global_percent = { "全局倍率", "%" },
    hot_reload = { "自动重读设置", "" },
    config_reload_sec = { "自动重读设置间隔(秒)", "秒" },
    tick_interval = { "非关键项刷新间隔(帧)", "帧" },
    host_only = { "联机：仅房主生效", "" },
    write_log = { "写入日志文件(日志过大会崩游戏)", "" },
    refresh_inventory = { "改设置后立即刷新背包", "" },
    debug_log = { "详细日志", "" },
    self_check = { "启动自检播报", "" },
    diag_report_cmd = { "诊断报告命令", "" },
    diag_slow_ms = { "诊断：慢域阈值(毫秒)", "毫秒" },
    chat_cmd = { "聊天指令 (/forge …)", "" },
    import_string = { "粘贴导入设置串", "" },
    tool_auto = { "工具自动连用", "" },
    weapon_auto = { "武器自动连用", "" },
    place_auto = { "放置类自动连用", "" },
    place_infinite = { "放置类无限使用", "" },
    inf_potion = { "无限：药水/增益", "" },
    inf_bomb = { "无限：炸弹/投掷物", "" },
    inf_summon = { "无限：召唤物", "" },
    inf_material = { "无限：材料", "" },
    inf_other = { "无限：其它消耗品", "" },
    best_prefix = { "最高词缀（所有物品）", "" },
    research_unlock = { "研究自动解锁（旅程模式）", "" },
    id_whitelist = { "只改这些物品 ID", "" },
    id_blacklist = { "排除这些物品 ID", "" },
    min_use_time = { "使用时间下限(帧)", "帧" },
    maxstack_mult = { "堆叠上限倍率", "%" },
    value_mult = { "售价倍率", "%" },
    rare_mult = { "稀有度倍率", "%" },
    pick_speed = { "镐·使用速度", "%" },
    pick_power = { "镐·挖掘力", "%" },
    pick_damage = { "镐·伤害", "%" },
    pick_range = { "镐·范围", "%" },
    axe_speed = { "斧·使用速度", "%" },
    axe_power = { "斧·砍伐力", "%" },
    axe_damage = { "斧·伤害", "%" },
    axe_range = { "斧·范围", "%" },
    hammer_speed = { "锤·使用速度", "%" },
    hammer_power = { "锤·锤击力", "%" },
    hammer_damage = { "锤·伤害", "%" },
    hammer_range = { "锤·范围", "%" },
    place_speed = { "放置·使用速度", "%" },
    place_range = { "放置·范围", "%" },
    melee_speed = { "近战·使用速度", "%" },
    melee_damage = { "近战·伤害", "%" },
    melee_knockback = { "近战·击退", "%" },
    melee_crit = { "近战·暴击率", "%" },
    melee_scale = { "近战·大小", "%" },
    melee_proj_scale = { "近战·弹幕体型", "%" },
    ranged_speed = { "远程·使用速度", "%" },
    ranged_damage = { "远程·伤害", "%" },
    ranged_knockback = { "远程·击退", "%" },
    ranged_crit = { "远程·暴击率", "%" },
    ranged_velocity = { "远程·弹速", "%" },
    ranged_proj_scale = { "远程·弹幕体型", "%" },
    magic_speed = { "魔法·使用速度", "%" },
    magic_damage = { "魔法·伤害", "%" },
    magic_knockback = { "魔法·击退", "%" },
    magic_crit = { "魔法·暴击率", "%" },
    magic_velocity = { "魔法·弹速", "%" },
    magic_mana = { "魔法·魔力消耗", "%" },
    magic_proj_scale = { "魔法·弹幕体型", "%" },
    summon_speed = { "召唤·使用速度", "%" },
    summon_damage = { "召唤·伤害", "%" },
    summon_knockback = { "召唤·击退", "%" },
    summon_scale = { "召唤·大小", "%" },
    summon_proj_scale = { "召唤·仆从体型", "%" },
    fish_speed = { "钓竿·使用速度", "%" },
    fish_power = { "钓竿·钓鱼力", "%" },
    other_speed = { "其他·使用速度", "%" },
    other_damage = { "其他·伤害", "%" },
    gui_enable = { "图形面板", "" },
    gui_layout = { "面板布局", "" },
}

-- ============ 21.1 基础工具（内联 ui_kit 的最小集，单文件不 require） ============
local GP = { frames = 0, phase = 0, done = false, unclamped = false,
             x_max = 0, y_max = 0, screen_w = 0, screen_h = 0, g = 1.0,
             budget = 0, saved_x = 24, saved_y = 24, width = 0, pos_applied = false }
local GS = { tab = 1, fold = {}, lib_page = 1, pg = {}, filter = "",
             editing = nil, buffer = "", confirm_key = nil,
             last_msg = "", export_text = "", show_export = false }
local IMG, IMG_TRIED = {}, false
local GUI_INIT = false
local VX, VW = 0, 400       -- 本帧的内容原点与内容宽
local GUI_CW, GUI_PAD = 0, 12  -- 内容区宽（窗口宽 − 2×pad）与 pad（左右等距断言用）

GUI.last_err = ""

local function gui_get()
    local g = mod.gui
    if g ~= nil then return g end
    return nil
end
local function has(n)
    local g = gui_get()
    if g == nil then return false end
    local ok, fn = pcall(function() return g[n] end)
    return ok and type(fn) == "function"
end
local function api(n, ...)
    local g = gui_get()
    if g == nil then return false end
    local ok, fn = pcall(function() return g[n] end)
    if not ok or type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function num(v, d)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
    return v
end
local function rnd(v) return math.floor(num(v, 0) + 0.5) end
local function U(n) return rnd(n * (GP.g or 1)) end

local function u8len(b)
    if b == nil then return 1 end
    if b < 0x80 then return 1 end
    if b < 0xC2 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    if b < 0xF8 then return 4 end
    return 1
end
local function units(s)
    local n, i, len = 0, 1, #s
    while i <= len do
        local b = string.byte(s, i)
        local l = u8len(b)
        if i + l - 1 > len then l = len - i + 1 end
        if l < 1 then l = 1 end
        n = n + ((b < 0x80) and 1 or 2)
        i = i + l
    end
    return n
end
local function trunc(s, maxu)
    s = tostring(s or "")
    maxu = math.floor(num(maxu, 0))
    if maxu <= 0 then return "" end
    if units(s) <= maxu then return s end
    if maxu <= 2 then return s:sub(1, 0) .. ".." end
    local keep = maxu - 2
    local out, n, i, len = {}, 0, 1, #s
    while i <= len do
        local b = string.byte(s, i)
        local l = u8len(b)
        if i + l - 1 > len then l = len - i + 1 end
        if l < 1 then l = 1 end
        local u = (b < 0x80) and 1 or 2
        if n + u > keep then break end
        out[#out + 1] = s:sub(i, i + l - 1)
        n = n + u
        i = i + l
    end
    return table.concat(out) .. ".."
end
local function fit(s, bw, sc)
    if s == nil then return "" end
    local scale = num(sc, 0.46)
    if scale <= 0 then scale = 0.46 end
    local maxu = math.floor(num(bw, 200) / (13.0 * scale))
    if maxu < 3 then maxu = 3 end
    return trunc(s, maxu)
end
-- 按显示单位切行（导出串 / 日志长行用）
local function wrap_units(s, maxu)
    s = tostring(s or "")
    local out, cur, n, i, len = {}, {}, 0, 1, #s
    while i <= len do
        local b = string.byte(s, i)
        local l = u8len(b)
        if i + l - 1 > len then l = len - i + 1 end
        if l < 1 then l = 1 end
        local u = (b < 0x80) and 1 or 2
        if n + u > maxu then
            out[#out + 1] = table.concat(cur)
            cur, n = {}, 0
        end
        cur[#cur + 1] = s:sub(i, i + l - 1)
        n = n + u
        i = i + l
    end
    if #cur > 0 then out[#out + 1] = table.concat(cur) end
    if #out == 0 then out[1] = "" end
    return out
end

local function txt(x, y, s, col, sc, maxw)
    if not has("text_at") then return end
    api("text_at", num(x, 0), num(y, 0), fit(s, maxw or 200, sc), col or GC.text, sc or 0.46)
end
local function fillr(x, y, w, h, col)
    x, y, w, h = num(x, 0), num(y, 0), num(w, 0), num(h, 0)
    if w <= 0 or h <= 0 then return false end
    if IMG.white and has("image") then
        local ok = api("image", IMG.white, x, y, w, h, col or GC.row_a, nil)
        if ok then return true end
    end
    if has("rect") then return api("rect", x, y, w, h, col or GC.row_a) == true end
    return false
end
local function card(x, y, w, h, col)
    x, y, w, h = num(x, 0), num(y, 0), num(w, 0), num(h, 0)
    if w <= 0 or h <= 0 then return false end
    if IMG.panel and has("nine_slice") then
        local ok = api("nine_slice", IMG.panel, x, y, w, h, 16, col or GC.row_b, 0)
        if ok then return true end
    end
    return fillr(x, y, w, h, col or GC.row_b)
end
local function btn(x, y, w, h, label)
    x, y, w, h = num(x, 0), num(y, 0), num(w, 0), num(h, 0)
    if w <= 0 or h <= 0 then return false end
    local s = fit(label, w - 6, 0.46)
    if IMG.button and has("image_button") then
        local ok, hit = api("image_button", IMG.button, x, y, w, h, s, 12)
        if ok then return hit == true end
    end
    if has("button_at") then
        local ok, hit = api("button_at", x, y, w, h, s)
        return ok and hit == true
    end
    return false
end
local function scroll_begin(id, x, y, w, h, cw, ch)
    if not has("begin_scroll") then return 0, 0, w, h end
    if w <= 0 or h <= 0 then return 0, 0, w, h end
    local ok, a, b, c, d = api("begin_scroll", id, x, y, w, h, cw, ch)
    if not ok then return 0, 0, w, h end
    return num(a, 0), num(b, 0), num(c, w), num(d, h)
end
local function scroll_end()
    if has("end_scroll") then api("end_scroll") end
end

-- ============ 21.2 主题 / 图片 / 屏幕探测 ============
local function apply_theme()
    if not has("set_style") then return end
    api("set_style", { panel = GC.panel, title = GC.title, button = GC.button,
                       hover = GC.hover, active = GC.active, border = GC.border, text = GC.text })
end
local function load_images()
    if IMG_TRIED then return end
    IMG_TRIED = true
    if not has("load_image") then return end
    local order = { "white", "panel", "button", "glyph" }
    for i = 1, #order do
        local ok, id = api("load_image", "lib/ui/" .. order[i] .. ".png")
        if ok and type(id) == "string" then IMG[order[i]] = id end
    end
    if has("image") then
        for _, id in pairs(IMG) do api("image", id, 0, 0, 1, 1, GC.invis, nil) end
    end
end
local function apply_skin()
    if not has("set_skin") or not IMG.panel or not IMG.glyph then return end
    local size = rnd(40 * GP.g)
    if size < 24 then size = 24 elseif size > 128 then size = 128 end
    api("set_skin", IMG.panel, 16, IMG.glyph, size, rnd(10 * GP.g))
end

-- 零游戏符号测屏（16 章 §3.2）：请求超大坐标 → 下一帧读回夹取上界
local function probe_step()
    if GP.frames < 2 or GP.done then return end
    if GP.phase == 0 then
        local ok, x, y = api("get_pos")
        if ok and type(x) == "number" then GP.saved_x, GP.saved_y = x, num(y, GP.saved_y) end
        api("set_pos", GUI_BIG, 0)
        GP.phase = 1
    elseif GP.phase == 1 then
        local ok, x = api("get_pos")
        GP.x_max = (ok and type(x) == "number") and x or 0
        api("set_pos", 0, GUI_BIG)
        GP.phase = 2
    else
        local ok, _x, y = api("get_pos")
        GP.y_max = (ok and type(y) == "number") and y or 0
        if GP.x_max > 20000 or GP.y_max > 20000 or GP.x_max <= 0 or GP.y_max <= 0 then
            GP.unclamped = true
        else
            local g = math.min(GP.x_max, GP.y_max) / 688.0
            if g < 1.0 then g = 1.0 elseif g > 2.5 then g = 2.5 end
            GP.g = g
            GP.screen_w = GP.x_max + 32.0 * g
            GP.screen_h = GP.y_max + 32.0 * g
            GP.budget = GP.y_max - 24.0 * g
            if GP.budget < 340 then GP.budget = 340 end
        end
        GP.phase = 3
        GP.done = true
        GP.pos_applied = false
        GP.width = 0
    end
end

local function win_w()
    local w = rnd(470 * (GP.g or 1))
    local sw = (GP.done and not GP.unclamped) and GP.screen_w or 0
    if sw > 0 and w > sw * 0.94 then w = math.floor(sw * 0.94) end
    local minw = 340
    if sw > 0 and sw * 0.94 < minw then minw = math.floor(sw * 0.94) end
    if w < minw then w = minw end
    if sw > 0 and w > sw then w = math.floor(sw) end
    if w < 120 then w = 120 end
    return w
end
local function avail_h()
    if GP.done and not GP.unclamped and GP.budget > 120 then return GP.budget end
    return 380.0
end

-- ============ 21.3 状态落盘 ============
local function gui_state_write()
    if GP.done and not GP.unclamped and has("get_pos") then
        local ok, x, y = api("get_pos")
        if ok and type(x) == "number" and type(y) == "number" then
            GP.saved_x, GP.saved_y = x, y
        end
    end
    local lines = {
        "tab=" .. tostring(GS.tab),
        "libpage=" .. tostring(GS.lib_page),
        "filter=" .. tostring(GS.filter or ""),
        "x=" .. tostring(math.floor(num(GP.saved_x, 24))),
        "y=" .. tostring(math.floor(num(GP.saved_y, 24))),
    }
    for i = 1, #GUI_GROUPS do
        lines[#lines + 1] = "fold" .. i .. "=" .. (GS.fold[i] and "true" or "false")
    end
    local ok = mod.write_file(GUI_STATE_FILE, table.concat(lines, "\n"))
    return ok ~= false
end

local function gui_state_read()
    local raw = mod.read_file(GUI_STATE_FILE)
    if type(raw) ~= "string" or raw == "" then return false end
    for line in raw:gmatch("[^\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then
            if k == "tab" then
                GS.tab = math.max(1, math.min(#GUI_PAGES, math.floor(num(v, 1))))
            elseif k == "libpage" then
                GS.lib_page = math.max(1, math.floor(num(v, 1)))
            elseif k == "filter" then
                GS.filter = v
            elseif k == "x" then
                GP.saved_x = num(v, GP.saved_x)
            elseif k == "y" then
                GP.saved_y = num(v, GP.saved_y)
            elseif k:match("^fold%d+$") then
                local i = tonumber(k:sub(5))
                if i and i >= 1 and i <= #GUI_GROUPS then GS.fold[i] = (v == "true") end
            end
        end
    end
    return true
end

-- ============ 21.4 动作 ============
local function gui_apply_change(key)
    if key == "id_whitelist" or key == "id_blacklist" then rebuild_id_filters() end
    pending_sweep = true
    if recompute_all then pcall(recompute_all) end
    if key == "gui_layout" then
        GS.layout = (cfg.gui_layout == "分页") and "分页" or "滚动"
    end
end

local function list_set_of(key)
    if key == "id_whitelist" then return id_whitelist_set end
    return id_blacklist_set
end
local function list_join(set)
    local ids = {}
    for id in pairs(set or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end
local function list_state(id)
    if id_blacklist_set and id_blacklist_set[id] then return "bl" end
    if id_whitelist_set and id_whitelist_set[id] then return "wl" end
    return ""
end
local function list_toggle(which, id)
    local key = (which == "wl") and "id_whitelist" or "id_blacklist"
    local set = parse_id_list(cfg[key]) or {}
    if set[id] then set[id] = nil else set[id] = true end
    cfg[key] = list_join(set)
    rebuild_id_filters()
    GS.last_msg = string.format("%s %s：%d", (which == "wl") and "白名单" or "黑名单",
        set[id] and "加入" or "移出", id)
    gui_apply_change(key)
    gui_state_write()
end

local function commit_edit()
    local e = GS.editing
    if not e then return end
    local name = (GUI_META[e.key] and GUI_META[e.key][1]) or e.key
    if e.key == "__filter__" then
        GS.filter = tostring(GS.buffer or "")
        GS.lib_page = 1
        GS.last_msg = (GS.filter == "") and "已清空过滤" or ("过滤：" .. GS.filter)
        GS.editing, GS.buffer = nil, ""
        gui_state_write()
        return
    end
    if e.kind == "num" then
        local n = tonumber(GS.buffer)
        if n then
            cfg[e.key] = math.floor(n)
            GS.last_msg = string.format("已改 %s = %d（只改本次游戏）", name, cfg[e.key])
            gui_apply_change(e.key)
        else
            GS.last_msg = "输入不是数字，未改动"
        end
    else
        cfg[e.key] = tostring(GS.buffer or "")
        GS.last_msg = string.format("已改 %s（只改本次游戏）", name)
        gui_apply_change(e.key)
    end
    GS.editing, GS.buffer = nil, ""
    gui_state_write()
end

local function do_action(act, arg)
    if act == "toggle_enabled" then
        cfg.enabled = not cfg.enabled
        GS.last_msg = cfg.enabled and "总开关已打开" or "总开关已关闭（完全停手）"
        gui_apply_change("enabled")
    elseif act == "reload" then
        local ok = read_config()
        gui_apply_change("enabled")
        GS.last_msg = ok and "已重读 config.json 并重算" or "重读失败：config.json 读不到本模组的键"
    elseif act == "reapply" then
        if GS.confirm_key ~= "reapply" then
            GS.confirm_key = "reapply"
            GS.last_msg = "危险动作：再点一次才真正重新应用词缀"
        else
            GS.confirm_key = nil
            local ok, n = pcall(sweep_main_player)
            GS.last_msg = ok and string.format("已重新应用（背包扫描返回值 %s）", tostring(n))
                or ("应用失败：" .. tostring(n))
        end
    elseif act == "selfcheck" then
        local ok, err = pcall(run_self_check)
        GS.last_msg = ok and "自检已播报到聊天栏" or ("自检失败：" .. tostring(err))
    elseif act == "export" then
        if GS.show_export then
            GS.show_export = false
            GS.last_msg = "已收起设置串"
        else
            GS.export_text = build_export_string(true)
            GS.show_export = true
            GS.last_msg = "已生成设置串（只显示，不写文件、不写设置）"
        end
    elseif act == "clearlog" then
        for i = #LOG_RING, 1, -1 do LOG_RING[i] = nil end
        GS.last_msg = "面板日志缓冲已清空"
    elseif act == "filter" then
        GS.editing = { kind = "str", key = "__filter__", title = "物品库过滤（ID 或名称片段）" }
        GS.buffer = tostring(GS.filter or "")
    elseif act == "filter_clear" then
        GS.filter = ""
        GS.lib_page = 1
        GS.last_msg = "已清空过滤"
        gui_state_write()
    elseif act == "lib_prev" then
        GS.lib_page = math.max(1, GS.lib_page - 1)
        gui_state_write()
    elseif act == "lib_next" then
        GS.lib_page = GS.lib_page + 1
        gui_state_write()
    elseif act == "fold" then
        local i = tonumber(arg) or 0
        if i >= 1 and i <= #GUI_GROUPS then
            GS.fold[i] = not GS.fold[i]
            gui_state_write()
        end
    elseif act == "pg_prev" then
        GS.pg[GS.tab] = math.max(1, (GS.pg[GS.tab] or 1) - 1)
    elseif act == "pg_next" then
        GS.pg[GS.tab] = (GS.pg[GS.tab] or 1) + 1
    elseif act == "toggle_wl" then
        list_toggle("wl", arg)
    elseif act == "toggle_bl" then
        list_toggle("bl", arg)
    end
end

-- ============ 21.5 物品库（只读检索 + 名单编辑，禁止生成类方法） ============
local LIB = { ids = {}, names = {}, scanned = 0, done = false, tried = false, fail = nil }
local M_LANG_NAME = nil

local function lib_name_now(id)
    if not M_LANG_NAME then return nil end
    local ok, v = pcall(invoke_static, M_LANG_NAME, id)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

local function lib_scan_step()
    if LIB.done then return end
    if not LIB.tried then
        LIB.tried = true
        local t = get_type("Terraria", "Lang") or get_type("Terraria.Localization", "Lang")
        if t then M_LANG_NAME = safe_get_method(t, "GetItemNameValue", 1) end
        if not M_LANG_NAME then
            LIB.fail = "取不到 Lang.GetItemNameValue：只按 ID 列表显示（不生成任何物品）"
            for i = 1, ITEM_CEILING do LIB.ids[i] = i end
            LIB.done = true
            LIB.scanned = ITEM_CEILING
            return
        end
    end
    local budget = 150
    while budget > 0 do
        local id = LIB.scanned + 1
        if id > ITEM_CEILING then LIB.done = true break end
        LIB.scanned = id
        local name = lib_name_now(id)
        if name then
            LIB.ids[#LIB.ids + 1] = id
            LIB.names[id] = name
        end
        budget = budget - 1
    end
end

local function lib_filtered()
    local f = tostring(GS.filter or "")
    if f == "" then return LIB.ids end
    local out = {}
    for i = 1, #LIB.ids do
        local id = LIB.ids[i]
        local name = LIB.names[id] or ""
        if tostring(id):find(f, 1, true) or name:find(f, 1, true) then out[#out + 1] = id end
    end
    return out
end

local function pager(n, page, per)
    per = math.max(1, math.floor(num(per, GUI_LIB_PER)))
    n = math.max(0, math.floor(num(n, 0)))
    local pages = math.max(1, math.ceil(n / per))
    page = math.floor(num(page, 1))
    if page < 1 then page = 1 elseif page > pages then page = pages end
    local first = (page - 1) * per + 1
    local last = math.min(n, first + per - 1)
    if first > n then first = n + 1 end
    return pages, page, first, last
end

-- ============ 21.6 各页的行 ============
local layout_effective          -- 前向声明（build_status 在 21.8 之前定义）
local GUI_PKG = "ailab.lua.itemforge"
local function domains_active()
    local inf = cfg.place_infinite or cfg.inf_potion or cfg.inf_bomb or cfg.inf_summon
        or cfg.inf_material or cfg.inf_other
    local pref = cfg.best_prefix or cfg.research_unlock
    local combat = false
    local ck = { "melee_speed", "melee_damage", "melee_knockback", "melee_crit", "melee_scale",
        "ranged_speed", "ranged_damage", "ranged_knockback", "ranged_crit", "ranged_velocity",
        "magic_speed", "magic_damage", "magic_knockback", "magic_crit", "magic_velocity",
        "summon_speed", "summon_damage", "summon_knockback", "summon_scale", "fish_speed", "fish_power" }
    for i = 1, #ck do
        if (cfg[ck[i]] or 100) ~= 100 then combat = true break end
    end
    local tools = false
    local tk = { "pick_speed", "pick_power", "pick_damage", "pick_range",
        "axe_speed", "axe_power", "axe_damage", "axe_range",
        "hammer_speed", "hammer_power", "hammer_damage", "hammer_range",
        "place_speed", "place_range" }
    for i = 1, #tk do
        if (cfg[tk[i]] or 100) ~= 100 then tools = true break end
    end
    return inf, pref, combat, tools
end

local function build_status(rows)
    rows[#rows + 1] = { kind = "head", text = "运行状态" }
    rows[#rows + 1] = { kind = "kv", k = "总开关", v = cfg.enabled and "开（功能生效）" or "关（完全停手）",
                        col = cfg.enabled and "ok" or "warn" }
    rows[#rows + 1] = { kind = "action", label = cfg.enabled and "关闭总开关" or "打开总开关", act = "toggle_enabled" }
    local inf, pref, combat, tools = domains_active()
    rows[#rows + 1] = { kind = "kv", k = "生效域 · 无限/消耗", v = inf and "开" or "关", col = inf and "ok" or "muted" }
    rows[#rows + 1] = { kind = "kv", k = "生效域 · 词缀/研究", v = pref and "开" or "关", col = pref and "ok" or "muted" }
    rows[#rows + 1] = { kind = "kv", k = "生效域 · 职业属性", v = combat and "开" or "关", col = combat and "ok" or "muted" }
    rows[#rows + 1] = { kind = "kv", k = "生效域 · 工具", v = tools and "开" or "关", col = tools and "ok" or "muted" }
    rows[#rows + 1] = { kind = "kv", k = "本帧命中",
        v = string.format("每帧钩子 %d 次 / 物品写入 %d 项", STAT.frame_calls, STAT.item_writes) }
    rows[#rows + 1] = { kind = "kv", k = "上次错误", v = (GUI.last_err ~= "" and GUI.last_err or "无"),
                        col = (GUI.last_err ~= "") and "warn" or "muted" }
    rows[#rows + 1] = { kind = "kv", k = "自动重读设置",
        v = cfg.hot_reload and string.format("开（每 %d 秒）", cfg.config_reload_sec) or "关" }
    rows[#rows + 1] = { kind = "kv", k = "设置版本", v = string.format("%d 项 · 校验 %04x", GUI.keys_n, GUI.keys_hash) }
    rows[#rows + 1] = { kind = "kv", k = "布局 / API", v = string.format("%s · %d/40 项", layout_effective(), GUI.api_have) }
    rows[#rows + 1] = { kind = "action", label = "刷新（重读设置并重算）", act = "reload" }
    if GS.last_msg ~= "" then
        rows[#rows + 1] = { kind = "text", text = "最近操作：" .. GS.last_msg, col = "gold" }
    end
end

local function build_params(rows)
    for gi = 1, #GUI_GROUPS do
        local grp = GUI_GROUPS[gi]
        rows[#rows + 1] = { kind = "group", text = grp.name .. (GS.fold[gi] and "（点标题收起）" or "（点标题展开）"),
                            act = "fold", arg = gi, right = string.format("%d 项", #grp.keys) }
        if GS.fold[gi] then
            for i = 1, #grp.keys do rows[#rows + 1] = { kind = "field", key = grp.keys[i] } end
        end
    end
end

local function build_library(rows)
    lib_scan_step()
    rows[#rows + 1] = { kind = "action",
        label = "过滤：" .. ((GS.filter == "" and "无（全部）") or GS.filter) .. "（点这里改）", act = "filter" }
    rows[#rows + 1] = { kind = "action", label = "清空过滤", act = "filter_clear" }
    if LIB.fail then rows[#rows + 1] = { kind = "text", text = LIB.fail, col = "warn" } end
    local ids = lib_filtered()
    local pages, page, first, last = pager(#ids, GS.lib_page, GUI_LIB_PER)
    GS.lib_page = page
    if #ids == 0 then
        rows[#rows + 1] = { kind = "text", text = "（没有匹配的物品）", col = "muted" }
    end
    for i = first, last do
        local id = ids[i]
        if id then
            rows[#rows + 1] = { kind = "item", id = id, name = LIB.names[id] or "?", idx = (i - first) + 1 }
        end
    end
    rows[#rows + 1] = { kind = "pager", text = string.format("第 %d/%d 页 · 共 %d 项 · 每页 %d",
        page, pages, #ids, GUI_LIB_PER) }
end

local function build_actions(rows)
    rows[#rows + 1] = { kind = "head", text = "一键操作（只改本次运行，不写设置）" }
    rows[#rows + 1] = { kind = "action", label = "重读设置（config.json）", act = "reload" }
    rows[#rows + 1] = { kind = "action",
        label = (GS.confirm_key == "reapply") and "再点一次：确认重新应用词缀" or "重新应用词缀（背包）",
        act = "reapply" }
    rows[#rows + 1] = { kind = "action", label = "启动自检（播报到聊天栏）", act = "selfcheck" }
    rows[#rows + 1] = { kind = "action",
        label = GS.show_export and "收起设置串" or "导出设置串（只显示，不落盘）", act = "export" }
    rows[#rows + 1] = { kind = "action", label = "清除面板日志", act = "clearlog" }
    if GS.last_msg ~= "" then
        rows[#rows + 1] = { kind = "text", text = "最近操作：" .. GS.last_msg, col = "gold" }
    end
    if GS.show_export then
        local lines = wrap_units(GS.export_text or "", 46)
        local cap = math.min(#lines, 20)
        for i = 1, cap do
            rows[#rows + 1] = { kind = "text", text = lines[i], col = "text", sc = 0.42 }
        end
        if #lines > cap then
            rows[#rows + 1] = { kind = "text", text = string.format("…… 其余 %d 行未显示", #lines - cap), col = "muted" }
        end
    end
end

local function build_about(rows)
    rows[#rows + 1] = { kind = "head", text = "关于" }
    rows[#rows + 1] = { kind = "kv", k = "版本", v = "v" .. tostring(mod.meta.version) }
    rows[#rows + 1] = { kind = "kv", k = "pkgId", v = tostring(GUI_PKG) }
    rows[#rows + 1] = { kind = "kv", k = "加载器 API", v = string.format("%d/40 项可用", GUI.api_have) }
    rows[#rows + 1] = { kind = "kv", k = "缺项", v = (GUI.api_missing ~= "" and GUI.api_missing or "无") }
    rows[#rows + 1] = { kind = "kv", k = "屏幕探测",
        v = GP.done and (GP.unclamped and "不可用（保守排版）" or string.format("g=%.2f 屏宽 %.0f", GP.g, GP.screen_w))
            or "未完成" }
    rows[#rows + 1] = { kind = "head", text = "最近日志（最多 30 行）" }
    local n = 0
    local start = math.max(1, #LOG_RING - 29)
    for i = start, #LOG_RING do
        n = n + 1
        rows[#rows + 1] = { kind = "text", text = LOG_RING[i], col = "muted", sc = 0.42 }
    end
    if n == 0 then rows[#rows + 1] = { kind = "text", text = "（日志缓冲为空）", col = "muted" } end
end

local function build_rows()
    local rows = {}
    if GS.tab == 1 then build_status(rows)
    elseif GS.tab == 2 then build_params(rows)
    elseif GS.tab == 3 then build_library(rows)
    elseif GS.tab == 4 then build_actions(rows)
    else build_about(rows) end
    return rows
end

-- ============ 21.7 行渲染 ============
-- 行卡片：有 panel.png 时用九宫格（圆角 + 描边），没图退回纯色。
-- ★ 左右各缩进 2px、上下各缩 1px：圆角/描边不会顶到窗口边框（宽度返工的老坑）。
local function row_base(x, y, w, h, col)
    if IMG.panel and has("nine_slice") then
        -- 行高只有 34 基础单位：九宫格边框必须用 8（用 16 会把中间挤没、圆角互相压）
        local ok = api("nine_slice", IMG.panel, x + 2, y + 1, w - 4, h - 2, 8, col or GC.row_b, 0)
        if ok then return true end
    end
    return fillr(x, y, w, h, col or GC.row_b)
end

local function draw_field(r, x, y, w, h)
    local key = r.key
    local meta = GUI_META[key]
    local name = meta and meta[1] or key
    local unit = (meta and meta[2]) or ""
    local val = cfg[key]
    local ctype = "int"
    if type(val) == "boolean" then ctype = "bool"
    elseif type(val) == "string" then ctype = (CHOICES[key] and "choice") or "str" end
    local valw = math.min(U(104), math.floor(w * 0.36))
    local labw = w - valw - U(12)
    txt(x + U(8), y + U(8), name, GC.text, 0.5, labw)
    local vx = x + w - valw - U(5)
    local vt, vc
    if ctype == "bool" then
        vt, vc = val and "开" or "关", val and GC.ok or GC.muted
    else
        vt = tostring(val)
        if ctype == "str" then
            vt = (vt == "" and "（空）") or vt
            vt = fit(vt, valw - U(8), 0.44)
        elseif ctype == "int" then
            vt = vt .. unit
        end
        vc = GC.text
    end
    local hit = btn(vx, y + U(3), valw, h - U(6), vt)
    if not hit then return end
    if ctype == "bool" then
        if key == "gui_enable" and val == true then
            if GS.confirm_key ~= "gui_enable" then
                GS.confirm_key = "gui_enable"
                GS.last_msg = "再点一次确认关闭面板（之后只能在 TEFManager 设置里开回来）"
                return
            end
            GS.confirm_key = nil
            cfg.gui_enable = false
            GS.last_msg = "面板已关闭：在 TEFManager 设置里把「图形面板」打开即可恢复"
            gui_state_write()
            return
        end
        cfg[key] = not val
        GS.last_msg = string.format("已改 %s = %s（只改本次游戏）", name, cfg[key] and "开" or "关")
        gui_apply_change(key)
        gui_state_write()
    elseif ctype == "choice" then
        local opts = CHOICES[key] or {}
        if #opts == 0 then return end
        local idx = 0
        for i = 1, #opts do if opts[i] == tostring(val) then idx = i break end end
        cfg[key] = opts[(idx % #opts) + 1]
        GS.last_msg = string.format("已改 %s = %s（只改本次游戏）", name, tostring(cfg[key]))
        gui_apply_change(key)
        gui_state_write()
    elseif ctype == "int" then
        GS.editing = { kind = "num", key = key, title = name .. (unit ~= "" and ("（" .. unit .. "）") or "") }
        GS.buffer = tostring(val)
        GS.confirm_key = nil
    else
        GS.editing = { kind = "str", key = key, title = name }
        GS.buffer = tostring(val)
        GS.confirm_key = nil
    end
end

local function draw_item_row(r, x, y, w, h)
    row_base(x, y, w, h, ((r.idx or 1) % 2 == 0) and GC.row_a or GC.row_b)
    local bw2 = U(34)
    local right = bw2 * 2 + U(48)
    local idw = U(54)
    local namew = w - idw - right - U(6)
    if namew < U(40) then namew = U(40) end
    txt(x + U(6), y + U(8), "#" .. tostring(r.id), GC.muted, 0.46, idw)
    txt(x + idw, y + U(8), r.name or "?", GC.text, 0.5, namew)
    local state = list_state(r.id)
    local st = (state == "bl" and "黑") or ((state == "wl" and "白") or "-")
    local b1 = x + w - U(5) - bw2 * 2 - U(4)
    txt(b1 - U(15), y + U(9), st, (state == "bl") and GC.warn or GC.accent, 0.46, U(14))
    if btn(b1, y + U(3), bw2, h - U(6), "白") then do_action("toggle_wl", r.id) end
    if btn(b1 + bw2 + U(4), y + U(3), bw2, h - U(6), "黑") then do_action("toggle_bl", r.id) end
end

local function draw_row(r, x, y, w, h)
    local mid = y + U(9)
    if r.kind == "head" then
        row_base(x, y, w, h, GC.row_a)
        fillr(x + U(8), y + U(7), U(3), h - U(14), GC.accent)
        txt(x + U(16), mid, r.text, GC.accent, 0.54, w - U(24))
    elseif r.kind == "group" then
        row_base(x, y, w, h, GC.row_a)
        if btn(x + U(4), y + U(2), w - U(8), h - U(4), r.text) then do_action("fold", r.arg) end
        if r.right then txt(x + w - U(56), mid, r.right, GC.muted, 0.42, U(50)) end
    elseif r.kind == "kv" then
        row_base(x, y, w, h, GC.row_b)
        local kw = math.floor(w * 0.40)
        txt(x + U(8), mid, r.k, GC.muted, 0.48, kw - U(10))
        txt(x + kw, mid, r.v, GC[r.col or "text"] or GC.text, 0.48, w - kw - U(8))
    elseif r.kind == "text" then
        txt(x + U(6), mid, r.text, GC[r.col or "text"] or GC.text, r.sc or 0.44, w - U(12))
    elseif r.kind == "field" then
        row_base(x, y, w, h, GC.row_b)
        draw_field(r, x, y, w, h)
    elseif r.kind == "item" then
        draw_item_row(r, x, y, w, h)
    elseif r.kind == "action" then
        local bw2 = math.min(w - U(12), U(260))
        if btn(x + U(6), y + U(3), bw2, h - U(6), r.label) then do_action(r.act, r.arg) end
    elseif r.kind == "pager" then
        if btn(x + U(6), y + U(3), U(62), h - U(6), "上一页") then do_action("lib_prev") end
        if btn(x + w - U(68), y + U(3), U(62), h - U(6), "下一页") then do_action("lib_next") end
        txt(x + U(74), mid, r.text, GC.muted, 0.44, w - U(150))
    end
end

-- ============ 21.8 容器层：滚动（1.9.0）/ 分页（老加载器） ============
function layout_effective()
    if not has("begin_scroll") or not has("end_scroll") then return "分页" end
    if (cfg.gui_layout or "滚动") == "分页" then return "分页" end
    return "滚动"
end

local function row_h() return U(34) end

local function draw_page_scroll(body0, vh)
    local bx, bw = VX, VW
    local rh = row_h()
    local rows = build_rows()
    local ch = math.max(rh * #rows + U(4), vh)
    local _sx, sy, _vw, sh = scroll_begin("if_page" .. tostring(GS.tab), bx, body0, bw, vh, bw, ch)
    for i = 1, #rows do
        local y = (i - 1) * rh
        if y + rh > sy and y < sy + sh then
            draw_row(rows[i], 0, y, bw, rh)
        end
    end
    scroll_end()
end

local function draw_page_paged(body0, vh)
    local bx, bw = VX, VW
    local rh = row_h()
    local foot = U(32)
    local list_h = vh - foot
    if list_h < rh then list_h = rh end
    local per = math.max(1, math.floor(list_h / rh))
    local rows = build_rows()
    local pages, page, first, last = pager(#rows, GS.pg[GS.tab] or 1, per)
    GS.pg[GS.tab] = page
    for i = first, last do
        draw_row(rows[i], bx, body0 + (i - first) * rh, bw, rh)
    end
    local fy = body0 + list_h
    if btn(bx, fy, U(58), foot - U(4), "上一页") then do_action("pg_prev") end
    if btn(bx + bw - U(58), fy, U(58), foot - U(4), "下一页") then do_action("pg_next") end
    txt(bx + U(62), fy + U(8), string.format("第 %d/%d 页", page, pages), GC.muted, 0.44, bw - U(126))
end

-- ============ 21.9 数字键盘编辑页（整页替换；v2.1.2 仿玩家工坊） ============
-- v2.1.1 及更早：半透明黑遮罩 + 小卡片键盘，小屏上压住参数行、点不准、值看不清。
-- 现在：进入编辑后本帧不再画页面内容，编辑页铺满内容区（无遮罩、无叠层）；
--       3 列 x 4 行键盘 1~9 / +/- / 0 / 退格，高度按可用空间自适应；
--       值直接画在框里（带闪烁光标）；底部 清空 / 默认 / 确定 / 取消。
local function edit_restore_default()
    local e = GS.editing
    if not e or e.key == "__filter__" then return end
    local name = (GUI_META[e.key] and GUI_META[e.key][1]) or e.key
    cfg[e.key] = DEFAULTS[e.key]
    gui_apply_change(e.key)
    GS.last_msg = string.format("已恢复 %s 的默认值（只改本次游戏）", name)
    GS.editing, GS.buffer = nil, ""
    gui_state_write()
end

local function draw_edit_overlay(bx, bw, body0, vh)
    local e = GS.editing
    if not e then return end
    local str_mode = (e.kind == "str")
    local x, w = bx, bw
    if str_mode then x, w = 0, bx * 2 + bw end
    local top = body0 + U(4)
    local bottom = body0 + vh - U(4)
    -- 不透明整页底：本帧页面行根本没画，这里再铺一层，保证「刚点开的那一帧」也不透
    fillr(0, body0, bx * 2 + bw, vh, GC.row_b)
    if not card(x, top, w, bottom - top, GC.panel) then
        fillr(x, top, w, bottom - top, GC.panel)
    end
    local px = x + U(10)
    local iw = w - U(20)
    local cur = (e.key == "__filter__") and (GS.filter or "") or cfg[e.key]
    local curtxt = (cur == nil) and "（空）" or tostring(cur)
    if curtxt == "" then curtxt = "（空）" end
    txt(px, top + U(7), e.title, GC.accent, 0.54, math.floor(iw * 0.60))
    txt(px + math.floor(iw * 0.44), top + U(9), "当前 " .. curtxt, GC.muted, 0.40,
        math.floor(iw * 0.56) - U(4))
    local gap = U(6)
    local act_h = U(30)
    local box_y = top + U(28)
    local box_h = U(38)
    local hint_y = box_y + box_h + U(3)
    local hint
    if str_mode then
        hint = "点下面的输入框，用系统键盘修改"
    elseif LIMITS[e.key] then
        hint = string.format("范围 %d ~ %d（只提示，确定时不夹取）", LIMITS[e.key][1], LIMITS[e.key][2])
    else
        hint = "输入后点「确定」生效（只改本次游戏）"
    end
    txt(px, hint_y, hint, GC.muted, 0.36, iw)

    local function actions(y, labels)
        local n = #labels
        local aw = math.floor((iw - gap * (n - 1)) / n)
        for i = 1, n do
            if btn(px + (i - 1) * (aw + gap), y, aw, act_h, labels[i]) then return labels[i] end
        end
        return nil
    end

    if str_mode then
        local iy = hint_y + U(16)
        local ih = bottom - U(4) - act_h - U(8) - iy
        if ih < U(60) then ih = U(60) end
        scroll_begin("if_edit_str", px, iy, iw, ih, iw, ih)
        if has("input_text") then
            local ok, v = api("input_text", "if_" .. tostring(e.key), GS.buffer or "")
            if ok and type(v) == "string" then GS.buffer = v end
        else
            txt(0, 0, "本机没有输入框 API：可用「清空」，或到 TEFManager 设置里改",
                GC.warn, 0.42, iw - U(8))
        end
        scroll_end()
        local hit = actions(bottom - U(4) - act_h, { "清空", "确定", "取消" })
        if hit == "清空" then GS.buffer = ""
        elseif hit == "确定" then commit_edit()
        elseif hit == "取消" then GS.editing, GS.buffer = nil, "" end
        return
    end

    -- 数字键盘：3 列 x 4 行。★ v2.1.3：从动作行上方往上排（不是从上往下堆），
    -- 面板再矮也不会让第 4 行压到 清空/默认/确定/取消。
    local act_y = bottom - U(4) - act_h
    local key_bottom = act_y - gap
    local key_top_min = hint_y + U(14)
    local kh = math.floor((key_bottom - gap * 3 - key_top_min) / 4)
    if kh < U(8) then kh = U(8) end
    if kh > U(44) then kh = U(44) end
    -- 只按 key_bottom 反推 key_top，不往上夹（否则第 4 行会压到动作键）
    local key_top = key_bottom - (4 * kh + gap * 3)
    local kw = math.floor((iw - gap * 2) / 3)
    local keys = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
                   { "+/-", "0", "退格" } }
    for ri = 1, 4 do
        for ci = 1, 3 do
            local k = keys[ri][ci]
            if btn(px + (ci - 1) * (kw + gap), key_top + (ri - 1) * (kh + gap), kw, kh, k) then
                if k == "退格" then
                    GS.buffer = tostring(GS.buffer or ""):sub(1, -2)
                elseif k == "+/-" then
                    local b = tostring(GS.buffer or "")
                    if b:sub(1, 1) == "-" then GS.buffer = b:sub(2) else GS.buffer = "-" .. b end
                else
                    GS.buffer = tostring(GS.buffer or "") .. k
                end
            end
        end
    end
    -- 值框最后画：本帧刚按的键立刻出现在框里
    fillr(px, box_y, iw, box_h, GC.row_a)
    fillr(px, box_y, U(3), box_h, GC.accent)
    local shown = tostring(GS.buffer or "")
    local blink = (math.floor((GP.frames or 0) / 20) % 2 == 0) and "|" or ""
    if shown == "" then
        txt(px + U(10), box_y + U(11), "点键盘输入数字" .. blink, GC.muted, 0.48, iw - U(18))
    else
        txt(px + U(10), box_y + U(10), shown .. blink, GC.text, 0.64, iw - U(18))
    end
    local hit = actions(act_y, { "清空", "默认", "确定", "取消" })
    if hit == "清空" then GS.buffer = ""
    elseif hit == "默认" then edit_restore_default()
    elseif hit == "确定" then commit_edit()
    elseif hit == "取消" then GS.editing, GS.buffer = nil, "" end
end

-- ============ 21.10 帧 ============
local API40 = {
    "text", "text_wrapped", "button", "checkbox", "slider", "same_line", "separator", "spacing",
    "collapsing_header", "progress_bar", "input_text", "set_title", "set_pos", "get_pos",
    "set_width", "set_cursor", "set_visible", "is_visible", "show", "hide", "set_collapsed",
    "is_collapsed", "toggle_collapsed", "set_style", "rect", "text_at", "button_at",
    "set_content_height", "load_image", "image_status", "release_image", "image", "image_fit",
    "nine_slice", "image_button", "set_skin",
    "begin_scroll", "end_scroll", "scroll_to", "image_cache_stats",
}

local function keys_stats()
    local n, hash = 0, 0
    local ks = {}
    for k in pairs(DEFAULTS) do ks[#ks + 1] = k end
    table.sort(ks)
    for i = 1, #ks do
        n = n + 1
        local s = ks[i]
        for j = 1, #s do hash = (hash * 31 + s:byte(j)) % 65521 end
    end
    return n, hash
end

local function gui_init()
    if GUI_INIT then return end
    GUI_INIT = true
    for i = 1, #GUI_GROUPS do GS.fold[i] = true end
    GS.layout = (cfg.gui_layout == "分页") and "分页" or "滚动"
    gui_state_read()
    local have, miss = 0, {}
    for i = 1, #API40 do
        if has(API40[i]) then
            have = have + 1
        else
            miss[#miss + 1] = API40[i]
        end
    end
    GUI.api_have = have
    GUI.api_missing = table.concat(miss, ",")
    GUI.keys_n, GUI.keys_hash = keys_stats()
end

local function apply_pos()
    if not GP.done or GP.pos_applied then return end
    local x, y = num(GP.saved_x, 24), num(GP.saved_y, 24)
    local sw = (not GP.unclamped) and GP.screen_w or 0
    local sh = (not GP.unclamped) and GP.screen_h or 0
    local ww = win_w()
    local wh = avail_h() + U(56)
    if sw > 0 then
        if x + ww > sw then x = sw - ww - U(6) end
        if x < 0 then x = 0 end
    end
    if sh > 0 then
        if y + wh > sh then y = sh - wh end
        if y < 0 then y = 0 end
    end
    if api("set_pos", math.floor(x), math.floor(y)) then
        GP.pos_applied = true
    end
end

local function gui_draw()
    gui_init()
    probe_step()
    load_images()
    local ww = win_w()
    -- ★ v2.1.2 左右等距（与玩家工坊同一算法）：
    --   加载器内容区 = 窗口宽 − 2×pad（pad = 12×g），内容原点本身已在 pad 处；
    --   这里只负责「内容区内」的对称留白：左右各减同一个 inset。
    local pad = rnd(12 * (GP.g or 1))
    local cw = ww - 2 * pad
    if cw < 160 then cw = 160 end
    local inset = rnd(4 * (GP.g or 1))
    local bx = inset
    local bw = cw - 2 * inset
    if bw < 120 then bw = 120 end
    GUI_CW, GUI_PAD = cw, pad
    VX, VW = bx, bw
    if GP.width ~= ww then
        api("set_width", ww)
        GP.width = ww
    end
    apply_theme()
    apply_skin()
    local ver = tostring(mod.meta.version)
    api("set_title", "属性工坊 v" .. ver, IMG.glyph and "工" or "IF")
    local lay = layout_effective()
    -- 头部第一行：版本 + 布局 + 写入数（窗口标题已经是「属性工坊 vX」，这里不再重复）
    txt(bx, U(4), "v" .. ver .. " · " .. lay .. " · 写入 " .. STAT.item_writes .. " 项",
        GC.accent, 0.56, bw)
    local sub = string.format("第 %d/%d 页 · 设置 %d 项 · API %d/40", GS.tab, #GUI_PAGES, GUI.keys_n, GUI.api_have)
    if lay == "分页" and not has("begin_scroll") then
        sub = sub .. " · 本机不支持滚动"
    end
    txt(bx, U(23), sub, GC.muted, 0.46, bw)
    local gap = U(6)
    local tw = math.floor((bw - gap * (#GUI_PAGES - 1)) / #GUI_PAGES)
    if tw < U(40) then tw = U(40) end
    if tw * #GUI_PAGES + gap * (#GUI_PAGES - 1) > bw then
        tw = math.floor((bw - gap * (#GUI_PAGES - 1)) / #GUI_PAGES)
    end
    for i = 1, #GUI_PAGES do
        local tx = bx + (i - 1) * (tw + gap)
        if btn(tx, U(40), tw, U(30), GUI_PAGES[i]) then
            if GS.tab ~= i then
                GS.tab = i
                GS.confirm_key = nil
                gui_state_write()
            end
        end
        if GS.tab == i then fillr(tx + U(3), U(70), tw - U(6), U(4), GC.accent) end
    end
    local body0 = U(80)
    local vh = avail_h() - body0 - U(6)
    if vh < U(110) then vh = U(110) end
    -- 正文不再叠第二层纸：窗口皮肤本身已经是羊皮纸，再套一层九宫格会变成双层边框。
    if GS.editing then
        draw_edit_overlay(bx, bw, body0, vh)
    elseif lay == "滚动" then
        draw_page_scroll(body0, vh)
    else
        draw_page_paged(body0, vh)
    end
    apply_pos()
end

local function gui_frame()
    GP.frames = GP.frames + 1
    api("set_content_height", avail_h())
    local ok, err = pcall(gui_draw)
    if not ok then
        GUI.last_err = tostring(err)
        api("set_content_height", avail_h())
    end
end

function mod.on_gui()
    if cfg.gui_enable == false then return end
    local ok, err = pcall(gui_frame)
    if not ok then GUI.last_err = tostring(err) end
end

-- ============ 21.11 诊断/测试句柄 ============
GUI.META = GUI_META
GUI.GROUPS = GUI_GROUPS
GUI.pages = GUI_PAGES
-- 左右等距判据：内容区宽 cw、加载器留白 pad、我们的绘制区 [bx, bx+bw]
GUI.box = function() return VX, VW, GUI_CW, GUI_PAD end
GUI.state = GS
GUI.cfg = cfg
GUI.defaults = DEFAULTS
GUI.probe = GP
GUI.lib = LIB
GUI.effective_layout = layout_effective
GUI.save_state = gui_state_write
GUI.load_state = gui_state_read
GUI.pager = pager
GUI.list_ids = lib_filtered
GUI.item_name = function(id) return LIB.names[id] end
GUI.list_state = list_state
GUI.log_tail = function(n)
    local out = {}
    local start = math.max(1, #LOG_RING - (tonumber(n) or 30) + 1)
    for i = start, #LOG_RING do out[#out + 1] = LOG_RING[i] end
    return out
end
GUI.render = gui_draw
GUI.reset = function()
    GUI_INIT = false
    GS.tab, GS.lib_page, GS.pg, GS.filter = 1, 1, {}, ""
    GS.editing, GS.buffer, GS.confirm_key = nil, "", nil
    GS.last_msg, GS.export_text, GS.show_export = "", "", false
    for i = 1, #GUI_GROUPS do GS.fold[i] = true end
end
GUI.lib_inject = function(ids, names)
    LIB.ids, LIB.names = {}, {}
    for i = 1, #(ids or {}) do
        LIB.ids[i] = ids[i]
        if names and names[i] then LIB.names[ids[i]] = names[i] end
    end
    LIB.done, LIB.scanned, LIB.tried = true, ITEM_CEILING, true
end
GUI.param_keys_count = function()
    local n = 0
    for i = 1, #GUI_GROUPS do n = n + #GUI_GROUPS[i].keys end
    return n
end
GUI.keys_n, GUI.keys_hash = 0, 0
end

itemforge_gui_install()


