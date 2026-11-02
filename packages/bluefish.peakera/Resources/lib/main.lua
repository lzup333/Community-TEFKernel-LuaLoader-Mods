mod.meta = { pkg_id = "bluefish.peakera", version = "8.0.0", version_code = 800, api_version = 1 }
-- 巅峰时代 / 作者：蓝色大肥鱼
-- 力量又回来了
-- ---------------------------------------------------------------------------
-- 改动一览（对应 1.4.5.8 反编译源码）：
--   1. 幽灵兜帽套装吸血固定 10%，并取消原版「打中递减」
--      （原版 0.2 - numHits*0.05，打第 5 下就没吸血了）
--      lifeSteal 每次只扣 1%，等效额度上限 ×100
--   2. 幽灵兜帽套装：取消 40% 魔法伤害惩罚（magicDamage +0.4，每帧补）
--   3. 进图 1 秒后播报「力量又回来了(◣_◢)」
--   4. 黑曜石套（3266 帽 + 3267 长衣 + 3268 裤）套装奖励强化：
--      鞭范围 +50%（whipRangeMultiplier = 1.5）
--      鞭速度 +50%（whipUseTimeMultiplier = 0.5，使用间隔减半）
--      召唤伤害 +25%（在装备加成之上再加 0.25）
--   5. 泰拉刃（757）回归 1.4.4 之前的数值，全部走「动态覆盖」，不写任何物品数据：
--      伤害 85 → 115（钩 Player.GetWeaponDamage，按 115/85 缩放，词缀倍率天然保留）
--      使用时间 18 → 14（ItemCheck 前后临时改 useTime/useAnimation，用完立刻还原）
--      近战速度加成折扣 ×0.75 → ×1.0（ItemCheck 前把已打折的 meleeSpeed 换算回全额）
-- ---------------------------------------------------------------------------

local patch = mod.patch

-- 【测试版专用】日志落盘到项目目录；正式版这里是空的
-- 转正版：不写任何文件（日志实现留空，改回落盘只需恢复 logf 内部）
local function logf(_) end

-- ============ 模组设置 ============
-- 开关由 TEFManager「模组设置」界面写入 Resources/config.json（schemaVersion:1 + values），
-- 声明在 Info.json 的 settings 数组里。这里启动时读一次，覆盖下面的默认值。
-- 读不到 / 解析失败 / 字段缺失 → 一律回落到默认值 true（默认全开）。
local CFG = {
    ghost     = true,   -- 幽灵套：吸血固定 10% + 无上限 + 不再降 40% 魔法伤害
    obsidian  = true,   -- 黑曜石套：鞭范围/鞭速度/召唤伤害
    terra     = true,   -- 泰拉刃：伤害 115 / 使用时间 14 / 攻速不打折
    blade     = true,   -- 刃杖：取消 33% 标记伤害惩罚
    typhoon   = true,   -- 利刃台风：伤害 90 / 使用时间 20 / 双发 / 3 秒
    phantasm  = true,   -- 幻影弓：50 → 70
    holy      = true,   -- 圣箭：神圣之星 100% 伤害 + 穿透 2
    unholy    = true,   -- 邪箭：穿透后不衰减
    jester    = true,   -- 小丑之箭：穿透后不衰减
    crystal   = true,   -- 水晶子弹：3 个碎片
    chloro    = true,   -- 叶绿弹：9 → 15
}

local function cfg_truthy(v)
    if type(v) == "boolean" then return v end
    if type(v) == "string" then return (v == "true" or v == "1") end
    return nil
end

local function load_config()
    local ok, text = pcall(function() return mod.read_file("config.json") end)
    if not ok or not text then
        logf("[cfg] config.json 读取失败，全部使用默认值（开）")
        return
    end
    local okj, dkjson = pcall(require, "dkjson")
    if not okj or type(dkjson) ~= "table" then
        logf("[cfg] dkjson 不可用，全部使用默认值（开）")
        return
    end
    local okp, raw = pcall(dkjson.decode, text)
    if not okp or type(raw) ~= "table" or type(raw.values) ~= "table" then
        logf("[cfg] config.json 解析失败，全部使用默认值（开）")
        return
    end
    local v = raw.values
    local okc, err = pcall(function()
        for k in pairs(CFG) do
            local val = cfg_truthy(v[k])
            if val ~= nil then CFG[k] = val end
        end
    end)
    if not okc then logf("[cfg] 应用配置异常: " .. tostring(err)) end
    logf(string.format(
        "[cfg] ghost=%s obs=%s terra=%s blade=%s typh=%s phant=%s holy=%s unholy=%s jester=%s crystal=%s chloro=%s",
        tostring(CFG.ghost), tostring(CFG.obsidian),
        tostring(CFG.terra), tostring(CFG.blade), tostring(CFG.typhoon),
        tostring(CFG.phantasm), tostring(CFG.holy), tostring(CFG.unholy),
        tostring(CFG.jester), tostring(CFG.crystal), tostring(CFG.chloro)))
end

-- ============ 常量 ============
local GHOST_HEAL_RATE   = 0.10        -- 吸血比例固定 10%（原版 0.2 - numHits*0.05，打 5 下就没）
local GHOST_MAGIC_FIX   = 0.4
-- 抵消多少比例的幽灵套魔伤惩罚：
--   0.0 = 完全取消（伤害回到不穿幽灵套的水平）
--   0.5 = 抵消一半
--   1.0 = 完全不抵消（原版）
local GHOST_PENALTY_KEEP = 0.5
local LIFESTEAL_COST_SCALE = 0.01   -- 吸血时只消耗 1% 额度（等效上限 ×100）
local ECHO_DELAY_FRAMES = 60          -- 约 1 秒

-- ============ 黑曜石套（3266 帽 / 3267 长衣 / 3268 裤）============
-- 原版套装奖励：鞭范围 / 鞭速度 / 召唤伤害各有一档，这里直接顶到目标值。
-- 鞭范围：whipRangeMultiplier（乘算系数，1.0 = 原样），1.5 = 范围 +50%
-- 鞭速度：whipUseTimeMultiplier（使用间隔倍率，越小越快），0.5 = 间隔减半 = 速度 +50%
-- 召唤伤害：minionDamage 是加算系数，套装奖励部分给到 0.25
local OBSIDIAN_ARMOR = { [0] = 3266, [1] = 3267, [2] = 3268 }
local OBSIDIAN_WHIP_RANGE  = 0.50
local OBSIDIAN_WHIP_SPEED  = 0.50
local OBSIDIAN_MINION_DMG  = 0.25

-- ============ 泰拉刃（757）回归旧版数值 ============
-- 原版 Item.cs: damage 85 / useTime 18 / useAnimation 18 / noMelee（伤害全在剑气 985）
-- 近战速度折扣：Player.Update 内 meleeSpeed = 1 + (meleeSpeed-1) × BonusMeleeSpeedMultiplier[手持物品]
-- 泰拉刃系数 0.75，即「降低 25%」；这里在 ItemCheck 之前把折扣换算还原。
local TERRA_ID          = 757
local TERRA_DAMAGE      = 115        -- 目标伤害
local TERRA_BASE_DAMAGE = 85         -- 原版伤害（缩放基准）
local TERRA_USE_TIME    = 14         -- 目标使用时间（同时用于 useAnimation）
local TERRA_SPEED_DISCOUNT = 0.75    -- 原版近战速度奖励的折扣系数（泰拉刃只吃 75%）

