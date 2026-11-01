-- ============================================================================
--  药水叠加 (BuffStack) v2.3.1   —— LuaLoader (lzup333.lualoader) 专用 Lua Mod
-- ----------------------------------------------------------------------------
--  只做一件事：当身上已经有某个状态效果、又吃到同一个效果时，不再按原版的
--  「谁长留谁」处理，而是把两次的剩余时间**相加**（时间叠加），仍然只占 1 个槽位。
--
--  ★ v2.0.0 相对 v1.1.0 的变更（本批 5 个模组的统一约定见
--    开发文档/12-下一版通用约定.md，那才是契约；本文件与它冲突时以它为准）
--    1) 【§4.5-①】按 buff 单独的时长上限 per_buff_limits（STRING）：
--       `编号:上限秒` 或 `名字:上限秒`，逗号分隔；另有按类别的默认值
--       per_buff_cat_limits（STRING，`类别:上限秒`）。
--       ★ 与全局 max_time_sec 的关系：**两者取小**（全局上限仍是总闸）。
--       解析失败有明确日志 + 诊断域 errs，并且**绝不影响其它设置**。
--    2) 【§4.5-②】减益也叠加开关 stack_debuff（SWITCH，默认 false）。
--       ★ 优先级顺序（写死并有测试断言）：
--           黑名单 > 免疫表 > 减益开关 > 强制位 > 类别开关 > 其他
--       「免疫表 > 减益开关」：免疫表是「连原版都不给加」，比叠加与否更靠前。
--    3) 【§4.5-③】叠加层数与总时长的可视化：announce 现在播报
--       「当前 N 层 / 共 M 秒」（层数 = 本模组在这条效果上成功结算的次数）。
--    4) 【§4.5-④】药水冷却缩减 potion_delay_mult（倍率类，默认 100 = 1 倍，上限 10000）。
--       ★ 只在 BuffStack 实现（玩家工坊不碰）。做法：改药水疾病(21)的时长
--         → 游戏自己会在 UpdateBuffs 里 potionDelay = buffTime[j]，所以整个冷却
--         自然缩短，而且不影响药水疾病这个 buff 该不该叠的判定。
--         并在 DelBuff(21) 后缀补一次（原版把 potionDelay 重置回原值时补乘）。
--    5) 【§4.5-⑤】强制移除/免疫指定 buff immune_buffs（STRING，列表式）。
--       黑名单 = 不叠加（效果照样有）；免疫表 = 直接不给加 + 身上已有时立刻移除。
--    6) 【§3.1 方案 B + §4.6】全套统一接口：
--       /forge export|import|stat|check|help、设置串分片、诊断域注册表、
--       self_check（默认开，进世界首帧播报一次）/ diag_report_cmd / diag_slow_ms。
--    7) 【§3.2】倍率/百分比类上限统一到 10000（=100 倍）；非倍率类（秒/帧/数量）不动。
--    8) Main.NewText 的 5 参 / 4 参探测抽成公共助手 chat_print(text)：
--       /forge 命令、自检播报、叠加播报**全部只走它**，不再有两份调用约定。
--
--  ★ v2.3.1：修「全部转永久」被每帧刷新打回、面板减为 3 页（删掉时间轴）、确认/取消不再重叠、
--   紫罗兰强调色与其它工坊面板区分。v2.3.0：羊皮纸主题、数字自由输入、可选 1~1000 滑块；
--    B2 blacklist_ids（真实 ID，与旧槽位并集）、B4 Buff 396 内置硬忽略。
--
--  ★ v2.1.0 新增（唯一一项）：
--    9) 【死亡保留】全部死亡保留开关 persist_all_on_death（SWITCH，默认 false）：
--       开启后把身上**所有**状态效果（无论是否已永久化、无论增益还是减益）都写进
--       游戏自带的 Main.persistentBuff，死亡重置时不会被清掉，复活后仍在。
--       ★ 与 persist_on_death 互不依赖：后者只管「已永久化的效果」，前者覆盖**全部**。
--       ★ 可逆：写之前先记下每条编号的原值，关掉开关后按原值还原（游戏自带的
--         71/73…79 那几条不受影响），不需要重启游戏。
--
--  依赖符号（每一个都用 参考库/符号/官方源码-{字段,方法}.tsv 核对过**形参个数**）：
--    Terraria.Player.buffType / buffTime  (int[]，长度 maxBuffs = 44)
--      官方源码-字段.tsv:16619 / :16620（public，非 const）
--    Terraria.Player.buffImmune (bool[])          字段.tsv:16621
--    Terraria.Player.whoAmI (int)                 字段.tsv（public）
--    Terraria.Player.maxBuffs (static；先 field_is_const 确证为 false 才读，否则用 44)
--    Terraria.Player.AddBuff_TryUpdatingExistingBuffTime(int,int) → 2 参  ← 主路径
--      源码依据：Player.cs 的 AddBuff() 里 `if (AddBuff_TryUpdatingExistingBuffTime(type, num)) return;`
--      即原版正是在这里判断「已经有了」并只保留较长时长；接管它 = 只改叠加规则、不动其它流程。
--    Terraria.Player.AddBuff(int,int,bool) → 3 参（方法.tsv；1.4.4 时代的 4 参写法已删）
--      ← 兜底路径 + 免疫拦截 + 药水冷却
--    Terraria.Player.DelBuff(int) → 1 参（方法.tsv）← 药水冷却：原版重置 potionDelay 时补乘
--    Terraria.Player.ClearBuff(int) → 1 参（方法.tsv）← 免疫表：一次性移除同种效果
--    Terraria.Player.ResetEffects() → 0 参        ← 每帧维持驱动 + 进世界门控
--    Terraria.Player.potionDelay (int)            字段.tsv:16688（public，非 const/readonly）
--    Terraria.Main.debuff / lightPet / vanityPet / meleeBuff / persistentBuff (static bool[])
--    Terraria.Main.netMode → static int **字段**（方法.tsv 无 get_/set_，只有字段）
--    Terraria.Main.get_myPlayer() → static int 0 参（属性 myPlayer 的 getter，字段.tsv:15405）
--    Terraria.Main.get_gameMenu() → static bool 0 参（属性 gameMenu 的 getter，字段.tsv:15431）
--      ★ 手机版 myPlayer / gameMenu 都是**属性**：patch.get_field 必然是 nil，
--        只能走 get_xxx()（或 get_property + property_get_method 桥接）。
--    Terraria.Main.NewText(string,byte,byte,byte,bool) → 5 参 static（手机版）；
--      另有 NewText(string,Color,bool) → 3 参重载（Color 是结构体，本模组不构造它）
--    Terraria.Lang.GetBuffName(int) → 1 参 static（播报与按名字写上限用）
--    Terraria.Chat.ChatCommandProcessor.ProcessIncomingMessage(ChatMessage,int) → 2 参 实例
--    Terraria.Chat.ChatHelper.SendChatMessageFromClient(ChatMessage) → 1 参 static
--    Terraria.Chat.ChatMessage.get_Text() → 0 参；后备字段 "<Text>k__BackingField"
--  写 buffTime 的时机依据：Player.UpdateBuffs 每帧做 `buffTime[j]--`（未死亡时），
--  过期槽位在 Player.Update 里 `buffType>0 and buffTime<=0` 时被 DelBuff —— 所以每帧
--  把永久效果的 buffTime 维持住，它就永远不会走到 0。
--  死亡保留依据：Player.UpdateDead 里 `if (buffType[i] <= 0 || !Main.persistentBuff[buffType[i]])`
--  会把非 persistentBuff 的效果清零 —— 写 Main.persistentBuff[type] 就是游戏自带的机制。
--
--  参考实现出处（参考库/lua/）：
--    health-lock / mana-lock : setup 只解析句柄 + 装钩子、pcall 包住 install_hook
--    light-penetration       : 沿父类链查字段 find_field + 属性→访问器桥接
--    combat-pets             : AddBuff 系列私有方法钩子 + pcall(patch.array_set, ...)
--    boss-direction-hint     : array_at 读 bool[]、属性→get_xxx 方法回退
--    drop-chain              : Main.netMode 静态字段读法（net_mode == 1 = 客机）
--    infinite-backpack       : Main.NewText 5 参（Android）用法
--    chat-commands           : 聊天命令拦截（ProcessIncomingMessage / SendChatMessageFromClient）
--  纪律：所有反射调用都 pcall 包住；句柄判空后早退；setup 里不调用任何游戏方法、
--        不读任何 const 字段；对象句柄绝不跨回调缓存。
--  ★ 未经实机验证：本工作区无法启动游戏，以上全部是静态分析 + 假内核测试的产物。
-- ============================================================================

mod.meta = { pkg_id = "ailab.lua.buffstack", version = "2.3.2" }

local P = mod.patch

local BLACK_SLOTS, ALLOW_SLOTS = 10, 6
local BUFF_CEILING  = 350   -- 保守编号上限（原版 BuffID.Count = 355），只给取名字与分类用
local CAP_FALLBACK  = 44    -- 原版 Player.maxBuffs = 44（源码核实）
local SHORT         = "药水叠加"        -- 统一行首 [药水叠加]
local SLUG          = "buffstack"      -- 设置串里的 slug
local POTION_BUFF   = 21               -- 药水疾病（原版 ApplyPotionDelay 里 AddBuff(21, potionDelay)）
local PER_LIMIT_MAX = 10000            -- 倍率/百分比类上限（§3.2）：单条上限也按同一上限夹取
local CHUNK         = 320              -- 设置串每片正文上限（§3.2）
local MAX_ENTRIES   = 100              -- 上限表 / 免疫表最多解析多少条（防手抖写爆）

-- ============================================================================
-- 1. 默认值 / 取值区间（必须与 Info.json 的 settings 逐项一致，打包器会校验）
--    ★ 倍率/百分比类上限 = 10000（§3.2，= 100 倍），默认 100 = 1 倍；
--      非倍率类（秒 / 帧 / 数量 / 编号）保持原有上限，不要一起放大。
-- ============================================================================
local DEFAULTS = {
    -- ---- 4 项总控（本批统一） ----
    enabled            = true,    -- 总开关
    host_only          = true,    -- 联机：仅房主生效（客机只读不写）
    tick_interval      = 10,      -- 非关键项刷新间隔（帧，1 = 逐帧 ≈ 旧行为）
    config_reload_sec  = 5,       -- 自动重读设置间隔（秒）
    write_log          = false,   -- 日志总开关（日志过大会崩游戏）

    -- ---- §4.6 诊断（5 模组统一键名） ----
    self_check         = true,    -- 进世界首帧把每个功能域的状态播报一次
    diag_report_cmd    = "forge stat", -- 详细报告命令（空 = 用默认）
    diag_slow_ms       = 50,      -- 单域平均耗时超过它就在报告里标 SLOW（1~1000）

    -- ---- 叠加核心 ----
    max_time_sec       = 86400,   -- UI：1 = 不限；内部 = 减 1（叠加后时长上限，秒）
    keep_sec           = 3600,    -- 永久效果的维持时长（秒）
    per_buff_limits    = "",      -- §4.5-① 单 buff 上限：编号:秒 或 名字:秒，逗号分隔
    per_buff_cat_limits = "",     -- §4.5-① 按类别默认上限：类别:秒，逗号分隔
    stack_debuff       = false,   -- §4.5-② 减益也叠加（PVP / 自虐向，默认关）
    immune_buffs       = "",      -- §4.5-⑤ 强制移除/免疫：编号或名字，逗号分隔

    -- ---- 类别开关 ----
    cat_buff           = true,    -- 类别开关：增益
    cat_debuff         = true,    -- 类别开关：减益
    cat_minion         = true,    -- 类别开关：召唤仆从
    cat_pet            = true,    -- 类别开关：宠物（光照 / 外观）
    cat_food           = true,    -- 类别开关：食物饱食
    cat_imbue          = true,    -- 类别开关：武器附魔
    cat_other          = true,    -- 类别开关：其他（6 个具名类别都判定不出来的编号）

    -- ---- 黑名单 / 强制位（旧槽位：UI 值 = 真实编号 + 1；STRING 用真实编号） ----
    blacklist_ids      = "94,6,396", -- 真实 ID、逗号分隔；空 = 不启用（与旧槽位取并集）
    blacklist_1        = 95,      -- 默认 95 = 魔力病(94)
    blacklist_2        = 7,       -- 默认 7 = 魔力涌动 / 魔力再生(6)
    blacklist_3        = 1,       -- UI 1 = 该槽位不使用
    blacklist_4        = 1,
    blacklist_5        = 1,
    blacklist_6        = 1,
    blacklist_7        = 1,
    blacklist_8        = 1,
    blacklist_9        = 1,
    blacklist_10       = 1,
    allow_1            = 1,       -- UI 1 = 该槽位不使用（强制可叠加，无视类别开关）
    allow_2            = 1,
    allow_3            = 1,
    allow_4            = 1,
    allow_5            = 1,
    allow_6            = 1,

    -- ---- 永久化 ----
    perm_threshold_sec = 1,       -- UI：1 = 关闭；内部 = 减 1（0 = 关闭）
    never_expire       = false,   -- 永不消失（全局）
    perm_only_buff     = true,    -- 永久化只作用于增益（保护性默认值）
    persist_on_death   = true,    -- 永久效果死亡复活后仍保留
    persist_all_on_death = false, -- 所有效果（含未永久化 / 减益）死亡复活后都保留

    -- ---- §4.5-④ 药水冷却缩减（倍率类：100 = 1 倍，上限 10000） ----
    potion_delay_mult  = 100,

    -- ---- 面板自身（19 章 §1.7） ----
    gui_enable         = true,    -- 关掉后 mod.on_gui 直接 return
    gui_layout         = "滚动",  -- CHOICE：滚动 / 分页
    gui_slider         = false,   -- SWITCH：参数页数值项额外显示 1~1000 滑块

    -- ---- 播报 / 日志 ----
    announce           = true,    -- 聊天栏播报（含 buff 编号 / 层数 / 总时长）
    debug_log          = false,   -- 详细日志（仍受 write_log 总开关约束）
}

