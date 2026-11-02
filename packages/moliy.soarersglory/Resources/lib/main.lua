-- 翱翔者的荣耀 / Soarer's Glory
-- 作者：Moliy    版本：1.0.0
-- 加强原版翱翔之证（Soaring Insignia，物品 ID 4989，玩家字段 empressBrooch）：
--   1. 移动速度加成、跳跃速度加成、水平加速度三项各做一个 1–50 倍的独立倍率（默认 1 = 原版）；
--   2. 「每帧把翅膀飞行时间回满」和「每帧把火箭靴燃料回满」这两个无限效果各做成一个开关。
-- 需要 LuaLoader >= 1.6.0（api_version 1，纯 Lua，无原生模块）。
-- 启动器设置由 LuaLoader 直接读 Info.json 的 settings 渲染（和光影 Mod 的面板同一套控件）。
--
-- 原理（全部取自 1.4.5.8 反编译源码 Source-1.4.5.8/PC/Terraria/Player.cs；行号是这一份的行号）：
--   装备扫描：Player.cs:14876-14880  ApplyEquipFunctional() 里
--       if (currentItem.type == 4989) { empressBrooch = true; moveSpeed += 0.075f; }
--   跳跃：    Player.cs:19719-19722  UpdateJumpHeight() 里 if (empressBrooch) jumpSpeedBoost += 1.8f;
--             末尾 Player.cs:19743 jumpSpeed += jumpSpeedBoost;
--   无限飞行：Player.cs:22417-22420  WingMovement() 末尾 if (empressBrooch && wingTime != 0f) wingTime = wingTimeMax;
--   加速度：  Player.cs:26698-26701  Update(int) 里 if (empressBrooch) runAcceleration *= 1.75f;
--   无限火箭：Player.cs:27063-27066  Update(int) 里 if (empressBrooch) rocketTime = rocketTimeMax;
--
-- 帧内时序（同一帧里这几个钩子的先后顺序，是本模组的全部依据）：
--   Player.cs:24556-24563  Update 开头先把 runAcceleration 重置成 0.08、maxRunSpeed 重置成 originalRunSpeed
--   Player.cs:25686        Update 里调 ResetEffects()（装备扫描 ApplyEquipFunctional 在这里面）
--   Player.cs:26203-26204  Update 里 runAcceleration *= moveSpeed; maxRunSpeed *= moveSpeed;
--   Player.cs:26209        Update 里调 UpdateJumpHeight()
--   Player.cs:26698-26701  Update 里 brooch 的 runAcceleration *= 1.75f
--   Player.cs:27017        Update 里调 WingMovement()
--   Player.cs:27063-27066  Update 里 brooch 的 rocketTime = rocketTimeMax
-- 所以：ResetEffects 的 postfix 改 moveSpeed 能吃到 26203 的乘法；UpdateJumpHeight 的
--   prefix 早于 19743 的 jumpSpeed 结算、postfix 又早于 26698 的 ×1.75 —— 正好能把倍率精确塞进去。
--
-- 三个倍率的算法（N 为倍率，N = 1 时与原版逐帧一致）：
--   移动速度：ResetEffects postfix 里 moveSpeed += 0.075 * (N - 1)
--   跳跃速度：UpdateJumpHeight prefix 里 jumpSpeedBoost += 1.8 * (N - 1)
--   水平加速度：UpdateJumpHeight postfix 里 runAcceleration *= (1 + 0.75N) / 1.75
--     —— 原版接着在 26698 再乘 1.75，合起来正好是 1 + 0.75N；N = 1 时 (1+0.75)/1.75 = 1，等于没动。
--
-- 两个开关的做法（关掉 = 让 brooch 那几行 if 不成立）：
--   无限飞行关：WingMovement 的 prefix 把 empressBrooch 临时置 false，postfix 再还原 ——
--     这个方法里只有 22417 一处读 brooch，所以只影响「回满翼时间」这一件事。
--   无限火箭关：Update 的 prefix 就把 empressBrooch 置 false，直到 Update 的 postfix 才还原 ——
--     因为 27063 那行藏在 Update 内部，Lua 钩不到方法中间，只能整帧压住。
--     压住期间原版的三处加成（跳跃 +1.8、加速度 ×1.75、翼时间回满）也一起失效，
--     所以由本模组按 N 自己补上全额，保证开关只影响火箭靴。
--
-- 只处理本地玩家（whoAmI == Main.myPlayer）：别的玩家由服务器同步，客户端硬改会错位。

