--[[
  ============================================================
  Weapon IFrame Config (武器无敌帧自定义)  v1.6.9
  泰拉瑞亚 PE 1.4.5.8 / TEFManager LuaLoader 模组
  ============================================================
  功能: "原版 / 局部无敌帧 / 取消无敌帧" 三种模式, 支持按武器独立配置。

  模式:
    0. 原版无敌帧 (mode=0): 完全不干预, 沿用游戏原版无敌帧。
    1. 局部无敌帧 (mode=1): 保持原版无敌帧数, 但类型改为局部无敌帧
       (usesLocalNPCImmunity=true)。无敌帧数 = 弹幕自身原版局部冷却
       (原版通常 1/6秒≈10帧), 仅当弹幕未设置(-2/nil)时补写10帧;
       与参考模组「去骗伤」一致, 并显式关闭 idstatic。效果 = 免疫从
       "原版全局共享"改为"每颗弹幕独立冷却", 多弹幕密集连续命中,
       不再被原版全局免疫吞伤害 —— "去骗伤"效果。
    2. 取消无敌帧 (mode=2): 无敌帧数固定为 1 帧(几乎每帧可命中)。
       使用局部免疫(usesLocalNPCImmunity + localNPCHitCooldown=1),
       每颗弹幕各自独立冷却, 多弹幕密集连续命中同一目标,
       伤害不再被原版无敌帧吞掉 —— 达到"取消无敌帧/骗伤"效果。

  【v1.6.2 教训】hook 原来装不上(诊断证明 itemcheck=false setdefaults=false),
  v1.6.2 强化 hook 安装后全部装上了, 但又暴露第二层问题:
  【v1.6.3 第二根因(本次修复)】
    v1.6.2 在 Projectile.SetDefaults 的 postfix 里读 owner ——
    诊断采样显示 owner 全是 255! 因为 Terraria 的 NewProjectile 内部
    是先调用 SetDefaults、之后才给 owner 赋值 (255=无所有者标记)。
    所以在 SetDefaults 时读 owner 永远拿到 255, 读不到玩家手持。
    ★ v1.6.3 主路径改为 hook Projectile.AI():
      每个弹幕每 tick 都会调用 AI(), 调用时 owner 必然已赋值,
      在 AI 回调里实时读 Main.player[owner] 的手持武器, 然后设置
      usesLocalNPCImmunity 等字段。AI 是幂等的, 设置一次即长期生效。
    ★ 复用保护: 弹幕对象池会复用实例, 用 processed[instance]
      (记录 owner + type) 判断是否需要重新处理, 避免误判和重复读手持。
    ★ v1.6.4(诊断增强): 免疫字段写入后立即回读, 记录到诊断的
      samples_apply 区块 (set[local/idstatic/cd] + 回读 local/idstatic/cd),
      验证 set_field_value 是否真正落盘; 诊断头部版本号改动态读取。

    ★ v1.6.6(重构为三档模式): 模式改为三选 —— 0=原版 / 1=静态无敌帧
      (保持原版无敌帧数≈10帧, 免疫类型改静态 usesIDStaticNPCImmunity +
      idStaticNPCHitCooldown) / 2=取消无敌帧(无敌帧固定1帧, 局部免疫
      usesLocalNPCImmunity + localNPCHitCooldown=1)。按模式分别写入对应
      免疫字段, 诊断 samples_apply 回读 local/idstatic/cd/idstatic_cd。

    ★ v1.6.7(去掉总开关): 按用户要求移除设置界面的「启用模组」开关,
       模组始终开启 (cfg.enabled 强制 true, 不再读取 config 里的 enabled)。

    ★ v1.6.8(修复静态模式无效——参考「去骗伤」模组):
       用户给出参考模组 ring.lua.nolies (去泥🐴骗伤)。其代码注释揭示
    PE 1.4.5.8 的 Damage_PVE_Inner 命中分支只认局部免疫:
      usesLocalNPCImmunity && localNPCHitCooldown != -2 → 记入
      localNPCImmunity[] 并清 npc.immune[owner]; 否则回落
      npc.immune[owner] = 10 (原版全局免疫), 改了等于没改。
      idstatic (usesIDStaticNPCImmunity/idStaticNPCHitCooldown)
      字段引擎根本不读! v1.6.7 静态模式写 idstatic 因此完全无效。
      v1.6.8: 静态模式(mode=1)改为局部免疫 + localNPCHitCooldown=10
      (与参考模组完全一致), 并显式关闭 idstatic; 取消模式(mode=2)
      保持局部免疫 + cd=1。三档: 原版=不干预 / 静态=局部10帧 /
      取消=局部1帧。

    ★ v1.6.9(按用户命名正名三模式):
      用户明确三个模式名称 ——
        1) 原版无敌帧: 完全不干预 (mode=0);
        2) 局部无敌帧: 保持原版无敌帧数, 但免疫类型改为局部
           (usesLocalNPCImmunity=true, 冷却沿用弹幕原版局部冷却,
           未设(-2/nil)补10帧) (mode=1);
        3) 取消无敌帧: 无敌帧数固定为 1 帧 (局部免疫 + cd=1) (mode=2)。
      即 v1.6.8 的"静态模式"正名为"局部无敌帧" —— PE 引擎不读 idstatic,
      局部免疫就是唯一生效路径, 三档模式实现保持不变。
    ★ v1.7.0(新增召唤伤害路径探测):
      用户反馈召唤杖(吸血鬼青蛙法杖[4273]等)三模式不生效 —— 普通弹幕写入
      局部免疫+cd=1 验证通过, 但召唤仆从(VampireFrog[758]等)体感无差异。
      本轮新增两条探测 hook 定位召唤仆从伤害的真实路径:
        A. prefix hook Projectile.Damage(): 调用前记录当前弹幕上下文(damage_ctx)
           + 统计召唤类弹幕(projPet[type]=true 或兜底 758/951/963)的 Damage 调用数;
           postfix 清空上下文(防止误配对到近战等非弹幕 StrikeNPC)。
        B. postfix hook NPC.StrikeNPC(): 命中时读取 damage_ctx, 统计\"由召唤弹幕
           上下文触发的命中数\" —— 验证召唤仆从是否真的经由
           Damage() -> (局部免疫判定) -> StrikeNPC() 这条普通损伤链路造成伤害。
      预期结论场景:
        H1 召唤仆从从不调用 Damage()(dc=0): 伤害走别的路径(如 AI 直接扣血),
           免疫字段对它天然无关, 需另寻方案(如 hook 仆从攻击函数)。
        H2 调用 Damage 但模式切换对 StrikeNPC 频率无影响: 免疫表不作用于
           召唤弹幕(引擎对 projPet 弹幕特殊处理)。
        H3 调用 Damage 且 StrikeNPC 频率随模式变化: 说明已生效, 体感差异
           来自仆从 AI 攻击节奏慢, 需对比具体跳字频率。
  配置来源: Resources/config.json -> values
    default_mode     : 0=原版 1=局部无敌帧 2=取消无敌帧 (未单独配置武器的默认模式)
    weapon_overrides : 逗号分隔 物品ID:模式(0/1/2), 例 "757:2,4:0"
    注意: 没有 enabled 总开关了, 模组装载即生效 (v1.6.7)。

  多人在线: 本 mod 未做网络同步, 请在 1.4.5.8 单主机场景使用。
