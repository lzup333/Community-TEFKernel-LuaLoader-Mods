-- afm_fish.lua
-- 渔力与渔获判定，规则对齐原版 Projectile.FishingCheck（TShock 自动钓鱼机插件
-- 也是直接复用这套：水体质量 → 幸运修正 → 五档掷骰 + 宝匣）。
--
-- 本模组在基础渔力上额外乘 1.2（模组设定），其余全部按原版公式走。

local M = {}

local CRATE_BASE = 10       -- 原版宝匣基础概率 %（100 里 < 10）
local CRATE_POTION = 15     -- 宝匣药水额外 +15

-- ==================== 渔力 ====================
-- 原版：基础渔力 = 竿渔力 + 鱼饵力 + fishingSkill（渔具加成）
--      再乘「时间天气倍率」，最后按水量削减、按幸运浮动
function M.power(pole, bait, gear)
    local sum = (pole or 0) + (bait or 0) + (gear or 0)
    if sum <= 0 then return 0 end
    return math.floor(sum)
end

-- 原版 Player.Fishing_GetPowerMultiplier 的完整复刻
--   env = { raining, cloud, day, time, moon, blood }
function M.multiplier(env)
    local v = 1.0
    if not env then return v end
    if env.raining then v = v * 1.2 end
    if (env.cloud or 0) > 0 then v = v * 1.1 end
    local t = env.time or 0
    if env.day then
        if t < 5400 or t > 48600 then v = v * 1.3 end        -- 清晨 / 黄昏
        if t > 16200 and t < 37800 then v = v * 0.8 end      -- 正午
    else
        if t > 6480 and t < 25920 then v = v * 0.8 end       -- 深夜
    end
    local mo = env.moon or 0
    if mo == 0 then v = v * 1.1                              -- 满月
    elseif mo == 1 or mo == 7 then v = v * 1.05
    elseif mo == 3 or mo == 5 then v = v * 0.95
    elseif mo == 4 then v = v * 0.9 end
    if env.blood then v = v * 1.1 end                        -- 血月
    return v
end

-- 原版：需要水量 = 300 × atmo
function M.need_water(atmo)
    if type(atmo) ~= "number" or atmo ~= atmo then atmo = 1 end
    return math.floor(300 * atmo)
end

-- 原版：水质不足时按比例削弱渔力
function M.apply_water(power, waterCells, needWater)
    if power <= 0 then return 0 end
    if type(needWater) ~= "number" or needWater <= 0 then needWater = 300 end
    local quality = (waterCells or 0) / needWater
    if quality < 1 then
        return math.floor(power * quality)
    end
    return power
end

-- 原版：幸运值命中的时候整体浮一次
--   luck < 0：以 |luck| 的概率把渔力乘 0.9~0.6
--   luck > 0：以 luck 的概率把渔力乘 1.1~1.4
function M.apply_luck(power, luck, randf)
    if type(luck) ~= "number" or luck ~= 0 then
        if luck == nil or luck ~= luck then luck = 0 end
    end
    if power <= 0 or luck == 0 then return power end
    local r = randf()
    if luck < 0 then
        if r < -luck then
            power = math.floor(power * (0.9 - randf() * 0.3))
        end
    else
        if r < luck then
            power = math.floor(power * (1.1 + randf() * 0.3))
        end
    end
    return power
end

-- 原版垃圾判定：两次 rand(50) 都大于渔力，且水量不足
-- rand0(n) 返回 0..n-1（对应 Main.rand.Next(n)）
function M.is_junk(power, waterCells, needWater, rand0)
    if (waterCells or 0) >= (needWater or 300) then return false end
    if rand0(50) <= power then return false end
    return rand0(50) > power
end

-- ==================== 五档掷骰（原版 FishingCheck_RollDropLevels）====================
-- rand0(n) → 0..n-1；返回各档位布尔值
function M.levels(power, rand0, cratePotion)
    if type(power) ~= "number" or power <= 0 then power = 1 end

    local num  = math.floor(150 / power)          -- 普通
    local num2 = math.floor(150 * 2 / power)      -- 少见
    local num3 = math.floor(150 * 7 / power)      -- 稀有
    local num4 = math.floor(150 * 15 / power)     -- 极稀有
    local num5 = math.floor(150 * 30 / power)     -- 传说
    local crateP = CRATE_BASE + (cratePotion and CRATE_POTION or 0)

    if num < 2 then num = 2 end
    if num2 < 3 then num2 = 3 end
    if num3 < 4 then num3 = 4 end
    if num4 < 5 then num4 = 5 end
    if num5 < 6 then num5 = 6 end

    return {
        common   = (rand0(num) == 0),
        uncommon = (rand0(num2) == 0),
        rare     = (rand0(num3) == 0),
        veryrare = (rand0(num4) == 0),
        legendary = (rand0(num5) == 0),
        crate    = (rand0(100) < crateP),
    }
end

-- ==================== 渔获物品池 ====================
-- 水环境：按档位给物品；越高档越值钱
local POOL = {
    common    = { 2290, 2297, 2298 },                -- 鲈鱼 / 鳟鱼 / 三文鱼
    uncommon  = { 2299, 2300, 2316, 2301 },          -- 大西洋鳕 / 金枪鱼 / 虾 / 红鲷
    rare      = { 2302, 2320 },                      -- 霓虹脂鲤 / 岩鱼
    veryrare  = { 2452, 4401 },                      -- 鲶鱼 / 比目鱼
    legendary = { 2310, 2311 },                      -- 棱镜鱼 / 花斑猪鱼
}
local JUNK = { 2337, 753, 2339 }                      -- 旧鞋 / 海草 / 铁罐

