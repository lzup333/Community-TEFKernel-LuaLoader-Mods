-- 物品：材料、召唤物、四系武器、饰品。
local q = mod.quickapi
local ids = require("cr_ids")
local util = require("cr_util")
local npcs = require("cr_npcs")
local buffs = require("cr_buffs")
local projectiles = require("cr_projectiles")
local HB = require("cr_hookbox")

local M = {}
-- 上一次开袋的时间，用来避免 use 回调和双击路径重复发奖。
local bag_opened_at = -100
local function bag_just_opened()
    return (os.clock() - bag_opened_at) < 0.5
end

local function use_beacon(player)
    local x, y = util.position("Player", player)
    if not x then return end
    npcs.spawn_golem(x + 220, y - 80)
end

local function use_summon(player, item)
    if npcs.boss_alive() then
        mod.info("碎晶之链：晶核领主已经在了")
        return
    end
    local ok, reason = npcs.spawn_boss(player)
    if not ok then
        mod.warn("碎晶之链：召唤失败 " .. tostring(reason))
        return
    end
    -- 原版没帮我们扣（这套内核上 consumable 不生效，宝藏袋也是手动扣的）
    if item then
        local stack = q.get_field_value("Terraria", "Item", "stack", item, "int32")
        if stack and stack > 0 then
            q.set_field_value("Terraria", "Item", "stack", item, stack - 1, "int32")
        end
    end
end

local function can_summon(player)
    return not npcs.boss_alive()
end

-- 自己发一发晶弹：朝鼠标方向，生成后立刻登记保活
local function fire_crystal_round(player, item)
    local px, py = util.player_center(player)
    if not px then return end
    local mx, my = util.mouse_world()
    local dx, dy
    if mx then
        dx, dy = mx - px, my - py
    else
        dx, dy = 1, 0
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then dx, dy = 1, 0 else dx, dy = dx / len, dy / len end

    local speed = 16
    local ok, v = pcall(q.get_field_value, "Terraria", "Item", "shootSpeed", item, "float")
    if ok and type(v) == "number" and v > 0 then speed = v end

    local damage = util.config_number("rifle_damage", 20)
    local index = util.spawn_projectile(ids.projectile.shot,
            px + dx * 24, py + dy * 24, dx * speed, dy * speed, damage, 255)
    if not index then return end
    util.track_custom_projectile(index, {
        damage = damage, knockBack = 1.0, width = 12, height = 12,
        timeLeft = 120, penetrate = 0, owner = 255,
        friendly = true, hostile = false, tileCollide = true,
    }, 120)
end

-- 弹药：不交给原版的 useAmmo（那会让发射的弹幕完全跟随弹药），
-- 改成自己挑第一种子弹、自己扣，并按弹药种类决定打什么。
-- 注意 ItemID.MusketBall 与 AmmoID.Bullet 都是 97，判断子弹种类要用 Item.type。
local MUSKET_BALL = 97      -- 火枪子弹：转成水晶弹
-- 89 = 水晶弹（命中分裂成 3 片碎片 90）。
-- 弹幕伤害直接取武器面板伤害，所以想把铳打出去的弹调弱，改它自己的 damage 就行
-- （配置项 rifle_damage），不会影响别人用水晶弹。
local CRYSTAL_ROUND = 89
-- false = 火枪子弹打原版水晶弹（89）。
-- 试过自己发射自家 CrystalShot：弹幕能出来，但会丢掉原版的举枪朝向和伤害加成
-- （shoot = 0 之后 ItemCheck 里那套计算整段不跑，手动补 itemRotation 实测无效）。
-- 收益不抵成本，先退回原版，等内核给出能直接生成自定义弹幕的接口再换。
local USE_CUSTOM_BULLET = false
local AMMO_BULLET = 97      -- 弹药分类：子弹
local INV_LAST = 58

-- 返回 (弹药类型, 弹药自己的弹幕 ID)；没有子弹返回 nil
local function pick_ammo(player)
    local inventory = q.get_object("Terraria", "Player", "inventory", player)
    if not inventory then return nil end
    local last = math.min(mod.patch.array_length(inventory) - 1, INV_LAST)
    for i = 0, last do
        local item = mod.patch.array_at(inventory, i)
        if item then
            local ammo = q.get_field_value("Terraria", "Item", "ammo", item, "int32")
            local stack = q.get_field_value("Terraria", "Item", "stack", item, "int32")
            if ammo == AMMO_BULLET and stack and stack > 0 then
                local type_id = q.get_field_value("Terraria", "Item", "type", item, "int32")
                local shoot = q.get_field_value("Terraria", "Item", "shoot", item, "int32")
                return type_id, shoot, i
            end
        end
    end
    return nil