--]]

mod.meta = { pkg_id = "operit.weaponiframe", version = "1.7.0" }

local patch = mod.patch

-- 句柄容器 (P.m_ai / P.m_item_check)
local P = {}

-- ============ 常量与默认配置 ============
local MODE_VANILLA, MODE_LOCAL, MODE_CANCEL = 0, 1, 2
local LOCAL_NPC_HIT_COOLDOWN = 1        -- 取消模式: 无敌帧固定 1 帧
local LOCAL_NPC_HIT_COOLDOWN_KEEP = 10  -- 局部模式: 原版无敌帧数 (1/6秒 ≈ 10帧), 弹幕未设局部冷却时补写

local DEFAULTS = {
    enabled = true,
    default_mode = MODE_VANILLA,
    weapon_overrides = "",
}

local cfg = {}

-- ============ 安全调用 ============
local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok and r ~= nil and r ~= false then return r end
    return nil
end

-- 沿继承链查找字段 (whoAmI 定义在 Entity 基类)
local function find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local f = safe(patch.get_field, cur, name)
        if f then return f end
        cur = safe(patch.get_parent, cur)
        guard = guard + 1
    end
    return nil
end

-- 解析 "757:2,4:0" -> {[757]=2, [4]=0} (支持 0/1/2 三档模式)
local function parse_overrides(str)
    local t = {}
    if type(str) ~= "string" then return t end
    for part in str:gmatch("[^,]+") do
        local sid, smode = part:match("^%s*(%d+)%s*:%s*(%d+)%s*$")
        if sid and smode then
            local id = tonumber(sid)
            local m = tonumber(smode)
            if m == MODE_LOCAL or m == MODE_CANCEL or m == MODE_VANILLA then
                t[id] = m
            end
        end
    end
    return t
