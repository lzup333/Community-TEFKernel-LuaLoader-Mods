-- 更好的DPS v1.0.0 —— 召唤物锁定傀儡 + DPS 显示计入陷阱与减益
-- 目标版本：Terraria 1.4.5.8 手机版 + LuaLoader
-- ============================================================================
-- 一、召唤物锁定傀儡
--   训练用傀儡 = NPC type 488（NPC.cs:14618）。它被 SetDefaults 里设成
--   `immortal = true`，而 NPC.CanBeChasedBy（NPC.cs:91139）：
--       if (active && chaseable && lifeMax > 5 && (!dontTakeDamage|ignore) && !friendly) {
--           if (!DebugOptions.LetProjectilesAimAtTargetDummies) return !immortal;  // ← 这里
--           return true;
--       }
--   → 因为 immortal，恒返回 false，召唤物永远不把傀儡当目标。
--   本模组 hook CanBeChasedBy 的 postfix（override_result），对 488 强制返回 true。
-- ----------------------------------------------------------------------------
-- 二、DPS 计入陷阱与减益
--   原版 DPS 只在 3 个地方累加，且都要求玩家带 DPS 类配件（accDreamCatcher）：
--       Player.cs:20608  ApplyDamageToNPC（玩家直接攻击）
--       Player.cs:44775  近战命中
--       Projectile.cs:13710  玩家投射物命中
--   DPS 真实算法在 Player.addDPS / getDPS（Player.cs:54868），
--   所有 DPS 配件（每秒伤害计数器、哥布林数据仪、个人数字助手、手机、贝壳电话）
--   读的都是同一份 player.dpsDamage，所以只要把伤害补进 addDPS，全部配件同步生效。
--
--   ① 减益：所有 DoT 实际扣血都走 NPC.GetHurtByDebuff(int)（NPC.cs:92986），
--      原版这里不记 DPS → hook postfix 补 addDPS(amount)。
--   ② 陷阱：NPC.StrikeNPC(int, float, int, bool, bool, int owner) 的第 6 参是伤害归属。
--      玩家造成的走 owner = 玩家索引（原版已统计，跳过）；
--      陷阱弹幕 / 尖刺 / 环境伤害走 owner = 255 或 -1 → 补 addDPS(返回值)。
--      这样不会与原有统计重复。
-- ----------------------------------------------------------------------------
-- 配置（TEFManager 设置页 → Resources/config.json）：
--   lock_dummy / count_trap / count_debuff 三个开关，默认全开。
-- 安全：只碰 hook 传入的实例；实例不跨帧缓存；全部 pcall 保护。
-- ============================================================================
mod.meta = { pkg_id = "bluefish.betterdps", version = "1.0.1", version_code = 2 }

local P = mod.patch
local H, hooks = {}, {}
local disabled = false

local ANN_TEXT = "知己知彼方能百战百胜～（∠·ω< )⌒☆"
local ANN_DELAY = 60

local DUMMY_TYPE = 488

local CFG = {
    lock_dummy   = true,
    count_trap   = true,
    count_debuff = true,
}

local function log(s)
    pcall(mod.info, "[更好的DPS] " .. tostring(s))
end

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 1e8
end

local function find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local f = P.get_field(cur, name)
        if f then return f end
        cur = P.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function rd(field, inst, ty)
    if not field or not inst then return nil end
    local ok, v = pcall(P.get_field_value, field, inst, ty)
    if ok then return v end
    return nil
end

-- ---------------- 配置 ----------------
local function parse_bool(raw, key, def)
    local lit = raw:match('"' .. key .. '"%s*:%s*([%a]+)')
    if lit == "true" then return true end
    if lit == "false" then return false end
    return def
end

local function refresh_config()
    if type(mod.read_file) ~= "function" then return end
    local ok, raw = pcall(mod.read_file, "config.json")
    if not ok or type(raw) ~= "string" then return end
    CFG.lock_dummy   = parse_bool(raw, "lock_dummy", CFG.lock_dummy)
    CFG.count_trap   = parse_bool(raw, "count_trap", CFG.count_trap)
    CFG.count_debuff = parse_bool(raw, "count_debuff", CFG.count_debuff)
