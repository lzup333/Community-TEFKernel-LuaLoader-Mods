-- 世纪之花召唤物 v3.0
--   · 地狱（ZoneUnderworldHeight）：试炼/二阶段种子雨伤害 ×2；
--     被弹幕打中（单次掉血 > 12）额外附加 5 秒诅咒之火（Buff 39）。
--
-- v2.9
--   · 丛林提示词同步：试炼开始时播报“丛林：数值×2/3”与实际存活秒数，
--     二阶段播报实际无敌秒数；tooltip 写明丛林规则。
--
-- v2.8
--   · 丛林环境里：试炼时长/(攻击间隔反向)/弹幕数量/伤害、二阶段无敌时长/
--     种子雨频率/伤害全部 ×2/3；迷雾效果不参与缩放。
--
-- v2.7
--   · 世纪之花血量 <= 50% 进入二阶段：15 秒（900 tick）闪烁无敌
--     （dontTakeDamage + alpha 闪烁），并从天上落种子雨；
--   · 种子雨覆盖半径 = 迷雾直径 7168 的一半（3584 直径，半径 1792）。
--
-- v2.6.1
--   · 修 trial_end 里被误插入的核心生成代码（引用未定义变量，失败时直接报错，
--     导致雾不散、trial.active 卡住无法重新召唤）。现在失败会清核心+雾+状态。
--
-- v2.6
--   · 玩家死亡时立即切断试炼：dead 改为字段/属性/statLife 三路判定，
--     ItemCheck 钩子也会检查；核心/雾全部清掉，不会等复活继续发射。
--
-- v2.5
--   · 试炼核心恢复成“弹幕实体”（可被砍中/击退，算是玩法的一部分），
--     核心绕玩家 320px 旋转并发射原版弹幕；被反弹技能击中有位移/瞬移属正常。
--   · 攻击间隔保持 15 tick（每 45 tick 一轮 3 发）。
--
-- v2.4
--   · 试炼不再有可被击中的核心弹幕（被反弹的村正技能砍中会“瞬移”）：
--     改由 ItemCheck 钩子驱动，位置/计时/弹幕全在 Lua 里算。
--   · 攻击间隔 15 tick（每 45 tick 一轮 3 发），弹幕量更大。
--
-- v2.3
--   · 雾改成圆形（1024×1024 圆形雾团，scale 7 ≈ 7168 直径），
--     开最大视野也能覆盖；不再是长方形。
--
-- v2.2
--   · 试炼弹幕改成世界之花原版弹幕：275 种子 / 276 毒种 / 277 荆棘球，
--     带真实伤害（40/50/60），核心绕玩家 320px 旋转并向玩家预判射击。
--   · 追踪弹幕改为按“玩家中心 = position + 宽高/2”取值，速度 9，每 0.33 秒
--     生成 3 颗，最多 24 颗。
--   · 从试炼开始到世纪之花被击杀，一直有雾蒙蒙的全屏光景（PlanteraMist）。
--
-- v1.8
--   · 找到真正原因：这个内核里 NPC.SpawnOnPlayer 是 6 个参数
--     (int plr, int npcType, float ai0..ai3)，之前按 2 参调用所以一直失败。
--     现在按 6 参调用；NewNPC 仍保留 10 参兜底。
--   · 召唤位置改为玩家面向方向 60 格（960px）外；SpawnOnPlayer 生成在
--     身边时会把世纪之花挪到 60 格处，留出反应时间。
--   · 判断“场上有没有世纪之花”改用 NPC.AnyNPCs(262)，不再手写遍历
--     Main.npc，避免误报导致“过一会就不能召”。
--   · 物品不消耗；使用/失败都会在聊天栏给结果。
--
-- v1.5
--   · 物品改成不消耗（可反复使用），避免“召过一次之后就没了”。
--   · 召唤前清掉 life<=0 的世纪之花残留，击杀后可以立刻再召。
--   · 提示会写场上还活着几只。
--   · 配方恢复为叶绿锭 ×10 + 丛林孢子 ×15 @ 秘银砧。
--   · 召唤判定只有一条：场上没有活着的世纪之花（262）。已经有的话会明确
--     提示“场上已经有一只活着的世纪之花”，不再静默失败。
--
-- v1.2：枚举 SpawnOnPlayer / NewNPC 的所有重载逐个尝试，并把每个失败原因
--       带到聊天栏，便于定位到底是哪个方法/参数不对。
--
-- v1.0 实机“怎么都召不出来”，这版改成三条路 + 每 tick 兜底：
--   1) NPC.SpawnOnPlayer(player, 262)   —— 原版 Boss 苏醒流程
--   2) NPC.NewNPC(EntitySource, x, y, 262, ..., target)
--   3) 如果 UseItem 回调没被加载器派发，ItemCheck 钩子里检测“手持本物品
--      并按住使用”同样会召唤（30 tick 冷却），保证一定能触发。
-- 每次失败都会在聊天栏说明是哪一步失败，方便定位。
--
-- 入口整体 pcall 保护；物品贴图 16 帧动态图。

pcall(require, "quickapi")

local q = mod.quickapi
local P = mod.patch
local M = {}

local PLANTERA = 262
local ITEM_NAME = "plantera_summon"
local registered = false
local item_id = -1
local last_try = -999

local function log(msg)
    if type(mod.warn) == "function" then pcall(mod.warn, "[Plantera] " .. tostring(msg)) end
end
local function stype(ns, cls)
    local ok, t = pcall(P.get_type, ns, cls)
    if ok then return t end
    return nil
end
local function smethod(t, name, argc)
    if not t then return nil end
    local ok, m = pcall(P.get_method, t, name, argc)
    if ok then return m end
    return nil
end
local function sfield(t, name)
    if not t then return nil end
    local ok, f = pcall(P.get_field, t, name)
    if ok then return f end
    return nil
end
local function fget(ns, cls, name, inst, kind)
    local ok, v = pcall(q.get_field_value, ns, cls, name, inst, kind or "int32")
    if ok then return v end
    return nil
end
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function write(ns, cls, name, inst, v, kind)
    local ok = pcall(q.set_field_value, ns, cls, name, inst, v, kind or "int32")
    return ok
end
local function read_vec2(ns, cls, name, inst)
    local ok, a, b = pcall(q.vec.get, ns, cls, name, inst)
    if ok and type(a) == "number" then return a, b end
    return nil
end
local function write_vec2(ns, cls, name, inst, x, y)
    local ok = pcall(q.vec.set, ns, cls, name, inst, x, y)
    return ok
end

local function fval(f, inst, kind)
    if not f then return nil end
    local ok, v = pcall(P.get_field_value, f, inst, kind or "int32")
    if ok then return v end
    return nil
