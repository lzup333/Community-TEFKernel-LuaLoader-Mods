-- ============================================================================
--  env.lua —— 环境采样器（只读）
--  目标：Terraria 1.4.5.8 手机版 + LuaLoader（api_version 1）
--
--  ⚠ 手机版关键差异（v1.1.0 修的就是这个）：
--    手机版 Player 的地带标记（ZoneJungle / ZoneSnow / ZoneRockLayerHeight …）
--    不是字段，而是 **属性**（get_ZoneJungle / get_ZoneRockLayerHeight …）。
--    之前按字段 get_field 读，全部拿到 nil，于是永远回落到「森林 / 岩层」。
--    现在每个地带标记按「先字段、再属性」两种方式解析；属性用
--    patch.invoke(getter, player) 读取（冒险手记等模组已验证这条路）。
--
--  读取内容：
--    · 层深：ZoneUnderworldHeight / ZoneSkyHeight / ZoneRockLayerHeight /
--            ZoneDirtLayerHeight / ZoneOverworldHeight（属性），读不到时按
--            position.Y/16 与 worldSurface / rockLayer / maxTilesY 兜底。
--    · 群系：腐化 / 猩红 / 神圣 / 丛林 / 雪原 / 蘑菇 / 地下沙漠 / 沙漠 /
--            地牢 / 神庙 / 蜂巢 / 花岗岩 / 大理石 / 海滩 / 陨石 / 墓地 / 微光。
--    · 事件：入侵（含剩余量）/ 血月 / 日食 / 南瓜月 / 霜月 / 史莱姆雨。
--  输出只有「环境 / 群系 / 事件」三项，正好对应聊天栏一行播报。
-- ============================================================================

local E = {}

E.VERSION = "1.1.2"

E.layerProbes = {
    { "ZoneUnderworldHeight", "地狱" },
    { "ZoneSkyHeight",        "太空" },
    { "ZoneRockLayerHeight",  "洞穴" },
    { "ZoneDirtLayerHeight",  "地下" },
    { "ZoneOverworldHeight",  "地表" },
}

E.biomeProbes = {
    { "ZoneCorrupt",           "腐化之地" },
    { "ZoneCrimson",           "猩红之地" },
    { "ZoneHallow",            "神圣之地" },
    { "ZoneJungle",            "丛林" },
    { "ZoneSnow",              "雪原" },
    { "ZoneGlowshroom",        "蘑菇洞" },
    { "ZoneUndergroundDesert", "地下沙漠" },
    { "ZoneDesert",            "沙漠" },
    { "ZoneDungeon",           "地牢" },
    { "ZoneLihzhardTemple",    "丛林神庙" },
    { "ZoneHive",              "蜂巢" },
    { "ZoneGranite",           "花岗岩洞" },
    { "ZoneMarble",            "大理石洞" },
    { "ZoneBeach",             "海滩" },
    { "ZoneMeteor",            "陨石区" },
    { "ZoneGraveyard",         "墓地" },
    { "ZoneShimmer",           "微光之地" },
}

local INVASION_NAMES = {
    [1] = "哥布林入侵",
    [2] = "雪人军团",
    [3] = "海盗入侵",
    [4] = "火星暴乱",
}