end

-- 有没有子弹（只检查，不改状态）。出错时放行——宁可打出去也不要变成点不动。
local function can_use_rifle(player, item)
    local ok, ammo_type = pcall(pick_ammo, player)
    if not ok then return true end
    return ammo_type ~= nil
end

-- 诊断用：最后一次开火选了什么弹
M.last_shot = nil

-- 每次开火：定这一发打什么，再扣掉一发子弹
local function use_rifle(player, item)
    local ammo_type, ammo_shoot, slot = pick_ammo(player)
    if not ammo_type or not slot then
        M.last_shot = { ammo = nil, slot = nil }
        return
    end

    local shot
    if ammo_type == MUSKET_BALL and USE_CUSTOM_BULLET and q.projectile_id(ids.projectile.shot) then
        -- 自己发射：关掉原版发射，手动生成自家晶弹（这样才能拿到下标去保活）
        shot = 0
        q.set_field_value("Terraria", "Item", "shoot", item, shot, "int32")
        M.last_shot = { ammo = ammo_type, slot = slot, shot = "CrystalShot" }
        fire_crystal_round(player, item)
    else
        -- 其他子弹按弹药自带的弹幕发射
        shot = (ammo_type == MUSKET_BALL) and CRYSTAL_ROUND or (ammo_shoot or CRYSTAL_ROUND)
        q.set_field_value("Terraria", "Item", "shoot", item, shot, "int32")
        M.last_shot = { ammo = ammo_type, slot = slot, shot = shot }
    end

    local inventory = q.get_object("Terraria", "Player", "inventory", player)
    local ammo_item = inventory and mod.patch.array_at(inventory, slot)
    if not ammo_item then return end
    local stack = q.get_field_value("Terraria", "Item", "stack", ammo_item, "int32")
    if stack and stack > 0 then
        q.set_field_value("Terraria", "Item", "stack", ammo_item, stack - 1, "int32")
    end
end

