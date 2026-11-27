-- bag_effect.lua
-- 多功能大背包 —— 四套随身被动效果
--   ① 随身制作站：容器里有制作站 = 身边摆着（写 Player.adjTile）
--   ② 随身增益站：容器里有增益家具 = 站它旁边（写 buffType/buffTime，篝火系另写 SceneMetrics 标记）
--   ③ 药水袋    ：同种药水 ≥10 瓶 → 对应 buff 常驻
--   ④ 旗帜袋    ：容器里有敌怪旗 → 旗帜增伤生效（写 SceneMetrics.NPCBannerBuff）
--
-- 参考实现：
--   完全之龙 v9.1.0 main.lua:8315（随身制作站）、:11700（增益家具 / 药水常驻）
--   类旗帜盒 v1.14.6 main.lua:1171（SceneMetrics.Reset postfix 写 NPCBannerBuff）
--   类药水袋 v1.2（buffType 直写，不碰 buffNoTimeDisplay 全局数组）
--
-- 三条硬约束（都是踩过的坑）：
--   1) 不碰 Main.buffNoTimeDisplay / BuffID.Sets.TimeLeftDoesNotDecrease —— 那两个是全局静态数组，
--      一改会把玩家自己喝的同类药水也变成永久，污染所有实例。
--   2) PE 版没有 Player.SetAdjTile、也没有 Recipe.TileCountsAs，所以等效站映射要自己补。
--   3) 写 bool 数组的元素类型内核只认一种，首次成功后锁定（bool / uint8 / int8 三种都试）。

-- patch 在 quickapi 里是局部变量，没有挂到 _G，必须从 mod.patch 取
local P = (mod and mod.patch) or _G.patch
if not P then
    pcall(mod.warn, "[随身效果] mod.patch 缺失，效果全部跳过")
    return {}
end
local E = {}

local DATA = nil
local ready = false
local H = {}

-- 定稿版：过程日志全部静默，不产生任何输出
local function log(_) end
local function warn(_) end

-- ============================ 反射小工具 ============================

local function rd(f, o, ty)
    if not f then return nil end
    local ok, v = pcall(P.get_field_value, f, o, ty)
    if ok then return v end
    return nil
end

local function arr_at(a, i, ty)
    if not a then return nil end
    local ok, v = pcall(P.array_at, a, i, ty)
    if ok then return v end
    return nil
end

local function arr_len(a)
    if not a then return 0 end
    local ok, n = pcall(P.array_length, a)
    if ok and type(n) == "number" then return n end
    return 0
end

local function arr_set(a, i, v, ty)
    if not a then return false end
    local ok, r = pcall(P.array_set, a, i, v, ty)
    return ok and r ~= false
end

-- bool 数组写元素：内核可能只认某一种类型，第一次成功后锁定
local BOOL_TYPE = nil
local function set_bool(arr, idx, val)
    local cands = BOOL_TYPE and { BOOL_TYPE } or { "bool", "uint8", "int8" }
    for i = 1, #cands do
        local ty = cands[i]
        local ok, r
        if ty == "bool" then
            ok, r = pcall(P.array_set, arr, idx, val, ty)
        else
            ok, r = pcall(P.array_set, arr, idx, val and 1 or 0, ty)
        end
        if ok and r ~= false then
            BOOL_TYPE = ty
            return true
        end
    end
    return false
end

local function set_bool_field(f, o, val)
    if not f then return false end
    local ok = pcall(P.set_field_value, f, o, val, "bool")
    if ok then return true end
    local ok2 = pcall(P.set_field_value, f, o, val and 1 or 0, "uint8")
    return ok2
end

-- ============================ 反射句柄绑定 ============================

