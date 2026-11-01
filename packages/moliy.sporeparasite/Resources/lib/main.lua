-- 孢子寄生 / Spore Parasite
-- 作者：Moliy    版本：1.1.0
-- 让孢子囊（Spore Sac）的孢子毒气飞得更快、孢子悬浮体追得更快，并提高孢子生成频率与数量上限。
-- 需要 LuaLoader ≥ 1.6.0（api_version 1，纯 Lua，无原生模块）。
--
-- 原理（全部取自 1.4.5.8 反编译源码，行号为 PC 版）：
--   生成：Player.SporeSac(Item)  Player.cs:42733
--         - Main.rand.Next(15) != 0 直接 return（约 1/15 概率）
--         - 场上已有 567/568 数量 >= 10 或 Main.rand.Next(15) < 数量 时 return（硬编码 10 个上限）
--         - 找到合法位置后 Projectile.NewProjectile(... 567 + rand(2) ...) 生成 1 个
--   悬浮体：Projectile.AI_105_SporeSac()  Projectile.cs:40769
--         - 追敌：velocity = (velocity * 40 + dir * 4) / 41，终端速度约 4
--   毒气：aiStyle 106 内联分支  Projectile.cs:34137
--         - 每帧 velocity *= 0.98，存活 60 帧；生成时初速 0.3（Projectile.cs:74318）
--
-- 1.0.3：
--   · 移速倍率 1-10，只在该悬浮体正在追敌时加速（没目标时不碰它的速度），超过目标速度会压回
--   · 新增「悬浮体数量上限」10-100（原版硬编码 10）：超上限时靠临时改 owner 让原版的计数失效
--   · 不再读 ai 数组（真机实测会 SIGSEGV）；不再带游戏内小面板

local P = mod.patch

local settings = {
    enabled = true,
    speed_multiplier = 5,
    production_multiplier = 5,
    max_spores = 10,
    accelerate_traps = true,
}

local TRAILING = { [567] = true, [568] = true }   -- 孢子悬浮体
local GAS = { [569] = true, [570] = true, [571] = true }  -- 孢子毒气

local T = {
    ready = false,
    hook_ai = nil,
    hook_spore = nil,
    spore_method = nil,
    busy = false,
    ai_calls = 0,
    calls_spore = 0,
    gas_boosted = 0,
    trap_boosted = 0,
    live_spores = 0,
    last_error = "",
    traps = {},       -- 弹幕对象指针 -> 最后一次被 AI 钩子看到时的 ai_calls
}

-- 毒气只在「第一次见到」时放大一次初速。
-- 键是弹幕对象指针（lightuserdata），对象死了地址可能被复用，所以表满就整体清掉。
local seen = {}
local seen_n = 0

local function first_sight(instance)
    if seen[instance] then
        return false
    end
    seen[instance] = true
    seen_n = seen_n + 1
    if seen_n > 2048 then
        seen = {}
        seen_n = 1
        seen[instance] = true
    end
    return true
end

local F = {}

local function clamp_int(v, lo, hi, default)
    v = tonumber(v)
    if v == nil then
        return default
    end
    v = math.floor(v + 0.5)
    if v < lo then v = lo end
    if v > hi then v = hi end
    return v
end

local function read_settings()
    local raw = nil
    local ok, err = pcall(function()
        raw = mod.read_file("config.json")
    end)
    if not ok or type(raw) ~= "string" then
        mod.warn("孢子寄生：没读到 config.json，全部走默认值（" .. tostring(err) .. "）")
        return
    end

    local function find_bool(key)
        local v = raw:match('"' .. key .. '"%s*:%s*(%a+)')
        if v == "true" then return true end
        if v == "false" then return false end
        return nil
    end

    local function find_num(key)
        local v = raw:match('"' .. key .. '"%s*:%s*(-?%d+%.?%d*)')
        return tonumber(v)
    end

    local b = find_bool("enabled")
    if b ~= nil then settings.enabled = b end
    local b2 = find_bool("accelerate_traps")
    if b2 ~= nil then settings.accelerate_traps = b2 end
    settings.speed_multiplier = clamp_int(find_num("speed_multiplier"), 1, 10, 5)
    settings.production_multiplier = clamp_int(find_num("production_multiplier"), 1, 50, 5)
    settings.max_spores = clamp_int(find_num("max_spores"), 10, 100, 10)
