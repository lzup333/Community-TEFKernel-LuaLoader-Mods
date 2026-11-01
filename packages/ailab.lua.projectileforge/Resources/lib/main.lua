-- ============================================================================
-- 弹幕工坊 (ProjectileForge)  v2.2.1     pkg_id = ailab.lua.projectileforge
-- 适用: Terraria Mobile 1.4.5.8 + TEFKernel + LuaLoader 1.6.3
--
-- 本 Mod 是一个独立的新 Mod，与「多倍弹幕(MultiProjectile)」没有任何依赖或
-- 覆盖关系：后者可以照常安装、同时启用。本 Mod 把「多重射击」扩展成一座可调的
-- 弹幕工坊，全部行为都由 TEFManager → 模组设置 里的滑块/开关驱动。
--
-- ★★ 未经实机验证：本工作区无法启动游戏。以下全部结论都是**静态分析**产物
--    （官方 1.4.5.8 手机版元数据 + PC 逻辑源码 + 假内核逻辑测试）。
--    交付文案与 README 一律写「未经实机验证」，不写「已测试可用」。
--
-- ============================================================================
-- v2.1.0 主要变更
-- ----------------------------------------------------------------------------
-- 【B3 修复：过滤方式与名单可读性】
--   · filter_mode 由 INTEGER(1..3) 改 CHOICE：不过滤 / 白名单 / 黑名单，默认黑名单。
--   · filter_id_1..4 / weapon_id_1..4 由「UI = 真实 ID + 1」的整数槽位改 STRING：
--     逗号分隔的真实 ProjectileID / ItemID；空串 = 不使用。
--     过滤名单默认 "31,67,71,179"（沙块/珍珠沙/泥沙/雪泥下落），武器名单默认 ""。
--   · 兼容旧配置：读到 number 时按旧语义迁移（v <= 1 = 空槽，否则 id = v - 1），
--     所以旧默认 32/68/72/180 会变成 31/67/71/179，绝不把 32 当真实 ID。
--   · 名单为空 = 不使用：白/黑名单都不拦任何弹幕（空串不误伤）。
--
-- 【图形面板：5 页，面板零反射】
--   · mod.on_gui：状态 / 参数 / 弹幕表 / 一键 / 关于；gui_enable + gui_layout。
--   · 面板里没有一处 patch.* / get_field_value / invoke：状态页读内部计数器，
--     弹幕表只读 §7.1 的 obs 聚合值（只在第 3 页打开时采集，2 秒后自动停）。
--   · 数值项一律纯数字输入（input_text + 确定/取消），不夹取；设置页仍按 Info.json 夹取。
--   · 老加载器没有 begin_scroll/end_scroll → 自动回落分页，并在标题下写一行说明。
--
-- ============================================================================
-- v2.0.0 主要变更（对应 下一版-开发提示词.md §3.7 / §4.4 / §3.2 / §3.1-B / §4.6）
-- ----------------------------------------------------------------------------
-- 【§3.7 追踪性能重构，9 条全做】
--   ① 对象做 Lua table key → 改用**整数下标**。手机版 Projectile 没有 identity
--      字段（官方字段表里搜不到；参考库旧 C++ 模组用的是 identity，那一代与现加载器
--      的元数据不同），可用的是 Terraria.Entity.whoAmI（int, public, 非 const,
--      偏移 0x10；字段表 17958 行，Projectile 继承 Entity）。本文件所有以弹幕为键的
--      缓存一律改成 whoAmI 整数下标（Lua 数组部分：无哈希、无对象引用、无 GC 压力），
--      也不再往表里存游戏对象（NPC 只存数组下标 + 快照，避免悬垂句柄）。
--   ② 全局共享候选目标表：每 global_scan_interval 帧只扫一次 Main.npc，筛出可追踪
--      目标 → 按「距最近玩家」裁剪（近的必留 + 最近的 K 个）+ 网格分桶，所有弹幕
--      共享这张小表；每枚弹幕的索敌退化成「查网格」，不再各自全表扫 Main.npc。
--   ③ is_targetable 的 6+ 次反射读 → 合成一次 NPC.CanBeChasedBy(object,bool)
--      （手机版有：方法表 10218 行，2 形参）；取不到句柄时回退到常量字段句柄缓存
--      + 第一行先读 active 早退 的精简版。
--   ④ netUpdate 只在「朝向变化超过 net_angle_deg 度」且「距上次同步 ≥
--      net_update_min_frames 帧」时置位；另有 net_sync 开关（关 = 完全不写网络字段）。
--   ⑤ 热路径去掉 pcall：每帧的字段读写一律直接调用（只在安装期/生成副本/聊天文本
--      兜底/配置读写这些非逐帧路径保留 pcall）。前提是写入字段的类型都已在官方字段表
--      逐项核对过（bool/int32/float/Vector2），不存在类型不匹配。
--   ⑥ 原 tracked_count() 的 pairs 遍历 → 维护 tracked_n 计数器。该函数已**删除**：
--      名额判定变成 1 次整数比较，失效名额由非关键桶惰性压缩（见 housekeeping）。
--   ⑦ 动态扫描间隔：每枚弹幕缓存 lastScanFrame + 由速度决定的 scanInterval
--      （速度越快扫得越勤；慢的/静止的拉长到基础间隔的 2 倍，快的缩到 1/4）。
--      Main.npc（我方弹幕追 NPC）用 track_interval、Main.player（敌方弹幕追玩家）
--      用 enemy_track_interval，两者分开设置。
--   ⑧ 早退链：开关关闭（零反射）→ 帧间隔闸门 → active → friendly/hostile 不匹配
--      → 速度 < 0.5 像素/帧 → 离屏代理 → 索敌半径外，逐层第一行就退出。
--   ⑨ MAX_TRACKED(60) 保留，且超限时优先服务玩家自己的弹幕：自己的弹幕可以踢掉一个
--      「非自己」的追踪名额（带游标，O(1) 摊销）。
--   · 转向强度仍按间隔做等效复合补偿 1-(1-turn)^interval（interval=1 与逐帧完全一致）；
--     默认参数下手感不变、只是更快，反射调用量级下降两三个数量级。
--   · perf_mode（CHOICE：性能优先 / 手感优先）：**同一份代码**，只换参数。
--     性能优先（默认）= 全局共享候选表 + 动态间隔 + 候选裁剪到 K 个；
--     手感优先 = 全局扫描频率提高 4 倍、间隔上限收紧到基础值、候选裁剪放宽。
--     默认档「性能优先」，且默认不影响原版弹幕行为（homing_enabled 默认关）。
--
-- 【§4.4 新增（全部默认关闭 / 默认等于原版）】
--   ② homing_priority（CHOICE：最近 / Boss优先 / 血量最高 / 混合）：混合档照
--      homing-projectile 的优先级链 —— Boss > 精英(rarity>=1) > 距离更近 > lifeMax 更高。
--   ③ 追踪曲线：homing_flight_frames（只在飞行前 N 帧追踪）、homing_ramp（强度随飞行
--      时间从 0 线性升到 100%）、homing_stop_distance（到目标这么近就停手；未设置时
--      保留原版 24 像素死区，手感不变）。
--   ④ 命中效果：hit_split_copies（命中分裂）、hit_explosion_radius + 伤害倍率、
--      hit_lifesteal_percent（吸血）、hit_lightning_chain + 伤害倍率 + 半径（闪电连锁）。
--      命中判定用 Projectile.numHits（int, 0x54）的增量，不新增钩子。
--   ⑤ 弹幕物理组：physics_no_gravity（锁成出生速度的绝对直线 = 同时消掉重力与阻力）、
--      physics_pass_wall（tileCollide=false 穿墙）、physics_bounce_limit（反弹次数上限，
--      超限回收）、physics_orbit_percent（绕目标环绕）、physics_return_home（归位）。
--   ⑥ 伤害细节：copy_full_damage（每份副本满伤害）、crit_transfer + crit_bonus
--      （暴击传递：把源弹幕的 bonusCritChance 传给副本/分裂/连锁）、
--      ignore_npc_immunity + local_immunity_frames（无敌帧穿透，走
--      usesLocalNPCImmunity / localNPCHitCooldown）。
--   ⑦ 安全阀：global_projectile_cap（全局弹幕上限 + 只回收本模组生成的副本）+
--      max_copies_per_frame（每帧最多新增副本数）+ 保留下落沙类黑名单。
--   ⑧ 网络节流：见 ④；net_sync 默认开（保持原版语义），关掉后一个网络字段都不写。
--   ⑨ weapon_filter_mode + weapon_id_1..4（按发射武器的物品 ID 白/黑名单，与属性工坊
--      §4.3-3 同一语义；取不到武器时按「不限制」放行并计入诊断）。
--   · 可自测指标：聊天栏 /forge perf 与 /forge stat 打印
--     「本帧扫描次数 / 命中弹幕数 / 平均耗时」。
--
-- 【§3.1 方案 B + §4.6 全套（严格照抄 开发文档/12-下一版通用约定.md §2/§3/§4）】
--   · /forge help|stat|check|export [all]|import <串>|import reset|perf
--   · 设置串 forge:<slug>|<k>=<v>;…|#<sum>（sum = 字节和 % 65521，十六进制小写），
--     每片 ≤320 字符并带 [i/n] 前缀；导入侧按片暂存、齐了才校验并应用。
--   · 诊断域注册表 domains[]：安装期一次写 fields/methods/hooks，运行期只自增
--     calls/hits（热路径直接 d.hits = d.hits + 1，不调函数）。self_check（默认开）
--     进世界首帧播报一次，每域一行；/forge check 可随时重播。
--
-- 【§3.2 倍率上限 10000】
--   · 倍率/百分比类上限一律 10000（=100 倍），默认仍 100（=1 倍）。
--   · 非倍率类（秒/帧/点/格/数量/次数/等级）上限保持原样，没有一起放大。
--   · Info.json 的 min/max、本文件的 DEFAULTS/LIMITS、读取时的双向夹取三处一致
--     （build_mod.py 会逐项比对）。
--   · 游戏对很多数值有硬性夹取，滑块调高未必有效果。
--
-- v1.1.0 保留项：host_only / tick_interval / config_reload_sec / write_log / debug_log /
--   scope_other / track_interval + 追踪硬性限制 / 默认黑名单（下落沙类 31 沙块下落、
--   67 珍珠沙块下落、71 泥沙块、179 雪泥块；来源 = 1.4.5.8 手机版 dump.cs 的
--   ProjectileID 枚举。这类弹幕落地会立刻变成图格，复制会重复物理结算，可能严重卡顿
--   甚至崩游戏，所以默认排除）。
-- v1.0.3：副本不再与已有弹幕重叠（切向分布不取 0 角 + 出生位置沿各自方向错开）。
-- v1.0.2：设置项改成「UI 值从 1 起算」（TEFManager 的整数滑块最小值是 1）。
-- v1.0.1：移除了聊天子系统（v1.0.0 一进游戏 SIGABRT）。v2.0.0 按 §4.6 / §3.1-B 的
--   要求重新引入聊天命令，但做了三条针对性加固（见 §16 注释）：
--     ① 只取两个已在旧崩溃日志里被证明「装成功过」的方法装钩子，不碰别的聊天符号；
--     ② 聊天文本只从 SayChatCommand.ProcessIncomingMessage(string,byte) 的 prefix 读，
--        **绝不反射 Terraria.Chat 的消息对象类型**（v1.0.0 就是在装载期反射它，紧接着
--        SIGABRT ×3）；
--     ③ 所有聊天输出都只发生在游戏内（收到命令 / 进世界首帧播报），setup() 阶段
--        绝不调用 Main.NewText（§5.1 的根因 A）。
--
-- 实现要点（照抄工作区内已验证的写法）：
--   * Hook Projectile.NewProjectile 的 postfix，result 是新弹幕下标；副本用「克隆整份
--     实参 + 生成后按字段精确改写」创建，回放前用 method_param_count 核对实参个数。
--   * Hook Projectile.AI 的 postfix 做逐帧工作，全部功能默认关闭；全关时每帧只做几次
--     布尔判断，一次反射调用都没有。
--   * 所有句柄解析、Hook 安装、回调体都在判空/失败分支保护之下，任何一步失败都只是
--     功能不生效，不影响游戏本体运行。
-- ============================================================================

mod.meta = { pkg_id = "ailab.lua.projectileforge", version = "2.2.3" }

local patch = mod.patch
local unpack = table.unpack or unpack

-- ============================================================================
-- 0. 常量（符号与编号都先在 1.4.5.8 手机版元数据里核对过）
--    ★ Main.maxProjectiles / Main.maxNPCs 在手机版是 const 字段（字段表 14881/14882
--      行，const=是）→ 绝不能读（读出来是 nil）；它们的值在字段表「默认值」列：
--      maxProjectiles = 1000、maxNPCs = 200，这里直接抄常数当数组上限兜底。
-- ============================================================================
local K = {
    -- 默认黑名单：下落沙类弹幕（来源 = 手机版 dump.cs 的 ProjectileID 枚举）
    ID_SAND_BALL_FALLING  = 31,     -- SandBallFalling      （沙块下落）
    ID_PEARL_SAND_FALLING = 67,     -- PearlSandBallFalling （珍珠沙块下落）
    ID_SILT_BALL          = 71,     -- SiltBall             （泥沙块下落）
    ID_SLUSH_BALL         = 179,    -- SlushBall            （雪泥块下落）
    MAX_PROJ_SLOTS        = 1000,   -- Main.maxProjectiles（const，抄字段表默认值）
    -- v2.2.0：候选表刷新周期的别名（与本项同义，不新增重复设置）
    NPC_LIST_REFRESH_ALIAS = "npc_list_refresh_interval",
    -- C 快通道偏移：全部取自 参考库/符号/官方源码-字段.tsv 的「偏移」列
    --   Entity.position=0x14 / Entity.velocity=0x1C / Projectile.type=0x64 / active=0x49
    --   相对 position 字段指针的偏移 = 0x00 / 0x08 / 0x50 / 0x35。
    FAST_POS_REL    = 0x00,
    FAST_VEL_REL    = 0x08,
    FAST_TYPE_REL   = 0x50,
    FAST_ACTIVE_REL = 0x35,
    FAST_READ_LEN   = 0x54,
    MAX_NPC_SLOTS         = 200,    -- Main.maxNPCs（const，抄字段表默认值）
    MAX_TRACKED           = 60,     -- 同时追踪的弹幕数硬上限
    MAX_CHAIN_TOTAL       = 100000, -- 单次分裂链总量保护（只防死循环/内存爆炸）
    MAX_CANDIDATES        = 96,     -- 全局共享候选表硬上限
    FIELD_LOOKUP_DEPTH    = 16,     -- 沿父类链找字段的最大层数
    DEFAULT_RELOAD_SEC    = 5,      -- config_reload_sec 读不到时的兜底秒数
    MIN_TRACK_SPEED       = 0.5,    -- 速度阈值（像素/帧），低于它不追踪（沿用 v1.1.0）
    STOP_DISTANCE_MIN     = 24,     -- 近距离停手死区（v1.1.0 固定值，保留 → 手感不变）
    OFFSCREEN_DISTANCE    = 2600,   -- 「离屏」代理阈值（像素）。Main.screenPosition 是
                                    -- Vector2 属性（字段表 15373 行）→ 本代读不到结构体
                                    -- 属性返回值，这里用「离玩家距离」做代理判定。
    PRUNE_RADIUS_MULT     = 3,      -- 候选裁剪：距玩家 N×索敌半径内的 NPC 无条件保留
    DYNAMIC_SPEED_REF     = 8,      -- 动态扫描间隔的速度参考点（像素/帧）
    INTERVAL_MIN_DIV      = 4,      -- 动态间隔最快缩到基础值的 1/4
    TARGET_GRACE_SCANS    = 3,      -- 目标连续缺席多少次扫描才放弃（× 全局扫描间隔）
    HIT_PER_FRAME_MAX     = 8,      -- 每帧最多处理多少次「命中效果」
    SMALL_MAX_HITS        = 200,    -- 单枚弹幕一生最多触发多少次命中效果
    -- 索敌策略内部编号（CHOICE 字符串 → 数字，热路径只比较数字）
    PRI_NEAREST = 1, PRI_BOSS = 2, PRI_HP = 3, PRI_MIXED = 4,
    -- 武器过滤内部编号
    WEAPON_ANY = 0, WEAPON_WHITE = 1, WEAPON_BLACK = 2,
    -- 性能档内部编号
    PERF_FAST = 1, PERF_FEEL = 2,
    -- 动态间隔的上下限系数（相对基础间隔）
    INTERVAL_MAX_MULT = 2,
    -- 网格键：key = (kx + OFF) * SPAN + (ky + OFF)。世界坐标 ±8400、格子 ≥64 像素，
    -- 所以 kx/ky 落在 ±132 内，OFF/SPAN 取 4096/8192 足够，且 32 位内精确表示。
    CELL_OFF = 4096, CELL_SPAN = 8192,
}

-- ============================================================================
-- 1. 默认值（必须与 Info.json 里每项 settings 的 defaultValue 完全一致）
--    TEFManager 没写配置 / 配置缺项时用这里的值兜底。
--    ★ 这里与 LIMITS 存的都是「UI 值」= Info.json 里 min/max/defaultValue 的那套
--      （整数滑块从 1 起算，因为 TEFManager 的最小值是 1）；
--      真正生效的内部值由 UI_OFFSET / CHOICE 映射得到（见下）。
-- ============================================================================
local DEFAULTS = {
    -- A. 作用范围与类型过滤
    enabled                = true,
    affect_player_shots    = true,
    affect_enemy_shots     = false,
    affect_minions         = false,
    affect_sentries        = false,
    affect_hooks           = false,
    affect_bobbers         = false,
    scope_other            = true,
    filter_mode            = "黑名单",
    filter_id_1            = "31,67,71,179",   -- 真实 ProjectileID：沙块/珍珠沙/泥沙/雪泥下落
    filter_id_2            = "",
    filter_id_3            = "",
    filter_id_4            = "",
    -- B. 多重射击
    extra_copies           = 5,
    spread_mode            = 1,
    spread_angle_deg       = 31,
    trigger_chance_percent = 100,
    chain_depth            = 1,
    max_copies_per_second  = 100,
    max_copies_per_frame   = 100,
    copy_velocity_percent  = 100,
    copy_damage_percent    = 101,
    copy_full_damage       = false,
    skip_stationary        = true,
    -- C. 属性改写
    damage_percent         = 100,
    knockback_percent      = 101,
    velocity_percent       = 100,
    scale_percent          = 100,
    lifetime_percent       = 100,
    pierce_bonus           = 1,
    lock_scale             = false,
    lock_pierce            = false,
    apply_overrides_to_copies = true,
    crit_transfer          = false,
    crit_bonus             = 1,
    -- C2. 无敌帧（§4.4-6）
    ignore_npc_immunity    = false,
    local_immunity_frames  = 10,
    -- D. 追踪机制
    homing_enabled         = false,
    perf_mode              = "性能优先",
    homing_priority        = "最近",
    homing_strength        = 18,
    homing_range           = 1500,
    track_interval         = 6,
    enemy_track_interval   = 10,
    global_scan_interval   = 20,
    homing_flight_frames   = 1,
    homing_ramp            = false,
    homing_stop_distance   = 1,
    -- D2. 命中效果（§4.4-4）
    hit_split_copies       = 1,
    hit_explosion_radius   = 1,
    hit_explosion_damage_percent = 50,
    hit_lifesteal_percent  = 1,
    hit_lightning_chain    = 1,
    hit_lightning_damage_percent = 50,
    hit_lightning_radius   = 400,
    -- D3. 弹幕物理组（§4.4-5）
    physics_no_gravity     = false,
    physics_pass_wall      = false,
    physics_bounce_limit   = 1,
    physics_orbit_percent  = 1,
    physics_return_home    = false,
    -- D4. 网络节流（§4.4-8）
    net_sync               = true,
    net_update_min_frames  = 10,
    net_angle_deg          = 15,
    -- D5. 按武器 ID 白/黑名单（§4.4-9）
    weapon_filter_mode     = "不过滤",
    weapon_id_1            = "",
    weapon_id_2            = "",
    weapon_id_3            = "",
    weapon_id_4            = "",
    -- D6. 安全阀（§4.4-7）
    global_projectile_cap  = 1000,
    -- D7. v2.2.0 性能 / 预算 / 实验（全部默认关闭或等价旧行为）
    max_checks_per_frame    = 0,       -- 0 = 不限
    adaptive_frame_skip     = false,
    adaptive_unit           = 200,
    target_switch_cooldown  = 30,      -- 0 = 不限制
    speed_override_interval = 1,       -- 1 = 每帧（旧行为）
    global_shot_budget      = 0,       -- 0 = 不限
    use_fastpath            = false,   -- 实验：默认关，自检失败自动关
    -- E. 总控（本批统一；5 个模组语义一致）+ §4.6 诊断三项
    self_check             = true,
    diag_report_cmd        = "forge stat",
    diag_slow_ms           = 50,
    -- E2. §9 聊天安全（v2.0.0 整改）
    chat_cmd               = false,    -- 聊天指令总开关：默认关闭 = 不碰任何 Chat 类型、不装钩子
    import_string          = "",       -- 默认（零聊天依赖）导入通道：粘贴设置串
    host_only              = true,
    tick_interval          = 10,
    config_reload_sec      = 5,
    write_log              = false,
    debug_log              = false,
    -- F. 图形面板（v2.1.0）
    gui_enable             = true,
    gui_layout             = "滚动",
}

-- 每项的滑块取值范围（与 Info.json 的 min/max 逐项一致，打包器会比对）。
-- ★ v2.0.0：倍率/百分比类上限一律 10000（=100 倍）；非倍率类保持原上限。
local LIMITS = {
    extra_copies           = { 1, 100 },        -- 份数类
    spread_mode            = { 1, 4 },
    spread_angle_deg       = { 1, 360 },        -- 角度：360 已是整圈
    trigger_chance_percent = { 1, 100 },        -- 概率上限就是 100%
    chain_depth            = { 1, 100 },        -- 层数类
    max_copies_per_second  = { 1, 100 },        -- 数量类
    max_copies_per_frame   = { 1, 100 },        -- 数量类（逐帧）
    copy_velocity_percent  = { 10, 10000 },     -- 倍率/百分比类
    copy_damage_percent    = { 1, 10000 },
    damage_percent         = { 1, 10000 },
    knockback_percent      = { 1, 10000 },
    velocity_percent       = { 10, 10000 },
    scale_percent          = { 10, 10000 },
    lifetime_percent       = { 10, 10000 },
    pierce_bonus           = { 1, 10000 },      -- 加值类
    crit_bonus             = { 1, 10000 },      -- 加值类
    local_immunity_frames  = { 1, 600 },        -- 帧类
    homing_strength        = { 1, 10000 },      -- 百分比类（100 = 直接对准）
    homing_range           = { 100, 10000 },    -- 点/像素类
    track_interval         = { 1, 60 },         -- 帧间隔类
    enemy_track_interval   = { 1, 60 },         -- 帧间隔类
    global_scan_interval   = { 1, 600 },        -- 候选表刷新周期（帧）；1..600
    homing_flight_frames   = { 1, 600 },        -- 帧类（UI = 帧数 + 1，1 = 不限）
    homing_stop_distance   = { 1, 2000 },       -- 点/像素类（UI = 像素 + 1，1 = 用原版 24）
    hit_split_copies       = { 1, 100 },        -- 份数类（UI = 份数 + 1，1 = 关闭）
    hit_explosion_radius   = { 1, 1000 },       -- 点/像素类（UI = 半径 + 1，1 = 关闭）
    hit_explosion_damage_percent = { 1, 10000 },-- 倍率类
    hit_lifesteal_percent  = { 1, 10000 },      -- 倍率类（UI = 百分比 + 1，1 = 关闭）
    hit_lightning_chain    = { 1, 20 },         -- 次数类（UI = 跳数 + 1，1 = 关闭）
    hit_lightning_damage_percent = { 1, 10000 },-- 倍率类
    hit_lightning_radius   = { 50, 2000 },      -- 点/像素类
    physics_bounce_limit   = { 1, 100 },        -- 次数类（UI = 次数 + 1，1 = 关闭）
    physics_orbit_percent  = { 1, 10000 },      -- 百分比类（UI = 度/帧×100 + 1，1 = 关闭）
    net_update_min_frames  = { 1, 60 },         -- 帧间隔类
    net_angle_deg          = { 1, 360 },        -- 角度类
    global_projectile_cap  = { 100, 3000 },     -- 数量类（原版上限 1000 = 不干预）
    max_checks_per_frame   = { 0, 100000 },     -- 0 = 不限
    adaptive_unit          = { 1, 1000 },       -- 每 N 发弹幕升一档
    target_switch_cooldown = { 0, 600 },        -- 0 = 不限制
    speed_override_interval = { 1, 60 },        -- 1 = 每帧
    global_shot_budget     = { 0, 100000 },     -- 0 = 不限
    diag_slow_ms           = { 1, 1000 },       -- 毫秒类（§4.6 统一项）
    tick_interval          = { 1, 60 },         -- 帧间隔类
    config_reload_sec      = { 1, 60 },         -- 秒间隔类
}

-- CHOICE 类设置的合法取值（必须与 Info.json 的 options 逐值、逐序一致；打包器会比对）
local CHOICES = {
    filter_mode        = { "不过滤", "白名单", "黑名单" },
    gui_layout         = { "滚动", "分页" },
    perf_mode          = { "性能优先", "手感优先" },
    homing_priority    = { "最近", "Boss优先", "血量最高", "混合" },
    weapon_filter_mode = { "不过滤", "白名单", "黑名单" },
}

-- TEFManager 的整数滑块最小值是 1：凡是「0 = 默认档 / 关闭 / 不限制」的设置项都写成从 1
-- 起算的 UI 值，再用这张表把偏移减回去（内部值仍 0 起算）。
local UI_OFFSET = {
    extra_copies          = 1,
    spread_mode           = 1,
    spread_angle_deg      = 1,
    chain_depth           = 1,
    max_copies_per_second = 1,
    copy_damage_percent   = 1,
    knockback_percent     = 1,
    pierce_bonus          = 1,
    crit_bonus            = 1,
    homing_flight_frames  = 1,
    homing_stop_distance  = 1,
    hit_split_copies      = 1,
    hit_explosion_radius  = 1,
    hit_lifesteal_percent = 1,
    hit_lightning_chain   = 1,
    physics_bounce_limit  = 1,
    physics_orbit_percent = 1,
}

-- 散射模式名称（日志与提示用）
local SPREAD_MODE_NAME = { [0] = "扇形", [1] = "环形", [2] = "随机", [3] = "同向" }

-- CHOICE 字符串 → 内部编号
local CHOICE_ID = {
    perf_mode = { ["性能优先"] = K.PERF_FAST, ["手感优先"] = K.PERF_FEEL },
    homing_priority = { ["最近"] = K.PRI_NEAREST, ["Boss优先"] = K.PRI_BOSS,
                        ["血量最高"] = K.PRI_HP, ["混合"] = K.PRI_MIXED },
    weapon_filter_mode = { ["不过滤"] = K.WEAPON_ANY, ["白名单"] = K.WEAPON_WHITE,
                           ["黑名单"] = K.WEAPON_BLACK },
}

-- ============================================================================
-- 2. 配置读取（TEFManager 把模组设置写成 config.json，格式为扁平 JSON 对象）
--    cfg.* 存**内部值**：INTEGER 减掉 UI_OFFSET，SWITCH 是 bool，CHOICE/STRING 是字符串。
-- ============================================================================
local cfg = {}
local config_loaded = false
local last_config_check = -math.huge
local cfg_version = 0            -- 每次设置重算 +1，用于让各槽位的派生缓存失效
-- 面板改过的运行时值：重读设置时覆盖回 cfg（绝不写 TEFManager 设置，见 §28）
local override = {}

