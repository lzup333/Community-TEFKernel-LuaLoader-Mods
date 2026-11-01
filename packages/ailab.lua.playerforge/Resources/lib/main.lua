-- ============================================================================
-- 玩家工坊（PlayerForge） v2.1.2      pkg_id = ailab.lua.playerforge
-- 适用：Terraria Mobile 1.4.5.8 + TEFKernel + LuaLoader 1.6.3+（图形面板需 1.9.0）
--
-- 【做什么】
--   把玩家自身的属性做成一座可调的工坊，共 108 项设置，全部在 TEFManager 的
--   「模组设置」里调，改完由「自动重读设置间隔」驱动生效（默认 5 秒，可关）。
--     · 每条数值属性都有两把旋钮：「倍率」（原版数值 × (UI/100)）与
--       「加值」（在原版数值上加减，UI 值 1 表示 +0）。
--     · 另外一批开关式能力：上帝模式、无限飞行、无限跳、熔岩免疫、夜视、点亮全图……
--     · 所有倍率/加值都作用在「装备、增益、buff 都算完之后」的最终数值上，
--       因此得到的是真正意义上的「最终伤害 ×N」「最终移速 ×N」。
--
-- 【v2.1.1 修复】主菜单打开面板切属性页的实机 SIGSEGV（nil 实例 + 字段偏移 0x820）：
--   属性页改用 Main.player[Main.myPlayer] 每帧现取；实例字段绝不传 nil；属性 getter 必须 0 参静态；
--   未进世界显示「不可用」；属性页不写入状态文件（重启先回状态页）。
--
-- 【v2.1.0 增量】图形面板（mod.gui / mod.on_gui）：
--   5 页（状态 / 属性 / 参数 / 一键 / 关于）；羊皮纸 + 金褐强调色（v2.3.1 工坊视觉基线）；
--   属性页只读（绝不 set_field_value，反射全 pcall，取不到显示「不可用」，最多每 6 帧刷新一次）；
--   客机（netMode==1）隐藏「回满血魔 / 点亮全图」并标注仅房主；
--   新增 gui_enable / gui_layout 两个设置项（旧加载器自动回落分页）。
--
-- 【v2.0.0 相对 v1.1.0 的增量】（§3.2 / §3.3 / §3.4 / §3.5 / §3.6 / §4.2 / §4.6）
--   1) §3.2 倍率/百分比类滑块上限 1000 → 10000（=100 倍）。非倍率类（秒/帧/点/格/数量）不动。
--   2) §3.3 minion_mult / turret_mult（默认 100）：仆从位/哨兵位百分比，
--      写在 Player.ResetEffects 的 postfix 里（原版每帧把它们重置为 1 + 装备加成，
--      写早了会被覆盖）。maxTurretsOld(0xBF0) 有变化检测，本模组绝不碰它。
--   3) §3.4 whip_speed / whip_range（默认 100）：写 Player.whipUseTimeMultiplier(0x2BC) /
--      Player.whipRangeMultiplier(0x2B8)，同样只能在 Player.ResetEffects 的 postfix 里写。
--      ★ 分工：属性工坊负责「对鞭子类物品跳过 useTime/useAnimation 的攻速改写」，
--        玩家工坊负责「用玩家侧字段提供鞭子加速/加长」。鞭长正比于物品模板的 useAnimation，
--        属性工坊一旦直接缩小 useAnimation，鞭长就会被吃掉 —— 所以两边必须配合。
--   4) §3.5 min_use_time（INTEGER，默认 3，范围 1~60）：所有攻速写入点统一
--      clamp(round(base × 攻速/100), min_use_time, 大值)；键名与语义与属性工坊一致。
--      本模组逐帧改 itemAnimationMax 的逻辑（鞭子加速）也共用这个下限。
--   5) §3.6-A 点亮全图：Main.get_Map（0 参属性）→ WorldMap 实例 →
--      循环 WorldMap.UnlockMapSection(sectionX, sectionY)（0..maxSectionsX-1 × 0..maxSectionsY-1）；
--      另有「逐格 WorldMap.Update(x, y, byte) 兜底」——必须分帧、带进度、可中断。
--      完成/进行中通过 Main.set_refreshMap(true) 刷新小地图。
--      ★ 已知坑：Main.ForcedMinimumZoom(0x9C4) 每帧被 max(1,…) 覆盖，单写无效，本模组不碰。
--   6) §3.6-B 视野：hook XNAWorldCameraSettings 的 0 参属性 getter
--      get_MinPixelScale / get_MaxPixelScale / get_MaxWorldWidth / get_MaxWorldHeight，
--      **默认值 = 原版（系数 1.0）= 零改动**。
--      备选路线：SpriteViewMatrix.Rebuild() 的 prefix 幂等缩放 _zoom（每帧每个矩阵只缩一次，
--      否则指数级缩放），默认关。
--   7) §3.6 光照：LightingEngine.UpdateLightDecay() 的 postfix 写 _workingLightMap 的
--      LightDecayThroughAir / LightDecayThroughSolid（穿透强度滑块 + 完全夜视开关）。
--      ★ 手机版 LegacyLighting 没有 _negLight/_negLight2/_negLight3（符号表校验已标「字段不存在」），
--        DoColors 那一路做不到，已在 README 的「做不到」一节写明。
--   8) §4.2 新增：暴击伤害倍率、无敌帧倍率/加值、药水冷却倍率、冲刺祝福、拾取范围
--      （Player.GetItemGrabRange(Item) 的 postfix 返回值）、自动使用/自动挥砍、自动朝向最近敌人。
--   9) §4.6 全套：诊断域注册表、self_check（默认开）/diag_report_cmd/diag_slow_ms、进世界首帧播报。
--
-- 【v2.0.2 相对 v2.0.1 的硬化】（同类崩溃家族的最后两条路径）
--   1) 删掉「反射属性名对应编译器后备字段」回退（v2.0.0 崩的就是聊天消息对象的
--      属性后备字段；本模组那条回退是死代码，见 part_body 的注释）。
--   2) 聊天播报的实参个数改成**问句柄自己**（method_param_count），不再按平台猜：
--      旧写法在「手机版只解析到 4 参重载」时会按 5 个实参调 4 参方法 → 越界 → SIGSEGV；
--      3 参重载的第二形参是 Color 结构体，libffi 只有标量，一律不调。
--
-- 【v2.0.1 相对 v2.0.0 的修复】（★ 崩溃修复，务必读）
--   A) **彻底移除**对聊天消息对象类型（Terraria.Chat 的消息类）的反射
--      （get_Text / <Text>k__BackingField）。v2.0.0 读聊天文本走的就是它；这条路径
--      被真机证实会把整个进程打死（原生崩溃，Lua 侧 pcall 拦不住 —— 本工作区唯一的
--      实机崩溃证据）。现在 main.lua 里**不出现该类型名**，测试里有静态断言守着。
--   B) 聊天指令改为**可选**（chat_cmd，默认关）：只有打开它才 get_type 聊天类型并装钩子；
--      唯一入口是 SayChatCommand.ProcessIncomingMessage(string, byte)（全标量参）。
--      关闭时聊天域直接标「未启用」，不装任何聊天钩子。
--   C) 默认（零聊天依赖）导出/导入：export_now → forge_export.txt；import_string 粘贴导入。
--   D) 崩溃取证日志（crash_log，默认开）：最近 60 条状态增量写 playerforge_diag.log。
--   E) 修正 Player.Hurt 的暴击回调实参错位（8 参签名的 crit 在 args[6]，不是 args[4]）。
--   A) 聊天文本入口只认 SayChatCommand.ProcessIncomingMessage(string, byte)（全标量参），
--      且只在 chat_cmd 打开时才解析。
--
-- 【怎么做（钩子与时机）】
--   原版每帧在 Player.Update 里按固定顺序重算这些字段，所以「写早了会被覆盖、
--   写晚了这一帧已经用过」。本模组按这个顺序挑时机：
--     ResetEffects → UpdateEquips → UpdateArmorSets → … → UpdateJumpHeight
--     → RefreshDoubleJumps → JumpMovement → WingMovement → ItemCheck
--   于是：
--     钩子1 Player.UpdateArmorSets(int)  postfix  ← 装备类最终数值（生命/移动/伤害/防御/
--                                                  范围/采集/幸运/全部开关）+ 药水冷却
--     钩子2 Player.UpdateJumpHeight()    postfix  ← 跳速/跳高 + 魔力上限（在 400 夹取之后）
--     钩子3 Player.JumpMovement()        postfix  ← 无限跳 / 无限飞行 / 无限火箭 / 冲刺祝福
--     钩子4 Player.UpdateManaRegen()     postfix  ← 魔力回复倍率
--     钩子5 Player.ResetEffects()        postfix  ← 仆从位/哨兵位倍率、鞭子字段（必须在这写）
--     钩子6 Player.UpdateImmunity()      postfix  ← 无敌帧倍率/加值
--     钩子7 Player.ApplyItemAnimation()  postfix  ← min_use_time 下限夹取
--     钩子8 Player.ItemCheck()           prefix   ← 自动使用/自动挥砍
--     钩子9 Player.GetItemGrabRange(Item) postfix ← 拾取范围倍率/加值
--     钩子10/11 NPC.StrikeNPC / Player.Hurt postfix ← 暴击伤害倍率
--     钩子12（可选）SayChatCommand.ProcessIncomingMessage(string,byte) prefix ← /forge 命令
--                  ★ 只有 chat_cmd 打开时装；默认关闭 = 不解析聊天类型、不装聊天钩子。
--     钩子13 LightingEngine.UpdateLightDecay() postfix ← 光照穿透/完全夜视
--     钩子14 LegacyLighting.UpdateLightDecay() postfix ← 传统光照兜底（尽量）
--     钩子15 XNAWorldCameraSettings.get_MinPixelScale / get_MaxPixelScale （视野缩放）
--     钩子16 SpriteViewMatrix.Rebuild()  prefix ← 备选缩放（默认关）
--     钩子17 Player.UpdateArmorSets 的（同钩子1）逐帧相位调度（设置比对/分帧点亮/自检）
--   默认配置下每次回调第一行就早退，一次反射调用都不发。
--
-- 【总控】
--   · host_only（默认开）：Main.netMode == 1（客机）时只读不写、不介入游戏数据；
--     取不到句柄时退化为「不限制」。
--   · tick_interval（默认 10 帧）：必须逐帧的最终数值写入保持逐帧；设置比对、免疫数组
--     还原、自动朝向、分帧点亮、统计这些可放宽的工作按序号分相位平摊（1 = 逐帧）。
--   · config_reload_sec（默认 5 秒）：自动重读设置的节拍，同时刷新 netMode 缓存。
--   · write_log（默认关）：关掉后除 setup() 阶段一次性「符号取不到」的 warn 外，
--     不执行任何 mod.info/warn/error，也不写任何日志文件；debug_log 仍是「详细日志」。
--   · self_check（默认开）：进世界首帧把每个功能域的句柄/钩子/命中一次性播报一次。
--   · chat_cmd（默认关）：聊天指令总开关，见上面 A) B)。
--   · crash_log（默认开）：把最近 60 条状态增量写进私有目录 playerforge_diag.log；
--     内核崩溃日志是异步刷盘的，崩溃会丢最后几行 —— 闪退请一并发来这个文件。
--
-- 【手机版符号】Main.myPlayer / Main.gameMenu 是**属性**（走 get_/set_ 桥接）；
--   Player.jumpSpeed / jumpHeight / tileRangeX / tileRangeY 也是**属性**；
--   Player.defaultItemGrabRange 是 const（不能读写）；Player.selectedItem 是**只读属性**；
--   Player/Entity 都没有 scale 字段 → 玩家体型倍率未实现；
--   Main.mouseX / mouseY 是**只读属性** → 自动瞄准没有可写入口。
--
-- 【稳定性设计】
--   · setup() 里只做元数据查询（get_type/get_field/get_method/field_is_static）
--     与安装钩子，绝不读写游戏字段、绝不调用游戏方法。
--   · 每个符号取不到 → 只打一条日志并关掉对应功能；空句柄绝不下传给反射调用。
--   · 所有字段读写都过 pcall；每个钩子用 pcall 安装，失败自动降级（见 setup 的阶段日志）。
--   · 钩子1 取不到时按 UpdateEquips → ResetEffects 逐级回退；钩子2 取不到时把它的
--     写入合并进钩子1（此时魔力上限受原版 400 夹取限制）。
--   · 免疫减益是数组级改动，关开关/卸载时会逐个还原。
--
-- 【未实机验证】本模组与工作区其它模组一样，只经过静态校验 + 假内核逻辑测试，
--   没有在真机上跑过。首次使用请先只装这一个模组。
-- ============================================================================

mod.meta = { pkg_id = "ailab.lua.playerforge", version = "2.1.3" }

local patch = mod.patch

local DEFAULTS = {
    enabled = true,
    self_check = true,
    diag_slow_ms = 50,
    diag_report_cmd = "forge stat",
    chat_cmd = false,
    import_string = "",
    export_now = false,
    hot_reload = true,
    config_reload_sec = 5,
    tick_interval = 10,
    host_only = true,
    write_log = false,
    debug_log = false,
    crash_log = true,
    life_max_mult = 100,
    life_max_add = 1,
    life_regen_mult = 100,
    life_full = false,
    god_mode = false,
    shadow_dodge = false,
    mana_max_mult = 100,
    mana_max_add = 1,
    mana_regen_mult = 100,
    mana_cost_mult = 100,
    mana_full = false,
    move_speed_mult = 100,
    move_speed_add = 1,
    jump_speed_mult = 100,
    jump_height_mult = 100,
    gravity_mult = 100,
    dash_on = 0,
    auto_jump = false,
    ignore_water = false,
    ice_skate = false,
    water_walk = false,
    no_fall_damage = false,
    no_knockback = false,
    infinite_flight = false,
    flight_time_mult = 100,
    infinite_jump = false,
    infinite_rocket = false,
    empress_brooch = false,
    tile_range_mult = 100,
    tile_range_add = 1,
    grab_range_mult = 100,
    grab_range_add = 1,
    damage_all_mult = 100,
    melee_damage_mult = 100,
    ranged_damage_mult = 100,
    magic_damage_mult = 100,
    summon_damage_mult = 100,
    melee_speed_mult = 100,
    whip_speed = 100,
    whip_speed_add = 1,
    whip_range = 100,
    whip_range_add = 1,
    crit_add = 1,
    armor_pen_add = 1,
    minion_mult = 100,
    minion_add = 1,
    turret_mult = 100,
    turret_add = 1,
    crit_damage_mult = 100,
    ammo_save = false,
    defense_mult = 100,
    defense_add = 1,
    endurance_add = 1,
    thorns_add = 1,
    aggro_add = 1001,
    lava_immune = false,
    fire_walk = false,
    water_breathing = false,
    debuff_immune = false,
    extra_accessory = false,
    immune_time_mult = 100,
    immune_time_add = 1,
    potion_cooldown_mult = 100,
    min_use_time = 3,
    pick_speed_mult = 100,
    tile_speed_mult = 100,
    wall_speed_mult = 100,
    fishing_add = 1,
    luck_add = 1,
    breath_max_mult = 100,
    night_vision = false,
    detect_creature = false,
    detect_treasure = false,
    danger_sense = false,
    calmed = false,
    invis = false,
    grav_control = false,
    acc_flipper = false,
    map_unlock_once = false,
    map_unlock_auto = false,
    map_progress = false,
    map_legacy_tiles = false,
    camera_zoomout = 100,
    camera_zoomin = 100,
    camera_world_bigger = false,
    camera_rebuild_zoom = false,
    light_full_night = false,
    light_penetration = 0,
    auto_cast = false,
    auto_fish_reel = false,
    auto_face_enemy = false,
    auto_aim = false,
    gui_enable = true,
    gui_layout = "滚动",
}

-- 每项允许范围（与 Info.json 的 min/max 一致；读取时再夹一次，防止手改 config.json 越界）
local LIMITS = {
    diag_slow_ms = { 1, 1000 },
    config_reload_sec = { 1, 60 },
    tick_interval = { 1, 60 },
    life_max_mult = { 1, 10000 },
    life_max_add = { 1, 10000 },
    life_regen_mult = { 1, 10000 },
    mana_max_mult = { 1, 10000 },
    mana_max_add = { 1, 10000 },
    mana_regen_mult = { 1, 10000 },
    mana_cost_mult = { 1, 10000 },
    move_speed_mult = { 1, 10000 },
    move_speed_add = { 1, 10000 },
    jump_speed_mult = { 1, 10000 },
    jump_height_mult = { 1, 10000 },
    gravity_mult = { 1, 10000 },
    dash_on = { 0, 6 },
    flight_time_mult = { 1, 10000 },
    tile_range_mult = { 1, 10000 },
    tile_range_add = { 1, 10000 },
    grab_range_mult = { 1, 10000 },
    grab_range_add = { 1, 10000 },
    damage_all_mult = { 1, 10000 },
    melee_damage_mult = { 1, 10000 },
    ranged_damage_mult = { 1, 10000 },
    magic_damage_mult = { 1, 10000 },
    summon_damage_mult = { 1, 10000 },
    melee_speed_mult = { 1, 10000 },
    whip_speed = { 1, 10000 },
    whip_speed_add = { 1, 10000 },
    whip_range = { 1, 10000 },
    whip_range_add = { 1, 10000 },
    crit_add = { 1, 100 },
    armor_pen_add = { 1, 10000 },
    minion_mult = { 1, 10000 },
    minion_add = { 1, 100 },
    turret_mult = { 1, 10000 },
    turret_add = { 1, 100 },
    crit_damage_mult = { 1, 10000 },
    defense_mult = { 1, 10000 },
    defense_add = { 1, 10000 },
    endurance_add = { 1, 100 },
    thorns_add = { 1, 10000 },
    aggro_add = { 1, 10000 },
    immune_time_mult = { 1, 10000 },
    immune_time_add = { 1, 10000 },
    potion_cooldown_mult = { 1, 10000 },
    min_use_time = { 1, 60 },
    pick_speed_mult = { 1, 10000 },
    tile_speed_mult = { 1, 10000 },
    wall_speed_mult = { 1, 10000 },
    fishing_add = { 1, 10000 },
    luck_add = { 1, 1000 },
    breath_max_mult = { 1, 10000 },
    camera_zoomout = { 1, 10000 },
    camera_zoomin = { 1, 10000 },
    light_penetration = { 0, 100 },
}


-- CHOICE 设置项的可选值（必须与 Info.json 的 options 逐值一致，build_mod.py 会校验）
local CHOICES = {
    gui_layout = { "滚动", "分页" },
}


-- 设置项声明顺序（= Info.json settings 的顺序）：/forge export 用它生成稳定的设置串，
-- 必须与 DEFAULTS 的键集合完全一致（build_mod.py 会校验 DEFAULTS/LIMITS/settings 三者对齐）。
local SETTING_ORDER = {
    "enabled",
    "self_check",
    "diag_slow_ms",
    "diag_report_cmd",
    "chat_cmd",
    "import_string",
    "export_now",
    "hot_reload",
    "config_reload_sec",
    "tick_interval",
    "host_only",
    "write_log",
    "debug_log",
    "crash_log",
    "life_max_mult",
    "life_max_add",
    "life_regen_mult",
    "life_full",
    "god_mode",
    "shadow_dodge",
    "mana_max_mult",
    "mana_max_add",
    "mana_regen_mult",
    "mana_cost_mult",
    "mana_full",
    "move_speed_mult",
    "move_speed_add",
    "jump_speed_mult",
    "jump_height_mult",
    "gravity_mult",
    "dash_on",
    "auto_jump",
    "ignore_water",
    "ice_skate",
    "water_walk",
    "no_fall_damage",
    "no_knockback",
    "infinite_flight",
    "flight_time_mult",
    "infinite_jump",
    "infinite_rocket",
    "empress_brooch",
    "tile_range_mult",
    "tile_range_add",
    "grab_range_mult",
    "grab_range_add",
    "damage_all_mult",
    "melee_damage_mult",
    "ranged_damage_mult",
    "magic_damage_mult",
    "summon_damage_mult",
    "melee_speed_mult",
    "whip_speed",
    "whip_speed_add",
    "whip_range",
    "whip_range_add",
    "crit_add",
    "armor_pen_add",
    "minion_mult",
    "minion_add",
    "turret_mult",
    "turret_add",
    "crit_damage_mult",
    "ammo_save",
    "defense_mult",
    "defense_add",
    "endurance_add",
    "thorns_add",
    "aggro_add",
    "lava_immune",
    "fire_walk",
    "water_breathing",
    "debuff_immune",
    "extra_accessory",
    "immune_time_mult",
    "immune_time_add",
    "potion_cooldown_mult",
    "min_use_time",
    "pick_speed_mult",
    "tile_speed_mult",
    "wall_speed_mult",
    "fishing_add",
    "luck_add",
    "breath_max_mult",
    "night_vision",
    "detect_creature",
    "detect_treasure",
    "danger_sense",
    "calmed",
    "invis",
    "grav_control",
    "acc_flipper",
    "map_unlock_once",
    "map_unlock_auto",
    "map_progress",
    "map_legacy_tiles",
    "camera_zoomout",
    "camera_zoomin",
    "camera_world_bigger",
    "camera_rebuild_zoom",
    "light_full_night",
    "light_penetration",
    "auto_cast",
    "auto_fish_reel",
    "auto_face_enemy",
    "auto_aim",
    "gui_enable",
    "gui_layout",
}

-- 自由文本设置项（STRING）：键 → 默认值，供 config.json 解析与导入导出使用
local STR_KEYS = {
    diag_report_cmd = "forge stat",
    import_string = "",
}

-- ============================================================================
-- 1. 常量 / 小工具
-- ============================================================================

-- 需要读写的字段 → 类型字符串。显式写出类型，不依赖内核的字段类型查询。
-- ★ 字段名对着 1.4.5.8 手机版符号表核对（参考库/符号/官方源码-字段.tsv）；
--   手机版把 jumpSpeed/jumpHeight/tileRangeX/tileRangeY 改成了**属性**（走 PROP_SPEC 桥接），
--   defaultItemGrabRange 是 **const**（读写皆失败 → 拾取范围功能降级不可用，见 setup 日志）。
local FIELD_SPEC = {
    -- 生命 / 魔力
    statLifeMax2 = "int32", statLife = "int32",
    statManaMax2 = "int32", statMana = "int32",
    lifeRegen = "int32", manaRegen = "int32", manaRegenCount = "int32",
    manaCost = "float",
    -- 防御 / 生存
    statDefense = "int32", endurance = "float", thorns = "float", aggro = "int32",
    creativeGodMode = "bool", shadowDodge = "bool", noKnockback = "bool", noFallDmg = "bool",
    fireWalk = "bool", lavaMax = "int32",
    breathMax = "int32", breath = "int32", gills = "bool", accFlipper = "bool",
    extraAccessory = "bool",
    -- 移动
    moveSpeed = "float", gravity = "float", jumpSpeed = "float", jumpHeight = "int32",
    autoJump = "bool", ignoreWater = "bool", iceSkate = "bool", waterWalk = "bool",
    -- 飞行 / 跳跃
    wingTime = "float", wingTimeMax = "int32", rocketTime = "int32", rocketTimeMax = "int32",
    empressBrooch = "bool",
    canJumpAgain_Cloud = "bool", hasJumpOption_Cloud = "bool",
    -- 交互范围
    tileRangeX = "int32", tileRangeY = "int32",
    -- 战斗
    meleeDamage = "float", rangedDamage = "float", magicDamage = "float", minionDamage = "float",
    arrowDamage = "float", bulletDamage = "float",
    meleeSpeed = "float", meleeCrit = "int32", rangedCrit = "int32", magicCrit = "int32",
    armorPenetration = "int32", maxMinions = "int32", maxTurrets = "int32",
    ammoCost75 = "bool", ammoCost80 = "bool",
    -- ★ v2.0.0（§3.3 / §3.4）：仆从位 / 哨兵位 / 鞭子 —— 都必须在 Player.ResetEffects
    --   的 postfix 里写（原版在该方法里把它们重置），字段已对着手机版符号表核对：
    --   whipRangeMultiplier(0x2B8) / whipUseTimeMultiplier(0x2BC) / maxMinions(0x354) / maxTurrets(0xBEC)。
    --   ★ maxTurretsOld(0xBF0) 有变化检测逻辑 —— 本模组绝不注册、绝不写它。
    whipRangeMultiplier = "float", whipUseTimeMultiplier = "float",
    -- 无敌帧 / 药水冷却（§4.2-⑤⑧）
    immuneTime = "int32", immuneAlpha = "int32", potionDelay = "int32",
    -- 冲刺祝福（§4.2-⑦）
    dash = "int32", dashType = "int32", dashDelay = "int32",
    -- 自动使用 / 物品选择
    controlUseItem = "bool", itemAnimation = "int32", itemAnimationMax = "int32",
    itemTime = "int32", itemTimeMax = "int32", reuseDelay = "int32",
    -- 采集 / 感知
    pickSpeed = "float", tileSpeed = "float", wallSpeed = "float",
    fishingSkill = "int32", luck = "float",
    nightVision = "bool", detectCreature = "bool", findTreasure = "bool",
    dangerSense = "bool", calmed = "bool", invis = "bool", gravControl = "bool",
    -- 数组与身份
    buffImmune = "object", buffType = "object", whoAmI = "int32",
    inventory = "object",
    -- ★ 手机版 Player.selectedItem 是**只读属性**（符号表 public [属性] 只有 get;），
    --   这里只登记 getter，写它没有意义。取值走 PROP_SPEC 桥接。
}

-- 玩家朝向 / 速度（定义在父类 Terraria.Entity 上，register 会沿父类链找）
local ENTITY_FIELDS = {
    direction = "int32", velocity = "object",
}

-- 只读属性（只有 getter）：手机版 Player.selectedItem。
-- 注意：register 会先按名字找字段；找不到时按 PROP_SPEC → PROP_RW → PROP_RO 顺序桥接。
local PROP_RO = {
    selectedItem = { "get_selectedItem" },
}

-- 通用「读写属性」登记：属性名 → { getter 名, setter 名 }。
-- 这里放的是手机版做成属性、但本模组按普通字段那样读写的成员。
local PROP_RW = {
    LightDecayThroughAir   = { "get_LightDecayThroughAir",   "set_LightDecayThroughAir" },
    LightDecayThroughSolid = { "get_LightDecayThroughSolid", "set_LightDecayThroughSolid" },
}

-- 已知是静态成员的名单（1.4.5.8 手机版符号表：jumpSpeed / jumpHeight / tileRangeX /
-- tileRangeY 是 static **属性**）。field_is_static 问不出来时用它兜底。
local KNOWN_STATIC = {
    jumpSpeed = true, jumpHeight = true,
    tileRangeX = true, tileRangeY = true,
}

