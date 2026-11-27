-- 无尽补给 (Endless Supply) 2.0.0（终版）
-- 手机端 TEFKernel + LuaLoader，纯 Lua
--
-- 范围（用户 2026-11-03 定稿）：
--   ① 弹药不消耗
--   ② 治疗药水不消耗（只认回血，蓝药 / 其他药水 / 食物一律按原版扣）
--   投掷类消耗品不处理。
--
-- 实现：
--   ① 弹药：Player.PickAmmo(8 参) + Player.PickAmmo_PickAmmoItem(1 参)
--      - 扣减只有一行 Player.cs:54319，扣的是 PickAmmo_PickAmmoItem 返回的那件背包 Item，
--        所以在那件 Item 上做「记下扣前数量 → 扣完写回」。真机已验证生效。
--      - 只剩 1 个时先临时抬到 2，避开原版 TurnToAir 把整格清空的路径。
--   ② 治疗药水：不钩 Player.CanConsumeConsumableItem —— 那个方法体只有 `return true;`
--      （Player.cs:5488-5491），IL2CPP 发布版会把它内联进调用点，钩子装得上却永不触发
--      （v1.0.1 真机窗口实测 CanConsume=0）。改成「记录 → 结算」：
--        * 记录点：Player.ItemCheck_TryStartUse(Item) prefix，
--                  备用 Player.ApplyLifeAndOrMana(Item) postfix；
--        * 结算点：Player.ItemCheck() postfix、Player.QuickHeal() postfix。
--      - 跨帧用 mod.patch.retain 拿 GC 托管副本，借用句柄下一帧就失效。
--   ③ 全程只用字段读写，不碰任何 array 原语
--      （钓鱼优化 1.3.0 的 patchlib_array_length 曾让游戏 SIGSEGV，pcall 拦不住）。

local P = mod.patch

local settings = {
    enabled = true,
    keep_ammo = true,
    keep_heal = true,
}

local T = {
    ready = false,
    hooks = {},
    last_error = nil,
}

local S = {
    -- 弹药
    pa_calls = 0,
    pi_calls = 0,
    pa_restore = 0,
    -- 治疗药水
    rec_calls = 0,
    rec_ok = 0,
    restored = 0,
    restore_fail = 0,
    errors = 0,
    -- 记账
    rec_item = nil,
    rec_before = 0,
    rec_bumped = false,
    rec_ttl = 0,
    ammo_item = nil,
    ammo_before = 0,
    ammo_bumped = false,
}

local F = {}
local M = {}

local function yn(v)
    if v then
        return "开"
    end
    return "关"
end

local function note_error(what, err)
    S.errors = S.errors + 1
    T.last_error = tostring(what) .. ": " .. tostring(err)
    if S.errors <= 3 then
        pcall(mod.warn, "无尽补给：" .. T.last_error)
    end
end

local function read_settings()
    local ok, raw = pcall(mod.read_file, "config.json")
    if not ok or type(raw) ~= "string" then
        return
    end
    local function bool_of(key, fallback)
        local v = raw:match('"' .. key .. '"%s*:%s*(%a+)')
        if v == "true" then
            return true
        elseif v == "false" then
            return false
        end
        return fallback
    end
    settings.enabled = bool_of("enabled", settings.enabled)
    settings.keep_ammo = bool_of("keep_ammo", settings.keep_ammo)
    settings.keep_heal = bool_of("keep_heal", settings.keep_heal)
end

local function field_of(t, name)
    if t == nil then
        return nil
    end
    local ok, f = pcall(P.get_field, t, name)
    if ok and f ~= nil and P.is_valid(f) then
        return f
    end
    return nil
end

local function method_of(t, name, argc)
    if t == nil then
        return nil
    end
    local ok, m = pcall(P.get_method, t, name, argc)
    if ok and m ~= nil and P.is_valid(m) then
        return m
    end
    return nil
end

local function get_int(field, instance)
    if field == nil or instance == nil then
        return nil
    end
    local ok, v = pcall(P.get_field_value, field, instance, "int32")
    if ok and type(v) == "number" then
        return v
    end
    return nil
end

local function set_int(field, instance, value)
    if field == nil or instance == nil then
        return false
    end
    local ok, r = pcall(P.set_field_value, field, instance, value, "int32")
    if not ok then
        return false
    end
    return r ~= false
end

local function my_player_index()
    if F.myPlayer == nil then
        return nil
    end
    return get_int(F.myPlayer, nil)
end

-- 只处理本地玩家；取不到 whoAmI / myPlayer 时按「是本地玩家」处理（单机不会错）
local function is_local(inst)
    if inst == nil or F.whoAmI == nil then
        return true
    end
    local who = get_int(F.whoAmI, inst)
    if who == nil then
        return true
    end
    local mine = my_player_index()
    if mine == nil then
        return true
    end
    return who == mine
end