-- 读取整型设置：容忍写成 12 / 12.0 / "12" 三种形态。上下限都夹。
local function parse_int(raw, key, fallback)
    local value = raw:match('"' .. key .. '"%s*:%s*(-?%d+%.?%d*)')
    if not value then return fallback end
    local n = tonumber(value)
    if not n then return fallback end
    n = math.floor(n)
    local lim = LIMITS[key]
    if lim then
        if n < lim[1] then n = lim[1] end
        if n > lim[2] then n = lim[2] end
    end
    return n
end

local function parse_bool(raw, key, fallback)
    local value = raw:match('"' .. key .. '"%s*:%s*(%a+)')
    if value == "true" then return true end
    if value == "false" then return false end
    return fallback
end

-- CHOICE / STRING：取 JSON 字符串字面量（去掉最外层引号）。
-- ★ CHOICE 的非法旧值（旧 config.json 里可能是数字）必须回落到默认档，不能卡住界面。
local function parse_str(raw, key, fallback)
    local value = raw:match('"' .. key .. '"%s*:%s*"([^"]*)"')
    if type(value) ~= "string" then return fallback end
    local choices = CHOICES[key]
    if choices then
        for i = 1, #choices do
            if value == choices[i] then return value end
        end
        return fallback
    end
    return value
end

-- B3 迁移：旧 filter_mode 是 INTEGER 1..3（UI 档位），换算成 CHOICE 标签。
--   1 = 不过滤 / 2 = 白名单 / 3 = 黑名单；其它数字回落到默认档。
local LEGACY_FILTER_MODE = { [1] = "不过滤", [2] = "白名单", [3] = "黑名单" }
local function parse_choice(raw, key, fallback, legacy)
    local value = raw:match('"' .. key .. '"%s*:%s*"([^"]*)"')
    if type(value) == "string" then
        local choices = CHOICES[key]
        if choices then
            for i = 1, #choices do
                if value == choices[i] then return value end
            end
            return fallback
        end
        return value
    end
    local num = raw:match('"' .. key .. '"%s*:%s*(-?%d+%.?%d*)')
    if num and legacy then
        local v = math.floor(tonumber(num) or 0)
        return legacy[v] or fallback
    end
    return fallback
end

-- B3 迁移：旧槽位是「UI = 真实 ID + 1；<= 1 = 空槽」。
--   32 → 31、68 → 67、72 → 71、180 → 179；绝不能把 32 当真实 ID。
local function legacy_id_string(v)
    v = math.floor(tonumber(v) or 0)
    if v <= 1 then return "" end
    return tostring(v - 1)
end
local function parse_id_list(raw, key, fallback)
    local value = raw:match('"' .. key .. '"%s*:%s*"([^"]*)"')
    if type(value) == "string" then return value end
    local num = raw:match('"' .. key .. '"%s*:%s*(-?%d+%.?%d*)')
    if num then return legacy_id_string(num) end
    return fallback
end

-- UI 值 → 内部值（减掉偏移；DEFAULTS 与配置解析结果都过这一道）
local function to_internal(key, v)
    local off = UI_OFFSET[key]
    if off and type(v) == "number" then return v - off end
    return v
end

local function copy_defaults()
    for k, v in pairs(DEFAULTS) do cfg[k] = to_internal(k, v) end
    cfg.perf_id = K.PERF_FAST
    cfg.priority_id = K.PRI_NEAREST
    cfg.weapon_mode_id = K.WEAPON_ANY
end

copy_defaults()

-- 派生参数（on_settings_changed 里算好，热路径只读这些：避免每帧做除法/比字符串）
local perf_id, pri_id = K.PERF_FAST, K.PRI_NEAREST
local homing_on, physics_on, hit_on = false, false, false
local lock_on = false
local overrides_on = false
local global_scan_frames, enemy_scan_frames, npc_scan_frames = 20, 10, 6
local net_angle_cos = 0.97
local prune_r2 = 0
local nearest_k = 24

-- 前向声明：这两个函数在 §24/§24.1 才定义，而 §21 的 tick_config 已经要引用它们 ——
--   ★ Lua 的 local 作用域从声明行开始：不前置声明会静默解析成全局（nil），
--     而调用点包在 pcall 里，错误会被吞掉（表现为「粘贴导入毫无反应」）。
local import_apply
local tick_import_string

local function read_config(raw_arg)
    if not config_loaded then copy_defaults() end

    local raw = raw_arg
    if type(raw) ~= "string" then raw = mod.read_file("config.json") end
    if type(raw) ~= "string" then
        config_loaded = true
        return false
    end

    -- 文件存在但里面一个本模组的键都没有（TEFManager 正在写的中间态、截断、
    -- 或放错了别的模组的配置）→ 当作读取失败，沿用上一次的有效值，
    -- 避免玩家的设置被一瞬间打回默认。
    local hits = 0
    for key in pairs(DEFAULTS) do
        if raw:find('"' .. key .. '"', 1, true) then hits = hits + 1 end
    end
    if hits == 0 then return false end

    -- 旧配置的名单是 INTEGER（UI = ID + 1）。如果只写了 filter_id_1=32 而没写
    --   filter_id_2..4（TEFManager 可能只落非默认项），要补上旧的默认 68/72/180，
    --   否则升级后默认黑名单只剩 31，67/71/179 会漏掉。
    local legacy_id_cfg = raw:match('"filter_id_[1-4]"%s*:%s*-?%d') ~= nil

    for key, default in pairs(DEFAULTS) do
        if type(default) == "boolean" then
            cfg[key] = parse_bool(raw, key, default)
        elseif type(default) == "number" then
            cfg[key] = to_internal(key, parse_int(raw, key, default))
        elseif key == "filter_mode" then
            cfg[key] = parse_choice(raw, key, default, LEGACY_FILTER_MODE)
        elseif key:match("^filter_id_%d$") then
            local fallback = default
            if legacy_id_cfg then
                -- 旧默认槽位 2/3/4 = 68/72/180（真实 67/71/179）
                if key == "filter_id_2" then fallback = "67"
                elseif key == "filter_id_3" then fallback = "71"
                elseif key == "filter_id_4" then fallback = "179" end
            end
            cfg[key] = parse_id_list(raw, key, fallback)
        elseif key:match("^weapon_id_%d$") then
            cfg[key] = parse_id_list(raw, key, default)
        else
            cfg[key] = parse_str(raw, key, default)
        end
    end
    -- 面板改过的运行时值覆盖回来（面板不写 TEFManager 设置）
    for k, v in pairs(override) do
        -- gui_enable 不走覆盖层：它是「面板关了怎么开回来」的自救开关，
        -- 必须让 TEFManager 设置页的值立刻生效，否则覆盖层会把面板永久锁死。
        if DEFAULTS[k] ~= nil and k ~= "gui_enable" then cfg[k] = v end
    end

    -- CHOICE → 内部编号（非法值已在 parse_str / parse_choice 里回落到默认档）
    cfg.perf_id = CHOICE_ID.perf_mode[cfg.perf_mode] or K.PERF_FAST
    cfg.priority_id = CHOICE_ID.homing_priority[cfg.homing_priority] or K.PRI_NEAREST
    cfg.weapon_mode_id = CHOICE_ID.weapon_filter_mode[cfg.weapon_filter_mode] or K.WEAPON_ANY

    last_config_raw = raw
    config_loaded = true
    return true
end

-- ============================================================================
-- 3. 日志（write_log 总开关；write_log = false 时运行期一条日志都不写）
--    debug_log 是二级开关（详细日志），必须在 write_log 打开时才有意义。
-- ============================================================================
local function log_info(fmt, ...)
    if cfg.write_log == true then mod.info(fmt, ...) end
end
local function log_warn(fmt, ...)
    if cfg.write_log == true then mod.warn(fmt, ...) end
end

local function now_seconds()
    if os.time then return os.time() end
    if os.clock then return os.clock() end
    return 0
end

-- 亚秒级时钟（性能指标用）。★ 加载期就把 os.clock 抓成 upvalue，热路径不再包 pcall。
--   拿不到 os.clock 就当 0：指标退化为 0 ms，功能不受影响。
local clock_fn = (os and os.clock) or nil
local function now_cpu()
    if clock_fn then return clock_fn() end
    return 0
end

local debug_last = -math.huge
-- 详细日志：速率限制每秒最多 1 条（日志过大本身也会把游戏拖崩）
local function log_debug(fmt, ...)
    if cfg.write_log ~= true or cfg.debug_log ~= true then return end
    local now = now_seconds()
    if now - debug_last < 1 then return end
    debug_last = now
    if mod.debug then
        mod.debug(fmt, ...)
    elseif mod.info then
        mod.info(fmt, ...)
    end
end

-- ============================================================================
-- 4. 句柄表（setup 里解析一次；只取句柄 + 装钩子，绝不调用游戏方法）
--    ★ 全部塞进一张表 H，而不是 60 个 upvalue —— Lua 主 chunk 的局部变量上限是 200，
--      分组后热路径只是多一次 table 取值（几十纳秒），相对一次反射调用可忽略。
-- ============================================================================
local H = {}

-- 方法句柄
H.new_text, H.ai, H.new_projectile, H.can_be_chased, H.get_update_count = nil, nil, nil, nil, nil
H.strike_npc, H.player_heal, H.get_game_menu, H.get_my_player, H.get_selected_item = nil, nil, nil, nil, nil
H.source_from_this = nil
-- 聊天命令句柄：★ 只在设置项「聊天指令」打开时才会被解析（默认关闭）。
--   唯一的聊天文本入口是 SayChatCommand.ProcessIncomingMessage(string, byte)：
--   它是 ChatInitializer 注册的 _defaultCommand，普通聊天与任何「未知 /命令」的原文
--   都会原样送到这里，参数全是标量。**绝不触达 Terraria.Chat 的消息对象类型**
--   （v1.0.0 实机 SIGABRT ×3 就崩在反射它的成员上，见 05-写法与陷阱.md §5.2）。
H.chat_say = nil

-- 类型句柄
H.t_main, H.t_projectile, H.t_npc, H.t_player, H.t_item = nil, nil, nil, nil, nil

-- 杂项状态（非热路径，放表里省局部变量）
local S = {
    ready = false,
    spawning = 0,              -- >0 表示正在由本 Mod 生成副本（此时 postfix 不再自行分裂）
    logged_first_copy = false,
    logged_first_override = false,
    spawn_warned = false,
    env_in_world = false,      -- 「进世界后的第一帧」双门控的边沿标记
    check_pending = false,     -- 本世界还没播报过自检
    chat_hooks = 0,            -- 已装上的聊天钩子数（聊天指令关闭时必须为 0）
    chat_hook_fail = nil,      -- 装不上时的原因（诊断用）
    import_seen_raw = nil,     -- 已处理过的 import_string 原文（防重复应用）
    import_active = nil,       -- 正在应用的那条串（并发保护）
    chat_last = "",
    budget_window_start = 0,
    budget_used = 0,
    -- v2.2.0 性能/预算/快通道（全是本地整数，面板只读）
    check_frame = nil, checks_used = 0,
    frame_calls = 0, last_frame_calls = 0, adaptive_n = 1,
    shot_frame = nil, shot_used = 0,
    fast_fail_logged = false,
    fbudget_frame = -1,
    fbudget_used = 0,
    frame_no = 0,              -- AI 回调序号（分桶用）
    phase = 0,                 -- 追踪错峰相位
    env_net_mode = 0,
    env_net_mode_ok = false,
    env_my_player = 0,
    env_my_player_ok = false,
    copy_ids = { n = 0 },      -- 本模组生成的副本下标（全局上限超限时只回收这些）
    hit_frame = nil,           -- 命中效果帧内预算：当前帧号
    hit_used = 0,              -- 命中效果帧内预算：本帧已处理次数
    samples = 0,               -- 帧号采样计数（兜底重取用）
    frags = {},                -- 导入设置串的分片缓存
    frag_have = 0,
    frag_total = 0,
    frag_missing = 0,
}

-- ============================================================================
-- 5. 以 whoAmI（整数下标）为键的「每槽位状态」
--   s.t    弹幕类型（判槽位复用 / 世代）
--   s.cv   派生缓存对应的 cfg_version
--   s.scope/s.frd/s.hst/s.own/s.copy  派生标志（首次见到时算一次，配置变了才重算）
--   s.last/s.iv       上次转向的帧号 / 动态扫描间隔（帧）
--   s.tgt/s.tkind     锁定目标（NPC 数组下标 / 玩家数组下标）
--   s.tracking        是否占着 MAX_TRACKED 名额
--   s.age/s.af        飞行帧数（追踪曲线用）
--   s.pvx/s.pvy/s.pf/s.pdot  上一帧速度与方向点积（物理组 / 反弹检测用）
--   s.bounces         已计反弹次数
--   s.spx/s.spy/s.spvx/s.spvy/s.spf  出生位置与出生速度（直线锁 / 归位用）
--   s.net/s.ndx/s.ndy 上次网络同步的帧号与朝向（netUpdate 节流）
--   s.nh/s.hits       上次看到的 numHits / 已触发的命中效果次数
-- ============================================================================
local slot = {}
local function slot_of(id)
    local s = slot[id]
    if not s then s = {}; slot[id] = s end
    return s
end

-- 追踪名额：tracked_n 计数器（替代 v1.1.0 的 pairs 遍历）+ 活跃名单（非关键桶里压缩）
local tracked_n = 0
local tracked_ids = { n = 0 }
local evict_cursor = 0

-- 每个 NPC 下标在最近一次扫描里的快照（只存整数下标与数值，不存对象 → 无悬垂句柄）
local npc_seen, npc_cx, npc_cy, npc_rank, npc_life = {}, {}, {}, {}, {}
-- 每个玩家下标在最近一次扫描里的快照
local pl_seen, pl_cx, pl_cy = {}, {}, {}
local pl_list, pl_list_n = {}, 0

-- 全局共享候选目标表（★ §3.7-②：每 global_scan_interval 帧只扫一次 Main.npc）
local cand = {
    frame = nil,         -- 上次扫描的帧号（拿不到帧号时记 cpu 秒）
    n = 0,               -- 候选数量
    npc = {}, cx = {}, cy = {}, dmin2 = {}, rank = {}, life = {},
    cell_size = 1,       -- 网格格子边长（像素）
    cells = {},          -- cells[key] = { n = k, [1..k] = 候选序号 }
    pn = 0,              -- 上次扫描时的有效玩家数
    grace = 60,          -- 目标宽限帧数 = 全局扫描间隔 × TARGET_GRACE_SCANS
    cropped = 0,         -- 被「最近 K 个」裁剪掉的 NPC 数（诊断用）
}

local copy_mark = {}     -- copy_mark[下标] = 帧号（供派生时识别「这是我们的副本」）
local cur_frame = nil    -- 本帧的游戏帧号（Main.get_GameUpdateCount）
local last_sampled_id = -1

-- 内部统计（只累加计数；聚合放在非关键桶里做，不写日志）
local stats = {
    tick_calls = 0, buckets = 0, bucket_index = 0,
    copies = 0, copies_last = 0, copies_per_bucket = 0,
    copies_frame = 0, copies_frame_no = -1, -- 本帧副本数（最近一次生成帧）
    checks_frame = 0, speed_writes = 0,      -- v2.2.0 面板只读
    budget_used = 0, budget_frame = -1, budget_denied = 0,
    explosion_hits = 0, chain_hits = 0,
    sec = 0, sec_copies = 0,               -- 当前这一秒的副本数（时间戳 = 秒）
    last_sec_copies = 0, peak_sec_copies = 0, -- 上一秒副本数 / 历史峰值（面板只读）
    overrides = 0, steers = 0, hits = 0, recycled = 0,
    perf = {
        frame = nil,
        scans_frame = 0,       -- 本帧扫描次数
        scans_total = 0,       -- 累计扫描次数
        steers_frame = 0,      -- 本帧「命中弹幕数」（真的做了转向的弹幕数）
        steers_total = 0,
        scan_ms = 0,           -- 扫描累计耗时（毫秒）
        steer_ms = 0,          -- 转向累计耗时（毫秒）
        avg_scan_ms = 0,       -- 平均每次扫描耗时
        avg_steer_ms = 0,      -- 平均每次转向耗时
        last_interval = 0,     -- 最近一次算出的动态间隔（诊断/测试用）
        skipped = { speed = 0, offscreen = 0, radar = 0, limit = 0, badid = 0,
                    checks = 0, adaptive = 0, cooldown = 0 },
    },
}