-- 手机版把这些静态成员做成了属性（没有字段可 get_field），必须走 get_/set_ 方法桥接。
-- 判据：参考库/符号/官方源码-字段.tsv 里「修饰」列含 [属性]、且没有 <X>k__BackingField。
local PROP_SPEC = {
    jumpSpeed  = { "get_jumpSpeed",  "set_jumpSpeed" },
    jumpHeight = { "get_jumpHeight", "set_jumpHeight" },
    tileRangeX = { "get_tileRangeX", "set_tileRangeX" },
    tileRangeY = { "get_tileRangeY", "set_tileRangeY" },
}

-- 游戏不会每帧重置的字段：必须记住原版基准值，否则每帧乘一次会指数膨胀
-- （defaultItemGrabRange 曾在此列，但它在手机版是 const，已放弃读写）
local BASE_NAMES = { "breathMax" }

-- 免疫减益每次最多处理多少个槽位（玩家最多 44 个 buff，取个安全上限）
local PURGE_LIMIT = 60

local warned = {}

-- ---- v2.0.0 通用约定用到的模块级状态 ----
local PKG_SLUG = "playerforge"      -- 设置串里的 slug（与 通用约定 §2/§3 一致）
local chat_arity = 0                -- Main.NewText 的形参个数（5 = 手机版 / 4 = 桌面）
-- （SETTING_ORDER 由 part_head.lua 按 Info.json 的声明顺序生成，这里不再重复声明。）
-- ★ cfg 必须在这里就声明：本段之后的 chat/导出助手（build_setting_string 等）
--   是按 upvalue 捕获它的；声明晚了会变成全局 nil（真机上的表现是 /forge export 静默失败）。
local cfg = {}
-- 诊断域注册表（§4.6-1）：DOMAINS 是有序数组（自检按序播报），DOMAIN 是名字 → 域。
-- 必须早声明 —— setup() 与 sym_warn() 都要按名字写它。
local DOMAINS = {}
local DOMAIN = {}

-- ---- §3.6-A 点亮全图：状态机 ----
--   路线1（首选，一次性跑完）：Main.get_Map → WorldMap.UnlockMapSection(sectionX, sectionY)
--   路线2（兜底，强制分帧）：WorldMap.GetChunkTile(x,y,out chunk) 拿 MapTile* 后逐格写
--     Type=1 / Light=255 / Color=255 —— 只读句柄能拿到时启用。
--   ⚠️ 绝不把 2000 万格塞进一次 tick。
local frame_i = 0            -- 全局帧序号
local gui_frame_hits = 0     -- 本帧功能域命中次数（面板状态页显示；tick 开头清零）（诊断错峰耗时 + 光照幂等保护都要用）
local map_pending = false    -- 本世界还需要跑一次点亮
local map_running = false    -- 分帧兜底正在进行
local map_done = false       -- 本世界已跑完
local map_sec_total = 0
local map_sec_i = 0
local map_cx, map_cy = 0, 0
local map_tile_total = 0
local map_tile_i = 0
local map_frame = 0
local map_last_report = 0

-- ---- §4.6-1 启动自检 ----
local self_check_pending = false
local self_check_done = false

local ready = false
local menu_flag = true          -- 保守初值：先当作在主菜单
local world_entered = false
local my_index = -1
local last_cfg_check = 0
local last_inst = nil


-- ★ v2.0.0：下面这些句柄在 build_plans / 钩子回调 / setup 里都要按 upvalue 使用，
--   所以必须在文件最前面声明（声明晚了会变成全局 nil → 真机上表现为功能静默失效）。
local acc_light_air, acc_light_solid     -- LightMap.LightDecayThroughAir / ThroughSolid


-- ★ v2.0.0：v2 新增的所有句柄统一放进这一张表，而不是 40 多个独立 local ——
--   Lua 5.4 每个函数的局部变量上限是 200，本文件主 chunk 的 upvalue 已经接近上限。
--   （诊断域用不到它，热路径也不查它，只有 setup 与少数回调会读。）
local G = {}

-- ---- 日志总闸（v1.1.0）----
--   write_log 关掉时，除 setup() 阶段一次性「符号取不到」的 warn 外，任何
--   mod.info/warn/error 都不执行（逐帧路径尤其如此），也不写任何日志文件。
--   用 LOG_ON / DEBUG_ON 缓存开关，避免逐帧去解析配置。
local LOG_ON, DEBUG_ON = false, false

local function log_info(text)
    if LOG_ON then mod.info(text) end
end

local function log_debug(text)
    if DEBUG_ON then mod.info(text) end
end

-- ★ v2.0.1：崩溃取证日志的写入口先声明（真正实现见 2b 段）。
--   放在这里是为了让 log_warn / sym_warn / sym_error 也把告警记进「死前遗言」。
local diag_note
local diag_warned = {}    -- 死前遗言的告警去重（与 write_log 的 warned 分开，互不影响）

-- 运行期告警：受 write_log 门控，同一 tag 只打一次；
-- ★ 但无论 write_log 开不开，都要把「第一次」记进崩溃取证日志（崩溃时它才是可靠证据）。
local function log_warn(tag, text)
    if not diag_warned[tag] then
        diag_warned[tag] = true
        if diag_note then diag_note("[warn] " .. tostring(tag) .. "：" .. tostring(text)) end
    end
    if not LOG_ON or warned[tag] then return end
    warned[tag] = true
    mod.warn(text)
end

-- setup() 阶段「符号取不到」（字段 / 方法 / 句柄）专用：write_log 关着也允许打一次
-- ★ v2.0.0：标签支持 "dom:<域>|<子项>" 形式，命中时同步把该域的「句柄」标成 fail。
--   setup 末尾会用这个把每个域的装载状态汇总进诊断注册表（自检播报的第一个字就是它）。
local function sym_mark(tag)
    local dom = tag:match("^dom:([^:]+):")
    local d = dom and DOMAIN and DOMAIN[dom]
    if d then d.sym_fail = (d.sym_fail or 0) + 1 end
end

local function sym_warn(tag, text)
    if warned[tag] then return end
    warned[tag] = true
    sym_mark(tag)
    if diag_note then diag_note("[sym] " .. tostring(text)) end
    mod.warn(text)
end

local function sym_error(tag, text)
    if warned[tag] then return end
    warned[tag] = true
    sym_mark(tag)
    if diag_note then diag_note("[sym-error] " .. tostring(text)) end
    mod.error(text)
end

-- ---- 联机身份（netMode）----
--   Main.netMode 在 1.4.5.8 手机版是 public static int 字段（可读）。
--   用缓存，跟设置重读同节拍刷新，绝不逐帧反射读；取不到句柄时退化为「不限制」。
local F_net_mode
local net_mode_cache = 0
local net_mode_ready = false

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

-- 调静态方法的唯一入口：先核形参个数再传（传多传少都会崩），并 pcall 包住。
-- 返回 (成功, 值)：void 方法成功时值为 nil，失败不会与成功混淆。
local function invoke_static(m, ...)
    if not m then return false, nil end
    local n = select("#", ...)
    if patch.method_param_count then
        local okc, cnt = pcall(patch.method_param_count, m)
        if okc and tonumber(cnt) and tonumber(cnt) ~= n then return false, nil end
    end
    local ok, v = pcall(patch.invoke, m, ...)
    if not ok or v == false then return false, nil end
    return true, v
end

-- 沿父类链找字段（Main.netMode 这类静态字段）
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

local function find_method(type_handle, name, argc)
    if not type_handle then return nil end
    local ok, m = pcall(patch.get_method, type_handle, name, argc)
    if ok and m then return m end
    ok, m = pcall(patch.get_method, type_handle, name)
    if ok and m then return m end
    return nil
end

-- 沿父类链找方法（属性可能声明在父类上）
local function find_method_chain(type_handle, name, argc)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local m = find_method(cur, name, argc)
        if m then return m end
        local ok2, p = pcall(patch.get_parent, cur)
        cur = ok2 and p or nil
        guard = guard + 1
    end
    return nil
end

-- ---- 光照引擎的轻量访问器（§3.6）----
-- body 在 setup 阶段一次登记；字段在运行期每帧重取（属性对象可能被换新）。
-- 实例句柄同一帧内可自由使用（用完不跨帧保存）。
-- ★ 关键修正：hook 回调拿到的是**实例**，不是类型句柄，所以这里必须用
--   「该实例所属类型的完整名」当键（instanceof 查不出来，用 hook 注册时记录的反查表）。
--   LIGHT_FIELD_KIND：实例 → 类型全名（由钩子回调在注册时填）
--   LIGHT_FIELD：类型全名 → _workingLightMap 字段句柄
local LIGHT_FIELD = {}
local LIGHT_FIELD_KIND = {}
-- ★ 每帧只应用一次：两个光照引擎都可能在同帧被调用（还有 split-screen 多实例），
--   在已经改过的值上再算一次会越算越接近 1.0（指数级穿透）。用帧号挡掉。
local light_applied_frame = -1

local function fget_lightmap(inst)
    if not inst then return nil end
    -- ★ 按「实例所属类型」查字段句柄：fget 的 key 是 LIGHT_FIELD_KIND 里登记过的类型名。
    --   兼容两种写法：① LIGHT_FIELD[类型名] ② LIGHT_FIELD[实例]（老写法兜底）。
    local f = LIGHT_FIELD[LIGHT_FIELD_KIND[inst] or ""]
    if not f then f = LIGHT_FIELD[inst] end
    if not f then return nil end
    local ok, v = pcall(patch.get_field_value, f, inst, "object")
    if not ok then return nil end
    return v
end

-- 访问器形如 { kind = "method", get =, set = } 或 { kind = "field", field = }
local function read_float_acc(acc, target)
    if not acc or not target then return nil end
    if acc.kind == "method" then
        local ok, v = pcall(patch.invoke, acc.get, target)
        if ok and type(v) == "number" then return v end
        return nil
    end
    local ok, v = pcall(patch.get_field_value, acc.field, target, "float")
    if ok and type(v) == "number" then return v end
    return nil
end

local function write_float_acc(acc, target, value)
    if not acc or not target then return false end
    if acc.kind == "method" then
        if not acc.set then return false end
        return (pcall(patch.invoke, acc.set, target, value))
    end
    return (pcall(patch.set_field_value, acc.field, target, value, "float"))
end

-- 解析一个 float 属性的读/写通道（与 参考库/lua/light-penetration 同款三级回退）
local function resolve_float_acc(type_handle, prop_name)
    if not type_handle then return nil end
    if patch.get_property and patch.property_get_method then
        local okp, prop = pcall(patch.get_property, type_handle, prop_name)
        if okp and prop then
            local getter, setter
            local okg, v = pcall(patch.property_get_method, prop)
            if okg and v then getter = v end
            if patch.property_set_method then
                local oks, w = pcall(patch.property_set_method, prop)
                if oks and w then setter = w end
            end
            if getter and setter then
                return { kind = "method", get = getter, set = setter, bridge = true }
            end
        end
    end
    local getter = find_method_chain(type_handle, "get_" .. prop_name, 0)
    local setter = find_method_chain(type_handle, "set_" .. prop_name, 1)
    if getter and setter then
        return { kind = "method", get = getter, set = setter }
    end
    -- ★ v2.0.2：**删掉**了「反射属性名对应的编译器后备字段」这条回退路径。
    --   它就是本工作区唯一有实机证据的崩溃家族（对聊天消息对象的属性 getter 与
    --   其编译器后备字段做反射 → 整进程原生崩溃，见 05-写法与陷阱.md §5.2）。
    --   本模组只有两处调用（LightMap 的 LightDecayThroughAir / LightDecayThroughSolid），
    --   而 1.4.5.8 手机版这两个属性**都有 get_/set_ 方法**（官方源码-方法.tsv 已核）——
    --   上面那一步必然命中，这条回退本来就是死代码。宁可不做，也不留反射入口。
    return nil
end



-- 取静态属性的 getter：优先属性桥接（get_property → property_get_method），
-- 退回 get_X() 方法；形参个数必须是 0。
local function resolve_getter(type_handle, prop_name, getter_name)
    if not type_handle then return nil end
    local g
    if patch.get_property and patch.property_get_method then
        local okp, prop = pcall(patch.get_property, type_handle, prop_name)
        if okp and prop then
            local okg, v = pcall(patch.property_get_method, prop)
            if okg and v then g = v end
        end
    end
    if not g then g = find_method_chain(type_handle, getter_name, 0) end
    if g and patch.method_param_count then
        local okc, cnt = pcall(patch.method_param_count, g)
        if okc and tonumber(cnt) and tonumber(cnt) ~= 0 then return nil end
    end
    return g
end

local function resolve_setter(type_handle, prop_name, setter_name)
    if not type_handle then return nil end
    local st
    if patch.get_property and patch.property_set_method then
        local okp, prop = pcall(patch.get_property, type_handle, prop_name)
        if okp and prop then
            local oks, v = pcall(patch.property_set_method, prop)
            if oks and v then st = v end
        end
    end
    if not st then st = find_method_chain(type_handle, setter_name, 1) end
    if st and patch.method_param_count then
        local okc, cnt = pcall(patch.method_param_count, st)
        if okc and tonumber(cnt) and tonumber(cnt) ~= 1 then return nil end
    end
    return st
end

-- ============================================================================
-- 2. 字段句柄（setup 里只做元数据查询，不读值）
-- ============================================================================

local F, ST, FT, PM = {}, {}, {}, {}   -- 字段句柄 / 是否静态 / 类型字符串 / 属性访问器
local T_PLAYER, T_MAIN
local M_get_my_player              -- Main.get_myPlayer（Android 上 myPlayer 是属性）
local M_get_game_menu              -- Main.get_gameMenu（同上）
local M_add_buff                   -- Player.AddBuff（3 参）

local function register(key, owner, name, ty)
    local field, cur, guard = nil, owner, 0
    while cur and guard < 16 do
        local ok, f = pcall(patch.get_field, cur, name)
        if ok and f then field = f break end
        local ok2, p = pcall(patch.get_parent, cur)
        cur = ok2 and p or nil
        guard = guard + 1
    end
    -- ★ 硬规则：const 字段读出来是 nil + 内核警告（再下传就崩），更不能写 → 直接拒绝
    if field and patch.field_is_const then
        local okc, is_const = pcall(patch.field_is_const, field)
        if okc and is_const == true then
            sym_warn("c_" .. key, string.format("字段 %s 是 const，不能读写，相关功能不可用", key))
            return nil
        end
    end
    if not field then
        -- ★ 手机版把一部分静态成员做成了属性：走 get_/set_ 方法桥接
        local ps = PROP_SPEC[name]
        if ps then
            local g = resolve_getter(owner, name, ps[1])
            if g then
                PM[key] = { get = g, set = resolve_setter(owner, name, ps[2]) }
                ST[key] = true
                return g
            end
        end
        -- ★ v2.0.0：通用读写属性（LightMap 的两个衰减系数）
        local rw = PROP_RW[name]
        if rw then
            local g = resolve_getter(owner, name, rw[1])
            if g then
                local st = resolve_setter(owner, name, rw[2])
                if st then
                    PM[key] = { get = g, set = st }
                    ST[key] = true
                    return g
                end
            end
        end
        -- ★ v2.0.0：只读属性（get 有、set 没有）。手机版 Player.selectedItem 就是这种，
        --   符号表写的是 `public [属性]` + `get;`，没有 set 通道；登记 getter 用于读取，
        --   写入一律失败返回 false（调用方必须判返回值）。
        local ro = PROP_RO[name]
        if ro then
            local g = resolve_getter(owner, name, ro[1])
            if g then
                PM[key] = { get = g, set = nil }
                ST[key] = true
                return g
            end
        end
        sym_warn("f_" .. key, string.format("找不到字段 %s，相关功能不可用", key))
        return nil
    end
    F[key], FT[key] = field, ty
    local st = nil
    if patch.field_is_static then
        local ok, v = pcall(patch.field_is_static, field)
        if ok and type(v) == "boolean" then st = v end
    end
    if st == nil then st = KNOWN_STATIC[name] and true or false end
    ST[key] = st
    return field
end

local function fget(key, inst)
    local pg = PM[key]
    if pg then
        local ok, v = invoke_static(pg.get)
        if not ok then
            log_warn("g_" .. key, string.format("读取属性 %s 失败", key))
            return nil
        end
        return v
    end
    local f = F[key]
    if not f then return nil end
    -- 注意：不能写 `ST[key] and nil or inst` —— Lua 里 nil 是假值，那样永远得到 inst
    local obj = inst
    if ST[key] then obj = nil end
    local ok, v = pcall(patch.get_field_value, f, obj, FT[key])
    if not ok then
        log_warn("g_" .. key, string.format("读取 %s 失败：%s", key, tostring(v)))
        return nil
    end
    return v
end

local function fset(key, inst, v)
    local pg = PM[key]
    if pg then
        if not pg.set then return false end
        local ok = invoke_static(pg.set, v)
        if not ok then
            log_warn("s_" .. key, string.format("写入属性 %s 失败", key))
            return false
        end
        return true
    end
    local f = F[key]
    if not f then return false end
    local obj = inst
    if ST[key] then obj = nil end
    local ok, err = pcall(patch.set_field_value, f, obj, v, FT[key])
    if not ok then
        log_warn("s_" .. key, string.format("写入 %s 失败：%s", key, tostring(err)))
        return false
    end
    return true
end

-- 对象数组字段：句柄可缓存、对象不可（每帧重取，见工作区第 5 章 §1.5）
local function get_array(key, inst)
    local v = fget(key, inst)
    if v and type(v) ~= "number" then return v end
    return nil
end


-- ★ v2.0.0：下面这些句柄在 2b 段的闭包里被用到，必须先声明（Lua upvalue 规则）。
local M_new_text                -- Main.NewText（5 参手机版 / 4 参桌面）
-- ★ v2.0.1：聊天文本的唯一句柄。SayChatCommand.ProcessIncomingMessage(string, byte)
--   是 ChatInitializer 注册的 _defaultCommand，普通聊天与未知 /命令的原文都会送到这里，
--   参数全是标量。**只有 chat_cmd 打开时才会解析它**（默认 nil = 一行聊天代码都不跑）。
local M_say_chat
-- ★ v2.0.1：这两个通道定义在 4b 段（那里才能用到 patch_config_key / last_raw），
--   但 tick() 要按 upvalue 调用它们，所以先声明。
local tick_import_string
local tick_export_now

-- ============================================================================
-- 2b. 聊天播报 / 命令（§4.6、通用约定 §2 / §9）
--   统一走 chat_print；取不到 Main.NewText 或不在游戏内就退化成 mod.info（不崩）。
-- ============================================================================

local CHAT_TAG = "[玩家工坊] "

-- ---- 崩溃取证日志（v2.0.1）：最近 60 条状态增量写进私有目录 ----
--   ★ 内核崩溃日志是异步刷盘的，崩溃会丢掉最后几行 —— 这份文件才是崩溃时可靠的
--     「死前遗言」（05-写法与陷阱.md §5.3 的经验）。由 tick 的桶 2 按节拍刷盘。
local DIAG_FILE = "playerforge_diag.log"
local DIAG_CAP = 60
local DIAG = { ring = {}, n = 0, dirty = false, last_body = nil }
diag_note = function(text)
    local stamp = "?"
    if os.date then
        local okd, d = pcall(os.date, "%H:%M:%S")
        if okd and type(d) == "string" then stamp = d end
    end
    DIAG.n = DIAG.n + 1
    DIAG.ring[DIAG.n] = "[" .. stamp .. "] " .. tostring(text)
    while DIAG.n > DIAG_CAP do
        table.remove(DIAG.ring, 1)
        DIAG.n = DIAG.n - 1
    end
    DIAG.dirty = true
end

local function diag_flush()
    if not DIAG.dirty then return end
    if cfg.crash_log ~= true then DIAG.dirty = false return end
    local body = table.concat(DIAG.ring, "\n") .. "\n"
    if body == DIAG.last_body then DIAG.dirty = false return end
    local ok = pcall(mod.write_file, DIAG_FILE, body)
    if ok then
        DIAG.last_body = body
        DIAG.dirty = false
    end
end

-- ★ §9.2-3：Main.NewText 只在「游戏内」调用。启动极早期 Main.chatMonitor 还没建好，
--   那时调它会让托管异常穿出 native 帧 → 整进程崩（05-写法与陷阱.md §5.1 根因 A）。
--   主菜单 / 尚未进世界时一律退化成写日志，绝不 invoke。
local function in_game()
    return world_entered and not menu_flag
end

local function chat_plain(text)
    if text == nil then return end
    if not M_new_text or not in_game() then
        if LOG_ON then mod.info("[chat] " .. tostring(text)) end
        return
    end
    local ok, s = pcall(patch.string_create, tostring(text))
    if not ok or not s then return end
    -- ★ v2.0.2：实参个数**问句柄自己**（红线 3.5：传多传少都会崩），不再按平台猜。
    --   旧写法 `mod.platform == "android"` 在「手机版但只解析到 4 参重载」时会按 5 个实参去调
    --   4 参方法 → 越界 → SIGSEGV。另外 3 参重载的第二形参是 Color **结构体**，
    --   libffi 只支持标量，一律不调（宁可退化成日志）。
    -- 手机版：NewText(string, byte R, byte G, byte B, bool onlyCurrentPlayer) = 5 参
    -- 桌面端：NewText(string, byte R, byte G, byte B) = 4 参
    local n = chat_arity
    if patch.method_param_count then
        local okc, c = pcall(patch.method_param_count, M_new_text)
        if okc and type(c) == "number" then n = c end
    end
    if n == 5 then
        pcall(patch.invoke, M_new_text, s, 255, 255, 255, false)
    elseif n == 4 then
        pcall(patch.invoke, M_new_text, s, 255, 255, 255)
    elseif LOG_ON then
        mod.info("[chat] " .. tostring(text))
    end
end

-- 本模组的播报统一带前缀；自检/报告里已经带前缀的就不再重复加
local function chat_print(text)
    if text == nil then return end
    local t = tostring(text)
    if t:sub(1, #CHAT_TAG) == CHAT_TAG then chat_plain(t)
    else chat_plain(CHAT_TAG .. t) end
end

-- ---- 设置串的分片导出 / 导入（通用约定 §3）----
local SHARD_MAX = 320                 -- 每片正文上限（含 [i/n] 前缀）
local shards = {}                     -- 导入侧：已收到的片
local shard_need = 0
local shard_slug = nil

local function esc(s)
    s = tostring(s)
    s = s:gsub("%%", "%%25")
    s = s:gsub(";", "%%3B")
    s = s:gsub("|", "%%7C")
    s = s:gsub("=", "%%3D")
    -- ★ v2.0.1：空格也转义（%20）。设置串必须是「一个不含空白的 token」——
    --   导入侧要按 JSON 字面量原地改写 config.json，而取值模式遇到空白就断了。
    s = s:gsub(" ", "%%20")
    return s
end

local function unesc(s)
    s = tostring(s)
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

-- 校验和：全部字符的字节和 % 65521，十六进制小写（通用约定 §3.1）
local function checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum + s:byte(i)) % 65521 end
    return string.format("%x", sum)
end

