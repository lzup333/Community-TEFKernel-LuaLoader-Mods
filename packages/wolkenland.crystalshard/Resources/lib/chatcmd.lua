-- 聊天指令：/crystal boss 召唤 Boss、/crystal golem 喊傀儡、/crystal hp 看血量。
-- 拦截方式：postfix 钩 ChatCommandProcessor.ProcessIncomingMessage 与
-- ChatHelper.SendChatMessageFromClient，从 ChatMessage.Text 读文本。
local q = mod.quickapi
local util = require("util")
local npcs = require("npcs")
local ids = require("ids")
local recipes = require("recipes")
local guide = require("guide")
local items = require("items")
local buffs = require("buffs")
local projectiles = require("projectiles")

local M = {}

local new_text, get_message_text, message_text_field

local function resolve_chat()
    new_text = q.method("Terraria", "Main", "NewText", 5)
            or q.method("Terraria", "Main", "NewText", 4)
            or q.method("Terraria", "Main", "NewText")

    local message_type = q.type("Terraria.Chat", "ChatMessage")
    if message_type then
        get_message_text = q.method("Terraria.Chat", "ChatMessage", "get_Text", 0)
        message_text_field = q.field("Terraria.Chat", "ChatMessage", "<Text>k__BackingField")
    end
end

-- 按方法真实的参数个数传参：多传一个会越界写入（内核按 param_count 分配槽位）
local function param_count(method)
    local ok, n = pcall(mod.patch.method_param_count, method)
    if ok and type(n) == "number" then return n end
    return nil
end

local function show(text)
    if not new_text then return end
    local message = mod.patch.string_create(text)
    if not message then return end
    local count = param_count(new_text)
    if count == 5 then
        pcall(q.call, new_text, message, 150, 226, 255, false)
    elseif count == 4 then
        pcall(q.call, new_text, message, 150, 226, 255)
    elseif count == 2 then
        pcall(q.call, new_text, message, false)
    else
        pcall(q.call, new_text, message)
    end
end

local function read_message_text(message)
    if not message then return nil end
    if get_message_text then
        local ok, str = pcall(q.call, get_message_text, message)
        if ok and str then
            local value = mod.patch.string_value(str)
            if value then return value end
        end
    end
    if message_text_field then
        local ok, value = pcall(q.get_field_value, "Terraria.Chat", "ChatMessage",
                "<Text>k__BackingField", message, "string")
        if ok then return value end
    end
    return nil
end

local HELP = "[碎晶] /crystal boss 召唤晶核领主 · /crystal golem [数量] 召唤傀儡 · /crystal hp 看 Boss 血量 · /crystal test 试生成一只傀儡 · /crystal diag 诊断弹幕 · /crystal t_npc|t_proj|t_buff 查原版 API · /crystal cproj / cproj2 测自定义弹幕 · /crystal texinfo 查纹理数组 · /crystal projinfo 查内核是否原生支持自定义弹幕 · /crystal buff 给自己挂晶核侵蚀 · /crystal bufftime 查精魂心跳 · /crystal dismiss 解散随从 · /crystal reforge 查重铸状态 · /crystal gun 查铳的弹药 · /crystal music [曲名/编号] 换战斗曲 · /crystal guide 查碎晶/晶核能做什么 · /配方 名称 查某物品怎么合成 · /gave 名称 [数量] 直接给物品"

local function command_boss()
    if npcs.boss_alive() then
        show("[碎晶] 晶核领主已经在场上了，先把它打完")
        return
    end
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local ok, reason = npcs.spawn_boss(player)
    if ok then
        show("[碎晶] 晶核领主来了")
    else
        show("[碎晶] 召唤失败：" .. tostring(reason))
    end
end

local function command_golem(args)
    local count = 1
    if args and args ~= "" then
        count = tonumber(args) or 1
        count = math.max(1, math.min(10, math.floor(count)))
    end
    local player, index = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local x, y = util.position("Player", player)
    for i = 1, count do
        npcs.spawn_golem(x + 200 + i * 40, y - 60)
    end
    show(("[碎晶] 召唤了 %d 只碎晶傀儡"):format(count))
end

-- 最小验证：只生成一只傀儡，确认自建的 NewNPC 路径通了
local function command_test()
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local x, y = util.position("Player", player)
    local index = npcs.spawn_golem(x + 120, y)
    if index then
        show(("[碎晶] 测试生成成功，Main.npc 下标 %s"):format(tostring(index)))
    else
        show("[碎晶] 测试生成失败，看日志里的警告")
    end
end