local function bind()
    local okp, Tp = pcall(P.get_type, "Terraria", "Player")
    local oki, Ti = pcall(P.get_type, "Terraria", "Item")
    if not (okp and Tp) then return false end

    H.Tp        = Tp
    H.Ti        = Ti
    H.f_adjtile = P.get_field(Tp, "adjTile")
    H.f_alch    = P.get_field(Tp, "alchemyTable")
    H.f_water   = P.get_field(Tp, "adjWaterSource")
    H.f_pbtype  = P.get_field(Tp, "buffType")
    H.f_pbtime  = P.get_field(Tp, "buffTime")
    H.f_liferegen = P.get_field(Tp, "lifeRegen")
    H.f_ctile   = Ti and P.get_field(Ti, "createTile")

    -- SceneMetrics（静态属性），供旗帜袋与篝火/心灯用
    local okm, Tm = pcall(P.get_type, "Terraria", "Main")
    if okm and Tm then
        H.Tm = Tm
        local prop = P.get_property and P.get_property(Tm, "SceneMetrics")
        if prop and P.property_get_method then
            H.get_sm = P.property_get_method(prop)
        end
        if not H.get_sm then H.get_sm = P.get_method(Tm, "get_SceneMetrics", 0) end
    end

    -- buff 栏绘制入口
    -- 【关键】手机版（Terraria Android）不是 Main.DrawInterface_Resources_Buffs 画的，
    -- 而是 TERRARIA.GUIBUFFS.Draw() —— 手机版有独立的一套 GUI 类
    -- （GUIHearts / GUIMana / GUIBuffs / GUIHotbar ...），参考「UI隐藏 v1.5.2」实测生效的写法。
    -- 之前挂 Main.DrawInterface_Resources_Buffs 在本机上等于挂空，所以开关切了也没反应。
    H.m_drawbuffs = nil
    do
        -- GUIBuffs 在【全局命名空间】：PE 源码 GUIBuffs.cs 里是 "public class GUIBuffs"，
        -- 没有 namespace 声明（其它 GUI 类如 GUIHearts 也是同一套）。所以要用 "" 去取。
        local Tb = nil
        for _, ns in ipairs({ "", "Terraria", "Terraria.GameContent" }) do
            local okb, t = pcall(P.get_type, ns, "GUIBuffs")
            if okb and t then Tb = t break end
        end
        if Tb then
            -- Draw() 是实例方法（PE 源码：public void Draw()）
            H.m_drawbuffs = P.get_method(Tb, "Draw", 0) or P.get_method(Tb, "Draw")
        end
        if not H.m_drawbuffs and Tm then
            -- 退路：PC 版入口（手机上大概率拿不到，留着不亏）
            H.m_drawbuffs = P.get_method(Tm, "DrawInterface_Resources_Buffs", 0)
        end
    end

    local oks, Ts = pcall(P.get_type, "Terraria", "SceneMetrics")
    if oks and Ts then
        H.Ts        = Ts
        H.f_banner  = P.get_field(Ts, "NPCBannerBuff")
        H.f_hasban  = P.get_field(Ts, "hasBanner")
        H.m_smreset = P.get_method(Ts, "Reset", 0)
        -- HasCampfire / HasHeartLantern 是 bool 属性，setter 用来骗原版 UpdateLifeRegen
        local function getter(n)
            local p = P.get_property and P.get_property(Ts, n)
            if p and P.property_get_method then
                local m = P.property_get_method(p)
                if m then return m end
            end
            return P.get_method(Ts, "get_" .. n, 0)
        end
        local function setter(n)
            local p = P.get_property and P.get_property(Ts, n)
            if p and P.property_set_method then
                local m = P.property_set_method(p)
                if m then return m end
            end
            return P.get_method(Ts, "set_" .. n, 1)
        end
        -- 篝火 / 心形灯笼：HasCampfire / HasHeartLantern 是自动属性
        --   （PC SceneMetrics.cs:218/222 `public bool HasCampfire { get; private set; }`），
        --   背后有编译器生成的字段 <HasCampfire>k__BackingField。
        --   直接写这个字段 = 不调用任何方法，又让原版 UpdateLifeRegen 自己按 +1/+2 算，
        --   玩家真站在篝火旁时原版也只算一次 → 天然不重复。
        --   拿不到就退回"事后补数值"（有双倍风险，见 life_regen_post 注释）。
        local function backing_field(T, name)
            if not T then return nil end
            local f = P.get_field(T, "<" .. name .. ">k__BackingField")
            if f then return f end
            -- 少数内核会把尖括号字段名做转义，再试几种写法
            f = P.get_field(T, "<" .. name .. ">k__BackingField")
            return f
        end
        H.f_camp_bf  = backing_field(Ts, "HasCampfire")
        H.f_heart_bf = backing_field(Ts, "HasHeartLantern")

        -- 和平蜡烛 / 水蜡烛 / 暗影蜡烛：这三个不是"给 buff"，而是 SceneMetrics 的 Zone 标志
        --   Player.cs:25714-25722 读 ZoneWaterCandle/ZonePeaceCandle/ZoneShadowCandle 后自己 AddBuff
        --   SceneMetrics.cs:713-715 在 CalculateZones 里按计数重算（会清成 false），
        --   所以必须等 CalculateZones 跑完之后再写 —— 挂它的 postfix。
        H.f_zonewater  = P.get_field(Ts, "ZoneWaterCandle")
        H.f_zonepeace  = P.get_field(Ts, "ZonePeaceCandle")
        H.f_zoneshadow = P.get_field(Ts, "ZoneShadowCandle")
        H.m_sm_scan    = P.get_method(Ts, "Scan", 1)
        H.m_calczones  = P.get_method(Ts, "CalculateZones", 0)
        if not H.m_calczones then H.m_calczones = P.get_method(Ts, "AddPlayerEffects", 1) end
        H.m_hascamp  = getter("HasCampfire")
        H.m_sethamp  = setter("HasCampfire")
        H.m_hashart  = getter("HasHeartLantern")
        H.m_sethart  = setter("HasHeartLantern")
    end

    log(("绑定结果 adjTile=%s buffType=%s createTile=%s NPCBannerBuff=%s SceneMetrics=%s 篝火字段=%s 心灯字段=%s"):format(
        tostring(H.f_adjtile ~= nil), tostring(H.f_pbtype ~= nil), tostring(H.f_ctile ~= nil),
        tostring(H.f_banner ~= nil), tostring(H.get_sm ~= nil),
        tostring(H.f_camp_bf ~= nil), tostring(H.f_heart_bf ~= nil)))
    return H.f_pbtype ~= nil or H.f_adjtile ~= nil