end

-- ---------------- 取本机玩家（每次现取，不跨帧缓存） ----------------
local function my_player()
    local user = rd(H.f_active_user, nil, "object") or rd(H.f_primary_user, nil, "object")
    local state = user and rd(H.f_user_state, user, "object")
    if not state then return nil end
    local idx = rd(H.f_my_player, state, "int32")
    local players = rd(H.f_players, nil, "object")
    if not (players and finite(idx) and idx >= 0 and idx <= 254) then return nil end
    local ok, pl = pcall(P.array_at, players, idx)
    if ok then return pl end
    return nil
end

-- 只有带 DPS 类配件时才补（与原版口径一致）
local function dps_ready(pl)
    if not pl then return false end
    return rd(H.f_dream, pl, "bool") == true
end

-- 只往 player.dpsDamage 里加数值，绝不调用 addDPS。
-- 原因（v1.0.1 修正）：玩家 addDPS 有两个坑会拉低显示：
--   ① dpsStarted 为 false（3 秒没出手）时，它把 dpsDamage 直接覆盖成这一击的数值
--      → 玩家打了 300，DOT 再补 12，显示反而从 300 掉到 12
--   ② 它每 2 秒刷新一次 dpsLastHit，统计窗口不断被拉长，
--      getDPS 归一化时用大分母一除，数值被摊薄 → 越小
-- 直接改 dpsDamage 不动时间轴，原窗口语义完全保留。
local function add_dps(pl, dmg)
    if not (H.f_dps_damage and finite(dmg) and dmg > 0) then return end
    local cur = rd(H.f_dps_damage, pl, "int32")
    if not finite(cur) then return end
    pcall(P.set_field_value, H.f_dps_damage, pl, cur + math.floor(dmg), "int32")
end

-- ---------------- ① 召唤物锁定傀儡 ----------------
local function on_can_chase(inst, args, result)
    if disabled or not CFG.lock_dummy then return nil end
    if result == true then return nil end          -- 原本就能追，不动
    if not inst then return nil end
    if rd(H.n_type, inst, "int32") ~= DUMMY_TYPE then return nil end
    if rd(H.n_active, inst, "bool") ~= true then return nil end
    if (rd(H.n_life_max, inst, "int32") or 0) <= 5 then return nil end
    if rd(H.n_dont_damage, inst, "bool") == true then return nil end
    -- 强制返回 true：召唤物把傀儡当作可锁定目标
    return true
end

-- ---------------- ② DPS 计入陷阱 ----------------
local function on_strike_npc(inst, args, result)
    if disabled or not CFG.count_trap then return end
    if not inst then return end
    if type(result) ~= "number" or result <= 0 then return end
    local owner = args and args[6]
    if type(owner) ~= "number" then return end
    -- 0..254 = 由某个玩家造成，原版已统计，跳过
    if owner >= 0 and owner <= 254 then return end
    local pl = my_player()
    if not dps_ready(pl) then return end
    add_dps(pl, result)
end

-- ---------------- ③ DPS 计入减益 ----------------
local function on_hurt_debuff(inst, args, result)
    if disabled or not CFG.count_debuff then return end
    if not inst then return end
    local amount = args and args[1]
    if type(amount) ~= "number" or amount <= 0 then return end
    local pl = my_player()
    if not dps_ready(pl) then return end
    add_dps(pl, amount)
end

-- ---------------- 播报 ----------------
local frames = 0
local announced = false

local function in_world()
    local user = rd(H.f_active_user, nil, "object") or rd(H.f_primary_user, nil, "object")
    local state = user and rd(H.f_user_state, user, "object")
    if not state then return false end
    return rd(H.f_menu, state, "bool") ~= true
end