-- 诊断：只读状态，不实际生成弹幕（生成那一步会崩，不能放在诊断里）
-- ===== 最小复现：把三个易崩 API 拆开单独测 =====
local add_buff_method, buff_resolved

local function resolve_add_buff()
    if buff_resolved then return end
    buff_resolved = true
    add_buff_method = q.method("Terraria", "Player", "AddBuff", 2)
            or q.method("Terraria", "Player", "AddBuff", 3)
            or q.method("Terraria", "Player", "AddBuff")
end

local function command_t_npc()
    local player = util.local_player()
    if not player then show("[碎晶] 找不到本机玩家"); return end
    local x, y = util.position("Player", player)
    local index, reason = npcs.spawn(1, x + 120, y)   -- 原版史莱姆
    if index then
        show(("[碎晶] t_npc 成功，下标 %s"):format(tostring(index)))
    else
        show("[碎晶] t_npc 失败：" .. tostring(reason))
    end
end

local function command_t_proj()
    local player = util.local_player()
    if not player then show("[碎晶] 找不到本机玩家"); return end
    local x, y = util.position("Player", player)
    local index = util.spawn_vanilla_projectile(1, x + 40, y, 8, 0, 10, 255)  -- 原版木箭
    local info = util.spawn_info()
    if index then
        show(("[碎晶] t_proj 成功，下标 %s（%s）"):format(tostring(index), tostring(info.mode)))
    else
        show("[碎晶] t_proj 失败：" .. tostring(info.fail or "未知"))
    end
end

-- 碎晶精魂的体检：buff 的 update 心跳有没有在跳、剩余时间查得到吗
local function command_bufftime()
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local id = buffs.runtime_id(buffs.minion_name)
    local beat = buffs.minion_heartbeat or 0
    local left = id and q.player_buff_time(player, id) or 0
    show(("[碎晶] 精魂 id=%s 心跳=%d 剩余=%s"):format(
            tostring(id), beat, tostring(left)))
    show("[碎晶] 等 2 秒再敲一次：心跳涨了说明 update 在跑；剩余一直是 0 说明 time 查不到")
end

-- 自定义弹幕实测：一次朝右打五发扇形晶刺（看得清楚），之后不管，
-- 靠 Main.Update 的 prefix/postfix 双保险把内核每帧清掉的字段补回来。
local function command_cproj()
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local x, y = util.position("Player", player)

    local spec = {
        damage = 32, knockBack = 3.0, width = 28, height = 28, scale = 1.4,
        timeLeft = 300, penetrate = 0, owner = 255,
        friendly = false, hostile = true, tileCollide = false,
    }
    local spawned = 0
    for i = -2, 2 do
        local index = util.spawn_projectile(ids.projectile.spike,
                x + 70, y, 7, i * 1.0, 32, 255)
        if index then
            util.track_custom_projectile(index, spec, 240)
            spawned = spawned + 1
        end
    end
    local info = util.spawn_info()
    if spawned == 0 then
        show("[碎晶] cproj 生成失败：" .. tostring(info.fail or "未知"))
        return
    end
    show(("[碎晶] cproj 打了 %d 发扇形晶刺（模式=%s，寿命 240 帧），看着屏幕找"):format(
            spawned, tostring(info.mode)))

    local frames = 0
    local handle
    local ok = pcall(function()
        handle = q.install_hook_postfix("Terraria", "Main", "Update", function()
            frames = frames + 1
            if frames == 30 then
                show("[碎晶] cproj 帧30：还看得见吗？看不见就说明绘制这段还是死的")
            end
            if frames >= 30 then
                pcall(function() if handle then handle:remove() end end)
            end
        end, { argc = 1 })
    end)
    if not ok or not handle then
        show("[碎晶] cproj 读数钩子没挂上")
    end
end

