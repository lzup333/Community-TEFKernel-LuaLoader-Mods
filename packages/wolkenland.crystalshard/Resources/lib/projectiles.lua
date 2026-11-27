-- 自定义弹幕：NewText 越界问题修好后（3.3.0），这条链路已经能正常生成。
local q = mod.quickapi
local util = require("util")
local ids = require("ids")
local buffs = require("buffs")

local M = {}

-- 直线飞：原版 AI 被跳过，位移要自己算。
local function straight_ai(projectile)
    q.projectile_move(projectile)
end

-- 弱追踪：只在 ai0 被置位（=1）时生效，转向很慢，横移能躲开。
local function adaptive_ai(projectile)
    local ok, arr = pcall(q.get_field_value, "Terraria", "Projectile", "ai", projectile, "object")
    local ai0 = 0
    if ok and arr then
        local okv, v = pcall(mod.patch.array_at, arr, 0, "float")
        if okv and type(v) == "number" then ai0 = v end
    end
    if ai0 >= 0.5 then
        local x, y = util.position("Projectile", projectile)
        local target = x and util.nearest_player(x, y, 1400)
        if target then
            local px, py = util.player_center(target.handle)
            if px then
                q.projectile_homing(projectile, px, py, 0.02, 0.02)
            end
        end
    end
    q.projectile_move(projectile)
end

-- 追踪：每帧把速度方向朝最近玩家掰一点，速度大小不变。
local function homing_ai(projectile)
    local x, y = util.position("Projectile", projectile)
    local target = util.nearest_player(x, y, 1600)
    if target then
        q.projectile_homing(projectile, target.x, target.y, 0.05, 0.1)
    end
    q.projectile_move(projectile)
end

-- 原版水晶弹命中分裂出的碎片（90）本身不追踪，这里补上
local VANILLA_SHARD = 90

local function shard_homing(projectile)
    if not projectile then return end
    local type_id = q.get_field_value("Terraria", "Projectile", "type", projectile, "int32")
    if type_id ~= VANILLA_SHARD then return end

    -- 坐标要先取：之前这行放在下面，敌对分支用到时还是 nil，
    -- 每帧在 nearest_player 里 nil 参与运算 → 钩子一直在报错。
    local x, y = util.position("Projectile", projectile)
    if not x then return end

    -- 敌对水晶弹是 Boss 的：带一点点追踪，提高命中率，但转得慢，横移还能躲
    local hostile = q.get_field_value("Terraria", "Projectile", "hostile", projectile, "bool")
    if hostile then
        local player = util.nearest_player(x, y, 1400)
        if player then
            local px, py = util.player_center(player.handle)
            if px then
                q.projectile_homing(projectile, px, py, 0.035, 0.06)
            end
        end
        return
    end
    local npc = util.nearest_npc(x, y, 700)
    if not npc then return end
    local tx, ty = util.center("NPC", npc)
    q.projectile_homing(projectile, tx, ty, 0.08, 0.25)
end

-- 原版召唤物 buff 依赖「找到对应召唤物弹幕」，我们的随从不是原版 minion，会被清掉。
-- 由随从自己每帧续一次（Player.AddBuff 已实测可用）。
-- 以前借原版 182 号召唤 buff 当门面；现在自定义 buff 能用了，
-- 换成自家「碎晶精魂」（buffs.lua 里注册）。
local add_buff_method, add_buff_resolved

-- 召唤物是自定义弹幕，内核每帧会把它重置成 active=false —— 不登记保活的话
-- 大约 1 秒就停住（1.2.78 实测）。中立弹幕，不伤害任何一方。
M.MINION_SPEC = {
    damage = 0, knockBack = 0, width = 26, height = 26,
    timeLeft = 36000, penetrate = -1, owner = 255,
    friendly = false, hostile = false, tileCollide = false,
}
M.MINION_LIFE = 216000     -- 1 小时；真正回收靠 buff 消失/解散

