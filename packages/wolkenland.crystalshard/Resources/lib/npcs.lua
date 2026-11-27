-- NPC：TEFKernel 1.4.0 的自定义 NPC 路径会在 NPC.SetDefaults 钩子里空指针崩溃
-- （pc=0，栈在 libtefkernel 的 SetDefaults 处理段），所以这里不再注册自定义 NPC，
-- 改为生成原版生物再改写数值，掉落由 NPC.NPCLoot 钩子补。
local q = mod.quickapi
local ids = require("ids")
local util = require("util")
local buffs = require("buffs")

local M = {}

-- 花岗岩傀儡：石质人形，和"碎晶傀儡"的定位最接近
-- 克苏鲁之眼：有完整二阶段的原版 Boss，用来承载"晶核领主"的战斗
local VANILLA_GOLEM = 482
local VANILLA_BOSS = 4
local VANILLA_SHARD = 89   -- 原版水晶弹：蓝色、直线、射程足够（462 幻影矢配色不搭）
local SKELETRON_HEAD = 35   -- 骷髅王：击败后开始刷新碎晶傀儡

M.GOLEM_TYPE = VANILLA_GOLEM
M.BOSS_TYPE = VANILLA_BOSS

-- 晶核领主的基准数值（难度缩放前）。
-- 血量/接触伤害参照骷髅王（经典：头 4400 血 / 32 接触伤害 / 10 防御）再各加一点；
-- 防御单独拉到 36——16 的时候掉血太快，撑不住一场循环。
-- 专家以上再乘下方 difficulty_scale，和原版同口径。
-- 历史：8000/75/30 → 5500/55/22 → 4000/45/12 → 4800/40/16 → 4800/40/36
local BOSS_SCALE = 1.45             -- 贴图 96px × 1.45 ≈ 140，和骷髅王头一个量级
local BOSS_BASE_LIFE = 4800
local BOSS_BASE_DAMAGE = 40
local BOSS_BASE_DEFENSE = 36

-- 弹幕伤害统一再压一档（保持套路不变，只压数字）
-- v1.2.15 起二阶段不再额外加伤：以前二阶段数字比一阶段高一截，
-- 叠上密集弹幕太顶，现在两阶段基本拉平（只靠射速/弹数体现压迫感）。
local BOSS_SHOT_SCALE = 0.8
-- 弹幕飞行速度也压一档：命中判定没那么急，躲起来有余地
local BOSS_SHOT_SPEED_SCALE = 0.85

-- 出场动画：3 秒，期间无敌、不推进 AI
local SUMMON_FRAMES = 300
local boss_state = {}
local crystal_boss_death   -- 前向声明：死亡演出收尾要用
local begin_summon   -- 定义在下面（出场动画那一段），spawn_boss 要先能引用

-- 只接管「我们召唤出来的」那只 Boss，世界上自然刷的克眼不动
local summoned_boss = {}
local mark_summoned

local new_npc_method, none_source_method, spawner_resolved

local function resolve_spawner()
    if spawner_resolved then return end
    spawner_resolved = true
    none_source_method = q.method("Terraria", "Projectile", "GetNoneSource", 0)
    new_npc_method = q.method("Terraria", "NPC", "NewNPC",
            { params = { "source", "X", "Y", "Type", "Start",
                         "ai0", "ai1", "ai2", "ai3", "Target" } })
            or q.method("Terraria", "NPC", "NewNPC", 10)
    if not new_npc_method then
        mod.warn("碎晶之链：找不到 NPC.NewNPC，生物无法生成")
    end
    if not none_source_method then
        mod.warn("碎晶之链：找不到 Projectile.GetNoneSource，生物可能无法生成")
    end
end

-- 内核的 mod.npc.spawn 会 new 一个没跑构造函数的 EntitySource_SpawnNPC，
-- 这里换成 il2cpp 里现成的 source。
function M.spawn(type_id, x, y)
    resolve_spawner()
    if not new_npc_method then return nil, "找不到 NPC.NewNPC" end
    if not type_id or type_id <= 0 then return nil, "无效生物 ID" end

    local source = util.get_source()
    if not source then return nil, "拿不到 EntitySource" end

    local ok, index = pcall(q.call, new_npc_method, source,
            math.floor(x + 0.5), math.floor(y + 0.5), type_id,
            0, 0.0, 0.0, 0.0, 0.0, 255)
    if not ok then
        mod.warn("碎晶之链：NPC.NewNPC 调用失败 " .. tostring(index))
        return nil, "NewNPC 失败"
    end
    if type(index) ~= "number" or index < 0 then
        return nil, "NewNPC 返回无效下标"
    end
    return index
end

-- ===== 战斗曲 =====
-- 内核没有音频接口（没有 audio_manager，Lua 侧也没有放 ogg 的 API），
-- 所以不能塞自定义音乐文件；能做的是在 Boss 活着时把原版曲目顶上去。
-- 曲名可配置：config.json 的 boss_music（"Boss2" / "Boss3" 或直接写数字）。
local music_state = { active = false, saved = nil, track = nil }

local function music_by_name(name)
    if type(name) ~= "string" or name == "" then return nil end
    local ok, value = pcall(q.get_field_value, "Terraria.ID", "MusicID", name, nil, "int32")
    if ok and type(value) == "number" and value >= 0 then return value end
    return nil
end

function M.boss_music_track()
    if music_state.track then return music_state.track end
    local configured = util.config()["boss_music"]
    local track
    if type(configured) == "number" then
        track = configured
    elseif type(configured) == "string" then
        track = music_by_name(configured) or tonumber(configured)
    end
    -- 石巨人：优先按名字取，取不到用编号兜底（25 = Boss5，石巨人/邪教徒那一档）
    track = track or music_by_name("Golem") or music_by_name("Boss5")
            or music_by_name("Boss4") or 25
    music_state.track = track
    return track
end

local function ensure_boss_music()
    local track = M.boss_music_track()
    if not track then return end
    local ok, current = pcall(q.get_field_value, "Terraria", "Main", "newMusic", nil, "int32")
    if not music_state.active then
        music_state.active = true
        music_state.saved = ok and current or 0
    end
    if not ok or current ~= track then
        pcall(q.set_field_value, "Terraria", "Main", "newMusic", nil, track, "int32")
        -- 一起写 curMusic，免得音频层看到 new≠cur 又重头播一遍
        pcall(q.set_field_value, "Terraria", "Main", "curMusic", nil, track, "int32")
    end
end

local function release_boss_music()
    if not music_state.active then return end
    music_state.active = false
    local saved = music_state.saved or 0
    pcall(q.set_field_value, "Terraria", "Main", "newMusic", nil, saved, "int32")
end

M.release_boss_music = release_boss_music

-- 运行时换曲：给了值就直接覆盖（配置文件读不到 / 想试听时用）
function M.set_boss_music(value)
    if type(value) == "number" and value >= 0 then
        music_state.track = value
    elseif type(value) == "string" then
        music_state.track = music_by_name(value) or tonumber(value) or music_state.track
    end
    music_state.active = false      -- 下一帧重新接管，好让新曲生效
    return music_state.track
end
M.music_active = function() return music_state.active, music_state.saved end

-- 按世界难度缩放到不同数值。Main.GameMode 是属性：0 普通 / 1 专家 / 2 大师 / 3 传奇
local game_mode_getter, game_mode_resolved

