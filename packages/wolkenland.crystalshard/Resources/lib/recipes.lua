-- 合成链：木材 → 信标 → 傀儡 → 碎晶 → 召唤符 → Boss → 晶核 → 全套装备
local q = mod.quickapi
local ids = require("ids")
local util = require("util")

local M = {}

local ANVIL = 16
local WORKBENCH = 18

local WOOD = 9
local GEL = 23
local IRON_BAR = 22

-- 配方清单：/crystal guide 用它反查「材料 → 能做什么」。
-- 手机端内核只补了合成菜单的越界配方，向导列表要自己补（见 guide.lua）。
M.list = {}

local LABEL = {
    [ids.item.shard] = "碎晶",
    [ids.item.core] = "晶核",
    [ids.item.beacon] = "晶核信标",
    [ids.item.summon] = "晶核召唤符",
    [ids.item.blade] = "碎晶刃",
    [ids.item.hammer] = "碎晶锤",
    [ids.item.spear] = "碎晶长枪",
    [ids.item.rifle] = "碎晶步枪",
    [ids.item.staff] = "碎晶法杖",
    [ids.item.minion_staff] = "碎晶权杖",
    [ids.item.charm] = "晶核护符",
    [ids.item.bracer] = "碎晶护腕",
    [ids.item.cloak] = "碎晶披风",
    [ids.item.eye] = "碎晶之眼",
    [ids.item.badge] = "碎晶徽章",
}

local MATERIAL_LABEL = {
    [WOOD] = "木材",
    [GEL] = "凝胶",
    [IRON_BAR] = "铁锭",
}

local STATION_LABEL = {
    [ANVIL] = "铁砧",
    [WORKBENCH] = "工作台",
    [17] = "熔炉",
    [26] = "恶魔祭坛",
}

local function label_of(id, name)
    if name and LABEL[name] then return LABEL[name] end
    if type(id) == "number" and MATERIAL_LABEL[id] then return MATERIAL_LABEL[id] end
    return nil
end

local function runtime_id(v)
    if type(v) == "number" then return v end
    if type(v) == "table" then return runtime_id(v.id or v.name) end
    if type(v) == "string" then
        local id = q.item_id(v)
        if type(id) == "number" and id > 0 then return id end
    end
    return nil
end