M.MINION_SHOT_SPEED = 12
M.MINION_SHOT_LIFE = 120
M.MINION_SHOT_DAMAGE = 40

local function minion_buff_id()
    return buffs.runtime_id and buffs.runtime_id(buffs.minion_name) or nil
end

local keep_beat = -1
local keep_refresh = 0
local MINION_BUFF_FRAMES = 216000   -- 1 小时；实际由 AI 每帧续，玩家看不到归零

local function keep_minion_buff(player)
    if not add_buff_resolved then
        add_buff_resolved = true
        add_buff_method = q.method("Terraria", "Player", "AddBuff", 2)
                or q.method("Terraria", "Player", "AddBuff", 3)
    end
    if not add_buff_method then return end
    local id = minion_buff_id()
    if not id then return end
    local beat = buffs.minion_heartbeat or 0
    if beat == keep_beat then
        return      -- 这一帧 buff 没在跑（被取消或没挂上）：不续，交给 AI 判死
    end
    keep_beat = beat
    -- 每 60 帧续一次时长，避免每帧 AddBuff；buff 正常时永远不会归零
    keep_refresh = (keep_refresh or 0) + 1
    if keep_refresh % 60 == 0 then
        pcall(q.call, add_buff_method, player, id, MINION_BUFF_FRAMES)
    end
end

-- 随从：绕玩家悬停，自动朝附近敌人射碎晶弹
local minion_state = {}

-- 新召一只时清掉该槽位的旧状态（whoAmI 复用）
function M.reset_minion_state(index)
    if type(index) ~= "number" or index < 0 then return end
    minion_state[index] = nil
end