end

-- ---------------- 聊天栏 ----------------
local notify_m5, notify_m4, notify_tried = nil, nil, false
local function notify(text)
    if not notify_tried then
        notify_tried = true
        local ok5, m5 = pcall(q.method, "Terraria", "Main", "NewText", 5)
        local ok4, m4 = pcall(q.method, "Terraria", "Main", "NewText", 4)
        notify_m5 = (ok5 and m5) or nil
        notify_m4 = (ok4 and m4) or nil
    end
    if type(P.string_create) ~= "function" then return end
    local okc, s = pcall(P.string_create, text)
    if not okc or not s then return end
    if notify_m5 then
        local ok, ret = pcall(P.invoke, notify_m5, s, 255, 120, 220, false)
        if ok and ret ~= false then return end
    end
    if notify_m4 then pcall(P.invoke, notify_m4, s, 255, 120, 220) end
end

-- ---------------- 字段 ----------------
local T_NPC = stype("Terraria", "NPC")
local T_PLAYER = stype("Terraria", "Player")
-- 这个内核里 NPC.SpawnOnPlayer 是 6 参：plr, npcType, ai0..ai3
local M_spawn_on_player = smethod(T_NPC, "SpawnOnPlayer", 6)
    or smethod(T_NPC, "SpawnOnPlayer", 2)
local M_any_npcs = smethod(T_NPC, "AnyNPCs", 1)
local M_new_npc = nil
local f_pj_active = sfield(stype("Terraria", "Projectile"), "active")
local f_pj_type = sfield(stype("Terraria", "Projectile"), "type")
local f_pj_owner = sfield(stype("Terraria", "Projectile"), "owner")
local f_npc_type = sfield(T_NPC, "type")
local f_npc_active = sfield(T_NPC, "active")
local f_npc_life = sfield(T_NPC, "life")
local f_npc_lifeMax = sfield(T_NPC, "lifeMax")
local f_npc_dont = sfield(T_NPC, "dontTakeDamage")
local f_npc_alpha = sfield(T_NPC, "alpha")
local f_npc_who = sfield(T_NPC, "whoAmI")
local f_pl_inv = sfield(T_PLAYER, "inventory")
local f_pl_sel = sfield(T_PLAYER, "selectedItem")
local f_pl_use = sfield(T_PLAYER, "controlUseItem")

-- EntitySource（NewNPC 需要）
local src_cache, src_tried = nil, false
local function get_source()
    if src_tried then return src_cache end
    src_tried = true
    local st = stype("Terraria.DataStructures", "EntitySource_SpawnNPC")
    if st then
        local ok, inst = pcall(P.new_instance, st)
        if ok and inst then src_cache = inst end
    end
    return src_cache
end

-- 返回：是否有活着的世纪之花。
-- 先用内核 NPC.AnyNPCs(262)；true 时再用 life>0 确认，避免死亡动画残留。
local function scan_plantera()
    local ok, arr = pcall(q.get_field_value, "Terraria", "Main", "npc", nil, "object")
    if not ok or not arr then return nil end
    local okn, n = pcall(P.array_length, arr)
    if not okn or type(n) ~= "number" then return nil end
    local alive = 0
    for i = 0, n - 1 do
        local okp, npc = pcall(P.array_at, arr, i)
        if okp and npc and fval(f_npc_active, npc, "bool") == true then
            if fval(f_npc_type, npc, "int32") == PLANTERA then
                local life = fval(f_npc_life, npc, "int32") or 0
                if life > 0 then
                    alive = alive + 1
                else
                    pcall(q.set_field_value, "Terraria", "NPC", "active", npc, false, "bool")
                end
            end
        end
    end
    return alive
end

local function plantera_alive()
    if M_any_npcs then
        local ok, res = pcall(P.invoke, M_any_npcs, PLANTERA)
        if ok and type(res) == "boolean" then
            if not res then return false, 0 end
            -- AnyNPCs 说 true：再用 life 确认，死亡残留当没有
            local alive = scan_plantera()
            if alive == nil then return true, 1 end  -- 读不到就信 AnyNPCs
            return alive > 0, alive
        end
    end
    local alive = scan_plantera()
    if alive == nil then return false, 0 end
    return alive > 0, alive
end

local M_proj_kill = smethod(stype("Terraria", "Projectile"), "Kill", 0)
local function kill_proj(p)
    if not p then return end
    local done = false
    if M_proj_kill then
        local ok = pcall(P.invoke, M_proj_kill, p)
        done = ok
    end
    if not done then
        -- 立即从弹幕表里摘掉（Kill 方法取不到时用）
        pcall(q.set_field_value, "Terraria", "Projectile", "active", p, false, "bool")
        pcall(q.set_field_value, "Terraria", "Projectile", "timeLeft", p, 0, "int32")
    end
end

local T_PROJ = stype("Terraria", "Projectile")
local M_new_proj = smethod(T_PROJ, "NewProjectile", 13)
    or smethod(T_PROJ, "NewProjectile", 12)
    or smethod(T_PROJ, "NewProjectile")

local function projectile_at(idx)
    local arr = q.get_field_value("Terraria", "Main", "projectile", nil, "object")
    if not arr or idx == nil then return nil end
    local ok, pr = pcall(P.array_at, arr, idx)
    if ok then return pr end
    return nil
end

local function spawn_proj(id, x, y, vx, vy, dmg, kb, owner, ai0, ai1, ai2, scale)
    if not id or id < 0 or not M_new_proj then return -1 end
    local ok, res = pcall(P.invoke, M_new_proj, nil, x, y, vx, vy, id,
        dmg or 0, kb or 0, owner or 0, ai0 or 0, ai1 or 0, ai2 or 0, nil)
    if not ok then return -1 end
    local idx = tonumber(res) or -1
    if idx >= 0 and scale then
        local arr = q.get_field_value("Terraria", "Main", "projectile", nil, "object")
        if arr then
            local okp, pr = pcall(P.array_at, arr, idx)
            if okp and pr then
                pcall(q.set_field_value, "Terraria", "Projectile", "scale", pr, scale, "float")
            end
        end
    end
    return idx
end

local function player_at(idx)
    local ok, arr = pcall(q.get_field_value, "Terraria", "Main", "player", nil, "object")
    if not ok or not arr then return nil end
    local okp, pl = pcall(P.array_at, arr, idx)
    if okp then return pl end
    return nil
end

local function proj_center(p)
    local x, y = read_vec2("Terraria", "Projectile", "position", p)
    if not x then return nil end
    local w = fget("Terraria", "Projectile", "width", p, "int32") or 0
    local h = fget("Terraria", "Projectile", "height", p, "int32") or 0
    return x + w / 2, y + h / 2