local function add(spec)
    M.list[#M.list + 1] = spec
    return q.add_recipe(spec)
end

-- 材料 id -> 用它做的成品（聊天指令用，不依赖界面）
local function mats_summary(spec)
    local parts = {}
    for _, mat in ipairs(spec.materials or {}) do
        local id = runtime_id(mat.id or mat.name)
        local name = type(mat.id) == "string" and mat.id or nil
        local label = label_of(id, name) or tostring(mat.id or mat.name)
        parts[#parts + 1] = ("%sx%d"):format(label, mat.count or 1)
    end
    return table.concat(parts, " ")
end

-- 按登记顺序返回各配方产物的 id（guide.lua 用尾巴下标校验自己的配方）
function M.result_ids()
    local out = {}
    for i = 1, #M.list do
        out[i] = runtime_id(M.list[i].result)
    end
    return out
end

function M.uses_of(material_id, limit)
    local out = {}
    if not material_id or material_id <= 0 then return out end
    for i = 1, #M.list do
        local spec = M.list[i]
        local hit = false
        for _, mat in ipairs(spec.materials or {}) do
            if runtime_id(mat.id or mat.name) == material_id then hit = true break end
        end
        if hit then
            local name = type(spec.result) == "table" and spec.result.id or spec.result
            local count = type(spec.result) == "table" and (spec.result.count or 1) or 1
            local label = label_of(runtime_id(spec.result), name) or tostring(name)
            local station = STATION_LABEL[spec.station]
            out[#out + 1] = ("%s x%d（%s%s）"):format(label, count,
                    station and (station .. " · ") or "", mats_summary(spec))
            if limit and #out >= limit then break end
        end
    end
    return out
end


-- 站台名：本模组常用的几个自己认识，其余交给调用方拼 #id
function M.station(tile_id)
    if type(tile_id) ~= "number" or tile_id < 0 then return nil end
    return STATION_LABEL[tile_id]
end

-- 材料名：优先用本模组的标签，其次 Lang，最后退回 #id
local function material_text(mat)
    local id = runtime_id(mat.id or mat.name)
    local name = type(mat.id) == "string" and mat.id or nil
    local label = label_of(id, name) or util.item_name(id) or ("#" .. tostring(id))
    return ("%sx%d"):format(label, mat.count or 1)
end

-- 一条配方排成一行：碎晶刃 x1 ← 晶核x6 碎晶x12 · 铁砧
local function format_spec(spec, label)
    local count = type(spec.result) == "table" and (spec.result.count or 1) or 1
    local parts = {}
    for _, mat in ipairs(spec.materials or {}) do
        parts[#parts + 1] = material_text(mat)
    end
    local station = STATION_LABEL[spec.station]
    local line = ("%s x%d ← %s"):format(label, count, table.concat(parts, " "))
    if station then line = line .. " · " .. station end
    return line
end

-- 按成品名（中文标签 / 注册名）查本模组配方
function M.find(query)
    local out = {}
    if type(query) ~= "string" or query == "" then return out end
    local needle = query:lower()
    for i = 1, #M.list do
        local spec = M.list[i]
        local name = type(spec.result) == "table" and spec.result.id or spec.result
        local label = label_of(runtime_id(spec.result), name) or tostring(name)
        local key = label:lower()
        local alt = tostring(name):lower()
        if key:find(needle, 1, true) or alt:find(needle, 1, true) then
            out[#out + 1] = format_spec(spec, label)
        end
    end
    return out
end

function M.register()
    add{
        result = { id = ids.item.beacon, count = 2 },
        materials = {
            { id = WOOD, count = 10 },
            { id = GEL, count = 5 },
            { id = ids.item.shard, count = 5 },
        },
        station = WORKBENCH,
    }

    add{
        result = { id = ids.item.summon, count = 1 },
        materials = { { id = ids.item.shard, count = 20 } },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.blade, count = 1 },
        materials = {
            { id = ids.item.core, count = 6 },
            { id = ids.item.shard, count = 12 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.hammer, count = 1 },
        materials = {
            { id = ids.item.core, count = 8 },
            { id = ids.item.shard, count = 14 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.spear, count = 1 },
        materials = {
            { id = ids.item.core, count = 4 },
            { id = ids.item.shard, count = 10 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.rifle, count = 1 },
        materials = {
            { id = ids.item.core, count = 5 },
            { id = ids.item.shard, count = 12 },
            { id = IRON_BAR, count = 3 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.staff, count = 1 },
        materials = {
            { id = ids.item.core, count = 6 },
            { id = ids.item.shard, count = 12 },
        },
        station = ANVIL,
    }


    add{
        result = { id = ids.item.minion_staff, count = 1 },
        materials = {
            { id = ids.item.core, count = 5 },
            { id = ids.item.shard, count = 15 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.charm, count = 1 },
        materials = {
            { id = ids.item.core, count = 5 },
            { id = ids.item.shard, count = 8 },
            { id = IRON_BAR, count = 2 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.bracer, count = 1 },
        materials = {
            { id = ids.item.core, count = 3 },
            { id = ids.item.shard, count = 8 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.cloak, count = 1 },
        materials = {
            { id = ids.item.core, count = 4 },
            { id = ids.item.shard, count = 10 },
            { id = IRON_BAR, count = 2 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.eye, count = 1 },
        materials = {
            { id = ids.item.core, count = 4 },
            { id = ids.item.shard, count = 8 },
        },
        station = ANVIL,
    }

    add{
        result = { id = ids.item.badge, count = 1 },
        materials = {
            { id = ids.item.core, count = 6 },
            { id = ids.item.shard, count = 12 },
        },
        station = ANVIL,
    }
end

return M