local function minion_ai(projectile)
    local who = q.get_field_value("Terraria", "Projectile", "whoAmI", projectile, "int32") or -1
    local state = minion_state[who]
    if not state then
        -- grace：头 60 帧不检查 buff。whoAmI 会复用，旧的 buff_seen 留着会把
        -- 新召唤物在 buff 还没挂上时直接判死（表现为「无法再次召唤」）。
        state = { tick = 0, cd = 30, buff_seen = false, grace = 60 }
        minion_state[who] = state
    end
    state.tick = state.tick + 1
    if state.cd > 0 then state.cd = state.cd - 1 end

    local x, y = util.position("Projectile", projectile)
    -- 找主人用很大的范围：玩家传送走之后也要能找回来（之前 4000 太窄，传送就丢）
    local owner = util.nearest_player(x, y, 60000)

    if owner then
        -- 离得太远（屏幕外）：直接瞬移到玩家身边，别慢慢飘
        local ddx, ddy = owner.x - x, owner.y - y
        local far = math.sqrt(ddx * ddx + ddy * ddy)
        if far > 1600 then
            pcall(q.vec.set, "Terraria", "Projectile", "position", projectile,
                    owner.x + math.random(-40, 40), owner.y - 60)
            x, y = util.position("Projectile", projectile)
        end
        -- 用 buff 的 update 心跳判断它还在不在：内核每帧会调 update，
        -- 玩家双击取消后就不再调了。这比查剩余时间可靠。
        local beat = buffs.minion_heartbeat or 0
        if beat ~= (state.last_beat or -1) then
            state.last_beat = beat
            state.seen_at = state.tick
            state.buff_seen = true
        elseif state.buff_seen and (state.tick - (state.seen_at or 0)) > 45 then
            -- 连续 45 帧没有心跳：buff 被取消了 → 所有召唤物一起立刻消失。
            -- 先按 spec 批量断保活（不看 whoAmI，避免对不上导致救活），再 kill。
            util.untrack_spec(M.MINION_SPEC)
            pcall(q.set_field_value, "Terraria", "Projectile", "active", projectile, false, "bool")
            pcall(q.set_field_value, "Terraria", "Projectile", "timeLeft", projectile, 0, "int32")
            pcall(function() q.proj(projectile).kill() end)
            return
        end
        keep_minion_buff(owner.handle)
        local phase = (who % 6) * (math.pi * 2 / 6)
        local orbit_x = owner.x + math.cos(state.tick / 45 + phase) * 90
        local orbit_y = owner.y - 70 + math.sin(state.tick / 45 + phase) * 26
        local dx, dy = orbit_x - x, orbit_y - y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 6 then
            local speed = math.min(10, dist * 0.14)
            util.move("Projectile", projectile, dx / dist * speed, dy / dist * speed)
        else
            util.move("Projectile", projectile, 0, 0)
        end
    else
        -- 找不到活着的玩家（例如玩家已死）：随从自行消失，避免留下孤儿
        util.untrack_projectile_handle(projectile)
        pcall(function() q.proj(projectile).kill() end)
        return
    end

    if state.cd == 0 then
        -- 只打玩家屏幕内的怪：以玩家为圆心 800（约半屏），避免隔着半张地图开火
        local npc = nil
        if owner then
            npc = util.nearest_npc(owner.x, owner.y, 800)
        else
            npc = q.find_nearest_npc(projectile, 800)
        end
        if npc then
            local px, py = util.position("Projectile", projectile)
            local nx, ny = util.center("NPC", npc)
            local dx, dy = nx - px, ny - py
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 1 then
                local owner_index = owner and owner.index or 255
                -- BOSS 同款晶刺（friendly 版），射程跟 Boss 弹幕一样
                local index = util.spawn_projectile(ids.projectile.minion_spike, px, py,
                        dx / dist * M.MINION_SHOT_SPEED,
                        dy / dist * M.MINION_SHOT_SPEED, M.MINION_SHOT_DAMAGE, owner_index)
                if index then
                    -- 每次新建 spec：owner 要写玩家索引，共享表容易被别的玩家覆盖
                    local spec = {
                        damage = M.MINION_SHOT_DAMAGE, knockBack = 2.0,
                        width = 18, height = 18, scale = 0.9,
                        timeLeft = M.MINION_SHOT_LIFE, penetrate = 0, owner = owner_index,
                        friendly = true, hostile = false, tileCollide = false,
                    }
                    util.revive_full(index, spec)     -- 先补成 friendly，别误伤玩家
                    util.track_custom_projectile(index, spec, M.MINION_SHOT_LIFE)
                end
                state.cd = 30
            end
        end
    end
end

-- 每种自定义弹幕的「出厂参数」：内核生成时不跑 SetDefaults，得我们自己补
local SPEC_BY_NAME = {
    [ids.projectile.spike] = {
        damage = 32, knockBack = 3.0, width = 28, height = 28, scale = 1.4, timeLeft = 300,
        friendly = false, hostile = true, tileCollide = false, penetrate = 0,
    },
    [ids.projectile.spike_red] = {
        damage = 40, knockBack = 3.5, width = 30, height = 30, scale = 2.0, timeLeft = 340,
        friendly = false, hostile = true, tileCollide = false, penetrate = 0,
    },
    -- 玩家自己的射击（铳的子弹）：伤害由武器决定，keep_damage 会保留原值
    [ids.projectile.shot] = {
        damage = 20, knockBack = 2.0, width = 14, height = 14, timeLeft = 180,
        friendly = true, hostile = false, tileCollide = true, penetrate = 0,
        keep_damage = true,
    },
    [ids.projectile.beam] = {
        damage = 30, knockBack = 2.0, width = 16, height = 16, timeLeft = 180,
        friendly = true, hostile = false, tileCollide = false, penetrate = 1,
        keep_damage = true,
    },
    [ids.projectile.bolt] = {
        damage = 30, knockBack = 2.0, width = 14, height = 14, timeLeft = 180,
        friendly = true, hostile = false, tileCollide = false, penetrate = 0,
        keep_damage = true,
    },
    [ids.projectile.magic] = {
        damage = 40, knockBack = 2.0, width = 18, height = 18, timeLeft = 180,
        friendly = true, hostile = false, tileCollide = false, penetrate = 0,
        keep_damage = true,
    },
}