-- ============ 刃杖（物品 4758 / 射弹 864）：取消 33% 标记伤害惩罚 ============
-- 原版 ProjectileID.cs：
--   public static float[] SummonTagDamageMultiplier = Factory.CreateFloatSet(1f, 864f, 0.669f);
-- 全游戏只有 864（刃杖飞刀）是 0.669，其它召唤物全是 1.0。
-- Projectile.cs 的 Damage_PVE_Inner 里：
--   num15 += (int)((num18 + bonusTagDamage) * Sets.SummonTagDamageMultiplier[type]);
-- 即「鞭子 + 词缀给的标记伤害」乘 0.669 后向下取整，才加到这次伤害上。
-- 改成 1.0 后标记加成 100% 到账，且不影响任何其它召唤物，也不碰物品数据。
local BLADE_PROJ_ID  = 864
local BLADE_FIX_MUL  = 1.0     -- 目标系数（原版 0.669）

-- ============ 泰拉刃的近战速度折扣：同样走静态数组 ============
-- 原版 ItemID.cs:1168
--   public static float[] BonusMeleeSpeedMultiplier =
--       Factory.CreateFloatSet(1f, 1827f, 0.5f, 3013f, 0.25f, 3106f, 0.33f, 757f, 0.75f);
-- 原版 Player.cs:26109
--   num29 = meleeSpeed - 1f;  num29 *= Sets.BonusMeleeSpeedMultiplier[手上物品类型];  meleeSpeed = 1f + num29;
-- 把 [757] 改成 1.0，折扣从源头消失，比在 ItemCheck 里按 0.75 反推更稳。
-- 2026-11-01 实机验证：before=0.75 → after=1.0，写入成功。
local TERRA_MELEE_IDX      = 757
local TERRA_SPEED_FIX_MUL  = 1.0     -- 目标系数（原版 0.75）
local terra_speed_fixed    = false   -- 写入成功后，ItemCheck 里就不再换算（否则会双重加速）

-- ============ 利刃台风（物品 2622 / 射弹 409）============
-- 2026-11-01 实机诊断（v4.1.0-诊断版）确认移动版与 PC 1.4.5.8 完全一致：
--   item2622  dmg=85  useTime=40  useAnim=40  shoot=409
--   proj409   timeLeft=300  extraUpdates=2  pen=-1  wh=30x30  ai=71  magic=true
-- 持续时间换算：extraUpdates=2 表示每帧 AI 跑 3 次，实际秒数 = timeLeft / 3 / 60
--   原版 300 → 1.67 秒；3 秒对应 timeLeft = 3 × 3 × 60 = 540
local TYPHOON_ITEM_ID      = 2622
local TYPHOON_PROJ_ID      = 409
local TYPHOON_BASE_DAMAGE  = 85      -- 原版物品伤害（缩放基准）
local TYPHOON_DAMAGE       = 90      -- 目标伤害
local TYPHOON_USE_TIME     = 20      -- 目标使用时间（同时用于 useAnimation）
local TYPHOON_TIMELEFT     = 540     -- 目标射弹 timeLeft（= 3 秒）
local typhoon_proj_logged  = false

-- ============ 圣箭（物品 516 / 箭矢射弹 91 / 神圣之星 92）============
-- 2026-11-01 核实：移动版圣箭伤害与 PC 一致（都是 13），**伤害不需要改**。
-- 只做两项：
--   ① 星星伤害：Projectile.cs:76773-76777 在 Kill() 里
--        int num673 = damage;  if (type == 91) num673 /= 3;   ← 只有圣箭才除以 3
--      在 Kill 之前把圣箭的 damage ×3，整数除法后正好还原成原值（3d/3 = d，精确无误差）
--      Kill() 内 type==91 的分支只在这一处用到 damage（其余分支互斥），无副作用
--   ② 星星穿透：Projectile.cs:1682-1693  type 92 的 SetDefaults 里 penetrate = 1，只能打一个目标
local HOLY_ARROW_PROJ    = 91
local HOLY_STAR_PROJ     = 92
local HOLY_STAR_PEN      = 2        -- 星星穿透 1 → 2（能打第二个目标）
local holy_logged        = {}       -- 每类只记一次日志

-- ============ 句柄 ============
local T_Main, T_Player, T_Proj
local f_proj_type, f_proj_damage, f_proj_timeleft
local f_proj_magic, f_proj_ai, f_proj_alpha
local f_pl_lifesteal, f_pl_magicdmg, f_pl_statlifemax, f_pl_statlife
local f_pl_head, f_pl_body, f_pl_legs, f_pl_dead, f_pl_whoami
local f_pl_whiprange, f_pl_whipuse, f_pl_miniondmg
local f_pl_meleespeed
local f_pl_inventory, f_pl_selecteditem
local m_get_helditem      -- Player.HeldItem 属性 getter（手机上 selectedItem 是只读属性，不是字段）
local m_get_selecteditem
local f_item_usetime, f_item_useanimation
local f_pl_ghostheal   -- 幽灵兜帽套装生效标志（由套装奖励置位）
local f_pl_armor, f_item_type   -- 护甲数组（Item[20]）与物品 type 字段
local f_main_gamemenu, f_main_players, f_myplayer, f_main_proj
local m_get_myplayer, m_newtext
local m_get_gamemenu
local m_newproj        -- Projectile.NewProjectile（静态方法，用于一次发多枚）
local f_proj_penetrate -- 圣箭星星穿透用
local f_proj_maxpen    -- 星星的 maxPenetrate 也要同步（SetDefaults 末行会写 maxPenetrate=penetrate，postfix 改 penetrate 追不上）
local f_proj_pos       -- 水晶子弹补发碎片要读坐标
local f_proj_vel       -- 同上，读速度
local f_proj_owner     -- 同上，碎片要继承主人
local m_proj_kill      -- Projectile.Kill()，圣箭死亡时生成星星
local m_damage_pve     -- Projectile.Damage_PVE(ref Rectangle, float)，邪箭/小丑之箭穿透衰减
local m_proj_src       -- Projectile.GetProjectileSource_FromThis()，补发碎片要 IEntitySource

-- ============ 状态 ============
local ready = false
local echo_done = false
local in_world_frames = 0
local obs_minion_base = nil   -- 黑曜石套：套装奖励施加前的召唤伤害基准
local terra_backup = {}       -- 泰拉刃：ItemCheck 期间临时改动的 useTime/useAnimation 原值（按玩家下标）
-- 回调计数（用于确认钩子是否真的被执行）

-- ============ 工具 ============
local function find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 12 do
        local f = patch.get_field(cur, name)
        if f then return f end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function get_i(f, inst, dft)
    if not f then return dft end
    local ok, v = pcall(patch.get_field_value, f, inst, "int32")
    if ok and v ~= nil then return v end
    return dft
end

local function set_i(f, inst, v)
    if f then pcall(patch.set_field_value, f, inst, v, "int32") end
end

local function get_f(f, inst, dft)
    if not f then return dft end
    local ok, v = pcall(patch.get_field_value, f, inst, "float")
    if ok and v ~= nil then return v end
    return dft
end

local function set_f(f, inst, v)
    if f then pcall(patch.set_field_value, f, inst, v, "float") end
end

local function get_b(f, inst, dft)
    if not f then return dft end
    local ok, v = pcall(patch.get_field_value, f, inst, "bool")
    if ok and v ~= nil then return v end
    return dft
end

local function say(s)
    if not m_newtext then return end
    pcall(function()
        local h = patch.string_create(s)
        patch.invoke(m_newtext, h)
    end)
end

--- 本地玩家下标；Android 上 myPlayer 是属性，字段读不到时回退 getter
local function my_player_index()
    local v = get_i(f_myplayer, nil, nil)
    if v ~= nil and v >= 0 then return v end
    if m_get_myplayer then
        local ok, r = pcall(patch.invoke, m_get_myplayer)
        if ok and type(r) == "number" and r >= 0 then return r end
    end
    return -1
end

