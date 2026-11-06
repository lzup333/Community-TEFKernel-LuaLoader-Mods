--=====================================================================
-- 全能大师 (Ultimate Master) v1.1.0
-- 肉前终极毕业移动饰品：缝合 7 件神装的移动精髓
--
-- v1.1.0 修复（全部对照 1.4.5.8.6 源码逐字段核对）
--   · spiderWalk                    -> spider
--   · accRun（不存在）              -> rocketBoots + canRocket
--   · doubleJumpCloud/Blizzard/     -> 本版直接移除。该饰品本身不提供二段跳，
--     Sandstorm（1.4.4 已改名）        强制置 false 只会废掉玩家自己戴的气球
--   · 受击 Buff 158（瓶中星光）      -> 63 (BuffID.Panic)
--   · item.Prefix(-3)              -> 删除。quickapi 的 defaults 代理只查字段
--                                     不查方法，item.Prefix 返回 nil，调用即报错；
--                                     且已有 prefixes = false，本就多余
--   · 每帧重置 rocketTime           -> 删除。只设 rocketTimeMax，飞行时自然消耗、
--                                     落地由原版补满 = 真正的限时飞行（原版为无限飞）
--   · moveSpeed = 1.0              -> 修正为可调倍率（1.0 等于原版默认，起不到加速）
--   · 贴图 Resources/Images/        -> Resources/Image/（官方要求 Image 目录）
--   · hook 未保存 / cleanup 为空    -> 保存句柄并在 cleanup 中 remove
--   · 每帧解析句柄与 item_id        -> 改为一次性解析 + 缓存
--=====================================================================
require("quickapi")

local q     = mod.quickapi
local patch = mod.patch

--==================== 可调参数（改这里就能调手感）====================
local CFG = {
    run_mph        = 50,    -- 常态奔跑目标速度（mph）
    burst_mph      = 100,   -- 受击爆发目标速度（mph）
    burst_seconds  = 8,     -- 爆发持续秒数（恐慌 Buff 也是 8 秒）
    fly_frames     = 204,   -- 飞行帧数，60 帧 = 1 秒，204 ≈ 3.4 秒
    lava_frames    = 2520,  -- 熔岩免疫帧数，2520 ≈ 42 秒
    rocket_level   = 3,     -- 初始火箭靴档位（面板可调）
    move_speed     = 1.6,   -- 移速倍率（原版装备加成也在这一档，1.0 = 无加成）
    run_accel      = 1.5,   -- 起步加速度
    run_slowdown   = 1.5,   -- 刹车减速度
}

-- mph -> Player.maxRunSpeed。原版 maxRunSpeed=3.0 约等于 15mph，
-- 换算系数 216000/42240 ≈ 5.1136。数值若手感不符，改 CFG 里的 mph 即可。
local function mph_to_run(mph) return mph / 5.1136 end

--==================== 状态 ==================
local F = {}                                  -- Player 字段句柄缓存
local F_item_type                             -- Item.type 字段句柄
local S = { frame = 0, burst_until = 0, item_id = false, rocket = 3, vanity = 6 }
local hook_equips, hook_hurt

--==================== 句柄解析（只做一次）====================
local PLAYER_FIELDS = {
    "moveSpeed", "maxRunSpeed", "accRunSpeed", "runAcceleration", "runSlowdown",
    "lavaMax", "lavaTime",
    "fireWalk", "waterWalk", "iceSkate", "ignoreWater", "accFlipper", "noFallDmg",
    "spider", "autoJump", "nightVision", "lightOrb",
    "rocketBoots", "canRocket", "rocketTime", "rocketTimeMax", "rocketFrame", "vanityRocketBoots", "velocity",
    "armor",
}

-- 沿父类链查找字段（Entity.velocity 这类继承字段必须这样找）
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