local function game_mode()
    if not game_mode_resolved then
        game_mode_resolved = true
        local prop = q.property("Terraria", "Main", "GameMode")
        if prop then
            local ok, getter = pcall(mod.patch.property_get_method, prop)
            if ok and getter then game_mode_getter = getter end
        end
    end
    if game_mode_getter then
        local ok, value = pcall(q.call, game_mode_getter)
        if ok and type(value) == "number" then return value end
    end
    return nil
end

local function difficulty_scale()
    local mode = game_mode()
    if mode == 3 then return 2.5, 1.5 end     -- 传奇
    if mode == 2 then return 1.8, 1.25 end    -- 大师
    if mode == 1 then return 1.35, 1.12 end   -- 专家
    if mode == 0 then return 1.0, 1.0 end     -- 普通
    -- 读不到 GameMode 时退回旧字段
    local master = q.get_field_value("Terraria", "Main", "masterMode", nil, "bool")
    local expert = q.get_field_value("Terraria", "Main", "expertMode", nil, "bool")
    if master then return 1.8, 1.25 end
    if expert then return 1.35, 1.12 end
    return 1.0, 1.0
end

-- 当前难度名（给诊断和提示用）
function M.difficulty_name()
    local mode = game_mode()
    if mode == 3 then return "传奇" end
    if mode == 2 then return "大师" end
    if mode == 1 then return "专家" end
    if mode == 0 then return "普通" end
    return "未知"
end

local function apply_stats(index, life_max, damage, defense)
    local list = q.get_object("Terraria", "Main", "npc")
    local npc = list and mod.patch.array_at(list, index)
    if not npc then return end
    q.set_field_value("Terraria", "NPC", "lifeMax", npc, math.floor(life_max), "int32")
    q.set_field_value("Terraria", "NPC", "life", npc, math.floor(life_max), "int32")
    q.set_field_value("Terraria", "NPC", "damage", npc, math.floor(damage), "int32")
    q.set_field_value("Terraria", "NPC", "defense", npc, math.floor(defense), "int32")
end

M.last_fire = nil

M.last_spawn = { golem = nil, boss = nil }

function M.spawn_golem(x, y)
    local type_id = q.npc_id(ids.npc.golem)
    if type_id and type_id > 0 then
        local index, reason = M.spawn(type_id, x, y)
        if index then
            M.last_spawn.golem = "custom"
            return index
        end
        mod.warn("碎晶之链：碎晶傀儡（自定义）生成失败 " .. tostring(reason))
    end
    -- 按要求：不再退回原版花岗岩傀儡。自定义 NPC 不能用就直接失败，
    -- 失败原因记进 last_spawn 和日志，方便定位内核那边的问题。
    M.last_spawn.golem = "failed"
    M.last_spawn.golem_error = tostring(reason)
    mod.warn("碎晶之链：碎晶傀儡（自定义）生成失败，已按无兜底模式直接放弃：" .. tostring(reason))
    return nil, reason
end

function M.spawn_boss(player)
    local x, y = util.position("Player", player)
    if not x then return false, "找不到玩家位置" end

    local type_id = q.npc_id(ids.npc.boss)
    if type_id and type_id > 0 then
        local index, reason = M.spawn(type_id, x, y - 320)
        if index then
            local hp_scale, dmg_scale = difficulty_scale()
            local multiplier = util.config_number("boss_life_multiplier", 1) * hp_scale
            local list = q.get_object("Terraria", "Main", "npc")
            local npc = list and mod.patch.array_at(list, index)
            if npc then
                local life_max = q.get_field_value("Terraria", "NPC", "lifeMax", npc, "int32")
                        or BOSS_BASE_LIFE
                local scaled = math.floor(life_max * multiplier)
                q.set_field_value("Terraria", "NPC", "lifeMax", npc, scaled, "int32")
                q.set_field_value("Terraria", "NPC", "life", npc, scaled, "int32")
                q.set_field_value("Terraria", "NPC", "damage", npc,
                        math.floor(BOSS_BASE_DAMAGE * dmg_scale), "int32")
                q.set_field_value("Terraria", "NPC", "defense", npc, BOSS_BASE_DEFENSE, "int32")
            end
            M.last_spawn.boss = "custom"
            mark_summoned(index)
            begin_summon(index)
            return true
        end
        mod.warn("碎晶之链：晶核领主（自定义）生成失败 " .. tostring(reason))
    end

    -- 按要求：不再退回原版克苏鲁之眼，生成失败就直接报错
    M.last_spawn.boss = "failed"
    M.last_spawn.boss_error = tostring(reason)
    mod.warn("碎晶之链：晶核领主（自定义）生成失败，已按无兜底模式直接放弃：" .. tostring(reason))
    return false, "晶核领主生成失败：" .. tostring(reason)
end

mark_summoned = function(index)
    local list = q.get_object("Terraria", "Main", "npc")
    local npc = list and mod.patch.array_at(list, index)
    if not npc then return end
    local who = q.get_field_value("Terraria", "NPC", "whoAmI", npc, "int32")
    if type(who) == "number" then
        summoned_boss[who] = true
    end
end

-- 找场上指定原版 type 的生物，返回下标
local function find_by_type(type_id)
    if not type_id or type_id <= 0 then return nil end
    local list = q.get_object("Terraria", "Main", "npc")
    if not list then return nil end
    for i = 0, mod.patch.array_length(list) - 1 do
        local npc = mod.patch.array_at(list, i)
        if npc then
            local active = q.get_field_value("Terraria", "NPC", "active", npc, "bool")
            if active and q.get_field_value("Terraria", "NPC", "type", npc, "int32") == type_id then
                return npc, i
            end
        end
    end
    return nil
end

-- 我们自己注册的 Boss 类型和"退回原版克眼"的类型都要认，
-- 否则自定义 Boss 在场时 boss_alive 会一直返回 false（可以无限召唤）
local function boss_type()
    local custom = q.npc_id(ids.npc.boss)
    if type(custom) == "number" and custom > 0 then return custom end
    return VANILLA_BOSS
end

function M.boss_alive()
    if find_by_type(boss_type()) then return true end
    return find_by_type(VANILLA_BOSS) ~= nil
end

function M.boss_health()
    local npc = find_by_type(boss_type()) or find_by_type(VANILLA_BOSS)
    if not npc then return nil end
    local life = q.get_field_value("Terraria", "NPC", "life", npc, "int32")
    local life_max = q.get_field_value("Terraria", "NPC", "lifeMax", npc, "int32")
    return life, life_max
end

-- NPC.NPCLoot 后置：按原版 type 补我们的掉落
local function npc_loot_postfix(npc)
    if not npc then return end
    local type_id = q.get_field_value("Terraria", "NPC", "type", npc, "int32")
    if type_id == VANILLA_GOLEM then
        local x, y = util.center("NPC", npc)
        local base = util.config_number("shards_per_kill", 3)
        util.drop_item(ids.item.shard, x, y, math.max(1, base + math.random(-1, 1)))
    elseif type_id == SKELETRON_HEAD then
        -- 击败骷髅王后，让碎晶傀儡开始在世界里出现
        local x, y = util.center("NPC", npc)
        local target = util.nearest_player(x, y, 4000)
        if target then
            for i = 1, 3 do
                M.spawn_golem(target.x + math.random(-260, 260), target.y - math.random(80, 220))
            end
            util.notify("骷髅王倒下后，碎晶傀儡开始在附近游荡……")
        end
    elseif type_id == VANILLA_BOSS then
        release_boss_music()
        local who = q.get_field_value("Terraria", "NPC", "whoAmI", npc, "int32")
        if type(who) == "number" then
            summoned_boss[who] = nil
        end
        local x, y = util.center("NPC", npc)
        util.drop_item(ids.item.core, x, y, 3 + math.random(0, 2))
        util.drop_item(ids.item.shard, x, y, 12 + math.random(0, 6))
    end