-- ============================================================================
-- 6. 诊断域注册表（§4.6-1：安装期登记一次，运行期只自增计数）
--    热路径禁止函数调用计数：把 d 缓存成 upvalue，直接 d.hits = d.hits + 1。
-- ============================================================================
local domains, D = {}, {}
local function reg_domain(key, name)
    local d = { name = name, fields = "?", methods = "?", hooks = "?",
                calls = 0, hits = 0, errs = 0, last_err = nil, ms = 0 }
    domains[#domains + 1] = d
    D[key] = d
    return d
end

reg_domain("ai", "弹幕AI逐帧")
reg_domain("newproj", "新弹幕(复制/改写)")
reg_domain("track", "追踪转向")
reg_domain("cand", "共享候选表")
reg_domain("hit", "命中效果")
reg_domain("phys", "弹幕物理组")
reg_domain("weapon", "武器白名单")
reg_domain("chat", "聊天命令")
reg_domain("cfg", "设置导入导出")
reg_domain("perf", "性能自测")

-- 测试专用出口（游戏内 _G.FORGE_TEST 为 nil，这一行不会执行任何东西）
if _G.FORGE_TEST then
    _G.FORGE_STATS = stats
    _G.FORGE_DOMAINS = domains
    _G.FORGE_DEFAULTS = DEFAULTS
    _G.FORGE_CFG = cfg
    _G.FORGE_SLOT = slot
end

-- 记录一次错误（只在该域自己的失败分支里写，不在热路径每帧写）
local function dom_err(d, msg)
    d.errs = d.errs + 1
    d.last_err = msg
end

-- ============================================================================
-- 7. 工具函数
-- ============================================================================

-- 字段在父类链上的情况很常见（position/velocity/whoAmI 在 Terraria.Entity 上），逐层查
local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < K.FIELD_LOOKUP_DEPTH do
        local field = patch.get_field(cur, name)
        if field then return field end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

-- 硬规则 #2：读之前先确证不是 const（readonly 可以读）。只装在安装期用。
local function field_readable(field)
    if not field then return false end
    if not patch.field_is_const then return true end
    local ok, is_const = pcall(patch.field_is_const, field)
    if not ok then return true end
    return is_const ~= true
end

-- ---- 读（热路径：直接调用，无 pcall；句柄判空早退）----
local function get_int(field, inst, default)
    if not field then return default end
    local v = patch.get_field_value(field, inst, "int32")
    if v == nil then return default end
    return v
end

local function get_float(field, inst, default)
    if not field then return default end
    local v = patch.get_field_value(field, inst, "float")
    if v == nil then return default end
    return v
end

local function get_bool(field, inst, default)
    if not field then return default end
    local v = patch.get_field_value(field, inst, "bool")
    if v == nil then return default end
    return v
end

-- ============================================================================
-- 7.1 弹幕表观察器（面板第 3 页用；只在面板打开时采集，聚合值，不逐弹幕反射）
--   面板本身绝不调 patch.*；这里借 Projectile.AI 已有的回调顺手数 type，
--   每个 projectile 每秒只做 1~2 次字段读，面板关闭后 obs.until_ 过期即停。
-- ============================================================================
local obs = { sec = 0, cur = {}, cur_n = 0, last = {}, last_n = 0, until_ = 0 }

local function obs_roll(now)
    if obs.sec == now then return end
    obs.last, obs.last_n = obs.cur, obs.cur_n
    obs.cur, obs.cur_n = {}, 0
    obs.sec = now
end

local function obs_note(instance, now)
    now = now or now_seconds()
    obs_roll(now)
    local t = get_int(H.f_type, instance, -1)
    if t < 0 then return end
    local rec = obs.cur[t]
    if not rec then
        rec = { t = t, n = 0, pl = 0 }
        obs.cur[t] = rec
        obs.cur_n = obs.cur_n + 1
    end
    rec.n = rec.n + 1
    if get_bool(H.f_friendly, instance, false) and not get_bool(H.f_hostile, instance, false) then
        rec.pl = rec.pl + 1
    end
end

if _G.FORGE_TEST then _G.FORGE_OBS = obs end

local function get_vec2(field, inst)
    if not field then return nil, nil end
    local x, y = patch.get_field_vec2(field, inst)
    if type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
    return x, y
end

-- ---- 写（热路径：直接调用，无 pcall）----
--   ★ §3.7-⑤：热路径去掉 pcall。前提是这里写入的每个字段类型都已在官方 1.4.5.8 手机版
--     字段表里逐项核对过（active/netUpdate/tileCollide/usesLocalNPCImmunity = bool、
--     damage/timeLeft/penetrate/localNPCHitCooldown/bonusCritChance = int、scale/knockBack
--     = float、velocity/position = Vector2，见字段表 17687-17790 行），传的类型名与
--     元数据完全一致，不存在“类型不匹配”。
--   ★ 生成副本、装钩子、配置读写这些非逐帧路径仍走 *_safe（pcall）与 pcall(invoke)。
local function set_bool(field, inst, v)
    if not field then return false end
    return patch.set_field_value(field, inst, v, "bool") ~= false
end

local function set_int(field, inst, v)
    if not field then return false end
    return patch.set_field_value(field, inst, v, "int32") ~= false
end

local function set_float(field, inst, v)
    if not field then return false end
    return patch.set_field_value(field, inst, v, "float") ~= false
end

local function set_vec2(field, inst, x, y)
    if not field then return false end
    return patch.set_field_vec2(field, inst, x, y) ~= false
end

-- ---- 写（非热路径：带 pcall，版本差异导致的类型不匹配不能把游戏线程带崩）----
local function set_int_safe(field, inst, v)
    if not field then return false end
    return pcall(patch.set_field_value, field, inst, v, "int32")
end

local function set_float_safe(field, inst, v)
    if not field then return false end
    return pcall(patch.set_field_value, field, inst, v, "float")
end

local function set_vec2_safe(field, inst, x, y)
    if not field then return false end
    return pcall(patch.set_field_vec2, field, inst, x, y)
end

-- ============================================================================
-- 10.5 v2.2.0 实验性 C 快通道（field_pointer + mem_read 一次批量读）
--   ★ 默认关闭；只在 cfg.use_fastpath=true 且自检通过后启用。
--   ★ 自检：同一发弹幕，快读 vs 托管 get_field 对拍 velocity/type/active；
--     不一致立即 cfg.use_fastpath=false（并写 override，避免 5 秒热重载又打开）。
--   ★ 偏移全部来自官方字段表的「偏移」列，绝不照抄其它模组的魔数。
-- ============================================================================
local FP = { checked = false, ok = false, result = "待自检", calls = 0 }

local function fast_read_raw(instance)
    if not (patch.field_pointer and patch.mem_read and H.f_position) then return nil end
    local ptr = patch.field_pointer(H.f_position, instance)
    if ptr == nil then return nil end
    local raw = patch.mem_read(ptr, 0, K.FAST_READ_LEN)
    if type(raw) ~= "string" or #raw < K.FAST_READ_LEN then return nil end
    local x  = string.unpack("<f", raw, 1 + K.FAST_POS_REL)
    local y  = string.unpack("<f", raw, 5 + K.FAST_POS_REL)
    local vx = string.unpack("<f", raw, 1 + K.FAST_VEL_REL)
    local vy = string.unpack("<f", raw, 5 + K.FAST_VEL_REL)
    local act = string.unpack("<B", raw, 1 + K.FAST_ACTIVE_REL) ~= 0
    local typ = string.unpack("<i4", raw, 1 + K.FAST_TYPE_REL)
    if x ~= x or y ~= y or vx ~= vx or vy ~= vy then return nil end
    return x, y, vx, vy, typ, act
end

local function fast_read(instance)
    if not (cfg.use_fastpath and FP.ok) then return nil end
    local x, y, vx, vy = fast_read_raw(instance)
    if x == nil then
        FP.ok = false
        cfg.use_fastpath = false
        if override then override.use_fastpath = false end
        FP.result = "读取失败，已回退"
        if not S.fast_fail_logged then
            S.fast_fail_logged = true
            if mod.warn then mod.warn("弹幕工坊：C 快通道读取失败，本次游戏已自动关闭") end
        end
        return nil
    end
    FP.calls = FP.calls + 1
    return x, y, vx, vy
end

local function fast_check(instance)
    if FP.checked then return end
    FP.checked = true
    if not cfg.use_fastpath then FP.result = "关闭"; return end
    if not (patch.field_pointer and patch.mem_read and H.f_position) then
        cfg.use_fastpath = false
        if override then override.use_fastpath = false end
        FP.result = "无 API，已关闭"
        if mod.warn then mod.warn("弹幕工坊：C 快通道缺少 field_pointer/mem_read，本次游戏已自动关闭") end
        return
    end
    local x, y, vx, vy, typ, act = fast_read_raw(instance)
    local mvx, mvy = get_vec2(H.f_velocity, instance)
    local mt = get_int(H.f_type, instance, -999)
    local ma = get_bool(H.f_active, instance, false)
    local ok = x ~= nil and mvx ~= nil
        and math.abs(vx - mvx) <= 0.001 and math.abs(vy - mvy) <= 0.001
        and typ == mt and act == ma
    if ok then
        FP.ok, FP.result = true, "自检通过"
    else
        FP.ok = false
        cfg.use_fastpath = false
        if override then override.use_fastpath = false end
        FP.result = "自检失败，已关闭"
        if not S.fast_fail_logged then
            S.fast_fail_logged = true
            if mod.warn then
                mod.warn("弹幕工坊：C 快通道自检失败（快读与托管路径不一致），本次游戏已自动关闭")
            end
        end
    end
end

-- 数组长度：array_length 有野外报告说真机返回 0 → pcall + 固定上限兜底；
-- 遍历时「扫到 nil 就停」也是安全兜底（越界返回 nil）。
local function array_count(arr, fallback)
    if not arr then return 0 end
    local ok, n = pcall(patch.array_length, arr)
    if ok and type(n) == "number" and n > 0 then return n end
    return fallback or 0
end

-- 从 Main.projectile / Main.player 取指定下标（0 起始）的对象
local function get_projectile_at(idx)
    if not H.f_main_projectile or type(idx) ~= "number" or idx < 0 then return nil end
    local arr = patch.get_field_value(H.f_main_projectile, nil, "object")
    if not arr then return nil end
    return patch.array_at(arr, idx)
end

local function main_player_at(idx)
    if not H.f_main_player or type(idx) ~= "number" or idx < 0 then return nil end
    local arr = patch.get_field_value(H.f_main_player, nil, "object")
    if not arr then return nil end
    return patch.array_at(arr, idx)
end

local function safe_hook(method, spec, label)
    if not method then
        mod.warn("安装钩子失败(" .. label .. ")：方法句柄为空")
        return nil
    end
    local ok, hook = pcall(patch.install_hook, method, spec)
    if not ok then
        -- setup 阶段的一次性安装诊断：属「符号/环境取不到」一类，write_log=false 也保留
        mod.warn("安装钩子失败(" .. label .. ")：" .. tostring(hook))
        return nil
    end
    return hook
end

-- 方法形参个数（硬规则 #3：invoke 的实参个数必须精确等于它）
local function method_argc(method)
    if not method then return nil end
    local ok, c = pcall(patch.method_param_count, method)
    if ok and type(c) == "number" and c >= 0 then return c end
    return nil
end

-- 取方法句柄并**当场核对形参个数**：个数不符就当取不到（宁可不生效，也不越界读栈）
local function method_exact(type_handle, name, argc)
    local m = patch.get_method(type_handle, name, argc)
    if not m then return nil end
    local c = method_argc(m)
    if c ~= nil and c ~= argc then return nil end
    return m
end

-- 取 type.field 并确认可读（非 const）；不可读返回 nil（硬规则 #2 的安装期门控）
local function field_of(type_handle, name)
    local f = find_field(type_handle, name)
    if f and not field_readable(f) then return nil end
    return f
end

-- ============================================================================
-- 8. 聊天输出（§4.6：统一封装 chat_print，全模组只走它）
--    ★ 只在游戏内（收到命令 / 进世界首帧播报）调用；setup() 阶段绝不调用。
--    Main.NewText 手机版有 5 参 (string,byte,byte,byte,bool) 与 3 参 (string,Color,bool)
--    两个重载（方法表 9575/9576 行）；Color 是结构体 → **只认 5 参**，取不到就退化成
--    写日志（不猜重载、不多传实参 —— 实参个数必须等于形参个数）。
-- ============================================================================
-- ★ §9：聊天指令总开关。关闭时全模组不碰任何 Chat 类型、不装聊天钩子。
local function chat_cmd_on()
    return cfg.chat_cmd == true
end

local function chat_print(text, force)
    if type(text) ~= "string" or text == "" then return false end
    if not force and text == S.chat_last then return true end   -- 简单去重，避免刷屏
    S.chat_last = text
    if H.new_text then
        -- ★★ v2.0.1 崩溃修复：形参是 string 的 invoke **必须**先构造托管字符串句柄。
        --   内核把 IL2CPP_TYPE_STRING 映射成 PATCH_OBJECT（TEFKernel field.c:82），
        --   LuaLoader 的 read_patch_value() 对 PATCH_OBJECT 只调 to_handle()，
        --   **Lua 字符串一律得到 NULL**（lua_api.cpp:162-205）—— 旧写法直接传 `text`
        --   就是给 Main.NewText 传了 null → ChatManager.ParseMessage(null) 里
        --   `text.Replace(...)` → NullReferenceException → 异常穿出 native 帧 →
        --   abort() → SIGABRT（pcall 拦不住）。「进世界首帧自检播报」默认就开着
        --   （self_check 默认 true）→ 进世界必崩，与实机日志一致。
        local s
        if patch.string_create then
            local oks, h = pcall(patch.string_create, text)
            if oks and h then s = h end
        end
        if s then
            local ok = pcall(patch.invoke, H.new_text, s, 255, 235, 120, false)
            if ok then return true end
        elseif not S.no_string_create then
            S.no_string_create = true
            log_warn("patch.string_create 不可用：聊天输出改为只写日志"
                .. "（绝不裸传 Lua 字符串 —— 那在真机上是 NULL → 进程崩溃）")
        end
    end
    log_info("%s", text)
    return false
end

-- ============================================================================
-- 9. 设置重算 / 派生参数 / 逐帧工作开关
-- ============================================================================
local filter_set = {}        -- 由 filter_id_1..4 的 STRING 列表构建的弹幕类型集合
local weapon_set = {}        -- 由 weapon_id_1..4 的 STRING 列表构建的物品 ID 集合
local filter_n, weapon_n = 0, 0

-- 把「真实 ID 的逗号分隔串」并进集合。同时兼容旧配置里残留的 number：
--   v <= 1 = 空槽，否则 id = v - 1（绝不能把 UI 值当真实 ID）。
local function add_id_tokens(raw, set)
    if type(raw) == "number" then raw = legacy_id_string(raw) end
    if type(raw) ~= "string" then return 0 end
    local added = 0
    for token in raw:gmatch("[^,，;%s]+") do
        local v = tonumber(token)
        if v then
            v = math.floor(v)
            if v > 0 and not set[v] then set[v] = true; added = added + 1 end
        end
    end
    return added
end

local function rebuild_sets()
    filter_set, filter_n = {}, 0
    for i = 1, 4 do
        filter_n = filter_n + add_id_tokens(cfg["filter_id_" .. i], filter_set)
    end
    weapon_set, weapon_n = {}, 0
    for i = 1, 4 do
        weapon_n = weapon_n + add_id_tokens(cfg["weapon_id_" .. i], weapon_set)
    end
end

-- 逐帧工作总开关：全关时 on_ai 只做几次布尔比较 → 一次反射调用都没有
local function refresh_frame_flags()
    -- 体型/穿透逐帧锁定（v1.1.0 就有；v2.0.0 挪到槽位状态 s.ls / s.lp 上）
    lock_on = (cfg.lock_scale == true) or (cfg.lock_pierce == true)
    homing_on = (cfg.homing_enabled == true)
    physics_on = (cfg.physics_no_gravity == true)
        or (cfg.physics_pass_wall == true)
        or (cfg.physics_bounce_limit > 0)
        or (cfg.physics_orbit_percent > 0)
        or (cfg.physics_return_home == true)
    hit_on = (cfg.hit_split_copies > 0)
        or (cfg.hit_explosion_radius > 0)
        or (cfg.hit_lifesteal_percent > 0)
        or (cfg.hit_lightning_chain > 0)
    overrides_on = (cfg.damage_percent ~= 100) or (cfg.knockback_percent ~= 100)
        or (cfg.velocity_percent ~= 100) or (cfg.scale_percent ~= 100)
        or (cfg.lifetime_percent ~= 100) or (cfg.pierce_bonus > 0)
        or (cfg.ignore_npc_immunity == true)
end

-- 设置变化后重算派生参数（避免热路径做除法/比字符串）
local function on_settings_changed()
    refresh_frame_flags()
    rebuild_sets()

    perf_id = cfg.perf_id or K.PERF_FAST
    pri_id = cfg.priority_id or K.PRI_NEAREST

    -- §3.7-⑦：Main.npc（我方弹幕）与 Main.player（敌方弹幕）分开的基础扫描间隔。
    --   性能优先 = 用户设定值；手感优先 = 扫描频率提高 4 倍（间隔缩短到 1/4）。
    local base_npc = cfg.track_interval
    local base_pl = cfg.enemy_track_interval
    if perf_id == K.PERF_FEEL then
        base_npc = math.max(1, math.floor(base_npc / 4))
        base_pl = math.max(1, math.floor(base_pl / 4))
    end
    if type(base_npc) ~= "number" or base_npc < 1 then base_npc = 6 end
    if type(base_pl) ~= "number" or base_pl < 1 then base_pl = 10 end
    npc_scan_frames = base_npc
    enemy_scan_frames = base_pl

    local gs = cfg.global_scan_interval
    if type(gs) ~= "number" or gs < 1 then gs = 20 end
    if perf_id == K.PERF_FEEL then gs = math.max(1, math.floor(gs / 4)) end
    global_scan_frames = gs
    cand.grace = gs * K.TARGET_GRACE_SCANS

    -- 候选裁剪：性能优先裁到 24 个，手感优先放宽到 48 个
    nearest_k = (perf_id == K.PERF_FEEL) and 48 or 24

    -- 裁剪半径：距玩家 N×索敌半径内的 NPC 无条件保留（避免远距离弹幕没目标可选）
    local range = cfg.homing_range
    if type(range) ~= "number" or range < 1 then range = 1 end
    local pr = range * K.PRUNE_RADIUS_MULT
    prune_r2 = pr * pr
    cand.cell_size = math.max(64, math.floor(range))

    -- netUpdate 的朝向阈值（度 → cos）
    local deg = cfg.net_angle_deg
    if type(deg) ~= "number" or deg < 1 then deg = 15 end
    if deg > 180 then deg = 180 end
    net_angle_cos = math.cos(deg * math.pi / 180)

    cfg_version = cfg_version + 1
end

-- ============================================================================
-- 10. 作用范围判定（A 组开关 + 类型过滤 + 武器白/黑名单）
-- ============================================================================
-- 类型过滤：filter_mode = 不过滤 / 白名单（只处理名单内）/ 黑名单（排除名单内）
local function type_allowed(t)
    local mode = cfg.filter_mode
    -- 旧内部数字（1/2）仍兼容；正常情况下 read_config 已经迁移成 CHOICE 字符串
    if mode == 1 then mode = "白名单" elseif mode == 2 then mode = "黑名单" end
    -- 「空 = 不使用」：名单为空时白/黑名单都不拦任何弹幕（空串不误伤）
    if filter_n == 0 then return true end
    if mode == "白名单" then
        if t == nil then return false end
        return filter_set[t] == true
    elseif mode == "黑名单" then
        if t == nil then return true end
        return filter_set[t] ~= true
    end
    return true
end

-- §4.4-⑨ 按武器 ID（= 发射它的那把武器物品的 Item.type）白/黑名单。
-- ★ 取不到武器（召唤物/哨兵/怪物弹幕/句柄缺失）时 **fail-open 放行** 并计入诊断，
--   免得「一开启白名单就所有弹幕都不生效」。
local function weapon_allowed(w)
    local mode = cfg.weapon_mode_id
    if mode == K.WEAPON_ANY or mode == nil then return true end
    -- 武器名单为空 = 不使用（空串不误伤；白名单空列表也不许把全部弹幕拦掉）
    if weapon_n == 0 then return true end
    if type(w) ~= "number" then
        dom_err(D.weapon, "取不到发射武器 ID，按不限制放行")
        return true
    end
    local in_list = weapon_set[w] == true
    if mode == K.WEAPON_WHITE then return in_list end
    return not in_list
end

local function is_player_side(p)
    return get_bool(H.f_friendly, p, false) and not get_bool(H.f_hostile, p, false)
end

-- 是否属于本 Mod 的处理范围（A 组开关 + 类型过滤 + 武器名单）
local function in_scope(p, wpn)
    if not get_bool(H.f_active, p, false) then return false end
    if not type_allowed(get_int(H.f_type, p, nil)) then return false end
    if not weapon_allowed(wpn) then return false end
    -- 特殊用途弹幕优先判定，避免被 friendly/hostile 误分类
    if get_bool(H.f_bobber, p, false) then return cfg.affect_bobbers == true end
    if get_bool(H.f_minion, p, false) then return cfg.affect_minions == true end
    if get_bool(H.f_sentry, p, false) then return cfg.affect_sentries == true end
    if get_int(H.f_ai_style, p, -1) == 7 then return cfg.affect_hooks == true end
    if is_player_side(p) then return cfg.affect_player_shots == true end
    if get_bool(H.f_hostile, p, false) then return cfg.affect_enemy_shots == true end
    -- 归属不明（中立/陷阱/环境弹幕…）→「其它」类
    return cfg.scope_other == true
end

-- 联机：host_only 打开且 Main.netMode == 1（客机）时，本 Mod 只读不写。
-- 句柄取不到 / 读不到 → 退化成「不限制」。
local function host_readonly()
    if cfg.host_only ~= true then return false end
    if not S.env_net_mode_ok then return false end
    return S.env_net_mode == 1
end

-- 拿到发射这枚弹幕的武器物品 ID（仅生成路径调用，不逐帧）。
--   owner → Main.player[owner] → Player.selectedItem（**属性**，走 0 参 getter）
--   → Player.inventory[selectedItem]（Item[]）→ Item.type
local function resolve_weapon(owner)
    if type(owner) ~= "number" or owner < 0 then return nil end
    if not (H.f_player_inventory and H.get_selected_item and H.f_item_type) then return nil end
    local pl = main_player_at(owner)
    if not pl then return nil end
    local sel = patch.invoke(H.get_selected_item, pl)
    if type(sel) ~= "number" then return nil end
    local inv = patch.get_field_value(H.f_player_inventory, pl, "object")
    if not inv then return nil end
    local it = patch.array_at(inv, sel)
    if not it then return nil end
    local w = get_int(H.f_item_type, it, nil)
    if w == 0 then return nil end          -- 空手/空格
    return w
end

-- ============================================================================
-- 11. 预算（性能保护）
-- ============================================================================
-- 每秒副本预算（v1.1.0 保留）
local function budget_take()
    -- 秒窗口先推进（即使「不限」也要推进）：make_one_copy 的每秒统计直接复用
    -- 这个时间戳，热路径不再额外调 os.time。
    local now = now_seconds()
    if now ~= S.budget_window_start then
        S.budget_window_start = now
        S.budget_used = 0
    end
    local limit = cfg.max_copies_per_second
    if type(limit) ~= "number" or limit <= 0 then return true end   -- 0 = 不限
    if S.budget_used >= limit then return false end
    S.budget_used = S.budget_used + 1
    return true
end

-- §4.4-⑦ 每帧最多新增副本数（在每秒预算之外的逐帧上限，防止一帧内爆发）
local function frame_budget_take(frame)
    local limit = cfg.max_copies_per_frame
    if type(limit) ~= "number" or limit <= 0 then return true end
    if S.fbudget_frame ~= frame then
        S.fbudget_frame = frame
        S.fbudget_used = 0
    end
    if S.fbudget_used >= limit then return false end
    S.fbudget_used = S.fbudget_used + 1
    return true
end

-- v2.2.0 全局弹幕预算：只统计「本模组新增」的副本/分裂；每帧回补。
--   0 = 不限；只在本模组自己的生成路径调用，绝不统计原版弹幕。
local function shot_budget_take(frame)
    local limit = cfg.global_shot_budget
    if type(limit) ~= "number" or limit <= 0 then return true end
    if frame == nil then return true end
    if S.shot_frame ~= frame then S.shot_frame, S.shot_used = frame, 0 end
    if S.shot_used >= limit then
        stats.budget_denied = stats.budget_denied + 1
        return false
    end
    S.shot_used = S.shot_used + 1
    stats.budget_used, stats.budget_frame = S.shot_used, frame
    return true
end

-- v2.2.0 自适应分帧档位：n < unit → 1；否则 floor(n/unit)，再夹到 [1, cap]。
--   process_every_n_frame 复用现有 tick_interval（不新增第 8 项设置）。
local function adaptive_n(n, unit, cap)
    if type(n) ~= "number" or n < 0 then n = 0 end
    if type(unit) ~= "number" or unit < 1 then unit = 200 end
    if n < unit then return 1 end
    local v = math.floor(n / unit)
    if type(cap) ~= "number" or cap < 1 then cap = 1 end
    if v > cap then v = cap end
    if v < 1 then v = 1 end
    return v
end
if _G.FORGE_TEST then _G.FORGE_ADAPTIVE_N = adaptive_n end

-- ============================================================================
-- 12. 每槽位派生缓存（scope / own / 世代）
-- ============================================================================
-- 槽位派生：默认（关闭所有功能）时一次都不调用；任一功能打开时每枚弹幕每世代一次。
-- 世代变化（类型变了 = 槽位被复用）→ 清掉绑定在旧弹幕上的追踪/物理/锁定状态。
local function ensure_profile(p, id, s, wpn)
    local t = get_int(H.f_type, p, -1)
    if s.pcv == cfg_version and s.pt == t then
        if wpn ~= nil then s.wpn = wpn end
        return s
    end
    s.pcv, s.pt = cfg_version, t
    if wpn ~= nil then s.wpn = wpn end
    local frd = get_bool(H.f_friendly, p, false)
    local hst = get_bool(H.f_hostile, p, false)
    s.frd, s.hst = frd, hst
    s.own = (H.f_owner and S.env_my_player_ok
             and get_int(H.f_owner, p, -1) == S.env_my_player) or false
    s.scope = (frd or hst) and in_scope(p, s.wpn) or false
    -- 世代变化 → 重置追踪/物理/锁定（不清 wpn：它是这一代的武器）
    if s.tracking then s.tracking = false; tracked_n = tracked_n - 1 end
    s.tgt, s.tkind, s.iv, s.last = nil, nil, nil, nil
    s.cool = nil
    s.age, s.af, s.nh, s.hits = 0, nil, nil, 0
    s.pvx, s.pvy, s.pf, s.pdot = nil, nil, nil, nil
    s.bounces = 0
    s.spx, s.spy, s.spvx, s.spvy, s.spf = nil, nil, nil, nil, nil
    s.net, s.ndx, s.ndy = nil, nil, nil
    s.ls, s.lp = nil, nil
    return s
end

-- ============================================================================
-- 13. 帧号（Main.get_GameUpdateCount，0 参静态 → uint；方法表 8856 行）
--     AI 热路径用 tick_frame（每帧只反射 1 次，见 §17）；这里给非逐帧路径用。
-- ============================================================================
local function game_frame_now()
    if not H.get_update_count then return nil end
    local v = patch.invoke(H.get_update_count)      -- argc 已在安装期核对为 0
    if type(v) == "number" then return v end
    return nil
end

-- 拿不到游戏帧号时的退路：用 os.clock() 折算成「帧」（60 帧/秒）。
-- 作用只是给限流一个单调递增的时间轴，精度足够（不参与任何游戏逻辑判定）。
local function fallback_frame()
    return math.floor(now_cpu() * 60)
end

-- ============================================================================
-- 14. C 组：弹幕属性改写（在弹幕刚生成时执行一次）
--     返回 base：最终值 + raw 原始值（副本按 apply_overrides_to_copies 取用）
-- ============================================================================
local function apply_overrides(p, s)
    local base = {}
    local raw = {}
    base.raw = raw

    -- ---- 速度 ----
    local vx, vy = get_vec2(H.f_velocity, p)
    if not vx then vx, vy = 0, 0 end
    raw.vx, raw.vy = vx, vy
    if cfg.velocity_percent ~= 100 then
        local k = cfg.velocity_percent / 100
        vx, vy = vx * k, vy * k
        set_vec2_safe(H.f_velocity, p, vx, vy)
    end
    base.vx, base.vy = vx, vy

    -- ---- 伤害 ----
    raw.damage = get_int(H.f_damage, p, nil)
    base.damage = raw.damage
    if raw.damage and cfg.damage_percent ~= 100 then
        local d = math.floor(raw.damage * cfg.damage_percent / 100)
        if d < 1 then d = 1 end
        if set_int_safe(H.f_damage, p, d) then base.damage = d end
    end

    -- ---- 击退 ----
    raw.knockback = get_float(H.f_knockback, p, nil)
    base.knockback = raw.knockback
    if raw.knockback and cfg.knockback_percent ~= 100 then
        local kb = raw.knockback * cfg.knockback_percent / 100
        if set_float_safe(H.f_knockback, p, kb) then base.knockback = kb end
    end

    -- ---- 体型 ----
    raw.scale = get_float(H.f_scale, p, nil)
    base.scale = raw.scale
    if raw.scale and cfg.scale_percent ~= 100 then
        local sc = raw.scale * cfg.scale_percent / 100
        if sc < 0.01 then sc = 0.01 end
        if set_float_safe(H.f_scale, p, sc) then base.scale = sc end
    end
    if s and cfg.lock_scale and base.scale then s.ls = base.scale end

    -- ---- 存活时间 ----
    raw.timeleft = get_int(H.f_timeleft, p, nil)
    base.timeleft = raw.timeleft
    if raw.timeleft and cfg.lifetime_percent ~= 100 then
        local t = math.floor(raw.timeleft * cfg.lifetime_percent / 100)
        if t < 1 then t = 1 end
        if set_int_safe(H.f_timeleft, p, t) then base.timeleft = t end
    end

    -- ---- 穿透 ----
    -- Projectile.penetrate 不是工作区已验证符号，取不到就整段跳过（功能静默失效）
    raw.pierce = get_int(H.f_penetrate, p, nil)
    base.pierce = raw.pierce
    if raw.pierce and raw.pierce >= 0 and cfg.pierce_bonus > 0 then
        local pv = raw.pierce + cfg.pierce_bonus
        if set_int_safe(H.f_penetrate, p, pv) then base.pierce = pv end
    end
    if s and cfg.lock_pierce and base.pierce then s.lp = base.pierce end

    -- ---- §4.4-⑥ 无敌帧穿透：usesLocalNPCImmunity / localNPCHitCooldown ----
    if cfg.ignore_npc_immunity then
        set_bool(H.f_uses_local_immunity, p, true)
        local cd = cfg.local_immunity_frames
        if type(cd) ~= "number" or cd < 1 then cd = 10 end
        set_int(H.f_local_hit_cooldown, p, cd)
    end

    -- ---- §4.4-⑥ 暴击传递（源弹幕自己的 bonusCritChance 记到 base 上）----
    base.crit = get_int(H.f_bonus_crit, p, nil)

    stats.overrides = stats.overrides + 1
    return base
end

-- 属性改写是否对副本生效
local function copy_source(base)
    if cfg.apply_overrides_to_copies then return base end
    return base.raw
end

-- ============================================================================
-- 15. B 组：多重射击
-- ============================================================================
-- 第 j 份副本相对原弹道的旋转角（弧度）
-- ★ v1.0.3：所有模式都不给 0 角（0 角 = 与已有弹幕/第 1 层副本完全重叠）。
local function copy_angle(j, n)
    local total = cfg.spread_angle_deg * math.pi / 180
    local mode = cfg.spread_mode
    if mode == 1 then                          -- 环形：整圈均匀，但整体偏半格
        return ((j + 0.5) / n) * 2 * math.pi
    elseif mode == 2 then                      -- 随机：夹角内随机，至少偏一小格
        local a = (math.random() - 0.5) * total
        local min_a = total * 0.02
        if math.abs(a) < min_a then a = (a >= 0 and min_a or -min_a) end
        return a
    elseif mode == 3 then                      -- 同向：方向一致（靠出生位置错开）
        return 0
    end
    -- 扇形：把 n 份副本均匀放进 (n+1) 个间隔里 → 没有任何一份落在 0 角上
    return -total / 2 + ((j + 1) / (n + 1)) * total
end

-- 相邻两份副本之间的「半格」步长（层与层之间错开半格用）
local function half_step(count)
    if count < 1 then return 0 end
    local total = cfg.spread_angle_deg * math.pi / 180
    if cfg.spread_mode == 1 then return math.pi / count end
    if cfg.spread_mode == 3 then return 0 end
    return total / (2 * count)
end

-- 生成后的公共收尾：登记副本 + 记录槽位派生 + 物理组/无敌帧/暴击（都在生成路径，非逐帧）
local function finish_new_projectile(cp, src_for_crit)
    local id = get_int(H.f_who_am_i, cp, -1)
    if id >= 0 and id < K.MAX_PROJ_SLOTS then
        local s = slot_of(id)
        s.wpn = src_for_crit and src_for_crit.wpn or s.wpn
        ensure_profile(cp, id, s, s.wpn)
        local rec = { id = id, t = get_int(H.f_type, cp, -1), tl = get_int(H.f_timeleft, cp, 0) }
        local n = S.copy_ids.n + 1
        S.copy_ids[n] = rec
        S.copy_ids.n = n
    end
    -- §4.4-⑤ 穿墙（生成时写一次；开启时每帧还会维持，见 do_physics）
    if cfg.physics_pass_wall then set_bool(H.f_tile_collide, cp, false) end
    -- §4.4-⑥ 无敌帧穿透
    if cfg.ignore_npc_immunity then
        set_bool(H.f_uses_local_immunity, cp, true)
        local cd = cfg.local_immunity_frames
        if type(cd) ~= "number" or cd < 1 then cd = 10 end
        set_int(H.f_local_hit_cooldown, cp, cd)
    end
    -- §4.4-⑥ 暴击传递
    if cfg.crit_transfer and src_for_crit and src_for_crit.crit then
        set_int(H.f_bonus_crit, cp, src_for_crit.crit + (cfg.crit_bonus or 0))
    end
    return cp
end

-- 生成一份副本，并按 src 精确改写它的属性。返回副本对象 + 描述表（失败返回 nil）。
-- ★ argc = method_param_count(M_new_projectile)：实参个数必须精确等于形参个数（硬规则 #3）。
--   不能直接用 #template —— Hook 收到的 args 里最后一个参数（1.4.5.8 的
--   NewProjectileModifier 委托）常常是 nil，Lua 表的 # 会把它算成 12，
--   而底层 invoke 要的是 13 个实参（多出来的那个补 nil 也要显式传）。
local function make_one_copy(template, argc, src, nsx, nsy, off, frame)
    if not shot_budget_take(frame) then return nil end
    if not frame_budget_take(frame) then return nil end
    local dup = {}
    for i = 1, argc do dup[i] = template[i] end

    S.spawning = S.spawning + 1
    local ok, r = pcall(patch.invoke, H.new_projectile, unpack(dup, 1, argc))
    S.spawning = S.spawning - 1

    if not ok then
        if not S.spawn_warned then
            S.spawn_warned = true
            log_warn("生成副本失败: " .. tostring(r))
        end
        dom_err(D.newproj, "invoke NewProjectile 失败: " .. tostring(r))
        return nil
    end
    if type(r) ~= "number" or r < 0 then return nil end

    local cp = get_projectile_at(r)
    if not cp then return nil end

    -- 把副本沿它自己的飞行方向挪开一点，出生瞬间不再与原弹幕叠在一起。
    local cpx, cpy = src.px, src.py
    if type(cpx) == "number" and type(cpy) == "number" then
        local len = math.sqrt(nsx * nsx + nsy * nsy)
        if len > 1e-6 then
            cpx = cpx + (nsx / len) * off
            cpy = cpy + (nsy / len) * off
            set_vec2_safe(H.f_position, cp, cpx, cpy)
        end
    end

    local child = { vx = nsx, vy = nsy, px = cpx, py = cpy, layer = (src.layer or 0) + 1 }
    child.raw = child
    child.crit = src.crit
    child.wpn = src.wpn

    set_vec2_safe(H.f_velocity, cp, nsx, nsy)
    if src.damage then
        -- §4.4-⑥ 每份副本是否满伤害：默认关（= 用副本伤害倍率，与 v1.1.0 一致）
        local d
        if cfg.copy_full_damage then
            d = src.damage
        else
            d = math.floor(src.damage * cfg.copy_damage_percent / 100)
        end
        if d < 0 then d = 0 end
        if set_int_safe(H.f_damage, cp, d) then child.damage = d end
    end
    if src.scale then
        if set_float_safe(H.f_scale, cp, src.scale) then child.scale = src.scale end
    end
    if src.timeleft then
        if set_int_safe(H.f_timeleft, cp, src.timeleft) then child.timeleft = src.timeleft end
    end
    if src.knockback then
        if set_float_safe(H.f_knockback, cp, src.knockback) then child.knockback = src.knockback end
    end
    if src.pierce then
        if set_int_safe(H.f_penetrate, cp, src.pierce) then child.pierce = src.pierce end
    end

    finish_new_projectile(cp, child)
    local s = slot[get_int(H.f_who_am_i, cp, -1) or -1]
    if s then
        if cfg.lock_scale and child.scale then s.ls = child.scale end
        if cfg.lock_pierce and child.pierce then s.lp = child.pierce end
    end

    stats.copies = stats.copies + 1
    -- 状态页只读这些计数器（面板本身零反射）
    local sec = S.budget_window_start
    if type(sec) ~= "number" or sec == 0 then sec = now_seconds() end
    if stats.sec ~= sec then
        stats.last_sec_copies = stats.sec_copies
        if stats.last_sec_copies > stats.peak_sec_copies then
            stats.peak_sec_copies = stats.last_sec_copies
        end
        stats.sec, stats.sec_copies = sec, 0
    end
    stats.sec_copies = stats.sec_copies + 1
    if stats.copies_frame_no ~= frame then
        stats.copies_frame_no, stats.copies_frame = frame, 0
    end
    stats.copies_frame = stats.copies_frame + 1
    log_debug("生成副本 #%d（层 %d，速度 %.2f,%.2f）", r, child.layer, nsx, nsy)
    return cp, child
end

-- 扇形/环形/随机/同向四种散射：逐份生成，需要连锁时递归生成下一层
local function spawn_copies(template, src, gen, state, frame)
    local n = #template
    -- 安全阀：回放 NewProjectile 必须带齐实参。用 method_param_count 精确核对
    -- （硬规则 #3：实参个数少一个就是越界读栈，pcall 拦不住）。
    if not H.new_projectile then
        if not S.spawn_warned then
            S.spawn_warned = true
            log_warn("NewProjectile 句柄为空，已跳过复制以保证安全")
        end
        return
    end
    local want = H.new_projectile_argc
    if want then
        if n > want then
            if not S.spawn_warned then
                S.spawn_warned = true
                log_warn(string.format(
                    "NewProjectile 实参个数(%d) 超过形参个数(%d)，已跳过复制以保证安全", n, want))
            end
            return
        end
    elseif n < 8 then
        if not S.spawn_warned then
            S.spawn_warned = true
            log_warn(string.format("NewProjectile 实参数量异常(%d)，已跳过复制以保证安全", n))
        end
        return
    end
    local argc = want or n      -- 缺尾的 nil 参数由 make_one_copy 补足

    local count = cfg.extra_copies
    if type(count) ~= "number" or count <= 0 then return end

    local vk = cfg.copy_velocity_percent / 100

    -- 第 2 层及以后整体错开「半格」，避免与第 1 层一一重叠。
    local twist = 0
    if gen > 1 then twist = (gen - 1) * half_step(count) end

    for j = 0, count - 1 do
        if state.made >= K.MAX_CHAIN_TOTAL then return end
        if not budget_take() then return end

        local ang = copy_angle(j, count) + twist
        local c, sn = math.cos(ang), math.sin(ang)
        local nsx = (src.vx * c - src.vy * sn) * vk
        local nsy = (src.vx * sn + src.vy * c) * vk

        local cp, child = make_one_copy(template, argc, src, nsx, nsy, 6 + 2 * (j % 3), frame)
        if cp then
            state.made = state.made + 1
            state.layers[gen] = (state.layers[gen] or 0) + 1
            if gen <= cfg.chain_depth then
                spawn_copies(template, copy_source(child), gen + 1, state, frame)
            end
        end
    end
end

-- ============================================================================
-- 16. §3.7-② 全局共享候选目标表（每 global_scan_interval 帧只扫一次 Main.npc）
--     所有弹幕共享 cand.* + 网格；每枚弹幕自己的索敌退化成「查 9 个格子」。
-- ============================================================================
local function cell_key(kx, ky)
    return (kx + K.CELL_OFF) * K.CELL_SPAN + (ky + K.CELL_OFF)
end

-- 按 dmin2 升序插入候选缓冲区（m = 当前数量）。返回新的 m。
-- 缓冲区上界 = MAX_CANDIDATES + 64：超了就直接丢掉最远的那个（插入已排序 → 末尾最远）。
local function cand_insert(id, x, y, d2, rk, lf, m)
    local cap = K.MAX_CANDIDATES + 64
    if m >= cap and d2 >= cand.dmin2[m] then return m end
    local pos = m + 1
    while pos > 1 and cand.dmin2[pos - 1] > d2 do
        cand.npc[pos], cand.cx[pos], cand.cy[pos] = cand.npc[pos-1], cand.cx[pos-1], cand.cy[pos-1]
        cand.dmin2[pos], cand.rank[pos], cand.life[pos] = cand.dmin2[pos-1], cand.rank[pos-1], cand.life[pos-1]
        pos = pos - 1
    end
    cand.npc[pos], cand.cx[pos], cand.cy[pos], cand.dmin2[pos], cand.rank[pos], cand.life[pos]
        = id, x, y, d2, rk, lf
    m = m + 1
    if m > cap then m = m - 1 end
    return m
end

-- NPC 是否可被追踪：
--   ③ 优先合成一次 NPC.CanBeChasedBy(object, bool)（手机版有；方法表 10218 行，2 形参）
--      —— 它内部就是 active && chaseable && lifeMax > 5 && !dontTakeDamage && !friendly
--      && !immortal，一次 invoke 顶 6 次字段读。
--   取不到句柄 → 回退到常量字段句柄缓存 + **第一行先读 active 早退** 的精简版。
local function can_be_chased(npc)
    if H.can_be_chased then
        -- attacker 传 nil（object 可为 null；参考库 one-hit-loot 也这么传）
        return patch.invoke(H.can_be_chased, npc, nil, false) == true
    end
    if not get_bool(H.f_npc_active, npc, false) then return false end     -- ① 第一行早退
    if not get_bool(H.f_npc_chaseable, npc, true) then return false end
    if get_int(H.f_npc_life_max, npc, 0) <= 5 then return false end
    if get_bool(H.f_npc_dont_take_damage, npc, false) then return false end
    if get_bool(H.f_npc_immortal, npc, false) then return false end
    if get_bool(H.f_npc_friendly, npc, false) then return false end
    return true
end

-- 一次全局扫描（真正干活的只有这里；每 global_scan_frames 帧一次）
local function scan_candidates(frame)
    local t0 = now_cpu()
    D.cand.calls = D.cand.calls + 1

    -- ---- 1) 玩家快照（敌方弹幕追玩家 + 候选裁剪都要用）----
    pl_list_n = 0
    local pl_arr = H.f_main_player and patch.get_field_value(H.f_main_player, nil, "object")
    if pl_arr then
        local pn = array_count(pl_arr, 8)
        if pn > 64 then pn = 64 end
        for i = 0, pn - 1 do
            local pl = patch.array_at(pl_arr, i)
            if pl == nil then break end
            if get_bool(H.f_player_active, pl, false)
                and not get_bool(H.f_player_dead, pl, false) then
                local x, y = get_vec2(H.f_player_position, pl)
                if x then
                    local cx = x + get_int(H.f_player_width, pl, 0) * 0.5
                    local cy = y + get_int(H.f_player_height, pl, 0) * 0.5
                    pl_cx[i], pl_cy[i], pl_seen[i] = cx, cy, frame
                    pl_list_n = pl_list_n + 1
                    pl_list[pl_list_n] = i
                end
            end
        end
    end
    cand.pn = pl_list_n

    -- ---- 2) NPC 扫描（全表只扫这一次）----
    local m = 0
    local arr = H.f_main_npc and patch.get_field_value(H.f_main_npc, nil, "object")
    if arr then
        local nn = array_count(arr, K.MAX_NPC_SLOTS)
        for i = 0, nn - 1 do
            local npc = patch.array_at(arr, i)
            if npc == nil then break end
            -- 第一行先读 active 早退（③ 的回退分支也一样）
            if get_bool(H.f_npc_active, npc, false) and can_be_chased(npc) then
                local x, y = get_vec2(H.f_npc_position, npc)
                if x then
                    local cx = x + get_int(H.f_npc_width, npc, 0) * 0.5
                    local cy = y + get_int(H.f_npc_height, npc, 0) * 0.5
                    -- 距最近玩家的距离（裁剪依据：优先服务玩家附近的战斗）
                    local dmin2
                    for k = 1, pl_list_n do
                        local px, py = pl_cx[pl_list[k]], pl_cy[pl_list[k]]
                        local dx, dy = cx - px, cy - py
                        local d2 = dx * dx + dy * dy
                        if dmin2 == nil or d2 < dmin2 then dmin2 = d2 end
                    end
                    if dmin2 == nil then dmin2 = 0 end     -- 没有玩家（极端情况）→ 不裁剪
                    local rk = 0
                    if get_bool(H.f_npc_boss, npc, false) then
                        rk = 2
                    elseif get_int(H.f_npc_rarity, npc, 0) >= 1 then
                        rk = 1                              -- 精英（原版稀有生物标记）
                    end
                    local lmax = get_int(H.f_npc_life_max, npc, 0)   -- 只读一次（反射调用要省）
                    m = cand_insert(i, cx, cy, dmin2, rk, lmax, m)
                    npc_seen[i], npc_cx[i], npc_cy[i] = frame, cx, cy
                    npc_rank[i], npc_life[i] = rk, lmax
                end
            end
        end
    end

    -- ---- 3) 裁剪：最近的 K 个（数组已按 dmin2 升序）+ 距玩家 prune_r2 内的 ----
    local keep = 0
    cand.cropped = 0
    for i = 1, m do
        if i <= nearest_k or cand.dmin2[i] <= prune_r2 then
            keep = keep + 1
            if keep ~= i then
                cand.npc[keep], cand.cx[keep], cand.cy[keep] = cand.npc[i], cand.cx[i], cand.cy[i]
                cand.dmin2[keep], cand.rank[keep], cand.life[keep] = cand.dmin2[i], cand.rank[i], cand.life[i]
            end
            if keep >= K.MAX_CANDIDATES then break end
        elseif cand.dmin2[i] > prune_r2 then
            cand.cropped = cand.cropped + (m - i + 1)
            break                                   -- 已升序：后面全部更远
        end
    end
    for i = keep + 1, m do
        cand.npc[i], cand.cx[i], cand.cy[i] = nil, nil, nil
        cand.dmin2[i], cand.rank[i], cand.life[i] = nil, nil, nil
    end
    cand.n = keep

    -- ---- 4) 网格分桶（格子边长 = 索敌半径 → 半径内的目标必在 3×3 格内）----
    local cells = {}
    cand.cells = cells
    local cs = cand.cell_size
    if cs < 1 then cs = 1 end
    for i = 1, keep do
        local kx = math.floor(cand.cx[i] / cs)
        local ky = math.floor(cand.cy[i] / cs)
        local key = cell_key(kx, ky)
        local c = cells[key]
        if not c then c = { n = 0 }; cells[key] = c end
        local cn = c.n + 1
        c[cn] = i
        c.n = cn
    end

    cand.frame = frame
    stats.perf.scans_frame = stats.perf.scans_frame + 1
    stats.perf.scans_total = stats.perf.scans_total + 1
    local dt = (now_cpu() - t0) * 1000
    if dt > 0 then stats.perf.scan_ms = stats.perf.scan_ms + dt end
    if stats.perf.scans_total > 0 then
        stats.perf.avg_scan_ms = stats.perf.scan_ms / stats.perf.scans_total
    end
    D.cand.hits = D.cand.hits + 1
    log_debug("共享候选表：可追踪 %d 个（裁剪掉 %d）", keep, cand.cropped)
