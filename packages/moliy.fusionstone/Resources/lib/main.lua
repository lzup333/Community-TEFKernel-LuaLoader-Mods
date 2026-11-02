-- 聚变石 / Fusion Stone
-- 作者：Moliy    版本：1.0.1
-- 加强原版闪亮石（Shiny Stone，物品 ID 3337）：把静止再生的上限从 40 HP/s 提到可调的 4000 HP/s，
-- 并且移动、受伤、使用物品、流血都不再重置爬升进度。
-- 需要 LuaLoader ≥ 1.6.0（api_version 1，纯 Lua，无原生模块）。
-- 启动器设置：启用开关 + 档位（温和/标准/极限/自定义）+ 自定义档时的上限与爬升秒数，
--   由 LuaLoader 直接读 Info.json 的 settings 渲染（和光影 Mod 的面板同一套控件）。
--
-- 原理（全部取自 1.4.5.8 反编译源码；下面注释用「单文件 Player.cs」的行号，
--   用户给的 Source-1.4.5.8.zip 里同一段代码在 Player.cs:19056 起、回血循环在 19405，
--   行号不同但逻辑逐句一致）：
--   原版节奏：Player.UpdateLifeRegen()  Player.cs:20058
--     - Player.cs:20086-20089  flag = shinyStone && IsConsideredStandingStill && itemAnimation == 0
--     - Player.cs:20266-20274  flag 时 lifeRegenTime 先托底到 1800、每帧 +4，lifeRegen 也 +4
--     - Player.cs:20358-20370  lifeRegenTime 超过 3000 后按 (t-3000)/300 加 num5（最多 +30）
--     - Player.cs:20385-20393  站立 ×1.25，闪亮石再 ×1.1
--     - Player.cs:20408-20409  lifeRegenCount += lifeRegen
--     - Player.cs:20433-20460  每 120 点 lifeRegenCount 回 1 点血（满血时点数照样扣掉，不会攒）
--   重置点：流血 Player.cs:20321、受伤 Player.cs:42595、溺水 Player.cs:25393、用物品（itemAnimation != 0）
--
-- 做法：勾 UpdateLifeRegen 的 prefix/postfix。
--   1. 先判断这件饰品有没有生效（shinyStone），没装 / 死亡就把我们自己的计时清零；
--   2. 装了就先把 shinyStone 置 false —— 让原版那段「静止才加速」的分支整段跳过，
--      由本模组接管这一段再生，避免两边叠加；
--   3. 自己维护一个只增不减的爬升计时 S.t，算出当前应当的 HP/s，
--      换算成 lifeRegenCount 点数（120 点 = 1 血）加到玩家身上，原版自己的回血循环会把血加上去；
--   4. postfix 把 shinyStone 恢复成 true，不影响原版其它地方读这个字段。
--   因为重置点全部来自原版那段分支，而我们已经把它跳过，所以移动/受伤/用物品/流血都不用额外处理。
--
-- 只处理本地玩家（whoAmI == Main.myPlayer）：别的玩家的血量由服务器同步，客户端硬改会错位。

local P = mod.patch

local settings = {
    enabled = true,
    preset = "standard",
    max_regen = 4000,
    ramp_seconds = 20,
}

local T = {
    ready = false,
    hook = nil,
    last_error = "",
    calls = 0,
}

local F = {}

-- S.t 是「已经爬升了多少秒」，只在没装石头或死亡时归零。
-- S.acc 是凑不满 1 点的零头，S.hps 只用于日志。
local S = {
    t = 0.0,
    acc = 0.0,
    hps = 0.0,
    modified = false,
    my_player = nil,
    logged_my_player = false,
}

local BASE_HPS = 10.0        -- 原版闪亮石静止起步就是 10 HP/s
local COUNT_PER_HP = 120.0   -- 原版：120 点 lifeRegenCount = 1 点血