end

local hook_state = { loot = false, ai = false, golem = false, boss = false, snow = false }

function M.debug_info()
    return hook_state, M.last_spawn
end


-- ===== 原创生物（自定义 NPC）=====
-- 生成走我们自己的 NewProjectile 风格调用：用自建 EntitySource，避免内核那份没跑构造的
local golem_state = {}
M.ai_calls = 0

local function golem_ai(npc)
    local who = q.get_field_value("Terraria", "NPC", "whoAmI", npc, "int32") or -1
    local state = golem_state[who]
    if not state then
        state = { tick = 0, phase = "orbit", angle = math.random() * math.pi * 2, timer = 0 }
        golem_state[who] = state
    end
    state.tick = state.tick + 1
    state.timer = state.timer + 1

    -- 贴身打到玩家：挂 15 秒「晶核侵蚀」。
    -- 接触伤害本身由原版结算，这里只是按距离补一个状态，每 30 帧最多触发一次。
    if state.tick % 30 == 0 then
        local gx, gy = util.center("NPC", npc)
        if gx then
            local victim = util.nearest_player(gx, gy, 90)
            if victim and victim.handle then
                buffs.apply_erosion(victim.handle, buffs.EROSION_FRAMES)
            end
        end
    end

    local cx, cy = util.center("NPC", npc)
    if not cx then return end

    -- 身边没有 Boss 时就按老样子追玩家（野怪形态）
    local boss = nil
    local boss_type = M.boss_alive() and q.npc_id(ids.npc.boss) or nil
    if boss_type and boss_type > 0 then
        boss = find_by_type(boss_type)
        if boss then boss = util.center("NPC", boss) and boss or nil end
    end
    local boss_x, boss_y
    if boss then
        boss_x, boss_y = util.center("NPC", boss)
    end

    if not boss_x then
        -- 野怪形态：慢速靠近玩家
        local target = util.nearest_player(cx, cy, 1400)
        if not target then
            util.move("NPC", npc, 0, 0)
            return
        end
        local dx, dy = target.x - cx, target.y - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1e-3 then len = 1 end
        local vx, vy = q.vec.get("Terraria", "NPC", "velocity", npc)
        vx, vy = vx or 0, vy or 0
        vx = vx + (dx / len * 2.4 - vx) * 0.1
        vy = vy + (dy / len * 2.4 - vy) * 0.1
        util.move("NPC", npc, vx, vy + math.sin(state.tick / 30) * 0.4)
        return
    end

    -- 战斗形态：绕 Boss 旋转 → 每 5 秒直线冲一次玩家 → 飞回 Boss 身边继续转
    local ORBIT_RADIUS = 180
    local ORBIT_PERIOD = 300      -- 5 秒
    local DASH_SPEED = 11
    local DASH_MAX = 95        -- 95 帧 × 11 ≈ 1000 像素的直线冲刺

    if state.phase == "dash" then
        if not state.dash_dx then
            state.phase, state.timer = "orbit", 0
        else
            -- 方向在起冲那一刻就锁死，一路冲到底（不再「靠近玩家就刹车」），
            -- 这样冲过的距离才是完整的直线段。
            state.dash_t = state.dash_t + 1
            util.move("NPC", npc, state.dash_dx * DASH_SPEED, state.dash_dy * DASH_SPEED)
            if state.dash_t >= DASH_MAX then
                state.phase, state.timer = "return", 0
            end
        end
        return
    end

    if state.phase == "return" then
        local dx, dy = boss_x - cx, boss_y - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 200 then
            state.phase, state.timer = "orbit", 0
            state.angle = math.atan(cy - boss_y, cx - boss_x)
        else
            util.move("NPC", npc, dx / len * 7, dy / len * 7)
        end
        return
    end

    -- orbit
    state.angle = (state.angle or 0) + 0.035
    local ox = boss_x + math.cos(state.angle) * ORBIT_RADIUS
    local oy = boss_y + math.sin(state.angle) * ORBIT_RADIUS * 0.65
    local dx, dy = ox - cx, oy - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1 then
        local step = math.min(len, 7)
        util.move("NPC", npc, dx / len * step, dy / len * step)
    else
        util.move("NPC", npc, 0, 0)
    end

    if state.timer >= ORBIT_PERIOD then
        local target = util.nearest_player(cx, cy, 2600)
        if target then
            state.phase = "dash"
            state.timer = 0
            state.dash_t = 0
            local dx, dy = target.x - cx, target.y - cy
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 1 then len = 1 end
            state.dash_dx, state.dash_dy = dx / len, dy / len
        else
            state.timer = 0
        end
    end
end

-- ===== Boss 的攻击套路 =====
-- 从 1.2.40 起打的是自家的「晶刺」（碎晶之链自己的弹幕，配色统一）。
-- 自定义弹幕每帧会被内核重置成 active=false / timeLeft=0，得靠两点：
--   1) util.track_custom_projectile 登记，Main.Update 前后各补一次（位移/命中/绘制）；
--   2) 寿命自己记（timeLeft 被重置，靠它永远不会过期）。
-- 生成失败就退回原版水晶弹 89，保证 Boss 不会哑火。

-- 存活压到 2 秒（120 帧）：自定义弹幕要自己管寿命，太长了同屏会堆一堆
local SHOT_LIFE = 120

-- 1.2.50：对照实验证明「生成时显式登记」在新内核上是好的（1.2.49 实测 active=true），
-- 之前不发弹是自动登记（SetDefaults + whoAmI）记错了下标。这里恢复自定义晶刺。
local USE_CUSTOM_SHOT = true

M.shot_stats = { calls = 0, spawned = 0, failed = 0, last_fail = nil }

local function spawn_shard(x, y, vx, vy, damage, homing)
    M.shot_stats.calls = M.shot_stats.calls + 1
    damage = math.max(1, math.floor(damage * BOSS_SHOT_SCALE))
    vx, vy = vx * BOSS_SHOT_SPEED_SCALE, vy * BOSS_SHOT_SPEED_SCALE

    local index = nil
    if USE_CUSTOM_SHOT then
        index = util.spawn_projectile(ids.projectile.spike, x, y, vx, vy, damage, 255)
    end
    if index then
        util.track_custom_projectile(index, {
            damage = damage, knockBack = 3.0, width = 28, height = 28, scale = 1.4,
            timeLeft = SHOT_LIFE, penetrate = 0, owner = 255,
            friendly = false, hostile = true, tileCollide = false,
            ai0 = homing and 1 or 0,
        }, SHOT_LIFE)
        M.shot_stats.spawned = M.shot_stats.spawned + 1
        return index
    end

    M.shot_stats.failed = M.shot_stats.failed + 1
    M.shot_stats.last_fail = util.spawn_info().fail

    -- 兜底：自定义弹幕这条路出问题时不至于让 Boss 变成木桩
    index = util.spawn_vanilla_projectile(VANILLA_SHARD, x, y, vx, vy, damage, 255)
    if not index then return nil end
    util.make_hostile(index, SHOT_LIFE)
    return index
end