-- 只认「治疗药水」：有回血量、且不是食物（食物 buff 走另一条）
local function is_heal_potion(item)
    if item == nil then
        return false
    end
    local heal = get_int(F.healLife, item) or 0
    if heal <= 0 then
        return false
    end
    return true
end

-- 跨帧句柄：能 retain 就 retain，不能就退回借用句柄（同帧结算仍可用）
local function keep_handle(inst)
    if P.retain ~= nil then
        local ok, h = pcall(P.retain, inst)
        if ok and h ~= nil then
            return h
        end
    end
    return inst
end

-- 记录点：这瓶治疗药马上要用，先记下扣前数量；只剩 1 个时抬到 2
local function remember(inst, item)
    if not T.ready or not settings.enabled or not settings.keep_heal then
        return
    end
    if item == nil or not is_local(inst) or not is_heal_potion(item) then
        return
    end
    local n = get_int(F.stack, item)
    if n == nil or n <= 0 then
        return
    end
    local h = keep_handle(item)
    if n == 1 then
        pcall(set_int, F.stack, item, 2)
    end
    S.rec_item = h
    S.rec_before = n
    S.rec_bumped = (n == 1)
    S.rec_ttl = 240
    S.rec_ok = S.rec_ok + 1
end

-- 结算点：扣过了就把数量写回；还没扣就等下一帧，最多等 240 帧
local function settle()
    local h = S.rec_item
    if h == nil then
        return
    end
    S.rec_ttl = S.rec_ttl - 1
    local now = get_int(F.stack, h)
    local done = false
    if now == nil then
        done = true
    elseif S.rec_bumped then
        if now ~= 1 then
            if pcall(set_int, F.stack, h, 1) then
                S.restored = S.restored + 1
            else
                S.restore_fail = S.restore_fail + 1
            end
        end
        done = true
    elseif now == S.rec_before - 1 then
        if pcall(set_int, F.stack, h, S.rec_before) then
            S.restored = S.restored + 1
        else
            S.restore_fail = S.restore_fail + 1
        end
        done = true
    elseif now ~= S.rec_before then
        done = true
    end
    if done or S.rec_ttl <= 0 then
        S.rec_item = nil
        S.rec_before = 0
        S.rec_bumped = false
        S.rec_ttl = 0
    end
end

-- 记录点一：Player.ItemCheck_TryStartUse(Item) prefix（点 H 喝药、正常使用都会过这里）
local function on_try_prefix(inst, args, result)
    S.rec_calls = S.rec_calls + 1
    local ok, err = pcall(remember, inst, args and args[1])
    if not ok then
        note_error("记录治疗药", err)
    end
    return false
end

-- 记录点二（备用）：Player.ApplyLifeAndOrMana(Item) postfix，回血药一定过这里
local function on_life_postfix(inst, args, result)
    if S.rec_item ~= nil then
        return
    end
    S.rec_calls = S.rec_calls + 1
    local ok, err = pcall(remember, inst, args and args[1])
    if not ok then
        note_error("记录治疗药", err)
    end
end

local function on_settle_postfix(inst, args, result)
    local ok, err = pcall(settle)
    if not ok then
        note_error("写回治疗药", err)
    end
end

-- 弹药（第一段）：每次 PickAmmo 开始前清状态
local function on_pickammo_prefix(inst, args, result)
    S.pa_calls = S.pa_calls + 1
    S.ammo_item = nil
    S.ammo_before = 0
    S.ammo_bumped = false
    return false
end

-- 弹药（第二段）：拿到本次真正会被扣的那件 Item
local function on_pickammo_item_postfix(inst, args, result)
    S.pi_calls = S.pi_calls + 1
    if not T.ready or not settings.enabled or not settings.keep_ammo then
        return
    end
    if result == nil or not is_local(inst) then
        return
    end
    local n = get_int(F.stack, result)
    if n == nil or n <= 0 then
        return
    end
    local h = keep_handle(result)
    S.ammo_item = h
    S.ammo_before = n
    if n == 1 then
        if set_int(F.stack, result, 2) then
            S.ammo_bumped = true
        end
    end
end

-- 弹药（第三段）：PickAmmo 结束，把数量写回扣减前的值
local function on_pickammo_postfix(inst, args, result)
    local item = S.ammo_item
    local before = S.ammo_before
    local bumped = S.ammo_bumped
    S.ammo_item = nil
    S.ammo_before = 0
    S.ammo_bumped = false
    if not T.ready or not settings.enabled or not settings.keep_ammo then
        return
    end
    if item == nil or before <= 0 then
        return
    end
    local now = get_int(F.stack, item)
    if now == nil then
        return
    end
    if bumped then
        if now ~= before then
            if set_int(F.stack, item, before) then
                S.pa_restore = S.pa_restore + 1
            end
        end
    elseif now == before - 1 then
        if set_int(F.stack, item, before) then
            S.pa_restore = S.pa_restore + 1
        end
    end