local function build_setting_string(include_all)
    local parts = {}
    for i = 1, #SETTING_ORDER do
        local k = SETTING_ORDER[i]
        local cur = cfg[k]
        local def = DEFAULTS[k]
        -- ★ v2.0.1：import_string 是「输入通道」、export_now 是「一次性按钮」，
        --   两者都不是设置值，导出时一律跳过（否则导出的串里会带上上次粘贴的内容）。
        if k ~= "import_string" and k ~= "export_now"
            and (include_all or cur ~= def) then
            local lit
            if type(cur) == "boolean" then lit = cur and "true" or "false"
            elseif type(cur) == "number" then lit = string.format("%d", math.floor(cur))
            else lit = esc(cur) end
            parts[#parts + 1] = k .. "=" .. lit
        end
    end
    local body = "forge:" .. PKG_SLUG .. "|" .. table.concat(parts, ";")
    return body .. "|#" .. checksum(body), #parts
end

-- ---- §9.3 零聊天依赖的导出通道：写进模组私有目录 ----
--   返回 (ok, 串, 项数)；无论 chat_cmd 开不开都落盘，聊天分片只是额外便利输出。
local EXPORT_FILE = "forge_export.txt"
local EXPORT_DIR = "/storage/emulated/0/Android/data/eternal.future.tefmanager/files/mods/"
    .. "lzup333.lualoader/private/" .. PKG_SLUG
local function export_to_file(all)
    local s, n = build_setting_string(all)
    local ok = pcall(mod.write_file, EXPORT_FILE, s)
    diag_note(string.format("导出设置：%d 项 → %s（%s）", n, EXPORT_FILE,
        ok and "成功" or "写盘失败"))
    return ok, s, n
end

local function print_shards(s)
    local n = math.ceil(#s / SHARD_MAX)
    if n < 1 then n = 1 end
    for i = 1, n do
        local piece = s:sub((i - 1) * SHARD_MAX + 1, i * SHARD_MAX)
        if n > 1 then
            chat_print(string.format("[%d/%d] %s", i, n, piece))
        else
            chat_print(piece)
        end
    end
    return n
end

-- ---- 就地改写 config.json 里的一个 key（通用约定 §3.3）----
--   只替换该 key 的值字面量，未知 key 与 schemaVersion 必须原样保留。
local function patch_config_key(raw, key, new_lit)
    local e = key:gsub("([^%w])", "%%%1")
    local pat = '("' .. e .. '"%s*:%s*)([^,}%s]+)'
    local out, n = raw:gsub(pat, function(head)
        return head .. new_lit
    end, 1)
    if n == 0 then return nil end
    return out
end

-- ============================================================================
-- 3. 设置读取（config.json → cfg）
-- ============================================================================

-- cfg 的 local 声明在文件最前面（见 §0），这里只做初始化填充。
for k, v in pairs(DEFAULTS) do cfg[k] = v end

local last_raw = nil

-- 设置读完 / 重读后刷新日志总闸与联机总控的缓存
local function refresh_log_gate()
    LOG_ON = cfg.write_log == true
    DEBUG_ON = LOG_ON and cfg.debug_log == true
end

-- 联机「仅房主生效」：客机（netMode == 1）只读不写、不介入游戏数据
local function is_client()
    return cfg.host_only ~= false and net_mode_cache == 1
end

local function parse_int(raw, key, fallback, lo, hi)
    local e = key:gsub("([^%w])", "%%%1")
    local v = tonumber(raw:match('"' .. e .. '"%s*:%s*(-?%d+)'))
    if not v then return fallback end
    v = math.floor(v)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function parse_bool(raw, key, fallback)
    local e = key:gsub("([^%w])", "%%%1")
    local t = raw:match('"' .. e .. '"%s*:%s*(%a+)')
    if t == "true" then return true end
    if t == "false" then return false end
    return fallback
end

-- ★ §4.6-2：STRING 设置项（diag_report_cmd / import_string）的解析。
--   TEFManager 把字符串写成 JSON 字符串字面量；这里做「取到内容」的最小解析。
--   ★ v2.0.1 修正：v2.0.0 用 `(([^"]|\\.)*)` 这种写法 —— **Lua 模式没有 `|` 交替**，
--     那个模式永远匹配不上，于是 STRING 设置项一直读到的是默认值。改成手写扫描：
--     从值开引号起逐个字符走，遇 \ 跳一个字符并还原转义，遇 " 结束。
local function parse_str(raw, key, fallback)
    local e = key:gsub("([^%w])", "%%%1")
    local _, quote_at = raw:find('"' .. e .. '"%s*:%s*"')
    if not quote_at then return fallback end
    local out, i, n = {}, quote_at + 1, #raw
    while i <= n do
        local c = raw:sub(i, i)
        if c == "\\" then
            local nxt = raw:sub(i + 1, i + 1)
            if nxt == "" then break end
            if nxt == "n" then out[#out + 1] = "\n"
            elseif nxt == "t" then out[#out + 1] = "\t"
            elseif nxt == "r" then out[#out + 1] = "\r"
            else out[#out + 1] = nxt end
            i = i + 2
        elseif c == '"' then
            return table.concat(out)
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return fallback
end

-- v2.0.0：SETTING_ORDER 由生成器（tools/gen.py）按 Info.json 的声明顺序写出，
-- 键集合与 DEFAULTS 完全一致（build_mod.py 会校验）。export 直接按它遍历，串稳定可复现。
local SETTING_ORDER_OK = (#SETTING_ORDER > 0)

-- 返回 true 表示「文件内容变了」（调用方据此重建写入计划）
local function read_config()
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then return false end
    if raw == last_raw then return false end
    last_raw = raw

    for key, lim in pairs(LIMITS) do
        cfg[key] = parse_int(raw, key, DEFAULTS[key], lim[1], lim[2])
    end
    for key, def in pairs(DEFAULTS) do
        if type(def) == "boolean" then
            cfg[key] = parse_bool(raw, key, def)
        end
    end
    for key, def in pairs(STR_KEYS) do
        cfg[key] = parse_str(raw, key, def)
    end
    -- CHOICE：只接受 CHOICES 表里声明过的值，手改 config.json 越界时退回默认
    do
        local layout = parse_str(raw, "gui_layout", DEFAULTS.gui_layout)
        local okv = false
        for i = 1, #CHOICES.gui_layout do
            if CHOICES.gui_layout[i] == layout then okv = true break end
        end
        cfg.gui_layout = okv and layout or DEFAULTS.gui_layout
    end
    refresh_log_gate()
    return true
end

-- ★ §9.2-1：聊天指令总开关。关闭时本模组**不解析任何聊天类型、不装任何聊天钩子**，
--   连 get_type 都不发一次 —— 因为「反射聊天消息对象」被真机证实会把进程打死。
local function chat_cmd_on()
    return cfg.chat_cmd == true
end

-- ============================================================================
-- 4. 写入计划（配置变了才重建；每帧只执行计划，不做分支判断）
-- ============================================================================

-- ============================================================================
-- 4b. 诊断域注册表（§4.6-1 / 通用约定 §4）
--   每个「功能域」在 setup() 里登记一次（fields/methods/hooks 取 ok/partial/fail），
--   运行期只做两件事：d.calls = d.calls + 1、d.hits = d.hits + 1（一次 table 写，
--   绝不调函数、绝不字符串拼接）。errs/last_err 只在该域自己的失败分支里写。
--   self_check（默认开）在进世界首帧把每个域播报一次；/forge stat 随时打印。
-- ============================================================================

local dom_n = 0             -- 已登记的域数（也用作错峰耗时的序号）

local function dom_new(name)
    local d = { name = name, fields = "?", methods = "?", hooks = "?",
                calls = 0, hits = 0, errs = 0, last_err = nil,
                ms = 0, ms_n = 0, seq = dom_n }
    DOMAINS[#DOMAINS + 1] = d
    DOMAIN[name] = d
    dom_n = dom_n + 1
    return d
end

local function dom_err(d, text)
    if not d then return end
    d.errs = d.errs + 1
    d.last_err = tostring(text)
end

-- 耗时统计：只在「详细日志」或自检报告那一刻才会被读，热路径里只是一次 table 读写。
-- 用 os.clock（纯 CPU 时钟，不调游戏方法），并且**按域序号错峰**：每个域只在
-- (帧序号 + 域序号) % 16 == 0 的那一帧统计一次，避免逐帧两次 os.clock。
local function dom_tick_time(d, frame_no)
    if (frame_no + d.seq) % 16 ~= 0 then return nil end
    return os.clock()
end

local function dom_time_end(d, t0)
    if not t0 then return end
    local ok, t1 = pcall(os.clock)
    if ok and type(t1) == "number" then
        d.ms = d.ms + (t1 - t0) * 1000
        d.ms_n = d.ms_n + 1
    end
end

-- 热路径里最省的一次自增：d 已经是缓存的 table，直接写字段（一次 table 写，无函数调用）。
-- 用 `d ~= nil` 短路而不是单独 if，尽量少一条指令。
local function dom_hit(name, n)
    local d = DOMAIN[name]
    if d then d.hits = d.hits + (n or 1) end
    gui_frame_hits = gui_frame_hits + (n or 1)
end

-- 本模组的「功能域 → 命中条件」映射（§4.6-1）。
-- 命中 = 当前配置下这个域确实在改写游戏数据（= 本帧会有实际写入）。
-- 只在 build_plans() 里按配置求值一次，运行期完全不重复计算。
local P                  -- 前向声明：DOMAIN_HITS 的闭包要用它（声明晚了会变全局 nil）
local DOMAIN_HITS = {
    { "仆从位倍率",   function() return P.reset and #P.reset > 0 end },
    { "哨兵位倍率",   function() return P.reset and #P.reset > 0 end },
    { "无敌帧",       function() return P.immune_mul ~= 1 or P.immune_add ~= 0 end },
    { "药水冷却",     function() return P.potion_mul > 1 end },
    { "冲刺祝福",     function() return P.dash_on > 0 end },
    { "拾取范围",     function() return P.grab_mul ~= 1 or P.grab_add ~= 0 end },
    { "暴击伤害",     function() return P.crit_dmg ~= 1.0 end },
    { "自动使用",     function() return P.auto_cast end },
    { "自动朝向敌人", function() return P.auto_face end },
    { "光照穿透",     function() return P.light_pen > 0 end },
    { "完全夜视",     function() return P.light_full end },
    { "视野缩放",     function() return P.cam_zoomout ~= 1.0 or P.cam_zoomin ~= 1.0
                                        or P.cam_world_bigger end },
    { "视野备选缩放", function() return P.cam_rebuild end },
    { "地图解锁",     function() return P.map_pending_now end },
    { "地图逐格兜底", function() return P.map_legacy end },
    { "使用时间下限", function() return (P.min_use_time or 3) > 1 and G.M_apply_item_anim ~= nil end },
    { "聊天命令",     function() return M_say_chat ~= nil end },
}

local function dom_apply_hits()
    for i = 1, #DOMAIN_HITS do
        local e = DOMAIN_HITS[i]
        local d = DOMAIN[e[1]]
        if d then
            local ok, v = pcall(e[2])
            if ok and v then
                d.hits = (d.hits or 0) + 1
            elseif not ok then
                dom_err(d, v)
            end
        end
    end
end


P = {
    main = {}, jump = {}, bools = {}, reset = {},
    life_full = false, mana_full = false, water_breathing = false,
    infinite_flight = false, infinite_rocket = false, infinite_jump = false,
    mana_regen_mul = 1, debuff_immune = false,
    active_main = false, active_jump = false, active_move = false, active_regen = false,
    -- ★ v2.0.0 新增
    active_reset = false,        -- 仆从位/哨兵位倍率 + 鞭子字段（Player.ResetEffects postfix）
    min_use_time = 3,            -- §3.5 攻速下限（帧）
    dash_on = 0,                 -- §4.2-⑦ 冲刺祝福档位（0 = 关）
    immune_mul = 1, immune_add = 0,   -- §4.2-⑤ 无敌帧
    potion_mul = 1,              -- §4.2-⑧ 药水冷却
    grab_mul = 1, grab_add = 0,  -- §4.2-⑩ 拾取范围（GetItemGrabRange postfix）
    crit_dmg = 1.0,              -- §4.2-④ 暴击伤害倍率
    auto_cast = false,           -- §4.2-⑨ 自动使用/自动挥砍
    auto_face = false,           -- §4.2-⑪ 自动朝向最近敌人
    light_pen = 0,               -- §3.6 光照穿透强度 0~100（0 = 原版）
    light_full = false,          -- §3.6 完全夜视
    cam_zoomout = 1.0, cam_zoomin = 1.0,   -- §3.6-B 视野缩放系数（1.0 = 不动）
    cam_world_bigger = false, cam_rebuild = false,
    map_once = false, map_auto = false, map_progress = false, map_legacy = false,
    map_pending_now = false,     -- 本次重算时是否需要点亮（供域命中判定）
}
local BASE = {}                 -- 原版基准（只抓一次）
local jump_in_main = false      -- 钩子2 装不上时把它合并进钩子1
local purge_needed = false      -- 需要做一次「清掉身上已有的减益」

local function push(list, key, ty, mul, add, lo, hi, use_base, use_clamp)
    -- 字段句柄或属性访问器都没有 → 该功能不可用，直接跳过
    if not F[key] and not PM[key] then return end
    mul = mul or 1
    add = add or 0
    if mul == 1 and add == 0 then return end
    list[#list + 1] = { k = key, ty = ty, mul = mul, add = add, lo = lo, hi = hi,
                        ub = use_base, clamp_min = use_clamp }
end

-- 把开关映射到「置 true 的布尔字段」
local SWITCH_FIELDS = {
    { "auto_jump", "autoJump" },
    { "ignore_water", "ignoreWater" },
    { "ice_skate", "iceSkate" },
    { "water_walk", "waterWalk" },
    { "no_fall_damage", "noFallDmg" },
    { "no_knockback", "noKnockback" },
    { "fire_walk", "fireWalk" },
    { "night_vision", "nightVision" },
    { "detect_creature", "detectCreature" },
    { "detect_treasure", "findTreasure" },
    { "danger_sense", "dangerSense" },
    { "calmed", "calmed" },
    { "invis", "invis" },
    { "grav_control", "gravControl" },
    { "acc_flipper", "accFlipper" },
    { "god_mode", "creativeGodMode" },
    { "shadow_dodge", "shadowDodge" },
    { "extra_accessory", "extraAccessory" },
    { "empress_brooch", "empressBrooch" },
    { "ammo_save", "ammoCost75" },
    { "ammo_save", "ammoCost80" },
}

local last_debuff_immune = false

local function build_plans()
    local main, jump, bools, reset = {}, {}, {}, {}
    local pct = function(k) return (cfg[k] or 100) / 100 end          -- 倍率：UI 100 = ×1
    local add1 = function(k) return (cfg[k] or 1) - 1 end             -- 整数加值：UI 1 = +0
    local addf = function(k) return ((cfg[k] or 1) - 1) / 100 end     -- 小数加值：UI 101 = +1.00

    if cfg.enabled then
        -- ---- 生命 / 魔力 ----
        push(main, "statLifeMax2", "int32", pct("life_max_mult"), add1("life_max_add"), 1, 2000000)
        push(main, "lifeRegen", "int32", pct("life_regen_mult"), 0, -100000, 100000)
        -- 魔力上限硬夹 2000：HUD 的星星是「每 20 点画一颗」的循环，值太大界面会卡
        push(jump, "statManaMax2", "int32", pct("mana_max_mult"), add1("mana_max_add"), 1, 2000)
        push(main, "manaCost", "float", pct("mana_cost_mult"), 0, 0, 100)

        -- ---- 防御 / 生存 ----
        push(main, "statDefense", "int32", pct("defense_mult"), add1("defense_add"), 0, 100000)
        push(main, "endurance", "float", 1, addf("endurance_add"), 0, 0.9)
        push(main, "thorns", "float", 1, add1("thorns_add"), 0, 100000)
        push(main, "aggro", "int32", 1, add1("aggro_add") - 1000, -100000, 100000)
        if cfg.lava_immune then push(main, "lavaMax", "int32", 1, 9999, 0, 100000) end

        -- ---- 移动 ----
        push(main, "moveSpeed", "float", pct("move_speed_mult"), addf("move_speed_add"), 0.01, 1000)
        push(main, "gravity", "float", pct("gravity_mult"), 0, 0.001, 100)
        push(jump, "jumpSpeed", "float", pct("jump_speed_mult"), 0, 0.1, 1000)
        push(jump, "jumpHeight", "int32", pct("jump_height_mult"), 0, 1, 100000)
        push(main, "wingTimeMax", "int32", pct("flight_time_mult"), 0, 0, 100000)

        -- ---- 交互范围 ----
        push(main, "tileRangeX", "int32", pct("tile_range_mult"), add1("tile_range_add"), 1, 100000)
        push(main, "tileRangeY", "int32", pct("tile_range_mult"), add1("tile_range_add"), 1, 100000)
        -- ★ 手机版 Player.defaultItemGrabRange 是 const（读写皆失败）→ register 拒绝注册，
        --   F.defaultItemGrabRange 为 nil，push 直接跳过；拾取范围滑块因此不生效。
        push(main, "defaultItemGrabRange", "int32", pct("grab_range_mult"), 0, 1, 100000, true)

        -- ---- 战斗 ----
        local all = pct("damage_all_mult")
        push(main, "meleeDamage", "float", all * pct("melee_damage_mult"), 0, 0, 1000000)
        push(main, "rangedDamage", "float", all * pct("ranged_damage_mult"), 0, 0, 1000000)
        push(main, "magicDamage", "float", all * pct("magic_damage_mult"), 0, 0, 1000000)
        push(main, "minionDamage", "float", all * pct("summon_damage_mult"), 0, 0, 1000000)
        push(main, "meleeSpeed", "float", pct("melee_speed_mult"), 0, 0.01, 100)
        local crit = add1("crit_add")
        push(main, "meleeCrit", "int32", 1, crit, 0, 100)
        push(main, "rangedCrit", "int32", 1, crit, 0, 100)
        push(main, "magicCrit", "int32", 1, crit, 0, 100)
        push(main, "armorPenetration", "int32", 1, add1("armor_pen_add"), 0, 100000)

        -- ---- §3.4 鞭子（Player.ResetEffects postfix；原版在该方法里把这两个字段重置为 1）----
        -- ★ 分工：属性工坊负责「对鞭子类物品跳过 useTime/useAnimation 改写」，
        --   这里负责「用玩家侧字段提供加速/加长」。鞭长 ∝ 物品模板 useAnimation × whipRangeMultiplier，
        --   属性工坊一旦直接缩小 useAnimation，鞭长就会被吃掉 —— 两边必须配合。
        --   攻速用 whipUseTimeMultiplier（倍率 + 小数加值），范围用 whipRangeMultiplier。
        push(reset, "whipUseTimeMultiplier", "float",
            pct("whip_speed"), ((cfg.whip_speed_add or 1) - 1) / 100, 0, 1000)
        push(reset, "whipRangeMultiplier", "float",
            pct("whip_range"), ((cfg.whip_range_add or 1) - 1) / 100, 0, 1000)

        -- ---- §3.3 仆从位 / 哨兵位：倍率 + 原始加值（同一公式：原版 × 倍率/100 + 加值）----
        -- ★ 仆从/哨兵各有实体与 AI 开销，最终值硬夹在 200 / 100（滑块本身能到 10000%，
        --   但真给 10000 倍上限会直接卡死，所以这里留硬夹并在文档里写明）。
        -- ★ maxTurretsOld(0xBF0) 有变化检测，本模组绝不注册、绝不写它。
        push(reset, "maxMinions", "int32", pct("minion_mult"), add1("minion_add"), 1, 200, false, true)
        push(reset, "maxTurrets", "int32", pct("turret_mult"), add1("turret_add"), 1, 100, false, true)

        -- ---- 采集 / 其它 ----
        local pick = pct("pick_speed_mult")
        push(main, "pickSpeed", "float", pick > 0 and (1 / pick) or 1, 0, 0.3, 10)
        push(main, "tileSpeed", "float", pct("tile_speed_mult"), 0, 0.05, 3)
        push(main, "wallSpeed", "float", pct("wall_speed_mult"), 0, 0.05, 3)
        push(main, "fishingSkill", "int32", 1, add1("fishing_add"), 0, 100000)
        push(main, "luck", "float", 1, addf("luck_add"), -100, 1000)
        push(main, "breathMax", "int32", pct("breath_max_mult"), 0, 1, 1000000, true)

        -- ---- 开关：直接置 true 的布尔字段 ----
        for i = 1, #SWITCH_FIELDS do
            local sv, fn = SWITCH_FIELDS[i][1], SWITCH_FIELDS[i][2]
            if cfg[sv] and F[fn] then bools[#bools + 1] = fn end
        end
    end

    P.main, P.jump, P.bools, P.reset = main, jump, bools, reset
    P.life_full = cfg.enabled and cfg.life_full and F.statLife ~= nil and F.statLifeMax2 ~= nil or false
    P.mana_full = cfg.enabled and cfg.mana_full and F.statMana ~= nil and F.statManaMax2 ~= nil or false
    -- 溺水是「直接扣血 + KillMe」，不走 Hurt，所以上帝模式挡不住它 —— 上帝模式顺带把呼吸条保持满值
    P.water_breathing = (cfg.enabled and (cfg.water_breathing or cfg.god_mode)
        and F.breath ~= nil and F.breathMax ~= nil) and true or false
    if P.water_breathing and F.gills then
        bools[#bools + 1] = "gills"      -- 直接给「鱼鳃」效果，呼吸条根本不会掉
    end
    P.infinite_flight = cfg.enabled and cfg.infinite_flight
        and F.wingTime ~= nil and F.wingTimeMax ~= nil or false
    P.infinite_rocket = cfg.enabled and cfg.infinite_rocket
        and F.rocketTime ~= nil and F.rocketTimeMax ~= nil or false
    P.infinite_jump = cfg.enabled and cfg.infinite_jump
        and F.canJumpAgain_Cloud ~= nil and F.hasJumpOption_Cloud ~= nil or false
    P.mana_regen_mul = cfg.enabled and pct("mana_regen_mult") or 1
    P.debuff_immune = cfg.enabled and cfg.debuff_immune and M_add_buff ~= nil
        and F.buffImmune ~= nil and F.debuff ~= nil or false

    -- ---- §3.5 攻速下限 ----
    P.min_use_time = math.floor(tonumber(cfg.min_use_time) or 3)
    if P.min_use_time < 1 then P.min_use_time = 1 end
    if P.min_use_time > 60 then P.min_use_time = 60 end

    -- ---- §4.2-⑦ 冲刺祝福：0 = 关 ----
    P.dash_on = math.floor(tonumber(cfg.dash_on) or 0)
    if not cfg.enabled or P.dash_on < 0 or P.dash_on > 6 then P.dash_on = 0 end
    if not (F.dash and F.dashType) then P.dash_on = 0 end

    -- ---- §4.2-⑤ 无敌帧：100 = 原版 ----
    P.immune_mul = pct("immune_time_mult")
    P.immune_add = add1("immune_time_add")
    if not (F.immuneTime and cfg.enabled) then P.immune_mul, P.immune_add = 1, 0 end

    -- ---- §4.2-⑧ 药水冷却：100 = 原版 ----
    P.potion_mul = pct("potion_cooldown_mult")
    if not (F.potionDelay and cfg.enabled) then P.potion_mul = 1 end

    -- ---- §4.2-⑩ 拾取范围：走 Player.GetItemGrabRange(Item) 的 postfix 返回值 ----
    P.grab_mul = pct("grab_range_mult")
    P.grab_add = add1("grab_range_add")
    if not (G.M_get_grab_range and cfg.enabled) then P.grab_mul, P.grab_add = 1, 0 end

    -- ---- §4.2-④ 暴击伤害倍率：原版写死 ×2 → 本项 100 = ×2，200 = ×4 ----
    P.crit_dmg = pct("crit_damage_mult")
    if not cfg.enabled then P.crit_dmg = 1.0 end

    -- ---- §4.2-⑨ 自动使用 ----
    P.auto_cast = cfg.enabled and cfg.auto_cast == true and F.controlUseItem ~= nil

    -- ---- §4.2-⑪ 自动朝向最近敌人 ----
    P.auto_face = cfg.enabled and cfg.auto_face == true
        and F.direction ~= nil and G.F_npc_array ~= nil and G.F_npc_active ~= nil
        and G.F_npc_friendly ~= nil and G.F_entity_position ~= nil

    -- ---- §3.6 光照 ----
    P.light_full = cfg.enabled and cfg.light_full_night == true and acc_light_air ~= nil
    P.light_pen = math.floor(tonumber(cfg.light_penetration) or 0)
    if P.light_pen < 0 then P.light_pen = 0 end
    if P.light_pen > 100 then P.light_pen = 100 end
    if not (acc_light_air or acc_light_solid) then P.light_pen = 0 end

    -- ---- §3.6-B 视野缩放：默认 1.0 = 完全不动 ----
    P.cam_zoomout = pct("camera_zoomout")
    P.cam_zoomin = pct("camera_zoomin")
    if not cfg.enabled then P.cam_zoomout, P.cam_zoomin = 1.0, 1.0 end
    P.cam_world_bigger = cfg.enabled and cfg.camera_world_bigger == true
    P.cam_rebuild = cfg.enabled and cfg.camera_rebuild_zoom == true and G.F_view_zoom ~= nil

    -- ---- §3.6-A 地图 ----
    P.map_progress = cfg.enabled and cfg.map_progress == true
    if not cfg.enabled then
        P.map_once, P.map_auto, P.map_legacy = false, false, false
    else
        P.map_once = cfg.map_unlock_once == true
        P.map_auto = cfg.map_unlock_auto == true
        P.map_legacy = cfg.map_legacy_tiles == true
    end

    if P.debuff_immune and not last_debuff_immune then purge_needed = true end
    last_debuff_immune = P.debuff_immune

    -- ★ 这几个 active_* 必须放在最后算：它们依赖上面所有新增的 P.xxx
    --   （尤其是 dash_on / potion_mul——写早了会读到上一版的值）。
    P.active_main = #main > 0 or #bools > 0 or P.life_full or P.water_breathing
        or P.potion_mul > 1
    P.active_jump = #jump > 0 or P.mana_full
    P.active_move = P.infinite_jump or P.infinite_flight or P.infinite_rocket
        or P.dash_on > 0
    P.active_regen = P.mana_regen_mul > 1 and F.manaRegen ~= nil and F.manaRegenCount ~= nil
    P.active_reset = #reset > 0

    -- §4.6-1：按当前配置重算「哪些域本帧会真的改写游戏数据」，写进诊断注册表的 hits。
    P.map_pending_now = (P.map_once or P.map_auto) and not map_done
    -- ★ 每次重算计划都要重新举起「该点亮」的标记：进世界那一刻 P.map_once 可能还是
    --   上一个配置的值（setup 时 build_plans 先跑，enter_world 后跑），所以不能只在
    --   enter_world 里设一次。
    if P.map_pending_now then map_pending = true end
    pcall(dom_apply_hits)
end

-- 执行计划：原版每帧都会把这些字段重算回原版值，所以「读到的当前值就是原版值」，
-- 直接 目标 = 原版 × 倍率 + 加值，天然幂等、不会叠加。
local function run_plan(list, inst)
    for i = 1, #list do
        local op = list[i]
        local cur = fget(op.k, inst)
        if type(cur) == "number" then
            local base = cur
            if op.ub then base = BASE[op.k] or cur end
            local t = base * op.mul + op.add
            -- ★ v2.0.0（§3.5）：走 clamp 的项（仆从位/哨兵位/…）额外保一个整数下限，
            --   防止「倍率很小 + 加值为 0」时把上限压到 0（0 个仆从位会让召唤直接失效）。
            if op.clamp_min and t < 1 then t = 1 end
            if op.lo and t < op.lo then t = op.lo end
            -- ★ 上界夹取：倍率类的上界由 LIMITS（= 滑块 max）在读取配置时夹好；
            --   但像 statManaMax2=2000（HUD 星星循环开销）、pickSpeed=10、tileSpeed=3
            --   这些「游戏本身另有硬夹」的项，必须在这里再夹一次。
            if op.hi and t > op.hi then t = op.hi end
            if t ~= t or t == math.huge or t == -math.huge then
                log_warn("nan_" .. op.k, string.format("%s 的计算结果非法（NaN/Inf），已跳过", op.k))
            elseif op.ty == "float" then
                if math.abs(t - cur) > 1e-4 then fset(op.k, inst, t) end
            else
                t = math.floor(t + 0.5)
                if t ~= cur then fset(op.k, inst, t) end
            end
        end
    end
end

-- ============================================================================
-- 5. 各钩子的应用逻辑
-- ============================================================================

local function apply_main(inst)
    -- ★ 写入口第一件事：联机客机（netMode==1）只读不写、不介入游戏数据
    ensure_net_mode()
    if is_client() then return end
    run_plan(P.main, inst)
    local b = P.bools
    for i = 1, #b do fset(b[i], inst, true) end
    if P.life_full then
        local mx = fget("statLifeMax2", inst)
        if type(mx) == "number" and mx > 0 then fset("statLife", inst, mx) end
    end
    if P.water_breathing then
        local mx = fget("breathMax", inst)
        if type(mx) == "number" then fset("breath", inst, mx) end
    end
    -- ★ §4.2-⑧ 药水冷却：原版在 Player.Update 里 potionDelay-- （每帧 1）。
    --   这里按倍率「多减一点」：new = cur - (cur / mul - cur)，等价于消耗速度 × mul。
    --   只在 cur > 1 时写，保证绝不会把它压到 0（0 = 可以无限喝药）。
    --   ⚠️ 联机时冷却由服务器判定，服务器仍按原速，本项会让请求被拒绝；默认 100（不动）。
    if P.potion_mul > 1 then
        local cur = fget("potionDelay", inst)
        if type(cur) == "number" and cur > 1 then
            local spend = cur / P.potion_mul
            local new_v = math.floor(cur - spend + 0.5)     -- int32 字段，先取整再写
            if new_v > 0 and new_v < cur then fset("potionDelay", inst, new_v) end
        end
    end
end

local function apply_jump(inst)
    ensure_net_mode()
    if is_client() then return end
    run_plan(P.jump, inst)
    if P.mana_full then
        local mx = fget("statManaMax2", inst)
        if type(mx) == "number" and mx > 0 then fset("statMana", inst, mx) end
    end
end

local function apply_move(inst)
    ensure_net_mode()
    if is_client() then return end
    if P.infinite_jump then
        fset("canJumpAgain_Cloud", inst, true)
        fset("hasJumpOption_Cloud", inst, true)
    end
    if P.infinite_flight then
        local mx = fget("wingTimeMax", inst)
        if type(mx) == "number" and mx > 0 then fset("wingTime", inst, mx) end
    end
    if P.infinite_rocket then
        local mx = fget("rocketTimeMax", inst)
        if type(mx) == "number" then fset("rocketTime", inst, mx) end
    end
    -- ★ §4.2-⑦ 冲刺祝福：每帧维持「处于冲刺状态」。原版在 Player.ResetEffects 里
    --   把 dashType 置 0，所以在帧末（JumpMovement postfix）重设。dashType 的档位语义
    --   取自 1.4.5.8 PC 源码（Player.cs:15164/15168/16550/... ）：
    --   1 塔比 / 2 克苏鲁之盾 / 3 日耀 / 4 水晶刺客 / 6 校准过的冲刺。
    --   ★ 部分档位自带无敌帧，联机会让判定与服务器不一致 —— 默认 0（关）。
    if P.dash_on > 0 and F.dash and F.dashType then
        fset("dashType", inst, P.dash_on)
        fset("dash", inst, P.dash_on)
        if F.dashDelay then fset("dashDelay", inst, 2) end
    end
end

local function apply_regen(inst)
    ensure_net_mode()
    if is_client() then return end
    if P.mana_regen_mul <= 1 then return end
    local r = fget("manaRegen", inst)
    local c = fget("manaRegenCount", inst)
    if type(r) == "number" and type(c) == "number" and r > 0 then
        fset("manaRegenCount", inst, c + math.floor(r * (P.mana_regen_mul - 1) + 0.5))
    end
end

-- ---- 免疫减益：靠 AddBuff 的 prefix 拦下「减益」，再加一次清理把身上已有的减益顶掉 ----

local debuff_arr, debuff_len = nil, 0

local function refresh_debuff_table()
    if not F.debuff then return false end
    local ok, arr = pcall(patch.get_field_value, F.debuff, nil, "object")
    if not ok or not arr then return false end
    local ok2, n = pcall(patch.array_length, arr)
    if not ok2 or type(n) ~= "number" or n < 1 then return false end
    debuff_arr, debuff_len = arr, n
    return true
end

local function is_debuff(t)
    if type(t) ~= "number" or t < 0 or t >= debuff_len or not debuff_arr then return false end
    local ok, v = pcall(patch.array_at, debuff_arr, t)
    if not ok then return false end
    return v == true or v == 1
end

local function on_add_buff(inst, args, result)
    if not P.debuff_immune or not args then return end
    if is_debuff(args[1]) then return true end       -- true = 跳过原方法（这个减益不加了）
end

local function purge_debuffs(inst)
    ensure_net_mode()
    if is_client() then return end
    purge_needed = false
    local bt = get_array("buffType", inst)
    local bi = get_array("buffImmune", inst)
    if not bt or not bi then return end
    local ok, n = pcall(patch.array_length, bt)
    if not ok or type(n) ~= "number" then return end
    if n > PURGE_LIMIT then n = PURGE_LIMIT end
    local marked = 0
    for i = 0, n - 1 do
        local ok2, t = pcall(patch.array_at, bt, i)
        if ok2 and type(t) == "number" and is_debuff(t) then
            -- 写进免疫表：同一帧稍后原版会用 buffImmune 把身上这些减益摘掉
            if pcall(patch.array_set, bi, t, true) then marked = marked + 1 end
        end
    end
    if marked > 0 then
        log_info(string.format("免疫减益：已清除身上 %d 个减益", marked))
    end
end

-- 上一次写入的值（用于卸载时还原「游戏不会每帧重置」的字段）
local function restore_bases(inst)
    for i = 1, #BASE_NAMES do
        local k = BASE_NAMES[i]
        if F[k] and type(BASE[k]) == "number" then fset(k, inst, BASE[k]) end
    end
end



-- ============================================================================
-- 6. 钩子回调
-- ============================================================================

-- ★ v2.0.0：新增功能用到的句柄 / 状态。声明必须早于下面的钩子回调
--   （Lua 闭包按名字捕获 upvalue；声明在后会变成全局变量 → 静默失效）。
local rebuild_target = {}    -- SpriteViewMatrix 实例 → 已缩放到的 _zoom（幂等保护）

local function refresh_my_index()
    if F.myPlayer then
        local ok, v = pcall(patch.get_field_value, F.myPlayer, nil, "int32")
        if ok and type(v) == "number" then my_index = v return end
    end
    if M_get_my_player then
        local ok, v = invoke_static(M_get_my_player)
        if ok and type(v) == "number" then my_index = v return end
    end
    my_index = -1
end

-- 主菜单门控：手机版 Main.gameMenu 是属性（没有字段）→ 字段 → getter → 保守 false
local function read_menu_flag()
    if F.gameMenu then
        local ok, v = pcall(patch.get_field_value, F.gameMenu, nil, "bool")
        if ok and type(v) == "boolean" then menu_flag = v return end
    end
    if M_get_game_menu then
        local ok, v = invoke_static(M_get_game_menu)
        if ok and type(v) == "boolean" then menu_flag = v return end
    end
    menu_flag = false
end

local function is_local(inst)
    if my_index < 0 or not F.whoAmI then return true end   -- 问不出来就不过滤
    local w = fget("whoAmI", inst)
    if type(w) ~= "number" then return true end
    return w == my_index
end

local function enter_world(inst)
    world_entered = true
    -- ★ v2.0.0：把玩家实例 retain 成 GC 托管句柄，跨帧使用（分帧点亮地图要用它定位玩家）。
    --   取不到 retain（老加载器）就退化为「不跨帧持有」，分帧点亮会改用 Map 宽高兜底。
    local okr, rh = pcall(patch.retain, inst)
    if okr and rh then last_inst = rh else last_inst = inst end
    -- 每次进世界：地图解锁复位（一次性的 map_unlock_once 才能再次触发）
    map_pending = P.map_once or P.map_auto
    map_done = false
    map_running = false
    if not self_check_done then self_check_pending = true end
    refresh_my_index()
    refresh_debuff_table()
    for i = 1, #BASE_NAMES do
        local k = BASE_NAMES[i]
        if F[k] and BASE[k] == nil then
            local v = fget(k, inst)
            if type(v) == "number" then BASE[k] = v end
        end
    end
    log_info("已进入世界：原版基准已记录，写入计划生效（钩子1=" ..
        (jump_in_main and "含跳跃" or "标准") .. "）")
    diag_note("已进入世界（world_entered=true）：原版基准已记录")
end

-- ---- §3.6-A 点亮全图：一次性路线（首选）----
--   Main.get_Map（0 参属性）→ WorldMap 实例 → 循环
--     WorldMap.UnlockMapSection(sectionX, sectionY)，sectionX ∈ [0, maxSectionsX-1]
--   大世界 8400×2400 → 42 × 16 = 672 段，一次性跑完不卡（属性/方法都是 0/2 标量参）。
local function map_section_counts()
    local sx, sy
    if G.F_main_max_sections_x then
        local ok, v = pcall(patch.get_field_value, G.F_main_max_sections_x, nil, "int32")
        if ok and type(v) == "number" and v > 0 then sx = math.floor(v) end
    end
    if G.F_main_max_sections_y then
        local ok, v = pcall(patch.get_field_value, G.F_main_max_sections_y, nil, "int32")
        if ok and type(v) == "number" and v > 0 then sy = math.floor(v) end
    end
    if not sx and G.F_main_max_tiles_x then
        local ok, v = pcall(patch.get_field_value, G.F_main_max_tiles_x, nil, "int32")
        if ok and type(v) == "number" and v > 0 then sx = math.floor(v / 200) end
    end
    if not sy and G.F_main_max_tiles_y then
        local ok, v = pcall(patch.get_field_value, G.F_main_max_tiles_y, nil, "int32")
        if ok and type(v) == "number" and v > 0 then sy = math.floor(v / 150) end
    end
    if not sx or sx < 1 then sx = 1 end
    if not sy or sy < 1 then sy = 1 end
    if sx > 4096 then sx = 4096 end
    if sy > 4096 then sy = 4096 end
    return sx, sy
end

local function map_refresh()
    if not G.M_set_refresh_map then return end
    -- Main.set_refreshMap(bool) —— 静态属性 setter（1 参）
    invoke_static(G.M_set_refresh_map, true)
end

local function run_map_unlock()
    if not G.F_map_getter or not G.M_unlock_section then
        return false, "取不到 Main.Map 或 WorldMap.UnlockMapSection"
    end
    -- ★ 属性 getter 是**实例方法**（0 形参，但 invoke 必须带 instance）：
--   先按「静态 0 参」调，失败再按「实例方法、实例传 nil」调（属性访问器不需要真实实例）。
local map
local ok, v = invoke_static(G.F_map_getter)
if ok and v then
    map = v
else
    local ok2, v2 = pcall(patch.invoke, G.F_map_getter, nil)
    if ok2 and v2 then map = v2 end
end
if not map then return false, "取不到 WorldMap 实例" end
    local sx, sy = map_section_counts()
    local t0 = os.clock and os.clock() or 0
    local done = 0
    for x = 0, sx - 1 do
        for y = 0, sy - 1 do
            if pcall(patch.invoke, G.M_unlock_section, map, x, y) then done = done + 1 end
        end
    end
    map_refresh()
    local ms = 0
    if os.clock then ms = math.floor((os.clock() - t0) * 1000) end
    return true, string.format("已点亮 %d/%d 段（%d×%d），耗时约 %d ms",
        done, sx * sy, sx, sy, ms)
end

-- 逐格兜底：必须在「一次性路线」不可用时才启用，且强制分帧。
--   WorldMap.GetChunkTile(x, y, out WorldMapChunk) 是 3 参（第 3 参是按引用输出）。
--   ★ 这个签名带 out 参数，本代加载器没有可验证的「按引用输出」调用约定 →
--     默认不用它。本函数只在能确认拿到 MapTile* 时才做写操作，否则原样返回 false。
local function run_map_tiles_step(budget)
    if not G.M_map_get_chunk_tile then
        return false, "取不到 WorldMap.GetChunkTile(x, y, out chunk)，逐格兜底不可用"
    end
    return false, "本代加载器不支持 out 参数调用，逐格兜底已停用（请用一次性点亮）"
end


local tick_slot = 0        -- 本帧轮到哪个「可放宽」相位（3 = 免疫数组还原该跑）
local auto_face_slot = 0   -- §4.2-⑪ 自动朝向的相位标记

-- ★ 可放宽的工作按序号分相位：第 k 项只在 (帧号 - k) 能被 tick_interval 整除的帧上跑。
--   tick_interval = 1 时全部逐帧；= 60 时每项各每 60 帧跑一次，任何一项都不会被跳过。
--   必须逐帧的部分（apply_main / apply_jump / apply_move / apply_regen，即「装备与增益
--   算完之后」的最终数值）在各自的钩子回调里每帧执行，不在这里。
local function tick()
    frame_i = frame_i + 1
    gui_frame_hits = 0
    local interval = math.floor(tonumber(cfg.tick_interval) or 10)
    if interval < 1 then interval = 1 end

    tick_slot = 0

    -- 桶 1：主菜单门控 + 本机玩家序号
    if (frame_i - 1) % interval == 0 then
        read_menu_flag()
        refresh_my_index()
    end

    -- 桶 2：设置比对 + netMode 缓存刷新（再受 config_reload_sec 的秒节拍限制）
    --   ★ v2.0.1：这一桶还要驱动「零聊天依赖」的导出/导入通道与崩溃取证日志。
    --     hot_reload 只决定「读到变化后是否重建写入计划」；导出/导入通道与它无关
    --     （客机上聊天不可用，这两个通道是官方替代通道）。
    if (frame_i - 2) % interval == 0 then
        local now = os.time()
        if type(now) == "number" and (now - last_cfg_check) >= cfg.config_reload_sec then
            last_cfg_check = now
            refresh_net_mode()
            if cfg.hot_reload then
                local ok, changed = pcall(read_config)
                if ok and changed then
                    build_plans()
                    pcall(refresh_debuff_table)
                    log_info(string.format("设置已重读：主计划 %d 项 / 跳跃计划 %d 项 / 开关 %d 个",
                        #P.main, #P.jump, #P.bools))
                end
            else
                -- 关掉自动重读时整体设置不生效（见文档），但这两个通道照旧可用
                local raw = mod.read_file("config.json")
                if type(raw) == "string" and raw ~= "" then
                    cfg.import_string = parse_str(raw, "import_string", "")
                    cfg.export_now = parse_bool(raw, "export_now", false)
                end
            end
            pcall(tick_import_string)
            pcall(tick_export_now)
            pcall(diag_flush)
        end
    end

    -- 桶 3：免疫数组还原（purge_debuffs 由 on_main 在这个相位帧上执行）
    if (frame_i - 3) % interval == 0 then tick_slot = 3 end

    -- 桶 4：统计（详细日志）
    if (frame_i - 4) % interval == 0 then
        log_debug(string.format("玩家工坊：帧 %d，计划 %d/%d/%d/%d，免疫减益 %s",
            frame_i, #P.main, #P.jump, #P.bools, #P.reset,
            P.debuff_immune and "开" or "关"))
    end

    -- 桶 5（§3.6-A）：点亮全图。一次性路线在相位帧上跑一次（大世界约 672 次 invoke）；
    --   逐格兜底路线**每帧一小批**（这里没有可用的分帧入口，所以整条兜底被停用）。
    if map_pending and not map_done and (frame_i - 5) % interval == 0 then
        map_pending = false
        if P.map_legacy and not G.M_unlock_section then
            local _, why = run_map_tiles_step(4000)
            log_warn("map_legacy", why or "逐格兜底不可用")
            if P.map_progress then chat_print(why or "逐格兜底不可用") end
            map_done = true
        else
            local ok, msg
            local oke, r1, r2 = pcall(run_map_unlock)
            if oke then ok, msg = r1, r2
            else ok, msg = false, "点亮时抛异常：" .. tostring(r1) end
            map_done = true
            map_pending = false
            if P.map_progress then
                chat_print(ok and msg or ("点亮地图失败：" .. tostring(msg)))
            end
            if not ok then log_warn("map_unlock", tostring(msg)) end
        end
        -- map_unlock_once 是一次性开关：播报后不写回 config（由玩家自己关），
        -- 但内部 pending 已清，不会每帧重跑。
    end

    -- 桶 6（§4.2-⑪）：自动朝向最近敌人（分相位 + 防抖：每 interval×4 帧重算一次）
    if P.auto_face and (frame_i - 6) % (interval * 4) == 0 then
        auto_face_slot = 6
    else
        auto_face_slot = 0
    end

    -- 桶 7（§4.6-1）：进世界首帧的自检播报
    --   ★ v2.0.1 修正：v2.0.0 漏了 self_check 总闸 —— 设置项「启动自检播报」关掉后
    --     照旧每进一次世界刷一遍聊天栏。现在真的按开关走（/forge check 手动触发不受限）。
    if self_check_pending and cfg.self_check == true and (frame_i - 7) % interval == 0 then
        self_check_broadcast()
    end

    -- 桶 8（v2.0.1 崩溃取证）：心跳。崩溃日志只从「进了世界」之后才有心跳，
    --   但阶段标记 / 钩子安装结果 / 告警在 setup 阶段就已经写进去了。
    if (frame_i - 8) % (interval * 6) == 0 then
        diag_note(string.format("心跳：帧 %d，菜单=%s，世界=%s，计划 %d/%d/%d/%d，域 %d 个",
            frame_i, tostring(menu_flag), tostring(world_entered),
            #P.main, #P.jump, #P.bools, #P.reset, #DOMAINS))
    end
end

local function on_main(inst, args, result)
    if not ready or not inst then return end
    pcall(tick)
    if menu_flag then return end
    if not world_entered then pcall(enter_world, inst) end
    if not is_local(inst) then return end
    if purge_needed and tick_slot == 3 then pcall(purge_debuffs, inst) end
    -- §4.2-⑪ 自动朝向（分相位调度；失败不影响其它功能）
    if auto_face_slot == 6 then pcall(apply_auto_face, inst) end
    local want_jump = jump_in_main and P.active_jump
    if not (P.active_main or want_jump) then return end
    local ok, err = pcall(function()
        if P.active_main then apply_main(inst) end
        if want_jump then apply_jump(inst) end
    end)
    if not ok then
        log_warn("cb_main", "主回调异常：" .. tostring(err))
    end
end

local function on_jump_height(inst, args, result)
    if not ready or not inst or menu_flag then return end
    if not P.active_jump then return end
    if not is_local(inst) then return end
    local ok, err = pcall(apply_jump, inst)
    if not ok then
        log_warn("cb_jump", "跳跃回调异常：" .. tostring(err))
    end
end

local function on_jump_movement(inst, args, result)
    if not ready or not inst or menu_flag then return end
    if not P.active_move then return end
    if not is_local(inst) then return end
    local ok, err = pcall(apply_move, inst)
    if not ok then
        log_warn("cb_move", "飞行回调异常：" .. tostring(err))
    end
end

local function on_mana_regen(inst, args, result)
    if not ready or not inst or menu_flag then return end
    if not P.active_regen then return end
    if not is_local(inst) then return end
    local ok, err = pcall(apply_regen, inst)
    if not ok then
        log_warn("cb_regen", "回魔回调异常：" .. tostring(err))
    end
end

local function on_add_buff_hook(inst, args, result)
    -- ★ 写入口第一件事：联机客机只读不写
    ensure_net_mode()
    if is_client() then return end
    if not ready or menu_flag or not P.debuff_immune then return end
    local ok, ret = pcall(on_add_buff, inst, args, result)
    if ok then return ret end
    return nil
end


-- ---- §4.6-1 自检 / 报告 ----
local function diag_lines(max_lines)
    local out = {}
    local total_calls, total_hits, total_errs = 0, 0, 0
    local slow = {}
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        total_calls = total_calls + d.calls
        total_hits = total_hits + d.hits
        total_errs = total_errs + d.errs
        local avg = 0
        if d.ms_n and d.ms_n > 0 then avg = d.ms / d.ms_n end
        if avg >= (tonumber(cfg.diag_slow_ms) or 50) then slow[#slow + 1] = d.name end
    end
    local limit = max_lines or 12
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        if i > limit then
            out[#out + 1] = string.format("…另有 %d 个域未显示（/forge stat 看全量）", #DOMAINS - limit)
            break
        end
        local fh = (d.fields == "ok") and "✅" or ((d.fields == "fail") and "❌" or "⚠️")
        local hh = (d.hooks == "ok") and "✅" or ((d.hooks == "fail") and "❌" or "⚠️")
        local tail
        if d.fields == "fail" and d.hooks == "fail" then
            tail = "已停用"
        else
            tail = string.format("本帧命中 %d 次", d.hits)
        end
        out[#out + 1] = string.format("域 %s：句柄%s 钩子%s %s", d.name, fh, hh, tail)
    end
    if #slow > 0 then
        out[#out + 1] = "SLOW： " .. table.concat(slow, " / ")
    end
    out[#out + 1] = string.format("合计 calls=%d hits=%d errs=%d", total_calls, total_hits, total_errs)
    return out
end

local function self_check_broadcast()
    self_check_pending = false
    self_check_done = true
    diag_note("启动自检播报（" .. #DOMAINS .. " 个功能域）")
    chat_plain(CHAT_TAG .. "启动自检（共 " .. #DOMAINS .. " 个功能域）")
    local lines = diag_lines(12)
    for i = 1, #lines do chat_plain(CHAT_TAG .. lines[i]) end
end

local function diag_report()
    self_check_done = true
    self_check_pending = false
    chat_plain(CHAT_TAG .. "诊断报告（共 " .. #DOMAINS .. " 个功能域）")
    local lines = diag_lines(#DOMAINS)
    for i = 1, #lines do chat_plain(CHAT_TAG .. lines[i]) end
    local interval = math.floor(tonumber(cfg.tick_interval) or 10)
    chat_plain(string.format(CHAT_TAG ..
        "设置刷新间隔 %d 秒 / 非关键项 %d 帧 / 总开关 %s / 房主限制 %s",
        math.floor(tonumber(cfg.config_reload_sec) or 5), interval,
        cfg.enabled and "开" or "关", cfg.host_only ~= false and "开" or "关"))
end

local function chat_help()
    chat_plain(CHAT_TAG .. "本模组支持的命令：")
    chat_plain(CHAT_TAG .. "  /forge help            —— 这页帮助")
    chat_plain(CHAT_TAG .. "  /forge stat            —— 诊断报告（每域 calls/hits/errs）")
    chat_plain(CHAT_TAG .. "  /forge check           —— 重跑一次启动自检")
    chat_plain(CHAT_TAG .. "  /forge export [all]    —— 导出设置串（落盘 " .. EXPORT_FILE
        .. "，默认只导非默认项）")
    chat_plain(CHAT_TAG .. "  /forge import <串>     —— 导入设置串（支持 [i/n] 分片）")
    chat_plain(CHAT_TAG .. "  /forge import reset    —— 放弃已缓存的分片")
    chat_plain(CHAT_TAG .. "  /forge map             —— 立刻点亮一次全图")
    chat_plain(CHAT_TAG .. "聊天指令可以关掉：设置项「聊天指令(/forge)」默认关闭，"
        .. "不改聊天也能用「导出当前设置到文件」和「导入设置串(粘贴)」")
end

local function chat_export(rest)
    local all = (rest == "all") or (rest == "ALL") or (rest == " -all")
    local ok, s, n = export_to_file(all)
    if n == 0 then
        chat_print("没有与默认值不同的设置项（用 /forge export all 导出全量）")
        return
    end
    if not ok then
        chat_print("导出失败：写 " .. EXPORT_FILE .. " 出错（模组私有目录不可写）")
        return
    end
    chat_print(string.format("导出 %d 项%s，共 %d 个字符，已落盘 %s（位于 %s）",
        n, all and "（全量）" or "", #s, EXPORT_FILE, EXPORT_DIR))
    -- 聊天分片只是便利输出（粘贴导入通道不需要分片；能走到这里说明聊天指令已开）
    print_shards(s)
end

-- 应用一条 k=v（未知 key / 类型不符 / 越界都计入 ignored）
--   ★ v2.0.1：import_string / export_now 是「通道本身」，不接受被导入（否则一条串可以自嵌套
--     触发下一轮导入，来回打转）。
local function apply_one_setting(raw, k, v)
    if k == "import_string" or k == "export_now" then return nil, false end
    local lim = LIMITS[k]
    local def = DEFAULTS[k]
    if lim then
        local num = tonumber(v)
        if not num then return nil, false end
        num = math.floor(num)
        if num < lim[1] then num = lim[1] end
        if num > lim[2] then num = lim[2] end
        local lit = string.format("%d", num)
        local out = patch_config_key(raw, k, lit)
        if not out then return nil, false end
        return out, true
    end
    if type(def) == "boolean" then
        local lit
        if v == "true" then lit = "true"
        elseif v == "false" then lit = "false"
        else return nil, false end
        local out = patch_config_key(raw, k, lit)
        if not out then return nil, false end
        return out, true
    end
    if STR_KEYS[k] ~= nil then
        local out = patch_config_key(raw, k, '"' .. tostring(unesc(v)):gsub('"', '\\"') .. '"')
        if not out then return nil, false end
        return out, true
    end
    return nil, false
end

local function chat_import(payload)
    local body = payload
    -- 分片：片首 [i/n]
    local i, n, rest = body:match("^%[(%d+)/(%d+)%]%s*(.*)$")
    if i and n then
        i, n = tonumber(i), tonumber(n)
        if n < 1 or n > 64 or i < 1 or i > n then
            chat_print("分片标号非法，已忽略")
            return
        end
        if rest:find("^forge:") then
            local slug = rest:match("^forge:([%w_%-]+)|")
            if slug and slug ~= PKG_SLUG then
                return                      -- 不是本模组的串，静默忽略（其他工坊处理）
            end
            if shard_slug ~= PKG_SLUG then shards, shard_slug, shard_need = {}, PKG_SLUG, n end
            if n ~= shard_need then shards = {} end
            shard_need = n
        end
        shards[i] = rest
        local missing
        for k = 1, shard_need do
            if not shards[k] then missing = k break end
        end
        if missing then
            chat_print(string.format("已收到第 %d/%d 片，缺第 %d 片", i, shard_need, missing))
            return
        end
        local parts = {}
        for k = 1, shard_need do parts[#parts + 1] = shards[k] end
        shards = {}
        chat_import(table.concat(parts))
        return
    end

    if not body:find("^forge:") then return end
    local slug, kv, sum = body:match("^forge:([%w_%-]+)|(.*)|#(%x+)$")
    if not slug then
        chat_print("设置串格式不对：应为 forge:<slug>|<k>=<v>;…|#<sum>")
        return
    end
    if slug ~= PKG_SLUG then return end       -- 不是本模组的串
    local head = body:sub(1, body:len() - (#sum + 2))
    local real = checksum(head)
    if real ~= sum then
        chat_print(string.format("校验和不符（串里是 %s，算出来是 %s），已拒绝", sum, real))
        return
    end

    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then
        chat_print("读不到 config.json，导入中止（没有改动任何设置）")
        return
    end
    local applied, ignored, failed = 0, 0, 0
    for pair in kv:gmatch("[^;]+") do
        local k, v = pair:match("^([%w_]+)=(.*)$")
        if k then
            local out, ok = apply_one_setting(raw, k, v)
            if ok then raw = out applied = applied + 1
            elseif LIMITS[k] or DEFAULTS[k] ~= nil then failed = failed + 1
            else ignored = ignored + 1 end
        end
    end
    if applied == 0 then
        chat_print(string.format("没有可应用的项（忽略 %d 项 / 失败 %d 项），设置未改动",
            ignored, failed))
        return
    end
    local okw, errw = pcall(mod.write_file, "config.json", raw)
    if not okw or errw == false then
        chat_print("写 config.json 失败：" .. tostring(errw) .. "（设置未改动）")
        return
    end
    -- 立即生效：重算内存里的 cfg 与写入计划
    last_raw = nil
    pcall(read_config)
    build_plans()
    pcall(refresh_debuff_table)
    chat_print(string.format("已导入 %d 项（忽略 %d 项 / 失败 %d 项），已立即生效",
        applied, ignored, failed))
    return true
end

-- ---- §9.3 默认（零聊天依赖）通道之一：一次性导出开关 export_now ----
--   打开 → 落盘 + 播报 → 自动写回 false（不会每个节拍重复导出）。
--   与 hot_reload 无关：这是聊天路径不可用时的官方替代通道。
local export_seen = nil
tick_export_now = function()
    if cfg.export_now ~= true then export_seen = nil return end
    if export_seen then return end
    export_seen = true
    local ok = export_to_file(false)
    -- 自动关掉开关：就地改写 config.json，只替换 export_now 的字面量
    local raw = mod.read_file("config.json")
    if type(raw) == "string" and raw ~= "" then
        local out = patch_config_key(raw, "export_now", "false")
        if out and out ~= raw then
            if pcall(mod.write_file, "config.json", out) then last_raw = out end
        end
    end
    cfg.export_now = false
    if ok then
        chat_print("已按「导出当前设置到文件」导出到 " .. EXPORT_FILE
            .. "（位于 " .. EXPORT_DIR .. "）；该开关已自动关闭")
    else
        chat_print("导出失败：写 " .. EXPORT_FILE .. " 出错（模组私有目录不可写）")
    end
end

-- 找到 "key": 后面那个字符串字面量的内容起止位置（只处理字符串值）
local function find_value_span(raw, key)
    local e = key:gsub("([^%w])", "%%%1")
    local _, quote_at = raw:find('"' .. e .. '"%s*:%s*"')
    if not quote_at then return nil end
    local i, n = quote_at + 1, #raw
    while i <= n do
        local c = raw:sub(i, i)
        if c == "\\" then i = i + 2
        elseif c == '"' then return quote_at + 1, i - 1 end
        i = i + 1
    end
    return nil
end

-- 就地把一个 STRING 设置项清空成 ""（只替换这个字面量，其它一个字符都不动）
local function clear_string_setting(key)
    local raw = mod.read_file("config.json")
    if type(raw) ~= "string" or raw == "" then return false end
    local vs, ve = find_value_span(raw, key)
    if not vs then return false end
    local out = raw:sub(1, vs - 1) .. '""' .. raw:sub(ve + 1)
    if out == raw then return false end
    local okw = pcall(mod.write_file, "config.json", out)
    if okw then last_raw = out end
    return okw
end

-- ---- §9.3 默认（零聊天依赖）通道之二：设置项 import_string（粘贴导入） ----
--   玩家把导出的串整串粘贴进 TEFManager 的设置项即可；校验 → 就地改写 config.json
--   → 播报结果 → 自动清空该设置项。单机与客机都能用，完全不经过聊天系统。
local import_seen = nil
tick_import_string = function()
    local body = tostring(cfg.import_string or "")
    if body == "" then import_seen = nil return end
    if body == import_seen then return end       -- 同一条串只处理一次，不刷屏
    import_seen = body
    diag_note(string.format("import_string 通道：收到 %d 字符的串，开始导入", #body))
    local ok = chat_import(body)                 -- 校验和 / 格式 / 应用 / 播报都在里面
    if ok then
        -- 成功才清空（失败留着让玩家自己改）；就地改写，只替换这一个字面量
        if clear_string_setting("import_string") then
            diag_note("import_string 通道：导入成功，设置项已清空")
        end
        cfg.import_string = ""
        import_seen = nil
    end
end

local function handle_chat_command(text)
    if type(text) ~= "string" then return end
    local t = text
    -- 允许前后空格；命令名大小写不敏感；前导 / 可省
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = t:match("^/?(%S+)%s*(.*)$")
    if not cmd then return end
    if cmd:lower() ~= "forge" then return end
    local sub, arg = rest:match("^(%S*)%s*(.*)$")
    sub = (sub or ""):lower()
    if sub == "" or sub == "help" then
        chat_help()
    elseif sub == "stat" then
        diag_report()
    elseif sub == "check" then
        self_check_broadcast()
    elseif sub == "export" then
        chat_export(arg)
    elseif sub == "import" then
        if (arg or ""):lower() == "reset" then
            shards, shard_need, shard_slug = {}, 0, nil
            chat_print("已清空分片缓存")
        elseif arg == "" then
            chat_print("用法：/forge import <设置串>，或 /forge import reset")
        else
            chat_import(arg)
        end
    elseif sub == "map" then
        map_pending = true
        chat_print("已排入点亮队列，本帧稍后执行")
    else
        chat_print("未知子命令 " .. sub .. "（用 /forge help 看命令表）")
    end
end

-- ---- §9.2：聊天命令的唯一入口 ----
--   Terraria.Chat.Commands.SayChatCommand.ProcessIncomingMessage(string text, byte clientId)
--   它是 ChatInitializer 注册的 _defaultCommand：普通聊天与任何「未知 /命令」的原文都会
--   原样送到这里，**参数全是标量**。prefix 返回 true = 跳过原方法（顺手不让 /forge 被
--   当普通聊天广播出去）。
--   ★★ 绝不触达 Terraria.Chat 的消息对象类型（聊天消息类）：v2.0.0 反射它的
--      get_Text / <Text>k__BackingField 在真机上把整个进程打死了（原生崩溃，pcall 拦不住）。
--      本函数只吃 string + number，不做任何消息对象的反射。
local function on_say_chat(inst, args, result)
    if not ready or not args then return nil end
    local text = args[1]
    if type(text) ~= "string" then return nil end
    local d = DOMAIN["聊天命令"]
    if d then d.calls = d.calls + 1 end
    -- 只处理本机玩家：args[2] 是 clientId（byte），Main.myPlayer 是属性 → 走 getter
    local id = args[2]
    if type(id) == "number" then
        local my = my_index
        if my < 0 then
            refresh_my_index()
            my = my_index
        end
        if my >= 0 and math.floor(id) ~= math.floor(my) then return nil end
    end
    -- 只认本模组的输入：/forge … 命令，或直接粘一整条 forge:… 设置串；其它聊天原样放行
    local head = text:gsub("^%s+", "")
    local first = head:match("^/?(%S+)")
    local is_cmd = first and first:lower() == "forge"
    local is_str = head:sub(1, 6) == "forge:"
    if not is_cmd and not is_str then return nil end
    if d then d.hits = d.hits + 1 end
    diag_note("[chat] 收到 " .. (is_cmd and "/forge 命令" or "设置串") .. "：" .. head:sub(1, 80))
    local ok, err
    if is_cmd then
        ok, err = pcall(handle_chat_command, text)
    else
        ok, err = pcall(chat_import, head)      -- 直接粘一整条串 = 导入
    end
    if not ok then log_warn("cb_chat", "聊天入口处理异常：" .. tostring(err)) end
    return true
end

local function on_armor_sets(inst, args, result)
    on_main(inst, args, result)
end

local function on_reset_effects(inst, args, result)
    if not ready or not inst or menu_flag then return end
    if not P.active_reset then return end
    if not is_local(inst) then return end
    -- ★ §3.3 / §3.4：仆从位 / 哨兵位倍率、鞭子 useTime / range 倍率 —— 原版在
    --   Player.ResetEffects 里把它们重置，**只有 postfix 写才不会被覆盖**。
    ensure_net_mode()
    if is_client() then return end
    local ok, err = pcall(run_plan, P.reset, inst)
    if not ok then
        log_warn("cb_reset", "ResetEffects 回调异常：" .. tostring(err))
    end
end

-- ---- §4.2-⑤ 无敌帧：Player.UpdateImmunity 的 postfix ----
--   原版每帧把 immuneTime 减 1（PC 源码 18974），这里把目标值夹到
--   「原版值 × 倍率 + 加值」，天然幂等（不会每帧再加一次）。
--   ⚠️ 联机时无敌帧由服务器判定；扣血请求仍会被服务器按原版冷却处理。
local function on_update_immunity(inst, args, result)
    if not ready or not inst or menu_flag then return end
    if P.immune_mul == 1 and P.immune_add == 0 then return end
    if not is_local(inst) then return end
    ensure_net_mode()
    if is_client() then return end
    local cur = fget("immuneTime", inst)
    if type(cur) ~= "number" or cur <= 0 then return end
    -- 注意：postfix 时原版已经减过 1 了，所以基准要 +1 才是「本帧开始的值」
    local raw = cur + 1
    local t = raw * P.immune_mul + P.immune_add
    t = math.floor(t + 0.5)
    if t > 60000 then t = 60000 end     -- 硬夹，防止误操作把无敌时间设成天文数字
    if t > cur then fset("immuneTime", inst, t) end
end

-- ---- §3.5 min_use_time：Player.ApplyItemAnimation 的 postfix ----
--   ApplyItemAnimation 内部调 SetItemAnimation(item.useAnimation, 攻速倍率)，
--   所以它是本帧 itemAnimationMax 的最终写入点；在这里夹下限最有效。
--   原版 SetItemAnimation 的夹取下限是 1，本模组把它抬到 min_use_time（默认 3）。
local function on_apply_item_animation(inst, args, result)
    if not ready or not inst or menu_flag then return end
    local minv = P.min_use_time or 3
    if minv <= 1 and P.dash_on == 0 then return end
    if not is_local(inst) then return end
    -- itemAnimationMax
    local mx = fget("itemAnimationMax", inst)
    if type(mx) == "number" and mx > 0 and mx < minv then
        fset("itemAnimationMax", inst, minv)
        local a = fget("itemAnimation", inst)
        if type(a) == "number" and a > minv then fset("itemAnimation", inst, minv) end
    end
    -- itemTimeMax（远程/魔法走这一路）
    local tmx = fget("itemTimeMax", inst)
    if type(tmx) == "number" and tmx > 0 and tmx < minv then
        fset("itemTimeMax", inst, minv)
        local t = fget("itemTime", inst)
        if type(t) == "number" and t > minv then fset("itemTime", inst, minv) end
    end
end

-- ---- §4.2-⑨ 自动使用 / 自动挥砍：Player.ItemCheck 的 prefix ----
--   参考 参考库/lua/auto-fisher 的手法：prefix 里直接置 controlUseItem = true，
--   让原版 ItemCheck 自己完成挥砍/抛竿/收线（鱼饵消耗、NPC 生成全走原版逻辑）。
--   返回 false = 继续执行原方法（本模组绝不接管原方法）。
--   ★ 本模组不自动收杆：原版 ItemCheck 会在鱼上钩时自己收线并交鱼。
local function on_item_check(inst, args, result)
    if not ready or not inst or menu_flag or not P.auto_cast then return false end
    if not is_local(inst) then return false end
    fset("controlUseItem", inst, true)
    return false
end

-- ---- §4.2-⑩ 拾取范围：Player.GetItemGrabRange(Item) 的 postfix（override_result）----
--   v1.1.0 因为 Player.defaultItemGrabRange 是 const 而放弃；
--   v2.0.0 改挂这个 1 参公有方法（手机版 dump.cs:62604），直接放大它的返回值。
--      最终 = 原版返回值 × 倍率/100 + (加值 − 1)
local function on_get_grab_range(inst, args, result)
    if type(result) ~= "number" then return nil end
    if P.grab_mul == 1 and P.grab_add == 0 then return nil end
    local t = result * P.grab_mul + P.grab_add
    if t < 1 then t = 1 end
    if t > 100000 then t = 100000 end
    t = math.floor(t + 0.5)
    if t == result then return nil end
    return t
end

-- ---- §4.2-④ 暴击伤害倍率：NPC.StrikeNPC postfix（override_result）----
--   原版 PC 1.4.5.8 NPC.cs:82067 写死 ×2；
--   本项 100 = 原版 ×2 不变，200 = ×4。
local function on_strike_npc(inst, args, result)
    if type(result) ~= "number" or not args then return nil end
    if P.crit_dmg == 1.0 then return nil end
    local crit = args[4]
    if crit ~= true and crit ~= 1 then return nil end
    local t = result * P.crit_dmg
    if t < 0 then t = 0 end
    if t > 2000000000 then t = 2000000000 end
    t = math.floor(t + 0.5)
    if t == result then return nil end
    return t
end

-- ★ v2.0.1 修正：Player.Hurt 是 8 参签名
--   (damageSource, Damage, hitDirection, pvp, quiet, Crit, cooldownCounter, dodgeable)
--   → crit 在 args[6]，args[4] 是 pvp 标志。v2.0.0 复用了 StrikeNPC 的回调，
--   于是「对玩家的暴击伤害倍率」在 pvp 时被误判成暴击、真正的暴击反而漏掉。
--   另：Hurt 返回值是 double（实际伤害），不做整数取整。
local function on_hurt_player(inst, args, result)
    if type(result) ~= "number" or not args then return nil end
    if P.crit_dmg == 1.0 then return nil end
    local crit = args[6]
    if crit ~= true and crit ~= 1 then return nil end
    local t = result * P.crit_dmg
    if t < 0 then t = 0 end
    if t > 2000000000 then t = 2000000000 end
    if t == result then return nil end
    return t
end

-- ---- §3.6-B 视野缩放：XNAWorldCameraSettings 的 0 参属性 getter ----
--   ★ 谁控制什么（对着 1.4.5.8 手机版反编译 + DeviceVPPICalculator.cs 确认）：
--     PixelScale = 「一个逻辑像素占多少屏幕像素」。ZoomScale 越大 → PixelScale 越大 → 画面越大（放大）。
--     所以：
--       MaxPixelScale（PixelScale 上限）= 放大上限   → 调大 = 双指能放得更大
--       MinPixelScale（PixelScale 下限）= 缩小上限   → 调**小** = 双指能缩得更小（看更多世界）
--     ★ 另有一个硬下限：PC 1.4.5.8 Main.cs:62987 `ForcedMinimumZoom = max(1, …)`，
--       手机版同名字段在 0x9C4，每帧被 max(1,…) 覆盖 → 单写它无效，本模组不碰。
local function on_get_max_pixel_scale(inst, args, result)
    if type(result) ~= "number" then return nil end
    if P.cam_zoomin == 1.0 then return nil end
    local t = result * P.cam_zoomin
    if t < 0.01 then t = 0.01 end
    if t > 1000 then t = 1000 end
    if t == result then return nil end
    return t
end

local function on_get_min_pixel_scale(inst, args, result)
    if type(result) ~= "number" then return nil end
    if P.cam_zoomout == 1.0 then return nil end
    local t = result * P.cam_zoomout
    if t < 0.01 then t = 0.01 end
    if t > 1000 then t = 1000 end
    if t == result then return nil end
    return t
end

local function on_get_max_world_width(inst, args, result)
    if type(result) ~= "number" then return nil end
    if not P.cam_world_bigger or P.cam_zoomout >= 1.0 or P.cam_zoomout <= 0 then return nil end
    local t = math.floor(result / P.cam_zoomout + 0.5)
    if t <= result then return nil end
    if t > 100000 then t = 100000 end
    return t
end

local function on_get_max_world_height(inst, args, result)
    if type(result) ~= "number" then return nil end
    if not P.cam_world_bigger or P.cam_zoomout >= 1.0 or P.cam_zoomout <= 0 then return nil end
    local t = math.floor(result / P.cam_zoomout + 0.5)
    if t <= result then return nil end
    if t > 100000 then t = 100000 end
    return t
end

-- ---- §3.6-B 备选：SpriteViewMatrix.Rebuild() 的 prefix（幂等缩放）----
--   ★ 必须做「每帧只缩一次」保护，否则 Rebuild 被反复调用会指数级缩放。
--   做法：每次缩放后把 _zoom 的目标值记在 rebuild_target 里；下一帧比较「原版本该给的
--   _zoom」与目标值是否相等 —— 相等就直接返回（本帧已经缩过），不等才缩一次并更新目标。
local function on_rebuild(inst, args, result)
    if not P.cam_rebuild or P.cam_zoomout >= 1.0 or P.cam_zoomout <= 0 then return false end
    if not inst or not G.F_view_zoom then return false end
    local f = P.cam_zoomout
    local ok, x, y = pcall(patch.get_field_vec2, G.F_view_zoom, inst)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return false end
    local tgt = rebuild_target[inst]
    if tgt and math.abs(x - tgt[1]) < 1e-6 and math.abs(y - tgt[2]) < 1e-6 then
        return false                       -- ★ 本帧已经缩过，直接放行（幂等保护）
    end
    local nx, ny = x * f, y * f
    if nx < 0.01 then nx = 0.01 end
    if ny < 0.01 then ny = 0.01 end
    if nx > 100 then nx = 100 end
    if ny > 100 then ny = 100 end
    if pcall(patch.set_field_vec2, G.F_view_zoom, inst, nx, ny) then
        rebuild_target[inst] = { nx, ny }
        if G.F_view_needs_rebuild then
            pcall(patch.set_field_value, G.F_view_needs_rebuild, inst, true, "bool")
        end
    end
    return false                           -- 继续执行原 Rebuild
end

-- ---- §3.6 光照：LightingEngine.UpdateLightDecay() 的 postfix ----
--   LightMap 的光照传播是乘法（light *= decay），所以 decay 越接近 1 衰减越弱。
--   穿透强度 p：new = 1 − (1 − old) × (100 − p) / 100
--     p = 0  → new = old（零改动）
--     p = 70 → 每格损失只剩 30%，传播距离约 3 倍
--     p = 99 → 每格损失只剩 1%
--   ⚠️ p = 100 时衰减系数 = 1.0，只保证「已有光不消失」；夜里没有任何光源时依然全黑，
--      要彻底明亮请用「完全夜视」（= 直接写 1.0）+ 玩家身上种光（见下）。
local function apply_light_decay(inst)
    if not inst then return end
    if light_applied_frame == frame_i then return end
    light_applied_frame = frame_i
    -- ★ 不能用「字段句柄非空」做提前返回：句柄是按**类型**缓存在 LIGHT_FIELD 里的，
    --   这里只判实例（fget_lightmap 内部会查表；查不到就返回 nil）。

    local map = fget_lightmap(inst)
    if not map then return end
    if P.light_full then
        write_float_acc(acc_light_air, map, 1.0)
        write_float_acc(acc_light_solid, map, 1.0)
        return
    end
    local p = P.light_pen
    if p <= 0 then return end
    local factor = (100 - p) / 100
    if factor <= 0 then factor = 0.01 end
    local old = read_float_acc(acc_light_air, map)
    if type(old) == "number" then
        write_float_acc(acc_light_air, map, 1.0 - (1.0 - old) * factor)
    end
    old = read_float_acc(acc_light_solid, map)
    if type(old) == "number" then
        write_float_acc(acc_light_solid, map, 1.0 - (1.0 - old) * factor)
    end
end

local function on_engine_light_decay(inst, args, result)
    if inst and not LIGHT_FIELD_KIND[inst] then
        LIGHT_FIELD_KIND[inst] = "Terraria.Graphics.Light.LightingEngine"
    end
    if P.light_full then light_applied_frame = -1 end   -- 完全夜视本身幂等，允许两路都写
    if not ready or P.light_pen <= 0 and not P.light_full then return end
    local ok, err = pcall(apply_light_decay, inst)
    if not ok then log_warn("cb_light", "光照回调异常：" .. tostring(err)) end
end

-- 传统光照引擎（Retro / 快速 / 普通模式）的兜底：手机版 1.4.5.8 的 LegacyLighting
-- 有 _workingLightMap(0x30)，但没有 _negLight/_negLight2/_negLight3
-- （参考库/符号/官方源码-校验.tsv 明确标「字段不存在」）→ 只能走 LightMap 的衰减属性。
local function on_legacy_light_decay(inst, args, result)
    if inst and not LIGHT_FIELD_KIND[inst] then
        LIGHT_FIELD_KIND[inst] = "Terraria.Graphics.Light.LegacyLighting"
    end
    if not ready or P.light_pen <= 0 and not P.light_full then return end
    local ok, err = pcall(apply_light_decay, inst)
    if not ok then log_warn("cb_light2", "传统光照回调异常：" .. tostring(err)) end
end

-- ---- §4.2-⑪ 自动朝向最近敌人（防抖 + 分相位）----
--   只改 Player.direction（Entity.direction, int, 0x38），不碰输入、不代替攻击。
--   防抖：每 (tick_interval × 4) 帧才重算一次目标；目标水平距离 < 8 像素时不动朝向。
local function apply_auto_face(inst)
    if not G.F_npc_array or not G.F_npc_active or not G.F_npc_friendly then return end
    local ok, arr = pcall(patch.get_field_value, G.F_npc_array, nil, "object")
    if not ok or not arr then return end
    local okn, n = pcall(patch.array_length, arr)
    if not okn or type(n) ~= "number" then return end
    local okp, px, py = pcall(patch.get_field_vec2, G.F_entity_position, inst)
    if not okp or type(px) ~= "number" then return end
    local best, bestd = nil, nil
    local limit = n
    if limit > 200 then limit = 200 end
    for i = 0, limit - 1 do
        local npc = patch.array_at(arr, i)
        if npc then
            local ok1, act = pcall(patch.get_field_value, G.F_npc_active, npc, "bool")
            if ok1 and act == true then
                local ok2, fr = pcall(patch.get_field_value, G.F_npc_friendly, npc, "bool")
                if not (ok2 and fr == true) then
                    local ok3, nx, ny = pcall(patch.get_field_vec2, G.F_entity_position, npc)
                    if ok3 and type(nx) == "number" then
                        local dx, dy = nx - px, ny - py
                        local d = dx * dx + dy * dy
                        -- 只考虑屏幕附近（约 1200 像素内），避免被远处怪拉着转
                        if d < 1200 * 1200 and (not bestd or d < bestd) then
                            best, bestd = dx, d
                        end
                    end
                end
            end
        end
    end
    if best == nil then return end
    if math.abs(best) < 8 then return end
    local dir = (best > 0) and 1 or -1
    local cur = fget("direction", inst)
    if cur ~= dir then fset("direction", inst, dir) end
end

-- ============================================================================
-- 7. 生命周期
-- ============================================================================

local hooks = {}

-- ---- §4.6-1 功能域登记表 ----
--   名字 → { 需要登记的句柄数（#sym_warn 条）, 需要装的钩子数 }
--   ★ 只在这里维护一份；sym_n 会在 setup 里按实际登记过的符号数改写。
local DOMAIN_SPEC = {
    { "仆从位倍率",   1 }, { "哨兵位倍率",   1 },
    { "鞭子攻速",     2 }, { "鞭子范围",     2 },
    { "使用时间下限", 2 }, { "地图解锁",     5 },
    { "地图逐格兜底", 2 }, { "视野缩放",     4 },
    { "视野备选缩放", 3 }, { "光照穿透",     3 },
    { "完全夜视",     3 }, { "暴击伤害",     2 },
    { "无敌帧",       1 }, { "药水冷却",     1 },
    { "冲刺祝福",     2 }, { "拾取范围",     1 },
    { "自动使用",     1 }, { "自动朝向敌人", 4 },
    -- ★ v2.0.1：聊天域只在 chat_cmd 打开时才会真的去解析/装钩子（默认关闭）
    { "聊天命令",     2 },
}

-- 域 → 该域用到的字段/属性的符号标签（sym_warn / sym_error 的 tag 前缀），用来算 fields。
-- 这里只登记「本模组主动查过、失败要告警」的符号；注册成功的不产生 sym 记录，
-- 所以 setup 末尾按「登记过的条数 vs 失败条数」反推 ok / partial / fail。
local DOMAIN_SYMBOLS = {
    ["仆从位倍率"] = { "maxMinions" },
    ["哨兵位倍率"] = { "maxTurrets" },
    ["鞭子攻速"] = { "whipUseTimeMultiplier" },
    ["鞭子范围"] = { "whipRangeMultiplier" },
    ["使用时间下限"] = { "itemAnimationMax", "ApplyItemAnimation" },
    ["地图解锁"] = { "Map", "UnlockMapSection", "refreshMap", "maxTilesX", "maxTilesY" },
    ["地图逐格兜底"] = { "GetChunkTile", "WorldMap.Update" },
    ["视野缩放"] = { "MinPixelScale", "MaxPixelScale", "MaxWorldWidth", "MaxWorldHeight" },
    ["视野备选缩放"] = { "Rebuild", "_zoom", "_needsRebuild" },
    ["光照穿透"] = { "LightingEngine.UpdateLightDecay", "_workingLightMap", "LightDecayThroughAir" },
    ["完全夜视"] = { "LegacyLighting.UpdateLightDecay", "LightDecayThroughSolid", "_negLight" },
    ["暴击伤害"] = { "StrikeNPC", "Player.Hurt" },
    ["无敌帧"] = { "immuneTime" },
    ["药水冷却"] = { "potionDelay" },
    ["冲刺祝福"] = { "dash", "dashType" },
    ["拾取范围"] = { "GetItemGrabRange" },
    ["自动使用"] = { "controlUseItem" },
    ["自动朝向敌人"] = { "Main.npc", "NPC.active", "Entity.position", "direction" },
    ["聊天命令"] = { "SayChatCommand", "Main.NewText" },
}

-- hook label 前缀 → 域名字（safe_hook 直接按前缀计数，不用改 20 处调用）
local HOOK_DOMAIN = {
    ["Player.ResetEffects（仆从位/哨兵位/鞭子）"] = "仆从位倍率",
    ["Player.UpdateImmunity（无敌帧）"] = "无敌帧",
    ["Player.ApplyItemAnimation（min_use_time）"] = "使用时间下限",
    ["Player.ItemCheck（自动使用）"] = "自动使用",
    ["Player.GetItemGrabRange（拾取范围）"] = "拾取范围",
    ["Player.GetItemGrabRange（只记命中）"] = "拾取范围",
    ["NPC.StrikeNPC（暴击伤害）"] = "暴击伤害",
    ["NPC.StrikeNPC_Inner（暴击伤害）"] = "暴击伤害",
    ["Player.Hurt（对玩家暴击伤害）"] = "暴击伤害",
    ["SayChatCommand（命令入口）"] = "聊天命令",
    ["LightingEngine.UpdateLightDecay"] = "光照穿透",
    ["LegacyLighting.UpdateLightDecay"] = "完全夜视",
    ["XNAWorldCameraSettings.MaxPixelScale"] = "视野缩放",
    ["XNAWorldCameraSettings.MinPixelScale"] = "视野缩放",
    ["XNAWorldCameraSettings.MaxWorldWidth"] = "视野缩放",
    ["XNAWorldCameraSettings.MaxWorldHeight"] = "视野缩放",
    ["SpriteViewMatrix.Rebuild（备选缩放）"] = "视野备选缩放",
}

local function safe_hook(method, spec, label)
    local dom = HOOK_DOMAIN[label]
    local d = dom and DOMAIN[dom]
    if d then
        d.hook_n = (d.hook_n or 0) + 1
        if not method then d.hook_fail = (d.hook_fail or 0) + 1 end
    end
    if not method then
        -- 方法句柄为空 = 符号取不到：这条 warn 不受 write_log 限制（每个 label 只打一次）
        sym_warn("hooknil_" .. label, "跳过钩子（方法句柄为空）：" .. label)
        return nil
    end
    local ok, h = pcall(patch.install_hook, method, spec)
    if not ok then
        if d then d.hook_fail = (d.hook_fail or 0) + 1 end
        log_warn("hookfail_" .. label, "安装钩子失败 " .. label .. "：" .. tostring(h))
        return nil
    end
    hooks[#hooks + 1] = h
    log_info("钩子已安装：" .. label)
    return h
end

function setup()
    -- ★ 先读一次配置：write_log 总闸从加载阶段就生效（否则 setup 的 info 全被门控）
    pcall(read_config)
    log_info("玩家工坊 阶段 1/5：解析类型")
    diag_note("阶段 1/5 开始")
    T_PLAYER = patch.get_type("Terraria", "Player")
    if not T_PLAYER then
        sym_error("no_player", "找不到 Terraria.Player，玩家工坊未启用")
        return
    end
    T_MAIN = patch.get_type("Terraria", "Main")

    log_info("玩家工坊 阶段 2/5：解析字段（只查元数据，不读值）")
    diag_note("阶段 2/5 开始")
    local nf, miss = 0, 0
    for name, ty in pairs(FIELD_SPEC) do
        if register(name, T_PLAYER, name, ty) then nf = nf + 1 else miss = miss + 1 end
    end
    if T_MAIN then
        -- 手机版这两个都是**属性**：字段注册会失败 → 下面走 get_ 方法桥接
        register("myPlayer", T_MAIN, "myPlayer", "int32")
        register("player", T_MAIN, "player", "object")
        register("gameMenu", T_MAIN, "gameMenu", "bool")
        register("debuff", T_MAIN, "debuff", "object")
        -- ★ Main.netMode 在 1.4.5.8 手机版是 public static int 字段（可读）
        F_net_mode = find_field(T_MAIN, "netMode")
        if not F_net_mode then
            sym_warn("no_netmode", "找不到 Main.netMode，「联机：仅房主生效」退化为不限制")
        end
    end
    -- ★ 手机版 Player.defaultItemGrabRange 是 const（符号表 const=是）：
    --   读出来是 nil、写不进去，拾取范围功能降级不可用（保留设置项以免打乱旧配置）
    sym_warn("const_grab",
        "Player.defaultItemGrabRange 是 const（手机版 1.4.5.8），拾取范围功能不可用")
    log_info(string.format("字段解析完成：%d 个可用，%d 个缺失", nf, miss))
    if not F.statLifeMax2 and not F.moveSpeed and not F.statDefense then
        sym_error("no_fields", "关键字段全部缺失（符号表与本机不匹配），玩家工坊未启用")
        return
    end

    log_info("玩家工坊 阶段 3/5：解析方法")
    diag_note("阶段 3/5 开始")
    if T_MAIN then
        -- 手机版 Main.myPlayer / Main.gameMenu 是属性：优先属性桥接，退回 get_X()
        M_get_my_player = resolve_getter(T_MAIN, "myPlayer", "get_myPlayer")
        M_get_game_menu = resolve_getter(T_MAIN, "gameMenu", "get_gameMenu")
        if not M_get_my_player then
            sym_warn("no_myplayer", "取不到 Main.myPlayer 属性 getter，多玩家过滤退化为不过滤")
        end
        if not M_get_game_menu then
            sym_warn("no_gamemenu", "取不到 Main.gameMenu 属性 getter，主菜单门控退化为不门控")
        end
    end
    -- 1.4.5.8 手机版 Player.AddBuff 只有 3 参重载（int, int, bool）
    M_add_buff = find_method(T_PLAYER, "AddBuff", 3) or find_method(T_PLAYER, "AddBuff", 4)
    if not M_add_buff then sym_warn("no_addbuff", "找不到 Player.AddBuff，免疫减益不可用") end

    log_info("玩家工坊 阶段 4/5：安装钩子")
    diag_note("阶段 4/5 开始")
    -- 钩子1：装备类最终数值。UpdateArmorSets(1) → UpdateEquips(1) → ResetEffects(0) 逐级回退
    local h1 = safe_hook(find_method(T_PLAYER, "UpdateArmorSets", 1),
        { postfix = on_armor_sets }, "Player.UpdateArmorSets")
    if not h1 then
        h1 = safe_hook(find_method(T_PLAYER, "UpdateEquips", 1),
            { postfix = on_armor_sets }, "Player.UpdateEquips（回退）")
    end
    if not h1 then
        h1 = safe_hook(find_method(T_PLAYER, "ResetEffects", 0),
            { postfix = on_armor_sets }, "Player.ResetEffects（回退）")
    end
    if not h1 then
        sym_error("no_main_hook", "主钩子一个都装不上，玩家工坊未启用")
        return
    end

    -- 钩子2：跳跃 + 魔力上限（必须晚于原版把 statManaMax2 夹到 400 的那一行）
    local h2 = safe_hook(find_method(T_PLAYER, "UpdateJumpHeight", 0),
        { postfix = on_jump_height }, "Player.UpdateJumpHeight")
    if not h2 then
        jump_in_main = true
        sym_warn("no_jumpheight",
            "UpdateJumpHeight 钩子不可用：跳跃与魔力上限已并入主钩子（魔力上限受原版 400 限制）")
    end

    -- 钩子3：无限跳 / 无限飞行 / 无限火箭（必须晚于 RefreshDoubleJumps 与 wingsLogic 判定）
    local h3 = safe_hook(find_method(T_PLAYER, "JumpMovement", 0),
        { postfix = on_jump_movement }, "Player.JumpMovement")

    -- 钩子4：魔力回复倍率
    local h4 = safe_hook(find_method(T_PLAYER, "UpdateManaRegen", 0),
        { postfix = on_mana_regen }, "Player.UpdateManaRegen")

    -- 钩子5：免疫减益（在 AddBuff 里直接拦下）
    local h5 = safe_hook(M_add_buff, { prefix = on_add_buff_hook }, "Player.AddBuff")

    log_info("玩家工坊 阶段 5/5：读取设置并生成写入计划")
    diag_note("阶段 5/5 开始")
    -- ---- §4.6-1：先把功能域登记进注册表（sym_warn 已经在这个过程中按 tag 记过失败）----
    for i = 1, #DOMAIN_SPEC do
        local name = DOMAIN_SPEC[i][1]
        local d = dom_new(name)
        local syms = DOMAIN_SYMBOLS[name]
        d.sym_n = (#DOMAIN_SPEC[i] > 1) and DOMAIN_SPEC[i][2] or (syms and #syms or 0)
        if syms then d.sym_total = #syms end
    end
    pcall(read_config)
    build_plans()
    last_cfg_check = os.time() or 0

    local extra = {}
    if not h2 then extra[#extra + 1] = "无跳高钩子" end
    if not h3 then extra[#extra + 1] = "无限跳/无限飞行不可用" end
    if not h4 then extra[#extra + 1] = "魔力回复倍率不可用" end
    if not h5 then extra[#extra + 1] = "免疫减益不可用" end

    log_info("玩家工坊 阶段 4b/5：安装 v2.0.0 新增钩子")
    diag_note("阶段 4b/5 开始")
    local h6, h7, h8, h9, h10, h11 = nil, nil, nil, nil, nil, nil
    local h12, h13, h14, h15, h16, h17, h18 = nil, nil, nil, nil, nil, nil, nil

    -- 钩子6（§3.3/§3.4）：仆从位/哨兵位倍率 + 鞭子字段 —— 必须在 ResetEffects 的 postfix
    h6 = safe_hook(find_method(T_PLAYER, "ResetEffects", 0),
        { postfix = on_reset_effects }, "Player.ResetEffects（仆从位/哨兵位/鞭子）")

    -- 钩子7（§4.2-⑤）：无敌帧倍率
    h7 = safe_hook(find_method(T_PLAYER, "UpdateImmunity", 0),
        { postfix = on_update_immunity }, "Player.UpdateImmunity（无敌帧）")

    -- 钩子8（§3.5）：使用时间下限
    G.M_apply_item_anim = find_method(T_PLAYER, "ApplyItemAnimation", 1)
    h8 = safe_hook(G.M_apply_item_anim,
        { postfix = on_apply_item_animation }, "Player.ApplyItemAnimation（min_use_time）")

    -- 钩子9（§4.2-⑨）：自动使用 / 自动挥砍
    h9 = safe_hook(find_method(T_PLAYER, "ItemCheck", 0),
        { prefix = on_item_check }, "Player.ItemCheck（自动使用）")

    -- 钩子10（§4.2-⑩）：拾取范围 —— 需要 override_result 才能改返回值
    G.M_get_grab_range = nil
    local grab_m = nil
    if patch.get_method_by_names then
        local okg, gm = pcall(patch.get_method_by_names, T_PLAYER, "GetItemGrabRange", { "item" })
        if okg and gm then grab_m = gm end
    end
    if not grab_m and patch.get_method_by_param_types then
        local okg, gm = pcall(patch.get_method_by_param_types, T_PLAYER, "GetItemGrabRange", { "Item" })
        if okg and gm then grab_m = gm end
    end
    if not grab_m then grab_m = find_method(T_PLAYER, "GetItemGrabRange", 1) end
    G.M_get_grab_range = grab_m
    h10 = safe_hook(grab_m, { override_result = true, postfix = on_get_grab_range },
        "Player.GetItemGrabRange（拾取范围）")
    if not h10 and grab_m then
        -- override_result 不被支持（老加载器）：退回只记命中的普通 postfix（返回值改不动）
        h10 = safe_hook(grab_m, { postfix = on_get_grab_range }, "Player.GetItemGrabRange（只记命中）")
        if h10 then G.M_get_grab_range = nil end
    end

    -- 钩子11/12（§4.2-④）：暴击伤害倍率
    G.T_NPC = patch.get_type("Terraria", "NPC")
    if G.T_NPC then
        h11 = safe_hook(find_method(G.T_NPC, "StrikeNPC", 6),
            { override_result = true, postfix = on_strike_npc }, "NPC.StrikeNPC（暴击伤害）")
        if not h11 then
            h11 = safe_hook(find_method(G.T_NPC, "StrikeNPC_Inner", 6),
                { override_result = true, postfix = on_strike_npc }, "NPC.StrikeNPC_Inner（暴击伤害）")
        end
    end
    h12 = safe_hook(find_method(T_PLAYER, "Hurt", 8),
        { override_result = true, postfix = on_hurt_player }, "Player.Hurt（对玩家暴击伤害）")

    -- 钩子13（§9.2）：聊天命令 —— ★ 默认关闭，关闭时一行聊天代码都不执行。
    --   唯一入口 SayChatCommand.ProcessIncomingMessage(string, byte)，参数全是标量。
    --   ★★ 这里**不做**任何聊天子系统的类型/字段/方法反射：v2.0.0 反射聊天消息成员
    --      被真机证实会让整个进程原生崩溃（05-写法与陷阱.md §5.2，唯一实机证据）。
    if chat_cmd_on() then
        local t_say = patch.get_type("Terraria.Chat.Commands", "SayChatCommand")
        if not t_say then t_say = patch.get_type("Terraria.Chat", "SayChatCommand") end
        M_say_chat = t_say and find_method(t_say, "ProcessIncomingMessage", 2) or nil
        h13 = safe_hook(M_say_chat, { prefix = on_say_chat }, "SayChatCommand（命令入口）")
        if h13 then
            log_info("聊天指令已启用（SayChatCommand.ProcessIncomingMessage）")
            diag_note("聊天指令已启用（chat_cmd=true）")
        else
            M_say_chat = nil
            sym_warn("dom:聊天命令:SayChatCommand",
                "聊天指令已打开，但 SayChatCommand.ProcessIncomingMessage(string,byte) 取不到或装不上；"
                .. "请改用「导入设置串(粘贴)」与「导出当前设置到文件」")
        end
    else
        diag_note("聊天指令未启用（chat_cmd=false）：未解析任何聊天类型、未装聊天钩子")
    end
    -- Main.NewText：手机版是 5 参 (string, byte, byte, byte, bool)，桌面端 4 参。
    -- ★ 只用于「游戏内」播报（chat_plain 里有 in_game 门控），启动阶段零反射调用。
    M_new_text = find_method(T_MAIN, "NewText", 5)
    chat_arity = 5
    if not M_new_text then
        M_new_text = find_method(T_MAIN, "NewText", 4)
        chat_arity = 4
    end
    if not M_new_text then
        M_new_text = find_method(T_MAIN, "NewText", 3)
        chat_arity = 3
    end
    if not M_new_text then
        sym_warn("dom:聊天命令:NewText",
            "找不到 Main.NewText，聊天播报与命令回显退化为只写日志")
    end

    -- 钩子15/16（§3.6）：光照
    G.T_ENGINE = patch.get_type("Terraria.Graphics.Light", "LightingEngine")
    G.T_LEGACY = patch.get_type("Terraria.Graphics.Light", "LegacyLighting")
    G.T_LIGHTMAP = patch.get_type("Terraria.Graphics.Light", "LightMap")
    if G.T_LIGHTMAP then
        acc_light_air = resolve_float_acc(G.T_LIGHTMAP, "LightDecayThroughAir")
        acc_light_solid = resolve_float_acc(G.T_LIGHTMAP, "LightDecayThroughSolid")
        if not acc_light_air then
            sym_warn("dom:光照穿透:LightDecayThroughAir",
                "取不到 LightMap.LightDecayThroughAir 的读写通道，光照穿透不可用")
        end
    else
        sym_warn("dom:光照穿透:LightMap", "找不到 Terraria.Graphics.Light.LightMap，光照穿透不可用")
    end
    if not G.T_ENGINE then
        sym_warn("dom:光照穿透:LightingEngine", "找不到 LightingEngine，光照穿透不可用")
    end
    if not G.T_LEGACY then
        sym_warn("dom:完全夜视:LegacyLighting", "找不到 LegacyLighting，传统光照路径不可用")
    end
    if G.T_ENGINE then
        G.F_engine_light_map = find_field(G.T_ENGINE, "_workingLightMap")
        if G.F_engine_light_map then
            LIGHT_FIELD["Terraria.Graphics.Light.LightingEngine"] = G.F_engine_light_map
        end
        G.M_engine_decay = find_method(G.T_ENGINE, "UpdateLightDecay", 0)
    end
    if G.T_LEGACY then
        G.F_legacy_light_map = find_field(G.T_LEGACY, "_workingLightMap")
        if G.F_legacy_light_map then
            LIGHT_FIELD["Terraria.Graphics.Light.LegacyLighting"] = G.F_legacy_light_map
        end
        G.M_legacy_decay = find_method(G.T_LEGACY, "UpdateLightDecay", 0)
    end
    h15 = safe_hook(G.M_engine_decay, { postfix = on_engine_light_decay }, "LightingEngine.UpdateLightDecay")
    h16 = safe_hook(G.M_legacy_decay, { postfix = on_legacy_light_decay }, "LegacyLighting.UpdateLightDecay")

    -- 钩子17（§3.6-B）：视野缩放（0 参属性 getter）
    G.T_CAMERA = patch.get_type("", "XNAWorldCameraSettings")
    if not G.T_CAMERA then G.T_CAMERA = patch.get_type(nil, "XNAWorldCameraSettings") end
    if not G.T_CAMERA and patch.get_type_by_name then
        local okc, v = pcall(patch.get_type_by_name, "XNAWorldCameraSettings")
        if okc then G.T_CAMERA = v end
    end
    if not G.T_CAMERA then
        sym_warn("dom:视野缩放:XNAWorldCameraSettings",
            "找不到 XNAWorldCameraSettings，视野缩放不可用")
    end
    if G.T_CAMERA then
        G.M_zoom_in = resolve_getter(G.T_CAMERA, "MaxPixelScale", "get_MaxPixelScale")
        G.M_zoom_out = resolve_getter(G.T_CAMERA, "MinPixelScale", "get_MinPixelScale")
        G.M_world_w = resolve_getter(G.T_CAMERA, "MaxWorldWidth", "get_MaxWorldWidth")
        G.M_world_h = resolve_getter(G.T_CAMERA, "MaxWorldHeight", "get_MaxWorldHeight")
    end
    h17 = safe_hook(G.M_zoom_in, { override_result = true, postfix = on_get_max_pixel_scale },
        "XNAWorldCameraSettings.MaxPixelScale")
    safe_hook(G.M_zoom_out, { override_result = true, postfix = on_get_min_pixel_scale },
        "XNAWorldCameraSettings.MinPixelScale")
    safe_hook(G.M_world_w, { override_result = true, postfix = on_get_max_world_width },
        "XNAWorldCameraSettings.MaxWorldWidth")
    safe_hook(G.M_world_h, { override_result = true, postfix = on_get_max_world_height },
        "XNAWorldCameraSettings.MaxWorldHeight")

    -- 钩子18（§3.6-B 备选）：SpriteViewMatrix.Rebuild（幂等缩放）
    G.T_VIEWMATRIX = patch.get_type("Terraria.Graphics", "SpriteViewMatrix")
    if G.T_VIEWMATRIX then
        G.F_view_zoom = find_field(G.T_VIEWMATRIX, "_zoom")
        G.F_view_needs_rebuild = find_field(G.T_VIEWMATRIX, "_needsRebuild")
        G.M_view_rebuild = find_method(G.T_VIEWMATRIX, "Rebuild", 0)
    end
    safe_hook(G.M_view_rebuild, { prefix = on_rebuild }, "SpriteViewMatrix.Rebuild（备选缩放）")

    -- ---- §3.6-A 点亮全图：符号 ----
    if T_MAIN then
        G.F_map_getter = resolve_getter(T_MAIN, "Map", "get_Map")
        G.M_set_refresh_map = resolve_setter(T_MAIN, "refreshMap", "set_refreshMap")
        G.F_main_max_tiles_x = find_field(T_MAIN, "maxTilesX")
        G.F_main_max_tiles_y = find_field(T_MAIN, "maxTilesY")
        G.F_main_max_sections_x = find_field(T_MAIN, "maxSectionsX")
        G.F_main_max_sections_y = find_field(T_MAIN, "maxSectionsY")
        -- ★ 这几个是 public static const：读 const 会拿到 nil + 内核警告（硬规则 #2），
        --   所以先确证 field_is_const 为 false 才登记。
        local function drop_const(f, label)
            if not f then return nil end
            if patch.field_is_const then
                local okc, c = pcall(patch.field_is_const, f)
                if okc and c == true then
                    sym_warn("dom:地图解锁:" .. label,
                        "Main." .. label .. " 是 const，改用其他方式推算地图段数")
                    return nil
                end
            end
            return f
        end
        G.F_main_max_sections_x = drop_const(G.F_main_max_sections_x, "maxSectionsX")
        G.F_main_max_sections_y = drop_const(G.F_main_max_sections_y, "maxSectionsY")
        G.F_main_max_tiles_x = drop_const(G.F_main_max_tiles_x, "maxTilesX")
        G.F_main_max_tiles_y = drop_const(G.F_main_max_tiles_y, "maxTilesY")
    end
    local T_WORLDMAP = patch.get_type("Terraria.Map", "WorldMap")
    if T_WORLDMAP then
        G.M_unlock_section = find_method(T_WORLDMAP, "UnlockMapSection", 2)
        G.M_map_get_chunk_tile = find_method(T_WORLDMAP, "GetChunkTile", 3)
        G.M_map_update = find_method(T_WORLDMAP, "Update", 3)
    end

    -- ---- §4.2-⑪ 自动朝向：符号 ----
    G.F_npc_array = T_MAIN and find_field(T_MAIN, "npc")
    G.F_npc_active = G.T_NPC and find_field(G.T_NPC, "active")
    G.F_npc_friendly = G.T_NPC and find_field(G.T_NPC, "friendly")
    G.F_npc_life = G.T_NPC and find_field(G.T_NPC, "life")
    G.T_ENTITY = patch.get_type("Terraria", "Entity")
    G.F_entity_position = G.T_ENTITY and find_field(G.T_ENTITY, "position")
    -- direction / velocity 在父类 Entity 上
    for name, ty in pairs(ENTITY_FIELDS) do
        register(name, T_PLAYER, name, ty)
    end

    pcall(read_config)
    build_plans()
    last_cfg_check = os.time() or 0

    -- ---- §4.6-1：把每个域的装载状态汇总进诊断注册表 ----
    --   sym_warn/sym_error 已经在 setup 期间把 "dom:<域>:<子项>" 的失败记进 d.sym_fail，
    --   这里读回来算 fields/methods；hooks 用 hook_n / hook_fail 直接算。
    for i = 1, #DOMAINS do
        local d = DOMAINS[i]
        if d.sym_n then
            if d.sym_fail and d.sym_fail > 0 then
                d.fields = (d.sym_fail >= d.sym_n) and "fail" or "partial"
            else
                d.fields = "ok"
            end
        end
        if d.hook_n then
            if (d.hook_fail or 0) > 0 then
                d.hooks = ((d.hook_fail or 0) >= d.hook_n) and "fail" or "partial"
            else
                d.hooks = "ok"
            end
        end
        if d.hook_n and d.hook_n > 0 then
            d.methods = (d.hooks == "ok") and "ok" or d.hooks
        end
    end

    local extra = {}
    if not h2 then extra[#extra + 1] = "无跳高钩子" end
    if not h3 then extra[#extra + 1] = "无限跳/无限飞行不可用" end
    if not h4 then extra[#extra + 1] = "魔力回复倍率不可用" end
    if not h5 then extra[#extra + 1] = "免疫减益不可用" end
    if not h6 then extra[#extra + 1] = "仆从位/哨兵位/鞭子不可用" end
    if not h7 then extra[#extra + 1] = "无敌帧不可用" end
    if not h8 then extra[#extra + 1] = "使用时间下限不可用" end
    if not h9 then extra[#extra + 1] = "自动使用不可用" end
    if not h10 then extra[#extra + 1] = "拾取范围不可用" end
    if not (h11 or h12) then extra[#extra + 1] = "暴击伤害倍率不可用" end
    if not M_new_text then extra[#extra + 1] = "聊天播报不可用" end
    if not acc_light_air then extra[#extra + 1] = "光照穿透不可用" end
    if not G.M_zoom_out then extra[#extra + 1] = "视野缩放不可用" end
    if not G.M_unlock_section then extra[#extra + 1] = "点亮全图不可用" end

    ready = true
    local extra_text = (#extra > 0) and ("（" .. table.concat(extra, "，") .. "）") or ""
    log_info(string.format(
        "玩家工坊 v" .. tostring(mod.meta.version) .. " 已启用：主计划 %d 项 / 跳跃计划 %d 项 / 重置计划 %d 项 / 开关 %d 个%s；"
        .. "重读间隔 %d 秒，非关键项间隔 %d 帧",
        #P.main, #P.jump, #P.reset, #P.bools, extra_text,
        cfg.config_reload_sec, cfg.tick_interval))
    if not cfg.enabled then
        log_info("总开关当前为关：本模组不会改写任何数值")
    end
    diag_note(string.format("setup 完成：钩子 %d 个，主计划 %d 项，chat_cmd=%s，crash_log=%s",
        #hooks, #P.main, tostring(cfg.chat_cmd), tostring(cfg.crash_log)))
    pcall(diag_flush)
end

function cleanup()
    ready = false
    -- 还原「游戏不会每帧重置」的字段
    if last_inst then pcall(restore_bases, last_inst) end
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
    F, ST, FT, PM = {}, {}, {}, {}
    BASE = {}
    debuff_arr, debuff_len = nil, 0
    world_entered = false
    last_inst = nil
    net_mode_ready = false
    -- v2.0.0 新增状态
    rebuild_target = {}
    LIGHT_FIELD, LIGHT_FIELD_KIND = {}, {}
    light_applied_frame = -1
    shards, shard_need, shard_slug = {}, 0, nil
    map_pending, map_running, map_done = false, false, false
    map_sec_total, map_sec_i = 0, 0
    auto_face_slot = 0
    self_check_pending, self_check_done = false, false
    -- v2.0.1 新增状态
    export_seen, import_seen = nil, nil
    DIAG.ring, DIAG.n, DIAG.dirty, DIAG.last_body = {}, 0, false, nil
    if G.M_set_refresh_map then invoke_static(G.M_set_refresh_map, true) end
    log_info("玩家工坊已卸载")
    diag_note("玩家工坊已卸载")
end

mod.cleanup = cleanup
-- ============================================================================
-- 22. 游戏内图形面板（LuaLoader 1.9.0 的 mod.gui / mod.on_gui）
-- ----------------------------------------------------------------------------
-- 只做面板，不改任何游戏逻辑：面板只改运行时 cfg，绝不写 TEFManager 设置。
-- 视觉基线 v2.3.1：羊皮纸底 + 九宫格卡片 + 页签下划线 + 奇偶行条纹；
-- 本模组强调色取「金褐」，与属性工坊（铜橙）/ 药水工坊（紫罗兰）区分。
--
-- 纪律（19 章 §1.3 的 21 条 + 16 章 §3）：
--   · 每帧第一行 set_content_height；整帧 pcall，异常写状态页；
--   · 首帧不 set_pos，第 2 帧起零游戏符号测屏；
--   · 根上下文不发流式控件；长内容进 begin_scroll（1.9.0）或分页（老加载器）；
--   · 颜色永远是真表，长文本一律 fit() 截断；
--   · 属性页只读：绝不 set_field_value；反射全 pcall；取不到返回 nil（显示「不可用」）；
--   · 属性页最多每 6 帧刷新一次缓存；
--   · 客机（netMode == 1）隐藏「回满血魔 / 点亮全图」，并明确标注「仅房主」。
-- ============================================================================
local function playerforge_gui_install()
local GUI = {}
PLAYERFORGE_GUI = GUI

local GUI_STATE_FILE = "playerforge-gui.txt"
local GUI_PAGES = { "状态", "属性", "参数", "一键", "关于" }
local GUI_BIG = 999999.0

-- 羊皮纸底 + 本模组强调色：金褐（worldforge 朱红 / buffstack 紫罗兰 / itemforge 铜橙）
local GC = {
    panel  = { 240, 228, 200, 246 },
    title  = { 236, 222, 194, 255 },
    button = { 214, 194, 158, 255 },
    hover  = { 234, 216, 176, 255 },
    active = { 176, 142, 92, 255 },
    border = { 74, 46, 20, 255 },
    text   = { 58, 38, 18, 255 },
    accent = { 142, 96, 32, 255 },
    gold   = { 156, 112, 44, 255 },
    muted  = { 108, 86, 58, 255 },
    ok     = { 74, 108, 46, 255 },
    warn   = { 168, 40, 32, 255 },
    bad    = { 168, 40, 32, 255 },
    white  = { 255, 255, 255, 255 },
    invis  = { 255, 255, 255, 0 },
    row_a  = { 228, 214, 184, 255 },
    row_b  = { 236, 224, 198, 255 },
    dim    = { 0, 0, 0, 150 },
}

local GP = { frames = 0, phase = 0, done = false, unclamped = false,
             x_max = 0, y_max = 0, screen_w = 0, screen_h = 0, g = 1.0,
             budget = 380.0, saved_x = 24, saved_y = 24, width = 0,
             pos_applied = false, page_h = 380.0 }
local GUI_GROUPS, GUI_META   -- 前向声明：状态读写与页面构建都要用
local GS = { tab = 1, pg = {}, fold = {}, edit = nil, buf = "",
             exp_text = "", exp_show = false, msg = "", log = {},
             selfcheck = nil, confirm_key = nil }
local IMG, IMG_TRIED = {}, false
local GUI_INIT = false
local VX, VW = 0, 400
local GUI_CW, GUI_PAD = 0, 0   -- 本帧内容区宽 / 加载器留白（测试断言左右等距用）

GUI.last_err = ""
GUI.err_n = 0
GUI.api_have = 0
GUI.api_missing = ""
GUI.keys_n = 0
GUI.keys_hash = 0

-- ============ 22.1 基础工具（内联 ui_kit 的最小集，单文件内联，不做模块拆分） ============
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
    if maxu <= 2 then return ".." end
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

-- ============ 22.2 主题 / 图片 / 屏幕探测 ============
local function apply_theme()
    if not has("set_style") then return end
    api("set_style", { panel = GC.panel, title = GC.title, button = GC.button,
                       hover = GC.hover, active = GC.active, border = GC.border,
                       text = GC.text })
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
    if not has("get_pos") or not has("set_pos") then
        GP.done = true
        return
    end
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
            if GP.budget < 220 then GP.budget = 220 end
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

-- ============ 22.3 状态落盘（只记面板自己的东西，不写 TEFManager 设置） ============
local function gui_state_write()
    if GP.done and not GP.unclamped and has("get_pos") then
        local ok, x, y = api("get_pos")
        if ok and type(x) == "number" and type(y) == "number" then
            GP.saved_x, GP.saved_y = x, y
        end
    end
    -- ★ 安全阀（2026-10-23）：属性页曾因主菜单 nil 实例实机 SIGSEGV；在属性页实机验证前，
    --   不把「属性页」写进状态文件，崩溃后重启一定回到状态页，避免开场即崩的死循环。
    local tab = GS.tab
    if tab == 2 then tab = 1 end
    local lines = { "tab=" .. tostring(tab),
                    "x=" .. tostring(math.floor(num(GP.saved_x, 24))),
                    "y=" .. tostring(math.floor(num(GP.saved_y, 24))) }
    for i = 1, #GUI_PAGES do
        lines[#lines + 1] = "pg" .. i .. "=" .. tostring(GS.pg[i] or 1)
    end
    for i = 1, #GUI_GROUPS do
        lines[#lines + 1] = "fold" .. i .. "=" .. (GS.fold[i] and "true" or "false")
    end
    local ok = mod.write_file(GUI_STATE_FILE, table.concat(lines, string.char(10)))
    return ok ~= false
end

local function gui_state_read()
    local raw = mod.read_file(GUI_STATE_FILE)
    if type(raw) ~= "string" or raw == "" then return false end
    for line in raw:gmatch("[^" .. string.char(10) .. "]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then
            if k == "tab" then
                GS.tab = math.max(1, math.min(#GUI_PAGES, math.floor(num(v, 1))))
            elseif k == "x" then
                GP.saved_x = num(v, GP.saved_x)
            elseif k == "y" then
                GP.saved_y = num(v, GP.saved_y)
            elseif k:match("^pg%d+$") then
                local i = tonumber(k:sub(3))
                if i and i >= 1 and i <= #GUI_PAGES then
                    GS.pg[i] = math.max(1, math.floor(num(v, 1)))
                end
            elseif k:match("^fold%d+$") then
                local i = tonumber(k:sub(5))
                if i and i >= 1 and i <= #GUI_GROUPS then GS.fold[i] = (v == "true") end
            end
        end
    end
    if GS.tab == 2 then GS.tab = 1 end   -- 安全阀：旧状态文件停在属性页时先回状态页
    return true
end

-- ============ 22.4 参数页：8 组（键必须把所有 DEFAULTS 恰好覆盖一次） ============
GUI_GROUPS = {
    { name = "生存", keys = {
        "life_max_mult", "life_max_add", "life_regen_mult", "life_full",
        "mana_max_mult", "mana_max_add", "mana_regen_mult", "mana_cost_mult", "mana_full",
        "water_breathing", "lava_immune", "fire_walk", "breath_max_mult", "debuff_immune",
        "extra_accessory", "potion_cooldown_mult", "immune_time_mult", "immune_time_add",
    } },
    { name = "移动", keys = {
        "move_speed_mult", "move_speed_add", "jump_speed_mult", "jump_height_mult",
        "gravity_mult", "dash_on", "auto_jump", "ignore_water", "ice_skate", "water_walk",
        "no_fall_damage", "no_knockback", "infinite_flight", "flight_time_mult",
        "infinite_jump", "infinite_rocket", "empress_brooch",
    } },
    { name = "战斗", keys = {
        "damage_all_mult", "melee_damage_mult", "ranged_damage_mult", "magic_damage_mult",
        "summon_damage_mult", "melee_speed_mult", "whip_speed", "whip_speed_add",
        "whip_range", "whip_range_add", "crit_add", "armor_pen_add", "minion_mult",
        "minion_add", "turret_mult", "turret_add", "crit_damage_mult", "ammo_save",
        "min_use_time",
    } },
    { name = "防御与减伤", keys = {
        "god_mode", "shadow_dodge", "defense_mult", "defense_add", "endurance_add",
        "thorns_add", "aggro_add",
    } },
    { name = "视野与光照", keys = {
        "night_vision", "detect_creature", "detect_treasure", "danger_sense", "calmed",
        "invis", "grav_control", "acc_flipper", "camera_zoomout", "camera_zoomin",
        "camera_world_bigger", "camera_rebuild_zoom", "light_full_night", "light_penetration",
    } },
    { name = "自动操作", keys = {
        "auto_cast", "auto_fish_reel", "auto_face_enemy", "auto_aim",
        "pick_speed_mult", "tile_speed_mult", "wall_speed_mult", "fishing_add",
        "tile_range_mult", "tile_range_add", "grab_range_mult", "grab_range_add", "luck_add",
    } },
    { name = "联机与日志", keys = {
        "enabled", "host_only", "write_log", "debug_log", "crash_log", "chat_cmd",
        "self_check", "diag_report_cmd", "diag_slow_ms", "hot_reload", "config_reload_sec",
        "tick_interval", "import_string", "export_now", "gui_enable", "gui_layout",
    } },
    { name = "其它", keys = {
        "map_unlock_once", "map_unlock_auto", "map_progress", "map_legacy_tiles",
    } },
}

-- 名称 / 单位（参数页与状态页共用；测试断言覆盖所有 DEFAULTS 键）
GUI_META = {
    enabled = { "总开关" },
    self_check = { "启动自检播报" },
    diag_slow_ms = { "诊断：慢域阈值", "毫秒" },
    diag_report_cmd = { "诊断报告命令" },
    chat_cmd = { "聊天指令 (/forge)", "" },
    import_string = { "粘贴导入设置串" },
    export_now = { "导出当前设置到文件" },
    hot_reload = { "自动重读设置" },
    config_reload_sec = { "自动重读间隔", "秒" },
    tick_interval = { "非关键项刷新间隔", "帧" },
    host_only = { "联机：仅房主生效" },
    write_log = { "写日志文件" },
    debug_log = { "详细日志" },
    crash_log = { "崩溃取证日志" },
    life_max_mult = { "生命上限倍率", "%" },
    life_max_add = { "生命上限加值", "点" },
    life_regen_mult = { "生命回复倍率", "%" },
    life_full = { "生命持续回满" },
    god_mode = { "上帝模式" },
    shadow_dodge = { "暗影闪避" },
    mana_max_mult = { "魔力上限倍率", "%" },
    mana_max_add = { "魔力上限加值", "点" },
    mana_regen_mult = { "魔力回复倍率", "%" },
    mana_cost_mult = { "魔力消耗倍率", "%" },
    mana_full = { "魔力持续回满" },
    move_speed_mult = { "移速倍率", "%" },
    move_speed_add = { "移速加值", "%" },
    jump_speed_mult = { "跳跃速度倍率", "%" },
    jump_height_mult = { "跳跃高度倍率", "%" },
    gravity_mult = { "重力倍率", "%" },
    dash_on = { "冲刺祝福档位", "档" },
    auto_jump = { "自动跳跃" },
    ignore_water = { "忽略水" },
    ice_skate = { "冰面滑行" },
    water_walk = { "水上行走" },
    no_fall_damage = { "免疫摔落伤害" },
    no_knockback = { "免疫击退" },
    infinite_flight = { "无限飞行" },
    flight_time_mult = { "飞行时间倍率", "%" },
    infinite_jump = { "无限跳跃" },
    infinite_rocket = { "无限火箭" },
    empress_brooch = { "女皇赐福" },
    tile_range_mult = { "放置范围倍率", "%" },
    tile_range_add = { "放置范围加值", "格" },
    grab_range_mult = { "拾取范围倍率", "%" },
    grab_range_add = { "拾取范围加值", "点" },
    damage_all_mult = { "全伤害倍率", "%" },
    melee_damage_mult = { "近战伤害倍率", "%" },
    ranged_damage_mult = { "远程伤害倍率", "%" },
    magic_damage_mult = { "魔法伤害倍率", "%" },
    summon_damage_mult = { "召唤伤害倍率", "%" },
    melee_speed_mult = { "近战攻速倍率", "%" },
    whip_speed = { "鞭子速度倍率", "%" },
    whip_speed_add = { "鞭子速度加值", "%" },
    whip_range = { "鞭子范围倍率", "%" },
    whip_range_add = { "鞭子范围加值", "%" },
    crit_add = { "暴击率加值", "%" },
    armor_pen_add = { "护甲穿透加值", "点" },
    minion_mult = { "仆从位倍率", "%" },
    minion_add = { "仆从位加值", "个" },
    turret_mult = { "哨兵位倍率", "%" },
    turret_add = { "哨兵位加值", "个" },
    crit_damage_mult = { "暴击伤害倍率", "%" },
    ammo_save = { "弹药节省" },
    defense_mult = { "防御倍率", "%" },
    defense_add = { "防御加值", "点" },
    endurance_add = { "减伤加值", "%" },
    thorns_add = { "荆棘加值", "点" },
    aggro_add = { "仇恨加值", "点" },
    lava_immune = { "熔岩免疫" },
    fire_walk = { "火焰行走" },
    water_breathing = { "水下呼吸" },
    debuff_immune = { "免疫减益" },
    extra_accessory = { "额外饰品栏" },
    immune_time_mult = { "无敌帧倍率", "%" },
    immune_time_add = { "无敌帧加值", "帧" },
    potion_cooldown_mult = { "药水冷却倍率", "%" },
    min_use_time = { "使用时间下限", "帧" },
    pick_speed_mult = { "镐速倍率", "%" },
    tile_speed_mult = { "放置速度倍率", "%" },
    wall_speed_mult = { "锤速倍率", "%" },
    fishing_add = { "钓鱼力加值", "点" },
    luck_add = { "幸运加值", "点" },
    breath_max_mult = { "呼吸上限倍率", "%" },
    night_vision = { "夜视" },
    detect_creature = { "生物探测" },
    detect_treasure = { "宝藏探测" },
    danger_sense = { "危险感" },
    calmed = { "镇静" },
    invis = { "隐身" },
    grav_control = { "重力控制" },
    acc_flipper = { "脚蹼" },
    map_unlock_once = { "进世界点亮全图" },
    map_unlock_auto = { "自动点亮全图" },
    map_progress = { "点亮进度播报" },
    map_legacy_tiles = { "逐格点亮兜底" },
    camera_zoomout = { "视野拉远", "%" },
    camera_zoomin = { "视野拉近", "%" },
    camera_world_bigger = { "世界更大" },
    camera_rebuild_zoom = { "备选缩放" },
    light_full_night = { "完全夜视" },
    light_penetration = { "光照穿透", "%" },
    auto_cast = { "自动使用 / 挥砍" },
    auto_fish_reel = { "自动收杆" },
    auto_face_enemy = { "自动朝向敌人" },
    auto_aim = { "自动瞄准（未实现）" },
    gui_enable = { "图形面板" },
    gui_layout = { "面板布局", "档" },
}

-- 参数页与三张表的一致性自检（测试也会调）
function GUI.spec_ok()
    local seen, n, dup = {}, 0, nil
    for gi = 1, #GUI_GROUPS do
        local grp = GUI_GROUPS[gi]
        for i = 1, #grp.keys do
            local k = grp.keys[i]
            if seen[k] then dup = k end
            seen[k] = true
            n = n + 1
            if DEFAULTS[k] == nil then return false, "参数页有 DEFAULTS 里不存在的键：" .. k, n end
        end
    end
    for k in pairs(DEFAULTS) do
        if not seen[k] then return false, "参数页漏了键：" .. tostring(k), n end
    end
    if dup then return false, "参数页重复键：" .. dup, n end
    return true, n, #GUI_PAGES
end

function GUI.meta_ok()
    local miss = {}
    for k in pairs(DEFAULTS) do
        if not GUI_META[k] then miss[#miss + 1] = k end
    end
    return #miss == 0, table.concat(miss, ",")
end

-- 取当前玩家实例：优先 Main.player[Main.myPlayer]（每帧现取，借用句柄只在本次回调内有效）。
-- ★ 2026-10-23 实机崩溃修复：主菜单里打开面板切到属性页时，绝不能再把 nil 实例传给
--   get_field_value —— 内核会按 null + 字段偏移读（本次 SIGSEGV 的 fault address=0x820）。
local function gui_player()
    if not in_game() then return nil end
    local idx = nil
    if F.myPlayer or PM.myPlayer then
        local v = fget("myPlayer")
        if type(v) == "number" then idx = v end
    end
    if idx == nil then idx = my_index end
    if type(idx) == "number" and idx >= 0 and (F.player or PM.player) then
        local arr = get_array("player")
        if arr then
            -- 越界/空元素一律当作「没有玩家」：0 在 Lua 里是真值，必须显式排除
            local okn, n = pcall(patch.array_length, arr)
            local in_range = (not okn) or (type(n) ~= "number") or (idx < n)
            if in_range then
                local ok, p = pcall(patch.array_at, arr, idx)
                if ok and p ~= nil and p ~= false and p ~= 0 then return p end
            end
        end
    end
    -- ★ 不再回退跨帧 retain 的 last_inst：拿不到主菜单/数组就显示「不可用」，
    --   宁可少显示一页数值，也不冒悬垂句柄的进程级崩溃风险。
    return nil
end

-- ============ 22.5 属性页（★ 只读） ============
--   · 绝不 set_field_value；读全部 pcall；float/int32/bool 各一路；
--   · 取不到返回 nil → 显示「不可用」，绝不显示成 0；
--   · 最多每 6 帧刷新一次（缓存），页面上每帧只读缓存。
local ATTR_ALL = {
    { "statLife", "int32" }, { "statLifeMax2", "int32" }, { "lifeRegen", "int32" },
    { "statMana", "int32" }, { "statManaMax2", "int32" }, { "manaRegen", "int32" },
    { "meleeDamage", "float" }, { "rangedDamage", "float" }, { "magicDamage", "float" },
    { "minionDamage", "float" }, { "arrowDamage", "float" }, { "bulletDamage", "float" },
    { "meleeCrit", "int32" }, { "rangedCrit", "int32" }, { "magicCrit", "int32" },
    { "statDefense", "int32" }, { "moveSpeed", "float" }, { "jumpSpeed", "float" },
    { "jumpHeight", "int32" }, { "luck", "float" }, { "immuneTime", "int32" },
    { "maxMinions", "int32" }, { "maxTurrets", "int32" }, { "defaultItemGrabRange", "int32" },
    { "nightVision", "bool" },
}
local ATTR = { frame = -9999, vals = {}, rows = {}, reads = 0, changed = 0,
               key = "", inst = nil, client = false, no_player_note = false }

local function attr_read(key, ty)
    local inst = ATTR.inst
    if inst == nil then return nil end
    local pg = PM[key]
    if pg then
        -- 属性 getter 必须是「0 参静态方法」才允许调用：传少了实参会 SIGSEGV
        if patch.method_param_count then
            local okc, c = pcall(patch.method_param_count, pg.get)
            if not okc or tonumber(c) ~= 0 then return nil end
        else
            return nil
        end
        if patch.method_is_static then
            local oks, st = pcall(patch.method_is_static, pg.get)
            if not oks or st ~= true then return nil end
        else
            return nil
        end
        ATTR.reads = ATTR.reads + 1
        local ok, v = pcall(patch.invoke, pg.get)
        if ok and (type(v) == "number" or type(v) == "boolean") then return v end
        return nil
    end
    local f = F[key]
    if not f then return nil end
    local obj = inst
    if ST[key] then obj = nil end
    -- ★ 实例字段绝不给 nil 实例（空指针 + 偏移 = 进程级 SIGSEGV，pcall 拦不住）
    if obj == nil and not ST[key] then return nil end
    ATTR.reads = ATTR.reads + 1
    local ok, v = pcall(patch.get_field_value, f, obj, ty)
    if ok and (type(v) == "number" or type(v) == "boolean") then return v end
    return nil
end

local function f_pair(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return "不可用", GC.warn end
    return string.format("%d / %d", math.floor(a), math.floor(b)), GC.text
end
local function f_int(v, suffix)
    if type(v) ~= "number" then return "不可用", GC.warn end
    return tostring(math.floor(v)) .. (suffix or ""), GC.text
end
local function f_pct(v)
    if type(v) ~= "number" then return "不可用", GC.warn end
    return string.format("%d%%", math.floor(v)), GC.text
end
local function f_mul(v)
    if type(v) ~= "number" then return "不可用", GC.warn end
    return string.format("×%.2f", v), GC.text
end
local function f_signed(v)
    if type(v) ~= "number" then return "不可用", GC.warn end
    return string.format("%+.2f", v), GC.text
end
local function f_bool(v)
    if type(v) ~= "boolean" then return "不可用", GC.warn end
    return v and "开" or "关", v and GC.ok or GC.muted
end

local AMT = {
    { "近战", "meleeDamage", "mul" }, { "远程", "rangedDamage", "mul" },
    { "魔法", "magicDamage", "mul" }, { "召唤", "minionDamage", "mul" },
    { "箭矢", "arrowDamage", "add" }, { "枪弹", "bulletDamage", "add" },
}

local function f_dmg(e, v)
    if type(v) ~= "number" then return "不可用", GC.warn end
    if e[3] == "add" then return string.format("%+.2f", v), GC.text end
    return string.format("×%.2f", v), GC.text
end

local function f_num2(v)
    if type(v) ~= "number" then return "不可用", GC.warn end
    return string.format("%.2f", v), GC.text
end

local function attr_rows(v)
    local R = {}
    local function head(t) R[#R + 1] = { kind = "head", text = t } end
    local function pair(l1, v1, c1, l2, v2, c2)
        R[#R + 1] = { kind = "kv2", l1 = l1, v1 = v1, c1 = c1, l2 = l2, v2 = v2, c2 = c2 }
    end
    head("生命 / 魔力（当前 · 上限 · 回复）")
    pair("生命（当前/上限）", f_pair(v.statLife, v.statLifeMax2), GC.text,
         "生命回复", f_int(v.lifeRegen), GC.text)
    pair("魔力（当前/上限）", f_pair(v.statMana, v.statManaMax2), GC.text,
         "魔力回复", f_int(v.manaRegen), GC.text)
    head("六类伤害与暴击（前四类 ×倍率，箭矢/枪弹 +加值）")
    for i = 1, #AMT, 2 do
        local a, b = AMT[i], AMT[i + 1]
        local av, ac = f_dmg(a, v[a[2]])
        local bv, bc = b and f_dmg(b, v[b[2]]) or nil, GC.text
        pair(a[1] .. "伤害", av, ac, b and (b[1] .. "伤害") or nil, bv, bc)
    end
    pair("近战暴击", f_pct(v.meleeCrit), GC.text, "远程暴击", f_pct(v.rangedCrit), GC.text)
    pair("魔法暴击", f_pct(v.magicCrit), GC.text, "防御", f_int(v.statDefense), GC.text)
    head("移动 / 生存")
    pair("移速", f_mul(v.moveSpeed), GC.text, "跳跃速度", f_num2(v.jumpSpeed), GC.text)
    pair("跳跃高度", f_int(v.jumpHeight), GC.text, "幸运", f_signed(v.luck), GC.text)
    pair("无敌帧", f_int(v.immuneTime, " 帧"), GC.text, "仆从上限", f_int(v.maxMinions), GC.text)
    pair("哨兵上限", f_int(v.maxTurrets), GC.text,
         "拾取范围", (function()
             local s, c = f_int(v.defaultItemGrabRange)
             if s == "不可用" then return "不可用（const）", c end
             return s, c
         end)(), GC.text)
    pair("夜视", f_bool(v.nightVision), GC.text, "光照穿透",
         tostring(math.floor(tonumber(cfg.light_penetration) or 0)) .. "%", GC.text)
    return R
end

local function attr_refresh()
    ATTR.inst = gui_player()
    if ATTR.inst == nil and not ATTR.no_player_note then
        ATTR.no_player_note = true
        diag_note("属性页：无玩家实例（in_game=" .. tostring(in_game()) .. "），整页显示不可用")
        pcall(diag_flush)
    elseif ATTR.inst ~= nil then
        ATTR.no_player_note = false
    end
    local v = {}
    if ATTR.inst ~= nil then
        for i = 1, #ATTR_ALL do
            local e = ATTR_ALL[i]
            v[e[1]] = attr_read(e[1], e[2])
        end
    end
    local parts = {}
    for i = 1, #ATTR_ALL do parts[#parts + 1] = tostring(v[ATTR_ALL[i][1]]) end
    local key = table.concat(parts, "|")
    if key ~= ATTR.key then
        ATTR.key = key
        ATTR.vals = v
        ATTR.rows = attr_rows(v)
        ATTR.changed = ATTR.changed + 1
    end
end

local function attr_ensure()
    if frame_i - ATTR.frame < 6 then return ATTR.rows end
    ATTR.frame = frame_i
    attr_refresh()
    return ATTR.rows
end

-- ============ 22.6 运行时信息 / 动作 ============
local layout_effective   -- 前向声明（状态页/页头都要用）
local function net_label()
    ensure_net_mode()
    local n = net_mode_cache
    if n == 1 then return "联机客机（只读）" end
    if n == 2 then return "联机房主" end
    if n == 0 then return "单机" end
    return "联机状态未知"
end
local function is_guest()
    ensure_net_mode()
    return net_mode_cache == 1
end
local function last_error_text()
    if GUI.last_err ~= "" then return GUI.last_err end
    local found = nil
    for i = #DOMAINS, 1, -1 do
        local d = DOMAINS[i]
        if d.last_err then found = d.name .. "：" .. d.last_err end
    end
    return found or "无"
end
local function log_add(text)
    GS.log[#GS.log + 1] = tostring(text)
    while #GS.log > 30 do table.remove(GS.log, 1) end
end
local function sanitize(s)
    s = tostring(s or "")
    s = s:gsub("✅", "OK")
    s = s:gsub("❌", "X")
    s = s:gsub("⚠️", "!")
    s = s:gsub("⚠", "!")
    return s
end

local function apply_change(key)
    if key == "gui_layout" then GS.pg = {} end
    local ok, err = pcall(build_plans)
    if not ok then
        GUI.last_err = "重建计划失败：" .. tostring(err)
        log_add(GUI.last_err)
    end
    last_cfg_check = os.time() or last_cfg_check
end

local function action_heal()
    if is_guest() then return false, "联机客机：回满血魔仅房主可用" end
    if not in_game() then return false, "未进入世界，回满不可用" end
    local inst = gui_player()
    if not inst then return false, "未识别到玩家，回满不可用" end
    local changed = 0
    local lmax = fget("statLifeMax2", inst)
    if type(lmax) == "number" and lmax > 0 then
        if fset("statLife", inst, lmax) then changed = changed + 1 end
    end
    local mmax = fget("statManaMax2", inst)
    if type(mmax) == "number" and mmax > 0 then
        if fset("statMana", inst, mmax) then changed = changed + 1 end
    end
    if changed == 0 then return false, "生命/魔力句柄不可用" end
    return true, "已回满生命与魔力"
end

local function action_map()
    if is_guest() then return false, "联机客机：点亮全图仅房主可用" end
    local ok, msg = run_map_unlock()
    return ok, msg
end

local function action_reload()
    local ok1, e1 = pcall(read_config)
    local ok2, e2 = pcall(build_plans)
    last_cfg_check = os.time() or last_cfg_check
    if not ok1 or not ok2 then
        return false, "重读失败：" .. tostring(e1 or e2)
    end
    return true, string.format("已重读设置（共 %d 项）", #SETTING_ORDER)
end

local function action_export()
    local ok, s, n = pcall(build_setting_string, true)
    if not ok or type(s) ~= "string" then return false, "导出失败：" .. tostring(s) end
    GS.exp_text = s
    GS.exp_show = true
    return true, string.format("已导出 %d 项设置串（只显示，不落盘）", n or 0)
end

local function action_selfcheck()
    local ok, lines = pcall(diag_lines, #DOMAINS)
    if not ok or type(lines) ~= "table" then return false, "自检失败：" .. tostring(lines) end
    GS.selfcheck = lines
    self_check_pending = false
    self_check_done = true
    return true, string.format("自检完成：%d 个功能域", #DOMAINS)
end

local function action_clearlog()
    DIAG.ring = {}
    DIAG.n = 0
    DIAG.dirty = true
    pcall(diag_flush)
    GS.log = {}
    GS.selfcheck = nil
    return true, "已清空面板日志与诊断环形缓存"
end

local function do_action(act, arg)
    local ok, msg
    if act == "tab" then
        GS.tab = math.max(1, math.min(#GUI_PAGES, math.floor(num(arg, 1))))
        GS.confirm_key = nil
        gui_state_write()
        return
    elseif act == "toggle_enabled" then
        cfg.enabled = not (cfg.enabled == true)
        apply_change("enabled")
        ok, msg = true, "总开关已" .. (cfg.enabled and "打开" or "关闭")
    elseif act == "toggle_god" then
        cfg.god_mode = not (cfg.god_mode == true)
        apply_change("god_mode")
        ok, msg = true, "上帝模式已" .. (cfg.god_mode and "打开" or "关闭")
    elseif act == "heal" then
        ok, msg = action_heal()
    elseif act == "map" then
        ok, msg = action_map()
    elseif act == "reload" then
        ok, msg = action_reload()
    elseif act == "export" then
        ok, msg = action_export()
    elseif act == "selfcheck" then
        ok, msg = action_selfcheck()
    elseif act == "clearlog" then
        ok, msg = action_clearlog()
    elseif act == "fold" then
        local i = math.floor(num(arg, 0))
        if i >= 1 and i <= #GUI_GROUPS then
            GS.fold[i] = not GS.fold[i]
            gui_state_write()
        end
        return
    end
    if msg then
        GS.msg = msg
        log_add(msg)
    end
end

-- ============ 22.7 各页的行 ============
local function build_status()
    local R = {}
    local on = cfg.enabled == true
    local lerr = last_error_text()
    R[#R + 1] = { kind = "statuscard", h = U(78) }
    R[#R + 1] = { kind = "kv", k = "总开关", v = on and "开（功能生效）" or "关（完全停手）",
                  col = on and "ok" or "warn" }
    R[#R + 1] = { kind = "kv", k = "上帝模式", v = cfg.god_mode and "开" or "关",
                  col = cfg.god_mode and "ok" or "muted" }
    R[#R + 1] = { kind = "kv", k = "已装钩子数", v = tostring(#hooks) .. " 个" }
    R[#R + 1] = { kind = "kv", k = "本帧命中", v = tostring(gui_frame_hits) .. " 次" }
    R[#R + 1] = { kind = "kv", k = "上次错误", v = lerr, col = (lerr ~= "无") and "warn" or "muted" }
    R[#R + 1] = { kind = "kv", k = "是否联机", v = net_label(),
                  col = is_guest() and "warn" or "text" }
    R[#R + 1] = { kind = "kv", k = "面板布局 / API",
                  v = layout_effective() .. " · " .. tostring(GUI.api_have) .. "/40" }
    R[#R + 1] = { kind = "action", label = "重读设置（config.json）", act = "reload" }
    R[#R + 1] = { kind = "action", label = "启动自检（结果在关于页）", act = "selfcheck" }
    if GS.msg ~= "" then
        R[#R + 1] = { kind = "text", text = "最近操作：" .. GS.msg, col = "gold" }
    end
    return R
end

local function build_attributes()
    local rows = attr_ensure()
    local R = {}
    local guest = is_guest()
    R[#R + 1] = { kind = "head",
                  text = string.format("属性（只读）· 每 6 帧刷新 · 第 %d 帧", ATTR.frame) }
    if not in_game() then
        R[#R + 1] = { kind = "text", text = "未进入世界：属性不可用（进世界后自动刷新）",
                      col = "warn", h = U(30) }
    elseif ATTR.inst == nil then
        R[#R + 1] = { kind = "text", text = "未识别到玩家：属性不可用", col = "warn", h = U(30) }
    end
    if guest then
        R[#R + 1] = { kind = "text", text = "联机中：数值以房主为准（本页只读）", col = "warn" }
    end
    for i = 1, #rows do R[#R + 1] = rows[i] end
    R[#R + 1] = { kind = "text",
                  text = "取不到的字段显示「不可用」，不会显示成 0；本页绝不改任何数值。",
                  col = "muted", h = U(26) }
    return R
end

local function build_params()
    local R = {}
    for gi = 1, #GUI_GROUPS do
        local grp = GUI_GROUPS[gi]
        -- 组头只写组名（实机反馈：后缀「已折叠，点标题展开」太长，挤掉名字也让页面变脏）
        R[#R + 1] = { kind = "group", text = grp.name, arg = gi,
                      right = tostring(#grp.keys) .. " 项" }
        if not GS.fold[gi] then
            for i = 1, #grp.keys do R[#R + 1] = { kind = "field", key = grp.keys[i] } end
        end
    end
    return R
end

local function build_actions()
    local R = {}
    local guest = is_guest()
    R[#R + 1] = { kind = "head", text = "一键操作（只改本次运行，不写 TEFManager 设置）" }
    if guest then
        R[#R + 1] = { kind = "text",
                      text = "联机客机：回满血魔 / 点亮全图仅房主可用（已隐藏）", col = "warn" }
    else
        R[#R + 1] = { kind = "action", label = "回满血魔", act = "heal" }
        R[#R + 1] = { kind = "action", label = "点亮全图（一次性）", act = "map" }
    end
    R[#R + 1] = { kind = "action", label = "重读设置（config.json）", act = "reload" }
    R[#R + 1] = { kind = "action",
                  label = GS.exp_show and "收起设置串" or "导出设置串（只显示，不落盘）",
                  act = "export" }
    R[#R + 1] = { kind = "action", label = "自检（显示每个功能域）", act = "selfcheck" }
    R[#R + 1] = { kind = "action", label = "清空面板日志与诊断缓存", act = "clearlog" }
    if GS.msg ~= "" then
        R[#R + 1] = { kind = "text", text = "最近操作：" .. GS.msg, col = "gold" }
    end
    if GS.exp_show and GS.exp_text ~= "" then
        R[#R + 1] = { kind = "head", text = "设置串（复制用；只显示）" }
        local lines = wrap_units(GS.exp_text, 46)
        local cap = math.min(#lines, 18)
        for i = 1, cap do
            R[#R + 1] = { kind = "text", text = lines[i], col = "text", sc = 0.40, h = U(24) }
        end
        if #lines > cap then
            R[#R + 1] = { kind = "text",
                          text = string.format("…… 其余 %d 行未显示（共 %d 字符）", #lines - cap,
                              #GS.exp_text), col = "muted", h = U(24) }
        end
    end
    if GS.selfcheck then
        R[#R + 1] = { kind = "head", text = "自检结果" }
        for i = 1, #GS.selfcheck do
            R[#R + 1] = { kind = "text", text = sanitize(GS.selfcheck[i]), col = "muted",
                          sc = 0.42, h = U(24) }
        end
    end
    return R
end

local function build_about()
    local R = {}
    R[#R + 1] = { kind = "head", text = "关于" }
    R[#R + 1] = { kind = "kv", k = "版本", v = "v" .. tostring(mod.meta.version) }
    R[#R + 1] = { kind = "kv", k = "pkgId", v = "ailab.lua.playerforge" }
    R[#R + 1] = { kind = "kv", k = "加载器 API", v = tostring(GUI.api_have) .. "/40 项可用" }
    R[#R + 1] = { kind = "kv", k = "缺项", v = (GUI.api_missing ~= "" and GUI.api_missing or "无") }
    R[#R + 1] = { kind = "kv", k = "屏幕探测",
                  v = GP.done and (GP.unclamped and "不可用（保守排版）"
                      or string.format("g=%.2f · 屏宽 %.0f · 高 %.0f", GP.g, GP.screen_w, GP.screen_h))
                      or "未完成" }
    R[#R + 1] = { kind = "kv", k = "状态文件", v = GUI_STATE_FILE }
    R[#R + 1] = { kind = "kv", k = "面板异常", v = tostring(GUI.err_n) .. " 次" }
    R[#R + 1] = { kind = "head", text = "最近日志（面板，最多 30 行）" }
    if #GS.log == 0 then
        R[#R + 1] = { kind = "text", text = "（日志缓冲为空）", col = "muted" }
    else
        for i = 1, #GS.log do
            R[#R + 1] = { kind = "text", text = GS.log[i], col = "muted", sc = 0.42, h = U(24) }
        end
    end
    R[#R + 1] = { kind = "head", text = "诊断环形缓存（最多 20 行）" }
    local n = 0
    local start = math.max(1, (DIAG.n or 0) - 19)
    for i = start, (DIAG.n or 0) do
        n = n + 1
        R[#R + 1] = { kind = "text", text = tostring(DIAG.ring[i] or ""), col = "muted",
                      sc = 0.40, h = U(24) }
    end
    if n == 0 then R[#R + 1] = { kind = "text", text = "（诊断缓存为空）", col = "muted" } end
    return R
end

local function build_rows()
    if GS.tab == 2 then return build_attributes() end
    if GS.tab == 3 then return build_params() end
    if GS.tab == 4 then return build_actions() end
    if GS.tab == 5 then return build_about() end
    return build_status()
end

-- ============ 22.8 行渲染 ============
local function row_height(r)
    return (r and r.h) or U(34)
end

local function row_base(x, y, w, h, col)
    if IMG.panel and has("nine_slice") then
        local ok = api("nine_slice", IMG.panel, x + 2, y + 1, w - 4, h - 2, 8, col or GC.row_b, 0)
        if ok then return true end
    end
    return fillr(x, y, w, h, col or GC.row_b)
end

local function field_value_label(key, val, unit)
    if val == nil then return "不可用" end
    if type(val) == "boolean" then return val and "开" or "关" end
    if type(val) == "number" then return string.format("%d%s", math.floor(val), unit or "") end
    local s = tostring(val)
    if s == "" then return "（空）" end
    return s
end

local function draw_field(key, x, y, w, h)
    local meta = GUI_META[key]
    local name = (meta and meta[1]) or key
    local unit = (meta and meta[2]) or ""
    local val = cfg[key]
    local ctype
    if CHOICES[key] then ctype = "choice"
    elseif type(val) == "boolean" then ctype = "bool"
    elseif type(val) == "number" then ctype = "int"
    else ctype = "str" end
    local valw = math.min(U(112), math.floor(w * 0.38))
    if valw < U(54) then valw = U(54) end
    local labw = w - valw - U(16)
    txt(x + U(8), y + U(8), name, GC.text, 0.5, labw)
    if LIMITS[key] and ctype == "int" then
        txt(x + U(8), y + U(21), string.format("范围 %d ~ %d（只提示，不夹取）",
            LIMITS[key][1], LIMITS[key][2]), GC.muted, 0.36, labw)
    end
    local vx = x + w - valw - U(6)
    local label = field_value_label(key, val, unit)
    if ctype == "choice" then
        label = tostring(val) .. " ›"
    end
    if not btn(vx, y + U(3), valw, h - U(6), label) then return end
    if ctype == "bool" then
        if key == "gui_enable" and val == true and GS.confirm_key ~= "gui_enable" then
            GS.confirm_key = "gui_enable"
            GS.msg = "再点一次确认关闭面板（之后只能在 TEFManager 设置里开回来）"
            return
        end
        GS.confirm_key = nil
        cfg[key] = not val
        apply_change(key)
        GS.msg = string.format("已改 %s = %s（只改本次游戏）", name, cfg[key] and "开" or "关")
        log_add(GS.msg)
        gui_state_write()
    elseif ctype == "choice" then
        local opts = CHOICES[key] or {}
        local idx = 0
        for i = 1, #opts do if opts[i] == tostring(val) then idx = i break end end
        cfg[key] = opts[(idx % #opts) + 1]
        apply_change(key)
        GS.msg = string.format("已改 %s = %s（只改本次游戏）", name, tostring(cfg[key]))
        log_add(GS.msg)
        gui_state_write()
    elseif ctype == "int" then
        GS.edit = { kind = "num", key = key, title = name .. (unit ~= "" and ("（" .. unit .. "）") or "") }
        GS.buf = tostring(math.floor(tonumber(val) or 0))
        GS.confirm_key = nil
    else
        GS.edit = { kind = "str", key = key, title = name }
        GS.buf = tostring(val or "")
        GS.confirm_key = nil
    end
end

local function draw_statuscard(x, y, w, h)
    card(x, y, w, h, GC.row_b)
    local on = cfg.enabled == true
    txt(x + U(14), y + U(8), "玩家工坊 · " .. (on and "运行中" or "已停止"),
        on and GC.ok or GC.bad, 0.68, w - U(170))
    txt(x + U(14), y + U(32),
        string.format("钩子 %d 个 · 本帧命中 %d 次 · %s", #hooks, gui_frame_hits, net_label()),
        GC.muted, 0.5, w - U(170))
    local bw = math.min(U(136), math.floor(w * 0.38))
    if btn(x + w - bw - U(10), y + U(22), bw, U(32),
        on and "关闭总开关" or "开启总开关") then
        do_action("toggle_enabled")
    end
end

local function draw_row(r, x, y, w, h)
    local mid = y + U(10)
    if r.kind == "head" then
        row_base(x, y, w, h, GC.row_a)
        fillr(x + U(8), y + U(7), U(3), h - U(14), GC.accent)
        txt(x + U(16), y + U(8), r.text, GC.accent, 0.52, w - U(24))
    elseif r.kind == "statuscard" then
        draw_statuscard(x, y, w, h)
    elseif r.kind == "kv" then
        row_base(x, y, w, h, GC.row_b)
        local kw = math.floor(w * 0.40)
        txt(x + U(8), mid, r.k, GC.muted, 0.48, kw - U(10))
        txt(x + kw, mid, r.v, GC[r.col or "text"] or GC.text, 0.48, w - kw - U(8))
    elseif r.kind == "kv2" then
        row_base(x, y, w, h, GC.row_b)
        local half = math.floor(w / 2)
        local lx, rx = x + U(8), x + half + U(8)
        local labw = math.floor(half * 0.52) - U(10)
        local valw = half - labw - U(16)
        txt(lx, mid, r.l1, GC.muted, 0.46, labw)
        txt(lx + labw, mid, r.v1, r.c1 or GC.text, 0.46, valw)
        if r.l2 then
            txt(rx, mid, r.l2, GC.muted, 0.46, labw)
            txt(rx + labw, mid, r.v2 or "", r.c2 or GC.text, 0.46, valw)
        end
    elseif r.kind == "text" then
        txt(x + U(6), y + U(5), r.text, GC[r.col or "text"] or GC.text, r.sc or 0.44, w - U(12))
    elseif r.kind == "group" then
        row_base(x, y, w, h, GC.row_a)
        if btn(x + U(4), y + U(2), w - U(8), h - U(4), r.text) then do_action("fold", r.arg) end
        if r.right then
            txt(x + w - U(62), y + U(8), r.right, GC.muted, 0.42, U(56))
        end
    elseif r.kind == "field" then
        row_base(x, y, w, h, GC.row_b)
        draw_field(r.key, x, y, w, h)
    elseif r.kind == "action" then
        local bw = math.min(w - U(12), U(280))
        if btn(x + U(6), y + U(3), bw, h - U(6), r.label) then do_action(r.act) end
    end
end

-- ============ 22.9 容器层：滚动（1.9.0）/ 分页（老加载器） ============
layout_effective = function()
    if not has("begin_scroll") or not has("end_scroll") then return "分页" end
    if (cfg.gui_layout or "滚动") == "分页" then return "分页" end
    return "滚动"
end

local function draw_content(rows, bx, body0, bw, vh)
    local total = 0
    for i = 1, #rows do total = total + row_height(rows[i]) end
    if layout_effective() == "滚动" then
        local ch = math.max(total, vh)
        local _sx, sy, _vw, sh = scroll_begin("pf_page" .. tostring(GS.tab),
            bx, body0, bw, vh, bw, ch)
        local y = 0
        for i = 1, #rows do
            local h = row_height(rows[i])
            if y + h > sy and y < sy + sh then
                draw_row(rows[i], 0, y, bw, h)
            end
            y = y + h
        end
        scroll_end()
    else
        local foot = U(30)
        local list_h = vh - foot
        if list_h < U(60) then list_h = U(60) end
        local pages = math.max(1, math.ceil(total / list_h))
        local page = math.max(1, math.min(pages, GS.pg[GS.tab] or 1))
        GS.pg[GS.tab] = page
        local off = (page - 1) * list_h
        local y = 0
        for i = 1, #rows do
            local h = row_height(rows[i])
            if y + h > off and y < off + list_h then
                draw_row(rows[i], bx, body0 + y - off, bw, h)
            end
            y = y + h
        end
        local fy = body0 + list_h
        if btn(bx, fy, U(58), foot - U(4), "上一页") and page > 1 then
            GS.pg[GS.tab] = page - 1
            gui_state_write()
        end
        if btn(bx + bw - U(58), fy, U(58), foot - U(4), "下一页") and page < pages then
            GS.pg[GS.tab] = page + 1
            gui_state_write()
        end
        txt(bx + U(64), fy + U(8), string.format("第 %d/%d 页", page, pages),
            GC.muted, 0.44, bw - U(130))
    end
end

-- ============ 22.10 参数编辑页（整页替换：不叠层、不压暗、不与内容重叠） ============
-- 实机反馈（2026-10-23）：旧版在参数行上叠「半透明黑 + 键盘卡片」，结果
-- 1 整块界面发黑 2 按键与参数行互相重叠、点不准 3 输入值另起一行小字看不清。
-- 现在改为：进入编辑页后本帧不再绘制参数行，编辑页占满内容区，
-- 正在输入的内容直接画在值框里，全程没有任何压暗遮罩。
local function commit_edit()
    local e = GS.edit
    if not e then return end
    local key = e.key
    if e.kind == "num" then
        local n = tonumber(GS.buf)
        if n ~= nil and n == n and n ~= math.huge and n ~= -math.huge then
            cfg[key] = math.floor(n)
            apply_change(key)
            GS.msg = string.format("已改 %s = %d（只改本次游戏）", (GUI_META[key] and GUI_META[key][1]) or key,
                cfg[key])
            log_add(GS.msg)
        else
            GS.msg = "输入不是数字，未改动"
            log_add(GS.msg)
        end
    else
        cfg[key] = tostring(GS.buf or "")
        apply_change(key)
        GS.msg = "已改 " .. ((GUI_META[key] and GUI_META[key][1]) or key) .. "（只改本次游戏）"
        log_add(GS.msg)
    end
    GS.edit = nil
    GS.buf = ""
    gui_state_write()
end

local function edit_restore_default()
    local e = GS.edit
    if not e then return end
    cfg[e.key] = DEFAULTS[e.key]
    apply_change(e.key)
    GS.msg = "已恢复默认值（只改本次游戏）"
    log_add(GS.msg)
    GS.edit, GS.buf = nil, ""
    gui_state_write()
end

local function draw_editor(bx, bw, body0, vh, cw)
    local e = GS.edit
    local str_mode = (e.kind == "str")
    local x, w
    if str_mode then
        -- 字符串用加载器自带输入框（宽度 = 内容区全宽），卡片也铺满内容区，避免框比卡片宽
        x, w = 0, cw
    else
        x, w = bx + U(4), bw - U(8)
    end
    local top = body0 + U(4)
    local bottom = body0 + vh - U(4)
    -- 不透明整页底：本帧参数行根本没画，这里再铺一层，保证「刚点开的那一帧」也不透
    fillr(0, body0, cw, vh, GC.row_b)
    if not card(x, top, w, bottom - top, GC.panel) then
        fillr(x, top, w, bottom - top, GC.panel)
    end
    local px = x + U(10)
    local iw = w - U(20)
    local cur = cfg[e.key]
    local curtxt = (cur == nil) and "（空）" or tostring(cur)
    if curtxt == "" then curtxt = "（空）" end
    txt(px, top + U(7), e.title, GC.accent, 0.56, math.floor(iw * 0.60))
    txt(px + math.floor(iw * 0.44), top + U(9), "当前 " .. curtxt, GC.muted, 0.40,
        math.floor(iw * 0.56) - U(4))
    local gap = U(6)
    local act_h = U(30)
    local box_y = top + U(28)
    local box_h = U(40)
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
        if has("input_text") then
            api("set_cursor", 0, iy)
            local ok, v = api("input_text", "pf_" .. tostring(e.key), GS.buf or "")
            if ok and type(v) == "string" then GS.buf = v end
        else
            txt(px, iy, "本机没有输入框 API：可用「清空」，或到 TEFManager 设置里改",
                GC.warn, 0.42, iw)
        end
        local hit = actions(bottom - U(4) - act_h, { "清空", "确定", "取消" })
        if hit == "清空" then
            GS.buf = ""
        elseif hit == "确定" then
            commit_edit()
        elseif hit == "取消" then
            GS.edit, GS.buf = nil, ""
        end
        return
    end

    -- 数字键盘：3 列 x 4 行，高度按可用空间算，永远落在编辑页内部
    local key_top = hint_y + U(18)
    local act_y = bottom - U(4) - act_h
    local kh = math.floor((act_y - gap - key_top - gap * 3) / 4)
    if kh < U(16) then kh = U(16) end
    if kh > U(44) then kh = U(44) end
    local kw = math.floor((iw - gap * 2) / 3)
    local keys = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
                   { "+/-", "0", "退格" } }
    for ri = 1, 4 do
        for ci = 1, 3 do
            local k = keys[ri][ci]
            if btn(px + (ci - 1) * (kw + gap), key_top + (ri - 1) * (kh + gap), kw, kh, k) then
                if k == "退格" then
                    GS.buf = tostring(GS.buf or ""):sub(1, -2)
                elseif k == "+/-" then
                    local b = tostring(GS.buf or "")
                    if b:sub(1, 1) == "-" then GS.buf = b:sub(2) else GS.buf = "-" .. b end
                else
                    GS.buf = tostring(GS.buf or "") .. k
                end
            end
        end
    end
    -- 值框最后画：本帧刚按的键立刻出现在框里
    fillr(px, box_y, iw, box_h, GC.row_a)
    fillr(px, box_y, U(3), box_h, GC.accent)
    local shown = tostring(GS.buf or "")
    local blink = (math.floor((GP.frames or 0) / 20) % 2 == 0) and "|" or ""
    if shown == "" then
        txt(px + U(10), box_y + U(12), "点键盘输入数字" .. blink, GC.muted, 0.50, iw - U(18))
    else
        txt(px + U(10), box_y + U(11), shown .. blink, GC.text, 0.66, iw - U(18))
    end
    local hit = actions(act_y, { "清空", "默认", "确定", "取消" })
    if hit == "清空" then
        GS.buf = ""
    elseif hit == "默认" then
        edit_restore_default()
    elseif hit == "确定" then
        commit_edit()
    elseif hit == "取消" then
        GS.edit, GS.buf = nil, ""
    end
end

-- ============ 22.11 每帧入口 ============
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
    gui_state_read()
    diag_note("面板初始化：tab=" .. tostring(GS.tab) .. " in_game=" .. tostring(in_game()))
    pcall(diag_flush)
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
    -- * 左右等距（2026-10-23 实机反馈：原先左边留 2 格、右边顶到皮肤边框）
    --   加载器内容区 = 窗口宽 - 2*pad（pad = 12*g_scale），内容原点本身已在 pad 处；
    --   所以这里只负责「内容区内」的对称留白：左右各减同一个值，绝不两侧拆开算。
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
    api("set_title", "玩家工坊 v" .. ver, IMG.glyph and "玩" or "PF")
    local lay = layout_effective()
    txt(bx, U(4), "v" .. ver .. " · 玩家工坊 · " .. lay, GC.accent, 0.58, bw)
    local sub = string.format("第 %d/%d 页 · 钩子 %d 个 · %s · 设置 %d 项 · API %d/40",
        GS.tab, #GUI_PAGES, #hooks, net_label(), GUI.keys_n, GUI.api_have)
    if lay == "分页" and not has("begin_scroll") then
        sub = sub .. " · 本机不支持滚动"
    end
    -- 0.40：内容区宽度减去左右留白后，长页头（含「本机不支持滚动」）才不会被截断
    txt(bx, U(23), sub, GC.muted, 0.40, bw)
    local gap = U(6)
    local tw = math.floor((bw - gap * (#GUI_PAGES - 1)) / #GUI_PAGES)
    if tw < U(40) then tw = U(40) end
    -- 取整剩下的几像素平分到两侧，页签条同样左右等距
    local left_all = math.max(0, math.floor((bw - (tw * #GUI_PAGES + gap * (#GUI_PAGES - 1))) / 2))
    for i = 1, #GUI_PAGES do
        local tx = bx + left_all + (i - 1) * (tw + gap)
        if btn(tx, U(40), tw, U(30), GUI_PAGES[i]) then
            if GS.tab ~= i then
                GS.tab = i
                GS.confirm_key = nil
                GS.edit, GS.buf = nil, ""
                gui_state_write()
                -- 实机崩溃取证：切页先落盘再画，万一崩在渲染里也能知道停在哪一页
                diag_note("面板切页：" .. tostring(i) .. " " .. tostring(GUI_PAGES[i]) ..
                    " in_game=" .. tostring(in_game()))
                pcall(diag_flush)
            end
        end
        if GS.tab == i then fillr(tx + U(3), U(70), tw - U(6), U(4), GC.accent) end
    end
    local body0 = U(80)
    local vh = avail_h() - body0 - U(6)
    if vh < U(110) then vh = U(110) end
    if GS.edit then
        draw_editor(bx, bw, body0, vh, cw)
    else
        local rows = build_rows()
        draw_content(rows, bx, body0, bw, vh)
        -- 本帧刚点开编辑页：参数行已经画了，用不透明整页盖上去（没有压暗层）
        if GS.edit then draw_editor(bx, bw, body0, vh, cw) end
    end
    apply_pos()
end

local function gui_frame()
    GP.frames = GP.frames + 1
    api("set_content_height", avail_h())
    local ok, err = pcall(gui_draw)
    if not ok then
        GUI.err_n = GUI.err_n + 1
        GUI.last_err = tostring(err)
        api("set_content_height", avail_h())
        txt(VX, U(84), "面板出错：" .. GUI.last_err, GC.bad, 0.5, VW)
    end
end

function mod.on_gui()
    if cfg.gui_enable == false then return end
    local ok, err = pcall(gui_frame)
    if not ok then
        GUI.err_n = GUI.err_n + 1
        GUI.last_err = tostring(err)
    end
end

-- ============ 22.12 诊断 / 测试句柄 ============
GUI.META = GUI_META
GUI.GROUPS = GUI_GROUPS
GUI.pages = GUI_PAGES
GUI.state = GS
GUI.probe = GP
GUI.attr = ATTR
GUI.effective_layout = layout_effective
GUI.save_state = gui_state_write
GUI.load_state = gui_state_read
GUI.render = gui_draw
GUI.act = do_action
GUI.net_label = net_label
GUI.is_guest = is_guest
GUI.state_file = GUI_STATE_FILE
GUI.attr_refresh = attr_refresh
GUI.attr_keys = ATTR_ALL
GUI.player = gui_player
GUI.cfg = cfg
GUI.limits = LIMITS
GUI.defaults = DEFAULTS
-- 左右等距的判据：内容区宽 cw、加载器留白 pad、我们的绘制区间 [bx, bx+bw]
GUI.box = function() return VX, VW, GUI_CW, GUI_PAD end
GUI.log_tail = function(n)
    local out = {}
    local start = math.max(1, #GS.log - (tonumber(n) or 30) + 1)
    for i = start, #GS.log do out[#out + 1] = GS.log[i] end
    return out
end

end

playerforge_gui_install()
todo_list = { "setup" }