-- 提前量：拿玩家贴图中心 + 玩家速度，按弹速迭代两次
local function lead_point(cx, cy, target, speed)
    local bx, by = util.player_center(target.handle)
    if not bx then bx, by = target.x, target.y end
    local vx, vy = util.player_velocity(target.handle)
    local ax, ay = bx, by
    for _ = 1, 2 do
        local dx, dy = ax - cx, ay - cy
        local dist = math.sqrt(dx * dx + dy * dy)
        local t = dist / math.max(speed, 0.1)
        ax, ay = bx + vx * t, by + vy * t
    end
    return ax, ay
end

-- 朝 (ax, ay) 撒 count 发扇形
local function fire_arc(cx, cy, ax, ay, count, spread, damage, speed, homing)
    local aim = math.atan(ay - cy, ax - cx)
    local fired = 0
    for i = 0, count - 1 do
        local angle = aim - spread * (count - 1) / 2 + spread * i
        if spawn_shard(cx, cy, math.cos(angle) * speed, math.sin(angle) * speed,
                damage, homing) then
            fired = fired + 1
        end
    end
    return fired
end

-- 整圈爆发（环形弹幕）
local function fire_ring(cx, cy, count, damage, speed, offset)
    local fired = 0
    local step = math.pi * 2 / count
    for i = 0, count - 1 do
        local angle = (offset or 0) + i * step
        if spawn_shard(cx, cy, math.cos(angle) * speed, math.sin(angle) * speed, damage) then
            fired = fired + 1
        end
    end
    return fired
end

-- 玩家头顶往下砸
local function fire_rain(target, count, damage, speed)
    local fired = 0
    for _ = 1, count do
        local x = (target.x or 0) + math.random(-340, 340)
        local y = (target.y or 0) - 430 - math.random(0, 140)
        if spawn_shard(x, y, math.random(-20, 20) * 0.1, speed + math.random(0, 15) * 0.05,
                damage) then
            fired = fired + 1
        end
    end
    return fired
end

-- 场上傀儡不超过 3 只
local function summon_golem_near(cx, cy)
    local golem_type = q.npc_id(ids.npc.golem)
    if golem_type and golem_type > 0 and util.count_npc(golem_type) >= 3 then return end
    M.spawn_golem(cx + math.random(-220, 220), cy + math.random(-160, 160))
end

-- 索敌范围拉到 6000（原来 4000），丢了目标也要 20 秒才消失（原来 5 秒），
-- 跑远一点不至于立刻脱战。
local BOSS_AGGRO_RANGE = 6000
local BOSS_LOSE_TARGET_FRAMES = 1200
-- 玩家死了就别让它在场上挂着了，1.5 秒内清掉
local BOSS_DESPAWN_ON_DEATH_FRAMES = 90

local function local_player_dead()
    local player = util.local_player()
    if not player then return false end
    local ok, value = pcall(q.get_field_value, "Terraria", "Player", "dead", player, "bool")
    return ok and value == true
end

-- 清掉这只 Boss 放出去的敌对弹幕，免得玩家复活后还被追着打
local function clear_boss_shots()
    local list = q.get_object("Terraria", "Main", "projectile")
    if not list then return end
    for i = 0, mod.patch.array_length(list) - 1 do
        local proj = mod.patch.array_at(list, i)
        if proj then
            local active = q.get_field_value("Terraria", "Projectile", "active", proj, "bool")
            if active then
                local hostile = q.get_field_value("Terraria", "Projectile", "hostile", proj, "bool")
                local type_id = q.get_field_value("Terraria", "Projectile", "type", proj, "int32")
                if hostile and (type_id == 89 or type_id == 90) then
                    pcall(q.set_field_value, "Terraria", "Projectile", "active", proj, false, "bool")
                end
            end
        end
    end
end

local function despawn_boss(npc, who)
    pcall(q.set_field_value, "Terraria", "NPC", "active", npc, false, "bool")
    if type(who) == "number" then
        boss_state[who] = nil
        summoned_boss[who] = nil
    end
    clear_boss_shots()
    release_boss_music()
    util.notify("晶核领主散去了")
end

-- ===== 召唤动画 =====
-- 视觉用弹幕：90 号水晶碎片，伤害 0、中立（既不伤玩家也不伤怪），只活几十帧。
local function fx_shard(x, y, vx, vy, life)
    local index = util.spawn_vanilla_projectile(90, x, y, vx, vy, 0, 255)
    if not index then return end
    local list = q.get_object("Terraria", "Main", "projectile")
    local proj = list and mod.patch.array_at(list, index)
    if not proj then return end
    pcall(q.set_field_value, "Terraria", "Projectile", "hostile", proj, false, "bool")
    pcall(q.set_field_value, "Terraria", "Projectile", "friendly", proj, false, "bool")
    pcall(q.set_field_value, "Terraria", "Projectile", "timeLeft", proj, life or 40, "int32")
end

begin_summon = function(index)
    local list = q.get_object("Terraria", "Main", "npc")
    local npc = list and mod.patch.array_at(list, index)
    if not npc then return end
    local who = q.get_field_value("Terraria", "NPC", "whoAmI", npc, "int32")
    if type(who) ~= "number" then return end

    -- whoAmI 会被复用：上一只的 enraged / hit_stack 等不能带过来，
    -- 否则新召出来直接算"已经过载过"，二阶段的开场爆发和提示都不会再出现。
    local state = {
        summon = SUMMON_FRAMES,
        timer = 0,
    }
    boss_state[who] = state

    pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, true, "bool")
    pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, 220, "int32")
    pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, 0.4, "float")
    util.notify("晶核在头顶裂开了……")
end