end

-- 该不该扫描（每 global_scan_frames 帧一次；拿不到帧号时按 帧/60 秒 折算）
local function scan_due(frame)
    if frame == nil then return false end
    if cand.frame ~= nil and frame - cand.frame < global_scan_frames then return false end
    return true
end

-- v2.2.0：命中特效不能等下一次全局扫描（否则第一发/扫描间隔内“看起来没生效”）。
--   只在命中帧、且候选表为空或已过期时补扫一次；正常情况下零额外开销。
local function ensure_candidates(frame)
    if frame == nil then return end
    if cand.frame == nil or cand.n == 0 or (frame - cand.frame) >= 2 then
        scan_candidates(frame)
    end
end

-- 查网格找目标（pri_id = 索敌策略；返回 NPC 数组下标与距离²）
-- 格子边长 = 索敌半径，所以「半径内的目标」必然落在以弹幕所在格为中心的 3×3 格内。
local function find_candidate(px, py, range2)
    if cand.n == 0 then return nil end
    local cs = cand.cell_size
    local kx = math.floor(px / cs)
    local ky = math.floor(py / cs)
    local cells = cand.cells
    local mode = pri_id
    local best, best_d2, best_rank, best_life
    for dx = -1, 1 do
        local base = (kx + dx + K.CELL_OFF) * K.CELL_SPAN
        for dy = -1, 1 do
            local c = cells[base + ky + dy + K.CELL_OFF]
            if c then
                local cn = c.n
                for i = 1, cn do
                    local idx = c[i]
                    local tx, ty = cand.cx[idx], cand.cy[idx]
                    local ddx, ddy = tx - px, ty - py
                    local d2 = ddx * ddx + ddy * ddy
                    if d2 <= range2 then
                        local rk = cand.rank[idx]
                        local lf = cand.life[idx]
                        local better
                        if best == nil then
                            better = true
                        elseif mode == K.PRI_NEAREST then
                            better = d2 < best_d2
                        elseif mode == K.PRI_BOSS then
                            better = (rk == 2 and best_rank ~= 2)
                                or (rk == best_rank and d2 < best_d2)
                        elseif mode == K.PRI_HP then
                            better = (lf > best_life) or (lf == best_life and d2 < best_d2)
                        else   -- 混合：Boss > 精英 > 更近 > 血更多（照 homing-projectile）
                            better = (rk > best_rank)
                                or (rk == best_rank and (d2 < best_d2
                                    or (d2 == best_d2 and lf > best_life)))
                        end
                        if better then
                            best, best_d2, best_rank, best_life = cand.npc[idx], d2, rk, lf
                        end
                    end
                end
            end
        end
    end
    return best, best_d2
end

-- 最近的活跃玩家下标（敌方弹幕用；玩家名单来自最近一次扫描的快照）
local function nearest_player(px, py)
    local best, best_d2
    for i = 1, pl_list_n do
        local idx = pl_list[i]
        local dx, dy = pl_cx[idx] - px, pl_cy[idx] - py
        local d2 = dx * dx + dy * dy
        if best_d2 == nil or d2 < best_d2 then best, best_d2 = idx, d2 end
    end
    return best, best_d2
end

-- ============================================================================
-- 17. 追踪：名额管理 / 动态扫描间隔 / 转向
-- ============================================================================
local function tracked_push(id)
    local n = tracked_ids.n + 1
    tracked_ids[n] = id
    tracked_ids.n = n
end

local function release_tracking(s, frame)
    if s.tracking then
        s.tracking = false
        tracked_n = tracked_n - 1
        if tracked_n < 0 then tracked_n = 0 end
    end
    if s.tgt ~= nil then s.cool = frame or cur_frame or fallback_frame() end
    s.tgt, s.tkind = nil, nil
end

-- v2.2.0 目标切换冷却：锁定后 N 帧内不重评；0 = 不限制。
--   冷却按弹幕 index 缓存在 s.cool；换目标成功时清空。
local function switch_allowed(s, frame)
    local cd = cfg.target_switch_cooldown
    if type(cd) ~= "number" or cd <= 0 then return true end
    if s.cool ~= nil and frame ~= nil and (frame - s.cool) <= cd then
        stats.perf.skipped.cooldown = stats.perf.skipped.cooldown + 1
        return false
    end
    return true
end

-- 超限时踢掉一个「非自己」的追踪名额（带游标，O(1) 摊销）。
-- ★ §3.7-⑨：超限时优先服务玩家自己的弹幕。
local function evict_one_nonown()
    local n = tracked_ids.n
    if n == 0 then return false end
    local steps, maxsteps = 0, K.MAX_TRACKED * 2
    while steps < maxsteps do
        steps = steps + 1
        evict_cursor = evict_cursor + 1
        if evict_cursor > n then evict_cursor = 1 end
        local id = tracked_ids[evict_cursor]
        local s = id and slot[id]
        if s and s.tracking and s.own ~= true then
            release_tracking(s, frame)
            return true
        end
    end
    return false
end

local function acquire_tracking(s, id)
    if s.tracking then return true end
    if tracked_n < K.MAX_TRACKED then
        s.tracking = true; tracked_n = tracked_n + 1; tracked_push(id)
        return true
    end
    if s.own and evict_one_nonown() then
        s.tracking = true; tracked_n = tracked_n + 1; tracked_push(id)
        return true
    end
    stats.perf.skipped.limit = stats.perf.skipped.limit + 1
    return false
end

-- 非关键桶：压缩追踪名单（把已释放的名额移出去，保证名单长度有界）
local function compact_tracked()
    local n = tracked_ids.n
    local w = 0
    for i = 1, n do
        local id = tracked_ids[i]
        local s = id and slot[id]
        if s and s.tracking then
            w = w + 1
            tracked_ids[w] = id
        end
    end
    for i = w + 1, n do tracked_ids[i] = nil end
    tracked_ids.n = w
    if evict_cursor > w then evict_cursor = 0 end
end

-- §3.7-⑦ 动态扫描间隔：速度越快扫得越勤；慢的/静止的拉长到基础间隔的 2 倍，快的缩到 1/4。
--   （思路参考 参考库/efmod/旧模组-CPP-123/弹幕追踪.cpp 的
--     dynamicInterval = base * stickySpeed/(speed+0.1) —— 只借思路，实现完全不同。）
--   手感优先档不做「拉长到 2 倍」，间隔上限就是基础值。
local function compute_interval(speed, is_enemy)
    local base = is_enemy and enemy_scan_frames or npc_scan_frames
    if type(base) ~= "number" or base < 1 then base = 6 end
    local dyn = math.floor(base * K.DYNAMIC_SPEED_REF / (speed + 0.5))
    local lo = math.max(1, math.floor(base / K.INTERVAL_MIN_DIV))
    local hi = (perf_id == K.PERF_FEEL) and base or (base * K.INTERVAL_MAX_MULT)
    if dyn < lo then dyn = lo end
    if dyn > hi then dyn = hi end
    stats.perf.last_interval = dyn
    return dyn
end

-- 把「当前方向」朝「目标方向」转 turn×夹角（用角度做）。
--   ★ 为什么不用线性插值：v1.1.0 的 nx = ux + (dx-ux)*turn 在「目标正在正后方」
--     （夹角 = 180°）时会退化成零向量方向，弹幕永远转不过来；用角度插值就没有这个坑。
--   （默认 homing_enabled 关闭，所以这个改动不影响任何默认行为。）
local function steer_dir(vx, vy, dx, dy, turn)
    local cur = math.atan(vy, vx)
    local want = math.atan(dy, dx)
    local diff = want - cur
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    local na = cur + diff * turn
    return math.cos(na), math.sin(na)
end

-- 把一枚弹幕的速度方向朝目标旋转。
-- interval = 相邻两次转向相隔的帧数，用来做转向强度补偿：
--   ★ 逐帧转向是「每帧转 turn」，隔 interval 帧转一次要等效就不能简单 turn*interval
--     （默认 18% × 6 = 108% > 100%，会把弹道瞬间锁死到目标方向上），
--     这里用等价的复合公式 1-(1-turn)^interval：interval=1 时与原逐帧完全一致。
local function apply_turn(instance, s, tx, ty, px, py, vx, vy, speed, interval)
    local dx, dy = tx - px, ty - py
    local dist = math.sqrt(dx * dx + dy * dy)

    -- §4.4-③ 到目标一定距离内停手（0 = 用原版 24 像素死区，手感不变）
    local stop = K.STOP_DISTANCE_MIN
    if cfg.homing_stop_distance > stop then stop = cfg.homing_stop_distance end
    if dist <= stop then return false end

    dx, dy = dx / dist, dy / dist

    local turn = cfg.homing_strength / 100
    -- §4.4-③ 强度随飞行时间递增（60 帧内从 0 线性升到 100%）
    if cfg.homing_ramp then
        local r = (s.age or 0) / 60
        if r > 1 then r = 1 end
        turn = turn * r
    end
    if interval > 1 then turn = 1 - (1 - turn) ^ interval end
    if turn > 1 then turn = 1 elseif turn < 0 then turn = 0 end

    local nx, ny = steer_dir(vx, vy, dx, dy, turn)
    -- v2.2.0 速度覆写间隔：只决定「多久写一次速度」，写成多少仍由速度倍率负责。
    local si = cfg.speed_override_interval
    if type(si) ~= "number" or si < 1 then si = 1 end
    local fr = cur_frame or 0
    local do_write = true
    if si > 1 and s.sw ~= nil and fr - s.sw < si then do_write = false end
    if do_write then
        set_vec2(H.f_velocity, instance, nx * speed, ny * speed)
        s.sw = fr
        stats.speed_writes = stats.speed_writes + 1

        -- §3.7-④ netUpdate 节流：只在「朝向变化超过 net_angle_deg 度」且「距上次同步 ≥
        --   net_update_min_frames 帧」时置位；net_sync 关掉后一个网络字段都不写。
        if cfg.net_sync and H.f_net_update then
            local ox, oy = s.ndx, s.ndy
            if ox == nil or (nx * ox + ny * oy) < net_angle_cos then
                local nf = cfg.net_update_min_frames
                if type(nf) ~= "number" or nf < 1 then nf = 10 end
                if s.net == nil or fr - s.net >= nf then
                    s.net = fr
                    s.ndx, s.ndy = nx, ny
                    set_bool(H.f_net_update, instance, true)
                end
            end
        else
            s.ndx, s.ndy = nx, ny
        end
    end

    stats.steers = stats.steers + 1
    stats.perf.steers_frame = stats.perf.steers_frame + 1
    stats.perf.steers_total = stats.perf.steers_total + 1
    D.track.hits = D.track.hits + 1
    return true
end

-- ============================================================================
-- 18. §4.4-⑤ 弹幕物理组（默认全关 → 一点开销都没有）
-- ============================================================================
-- 返回生效后的 (vx, vy)；回收弹幕时返回 nil（调用方据此早退）。
local function do_physics(instance, s, px, py, vx, vy, speed, frame)
    D.phys.calls = D.phys.calls + 1

    -- 穿墙：每帧维持（有些 AI 会把 tileCollide 改回来；生成时已写过一次）
    if cfg.physics_pass_wall then set_bool(H.f_tile_collide, instance, false) end

    -- 出生点 / 出生速度（归位与直线锁都要用）
    if s.spx == nil then
        s.spx, s.spy, s.spvx, s.spvy, s.spf = px, py, vx, vy, frame
    end

    -- 无视重力/阻力：锁成「出生方向 + 出生速度」的绝对直线（位置按帧数外推）。
    --   ★ 这是**覆盖式**的：它会同时消掉重力与空气阻力，也会盖住原版 AI 对速度的改动。
    --     默认关闭；开启后与「环绕/归位/反弹」不叠加（这里直接返回）。
    if cfg.physics_no_gravity then
        local dt = frame - (s.spf or frame)
        set_vec2(H.f_velocity, instance, s.spvx, s.spvy)
        set_vec2(H.f_position, instance, s.spx + s.spvx * dt, s.spy + s.spvy * dt)
        s.pvx, s.pvy, s.pf = s.spvx, s.spvy, frame
        D.phys.hits = D.phys.hits + 1
        return s.spvx, s.spvy
    end

    -- 反弹次数：用「速度方向反转」（点积 < -0.5）近似判定一次反弹；超限就回收弹幕。
    --   ★ 本代加载器读不到原版内部的反弹计数，这里是自己数的近似值（默认关闭）。
    local pvx, pvy = s.pvx, s.pvy
    if pvx and s.pf == frame - 1 and cfg.physics_bounce_limit > 0 then
        local l1 = math.sqrt(pvx * pvx + pvy * pvy)
        if l1 > 0.1 and speed > 0.1 then
            local dot = (pvx * vx + pvy * vy) / (l1 * speed)
            if dot < -0.5 then
                s.bounces = (s.bounces or 0) + 1
                D.phys.hits = D.phys.hits + 1
                if s.bounces > cfg.physics_bounce_limit then
                    set_bool(H.f_active, instance, false)      -- 回收
                    stats.recycled = stats.recycled + 1
                    return nil
                end
            end
        end
    end
    s.pvx, s.pvy, s.pf = vx, vy, frame

    local outx, outy = vx, vy
    -- 归位：离开出生点超过索敌半径就朝出生点转回去
    if cfg.physics_return_home then
        local ddx, ddy = s.spx - px, s.spy - py
        local d2 = ddx * ddx + ddy * ddy
        local r = cfg.homing_range
        if type(r) ~= "number" or r < 1 then r = 1 end
        if d2 > r * r and speed > 0.1 then
            local dd = math.sqrt(d2)
            local nx, ny = steer_dir(outx, outy, ddx / dd, ddy / dd, 0.15)
            outx, outy = nx * speed, ny * speed
            set_vec2(H.f_velocity, instance, outx, outy)
            D.phys.hits = D.phys.hits + 1
        end
    end

    -- 环绕：每帧把速度方向绕锁定目标旋转 physics_orbit_percent/100 度
    --   （配合追踪会形成绕目标转圈；没有锁定目标时不生效）
    if cfg.physics_orbit_percent > 0 and s.tgt and s.tkind == 1 then
        local ang = (cfg.physics_orbit_percent / 100) * math.pi / 180
        local c, sn = math.cos(ang), math.sin(ang)
        local nx = outx * c - outy * sn
        local ny = outx * sn + outy * c
        outx, outy = nx, ny
        set_vec2(H.f_velocity, instance, nx, ny)
        D.phys.hits = D.phys.hits + 1
    end
    return outx, outy
end

-- ============================================================================
-- 19. §4.4-④ 命中效果（命中判定 = Projectile.numHits 的增量，不新增钩子）
-- ============================================================================
-- 对单个 NPC 造成一次伤害。★ 这是写操作 → 只在非客机（host_readonly=false）时调用。
--   NPC.StrikeNPC(int Damage, float knockBack, int hitDirection, bool crit,
--                 bool fromNet, int owner) —— 手机版 6 形参（方法表 10201 行）
local function strike_one(npc, dmg, kb, dir, owner)
    if not (H.strike_npc and npc) then return false end
    if type(dmg) ~= "number" or dmg < 1 then dmg = 1 end
    if type(kb) ~= "number" then kb = 0 end
    if type(dir) ~= "number" then dir = 0 end
    if type(owner) ~= "number" then owner = 255 end
    return pcall(patch.invoke, H.strike_npc, npc, math.floor(dmg), kb, dir, false, false, owner)
end

-- 命中爆炸：对命中点半径内的候选 NPC 各打一次（候选表已经裁剪过，最多 96 个）
local function explosion_at(px, py, radius, dmg, kb, owner, skip_index)
    if radius <= 0 or dmg < 1 then return 0 end
    local arr = H.f_main_npc and patch.get_field_value(H.f_main_npc, nil, "object")
    if not arr then return 0 end
    local r2 = radius * radius
    local hit = 0
    for i = 1, cand.n do
        local nid = cand.npc[i]
        if nid ~= skip_index then
            local ddx, ddy = cand.cx[i] - px, cand.cy[i] - py
            if ddx * ddx + ddy * ddy <= r2 then
                local npc = patch.array_at(arr, nid)
                if npc and get_bool(H.f_npc_active, npc, false) then
                    local dir = (cand.cx[i] >= px) and 1 or -1
                    if strike_one(npc, dmg, kb, dir, owner) then hit = hit + 1 end
                end
            end
        end
    end
    return hit
end

-- 闪电连锁：从命中点开始，每次跳到半径内「还没被打过」的最近一个 NPC，伤害逐跳衰减 0.8
local function chain_at(px, py, radius, dmg, kb, owner, jumps, skip_index)
    if jumps <= 0 or dmg < 1 then return 0 end
    local arr = H.f_main_npc and patch.get_field_value(H.f_main_npc, nil, "object")
    if not arr then return 0 end
    local r2 = radius * radius
    local seen = {}
    local cx0, cy0 = px, py
    -- v2.2.0：连锁的第一跳跳过「刚命中的那个 NPC」，否则看起来像只打了一下。
    local skip = skip_index
    if skip == nil then
        local bd
        for i = 1, cand.n do
            local ddx, ddy = cand.cx[i] - px, cand.cy[i] - py
            local d2 = ddx * ddx + ddy * ddy
            if d2 <= r2 and (bd == nil or d2 < bd) then skip, bd = cand.npc[i], d2 end
        end
    end
    -- 只有一个目标时不要把自己跳掉（否则连锁看起来完全没生效）
    if skip ~= nil then
        local alt = false
        for i = 1, cand.n do
            if cand.npc[i] ~= skip then
                local ddx, ddy = cand.cx[i] - px, cand.cy[i] - py
                if ddx * ddx + ddy * ddy <= r2 then alt = true; break end
            end
        end
        if not alt then skip = nil end
    end
    local hit = 0
    for j = 1, jumps do
        local best_id, best_d2, best_x, best_y
        for i = 1, cand.n do
            local nid = cand.npc[i]
            if nid ~= skip and not seen[nid] then
                local ddx, ddy = cand.cx[i] - cx0, cand.cy[i] - cy0
                local d2 = ddx * ddx + ddy * ddy
                if d2 <= r2 and (best_d2 == nil or d2 < best_d2) then
                    best_id, best_d2, best_x, best_y = nid, d2, cand.cx[i], cand.cy[i]
                end
            end
        end
        if not best_id then break end
        seen[best_id] = true
        local npc = patch.array_at(arr, best_id)
        if npc and get_bool(H.f_npc_active, npc, false) then
            local d = dmg * (0.8 ^ (j - 1))
            if d < 1 then d = 1 end
            local dir = (best_x >= cx0) and 1 or -1
            if strike_one(npc, d, kb, dir, owner) then
                hit = hit + 1
                cx0, cy0 = best_x, best_y
            end
        end
    end
    return hit