--- 取本地玩家对象（用缓存的数组句柄）
local function local_player()
    local idx = my_player_index()
    if idx < 0 or not f_main_players then return nil end
    local ok, arr = pcall(patch.get_field_value, f_main_players, nil, "object")
    if not (ok and arr) then return nil end
    local ok2, pl = pcall(patch.array_at, arr, idx)
    if ok2 then return pl end
    return nil
end
--- 给玩家回血（不超过上限），返回实际增加量
local function heal_player(pl, amount)
    local life = get_i(f_pl_statlife, pl, 0)
    local maxlife = get_i(f_pl_statlifemax, pl, 0)
    if life <= 0 or maxlife <= 0 then return 0 end
    local add = math.floor(amount + 0.5)
    if add < 1 then add = 1 end
    local newlife = life + add
    if newlife > maxlife then newlife = maxlife end
    if newlife <= life then return 0 end
    set_i(f_pl_statlife, pl, newlife)
    return newlife - life
end

-- ============ Hook 2: Projectile.ghostHeal（幽灵兜帽吸血）============
-- 吸血率固定 10%（原版 0.2 - numHits*0.05，第 5 次命中起为 0）
-- lifeSteal 只扣 1%，等效额度上限 ×100，即「无限制」
local function ghost_heal_prefix(inst, args, result)
    if not ready or not inst then return false end
    if not CFG.ghost then return false end   -- 开关关闭：完全交回原版
    local dmg = args and args[1]
    if type(dmg) ~= "number" or dmg <= 1 then return true end
    if not get_b(f_proj_magic, inst, false) then return true end
    local pl = local_player()
    if not pl then return true end
    local ls = get_f(f_pl_lifesteal, pl, 0)
    if ls <= 0 then return true end

    -- 固定 10%，取消原版「命中数越多吸血越少」的递减
    local rate = GHOST_HEAL_RATE

    local amount = dmg * rate
    if amount < 1 then return true end
    local gained = heal_player(pl, amount)
    if gained > 0 then
        -- 原版每帧把 lifeSteal 硬压回 70，补上去无效；改为只扣 1%，等效额度 ×100
        set_f(f_pl_lifesteal, pl, ls - amount * LIFESTEAL_COST_SCALE)
    end
    return true
end

-- ============ Hook 5: Player.Update（额度续航 / 幽灵套装魔伤 / 播报）============
-- gameMenu 在 PE 版可能是属性，字段读不到时走 getter
local function in_game_world(pl)
    if m_get_gamemenu then
        local ok, r = pcall(patch.invoke, m_get_gamemenu)
        if ok and type(r) == "boolean" then return not r end
    end
    if f_main_gamemenu then return not get_b(f_main_gamemenu, nil, true) end
    -- 兜底：活着且有血量上限，说明已经进世界
    return get_i(f_pl_statlife, pl, 0) > 0 and not get_b(f_pl_dead, pl, true)
end

local upd_err_logged = false

-- ============ 套装判定与基准 ============
local md_base = -1        -- 未施加惩罚时的 magicDamage 基准
local hood_miss = 0       -- 连续多少帧判定为「没穿套装」，用于防抖

-- ============ 幽灵兜帽套装判定 ============
-- 注意：player.head / body / legs 是发型和衣服样式，不是护甲。
-- 真正的护甲在 player.armor[0]（头）/ [1]（身）/ [2]（腿）。
-- 1503 = Spectre Hood、1504 = Spectre Robe、1505 = Spectre Pants
local function is_spectre_hood(pl)
    if f_pl_armor and f_item_type then
        local ok, arr = pcall(patch.get_field_value, f_pl_armor, pl, "object")
        if ok and arr then
            local t0, t1, t2 = -1, -1, -1
            local o1, a0 = pcall(patch.array_at, arr, 0)
            if o1 and a0 then t0 = get_i(f_item_type, a0, -1) end
            local o2, a1 = pcall(patch.array_at, arr, 1)
            if o2 and a1 then t1 = get_i(f_item_type, a1, -1) end
            local o3, a2 = pcall(patch.array_at, arr, 2)
            if o3 and a2 then t2 = get_i(f_item_type, a2, -1) end
            if t0 == 1503 and t1 == 1504 and t2 == 1505 then return true end
        end
    end
    if f_pl_ghostheal and get_b(f_pl_ghostheal, pl, false) then return true end
    return false
end

-- ============ 黑曜石套：判定与强化 ============
-- 读 armor[0..2] 的 type，读不到返回 nil
local function armor_ids(pl)
    if not (f_pl_armor and f_item_type) then return nil end
    local ok, arr = pcall(patch.get_field_value, f_pl_armor, pl, "object")
    if not (ok and arr) then return nil end
    local ids = {}
    for slot = 0, 2 do
        local o, it = pcall(patch.array_at, arr, slot)
        if o and it then
            ids[slot] = get_i(f_item_type, it, -1)
        else
            ids[slot] = -1
        end
    end
    return ids
end

local function is_obsidian_set(pl)
    local ids = armor_ids(pl)
    if not ids then return false end
    return ids[0] == OBSIDIAN_ARMOR[0]
       and ids[1] == OBSIDIAN_ARMOR[1]
       and ids[2] == OBSIDIAN_ARMOR[2]
end

-- 必须在「套装奖励施加之后」调用（UpdateArmorSets 尾部 / Update 尾部）。
-- 鞭范围与鞭速度直接顶到目标值：这两个字段除了每帧重置为 1.0 以外没有别的写入点，
-- 唯二的其它来源（蜜蜂头 1159、蜘蛛套 3381-3383）也占头槽，不可能与黑曜石三件同时生效。
-- 召唤伤害走「基准 + 0.25」，基准是套装奖励前的值，这样饰品加成不会被吞掉。
local function apply_obsidian(pl)
    if not is_obsidian_set(pl) then
        obs_minion_base = nil
        return
    end
    if f_pl_whiprange then
        set_f(f_pl_whiprange, pl, 1.0 + OBSIDIAN_WHIP_RANGE)
    end
    if f_pl_whipuse then
        set_f(f_pl_whipuse, pl, 1.0 - OBSIDIAN_WHIP_SPEED)
    end
    if f_pl_miniondmg and obs_minion_base and obs_minion_base > 0 then
        set_f(f_pl_miniondmg, pl, obs_minion_base + OBSIDIAN_MINION_DMG)
    end
end

-- UpdateEquips 结束时（套装奖励还没加）记录召唤伤害基准
local function record_obsidian_base(pl)
    if not f_pl_miniondmg then return end
    if not is_obsidian_set(pl) then
        obs_minion_base = nil
        return
    end
    local m = get_f(f_pl_miniondmg, pl, -1)
    if m > 0 then obs_minion_base = m end
end

-- ============ 泰拉刃（757）：纯动态覆盖 ============
-- 原则：绝不改动 Item 的持久字段（damage / useTime / useAnimation 都会随玩家存档保存），
-- 只在「游戏读取的那一刻」给值——要么直接改返回值，要么临时改完立刻还原。

--- 玩家当前手持的物品
--- 手机上 Player.selectedItem / HeldItem 都是只读属性（没有字段），
--- 所以优先走 HeldItem 属性的 getter，拿不到再退回 inventory + 下标。
local function held_item(pl)
    if m_get_helditem then
        local ok, it = pcall(patch.invoke, m_get_helditem, pl)
        if ok and it then return it end
    end
    if not f_pl_inventory then return nil end
    local idx = -1
    if f_pl_selecteditem then
        idx = get_i(f_pl_selecteditem, pl, -1)
    elseif m_get_selecteditem then
        local ok, v = pcall(patch.invoke, m_get_selecteditem, pl)
        if ok and type(v) == "number" then idx = v end
    end
    if idx < 0 then return nil end
    local ok, arr = pcall(patch.get_field_value, f_pl_inventory, pl, "object")
    if not (ok and arr) then return nil end
    local ok2, it = pcall(patch.array_at, arr, idx)
    if ok2 then return it end
    return nil