-- 每帧的出场表现（共 300 帧 ≈ 5 秒）：
--   0-89   预兆：本体全透明停在 900 高空，碎晶从地面往头顶聚集
--   90-209 下坠：前慢后快（ease-in），带向下拖尾
--   210-269 悬停蓄力：透明度归零、体型呼吸、四周碎晶加速收缩
--   270-299 爆发：双层环形炸开 + 体型回弹
local function summon_tick(npc, state)
    local frame = SUMMON_FRAMES - (state.summon or 0)
    local x, y = util.center("NPC", npc)
    local player = util.nearest_player(x, y, 12000)
    local px, py = x, y
    if player then px, py = player.x, player.y end

    local target_x = px
    local target_y = py - 260
    local hw = math.floor((q.get_field_value("Terraria", "NPC", "width", npc, "int32") or 140) / 2)

    if frame < 90 then
        pcall(q.vec.set, "Terraria", "NPC", "position", npc,
                target_x - hw, py - 900 - hw)
        pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, 255, "int32")
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, 0.5, "float")
        if frame == 0 then util.notify("空气开始发冷……") end
        if frame % 3 == 0 then
            local angle = math.random() * math.pi * 2
            local dist = 260 + math.random(0, 180)
            local sx = px + math.cos(angle) * dist
            local sy = py + math.sin(angle) * dist * 0.4
            fx_shard(sx, sy, (target_x - sx) / 30, (target_y - sy) / 30, 34)
        end
    elseif frame < 210 then
        local t = (frame - 90) / 120
        local start_y = py - 900
        local ny = start_y + (target_y - start_y) * (t ^ 1.8)
        pcall(q.vec.set, "Terraria", "NPC", "position", npc, target_x - hw, ny - hw)
        pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc,
                math.floor(255 * (1 - t * 0.8)), "int32")
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, 0.5 + 0.6 * t, "float")
        if frame == 90 then util.notify("头顶有什么东西在落下来") end
        if frame % 4 == 0 then
            fx_shard(target_x + math.random(-60, 60), ny - 40,
                    0, 5 + math.random(0, 40) * 0.1, 26)
        end
    elseif frame < 270 then
        local t = (frame - 210) / 60
        if frame == 210 then util.notify("晶核开始坍缩") end
        pcall(q.vec.set, "Terraria", "NPC", "position", npc,
                target_x - hw, target_y - hw + math.sin(t * 14) * 6)
        pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc,
                math.floor(50 * (1 - t)), "int32")
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc,
                1.1 + math.sin(t * 14) * 0.06, "float")
        if frame % 3 == 0 then
            local angle = math.random() * math.pi * 2
            local dist = 300 - 200 * t
            local sx = target_x + math.cos(angle) * dist
            local sy = target_y + math.sin(angle) * dist
            fx_shard(sx, sy, (target_x - sx) / 14, (target_y - sy) / 14, 18)
        end
    else
        pcall(q.vec.set, "Terraria", "NPC", "position", npc, target_x - hw, target_y - hw)
        if frame == 270 then
            for i = 0, 9 do
                local angle = i * math.pi * 2 / 10
                fx_shard(target_x, target_y, math.cos(angle) * 9, math.sin(angle) * 9, 32)
            end
            for i = 0, 5 do
                local angle = i * math.pi * 2 / 6 + 0.26
                fx_shard(target_x, target_y, math.cos(angle) * 5.5, math.sin(angle) * 5.5, 38)
            end
            -- 贴地往外掀的一层，落地感靠这个
            for i = 0, 7 do
                local dir = (i % 2 == 0) and 1 or -1
                fx_shard(target_x + dir * 30, py - 20,
                        dir * (9 + math.random(0, 4)), 0, 40)
            end
            util.notify("晶核领主降临！")
        end
        local back = math.max(0, 1.25 - (frame - 270) * 0.017)
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, back, "float")
    end
end

-- ===== 二阶段切换表演（110 帧 ≈ 1.8 秒）=====
-- 蓄势 → 剧烈抖动 → 炸开，期间无敌、不推进 AI
local TRANSITION_FRAMES = 110

local function transition_tick(npc, state, target)
    local frame = TRANSITION_FRAMES - (state.transition or 0)
    local x, y = util.center("NPC", npc)
    -- hw 原来只在 summon_tick 里定义，这里引用了它却没定义，每帧抛错 →
    -- 转场跑不完 → dontTakeDamage 一直挂着 → 二阶段无敌（1.2.71 的 bug）
    local hw = math.floor((q.get_field_value("Terraria", "NPC", "width", npc, "int32") or 140) / 2)

    local function abort()
        pcall(q.set_field_value, "Terraria", "NPC", "onFire2", npc, false, "bool")
        pcall(q.set_field_value, "Terraria", "NPC", "ichor", npc, false, "bool")
        pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, 0, "int32")
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, BOSS_SCALE, "float")
        pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, false, "bool")
        state.transition = 0
    end

    -- 玩家没了就中止，别把它卡在无敌状态
    if not target then
        abort()
        return
    end

    local anchor_y = target.y - 280
    if frame < 45 then
        local t = frame / 45
        pcall(q.vec.set, "Terraria", "NPC", "position", npc, x - hw, anchor_y - hw)
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, BOSS_SCALE * (1.0 + t * 0.25), "float")
        pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc,
                math.floor(math.abs(math.sin(t * math.pi * 2)) * 90), "int32")
        if frame % 8 == 0 then
            local angle = math.random() * math.pi * 2
            local dist = 240 - 120 * t
            fx_shard(x + math.cos(angle) * dist, y + math.sin(angle) * dist,
                    -math.cos(angle) * 3, -math.sin(angle) * 3, 14)
        end
    elseif frame < 85 then
        -- 抖动阶段挂上染色：onFire2 画火苗、ichor 叠一层暖色，收尾再摘掉
        if frame == 45 then
            pcall(q.set_field_value, "Terraria", "NPC", "onFire2", npc, true, "bool")
            pcall(q.set_field_value, "Terraria", "NPC", "ichor", npc, true, "bool")
            util.notify_color("晶核烧起来了——", 255, 90, 70)
        end
        local t = (frame - 45) / 40
        pcall(q.vec.set, "Terraria", "NPC", "position", npc,
                x - hw + math.random(-5, 5), anchor_y - hw + math.random(-5, 5))
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, BOSS_SCALE * (1.25 - t * 0.1), "float")
        pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, 0, "int32")
        if frame % 5 == 0 then
            local angle = math.random() * math.pi * 2
            local dist = 120 - 90 * t
            fx_shard(x + math.cos(angle) * dist, y + math.sin(angle) * dist,
                    -math.cos(angle) * 4, -math.sin(angle) * 4, 10)
        end
    else
        pcall(q.vec.set, "Terraria", "NPC", "position", npc, x - hw, anchor_y - hw)
        if frame == 85 then
            pcall(q.set_field_value, "Terraria", "NPC", "onFire2", npc, false, "bool")
            pcall(q.set_field_value, "Terraria", "NPC", "ichor", npc, false, "bool")
            for i = 0, 9 do
                local angle = i * math.pi * 2 / 10
                fx_shard(x, y, math.cos(angle) * 8, math.sin(angle) * 8, 30)
            end
            for i = 0, 4 do
                local dir = (i % 2 == 0) and 1 or -1
                fx_shard(x + dir * 20, y + 40, dir * 9, 0, 40)
            end
            util.notify_color("晶核领主进入暴走状态", 255, 90, 70)
        end
        pcall(q.set_field_value, "Terraria", "NPC", "scale", npc,
                BOSS_SCALE * (1.15 - (frame - 85) * 0.0075), "float")
    end
end

-- ===== 死亡演出 / 全灭退场 =====
-- 死亡：定身、闪烁、逐帧上透明度、碎裂特效，最后统一结算掉落。
-- 注意不能直接让 life 掉到 0：原版同一帧就会判死，演出根本没机会播。
local DEATH_FRAMES = 120   -- 2 秒
local FLEE_FRAMES = 90     -- 1.5 秒

local function any_player_alive(cx, cy)
    return util.nearest_player(cx, cy, 100000) ~= nil
end

local function death_tick(npc, state, frame, who)
    local cx, cy = util.center("NPC", npc)
    util.move("NPC", npc, 0, 0)
    -- 透明度：0 → 255，最后三分之一开始闪
    local t = frame / DEATH_FRAMES
    local alpha = math.floor(math.min(255, t * 300))
    pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, alpha, "int32")
    -- 抽动：左右小幅位移，像在崩解
    if frame % 6 < 3 then
        util.move("NPC", npc, 1.5, 0)
    else
        util.move("NPC", npc, -1.5, 0)
    end
    -- 碎裂特效
    if frame % 10 == 0 and cx then
        local ang = math.random() * math.pi * 2
        local sp = 2 + math.random() * 4
        fx_shard(cx + math.random(-30, 30), cy + math.random(-30, 30),
                math.cos(ang) * sp, math.sin(ang) * sp - 1.5, 45)
    end
    if frame == 40 then util.notify_color("晶核开始崩解——", 255, 120, 150) end

    if state.dying <= 1 then
        -- 收尾：掉落 + 移除
        if not state.death_fired then
            state.death_fired = true
            pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, 255, "int32")
            pcall(q.set_field_value, "Terraria", "NPC", "active", npc, false, "bool")
            if type(who) == "number" then
                boss_state[who] = nil
                summoned_boss[who] = nil
            end
            clear_boss_shots()
            crystal_boss_death(npc)
        end
    end