end

-- 命中分裂：以命中点为出生点，按环形散开生成 N 份同类型弹幕。
--   ★ 这里必须给 NewProjectile 一个**真的** IEntitySource：PC 1.4.5.8 的
--     NewProjectile 里会拿它去 ApplyStatsFromSource / FindBannerToAssociateTo，
--     传 nil 有 NRE 风险。手机版有 Projectile.GetProjectileSource_FromThis()
--     （方法表里 0 参实例方法，返回 IEntitySource）——取不到就整段跳过（失败分支）。
local function split_at(instance, px, py, vx, vy, speed, frame)
    local n = cfg.hit_split_copies
    if type(n) ~= "number" or n <= 0 then return 0 end
    if not H.new_projectile or H.new_projectile_argc ~= 13 then
        dom_err(D.hit, "NewProjectile(13) 句柄不可用，命中分裂跳过")
        return 0
    end
    if not H.source_from_this then
        dom_err(D.hit, "取不到 GetProjectileSource_FromThis，命中分裂跳过")
        return 0
    end
    local owner = get_int(H.f_owner, instance, 255)
    -- 联机客机：NewProjectile 内部有 owner 断言（owner 必须是自己），不是自己的就跳过
    if S.env_net_mode_ok and S.env_net_mode ~= 0 and S.env_my_player_ok
        and owner ~= S.env_my_player then
        dom_err(D.hit, "联机下弹幕 owner 不是本机，命中分裂跳过")
        return 0
    end
    local ok_src, src = pcall(patch.invoke, H.source_from_this, instance)
    if not ok_src or src == nil then
        dom_err(D.hit, "取不到 IEntitySource，命中分裂跳过")
        return 0
    end
    local ptype = get_int(H.f_type, instance, -1)
    local dmg = get_int(H.f_damage, instance, 0)
    local kb = get_float(H.f_knockback, instance, 0)
    local crit = get_int(H.f_bonus_crit, instance, nil)
    if ptype < 0 then return 0 end
    local base_ang = math.atan(vy, vx)
    local step = 2 * math.pi / n
    local made = 0
    for j = 0, n - 1 do
        if not shot_budget_take(frame) then break end
        if not frame_budget_take(frame) then break end
        if not budget_take() then break end
        local ang = base_ang + step * (j + 0.5)
        local nsx, nsy = math.cos(ang) * speed, math.sin(ang) * speed
        S.spawning = S.spawning + 1
        local ok, r = pcall(patch.invoke, H.new_projectile, src, px, py, nsx, nsy,
            ptype, dmg, kb, owner, 0, 0, 0, nil)
        S.spawning = S.spawning - 1
        if ok and type(r) == "number" and r >= 0 then
            local cp = get_projectile_at(r)
            if cp then
                finish_new_projectile(cp, { crit = crit })
                made = made + 1
            end
        end
    end
    return made
end

-- 命中效果的统一入口（每枚弹幕每次 numHits 增长调用一次）
local function do_hit_effects(instance, s, px, py, vx, vy, speed, frame)
    -- 每帧最多处理 HIT_PER_FRAME_MAX 次（性能保护）
    if S.hit_frame ~= frame then
        S.hit_frame = frame
        S.hit_used = 0
    end
    if S.hit_used >= K.HIT_PER_FRAME_MAX then return end
    S.hit_used = S.hit_used + 1

    D.hit.calls = D.hit.calls + 1
    stats.hits = stats.hits + 1
    D.hit.hits = D.hit.hits + 1
    ensure_candidates(frame)

    local dmg = get_int(H.f_damage, instance, 0)
    local kb = get_float(H.f_knockback, instance, 0)
    local owner = get_int(H.f_owner, instance, 255)
    local dir = (vx >= 0) and 1 or -1

    -- ① 命中爆炸（溅射）
    if cfg.hit_explosion_radius > 0 then
        local d = math.floor(dmg * cfg.hit_explosion_damage_percent / 100 + 0.5)
        if d < 1 then d = 1 end
        -- 爆炸是命中点的溅射：连刚命中的目标一起算（否则单目标时看起来“没生效”）
        stats.explosion_hits = stats.explosion_hits
            + (explosion_at(px, py, cfg.hit_explosion_radius, d, kb, owner, nil) or 0)
    end
    -- ② 闪电连锁
    if cfg.hit_lightning_chain > 0 then
        local d = math.floor(dmg * cfg.hit_lightning_damage_percent / 100 + 0.5)
        if d < 1 then d = 1 end
        local skip = (s.tkind == 1) and s.tgt or nil
        stats.chain_hits = stats.chain_hits
            + (chain_at(px, py, cfg.hit_lightning_radius, d, kb, owner,
                cfg.hit_lightning_chain, skip) or 0)
    end
    -- ③ 命中吸血（治疗弹幕的 owner）
    if cfg.hit_lifesteal_percent > 0 then
        local heal = math.floor(dmg * cfg.hit_lifesteal_percent / 100)
        if heal >= 1 and H.player_heal then
            local pl = main_player_at(owner)
            if pl then pcall(patch.invoke, H.player_heal, pl, heal) end
        end
    end
    -- ④ 命中分裂
    if cfg.hit_split_copies > 0 then
        split_at(instance, px, py, vx, vy, speed, frame)
    end
end

-- ============================================================================
-- 20. 逐帧工作分档 + tick_interval 分桶（可放宽的活只在桶 1 跑）
-- ============================================================================
local function bucket_of()
    local n = cfg.tick_interval
    if type(n) ~= "number" or n < 1 then n = 1 end
    S.frame_no = S.frame_no + 1
    return (S.frame_no % n) + 1        -- Lua 下标 1 起；n = 1 时恒为 1（= 逐帧）
end

-- §4.4-⑦ 全局弹幕上限 + 超限自动回收（**只回收本模组生成的副本**，绝不动原版弹幕）
--   ★ 默认值 = 1000 = 原版上限 → 这个函数第一行就返回，零开销。
local function enforce_global_cap()
    local cap = cfg.global_projectile_cap
    if type(cap) ~= "number" or cap >= K.MAX_PROJ_SLOTS then return end
    local arr = H.f_main_projectile and patch.get_field_value(H.f_main_projectile, nil, "object")
    if not arr then return end
    local n = array_count(arr, K.MAX_PROJ_SLOTS)
    local active = 0
    for i = 0, n - 1 do
        local p = patch.array_at(arr, i)
        if p == nil then break end
        if get_bool(H.f_active, p, false) then active = active + 1 end
    end
    D.newproj.calls = D.newproj.calls + 1
    if active <= cap then return end
    local need = active - cap
    local ids = S.copy_ids
    local recycled = 0
    for i = 1, ids.n do
        if recycled >= need then break end
        local rec = ids[i]
        if rec then
            local p = get_projectile_at(rec.id)
            if p and get_bool(H.f_active, p, false)
                and get_int(H.f_type, p, -1) == rec.t
                and get_int(H.f_timeleft, p, 0) <= rec.tl then
                if set_bool(H.f_active, p, false) then
                    recycled = recycled + 1
                    stats.recycled = stats.recycled + 1
                end
            end
        end
    end
    log_debug("全局弹幕超限：本模组副本回收 %d 份（活跃 %d / 上限 %d）", recycled, active, cap)
end

-- 副本记录表压缩（防止 S.copy_ids 无限增长）
local function compact_copy_ids()
    local ids = S.copy_ids
    if ids.n <= 256 then return end
    local w = 0
    for i = 1, ids.n do
        local rec = ids[i]
        local keep = false
        if rec then
            local p = get_projectile_at(rec.id)
            if p and get_bool(H.f_active, p, false)
                and get_int(H.f_type, p, -1) == rec.t then
                keep = true
            end
        end
        if keep then w = w + 1; ids[w] = rec end
    end
    for i = w + 1, ids.n do ids[i] = nil end
    ids.n = w
end

local function housekeeping(bucket)
    stats.bucket_index = bucket
    if bucket == 1 then
        stats.buckets = stats.buckets + 1
        if tracked_ids.n > 0 then compact_tracked() end
        compact_copy_ids()
        enforce_global_cap()
        -- 非关键：统计聚合（累计计数 → 本桶新增；只在 write_log + debug_log 都开时打印）
        local dc = stats.copies - stats.copies_last
        stats.copies_last = stats.copies
        stats.copies_per_bucket = dc
        if dc > 0 then
            log_debug("本桶新增副本 %d 份（累计 %d 份）", dc, stats.copies)
        end
    end
end

-- 帧号：AI 是「按 Main.projectile 下标升序、每枚弹幕一次」回调的 → 本枚的下标不大于
-- 上一枚时说明原版循环已经翻页，这时才重新反射读一次 Main.get_GameUpdateCount。
--   ★ §3.7-⑦ 要求用 Main.get_GameUpdateCount() 做帧计数；这样每帧只反射 1 次，
--     而不是每枚弹幕各反射 1 次。
local function tick_frame(id)
    S.frame_calls = (S.frame_calls or 0) + 1
    if H.get_update_count then
        S.samples = (S.samples or 0) + 1
        -- 三个条件任一成立就重新取帧号：
        --   · 还没取过；
        --   · 本枚弹幕的下标不大于上一枚 → 原版循环已经翻页（最常用的判据）；
        --   · 回调计数超过 48 次还没翻页 → 兜底（防止低下标弹幕长期不活跃导致帧号停住）。
        if cur_frame == nil or id <= last_sampled_id or S.samples > 48 then
            S.samples = 0
            local v = patch.invoke(H.get_update_count)
            if type(v) == "number" then
                if v ~= cur_frame then
                    cur_frame = v
                    S.last_frame_calls = S.frame_calls
                    S.frame_calls = 0
                    -- 「本帧扫描次数 / 命中弹幕数」按帧清零（§3.7 的可自测指标）
                    if stats.perf.frame ~= v then
                        stats.perf.frame = v
                        stats.perf.scans_frame = 0
                        stats.perf.steers_frame = 0
                    end
                end
            end
        end
        last_sampled_id = id
        if cur_frame ~= nil then return cur_frame end
    end
    return fallback_frame()
end

-- ============================================================================
-- 21. 环境缓存与配置热重载
-- ============================================================================
-- Main.netMode：静态 int32 字段（字段表 14616 行，readonly=是 但**不是 const**，可读）
-- Main.myPlayer：手机版是**属性** → 只能走 getter（0 参）
local function refresh_env()
    if H.f_main_net_mode then
        local v = patch.get_field_value(H.f_main_net_mode, nil, "int32")
        if type(v) == "number" then
            S.env_net_mode = v
            S.env_net_mode_ok = true
        end
    end
    if H.get_my_player then
        local ok, v = pcall(patch.invoke, H.get_my_player)
        if ok and type(v) == "number" then
            S.env_my_player = v
            S.env_my_player_ok = true
        end
    end
end

-- Main.gameMenu 是**属性**（字段表 15431 行 [属性]）→ 走 0 参 getter get_gameMenu
-- （方法表 8636 行）。取不到就返回 nil（门控退化成“一直不在世界”，自检不播报）。
local function in_game_menu()
    if not H.get_game_menu then return nil end
    local ok, v = pcall(patch.invoke, H.get_game_menu)
    if ok and type(v) == "boolean" then return v end
    return nil
end

local function tick_config()
    local interval = cfg.config_reload_sec
    if type(interval) ~= "number" or interval < 1 then interval = K.DEFAULT_RELOAD_SEC end
    local now = now_seconds()
    if now - last_config_check < interval then return end
    last_config_check = now
    local ok = pcall(function()
        -- ★ 无论 hot_reload 开不开都要读一次 config.json：热重载要靠它，
        --   §9.3 的 import_string 通道也要靠它（客机上聊天不可用时的官方替代通道）。
        local raw = mod.read_file("config.json")
        if read_config(raw) then on_settings_changed() end
        refresh_env()
        tick_import_string()
    end)
    if not ok then
        log_warn("重读设置/环境缓存失败：本次沿用上一次的有效设置")
    end
end

-- ============================================================================
-- 22. Hook 回调
-- ============================================================================
-- Postfix: Projectile.NewProjectile —— 属性改写 + 多重射击
local function on_new_projectile(instance, args, result)
    if not S.ready or not args then return end
    tick_config()
    if not cfg.enabled then return end
    if host_readonly() then return end          -- ★ 写入口第一行：客机只读不写
    if type(result) ~= "number" or result < 0 then return end

    local p = get_projectile_at(result)
    if not p then return end
    D.newproj.calls = D.newproj.calls + 1

    -- §4.4-⑨ 发射武器 ID（只在生成路径解析一次，不逐帧）
    local owner = get_int(H.f_owner, p, nil)
    local wpn = resolve_weapon(owner)

    local id = get_int(H.f_who_am_i, p, -1)
    local s
    if id >= 0 and id < K.MAX_PROJ_SLOTS then
        s = slot_of(id)
        ensure_profile(p, id, s, wpn)
    end
    if not in_scope(p, wpn) then return end

    -- §4.4-⑤ 穿墙（生成时先写一次；开启时逐帧还会维持）
    if cfg.physics_pass_wall then set_bool(H.f_tile_collide, p, false) end

    -- C 组：属性改写（每个新弹幕只会经过这里一次）
    local base = apply_overrides(p, s)
    -- 把原弹幕的位置一起带下去，副本才能从「错开一点」的位置出生
    local ppx, ppy = get_vec2(H.f_position, p)
    base.px, base.py = ppx, ppy
    base.raw.px, base.raw.py = ppx, ppy
    base.wpn = wpn
    if not S.logged_first_override and overrides_on then
        S.logged_first_override = true
        log_info("弹幕属性改写已生效")
    end

    -- B 组：多重射击。正在由本 Mod 造副本时（spawning > 0）不再自行分裂，
    -- 连锁层数由 spawn_copies 的递归深度精确控制。
    if S.spawning > 0 then return end
    if type(cfg.extra_copies) ~= "number" or cfg.extra_copies <= 0 then return end
    if cfg.trigger_chance_percent < 100 then
        if math.random(1, 100) > cfg.trigger_chance_percent then return end
    end
    if cfg.skip_stationary and (base.vx * base.vx + base.vy * base.vy) <= 0.0001 then return end

    local frame = game_frame_now() or fallback_frame()
    local state = { made = 0, layers = {} }
    spawn_copies(args, copy_source(base), 1, state, frame)

    if state.made > 0 and not S.logged_first_copy then
        S.logged_first_copy = true
        log_info(string.format("弹幕工坊已生效：1 发 → %d 发（共 %d 份副本）",
            state.made + 1, state.made))
    end
end

-- Postfix: Projectile.AI —— 逐帧工作（追踪 / 物理组 / 命中效果）
--   全部功能默认关闭：全关时这个回调只做几次布尔比较，一次反射调用都没有。
local function on_ai(instance, args, result)
    if not S.ready or not instance then return end
    tick_config()
    -- 面板第 3 页的聚合观察：只有面板要求时才采集（过期即停，默认零开销）
    if obs.until_ > 0 then
        local now = now_seconds()
        if now <= obs.until_ then
            obs_note(instance, now)
        else
            obs.until_ = 0          -- 过期立刻归零：默认/面板切走后这条分支不再进来
        end
    end
    if not cfg.enabled then return end
    if host_readonly() then return end          -- ★ 写入口第一行：客机只读不写

    -- v2.2.0 每帧处理上限：0 = 不限；两开关全关时一次额外反射都不做
    local check_limit = cfg.max_checks_per_frame
    if type(check_limit) ~= "number" or check_limit < 0 then check_limit = 0 end
    if check_limit > 0 or cfg.adaptive_frame_skip then
        local fr0 = game_frame_now() or fallback_frame()
        if S.check_frame ~= fr0 then S.check_frame, S.checks_used = fr0, 0 end
        if check_limit > 0 and S.checks_used >= check_limit then
            stats.perf.skipped.checks = stats.perf.skipped.checks + 1
            return
        end
        S.checks_used = S.checks_used + 1
        stats.checks_frame = S.checks_used
    end

    stats.tick_calls = stats.tick_calls + 1
    D.ai.calls = D.ai.calls + 1
    housekeeping(bucket_of())

    -- ★ 零开销路径（§3.7-⑧ 的第一层早退）
    if not (homing_on or physics_on or hit_on or lock_on) then return end

    -- §3.7-① 一律用 whoAmI（整数下标）做键：不再把弹幕对象塞进 Lua 表
    local id = get_int(H.f_who_am_i, instance, -1)
    if id < 0 or id >= K.MAX_PROJ_SLOTS then
        stats.perf.skipped.badid = stats.perf.skipped.badid + 1
        dom_err(D.ai, "whoAmI 越界/取不到，已跳过这枚弹幕")
        return
    end
    local s = slot_of(id)
    ensure_profile(instance, id, s)
    if not s.scope then return end

    local frame = tick_frame(id)
    if frame == nil then return end

    -- v2.2.0 自适应分帧：n = 上一帧 AI 回调数；N>1 时按帧号取模跳过
    if cfg.adaptive_frame_skip then
        local N = adaptive_n(S.last_frame_calls or 0, cfg.adaptive_unit, cfg.tick_interval)
        S.adaptive_n = N
        if N > 1 and (frame % N) ~= 0 then
            stats.perf.skipped.adaptive = stats.perf.skipped.adaptive + 1
            return
        end
    else
        S.adaptive_n = 1
    end

    -- §3.7-② 全局共享候选表：每 global_scan_interval 帧只扫一次 Main.npc
    if scan_due(frame) then scan_candidates(frame) end

    -- 飞行帧数（§4.4-③ 追踪曲线用）：按游戏帧推进，不按回调次数
    if s.af == nil then s.af = frame end
    if frame > s.af then
        s.age = (s.age or 0) + (frame - s.af)
        s.af = frame
    end

    -- 体型 / 穿透逐帧锁定（每帧维持，防止原版 AI 改回去）
    if cfg.lock_scale and s.ls then set_float(H.f_scale, instance, s.ls) end
    if cfg.lock_pierce and s.lp then set_int(H.f_penetrate, instance, s.lp) end
    -- 只开了「锁定」时，到这里就没事了（省掉速度/位置那几次反射读）
    if not (homing_on or physics_on or hit_on) then return end

    -- §3.7-⑦ 帧间隔闸门。只开追踪（物理/命中/锁定都关）时把它提到读字段之前，
    -- 这样被跳过的那些帧一次字段读都没有。
    local want_phys, want_hit = physics_on, hit_on
    if homing_on and not (want_phys or want_hit) and not lock_on then
        local iv = s.iv
        if iv ~= nil and (frame - (s.last or frame)) < iv then return end
    end

    local vx, vy, px, py
    if cfg.use_fastpath then
        if not FP.checked then fast_check(instance) end
        if FP.ok then
            local fx, fy, fvx, fvy = fast_read(instance)
            if fx ~= nil then px, py, vx, vy = fx, fy, fvx, fvy end
        end
    end
    if vx == nil then vx, vy = get_vec2(H.f_velocity, instance) end
    if vx == nil then return end
    local speed2 = vx * vx + vy * vy
    local speed = math.sqrt(speed2)
    if px == nil then px, py = get_vec2(H.f_position, instance) end
    if px == nil then return end

    -- §4.4-⑤ 弹幕物理组（默认关）。它可能改写速度（直线锁/归位/环绕），
    -- 所以要把生效后的速度接回来给追踪用，否则追踪会用上一帧的旧方向把它盖掉。
    if want_phys then
        local nvx, nvy = do_physics(instance, s, px, py, vx, vy, speed, frame)
        if nvx == nil then return end            -- 回收了这枚弹幕
        vx, vy = nvx, nvy
        speed2 = vx * vx + vy * vy
        speed = math.sqrt(speed2)
    end

    -- §4.4-④ 命中效果（默认关）：用 numHits 的增量做命中判定
    if want_hit then
        local nh = get_int(H.f_num_hits, instance, nil)
        if nh then
            local prev = s.nh
            if prev == nil then prev = 0 end
            s.nh = nh
            -- v2.2.0：第一次看到时如果 numHits 已经 > 0（生成后立刻命中），也要触发。
            if nh > prev and (s.hits or 0) < K.SMALL_MAX_HITS then
                s.hits = (s.hits or 0) + 1
                local hx = px + get_int(H.f_width, instance, 0) * 0.5
                local hy = py + get_int(H.f_height, instance, 0) * 0.5
                do_hit_effects(instance, s, hx, hy, vx, vy, speed, frame)
            end
        end
    end

    if not homing_on then return end

    -- ---- 追踪：帧间隔闸门（动态间隔）+ ⑧ 早退链 ----
    local iv = s.iv
    if iv ~= nil and (frame - (s.last or frame)) < iv then return end
    s.last = frame

    -- ⑧-① active 早退（原版 AI 本来就只对 active 弹幕回调，这里再确认一次，
    --     成本 1 次 bool 读，换来「万一句柄/槽位错位也不会写坏别的弹幕」）
    if get_bool(H.f_active, instance, false) ~= true then
        release_tracking(s, frame)
        return
    end
    -- ⑧-② friendly / hostile 不匹配：已在 ensure_profile 里一次性判掉（s.scope），
    --     这里只做一次整数/布尔比较。
    if not s.frd and not s.hst then return end
    -- ⑧-③ 速度 < 阈值
    if speed2 < K.MIN_TRACK_SPEED * K.MIN_TRACK_SPEED then
        stats.perf.skipped.speed = stats.perf.skipped.speed + 1
        return
    end

    local cx = px + get_int(H.f_width, instance, 0) * 0.5
    local cy = py + get_int(H.f_height, instance, 0) * 0.5

    -- ⑧-④ 离屏（代理：距最近活跃玩家超过 OFFSCREEN_DISTANCE）
    --   ★ Main.screenPosition 是 Vector2 属性（字段表 15373 行）→ 本代读不到；
    --     这里用「离玩家距离」代理，阈值取得比任何手机屏幕都大，误杀概率极低。
    if pl_list_n > 0 then
        local _, dmin2 = nearest_player(cx, cy)
        if dmin2 and dmin2 > K.OFFSCREEN_DISTANCE * K.OFFSCREEN_DISTANCE then
            stats.perf.skipped.offscreen = stats.perf.skipped.offscreen + 1
            return
        end
    end

    -- §4.4-③ 追踪曲线：只在飞行前 N 帧追踪
    local F = cfg.homing_flight_frames
    if type(F) == "number" and F > 0 and (s.age or 0) > F then
        release_tracking(s, frame)
        return
    end

    local range = cfg.homing_range
    if type(range) ~= "number" or range < 1 then range = 1 end
    local range2 = range * range
    local tx, ty
    local is_enemy = (s.hst == true) and (s.frd ~= true)

    if is_enemy then
        -- ================= 敌方弹幕追玩家（§3.7-⑦ 的 player 分支）=================
        local pi = s.tgt
        if pi ~= nil and (pl_seen[pi] == nil or (frame - pl_seen[pi]) > cand.grace) then
            release_tracking(s, frame)
            pi = nil
        end
        if pi ~= nil then
            local ddx, ddy = pl_cx[pi] - cx, pl_cy[pi] - cy
            if ddx * ddx + ddy * ddy > range2 then
                -- ⑧-⑤ 索敌半径外 → 释放目标并早退
                release_tracking(s, frame)
                stats.perf.skipped.radar = stats.perf.skipped.radar + 1
                return
            end
            tx, ty = pl_cx[pi], pl_cy[pi]
        else
            if not switch_allowed(s, frame) then return end
            if not acquire_tracking(s, id) then return end
            local npi, nd2 = nearest_player(cx, cy)
            if npi == nil or (nd2 and nd2 > range2) then
                release_tracking(s, frame)
                stats.perf.skipped.radar = stats.perf.skipped.radar + 1
                return
            end
            s.tgt, s.tkind = npi, 2
            s.cool = nil
            tx, ty = pl_cx[npi], pl_cy[npi]
        end
    else
        -- 联机下不动「别人发射的」弹幕（避免与别人客户端的模拟打架）；
        -- 单机/服务器/房主侧照常，且超限时仍然优先服务自己的弹幕（§3.7-⑨）。
        if not s.own and S.env_net_mode_ok and S.env_net_mode ~= 0 and S.env_my_player_ok then
            release_tracking(s, frame)
            return
        end
        -- ================= 我方弹幕追 NPC（§3.7-⑦ 的 npc 分支）=================
        local nid = s.tgt
        if nid ~= nil and (npc_seen[nid] == nil or (frame - npc_seen[nid]) > cand.grace) then
            release_tracking(s, frame)
            nid = nil
        end
        if nid ~= nil then
            local ddx, ddy = npc_cx[nid] - cx, npc_cy[nid] - cy
            if ddx * ddx + ddy * ddy > range2 then
                release_tracking(s, frame)
                stats.perf.skipped.radar = stats.perf.skipped.radar + 1
                return
            end
            tx, ty = npc_cx[nid], npc_cy[nid]
        else
            -- ⑧-⑤ 共享候选表为空 = 附近没有任何可追踪目标 → 直接早退，不扫 NPC
            if cand.n == 0 then
                stats.perf.skipped.radar = stats.perf.skipped.radar + 1
                return
            end
            if not switch_allowed(s, frame) then return end
            if not acquire_tracking(s, id) then return end
            local best, bd2 = find_candidate(cx, cy, range2)
            if best == nil then
                release_tracking(s, frame)
                stats.perf.skipped.radar = stats.perf.skipped.radar + 1
                return
            end
            s.tgt, s.tkind = best, 1
            s.cool = nil
            D.cand.hits = D.cand.hits + 1
            tx, ty = npc_cx[best], npc_cy[best]
            if tx == nil then
                release_tracking(s, frame)
                return
            end
        end
    end

    D.ai.hits = D.ai.hits + 1
    local turned = apply_turn(instance, s, tx, ty, cx, cy, vx, vy, speed, iv or 1)

    -- 下一次的等待间隔：由这次的速度决定（§3.7-⑦）
    s.iv = compute_interval(speed, is_enemy)

    -- 目标已经不在（apply_turn 因“停手距离”没转向不算失败）
    if not turned and s.tgt == nil then release_tracking(s, frame) end
end

-- ============================================================================
-- 23. §4.6 诊断报告 / §3.7 性能指标（聊天栏输出）
-- ============================================================================
local VER, SLUG = tostring(mod.meta.version), "projectileforge"
local EXPORT_FILE = "forge_export.txt"     -- §9.3 零聊天依赖的导出落盘文件
local last_config_raw = nil                -- 上一次读到的 config.json 原文（含 import_string）

local function ok_mark(v)
    if v == "ok" then return "✅" end
    if v == "partial" then return "⚠" end
    if v == "fail" then return "❌" end
    return "？"
end