-- 内核原生支持探针：生成一枚晶刺，但**不登记保活**，只看它自己活不活。
-- 如果能自己活着、自己在动，说明新内核已经接手，我们的保活机制该关掉
-- （不然会把「命中后被销毁」又救回来，出现打中不消失、一次伤害算好几下）。
local function command_projinfo()
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local x, y = util.position("Player", player)
    local spike = q.projectile_id(ids.projectile.spike)
    local shot = q.projectile_id(ids.projectile.shot)
    local spec = {
        damage = 32, knockBack = 3.0, width = 28, height = 28, scale = 1.4,
        timeLeft = 240, penetrate = 0, owner = 255,
        friendly = false, hostile = true, tileCollide = false,
    }
    local index = util.spawn_projectile(ids.projectile.spike, x + 100, y, 5, 0, 32, 255)
    if index then
        util.track_custom_projectile(index, spec, 240)   -- 已知下标，直接登记更可靠
    end
    local info = util.spawn_info()
    local hits, tracked = require("projectiles").autotrack_stats()
    show(("[碎晶] projinfo：晶刺=%s 晶弹=%s 下标=%s 模式=%s"):format(
            tostring(spike), tostring(shot), tostring(index), tostring(info.mode)))
    local kerr, kerr_last = util.keepalive_stats()
    local list0 = q.get_object("Terraria", "Main", "projectile")
    local my_proj = list0 and index and mod.patch.array_at(list0, index)
    local my_who = my_proj and q.get_field_value("Terraria", "Projectile", "whoAmI", my_proj, "int32")
    show(("[碎晶] 自动登记命中=%s 跟踪中=%s 跟踪下标=%s 生成下标=%s whoAmI=%s 保活出错=%s %s"):format(
            tostring(hits), tostring(tracked), tostring(util.tracked_first_index()),
            tostring(index), tostring(my_who), tostring(kerr),
            kerr_last and ("(" .. kerr_last .. ")") or ""))
    if not index then
        show("[碎晶] 生成失败：" .. tostring(info.fail or "未知"))
        return
    end

    local list = q.get_object("Terraria", "Main", "projectile")
    local function read(field, typ)
        local proj = list and mod.patch.array_at(list, index)
        if not proj then return nil end
        local ok, v = pcall(q.get_field_value, "Terraria", "Projectile", field, proj, typ)
        if ok then return v end
        return nil
    end
    local frames = 0
    local handle
    local ok = pcall(function()
        handle = q.install_hook_postfix("Terraria", "Main", "Update", function()
            frames = frames + 1
            if frames ~= 2 and frames ~= 10 and frames ~= 30 then return end
            show(("[碎晶] projinfo 帧%s active=%s timeLeft=%s"):format(
                    tostring(frames), tostring(read("active", "bool")),
                    tostring(read("timeLeft", "int32"))))
            if frames >= 30 then
                pcall(function() if handle then handle:remove() end end)
            end
        end, { argc = 1 })
    end)
    if not ok or not handle then
        show("[碎晶] projinfo 读数钩子没挂上")
    end
end

-- 自定义弹幕命中测试：把晶刺朝自己脸上打，看血量掉不掉（它 hostile=true，打玩家）
local function command_cproj2()
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local x, y = util.position("Player", player)
    -- 从玩家右边 160 像素处朝左飞，穿自己
    local index = util.spawn_projectile(ids.projectile.spike, x + 160, y, -6, 0, 32, 255)
    local info = util.spawn_info()
    if not index then
        show("[碎晶] cproj2 生成失败：" .. tostring(info.fail or "未知"))
        return
    end
    util.track_custom_projectile(index, {
        damage = 32, knockBack = 3.0, width = 28, height = 28, scale = 1.4,
        timeLeft = 300, penetrate = 0, owner = 255,
        friendly = false, hostile = true, tileCollide = false,
    })

    local life_before = q.get_field_value("Terraria", "Player", "statLife", player, "int32")
    show(("[碎晶] cproj2 已生成 下标=%s 血量=%s，看第 5/20/40 帧"):format(
            tostring(index), tostring(life_before)))

    local frames = 0
    local handle
    local ok = pcall(function()
        handle = q.install_hook_postfix("Terraria", "Main", "Update", function()
            frames = frames + 1
            if frames ~= 5 and frames ~= 20 and frames ~= 40 then return end
            local me = util.local_player()
            local life = me and q.get_field_value("Terraria", "Player", "statLife", me, "int32")
            show(("[碎晶] cproj2 帧%s 血量=%s（起始 %s）"):format(
                    tostring(frames), tostring(life), tostring(life_before)))
            if frames >= 40 then
                pcall(function() if handle then handle:remove() end end)
            end
        end, { argc = 1 })
    end)
    if not ok or not handle then
        show("[碎晶] cproj2 读数失败（Main.Update 钩子没挂上）")
    end
end