end

-- ============================ 容器遍历工具 ============================

-- 遍历某个分区池里所有「有东西」的槽，回调 (id, stack)
local function each_slot(section, fn)
    if not DATA or not DATA.pools then return end
    local pool = DATA.pools[section]
    if not pool then return end
    local cap = DATA.section_cap(section)
    for i = 1, cap do
        local s = pool[i]
        if s and s.id and s.id > 0 and (s.stack or 0) > 0 then
            fn(s.id, s.stack)
        end
    end
end

-- ============================ ① 随身制作站 ============================
-- 写 Player.adjTile[tileType]。PE 没有 SetAdjTile，等效站自己补。

-- 历史遗留：第一版用它做第二层过滤，导致大量制作站失效，现已不再参与判定。
-- 保留这份清单仅作查阅（是我们容器里可能出现的 tile 类型）。
local CRAFT_ALLOW_INFO = {
    [16]  = true,   -- 铁砧 / 铅砧
    [17]  = true,   -- 熔炉
    [18]  = true,   -- 工作台
    [26]  = true,   -- 恶魔祭坛 / 猩红祭坛
    [77]  = true,   -- 地狱熔炉
    [86]  = true,   -- 织布机
    [94]  = true,   -- 酒桶
    [96]  = true,   -- 烹饪锅 / 大锅
    [106] = true,   -- 锯木机
    [114] = true,   -- 工匠作坊
    [125] = true,   -- 水晶球
    [133] = true,   -- 精金熔炉 / 钛金熔炉
    [134] = true,   -- 秘银砧 / 山铜砧
    [172] = true,   -- 水槽
    [243] = true,   -- 灌注站
    [247] = true,   -- 自动锤炼机
    [283] = true,   -- 重型工作台
    [355] = true,   -- 炼药桌
    [412] = true,   -- 远古操纵机
    [699] = true,   -- 炼金瓶
    [215] = true,   -- 骨头焊机（工作台的等效目标）
}
-- 等效站：站在左边旁边，也算右边的站可用（抄 PC Recipe.SetupTileInheritance）
local CRAFT_EQ = {
    [96]  = { 215 }, [17] = { 215 }, [302] = { 17 },
    [77]  = { 17 },  [133] = { 77 }, [134] = { 16 },
    [355] = { 13 },  [699] = { 13 }, [304] = { 86 },
    [412] = { 17 },
}

local craft_tile_of = {}    -- item id -> tileType（永久缓存，避免反复造实例）
local craft_set = {}        -- tileType -> true（本轮命中）
local craft_n = 0
local craft_scan_wait = 0

local function craft_tile(id)
    local c = craft_tile_of[id]
    if c ~= nil then return c end
    local ct = 0
    local inst = DATA and DATA.make_item and DATA.make_item(id)
    if inst then
        local v = rd(H.f_ctile, inst, "int32")
        if type(v) == "number" then ct = v end
    end
    craft_tile_of[id] = ct
    return ct
end

local function craft_rescan()
    for k in pairs(craft_set) do craft_set[k] = nil end
    craft_n = 0
    each_slot("craft", function(id)
        local ct = craft_tile(id)
        -- 不再做第二层 tile 白名单：能进 craft 分区的物品本来就由数据层白名单把关，
        -- 这里再筛一遍只会把染缸/书架/茶壶/搅拌机/玻璃窑/蜂蜜分配机/制冰机/
        -- 生命木织机/天磨/固化机/祭坛 这些全滤掉（第一版就是这么漏的）。
        if ct and ct > 0 then
            if not craft_set[ct] then craft_set[ct] = true; craft_n = craft_n + 1 end
        end
    end)
    -- 展开等效站（可能要跳几级，用队列走到不动为止）
    local queue, qn = {}, 0
    for t in pairs(craft_set) do qn = qn + 1; queue[qn] = t end
    local i = 1
    while i <= qn do
        local t = queue[i]; i = i + 1
        local list = CRAFT_EQ[t]
        if list then
            for j = 1, #list do
                local e = list[j]
                if not craft_set[e] then
                    craft_set[e] = true; qn = qn + 1; queue[qn] = e; craft_n = craft_n + 1
                end
            end
        end
    end
end