-- §3.7 可自测指标：本帧扫描次数 / 命中弹幕数 / 平均耗时
local function perf_line()
    local pf = stats.perf
    local cur = cur_frame
    local this_scans = (cur ~= nil and pf.frame == cur) and pf.scans_frame or 0
    local this_steers = (cur ~= nil and pf.frame == cur) and pf.steers_frame or 0
    return string.format(
        "[弹幕工坊] 本帧(帧 %s) 扫描 %d 次 / 命中弹幕 %d 枚；平均 扫描 %.3f ms、转向 %.3f ms；"
        .. "累计 扫描 %d 次 / 转向 %d 枚",
        tostring(cur or "?"), this_scans, this_steers,
        pf.avg_scan_ms, pf.avg_steer_ms, pf.scans_total, pf.steers_total)
end

local function slow_ms()
    local v = cfg.diag_slow_ms
    if type(v) ~= "number" or v < 1 then v = 50 end
    return v
end

-- 每域一行（最多 12 行，超出折叠成一行统计）；行首统一 [弹幕工坊]
local function diag_report(title)
    chat_print(string.format("[弹幕工坊] %s（v%s，诊断阈值 %d ms）", title, VER, slow_ms()))
    local lim = 12
    local total = #domains
    local shown = 0
    for i = 1, total do
        if shown >= lim then break end
        local d = domains[i]
        local st
        if d.fields == "fail" or d.hooks == "fail" then
            st = "已停用"
        else
            st = string.format("命中 %d 次", d.hits)
        end
        local slow = ""
        if d == D.cand and stats.perf.avg_scan_ms > slow_ms() then slow = " SLOW" end
        if d == D.track and stats.perf.avg_steer_ms > slow_ms() then slow = " SLOW" end
        chat_print(string.format("[弹幕工坊] 域 %s：句柄%s 钩子%s %s%s",
            d.name, ok_mark(d.fields), ok_mark(d.hooks), st, slow))
        shown = shown + 1
    end
    if total > lim then
        chat_print(string.format("[弹幕工坊] …其余 %d 个域未展开（用 /forge stat 再看）", total - lim))
    end
    chat_print(perf_line())
    -- 最近错误（最多 3 条）
    local errs = 0
    for i = 1, total do
        local d = domains[i]
        if d.errs > 0 then
            if errs < 3 then
                chat_print(string.format("[弹幕工坊] 域 %s 错误 %d 次：%s",
                    d.name, d.errs, tostring(d.last_err)))
            end
            errs = errs + 1
        end
    end
    if errs == 0 then chat_print("[弹幕工坊] 无错误记录") end
end

-- ============================================================================
-- 24. §3.1 方案 B / §3 设置串：导出 / 导入（分片 + 校验和 + 就地改写 config.json）
-- ============================================================================
local function ui_value(key)
    local v = cfg[key]
    local off = UI_OFFSET[key]
    if off and type(v) == "number" then return v + off end
    return v
end