local LIMITS = {
    tick_interval      = { 1, 60 },
    config_reload_sec  = { 1, 60 },
    diag_slow_ms       = { 1, 1000 },
    max_time_sec       = { 1, 86400 },
    keep_sec           = { 60, 86400 },
    -- 上限表 / 免疫表是 STRING：这里给的是「解析出来的每一条数值」的夹取区间
    per_buff_limits    = { 1, PER_LIMIT_MAX },
    per_buff_cat_limits = { 1, PER_LIMIT_MAX },
    blacklist_1        = { 1, 401 },
    blacklist_2        = { 1, 401 },
    blacklist_3        = { 1, 401 },
    blacklist_4        = { 1, 401 },
    blacklist_5        = { 1, 401 },
    blacklist_6        = { 1, 401 },
    blacklist_7        = { 1, 401 },
    blacklist_8        = { 1, 401 },
    blacklist_9        = { 1, 401 },
    blacklist_10       = { 1, 401 },
    allow_1            = { 1, 401 },
    allow_2            = { 1, 401 },
    allow_3            = { 1, 401 },
    allow_4            = { 1, 401 },
    allow_5            = { 1, 401 },
    allow_6            = { 1, 401 },
    perm_threshold_sec = { 1, 86400 },
    potion_delay_mult  = { 1, 10000 },      -- 倍率类：§3.2
}

-- UI 值 → 内部值的偏移表（1 = 内部 0；只列需要减 1 的键，其余原样）
-- DEFAULTS / LIMITS / Info.json 存的都是 UI 值，CFG.* 存内部值。
-- ★ 黑名单 / 强制位不在这里偏移：槽位统一存 UI 值，解析时 id = v - 1（B1）。
UI_OFFSET = {
    max_time_sec       = 1,
    perm_threshold_sec = 1,
}

-- CHOICE 的合法取值（必须与 Info.json 的 options 逐值一致，打包器会校验）
local CHOICES = {
    gui_layout = { "滚动", "分页" },
}

-- 内部值 → UI 值（导出设置串时用；与 UI_OFFSET 互为逆运算）
local function to_ui(key, v)
    local off = UI_OFFSET[key]
    if off and type(v) == "number" then return v + off end
    return v
end

local function to_internal(key, v)
    local off = UI_OFFSET[key]
    if off and type(v) == "number" then return v - off end
    return v
end

-- ============================================================================
-- 2. 运行时状态 + 日志总开关
-- ============================================================================
local CFG = {}
for k, v in pairs(DEFAULTS) do CFG[k] = to_internal(k, v) end   -- DEFAULTS 是 UI 值

-- ★ 本轮新增状态全部放全局表：main chunk 的 200 个 local 已用满（再加 local 编译失败）。
--   bs_state.ignore = 内置硬忽略表（B4：BuffID.ManaHeat = 396）
--   bs_state.extra  = blacklist_ids 解析结果（B2：与旧槽位取并集）
bs_state = {
    ignore = { [396] = true },
    extra = {},
    buffs = {},          -- 面板快照 {id,time,layers,name,ignored}
    snap_tick = 0,
    logs = {},           -- 面板「最近 30 行日志」环形缓冲
    pending = nil,       -- 面板一键操作：下一帧在 ResetEffects 里用新鲜实例执行
    need_snap = false,
    panel_seen = false,  -- 面板真正画过一帧后才维护快照（没开面板 = 零开销）
    override = {},       -- 面板改过的运行时值：重读设置时覆盖回 CFG，绝不写 TEFManager 设置
}
GUI_MOD = require("gui")

local LOG_ON, IN_SETUP = false, false     -- 日志总开关 / setup 阶段标记
local blacklist, allowlist = {}, {}       -- 生效中的编号集合
local bl_slot, al_slot = {}, {}           -- [槽位号] = 该槽位当前生效的编号（增量重建用）
-- ★ 这两个表名不要叫 per_buff_limits / immune_buffs：build_mod.py 会用
--   `per_buff_limits\s*=\s*<字面量>` 去 DEFAULTS 里核对默认值，重名会让它读到 LIMITS 那一行。
local per_limit_tab = {}                  -- [buffType] = 单 buff 上限（秒）
local cat_limit_tab = {}                  -- [类别名] = 该类别默认上限（秒）
local per_name_pending = false            -- 上限表里有「按名字写」但还没解析过
local immune_tab, immune_name_pending = {}, false
local shard_parts, shard_expect = {}, 0   -- 设置串分片缓存（按进世界重置）
local DOM = {}                            -- 诊断域注册表：DOM.<key> = {name=…, calls=…}
local OP_US = {}                          -- 同上，按登记顺序存一份（报告按顺序播报）

local net_mode          = -1              -- Main.netMode 缓存；-1 = 取不到 → 不限制
local net_ready         = false           -- 首次进钩子时求一次，之后跟配置节拍刷新
local readonly_mode     = false           -- host_only 生效且本机是客机 → 只读不写
local cached_my_player  = -1              -- Main.myPlayer 缓存（跟配置节拍刷新）
local reload_frames     = 300             -- 自动重读设置 + 刷新缓存的节拍（帧）

local ready         = false
local tick          = 0
local cap           = CAP_FALLBACK
local cap_locked    = false               -- 真机探测到更小长度后锁定，不再变化
local arr_type      = nil                 -- 当前绑定的 buffType 数组（每次进钩子重取）
local arr_time      = nil                 -- 当前绑定的 buffTime 数组
local statics       = {}                  -- 静态 bool[] 缓存：statics[key] = 数组 / false
local stat_missing  = {}
local keep_set      = {}                  -- [buffType] = true → 已永久化，需要每帧维持
-- persist_all_on_death 的原值快照挂在诊断域里（DOM.persist.orig），不新开文件级 local：
-- 主 chunk 的 local 数已接近 Lua 5.4 的 200 上限。
local name_cache    = {}
local announce_last = {}                  -- [buffType] = 上次播报的 tick
local layer_count   = {}                  -- [buffType] = {n = 累计层数, last = 上次叠加后的帧数}
local log_once_seen = {}
local cat_cache     = {}                  -- [buffType] = 类别（按编号分片失效，见 §10）
local pending       = nil                 -- 回退路径：prefix 记下的快照
local hook_mode     = "none"
local fallback_player = -1
local add_scope     = 0                   -- AddBuff 的嵌套深度（只处理最外层）
local helper_hit    = false               -- 本次 AddBuff 调用是否已被主路径结算过
local immune_hit    = false               -- 本次 AddBuff 是否已被免疫表拦下
local new_text_args = 0                   -- Main.NewText 的实参个数（0 = 播报不可用）
local self_scaled   = false               -- 本模组已经缩放过的 potionDelay（待原版重置那次补乘）
local in_world_prev = false               -- 进世界边沿标记（self_check 每次进世界各播一次）
local announce                            -- 前置声明（finalize_time / maintain 会用到）
local refresh_persistent, refresh_net_mode
local chat_print, load_config, recompute_derived, parse_entry_lists, apply_payload
local cmd_export, cmd_import, cmd_stat, cmd_check, cmd_help, self_check_report
local resolve_prop, limit_seconds_of

-- ★ 句柄变量必须在**使用点之前**声明（Lua 的 local 作用域从声明处开始！）。
--   原先这组声明放在 §5，而 §4 的 name_to_id() 先用了 M_get_buff_name →
--   那里读到的是全局 nil，「按名字写上限 / 免疫表」会永远解析失败。
local T_PLAYER, T_MAIN, T_LANG, T_CHAT_PROC, T_CHAT_HELPER, T_CHAT_MSG
local F_buff_type, F_buff_time, F_who_am_i, F_max_buffs, F_buff_immune, F_potion_delay
local F_m_debuff, F_m_light_pet, F_m_vanity_pet, F_m_melee_buff, F_m_persistent
local F_m_net_mode, F_msg_text
local M_try_update, M_add_buff, M_del_buff, M_clear_buff, M_reset_effects
local M_new_text, M_get_buff_name, M_get_my_player, M_get_game_menu
local M_proc_incoming, M_send_from_client, M_get_text