-- 贴图数组体检：内核给自定义 type 扩过纹理数组吗？
-- 晶刺看不见（没贴图）时先看这个：Projectile 数组长度要是小于我们的 type，就是没扩。
local function command_texinfo()
    local function array_len(class, field_name)
        local ok, arr = pcall(q.get_field_value, "Terraria.GameContent", class, field_name, nil, "object")
        if not ok or not arr then return nil end
        local ok2, n = pcall(mod.patch.array_length, arr)
        if ok2 and type(n) == "number" then return n end
        return nil
    end

    local spike = q.projectile_id(ids.projectile.spike)
    local item = q.item_id(ids.item.shard)
    show(("[碎晶] type：晶刺=%s 碎晶=%s"):format(tostring(spike), tostring(item)))
    show(("[碎晶] 纹理数组长度：Projectile=%s Item=%s Buff=%s"):format(
            tostring(array_len("TextureAssets", "Projectile")),
            tostring(array_len("TextureAssets", "Item")),
            tostring(array_len("TextureAssets", "Buff"))))

    local main_proj = q.get_object("Terraria", "Main", "projectile")
    local main_item = q.get_object("Terraria", "Main", "item")
    show(("[碎晶] 实体数组长度：Main.projectile=%s Main.item=%s"):format(
            tostring(main_proj and mod.patch.array_length(main_proj)),
            tostring(main_item and mod.patch.array_length(main_item))))
end

local function command_t_buff()
    local player = util.local_player()
    if not player then show("[碎晶] 找不到本机玩家"); return end
    resolve_add_buff()
    if not add_buff_method then
        show("[碎晶] t_buff：找不到 Player.AddBuff")
        return
    end
    local ok, res = pcall(q.call, add_buff_method, player, 1, 300)  -- 原版 1 号 buff
    if ok then
        show("[碎晶] t_buff 调用成功")
    else
        show("[碎晶] t_buff 失败：" .. tostring(res))
    end
end

-- 自定义 Buff 自测：给自己挂「晶核侵蚀」，看 ID 拿不拿得到、减益有没有上
local function command_buff()
    if not buffs.available() then
        show("[碎晶] 当前加载器没有 mod.buff 接口，自定义 Buff 用不了")
        return
    end
    if not buffs.ENABLED then
        show("[碎晶] 自定义 Buff 当前是关着的：内核在加载阶段注册会闪退，等修好再开")
        return
    end
    if not buffs.registered then
        show("[碎晶] 晶核侵蚀没登记上：" .. tostring(buffs.error or "加载阶段没走到"))
        return
    end
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local actual, id = buffs.apply_erosion(player, 600)
    if not actual then
        show("[碎晶] 挂晶核侵蚀失败：" .. tostring(id))
        return
    end

    -- buff 栏为什么不显示：分别看 ID 有没有越界、纹理数组够不够长
    local okc, buff_count = pcall(q.get_field_value, "Terraria.ID", "BuffID", "Count", nil, "int32")
    local okb, buff_tex = pcall(q.get_field_value, "Terraria.GameContent", "TextureAssets",
            "Buff", nil, "object")
    local tex_len = (okb and buff_tex) and mod.patch.array_length(buff_tex) or nil
    show(("[碎晶] Buff id=%s BuffID.Count=%s 纹理数组=%s"):format(
            tostring(id), tostring(okc and buff_count or "?"), tostring(tex_len or "?")))
    show(("[碎晶] 已挂晶核侵蚀 id=%s 时长=%s 剩余=%s"):format(
            tostring(id), tostring(actual), tostring(buffs.time(id, player))))
end

-- 列出已注册物品的 runtime_id，用来确认注册有没有生效、顺序对不对
-- 弹幕侧诊断：列出自定义弹幕 ID，并实测生成一发晶刺
-- 解散全部碎晶随从
local function command_dismiss()
    local items = require("items")
    local removed = items.dismiss_minions()
    show(("已解散 %d 只碎晶随从"):format(removed or 0))
end