end

local function flee_tick(npc, state, frame, who)
    local cx, cy = util.center("NPC", npc)
    -- 往上飘走，同时淡出
    util.move("NPC", npc, 0, -1.2)
    local t = frame / FLEE_FRAMES
    pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc,
            math.floor(math.min(255, t * 260)), "int32")
    if frame % 12 == 0 and cx then
        fx_shard(cx + math.random(-24, 24), cy + math.random(-24, 24),
                (math.random() - 0.5) * 2, -1 - math.random() * 2, 40)
    end
    if state.fleeing <= 1 then
        pcall(q.set_field_value, "Terraria", "NPC", "active", npc, false, "bool")
        if type(who) == "number" then
            boss_state[who] = nil
            summoned_boss[who] = nil
        end
        clear_boss_shots()
        release_boss_music()
    end
end

local function boss_ai_vanilla(npc)
    local who = q.get_field_value("Terraria", "NPC", "whoAmI", npc, "int32") or -1
    local state = boss_state[who]
    if not state then
        state = { timer = 0 }
        boss_state[who] = state
    end
    state.timer = state.timer + 1
    M.ai_calls = (M.ai_calls or 0) + 1

    -- 出场动画期间：不进正常 AI、不掉血、不动
    if (state.summon or 0) > 0 then
        state.summon = state.summon - 1
        summon_tick(npc, state)
        -- 音乐压到最后爆发那一下再进，前面留安静
        if SUMMON_FRAMES - state.summon >= 270 then ensure_boss_music() end
        if state.summon == 0 then
            pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, false, "bool")
            pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, 0, "int32")
            pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, BOSS_SCALE, "float")
            local sx, sy = util.center("NPC", npc)
            state.expect_x, state.expect_y = sx, sy
            state.timer = 0
        end
        return
    end

    -- 死亡演出进行中：不跑正常 AI
    if (state.dying or 0) > 0 then
        local frame = DEATH_FRAMES - state.dying + 1
        state.dying = state.dying - 1
        death_tick(npc, state, frame, who)
        return
    end
    -- 全灭退场演出进行中
    if (state.fleeing or 0) > 0 then
        local frame = FLEE_FRAMES - state.fleeing + 1
        state.fleeing = state.fleeing - 1
        flee_tick(npc, state, frame, who)
        return
    end

    -- 血量归零：拦下来先播演出（原版同一帧就会判死，所以这里把 life 顶回 1）
    local life_now = q.get_field_value("Terraria", "NPC", "life", npc, "int32") or 1
    if life_now <= 0 then
        state.dying = DEATH_FRAMES
        state.death_fired = false
        pcall(q.set_field_value, "Terraria", "NPC", "life", npc, 1, "int32")
        pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, true, "bool")
        return
    end

    -- 只要它还活着，战斗曲就一直顶着
    ensure_boss_music()

    local cx, cy = util.center("NPC", npc)
    local target = util.nearest_player(cx, cy, BOSS_AGGRO_RANGE)
    if not target then
        util.move("NPC", npc, 0, 0)
        state.no_target = (state.no_target or 0) + 1
        local limit = local_player_dead() and BOSS_DESPAWN_ON_DEATH_FRAMES
                or BOSS_LOSE_TARGET_FRAMES
        if state.no_target > limit then
            if not any_player_alive(cx, cy) then
                -- 把所有玩家都打倒了：播一段退场动画再消失
                state.fleeing = FLEE_FRAMES
                pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, true, "bool")
            else
                despawn_boss(npc, who)
            end
        end
        return
    end
    state.no_target = 0

    local life = q.get_field_value("Terraria", "NPC", "life", npc, "int32") or 0
    local life_max = q.get_field_value("Terraria", "NPC", "lifeMax", npc, "int32") or 1
    -- 二阶段在 40% 血才进：一阶段吃掉 60% 血，二阶段只负责收尾
    local phase = (life * 100 <= life_max * 40) and 2 or 1
    local enraged = phase == 2

    -- 无敌帧：自定义 NPC 不会自动递减 immune[]
    local immune = q.get_object("Terraria", "NPC", "immune", npc)
    if immune then
        for i = 0, 8 do
            local left = mod.patch.array_at(immune, i, "int32")
            if left and left > 0 then
                pcall(mod.patch.array_set, immune, i, left - 1, "int32")
            end
        end
    end

    -- 防御固定，不做"连续挨打临时加防"（v1.2.18 删掉，玩家反馈太肉）
    pcall(q.set_field_value, "Terraria", "NPC", "defense", npc,
            BOSS_BASE_DEFENSE, "int32")

    -- 晶核过载：血量跌破 40% / 20% / 10% 各炸一圈。
    -- 以前只在进二阶段时触发一次，加上 whoAmI 复用把状态带过去，
    -- 第二场之后干脆再也不出现（v1.2.21 一并修掉）。
    local want, fired = 0, 0
    if enraged and not state.enraged then
        state.enraged = true
    end
    local OVERLOAD_AT = { 40, 20, 10 }
    state.stage = state.stage or 0
    local percent = (life * 100) / math.max(1, life_max)
    while state.stage < #OVERLOAD_AT and percent <= OVERLOAD_AT[state.stage + 1] do
        state.stage = state.stage + 1
        if state.stage == 1 then
            -- 40%：交给切换表演，爆发放在表演结尾
            state.transition = TRANSITION_FRAMES
            pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, true, "bool")
            util.notify_color("晶核开始过载——", 255, 90, 70)
        else
            want = 14
            fired = fire_ring(cx, cy, want, 26, 6.5, state.timer * 0.1)
            util.notify(("晶核领主的晶核过载了（剩 %d%%）"):format(OVERLOAD_AT[state.stage]))
        end
    end

    -- 切换表演：无敌、不攻击、不动，演完再继续
    if (state.transition or 0) > 0 then
        state.transition = state.transition - 1
        transition_tick(npc, state, target)
        if state.transition == 0 then
            pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, false, "bool")
            pcall(q.set_field_value, "Terraria", "NPC", "alpha", npc, 0, "int32")
            pcall(q.set_field_value, "Terraria", "NPC", "scale", npc, BOSS_SCALE, "float")
            local sx, sy = util.center("NPC", npc)
            state.expect_x, state.expect_y = sx, sy
        end
        return
    end

    -- 兜底：正常战斗时绝不该处于无敌。各个演出自己负责开关，这里防漏 ——
    -- 1.2.71 就是转场里抛错导致 dontTakeDamage 一直挂着，二阶段完全打不动。
    if q.get_field_value("Terraria", "NPC", "dontTakeDamage", npc, "bool") then
        pcall(q.set_field_value, "Terraria", "NPC", "dontTakeDamage", npc, false, "bool")
    end

    local speed = enraged and 10 or 7
    local accel = 0.16
    local target_x, target_y = target.x, target.y - 240
    -- ===== 冲刺段：克眼式连续直线冲刺 =====
    -- 一阶段 2 连冲；二阶段先瞬移到玩家侧上方，再 3 连冲。
    -- 每段冲刺 = 蓄力(10) + 直线加速(22) + 收尾(8)，冲完一段立刻接下一段。
    local dash_count = enraged and 3 or 2
    local DASH_WIND, DASH_RUN, DASH_REST = 10, 36, 8   -- 直线段 36 帧，冲得更远
    local dash_total = (enraged and 12 or 0) + dash_count * (DASH_WIND + DASH_RUN + DASH_REST)
    local dash_end = 150 + dash_total
    local off = dash_total - 80            -- 相对旧的 80 帧冲刺窗口多出来的时间
    local cycle = state.timer % (600 + off)

    if cycle < 150 then
        state.dash = nil
    elseif cycle < dash_end then
        if not state.dash then
            state.dash = { left = dash_count, phase = "wind", t = 0 }
            if enraged then
                -- 瞬移：绕到玩家侧上方，给玩家一点反应距离
                local side = (cx < target.x) and -1 or 1
                pcall(q.vec.set, "Terraria", "NPC", "position", npc,
                        target.x + side * 320, target.y - 260)
                cx, cy = util.center("NPC", npc)
                state.expect_x, state.expect_y = cx, cy
            end
        end
        local d = state.dash
        d.t = d.t + 1
        if d.phase == "wind" then
            -- 蓄力：悬停、对准玩家
            util.move("NPC", npc, 0, 0)
            if d.t >= DASH_WIND then
                d.phase, d.t = "run", 0
                local tx, ty = util.player_center(target.handle)
                d.dir_x, d.dir_y = (tx or target.x) - cx, (ty or target.y) - cy
                local len = math.sqrt(d.dir_x * d.dir_x + d.dir_y * d.dir_y)
                if len < 1 then len = 1 end
                d.dir_x, d.dir_y = d.dir_x / len, d.dir_y / len
            end
        elseif d.phase == "run" then
            local dash_speed = enraged and 30 or 22
            -- 越冲越快，收尾前达到最高速
            local t = d.t / DASH_RUN
            local sp = dash_speed * (0.6 + 0.4 * t)
            util.move("NPC", npc, d.dir_x * sp, d.dir_y * sp)
            if d.t >= DASH_RUN then
                d.phase, d.t = "rest", 0
            end
        else
            util.move("NPC", npc, 0, 0)
            if d.t >= DASH_REST then
                d.left = d.left - 1
                if d.left <= 0 then
                    state.dash = nil
                else
                    d.phase, d.t = "wind", 0
                    -- 下一段重新对准玩家当前位置
                    local tx, ty = util.player_center(target.handle)
                    cx, cy = util.center("NPC", npc)
                    state.expect_x, state.expect_y = cx, cy
                end
            end
        end
        return
    end

    if cycle < 120 then
        -- ① 悬停点射：扇形，间隔压得很短
        target_x = target.x + math.sin(state.timer / 60) * 190
        target_y = target.y - 250
        local interval = enraged and 44 or 38
        if state.timer % interval == 0 then
            local shot_speed = enraged and 13 or 11
            local ax, ay = lead_point(cx, cy, target, shot_speed)
            want = enraged and 4 or 3
            fired = fire_arc(cx, cy, ax, ay, want, enraged and 0.13 or 0.16,
                    enraged and 28 or 26, shot_speed)
        end
    elseif cycle < 150 then
        -- ② 蓄力：抬升 + 两发提前量狙击（不再停火）
        target_x = target.x
        target_y = target.y - 380
        accel = 0.08
        speed = speed * 0.7
        if cycle == 120 or cycle == 138 then
            local ax, ay = lead_point(cx, cy, target, 9)
            want = 1
            fired = fire_arc(cx, cy, ax, ay, 1, 0, enraged and 31 or 30, 9)
        end
    elseif cycle < 230 then
        -- ③ 冲撞：速度拉到 20 / 26，二阶段在 200 帧后再扑一次
        target_x = target.x
        target_y = target.y
        accel = 0.35
        speed = (enraged and 28 or 22)
        if enraged and cycle >= 200 then speed = speed + 4 end
    elseif cycle < 260 + off then
        -- ④ 脱离：一阶段丢一圈小环形；二阶段冲撞后回身三连狙击 + 小环形
        target_x = cx + (cx - target.x) * 0.5
        target_y = target.y - 320
        accel = 0.24
        speed = speed + 4
        if enraged then
            if cycle == 230 or cycle == 250 then
                local ax, ay = lead_point(cx, cy, target, 14)
                want = want + 1
                fired = fired + fire_arc(cx, cy, ax, ay, 1, 0, 36, 14)
            end
            if cycle == 236 then
                want = want + 8
                fired = fired + fire_ring(cx, cy, 6, 28, 7.0, 0)
            end
        end
    elseif cycle < 300 + off then
        -- ⑤ 环形爆发
        target_x = target.x
        target_y = target.y - 300
        accel = 0.12
        if cycle == 260 then
            want = enraged and 13 or 12
            fired = fire_ring(cx, cy, want, enraged and 32 or 30, 7.5, 0)
        end
    elseif cycle < 400 + off then
        -- ⑥ 绕圈 + 螺旋弹幕：每 10 帧 2 发
        local angle = (cycle - 300) / 100 * math.pi * 2
        target_x = target.x + math.cos(angle) * 200
        target_y = target.y + math.sin(angle) * 200
        accel = 0.18
        speed = speed + 3
        local spiral_gap = enraged and 15 or 9
        if state.timer % spiral_gap == 0 then
            want = 2
            fired = fire_ring(cx, cy, 2, enraged and 21 or 20, 8.5, state.timer * 0.4)
        end
        -- 二阶段专属：边绕边往外扩圈，越往后越快，逼玩家换方向
        if enraged and (cycle == 300 or cycle == 340 or cycle == 380) then
            local wave = (cycle - 300) / 40 + 1
            want = want + 10
            fired = fired + fire_ring(cx, cy, 10, 24,
                    6.0 + wave, wave * 0.15)
        end
    elseif cycle < 460 + off then
        -- ⑦ 三连狙击：瞄准、间隔 16 帧、弹速 14
        target_x = target.x
        target_y = target.y - 220
        accel = 0.16
        if cycle == 400 or cycle == 416 or cycle == 432 then
            local ax, ay = lead_point(cx, cy, target, 14)
            want = 1
            fired = fire_arc(cx, cy, ax, ay, 1, 0, enraged and 36 or 34, 14, true)
        end
    elseif cycle < 540 + off then
        -- ⑧ 天降晶雨：二阶段专属（一阶段这一段只是悬停逼近）
        target_x = target.x + math.sin(state.timer / 40) * 120
        target_y = target.y - 330
        accel = 0.16
        if enraged and (cycle == 460 or cycle == 500) then
            want = 5
            fired = fire_rain(target, want, 26, 8)
        end
    else
        -- ⑨ 收尾：逼近 + 每 40 帧一发提前量直射，二阶段还会瞬移
        target_x = target.x + math.sin(state.timer / 45) * 200
        target_y = target.y - 260
        local tail_gap = enraged and 40 or 32
        if state.timer % tail_gap == 0 then
            local ax, ay = lead_point(cx, cy, target, 12)
            want = 1
            -- 二阶段的收尾直射也带一点弱追踪
            fired = fire_arc(cx, cy, ax, ay, 1, 0, enraged and 32 or 30, 12, enraged)
        end
        if enraged and cycle == 540 then
            local side = (cx < target.x) and 1 or -1
            pcall(q.vec.set, "Terraria", "NPC", "position", npc,
                    target.x + side * 300, target.y - 150)
            cx, cy = util.center("NPC", npc)
            state.expect_x, state.expect_y = cx, cy
        end
    end

    if want > 0 then
        M.last_fire = {
            fired = fired,
            want = want,
            fail = util.spawn_info().fail,
            pos = { cx, cy },
        }
    end

    -- 离得太远就提速追，不然玩家一跑就拉开、看起来像脱战
    local gap_x, gap_y = target.x - cx, target.y - cy
    local gap = math.sqrt(gap_x * gap_x + gap_y * gap_y)
    if gap > 900 then
        speed = speed + math.min(8, (gap - 900) / 250)
        accel = math.max(accel, 0.25)
    end

    local dx, dy = target_x - cx, target_y - cy
    local len = math.sqrt(dx * dx + dy * dy)
    local vx, vy = q.vec.get("Terraria", "NPC", "velocity", npc)
    vx, vy = vx or 0, vy or 0
    local tvx, tvy = 0, 0
    if len > 2 then
        tvx, tvy = dx / len * speed, dy / len * speed
    end
    vx = vx + (tvx - vx) * accel
    vy = vy + (tvy - vy) * accel

    -- 击退抑制
    pcall(q.set_field_value, "Terraria", "NPC", "knockBackResist", npc, 1.0, "float")
    local px, py = util.position("NPC", npc)
    if px and state.expect_x then
        local ox = px - state.expect_x
        local oy = py - state.expect_y
        if math.abs(ox) + math.abs(oy) > 6 then
            pcall(q.vec.set, "Terraria", "NPC", "position", npc,
                    state.expect_x, state.expect_y)
            px, py = state.expect_x, state.expect_y
        end
    end

    util.move("NPC", npc, vx, vy)
    state.expect_x, state.expect_y = (px or cx) + vx, (py or cy) + vy

    -- 召唤傀儡：二阶段更勤
    local summon_interval = enraged and 300 or 420
    if state.timer % summon_interval == 0 then
        summon_golem_near(cx, cy)
    end