local P = mod.patch

local settings = {
    enabled = true,
    infinite_flight = true,
    infinite_rocket = true,
    move_mult = 1,
    jump_mult = 1,
    accel_mult = 1,
}

local T = {
    ready = false,
    hooks = {},
    last_error = "",
    calls = 0,
}

local F = {}

-- 单帧状态：S.active 只在「本地玩家的 Player.Update 正在跑」这段里为真，
-- 同一帧里 ResetEffects / UpdateJumpHeight / WingMovement 的钩子靠它判断该不该动手。
local S = {
    active = false,
    suppress = false,        -- 整帧压住 brooch（火箭靴无限被关掉时）
    wing_suppressed = false, -- 只在 WingMovement 里压住 brooch（无限飞行被关掉时）
    my_player = nil,
    logged_my_player = false,
}

-- 原版翱翔之证给的三个数值
local BASE_MOVE = 0.075
local BASE_JUMP = 1.8
local BASE_ACCEL = 1.75

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
        mod.warn("翱翔者的荣耀：没读到 config.json，全部走默认值（" .. tostring(err) .. "）")
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
    b = find_bool("infinite_flight")
    if b ~= nil then settings.infinite_flight = b end
    b = find_bool("infinite_rocket")
    if b ~= nil then settings.infinite_rocket = b end

    settings.move_mult = clamp_int(find_num("move_mult"), 1, 50, 1)
    settings.jump_mult = clamp_int(find_num("jump_mult"), 1, 50, 1)
    settings.accel_mult = clamp_int(find_num("accel_mult"), 1, 50, 1)
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

-- bool 字段有的实现直接给 true/false，有的给 1/0，两种都认
local function is_true(v)
    return v == true or v == 1
end

local function my_player_index()
    if S.my_player == nil and F.myPlayer ~= nil then
        local ok, v = pcall(function()
            return P.get_field_value(F.myPlayer, nil, "int32")   -- 静态字段：instance 传 nil
        end)
        if ok then
            S.my_player = v
            if not S.logged_my_player and v ~= nil then
                S.logged_my_player = true
                mod.info("翱翔者的荣耀：本地玩家 whoAmI=" .. tostring(v))
            end
        end
    end
    return S.my_player
end

local function fail(err)
    T.ready = false
    T.last_error = tostring(err)
    mod.error("翱翔者的荣耀：hook 出错，已自动停用：" .. tostring(err))
end

local function get_float(field, instance)
    if field == nil then return nil end
    return P.get_field_value(field, instance, "float")
end

local function set_float(field, instance, v)
    if field == nil then return end
    P.set_field_value(field, instance, v, "float")
end

-- ---------------------------------------------------------------- 钩子

-- Player.Update(int i)：整帧的边界，负责压住/还原 brooch
local function on_update_prefix(instance, args)
    if not T.ready or not settings.enabled then return false end
    if instance == nil then return false end

    -- 先用参数 i 挡掉别的玩家（256 个 Player 每帧都会跑 Update，别白读字段）
    local i = nil
    if type(args) == "table" then i = args[1] end
    local my = my_player_index()
    if my ~= nil and i ~= nil and i ~= my then
        return false
    end

    local ok, err = pcall(function()
        if not is_true(P.get_field_value(F.empressBrooch, instance, "bool")) then
            return
        end
        T.calls = T.calls + 1
        S.active = true
        S.suppress = (not settings.infinite_rocket)
        if S.suppress then
            -- 整帧压住：这样 27063 的 rocketTime = rocketTimeMax 就不会执行。
            -- 注意 ResetEffects 里的装备扫描会把它重新置 true，所以下面 ResetEffects 的 postfix 还要再压一次。
            P.set_field_value(F.empressBrooch, instance, false, "bool")
        end
    end)
    if not ok then fail(err) end
    return false   -- 永远不跳过原方法
end

local function on_update_postfix(instance, args, result)
    if not S.active then return end
    S.active = false
    S.suppress = false
    S.wing_suppressed = false
    pcall(P.set_field_value, F.empressBrooch, instance, true, "bool")