end

-- ============ 幻影弓（物品 3540）============
-- PC 1.4.5.8 Item.cs:31729 case 3540：damage = 50 / useTime 12 / shootSpeed 20 / shoot 630
-- 与泰拉刃、利刃台风同一套做法：钩 GetWeaponDamage 按 70/50 缩放返回値，
-- 词缀加成天然保留，不写任何物品数据。
-- 注意：弓的最终伤害 = GetWeaponDamage(弓) + 弹药伤害（PickAmmo 里相加），
-- 这里只放大「弓」的那一部分，弹药贡献不变，正是「弓的伤害 50→70」的本意。
local PHANTASM_ID          = 3540
local PHANTASM_DAMAGE      = 70      -- 目标伤害
local PHANTASM_BASE_DAMAGE = 50      -- 原版伤害（缩放基准）
local phantasm_logged      = false

-- ============ 邪箭 / 小丑之箭：取消穿透后的伤害递减 ============
-- PC 1.4.5.8 Projectile.cs:13560-13565，位置在 Damage_PVE_Inner 的 switch (type) 里：
--     case 5:  damage = (int)((double)damage * 0.9);    ← 小丑之箭，穿透后 -10%
--     case 4:  damage = (int)((double)damage * 0.95);   ← 邪箭，穿透后 -5%
-- 这段是在「本次命中结算完之后」给下一次命中留的衰减值。
--
-- 做法：钩 Projectile.Damage_PVE(ref Rectangle, float) 的 prefix + postfix。
--   prefix  —— 记下本次命中结算前的 damage（模块级标量，用完即清）
--   postfix —— 把被衰减过的 damage 还原成刚记下的那个值
-- 这样一次命中多个目标也能精确还原（d0 是整次调用的起点），
-- 且不需要按槽位存状态，没有 whoAmI 复用和内存残留的问题。
local ARROW_UNHOLY = 4
local ARROW_JESTER = 5
local pve_d0       = nil      -- 本次 Damage_PVE 调用前的伤害
local arrow_logged = {}

-- ============ 水晶子弹：碎片 2 → 3 ============
-- PC 1.4.5.8 Projectile.cs:76802-76810，在 Kill() 的 else if (type == 89) 分支里：
--     if (type == 89 && owner == Main.myPlayer)
--         for (int num677 = 0; num677 < 2; num677++)      ← 固定 2 个
--             NewProjectile(..., 90, (int)((double)damage * 0.5), 0f, owner);
-- 做法：在 Kill 的 prefix 里先自己补发 1 个碎片（90），原版随后照发 2 个 → 共 3 个。
-- 为什么放 prefix 不放 postfix：prefix 时射弹对象一定有效，能读 position / velocity / damage / owner；
-- postfix 时对象可能已被回收，读字段会拿到垃圾值。
-- 调的是 13 参重载（PC 只有 11 参与 13 参两个版本，原版这句走的就是 13 参）：
--   (spawnSource, X, Y, SpeedX, SpeedY, Type, Damage, KnockBack, Owner, ai0, ai1, ai2, modifer)
local CRYSTAL_BULLET_PROJ = 89
local CRYSTAL_SHARD_PROJ  = 90
local crystal_logged      = false
local crystal_reenter     = false

-- ============ 叶绿弹：伤害 9 → 15 ============
-- 叶绿弹是「弹药」，物品 1179 / 射弹 207，Item.cs:14482 里 damage = 9。
-- 弹药伤害在 PickAmmo 里是「加到武器伤害上」的（Player.cs:54196 Damage += ammo.damage × 倍率），
-- 所以这里不能在 SetDefaults 里改模板（背包里的存量弹药不会重新 SetDefaults），
-- 也不能在 NewProjectile 的 prefix 里改 args（args 是值拷贝，改了不生效）。
-- 做法：钩 NewProjectile 的 postfix，拿到返回的射弹下标，直接改 Main.projectile[i].damage += 6。
-- 这样「弹药贡献」正好从 9 变成 15，武器本身的伤害一点不动。
local CHLORO_PROJ   = 207
local CHLORO_ADD    = 6        -- 15 - 9
local chloro_logged = false

-- ① 伤害：钩 GetWeaponDamage 的返回值
-- 原版 = (int)(item.damage × meleeDamage)，item.damage 里已经含了词缀加成，
-- 所以乘一个固定比例 115/85，等于「词缀也按 115 这个新基准重算」，且一点数据都不动。
local function weapon_damage_postfix(inst, args, result)
    if not ready then return nil end
    local it = args and args[1]
    if not it then return nil end
    if type(result) ~= "number" or result <= 0 then return nil end
    local t = get_i(f_item_type, it, -1)
    if CFG.terra and t == TERRA_ID then
        return math.floor(result * TERRA_DAMAGE / TERRA_BASE_DAMAGE + 0.5)
    elseif CFG.typhoon and t == TYPHOON_ITEM_ID then
        -- 利刃台风 85 → 90：同样按比例缩放，词缀加成天然保留
        return math.floor(result * TYPHOON_DAMAGE / TYPHOON_BASE_DAMAGE + 0.5)
    elseif CFG.phantasm and t == PHANTASM_ID then
        -- 幻影弓 50 → 70
        local nv = math.floor(result * PHANTASM_DAMAGE / PHANTASM_BASE_DAMAGE + 0.5)
        if not phantasm_logged then
            phantasm_logged = true
            logf(string.format("[phantasm] GetWeaponDamage %s → %s", tostring(result), tostring(nv)))
        end
        return nv
    end
    return nil
end

-- ② 使用时间：ItemCheck 之前临时把 useTime/useAnimation 改成 14，
-- 游戏按 14 算完挥动节奏后立刻还原，存档里永远是原版的 18。
local function itemcheck_prefix(inst)
    if not ready or not inst then return false end
    local it = held_item(inst)
    if not it then return false end
    local itype = get_i(f_item_type, it, -1)

    -- 利刃台风：使用时间 40 → 20（同样是临时改、用完还原，不写物品数据）
    if CFG.typhoon and itype == TYPHOON_ITEM_ID then
        local idx = get_i(f_pl_whoami, inst, -1)
        if idx < 0 then return false end
        local ut2 = get_i(f_item_usetime, it, -1)
        local ua2 = get_i(f_item_useanimation, it, -1)
        if ut2 < 0 or ua2 < 0 then return false end
        if ut2 ~= TYPHOON_USE_TIME then
            terra_backup[idx] = { useTime = ut2, useAnimation = ua2 }
        end
        if terra_backup[idx] then
            set_i(f_item_usetime, it, TYPHOON_USE_TIME)
            set_i(f_item_useanimation, it, TYPHOON_USE_TIME)
        end
        return false
    end

    if not CFG.terra or itype ~= TERRA_ID then return false end
    local idx = get_i(f_pl_whoami, inst, -1)
    if idx < 0 then return false end
    local ut = get_i(f_item_usetime, it, -1)
    local ua = get_i(f_item_useanimation, it, -1)
    if ut < 0 or ua < 0 then return false end
    -- 只有读到「不是 14」的原值才刷新备份：
    -- 万一某一帧没还原成功、物品停在 14，这里也不会把 14 当成原值记下来
    if ut ~= TERRA_USE_TIME then
        terra_backup[idx] = { useTime = ut, useAnimation = ua }
    end
    if not terra_backup[idx] then return false end
    -- ③ 近战速度奖励折扣
    --    首选「源头改数组」：ItemID.Sets.BonusMeleeSpeedMultiplier[757] 改成 1.0 后，
    --    Player.Update 算出来的 meleeSpeed 本来就不打折，这里什么都不用做（再做会双重加速）。
    --    只有数组写不进去时，才退回老办法：按 1/(1+(1/ms-1)/0.75) 反推回全额攻速。
    --    必须在挥动动画计算之前做，挂在 Update 尾部是无效的。
    if f_pl_meleespeed and not terra_speed_fixed then
        local ms = get_f(f_pl_meleespeed, inst, -1)
        if ms > 0 and ms < 1 then
            local raw = 1 + (1 / ms - 1) / TERRA_SPEED_DISCOUNT
            if raw > 0 then set_f(f_pl_meleespeed, inst, 1 / raw) end
        end
    end
    set_i(f_item_usetime, it, TERRA_USE_TIME)
    set_i(f_item_useanimation, it, TERRA_USE_TIME)
    return false