local function command_pids()
    local names = {
        "CrystalBeam", "CrystalBolt", "CrystalShot", "CrystalMagicBolt",
        "CrystalMinion", "CrystalMinionShot", "CrystalSpike", "CrystalSpikeRed",
    }
    local parts = {}
    for i = 1, #names do
        local id = q.projectile_id(names[i])
        parts[#parts + 1] = ("%s=%s"):format(names[i]:gsub("Crystal", ""), tostring(id))
    end
    show("[碎晶] " .. table.concat(parts, " "))

    util.prepare_spawner()
    local info = util.spawn_info()
    show(("[碎晶] 接口 method=%s source=%s mode=%s srcmode=%s")
            :format(tostring(info.has_method), tostring(info.has_source),
                    tostring(info.mode), tostring(info.source_mode)))

    -- 统计场上一共还有多少枚我们的弹幕（看是生成了立刻消失，还是活着但没画出来）
    local alive_custom, alive_vanilla = 0, 0
    local custom_id = q.projectile_id(ids.projectile.spike)
    local list = q.get_object("Terraria", "Main", "projectile")
    if list then
        for i = 0, mod.patch.array_length(list) - 1 do
            local proj = mod.patch.array_at(list, i)
            if proj then
                local active = q.get_field_value("Terraria", "Projectile", "active", proj, "bool")
                local type_id = q.get_field_value("Terraria", "Projectile", "type", proj, "int32")
                if active then
                    if type_id == custom_id then
                        alive_custom = alive_custom + 1
                    elseif type_id == 90 then
                        alive_vanilla = alive_vanilla + 1
                    end
                end
            end
        end
    end
    show(("[碎晶] 存活：自定义晶刺 %d 枚 · 原版水晶碎片 %d 枚")
            :format(alive_custom, alive_vanilla))

    local me = util.local_player()
    if me then
        local px, py = util.position("Player", me)
        if px then
            show(("[碎晶] 玩家位置 %d,%d"):format(math.floor(px), math.floor(py)))
        end
    end

    show(("[碎晶] Boss AI 已调用 %d 次 · 当前难度：%s"):format(npcs.ai_calls or 0, npcs.difficulty_name()))

    local last = npcs.last_fire
    if last then
        local pos = last.pos or {}
        show(("[碎晶] Boss 上次发射 %d/%d，失败=%s，位置=%s,%s")
                :format(last.fired or 0, last.want or 0, tostring(last.fail or "无"),
                        tostring(pos[1] and math.floor(pos[1]) or "?"),
                        tostring(pos[2] and math.floor(pos[2]) or "?")))
    else
        show("[碎晶] Boss 还没有发射记录")
    end

    local player = util.local_player()
    if not player then return end
    local x, y = util.position("Player", player)
    local index = util.spawn_projectile(ids.projectile.spike, x + 40, y, 6, 0, 10, 255)
    if index then
        show("[碎晶] 自定义晶刺生成成功，下标 " .. tostring(index))
    else
        show("[碎晶] 自定义晶刺生成失败：" .. tostring(util.spawn_info().fail or "未知"))
    end
end

local function command_items()
    local names = {
        "CrystalShard", "CrystalCore", "CrystalTreasureBag", "CrystalBeacon",
        "CrystalCoreSummon", "CrystalBlade", "CrystalHammer", "CrystalSpear",
        "CrystalRifle", "CrystalStaff", "CrystalSummonStaff", "CrystalCoreCharm",
        "CrystalBracer", "CrystalCloak", "CrystalEye", "CrystalBadge",
    }
    local parts = {}
    for i = 1, #names do
        local id = q.item_id(names[i])
        parts[#parts + 1] = ("%s=%s"):format(names[i]:gsub("Crystal", ""), tostring(id))
    end
    show("[碎晶] " .. table.concat(parts, " "))
end

local function command_music(arg)
    if arg and arg ~= "" then
        local value = tonumber(arg) or arg
        local track = npcs.set_boss_music(value)
        show(("[碎晶] 战斗曲已切到 %s（Boss 在场时生效）"):format(tostring(track)))
        return
    end
    local on, saved = npcs.music_active()
    show(("[碎晶] 战斗曲 %s · 顶上=%s · 进战斗前的曲子=%s"):format(
            tostring(npcs.boss_music_track()), tostring(on), tostring(saved)))
end

local function command_gun()
    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local inventory = q.get_object("Terraria", "Player", "inventory", player)
    local held = inventory and mod.patch.array_at(inventory,
            q.get_field_value("Terraria", "Player", "selectedItem", player, "int32") or 0)
    if not held then
        show("[碎晶] 读不到手持物品")
        return
    end
    local type_id = q.get_field_value("Terraria", "Item", "type", held, "int32")
    local shoot = q.get_field_value("Terraria", "Item", "shoot", held, "int32")
    local use_ammo = q.get_field_value("Terraria", "Item", "useAmmo", held, "int32")
    show(("[碎晶] 手持 id=%s shoot=%s useAmmo=%s"):format(
            tostring(type_id), tostring(shoot), tostring(use_ammo)))

    local last = items.last_shot
    if last then
        show(("[碎晶] 上一发：弹药=%s 槽=%s 打出=%s"):format(
                tostring(last.ammo), tostring(last.slot), tostring(last.shot)))
    else
        show("[碎晶] 还没记录到开火（装弹后对着空地打一发再看）")
    end
end

local function command_reforge()
    local ok = items.try_apply_reforge()
    local report = items.reforge_report()
    if not ok and #report == 0 then
        show("[碎晶] 物品 ID 还没分配，进世界后再试")
        return
    end
    if report.error then
        show("[碎晶] 重铸设置失败：" .. tostring(report.error))
        return
    end
    show("[碎晶] 重铸：" .. table.concat(report, " "))
    show("[碎晶] 表长度：" .. table.concat(items.reforge_tables(), " "))
end

local function command_guide()
    local shard = q.item_id(ids.item.shard)
    local core = q.item_id(ids.item.core)
    show(("[碎晶] 碎晶 %d 项 · 晶核 %d 项"):format(
            #recipes.uses_of(shard), #recipes.uses_of(core)))
    for _, line in ipairs(guide.dump()) do
        show("[碎晶] " .. line)
    end
end

local function command_diag()
    util.prepare_spawner()
    local info = util.spawn_info()
    show(("[碎晶] 接口 method=%s source=%s v2=%s struct=%s")
            :format(tostring(info.has_method), tostring(info.has_source),
                    tostring(info.has_v2), tostring(info.has_struct)))
    show(("[碎晶] 生成模式：" .. tostring(info.mode)))
    if info.fail then
        show("[碎晶] 上次失败：" .. tostring(info.fail))
    end

    items.try_apply_reforge()
    show(("[碎晶] ID 探针：内核=%s 反查=%s"):format(
            tostring(q.item_id(ids.item.blade)),
            tostring(util.item_id_of(ids.item.blade, "碎晶刃"))))
    local music_on, music_saved = npcs.music_active()
    show(("[碎晶] 战斗曲：%s（顶上=%s 原曲=%s）"):format(
            tostring(npcs.boss_music_track()), tostring(music_on), tostring(music_saved)))

    local reforge = items.reforge_report()
    if #reforge > 0 then
        show("[碎晶] 重铸：" .. table.concat(reforge, " "))
    elseif reforge.error then
        show("[碎晶] 重铸设置失败：" .. tostring(reforge.error))
    end

    local st = npcs.shot_stats
    if st then
        show(("[碎晶] Boss 出招：尝试=%d 生成成功=%d 失败=%d 最近失败=%s"):format(
                st.calls, st.spawned, st.failed, tostring(st.last_fail)))
    end

    local st2 = util.stats
    show(("[碎晶] 弹幕登记：登记=%d 取消保活=%d 当前跟踪=%d"):format(
            st2.tracked or 0, st2.untracked or 0, util.tracked_count()))

    local hits, tracked = projectiles.autotrack_stats()
    show(("[碎晶] 自定义弹幕：SetDefaults 命中=%d 跟踪中=%d"):format(hits, tracked))

    local hooks, last = npcs.debug_info()
    show(("[碎晶] 钩子 AI=%s 掉落=%s")
            :format(tostring(hooks.ai), tostring(hooks.loot)))
    show(("[碎晶] 自定义 NPC 注册：傀儡=%s Boss=%s 上次生成：傀儡=%s Boss=%s"):format(
            tostring(hooks.golem), tostring(hooks.boss),
            tostring(last and last.golem or "-"), tostring(last and last.boss or "-")))
    if hooks.golem_error then
        show("[碎晶] 傀儡注册错误：" .. tostring(hooks.golem_error))
    end
    if hooks.boss_error then
        show("[碎晶] Boss 注册错误：" .. tostring(hooks.boss_error))
    end
    if hooks.ai_error then
        show("[碎晶] AI 钩子错误：" .. tostring(hooks.ai_error))
    end

    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
end

local function command_hp()
    local life, max = npcs.boss_health()
    if not life then
        show("[碎晶] 场上没有晶核领主")
        return
    end
    show(("[碎晶] 晶核领主 %d / %d"):format(life, max))
end


local RECIPE_HELP = "[配方] 用法：/配方 名称，例：/配方 碎晶刃"

-- 查「碎晶 / 晶核 能做什么」：玩家很可能拿材料名来问
local function material_uses(query)
    local list = {
        { label = "碎晶", id = q.item_id(ids.item.shard) },
        { label = "晶核", id = q.item_id(ids.item.core) },
    }
    for _, entry in ipairs(list) do
        if entry.id and (entry.label:find(query, 1, true) or query:find(entry.label, 1, true)) then
            return entry
        end
    end
    return nil
end

-- 去掉玩家可能顺手打的全角括号、引号、空白。
-- 注意：Lua 的字符类按字节匹配，多字节标点不能塞进 []，要逐个 gsub。
local STRIP_CHARS = { "（", "）", "(", ")", "「", "」", "『", "』", "《", "》", '"', "'" }
local STRIP_PATTERNS = {}
for i = 1, #STRIP_CHARS do
    STRIP_PATTERNS[i] = STRIP_CHARS[i]:gsub("([%p])", "%%%1")
end

local function clean_query(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("%s", "")
    for i = 1, #STRIP_PATTERNS do
        text = text:gsub(STRIP_PATTERNS[i], "")
    end
    return text
end

local function command_recipe(query)
    query = clean_query(query)
    if query == "" then
        show(RECIPE_HELP)
        return
    end

    -- 先查本模组自己的配方表：不依赖 Lang 能不能取到自定义物品名
    local hits = recipes.find(query)
    local source = "本模组"
    if #hits == 0 then
        -- 再查整张配方表（原版物品也在这儿）
        hits = guide.search(query, 4)
        source = "全部配方"
    end

    if #hits == 0 then
        local material = material_uses(query)
        if material then
            local lines = recipes.uses_of(material.id)
            show(("[配方] %s 能做 %d 项："):format(material.label, #lines))
            local chunk, len = {}, 0
            for i = 1, #lines do
                local name = lines[i]:match("^[^ ]+") or lines[i]
                chunk[#chunk + 1] = name
                len = len + #name + 1
                if len > 26 or i == #lines then
                    show("[配方] " .. table.concat(chunk, " "))
                    chunk, len = {}, 0
                end
            end
            return
        end
        show(("[配方] 没找到「%s」，试试更短的名字"):format(query))
        return
    end

    show(("[配方] %s 命中 %d 条："):format(source, #hits))
    for i = 1, math.min(#hits, 5) do
        show("[配方] " .. hits[i])
    end
end

local last_text, last_time = nil, -10


-- ===== /gave：直接给物品（测试用）=====
local function our_item(query)
    local needle = query:lower()
    local partial
    for key, name in pairs(ids.item) do
        local label = (ids.zh and ids.zh[key]) or key
        if label == query or name:lower() == needle then
            return q.item_id(name), label
        end
        if not partial and (label:find(query, 1, true) or name:lower():find(needle, 1, true)) then
            partial = { name = name, label = label }
        end
    end
    if partial then return q.item_id(partial.name), partial.label end
    return nil
end

-- 英文名走 ItemID.Search.GetId，一下就能查到
local function search_get_id(query)
    local ok, result = pcall(function()
        local search = q.get_object("Terraria.ID", "ItemID", "Search", nil)
        if not search then return nil end
        local m = q.method("Terraria.ID", "SearchBase", "GetId", 1)
        if not m then return nil end
        local okc, id = pcall(q.call, m, search, query)
        if okc and type(id) == "number" and id > 0 then return id end
        return nil
    end)
    if ok then return result end
    return nil
end

-- 中文名（含原版）只能把 Lang 里的名字过一遍；util.item_name 有缓存，第一次慢一点
local function lang_item_scan(query)
    local needle = query:lower()
    for id = 1, 6500 do
        local name = util.item_name(id)
        if name and name:lower():find(needle, 1, true) then
            return id, name
        end
    end
    return nil
end

local function resolve_item(query)
    local number = tonumber(query)
    if number and number > 0 then
        return math.floor(number), ("#" .. tostring(math.floor(number)))
    end

    local id, label = our_item(query)
    if id and id > 0 then return id, label end

    id = search_get_id(query)
    if id then
        return id, util.item_name(id) or query
    end

    id, label = lang_item_scan(query)
    if id then return id, label end
    return nil
end

local function command_give(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        show("[碎晶] 用法：/gave 碎晶刃 [数量]")
        return
    end

    local parts = {}
    for token in text:gmatch("%S+") do parts[#parts + 1] = token end
    local count = 1
    if #parts > 1 and tonumber(parts[#parts]) then
        count = math.max(1, math.min(999, math.floor(tonumber(parts[#parts]))))
        parts[#parts] = nil
    end

    local query = table.concat(parts, "")
    local id, label = resolve_item(query)
    if not id then
        local spaced = table.concat(parts, " ")
        if spaced ~= query then id, label = resolve_item(spaced) end
    end
    if not id then
        show(("[碎晶] 没找到「%s」"):format(query))
        return
    end

    local player = util.local_player()
    if not player then
        show("[碎晶] 找不到本机玩家，先进世界")
        return
    end
    local x, y = util.position("Player", player)
    if not x then
        show("[碎晶] 读不到坐标")
        return
    end

    local ok = util.drop_item(id, x + 8, y, count)
    if ok then
        show(("[碎晶] 给予 %s x%d"):format(tostring(label or id), count))
    else
        show(("[碎晶] 给予失败（id=%s）"):format(tostring(id)))
    end
end

local function handle_text(raw)
    if type(raw) ~= "string" then return end
    local now = os.clock()
    if raw == last_text and (now - last_time) < 0.4 then return end
    last_text, last_time = raw, now
    local command, args = raw:match("^%s*/([^%s]+)%s*(.*)$")
    if not command then return end
    command = command:lower()

    if command == "配方" or command == "合成" or command == "recipe"
            or command == "peifang" or command == "hecheng" then
        command_recipe(args)
        return
    end

    if command == "gave" or command == "give" or command == "给予"
            or command == "gei" then
        command_give(args)
        return
    end

    if command ~= "crystal" and command ~= "cs" then return end

    args = args or ""
    args = args:gsub("%s+$", "")

    if args == "" or args:lower() == "help" then
        show(HELP)
    elseif args:lower() == "boss" or args:lower() == "summon" then
        command_boss()
    elseif args:lower():match("^golem") then
        local rest = args:match("^%a+%s*(.*)$") or ""
        command_golem(rest)
    elseif args:lower() == "t_npc" then
        command_t_npc()
    elseif args:lower() == "t_proj" then
        command_t_proj()
    elseif args:lower() == "cproj" then
        command_cproj()
    elseif args:lower() == "cproj2" then
        command_cproj2()
    elseif args:lower() == "texinfo" then
        command_texinfo()
    elseif args:lower() == "projinfo" then
        command_projinfo()
    elseif args:lower() == "bufftime" then
        command_bufftime()
    elseif args:lower() == "t_buff" then
        command_t_buff()
    elseif args:lower() == "buff" then
        command_buff()
    elseif args:lower() == "dismiss" then
        command_dismiss()
    elseif args:lower() == "pids" then
        command_pids()
    elseif args:lower() == "items" then
        command_items()
    elseif args:lower():match("^music") or args:lower():match("^yinyue") then
        local rest = args:match("^%a+%s*(.*)$") or ""
        command_music(rest)
    elseif args:lower() == "gun" or args:lower() == "qiang" then
        command_gun()
    elseif args:lower() == "reforge" or args:lower() == "cz" then
        command_reforge()
    elseif args:lower() == "guide" or args:lower() == "hint" then
        command_guide()
    elseif args:lower() == "diag" then
        command_diag()
    elseif args:lower() == "test" then
        command_test()
    elseif args:lower() == "hp" then
        command_hp()
    else
        show(HELP)
    end
end

local OUR_COMMANDS = {
    crystal = true, cs = true,
    ["配方"] = true, ["合成"] = true,
    recipe = true, peifang = true, hecheng = true,
    gave = true, give = true, ["给予"] = true, gei = true,
}

local function on_incoming_prefix(instance, args)
    if not args then return false end
    local text = read_message_text(args[1])
    if type(text) ~= "string" then return false end
    local name = text:match("^%s*/([^%s]+)")
    if not name then return false end
    if not OUR_COMMANDS[name:lower()] then return false end
    local client_id = args[2]
    local my_index = util.my_player_index()
    if type(client_id) == "number" and client_id ~= my_index then return false end
    handle_text(text)
    return true
end

local function on_incoming_message(instance, args, result)
    if not args then return end
    local message = args[1]
    local client_id = args[2]
    local my_index = util.my_player_index()
    if type(client_id) == "number" and client_id ~= my_index then return end
    handle_text(read_message_text(message))
end

local function on_send_from_client(instance, args, result)
    if not args then return end
    handle_text(read_message_text(args[1]))
end

function M.register()
    resolve_chat()
    if not new_text then
        mod.warn("碎晶之链：找不到 Main.NewText，聊天指令提示会失效")
    end

    -- 前缀：自家指令自己处理完就吞掉，免得原版再回一句「未知指令」
    local okp = pcall(q.install_hook_prefix, "Terraria.Chat", "ChatCommandProcessor",
            "ProcessIncomingMessage", on_incoming_prefix, { argc = 2 })
    if not okp then
        mod.warn("碎晶之链：聊天指令前缀钩子安装失败，指令仍可执行但原版可能报未知指令")
    end

    local ok = pcall(q.install_hook_postfix, "Terraria.Chat", "ChatCommandProcessor",
            "ProcessIncomingMessage", on_incoming_message, { argc = 2 })
    if not ok then
        mod.warn("碎晶之链：ProcessIncomingMessage 钩子安装失败，/crystal 可能不可用")
    end

    local ok2 = pcall(q.install_hook_postfix, "Terraria.Chat", "ChatHelper",
            "SendChatMessageFromClient", on_send_from_client, { argc = 1 })
    if not ok2 then
        mod.warn("碎晶之链：SendChatMessageFromClient 钩子安装失败（联机指令可能不可用）")
    end
end

return M
