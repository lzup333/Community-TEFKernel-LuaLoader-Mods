-- 这是我觉得这很闪避啊 (Very Dodge) 1.0.0
-- 作者：Moliy
--
-- 作用：自定义 混乱之脑 / 忍者（黑腰带·忍者大师装备）/ 秘术腰带 的闪避概率。
--
-- 原版判定在 Player.Hurt 里（Source-1.4.5.8\PC\Terraria\Player.cs:38497-38519）：
--   38499  if (mysticSashDodge && Main.rand.Next(10) == 0) { DoMysticSashDodge(); return 0.0; }
--   38504  if (blackBelt && Main.rand.Next(10) == 0) { NinjaDodge(); return 0.0; }
--   38509  if (brainOfConfusionItem != null && !brainOfConfusionItem.IsAir && Main.rand.Next(6) == 0
--             && FindBuffIndex(321) == -1) { BrainOfConfusionDodge(); return 0.0; }
-- 命中顺序就是上面这个顺序，本模组保持一致。
--
-- 做法：钩 Player.Hurt 的 prefix，自己先掷骰。中了就调用原版对应的闪避动作，
--       再 return true, 0.0 跳过整个 Hurt（原版闪避也是 return 0.0，行为完全一致）。
--       没中就放行，让原版继续跑（后面的减伤、击退、无敌帧都照旧）。
--
-- 概率换算（目标 T，原版 v，都是 0..1）：
--   T >= v：prefix 掷 (T - v) / (1 - v)，原版判定保持不动。
--           两层合起来：命中概率 = p + (1-p) * v = T，正好等于目标值。
--   T <  v：prefix 自己掷 T，同时把该饰品这一次的判定压掉（postfix 还原）。
-- 压掉的办法：黑腰带 / 秘术腰带是 bool 字段，只在 Hurt 里被读，压掉无副作用；
--   混乱之脑是物品字段，只能临时置 null —— 这一次会连带跳过
--   Player.cs:38688 那段「被击时让附近敌人陷入困惑」的被动。

local P = mod.patch

local settings = {
    enabled = true,
    brain_chance = 17,
    ninja_chance = 10,
    sash_chance = 10,
}

local T = { ready = false, hook = nil, last_error = nil }
local F = {}
local M = {}
local S = { sup_sash = false, sup_belt = false, sup_brain = false, kept_brain = nil }

local function clamp_int(v, lo, hi)
    v = tonumber(v)
    if not v then
        return lo
    end
    v = math.floor(v + 0.5)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

local function read_settings()
    local ok, raw = pcall(mod.read_file, "config.json")
    if not ok or type(raw) ~= "string" then
        mod.warn("读不到 config.json，使用内置默认值")
        return
    end

    local function bool_of(key, dflt)
        local v = raw:match('"' .. key .. '"%s*:%s*(%a+)')
        if v == "true" then
            return true
        end
        if v == "false" then
            return false
        end
        return dflt
    end

    local function int_of(key, dflt, lo, hi)
        local v = raw:match('"' .. key .. '"%s*:%s*(-?%d+%.?%d*)')
        if v then
            return clamp_int(tonumber(v), lo, hi)
        end
        return dflt
    end

    settings.enabled = bool_of("enabled", settings.enabled)
    settings.brain_chance = int_of("brain_chance", settings.brain_chance, 0, 100)
    settings.ninja_chance = int_of("ninja_chance", settings.ninja_chance, 0, 100)
    settings.sash_chance = int_of("sash_chance", settings.sash_chance, 0, 100)
end

local function field_of(t, name)
    if not t or not P.is_valid(t) then
        return nil
    end
    local ok, f = pcall(P.get_field, t, name)
    if ok and f and P.is_valid(f) then
        return f
    end
    return nil
end

local function method_of(t, name, argc)
    if not t or not P.is_valid(t) then
        return nil
    end
    local ok, m = pcall(P.get_method, t, name, argc)
    if ok and m and P.is_valid(m) then
        return m
    end
    return nil
end

local function is_true(v)
    return v == true or v == 1
end

local function get_bool(f, inst)
    if not f then
        return false
    end
    local ok, v = pcall(P.get_field_value, f, inst, "bool")
    if ok then
        return is_true(v)
    end
    return false
end

local function set_bool(f, inst, v)
    if not f then
        return
    end
    pcall(P.set_field_value, f, inst, v, "bool")
end

local function get_int(f, inst)
    if not f then
        return 0
    end
    local ok, v = pcall(P.get_field_value, f, inst, "int32")
    if ok and type(v) == "number" then
        return v
    end
    return 0
end

local function is_local(inst)
    if not F.whoAmI or not F.myPlayer then
        return true
    end
    return get_int(F.whoAmI, inst) == get_int(F.myPlayer, nil)
end

-- 混乱之脑是否真的戴着（字段非 null 且物品不是空气）
local function brain_item(inst)
    if not F.brainItem then
        return nil
    end
    local ok, item = pcall(P.get_field_value, F.brainItem, inst, "object")
    if not ok or item == nil then
        return nil
    end
    if F.itemType then
        if get_int(F.itemType, item) <= 0 then
            return nil
        end
    end
    return item
end

-- 原版 38509 的最后一个条件：身上有 321 号 buff 就不掷那一手
local function brain_buff_blocked(inst)
    if not M.findBuff then
        return false
    end
    local ok, idx = pcall(P.invoke, M.findBuff, inst, 321)
    if ok and type(idx) == "number" then
        return idx ~= -1
    end
    return false
end

-- 返回：这次要掷的概率 p、原版判定要不要压掉
local function roll_for(target, vanilla)
    if target <= vanilla then
        return target, true
    end
    local p = (target - vanilla) / (1.0 - vanilla)
    if p < 0 then
        p = 0
    end
    if p > 1 then
        p = 1
    end
    return p, false