end

--- 还原某位玩家手持物品的使用时间（正常结束与异常中断都走这里）
local function terra_restore(pl)
    if not pl then return end
    local idx = get_i(f_pl_whoami, pl, -1)
    if idx < 0 then return end
    local b = terra_backup[idx]
    if not b then return end
    terra_backup[idx] = nil
    local it = held_item(pl)
    if not it then return end
    if b.useTime and b.useTime > 0 then set_i(f_item_usetime, it, b.useTime) end
    if b.useAnimation and b.useAnimation > 0 then set_i(f_item_useanimation, it, b.useAnimation) end
end

local function itemcheck_postfix(inst)
    if not inst then return end
    pcall(terra_restore, inst)
end

-- ============ 刃杖：把 SummonTagDamageMultiplier[864] 写成 1.0 ============
-- 2026-11-01 实机诊断结论：
--   静态数组在手机上完全可达，get_inner_type → get_field → get_field_value → array_at 一路成功，
--   读到的原值就是 0.6690000295639，写完回读 1.0，10 秒后仍然是 1.0（没有被游戏重置）。
-- 两个坑：
--   ① setup 阶段数组还没实例化（get_field_value 返回 nil），必须等进世界后再写；
--   ② array_set 必须带类型参数 "float"，不带类型会把值写成 0（会踩成「标记伤害归零」）。
local blade_fixed = false
local blade_retry = 0

local function fix_blade_multiplier()
    if not CFG.blade then blade_fixed = true return end   -- 开关关闭：标记完成，不再重试
    if blade_fixed then return end
    local okT, T_PID = pcall(patch.get_type, "Terraria.ID", "ProjectileID")
    if not (okT and T_PID) then return end
    local okI, sets = pcall(patch.get_inner_type, T_PID, "Sets")
    if not (okI and sets) then return end
    local okF, f = pcall(patch.get_field, sets, "SummonTagDamageMultiplier")
    if not (okF and f) then return end
    local okA, arr = pcall(patch.get_field_value, f, nil, "object")
    if not (okA and arr) then return end

    local okR, cur = pcall(patch.array_at, arr, BLADE_PROJ_ID, "float")
    local c = okR and tonumber(cur) or nil
    if c and c >= BLADE_FIX_MUL - 0.01 then
        blade_fixed = true
        return
    end

    pcall(patch.array_set, arr, BLADE_PROJ_ID, BLADE_FIX_MUL, "float")
    local okV, v = pcall(patch.array_at, arr, BLADE_PROJ_ID, "float")
    local nv = okV and tonumber(v) or nil
    if nv and nv >= BLADE_FIX_MUL - 0.01 then
        blade_fixed = true
    elseif c then
        -- 写不进去就还原原值，保证不会比原版更差
        pcall(patch.array_set, arr, BLADE_PROJ_ID, c, "float")
    end
end

-- ============ 泰拉刃：把 BonusMeleeSpeedMultiplier[757] 写成 1.0 ============
-- 与刃杖同一套机制（同为 float[] 静态数组），只是换了个类型和下标。
local function fix_terra_speed()
    if not CFG.terra then terra_speed_fixed = true return end   -- 开关关闭：标记完成，不再重试
    if terra_speed_fixed then return end
    local okT, T_IID = pcall(patch.get_type, "Terraria.ID", "ItemID")
    if not (okT and T_IID) then return end
    local okI, sets = pcall(patch.get_inner_type, T_IID, "Sets")
    if not (okI and sets) then return end
    local okF, f = pcall(patch.get_field, sets, "BonusMeleeSpeedMultiplier")
    if not (okF and f) then return end
    local okA, arr = pcall(patch.get_field_value, f, nil, "object")
    if not (okA and arr) then return end

    local okR, cur = pcall(patch.array_at, arr, TERRA_MELEE_IDX, "float")
    local c = okR and tonumber(cur) or nil
    if c and c >= TERRA_SPEED_FIX_MUL - 0.01 then
        terra_speed_fixed = true
        return
    end

    pcall(patch.array_set, arr, TERRA_MELEE_IDX, TERRA_SPEED_FIX_MUL, "float")
    local okV, v = pcall(patch.array_at, arr, TERRA_MELEE_IDX, "float")
    local nv = okV and tonumber(v) or nil
    if nv and nv >= TERRA_SPEED_FIX_MUL - 0.01 then
        terra_speed_fixed = true
    elseif c then
        -- 写不进去就还原原值，ItemCheck 里的老换算继续兜底
        pcall(patch.array_set, arr, TERRA_MELEE_IDX, c, "float")
    end
end

-- 发现 magicDamage 低于基准就恢复。基准由 UpdateEquips 结束时记录。
local function restore_md(pl, tag)
    if not is_spectre_hood(pl) then return end
    local md = get_f(f_pl_magicdmg, pl, -1)
    if md < 0 then return end
    -- 目标值 = 基准 - 惩罚 × 保留比例
    local target = md_base - GHOST_MAGIC_FIX * GHOST_PENALTY_KEEP
    if md_base > 0 and md < target - 0.02 then
        set_f(f_pl_magicdmg, pl, target)
    end
end

-- 主体逻辑放在 do_update 里，外面用 pcall 包一层：
-- 任何一行出错都不会让整个回调静默失效，且会在日志里留下一条 [ERR]
local function do_update(pl)

    -- ① lifeSteal：原版每帧硬压回 70/80，这里补值无效（已改为在吸血时只扣 1%），
    --    只读取用于日志观察
    local ls = get_f(f_pl_lifesteal, pl, -1)

    -- ② 幽灵兜帽套装：补回 40% 魔法伤害
    --    优先用 player.ghostHeal（套装奖励置位的标志），拿不到再退回装备 ID：
    --    1503 = Spectre Hood（兜帽）、1504 = Spectre Robe（长袍）、1505 = Spectre Pants（护腿）
    local spectre_hood = is_spectre_hood(pl)
    if spectre_hood then
        hood_miss = 0
        if CFG.ghost then restore_md(pl, "Update") end
    else
        -- 单帧判定失败可能只是数组读取抖动，连续 30 帧才算真的没穿
        hood_miss = hood_miss + 1
        if hood_miss > 30 then md_base = -1 end
    end


    -- ③ 黑曜石套：鞭范围 / 鞭速度 / 召唤伤害（Update 末尾再兜一次，保证同帧生效）
    if CFG.obsidian then apply_obsidian(pl) end

    -- ④ 泰拉刃：万一某帧 ItemCheck 中途异常没走到还原，这里兜住，避免 14 被带进存档
    if next(terra_backup) ~= nil then
        pcall(terra_restore, pl)
    end

    -- ⑤ 进图 1 秒后播报
    if not echo_done then
        if in_game_world(pl) then
            in_world_frames = in_world_frames + 1
            if in_world_frames >= ECHO_DELAY_FRAMES then
                echo_done = true
                say("[c/FF3333:力量又回来了(◣_◢)]")
                logf("[echo] done at frame " .. in_world_frames)
            end
        else
            in_world_frames = 0
        end
    end

    -- ⑥ 静态数组修正：刃杖标记乘数 + 泰拉刃攻速折扣
    --    数组要等进世界后才实例化，所以这里每 2 秒试一次，两项都成功就不再进这个分支
    if not blade_fixed or not terra_speed_fixed then
        blade_retry = blade_retry + 1
        if blade_retry >= 120 then
            blade_retry = 0
            if CFG.blade then pcall(fix_blade_multiplier) end
            if CFG.terra then pcall(fix_terra_speed) end
        end
    end

