mod.meta = { pkg_id = "bluefish.peakera", version = "4.0.0", version_code = 400, api_version = 1 }
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

-- 转正版：不写任何文件（日志实现留空，改回落盘只需恢复 logf 内部）
local function logf(_) end

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
local f_main_gamemenu, f_main_players, f_myplayer
local m_get_myplayer, m_newtext
local m_get_gamemenu

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

-- ① 伤害：钩 GetWeaponDamage 的返回值
-- 原版 = (int)(item.damage × meleeDamage)，item.damage 里已经含了词缀加成，
-- 所以乘一个固定比例 115/85，等于「词缀也按 115 这个新基准重算」，且一点数据都不动。
local function weapon_damage_postfix(inst, args, result)
    if not ready then return nil end
    local it = args and args[1]
    if not it then return nil end
    if get_i(f_item_type, it, -1) ~= TERRA_ID then return nil end
    if type(result) ~= "number" or result <= 0 then return nil end
    return math.floor(result * TERRA_DAMAGE / TERRA_BASE_DAMAGE + 0.5)
end

-- ② 使用时间：ItemCheck 之前临时把 useTime/useAnimation 改成 14，
-- 游戏按 14 算完挥动节奏后立刻还原，存档里永远是原版的 18。
local function itemcheck_prefix(inst)
    if not ready or not inst then return false end
    local it = held_item(inst)
    if not it then return false end
    if get_i(f_item_type, it, -1) ~= TERRA_ID then return false end
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
        restore_md(pl, "Update")
    else
        -- 单帧判定失败可能只是数组读取抖动，连续 30 帧才算真的没穿
        hood_miss = hood_miss + 1
        if hood_miss > 30 then md_base = -1 end
    end


    -- ③ 黑曜石套：鞭范围 / 鞭速度 / 召唤伤害（Update 末尾再兜一次，保证同帧生效）
    apply_obsidian(pl)

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
            pcall(fix_blade_multiplier)
            pcall(fix_terra_speed)
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
    pcall(restore_md, inst, "UpdateArmorSets")
    pcall(apply_obsidian, inst)
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
    f_myplayer      = find_field(T_Main, "myPlayer")
    if not f_myplayer then
        m_get_myplayer = patch.get_method(T_Main, "get_myPlayer", 0)
            or patch.get_method(T_Main, "get_myPlayer")
    end
    m_newtext = patch.get_method(T_Main, "NewText", 3) or patch.get_method(T_Main, "NewText", 5)

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