end

-- Player.ResetEffects()：装备扫描在这里面跑完，正好补移动速度、“压住”要被压的 brooch
local function on_reset_postfix(instance, args, result)
    if not S.active then return end
    local ok, err = pcall(function()
        if S.suppress then
            P.set_field_value(F.empressBrooch, instance, false, "bool")
        end
        local n = settings.move_mult
        if n > 1 and F.moveSpeed ~= nil then
            local cur = get_float(F.moveSpeed, instance)
            if cur ~= nil then
                set_float(F.moveSpeed, instance, cur + BASE_MOVE * (n - 1))
            end
        end
    end)
    if not ok then fail(err) end
end

-- Player.UpdateJumpHeight()：prefix 补跳跃速度，postfix 补水平加速度
local function on_jump_prefix(instance, args)
    if not S.active then return false end
    local ok, err = pcall(function()
        local n = settings.jump_mult
        local extra = BASE_JUMP * (n - 1)
        if S.suppress then
            -- 整帧压住时原版那行 `jumpSpeedBoost += 1.8` 也不会执行，所以补全额
            extra = extra + BASE_JUMP
        end
        if extra == 0 or F.jumpSpeedBoost == nil then
            return
        end
        local cur = get_float(F.jumpSpeedBoost, instance) or 0
        set_float(F.jumpSpeedBoost, instance, cur + extra)
    end)
    if not ok then fail(err) end
    return false
end

local function on_jump_postfix(instance, args, result)
    if not S.active then return end
    local ok, err = pcall(function()
        local n = settings.accel_mult
        local total = 1 + (BASE_ACCEL - 1) * n          -- 想要的合计倍率：1 + 0.75N
        local mult
        if S.suppress then
            mult = total                                -- 原版 ×1.75 已被压掉，自己补全额
        else
            mult = total / BASE_ACCEL                   -- 原版随后还会 ×1.75
        end
        if math.abs(mult - 1) < 0.000001 then
            return
        end
        if F.runAcceleration == nil then
            return
        end
        local cur = get_float(F.runAcceleration, instance)
        if cur == nil then
            return
        end
        set_float(F.runAcceleration, instance, cur * mult)
    end)
    if not ok then fail(err) end
end

-- Player.WingMovement()：无限飞行开关；整帧被压住时由这里把翼时间补满
local function on_wing_prefix(instance, args)
    if not S.active then return false end
    if not settings.infinite_flight and not S.suppress then
        local ok, err = pcall(function()
            -- 这个方法里只有 22417 一处读 brooch，压住 = 不再回满翼时间
            P.set_field_value(F.empressBrooch, instance, false, "bool")
            S.wing_suppressed = true
        end)
        if not ok then fail(err) end
    end
    return false
end

local function on_wing_postfix(instance, args, result)
    if not S.active then return end
    local ok, err = pcall(function()
        if S.wing_suppressed then
            S.wing_suppressed = false
            P.set_field_value(F.empressBrooch, instance, true, "bool")
        end
        if S.suppress and settings.infinite_flight then
            -- 整帧压住时原版不会回满翼时间，这里照着 22417 的逻辑自己补上
            local wt = get_float(F.wingTime, instance)
            if wt ~= nil and wt ~= 0 then
                local mx = P.get_field_value(F.wingTimeMax, instance, "int32")
                if mx ~= nil then
                    set_float(F.wingTime, instance, mx)
                end
            end
        end
    end)
    if not ok then fail(err) end
end

-- ---------------------------------------------------------------- 安装