end

local ITEM_HEART = 58   -- 原版「生命心」：捡起来回 20 血

local function golem_death(npc)
    local x, y = util.center("NPC", npc)
    local base = util.config_number("shards_per_kill", 3)
    util.drop_item(ids.item.shard, x, y, math.max(1, base + math.random(-1, 1)))
    -- 被打死时掉一颗回血心心（Boss 战里的小补给）
    if x then
        util.drop_item(ITEM_HEART, x, y, 1)
    end
end

crystal_boss_death = function(npc)
    release_boss_music()
    local who = q.get_field_value("Terraria", "NPC", "whoAmI", npc, "int32")
    if type(who) == "number" then
        boss_state[who] = nil
        summoned_boss[who] = nil
    end
    util.notify("晶核领主已被击败！")
    local x, y = util.center("NPC", npc)
    util.drop_item(ids.item.core, x, y, 3 + math.random(0, 2))
    util.drop_item(ids.item.shard, x, y, 12 + math.random(0, 6))
    util.drop_item(ITEM_HEART, x, y, 1)   -- 原版生命心
    util.drop_item(ids.item.bag, x, y, 1)
end


-- ===== 雪地野刷：击败骷髅王后，雪地会自然出现碎晶傀儡 =====
local snow_tick = 0

local function downed_skeletron()
    local ok, v = pcall(q.get_field_value, "Terraria", "NPC", "downedBoss3", nil, "bool")
    return ok and v == true