-- 宝藏袋发奖：两件不重复的装备 + 一把碎晶 + 12 金 50 银。
-- 不含扣物品，扣东西交给原版（TryOpenContainer 拿到 true 后自己 stack--）。
local function grant_treasure_bag(player)
    local x, y = util.position("Player", player)
    if not x then return end
    local pool = {
        ids.item.blade, ids.item.hammer, ids.item.spear, ids.item.rifle,
        ids.item.staff, ids.item.minion_staff,
        ids.item.charm, ids.item.bracer, ids.item.cloak, ids.item.eye, ids.item.badge,
    }
    local first = pool[math.random(#pool)]
    local second = pool[math.random(#pool)]
    -- 随机到同一件时重摇，保证稳定开出两件（原版 boss 袋也是这个做法）
    local guard = 0
    while second == first and guard < 8 do
        second = pool[math.random(#pool)]
        guard = guard + 1
    end
    util.drop_item(first, x + 24, y, 1)
    if second ~= first then
        util.drop_item(second, x - 24, y, 1)
    end
    util.drop_item(ids.item.shard, x, y, 8 + math.random(0, 4))
    -- 12 金 50 银：原版宝藏袋也是按面额拆着掉的（73 = 金币，72 = 银币）
    util.drop_item(73, x + 32, y, 12)
    util.drop_item(72, x + 32, y, 50)
end

-- 宝藏袋：开出两件不重复的装备 + 一把碎晶
local function use_treasure_bag(player, item)
    -- 正常路径是双击 → 原版容器逻辑 → 我们接管；这里只是兜底
    if bag_just_opened() then return end
    if item then
        local stack = q.get_field_value("Terraria", "Item", "stack", item, "int32")
        if stack and stack > 0 then
            q.set_field_value("Terraria", "Item", "stack", item, stack - 1, "int32")
        end
    end
    bag_opened_at = os.clock()
    grant_treasure_bag(player)
end

-- 随从：上限跟随玩家召唤栏（maxMinions），用自定义弹幕承载
local function minion_limit(player)
    local limit = q.get_field_value("Terraria", "Player", "maxMinions", player, "int32")
    if type(limit) ~= "number" then return 1 end
    return limit
end

function M.dismiss_minions()
    local minion_id = q.projectile_id(ids.projectile.minion)
    if not minion_id or minion_id < 0 then return 0 end
    local list = q.get_object("Terraria", "Main", "projectile")
    if not list then return 0 end

    local kill_method = q.method("Terraria", "Projectile", "Kill", 0)
    local removed = 0
    for i = 0, mod.patch.array_length(list) - 1 do
        local proj = mod.patch.array_at(list, i)
        if proj then
            local active = q.get_field_value("Terraria", "Projectile", "active", proj, "bool")
            local type_id = q.get_field_value("Terraria", "Projectile", "type", proj, "int32")
            if active and type_id == minion_id then
                -- 先断保活（按 spec 批量断，避免 whoAmI 对不上），再杀
                util.untrack_spec(projectiles.MINION_SPEC)
                -- 再直接调 Kill；失败就退化成标记失效
                local ok = false
                if kill_method then
                    local ok_call = pcall(q.call, kill_method, proj)
                    ok = ok_call
                end
                if not ok then
                    pcall(q.set_field_value, "Terraria", "Projectile", "active", proj, false, "bool")
                    pcall(q.set_field_value, "Terraria", "Projectile", "timeLeft", proj, 0, "int32")
                end
                removed = removed + 1
            end
        end
    end
    return removed
end

local function use_minion_staff(player)
    local minion_id = q.projectile_id(ids.projectile.minion)
    if not minion_id or minion_id < 0 then
        mod.warn("碎晶之链：碎晶随从弹幕未就绪，稍后再试")
        return
    end
    local limit = minion_limit(player)
    local current = util.count_projectile(minion_id)
    if current >= limit then
        mod.info(("碎晶随从已满 %d/%d"):format(current, limit))
        return
    end
    local x, y = util.position("Player", player)
    if not x then return end
    local who = q.get_field_value("Terraria", "Player", "whoAmI", player, "int32") or 255
    local angle = (current + 1) * (math.pi * 2 / limit)
    local index = util.spawn_projectile(ids.projectile.minion,
            x + math.cos(angle) * 60, y - 40 + math.sin(angle) * 30, 0, 0, 0, who)
    if index then
        projectiles.reset_minion_state(index)
        -- 登记保活：自定义弹幕会被内核每帧重置，不登记大约 1 秒就不动了
        util.track_custom_projectile(index, projectiles.MINION_SPEC, projectiles.MINION_LIFE)
        -- 挂自家「碎晶精魂」：buff 栏里能看到，双击取消时随从会自己散去
        local buff_id = buffs.runtime_id(buffs.minion_name)
        if buff_id then
            local add_buff = q.method("Terraria", "Player", "AddBuff", 2)
                    or q.method("Terraria", "Player", "AddBuff", 3)
            if add_buff then
                pcall(q.call, add_buff, player, buff_id, 3600)
            end
        end
        mod.info(("碎晶随从已召唤 %d/%d"):format(current + 1, limit))
    else
        local info = util.spawn_info()
        mod.warn("碎晶之链：碎晶随从召唤失败 " .. tostring(info.fail or "未知原因"))
    end
end


-- ===== 重铸（哥布林工匠）=====
-- 哥布林只看这几张表：PrefixLegacy.ItemSets.* 和 ItemID.Sets.CanGetPrefixes。
-- 内核靠 register_item 的 prefixes 字段置位，但那份"名字→类别"的映射不透明，
-- 这里直接自己写表，写完再读回来校验。
local REFORGE = {
    { label = "晶刃",   name = ids.item.blade,        field = "SwordsHammersAxesPicks" },
    { label = "之锤",   name = ids.item.hammer,       field = "SwordsHammersAxesPicks" },
    { label = "长枪",   name = ids.item.spear,        field = "SpearsMacesChainsawsDrillsPunchCannon" },
    { label = "步枪",   name = ids.item.rifle,        field = "GunsBows" },
    { label = "法杖",   name = ids.item.staff,        field = "Magic" },
    { label = "权杖",   name = ids.item.minion_staff, field = "Summon" },
    { label = "护符",   name = ids.item.charm,        field = "CanGetPrefixes" },
    { label = "护腕",   name = ids.item.bracer,       field = "CanGetPrefixes" },
    { label = "披风",   name = ids.item.cloak,        field = "CanGetPrefixes" },
    { label = "之眼",   name = ids.item.eye,          field = "CanGetPrefixes" },
    { label = "徽章",   name = ids.item.badge,        field = "CanGetPrefixes" },
}

local reforge_report = {}

-- 静态 bool[] 字段：两种取值方式都试一遍（不同平台参数要求不一样）
local function static_array(field)
    if not field then return nil end
    local ok, arr = pcall(mod.patch.get_field_value, field, nil, "object")
    if ok and arr then return arr end
    ok, arr = pcall(mod.patch.get_field_value, field, nil)
    if ok and arr then return arr end
    return nil
end

local function inner_type(parent, name)
    if not parent then return nil end
    local ok, value = pcall(mod.patch.get_inner_type, parent, name)
    if ok then return value end
    return nil
end

local function member_field(parent, name)
    if not parent then return nil end
    local ok, value = pcall(mod.patch.get_field, parent, name)
    if ok then return value end
    return nil
end

local function prefix_fields()
    local out = {}
    local legacy = q.type("Terraria.GameContent.Prefixes", "PrefixLegacy")
    if legacy then
        local sets = inner_type(legacy, "ItemSets")
        if sets then
            for _, name in ipairs({ "SwordsHammersAxesPicks",
                    "SpearsMacesChainsawsDrillsPunchCannon", "GunsBows",
                    "Magic", "Summon" }) do
                local f = member_field(sets, name)
                if f then out[name] = f end
            end
        end
    end
    local item_id_type = q.type("Terraria.ID", "ItemID")
    if item_id_type then
        local sets = inner_type(item_id_type, "Sets")
        if sets then
            local f = member_field(sets, "CanGetPrefixes")
            if f then out.CanGetPrefixes = f end
        end
    end
    return out
end

-- 数组太短（自定义物品 ID 超出原版容量）时，自己造一个大一点的数组写回去
local function grow_flag_array(field, arr, needed)
    local okl, len = pcall(mod.patch.array_length, arr)
    if not (okl and type(len) == "number") then return nil end
    local target = math.max(needed + 256, len + 2048)

    local okc, bigger = pcall(mod.patch.array_create, target, "bool")
    if not (okc and bigger) then return nil end
    for i = 0, len - 1 do
        local okr, value = pcall(mod.patch.array_at, arr, i, "bool")
        if okr and value then
            pcall(mod.patch.array_set, bigger, i, true, "bool")
        end
    end
    local oks = pcall(mod.patch.set_field_value, field, nil, bigger, "object")
    if not oks then return nil end
    return bigger, target
end

-- 写一个 bool[] 的下标；返回 true 或失败原因（短字符串，方便打在聊天框里）
local function write_flag(field, type_id)
    local arr = static_array(field)
    if not arr then return "无数组" end

    local okl, len = pcall(mod.patch.array_length, arr)
    if not (okl and type(len) == "number") then return "无长度" end
    if type_id >= len then
        local bigger = grow_flag_array(field, arr, type_id)
        if not bigger then
            return ("越界%d/%d"):format(type_id, len)
        end
        arr = bigger
    end

    local okw = pcall(mod.patch.array_set, arr, type_id, true, "bool")
    if not okw then return "写失败" end

    local okr, value = pcall(mod.patch.array_at, arr, type_id, "bool")
    if not okr then return "读失败" end
    if value == true then return true end
    return "读回为假"
end

-- 每张表的数组长度（诊断用）
function M.reforge_tables()
    local fields = prefix_fields()
    local out = {}
    for _, name in ipairs({ "SwordsHammersAxesPicks", "GunsBows", "Magic", "Summon",
            "SpearsMacesChainsawsDrillsPunchCannon", "CanGetPrefixes" }) do
        local field = fields[name]
        if not field then
            out[#out + 1] = name .. "=无字段"
        else
            local arr = static_array(field)
            if not arr then
                out[#out + 1] = name .. "=无数组"
            else
                local ok, len = pcall(mod.patch.array_length, arr)
                out[#out + 1] = name .. "=" .. (ok and tostring(len) or "?")
            end
        end
    end
    return out
end

local function apply_reforge_flags()
    reforge_report = {}
    local fields = prefix_fields()
    if not fields.SwordsHammersAxesPicks and not fields.CanGetPrefixes then
        reforge_report.error = "找不到 PrefixLegacy.ItemSets / ItemID.Sets"
        return false
    end

    local all_ok = true
    for i = 1, #REFORGE do
        local entry = REFORGE[i]
        local field = fields[entry.field]
        local type_id = util.item_id_of(entry.name, entry.label)
        local result
        if not field then
            result = "无表"
        elseif not type_id or type_id <= 0 then
            result = "无ID"
        else
            result = write_flag(field, type_id)
        end
        if result ~= true then all_ok = false end
        reforge_report[#reforge_report + 1] = entry.label .. "="
                .. (result == true and "OK" or tostring(result))
    end
    return all_ok
end

local reforge_applied = false

-- 物品 ID 是内核在更晚的阶段分配的（注册当场 q.item_id 还是 nil），
-- 所以不能在这里直接写表，要等 ID 可用了再补。
function M.try_apply_reforge()
    if reforge_applied then return true end
    local probe = util.item_id_of(ids.item.blade, "碎晶刃")
    if not probe or probe <= 0 then return false end
    local all_ok = apply_reforge_flags()
    if not all_ok then return false end        -- 没全写上就继续等，下一帧再试
    reforge_applied = true
    mod.info("碎晶之链：重铸类别已写入")
    return true
end

function M.reforge_report()
    return reforge_report
end

local function schedule_reforge()
    local tries = 0
    local handle
    local ok = pcall(function()
        handle = q.install_hook_postfix("Terraria", "Main", "Update", function()
            tries = tries + 1
            -- 每 30 帧试一次，免得每帧都去碰这些数组
            if tries % 30 == 0 and M.try_apply_reforge() then
                pcall(function() if handle then handle:remove() end end)
            elseif tries > 7200 then
                pcall(function() if handle then handle:remove() end end)
            end
        end, { argc = 1 })
    end)
    if not ok or not handle then
        mod.warn("碎晶之链：重铸类别没排上（Main.Update 钩子失败），重进世界会再试一次")
    end
end

-- ===== 宝藏袋：完全按原版机制接上 =====
-- 原版双击打开袋子是两步（PC 1.4.5.8 源码 Terraria.UI/ItemSlot.cs）：
--   ① ItemSlot 右键判定：if (ItemID.Sets.OpenableBag[type]) → TryOpenContainer
--      ↑ 这一步只认 OpenableBag，不认 BossBag。漏了它双击就毫无反应。
--   ② TryOpenContainer_GrantItems：if (ItemID.Sets.BossBag[type]) → player.OpenBossBag(type)
--      ↑ 这一步才分派到 BossBag 的具体掉落
--   ③ 打开成功后由 ItemSlot 自己 item.stack--（我们不用手动扣）
-- Player.OpenBossBag 内部是 switch(type)，只认原版那几个袋子，自定义 type 进去什么都不会掉。
-- 所以接管点放在 ② —— 比 ③ 更上游，拦下之后原版根本走不到那个 switch。
local function bag_type_id()
    local type_id = util.item_id_of(ids.item.bag, "晶核宝藏袋")
    if type_id and type_id > 0 then return type_id end
    return nil
end
local function mark_bag_sets()
    local type_id = bag_type_id()
    if not type_id then return false end
    local item_id_type = q.type("Terraria.ID", "ItemID")
    if not item_id_type then return false end
    local sets = inner_type(item_id_type, "Sets")
    if not sets then return false end
    local ok_open, ok_boss = false, false
    local f_open = member_field(sets, "OpenableBag")
    if f_open then ok_open = (write_flag(f_open, type_id) == true) end
    local f_boss = member_field(sets, "BossBag")
    if f_boss then ok_boss = (write_flag(f_boss, type_id) == true) end
    return ok_open and ok_boss
end

-- 双击宝藏袋：接管原版打开容器的分派，用时间窗保证只发一次奖。
-- 挂在 ItemSlot.TryOpenContainer_GrantItems 上（TryOpenContainer 内部对每个袋子/箱子都会调它），
-- 拦下后原版就不会再进 Player.OpenBossBag 那个只认原版编号的 switch。
local function bag_grant_once(player)
    if bag_just_opened() then return end
    bag_opened_at = os.clock()
    grant_treasure_bag(player)
end

-- 从任意对象上读 Item.type；不是 Item 就返回 nil
local function read_item_type(obj)
    if obj == nil then return nil end
    local ok, v = pcall(q.get_field_value, "Terraria", "Item", "type", obj, "int32")
    if ok and type(v) == "number" then return v end
    return nil
end

-- 注意：quickapi 的钩子回调签名是官方的 (instance, args, result)，
--       args 是 1 起始的参数表；prefix 返回 true 才是「跳过原方法」。
local function on_grant_items(instance, args)
    local item = args and args[1]
    local player = args and args[2]
    local bag = bag_type_id()
    if not bag or read_item_type(item) ~= bag then return nil end
    bag_grant_once(player)
    -- 跳过原版并返回 true：告诉原版「已经处理完了」，它据此扣掉一个袋子
    return true, true
end

function M.hooks_on()
    local ok, h = pcall(q.install_hook_prefix, "Terraria.UI", "ItemSlot",
            "TryOpenContainer_GrantItems", on_grant_items, { argc = 2 })
    if ok and h then
        HB.add(h)
        return true
    end
    return false
end

-- 标记必须等物品 runtime id 分配完才写得上。
-- register 阶段 q.item_id 拿到的是 -1（内核延后分配），所以照 schedule_reforge 的办法：
-- 挂 Main.Update，每 30 帧重试一次，写成功就卸钩子。
local bag_sets_done = false
local function schedule_bag_sets()
    if bag_sets_done then return end
    local tries = 0
    local handle
    local ok = pcall(function()
        handle = q.install_hook_postfix("Terraria", "Main", "Update", function()
            if bag_sets_done then
                pcall(function() if handle then handle:remove() end end)
                return
            end
            tries = tries + 1
            if tries > 7200 then
                pcall(function() if handle then handle:remove() end end)
                return
            end
            if tries % 30 ~= 0 then return end
            if mark_bag_sets() then
                bag_sets_done = true
                pcall(function() if handle then handle:remove() end end)
            end
        end, { argc = 1 })
    end)
    if not ok or not handle then
        pcall(mod.warn, "碎晶之链：宝藏袋标记没排上（Main.Update 钩子失败）")
    end
end
function M.register()



    q.register_item{
        name = ids.item.shard,
        texture = "CrystalShard.png",
        maxStack = 999, width = 20, height = 20, sacrifice = 100,
        rare = 1, value = 800,
        tooltip = true,
        language = {
            en = { name = "碎晶", tooltip = "从傀儡身上剥下来的活性晶体。" },
            zh = { name = "碎晶", tooltip = "从傀儡身上剥下来的活性晶体。" },
        },
    }

    q.register_item{
        name = ids.item.core,
        texture = "CrystalCore.png",
        maxStack = 99, width = 26, height = 26, sacrifice = 25,
        rare = 4, value = 20000,
        tooltip = true,
        language = {
            en = { name = "晶核", tooltip = "晶核领主的内核，还在微微发烫。" },
            zh = { name = "晶核", tooltip = "晶核领主的内核，还在微微发烫。" },
        },
    }


    q.register_item{
        name = ids.item.bag,
        texture = "CrystalTreasureBag.png",
        maxStack = 9999, width = 30, height = 30, sacrifice = 25,
        useStyle = 4, useTime = 30, useAnimation = 30,
        consumable = true,
        rare = 8, value = 100000,
        expert = true,
        use_sound = "Item1",
        tooltip = true,
        use = use_treasure_bag,
        language = {
            en = { name = "晶核宝藏袋", tooltip = "点击使用或双击打开\n打开后随机获得两件晶核装备和一把碎晶。" },
            zh = { name = "晶核宝藏袋", tooltip = "点击使用或双击打开\n打开后随机获得两件晶核装备和一把碎晶。" },
        },
    }

    q.register_item{
        name = ids.item.beacon,
        texture = "CrystalBeacon.png",
        maxStack = 99, width = 22, height = 22, sacrifice = 25,
        useStyle = 4, useTime = 30, useAnimation = 30,
        consumable = true,
        rare = 2, value = 3000,
        use_sound = "Item1",
        tooltip = true,
        use = use_beacon,
        language = {
            en = { name = "碎晶信标", tooltip = "在身旁召唤一只碎晶傀儡。\n骷髅王倒下后，雪地会自然出现碎晶傀儡" },
            zh = { name = "碎晶信标", tooltip = "在身旁召唤一只碎晶傀儡。\n骷髅王倒下后，雪地会自然出现碎晶傀儡" },
        },
    }

    q.register_item{
        name = ids.item.summon,
        texture = "CrystalCoreSummon.png",
        maxStack = 20, width = 26, height = 26, sacrifice = 10,
        useStyle = 4, useTime = 30, useAnimation = 30,
        consumable = true,
        rare = 5, value = 40000,
        use_sound = "Item1",
        tooltip = true,
        can_use = can_summon,
        use = use_summon,
        language = {
            en = { name = "晶核召唤符", tooltip = "唤醒晶核领主。一次只能召一只。" },
            zh = { name = "晶核召唤符", tooltip = "唤醒晶核领主。一次只能召一只。" },
        },
    }

    -- 近战：晶刃
    q.register_item{
        name = ids.item.blade,
        texture = "CrystalBlade.png",
        damage = 58, knockBack = 6.5, crit = 6,
        useStyle = 1, useTime = 18, useAnimation = 18,
        autoReuse = true, melee = true, maxStack = 1, width = 44, height = 44, sacrifice = 1,
        prefixes = "sword",
        -- 自定义弹幕在内核上生成不了（NewProjectile 会崩/静默失败），改用原版剑气
        shoot = 132, shootSpeed = 10.0,
        rare = 5, value = 120000,
        use_sound = "Item1",
        tooltip = true,
        language = {
            en = { name = "晶刃", tooltip = "挥动时甩出一道晶光。" },
            zh = { name = "晶刃", tooltip = "挥动时甩出一道晶光。" },
        },
    }

    -- 近战：晶核巨锤（慢、重、击退高）
    q.register_item{
        name = ids.item.hammer,
        texture = "CrystalHammer.png",
        damage = 84, knockBack = 9.0, crit = 4,
        useStyle = 1, useTime = 32, useAnimation = 32,
        autoReuse = true, melee = true, maxStack = 1, width = 46, height = 46, sacrifice = 1,
        scale = 1.08,
        rare = 5, value = 140000,
        use_sound = "Item1",
        tooltip = true,
        language = {
            en = { name = "晶核巨锤", tooltip = "挥得慢，被砸中的东西基本就停下来了。" },
            zh = { name = "晶核巨锤", tooltip = "挥得慢，被砸中的东西基本就停下来了。" },
        },
    }

    -- 远程：晶矛
    q.register_item{
        name = ids.item.spear,
        texture = "CrystalSpear.png",
        damage = 44, knockBack = 2.0, crit = 8,
        useStyle = 5, useTime = 22, useAnimation = 22,
        autoReuse = true, ranged = true, maxStack = 1, width = 40, height = 40, sacrifice = 1,

        rare = 5, value = 120000,
        use_sound = "Item5",
        shoot = 90, shootSpeed = 14.0,
        tooltip = true,
        language = {
            en = { name = "晶矛", tooltip = "掷出一根晶矛。" },
            zh = { name = "晶矛", tooltip = "掷出一根晶矛。" },
        },
    }

    -- 远程：晶光铳（快、连射）
    q.register_item{
        name = ids.item.rifle,
        texture = "CrystalRifle.png",
        -- 弹幕伤害 = 这里的 damage；配置项 rifle_damage 可以在不改包的情况下调
        damage = util.config_number("rifle_damage", 20),
        knockBack = 1.2, crit = 4,
        useStyle = 5, useTime = 9, useAnimation = 9,
        autoReuse = true, ranged = true, maxStack = 1, width = 48, height = 24, sacrifice = 1,

        rare = 5, value = 130000,
        use_sound = "Item5",
        -- 只有火枪子弹会被转成水晶弹（89，命中分裂），其他子弹按原样发射
        can_use = can_use_rifle,
        use = use_rifle,
        shoot = 89, shootSpeed = 16.0,
        tooltip = true,
        language = {
            en = { name = "晶光铳", tooltip = "消耗子弹。火枪子弹会变成水晶弹，命中分裂成追踪碎片。\n其他子弹按原样打出。" },
            zh = { name = "晶光铳", tooltip = "消耗子弹。火枪子弹会变成水晶弹，命中分裂成追踪碎片。\n其他子弹按原样打出。" },
        },
    }

    -- 魔法：晶光杖
    q.register_item{
        name = ids.item.staff,
        texture = "CrystalStaff.png",
        damage = 46, knockBack = 3.0, crit = 4,
        useStyle = 5, useTime = 24, useAnimation = 24,
        autoReuse = true, magic = true, mana = 10, maxStack = 1, width = 40, height = 40, sacrifice = 1,
        shoot = 156, shootSpeed = 11.0,
        rare = 5, value = 130000,
        use_sound = "Item1",
        tooltip = true,
        language = {
            en = { name = "晶光杖", tooltip = "射出一道能穿透的晶光。" },
            zh = { name = "晶光杖", tooltip = "射出一道能穿透的晶光。" },
        },
    }


    -- 召唤：碎晶权杖
    q.register_item{
        name = ids.item.minion_staff,
        texture = "CrystalSummonStaff.png",
        damage = 24, knockBack = 2.0,
        useStyle = 5, useTime = 30, useAnimation = 30,
        maxStack = 1, width = 40, height = 40, sacrifice = 1,
        rare = 5, value = 130000,
        use_sound = "Item1",
        tooltip = true,
        use = use_minion_staff,
        language = {
            en = { name = "碎晶权杖", tooltip = "召一只小碎晶跟着你，它会自己打怪。召唤栏有几格就能带几只。" },
            zh = { name = "碎晶权杖", tooltip = "召一只小碎晶跟着你，它会自己打怪。召唤栏有几格就能带几只。" },
        },
    }

    -- 饰品
    q.register_item{
        name = ids.item.charm,
        sacrifice = 1,
        width = 28, height = 28,
        texture = "CrystalCoreCharm.png",
        accessory = true, defense = 12,
        rare = 5, value = 80000,
        tooltip = true,
        language = {
            en = { name = "晶核护符", tooltip = "晶核贴着你，替你挡下一些。+12 防御。" },
            zh = { name = "晶核护符", tooltip = "晶核贴着你，替你挡下一些。+12 防御。" },
        },
    }

    q.register_item{
        name = ids.item.bracer,
        sacrifice = 1,
        width = 26, height = 26,
        texture = "CrystalBracer.png",
        accessory = true,
        rare = 5, value = 70000,
        tooltip = true,
        language = {
            en = { name = "碎晶护腕", tooltip = "出手更准。+8% 暴击率。" },
            zh = { name = "碎晶护腕", tooltip = "出手更准。+8% 暴击率。" },
        },
    }

    q.register_item{
        name = ids.item.cloak,
        sacrifice = 1,
        width = 28, height = 28,
        texture = "CrystalCloak.png",
        accessory = true,
        rare = 5, value = 70000,
        tooltip = true,
        language = {
            en = { name = "晶核披风", tooltip = "轻得像没有重量。+12% 移动速度。" },
            zh = { name = "晶核披风", tooltip = "轻得像没有重量。+12% 移动速度。" },
        },
    }

    q.register_item{
        name = ids.item.eye,
        sacrifice = 1,
        width = 26, height = 26,
        texture = "CrystalEye.png",
        accessory = true,
        rare = 5, value = 70000,
        tooltip = true,
        language = {
            en = { name = "晶核之眼", tooltip = "看得见魔力流向。+20 最大魔力。" },
            zh = { name = "晶核之眼", tooltip = "看得见魔力流向。+20 最大魔力。" },
        },
    }

    q.register_item{
        name = ids.item.badge,
        sacrifice = 1,
        width = 26, height = 26,
        texture = "CrystalBadge.png",
        accessory = true,
        rare = 5, value = 90000,
        tooltip = true,
        language = {
            en = { name = "晶核徽章", tooltip = "多带一只随从。" },
            zh = { name = "晶核徽章", tooltip = "多带一只随从。" },
        },
    }


-- 朝向钩子已停用（见 USE_CUSTOM_BULLET 的说明），代码留着备用
    schedule_reforge()
    -- 宝藏袋标记不能在这里直接写：此刻 runtime id 还是 -1，交给定时重试
    schedule_bag_sets()
end
return M