end

local prop_zone_jungle
local function is_jungle(pl)
    if not pl then return false end
    local v = fget("Terraria", "Player", "ZoneJungle", pl, "bool")
    if v == true then return true end
    if not prop_zone_jungle then
        local okp, pr = pcall(q.property, "Terraria", "Player", "ZoneJungle")
        if okp and pr then
            local okg, g = pcall(P.property_get_method, pr)
            if okg and g then prop_zone_jungle = g end
        end
        if not prop_zone_jungle then prop_zone_jungle = false end
    end
    if prop_zone_jungle then
        local okv, r = pcall(P.invoke, prop_zone_jungle, pl)
        if okv and r == true then return true end
    end
    return false
end

-- 丛林里所有数值 ×2/3（迷雾效果不参与）
local prop_under
local function is_underworld(pl)
    if not pl then return false end
    local v = fget("Terraria", "Player", "ZoneUnderworldHeight", pl, "bool")
    if v == true then return true end
    if not prop_under then
        local okp, pr = pcall(q.property, "Terraria", "Player", "ZoneUnderworldHeight")
        if okp and pr then
            local okg, g = pcall(P.property_get_method, pr)
            if okg and g then prop_under = g end
        end
        if not prop_under then prop_under = false end
    end
    if prop_under then
        local okv, r = pcall(P.invoke, prop_under, pl)
        if okv and r == true then return true end
    end
    return false
end

local UNDER = { last = nil }
local function underworld_tick(pl)
    if not pl then UNDER.last = nil; return end
    local life = fget("Terraria", "Player", "statLife", pl, "int32")
    if is_underworld(pl) and (trial.active or PHASE.active) and type(life) == "number" then
        if UNDER.last and life < UNDER.last - 12 then
            -- 被我们的弹幕打中（掉血 > 12），附带诅咒之火 5 秒
            pcall(q.invoke, "Terraria", "Player", "AddBuff", pl, 39, 300)
        end
    end
    UNDER.last = life
end

local function jungle_scale(pl, v)
    if is_jungle(pl) then return v * 2 / 3 end
    return v
end

local prop_dead
local function player_dead(pl)
    if not pl then return true end
    local d = fget("Terraria", "Player", "dead", pl, "bool")
    if d == true then return true end
    if not prop_dead then
        local okp, pr = pcall(q.property, "Terraria", "Player", "dead")
        if okp and pr then
            local okg, g = pcall(P.property_get_method, pr)
            if okg and g then prop_dead = g end
        end
        if not prop_dead then prop_dead = false end
    end
    if prop_dead then
        local okv, v = pcall(P.invoke, prop_dead, pl)
        if okv and v == true then return true end
    end
    local life = fget("Terraria", "Player", "statLife", pl, "int32")
    if type(life) == "number" and life <= 0 then return true end
    return false
end

local function player_center(player)
    -- 按《人物中心位置》文档：position 是碰撞箱左上角，中心 = position + 宽高/2
    local x, y = read_vec2("Terraria", "Player", "position", player)
    local w = fget("Terraria", "Player", "width", player, "int32") or 20
    local h = fget("Terraria", "Player", "height", player, "int32") or 40
    if x then return x + w / 2, y + h / 2 end
    -- 退回 Center 属性
    local okp, prop = pcall(q.property, "Terraria", "Player", "Center")
    if okp and prop then
        local okg, g = pcall(P.property_get_method, prop)
        if okg and g then
            local okv, px, py = pcall(P.invoke, g, player)
            if okv and type(px) == "number" then return px, py end
        end
    end
    return nil
end

local function local_player_index()
    return fget("Terraria", "Main", "myPlayer", nil, "int32") or 0
end
local function player_index_of(player)
    return fget("Terraria", "Player", "whoAmI", player, "int32")
end

local function held_item(player)
    local inv = fval(f_pl_inv, player, "object")
    if not inv then return nil end
    local sel = fval(f_pl_sel, player, "int32") or 0
    local ok, it = pcall(P.array_at, inv, sel)
    if ok then return it end
    return nil
end