end

local function field_of(t, name)
    local ok, f = pcall(function()
        return P.get_field(t, name)
    end)
    if not ok or f == nil or not P.is_valid(f) then
        return nil
    end
    return f
end

-- 统计「最近还在被 AI 钩子看到」的悬浮体数量，顺手清掉已经不动的记录。
-- 只数不碰指针，改 owner 那一步另外做，避免读到已经回收的对象。
local function collect_live(window)
    local live = 0
    local list = nil
    local recycle = nil
    for inst, stamp in pairs(T.traps) do
        if T.ai_calls - stamp <= window then
            live = live + 1
            list = list or {}
            list[#list + 1] = inst
        else
            recycle = recycle or {}
            recycle[#recycle + 1] = inst
        end
    end
    if recycle then
        for i = 1, #recycle do
            T.traps[recycle[i]] = nil
        end
    end
    return live, list
end

-- 每帧、每个弹幕都会进来一次：先做最便宜的判断，再按类型分流
local function on_ai(instance, args, result)
    if not T.ready or not settings.enabled then return end
    if instance == nil then return end

    T.ai_calls = T.ai_calls + 1

    local mult = settings.speed_multiplier
    local ok, err = pcall(function()
        local ptype = P.get_field_value(F.ptype, instance, "int32")
        if ptype == nil then return end

        if TRAILING[ptype] then
            T.traps[instance] = T.ai_calls
            if not settings.accelerate_traps or mult <= 1 then return end
            local vx, vy = P.get_field_vec2(F.velocity, instance)
            if vx == nil then return end
            local sp = math.sqrt(vx * vx + vy * vy)
            -- 原版对 567/568 只有两种行为（Projectile.cs:40769 AI_105_SporeSac）：
            --   有敌人：velocity = (velocity * 40 + dir * 4) / 41  → 速度收敛到 4
            --   没敌人：velocity *= 0.98                             → 速度一路衰减
            -- 所以「速度还在 4 附近」就是正在追敌，「速度在掉」就是没目标在飘。
            -- 1.0.3 的错就错在不加区分地往回推到 target：没目标时它一直在飘，
            -- 我却每帧把它重新加速到 20px/帧 →  spores 全被打飞、满地图乱窜。
            if sp < 3.0 then return end
            local target = 4.0 * mult
            local k
            if sp >= target then
                -- 已经比目标快（高倍率下容易绕过目标），压回目标速度，避免绕圈来回甩
                k = target / sp
            else
                k = target / sp
                if k > 1.10 then k = 1.10 end
            end
            if k > 1.0 or k < 0.98 then
                P.set_field_vec2(F.velocity, instance, vx * k, vy * k)
                T.trap_boosted = T.trap_boosted + 1
            end
        elseif GAS[ptype] then
            if mult <= 1 then return end
            -- 只在第一次见到时放大初速；之后照原版 ×0.98 衰减，不会累积
            local vx, vy = P.get_field_vec2(F.velocity, instance)
            if vx == nil then return end
            local sp = math.sqrt(vx * vx + vy * vy)
            if sp < 0.01 then return end
            if not first_sight(instance) then return end
            if sp > 0.9 then return end          -- 只处理刚出生的毒气（初速 0.3）
            P.set_field_vec2(F.velocity, instance, vx * mult, vy * mult)
            T.gas_boosted = T.gas_boosted + 1
        end
    end)

    if not ok then
        T.ready = false
        T.last_error = tostring(err)
        mod.error("孢子寄生：弹幕加速出错，已自动停用 hook：" .. tostring(err))
    end
end

local function on_spore(instance, args)
    if not T.ready or not settings.enabled then return false end
    local n = settings.production_multiplier
    if n <= 1 then return false end
    if T.busy then return false end           -- 内层重入：让原版照常执行
    if instance == nil or args == nil or args[1] == nil then return false end

    T.calls_spore = T.calls_spore + 1

    local cap = settings.max_spores
    local live, list = collect_live(240)
    T.live_spores = live

    -- 到上限就别再生成（直接吞掉这次调用，原版本来也会 return）
    if live >= cap then
        return true
    end

    -- 上限高于原版 10 时：临时把现有悬浮体的 owner 改成 255，
    -- 让 Player.SporeSac 里那句 num >= 10 的计数永远为 0，从而绕过硬编码上限。
    local saved = nil
    if cap > 10 and list and F.owner then
        saved = {}
        for i = 1, #list do
            local trap = list[i]
            local o = P.get_field_value(F.owner, trap, "int32")
            if o ~= nil then
                saved[#saved + 1] = { trap, o }
            end
        end
        for i = 1, #saved do
            pcall(P.set_field_value, F.owner, saved[i][1], 255, "int32")
        end
    end

    T.busy = true
    local ok, err = pcall(function()
        for _ = 1, n do
            P.invoke(T.spore_method, instance, args[1])
        end
    end)
    T.busy = false

    if saved then
        for i = 1, #saved do
            pcall(P.set_field_value, F.owner, saved[i][1], saved[i][2], "int32")
        end
    end

    if not ok then
        T.ready = false
        T.last_error = tostring(err)
        mod.error("孢子寄生：追加生成出错，已自动停用 hook：" .. tostring(err))
        return false
    end
    return true
end

local function add_hook(method, def, label)
    if method == nil or not P.is_valid(method) then
        mod.error("孢子寄生：取不到方法 " .. label)
        return nil
    end
    local ok, hook = pcall(function()
        return P.install_hook(method, def)
    end)
    if not ok or hook == nil then
        mod.error("孢子寄生：装 hook 失败 " .. label .. "：" .. tostring(hook))
        return nil
    end
    return hook
end

function setup()
    read_settings()

    local proj = P.get_type("Terraria", "Projectile")
    local player = P.get_type("Terraria", "Player")
    if proj == nil or player == nil then
        T.last_error = "找不到 Terraria.Projectile / Terraria.Player"
        mod.error("孢子寄生：" .. T.last_error .. "，游戏版本可能不匹配")
        return
    end

    F.ptype = field_of(proj, "type")
    F.velocity = field_of(proj, "velocity")
    F.owner = field_of(proj, "owner")
    if F.ptype == nil or F.velocity == nil then
        T.last_error = "Projectile 字段没取全（type/velocity）"
        mod.error("孢子寄生：" .. T.last_error .. "，放弃安装")
        return
    end

    T.spore_method = P.get_method(player, "SporeSac", 1)
    if T.spore_method == nil or not P.is_valid(T.spore_method) then
        T.last_error = "取不到 Player.SporeSac(Item)"
        mod.error("孢子寄生：" .. T.last_error .. "，放弃安装")
        return
    end

    local ai_method = P.get_method(proj, "AI", 0)
    T.ready = true

    if settings.speed_multiplier > 1 then
        T.hook_ai = add_hook(ai_method, { postfix = on_ai }, "Projectile.AI")
    end
    if settings.production_multiplier > 1 then
        T.hook_spore = add_hook(T.spore_method, { prefix = on_spore }, "Player.SporeSac")
    end

    mod.info(string.format(
        "孢子寄生就绪：移速 ×%d（悬浮体%s），产量 ×%d，悬浮体上限 %d；hook=%s/%s",
        settings.speed_multiplier,
        settings.accelerate_traps and "也加速" or "不动",
        settings.production_multiplier,
        settings.max_spores,
        tostring(T.hook_ai ~= nil),
        tostring(T.hook_spore ~= nil)))
end

function mod.cleanup()
    T.ready = false
    if T.hook_ai ~= nil then
        pcall(function() T.hook_ai:remove() end)
        T.hook_ai = nil
    end
    if T.hook_spore ~= nil then
        pcall(function() T.hook_spore:remove() end)
        T.hook_spore = nil
    end
    mod.info("孢子寄生：已卸载，恢复原版孢子囊")
end

-- 启动入口：加载器会拿 todo_list 里的字符串去 _G 找同名函数，
-- 所以这里必须挂全局，不能是 local function。
local booted = false
local function boot()
    if booted then
        return
    end
    booted = true
    setup()
end

_G.spore_boot = boot
todo_list = { "spore_boot" }

function mod.init()
    boot()
end