end


-- ============ Hook: Player.UpdateEquips（魔伤补偿的正确时机）============
-- 调用顺序：ResetEffects(md=1.0) -> UpdateEquips(幽灵套 md-=0.4) -> ItemCheck(伤害结算)
-- 所以必须在 UpdateEquips 之后、ItemCheck 之前补，挂在 Update 末尾是白补。
local function equips_postfix(inst, args, result)
    if not ready or not inst then return end
    local pl = inst
    record_obsidian_base(pl)
    if not is_spectre_hood(pl) then return end
    -- UpdateEquips 结束时 magicDamage 还是「未惩罚」状态，记下来作为基准
    local md = get_f(f_pl_magicdmg, pl, -1)
    if md >= 0 then
        -- 只增不减：避免某一帧读到已被惩罚的值把基准拉低
        if md > md_base then md_base = md end
    end
end

-- ============ Hook: Player.UpdateArmorSets（套装奖励生效点，最可能在这里扣 0.4）============
local function armorsets_postfix(inst, args, result)
    if not ready or not inst then return end
    if CFG.ghost then pcall(restore_md, inst, "UpdateArmorSets") end
    if CFG.obsidian then pcall(apply_obsidian, inst) end
end

local function update_postfix(inst, args, result)
    if not ready or not inst then return end
    local ok, err = pcall(do_update, inst)
    if not ok and not upd_err_logged then
        upd_err_logged = true
        logf("[ERR] update_postfix: " .. tostring(err))
        mod.error("[巅峰] " .. tostring(err))
    end
end

-- ============ 射弹 SetDefaults：利刃台风持续时间 + 神圣之星穿透 ============
-- 走 Projectile.SetDefaults(int Type) 的 postfix：此时 SetDefaults 刚跑完，
-- 而 NewProjectile 后续只设 position/owner/velocity/damage，不再碰 timeLeft / penetrate，写完不会被覆盖。
local function proj_setdefaults_postfix(inst, args, result)
    if not ready or not inst then return end
    local ok, err = pcall(function()
        local t = get_i(f_proj_type, inst, -1)

        if CFG.typhoon and t == TYPHOON_PROJ_ID then
            set_i(f_proj_timeleft, inst, TYPHOON_TIMELEFT)
            if not typhoon_proj_logged then
                typhoon_proj_logged = true
                logf("[typhoon] timeLeft → " .. tostring(get_i(f_proj_timeleft, inst, -1)))
            end
            return
        end

        -- 神圣之星：penetrate 1 → 2，命中第一个目标后不消失，能打到第二个
        -- 注意：SetDefaults 的最后一行是 maxPenetrate = penetrate，所以 maxPenetrate 现在还是 1，
        -- 两个字段必须一起改，否则 maxPenetrate != penetrate 会让免疫/音效判定走偏。
        if CFG.holy and t == HOLY_STAR_PROJ then
            local old = get_i(f_proj_penetrate, inst, -1)
            local oldMax = get_i(f_proj_maxpen, inst, -1)
            set_i(f_proj_penetrate, inst, HOLY_STAR_PEN)
            set_i(f_proj_maxpen, inst, HOLY_STAR_PEN)
            if not holy_logged.pen then
                holy_logged.pen = true
                logf(string.format("[holy] star penetrate %s→%s  maxPenetrate %s→%s",
                    tostring(old), tostring(get_i(f_proj_penetrate, inst, -1)),
                    tostring(oldMax), tostring(get_i(f_proj_maxpen, inst, -1))))
            end
        end
    end)
    if not ok then logf("[typhoon] setdefaults err " .. tostring(err)) end
end

-- ============ 利刃台风：一次发 2 枚 ============
-- LuaLoader 没有生成射弹的接口，只能钩 Projectile.NewProjectile（float 版，13 个参数）：
--   args = { spawnSource, X, Y, SpeedX, SpeedY, Type, Damage, KnockBack, Owner, ai0, ai1, ai2, modifer }
-- 在 prefix 里用 patch.invoke 再调一次同一方法（速度偏转约 12°），然后放行原调用。
-- 安全设计：第一次遇到 409 只「上膛」不发射，第二次起才真正多发；
-- 重入守卫 np_reenter 必须在最前面，否则内层调用会无限递归。
local np_reenter = false
local np_armed   = false     -- 首次遇到 409 只上膛，第二次起才多发

local function newproj_prefix(inst, args, result)
    if np_reenter then return false end
    if not args or not m_newproj then return false end
    if not CFG.typhoon or args[6] ~= TYPHOON_PROJ_ID then return false end

    if not np_armed then
        np_armed = true
        return false
    end

    local sx, sy = args[4], args[5]
    if type(sx) ~= "number" or type(sy) ~= "number" then return false end
    local ang = 0.21                       -- 约 12°
    local cs, sn = math.cos(ang), math.sin(ang)
    local nsx, nsy = sx * cs - sy * sn, sx * sn + sy * cs

    np_reenter = true
    pcall(patch.invoke, m_newproj,
        args[1], args[2], args[3], nsx, nsy,
        args[6], args[7], args[8], args[9],
        args[10], args[11], args[12], args[13])
    np_reenter = false
    return false                           -- 放行原调用，原方法自己发第一枚
end

-- ============ 叶绿弹：伤害 9 → 15 ============
-- NewProjectile 的 args 是值拷贝，prefix 里改 args[7] 不会影响原方法；
-- 只能等它返回射弹下标后，从 Main.projectile[idx] 上直接改字段。
-- 注意：内核不允许同一方法装两个钩子，所以这个 postfix 必须和利刃台风的 prefix
-- 挂在同一个 hook(m_newproj, {...}) 调用里。
local function newproj_postfix(inst, args, result)
    if not ready or not f_main_proj or not f_proj_damage then return end
    if not CFG.chloro or not args or args[6] ~= CHLORO_PROJ then return end
    if type(result) ~= "number" or result < 0 then return end
    pcall(function()
        local arr = patch.get_field_value(f_main_proj, nil, "object")
        if not arr then return end
        local p = patch.array_at(arr, result)
        if not p or not patch.is_valid(p) then return end
        local d = get_i(f_proj_damage, p, -1)
        if d and d > 0 then
            set_i(f_proj_damage, p, d + CHLORO_ADD)
            if not chloro_logged then
                chloro_logged = true
                logf(string.format("[chloro] proj idx=%s damage %s → %s",
                    tostring(result), tostring(d), tostring(d + CHLORO_ADD)))
            end
        end
    end)
end

