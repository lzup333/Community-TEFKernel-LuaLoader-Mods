--=====================================================================
-- 心之钢 (Heartsteel) v2.3.1 —— 饰品版
-- 装备「心之钢」饰品后，命中敌怪叠层；叠满引爆：造成基于最大生命的伤害、回复生命，
-- 并永久提升少量最大生命。未佩戴时完全不生效。
--
-- 修复（全部对照 1.4.5.8.6 源码核实）：
--   · StrikeNPC 的 argc 5 -> 6（NPC.cs:4869，只有 6 参一个重载）
--   · Main.myPlayer 是属性 -> 用 property_get_method 取 getter（Main.cs:7187）
--   · NewText 4 参 -> 5 参（只有 3 参和 5 参两个重载，Main.cs:14190/14196）
--   · pkg_id 与 Info.json 的 pkgId 统一为 omni.lua.heartsteel
--   · config.json 真正读取，缺失/损坏全部回落默认值
--   · 冷却表改用 npc.whoAmI 整数下标（对象句柄是借用的，不能跨帧当 key）
--   · array_at 加越界检查；cleanup 里 remove 钩子；撤掉聊天栏刷屏
--   · NPC.CountsAsACritter 是属性，走 get_CountsAsACritter（NPC.cs:2409）
--   · ApplyDamageToNPC 的 PlayerNPCHitSource 是 struct，改用 StrikeNPC 自身造成伤害
--
-- v2.3.0：永久生命改为「每帧补到 statLifeMax2」
--   原版 statLifeMax 有 500 硬上限，直接写会被存档削回 500；
--   改为把加成存进 heartsteel.dat，每帧加到有效上限 statLifeMax2 上，不受上限影响。
--=====================================================================
require("quickapi")

local q     = mod.quickapi
local patch = mod.patch

--==================== 默认配置（config.json 缺失时的兜底）====================
local DEFAULTS = {
    max_stacks       = 3,    -- 引爆所需层数
    dmg_ratio        = 10,   -- 引爆伤害 = 最大生命 × 该百分比
    heal_ratio       = 50,   -- 回复 = 造成伤害 × 该百分比
    life_gain_tenths = 5,    -- 每次引爆永久生命 ×0.1（5 = +0.5；10 = +1.0）
    filter_mode      = 1,    -- 敌怪过滤：1 仅敌对 / 2 仅Boss / 3 敌对且≥100血 / 4 不过滤
    npc_cooldown     = 30,   -- 同一目标引爆冷却（秒）
}

local FILTER_NAME = {
    [1] = "仅敌对怪（排除小动物/友好/无敌）",
    [2] = "仅 Boss",
    [3] = "敌对怪且血量 ≥100",
    [4] = "不过滤（任何被打中的 NPC）",
}

local SAVE_FILE = "heartsteel.dat"

--==================== 运行时状态 ====================
local S = {
    cfg      = {},
    stacks   = 0,
    acc      = 0,      -- 永久生命的小数累计（statLifeMax 是 int，攒够 1 才写）
    gained   = 0,      -- 已累计获得的整点生命（仅用于显示）
    procs    = 0,      -- 引爆次数
    npc_cd   = {},     -- whoAmI -> os.time 到期时间
    in_proc  = false,  -- 重入锁：引爆时自己调 StrikeNPC 会再次触发钩子
    last_save = 0,
    last_base    = nil,   -- 上一帧 statLifeMax2 的基础值
    last_written = nil,   -- 上一帧我们写进去的值
    ready    = false,
}

local H = {}           -- 句柄缓存
local hook_strike, hook_equips

--==================== 句柄解析 ====================
local function find_field(T, name)
    local cur, guard = T, 0
    while cur and guard < 32 do
        local f = patch.get_field(cur, name)
        if f then return f end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local NPC_FIELDS = { "active", "friendly", "townNPC", "boss", "immortal",
                     "lifeMax", "type", "whoAmI" }

