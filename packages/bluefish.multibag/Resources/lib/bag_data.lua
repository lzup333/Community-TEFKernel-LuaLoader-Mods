-- bag_data.lua
-- 多功能大背包：数据层
--   1) 100 格容器（内存 + 文本持久化）
--   2) 背包读写（多组合尝试，兼容不同内核的取值方式）
--   3) 物品分类：药水 / 旗帜 / 增益站 / 杂物
-- ---------------------------------------------------------------------------

local q = mod.quickapi
local patch = mod.patch

local D = {}

-- ID -> 中文名全量表（6180 条，由游戏本地化文件生成）
local ok_bf, BUFF_TABLE = pcall(require, "item_buff")
if not ok_bf or type(BUFF_TABLE) ~= "table" then BUFF_TABLE = {} end
local ok_cn, CN_TABLE = pcall(require, "item_cn")
if not ok_cn or type(CN_TABLE) ~= "table" then CN_TABLE = {} end

D.SLOT_COUNT = 100
local SAVE_NAME = "multibag_data.txt"

-- 旧的单池数组已废弃，改成分区 D.pools（见文件下方「分区」一节）
D.dirty = false
D.inv_debug = "未探测"
D.loaded = false

-- ==========================================================================
-- 背包访问
-- ==========================================================================

local inv_field = nil
local inv_probed = false

local function get_inv_field()
    if inv_probed then return inv_field end
    inv_probed = true
    local ok, pt = pcall(patch.get_type, "Terraria", "Player")
    if not ok or not pt then D.inv_debug = "Player 类型取不到" return nil end
    for _, name in ipairs({ "inventory", "Inventory", "inv" }) do
        local okf, f = pcall(patch.get_field, pt, name)
        if okf and f then
            inv_field = f
            D.inv_debug = "字段 " .. name
            return f
        end
    end
    D.inv_debug = "找不到 inventory 字段"
    return nil
end

