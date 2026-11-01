-- ============================================================================
-- 世界工坊（WorldForge）v10.4.0   pkg_id = ailab.lua.worldforge
-- 适用：Terraria Mobile 1.4.5.8 + TEFKernel + LuaLoader 1.6.3
--
-- 【怎么读这份源码】Resources/lib/main.lua 是**拼装产物**，由
--   tools/gen.py + tools/parts/*.lua 生成。改代码请改 tools/parts/ 里的文件，
--   再跑 `python3 tools/gen.py`。直接改 main.lua 会在下次生成时被覆盖。
--
-- 【做什么】把「世界本身」做成一座可调的工坊，共 192 项设置、21 个分组：
--   总控（13）：模组总开关 / 联机：只有房主生效 / 自动重读设置 / 自动重读间隔 / 非关键项刷新间隔 / 详细日志 / 写入日志文件 / 进世界自检播报 / 诊断报告命令
--          聊天指令 /forge / 导入设置串 / 自动导出设置串 / 慢功能告警阈值
--   时间（5）：时间流速·倍率 / 冻结时间 / 昼夜锁定 / 锁定时刻 / 月相锁定
--   天气（17）：下雨模式 / 雨量强度 / 风力模式 / 风向 / 风力强度 / 沙尘暴模式 / 沙尘暴强度 / 锁定云量 / 禁止雷击 / 雷击频率 / 每帧最多补雷次数 / 雷击下落时长
--          同时存在的落雷上限 / 满屏落雷·每帧道数 / 两道落雷的最小间距 / 云量 / 夜晚坠落之星·倍率
--   事件（18）：永久血月 / 禁止血月 / 永久日食 / 禁止日食 / 永久史莱姆雨 / 禁止史莱姆雨 / 永久灯笼夜 / 永久派对 / 永久南瓜月 / 永久霜月 / 永久万圣节
--          永久圣诞节 / 入侵波数·倍率 / 事件进度·快进倍率 / 日食·自动重复间隔 / 血月·自动重复间隔 / 南瓜月·自动重复间隔 / 霜月·自动重复间隔
--   刷怪（17）：刷怪速度·倍率 / 刷怪上限·倍率 / 禁止自然刷怪 / 禁止 Boss 自然出现 / 禁止小动物自然出现 / 单次额外生成上限 / 召唤 Boss·一次几只
--          刷怪倍率·Boss / 刷怪倍率·史莱姆 / 刷怪倍率·飞行 / 刷怪倍率·地面 / 刷怪倍率·小动物 / 刷怪倍率·其它 / 禁止入侵事件 / 精英与稀有怪·刷新倍率
--          同屏敌怪硬上限 / 怪物 AI 简化（性能）
--   生物属性（26）：生物生命·倍率 / 生物伤害·倍率 / 生物防御·倍率 / 生物抗击退·倍率 / 生物金钱·倍率 / 生物体型·倍率 / 影响友好生物 / Boss 生命·倍率
--            Boss 伤害·倍率 / Boss 防御·倍率 / Boss 抗击退·倍率 / Boss 金钱·倍率 / Boss 体型·倍率 / 史莱姆·生命倍率 / 史莱姆·伤害倍率
--            史莱姆·防御倍率 / 飞行·生命倍率 / 飞行·伤害倍率 / 飞行·防御倍率 / 地面·生命倍率 / 地面·伤害倍率 / 地面·防御倍率 / 其它·生命倍率
--            其它·伤害倍率 / 其它·防御倍率 / 生物分类覆盖表
--   住房（4）：住房免装修 / 一屋可住人数 / 腐化房间也能住 / 无视房间尺寸
--   晶塔（5）：晶塔无视距离 / 晶塔无视危险判定 / 允许同类型晶塔多座 / 晶塔总数上限 / （暂未支持）
--   世界（6）：禁止生物群系蔓延 / 强制生物群系蔓延 / 取消世界边缘限制 / 重力药水屏幕不翻转 / 强制困难模式 / 生物群系蔓延速度
--   液体世界（4）：灌注液体 / 液面高度 / 每秒灌注格数 / 冻结液体
--   树木（1）：禁止树木生长
--   渔夫（4）：任务奖励·份数 / 完成即刷新任务 / 任务鱼堆叠上限 / （暂未支持）
--   稀有生物（4）：稀有生物·刷新倍率 / 稀有判定·沿用原版标记 / 稀有判定·掉落金钱（备用） / 稀有编号补表
--   复活与死亡（4）：复活地点 / 复活等待时间·倍率 / 秒复活（无视原版记时） / 死亡不掉墓碑
--   制作站（2）：制作范围加倍 / 炼药桌效果全局生效
--   世界生成（7）：陨石坠落 / 禁止世纪之花苞生成 / 立刻生成世纪之花苞 / 花苞补种间隔 / 世纪之花每天刷新 / 每天刷新·生成次数 / 花苞补种次数上限
--   地图生成（34）：世界大小 / 邪恶类型 / 额外生命水晶 / 额外魔力水晶 / 额外浮空岛 / 额外云岛 / 额外云湖 / 额外洞穴 / 矿脉方块编号 / 额外矿脉 / 额外微光群系
--            生成后清除的方块 / 每帧扫描格数 / （暂未支持） / 额外埋藏宝箱 / 宝箱主物品编号 / 宝箱样式 / 生成后方块替换 / 自定义世界宽度 / 自定义世界高度
--            自定义出生点 X / 自定义出生点 Y / 新世界起始时刻 / 浮空岛附带天空房与宝箱 / 天空房家具样式 / 云岛 / 云湖上也埋宝箱 / 天空结构的生成高度
--            地下结构的生成深度 / 结构类生成间隔 / 每帧最多清除 / 替换格数 / 单次生成·特征总量上限 / 特征生成速度 / 结构放置后补图块框架 / 图块扫描·分块批量读
--   地下结构（10）：额外大理石堆 / 额外神庙祭坛 / 额外暗影球 / 猩红心 / 额外墓地 / 额外苔藓 / 额外发光苔藓 / 额外神庙陷阱 / 额外岩浆陷阱 / 额外雕像陷阱 / 额外蜂巢
--   沙漠与绿洲（5）：额外宝石洞 / 额外矿斑 / 额外石斑 / 额外贝壳堆 / 额外绿洲
--   微光（4）：启用自定义微光配方 / 任意物品→任意物品 / （暂未支持） / 微光配方表
--   NPC 商店（2）：商店售价·倍率 / （暂未支持）
--   设置项类型：开关 56 / 整数 111 / 单选 13 / 文本 12
--
-- 【怎么做（钩子与时机，行号取自 Terraria 1.4.4 反编译源码）】
--   Main.DoUpdate 每帧顺序：UpdateWeather → NPC.SpawnNPC → Main.UpdateTime → WorldGen.UpdateWorld。
--   而 Main.UpdateTime 内部是：事件与雨天推进 → UpdateTimeRate → time += dayRate → 各事件 UpdateTime。
--   于是「世界属性」全部挂在 Main.UpdateTimeRate 的 postfix 上：原版刚把 dayRate 算完、
--   时间还没推进，改 dayRate 立刻生效，也不会被原版顶掉（本模组最关键的一个时机）。
--   各功能挂载点：
--     · 时间 / 天气 / 事件 / 刷怪参数 / 困难模式 → Main.UpdateTimeRate postfix（每帧一次）
--     · 心跳与设置热重载                     → Player.ResetEffects postfix（每帧一次，极廉价）
--     · 生物属性倍率                          → NPC.SetDefaults postfix（每个生物创建时一次）
--     · 分类刷怪（拦截 / 额外生成）            → NPC.NewNPC prefix+postfix
--       「是否自然刷怪」的窗口                → NPC.SpawnNPC prefix/postfix（只置标志）
--     · 住房免装修 / 一屋 N 人 / 无视腐化 / 无视尺寸 → WorldGen 的 RoomNeeds /
--       ScoreRoom_IsThisRoomOccupiedBySomeone / GetTileTypeCountByCategory / StartRoomCheck
--     · 晶塔规则                              → TeleportPylonsSystem 的 3 个标量入口 + NPC.AnyDanger
--     · 入侵波数 / 事件进度 / 自动重复事件    → Main.StartInvasion postfix + 帧阶段（41）
--     · 蔓延速率                              → WorldGen.UpdateWorld + UpdateWorld_OvergroundTile/UndergroundTile
--     · 液体灌注 / 世界边缘 / 重力不翻转      → WorldGen.PlaceLiquid / Player.BordersMovement + Main.ClampScreenPositionToWorld / Player.Update
--     · 商店售价                              → Item.GetStoreValue postfix（override_result）
--     · 地图生成：世界大小 / 邪恶类型          → WorldGen.CreateNewWorld prefix（★ 主线程）
--       （SetWorldSize(size) + setWorldSize() + WorldGenParam_Evil / crimson；
--        ★ v8：Task.Factory.StartNew 之前执行、clearWorld/Reset 都在 Task 里 → 写在这里时机等价）
--       ★★ v8 崩溃修复：WorldGen.Reset / WorldGen.GenerateWorld 跑在**世界生成线程**上，
--          一律不挂钩子 —— 从 worker 线程进 Lua = 两个线程同时用一个 lua_State → SIGSEGV）
--     · 地图生成：生成后追加 / 清除            → 主线程 CreateNewWorld 打标记 + world 阶段分帧任务队列
--       （每帧扫描 wgen_budget 格；v10 起 wgen_hits_frame 默认 1 = 不限制改动格数；
--        结构类每 wgen_struct_gap 帧 1 个，v10 起默认 1 = 不节流）
--       （★ v8：图块只读不写；清除走 KillTile（原版内部自己补 frame）；结构放完调 SectionTileFrame）
--     · 岛上天空房 / 宝箱                      → WorldGen.IslandHouse(3) + WorldGen.PlaceChest(5)
--     · 启动自检（默认开）                    → 进世界后的第一帧，聊天栏播报 + 日志
--     · 聊天命令（★ chat_cmd 默认关闭）        → 打开后才解析并挂
--       Chat.Commands.SayChatCommand.ProcessIncomingMessage(string, byte) 的 **prefix**
--       （它是 ChatInitializer 注册的默认命令：普通聊天与未知 /命令的原文都送到这里；
--         prefix 返回 true = 跳过原方法 = 顺手不让设置串被当普通聊天广播出去）
--       ★★ 绝不触达任何聊天消息类型（那种反射正是本工作区唯一那条实机 SIGABRT 证据）
--     · 落雷（v7）                            → WorldGen.SpawnStormLightning / TrySpawnLightningBolt
--       ★ v9：雷击「起手到劈击的时长」         → Projectile.AI_203_StormLightning(0 参) postfix，
--          按倍率增减落雷弹幕（type 1091）的 ai[1] 推进量（手机版 ai 是内联结构体 →
--          get_field_raw + string.unpack/pack，与参考库 auto-fisher / combat-pets 同款写法）
--       ★ v9：雷击「同时上限」                 → WorldGen.TrySpawnLightningBolt(int,int) prefix
--          里数 Main.projectile 中 type = 1091 且在 active 的弹幕
--     · 一键操作（v9）                        → 纯被动：只在 GUI / 聊天调用时执行一次，
--          不装任何钩子、默认路径零开销（分片 87）；世界特征类走地图生成的分帧任务队列
--          取消生成请用「任务状态 / 取消地图生成」两个一键按钮
--     · 禁止入侵                              → Main.StartInvasion prefix
--     · 生物群系蔓延                          → WorldGen.UpdateWorld prefix/postfix（只置标志）
--       + CreativePowers.ASharedTogglePower.get_Enabled
--       （UpdateWorld 每帧开头都把蔓延开关重置成「允许」，只有拦在它内部读开关那一句上才拦得住）
--
-- 【性能】默认配置（所有倍率 100、所有开关关）下：
--   · 每帧只执行一次极廉价的自检（一组数字比较）+ 每 30 帧一次的主菜单/设置检查；
--   · 所有写入都是「值与目标不同才写」（fset_if），默认路径上一次反射写入都不发；
--   · 冷路径钩子（住房 / 晶塔 / 刷怪 / 生物）第一行早退；
--   · ★ v8：图块扫描走「一行一次指针 + 64 格一块批量读」，原生调用数约降到 1/30；
--           清除不再逐格补 frame（原版 KillTile 内部已经补过）；结构类按间隔分帧。
--
-- 【稳定性设计】
--   · setup() 里只做元数据查询（get_type / get_field / get_method）与安装钩子，
--     绝不读写游戏字段、绝不调用游戏方法（头条红线）。
--   · 每个符号取不到 → 只打一条日志并关掉对应功能；const 字段一律不注册（红线 2）；
--     空句柄绝不下传给反射调用（红线 4）；实参个数用 method_param_count 核实（红线 3.5）。
--   · 所有字段读写都过 pcall；每个钩子用 pcall 安装，失败自动降级（见阶段日志）。
--   · 窗口标志（蔓延 / 晶塔传送 / 住房判定 / 自然刷怪）由 tick() 每帧强制清零，绝不跨帧残留。
--   · 本模组写过的、游戏不会自己重算的全局值（刷怪速度 / 刷怪上限 / 困难模式）
--     都登记在撤销表里，关总开关或卸载时按「三态比对」还原，不覆盖别人的修改。
--
-- 【未实机验证】本模组与工作区其它模组一样，只经过静态校验 + 假内核逻辑测试，
--   没有在真机上跑过。首次使用请先只装这一个模组。
-- ============================================================================

mod.meta = { pkg_id = "ailab.lua.worldforge", version = "10.4.0" }

local patch = mod.patch

-- ----------------------------------------------------------------------------
-- 设置项默认值（由 tools/gen.py 生成，改设置项请改 gen.py 的 spec）
-- ----------------------------------------------------------------------------
local DEFAULTS = {
    -- 总控
    enabled = true,
    host_only = true,
    hot_reload = true,
    config_reload_sec = 5,
    tick_interval = 10,
    verbose_log = false,
    write_log = false,
    self_check = true,
    diag_report_cmd = "forge stat",
    chat_cmd = false,
    import_string = "",
    export_mode = false,
    diag_slow_ms = 50,
    -- 时间
    time_speed = 100,
    time_freeze = false,
    day_lock = "none",
    lock_hour = 12,
    moon_lock = 1,
    -- 天气
    rain_mode = "none",
    rain_intensity = 60,
    wind_mode = "none",
    wind_dir = "east",
    wind_power = 40,
    sandstorm_mode = "none",
    sandstorm_power = 60,
    cloud_lock = false,
    lightning_block = false,
    lightning_freq_mult = 100,
    lightning_extra_cap = 5,
    lightning_windup_mult = 100,
    lightning_max_bolts = 1,
    lightning_spread_bolts = 1,
    lightning_min_dist = 1,
    cloud_amount = 101,
    starfall_mult = 100,
    -- 事件
    blood_moon = false,
    block_blood_moon = false,
    eclipse = false,
    block_eclipse = false,
    slime_rain = false,
    block_slime_rain = false,
    lantern_night = false,
    party = false,
    pumpkin_moon = false,
    snow_moon = false,
    always_halloween = false,
    always_christmas = false,
    invasion_wave_mult = 100,
    event_progress_mult = 100,
    eclipse_repeat_days = 1,
    bloodmoon_repeat_days = 1,
    pumpkinmoon_repeat_days = 1,
    snowmoon_repeat_days = 1,
    -- 刷怪
    spawn_rate_mult = 100,
    spawn_cap_mult = 100,
    no_natural_spawn = false,
    block_boss_spawn = false,
    block_passive_spawn = false,
    spawn_dup_limit = 3,
    boss_summon_count = 1,
    spawn_mult_boss = 100,
    spawn_mult_slime = 100,
    spawn_mult_flying = 100,
    spawn_mult_ground = 100,
    spawn_mult_passive = 100,
    spawn_mult_other = 100,
    block_invasion = false,
    elite_spawn_mult = 100,
    enemy_hard_cap = 1,
    ai_simplify = false,
    -- 生物属性
    npc_life_mult = 100,
    npc_damage_mult = 100,
    npc_defense_mult = 100,
    npc_kb_mult = 100,
    npc_value_mult = 100,
    npc_scale_mult = 100,
    npc_affect_friendly = false,
    boss_life_mult = 100,
    boss_damage_mult = 100,
    boss_defense_mult = 100,
    boss_kb_mult = 100,
    boss_value_mult = 100,
    boss_scale_mult = 100,
    cat_slime_life = 100,
    cat_slime_damage = 100,
    cat_slime_defense = 100,
    cat_fly_life = 100,
    cat_fly_damage = 100,
    cat_fly_defense = 100,
    cat_ground_life = 100,
    cat_ground_damage = 100,
    cat_ground_defense = 100,
    cat_other_life = 100,
    cat_other_damage = 100,
    cat_other_defense = 100,
    cat_override = "",
    -- 住房
    house_no_furniture = false,
    house_max_npcs = 1,
    house_ignore_evil = false,
    house_ignore_size = false,
    -- 晶塔
    pylon_ignore_range = false,
    pylon_ignore_danger = false,
    pylon_allow_dupes = false,
    pylon_total_limit = 1,
    pylon_note = "",
    -- 世界
    spread_block = false,
    spread_force = false,
    world_edge_free = false,
    gravity_no_flip = false,
    hardmode = false,
    spread_speed_mult = 100,
    -- 液体世界
    liquid_mode = "off",
    liquid_height = 50,
    liquid_rate = 500,
    freeze_liquid = false,
    -- 树木
    tree_block_growth = false,
    -- 渔夫
    angler_reward_mult = 1,
    angler_instant = false,
    quest_fish_stack = 1,
    angler_reward_note = "",
    -- 稀有生物
    rare_spawn_mult = 100,
    rare_use_rarity = true,
    rare_value_threshold = 5000,
    rare_list = "",
    -- 复活与死亡
    respawn_mode = "spawn",
    respawn_time_mult = 100,
    respawn_instant = false,
    tombstone_block = false,
    -- 制作站
    craft_range_boost = false,
    alchemy_table_global = false,
    -- 世界生成
    meteor_mode = "none",
    plantera_bulb_block = false,
    plantera_bulb_now = false,
    plantera_bulb_interval = 1,
    plantera_daily = false,
    plantera_daily_count = 10,
    plantera_bulb_runs = 1,
    -- 地图生成
    wgen_size = "none",
    wgen_evil = "none",
    wgen_life_crystals = 1,
    wgen_mana_crystals = 1,
    wgen_islands = 1,
    wgen_cloud_islands = 1,
    wgen_cloud_lakes = 1,
    wgen_caves = 1,
    wgen_ore_type = 7,
    wgen_ore_veins = 1,
    wgen_shimmer_biomes = 1,
    wgen_clear_tiles = "",
    wgen_budget = 4000,
    wgen_note = "",
    wgen_chests = 1,
    wgen_chest_item = 0,
    wgen_chest_style = 0,
    wgen_replace = "",
    wgen_custom_w = 0,
    wgen_custom_h = 0,
    wgen_spawn_x = 0,
    wgen_spawn_y = 0,
    wgen_start = "none",
    wgen_island_house = true,
    wgen_island_style = 1,
    wgen_cloud_chest = false,
    wgen_sky_band = "standard",
    wgen_under_band = "standard",
    wgen_struct_gap = 1,
    wgen_hits_frame = 1,
    wgen_total_cap = 5000,
    wgen_speed = 1,
    wgen_reframe = true,
    wgen_quick_scan = true,
    -- 地下结构
    wgen_marble = 1,
    wgen_lihzahrd = 1,
    wgen_shadow_orbs = 1,
    wgen_graveyards = 1,
    wgen_moss = 1,
    wgen_glow_moss = 1,
    wgen_mayan_traps = 1,
    wgen_lava_traps = 1,
    wgen_statue_traps = 1,
    wgen_bee_larva = 1,
    -- 沙漠与绿洲
    wgen_gem_caves = 1,
    wgen_ore_patches = 1,
    wgen_stone_patches = 1,
    wgen_shell_piles = 1,
    wgen_oases = 1,
    -- 微光
    shimmer_enable = false,
    shimmer_any_item = 1,
    chest_loot_note = "",
    shimmer_recipes = "",
    -- NPC 商店
    shop_price_mult = 100,
    shop_happiness_note = "",
}

-- INTEGER 的取值范围（读取时再夹一次，防止手改 config.json 越界）
local LIMITS = {
    config_reload_sec = { 1, 60 },
    tick_interval = { 1, 60 },
    diag_slow_ms = { 1, 1000 },
    time_speed = { 1, 10000 },
    lock_hour = { 1, 24 },
    moon_lock = { 1, 10 },
    rain_intensity = { 1, 100 },
    wind_power = { 1, 100 },
    sandstorm_power = { 1, 100 },
    lightning_freq_mult = { 1, 10000 },
    lightning_extra_cap = { 1, 200 },
    lightning_windup_mult = { 20, 400 },
    lightning_max_bolts = { 1, 21 },
    lightning_spread_bolts = { 1, 31 },
    lightning_min_dist = { 1, 121 },
    cloud_amount = { 1, 201 },
    starfall_mult = { 1, 10000 },
    invasion_wave_mult = { 1, 10000 },
    event_progress_mult = { 1, 10000 },
    eclipse_repeat_days = { 1, 31 },
    bloodmoon_repeat_days = { 1, 31 },
    pumpkinmoon_repeat_days = { 1, 31 },
    snowmoon_repeat_days = { 1, 31 },
    spawn_rate_mult = { 1, 10000 },
    spawn_cap_mult = { 1, 10000 },
    spawn_dup_limit = { 1, 100 },
    boss_summon_count = { 1, 10 },
    spawn_mult_boss = { 1, 10000 },
    spawn_mult_slime = { 1, 10000 },
    spawn_mult_flying = { 1, 10000 },
    spawn_mult_ground = { 1, 10000 },
    spawn_mult_passive = { 1, 10000 },
    spawn_mult_other = { 1, 10000 },
    elite_spawn_mult = { 1, 10000 },
    enemy_hard_cap = { 1, 501 },
    npc_life_mult = { 1, 10000 },
    npc_damage_mult = { 1, 10000 },
    npc_defense_mult = { 1, 10000 },
    npc_kb_mult = { 1, 10000 },
    npc_value_mult = { 1, 10000 },
    npc_scale_mult = { 1, 10000 },
    boss_life_mult = { 1, 10000 },
    boss_damage_mult = { 1, 10000 },
    boss_defense_mult = { 1, 10000 },
    boss_kb_mult = { 1, 10000 },
    boss_value_mult = { 1, 10000 },
    boss_scale_mult = { 1, 10000 },
    cat_slime_life = { 1, 10000 },
    cat_slime_damage = { 1, 10000 },
    cat_slime_defense = { 1, 10000 },
    cat_fly_life = { 1, 10000 },
    cat_fly_damage = { 1, 10000 },
    cat_fly_defense = { 1, 10000 },
    cat_ground_life = { 1, 10000 },
    cat_ground_damage = { 1, 10000 },
    cat_ground_defense = { 1, 10000 },
    cat_other_life = { 1, 10000 },
    cat_other_damage = { 1, 10000 },
    cat_other_defense = { 1, 10000 },
    house_max_npcs = { 1, 100 },
    pylon_total_limit = { 1, 100 },
    spread_speed_mult = { 1, 2400 },
    liquid_height = { 1, 100 },
    liquid_rate = { 1, 5000 },
    angler_reward_mult = { 1, 100 },
    quest_fish_stack = { 1, 9999 },
    rare_spawn_mult = { 1, 10000 },
    rare_value_threshold = { 1, 1000000 },
    respawn_time_mult = { 1, 10000 },
    plantera_bulb_interval = { 1, 241 },
    plantera_daily_count = { 1, 100 },
    plantera_bulb_runs = { 1, 101 },
    wgen_life_crystals = { 1, 501 },
    wgen_mana_crystals = { 1, 501 },
    wgen_islands = { 1, 21 },
    wgen_cloud_islands = { 1, 21 },
    wgen_cloud_lakes = { 1, 21 },
    wgen_caves = { 1, 201 },
    wgen_ore_type = { 1, 1000 },
    wgen_ore_veins = { 1, 301 },
    wgen_shimmer_biomes = { 1, 6 },
    wgen_budget = { 1, 20000 },
    wgen_chests = { 1, 101 },
    wgen_chest_item = { 0, 6000 },
    wgen_chest_style = { 0, 47 },
    wgen_custom_w = { 0, 16800 },
    wgen_custom_h = { 0, 4800 },
    wgen_spawn_x = { 0, 16800 },
    wgen_spawn_y = { 0, 4800 },
    wgen_island_style = { 1, 4 },
    wgen_struct_gap = { 1, 120 },
    wgen_hits_frame = { 1, 2001 },
    wgen_total_cap = { 1, 5000 },
    wgen_speed = { 1, 20 },
    wgen_marble = { 1, 21 },
    wgen_lihzahrd = { 1, 11 },
    wgen_shadow_orbs = { 1, 21 },
    wgen_gem_caves = { 1, 51 },
    wgen_ore_patches = { 1, 101 },
    wgen_graveyards = { 1, 21 },
    wgen_moss = { 1, 41 },
    wgen_glow_moss = { 1, 41 },
    wgen_mayan_traps = { 1, 41 },
    wgen_lava_traps = { 1, 41 },
    wgen_statue_traps = { 1, 41 },
    wgen_bee_larva = { 1, 41 },
    wgen_stone_patches = { 1, 101 },
    wgen_shell_piles = { 1, 51 },
    wgen_oases = { 1, 11 },
    shimmer_any_item = { 1, 6001 },
    shop_price_mult = { 1, 10000 },
}

-- CHOICE 的合法取值（不在表里 → 回到默认档，兼容旧版 config.json 里的数字）
local CHOICES = {
    day_lock = { "none", "day", "night", "clock" },
    rain_mode = { "none", "on", "off" },
    wind_mode = { "none", "lock", "calm" },
    wind_dir = { "west", "still", "east" },
    sandstorm_mode = { "none", "on", "off" },
    liquid_mode = { "off", "water", "lava", "honey" },
    respawn_mode = { "spawn", "in_place" },
    meteor_mode = { "none", "block", "boost", "now" },
    wgen_size = { "none", "small", "medium", "large" },
    wgen_evil = { "none", "random", "corruption", "crimson" },
    wgen_start = { "none", "day", "night", "dusk" },
    wgen_sky_band = { "standard", "low", "high" },
    wgen_under_band = { "standard", "shallow", "deep", "all" },
}

-- ★ v8.1：设置项 → { 分组, 标题, 单位 }（GUI 面板用；和 TEFManager 设置界面显示的一致）
local KEY_META = {
    enabled = { "总控", "模组总开关", "" },
    host_only = { "总控", "联机：只有房主生效", "" },
    hot_reload = { "总控", "自动重读设置", "" },
    config_reload_sec = { "总控", "自动重读间隔", "秒" },
    tick_interval = { "总控", "非关键项刷新间隔", "帧" },
    verbose_log = { "总控", "详细日志", "" },
    write_log = { "总控", "写入日志文件", "" },
    self_check = { "总控", "进世界自检播报", "" },
    diag_report_cmd = { "总控", "诊断报告命令", "" },
    chat_cmd = { "总控", "聊天指令 /forge", "" },
    import_string = { "总控", "导入设置串", "" },
    export_mode = { "总控", "自动导出设置串", "" },
    diag_slow_ms = { "总控", "慢功能告警阈值", "毫秒" },
    time_speed = { "时间", "时间流速·倍率", "%" },
    time_freeze = { "时间", "冻结时间", "" },
    day_lock = { "时间", "昼夜锁定", "" },
    lock_hour = { "时间", "锁定时刻", "时" },
    moon_lock = { "时间", "月相锁定", "档" },
    rain_mode = { "天气", "下雨模式", "" },
    rain_intensity = { "天气", "雨量强度", "%" },
    wind_mode = { "天气", "风力模式", "" },
    wind_dir = { "天气", "风向", "" },
    wind_power = { "天气", "风力强度", "%" },
    sandstorm_mode = { "天气", "沙尘暴模式", "" },
    sandstorm_power = { "天气", "沙尘暴强度", "%" },
    cloud_lock = { "天气", "锁定云量", "" },
    lightning_block = { "天气", "禁止雷击", "" },
    lightning_freq_mult = { "天气", "雷击频率", "%" },
    lightning_extra_cap = { "天气", "每帧最多补雷次数", "次" },
    lightning_windup_mult = { "天气", "雷击下落时长", "%" },
    lightning_max_bolts = { "天气", "同时存在的落雷上限", "道" },
    lightning_spread_bolts = { "天气", "满屏落雷·每帧道数", "道" },
    lightning_min_dist = { "天气", "两道落雷的最小间距", "格" },
    cloud_amount = { "天气", "云量", "档" },
    starfall_mult = { "天气", "夜晚坠落之星·倍率", "%" },
    blood_moon = { "事件", "永久血月", "" },
    block_blood_moon = { "事件", "禁止血月", "" },
    eclipse = { "事件", "永久日食", "" },
    block_eclipse = { "事件", "禁止日食", "" },
    slime_rain = { "事件", "永久史莱姆雨", "" },
    block_slime_rain = { "事件", "禁止史莱姆雨", "" },
    lantern_night = { "事件", "永久灯笼夜", "" },
    party = { "事件", "永久派对", "" },
    pumpkin_moon = { "事件", "永久南瓜月", "" },
    snow_moon = { "事件", "永久霜月", "" },
    always_halloween = { "事件", "永久万圣节", "" },
    always_christmas = { "事件", "永久圣诞节", "" },
    invasion_wave_mult = { "事件", "入侵波数·倍率", "%" },
    event_progress_mult = { "事件", "事件进度·快进倍率", "%" },
    eclipse_repeat_days = { "事件", "日食·自动重复间隔", "天" },
    bloodmoon_repeat_days = { "事件", "血月·自动重复间隔", "天" },
    pumpkinmoon_repeat_days = { "事件", "南瓜月·自动重复间隔", "天" },
    snowmoon_repeat_days = { "事件", "霜月·自动重复间隔", "天" },
    spawn_rate_mult = { "刷怪", "刷怪速度·倍率", "%" },
    spawn_cap_mult = { "刷怪", "刷怪上限·倍率", "%" },
    no_natural_spawn = { "刷怪", "禁止自然刷怪", "" },
    block_boss_spawn = { "刷怪", "禁止 Boss 自然出现", "" },
    block_passive_spawn = { "刷怪", "禁止小动物自然出现", "" },
    spawn_dup_limit = { "刷怪", "单次额外生成上限", "只" },
    boss_summon_count = { "刷怪", "召唤 Boss·一次几只", "只" },
    spawn_mult_boss = { "刷怪", "刷怪倍率·Boss", "%" },
    spawn_mult_slime = { "刷怪", "刷怪倍率·史莱姆", "%" },
    spawn_mult_flying = { "刷怪", "刷怪倍率·飞行", "%" },
    spawn_mult_ground = { "刷怪", "刷怪倍率·地面", "%" },
    spawn_mult_passive = { "刷怪", "刷怪倍率·小动物", "%" },
    spawn_mult_other = { "刷怪", "刷怪倍率·其它", "%" },
    block_invasion = { "刷怪", "禁止入侵事件", "" },
    elite_spawn_mult = { "刷怪", "精英与稀有怪·刷新倍率", "%" },
    enemy_hard_cap = { "刷怪", "同屏敌怪硬上限", "只" },
    ai_simplify = { "刷怪", "怪物 AI 简化（性能）", "" },
    npc_life_mult = { "生物属性", "生物生命·倍率", "%" },
    npc_damage_mult = { "生物属性", "生物伤害·倍率", "%" },
    npc_defense_mult = { "生物属性", "生物防御·倍率", "%" },
    npc_kb_mult = { "生物属性", "生物抗击退·倍率", "%" },
    npc_value_mult = { "生物属性", "生物金钱·倍率", "%" },
    npc_scale_mult = { "生物属性", "生物体型·倍率", "%" },
    npc_affect_friendly = { "生物属性", "影响友好生物", "" },
    boss_life_mult = { "生物属性", "Boss 生命·倍率", "%" },
    boss_damage_mult = { "生物属性", "Boss 伤害·倍率", "%" },
    boss_defense_mult = { "生物属性", "Boss 防御·倍率", "%" },
    boss_kb_mult = { "生物属性", "Boss 抗击退·倍率", "%" },
    boss_value_mult = { "生物属性", "Boss 金钱·倍率", "%" },
    boss_scale_mult = { "生物属性", "Boss 体型·倍率", "%" },
    cat_slime_life = { "生物属性", "史莱姆·生命倍率", "%" },
    cat_slime_damage = { "生物属性", "史莱姆·伤害倍率", "%" },
    cat_slime_defense = { "生物属性", "史莱姆·防御倍率", "%" },
    cat_fly_life = { "生物属性", "飞行·生命倍率", "%" },
    cat_fly_damage = { "生物属性", "飞行·伤害倍率", "%" },
    cat_fly_defense = { "生物属性", "飞行·防御倍率", "%" },
    cat_ground_life = { "生物属性", "地面·生命倍率", "%" },
    cat_ground_damage = { "生物属性", "地面·伤害倍率", "%" },
    cat_ground_defense = { "生物属性", "地面·防御倍率", "%" },
    cat_other_life = { "生物属性", "其它·生命倍率", "%" },
    cat_other_damage = { "生物属性", "其它·伤害倍率", "%" },
    cat_other_defense = { "生物属性", "其它·防御倍率", "%" },
    cat_override = { "生物属性", "生物分类覆盖表", "" },
    house_no_furniture = { "住房", "住房免装修", "" },
    house_max_npcs = { "住房", "一屋可住人数", "个" },
    house_ignore_evil = { "住房", "腐化房间也能住", "" },
    house_ignore_size = { "住房", "无视房间尺寸", "" },
    pylon_ignore_range = { "晶塔", "晶塔无视距离", "" },
    pylon_ignore_danger = { "晶塔", "晶塔无视危险判定", "" },
    pylon_allow_dupes = { "晶塔", "允许同类型晶塔多座", "" },
    pylon_total_limit = { "晶塔", "晶塔总数上限", "座" },
    pylon_note = { "晶塔", "（暂未支持）", "" },
    spread_block = { "世界", "禁止生物群系蔓延", "" },
    spread_force = { "世界", "强制生物群系蔓延", "" },
    world_edge_free = { "世界", "取消世界边缘限制", "" },
    gravity_no_flip = { "世界", "重力药水屏幕不翻转", "" },
    hardmode = { "世界", "强制困难模式", "" },
    spread_speed_mult = { "世界", "生物群系蔓延速度", "%" },
    liquid_mode = { "液体世界", "灌注液体", "" },
    liquid_height = { "液体世界", "液面高度", "%" },
    liquid_rate = { "液体世界", "每秒灌注格数", "格/帧" },
    freeze_liquid = { "液体世界", "冻结液体", "" },
    tree_block_growth = { "树木", "禁止树木生长", "" },
    angler_reward_mult = { "渔夫", "任务奖励·份数", "份" },
    angler_instant = { "渔夫", "完成即刷新任务", "" },
    quest_fish_stack = { "渔夫", "任务鱼堆叠上限", "条" },
    angler_reward_note = { "渔夫", "（暂未支持）", "" },
    rare_spawn_mult = { "稀有生物", "稀有生物·刷新倍率", "%" },
    rare_use_rarity = { "稀有生物", "稀有判定·沿用原版标记", "" },
    rare_value_threshold = { "稀有生物", "稀有判定·掉落金钱（备用）", "铜" },
    rare_list = { "稀有生物", "稀有编号补表", "" },
    respawn_mode = { "复活与死亡", "复活地点", "" },
    respawn_time_mult = { "复活与死亡", "复活等待时间·倍率", "%" },
    respawn_instant = { "复活与死亡", "秒复活（无视原版记时）", "" },
    tombstone_block = { "复活与死亡", "死亡不掉墓碑", "" },
    craft_range_boost = { "制作站", "制作范围加倍", "" },
    alchemy_table_global = { "制作站", "炼药桌效果全局生效", "" },
    meteor_mode = { "世界生成", "陨石坠落", "" },
    plantera_bulb_block = { "世界生成", "禁止世纪之花苞生成", "" },
    plantera_bulb_now = { "世界生成", "立刻生成世纪之花苞", "" },
    plantera_bulb_interval = { "世界生成", "花苞补种间隔", "档" },
    plantera_daily = { "世界生成", "世纪之花每天刷新", "" },
    plantera_daily_count = { "世界生成", "每天刷新·生成次数", "次" },
    plantera_bulb_runs = { "世界生成", "花苞补种次数上限", "次" },
    wgen_size = { "地图生成", "世界大小", "" },
    wgen_evil = { "地图生成", "邪恶类型", "" },
    wgen_life_crystals = { "地图生成", "额外生命水晶", "个" },
    wgen_mana_crystals = { "地图生成", "额外魔力水晶", "个" },
    wgen_islands = { "地图生成", "额外浮空岛", "座" },
    wgen_cloud_islands = { "地图生成", "额外云岛", "座" },
    wgen_cloud_lakes = { "地图生成", "额外云湖", "处" },
    wgen_caves = { "地图生成", "额外洞穴", "个" },
    wgen_ore_type = { "地图生成", "矿脉方块编号", "编号" },
    wgen_ore_veins = { "地图生成", "额外矿脉", "条" },
    wgen_shimmer_biomes = { "地图生成", "额外微光群系", "处" },
    wgen_clear_tiles = { "地图生成", "生成后清除的方块", "" },
    wgen_budget = { "地图生成", "每帧扫描格数", "格/帧" },
    wgen_note = { "地图生成", "（暂未支持）", "" },
    wgen_chests = { "地图生成", "额外埋藏宝箱", "个" },
    wgen_chest_item = { "地图生成", "宝箱主物品编号", "编号" },
    wgen_chest_style = { "地图生成", "宝箱样式", "样式" },
    wgen_replace = { "地图生成", "生成后方块替换", "" },
    wgen_custom_w = { "地图生成", "自定义世界宽度", "格" },
    wgen_custom_h = { "地图生成", "自定义世界高度", "格" },
    wgen_spawn_x = { "地图生成", "自定义出生点 X", "格" },
    wgen_spawn_y = { "地图生成", "自定义出生点 Y", "格" },
    wgen_start = { "地图生成", "新世界起始时刻", "" },
    wgen_island_house = { "地图生成", "浮空岛附带天空房与宝箱", "" },
    wgen_island_style = { "地图生成", "天空房家具样式", "样式" },
    wgen_cloud_chest = { "地图生成", "云岛 / 云湖上也埋宝箱", "" },
    wgen_sky_band = { "地图生成", "天空结构的生成高度", "" },
    wgen_under_band = { "地图生成", "地下结构的生成深度", "" },
    wgen_struct_gap = { "地图生成", "结构类生成间隔", "帧" },
    wgen_hits_frame = { "地图生成", "每帧最多清除 / 替换格数", "格/帧" },
    wgen_total_cap = { "地图生成", "单次生成·特征总量上限", "个" },
    wgen_speed = { "地图生成", "特征生成速度", "个/帧" },
    wgen_reframe = { "地图生成", "结构放置后补图块框架", "" },
    wgen_quick_scan = { "地图生成", "图块扫描·分块批量读", "" },
    wgen_marble = { "地下结构", "额外大理石堆", "处" },
    wgen_lihzahrd = { "地下结构", "额外神庙祭坛", "座" },
    wgen_shadow_orbs = { "地下结构", "额外暗影球 / 猩红心", "个" },
    wgen_gem_caves = { "沙漠与绿洲", "额外宝石洞", "处" },
    wgen_ore_patches = { "沙漠与绿洲", "额外矿斑", "处" },
    wgen_graveyards = { "地下结构", "额外墓地", "处" },
    wgen_moss = { "地下结构", "额外苔藓", "处" },
    wgen_glow_moss = { "地下结构", "额外发光苔藓", "处" },
    wgen_mayan_traps = { "地下结构", "额外神庙陷阱", "处" },
    wgen_lava_traps = { "地下结构", "额外岩浆陷阱", "处" },
    wgen_statue_traps = { "地下结构", "额外雕像陷阱", "处" },
    wgen_bee_larva = { "地下结构", "额外蜂巢", "处" },
    wgen_stone_patches = { "沙漠与绿洲", "额外石斑", "处" },
    wgen_shell_piles = { "沙漠与绿洲", "额外贝壳堆", "处" },
    wgen_oases = { "沙漠与绿洲", "额外绿洲", "处" },
    shimmer_enable = { "微光", "启用自定义微光配方", "" },
    shimmer_any_item = { "微光", "任意物品→任意物品", "编号" },
    chest_loot_note = { "微光", "（暂未支持）", "" },
    shimmer_recipes = { "微光", "微光配方表", "" },
    shop_price_mult = { "NPC 商店", "商店售价·倍率", "%" },
    shop_happiness_note = { "NPC 商店", "（暂未支持）", "" },
}

-- UI 值 → 内部语义值的偏移（TEFManager 的 INTEGER 最小值会被顶成 1，
-- 所以「0 = 关闭」这类语义在界面上要从 1 起算，读回来减掉这个偏移）
local UI_OFFSET = {
    lightning_max_bolts = 1,
    lightning_spread_bolts = 1,
    lightning_min_dist = 1,
    eclipse_repeat_days = 1,
    bloodmoon_repeat_days = 1,
    pumpkinmoon_repeat_days = 1,
    snowmoon_repeat_days = 1,
    enemy_hard_cap = 1,
    plantera_bulb_interval = 1,
    plantera_bulb_runs = 1,
    wgen_life_crystals = 1,
    wgen_mana_crystals = 1,
    wgen_islands = 1,
    wgen_cloud_islands = 1,
    wgen_cloud_lakes = 1,
    wgen_caves = 1,
    wgen_ore_veins = 1,
    wgen_shimmer_biomes = 1,
    wgen_chests = 1,
    wgen_hits_frame = 1,
    wgen_marble = 1,
    wgen_lihzahrd = 1,
    wgen_shadow_orbs = 1,
    wgen_gem_caves = 1,
    wgen_ore_patches = 1,
    wgen_graveyards = 1,
    wgen_moss = 1,
    wgen_glow_moss = 1,
    wgen_mayan_traps = 1,
    wgen_lava_traps = 1,
    wgen_statue_traps = 1,
    wgen_bee_larva = 1,
    wgen_stone_patches = 1,
    wgen_shell_piles = 1,
    wgen_oases = 1,
    shimmer_any_item = 1,
}



-- ============================================================================
-- 05 · 共享状态（★ 必须是第一个分片）
-- ----------------------------------------------------------------------------
-- Lua 的词法作用域规则：函数体里引用的 local 必须在**函数定义处**已经声明，
-- 否则那个名字会被当成全局变量（读到 nil）。v1.0.0 吃过这个亏（「运行状态与句柄
-- 必须在回调定义之前声明」那段注释），所以现在把跨文件共享的状态一次性集中到最前面，
-- 后面任何一个分片都不必再关心声明顺序。
--
-- 约定：**任何跨分片共享的可变状态都写在这里**；分片内部私有的临时量才用 local。
-- ============================================================================

-- 设置值：config.json 的解析结果，初值 = Info.json 里的默认值
local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end

-- 计划：build_plans() 从 cfg 推导出来的「本帧该做什么」。
-- ★ 执行层只读 P，不再看 cfg —— 这样「设置 → 行为」的换算只有一处，逻辑测试只需要
--   喂一个 cfg 就能断言整张计划表。
local P = { world = {}, spawn = {}, house = {}, pylon = {}, attr = { cat = {}, override = {} },
    -- v3 新增功能域（同样先建好空表：钩子在 setup 第 4 阶段就装上了，计划要到第 5 阶段才出来）
    tree = {}, angler = {}, rare = { list = {} }, starfall = {},
    death = {}, station = {}, gen = {}, shimmer = {},
    -- ★ v5 新增功能域的计划子表（同样先建好空表，理由同上）
    events = {}, spawnq = {}, liquid = {}, misc = {}, shop = {}, fish = {},
    -- ★ v6 新增：地图生成专项（世界大小/邪恶类型、生成后追加特征、生成后清除方块）
    wgen = {} }
-- （子表先建好：钩子在 setup 的第 4 阶段就装上了，而计划要到第 5 阶段才算出来，
--   中间这段时间任何回调都不该因为 P.world 是 nil 而报错）

-- ---------------------------------------------------------------- 生命周期
local in_setup = true          -- 正在 setup() 里（此阶段允许打日志/落盘诊断，之后只由 cfg.write_log 决定）
local tick_i = 0               -- 每帧自增的节拍计数（分桶用；tick() 每帧 +1，限流前就加）
local ready = false            -- setup 完成（至少装上一个钩子）
local menu_flag = true         -- 保守初值：先当作在主菜单；由 tick() 每 30 帧核对
local world_entered = false    -- 是否进过世界（用来识别「回到主菜单」）
local hooks = {}               -- 已安装的钩子句柄（卸载时逐个 remove）
local tick                     -- 前向声明：心跳定义在 90_lifecycle，40_world 的兜底路径要用
-- ★ v5：聊天输出助手（定义在最后一个分片 95_chat.lua，但 44/46/85 等分片要提前引用它，
--   所以在这里前向声明 —— Lua 的词法作用域要求「引用的 local 必须在函数定义处已声明」）
local chat_print
-- ★ v6：地图生成专项的跨分片控制表（86_worldgen.lua 填 status/cancel，95_chat.lua 的
--   /forge wgen 读它）。定义在最早的分片里，后面任何分片都能安全引用。
local WGCTL = {}
-- ★ v9：一键操作的跨分片控制表（87_oneshot.lua 填内容，96_gui.lua 的「一键」页与 95_chat 读它）。
--   为什么必须放这里：96_gui 是最后一个分片，它只看得到「主 chunk 顶层声明的 local」；
--   而 87_oneshot 分片自己包在 do…end 里，它的 local 对外不可见 → 对外只经这张共享表。
local ONESHOT = {}
local DOMAINS = {}             -- 功能域注册表：每个分片自己登记 字段/方法/安装钩子
local UNDO = {}                -- 撤销表：字段键 → { base = 原版值, last = 本模组上次写入值 }
-- 跨帧记忆（★ 与 fl 的区别：fl 每帧被 tick() 清零，只能表示「本次调用内部」的窗口；
-- 凡是需要「上一帧是什么样」的边沿检测、或「这件事做过没有」的一次性标志，都放这里）
local mem = {}
-- ★ v5.0.0（§9 整改）：import_string 通道的「上次已经处理过的串」。
--   放进 mem（跨帧、卸载时随 mem 一起清）；空串 = 还没处理过任何串。
--   语义：read_config 读到的 import_string 只要与本值不同且非空，就校验 + 应用一次。
mem.last_import = ""
local stats = {                -- 诊断统计
    frames = 0, ticks = 0, writes = 0, blocks = 0, dups = 0, reloads = 0,
    fields_ok = 0, fields_miss = 0, npc_seen = 0,
    netmode_blocked = 0,       -- 因为「仅房主生效」而被挡下的写入次数
    -- ★ v5 新增：方法解析与钩子安装的成败计数（按「功能域"阶段"取差值」得到每域的句柄/钩子状态）
    methods_ok = 0, methods_miss = 0,
    hooks_try = 0, hooks_ok = 0,
    chat_cmds = 0,             -- 收到并处理的聊天命令条数
    -- ★ v5.0.0（§9 整改）新增：
    type_lookups = 0,          -- 一共问过多少次 patch.get_type（诊断「chat_cmd 关时是否真的零 Chat 触达」）
    chat_types = 0,            -- 其中落在 Terraria.Chat.* 命名空间的类型解析次数（关 = 必须为 0 的硬指标）
    chat_disabled = 0,         -- 因为 chat_cmd=false 而整体关闭的聊天域标记（0/1）
    import_ok = 0,             -- import_string 通道成功应用次数
    import_fail = 0,           -- import_string 通道失败次数（格式 / 校验和 / 写文件）
}

-- ---------------------------------------------------------------- 窗口标志
-- 「窗口标志」只在产生它的那次调用内部有效：tick() 每帧强制清零，绝不跨帧残留。
-- 残留的后果很具体：in_world_update 残留会让旅行模式的「停止蔓延」串味（把时间/雨/风
-- 一起冻住），pylon_request 残留会一直免危险，natural_spawn 残留会让非自然生成也被拦。
local fl = {
    world_update = false,      -- 正在 WorldGen.UpdateWorld 内部
    pylon_request = false,     -- 正在晶塔传送请求内部
    score_room = 0,            -- WorldGen.ScoreRoom 嵌套深度（>0 = 正在判定住房）
    spawn_dead = false,        -- 本次 Player.Spawn 是「死亡复活」（进来时 Player.dead 为真）
    artisan_saved = nil,       -- AdjTiles 前保存的 ateArtisanBread 原值
    artisan_touched = false,   -- 本次 AdjTiles 里我们改过 ateArtisanBread
    boss_summon = false,       -- 正在 Player.ItemCheck_UseBossSpawners 内部（= 这次生成来自召唤 Boss 的消耗品）
    sp_invoke = false,         -- 正在我们自己发起的「额外逐格蔓延」（递归保护，v5）
    li_invoke = false,         -- ★ v7：正在我们自己发起的「额外补雷」（递归保护）
    li_force = false,          -- ★ v10.2：一键页「手动劈雷 / 闪光」窗口（上限与间距都不拦）
    importing = false,         -- ★ v5.0.0：正在应用设置串（期间的设置重读不许再触发一次导入）
}

-- 刷怪窗口状态
local spawn_win = {
    natural = false,           -- 正在 NPC.SpawnNPC 内部（= 这次生成是自然刷怪）
    budget = 0,                -- 本次自然刷怪还剩几次「额外生成」配额
    in_dup = false,            -- 正在执行本模组发起的额外生成（防递归）
}

-- ---------------------------------------------------------------- 缓存
local type_cat = {}            -- [生物 type] = 类别（由 SetDefaults 现场学出来）
local type_base = {}           -- [生物 type] = { 字段 = { base = 原版值, last = 上次写入值 } }

-- ---------------------------------------------------------------- 句柄
local T = {}                   -- setup 阶段解析出来的类型句柄
local M = {}                   -- setup 阶段解析出来的方法句柄
local ARG = { new_npc = 10, spawn_on_player = 6 }   -- 实参个数（setup 阶段用 method_param_count 核实）



-- ============================================================================
-- 10 · 核心工具：日志 / 落盘诊断 / 字段句柄注册表 / 钩子 / 撤销表 / 功能域
-- ============================================================================

local warned = {}

-- ★ v5.0.0（《12-下一版通用约定》§9 整改）：**所有类型解析都必须经这个包装**。
--   它只做两件簿记（零游戏调用、零反射）：
--     · stats.type_lookups —— 一共问过多少次 get_type；
--     · stats.chat_types   —— 其中落在 `Terraria.Chat*` 命名空间的次数。
--   第二条是本代的验收硬指标：`chat_cmd = false`（默认）时**一次都不许是 Chat 类型**，
--   因为「装聊天钩子」是安全的、而「触达聊天类型」正是那次实机 SIGABRT 的相邻路径
--   （见开发文档 05-写法与陷阱.md §5.2）。测试里有一条断言直接读这两个计数。
local function get_type(ns, name)
    stats.type_lookups = stats.type_lookups + 1
    local full = tostring(ns or "")
    if name ~= nil then full = full .. "." .. tostring(name) end
    if full:find("Terraria.Chat", 1, true) == 1 then
        stats.chat_types = stats.chat_types + 1
    end
    return patch.get_type(ns, name)
end

-- ★ v4：日志总开关。默认关闭时除了 setup() 阶段的一次性诊断（in_setup）之外，
--   一行日志都不写 —— 日志文件越长越容易把游戏拖崩，玩家可在设置里打开。
local function log_allowed()
    return in_setup or cfg.write_log == true
end

local function warn_once(tag, msg)
    if warned[tag] then return end
    warned[tag] = true
    if not log_allowed() then return end
    mod.warn(msg)
end

local function info_once(tag, msg)
    if warned[tag] then return end
    warned[tag] = true
    if not log_allowed() then return end
    mod.info(msg)
end

local function fmt_bool(v) return v and "开" or "关" end

-- ---------------------------------------------------------------- 落盘诊断
-- 日志异步刷盘，进程猝死会丢最后几行；所以自己也留一份（崩溃后唯一可靠的「死前遗言」）。
-- 只在内容变化时刷盘，避免每帧写文件。
local diag_lines = {}
local diag_dirty = false
local DIAG_MAX = 120

local function diag(msg)
    if not log_allowed() then return end
    if #diag_lines >= DIAG_MAX then table.remove(diag_lines, 1) end
    diag_lines[#diag_lines + 1] = tostring(msg)
    diag_dirty = true
end

local function diag_flush()
    if not log_allowed() then
        diag_lines, diag_dirty = {}, false
        return
    end
    if not diag_dirty then return end
    diag_dirty = false
    pcall(mod.write_file, "worldforge.log", table.concat(diag_lines, "\n") .. "\n")
end

-- 详细日志：要「写入日志文件」+「详细日志」两个开关都打开才输出
local function verbose(msg)
    if cfg.write_log and cfg.verbose_log then mod.info(msg) end
end

-- ---------------------------------------------------------------- 句柄查找
local function find_method(type_handle, name, argc)
    if not type_handle then
        stats.methods_miss = stats.methods_miss + 1
        return nil
    end
    if argc then
        local ok, m = pcall(patch.get_method, type_handle, name, argc)
        if ok and m then
            stats.methods_ok = stats.methods_ok + 1
            return m
        end
    end
    local ok, m = pcall(patch.get_method, type_handle, name)
    if ok and m then
        stats.methods_ok = stats.methods_ok + 1
        return m
    end
    stats.methods_miss = stats.methods_miss + 1
    return nil
end

-- 按「参数名表」精确选重载（同名 + 同形参个数时唯一能区分的办法，见 03 §4.2）。
-- 失败返回 nil（调用方必须判空）。
local function find_method_by_names(type_handle, name, names)
    if not type_handle or not patch.get_method_by_names then
        stats.methods_miss = stats.methods_miss + 1
        return nil
    end
    local ok, m = pcall(patch.get_method_by_names, type_handle, name, names)
    if ok and m then
        stats.methods_ok = stats.methods_ok + 1
        return m
    end
    stats.methods_miss = stats.methods_miss + 1
    return nil
end

-- 沿父类链找字段（1.4.5 的字段可能被挪到基类上）
local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local ok, f = pcall(patch.get_field, cur, name)
        if ok and f then return f end
        local ok2, p = pcall(patch.get_parent, cur)
        cur = ok2 and p or nil
        guard = guard + 1
    end
    return nil
end

-- 对象句柄有效性（只用于实例句柄；字段/方法句柄不要过这个）
local function valid_obj(h)
    if not h then return false end
    if patch.is_valid then
        local ok, v = pcall(patch.is_valid, h)
        if ok then return v and true or false end
    end
    return true
end

-- ---------------------------------------------------------------- 字段注册表
-- 句柄表：F[key] = 字段句柄 / FT[key] = 类型字符串 / ST[key] = 是否静态
local F, ST, FT = {}, {}, {}

-- 已知的静态字段（field_is_static 问不出来时的兜底；都对着 1.4.4 反编译源码核对过）
local KNOWN_STATIC = {
    dayRate = true, dayTime = true, time = true, moonPhase = true,
    raining = true, rainTime = true, maxRaining = true, cloudAlpha = true,
    windSpeedCurrent = true, windSpeedTarget = true, numClouds = true,
    bloodMoon = true, eclipse = true, slimeRain = true, slimeRainTime = true,
    pumpkinMoon = true, snowMoon = true, hardMode = true, netMode = true,
    forceHalloweenForToday = true, forceXMasForToday = true,
    gameMenu = true, npc = true, myPlayer = true,
    defaultSpawnRate = true, defaultMaxSpawns = true,
    AllowedToSpreadInfections = true, numRoomTiles = true, roomX = true, roomY = true,
    Happening = true, TimeLeft = true, IntendedSeverity = true, Severity = true,
    ManualLanterns = true, ManualParty = true,
    -- v3 新增（逐个对着 1.4.4 反编译源码核对过是 public static、不是 const）
    spawnMeteor = true,
    -- v3.1 新增（同样对着反编译源码核对过是 public static、不是 const）
    lightning = true,
    -- v4 新增：这三条是 1.4.5.8 手机版里**静态字段**，但不在 1.4.4 的旧表里；
    -- 不登记的话，遇到缺 field_is_const 的老加载器会被当成「实例字段」注册（读法可能不对）。
    thunderDelay = true, starfallBoost = true, PylonSystem = true,
    -- v5 新增（逐个对着 1.4.5.8 手机版符号表核过是 public/private static、不是 const）：
    lightningDecay = true, lightningSpeed = true,
    invasionSize = true, invasionSizeStart = true, invasionProgress = true,
    invasionProgressMax = true, invasionType = true,
    maxTilesX = true, maxTilesY = true, ClampScreenPositionToWorld = true,
    -- ★ v6 地图生成专项：这些都是 public/private static、**非 const**（对着 1.4.5.8 手机版
    --   字段表逐条核过）；登记进白名单是为了让「没有 field_is_const 的老加载器」也敢注册。
    wg_generating = true, wg_crimson = true, wg_param_evil = true,
    td_lookup = true, td_type = true, td_sheader = true,
    -- ★ v10 新增（对着 1.4.5.8 手机版字段表核过：全是 public static、非 const）：
    --   地表 / 岩层高度（Main，double，0x470 / 0x478）与宝石洞前置校验的四个计数
    --   （WorldGen.maxTileCount / lavaCount / iceCount / rockCount）。
    world_surface = true, rock_layer = true,
    wg_max_tile_count = true, wg_lava_count = true,
    wg_ice_count = true, wg_rock_count = true,
    downedMechBoss1 = true, downedMechBoss2 = true, downedMechBoss3 = true,
    -- ★ v9：数落雷弹幕要扫的 Main.projectile（Projectile[]，public static 非 const；
    --   对着 1.4.5.8 手机版字段表核过：0x5B8）。进白名单是为了让「没有 field_is_const 的
    --   老加载器」也敢把它按静态字段注册（否则会按实例字段注册 → 永远读到 nil）。
    main_projectile = true,
    -- ★ v10.2：世界更新速率（蔓延速度）。Main.desiredWorldTilesUpdateRate 是 public static int，
    --   非 const（mod_symbol 已核）；WorldGen.GetWorldUpdateRate() = min(它, 24)。
    desired_world_rate = true,
    -- ★ v9：清掉落物要扫的 Main.item（WorldItem[]，public static 非 const，0x570）
    item = true,
}

-- 注册一个字段句柄。失败只打一条日志并返回 nil —— 调用方必须判空后早退（红线 4）。
local function register(key, owner, name, ty)
    local field = find_field(owner, name)
    if not field then
        stats.fields_miss = stats.fields_miss + 1
        warn_once("f_" .. key, "找不到字段 " .. name .. "，相关功能自动降级")
        return nil
    end
    -- 判断静态/实例（先判它，因为下面的 const 规则要用到）
    local st = nil
    if patch.field_is_static then
        local ok, v = pcall(patch.field_is_static, field)
        if ok and type(v) == "boolean" then st = v end
    end
    if st == nil then st = KNOWN_STATIC[key] and true or false end

    -- 红线 2：const 字段读不得（手机版把 ItemID.Count / NPCID.Count 编成 const 字面量，
    -- 内核拿不到真实指针，抛 "Cannot get pointer to const field" → SIGABRT，pcall 拦不住）。
    -- 判定规则（C# 语义：const 一定是 static，所以实例字段天然不可能踩这条）：
    --   · field_is_const 能问 → 只有确证为 false 才注册；
    --   · 问不出来 / 老加载器没有这个 API → 只有 KNOWN_STATIC 白名单里的静态字段才注册
    --     （它们是逐个对着 1.4.4 反编译源码核对过的 public static 字段）。
    if st then
        local refuse = false
        if patch.field_is_const then
            local okc, c = pcall(patch.field_is_const, field)
            if okc then
                refuse = (c == true)
            else
                refuse = not KNOWN_STATIC[key]
            end
        else
            refuse = not KNOWN_STATIC[key]
        end
        if refuse then
            stats.fields_miss = stats.fields_miss + 1
            warn_once("c_" .. key, "字段 " .. name
                .. " 疑似 const（手机版常见），按红线不读不写，相关功能降级")
            return nil
        end
    end

    F[key], FT[key] = field, ty
    ST[key] = st
    stats.fields_ok = stats.fields_ok + 1
    return field
end

local function fget(key, inst)
    local f = F[key]
    if not f then return nil end
    -- 注意：不能写 `ST[key] and nil or inst` —— Lua 里 nil 是假值，那样永远得到 inst
    local obj = inst
    if ST[key] then obj = nil end
    local ok, v = pcall(patch.get_field_value, f, obj, FT[key])
    if not ok then
        warn_once("g_" .. key, "读取 " .. key .. " 失败：" .. tostring(v))
        return nil
    end
    return v
end

local function fset(key, inst, v)
    local f = F[key]
    if not f then return false end
    local obj = inst
    if ST[key] then obj = nil end
    local ok, err = pcall(patch.set_field_value, f, obj, v, FT[key])
    if not ok then
        warn_once("s_" .. key, "写入 " .. key .. " 失败：" .. tostring(err))
        return false
    end
    stats.writes = stats.writes + 1
    return true
end

-- 「值与目标不同才写」：默认路径上省掉绝大多数冗余写入
local function fset_if(key, inst, v)
    local cur = fget(key, inst)
    if type(cur) == "number" and type(v) == "number" then
        if cur == v then return false end
    elseif cur == v then
        return false
    end
    return fset(key, inst, v)
end

-- Vector2 字段（position / velocity / lastDeathPostion …）：
-- ★ 不能走 get_field_value —— 类型字符串表里没有 vec2，必须用专门的 get/set_field_vec2。
local function fget_vec2(key, inst)
    local f = F[key]
    if not f then return nil end
    local obj = inst
    if ST[key] then obj = nil end
    local ok, x, y = pcall(patch.get_field_vec2, f, obj)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end

local function fset_vec2(key, inst, x, y)
    local f = F[key]
    if not f then return false end
    local obj = inst
    if ST[key] then obj = nil end
    local ok = pcall(patch.set_field_vec2, f, obj, x, y)
    if not ok then
        warn_once("v_" .. key, "写入 " .. key .. "（Vector2）失败")
        return false
    end
    stats.writes = stats.writes + 1
    return true
end

-- 静态对象字段（数组）：句柄可缓存，对象每帧重取
local function get_object(key)
    local f = F[key]
    if not f then return nil end
    local ok, v = pcall(patch.get_field_value, f, nil, "object")
    if ok and v and type(v) ~= "number" then return v end
    return nil
end

-- ---------------------------------------------------------------- 撤销表
-- 只登记「游戏不会每帧自己重算」的全局值（刷怪速度 / 刷怪上限 / 困难模式）。
-- 每条记两个值：base = 我们接手前的原版值，last = 本模组上次写进去的值。
-- 三态判定：读到的当前值 == base → 我们还没写或已被还原；
--           读到的当前值 == last → 是我们写的，可以继续改 / 可以还原；
--           其它               → 别人改过，一律以它为新基准，绝不覆盖。
local function base_of(key, cur)
    local r = UNDO[key]
    if not r then
        r = { base = cur, last = nil }
        UNDO[key] = r
    elseif r.last ~= nil and cur ~= r.last and cur ~= r.base then
        r.base = cur
    elseif r.last == nil and cur ~= r.base then
        r.base = cur
    end
    return r
end

local function commit(key, rec, v)
    if fset(key, nil, v) then
        rec.last = v
        return true
    end
    return false
end

-- 还原一批键（卸载 / 关总开关时用）；只有「当前值还是我们写的那个」才还原
local function undo_restore(keys)
    local n = 0
    for i = 1, #keys do
        local key = keys[i]
        local rec = UNDO[key]
        if rec and rec.last ~= nil then
            local cur = fget(key)
            if cur == rec.last then
                if fset(key, nil, rec.base) then n = n + 1 end
            end
        end
        UNDO[key] = nil
    end
    return n
end

-- ---------------------------------------------------------------- 钩子与功能域
-- 每个分片通过 domain{...} 登记自己：字段注册 / 方法解析 / 钩子安装。
-- setup() 只需要按阶段遍历这张表，新增功能不必再回头改 setup。
-- ★ v5：功能域注册表按《12-下一版通用约定》§4 升级。
--   难点：约定要求 d.fields / d.methods / d.hooks 存放 "ok"/"partial"/"fail" 三个标签，
--   而各分片又习惯用同名的键登记「安装期阶段函数」。为了两者兼得，这里把阶段函数整体
--   搬进 d.phase（fields/methods/install/world/frame/reload/reset/invasion），
--   把 d.fields / d.methods / d.hooks 空出来给标签用 —— 各分片一行都不用改。
--   · calls/hits/errs/last_err：运行期计数（hits 由各域在自己的热路径里 d.hits = d.hits + 1）
--   · c = { ... }：命名计数器（诊断用），写它只花一次 table 写
--   · t/n：累计耗时（秒）与采样次数，供 diag_slow_ms 判 SLOW
-- ★ v5.0.0（§9 整改）：聊天域专用门控。`chat_cmd` 默认 false —— 关闭时这个域一步都不许走
--   （不解析 SayChatCommand、不装聊天钩子、不触达任何 Terraria.Chat 类型）。
local function chat_domain_enabled()
    return cfg.chat_cmd == true
end

local function domain(def)
    -- ★ 把**所有**函数值键都收进 def.phase（不写死键名！）：
    --   除了 fields/methods/install/world/frame/reload/reset/invasion，
    --   还有 npc_new_prefix / npc_new_postfix 这类由别的主人派发的阶段函数
    --   （v5 早期版本写死了键名，结果 npc_new_* 整条阶段链被吞掉 —— 分类刷怪与生物属性全废）。
    def.phase = {}
    for k, v in pairs(def) do
        if type(v) == "function" then
            def.phase[k] = v
            def[k] = nil
        end
    end
    def.calls, def.hits, def.errs, def.last_err = 0, 0, 0, nil
    def.c = {}
    def.t, def.n = 0, 0
    -- 安装期按「阶段前后差值」算出来的句柄/钩子计数（evaluation 时折算成 ok/partial/fail 标签）
    def.n_fields_ok, def.n_fields_miss = 0, 0
    def.n_methods_ok, def.n_methods_miss = 0, 0
    def.n_hooks_ok, def.n_hooks_try = 0, 0
    DOMAINS[#DOMAINS + 1] = def
    return def
end

-- 命名计数器（只在**非默认路径**上写，默认配置下一次都不发）
local function dcount(d, key, n)
    if not d then return end
    local c = d.c
    c[key] = (c[key] or 0) + (n or 1)
end

-- 派发一个「阶段」给所有功能域。★ v3 起新增功能的唯一正道：
-- 同一个方法上装第二个钩子会把先装的那个顶掉（内核只保留最后安装的一个；假内核已实测，
-- 真内核语义未知但没必要拿主钩子去赌）。所以 Main.UpdateTimeRate（40_world）、
-- NPC.SetDefaults（50_npc）、NPC.NewNPC（60_spawn）这三个热点方法**只允许一个主人**，
-- 后来者改为登记阶段函数，由主人在恰当的位置 call_domains 派发。
-- 返回值：第一个「认领」了这次调用的阶段函数的返回值（prefix 拦截靠它传递）。
local function call_domains(phase, ...)
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        local fn = d.phase and d.phase[phase]
        if fn then
            d.calls = d.calls + 1
            local t0 = os.clock()
            local ok, a, b = pcall(fn, ...)
            local dt = os.clock() - t0
            if dt > 0 then d.t = d.t + dt end
            d.n = d.n + 1
            if not ok then
                d.errs = d.errs + 1
                d.last_err = tostring(a)
                warn_once("d_" .. phase .. tostring(d.name),
                    "功能域「" .. tostring(d.name) .. "」阶段 " .. phase .. " 失败：" .. tostring(a))
            elseif a ~= nil then
                return a, b
            end
        end
    end
    return nil
end

local function safe_hook(method, spec, label)
    stats.hooks_try = stats.hooks_try + 1
    if not method then
        mod.warn("跳过钩子（方法句柄为空）：" .. label)
        return nil
    end
    local ok, h = pcall(patch.install_hook, method, spec)
    if not ok then
        mod.warn("安装钩子失败 " .. label .. "：" .. tostring(h))
        return nil
    end
    stats.hooks_ok = stats.hooks_ok + 1
    hooks[#hooks + 1] = h
    verbose("钩子已安装：" .. label)
    return h
end

-- 反射调用统一入口（★ 只用于**静态**方法）：句柄判空 + 实参个数核对 + pcall。
-- 返回 true / false, err。空句柄绝不下传（红线 4）；实参个数不符宁可放弃（红线 3.5）。
-- ⚠ 实例方法不能用它 —— patch.invoke 的实例方法还要占一个 instance 槽位，
--   所以实例方法一律走下面的 invoke_instance（否则就是「少传实参」→ 越界 → 崩）。
local function invoke_checked(method, argc, ...)
    if not method then return false, "方法句柄为空" end
    if patch.method_param_count then
        local okc, n = pcall(patch.method_param_count, method)
        if okc and type(n) == "number" and n ~= argc then
            return false, "实参个数不符（句柄 " .. n .. " vs 传入 " .. argc .. "）"
        end
    end
    local args = table.pack(...)
    if args.n ~= argc then return false, "实参个数不符（传入 " .. args.n .. " vs 声明 " .. argc .. "）" end
    local ok, err = pcall(patch.invoke, method, table.unpack(args, 1, args.n))
    if not ok then return false, tostring(err) end
    return true
end

-- ---------------------------------------------------------------- v4 新增工具
-- 分桶：「非关键项刷新间隔」把同一批工作平摊到 N 帧里，每帧只跑一组。
--   n        = 这一组的固定编号（同一功能永远用同一个编号）
--   interval = P.tick（1 = 逐帧，等价旧行为）
-- tick_i 由 tick() 每帧 +1，所以每 interval 帧各组各跑一次。
local function bucket_ok(n, interval)
    if not interval or interval <= 1 then return true end
    if not n or n < 0 then return true end
    return (tick_i % interval) == (n % interval)
end

-- Main.netMode：0 单机 / 1 客机 / 2 服务器。手机版是**普通静态 int 字段**（已对符号表核实），
-- 但为了不依赖这一点，读不到就当成 0（= 不受限），绝不让「取不到句柄」把功能全废。
local net_cache = { mode = 0, at = -10 }
local function main_net_mode()
    if not F.netMode then return 0 end
    local now = stats.frames
    -- ★ 首帧就必须读一次（at < 0 为初值）：否则进世界后的头几十帧认不出「自己是客机」，
    --    host_only 会有约 20 帧的漏写窗口（测试实测到 raining 被写进去）。
    if net_cache.at < 0 or (now - net_cache.at) >= 30 then
        net_cache.at = now
        local v = fget("netMode")
        net_cache.mode = (type(v) == "number") and v or 0
    end
    return net_cache.mode
end

-- ★ v4 的总闸：cfg.host_only（默认开）时，作为客机（netMode == 1）**只读不写**。
--   这样几个好友各自的设置不会互相打架，也不会把服务器上的数据改乱。
local function may_write()
    if cfg.host_only ~= true then return true end
    if main_net_mode() == 1 then
        stats.netmode_blocked = stats.netmode_blocked + 1
        return false
    end
    return true
end

-- 本地玩家下标。★ 手机版 Main.myPlayer 是**属性**（符号表「修饰」列带 [属性]），
-- 取字段必然返回 nil（见 05 §4.6），所以这里有 get_myPlayer 方法兜底。
local function my_player_index()
    if F.myPlayer then
        local v = fget("myPlayer")
        if type(v) == "number" then return v end
    end
    if M.get_my_player then
        local ok, v = pcall(patch.invoke, M.get_my_player)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

-- 实例方法的反射调用：实参个数 = 形参个数（不含 this），instance 单独占一个槽位。
-- 现有 invoke_checked 只对静态方法正确 —— 这是本工作区一个真实的崩溃点（渔夫额外奖励）。
local function invoke_instance(method, inst, ...)
    if not method then return false, "方法句柄为空" end
    if not inst then return false, "实例句柄为空" end
    local n
    if patch.method_param_count then
        local okc, cnt = pcall(patch.method_param_count, method)
        if okc and type(cnt) == "number" then n = cnt end
    end
    local args = table.pack(...)
    if n and args.n ~= n then
        return false, "实参个数不符（句柄 " .. n .. " vs 传入 " .. args.n .. "）"
    end
    local ok, err = pcall(patch.invoke, method, inst, table.unpack(args, 1, args.n))
    if not ok then return false, tostring(err) end
    return true
end

-- Main.npc[i] → NPC 实例句柄。★ 借用手柄：只在**当前回调内**有效，绝不跨帧保存（03 §1.1）。
local function npc_by_index(idx)
    if type(idx) ~= "number" or idx < 0 then return nil end
    local arr = get_object("npc")
    if not arr then return nil end
    local ok, obj = pcall(patch.array_at, arr, idx)
    if ok and obj and type(obj) ~= "number" then return obj end
    return nil
end



-- ============================================================================
-- 20 · 设置读取：config.json → cfg
-- ----------------------------------------------------------------------------
-- TEFManager 把设置写成 {"schemaVersion":1,"values":{...}}（ModSettingsStore.kt）。
-- 不依赖 JSON 库（LuaLoader 不保证提供），用模式匹配直接抠值 —— 与 26 个参考 Mod 一致。
-- 四种类型各一个解析器，**每种都在 Lua 侧再夹一次范围**（界面上的 min/max 只是 UI 提示，
-- 手改 config.json 完全能越界）。
-- ============================================================================

local last_raw = nil
local cfg_stat = { keys = 0, reloads = 0 }

local function esc(key)
    return (key:gsub("([^%w])", "%%%1"))
end

-- ★ v3.1：**倍率/数量类设置不再做上夹取**。界面上的 max 只是滑块行程，手改 config.json
--   想填多大就多大（玩家要 1 万倍刷怪/掉落是玩家自己的选择，模组不替他设上限）。
--   例外是下面这张表里的「枚举 / 数组下标」类设置：月相只有 0~8、云量有数组长度上限、
--   时刻只有 1~24，越界会直接当成游戏里的下标用，所以仍然按滑块范围夹紧。
--   下限一律保留（负数会让「间隔 / 上限」这类语义反过来）。
-- v4：新增的「节拍 / 间隔 / 上限」类设置也必须按滑块范围夹紧 —— 它们会被当成循环长度
-- 或比较阈值用，越界（手改 config.json 填一亿帧）会让分桶逻辑失去意义。
local HARD_LIMIT_KEYS = {
    -- 枚举 / 下标 / 节拍 / 数量类：手改 config.json 越界会直接当成数组下标、循环长度或
    -- 比较阈值用，所以仍然按滑块范围夹紧（★ 倍率类一律不进来，倍率想填多大由玩家决定）
    moon_lock = true, cloud_amount = true, lock_hour = true,
    tick_interval = true, config_reload_sec = true, pylon_total_limit = true,
    plantera_bulb_interval = true, house_max_npcs = true,
    -- v5 新增（都是「秒/帧/点/格/个/天/编号」类，不是倍率）
    diag_slow_ms = true, enemy_hard_cap = true, liquid_rate = true, liquid_height = true,
    plantera_daily_count = true, plantera_bulb_runs = true,
    quest_fish_stack = true, shimmer_any_item = true,
    eclipse_repeat_days = true, bloodmoon_repeat_days = true,
    pumpkinmoon_repeat_days = true, snowmoon_repeat_days = true,
    -- v8 新增（帧 / 格 / 个 类，同样必须按滑块范围夹紧）
    wgen_struct_gap = true, wgen_hits_frame = true, wgen_total_cap = true, wgen_budget = true,
    -- v9 新增（「道」类计数；倍率类的 lightning_windup_mult 不进这张表，由 30_plan 自己夹）
    lightning_max_bolts = true,
}

local function parse_int(raw, key, fallback, lo, hi)
    local v = tonumber(raw:match('"' .. esc(key) .. '"%s*:%s*(-?%d+)'))
    if not v then return fallback end
    v = math.floor(v)
    if lo and v < lo then v = lo end
    if hi and HARD_LIMIT_KEYS[key] and v > hi then v = hi end
    if v > 1000000000 then v = 1000000000 end   -- 只是防溢出（int32 量级），不是功能上限
    return v
end

local function parse_bool(raw, key, fallback)
    local t = raw:match('"' .. esc(key) .. '"%s*:%s*(%a+)')
    if t == "true" then return true end
    if t == "false" then return false end
    return fallback
end

-- CHOICE：只接受 CHOICES 里列出的取值。旧版 config.json 里存的是数字（旧版这些项是
-- INTEGER），匹配不到字符串 → 自动回到默认档，不会把界面卡在一个不存在的选项上。
local function parse_choice(raw, key, fallback, allowed)
    local v = raw:match('"' .. esc(key) .. '"%s*:%s*"([^"]*)"')
    if type(v) ~= "string" then return fallback end
    for i = 1, #allowed do
        if allowed[i] == v then return v end
    end
    return fallback
end

local function parse_string(raw, key, fallback, maxlen)
    local v = raw:match('"' .. esc(key) .. '"%s*:%s*"([^"]*)"')
    if type(v) ~= "string" then return fallback end
    v = v:gsub('\\"', '"'):gsub("\\\\", "\\")
    if maxlen and #v > maxlen then v = v:sub(1, maxlen) end
    return v
end

-- 返回 true 表示「文件内容变了、cfg 已更新」
local function read_config()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then return false end
    if raw == last_raw then return false end
    last_raw = raw

    local n = 0
    for key, lim in pairs(LIMITS) do
        cfg[key] = parse_int(raw, key, DEFAULTS[key], lim[1], lim[2])
        n = n + 1
    end
    for key, allowed in pairs(CHOICES) do
        cfg[key] = parse_choice(raw, key, DEFAULTS[key], allowed)
        n = n + 1
    end
    for key, def in pairs(DEFAULTS) do
        if type(def) == "boolean" then
            cfg[key] = parse_bool(raw, key, def)
            n = n + 1
        elseif type(def) == "string" and CHOICES[key] == nil then
            cfg[key] = parse_string(raw, key, def, 512)
            n = n + 1
        end
    end
    cfg_stat.keys = n
    cfg_stat.reloads = cfg_stat.reloads + 1
    return true
end



-- ============================================================================
-- 30 · 计划：cfg → P
-- ----------------------------------------------------------------------------
-- 这一节是**纯逻辑**：不碰任何句柄、不发任何反射调用，因此可以在假内核里单独测。
-- 执行层（40~80）只读 P，不再自己解释 cfg —— v1.0.0 的刷怪参数在两处各算了一遍
-- （build_plans 算 P.spawn_rate，apply_spawn_params 又照着 cfg 重算一次），
-- P.spawn_rate / P.spawn_cap 实际是死代码。现在换算只有这一处。
-- ============================================================================

-- 生物类别（与设置项一一对应；type_cat 里存的就是这几个值）
local CAT_BOSS, CAT_SLIME, CAT_FLY, CAT_GROUND, CAT_PASSIVE, CAT_OTHER = 0, 1, 2, 3, 4, 5
local CAT_LABEL = {
    [CAT_BOSS] = "Boss", [CAT_SLIME] = "史莱姆", [CAT_FLY] = "飞行",
    [CAT_GROUND] = "地面", [CAT_PASSIVE] = "小动物", [CAT_OTHER] = "其它",
}

local function pct(k) return (cfg[k] or 100) / 100 end

-- ★ v7：「A=B」形式的方块替换表（30=0 表示把 30 号方块删掉）。非法片段直接忽略。
local function parse_pairs(s)
    local t = {}
    if type(s) ~= "string" or s == "" then return t end
    for a, b in s:gmatch("(%d+)%s*[=:]%s*(%d+)") do
        local k, v = tonumber(a), tonumber(b)
        if k and v and k >= 1 and k <= 1000 and v >= 0 and v <= 1000 then t[k] = v end
    end
    return t
end

-- v6：地图生成专项用的小换算（同样是纯逻辑，可在假内核里单独断言）
local SIZE_CODE = { small = 0, medium = 1, large = 2 }
local EVIL_CODE = { random = -1, corruption = 0, crimson = 1 }
local function wg_size_of(en, v)
    if not en then return "none" end
    if v == "small" or v == "medium" or v == "large" then return v end
    return "none"
end
local function wg_evil_of(en, v)
    if not en then return "none" end
    if v == "random" or v == "corruption" or v == "crimson" then return v end
    return "none"
end
-- UI 值 1 = 0 个（TEFManager 会把 INTEGER 的 min<=0 顶成 1），再按上限夹取
local function ui_off(v, lo, hi)
    local n = math.floor(tonumber(v) or lo) - lo
    if n < 0 then n = 0 end
    if n > hi then n = hi end
    return n
end
local function clamp_num(v, lo, hi, dflt)
    local n = math.floor(tonumber(v) or dflt or lo)
    if n < lo then n = lo end
    if n > hi then n = hi end
    return n
end

-- ---- 时刻换算 --------------------------------------------------------------
-- 泰拉瑞亚的 Main.time 不是「几点」而是「本段已经过了多少 tick」（1 秒 = 60 tick，
-- 于是 1 小时 = 3600 tick）：白天从 4:30 起算、长 15 小时（0~54000），
-- 夜晚从 19:30 起算、长 9 小时（0~32400）。
local DAY_START_H, NIGHT_START_H = 4.5, 19.5

local function hour_to_clock(h)
    h = math.floor(h or 12)
    if h < 1 then h = 1 end
    if h > 24 then h = 24 end
    if h >= 5 and h <= 19 then
        return { day = true, ticks = (h - DAY_START_H) * 3600 }
    end
    local hh = h % 24
    return { day = false, ticks = ((hh - NIGHT_START_H) % 24) * 3600 }
end

-- ---- 生物分类覆盖表 --------------------------------------------------------
-- 形如 "4=0,50=1,113=3"；类别 0~5 见 CAT_LABEL。非法片段直接忽略（不报错、不中断解析）。
local function parse_overrides(s)
    local t = {}
    if type(s) ~= "string" or s == "" then return t end
    for a, b in s:gmatch("(%d+)%s*[=:]%s*(%d+)") do
        local id, cat = tonumber(a), tonumber(b)
        if id and cat and id >= 1 and id <= 3000 and cat >= 0 and cat <= 5 then
            t[id] = cat
        end
    end
    return t
end

-- ---- 纯编号表（稀有生物补表用）--------------------------------------------
-- 与分类覆盖表不同：这里只要编号，不要类别。非数字片段一律忽略。
local function parse_ids(s)
    local t = {}
    if type(s) ~= "string" or s == "" then return t end
    for a in s:gmatch("(%d+)") do
        local id = tonumber(a)
        if id and id >= 1 and id <= 3000 then t[id] = true end
    end
    return t
end

local function build_plans()
    local en = cfg.enabled and true or false

    -- ======================================================== 世界（时间/天气/事件）
    local w = {}
    w.time_speed = en and pct("time_speed") or 1.0
    w.freeze = en and cfg.time_freeze or false

    local lock
    if en and cfg.day_lock == "day" then lock = hour_to_clock(12)
    elseif en and cfg.day_lock == "night" then lock = hour_to_clock(24)
    elseif en and cfg.day_lock == "clock" then lock = hour_to_clock(cfg.lock_hour)
    end
    if lock then
        w.lock_day, w.lock_ticks = lock.day, lock.ticks
    else
        w.lock_day, w.lock_ticks = nil, nil
    end

    w.moon_lock = (en and math.floor(cfg.moon_lock or 1) > 1) and (math.floor(cfg.moon_lock) - 2) or -1

    w.rain = en and cfg.rain_mode or "none"                    -- none / on / off
    w.rain_val = (cfg.rain_intensity or 60) / 100
    w.wind = en and cfg.wind_mode or "none"                    -- none / lock / calm
    local dir = cfg.wind_dir or "east"
    if dir == "still" then
        w.wind_val = 0.0
    elseif dir == "west" then
        w.wind_val = -(cfg.wind_power or 40) / 100
    else
        w.wind_val = (cfg.wind_power or 40) / 100
    end
    w.sand = en and cfg.sandstorm_mode or "none"               -- none / on / off
    w.sand_val = (cfg.sandstorm_power or 60) / 100
    w.cloud_lock = en and cfg.cloud_lock or false
    w.cloud_amount = math.floor(cfg.cloud_amount or 101) - 1

    w.blood_moon = en and cfg.blood_moon or false
    w.block_blood_moon = en and cfg.block_blood_moon or false
    w.eclipse = en and cfg.eclipse or false
    w.block_eclipse = en and cfg.block_eclipse or false
    -- 「禁止」优先于「永久」：两个都开时以禁止为准（描述里写明了）
    w.slime_rain = en and (not cfg.block_slime_rain) and cfg.slime_rain or false
    w.block_slime_rain = en and cfg.block_slime_rain or false
    w.lantern_night = en and cfg.lantern_night or false
    w.party = en and cfg.party or false
    w.pumpkin_moon = en and cfg.pumpkin_moon or false
    w.snow_moon = en and cfg.snow_moon or false
    w.halloween = en and cfg.always_halloween or false
    w.christmas = en and cfg.always_christmas or false

    w.hardmode = en and cfg.hardmode or false
    w.block_invasion = en and cfg.block_invasion or false
    w.spread_block = en and cfg.spread_block or false
    w.spread_force = en and (not cfg.spread_block) and cfg.spread_force or false

    -- ★★ v10.2：生物群系蔓延速度 = 世界更新速率 ★★
    --   v5~v10 走的是「额外重跑逐格更新入口」，改了两轮都被玩家判为「没反应」：那条路
    --   每帧只多抽几十~几千格，而原版一次 UpdateWorld 本来就抽全图约 0.3% 的格子，
    --   增量被淹没在随机噪声里。现在改用原版自己就有的那个旋钮：
    --     WorldGen.GetWorldUpdateRate() = min(Main.desiredWorldTilesUpdateRate, 24)
    --   而 Main.UpdateTimeRate() 每帧都会把 desiredWorldTilesUpdateRate 设回时间倍率（默认 1）。
    --   本模组的钩子就装在 Main.UpdateTimeRate 的 postfix 上，在那里把它写成本值即可 ——
    --   UpdateWorld 每帧抽的随机格数按倍率线性上升（最多 24 倍），
    --   腐化 / 猩红 / 神圣的蔓延、草与藤蔓生长、植物生长一起变快。
    --   100% = 原版；100 ~ 2400% 映射到 1 ~ 24 倍（游戏自身硬夹 24）。
    --   ★ 低于 100% 时无法把速率降到 1 以下，改走逐格 prefix 的按概率跳过（见 40_world）。
    w.spread_mult = en and (math.floor(cfg.spread_speed_mult or 100)) or 100
    if w.spread_mult < 1 then w.spread_mult = 1 end
    if w.spread_mult > 2400 then w.spread_mult = 2400 end
    local srate = math.floor(w.spread_mult / 100 + 0.5)
    if srate < 1 then srate = 1 end
    if srate > 24 then srate = 24 end
    w.spread_rate = srate
    w.spread_rate_on = en and (w.spread_mult > 100) and srate > 1

    -- 刷怪参数：NPC.defaultSpawnRate 是「间隔」，所以要除；defaultMaxSpawns 是「上限」，要乘
    w.spawn_rate_mult = math.floor(cfg.spawn_rate_mult or 100)
    w.spawn_cap_mult = math.floor(cfg.spawn_cap_mult or 100)
    w.no_natural_spawn = en and cfg.no_natural_spawn or false
    w.spawn_check = en and (w.spawn_rate_mult ~= 100 or w.spawn_cap_mult ~= 100
        or w.no_natural_spawn) or false

    -- v4：用召唤物召 Boss 时一次几只（只作用于 Player.ItemCheck_UseBossSpawners 窗口）
    local bc = math.floor(cfg.boss_summon_count or 1)
    if bc < 1 then bc = 1 end
    if bc > 10 then bc = 10 end
    P.boss_count = en and bc or 1

    w.active = w.time_speed ~= 1.0 or w.freeze or w.lock_ticks ~= nil or w.moon_lock >= 0
        or w.rain ~= "none" or w.wind ~= "none" or w.sand ~= "none" or w.cloud_lock
        or w.blood_moon or w.block_blood_moon or w.eclipse or w.block_eclipse
        or w.slime_rain or w.block_slime_rain or w.lantern_night or w.party
        or w.pumpkin_moon or w.snow_moon or w.halloween or w.christmas
        or w.hardmode or w.spawn_check or w.spread_block or w.spread_force
        or w.spread_mult ~= 100

    -- ======================================================== 刷怪分类
    local s = {}
    s.cat = {
        [CAT_BOSS + 1] = (cfg.spawn_mult_boss or 100) / 100,
        [CAT_SLIME + 1] = (cfg.spawn_mult_slime or 100) / 100,
        [CAT_FLY + 1] = (cfg.spawn_mult_flying or 100) / 100,
        [CAT_GROUND + 1] = (cfg.spawn_mult_ground or 100) / 100,
        [CAT_PASSIVE + 1] = (cfg.spawn_mult_passive or 100) / 100,
        [CAT_OTHER + 1] = (cfg.spawn_mult_other or 100) / 100,
    }
    s.block_boss = en and cfg.block_boss_spawn or false
    s.block_passive = en and cfg.block_passive_spawn or false
    s.dup_limit = math.floor(cfg.spawn_dup_limit or 3)
    if s.dup_limit < 1 then s.dup_limit = 1 end      -- 0 与负数无意义，只保留下限
    if s.dup_limit > 100000 then s.dup_limit = 100000 end
    local any_cat = false
    for i = 1, 6 do
        if s.cat[i] ~= 1 then any_cat = true end
    end
    s.filter = en and (any_cat or s.block_boss or s.block_passive) or false

    -- ======================================================== 生物属性
    local function g6()
        return {
            life = pct("npc_life_mult"), damage = pct("npc_damage_mult"),
            defense = pct("npc_defense_mult"), kb = pct("npc_kb_mult"),
            value = pct("npc_value_mult"), scale = pct("npc_scale_mult"),
        }
    end
    local function cat6(l, d, f)
        return { life = pct(l), damage = pct(d), defense = pct(f), kb = 1, value = 1, scale = 1 }
    end
    local function mul(x, y)
        return {
            life = x.life * y.life, damage = x.damage * y.damage, defense = x.defense * y.defense,
            kb = x.kb * y.kb, value = x.value * y.value, scale = x.scale * y.scale,
        }
    end
    local g = g6()
    local boss = cat6("boss_life_mult", "boss_damage_mult", "boss_defense_mult")
    boss.kb = pct("boss_kb_mult")
    boss.value = pct("boss_value_mult")
    boss.scale = pct("boss_scale_mult")

    local a = {
        [CAT_BOSS] = mul(g, boss),
        [CAT_SLIME] = mul(g, cat6("cat_slime_life", "cat_slime_damage", "cat_slime_defense")),
        [CAT_FLY] = mul(g, cat6("cat_fly_life", "cat_fly_damage", "cat_fly_defense")),
        [CAT_GROUND] = mul(g, cat6("cat_ground_life", "cat_ground_damage", "cat_ground_defense")),
        [CAT_PASSIVE] = g6(),
        [CAT_OTHER] = mul(g, cat6("cat_other_life", "cat_other_damage", "cat_other_defense")),
    }
    local attr_on = false
    for i = 0, 5 do
        local x = a[i]
        if x.life ~= 1 or x.damage ~= 1 or x.defense ~= 1
            or x.kb ~= 1 or x.value ~= 1 or x.scale ~= 1 then
            attr_on = true
        end
    end

    -- ======================================================== 住房 / 晶塔
    local h = {}
    h.no_furniture = en and cfg.house_no_furniture or false
    h.ignore_evil = en and cfg.house_ignore_evil or false
    h.ignore_size = en and cfg.house_ignore_size or false
    h.max_npcs = math.floor(cfg.house_max_npcs or 1)
    if h.max_npcs < 1 then h.max_npcs = 1 end
    if h.max_npcs > 10000 then h.max_npcs = 10000 end
    h.active = h.no_furniture or h.ignore_evil or h.ignore_size or h.max_npcs > 1

    -- ★ v4 重构：原版晶塔判定的**唯一入口** HandleTeleportRequest / DoesPylonAcceptTeleportation /
    --   HowManyNPCsDoesPylonNeed 的第一个形参都是结构体 TeleportPylonInfo，本加载器的 hook 走
    --   libffi 闭包、只支持标量参数（05 §4.3），挂上会崩 —— 所以「所需 NPC 数」「无视生物群系」
    --   这两项在 v4 里被砍掉（旧 C++ 加载器能挂，所以旧模组有这两个功能）。
    --   能挂上且确实生效的是下面这四条：
    --     · IsPlayerNearAPylon(Player)                ← 无视距离
    --     · NPC.AnyDanger(bool,bool,bool)             ← 无视危险判定
    --     · HasPylonOfType(TeleportPylonType)         ← 允许同类型多座 / 全图总数上限
    local py = {}
    -- ★ v5：删掉「晶塔改造总开关」—— 它是 v4 里「开了子项没反应」的头号原因
    --   （子项全部依赖总开关，而总开关默认关）。现在每个子项各管各的。
    py.range = en and cfg.pylon_ignore_range or false
    py.danger = en and cfg.pylon_ignore_danger or false
    py.dupes = en and cfg.pylon_allow_dupes or false
    py.limit = en and (math.floor(cfg.pylon_total_limit or 1) - 1) or 0   -- 0 = 不限制
    if py.limit < 0 then py.limit = 0 end
    py.active = py.range or py.danger or py.dupes or py.limit > 0

    -- ======================================================== v3：树木 / 旅商 / 渔夫
    local tr = {}
    tr.block = en and cfg.tree_block_growth or false
    tr.active = tr.block

    local an = {}
    an.reward_mult = math.floor(cfg.angler_reward_mult or 1)
    if an.reward_mult < 1 then an.reward_mult = 1 end
    if an.reward_mult > 100 then an.reward_mult = 100 end
    an.instant = en and cfg.angler_instant or false
    an.active = en and (an.reward_mult > 1 or an.instant) or false

    -- v5：任务鱼堆叠上限（1 = 原版：uniqueStack，一格一条）
    local fi = {}
    fi.stack = math.floor(cfg.quest_fish_stack or 1)
    if fi.stack < 1 then fi.stack = 1 end
    if fi.stack > 9999 then fi.stack = 9999 end
    fi.active = en and fi.stack > 1

    -- v5：刷怪质量（精英与稀有怪倍率 / 同屏敌怪硬上限 / 怪物 AI 简化）
    local sq = {}
    sq.elite_mult = math.floor(cfg.elite_spawn_mult or 100) / 100
    if sq.elite_mult < 0.01 then sq.elite_mult = 0.01 end
    if sq.elite_mult > 100 then sq.elite_mult = 100 end
    -- 界面值 1 = 不限制；N ≥ 2 = 硬上限 N 只
    sq.cap = en and (math.floor(cfg.enemy_hard_cap or 1) - 1) or 0
    if sq.cap < 0 then sq.cap = 0 end
    if sq.cap > 500 then sq.cap = 500 end
    sq.ai = en and cfg.ai_simplify or false
    sq.ai_dist = 2400                       -- 两屏半（像素）：超过它才跳过这一帧的 AI
    sq.active = (sq.elite_mult ~= 1) or (sq.cap > 0) or sq.ai

    -- v5：液体世界（分帧灌注；0 = 水 / 1 = 岩浆 / 2 = 蜂蜜，原版枚举值）
    local lq = {}
    local mode = en and (cfg.liquid_mode or "off") or "off"
    lq.on = (mode ~= "off")
    -- ★ v7：冻结液体（跳过 Liquid.UpdateLiquid）
    lq.freeze = en and cfg.freeze_liquid or false
    lq.type = (mode == "lava") and 1 or ((mode == "honey") and 2 or 0)
    lq.height = math.floor(cfg.liquid_height or 50)
    if lq.height < 1 then lq.height = 1 end
    if lq.height > 100 then lq.height = 100 end
    lq.rate = math.floor(cfg.liquid_rate or 500)
    if lq.rate < 1 then lq.rate = 1 end
    if lq.rate > 5000 then lq.rate = 5000 end

    -- v5：世界边缘限制取消 / 重力药水屏幕不翻转
    local mi = {}
    mi.edge_free = en and cfg.world_edge_free or false
    mi.no_flip = en and cfg.gravity_no_flip or false
    mi.active = mi.edge_free or mi.no_flip

    -- v5：商店售价倍率（1.0 = 原版）
    local sp = {}
    sp.mult = math.floor(cfg.shop_price_mult or 100) / 100
    if sp.mult < 0.01 then sp.mult = 0.01 end
    if sp.mult > 100 then sp.mult = 100 end
    sp.active = en and sp.mult ~= 1

    -- v5：事件与月亮事件（入侵波数 / 进度快进 / 自动重复间隔）
    local ev = {}
    ev.wave_mult = math.floor(cfg.invasion_wave_mult or 100) / 100
    if ev.wave_mult < 0.01 then ev.wave_mult = 0.01 end
    if ev.wave_mult > 100 then ev.wave_mult = 100 end
    ev.wave = en and (ev.wave_mult ~= 1)
    ev.prog_mult = math.floor(cfg.event_progress_mult or 100) / 100
    if ev.prog_mult < 0.01 then ev.prog_mult = 0.01 end
    if ev.prog_mult > 100 then ev.prog_mult = 100 end
    ev.prog = en and (ev.prog_mult > 1)
    -- 界面值 1 = 不自动重复；N ≥ 2 = 每 (N−1) 天一次
    local function days(key)
        if not en then return 0 end
        local v = math.floor(cfg[key] or 1) - 1
        if v < 0 then v = 0 end
        if v > 30 then v = 30 end
        return v
    end
    ev.eclipse_days = days("eclipse_repeat_days")
    ev.blood_days = days("bloodmoon_repeat_days")
    ev.pumpkin_days = days("pumpkinmoon_repeat_days")
    ev.snow_days = days("snowmoon_repeat_days")
    ev.rep = (ev.eclipse_days > 0 or ev.blood_days > 0
        or ev.pumpkin_days > 0 or ev.snow_days > 0)
    ev.active = ev.wave or ev.prog or ev.rep

    -- ======================================================== v3：稀有生物
    local ra = {}
    ra.mult = pct("rare_spawn_mult")
    ra.threshold = math.floor(cfg.rare_value_threshold or 5000)
    ra.rarity = (cfg.rare_use_rarity ~= false)     -- 原版判据（NPC.rarity > 0）默认开启
    ra.list = parse_ids(cfg.rare_list)
    local any_rare = false
    for _ in pairs(ra.list) do any_rare = true break end
    -- ★ v5：「精英与稀有怪·刷新倍率」也走这条通道，所以它非 1 时本域必须激活
    ra.active = en and (ra.mult ~= 1 or any_rare or (sq.elite_mult ~= 1)) or false

    -- ======================================================== v3：死亡与复活 / 制作站
    local de = {}
    de.in_place = en and (cfg.respawn_mode == "in_place") or false
    de.block_tomb = en and cfg.tombstone_block or false
    -- 复活等待时间倍率（100 = 原版；原版把 respawnTimer 硬夹在 3600 帧 = 60 秒以内）
    de.time_mult = math.floor(cfg.respawn_time_mult or 100) / 100
    if de.time_mult < 0.01 then de.time_mult = 0.01 end
    if de.time_mult > 100 then de.time_mult = 100 end
    -- 秒复活：把 respawnTimer 置 1（= 原版 Player.SkipRespawnTime）
    de.instant = en and cfg.respawn_instant or false
    de.active = de.in_place or de.block_tomb or de.instant or de.time_mult ~= 1.0

    local st = {}
    st.craft_boost = en and cfg.craft_range_boost or false
    st.alchemy_global = en and cfg.alchemy_table_global or false
    st.active = st.craft_boost or st.alchemy_global

    -- ======================================================== v3：世界生成事件 / 微光
    local ge = {}
    ge.meteor = en and cfg.meteor_mode or "none"       -- none / block / boost / now
    ge.bulb_block = en and cfg.plantera_bulb_block or false
    ge.bulb_now = en and cfg.plantera_bulb_now or false
    -- 花苞补种间隔（分钟）：UI 1 = 不补种；UI N ≥ 2 = 每 (N−1) 分钟补一次
    ge.bulb_minutes = math.floor(cfg.plantera_bulb_interval or 1) - 1
    if ge.bulb_minutes < 0 then ge.bulb_minutes = 0 end
    if ge.bulb_minutes > 240 then ge.bulb_minutes = 240 end
    -- v5：世纪之花每天刷新 + 本模组触发的生成次数上限（0 = 不限）
    ge.bulb_daily = en and cfg.plantera_daily or false
    ge.bulb_daily_count = math.floor(cfg.plantera_daily_count or 10)
    if ge.bulb_daily_count < 1 then ge.bulb_daily_count = 1 end
    if ge.bulb_daily_count > 100 then ge.bulb_daily_count = 100 end
    ge.bulb_runs = en and (math.floor(cfg.plantera_bulb_runs or 1) - 1) or 0
    if ge.bulb_runs < 0 then ge.bulb_runs = 0 end
    if ge.bulb_runs > 100 then ge.bulb_runs = 100 end
    ge.active = (ge.meteor ~= "none") or ge.bulb_block or ge.bulb_now or ge.bulb_minutes > 0
        or ge.bulb_daily

    local sh = {}
    sh.on = en and cfg.shimmer_enable or false
    -- v5：任意物品→任意物品（界面值 1 = 关；N ≥ 2 = 嬗变成物品 (N−1)）
    sh.any = en and (math.floor(cfg.shimmer_any_item or 1) - 1) or 0
    if sh.any < 0 then sh.any = 0 end
    if sh.any > 6000 then sh.any = 6000 end
    sh.active = sh.on or (sh.any > 0)

    -- ======================================================== 雷击（暴风雨闪电）
    local li = {}
    li.block = en and cfg.lightning_block or false
    li.mult = pct("lightning_freq_mult")
    -- ★ v7：>100 时每帧额外补雷的次数上限（性能硬夹）
    li.extra = clamp_num(cfg.lightning_extra_cap, 1, 200, 5)
    -- ★ v9：① 起手到劈击的时长倍率（落雷弹幕 ai[1] 的每帧推进量 ×本值；
    --   1.0 = 原版 240 帧）。手改 config.json 填天文数字也只会把落雷压缩到 1 帧，无溢出风险。
    li.windup = clamp_num(cfg.lightning_windup_mult, 20, 400, 100) / 100
    li.windup_on = en and li.windup ~= 1.0
    -- ★ v9：② 同时存在的落雷上限。UI 值 1 = 不限（0）；N ≥ 2 = 最多 (N−1) 道。
    li.max_bolts = en and ui_off(cfg.lightning_max_bolts, 1, 20) or 0
    li.cap_on = li.max_bolts > 0
    -- ★ v10.1：满屏落雷（真机反馈：落雷有距离限制、想要满屏）。
    --   界面值 1 = 关（0 道）；N ≥ 2 = 每帧额外在玩家左右 ±90 格铺 (N−1) 个落点。
    --   走 **2 参 WorldGen.TrySpawnLightningBolt(x,y)** —— 它**不做**原版 4 参重载里那套
    --   「同一玩家 800 像素内已有落雷就跳过」的去重，所以能横向铺满一屏。
    li.spread = en and ui_off(cfg.lightning_spread_bolts, 1, 30) or 0
    li.spread_on = li.spread > 0
    -- ★ v10.2：两道落雷之间的最小间距（格）。0 = 本模组不额外限制。
    --   作用点是 on_try_bolt 的 prefix —— 自然落雷与「满屏落雷」都走那一道闸。
    li.min_dist = en and ui_off(cfg.lightning_min_dist, 1, 120) or 0
    li.dist_on = li.min_dist > 0
    li.active = li.block or li.mult ~= 1 or li.windup_on or li.cap_on or li.spread_on
        or li.dist_on

    -- ======================================================== 坠落之星（夜晚）
    -- 原版：夜间星落概率 ∝ Star.starfallBoost，而 Star.NightSetup() 每晚把它重置成
    -- 1 或随机 3~5。这里每帧（分桶后）写回固定值，因此开了本项就不再有「大星夜」的随机性。
    local sf = {}
    sf.mult = pct("starfall_mult")
    if sf.mult < 0 then sf.mult = 0 end
    if sf.mult > 100 then sf.mult = 100 end
    sf.active = en and sf.mult ~= 1.0

    -- ======================================================== v6：地图生成专项（§5）
    -- 纯逻辑：把设置换算成「要放几个 / 要清哪些编号 / 新建世界用哪一档」。
    -- ★ 世界大小与邪恶类型是**不可逆**的，只在新建世界时写；这里只做映射与夹取。
    local wg = {}
    wg.size = wg_size_of(en, cfg.wgen_size)            -- none / small / medium / large
    wg.evil = wg_evil_of(en, cfg.wgen_evil)            -- none / random / corruption / crimson
    wg.size_n = SIZE_CODE[wg.size]                     -- 0/1/2（nil = 不干预）
    wg.evil_n = EVIL_CODE[wg.evil]                     -- -1/0/1（nil = 不干预）
    wg.life = ui_off(cfg.wgen_life_crystals, 1, 500)
    wg.mana = ui_off(cfg.wgen_mana_crystals, 1, 500)
    wg.islands = ui_off(cfg.wgen_islands, 1, 20)
    wg.cloud_islands = ui_off(cfg.wgen_cloud_islands, 1, 20)
    wg.cloud_lakes = ui_off(cfg.wgen_cloud_lakes, 1, 20)
    wg.caves = ui_off(cfg.wgen_caves, 1, 200)
    wg.ore_veins = ui_off(cfg.wgen_ore_veins, 1, 300)
    wg.shimmer = ui_off(cfg.wgen_shimmer_biomes, 1, 5)
    wg.ore_type = clamp_num(cfg.wgen_ore_type, 1, 1000, 7)
    wg.budget = clamp_num(cfg.wgen_budget, 1, 20000, 4000)
    wg.clear = parse_ids(cfg.wgen_clear_tiles)
    wg.clear_on = next(wg.clear) ~= nil
    -- ★ v7 新增：宝箱 / 地下结构 / 沙漠绿洲 / 方块替换 / 自定义尺寸·出生点·起始时刻
    wg.chests = ui_off(cfg.wgen_chests, 1, 100)
    wg.chest_item = clamp_num(cfg.wgen_chest_item, 0, 6000, 0)
    -- ★ v10.1：界面值 0 = 原版自动（-1，地下箱 = 金箱 + 地下战利品表）；1 = 木箱，2 = 金箱 …
    --   并且**禁用 4 号样式**：原版 4 号样式 = 地狱宝箱分支，会去读只有生成期才填的
    --   GenVars.hellChestItem（生成后是 null）→ NullReferenceException → 崩。见 86 的 place_chest。
    wg.chest_style = clamp_num(cfg.wgen_chest_style, 0, 47, 0) - 1
    if wg.chest_style == 4 then wg.chest_style = 3 end
    wg.marble = ui_off(cfg.wgen_marble, 1, 20)
    wg.lihzahrd = ui_off(cfg.wgen_lihzahrd, 1, 10)
    wg.shadow_orbs = ui_off(cfg.wgen_shadow_orbs, 1, 20)
    wg.gem_caves = ui_off(cfg.wgen_gem_caves, 1, 50)
    wg.ore_patches = ui_off(cfg.wgen_ore_patches, 1, 100)
    wg.stone_patches = ui_off(cfg.wgen_stone_patches, 1, 100)
    wg.shell_piles = ui_off(cfg.wgen_shell_piles, 1, 50)
    wg.oases = ui_off(cfg.wgen_oases, 1, 10)
    -- ★ v10.2：新增的原版特征（墓地 / 苔藓 / 发光苔藓 / 神庙陷阱 / 岩浆陷阱 / 雕像陷阱 / 蜂巢）
    wg.graveyards = ui_off(cfg.wgen_graveyards, 1, 20)
    wg.moss = ui_off(cfg.wgen_moss, 1, 40)
    wg.glow_moss = ui_off(cfg.wgen_glow_moss, 1, 40)
    wg.mayan_traps = ui_off(cfg.wgen_mayan_traps, 1, 40)
    wg.lava_traps = ui_off(cfg.wgen_lava_traps, 1, 40)
    wg.statue_traps = ui_off(cfg.wgen_statue_traps, 1, 40)
    wg.bee_larva = ui_off(cfg.wgen_bee_larva, 1, 40)
    -- ★ v10.2：特征生成速度（每帧最多放几个）；一键页上也有一个快捷滑块改它
    wg.speed = clamp_num(cfg.wgen_speed, 1, 20, 1)
    wg.replace = parse_pairs(cfg.wgen_replace)
    wg.replace_on = next(wg.replace) ~= nil
    wg.cw = clamp_num(cfg.wgen_custom_w, 0, 16800, 0)
    wg.ch = clamp_num(cfg.wgen_custom_h, 0, 4800, 0)
    if wg.cw > 0 and wg.cw < 4200 then wg.cw = 4200 end
    if wg.ch > 0 and wg.ch < 1200 then wg.ch = 1200 end
    if not (wg.cw > 0 and wg.ch > 0) then wg.cw, wg.ch = 0, 0 end
    wg.spawn_x = clamp_num(cfg.wgen_spawn_x, 0, 16800, 0)
    wg.spawn_y = clamp_num(cfg.wgen_spawn_y, 0, 4800, 0)
    local wgs = tostring(cfg.wgen_start or "none")
    if wgs ~= "day" and wgs ~= "night" and wgs ~= "dusk" then wgs = "none" end
    wg.start = wgs
    -- ★ v8：崩溃修复（触发链全主线程）+ 性能预算 + 生成保真 / 自由度
    wg.island_house = (cfg.wgen_island_house ~= false)
    wg.island_style = ui_off(cfg.wgen_island_style, 1, 3)
    wg.cloud_chest = (cfg.wgen_cloud_chest == true)
    wg.reframe = (cfg.wgen_reframe ~= false)
    wg.quick_scan = (cfg.wgen_quick_scan ~= false)
    -- ★ v10：性能限制默认全部关掉（用户实测：那些限制是多余的，真因是结构一生成就崩）。
    --   gap = 1 = 不节流；hits = 0 = 每帧改动格数不限制（界面值 1 = 不限制）；
    --   cap 上限放到 5000（只是手改 config.json 填天文数字时的安全阀）。
    wg.gap = clamp_num(cfg.wgen_struct_gap, 1, 120, 1)
    wg.hits = ui_off(cfg.wgen_hits_frame, 1, 2000)
    wg.cap = clamp_num(cfg.wgen_total_cap, 1, 5000, 5000)
    -- ★ v10：天空结构的落点改成「离地表至少多少格」（sky_delta），不再用图高比例 --
    --   比例在小世界上会落到地面以下（云被塞进地里）。见 gen.py 的「天空结构的生成高度」。
    local sk = tostring(cfg.wgen_sky_band or "standard")
    if sk == "low" then wg.sky_delta = 40
    elseif sk == "high" then wg.sky_delta = 240
    else wg.sky_delta = 100 end
    local ub = tostring(cfg.wgen_under_band or "standard")
    if ub == "shallow" then wg.under_lo, wg.under_hi = 0.25, 0.60
    elseif ub == "deep" then wg.under_lo, wg.under_hi = 0.60, 0.95
    elseif ub == "all" then wg.under_lo, wg.under_hi = 0.20, 0.95
    else wg.under_lo, wg.under_hi = nil, nil end
    wg.content = (wg.life > 0) or (wg.mana > 0) or (wg.islands > 0) or (wg.cloud_islands > 0)
        or (wg.cloud_lakes > 0) or (wg.caves > 0) or (wg.ore_veins > 0) or (wg.shimmer > 0)
        or (wg.chests > 0) or (wg.marble > 0) or (wg.lihzahrd > 0) or (wg.shadow_orbs > 0)
        or (wg.gem_caves > 0) or (wg.ore_patches > 0) or (wg.stone_patches > 0)
        or (wg.shell_piles > 0) or (wg.oases > 0)
        or (wg.graveyards > 0) or (wg.moss > 0) or (wg.glow_moss > 0)
        or (wg.mayan_traps > 0) or (wg.lava_traps > 0) or (wg.statue_traps > 0)
        or (wg.bee_larva > 0)
    wg.active = en and (wg.content or wg.clear_on or wg.replace_on
        or wg.size_n ~= nil or wg.evil_n ~= nil or wg.cw > 0
        or wg.spawn_x > 0 or wg.spawn_y > 0 or wg.start ~= "none")

    -- ======================================================== 总控（节拍 / 总闸）
    local ti = math.floor(cfg.tick_interval or 10)
    if ti < 1 then ti = 1 end
    if ti > 60 then ti = 60 end
    local rs = math.floor(cfg.config_reload_sec or 5)
    if rs < 1 then rs = 1 end
    if rs > 60 then rs = 60 end

    -- ======================================================== 写回计划
    P.tick = ti
    P.host_only = (cfg.host_only ~= false)
    P.reload_sec = rs
    P.write_log = (cfg.write_log == true)
    P.starfall = sf
    P.world = w
    P.spawn = s
    P.attr = {
        active = en and attr_on or false,
        friendly = en and cfg.npc_affect_friendly or false,
        cat = a,
        override = parse_overrides(cfg.cat_override),
    }
    P.house = h
    P.pylon = py
    P.tree, P.angler, P.rare = tr, an, ra
    P.death, P.station, P.gen, P.shimmer = de, st, ge, sh
    P.events, P.spawnq, P.liquid, P.misc, P.shop, P.fish = ev, sq, lq, mi, sp, fi
    P.lightning = li
    P.wgen = wg
    P.any = w.active or s.filter or P.attr.active or h.active or py.active
        or tr.active or an.active or ra.active
        or de.active or st.active or ge.active or sh.active or li.active
        or sf.active or ev.active or sq.active or lq.on or mi.active or sp.active or fi.active
        or wg.active
    P.count = cfg_stat.keys
end



-- ============================================================================
-- 40 · 世界属性：时间 / 天气 / 事件 / 刷怪参数 / 困难模式 / 生物群系蔓延
-- ----------------------------------------------------------------------------
-- 全部挂在 Main.UpdateTimeRate 的 postfix 上，每帧一次。时机理由（v1.0.0 踩过的坑）：
--   Main.UpdateTime 内部是「事件与雨天推进 → UpdateTimeRate → time += dayRate → 各事件推进」，
--   dayRate 是在 UpdateTimeRate 里被**重新算出来**的；挂在 Main.UpdateTime 上会被它内部
--   的重算顶掉，挂在 UpdateTimeRate 的 postfix 上则「原版刚算完、时间还没推进」，
--   改 dayRate 立刻生效且不会被覆盖。
-- 写入一律走 fset_if（值不同才写）：默认配置下一次反射写入都不发。
-- ============================================================================

-- 本模组接管的「游戏不会每帧自己重算」的全局值（撤销表管理的键）
local UNDO_KEYS = { "defaultSpawnRate", "defaultMaxSpawns", "hardMode" }

-- ★★ v10.2：蔓延速度 = 世界更新速率（Main.desiredWorldTilesUpdateRate）★★
--   v5~v10 的「额外重跑逐格入口」被玩家实测判为「没反应」：原版一次 UpdateWorld 本来就
--   从全图随机抽约 0.3% 的格子，额外补几十~几千格淹没在随机噪声里。现在改成动原版自己
--   的那根旋钮：WorldGen.GetWorldUpdateRate() = min(Main.desiredWorldTilesUpdateRate, 24)，
--   而 Main.UpdateTimeRate() 每帧都会把它设回时间倍率（默认 1）。
--   本模组的钩子正好挂在 Main.UpdateTimeRate 的 postfix 上，在那里写一个 1~24 的整数，
--   每帧抽样的格数就按倍率线性上升（最多 24 倍）—— 蔓延与草 / 藤 / 植物生长一起变快。
--   低于 100% 时改用逐格入口 prefix 的「按概率跳过该格」（速率最低只能到 1，降不下去）。
local WD          -- ★ 前向声明：下面几个回调体里要引用它

local world_applied = false      -- 本模组是否已经动过世界属性
local last_day_rate = nil        -- 上一次写进去的 dayRate（防「没被重算时反复乘」）
local mp_warned = false          -- 多人客户端只提醒一次
local frame_seen_by_utr = nil    -- 上一次在本钩子里看到的心跳计数（心跳兜底的判据）
local starfall_written = nil     -- 本模组上次写进 Star.starfallBoost 的值（还原用）

-- ---------------------------------------------------------------- 主机权威总闸
-- ★ v4：总闸是核心层的 may_write()（由「联机：仅房主生效」控制）。单人 / 房主（netMode 0/2）
-- 照常；作为客机（netMode 1）时一律只读不写 —— 好友各自的设置就不会互相打架，
-- 也不会把服务器上的世界数据改乱。玩家想强行在客机生效，就把那个开关关掉。
local function mp_allowed()
    if may_write() then return true end
    if not mp_warned then
        mp_warned = true
        warn_once("mp_host_only",
            "检测到多人客户端（netMode=1）：按「联机：仅房主生效」的规则，本模组不写入任何数据。"
            .. "想让客机也强行生效，请在设置里关掉那一项。")
        diag("多人客户端：世界写入暂停（仅房主生效）")
        diag_flush()
    end
    return false
end

-- ---------------------------------------------------------------- 刷怪参数
-- NPC.defaultSpawnRate / defaultMaxSpawns 是 private static 全局值，改一次长期有效，
-- 而且**游戏不会每帧把它重算回去** —— 属于「必须先记原版基准值、卸载时要还原」那一类。
local function apply_spawn_params()
    if not (F.defaultSpawnRate and F.defaultMaxSpawns) then return end
    local w = P.world
    local cur_rate, cur_cap = fget("defaultSpawnRate"), fget("defaultMaxSpawns")
    if type(cur_rate) ~= "number" or type(cur_cap) ~= "number" then return end

    local rr = base_of("defaultSpawnRate", cur_rate)
    local rc = base_of("defaultMaxSpawns", cur_cap)

    local want_rate = math.floor(rr.base * 100 / w.spawn_rate_mult + 0.5)
    if w.no_natural_spawn then want_rate = 600000 end
    if want_rate < 1 then want_rate = 1 end
    if want_rate > 2000000000 then want_rate = 2000000000 end   -- 只防 int32 溢出

    local want_cap = math.floor(rc.base * w.spawn_cap_mult / 100 + 0.5)
    if want_cap < 0 then want_cap = 0 end
    if want_cap > 2000000000 then want_cap = 2000000000 end     -- 只防 int32 溢出

    if cur_rate ~= want_rate then commit("defaultSpawnRate", rr, want_rate) end
    if cur_cap ~= want_cap then commit("defaultMaxSpawns", rc, want_cap) end
end

local function restore_spawn_params()
    local n = 0
    for _, key in ipairs({ "defaultSpawnRate", "defaultMaxSpawns" }) do
        local rec = UNDO[key]
        if rec and rec.last ~= nil then
            local cur = fget(key)
            if cur == rec.last and fset(key, nil, rec.base) then n = n + 1 end
        end
        UNDO[key] = nil
    end
    return n
end

-- ---------------------------------------------------------------- 困难模式
-- Main.hardMode 只会在「击败血肉墙」时被游戏改写一次，所以也是「记基准值、要还原」那一类。
-- 还原时只认「当前值还是我们写进去的 true」，避免把玩家自己打出来的困难模式关掉。
local function apply_hardmode()
    if not F.hardMode then return end
    local cur = fget("hardMode")
    if type(cur) ~= "boolean" then return end
    if P.world.hardmode then
        if not cur then
            local rec = base_of("hardMode", cur)
            if commit("hardMode", rec, true) then
                diag("困难模式已由本模组开启")
                diag_flush()
            end
        end
    else
        local rec = UNDO.hardMode
        if rec then
            if rec.last ~= nil and cur == rec.last then
                fset("hardMode", nil, rec.base)
                diag("困难模式已还原")
            end
            UNDO.hardMode = nil
        end
    end
end

-- ---------------------------------------------------------------- 还原
-- 关总开关 / 卸载时调用：只还原「游戏不会自己重算」的全局值。
-- 时间流速、天气、事件状态都是游戏每帧自己重算的字段，本模组一停手它们就回原版。
local function restore_world()
    world_applied = false
    last_day_rate = nil
    -- ★ v10.2：蔓延速度也要还原 —— 把世界更新速率还回原版的 1
    --   （只有「当前值还停在我们写进去的那个值上」才还原，绝不覆盖别人写的）
    local last_rate = mem.sp_rate_last
    mem.sp_rate_last = nil
    if last_rate and last_rate ~= 1 and F.desired_world_rate then
        local cur = fget("desired_world_rate")
        if type(cur) == "number" and cur == last_rate then
            if fset("desired_world_rate", nil, 1) then
                diag("蔓延速度：世界更新速率已还原为 1")
            end
        end
    end
    -- 坠落之星：只有还停在我们写进去的那个值上才还原
    if starfall_written ~= nil then
        local cur = fget("starfall_boost")
        if type(cur) == "number" and math.abs(cur - starfall_written) < 1e-4 then
            fset("starfall_boost", nil, 1.0)
        end
        starfall_written = nil
    end
    local n = restore_spawn_params()
    local rec = UNDO.hardMode
    if rec then
        local cur = fget("hardMode")
        if rec.last ~= nil and cur == rec.last then
            fset("hardMode", nil, rec.base)
            n = n + 1
        end
        UNDO.hardMode = nil
    end
    if n > 0 then
        diag("已还原 " .. n .. " 个全局值")
        diag_flush()
    end
end

-- ---------------------------------------------------------------- 时间
local function apply_time()
    local w = P.world
    if not F.dayRate then return end
    local cur = fget("dayRate")
    if type(cur) ~= "number" then return end

    local target
    if w.freeze or w.lock_ticks ~= nil then
        target = 0
    elseif w.time_speed ~= 1.0 then
        if last_day_rate ~= nil and cur == last_day_rate then
            -- 正常不会发生：说明原版这一帧没有重算 dayRate，而我们上次写的值还在。
            -- 此时再乘一次就会指数放大（1→2→4→8…），所以宁可这一帧不动手。
            warn_once("day_rate_hold", "dayRate 未被原版重算，已暂停倍率写入以免指数放大")
            return
        end
        target = math.floor(cur * w.time_speed + 0.5)
    else
        last_day_rate = nil
        return
    end

    if target < 0 then target = 0 end
    if target > 2000000000 then target = 2000000000 end         -- 只防 int32 溢出
    if target ~= cur then
        if fset("dayRate", nil, target) then last_day_rate = target end
    else
        last_day_rate = nil
    end
end

-- ---------------------------------------------------------------- 坠落之星（夜晚）
-- 原版：`WorldGen` 的星落判定是 `Main.rand.Next(8000) < 10 * (maxTilesX/4200) * Star.starfallBoost`，
-- 而 `Star.NightSetup()`（每晚开始时）会把 starfallBoost 重置成 1，或 1/10 概率给 3~5 倍。
-- 于是只要每个节拍把目标值写回去，就能稳定控制坠落之星的数量。
local function apply_starfall()
    local sf = P.starfall
    if not sf then return end
    if not F.starfall_boost then return end
    if not sf.active then
        -- 关掉后把值还回 1.0（只有还是我们写的那一个值才还原，不覆盖别人）
        if starfall_written ~= nil then
            local cur = fget("starfall_boost")
            if type(cur) == "number" and math.abs(cur - starfall_written) < 1e-4 then
                fset("starfall_boost", nil, 1.0)
            end
            starfall_written = nil
        end
        return
    end
    local want = sf.mult
    local cur = fget("starfall_boost")
    if type(cur) == "number" and math.abs(cur - want) < 1e-4 then
        starfall_written = want
        return
    end
    if fset("starfall_boost", nil, want) then
        starfall_written = want
        stats.starfall_sets = (stats.starfall_sets or 0) + 1
    end
end

-- ★★ v10.2：把「蔓延速度」写进原版的世界更新速率 ★★（见文件头）
--   必须逐帧写：Main.UpdateTimeRate 每帧都会把它重置成时间倍率（默认 1），
--   而我们正跑在它的 postfix 上，所以「这一帧写完，UpdateWorld 立刻就用新值」。
local function apply_spread_rate()
    local w = P.world
    if not w or not F.desired_world_rate then return end
    local cur = fget("desired_world_rate")
    if type(cur) ~= "number" then return end
    if not w.spread_rate_on then
        -- 关掉时还回原版的 1：只认「当前值还是我们写进去的那个」，绝不覆盖别人写的值
        local last = mem.sp_rate_last
        mem.sp_rate_last = nil
        if last and last ~= 1 and cur == last then
            if fset("desired_world_rate", nil, 1) then
                diag("蔓延速度：世界更新速率已还原为 1")
            end
        end
        return
    end
    local want = w.spread_rate or 1
    if want < 1 then want = 1 end
    if want > 24 then want = 24 end
    -- 当前值是 0 = 游戏本意是「这一帧不做世界更新」（菜单 / 冻结时间），绝不硬开
    if cur == 0 then mem.sp_rate_last = nil return end
    if cur ~= want then
        if fset("desired_world_rate", nil, want) then
            dcount(WD, "蔓延速率写入", 1)
        end
    end
    mem.sp_rate_last = want
end

-- ---------------------------------------------------------------- 世界属性总入口
-- ★ v4 性能：必须逐帧的（dayRate 倍率 / 时间冻结）保持逐帧；其余按「非关键项刷新间隔」
-- 分桶轮转（bucket_ok），每 interval 帧才碰一次。interval = 1 时退化成逐帧（等价旧行为）。
local function apply_world()
    local w = P.world
    local sf_on = P.starfall and P.starfall.active
    -- ★ v4.0.1 修：坠落之星原来只在 apply_world 里被调，而进门的判据只有 P.world.active ——
    --   于是「只开坠落之星倍率、其它世界属性全默认」时一次都不会写。现在它自己也算「有待办」。
    if not (w.active or sf_on) then
        -- 注意：即使都变成 false 也要进来一次 —— 它负责把之前写过的
        -- 全局刷怪参数 / 困难模式还原回原版（否则关掉功能后那些值会永远停在被改过的状态）
        if world_applied then pcall(restore_world) end
        return
    end
    if not mp_allowed() then return end
    world_applied = true
    local ti = P.tick or 10

    -- 只有「坠落之星」开着时，跳过下面所有世界属性写入，直接到桶 6
    if not w.active then
        if bucket_ok(6, ti) then pcall(apply_starfall) end
        return
    end

    -- ---- 时间倍率：必须逐帧（原版每帧重算 dayRate）----
    pcall(apply_time)

    -- ---- v10.2：蔓延速度（写原版的世界更新速率；必须逐帧，原版每帧都会重置它）----
    pcall(apply_spread_rate)

    -- ---- 桶 1：雨 ----
    if bucket_ok(1, ti) then
        if w.rain == "on" then
            fset_if("raining", nil, true)
            if F.rainTime then fset_if("rainTime", nil, 86400) end
            if F.maxRaining then fset_if("maxRaining", nil, w.rain_val) end
            if F.cloudAlpha then fset_if("cloudAlpha", nil, w.rain_val) end
        elseif w.rain == "off" then
            fset_if("raining", nil, false)
            if F.rainTime then fset_if("rainTime", nil, 0) end
            if F.maxRaining then fset_if("maxRaining", nil, 0.0) end
            if F.cloudAlpha then fset_if("cloudAlpha", nil, 0.0) end
        end
    end

    -- ---- 桶 2：风 + 沙尘暴 ----
    if bucket_ok(2, ti) then
        if w.wind == "lock" or w.wind == "calm" then
            local v = w.wind_val
            if w.wind == "calm" then v = 0.0 end
            if F.windSpeedCurrent then fset_if("windSpeedCurrent", nil, v) end
            if F.windSpeedTarget then fset_if("windSpeedTarget", nil, v) end
        end
        if w.sand == "on" then
            fset_if("Happening", nil, true)
            if F.TimeLeft then fset_if("TimeLeft", nil, 80000) end
            if F.IntendedSeverity then fset_if("IntendedSeverity", nil, w.sand_val) end
        elseif w.sand == "off" then
            fset_if("Happening", nil, false)
            if F.TimeLeft then fset_if("TimeLeft", nil, 0) end
            if F.IntendedSeverity then fset_if("IntendedSeverity", nil, 0.0) end
        end
        if w.cloud_lock then fset_if("numClouds", nil, w.cloud_amount) end
    end

    -- ---- 桶 3：血月 / 日食 / 史莱姆雨 / 灯笼夜 / 派对 / 南瓜月 / 霜月 / 节日 ----
    if bucket_ok(3, ti) then
        if w.block_blood_moon then
            fset_if("bloodMoon", nil, false)
        elseif w.blood_moon then
            fset_if("bloodMoon", nil, true)
        end
        if w.block_eclipse then
            fset_if("eclipse", nil, false)
        elseif w.eclipse then
            fset_if("eclipse", nil, true)
        end
        if w.block_slime_rain then
            fset_if("slimeRain", nil, false)
            if F.slimeRainTime then fset_if("slimeRainTime", nil, 0.0) end
        elseif w.slime_rain then
            fset_if("slimeRain", nil, true)
            if F.slimeRainTime then fset_if("slimeRainTime", nil, 3600.0) end
        end
        if w.lantern_night then fset_if("ManualLanterns", nil, true) end
        if w.party then fset_if("ManualParty", nil, true) end
        if w.pumpkin_moon then fset_if("pumpkinMoon", nil, true) end
        if w.snow_moon then fset_if("snowMoon", nil, true) end
        if w.halloween then fset_if("forceHalloweenForToday", nil, true) end
        if w.christmas then fset_if("forceXMasForToday", nil, true) end
    end

    -- ---- 桶 4：锁定时刻 / 月相（dayRate 已经被上面的 apply_time 归零，时间不会漂走）----
    if bucket_ok(4, ti) then
        if w.lock_ticks ~= nil then
            fset_if("dayTime", nil, w.lock_day and true or false)
            if F.time then
                local cur = fget("time")
                if type(cur) == "number" and math.abs(cur - w.lock_ticks) > 1.0 then
                    fset("time", nil, w.lock_ticks)
                end
            end
        end
        if w.moon_lock >= 0 then fset_if("moonPhase", nil, w.moon_lock) end
    end

    -- ---- 桶 5：刷怪参数 / 困难模式（改一次长期有效，被别的模组改回去也能在一个节拍内纠正）----
    if bucket_ok(5, ti) then
        if w.spawn_check then pcall(apply_spawn_params) else pcall(restore_spawn_params) end
        pcall(apply_hardmode)
    end

    -- ---- 桶 6：坠落之星 ----
    if bucket_ok(6, ti) then pcall(apply_starfall) end
end

-- ---------------------------------------------------------------- 钩子
local function on_update_time_rate(inst, args, result)
    if not ready then return end
    -- 心跳兜底：心跳本来挂在 Player.ResetEffects 上（每帧一次）。万一那个钩子装不上、
    -- 或者跑在没有本地玩家的服务端，这里补一次 —— 判据是「这一帧心跳还没跑过」
    -- （心跳每跑一次 stats.frames 就 +1），所以它**只在心跳真的没跑时**才补，
    -- 不会把 tick 的 30 帧限流变成 15 帧。
    if frame_seen_by_utr == nil or stats.frames == frame_seen_by_utr then
        pcall(tick)
    end
    frame_seen_by_utr = stats.frames
    -- v3：把「每帧的世界生成逻辑」派发给别的功能域（陨石的待落标志）。
    -- 位置在心跳兜底之后、世界属性写入之前：主菜单里不做（menu_flag 时直接跳过）。
    if not menu_flag then call_domains("world") end
    if menu_flag then return end
    if not (P.world.active or world_applied or (P.starfall and P.starfall.active)) then return end
    local ok, err = pcall(apply_world)
    if not ok then warn_once("apply_world", "世界属性应用失败：" .. tostring(err)) end
end

local function on_start_invasion(inst, args)
    if not ready or not P.world.block_invasion then return end
    return true                      -- 跳过原方法：这次入侵不开始
end

-- ★ v5：入侵波数倍率只能在 Main.StartInvasion **执行完之后**写
--   （postfix 里才拿得到原版刚设好的 invasionSize / invasionSizeStart）。
--   这个方法的主钩子归 40_world（禁止入侵），所以后来者按约定登记成阶段函数，
--   由这里 call_domains("invasion") 派发给 41_events。
local function on_start_invasion_post(inst, args)
    if not ready then return end
    call_domains("invasion")
end

-- UpdateWorld 每帧开头都会把 AllowedToSpreadInfections 重置成「允许」，之后才逐个图格读它。
-- 所以只能在它内部、读开关的那一句上动手：AllowedToSpreadInfections = !StopBiomeSpreadPower.Enabled
local function on_update_world_prefix()
    fl.world_update = true
end

local function on_update_world_postfix()
    fl.world_update = false
end

local function on_get_enabled(inst, args)
    if not ready or not fl.world_update then return end
    if P.world.spread_block then return true, true end    -- Enabled=true  → 停止蔓延
    if P.world.spread_force then return true, false end   -- Enabled=false → 强制蔓延
    -- ★ v7：<100 的「按比例减速」改挂逐格更新入口的 prefix（见 on_tile_prefix），
    --   不再走这里 —— 旧版依赖 CreativePowers.ASharedTogglePower.get_Enabled，
    --   手机上取不到那个嵌套类型时三条路会一起静默失效。
end

-- ★ v7：蔓延速率 < 100 = 在原版**逐格**世界更新入口的 prefix 里按概率跳过该格。
--   （手机版 UpdateWorld_OvergroundTile / UpdateWorld_UndergroundTile 是 4 个标量参，
--     PC 是 3 个 —— 这里按 4 取，与 M.ow_tile / M.ug_tile 一致。）
local function on_tile_prefix(inst, args)
    if not ready then return nil end
    local w = P.world
    if not w then return nil end
    if w.spread_block or w.spread_force then return nil end
    local m = w.spread_mult or 100
    if m < 100 then
        -- 只有「慢于原版」才需要这条：速率本身最低是 1，降不下去
        if math.random() >= m / 100 then
            dcount(WD, "跳过蔓延格", 1)
            return true
        end
    end
    return nil
end

-- ★★ v10.2：删掉了 v10 的「额外重跑逐格更新入口」整条路 ★★
--   （spread_size / spread_extra_step / on_ow_tile / on_ug_tile 与 spread_extra_cap 设置一并移除）
--   理由：那正是玩家报了两轮的「调了没反应」—— 同一批格子重跑基本幂等，换新坐标也只是
--   在 0.3% 的抽样噪声上加一点点。现在只保留「< 100% 时按概率跳过该格」这条可靠的下调路径。

-- CreativePowers 里嵌套的 ASharedTogglePower 类型：优先用 get_inner_types 枚举，
-- 拿不到再退化成一串名字猜测，全取不到就放弃该功能（蔓延开关失效，其余不受影响）。
local function find_toggle_power_type()
    local T_CP = get_type("Terraria.GameContent.Creative", "CreativePowers")
    if T_CP and patch.get_inner_types and patch.get_full_name then
        local ok, list = pcall(patch.get_inner_types, T_CP)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local ok2, full = pcall(patch.get_full_name, list[i])
                if ok2 and type(full) == "string" and full:find("ASharedTogglePower", 1, true) then
                    return list[i]
                end
            end
        end
    end
    local names = { "ASharedTogglePower", "CreativePowers.ASharedTogglePower",
                    "CreativePowers+ASharedTogglePower" }
    for i = 1, #names do
        local ok, t = pcall(get_type, "Terraria.GameContent.Creative", names[i])
        if ok and t then return t end
    end
    return nil
end

WD = domain({
    name = "世界属性",
    fields = function(T)
        -- Main：时间 / 天气 / 事件 / 难度 / 多人
        register("dayRate", T.MAIN, "dayRate", "int32")
        register("dayTime", T.MAIN, "dayTime", "bool")
        register("time", T.MAIN, "time", "double")
        register("moonPhase", T.MAIN, "moonPhase", "int32")
        register("raining", T.MAIN, "raining", "bool")
        register("rainTime", T.MAIN, "rainTime", "int32")
        register("maxRaining", T.MAIN, "maxRaining", "float")
        register("cloudAlpha", T.MAIN, "cloudAlpha", "float")
        register("windSpeedCurrent", T.MAIN, "windSpeedCurrent", "float")
        register("windSpeedTarget", T.MAIN, "windSpeedTarget", "float")
        register("numClouds", T.MAIN, "numClouds", "int32")
        register("bloodMoon", T.MAIN, "bloodMoon", "bool")
        register("eclipse", T.MAIN, "eclipse", "bool")
        register("slimeRain", T.MAIN, "slimeRain", "bool")
        register("slimeRainTime", T.MAIN, "slimeRainTime", "double")
        register("pumpkinMoon", T.MAIN, "pumpkinMoon", "bool")
        register("snowMoon", T.MAIN, "snowMoon", "bool")
        register("hardMode", T.MAIN, "hardMode", "bool")
        register("netMode", T.MAIN, "netMode", "int32")
        register("forceHalloweenForToday", T.MAIN, "forceHalloweenForToday", "bool")
        register("forceXMasForToday", T.MAIN, "forceXMasForToday", "bool")
        register("gameMenu", T.MAIN, "gameMenu", "bool")
        -- v5：世界尺寸（蔓延加速的步长、液体灌注的范围都要用）
        register("max_tiles_x", T.MAIN, "maxTilesX", "int32")
        register("max_tiles_y", T.MAIN, "maxTilesY", "int32")
        -- ★ v10.2：世界更新速率（= 蔓延速度的旋钮）。public static int 非 const。
        register("desired_world_rate", T.MAIN, "desiredWorldTilesUpdateRate", "int32")
        register("npc", T.MAIN, "npc", "object")
        -- NPC：刷怪参数（静态全局值）
        register("defaultSpawnRate", T.NPC, "defaultSpawnRate", "int32")
        register("defaultMaxSpawns", T.NPC, "defaultMaxSpawns", "int32")
        -- 沙尘暴 / 灯笼夜 / 派对
        register("Happening", T.SAND, "Happening", "bool")
        register("TimeLeft", T.SAND, "TimeLeft", "int32")
        register("IntendedSeverity", T.SAND, "IntendedSeverity", "float")
        register("Severity", T.SAND, "Severity", "float")
        register("ManualLanterns", T.LANTERN, "ManualLanterns", "bool")
        register("ManualParty", T.PARTY, "ManualParty", "bool")

        -- v4：夜晚坠落之星（Terraria.Star.starfallBoost，public static float，非 const）
        register("starfall_boost", T.STAR, "starfallBoost", "float")
    end,
    methods = function(T)
        M.update_time_rate = find_method(T.MAIN, "UpdateTimeRate", 0)
        M.start_invasion = find_method(T.MAIN, "StartInvasion", 1)
        M.update_world = T.WORLDGEN and find_method(T.WORLDGEN, "UpdateWorld", 0)
        -- v5：逐格世界更新入口（4 个标量参、private static；蔓延速率 > 100 时额外重跑它们）
        M.ow_tile = T.WORLDGEN and find_method(T.WORLDGEN, "UpdateWorld_OvergroundTile", 4)
        M.ug_tile = T.WORLDGEN and find_method(T.WORLDGEN, "UpdateWorld_UndergroundTile", 4)
        local T_TOGGLE = find_toggle_power_type()
        M.get_enabled = T_TOGGLE and find_method(T_TOGGLE, "get_Enabled", 0)
        if not M.get_enabled and T_TOGGLE and patch.get_property and patch.property_get_method then
            local okp, prop = pcall(patch.get_property, T_TOGGLE, "Enabled")
            if okp and prop then
                local okg, g = pcall(patch.property_get_method, prop)
                if okg then M.get_enabled = g end
            end
        end
        if not M.get_enabled then
            mod.warn("找不到 CreativePowers.ASharedTogglePower.get_Enabled：「禁止/强制蔓延」不可用")
        end
    end,
    install = function()
        if not safe_hook(M.update_time_rate, { postfix = on_update_time_rate }, "Main.UpdateTimeRate") then
            mod.error("主钩子（Main.UpdateTimeRate）装不上：时间 / 天气 / 事件 / 刷怪参数全部不可用")
        end
        safe_hook(M.start_invasion,
            { prefix = on_start_invasion, postfix = on_start_invasion_post }, "Main.StartInvasion")
        safe_hook(M.ow_tile, { prefix = on_tile_prefix },
            "WorldGen.UpdateWorld_OvergroundTile（只在蔓延速率 < 100% 时按概率跳过该格）")
        safe_hook(M.ug_tile, { prefix = on_tile_prefix },
            "WorldGen.UpdateWorld_UndergroundTile（同上）")
        safe_hook(M.update_world, { prefix = on_update_world_prefix, postfix = on_update_world_postfix },
            "WorldGen.UpdateWorld")
        safe_hook(M.get_enabled, { prefix = on_get_enabled }, "CreativePowers.ASharedTogglePower.get_Enabled")
    end,
})


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 41 · 入侵 / 事件进度 / 月亮事件的自动重复（v5 新增）
  -- ----------------------------------------------------------------------------
  -- 三条功能、三条独立的通道，都默认等于原版：
  --
  --   ① 入侵波数·倍率（invasion_wave_mult）
  --      证据（PC 1.4.5.8 `Main.StartInvasion(int)`）：入侵开始时把
  --      `Main.invasionSize` 与 `Main.invasionSizeStart` 设成「本次要击杀的敌人数」，
  --      之后每杀一只 `invasionSize--`，减到 0 事件结束。所以**只在开始那一刻**乘一次
  --      就能把波次拉长 / 缩短，而且不会和原版的击杀计数打架（中途绝不再写）。
  --      ★ 挂点必须挂在 `Main.StartInvasion` 的 postfix 上，而 40_world 已经占了这个方法
  --        的 prefix（禁止入侵）。同一方法装第二个钩子会把先装的那个顶掉，所以 40_world
  --        在它自己的 hook 里 `call_domains("invasion")` 派发到这里（见 10_core 的说明）。
  --
  --   ② 事件进度·快进倍率（event_progress_mult）
  --      证据（PC 1.4.5.8）：入侵 / 南瓜月 / 霜月的进度条读数就是
  --      `Main.invasionProgress`（上限 `Main.invasionProgressMax`），原版靠击杀累加它。
  --      这里每帧额外补 `上限 × (倍率−100) ÷ 100 ÷ 60` 点（= 每秒额外推进这么多），
  --      只喂进度条、不碰刷怪与击杀计数。倍率 ≤ 100 时一行都不执行。
  --
  --   ③ 日食 / 血月 / 南瓜月 / 霜月的自动重复间隔
  --      原版这三个（日食、血月、月亮事件）都是「满足条件时随机出现」，没有周期。
  --      这里用 `Main.dayTime` 的边沿自己数天：天亮 = 新的一天 +1；
  --      天亮时若 `天数 % 日食间隔 == 0` 就 `eclipse = true`；
  --      入夜时若 `天数 % 血月间隔 == 0` 就 `bloodMoon = true`（南瓜月 / 霜月同理）。
  --      ★ 「禁止」优先于「自动重复」，「永久」也优先于「自动重复」——
  --        三种写法同时开时不会互相打架（禁止 > 永久 > 自动重复）。
  --      ★ 第一次观测到当前昼夜相位时**只记录、不触发**，所以不会一进世界就突然来一场。
  -- ============================================================================

  local EV          -- ★ 前向声明：下面几个回调体里要引用它，Lua 要求引用处的 local 已声明
  EV = domain({
      name = "事件与月亮事件",
      fields = function(T)
          -- Main：入侵与月亮事件（全部 public static、非 const，符号表已核实）
          register("invasion_size", T.MAIN, "invasionSize", "int32")
          register("invasion_size_start", T.MAIN, "invasionSizeStart", "int32")
          register("invasion_type", T.MAIN, "invasionType", "int32")
          register("invasion_progress", T.MAIN, "invasionProgress", "int32")
          register("invasion_progress_max", T.MAIN, "invasionProgressMax", "int32")
          -- dayTime / eclipse / bloodMoon / pumpkinMoon / snowMoon 由 40_world 注册（同一个域表）
      end,
      -- 入境（StartInvasion postfix，由 40_world 派发）：
      invasion = function()
          local e = P.events
          EV.hits = EV.hits + 1
          if not e or not e.wave or not may_write() then return end
          if not (F.invasion_size and F.invasion_size_start) then return end
          local m = e.wave_mult
          if m == 1 then return end
          local sz = fget("invasion_size")
          if type(sz) ~= "number" or sz <= 0 then return end
          local want = math.floor(sz * m + 0.5)
          if want < 1 then want = 1 end
          if want > 100000000 then want = 100000000 end   -- 只防 int32 溢出
          if want ~= sz then
              fset("invasion_size", nil, want)
              fset_if("invasion_size_start", nil, want)
              dcount(EV, "波数改写", 1)
              verbose("入侵波数：" .. sz .. " → " .. want)
          end
      end,
      -- 每帧（由 Main.UpdateTimeRate postfix 派发，见 40_world）：进度快进 + 昼夜边沿
      world = function()
          local e = P.events
          if not e or not (e.prog or e.rep) then return end
          local d = fget("dayTime")
          if type(d) ~= "boolean" then return end

          -- ---- 昼夜边沿：只在相位真的翻转时动一次 ----
          local last = mem.ev_phase
          if last == nil then
              mem.ev_phase = d                      -- 第一次看到：只记录，不触发
          elseif last ~= d then
              mem.ev_phase = d
              if d then
                  mem.ev_day = (mem.ev_day or 0) + 1     -- 天亮 = 新的一天
                  dcount(EV, "天数", 1)
              end
              if not may_write() then return end
              local w = P.world
              local n = mem.ev_day or 0
              if d then
                  if e.eclipse_days > 0 and (n % e.eclipse_days) == 0
                      and not w.eclipse and not w.block_eclipse then
                      if fset_if("eclipse", nil, true) then
                          dcount(EV, "日食", 1)
                          chat_print("[世界工坊] 自动重复：今天是日食")
                      end
                  end
              else
                  if e.blood_days > 0 and (n % e.blood_days) == 0
                      and not w.blood_moon and not w.block_blood_moon then
                      if fset_if("bloodMoon", nil, true) then
                          dcount(EV, "血月", 1)
                          chat_print("[世界工坊] 自动重复：今晚是血月")
                      end
                  end
                  if e.pumpkin_days > 0 and (n % e.pumpkin_days) == 0 and not w.pumpkin_moon then
                      if fset_if("pumpkinMoon", nil, true) then
                          dcount(EV, "南瓜月", 1)
                          chat_print("[世界工坊] 自动重复：今晚是南瓜月")
                      end
                  end
                  if e.snow_days > 0 and (n % e.snow_days) == 0 and not w.snow_moon then
                      if fset_if("snowMoon", nil, true) then
                          dcount(EV, "霜月", 1)
                          chat_print("[世界工坊] 自动重复：今晚是霜月")
                      end
                  end
              end
          end

          -- ---- 事件进度快进（只喂进度条）----
          if not e.prog or not may_write() then return end
          local m = e.prog_mult
          if m <= 1 then return end
          local pg = fget("invasion_progress")
          local mx = fget("invasion_progress_max")
          if type(pg) ~= "number" or type(mx) ~= "number" then return end
          if pg < 0 or mx <= 0 then return end          -- -1 = 当前没有事件
          local it = fget("invasion_type")
          local pm, sm = fget("pumpkinMoon"), fget("snowMoon")
          local live = (type(it) == "number" and it ~= 0) or pm == true or sm == true
          if not live then return end
          -- 每帧 = 每秒的 1/60：(倍率−100)% × 上限 ÷ 60
          local add = mx * (m - 1) / 6000
          mem.ev_carry = (mem.ev_carry or 0) + add
          local inc = math.floor(mem.ev_carry)
          if inc < 1 then return end
          mem.ev_carry = mem.ev_carry - inc
          if inc > mx then inc = mx end
          if fset("invasion_progress", nil, math.floor(pg + inc)) then
              dcount(EV, "进度补点", inc)
          end
      end,
      reset = function()
          mem.ev_phase, mem.ev_day, mem.ev_carry = nil, 0, 0
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 42 · 雷击（暴风雨的落雷与闪光）—— ★ v7 按「真正劈人的那条链」重写；v9 加两项
  -- ----------------------------------------------------------------------------
  -- 【为什么 v6 及以前无效】旧版只做两件事：prefix 拦 Main.NewLightning(bool,bool)
  --   与每帧压 4 个字段（lightning / thunderDelay / lightningDecay / lightningSpeed）。
  --   但 1.4.5.8 的雷击是**两套**（PC 逻辑权威）：
  --     · Main.NewLightning(bool instant, bool skipSound)（2 参 public static，Main.cs:59652 起）
  --       = 只做屏幕闪光 + 雷声，只设 lightning / lightningDecay / lightningSpeed / thunderDelay，
  --         **不产生任何伤害**；
  --     · WorldGen.SpawnStormLightning()（0 参 private static，WorldGen.cs:72444）
  --       = 每帧由 WorldGen.UpdateWorld() 调用（WorldGen.cs:72081）；它对每个在雨里的玩家按
  --         1/150 的概率调用 SpawnStormLightningNearPlayer → TrySpawnLightningBolt(x,y)
  --         （2 参 public static，WorldGen.cs:72585）→ Projectile.NewProjectile(...) 生成落雷。
  --   → 旧版「一根都没碰到落雷链」，所以玩家开「禁止雷击」照样被雷劈，观感就是完全无效。
  --
  -- 【v7 挂点】三条链一起拦（都是全标量参数，可安全装 hook）：
  --   · WorldGen.SpawnStormLightning()      0 参 → prefix 拦（禁止 / 概率减速）；postfix 补雷（倍率>100）
  --   · WorldGen.TrySpawnLightningBolt(int,int) 2 参 → prefix 拦（禁止；第二道闸）
  --   · Main.NewLightning(bool,bool)         2 参 → prefix 拦（禁止时把闪光雷声也关掉）
  -- 【命名计数器】风暴拦截 / 概率拦截 / 额外补雷 / 落雷拦截 / 闪光雷声拦截
  --   （进世界自检播报 + /forge stat 可查，取不到句柄时域状态是可见的 ❌）
  --
  -- ★★★ v9 新增两项（用户要求：改「从特效产生到劈下来」的时间 + 改「同时存在的雷击上限」）★★★
  --   【A. 起手到劈击的时长（lightning_windup_mult）】
  --     证据链（PC 1.4.5.8 源码，逻辑权威）：
  --       WorldGen.cs:72598  Projectile.NewProjectile(..., 1091, 500, 0f, Main.myPlayer, -1f, 0f, num)
  --                           → ProjectileID.StormLightning = 1091（1.4.5.8 手机版 dump.cs
  --                             「public const short StormLightning = 1091」已核实，同一个号）
  --       Projectile.cs:10177 SetDefaults：type 1091 → aiStyle = 203、hostile = true
  --       Projectile.cs:40361 AI_203_StormLightning()：
  --             int num = 240;  ai[1]++;  if (ai[1] >= num) Kill();
  --             float num7 = ai[1] / num;              ← 闪电绘制进度
  --             ai[1] == (int)(num * 0.15f) → 起手音效 + StormlightningWindup 粒子
  --       即：**弹幕的存活帧数就是「特效出现 → 劈完」的总时长**，全部由 ai[1] 的推进量决定。
  --     挂点 = Projectile.AI_203_StormLightning 的 **postfix**（0 参实例方法；只在落雷弹幕上跑，
  --       不是 Projectile.Update 那种每帧几百次的热路径）。回调里：
  --         ① 先读弹幕的 type 字段，不是 1091 就早退（aiStyle 203 还被 1117/1122 用）；
  --         ② 读 ai[1]（手机版 ai 是**内联结构体** Float_FixedArray_3 → 用 get_field_raw(12 字节)
  --            + string.unpack("<f", raw, idx*4+1)；桌面端是托管 float[] → array_at。与参考库
  --            auto-fisher / combat-pets 的 proj_ai_get / proj_ai_set 完全同款写法）；
  --         ③ 写回 ai[1] + (1 / 倍率 - 1)，夹在 [0, 240]：倍率 200% → 每帧净 +0.5 → 480 帧
  --            （时长 x2，更慢）；倍率 50% → 每帧净 +2 → 120 帧（更快）。
  --            ★ v10 修正：旧版写成 ai[1] + (倍率 - 1)（把倍率当**速度**用），实测「调高 → 落雷加快」，
  --            与本项名字「时长倍率」正好相反 —— 这就是用户报的「倒数 / 单位反」。
  --            ★ 只写 ai[1]，不碰伤害、落点、
  --            localAI（伤害判定 Damage_CanDealDamage 里那条 localAI[0] 的门我们一律不动）。
  --   【B. 同时存在的落雷上限（lightning_max_bolts）】
  --     WorldGen.TrySpawnLightningBolt(int,int) 的 prefix 里数一遍现役落雷：Main.projectile 的
  --     1000 个槽位（★ Main.maxProjectiles 是 **const = 1000**，按红线 2 抄常数，绝不读 const 字段），
  --     槽位 → Projectile 实例（patch.array_at）→ active(bool) + type(int)，数 type == 1091。
  --     数到上限 → prefix 返回 true = 跳过原方法 = 这次不生成。同一帧内只数一次（mem 缓存）。
  --     ★ 原版自己只在「同一玩家 800 像素内已有落雷」时跳过（WorldGen.cs:72573-72581），跨玩家仍叠加。
  -- ============================================================================

  -- ★★ v10.2 修的四件事（细节写在对应函数上方）★★
  --   ① 满屏落雷不生效：pcall(spread_bolts) 原来挂在「频率倍率 > 100%」分支里，而且
  --      spread_bolts 在声明之前就被引用（全局 nil）→ 现在前向声明 + 每帧独立执行。
  --   ② 同时存在的落雷上限无效：原来 fl.li_invoke 一进来就 return，把本模组自己补的雷
  --      全放行了 → 现在只有 fl.li_force（一键手动劈雷）才全放行。
  --   ③ 新增「两道落雷的最小间距」：同一道闸上按格距判，自然雷与满屏雷都管。
  --   ④ 每帧只扫一遍 Main.projectile（上限 + 间距共用），并用 li_add 把本帧已放行的
  --      落雷算进去，避免「一帧内连生几十道」把上限整个绕过去。
  local LI          -- ★ 前向声明：回调体里要引用它
  local spread_bolts -- ★★ v10.2 前向声明（这正是「满屏落雷没反应」的第二个原因：
                     --   旧版在声明之前引用它 → 那是全局名 nil → pcall(nil) 每帧静默失败）

  -- ★ v9 常量（都是 const 字面量，抄的是官方源码 / 符号表的「默认值」列，不是读 const 字段）
  local BOLT_TYPE = 1091      -- ProjectileID.StormLightning
  local MAX_PROJ = 1000       -- Main.maxProjectiles（const）
  local AI203_LIFE = 240      -- AI_203_StormLightning 里的 num（存活帧数硬夹上界）

  -- ① 主钩子：原版每帧的排雷入口（0 参 private static）
  local function on_spawn_storm(inst, args)
      if not ready then return nil end
      local li = P.lightning
      if not li or not li.active then return nil end
      LI.calls = LI.calls + 1
      if not may_write() then return nil end
      if li.block then
          LI.hits = LI.hits + 1
          dcount(LI, "风暴拦截", 1)
          return true                 -- 跳过原方法 = 本帧不排雷
      end
      local m = li.mult
      if m < 1 and math.random() >= m then
          LI.hits = LI.hits + 1
          dcount(LI, "概率拦截", 1)
          return true
      end
      return nil
  end

  -- ② postfix：满屏落雷（每帧）+ 频率倍率 > 100 的额外补雷
  local function on_spawn_storm_post(inst, args)
      if not ready or fl.li_invoke then return nil end
      local li = P.lightning
      if not li or not li.active or li.block then return nil end
      if not may_write() then return nil end
      -- ★★ v10.2 修「满屏落雷不生效」★★（原版有两个独立的致命原因，缺一不可）
      --   ① 旧版把 pcall(spread_bolts) 写在下面「if m <= 1 then return nil end」的**后面**：
      --      「雷击频率」保持默认 100% 时一行都不执行 —— 而玩家开满屏落雷时通常不会同时去
      --      动频率倍率，于是永远看不到效果。
      --   ② 更隐蔽：spread_bolts 是后文才声明的 local，旧版在它之前引用 → 那是全局名（nil）
      --      → pcall(nil) 每帧静默失败。现在它已在文件上方前向声明。
      if li.spread_on and mem.li_spread_at ~= stats.frames then
          mem.li_spread_at = stats.frames
          pcall(spread_bolts)
      end
      local m = li.mult
      if m <= 1 then return nil end
      if not M.storm_lightning then return nil end
      local p = m - 1
      local cap = li.extra or 5
      if p > cap then p = cap end
      local n = math.floor(p)
      if math.random() < (p - n) then n = n + 1 end
      for _ = 1, n do
          fl.li_invoke = true
          local ok, err = invoke_checked(M.storm_lightning, 0)
          fl.li_invoke = false
          if ok then
              LI.hits = LI.hits + 1
              dcount(LI, "额外补雷", 1)
          else
              LI.errs = LI.errs + 1
              LI.last_err = tostring(err)
              warn_once("lightning_invoke", "额外触发排雷失败：" .. tostring(err))
              break
          end
      end
      return nil
  end

  -- ★★ v10.2：现役落雷的「一帧只扫一次」统计 ★★
  --   同屏上限与最小间距都要数 Main.projectile 里的 1091 号弹幕，而那是 1000 个槽位，
  --   很贵 —— 所以每帧只扫一次并缓存在 mem 里：
  --     · li_base = 扫描那一刻的现役落雷数
  --     · li_add  = 本帧已经被我们放行、但扫描时还不存在的落雷数（见 bolt_mark）
  --     · li_pts  = 现役落雷坐标（格），只在开了「最小间距」时才收集
  --   ★ 一个槽位都读不到时一律降级为「数不出来」＝不拦，绝不误拦落雷。
  local function bolt_frame_prep()
      if mem.li_at == stats.frames then return end
      mem.li_at = stats.frames
      mem.li_base, mem.li_add, mem.li_pts = nil, 0, nil
      local li = P.lightning
      if not li or not (li.cap_on or li.dist_on) then return end
      if not (F.proj_type and F.proj_active) then return end
      local arr = get_object("main_projectile")
      if not arr then return end
      local n, readable = 0, 0
      local pts = (li.dist_on and F.proj_pos) and {} or nil
      for i = 0, MAX_PROJ - 1 do
          local oka, p = pcall(patch.array_at, arr, i)
          if oka and p and type(p) ~= "number" then
              readable = readable + 1
              if fget("proj_active", p) == true and fget("proj_type", p) == BOLT_TYPE then
                  n = n + 1
                  if pts then
                      local px, py = fget_vec2("proj_pos", p)
                      if type(px) == "number" and type(py) == "number" then
                          pts[#pts + 1] = px / 16.0
                          pts[#pts + 1] = py / 16.0
                      end
                  end
              end
          end
      end
      if readable == 0 then return end          -- 读不到 = 数不出来（保持 nil）
      if li.cap_on then mem.li_base = n end
      if pts then mem.li_pts = pts end
  end

  -- 现役落雷数（含本帧已放行的）；nil = 数不出来
  local function bolt_count()
      if type(mem.li_base) ~= "number" then return nil end
      return mem.li_base + (mem.li_add or 0)
  end

  -- 与已有落雷的距离是否小于 tiles 格（用平方比较，不开方）
  local function bolt_too_close(x, y, tiles)
      local pts = mem.li_pts
      if type(pts) ~= "table" then return false end
      local lim2 = tiles * tiles
      for i = 1, #pts, 2 do
          local dx = pts[i] - x
          local dy = pts[i + 1] - y
          if dx * dx + dy * dy < lim2 then return true end
      end
      return false
  end

  -- 放行一根落雷时记账：上限与间距都要把「本帧即将生成的」算进去
  local function bolt_mark(x, y)
      local li = P.lightning
      if not li or not (li.cap_on or li.dist_on) then return end
      mem.li_add = (mem.li_add or 0) + 1
      if type(mem.li_pts) == "table" and type(x) == "number" and type(y) == "number" then
          mem.li_pts[#mem.li_pts + 1] = x
          mem.li_pts[#mem.li_pts + 1] = y
      end
  end

  -- ★★ v10.1 / v10.2：满屏落雷 ★★
  --   原版真正生成落雷的是 4 参 TrySpawnLightningBolt(List<Rectangle>,int,int,ref bool)，
  --   它内部有「同一名玩家 800 像素（50 格）内已有落雷就 return false」的去重；而它的第一个
  --   参数是 List<Rectangle>、第四个是 ref bool —— **本加载器的钩子只支持标量参数，挂不上**
  --   （同 30 节对晶塔结构体参数的结论）。所以那道 800 像素限制改不了，只能绕：
  --   本项直接调 **2 参** WorldGen.TrySpawnLightningBolt(x, y)，它没有那套去重，
  --   于是可以在玩家左右 ±90 格（约一屏宽）横向铺开若干个落点。
  --   落点取「该列第一个实心方块的正上方」：与原版一样，雷劈在地面 / 屋顶上。
  local SPREAD_TILES = 90
  local function local_tile()
      local arr = get_object("player")
      if not arr then return nil end
      local ok, p = pcall(patch.array_at, arr, my_player_index())
      if not ok or not p or type(p) == "number" then return nil end
      if not F.position then return nil end
      local px, py = fget_vec2("position", p)
      if type(px) ~= "number" or type(py) ~= "number" then return nil end
      return math.floor(px / 16), math.floor(py / 16)
  end
  local function strike_y(x, my, y0)
      if not M.wg_solid_tile then return nil end
      local y = math.floor(tonumber(y0) or 20)
      if y < 2 then y = 2 end
      local lim = my - 60
      while y < lim do
          local ok, solid = pcall(patch.invoke, M.wg_solid_tile, x, y, false)
          if not ok then return nil end
          if solid == true then return y - 1 end
          y = y + 1
      end
      return nil
  end
  spread_bolts = function()
      local li = P.lightning
      if not li or not li.spread_on or li.block then return end
      if not ready or not M.try_bolt then return end
      if not may_write() then return end
      local mx, my = fget("max_tiles_x"), fget("max_tiles_y")
      if type(mx) ~= "number" or type(my) ~= "number" then return end
      local px, py = local_tile()
      if not px then return end
      local used = {}      -- ★ v10.2：同一条竖线上不叠第二道雷
      for _ = 1, li.spread do
          local x = px + math.random(-SPREAD_TILES, SPREAD_TILES)
          if x < 20 then x = 20 end
          if x > mx - 21 then x = mx - 21 end
          if not used[x] then
              used[x] = true
              local sy = strike_y(x, my, py - 12)
              if sy then
                  fl.li_invoke = true
                  local ok = invoke_checked(M.try_bolt, 2, x, sy)
                  fl.li_invoke = false
                  if ok then
                      LI.hits = LI.hits + 1
                      dcount(LI, "满屏落雷", 1)
                  else
                      LI.errs = LI.errs + 1
                      LI.last_err = "满屏落雷调用失败"
                      break
                  end
              end
          end
      end
  end

  -- ③ 第二道闸：真正落雷（原版 4 参重载最后就是调它；本模组的一键劈雷 / 满屏落雷也走它）
  --   ★★ v10.2：「同时存在的落雷上限」在这里对**所有来源**生效 ★★
  --     旧版函数开头就写「if fl.li_invoke then return nil end」，而本模组自己的额外补雷与
  --     满屏落雷正是带着 fl.li_invoke 进来的 —— 于是上限只拦得住原版自然落雷，玩家一开
  --     满屏落雷就等于把上限彻底关掉了（这正是「同屏雷击上限改不动」的原因）。
  --     现在只有一键页「手动劈雷」用的 fl.li_force 才全放行。
  --   ★ v10.2 新增：「两道落雷的最小间距」也在这一道闸上判（自然雷与满屏雷都管）。
  local function on_try_bolt(inst, args)
      if not ready then return nil end
      if fl.li_force then return nil end             -- 手动一键：禁止 / 上限 / 间距都不拦
      local li = P.lightning
      if not li then return nil end
      if li.block then
          if not may_write() then return nil end
          LI.hits = LI.hits + 1
          dcount(LI, "落雷拦截", 1)
          return true
      end
      if li.cap_on or li.dist_on then
          bolt_frame_prep()
          local x = args and tonumber(args[1]) or nil
          local y = args and tonumber(args[2]) or nil
          if li.cap_on then
              local n = bolt_count()
              if type(n) == "number" then
                  if n >= li.max_bolts then
                      if not may_write() then return nil end
                      LI.hits = LI.hits + 1
                      dcount(LI, "上限拦截", 1)
                      return true
                  end
              else
                  warn_once("li_cap_nocount", "同时落雷上限：读不到 Main.projectile / Projectile 字段，"
                      .. "本项设置无法生效（其余雷击功能不受影响）")
                  dcount(LI, "上限-数不出来", 1)
              end
          end
          if li.dist_on and x and y then
              if bolt_too_close(x, y, li.min_dist) then
                  if not may_write() then return nil end
                  LI.hits = LI.hits + 1
                  dcount(LI, "间距拦截", 1)
                  return true
              end
          end
          if x and y then bolt_mark(x, y) end
      end
      return nil
  end

  -- ④ 屏幕闪光 / 雷声：只在「禁止雷击」时一起关掉
  local function on_new_lightning(inst, args)
      if not ready or fl.li_invoke or fl.li_force then return nil end   -- ★ 一键「闪光雷声」放行
      local li = P.lightning
      if not li or not li.block then return nil end
      if not may_write() then return nil end
      LI.hits = LI.hits + 1
      dcount(LI, "闪光雷声拦截", 1)
      return true
  end

  -- ★ v9：落雷弹幕 ai[idx] 的读 / 写（手机版内联结构体 + 桌面端托管数组两条路）
  local function bolt_ai_get(inst, idx)
      local f = F.proj_ai
      if not f or not inst then return nil end
      if mod.platform == "android" then
          local okr, raw = pcall(patch.get_field_raw, f, inst, 12)
          if not okr or type(raw) ~= "string" or #raw < (idx + 1) * 4 then return nil end
          local okv, v = pcall(string.unpack, "<f", raw, idx * 4 + 1)
          if not okv then return nil end
          return v
      end
      local arr = fget("proj_ai", inst)
      if not arr then return nil end
      local oka, v = pcall(patch.array_at, arr, idx, "float")
      if not oka then return nil end
      return v
  end

  local function bolt_ai_set(inst, idx, v)
      local f = F.proj_ai
      if not f or not inst then return false end
      if mod.platform == "android" then
          local okr, raw = pcall(patch.get_field_raw, f, inst, 12)
          if not okr or type(raw) ~= "string" or #raw < 12 then return false end
          local okp, bytes = pcall(string.pack, "<f", v)
          if not okp or type(bytes) ~= "string" or #bytes ~= 4 then return false end
          local out = raw:sub(1, idx * 4) .. bytes .. raw:sub(idx * 4 + 5)
          local oks = pcall(patch.set_field_raw, f, inst, out)
          return oks and true or false
      end
      local arr = fget("proj_ai", inst)
      if not arr or not patch.array_set then return false end
      local oks, r = pcall(patch.array_set, arr, idx, v, "float")
      return oks and r ~= false
  end

  -- ⑤ ★ v9：AI_203 的 postfix —— 按「起手到劈击的时长倍率」增减 ai[1] 的每帧推进量。
  --    每帧只跑在落雷弹幕上（不是每帧几百次的通用热路径）；倍率 = 100% 时一行都不执行。
  local function on_bolt_ai(inst, args)
      if not ready or not inst then return nil end
      local li = P.lightning
      if not li or not li.windup_on then return nil end
      if not F.proj_ai or not F.proj_type then return nil end
      if fget("proj_type", inst) ~= BOLT_TYPE then return nil end
      if not may_write() then return nil end
      local cur = bolt_ai_get(inst, 1)
      if type(cur) ~= "number" or cur < 0 or cur > AI203_LIFE then return nil end
      -- ★★ v10：倍率方向修反 ★★
      --   本项是「起手到劈击的**时长**倍率」：界面 200% 应当是「时长 x2」= 更慢。
      --   旧版写 cur + (倍率 - 1)（把倍率当速度用）→ 200% 时每帧 +2 → 120 帧劈完 = 更快，
      --   用户实测「调高 → 落雷加快」正是这个倒数 / 单位反。
      --   正确：每帧推进量 = 1 / 倍率。200% → 净 +0.5 → 480 帧；50% → 净 +2 → 120 帧。
      local mult = li.windup
      if type(mult) ~= "number" or mult <= 0 then return nil end
      local want = cur + (1 / mult - 1)
      if want < 0 then want = 0 end
      if want > AI203_LIFE then want = AI203_LIFE end
      if want == cur then return nil end
      if bolt_ai_set(inst, 1, want) then
          LI.hits = LI.hits + 1
          dcount(LI, "雷击时长调整", 1)
      else
          LI.errs = LI.errs + 1
          LI.last_err = "写不回落雷弹幕的 ai[1]"
          warn_once("lightning_ai_set", "雷击时长：写不回落雷弹幕的 ai[1]（本帧跳过）")
      end
      return nil
  end

  LI = domain({
      name = "雷击",
      fields = function(T)
          -- ★ v9：数落雷弹幕要用到的三件套（全是 public、非 const 的普通字段/数组字段）
          register("main_projectile", T.MAIN, "projectile", "object")
          register("proj_active", T.PROJECTILE, "active", "bool")
          register("proj_type", T.PROJECTILE, "type", "int32")
          -- ai 是 float[]（桌面）/ Float_FixedArray_3（手机内联结构体）→ 只当 object 取字段指针
          register("proj_ai", T.PROJECTILE, "ai", "object")
          -- ★ v10.2：落雷坐标（Vector2 实例字段）—— 「两道落雷的最小间距」要用
          register("proj_pos", T.PROJECTILE, "position", "object")
      end,
      methods = function(T)
          M.new_lightning = T.MAIN and find_method(T.MAIN, "NewLightning", 2)
          -- ★ v7：真正劈人的那条链（private static 也能取到；口径见文件头）
          M.storm_lightning = T.WORLDGEN and find_method(T.WORLDGEN, "SpawnStormLightning", 0)
          M.try_bolt = T.WORLDGEN and find_method(T.WORLDGEN, "TrySpawnLightningBolt", 2)
          -- ★ v9：落雷弹幕的 AI（0 参实例 private；只装在落雷这一条支线上）
          M.bolt_ai203 = T.PROJECTILE and find_method(T.PROJECTILE, "AI_203_StormLightning", 0)
          if T.WORLDGEN and not M.storm_lightning then
              mod.error("找不到 WorldGen.SpawnStormLightning()：雷击相关功能全部停用"
                  .. "（可复核：grep -P '^Terraria\\.WorldGen\\tSpawnStormLightning\\t' "
                  .. "参考库/符号/官方源码-方法.tsv）")
          end
          if T.PROJECTILE and not M.bolt_ai203 then
              mod.warn("找不到 Projectile.AI_203_StormLightning()："
                  .. "「雷击·起手到劈击的时长倍率」停用（其余雷击功能不受影响）")
          end
      end,
      install = function()
          safe_hook(M.storm_lightning, { prefix = on_spawn_storm, postfix = on_spawn_storm_post },
              "WorldGen.SpawnStormLightning")
          safe_hook(M.try_bolt, { prefix = on_try_bolt }, "WorldGen.TrySpawnLightningBolt(int,int)")
          safe_hook(M.new_lightning, { prefix = on_new_lightning }, "Main.NewLightning(bool,bool)")
          safe_hook(M.bolt_ai203, { postfix = on_bolt_ai },
              "Projectile.AI_203_StormLightning（v9：雷击起手到劈击的时长）")
      end,
      reset = function()
          mem.li_at, mem.li_base, mem.li_add = nil, nil, 0
          mem.li_pts, mem.li_spread_at = nil, nil
      end,
  })
end



-- ============================================================================
-- 45 · 树木生长（WorldGen.GrowTree）
-- ----------------------------------------------------------------------------
-- 取证（Terraria 1.4.5.8 手机版 + PC 源码，行号即出处）：
--   · 树苗的逐帧生长在 `WorldGen.UpdateWorld` 的逐图格扫描里，最终落到
--     `GrowTree(i, j)` —— 这是普通树木生长的唯一出口，在它的 prefix 返回
--     `true, false` 就等于「这次没长成」。
--   · 宝石树 / 樱花 / 柳树 / 灰烬树走的是
--     `GrowTreeWithSettings(int, int, GrowTreeSettings)`：第三个参数是**结构体**。
--     按本工作区红线（带结构体参数的方法 libffi 传不了、实机崩过），这里**不挂它** ——
--     所以本功能只作用于普通树木，设置项描述里已写明。
--   · 「生长速度」做不到：加速的门 `genRand.Next(num5) == 0` 是 UpdateWorld 里的局部量，
--     与「蔓延速度」同一个结论 —— Lua 层没有可挂钩的字段。
--   · 「放宽生长条件」也做不到：条件判定全在 GrowTree 函数体内部，没有可改的字段。
--
-- ★★ v10 崩溃修复（这条对应「第一次进世界 / 新建世界偶现崩溃，并导致世界消失」）★★
--   旧版在 `setup()` 阶段就无条件挂上 GrowTree 的 prefix。但 GrowTree **不只在主线程被调**：
--     PC 1.4.5.8 WorldGen.cs:24268 —— `OverGrownDungeon()`（地牢生成那一趟）里直接调
--     `GrowTree(j, k)`；这个 pass 由 :26070 的 AddGenerationPass 在**世界生成线程**上跑。
--   ⇒ 生成新世界时 worker 线程会进 Lua（`dcount` / `P.tree` / `may_write` 全是 Lua 操作），
--     与主线程共用一个 lua_State，且是「未附着 IL2CPP GC 的原生线程去调托管方法」——
--     两条都是原生层内存踩踏 / 直接 abort 的形状，pcall 拦不住。
--   ⇒ 现在改成**只在进世界之后安装、回主菜单就摘掉**：
--     世界生成只可能发生在主菜单（那时钩子不存在），进世界后的 GrowTree 全在主线程的
--     逐格世界更新里。安装/摘除挂在功能域的 world / reset 两个阶段（都是主线程）。
-- ============================================================================

local tree_hook = nil          -- 已安装的 WorldGen.GrowTree 钩子句柄（nil = 没装）

local function on_grow_tree(inst, args)
    if not ready or not P.tree.block then return end
    if not may_write() then return end
    stats.tree_blocks = (stats.tree_blocks or 0) + 1
    return true, false                 -- GrowTree 返回 false = 这一次没长成
end

local function tree_hook_on()
    if tree_hook or not M.grow_tree then return end
    tree_hook = safe_hook(M.grow_tree, { prefix = on_grow_tree },
        "WorldGen.GrowTree（★ v10：只在进世界之后安装 —— 它也会在世界生成线程上被调到）")
end

local function tree_hook_off()
    if not tree_hook then return end
    local h = tree_hook
    tree_hook = nil
    pcall(function() h:remove() end)
end

domain({
    name = "树木生长",
    methods = function(T)
        -- ★ v4：1.4.5.8 手机版是 GrowTree(int i, int y, int treeHeightAddon, bool ignoreWalls)
        --   —— 4 个形参全是标量（旧代码按 2 参找，句柄取不到，靠 find_method 的兜底才勉强装上）。
        M.grow_tree = T.WORLDGEN and find_method(T.WORLDGEN, "GrowTree", 4)
    end,
    -- ★ v10：**不再在 install 里挂钩子**（理由见文件头）。world 阶段只在「已进世界」时被派发。
    world = function()
        if not ready then return end
        tree_hook_on()
    end,
    reset = function()
        -- 回主菜单 / 换世界：立刻摘掉（下一次进世界再装）
        tree_hook_off()
    end,
})



-- ============================================================================
-- 50 · 生物分类与属性倍率（v4：改挂 NPC.NewNPC 的 postfix）
-- ----------------------------------------------------------------------------
-- ★ 为什么换钩子：1.4.5.8 手机版唯一的初始化点是
--   `NPC.SetDefaults(int Type, NPCSpawnParams spawnparams)` —— 第 2 个形参是**结构体**，
--   本加载器的 hook 只支持标量参数（05 §4.3），这个钩子装不上（旧版正是靠
--   find_method 的「按名字兜底」才勉强挂上，实际不生效）。
--   现在改成复用 `NPC.NewNPC(source, X, Y, Type, ...)`（10 个全是标量/引用）的 postfix ——
--   它由 60_spawn.lua 装钩子并通过 call_domains("npc_new_postfix") 派发，本域只登记阶段函数，
--   所以不多占钩子位、也不会和刷怪那套打架。postfix 的 result 就是新 NPC 在 Main.npc 里的下标。
-- 幂等性靠「同类型生物的原版基准值 + 本模组上次写入值」两个记忆值做三态判定（plan_value）：
--   cur == base → 没人动过，写 base × 倍率；
--   cur == last → 是我们自己缩放过的（同一个实例重复调用），什么都不做；
--   其它        → 第三方改过，以它为新基准。
-- ★ v1.0.0 在这里翻过一次车：写入成功后忘了记 last，第二次 SetDefaults 把我们的值
--   当成「第三方改过的值」再乘一遍 → 属性翻倍。测试里有一条断言专门盯着它。
-- ============================================================================

local ATTR_SPEC = {
    -- key 是 NPC 的字段名；mult 是 P.attr.cat[cat] 里的键
    { key = "lifeMax",         mult = "life",    lo = 1,    hi = 2000000, float = false },
    { key = "damage",          mult = "damage",  lo = 0,    hi = 100000,  float = false },
    { key = "defense",         mult = "defense", lo = 0,    hi = 100000,  float = false },
    { key = "knockBackResist", mult = "kb",      lo = 0,    hi = 2,       float = true },
    { key = "value",           mult = "value",   lo = 0,    hi = 1e9,     float = true },
    { key = "scale",           mult = "scale",   lo = 0.05, hi = 12,      float = true },
}

-- 三态取值。返回 (目标值, 记录)；目标值为 nil 表示「这一帧不用动手」。
local function plan_value(rec, key, cur, mult, lo, hi)
    if mult == 1 then return nil end
    local st = rec[key]
    if not st then
        st = { base = cur }
        rec[key] = st
    end
    local target
    if cur == st.base then
        target = st.base * mult
    elseif st.last ~= nil and cur == st.last then
        return nil                      -- 已经是本模组缩放后的值（同一个实例的重复调用）
    else
        st.base, st.last = cur, nil     -- 被别的模组 / 原版改成了第三个值：以它为新基准
        target = cur * mult
    end
    if target < lo then target = lo end
    if target > hi then target = hi end
    return target, st                   -- 第二个返回值：写入成功后要把 last 记回去
end

-- 分类规则：只看生物自己的字段，不查表（查表要内置几千个编号，体积换不来多少精度）。
-- 归错了可以用设置里的「生物分类覆盖表」手工纠正，所以这里只要「大部分对」即可。
--   覆盖表 > Boss > 友好 / 被动 > 史莱姆(AI 1) > 飞行 > 地面 > 无重力 > 其它
local function classify(inst, ty)
    local ov = P.attr.override
    if ov and ty and ov[ty] ~= nil then return ov[ty], "分类覆盖表" end
    if fget("boss", inst) == true then return CAT_BOSS, "boss 字段" end
    local ai = fget("aiStyle", inst)
    if type(ai) ~= "number" then ai = -1 end
    if ai == 7 or fget("townNPC", inst) == true or fget("friendly", inst) == true then
        return CAT_PASSIVE, "友好 / 被动"
    end
    if ai == 1 then return CAT_SLIME, "aiStyle 1" end
    if ai == 2 or ai == 5 or ai == 22 or ai == 24 then return CAT_FLY, "aiStyle 飞行" end
    if ai == 3 or ai == 6 or ai == 8 or ai == 9 or ai == 16 then return CAT_GROUND, "aiStyle 地面" end
    if fget("noGravity", inst) == true then return CAT_FLY, "无重力" end
    return CAT_OTHER, "其它"
end

local function apply_npc_attrs(inst, ty, cat)
    local a = P.attr.cat[cat]
    if not a then return end
    local rec = type_base[ty]
    if not rec then
        rec = {}
        type_base[ty] = rec
    end

    for i = 1, #ATTR_SPEC do
        local spec = ATTR_SPEC[i]
        local mult = a[spec.mult]
        if mult and mult ~= 1 then
            local cur = fget(spec.key, inst)
            if type(cur) == "number" and cur > 0 then
                local target, st = plan_value(rec, spec.key, cur, mult, spec.lo, spec.hi)
                if target ~= nil then
                    if spec.float then
                        if math.abs(target - cur) > 1e-4 and fset(spec.key, inst, target) then
                            st.last = target
                        end
                    else
                        target = math.floor(target + 0.5)
                        if target ~= cur and fset(spec.key, inst, target) then
                            st.last = target
                            -- 生命上限改了，当前血量要按同比例跟过去（新生物本来是满血）
                            if spec.key == "lifeMax" then
                                local cur_life = fget("life", inst)
                                if type(cur_life) == "number" then
                                    local nl = math.floor(cur_life * target / cur + 0.5)
                                    if nl < 1 then nl = 1 end
                                    if nl > target then nl = target end
                                    if nl ~= cur_life then fset("life", inst, nl) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- NPC.NewNPC 的 postfix：result = 新生物在 Main.npc 里的下标（200 = 原版「没有空位」）
local function on_new_npc(inst, args, result)
    if not ready then return end
    -- 默认配置下这里第一行就返回：不做任何反射调用
    if not (P.attr.active or P.spawn.filter) then return end
    -- ★ v4 主机总闸：作为客机（netMode=1）时不写任何生物属性，避免与服务器不同步
    if not may_write() then return end
    local npc = npc_by_index(result)
    if not npc then return end
    local ty = args and args[4]                 -- NewNPC(source, X, Y, Type, ...)
    if type(ty) ~= "number" or ty < 1 or ty > 2000 then ty = fget("npctype", npc) end
    if type(ty) ~= "number" or ty < 0 then return end

    local cat, why = classify(npc, ty)
    if type_cat[ty] ~= cat then
        type_cat[ty] = cat
        stats.npc_seen = stats.npc_seen + 1
        -- 详细日志：给「生物分类覆盖表」提供编号 → 归类的对应关系
        verbose(string.format("首次归类：生物编号 %d → %s（依据 %s）", ty,
            CAT_LABEL[cat] or "?", why))
    end

    if not P.attr.active then return end
    if cat == CAT_PASSIVE and not P.attr.friendly then return end
    local ok, err = pcall(apply_npc_attrs, npc, ty, cat)
    if not ok then warn_once("attr", "生物属性倍率应用失败：" .. tostring(err)) end
end

domain({
    name = "生物属性",
    fields = function(T)
        register("aiStyle", T.NPC, "aiStyle", "int32")
        register("boss", T.NPC, "boss", "bool")
        register("townNPC", T.NPC, "townNPC", "bool")
        register("friendly", T.NPC, "friendly", "bool")
        register("noGravity", T.NPC, "noGravity", "bool")
        register("lifeMax", T.NPC, "lifeMax", "int32")
        register("life", T.NPC, "life", "int32")
        register("damage", T.NPC, "damage", "int32")
        register("defense", T.NPC, "defense", "int32")
        register("knockBackResist", T.NPC, "knockBackResist", "float")
        register("value", T.NPC, "value", "float")
        register("scale", T.NPC, "scale", "float")
        register("npctype", T.NPC, "type", "int32")
    end,
    -- ★ v4：不再自己装钩子。NPC.SetDefaults 的第 2 个形参是结构体，挂不上；
    --   改由 60_spawn.lua 的 NPC.NewNPC postfix 派发（同一个方法只允许一个钩子主人）。
    npc_new_postfix = on_new_npc,
})


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 57 · 渔夫：任务立刻刷新 / 奖励份数 / 任务鱼堆叠 —— v5 按「从未修过」重写
  -- ----------------------------------------------------------------------------
  -- ★★ 为什么旧版无效（三段，全部可复核）★★
  --
  -- ① 【v3】挂在 Player.GetAnglerReward 的 postfix 上 —— 时机太早。
  --    PC `Main.NPCChatText_DoAnglerQuest()`（Main.cs:40969-41004）的顺序是：
  --      先 FindItem(任务鱼) → 扣一条 → anglerQuestsFinished++ →
  --      `player.GetAnglerReward(...)`（第 40987 行）→ …… → **之后**才
  --      `anglerQuestFinished = true;`（第 40993 行）→ `anglerWhoFinishedToday.Add(name)`。
  --    在 GetAnglerReward 那一刻调 AnglerQuestSwap()，紧接着就被原版那一行
  --    `anglerQuestFinished = true` 顶回来 → 任务没换，用户看到的就是「无效」。
  --
  -- ② 【v4】改挂 Main.NPCChatText_DoAnglerQuest 的 postfix —— 只覆盖「点按钮」这一条路。
  --    手机版这条路是 NPC 交互系统的一个 UI 回调：
  --      `Terraria.GameContent.NPCInteractions.Actions.AnglerQuest.Interact()`
  --      （手机版源码 `Assembly-CSharp/Terraria.GameContent/NPCInteractions.cs:158/187`）
  --    它只在「玩家点渔夫的任务按钮」的瞬间触发一次。于是：
  --      · 完成标志由**别的**路径置位（联机客机走 NetMessage.SendData(75)、
  --        服务端/主机侧置位）时，这个 postfix 一次都不会命中；
  --      · 而这正是最需要「立刻刷新」的场景。
  --    更关键的是 v4 **没有任何命中计数**：钩子没装上、装上了没命中、命中了被原版顶掉
  --    这三种情况在用户眼里完全一样 —— 这正是「功能无效」最难定位的根源。
  --
  -- ③ 手机版 `Main.anglerQuestFinished` 是**属性**，不是字段！
  --      字段/属性表：Terraria.Main  anglerQuestFinished  bool  public static [属性]  是  get; set;
  --      dump.cs:51695（属性） / 53116（get_anglerQuestFinished） / 53119（set_...）
  --      真正的存储搬到了**按本地用户**的 `LocalUserGameState.anglerQuestFinished`（bool, 0x196，
  --      dump.cs:33111）。所以任何「用 get_field 读/写这个标志位」的兜底写法在手机版必然拿到 nil；
  --      要读它只能走 0 参静态属性 getter，要清它只能走 1 参属性 setter。
  --
  -- ★ v5 做法（每帧轮询为主路，聊天钩子为第二路，两路各自计数）：
  --   参考 `旧模组-CPP-123/渔夫任务刷新最好.cpp`：它 hook `Player.ResetEffects`（每帧），
  --   在 `CheckAnglerQuest()` 里 `g_pGetAnglerQuestFinished->Call(nullptr, 0)`，
  --   为 true 就 `g_pAnglerQuestSwap->Call(nullptr, 0)` —— 一帧内完成
  --   「交任务 → 标志位 true → 立刻换新任务」。
  --   我们这边：`Main.get_anglerQuestFinished()`（0 参静态属性 getter，成本可忽略）
  --   → true 就 `Main.AnglerQuestSwap()`。挂在 40_world 派发的「world」每帧阶段上，
  --   由独立开关「完成即刷新任务」控制（默认关，默认路径上一次 invoke 都不发）。
  --   兜底：swap 句柄取不到时走 `set_anglerQuestFinished(false)` + 清
  --   `Main.anglerWhoFinishedToday`（List::Clear）+ 从 `Main.anglerQuestItemNetIDs` 里抽一个新任务。
  --   ★ 客机限制（原版行为，不是我们的 bug）：`AnglerQuestSwap()` 第一行就是
  --     `if (netMode == 1) return;` —— 作为客机进别人世界时换不了任务，说明里已写明。
  --
  -- 符号证据（全部已对 参考库/符号/官方源码-{方法,字段}.tsv 核实）：
  --   Terraria.Main	get_anglerQuestFinished	0	→ bool	public static（属性）
  --   Terraria.Main	set_anglerQuestFinished	1	bool
  --   Terraria.Main	AnglerQuestSwap	0	void	public static
  --   Terraria.Main	NPCChatText_DoAnglerQuest	0	void	public static
  --   Terraria.Main	anglerWhoFinishedToday	List<string>	0x658
  --   Terraria.Main	anglerQuest	int	0x660
  --   Terraria.Main	anglerQuestItemNetIDs	int[]	0x10B8
  --   Terraria.Player	GetAnglerReward	2	NPC, int（**实例**方法）
  --   Terraria.Item	SetDefaults	2	int, ItemVariant（★ 手机版是 2 参，不是 3 参！）
  -- ============================================================================

  local in_reward = false               -- 递归保护：额外奖励自己也会跑进这个 postfix
  local AN          -- ★ 前向声明：下面几个回调体里要引用它

  -- ---------------------------------------------------------------- ① 每帧轮询（主路）
  local function poll_angler()
      if not ready or not P.angler.instant then return end
      if not may_write() then return end
      -- 手机版是属性：只能走 0 参静态 getter（用 get_field 读必然 nil）
      if not M.get_angler_finished then return end
      local ok, fin = pcall(patch.invoke, M.get_angler_finished)
      if not ok then
          AN.errs = AN.errs + 1
          AN.last_err = "get_anglerQuestFinished 调用失败"
          return
      end
      if fin ~= true then return end
      AN.hits = AN.hits + 1
      dcount(AN, "轮询命中", 1)
      -- 主路：原版换任务
      if M.angler_swap then
          local ok2 = invoke_checked(M.angler_swap, 0)
          if ok2 then
              dcount(AN, "轮询刷新", 1)
              verbose("渔夫任务已刷新（每帧轮询属性 getter）")
              return
          end
      end
      -- 兜底：setter 清标志 + 清今日名单 + 抽新任务编号
      if M.set_angler_finished then
          local ok3 = invoke_checked(M.set_angler_finished, 1, false)
          if ok3 then dcount(AN, "兜底清标志", 1) end
      end
      local lst = F.angler_finished_today and fget("angler_finished_today")
      if lst and patch.list_clear then
          local okc = pcall(patch.list_clear, lst)
          if okc then dcount(AN, "兜底清名单", 1) end
      end
      local ids = F.angler_quest_ids and get_object("angler_quest_ids")
      if ids then
          local okn, n = pcall(patch.array_length, ids)
          if okn and type(n) == "number" and n > 0 then
              local pick = math.random(0, n - 1)
              local okv, v = pcall(patch.array_at, ids, pick, "int32")
              if okv and type(v) == "number" and v > 0 then
                  fset("angler_quest", nil, pick)
                  dcount(AN, "兜底抽新任务", 1)
              end
          end
      end
  end

  -- ---------------------------------------------------------------- ② 聊天钩子（第二路）
  local function on_angler_done(inst, args)
      if not ready or not P.angler.instant then return end
      if not may_write() then return end
      if not M.angler_swap then return end
      local ok, err = invoke_checked(M.angler_swap, 0)
      if not ok then
          AN.errs = AN.errs + 1
          AN.last_err = tostring(err)
          warn_once("angler_swap", "刷新渔夫任务失败：" .. tostring(err))
      else
          AN.hits = AN.hits + 1
          dcount(AN, "交任务即刷新", 1)
          verbose("渔夫任务已刷新（交任务即刷新）")
      end
  end

  -- ---------------------------------------------------------------- ③ 奖励份数
  -- Player.GetAnglerReward(NPC,int) 是**实例方法**，必须走 invoke_instance
  -- （instance 单独占一个槽位）。旧版用 invoke_checked 少传 instance 槽位 = 越界读栈。
  local function on_angler_reward(inst, args)
      if not ready or in_reward then return end
      if not P.angler.active then return end
      if not may_write() then return end
      if not args or not inst then return end
      local mult = P.angler.reward_mult
      if mult <= 1 or not M.angler_reward then return end

      local angler, quest_item = args[1], args[2]
      in_reward = true
      for _ = 2, mult do
          local ok, err = invoke_instance(M.angler_reward, inst, angler, quest_item)
          if not ok then
              AN.errs = AN.errs + 1
              AN.last_err = tostring(err)
              warn_once("angler_dup", "渔夫额外奖励失败：" .. tostring(err))
              break
          end
          AN.hits = AN.hits + 1
          dcount(AN, "额外奖励", 1)
      end
      in_reward = false
  end

  -- ---------------------------------------------------------------- ④ 任务鱼堆叠上限
  -- 任务鱼（2450~2488 / 4393 / 4394，见 Main.anglerQuestItemNetIDs）在原版是 uniqueStack：
  -- 一格只能放一条。这里在 Item.SetDefaults 的 postfix 里按编号放宽（手机版是 **2 参**：
  -- int Type, ItemVariant variant —— 旧 EFMod 参考文件里的 3 参是 PC 的旧签名，别照抄）。
  local quest_fish = {}          -- [物品编号] = true（进世界后从 anglerQuestItemNetIDs 现学）

  local function learn_quest_fish()
      if not F.angler_quest_ids then return end
      local ids = get_object("angler_quest_ids")
      if not ids then return end
      local ok, n = pcall(patch.array_length, ids)
      if not ok or type(n) ~= "number" or n <= 0 then return end
      quest_fish = {}
      for i = 0, n - 1 do
          local okv, v = pcall(patch.array_at, ids, i, "int32")
          if okv and type(v) == "number" and v > 0 then quest_fish[v] = true end
      end
      mem.fish_learned = true
      dcount(AN, "任务鱼编号", n)
  end

  local function on_item_setdefaults(inst, args, result)
      if not ready or not P.fish.active or not inst or not args then return end
      local ty = args[1]
      if type(ty) ~= "number" then return end
      if not mem.fish_learned then pcall(learn_quest_fish) end
      if not quest_fish[ty] then return end
      AN.hits = AN.hits + 1
      dcount(AN, "任务鱼放宽", 1)
      local want = P.fish.stack
      if fset_if("item_max_stack", inst, math.floor(want)) then
          dcount(AN, "改堆叠上限", 1)
      end
      -- ★ uniqueStack 是「一格只能一个」的开关，必须关掉才能叠
      if fset_if("item_unique_stack", inst, false) then
          dcount(AN, "关 uniqueStack", 1)
      end
  end

  AN = domain({
      name = "渔夫任务",
      fields = function(T)
          -- 属性背后的真实存储在本机取不到（LocalUserGameState 是按用户的），
          -- 这里只登记兜底路径要用的两个静态字段（都不是 const）
          register("angler_finished_today", T.MAIN, "anglerWhoFinishedToday", "object")
          register("angler_quest", T.MAIN, "anglerQuest", "int32")
          register("angler_quest_ids", T.MAIN, "anglerQuestItemNetIDs", "object")
          -- Item 侧（任务鱼堆叠）
          register("item_max_stack", T.ITEM, "maxStack", "int32")
          register("item_unique_stack", T.ITEM, "uniqueStack", "bool")
      end,
      methods = function(T)
          -- ★ 手机版是**属性**：必须取 get_/set_ 这对方法，不能取字段
          M.get_angler_finished = T.MAIN and find_method(T.MAIN, "get_anglerQuestFinished", 0)
          M.set_angler_finished = T.MAIN and find_method(T.MAIN, "set_anglerQuestFinished", 1)
          M.angler_swap = T.MAIN and find_method(T.MAIN, "AnglerQuestSwap", 0)
          M.angler_done = T.MAIN and find_method(T.MAIN, "NPCChatText_DoAnglerQuest", 0)
          M.angler_reward = T.PLAYER and find_method(T.PLAYER, "GetAnglerReward", 2)
          -- ★ 手机版 Item.SetDefaults 是 **2 参**（int Type, ItemVariant variant）
          M.item_setdefaults = T.ITEM and find_method(T.ITEM, "SetDefaults", 2)
          if T.MAIN and not M.get_angler_finished then
              mod.warn("找不到 Main.get_anglerQuestFinished（属性 getter）："
                  .. "「完成即刷新任务」的轮询主路不可用，只保留交任务钩子")
          end
      end,
      install = function()
          safe_hook(M.angler_reward, { postfix = on_angler_reward }, "Player.GetAnglerReward")
          safe_hook(M.angler_done, { postfix = on_angler_done },
              "Main.NPCChatText_DoAnglerQuest（第二路）")
          safe_hook(M.item_setdefaults, { postfix = on_item_setdefaults }, "Item.SetDefaults")
      end,
      -- ★ 主路：每帧轮询属性 getter（由 40_world 的 world 阶段派发）
      world = poll_angler,
      reset = function()
          quest_fish = {}
          mem.fish_learned = false
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do

  -- ============================================================================
  -- 60 · 分类刷怪：拦截与额外生成
  -- ----------------------------------------------------------------------------
  -- 挂钩思路（v1.0.0 定下来、没有更好的替代）：
  --   · NPC.SpawnNPC 是「自然刷怪」的唯一入口 → 只在它的 prefix/postfix 之间置一个窗口标志；
  --   · 窗口内的 NPC.NewNPC 才按类别决定「拦掉」还是「多刷几只」。
  --   · 拦掉用「prefix 返回 true, 200」——200 是原版 NewNPC 里表示「没有空位」的返回值，
  --     于是调用方会当成一次正常的失败，不会有人察觉异常。
  -- 类别来自 NPC.SetDefaults 阶段现场学出来的 type_cat（见 50_npc.lua）；没学到的类别一律放行。
  -- ============================================================================

  local SP          -- ★ 前向声明：多个回调体里要引用它（刷怪质量的诊断计数器）

  -- 只认「(source, X, Y, Type, ...)」这一种形参布局，并做一次合理性校验；
  -- 校验不过就整段跳过 —— 宁可少一个功能，也不拿不确定的实参去赌。
  local function spawn_args_ok(args)
      if not args then return nil end
      local x, y, ty = args[2], args[3], args[4]
      if type(x) ~= "number" or type(y) ~= "number" or type(ty) ~= "number" then return nil end
      if ty < 1 or ty > 2000 then return nil end
      if x < 0 or y < 0 or x > 200000 or y > 200000 then return nil end
      return ty
  end

  local function on_spawn_npc_prefix()
      if not ready then return end
      -- 客机上自然刷怪由服务器负责，本模组完全不介入
      if not may_write() then return end
      spawn_win.natural = true
      spawn_win.budget = P.spawn.dup_limit
  end

  local function on_spawn_npc_postfix()
      spawn_win.natural = false
      spawn_win.budget = 0
  end

  -- 返回 true 表示「这次生成应当被拦掉」
  local function blocked(ty, cat)
      local s = P.spawn
      if cat == CAT_BOSS and s.block_boss then return true end
      if cat == CAT_PASSIVE and s.block_passive then return true end
      local mult = s.cat[cat + 1]
      if mult == nil or mult >= 1 then return false end
      if mult <= 0 then return true end
      return math.random() >= mult
  end

  -- ★ v5：同屏敌怪硬上限。只数「敌对且非 Boss、非城镇 NPC、非友方」的存活生物，
  --   每帧最多数一次（mem.eh_frame 记帧号）。Boss / 城镇 NPC / 小动物永不计数，
  --   所以事件与 Boss 战不受影响；也绝不杀已经存在的怪，只是不再放新的进来。
  local function hostile_count()
      if mem.eh_frame == stats.frames then return mem.eh_count or 0 end
      mem.eh_frame = stats.frames
      local arr = get_object("npc")
      local n = 0
      if arr then
          local ok, len = pcall(patch.array_length, arr)
          if ok and type(len) == "number" then
              for i = 0, len - 1 do
                  local ok2, npc = pcall(patch.array_at, arr, i)
                  if ok2 and npc and valid_obj(npc) then
                      if fget("npc_active", npc) == true
                          and fget("boss", npc) ~= true
                          and fget("townNPC", npc) ~= true
                          and fget("friendly", npc) ~= true then
                          n = n + 1
                      end
                  end
              end
          end
      end
      mem.eh_count = n
      return n
  end

  local function on_new_npc_prefix(inst, args)
      if not may_write() then return end
      -- v3：先问别的功能域要不要拦（稀有生物倍率 < 100% 时按概率拦掉）
      local a, b = call_domains("npc_new_prefix", inst, args)
      if a ~= nil then return a, b end
      if not ready then return end
      -- ★ v5：同屏敌怪硬上限（独立于「刷怪参数」与「分类刷怪」，只拦自然刷怪窗口内的新生成）
      local sq = P.spawnq
      if sq and sq.cap > 0 and spawn_win.natural then
          local ty0 = spawn_args_ok(args)
          if ty0 then
              local c = type_cat[ty0]
              if c ~= CAT_BOSS and c ~= CAT_PASSIVE and hostile_count() >= sq.cap then
                  SP.hits = SP.hits + 1
                  dcount(SP, "硬上限拦截", 1)
                  return true, 200
              end
          end
      end
      if not spawn_win.natural or not P.spawn.filter then return end
      local ty = spawn_args_ok(args)
      if not ty then return end
      local cat = type_cat[ty]
      if cat == nil then return end                  -- 还没学到这个类别 → 放行
      if blocked(ty, cat) then
          stats.blocks = stats.blocks + 1
          return true, 200                           -- 200 = 原版的「没有空位」→ 这次不生成
      end
  end

  local function on_new_npc_postfix(inst, args, result)
      -- v3：先让别的功能域做额外生成（稀有生物倍率 > 100% 时多刷几只），配额共享
      call_domains("npc_new_postfix", inst, args, result)
      if not ready or spawn_win.in_dup or not spawn_win.natural or spawn_win.budget <= 0 then return end
      if not may_write() then return end
      if not P.spawn.filter or not M.new_npc then return end
      if result == 200 then return end               -- 原方法自己就失败了，别再补
      local ty = spawn_args_ok(args)
      if not ty then return end
      local cat = type_cat[ty]
      if cat == nil then return end
      local mult = P.spawn.cat[cat + 1]
      if mult == nil or mult <= 1 then return end

      local extra = math.floor(mult + 0.5) - 1
      if extra > spawn_win.budget then extra = spawn_win.budget end
      if extra <= 0 then return end

      local n = ARG.new_npc
      if type(n) ~= "number" or n < 4 or n > 16 then return end

      local call, ox, oy = {}, args[2], args[3]
      for i = 1, n do call[i] = args[i] end
      spawn_win.in_dup = true
      for _ = 1, extra do
          call[2] = ox + math.random(-24, 24)
          call[3] = oy + math.random(-16, 16)
          local ok, err = invoke_checked(M.new_npc, n, table.unpack(call, 1, n))
          if not ok then
              warn_once("dup", "额外生成失败：" .. tostring(err))
              break
          end
          spawn_win.budget = spawn_win.budget - 1
          stats.dups = stats.dups + 1
          if spawn_win.budget <= 0 then break end
      end
      spawn_win.in_dup = false
  end

  -- ★ v5：怪物 AI 简化（性能开关）。钩 NPC.UpdateNPC(int) 的 prefix，
  --   只在「离本地玩家很远」且「不是 Boss / 城镇 NPC / 小动物 / 友方」时跳过这一帧的 AI。
  --   为什么用本地玩家而不是全部玩家：读 255 个玩家坐标会让这个「性能开关」比不做还慢；
  --   单机与「自己当房主」场景下本地玩家就是唯一观者，多人才有差异（README 已写明）。
  local function on_npc_update(inst, args)
      if not ready or not inst then return end
      local sq = P.spawnq
      if not sq or not sq.ai then return end
      if fget("boss", inst) == true or fget("townNPC", inst) == true
          or fget("friendly", inst) == true then return end
      local arr = get_object("player")
      if not arr then return end
      local my = my_player_index()
      local okp, p = pcall(patch.array_at, arr, my)
      if not okp or not p or not valid_obj(p) then return end
      local px, py = fget_vec2("position", p)
      local nx, ny = fget_vec2("npc_pos", inst)
      if not (px and nx) then return end
      local dx, dy = nx - px, ny - py
      local d2 = dx * dx + dy * dy
      local r = sq.ai_dist or 2400
      if d2 < r * r then return end
      SP.hits = SP.hits + 1
      dcount(SP, "跳过远处 AI", 1)
      return true                       -- 跳过原方法：这一帧远处置之不理
  end

  SP = domain({
      name = "刷怪质量",
      fields = function(T)
          register("npc_active", T.NPC, "active", "bool")
          register("npc_pos", T.NPC, "position", "vec2")
          register("player", T.MAIN, "player", "object")
      end,
      install = function()
          safe_hook(M.update_npc, { prefix = on_npc_update }, "NPC.UpdateNPC（AI 简化）")
      end,
      methods = function(T)
          M.update_npc = T.NPC and find_method(T.NPC, "UpdateNPC", 1)
      end,
  })

  domain({
      name = "分类刷怪",
      methods = function(T)
          M.new_npc = find_method(T.NPC, "NewNPC", 10) or find_method(T.NPC, "NewNPC")
          M.spawn_npc = find_method(T.NPC, "SpawnNPC", 0)
          -- 核实 NewNPC 的形参个数（额外生成时按它传参；问不出来就退回 10）
          if M.new_npc and patch.method_param_count then
              local okc, cnt = pcall(patch.method_param_count, M.new_npc)
              if okc and type(cnt) == "number" and cnt >= 4 and cnt <= 16 then ARG.new_npc = cnt end
          end
      end,
      install = function()
          safe_hook(M.spawn_npc, { prefix = on_spawn_npc_prefix, postfix = on_spawn_npc_postfix },
              "NPC.SpawnNPC")
          safe_hook(M.new_npc, { prefix = on_new_npc_prefix, postfix = on_new_npc_postfix },
              "NPC.NewNPC")
      end,
  })

  -- ============================================================================
  -- 60b · 召唤 Boss 一次几只（v4 新增）
  -- ----------------------------------------------------------------------------
  -- 取证（PC Player.cs:44093 / 手机版符号表已核实）：
  --   · `Player.ItemCheck_UseBossSpawners(int onWhichPlayer, Item sItem)` 是**唯一**处理
  --     「用召唤物召 Boss」的方法（形参是 int + Item 引用，可以安全挂）；
  --   · 它内部调 `NPC.SpawnOnPlayer(int plr, int npcType, float ai0..ai3)` —— 6 个标量、
  --     public static，重复调用就是真的再召一只。
  --   · 哥布林入侵 / 史莱姆雨 / 刷怪雕像也走 SpawnOnPlayer，所以必须用 fl.boss_summon
  --     窗口把「召唤物触发的」和「事件刷的」分开，绝不无差别翻倍。
  --   ★ 机械三王那种一次召两只的道具（544 → 125 + 126）会在每只上各乘一遍，
  --     所以实际只数 = 2 × 设置值，已写进设置说明。
  -- ============================================================================

  local in_boss_dup = false

  local function on_use_boss_spawners_prefix()
      if not ready then return end
      fl.boss_summon = true
  end

  local function on_use_boss_spawners_postfix()
      fl.boss_summon = false
  end

  local function on_spawn_on_player(inst, args)
      if not ready or not fl.boss_summon or in_boss_dup then return end
      local n = P.boss_count or 1
      if n <= 1 or not M.spawn_on_player then return end
      if not may_write() then return end
      local argc = ARG.spawn_on_player
      if type(argc) ~= "number" or argc < 2 or argc > 16 then return end
      if not args then return end
      local call = {}
      for i = 1, argc do call[i] = args[i] end
      if type(call[1]) ~= "number" or type(call[2]) ~= "number" then return end

      in_boss_dup = true
      for _ = 2, n do
          local ok, err = invoke_checked(M.spawn_on_player, argc, table.unpack(call, 1, argc))
          if not ok then
              warn_once("boss_dup", "额外召唤 Boss 失败：" .. tostring(err))
              break
          end
          stats.boss_extra = (stats.boss_extra or 0) + 1
      end
      in_boss_dup = false
  end

  domain({
      name = "召唤 Boss 数量",
      methods = function(T)
          M.use_boss_spawners = T.PLAYER and find_method(T.PLAYER, "ItemCheck_UseBossSpawners", 2)
          M.spawn_on_player = T.NPC and find_method(T.NPC, "SpawnOnPlayer", 6)
          if M.spawn_on_player and patch.method_param_count then
              local okc, cnt = pcall(patch.method_param_count, M.spawn_on_player)
              if okc and type(cnt) == "number" then ARG.spawn_on_player = cnt end
          end
      end,
      install = function()
          -- 不按设置值决定要不要装（setup 阶段还没读设置）：回调里 P.boss_count <= 1 时第一行早退
          safe_hook(M.use_boss_spawners,
              { prefix = on_use_boss_spawners_prefix, postfix = on_use_boss_spawners_postfix },
              "Player.ItemCheck_UseBossSpawners")
          safe_hook(M.spawn_on_player, { postfix = on_spawn_on_player }, "NPC.SpawnOnPlayer")
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do

  -- ============================================================================
  -- 62 · 稀有生物刷新
  -- ----------------------------------------------------------------------------
  -- 「稀有」怎么判？**先用游戏自己的标准**：
  --   `NPC.rarity` —— 原版就是靠它标记稀有生物的（生命体分析仪认的就是 rarity > 0）。
  --   因此主判据是 `rarity > 0`，与「掉落金钱 ≥ 阈值」的旧判据相比，这才是原版口径。
  --   备用判据（只在 rarity 读不到时生效）：`NPC.value`（掉落金钱，单位铜币）。
  --   两条判据都漏掉的个别生物，还可以用设置里的「稀有编号补表」手工补。
  --
  -- ★ 不自己装钩子：NPC.SetDefaults 归 50_npc、NPC.NewNPC 归 60_spawn，同一个方法上装第二个
  --   钩子会把先装的那个顶掉（内核只保留最后安装的一个）。所以本域改用「阶段登记」：
  --   把三个处理函数登记成 npc_defaults / npc_new_prefix / npc_new_postfix，
  --   由那两处既有钩子通过 call_domains 派发 —— 效果一样，但只占一个钩子位。
  --
  -- 倍率怎么生效？复用 60_spawn.lua 已经建立的那套窗口机制：
  --   · 只有落在 `NPC.SpawnNPC`（自然刷怪）窗口里的 `NPC.NewNPC` 才动手；
  --   · < 100% 按概率拦掉，> 100% 在原实参上再调一次 NewNPC（= 多刷一只）。
  -- ============================================================================

  local type_rare = {}                  -- [生物 type] = true（由 SetDefaults 现场学出来）
  local rarity_types = { "int32", "float" }   -- 反编译源码核对：NPC.rarity 是 public int（int32 优先）

  -- 读 NPC.rarity：按 int32 读（反编译源码核对为 public int），读不到再试 float。
  -- 句柄判空 + pcall 包裹（红线 4）；读不到返回 nil，调用方走备用判据。
  local function fget_rarity(inst)
      local f = F["rarity"]
      if not f then return nil end
      for i = 1, #rarity_types do
          local ok, v = pcall(patch.get_field_value, f, inst, rarity_types[i])
          if ok and type(v) == "number" then return v end
      end
      return nil
  end

  local function learn_rare(inst, ty)
      if type_rare[ty] ~= nil then return end
      if P.rare.list[ty] then
          type_rare[ty] = true
          return
      end
      -- ① 原版判据：rarity > 0（设置「原版稀有标记」关闭时跳过这一条）
      if P.rare.rarity ~= false then
          local r = fget_rarity(inst)
          if type(r) == "number" then
              type_rare[ty] = (r > 0)
              if type_rare[ty] then
                  verbose(string.format("首次标记稀有生物：编号 %d（原版 rarity=%s）",
                      ty, tostring(r)))
              end
              return
          end
      end
      -- ② 备用判据：掉落金钱（只在 rarity 字段不可用时走到这里）
      local v = fget("value", inst)
      type_rare[ty] = (type(v) == "number" and v >= P.rare.threshold) or false
      if type_rare[ty] then
          verbose(string.format("首次标记稀有生物：编号 %d（掉落 %d 铜，rarity 不可用）",
              ty, math.floor(v)))
      end
  end

  -- v4：现场学「这个编号是不是稀有」。原来挂在 NPC.SetDefaults 上，但那个方法带结构体参数、
  -- 挂不上，所以改到 NPC.NewNPC 的 postfix（由 60_spawn 派发）。
  local function learn_from_spawn(args, result)
      if not P.rare.active then return end
      local npc = npc_by_index(result)
      if not npc then return end
      local ty = args and args[4]
      if type(ty) ~= "number" or ty < 1 or ty > 2000 then ty = fget("npctype", npc) end
      if type(ty) ~= "number" or ty < 0 then return end
      pcall(learn_rare, npc, ty)
  end

  -- 与 60_spawn.lua 同构的实参合理性校验（宁可少一个功能，也不拿不确定的实参去赌）
  local function rare_args_ok(args)
      if not args then return nil end
      local x, y, ty = args[2], args[3], args[4]
      if type(x) ~= "number" or type(y) ~= "number" or type(ty) ~= "number" then return nil end
      if ty < 1 or ty > 2000 then return nil end
      if x < 0 or y < 0 or x > 200000 or y > 200000 then return nil end
      return ty
  end

  -- ★ v5：稀有生物的总倍率 = 「稀有生物·刷新倍率」×「精英与稀有怪·刷新倍率」
  --   （后者是 v5 新增，专门给「稀有/精英怪出现概率」这一把旋钮；两者相乘，默认都是 1）
  local function rare_eff_mult()
      local m = P.rare.mult
      local e = (P.spawnq and P.spawnq.elite_mult) or 1
      return m * e
  end

  local function on_new_npc_prefix(inst, args)
      if not ready or spawn_win.in_dup or not spawn_win.natural or not P.rare.active then return end
      local eff = rare_eff_mult()
      if eff >= 1 then return end
      local ty = rare_args_ok(args)
      if not ty or not type_rare[ty] then return end
      if eff <= 0 or math.random() >= eff then
          stats.rare_blocks = (stats.rare_blocks or 0) + 1
          return true, 200                       -- 200 = 原版的「没有空位」
      end
  end

  local function on_new_npc_postfix(inst, args, result)
      if not ready then return end
      pcall(learn_from_spawn, args, result)
      if not spawn_win.natural or spawn_win.in_dup then return end
      if not may_write() then return end
      local eff = rare_eff_mult()
      if not P.rare.active or eff <= 1 or spawn_win.budget <= 0 then return end
      if not M.new_npc or result == 200 then return end
      local ty = rare_args_ok(args)
      if not ty or not type_rare[ty] then return end

      local extra = math.floor(eff + 0.5) - 1
      if extra > spawn_win.budget then extra = spawn_win.budget end
      if extra <= 0 then return end
      local n = ARG.new_npc
      if type(n) ~= "number" or n < 4 or n > 16 then return end

      local call, ox, oy = {}, args[2], args[3]
      for i = 1, n do call[i] = args[i] end
      spawn_win.in_dup = true
      for _ = 1, extra do
          call[2] = ox + math.random(-24, 24)
          call[3] = oy + math.random(-16, 16)
          local ok = invoke_checked(M.new_npc, n, table.unpack(call, 1, n))
          if not ok then break end
          spawn_win.budget = spawn_win.budget - 1
          stats.rare_dups = (stats.rare_dups or 0) + 1
          if spawn_win.budget <= 0 then break end
      end
      spawn_win.in_dup = false
  end

  local function reset_rare()
      type_rare = {}
  end

  domain({
      name = "稀有生物",
      fields = function(T)
          -- 原版稀有判据；取不到（或被判为 const）时自动退回「掉落金钱」备用判据
          register("rarity", T.NPC, "rarity", "float")
      end,
      methods = function(T)
          M.new_npc = M.new_npc or (T.NPC and find_method(T.NPC, "NewNPC", 10))
      end,
      -- 不装钩子，只登记阶段（见文件头注释）
      npc_new_prefix = on_new_npc_prefix,
      npc_new_postfix = on_new_npc_postfix,
      reset = reset_rare,
      reload = reset_rare,        -- 阈值/补表改了就重新学一遍
  })
end



-- ============================================================================
-- 65 · 死亡与复活：原地复活 / 墓碑掉落
-- ----------------------------------------------------------------------------
-- 取证（Terraria 1.4.4 反编译，行号即出处）：
--   · 复活：`Player.Spawn(PlayerSpawnContext)`（Player.cs:35700，public void / 1 参）。
--     死亡复活的调用点是 `Spawn(PlayerSpawnContext.ReviveFromDeath)`（Player.cs:16893）；
--     魔镜回城与「进入世界」走的是同一个方法的重载枚举值。
--     ★ 怎么区分「死亡复活」和「魔镜回城」？**不去猜枚举的数值**（枚举定义不在
--       Player.cs 里，猜错就会把魔镜变成自杀传送），而是读 `Player.dead`：
--       死亡复活时它一定是 true，魔镜回城时一定是 false。prefix 里记下这个事实，
--       postfix 里才动手 —— 这样即使枚举顺序在本机不同也不会误伤。
--   · 死亡坐标：`Player.lastDeathPostion`（Player.cs:639，public Vector2，
--     原版拼写就是 Postion）在 Player.cs:36694 被写成死亡瞬间的 Center。
--     原地复活 = 把 `Player.position` 写回它（同时把速度归零，免得带着死亡时的惯性飞出去）。
--   · 墓碑：`Player.DropTombstone(long, NetworkText, int)`（Player.cs:36908，3 参）
--     是墓碑掉落的唯一出口（玩家死亡流程 Player.cs:36852 调它）。
--     三个参数全是标量或引用类型，没有结构体 → 可以安全地在 prefix 拦掉。
-- ============================================================================

local function on_spawn_prefix(inst)
    if not ready or not P.death.in_place then return end
    fl.spawn_dead = (fget("dead", inst) == true)
end

local function on_spawn_postfix(inst)
    if not ready or not fl.spawn_dead then return end
    fl.spawn_dead = false
    if not P.death.in_place then return end

    local dx, dy = fget_vec2("last_death_pos", inst)
    if type(dx) ~= "number" or type(dy) ~= "number" then return end
    -- (0,0) 是世界左上角外，说明这一局还没死过 → 不碰
    if dx < 16 or dy < 16 then return end
    if fset_vec2("position", inst, dx, dy) then
        fset_vec2("velocity", inst, 0, 0)
        stats.in_place_revive = (stats.in_place_revive or 0) + 1
        verbose(string.format("原地复活：%.0f, %.0f", dx, dy))
    end
end

-- ★ v4：「复活等待时间倍率 / 秒复活」。
--   原版 Player.KillMe(PlayerDeathReason, double, int, bool) 里有一句
--   `respawnTimer = GetRespawnTime(pvp);`（PC Player.cs:39210），之后 Player.UpdateDead
--   每帧 `respawnTimer = Clamp(respawnTimer - 1, 0, respawnTimerMax)`，到 0 且是本地玩家就复活。
--   respawnTimerMax 是 **readonly 常量 3600 帧（= 60 秒）**，所以：
--     · 调小（倍率 < 100）有效且明显；
--     · 调大超过 60 秒没有意义（下一帧就被夹回去）—— 已写进设置说明。
--   第一个形参 PlayerDeathReason 是**类**（引用类型），不是结构体，所以这个钩子能安全挂上。
--   秒复活 = 把 respawnTimer 置 1，等同原版 Player.SkipRespawnTime()（它的实现就是 `respawnTimer = 1;`）。
local function on_kill_me(inst, args)
    if not ready or not P.death.active then return end
    if not may_write() then return end
    if not inst then return end
    local who = fget("who_am_i", inst)
    if type(who) ~= "number" or who ~= my_player_index() then return end

    if P.death.instant then
        if M.skip_respawn then
            local ok = invoke_instance(M.skip_respawn, inst)
            if ok then
                stats.instant_respawn = (stats.instant_respawn or 0) + 1
                verbose("秒复活：已把复活计时置为 1 帧")
                return
            end
        end
        if fset_if("respawn_timer", inst, 1) then
            stats.instant_respawn = (stats.instant_respawn or 0) + 1
        end
        return
    end

    local mult = P.death.time_mult
    if mult == 1.0 then return end
    local cur = fget("respawn_timer", inst)
    if type(cur) ~= "number" or cur <= 0 then return end
    local want = math.floor(cur * mult + 0.5)
    if want < 1 then want = 1 end
    if want > 3600 then want = 3600 end        -- 原版上限（respawnTimerMax）
    if want ~= cur then
        if fset("respawn_timer", inst, want) then
            stats.respawn_time_sets = (stats.respawn_time_sets or 0) + 1
        end
    end
end

local function on_drop_tombstone(inst, args)
    if not ready or not P.death.block_tomb then return end
    stats.tomb_blocks = (stats.tomb_blocks or 0) + 1
    return true                        -- 拦掉这次墓碑掉落
end

domain({
    name = "死亡与复活",
    fields = function(T)
        register("dead", T.PLAYER, "dead", "bool")
        register("last_death_pos", T.PLAYER, "lastDeathPostion", "vec2")
        register("position", T.PLAYER, "position", "vec2")
        register("velocity", T.PLAYER, "velocity", "vec2")
        -- v4：复活计时与本地玩家判定
        register("respawn_timer", T.PLAYER, "respawnTimer", "int32")
        register("who_am_i", T.PLAYER, "whoAmI", "int32")
    end,
    methods = function(T)
        M.spawn = T.PLAYER and find_method(T.PLAYER, "Spawn", 1)
        M.drop_tombstone = T.PLAYER and find_method(T.PLAYER, "DropTombstone", 3)
        -- v4：KillMe(PlayerDeathReason, double, int, bool) ／ SkipRespawnTime()
        M.kill_me = T.PLAYER and find_method(T.PLAYER, "KillMe", 4)
        M.skip_respawn = T.PLAYER and find_method(T.PLAYER, "SkipRespawnTime", 0)
    end,
    install = function()
        safe_hook(M.spawn, { prefix = on_spawn_prefix, postfix = on_spawn_postfix }, "Player.Spawn")
        safe_hook(M.drop_tombstone, { prefix = on_drop_tombstone }, "Player.DropTombstone")
        safe_hook(M.kill_me, { postfix = on_kill_me }, "Player.KillMe（复活计时）")
    end,
})



-- ============================================================================
-- 68 · 制作站：制作范围 / 特殊制作站效果
-- ----------------------------------------------------------------------------
-- 取证（Terraria 1.4.4 反编译，行号即出处）：
--   · 制作范围：`Player.AdjTiles()`（Player.cs:33827，public void / 0 参）是「玩家周围
--     有哪些制作站」的**唯一扫描函数**，范围被写死在函数开头：
--         int num = 4;  int num2 = 3;
--         if (ateArtisanBread) { num += 4; num2 += 4; }
--     即原版水平 ±4 / 垂直 3+3 格，吃了「工匠面包」变成 ±8 / 7+7 格。
--     于是「扩大制作范围」有两条路：① 改写扫描半径（做不到，是局部量）；
--     ② **在读半径之前把 `Player.ateArtisanBread` 临时置 true**（原版自己的加宽通道）。
--     本模组走 ②：prefix 置 true，postfix 还原成原值 —— 不污染存档里的那个标志位。
--   · 炼药桌：`Player.AdjTiles` 在扫到 355 号图格（炼药桌）时把 `Player.alchemyTable`
--     （Player.cs:589）置 true（33878 行），而消耗判据在
--     `Recipe.cs:190  if (alchemy && Main.player[Main.myPlayer].alchemyTable)`。
--     既然判据只是一个 bool，postfix 里把它强制成 true 就等于「炼药桌效果全局生效」。
--   · 省料概率改不了：`Recipe.cs:190` 那一段的概率是内联的随机数，没有可改的字段，
--     所以本模组只做「生效范围」，不做「概率」。
-- ============================================================================

local function on_adj_tiles_prefix(inst)
    if not ready then return end
    -- v4 主机总闸：客机上不写（这个字段是存档位，客机改了也没意义）
    if not may_write() then return end
    -- 记下原值：postfix 里必须原样还回去（这是存档位，不能留下我们的痕迹）
    fl.artisan_saved = fget("artisan_bread", inst)
    if P.station.craft_boost and fl.artisan_saved ~= true then
        if fset("artisan_bread", inst, true) then
            fl.artisan_touched = true
            stats.craft_boost = (stats.craft_boost or 0) + 1
        end
    end
end

local function on_adj_tiles_postfix(inst)
    if not ready then return end
    if fl.artisan_touched then
        fl.artisan_touched = false
        -- 还原：原值不是 true 就写回 false（true 的话本来就不用动）
        if fl.artisan_saved ~= true then fset("artisan_bread", inst, false) end
        fl.artisan_saved = nil
    end
    if P.station.alchemy_global then
        -- AdjTiles 内部刚把它清成 false 再按扫描结果置位，这里覆盖成「永远有炼药桌」
        if fget("alchemy_table", inst) ~= true then
            if fset("alchemy_table", inst, true) then
                stats.alchemy_global = (stats.alchemy_global or 0) + 1
            end
        end
    end
end

domain({
    name = "制作站",
    fields = function(T)
        register("artisan_bread", T.PLAYER, "ateArtisanBread", "bool")
        register("alchemy_table", T.PLAYER, "alchemyTable", "bool")
    end,
    methods = function(T)
        M.adj_tiles = T.PLAYER and find_method(T.PLAYER, "AdjTiles", 0)
    end,
    install = function()
        safe_hook(M.adj_tiles, { prefix = on_adj_tiles_prefix, postfix = on_adj_tiles_postfix },
            "Player.AdjTiles")
    end,
})



-- ============================================================================
-- 70 · NPC 住房判定（WorldGen 的四件套）
-- ----------------------------------------------------------------------------
-- 时机与理由：
--   · 免装修   → RoomNeeds 是家具判定（门/桌/椅/光源）的唯一入口，
--                MoveTownNPC 与 QuickFindHome 都走它；prefix 直接跳过即可
--                （它置的那批全局标志只用于失败提示，跳过不留副作用）。
--   · 无视腐化 → ScoreRoom 里唯一会被「邪恶方块」扣分的地方就是一次
--                GetTileTypeCountByCategory 调用；只在「正在判定住房」时按 0 返回。
--   · 一屋 N 人 → 两道门一起开：
--                ① TownRoomManager.CanNPCsLiveWithEachOther 是原版「谁能和谁同住」的判据，
--                   prefix 恒返回 true = 任何 NPC 都能同住（这才是「一屋 N 人」真正的开关）；
--                ② ScoreRoom_IsThisRoomOccupiedBySomeone 负责「住满 N 个才算有人」的计数上限。
--   · 无视尺寸 → StartRoomCheck 的失败只有两种原因：起点就是实心块（一个房间格子
--                都没扫到）／扫到了但不足 60 格。只有「确实扫到了房间」才放过，
--                避免把野地当成房子。
-- 「正在判定住房」用嵌套深度计数而不是布尔：ScoreRoom 可能被嵌套调用。
--
-- ★ v4 修形参个数（旧代码照 1.4.4 写错，句柄取不到 → 功能静默失效）：
--   RoomNeeds()                                        0 参（旧代码传 1）
--   ScoreRoom(int,int,IRoomCheckFeedback)              3 参（旧代码传 2）
--   StartRoomCheck(int,int,IRoomCheckFeedback)         3 参（旧代码传 2）
--   GetTileTypeCountByCategory(int[],TileScanGroup)    2 参 ✓
--   ScoreRoom_IsThisRoomOccupiedBySomeone(int,int)     2 参 ✓
--
-- ★ 「一屋 N 人」为什么以前不生效：房间格子数组是 int[]，而 array_at 对**值类型数组**
--   必须显式给类型名（省略时按对象指针解释，读出来不是数字）→ 房间格子集合是空的 →
--   数不清人数 → 每一帧都退回原版判定。现在两个数组都显式读 "int32" 修复。
--   （另：这个方法的两个形参是 ignoreNPC / npcTypeAsking，**不是坐标**，不能用它们兜底。）
-- ============================================================================

-- 统计「已经住在这个房间里」的城镇 NPC 数（early-exit：够数就停）
-- 判据：NPC 的 homeTile 落在 WorldGen.roomX/roomY 记录的这批房间格子上
--（与原版 ScoreRoom_IsThisRoomOccupiedBySomeone 用的是同一个集合）。
-- 集合读不出来时返回 nil → 交回原版判定，绝不猜。
local function count_room_npcs(limit)
    local n = fget("numRoomTiles")
    if type(n) ~= "number" or n < 1 then n = 0 end
    if n > 600 then n = 600 end

    local rx, ry, arr = get_object("roomX"), get_object("roomY"), get_object("npc")
    if not arr then return nil end
    local ok, total = pcall(patch.array_length, arr)
    if not ok or type(total) ~= "number" or total < 1 then total = 400 end
    if total > 400 then total = 400 end
    if total < 1 then return nil end

    local set = nil
    if n > 0 and rx and ry then
        local s, keys = {}, 0
        for i = 0, n - 1 do
            -- ★ 值类型数组必须给 "int32"（省略类型会被当成对象指针，读出来不是数字）
            local okx, x = pcall(patch.array_at, rx, i, "int32")
            local oky, y = pcall(patch.array_at, ry, i, "int32")
            if okx and oky and type(x) == "number" and type(y) == "number" then
                s[x * 100000 + y] = true
                keys = keys + 1
            end
        end
        if keys > 0 then set = s end
    end
    if not set then return nil end        -- 房间格子读不到 → 交回原版，不猜

    local count = 0
    for i = 0, total - 1 do
        local ok2, obj = pcall(patch.array_at, arr, i)
        if ok2 and valid_obj(obj) and fget("townNPC", obj) == true and fget("homeless", obj) ~= true then
            local hx, hy = fget("homeTileX", obj), fget("homeTileY", obj)
            if type(hx) == "number" and type(hy) == "number" then
                -- 原版判据是「家坐标 与 家坐标-1 都在房间格子里」，这里对齐它
                if set[hx * 100000 + hy] == true or set[hx * 100000 + (hy - 1)] == true then
                    count = count + 1
                    if count >= limit then return count end
                end
            end
        end
    end
    return count
end

local function on_score_room_prefix()
    fl.score_room = fl.score_room + 1
end

local function on_score_room_postfix()
    if fl.score_room > 0 then fl.score_room = fl.score_room - 1 end
end

local function on_can_live_together(inst, args)
    if not ready or P.house.max_npcs <= 1 then return end
    if not may_write() then return end
    return true, true                      -- 跳过原方法：这两个 NPC 可以同住
end

local function on_room_needs(inst, args)
    if not ready or not P.house.no_furniture then return end
    if not may_write() then return end
    return true, true
end

local function on_tile_type_count(inst, args, result)
    if not ready or fl.score_room <= 0 or not P.house.ignore_evil then return result end
    if not may_write() then return result end
    return 0
end

local function on_start_room_check(inst, args, result)
    if not ready or not P.house.ignore_size then return result end
    if not may_write() then return result end
    if result == true then return result end
    local n = fget("numRoomTiles")
    if type(n) ~= "number" or n < 1 then return result end
    return true
end

local function on_room_occupied(inst, args, result)
    if not ready or P.house.max_npcs <= 1 then return result end
    if not may_write() then return result end
    local n = count_room_npcs(P.house.max_npcs)
    if not n then return result end
    if n >= P.house.max_npcs then return true end
    return false
end

domain({
    name = "NPC 住房",
    fields = function(T)
        register("numRoomTiles", T.WORLDGEN, "numRoomTiles", "int32")
        register("roomX", T.WORLDGEN, "roomX", "object")
        register("roomY", T.WORLDGEN, "roomY", "object")
        register("homeless", T.NPC, "homeless", "bool")
        register("homeTileX", T.NPC, "homeTileX", "int32")
        register("homeTileY", T.NPC, "homeTileY", "int32")
    end,
    methods = function(T)
        M.room_needs = T.WORLDGEN and find_method(T.WORLDGEN, "RoomNeeds", 0)
        M.score_room = T.WORLDGEN and find_method(T.WORLDGEN, "ScoreRoom", 3)
        M.room_occupied = T.WORLDGEN and find_method(T.WORLDGEN, "ScoreRoom_IsThisRoomOccupiedBySomeone", 2)
        M.tile_count = T.WORLDGEN and find_method(T.WORLDGEN, "GetTileTypeCountByCategory", 2)
        M.start_room_check = T.WORLDGEN and find_method(T.WORLDGEN, "StartRoomCheck", 3)
        -- 两个同名重载（int,NPC）与（NPC,NPC）-> 按参数名精确选第一个
        M.can_live_together = T.TOWNROOM
            and (find_method_by_names(T.TOWNROOM, "CanNPCsLiveWithEachOther", { "npc1ByType", "npc2" })
                 or find_method(T.TOWNROOM, "CanNPCsLiveWithEachOther", 2))
    end,
    install = function()
        safe_hook(M.room_needs, { prefix = on_room_needs }, "WorldGen.RoomNeeds")
        safe_hook(M.score_room, { prefix = on_score_room_prefix, postfix = on_score_room_postfix },
            "WorldGen.ScoreRoom")
        safe_hook(M.room_occupied, { override_result = true, postfix = on_room_occupied },
            "WorldGen.ScoreRoom_IsThisRoomOccupiedBySomeone")
        safe_hook(M.tile_count, { override_result = true, postfix = on_tile_type_count },
            "WorldGen.GetTileTypeCountByCategory")
        safe_hook(M.start_room_check, { override_result = true, postfix = on_start_room_check },
            "WorldGen.StartRoomCheck")
        -- 「一屋 N 人」的第一道门：任何 NPC 都能同住
        safe_hook(M.can_live_together, { prefix = on_can_live_together },
            "TownRoomManager.CanNPCsLiveWithEachOther")
    end,
})


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 72 · NPC 商店售价倍率（v5 新增）
  -- ----------------------------------------------------------------------------
  -- 取证（PC 1.4.5.8 只有一个价格出口）：
  --   · `Player.GetItemExpectedPrice(Item, out long, out long)` 里价格是这样来的：
  --       `int storeValue = item.GetStoreValue(); calcForSelling = storeValue;
  --        calcForBuying = storeValue;` 然后才乘 / 除
  --       `currentShoppingSettings.PriceAdjustment`（幸福度系数）。
  --   · `Item.GetStoreValue()` 是**0 参实例方法、返回 int**（手机版符号表已核实），
  --     `shopCustomPrice` 有值时直接返回它、否则返回 `Item.value` —— 全游戏就这一个出口
  --     （PC 里只有 Item.cs 的定义与 Player.cs:35645 这一个调用点）。
  --   → 在它的 postfix 里把返回值乘上倍率（`override_result = true`），
  --     买价与卖价的计算基准一起变；后面幸福度系数的乘除照旧生效。
  --   ★ 「无视幸福度」本代做不到：价格系数是 `ShoppingSettings` **结构体**
  --     （`ShopHelper.GetShoppingSettings(Player,NPC)` 按值返回、`Player.currentShoppingSettings`
  --     是结构体字段），内核把复杂结构体字段当 PATCH_POINTER 处理，Lua 侧既读不出字段、
  --     也无法构造结构体返回值去覆盖。设置页里那一项是只读说明。
  -- ============================================================================

  local SH          -- ★ 前向声明：on_store_value 里要引用它

  local function on_store_value(inst, args, result)
      if not ready then return end
      -- ★ v7：先记「钩子真的被调到了」，再判断设置 —— 这样 /forge stat 里
      --   「调用 n」能把「句柄没取到 / 钩子没生效（调用恒 0）」与「override_result 被忽略
      --   （调用在涨、价格改写恒 0）」区分开，不用猜。
      SH.calls = SH.calls + 1
      if not P.shop.active then return end
      if type(result) ~= "number" then return end
      if not may_write() then return end
      local m = P.shop.mult
      if m == 1 then return end
      local v = math.floor(result * m + 0.5)
      if v < 1 then v = 1 end
      if v > 2000000000 then v = 2000000000 end
      SH.hits = SH.hits + 1
      dcount(SH, "价格改写", 1)
      return v
  end

  SH = domain({
      name = "商店售价",
      methods = function(T)
          M.store_value = T.ITEM and find_method(T.ITEM, "GetStoreValue", 0)
      end,
      install = function()
          safe_hook(M.store_value, { postfix = on_store_value, override_result = true },
              "Item.GetStoreValue")
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 80 · 晶塔规则 —— v5 按「从未修过」重写
  -- ----------------------------------------------------------------------------
  -- ★★ 为什么旧版无效（三条，全部可复核）★★
  --
  -- ① 【v4】所有子项都挂在「晶塔改造总开关」（pylon_unlock，默认**关**）下面：
  --      py.range = py.on and cfg.pylon_ignore_range ...
  --    于是玩家只打开「晶塔无视距离」时**什么都不发生**，而设置页与 report() 都没提示
  --    这层依赖 —— 这是 v4「所有改造均不生效」的头号原因。v5 **删掉总开关**，每个子项各管各的。
  --
  -- ② 【v4】「允许同类型多座」与「总数上限」的分支顺序写反了：
  --      先判 limit、再判 dupes，而 dupes 分支直接 `return false` —— 两个都开时
  --      总数上限永远不会生效。v5 改成：先判上限（到顶就恒 true = 拒绝放置），再判多座。
  --      另外「总数上限」的界面值 1 = 不限、N ≥ 2 = 最多 N−1 座，v5 在说明里写清楚了。
  --
  -- ③ 【v4 及以前】`NPC.AnyDanger` 按 1.4.4 的 **2 参** 取句柄（旧 C++ 文件甚至只写 1 个 self），
  --    而 1.4.5.8 手机版是 **3 参**：
  --      grep -P '^Terraria\.NPC\tAnyDanger\t' 参考库/符号/官方源码-方法.tsv
  --      → Terraria.NPC  AnyDanger  3  bool, bool, bool  quickBossNPCCheck, ignorePillarsAndMoonlordCountdown, ignoreInvasions
  --    句柄取不到 → 「无视危险」静默失效（连失败日志都没有）。
  --
  -- ★ 真正的判定入口在哪里（PC 1.4.5.8 `Terraria.GameContent/TeleportPylonsSystem.cs`）：
  --     `HandleTeleportRequest(TeleportPylonInfo info, int playerIndex)`（第 100 行）是**唯一**的
  --     传送受理入口，它依次调用：
  --       · `IsPlayerNearAPylon(Player)`（第 107 行，**静态、1 类参**）← 我们能挂 ★无视距离
  --       · `HowManyNPCsDoesPylonNeed(info, player)`          ← 结构体参，挂不上
  --       · `DoesPylonHaveEnoughNPCsAroundIt(info, int)`      ← 结构体参，挂不上
  --       · `DoesPylonAcceptTeleportation(info, player)`      ← 结构体参，挂不上（生物群系要求）
  --       · `DoesPositionHaveEnoughNPCs(int, Point16)`        ← 结构体参，挂不上
  --     所以「所需 NPC 数」「无视生物群系」本代**做不到**（设置页里是只读说明）：
  --     本代 Lua 加载器的钩子走 libffi 闭包、**只支持标量参数**（05 §4.3），
  --     `TeleportPylonInfo` / `Point16` 是 `IL2CPP_TYPE_VALUETYPE` 按值传递。
  --     旧 EFMod(C++) 模组能挂是因为那一代 C++ 加载器支持结构体按值 —— 证据就是
  --     `无条件放置晶塔无视事件传送.cpp` 里把 `Point16` 写成两个 int：
  --       `Hook_DoesPositionHaveEnoughNPCs(self, int x, int y)`（结构体按寄存器拆开）。
  --     ★ 注意 `TeleportPylonType` 是**枚举**，内核把枚举映射成 PATCH_INT32（标量），
  --       所以 `HasPylonOfType(TeleportPylonType)` 能挂 —— 与结构体不是一回事。
  --
  -- ★ v5 保留并加固的三条（各自带命中计数）：
  --     ① 晶塔无视距离   → `IsPlayerNearAPylon` prefix 恒 true
  --     ② 晶塔无视危险   → `NPC.AnyDanger(bool,bool,bool)` prefix 恒 false
  --     ③ 允许同类型多座 / 全图总数上限 → `HasPylonOfType` postfix 覆盖返回值
  --     + 可用性核查：`HasAnyPylon()` / `Update()` / `RequestImmediateUpdate()` 三个标量入口
  --       都解析出来并在诊断里报告；进世界首帧调一次 `Update()` 让 `_pylons` 列表是新鲜的，
  --       计数拿不到长度时用 `HasAnyPylon()` 退化成 0/1。
  -- ============================================================================

  local PY          -- ★ 前向声明：下面几个回调体里要引用它

  -- 实际晶塔座数：Main.PylonSystem（public static 字段）→ _pylons
  -- （List<TeleportPylonInfo>，private 实例字段）→ list_get_array → array_length。
  -- 任何一步拿不到就退回 HasAnyPylon()（0/1），绝不猜。
  local function pylon_count()
      local sys = get_object("pylon_system")
      if not sys and not M.get_pylons then return nil end
      local lst
      if F.pylon_list then lst = fget("pylon_list", sys) end
      if not lst and M.get_pylons then
          local ok, v = pcall(patch.invoke, M.get_pylons, sys)
          if ok and v then lst = v end
      end
      if lst then
          local ok, arr = pcall(patch.list_get_array, lst)
          if ok and arr then
              local ok2, n = pcall(patch.array_length, arr)
              if ok2 and type(n) == "number" then
                  return n
              end
          end
      end
      if M.has_any_pylon and sys then
          local ok, v = pcall(patch.invoke, M.has_any_pylon, sys)
          if ok and type(v) == "boolean" then return v and 1 or 0 end
      end
      return nil
  end

  local function on_player_near_pylon(inst, args)
      if not ready or not P.pylon.range then return end
      PY.hits = PY.hits + 1
      dcount(PY, "无视距离", 1)
      return true, true                      -- 跳过原方法：就算在晶塔旁边
  end

  local function on_any_danger(inst, args)
      if not ready or not P.pylon.danger then return end
      PY.hits = PY.hits + 1
      dcount(PY, "无视危险", 1)
      return true, false                     -- 跳过原方法：「有危险」恒为假
  end

  local function on_has_pylon_of_type(inst, args, result)
      if not ready or not P.pylon.active then return result end
      if not may_write() then return result end

      -- ★ ① 先判「全图总数上限」：到顶后**任何**类型都回答「已经有了」→ 原版拒绝放置
      local limit = P.pylon.limit or 0
      if limit > 0 then
          local n = pylon_count()
          if n and n >= limit then
              PY.hits = PY.hits + 1
              dcount(PY, "总数到顶拦截", 1)
              return true
          end
      end
      -- ★ ② 再判「允许同类型多座」：恒 false = 取消「每种只能一座」
      if P.pylon.dupes then
          PY.hits = PY.hits + 1
          dcount(PY, "同类型放行", 1)
          return false
      end
      return result
  end

  PY = domain({
      name = "晶塔",
      fields = function(T)
          -- Main.PylonSystem：public static TeleportPylonsSystem（符号表已核实是普通静态字段）
          register("pylon_system", T.MAIN, "PylonSystem", "object")
          -- TeleportPylonsSystem._pylons：private List<TeleportPylonInfo>（private 也能取句柄）
          register("pylon_list", T.PYLON, "_pylons", "object")
      end,
      methods = function(T)
          -- ★ IsPlayerNearAPylon 是 **静态**、1 个类参
          M.player_near_pylon = T.PYLON and find_method(T.PYLON, "IsPlayerNearAPylon", 1)
          -- ★ HasPylonOfType 是**实例**方法、1 个**枚举**参（枚举 → 内核 PATCH_INT32，可挂）
          M.has_pylon_of_type = T.PYLON and find_method(T.PYLON, "HasPylonOfType", 1)
          -- ★ 3 参（quickBossNPCCheck / ignorePillarsAndMoonlordCountdown / ignoreInvasions）
          M.any_danger = T.NPC and find_method(T.NPC, "AnyDanger", 3)
          -- 可用性核查用的三个标量入口
          M.has_any_pylon = T.PYLON and find_method(T.PYLON, "HasAnyPylon", 0)
          M.pylon_update = T.PYLON and find_method(T.PYLON, "Update", 0)
          M.pylon_request_update = T.PYLON and find_method(T.PYLON, "RequestImmediateUpdate", 0)
          M.get_pylons = T.PYLON and find_method(T.PYLON, "get_Pylons", 0)
      end,
      install = function()
          safe_hook(M.player_near_pylon, { prefix = on_player_near_pylon },
              "TeleportPylonsSystem.IsPlayerNearAPylon")
          safe_hook(M.any_danger, { prefix = on_any_danger }, "NPC.AnyDanger")
          safe_hook(M.has_pylon_of_type, { override_result = true, postfix = on_has_pylon_of_type },
              "TeleportPylonsSystem.HasPylonOfType")
      end,
      -- 进世界后第一帧把 _pylons 列表刷一次（原版 Update() 自带宽限，代价低、幂等）
      frame = function()
          if not P.pylon.active or mem.pylon_refreshed then return end
          mem.pylon_refreshed = true
          if M.pylon_update then
              local ok = invoke_instance(M.pylon_update, get_object("pylon_system"))
              if ok then dcount(PY, "列表已刷新", 1) end
          end
      end,
      reset = function()
          mem.pylon_refreshed = false
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do

  -- ============================================================================
  -- 85 · 世界生成事件：陨石坠落 / 世纪之花苞
  -- ----------------------------------------------------------------------------
  -- 取证（Terraria 1.4.4 反编译，行号即出处）：
  --   · 陨石：
  --       `WorldGen.spawnMeteor`（WorldGen.cs:980，**public static bool 字段**）是待落标志；
  --       `Main.HandleMeteorFall()`（Main.cs:62219）里那一句
  --           if (time > 16200.0 && WorldGen.spawnMeteor) { spawnMeteor = false; dropMeteor(); }
  --       就是唯一的坠落判定（time > 16200 = 白天 9:00 之后）。
  --       → 改这个字段就等于改生成机制：置 false = 永远不落；置 true = 一过 9:00 就落。
  --       `WorldGen.dropMeteor()`（2739，public static void / 0 参）是实际落点生成器，
  --       「立即坠一颗」= 原样 invoke 它。
  --   · 世纪之花苞：
  --       `WorldGen.GeneratePlanteraBulbOnAllMechsDefeated()`（WorldGen.cs:64092，
  --       public static bool / 0 参）是花苞成规模生成的地方；原版只在
  --       「三王全败」这个一次性事件里调它（NPC.cs:71102）。
  --       → prefix 拦掉 = 永不生成；原样 invoke = 立刻补一次。
  -- ============================================================================

  local GN          -- ★ 前向声明：bulb_generate 与下面几个回调体里都要用它

  local function apply_meteor()
      local mode = P.gen.meteor
      if mode == "block" then
          if fget("spawn_meteor") ~= false then
              if fset_if("spawn_meteor", nil, false) then
                  stats.meteor_blocks = (stats.meteor_blocks or 0) + 1
              end
          end
      elseif mode == "boost" then
          if fget("spawn_meteor") ~= true then
              if fset_if("spawn_meteor", nil, true) then
                  stats.meteor_boosts = (stats.meteor_boosts or 0) + 1
              end
          end
      end
  end

  -- ★ v5：本模组触发的「花苞生成」统一走这里，顺手把次数上限（P.gen.bulb_runs）夹住。
  --   参考 `旧模组-CPP-123/世纪之花每天刷新最终.cpp`：它 hook Player.ResetEffects，
  --   用 NPC.downedMechBoss1/2/3 判定三王全败，再在白天开始时调原版生成流程。
  --   ★ 为什么上限统计的是「生成次数」而不是「世界上花苞的实际个数」：
  --     数实际个数要逐格扫描约 170 万格（Tile.type 在手机版还是**属性**，只能 invoke getter），
  --     成本过高，本代不做 —— README「为什么这几个功能做不到」一节写明了。
  local function bulb_generate(times, label)
      if not M.bulb_all or not P.gen then return 0 end
      local cap = P.gen.bulb_runs or 0            -- 0 = 不限次数
      local done = 0
      for _ = 1, times do
          if cap > 0 and (mem.bulb_runs or 0) >= cap then
              dcount(GN, "次数到顶", 1)
              break
          end
          local ok = invoke_checked(M.bulb_all, 0)
          if not ok then break end
          mem.bulb_runs = (mem.bulb_runs or 0) + 1
          GN.hits = GN.hits + 1
          done = done + 1
      end
      if done > 0 then
          dcount(GN, label or "花苞生成", done)
          verbose("花苞生成：" .. label .. " × " .. done)
      end
      return done
  end

  local function on_bulb_all(inst, args)
      if not ready or not P.gen.bulb_block then return end
      stats.bulb_blocks = (stats.bulb_blocks or 0) + 1
      return true, false
  end

  -- ★ v4：花苞补种间隔。
  --   原版只在「三王全败」那一刻调一次 GeneratePlanteraBulbOnAllMechsDefeated()
  --   （NPC.cs:79599，且要求 netMode != 1），一次只铺一朵（内部找到就 return true）。
  --   所谓「生成间隔」在原版根本不存在（判定是局部随机量，改不动），所以本模组改成
  --   「按玩家设定的间隔，定期再调一次原版那套生成流程」：贴住原版规则，又能自由调频率。
  local function apply_bulb_interval()
      if not may_write() then return end
      local mins = P.gen and P.gen.bulb_minutes or 0
      if mins <= 0 or not M.bulb_all then return end
      local now = os.time()
      if type(now) ~= "number" then return end
      if mem.bulb_next == nil then
          mem.bulb_next = now + mins * 60
          return
      end
      if now < mem.bulb_next then return end
      mem.bulb_next = now + mins * 60
      bulb_generate(1, "按间隔补种")
  end

  -- ★ v5：世纪之花每天刷新（每个白天开始时一次；三王全败才做）。
  --   天数用 Main.dayTime 的上升沿自己数，第一次观测只记录不触发。
  local function apply_bulb_daily()
      if not P.gen.bulb_daily or not may_write() then return end
      if not M.bulb_all then return end
      local d = fget("dayTime")
      if type(d) ~= "boolean" then return end
      local last = mem.bulb_phase
      if last == nil then
          mem.bulb_phase = d
          return
      end
      if last == d then return end
      mem.bulb_phase = d
      if not d then return end                       -- 只在入昼那一刻做
      if fget("downedMechBoss1") ~= true or fget("downedMechBoss2") ~= true
          or fget("downedMechBoss3") ~= true then
          return
      end
      dcount(GN, "每日刷新日", 1)
      bulb_generate(P.gen.bulb_daily_count or 10, "每日刷新")
  end

  -- 一次性动作（进世界后 / 设置刚打开时做一次），靠 mem 跨帧记住做过没有
  local function once_actions()
      if not P.gen.active then return end
      if P.gen.meteor == "now" and not mem.meteor_done and M.drop_meteor then
          mem.meteor_done = true
          local ok, err = invoke_checked(M.drop_meteor, 1, false)   -- false = 落在地表（原版常规）
          if not ok then
              warn_once("meteor_now", "召唤陨石失败：" .. tostring(err))
          else
              stats.meteor_now = (stats.meteor_now or 0) + 1
              mod.info("已按设置召唤一颗陨石")
          end
      end
      if P.gen.bulb_now and not mem.bulb_done and M.bulb_all then
          mem.bulb_done = true
          if bulb_generate(1, "立刻生成") > 0 then
              stats.bulb_now = (stats.bulb_now or 0) + 1
              mod.info("已按设置生成世纪之花苞")
          end
      end
  end

  -- 每帧（不自己装钩子 —— Main.UpdateTimeRate 归 40_world，本域登记成 world 阶段，
  -- 由 40_world 的 postfix 通过 call_domains 派发；同一方法装第二个钩子会把主钩子顶掉）
  local function on_world_frame()
      if not ready then return end
      if P.gen.meteor == "block" or P.gen.meteor == "boost" then pcall(apply_meteor) end
      pcall(apply_bulb_interval)
      pcall(apply_bulb_daily)
  end

  GN = domain({
      name = "世界生成事件",
      fields = function(T)
          register("spawn_meteor", T.WORLDGEN, "spawnMeteor", "bool")
          -- v5：三王全败标志（世纪之花每天刷新的前置条件）
          register("downedMechBoss1", T.NPC, "downedMechBoss1", "bool")
          register("downedMechBoss2", T.NPC, "downedMechBoss2", "bool")
          register("downedMechBoss3", T.NPC, "downedMechBoss3", "bool")
      end,
      methods = function(T)
          -- ★ v4：手机版签名是 dropMeteor(bool spawnUnderGround)（1 参）；
          --   旧代码按 0 参找 -> 句柄取到 1 参版但 invoke_checked(...,0) 被个数核对挡下 -> 静默失效。
          M.drop_meteor = T.WORLDGEN and find_method(T.WORLDGEN, "dropMeteor", 1)
          M.bulb_all = T.WORLDGEN and find_method(T.WORLDGEN, "GeneratePlanteraBulbOnAllMechsDefeated", 0)
      end,
      install = function()
          safe_hook(M.bulb_all, { prefix = on_bulb_all },
              "WorldGen.GeneratePlanteraBulbOnAllMechsDefeated")
      end,
      world = on_world_frame,
      frame = once_actions,
      reset = function()
          mem.meteor_done, mem.bulb_done, mem.bulb_next = false, false, nil
          mem.bulb_runs, mem.bulb_phase = 0, nil
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片对外只通过功能域表 / 共享表（WGCTL）/ P 表交互。
do
  -- ★★ v9：本分片整体再包一层 IIFE ★★
  --   主 chunk 也是一个函数，**活着的 local 上限 200**；86 号分片自己就有 40 多个 local，
  --   加上前面各分片的 162 个顶层 local 会直接顶爆（实测 main.lua:5496
  --   "too many local variables (limit is 200)"）。放进 IIFE 后它们只是内层函数的 local。
  --   对外只经共享表 WGCTL（95_chat 与 96_gui 都只读它），跨分片引用为零。
  (function()
  -- ============================================================================
  -- 86 · 地图生成专项（§5 世界生成）
  -- ----------------------------------------------------------------------------
  -- 设计稿：`开发文档/13-世界生成专项设计.md`（§2 触发框架、§3 全标量工具、
  -- §5 世界大小与邪恶类型、§7 图块读写姿势）。
  --
  -- 【触发与分帧】（设计稿 §2 强制）
  --   · `WorldGen.Reset()`（0 参 public static）**prefix** → 先写邪恶类型：
  --     PC 1.4.5.8 `WorldGen.Reset()`（WorldGen.cs:11136 起）的方法体里就是那句
  --     `crimson = genRand.Next(2) == 0; if (WorldGenParam_Evil == 0/1) { … }`，
  --     所以 **Reset 的 prefix 是改写邪恶类型的唯一正确时机**；
  --     同一方法的 **postfix** → 标记「即将生成」。
  --   · 进世界后由 40_world 的 `Main.UpdateTimeRate` postfix 每帧派发 `world` 阶段
  --     （同一方法只能有一个主人，这里登记阶段函数）；读
  --     `WorldGen.generatingWorld`（bool public static，非 const，0x1A8）：
  --     它已是 false → 判定「生成完成」→ 建任务队列。
  --   · 队列每帧只花固定预算：方块扫描每帧 `wgen_budget` 格、特征类每帧 1 个；
  --     约每 10 秒播一次进度；关掉开关立刻中断；数量一律在计划层夹取。
  --
  -- 【不可逆项：世界大小 / 邪恶类型】（设计稿 §5，README 必须醒目警告）
  --   · 世界大小：在 `WorldGen.CreateNewWorld` / `WorldGen.GenerateWorld` 的 prefix 里
  --     调 `WorldGen.SetWorldSize(int)` + `setWorldSize()`（后者补 bottomWorld /
  --     rightWorld / maxSectionsX / maxSectionsY）—— 那时 `clearWorld()` 还没按尺寸
  --     分配数组。若能解析出无命名空间的 `GUIWorldCreateMenu` 类型，再把实例字段
  --     `worldSize` 一起写上（多一条路；失败只降级）。**只对新建世界生效。**
  --   · 邪恶类型：`WorldGenParam_Evil`（-1 随机 / 0 腐化 / 1 猩红，与 PC 源码一致）
  --     + `WorldGen.crimson`（bool）。在 Reset prefix 写。
  --   ★ 本域**不写** GUI 的 evilType 字段：它的编号规则在手机版元数据里查不到
  --     （只有字段声明、方法体是桩），写错会把玩家的选择改反 —— 邪恶类型走
  --     WorldGenParam_Evil 这一条权威通道。
  --
  -- 【图块读写】（设计稿 §7）
  --   · **只读不写**：清除一律走 `WorldGen.KillTile` + `WorldGen.SquareTileFrame`
  --     （先读后写，绝不盲写内存）。
  --   · 快通道：`TileData.TileLookup / TileType / TileSHeader`（Android 原生数组，
  --     field_pointer + ptr_deref + mem_read_values/mem_read），抄 `参考库/lua/chaos-gen`。
  --   · 托管回退：`Framing.GetTileSafely(int,int)` → `Tile.get_type()`。
  --     ★ 手机版 `Tile.type` 是**属性**（符号表带 [属性]，get_type/set_type），
  --       所以必须走 get_property + property_get_method + 实例调用，不能用 get_field。
  --   · ★★ 安全闸：快通道必须先在若干坐标上与托管路径**对拍一致**才启用。
  --     指针错位宁可不用（退回托管路径），绝不拿「读错的值」去删方块。
  --
  -- ★ 默认全关（新设置项默认 = 不干预 / 0 个 / 原版）：默认路径上本域一行都不执行。
  -- ============================================================================

  -- 与 chaos-gen 一致的常量
  local ACTIVE_MASK = 0x20          -- Tile.sTileHeader 的 bit5 = active
  local NO_TILE = 0xFFFFFFFF
  local MAX_TILE_INDEX = 0x10000000

  -- 快通道指针（只有探测 + 对拍都通过才有值；换世界后重新探测）
  local p_lookup, p_type, p_sheader
  local WG                          -- ★ 前向声明：下面的回调体要引用域名表


  -- ---------------------------------------------------------------- 小工具
  local function rand_int(lo, hi)
      if hi < lo then lo, hi = hi, lo end
      return lo + math.random(hi - lo + 1) - 1
  end

  local function world_size()
      local mx, my = fget("max_tiles_x"), fget("max_tiles_y")
      if type(mx) ~= "number" or type(my) ~= "number" or mx < 1 or my < 1 then return nil end
      return mx, my
  end

  -- 需要**返回值**的静态方法调用：invoke_checked 会丢掉返回值，所以这里单开一个。
  -- 一样做句柄判空 + 实参个数核对（红线 3 / 4），失败返回 nil。
  local function invoke_value(method, argc, ...)
      if not method then return nil end
      if patch.method_param_count then
          local okc, n = pcall(patch.method_param_count, method)
          if okc and type(n) == "number" and n ~= argc then return nil end
      end
      local args = table.pack(...)
      if args.n ~= argc then return nil end
      local ok, a, b = pcall(patch.invoke, method, table.unpack(args, 1, args.n))
      if not ok then return nil end
      return a, b
  end


  -- 实例方法的返回值调用（属性 getter 用）：形参必须是 0 个
  local function invoke_instance_value(method, inst)
      if not method or not inst then return false, nil end
      if patch.method_param_count then
          local okc, n = pcall(patch.method_param_count, method)
          if okc and type(n) == "number" and n ~= 0 then return false, nil end
      end
      local ok, v = pcall(patch.invoke, method, inst)
      if not ok then return false, nil end
      return true, v
  end

  local function in_world(x, y, fluff)
      if not M.wg_in_world then return true end       -- 句柄缺失时退化为不检查（InWorld 只判边界）
      return invoke_value(M.wg_in_world, 3, x, y, fluff or 0) == true
  end

  local function empty_area(x1, x2, y1, y2)
      if not M.wg_empty_check then return true end    -- 缺失时退化为不检查
      return invoke_value(M.wg_empty_check, 5, x1, x2, y1, y2, -1) == true
  end

  -- ★ v10：「是不是实心方块」只走这里 —— WorldGen.SolidTile(int, int, bool)（3 个标量参、bool 返回）。
  --   句柄缺席返回 nil = 不知道，调用方按「不检查 / 交给原版自己判」处理（与旧版同源）。
  local function solid_tile(x, y)
      if not M.wg_solid_tile then return nil end
      local ok, v = pcall(patch.invoke, M.wg_solid_tile, x, y, false)
      if not ok then return nil end
      if v == true then return true end
      if v == false then return false end
      return nil
  end

  -- ★★ v10：宝石洞的前置校验（原版 GemCaves 那一趟的前置条件，PC WorldGen.cs:17569-17580）★★
  --   原版先 countTiles(x, y, jungle=false, lavaOk=false) 数「这一点所在连通空腔有多大」，
  --   要求 50 <= n < 300 且没有岩浆 / 冰、并且落点在岩石里，才敢调 gemCave()。
  --   少了这一步就是灾难：gemCave 内部的 Spread.Gem(x,y) 是**没有上限的洪水填充** ——
  --   从一块连通的空气出发，会把整个世界连在一起的空气（含天空与地表）全变成宝石洞的墙。
  --   这正是用户实测的「运行后持久卡顿，恢复后整个世界变成一个宝石洞」。
  --   countTiles(int,int,bool,bool) 全是标量参、返回 int，可以放心调；但它用
  --   WorldGen.maxTileCount（public static int，非 const）当上限，调用前必须先写 300。
  local GEM_MIN, GEM_MAX = 50, 300
  local gem_guard_warned = false
  local function gem_site_ok(x, y)
      if not M.wg_count_tiles then return false, "取不到 WorldGen.countTiles" end
      -- ★ 注意：fset_if 返回 false 有两种含义（写失败 / 值本来就对），必须再读一次确认，
      --   否则第二次调用起就永远「写不进去」→ 宝石洞被自己的守卫挡死。
      if not fset_if("wg_max_tile_count", nil, GEM_MAX) and fget("wg_max_tile_count") ~= GEM_MAX then
          if not gem_guard_warned then
              gem_guard_warned = true
              warn_once("wg_gem_nomax", "地图生成：写不了 WorldGen.maxTileCount → "
                  .. "宝石洞的前置校验无法进行，本版**不再生成宝石洞**（宁可不生成，也不炸世界）")
          end
          return false, "写不了 WorldGen.maxTileCount"
      end
      local n = invoke_value(M.wg_count_tiles, 4, x, y, false, false)
      if type(n) ~= "number" then return false, "countTiles 没返回数字" end
      if n < GEM_MIN or n >= GEM_MAX then
          return false, string.format("连通空腔 %d 格（原版要求 %d ~ %d）", n, GEM_MIN, GEM_MAX - 1)
      end
      local lava, ice, rock = fget("wg_lava_count"), fget("wg_ice_count"), fget("wg_rock_count")
      if type(lava) == "number" and lava > 0 then return false, "点上有岩浆" end
      if type(ice) == "number" and ice > 0 then return false, "点上有冰" end
      if type(rock) == "number" and rock <= 0 then return false, "点不在岩石里" end
      return true, n
  end

  -- ★ v10：地表高度（Main.worldSurface 是 public static double，0x470，非 const）。
  --   读不到就退化成「图高的 25%」—— 只用于**取点范围**，绝不拿它当写入依据。
  local function world_surface()
      local mx, my = world_size()
      if not mx then return nil end
      local ws = fget("world_surface")
      if type(ws) ~= "number" or ws < 100 or ws > my then ws = my * 0.25 end
      return mx, my, ws
  end

  -- ---------------------------------------------------------------- 图块读取
  -- ★★ v10 崩溃修复（本版最高优先级）★★
  --   旧版有一条「托管回退」：Framing.GetTileSafely(int,int)（**返回 Tile 结构体**）
  --   → Tile.get_type()（**拿结构体当 this 的实例方法**）。两条都踩在
  --   05-写法与陷阱 §4.3「不要把结构体交给反射」上：内核要把值类型的返回值 / 接收者
  --   编组成托管对象，一旦解释错就是野指针 → SIGSEGV。
  --   ★ 反证（用户实测，吻合度 100%）：会崩的正好是**唯一会调用这个函数**的那几项 ——
  --     矿脉 / 陨石矿脉 / 埋藏宝箱（自己读图块）、云岛 / 云湖（默认埋宝箱 → 读图块找落脚点）；
  --     而浮空岛（chest=false）/ 大理石堆 / 神庙祭坛 / 暗影球 / 洞穴 / 水晶 / 微光
  --     一次都没调用过它，也一次都没崩过。
  --   → 本版**彻底删掉托管回退**：
  --     · 需要图块**类型**的只有「生成后清除 / 替换」两个开关 → 只走原生数组快通道；
  --       快通道没通过对拍就一项都不读（那两个开关直接跳过并播报，绝不盲删、绝不盲改）；
  --     · 只需要「是不是实心」的判断 → 走 WorldGen.SolidTile（3 个标量参、返回 bool），
  --       全程不碰任何结构体。
  --   ★ 原生数组快通道是纯内存读（field_pointer + ptr_deref + mem_read_values），
  --     与参考库 chaos-gen / vein-miner 同款，不涉及托管对象编组，是安全的。

  -- 快通道能力探测（**懒执行**：只在进世界后第一次要用时探一次，setup 阶段零游戏调用）
  local function probe_fast()
      if mem.wg_fast_probe ~= nil then return mem.wg_fast_probe end
      mem.wg_fast_probe = false
      if not (patch.field_pointer and patch.ptr_deref
          and patch.mem_read_values and patch.mem_read) then return false end
      if not (F.td_lookup and F.td_type and F.td_sheader) then return false end
      local ok1, l = pcall(patch.field_pointer, F.td_lookup, nil)
      local ok2, t = pcall(patch.field_pointer, F.td_type, nil)
      local ok3, s = pcall(patch.field_pointer, F.td_sheader, nil)
      if not (ok1 and ok2 and ok3 and l and t and s) then return false end
      p_lookup, p_type, p_sheader = l, t, s
      mem.wg_fast_probe = true
      return true
  end

  -- ★ v8：快通道读取原语（**只读**）：TileLookup[y*maxTilesX+x] → idx → TileSHeader[idx] / TileType[idx]
  --   旧版是「一格两次 mem_read + 两次字符串分配」——一行 8400 格就是 16800 次原生调用 +
  --   16800 个短字符串，全图扫描的耗时与 GC 压力几乎全在这里。现在改成：
  --     · 一行只 ptr_deref 一次（拿 TileLookup / TileType / TileSHeader 三个数组基址）；
  --     · TileSHeader / TileType 按 64 格一块批量读（mem_read_values）进缓存，命中零原生调用。
  --   同量级扫描所需的原生调用数降到约 1/30，语义与逐格读完全一致（两条路已对拍过）。
  local FAST_CHUNK = 64
  local fast_chunk = { base = -1, cnt = nil, sh = nil, ty = nil }

  local function fast_forget_chunk()
      fast_chunk.base, fast_chunk.cnt, fast_chunk.sh, fast_chunk.ty = -1, nil, nil, nil
  end

  -- 取一行：TileLookup[y*mx+x] → 下标（uint32）。三个数组基址随行一起缓存。
  local function fast_row(y, mx)
      if mem.wg_row_y ~= y or mem.wg_row_mx ~= mx or type(mem.wg_row) ~= "table" then
          local okd, lookup = pcall(patch.ptr_deref, p_lookup, 0)
          local okd2, types = pcall(patch.ptr_deref, p_type, 0)
          local okd3, sheader = pcall(patch.ptr_deref, p_sheader, 0)
          if not (okd and okd2 and okd3) or not (lookup and types and sheader) then return nil end
          local okr, r = pcall(patch.mem_read_values, lookup, y * mx * 4, mx, "uint32")
          if not okr or type(r) ~= "table" then return nil end
          mem.wg_row, mem.wg_row_y, mem.wg_row_mx = r, y, mx
          mem.wg_types, mem.wg_sheader = types, sheader
      end
      return mem.wg_row, mem.wg_types, mem.wg_sheader
  end

  -- 从 64 格一块的缓存里取 idx 的 (sTileHeader, tileType)；未命中就整块读一次
  -- ★ v10：total = 图块池长度（= maxTilesX × maxTilesY），最后一块按剩余长度截断 ——
  --   旧版固定读 64 格，在图块池最末尾会**多读最多 63 格**（跨到别的堆块上），
  --   指针落在未映射页上就是 SIGSEGV。现在永远不越过数组末尾。
  local function fast_chunk_at(idx, types, sheader, total)
      local base = math.floor(idx / FAST_CHUNK) * FAST_CHUNK
      local cnt = FAST_CHUNK
      if type(total) == "number" and base + cnt > total then cnt = total - base end
      if cnt < 1 then return nil end
      if fast_chunk.base ~= base or fast_chunk.cnt ~= cnt or type(fast_chunk.sh) ~= "table" then
          local ok1, sh = pcall(patch.mem_read_values, sheader, base * 2, cnt, "int16")
          local ok2, ty = pcall(patch.mem_read_values, types, base * 2, cnt, "uint16")
          if not (ok1 and ok2 and type(sh) == "table" and type(ty) == "table") then
              fast_forget_chunk()
              return nil
          end
          fast_chunk.base, fast_chunk.cnt, fast_chunk.sh, fast_chunk.ty = base, cnt, sh, ty
      end
      local sh = fast_chunk.sh[idx - base + 1]
      local ty = fast_chunk.ty[idx - base + 1]
      if type(sh) ~= "number" or type(ty) ~= "number" then return nil end
      return sh, ty
  end

  local function read_tile_fast(x, y, mx, row, types, sheader, total)
      if not (row and types and sheader) then return nil end
      local idx = row[x + 1]
      if type(idx) ~= "number" then return nil end
      if idx == NO_TILE then return 0 end
      if idx < 0 or idx >= MAX_TILE_INDEX then return nil end
      local sh, ty = fast_chunk_at(idx, types, sheader, total)
      if sh == nil then return nil end
      if (sh & ACTIVE_MASK) == 0 then return 0 end
      return ty
  end

  -- ★ v10：原生快通道的底层读（不检查「有没有通过对拍」，只给 verify_fast 与 read_tile_at 用）
  local function fast_read(x, y, mx, my)
      local row, types, sheader = fast_row(y, mx)
      if not row then return nil end
      return read_tile_fast(x, y, mx, row, types, sheader, mx * my)
  end

  -- 读某一格（尺寸已知时用这个，扫描热路径走它，避免每格重取世界尺寸）
  -- 返回 0 = 空气；非 0 = 图块编号；nil = **读不到**（快通道没通过对拍 / 原生数组取不到）
  -- ★ v10：nil 的语义变严了 —— 旧版 nil 会退到结构体反射路径（那是崩溃源），现在 nil 就是
  --   「读不到」，调用方必须自己决定放弃（清除 / 替换两个开关就是这么做的）。
  local function read_tile_at(x, y, mx, my)
      if x < 0 or y < 0 or x >= mx or y >= my then return nil end
      if mem.wg_fast ~= true then return nil end
      return fast_read(x, y, mx, my)
  end

  local function read_tile_type(x, y)
      local mx, my = world_size()
      if not mx then return nil end
      return read_tile_at(x, y, mx, my)
  end

  -- ★★ 安全闸：快通道与托管路径对拍。不一致 / 样本太少 → 关死快通道，退回托管路径。
  --   （托管路径也拿不到时才真的没有读取能力 → 调用方必须放弃「清除」任务，绝不盲删。）
  -- ★ v8：「图块扫描·分块批量读」关掉时直接走托管路径；每次启用/换世界先清掉分块与行缓存
  --   （TileData 的数组基址在换世界后可能已经变了）。
  local function verify_fast()
      if mem.wg_fast_verified then return mem.wg_fast == true end
      fast_forget_chunk()
      mem.wg_row, mem.wg_row_y, mem.wg_row_mx = nil, nil, nil
      mem.wg_types, mem.wg_sheader = nil, nil
      local function off(why)
          mem.wg_fast, mem.wg_fast_verified = false, true
          p_lookup, p_type, p_sheader = nil, nil, nil
          if why then
              warn_once("wg_fast_off", "地图生成：原生数组快通道不可用（" .. tostring(why)
                  .. "）→「生成后清除 / 替换」本次整体跳过（★ v10 起不再退回结构体反射路径，"
                  .. "绝不盲删盲改）")
          end
          return false
      end
      if P.wgen and P.wgen.quick_scan == false then
          return off("设置里关掉了「图块扫描·分块批量读」")
      end
      if not probe_fast() then return off("取不到 TileData 的三个原生数组") end
      local mx, my = world_size()
      if not mx then return false end
      if not M.wg_solid_tile then return off("取不到 WorldGen.SolidTile，无法对拍") end
      -- ★ v10：对拍对象换成 WorldGen.SolidTile（标量参 + bool 返回，绝不碰结构体）。
      --   三条判据，缺一不可：
      --     ① 高空样本必须读出 0（空气）；
      --     ② 最底层样本必须读出非 0；
      --     ③ 纵扫若干列，「读出非 0 == 原版实心」的一致率 ≥ 70%
      --        （不一致只可能来自平台 / 植物这类「非实心但有图块」的少数格）。
      --   指针算错时 ① ② 基本必错，③ 会掉到 50% 附近 —— 三条一起就是很强的闸门。
      local total = mx * my
      local n, agree, bad = 0, 0, nil
      local x0 = math.floor(mx * 0.5)
      for k = 1, 24 do
          local y = 40 + math.floor((my - 80) * (k - 0.5) / 24)
          local x = x0 + ((k % 7) - 3) * 37
          if x < 2 then x = 2 end
          if x > mx - 3 then x = mx - 3 end
          local row, types, sheader = fast_row(y, mx)
          local a = read_tile_fast(x, y, mx, row, types, sheader, total)
          local b = solid_tile(x, y)
          if a ~= nil then
              n = n + 1
              if type(b) == "boolean" then
                  if (a ~= 0) == b then
                      agree = agree + 1
                  elseif not bad then
                      bad = string.format("(%d,%d) 读出=%d 原版实心=%s", x, y, a, tostring(b))
                  end
              end
          end
      end
      local sky_ok, deep_ok = false, false
      for k = 1, 8 do
          local sx = math.floor(mx * 0.2) + k * 11
          if fast_read(sx, 3 + k, mx, my) == 0 then sky_ok = true end
          if (fast_read(sx, my - 4 - k, mx, my) or 0) ~= 0 then deep_ok = true end
      end
      if fast_read(math.floor(mx * 0.5), 5, mx, my) == 0 then sky_ok = true end
      fast_forget_chunk()
      mem.wg_row, mem.wg_row_y, mem.wg_row_mx = nil, nil, nil
      mem.wg_types, mem.wg_sheader = nil, nil
      if n < 12 then return off("样本太少（只读到 " .. n .. " 个）") end
      if not sky_ok then return off("高空样本读出来不是空气") end
      if not deep_ok then return off("最底层样本读出来是空的") end
      if agree * 100 < n * 70 then
          return off("与 WorldGen.SolidTile 的一致率只有 " .. math.floor(agree * 100 / n) .. "%"
              .. (bad and ("，首个反例 " .. bad) or ""))
      end
      mem.wg_fast = true
      if log_allowed() then
          mod.info("地图生成：原生数组快通道已通过对拍（" .. n .. " 个样本，与 SolidTile 一致 "
              .. agree .. " 个）")
      end
      return true
  end

  -- ---------------------------------------------------------------- 特征放置
  -- ★ v9：一键操作的临时选项表。所有放置函数统一经 wopt() 取参数：
  --   · 设置驱动的任务 → WGADHOC 为 nil → 读 P.wgen（v6~v8 的老行为，一字不改）；
  --   · 一键操作的任务 → WGADHOC = 当场生成的一张选项表（不依赖「地图生成专项」是否打开）。
  --   ★ 声明在放置函数**之前**：Lua 的词法作用域要求引用处的 local 已声明（静态自检会抓）。
  local WGADHOC = nil
  local function wopt() return WGADHOC or P.wgen or {} end

  -- 每个函数返回 true = 这次真的放置了；false = 换下一帧再试（调用方有重试上限）
  local function place_life()
      if not M.wg_add_life then return false end
      local mx, my = world_size(); if not mx then return false end
      local x = rand_int(120, mx - 121)
      local y = rand_int(math.floor(my * 0.25), my - 120)
      if not in_world(x, y, 40) then return false end
      return invoke_value(M.wg_add_life, 2, x, y) == true
  end

  local function place_mana()
      if not M.wg_add_mana then return false end
      local mx, my = world_size(); if not mx then return false end
      local x = rand_int(120, mx - 121)
      local y = rand_int(math.floor(my * 0.25), my - 120)
      if not in_world(x, y, 40) then return false end
      return invoke_value(M.wg_add_mana, 2, x, y) == true
  end

  -- ★ v8：结构放置后补图块框架。
  --   原版的补框架步骤只在世界生成期间跑；本模组是**生成完成之后**才放结构的，
  --   所以必须自己调一次 WorldGen.SectionTileFrame（4 参，手机版符号表已核实）把那一整段重 frame，
  --   否则新放的方块贴图可能不连续（看着像破的）。
  --   参数是**闭区间**端点（PC 源码语义）：调用方传的就是区域右下角，这里只负责夹到世界范围内。
  local function frame_area(x1, y1, x2, y2)
      if not (M.wg_section_frame and may_write()) then return end
      local mx, my = world_size(); if not mx then return end
      if x1 < 0 then x1 = 0 end
      if y1 < 0 then y1 = 0 end
      if x2 > mx - 1 then x2 = mx - 1 end
      if y2 > my - 1 then y2 = my - 1 end
      if x2 < x1 or y2 < y1 then return end
      if invoke_checked(M.wg_section_frame, 4, x1, y1, x2, y2) then
          dcount(WG, "补图块框架", 1)
      end
  end

  -- ★ v8：在结构（云岛 / 云湖）上找一个落脚点放宝箱。
  --   ★ v10：实心判定改走 WorldGen.SolidTile（标量参 + bool），**不再读图块编号** ——
  --   这条路径原来正是「云岛 / 云湖一点就崩」的现场（它调的 read_tile_at 落到结构体反射上）。
  local function chest_on_surface(x, y, mx, my)
      if not M.wg_place_chest then return false end
      local w = wopt()
      local style = (w and w.chest_style) or 0
      local offsets = { 0, -3, 3, -6, 6 }
      for i = 1, #offsets do
          local cx = x + offsets[i]
          if cx > 3 and cx < mx - 4 then
              local solid = nil
              for yy = y - 30, y + 70 do
                  local s = solid_tile(cx, yy)
                  if s == nil then break end          -- 读不到实心判定 → 放弃这一列（绝不盲放）
                  if s then solid = yy break end
              end
              if solid and solid > 3 and solid < my - 3 and solid_tile(cx, solid - 1) == false then
                  local ok, idx = invoke_value(M.wg_place_chest, 5, cx, solid - 1, 21, true, style)
                  if ok and type(idx) == "number" and idx >= 0 then
                      dcount(WG, "云岛宝箱", 1)
                      return true
                  end
              end
          end
      end
      return false
  end

  -- 浮空岛 / 云岛 / 云湖：都要求目标区域是空的（EmptyTileCheck 返回 true = 整片空）
  -- ★★ v8：「岛都是光秃秃的」修复 ★★
  --   原版浮空岛是**两趟**生成的：FloatingIslands 那趟只调 CloudIsland / CloudLake 画地形，
  --   房子 + 宝箱 + 家具在下一趟 FloatingIslandHouses 里由 WorldGen.IslandHouse(x, y, style) 铺，
  --   而且用的是**同一个 (x, y)**（PC WorldGen.cs:13169-13177 记下 X/Y/Style，17997 再原样调）。
  --   旧版只调了前半趟，所以额外生成的岛全是空壳。
  --   opts.house = 补 IslandHouse；opts.chest = 再找一个落脚点埋宝箱；opts.style = 家具样式
  -- ★★ v10：落点规则与地形函数一起大修 ★★
  --   ① 落点 y 必须在**地表以上的天空**。原版（WorldGen.cs:13071-13105）先在该列从 y=200
  --      往下找第一个实心方块（= 地表高度 num6），再取 y = rand(90, num6 − 100)，
  --      最后夹一次 y ≤ worldSurfaceLow − 50。旧版用「图高的 8%~35%」：小世界上这个区间
  --      会落到地面以下，云被塞进地里，观感与判据全错。
  --   ② x ∈ [10%, 90%] 且避开正中 ±150 格（原版 :13029-13041）。
  --   ③ 地形函数改成 **CloudIsland / CloudLake**：WorldGen.FloatingIsland 在 1.4.5.8 里是
  --      **死代码**（全 PC 源码只有定义、零调用点），它只画一个土核 —— 这正是用户实测
  --      「只有一个土岛的核心 + 上面的房子，没有云、没有各种生态元素」的根因。
  --      原版真正调用的是 CloudIsland（云 + 土 + 草 + 树 + 湖水）/ CloudLake（天空湖）。
  local function sky_y()
      local mx, my, ws = world_surface()
      if not mx then return nil end
      local w = wopt()
      local delta = w.sky_delta or 100        -- 离地表至少多少格（越大越高）
      local y_lo = 90
      local y_hi = math.floor(ws) - delta
      if y_hi < y_lo + 20 then y_hi = y_lo + 20 end
      if y_hi > my - 60 then y_hi = my - 60 end
      return y_lo, y_hi
  end
  local function place_sky(method, span, opts)
      if not method then return false end
      local mx, my = world_size(); if not mx then return false end
      local y_lo, y_hi = sky_y()
      if not y_lo then return false end
      -- 一次调用最多试 opts.tries 个落点（原版同样是死循环重试，把重试放在这里收敛更快）
      for _ = 1, (opts.tries or 8) do
          -- 避开正中 ±150 格（原版 :13029-13041）。★ v10 加一层自适应：只有两侧都留有
          -- 足够宽的可用区间时才排除正中 —— 否则在窄世界（或假内核的小世界）里一个合法落点
          -- 都选不出来。真机世界最小 4200 格，永远走「排除正中」这条路。
          local lo, hi = math.floor(mx * 0.1), math.floor(mx * 0.9)
          local c1, c2 = math.floor(mx / 2) - 150, math.floor(mx / 2) + 150
          local x
          if (c1 - lo) > 20 and (hi - c2) > 20 then
              if math.random() < 0.5 then x = rand_int(lo, c1) else x = rand_int(c2, hi) end
          else
              x = rand_int(lo, hi)
          end
          local y = rand_int(y_lo, y_hi)
          if in_world(x, y, 60) and empty_area(x - span, x + span, y - 6, y + 6) then
              if invoke_checked(method, 2, x, y) then
                  if opts.house and M.wg_island_house then
                      if invoke_checked(M.wg_island_house, 3, x, y, opts.style or 0) then
                          dcount(WG, "岛上天空房", 1)
                      end
                  end
                  if opts.chest then pcall(chest_on_surface, x, y, mx, my) end
                  if wopt().reframe then
                      frame_area(x - span - 40, y - 60, x + span + 40, y + 60)
                  end
                  return true
              end
          end
      end
      return false
  end

  -- ★ v10：浮空岛 = 原版的 CloudIsland（含云 / 土 / 草 / 树 / 小湖）。
  --   原来用的 M.wg_island（WorldGen.FloatingIsland）是死代码，只画土核 —— 见上面 ③。
  local function island_method() return M.wg_cloud_island or M.wg_island end

  local function place_island()
      local w = wopt()
      return place_sky(island_method(), 14,
          { house = w.island_house, chest = w.cloud_chest, style = w.island_style or 0, tries = 8 })
  end
  local function place_cloud_island()
      local w = wopt()
      return place_sky(island_method(), 14,
          { house = w.island_house, chest = w.cloud_chest, style = w.island_style or 0, tries = 8 })
  end
  local function place_cloud_lake()
      local w = wopt() or {}
      -- ★ 原版的天空房那趟会跳过云湖（skyLake[i] = true），所以这里也不补房子
      return place_sky(M.wg_cloud_lake, 10,
          { house = false, chest = w.cloud_chest, style = w.island_style or 0, tries = 8 })
  end

  -- ★ v8：「地下结构的生成深度」设置。只有玩家选了浅层 / 深层 / 全程才覆盖；
  --   选「标准」时各功能保持自己原来的原版范围。
  local function und_lo(dflt)
      local w = wopt()
      if w and w.under_lo then return w.under_lo end
      return dflt
  end
  local function und_hi(dflt)
      local w = wopt()
      if w and w.under_hi then return w.under_hi end
      return dflt
  end

  local function place_cave()
      if not M.wg_caverer then return false end
      local mx, my = world_size(); if not mx then return false end
      local x = rand_int(120, mx - 121)
      local y = rand_int(math.floor(my * und_lo(0.28)), math.floor(my * und_hi(0.92)))
      if not in_world(x, y, 40) then return false end
      return invoke_checked(M.wg_caverer, 2, x, y)
  end

  -- 矿脉：TileRunner(i, j, strength, steps, type, addTile, speedX, speedY, noYChange,
  --                  overRide, ignoreTileType) —— 11 个标量参，已核实。
  local function place_ore(t)
      if not M.wg_tile_runner then return false end
      local mx, my = world_size(); if not mx then return false end
      local x = rand_int(120, mx - 121)
      local y = rand_int(math.floor(my * und_lo(0.20)), math.floor(my * und_hi(0.85)))
      if not in_world(x, y, 40) then return false end
      -- ★ v10：先确认这一点在实心方块里才下钻 —— WorldGen.SolidTile（标量参 + bool），
      --   不再读图块编号。句柄缺席（返回 nil）时保持旧行为：交给原版自己判。
      if solid_tile(x, y) == false then return false end
      local strength = 5.0 + rand_int(0, 6)
      local steps = rand_int(3, 9)
      return invoke_checked(M.wg_tile_runner, 11, x, y, strength, steps, t.ore_type,
          true, 0.0, 0.0, false, true, -1)
  end

  local function place_shimmer()
      if not M.wg_shimmer_biome then return false end
      local mx, my = world_size(); if not mx then return false end
      local x = rand_int(200, mx - 201)
      local y = rand_int(math.floor(my * und_lo(0.30)), math.floor(my * und_hi(0.90)))
      if not in_world(x, y, 80) then return false end
      return invoke_value(M.wg_shimmer_biome, 2, x, y) == true
  end


  -- ---------------------------------------------------------------- v7 新特征（宝箱 / 结构 / 替换 / 诊断）
  -- ★★ 这些全部包在一个嵌套函数里（只留 WGST / V7 两个 local）★★
  --   Lua 5.4 主 chunk 也是一个函数，“活着的 local”上限 200；
  --   86 号分片本来就很长，若把新加的 20 多个函数都当成包裹块的 local，
  --   会直接撞上这个上限（实测：tests 里 main.lua:4813 报
  --   "too many local variables (limit is 200)"）。放进 IIFE 后它们只是内层函数的 local。
  local WGST = { pending = false, gen = false, arm = 0, readback = "", maxage = 216000 }

  local V7 = (function()
      -- 只关心「这次放成功了没有」的静态调用
      -- （void 方法返回 nil；bool 方法返回 false = 没放成）
      local function invoke_ok(method, argc, ...)
          if not method then return false end
          if patch.method_param_count then
              local okc, n = pcall(patch.method_param_count, method)
              if okc and type(n) == "number" and n ~= argc then return false end
          end
          local args = table.pack(...)
          if args.n ~= argc then return false end
          local ok, a = pcall(patch.invoke, method, table.unpack(args, 1, args.n))
          if not ok then return false end
          if a == false then return false end
          return true
      end

      local function place_chest(t)
          if not M.wg_buried_chest then return false end
          local mx, my, ws = world_surface(); if not mx then return false end
          -- ★★ v10.1 崩溃修复（真机反馈：只有埋藏宝箱仍然崩）★★
          --   PC WorldGen.cs:36504-36509：
          --     if (chestTileType == 21 && (chestStyle == 4 ||
          --         (num7 > Main.maxTilesY - 205 && num10 == 0)))
          --         → num10 = GenVars.hellChestItem[GenVars.hellChest];
          --   而 GenVars.hellChestItem 只在**世界生成期间**被赋值（WorldGen.cs:11286 的
          --   GenVars.hellChestItem = list2.ToArray()）—— 生成完成之后它是 **null**，
          --   下标访问就是 NullReferenceException → 异常穿出原生帧 → SIGABRT（pcall 拦不住）。
          --   旧版的 y 区间是 [图高 35%, 图高−120]，大世界会探到最底下 205 格（地狱层）→ 偶发崩。
          --   ⇒ 落点必须避开最底下 420 格（比原版判据 205 再多留一倍余量），
          --     并且**样式禁止 4**（4 号样式无条件走这条路，与深度无关）。
          local y_lo = math.floor(ws) + 40
          local y_hi = my - 420
          if y_hi <= y_lo + 20 then
              -- 极小世界兜底（真机世界最小 1200 高，永远走上面那条 420 余量）：
              -- 假内核 400x300 那种尺寸下 my-420 是负数，给一条仍然在地表以下的窄带。
              y_lo = math.min(my - 260, math.floor(ws) + 40)
              y_hi = math.min(my - 40, y_lo + 200)
          end
          if y_hi <= y_lo + 5 then return false end
          local x = rand_int(120, mx - 121)
          local y = rand_int(y_lo, y_hi)
          if not in_world(x, y, 40) then return false end
          -- ★ v10：先读后写 —— 走 WorldGen.SolidTile（标量参 + bool），不再读图块编号。
          local sv = solid_tile(x, y)
          if sv == nil or sv == false then return false end
          local style = tonumber(t.chest_style) or -1
          if style == 4 then style = 3 end        -- 4 号 = 地狱宝箱分支（见上）→ 换 3 号
          -- notNearOtherChests = false：生成完成后没必要做 Chest.NearOtherChests 的 50x16 扫描，
          --   而且它走 Framing.GetTileSafely（本版刻意一步都不碰托管 Tile 路径）。
          -- trySlope = false：那是给世界生成用的半砖校正，生成后不需要，少动一处图块。
          return invoke_ok(M.wg_buried_chest, 7, x, y, t.chest_item or 0,
              false, style, false, 21) == true
      end

      -- 结构类统一入口（地下那一类）：只做边界检查，落点是否合适交给原版自己判。
      -- ★ v8：band = true 时把深度范围交给「地下结构的生成深度」设置覆盖。
      -- ★ v10：一次调用里多试几个候选点 —— 原来每帧只掷一次骰子，连续 60 次找不到就
      --   放弃整条任务；原版自己也是「重试到成功为止」的死循环。
      local function place_grid(method, argc, y_lo, y_hi, band, tries)
          if not method then return false end
          local mx, my = world_size(); if not mx then return false end
          if band then y_lo, y_hi = und_lo(y_lo), und_hi(y_hi) end
          local ya = math.floor(my * y_lo)
          local yb = math.floor(my * y_hi)
          if yb <= ya then yb = ya + 1 end
          for _ = 1, (tries or 12) do
              local x = rand_int(200, mx - 201)
              local y = rand_int(ya, yb)
              if in_world(x, y, 60) and invoke_ok(method, argc, x, y) then return true end
          end
          return false
      end

      -- ★★ v10：地表结构（矿斑 / 石斑 / 贝壳堆 / 绿洲 / 大理石堆）的落点规则 ★★
      --   原版调用点（PC WorldGen.cs）：
      --     · OrePatch             :18603  y = genRand.Next(worldSurfaceLow, worldSurface)
      --     · StonePatch           :18635  y = genRand.Next(worldSurfaceLow, worldSurface)
      --     · PlaceOasis           :16355  y = genRand.Next(100, (int)worldSurface)
      --     · MarblePileWithStatues:16391  y = (int)(worldSurface / 2)
      --     · ShellPile            :16439  y = shellStartY − 50（海滩沙地正上方 50 格）
      --   共同点：**y 必须落在地表以上的空气里**。这些函数进去第一件事都是
      --   「while (!SolidTile(X, num)) num++」（从 Y 往下找第一块实心），紧接着
      --   「if (num > Main.worldSurface) return false;」。旧版给的是「图高的 25%~85%」
      --   （地下深处）→ num 立刻超过 worldSurface → **必然 false** →
      --   用户看到的「每个世界都找不到可生成的点、放置特征 0 个」就是这一条。
      --   现在按地表带取点，并且一次调用内试多个候选（原版同样靠重试）。
      local function surface_band()
          local mx, my, ws = world_surface()
          if not mx then return nil end
          local lo = 100
          local hi = math.floor(ws) - 20
          if hi < lo + 20 then hi = lo + 20 end
          if hi > my - 40 then hi = my - 40 end
          return mx, my, ws, lo, hi
      end

      -- 地表结构：在 [x_lo, x_hi] × [y_lo, y_hi] 里试 tries 个候选点
      -- avoid_center = true 时避开世界正中（原版 orePatch 避 48%~52%、stonePatch 避 47%~53%）
      local function patch_try(method, argc, x_lo, x_hi, y_lo, y_hi, avoid_center, tries)
          if not method then return false end
          local mx = world_size(); if not mx then return false end
          -- ★ v10：原版是「随机取 x，撞在正中就重取」。这里等价地直接在两翼里取；
          --   只有两翼都够宽时才排除正中（窄世界 / 假内核的小世界否则一个点都取不到）。
          local lo, hi = x_lo, x_hi
          if lo < 60 then lo = 60 end
          if hi > mx - 61 then hi = mx - 61 end
          if hi <= lo then return false end
          local c1, c2 = math.floor(mx * 0.47), math.floor(mx * 0.53)
          for _ = 1, tries do
              local x
              if avoid_center and (c1 - lo) > 20 and (hi - c2) > 20 then
                  if math.random() < 0.5 then x = rand_int(lo, c1) else x = rand_int(c2, hi) end
              else
                  x = rand_int(lo, hi)
              end
              local y = rand_int(y_lo, y_hi)
              if invoke_ok(method, argc, x, y) then return true end
          end
          return false
      end

      local function place_marble()
          local mx, my, ws = surface_band(); if not mx then return false end
          -- 原版：y = (int)(worldSurface / 2)（天空），要求往下第一块实心是土 / 石
          local yl = math.max(60, math.floor(ws * 0.35))
          local yh = math.max(yl + 10, math.floor(ws * 0.75))
          return patch_try(M.wg_marble, 2, 150, mx - 151, yl, yh, true, 40)
      end
      local function place_lihzahrd() return place_grid(M.wg_lihzahrd, 2, 0.55, 0.95, true, 12) end
      local function place_gem_cave()
          local mx, my = world_size(); if not mx then return false end
          if not M.wg_gem_cave then return false end
          local rl = fget("rock_layer")
          if type(rl) ~= "number" or rl < 100 or rl > my then rl = my * 0.35 end
          local y_lo = math.floor(rl) + 30
          local y_hi = my - 230
          if y_hi < y_lo + 20 then y_lo, y_hi = math.floor(my * 0.35), my - 60 end
          -- ★ v10：照抄原版 GemCaves 那一趟（PC WorldGen.cs:17558-17585）：
          --   y ∈ [rockLayer + 30, maxTilesY − 230]，并且**先用 countTiles 校验落点在小空腔里**
          --   （见 gem_site_ok 的长注释：少了这一步 Spread.Gem 会把整个世界淹掉）。
          --   最多试 24 个候选；都不通过就放弃 —— 宁可不生成，也绝不炸世界。
          for _ = 1, 24 do
              local x = rand_int(200, mx - 201)
              local y = rand_int(y_lo, y_hi)
              local ok, why = gem_site_ok(x, y)
              if ok then
                  if invoke_ok(M.wg_gem_cave, 2, x, y) then
                      dcount(WG, "宝石洞-空腔合格", 1)
                      return true
                  end
              elseif log_allowed() then
                  verbose("宝石洞：候选点 (" .. tostring(x) .. "," .. tostring(y)
                      .. ") 被前置校验拒绝：" .. tostring(why))
              end
          end
          return false
      end
      local function place_ore_patch()
          local mx, my, ws, lo, hi = surface_band(); if not mx then return false end
          return patch_try(M.wg_ore_patch, 2, 150, mx - 151, lo, hi, true, 40)
      end
      local function place_stone_patch()
          local mx, my, ws, lo, hi = surface_band(); if not mx then return false end
          return patch_try(M.wg_stone_patch, 2, 150, mx - 151, lo, hi, true, 40)
      end
      local function place_shell_pile()
          local mx, my, ws, lo, hi = surface_band(); if not mx then return false end
          -- 原版只在海滩（世界两端的沙地）用 GenVars.shellStartX/Y 取点；这里自己找两端。
          local yh = math.max(lo + 10, math.floor(ws) - 60)
          local right = (math.random() < 0.5)
          local x_lo, x_hi = 120, 420
          if right then x_lo, x_hi = mx - 420, mx - 120 end
          return patch_try(M.wg_shell_pile, 2, x_lo, x_hi, lo, yh, false, 60)
      end
      local function place_oasis()
          local mx, my, ws, lo, hi = surface_band(); if not mx then return false end
          -- 原版避开海滩：x ∈ [beachDistance + 300, maxTilesX − (beachDistance + 300)]
          local d = math.min(500, math.floor(mx * 0.08))
          return patch_try(M.wg_oasis, 2, d, mx - d, lo, hi, false, 60)
      end

      -- ★★ v10.2：新增的原版特征 ★★
      --   全部对着 1.4.5.8 手机版方法表核过：public static、参数全是标量（所以能 invoke）。
      --   落点是否合适由原版自己判（返回 false = 换下一个候选点，连续 60 次找不到就放弃该任务）。
      --   ★ 与原版一致的地方：这些函数进去第一件事都是「从 Y 往下找第一块合适的方块」，
      --     所以给它们「地表带 / 地下带」的 y 就够，不需要我们先读图块。
      local function place_graveyard()
          local mx, my, ws, lo, hi = surface_band(); if not mx then return false end
          return patch_try(M.wg_grave, 2, 200, mx - 201, lo, hi, false, 20)
      end
      local function place_moss() return place_grid(M.wg_moss, 2, 0.35, 0.95, true, 12) end
      local function place_glow_moss()
          if not M.wg_glow_moss then return false end
          local mx, my = world_size(); if not mx then return false end
          local y_lo = math.floor(my * und_lo(0.35))
          local y_hi = math.floor(my * und_hi(0.95))
          if y_hi <= y_lo then y_hi = y_lo + 40 end
          for _ = 1, 12 do
              local x = rand_int(200, mx - 201)
              local y = rand_int(y_lo, y_hi)
              if in_world(x, y, 60) and invoke_ok(M.wg_glow_moss, 3, x, y, my - 40) then
                  return true
              end
          end
          return false
      end
      local function place_mayan_trap() return place_grid(M.wg_mayan, 2, 0.45, 0.95, true, 24) end
      local function place_lava_trap() return place_grid(M.wg_lava, 2, 0.55, 0.98, true, 24) end
      local function place_statue_trap() return place_grid(M.wg_statue_trap, 2, 0.30, 0.95, true, 24) end
      local function place_bee_larva() return place_grid(M.wg_bee, 2, 0.25, 0.90, true, 24) end

      local function place_shadow_orb()
          if not M.wg_shadow_orb then return false end
          local mx, my = world_size(); if not mx then return false end
          local x = rand_int(150, mx - 151)
          local y = rand_int(math.floor(my * und_lo(0.25)), math.floor(my * und_hi(0.85)))
          if not in_world(x, y, 60) then return false end
          return invoke_ok(M.wg_shadow_orb, 3, x, y, false)
      end

      -- 进世界后的「读回值」——诊断世界大小 / 邪恶类型到底写进去没有
      local function read_back(w)
          local mx, my = fget("max_tiles_x"), fget("max_tiles_y")
          local cr = fget("wg_crimson")
          return string.format(
              "maxTilesX=%s maxTilesY=%s crimson=%s（设置 尺寸=%s 自定义=%s×%s 邪恶=%s）",
              tostring(mx), tostring(my), tostring(cr), tostring(w and w.size or "none"),
              tostring(w and w.cw or 0), tostring(w and w.ch or 0), tostring(w and w.evil or "none"))
      end

      -- 自定义出生点（Main.spawnTileX / spawnTileY 是属性 → setter 桥接）。只写一次。
      local function spawn_once()
          local w = P.wgen
          if not w then return end
          if not may_write() then return end
          local mx, my = world_size(); if not mx then return end
          local sx, sy = w.spawn_x or 0, w.spawn_y or 0
          if sx > 3 and sx < mx - 3 and M.spawn_x_set then
              if pcall(patch.invoke, M.spawn_x_set, sx) then dcount(WG, "出生点写入", 1) end
          end
          if sy > 3 and sy < my - 3 and M.spawn_y_set then
              if pcall(patch.invoke, M.spawn_y_set, sy) then dcount(WG, "出生点写入", 1) end
          end
      end

      -- 新世界起始时刻（只写一次）
      local function start_time()
          local w = P.wgen
          if not w or w.start == "none" then return end
          if not may_write() then return end
          local day, ticks
          if w.start == "day" then day, ticks = true, (8 - 4.5) * 3600
          elseif w.start == "dusk" then day, ticks = false, 0.0
          else day, ticks = false, (20 - 19.5) * 3600 end
          if F.dayTime then fset_if("dayTime", nil, day) end
          if F.time then fset_if("time", nil, ticks) end
          dcount(WG, "起始时刻写入", 1)
      end

      -- 武装「刚生成完一个新世界」的标记
      local function arm(why)
          if not WGST.pending then dcount(WG, "pending武装", 1) end
          WGST.pending, WGST.arm = true, stats.frames
          if log_allowed() then diag("地图生成：pending 武装（" .. tostring(why) .. "）") end
      end

      return { chest = place_chest, marble = place_marble, lihzahrd = place_lihzahrd,
               shadow_orb = place_shadow_orb, gem_cave = place_gem_cave, ore_patch = place_ore_patch,
               stone_patch = place_stone_patch, shell_pile = place_shell_pile, oasis = place_oasis,
               graveyard = place_graveyard, moss = place_moss, glow_moss = place_glow_moss,
               mayan = place_mayan_trap, lava_trap = place_lava_trap,
               statue_trap = place_statue_trap, bee_larva = place_bee_larva,
               read_back = read_back, spawn = spawn_once, start_time = start_time, arm = arm }
  end)()

  -- ---------------------------------------------------------------- 任务队列
  local function build_job()
      local mx, my = world_size()
      if not mx then return nil end
      local w = P.wgen
      local tasks = {}
      -- ★ v8：结构类节流。gap > 1 = 放成功一次之后要等 gap 帧才允许下一次。
      --   理由：FloatingIsland / CloudIsland 一次调用内部要写几十万格图块
      --   （PC WorldGen.cs 里是 20~25 轮 × 约 120×120 的双重循环），
      --   旧版「每帧 1 个」= 每帧几十万次图块写入 → 掉帧甚至崩游戏。
      local G = w.gap or 1
      if G < 1 then G = 1 end
      local H = math.floor(G / 2); if H < 1 then H = 1 end
      local function feat(name, count, fn, extra, gap)
          if count and count > 0 and fn then
              local t = { kind = "feature", name = name, left = count, tries = 0, fn = fn,
                          gap = gap or 1 }
              if extra then for k, v in pairs(extra) do t[k] = v end end
              tasks[#tasks + 1] = t
          end
      end
      feat("生命水晶", w.life, place_life)
      feat("魔力水晶", w.mana, place_mana)
      feat("浮空岛", w.islands, place_island, nil, G)
      feat("云岛", w.cloud_islands, place_cloud_island, nil, G)
      feat("云湖", w.cloud_lakes, place_cloud_lake, nil, G)
      feat("洞穴", w.caves, place_cave, nil, H)
      feat("矿脉", w.ore_veins, place_ore, { ore_type = w.ore_type })
      feat("微光群系", w.shimmer, place_shimmer)
      -- ★ v7 新特征
      feat("埋藏宝箱", w.chests, V7.chest,
          { chest_item = w.chest_item, chest_style = w.chest_style })
      feat("大理石堆", w.marble, V7.marble, nil, H)
      feat("神庙祭坛", w.lihzahrd, V7.lihzahrd, nil, H)
      feat("暗影球", w.shadow_orbs, V7.shadow_orb, nil, H)
      feat("宝石洞", w.gem_caves, V7.gem_cave, nil, H)
      feat("矿斑", w.ore_patches, V7.ore_patch, nil, H)
      feat("石斑", w.stone_patches, V7.stone_patch, nil, H)
      feat("贝壳堆", w.shell_piles, V7.shell_pile, nil, H)
      feat("绿洲", w.oases, V7.oasis, nil, H)
      -- ★ v10.2 新特征
      feat("墓地", w.graveyards, V7.graveyard, nil, G)
      feat("苔藓", w.moss, V7.moss, nil, 1)
      feat("发光苔藓", w.glow_moss, V7.glow_moss, nil, H)
      feat("神庙陷阱", w.mayan_traps, V7.mayan, nil, 1)
      feat("岩浆陷阱", w.lava_traps, V7.lava_trap, nil, 1)
      feat("雕像陷阱", w.statue_traps, V7.statue_trap, nil, 1)
      feat("蜂巢", w.bee_larva, V7.bee_larva, nil, 1)
      if w.clear_on then
          tasks[#tasks + 1] = { kind = "scan", name = "清除方块", ids = w.clear, x = 0, y = 0 }
      end
      if w.replace_on then
          tasks[#tasks + 1] = { kind = "replace", name = "方块替换", map = w.replace, x = 0, y = 0 }
      end
      -- ★ v8：特征总量安全阀（手改 config.json 填天文数字时兜底）。
      --   只削「特征」不削「清除 / 替换」—— 后两者本来就是分帧全图扫描，有独立预算。
      local cap = w.cap or 300
      local total = 0
      for i = 1, #tasks do
          if tasks[i].kind == "feature" then total = total + tasks[i].left end
      end
      if total > cap then
          local over = total - cap
          for i = #tasks, 1, -1 do
              if over <= 0 then break end
              local t = tasks[i]
              if t.kind == "feature" and t.left > 0 then
                  local cut = t.left
                  if cut > over then cut = over end
                  t.left = t.left - cut
                  over = over - cut
              end
          end
          local kept = {}
          for i = 1, #tasks do
              local t = tasks[i]
              if t.kind ~= "feature" or t.left > 0 then kept[#kept + 1] = t end
          end
          tasks = kept
          dcount(WG, "特征超上限", 1)
          chat_print(string.format(
              "[世界工坊] 地图生成专项：特征总数 %d 超过「单次生成·特征总量上限」%d，已按上限削减",
              total, cap))
      end
      if #tasks == 0 then return nil end
      return { tasks = tasks, i = 1, mx = mx, my = my, scanned = 0, hits = 0, features = 0,
               next_report = stats.frames + 600 }
  end

  local function job_progress(j)
      local total, done = 0, 0
      for i = 1, #j.tasks do
          local t = j.tasks[i]
          if t.kind == "scan" or t.kind == "replace" then
              -- 扫描 / 替换按「格 / 200」折算成一个与特征数量同量级的粗粒度单位
              total = total + (j.mx * j.my) / 200
              done = done + (t.y * j.mx + t.x) / 200
          else
              total = total + t.left + (t.done or 0)
              done = done + (t.done or 0)
          end
      end
      if total <= 0 then return 100 end
      local p = math.floor(done * 100 / total + 0.5)
      if p < 0 then p = 0 end
      if p > 100 then p = 100 end
      return p
  end

  local function finish_job(reason)
      local j = mem.wg_job
      mem.wg_job = nil
      if j and j.adhoc then WGADHOC = nil end        -- ★ v9：一键任务的临时选项表随任务一起清
      if not j then return end
      chat_print(string.format(
          "[世界工坊] 地图生成专项结束（%s）：扫描 %d 格 / 清除 %d 格 / 放置特征 %d 个",
          tostring(reason), j.scanned or 0, j.hits or 0, j.features or 0))
      diag("地图生成专项结束：" .. tostring(reason))
      diag_flush()
  end

  -- ★ v8：扫描预算。快通道（分块批量读）可用时按设置走；退回托管路径时压到 1500 格/帧 ——
  --   托管路径每格两次 invoke，照原预算跑会把帧时间吃光。
  local function scan_budget(w)
      local b = w.budget or 4000
      if mem.wg_fast ~= true and b > 1500 then b = 1500 end
      return b
  end

  -- ★ v8：两条读路都不可用 → 调用方放弃该任务（绝不盲删 / 盲改）
  local function read_path_ok(j)
      if not mem.wg_fast_verified then pcall(verify_fast) end
      return read_tile_at(0, 0, j.mx, j.my) ~= nil
  end

  local function report_progress(j)
      if stats.frames >= (j.next_report or 0) then
          j.next_report = stats.frames + 600
          chat_print(string.format("[世界工坊] 地图生成专项进行中：约 %d%%（可随时关掉相关设置停止）",
              job_progress(j)))
      end
  end

  local function step_job()
      local j = mem.wg_job
      if not j then return end
      local w = P.wgen
      if j.adhoc then
          -- ★ v9 一键任务：不受「地图生成专项」各个开关影响（玩家是当场点的按钮），
          --   但仍然受总开关管：总开关一关就立刻收尾（与设置驱动的任务同一个语义）。
          if cfg.enabled == false then
              finish_job("总开关已关闭")
              return
          end
          w = wopt()
      elseif not w or not w.active then                    -- 关掉开关 = 立刻中断
          finish_job("设置已关闭")
          return
      end
      if not may_write() then return end
      local t = j.tasks[j.i]
      if t == nil then
          finish_job("全部完成")
          return
      end

      if t.kind == "scan" then
          if not M.wg_kill_tile then
              warn_once("wg_clear_nohook", "地图生成：取不到 KillTile，"
                  .. "「生成后清除方块」已跳过（不盲删）")
              j.i = j.i + 1
              return
          end
          if not read_path_ok(j) then
              warn_once("wg_clear_noread", "地图生成：图块读取两条路都不可用"
                  .. "（TileData 原生数组 + Framing.GetTileSafely 都没取到），"
                  .. "「生成后清除方块」已跳过（绝不盲删）")
              j.i = j.i + 1
              return
          end
          local budget = scan_budget(w)
          -- ★ v10：「每帧最多改动格数」= 0 表示**不限制**（默认）。界面值 1 = 不限制。
          local hits = w.hits or 0
          if hits < 0 then hits = 0 end
          local unlimited = (hits == 0)
          while budget > 0 and (unlimited or hits > 0) and t.y < j.my do
              local x, y = t.x, t.y
              local ty = read_tile_at(x, y, j.mx, j.my)
              j.scanned = j.scanned + 1
              if ty ~= nil and ty ~= 0 and t.ids[ty] then
                  -- ★ v8：不再逐格补 SquareTileFrame —— 原版 KillTile 内部自己就调了
                  --   SquareTileFrame / SquareWallFrame（PC WorldGen.cs:64256、64436-64440），
                  --   多补一次纯属浪费。同时 noItem = true（不掉落物品）。
                  if invoke_checked(M.wg_kill_tile, 5, x, y, false, false, true) then
                      j.hits = j.hits + 1
                      hits = hits - 1
                      dcount(WG, "清除方块", 1)
                  end
              end
              budget = budget - 1
              t.x = t.x + 1
              if t.x >= j.mx then t.x = 0; t.y = t.y + 1 end
          end
          if t.y >= j.my then j.i = j.i + 1 end
      elseif t.kind == "replace" then
          -- ★ v7：生成后方块替换（A=B）。复用同一套分帧全图扫描；先读到 == A 才写 B。
          if not (M.wg_kill_tile and M.wg_square_frame) then
              warn_once("wg_rep_nohook", "地图生成：取不到 KillTile / SquareTileFrame，"
                  .. "「生成后方块替换」已跳过（不盲改）")
              j.i = j.i + 1
              return
          end
          if not read_path_ok(j) then
              warn_once("wg_rep_noread", "地图生成：图块读取两条路都不可用（TileData 原生数组 + "
                  .. "Framing.GetTileSafely 都没取到），「生成后方块替换」已跳过（绝不盲改）")
              j.i = j.i + 1
              return
          end
          local budget = scan_budget(w)
          -- ★ v10：「每帧最多改动格数」= 0 表示**不限制**（默认）。界面值 1 = 不限制。
          local hits = w.hits or 0
          if hits < 0 then hits = 0 end
          local unlimited = (hits == 0)
          while budget > 0 and (unlimited or hits > 0) and t.y < j.my do
              local x, y = t.x, t.y
              local ty = read_tile_at(x, y, j.mx, j.my)
              j.scanned = j.scanned + 1
              if ty ~= nil and ty ~= 0 then
                  local dst = t.map[ty]
                  if dst ~= nil then
                      if dst == 0 then
                          -- ★ v8：删除走 KillTile 即可（它内部已经补了 frame）
                          if invoke_checked(M.wg_kill_tile, 5, x, y, false, false, true) then
                              j.hits = j.hits + 1
                              hits = hits - 1
                              dcount(WG, "替换·删除", 1)
                          end
                      elseif not M.wg_place_tile then
                          warn_once("wg_rep_noplace", "地图生成：取不到 WorldGen.PlaceTile（7 参），"
                              .. "「生成后方块替换」只做了 B=0（删除）的部分")
                      else
                          -- ★ PlaceTile 自己不保证补 frame → 这一条保留 SquareTileFrame
                          if invoke_checked(M.wg_kill_tile, 5, x, y, false, false, true)
                              and invoke_checked(M.wg_place_tile, 7, x, y, dst, false, false, -1, 0) then
                              invoke_checked(M.wg_square_frame, 3, x, y, true)
                              j.hits = j.hits + 1
                              hits = hits - 1
                              dcount(WG, "替换·改写", 1)
                          end
                      end
                  end
              end
              budget = budget - 1
              t.x = t.x + 1
              if t.x >= j.mx then t.x = 0; t.y = t.y + 1 end
          end
          if t.y >= j.my then j.i = j.i + 1 end
      else
          -- 特征类：每帧最多放 speed 个
          -- ★ v10.2：「特征生成速度」= 每帧最多放置几个特征（1~20）。设置里有一项，
          --   一键页「特征」分页上也有一个快捷滑块直接改它（改的是运行时覆盖层）。
          -- ★ v8：结构类（gap > 1）放成功一次后要等 gap 帧，这一帧就不再继续。
          local speed = math.floor(tonumber(w.speed) or 1)
          if speed < 1 then speed = 1 end
          if speed > 20 then speed = 20 end
          for _ = 1, speed do
              local gap = t.gap or 1
              if gap > 1 and t.last and (stats.frames - t.last) < gap then
                  break                    -- 这一帧到此为止：等下一个窗口
              end
              local okp = t.fn(t)
              t.tries = (t.tries or 0) + 1
              if okp then
                  t.left = t.left - 1
                  t.done = (t.done or 0) + 1
                  j.features = j.features + 1
                  dcount(WG, t.name, 1)
                  t.tries = 0
                  if gap > 1 then t.last = stats.frames end
              elseif t.tries > (t.max_tries or 60) then
                  verbose("地图生成：「" .. tostring(t.name) .. "」连续 60 次没找到合适位置，放弃剩余")
                  t.left = 0
              end
              if t.left <= 0 then j.i = j.i + 1 break end
          end
      end

      -- 进度播报：约 10 秒一次（600 帧）+ 结束一次
      report_progress(j)
      if j.i > #j.tasks then finish_job("全部完成") end
  end

  -- ---------------------------------------------------------------- 不可逆项：新建世界
  local function apply_evil()
      local w = P.wgen
      if not w or w.evil_n == nil then return end
      if not may_write() then return end
      local n = 0
      if fset_if("wg_param_evil", nil, w.evil_n) then n = n + 1 end
      if w.evil_n == 0 then
          if fset_if("wg_crimson", nil, false) then n = n + 1 end
      elseif w.evil_n == 1 then
          if fset_if("wg_crimson", nil, true) then n = n + 1 end
      end
      if n > 0 then
          dcount(WG, "新建世界·邪恶类型", 1)
          if log_allowed() then mod.info("地图生成：新建世界邪恶类型 = " .. tostring(w.evil)) end
      end
  end

  local function apply_size()
      local w = P.wgen
      if not w then return end
      local do_std = w.size_n ~= nil
      local do_custom = (w.cw or 0) > 0 and (w.ch or 0) > 0
      if not do_std and not do_custom then return end
      if not may_write() then return end
      local n = 0
      if do_std then
          if invoke_checked(M.wg_set_size, 1, w.size_n) then n = n + 1 end   -- 只写 maxTilesX/Y
      end
      if do_custom then
          -- ★ v7：自定义宽×高。setWorldSize() 只算 bottomWorld / rightWorld /
          --   maxSectionsX/Y（PC WorldGen.cs:6499-6505），**不动** maxTilesX/Y，
          --   所以在它之前写这两个字段是安全的。
          if fset_if("max_tiles_x", nil, w.cw) then n = n + 1 end
          if fset_if("max_tiles_y", nil, w.ch) then n = n + 1 end
      end
      if invoke_checked(M.wg_set_size_lc, 0) then n = n + 1 end              -- 补世界边界 / 分区数
      if n > 0 then
          dcount(WG, "世界大小写入", 1)
          if log_allowed() then
              mod.info("地图生成：新建世界大小 = " .. tostring(w.size)
                  .. " / 自定义 " .. tostring(w.cw) .. "×" .. tostring(w.ch))
          end
      end
  end


  -- ★★ v8 崩溃修复（本次的核心）★★
  --   旧版把「武装 pending + 写世界大小 + 写邪恶类型」当成 WorldGen.Reset() / GenerateWorld() 的钩子来做。
  --   但这两个方法跑在**世界生成线程**上：
  --     PC 1.4.5.8 WorldGen.cs:6574 —— CreateNewWorld() 里 Task.Factory.StartNew(worldGenCallback)，
  --     而 worldGenCallback → GenerateWorld() → clearWorld(); Reset(); 全在这条 worker 线程上。
  --   钩子回调里做的事是纯 Lua（dcount / V7.arm / diag / pcall），于是**两个线程同时进同一个
  --   lua_State** —— 这不是 pcall 能拦住的 Lua 错误，而是原生层的内存踩踏。
  --   TEFKernel 日志里那几次 SIGSEGV 的故障地址（0x21b983 / 0x407a9c / 0x330b46 …）全是小的
  --   野地址，正是「指针被写坏」的形状。→ 生成线程上的钩子现在**一个都不装**。
  --
  --   时机照样成立：CreateNewWorld() 是在 Task.Factory.StartNew **之前**执行的（主线程），
  --   而 clearWorld() / Reset()（Reset 的方法体自己读 WorldGenParam_Evil，PC WorldGen.cs:11335）
  --   都在 Task 里。所以在 CreateNewWorld 的 prefix 里写世界大小与邪恶类型，语义与旧版完全等价。
  local function on_world_create_prefix()
      if not ready then return nil end
      dcount(WG, "创建入口命中", 1)
      WGST.gen = true
      local w = P.wgen
      local want = w and (w.content or w.clear_on or w.replace_on or w.size_n ~= nil
          or w.evil_n ~= nil or w.cw > 0 or w.spawn_x > 0 or w.spawn_y > 0 or w.start ~= "none")
      if want then V7.arm("WorldGen.CreateNewWorld") end
      pcall(apply_size)
      pcall(apply_evil)
      return nil
  end

  -- GUIWorldCreateMenu.CreateWorld prefix（实例方法）：把实例的 worldSize 也写上
  local function on_gui_create_prefix(inst)
      if not ready then return nil end
      dcount(WG, "菜单钩子命中", 1)
      local w = P.wgen
      if inst and w and w.size_n ~= nil and F.gui_world_size and may_write() then
          local ok = pcall(patch.set_field_value, F.gui_world_size, inst, w.size_n, "int32")
          if ok then dcount(WG, "创建菜单·世界大小字段", 1) end
      end
      if may_write() then pcall(apply_size) end
      return nil                               -- 不跳过原方法
  end

  -- ---------------------------------------------------------------- 每帧（world 阶段）
  local function on_world_frame()
      -- ★ 默认零开销：没有「即将生成」标记、也没有进行中的任务时，只读两个 Lua 表字段就退出。
      -- ★★ 这里**不能**按「设置是否打开」提前 return：关掉设置正是要靠下面的 step_job
      --   去收尾（中断 + 播报）。把清理路径和入口门控写在同一个条件里，任务会永远留在
      --   mem 里静默卡死 —— 本工作区踩过同类坑，所以单独判。
      if not WGST.pending and not mem.wg_job then return end
      local w = P.wgen
      if not w then return end
      -- 「刚生成完一个新世界」标记：进世界后 generatingWorld 已是 false → 判定生成完成
      if WGST.pending then
          if stats.frames - WGST.arm > WGST.maxage then
              WGST.pending, WGST.gen = false, false
              dcount(WG, "pending过期", 1)
              return
          end
          WGST.pending = false
          WGST.gen = false
          dcount(WG, "pending消费", 1)
          if not w.active then return end                  -- 生成期间设置被关掉了：不用建队列
          if fget("wg_generating") == true then
              WGST.pending, WGST.arm = true, stats.frames -- 后台还在生成，下一帧再看
              return
          end
          WGST.readback = V7.read_back(w)
          pcall(V7.spawn)
          pcall(V7.start_time)
          mem.wg_job = build_job()
          if mem.wg_job then
              WG.hits = WG.hits + 1
              chat_print(string.format(
                  "[世界工坊] 地图生成专项：世界生成完成，开始按规则追加 / 替换 / 清除"
                  .. "（结构每 %d 帧 1 个，小特征每帧 1 个，全图扫描 %d 格/帧）",
                  (P.wgen and P.wgen.gap) or 1, (P.wgen and P.wgen.budget) or 4000))
              chat_print("[世界工坊] 地图生成读回：" .. WGST.readback)
              diag("地图生成专项：任务队列已建立（" .. tostring(#mem.wg_job.tasks) .. " 条）；" .. WGST.readback)
              diag_flush()
          end
          return
      end
      WG.hits = WG.hits + 1
      -- ★ 任务执行失败必须记账（否则 pcall 会把它吞掉，用户只看到「没反应」）
      local ok, err = pcall(step_job)
      if not ok then
          WG.errs = WG.errs + 1
          WG.last_err = tostring(err)
          warn_once("wg_step", "地图生成：任务执行失败（该条任务将被放弃）：" .. tostring(err))
          if mem.wg_job and mem.wg_job.tasks[mem.wg_job.i] then
              mem.wg_job.i = mem.wg_job.i + 1
          end
      end
  end

  WG = domain({
      name = "地图生成",
      fields = function(T)
          -- 无命名空间的类型（手机版符号表里 GUIWorldCreateMenu 没有命名空间）→ 逐个试探
          local gui
          local tries = {
              { "", "GUIWorldCreateMenu" },
              { nil, "GUIWorldCreateMenu" },
              { "Terraria", "GUIWorldCreateMenu" },
              { "Terraria.UI", "GUIWorldCreateMenu" },
          }
          for i = 1, #tries do
              if not gui then
                  local ok, t = pcall(get_type, tries[i][1], tries[i][2])
                  if ok and t then gui = t end
              end
          end
          T.GUICREATE = gui
          T.TILEDATA = get_type("Terraria", "TileData")
          -- ★ v10：不再解析 Terraria.Framing / Terraria.Tile —— 那两条是结构体反射（崩溃源），
          --   本分片现在一次都不碰（见文件头「v10 崩溃修复」）。

          register("wg_generating", T.WORLDGEN, "generatingWorld", "bool")
          register("wg_crimson", T.WORLDGEN, "crimson", "bool")
          register("wg_param_evil", T.WORLDGEN, "WorldGenParam_Evil", "int32")
          register("gui_world_size", gui, "worldSize", "int32")
          -- ★ v10：地表高度 / 岩层高度（Main 的 public static double，非 const）。
          --   地表结构的取点范围、天空结构与宝石洞的落点都要用；只用作**取点**，不当写入依据。
          register("world_surface", T.MAIN, "worldSurface", "double")
          register("rock_layer", T.MAIN, "rockLayer", "double")
          -- ★ v10：宝石洞前置校验（WorldGen.countTiles）的读写口 —— 全是 public static int，非 const。
          --   maxTileCount 是 countTiles 的计数上限（原版 GemCaves 那一趟写 300），
          --   另外三个是它跑完之后的副作用计数（岩浆 / 冰 / 岩石格数）。
          register("wg_max_tile_count", T.WORLDGEN, "maxTileCount", "int32")
          register("wg_lava_count", T.WORLDGEN, "lavaCount", "int32")
          register("wg_ice_count", T.WORLDGEN, "iceCount", "int32")
          register("wg_rock_count", T.WORLDGEN, "rockCount", "int32")
          -- 原生数组字段：只用于 field_pointer 取地址（读图块），不参与普通读写
          register("td_lookup", T.TILEDATA, "TileLookup", "object")
          register("td_type", T.TILEDATA, "TileType", "object")
          register("td_sheader", T.TILEDATA, "TileSHeader", "object")
      end,
      methods = function(T)
          M.wg_reset = T.WORLDGEN and find_method(T.WORLDGEN, "Reset", 0)
          M.wg_create = T.WORLDGEN and find_method(T.WORLDGEN, "CreateNewWorld", 1)
          M.wg_generate = T.WORLDGEN and find_method(T.WORLDGEN, "GenerateWorld", 2)
          M.wg_set_size = T.WORLDGEN and find_method(T.WORLDGEN, "SetWorldSize", 1)
          M.wg_set_size_lc = T.WORLDGEN and find_method(T.WORLDGEN, "setWorldSize", 0)
          M.wg_in_world = T.WORLDGEN and find_method(T.WORLDGEN, "InWorld", 3)
          M.wg_empty_check = T.WORLDGEN and find_method(T.WORLDGEN, "EmptyTileCheck", 5)
          M.wg_add_life = T.WORLDGEN and find_method(T.WORLDGEN, "AddLifeCrystal", 2)
          M.wg_add_mana = T.WORLDGEN and find_method(T.WORLDGEN, "AddManaCrystal", 2)
          M.wg_island = T.WORLDGEN and find_method(T.WORLDGEN, "FloatingIsland", 2)
          M.wg_cloud_island = T.WORLDGEN and find_method(T.WORLDGEN, "CloudIsland", 2)
          M.wg_cloud_lake = T.WORLDGEN and find_method(T.WORLDGEN, "CloudLake", 2)
          M.wg_caverer = T.WORLDGEN and find_method(T.WORLDGEN, "Caverer", 2)
          M.wg_tile_runner = T.WORLDGEN and find_method(T.WORLDGEN, "TileRunner", 11)
          M.wg_shimmer_biome = T.WORLDGEN and find_method(T.WORLDGEN, "ShimmerMakeBiome", 2)
          M.wg_kill_tile = T.WORLDGEN and find_method(T.WORLDGEN, "KillTile", 5)
          M.wg_square_frame = T.WORLDGEN and find_method(T.WORLDGEN, "SquareTileFrame", 3)
          -- ★★ v10：**彻底删掉** Framing.GetTileSafely 与 Tile.get_type 两条句柄 ★★
          --   前者返回 Tile 结构体、后者拿结构体当 this —— 就是本版修掉的那个崩溃源
          --   （见文件头「v10 崩溃修复」的长注释）。换成两条全标量参的方法：
          M.wg_solid_tile = T.WORLDGEN and find_method(T.WORLDGEN, "SolidTile", 3)
          M.wg_count_tiles = T.WORLDGEN and find_method(T.WORLDGEN, "countTiles", 4)
          if T.WORLDGEN and not M.wg_solid_tile then
              mod.warn("找不到 WorldGen.SolidTile(int,int,bool)：矿脉「先读后写」与云岛找宝箱落脚点"
                  .. "退化成不检查（交给原版自己判），其余功能不受影响")
          end
          -- GUIWorldCreateMenu.CreateWorld（0 参 public 实例方法）
          M.wg_gui_create = T.GUICREATE and find_method(T.GUICREATE, "CreateWorld", 0)
          -- ★ v7 新内容（符号已对 1.4.5.8 手机版方法表逐条核实形参个数）
          M.wg_buried_chest = T.WORLDGEN and find_method(T.WORLDGEN, "AddBuriedChest", 7)
          M.wg_marble = T.WORLDGEN and find_method(T.WORLDGEN, "MarblePileWithStatues", 2)
          M.wg_lihzahrd = T.WORLDGEN and find_method(T.WORLDGEN, "AddLihzahrdAltar", 2)
          M.wg_shadow_orb = T.WORLDGEN and find_method(T.WORLDGEN, "AddShadowOrb", 3)
          M.wg_gem_cave = T.WORLDGEN and find_method(T.WORLDGEN, "gemCave", 2)
          -- ★ v10.2：新增的原版特征（手机版方法表：全部 public static、参数全标量）
          M.wg_grave = T.WORLDGEN and find_method(T.WORLDGEN, "SpawnGraveyardBiome", 2)
          M.wg_moss = T.WORLDGEN and find_method(T.WORLDGEN, "setMoss", 2)
          M.wg_glow_moss = T.WORLDGEN and find_method(T.WORLDGEN, "neonMossBiome", 3)
          M.wg_mayan = T.WORLDGEN and find_method(T.WORLDGEN, "mayanTrap", 2)
          M.wg_lava = T.WORLDGEN and find_method(T.WORLDGEN, "placeLavaTrap", 2)
          M.wg_statue_trap = T.WORLDGEN and find_method(T.WORLDGEN, "PlaceStatueTrap", 2)
          M.wg_bee = T.WORLDGEN and find_method(T.WORLDGEN, "AddBeeLarva", 2)
          M.wg_ore_patch = T.WORLDGEN and find_method(T.WORLDGEN, "OrePatch", 2)
          M.wg_stone_patch = T.WORLDGEN and find_method(T.WORLDGEN, "StonePatch", 2)
          M.wg_shell_pile = T.WORLDGEN and find_method(T.WORLDGEN, "ShellPile", 2)
          M.wg_oasis = T.WORLDGEN and find_method(T.WORLDGEN, "PlaceOasis", 2)
          M.wg_place_tile = T.WORLDGEN and find_method(T.WORLDGEN, "PlaceTile", 7)
          -- ★ v8：岛屿天空房（含宝箱 / 家具 / 墙）/ 云岛宝箱 / 批量补框架
          M.wg_island_house = T.WORLDGEN and find_method(T.WORLDGEN, "IslandHouse", 3)
          M.wg_place_chest = T.WORLDGEN and find_method(T.WORLDGEN, "PlaceChest", 5)
          M.wg_section_frame = T.WORLDGEN and find_method(T.WORLDGEN, "SectionTileFrame", 4)
          -- ★ v7：自定义出生点（Main.spawnTileX / spawnTileY 是属性 → setter 桥接）
          if T.MAIN and patch.get_property and patch.property_set_method then
              local function spawn_setter(pname)
                  local okp, prop = pcall(patch.get_property, T.MAIN, pname)
                  if not (okp and prop) then return nil end
                  local oks, s = pcall(patch.property_set_method, prop)
                  if oks and s then return s end
                  return nil
              end
              M.spawn_x_set = spawn_setter("spawnTileX")
              M.spawn_y_set = spawn_setter("spawnTileY")
          end
      end,
      install = function()
          -- ★★ v8 崩溃修复：只挂主线程锚点（理由见上面 on_world_create_prefix 的长注释）★★
          safe_hook(M.wg_create, { prefix = on_world_create_prefix },
              "WorldGen.CreateNewWorld（地图生成：世界大小 / 邪恶类型 / 武装 pending）")
          safe_hook(M.wg_gui_create, { prefix = on_gui_create_prefix },
              "GUIWorldCreateMenu.CreateWorld（地图生成：创建菜单尺寸字段）")
          -- ★ 明确不装：WorldGen.Reset / WorldGen.GenerateWorld —— 两者都在生成线程上，
          --   从那里执行任何 Lua 都是「两个线程同时用一个 lua_State」。
          if M.wg_reset or M.wg_generate then
              verbose("地图生成：生成线程钩子（WorldGen.Reset / GenerateWorld）按崩溃修复要求不安装")
          end
      end,
      world = on_world_frame,
      reset = function()
          -- ★ v7：pending 不再放 mem。只有「还没看到任何一次真正的生成」时才清掉，
          --   避免「生成完成 → 回菜单边沿」把刚武装的 pending 清没（旧版就是这个坑）。
          if not WGST.gen then WGST.pending = false end
          mem.wg_job = nil
          mem.wg_row, mem.wg_row_y, mem.wg_row_mx = nil, nil, nil
          mem.wg_types, mem.wg_sheader = nil, nil
          mem.wg_fast, mem.wg_fast_probe, mem.wg_fast_verified = nil, nil, nil
          fast_forget_chunk()
          p_lookup, p_type, p_sheader = nil, nil, nil
      end,
  })

  -- 供 95_chat 的 `/forge wgen` 使用（跨分片只经这个共享表）
  -- ============================================================================
  -- ★ v9：一键操作（87_oneshot.lua 调这里）——「当场把 N 个特征塞进队列」
  -- ----------------------------------------------------------------------------
  -- 与 build_job()（设置驱动）的区别只有三处：
  --   ① 任务表由调用方给，不读设置；② 走 WGADHOC 选项表（结构补天空房 / 宝箱、补框架都打开）；
  --   ③ 已经在跑别的任务时不打断，**追加到队尾**（同一个分帧执行器，同一套预算与播报）。
  -- 默认零开销：没人点按钮时本表一个函数都不会被调到。
  -- ============================================================================
  local ADHOC_DEFS = {
      life       = { name = "生命水晶", fn = place_life,         gap = 1 },
      mana       = { name = "魔力水晶", fn = place_mana,         gap = 1 },
      island     = { name = "浮空岛",   fn = place_island,       struct = true },
      cloud      = { name = "云岛",     fn = place_cloud_island, struct = true },
      lake       = { name = "云湖",     fn = place_cloud_lake,   struct = true },
      cave       = { name = "洞穴",     fn = place_cave,         gap = 4 },
      ore        = { name = "矿脉",     fn = place_ore,          gap = 1 },
      meteor_ore = { name = "陨石矿脉", fn = place_ore,          gap = 1, extra = { ore_type = 37 } },
      shimmer    = { name = "微光群系", fn = place_shimmer,      gap = 4 },
      chest      = { name = "埋藏宝箱", fn = V7.chest,           gap = 1 },
      marble     = { name = "大理石堆", fn = V7.marble,          gap = 4 },
      lihzahrd   = { name = "神庙祭坛", fn = V7.lihzahrd,        gap = 4 },
      orb        = { name = "暗影球",   fn = V7.shadow_orb,      gap = 4 },
      gemcave    = { name = "宝石洞",   fn = V7.gem_cave,        gap = 4 },
      orepatch   = { name = "矿斑",     fn = V7.ore_patch,       gap = 4 },
      stonepatch = { name = "石斑",     fn = V7.stone_patch,     gap = 4 },
      shell      = { name = "贝壳堆",   fn = V7.shell_pile,      gap = 4 },
      oasis      = { name = "绿洲",     fn = V7.oasis,          gap = 4 },
      -- ★ v10.2 新增（原版还有一大堆可用的特征，这些是参数全标量、能安全 invoke 的）
      graveyard  = { name = "墓地",     fn = V7.graveyard,      gap = 8 },
      moss       = { name = "苔藓",     fn = V7.moss,           gap = 1 },
      glowmoss   = { name = "发光苔藓", fn = V7.glow_moss,      gap = 4 },
      mayan      = { name = "神庙陷阱", fn = V7.mayan,          gap = 1 },
      lavatrap   = { name = "岩浆陷阱", fn = V7.lava_trap,      gap = 1 },
      statuetrap = { name = "雕像陷阱", fn = V7.statue_trap,    gap = 1 },
      bee        = { name = "蜂巢",     fn = V7.bee_larva,      gap = 1 },
  }
  -- 顺序即「一键页里类型选择器的翻页顺序」：小特征在前、结构在后
  local ADHOC_ORDER = { "life", "mana", "ore", "meteor_ore", "chest", "cave", "shimmer",
      "gemcave", "orepatch", "stonepatch", "marble", "lihzahrd", "orb", "shell", "oasis",
      "moss", "glowmoss", "bee", "mayan", "lavatrap", "statuetrap", "graveyard",
      "island", "cloud", "lake" }
  -- 一次一键操作最多放几个（与设置的「单次生成·特征总量上限」同一个数量级，防手滑点爆）
  local ADHOC_CAP = 300

  local function adhoc_tasks(specs)
      local list, total = {}, 0
      if type(specs) ~= "table" then return list end
      for i = 1, #specs do
          local sp = specs[i]
          local def = (type(sp) == "table") and ADHOC_DEFS[sp.kind] or nil
          local n = (type(sp) == "table") and math.floor(tonumber(sp.count) or 1) or 0
          if def and n > 0 then
              if total + n > ADHOC_CAP then n = ADHOC_CAP - total end
              if n > 0 then
                  total = total + n
                  -- ★ v10：结构类的节流不再写死 8 帧 —— 跟「结构类生成间隔」设置走
                  --   （该设置默认 1 = 不节流，见 gen.py / 30_plan）。
                  local gp = def.gap or 1
                  if def.struct then
                      gp = tonumber(wopt().gap) or 1
                      if gp < 1 then gp = 1 end
                  end
                  local t = { kind = "feature", name = def.name, left = n, tries = 0,
                              fn = def.fn, gap = gp }
                  if def.extra then
                      for k, v in pairs(def.extra) do t[k] = v end
                  end
                  -- 矿脉：优先用调用方指定的方块编号，其次用设置里的，最后回落到 6 号（铁矿石）
                  if sp.kind == "ore" and t.ore_type == nil then
                      t.ore_type = sp.ore_type or wopt().ore_type or 6
                  end
                  if type(t.ore_type) ~= "number" then t.ore_type = 6 end
                  list[#list + 1] = t
              end
              if total >= ADHOC_CAP then break end
          end
      end
      return list
  end

  -- 返回 (加入的特征数, 是否新建了队列, 给人看的一句话)
  WGCTL.spawn_features = function(specs)
      local tasks = adhoc_tasks(specs)
      if #tasks == 0 then return 0, false, "没有可放置的特征（类型 / 个数不合法）" end
      local total = 0
      for i = 1, #tasks do total = total + (tasks[i].left or 0) end
      local j = mem.wg_job
      if j then
          for i = 1, #tasks do j.tasks[#j.tasks + 1] = tasks[i] end
          return total, false, string.format("已追加 %d 个特征到进行中的队列", total)
      end
      local mx, my = world_size()
      if not mx then return 0, false, "读不到世界尺寸（还没进世界？）" end
      if not may_write() then return 0, false, "当前是客机：一键生成不写入（仅房主生效）" end
      -- 一键任务自己的选项表：结构与宝箱该补的都补上（不看「地图生成专项」的设置）
      local g = tonumber(P.wgen and P.wgen.gap) or 8
      if g < 1 then g = 1 end
      WGADHOC = {
          gap = g, reframe = true,
          sky_delta = tonumber(P.wgen and P.wgen.sky_delta) or 100,
          under_lo = nil, under_hi = nil,
          island_house = true, cloud_chest = true, island_style = 0,
          chest_style = 0, chest_item = 0,
          ore_type = tonumber(P.wgen and P.wgen.ore_type) or 6,
          speed = tonumber(P.wgen and P.wgen.speed) or 1,   -- ★ v10.2：特征生成速度
          hits = 0,                         -- 一键任务不吃「每帧最多改动格数」（玩家当场点的）
      }
      mem.wg_job = { tasks = tasks, i = 1, mx = mx, my = my, scanned = 0, hits = 0,
                     features = 0, adhoc = true, next_report = stats.frames + 600 }
      WG.hits = WG.hits + 1
      dcount(WG, "一键生成队列", 1)
      if log_allowed() then
          diag("一键操作：新建特征队列（" .. tostring(total) .. " 个，结构每 " .. tostring(g) .. " 帧 1 个）")
      end
      return total, true, string.format("已开始一键生成 %d 个特征（结构每 %d 帧 1 个）", total, g)
  end
  -- 供「一键」页做类型选择器：顺序 + { id → 中文名 }
  WGCTL.adhoc = function()
      local labels = {}
      for k, v in pairs(ADHOC_DEFS) do labels[k] = v.name end
      local order = {}
      for i = 1, #ADHOC_ORDER do order[i] = ADHOC_ORDER[i] end
      return order, labels
  end

  -- ★ v10.2：供面板显示进度条（0~1）；没有进行中的任务时返回 nil
  WGCTL.progress = function()
      local j = mem.wg_job
      if not j then return nil end
      local p = job_progress(j)
      if type(p) ~= "number" then return nil end
      return p / 100
  end
  -- 供 95_chat 的 /forge wgen 使用（跨分片只经这个共享表）
  WGCTL.status = function()
      local j = mem.wg_job
      if not j then
          if mem.wg_pending then return "正在等待世界生成结束" end
          return "当前没有进行中的地图生成任务"
      end
      local t = j.tasks[j.i]
      local tag = j.adhoc and "一键生成" or "地图生成专项"
      local name = "收尾"
      if t then
          if t.kind == "scan" or t.kind == "replace" then name = t.name
          else name = tostring(t.name) .. "（剩 " .. tostring(t.left) .. "）" end
      end
      return string.format("%s进行中：%s ／ 进度约 %d%% ／ 已扫描 %d 格 ／ 已清除 %d 格 ／ 已放置特征 %d 个",
          tag, name, job_progress(j), j.scanned or 0, j.hits or 0, j.features or 0)
  end
  -- ★ v7：/forge wgen 的「触发链」一行 —— 用户回一句就能定位是
  --   「钩子没触发」「pending 被清」还是「写入/读回不符」。
  WGCTL.chain = function()
      local c = WG.c
      local function g(k) return tostring(c[k] or 0) end
      return string.format(
          "主线程触发链：创建入口命中 %s / 菜单钩子命中 %s / pending 武装 %s 消费 %s 过期 %s"
          .. " / 世界大小写入 %s / 结构节流 %s 帧 1 个 / 特征超上限 %s"
          .. " / 读回 %s"
          .. "（生成线程钩子 WorldGen.Reset / GenerateWorld 按崩溃修复**不安装**）",
          g("创建入口命中"), g("菜单钩子命中"),
          g("pending武装"), g("pending消费"), g("pending过期"), g("世界大小写入"),
          tostring(P.wgen and P.wgen.gap or 1), g("特征超上限"),
          (WGST.readback ~= "" and WGST.readback) or "（还没进过新世界）")
  end
  WGCTL.cancel = function()
      WGST.pending, WGST.gen = false, false
      if mem.wg_job or mem.wg_pending then
          mem.wg_pending = nil
          finish_job("被 /forge wgen stop 取消")
          return true
      end
      return false
  end
  end)()
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过共享表 ONESHOT / WGCTL / 全局函数交互。
do
  -- ============================================================================
  -- 87 · 一键操作（v9 新增）
  -- ----------------------------------------------------------------------------
  -- 【是什么】把玩家最想「马上做一次」的事做成按钮：GUI 第 5 页「一键」的四个分页
  --   （事件 / 特征 / 玩家 / 雷击）都调这里。三类实现路径：
  --     · 事件与天气类：写已经注册过的 Main 字段，或者调**原版自己的入口方法**
  --       Main.StartSlimeRain(bool) / startPumpkinMoon() / startSnowMoon() / stopMoonEvent() /
  --       StartInvasion(int) / Sandstorm.StartSandstorm() / StopSandstorm() /
  --       WorldGen.StartMeteorShower() / dropMeteor(bool) /
  --       GeneratePlanteraBulbOnAllMechsDefeated() / StartHardmode(bool?) / SmashAltar(int,int)
  --       —— 形参个数逐个对着 1.4.5.8 手机版方法表核过（见 参考库/符号/官方源码-方法.tsv）。
  --     · 世界特征类：交给 86 的地图生成分帧队列（WGCTL.spawn_features）——
  --       与设置里的「生成后追加特征」共用同一套放置函数 / 预算 / 进度播报 / 取消逻辑。
  --     · 玩家与雷击类：回满血蓝 / 清减益 / 传送到出生点 / 清掉落物 / 清敌怪 /
  --       头顶劈一道雷 / 屏幕闪光雷声 / 驱散所有落雷。
  -- 【纪律】
  --   ① 默认零开销：本分片**不装任何钩子**，只有玩家点了按钮才会进任何一条执行路径；
  --   ② 每条操作先判句柄 / 先判字段是否注册，取不到就返回一句「不可用：…」——
  --      绝不拿空句柄去 invoke（红线 4），绝不猜符号名（红线 5）；
  --   ③ 写世界数据一律过 may_write()（联机「仅房主生效」时客机只读）；
  --      只改本机角色自身状态的几项（回血 / 清减益 / 传送）不受该限制 —— 那是本地状态。
  --   ④ 每条操作都记账（域计数器 + 按 id 的命名计数器），/forge stat 与 GUI「逐域诊断」看得到。
  -- ============================================================================

  -- ★★ 整体再包一层 IIFE（立即调用的函数）★★
  --   主 chunk 也是一个函数，**活着的 local 上限 200**：本分片有 30 多个 local，
  --   直接铺在 do…end 里会和前面各分片的 local 叠加（实测 v9 首版在 86 分片处报
  --   "too many local variables (limit is 200)"）。放进 IIFE 后它们只是内层函数的 local，
  --   对外照旧只经共享表 ONESHOT 交互（表本身声明在 05_state，是主 chunk 的 local）。
  (function()
  local OS                       -- ★ 前向声明：下面所有回调体里都要引用它
  local NOT_HOST = "当前是客机：本模组不写世界数据（设置里的「仅房主生效」开着）"
  local NO_MAPGEN = "地图生成专项未启用（86 分片没装上）"
  local BUFF_SLOTS = 44          -- ★ Player.maxBuffs 是 const = 44（抄常数，不读 const 字段）
  local NPC_SLOTS = 200          -- ★ Main.maxNPCs 是 const = 200
  local ITEM_SLOTS = 400         -- ★ Main.maxItems 是 const = 400

  -- 数量档（特征页的「个数 +/-」在 1 / 5 / 20 三档之间循环）
  local COUNTS = { 1, 5, 20 }

  local function miss(what) return false, "不可用：" .. tostring(what) end
  local function done(msg) return true, msg end

  -- 写一个已注册的全局字段；返回 true = 值已经是目标值或写入成功
  local function wset(key, v)
      if not F[key] then return false end
      if fget(key) == v then return true end
      return fset(key, nil, v)
  end

  -- 静态方法调用（判空 + 实参个数核对 + pcall）；返回 (ok, 返回值)
  local function CALL(m, argc, ...)
      if not m then return false, nil end
      if patch.method_param_count then
          local okc, n = pcall(patch.method_param_count, m)
          if okc and type(n) == "number" and n ~= argc then return false, nil end
      end
      local args = table.pack(...)
      if args.n ~= argc then return false, nil end
      local ok, a = pcall(patch.invoke, m, table.unpack(args, 1, args.n))
      if not ok then return false, nil end
      return true, a
  end

  -- 实例方法调用（instance 单独占一个实参槽位；返回 (ok, 返回值)）
  local function CALLI(m, inst, ...)
      if not m or not inst then return false, nil end
      local n
      if patch.method_param_count then
          local okc, c = pcall(patch.method_param_count, m)
          if okc and type(c) == "number" then n = c end
      end
      local args = table.pack(...)
      if n and args.n ~= n then return false, nil end
      local ok, a = pcall(patch.invoke, m, inst, table.unpack(args, 1, args.n))
      if not ok then return false, nil end
      return true, a
  end

  -- Main.player[myPlayer] → 玩家实例（借用手柄：只在当前调用内有效）
  local function my_player()
      local arr = get_object("player")
      if not arr then return nil end
      local ok, p = pcall(patch.array_at, arr, my_player_index())
      if not ok or not p or type(p) == "number" then return nil end
      return p
  end

  -- 本地玩家所在图格（x, y）；读不到返回 nil
  local function my_tile()
      local p = my_player()
      if not p or not F.position then return nil end
      local x, y = fget_vec2("position", p)
      if type(x) ~= "number" or type(y) ~= "number" then return nil end
      return math.floor(x / 16), math.floor(y / 16)
  end

  -- 遍历一个对象数组（Main.projectile / Main.item / Main.npc）
  local function scan(arrkey, slots, fn)
      local arr = get_object(arrkey)
      if not arr then return 0 end
      local n = 0
      for i = 0, slots - 1 do
          local oka, o = pcall(patch.array_at, arr, i)
          if oka and o and type(o) ~= "number" then
              local okf, hit = pcall(fn, o)
              if okf and hit then n = n + 1 end
          end
      end
      return n
  end

  -- ---------------------------------------------------------------- 操作实现
  local H = {}

  -- ---- 事件 / 天气 ----
  H.e_blood = function()
      if not may_write() then return false, NOT_HOST end
      if not wset("bloodMoon", true) then return miss("Main.bloodMoon") end
      return done("已开启血月（天亮时原版会自己结束；想看整晚建议同时点「天黑」）")
  end
  H.e_eclipse = function()
      if not may_write() then return false, NOT_HOST end
      if not wset("eclipse", true) then return miss("Main.eclipse") end
      return done("已开启日食（白天生效；可配合「天亮」）")
  end
  H.e_slime = function()
      if not may_write() then return false, NOT_HOST end
      local ok = CALL(M.start_slime_rain, 1, true)
      if ok then return done("已开始史莱姆雨（原版入口 Main.StartSlimeRain）") end
      if wset("slimeRain", true) then
          if F.slimeRainTime then wset("slimeRainTime", 3600.0) end
          return done("已开启史莱姆雨（退化为写字段：取不到 StartSlimeRain）")
      end
      return miss("Main.StartSlimeRain / Main.slimeRain")
  end
  H.e_moon_end = function()
      if not may_write() then return false, NOT_HOST end
      if CALL(M.stop_moon_event, 0) then return done("月亮事件（南瓜月 / 霜月）已结束") end
      wset("pumpkinMoon", false)
      wset("snowMoon", false)
      return done("已关掉南瓜月 / 霜月（退化为写字段：取不到 stopMoonEvent）")
  end
  H.e_pumpkin = function()
      if not may_write() then return false, NOT_HOST end
      if CALL(M.start_pumpkin_moon, 0) then return done("南瓜月已开始（哀嚎的树精与南瓜王会一波波刷出来）") end
      if wset("pumpkinMoon", true) then return done("已开启南瓜月（退化为写字段）") end
      return miss("Main.startPumpkinMoon")
  end
  H.e_snow = function()
      if not may_write() then return false, NOT_HOST end
      if CALL(M.start_snow_moon, 0) then return done("霜月已开始（圣诞军团与冰雪女王）") end
      if wset("snowMoon", true) then return done("已开启霜月（退化为写字段）") end
      return miss("Main.startSnowMoon")
  end
  H.e_lantern = function()
      if not may_write() then return false, NOT_HOST end
      if not wset("ManualLanterns", true) then return miss("LanternNight.ManualLanterns") end
      return done("灯笼夜已开启（今晚会满天灯笼）")
  end
  H.e_party = function()
      if not may_write() then return false, NOT_HOST end
      if not wset("ManualParty", true) then return miss("BirthdayParty.ManualParty") end
      return done("派对已开启（NPC 会一直开派对）")
  end
  H.e_sand = function()
      if not may_write() then return false, NOT_HOST end
      if CALL(M.sand_start, 0) then return done("沙尘暴已开始（沙漠生物群系里看得见）") end
      return miss("Sandstorm.StartSandstorm")
  end
  H.e_sand_stop = function()
      if not may_write() then return false, NOT_HOST end
      if CALL(M.sand_stop, 0) then return done("沙尘暴已停止") end
      return miss("Sandstorm.StopSandstorm")
  end
  H.e_rain = function()
      if not may_write() then return false, NOT_HOST end
      local n = 0
      if wset("raining", true) then n = n + 1 end
      if F.rainTime and wset("rainTime", 86400) then n = n + 1 end
      if F.maxRaining and wset("maxRaining", 1.0) then n = n + 1 end
      if F.cloudAlpha and wset("cloudAlpha", 1.0) then n = n + 1 end
      if n == 0 then return miss("Main.raining") end
      return done("已开始下雨（1.0 = 暴雨；雨量倍率设置仍会接管）")
  end
  H.e_rain_stop = function()
      if not may_write() then return false, NOT_HOST end
      wset("raining", false)
      if F.rainTime then wset("rainTime", 0) end
      if F.maxRaining then wset("maxRaining", 0.0) end
      if F.cloudAlpha then wset("cloudAlpha", 0.0) end
      return done("已放晴")
  end
  H.e_shower = function()
      if not may_write() then return false, NOT_HOST end
      if CALL(M.start_meteor_shower, 0) then return done("流星雨已开始（天上会掉流星）") end
      return miss("WorldGen.StartMeteorShower")
  end
  H.e_meteor = function()
      if not may_write() then return false, NOT_HOST end
      local ok, r = CALL(M.drop_meteor, 1, false)
      if ok then return done("一颗陨石正在落下（会砸在地表，注意别站在落点上）") end
      return miss("WorldGen.dropMeteor(bool)")
  end
  H.e_bulb = function()
      if not may_write() then return false, NOT_HOST end
      local ok, r = CALL(M.bulb_all, 0)
      if not ok then return miss("WorldGen.GeneratePlanteraBulbOnAllMechsDefeated()") end
      if r == true then return done("已生成一朵世纪之花苞（原版判定：地下丛林）") end
      return done("原版这次没找到合适的位置（花苞要地下丛林，再点几次试试）")
  end
  H.e_hardmode = function()
      if not may_write() then return false, NOT_HOST end
      -- ★ 手机版符号表里 StartHardmode 是 0 参，PC 源码里是 (bool force = false) 1 参
      --   → 两个都探一遍，用哪个就用哪个的实参个数（红线 3.5：实参个数必须等于句柄形参个数）
      if CALL(M.hardmode0, 0) then
          return done("已开启困难模式（不可逆）：世界被转化、地下会出现新矿、怪物全面强化")
      end
      if CALL(M.hardmode1, 1, true) then
          return done("已开启困难模式（不可逆）：世界被转化、地下会出现新矿、怪物全面强化")
      end
      if wset("hardMode", true) then
          return done("已把 hardMode 置为真（退化路径：取不到 WorldGen.StartHardmode，"
              .. "不会转化世界、也不会补矿）")
      end
      return miss("WorldGen.StartHardmode / Main.hardMode")
  end
  local function invade(kind, name)
      return function()
          if not may_write() then return false, NOT_HOST end
          local w = P.world
          if w and w.block_invasion then
              return false, "「禁止入侵」开着：已挡下（请先在设置里关掉它，或用 /forge 关）"
          end
          if CALL(M.start_invasion, 1, kind) then return done("已开始" .. name .. "（原版入口 Main.StartInvasion）") end
          return miss("Main.StartInvasion(int)")
      end
  end
  H.e_goblin = invade(1, "哥布林入侵")
  H.e_pirate = invade(2, "海盗入侵")
  H.e_frost = invade(3, "雪人军团")
  H.e_martian = invade(4, "火星暴乱")
  H.e_invade_end = function()
      if not may_write() then return false, NOT_HOST end
      local n = 0
      if F.invasion_size and wset("invasion_size", 0) then n = n + 1 end
      if F.invasion_type and wset("invasion_type", 0) then n = n + 1 end
      if F.invasion_progress and wset("invasion_progress", -1) then n = n + 1 end
      if n == 0 then return miss("Main.invasionSize / invasionType / invasionProgress") end
      return done("入侵已结束（敌人数与进度条清零）")
  end
  H.e_altar = function()
      if not may_write() then return false, NOT_HOST end
      if fget("hardMode") ~= true then
          return false, "祭坛只能砸在困难模式里：请先点「困难模式」"
      end
      local tx, ty = my_tile()
      if not tx then
          local mx, my = fget("max_tiles_x"), fget("max_tiles_y")
          if type(mx) == "number" and type(my) == "number" then tx, ty = math.floor(mx / 2), math.floor(my / 2) end
      end
      if not tx then return miss("本地玩家坐标 / 世界尺寸") end
      if CALL(M.smash_altar, 2, tx, ty) then
          return done("已砸碎一座恶魔祭坛：生成一批困难模式矿石（多砸几次会换矿种）")
      end
      return miss("WorldGen.SmashAltar(int,int)")
  end
  local function set_clock(day, ticks, label)
      return function()
          if not may_write() then return false, NOT_HOST end
          if not F.dayTime or not F.time then return miss("Main.dayTime / Main.time") end
          wset("dayTime", day)
          wset("time", ticks)
          return done("时间已跳到" .. label)
      end
  end
  H.e_dawn = set_clock(true, 0.0, "黎明（4:30）")
  H.e_noon = set_clock(true, 27000.0, "正午（12:00）")
  H.e_dusk = set_clock(false, 0.0, "黄昏（19:30）")
  H.e_midnight = set_clock(false, 16200.0, "午夜（0:00）")
  H.e_moon_full = function()
      if not F.moonPhase then return miss("Main.moonPhase") end
      if not wset("moonPhase", 0) then return false, "写月相失败" end
      return done("月相已置为满月（0 档）")
  end
  H.e_moon_new = function()
      if not F.moonPhase then return miss("Main.moonPhase") end
      if not wset("moonPhase", 4) then return false, "写月相失败" end
      return done("月相已置为新月（4 档）")
  end

  -- ---- 世界特征（走 86 的分帧队列）----
  local function mapgen_ready()
      return type(WGCTL) == "table" and type(WGCTL.spawn_features) == "function"
  end
  local FEAT_ORDER, FEAT_LABELS = nil, nil
  local FEAT_IDX = 1
  local feat_count = 1
  local function feat_meta()
      if FEAT_ORDER then return FEAT_ORDER, FEAT_LABELS end
      local order, labels = {}, {}
      if type(WGCTL) == "table" and type(WGCTL.adhoc) == "function" then
          local ok, o, l = pcall(WGCTL.adhoc)
          if ok and type(o) == "table" and #o > 0 then order, labels = o, (l or {}) end
      end
      FEAT_ORDER, FEAT_LABELS = order, labels
      return order, labels
  end
  local function feat_id()
      local order = feat_meta()
      if #order == 0 then return nil end
      if FEAT_IDX < 1 then FEAT_IDX = #order end
      if FEAT_IDX > #order then FEAT_IDX = 1 end
      return order[FEAT_IDX]
  end
  local function feat_label()
      local order, labels = feat_meta()
      local id = feat_id()
      if not id then return "（无可用类型）" end
      return tostring(labels[id] or id) .. "  " .. tostring(FEAT_IDX) .. "/" .. tostring(#order)
  end
  local function spawn_specs(specs)
      if not mapgen_ready() then return false, NO_MAPGEN end
      local ok, n, fresh, msg = pcall(WGCTL.spawn_features, specs)
      if not ok then return false, "地图生成队列出错：" .. tostring(n) end
      if (n or 0) <= 0 then return false, tostring(msg or "没有可放置的特征") end
      return true, tostring(msg or ("已加入 " .. tostring(n) .. " 个特征"))
  end
  H.f_prev = function()
      local order = feat_meta()
      if #order == 0 then return false, NO_MAPGEN end
      FEAT_IDX = FEAT_IDX - 1
      feat_id()
      return done("当前类型：" .. feat_label())
  end
  H.f_next = function()
      local order = feat_meta()
      if #order == 0 then return false, NO_MAPGEN end
      FEAT_IDX = FEAT_IDX + 1
      feat_id()
      return done("当前类型：" .. feat_label())
  end
  H.f_less = function()
      for i = #COUNTS, 1, -1 do
          if COUNTS[i] < feat_count then feat_count = COUNTS[i] break end
      end
      return done("个数：" .. tostring(feat_count))
  end
  H.f_more = function()
      for i = 1, #COUNTS do
          if COUNTS[i] > feat_count then feat_count = COUNTS[i] break end
      end
      return done("个数：" .. tostring(feat_count))
  end
  H.f_go = function()
      local id = feat_id()
      if not id then return false, NO_MAPGEN end
      return spawn_specs({ { kind = id, count = feat_count } })
  end
  H.f_all = function()
      local order = feat_meta()
      if #order == 0 then return false, NO_MAPGEN end
      local specs = {}
      for i = 1, #order do specs[i] = { kind = order[i], count = 1 } end
      return spawn_specs(specs)
  end
  H.f_stat = function()
      if type(WGCTL) ~= "table" or type(WGCTL.status) ~= "function" then return false, NO_MAPGEN end
      return done(tostring(WGCTL.status()))
  end
  H.f_stop = function()
      if type(WGCTL) ~= "table" or type(WGCTL.cancel) ~= "function" then return false, NO_MAPGEN end
      if WGCTL.cancel() then return done("已取消（已改的部分不回滚）") end
      return done("当前没有进行中的任务")
  end
  local function quick(kind, count)
      return function() return spawn_specs({ { kind = kind, count = count } }) end
  end
  H.q_life20 = quick("life", 20)
  H.q_mana10 = quick("mana", 10)
  H.q_chest5 = quick("chest", 5)
  H.q_cave5 = quick("cave", 5)
  H.q_island1 = quick("island", 1)
  H.q_cloud1 = quick("cloud", 1)
  H.q_lake1 = quick("lake", 1)
  H.q_shimmer1 = quick("shimmer", 1)
  H.q_ore5 = quick("ore", 5)
  H.q_marble2 = quick("marble", 2)
  H.q_orb2 = quick("orb", 2)
  H.q_oasis2 = quick("oasis", 2)
  H.q_grave1 = quick("graveyard", 1)
  H.q_moss5 = quick("moss", 5)
  H.q_glow5 = quick("glowmoss", 5)
  H.q_bee1 = quick("bee", 1)
  H.q_mayan3 = quick("mayan", 3)
  H.q_lava3 = quick("lavatrap", 3)
  H.q_statue3 = quick("statuetrap", 3)
  H.q_gem2 = quick("gemcave", 2)

  -- ---- 玩家 ----
  H.p_heal = function()
      local p = my_player()
      if not p then return miss("Main.player[myPlayer]") end
      if not (F.p_stat_life and F.p_life_max2) then return miss("Player.statLife / statLifeMax2") end
      local life = fget("p_life_max2", p)
      local mana = F.p_mana_max2 and fget("p_mana_max2", p) or nil
      if type(life) ~= "number" then return false, "读不到生命上限" end
      fset("p_stat_life", p, life)
      if type(mana) == "number" and F.p_stat_mana then fset("p_stat_mana", p, mana) end
      return done(string.format("已回满：生命 %d，魔力 %s", life,
          type(mana) == "number" and tostring(mana) or "（读不到上限，未动）"))
  end
  H.p_buffs = function()
      local p = my_player()
      if not p then return miss("Main.player[myPlayer]") end
      if not (F.p_buff_type and M.clear_buff) then return miss("Player.buffType / Player.ClearBuff") end
      local arr = fget("p_buff_type", p)
      if not arr then return false, "读不到减益列表" end
      local n, kinds = 0, {}
      for i = 0, BUFF_SLOTS - 1 do
          local okv, v = pcall(patch.array_at, arr, i, "int32")
          if okv and type(v) == "number" and v > 0 then
              if invoke_instance(M.clear_buff, p, v) then
                  n = n + 1
                  if #kinds < 6 then kinds[#kinds + 1] = tostring(v) end
              end
          end
      end
      if n == 0 then return done("身上没有需要清除的减益") end
      return done(string.format("已清除 %d 个减益（编号 %s%s）", n, table.concat(kinds, ","),
          n > #kinds and " …" or ""))
  end
  H.p_spawn = function()
      local p = my_player()
      if not p then return miss("Main.player[myPlayer]") end
      if not F.position then return miss("Player.position") end
      local sx, sy = nil, nil
      if M.get_spawn_tx then local ok, v = CALL(M.get_spawn_tx, 0) if ok and type(v) == "number" then sx = v end end
      if M.get_spawn_ty then local ok, v = CALL(M.get_spawn_ty, 0) if ok and type(v) == "number" then sy = v end end
      if type(sx) ~= "number" or type(sy) ~= "number" then return miss("Main.spawnTileX / spawnTileY（属性 getter）") end
      -- 玩家碰撞箱 20×42（原版常量）；出生点图格是脚下那一格
      local ok = fset_vec2("position", p, sx * 16 + 8 - 10, sy * 16 - 42)
      if not ok then return false, "写玩家坐标失败" end
      if F.velocity then fset_vec2("velocity", p, 0, 0) end
      return done(string.format("已传送回出生点（格 %d,%d）；若卡在方块里再点一次", sx, sy))
  end
  H.p_items = function()
      if not may_write() then return false, NOT_HOST end
      if not (M.wi_get_type and M.wi_set_type) then return miss("WorldItem.get_type / set_type") end
      local n = scan("item", ITEM_SLOTS, function(o)
          local okv, v = CALLI(M.wi_get_type, o)
          if okv and type(v) == "number" and v ~= 0 then
              if CALLI(M.wi_set_type, o, 0) then return true end
          end
          return false
      end)
      if n == 0 then return done("地上没有掉落物") end
      return done(string.format("已清空地上的 %d 件掉落物", n))
  end
  H.p_enemies = function()
      if not may_write() then return false, NOT_HOST end
      if not F.npc_active then return miss("NPC.active") end
      local n = scan("npc", NPC_SLOTS, function(o)
          if fget("npc_active", o) ~= true then return false end
          if fget("friendly", o) == true then return false end
          if fget("townNPC", o) == true then return false end
          if fget("boss", o) == true then return false end
          return fset("npc_active", o, false)
      end)
      if n == 0 then return done("当前没有可清除的敌怪（Boss、城镇 NPC、友方生物一律不动）") end
      return done(string.format("已驱散 %d 只敌怪（Boss / 城镇 NPC / 友方生物不动）", n))
  end
  H.p_stat = function()
      -- ★ 不调 report()：它是 90_lifecycle 里的 **local**（而且是在本分片之后才声明），
      --   在 87 分片里引用会退化成全局 nil（静态自检也会报前向引用）。
      --   这里直接播报本域自己的汇总行，效果等价、且与分片顺序无关。
      chat_print("[世界工坊] " .. tostring(ONESHOT.summary and ONESHOT.summary() or "一键操作"))
      return done("一键操作汇总已播报（聊天栏）")
  end
  H.p_selfcheck = function()
      pcall(self_check_report)
      return done("自检已播报（聊天栏 + 日志）")
  end

  -- ---- 雷击 ----
  -- ★ fl.li_invoke：本模组的「自发起调用」窗口标志（42 分片的 3 个 prefix 都认它），
  --   所以「禁止雷击」开着时，玩家手动点「头顶劈雷 / 闪光雷声」照样能劈出来。
  -- ★ v10.2：fl.li_force 是「玩家手动点的」标记 —— 42 分片的 on_try_bolt 见到它就全放行
  --   （禁止雷击 / 同屏上限 / 最小间距都不拦）。fl.li_invoke 仍然要置：它让 42 的额外补雷
  --   分支不递归，也让 on_new_lightning 放行。
  local function with_bypass(fn)
      local old, oldf = fl.li_invoke, fl.li_force
      fl.li_invoke, fl.li_force = true, true
      local a, b = fn()
      fl.li_invoke, fl.li_force = old, oldf
      return a, b
  end
  H.l_strike = function()
      if not may_write() then return false, NOT_HOST end
      if not M.try_bolt then return miss("WorldGen.TrySpawnLightningBolt(int,int)") end
      local tx, ty = my_tile()
      if not tx then return miss("本地玩家坐标") end
      local ok, r = with_bypass(function() return CALL(M.try_bolt, 2, tx, ty) end)
      if not ok then return miss("WorldGen.TrySpawnLightningBolt(int,int)") end
      if r == true then return done("已在你头顶劈下一道雷（落点就是你脚下那一格）") end
      return done("原版拒绝了这次落雷（该位置不可劈：多半在室内 / 被遮挡，换个露天位置再试）")
  end
  H.l_flash = function()
      if not M.new_lightning then return miss("Main.NewLightning(bool,bool)") end
      local ok = with_bypass(function() return CALL(M.new_lightning, 2, true, false) end)
      if not ok then return miss("Main.NewLightning(bool,bool)") end
      return done("已来一次屏幕闪光 + 雷声（不含伤害）")
  end
  H.l_clear = function()
      if not may_write() then return false, NOT_HOST end
      if not (F.proj_type and F.proj_active) then return miss("Projectile.type / active") end
      local BOLT = 1091
      local n = scan("main_projectile", 1000, function(o)
          if fget("proj_type", o) == BOLT and fget("proj_active", o) == true then
              return fset("proj_active", o, false)
          end
          return false
      end)
      if n == 0 then return done("当前没有正在劈的落雷") end
      return done(string.format("已驱散 %d 道落雷", n))
  end
  H.l_info = function()
      local li = P.lightning or {}
      local cap = (li.max_bolts and li.max_bolts > 0) and (tostring(li.max_bolts) .. " 道") or "不限制"
      local dist = (li.min_dist and li.min_dist > 0) and (tostring(li.min_dist) .. " 格") or "不额外限制"
      return done(string.format(
          "雷击：禁止=%s，频率 %.0f%%，下落时长 %.0f%%，同时最多 %s，每帧满屏 %d 道，最小间距 %s",
          li.block and "开" or "关", (li.mult or 1) * 100, (li.windup or 1) * 100,
          cap, tonumber(li.spread) or 0, dist))
  end

  -- ---- 娱乐（★ v10.2 新增：都是玩家点一下图个乐，不影响世界数据的都不过 may_write）----
  local FUN_BUFFS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18 }
  H.x_buff = function()
      local p = my_player()
      if not p then return miss("Main.player[myPlayer]") end
      if not M.add_buff then return miss("Player.AddBuff(int,int,bool)") end
      local n = 0
      for i = 1, #FUN_BUFFS do
          if CALLI(M.add_buff, p, FUN_BUFFS[i], 10800, false) then n = n + 1 end
      end
      if n == 0 then return miss("Player.AddBuff(int,int,bool)") end
      return done(string.format("已挂上 %d 个常用增益（约 3 分钟）", n))
  end
  -- ★ NPC.SpawnOnPlayer 在 1.4.5.8 手机版是 6 参：(plr, npcType, ai0..ai3)。原版自己还会判
  --   条件（白天 / 夜晚、有没有别的 Boss），不满足时它会立刻消失 —— 提示里写清楚了。
  local function summon(ty, name)
      return function()
          if not may_write() then return false, NOT_HOST end
          if not M.spawn_on_player then return miss("NPC.SpawnOnPlayer") end
          local plr = my_player_index()
          if not CALL(M.spawn_on_player, 6, plr, ty, 0.0, 0.0, 0.0, 0.0) then
              return miss("NPC.SpawnOnPlayer(int,int,float,float,float,float)")
          end
          return done("已在你身边召唤" .. name .. "（走到开阔地再点，原版条件不满足时它会立刻消失）")
      end
  end
  H.x_slimeking = summon(50, "史莱姆王")
  H.x_eye = summon(4, "克苏鲁之眼")
  H.x_boltstorm = function()
      if not may_write() then return false, NOT_HOST end
      if not M.try_bolt then return miss("WorldGen.TrySpawnLightningBolt(int,int)") end
      local tx, ty = my_tile()
      if not tx then return miss("本地玩家坐标") end
      local mx = fget("max_tiles_x")
      if type(mx) ~= "number" then return miss("Main.maxTilesX") end
      local n, seen = 0, {}
      for _ = 1, 24 do
          local x = tx + math.random(-60, 60)
          if x < 20 then x = 20 end
          if x > mx - 21 then x = mx - 21 end
          if not seen[x] then
              seen[x] = true
              local ok = with_bypass(function() return CALL(M.try_bolt, 2, x, ty) end)
              if ok then n = n + 1 end
          end
      end
      if n == 0 then return miss("WorldGen.TrySpawnLightningBolt(int,int)") end
      return done(string.format("已在你左右各 60 格内劈下 %d 道雷（不受禁止 / 上限 / 间距限制）", n))
  end

  -- ---------------------------------------------------------------- 页面数据（GUI 直接渲染）
  -- 每项：{ id, label }（label 可以是函数 → 每帧取一次动态文字）；只有 label 没有 id = 纯文字。
  local GROUPS = {
      { id = "event", name = "事件", rows = {
          { { id = "e_blood", label = "血月" }, { id = "e_eclipse", label = "日食" },
            { id = "e_slime", label = "史莱姆雨" }, { id = "e_moon_end", label = "结束月事" } },
          { { id = "e_pumpkin", label = "南瓜月" }, { id = "e_snow", label = "霜月" },
            { id = "e_lantern", label = "灯笼夜" }, { id = "e_party", label = "派对" } },
          { { id = "e_sand", label = "沙尘暴" }, { id = "e_sand_stop", label = "停沙尘暴" },
            { id = "e_rain", label = "下雨" }, { id = "e_rain_stop", label = "放晴" } },
          { { id = "e_shower", label = "流星雨" }, { id = "e_meteor", label = "陨石" },
            { id = "e_bulb", label = "花苞" }, { id = "e_hardmode", label = "困难模式" } },
          { { id = "e_goblin", label = "哥布林军" }, { id = "e_pirate", label = "海盗入侵" },
            { id = "e_frost", label = "雪人军团" }, { id = "e_martian", label = "火星暴乱" } },
          { { id = "e_invade_end", label = "结束入侵" }, { id = "e_altar", label = "祭坛矿石" },
            { id = "e_dawn", label = "天亮" }, { id = "e_noon", label = "正午" } },
          { { id = "e_dusk", label = "天黑" }, { id = "e_midnight", label = "午夜" },
            { id = "e_moon_full", label = "满月" }, { id = "e_moon_new", label = "新月" } },
      } },
      { id = "feat", name = "特征", head = {
          { { id = "f_prev", label = "类型 -" }, { label = feat_label },
            { id = "f_next", label = "类型 +" }, { id = "f_all", label = "每样各1" } },
          { { id = "f_less", label = "个数 -" },
            { label = function() return "个数 " .. tostring(feat_count) end },
            { id = "f_more", label = "个数 +" }, { id = "f_go", label = "生成" } },
          { { id = "f_stat", label = "任务状态" }, { id = "f_stop", label = "取消任务" } },
          -- ★ v10.2：生成速度（每帧最多放几个特征）—— 直接给一条真滑块，改的是运行时覆盖层
          { { label = "生成速度（每帧几个）" }, { slider = "wgen_speed" } },
      }, rows = {
          { { id = "q_life20", label = "生命水晶x20" }, { id = "q_mana10", label = "魔力水晶x10" },
            { id = "q_chest5", label = "宝箱x5" }, { id = "q_cave5", label = "洞穴x5" } },
          { { id = "q_island1", label = "浮空岛x1" }, { id = "q_cloud1", label = "云岛x1" },
            { id = "q_lake1", label = "云湖x1" }, { id = "q_shimmer1", label = "微光x1" } },
          { { id = "q_ore5", label = "矿脉x5" }, { id = "q_marble2", label = "大理石x2" },
            { id = "q_orb2", label = "暗影球x2" }, { id = "q_oasis2", label = "绿洲x2" } },
          { { id = "q_grave1", label = "墓地x1" }, { id = "q_moss5", label = "苔藓x5" },
            { id = "q_glow5", label = "发光苔藓x5" }, { id = "q_bee1", label = "蜂巢x1" } },
          { { id = "q_mayan3", label = "神庙陷阱x3" }, { id = "q_lava3", label = "岩浆陷阱x3" },
            { id = "q_statue3", label = "雕像陷阱x3" }, { id = "q_gem2", label = "宝石洞x2" } },
      } },
      { id = "player", name = "玩家", rows = {
          { { id = "p_heal", label = "回满血蓝" }, { id = "p_buffs", label = "清减益" },
            { id = "p_spawn", label = "回出生点" }, { id = "p_items", label = "清掉落物" } },
          { { id = "p_enemies", label = "清空敌怪" }, { id = "p_stat", label = "状态播报" },
            { id = "p_selfcheck", label = "重跑自检" } },
      } },
      { id = "fun", name = "娱乐", rows = {
          { { id = "x_buff", label = "全套增益" }, { id = "x_slimeking", label = "史莱姆王" },
            { id = "x_eye", label = "克苏鲁之眼" }, { id = "x_boltstorm", label = "满屏落雷" } },
      } },
      { id = "bolt", name = "雷击", head = {
          { { slider = "lightning_windup_mult" } },
          { { slider = "lightning_max_bolts" } },
      }, rows = {
          { { id = "l_strike", label = "头顶劈雷" }, { id = "l_flash", label = "闪光雷声" },
            { id = "l_clear", label = "驱散落雷" }, { id = "l_info", label = "雷击状态" } },
      } },
  }

  -- ---------------------------------------------------------------- 对外接口
  local function run(id)
      local fn = H[id]
      if not fn then return "未知操作：" .. tostring(id) end
      local ok, a, b = pcall(fn)
      if not ok then
          OS.errs = OS.errs + 1
          OS.last_err = tostring(a)
          return "执行出错：" .. tostring(a)
      end
      local good, msg = a, b
      if good then
          OS.hits = OS.hits + 1
          dcount(OS, id, 1)
      end
      local text = tostring(msg or "")
      ONESHOT.last = text
      if log_allowed() then diag("一键操作 " .. tostring(id) .. "：" .. text) end
      return text
  end

  ONESHOT.groups = GROUPS
  ONESHOT.run = run
  ONESHOT.label = function(g) return tostring(g and g.name or "") end
  ONESHOT.feature = function() return feat_id(), feat_label(), feat_count end
  -- 供 GUI 用的只读汇总（一行）
  ONESHOT.summary = function()
      return string.format("上次的一键操作：%s", tostring(ONESHOT.last or "（还没用过）"))
  end
  ONESHOT.last = "（还没用过）"

  -- ---------------------------------------------------------------- 全局入口
  -- 与 report / self_check_report / setup 同一个风格：供 95_chat 的 /forge one 使用，
  -- 逻辑测试也从这里直接驱动每一条一键操作（不必模拟 GUI 点击）。
  function oneshot_run(id) return run(id) end
  function oneshot_ids()
      local ids = {}
      for i = 1, #GROUPS do
          local g = GROUPS[i]
          local function take(list)
              if type(list) ~= "table" then return end
              for r = 1, #list do
                  local row = list[r]
                  if type(row) == "table" then
                      for c = 1, #row do
                          local it = row[c]
                          if type(it) == "table" and it.id then ids[#ids + 1] = it.id end
                      end
                  end
              end
          end
          take(g.head)
          take(g.rows)
      end
      return ids
  end

  OS = domain({
      name = "一键操作",
      fields = function(T)
          -- 玩家自身状态（全是 public 实例字段，非 const、非属性）
          register("p_stat_life", T.PLAYER, "statLife", "int32")
          register("p_stat_mana", T.PLAYER, "statMana", "int32")
          register("p_life_max2", T.PLAYER, "statLifeMax2", "int32")
          register("p_mana_max2", T.PLAYER, "statManaMax2", "int32")
          register("p_buff_type", T.PLAYER, "buffType", "object")
          -- 清掉落物要扫的 Main.item（WorldItem[]，public static 非 const，已进 KNOWN_STATIC 白名单）
          register("item", T.MAIN, "item", "object")
          -- ★ position / velocity / npc_active / friendly / townNPC / boss 这些键
          --   由前面的分片注册过（65_death / 60_spawn / 50_npc），这里直接复用，不再重复注册。
      end,
      methods = function(T)
          -- 事件入口（形参个数对着 1.4.5.8 手机版方法表核过）
          M.start_slime_rain = T.MAIN and find_method(T.MAIN, "StartSlimeRain", 1)
          M.start_pumpkin_moon = T.MAIN and find_method(T.MAIN, "startPumpkinMoon", 0)
          M.start_snow_moon = T.MAIN and find_method(T.MAIN, "startSnowMoon", 0)
          M.stop_moon_event = T.MAIN and find_method(T.MAIN, "stopMoonEvent", 0)
          M.start_invasion = T.MAIN and find_method(T.MAIN, "StartInvasion", 1)
          M.new_lightning = T.MAIN and find_method(T.MAIN, "NewLightning", 2)
          M.get_spawn_tx = T.MAIN and find_method(T.MAIN, "get_spawnTileX", 0)
          M.get_spawn_ty = T.MAIN and find_method(T.MAIN, "get_spawnTileY", 0)
          M.sand_start = T.SAND and find_method(T.SAND, "StartSandstorm", 0)
          M.sand_stop = T.SAND and find_method(T.SAND, "StopSandstorm", 0)
          M.start_meteor_shower = T.WORLDGEN and find_method(T.WORLDGEN, "StartMeteorShower", 0)
          M.drop_meteor = T.WORLDGEN and find_method(T.WORLDGEN, "dropMeteor", 1)
          M.bulb_all = T.WORLDGEN and find_method(T.WORLDGEN,
              "GeneratePlanteraBulbOnAllMechsDefeated", 0)
          M.smash_altar = T.WORLDGEN and find_method(T.WORLDGEN, "SmashAltar", 2)
          M.try_bolt = T.WORLDGEN and find_method(T.WORLDGEN, "TrySpawnLightningBolt", 2)
          -- ★ StartHardmode：手机版符号表 0 参，PC 源码 (bool force = false) 1 参 → 两个都探
          M.hardmode0 = T.WORLDGEN and find_method(T.WORLDGEN, "StartHardmode", 0)
          M.hardmode1 = T.WORLDGEN and find_method(T.WORLDGEN, "StartHardmode", 1)
          -- 玩家清减益（1 参实例方法）
          M.clear_buff = T.PLAYER and find_method(T.PLAYER, "ClearBuff", 1)
          -- ★ v10.2：一键「全套增益」（实例方法，3 参：type, time, fromNetPvP）
          M.add_buff = T.PLAYER and find_method(T.PLAYER, "AddBuff", 3)
          -- 地上掉落物：WorldItem.active 是**只读属性**（= type != 0），所以清掉落物 = 把 type 置 0
          if T.WORLDITEM then
              M.wi_get_type = find_method(T.WORLDITEM, "get_type", 0)
              M.wi_set_type = find_method(T.WORLDITEM, "set_type", 1)
          end
      end,
      -- 本域不装任何钩子（一键操作都是被动的：点了才做）
  })
  end)()
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do

  -- ============================================================================
  -- 88 · 微光配方（ShimmerTransformToItem）
  -- ----------------------------------------------------------------------------
  -- 取证：
  --   · 微光嬗变表是 `ItemID.Sets.ShimmerTransformToItem`（int[]，下标 = 源物品编号、
  --     值 = 嬗变产物编号）。`ItemID.Sets` 是**嵌套类型**，`get_type` 取不到，
  --     必须 `patch.get_inner_type(ItemID, "Sets")`（`参考库/api/lualoader-1.6.3.tsv:38`）。
  --   · 写法有现成先例：`参考库/lua/forgotten-item-refresh/main.lua:208 / 500-513` ——
  --     取字段 → `get_field_value(f, nil, "object")` 拿托管数组 → 逐个写元素；
  --     并且它**还挂了 `ItemID.Sets..cctor` 的 postfix 重新应用一次**，
  --     因为静态构造会把这些表重建。本分片照抄这个套路。
  --   · ★ 为什么配方要用户手填、不内置？物品编号猜错等于往别人存档里写错的嬗变规则
  --     （不可逆），所以本模组只提供**通道**：默认空表，行为与原版完全一致。
  --     格式「源=产物」，多条逗号隔开，与「生物分类覆盖表」同一套解析风格。
  -- ============================================================================

  local SHM         -- ★ 前向声明：apply_shimmer 与回调体里要引用它（诊断计数器）

  local shimmer_pairs = {}              -- { {src, dst}, ... }，由设置解析而来
  -- ★ v4：产物数量。原版嬗变表 ShimmerTransformToItem 只有「源→产物」一个整数，
  --   表达不了数量；所以数量靠挂 WorldItem.SpawnShimmeredItem(int itemNumber, int type, int stack)
  --   的 postfix 再补几次（该方法就是微光产出物品的唯一出口，PC WorldItem.cs:629）。
  --   键 = 产物编号（因为调用点只拿得到产物），值 = 想要的总数量。
  local shimmer_count = {}              -- [产物编号] = 数量(>=1)
  local shimmer_applied = {}            -- 本模组写过的 { src, 原值 }，用来还原（三态幂等的老规矩）
  local shimmer_dirty = true            -- reload 只置标志；真正的写入推迟到进世界后的帧阶段
                                        -- （红线 1：setup 里绝不读写字段值）

  -- 支持两种写法：`源=产物` 与 `源=产物*数量`（数量 1~999，省略按 1）
  local function parse_shimmer(s)
      local t, cnt = {}, {}
      if type(s) ~= "string" or s == "" then return t, cnt end
      for seg in s:gmatch("[^,，;；]+") do
          local a, b, c = seg:match("(%d+)%s*[=:]%s*(%d+)%s*[%*xX]%s*(%d+)")
          local n = 1
          if a then
              n = tonumber(c) or 1
              if n < 1 then n = 1 end
              if n > 999 then n = 999 end
          else
              a, b = seg:match("(%d+)%s*[=:]%s*(%d+)")
          end
          local src, dst = tonumber(a), tonumber(b)
          if src and dst and src >= 1 and src <= 6000 and dst >= 0 and dst <= 6000 then
              t[#t + 1] = { src, dst }
              if dst > 0 and n > 1 then cnt[dst] = n end
          end
      end
      return t, cnt
  end

  -- full = true 时才做「任意物品→任意物品」的整表填充（约 5000 个下标，只在设置变化/
  -- 进世界时做一次）；周期性重申只重写用户手填的那几条，避免每 5 秒写 5000 次数组元素。
  local function apply_shimmer(full)
      if not ready then return end
      if not may_write() then return end
      local arr = get_object("shimmer_map")
      if not arr then return end
      -- ① 先把上一次写过的还原（设置改了、或者关掉了开关，都要还回去）
      for i = 1, #shimmer_applied do
          pcall(patch.array_set, arr, shimmer_applied[i][1], shimmer_applied[i][2], "int32")
      end
      shimmer_applied = {}
      -- ② v5：任意物品→任意物品（把整张表里「原本不嬗变」的下标全部填成目标产物）
      if full and P.shimmer.any and P.shimmer.any > 0 then
          local okn, n = pcall(patch.array_length, arr)
          if okn and type(n) == "number" and n > 0 then
              local filled = 0
              for idx = 0, n - 1 do
                  local okv, v = pcall(patch.array_at, arr, idx, "int32")
                  if okv and type(v) == "number" and v == 0 then
                      local oks = pcall(patch.array_set, arr, idx, P.shimmer.any, "int32")
                      if oks then
                          shimmer_applied[#shimmer_applied + 1] = { idx, 0 }
                          filled = filled + 1
                      end
                  end
              end
              if filled > 0 then
                  SHM.hits = SHM.hits + filled
                  dcount(SHM, "任意嬗变填充", filled)
                  verbose("微光：任意物品→任意物品，已填 " .. filled .. " 个下标")
              end
          end
      end
      if not P.shimmer.on or #shimmer_pairs == 0 then return end
      -- ② 再写新的；写之前把原值记下来，供下次还原
      local n = 0
      for i = 1, #shimmer_pairs do
          local src, dst = shimmer_pairs[i][1], shimmer_pairs[i][2]
          local old = 0
          local ok0, v = pcall(patch.array_at, arr, src, "int32")
          if ok0 and type(v) == "number" then old = v end
          local ok, r = pcall(patch.array_set, arr, src, dst, "int32")
          if ok and r ~= false then
              shimmer_applied[#shimmer_applied + 1] = { src, old }
              n = n + 1
          end
      end
      if n > 0 then
          stats.shimmer_sets = (stats.shimmer_sets or 0) + n
          SHM.hits = SHM.hits + n
          dcount(SHM, "手填配方", n)
          verbose("微光配方已写入 " .. n .. " 条")
      elseif not warned["shimmer_arr"] then
          warned["shimmer_arr"] = true
          mod.warn("写 ShimmerTransformToItem 失败，微光配方已跳过")
      end
  end

  -- ★ v4：产物数量。SpawnShimmeredItem 是微光产出物品的唯一出口，postfix 里再补几次即可。
  --   args 是 1 起始：args[1] = itemNumber, args[2] = type, args[3] = stack。
  --   自己发的调用会再次进入本 postfix，所以必须有 in_spawn 递归保护。
  local in_spawn = false

  local function on_spawn_shimmered(inst, args)
      if not ready or in_spawn then return end
      if not P.shimmer.on then return end
      if not may_write() then return end
      if not inst or not args then return end
      local item_number, itype, stack = args[1], args[2], args[3]
      if type(itype) ~= "number" or type(stack) ~= "number" or stack < 1 then return end
      local want = shimmer_count[itype]
      if not want or want <= 1 then return end
      local extra = stack * (want - 1)
      if extra < 1 then return end
      if extra > 9999 then extra = 9999 end
      in_spawn = true
      local ok, err = invoke_instance(M.shimmer_spawn, inst, item_number, itype, extra)
      in_spawn = false
      if ok then
          stats.shimmer_extra = (stats.shimmer_extra or 0) + extra
      else
          warn_once("shimmer_extra", "微光产物加量失败：" .. tostring(err))
      end
  end

  -- 静态构造会把整张表重建回原版 → 旧的原值记录作废，等帧阶段重写一遍
  local function on_sets_cctor()
      shimmer_applied = {}
      shimmer_dirty = true
  end

  -- ItemID.Sets 是嵌套类型：优先 get_inner_type，失败再退回 get_inner_types 枚举
  local function find_sets()
      local tid = get_type("Terraria.ID", "ItemID")
      if not tid then return nil end
      if patch.get_inner_type then
          local ok, s = pcall(patch.get_inner_type, tid, "Sets")
          if ok and s then return s end
      end
      if patch.get_inner_types then
          local ok, list = pcall(patch.get_inner_types, tid)
          if ok and type(list) == "table" then
              for i = 1, #list do
                  local ok2, nm = pcall(patch.get_full_name, list[i])
                  if ok2 and type(nm) == "string" and nm:find("Sets", 1, true) then return list[i] end
              end
          end
      end
      return nil
  end

  SHM = domain({
      name = "微光配方",
      fields = function(T)
          local sets = find_sets()
          if sets then
              T.ITEMID_SETS = sets
              register("shimmer_map", sets, "ShimmerTransformToItem", "object")
          else
              warn_once("shimmer_sets", "找不到 ItemID.Sets（需要 get_inner_type），微光配方已跳过")
          end
      end,
      methods = function(T)
          -- v4：ItemID.Sets 在 1.4.5.8 手机版**没有 .cctor**（符号表核实），
          -- 所以改用「帧阶段周期性重申」来对抗静态构造重建，见下面的 frame。
          -- v4：产物数量的补发出口（public void，3 参：itemNumber / type / stack）
          M.shimmer_spawn = T.WORLDITEM and find_method(T.WORLDITEM, "SpawnShimmeredItem", 3)
      end,
      install = function()
          -- 静态构造会把整张表重建 → 必须挂它的 postfix 重新写一遍（照抄先例）
          safe_hook(M.shimmer_spawn, { postfix = on_spawn_shimmered }, "WorldItem.SpawnShimmeredItem")
      end,
      -- ★ reload 只做纯 Lua 的解析：它在 setup 第 5 阶段就会被调到，那时候碰字段值 = 违反红线 1。
      --   真正的写入交给帧阶段（进世界之后才跑），中间用 shimmer_dirty 传递。
      reload = function()
          shimmer_pairs, shimmer_count = parse_shimmer(cfg.shimmer_recipes)
          shimmer_dirty = true
      end,
      frame = function()
          -- 帧阶段本身就是 30 帧一次；默认每 10 次（约 5 秒）重申一遍，
          -- 这样即使 ItemID.Sets 被静态构造重建过（本机没有 .cctor 可挂）也能自动纠正。
          mem.shimmer_tick = (mem.shimmer_tick or 0) + 1
          if not shimmer_dirty and (mem.shimmer_tick % 10) ~= 0 then return end
          local full = shimmer_dirty
          shimmer_dirty = false
          pcall(apply_shimmer, full)
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 44 · 液体世界：分帧把水 / 岩浆 / 蜂蜜灌进世界下半部（v5 新增）
  -- ----------------------------------------------------------------------------
  -- 取证与写法（参考 旧模组-CPP-123/水世界制作者.cpp，只借思路）：
  --   · 原版唯一的「放置液体」出口是 `WorldGen.PlaceLiquid(int x, int y, byte liquidType,
  --     byte amount)`（**4 个标量参、public static**，符号表已核实）。
  --     ★ 它内部自己判 `tile.nactive() && Main.tileSolid[tile.type] && !Main.tileSolidTop[...]`
  --       就直接返回 false，所以**实心方块一律会被原版拒绝**，我们不必逐格读 Tile
  --       （手机版 Tile.type 是**属性**，只能 invoke getter，逐格读成本极高，正好躲开）。
  --   · 液体类型：0 = 水、1 = 岩浆、2 = 蜂蜜（原版枚举值）。
  --   · 地形是 3 维的：从世界最底层的最右一列开始，x 递减、列末换行、y 递减，
  --     一直灌到「液面高度」。整个过程分帧（每帧由「每秒灌注格数」控制），
  --     每 600 帧（约 10 秒）在聊天栏播一次进度，灌完再播一次并自动停手。
  --   · 关掉开关 = 立刻停在当前游标（已灌进去的液体不回收，也不会回退游标，
  --     下次再开会从断点继续）。
  -- ★ 默认关闭（liquid_mode = off）：默认路径上本分域一行都不执行。
  -- ============================================================================

  local LQ          -- ★ 前向声明：world 回调体里要引用它
  LQ = domain({
      name = "液体世界",
      -- maxTilesX / maxTilesY 由 40_world 注册（同一个句柄表），这里不再重复注册
      methods = function(T)
          M.place_liquid = T.WORLDGEN and find_method(T.WORLDGEN, "PlaceLiquid", 4)
          -- ★ v7：冻结液体 = 跳过原版 Liquid.UpdateLiquid()（0 参 public static）
          local T_LQ = get_type("Terraria", "Liquid")
          M.liquid_update = T_LQ and find_method(T_LQ, "UpdateLiquid", 0)
      end,
      install = function()
          -- ★ v7：冻结液体（prefix 返回 true = 跳过原方法：液体不再流动 / 平衡水位）。
          --   只影响本机表现、不改世界数据，所以不受「仅房主生效」限制。
          safe_hook(M.liquid_update, { prefix = function(inst, args)
              if not ready then return nil end
              if not (P.liquid and P.liquid.freeze) then return nil end
              LQ.hits = LQ.hits + 1
              dcount(LQ, "冻结液体帧", 1)
              return true
          end }, "Liquid.UpdateLiquid")
      end,
      world = function()
          local pl = P.liquid
          if not pl or not pl.on then return end
          LQ.hits = LQ.hits + 1
          if not may_write() then return end
          if not M.place_liquid then
              LQ.errs = LQ.errs + 1
              LQ.last_err = "取不到 WorldGen.PlaceLiquid(int,int,byte,byte)"
              return
          end
          local mx = fget("max_tiles_x")
          local my = fget("max_tiles_y")
          if type(mx) ~= "number" or type(my) ~= "number" or mx < 1 or my < 1 then return end

          -- 游标：x 从最右列往左，y 从最底行往上；液面 = 世界高度 × 高度百分比
          local top = math.floor(my * (pl.height or 50) / 100)
          if top < 0 then top = 0 end
          if top > my then top = my end
          if mem.lq_x == nil or mem.lq_top ~= top or mem.lq_type ~= pl.type then
              mem.lq_x, mem.lq_y = mx - 1, my - 1
              mem.lq_top, mem.lq_type, mem.lq_done = top, pl.type, false
              mem.lq_next = 0
          end
          if mem.lq_done then return end

          local budget = pl.rate or 500
          local ok_n, fail_n = 0, 0
          while budget > 0 do
              local x, y = mem.lq_x, mem.lq_y
              local ok = invoke_checked(M.place_liquid, 4, x, y, pl.type, 255)
              if ok then ok_n = ok_n + 1 else fail_n = fail_n + 1 end
              budget = budget - 1
              x = x - 1
              if x < 0 then
                  x = mx - 1
                  y = y - 1
                  if y < top then
                      mem.lq_done = true
                      mem.lq_x, mem.lq_y = x, y
                      break
                  end
              end
              mem.lq_x, mem.lq_y = x, y
          end
          if ok_n > 0 then dcount(LQ, "灌注格", ok_n) end
          if fail_n > 0 then dcount(LQ, "原版拒收", fail_n) end

          -- 进度播报：约 10 秒一次 + 灌完一次
          if mem.lq_done then
              chat_print("[世界工坊] 液体灌注完成（已灌到液面高度）")
              verbose("液体灌注完成")
          elseif stats.frames >= (mem.lq_next or 0) then
              mem.lq_next = stats.frames + 600
              local pct = 100
              local span = (my - top)
              if span > 0 then pct = math.floor((my - 1 - mem.lq_y) * 100 / span + 0.5) end
              if pct < 0 then pct = 0 end
              if pct > 100 then pct = 100 end
              chat_print(string.format("[世界工坊] 液体灌注中：约 %d%%（可随时关掉「灌注液体」停止）", pct))
          end
      end,
      reset = function()
          mem.lq_x, mem.lq_y, mem.lq_done = nil, nil, false
          mem.lq_top, mem.lq_type, mem.lq_next = nil, nil, 0
      end,
  })
end


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 46 · 世界边缘限制取消 / 重力药水屏幕不翻转（v5 新增，两条独立开关）
  -- ----------------------------------------------------------------------------
  -- ① 世界边缘限制取消（world_edge_free）
  --    证据（旧模组-CPP-123/世界边缘取消限制.cpp 的登记表，只借思路）：
  --      · `Terraria.Player.BordersMovement()`            0 参、**实例**、public
  --      · `Terraria.Main.ClampScreenPositionToWorld()`    0 参、**静态**、public
  --      手机版两个都在，符号表已核实。旧 C++ 模组把它们 hook 成「不调用原方法」，
  --      就等于玩家 / 镜头不再被世界边界推回来 —— 我们这边对应 `prefix` 返回 true。
  --      ★ 只影响本机表现（玩家位置与镜头），不改世界数据，所以不受「仅房主生效」限制。
  --
  -- ② 重力药水屏幕不翻转（gravity_no_flip）
  --    证据（旧模组-CPP-123/重力药水屏幕不翻转.cpp）：
  --      · `Player.gravControl`(bool,0xBFC) / `Player.gravControl2`(bool,0xBFD)
  --      · `Player.gravDir`(float,0x84C)
  --      它的做法是 hook `Player.Update(int)` 的 postfix：当玩家身上有「重力控制」
  --      （重力药水 / 重力球）且 gravDir == −1 时，把 gravDir 写成 −0.99 ——
  --      原版用 `gravDir == −1` 判定「大头朝下」来翻转屏幕与操作，
  --      −0.99 既保留下落的物理方向，又不触发翻转。三处符号均已核实（见 README）。
  --      ★ `Player.ResetEffects` 归心跳（同一方法不能装第二个钩子），所以这里挂
  --        `Player.Update(int)`（每帧对每个玩家各一次，第一行早退，独立开关控制）。
  -- ============================================================================


  local MS          -- ★ 前向声明：三个回调体里都要引用它（Lua 词法作用域）

  -- 世界边缘：跳过原方法 = 不再把玩家 / 镜头推回世界内
  local function on_borders_movement(inst, args)
      if not ready or not P.misc.edge_free then return end
      MS.hits = MS.hits + 1
      dcount(MS, "边缘放行", 1)
      return true
  end

  local function on_clamp_screen(inst, args)
      if not ready or not P.misc.edge_free then return end
      MS.hits = MS.hits + 1
      dcount(MS, "镜头放行", 1)
      return true
  end

  -- 重力药水：把「完全倒转」-1 改成 -0.99，物理方向不变、屏幕不翻转
  local function on_player_update(inst, args)
      if not ready or not P.misc.no_flip then return end
      if not inst then return end
      if not (F.grav_control and F.grav_dir) then return end
      local g1 = fget("grav_control", inst)
      local g2 = F.grav_control2 and fget("grav_control2", inst) or false
      if g1 ~= true and g2 ~= true then return end
      local dir = fget("grav_dir", inst)
      if type(dir) ~= "number" or dir > -0.995 then return end
      MS.hits = MS.hits + 1
      if fset("grav_dir", inst, -0.99) then dcount(MS, "屏幕不翻转", 1) end
  end

  MS = domain({
      name = "世界边缘与重力",
      fields = function(T)
          register("grav_control", T.PLAYER, "gravControl", "bool")
          register("grav_control2", T.PLAYER, "gravControl2", "bool")
          register("grav_dir", T.PLAYER, "gravDir", "float")
      end,
      methods = function(T)
          M.borders_movement = T.PLAYER and find_method(T.PLAYER, "BordersMovement", 0)
          M.clamp_screen = T.MAIN and find_method(T.MAIN, "ClampScreenPositionToWorld", 0)
          M.player_update = T.PLAYER and find_method(T.PLAYER, "Update", 1)
      end,
      install = function()
          safe_hook(M.borders_movement, { prefix = on_borders_movement }, "Player.BordersMovement")
          safe_hook(M.clamp_screen, { prefix = on_clamp_screen }, "Main.ClampScreenPositionToWorld")
          safe_hook(M.player_update, { postfix = on_player_update }, "Player.Update（重力不翻转）")
      end,
  })
end



-- ============================================================================
-- 90 · 生命周期：心跳 / 设置热重载 / setup / cleanup / 诊断报告
-- ============================================================================

local last_cfg_check = 0
local report                    -- 前向声明：tick() 要用它，定义在本文件后半段

-- 换世界 / 回主菜单时，现场学出来的分类与基准值全部作废：
--   · 分类（type_cat）本身不会错，但覆盖表可能刚改过；
--   · 基准值（type_base）在**另一个世界**里没有任何意义 —— 新世界的原版值会被
--     误判成「第三方改过的值」，进而把倍率算错。
local function rehash_world_state()
    type_cat, type_base = {}, {}
    -- v3：各功能域自己登记的「换世界就作废」的缓存（稀有标记 / 一次性动作标志）
    for i = 1, #DOMAINS do
        local fn = DOMAINS[i].phase and DOMAINS[i].phase.reset
        if fn then pcall(fn) end
    end
    mem.meteor_done, mem.bulb_done, mem.bulb_next, mem.merchant_day = false, false, nil, nil
end

-- 心跳：每帧一次（挂在 Player.ResetEffects 的 postfix，静态方法挂不上时由
-- Main.UpdateTimeRate 的 postfix 兜底），重活按 30 帧 / 3 秒限流。
-- ★ v5：进世界检测加速。手机版 Main.gameMenu 是**属性**，只能 invoke getter；
--   30 帧一拍的旧节拍会让「进世界后的第一帧播报」迟到最多 0.5 秒。
--   这里只在「还没进过本世界」时每 6 帧探一次（一次 0 参属性读，可忽略），
--   一进世界就把 menu_flag 翻过来，并安排 2 帧后播报自检（让各域至少跑过一帧）。
local function quick_menu_probe()
    if F.gameMenu then
        local ok, v = pcall(patch.get_field_value, F.gameMenu, nil, "bool")
        if ok and v == false then return false end
    elseif M.get_game_menu then
        local ok, v = pcall(patch.invoke, M.get_game_menu)
        if ok and v == false then return false end
    end
    return true
end

function tick()
    stats.frames = stats.frames + 1
    tick_i = tick_i + 1                    -- 分桶节拍：必须在 30 帧限流之前自增
    if tick_i > 100000000 then tick_i = 0 end

    -- ---- v5：进世界快速探测（≤6 帧，只在首次进世界之前生效）----
    if ready and menu_flag and not world_entered and (stats.frames % 6) == 0 then
        if not quick_menu_probe() then
            menu_flag = false
            diag("已进入世界（快速探测）")
            diag_flush()
        end
    end

    -- ---- v5：进世界的边沿（无论从哪条路翻过来的），安排 2 帧后播报自检 ----
    --   等 2 帧是为了让各功能域至少完整跑过一帧，播报里的「命中次数」才有意义。
    if ready and not menu_flag and not world_entered then
        world_entered = true
        mem.self_check_at = stats.frames + 2
        -- ★ v5.0.0：聊天指令默认关闭 → 每次进世界补一条一次性提示（与 self_check 解耦）
        if not cfg.chat_cmd then mem.chat_tip_at = stats.frames + 2 end
        -- ★ v5.0.0：设置项「自动导出设置串」打开时，进世界后自动导一次
        --   （落盘 forge_export.txt + 游戏内播报；与聊天指令完全无关）
        if cfg.export_mode then mem.export_at = stats.frames + 2 end
    end

    -- ---- v5：启动自检 / 诊断播报（一次性，每进一次世界一次）----
    if ready and not menu_flag and mem.self_check_at and stats.frames >= mem.self_check_at then
        mem.self_check_at = nil
        if cfg.self_check ~= false then pcall(self_check_report) end
    end
    -- ---- v5.0.0：聊天默认关闭的一次性提示（只有一行；关掉 self_check 也照发一次）----
    if ready and not menu_flag and mem.chat_tip_at and stats.frames >= mem.chat_tip_at then
        mem.chat_tip_at = nil
        pcall(chat_tip_report)
    end
    -- ---- v5.0.0：自动导出（一次性，每进一次世界一次）----
    if ready and not menu_flag and mem.export_at and stats.frames >= mem.export_at then
        mem.export_at = nil
        pcall(auto_export_report, "进世界自动导出")
    end

    -- ★ 安全网：窗口标志绝不允许跨帧残留。
    --   残留的具体后果：world_update 会让旅行模式的「停止蔓延」串味（把时间/雨/风一起冻住），
    --   pylon_request 会一直免危险，natural_spawn 会让非自然生成也被拦。
    --   这里无条件清零：产生这些标志的调用是**同步**的（SpawnNPC → NewNPC → … → postfix
    --   全在一次 C# 调用里），中间不可能插进一次心跳，所以清零不会打断任何窗口。
    fl.world_update = false
    fl.pylon_request = false
    fl.score_room = 0
    fl.spawn_dead = false
    fl.boss_summon = false
    fl.sp_invoke = false
    fl.artisan_saved = nil
    fl.artisan_touched = false
    spawn_win.natural = false
    spawn_win.in_dup = false

    if stats.frames ~= 1 and stats.frames % 30 ~= 0 then return end
    stats.ticks = stats.ticks + 1

    -- ---- 主菜单判定（每 30 帧一次，只读一个 bool）----
    -- v4：1.4.5.8 手机版里 Main.gameMenu 是**属性**（符号表「修饰」列带 [属性]），
    -- get_field 必然返回 nil（05 §4.6）→ 旧版永远以为「已经进世界」。这里补 get_gameMenu() 兜底。
    local in_menu, got_menu = false, false
    if F.gameMenu then
        local ok, v = pcall(patch.get_field_value, F.gameMenu, nil, "bool")
        if ok and type(v) == "boolean" then in_menu, got_menu = v, true end
    end
    if not got_menu and M.get_game_menu then
        local ok, v = pcall(patch.invoke, M.get_game_menu)
        if ok and type(v) == "boolean" then in_menu = v end
    end
    if in_menu ~= menu_flag then
        menu_flag = in_menu
        if menu_flag then
            rehash_world_state()
            mem.self_check_at = nil
            mem.chat_tip_at = nil
            mem.export_at = nil
            world_entered = false
            diag("回到主菜单：分类与基准值缓存已清空")
        else
            diag("已进入世界")
        end
        diag_flush()
    end
    -- ★ v5：这里**不再**直接置 world_entered —— 「进世界的边沿 + 自检播报安排」统一交给
    --   tick() 开头那段每帧都跑的代码（本块每 30 帧才跑一次，抢先把 world_entered 置 true
    --   会让自检永远排不上号，实测就是这么漏掉的）。

    -- ---- 设置热重载（间隔由「自动重读设置间隔」决定；同一节拍也刷新 netMode 缓存）----
    local now = os.time()
    local reload_gap = (P.reload_sec or 5)
    if reload_gap < 1 then reload_gap = 1 end
    if type(now) == "number" and (now - last_cfg_check >= reload_gap) then
        last_cfg_check = now
        if cfg.hot_reload then
            local ok, changed = pcall(read_config)
            if ok and changed then
                build_plans()
                -- v3：设置变了要让功能域有机会重算自己的缓存（微光配方表 / 稀有标记）
                for i = 1, #DOMAINS do
                    local fn = DOMAINS[i].phase and DOMAINS[i].phase.reload
                    if fn then pcall(fn) end
                end
                stats.reloads = stats.reloads + 1
                report("设置已重读")
                -- ★ v5.0.0：开着「自动导出设置串」时，改完设置就顺带重导一次
                --   （export_channel 只导非默认项；没有非默认项时它自己会说明并返回）
                if cfg.export_mode then pcall(auto_export_report, "设置重读自动导出") end
            end
            -- ★ v5.0.0（§9.3）：这一段**每拍都查**，不只在文件变化时查。
            --   理由：玩家把串粘贴进「导入设置串」后，TEFManager 写出来的可能恰好是
            --   与上次一模一样的字节（例如上一拍已经读到过同一份内容），
            --   read_config 会因 `raw == last_raw` 直接返回 false；
            --   poll_import_string 自己用 mem.last_import 去重，所以每拍调用也不会重复导入。
            --   ★ 放在这里（而不是上面的 if changed 里）：热重载开着就一定能被检测到，
            --     单机与客机都可用 —— 配置文件在本机，客机也能改自己的设置，完全不依赖聊天。
            pcall(poll_import_string)
        end
    end

    -- v3：各功能域的慢速帧逻辑（旅商每日召唤 / 一次性动作）。全部第一行早退。
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        local fn = d.phase and d.phase.frame
        if fn then
            d.calls = d.calls + 1
            local t0 = os.clock()
            local ok, err = pcall(fn)
            local dt = os.clock() - t0
            if dt > 0 then d.t = d.t + dt end
            d.n = d.n + 1
            if not ok then
                d.errs = d.errs + 1
                d.last_err = tostring(err)
            end
        end
    end
end

local function on_reset_effects(inst)
    if not ready then return end
    pcall(tick)
end

-- 诊断报告：把「现在到底哪些功能在动手」压成一行，改设置时输出一次
-- ---------------------------------------------------------------- v5：功能域状态与诊断
-- 「句柄」= 该域在 fields/methods 两个安装阶段里成功解析到的数量 vs 失败的数量；
-- 「钩子」= 该域在 install 阶段装成功的钩子数 vs 尝试数。两者都在安装期一次性算完。
local function state3(ok, miss)
    if ok > 0 and miss == 0 then return "ok" end
    if ok > 0 then return "partial" end
    if miss > 0 then return "fail" end
    return "none"
end

local function domain_label(state)
    if state == "ok" then return "✅" end
    if state == "partial" then return "⚠" end
    if state == "fail" then return "❌" end
    return "—"
end

local function eval_domain_labels()
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        d.fields = state3(d.n_fields_ok, d.n_fields_miss)
        d.methods = state3(d.n_methods_ok, d.n_methods_miss)
        d.hooks = state3(d.n_hooks_ok, d.n_hooks_try - d.n_hooks_ok)
    end
end

-- 命名计数器摘要（最多 5 个），用于自检与 /forge stat
local function counter_summary(d)
    local keys = {}
    for k, v in pairs(d.c) do
        if type(v) == "number" and v > 0 then keys[#keys + 1] = k end
    end
    if #keys == 0 then return "" end
    table.sort(keys)
    local out = {}
    for i = 1, #keys do
        if i > 8 then out[#out + 1] = "…" break end
        out[#out + 1] = keys[i] .. " " .. tostring(d.c[keys[i]])
    end
    return "（" .. table.concat(out, " / ") .. "）"
end

local function domain_line(d)
    return string.format("域 %s：句柄%s 钩子%s 调用 %d 命中 %d 错误 %d%s",
        tostring(d.name), domain_label(d.fields), domain_label(d.hooks),
        d.calls, d.hits, d.errs, counter_summary(d))
end

-- 进世界后一次性播报（聊天栏 + 日志各一份）
function self_check_report()
    local n = #DOMAINS
    local head = string.format("[世界工坊] 启动自检：域 %d 个 / 钩子 %d/%d 个 / 设置 %d 项",
        n, stats.hooks_ok, stats.hooks_try, P.count or 0)
    chat_print(head)
    local maxl = 12
    for i = 1, n do
        if i > maxl then break end
        chat_print("[世界工坊] " .. domain_line(DOMAINS[i]))
    end
    if n > maxl then
        chat_print(string.format("[世界工坊] 其余 %d 个域见 /forge stat 或日志文件", n - maxl))
    end
    diag(head)
    for i = 1, n do diag("  " .. domain_line(DOMAINS[i])) end
    diag_flush()
end

-- /forge stat：完整诊断（逐域一行；每域平均耗时超阈值标 SLOW）
function report_stats()
    chat_print(string.format(
        "[世界工坊] 诊断：域 %d / 钩子 %d/%d / 字段 %d 缺 %d / 方法 %d 缺 %d / 设置 %d 项"
        .. " / 帧 %d / 帧写 %d / 客机挡下 %d / 聊天命令 %d",
        #DOMAINS, stats.hooks_ok, stats.hooks_try,
        stats.fields_ok, stats.fields_miss, stats.methods_ok, stats.methods_miss,
        P.count or 0, stats.frames, stats.writes, stats.netmode_blocked, stats.chat_cmds))
    local lim = tonumber(cfg.diag_slow_ms) or 50
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        local avg = (d.n > 0) and (d.t / d.n * 1000) or 0
        local slow = (avg > lim and d.n > 0) and " SLOW" or ""
        chat_print(string.format("[世界工坊] %s 平均 %.3fms%s%s",
            domain_line(d), avg, slow, d.last_err and (" 最近错误：" .. tostring(d.last_err)) or ""))
    end
    -- ★ v5.0.0：聊天与导入通道的现状（chat_cmd 关时也照实说明「零触达」）
    if cfg.chat_cmd then
        chat_print(string.format(
            "[世界工坊] 聊天命令：开启 ｜ Chat 类型解析 %d 次 ｜ 命令 %d 条 ｜ 导入成功 %d / 失败 %d",
            stats.chat_types, stats.chat_cmds, stats.import_ok, stats.import_fail))
    else
        chat_print(string.format(
            "[世界工坊] 聊天命令：默认关闭（类型解析 %d 次，本机配置）｜ 导入成功 %d / 失败 %d"
            .. " ｜ 串请粘贴到「导入设置串」设置项",
            stats.chat_types, stats.import_ok, stats.import_fail))
    end
    diag("[世界工坊] /forge stat 已输出逐域诊断")
    diag_flush()
end

function report(prefix)
    local msg = string.format(
        "%s -> 世界 %s / 事件与月亮事件 %s / 刷怪分类 %s / 刷怪质量 %s / 生物属性 %s"
        .. " / 住房 %s / 晶塔 %s / 蔓延 %s(速率×%.2f) / 困难模式 %s"
        .. " | 树木 %s / 渔夫 %s / 稀有 %s / 复活与复活时间 %s / 制作站 %s / 世界生成 %s"
        .. " / 微光与产物数量 %s / 坠落之星 %s / 雷击 %s / 液体 %s / 世界边缘与重力 %s"
        .. " / 商店售价 %s / 地图生成专项 %s ｜ 房主总闸 %s（间隔 %d 帧）（设置 %d 项，钩子 %d/%d 个）",
        prefix, fmt_bool(P.world.active), fmt_bool(P.events and P.events.active),
        fmt_bool(P.spawn.filter), fmt_bool(P.spawnq and P.spawnq.active), fmt_bool(P.attr.active),
        fmt_bool(P.house.active), fmt_bool(P.pylon.active), fmt_bool(P.world.spread_block
            or P.world.spread_force or ((P.world.spread_mult or 100) ~= 100)),
        (P.world.spread_mult or 100) / 100, fmt_bool(P.world.hardmode),
        fmt_bool(P.tree.active), fmt_bool(P.angler.active),
        fmt_bool(P.rare.active), fmt_bool(P.death.active), fmt_bool(P.station.active),
        fmt_bool(P.gen.active), fmt_bool(P.shimmer.active), fmt_bool(P.starfall.active),
        fmt_bool(P.lightning.active), fmt_bool(P.liquid and P.liquid.on),
        fmt_bool(P.misc and P.misc.active), fmt_bool(P.shop and P.shop.active),
        fmt_bool(P.wgen and P.wgen.active),
        fmt_bool(P.host_only), P.tick or 1,
        P.count or 0, stats.hooks_ok, stats.hooks_try)
    if cfg.write_log then mod.info(msg) end
    diag(msg)
    if cfg.verbose_log and cfg.write_log then
        diag(string.format("时间：流速 %.2f 冻结=%s 锁定=%s(%s) 月相=%d",
            P.world.time_speed, tostring(P.world.freeze), tostring(P.world.lock_ticks ~= nil),
            tostring(P.world.lock_day), P.world.moon_lock))
        diag(string.format("刷怪参数：速度 ×%.2f 上限 ×%.2f 禁刷=%s",
            P.world.spawn_rate_mult / 100, P.world.spawn_cap_mult / 100,
            tostring(P.world.no_natural_spawn)))
    end
    diag_flush()
end

-- 探测加载器是否具备「1.6.1 才补齐」的那几项反射元数据能力，缺了只影响降级路径
local function probe_capabilities()
    local miss = {}
    local pf = F.dayRate or F.dayTime or F.raining or F.defaultSpawnRate
    if patch.field_is_static then
        if pf and not pcall(patch.field_is_static, pf) then miss[#miss + 1] = "field_is_static" end
    else
        miss[#miss + 1] = "field_is_static"
    end
    if patch.method_param_count then
        if M.update_time_rate and not pcall(patch.method_param_count, M.update_time_rate) then
            miss[#miss + 1] = "method_param_count"
        end
    else
        miss[#miss + 1] = "method_param_count"
    end
    if patch.get_inner_types and patch.get_full_name then
        local T_CP = get_type("Terraria.GameContent.Creative", "CreativePowers")
        if T_CP then
            local okp, list = pcall(patch.get_inner_types, T_CP)
            if not okp or type(list) ~= "table" then miss[#miss + 1] = "get_inner_types" end
        end
    else
        miss[#miss + 1] = "get_inner_types"
    end
    if #miss > 0 then
        mod.warn("当前加载器缺少这些能力：" .. table.concat(miss, " / ")
            .. "（相关功能自动降级，其余功能照常工作）")
    end
end

local function run_domain_phase(phase, label)
    local n = 0
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        local fn = d.phase and d.phase[phase]
        if fn then
            local f0, fm0 = stats.fields_ok, stats.fields_miss
            local m0, mm0 = stats.methods_ok, stats.methods_miss
            local h0, ht0 = stats.hooks_ok, stats.hooks_try
            local ok, err = pcall(fn, T)
            -- ★ v5：按「阶段前后差值」自动算出每域的句柄/钩子状态，各分片无需自己声明清单
            if phase == "fields" then
                d.n_fields_ok, d.n_fields_miss = stats.fields_ok - f0, stats.fields_miss - fm0
            elseif phase == "methods" then
                d.n_methods_ok, d.n_methods_miss = stats.methods_ok - m0, stats.methods_miss - mm0
            elseif phase == "install" then
                d.n_hooks_ok, d.n_hooks_try = stats.hooks_ok - h0, stats.hooks_try - ht0
            end
            if not ok then
                d.errs = d.errs + 1
                d.last_err = tostring(err)
                mod.warn("功能域「" .. tostring(d.name) .. "」" .. label .. "失败：" .. tostring(err))
            else
                n = n + 1
            end
        end
    end
    return n
end

function setup()
    in_setup = true                 -- ★ 重新 setup（热重载）时也要恢复「加载期允许打日志」
    mod.info("世界工坊 v" .. tostring(mod.meta.version) .. " 阶段 1/5：解析类型")
    T.MAIN = get_type("Terraria", "Main")
    T.NPC = get_type("Terraria", "NPC")
    T.WORLDGEN = get_type("Terraria", "WorldGen")
    T.PLAYER = get_type("Terraria", "Player")
    T.SAND = get_type("Terraria.GameContent.Events", "Sandstorm")
    T.LANTERN = get_type("Terraria.GameContent.Events", "LanternNight")
    T.PARTY = get_type("Terraria.GameContent.Events", "BirthdayParty")
    T.PYLON = get_type("Terraria.GameContent", "TeleportPylonsSystem")
    T.TOWNROOM = get_type("Terraria.GameContent", "TownRoomManager")
    T.STAR = get_type("Terraria", "Star")
    T.WORLDITEM = get_type("Terraria", "WorldItem")
    -- ★ v9：落雷弹幕（Projectile 1091）的 ai / active / type。数落雷上限、改雷击时长都要它。
    T.PROJECTILE = get_type("Terraria", "Projectile")
    -- v5 新增：商店售价（Item）。
    -- ★ 聊天相关类型**不在这里解析**（§9 整改）：聊天文本入口由 95_chat 在 chat_cmd=true 时才取。
    T.ITEM = get_type("Terraria", "Item")
    -- ★★ v5.0.0（§9 整改）：这里完全不再碰 Terraria.Chat。
    --   旧的 T.CHATCMD / T.CHATHELPER / T.CHATMSG 三个 get_type 已删除：最后那一个
    --   （聊天消息类型）就是实机 SIGABRT 那一行（见 05-写法与陷阱.md §5.2），前两个也不再
    --   需要 —— 聊天文本唯一入口是
    --   Terraria.Chat.Commands.SayChatCommand.ProcessIncomingMessage(string, byte)，
    --   由聊天功能域在 `chat_cmd == true` 时才解析（95_chat.lua）。
    --   `chat_cmd` 默认 false ⇒ 默认路径上一次 Chat 类型解析都不发（stats.chat_types 恒 0）。
    if not T.MAIN then
        mod.error("找不到 Terraria.Main，世界工坊未启用")
        return
    end
    diag("阶段1 类型：main=" .. tostring(T.MAIN ~= nil) .. " npc=" .. tostring(T.NPC ~= nil)
        .. " worldgen=" .. tostring(T.WORLDGEN ~= nil) .. " player=" .. tostring(T.PLAYER ~= nil)
        .. " pylon=" .. tostring(T.PYLON ~= nil))
    diag_flush()

    -- ★★★ v5.0.0（§9.4 验收硬指标）：聊天功能**默认关闭**。
    --   TEFManager 的完整设置要到第 5 阶段才读，所以这里先只预读「聊天指令」这一个键：
    --   它决定「方法解析 / 钩子安装」两个阶段要不要解析 SayChatCommand / 装聊天钩子。
    --   ★ **必须放在阶段 3（方法解析）之前**：95_chat 的聊天功能域是在 methods 阶段
    --     里做门控的，预读放在 install 之前就晚了（methods 已经跑完，gate 读到默认 false）。
    --   预读只做正则取一个 bool（不装钩子、不读游戏内存），安全；第 5 阶段仍会完整重读一次。
    local ok_cc, tcc = pcall(read_config)
    if not ok_cc then mod.warn("预读 config.json 失败（chat_cmd 按默认关闭处理）：" .. tostring(tcc)) end
    if cfg.chat_cmd then
        mod.info("聊天指令：已开启（chat_cmd = true）→ 解析 SayChatCommand 并安装聊天入口钩子")
    else
        stats.chat_disabled = 1
        mod.info("聊天指令：默认关闭（chat_cmd = false）→ 不解析任何 Terraria.Chat 类型、不装聊天钩子；"
            .. "导出仍写 forge_export.txt，导入请用「导入设置串」设置项")
    end
    mod.info("世界工坊 阶段 2/5：注册字段（只查元数据，不读值）")
    run_domain_phase("fields", "字段注册")
    mod.info("字段注册完成：" .. stats.fields_ok .. " 个可用，" .. stats.fields_miss .. " 个缺失")
    if not F.dayRate and not F.defaultSpawnRate and not F.Happening then
        mod.error("关键字段全部缺失（符号表与本机不匹配），世界工坊未启用")
        return
    end

    mod.info("世界工坊 阶段 3/5：解析方法")
    run_domain_phase("methods", "方法解析")
    M.reset_effects = T.PLAYER and find_method(T.PLAYER, "ResetEffects", 0)
    -- 手机版 gameMenu / myPlayer 是属性，字段取不到 -> 必须留方法兜底（05 §4.6）
    M.get_game_menu = T.MAIN and find_method(T.MAIN, "get_gameMenu", 0)
    M.get_my_player = T.MAIN and find_method(T.MAIN, "get_myPlayer", 0)
    diag("阶段3 方法：timeRate=" .. tostring(M.update_time_rate ~= nil)
        .. " setDefaults=" .. tostring(M.set_defaults ~= nil)
        .. " spawnNpc=" .. tostring(M.spawn_npc ~= nil)
        .. " newNpc=" .. tostring(M.new_npc ~= nil)
        .. " updateWorld=" .. tostring(M.update_world ~= nil)
        .. " toggle=" .. tostring(M.get_enabled ~= nil)
        .. " pylon=" .. tostring(M.pylon_npc ~= nil)
        .. " pylonAccept=" .. tostring(M.pylon_accept ~= nil)
        .. " pylonNear=" .. tostring(M.player_near_pylon ~= nil)
        .. " killMe=" .. tostring(M.kill_me ~= nil)
        .. " spawnOnPlayer=" .. tostring(M.spawn_on_player ~= nil)
        .. " hasPylon=" .. tostring(M.has_pylon_of_type ~= nil)
        .. " anyDanger=" .. tostring(M.any_danger ~= nil)
        .. " shimmerSpawn=" .. tostring(M.shimmer_spawn ~= nil)
        .. " canLive=" .. tostring(M.can_live_together ~= nil)
        .. " anglerDone=" .. tostring(M.angler_done ~= nil)
        .. " newLightning=" .. tostring(M.new_lightning ~= nil)
        .. " rarityField=" .. tostring(F.rarity ~= nil))
    probe_capabilities()

    mod.info("世界工坊 阶段 4/5：安装钩子（" .. #DOMAINS .. " 个功能域）")
    run_domain_phase("install", "钩子安装")
    -- 心跳钩子单独装：它不属于任何功能域，但「窗口标志安全网 + 设置热重载」都靠它
    safe_hook(M.reset_effects, { postfix = on_reset_effects }, "Player.ResetEffects（心跳）")

    mod.info("世界工坊 阶段 5/5：读取设置并生成计划")
    local ok_cfg, err_cfg = pcall(read_config)
    if not ok_cfg then mod.warn("读取 config.json 失败（改用默认值）：" .. tostring(err_cfg)) end
    build_plans()
    run_domain_phase("reload", "设置重应用")
    -- ★ v5.0.0：如果玩家在启动前就把串留在「导入设置串」里，这里补一次检测
    --   （tick 里也有一条；本函数里跑一次是为了「改完设置重启游戏」这条路径也不漏）
    pcall(poll_import_string)
    last_cfg_check = os.time() or 0
    if type(math.randomseed) == "function" then
        local ok_t, t = pcall(os.time)
        pcall(math.randomseed, (ok_t and type(t) == "number") and t or 20261009)
    end

    eval_domain_labels()
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        diag(string.format("  域 %s：字段 %s(%d/%d) 方法 %s(%d/%d) 钩子 %s(%d/%d)",
            tostring(d.name), tostring(d.fields), d.n_fields_ok, d.n_fields_ok + d.n_fields_miss,
            tostring(d.methods), d.n_methods_ok, d.n_methods_ok + d.n_methods_miss,
            tostring(d.hooks), d.n_hooks_ok, d.n_hooks_try))
    end
    ready = true
    in_setup = false               -- 之后一律由 cfg.write_log 决定要不要写日志
    diag("阶段5 完成：钩子 " .. #hooks .. " 个，设置项 " .. (P.count or 0) .. " 项")
    diag_flush()
    report("世界工坊已启用")
    if not P.any then
        mod.info("当前全部为原版默认值：本模组每帧只做一次自检，不产生任何写入")
    end
end

function cleanup()
    ready = false
    pcall(restore_world)
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
    F, ST, FT = {}, {}, {}
    type_cat, type_base = {}, {}
    -- v3：各功能域自己登记的「世界缓存」也要清（否则重新 setup 后会沿用旧阈值学出来的标记）
    for i = 1, #DOMAINS do
        local fn = DOMAINS[i].phase and DOMAINS[i].phase.reset
        if fn then pcall(fn) end
    end
    UNDO = {}
    fl.world_update, fl.pylon_request, fl.score_room = false, false, 0
    fl.spawn_dead, fl.artisan_saved, fl.artisan_touched = false, nil, false
    spawn_win.natural, spawn_win.budget, spawn_win.in_dup = false, 0, false
    mem.meteor_done, mem.bulb_done, mem.bulb_next, mem.merchant_day = false, false, nil, nil
    mem.self_check_at, mem.chat_tip_at, mem.export_at, mem.imp = nil, nil, nil, nil
    fl.boss_summon = false
    tick_i = 0
    world_entered, menu_flag = false, true
    mod.info("世界工坊已卸载（钩子已摘除，改过的全局值已还原）")
end

mod.cleanup = cleanup
todo_list = { "setup" }


-- ★★ 分片作用域包裹（v5）：本分片的所有 local 都关在下面这个 do…end 里，
--   不进主 chunk 的 200 个顶层 local 名额（Lua 5.4 主 chunk 也是一个函数）。
--   本分片不向其它分片导出任何 local；对外只通过功能域表 / 全局函数 / P 表交互。
do
  -- ============================================================================
  -- 95 · 聊天命令 / 设置串导入导出 / 启动自检（v5 新增）
  -- ----------------------------------------------------------------------------
  -- 契约：《开发文档/12-下一版通用约定.md》§2（命令表）、§3（设置串格式与分片）、§4（诊断）。
  --
  -- ★★ v5.0.0（《12-下一版通用约定》§9）：**聊天功能整体默认关闭**（设置项 chat_cmd）。
  -- ----------------------------------------------------------------------------
  -- 事实（本工作区唯一的真机证据，开发文档/05-写法与陷阱.md §5.2）：
  --   ProjectileForge v1.0.0 连续 3 次 SIGABRT，内核日志停在
  --   「Found type: Terraria.Chat.<那个聊天消息类型>」→ 反射它的成员（文本 getter /
  --   自动属性背后的字段）会让 libil2cpp 的 C++ 异常穿出 native 帧 → abort()，
  --   **Lua 侧 pcall 拦不住**。而「装聊天钩子」本身是被证明安全的。
  --   ⇒ 本文件（以及整个 main.lua）**任何地方都不许出现那个类型名的字面量**：
  --     验收硬指标是 `grep -c 那个类型名 main.lua == 0`，tests/test.lua 里有对应静态断言。
  --     详见《12-下一版通用约定》§9.1/§9.4 与本文件不再重复写出该名字。
  --
  -- 拦截入口（只在 cfg.chat_cmd == true 时安装，单一入口）：
  --   Terraria.Chat.Commands.SayChatCommand.ProcessIncomingMessage(string text, byte clientId)
  --     2 参实例方法（符号表：Terraria.Chat.Commands.SayChatCommand · 2 · string, byte）。
  --     ★ 它是 ChatInitializer.cs:29 注册的 _defaultCommand：PC 侧
  --       Terraria.Chat/ChatCommandProcessor.cs 的 ProcessIncomingMessage 里，
  --       _commands 查不到时走 `else if (_defaultCommand != null)` 分支 →
  --       **普通聊天与任何未知「/命令」的原文都原样送到这里**（纯 string + byte 两标量，
  --       没有任何聊天消息对象参与），是本模组唯一允许的聊天文本入口。
  --   · 用 **prefix** 回调（本加载器 prefix 返回 true = 跳过原方法，见 03-LuaAPI.md §4.6）；
  --     命中本模组命令时返回 true → 顺手阻止该设置串被原版当普通聊天广播出去。
  --   · 只处理本机玩家：args[2]（clientId）必须 == Main.myPlayer；不相等一律返回 false，
  --     原逻辑照走（非本模组的文本一律不动）。
  --
  -- 输出：Main.NewText(string, byte, byte, byte, bool)（手机版 **5 参**；桌面端的 4 参重载
  --   在手机版不存在，3 参那个要 Color 结构体、更挂不得）。取不到就只写日志，绝不静默。
  --
  -- 设置串格式：forge:<slug>|<k>=<v>;<k>=<v>|#<sum>
  --   · 4 种类型统一用 JSON 风格字面量；`%` `;` `|` `=` `"` 用 %XX 转义。
  --   · <sum> = 整个「forge:<slug>|<body>」的字节和 % 65521，十六进制小写。
  --   · 默认只导出与默认值不同的项；`/forge export all` 导出全量。
  --   · 超过 320 字符自动分片成 `[i/n] <片>` 逐行打印；import 侧按 i 暂存、齐了才校验应用。
  --   · 应用 = **就地改写 config.json 文本**（只替换该 key 的字面量，未知 key 与
  --     schemaVersion 原样保留），然后立刻重算 cfg + 重跑各域 reload + 播报。
  -- ============================================================================

  local SLUG = "worldforge"
  local CMD = "forge"
  local SHARD = 320          -- 每片正文上限（约定 §3.2）

  -- ★ 前向声明：handle_text 会写 CT.hits（诊断计数），而 CT 的 domain{} 定义在本文件末尾。
  --   Lua 的词法作用域是「按位置」的：如果这里不先声明，handle_text 里的 CT 会退化成
  --   **全局变量**（读到 nil）→ "attempt to index a nil value (global 'CT')"。
  --   （这个坑真实存在过一次：整改时删掉了前向声明，测试立刻在 /forge help 上炸了。）
  local CT

  -- ---------------------------------------------------------------- 输出
  local reported_api_fail = false
  local reported_str_fail = false

  -- ★★ v6.0.1 崩溃修复：形参是 string 的 invoke **必须**先构造托管字符串句柄。
  --   机理（对着 1.6.3 的 LuaLoader 源码逐行核过）：
  --     · 内核把 IL2CPP_TYPE_STRING 映射成 PATCH_OBJECT（field.c:82）；
  --     · LuaLoader 的 read_patch_value() 对 PATCH_OBJECT 只调 to_handle()，
  --       而 to_handle() 只认 lightuserdata/托管句柄 —— **Lua 字符串一律得到 NULL**
  --       （lua_api.cpp:162-205；`array_set`/字段写入是另一条路，那条会自动 string_create，
  --        所以「字段能写字符串」不代表「invoke 能传字符串」）。
  --   后果：Main.NewText 收到 null → ChatManager.ParseMessage(null) 里 `text.Replace(...)`
  --     → NullReferenceException → 托管异常从 native 帧穿出 → abort() → **SIGABRT**。
  --     pcall 拦不住（崩在 C/托管边界），而本模组**进世界后默认就会播报自检**
  --     → 每次进世界必崩。实机日志（TEFKernel SIGABRT + __cxa_get_exception_ptr）即此。
  local function to_managed_string(text)
      if not patch.string_create then return nil end
      local ok, h = pcall(patch.string_create, text)
      if ok and h then return h end
      return nil
  end

  function chat_print(text)
      text = tostring(text)
      if M.new_text and patch.string_create then
          local s = to_managed_string(text)
          if s then
              local ok = invoke_checked(M.new_text, 5, s, 255, 255, 255, true)
              if ok then return true end
          elseif not reported_str_fail then
              reported_str_fail = true
              mod.warn("patch.string_create 不可用：聊天输出改为只写日志"
                  .. "（绝不裸传 Lua 字符串 —— 那在真机上是 NULL → 进程崩溃）")
          end
      elseif M.new_text and not reported_api_fail then
          reported_api_fail = true
          mod.warn("Main.NewText(string,byte,byte,byte,bool) 不可用：聊天输出改为只写日志")
      end
      mod.info("[世界工坊] " .. text)
      return false
  end

  -- ---------------------------------------------------------------- 设置串
  local function esc_val(s)
      s = tostring(s)
      s = s:gsub("%%", "%%25")            -- ★ 百分号必须先转，否则会和后面的转义打架
      s = s:gsub('"', "%%22")
      s = s:gsub(";", "%%3B")
      s = s:gsub("|", "%%7C")
      s = s:gsub("=", "%%3D")
      return s
  end

  local function unesc_val(s)
      return (tostring(s):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
  end

  local function checksum(s)
      local sum = 0
      for i = 1, #s do sum = (sum + s:byte(i)) % 65521 end
      return string.format("%x", sum)
  end

  local function sorted_keys()
      local ks = {}
      for k in pairs(DEFAULTS) do ks[#ks + 1] = k end
      table.sort(ks)
      return ks
  end

  local function lit_of(key)
      local v = cfg[key]
      local d = DEFAULTS[key]
      if v == nil then v = d end
      if type(d) == "boolean" then return v and "true" or "false" end
      if type(d) == "number" then return tostring(math.floor(tonumber(v) or d)) end
      return '"' .. esc_val(v) .. '"'
  end

  local function build_settings_string(all)
      local parts = {}
      local ks = sorted_keys()
      for i = 1, #ks do
          local k = ks[i]
          if all or cfg[k] ~= DEFAULTS[k] then
              parts[#parts + 1] = k .. "=" .. lit_of(k)
          end
      end
      local head = "forge:" .. SLUG .. "|"
      local body = table.concat(parts, ";")
      return head .. body .. "|#" .. checksum(head .. body), #parts
  end

  local function chat_shards(s)
      local n = math.ceil(#s / SHARD)
      if n <= 1 then
          chat_print(s)
          return
      end
      for i = 1, n do
          chat_print(string.format("[%d/%d] %s", i, n, s:sub((i - 1) * SHARD + 1, i * SHARD)))
      end
  end

  -- 解析设置串 → items（{key, value} 列表）。返回 items, 未知项数, 错误串
  local function parse_settings_string(raw)
      local head, slug, body = tostring(raw):match("^(forge:)([%w_%-]+)|(.*)$")
      if not head then return nil, 0, "格式不对（应以 forge:worldforge| 开头）" end
      if slug ~= SLUG then
          return nil, 0, "这是 " .. tostring(slug) .. " 的设置串，不是世界工坊的"
      end
      local payload, sum = body:match("^(.*)|#(%x+)$")
      if not payload then return nil, 0, "缺少校验和（串尾应有 |#xxxx）" end
      if checksum("forge:" .. SLUG .. "|" .. payload) ~= sum:lower() then
          return nil, 0, "校验和不符（串可能被截断或被改过）"
      end
      local out, bad = {}, 0
      for seg in payload:gmatch("[^;]+") do
          local k, v = seg:match("^([%w_]+)=(.*)$")
          local d = k and DEFAULTS[k]
          if k and v and d ~= nil then
              if type(d) == "boolean" then
                  if v == "true" then
                      out[#out + 1] = { k, true }
                  elseif v == "false" then
                      out[#out + 1] = { k, false }
                  else
                      bad = bad + 1
                  end
              elseif type(d) == "number" then
                  local n = tonumber(v)
                  if n then out[#out + 1] = { k, n } else bad = bad + 1 end
              else
                  local sv = v:match('^"(.*)"$')
                  if sv == nil then sv = v end
                  out[#out + 1] = { k, unesc_val(sv) }
              end
          else
              bad = bad + 1
          end
      end
      return out, bad
  end

  local function known_kind(key)
      local d = DEFAULTS[key]
      if type(d) == "boolean" then return "bool" end
      if type(d) == "number" then return "int" end
      if CHOICES[key] then return "choice" end
      return "str"
  end

  local function json_lit(key, val)
      local d = DEFAULTS[key]
      if type(d) == "boolean" then return val and "true" or "false" end
      if type(d) == "number" then return tostring(math.floor(tonumber(val) or d)) end
      local s = tostring(val):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
      return '"' .. s .. '"'
  end

  -- 就地改写 config.json 文本。返回 ok, err, changed, added, ignored
  local function apply_items(items)
      local raw = mod.read_file("config.json")
      if type(raw) ~= "string" or raw == "" then
          raw = '{"schemaVersion":1,"values":{}}'
      end
      local changed, added, ignored = 0, 0, 0
      for i = 1, #items do
          local k, v = items[i][1], items[i][2]
          local kind = known_kind(k)
          local okv = true
          if kind == "int" then
              v = math.floor(tonumber(v) or DEFAULTS[k])
              local lim = LIMITS[k]
              if lim then
                  if v < lim[1] then v = lim[1] end
                  if v > lim[2] then v = lim[2] end
              end
          elseif kind == "choice" then
              local allowed = CHOICES[k]
              local hit = false
              for j = 1, #allowed do
                  if allowed[j] == v then hit = true break end
              end
              if not hit then okv = false end
          elseif kind == "bool" then
              v = (v == true)
          end
          if not okv then
              ignored = ignored + 1
          else
              local lit = json_lit(k, v)
              -- ★ esc() 是给 **Lua 模式** 转义用的（_ 会变成 %_），只能出现在 pattern 里；
              --   写回文件的字面量必须用原始 key，否则会写出 "time%_speed" 这种坏键。
              local kq = '"' .. k .. '"'
              local kp = '"' .. esc(k) .. '"'
              local pat
              if kind == "int" then pat = kp .. "%s*:%s*%-?%d+"
              elseif kind == "bool" then pat = kp .. "%s*:%s*%a+"
              else pat = kp .. '%s*:%s*"[^"]*"' end
              local found = false
              local nraw = raw:gsub(pat, function()
                  found = true
                  return kq .. ":" .. lit
              end, 1)
              if found then
                  raw = nraw
                  changed = changed + 1
              else
                  -- 文件里没有这个 key（手改过 config.json / TEFManager 省略了默认项）：塞进 values
                  local n2
                  if raw:find('"values"%s*:%s*{}') then
                      raw, n2 = raw:gsub('("values"%s*:%s*){}',
                          function(a) return a .. "{" .. kq .. ":" .. lit .. "}" end, 1)
                  else
                      raw, n2 = raw:gsub('("values"%s*:%s*{)',
                          function(a) return a .. kq .. ":" .. lit .. "," end, 1)
                  end
                  if n2 and n2 > 0 then added = added + 1 else ignored = ignored + 1 end
              end
          end
      end
      if changed + added == 0 then
          return false, "没有任何一项被写进 config.json（忽略 " .. ignored .. " 项）", 0, 0, ignored
      end
      if added > 0 then
          -- 我们插入时统一带了尾逗号，这里把「,}」收拾成「}」（原文件是机器生成的合法 JSON，不会有别的 ,}）
          raw = raw:gsub(",%s*}", "}")
      end
      if not mod.write_file("config.json", raw) then
          return false, "写入 config.json 失败", 0, 0, ignored
      end
      -- 立刻在内存里重算并重跑各域 reload（走已有的 load_config → build_plans → domain.reload）
      local okc, errc = pcall(read_config)
      if not okc then
          return false, "重读 config.json 失败：" .. tostring(errc), changed, added, ignored
      end
      pcall(build_plans)
      for i = 1, #DOMAINS do
          local fn = DOMAINS[i].phase and DOMAINS[i].phase.reload
          if fn then pcall(fn) end
      end
      pcall(report, "导入设置")
      return true, nil, changed, added, ignored
  end  -- ---------------------------------------------------------------- 命令
  local function cmd_help()
      chat_print("[世界工坊] 命令表（大小写不敏感，前导 / 可省）：")
      chat_print("[世界工坊]   /forge help            本命令表")
      chat_print("[世界工坊]   /forge stat            逐域诊断：句柄/钩子/调用/命中/错误/平均耗时")
      chat_print("[世界工坊]   /forge check           重跑一次启动自检并播报")
      chat_print("[世界工坊]   /forge export          导出「与默认值不同」的设置串")
      chat_print("[世界工坊]   /forge export all      导出全部设置")
      chat_print("[世界工坊]   /forge import <串>     导入设置串（长串会被自动分片，逐片发完）")
      chat_print("[世界工坊]   /forge import reset    放弃已缓存的分片")
      chat_print("[世界工坊]   /forge one             一键操作：列出全部编号（v9）")
      chat_print("[世界工坊]   /forge one <编号>      执行一次一键操作（例：/forge one e_blood）")
      chat_print("[世界工坊]   /forge wgen            地图生成专项：当前进度")
      chat_print("[世界工坊]   /forge wgen stop       取消正在进行的生成后追加 / 清除任务")
      chat_print("[世界工坊] ★ 聊天指令默认关闭：先在 TEFManager 设置里打开「聊天指令」才认这些命令。")
      chat_print("[世界工坊] ★ 没开时请用「导入设置串」设置项：把串粘贴进去即可（导出仍照常写文件+播报）。")
  end

  -- ★ v5.0.0（§9.3）：默认（零聊天依赖）的导出通道。
  --   聊天关着也要能导出：把串落盘 + 用一次 Main.NewText 播报。
  --   ★ 单机与客机都可用；不依赖聊天系统，也不依赖任何 Chat 类型。
  function export_channel(origin)
      local str, n = build_settings_string(false)
      if n == 0 then
          chat_print("[世界工坊] 没有与默认值不同的设置项（用 /forge export all 可导出全量）")
          return false, "没有非默认项"
      end
      local okw = mod.write_file("forge_export.txt", str)
      if okw then
          chat_print(string.format(
              "[世界工坊] 已导出 %d 项（%d 字符）→ 模组私有目录 forge_export.txt；"
              .. "客机请把这段串复制粘贴到「导入设置串」设置项里。", n, #str))
      else
          chat_print("[世界工坊] 导出失败：写 forge_export.txt 没成功（请检查存储权限）")
      end
      -- 整串原样再播一行，方便在游戏内直接长按复制
      chat_shards(str)
      diag(string.format("导出通道（%s）：%d 项 / %d 字符 / 落盘 %s",
          tostring(origin), n, #str, tostring(okw)))
      diag_flush()
      return okw, str, n
  end

  local function cmd_export(all)
      if not all then
          -- 默认走零聊天依赖的落盘通道；`export all` 仍按老路子逐片打到聊天栏
          return export_channel("/forge export")
      end
      local str, n = build_settings_string(true)
      if n == 0 then
          chat_print("[世界工坊] 没有任何可导出的设置项")
          return
      end
      chat_print(string.format("[世界工坊] 设置串（全量）：%d 项 / %d 字符（可整段复制给另一台设备导入）", n, #str))
      chat_shards(str)
  end

  local function cmd_import(arg)
      arg = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if arg == "" then
          chat_print("[世界工坊] 用法：/forge import <设置串>（用 /forge export 生成）或 /forge import reset")
          return
      end
      if arg:lower() == "reset" then
          mem.imp = nil
          chat_print("[世界工坊] 已放弃已缓存的导入分片")
          return
      end
      local i, n, chunk = arg:match("^%[(%d+)/(%d+)%]%s*(.*)$")
      if i then
          i, n = tonumber(i), tonumber(n)
          if not (i >= 1 and n >= 1 and i <= n) then
              chat_print("[世界工坊] 分片序号不对，整段重发一次吧")
              return
          end
          local cache = mem.imp
          if not cache or cache.n ~= n then
              cache = { n = n, got = {}, cnt = 0 }
              mem.imp = cache
          end
          if not cache.got[i] then cache.cnt = cache.cnt + 1 end
          cache.got[i] = chunk
          if cache.cnt < n then
              chat_print(string.format("[世界工坊] 已收到第 %d/%d 片，还差 %d 片", i, n, n - cache.cnt))
              return
          end
          local buf = {}
          for j = 1, n do
              if not cache.got[j] then
                  chat_print(string.format("[世界工坊] 缺第 %d 片，请把 export 的输出整段发完", j))
                  return
              end
              buf[#buf + 1] = cache.got[j]
          end
          mem.imp = nil
          arg = table.concat(buf)
      end
      local ok, msg = import_channel(arg, "/forge import")
      if not ok then
          chat_print("[世界工坊] 导入失败：" .. tostring(msg))
      end
  end

  -- ---------------------------------------------------------------- ★ 默认导入通道（零聊天依赖）
  -- 语义（约定 §9.3）：玩家把串**粘贴**进 TEFManager 的「导入设置串」设置项即可。
  --   本函数由 read_config 之后的「检测到 import_string 非空」触发，单机与客机都可用；
  --   客户端上 TEFManager 的配置文件在**本机**，所以客机也能改自己的设置 → 不依赖聊天。
  -- 返回 true, 播报串 / false, 错误原因。
  function import_channel(raw, origin)
      raw = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if raw == "" then return false, "串是空的" end
      local items, bad, err = parse_settings_string(raw)
      if not items then
          stats.import_fail = stats.import_fail + 1
          chat_print("[世界工坊] 导入设置串失败：" .. tostring(err))
          diag("导入通道（" .. tostring(origin) .. "）失败：" .. tostring(err))
          diag_flush()
          return false, err
      end
      -- ★ 递归保护：apply_items 内部要 read_config / build_plans / report，
      --   期间任何再次触发本函数的路径都必须被挡住（否则长串会反复重放）。
      if fl.importing then return false, "正在导入中" end
      fl.importing = true
      local ok, werr, changed, added, ignored = apply_items(items)
      fl.importing = false
      if not ok then
          stats.import_fail = stats.import_fail + 1
          chat_print("[世界工坊] 导入设置串失败：" .. tostring(werr))
          diag("导入通道（" .. tostring(origin) .. "）失败：" .. tostring(werr))
          diag_flush()
          return false, werr
      end
      stats.import_ok = stats.import_ok + 1
      local tip = (origin == "import_string")
          and "（请把「导入设置串」这一项清空，否则改别的设置时会再执行一次）" or ""
      chat_print(string.format(
          "[世界工坊] 已导入 %d 项（改写 %d / 新增 %d / 忽略 %d / 串里不认识 %d）%s",
          changed + added, changed, added, ignored, bad, tip))
      diag(string.format("导入通道（%s）：改写 %d / 新增 %d / 忽略 %d / 不认识 %d",
          tostring(origin), changed, added, ignored, bad))
      diag_flush()
      return true, changed + added
  end

  -- 设置重读之后调用（90_lifecycle 的 tick）：只要 import_string 与本模组上次处理过的不一样
  -- 且非空，就走一次导入。★ 结果必须回写「空串」，否则下次改任何别的设置 → 文件变化 →
  -- 重读 → 又看到同一个非空串 → 无限重复导入（老串把新设置顶掉）。
  function poll_import_string()
      local raw = cfg.import_string
      if type(raw) ~= "string" then raw = "" end
      if raw == "" then
          if mem.last_import ~= "" then mem.last_import = "" end
          return false
      end
      if raw == mem.last_import then return false end
      mem.last_import = raw
      local ok = import_channel(raw, "import_string")
      clear_import_string()
      return ok
  end

  -- ★ v5.0.0：进世界后一次性提示「聊天指令默认关闭 + 怎么导入导出」。
  --   独立于 self_check（自检可以关，这条提示只发一次、只有一行），
  --   由 mem.chat_tip_at 门控 —— 不刷屏，且关掉 self_check 时也不会莫名多出一行。
  function chat_tip_report()
      local okw = mod.read_file("config.json") ~= nil     -- 只用于措辞（有无配置文件）
      chat_print("[世界工坊] 聊天指令默认关闭：要 /forge 命令请在 TEFManager 里打开「聊天指令」"
          .. "（这一条与一次实机崩溃的路径相邻，所以默认不碰）。"
          .. "导入设置串不受影响：把串粘贴到「导入设置串」设置项即可；"
          .. "导出仍会写入模组私有目录 forge_export.txt 并在游戏内播报。")
      diag("已播报「聊天指令默认关闭」提示（config.json 存在=" .. tostring(okw) .. "）")
      diag_flush()
  end

  -- ★ v5.0.0：进世界后一次性自动导出（设置项「自动导出设置串」打开时）。
  --   导出这条路**与聊天指令无关**（§9.3 导出方向：落盘 + Main.NewText 播报）。
  --   只导「与默认值不同」的项；一项都没有时 export_channel 自己会播报并返回 false，
  --   这里额外用 mem 记一次「本世界已经试过了」，避免每次进世界都刷屏。
  function auto_export_report(origin)
      if not cfg.export_mode then return false end
      -- 先看有没有非默认项：没有就静默跳过（不然每次进世界都多一行「没有非默认项」）
      local _, n = build_settings_string(false)
      if n == 0 then
          diag("自动导出（" .. tostring(origin) .. "）：没有与默认值不同的项，跳过")
          diag_flush()
          return false
      end
      return (export_channel(origin))
  end

  -- 把 import_string 就地清空（只动这一个 key 的字面量，其它 key 与 schemaVersion 原样保留）
  function clear_import_string()
      local raw = mod.read_file("config.json")
      if type(raw) ~= "string" or raw == "" then return false end
      local kq = '"import_string"'
      local pat = kq .. '%s*:%s*"[^"]*"'
      local hit = false
      local nraw = raw:gsub(pat, function() hit = true return kq .. ':""' end, 1)
      if not hit then
          -- 文件里根本没有这个 key（TEFManager 省略了空串项）：塞一个进 values
          local n2
          if nraw:find('"values"%s*:%s*{}') then
              nraw, n2 = nraw:gsub('("values"%s*:%s*){}',
                  function(a) return a .. '{' .. kq .. ':""}' end, 1)
          else
              nraw, n2 = nraw:gsub('("values"%s*:%s*{)',
                  function(a) return a .. kq .. ':""' .. ',' end, 1)
          end
          if n2 and n2 > 0 then nraw = nraw:gsub(",%s*}", "}") hit = true end
      end
      if not hit then return false end
      if not mod.write_file("config.json", nraw) then return false end
      cfg.import_string = ""        -- 内存同步，避免同一拍里再被当成「新串」
      return true
  end

  -- 命令分发：命中就返回 true（→ 聊天钩子的 prefix 跳过原方法，设置串不会当普通聊天发出去）
  function handle_text(text)
      if type(text) ~= "string" then return false end
      -- ★ 默认零依赖：chat_cmd 关着时连字符串都不解析（保证「完全不碰聊天」这条语义）
      if not cfg.chat_cmd then return false end
      local t = text:gsub("^%s+", ""):gsub("%s+$", "")
      if t:sub(1, 1) == "/" then t = t:sub(2) end
      if t == "" then return false end

      -- diag_report_cmd（默认 forge stat）允许玩家自定义触发串
      local cfgtxt = tostring(cfg.diag_report_cmd or "")
      local cnorm = cfgtxt:gsub("^%s+", ""):gsub("^/", ""):gsub("%s+$", ""):lower()
      if cnorm ~= "" and t:lower() == cnorm then
          stats.chat_cmds = stats.chat_cmds + 1
          CT.hits = CT.hits + 1
          report_stats()
          return true
      end

      local head, rest = t:match("^(%S+)%s*(.*)$")
      if not head or head:lower() ~= CMD then return false end
      stats.chat_cmds = stats.chat_cmds + 1
      CT.hits = CT.hits + 1
      local sub, arg = rest:match("^(%S*)%s*(.*)$")
      sub = (sub or ""):lower()
      if sub == "" or sub == "help" then
          cmd_help()
      elseif sub == "stat" then
          report_stats()
      elseif sub == "check" then
          self_check_report()
      elseif sub == "export" then
          cmd_export((arg or ""):lower():find("all", 1, true) ~= nil)
      elseif sub == "import" then
          cmd_import(arg)
      elseif sub == "one" then
          -- v9：一键操作。★ 与 GUI 第 5 页走的是同一条实现（87 分片的 oneshot_run），
          --   所以「禁止雷击 / 仅房主生效」这些闸门的行为完全一致。
          local id = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
          if id == "" then
              local ids = type(oneshot_ids) == "function" and oneshot_ids() or {}
              chat_print("[世界工坊] 一键操作编号（共 " .. tostring(#ids) .. " 个）："
                  .. table.concat(ids, " "))
              chat_print("[世界工坊] 用法：/forge one <编号>；GUI 第 5 页「一键」有同样的按钮")
          elseif type(oneshot_run) == "function" then
              chat_print("[世界工坊] 一键操作 " .. id .. "：" .. tostring(oneshot_run(id)))
          else
              chat_print("[世界工坊] 一键操作分片未启用（87_oneshot 没装上）")
          end
      elseif sub == "wgen" then
          -- v6：地图生成专项的进度 / 取消（聊天指令默认关闭，打开时才有意义）
          if (arg or ""):lower():find("stop", 1, true) then
              if WGCTL.cancel and WGCTL.cancel() then
                  chat_print("[世界工坊] 地图生成专项：已取消（已放置 / 已清除的部分不会回滚）")
              else
                  chat_print("[世界工坊] 地图生成专项：当前没有进行中的任务")
              end
          else
              chat_print("[世界工坊] 地图生成专项：" .. tostring(WGCTL.status and WGCTL.status() or "未启用"))
              if WGCTL.chain then
                  chat_print("[世界工坊] 触发链：" .. tostring(WGCTL.chain()))
              end
          end
      else
          chat_print("[世界工坊] 未知命令：" .. sub .. "（用 /forge help 看命令表）")
      end
      return true
  end

  -- ---------------------------------------------------------------- 聊天钩子
  -- ★ 只处理本机玩家（约定 §2.1）。clientId 是 byte（Lua 侧是 number）。
  --   取不到 Main.myPlayer 时**宁可放行**（返回 false，交给原逻辑）也不误吞别人的聊天。
  local function is_local_client(cid)
      if type(cid) ~= "number" then return false end
      local my = my_player_index()
      if type(my) ~= "number" then return false end
      return cid == my
  end

  -- prefix：返回 true = 跳过原方法（命中本模组命令时顺手阻止原版广播这段设置串）
  local function on_say_incoming(inst, args)
      if not ready or type(args) ~= "table" then return false end
      -- ★ v6.0.1：钩子的 string 形参也是**托管字符串句柄**（内核按 PATCH_OBJECT 压栈，
      --   见 lua_api.cpp push_hook_arg_value），不是 Lua 字符串 —— 必须过 patch.string_value
      --   取值。旧写法 `type(text) ~= "string"` 会把所有聊天命令静默吃掉
      --   （chat_cmd 开着也永远没反应）；这里两种形态都兼容。
      local text = args[1]
      if type(text) ~= "string" and patch.string_value then
          local okv, v = pcall(patch.string_value, text)
          if okv then text = v end
      end
      if type(text) ~= "string" then return false end
      if not is_local_client(args[2]) then return false end
      local ok, handled = pcall(handle_text, text)
      if ok and handled == true then return true end
      return false
  end

  CT = domain({
      name = "聊天命令",
      fields = function(T)
          -- ★ 本域**没有任何字段**：聊天文本来自 SayChatCommand 的纯 string 形参，
          --   绝不反射聊天消息对象的任何成员（那段就是实机 SIGABRT 那一行）。
      end,
      methods = function(T)
          -- ★ Main.NewText 与聊天类型无关，任何情况下都解析：
          --   import_string 通道、液体进度、自动重复事件都要用它播报。
          M.new_text = T.MAIN and find_method(T.MAIN, "NewText", 5)
          if not M.new_text then
              warn_once("newtext", "找不到 Main.NewText(string,byte,byte,byte,bool)：聊天输出改为只写日志")
          end
          -- ★ 门控：chat_cmd 关闭（默认）→ 下面一步都不走，Type.CHATSAY 保持 nil，
          --   install 阶段 safe_hook(nil) 直接跳过 —— 默认路径上零聊天触达。
          if not chat_domain_enabled() then return end
          T.CHATSAY = get_type("Terraria.Chat.Commands", "SayChatCommand")
          if T.CHATSAY then
              M.chat_say = find_method(T.CHATSAY, "ProcessIncomingMessage", 2)
          end
          -- Main.myPlayer 是**属性**（符号表「修饰」列带 [属性]）→ 必须走
          -- get_property + property_get_method 桥接（约定 §2.1）。旧加载器没有这两个 API 时
          -- 退回 setup 第 3 阶段用 get_myPlayer() 取的 getter（core 的 my_player_index 会用）。
          if T.MAIN and patch.get_property and patch.property_get_method then
              local okp, prop = pcall(patch.get_property, T.MAIN, "myPlayer")
              if okp and prop then
                  local okg, g = pcall(patch.property_get_method, prop)
                  if okg and g then
                      M.get_my_player = g
                      M.my_player_bridge = true
                  end
              end
          end
          if not M.get_my_player then
              warn_once("myplayer", "取不到 Main.myPlayer（属性桥接与 get_myPlayer 都失败）："
                  .. "聊天命令将只处理「clientId 参数缺失」的消息")
          end
          if not M.chat_say then
              warn_once("chatsay", "找不到 SayChatCommand.ProcessIncomingMessage(string,byte)："
                  .. "聊天命令不可用（导入请改用「导入设置串」设置项）")
          end
      end,
      install = function()
          -- chat_cmd 关闭时不装（M.chat_say 为 nil → safe_hook 只打一条日志就返回）
          if not chat_domain_enabled() then return end
          safe_hook(M.chat_say, { prefix = on_say_incoming },
              "Chat.Commands.SayChatCommand.ProcessIncomingMessage（聊天命令入口）")
      end,
      reset = function()
          mem.imp = nil
      end,
  })

end


-- ============================================================================
-- 96 · 游戏内 GUI 面板（WorldForge 世界工坊）—— LuaLoader 1.9.0 / mod.gui 40 项
-- ----------------------------------------------------------------------------
-- 【这一版重做了什么】（1.8.0 / 36 项 → 1.9.0 / 40 项）
--
--   1) 滚动容器 + 虚拟列表（1.9.0 新增 begin_scroll / end_scroll）
--      参数页与一键页的列表**只为可见行发绘制指令**，一页能装几百行也不会画到
--      窗口外。旧版只有「一行行往下堆 + 翻页压缩」，参数一多就要靠翻页硬扛；
--      现在长内容不再有上限（16-GUI开发.md §3.4、陷阱 5）。
--   2) 图片皮肤：set_skin(panel.png, 16, glyph.png, 40) + 九宫格 nine_slice
--      + 图片按钮 image_button + 1x1 白图纯色（image）。收起入口从「文字方块」
--      变成一张图（§4.5 实测反馈：单个汉字观感差）。
--   3) 缓存读数：诊断页印 image_cache_stats() 的 4 个数（§4.4）。
--   4) 中文不再画成 *：所有要绘制的字符串统一过 SX()（见下面的符号表）。
--      机理：泰拉瑞亚把 SpriteFont.DefaultCharacter 设成了 '*'，字形缺失的字符
--      会画成 *。手机版中文走的是**官方中文本地化子集字体**（几百个常用字 +
--      常用全角标点），Mod 自造的箭头 / 星号 / 数学符号 / 圈号几乎都缺字形。
--      对策是「不让这些字符进入绘制调用」，**不是**把界面改成英文。
--   5) 高度安全：窗口内容高固定 = 实测可用内容高（§3.2 零游戏符号探测），
--      所有长内容一律进滚动容器，绝不让任何控件画到内容区之外
--      （真机实测：超出屏幕的滑块点不到，§3.1 / §10.1 第 6 条）。
--      可用内容高连「头部 + 控制行 + 工具条 + 最小视口」都放不下时，页脚工具条让位给
--      一行 check_line 告警（文案保留旧版的「超出屏幕」，玩家看得懂 —— 旧版 abs_warn 有它，
--      重写成滚动容器时不能把这条玩家可见的告警弄丢）。
--
-- 【1.9.0 的三处行为变化，本文件全部按新行为写（§1.3）】
--   · 收起后**一律**是 32*g_scale 的方形图标（不再「没 icon 就只剩标题栏」）
--     → set_skin 给一张图标图，set_title 的文字图标只当图片没解码完时的兜底。
--   · set_pos 首次调用会被加载器私有目录的 gui_layout.json 覆盖
--     → 屏幕探测从第 2 帧才开始（第 1 帧绝不调 set_pos，陷阱 11）。
--   · set_style 的 text 键现在也管按钮 / 复选框 / 进度条 / 折叠头 / 输入框的文字
--     → 本面板是「米黄纸 + 墨字」亮色主题，按钮文字跟着变深，不再白字白底（§5）。
--
-- 【配色】模仿 交接目录/参考ui2.jpg（游戏内「合成图鉴」）：米黄羊皮纸底 + 深褐描边
--   + 金褐按钮 + 墨褐正文。没选参考ui.jpg（深色 Boss 清单）的原因：前者是浅底
--   深字，中文在 0.5~0.6 缩放下更清楚，也顺手绕开「亮色 title 配硬编码白字」的坑。
--
-- 【容器纪律】
--   · 本分片一次 patch.* 反射调用都没有（红线）；
--   · 每一帧**第一行**就是 set_content_height（陷阱 27：它写在最后 + 中间任何一行
--     抛错 = 窗口高退回 56*g_scale，真机表现是「面板缩成一条、点不了也滚不动」）；
--   · 除旧加载器降级页外，所有绘制要么是绝对布局、要么在 begin_scroll/end_scroll
--     里：**根上下文里一个流式控件都不发**（根上下文的 cy 直接决定窗口高度）。
--     用 set_cursor + 流式控件做「精确落位的真滑块 / 真复选框」时，也都先开一层
--     滚动视口，这样根光标不会被推走。
--   · 每个 G[name] 调用前先 type(G[name])=="function" 判空；整帧套 pcall。
--   · 绝不给 text_at / rect / button_at 传 nil 颜色（陷阱 27：luaL_checktype 直接
--     luaL_error，整帧中断）。所有颜色都来自下面的 C 表，永远是真的 {r,g,b,a}。
-- ============================================================================
local function wf_gui_install()
  local VERSION    = tostring(mod.meta.version)
  local STATE_FILE = "worldforge-gui.txt"
  local LOG_FILE   = "worldforge.log"
  local NL         = string.char(10)
  local G          = nil

  -- ---------------------------------------------------------------- 40 项名单
  -- 36 项（1.8.0）+ 1.9.0 新增的 4 项。名字一个字都不许猜：全部来自
  -- 参考库/上游/LuaLoader-1.9.0/doc/gui.md §2~§5 与 src/gui.cpp 的注册表。
  local API40 = {
    "text", "text_wrapped", "button", "checkbox", "slider", "same_line", "separator", "spacing",
    "collapsing_header", "progress_bar", "input_text", "set_title", "set_pos", "get_pos",
    "set_width", "set_cursor", "set_visible", "is_visible", "show", "hide", "set_collapsed",
    "is_collapsed", "toggle_collapsed", "set_style", "rect", "text_at", "button_at",
    "set_content_height", "load_image", "image_status", "release_image", "image", "image_fit",
    "nine_slice", "image_button", "set_skin",
    "begin_scroll", "end_scroll", "scroll_to", "image_cache_stats",
  }
  local API_NEW = { "begin_scroll", "end_scroll", "scroll_to", "image_cache_stats" }

  local PAGES = { "状态", "参数", "一键", "工具", "帮助" }
  local BIG = 999999.0
  local WIN_W_MIN, WIN_W_MAX, WIN_W_DEFAULT = 360, 900, 470
  local POS_MAX_X, POS_MAX_Y = 1200, 300

  -- ---------------------------------------------------------------- 配色表
  -- 全部是真的 {r,g,b,a}：任何一处传 nil 都会 luaL_error（陷阱 27）。
  -- 只有这 7 个键能进 set_style：panel title button hover active border text。
  local C = {
    panel  = { 240, 228, 200, 246 },   -- 羊皮纸底
    title  = { 236, 222, 194, 255 },   -- 标题栏（浅底 → 配深字，绕开硬编码白字）
    button = { 214, 194, 158, 255 },
    hover  = { 234, 216, 176, 255 },
    active = { 176, 142, 92, 255 },
    border = { 74, 46, 20, 255 },      -- 深褐描边（也管滚动滑轨）
    text   = { 58, 38, 18, 255 },      -- 墨褐正文
    accent = { 138, 40, 26, 255 },     -- 朱红（标题 / 强调）
    gold   = { 156, 112, 44, 255 },    -- 金褐（次级强调）
    muted  = { 108, 86, 58, 255 },
    white  = { 255, 255, 255, 255 },
    invis  = { 255, 255, 255, 0 },     -- 1x1 透明预解码用
    row_a  = { 228, 214, 184, 255 },   -- 奇偶条纹
    row_b  = { 236, 224, 198, 255 },
    diff   = { 246, 222, 158, 255 },   -- 改动高亮
    warn   = { 168, 40, 32, 255 },
    ok     = { 74, 108, 46, 255 },
  }

  -- ---------------------------------------------------------------- 基础工具
  local function clamp_iv(v, lo, hi)
    v = math.floor(tonumber(v) or lo)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end
  -- 永远给出一个数字：nil / NaN 都不许流进绘制调用。
  -- （math.floor(nil) 和「传 nil 颜色」一样是整帧中断的常见源头，陷阱 27）
  local function num(v, d)
    v = tonumber(v)
    if v == nil or v ~= v then return d end
    return v
  end
  local function has(n) return G ~= nil and type(G[n]) == "function" end
  local function api(n, ...)
    if not has(n) then return false end
    return pcall(G[n], ...)
  end
  local function utf8_n(b)
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
  end
  local function units(s)
    local n, i, len = 0, 1, #s
    while i <= len do
      local l = utf8_n(string.byte(s, i))
      n = n + ((l == 1) and 1 or 2)     -- ASCII 算 1 个单位，CJK 算 2 个
      i = i + l
    end
    return n
  end
  -- 按「显示宽度单位」截断。★ 游戏字体不能按像素裁剪：滚动视口边缘不完整的
  -- 文本行会被**整行隐藏**（陷阱 7 / §3.5），所以宁可自己截断。省略号留 3 个单位。
  local function trunc(s, maxu)
    s = tostring(s)
    if units(s) <= maxu then return s end
    if maxu < 6 then maxu = 6 end
    local n, i, out, len = 0, 1, {}, #s
    while i <= len do
      local l = utf8_n(string.byte(s, i))
      local u = (l == 1) and 1 or 2
      if n + u > maxu - 3 then break end
      out[#out + 1] = s:sub(i, i + l - 1)
      n = n + u
      i = i + l
    end
    return table.concat(out) .. "..."
  end
  -- 一个显示宽度单位在某 scale 下大约占多少像素（真机实测 1.0 时 ASCII ≈ 13px）
  local function fit(s, bw, sc)
    local maxu = math.floor(num(bw, 200) / (13 * num(sc, 0.6)))
    if maxu < 8 then maxu = 8 end
    return trunc(s, maxu)
  end

  -- ==========================================================================
  -- 中文变 * 的处置：绘制前把所有高风险符号换成 ASCII 等价物
  -- --------------------------------------------------------------------------
  -- 表用 \u{...} 转义写（Lua 5.3+ 的十六进制字符转义），原因是这个分片要被
  -- tests/test.lua 的静态契约扫一遍：源码里**不许出现**那些码位（真机字体没有
  -- 它们的字形）。写成转义后，源码本身是纯 ASCII，而运行时替换照样生效。
  -- 右边一列**全部是 ASCII**，所以 SX() 是幂等的（替换结果不会再被任何键命中）。
  -- 保留：常用汉字 + 官方中文里一定出现的全角标点 ，。：、？！（）""''%
  -- 换掉：其余装饰性符号（星号 / 箭头 / 框线 / 数学符号 / 圈号 / 扑克牌 …）。
  -- 「删」= 直接删掉（装饰性符号删了不影响语义）。
  -- ==========================================================================
  local SYM = {
    -- 星号 / 闪光类装饰
    ["\u{2605}"] = "", ["\u{2606}"] = "", ["\u{2726}"] = "", ["\u{2727}"] = "",
    ["\u{272A}"] = "", ["\u{2736}"] = "", ["\u{273D}"] = "",
    -- 箭头
    ["\u{2192}"] = "->", ["\u{2190}"] = "<-", ["\u{2191}"] = "^", ["\u{2193}"] = "v",
    ["\u{2194}"] = "<->", ["\u{21D2}"] = "=>", ["\u{21D0}"] = "<=",
    ["\u{25B8}"] = ">", ["\u{25C2}"] = "<", ["\u{25B6}"] = ">", ["\u{25C0}"] = "<",
    ["\u{25B2}"] = "^", ["\u{25BC}"] = "v",
    -- 方框 / 书名号 / 括号类（全角圆括号（）保留，不动）
    ["\u{3010}"] = "[", ["\u{3011}"] = "]",
    ["\u{3014}"] = "[", ["\u{3015}"] = "]",
    ["\u{300A}"] = "<", ["\u{300B}"] = ">", ["\u{3008}"] = "<", ["\u{3009}"] = ">",
    ["\u{300C}"] = "[", ["\u{300D}"] = "]", ["\u{300E}"] = "[", ["\u{300F}"] = "]",
    -- 制表 / 框线
    ["\u{2500}"] = "-", ["\u{2501}"] = "-", ["\u{2502}"] = "|", ["\u{2550}"] = "=",
    ["\u{250C}"] = "+", ["\u{2510}"] = "+", ["\u{2514}"] = "+", ["\u{2518}"] = "+",
    -- 数学 / 标度
    ["\u{00F7}"] = "/", ["\u{00D7}"] = "X", ["\u{00B2}"] = "2", ["\u{00B3}"] = "3",
    ["\u{2103}"] = "C", ["\u{2030}"] = "0/00", ["\u{221A}"] = "sqrt",
    ["\u{2248}"] = "~=", ["\u{2265}"] = ">=", ["\u{2264}"] = "<=",
    ["\u{2260}"] = "!=", ["\u{00B1}"] = "+-", ["\u{221E}"] = "inf",
    -- 打勾 / 打叉（真机会画成 * 或方块）
    ["\u{2714}"] = "OK", ["\u{2713}"] = "OK", ["\u{2611}"] = "OK",
    ["\u{2718}"] = "X", ["\u{2717}"] = "X", ["\u{2715}"] = "X", ["\u{2716}"] = "X",
    ["\u{274C}"] = "X", ["\u{2705}"] = "OK", ["\u{26A0}"] = "!!",
    -- 省略号 / 间隔号 / 破折号
    ["\u{2025}"] = "...", ["\u{2026}"] = "...", ["\u{00B7}"] = ".", ["\u{2027}"] = ".",
    ["\u{30FB}"] = ".", ["\u{2014}"] = "-", ["\u{2013}"] = "-", ["\u{FF0D}"] = "-",
    ["\u{2018}"] = "'", ["\u{2019}"] = "'", ["\u{201C}"] = "\"", ["\u{201D}"] = "\"",
    ["\u{00A7}"] = "", ["\u{203B}"] = "[!]", ["\u{FF5E}"] = "~", ["\u{301C}"] = "~",
    -- 圈号 / 括号数字
    ["\u{2460}"] = "(1)", ["\u{2461}"] = "(2)", ["\u{2462}"] = "(3)", ["\u{2463}"] = "(4)",
    ["\u{2464}"] = "(5)", ["\u{2465}"] = "(6)", ["\u{2466}"] = "(7)", ["\u{2467}"] = "(8)",
    ["\u{2468}"] = "(9)", ["\u{2469}"] = "(10)",
    -- 几何 / 圆点 / 扑克 / 其他装饰
    ["\u{25CB}"] = "o", ["\u{25CF}"] = "o", ["\u{25A0}"] = "#", ["\u{25A1}"] = "#",
    ["\u{25C7}"] = "<>", ["\u{25C6}"] = "<>", ["\u{25B3}"] = "^", ["\u{25BD}"] = "v",
    ["\u{2660}"] = "", ["\u{2665}"] = "", ["\u{2666}"] = "", ["\u{2663}"] = "",
    ["\u{3299}"] = "", ["\u{25CE}"] = "", ["\u{263A}"] = "", ["\u{266A}"] = "",
    ["\u{2600}"] = "", ["\u{2601}"] = "", ["\u{2602}"] = "", ["\u{2603}"] = "",
    ["\u{FF5C}"] = "|", ["\u{FF3C}"] = "\\", ["\u{FF0F}"] = "/", ["\u{3000}"] = " ",
  }
  local function sub_all(s, from, to)
    local out, i = {}, 1
    while true do
      local a, b = s:find(from, i, true)
      if not a then out[#out + 1] = s:sub(i) break end
      out[#out + 1] = s:sub(i, a - 1)
      out[#out + 1] = to
      i = b + 1
    end
    return table.concat(out)
  end
  -- 唯一入口：所有要绘制的字符串都要走这里（含按钮 / 复选框 / 滑块的 label）。
  -- 纯 ASCII 的字符串直接返回（一行 find 的开销），含非 ASCII 才逐字符查表。
  local function SX(v)
    local s = tostring(v)
    if not s:find("[\128-\255]") then return s end
    local out, i, len, hit = {}, 1, #s, false
    while i <= len do
      local l = utf8_n(string.byte(s, i))
      local ch = s:sub(i, i + l - 1)
      local r = SYM[ch]
      if r ~= nil then hit = true out[#out + 1] = r else out[#out + 1] = ch end
      i = i + l
    end
    if not hit then return s end
    return table.concat(out)
  end

  -- ---------------------------------------------------------------- 面板状态
  local S = {
    inited = false, predecoded = false, frames = 0,
    page = 1, tab = 1,
    g = 1.0, budget = 0,
    win_x = 24, win_y = 24, win_w = WIN_W_DEFAULT,
    pos_valid = false, pos_applied = false, width_applied = -1,
    api_have = 0, api_missing = "", api_missing_n = 0,
    visible = true, force_save = false,
    last_err = "", err_mode = false, err_logged = false,
    last_hits = 0, last_calls = 0, frame_hits = 0, frame_calls = 0, total_hits = 0,
    fields_miss = 0, methods_miss = 0, warn_n = 0,
    d_ok = 0, d_note = 0, d_bad = 0, d_off = 0, dom_list = {}, dom_bad_only = false,
    dom_page = 1, last_dom_err = "-",
    grp = 1, only_diff = false, sel = nil, filter = "",
    -- ★ v10.3：折叠状态进状态文件（gopen=组号列表）；默认只展开第 1 组
    gopen = {}, gopen_loaded = false,
    -- ★ v10.3：检索缓存（键 = 输入串 + 分组版本）与命中计数（自检页会印出来）
    fver = 0, fcache_key = nil, fcache = nil, fcalc = 0, fhit = 0,
    -- ★ v10.3（B5）：数字输入态；危险动作的二次确认态
    num_key = nil, num_buf = "", num_msg = "",
    os_confirm = nil, key_confirm = nil,
    os_tab = 1,
    op_last = "-", op_n = 0, apply_n = 0, reloads_seen = -1,
    gkeys = 0, gbool = 0, gnum = 0, gchoice = 0, gstr = 0,
    changed = false, changed_prev = false,
    log_lines = {}, log_n = 0, log_at = -999, log_err = "(还没读)",
    img_ready = 0, img_total = 0, img_stat = {},
    cache = { 0, 0, 0, 0 }, cache_at = 0,
    roll_pending = false, roll_hit = 0, roll_miss = {}, roll_last = "(还没跑)",
    fold1 = false, fold2 = false,
    sc_open = 0, sc_close = 0, sc_depth = 0, sc_extra = 0, scroll = true,
    sc_po = 0, sc_pc = 0,
    probe = { phase = 0, done = false, unclamped = false, x_max = 0, y_max = 0,
              s = 1.0, screen_w = 0, screen_h = 0, saved_x = 24, saved_y = 24 },
  }
  -- 运行时覆盖层：GOV[k] 是本帧盖在 cfg[k] 上的值。
  -- ★ 面板**只改运行时** cfg，绝不写 TEFManager 的 config.json（18 章硬约束 10）；
  --   要留下来的写自己的状态文件 worldforge-gui.txt。
  local GOV = {}
  local GOV_N = 0
  local function gov_count()
    local n = 0
    for _ in pairs(GOV) do n = n + 1 end
    GOV_N = n
    return n
  end
  local function budget()      -- 可用内容高（px）；0 = 还没测出来
    if S.probe.done and not S.probe.unclamped and S.budget > 0 then return S.budget end
    return 0
  end
  local function avail()       -- 要声明给加载器的窗口内容高
    local b = budget()
    if b > 0 then return b end
    return 380.0
  end
  -- ★ 保留这个函数名与写法：静态契约要求「布局按探针测到的 g_scale 缩放（不写死像素）」
  local function U(v) return v * S.g end

  -- ---------------------------------------------------------------- 图片
  -- PNG 只放 Resources/lib/ui/ 下，路径写 lib/ui/x.png（相对模组私有目录）。
  -- ★ 皮肤用的两张（panel / glyph）绝不 release：release_image 立刻删缓存条目，
  --   皮肤与收起图标会当场失效（陷阱 18）；要演示生命周期就 release white。
  local IMGP = {
    white  = "lib/ui/white.png",     -- 1x1 白图：加颜色 = 真正的纯色矩形
    panel  = "lib/ui/panel.png",     -- 九宫格羊皮纸（set_skin + nine_slice）
    button = "lib/ui/button.png",    -- 九宫格按钮（image_button）
    glyph  = "lib/ui/glyph.png",     -- 收起入口图标 / 关于页 image_fit
  }
  local IMG = {}
  local IMG_TRIED = false
  local function ensure_images()
    if IMG_TRIED then return end
    IMG_TRIED = true
    if not has("load_image") then return end
    local n = 0
    -- 固定顺序（pairs 顺序不定，但这里只影响 load 的先后，无所谓）
    local order = { "white", "panel", "button", "glyph" }
    for i = 1, #order do
      local k = order[i]
      local ok, id = pcall(G.load_image, IMGP[k])
      if ok and type(id) == "string" then IMG[k] = id n = n + 1 end
    end
    S.img_total = n
  end
  -- ★ load_image 只登记；真正解码发生在**第一次被绘制**时 → 想提前拿尺寸 /
  --   想让 image_status 变成 ready，就先 1x1 透明画一次（§4.2）。
  local function predecode_images()
    if not has("image") then return end
    local order = { "white", "panel", "button", "glyph" }
    for i = 1, #order do
      local id = IMG[order[i]]
      if id then pcall(G.image, id, 0, 0, 1, 1, C.invis, nil) end
    end
  end
  local function refresh_images()
    S.img_ready = 0
    S.img_stat = {}
    if not has("image_status") then return end
    local order = { "white", "panel", "button", "glyph" }
    for i = 1, #order do
      local k = order[i]
      local id = IMG[k]
      if id then
        local ok, st, w, h = pcall(G.image_status, id)
        local stx = ok and tostring(st or "?") or "(status 调用失败)"
        S.img_stat[k] = string.format("%s %sx%s", stx, tostring(ok and w or "?"), tostring(ok and h or "?"))
        if stx == "ready" then S.img_ready = S.img_ready + 1 end
      else
        S.img_stat[k] = "nil（load_image 返回 nil，图没打包进来？）"
      end
    end
  end

  -- ---------------------------------------------------------------- 绘制包装
  -- 每个包装都做四件事：① type(G[x])=="function" 判空 ② pcall ③ 颜色永远是表
  -- ④ 字符串过 SX()。少一项 API 只降级，绝不整帧抛错（硬性要求 6）。
  local D = {}
  D.text = function(x, y, s, col, sc, bw)
    if not has("text_at") then return end
    local t = SX(s)
    if bw then t = fit(t, bw, sc) end
    pcall(G.text_at, num(x, 0), num(y, 0), t, col or C.text, num(sc, 0.6))
  end
  D.rect = function(x, y, w, h, col)
    if not has("rect") then return end
    w, h = num(w, 0), num(h, 0)
    if w <= 0 or h <= 0 then return end
    pcall(G.rect, num(x, 0), num(y, 0), w, h, col or C.row_a)
  end
  D.btn = function(x, y, w, h, label)
    if not has("button_at") then return false end
    w, h = num(w, 0), num(h, 0)
    if w <= 0 or h <= 0 then return false end
    local ok, hit = pcall(G.button_at, num(x, 0), num(y, 0), w, h, SX(label))
    return ok and hit == true
  end
  D.ibtn = function(id, x, y, w, h, label, border)
    if num(w, 0) <= 0 or num(h, 0) <= 0 then return false end
    -- 图片没准备好就退回普通 button_at：降级而不是什么都不画（否则按钮点不到）
    if id == nil or not has("image_button") then return D.btn(x, y, w, h, label) end
    local ok, hit = pcall(G.image_button, id, num(x, 0), num(y, 0), w, h, SX(label),
                          math.max(0, math.floor(num(border, 0))))
    if not ok then return false end
    return hit == true
  end
  D.nine = function(id, x, y, w, h, border, col, edge)
    border = math.floor(num(border, 0))
    if border <= 0 or num(w, 0) <= 0 or num(h, 0) <= 0 then return end
    if id == nil or not has("nine_slice") then D.rect(x, y, w, h, col) return end
    pcall(G.nine_slice, id, num(x, 0), num(y, 0), w, h, border, col or C.white, num(edge, 0))
  end
  D.img = function(id, x, y, w, h, col, src)
    if id == nil or not has("image") then return end
    w, h = num(w, 0), num(h, 0)
    if w <= 0 or h <= 0 then return end
    pcall(G.image, id, num(x, 0), num(y, 0), w, h, col or C.white, src)
  end
  D.imgfit = function(id, x, y, w, h, mode, col)
    if id == nil or num(w, 0) <= 0 or num(h, 0) <= 0 then return end
    if has("image_fit") then
      pcall(G.image_fit, id, num(x, 0), num(y, 0), w, h, mode or "contain", col or C.white)
    else
      D.img(id, x, y, w, h, col, nil)
    end
  end
  -- 1x1 白图 + 颜色 = 真正的纯色矩形（rect 走 DrawInvBG 底纹，做不到纯色）
  D.fill = function(x, y, w, h, col)
    if IMG.white then D.img(IMG.white, x, y, w, h, col, nil) else D.rect(x, y, w, h, col) end
  end
  -- 按钮皮肤：九宫格 button.png；没有图就交给 D.ibtn 退回普通按钮
  local function bskin() return IMG.button or IMG.panel end

  -- ---------------------------------------------------------------- 流式包装
  -- 流式控件只在三处出现（它们才是「真能拖的滑块 / 真能点的复选框」）：
  --   ① 参数页每一行：set_cursor 精确落位 + 只给可见行发（虚拟列表）；
  --   ② 各页底部的工具条：编辑当前项 / 快捷开关 / 筛选框 / 折叠头 / 进度条；
  --   ③ 旧加载器降级页。
  -- ★ ①② 一律先开一层滚动视口，这样根光标（决定窗口高度）不会被推走。
  local FW = {}
  FW.text  = function(s) return api("text", SX(s)) end
  FW.wrap  = function(s) return api("text_wrapped", SX(s)) end
  FW.btn   = function(s) local ok, r = api("button", SX(s)) return ok and r == true end
  -- ★ checkbox 返回的是**新值**，不是「是否被点击」（陷阱 4）。
  --   写成 if checkbox() then 翻转 end，只要当前值是 true 就每帧翻转一次。
  FW.check = function(s, v)
    v = (v == true)
    local ok, r = api("checkbox", SX(s), v)
    if ok and type(r) == "boolean" then return r end
    return v
  end
  FW.same  = function() return api("same_line") end
  FW.sep   = function() return api("separator") end
  FW.space = function() return api("spacing") end
  FW.fold  = function(s)
    local ok, r = api("collapsing_header", SX(s))
    if ok and type(r) == "boolean" then return r end
    return false
  end
  FW.bar   = function(v)
    local x = num(v, 0)
    if x < 0 then x = 0 end
    if x > 1 then x = 1 end
    return api("progress_bar", x)
  end
  FW.input = function(s, v)
    v = tostring(v or "")
    local ok, r = api("input_text", SX(s), v)
    if ok and type(r) == "string" then return r end
    return v
  end
  local function cursor(x, y)          -- 流式控件落位（相对当前上下文原点）
    if has("set_cursor") then pcall(G.set_cursor, num(x, 0), num(y, 0)) end
  end

  -- ---------------------------------------------------------------- 滚动视口
  -- begin_scroll(id,x,y,w,h,cw,ch) → sx,sy,vw,vh；内部坐标相对滚动内容，
  -- 加载器自动减掉滚动偏移（§3.4）。参数校验很硬：w/h 必须 > 0、cw/ch 必须
  -- 有限且 >= 0，否则 luaL_error（陷阱 6）→ 这里全部夹一遍再发。
  -- 记账 sc_open/sc_close/sc_depth 是为了「每帧几何自查」里能证明配对。
  local function SB(id, x, y, w, h, cw, ch)
    w, h = num(w, 1), num(h, 1)
    if w <= 0 then w = 1 end
    if h <= 0 then h = 1 end
    cw, ch = num(cw, 0), num(ch, 0)
    if cw < 0 then cw = 0 end
    if ch < 0 then ch = 0 end
    if has("begin_scroll") then
      local ok, a, b, c, d = pcall(G.begin_scroll, id, num(x, 0), num(y, 0), w, h, cw, ch)
      if ok then
        S.sc_depth = S.sc_depth + 1
        S.sc_open = S.sc_open + 1
        return num(a, 0), num(b, 0), num(c, w), num(d, h)
      end
    end
    -- 视口没开成（老加载器）：坐标不再被平移，但不许报错 → 退化成「不裁剪」
    return 0, 0, w, h
  end
  local function SE()
    if S.sc_depth > 0 then
      S.sc_depth = S.sc_depth - 1
      S.sc_close = S.sc_close + 1
      if has("end_scroll") then pcall(G.end_scroll) end
    elseif has("end_scroll") then
      S.sc_extra = S.sc_extra + 1          -- 多关一次：只记账，不主动配对
    end
  end

  -- 老加载器（1.8.0）没有 begin_scroll：坐标不再被裁剪，所以只画「一定在窗口
  -- 内容区里」的行，宁可少画也不许画到窗口外（1.9.0 上 S.scroll = true，永远放行）。
  local function in_view(y, h, bh)
    if S.scroll then return true end
    return (num(y, 0) + num(h, 0)) <= num(bh, 0) + 2
  end

  -- 二分：第一条「底边在视口上边之下」的行（py 单调递增）。
  -- 只给可见行发绘制指令 = 虚拟列表（§3.4 明确点名的用法）。
  local function first_row(py, ph, n, sy)
    local lo, hi = 1, n
    while lo < hi do
      local mid = math.floor((lo + hi) / 2)
      if py[mid] + U(ph[mid]) <= sy then lo = mid + 1 else hi = mid end
    end
    return lo
  end

  -- ================================================================ 参数索引
  -- 唯一事实来源还是 main.lua 里的三个表：DEFAULTS / LIMITS / CHOICES
  -- （新增设置只改 main.lua 的这三个表，这一页自动长出控件）。
  -- 标题取 KEY_META（gen.py 从设置项 spec 生成，和 TEFManager 设置界面里一模一样）。
  local IDX = { keys = {}, by_key = {}, by_group = {}, groups = {} }
  local INDEX_BUILT = false

  local function kind_of(k)
    local d = DEFAULTS[k]
    if type(d) == "boolean" then return "bool" end
    if type(d) == "number" then return "int" end
    if CHOICES[k] then return "choice" end
    if type(d) == "string" then return "str" end
    return nil
  end
  local function key_meta(k)
    local m = KEY_META and KEY_META[k]
    if type(m) ~= "table" then return nil end
    return m
  end
  local function title_of(k)
    local m = key_meta(k)
    local t = (m and type(m[2]) == "string" and m[2] ~= "") and m[2] or tostring(k)
    local u = m and m[3]
    -- 全角括号（）是官方中文里一定有的字形，可以保留；"%" 单位没信息，不加
    if type(u) == "string" and u ~= "" and u ~= "%" then t = t .. "（" .. u .. "）" end
    return t
  end
  local function section_of(k)
    local m = key_meta(k)
    if m and type(m[1]) == "string" and m[1] ~= "" then return m[1] end
    return tostring(k):match("^([%a]+)_") or "其他"
  end
  local function cur_of(k)
    local v = GOV[k]
    if v == nil then v = cfg[k] end
    if v == nil then v = DEFAULTS[k] end
    return v
  end
  local function is_diff(k) return cur_of(k) ~= DEFAULTS[k] end
  local function build_index()
    if INDEX_BUILT then return end
    INDEX_BUILT = true
    local ks = {}
    for k in pairs(DEFAULTS) do ks[#ks + 1] = k end
    table.sort(ks)
    local nb, nn, nc, ns = 0, 0, 0, 0
    for i = 1, #ks do
      local k = ks[i]
      local kind = kind_of(k)
      -- ★ import_string 是「导入设置串」通道，不是参数：面板按硬约束不碰它
      --   （它会去改写 config.json，而面板只改运行时 cfg）。
      if kind and k ~= "import_string" then
        local full = SX(title_of(k))
        local e = { key = k, kind = kind, full = full, name = SX(trunc(full, 22)) }
        if kind == "int" then
          local lim = LIMITS[k]
          e.lo, e.hi = num(lim and lim[1], 0), num(lim and lim[2], 1000000)
          if e.hi <= e.lo then e.kind = "str" end
        elseif kind == "choice" then
          if type(CHOICES[k]) ~= "table" or #CHOICES[k] == 0 then e.kind = "str" end
        end
        if e.kind == "int" then nn = nn + 1
        elseif e.kind == "bool" then nb = nb + 1
        elseif e.kind == "choice" then nc = nc + 1
        else ns = ns + 1 end
        IDX.keys[#IDX.keys + 1] = e
        IDX.by_key[k] = e
        local grp = section_of(k)
        local bucket = IDX.by_group[grp]
        if not bucket then
          bucket = {}
          IDX.by_group[grp] = bucket
          IDX.groups[#IDX.groups + 1] = grp
        end
        bucket[#bucket + 1] = e
      end
    end
    table.sort(IDX.groups)
    -- ★ v10.3：分组版本号（检索缓存键的一半）；分组表建好就 +1
    S.fver = S.fver + 1
    -- ★ v10.3：默认只展开第 1 组；状态文件里有 gopen 记录时由 load_state 覆盖
    if not S.gopen_loaded then
      S.gopen = {}
      if IDX.groups[1] then S.gopen[IDX.groups[1]] = true end
    end
    S.gkeys, S.gbool, S.gnum, S.gchoice, S.gstr = #IDX.keys, nb, nn, nc, ns
  end
  -- ---------------------------------------------------------------- 检索（v10.3）
  -- 规则：输入 ≤2 字按「分组名」过滤（整组显示）；>2 字按「设置项标题」过滤
  -- （组里只留命中的项）。两条兜底：① 也匹配内部 key（自绘键盘没有中文，面板里只能敲
  -- ASCII）；② 大小写不敏感。
  -- 结果按「输入串 + 分组版本」缓存：同一串、分组没变就直接复用上一次的表，
  -- 单次重算 O(设置项数)，不是每帧 O(组数 × 项数)。
  local function hit(s, f)
    if f == "" then return true end
    if type(s) ~= "string" then return false end
    return s:lower():find(f:lower(), 1, true) ~= nil
  end
  -- 检索规则里的「2 个字」= 字符数（不是 units 的显示宽度：一个汉字算 2 个单位，
  -- 用 units 会把「地图」判成 4 而走错分支）
  local function nchars(s)
    local n, i, len = 0, 1, #s
    while i <= len do i = i + utf8_n(string.byte(s, i)) n = n + 1 end
    return n
  end
  local function filter_build()
    local f = S.filter or ""
    local fu = (f ~= "") and nchars(f) or 0
    local by_group, order, total = {}, {}, 0
    local mode = "全部"
    if fu > 0 and fu <= 2 then
      mode = "分组"
      for gi = 1, #IDX.groups do
        local gname = IDX.groups[gi]
        if hit(gname, f) then
          local src = IDX.by_group[gname] or {}
          local out = {}
          for i = 1, #src do
            local e = src[i]
            if not S.only_diff or is_diff(e.key) then out[#out + 1] = e end
          end
          if #out > 0 then
            by_group[gname] = out
            order[#order + 1] = gname
            total = total + #out
          end
        end
      end
    else
      if fu > 2 then mode = "标题" end
      for gi = 1, #IDX.groups do
        local gname = IDX.groups[gi]
        local src = IDX.by_group[gname] or {}
        local out = {}
        for i = 1, #src do
          local e = src[i]
          local keep = (not S.only_diff) or is_diff(e.key)
          if keep and f ~= "" then keep = hit(e.full, f) or hit(e.key, f) end
          if keep then out[#out + 1] = e end
        end
        if #out > 0 then
          by_group[gname] = out
          order[#order + 1] = gname
          total = total + #out
        end
      end
    end
    return { by_group = by_group, order = order, total = total, mode = mode, f = f }
  end
  local function filter_ver()
    return tostring(S.fver) .. "|" .. tostring(S.only_diff and 1 or 0) .. "|" ..
           tostring(#IDX.groups) .. "|" .. tostring(#IDX.keys)
  end
  local function filter_result()
    local key = tostring(S.filter or "") .. "@" .. filter_ver()
    if S.fcache_key == key and S.fcache then
      S.fhit = S.fhit + 1
      return S.fcache
    end
    local r = filter_build()
    S.fcache_key, S.fcache = key, r
    S.fcalc = S.fcalc + 1
    return r
  end
  local function group_list(grp)
    local r = filter_result()
    return (r.by_group and r.by_group[grp]) or {}
  end
  -- 检索时命中的组一律展开显示（不改状态文件里的折叠记录）：否则筛出来只剩组名
  local function group_open(gname)
    if (S.filter or "") ~= "" then return true end
    return S.gopen[gname] == true
  end
  local function next_group(dir)
    local n = #IDX.groups
    if n == 0 then return end
    local grp = clamp_iv(S.grp, 1, n)
    for _ = 1, n do
      grp = grp + dir
      if grp < 1 then grp = n end
      if grp > n then grp = 1 end
      if #group_list(IDX.groups[grp]) > 0 then break end
    end
    S.grp = grp
    S.force_save = true
    -- 换组后回到列表顶部（scroll_to 是 1.9.0 新增；位置只在会话内有效）
    if has("scroll_to") then pcall(G.scroll_to, "wf_params", 0, 0) end
  end
  local function set_val(e, v)
    if type(e) ~= "table" then return false end
    if e.kind == "bool" then
      GOV[e.key] = (v == true)
    elseif e.kind == "int" then
      local n = math.floor(num(v, DEFAULTS[e.key]))
      if n < e.lo then n = e.lo end
      if n > e.hi then n = e.hi end
      GOV[e.key] = n
    elseif e.kind == "choice" then
      local list = CHOICES[e.key]
      if type(list) ~= "table" then return false end
      local okv = false
      for i = 1, #list do if list[i] == v then okv = true end end
      if not okv then return false end
      GOV[e.key] = v
    else
      return false                     -- 文本项只读（长文本/换行会污染状态文件）
    end
    gov_count()
    S.force_save = true
    return true
  end
  -- 危险的单选项：先算出「下一个值」，等玩家确认后才 set_val
  local function next_choice(e)
    local list = CHOICES[e.key]
    if type(list) ~= "table" or #list == 0 then return nil end
    local cur = cur_of(e.key)
    local idx = 1
    for i = 1, #list do if list[i] == cur then idx = i end end
    idx = idx + 1
    if idx > #list then idx = 1 end
    return list[idx]
  end
  -- ★ v10.3：不可逆的参数项（改世界大小只对新建世界生效，改了就回不去）
  local DANGER_KEY = { wgen_size = true }
  local function bump(e, dir)
    if type(e) ~= "table" or e.kind ~= "choice" then return end
    local list = CHOICES[e.key]
    if type(list) ~= "table" or #list == 0 then return end
    local cur = cur_of(e.key)
    local idx = 1
    for i = 1, #list do if list[i] == cur then idx = i end end
    idx = idx + dir
    if idx < 1 then idx = #list end
    if idx > #list then idx = 1 end
    set_val(e, list[idx])
  end
  -- 重置单条：删掉覆盖层里的这一项 → 回到 config.json 的文件值 / 默认值
  local function reset_one(e)
    if type(e) ~= "table" then return end
    if GOV[e.key] ~= nil then
      GOV[e.key] = nil
      gov_count()
      S.force_save = true
      S.changed = true
    end
  end

  -- ================================================================ 运行时覆盖层
  -- 覆盖层 → 运行时 cfg（纯内存）+ 重算计划 + 各域重应用。★ 绝不写 config.json。
  local function apply_overlay(why)
    local n = 0
    for k, v in pairs(GOV) do
      if cfg[k] ~= v then cfg[k] = v n = n + 1 end
    end
    if n > 0 then
      pcall(build_plans)
      for i = 1, #DOMAINS do
        local fn = DOMAINS[i].phase and DOMAINS[i].phase.reload
        if fn then pcall(fn) end
      end
      diag(string.format("GUI 覆盖层已应用（%s）：%d 项写进运行时 cfg（config.json 未动）",
        tostring(why), n))
      diag_flush()
    end
    S.apply_n = n
    return n
  end
  -- 设置重读（默认 5 秒一次）会把 cfg 覆盖回文件值 → 把面板上的值再压回去。
  -- 这就是「容器守卫」：面板的值必须一直压得住 TEFManager 的重读。
  local function overlay_guard()
    if next(GOV) == nil then return end
    if S.reloads_seen ~= cfg_stat.reloads then
      S.reloads_seen = cfg_stat.reloads
      apply_overlay("配置重读")
      return
    end
    for k, v in pairs(GOV) do
      if cfg[k] ~= v then apply_overlay("对账") return end
    end
  end
  local function clear_overlay(why)
    GOV = {}
    gov_count()
    S.force_save = true
    S.op_last = tostring(why or "覆盖层已清空")
  end

  -- ================================================================ 状态文件
  -- worldforge-gui.txt：**原地兼容读旧状态**（键名一个都没改，只是新增了 sel=）。
  local function gov_load(k, rawv)
    local d = DEFAULTS[k]
    if d == nil then return end
    if type(d) == "boolean" then
      if rawv == "true" then GOV[k] = true elseif rawv == "false" then GOV[k] = false end
    elseif type(d) == "number" then
      local n = tonumber(rawv)
      if n then
        local lim = LIMITS[k]
        n = math.floor(n)
        if lim then
          if n < lim[1] then n = lim[1] end
          if n > lim[2] then n = lim[2] end
        end
        GOV[k] = n
      end
    end
  end
  local function clamp_pos(x, y) return clamp_iv(x, 0, POS_MAX_X), clamp_iv(y, 0, POS_MAX_Y) end
  local function save_state()
    if type(mod.write_file) ~= "function" then return false end
    local wx, wy = clamp_pos(S.win_x, S.win_y)
    -- ★ v10.3：折叠状态落盘（记组号，比中文组名稳；gn 对不上就忽略旧记录）
    local op = {}
    for i = 1, #IDX.groups do if S.gopen[IDX.groups[i]] then op[#op + 1] = i end end
    local t = {
      "v=" .. VERSION,
      "gn=" .. tostring(#IDX.groups),
      "gopen=" .. table.concat(op, ","),
      "page=" .. tostring(S.page),
      "tab=" .. tostring(S.tab),
      "dom_page=" .. tostring(S.dom_page),
      "dom_bad=" .. (S.dom_bad_only and "1" or "0"),
      "only_diff=" .. (S.only_diff and "1" or "0"),
      "os_tab=" .. tostring(S.os_tab),
      "grp=" .. tostring(S.grp),
      "sel=" .. tostring(S.sel or ""),
      "win_w=" .. tostring(clamp_iv(S.win_w, WIN_W_MIN, WIN_W_MAX)),
      "wx=" .. tostring(S.pos_valid and wx or -1),
      "wy=" .. tostring(S.pos_valid and wy or -1),
    }
    for k, v in pairs(GOV) do
      local d = DEFAULTS[k]
      if type(d) == "boolean" then
        t[#t + 1] = "gov." .. k .. "=" .. (v and "true" or "false")
      elseif type(d) == "number" then
        t[#t + 1] = "gov." .. k .. "=" .. tostring(math.floor(v))
      end
    end
    table.sort(t)
    local okw, err = pcall(mod.write_file, STATE_FILE, table.concat(t, NL))
    if not okw then
      if type(mod.warn) == "function" then mod.warn("世界工坊 GUI：状态写入失败：" .. tostring(err)) end
      return false
    end
    return true
  end
  local function load_state()
    if type(mod.read_file) ~= "function" then return false end
    local okr, raw = pcall(mod.read_file, STATE_FILE)
    if not okr or type(raw) ~= "string" or raw == "" then return false end
    local function rnum(key)
      local v = raw:match(key .. "=(-?%d+)")
      return v and tonumber(v) or nil
    end
    local p = rnum("page")     if p and p >= 1 and p <= #PAGES then S.page = p end
    local tb = rnum("tab")     if tb and tb >= 1 and tb <= 2 then S.tab = tb end
    local dp = rnum("dom_page") if dp and dp >= 1 then S.dom_page = dp end
    local grp = rnum("grp")    if grp and grp >= 1 then S.grp = grp end
    -- ★ v10.3：折叠状态（gopen=组号,组号）。分组数变了（gn 对不上）就忽略旧记录，
    --   回到「只展开第 1 组」的默认，免得把展开状态套到别的组上。
    local gn = rnum("gn")
    local go = raw:match("gopen=([^\n]*)")
    if go and (gn == nil or gn == #IDX.groups) then
      S.gopen, S.gopen_loaded = {}, true
      for n in go:gmatch("%d+") do
        local gi = tonumber(n)
        if gi and gi >= 1 and gi <= #IDX.groups then S.gopen[IDX.groups[gi]] = true end
      end
    end
    local w = rnum("win_w")    if w then S.win_w = clamp_iv(w, WIN_W_MIN, WIN_W_MAX) end
    local ot = rnum("os_tab")  if ot and ot >= 1 then S.os_tab = ot end
    if raw:match("dom_bad=1")   then S.dom_bad_only = true end
    if raw:match("only_diff=1") then S.only_diff = true end
    local sl = raw:match("sel=([^\n]*)")
    if sl and sl ~= "" then S.sel = sl end
    local wx, wy = rnum("wx"), rnum("wy")
    if wx and wy and wx >= 0 and wy >= 0 then
      local cx, cy = clamp_pos(wx, wy)
      if (cx ~= wx or cy ~= wy) and type(mod.warn) == "function" then
        mod.warn(string.format("世界工坊 GUI：上次记录的窗口位置在屏幕外，已回落到 (%d, %d)", cx, cy))
      end
      S.win_x, S.win_y, S.pos_valid = cx, cy, true
    end
    for line in (raw .. NL):gmatch("([^\n]*)\n") do
      local k, v = line:match("^gov%.([%w_]+)=(.*)$")
      if k then gov_load(k, v) end
    end
    gov_count()
    return true
  end

  -- ================================================================ 日志
  local function cut_line(s) return trunc(s, 54) end
  local function read_log_tail()
    S.log_at = S.frames
    if type(mod.read_file) ~= "function" then S.log_err = "(没有 mod.read_file)" return end
    local ok, raw = pcall(mod.read_file, LOG_FILE)
    if not ok or type(raw) ~= "string" or raw == "" then
      S.log_lines = {}
      S.log_n = 0
      S.log_err = "(无日志：write_log 关着时模组不落盘)"
      return
    end
    local all = {}
    for line in (raw .. NL):gmatch("([^\n]*)\n") do
      if line ~= "" then all[#all + 1] = line end
    end
    local out = {}
    local first = #all - 16 + 1
    if first < 1 then first = 1 end
    for i = first, #all do out[#out + 1] = SX(cut_line(all[i])) end
    S.log_lines = out
    S.log_n = #all
    S.log_err = string.format("共 %d 行", #all)
  end

  -- ================================================================ 一键操作
  -- 全部是模组自己已有的公开函数：self_check_report / report_stats / report /
  -- probe_capabilities / rehash_world_state / restore_world / undo_restore /
  -- build_plans / WGCTL / ONESHOT —— 一个都不许猜名字（都是 main.lua 里真实存在的）。
  local function run_op(name)
    local ops = {
      self_check = function() self_check_report() return "自检结果已发到聊天栏与日志" end,
      replan     = function()
        local n = apply_overlay("重新应用")
        return string.format("已重新应用设置（本次改动 %d 项）", n)
      end,
      restore    = function() restore_world() return "已把本模组改过的世界参数还原回原版" end,
      undo       = function()
        undo_restore(UNDO_KEYS)
        return "已按原版值回退本模组写过的全局数据"
      end,
      clear_gov  = function()
        clear_overlay("面板里的参数改动已全部清空")
        apply_overlay("清空面板改动")
        return S.op_last
      end,
      wgen_stat  = function()
        if type(WGCTL) ~= "table" or type(WGCTL.status) ~= "function" then return "地图生成专项未启用" end
        return tostring(WGCTL.status())
      end,
      wgen_stop  = function()
        if type(WGCTL) ~= "table" or type(WGCTL.cancel) ~= "function" then return "地图生成专项未启用" end
        if WGCTL.cancel() then return "已取消（已改的部分不回滚）" end
        return "当前没有进行中的任务"
      end,
    }
    local fn = ops[name]
    if not fn then return "未知操作" end
    S.op_n = S.op_n + 1
    local ok, r = pcall(fn)
    if not ok then return "执行出错：" .. tostring(r) end
    return SX(tostring(r))
  end

  -- ================================================================ 屏幕探测
  -- 零游戏符号（§3.2）：加载器每帧把窗口坐标夹进 [0, screen - 32*g_scale]，
  -- 所以「请求超大坐标 → 下一帧 get_pos 读回上界」；再由
  -- g_scale = clamp(min(screen_w,screen_h)/720, 1, 2.5) 得 g = min(x上界,y上界)/688，
  -- 可用内容高 = y上界 - 24*g。真机读数：g=1.0、y上界=404、屏幕≈436、可用 380 px。
  -- ★ 第 1 帧绝不调 set_pos：1.9.0 起首次 set_pos 会被 gui_layout.json 的记录覆盖
  --   （陷阱 11），那时读回的是「用户上次拖到的位置」而不是夹取上界。
  local function probe_step()
    local PR = S.probe
    if S.frames < 2 or PR.done then return end
    if PR.phase == 0 then
      local okp, px, py = api("get_pos")
      if okp and type(px) == "number" then PR.saved_x, PR.saved_y = px, num(py, PR.saved_y) end
      api("set_pos", BIG, 0)
      PR.phase = 1
    elseif PR.phase == 1 then
      local ok, x = api("get_pos")
      PR.x_max = (ok and type(x) == "number") and x or 0
      api("set_pos", 0, BIG)
      PR.phase = 2
    else
      local ok, _x, y = api("get_pos")
      PR.y_max = (ok and type(y) == "number") and y or 0
      if PR.x_max > 20000 or PR.y_max > 20000 then
        PR.unclamped = true
        mod.info("世界工坊 GUI：本加载器不夹取窗口坐标，屏幕探测不可用（面板按 g_scale=1 / 可用 380 px 保守排版）")
      else
        local mn = math.min(PR.x_max, PR.y_max)
        local g = mn / 688.0
        if g < 1.0 then g = 1.0 end
        if g > 2.5 then g = 2.5 end
        PR.s = g
        PR.screen_w = PR.x_max + 32.0 * g
        PR.screen_h = PR.y_max + 32.0 * g
        S.g = g
        S.budget = PR.y_max - 24.0 * g
        mod.info(string.format(
          "世界工坊 GUI：屏幕探测 x上界=%.0f y上界=%.0f g_scale=%.2f 屏幕≈%.0fx%.0f 可用内容高=%.0f px",
          PR.x_max, PR.y_max, g, PR.screen_w, PR.screen_h, S.budget))
      end
      PR.phase = 3
      PR.done = true
      S.win_x, S.win_y = PR.saved_x, PR.saved_y
      S.pos_applied = false
      S.width_applied = -1               -- g_scale 变了 → 宽度按新比例再写一次
    end
  end

  -- 本机单位 = 基础单位 × g_scale。窗口宽度也按 g_scale 缩放，否则 g 大的手机上
  -- 内容会横向溢出。
  local function win_w_applied()
    local w = math.floor(U(clamp_iv(S.win_w, WIN_W_MIN, WIN_W_MAX)) + 0.5)
    local sw = (S.probe.done and not S.probe.unclamped) and S.probe.screen_w or 0
    if sw > 0 and w > sw * 0.97 then w = math.floor(sw * 0.97) end
    if w < 120 then w = 120 end
    return w
  end
  -- 内容宽 = 窗宽 - 2*pad（加载器里 pad = 12*g_scale，源 gui.cpp:1151）
  local function body_w() return win_w_applied() - U(24) end

  local function apply_geometry()
    local w = win_w_applied()
    if S.width_applied ~= w then
      api("set_width", w)
      S.width_applied = w
    end
    if not S.pos_applied then
      -- ★ 自己先夹一次：坏坐标一旦写进自己的状态文件，在旧加载器上就是
      --   「重启也抓不回来」（§6.2）。写回去之前也要夹。
      local x, y = clamp_pos(S.win_x, S.win_y)
      local win_h = avail() + U(56)          -- th + pad + 内容高 + pad
      local sh = (S.probe.done and not S.probe.unclamped) and S.probe.screen_h or 0
      if sh > 0 and y + win_h > sh then
        y = math.floor(sh - win_h)
        if y < 0 then y = 0 end
      end
      if api("set_pos", x, y) then
        S.pos_applied = true
        S.pos_valid = true
      end
    end
  end
  local function apply_theme()
    -- 只有这 7 个键（§5）；text 键在 1.9.0 起也管按钮/复选框/进度条/折叠头/输入框
    if has("set_style") then
      pcall(G.set_style, { panel = C.panel, title = C.title, button = C.button,
                           hover = C.hover, active = C.active, border = C.border, text = C.text })
    end
  end
  local function apply_title()
    -- 收起方块画的是 skin_icon（图片）；文字图标只当图片没解码完时的兜底
    -- ★ v10.4：窗口标题栏偶尔缺字（加载器侧绘制问题，多个模组都这样）。
    --   这里只留短标题；完整版本号在第一行正文里（page_head）。
    api("set_title", "世界工坊", IMG.glyph and "工" or "WF")
  end
  local function apply_skin()
    -- ★ set_skin 参数任一不合法（border<=0 / iconSize 不在 24~128 / 两个 id 不属于自己）
    --   → **整次调用被静默忽略**（陷阱 19），所以要自己判一遍参数。
    if not has("set_skin") or not IMG.panel or not IMG.glyph then return end
    local size = math.floor(U(40))
    if size < 24 then size = 24 end
    if size > 128 then size = 128 end
    pcall(G.set_skin, IMG.panel, 16, IMG.glyph, size, math.floor(U(10)))
  end

  -- ================================================================ 版面常量
  -- 全部是「基础单位」，乘 S.g 之后才是像素。头部拆两行（18 章 §3 的坑：
  -- 一行太长会被自己的 fit() 截断，把视口高这种关键读数截掉）。
  -- ★ v10.1：NAVH / CTLH 从 22 提到 30 —— 加载器 line_height() = 28*g_scale，而 image_button 的
  --   文字是垂直居中于按钮矩形的：按钮高 < 行高时文字会画到矩形之外（真机反馈：标签页与工具按钮
  --   的字偏上、在滚动视口最上沿还会整行被隐藏）。BODY0 相应下移到 100（控制行 66..96）。
  local HDR1, HDR2, NAVY, NAVH, CTLY, CTLH, BODY0 = 0, 17, 34, 30, 66, 30, 100

  local function page_head(bw, extra)
    local head = "世界工坊 v" .. VERSION
    if cfg.enabled == false then head = head .. "   （总开关已关，功能已停手）" end
    D.text(0, U(HDR1), SX(head), C.accent, 0.62, bw)
    local sub = extra
    if sub == nil or sub == "" then sub = "点上面的标签切页；参数与开关改完立刻生效" end
    D.text(0, U(HDR2), SX(sub), C.muted, 0.55, bw)
    local gap = U(4)
    local nw = math.floor((bw - gap * (#PAGES - 1)) / #PAGES)
    if nw < U(40) then nw = U(40) end
    for i = 1, #PAGES do
      local bx = (i - 1) * (nw + gap)
      if D.ibtn(bskin(), bx, U(NAVY), nw, U(NAVH), PAGES[i], 12) then
        if S.page ~= i then S.num_key, S.num_buf = nil, "" end
        S.page = i
        S.force_save = true
        -- ★ v10.2：切页回到该页列表顶部（1.9.0 的 scroll_to）
        if has("scroll_to") then
          local sid = ({ "wf_status", "wf_params", "wf_os", "wf_ops", "wf_about" })[i]
          if sid then pcall(G.scroll_to, sid, 0, 0) end
        end
      end
      if i == S.page then D.fill(bx, U(NAVY + NAVH - 3), nw, U(2), C.accent) end
    end
  end

  -- 一页的几何：头部两行 + 页签 + 控制行 + 底部工具条，剩下全是滚动视口。
  -- 屏幕太矮时先把工具条丢掉，再不够就把视口压到最小高（并把警告写进自查行）。
  local function page_geo(ctl_h, dock_h)
    local a = avail()
    local top = U(BODY0) + U(num(ctl_h, 0))
    local dh = U(num(dock_h, 0))
    -- 固定部分的基础单位总高：头部 + 控制行 + 工具条 + 最小视口（check_line 用它判要不要告警）
    local fixed = BODY0 + num(ctl_h, 0) + num(dock_h, 0) + 56
    local bh = a - top - dh
    local dropped = false
    if bh < U(56) and dh > 0 then
      -- ★ 可用内容高不够：先丢掉页脚工具条，把那一行让给高度告警（见 check_line）。
      dropped = true
      dh = 0
      bh = a - top - U(13)
    end
    local tight = false
    if bh < U(44) then
      bh = U(44)
      tight = true
    end
    return top, bh, dh, tight, dropped, fixed
  end

  -- 「每帧几何自查」那一行（抄 16 章 §3 的做法：把自己的估算高与可用高都印出来）
  -- 1.9.0 的说法：窗口内容高恒等于可用内容高（长内容进滚动容器），所以这里说的是
  -- 「固定部分（头部 + 控制行 + 工具条 + 最小视口）放不下」→ 页脚工具条已被省掉。
  -- ★ 保留「超出屏幕」四个字：真机实测过的告警文案，玩家看得懂。
  local function check_line(y, bw, fixed_base, extra)
    local a = avail()
    local over = U(fixed_base) > a + 0.5
    local s = string.format("固定占 %d px / 可用 %.0f px%s%s", math.floor(U(fixed_base)), a,
      over and "   !! 超出屏幕：固定部分放不下，页脚工具条已省掉（其余内容在滚动容器里）" or "",
      extra and ("   " .. extra) or "")
    D.text(0, y, s, over and C.warn or C.muted, 0.5, bw)
    return y + U(13)
  end

  -- ================================================================ 一键操作数据
  -- 全部来自 87_oneshot 分片导出的共享表 ONESHOT（本分片一次 patch.* 都不发）：
  --   ONESHOT.groups = { { id, name, head = 行表?, rows = 行表 }, ... }
  --   一行 = { { id, label }, ... }；label 可以是函数（每帧取动态文字）；
  --   只有 label 没有 id = 纯文字；带 slider = <设置项 key> = 直接给一行滑块。
  local function os_groups()
    if type(ONESHOT) ~= "table" then return nil end
    local g = ONESHOT.groups
    if type(g) ~= "table" or #g == 0 then return nil end
    return g
  end
  local function os_label(it)
    local l = it.label
    if type(l) == "function" then
      local ok, v = pcall(l)
      if ok then return SX(tostring(v)) end
      return "!! 取文字失败"
    end
    return SX(tostring(l or "?"))
  end
  local function os_call(id)
    if type(ONESHOT) ~= "table" or type(ONESHOT.run) ~= "function" then
      return "一键操作未启用（87 分片没装上）"
    end
    local ok, r = pcall(ONESHOT.run, id)
    if not ok then return "执行出错：" .. tostring(r) end
    return SX(tostring(r))
  end
  -- 带 slider 的行：直接调参数页那一项的真滑块（只改运行时覆盖层）
  -- ★ v10.4：一键页也不再给滑块 —— 点一下直接跳去参数页的数字键盘
  local function os_num_btn(key, x, y, w, h)
    local e = IDX.by_key[key]
    if not e or e.kind ~= "int" then return end
    local cur = math.floor(num(cur_of(e.key), e.lo))
    if D.ibtn(bskin(), x, y, w, h, e.name .. "：" .. tostring(cur), 10) then
      S.num_key, S.num_buf, S.num_msg = key, tostring(cur), ""
      S.sel = key
      S.page = 2
      S.force_save = true
      if has("scroll_to") then pcall(G.scroll_to, "wf_params", 0, 0) end
    end
  end
  -- ★ v10.3：一键页的危险动作（不可逆或大量改写世界）→ 二次确认
  local OS_DANGER = {
    e_hardmode = true, f_all = true, f_go = true, p_items = true, p_enemies = true,
  }
  local function os_trigger(id, lbl)
    if OS_DANGER[id] then
      S.os_confirm = { id = id, label = lbl }
      S.op_last = "危险操作「" .. lbl .. "」：请再点一次确定"
      S.force_save = true
      if has("scroll_to") then pcall(G.scroll_to, "wf_os", 0, 0) end
    else
      S.op_last = os_call(id)
      S.force_save = true
    end
  end
  -- 头部控制条（类型 / 个数 / 滑块）：一行一个真控件（不改布局，保持紧凑）
  local function os_item(it, x, y, w, h)
    if type(it) ~= "table" then return end
    if it.slider then
      os_num_btn(it.slider, x, y, w, h)
      return
    end
    local lbl = os_label(it)
    if it.id then
      if D.ibtn(bskin(), x, y, w, h, lbl, 12) then os_trigger(it.id, lbl) end
    else
      D.text(x + U(4), y + U(4), lbl, C.muted, 0.55, w - U(8))
    end
  end
  -- ★ v10.4（实机反馈）：「图 + 文字」两行原来是两个按钮（上图片、下文字），
  --   功能完全一样、纯冗余。现在只保留一个 image_button，文字直接画在按钮里。
  local TILE_H = 38
  local function os_tile(it, x, y, w)
    if type(it) ~= "table" then return end
    if it.slider then
      os_num_btn(it.slider, x, y, w, U(34))
      return
    end
    local lbl = os_label(it)
    if it.id then
      if OS_DANGER[it.id] then
        D.fill(x + w - U(9), y + U(2), U(6), U(6), C.warn)
      end
      if D.ibtn(bskin(), x, y, w, U(34), lbl, 12) then os_trigger(it.id, lbl) end
    else
      D.text(x + U(4), y + U(9), lbl, C.muted, 0.55, w - U(8))
    end
  end

  -- ================================================================ 各页
  -- 约定：页面函数只负责画内容，返回 nil；窗口高度由 frame_body 统一钉死。
  local PG = {}

  -- ================================================================ 状态页
  -- ★ v10.2：整页改成玩家看得懂的话 —— 不再印钩子数量、调用次数、命中次数、技术明细表。
  local function active_names()
    local t = {}
    local function add(ok, name) if ok then t[#t + 1] = name end end
    add(P.world and P.world.active, "世界与天气")
    add(P.world and (P.world.spread_block or P.world.spread_force or P.world.spread_rate_on),
        "生物群系蔓延")
    add(P.lightning and P.lightning.active, "雷击")
    add(P.events and P.events.active, "事件与月亮事件")
    add(P.spawn and P.spawn.filter, "刷怪规则")
    add(P.spawnq and P.spawnq.active, "刷怪质量与上限")
    add(P.attr and P.attr.active, "生物属性")
    add(P.rare and P.rare.active, "稀有生物")
    add(P.house and P.house.active, "住房")
    add(P.pylon and P.pylon.active, "晶塔")
    add(P.tree and P.tree.active, "树木")
    add(P.angler and P.angler.active, "渔夫")
    add(P.fish and P.fish.active, "任务鱼堆叠")
    add(P.death and P.death.active, "复活与墓碑")
    add(P.station and P.station.active, "制作站")
    add(P.gen and P.gen.active, "陨石与世纪之花")
    add(P.shimmer and P.shimmer.active, "微光嬗变")
    add(P.liquid and P.liquid.on, "液体世界")
    add(P.liquid and P.liquid.freeze, "冻结液体")
    add(P.misc and P.misc.active, "世界边缘与重力")
    add(P.shop and P.shop.active, "商店售价")
    add(P.starfall and P.starfall.active, "坠落之星")
    add(P.wgen and P.wgen.active, "地图生成")
    return t
  end

  -- 地图生成进度（0~1）＋一行说明；没有任务时返回 nil
  local function gen_progress()
    if type(WGCTL) ~= "table" or type(WGCTL.progress) ~= "function" then return nil end
    local ok, v = pcall(WGCTL.progress)
    if not ok or type(v) ~= "number" then return nil end
    local oks, st = pcall(WGCTL.status)
    return v, (oks and tostring(st) or "正在生成特征")
  end

  -- 状态页：一句话结论 + 已开启的功能 + 上次操作；长内容全在滚动视口里
  PG.status = function(bw)
    local top, bh, dh, tight, dropped, fixed = page_geo(0, 74)
    local L = {}
    local function Ln(t, c, s) L[#L + 1] = { t = t, c = c or C.text, s = s or 0.55 } end
    local on = (cfg.enabled ~= false)
    Ln(on and "模组总开关：开" or "模组总开关：关（所有功能都已停手）",
       on and C.ok or C.warn, 0.62)
    local names = active_names()
    if #names == 0 then
      Ln("当前没有任何功能被改动，全部是原版行为。", C.muted)
    else
      Ln(string.format("已开启 %d 类功能：", #names), C.accent)
      local line = ""
      for i = 1, #names do
        if line == "" then line = names[i] else line = line .. "、" .. names[i] end
        if units(line) >= 24 then Ln("  " .. line) line = "" end
      end
      if line ~= "" then Ln("  " .. line) end
    end
    local prog, ptext = gen_progress()
    if prog then Ln("地图生成：" .. trunc(ptext, 46), C.gold) end
    if GOV_N > 0 then
      Ln(string.format("你在本面板里改过 %d 项参数（只在本次游戏里有效，设置文件没有被改动）",
         GOV_N), C.gold)
    else
      Ln("你在本面板里还没有改过参数。", C.muted)
    end
    if S.fold1 then
      Ln("这块面板怎么用：", C.accent, 0.58)
      Ln("  - 参数页：按分组折叠，点组名展开；里面的滑块与开关改完立刻生效。")
      Ln("  - 一键页：点一下马上执行（事件 / 生成特征 / 玩家状态 / 雷击 / 娱乐）。")
      Ln("  - 工具页：把世界还原回原版、撤销本模组的改动、取消正在跑的生成功。")
      Ln("  - 想让改动长期保留：请到模组的设置界面里改这一项，面板只改这一次游戏里的值。")
    end
    local need = #L * U(15) + U(84)
    local ch = (need > bh) and need or bh
    local sx, sy, vw, vh = SB("wf_status", 0, top, bw, bh, bw, ch)
    local yy = 0
    for i = 1, #L do
      if in_view(yy, 15, bh) then D.text(U(2), yy, L[i].t, L[i].c, L[i].s, bw - U(8)) end
      yy = yy + U(15)
    end
    yy = yy + U(4)
    local bx = 0
    if in_view(yy, 30, bh) and D.ibtn(bskin(), bx, yy, U(88), U(30), "保存面板状态", 10) then
      S.force_save = true
      S.op_last = "面板状态已保存"
    end
    bx = bx + U(92)
    if in_view(yy, 30, bh) and D.ibtn(bskin(), bx, yy, U(76), U(30), "重新应用", 10) then
      S.op_last = run_op("replan")
    end
    bx = bx + U(80)
    if in_view(yy, 30, bh) and D.ibtn(bskin(), bx, yy, U(80), U(30), "回到顶部", 10) then
      if has("scroll_to") then pcall(G.scroll_to, "wf_status", 0, 0) end
    end
    yy = yy + U(34)
    if in_view(yy, 15, bh) then
      D.text(U(2), yy, "上次操作：" .. trunc(S.op_last, 46), C.muted, 0.5, bw - U(8))
    end
    yy = yy + U(15)
    D.text(U(2), yy, string.format("本页 %d px / 可用 %.0f px   视口 %d px（内容在滚动容器里，不占窗口高度）",
      math.floor(U(BODY0 + 74)), avail(), math.floor(bh)), tight and C.warn or C.muted, 0.5, bw - U(8))
    SE()
    if dh > 0 then
      SB("wf_status_dock", 0, avail() - dh, bw, dh, bw, dh)
      local p2 = gen_progress()
      if p2 then
        cursor(U(2), U(0))
        FW.bar(p2)
      end
      cursor(U(2), U(30))
      S.fold1 = FW.fold("面板说明 / 怎么用（点开）")
      SE()
    elseif dropped then
      check_line(avail() - U(14), bw, fixed)
    end
  end

  -- 参数页：从 DEFAULTS / LIMITS / CHOICES / KEY_META 自动生成
  -- ★★ v10.2：改成「折叠分组」★★
  --   一屏把所有分组按名字列出来，点一下展开该组的滑块 / 开关，再点一下收起；多个组可以同时
  --   展开。旧版是「< 组 / 组 >」一页一组，设置一多就得来回翻页找。
  local function param_rows()
    local rows = {}
    local FR = filter_result()
    for gi = 1, #FR.order do
      local gname = FR.order[gi]
      local list = FR.by_group[gname] or {}
      if #list > 0 then
        rows[#rows + 1] = { kind = "group", gi = gi, name = gname, n = #list }
        if group_open(gname) then
          for i = 1, #list do rows[#rows + 1] = { kind = "item", e = list[i] } end
        end
      end
    end
    return rows
  end

  -- ---------------------------------------------------------------- 数字键盘（v10.4）
  -- 照 项目/playerforge：点「值」后**整页**换成编辑页（不叠层、不压暗、不与参数行重叠），
  -- 3 列 x 4 行自绘数字键盘 + 清空 / 默认 / 确定 / 取消。不依赖系统输入法。
  local function num_commit(e)
    local n = tonumber(S.num_buf)
    if n == nil or n ~= n then
      S.num_msg = "输入不是数字，保持原值"
    elseif e.lo >= 0 and n < 0 then
      S.num_msg = "这一项不能是负数，保持原值"
    else
      n = math.floor(n)
      GOV[e.key] = n            -- ★ 确定时不夹取范围（16 章 §2.6），0 也能写
      gov_count()
      S.changed, S.sel = true, e.key
      S.force_save = true
      S.num_msg = string.format("已写入 %d（面板不夹取范围）", n)
    end
    S.num_key, S.num_buf = nil, ""
  end
  local function draw_num_editor(bw)
    local e = IDX.by_key[S.num_key]
    if not e then S.num_key = nil return end
    local ey = U(BODY0)
    local bottom = avail() - U(4)
    if bottom - ey < U(140) then bottom = ey + U(140) end
    D.fill(0, ey, bw, bottom - ey, C.row_a)
    D.text(U(4), ey + U(2), "输入「" .. trunc(e.full, 24) .. "」", C.accent, 0.56, bw - U(8))
    local cur = math.floor(num(cur_of(e.key), 0))
    D.text(U(4), ey + U(18), string.format("当前 %d；范围 %d ~ %d（只提示，确定时不夹取）",
      cur, e.lo, e.hi), C.muted, 0.45, bw - U(8))
    local box_y = ey + U(32)
    D.fill(U(2), box_y, bw - U(4), U(34), C.row_b)
    D.fill(U(2), box_y, U(3), U(34), C.accent)
    local shown = S.num_buf or ""
    if shown == "" then
      D.text(U(10), box_y + U(9), "点下面的数字键输入（0 也可以）", C.muted, 0.55, bw - U(16))
    else
      D.text(U(10), box_y + U(2), shown, C.text, 0.9, bw - U(16))
    end
    local act_h = U(30)
    local act_y = bottom - act_h
    local key_top = box_y + U(40)
    local gap = U(4)
    local kh = math.floor((act_y - U(6) - key_top - gap * 3) / 4)
    if kh < U(14) then kh = U(14) end
    if kh > U(34) then kh = U(34) end
    local kw = math.floor((bw - gap * 2) / 3)
    local neg = (e.lo < 0)
    local keys = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
                   { neg and "+/-" or "清零", "0", "退格" } }
    for ri = 1, 4 do
      for ci = 1, 3 do
        local k = keys[ri][ci]
        if D.ibtn(bskin(), (ci - 1) * (kw + gap), key_top + (ri - 1) * (kh + gap), kw, kh, k, 10) then
          if k == "退格" then
            S.num_buf = tostring(S.num_buf or ""):sub(1, -2)
          elseif k == "+/-" then
            local b = tostring(S.num_buf or "")
            if b:sub(1, 1) == "-" then S.num_buf = b:sub(2) else S.num_buf = "-" .. b end
          elseif k == "清零" then
            S.num_buf = "0"
          else
            local b = tostring(S.num_buf or "")
            if #b < 12 then S.num_buf = b .. k end
          end
        end
      end
    end
    local labels = { "清空", "默认", "确定", "取消" }
    local aw = math.floor((bw - gap * 3) / 4)
    for i = 1, 4 do
      if D.ibtn(bskin(), (i - 1) * (aw + gap), act_y, aw, act_h, labels[i], 10) then
        if labels[i] == "清空" then
          S.num_buf = ""
        elseif labels[i] == "默认" then
          reset_one(e)
          S.num_key, S.num_buf = nil, ""
          S.num_msg = "已恢复默认值"
        elseif labels[i] == "确定" then
          num_commit(e)
        else
          S.num_key, S.num_buf = nil, ""
          S.num_msg = "已取消，保持原值"
        end
      end
    end
  end

  PG.params = function(bw)
    build_index()
    local FR = filter_result()
    local total_n = #IDX.groups
    if total_n == 0 then
      D.text(0, U(BODY0), "读不到设置表：本页从设置表自动生成控件", C.warn, 0.6, bw)
      return
    end
    local editing = (S.num_key ~= nil and IDX.by_key[S.num_key] ~= nil)
    if S.num_key ~= nil and not editing then S.num_key, S.num_buf = nil, "" end
    if editing then
      draw_num_editor(bw)
      return
    end
    local top, bh, dh, tight, dropped, fixed = page_geo(68, 62)
    local rows = param_rows()
    local vis_n = #FR.order
    local open_n = 0
    for gi = 1, vis_n do if group_open(FR.order[gi]) then open_n = open_n + 1 end end

    -- ★ v10.3 控制行 A：检索框 + 清空 + 折叠（流式控件先开视口，不能推走根光标）
    --   版面预算：两行控制条（68）与 v10.2 相同 → 参数列表的可视高度不被检索框吃掉
    local by = U(CTLY)
    local bx_c = bw - U(74)            -- 清空检索
    local bx_o = bx_c - U(76)          -- 全部展开
    local bx_s = bx_o - U(76)          -- 全部收起
    local sw = bx_s - U(4)
    if sw > U(80) then
      SB("wf_search", 0, by, sw, U(CTLH), sw, U(CTLH))
      cursor(U(4), U(2))
      -- ★ 输入框初值必须是 ASCII（del 是 pop_back() 删 1 字节，中文初值会留下非法 UTF-8，
      --   §1.3 第 20 条）。检索串可能是中文（注入 / 将来的输入法）→ 框里留空，
      --   真正的检索串画在下面工具条里，清空请点「清空检索」。
      local disp = S.filter or ""
      if disp:find("[\128-\255]") then disp = "" end
      local nf = FW.input("检索 分组或标题", disp)
      SE()
      if nf ~= disp then
        S.filter = nf
        S.force_save = true
        if has("scroll_to") then pcall(G.scroll_to, "wf_params", 0, 0) end
      end
    end
    if D.ibtn(bskin(), bx_s, by, U(72), U(CTLH), "全部收起", 10) then
      S.gopen = {}
      S.force_save = true
    end
    if D.ibtn(bskin(), bx_o, by, U(72), U(CTLH), "全部展开", 10) then
      S.gopen = {}
      for gi = 1, vis_n do S.gopen[FR.order[gi]] = true end
      S.force_save = true
    end
    if D.ibtn(bskin(), bx_c, by, U(74), U(CTLH), "清空检索", 10) then
      if S.filter ~= "" then
        S.filter = ""
        S.force_save = true
        if has("scroll_to") then pcall(G.scroll_to, "wf_params", 0, 0) end
      end
    end
    -- 控制行 B：筛选 / 落盘 / 回默认 / 回到顶部
    local by2 = by + U(34)
    if D.ibtn(bskin(), 0, by2, U(80), U(CTLH),
              S.only_diff and "[只看已改]" or "只看已改", 10) then
      S.only_diff = not S.only_diff
      S.force_save = true
      if has("scroll_to") then pcall(G.scroll_to, "wf_params", 0, 0) end
    end
    if D.ibtn(bskin(), U(84), by2, U(76), U(CTLH), "保存状态", 10) then
      S.force_save = true
      S.op_last = "面板状态已保存"
    end
    if D.ibtn(bskin(), U(164), by2, U(88), U(CTLH), "全部回默认", 10) then
      clear_overlay("参数已全部回默认")
      apply_overlay("全部回默认")
      S.op_last = "所有参数已恢复默认值"
    end
    if D.ibtn(bskin(), U(256), by2, U(64), U(CTLH), "回到顶部", 10) then
      if has("scroll_to") then pcall(G.scroll_to, "wf_params", 0, 0) end
    end

    -- 行高表（基础单位）：分组头 38 / bool 64 / int 66 / choice 66 / str 30
    local nrow = #rows
    local py, ph = {}, {}
    local yy = 0
    for i = 1, nrow do
      local r = rows[i]
      local h = 30
      if r.kind == "group" then
        h = 38
      else
        local k = r.e.kind
        if k == "bool" then h = 64
        elseif k == "int" then h = 66
        elseif k == "choice" then h = 66 end
      end
      py[i] = yy
      ph[i] = h
      yy = yy + U(h)
    end
    local ch = (yy + U(4) > bh) and yy + U(4) or bh
    local sx, sy, vw, vh = SB("wf_params", 0, top, bw, bh, bw, ch)
    local first = first_row(py, ph, nrow, sy)
    for i = first, nrow do
      if py[i] > sy + vh then break end
      local r = rows[i]
      local ry = py[i] + U(2)
      if r.kind == "group" then
        local bucket = IDX.by_group[r.name] or {}
        local dim = 0
        for kk = 1, #bucket do if is_diff(bucket[kk].key) then dim = dim + 1 end end
        -- ★ 组名就是按钮标签（不带动态数字）—— 标签稳定，点起来才可靠；
        --   「N 项 / 已改 M 项」画在按钮右边（自绘文本，画在按钮之后 = 盖在它上面）
        local opn = group_open(r.name)
        local label = (opn and "[-] " or "[+] ") .. r.name
        D.fill(0, ry, bw - U(6), U(ph[i]) - U(4), C.row_b)
        if D.ibtn(bskin(), 0, ry + U(3), bw - U(10), U(30), label, 10) then
          if (S.filter or "") ~= "" then
            S.filter = ""                      -- 检索态下点组头 = 先退出检索，再折叠
            S.force_save = true
          end
          if S.gopen[r.name] then S.gopen[r.name] = nil else S.gopen[r.name] = true end
          S.force_save = true
        end
        local hint = tostring(r.n) .. " 项"
        if dim > 0 then hint = hint .. "，已改 " .. tostring(dim) .. " 项" end
        D.text(bw - U(160), ry + U(10), hint,
          dim > 0 and C.accent or C.muted, 0.45, U(150))
      else
        local e = r.e
        D.fill(0, ry, bw - U(6), U(ph[i]) - U(4),
          is_diff(e.key) and C.diff or (i % 2 == 0 and C.row_a or C.row_b))
        local tool_y = ry + ((e.kind == "int") and U(36) or U(34))
        if is_diff(e.key) then
          if D.ibtn(bskin(), bw - U(60), tool_y, U(56), U(30), "复位", 8) then reset_one(e) end
        end
        if e.kind == "bool" then
          cursor(U(6), ry + U(3))
          local cur = cur_of(e.key) == true
          local nv = cur
          if type(G.checkbox) == "function" then nv = G.checkbox(e.name, cur) end
          if nv ~= cur then set_val(e, nv == true) S.changed = true S.sel = e.key end
        elseif e.kind == "int" then
          -- ★ v10.4：所有数值项都不再用滑块 —— 「0 = 默认 / 0 = 关闭」的项滑块根本输不进 0
          --   （16 章 §2.8），大范围项也拖不准。统一改成「值 N」按钮 + 数字键盘。
          local cur = math.floor(num(cur_of(e.key), e.lo))
          D.text(U(6), ry + U(3), e.name, C.text, 0.55, bw - U(150))
          if D.ibtn(bskin(), U(4), tool_y, U(132), U(30),
                    string.format("值 %d", cur), 10) then
            S.num_key, S.num_buf, S.num_msg = e.key, tostring(cur), ""
            S.sel = e.key
            if has("scroll_to") then pcall(G.scroll_to, "wf_params", 0, 0) end
          end
          D.text(U(142), tool_y + U(8),
            string.format("范围 %d ~ %d；点「值」开数字键盘", e.lo, e.hi),
            C.muted, 0.45, bw - U(208))
        elseif e.kind == "choice" then
          local cur = tostring(cur_of(e.key))
          local ck = S.key_confirm
          if ck and ck.key == e.key and ck.value ~= nil then
            -- ★ v10.3：危险项二次确认（改世界大小对新世界不可逆）
            D.text(U(6), ry + U(3),
              "把「" .. e.full .. "」从 " .. SX(cur) .. " 改成 " .. SX(tostring(ck.value)) .. "？",
              C.warn, 0.5, bw - U(8))
            if D.ibtn(bskin(), U(4), tool_y, U(92), U(30), "确定执行", 10) then
              set_val(e, ck.value)
              S.changed, S.sel = true, e.key
              S.key_confirm = nil
              S.op_last = "已改：「" .. e.full .. "」"
            end
            if D.ibtn(bskin(), U(100), tool_y, U(88), U(30), "取消", 10) then
              S.key_confirm = nil
              S.op_last = "已取消"
            end
          else
            if D.ibtn(bskin(), U(4), ry + U(3), bw - U(12), U(30), e.name .. "：" .. SX(cur), 10) then
              if DANGER_KEY[e.key] then
                S.key_confirm = { key = e.key, value = next_choice(e) }
                S.op_last = "危险项：再点一次「确定执行」"
              else
                bump(e, 1) S.changed = true S.sel = e.key
              end
            end
          end
        else
          D.text(U(6), ry + U(6), e.name .. " = " .. trunc(tostring(cur_of(e.key)), 10) .. "（只读文本项）",
            C.muted, 0.5, bw - U(60))
        end
      end
    end
    SE()
    -- 工具条：编辑数字 / 当前项 + 地图生成进度
    if dh > 0 then
      SB("wf_params_dock", 0, avail() - dh, bw, dh, bw, dh)
      do
        local sel = S.sel and IDX.by_key[S.sel] or nil
        local info
        if sel then
          info = "当前项：" .. sel.full .. " = " .. trunc(tostring(cur_of(sel.key)), 16)
        else
          info = string.format("共 %d 个分组 / %d 项；已展开 %d 组；改动 %d 项",
            total_n, #IDX.keys, open_n, GOV_N)
        end
        D.text(U(2), U(2), info, C.accent, 0.5, bw - U(8))
        if (S.filter or "") ~= "" then
          D.text(U(2), U(24), string.format("筛：%s -> %d 组 / %d 项", trunc(S.filter, 14),
            vis_n, FR.total), C.gold, 0.45, bw - U(8))
        elseif S.num_msg ~= "" then
          D.text(U(2), U(24), S.num_msg, C.gold, 0.45, bw - U(8))
        else
          local prog, ptext = gen_progress()
          if prog then
            cursor(U(2), U(20))
            FW.bar(prog)
            D.text(U(2), U(48), "地图生成：" .. trunc(ptext, 40), C.gold, 0.45, bw - U(8))
          else
            D.text(U(2), U(24), "提示：想让改动长期保留，请到模组的设置界面里改这一项。",
              C.muted, 0.45, bw - U(8))
          end
        end
      end
      SE()
    elseif dropped then
      check_line(avail() - U(14), bw, fixed)
    end
  end

  -- 一键页：四个分页 + 40 余个按钮（图片按钮 + 九宫格皮肤）+ 类型选择器 / 个数档
  -- 行表来自 ONESHOT.groups；按钮行走滚动容器 + 虚拟列表（只画可见行）。
  PG.oneshot = function(bw)
    build_index()
    local top0 = U(CTLY)
    local gs = os_groups()
    if not gs then
      D.text(0, top0, "一键操作分片未启用：读不到 ONESHOT（87_oneshot.lua 没装上）", C.warn, 0.55, bw)
      return
    end
    S.os_tab = clamp_iv(S.os_tab, 1, #gs)
    local gap = U(4)
    -- v10.1：右边留出 U(80) 给「回到顶部」—— 原来分页签铺满整宽，第 4 个签（雷击）
    --   与「回到顶部」的矩形重叠 74x30：点雷击的右半边会命中回到顶部（真机上也点不准）。
    local nw = math.floor((bw - U(80) - gap * (#gs - 1)) / #gs)
    if nw < U(40) then nw = U(40) end
    local x = 0
    for i = 1, #gs do
      local nm = SX(tostring(gs[i].name or ("分页" .. i)))
      if D.ibtn(bskin(), x, top0, nw, U(30), nm, 10) then
        S.os_tab = i
        S.os_confirm = nil
        S.force_save = true
        if has("scroll_to") then pcall(G.scroll_to, "wf_os", 0, 0) end
      end
      if i == S.os_tab then D.fill(x, top0 + U(27), nw, U(2), C.accent) end
      x = x + nw + gap
    end
    local grp = gs[S.os_tab]
    local head = (type(grp) == "table" and type(grp.head) == "table") and grp.head or nil
    local head_n = head and #head or 0
    local rows = (type(grp) == "table" and type(grp.rows) == "table") and grp.rows or {}
    D.text(0, top0 + U(24), string.format("第 %d/%d 组  共 %d 行  上次：%s", S.os_tab, #gs, #rows,
      trunc(S.op_last, 30)), C.muted, 0.5, bw - U(80))
    if D.ibtn(bskin(), bw - U(76), top0, U(76), U(30), "回到顶部", 10) then
      if has("scroll_to") then pcall(G.scroll_to, "wf_os", 0, 0) end
    end
    -- ★ v10.1：行距 34 → 36、按钮高 26 → 30（加载器 line_height = 28*g_scale）
    local HEAD_H = 36
    local head_top = U(CTLY + 36)
    if avail() - (head_top + U(head_n * HEAD_H) + U(6)) < U(44) then
      head_n = 0                    -- 屏幕太矮：先丢掉头部行，保证视口还在窗口内容区里
    end
    if head_n > 0 then
      local hh = U(head_n * HEAD_H) + U(2)
      SB("wf_oshead", 0, head_top, bw, hh, bw, hh)
      for i = 1, head_n do
        local row = head[i]
        local rw = (type(row) == "table") and #row or 0
        if rw > 0 then
          local cw2 = math.floor((bw - U(3 * (rw - 1))) / rw)
          for j = 1, rw do
            os_item(row[j], (j - 1) * (cw2 + U(3)), (i - 1) * U(HEAD_H) + U(2), cw2, U(30))
          end
        end
      end
      SE()
    end
    local top = head_top + U(head_n * HEAD_H) + U(6)
    if top > avail() - U(44) then top = avail() - U(44) end
    if top < 0 then top = 0 end
    local bh = avail() - top
    local nrow = #rows
    local cf = S.os_confirm
    local cfh = cf and U(40) or 0
    local py, ph = {}, {}
    local yy = cfh
    for i = 1, nrow do
      py[i] = yy
      ph[i] = TILE_H
      yy = yy + U(TILE_H)
    end
    local ch = (yy + U(6) > bh) and yy + U(6) or bh
    local sx, sy, vw, vh = SB("wf_os", 0, top, bw, bh, bw, ch)
    if cf then
      -- ★ v10.3：危险动作的二次确认条（视口内容最上方；确认前绝不执行）
      D.fill(0, 0, bw - U(6), U(36), C.diff)
      D.text(U(4), U(4), "危险操作：" .. trunc(cf.label, 18) .. "，再点一次确认",
        C.warn, 0.5, bw - U(196))
      if D.ibtn(bskin(), bw - U(190), U(3), U(88), U(30), "确定执行", 10) then
        S.op_last = os_call(cf.id)
        S.os_confirm = nil
        S.force_save = true
      end
      if D.ibtn(bskin(), bw - U(98), U(3), U(88), U(30), "取消", 10) then
        S.os_confirm = nil
        S.op_last = "已取消危险操作"
      end
    end
    local first = first_row(py, ph, nrow, sy)
    for i = first, nrow do
      if py[i] > sy + vh then break end
      local row = rows[i]
      local rw = (type(row) == "table") and #row or 0
      if rw > 0 then
        local cw2 = math.floor((bw - U(3 * (rw - 1))) / rw)
        for j = 1, rw do
          os_tile(row[j], (j - 1) * (cw2 + U(3)), py[i], cw2)
        end
      end
    end
    D.text(U(2), math.max(yy, bh) - U(14),
      string.format("可见第 %d-%d 行 / 共 %d 行（滚动容器里只画这些）", first, math.min(nrow,
        first + math.floor(vh / U(TILE_H))), nrow), C.muted, 0.45, bw - U(8))
    SE()
  end

  -- 常用开关：真复选框（返回新值，陷阱 4），只改运行时覆盖层
  local function quick_check(key, label, x, y)
    local e = IDX.by_key[key]
    if not e then return end
    cursor(x, y)
    local cur = cur_of(key) == true
    local nv = cur
    if type(G.checkbox) == "function" then nv = G.checkbox(label, cur) end
    if nv ~= cur then
      set_val(e, nv == true)
      apply_overlay("开关 " .. key)
      S.op_last = label .. " -> " .. (nv and "开" or "关")
    end
  end

  -- 工具页：一次性动作（恢复 / 撤销 / 取消）＋四个常用开关
  PG.ops = function(bw)
    build_index()
    local top, bh, dh, tight, dropped, fixed = page_geo(0, 78)
    local OPS = {
      { "恢复原版世界", "restore" }, { "撤销本模组的改动", "undo" },
      { "重新应用设置", "replan" }, { "清空面板里的改动", "clear_gov" },
      { "生成任务状态", "wgen_stat" }, { "取消生成任务", "wgen_stop" },
      { "重跑自检", "self_check" }, { "重置窗口与屏幕", "@screen" },
    }
    local nrow = math.ceil(#OPS / 2)
    local y0 = nrow * U(34) + U(6)
    -- ★ v10.3：面板自检（只读）。40 项 API / 图片 id 状态 / 缓存 4 个数 / 上次错误。
    local function st(k)
      local v = S.img_stat and S.img_stat[k]
      return v and trunc(tostring(v), 16) or "还没刷新"
    end
    local open_n = 0
    for i = 1, #IDX.groups do if S.gopen[IDX.groups[i]] then open_n = open_n + 1 end end
    local DIAG = {
      { string.format("mod.gui：40 项里可用 %d 项%s", S.api_have,
          (S.api_missing_n > 0) and ("，缺 " .. trunc(S.api_missing, 40)) or "（全齐）"),
        (S.api_missing_n > 0) and C.warn or C.ok },
      { "图片：white " .. st("white") .. "；panel " .. st("panel"), C.muted },
      { "　　　button " .. st("button") .. "；glyph " .. st("glyph"), C.muted },
      { string.format("缓存：已用 %d KiB / 上限 %d KiB / 条目 %d / 淘汰 %d",
          math.floor(num(S.cache[1], 0) / 1024), math.floor(num(S.cache[2], 0) / 1024),
          num(S.cache[3], 0), num(S.cache[4], 0)), C.muted },
      { "上次错误：" .. ((S.last_err == "") and "无" or trunc(S.last_err, 46)),
        (S.last_err == "") and C.ok or C.warn },
      { string.format("检索缓存：重算 %d / 命中 %d（键 = 输入串 + 分组版本 %d 组）",
          S.fcalc, S.fhit, #IDX.groups), C.muted },
      { string.format("折叠：已展开 %d / %d 组；状态文件 %s", open_n, #IDX.groups, STATE_FILE),
        C.muted },
      { string.format("屏幕：g_scale %.2f / 可用内容高 %.0f px", S.g, avail()), C.muted },
    }
    local need = y0 + U(15) + U(20) + U(17) + U(#DIAG * 14) + U(8)
    local ch = (need > bh) and need or bh
    local sx, sy, vw, vh = SB("wf_ops", 0, top, bw, bh, bw, ch)
    local half = math.floor((bw - U(4)) / 2)
    local py, ph = {}, {}
    for i = 1, nrow do py[i] = (i - 1) * U(34) ph[i] = 34 end
    local first = first_row(py, ph, nrow, sy)
    if first < 1 then first = 1 end
    for i = 1, #OPS do
      local r = math.floor((i - 1) / 2)
      if r + 1 >= first then
        local bx = ((i - 1) % 2) * (half + U(4))
        local byy = r * U(34) + U(2)
        if byy <= sy + vh then
          if D.ibtn(bskin(), bx, byy, half, U(30), OPS[i][1], 10) then
            if OPS[i][2] == "@screen" then
              S.probe.phase, S.probe.done = 0, false
              S.win_x, S.win_y, S.pos_applied = 24, 24, false
              S.op_last = "正在重新探测屏幕，并把窗口放回左上角"
            else
              S.op_last = OPS[i][1] .. "：" .. run_op(OPS[i][2])
            end
            S.force_save = true
          end
        end
      end
    end
    local y = y0
    D.text(U(2), y, "上次：" .. trunc(S.op_last, 40), C.muted, 0.5, bw - U(8))
    y = y + U(15)
    D.text(U(2), y, "「恢复原版世界 / 撤销改动」执行前，请先确认世界已经保存。",
      C.warn, 0.45, bw - U(8))
    y = y + U(20)
    D.text(U(2), y, "面板自检（只读，不动任何设置）", C.accent, 0.55, bw - U(8))
    y = y + U(17)
    for i = 1, #DIAG do
      D.text(U(2), y, DIAG[i][1], DIAG[i][2], 0.45, bw - U(8))
      y = y + U(14)
    end
    SE()
    if dh > 0 then
      SB("wf_ops_dock", 0, avail() - dh, bw, dh, bw, dh)
      local half2 = math.floor(bw / 2)
      quick_check("enabled", "总开关", U(2), U(0))
      quick_check("host_only", "仅房主生效", U(2) + half2, U(0))
      quick_check("write_log", "记录日志", U(2), U(34))
      quick_check("hardmode", "强制困难模式", U(2) + half2, U(34))
      SE()
    elseif dropped then
      check_line(avail() - U(14), bw, fixed)
    end
  end

  -- 帮助页：使用说明 / 运行日志
  -- ★ v10.2：原来这里的「按功能列出的技术明细表」「图片缓存读数」「能力点名页」都是给
  --   开发者看的，玩家不需要知道那些数字，已全部移除。
  PG.about = function(bw)
    build_index()
    local top, bh, dh, tight = page_geo(0, 0)
    local by = U(CTLY)
    if D.ibtn(bskin(), 0, by, U(92), U(CTLH), S.tab == 1 and "[使用说明]" or "使用说明", 10) then
      S.tab = 1 S.force_save = true
    end
    if D.ibtn(bskin(), U(96), by, U(92), U(CTLH), S.tab == 2 and "[运行日志]" or "运行日志", 10) then
      S.tab = 2 S.force_save = true
    end
    if IMG.glyph then D.imgfit(IMG.glyph, bw - U(30), by + U(2), U(26), U(26), "contain", C.white) end
    D.text(U(196), by + U(5), "遇到问题先看这一页；日志可以复制给作者", C.muted, 0.5, bw - U(232))
    local L = {}
    local function Ln(t, c, sc) L[#L + 1] = { t = t, c = c or C.muted, s = sc or 0.5 } end
    if S.tab == 2 then
      Ln("日志尾巴（" .. LOG_FILE .. "）：" .. tostring(S.log_err), C.text, 0.55)
      for i = 1, #S.log_lines do Ln("  " .. S.log_lines[i], C.muted, 0.45) end
    else
      Ln("世界工坊 v" .. VERSION .. "    平台 " .. tostring(mod.platform), C.text, 0.58)
      Ln("本模组一共 " .. tostring(P.count or 0) .. " 项设置。有三种改法：", C.accent, 0.55)
      Ln("  1. 模组的设置界面（在 TEFManager 里点这个模组）：改完回到游戏几秒后生效，会长期保留。")
      Ln("  2. 面板的「参数」页：按分组折叠，点开组名就能拖滑块；只在本次游戏里生效。")
      Ln("  3. 面板的「一键」页：点一下马上执行一次，不用先改设置。")
      Ln("改了没反应？按顺序看：", C.accent, 0.55)
      Ln("  - 「状态」页第一行是不是「模组总开关：开」；")
      Ln("  - 联机时自己是不是客机（客机默认不写世界数据，想改请在设置里关掉「仅房主生效」）；")
      Ln("  - 到「工具」页点一次「重跑自检」，结果会发到聊天栏和日志。")
      Ln("中文显示成 * 怎么办：", C.gold, 0.55)
      Ln("  那个字不在游戏字体里（手机中文用的是官方本地化子集字体），不是模组坏了。")
      Ln("面板里改的参数只影响本次游戏，绝不写你的设置文件；", C.gold)
      Ln("  想长期保留，请到设置界面里改同一项。")
      Ln("状态文件：" .. STATE_FILE .. "（面板记住上次的页、窗口位置与面板改动）")
      Ln("日志文件：" .. LOG_FILE .. "（需要在设置里打开「写入日志文件」才会写）")
    end
    local need = #L * U(14) + U(72)
    local ch = (need > bh) and need or bh
    local sx, sy, vw, vh = SB("wf_about", 0, top, bw, bh, bw, ch)
    local yy = 0
    for i = 1, #L do
      if in_view(yy, 14, bh) then D.text(U(2), yy, L[i].t, L[i].c, L[i].s, bw - U(8)) end
      yy = yy + U(14)
    end
    yy = yy + U(4)
    local bx = 0
    if in_view(yy, 30, bh) and D.ibtn(bskin(), bx, yy, U(84), U(30), "刷新日志", 10) then
      read_log_tail() S.op_last = "日志已刷新"
    end
    bx = bx + U(88)
    if in_view(yy, 30, bh) and D.ibtn(bskin(), bx, yy, U(84), U(30), "保存状态", 10) then
      S.force_save = true
      S.op_last = "面板状态已保存"
    end
    bx = bx + U(88)
    if in_view(yy, 30, bh) and D.ibtn(bskin(), bx, yy, U(84), U(30), "重置窗口", 10) then
      S.win_x, S.win_y, S.pos_applied = 24, 24, false
      S.force_save = true
    end
    bx = bx + U(88)
    if in_view(yy, 30, bh) and D.ibtn(bskin(), bx, yy, U(84), U(30), "适应屏幕", 10) then
      S.probe.phase, S.probe.done = 0, false
      S.op_last = "正在重新探测屏幕"
    end
    SE()
    if tight then
      D.text(U(2), avail() - U(14), "!! 可用内容高太小，底部控件会被屏幕切掉", C.warn, 0.45, bw - U(8))
    end
  end

  -- 出错页（绝对布局 + draw_abs：保留那条「绝对布局页必须声明内容高」的路径）
  PG.error = function(bw)
    local y = U(6)
    D.text(0, y, "面板上次出错（已停在错误页，不会刷屏）：", C.warn, 0.58, bw)
    y = y + U(18)
    D.text(0, y, trunc(S.last_err, 120), C.muted, 0.5, bw)
    y = y + U(22)
    if D.btn(0, y, U(92), U(30), "复位并继续") then
      S.err_mode, S.last_err = false, ""
      S.pos_applied, S.width_applied = false, -1
    end
    if D.btn(U(100), y, U(92), U(30), "复位窗口") then
      S.win_x, S.win_y, S.pos_applied = 24, 24, false
    end
    y = y + U(26)
    D.text(0, y, "提示：点「复位并继续」回到面板；阴影里的错误也写进了 " .. LOG_FILE, C.muted, 0.45, bw)
    y = y + U(15)
    return (y + U(6)) / S.g
  end

  -- 旧加载器降级页（22 项时代：没有 text_at / button_at），纯流式
  PG.fallback = function()
    FW.text("世界工坊 v" .. VERSION)
    FW.wrap("本机加载器版本较旧，面板只能显示这一页。"
      .. "装上 LuaLoader 1.9.0 就能得到可滚动的参数页、一键页和图片皮肤。")
    for i = 1, #PAGES do
      if (i - 1) % 3 ~= 0 then FW.same() end
      if FW.btn(PAGES[i]) then S.page = i S.force_save = true end
    end
    FW.sep()
    if S.page == 3 then
      if FW.btn("生成任务状态") then S.op_last = run_op("wgen_stat") end
      FW.same()
      if FW.btn("取消生成任务") then S.op_last = run_op("wgen_stop") end
    else
      if FW.btn("恢复原版世界") then S.op_last = run_op("restore") end
      FW.same()
      if FW.btn("撤销本模组的改动") then S.op_last = run_op("undo") end
    end
    FW.wrap("上次：" .. trunc(S.op_last, 30))
  end

  -- 绝对布局页的收尾：声明内容高。★ 这条调用必须留在根上下文里
  -- （set_content_height 改的是当前上下文的光标；在视口里调只会改子光标）。
  local function draw_abs(fn)
    local used_base = fn()
    if has("set_content_height") then
      pcall(G.set_content_height, U(used_base))
    end
  end

  -- ================================================================ 帧循环
  local function frame_body()
    -- 40 项能力点名（只计数，不绘制）
    local have, missing, miss_n = 0, "", 0
    for i = 1, #API40 do
      if type(G[API40[i]]) == "function" then
        have = have + 1
      else
        miss_n = miss_n + 1
        missing = (missing == "") and API40[i] or (missing .. " " .. API40[i])
      end
    end
    S.api_have, S.api_missing, S.api_missing_n = have, missing, miss_n
    S.sc_open, S.sc_close, S.sc_extra, S.sc_depth = 0, 0, 0, 0
    S.scroll = has("begin_scroll")
    if not S.visible then return end
    overlay_guard()
    probe_step()
    if S.probe.done then
      apply_geometry()
      local okp, px, py = api("get_pos")
      if okp and type(px) == "number" then
        S.win_x, S.win_y, S.pos_valid = px, num(py, S.win_y), true
      end
    end
    ensure_images()
    if not S.predecoded then
      S.predecoded = true
      predecode_images()
    end
    apply_theme()
    apply_title()
    apply_skin()
    if S.frames - S.img_at >= 30 then
      S.img_at = S.frames
      refresh_images()
    end
    -- ★ v10.2：图片缓存读数只用于内部记账（面板不再印这些技术数字）
    if S.frames - S.cache_at >= 120 then
      S.cache_at = S.frames
      if has("image_cache_stats") then
        local okc, ca, cb, cc, cd = pcall(G.image_cache_stats)
        if okc then S.cache = { num(ca, 0), num(cb, 0), num(cc, 0), num(cd, 0) } end
      end
    end
    if S.frames - S.log_at >= 60 then read_log_tail() end
    if S.err_mode then draw_abs(PG.error) return end
    -- 22 项时代（没有 text_at / button_at）：降级成一页流式，绝不整帧抛错
    if not (has("text_at") and has("button_at")) then PG.fallback() return end
    S.page = clamp_iv(S.page, 1, #PAGES)
    local bw = body_w()
    if bw < U(120) then bw = U(120) end
    page_head(bw)
    local fn = PG.by_page[S.page]
    if fn then fn(bw) end
    -- ★ 老加载器（1.8.0）没有滚动视口：工具条里的流式控件会推动**根光标**，
    --   把窗口高度算小。这里在帧尾再把内容高钉回来（1.9.0 上 S.scroll = true，
    --   根光标从来没被推走过，这行等于空操作）。
    if not S.scroll and has("set_content_height") then pcall(G.set_content_height, avail()) end
  end
  PG.by_page = { PG.status, PG.params, PG.oneshot, PG.ops, PG.about }

  local function init_gui()
    build_index()
    load_state()
    S.width_applied = -1
    S.pos_applied = false
    S.visible = true
    S.win_w = clamp_iv(S.win_w, WIN_W_MIN, WIN_W_MAX)
    S.reloads_seen = cfg_stat.reloads
    S.img_at = -999
    S.cache_at = -999   -- ★ v10.2：第一帧就取一次图片缓存读数（内部记账用）
    S.probe.phase, S.probe.done = 0, false
    local n = 0
    if next(GOV) ~= nil then n = apply_overlay("启动恢复覆盖层") end
    mod.info(string.format(
      "世界工坊 GUI v%s：面板已就绪（5 页 / mod.gui %d 项 / 滚动容器 %s / g_scale %s）；状态文件 %s 覆盖层 %d 项，本次应用 %d 项",
      VERSION, S.api_have, has("begin_scroll") and "可用" or "不可用（1.8.0）",
      tostring(S.g), STATE_FILE, GOV_N, n))
  end

  -- ============================================================================
  -- 唯一入口：必须挂在 mod 表上（全局 function on_gui() 不会被调用，陷阱 1）
  -- ============================================================================
  mod.on_gui = function()
    G = mod.gui
    if type(G) ~= "table" then return end
    S.frames = S.frames + 1
    local have = 0
    for i = 1, #API40 do if type(G[API40[i]]) == "function" then have = have + 1 end end
    S.api_have = have
    if not S.inited then
      S.inited = true
      local ok0, e0 = pcall(init_gui)
      if not ok0 and type(mod.warn) == "function" then
        mod.warn("世界工坊 GUI：初始化失败：" .. tostring(e0))
      end
    end
    -- ★★ 陷阱 27：第一行就声明内容高。它写在最后 + 中间任何一行抛错
    --    = 窗口高度退回 56*g_scale → 真机表现「面板缩成一条、点不了也滚不动」。
    if has("set_content_height") then pcall(G.set_content_height, avail()) end
    local ok, err = pcall(frame_body)
    if not ok then
      S.last_err = tostring(err)
      S.err_mode = true
      if not S.err_logged then
        S.err_logged = true
        if type(mod.error) == "function" then
          mod.error("世界工坊 GUI：on_gui 出错，面板停在错误页（不再刷屏）：" .. tostring(err))
        end
      end
    end
    -- 参数页拖滑块时值每帧都在变：等它停下来再重算（省掉每帧 build_plans + 各域 reload）
    if S.changed_prev and not S.changed then
      local n = apply_overlay("参数微调")
      if n > 0 then S.op_last = string.format("已应用 %d 项参数改动", n) end
      S.force_save = true
    end
    S.sc_po, S.sc_pc = S.sc_open, S.sc_close
    S.changed_prev = S.changed
    S.changed = false
    if S.force_save and not S.changed then
      S.force_save = false
      save_state()
    end
  end

  -- 卸载时把「上次页 / 位置 / 覆盖层」落盘（包一层，不动原来的 cleanup）
  local prev_cleanup = mod.cleanup
  mod.cleanup = function()
    if type(prev_cleanup) == "function" then pcall(prev_cleanup) end
    pcall(save_state)
  end
end

wf_gui_install()