local craft_warned = false
local function craft_apply(player)
    if not player or craft_n <= 0 then return end
    local arr = rd(H.f_adjtile, player, "object")
    if not arr then return end
    local n = arr_len(arr)
    if n <= 0 then return end
    local bad = 0
    for t in pairs(craft_set) do
        if t > 0 and t < n then
            if not set_bool(arr, t, true) then bad = bad + 1 end
        end
    end
    if bad > 0 and not craft_warned then
        craft_warned = true
        warn("adjTile 写入失败 " .. bad .. " 项")
    end
    -- 炼药桌 / 炼金瓶：单独字段，不写它做不了药水（材料 1/3 不消耗也靠它）
    if craft_set[355] or craft_set[699] then
        set_bool_field(H.f_alch, player, true)
    end
    -- 水槽：原版靠 CountsAsWaterForCrafting 置 adjWaterSource，我们直接写
    if craft_set[172] then
        set_bool_field(H.f_water, player, true)
    end
end

-- ============================ ③ 药水袋 / ② 增益站：给 buff ============================

local BUFF_TIME = 180       -- 3 秒；每 45 帧续一次（原来是 1 秒 / 每帧续，反射调用量是现在的 3 倍）
local BUFF_EVERY = 45
local RESCAN_EVERY = 30      -- 0.5 秒扫一轮容器（完全之龙 af_tick 的 g_scan < 30 同频）
local BANNER_SCAN_EVERY = 4  -- 旗帜计数每 4 轮才统计一次（约 2 秒），它不需要 0.5 秒响应
local buff_slot = {}        -- 上次命中的槽位缓存

-- keep_long = true 时只在现有时间不足时补，绝不把玩家自己喝的长 buff 压成 1 秒
-- 数组句柄缓存：同一个 Player 实例的 buffType/buffTime 数组引用在游戏内不会变，
-- 每帧重新 get_field_value 两次是纯浪费（这是原来最重的一笔开销）。
local buff_arrays = {}

local function get_buff_arrays(player)
    local c = buff_arrays[player]
    if c then
        local n = arr_len(c.ba)
        if n > 0 then return c.ba, c.bt, n end
        buff_arrays[player] = nil        -- 读到 0 说明缓存坏了，重取
    end
    local ba = rd(H.f_pbtype, player, "object")
    local bt = rd(H.f_pbtime, player, "object")
    if not (ba and bt) then return nil end
    local n = arr_len(ba)
    if n <= 0 then return nil end
    buff_arrays[player] = { ba = ba, bt = bt }
    return ba, bt, n
end

local function give_buff(player, bid, keep_long)
    if not (player and bid and bid > 0) then return end
    local ba, bt, maxn = get_buff_arrays(player)
    if not (ba and bt and maxn) then return end

    local function stamp(slot)
        if keep_long then
            local cur = arr_at(bt, slot, "int32")
            if type(cur) == "number" and cur >= BUFF_TIME then return end
        end
        arr_set(bt, slot, BUFF_TIME, "int32")
    end

    local cached = buff_slot[bid]
    if cached and arr_at(ba, cached, "int32") == bid then
        stamp(cached)
        return
    end

    local free = -1
    for i = 0, maxn - 1 do
        local cur = arr_at(ba, i, "int32")
        if cur == bid then
            buff_slot[bid] = i
            stamp(i)
            return
        elseif cur == 0 and free < 0 then
            free = i
        end
    end
    if free >= 0 then
        arr_set(ba, free, bid, "int32")
        arr_set(bt, free, BUFF_TIME, "int32")
        buff_slot[bid] = free
    end
end

-- 取下即失效：这一轮不再需要的 buff，把它剩余时长清零。
-- 关键防误伤：只清 t <= BUFF_TIME 的槽位 —— 那是我们续期时写进去的 3 秒；
--   玩家自己喝的药水是 3600 帧（一分钟），远超 BUFF_TIME，绝不会被清掉。
-- （类药水袋 / 完全之龙都做了这一步，否则取下物品后 buff 还会残留一段时间）
local function clear_stale_buffs(player, want)
    local ba, bt = get_buff_arrays(player)
    if not (ba and bt) then return end
    for bid, slot in pairs(buff_slot) do
        if not want[bid] then
            local cur = arr_at(ba, slot, "int32")
            local t = arr_at(bt, slot, "int32")
            if cur == bid and type(t) == "number" and t > 0 and t <= BUFF_TIME then
                arr_set(bt, slot, 0, "int32")
            end
            buff_slot[bid] = nil
        end
    end
end

local POTION_NEED = 30

-- ①站 ②药水 的命中集合，每轮扫描重算
local stat_buffs = {}       -- buffType -> true（增益站给的）
local pot_buffs  = {}       -- buffType -> true（药水给的，用 keep_long）
local want_camp  = false    -- 需要篝火再生
local want_heart = false    -- 需要心形灯笼再生
local want_water = false    -- 水蜡烛
local want_peace = false    -- 和平蜡烛
local want_shadow= false    -- 暗影蜡烛
-- 容器里实际有几面旗。必须声明在 effects_rescan 之前，否则那边赋值会跑到全局去
local banner_have = 0
local banner_scan_t = 0
local banner_list = {}      -- 容器里当前有哪些旗帜物品 id（约每 2 秒重建一次）