end

local function restore_all(inst)
    if S.sup_sash then
        S.sup_sash = false
        set_bool(F.sash, inst, true)
    end
    if S.sup_belt then
        S.sup_belt = false
        set_bool(F.blackBelt, inst, true)
    end
    if S.sup_brain then
        S.sup_brain = false
        local kept = S.kept_brain
        S.kept_brain = nil
        if kept ~= nil and F.brainItem then
            pcall(P.set_field_value, F.brainItem, inst, kept, "object")
        end
    end
end

local function evaluate(inst)
    if not is_local(inst) then
        return false
    end
    -- 原版 38491-38496：处于无敌帧时直接 return 0.0，不会走到闪避判定
    if get_bool(F.immune, inst) then
        return false
    end

    local sash_on = get_bool(F.sash, inst)
    local belt_on = get_bool(F.blackBelt, inst)
    local brain = brain_item(inst)

    if sash_on then
        local p, suppress = roll_for(settings.sash_chance / 100.0, 0.1)
        if suppress then
            set_bool(F.sash, inst, false)
            S.sup_sash = true
        end
        if p > 0 and math.random() < p then
            pcall(P.invoke, M.sashDodge, inst)
            return true
        end
    end

    if belt_on then
        local p, suppress = roll_for(settings.ninja_chance / 100.0, 0.1)
        if suppress then
            set_bool(F.blackBelt, inst, false)
            S.sup_belt = true
        end
        if p > 0 and math.random() < p then
            pcall(P.invoke, M.ninjaDodge, inst)
            return true
        end
    end

    if brain ~= nil then
        local vanilla = 1.0 / 6.0
        if brain_buff_blocked(inst) then
            vanilla = 0.0
        end
        local p, suppress = roll_for(settings.brain_chance / 100.0, vanilla)
        if suppress then
            S.kept_brain = P.retain(brain)
            pcall(P.set_field_value, F.brainItem, inst, nil, "object")
            S.sup_brain = true
        end
        if p > 0 and math.random() < p then
            pcall(P.invoke, M.brainDodge, inst)
            return true
        end
    end

    return false
end

local function on_prefix(inst, args, result)
    if not T.ready or not settings.enabled then
        return false
    end
    if inst == nil then
        return false
    end
    if args and args[8] == false then
        return false
    end

    local ok, dodged = pcall(evaluate, inst)
    if not ok then
        T.last_error = tostring(dodged)
        restore_all(inst)
        return false
    end
    if dodged then
        restore_all(inst)
        return true, 0.0
    end
    return false
end

local function on_postfix(inst, args, result)
    if S.sup_sash or S.sup_belt or S.sup_brain then
        restore_all(inst)
    end
end

local function setup()
    read_settings()
    if not settings.enabled then
        mod.info("这是我觉得这很闪避啊：设置里已关闭，不安装钩子")
        return
    end

    local player = P.get_type("Terraria", "Player")
    local main = P.get_type("Terraria", "Main")
    local item = P.get_type("Terraria", "Item")
    if not player or not main then
        mod.error("取不到 Terraria.Player / Terraria.Main，放弃安装")
        return
    end

    F.sash = field_of(player, "mysticSashDodge")
    F.blackBelt = field_of(player, "blackBelt")
    F.brainItem = field_of(player, "brainOfConfusionItem")
    F.immune = field_of(player, "immune")
    F.myPlayer = field_of(main, "myPlayer")
    -- whoAmI 定义在基类 Entity 上（Entity.cs:8），Player 上直接取可能取不到
    F.whoAmI = field_of(player, "whoAmI")
    if not F.whoAmI then
        local entity = P.get_type("Terraria", "Entity")
        if entity then
            F.whoAmI = field_of(entity, "whoAmI")
        end
    end
    if item then
        F.itemType = field_of(item, "type")
    end

    if not F.sash and not F.blackBelt and not F.brainItem then
        mod.error("取不到 mysticSashDodge / blackBelt / brainOfConfusionItem，放弃安装")
        return
    end

    local hurt = method_of(player, "Hurt", 8)
    if not hurt then
        mod.error("取不到 Player.Hurt(...)，放弃安装")
        return
    end

    M.sashDodge = method_of(player, "DoMysticSashDodge", 0)
    M.ninjaDodge = method_of(player, "NinjaDodge", 0)
    M.brainDodge = method_of(player, "BrainOfConfusionDodge", 0)
    M.findBuff = method_of(player, "FindBuffIndex", 1)

    if not M.sashDodge and not M.ninjaDodge and not M.brainDodge then
        mod.error("取不到闪避动作方法，放弃安装")
        return
    end

    pcall(math.randomseed, os.time and os.time() or 0)

    local ok, hook = pcall(P.install_hook, hurt, { prefix = on_prefix, postfix = on_postfix })
    if not ok or not hook then
        mod.error("安装 Player.Hurt 钩子失败：" .. tostring(hook))
        return
    end

    T.hook = hook
    T.ready = true
    mod.info(string.format(
        "这是我觉得这很闪避啊就绪：混乱之脑 %d%%、忍者（黑腰带/忍者大师装备）%d%%、秘术腰带 %d%%",
        settings.brain_chance, settings.ninja_chance, settings.sash_chance))
end

function mod.cleanup()
    if T.hook then
        pcall(function()
            T.hook:remove()
        end)
        T.hook = nil
    end
    T.ready = false
end

function _G.verydodge_boot()
    local ok, err = pcall(setup)
    if not ok then
        T.ready = false
        T.last_error = tostring(err)
        mod.error("启动失败：" .. T.last_error)
    end
end

todo_list = { "verydodge_boot" }

function mod.init()
    _G.verydodge_boot()
end