-- ============ 水晶子弹：补发第 3 个碎片 ============
-- 原版 Kill 里固定发 2 个碎片（type 90），这里在 Kill 之前先补 1 个 → 共 3 个。
-- 速度算法照抄原版：vec = -velocity * rand(40,70)*0.01 + rand(-20,21)*0.4
-- C# 的 Random.Next(min,max) 左闭右开，所以是 40~69、-20~20。
local function crystal_extra_shard(inst)
    if crystal_reenter then return end
    if not (m_newproj and m_proj_src and f_proj_pos and f_proj_vel and f_proj_owner) then return end
    crystal_reenter = true
    local ok, err = pcall(function()
        local px, py = patch.get_field_vec2(f_proj_pos, inst)
        local vx, vy = patch.get_field_vec2(f_proj_vel, inst)
        if type(px) ~= "number" or type(py) ~= "number"
            or type(vx) ~= "number" or type(vy) ~= "number" then
            logf("[crystal] vec2 read failed")
            return
        end
        local d = get_i(f_proj_damage, inst, -1)
        if d <= 0 then
            logf("[crystal] damage invalid " .. tostring(d))
            return
        end
        local ow = get_i(f_proj_owner, inst, -1)
        local src = patch.invoke(m_proj_src, inst)
        if not src then
            logf("[crystal] source is nil")
            return
        end
        local nx = -vx * (math.random(40, 69) * 0.01) + math.random(-20, 20) * 0.4
        local ny = -vy * (math.random(40, 69) * 0.01) + math.random(-20, 20) * 0.4
        local dmg = math.floor(d * 0.5)     -- 原版 (int)((double)damage * 0.5)
        local ret = patch.invoke(m_newproj, src, px + nx, py + ny, nx, ny,
            CRYSTAL_SHARD_PROJ, dmg, 0, ow, 0, 0, 0, nil)
        if not crystal_logged then
            crystal_logged = true
            logf(string.format("[crystal] extra shard ret=%s pos=%.1f,%.1f vel=%.2f,%.2f dmg=%s owner=%s",
                tostring(ret), px, py, nx, ny, tostring(dmg), tostring(ow)))
        end
    end)
    crystal_reenter = false
    if not ok then logf("[crystal] err " .. tostring(err)) end
end

-- ============ 圣箭：把「星星伤害 ÷3」还原成 100% ============
-- Projectile.Kill() 里 type==91 的分支只有这一处用到 damage：
--     int num673 = damage;  if (type == 91) { num673 /= 3; }
--     NewProjectile(..., 92, num673, ...)
-- 在 Kill 之前把圣箭的 damage ×3，整数除法后 num673 = 3d/3 = d，精确还原（无浮点误差）。
-- 该分支与其它 type 分支互斥，不会影响别的弹幕；弹幕随后即被回收，不需要还原。
local function proj_kill_prefix(inst, args, result)
    if not ready or not inst then return false end
    local ok = pcall(function()
        local t = get_i(f_proj_type, inst, -1)
        if CFG.holy and t == HOLY_ARROW_PROJ then
            local d = get_i(f_proj_damage, inst, -1)
            if d <= 0 then return end
            set_i(f_proj_damage, inst, d * 3)
            if not holy_logged.kill then
                holy_logged.kill = true
                logf("[holy] kill: arrow damage " .. tostring(d) .. " → " .. tostring(d * 3))
            end
        elseif CFG.crystal and t == CRYSTAL_BULLET_PROJ then
            crystal_extra_shard(inst)
        end
    end)
    if not ok then return false end
    return false        -- 永远放行原方法
end

-- ============ 邪箭 / 小丑之箭：穿透后不衰减 ============
local function pve_prefix(inst, args, result)
    pve_d0 = nil
    if not ready or not inst then return false end
    local ok = pcall(function()
        local t = get_i(f_proj_type, inst, -1)
        local want = (CFG.unholy and t == ARROW_UNHOLY) or (CFG.jester and t == ARROW_JESTER)
        if not want then return end
        local d = get_i(f_proj_damage, inst, -1)
        if d and d > 0 then pve_d0 = d end
    end)
    if not ok then pve_d0 = nil end
    return false        -- 永远放行原方法
end

local function pve_postfix(inst, args, result)
    if not pve_d0 then return end
    local d0 = pve_d0
    pve_d0 = nil        -- 用完即清，避免残留影响下一次
    if not ready or not inst then return end
    pcall(function()
        local d = get_i(f_proj_damage, inst, -1)
        if d and d > 0 and d ~= d0 then
            set_i(f_proj_damage, inst, d0)
            if not arrow_logged.pen then
                arrow_logged.pen = true
                logf(string.format("[arrow] pen-damage %s → restored %s", tostring(d), tostring(d0)))
            end
        end
    end)
end

-- ============ 钩子安装 ============
local function hook(method, spec, label)
    if not method then
        logf("[hook] MISSING " .. label)
        mod.error("[巅峰] 缺少方法：" .. label)
        return false
    end
    local ok, err = pcall(patch.install_hook, method, spec)
    if not ok then
        logf("[hook] FAIL " .. label .. " : " .. tostring(err))
        mod.error("[巅峰] 挂钩失败 " .. label .. "：" .. tostring(err))
        return false
    end
    logf("[hook] OK " .. label)
    return true
end