-- ---------------------------------------------------------------------------
-- 句柄解析
-- ---------------------------------------------------------------------------
local function find_field(p, type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local ok, f = pcall(p.get_field, cur, name)
        if ok and f then return f end
        local okp, parent = pcall(p.get_parent, cur)
        cur = (okp and parent) or nil
        guard = guard + 1
    end
    return nil
end

-- 地带标记：字段与属性两种形态都收进来，读取时属性优先
-- （手机版是属性；桌面/其它版本可能是字段；两套都留着最稳）
local function zone_handle(p, T_Player, name)
    local f = find_field(p, T_Player, name)

    local getter = nil
    local okp, prop = pcall(p.get_property, T_Player, name)
    if okp and prop then
        local okm, g = pcall(p.property_get_method, prop)
        if okm then getter = g end
    end

    if not f and not getter then return nil end
    return { f = f, prop = getter, name = name }
end

-- ---------------------------------------------------------------------------
-- E.attach(patch, T_Main, T_Player) -> ctx
-- ---------------------------------------------------------------------------
function E.attach(p, T_Main, T_Player)
    local ctx = { p = p, f = {}, z = {} }

    local function mf(name)
        local ok, f = pcall(find_field, p, T_Main, name)
        if ok then return f end
        return nil
    end

    ctx.f.myplayer          = mf("myPlayer")
    ctx.f.playerarray       = mf("player")
    ctx.f.gamemenu          = mf("gameMenu")
    ctx.f.invasiontype      = mf("invasionType")
    ctx.f.invasionsize      = mf("invasionSize")
    ctx.f.invasionsizestart = mf("invasionSizeStart")
    ctx.f.bloodmoon         = mf("bloodMoon")
    ctx.f.eclipse           = mf("eclipse")
    ctx.f.pumpkin           = mf("pumpkinMoon")
    ctx.f.snowmoon          = mf("snowMoon")
    ctx.f.slimerain         = mf("slimeRain")
    ctx.f.worldsurface      = mf("worldSurface")
    ctx.f.rocklayer         = mf("rockLayer")
    ctx.f.maxtilesy         = mf("maxTilesY")

    -- position / whoAmI / active 都定义在 Entity 基类上，先按父类链找，
    -- 找不到再显式问一次 Entity 类型。
    local T_Entity = nil
    pcall(function() T_Entity = p.get_type("Terraria", "Entity") end)
    local function entity_field(name)
        local f = find_field(p, T_Player, name)
        if f then return f end
        if T_Entity then
            local ok, ef = pcall(p.get_field, T_Entity, name)
            if ok then return ef end
        end
        return nil
    end
    ctx.f.position = entity_field("position")
    ctx.f.whoami   = entity_field("whoAmI")
    ctx.f.active   = entity_field("active")

    -- 地带标记
    for _, probe in ipairs(E.layerProbes) do
        local name = probe[1]
        ctx.z[name] = zone_handle(p, T_Player, name)
    end
    for _, probe in ipairs(E.biomeProbes) do
        local name = probe[1]
        ctx.z[name] = zone_handle(p, T_Player, name)
    end

    return ctx
end

-- ---------------------------------------------------------------------------
-- 读值
-- ---------------------------------------------------------------------------
local function rd(p, f, inst, ty)
    if not f then return nil end
    local ok, v = pcall(p.get_field_value, f, inst, ty)
    if ok then return v end
    return nil
end

local function rd_num(p, f, inst, ...)
    local types = { ... }
    for _, ty in ipairs(types) do
        local v = rd(p, f, inst, ty)
        if type(v) == "number" then return v end
    end
    return nil
end

local function rd_zone(p, z, inst)
    if not z then return nil end
    -- 属性优先：手机版只有属性；桌面版属性若不存在会走下面的字段分支
    if z.prop then
        local ok, v = pcall(p.invoke, z.prop, inst)
        if ok and type(v) == "boolean" then return v end
    end
    if z.f then
        return rd(p, z.f, inst, "bool")
    end
    return nil
end

local function rd_vec(p, f, inst)
    if not f then return nil, nil end
    local ok, x, y = pcall(p.get_field_vec2, f, inst)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- 主采样
-- ---------------------------------------------------------------------------
function E.read(ctx, inst)
    local p = ctx.p
    local f = ctx.f

    local v = { zones = {}, biomes = {}, events = {} }

    local px, py = rd_vec(p, f.position, inst)
    if type(px) == "number" and type(py) == "number" then
        v.posX = px / 16
        v.posY = py / 16
    end

    for name, z in pairs(ctx.z) do
        v.zones[name] = rd_zone(p, z, inst)
    end

    -- 层深
    for _, probe in ipairs(E.layerProbes) do
        if v.zones[probe[1]] == true then
            v.layer = probe[2]
            break
        end
    end
    if not v.layer and type(v.posY) == "number" then
        local surface = rd_num(p, f.worldsurface, nil, "double", "float")
        local rock    = rd_num(p, f.rocklayer, nil, "double", "float")
        local maxY    = rd(p, f.maxtilesy, nil, "int32")
        if type(surface) == "number" and v.posY < surface then
            v.layer = "地表"
        elseif type(rock) == "number" and v.posY < rock then
            v.layer = "地下"
        elseif type(maxY) == "number" and v.posY < maxY - 200 then
            v.layer = "洞穴"
        else
            v.layer = "地狱"
        end
    end
    v.layer = v.layer or "未知"

    -- 群系
    for _, probe in ipairs(E.biomeProbes) do
        if v.zones[probe[1]] == true then
            v.biomes[#v.biomes + 1] = probe[2]
        end
    end
    if #v.biomes == 0 then
        if v.layer == "地表" then
            v.biomes[1] = "森林"
        elseif v.layer == "地下" or v.layer == "洞穴" then
            v.biomes[1] = "岩层"
        else
            v.biomes[1] = "无"
        end
    end

    -- 事件
    local function add_event(name, kind)
        v.events[#v.events + 1] = { name = name, kind = kind }
    end
    local invasion = rd(p, f.invasiontype, nil, "int32")
    if type(invasion) == "number" and invasion > 0 then
        local nm = INVASION_NAMES[invasion] or ("入侵 #" .. math.floor(invasion))
        local size  = rd(p, f.invasionsize, nil, "int32")
        local start = rd(p, f.invasionsizestart, nil, "int32")
        if type(size) == "number" and type(start) == "number" and start > 0 then
            local left = math.floor(size)
            if left < 0 then left = 0 end
            nm = nm .. " " .. left .. "/" .. math.floor(start)
        end
        add_event(nm, "invasion")
    end
    if rd(p, f.bloodmoon, nil, "bool") == true then add_event("血月", "blood") end
    if rd(p, f.eclipse, nil, "bool") == true then add_event("日食", "eclipse") end
    if rd(p, f.pumpkin, nil, "bool") == true then add_event("南瓜月", "pumpkin") end
    if rd(p, f.snowmoon, nil, "bool") == true then add_event("霜月", "snowmoon") end
    if rd(p, f.slimerain, nil, "bool") == true then add_event("史莱姆雨", "slime") end

    local evNames = {}
    for _, e in ipairs(v.events) do evNames[#evNames + 1] = e.name end
    v.eventStr = #evNames > 0 and table.concat(evNames, "、") or "无"

    -- 去重签名：只包含会被播报的三项
    v.sig = table.concat({
        table.concat(v.biomes, "/"),
        v.layer,
        v.eventStr,
    }, "|")

    return v
end

E.INVASION_NAMES = INVASION_NAMES

return E