local function bind_fields()
    local PT = q.type("Terraria", "Player")
    local IT = q.type("Terraria", "Item")
    if not PT or not IT then
        mod.error("[全能大师] 取不到 Terraria.Player / Terraria.Item 类型")
        return false
    end
    local missing = {}
    for _, name in ipairs(PLAYER_FIELDS) do
        F[name] = find_field(PT, name)
        if not F[name] then missing[#missing + 1] = name end
    end
    F_item_type = find_field(IT, "type")
    if not F_item_type then missing[#missing + 1] = "Item.type" end
    if #missing > 0 then
        mod.warn("[全能大师] 以下字段缺失，对应效果将跳过: " .. table.concat(missing, ", "))
    end
    return F.armor ~= nil
end

--==================== 判断是否佩戴 ====================
-- 注册阶段内核还没分配 ID，返回 -1；进世界后才有真实 ID，所以延迟解析并缓存。
local function acc_id()
    if S.item_id and S.item_id > 0 then return S.item_id end
    local id = q.item_id("UltimateMaster")
    if type(id) == "number" and id > 0 then
        S.item_id = id
        return id
    end
    return nil
end

local function has_acc(player)
    local id = acc_id()
    if not id or not F.armor then return false end
    local armor = patch.get_field_value(F.armor, player, "object")
    if not armor then return false end
    -- armor[0..2] 是头/身/腿，armor[3..9] 是 7 个饰品槽
    for i = 3, 9 do
        local it = patch.array_at(armor, i)
        if it and patch.get_field_value(F_item_type, it, "int32") == id then
            return true
        end
    end
    return false
end

--==================== 写字段的小包装 ====================
local function set_f(player, name, v, ty)
    local f = F[name]
    if f then patch.set_field_value(f, player, v, ty) end
end

--==================== 每帧属性注入 ====================
local function apply(player)
    local bursting = S.frame < S.burst_until
    local target   = bursting and CFG.burst_mph or CFG.run_mph
    local run      = mph_to_run(target)

    -- 极限移速
    set_f(player, "maxRunSpeed",    run,           "float")
    set_f(player, "accRunSpeed",    run,           "float")
    set_f(player, "moveSpeed",      CFG.move_speed,  "float")
    set_f(player, "runAcceleration", CFG.run_accel,  "float")
    set_f(player, "runSlowdown",     CFG.run_slowdown, "float")

    -- 熔岩 / 液体
    set_f(player, "lavaMax",    CFG.lava_frames, "int32")
    set_f(player, "lavaTime",   CFG.lava_frames, "int32")
    set_f(player, "fireWalk",   true, "bool")
    set_f(player, "waterWalk",  true, "bool")
    set_f(player, "iceSkate",   true, "bool")
    set_f(player, "ignoreWater", true, "bool")
    set_f(player, "accFlipper", true, "bool")
    set_f(player, "noFallDmg",  true, "bool")

    -- 地面与深渊机动
    set_f(player, "spider",     true, "bool")
    set_f(player, "autoJump",   true, "bool")
    set_f(player, "nightVision", true, "bool")
    set_f(player, "lightOrb",   true, "bool")

    -- 飞行：只设上限，不设当前值。
    -- 原版在落地时把 rocketTime 补到 rocketTimeMax，飞行时逐帧消耗，
    -- 所以这样才是「3.4 秒飞完就得落地」；每帧重置 rocketTime 会变成无限飞。
    set_f(player, "rocketBoots",    S.rocket, "int32")
    set_f(player, "canRocket",      true,             "bool")
    set_f(player, "rocketTimeMax",  CFG.fly_frames,   "int32")
    set_f(player, "vanityRocketBoots", S.vanity, "int32")   -- 靴子外观档位（驱动原版火焰尝试）

    -- ★实验：补写 rocketFrame，尝试驱动原版火焰粒子
    if F.rocketFrame and F.velocity then
        local _, vy = patch.get_field_vec2(F.velocity, player)
        local rt = patch.get_field_value(F.rocketTime, player, "int32")
        if type(vy) == "number" and vy ~= 0 and type(rt) == "number" and rt > 0 then
            set_f(player, "rocketFrame", true, "bool")
        end
    end
end

--==================== Hook 回调 ====================
local function on_equips(player)
    if not player then return end
    S.frame = S.frame + 1
    if not has_acc(player) then return end
    apply(player)
end

local function on_hurt(player)
    if not player then return end
    if not has_acc(player) then return end
    -- BuffID.Panic = 63（158 是 StarInBottle 瓶中星光，原代码写错了）
    S.burst_until = S.frame + CFG.burst_seconds * 60
    if mod.buff and mod.buff.add then
        pcall(mod.buff.add, 63, player, CFG.burst_seconds * 60)
    end
end

--==================== 生命周期 ====================
function mod.init()
    q.register_item({
        name      = "UltimateMaster",
        texture   = "acc.png",              -- 文件在 Resources/Image/acc.png
        tooltip   = true,                   -- ★必须为 true 才会显示 language 里的介绍
        accessory = true,
        width     = 24,
        height    = 24,
        rare      = 11,
        value     = 5000000,
        prefixes  = false,                  -- 禁用随机前缀，防词缀覆盖介绍

        language = {
            zh = {
                name    = "全能大师",
                tooltip = "赋予泰拉大陆最顶级的终极机动性\n"
                       .. "【极限陆地】极速奔跑、极高起步加速度\n"
                       .. "【立体机动】约 3.4 秒超长飞行、墙面攀爬、自动连跳\n"
                       .. "【全地形】水面行走、冰面防滑、涉水极速\n"
                       .. "【炼狱适应】42 秒熔岩免疫与行走\n"
                       .. "【深渊适应】水下呼吸、夜视\n"
                       .. "【求生本能】受击后 8 秒极速爆发\n"
                       .. "——拥有了它，你就是风本身",
            },
        },

        recipe = {
            result = 1,
            materials = {
                { id = 5000, count = 1 },   -- 泰拉闪耀靴
                { id = 3990, count = 1 },   -- 水陆两用靴
                { id = 1861, count = 1 },   -- 北极潜水装备
                { id = 5331, count = 1 },   -- 马掌气球束 (HorseshoeBundle)
                { id = 5107, count = 1 },   -- 魔光护符
                { id = 3995, count = 1 },   -- 青蛙装备
                { id = 1290, count = 1 },   -- 恐慌项链
            },
            station = 114,                  -- 工匠作坊
        },
    })

    if not bind_fields() then
        mod.error("[全能大师] 句柄绑定失败，属性注入不会生效")
        return
    end

    -- Player.UpdateEquips(int i)：1 参
    hook_equips = q.install_hook_postfix("Terraria", "Player", "UpdateEquips",
            function(player) pcall(on_equips, player) end, { argc = 1 })

    -- Player.Hurt(PlayerDeathReason, int, int, bool, bool, bool, int, bool)：8 参
    hook_hurt = q.install_hook_postfix("Terraria", "Player", "Hurt",
            function(player) pcall(on_hurt, player) end, { argc = 8 })

    if not hook_equips then mod.error("[全能大师] UpdateEquips 钩子安装失败") end
    if not hook_hurt   then mod.warn("[全能大师] Hurt 钩子安装失败，受击爆发不可用") end
    mod.info(string.format("[全能大师] v1.1.6 已加载（%.0f mph / 飞行 %d 帧）",
            CFG.run_mph, CFG.fly_frames))
end

function mod.cleanup()
    for _, h in ipairs({ hook_equips, hook_hurt }) do
        if h then pcall(function() h:remove() end) end
    end
    hook_equips, hook_hurt = nil, nil
    F, F_item_type = {}, nil
    S = { frame = 0, burst_until = 0, item_id = false, rocket = S.rocket, vanity = S.vanity }
end