end

local function load_config()
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    cfg.overrides = {}
    local text = mod.read_file("config.json")
    if text then
        local dkjson = require("dkjson")
        local ok, raw = pcall(dkjson.decode, text)
        if ok and type(raw) == "table" and type(raw.values) == "table" then
            local v = raw.values
            -- v1.6.7: 移除总开关, 始终开启 (不再读取 enabled)
            cfg.enabled = true
            local dm = tonumber(v.default_mode)
            if dm == MODE_LOCAL or dm == MODE_CANCEL or dm == MODE_VANILLA then
                cfg.default_mode = dm
            end
            if type(v.weapon_overrides) == "string" then
                cfg.weapon_overrides = v.weapon_overrides
                cfg.overrides = parse_overrides(v.weapon_overrides)
            end
        else
            mod.info("[IFrame] config.json 解析失败, 使用内置默认值")
        end
    end
    local oc = {}
    for id, m in pairs(cfg.overrides) do oc[#oc+1] = string.format("%d:%d", id, m) end
    local mode_names = { [MODE_VANILLA]="原版", [MODE_LOCAL]="局部无敌帧", [MODE_CANCEL]="取消无敌帧" }
    mod.info(string.format("[IFrame] 配置: 启用=%s 默认模式=%s 覆盖=[%s]",
        tostring(cfg.enabled),
        mode_names[cfg.default_mode] or "未知",
        table.concat(oc, ",")))
end

-- ============ patch 句柄 ============
local proj_type            -- Projectile.type (int32)
local proj_uses_local      -- Projectile.usesLocalNPCImmunity
local proj_uses_id_static  -- Projectile.usesIDStaticNPCImmunity
local proj_local_cd        -- Projectile.localNPCHitCooldown
local proj_id_static_cd    -- Projectile.idStaticNPCHitCooldown
local proj_owner           -- Projectile.owner (int32)
local item_type            -- Item.type
local player_who_am_i      -- Player.whoAmI (Entity 基类)
local F_player_active      -- Player.active (bool)
local F_inventory          -- Player.inventory (Item[])
local M_get_selected_item  -- 方法: Player.get_selectedItem()
local SP_selected_item     -- 属性: Player.selectedItem
local M_sel_prop_getter    -- 属性 getter
local SP_held_item         -- 属性: Player.HeldItem
local M_held_prop_getter   -- 属性 getter
local F_main_player        -- Main.player (static Player[])
local F_proj_pet           -- Main.projPet (static bool[], v1.7.0 召唤探测)
local owner_weapon = {}    -- owner -> 手持物品ID (ItemCheck 缓存, 兜底用)
local processed = {}       -- instance -> {owner=, ptype=} (对象池复用检测)
local hook_ai              -- Projectile.AI hook (主路径)
local hook_item_check      -- Player.ItemCheck hook (缓存补充)
local hook_damage          -- Projectile.Damage hook (v1.7.0 召唤探测)
local hook_npc_strike      -- NPC.StrikeNPC hook (v1.7.0 召唤探测)
-- v1.7.0 召唤伤害路径探测状态
local damage_ctx = nil     -- {ptype=, owner=} 当前正在执行 Damage() 的弹幕上下文
local summon_dc = {}       -- type -> Damage() 调用次数 (召唤类弹幕)
local summon_sc = {}       -- type -> StrikeNPC() 命中次数 (召唤类上下文触发)
local summon_total_dc = 0
local summon_total_sc = 0
local strike_samples = {}  -- 最近配对样本 (召唤类上下文命中)
local SUMMON_BACKUP = { [758]=true, [951]=true, [963]=true }  -- 兜底召唤类型(projPet 不可用时)

-- ============ 自诊断 (双写: 私有目录 + /sdcard/Download) ============
local DIAG_FILE = "weaponiframe_debug.log"
local DIAG_PUBLIC = "/sdcard/Download/weaponiframe_debug.log"
local item_check_count = 0
local ai_process_count = 0
local diag_counter = 0
local SAMPLE_MAX = 20
local sample = {}
local sample_apply = {}   -- AI 写入免疫字段后的回读结果 (写入层验证)
local setup_errors = {}   -- setup/bind 阶段的错误清单, 写入诊断

-- 记录错误到诊断并打印日志（比裸 mod.error 多了诊断落盘）
local function note_err(msg)
    setup_errors[#setup_errors + 1] = msg
    mod.error("[IFrame] " .. msg)
end

local function diag_text()
    local t = {}
    t[#t+1] = "[weaponiframe] v" .. tostring(mod.meta.version) .. " 诊断 " .. tostring(os.date("%Y-%m-%d %H:%M:%S"))
    t[#t+1] = "cfg.enabled=" .. tostring(cfg.enabled)
    t[#t+1] = "cfg.default_mode=" .. tostring(cfg.default_mode)
    t[#t+1] = "cfg.default_mode_name=" .. tostring(({ [0]="原版", [1]="局部无敌帧", [2]="取消无敌帧" })[cfg.default_mode] or "?")
    local ov = {}
    for id, m in pairs(cfg.overrides) do ov[#ov+1] = id .. ":" .. m end
    t[#t+1] = "cfg.overrides=[" .. table.concat(ov, ",") .. "]"
    t[#t+1] = "handles: proj_fields=" .. tostring(proj_uses_local ~= nil and proj_uses_id_static ~= nil and proj_local_cd ~= nil and proj_type ~= nil) ..
              " proj_owner=" .. tostring(proj_owner ~= nil) ..
              " item_type=" .. tostring(item_type ~= nil) ..
              " whoAmI=" .. tostring(player_who_am_i ~= nil) ..
              " active=" .. tostring(F_player_active ~= nil) ..
              " inventory=" .. tostring(F_inventory ~= nil) ..
              " sel_method=" .. tostring(M_get_selected_item ~= nil) ..
              " sel_prop=" .. tostring(M_sel_prop_getter ~= nil) ..
              " held_prop=" .. tostring(M_held_prop_getter ~= nil) ..
              " main_player=" .. tostring(F_main_player ~= nil)
    t[#t+1] = "hooks: ai=" .. tostring(hook_ai ~= nil) ..
              " itemcheck=" .. tostring(hook_item_check ~= nil) ..
              " damage=" .. tostring(hook_damage ~= nil) ..
              " strikenpc=" .. tostring(hook_npc_strike ~= nil) ..
              " item_check_count=" .. tostring(item_check_count) ..
              " ai_process_count=" .. tostring(ai_process_count)
    t[#t+1] = "errors (" .. #setup_errors .. "):"
    if #setup_errors == 0 then t[#t+1] = "  (none)" end
    for i = 1, #setup_errors do t[#t+1] = "  " .. setup_errors[i] end
    t[#t+1] = "samples(ai 新实例处理, " .. #sample .. "):"
    for i = 1, #sample do t[#t+1] = "  " .. sample[i] end
    t[#t+1] = "samples_apply(局部/取消模式写入后回读, " .. #sample_apply .. "):"
    if #sample_apply == 0 then
        t[#t+1] = "  (none - 未触发局部/取消模式写字段, 请用普通弹幕武器而非召唤杖测试)"
    end
    for i = 1, #sample_apply do t[#t+1] = "  " .. sample_apply[i] end
    -- v1.7.0 召唤伤害路径探测诊断
    t[#t+1] = "summon_diag(召唤弹幕伤害路径探测, v1.7.0):"
    t[#t+1] = "  total: dc(Damage调用)=" .. tostring(summon_total_dc) ..
              " sc(StrikeNPC命中)=" .. tostring(summon_total_sc)
    local sks = {}
    for k in pairs(summon_dc) do sks[#sks + 1] = k end
    table.sort(sks)
    if #sks == 0 then
        t[#t+1] = "  (0 次召唤弹幕 Damage 调用 —— 若召唤杖打怪仍为 0, 证实召唤仆从不走 Projectile.Damage, 伤害在别处!)"
    end
    for i = 1, #sks do
        local k = sks[i]
        t[#t+1] = string.format("  type=%s dc=%s sc=%s", tostring(k), tostring(summon_dc[k]), tostring(summon_sc[k] or 0))
    end
    if #strike_samples > 0 then
        t[#t+1] = "  strike_samples(召唤弹幕上下文触发的命中):"
        for i = 1, #strike_samples do t[#t+1] = "    " .. strike_samples[i] end
    end
    local ow = {}
    for k, v in pairs(owner_weapon) do ow[#ow+1] = k .. "->" .. v end
    t[#t+1] = "owner_weapon {" .. table.concat((ow[1] and ow or {"EMPTY"}), ", ") .. "}"
    return table.concat(t, "\n")
end

local function write_diag()
    local text = diag_text()
    local ok1 = mod.write_file(DIAG_FILE, text)
    local ok2 = false
    local f, err = io.open(DIAG_PUBLIC, "w")
    if f then f:write(text) f:close() ok2 = true end
    return ok1, ok2
end

-- ============ 读取玩家当前手持物品ID (多通道, 任一成功即可) ============
local function get_player_held_type(pl)
    if not pl or not item_type then return nil end
    local sel = nil
    -- 通道1: get_selectedItem() 方法
    if M_get_selected_item then
        local v = safe(patch.invoke, M_get_selected_item, pl)
        if type(v) == "number" then sel = v end
    end
    -- 通道2: selectedItem 属性 getter
    if sel == nil and M_sel_prop_getter then
        local v = safe(patch.invoke, M_sel_prop_getter, pl)
        if type(v) == "number" then sel = v end
    end
    -- 通道3: HeldItem 属性 → Item 句柄 → Item.type (最直接)
    if M_held_prop_getter then
        local it = safe(patch.invoke, M_held_prop_getter, pl)
        if it then
            local tp = safe(patch.get_field_value, item_type, it, "int32")
            if tp ~= nil then return tp end
        end
    end
    -- 通道1/2 拿到槽位后: inventory[sel].type
    if sel == nil or sel < 0 then return nil end
    local inv = safe(patch.get_field_value, F_inventory, pl, "object")
    if not inv then return nil end
    local len = safe(patch.array_length, inv)
    if not len or sel >= len then return nil end
    local held = safe(patch.array_at, inv, sel)
    if not held then return nil end
    return safe(patch.get_field_value, item_type, held, "int32")
end

-- ============ Hook: Player.ItemCheck (仅缓存补充, 非主路径) ============
local function on_item_check(instance, args, result)
    if not cfg.enabled or not instance then return end
    item_check_count = item_check_count + 1
    local idx = nil
    if player_who_am_i then
        local w = safe(patch.get_field_value, player_who_am_i, instance, "int32")
        if w ~= nil then idx = w end
    end
    if idx == nil and type(args) == "table" then
        local a = args[1]
        if type(a) == "number" then idx = a end
    end
    if idx == nil then return end
    local tp = get_player_held_type(instance)
    if tp ~= nil then owner_weapon[idx] = tp end
    diag_counter = diag_counter + 1
    if diag_counter % 120 == 0 then write_diag() end
end

-- ============ 核心: Hook Projectile.AI (主路径, 每 tick 调用, owner 必然已赋值) ============
local function on_projectile_ai(instance, args, result)
    if not cfg.enabled or not instance then return end

    -- 每 tick: 读 owner + type (用于复用检测)
    local owner = safe(patch.get_field_value, proj_owner, instance, "int32")
    if owner == nil or owner < 0 then return end
    local ptype = safe(patch.get_field_value, proj_type, instance, "int32")

    -- 快速路径: 同一实例同 owner 同 type 已处理过 → 跳过 (AI 每帧都来)
    local rec = processed[instance]
    if rec and rec.owner == owner and rec.ptype == ptype then return end

    -- 完整处理: 确认这是"有效的玩家弹幕" (Main.player[owner].active == true)
    local pl = nil
    local arr = safe(patch.get_field_value, F_main_player, nil, "object")
    if arr then
        local len = safe(patch.array_length, arr)
        if len and owner < len then
            local pj = safe(patch.array_at, arr, owner)
            if pj then
                local act = safe(patch.get_field_value, F_player_active, pj, "bool")
                if act == true then pl = pj end
            end
        end
    end

    -- 非玩家弹幕(NPC/环境/空闲玩家): 记录已查过, 立即返回(每帧只查一次)
    if not pl then
        processed[instance] = { owner = owner, ptype = ptype }
        return
    end

    local oid = get_player_held_type(pl)          -- 实时读手持 (发射时的手持)
    if oid == nil then oid = owner_weapon[owner] end  -- 兜底: ItemCheck 缓存
    local mode = cfg.default_mode
    if oid and cfg.overrides[oid] ~= nil then mode = cfg.overrides[oid] end

    -- 采样(最近 SAMPLE_MAX 条, 定位用)
    sample[#sample+1] = string.format("owner=%s oid=%s read=%s mode=%s type=%s",
        tostring(owner), tostring(oid), tostring(oid ~= nil), tostring(mode), tostring(ptype))
    if #sample > SAMPLE_MAX then table.remove(sample, 1) end
    processed[instance] = { owner = owner, ptype = ptype }
    ai_process_count = ai_process_count + 1

    if mode == MODE_VANILLA then return end  -- 原版: 不干预

    -- 三档模式(v1.6.9): PE 1.4.5.8 引擎只认"局部免疫"分支, 局部/取消
    --   都走局部免疫(usesLocalNPCImmunity), 差异只在冷却帧数:
    --   局部(1)=保持原版无敌帧数(弹幕自带值, 未设补10) / 取消(2)=固定1帧。
    --   参考模组「去骗伤」做法: 显式关闭 idstatic (引擎根本不读该字段)。
    local use_local  = (mode == MODE_LOCAL or mode == MODE_CANCEL)
    local use_static = false

    -- 写入免疫字段: 每个 set 捕获 pcall结果+返回值, 验证写入是否被接受
    local set_oks = {}
    if proj_uses_local then
        local ok, res = pcall(patch.set_field_value, proj_uses_local, instance, use_local, "bool")
        set_oks[#set_oks+1] = "local=" .. tostring(ok and res)
    end
    if proj_uses_id_static then
        local ok, res = pcall(patch.set_field_value, proj_uses_id_static, instance, use_static, "bool")
        set_oks[#set_oks+1] = "idstatic=" .. tostring(ok and res)
    end
    -- 局部(1)/取消(2) 都写局部冷却: 局部=保持原版帧数(未设补10) / 取消=1帧
    --   只补"未启用"(-2/nil) 的, 弹幕已有原版冷却值则不动 = 保持原版无敌帧数
    if use_local and proj_local_cd then
        local okcd, cdv = pcall(patch.get_field_value, proj_local_cd, instance, "int32")
        local target_cd = (mode == MODE_LOCAL) and LOCAL_NPC_HIT_COOLDOWN_KEEP or LOCAL_NPC_HIT_COOLDOWN
        if okcd and (cdv == nil or cdv == -2) then
            local ok, res = pcall(patch.set_field_value, proj_local_cd, instance, target_cd, "int32")
            set_oks[#set_oks+1] = "cd=" .. tostring(ok and res)
        else
            set_oks[#set_oks+1] = "cd=skip(" .. tostring(cdv) .. ")"
        end
    end
    -- v1.6.8: 不再写 idStaticNPCHitCooldown (引擎不读, 写了无效);
    --         保留字段句柄仅用于下方回读诊断。
    -- 写入后回读最终字段值 (真正落盘验证)
    local rl, rid, rcd, riscd = "?", "?", "?", "?"
    if proj_uses_local then
        local ok1, v1 = pcall(patch.get_field_value, proj_uses_local, instance, "bool")
        if ok1 then rl = tostring(v1) end
    end
    if proj_uses_id_static then
        local ok2, v2 = pcall(patch.get_field_value, proj_uses_id_static, instance, "bool")
        if ok2 then rid = tostring(v2) end
    end
    if proj_local_cd then
        local ok3, v3 = pcall(patch.get_field_value, proj_local_cd, instance, "int32")
        if ok3 then rcd = tostring(v3) end
    end
    if proj_id_static_cd then
        local ok4, v4 = pcall(patch.get_field_value, proj_id_static_cd, instance, "int32")
        if ok4 then riscd = tostring(v4) end
    end
    sample_apply[#sample_apply+1] = string.format("owner=%s oid=%s t=%s mode=%s set[%s] local=%s idstatic=%s cd=%s idstatic_cd=%s",
        tostring(owner), tostring(oid), tostring(ptype), tostring(mode), table.concat(set_oks, ","), rl, rid, rcd, riscd)
    if #sample_apply > SAMPLE_MAX then table.remove(sample_apply, 1) end
end

-- ============ v1.7.0 召唤仆从伤害路径探测 ============
local proj_pet_arr = nil   -- Main.projPet 数组句柄 (懒加载)
local function is_summon_type(ptype)
    if not ptype or ptype < 1 then return false end
    if SUMMON_BACKUP[ptype] then return true end
    if not proj_pet_arr then
        if F_proj_pet then
            local arr = safe(patch.get_field_value, F_proj_pet, nil, "object")
            if arr then proj_pet_arr = arr end
        end
    end
    if proj_pet_arr then
        local v = safe(patch.array_at, proj_pet_arr, ptype)
        if v == true then return true end
    end
    return false
end
-- prefix: Damage() 调用前记录上下文 (绝不可 return false! 必须放行原方法)
local function on_proj_damage(instance, args, result)
    if not instance then return end
    local ptype = safe(patch.get_field_value, proj_type, instance, "int32")
    local owner = safe(patch.get_field_value, proj_owner, instance, "int32")
    damage_ctx = { ptype = ptype, owner = owner }
    if is_summon_type(ptype) then
        summon_dc[ptype] = (summon_dc[ptype] or 0) + 1
        summon_total_dc = summon_total_dc + 1
    end
end
-- postfix: Damage() 返回后清空上下文 (防止误配对近战等非弹幕 StrikeNPC)
local function on_proj_damage_done(instance, args, result)
    damage_ctx = nil
end
-- postfix: NPC.StrikeNPC 命中, 若当前上下文是召唤弹幕 -> 统计
local function on_npc_strike(instance, args, result)
    local ctx = damage_ctx
    if not ctx or not is_summon_type(ctx.ptype) then return end
    local dmg = (type(args) == "table" and args[1]) or nil
    summon_sc[ctx.ptype] = (summon_sc[ctx.ptype] or 0) + 1
    summon_total_sc = summon_total_sc + 1
    strike_samples[#strike_samples + 1] = string.format("t=%s owner=%s dmg=%s",
        tostring(ctx.ptype), tostring(ctx.owner), tostring(dmg))
    if #strike_samples > 12 then table.remove(strike_samples, 1) end
end
-- ============ 生命周期 ============
local function bind_patch()
    local projectile = safe(patch.get_type, "Terraria", "Projectile")
    if not projectile then
        note_err("找不到 Terraria.Projectile 类型")
        return
    end
    proj_type           = safe(patch.get_field, projectile, "type")
    proj_uses_local     = safe(patch.get_field, projectile, "usesLocalNPCImmunity")
    proj_uses_id_static = safe(patch.get_field, projectile, "usesIDStaticNPCImmunity")
    proj_local_cd       = safe(patch.get_field, projectile, "localNPCHitCooldown")
    proj_id_static_cd   = safe(patch.get_field, projectile, "idStaticNPCHitCooldown")
    proj_owner          = safe(patch.get_field, projectile, "owner")
    -- 主路径 hook: Projectile.AI() (0 参数; 每 tick 调用, owner 已赋值)
    P.m_ai = safe(patch.get_method, projectile, "AI", 0)
        or safe(patch.get_method, projectile, "AI")
    if not proj_type or not proj_owner then
        note_err("Projectile.type/owner 字段缺失, 主路径不可用")
    end
    if not proj_uses_local or not proj_uses_id_static or not proj_local_cd or not proj_id_static_cd then
        note_err("Projectile 免疫字段缺失(usesLocalNPCImmunity/usesIDStaticNPCImmunity/localNPCHitCooldown/idStaticNPCHitCooldown), 取消模式无法生效")
    end
    if not P.m_ai then
        note_err("找不到 Projectile.AI 方法, 主 hook 无法安装")
    end

    -- 按武器配置读取所需句柄 (多通道)
    local player = safe(patch.get_type, "Terraria", "Player")
    if player then
        player_who_am_i = find_field(player, "whoAmI")
        F_player_active = find_field(player, "active")
        F_inventory     = find_field(player, "inventory")
        M_get_selected_item = safe(patch.get_method, player, "get_selectedItem", 0)
        SP_selected_item    = safe(patch.get_property, player, "selectedItem")
        if SP_selected_item then
            M_sel_prop_getter = safe(patch.property_get_method, SP_selected_item)
        end
        SP_held_item = safe(patch.get_property, player, "HeldItem")
        if SP_held_item then
            M_held_prop_getter = safe(patch.property_get_method, SP_held_item)
        end
        P.m_item_check = safe(patch.get_method, player, "ItemCheck", 0)
            or safe(patch.get_method, player, "ItemCheck")
        if not P.m_item_check then
            note_err("找不到 Player.ItemCheck 方法, 缓存补充不可用(不影响主路径)")
        end
        if not F_player_active then
            note_err("找不到 Player.active 字段, 无法区分玩家/NPC 弹幕")
        end
    else
        note_err("找不到 Terraria.Player 类型, 按武器配置不可用")
    end

    -- Main.player (static Player[]) —— 主路径数据源
    local main = safe(patch.get_type, "Terraria", "Main")
    if main then
        F_main_player = safe(patch.get_field, main, "player")
    end

    local item = safe(patch.get_type, "Terraria", "Item")
    if item then
        item_type = safe(patch.get_field, item, "type")
    end

    if not (F_main_player and item_type) then
        note_err("主路径句柄不完整(Main.player/Item.type), 按武器配置不可用")
    end
    -- v1.7.0 召唤探测: Projectile.Damage / NPC.StrikeNPC / Main.projPet
    P.m_damage = safe(patch.get_method, projectile, "Damage", 0)
        or safe(patch.get_method, projectile, "Damage")
    if not P.m_damage then
        note_err("找不到 Projectile.Damage 方法, 召唤探测不可用(不影响三模式主功能)")
    end
    local npc_type = safe(patch.get_type, "Terraria", "NPC")
    if npc_type then
        P.m_npc_strike = safe(patch.get_method, npc_type, "StrikeNPC", 6)
            or safe(patch.get_method, npc_type, "StrikeNPC")
        if not P.m_npc_strike then
            note_err("找不到 NPC.StrikeNPC 方法, 召唤探测不可用(不影响三模式主功能)")
        end
    else
        note_err("找不到 Terraria.NPC 类型, 召唤探测不可用(不影响三模式主功能)")
    end
    if main then
        F_proj_pet = safe(patch.get_field, main, "projPet")
        if not F_proj_pet then
            note_err("找不到 Main.projPet 字段, 召唤类型判定退化为兜底表")
        end
    end
end

function setup()
    mod.info("[IFrame] 初始化 武器无敌帧 模组 v" .. tostring(mod.meta.version))
    load_config()
    bind_patch()
    if P.m_ai then
        local ok, h = pcall(patch.install_hook, P.m_ai, {
            postfix = on_projectile_ai })
        if ok and h then
            hook_ai = h
            mod.info("[IFrame] Projectile.AI Hook 安装成功 (主路径)")
        else
            note_err("Projectile.AI Hook 安装失败: " .. tostring(h))
        end
    end
    if P.m_item_check then
        local ok2, h2 = pcall(patch.install_hook, P.m_item_check, {
            postfix = on_item_check })
        if ok2 and h2 then
            hook_item_check = h2
            mod.info("[IFrame] Player.ItemCheck Hook 安装成功 (缓存补充)")
        else
            note_err("Player.ItemCheck Hook 安装失败: " .. tostring(h2) .. " (将完全依赖 AI 实时读取)")
        end
    end
    -- v1.7.0 召唤探测 hooks (prefix+postfix 配对)
    if P.m_damage then
        local ok3, h3 = pcall(patch.install_hook, P.m_damage, {
            prefix = on_proj_damage,
            postfix = on_proj_damage_done })
        if ok3 and h3 then
            hook_damage = h3
            mod.info("[IFrame] Projectile.Damage Hook 安装成功 (召唤探测)")
        else
            note_err("Projectile.Damage Hook 安装失败: " .. tostring(h3))
        end
    end
    if P.m_npc_strike then
        local ok4, h4 = pcall(patch.install_hook, P.m_npc_strike, {
            postfix = on_npc_strike })
        if ok4 and h4 then
            hook_npc_strike = h4
            mod.info("[IFrame] NPC.StrikeNPC Hook 安装成功 (召唤探测)")
        else
            note_err("NPC.StrikeNPC Hook 安装失败: " .. tostring(h4))
        end
    end
    write_diag()  -- 无论成败都写一份诊断, 便于一次性定位
end

function cleanup()
    if hook_ai then pcall(hook_ai.remove, hook_ai) hook_ai = nil end
    if hook_item_check then pcall(hook_item_check.remove, hook_item_check) hook_item_check = nil end
    if hook_damage then pcall(hook_damage.remove, hook_damage) hook_damage = nil end
    if hook_npc_strike then pcall(hook_npc_strike.remove, hook_npc_strike) hook_npc_strike = nil end
    damage_ctx = nil
    owner_weapon = {}
    processed = {}
    write_diag()
end

todo_list = { "setup" }