local function bind()
    local T_NPC    = q.type("Terraria", "NPC")
    local T_PLAYER = q.type("Terraria", "Player")
    local T_MAIN   = q.type("Terraria", "Main")
    if not T_NPC or not T_PLAYER or not T_MAIN then
        mod.error("[心之钢] 取不到 Terraria.NPC / Player / Main 类型")
        return false
    end

    for _, n in ipairs(NPC_FIELDS) do
        H[n] = find_field(T_NPC, n)
        if not H[n] then mod.warn("[心之钢] NPC 字段缺失: " .. n) end
    end
    H.player      = find_field(T_MAIN, "player")   -- Main.player 静态 Player[]
    H.statLifeMax  = find_field(T_PLAYER, "statLifeMax")   -- 基础上限（原版 500 硬顶）
    H.statLifeMax2 = find_field(T_PLAYER, "statLifeMax2")  -- 有效上限（装备加成后的）
    H.armor       = find_field(T_PLAYER, "armor")        -- Player.armor  Item[]
    H.itemType    = find_field(q.type("Terraria", "Item"), "type")
    H.statLife    = find_field(T_PLAYER, "statLife")

    -- 属性：Main.myPlayer -> getter 方法
    local prop = patch.get_property and patch.get_property(T_MAIN, "myPlayer")
    if prop then
        H.m_myPlayer = patch.property_get_method and patch.property_get_method(prop)
    end
    if not H.m_myPlayer then
        H.m_myPlayer = patch.get_method(T_MAIN, "get_myPlayer", 0)
    end

    -- 属性：NPC.CountsAsACritter -> getter 方法
    H.m_critter = patch.get_method(T_NPC, "get_CountsAsACritter", 0)

    H.m_strike = patch.get_method(T_NPC, "StrikeNPC", 6)
    H.m_heal   = patch.get_method(T_PLAYER, "Heal", 1)

    local miss = {}
    for _, k in ipairs({ "active", "friendly", "townNPC", "boss", "immortal", "lifeMax" }) do
        if not H[k] then miss[#miss + 1] = k end
    end
    if #miss > 0 then
        mod.error("[心之钢] 关键字段缺失，功能无法工作: " .. table.concat(miss, ", "))
        return false
    end
    if not H.m_strike then mod.error("[心之钢] 取不到 NPC.StrikeNPC(6)") return false end
    return true
end

--==================== 配置与存档 ====================
-- config.json 由 TEFManager 的设置界面写入，格式 { "schemaVersion":1, "values": { ... } }
-- 值可能是数字或字符串（CHOICE 类型），所以引号要可选
local function parse_cfg(text)
    for k, def in pairs(DEFAULTS) do
        local v = text:match('"' .. k .. '"%s*:%s*"?(%d+)')
        local n = tonumber(v)
        if n ~= nil then S.cfg[k] = n else S.cfg[k] = def end
    end
    -- 每次永久生命以「十分之一」为单位存储，转成实际数值
    S.cfg.life_gain = (tonumber(S.cfg.life_gain_tenths) or 5) / 10
end

local function load_cfg()
    for k, v in pairs(DEFAULTS) do S.cfg[k] = v end
    S.cfg.life_gain = DEFAULTS.life_gain_tenths / 10
    local ok, txt = pcall(mod.read_file, "config.json")
    if ok and type(txt) == "string" and #txt > 0 then pcall(parse_cfg, txt) end
end

-- 只持久化「小数累计」和统计；参数每次从 config.json 读，避免两处打架
local function load_state()
    local ok, txt = pcall(mod.read_file, SAVE_FILE)
    if not ok or type(txt) ~= "string" or #txt == 0 then return end
    local acc, gained, procs = txt:match("^([%-%d%.]+)|(%d+)|(%d+)")
    if acc then
        S.acc    = tonumber(acc) or 0
        S.gained = tonumber(gained) or 0
        S.procs  = tonumber(procs) or 0
    end
end

local function save_state(force)
    local now = os.time()
    if not force and now - S.last_save < 3 then return end
    S.last_save = now
    local txt = string.format("%.4f|%d|%d", S.acc, S.gained, S.procs)
    pcall(mod.write_file, SAVE_FILE, txt)
end

--==================== 读数工具 ====================
local function gi(f, inst) return patch.get_field_value(f, inst, "int32") end
local function gb(f, inst) return patch.get_field_value(f, inst, "bool") end
local function si(f, inst, v) if f then patch.set_field_value(f, inst, v, "int32") end end

--==================== 佩戴判定 ====================
-- 注册阶段 runtime_id 是 -1，进世界后才有效，所以延迟解析并缓存
local function acc_id()
    if type(S.item_id) == "number" and S.item_id > 0 then return S.item_id end
    local id = q.item_id("Heartsteel")
    if type(id) == "number" and id > 0 then
        S.item_id = id
        return id
    end
    return nil
end

local function has_acc(player)
    local id = acc_id()
    if not id or not H.armor or not H.itemType then return false end
    local armor = patch.get_field_value(H.armor, player, "object")
    if not armor then return false end
    -- armor[0..2] 是头/身/腿，armor[3..9] 是 7 个饰品槽
    for i = 3, 9 do
        local it = patch.array_at(armor, i)
        if it and gi(H.itemType, it) == id then return true end
    end
    return false
end

--==================== 敌怪过滤 ====================
local function pass_filter(npc)
    local mode = math.floor(S.cfg.filter_mode + 0.5)

    if mode == 4 then return true end                       -- 不过滤

    if not gb(H.active, npc) then return false end
    if gb(H.friendly, npc) then return false end
    if gb(H.townNPC, npc) then return false end
    if gb(H.immortal, npc) then return false end
    if mode ~= 2 and H.m_critter then                       -- Boss 模式不判小动物
        local okc, isc = pcall(q.call, H.m_critter, npc)
        if okc and isc == true then return false end
    end

    if mode == 2 then                                       -- 仅 Boss
        return gb(H.boss, npc) == true
    elseif mode == 3 then                                   -- 敌对且血量 ≥100
        local lm = gi(H.lifeMax, npc) or 0
        return lm >= 100
    end
    return true                                             -- 模式 1：仅敌对
end

--==================== 引爆 ====================
local function do_proc(player, npc, my_idx)
    local maxLife = gi(H.statLifeMax2, player) or gi(H.statLifeMax, player) or 0

    -- 伤害：按最大生命百分比
    local dmg = math.floor(maxLife * S.cfg.dmg_ratio / 100)
    if dmg < 1 then dmg = 1 end

    -- 用 StrikeNPC 自己结算（避免 ApplyDamageToNPC 的结构体参数问题）
    if H.m_strike then
        S.in_proc = true
        pcall(patch.invoke, H.m_strike, npc, dmg, 0.0, 0, false, false, my_idx)
        S.in_proc = false
    end

    -- 治疗
    local heal = math.floor(dmg * S.cfg.heal_ratio / 100)
    if heal > 0 and H.m_heal then
        pcall(patch.invoke, H.m_heal, player, heal)
    end

    -- 永久生命：小数累计。不再写 statLifeMax（原版有 500 硬上限，写了会被存档削掉），
    -- 而是累加到 S.gained，由 on_equips 每帧补到 statLifeMax2 上
    S.acc = S.acc + (tonumber(S.cfg.life_gain) or 0)
    local whole = math.floor(S.acc)
    if whole >= 1 then
        S.acc = S.acc - whole
        S.gained = S.gained + whole
        -- 顺带回一点当前血，让血条不至于因为上限变高而显得很空
        local cur_life = gi(H.statLife, player) or 0
        si(H.statLife, player, cur_life + whole)
    end

    S.procs = S.procs + 1
    save_state(false)
end

--==================== Hook 回调 ====================
-- 本地玩家索引（缓存；取不到时返回 nil）
local function my_index()
    if type(S.my_idx) == "number" then return S.my_idx end
    if H.m_myPlayer then
        local ok, v = pcall(patch.invoke, H.m_myPlayer)
        if ok and type(v) == "number" and v >= 0 and v <= 254 then
            S.my_idx = v
            return v
        end
    end
    return nil
end

local function on_strike(npc, args, result)
    if S.in_proc then return end                     -- 重入锁：自己造成的伤害不再计层
    if not npc then return end
    if type(result) ~= "number" or result <= 0 then return end

    -- 先过滤敌怪（便宜，先挡掉大部分 NPC）
    if not pass_filter(npc) then return end

    -- 解析本地玩家
    local idx = my_index()
    if not idx then return end
    local players = patch.get_field_value(H.player, nil, "object")
    if not players then return end
    local player = patch.array_at(players, idx)
    if not player then return end

    -- 只在佩戴「心之钢」时生效
    S.equipped = has_acc(player)
    if not S.equipped then return end

    -- 只算本地玩家打出的
    local owner = args and args[6]
    if type(owner) == "number" and owner >= 0 and owner ~= idx then return end

    -- 同目标冷却（用 whoAmI 整数下标，不用对象句柄）
    local wa = gi(H.whoAmI, npc)
    if type(wa) == "number" and wa >= 0 then
        local now = os.time()
        local until_ = S.npc_cd[wa]
        if until_ and now < until_ then return end
    end

    S.stacks = S.stacks + 1
    local need = math.max(1, math.floor((S.cfg.max_stacks or 3) + 0.5))
    if S.stacks < need then return end

    S.stacks = 0
    if type(wa) == "number" and wa >= 0 then
        S.npc_cd[wa] = os.time() + (S.cfg.npc_cooldown or 30)
    end

    do_proc(player, npc, idx)
end

--==================== 面板 ====================

--==================== 生命周期 ====================
--==================== 每帧补生命上限 ====================
local function on_equips(player)
    if not player then return end
    if not H.statLifeMax2 then return end
    local bonus = S.gained or 0
    if bonus <= 0 then return end

    local cur = gi(H.statLifeMax2, player)
    if type(cur) ~= "number" then return end

    -- 判断这一帧游戏有没有重算 statLifeMax2：
    --   重算了 → cur 就是基础值
    --   没重算 → cur 是我们上帧写进去的，基础值要减去已加的加成
    local base
    if S.last_written and cur == S.last_written then
        base = S.last_base or (cur - bonus)
    else
        base = cur
    end

    local want = base + bonus
    if want ~= cur then si(H.statLifeMax2, player, want) end
    S.last_base    = base
    S.last_written = want
end

function mod.init()
    -- 注册饰品。注册阶段内核还没分配 ID，runtime_id 为 -1，必须运行时再查
    q.register_item({
        name      = "Heartsteel",
        texture   = "heartsteel.png",       -- 32x32 PNG，放在 Resources/Image/
        tooltip   = true,
        accessory = true,
        width     = 24,
        height    = 24,
        rare      = 5,
        value     = 200000,
        prefixes  = false,
        language  = {
            zh = {
                name    = "心之钢",
                tooltip = "命中敌怪时叠层，叠满后引爆：\n"
                       .. "· 对目标造成基于你最大生命的伤害\n"
                       .. "· 回复部分生命\n"
                       .. "· 永久提升少量最大生命\n"
                       .. "——越战越强，越强越战",
            },
            en = {
                name    = "Heartsteel",
                tooltip = "Hits build stacks. At max stacks, detonate: damage based on your max life, heal, and permanently gain a little max life.",
            },
        },
        recipe = {
            result = 1,
            materials = {
                { id = 22,  count = 12 },   -- 铁锭
                { id = 178, count = 3 },    -- 红宝石
            },
            station = 18,                   -- 工作台
        },
    })

    load_cfg()
    load_state()
    if not bind() then return end

    -- 每帧把「永久生命加成」补到有效上限 statLifeMax2 上
    -- （statLifeMax 有原版 500 硬上限，写超过会被存档削掉）
    hook_equips = q.install_hook_postfix("Terraria", "Player", "UpdateEquips",
            function(player) pcall(on_equips, player) end, { argc = 1 })
    if not hook_equips then
        mod.error("[心之钢] UpdateEquips 钩子安装失败，永久生命不会生效")
    end

    hook_strike = q.install_hook_postfix("Terraria", "NPC", "StrikeNPC",
            function(npc, args, result) pcall(on_strike, npc, args, result) end,
            { argc = 6 })

    if not hook_strike then
        mod.error("[心之钢] StrikeNPC 钩子安装失败")
        return
    end
    S.ready = true
    mod.info(string.format("[心之钢] v2.3.1 已加载：%d 层引爆 / 伤害 %d%% / 回复 %d%% / 永久 +%.1f / 冷却 %d 秒 / 过滤 %s",
        math.floor(S.cfg.max_stacks + 0.5), math.floor(S.cfg.dmg_ratio + 0.5),
        math.floor(S.cfg.heal_ratio + 0.5), S.cfg.life_gain,
        math.floor(S.cfg.npc_cooldown + 0.5),
        FILTER_NAME[math.floor(S.cfg.filter_mode + 0.5)] or "?"))
end

function mod.cleanup()
    for _, h in ipairs({ hook_strike, hook_equips }) do
        if h then pcall(function() h:remove() end) end
    end
    hook_strike, hook_equips = nil, nil
    save_state(true)
    H = {}
    S.ready = false
end