local CRATE_LOW  = 2334   -- 木匣
local CRATE_MID  = 2335   -- 铁匣
local CRATE_HIGH = 2336   -- 金匣

local function crate_for(power)
    if power >= 100 then return CRATE_HIGH end
    if power >= 50 then return CRATE_MID end
    return CRATE_LOW
end

-- 按档位优先取最稀有命中的那个（原版也是从高到低匹配掉落规则）
-- rand(n) 返回 1..n
function M.pick(lv, power, rand)
    if lv.legendary then return POOL.legendary[rand(#POOL.legendary)] end
    if lv.veryrare  then return POOL.veryrare[rand(#POOL.veryrare)] end
    if lv.rare      then return POOL.rare[rand(#POOL.rare)] end
    if lv.uncommon  then return POOL.uncommon[rand(#POOL.uncommon)] end
    return POOL.common[rand(#POOL.common)]
end

function M.pick_crate(power, rand)
    return crate_for(power)
end

function M.pick_junk(rand)
    return JUNK[rand(#JUNK)]
end

-- ==================== 鱼饵消耗（原版概率）====================
-- 概率 = 1 / (1 + 渔力/6)；有钓具箱再 ×0.8
function M.bait_consume_chance(power, hasTackleBox)
    if type(power) ~= "number" or power < 0 then power = 0 end
    local chance = 1 / (1 + power / 6)
    if hasTackleBox then chance = chance * 0.8 end
    return chance
end

-- ==================== 物品名称 ====================
local NAME = {
    [2290] = "鲈鱼", [2297] = "鳟鱼", [2298] = "三文鱼",
    [2299] = "大西洋鳕鱼", [2300] = "金枪鱼", [2316] = "虾", [2301] = "红鲷鱼",
    [2302] = "霓虹脂鲤", [2320] = "岩鱼", [2452] = "鲶鱼", [4401] = "比目鱼",
    [2310] = "棱镜鱼", [2311] = "花斑猪鱼",
    [2337] = "旧鞋", [753] = "海草", [2339] = "铁罐",
    [2334] = "木匣", [2335] = "铁匣", [2336] = "金匣",
}

function M.name_of(itype)
    return NAME[itype] or ("物品" .. tostring(itype))
end

-- ==================== 渔具加成（照抄 TShock 插件默认配置）====================
-- 原插件把渔具放进钓鱼机的箱子里，按这张表折算「永久渔力加成」。
local EXTRA = {
    [2375] = 10,                        -- 钓具箱
    [2374] = 10,                        -- 渔夫耳环
    [2373] = 10,                        -- 强化鱼线
    [3721] = 10,                        -- 渔夫工具包
    [5064] = 10,                        -- 防熔岩渔具袋
    [5139] = 10,                        -- 钓鱼浮标
    [5140] = 10, [5141] = 10,           -- 发光浮标（星 / 熔岩）
    [5142] = 10, [5143] = 10,           -- 发光浮标（氪 / 氙）
    [5144] = 10, [5145] = 10,           -- 发光浮标（氩 / 紫）
    [5146] = 10,                        -- 发光浮标（彩虹）
    [2367] = 5, [2368] = 5, [2369] = 5, -- 渔夫帽 / 背心 / 裤
    [2356] = 15,                        -- 宝匣药水
}
local EXTRA_NAME = {
    [2375] = "钓具箱", [2374] = "渔夫耳环", [2373] = "强化鱼线",
    [3721] = "渔夫工具包", [2356] = "宝匣药水",
    [5064] = "防熔岩渔具袋",
    [5139] = "钓鱼浮标", [5140] = "发光浮标", [5141] = "熔岩浮标",
    [5142] = "氪浮标", [5143] = "氙浮标", [5144] = "氩浮标",
    [5145] = "紫浮标", [5146] = "彩虹浮标",
    [2367] = "渔夫帽", [2368] = "渔夫背心", [2369] = "渔夫裤",
}

M.POTION = 2354          -- 钓鱼药水
M.CHUM   = 4608          -- 鱼饵桶

-- 机器里是否装了宝匣药水（2356）：永久 +15 渔力，同时宝匣概率 +15%
function M.has_crate_potion(gears)
    for _, g in ipairs(gears or {}) do
        if g == 2356 then return true end
    end
    return false
end
M.POTION_BONUS = 20      -- 原插件「钓鱼药水加成」
M.CHUM_BONUS   = 10      -- 原插件「鱼饵桶加成」
M.POTION_FRAMES = 60 * 60 * 8    -- 8 分钟
M.CHUM_FRAMES   = 60 * 60 * 10   -- 10 分钟

function M.extra_of(itype)
    return EXTRA[itype] or 0
end

function M.extra_name(itype)
    return EXTRA_NAME[itype] or ("物品" .. tostring(itype))
end

-- gears: { type, type, ... }；返回加成合计与明细文本
function M.extra_sum(gears, potion_frames, chum_frames)
    local sum, names = 0, {}
    for _, t in ipairs(gears or {}) do
        local v = EXTRA[t]
        if v then
            sum = sum + v
            names[#names + 1] = string.format("%s+%d", EXTRA_NAME[t] or ("物品" .. t), v)
        end
    end
    if (potion_frames or 0) > 0 then
        sum = sum + M.POTION_BONUS
        names[#names + 1] = string.format("钓鱼药水+%d", M.POTION_BONUS)
    end
    if (chum_frames or 0) > 0 then
        sum = sum + M.CHUM_BONUS
        names[#names + 1] = string.format("鱼饵桶+%d", M.CHUM_BONUS)
    end
    return sum, table.concat(names, " ")
end

return M