-- 返回 (数组句柄, 长度)；失败返回 nil, 0
-- 参考「类药水袋」inventory_of：先拿字段句柄，再 get_field_value(f, player, "object")
function D.inv(player)
    if not player then
        D.inv_debug = "player 为空"
        return nil, 0
    end

    local tries = {}

    -- ① 字段句柄 + "object"（参考模组的做法）
    local f = get_inv_field()
    if f then
        local ok, arr = pcall(patch.get_field_value, f, player, "object")
        if ok and arr then
            local okl, n = pcall(patch.array_length, arr)
            if okl and type(n) == "number" and n > 0 then
                D.inv_debug = "ok(field) len=" .. n
                return arr, n
            end
            tries[#tries + 1] = "field:长度失败"
        else
            tries[#tries + 1] = "field:nil"
        end
    else
        tries[#tries + 1] = "无字段"
    end

    -- ② quickapi.get_object
    local ok2, arr2 = pcall(q.get_object, "Terraria", "Player", "inventory", player)
    if ok2 and arr2 then
        local okl, n = pcall(patch.array_length, arr2)
        if okl and type(n) == "number" and n > 0 then
            D.inv_debug = "ok(go) len=" .. n
            return arr2, n
        end
        tries[#tries + 1] = "go:长度失败"
    else
        tries[#tries + 1] = "go:nil"
    end

    D.inv_debug = "失败(" .. table.concat(tries, ",") .. ")"
    return nil, 0
end

-- ==========================================================================
-- Item 字段句柄
-- ==========================================================================

local F = {}
local fields_ready = false

local function fget(field, inst, kind)
    if not field or not inst then return nil end
    local ok, v = pcall(patch.get_field_value, field, inst, kind)
    if ok then return v end
    return nil
end

local function need_fields()
    if fields_ready then return true end
    local ok, t = pcall(patch.get_type, "Terraria", "Item")
    if not ok or not t then return false end
    local function f(n)
        local ok2, v = pcall(patch.get_field, t, n)
        return ok2 and v or nil
    end
    F.type       = f("type")
    F.stack      = f("stack")
    F.buffType   = f("buffType")
    F.consumable = f("consumable")
    F.healLife   = f("healLife")
    F.healMana   = f("healMana")
    F.createTile = f("createTile")
    F.placeStyle = f("placeStyle")
    F.maxStack   = f("maxStack")
    F.favorited  = f("favorited")
    fields_ready = F.type ~= nil
    return fields_ready
end

local function item_int(field, inst)
    return tonumber(fget(field, inst, "int32")) or 0
end

local function item_bool(field, inst)
    local v = fget(field, inst, "bool")
    return v == true
end

function D.slot_type(slot)
    if not need_fields() or not slot then return 0 end
    return item_int(F.type, slot)
end

-- 造一个指定 id 的 Item 实例
local item_type_handle = nil
local m_setdefaults = nil

function D.make_item(id)
    if not need_fields() then return nil end
    if not item_type_handle then
        local ok, t = pcall(patch.get_type, "Terraria", "Item")
        if ok then item_type_handle = t end
    end
    if not item_type_handle then return nil end

    local ok, inst = pcall(patch.new_instance, item_type_handle)
    if not ok or not inst then return nil end

    if not m_setdefaults then
        -- 1.4.6 是两参版本（第二参 ItemVariant，可传 nil），1.4.5.8 是单参
        for _, argc in ipairs({ 2, 1 }) do
            local okm, m = pcall(patch.get_method, item_type_handle, "SetDefaults", argc)
            if okm and m then
                m_setdefaults = m
                m_setdefaults_argc = argc
                break
            end
        end
    end
    if m_setdefaults then
        if m_setdefaults_argc == 2 then
            pcall(patch.invoke, m_setdefaults, inst, id, nil)
        else
            pcall(patch.invoke, m_setdefaults, inst, id)
        end
    end
    return inst
end

-- ==========================================================================
-- 分类
-- ==========================================================================

-- ==========================================================================
-- 分区：每个页签一套独立容量，互不挤占
-- ==========================================================================
D.SECTIONS = {
    { key = "misc",    cap = 500 },   -- 物品
    { key = "craft",   cap = 36  },   -- 制作站
    { key = "buffpot", cap = 40  },   -- 增益药水
    { key = "food",    cap = 1   },   -- 食物
    { key = "flask",   cap = 1   },   -- 药剂（武器浸附）
    { key = "station", cap = 14  },   -- 增益站
    { key = "banner",  cap = 285 },   -- 敌怪旗
}
D.CAPS = {}
D.pools = {}
for _, sec in ipairs(D.SECTIONS) do
    D.CAPS[sec.key] = sec.cap
    D.pools[sec.key] = {}
end


function D.section_cap(key) return D.CAPS[key] or 0 end

function D.section_used(key)
    local p = D.pools[key]
    if not p then return 0 end
    local n = 0
    for i = 1, (D.CAPS[key] or 0) do
        if p[i] then n = n + 1 end
    end
    return n
end

-- 食物 buff（WellFed 三档）
local FOOD_BUFF = { [26] = true, [206] = true, [207] = true }
-- 药剂（武器浸附）buff
local FLASK_BUFF = {
    [71] = true, [73] = true, [74] = true, [75] = true,
    [76] = true, [77] = true, [78] = true, [79] = true,
}

-- 敌怪旗物品 ID（BannerSystem.BannerToItem 推导，共 292 种）
-- 只包含「击杀怪物掉落、放置后给玩家旗帜增益」的敌怪旗
-- 装饰旗（红旗/绿旗/蓝旗/黄旗/世界旗/十字章旗等）不在此列
local BANNER_IDS = {
    1615, 1616, 1617, 1618, 1619, 1620, 1621, 1622, 1623, 1624, 1625, 1626,
    1627, 1628, 1629, 1630, 1631, 1632, 1633, 1634, 1635, 1636, 1637, 1638,
    1639, 1640, 1641, 1642, 1643, 1644, 1645, 1646, 1647, 1648, 1649, 1650,
    1651, 1652, 1653, 1654, 1655, 1656, 1657, 1658, 1659, 1660, 1661, 1662,
    1663, 1664, 1665, 1666, 1667, 1668, 1669, 1670, 1671, 1672, 1673, 1674,
    1675, 1676, 1677, 1678, 1679, 1680, 1681, 1682, 1683, 1684, 1685, 1686,
    1687, 1688, 1689, 1690, 1691, 1692, 1693, 1694, 1695, 1696, 1697, 1698,
    1699, 1700, 1701, 2897, 2898, 2899, 2900, 2901, 2902, 2903, 2904, 2905,
    2906, 2907, 2908, 2909, 2910, 2911, 2912, 2913, 2914, 2915, 2916, 2917,
    2918, 2919, 2920, 2921, 2922, 2923, 2924, 2925, 2926, 2927, 2928, 2929,
    2930, 2931, 2932, 2933, 2934, 2935, 2936, 2937, 2938, 2939, 2940, 2941,
    2942, 2943, 2944, 2945, 2946, 2947, 2948, 2949, 2950, 2951, 2952, 2953,
    2954, 2955, 2956, 2957, 2958, 2959, 2960, 2961, 2962, 2963, 2964, 2965,
    2966, 2967, 2968, 2969, 2970, 2971, 2972, 2973, 2974, 2975, 2976, 2977,
    2978, 2979, 2980, 2981, 2982, 2983, 2984, 2985, 2986, 2987, 2988, 2989,
    2990, 2991, 2992, 2993, 2994, 3390, 3391, 3392, 3393, 3394, 3395, 3396,
    3397, 3398, 3399, 3400, 3401, 3402, 3403, 3404, 3405, 3406, 3407, 3408,
    3409, 3410, 3411, 3412, 3413, 3414, 3415, 3416, 3417, 3418, 3419, 3420,
    3421, 3422, 3423, 3424, 3425, 3426, 3427, 3428, 3429, 3430, 3431, 3432,
    3433, 3434, 3435, 3436, 3437, 3438, 3439, 3440, 3441, 3442, 3443, 3444,
    3445, 3446, 3447, 3448, 3449, 3450, 3451, 3452, 3593, 3594, 3780, 3789,
    3790, 3791, 3792, 3793, 3837, 3838, 3839, 3840, 3841, 3842, 3843, 3844,
    3845, 3846, 4541, 4542, 4543, 4544, 4545, 4546, 4602, 4687, 4688, 4965,
    4966, 4967, 4968, 4969, 4970, 4971, 4972, 4973, 4974, 4975, 4976, 4977,
    5352, 5651, 5672, 5673,
}
local BANNER_ITEM = {}
for _, v in ipairs(BANNER_IDS) do BANNER_ITEM[v] = true end

-- TileID.Banners = 91（注意：21 是 Containers 宝箱，之前搞错了）
local BANNER_TILE = 91

-- 制作站（可放置、靠近后能合成）：PE 1.4.5.8 实测 ItemID
local CRAFT_ITEMS = {
    -- ===== 基础制作站 =====
    [36]   = true,  -- 工作台
    [33]   = true,  -- 熔炉
    [35]   = true,  -- 铁砧
    [716]  = true,  -- 铅砧
    [221]  = true,  -- 地狱熔炉
    [524]  = true,  -- 精金熔炉
    [1221] = true,  -- 钛金熔炉
    [525]  = true,  -- 秘银砧
    [1220] = true,  -- 山铜砧
    [1551] = true,  -- 自动锤炼机
    [5532] = true,  -- 恶魔祭坛
    [5533] = true,  -- 猩红祭坛
    [354]  = true,  -- 书架
    [3000] = true,  -- 炼药桌
    -- ===== 功能性工作台 =====
    [345]  = true,  -- 烹饪锅
    [1791] = true,  -- 大锅
    [352]  = true,  -- 酒桶
    [5008] = true,  -- 茶壶
    [363]  = true,  -- 锯木机
    [398]  = true,  -- 工匠作坊
    [1430] = true,  -- 灌注站
    [1120] = true,  -- 染缸
    [5482] = true,  -- 炼金瓶（死亡细胞药剂站）
    [3549] = true,  -- 远古操纵机
    [4142] = true,  -- 腐变室（腐化制作站）
    [332]  = true,  -- 织布机
    [2172] = true,  -- 重型工作台
    -- ===== 特殊制作机 =====
    [2192] = true,  -- 骨头焊机
    [2193] = true,  -- 腐变室（血肉克隆机）
    [2194] = true,  -- 玻璃窑
    [2195] = true,  -- 神庙熔炉
    [2196] = true,  -- 生命织机
    [2197] = true,  -- 天磨
    [2198] = true,  -- 制冰机
    [2203] = true,  -- 蒸汽朋克锅炉
    [2204] = true,  -- 蜂蜜分配器
    [995]  = true,  -- 搅拌机
    [997]  = true,  -- 提炼机
    [996]  = true,  -- 绞肉机
    [998]  = true,  -- 凝固机
    [5296] = true,  -- 叶绿提炼机
}

-- 水槽：65 种材质，全部算制作站（可装水、可炼药）
local SINK_IDS = {
    2827, 2828, 2829, 2830, 2831, 2832, 2833, 2834, 2835, 2836,
    2837, 2838, 2839, 2840, 2841, 2842, 2843, 2844, 2845, 2846,
    2847, 2848, 2849, 2850, 2851, 2852, 2853, 2854, 2855, 3147,
    3148, 3149, 3896, 3972, 4160, 4181, 4202, 4223, 4312, 4581,
    5163, 5184, 5205, 5563, 5616, 5704, 5727, 5752, 5771, 5792,
    5813, 5834, 5853, 5873, 5892, 5913, 5947, 5969, 5990, 6013,
    6036, 6059, 6082, 6104, 6126,
}
for _, v in ipairs(SINK_IDS) do CRAFT_ITEMS[v] = true end


-- 自己的物品 ID（由 bag_core 注入），收纳时跳过，免得把背包本身收进去
local SELF_ITEM_ID = 0
function D.set_self_item(id)
    SELF_ITEM_ID = tonumber(id) or 0
end

-- 增益站：PE 1.4.5.8 实测 ID（ItemID -> 对应 BuffID，0 = 不加 buff）
-- 硬编码为主，名字反查为辅（万一版本不同）
local STATIONS_HARD = {
    [487]  = 29,   -- 水晶球 -> 洞察
    [966]  = 87,   -- 篝火 -> 温暖
    [1431] = 158,  -- 星星瓶 -> 星光
    [1859] = 89,   -- 心形灯笼 -> 心之灯
    [2177] = 93,   -- 弹药箱
    [2999] = 150,  -- 施法桌 -> 着魔
    [3117] = 0,    -- 和平蜡烛
    [148]  = 0,    -- 水蜡烛
    [3198] = 159,  -- 磨刀石 -> 尖锐
    [3814] = 348,  -- 战争桌 -> 策略
    [3750] = 192,  -- 蛋糕块 -> 糖分冲击
    [63]   = 146,  -- 向日葵 -> 快乐
    [4276] = 215,  -- 巴斯特雕像 -> 巴斯特防御
    [5322] = 350,  -- 暗影蜡烛
    [3046] = 87,   -- 诅咒篝火
    [3047] = 87,   -- 恶魔篝火
    [3048] = 87,   -- 冰冻篝火
    [3049] = 87,   -- 脓血篝火
    [3050] = 87,   -- 彩虹篝火
    [3723] = 87,   -- 超亮篝火
}

-- 名字反查（ItemID.xxx / BuffID.xxx），拿不到就返回 nil
local function id_by(holder, name)
    local ok, v = pcall(function()
        local t = patch.get_type("Terraria.ID", holder)
        local f = t and patch.get_field(t, name)
        if not f then return nil end
        return patch.get_field_value(f, nil, "int32")
    end)
    if ok and type(v) == "number" and v > 0 then return v end
    return nil
end

local station_map = nil

local function build_station_map()
    local map = {}
    -- 先铺硬编码（PE 实测值）
    for k, v in pairs(STATIONS_HARD) do map[k] = v end

    -- 再用名字查到的 ID 补/覆盖（版本不同时更稳）
    local pairs_name = {
        { "CrystalBall",      "Clairvoyance" },
        { "Campfire",         "Campfire" },
        { "StarinaBottle",    "StarInBottle" },
        { "HeartLantern",     "HeartLamp" },
        { "AmmoBox",          "AmmoBox" },
        { "BewitchingTable",  "Bewitched" },
        { "SharpeningStation","Sharpened" },
        { "PeaceCandle",      nil },
        { "WaterCandle",      nil },
        { "CursedCampfire",   "Campfire" },
        { "DemonCampfire",    "Campfire" },
        { "FrozenCampfire",   "Campfire" },
        { "IchorCampfire",    "Campfire" },
        { "RainbowCampfire",  "Campfire" },
        { "UltraBrightCampfire", "Campfire" },
    }
    for _, pr in ipairs(pairs_name) do
        local iid = id_by("ItemID", pr[1])
        if iid and iid > 0 then
            local bid = pr[2] and (id_by("BuffID", pr[2]) or 0) or 0
            map[iid] = bid
        end
    end
    return map
end

function D.station_buff(type_id)
    if not station_map then station_map = build_station_map() end
    return station_map[type_id]
end

-- 返回分区 key：banner / station / craft / food / flask / buffpot / misc
function D.classify_slot(slot)
    if not need_fields() or not slot then return nil, 0 end
    local t = item_int(F.type, slot)
    if t <= 0 then return nil, 0 end

    -- 背包本身不收纳
    if SELF_ITEM_ID > 0 and t == SELF_ITEM_ID then return nil, 0 end

    -- 敌怪旗：只认 BannerToItem 白名单（装饰旗虽是图格 91 但不收）
    if BANNER_ITEM[t] then
        return "banner", t
    end

    -- 增益站
    if not station_map then station_map = build_station_map() end
    if station_map[t] ~= nil then return "station", t end

    -- 制作站：只认白名单，不做名字猜测
    if CRAFT_ITEMS[t] then return "craft", t end

    local buff = item_int(F.buffType, slot)
    if buff > 0 and item_bool(F.consumable, slot) then
        -- 食物：WellFed 系列
        if FOOD_BUFF[buff] then return "food", t end
        -- 药剂：武器浸附
        if FLASK_BUFF[buff] then return "flask", t end
        -- 增益药水：排除回血/回魔
        local hl = item_int(F.healLife, slot)
        local hm = item_int(F.healMana, slot)
        if hl <= 0 and hm <= 0 then return "buffpot", t end
    end

    return "misc", t
end

-- ==========================================================================
-- 容器操作
-- ==========================================================================

local MAX_PER_SLOT = 9999

-- 往指定分区放：返回没放下的剩余数量
function D.add(section, id, count)
    if not id or id <= 0 or not count or count <= 0 then return count end
    local pool = D.pools[section]
    local cap = D.CAPS[section]
    if not pool or not cap then return count end

    local left = count

    -- 先叠到已有的同类格子上
    for i = 1, cap do
        if left <= 0 then break end
        local s = pool[i]
        if s and s.id == id and s.stack < MAX_PER_SLOT then
            local add = math.min(left, MAX_PER_SLOT - s.stack)
            s.stack = s.stack + add
            left = left - add
        end
    end

    -- 再占空格
    for i = 1, cap do
        if left <= 0 then break end
        if not pool[i] then
            local add = math.min(left, MAX_PER_SLOT)
            pool[i] = { id = id, stack = add }
            left = left - add
        end
    end

    if left ~= count then D.dirty = true end
    return left
end

-- 所有分区已用格数之和
function D.total_used()
    local n = 0
    for _, sec in ipairs(D.SECTIONS) do
        n = n + D.section_used(sec.key)
    end
    return n
end

-- 背包里还有没有这个大背包
function D.count_by_class(cls)
    return D.section_used(cls)
end

-- ==========================================================================
-- 手持收纳（保底通道）
-- 背包数组读不到时，至少还能靠「手持物品 → 点收纳」一个个搬
-- ==========================================================================

function D.held_item(player)
    local ok, it = pcall(function()
        local pt = patch.get_type("Terraria", "Player")
        if not pt then return nil end
        local prop = patch.get_property(pt, "HeldItem")
        if not prop then return nil end
        local getter = patch.property_get_method(prop)
        if not getter then return nil end
        local v = patch.invoke(getter, player)
        if v and v ~= false then return v end
        return nil
    end)
    if ok then return it end
    return nil
end

function D.collect_held(player)
    if not need_fields() then return 0, "Item 字段读不到" end
    local it = D.held_item(player)
    if not it then return 0, "读不到手持物品" end

    local t = item_int(F.type, it)
    if t <= 0 then return 0, "手上是空的" end
    local stack = item_int(F.stack, it)
    if stack <= 0 then return 0, "数量为 0" end

    -- 手持也要先分类，进对应分区
    local cls, ct = D.classify_slot(it)
    if not cls or ct <= 0 then
        cls = "misc"
    end
    local left = D.add(cls, t, stack)
    if left < stack then
        pcall(patch.set_field_value, F.stack, it, left, "int32")
        if left <= 0 then
            pcall(patch.set_field_value, F.type, it, 0, "int32")
        end
        D.save()
        return stack - left, nil
    end
    return 0, "容器满了"
end

-- ==========================================================================
-- 持久化
-- ==========================================================================

function D.save()
    local out = { "v2" }
    for _, sec in ipairs(D.SECTIONS) do
        local pool = D.pools[sec.key]
        for i = 1, sec.cap do
            local s = pool[i]
            if s then
                out[#out + 1] = string.format("%s|%d|%d|%d", sec.key, i, s.id, s.stack)
            end
        end
    end
    pcall(mod.write_file, SAVE_NAME, table.concat(out, "\n"))
    D.dirty = false
end

function D.load()
    if D.loaded then return end
    D.loaded = true
    local ok, txt = pcall(mod.read_file, SAVE_NAME)
    if not ok or type(txt) ~= "string" or txt == "" then return end
    for _, sec in ipairs(D.SECTIONS) do D.pools[sec.key] = {} end

    local migrated = 0
    for line in txt:gmatch("[^\r\n]+") do
        -- 新格式：section|index|id|stack
        local sec, i, id, n = line:match("^(%a+)|(%d+)|(%d+)|(%d+)$")
        if sec and D.pools[sec] then
            local idx = tonumber(i)
            if idx and idx >= 1 and idx <= D.CAPS[sec] then
                D.pools[sec][idx] = { id = tonumber(id), stack = tonumber(n) }
            end
        else
            -- 旧格式（一格一拍，没有分区）：读到就按分类重新归位
            local oi, oid, on = line:match("^(%d+)|(%d+)|(%d+)$")
            if oi then
                local idnum = tonumber(oid)
                local cnt = tonumber(on)
                if idnum and idnum > 0 and cnt and cnt > 0 then
                    local key = D.classify_id(idnum) or "misc"
                    D.add(key, idnum, cnt)
                    migrated = migrated + 1
                end
            end
        end
    end
    if migrated > 0 then
        D.save()
    end
end

-- ==========================================================================
-- 物品名字
-- ==========================================================================

local name_cache = {}
local name_miss = {}    -- id -> 取名字失败次数
local SELF_NAME = {}    -- 本模组注册的物品 id -> 名字

-- 注册物品后调用：把 id 和名字记进来，列表里就不会显示成 ID:xxxx
function D.reg_self(id, nm)
    if type(id) == "number" and id > 0 and type(nm) == "string" and nm ~= "" then
        SELF_NAME[id] = nm
        name_cache[id] = nm
    end
end

-- 调静态方法拿字符串。patch.invoke 第 2 参是 obj（静态方法传 nil），
-- 之前只传了 id，等于把 id 当成 obj、实参少一个 → 永远拿不到 → 显示「物品#ID」。
local function call_str(m, id)
    if not m then return nil end
    -- ① 标准静态调用：obj = nil
    local ok, v = pcall(patch.invoke, m, nil, id)
    if ok then local s = to_str(v); if s then return s end end
    -- ② 某些封装会把静态方法当实例方法
    ok, v = pcall(patch.invoke, m, id)
    if ok then local s = to_str(v); if s then return s end end
    return nil
end

-- 调静态方法拿对象（LocalizedText 之类）
local function call_obj(m, id)
    if not m then return nil end
    local ok, v = pcall(patch.invoke, m, nil, id)
    if ok and v and v ~= false then return v end
    ok, v = pcall(patch.invoke, m, id)
    if ok and v and v ~= false then return v end
    return nil
end

-- 取 LocalizedText.Value
local function loc_value(loc)
    if not loc then return nil end
    local okT, ltT = pcall(patch.get_type, "Terraria.Localization", "LocalizedText")
    if not okT or not ltT then return nil end
    local prop = patch.get_property(ltT, "Value")
    if not prop then return nil end
    local g = patch.property_get_method(prop)
    if not g then return nil end
    local ok, s = pcall(patch.invoke, g, loc)
    if ok then return to_str(s) end
    return nil
end

-- ⓪ 最可靠：造一个临时 Item 实例，读它的 Name 属性
--    游戏界面显示的名字就是它，语言切换也会自动跟随
local function name_by_instance(id)
    local ok, inst = pcall(D.make_item, id)
    if not ok or not inst then return nil end
    local okT, t = pcall(patch.get_type, "Terraria", "Item")
    if not okT or not t then return nil end
    -- Item.Name 在不同版本里可能是属性（表达式体）也可能是字段，两种都试
    local prop = patch.get_property and patch.get_property(t, "Name")
    if prop then
        local g = patch.property_get_method and patch.property_get_method(prop)
        if g then
            local ok2, s = pcall(patch.invoke, g, inst)
            if ok2 then
                local r = to_str(s)
                if r then return r end
            end
        end
    end
    local fld = patch.get_field and patch.get_field(t, "Name")
    if fld then
        local ok3, s = pcall(patch.get_field_value, fld, inst, "object")
        if ok3 then
            local r = to_str(s)
            if r then return r end
        end
    end
    return nil
end

-- PE/IL2CPP 上反射读到的"字符串"往往是 userdata 句柄，必须用 patch.string_value 转换
local function to_str(v)
    if type(v) == "string" then return (v ~= "" and v or nil) end
    if v ~= nil and patch.string_value then
        local ok, s = pcall(patch.string_value, v)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

-- 物品中文名（多层降级，失败不缓存，下次再试）
function D.item_name(id)
    if not id or id <= 0 then return "?" end
    local own = SELF_NAME[id]
    if own then return own end
    local c = name_cache[id]
    if c then return c end

    -- ① 先查内置表：O(1)、无反射开销、PE 上最稳
    local nm = CN_TABLE[id]
    -- ② 表里没有（mod 自定义物品）再走反射
    if not nm then nm = name_by_instance(id) end

    local okLang, langT = pcall(patch.get_type, "Terraria", "Lang")
    if okLang and langT then
        -- ① GetItemNameValue(int) -> string
        if not nm then
            nm = call_str(patch.get_method(langT, "GetItemNameValue", 1), id)
        end

        -- ② GetItemName(int) -> LocalizedText -> .Value
        if not nm then
            nm = loc_value(call_obj(patch.get_method(langT, "GetItemName", 1), id))
        end

        -- ③ 英文内部名兜底：ItemID.Search[id] -> "IronBar"
        if not nm then
            local ok3, v3 = pcall(function()
                local t = patch.get_type("Terraria.ID", "ItemID")
                if not t then return nil end
                local f = patch.get_field(t, "Search")
                if not f then return nil end
                local dct = patch.get_field_value(f, nil, "object")
                if not dct then return nil end
                return patch.dictionary_get_value(dct, id, "int32", "string")
            end)
            if ok3 and type(v3) == "string" and v3 ~= "" then nm = v3 end
        end
    end

    if nm then
        name_cache[id] = nm
        return nm
    end
    -- 没拿到名字：第三方模组物品可能游戏本体就没给名字。
    -- 不要每帧重试（name_by_instance 内部会 new_instance + SetDefaults，代价高），
    -- 试满 3 次落缓存，直接用 ID 显示。
    name_miss[id] = (name_miss[id] or 0) + 1
    if name_miss[id] >= 3 then
        name_cache[id] = "ID " .. tostring(id)
    end
    return "ID " .. tostring(id)
end

-- 物品对应的 buffType（0 = 不加 buff）
local buff_cache = {}

function D.item_buff(id)
    if not id or id <= 0 then return 0 end
    local c = buff_cache[id]
    if c then return c end
    -- 静态表优先：由 PC 1.4.5.8 源码解析出来的原版全量表，命中就零开销返回。
    -- 反射那条路要 new_instance + SetDefaults，手机上经常读不到；
    -- 而且旧代码读到 0 也会缓存成 0，导致整批药水永久失效 —— 这是药水袋不生效的根因。
    local sb = BUFF_TABLE[id]
    if sb and sb > 0 then
        buff_cache[id] = sb
        return sb
    end
    local inst = D.make_item(id)
    local b = 0
    if inst and fields_ready then
        b = item_int(f.buffType, inst)
    end
    if b > 0 then buff_cache[id] = b end   -- 只缓存成功结果
    return b
end

-- ==========================================================================
-- 按 id 分类（容器里只存 id，需要造临时 Item 读属性，结果做缓存）
-- ==========================================================================

local class_cache = {}

function D.classify_id(id)
    if not id or id <= 0 then return nil end
    local c = class_cache[id]
    if c then return c end
    local inst = D.make_item(id)
    local cls = nil
    if inst then
        cls = D.classify_slot(inst)
    end
    if not cls then
        if not inst then return "misc" end  -- 造不出实例就不缓存，下次再试
        cls = "misc"
    end
    class_cache[id] = cls
    return cls
end

-- ==========================================================================
-- 收纳：把背包里符合条件的物品搬进容器
--   only_classed = true 时只收 药水/旗帜/增益站，杂物留在背包
-- ==========================================================================

function D.collect(player, only_classed)
    local inv, n = D.inv(player)
    if not inv then return 0, "背包读不到：" .. tostring(D.inv_debug) end

    local moved = 0
    for i = 0, n - 1 do
        local slot = patch.array_at(inv, i)
        if slot then
            local cls, t = D.classify_slot(slot)
            -- 被玩家收藏（物品栏左上角的星标）一律不动
            local fav = F.favorited and item_bool(F.favorited, slot) or false
            -- only_classed = true 时只收各类专用区，物品区（misc）不动
            if cls and t > 0 and not fav and (not only_classed or cls ~= "misc") then
                local stack = item_int(F.stack, slot)
                if stack > 0 then
                    -- 按分类放进对应分区的池子；该分区满了就留在背包里
                    local left = D.add(cls, t, stack)
                    if left < stack then
                        moved = moved + (stack - left)
                        pcall(patch.set_field_value, F.stack, slot, left, "int32")
                        if left <= 0 then
                            pcall(patch.set_field_value, F.type, slot, 0, "int32")
                        end
                    end
                end
            end
        end
    end

    if moved > 0 then D.save() end
    return moved, nil
end

-- ==========================================================================
-- 取出：把容器第 index 格取出 count 个塞回背包
-- ==========================================================================

function D.take_out(player, section, index, count)
    local pool = D.pools[section]
    if not pool then return 0 end
    local s = pool[index]
    if not s then return 0 end

    local inv, n = D.inv(player)
    if not inv then return 0 end

    local want = math.min(count or s.stack, s.stack)
    local left = want

    -- ① 先叠到背包里已有的同类物品上
    for i = 0, n - 1 do
        if left <= 0 then break end
        local slot = patch.array_at(inv, i)
        if slot and item_int(F.type, slot) == s.id then
            local st = item_int(F.stack, slot)
            local mx = item_int(F.maxStack, slot)
            if mx <= 0 then mx = 999 end
            if st < mx then
                local add = math.min(left, mx - st)
                pcall(patch.set_field_value, F.stack, slot, st + add, "int32")
                left = left - add
            end
        end
    end

    -- ② 再找空格子放
    for i = 0, n - 1 do
        if left <= 0 then break end
        local slot = patch.array_at(inv, i)
        if slot and item_int(F.type, slot) == 0 then
            local inst = D.make_item(s.id)
            if not inst then break end
            local mx = item_int(F.maxStack, inst)
            if mx <= 0 then mx = 999 end
            local put = math.min(left, mx)
            pcall(patch.set_field_value, F.stack, inst, put, "int32")
            local ok = pcall(patch.array_set, inv, i, inst)
            if ok then left = left - put end
        end
    end

    local got = want - left
    if got > 0 then
        s.stack = s.stack - got
        if s.stack <= 0 then pool[index] = nil end
        D.save()
    end
    return got
end

D.ID = ID
D.F = F

return D