local function add_hook(method, def, label)
    local ok, hook = pcall(function()
        return P.install_hook(method, def)
    end)
    if not ok or hook == nil then
        mod.error("翱翔者的荣耀：给 " .. label .. " 装 hook 失败：" .. tostring(hook))
        return false
    end
    T.hooks[#T.hooks + 1] = hook
    return true
end

local function get_method_of(t, name)
    local ok, m = pcall(function()
        return P.get_method(t, name, 0)
    end)
    if not ok or m == nil or not P.is_valid(m) then
        return nil
    end
    return m
end

function setup()
    read_settings()

    if not settings.enabled then
        mod.info("翱翔者的荣耀：启动器里已关闭，不安装 hook，保持原版翱翔之证")
        return
    end

    local player = P.get_type("Terraria", "Player")
    local main_t = P.get_type("Terraria", "Main")
    if player == nil then
        T.last_error = "找不到 Terraria.Player"
        mod.error("翱翔者的荣耀：" .. T.last_error .. "，游戏版本可能不匹配")
        return
    end

    F.empressBrooch = field_of(player, "empressBrooch")
    F.jumpSpeedBoost = field_of(player, "jumpSpeedBoost")
    F.runAcceleration = field_of(player, "runAcceleration")
    F.moveSpeed = field_of(player, "moveSpeed")
    F.wingTime = field_of(player, "wingTime")
    F.wingTimeMax = field_of(player, "wingTimeMax")
    F.whoAmI = field_of(player, "whoAmI")
    if F.whoAmI == nil then
        -- whoAmI 是基类 Entity 的字段（Entity.cs:8 `public int whoAmI;`），Player 自己没声明
        local entity = P.get_type("Terraria", "Entity")
        if entity ~= nil then
            F.whoAmI = field_of(entity, "whoAmI")
        end
    end
    if main_t ~= nil then
        F.myPlayer = field_of(main_t, "myPlayer")   -- Main.cs:1807 `public static int myPlayer;`
    end

    if F.empressBrooch == nil then
        T.last_error = "取不到 Player.empressBrooch"
        mod.error("翱翔者的荣耀：" .. T.last_error .. "，放弃安装")
        return
    end
    if F.jumpSpeedBoost == nil or F.runAcceleration == nil or F.moveSpeed == nil then
        T.last_error = "取不到 jumpSpeedBoost / runAcceleration / moveSpeed"
        mod.error("翱翔者的荣耀：" .. T.last_error .. "，放弃安装")
        return
    end
    if F.wingTime == nil or F.wingTimeMax == nil then
        mod.warn("翱翔者的荣耀：取不到 wingTime / wingTimeMax，关掉无限飞行时可能不彻底（其它功能不受影响）")
    end
    if F.whoAmI == nil or F.myPlayer == nil then
        mod.warn("翱翔者的荣耀：读不到 whoAmI / Main.myPlayer，将按「所有玩家」处理（单机无影响）")
    end

    local m_update = get_method_of(player, "Update")
    local m_reset = get_method_of(player, "ResetEffects")
    local m_jump = get_method_of(player, "UpdateJumpHeight")
    local m_wing = get_method_of(player, "WingMovement")
    if m_update == nil or m_reset == nil or m_jump == nil or m_wing == nil then
        T.last_error = "取不到 Player.Update / ResetEffects / UpdateJumpHeight / WingMovement"
        mod.error("翱翔者的荣耀：" .. T.last_error .. "，放弃安装")
        return
    end

    T.ready = true
    if not add_hook(m_update, { prefix = on_update_prefix, postfix = on_update_postfix }, "Player.Update") then
        T.ready = false
        return
    end
    if not add_hook(m_reset, { postfix = on_reset_postfix }, "Player.ResetEffects") then
        T.ready = false
        return
    end
    if not add_hook(m_jump, { prefix = on_jump_prefix, postfix = on_jump_postfix }, "Player.UpdateJumpHeight") then
        T.ready = false
        return
    end
    if not add_hook(m_wing, { prefix = on_wing_prefix, postfix = on_wing_postfix }, "Player.WingMovement") then
        T.ready = false
        return
    end

    mod.info(string.format(
        "翱翔者的荣耀就绪：移动 ×%d、跳跃 ×%d、水平加速度 ×%d，无限飞行 %s、火箭靴无限 %s",
        settings.move_mult, settings.jump_mult, settings.accel_mult,
        tostring(settings.infinite_flight), tostring(settings.infinite_rocket)))
end

function mod.cleanup()
    T.ready = false
    S.active = false
    S.suppress = false
    S.wing_suppressed = false
    for i = #T.hooks, 1, -1 do
        local hook = T.hooks[i]
        if hook ~= nil then
            pcall(function() hook:remove() end)
        end
        T.hooks[i] = nil
    end
    mod.info("翱翔者的荣耀：已卸载，恢复原版翱翔之证")
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

_G.soarersglory_boot = boot
todo_list = { "soarersglory_boot" }

function mod.init()
    boot()
end