function setup()
    logf("=== setup " .. os.date("%H:%M:%S") .. " ===")
    logf("platform=" .. tostring(mod.platform))
    -- 先读模组设置（config.json），后面的所有钩子回调都按 CFG 判断是否生效
    pcall(load_config)
    T_Main   = patch.get_type("Terraria", "Main")
    T_Player = patch.get_type("Terraria", "Player")
    T_Proj   = patch.get_type("Terraria", "Projectile")
    logf(string.format("types: Main=%s Player=%s Proj=%s",
        tostring(T_Main), tostring(T_Player), tostring(T_Proj)))
    if not (T_Main and T_Player and T_Proj) then
        mod.error("[巅峰] 类型获取失败")
        return
    end

    f_proj_type     = find_field(T_Proj, "type")
    f_proj_damage   = find_field(T_Proj, "damage")
    f_proj_timeleft = find_field(T_Proj, "timeLeft")
    f_proj_magic    = find_field(T_Proj, "magic")
    f_proj_ai       = find_field(T_Proj, "ai")
    f_proj_alpha    = find_field(T_Proj, "alpha")
    f_proj_penetrate = find_field(T_Proj, "penetrate")
    f_proj_maxpen    = find_field(T_Proj, "maxPenetrate")
    f_proj_pos       = find_field(T_Proj, "position")      -- 继承自 Entity
    f_proj_vel       = find_field(T_Proj, "velocity")      -- 继承自 Entity
    f_proj_owner     = find_field(T_Proj, "owner")

    f_pl_lifesteal   = find_field(T_Player, "lifeSteal")
    f_pl_magicdmg    = find_field(T_Player, "magicDamage")
    f_pl_statlifemax = find_field(T_Player, "statLifeMax2")
    f_pl_statlife    = find_field(T_Player, "statLife")
    f_pl_head        = find_field(T_Player, "head")
    f_pl_body        = find_field(T_Player, "body")
    f_pl_legs        = find_field(T_Player, "legs")
    f_pl_dead        = find_field(T_Player, "dead")
    f_pl_whoami      = find_field(T_Player, "whoAmI")
    f_pl_ghostheal   = find_field(T_Player, "ghostHeal")
    f_pl_armor       = find_field(T_Player, "armor")
    f_pl_whiprange   = find_field(T_Player, "whipRangeMultiplier")
    f_pl_meleespeed  = find_field(T_Player, "meleeSpeed")
    f_pl_whipuse     = find_field(T_Player, "whipUseTimeMultiplier")
    f_pl_miniondmg   = find_field(T_Player, "minionDamage")
    do
        local T_Item = patch.get_type("Terraria", "Item")
        if T_Item then
            f_item_type = find_field(T_Item, "type")
            f_item_usetime = find_field(T_Item, "useTime")
            f_item_useanimation = find_field(T_Item, "useAnimation")
        end
    end
    f_pl_inventory    = find_field(T_Player, "inventory")
    f_pl_selecteditem = find_field(T_Player, "selectedItem")   -- 手机上为 nil（只读属性，不是字段）
    pcall(function()
        local ph = patch.get_property(T_Player, "HeldItem")
        if ph then m_get_helditem = patch.property_get_method(ph) end
        local ps = patch.get_property(T_Player, "selectedItem")
        if ps then m_get_selecteditem = patch.property_get_method(ps) end
    end)

    f_main_gamemenu = find_field(T_Main, "gameMenu")
    f_main_players  = find_field(T_Main, "player")
    f_main_proj     = find_field(T_Main, "projectile")   -- Projectile[]，叶绿弹改伤害用
    f_myplayer      = find_field(T_Main, "myPlayer")
    if not f_myplayer then
        m_get_myplayer = patch.get_method(T_Main, "get_myPlayer", 0)
            or patch.get_method(T_Main, "get_myPlayer")
    end
    m_newtext = patch.get_method(T_Main, "NewText", 3) or patch.get_method(T_Main, "NewText", 5)

    -- 利刃台风多发用：NewProjectile 的 float 版是 13 参（Vector2 版是 11 参，内部会转调 float 版）
    m_newproj = patch.get_method(T_Proj, "NewProjectile", 13)
             or patch.get_method(T_Proj, "NewProjectile", 11)
    logf("[typhoon] NewProjectile = " .. tostring(m_newproj))

    -- 圣箭用：Projectile.Kill() 无参
    m_proj_kill = patch.get_method(T_Proj, "Kill", 0) or patch.get_method(T_Proj, "Kill")
    logf("[holy] Projectile.Kill = " .. tostring(m_proj_kill))

    -- 邪箭/小丑之箭用：Damage_PVE(ref Rectangle, float) —— 2 参（PE 源码核实）
    m_damage_pve = patch.get_method(T_Proj, "Damage_PVE", 2) or patch.get_method(T_Proj, "Damage_PVE")
    logf("[arrow] Projectile.Damage_PVE = " .. tostring(m_damage_pve))

    -- 水晶子弹补发碎片用：GetProjectileSource_FromThis() —— 0 参，返回 IEntitySource
    m_proj_src = patch.get_method(T_Proj, "GetProjectileSource_FromThis", 0)
              or patch.get_method(T_Proj, "GetProjectileSource_FromThis")
    logf("[crystal] GetProjectileSource_FromThis = " .. tostring(m_proj_src))

    -- gameMenu 在 PE 版是属性，补上 getter
    pcall(function()
        local pg = patch.get_property(T_Main, "gameMenu")
        if pg then m_get_gamemenu = patch.property_get_method(pg) end
    end)
    logf("getters: gamemenu=" .. tostring(m_get_gamemenu))

    logf(string.format("proj: type=%s dmg=%s tleft=%s magic=%s",
        tostring(f_proj_type), tostring(f_proj_damage), tostring(f_proj_timeleft),
        tostring(f_proj_magic)))
    logf(string.format("player: ls=%s md=%s life=%s max=%s head=%s who=%s",
        tostring(f_pl_lifesteal), tostring(f_pl_magicdmg), tostring(f_pl_statlife),
        tostring(f_pl_statlifemax), tostring(f_pl_head), tostring(f_pl_whoami)))
    logf(string.format("main: menu=%s players=%s myplayer=%s getmy=%s newtext=%s",
        tostring(f_main_gamemenu), tostring(f_main_players),
        tostring(f_myplayer), tostring(m_get_myplayer), tostring(m_newtext)))

    if not (f_proj_type and f_proj_damage and f_proj_timeleft) then
        mod.error("[巅峰] Projectile 关键字段缺失")
        return
    end
    local ok_all = true

    ok_all = hook(patch.get_method(T_Proj, "ghostHeal", 3),
        { prefix = ghost_heal_prefix }, "Projectile.ghostHeal") and ok_all

    ok_all = hook(
        patch.get_method(T_Player, "UpdateEquips", 1) or patch.get_method(T_Player, "UpdateEquips"),
        { postfix = equips_postfix }, "Player.UpdateEquips") and ok_all

    ok_all = hook(
        patch.get_method(T_Player, "UpdateArmorSets", 1) or patch.get_method(T_Player, "UpdateArmorSets"),
        { postfix = armorsets_postfix }, "Player.UpdateArmorSets") and ok_all

    ok_all = hook(
        patch.get_method(T_Player, "Update", 1) or patch.get_method(T_Player, "Update"),
        { postfix = update_postfix }, "Player.Update") and ok_all

    -- 利刃台风：持续时间（SetDefaults postfix）+ 多发（NewProjectile prefix）
    -- 这两个单独装，不并入 ok_all：万一装不上只能说明这一项不能用，不能拖垮已有 7 项功能
    local typhoon_a = hook(
        patch.get_method(T_Proj, "SetDefaults", 1) or patch.get_method(T_Proj, "SetDefaults"),
        { postfix = proj_setdefaults_postfix }, "Projectile.SetDefaults")
    local typhoon_b = hook(m_newproj,
        { prefix = newproj_prefix, postfix = newproj_postfix }, "Projectile.NewProjectile")
    -- 圣箭：星星伤害还原（Kill 之前把圣箭 damage ×3）
    local holy_k = hook(m_proj_kill,
        { prefix = proj_kill_prefix }, "Projectile.Kill")
    -- 邪箭 / 小丑之箭：穿透后伤害不递减
    local arrow_h = hook(m_damage_pve,
        { prefix = pve_prefix, postfix = pve_postfix }, "Projectile.Damage_PVE")
    logf(string.format("[typhoon] hooks: setdefaults=%s newproj=%s | [holy] kill=%s | [arrow] pve=%s",
        tostring(typhoon_a), tostring(typhoon_b), tostring(holy_k), tostring(arrow_h)))

    -- 泰拉刃：伤害（改返回值）+ 使用时间（临时改完还原）
    -- 两者分开判断：伤害钩子只要认得 Item.type 就能装，不依赖能不能取到手持物品
    local can_hold = (m_get_helditem ~= nil)
        or (f_pl_inventory ~= nil and (f_pl_selecteditem ~= nil or m_get_selecteditem ~= nil))

    if f_item_type then
        ok_all = hook(
            patch.get_method(T_Player, "GetWeaponDamage", 1),
            { postfix = weapon_damage_postfix, override_result = true },
            "Player.GetWeaponDamage") and ok_all
    else
        mod.error("[巅峰] 缺少 Item.type，泰拉刃伤害未启用")
    end

    if f_item_usetime and f_item_useanimation and can_hold then
        ok_all = hook(
            patch.get_method(T_Player, "ItemCheck", 0) or patch.get_method(T_Player, "ItemCheck"),
            { prefix = itemcheck_prefix, postfix = itemcheck_postfix },
            "Player.ItemCheck") and ok_all
    else
        mod.error("[巅峰] 取不到手持物品或 Item 时间字段，泰拉刃攻速未启用")
    end

    -- 自检：只在有缺失时输出一条，正常不刷屏
    do
        local miss = {}
        if not f_item_type then miss[#miss + 1] = "Item.type" end
        if not f_item_usetime then miss[#miss + 1] = "Item.useTime" end
        if not f_item_useanimation then miss[#miss + 1] = "Item.useAnimation" end
        if not m_get_helditem then miss[#miss + 1] = "HeldItem.get" end
        if not f_pl_inventory then miss[#miss + 1] = "Player.inventory" end
        if #miss > 0 then
            mod.error("[巅峰] 泰拉刃字段缺失：" .. table.concat(miss, ","))
        end
    end

    ready = ok_all
    logf("ready=" .. tostring(ready))
    if ready then
        mod.info("[巅峰] 已启用")
    else
        mod.error("[巅峰] 部分钩子未装上，功能可能不完整")
    end
end

todo_list = { "setup" }