-- 档位预设（和光影 Mod 的「画质档位」同一套做法：启动器把 CHOICE 渲染成按钮组）。
-- 只有档位选「自定义」时才用下面两项 INTEGER 的数值。
local PRESETS = {
    gentle = { max_regen = 100, ramp_seconds = 10 },
    standard = { max_regen = 4000, ramp_seconds = 20 },
    ultimate = { max_regen = 4000, ramp_seconds = 0 },
}

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
        mod.warn("聚变石：没读到 config.json，全部走默认值（" .. tostring(err) .. "）")
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
    settings.max_regen = clamp_int(find_num("max_regen"), 40, 4000, 4000)
    settings.ramp_seconds = clamp_int(find_num("ramp_seconds"), 0, 120, 20)

    -- 档位：先读字符串，命中预设就覆盖上面两项；「自定义」或读不到才用两项的数值
    local preset = raw:match('"preset"%s*:%s*"([%w_]+)"')
    if preset == nil or PRESETS[preset] == nil then
        if preset == nil then
            settings.preset = "standard"
        else
            settings.preset = "custom"
        end
    else
        settings.preset = preset
        settings.max_regen = PRESETS[preset].max_regen
        settings.ramp_seconds = PRESETS[preset].ramp_seconds
    end
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

-- 只对本地玩家生效；拿不到 whoAmI / Main.myPlayer 时退回「所有玩家」（单机里就是一回事）
local function is_local_player(instance)
    if F.whoAmI == nil or F.myPlayer == nil then
        return true
    end
    local who = P.get_field_value(F.whoAmI, instance, "int32")
    if who == nil then
        return true
    end
    if S.my_player == nil then
        local my = P.get_field_value(F.myPlayer, nil, "int32")   -- 静态字段：instance 传 nil
        if my == nil then
            return true
        end
        S.my_player = my
        if not S.logged_my_player then
            S.logged_my_player = true
            mod.info("聚变石：本地玩家 whoAmI=" .. tostring(my))
        end
    end
    return who == S.my_player
end

local function reset_ramp()
    S.t = 0.0
    S.acc = 0.0
    S.hps = 0.0
end

-- bool 字段有的实现直接给 true/false，有的给 1/0，两种都认
local function is_true(v)
    return v == true or v == 1
end

local function on_prefix(instance, args)
    if not T.ready or not settings.enabled then return false end
    if instance == nil then return false end
    if not is_local_player(instance) then return false end

    T.calls = T.calls + 1

    local ok, err = pcall(function()
        local has_stone = P.get_field_value(F.shinyStone, instance, "bool")
        if not is_true(has_stone) then
            reset_ramp()          -- 没戴闪亮石：和原版一样，下次戴上重新爬
            return
        end

        local dead = false
        if F.dead ~= nil then
            dead = is_true(P.get_field_value(F.dead, instance, "bool"))
        end
        if dead then
            reset_ramp()          -- 死了就重来（复活后重新起步）
            return
        end

        -- 关键一步：跳过原版「静止才加速、一动就清零」的那一整段分支
        P.set_field_value(F.shinyStone, instance, false, "bool")
        S.modified = true

        S.t = S.t + 1.0 / 60.0

        local cap = settings.max_regen
        local ramp = settings.ramp_seconds
        local hps
        if ramp <= 0 then
            hps = cap
        else
            local k = S.t / ramp
            if k > 1.0 then k = 1.0 end
            if k < 0.0 then k = 0.0 end
            hps = BASE_HPS + (cap - BASE_HPS) * k
        end
        S.hps = hps

        -- 每帧要回 hps/60 点血，lifeRegenCount 里 1 点血 = 120 点 → 每帧注入 hps*2 点
        S.acc = S.acc + hps * (COUNT_PER_HP / 60.0)
        local add = math.floor(S.acc)
        if add <= 0 then
            return
        end
        S.acc = S.acc - add

        local cnt = P.get_field_value(F.lifeRegenCount, instance, "int32")
        if cnt == nil then
            return
        end
        if cnt < 0 then
            cnt = 0          -- 中毒/着火留下的负点数先归零，不然会被白扣掉
        end
        P.set_field_value(F.lifeRegenCount, instance, cnt + add, "int32")
    end)

    if not ok then
        T.ready = false
        T.last_error = tostring(err)
        mod.error("聚变石：再生注入出错，已自动停用 hook：" .. tostring(err))
    end

    return false   -- 永远不跳过原方法，后半段的回血循环还要它来跑