-- ★ 日志总开关（write_log）：这是本模组**唯一**的日志出口。
--   write_log = false 时，除了 setup() 阶段「符号取不到 / 钩子装不上」这类一次性诊断，
--   运行期（尤其逐帧与高频路径）任何 mod.info/warn/error/debug 都不执行，
--   也不会往 private_dir 写任何日志文件。
local log_i, log_w, log_e, log_d
bs_push_log = function(kind, msg)
    local t = bs_state.logs
    t[#t + 1] = { kind = tostring(kind or "info"), msg = tostring(msg or "") }
    while #t > 120 do table.remove(t, 1) end
end
log_i = function(msg) if LOG_ON then mod.info(msg) end bs_push_log("info", msg) end
log_w = function(msg) if LOG_ON or IN_SETUP then mod.warn(msg) end bs_push_log("warn", msg) end
log_e = function(msg) if LOG_ON or IN_SETUP then mod.error(msg) end bs_push_log("error", msg) end
log_d = function(msg) if LOG_ON and CFG.debug_log == true then mod.info(msg) end
    if CFG.debug_log == true then bs_push_log("debug", msg) end end

-- ============================================================================
-- 3. 诊断域注册表（§4.6-1：5 模组统一机制）
--    安装期登记一次；运行期只自增计数器（热路径里直接 d.calls = d.calls + 1，
--    不做函数调用；耗时累加走 add_ms，只有逐帧/高频域才用）。
-- ============================================================================
local CLK = os.clock                       -- 缓存 upvalue，热路径少一次全局查表
local OP_ON = true                         -- 是否给热路径域计时（诊断用；关掉则零 os.clock 开销）
local function add_ms(d)
    local t0 = CLK()
    return function()
        local dt = (CLK() - t0) * 1000
        d.ms = d.ms + dt
        if dt > d.max_ms then d.max_ms = dt end
    end
end

-- 登记一个功能域（§4.1）。安装期一次性写入 fields/methods/hooks，
-- 运行期只自增 calls/hits（热路径里直接 d.hits = d.hits + 1，不做函数调用）。
local function add_domain(key, name)
    local d = { key = key, name = name, fields = "?", methods = "?", hooks = "?",
                calls = 0, hits = 0, errs = 0, last_err = nil, ms = 0, max_ms = 0 }
    DOM[key] = d
    OP_US[#OP_US + 1] = d
    return d
end

local function st_fields(d, ok) if not ok then d.fields = "fail"
    elseif d.fields ~= "fail" then d.fields = "ok" end end
local function st_methods(d, ok) if not ok then d.methods = "fail"
    elseif d.methods ~= "fail" then d.methods = "ok" end end
local function st_hook(d, ok) if not ok then d.hooks = "fail"
    elseif d.hooks ~= "fail" then d.hooks = "ok" end end

-- 域错误：只在该域自己的失败分支里写（绝不在热路径每帧写）
local function domain_err(d, msg)
    d.errs = d.errs + 1
    d.last_err = tostring(msg)
    log_w("[" .. SHORT .. "] 域 " .. d.name .. " 出错：" .. tostring(msg))
end

-- ============================================================================
-- 4. 配置解析（TEFManager 改设置 → config.json → 这里解析）
-- ============================================================================
local function esc_key(key)
    return '"' .. key:gsub("([^%w])", "%%%1") .. '"'
end

-- 按 LIMITS 双向夹取：滑块上限已收紧，手改 config.json 也不能越界
-- （tick_interval / config_reload_sec 越界会直接破坏分桶与节拍，必须夹住）
local function parse_int(raw, key, fallback, lo, hi)
    if type(raw) ~= "string" then return fallback end
    local v = tonumber(raw:match(esc_key(key) .. "%s*:%s*(-?%d+)"))
    if not v then return fallback end
    v = math.floor(v)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

-- STRING 类：取 "key" : "值" 里的原始字面量。
-- ★ Lua 模式里的转义符是 `%` 而不是 `\`（写成 \\ 会被 Lua 字符串先吃掉一层，
--   模式里就只剩一个裸反斜杠 → 匹配永远失败）。这里用 %" / %% 。
local function parse_str(raw, key, fallback)
    if type(raw) ~= "string" then return fallback end
    -- 用「非贪婪 + 不含引号」的写法：嵌套的 (A|B)* 交替在 Lua 模式里不可靠
    local pat = esc_key(key) .. '%s*:%s*"([^"]*)"'
    local v = raw:match(pat)
    if not v then return fallback end
    v = v:gsub('%%"', '"')
    return v
end

local function parse_bool(raw, key, fallback)
    if type(raw) ~= "string" then return fallback end
    local v = raw:match(esc_key(key) .. "%s*:%s*(%a+)")
    if v == "true" then return true end
    if v == "false" then return false end
    return fallback
end

-- 黑名单 / 白名单：槽位存的是「设置页的 UI 值」= 真实编号 + 1，v <= 1 = 空槽。
-- ★ B1 修复：解析时统一 id = v - 1，绝不再把 UI 值当真实编号查表。
bs_slot_id = function(v)
    if type(v) ~= "number" or v <= 1 then return nil end
    local id = math.floor(v) - 1
    if id < 1 or id > 400 then return nil end
    return id
end

-- 并集重建：blacklist_ids（真实编号）∪ 旧槽位（UI 值 - 1）。10 个槽位，重建成本可忽略。
bs_rebuild_blacklist = function()
    local set = {}
    for id in pairs(bs_state.extra) do set[id] = true end
    for i = 1, BLACK_SLOTS do
        local id = bl_slot[i]
        if id then set[id] = true end
    end
    blacklist = set
end

bs_rebuild_allowlist = function()
    local set = {}
    for i = 1, ALLOW_SLOTS do
        local id = al_slot[i]
        if id then set[id] = true end
    end
    allowlist = set
end

local function refresh_bl_slot(i)
    local id = bs_slot_id(CFG["blacklist_" .. i])
    if bl_slot[i] ~= id then
        bl_slot[i] = id
        bs_rebuild_blacklist()
    end
end

local function refresh_al_slot(i)
    local id = bs_slot_id(CFG["allow_" .. i])
    if al_slot[i] ~= id then
        al_slot[i] = id
        bs_rebuild_allowlist()
    end
end

local function rebuild_id_sets()
    blacklist, allowlist, bl_slot, al_slot = {}, {}, {}, {}
    bs_parse_blacklist_ids()
    for i = 1, BLACK_SLOTS do refresh_bl_slot(i) end
    for i = 1, ALLOW_SLOTS do refresh_al_slot(i) end
    -- 所有槽位都为空时上面的 refresh 不会触发重建：显式重建一次，保证 STRING 生效。
    bs_rebuild_blacklist()
    bs_rebuild_allowlist()
end

local function tick_interval()
    local n = CFG.tick_interval
    if type(n) ~= "number" or n < 1 then return 1 end
    n = math.floor(n)
    if n > 60 then n = 60 end
    return n
end

-- ---------------------------------------------------------------------------
-- §4.5-① 上限表解析 / §4.5-⑤ 免疫表解析
-- 格式（与 README 一致）：
--   per_buff_limits     "5:600, 铁皮:600, 中毒:30"          ← 编号 / buff 名字
--   per_buff_cat_limits "buff:3600, debuff:60, minion:1800" ← 类别
--   immune_buffs        "94, 6, 魔力病, 魔力涌动"            ← 编号 / 名字
-- 见什么错就报什么错（diagnostics 域 errs + 日志），解析失败的那**一条**被跳过，
-- 其余条目照常生效；绝不因为一条写错就让整个设置失效。
-- ---------------------------------------------------------------------------
local CAT_ALIAS = {
    buff = "buff", debuff = "debuff", minion = "minion", pet = "pet",
    food = "food", imbue = "imbue", other = "other",
    ["增益"] = "buff", ["减益"] = "debuff", ["仆从"] = "minion", ["召唤"] = "minion",
    ["宠物"] = "pet", ["食物"] = "food", ["附魔"] = "imbue", ["其他"] = "other",
}

local function split_top(s, sep)
    local out = {}
    for raw_piece in tostring(s):gmatch("([^" .. sep .. "]+)") do
        local piece = raw_piece:gsub("^%s+", ""):gsub("%s+$", "")
        if piece ~= "" then out[#out + 1] = piece end
    end
    return out
end

-- B2：blacklist_ids = 真实 ID、逗号分隔、空 = 不启用；与旧槽位取并集。
bs_parse_blacklist_ids = function()
    bs_state.extra = {}
    local s = CFG.blacklist_ids
    if type(s) ~= "string" or s == "" then return end
    local dom = DOM and DOM.limits
    local entries = split_top(s, ",")
    if #entries > MAX_ENTRIES then
        if dom then domain_err(dom, "blacklist_ids 条目太多（" .. #entries .. " > " .. MAX_ENTRIES
            .. "），只取前 " .. MAX_ENTRIES .. " 条") end
        entries = { table.unpack(entries, 1, MAX_ENTRIES) }
    end
    for _, e in ipairs(entries) do
        local n = tonumber(e)
        if n and n >= 1 and n <= 400 then
            bs_state.extra[math.floor(n)] = true
        else
            if dom then domain_err(dom, "blacklist_ids: 不是 1~400 的真实编号（'" .. tostring(e) .. "'）") end
        end
    end
end

-- `编号:上限` / `名字:上限` 的单条解析；返回 key, sec, errmsg
local function split_kv(entry)
    local k, v = entry:match("^(.-)%s*[:：]%s*(-?%d+)%s*$")
    if not k then
        local k2 = entry:match("^(.-)%s*[:：]%s*(.*)$")
        if not k2 then return nil, nil, "缺少分隔符 ':'" end
        return nil, nil, "上限不是整数（'" .. tostring(entry) .. "'）"
    end
    k = k:gsub("^%s+", ""):gsub("%s+$", "")
    if k == "" then return nil, nil, "缺少 key" end
    local n = tonumber(v)
    if not n then return nil, nil, "上限不是整数" end
    if n < 1 then n = 1 end
    if n > PER_LIMIT_MAX then n = PER_LIMIT_MAX end
    return k, math.floor(n), nil
end

-- 把一行字面量里的 `%XX` 反转义（设置串用）
local function unescape(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

-- 把 buff 名字解析成编号；名字匹配失败返回 nil + 原因
local function name_to_id(name)
    if not M_get_buff_name then return nil, "取不到 Lang.GetBuffName（无法按名字解析）" end
    for id = 1, BUFF_CEILING do
        local ok, h = pcall(P.invoke, M_get_buff_name, id)
        if ok and h then
            local ok2, s = pcall(P.string_value, h)
            if ok2 and type(s) == "string" and s == name then return id end
        end
    end
    return nil, "找不到名叫「" .. tostring(name) .. "」的状态效果"
end

-- 单条 key → buff 编号。数字 key 直接当编号；名字要等进世界（GetBuffName 可用）才解析。
local function resolve_buff_key(k)
    local n = tonumber(k)
    if n then
        if n < 1 or n > 400 then return nil, "编号越界（" .. tostring(n) .. "，应为 1~400）" end
        return math.floor(n)
    end
    return name_to_id(k)
end

-- allow_pending：M_get_buff_name 还没取到时，把「按名字写」的条目记为待重解析而不是报错。
--   默认值 = (M_get_buff_name == nil)：load_config() 在 setup 里先跑一遍，那时句柄一定还没有。
parse_entry_lists = function(allow_pending)
    per_limit_tab, cat_limit_tab, immune_tab = {}, {}, {}
    local dom = DOM and DOM.limits
    if allow_pending == nil then allow_pending = (M_get_buff_name == nil) end
    local pending_names = false

    local s = CFG.per_buff_limits
    if type(s) == "string" and s ~= "" then
        local entries = split_top(s, ",")
        if #entries > MAX_ENTRIES then
            if dom then domain_err(dom, "per_buff_limits 条目太多（" .. #entries .. " > " .. MAX_ENTRIES .. "），只取前 " .. MAX_ENTRIES .. " 条") end
            entries = { table.unpack(entries, 1, MAX_ENTRIES) }
        end
        for _, e in ipairs(entries) do
            local k, sec, err = split_kv(e)
            if err then
                if dom then domain_err(dom, "per_buff_limits: " .. err) end
            else
                local id, why = resolve_buff_key(k)
                if id then
                    per_limit_tab[id] = sec
                elseif allow_pending then
                    -- 句柄还没就位：不报错，等 M_get_buff_name 就位后重解析一次
                    pending_names = true
                else
                    if dom then domain_err(dom, "per_buff_limits: " .. tostring(why)) end
                end
            end
        end
    end

    local c = CFG.per_buff_cat_limits
    if type(c) == "string" and c ~= "" then
        local entries = split_top(c, "|")           -- 类别默认值用 '|' 分隔，避免和逗号混淆
        if #entries == 1 and #split_top(c, ",") > 1 then entries = split_top(c, ",") end
        for _, e in ipairs(entries) do
            local k, sec, err = split_kv(e)
            if err then
                if dom then domain_err(dom, "per_buff_cat_limits: " .. err) end
            else
                local canon = CAT_ALIAS[k] or CAT_ALIAS[k:lower()]
                if canon then
                    cat_limit_tab[canon] = sec
                else
                    if dom then domain_err(dom, "per_buff_cat_limits: 未知类别「" .. tostring(k)
                        .. "」（可用：buff/debuff/minion/pet/food/imbue/other 或 增益/减益/仆从/宠物/食物/附魔/其他）") end
                end
            end
        end
    end

    local im = CFG.immune_buffs
    if type(im) == "string" and im ~= "" then
        local entries = split_top(im, ",")
        if #entries > MAX_ENTRIES then
            if dom then domain_err(dom, "immune_buffs 条目太多（" .. #entries .. " > " .. MAX_ENTRIES .. "），只取前 " .. MAX_ENTRIES .. " 条") end
            entries = { table.unpack(entries, 1, MAX_ENTRIES) }
        end
        for _, e in ipairs(entries) do
            if e:find("[:：]") then
                if dom then domain_err(dom, "immune_buffs: 只要编号或名字，不要写 ':'（'" .. e .. "'）") end
            else
                local id, why = resolve_buff_key(e)
                if id then
                    immune_tab[id] = true
                elseif allow_pending then
                    pending_names = true       -- 同上：句柄还没就位时不报错
                else
                    if dom then domain_err(dom, "immune_buffs: " .. tostring(why)) end
                end
            end
        end
    end

    per_name_pending, immune_name_pending = pending_names, pending_names
end

-- §4.5-① 上限查找：单 buff 上限 → 类别默认 → 全局 max_time_sec，全部**取小**
limit_seconds_of = function(id, cat)
    local best
    local per = per_limit_tab[id]
    if per then best = per end
    if cat then
        local cl = cat_limit_tab[cat]
        if cl and (not best or cl < best) then best = cl end
    end
    local g = CFG.max_time_sec
    if type(g) == "number" and g > 0 and (not best or g < best) then best = g end
    return best
end

recompute_derived = function()
    parse_entry_lists()
    if type(CFG.potion_delay_mult) ~= "number" then CFG.potion_delay_mult = 100 end
    if CFG.potion_delay_mult < 1 then CFG.potion_delay_mult = 1 end
    if CFG.potion_delay_mult > 10000 then CFG.potion_delay_mult = 10000 end
end

load_config = function()
    local raw = nil
    local ok, r = pcall(mod.read_file, "config.json")
    if ok and type(r) == "string" then raw = r end
    for k, def in pairs(DEFAULTS) do
        if type(def) == "boolean" then
            CFG[k] = parse_bool(raw, k, def)
        elseif type(def) == "string" then
            CFG[k] = parse_str(raw, k, def)
        else
            local lim = LIMITS[k]
            -- parse_int 按 LIMITS 夹在 UI 区间，这里再减偏移落回内部值
            CFG[k] = to_internal(k, parse_int(raw, k, def, lim and lim[1], lim and lim[2]))
        end
    end
    -- 面板改过的运行时值：覆盖回刚解析的 CFG（绝不写 TEFManager 设置）
    for k, v in pairs(bs_state.override) do
        if DEFAULTS[k] ~= nil then CFG[k] = v end
    end
    LOG_ON = (CFG.write_log == true)
    rebuild_id_sets()
    recompute_derived()
    local s = CFG.config_reload_sec
    if type(s) ~= "number" or s < 1 then s = 5 end
    reload_frames = math.floor(s) * 60
end

-- ============================================================================
-- 5. 句柄（setup 里解析一次）
-- ============================================================================
-- ============================================================================
-- 6. 底层读写包装（全部 pcall；句柄为空一律早退，绝不把空句柄送进反射调用）
-- ============================================================================
local function is_num(v) return type(v) == "number" end

local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local field = P.get_field(cur, name)
        if field then return field end
        cur = P.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function fget_int(field, inst, default)
    if not field then return default end
    local ok, v = pcall(P.get_field_value, field, inst, "int32")
    if ok and is_num(v) then return math.floor(v) end
    return default
end

local function fset_int(field, inst, v)
    if not field then return false end
    local ok, r = pcall(P.set_field_value, field, inst, math.floor(v), "int32")
    return ok and r ~= false
end

local function fget_obj(field, inst)
    if not field then return nil end
    local ok, v = pcall(P.get_field_value, field, inst, "object")
    if ok and v then return v end
    return nil
end

local function fget_bool(field, inst, default)
    if not field then return default end
    local ok, v = pcall(P.get_field_value, field, inst, "bool")
    if ok then return v == true end
    return default
end

local function call0(m)                 -- 0 参方法（实例/静态都不带实参）
    if not m then return nil end
    local ok, v = pcall(P.invoke, m)
    if ok then return v end
    return nil
end

-- 属性 → 访问器桥接（myPlayer / gameMenu 在手机版都是属性）
local function resolve_prop(type_handle, prop_name, getter_name)
    local m = P.get_method(type_handle, getter_name, 0)
    if not m then m = P.get_method(type_handle, getter_name) end
    if not m then
        local prop = P.get_property(type_handle, prop_name)
        if prop and P.property_get_method then
            local ok_p, mm = pcall(P.property_get_method, prop)
            if ok_p then m = mm end
        end
    end
    if m and P.method_param_count then
        local ok_n, n = pcall(P.method_param_count, m)
        if not ok_n or n ~= 0 then m = nil end
    end
    return m
end

local function a_int(arr, i)
    if not arr then return nil end
    local ok, v = pcall(P.array_at, arr, i, "int32")
    if ok and is_num(v) then return math.floor(v) end
    return nil
end

-- 三态：true / false / nil（nil = 数组句柄取不到 → 「判定不出来」）
local function a_bool(arr, i)
    if not arr then return nil end
    local ok, v = pcall(P.array_at, arr, i, "bool")
    if ok then return v == true end
    return nil
end

local function a_set_int(arr, i, v)
    if not arr or not P.array_set then return false end
    local ok, r = pcall(P.array_set, arr, i, v, "int32")
    if not ok then return false end
    return r ~= false
end

-- 一次性日志：即使日志关掉也要记账，避免下次再来一遍
local function log_once(tag, msg)
    if log_once_seen[tag] then return end
    log_once_seen[tag] = true
    log_i("[" .. SHORT .. "] " .. tostring(msg))
end

-- 静态 bool[]（Main.debuff 等）：首次用到时惰性取，取不到最多重试 3 次
local function static_arr(key, field)
    local cached = statics[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    if (stat_missing[key] or 0) >= 3 then
        statics[key] = false
        return nil
    end
    local arr = fget_obj(field, nil)
    if arr then
        statics[key] = arr
        return arr
    end
    stat_missing[key] = (stat_missing[key] or 0) + 1
    return nil
end

-- ============================================================================
-- 7. 编号 / 玩家
-- ============================================================================
-- 只读「确证不是 const」的静态字段；问不出来就永远用兜底值 44
local function read_max_buffs()
    local f = F_max_buffs
    if not f or not P.field_is_const then return nil end
    local ok_c, c = pcall(P.field_is_const, f)
    if not ok_c or c ~= false then return nil end       -- true 或 nil 都不读
    local ok, v = pcall(P.get_field_value, f, nil, "int32")
    if ok and is_num(v) and v >= 1 and v <= 400 then return math.floor(v) end
    return nil
end

-- Main.myPlayer：手机版是**属性**、无后备字段，只能 invoke get_myPlayer()。
local function refresh_my_player()
    local v = -1
    local r = call0(M_get_my_player)
    if is_num(r) and r >= 0 then v = math.floor(r) end
    if v < 0 or v > 255 then v = -1 end
    cached_my_player = v
end

local function my_player_index()
    if cached_my_player < 0 then refresh_my_player() end     -- 首帧惰性求一次，之后跟节拍刷新
    return cached_my_player
end

local function player_index(inst)
    return fget_int(F_who_am_i, inst, -1)
end

-- 只管本机玩家（原版的 buffTime 递减本来就带 whoAmI == Main.myPlayer 条件）
local function is_local(inst)
    if not inst then return false end
    local me = my_player_index()
    if me < 0 then
        if fallback_player < 0 then fallback_player = player_index(inst) end
        me = fallback_player
    end
    if me < 0 then return true end        -- 连编号都取不到：单人环境下当作本机处理
    return player_index(inst) == me
end

-- Main.gameMenu：同样是**属性**（get_gameMenu）。取不到时返回 nil（= 不阻止播报）
local function in_game_menu()
    local v = call0(M_get_game_menu)
    if v == nil then return nil end
    return v == true
end

-- ============================================================================
-- 8. 聊天栏输出（§2.2：全模组只走 chat_print 一个出口）
-- ============================================================================
-- ★ v1.1.0 修过 bug：旧版用 `get_method(T_MAIN,"NewText")`（不给 argc）做下限回退，
--   在只有 3 参重载 NewText(string, Color, bool) 的平台上会挂到它，而调用处硬写
--   4 个实参 → 「实参个数 ≠ 形参个数」是崩进程级错误（05-写法与陷阱 §4.5/§4.2）。
--   现在：只接受能安全构造实参的重载，并把句柄**自身的**实参个数记下来。
local function resolve_new_text()
    local m = P.get_method(T_MAIN, "NewText", 5)     -- 1.4.5.8 手机版（TSV 核实）
    if m then return m, 5 end
    m = P.get_method(T_MAIN, "NewText", 4)           -- 旧桌面端 NewText(string,byte,byte,byte)
    if m then return m, 4 end
    return nil, 0                                    -- 3 参重载需要 Color 结构体 → 放弃播报
end

-- ★ 唯一的聊天输出助手：/forge 命令、自检播报、叠加播报全部走它。
chat_print = function(text)
    if not text or not M_new_text or new_text_args == 0 or not P.string_create then return false end
    local ok_s, s = pcall(P.string_create, text)
    if not ok_s or not s then return false end
    local ok, r
    if new_text_args == 5 then
        ok, r = pcall(P.invoke, M_new_text, s, 255, 210, 70, false)
    else
        ok, r = pcall(P.invoke, M_new_text, s, 255, 210, 70)
    end
    if not ok or r == false then
        M_new_text, new_text_args = nil, 0
        log_w("[" .. SHORT .. "] Main.NewText 调用失败，已关闭聊天栏播报")
        return false
    end
    return true
end

local function buff_label(id)
    local cached = name_cache[id]
    if cached then return cached end
    local name = nil
    if M_get_buff_name and id >= 1 and id <= BUFF_CEILING then
        local ok, h = pcall(P.invoke, M_get_buff_name, id)
        if ok and h then
            local ok2, s = pcall(P.string_value, h)
            if ok2 and type(s) == "string" and #s > 0 then name = s end
        end
    end
    if not name then name = "Buff" .. tostring(id) end
    local out = name .. "(ID " .. tostring(id) .. ")"
    name_cache[id] = out
    return out
end

announce = function(id, text, kind)
    if CFG.announce ~= true then return end
    -- 去重键 = (效果, 播报种类)：叠加播报与「转为永久」播报互不顶掉
    local key = tostring(id) .. ":" .. tostring(kind or "stack")
    local last = announce_last[key]
    if last and (tick - last) < 300 then return end     -- 同一种效果 5 秒内只播一次
    announce_last[key] = tick
    chat_print("[" .. SHORT .. "] " .. buff_label(id) .. " " .. tostring(text))
end

-- ============================================================================
-- 9. 类别与规则
-- ============================================================================
-- 食物 / 饱食类：抄自 BuffID.Sets.IsFedState = {26, 206, 207, 332, 333, 334}（源码核实）
local FOOD_BUFFS = { [26] = true, [206] = true, [207] = true, [332] = true, [333] = true, [334] = true }

-- 召唤仆从类：抄自 Terraria.ID.BuffID 里名字带 Minion 的成员 + Ravens/DeadlySphere/
-- VampireFrog/StormTiger/EmpressBlade（泰拉棱镜）/BabySlime（史莱姆法杖），编号源码核实。
local MINION_BUFFS = {
    [64] = true,  [83] = true,  [125] = true, [126] = true, [133] = true, [134] = true,
    [135] = true, [139] = true, [140] = true, [161] = true, [182] = true, [187] = true,
    [188] = true, [214] = true, [263] = true, [322] = true, [325] = true, [335] = true,
}

-- 类别判定：返回 6 个具名类别之一，或 "other"（= 判定不出来）。
-- "other" 的两种来源：① 编号不在已知范围内（<=0 或 > 350）；② 游戏数据取不到
-- （没有 Terraria.Main / 静态数组句柄为空）→ 无法判断它是不是减益、宠物、附魔。
local function classify(id)
    if id <= 0 or id > BUFF_CEILING then return "other" end
    local deb = a_bool(static_arr("debuff", F_m_debuff), id)
    if deb == nil then return "other" end
    if deb == true then return "debuff" end
    if FOOD_BUFFS[id] then return "food" end
    local light  = a_bool(static_arr("lightPet",  F_m_light_pet),  id)
    local vanity = a_bool(static_arr("vanityPet", F_m_vanity_pet), id)
    if light == nil or vanity == nil then return "other" end
    if light == true or vanity == true then return "pet" end
    if MINION_BUFFS[id] then return "minion" end
    local imbue = a_bool(static_arr("meleeBuff", F_m_melee_buff), id)
    if imbue == nil then return "other" end
    if imbue == true then return "imbue" end
    return "buff"
end

-- 类别缓存：命中即返回；缓存由「桶任务」按编号分片失效（见 §11），
-- 所以世界重载 / 数据变化最多 tick_interval 帧后就会被重新判定。
local function category_of(id)
    local cached = cat_cache[id]
    if cached then return cached end
    local cat = classify(id)
    cat_cache[id] = cat
    return cat
end

-- ★ 优先级（§4.5-② 要求写死并有测试断言）：
--     ① 黑名单        —— 一定不叠加（压过一切）
--     ② 免疫表        —— 根本不给加 / 立刻移除（比「叠加与否」更靠前）
--     ③ 减益开关      —— 是减益且 stack_debuff=false → 不叠加（默认）
--     ④ 强制位        —— 无视类别开关，一定叠加
--     ⑤ 具名类别开关
--     ⑥ 其他开关（判定不出来的兜底）
local function stack_allowed(id)
    if id <= 0 then return false end
    if bs_state.ignore[id] then return false end       -- B4：BuffID.ManaHeat(396) 永久忽略
    if blacklist[id] then return false end
    if immune_tab[id] then return false end
    if allowlist[id] then return true end
    local cat = category_of(id)
    if cat == "debuff" then
        -- ★ 黑名单 > 减益开关：走到这里说明不在黑名单里
        if CFG.stack_debuff == true then return true end
        return CFG.cat_debuff == true
    end
    if cat == "food"   then return CFG.cat_food   == true end
    if cat == "pet"    then return CFG.cat_pet    == true end
    if cat == "minion" then return CFG.cat_minion == true end
    if cat == "imbue"  then return CFG.cat_imbue  == true end
    if cat == "other"  then return CFG.cat_other  == true end
    return CFG.cat_buff == true
end

-- 帧数上限：面板允许自由输入，但进游戏前必须落到 int32 安全区，
-- 否则 1e300 秒会变成 inf，fset_int 会写坏。
function bs_safe_frames(sec)
    local n = tonumber(sec) or 0
    if n ~= n or n <= 0 then return 0 end
    n = n * 60
    if n ~= n or n > 2147483647 then n = 2147483647 end
    return math.floor(n)
end

local function perm_frames()
    return bs_safe_frames(CFG.perm_threshold_sec)
end

-- 永久效果的维持时长：恒大于阈值，这样存档重进后还能重新判定为永久
local function keep_frames()
    local k = bs_safe_frames(CFG.keep_sec)
    local pf = perm_frames()
    if pf + 60 > k then k = pf + 60 end
    if k > 2147483647 then k = 2147483647 end
    return k
end

local function perm_allowed(id)
    if CFG.perm_only_buff == true and classify(id) == "debuff" then return false end
    return true
end

local function should_become_permanent(id, time)
    if bs_state.ignore[id] then return false end      -- B4：内置忽略项永不永久化
    if not perm_allowed(id) then return false end
    -- ★ v2.3.1：已经被「全部增益转永久」或阈值标记过，之后每次重新获得 / 刷新都继续永久。
    --   快乐(146=Sunflower) 这类效果原版每帧都 AddBuff(146, 2) 刷新一次；若这里不认
    --   keep_set，下一次刷新就会被全局时长上限重新夹取，表现成「按了转永久却没永久」。
    if keep_set[id] then return true end
    if CFG.never_expire == true then return true end
    local pf = perm_frames()
    return pf > 0 and is_num(time) and time >= pf
end

-- ============================================================================
-- 10. 叠加核心（只保留「时间叠加」）
-- ============================================================================
local function secs(frames) return math.floor(frames / 60) end

-- 句柄可以缓存，对象不行：每次进钩子都从「本次调用拿到的玩家实例」重取数组。
local function bind_arrays(inst)
    if not inst then return false end
    arr_type = fget_obj(F_buff_type, inst)
    arr_time = fget_obj(F_buff_time, inst)
    return arr_type ~= nil and arr_time ~= nil
end

local function find_slot(id)
    if not arr_type or not arr_time then return -1, 0 end
    for i = 0, cap - 1 do
        local t = a_int(arr_type, i)
        if t == nil then break end
        if t == id then
            local tm = a_int(arr_time, i)
            if tm and tm > 0 then return i, tm end
        end
    end
    return -1, 0
end

-- 结算要写入的时长：命中永久规则 → 维持时长；否则按「单 buff 上限 / 类别默认 / 全局
-- 上限」三者取小截断（§4.5-①）。
local function finalize_time(id, t)
    if not is_num(t) or t < 1 then t = 1 end
    if bs_state.ignore[id] then return t end          -- B4：不改写、不永久化、不参与上限
    if should_become_permanent(id, t) then
        if not keep_set[id] then
            keep_set[id] = true
            announce(id, "剩余时长已达阈值，转为永久效果（不再倒计时）", "perm")
        end
        return keep_frames()
    end
    local lim = limit_seconds_of(id, category_of(id))
    if lim and lim > 0 then
        local m = lim * 60
        if m ~= m or m > 2147483647 then m = 2147483647 end
        if t > m then t = m end
    end
    return t
end

-- 层数可视化（§4.5-③）：层数 = 本模组在这条效果上成功结算的次数。
-- 「重新开始计数」的两个判据：
--   ① 距上次叠加 ≥ LAYER_IDLE_FRAMES（30 秒，见下）：当成新的一轮；
--   ② 当前剩余时长比「上次写进去的时长 − 中间过去的帧数」小得多 → 说明它已经过期又被重获。
-- ★ 为什么是 30 秒而不是 announce 的 5 秒节流：玩家两次吃药常常隔几十秒，
--   若沿用 5 秒窗口，层数几乎永远显示 1，这个可视化就废了。buff 是每帧 -1，
--   所以「预期剩余」用帧数外推是准的（永久效果因为每帧被重写，帧差判据会自动失效）。
local LAYER_IDLE_FRAMES = 1800
local function bump_layer(id, cur_time, applied)
    local rec = layer_count[id]
    -- 预计剩余：上次结算时写进去的时长，减去这中间过去的帧数（buff 是每帧 -1）
    local gaps = rec and (tick - rec.frame) or nil
    -- 预期剩余：上次写进去的时长 − 中间经过的帧数（永久效果会被每帧重写，这个推算自动失效）
    local expect = rec and (rec.total - (gaps or 0)) or nil
    -- ★ 判据 ①：隔了 30 秒以上 → 当成新的一轮（早该过期了）；
    --   判据 ②：本次结算前它已经掉到预期以下（= 这中间它到期过，是新获得的一条）
    if not rec or gaps >= LAYER_IDLE_FRAMES or (expect and is_num(cur_time) and cur_time < expect - 60) then
        rec = { n = 0, frame = tick, total = 0 }
        layer_count[id] = rec
    end
    rec.n = rec.n + 1
    rec.frame = tick
    return rec.n
end

-- 返回 true = 本次叠加已由本模组处理完（主路径下调用方要跳过原方法）
local function stack_core(inst, id, applied, slot, old_time)
    if readonly_mode then return false end          -- ★ 联机：客机只读不写
    if CFG.enabled ~= true then return false end
    if not stack_allowed(id) then return false end
    if not is_num(applied) or applied <= 0 then return false end
    if not is_num(old_time) or old_time <= 0 or slot < 0 then return false end

    local d = DOM.result
    d.calls = d.calls + 1
    local done
    if OP_ON then done = add_ms(d) end
    local sum = old_time + applied
    -- ★ v2.3.1：已经永久的效果会被原版每帧刷新（如快乐 146 每帧 AddBuff(146,2)）。
    --   这种刷新既不该累加层数（否则几分钟后变成「2101 层」），也不该每 5 秒刷一次播报。
    local was_perm = keep_set[id] == true
    local t = finalize_time(id, sum)
    local layers
    if was_perm then
        layers = (layer_count[id] and layer_count[id].n) or 1
    else
        layers = bump_layer(id, old_time, applied)
    end
    local ok_write = a_set_int(arr_time, slot, t)
    if ok_write and layer_count[id] then
        layer_count[id].frame = tick
        layer_count[id].total = t
    end
    if done then done() end
    if not ok_write then
        d.errs = d.errs + 1
        d.last_err = "写入槽位 " .. tostring(slot) .. " 失败"
        log_d("写入时长失败（槽位 " .. tostring(slot) .. "）")
        return false
    end
    d.hits = d.hits + 1
    if is_local(inst) and not was_perm then
        announce(id, string.format("时间叠加：%d 秒 + %d 秒 = %d 秒（当前 %d 层 / 共 %d 秒）",
            secs(old_time), secs(applied), secs(t), layers, secs(t)))
    end
    return true
end

-- ============================================================================
-- 11. §4.5-⑤ 免疫表：直接移除（黑名单是「不叠加」，免疫表是「根本不给」）
-- ============================================================================
-- 就地删除一个状态槽位并**照抄原版 DelBuff 的压缩逻辑**（玩家自己的 DelBuff 是
-- 实例方法、Core 里能直接调；这里同时准备手动版作为退路，两者必须等价）。
local function compact_slots()
    local num = 0
    for i = 0, cap - 2 do
        local t, tm = a_int(arr_type, i), a_int(arr_time, i)
        if t and tm and t ~= 0 and tm ~= 0 then
            if num < i then
                a_set_int(arr_time, num, tm)
                a_set_int(arr_type, num, t)
                a_set_int(arr_time, i, 0)
                a_set_int(arr_type, i, 0)
            end
            num = num + 1
        end
    end
end

local function remove_buff_at(inst, slot)
    if slot < 0 then return false end
    -- 首选游戏自己的 DelBuff(slot)（源码核实：只清这一格 + 压缩）
    if M_del_buff then
        local before = a_int(arr_type, slot)
        local ok, r = pcall(P.invoke, M_del_buff, inst, slot)
        if ok and r ~= false then
            -- 原版 DelBuff 会压缩槽位：删掉后该格可能被后面的效果占用，
            -- 所以判据是「这一格不再是原来那条」，不是「这一格变 0」。
            local after = a_int(arr_type, slot)
            if before ~= nil and after ~= before then return true end
        end
    end
    if not a_set_int(arr_time, slot, 0) then return false end
    a_set_int(arr_type, slot, 0)
    compact_slots()
    return true
end

-- 免疫表命中：返回 true = 这次 AddBuff 不应该生效
local function immune_blocks(inst, id)
    local d = DOM.immune
    if not immune_tab[id] then return false end
    d.calls = d.calls + 1
    local slot = find_slot(id)
    if slot >= 0 then
        if remove_buff_at(inst, slot) then d.hits = d.hits + 1 end
    else
        d.hits = d.hits + 1
    end
    if is_local(inst) then
        announce(id, "在免疫表里：已拦下 / 移除（黑名单只是「不叠加」，免疫表是「直接不给」）", "immune")
    end
    return true
end

-- 一次性清扫：进世界后轮到 b==1 那个桶时扫一遍本机玩家（只扫免疫表里的编号，表空时零开销）。
-- ★ 桶号 = tick % n + 1：默认 n=10 时，第 1 桶落在 **tick=9**（第 9 帧），不是第 1 帧；
--   n=1 时才是每帧。这一点写进 README，免得以为「进世界立刻清」是第 1 帧的事。
local function sweep_immune(inst)
    if next(immune_tab) == nil then return end
    if readonly_mode then return end            -- ★ 联机：客机只读不写（host_only）
    if not bind_arrays(inst) then return end
    local d = DOM.immune
    for i = 0, cap - 1 do
        local t = a_int(arr_type, i)
        if t == nil then break end
        if t > 0 and immune_tab[t] then
            d.calls = d.calls + 1
            if remove_buff_at(inst, i) then d.hits = d.hits + 1 end
            log_d("免疫表：移除了槽位 " .. tostring(i) .. " 上的效果 " .. tostring(t))
        end
    end
end

-- ============================================================================
-- 12. §4.5-④ 药水冷却缩减（只在 BuffStack 实现，玩家工坊不碰）
-- ============================================================================
-- 原理：原版 Player.UpdateBuffs 里 `else if (buffType[j] == 21) potionDelay = buffTime[j];`
-- → 药水疾病(21) 的 buffTime 就是冷却本体。**改它的时长**即可等比缩短冷却，
--   而且完全不影响「药水疾病该不该叠加」的判定（它照样走本模组的叠加规则）。
-- 数值：mult = potion_delay_mult / 100；scaled = floor(v * mult)。
-- 副作用（写进 README）：缩放后折算可能差 1 帧；药水疾病图标的倒计时会跟着变短。
local function potion_scale_ok(inst)
    if readonly_mode then return false end
    if CFG.enabled ~= true then return false end
    if type(CFG.potion_delay_mult) ~= "number" or CFG.potion_delay_mult == 100 then return false end
    if not F_potion_delay then return false end
    if not is_local(inst) then return false end
    return true
end

local function scale_value(v)
    local m = CFG.potion_delay_mult / 100
    local out = math.floor(v * m)
    if out < 1 then out = 1 end
    if out > 2147483647 then out = 2147483647 end
    return out
end

-- AddBuff 后缀里对「药水疾病」生效
local function potion_apply(inst, id)
    if id ~= POTION_BUFF then return end
    if not potion_scale_ok(inst) then return end
    local d = DOM.potion
    d.calls = d.calls + 1
    local slot, tm = find_slot(id)
    if slot < 0 or not tm or tm <= 0 then return end
    local scaled = scale_value(tm)
    if scaled == tm then return end
    if not a_set_int(arr_time, slot, scaled) then
        d.errs = d.errs + 1
        d.last_err = "写入药水疾病时长失败"
        return
    end
    if fset_int(F_potion_delay, inst, scaled) then self_scaled = true end
    d.hits = d.hits + 1
    if is_local(inst) then
        announce(id, string.format("冷却缩减：%d 秒 → %d 秒（倍率 %d%%）",
            secs(tm), secs(scaled), CFG.potion_delay_mult), "potion")
    end
end

-- DelBuff 后缀：原版在「药水疾病被清掉」时会把 potionDelay 重置回**未缩放**的值
-- （源码核实 Player.cs:11808 的赋值 + 解除时按 buff 原来的时长重置），这里补乘一次。
local function potion_restore(inst)
    if not self_scaled then return end
    if not potion_scale_ok(inst) then return end
    if not bind_arrays(inst) then return end
    -- 两种情况都要补一次：① 还有药水疾病（原版刚才把 potionDelay 重置回原值）
    -- ② 药水疾病已被清掉（残留的值仍是未缩放的原值）。补乘保证与 buffTime 一致。
    local raw = fget_int(F_potion_delay, inst, -1)
    if raw > 1 then
        local scaled = scale_value(raw)
        if scaled < raw then
            if fset_int(F_potion_delay, inst, scaled) then
                DOM.potion.hits = DOM.potion.hits + 1
            end
        end
    end
    self_scaled = false
end

-- 分桶任务里的收尾：药水疾病真过期后解除标记（避免下一次误缩放）
local function potion_sweep(inst)
    if not self_scaled then return end
    if not bind_arrays(inst) then return end
    local slot, tm = find_slot(POTION_BUFF)
    if slot < 0 or not tm or tm <= 0 then self_scaled = false end
end

-- ============================================================================
-- 13. 总控：netMode / 分桶 / 节拍 / 每帧维持
-- ============================================================================
-- Main.netMode：static int 字段（方法.tsv 里没有 get_/set_，只有字段）。取不到时
-- **必须退化成「不限制」**，绝不能因为联机判定失败就让整个模组失效。
refresh_net_mode = function()
    local v = -1
    local f = F_m_net_mode
    if f and P.field_is_const then
        local ok_c, c = pcall(P.field_is_const, f)
        if ok_c and c == false then v = fget_int(f, nil, -1) end
    end
    if v < 0 or v > 3 then v = -1 end               -- 取不到 / 非法 → 不限制
    net_mode = v
    readonly_mode = (CFG.host_only == true) and (v == 1)
end

-- 首次进写入路径时补一次 netMode（进世界后才有意义），之后跟配置节拍刷新
local function ensure_net_mode()
    if not net_ready then
        refresh_net_mode()
        net_ready = true
    end
end

-- 死亡保留登记（非关键状态刷新，由桶任务驱动，不再每 30 帧无条件跑）
--   ① keep_set：persist_on_death 只管「已永久化」的效果（行为与旧版一致）；
--   ② persist_all_on_death：把**当前身上所有**效果（含未永久化 / 减益）都登记。
-- ★ ② 可逆：写之前把每条编号的原值记进 DOM.persist.orig，关掉开关后原样写回
--   （游戏自带的 persistentBuff[71/73…79] 也在「原值」里，不会被误清）。
--   ★ 快照不新开文件级 local：主 chunk 的 local 数已接近 200 上限。
refresh_persistent = function()
    local arr = static_arr("persistentBuff", F_m_persistent)
    if not arr then return end
    local d = DOM.persist
    local orig = d.orig
    local all = (CFG.persist_all_on_death == true)

    -- 关掉「全部保留」后把之前改过的标记还原（只动我们改过的那几条）
    if not all and next(orig) ~= nil then
        local n = 0
        for id, old in pairs(orig) do
            if a_set_int(arr, id, old and 1 or 0) then n = n + 1 end
            orig[id] = nil
        end
        if n > 0 then log_d("全部死亡保留已关闭：已还原 " .. tostring(n) .. " 条 persistentBuff 标记") end
    end

    -- ① 已永久化的效果（受 persist_on_death 控制）
    if CFG.persist_on_death == true then
        for id in pairs(keep_set) do
            if a_bool(arr, id) ~= true then
                if a_set_int(arr, id, 1) and a_bool(arr, id) == true then
                    log_d("效果 " .. tostring(id) .. " 已登记为死亡后保留")
                end
            end
        end
    end

    -- ② 全部保留：扫当前状态槽位，把每一条都登记（arr_type 未绑定时跳过本域）
    if all and arr_type then
        for i = 0, cap - 1 do
            local id = a_int(arr_type, i)
            if id == nil then break end
            if id > 0 then
                local cur = a_bool(arr, id)
                if cur ~= nil then
                    if orig[id] == nil then orig[id] = cur end
                    if cur ~= true then
                        d.calls = d.calls + 1
                        if a_set_int(arr, id, 1) and a_bool(arr, id) == true then
                            d.hits = d.hits + 1
                            log_d("效果 " .. tostring(id) .. " 已登记为死亡后保留（全部保留）")
                        end
                    end
                end
            end
        end
    end
end

-- ★ 必须逐帧的活（buff 时长维持 / 永久化维持）保持逐帧，一秒都不能放宽。
local function maintain()
    if readonly_mode then return end
    -- 默认配置里永久化是关的、keep_set 也是空的 → 这一帧什么都不用做（零 array_at 开销）
    if perm_frames() <= 0 and CFG.never_expire ~= true and next(keep_set) == nil then return end
    local kt = keep_frames()
    for i = 0, cap - 1 do
        local id = a_int(arr_type, i)
        if id == nil then
            -- 这个下标读不到：真机数组比 44 短（手机版可能不同），按实际值收缩
            if not cap_locked and i > 0 then
                cap_locked = true
                cap = i
                log_once("cap", "真机状态槽位数为 " .. tostring(i) .. "（不是 44），已按实际值工作")
            end
            break
        end
        if id > 0 and not bs_state.ignore[id] then
            local tm = a_int(arr_time, i)
            if tm and tm > 0 then
                if not keep_set[id] and should_become_permanent(id, tm) then
                    keep_set[id] = true
                    announce(id, "剩余时长已达阈值，转为永久效果（不再倒计时）", "perm")
                end
                if keep_set[id] and tm ~= kt then
                    a_set_int(arr_time, i, kt)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 13b. 面板数据（只读快照，供 gui.lua 状态页/一键页计数；不跨回调缓存玩家对象句柄）
-- ---------------------------------------------------------------------------
bs_update_snapshot = function()
    local out = {}
    if not bs_state.panel_seen or CFG.gui_enable ~= true or not arr_type or not arr_time then
        bs_state.buffs, bs_state.snap_tick = out, tick
        return
    end
    for i = 0, cap - 1 do
        local id = a_int(arr_type, i)
        if id == nil then break end                     -- 越界 / 短数组：一律跳过
        if id > 0 then
            local tm = a_int(arr_time, i)
            if tm and tm > 0 then
                local rec = layer_count[id]
                out[#out + 1] = {
                    id = id, time = tm, layers = (rec and rec.n) or 1,
                    name = buff_label(id), ignored = (bs_state.ignore[id] == true),
                }
            end
        end
    end
    bs_state.buffs, bs_state.snap_tick = out, tick
end

-- 面板一键操作：只登记，下一帧由 ResetEffects 用**新鲜**的玩家实例执行（不缓存对象）。
bs_run_action = function(action, inst)
    if action == "self_check" then self_check_report(); return end
    if action == "reload" then
        bs_state.override = {}
        load_config()
        refresh_net_mode()
        refresh_my_player()
        bs_state.need_snap = true
        chat_print("[" .. SHORT .. "] 已重读设置（面板改动已放弃）")
        return
    end
    if not inst or not bind_arrays(inst) then return end
    if action == "clear_debuffs" then
        if readonly_mode then chat_print("[" .. SHORT .. "] 客机只读（host_only）：不清空减益"); return end
        local n = 0
        for i = cap - 1, 0, -1 do
            local id = a_int(arr_type, i)
            if id and id > 0 and not bs_state.ignore[id] and classify(id) == "debuff" then
                if remove_buff_at(inst, i) then n = n + 1 end
            end
        end
        chat_print("[" .. SHORT .. "] 已清空减益 " .. n .. " 个（内置忽略项保留）")
    elseif action == "perm_all" then
        if readonly_mode then chat_print("[" .. SHORT .. "] 客机只读（host_only）：不改永久化"); return end
        local n = 0
        for i = 0, cap - 1 do
            local id = a_int(arr_type, i)
            if id == nil then break end
            if id > 0 and not bs_state.ignore[id] and classify(id) ~= "debuff" then
                keep_set[id] = true
                if a_set_int(arr_time, i, keep_frames()) then n = n + 1 end
            end
        end
        chat_print("[" .. SHORT .. "] 已把 " .. n .. " 个增益转为永久（内置忽略项保留）")
    elseif action == "clear_log" then
        bs_state.logs = {}
    end
    bs_update_snapshot()
end

-- ★ 可放宽的活：按序号平摊进 tick_interval 个桶，每帧只跑「当前帧号 % 间隔」那个桶。
--   桶编号 = tick % n + 1 ∈ [1, n]（Lua 下标从 1 起，不会越界）。
local function run_bucket(b, n, inst)
    -- ① 黑名单 / 白名单集合重建：本桶只负责第 b, b+n, b+2n … 个槽位
    for i = b, BLACK_SLOTS, n do refresh_bl_slot(i) end
    for i = b, ALLOW_SLOTS, n do refresh_al_slot(i) end

    -- ② 类别缓存分片失效：本桶只负责它那一段编号，下一帧按需重算
    local chunk = math.ceil(BUFF_CEILING / n)
    local lo = (b - 1) * chunk + 1
    local hi = lo + chunk - 1
    if hi > BUFF_CEILING then hi = BUFF_CEILING end
    for id = lo, hi do cat_cache[id] = nil end

    -- ③ 非关键状态刷新（只让第 1 桶做，避免 n 倍重复）
    if b == 1 then
        refresh_persistent()
        -- ④ §4.5-⑤ 免疫表清扫（进世界第一桶就会跑；表空时零开销）
        if inst then sweep_immune(inst) end
    end
end

-- 进世界边沿检测（§4.3）：Main.gameMenu == false 且 ResetEffects 被调用 = 已在世界里。
-- 每帧只做一次 0 参属性读取，成本可忽略；退出世界（gameMenu 变 true）时清零标记。
local function world_edge_check()
    local menu = in_game_menu()
    if menu == true then
        if in_world_prev then in_world_prev = false end
        return false
    end
    if not in_world_prev then
        in_world_prev = true
        return true                      -- 本次是「进世界」的第一帧
    end
    return false
end

-- 节拍：设置重读 + netMode / myPlayer 缓存刷新（同一个节拍）
local function beat(inst)
    if tick == 1 or (tick % reload_frames) == 0 then
        load_config()
        refresh_net_mode()
        net_ready = true
        refresh_my_player()
        -- 名字类条目（上限表 / 免疫表里按名字写的）：还有没解析出来的就每个节拍再试一次
        if per_name_pending or immune_name_pending then parse_entry_lists(false) end
    end
    local n = tick_interval()
    run_bucket((tick % n) + 1, n, inst)
end

-- ============================================================================
-- 14. 钩子回调
-- ============================================================================
-- ★ 双路径：主路径 + 兜底路径**同时安装**，用 helper_hit / add_scope 协调，
--   保证「叠加只结算一次」，同时覆盖两种失效场景：
--     ① 主路径那个私有方法在真机上被内联/改名 → 钩子装上了却永远不会被调用；
--     ② 主路径符号本身就取不到。
--   只装主路径时，场景 ① 下模组看起来完全没生效。

-- 主路径：Player.AddBuff_TryUpdatingExistingBuffTime（private bool (int,int)）
local function on_try_update(instance, args, result)
    ensure_net_mode()
    if readonly_mode then return end            -- ★ 只读：不接管，交回原版
    if not ready or CFG.enabled ~= true or not instance or not args then return end
    local id, tm = args[1], args[2]
    if not is_num(id) or not is_num(tm) then return end
    id, tm = math.floor(id), math.floor(tm)
    if id <= 0 or tm <= 0 then return end
    if not bind_arrays(instance) then return end
    local slot, old_time = find_slot(id)
    if slot < 0 then return end                 -- 身上没有这个效果 → 交给原版新增
    helper_hit = true                           -- 这次确实进了「已有同种效果」的判定
    if stack_core(instance, id, tm, slot, old_time) then
        return true, true
    end
end

-- 兜底路径：Player.AddBuff 前缀（记快照 + 免疫拦截）+ 后缀（结算 + 药水冷却）
local function on_add_buff_pre(instance, args, result)
    add_scope = add_scope + 1                   -- 配平计数放在最前，postfix 才能对上
    ensure_net_mode()
    if add_scope > 1 then return end
    helper_hit = false
    immune_hit = false
    pending = nil
    if readonly_mode then return end            -- ★ 只读：不介入
    if not ready or CFG.enabled ~= true or not instance or not args then return end
    local id, tm = args[1], args[2]
    if not is_num(id) or not is_num(tm) then return end
    id, tm = math.floor(id), math.floor(tm)
    if id <= 0 or tm <= 0 then return end
    if not bind_arrays(instance) then return end
    -- AddBuff 的第一句就是 if (buffImmune[type]) return;（免疫时不会走到时长更新）
    local immune_now = a_bool(fget_obj(F_buff_immune, instance), id)
    if immune_now == true then return end
    -- §4.5-⑤ 免疫表：连原版都不给加（比「叠加与否」更靠前）
    if immune_blocks(instance, id) then
        immune_hit = true
        return true          -- ★ 必须显式 true：跳过原方法（`return` 等价返回 nil = 不接管）
    end
    local slot, old_time = find_slot(id)
    if slot < 0 then return end
    pending = { who = player_index(instance), id = id, tm = tm, slot = slot, old = old_time }
end

local function on_add_buff_post(instance, args, result)
    if add_scope > 0 then add_scope = add_scope - 1 end
    if readonly_mode then return end            -- ★ 只读：不结算
    if add_scope > 0 then return end            -- 嵌套调用的后缀：不结算
    local snap = pending
    pending = nil
    if not instance or not ready or CFG.enabled ~= true then return end
    -- §4.5-④ 药水冷却：即使这次 AddBuff 被免疫表拦下也要收尾，所以放在最前
    if args and args[1] then
        local aid = args[1]
        if is_num(aid) then potion_apply(instance, math.floor(aid)) end
    end
    if immune_hit then immune_hit = false; return end
    if helper_hit then return end                -- 主路径已经结算过：绝不叠加第二次
    if not snap then return end
    if player_index(instance) ~= snap.who then return end
    if not bind_arrays(instance) then return end
    -- 原版刚跑完：槽位可能被前面的 DelBuff 压缩挪动过，先确认再取
    local slot, cur = find_slot(snap.id)
    if slot < 0 then return end
    local applied = snap.tm
    -- 原版把时长改成了 max(旧, 专家倍率后的新值)：比旧值大的那个就是它实际写入的值
    if cur and cur > snap.old and cur > applied then applied = cur end
    stack_core(instance, snap.id, applied, slot, snap.old)
end

-- 兜底路径：Player.DelBuff(int) 后缀 —— 药水冷却的「原版重置」补乘
local function on_del_buff(instance, args, result)
    if readonly_mode or not ready or CFG.enabled ~= true then return end
    if not instance then return end
    potion_restore(instance)
end

-- 每帧驱动：Player.ResetEffects 后缀（0 参、14 个现成 Mod 都在用）
local function on_reset_effects(instance)
    if not ready or CFG.enabled ~= true or not instance then return end
    tick = tick + 1
    if not is_local(instance) then return end
    -- ★ 进世界首帧播报（self_check，默认开、一次性）
    if world_edge_check() and CFG.self_check == true then self_check_report() end
    if not bind_arrays(instance) then return end   -- 每帧重取对象字段（不缓存实例）
    -- 面板一键操作：用本帧的新鲜实例执行（避免缓存玩家对象句柄）
    if bs_state.pending then
        local act = bs_state.pending
        bs_state.pending = nil
        bs_run_action(act, instance)
    end
    if bs_state.panel_seen and (tick % 30 == 0 or bs_state.need_snap) then
        bs_state.need_snap = false
        bs_update_snapshot()
    end
    -- §4.5-④ 药水冷却的标记收尾：必须逐帧（原版下一帧就会用 buffTime 覆盖 potionDelay）；
    -- 它自己第一行就是 `if not self_scaled then return end`，倍率=100（默认）时零开销。
    potion_sweep(instance)
    beat(instance)                                 -- 桶任务（免疫清扫等）需要已绑定的数组
    if readonly_mode then return end            -- ★ 只读：不维持、不写
    maintain()
end

-- ============================================================================
-- 15. §3.1 方案 B + §2.3：聊天命令 /forge help|stat|check|export|import
-- ============================================================================
local function encode_cfg_value(key)
    local v = CFG[key]
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "number" then return tostring(to_ui(key, v)) end
    return tostring(v)
end

local function escape_token(s)
    return (tostring(s):gsub("[;|=%%]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- 设置串：forge:<slug>|<k>=<v>;…|#<sum>，sum = 全部字符字节和 % 65521（十六进制小写）
local function build_payload(all)
    local parts = {}
    local n_diff = 0
    for k, def in pairs(DEFAULTS) do
        local cur_ui = to_ui(k, CFG[k])
        local changed = (cur_ui ~= def)
        if changed then n_diff = n_diff + 1 end
        if all or changed then
            parts[#parts + 1] = k .. "=" .. escape_token(encode_cfg_value(k))
        end
    end
    table.sort(parts)
    local body = SLUG .. "|" .. table.concat(parts, ";")
    local sum = 0
    for i = 1, #body do sum = sum + body:byte(i) end
    local full = "forge:" .. body .. "|#" .. string.format("%x", sum % 65521)
    return full, n_diff
end

local function print_chunks(full)
    local head = 1
    local body = full
    local total = math.max(1, math.ceil(#body / CHUNK))
    local n = 0
    while head <= #body do
        local piece = body:sub(head, head + CHUNK - 1)
        head = head + CHUNK
        n = n + 1
        chat_print(string.format("[%d/%d] %s", n, total, piece))
    end
    if n == 0 then chat_print("[1/1] " .. body) end
    return n, total
end

cmd_export = function(rest)
    local all = tostring(rest):lower():find("all", 1, true) ~= nil
    local full, n_diff = build_payload(all)
    local n, total = print_chunks(full)
    chat_print(string.format("[%s] 已导出设置串：%d 片，共 %d 字符（%s）。导入侧直接 /forge import <串>。",
        SHORT, n, #full, all and "全部设置" or ("与默认值不同的 " .. n_diff .. " 项")))
    log_i("[" .. SHORT .. "] export: 片数=" .. total .. " 字符数=" .. #full)
end

cmd_import = function(rest)
    local body = tostring(rest or "")
    body = body:gsub("^%s+", ""):gsub("%s+$", "")
    if body == "" then
        chat_print("[" .. SHORT .. "] 用法：/forge import <设置串>（可用 /forge export 先导出）；/forge import reset 放弃已缓存的分片")
        return
    end
    if body:lower() == "reset" then
        shard_parts, shard_expect = {}, 0
        chat_print("[" .. SHORT .. "] 已放弃缓存的分片")
        return
    end
    -- 分片：[i/n] 正文
    local i, n, piece = body:match("^%[(%d+)%s*/%s*(%d+)%]%s*(.*)$")
    if i then
        i, n = tonumber(i), tonumber(n)
        if not n or n < 1 or n > 64 or not i or i < 1 or i > n then
            chat_print("[" .. SHORT .. "] 分片头非法：" .. tostring(body:sub(1, 24))); return
        end
        if shard_expect ~= n then shard_parts, shard_expect = {}, n end
        shard_parts[i] = piece
        local got = 0
        for j = 1, n do if shard_parts[j] then got = got + 1 end end
        if got < n then
            local miss = {}
            for j = 1, n do if not shard_parts[j] then miss[#miss + 1] = j end end
            chat_print(string.format("[%s] 已收到 %d/%d 片，缺第 %s 片", SHORT, got, n,
                table.concat(miss, ",")))
            return
        end
        local joined = table.concat(shard_parts, "")
        shard_parts, shard_expect = {}, 0
        cmd_import(joined)                      -- 拼好后当整串处理
        return
    end
    if not body:find("forge:", 1, true) then
        chat_print("[" .. SHORT .. "] 不是本模组的设置串（应以 forge: 开头）")
        return
    end
    apply_payload(body)
end

apply_payload = function(full)
    local slug, kvraw, sum = full:match("^forge:([^|]*)|([^|]*)|#(%x+)$")
    if not slug then
        chat_print("[" .. SHORT .. "] 设置串格式错误（应为 forge:<模组>|<k>=<v>;…|#<校验>）")
        return
    end
    if slug ~= SLUG then
        chat_print("[" .. SHORT .. "] 这不是药水叠加的设置串（串里的模组是「" .. tostring(slug) .. "」）")
        return
    end
    local want = 0
    local base = slug .. "|" .. kvraw
    for i = 1, #base do want = want + base:byte(i) end
    if string.format("%x", want % 65521) ~= sum:lower() then
        chat_print("[" .. SHORT .. "] 校验失败：设置串可能被截断或被改过（未应用任何设置）")
        return
    end

    local changes, ignored = {}, 0
    for pair in kvraw:gmatch("([^;]+)") do
        local k, v = pair:match("^([^=]+)=(.*)$")
        if not k or DEFAULTS[k] == nil then
            ignored = ignored + 1
        else
            local raw = unescape(v)
            local def = DEFAULTS[k]
            if type(def) == "boolean" then
                if raw == "true" or raw == "false" then changes[k] = raw end
            elseif type(def) == "string" then
                changes[k] = raw
            else
                local num = tonumber(raw)
                if num then changes[k] = tostring(math.floor(num)) end
            end
        end
    end
    if next(changes) == nil then
        chat_print("[" .. SHORT .. "] 串里没有本模组认得的设置项（忽略 " .. ignored .. " 项）")
        return
    end

    -- 就地改写 config.json：只替换该 key 的值，未知 key 与 schemaVersion 原样保留
    local raw_file = nil
    local ok_r, r = pcall(mod.read_file, "config.json")
    if ok_r and type(r) == "string" then raw_file = r end
    if not raw_file then
        chat_print("[" .. SHORT .. "] 读不到 config.json，未做任何改动")
        return
    end
    local new_raw, applied, added = raw_file, 0, 0
    for k, lit in pairs(changes) do
        local val = (type(DEFAULTS[k]) == "boolean" or type(DEFAULTS[k]) == "number")
            and lit or ('"' .. lit:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"')
        local kpat = '"' .. k:gsub("([^%w])", "%%%1") .. '"'
        local out, cnt = new_raw:gsub("(" .. kpat .. "%s*:%s*)([^,}]*)([,}])",
            function(pre, _, tail) return pre .. val .. tail end)
        if cnt > 0 then
            new_raw, applied = out, applied + cnt
        else
            -- ★ TEFManager 只把「玩家改过的项」写进 config.json，没改过的 key **根本不存在**。
            --   所以导入不能只做替换：不存在的 key 必须补写进 "values" 对象里。
            --   注意写法：gsub 的替换串里 `%1` 才是捕获组，直接拼 key/val 时不能带转义。
            -- 用 string.char(34) 拼引号：避免「替换串里的转义」和「Lua 字符串转义」两层打架
            local Q = string.char(34)
            local out2, cnt2 = new_raw:gsub('("values"%s*:%s*{)',
                "%1" .. Q .. k .. Q .. ":" .. val .. ",", 1)
            if cnt2 > 0 then new_raw, applied, added = out2, applied + 1, added + 1 end
        end
    end
    -- 补写后可能留下 ",}"/",}" 之类的尾逗号：JSON 不允许，必须清掉
    new_raw = new_raw:gsub(",%s*}", "}")
    if applied == 0 then
        chat_print("[" .. SHORT .. "] config.json 里没有可改写的 key（未改动）")
        return
    end
    local ok_w, wr = pcall(mod.write_file, "config.json", new_raw)
    if not ok_w or wr == false then
        chat_print("[" .. SHORT .. "] 写入 config.json 失败，未做任何改动")
        return
    end
    load_config()                                -- 立刻生效 + 重算派生数据（上限表 / 免疫表…）
    local extra = (ignored > 0) and ("，忽略 " .. ignored .. " 项未识别") or ""
    if added > 0 then extra = extra .. "，其中 " .. added .. " 项是新建的 key" end
    chat_print(string.format("[%s] 已导入 %d 项设置%s（模式：就地改写 config.json，立即生效）",
        SHORT, applied, extra))
    log_i("[" .. SHORT .. "] import: 应用 " .. applied .. " 项，忽略 " .. ignored .. " 项")
end

local function fmt_domain(d, slow_ms)
    local tag = (d.fields == "ok" and d.methods == "ok" and d.hooks == "ok") and "✅" or
        ((d.fields == "fail" and d.methods == "fail") and "❌" or "⚠")
    local avg = (d.calls > 0) and (d.ms / d.calls) or 0
    -- 用**峰值**判 SLOW：偶发一次卡顿也该被看见（且判定是确定性的）
    local slow = (d.max_ms > slow_ms) and " SLOW" or ""
    local s = string.format("  %s %s：句柄%s 钩子%s 调用 %d 命中 %d 错误 %d 平均 %.2fms 峰值 %.2fms%s",
        tag, d.name, tostring(d.fields), tostring(d.hooks), d.calls, d.hits, d.errs,
        avg, d.max_ms, slow)
    if d.last_err then s = s .. "\n      最近错误：" .. tostring(d.last_err) end
    return s
end

cmd_stat = function(rest)
    local slow_ms = CFG.diag_slow_ms
    if type(slow_ms) ~= "number" or slow_ms < 1 then slow_ms = 50 end
    chat_print(string.format("[%s] 诊断报告：v%s 路径=%s 槽位上限=%d netMode=%d 只读=%s 分帧=%d 帧",
        SHORT, tostring(mod.meta.version), hook_mode, cap, net_mode,
        tostring(readonly_mode), tick_interval()))
    chat_print(string.format("[%s] 叠加：黑名单 %d 项 / 免疫表 %d 项 / 单 buff 上限 %d 项 / 类别默认 %d 项 / 减益叠加=%s / 冷却倍率=%d%%",
        SHORT, (function() local n = 0 for _ in pairs(blacklist) do n = n + 1 end return n end)(),
        (function() local n = 0 for _ in pairs(immune_tab) do n = n + 1 end return n end)(),
        (function() local n = 0 for _ in pairs(per_limit_tab) do n = n + 1 end return n end)(),
        (function() local n = 0 for _ in pairs(cat_limit_tab) do n = n + 1 end return n end)(),
        tostring(CFG.stack_debuff), CFG.potion_delay_mult or 100))
    for _, d in ipairs(OP_US) do chat_print("[" .. SHORT .. "]" .. fmt_domain(d, slow_ms)) end
end

cmd_check = function(rest)
    chat_print("[" .. SHORT .. "] 重新自检（等同进世界首帧那次）")
    self_check_report()
end

cmd_help = function(rest)
    local cmds = {
        "/forge help — 显示这份命令表",
        "/forge stat — 诊断统计（每域 calls/hits/errs/最近错误/耗时，超阈值标 SLOW）",
        "/forge check — 重跑一次启动自检并播报",
        "/forge export [all] — 导出设置串（默认只导出与默认值不同的项）",
        "/forge import <串> — 导入设置串（支持 [i/n] 分片）",
        "/forge import reset — 放弃已缓存的分片",
    }
    chat_print("[" .. SHORT .. "] 命令表（" .. tostring(CFG.diag_report_cmd or "forge stat") .. " 等价于 /forge stat）：")
    for _, c in ipairs(cmds) do chat_print("  " .. c) end
end

-- 启动自检播报（§4.2）：每域一行、最多 12 行，超出折叠成一行统计
self_check_report = function()
    chat_print(string.format("[%s] 自检：v%s 路径=%s 槽位上限=%d netMode=%d 只读=%s（联机仅房主生效=%s）",
        SHORT, tostring(mod.meta.version), hook_mode, cap, net_mode, tostring(readonly_mode),
        tostring(CFG.host_only)))
    local shown = 0
    local ok_n = 0
    for _, d in ipairs(OP_US) do
        local ok = (d.fields == "ok" and d.methods == "ok" and d.hooks == "ok")
        if ok then ok_n = ok_n + 1 end
        if shown < 12 then
            shown = shown + 1
            local mark = ok and "✅" or ((d.fields == "fail" or d.methods == "fail") and "❌" or "⚠")
            chat_print(string.format("[%s] 域 %s：句柄%s 钩子%s 本帧命中 %d 次",
                SHORT, d.name, mark, (d.fields == "ok" and "✅") or d.fields,
                d.hits))
        end
    end
    if #OP_US > shown then
        chat_print(string.format("[%s] …其余 %d 个功能域已折叠（%d 个完好）；装 %d 个域，用 /forge stat 看全部明细",
            SHORT, #OP_US - shown, ok_n, #OP_US))
    end
end

-- 命令入口（大小写不敏感、前导 / 可省）。两种形状都接受：
--   ① `/forge import <串>`（标准写法）
--   ② `forge:<slug>|<k>=<v>;…|#<sum>` 或 `[i/n] forge:<slug>|…`（直接从聊天栏复制 export 输出）
local function handle_command(text)
    local s = tostring(text):gsub("^%s+", "")
    s = s:gsub("[\r\n]", " ")
    if s:sub(1, 1) == "/" then s = s:sub(2) end
    local head = s:match("^(%S+)")
    if not head then return end
    local lc = head:lower()
    if lc == "forge" or lc == SLUG then
        local rest = s:match("^%S+%s*(.*)$") or ""
        local sub, arg = rest:match("^(%S*)%s*(.*)$")
        sub = (sub or ""):lower()
        if sub == "help" or sub == "" then cmd_help(arg)
        elseif sub == "stat" or sub == "status" then cmd_stat(arg)
        elseif sub == "check" then cmd_check(arg)
        elseif sub == "export" then cmd_export(arg)
        elseif sub == "import" then cmd_import(arg)
        else
            chat_print("[" .. SHORT .. "] 不认识的子命令「" .. sub .. "」，用 /forge help 看命令表")
        end
        return
    end
    -- ② 直接贴 export 的输出（可能带 [i/n] 分片头：要把分片头**原样**交给 cmd_import，
    --    不能剥掉，否则每一片都会被当成一个完整的整串直接应用）
    if s:match("^%[%d+%s*/%s*%d+%]") or s:find("forge:", 1, true) == 1 then
        cmd_import(s)
    end
end

local function read_message_text(message)
    if not message then return nil end
    if M_get_text then
        local ok, s = pcall(P.invoke, M_get_text, message)
        if ok and s then
            local ok2, v = pcall(P.string_value, s)
            if ok2 and type(v) == "string" then return v end
        end
    end
    if F_msg_text then
        local ok, v = pcall(P.get_field_value, F_msg_text, message, "string")
        if ok and type(v) == "string" then return v end
    end
    return nil
end

local function on_process_incoming(instance, args, result)
    if not args then return end
    local message, client_id = args[1], args[2]
    local me = my_player_index()
    if me >= 0 and is_num(client_id) and math.floor(client_id) ~= me then return end
    local text = read_message_text(message)
    if text then
        DOM.cmd.calls = DOM.cmd.calls + 1
        handle_command(text)
    end
end

local function on_send_from_client(instance, args, result)
    if not args then return end
    local text = read_message_text(args[1])
    if text then
        DOM.cmd.calls = DOM.cmd.calls + 1
        handle_command(text)
    end
end

-- ============================================================================
-- 16. 安装 / 生命周期
-- ============================================================================
local function safe_hook(method, spec, label)
    if not method then
        log_e("[" .. SHORT .. "] 安装钩子失败(" .. label .. ")：方法句柄为空")
        return false
    end
    local ok, err = pcall(P.install_hook, method, spec)
    if not ok then
        log_e("[" .. SHORT .. "] 安装钩子失败(" .. label .. ")：" .. tostring(err))
        return false
    end
    return true
end

local function bootstrap()
    load_config()

    T_PLAYER = P.get_type("Terraria", "Player")
    if not T_PLAYER then
        log_e("[" .. SHORT .. "] 找不到 Terraria.Player，模组停用")
        return
    end
    T_MAIN = P.get_type("Terraria", "Main")
    T_LANG = P.get_type("Terraria", "Lang")
    T_CHAT_PROC = P.get_type("Terraria.Chat", "ChatCommandProcessor")
    T_CHAT_HELPER = P.get_type("Terraria.Chat", "ChatHelper")
    T_CHAT_MSG = P.get_type("Terraria.Chat", "ChatMessage")

    -- ---- 诊断域注册（§4.1，安装期一次性登记） ----
    DOM, OP_US = {}, {}
    add_domain("result",  "叠加核心")
    add_domain("rule",    "规则/优先级")
    add_domain("limits",  "上限表")
    add_domain("immune",  "免疫表")
    add_domain("potion",  "药水冷却")
    add_domain("perm",    "永久化")
    add_domain("persist", "死亡保留")
    add_domain("cmd",     "聊天命令")
    add_domain("selfchk", "启动自检")
    parse_entry_lists()          -- 现在 DOM 有了，解析失败才能记进诊断域

    F_buff_type = find_field(T_PLAYER, "buffType")
    F_buff_time = find_field(T_PLAYER, "buffTime")
    F_who_am_i  = find_field(T_PLAYER, "whoAmI")
    F_max_buffs = find_field(T_PLAYER, "maxBuffs")
    F_buff_immune = find_field(T_PLAYER, "buffImmune")
    F_potion_delay = find_field(T_PLAYER, "potionDelay")
    if not F_potion_delay then
        DOM.potion.fields = "fail"
        DOM.potion.methods = "fail"
    end
    if not (F_buff_type and F_buff_time) then
        log_e("[" .. SHORT .. "] 找不到 Player.buffType / buffTime，模组停用")
        return
    end
    if not (F_who_am_i and F_buff_immune) then
        log_w("[" .. SHORT .. "] 找不到 Player.whoAmI / buffImmune，本机判定与免疫判断会退化（叠加本身可用）")
    end
    DOM.result.fields = (F_buff_type and F_buff_time and F_who_am_i and F_buff_immune) and "ok" or "partial"

    if T_MAIN then
        F_m_debuff     = P.get_field(T_MAIN, "debuff")
        F_m_light_pet  = P.get_field(T_MAIN, "lightPet")
        F_m_vanity_pet = P.get_field(T_MAIN, "vanityPet")
        F_m_melee_buff = P.get_field(T_MAIN, "meleeBuff")
        F_m_persistent = P.get_field(T_MAIN, "persistentBuff")
        F_m_net_mode   = P.get_field(T_MAIN, "netMode")      -- static int 字段（非属性、非 const）
        -- ★ myPlayer / gameMenu 都是**属性**（无后备字段）：一律不用 get_field，只走 getter
        M_get_my_player = resolve_prop(T_MAIN, "myPlayer", "get_myPlayer")
        M_get_game_menu = resolve_prop(T_MAIN, "gameMenu", "get_gameMenu")
        M_new_text, new_text_args = resolve_new_text()
        if not M_new_text then
            log_w("[" .. SHORT .. "] 取不到可安全调用的 Main.NewText，聊天栏播报不可用（叠加本身不受影响）")
        end
        if not F_m_net_mode then
            log_w("[" .. SHORT .. "] 取不到 Main.netMode，联机限制无法生效（退化为「不限制」）")
        end
    else
        log_w("[" .. SHORT .. "] 找不到 Terraria.Main，类别判定会退化为「其他」，死亡保留不可用")
    end
    if not M_get_game_menu then
        log_w("[" .. SHORT .. "] 取不到 Main.gameMenu（属性 get_gameMenu），进世界门控退化为「每次会话播报一次」")
    end

    if T_LANG then
        local m = P.get_method(T_LANG, "GetBuffName", 1)
        if not m then m = P.get_method(T_LANG, "GetBuffName") end
        if m and P.method_param_count then
            local ok_n, n = pcall(P.method_param_count, m)
            if not ok_n or n ~= 1 then m = nil end
        end
        M_get_buff_name = m
    end
    -- ★ 名字类条目（上限表 / 免疫表里按名字写的）现在才能解析：句柄一就位就无条件重解析一次
    --   （load_config 里那一遍 M_get_buff_name 必定是 nil，按名字写的条目全被跳过了）
    parse_entry_lists(false)

    M_reset_effects = P.get_method(T_PLAYER, "ResetEffects", 0)
        or P.get_method(T_PLAYER, "ResetEffects")
    -- 主路径：私有方法（源码核实：AddBuff 内部就是调它来判断「已经有了」）
    M_try_update = P.get_method(T_PLAYER, "AddBuff_TryUpdatingExistingBuffTime", 2)
        or P.get_method(T_PLAYER, "AddBuff_TryUpdatingExistingBuffTime")
    -- 兜底路径：TSV 核实 1.4.5.8 手机版是 AddBuff(int type, int time, bool fromNetPvP) = 3 参
    M_add_buff = P.get_method(T_PLAYER, "AddBuff", 3)
        or P.get_method(T_PLAYER, "AddBuff")
    -- §4.5-⑤ 免疫表 / §4.5-④ 药水冷却：显式 1 参重载（DelBuff 在手机版还有别的重载）
    M_del_buff = P.get_method(T_PLAYER, "DelBuff", 1)
    M_clear_buff = P.get_method(T_PLAYER, "ClearBuff", 1)
        or P.get_method(T_PLAYER, "ClearBuff")

    -- 聊天命令（§2.1）：postfix × 2，两个都装，任一生效即可用
    local hook_cmd = false
    if T_CHAT_PROC then
        local m = P.get_method(T_CHAT_PROC, "ProcessIncomingMessage", 2)
            or P.get_method(T_CHAT_PROC, "ProcessIncomingMessage")
        hook_cmd = safe_hook(m, { postfix = on_process_incoming }, "ChatCommandProcessor.ProcessIncomingMessage")
    end
    if T_CHAT_HELPER then
        local m = P.get_method(T_CHAT_HELPER, "SendChatMessageFromClient", 1)
            or P.get_method(T_CHAT_HELPER, "SendChatMessageFromClient")
        local ok2 = safe_hook(m, { postfix = on_send_from_client }, "ChatHelper.SendChatMessageFromClient")
        hook_cmd = hook_cmd or ok2
    end
    if T_CHAT_MSG then
        M_get_text = P.get_method(T_CHAT_MSG, "get_Text", 0)
            or P.get_method(T_CHAT_MSG, "get_Text")
        F_msg_text = P.get_field(T_CHAT_MSG, "<Text>k__BackingField")
    end
    if M_get_text and P.method_param_count then
        local ok_n, n = pcall(P.method_param_count, M_get_text)
        if not ok_n or n ~= 0 then M_get_text = nil end
    end
    DOM.cmd.fields = (T_CHAT_MSG and (M_get_text or F_msg_text)) and "ok" or "fail"
    DOM.cmd.methods = (T_CHAT_PROC or T_CHAT_HELPER) and "ok" or "fail"
    DOM.cmd.hooks = hook_cmd and "ok" or "fail"
    if not hook_cmd then
        log_w("[" .. SHORT .. "] 聊天命令钩子都没装上，/forge 系列命令不可用")
    end

    st_fields(DOM.result, F_buff_type and F_buff_time)
    st_methods(DOM.result, M_reset_effects and (M_try_update or M_add_buff))
    DOM.result.hits = 1

    if not safe_hook(M_reset_effects, { postfix = on_reset_effects }, "Player.ResetEffects") then
        st_hook(DOM.result, false)
        log_e("[" .. SHORT .. "] 每帧维持钩子装不上，模组停用")
        return
    end
    st_hook(DOM.result, true)

    -- ★ 两条路径**同时安装**（互相协调，实际只结算一次）
    local ok_helper = false
    if M_try_update then
        ok_helper = safe_hook(M_try_update, { prefix = on_try_update },
            "Player.AddBuff_TryUpdatingExistingBuffTime")
    end
    local ok_add = false
    if M_add_buff then
        ok_add = safe_hook(M_add_buff,
            { prefix = on_add_buff_pre, postfix = on_add_buff_post }, "Player.AddBuff")
    end
    if ok_helper and ok_add then
        hook_mode = "dual"
    elseif ok_helper then
        hook_mode = "helper"
    elseif ok_add then
        hook_mode = "addbuff"
        log_w("[" .. SHORT .. "] 主路径符号缺失，已回退到 Player.AddBuff 前后缀（专家模式下减益时长可能少算倍率）")
    else
        log_e("[" .. SHORT .. "] 两条叠加路径都装不上，模组停用")
        return
    end

    -- §4.5-⑤ 免疫表：还需要「每帧清扫」那条路才完整（打勾状态由 hook 决定）
    local ok_del = false
    if M_del_buff then
        ok_del = safe_hook(M_del_buff, { postfix = on_del_buff }, "Player.DelBuff")
    end
    DOM.immune.fields = F_buff_immune and "ok" or "fail"
    DOM.immune.methods = (M_clear_buff or M_add_buff) and "ok" or "fail"
    DOM.immune.hooks = (ok_add and (M_clear_buff or M_del_buff)) and "ok" or "partial"
    if not M_clear_buff then
        DOM.immune.last_err = "取不到 ClearBuff(int)：改用「置零 + 照抄原版压缩逻辑」的等价实现"
    end
    DOM.potion.fields = F_potion_delay and "ok" or "fail"
    DOM.potion.methods = M_del_buff and "ok" or "partial"
    DOM.potion.hooks = (ok_add and ok_del) and "ok" or "partial"

    st_fields(DOM.perm, F_buff_time and F_buff_type)
    st_methods(DOM.perm, M_reset_effects)
    st_hook(DOM.perm, true)
    DOM.persist.fields = F_m_persistent and "ok" or "fail"
    DOM.persist.orig = {}       -- persist_all_on_death 的原值快照（关掉开关时还原用）

    cap = read_max_buffs() or CAP_FALLBACK
    ready = true
    -- 日志里的数字都是内部值：永久阈值 0 = 关闭（设置页显示 1）
    log_i(string.format(
        "[%s] v%s 已启用：路径=%s，只保留时间叠加，槽位上限=%d，永久阈值=%d 秒，非关键项刷新间隔=%d 帧，自动重读=%d 秒，自检=%s，冷却倍率=%d%%",
        SHORT, tostring(mod.meta.version), hook_mode, cap, CFG.perm_threshold_sec,
        tick_interval(), CFG.config_reload_sec, tostring(CFG.self_check),
        CFG.potion_delay_mult or 100))
end

-- ---------------------------------------------------------------------------
-- 15b. 面板 API（gui.lua 只认这张表；面板只改运行时状态，不写 TEFManager 设置）
-- ---------------------------------------------------------------------------
bs_api = {
    defaults = DEFAULTS, limits = LIMITS, choices = CHOICES,
    get = function(k) return CFG[k] end,
    -- ★ v2.3.2：面板「默认」键用。DEFAULTS 存的是 UI 值，CFG 存内部值，
    --   这里做一次 to_internal，避免 86400 被当内部值写成 86399。
    default_ui = function(k) return to_internal(k, DEFAULTS[k]) end,
    panel_bounds = function(k)
        local lim = LIMITS[k]
        if not lim then return 0, 1000000 end
        local off = UI_OFFSET[k]
        if off then return 0, lim[2] - off end
        return lim[1], lim[2]
    end,
    set = function(k, v)
        local def = DEFAULTS[k]
        if def == nil then return false end
        if type(def) == "boolean" then
            if v ~= true and v ~= false then return false end
            CFG[k] = v
        elseif type(def) == "string" then
            local sv = tostring(v or "")
            if #sv > 500 then sv = sv:sub(1, 500) end
            CFG[k] = sv
        else
            local n = tonumber(v)
            if not n or n ~= n or n == math.huge or n == -math.huge then return false end
            -- ★ v2.3.0+：面板数字框自由输入，不再按 LIMITS 夹取；
            --   LIMITS 只用于设置页声明、滑块范围和显示提示。
            CFG[k] = math.floor(n)
        end
        bs_state.override[k] = CFG[k]
        if k == "blacklist_ids" or k:match("^blacklist_%d+$") or k:match("^allow_%d+$") then
            rebuild_id_sets()
        elseif k == "per_buff_limits" or k == "per_buff_cat_limits" or k == "immune_buffs"
            or k == "potion_delay_mult" or k == "max_time_sec" then
            recompute_derived()
        end
        return true
    end,
    action = function(what) bs_state.pending = tostring(what) end,
    refresh_snapshot = function() bs_state.need_snap = true end,
    stats = function()
        return {
            cap = cap, tick = tick, hook_mode = hook_mode, readonly = readonly_mode,
            net_mode = net_mode, buff_count = #bs_state.buffs, snap_tick = bs_state.snap_tick,
        }
    end,
    buffs = function() return bs_state.buffs end,
    ignored = function(id) return bs_state.ignore[id] == true end,
    limit_seconds = function(id) return limit_seconds_of(id, category_of(id)) end,
    logs = function() return bs_state.logs end,
    domain_errors = function()
        local n, last = 0, nil
        for _, d in ipairs(OP_US) do
            n = n + (d.errs or 0)
            if d.last_err then last = d.name .. "：" .. tostring(d.last_err) end
        end
        return n, last
    end,
}

function setup()
    if GUI_MOD then GUI_MOD.init(mod, bs_api) end  -- 只绑定，不调用任何游戏方法
    IN_SETUP = true                             -- 只放行「符号取不到」这类一次性诊断
    local ok, err = pcall(bootstrap)
    if not ok then log_e("[" .. SHORT .. "] setup() 出错，模组未完整装载：" .. tostring(err)) end
    IN_SETUP = false
end

function cleanup()
    ready = false
    tick = 0
    cap = CAP_FALLBACK
    cap_locked = false
    arr_type, arr_time = nil, nil
    statics, stat_missing = {}, {}
    keep_set, name_cache, announce_last, log_once_seen = {}, {}, {}, {}
    cat_cache = {}
    blacklist, allowlist, bl_slot, al_slot = {}, {}, {}, {}
    per_limit_tab, cat_limit_tab, immune_tab = {}, {}, {}
    layer_count = {}
    pending = nil
    add_scope = 0
    helper_hit = false
    immune_hit = false
    self_scaled = false
    in_world_prev = false
    shard_parts, shard_expect = {}, 0
    fallback_player = -1
    cached_my_player = -1
    net_mode = -1
    net_ready = false
    readonly_mode = false
    bs_state.buffs, bs_state.logs, bs_state.pending, bs_state.need_snap = {}, {}, nil, false
    bs_state.extra, bs_state.override, bs_state.snap_tick = {}, {}, 0
    bs_state.panel_seen = false
    if GUI_MOD and GUI_MOD.reset then GUI_MOD.reset() end
end

-- 19 章 §1.3-1：入口必须写 mod.on_gui（全局 on_gui 不会被调用）。
mod.on_gui = function()
    if CFG.gui_enable ~= true then return end      -- 自救：在 TEFManager 设置页开回来
    if not bs_state.panel_seen then
        bs_state.panel_seen = true                 -- 从这一帧起才维护时间轴快照
        bs_state.need_snap = true
    end
    if GUI_MOD then GUI_MOD.on_gui() end
end

todo_list = { "setup" }