local function say(text)
    if not H.m_newtext5 then return false end
    local s = text
    if P.string_create then
        local ok, r = pcall(P.string_create, text)
        if ok and r then s = r end
    end
    local ok, r = pcall(P.invoke, H.m_newtext5, s, 200, 190, 255, false)
    return ok and r ~= false
end

local function on_main_update()
    if announced then return end
    if not in_world() then
        frames = 0
        return
    end
    frames = frames + 1
    if frames == 1 then refresh_config() end
    if frames >= ANN_DELAY then
        if say(ANN_TEXT) then announced = true end
    end
end

local function chk(cond, name)
    if not cond then error(name, 2) end
    return cond
end

local function field(t, name)
    return chk(P.get_field(t, name), "缺少字段 " .. name)
end

function setup()
    refresh_config()
    local ok, e = pcall(function()
        local main = chk(P.get_type("Terraria", "Main"), "缺少类型 Main")
        local nt   = chk(P.get_type("Terraria", "NPC"), "缺少类型 NPC")
        local pt   = chk(P.get_type("Terraria", "Player"), "缺少类型 Player")
        local st   = chk(P.get_type("", "LocalUserGameState"), "缺少类型 LocalUserGameState")
        local user_t  = chk(P.get_type("", "LocalUser"), "缺少类型 LocalUser")
        local users_t = chk(P.get_type("", "UserManagement"), "缺少类型 UserManagement")

        H.f_active_user  = field(user_t, "Active")
        H.f_primary_user = field(users_t, "PrimaryPlayer")
        H.f_user_state   = field(user_t, "GameState")
        H.f_my_player    = field(st, "myPlayer")
        H.f_menu         = field(st, "gameMenu")
        H.f_players      = field(main, "player")

        H.n_type        = find_field(nt, "type")
        H.n_active      = find_field(nt, "active")
        H.n_life_max    = find_field(nt, "lifeMax")
        H.n_dont_damage = find_field(nt, "dontTakeDamage")
        H.f_dream       = find_field(pt, "accDreamCatcher")
        H.f_dps_damage  = find_field(pt, "dpsDamage")
        H.m_newtext5    = P.get_method(main, "NewText", 5)
        H.m_update      = P.get_method(main, "Update", 1) or P.get_method(main, "Update", 0)

        chk(H.n_type and H.n_active and H.n_life_max, "NPC 字段缺失")
        chk(H.f_dream, "Player.accDreamCatcher 缺失")
        chk(H.f_dps_damage, "Player.dpsDamage 缺失")

        -- ① CanBeChasedBy（参数个数因版本而异，逐个尝试）
        local m_chase = P.get_method(nt, "CanBeChasedBy", 2)
            or P.get_method(nt, "CanBeChasedBy", 1)
            or P.get_method(nt, "CanBeChasedBy", 0)
        if m_chase then
            local h = P.install_hook(m_chase, { postfix = on_can_chase, override_result = true })
            if h then hooks[#hooks + 1] = h end
        end

        -- ② StrikeNPC(6)
        local m_strike = P.get_method(nt, "StrikeNPC", 6)
        if m_strike then
            local h = P.install_hook(m_strike, { postfix = on_strike_npc })
            if h then hooks[#hooks + 1] = h end
        end

        -- ③ GetHurtByDebuff(1)
        local m_dot = P.get_method(nt, "GetHurtByDebuff", 1)
        if m_dot then
            local h = P.install_hook(m_dot, { postfix = on_hurt_debuff })
            if h then hooks[#hooks + 1] = h end
        end

        if H.m_update then
            local h = P.install_hook(H.m_update, { postfix = on_main_update })
            if h then hooks[#hooks + 1] = h end
        end

        log(string.format("就绪 钩子=%d 傀儡锁=%s 陷阱=%s 减益=%s",
            #hooks, tostring(CFG.lock_dummy), tostring(CFG.count_trap), tostring(CFG.count_debuff)))
    end)
    if not ok then
        disabled = true
        log("初始化失败: " .. tostring(e))
    end
end

function cleanup()
    disabled = true
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
    log("已卸载")
end

todo_list = { "setup" }