local spec_by_id = {}

local function spec_for(type_id)
    local cached = spec_by_id[type_id]
    if cached then return cached end
    for name, spec in pairs(SPEC_BY_NAME) do
        if q.projectile_id(name) == type_id then
            spec_by_id[type_id] = spec
            return spec
        end
    end
    return nil
end

-- Projectile.Update 的 prefix：只处理「我们自己注册、且已经死了」的弹幕
local function repair_custom_projectile(projectile)
    if not projectile then return end
    local type_id = q.get_field_value("Terraria", "Projectile", "type", projectile, "int32")
    if type(type_id) ~= "number" or type_id <= 1000 then return end
    if q.get_field_value("Terraria", "Projectile", "active", projectile, "bool") then return end
    local spec = spec_for(type_id)
    if spec then
        util.revive_handle(projectile, spec)
    end
end

-- 自动登记：游戏生成弹幕时会调 Projectile.SetDefaults，在这里按 type 认出自己的弹幕。
-- 这样玩家武器打出来的自定义弹幕也能被保活（不需要我们自己知道 Main.projectile 下标）。
local setdefaults_hits = 0

local function autotrack_on_setdefaults(projectile)
    if not projectile then return end
    local type_id = q.get_field_value("Terraria", "Projectile", "type", projectile, "int32")
    if type(type_id) ~= "number" or type_id <= 1000 then return end
    local spec = spec_for(type_id)
    if not spec then return end
    setdefaults_hits = setdefaults_hits + 1
    util.autotrack(projectile, type_id, spec)
end

function M.autotrack_stats()
    return setdefaults_hits, util.tracked_count()
end

-- 命中玩家：取消保活（不然每帧补活会把它「救活」，打中也不消失），
-- 同时给玩家挂 15 秒「晶核侵蚀」。
local function untrack_on_hit_player(projectile, player)
    util.untrack_projectile_handle(projectile)
    if player then
        buffs.apply_erosion(player, buffs.EROSION_FRAMES)
    end
end

-- 命中 NPC：只取消保活。召唤物的晶刺是 friendly，打怪走的是这条；
-- 不取消的话打中了也会被补活，表现为「弹幕穿透一群怪还不消失」。
local function untrack_on_hit_npc(projectile)
    util.untrack_projectile_handle(projectile)
end