-- ---------------- 召唤 ----------------
local function method_list(name)
    local out = {}
    if not T_NPC then return out end
    local ok, list = pcall(P.get_methods, T_NPC, true)
    if not ok or type(list) ~= "table" then return out end
    for _, m in ipairs(list) do
        local okn, mn = pcall(P.method_name, m)
        if okn and mn == name then out[#out + 1] = m end
    end
    return out
end

-- 60 格 = 960 像素；朝玩家面向的方向生成，太靠世界边缘就反向
local function spawn_point(player)
    local cx, cy = player_center(player)
    if not cx then return nil end
    local dir = fget("Terraria", "Player", "direction", player, "int32") or 1
    if dir == 0 then dir = 1 end
    local x = cx + dir * 60 * 16
    local y = cy - 96
    local mx = fget("Terraria", "Main", "maxTilesX", nil, "int32") or 0
    local my = fget("Terraria", "Main", "maxTilesY", nil, "int32") or 0
    local maxx = mx > 0 and mx * 16 or 1e9
    local maxy = my > 0 and my * 16 or 1e9
    if x < 160 or x > maxx - 160 then
        x = cx - dir * 60 * 16
    end
    if x < 160 then x = 160 elseif x > maxx - 160 then x = maxx - 160 end
    if y < 160 then y = 160 elseif y > maxy - 160 then y = maxy - 160 end
    return x, y
end

-- 把刚召出来的世纪之花挪到目标点（SpawnOnPlayer 会生成在玩家身边）
local function move_plantera(sx, sy)
    local ok, arr = pcall(q.get_field_value, "Terraria", "Main", "npc", nil, "object")
    if not ok or not arr then return end
    local okn, n = pcall(P.array_length, arr)
    if not okn or type(n) ~= "number" then return end
    for i = n - 1, 0, -1 do
        local okp, npc = pcall(P.array_at, arr, i)
        if okp and npc and fval(f_npc_active, npc, "bool") == true
            and fval(f_npc_type, npc, "int32") == PLANTERA
            and (fval(f_npc_life, npc, "int32") or 0) > 0 then
            local w = fget("Terraria", "NPC", "width", npc, "int32") or 0
            local h = fget("Terraria", "NPC", "height", npc, "int32") or 0
            -- position 是 Vector2，用 vec.set 更稳
            pcall(q.vec.set, "Terraria", "NPC", "position", npc, x - w / 2, y - h / 2)
            pcall(q.set_field_value, "Terraria", "NPC", "velocity", npc, 0, "object")
            pcall(q.vec.set, "Terraria", "NPC", "velocity", npc, 0, 0)
            return
        end
    end
end

local function try_spawn(player)
    local alive, cnt = plantera_alive()
    if alive then
        return false, "场上已有 " .. tostring(cnt) .. " 只活着的世纪之花"
    end
    local idx = fget("Terraria", "Player", "whoAmI", player, "int32") or 0
    local sx, sy = spawn_point(player)
    local src = get_source()
    local errs = {}

    -- 1) 枚举所有 SpawnOnPlayer 重载：索引版 / 玩家对象版都试
    for _, m in ipairs(method_list("SpawnOnPlayer")) do
        local n = 0
        pcall(function() n = P.method_param_count(m) or 0 end)
        local tries = {}
        if n >= 6 then
            tries = {
                { idx, PLANTERA, 0, 0, 0, 0 },
                { player, PLANTERA, 0, 0, 0, 0 },
            }
        elseif n == 2 then
            tries = { { idx, PLANTERA }, { player, PLANTERA } }
        elseif n == 1 then
            tries = { { PLANTERA } }
        end
        for _, a in ipairs(tries) do
            local ok, err = pcall(P.invoke, m, table.unpack(a))
            if ok then
                if plantera_alive() then
                    if sx then move_plantera(sx, sy) end
                    return true, "SpawnOnPlayer(" .. n .. ")"
                end
                errs[#errs + 1] = "SoP" .. n .. "已调用但没生成"
            else
                errs[#errs + 1] = "SoP" .. n .. ":" .. tostring(err)
            end
        end
    end

    -- 2) 枚举所有 NewNPC 重载，按参数个数拼
    if sx then
        for _, m in ipairs(method_list("NewNPC")) do
            local n = 0
            pcall(function() n = P.method_param_count(m) or 0 end)
            local a
            if n >= 4 and not src then
                a = nil
            elseif n >= 10 then
                a = { src, sx, sy, PLANTERA, 0, 0, 0, 0, 0, idx }
            elseif n == 9 then
                a = { src, sx, sy, PLANTERA, 0, 0, 0, 0, idx }
            elseif n == 8 then
                a = { src, sx, sy, PLANTERA, 0, 0, 0, idx }
            elseif n == 7 then
                a = { src, sx, sy, PLANTERA, 0, 0, idx }
            elseif n == 6 then
                a = { src, sx, sy, PLANTERA, 0, idx }
            elseif n == 5 then
                a = { src, sx, sy, PLANTERA, idx }
            elseif n == 4 then
                a = { src, sx, sy, PLANTERA }
            elseif n == 3 then
                a = { sx, sy, PLANTERA }
            end
            if a then
                local ok, err = pcall(P.invoke, m, table.unpack(a))
                if ok and plantera_alive() then
                    if sx then move_plantera(sx, sy) end
                    return true, "NewNPC(" .. n .. ")"
                end
                if not ok then errs[#errs + 1] = "NN" .. n .. ":" .. tostring(err) end
            end
        end
    else
        errs[#errs + 1] = "无玩家坐标"
    end

    -- 3) 直接 q.invoke 名字（含 nil source 的 NewNPC）
    local ok3 = pcall(q.invoke, "Terraria", "NPC", "SpawnOnPlayer", idx, PLANTERA, 0, 0, 0, 0)
    if not ok3 then
        ok3 = pcall(q.invoke, "Terraria", "NPC", "SpawnOnPlayer", idx, PLANTERA)
    end
    if ok3 and plantera_alive() then
        if sx then move_plantera(sx, sy) end
        return true, "q.SpawnOnPlayer"
    end
    if sx then
        local tries = {
            { n = 10, a = { nil, sx, sy, PLANTERA, 0, 0, 0, 0, 0, idx } },
            { n = 9,  a = { nil, sx, sy, PLANTERA, 0, 0, 0, 0, idx } },
            { n = 8,  a = { nil, sx, sy, PLANTERA, 0, 0, 0, idx } },
            { n = 3,  a = { sx, sy, PLANTERA } },
        }
        for _, t in ipairs(tries) do
            local ok4 = pcall(q.invoke, "Terraria", "NPC", "NewNPC", table.unpack(t.a, 1, t.n))
            if ok4 and plantera_alive() then
                if sx then move_plantera(sx, sy) end
                return true, "NewNPC(nil," .. t.n .. ")"
            end
        end
    end

    local msg = table.concat(errs, " | ")
    if #msg > 180 then msg = msg:sub(1, 180) .. "..." end
    return false, msg ~= "" and msg or "没有可用的召唤方法"
end


-- ============================================================
-- 试炼：召唤前先进入「只有弹幕、一直瞄准你」的阶段
--   · 核心弹幕悬在玩家头顶，持续 20 秒；
--   · 每 0.5 秒生成一颗追踪弹幕，朝玩家当前位置缓慢追踪；
--   · 被任意一颗弹幕贴近（<26px）→ 试炼失败，全部清掉；
--   · 存活满 20 秒 → 试炼通过，才真正召唤世纪之花。
-- ============================================================
local trial = {
    active = false,
    ticks = 0,
    duration = 1200,     -- 20 秒
    core_idx = nil,
    core_id = -1,
    orb_id = -1,
    last_spawn = 0,
    jungle = false,
}

local MIST = { idx = nil, saw = false }

local function mist_ai(proj)
    pcall(function()
        local owner = fval(f_pj_owner, proj, "int32") or 0
        local pl = player_at(owner)
        if not pl then kill_proj(proj); return end
        local cx, cy = player_center(pl)
        if not cx then kill_proj(proj); return end
        -- 1024 的圆形雾，scale 7 → 直径 7168，开最大视野也能盖住
        write_vec2("Terraria", "Projectile", "position", proj, cx - 512, cy - 512)
        write("Terraria", "Projectile", "scale", proj, 7.0, "float")
        write("Terraria", "Projectile", "timeLeft", proj, 60, "int32")
        local alive = plantera_alive()
        if alive then MIST.saw = true end
        if MIST.saw and not alive then
            -- 世纪之花已经被打死：收雾
            MIST.saw = false
            MIST.idx = nil
            kill_proj(proj)
        end
    end)
end

local function kill_mist()
    local p = MIST.idx and projectile_at(MIST.idx) or nil
    if p then kill_proj(p) end
    MIST.idx = nil
    MIST.saw = false
end

local function trial_running()
    if not trial.active then return false end
    local core = trial.core_idx and projectile_at(trial.core_idx) or nil
    if core and fval(f_pj_active, core, "bool") == true then return true end
    trial.active = false
    trial.ticks = 0
    trial.core_idx = spawn_proj(trial.core_id, cx - 24, cy - 110, 0, 0, 0, 0, idx, 0, 0, 0, 1)
    if not trial.core_idx or trial.core_idx < 0 then
        trial.active = false
        return false, "试炼核心生成失败"
    end
    return false
end

local function orb_count()
    if trial.orb_id < 0 then return 0 end
    local arr = q.get_field_value("Terraria", "Main", "projectile", nil, "object")
    if not arr then return 0 end
    local okn, n = pcall(P.array_length, arr)
    if not okn or type(n) ~= "number" then return 0 end
    local c = 0
    for i = 0, n - 1 do
        local okp, pr = pcall(P.array_at, arr, i)
        if okp and pr and fval(f_pj_active, pr, "bool") == true
            and fval(f_pj_type, pr, "int32") == trial.orb_id then
            c = c + 1
        end
    end
    return c
end

local function kill_orbs()
    if trial.orb_id < 0 then return end
    local arr = q.get_field_value("Terraria", "Main", "projectile", nil, "object")
    if not arr then return end
    local okn, n = pcall(P.array_length, arr)
    if not okn or type(n) ~= "number" then return end
    for i = 0, n - 1 do
        local okp, pr = pcall(P.array_at, arr, i)
        if okp and pr and fval(f_pj_active, pr, "bool") == true
            and fval(f_pj_type, pr, "int32") == trial.orb_id then
            kill_proj(pr)
        end
    end
end

local function trial_end(success, player)
    local core = trial.core_idx and projectile_at(trial.core_idx) or nil
    if core then kill_proj(core) end
    trial.core_idx = nil
    kill_orbs()
    
    if trial.wave_bullets then
        for _, b in ipairs(trial.wave_bullets) do
            local p = projectile_at(b.idx)
            if p then kill_proj(p) end
        end
        trial.wave_bullets = nil
    end
    
    trial.active = false
    trial.ticks = 0
    if not success then kill_mist() end
    if success then
        notify("试炼通过！世纪之花苏醒！")
        local ok, why = try_spawn(player)
        if not ok then notify("召唤失败：" .. tostring(why)) end
    else
        notify("试炼失败：被世界之花的弹幕击中，再来一次")
    end
end

local function trial_orb_ai(proj)
    pcall(function()
        local owner = fval(f_pj_owner, proj, "int32") or 0
        local pl = player_at(owner)
        if not pl then
            kill_proj(proj)
            return
        end
        local px, py = proj_center(proj)
        local cx, cy = player_center(pl)
        if not px or not cx then kill_proj(proj); return end
        -- 预判玩家速度，让“追踪”看起来真的是在瞄人
        local pvx, pvy = read_vec2("Terraria", "Player", "velocity", pl)
        if pvx then cx, cy = cx + pvx * 14, cy + pvy * 14 end
        local dx, dy = cx - px, cy - py
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 1 then d = 1 end
        local sp = 9.0
        write_vec2("Terraria", "Projectile", "velocity", proj, dx / d * sp, dy / d * sp)
        write_vec2("Terraria", "Projectile", "position", proj, px + dx / d * sp, py + dy / d * sp)
        write("Terraria", "Projectile", "rotation", proj, atan2(dy, dx), "float")
        write("Terraria", "Projectile", "timeLeft", proj, 600, "int32")
        -- 命中判定：贴近玩家就算失败
        if d < 26 then
            trial_end(false, pl)
        end
    end)
end

-- 试炼主循环：不再用“可被击中的核心弹幕”，全部由 ItemCheck 钩子驱动，
-- 这样被反弹的村正技能砍到也没有东西会瞬移。
local T_DUST = stype("Terraria", "Dust")
local M_new_dust = smethod(T_DUST, "NewDust", 9)
local M_add_light = smethod(stype("Terraria", "Lighting"), "AddLight", 5)

local function trial_visual(x, y, scale)
    if M_add_light then pcall(P.invoke, M_add_light, x, y, 0.9, 0.4, 0.8) end
    if M_new_dust then
        for i = 1, 3 do
            pcall(P.invoke, M_new_dust, x + math.random(-8, 8), y + math.random(-8, 8),
                1, 1, 278, 0, 0, 0, nil, (scale or 1) * 1.4)
        end
    end
end

local function trial_core_ai(proj)
    pcall(function()
        local owner = fval(f_pj_owner, proj, "int32") or 0
        local pl = player_at(owner)
        if not pl or trial.active ~= true then
            kill_proj(proj)
            return
        end
        if player_dead(pl) then
            trial_end(false, pl)
            return
        end
        local cx, cy = player_center(pl)
        if not cx then kill_proj(proj); return end

        trial.ticks = (trial.ticks or 0) + 1
        local ang = trial.ticks * 0.03
        local ox = cx + math.cos(ang) * 320
        local oy = cy + math.sin(ang) * 320 - 80
        write_vec2("Terraria", "Projectile", "position", proj, ox - 24, oy - 24)
        write("Terraria", "Projectile", "timeLeft", proj, 60, "int32")
        write("Terraria", "Projectile", "rotation", proj, ang, "float")

        local jf = trial.jungle and (2 / 3) or 1

        -- ====== 【旧功能保留】瞄准玩家射击 ======
        local interval = math.max(6, math.floor(15 * jf))
        if trial.ticks % interval == 0 then
            local n = (trial.ticks % (interval * 3) == 0) and 3 or 2
            n = math.max(1, math.floor(n * jf + 0.5))
            for k = 1, n do
                local r = math.random()
                local ty, dmg
                if r < 0.55 then ty, dmg = 275, 40
                elseif r < 0.85 then ty, dmg = 276, 50
                else ty, dmg = 277, 60 end
                dmg = math.max(1, math.floor(dmg * jf))
                if is_underworld(pl) then dmg = dmg * 2 end
                local tx, tyy = player_center(pl)
                local pvx, pvy = read_vec2("Terraria", "Player", "velocity", pl)
                if pvx then tx, tyy = tx + pvx * 10, tyy + pvy * 10 end
                local dx, dy = tx - ox, tyy - oy
                local d = math.sqrt(dx * dx + dy * dy)
                if d < 1 then d = 1 end
                spawn_proj(ty, ox - 8, oy - 8, dx / d * 12, dy / d * 12, dmg, 3, 255, 0, 0, 0, 1)
            end
        end

        -- ====== 【新功能保留】2秒积攒后爆裂的荆棘球阵 ======
        trial.wave_timer = (trial.wave_timer or 0) + 1
        if not trial.wave_bullets then
            if trial.wave_timer >= (trial.wave_cd or 0) then
                trial.wave_bullets = {}
                local count = 16      -- 一圈 16 颗
                local radius = 180    -- 围绕玩家半径 180 像素
                for i = 1, count do
                    local b_ang = (i - 1) * (math.pi * 2 / count)
                    local bx = cx + math.cos(b_ang) * radius - 8
                    local by = cy + math.sin(b_ang) * radius - 8
                    local idx = spawn_proj(277, bx, by, 0, 0, 60, 3, 255, 0, 0, 0, 1)
                    if idx >= 0 then
                        table.insert(trial.wave_bullets, { idx = idx, ang = b_ang })
                    end
                end
                trial.wave_timer = 0
            end
        else
            -- 锁住这圈子弹的位置，不让它们因为重力掉下去
            for _, b in ipairs(trial.wave_bullets) do
                local p = projectile_at(b.idx)
                if p and fval(f_pj_active, p, "bool") == true then
                    local bx = cx + math.cos(b.ang) * 180 - 8
                    local by = cy + math.sin(b.ang) * 180 - 8
                    write_vec2("Terraria", "Projectile", "position", p, bx, by)
                    write_vec2("Terraria", "Projectile", "velocity", p, 0, 0)
                end
            end
            
            -- 2 秒（120 tick）后向四周爆开
            if trial.wave_timer >= 120 then
                for _, b in ipairs(trial.wave_bullets) do
                    local p = projectile_at(b.idx)
                    if p and fval(f_pj_active, p, "bool") == true then
                        local speed = 12
                        write_vec2("Terraria", "Projectile", "velocity", p, math.cos(b.ang) * speed, math.sin(b.ang) * speed)
                    end
                end
                trial.wave_bullets = nil
                trial.wave_timer = 0
                trial.wave_cd = 60 -- 爆开后休息 1 秒，重新积攒
            end
        end
        -- ============================================

        local duration = math.floor(1200 * jf)
        if trial.ticks >= duration then
            trial_end(true, pl)
        end
    end)
end

local function trial_tick(player)
    if not trial.active then return end
    if fget("Terraria", "Player", "dead", player, "bool") == true then
        trial_end(false, player)
        return
    end
    local cx, cy = player_center(player)
    if not cx then
        trial_end(false, player)
        return
    end
    trial.ticks = (trial.ticks or 0) + 1
    local ang = trial.ticks * 0.03
    local ox = cx + math.cos(ang) * 320
    local oy = cy + math.sin(ang) * 320 - 80
    trial_visual(ox, oy, 1)

    -- 攻击间隔再缩短：每 15 tick 一轮 2 发，每 45 tick 一轮 3 发
    if trial.ticks % 15 == 0 then
        local n = (trial.ticks % 45 == 0) and 3 or 2
        for k = 1, n do
            local r = math.random()
            local ty, dmg
            if r < 0.55 then ty, dmg = 275, 40
            elseif r < 0.85 then ty, dmg = 276, 50
            else ty, dmg = 277, 60 end
            local tx, tyy = player_center(player)
            local pvx, pvy = read_vec2("Terraria", "Player", "velocity", player)
            if pvx then tx, tyy = tx + pvx * 10, tyy + pvy * 10 end
            local dx, dy = tx - ox, tyy - oy
            local d = math.sqrt(dx * dx + dy * dy)
            if d < 1 then d = 1 end
            spawn_proj(ty, ox - 8, oy - 8, dx / d * 12, dy / d * 12,
                dmg, 3, 255, 0, 0, 0, 1)
        end
    end

    if trial.ticks >= trial.duration then
        trial_end(true, player)
    end
end

-- ============================================================
-- 世纪之花二阶段：15 秒闪烁无敌 + 种子雨（范围 = 迷雾半径的一半）
-- ============================================================
local PHASE = { who = nil, active = false, ticks = 0, done = false, lock_x = nil, lock_y = nil, spin_bullets = nil }

local function find_plantera()
    local ok, arr = pcall(q.get_field_value, "Terraria", "Main", "npc", nil, "object")
    if not ok or not arr then return nil end
    local okn, n = pcall(P.array_length, arr)
    if not okn or type(n) ~= "number" then return nil end
    for i = 0, n - 1 do
        local okp, npc = pcall(P.array_at, arr, i)
        if okp and npc and fval(f_npc_active, npc, "bool") == true then
            if fval(f_npc_type, npc, "int32") == PLANTERA then
                local life = fval(f_npc_life, npc, "int32") or 0
                if life > 0 then return npc, life end
            end
        end
    end
    return nil
end

local function plantera_phase_tick(player)
    local npc, life = find_plantera()
    if not npc then
        PHASE.active = false
        PHASE.who = nil
        PHASE.done = false
        -- 清理残留的子弹
        if PHASE.spin_bullets then
            for _, b in ipairs(PHASE.spin_bullets) do
                local p = projectile_at(b.idx)
                if p then kill_proj(p) end
            end
            PHASE.spin_bullets = nil
        end
        return
    end
    local who = fval(f_npc_who, npc, "int32") or -1
    if PHASE.who ~= who then
        PHASE.who = who
        PHASE.active = false
        PHASE.done = false
        PHASE.ticks = 0
        PHASE.spin_bullets = nil
    end
    local maxLife = fval(f_npc_lifeMax, npc, "int32") or 30000
    
    if not PHASE.done and life <= maxLife * 0.5 then
        PHASE.done = true
        PHASE.active = true
        PHASE.ticks = 0
        PHASE.spin_bullets = nil
        -- 记录 NPC 位置（定身用）
        local px, py = read_vec2("Terraria", "NPC", "position", npc)
        PHASE.lock_x = px
        PHASE.lock_y = py
        -- 记录玩家位置（毒种阵的圆心，原地不跟随）
        local pcx, pcy = player_center(player)
        PHASE.p_center_x = pcx
        PHASE.p_center_y = pcy
        notify("世纪之花受到重创，进入 3 秒锁血硬直！")
    end
    if not PHASE.active then return end

    PHASE.ticks = PHASE.ticks + 1
    local jf = is_jungle(player) and (2 / 3) or 1

    -- ====== 前 3 秒（180 帧）强制锁血定身 + 原地旋转毒种阵 ======
    if PHASE.ticks <= 180 then
        -- 1. 世纪之花定身
        pcall(q.vec.set, "Terraria", "NPC", "velocity", npc, 0, 0)
        if PHASE.lock_x and PHASE.lock_y then
            pcall(q.vec.set, "Terraria", "NPC", "position", npc, PHASE.lock_x, PHASE.lock_y)
        end
        -- 锁血
        if f_npc_dont then pcall(P.set_field_value, f_npc_dont, npc, false, "bool") end
        if f_npc_alpha then pcall(P.set_field_value, f_npc_alpha, npc, 0, "int32") end
        pcall(P.set_field_value, f_npc_life, npc, math.floor(maxLife * 0.5), "int32")

        -- 2. 毒种阵逻辑
        if not PHASE.p_center_x then PHASE.p_center_x, PHASE.p_center_y = player_center(player) end
        local cx, cy = PHASE.p_center_x, PHASE.p_center_y
        local radius =65    -- 结界半径

        -- 【新增】出圈扣血机制
        local pcx, pcy = player_center(player)
        if pcx and cx then
            local dx = pcx - cx
            local dy = pcy - cy
            local dist = math.sqrt(dx * dx + dy * dy)
            -- 如果玩家跑到了圈外
            if dist > radius then
                -- 每 10 tick (约 0.16 秒) 扣一次血，防止一帧扣死
                if PHASE.ticks % 10 == 0 then
                    local p_life = fget("Terraria", "Player", "statLife", player, "int32")
                    local max_p_life = fget("Terraria", "Player", "statLifeMax2", player, "int32") or 100
                    if p_life and p_life > 1 then
                        local dmg = math.max(10, math.floor(max_p_life * 0.05)) -- 每次扣除 5% 最大生命
                        pcall(P.set_field_value, "Terraria", "Player", "statLife", player, math.max(0, p_life - dmg), "int32")
                    end
                end
            end
        end

        if not PHASE.spin_bullets then
            PHASE.spin_bullets = {}
            local count = 16      -- 一圈 16 颗
            local success = false
            for i = 1, count do
                local ang = (i - 1) * (math.pi * 2 / count)
                local bx = cx + math.cos(ang) * radius - 8
                local by = cy + math.sin(ang) * radius - 8
                local idx = spawn_proj(276, bx, by, 0, 0, 50, 3, 255, 0, 0, 0, 1)
                if idx >= 0 then
                    table.insert(PHASE.spin_bullets, { idx = idx, base_ang = ang })
                    success = true
                end
            end
            if not success then
                PHASE.spin_bullets = nil -- 如果生成失败，下一帧重试
            end
        end

        -- 每帧更新位置，围绕记录的原地坐标旋转
        if PHASE.spin_bullets then
            local rot_speed = 0.05 -- 旋转速度
            for _, b in ipairs(PHASE.spin_bullets) do
                local p = projectile_at(b.idx)
                if p and fval(f_pj_active, p, "bool") == true then
                    local cur_ang = b.base_ang + PHASE.ticks * rot_speed
                    local bx = cx + math.cos(cur_ang) * radius - 8
                    local by = cy + math.sin(cur_ang) * radius - 8
                    write_vec2("Terraria", "Projectile", "position", p, bx, by)
                    write_vec2("Terraria", "Projectile", "velocity", p, 0, 0)
                    write("Terraria", "Projectile", "timeLeft", p, 60, "int32")
                    -- 强制无碰撞，防止它们因为贴着方块而瞬间消失
                    pcall(q.set_field_value, "Terraria", "Projectile", "tileCollide", p, false, "bool")
                end
            end
        end

        return 
    end

    -- ====== 3 秒硬直结束（181帧），子弹向四周炸开！ ======
    if PHASE.ticks == 181 and PHASE.spin_bullets then
        local blast_speed = 14 -- 炸开的飞行速度
        for _, b in ipairs(PHASE.spin_bullets) do
            local p = projectile_at(b.idx)
            if p then
                local px, py = proj_center(p)
                if px then
                    local dx, dy = px - PHASE.p_center_x, py - PHASE.p_center_y
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d < 1 then d = 1 end
                    write_vec2("Terraria", "Projectile", "velocity", p, (dx/d) * blast_speed, (dy/d) * blast_speed)
                    write("Terraria", "Projectile", "timeLeft", p, 300, "int32") -- 给 5 秒的飞行时间
                end
            end
        end
        PHASE.spin_bullets = nil -- 清空记录，让引擎接管它们
    end

    -- ====== 3 秒后，正式开始 15 秒无敌闪烁 + 种子雨 ======
    local invuln_ticks = PHASE.ticks - 180
    if invuln_ticks == 1 then
        local secs = math.floor(900 * jf / 60)
        if is_jungle(player) then
            notify(string.format("二阶段（丛林：数值×2/3）：%d 秒闪烁无敌 + 种子雨", secs))
        else
            notify(string.format("二阶段：%d 秒闪烁无敌 + 种子雨", secs))
        end
    end

    if f_npc_dont then
        pcall(P.set_field_value, f_npc_dont, npc, true, "bool")
    end
    if f_npc_alpha then
        local a = (invuln_ticks % 10 < 5) and 0 or 170
        pcall(P.set_field_value, f_npc_alpha, npc, a, "int32")
    end

    -- 种子雨
    local rain_interval = math.max(4, math.floor(8 / jf))
    if invuln_ticks % rain_interval == 0 and player then
        local cx, cy = player_center(player)
        if cx then
            local rain_n = math.max(1, math.floor(2 * jf + 0.5))
            for k = 1, rain_n do
                local a = math.random() * math.pi * 2
                local r = math.sqrt(math.random()) * 1792
                local sx = cx + math.cos(a) * r
                local sy = cy - 700 - math.random() * 200
                local ty, dmg
                if math.random() < 0.7 then ty, dmg = 275, 40 else ty, dmg = 276, 50 end
                dmg = math.max(1, math.floor(dmg * jf))
                if is_underworld(player) then dmg = dmg * 2 end
                spawn_proj(ty, sx, sy, (math.random() - 0.5) * 2, 9 + math.random() * 4,
                    dmg, 3, 255, 0, 0, 0, 1)
            end
        end
    end

    if invuln_ticks >= math.floor(900 * jf) then
        PHASE.active = false
        if f_npc_dont then pcall(P.set_field_value, f_npc_dont, npc, false, "bool") end
        if f_npc_alpha then pcall(P.set_field_value, f_npc_alpha, npc, 0, "int32") end
        notify("世纪之花恢复可被攻击")
    end
end

local function start_trial(player)
    if trial_running() then return false, "试炼已经在进行" end
    local alive = plantera_alive()
    if alive then return false, "场上已有活着的世纪之花" end
    trial.orb_id = q.projectile_id("PlanteraTrialOrb") or -1
    trial.core_id = q.projectile_id("PlanteraTrialCore") or -1
    if trial.core_id < 0 then return false, "试炼核心未注册" end
    local cx, cy = player_center(player)
    if not cx then return false, "取不到玩家坐标" end
    local idx = fget("Terraria", "Player", "whoAmI", player, "int32") or 0
    trial.active = true
    trial.ticks = 0
    trial.last_spawn = 0
    trial.jungle = is_jungle(player)
    trial.core_idx = spawn_proj(trial.core_id, cx - 24, cy - 110, 0, 0, 0, 0, idx, 0, 0, 0, 1)
    if not trial.core_idx or trial.core_idx < 0 then
        trial.active = false
        return false, "试炼核心生成失败"
    end
    MIST.saw = false
    local mist_id = q.projectile_id("PlanteraMist") or -1
    if mist_id >= 0 then
        MIST.idx = spawn_proj(mist_id, cx - 512, cy - 512, 0, 0, 0, 0, idx, 0, 0, 0, 7)
    end
    local dur = math.floor(1200 * (trial.jungle and (2 / 3) or 1) / 60)
    local extra = ""
    if is_underworld(player) then extra = "，地狱：伤害×2、攻击附带诅咒之火" end
    if trial.jungle then
        notify(string.format("试炼开始（丛林：数值×2/3）：存活 %d 秒，弹幕减量减伤%s", dur, extra))
    else
        notify(string.format("试炼开始：存活 %d 秒，才能唤醒世纪之花%s", dur, extra))
    end
    return true
end


-- ---------------- 物品 ----------------
local function ensure_item_id()
    if item_id > 0 then return item_id end
    local ok, v = pcall(q.item_id, ITEM_NAME)
    if ok and type(v) == "number" and v > 0 then item_id = v end
    return item_id
end

local function register()
    if registered then return end
    registered = true
    if not (q and q.register_item) then return end

    pcall(q.register_projectile, {
        name = "PlanteraMist",
        texture = "Mist.png",
        defaults = {
            width = 1024, height = 1024, scale = 7.0,
            aiStyle = -1, friendly = false, hostile = false,
            damage = 0, penetrate = -1, tileCollide = false,
            ignoreWater = true, timeLeft = 60, alpha = 0, drawLayer = 4,
        },
        ai = mist_ai,
    })
    pcall(q.register_projectile, {
        name = "PlanteraTrialCore",
        texture = "TrialCore.png",
        defaults = {
            width = 48, height = 48, scale = 1.0,
            aiStyle = -1, friendly = false, hostile = false,
            damage = 0, penetrate = -1, tileCollide = false,
            ignoreWater = true, timeLeft = 60, alpha = 0, drawLayer = 4,
        },
        ai = trial_core_ai,
    })
    pcall(q.register_projectile, {
        name = "PlanteraTrialOrb",
        texture = "TrialOrb.png",
        defaults = {
            width = 20, height = 20, scale = 1.0,
            aiStyle = -1, friendly = false, hostile = false,
            damage = 0, penetrate = -1, tileCollide = false,
            ignoreWater = true, timeLeft = 600, alpha = 0, drawLayer = 4,
        },
        ai = trial_orb_ai,
    })

    pcall(q.register_item, {
        name = ITEM_NAME,
        texture = "PlanteraSummon.png",
        tooltip = true,
        animation = { ticks = 3, frames = 16 },
        defaults = {
            width = 32, height = 32,
            useStyle = 4, useTime = 45, useAnimation = 45,
            maxStack = 20, rare = 8, value = 100000,
            noMelee = true, autoReuse = false, consumable = false,
            damage = 0, knockBack = 0, melee = false,
        },
        can_use = function(player, item, ignore)
            if not player then return false end
            if trial.active then return false end
            return not plantera_alive()
        end,
        use = function(player, item)
            local ok, why = start_trial(player)
            if not ok then notify("无法开始试炼：" .. tostring(why)) end
        end,
        language = {
            zh = {
                name = "世纪之花之种",
                tooltip = "使用后进入试炼：躲开世界之花的种子/毒种/荆棘球\n通过后才会唤醒世纪之花（物品不消耗）\n丛林内：试炼/二阶段所有数值 ×2/3，迷雾不变",
            },
            en = {
                name = "Plantera Seed",
                tooltip = "Summons Plantera\nWorks like the vanilla boss awakening",
            },
        },
        recipe = {
            result = 1,
            materials = {
                { id = 1006, count = 10 },  -- 叶绿锭
                { id = 331,  count = 15 },  -- 丛林孢子
            },
            station = 134,                  -- 秘银砧 / 山铜砧
        },
    })
end

-- 兜底：UseItem 回调没被派发时，手持并按住使用也会触发
local hook_tick = 0
local function install_tick()
    pcall(q.install_hook_postfix, "Terraria", "Player", "ItemCheck", function(player)
        hook_tick = hook_tick + 1
        pcall(function()
            if not player then return end
            pcall(underworld_tick, player)
            if trial.active then
                if player_dead(player) then
                    trial_end(false, player)
                end
                return
            end
            pcall(plantera_phase_tick, player)
            local id = ensure_item_id()
            if id <= 0 then return end
            local it = held_item(player)
            if not it then return end
            if fget("Terraria", "Item", "type", it, "int32") ~= id then return end
            if fval(f_pl_use, player, "bool") ~= true then return end
            if hook_tick - last_try < 30 then return end
            last_try = hook_tick
            if trial_running() then return end
            if plantera_alive() then
                notify("场上已有活着的世纪之花")
                return
            end
            local ok, why = start_trial(player)
            if not ok then notify("无法开始试炼：" .. tostring(why)) end
        end)
    end)
end

local function install_strike_guard()
    pcall(q.install_hook_prefix, "Terraria", "NPC", "StrikeNPC", function(npc, ...)
        if fval(f_npc_type, npc, "int32") ~= PLANTERA then return false end
        
        local life = fval(f_npc_life, npc, "int32") or 0
        local maxLife = fval(f_npc_lifeMax, npc, "int32") or 30000
        
        -- 1. 一阶段（还没进二阶段）
        if not PHASE.done then
            -- 每次攻击固定扣除 10% 的血量（砍 5 刀必定进二阶段）
            local new_life = life - math.floor(maxLife * 0.1)
            
            if new_life <= maxLife * 0.5 then
                -- 触发二阶段：强行锁在 50%
                pcall(P.set_field_value, f_npc_life, npc, math.floor(maxLife * 0.5), "int32")
                PHASE.who = fval(f_npc_who, npc, "int32") or -1
                PHASE.done = true
                PHASE.active = true
                PHASE.ticks = 0
                notify("世纪之花受到重创，进入锁血硬直！")
            else
                -- 正常扣除这 10% 的血
                pcall(P.set_field_value, f_npc_life, npc, new_life, "int32")
            end
            -- 拦截那 5500万的真实伤害，防止秒杀
            return true 
        end
        
        -- 2. 二阶段硬直和无敌期间（绝对免伤）
        if PHASE.active then
            return true
        end
        
        -- 3. 二阶段无敌结束，原版伤害放行（这时候你可以一刀 5500 万秒了它）
        return false
    end)
end

function mod.init()
    local ok, err = pcall(register)
    if not ok then log("init: " .. tostring(err)) end
    pcall(install_tick)
    pcall(install_strike_guard)
end



return M