-- 值 → 串里的字面量：bool → true/false；数字 → 十进制整数；字符串 → 原样（; | = 转义）
local function encode_value(v)
    local t = type(v)
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then return tostring(math.floor(v)) end
    return (tostring(v):gsub("[;|=%%]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function unescape_value(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function checksum(s)
    local sum = 0
    for i = 1, #s do
        sum = (sum + s:byte(i)) % 65521
    end
    return string.format("%x", sum)
end

local function build_export_string(all)
    local parts, n = {}, 0
    for key, default in pairs(DEFAULTS) do
        local uv = ui_value(key)
        if all or uv ~= default then
            n = n + 1
            parts[n] = key .. "=" .. encode_value(uv)
        end
    end
    table.sort(parts)
    local body = table.concat(parts, ";")
    local head = "forge:" .. SLUG .. "|" .. body
    return head .. "|#" .. checksum(head), n
end

-- 导出：**始终**把整串落到模组私有目录的 forge_export.txt（§9.3 零聊天依赖通道），
--   聊天分片只是 chat_cmd 打开时的便利输出。返回 (ok, 串, 项数, 分片数)。
function export_print(all, no_chat)
    local str, n = build_export_string(all)
    local MAXBODY = 320
    local parts, cnt, i = {}, 0, 1
    while i <= #str do
        cnt = cnt + 1
        parts[cnt] = str:sub(i, i + MAXBODY - 1)
        i = i + MAXBODY
    end
    if cnt == 0 then cnt = 1; parts[1] = "" end
    local ok = mod.write_file(EXPORT_FILE, str)
    if no_chat then
        D.cfg.hits = D.cfg.hits + 1
        return ok, str, n, cnt
    end
    if not ok then
        chat_print("[弹幕工坊] 导出失败：写 " .. EXPORT_FILE .. " 出错（模组私有目录不可写）", true)
        D.cfg.hits = D.cfg.hits + 1
        return false, str, n, cnt
    end
    for k = 1, cnt do
        chat_print(string.format("[%d/%d] %s", k, cnt, parts[k]))
    end
    chat_print(string.format("[弹幕工坊] 已导出 %d 片 / %d 项到 %s%s；也可用设置项 import_string 粘贴导入",
        cnt, n, EXPORT_FILE, all and "（全量）" or "（只含与默认不同的项）"))
    D.cfg.hits = D.cfg.hits + 1
    return true, str, n, cnt
end

-- ============================================================================
-- 24.1 §9.3 默认（零聊天依赖）导入通道：设置项 import_string
--      玩家把整串粘贴进 TEFManager 设置界面即可；校验 → 就地改写 config.json
--      → 播报结果 → 清空该项。单机与客机都可用，完全不经过聊天系统。
-- ============================================================================
-- 找到 "key": 后面那个字面量的起止字节位置（值可能是字符串或数字）
local function find_value_span(raw, key)
    local esc = key:gsub("([^%w])", "%%%1")
    local ks, ke = raw:find('"' .. esc .. '"%s*:%s*', 1)
    if not ks then return nil end
    local vs = ke + 1
    local rest = raw:sub(vs)
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
    local off = rest:find("[,%}%s]")
    return vs, off and (vs + off - 2) or #raw
end

-- 就地清空 import_string（只替换这一个字面量，其它一个字符都不动）
local function clear_import_string()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then return false end
    local vs, ve = find_value_span(raw, "import_string")
    if vs then
        local out = raw:sub(1, vs - 1) .. '""' .. raw:sub(ve + 1)
        if out ~= raw and mod.write_file("config.json", out) then
            last_config_raw = out
            return true
        end
    end
    return false
end

-- 检查 import_string 是否被粘贴了新串；是就校验 + 应用 + 清空 + 播报。
--   ★ 与 hot_reload 无关（由 tick_config 的节拍驱动）：玩家关掉「自动重读设置」后
--     这条通道也必须能用 —— 它是聊天路径在客机上不可靠时的官方替代通道。
tick_import_string = function()
    local raw = tostring(cfg.import_string or "")
    if raw == "" then
        S.import_seen_raw = raw
        return
    end
    if raw == S.import_seen_raw then return end      -- 已经处理过这条
    if S.import_active then return end
    S.import_active = true
    S.import_seen_raw = raw
    local ok, msg, other = import_apply(raw, true)
    if other then
        S.import_active = nil
        return
    end
    if not ok then
        chat_print((msg or "[弹幕工坊] 导入失败") .. "（import_string 中的串未生效）", true)
    else
        clear_import_string()                        -- 成功才清空，失败留着让玩家改
        chat_print((msg or "") .. "；已清空设置项 import_string", true)
    end
    S.import_active = nil
end

-- 解析出「要改的 key → UI 值」，未知 key 计入忽略
local function parse_import_body(body)
    local changes, applied, ignored = {}, 0, 0
    for pair in body:gmatch("[^;]+") do
        local k, v = pair:match("^([%w_]+)=(.*)$")
        if k then
            local default = DEFAULTS[k]
            if default == nil then
                ignored = ignored + 1
            else
                local val
                local t = type(default)
                if t == "boolean" then
                    if v == "true" then val = true
                    elseif v == "false" then val = false end
                elseif t == "number" then
                    local num = tonumber(v)
                    if num then
                        num = math.floor(num)
                        local lim = LIMITS[k]
                        if lim then
                            if num < lim[1] then num = lim[1] end
                            if num > lim[2] then num = lim[2] end
                        end
                        val = num
                    end
                else
                    local s = unescape_value(v)
                    local choices = CHOICES[k]
                    if choices then
                        for j = 1, #choices do
                            if s == choices[j] then val = s end
                        end
                    else
                        val = s
                    end
                end
                if val ~= nil then
                    changes[k] = val
                    applied = applied + 1
                else
                    ignored = ignored + 1
                end
            end
        end
    end
    return changes, applied, ignored
end

-- 就地改写 config.json 文本（只替换该 key 的值；schemaVersion 与未知 key 原样保留）
local function write_back_config(changes)
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" then
        raw = '{"schemaVersion":1,"values":{}}'
    end
    local wrote = 0
    for k, v in pairs(changes) do
        local lit
        if type(v) == "string" then
            -- JSON 里字符串要带引号；只转义引号与反斜杠（config.json 是扁平 JSON）
            lit = '"' .. (v:gsub('[%\\"]', function(c)
                if c == '"' then return '\\"' end
                return '\\\\'
            end)) .. '"'
        else
            lit = encode_value(v)
        end
        local pat = '("' .. k .. '"%s*:%s*)([^,}%s]+)'
        local replaced = false
        raw = raw:gsub(pat, function(prefix)
            replaced = true
            return prefix .. lit
        end)
        if replaced then
            wrote = wrote + 1
        else
            -- 文件里没有这个 key → 插到 "values" 的 { 之后（保守：只在结构存在时插）
            local vpos = raw:find('"values"%s*:%s*{')
            if vpos then
                local brace = raw:find("{", vpos)
                if brace then
                    raw = raw:sub(1, brace) .. '"' .. k .. '":' .. lit .. ","
                        .. raw:sub(brace + 1)
                    wrote = wrote + 1
                end
            end
        end
    end
    if wrote == 0 then return false, "config.json 结构与预期不符，未写入" end
    local ok = mod.write_file("config.json", raw)
    if not ok then return false, "写 config.json 失败" end
    return true, wrote
end

-- 纯导入：给一条完整串就校验 + 就地改写 config.json + 立刻生效。
--   返回 (ok, 消息, is_other_slug)。no_chat = true 时一个字都不往聊天栏打
--   （import_string 通道用它，再把消息交给自己的播报节奏）。
import_apply = function(str, no_chat)
    local function say(text, force)
        if not no_chat then chat_print(text, force) end
    end
    local slug, body, sum = str:match("^forge:([%w_%-]+)|(.*)|#(%x+)$")
    if slug == nil then
        say("[弹幕工坊] 导入失败：设置串格式不合法", true)
        dom_err(D.cfg, "格式不合法")
        return false, "[弹幕工坊] 导入失败：设置串格式不合法", false
    end
    if slug ~= SLUG then
        -- 别的模组的串：聊天侧提示一句，import_string 通道静默忽略
        say(string.format("[弹幕工坊] 这条串属于 %s，不是本模组的（已忽略）", slug), true)
        return false, nil, true
    end
    local head = "forge:" .. slug .. "|" .. body
    if checksum(head) ~= sum then
        say("[弹幕工坊] 导入失败：校验和不匹配（可能复制不全）", true)
        dom_err(D.cfg, "校验和不匹配")
        return false, "[弹幕工坊] 导入失败：校验和不匹配（可能复制不全）", false
    end
    local changes, applied, ignored = parse_import_body(body)
    if applied == 0 then
        say(string.format("[弹幕工坊] 导入失败：没有可识别的项（忽略 %d 项）", ignored), true)
        dom_err(D.cfg, "没有可识别的项")
        return false, string.format("[弹幕工坊] 导入失败：没有可识别的项（忽略 %d 项）", ignored), false
    end
    local ok, info = write_back_config(changes)
    if not ok then
        say("[弹幕工坊] 导入失败：" .. tostring(info) .. "（游戏内设置未改动）", true)
        dom_err(D.cfg, tostring(info))
        return false, "[弹幕工坊] 导入失败：" .. tostring(info) .. "（游戏内设置未改动）", false
    end
    -- 立刻生效：重读 + 重算派生参数
    if read_config() then on_settings_changed() end
    refresh_env()
    D.cfg.hits = D.cfg.hits + 1
    local msg = string.format("[弹幕工坊] 已导入 %d 项（忽略 %d 项）；设置已即时生效", applied, ignored)
    say(msg, true)
    say(string.format("[弹幕工坊] 当前：副本 %d 份 / %s / 追踪%s / 性能档 %s",
        cfg.extra_copies, SPREAD_MODE_NAME[cfg.spread_mode] or "?",
        cfg.homing_enabled and "开" or "关", tostring(cfg.perf_mode)), true)
    return true, msg, false
end

-- ============================================================================
-- 25. 聊天命令（§2.3 命令表；前缀一律 forge，单机/联机都可用）
-- ============================================================================
local function help_print()
    chat_print("[弹幕工坊] 命令列表（大小写不敏感，前导 / 可省）")
    chat_print("[弹幕工坊] /forge help            本列表")
    chat_print("[弹幕工坊] /forge stat            诊断统计（每域 calls/hits/errs）")
    chat_print("[弹幕工坊] /forge check           重跑一次自检并播报")
    chat_print("[弹幕工坊] /forge perf            本帧扫描次数 / 命中弹幕数 / 平均耗时")
    chat_print("[弹幕工坊] /forge export [all]    导出设置串（默认只导非默认项；自动分片）")
    chat_print("[弹幕工坊] /forge import <串>     导入设置串（支持 [i/n] 分片）")
    chat_print("[弹幕工坊] /forge import reset    放弃已缓存的分片")
end

local function stat_print()
    diag_report("诊断统计")
    local pf = stats.perf
    chat_print(string.format(
        "[弹幕工坊] 跳过：速度%d 离屏%d 超距%d 名额满%d 下标异常%d；非关键桶 %d 次；副本累计 %d / 回收 %d",
        pf.skipped.speed, pf.skipped.offscreen, pf.skipped.radar, pf.skipped.limit,
        pf.skipped.badid, stats.buckets, stats.copies, stats.recycled))
    chat_print(string.format("[弹幕工坊] 候选表：%d 个可追踪目标（本轮裁剪掉 %d）；同时追踪 %d / 上限 %d",
        cand.n, cand.cropped, tracked_n, K.MAX_TRACKED))
end

local function import_fragment_or_apply(arg)
    local idx, total, body = arg:match("^%[(%d+)/(%d+)%]%s*(.*)$")
    if idx then
        idx, total = tonumber(idx), tonumber(total)
        if not total or total < 1 or total > 99 or not idx or idx < 1 or idx > total then
            chat_print("[弹幕工坊] 分片编号异常，已忽略这一片")
            dom_err(D.cfg, "分片编号异常")
            return
        end
        if S.frag_total ~= total then
            S.frags, S.frag_have = {}, 0
            S.frag_total = total
        end
        S.frags[idx] = body
        S.frag_have = 0
        local missing
        for k = 1, total do
            if S.frags[k] then
                S.frag_have = S.frag_have + 1
            elseif not missing then
                missing = k
            end
        end
        if S.frag_have < total then
            chat_print(string.format("[弹幕工坊] 已收 %d/%d 片；缺第 %s 片",
                S.frag_have, total, tostring(missing)))
            return
        end
        local full = table.concat(S.frags, "", 1, total)
        S.frags, S.frag_have, S.frag_total = {}, 0, 0
        import_apply(full)
    else
        import_apply(arg)
    end
end

local function handle_forge(cmd, arg)
    if cmd == "help" then
        help_print()
    elseif cmd == "stat" then
        stat_print()
    elseif cmd == "check" then
        diag_report("重跑自检")
    elseif cmd == "perf" then
        chat_print(perf_line())
    elseif cmd == "export" then
        export_print(arg:lower() == "all")
    elseif cmd == "import" then
        if arg == "" then
            chat_print("[弹幕工坊] 用法：/forge import <设置串>（或 /forge import reset）")
        elseif arg:lower() == "reset" then
            S.frags, S.frag_have, S.frag_total = {}, 0, 0
            chat_print("[弹幕工坊] 已清空分片缓存")
        else
            import_fragment_or_apply(arg)
        end
    elseif cmd == "" then
        help_print()
    else
        chat_print("[弹幕工坊] 未知命令 /forge " .. cmd .. "（用 /forge help 看列表）")
    end
end

-- 三态解析聊天文本，返回 (state, cmd, arg)：
--   "ours"    = 本模组要处理（prefix 拦截，不当普通聊天广播）
--   "unknown" = /forge 命名空间但不认识的小命令（提示 + 拦截）
--   "other"   = 与本模组无关（返回 nil，交给原版继续）
-- ★ arg 保留原大小写（设置串里含中文与大小写敏感的内容）。
local FORGE_CMDS = {
    help = true, stat = true, check = true, perf = true, export = true, import = true,
}

local function recognized_cmd(text)
    if type(text) ~= "string" then return "other" end
    local t = (text:gsub("^%s*/?%s*", ""):gsub("%s+$", ""))
    if t == "" then return "other" end
    -- ★ 括号不能省：gsub 返回 (串, 替换次数)，漏掉会污染后面的比较
    local want = (tostring(cfg.diag_report_cmd or ""):gsub("^%s*/?%s*", ""):gsub("%s+$", ""):lower())
    if want ~= "" and t:lower() == want then return "ours", "\0diag", "" end
    local head, tail = t:match("^(%S+)%s*(.*)$")
    if not head or head:lower() ~= "forge" then return "other" end
    tail = tail or ""
    -- 直接粘贴了一整条设置串（没有 import 关键字）也接受
    if tail:sub(1, 6) == "forge:" then return "ours", "import", tail end
    local cmd, arg = tail:match("^(%S+)%s*(.*)$")
    if not cmd then
        if tail == "" then return "ours", "help", "" end
        return "unknown", tail, ""
    end
    if FORGE_CMDS[cmd:lower()] then return "ours", cmd:lower(), arg or "" end
    return "unknown", cmd, arg or ""
end

-- 唯一的聊天文本入口（§9.2）：
--   Terraria.Chat.Commands.SayChatCommand.ProcessIncomingMessage(string text, byte clientId)
--   它是 ChatInitializer 注册的 _defaultCommand —— 普通聊天与任何「未知 /命令」的原文
--   都会原样送到这里；参数全是标量（string + byte），不碰任何 Chat 消息对象。
--   prefix 返回 true = 跳过原方法 → 顺手阻止该串被原版当普通聊天广播出去。
local function on_say_chat(instance, args, result)
    if not S.ready or not args then return nil end
    local text = args[1]
    if type(text) ~= "string" then return nil end
    D.chat.calls = D.chat.calls + 1
    -- 只处理本机玩家：args[2] 是 clientId（byte），Main.myPlayer 是属性 → 走 getter
    local id = args[2]
    if type(id) == "number" and S.env_my_player_ok then
        if math.floor(id) ~= math.floor(S.env_my_player) then return nil end
    end
    local state, cmd, arg = recognized_cmd(text)
    if state == "other" then return nil end
    D.chat.hits = D.chat.hits + 1
    if state == "unknown" then
        chat_print("[弹幕工坊] 未知命令 /forge " .. cmd .. "（用 /forge help 看列表）")
        return true
    end
    if cmd == "\0diag" then
        stat_print()
    else
        handle_forge(cmd, arg)
    end
    return true
end

-- ============================================================================
-- 26. 「进世界后的第一帧」门控（§4.3）+ 进世界首帧自检播报（§4.6）
--   没有进世界/退出世界回调 → 用 Main.gameMenu == false + Player.ResetEffects 被调用
--   双门控。每帧只做一次 bool 读（0 参属性 getter）。
-- ============================================================================
local function on_reset_effects(instance, args, result)
    tick_config()                       -- 配置热重载也挂在这里：进世界前就能生效
    local gm = in_game_menu()
    if gm == nil then return end
    if gm then
        if S.env_in_world then
            S.env_in_world = false      -- 退出世界：边沿标记清零 + 分片缓存重置
            S.frags, S.frag_have, S.frag_total = {}, 0, 0
        end
        return
    end
    if S.env_in_world then return end
    S.env_in_world = true
    if cfg.self_check == true then
        diag_report("启动自检")          -- 每次进世界各播一次
    end
end

-- ============================================================================
-- 27. 生命周期
-- ============================================================================
local hooks = {}

local function mark(cond) return cond and "ok" or "fail" end

function setup()
    read_config()
    on_settings_changed()

    H.t_main = patch.get_type("Terraria", "Main")
    H.t_projectile = patch.get_type("Terraria", "Projectile")
    H.t_npc = patch.get_type("Terraria", "NPC")
    H.t_player = patch.get_type("Terraria", "Player")
    H.t_item = patch.get_type("Terraria", "Item")
    if not H.t_main or not H.t_projectile then
        mod.warn("弹幕工坊未启用：获取类型失败 (Main/Projectile)")
        D.ai.fields, D.ai.hooks = "fail", "fail"
        D.newproj.fields, D.newproj.hooks = "fail", "fail"
        D.track.fields, D.track.methods = "fail", "fail"
        D.cand.fields, D.cand.methods = "fail", "fail"
        return
    end

    -- ---- 弹幕 / 实体字段（沿父类链查找；field_of 会挡掉 const，硬规则 #2）----
    H.f_main_projectile = field_of(H.t_main, "projectile")
    H.f_main_npc        = field_of(H.t_main, "npc")
    H.f_main_player     = field_of(H.t_main, "player")
    H.f_main_net_mode   = field_of(H.t_main, "netMode")
    H.f_active          = field_of(H.t_projectile, "active")
    H.f_type            = field_of(H.t_projectile, "type")
    H.f_friendly        = field_of(H.t_projectile, "friendly")
    H.f_hostile         = field_of(H.t_projectile, "hostile")
    H.f_minion          = field_of(H.t_projectile, "minion")
    H.f_sentry          = field_of(H.t_projectile, "sentry")
    H.f_bobber          = field_of(H.t_projectile, "bobber")
    H.f_ai_style        = field_of(H.t_projectile, "aiStyle")
    H.f_damage          = field_of(H.t_projectile, "damage")
    H.f_knockback       = field_of(H.t_projectile, "knockBack")
    H.f_scale           = field_of(H.t_projectile, "scale")
    H.f_timeleft        = field_of(H.t_projectile, "timeLeft")
    H.f_penetrate       = field_of(H.t_projectile, "penetrate")
    H.f_velocity        = field_of(H.t_projectile, "velocity")
    H.f_position        = field_of(H.t_projectile, "position")
    H.f_width           = field_of(H.t_projectile, "width")
    H.f_height          = field_of(H.t_projectile, "height")
    H.f_who_am_i        = field_of(H.t_projectile, "whoAmI")   -- Entity.whoAmI（0x10）
    H.f_net_update      = field_of(H.t_projectile, "netUpdate")
    H.f_owner           = field_of(H.t_projectile, "owner")
    H.f_tile_collide    = field_of(H.t_projectile, "tileCollide")
    H.f_num_hits        = field_of(H.t_projectile, "numHits")
    H.f_uses_local_immunity = field_of(H.t_projectile, "usesLocalNPCImmunity")
    H.f_local_hit_cooldown  = field_of(H.t_projectile, "localNPCHitCooldown")
    H.f_bonus_crit      = field_of(H.t_projectile, "bonusCritChance")

    if H.t_npc then
        H.f_npc_active           = field_of(H.t_npc, "active")
        H.f_npc_chaseable        = field_of(H.t_npc, "chaseable")
        H.f_npc_life_max         = field_of(H.t_npc, "lifeMax")
        H.f_npc_dont_take_damage = field_of(H.t_npc, "dontTakeDamage")
        H.f_npc_immortal         = field_of(H.t_npc, "immortal")
        H.f_npc_friendly         = field_of(H.t_npc, "friendly")
        H.f_npc_boss             = field_of(H.t_npc, "boss")
        H.f_npc_rarity           = field_of(H.t_npc, "rarity")
        H.f_npc_position         = field_of(H.t_npc, "position")
        H.f_npc_width            = field_of(H.t_npc, "width")
        H.f_npc_height           = field_of(H.t_npc, "height")
    end
    if H.t_player then
        H.f_player_active    = field_of(H.t_player, "active")
        H.f_player_dead      = field_of(H.t_player, "dead")
        H.f_player_inventory = field_of(H.t_player, "inventory")
        H.f_player_position  = field_of(H.t_player, "position")
        H.f_player_width     = field_of(H.t_player, "width")
        H.f_player_height    = field_of(H.t_player, "height")
    end
    if H.t_item then
        H.f_item_type = field_of(H.t_item, "type")
    end

    if not H.f_main_projectile or not H.f_active or not H.f_velocity then
        mod.warn("弹幕工坊未启用：获取关键字段失败 (Main.projectile / Projectile.active / velocity)")
        D.ai.fields = "fail"
        D.newproj.fields = "fail"
        return
    end
    if not H.f_friendly or not H.f_hostile or not H.f_type then
        mod.warn("弹幕工坊未启用：获取弹幕归属字段失败 (friendly/hostile/type)")
        return
    end
    if not H.f_penetrate then
        mod.warn("未找到 Projectile.penetrate：穿透加成/穿透锁定将不生效（其余功能不受影响）")
    end
    if not H.f_scale then
        mod.warn("未找到 Projectile.scale：体型改写/体型锁定将不生效（其余功能不受影响）")
    end
    if not H.f_who_am_i then
        mod.warn("未找到 Entity.whoAmI：追踪/物理组/命中效果将不生效（其余功能不受影响）")
    end

    -- ---- 方法（硬规则 #3：N = C# 形参个数，不含 this；全部核过 TSV）----
    -- Main.NewText：只认 5 参 (string,byte,byte,byte,bool)（方法表 9576 行）；3 参那个带
    -- Color 结构体，不碰。
    H.new_text = method_exact(H.t_main, "NewText", 5)
    if not H.new_text then
        mod.warn("取不到 Main.NewText 的 5 参重载：/forge 命令的输出只写日志")
    end
    -- Main.get_GameUpdateCount：0 参静态 → uint（方法表 8856 行）
    H.get_update_count = method_exact(H.t_main, "get_GameUpdateCount", 0)
    if not H.get_update_count then
        mod.warn("取不到 Main.get_GameUpdateCount：帧号改用 os.clock 折算（功能不受影响）")
    end
    -- Main.gameMenu 是**属性**（字段表 15431 行）→ 0 参 getter（方法表 8636 行）
    H.get_game_menu = method_exact(H.t_main, "get_gameMenu", 0)
    -- Main.myPlayer 是**属性**（字段表 15405 行 [属性]）→ 属性桥接优先，再退 get_myPlayer
    --   （方法表 8584 行 get_myPlayer 是它的 getter，0 参）
    if patch.get_property then
        local prop = patch.get_property(H.t_main, "myPlayer")
        if prop and patch.property_get_method then
            H.get_my_player = patch.property_get_method(prop)
        end
    end
    if not H.get_my_player then
        H.get_my_player = method_exact(H.t_main, "get_myPlayer", 0)
    end
    if not H.get_my_player then
        mod.warn("未找到 Main.get_myPlayer：追踪的 owner 限制/聊天自机判定退化为「只看友方」")
    end
    -- Player.selectedItem 是**属性**（字段表 17579 行）→ 0 参 getter（方法表里有 get_selectedItem）
    if H.t_player then
        if patch.get_property then
            local prop = patch.get_property(H.t_player, "selectedItem")
            if prop and patch.property_get_method then
                H.get_selected_item = patch.property_get_method(prop)
            end
        end
        if not H.get_selected_item then
            H.get_selected_item = method_exact(H.t_player, "get_selectedItem", 0)
        end
        H.player_heal = method_exact(H.t_player, "Heal", 1)          -- 命中吸血
    end
    if H.t_npc then
        -- ③ 合成一次 NPC.CanBeChasedBy(object, bool)（方法表 10218 行，2 形参）
        H.can_be_chased = method_exact(H.t_npc, "CanBeChasedBy", 2)
        -- 命中爆炸/闪电连锁：NPC.StrikeNPC(int,float,int,bool,bool,int)（方法表 10201 行）
        H.strike_npc = method_exact(H.t_npc, "StrikeNPC", 6)
    end
    -- 命中分裂需要一个真的 IEntitySource：Projectile.GetProjectileSource_FromThis()（0 参实例）
    H.source_from_this = method_exact(H.t_projectile, "GetProjectileSource_FromThis", 0)

    -- ---- Projectile.NewProjectile：1.4.5.8 手机版只有 11 参与 13 参两个重载 ----
    -- ★ 只认 13 参重载（IEntitySource, float×4, int, int, float, int, float×3,
    --   NewProjectileModifier）。11 参那个前 3 个形参里带 Vector2 按值结构体 ——
    --   本加载器的 hook 走 libffi 闭包、只支持标量参数，挂它可能崩，所以**绝不做**
    --   「按个数回退/按名字回退」到那个重载。
    H.new_projectile = method_exact(H.t_projectile, "NewProjectile", 13)
    H.new_projectile_argc = method_argc(H.new_projectile)
    if H.new_projectile then
        local h = safe_hook(H.new_projectile, { postfix = on_new_projectile }, "Projectile.NewProjectile")
        if h then
            hooks[#hooks + 1] = h
            D.newproj.hooks = "ok"
        else
            H.new_projectile = nil
        end
    else
        mod.warn("取不到 Projectile.NewProjectile 的 13 参重载（11 参那个带 Vector2 按值结构体，"
            .. "按红线不挂）：多重射击/属性改写/命中分裂不可用，追踪等其余功能照常")
    end

    -- ---- Projectile.AI：逐帧工作（失败不影响多重射击/属性改写）----
    H.ai = method_exact(H.t_projectile, "AI", 0)
    local h_ai = safe_hook(H.ai, { postfix = on_ai }, "Projectile.AI")
    if h_ai then
        hooks[#hooks + 1] = h_ai
        D.ai.hooks = "ok"
    else
        mod.warn("Projectile.AI Hook 未安装：追踪/物理组/命中效果不可用")
    end

    -- ---- Player.ResetEffects：进世界首帧门控 + 自检播报（0 参；模式 2）----
    if H.t_player then
        local m_reset = method_exact(H.t_player, "ResetEffects", 0)
        local h_reset = safe_hook(m_reset, { postfix = on_reset_effects }, "Player.ResetEffects")
        if h_reset then
            hooks[#hooks + 1] = h_reset
        else
            mod.warn("Player.ResetEffects Hook 未安装：进世界首帧自检播报不可用")
        end
    end

    -- ---- 聊天命令钩子（§9.2）：★ 默认关闭 ----
    --   唯一入口是 SayChatCommand.ProcessIncomingMessage(string, byte)：它注册为
    --   _defaultCommand，普通聊天与未知 /命令的原文都会送到这里，参数全是标量。
    --   关闭时这里一行都不执行（不 get_type、不 get_method、不装钩子）。
    if chat_cmd_on() then
        local t_say = patch.get_type("Terraria.Chat.Commands", "SayChatCommand")
        if not t_say then t_say = patch.get_type("Terraria.Chat", "SayChatCommand") end
        H.chat_say = t_say and method_exact(t_say, "ProcessIncomingMessage", 2) or nil
        if safe_hook(H.chat_say, { prefix = on_say_chat },
                "SayChatCommand.ProcessIncomingMessage") then
            S.chat_hooks = S.chat_hooks + 1
            log_info("弹幕工坊：聊天指令已启用（SayChatCommand.ProcessIncomingMessage）")
        else
            S.chat_hook_fail = "SayChatCommand.ProcessIncomingMessage(string,byte) 取不到或装不上"
            mod.warn("弹幕工坊：聊天指令已打开但装不上（" .. S.chat_hook_fail
                .. "）；请改用设置项 import_string 粘贴导入 / forge_export.txt 导出")
        end
    end

    -- ---- 诊断域的装载状态（§4.1：安装期一次性写入）----
    D.ai.fields       = mark(H.f_active and H.f_velocity and H.f_who_am_i)
    D.ai.methods      = mark(H.ai)
    D.newproj.fields  = mark(H.f_damage and H.f_velocity and H.f_type)
    D.newproj.methods = mark(H.new_projectile)
    D.track.fields    = mark(H.f_velocity and H.f_position and H.f_owner)
    D.track.methods   = mark(H.f_who_am_i and H.get_update_count)
    D.cand.fields     = mark(H.f_main_npc and H.f_npc_active)
    D.cand.methods    = mark(H.can_be_chased or (H.f_npc_life_max and H.f_npc_chaseable))
    D.hit.methods     = mark(H.strike_npc)
    D.hit.fields      = mark(H.f_num_hits)
    D.phys.fields     = mark(H.f_velocity and H.f_position and H.f_tile_collide)
    D.phys.methods    = "ok"
    D.weapon.fields   = mark(H.f_player_inventory and H.get_selected_item and H.f_item_type)
    D.weapon.methods  = "ok"
    if S.chat_hooks > 0 then
        D.chat.fields, D.chat.methods, D.chat.hooks = "ok", "ok", "ok"
    elseif chat_cmd_on() then
        D.chat.fields, D.chat.methods, D.chat.hooks = "fail", "fail", "fail"
        D.chat.enabled = false
    else
        -- 聊天指令默认关闭：这个域标成「未启用」，不误报成故障
        D.chat.fields, D.chat.methods, D.chat.hooks = "n/a", "n/a", "n/a"
        D.chat.enabled = false
    end
    D.cfg.fields, D.cfg.methods, D.cfg.hooks = "ok", "ok", "ok"
    D.perf.methods    = H.get_update_count and "ok" or "partial"
    D.perf.fields     = "ok"
    if not H.f_num_hits then
        mod.warn("未找到 Projectile.numHits：命中效果（分裂/爆炸/吸血/连锁）不可用")
    end
    if not H.strike_npc then
        mod.warn("未找到 NPC.StrikeNPC(6 参)：命中爆炸/闪电连锁不可用")
    end
    if not H.source_from_this then
        mod.warn("未找到 Projectile.GetProjectileSource_FromThis：命中分裂不可用")
    end

    S.ready = true
    log_info(string.format(
        "弹幕工坊 v%s 已启用：副本 %d 份 / %s / %d° / 触发 %d%% / 连锁 %d 层；追踪 %s（%s，强度 %d%%）；"
        .. "命中效果 %s；物理组 %s",
        VER, cfg.extra_copies, SPREAD_MODE_NAME[cfg.spread_mode] or "?", cfg.spread_angle_deg,
        cfg.trigger_chance_percent, cfg.chain_depth,
        cfg.homing_enabled and "开" or "关", tostring(cfg.perf_mode), cfg.homing_strength,
        hit_on and "开" or "关", physics_on and "开" or "关"))
end

-- ============================================================================
function cleanup()
    for _, h in ipairs(hooks) do
        pcall(function() h:remove() end)
    end
    hooks = {}
    S.ready = false
    S.spawning = 0
    S.env_in_world = false
    H.chat_say = nil
    S.chat_hooks = 0
    S.chat_hook_fail = nil
    S.import_active = nil
    S.import_seen_raw = nil
    -- 释放所有以整数下标为键的槽位状态与追踪名额（幂等）
    slot = {}
    tracked_ids = { n = 0 }
    tracked_n = 0
    evict_cursor = 0
    S.copy_ids = { n = 0 }
    S.frags, S.frag_have, S.frag_total = {}, 0, 0
    cand.n = 0
    cand.frame = nil
    cand.cells = {}
    cur_frame = nil
    last_sampled_id = -1
    log_info("弹幕工坊已卸载")
end

-- 与其它 4 个工坊模组保持一致的卸载入口（两种写法都留：全局函数 + mod.cleanup）
-- 28. 图形面板（mod.on_gui，5 页）—— v2.1.0
-- ----------------------------------------------------------------------------
-- ★ 面板本身**不做任何逐弹幕反射**：这里没有一处 patch.* / get_field_value /
--   invoke；状态页读模组自己的计数器，弹幕表只读 obs（§7.1 聚合观察器）。
--   tests/test.lua 用假 GUI + patch 调用计数断言 on_gui 内 patch.* = 0。
-- ★ 参数页数值项一律用纯数字输入（input_text + 确定/取消），不夹取 [lo,hi]；
--   设置页仍由 Info.json 的 min/max 夹取。
-- ★ 老加载器（没有 begin_scroll/end_scroll）自动回落「分页」，并在标题下写一行说明。
-- ============================================================================
local function install_gui()
    local GUI_FILE = "projectileforge-gui.txt"
    local PAGES = { "状态", "参数", "弹幕表", "一键", "关于" }
    local API_NAMES = {
        "text_at", "button_at", "rect", "checkbox", "button", "input_text",
        "begin_scroll", "end_scroll", "set_content_height", "set_width", "set_pos",
        "get_pos", "set_style", "set_title", "set_skin", "load_image", "image",
        "image_button", "nine_slice",
    }
    -- 七个折叠组：覆盖 DEFAULTS 的每一项（新增设置只要加进这张表）
    local GROUPS = {
        { title = "作用范围", keys = {
            "enabled", "affect_player_shots", "affect_enemy_shots", "affect_minions",
            "affect_sentries", "affect_hooks", "affect_bobbers", "scope_other",
            "filter_mode", "filter_id_1", "filter_id_2", "filter_id_3", "filter_id_4" } },
        { title = "副本与散射", keys = {
            "extra_copies", "spread_mode", "spread_angle_deg", "trigger_chance_percent",
            "chain_depth", "max_copies_per_second", "max_copies_per_frame",
            "copy_velocity_percent", "copy_damage_percent", "copy_full_damage",
            "skip_stationary" } },
        { title = "属性改写", keys = {
            "damage_percent", "knockback_percent", "velocity_percent", "scale_percent",
            "lifetime_percent", "pierce_bonus", "lock_scale", "lock_pierce",
            "apply_overrides_to_copies", "crit_transfer", "crit_bonus",
            "ignore_npc_immunity", "local_immunity_frames" } },
        { title = "追踪与索敌", keys = {
            "homing_enabled", "perf_mode", "homing_priority", "homing_strength",
            "homing_range", "track_interval", "enemy_track_interval",
            "global_scan_interval", "homing_flight_frames", "homing_ramp",
            "homing_stop_distance", "target_switch_cooldown" } },
        { title = "命中特效", keys = {
            "hit_split_copies", "hit_explosion_radius", "hit_explosion_damage_percent",
            "hit_lifesteal_percent", "hit_lightning_chain",
            "hit_lightning_damage_percent", "hit_lightning_radius" } },
        { title = "物理", keys = {
            "physics_no_gravity", "physics_pass_wall", "physics_bounce_limit",
            "physics_orbit_percent", "physics_return_home" } },
        { title = "性能与联机", keys = {
            "net_sync", "net_update_min_frames", "net_angle_deg", "weapon_filter_mode",
            "weapon_id_1", "weapon_id_2", "weapon_id_3", "weapon_id_4",
            "global_projectile_cap", "max_checks_per_frame", "adaptive_frame_skip",
            "adaptive_unit", "speed_override_interval", "global_shot_budget", "use_fastpath",
            "self_check", "diag_report_cmd", "diag_slow_ms",
            "chat_cmd", "import_string", "host_only", "tick_interval",
            "config_reload_sec", "write_log", "debug_log", "gui_enable", "gui_layout" } },
    }
    local LABELS = {
        enabled = "总开关", affect_player_shots = "作用于玩家弹幕",
        affect_enemy_shots = "作用于敌对弹幕", affect_minions = "作用于召唤物弹幕",
        affect_sentries = "作用于哨兵弹幕", affect_hooks = "作用于钩爪",
        affect_bobbers = "作用于钓鱼浮标", scope_other = "作用于其它弹幕",
        filter_mode = "类型过滤方式", filter_id_1 = "过滤名单 1（真实 ID，逗号分隔）",
        filter_id_2 = "过滤名单 2（真实 ID，逗号分隔）",
        filter_id_3 = "过滤名单 3（真实 ID，逗号分隔）",
        filter_id_4 = "过滤名单 4（真实 ID，逗号分隔）",
        extra_copies = "每发额外副本数", spread_mode = "散射模式（1 扇形 / 2 环形 / 3 随机 / 4 同向）",
        spread_angle_deg = "散射角度", trigger_chance_percent = "触发概率（%）",
        chain_depth = "分裂层数", max_copies_per_second = "每秒副本上限",
        max_copies_per_frame = "每帧副本上限", copy_velocity_percent = "副本速度（%）",
        copy_damage_percent = "副本伤害（%）", copy_full_damage = "副本满伤害",
        skip_stationary = "跳过静止弹幕", damage_percent = "伤害（%）",
        knockback_percent = "击退（%）", velocity_percent = "速度（%）",
        scale_percent = "体型（%）", lifetime_percent = "存活时间（%）",
        pierce_bonus = "穿透加成", lock_scale = "逐帧锁定体型",
        lock_pierce = "逐帧锁定穿透", apply_overrides_to_copies = "副本继承属性改写",
        crit_transfer = "暴击传递", crit_bonus = "暴击加成",
        ignore_npc_immunity = "无视 NPC 无敌帧", local_immunity_frames = "本地无敌帧（帧）",
        homing_enabled = "追踪总开关", perf_mode = "性能档", homing_priority = "索敌策略",
        homing_strength = "转向强度（%）", homing_range = "索敌半径",
        track_interval = "我方扫描间隔（帧）", enemy_track_interval = "敌方扫描间隔（帧）",
        global_scan_interval = "候选表刷新周期（帧）", homing_flight_frames = "只追踪前 N 帧",
        homing_ramp = "强度线性递增", homing_stop_distance = "停手距离",
        hit_split_copies = "命中分裂份数", hit_explosion_radius = "爆炸半径",
        hit_explosion_damage_percent = "爆炸伤害（%）", hit_lifesteal_percent = "吸血（%）",
        hit_lightning_chain = "闪电连锁跳数", hit_lightning_damage_percent = "闪电伤害（%）",
        hit_lightning_radius = "闪电半径", physics_no_gravity = "无重力直线锁",
        physics_pass_wall = "穿墙", physics_bounce_limit = "反弹上限",
        physics_orbit_percent = "环绕（度/帧×100）", physics_return_home = "归位",
        target_switch_cooldown = "目标切换冷却（帧，0=不限）",
        max_checks_per_frame = "每帧处理上限（0=不限）",
        adaptive_frame_skip = "自适应分帧", adaptive_unit = "自适应档位密度",
        speed_override_interval = "速度覆写间隔（帧）",
        global_shot_budget = "全局弹幕预算（0=不限）",
        use_fastpath = "C 快通道（实验，自检失败自动关）",
        net_sync = "网络同步", net_update_min_frames = "最小同步间隔（帧）",
        net_angle_deg = "同步角度阈值（度）", weapon_filter_mode = "武器名单方式",
        weapon_id_1 = "武器名单 1（真实 ID，逗号分隔）",
        weapon_id_2 = "武器名单 2（真实 ID，逗号分隔）",
        weapon_id_3 = "武器名单 3（真实 ID，逗号分隔）",
        weapon_id_4 = "武器名单 4（真实 ID，逗号分隔）",
        global_projectile_cap = "全局弹幕上限", self_check = "进世界自检播报",
        diag_report_cmd = "诊断命令", diag_slow_ms = "慢域阈值（ms）",
        chat_cmd = "聊天指令（默认关）", import_string = "粘贴导入设置串",
        host_only = "仅房主生效", tick_interval = "非关键刷新间隔（帧）",
        config_reload_sec = "自动重读设置间隔（秒）", write_log = "写日志",
        debug_log = "详细日志", gui_enable = "面板总开关", gui_layout = "面板布局",
    }
    local C = {
        panel = { 240, 228, 200, 246 }, title = { 236, 222, 194, 255 },
        button = { 214, 194, 158, 255 }, hover = { 234, 216, 176, 255 },
        active = { 176, 142, 92, 255 }, border = { 74, 46, 20, 255 },
        text = { 58, 38, 18, 255 }, accent = { 138, 40, 26, 255 },
        gold = { 156, 112, 44, 255 }, muted = { 108, 86, 58, 255 },
        white = { 255, 255, 255, 255 }, invis = { 255, 255, 255, 0 },
        row_a = { 228, 214, 184, 255 }, row_b = { 236, 224, 198, 255 },
        ok = { 74, 108, 46, 255 }, bad = { 168, 40, 32, 255 },
    }
    local GP = {
        inited = false, frames = 0, page = 1, sub = 1, sub_page = 1, page3_sub = 1,
        fold = {}, edit_key = nil, edit_buf = "", last_msg = "", last_err = nil,
        last_err_logged = false, selfcheck = "", player_only = false,
        g = 1, budget = 0, screen_w = 0, width_applied = -1, pos_applied = false,
        win_x = 40, win_y = 40, probe = { phase = 0, done = false },
        old_fallback = false, drawn = 0, drawn_keys = {},
        page3_total = 0, page3_shown = 0, setting_count = 0,
    }
    local G, IMG, IMG_TRIED, ASSETS_DONE = nil, {}, false, false
    do
        for k in pairs(DEFAULTS) do GP.setting_count = GP.setting_count + 1 end
    end

    -- ---------------------------------------------------------------- 基础工具
    local function num(v, d)
        v = tonumber(v)
        if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
        return v
    end
    local function U(v) return num(v, 0) * GP.g end
    local function has(n) return G ~= nil and type(G[n]) == "function" end
    local function api(n, ...)
        if not has(n) then return false end
        return pcall(G[n], ...)
    end
    local function byte_len(b)
        if b < 0x80 then return 1 end
        if b < 0xE0 then return 2 end
        if b < 0xF0 then return 3 end
        return 4
    end
    local function units(s)
        local n, i = 0, 1
        while i <= #s do
            local l = byte_len(string.byte(s, i))
            n = n + ((l == 1) and 1 or 2)
            i = i + l
        end
        return n
    end
    local function fit(s, bw, sc)
        s = tostring(s or "")
        if not bw or bw <= 0 then return s end
        local limit = bw / math.max(0.1, num(sc, 0.55))
        if units(s) <= limit then return s end
        local out, n, i = {}, 0, 1
        while i <= #s do
            local l = byte_len(string.byte(s, i))
            local w = (l == 1) and 1 or 2
            if n + w > limit - 2 then break end
            out[#out + 1] = s:sub(i, i + l - 1)
            n = n + w
            i = i + l
        end
        return table.concat(out) .. "…"
    end
    local function txt(x, y, s, col, sc, bw)
        if not has("text_at") then return end
        local t = fit(s, bw, sc or 0.55)
        pcall(G.text_at, num(x, 0), num(y, 0), t, col or C.text, num(sc, 0.55))
    end
    local function rect(x, y, w, h, col)
        if not has("rect") then return end
        w, h = num(w, 0), num(h, 0)
        if w <= 0 or h <= 0 then return end
        pcall(G.rect, num(x, 0), num(y, 0), w, h, col or C.row_a)
    end
    local function btn(x, y, w, h, label)
        if not has("button_at") then return false end
        w, h = num(w, 0), num(h, 0)
        if w <= 0 or h <= 0 then return false end
        local ok, hit = pcall(G.button_at, num(x, 0), num(y, 0), w, h, fit(label, w, 0.55))
        return ok and hit == true
    end
    local function ibtn(x, y, w, h, label, border)
        if IMG.button and has("image_button") then
            local ok, hit = pcall(G.image_button, IMG.button, num(x, 0), num(y, 0),
                num(w, 0), num(h, 0), fit(label, w, 0.55), num(border, 0))
            if ok then return hit == true end
        end
        return btn(x, y, w, h, label)
    end
    local function set_cursor(x, y)
        if has("set_cursor") then pcall(G.set_cursor, num(x, 0), num(y, 0)) end
    end

    -- ---------------------------------------------------------------- 状态文件
    local function save_state()
        local parts = { "page=" .. GP.page, "sub=" .. GP.sub, "page3_sub=" .. GP.page3_sub,
            "player_only=" .. tostring(GP.player_only) }
        for i = 1, #GROUPS do
            parts[#parts + 1] = "fold" .. i .. "=" .. ((GP.fold[i] == false) and "0" or "1")
        end
        if mod.write_file then mod.write_file(GUI_FILE, table.concat(parts, "\n")) end
    end
    local function load_state()
        if not mod.read_file then return end
        local raw = mod.read_file(GUI_FILE)
        if type(raw) ~= "string" then return end
        for k, v in raw:gmatch("([%w_]+)=(%S+)") do
            if k == "page" then GP.page = math.max(1, math.min(#PAGES, math.floor(num(v, 1))))
            elseif k == "sub" then GP.sub = math.max(1, math.floor(num(v, 1)))
            elseif k == "page3_sub" then GP.page3_sub = math.max(1, math.floor(num(v, 1)))
            elseif k == "player_only" then GP.player_only = (v == "true")
            elseif k:match("^fold%d+$") then
                local i = tonumber(k:match("^fold(%d+)$"))
                if i and v == "0" then GP.fold[i] = false elseif i then GP.fold[i] = true end
            end
        end
    end

    -- ---------------------------------------------------------------- 屏幕探测 / 皮肤
    local function avail()
        if GP.budget and GP.budget > 0 then return GP.budget end
        -- 探测失败时的保守值：给标题栏 + 上下内边距留足空间
        return 300.0
    end
    local function body_w()
        -- v2.2.0 宽度回收：外壳宽度 = body_w，绘制区再让出 8 单位右边距
        local w = U(458)
        if GP.screen_w > 0 and w > GP.screen_w * 0.94 then w = GP.screen_w * 0.94 end
        if w < U(180) then w = U(180) end
        return w
    end
    local function probe_step()
        local P = GP.probe
        if P.done then return end
        if GP.frames < 2 then return end
        if not has("get_pos") or not has("set_pos") then P.done = true; return end
        if P.phase == 0 then
            local ok, x, y = pcall(G.get_pos)
            if ok then GP.win_x, GP.win_y = num(x, 40), num(y, 40) end
            pcall(G.set_pos, 999999, 0)
            P.phase = 1
        elseif P.phase == 1 then
            local ok, x = pcall(G.get_pos)
            P.xmax = ok and num(x, 0) or 0
            pcall(G.set_pos, 0, 999999)
            P.phase = 2
        else
            local ok, _x, y = pcall(G.get_pos)
            P.ymax = ok and num(y, 0) or 0
            P.done = true
            if P.xmax > 20000 or P.ymax > 20000 then
                P.unclamped = true
            else
                local mn = math.min(P.xmax, P.ymax)
                local g = mn / 688.0
                if g < 1.0 then g = 1.0 end
                if g > 2.5 then g = 2.5 end
                GP.g = g
                GP.screen_w = P.xmax + 32.0 * g
                -- ★ v2.2.3：不再扣 win_y。实机反馈「面板高度偏低，编辑页键盘压到动作行」——
                --   探测时窗口内容高只有 300，win_y 又被减掉一次，预算被砍掉一格。
                --   现在按「窗口顶边可以上移」来算：预算只扣上下内边距，位置在 apply_geometry 里收。
                GP.budget = P.ymax - 24.0 * g - 4.0 * g
                if GP.budget < 340 then GP.budget = 340 end
                -- 探测时窗口高 ≈ 56g + 300（内容 300 是回退值）；据此估出屏幕高，
                -- 换算出「这个预算下窗口顶边最高能放到哪」，避免底部被屏幕裁掉。
                GP.y_cap = P.ymax + 300.0 - GP.budget
                if GP.y_cap < 0 then GP.y_cap = 0 end
            end
            pcall(G.set_pos, GP.win_x, GP.win_y)
            GP.pos_applied = true
        end
    end
    local function apply_geometry()
        local w = math.floor(body_w() + 0.5)
        if has("set_width") and GP.width_applied ~= w then
            if api("set_width", w) then GP.width_applied = w end
        end
        if GP.probe.done and not GP.pos_applied and has("set_pos") then
            local y = GP.win_y
            if GP.y_cap and y > GP.y_cap then y = GP.y_cap end
            if y < 0 then y = 0 end
            if api("set_pos", GP.win_x, y) then GP.pos_applied = true end
        end
    end
    local function ensure_images()
        if IMG_TRIED then return end
        IMG_TRIED = true
        if not has("load_image") then return end
        local order = { "white", "panel", "button", "glyph" }
        local paths = { white = "lib/ui/white.png", panel = "lib/ui/panel.png",
            button = "lib/ui/button.png", glyph = "lib/ui/glyph.png" }
        for i = 1, #order do
            local ok, id = pcall(G.load_image, paths[order[i]])
            if ok and type(id) == "string" then IMG[order[i]] = id end
        end
    end
    local function ensure_assets()
        ensure_images()
        if ASSETS_DONE then return end
        ASSETS_DONE = true
        if has("set_style") then
            pcall(G.set_style, { panel = C.panel, title = C.title, button = C.button,
                hover = C.hover, active = C.active, border = C.border, text = C.text })
        end
        if has("set_title") then pcall(G.set_title, "弹幕工坊 v" .. VER, "弹") end
        -- 图片先画一次才会解码（§4.2）；set_skin 之前先把四张图各画 1x1 透明一次
        if has("image") then
            for _, k in ipairs({ "white", "panel", "button", "glyph" }) do
                if IMG[k] then pcall(G.image, IMG[k], 0, 0, 1, 1, C.invis, nil) end
            end
        end
        if IMG.panel and IMG.glyph and has("set_skin") then
            local size = math.floor(U(40))
            if size < 24 then size = 24 end
            if size > 128 then size = 128 end
            pcall(G.set_skin, IMG.panel, 16, IMG.glyph, size, math.floor(U(10)))
        end
    end

    -- ---------------------------------------------------------------- 数据读写
    local function panel_set(k, v)
        local def = DEFAULTS[k]
        if def == nil then return false end
        -- 面板总开关只允许在 TEFManager 设置页改（自救通道，绝不能被覆盖层锁死）
        if k == "gui_enable" then return false end
        if type(def) == "boolean" then
            cfg[k] = (v == true)
        elseif type(def) == "number" then
            local n = tonumber(v)
            if not n or n ~= n or n == math.huge or n == -math.huge then return false end
            cfg[k] = math.floor(n)
        else
            cfg[k] = tostring(v or ""):sub(1, 500)
        end
        override[k] = cfg[k]
        on_settings_changed()
        return true
    end
    local function clear_override()
        for k in pairs(override) do override[k] = nil end
    end
    local function use_scroll()
        if cfg.gui_layout == "分页" then return false end
        if has("begin_scroll") and has("end_scroll") then return true end
        GP.old_fallback = true
        return false
    end
    local function field_label(k) return LABELS[k] or tostring(k) end
    local function field_height(k)
        if GP.edit_key == k then return U(112) end
        if type(DEFAULTS[k]) == "boolean" then return U(36) end
        if type(DEFAULTS[k]) == "number" then return U(44) end
        return U(44)
    end

    -- ---------------------------------------------------------------- 参数页控件
    local function cycle_choice(k)
        local vals = CHOICES[k] or {}
        if #vals == 0 then return end
        local cur = cfg[k]
        local idx = 1
        for i = 1, #vals do if vals[i] == cur then idx = i end end
        panel_set(k, vals[idx % #vals + 1])
    end
    local function confirm_edit()
        local k = GP.edit_key
        if not k then return end
        local def = DEFAULTS[k]
        if type(def) == "number" then
            local n = tonumber(GP.edit_buf)
            if n and n == n and n ~= math.huge and n ~= -math.huge then
                panel_set(k, math.floor(n))
            end
        else
            panel_set(k, GP.edit_buf or "")
        end
        GP.edit_key, GP.edit_buf = nil, ""
    end
    local function edit_buttons(y, bw)
        if btn(U(6), y + U(66), U(110), U(30), "确定") then confirm_edit() end
        if btn(U(122), y + U(66), U(110), U(30), "取消") then
            GP.edit_key, GP.edit_buf = nil, ""
        end
    end
    local function draw_editor(k, y, bw)
        local label = field_label(k)
        txt(U(8), y + U(3), label, C.gold, 0.55, bw - U(16))
        if has("input_text") then
            set_cursor(U(8), y + U(26))
            local ok, r = pcall(G.input_text, label, GP.edit_buf or "")
            if ok and type(r) == "string" then
                GP.edit_buf = r:gsub("[\r\n]", ""):sub(1, 120)
            end
        else
            txt(U(8), y + U(28), "当前值 " .. tostring(GP.edit_buf or ""), C.text, 0.55, bw - U(16))
        end
        edit_buttons(y, bw)
    end
    local function draw_field(k, y, bw)
        local def = DEFAULTS[k]
        local cur = cfg[k]
        if cur == nil then cur = def end
        GP.drawn = GP.drawn + 1
        GP.drawn_keys[k] = (GP.drawn_keys[k] or 0) + 1
        local h = field_height(k)
        rect(0, y, bw, h, C.row_b)
        local label = field_label(k)
        if type(def) == "boolean" then
            if k == "gui_enable" then
                txt(U(6), y + U(6), label .. "：" .. (cur and "开" or "关")
                    .. "（在 TEFManager 设置页改）", C.text, 0.55, bw - U(12))
            else
                txt(U(6), y + U(6), label .. "：" .. (cur and "开" or "关"), C.text, 0.55, bw - U(84))
                if btn(bw - U(74), y + U(4), U(68), U(28), "切换") then panel_set(k, not cur) end
            end
        elseif type(def) == "number" then
            if GP.edit_key == k then
                draw_editor(k, y, bw)
            else
                txt(U(6), y + U(7), label .. "：" .. tostring(cur), C.text, 0.55, bw - U(104))
                if btn(bw - U(94), y + U(6), U(88), U(28), "输入") then
                    GP.edit_key, GP.edit_buf = k, tostring(cur)
                end
            end
        elseif CHOICES[k] then
            txt(U(6), y + U(7), label .. "：" .. tostring(cur), C.text, 0.55, bw - U(104))
            if btn(bw - U(94), y + U(6), U(88), U(28), "切换") then cycle_choice(k) end
        elseif k == "import_string" then
            -- 导入串可能几百上千字符：面板不做编辑（input_text 会把长串截断），
            -- 只显示状态并提示去 TEFManager 设置页粘贴。
            local shown = tostring(cur or "")
            if shown == "" then shown = "（空，去 TEFManager 设置页粘贴）"
            else shown = "已有 " .. #shown .. " 字符（去 TEFManager 设置页修改）" end
            txt(U(6), y + U(7), label .. "：" .. shown, C.muted, 0.5, bw - U(12))
        else
            if GP.edit_key == k then
                draw_editor(k, y, bw)
            else
                local shown = tostring(cur or "")
                if shown == "" then shown = "（空）" end
                txt(U(6), y + U(7), label .. "：" .. shown, C.text, 0.55, bw - U(104))
                if btn(bw - U(94), y + U(6), U(88), U(28), "编辑") then
                    GP.edit_key, GP.edit_buf = k, tostring(cur or "")
                end
            end
        end
    end
    local function draw_group(gi, y, bw)
        local g = GROUPS[gi]
        local open = GP.fold[gi] ~= false
        rect(0, y, bw, U(34), C.row_a)
        if ibtn(U(4), y + U(2), bw - U(8), U(30),
                (open and "收起 " or "展开 ") .. gi .. "、" .. g.title, 10) then
            GP.fold[gi] = not open
            save_state()
            open = GP.fold[gi] ~= false
        end
        y = y + U(36)
        if not open then return y end
        for _, k in ipairs(g.keys) do
            draw_field(k, y, bw)
            y = y + field_height(k)
        end
        return y
    end
    local function params_height()
        local h = U(10)
        for gi = 1, #GROUPS do
            h = h + U(36)
            if GP.fold[gi] ~= false then
                for _, k in ipairs(GROUPS[gi].keys) do h = h + field_height(k) end
            end
        end
        return h + U(16)
    end
    local function draw_page_params(bw, top, availh)
        GP.drawn, GP.drawn_keys = 0, {}
        if use_scroll() then
            local ch = params_height()
            local ok, _sx, _sy, vw = pcall(G.begin_scroll, "pf_params", 0, top, bw, availh, bw, ch)
            if ok then
                local y = U(4)
                for gi = 1, #GROUPS do y = draw_group(gi, y, num(vw, bw)) end
                pcall(G.end_scroll)
                return
            end
        end
        local gi = math.max(1, math.min(#GROUPS, math.floor(num(GP.sub, 1))))
        GP.sub = gi
        local keys = GROUPS[gi].keys
        local per = math.max(1, math.floor((availh - U(40)) / U(46)))
        local pages = math.max(1, math.ceil(#keys / per))
        GP.sub_page = math.max(1, math.min(pages, math.floor(num(GP.sub_page, 1))))
        local sp = GP.sub_page
        local y = top
        if ibtn(U(4), y, U(100), U(28), "上一组", 10) then
            GP.sub = (gi - 2) % #GROUPS + 1; GP.sub_page = 1; save_state()
        end
        if ibtn(U(108), y, U(100), U(28), "下一组", 10) then
            GP.sub = gi % #GROUPS + 1; GP.sub_page = 1; save_state()
        end
        if ibtn(U(212), y, U(90), U(28), "上页", 10) then
            GP.sub_page = math.max(1, sp - 1); save_state()
        end
        if ibtn(U(306), y, U(90), U(28), "下页", 10) then
            GP.sub_page = math.min(pages, sp + 1); save_state()
        end
        txt(U(400), y + U(4), gi .. "/" .. #GROUPS .. " 组 " .. sp .. "/" .. pages .. " 页",
            C.muted, 0.5, bw - U(404))
        y = y + U(34)
        for i = (sp - 1) * per + 1, math.min(#keys, sp * per) do
            local k = keys[i]
            draw_field(k, y, bw)
            y = y + field_height(k)
        end
    end

    -- ---------------------------------------------------------------- 整页数字键盘（v2.2.2）
    -- 仿玩家工坊：点数值后不再在参数行里叠系统输入框，改成整页编辑页
    -- （本帧完全不画参数行），3 列 x 4 行 1~9 / +/- / 0 / 退格 + 清空/默认/确定/取消。
    -- 字符串项仍用加载器输入框（与玩家工坊一致），但同样占整页、不压别的行。
    local function edit_default()
        local k = GP.edit_key
        if not k then return end
        panel_set(k, DEFAULTS[k])
        GP.edit_key, GP.edit_buf = nil, ""
    end
    local function draw_editor_page(bw, top, ah)
        local k = GP.edit_key
        if not k then return end
        local num_mode = (type(DEFAULTS[k]) == "number")
        local label = field_label(k)
        local cur = cfg[k]
        if cur == nil then cur = DEFAULTS[k] end
        rect(0, top, bw, ah, C.row_b)
        txt(0, top + U(4), label, C.gold, 0.6, bw)
        local curtxt = tostring(cur)
        if curtxt == "" then curtxt = "（空）" end
        txt(0, top + U(22), "当前 " .. curtxt, C.muted, 0.5, bw)
        local gap = U(6)
        local act_h = U(30)
        local bottom = top + ah - U(4)
        local box_y = top + U(42)
        local box_h = U(38)
        local hint_y = box_y + box_h + U(3)
        if num_mode then
            local lim = LIMITS[k]
            if lim then
                txt(0, hint_y, string.format("范围 %d ~ %d（只提示，确定时不夹取）", lim[1], lim[2]),
                    C.muted, 0.4, bw)
            else
                txt(0, hint_y, "输入后点「确定」生效（只改本次游戏）", C.muted, 0.4, bw)
            end
        else
            txt(0, hint_y, "点下面的输入框，用系统键盘修改", C.muted, 0.4, bw)
        end

        local function actions(y, labels)
            local n = #labels
            local aw = math.floor((bw - gap * (n - 1)) / n)
            for i = 1, n do
                if btn((i - 1) * (aw + gap), y, aw, act_h, labels[i]) then return labels[i] end
            end
            return nil
        end

        if not num_mode then
            local iy = hint_y + U(14)
            if has("input_text") then
                set_cursor(0, iy)
                local ok, r = pcall(G.input_text, label, GP.edit_buf or "")
                if ok and type(r) == "string" then
                    GP.edit_buf = r:gsub("[\r\n]", ""):sub(1, 120)
                end
            else
                txt(0, iy, "本机没有输入框 API：可用「清空」或去 TEFManager 设置里改",
                    C.muted, 0.5, bw)
            end
            local hit = actions(bottom - act_h, { "清空", "确定", "取消" })
            if hit == "清空" then GP.edit_buf = ""
            elseif hit == "确定" then confirm_edit()
            elseif hit == "取消" then GP.edit_key, GP.edit_buf = nil, "" end
            return
        end

        -- ★ v2.2.3：键盘从动作行上方「往上排」，不是从上往下堆。
        --   这样无论面板多矮，第 4 行都不会压到 清空/默认/确定/取消（实机重叠的那一处）。
        local act_y = bottom - act_h
        local key_bottom = act_y - gap
        local key_top_min = hint_y + U(14)
        local kh = math.floor((key_bottom - gap * 3 - key_top_min) / 4)
        if kh < U(8) then kh = U(8) end
        if kh > U(44) then kh = U(44) end
        -- 关键：只按 key_bottom 反推 key_top，绝不把 key_top 往上夹 ——
        -- 往上夹会把第 4 行顶进动作行（实机截图里 清空/- 与 退格取消 重叠就是它）。
        local key_top = key_bottom - (4 * kh + gap * 3)
        local kw = math.floor((bw - gap * 2) / 3)
        local keys = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
                       { "+/-", "0", "退格" } }
        for ri = 1, 4 do
            for ci = 1, 3 do
                local key = keys[ri][ci]
                if btn((ci - 1) * (kw + gap), key_top + (ri - 1) * (kh + gap), kw, kh, key) then
                    if key == "退格" then
                        GP.edit_buf = tostring(GP.edit_buf or ""):sub(1, -2)
                    elseif key == "+/-" then
                        local b = tostring(GP.edit_buf or "")
                        if b:sub(1, 1) == "-" then GP.edit_buf = b:sub(2) else GP.edit_buf = "-" .. b end
                    else
                        GP.edit_buf = tostring(GP.edit_buf or "") .. key
                    end
                end
            end
        end
        -- 值框最后画：本帧刚按的键立刻出现在框里
        rect(0, box_y, bw, box_h, C.row_a)
        rect(0, box_y, U(3), box_h, C.accent)
        local shown = tostring(GP.edit_buf or "")
        local blink = (math.floor(GP.frames / 20) % 2 == 0) and "|" or ""
        if shown == "" then
            txt(U(10), box_y + U(11), "点键盘输入数字" .. blink, C.muted, 0.5, bw - U(18))
        else
            txt(U(10), box_y + U(10), shown .. blink, C.text, 0.65, bw - U(18))
        end
        local hit = actions(act_y, { "清空", "默认", "确定", "取消" })
        if hit == "清空" then GP.edit_buf = ""
        elseif hit == "默认" then edit_default()
        elseif hit == "确定" then confirm_edit()
        elseif hit == "取消" then GP.edit_key, GP.edit_buf = nil, "" end
    end

    -- ---------------------------------------------------------------- 状态页
    local function bool_row_at(k, label, x, y, w)
        rect(x, y, w, U(24), C.row_b)
        txt(x + U(4), y + U(3), label .. "：" .. (cfg[k] and "开" or "关"), C.text, 0.55, w - U(60))
        if btn(x + w - U(54), y, U(50), U(23), "切换") then panel_set(k, not cfg[k]) end
    end
    local function status_line(y, bw, label, value, col)
        rect(0, y, bw, U(24), C.row_a)
        txt(U(6), y + U(3), label .. "：" .. tostring(value), col or C.text, 0.55, bw - U(12))
        return y + U(24)
    end
    local function draw_page_status(bw, top, availh)
        local y = top
        rect(0, y, bw, U(28), C.row_b)
        txt(U(6), y + U(4), "总开关：" .. (cfg.enabled and "开" or "关"), C.text, 0.55, bw - U(84))
        if btn(bw - U(74), y + U(1), U(68), U(24), "切换") then panel_set("enabled", not cfg.enabled) end
        y = y + U(30)
        txt(0, y, "生效域（点一行切换）", C.gold, 0.5, bw)
        y = y + U(18)
        local scopes = {
            { "affect_player_shots", "玩家" }, { "affect_enemy_shots", "敌对" },
            { "affect_minions", "召唤" }, { "affect_sentries", "哨兵" },
            { "affect_hooks", "钩爪" }, { "affect_bobbers", "浮标" },
            { "scope_other", "其它" },
        }
        local half = bw / 2
        for i = 1, #scopes do
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            bool_row_at(scopes[i][1], scopes[i][2], col * (half + U(2)), y + row * U(25), half - U(2))
        end
        y = y + math.ceil(#scopes / 2) * U(25) + U(2)
        local same_frame = (stats.copies_frame_no == cur_frame)
        y = status_line(y, bw, "本帧副本", (same_frame and stats.copies_frame or 0)
            .. " / 上限 " .. tostring(cfg.global_projectile_cap)
            .. " · 秒峰值 " .. stats.last_sec_copies)
        y = status_line(y, bw, "追踪状态", (cfg.homing_enabled and "开" or "关")
            .. " · 名额 " .. tracked_n .. "/" .. K.MAX_TRACKED
            .. " · " .. tostring(cfg.homing_priority))
        local lim = cfg.max_checks_per_frame
        local lim_s = (type(lim) == "number" and lim > 0) and tostring(lim) or "不限"
        local bud = cfg.global_shot_budget
        local bud_s = "不限"
        if type(bud) == "number" and bud > 0 then
            bud_s = tostring((stats.budget_frame == cur_frame) and stats.budget_used or 0) .. "/" .. bud
        end
        local fp_s = "关"
        if cfg.use_fastpath then fp_s = FP.ok and "OK" or tostring(FP.result) end
        y = status_line(y, bw, "处理/预算", string.format("%d/%s · N=%d · 预算 %s · 快通道 %s",
            S.checks_used or 0, lim_s, S.adaptive_n or 1, bud_s, fp_s))
        local err = GP.last_err
        if not err then
            for i = 1, #domains do
                if domains[i].last_err then err = domains[i].name .. "：" .. tostring(domains[i].last_err) break end
            end
        end
        status_line(y, bw, "上次错误", err or "无", err and C.bad or C.ok)
        y = y + U(26)
        if btn(0, y, U(100), U(26), "刷新") then
            local raw = mod.read_file and mod.read_file("config.json") or nil
            if read_config(raw) then on_settings_changed(); GP.last_msg = "已重读设置"
            else GP.last_msg = "没有可读的 config.json（沿用当前值）" end
        end
        txt(U(108), y + U(4), GP.last_msg, C.muted, 0.5, bw - U(112))
    end

    -- ---------------------------------------------------------------- 弹幕表页
    local function draw_page_bombs(bw, top, availh)
        local now = now_seconds()
        obs.until_ = now + 2
        if obs.sec == 0 then obs.sec = now end
        local y = top
        rect(0, y, bw, U(30), C.row_b)
        txt(U(6), y + U(5), "只显示玩家弹幕：" .. (GP.player_only and "开" or "关"),
            C.text, 0.55, bw - U(84))
        if btn(bw - U(74), y + U(2), U(68), U(26), "切换") then
            GP.player_only = not GP.player_only
            save_state()
        end
        y = y + U(32)
        local rows = {}
        for t, rec in pairs(obs.cur) do
            if not GP.player_only or rec.pl > 0 then
                rows[#rows + 1] = { t = t, n = rec.n, pl = rec.pl }
            end
        end
        table.sort(rows, function(a, b)
            if a.n == b.n then return a.t < b.t end
            return a.n > b.n
        end)
        GP.page3_total = #rows
        local function row_text(r)
            local n = GP.player_only and r.pl or r.n
            return string.format("类型 %d   数量 %d   名单：%s%s", r.t, n,
                filter_set[r.t] and "是" or "否", GP.player_only and ("（玩家 " .. r.pl .. "）") or "")
        end
        local function empty_text()
            if obs.cur_n == 0 then return "未采集到活跃弹幕（本页打开后自动采集 1~2 秒）" end
            return "当前没有符合条件的弹幕"
        end
        if use_scroll() then
            local shown = math.min(#rows, 20)
            GP.page3_shown = shown
            local ch = U(40) + shown * U(30) + U(30)
            local ok, _sx, _sy, vw = pcall(G.begin_scroll, "pf_bombs", 0, y, bw, availh, bw, ch)
            if ok then
                local yy = U(4)
                txt(U(6), yy, "类型 / 数量 / 是否在过滤名单（数据 = 模组已采集的聚合值）", C.muted, 0.5, bw - U(12))
                yy = yy + U(26)
                if #rows == 0 then
                    txt(U(6), yy, empty_text(), C.muted, 0.55, num(vw, bw) - U(12))
                else
                    for i = 1, shown do
                        local r = rows[i]
                        rect(0, yy, num(vw, bw), U(28), (i % 2 == 0) and C.row_b or C.row_a)
                        txt(U(6), yy + U(4), row_text(r), C.text, 0.55, num(vw, bw) - U(12))
                        yy = yy + U(30)
                    end
                    if #rows > 20 then
                        txt(U(6), yy, "…还有 " .. (#rows - 20) .. " 项（只显示前 20）", C.gold, 0.5, num(vw, bw) - U(12))
                    end
                end
                pcall(G.end_scroll)
                return
            end
        end
        -- 分页/老加载器：按可用高度决定每页项数（最多 10 项）
        local per = math.max(1, math.min(10, math.floor((availh - U(70)) / U(30))))
        local total_pages = math.max(1, math.ceil(#rows / per))
        local ps = math.max(1, math.min(total_pages, math.floor(num(GP.page3_sub, 1))))
        GP.page3_sub = ps
        GP.page3_shown = math.min(per, math.max(0, #rows - (ps - 1) * per))
        if ibtn(U(4), y, U(100), U(28), "上一页", 10) then GP.page3_sub = (ps - 2) % total_pages + 1; save_state() end
        if ibtn(U(110), y, U(100), U(28), "下一页", 10) then GP.page3_sub = ps % total_pages + 1; save_state() end
        txt(U(220), y + U(4), "第 " .. ps .. "/" .. total_pages .. " 页（共 " .. #rows .. " 项）", C.muted, 0.5, bw - U(226))
        y = y + U(32)
        if #rows == 0 then
            txt(U(6), y, empty_text(), C.muted, 0.55, bw - U(12))
            return
        end
        for i = 1, GP.page3_shown do
            local r = rows[(ps - 1) * per + i]
            rect(0, y, bw, U(28), (i % 2 == 0) and C.row_b or C.row_a)
            txt(U(6), y + U(4), row_text(r), C.text, 0.55, bw - U(12))
            y = y + U(30)
        end
    end

    -- ---------------------------------------------------------------- 一键页
    local function panel_selfcheck()
        local lines, fails = {}, 0
        for i = 1, #domains do
            local d = domains[i]
            if d.fields == "fail" or d.hooks == "fail" or d.methods == "fail" then
                fails = fails + 1
                if #lines < 5 then lines[#lines + 1] = d.name .. "（失败）" end
            end
        end
        lines[#lines + 1] = string.format("诊断域 %d 个 / 失败 %d 个", #domains, fails)
        lines[#lines + 1] = string.format("弹幕表观察：本秒 %d 类", obs.cur_n)
        lines[#lines + 1] = string.format("追踪名额 %d/%d；本帧副本 %d", tracked_n, K.MAX_TRACKED,
            stats.copies_frame)
        return table.concat(lines, "；")
    end
    local function draw_page_actions(bw, top, availh)
        local y = top
        local bw2 = math.floor((bw - U(6)) / 2)
        if ibtn(0, y, bw2, U(34), "重读设置", 10) then
            clear_override()
            local raw = mod.read_file and mod.read_file("config.json") or nil
            if read_config(raw) then on_settings_changed(); GP.last_msg = "已重读 config.json"
            else GP.last_msg = "没有可读的 config.json（沿用当前值）" end
        end
        if ibtn(bw2 + U(6), y, bw2, U(34), "清空副本记录", 10) then
            S.copy_ids = { n = 0 }
            GP.last_msg = "已清空本模组的副本记录"
        end
        y = y + U(40)
        if ibtn(0, y, bw2, U(34), "追踪总开关：" .. (cfg.homing_enabled and "开" or "关"), 10) then
            panel_set("homing_enabled", not cfg.homing_enabled)
            GP.last_msg = "追踪已" .. (cfg.homing_enabled and "打开" or "关闭")
        end
        if ibtn(bw2 + U(6), y, bw2, U(34), "自检", 10) then
            GP.selfcheck = panel_selfcheck()
            GP.last_msg = "自检完成（结果见下方，不写聊天栏、不反射）"
        end
        y = y + U(42)
        rect(0, y, bw, U(30), C.row_a)
        txt(U(6), y + U(5), "最近操作：" .. (GP.last_msg ~= "" and GP.last_msg or "无"),
            C.muted, 0.5, bw - U(12))
        y = y + U(34)
        if GP.selfcheck ~= "" then
            txt(0, y, "自检结果：", C.gold, 0.55, bw)
            y = y + U(22)
            local s = GP.selfcheck
            local n = 0
            while #s > 0 and n < 4 do
                local line = s:sub(1, 52)
                local cut = line:match("^(.-)；")
                if cut then line = cut; s = s:sub(#cut + 2) else s = "" end
                txt(U(6), y, line, C.text, 0.5, bw - U(12))
                y = y + U(22)
                n = n + 1
            end
        end
        txt(0, y + U(10), "提示：本页只改本次游戏的运行时值（覆盖层），不写 TEFManager 设置；"
            .. "「重读设置」会清掉覆盖层。", C.muted, 0.5, bw)
    end

    -- ---------------------------------------------------------------- 关于/日志页
    local function draw_page_about(bw, top, availh)
        local y = top
        local api_have = 0
        for i = 1, #API_NAMES do if has(API_NAMES[i]) then api_have = api_have + 1 end end
        local lines = {
            "弹幕工坊 ProjectileForge v" .. VER .. "（pkg ailab.lua.projectileforge）",
            string.format("设置 %d 项 · mod.gui %d/%d 项 · 布局 %s%s", GP.setting_count, api_have,
                #API_NAMES, use_scroll() and "滚动" or "分页",
                GP.old_fallback and "（本机不支持滚动，已切换分页）" or ""),
            "面板零反射：状态/参数/弹幕表都只读模组自己的计数器与聚合值",
            string.format("状态文件 %s · config 热重读 %d 秒", GUI_FILE, num(cfg.config_reload_sec, 5)),
            "诊断域：",
        }
        for i = 1, #lines do
            txt(0, y, lines[i], (i == 1) and C.accent or C.text, 0.55, bw)
            y = y + U(24)
        end
        local shown = 0
        for i = 1, #domains do
            local d = domains[i]
            if d.errs > 0 and shown < 5 then
                txt(U(6), y, string.format("· %s：错误 %d 次，最近 %s", d.name, d.errs, tostring(d.last_err)),
                    C.bad, 0.5, bw - U(12))
                y = y + U(22)
                shown = shown + 1
            end
        end
        if shown == 0 then
            txt(U(6), y, "· 没有诊断错误记录", C.ok, 0.5, bw - U(12))
            y = y + U(22)
        end
        txt(0, y + U(4), "上次面板错误：" .. (GP.last_err or "无"), (GP.last_err and C.bad or C.ok), 0.5, bw)
        y = y + U(24)
        txt(0, y, "日志文件：forge_export.txt（导出串）· config.json（TEFManager 设置）", C.muted, 0.5, bw)
    end

    -- ---------------------------------------------------------------- 页头 / 帧
    local function page_head(bw)
        txt(0, U(2), "弹幕工坊 v" .. VER, C.accent, 0.64, bw)
        local sub = string.format("第 %d/5 页 · %s · 面板每帧 patch 调用 = 0", GP.page,
            use_scroll() and "滚动" or "分页")
        if GP.old_fallback then sub = sub .. "（本机不支持滚动，已切换分页）" end
        txt(0, U(19), sub, C.muted, 0.5, bw)
        local gap = U(4)
        local n = #PAGES
        local w = math.floor((bw - gap * (n - 1)) / n)
        for i = 1, n do
            local x = (i - 1) * (w + gap)
            if ibtn(x, U(34), w, U(28), PAGES[i], 10) then
                if GP.page ~= i then
                    GP.page = i
                    GP.edit_key, GP.edit_buf = nil, ""
                    save_state()
                end
            end
            if GP.page == i then rect(x, U(63), w, U(3), C.accent) end
        end
    end
    local function init_panel()
        GP.inited = true
        load_state()
        ensure_assets()
        if mod.info then
            mod.info(string.format("弹幕工坊 GUI v%s：面板已就绪（5 页 / %d 项设置 / 滚动 %s）",
                VER, GP.setting_count, has("begin_scroll") and "可用" or "不可用（回落分页）"))
        end
    end
    local function frame_body()
        probe_step()
        apply_geometry()
        ensure_assets()
        if not (has("text_at") and has("button_at")) then
            if has("text") then pcall(G.text, "弹幕工坊：当前加载器 GUI API 不足，面板不可用") end
            return
        end
        -- 加载器内容区宽度 = 窗口宽 - 2*PAD(12*g)，绘制必须用同一宽度，
        -- 否则右侧会压到边框/滚动条外侧。
        local bw = body_w() - U(24)
        page_head(bw)
        local top = U(72)
        local ah = avail() - top - U(6)
        if ah < U(80) then ah = U(80) end
        local page = GP.page
        if page == 1 then draw_page_status(bw, top, ah)
        elseif page == 2 then
            if GP.edit_key then draw_editor_page(bw, top, ah)
            else draw_page_params(bw, top, ah) end
        elseif page == 3 then draw_page_bombs(bw, top, ah)
        elseif page == 4 then draw_page_actions(bw, top, ah)
        else draw_page_about(bw, top, ah) end
        if not use_scroll() and has("set_content_height") then pcall(G.set_content_height, avail()) end
    end

    -- ---------------------------------------------------------------- 唯一入口
    mod.on_gui = function()
        G = (type(mod.gui) == "table") and mod.gui or nil
        if not G then return end
        -- ★ 每帧第一行就声明内容高（陷阱 27：写在最后 + 中间抛错 = 面板缩成一条）
        if has("set_content_height") then pcall(G.set_content_height, avail()) end
        if cfg.gui_enable ~= true then return end
        GP.frames = GP.frames + 1
        if not GP.inited then
            local ok0, e0 = pcall(init_panel)
            if not ok0 then GP.last_err = tostring(e0) end
        end
        local ok, err = pcall(frame_body)
        if not ok then
            GP.last_err = tostring(err)
            if not GP.last_err_logged then
                GP.last_err_logged = true
                if mod.error then mod.error("弹幕工坊 GUI：on_gui 出错，面板停在错误页：" .. tostring(err)) end
            end
        end
    end
    if _G.FORGE_TEST then _G.FORGE_GUI = GP end
end
install_gui()

mod.cleanup = cleanup

todo_list = { "setup" }