function M.register()
    q.register_projectile{
        name = ids.projectile.beam,
        texture = "CrystalBeam.png",
        width = 16, height = 16,
        damage = 40, knockBack = 2.0, timeLeft = 45,
        friendly = true, hostile = false,
        tileCollide = false, penetrate = 1, light = 0.7,
        ai = adaptive_ai,
        on_hit_player = untrack_on_hit_player,
        on_hit_npc = untrack_on_hit_npc,
    }

    q.register_projectile{
        name = ids.projectile.bolt,
        texture = "CrystalBolt.png",
        width = 12, height = 12,
        damage = 38, knockBack = 1.5, timeLeft = 60,
        friendly = true, hostile = false,
        tileCollide = true, penetrate = 0, light = 0.5,
        ai = straight_ai,
    }

    q.register_projectile{
        name = ids.projectile.shot,
        texture = "CrystalShot.png",
        width = 12, height = 12,
        damage = 28, knockBack = 1.0, timeLeft = 30,
        friendly = true, hostile = false,
        tileCollide = true, penetrate = 0, light = 0.4,
        ai = straight_ai,
    }

    q.register_projectile{
        name = ids.projectile.magic,
        texture = "CrystalMagicBolt.png",
        width = 16, height = 16,
        damage = 42, knockBack = 2.5, timeLeft = 70,
        friendly = true, hostile = false,
        tileCollide = false, penetrate = 2, light = 0.8,
        ai = straight_ai,
    }

    -- 中立弹幕：不参与碰撞，只负责跟随和放弹
    q.register_projectile{
        name = ids.projectile.minion,
        texture = "CrystalMinion.png",
        width = 26, height = 26,
        damage = 0, knockBack = 0, timeLeft = 36000,
        friendly = false, hostile = false,
        tileCollide = false, penetrate = -1, light = 0.4,
        ai = minion_ai,
    }

    q.register_projectile{
        name = ids.projectile.minion_shot,
        texture = "CrystalMinionShot.png",
        width = 12, height = 12,
        damage = 24, knockBack = 1.5, timeLeft = 50,
        friendly = true, hostile = false,
        tileCollide = true, penetrate = 0, light = 0.5,
        ai = straight_ai,
    }

    -- 召唤物专用晶刺：跟 Boss 的同贴图，但尺寸小一圈、伤害更高、只打怪
    q.register_projectile{
        name = ids.projectile.minion_spike,
        texture = "CrystalSpike.png",
        width = 18, height = 18, scale = 0.9,
        damage = 40, knockBack = 2.0, timeLeft = 120,
        friendly = true, hostile = false,
        tileCollide = false, penetrate = 0, light = 0.6,
        ai = adaptive_ai,
        on_hit_npc = untrack_on_hit_npc,
        on_hit_player = untrack_on_hit_player,
    }

    q.register_projectile{
        name = ids.projectile.spike,
        texture = "CrystalSpike.png",
        width = 28, height = 28, scale = 1.4,
        damage = 32, knockBack = 3.0, timeLeft = 300,
        friendly = false, hostile = true,
        tileCollide = false, penetrate = 0, light = 0.6,
        -- 默认直线；ai0 = 1 时才弱追踪（只给狙击那几发用）
        ai = adaptive_ai,
        on_hit_player = untrack_on_hit_player,
        on_hit_npc = untrack_on_hit_npc,
    }

    q.register_projectile{
        name = ids.projectile.spike_red,
        texture = "CrystalSpikeRed.png",
        width = 30, height = 30, scale = 2.0,
        damage = 40, knockBack = 3.5, timeLeft = 340,
        friendly = false, hostile = true,
        tileCollide = false, penetrate = 0, light = 0.7,
        ai = straight_ai,
    }

    local ok, err = pcall(q.install_hook_postfix, "Terraria", "Projectile", "AI",
            shard_homing, { argc = 0 })
    if not ok then
        mod.warn("碎晶之链：Projectile.AI 钩子安装失败 " .. tostring(err))
    end

    -- 自定义弹幕每帧都会被内核重置成 active=false / timeLeft=0（实测：补完立刻是 true，
    -- 下一帧又变回 false）。所以在 Projectile.Update 的 prefix 里把它补回来，
    -- 这样本次更新读到的就是活着的弹幕，位移、命中、寿命都能正常走。
    local ok2, err2 = pcall(q.install_hook_prefix, "Terraria", "Projectile", "Update",
            repair_custom_projectile, { argc = 1 })
    if not ok2 then
        mod.warn("碎晶之链：Projectile.Update 修复钩子安装失败 " .. tostring(err2))
    end

    -- 自动登记先关掉（1.2.49 对照实验）：1.2.39 能跑通的那版没有它，
    -- 那时候是在生成处按返回值显式登记。等实验结论出来再决定要不要开。
    local AUTOTRACK = false
    if AUTOTRACK then
        local ok3, err3 = pcall(q.install_hook_postfix, "Terraria", "Projectile", "SetDefaults",
                autotrack_on_setdefaults, { argc = 1 })
        if not ok3 then
            mod.warn("碎晶之链：Projectile.SetDefaults 钩子安装失败 " .. tostring(err3))
        end
    end
end

return M