end

local function in_snow(player)
    local ok, v = pcall(q.get_field_value, "Terraria", "Player", "ZoneSnow", player, "bool")
    if ok and type(v) == "boolean" then return v end
    local prop = q.property("Terraria", "Player", "ZoneSnow")
    if prop then
        local ok_p, getter = pcall(mod.patch.property_get_method, prop)
        if ok_p and getter then
            local ok_c, r = pcall(q.call, getter, player)
            if ok_c then return r == true end
        end
    end
    return false
end

local function snow_spawn_tick()
    snow_tick = snow_tick + 1
    if snow_tick % 3600 ~= 0 then return end        -- 每 60 秒刷新一批
    if not downed_skeletron() then return end

    local player = util.local_player()
    if not player then return end
    if not in_snow(player) then return end

    local golem_type = q.npc_id(ids.npc.golem)
    if not golem_type or golem_type < 0 then return end
    if util.count_npc(golem_type) >= 3 then return end

    local x, y = util.position("Player", player)
    if not x then return end
    for i = 1, 3 do
        local side = math.random(0, 1) == 1 and 1 or -1
        M.spawn_golem(x + side * math.random(500, 900), y - math.random(60, 160))
    end
end

function M.register()
    local ok, err = pcall(q.install_hook_postfix, "Terraria", "NPC", "NPCLoot",
            npc_loot_postfix, { argc = 0 })
    hook_state.loot = ok and true or false
    if not ok then
        hook_state.loot_error = tostring(err)
        mod.warn("碎晶之链：NPCLoot 钩子安装失败 " .. tostring(err))
    end

    -- 原创生物：碎晶傀儡 + 晶核领主
    local ok_golem, err_golem = pcall(q.register_npc, {
        name = ids.npc.golem,
        texture = "CrystalGolem.png",
        frames = 1,
        width = 36, height = 36,
        lifeMax = 700, life = 700,
        damage = 40, defense = 15,
        knockBackResist = 0.6,
        noGravity = true, noTileCollide = true,
        friendly = false,
        aiStyle = 0,
        ai = golem_ai,
        on_death = golem_death,
    })
    hook_state.golem = ok_golem and true or false
    if not ok_golem then
        hook_state.golem_error = tostring(err_golem)
        mod.warn("碎晶之链：碎晶傀儡注册失败 " .. tostring(err_golem))
    end

    local ok_boss, err_boss = pcall(q.register_npc, {
        name = ids.npc.boss,
        texture = "CrystalCoreLord.png",
        frames = 1,
        width = 140, height = 140,
        scale = BOSS_SCALE,
        lifeMax = BOSS_BASE_LIFE, life = BOSS_BASE_LIFE,
        damage = BOSS_BASE_DAMAGE, defense = BOSS_BASE_DEFENSE,
        knockBackResist = 1.0,   -- 完全免疫击退
        noGravity = true, noTileCollide = true,
        friendly = false,
        boss = true,   -- 实验：原生 Boss 血条。若进世界崩，这是唯一变量，回退成 false 即可
        aiStyle = 0,
        ai = boss_ai_vanilla,
        on_death = crystal_boss_death,
    })
    hook_state.boss = ok_boss and true or false
    if not ok_boss then
        hook_state.boss_error = tostring(err_boss)
        mod.warn("碎晶之链：晶核领主注册失败 " .. tostring(err_boss))
    end

    local ok_snow, err_snow = pcall(q.install_hook_postfix, "Terraria", "Main", "Update",
            snow_spawn_tick, { argc = 1 })
    hook_state.snow = ok_snow and true or false
    if not ok_snow then
        hook_state.snow_error = tostring(err_snow)
        mod.warn("碎晶之链：Main.Update 钩子安装失败，雪地不会野刷 " .. tostring(err_snow))
    end

    -- 旧的 NPC.AI 后置钩子已删除：它引用了一个不存在的变量，而且和自定义 AI 重复。
    -- 现在 Boss 的全部行为都在注册时的 ai 回调里。
    hook_state.ai = false
end

return M