local function effects_rescan()
    for k in pairs(stat_buffs) do stat_buffs[k] = nil end
    for k in pairs(pot_buffs) do pot_buffs[k] = nil end
    want_camp, want_heart = false, false
    want_water, want_peace, want_shadow = false, false, false

    -- ② 增益站：容器里每个增益家具给一个 buff
    each_slot("station", function(id)
        local b = DATA.station_buff and DATA.station_buff(id) or 0
        if b and b > 0 then stat_buffs[b] = true end
        -- 水蜡烛 148 / 和平蜡烛 3117 / 暗影蜡烛 5322：走 Zone 标志（原版手持才生效的那条路）
        if id == 148 then want_water = true
        elseif id == 3117 then want_peace = true
        elseif id == 5322 then want_shadow = true end
        -- 篝火(87) / 心形灯笼(89) 的真实效果在原版 UpdateLifeRegen 里，光给 buff 只有图标
        if id == 966 or (id >= 3046 and id <= 3050) or id == 3723
           or (id >= 4689 and id <= 4694) then
            want_camp = true
        elseif id == 1859 then
            want_heart = true
        end
    end)

    -- ③ 药水袋：分三块扫
    --   buffpot（增益药水）→ 同种累计 ≥10 瓶才生效
    --   food（食物）→ 同样要 ≥10 个（WellFed 三档 26/206/207 由物品 buffType 自带）
    --   flask（药剂）→ 同样要 ≥10 瓶（buff 71/73~79）
    local function add_potion(section, need)
        local cnt = {}
        each_slot(section, function(id, stack)
            cnt[id] = (cnt[id] or 0) + (stack or 0)
        end)
        for id, n in pairs(cnt) do
            if n >= need then
                local b = DATA.item_buff and DATA.item_buff(id) or 0
                if b and b > 0 then pot_buffs[b] = true end
            end
        end
    end
    -- 旗帜袋：统计容器里有几面旗（0 时 Reset 回调直接跳过）
    -- 285 格遍历不必每 0.5 秒做一次，每 4 轮（约 2 秒）一次足够
    banner_scan_t = banner_scan_t + 1
    if (banner_scan_t % BANNER_SCAN_EVERY) == 1 then
        -- 重建列表。这样 Reset 回调里每帧只遍历「实际有几面旗」，
        -- 而不是固定扫 285 个格子。
        for i = #banner_list, 1, -1 do banner_list[i] = nil end
        each_slot("banner", function(id) banner_list[#banner_list + 1] = id end)
        banner_have = #banner_list
    end

    -- 统计当前代挂了多少个 buff：屏幕按钮用它决定要不要显示
    do
        local n = 0
        for _ in pairs(stat_buffs) do n = n + 1 end
        for _ in pairs(pot_buffs) do n = n + 1 end
        E.active_n = n
    end

    add_potion("buffpot", POTION_NEED)   -- 增益药水：≥30 瓶
    add_potion("food", POTION_NEED)      -- 食物：≥30 个
    add_potion("flask", POTION_NEED)     -- 药剂：≥30 瓶
end

-- 篝火/心灯：只在 UpdateLifeRegen 之后补数值（+1 / +2），不碰 SceneMetrics 的反射调用。
-- （曾经试过写 SceneMetrics.HasCampfire 骗原版自己算，但那要每帧 invoke getter+setter，
--   句柄一旦不对就是原生层崩溃，而且是"一进世界就闪退"这种最难查的形式，已放弃该路线。）

-- CalculateZones postfix：补三种蜡烛的 Zone 标志 + 篝火/心灯的原版标记
-- （都是写字段，不调用任何方法，所以没有原生层风险）
local function apply_candles(inst)
    if not inst then return end
    if want_water then set_bool_field(H.f_zonewater, inst, true) end
    if want_peace then set_bool_field(H.f_zonepeace, inst, true) end
    if want_shadow then set_bool_field(H.f_zoneshadow, inst, true) end
    if want_camp and H.f_camp_bf then set_bool_field(H.f_camp_bf, inst, true) end
    if want_heart and H.f_heart_bf then set_bool_field(H.f_heart_bf, inst, true) end
end

local function life_regen_post(player)
    if not (want_camp or want_heart) then return end
    if not player or not H.f_liferegen then return end
    local add = 0
    -- 关键：如果已经能写 HasCampfire / HasHeartLantern 字段，原版就会自己算 +1/+2，
    -- 这里绝不能再补，否则玩家站在真篝火旁边会变成双倍。
    if want_camp and not H.f_camp_bf then add = add + 1 end
    if want_heart and not H.f_heart_bf then add = add + 2 end
    if add <= 0 then return end
    local ok, v = pcall(P.get_field_value, H.f_liferegen, player, "int32")
    if ok and type(v) == "number" then
        pcall(P.set_field_value, H.f_liferegen, player, v + add, "int32")
    end
end

-- ============================ 隐藏代挂 buff 的图标 ============================
-- 需求：药水袋 / 增益站常年挂着十几个 buff，图标铺满屏幕，但效果必须保留。
--
-- 做法：hook Main.DrawInterface_Resources_Buffs 的 prefix，在绘制前把这些槽位的
--   buffType 临时改成 0，绘制完（postfix）立刻改回来。
--   → 绘制时它们不存在，所以不画；效果不受影响，整段只发生在一帧的绘制瞬间。
--
-- 区分"代挂的"和"玩家自己的"：看剩余时长。
--   我们续期写的是 BUFF_TIME（3 秒），玩家自己喝的药水是 3600 帧（一分钟）。
--   只有 t <= BUFF_TIME 的才算我们刷的。
--
-- 不跳整个方法（prefix 返回 true）的原因：那样连玩家自己的 buff 也看不见。
-- prefix 返回 false = 照常执行原方法，只是数据已被临时改过。
E.icons_hidden = false        -- 开关：true = 不画代挂的 buff 图标

local hide_slots, hide_ids = {}, {}

local function buffbar_prefix(inst)
    if not E.icons_hidden then return false end
    local me = E.player
    if not me then return false end
    local ba, bt = get_buff_arrays(me)
    if not (ba and bt) then return false end
    local n = 0
    for bid, slot in pairs(buff_slot) do
        if arr_at(ba, slot, "int32") == bid then
            local t = arr_at(bt, slot, "int32")
            if type(t) == "number" and t > 0 and t <= BUFF_TIME then
                n = n + 1
                hide_slots[n] = slot
                hide_ids[n] = bid
                arr_set(ba, slot, 0, "int32")   -- 只在绘制期间为 0
            end
        end
    end
    return false
end

local function buffbar_postfix(inst)
    if #hide_slots == 0 then return end
    local me = E.player
    local ba = nil
    if me then ba = get_buff_arrays(me) end
    if ba then
        for i = 1, #hide_slots do
            arr_set(ba, hide_slots[i], hide_ids[i], "int32")   -- 立刻还原
        end
    end
    for i = #hide_slots, 1, -1 do
        hide_slots[i] = nil
        hide_ids[i] = nil
    end
end

-- ============================ ④ 旗帜袋 ============================

local banner_of = {}        -- item id -> bannerType
local banner_n = 0
-- 注：banner_have 的声明在最上面（stat_buffs 附近）。
--    Lua 的 local 作用域从声明处开始，如果声明写在 effects_rescan 后面，
--    那个函数里的赋值会变成全局变量，而本文件读到的 local 永远是 0 → 旗帜袋静默失效。
local banner_warned = false
local banner_done_logged = false

-- PC 1.4.5.8 BannerSystem.BannerToItem 原文抄写（PC/Terraria.GameContent/BannerSystem.cs:341）
-- 用它做兜底：即使反射拿不到 BannerToItem，反查表也一定是完整的 292 条。
-- （上一版只走反射，反射一旦失败 banner_n 就是 0，而代码会静默 return —— 表现就是"完全没效果"，且日志里不报错）
local function banner_to_item_math(b)
    if b == 292 then return 5673 end
    if b == 291 then return 5672 end
    if b == 290 then return 5651 end
    if b == 289 then return 5352 end
    if b >= 276 then return 4965 + b - 276 end
    if b >= 274 then return 4687 + b - 274 end
    if b == 273 then return 4602 end
    if b >= 267 then return 4541 + b - 267 end
    if b >= 257 then return 3837 + b - 257 end
    if b >= 252 then return 3789 + b - 252 end
    if b == 251 then return 3780 end
    if b >= 249 then return 3593 + b - 249 end
    if b >= 186 then return 3390 + b - 186 end
    if b >= 88 then return 2897 + b - 88 end
    return 1615 + b - 1
end

local function build_banner_reverse()
    local n = 0

    -- ① 公式表（必定成功）
    --   循环范围对齐类旗帜盒：它用 0..MaxBannerTypes-1（MaxBannerTypes=293）
    for b = 0, 292 do
        local it = (b == 0) and 1614 or banner_to_item_math(b)
        if it and it > 0 and not banner_of[it] then
            banner_of[it] = b
            n = n + 1
        end
    end

    -- ② 反射核对：能调通就用游戏自己的映射覆盖公式表
    local okb, Tb = pcall(P.get_type, "Terraria.GameContent", "BannerSystem")
    if not okb or not Tb then
        okb, Tb = pcall(P.get_type, "Terraria", "BannerSystem")
    end
    local m = Tb and P.get_method(Tb, "BannerToItem", 1)
    if m then
        local cnt = 0
        for b = 0, 292 do
            local okr, it = pcall(P.invoke, m, nil, b)
            if okr and type(it) == "number" and it > 0 then
                banner_of[it] = b
                cnt = cnt + 1
            end
        end
        log("BannerToItem 反射核对 " .. cnt .. " 条")
    else
        log("BannerToItem 反射不可用，使用公式表（不影响结果）")
    end

    banner_n = n
    log("旗帜反查表构建完成：" .. n .. " 条")
    return n
end

-- SceneMetrics.Reset postfix：清空之后把容器里的旗帜补写回去
-- （Reset 之后原版 ScanTiles 会再置 true，不会把我们的写清掉）
-- 读 NPCBannerBuff 的 bool[]（只按 object 读，和类旗帜盒一致）
local arr_read_warned = false
local function get_banner_arr(inst)
    if not H.f_banner then return nil end
    return rd(H.f_banner, inst, "object")
end

local inst_fallback_warned = false

local function apply_bag_banner(inst)
    if banner_n <= 0 then return end
    if banner_have <= 0 then return end     -- 空容器：一次字段都不用读
    if not (H.f_banner and DATA) then return end
    -- 只接受 hook 回调给的实例；拿不到就放弃这一轮（不再去 invoke 属性 getter）
    if not inst then
        if not inst_fallback_warned then
            inst_fallback_warned = true
            warn("旗帜袋：hook 回调没有给出 SceneMetrics 实例")
        end
        return
    end
    local arr = get_banner_arr(inst)
    if not arr then
        if not arr_read_warned then
            arr_read_warned = true
            warn("旗帜袋：NPCBannerBuff 数组读取失败（字段=bool[]，object/array 两种类型都试过）")
        end
        return
    end
    -- 长度校验：NPCBannerBuff 长度应为 MaxBannerTypes(293)。
    -- 越界写 bool[] 会直接崩原生层，pcall 拦不住，所以必须自己卡住。
    local alen = arr_len(arr)
    if alen <= 0 then
        if not arr_read_warned then
            arr_read_warned = true
            warn("旗帜袋：NPCBannerBuff 长度读到 0，放弃写入")
        end
        return
    end

    local hit = 0
    for i = 1, #banner_list do
        local bt = banner_of[banner_list[i]]
        if bt and bt >= 0 and bt < alen and set_bool(arr, bt, true) then
            hit = hit + 1
        end
    end
    if hit > 0 then
        set_bool_field(H.f_hasban, inst, true)
        if not banner_done_logged then
            banner_done_logged = true
            log("旗帜袋生效：已写入 " .. hit .. " 面旗帜的 NPCBannerBuff")
        end
    elseif not banner_warned then
        banner_warned = true
        warn("旗帜袋：NPCBannerBuff 写入 0 项（容器里没有旗帜，或 array_set 写 bool 失败）")
    end
end

-- ============================ 挂点安装 ============================

local hooks = {}
local hook_names = {}

local function install_hooks()
    -- 随身制作站：AdjTiles 每帧 Clear 一次，我们在它跑完之后补写
    if H.Tp then
        local mAdj = P.get_method(H.Tp, "AdjTiles", 0)
        if mAdj then
            local ok, h = pcall(P.install_hook, mAdj, {
                postfix = function(inst)
                    pcall(function()
                        if not ready or not inst then return end
                        craft_scan_wait = craft_scan_wait + 1
                        if craft_scan_wait >= 15 then
                            craft_scan_wait = 0
                            pcall(craft_rescan)
                        end
                        if craft_n > 0 then pcall(craft_apply, inst) end
                    end)
                end,
            })
            if ok and h then hooks[#hooks + 1] = h; hook_names[#hook_names + 1] = "AdjTiles" end
        end
        -- UpdateLifeRegen：篝火 / 心灯的再生
        local mLr = P.get_method(H.Tp, "UpdateLifeRegen", 0)
        if mLr then
            -- 只装 postfix：直接补数值。原先 pre 里会去 invoke SceneMetrics 的
            -- HasCampfire getter/setter，那是每帧两次反射调用，句柄稍有不对就会崩原生层。
            local ok, h = pcall(P.install_hook, mLr, {
                postfix = function(inst) pcall(life_regen_post, inst) end,
            })
            if ok and h then hooks[#hooks + 1] = h; hook_names[#hook_names + 1] = "UpdateLifeRegen" end
        end
    end
    -- 和平蜡烛 / 水蜡烛 / 暗影蜡烛
    if H.m_calczones then
        local ok, h = pcall(P.install_hook, H.m_calczones, {
            postfix = function(inst) pcall(apply_candles, inst) end,
        })
        if ok and h then hooks[#hooks + 1] = h; hook_names[#hook_names + 1] = "CalculateZones" end
    end
    -- 隐藏代挂 buff 图标
    if H.m_drawbuffs then
        local ok, h = pcall(P.install_hook, H.m_drawbuffs, {
            prefix  = function(inst) return buffbar_prefix(inst) end,
            postfix = function(inst) pcall(buffbar_postfix, inst) end,
        })
        if ok and h then
            hooks[#hooks + 1] = h
            hook_names[#hook_names + 1] = "GUIBuffs.Draw"
        else
            log("[Buff图标] 绘制钩子安装失败 ok=" .. tostring(ok) .. " h=" .. tostring(h))
        end
    end
    -- 旗帜袋：两个挂点都装（幂等，重复写 true 无害）
    --   ① SceneMetrics.Reset postfix —— 清空后立刻补写
    --   ② SceneMetrics.Scan  postfix —— Reset 万一没拦住，整轮扫描结束再补一次
    if H.m_smreset then
        local ok, h = pcall(P.install_hook, H.m_smreset, {
            postfix = function(inst) pcall(apply_bag_banner, inst) end,
        })
        if ok and h then hooks[#hooks + 1] = h; hook_names[#hook_names + 1] = "SceneMetrics.Reset" end
    end
    -- 注：不挂 SceneMetrics.Scan —— 它的参数是 struct（SceneMetricsScanSettings），
    --     hook 一个带 struct 参数的方法风险高，类旗帜盒也只挂了无参的 Reset。

    log("钩子安装完成 " .. #hooks .. " 个：" .. table.concat(hook_names, ", "))
end

-- ============================ 对外接口 ============================

local bind_fail_logged = false

function E.setup(d)
    if ready then return true end
    if d then DATA = d end
    if not DATA then
        warn("数据层未就绪")
        return false
    end
    -- 注意：这里是 mod.init 阶段，反射有可能还没完全就绪（模组加载早于世界加载）。
    -- 类旗帜盒是靠"进世界后再 bind"躲开这个坑的，我们改成在主循环里按需重试（见 E.tick）。
    if not bind() then
        if not bind_fail_logged then
            bind_fail_logged = true
            warn("关键反射句柄缺失，将在运行中重试")
        end
        return false
    end
    ready = true
    pcall(build_banner_reverse)
    pcall(effects_rescan)
    pcall(craft_rescan)
    pcall(install_hooks)
    return true
end

-- 由 bag_core.on_tick 每帧调用
function E.tick(player)
    if not player then return end
    E.player = player          -- 给绘制 hook 用
    E._t = (E._t or 0) + 1

    -- 绑定失败就每 2 秒重试一次（模组加载早于世界加载，第一次往往拿不到反射句柄）
    if not ready then
        if (E._t % 120) == 0 then pcall(E.setup) end
        return
    end
    if E.on ~= false and (E._t % RESCAN_EVERY) == 0 then
        pcall(effects_rescan)
    end

    -- ① 制作站：主力是 AdjTiles 的 postfix（开背包时每帧一次），
    --   这里只是"万一 AdjTiles 不在 Update 链上"的兜底，降到每 10 帧一次。
    if E.on ~= false and craft_n > 0 and (E._t % 10) == 0 then
        pcall(craft_apply, player)
    end

    -- ④ 旗帜袋：只用 hook 驱动。
    --   v0.9.6 曾在这里「每 5 帧直写一次 SceneMetrics」，结果一进世界就闪退：
    --   那条路径在 hook 从没触发时等于从没跑过，一旦变成常驻执行就暴露了
    --   sm_instance/invoke 和数组写入的问题。这里撤掉，回到类旗帜盒的单 hook 路线。

    -- 统计玩家身上一共有几个 buff（含自己喝的）：屏幕按钮用它决定要不要露面
    if (E._t % 15) == 0 then
        local ba, bt, maxn = get_buff_arrays(player)
        local cnt = 0
        if ba and maxn then
            for i = 0, maxn - 1 do
                local v = arr_at(ba, i, "int32")
                if type(v) == "number" and v > 0 then cnt = cnt + 1 end
            end
        end
        E.player_buffs = cnt
    end

    -- ② 增益站 + ③ 药水袋：每 45 帧续一次（buff 时长 3 秒，留足余量）
    if E.on ~= false and (E._t % BUFF_EVERY) == 0 then
        local want = {}
        for bid in pairs(stat_buffs) do
            want[bid] = true
            pcall(give_buff, player, bid, false)
        end
        for bid in pairs(pot_buffs) do
            want[bid] = true
            pcall(give_buff, player, bid, true)
        end
        -- 取下即失效：不在 want 里的，清掉我们刷的短时长
        pcall(clear_stale_buffs, player, want)
    end
end

-- 容器内容变了，让下一轮立刻重扫
function E.refresh()
    pcall(effects_rescan)
    pcall(craft_rescan)
end

function E.cleanup()
    for i = 1, #hooks do
        pcall(function() hooks[i]:remove() end)
    end
    hooks = {}
    hook_names = {}
    ready = false
end

return E