end

local function add_hook(method, def, label)
    if method == nil then
        return false
    end
    local ok, hook = pcall(P.install_hook, method, def)
    if not ok or hook == nil then
        note_error("安装钩子 " .. tostring(label), hook)
        return false
    end
    T.hooks[#T.hooks + 1] = hook
    return true
end

local function setup()
    read_settings()
    if not settings.enabled then
        pcall(mod.info, "无尽补给已关闭（启动器里打开后重新进入游戏即可）")
        return
    end
    local okp, player = pcall(P.get_type, "Terraria", "Player")
    local okm, main = pcall(P.get_type, "Terraria", "Main")
    local oki, item = pcall(P.get_type, "Terraria", "Item")
    if not okp or player == nil or not okm or main == nil or not oki or item == nil then
        pcall(mod.error, "取不到 Terraria.Player / Main / Item，放弃安装")
        return
    end

    F.whoAmI = field_of(player, "whoAmI")
    if F.whoAmI == nil then
        local oke, entity = pcall(P.get_type, "Terraria", "Entity")
        if oke and entity ~= nil then
            F.whoAmI = field_of(entity, "whoAmI")
        end
    end
    F.myPlayer = field_of(main, "myPlayer")

    F.healLife = field_of(item, "healLife")
    F.stack = field_of(item, "stack")

    M.pickAmmo = method_of(player, "PickAmmo", 8)
    M.pickAmmoItem = method_of(player, "PickAmmo_PickAmmoItem", 1)
    M.tryStartUse = method_of(player, "ItemCheck_TryStartUse", 1)
    M.applyLifeMana = method_of(player, "ApplyLifeAndOrMana", 1)
    M.itemCheck = method_of(player, "ItemCheck", 0)
    M.quickHeal = method_of(player, "QuickHeal", 0)

    local need_heal = settings.keep_heal
    local need_ammo = settings.keep_ammo

    if need_heal and (F.stack == nil or F.healLife == nil or (M.tryStartUse == nil and M.applyLifeMana == nil)) then
        pcall(mod.warn, "取不到 Item.healLife / Item.stack / ItemCheck_TryStartUse，治疗药不生效")
        need_heal = false
    end
    if need_heal and M.itemCheck == nil and M.quickHeal == nil then
        pcall(mod.warn, "取不到 ItemCheck / QuickHeal，治疗药无法结算")
        need_heal = false
    end
    if need_ammo and (M.pickAmmo == nil or M.pickAmmoItem == nil or F.stack == nil) then
        pcall(mod.warn, "取不到 PickAmmo / PickAmmo_PickAmmoItem / Item.stack，弹药不消耗不生效")
        need_ammo = false
    end
    if not need_heal and not need_ammo then
        pcall(mod.error, "没有可用的钩子，模组不生效")
        return
    end

    T.ready = true
    local hooked = 0

    if need_heal then
        if M.tryStartUse ~= nil then
            if add_hook(M.tryStartUse, { prefix = on_try_prefix }, "ItemCheck_TryStartUse") then
                hooked = hooked + 1
            end
        end
        if M.applyLifeMana ~= nil then
            if add_hook(M.applyLifeMana, { postfix = on_life_postfix }, "ApplyLifeAndOrMana") then
                hooked = hooked + 1
            end
        end
        if M.itemCheck ~= nil then
            if add_hook(M.itemCheck, { postfix = on_settle_postfix }, "ItemCheck") then
                hooked = hooked + 1
            end
        end
        if M.quickHeal ~= nil then
            if add_hook(M.quickHeal, { postfix = on_settle_postfix }, "QuickHeal") then
                hooked = hooked + 1
            end
        end
    end

    if need_ammo then
        if add_hook(M.pickAmmo, { prefix = on_pickammo_prefix, postfix = on_pickammo_postfix }, "PickAmmo") then
            hooked = hooked + 1
        end
        if add_hook(M.pickAmmoItem, { postfix = on_pickammo_item_postfix }, "PickAmmo_PickAmmoItem") then
            hooked = hooked + 1
        end
    end

    pcall(mod.info, "无尽补给就绪：弹药不消耗 %s、治疗药不消耗 %s（共装 %d 个钩子）",
        yn(need_ammo), yn(need_heal), hooked)
end

function mod.cleanup()
    for i = 1, #T.hooks do
        pcall(function()
            T.hooks[i]:remove()
        end)
    end
    T.hooks = {}
    T.ready = false
end

local function boot()
    local ok, err = pcall(setup)
    if not ok then
        T.ready = false
        note_error("setup", err)
        pcall(mod.error, "无尽补给初始化失败：" .. tostring(err))
    end
end

_G.endless_supply_boot = boot
todo_list = { "endless_supply_boot" }

function mod.init()
    boot()
end