end

local function on_postfix(instance, args, result)
    if not S.modified then return end
    S.modified = false
    pcall(P.set_field_value, F.shinyStone, instance, true, "bool")
end

function setup()
    read_settings()

    if not settings.enabled then
        mod.info("聚变石：启动器里已关闭，不安装 hook，保持原版闪亮石")
        return
    end

    local player = P.get_type("Terraria", "Player")
    local main_t = P.get_type("Terraria", "Main")
    if player == nil then
        T.last_error = "找不到 Terraria.Player"
        mod.error("聚变石：" .. T.last_error .. "，游戏版本可能不匹配")
        return
    end

    F.shinyStone = field_of(player, "shinyStone")
    F.lifeRegenCount = field_of(player, "lifeRegenCount")
    F.dead = field_of(player, "dead")
    F.whoAmI = field_of(player, "whoAmI")
    if F.whoAmI == nil then
        -- whoAmI 是基类 Entity 的字段（Entity.cs:8 `public int whoAmI;`），Player 自己没声明，
        -- 取字段的实现若不会往上找父类，就得从 Entity 上取；offset 一样，照样能用 Player 实例读。
        local entity = P.get_type("Terraria", "Entity")
        if entity ~= nil then
            F.whoAmI = field_of(entity, "whoAmI")
        end
    end
    if main_t ~= nil then
        F.myPlayer = field_of(main_t, "myPlayer")   -- Main.cs:1807 `public static int myPlayer;`
    end

    if F.shinyStone == nil or F.lifeRegenCount == nil then
        T.last_error = "取不到 Player.shinyStone / lifeRegenCount"
        mod.error("聚变石：" .. T.last_error .. "，放弃安装")
        return
    end
    if F.whoAmI == nil or F.myPlayer == nil then
        mod.warn("聚变石：读不到 whoAmI / Main.myPlayer，将按「所有玩家」处理（单机无影响）")
    end

    local method = P.get_method(player, "UpdateLifeRegen", 0)
    if method == nil or not P.is_valid(method) then
        T.last_error = "取不到 Player.UpdateLifeRegen()"
        mod.error("聚变石：" .. T.last_error .. "，放弃安装")
        return
    end

    T.ready = true
    local ok, hook = pcall(function()
        return P.install_hook(method, { prefix = on_prefix, postfix = on_postfix })
    end)
    if not ok or hook == nil then
        T.ready = false
        T.last_error = "装 hook 失败"
        mod.error("聚变石：装 hook 失败：" .. tostring(hook))
        return
    end
    T.hook = hook

    mod.info(string.format(
        "聚变石就绪（档位 %s）：再生 %d → %d HP/s 用 %d 秒爬满，移动/受伤/用物品/流血都不再重置",
        tostring(settings.preset), math.floor(BASE_HPS), settings.max_regen, settings.ramp_seconds))
end

function mod.cleanup()
    T.ready = false
    if T.hook ~= nil then
        pcall(function() T.hook:remove() end)
        T.hook = nil
    end
    mod.info("聚变石：已卸载，恢复原版闪亮石")
end

-- 启动入口：加载器会拿 todo_list 里的字符串去 _G 找同名函数，所以这里必须挂全局。
local booted = false
local function boot()
    if booted then
        return
    end
    booted = true
    setup()
end

_G.fusionstone_boot = boot
todo_list = { "fusionstone_boot" }

function mod.init()
    boot()
end
