-- 通用工具：读配置、取坐标、找玩家、生成弹幕、查 NPC。
local q = mod.quickapi
local M = {}

local config_cache

function M.config()
    if config_cache then return config_cache end
    local values = {}
    local text = mod.read_file("config.json")
    if type(text) == "string" then
        for key, raw in text:gmatch('"([%w_]+)"%s*:%s*([%w_%.%-]+)') do
            if raw == "true" then
                values[key] = true
            elseif raw == "false" then
                values[key] = false
            else
                values[key] = tonumber(raw) or raw
            end
        end
    end
    config_cache = values
    return values
end

function M.config_number(key, default)
    local value = M.config()[key]
    if type(value) == "number" then return value end
    return default
end

function M.position(class, instance)
    return q.vec.get("Terraria", class, "position", instance)
end

function M.move(class, instance, vx, vy)
    local x, y = M.position(class, instance)
    q.vec.set("Terraria", class, "velocity", instance, vx, vy)
    q.vec.set("Terraria", class, "position", instance, x + vx, y + vy)
    return x + vx, y + vy
end

-- 实体中心点：接触伤害与掉落都按贴图中心算，避免半格偏移。
function M.center(class, instance)
    local x, y = M.position(class, instance)
    local w = q.get_field_value("Terraria", class, "width", instance, "int32") or 0
    local h = q.get_field_value("Terraria", class, "height", instance, "int32") or 0
    return x + w / 2, y + h / 2
end

-- 鼠标在世界里的位置（Main.MouseWorld 是个 Vector2 属性，得按结构体返回读）
local mouse_getter, mouse_resolved

function M.mouse_world()
    if not mouse_resolved then
        mouse_resolved = true
        local prop = q.property("Terraria", "Main", "MouseWorld")
        if prop then
            local ok, m = pcall(mod.patch.property_get_method, prop)
            if ok and m then mouse_getter = m end
        end
    end
    if not mouse_getter or not mod.patch.invoke_value_args then return nil end
    local ok, raw = pcall(mod.patch.invoke_value_args, mouse_getter, {})
    if not ok or type(raw) ~= "string" then return nil end
    local okk, x, y = pcall(string.unpack, "<ff", raw)
    if okk and type(x) == "number" then return x, y end
    return nil
end

-- 找离 (x, y) 最近的活着的玩家。返回的 handle 只在当前帧有效。
function M.nearest_player(x, y, radius)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local players = q.get_object("Terraria", "Main", "player")
    if not players then return nil end
    local limit = radius and radius * radius
    local best, best_d2
    for i = 0, mod.patch.array_length(players) - 1 do
        local player = mod.patch.array_at(players, i)
        if player then
            local active = q.get_field_value("Terraria", "Player", "active", player, "bool")
            local dead = q.get_field_value("Terraria", "Player", "dead", player, "bool")
            if active and not dead then
                local px, py = M.position("Player", player)
                if px then
                    local d2 = (px - x) ^ 2 + (py - y) ^ 2
                    if (not limit or d2 <= limit) and (not best_d2 or d2 < best_d2) then
                        best_d2 = d2
                        best = { handle = player, index = i, x = px, y = py }
                    end
                end
            end
        end
    end
    if best then best.dist = math.sqrt(best_d2) end
    return best
end

-- 统计某类型 NPC 的存活数量（用于「Boss 已存在就不让再召唤」）
function M.count_npc(type_id)
    if not type_id or type_id < 0 then return 0 end
    local npcs = q.get_object("Terraria", "Main", "npc")
    if not npcs then return 0 end
    local count = 0
    for i = 0, mod.patch.array_length(npcs) - 1 do
        local npc = mod.patch.array_at(npcs, i)
        if npc then
            local active = q.get_field_value("Terraria", "NPC", "active", npc, "bool")
            if active and q.get_field_value("Terraria", "NPC", "type", npc, "int32") == type_id then
                count = count + 1
            end
        end
    end
    return count
end


-- 统计某类弹幕的存在数量（随从去重用）
function M.count_projectile(type_id)
    if not type_id or type_id < 0 then return 0 end
    local projectiles = q.get_object("Terraria", "Main", "projectile")
    if not projectiles then return 0 end
    local count = 0
    for i = 0, mod.patch.array_length(projectiles) - 1 do
        local projectile = mod.patch.array_at(projectiles, i)
        if projectile then
            local active = q.get_field_value("Terraria", "Projectile", "active", projectile, "bool")
            if active and q.get_field_value("Terraria", "Projectile", "type", projectile, "int32") == type_id then
                count = count + 1
            end
        end
    end
    return count
end


local new_text_method, text_resolved

local function resolve_text()
    if text_resolved then return end
    text_resolved = true
    new_text_method = q.method("Terraria", "Main", "NewText", 5)
            or q.method("Terraria", "Main", "NewText", 4)
            or q.method("Terraria", "Main", "NewText")
end

-- 游戏内聊天框提示（mod.info 只进内核日志，玩家看不到）

-- 找离 (x, y) 最近的敌对 NPC。返回的对象句柄只在当前帧有效。
function M.nearest_npc(x, y, radius)
    local list = q.get_object("Terraria", "Main", "npc")
    if not list then return nil end
    local limit = (radius or 600) ^ 2
    local best, best_d2
    for i = 0, mod.patch.array_length(list) - 1 do
        local npc = mod.patch.array_at(list, i)
        if npc then
            local active = q.get_field_value("Terraria", "NPC", "active", npc, "bool")
            local friendly = q.get_field_value("Terraria", "NPC", "friendly", npc, "bool")
            local life = q.get_field_value("Terraria", "NPC", "life", npc, "int32")
            if active and not friendly and life and life > 0 then
                local nx, ny = M.position("NPC", npc)
                if nx then
                    local d2 = (nx - x) ^ 2 + (ny - y) ^ 2
                    if d2 <= limit and (not best_d2 or d2 < best_d2) then
                        best, best_d2 = npc, d2
                    end
                end
            end
        end
    end
    return best
end

-- 带颜色的聊天提示：默认是碎晶蓝，危险/警告用红色
function M.notify_color(text, r, g, b)
    resolve_text()
    if not new_text_method then return end
    local message = mod.patch.string_create(text)
    if not message then return end
    r, g, b = r or 150, g or 226, b or 255
    -- 按方法真实参数个数传参：多传一个会越界写入（内核按 param_count 分配槽位）
    local ok, count = pcall(mod.patch.method_param_count, new_text_method)
    count = (ok and type(count) == "number") and count or nil
    if count == 5 then
        pcall(q.call, new_text_method, message, r, g, b, false)
    elseif count == 4 then
        pcall(q.call, new_text_method, message, r, g, b)
    elseif count == 2 then
        pcall(q.call, new_text_method, message, false)
    else
        pcall(q.call, new_text_method, message)
    end
end

function M.notify(text)
    M.notify_color(text, 150, 226, 255)
end

local new_projectile_13, new_projectile_11, none_source, spawner_ready
local spawn_info = { has_method = false, has_source = false, mode = "none" }

-- 弹幕生成状态
function M.spawn_info()
    return spawn_info
end


-- 统一取 EntitySource：优先自己走托管构造（new_instance 会调 ctor），
-- 失败再退回 Projectile.GetNoneSource（某些版本上它返回 false/异常）
local resolve_spawner
local source_class, source_class_resolved

function M.get_source()
    if not source_class_resolved then
        source_class_resolved = true
        source_class = q.type("Terraria.DataStructures", "EntitySource_SpawnNPC")
    end
    if source_class and mod.patch.new_instance then
        local ok, instance = pcall(mod.patch.new_instance, source_class)
        if ok and instance then
            spawn_info.source_mode = "new_instance"
            return instance
        end
    end

    resolve_spawner()
    if none_source then
        local ok2, src = pcall(q.call, none_source)
        if ok2 and src and src ~= false then
            spawn_info.source_mode = "GetNoneSource"
            return src
        end
        spawn_info.source_error = tostring(src)
    end
    return nil
end

-- NewProjectile 有两个重载：13 参（float X/Y/SpeedX/SpeedY）与 11 参（Vector2）。
-- Android 上把一堆 float/int 混着走 libffi 容易错位，优先用 Vector2 版 + 结构体参数。
resolve_spawner = function()
    if spawner_ready then return end
    spawner_ready = true

    new_projectile_11 = q.method("Terraria", "Projectile", "NewProjectile",
            { params = { "spawnSource", "position", "velocity", "Type", "Damage",
                         "KnockBack", "Owner", "ai0", "ai1", "ai2", "modifer" } })
            or q.method("Terraria", "Projectile", "NewProjectile", 11)

    new_projectile_13 = q.method("Terraria", "Projectile", "NewProjectile",
            { params = { "spawnSource", "X", "Y", "SpeedX", "SpeedY", "Type", "Damage",
                         "KnockBack", "Owner", "ai0", "ai1", "ai2", "modifer" } })
            or q.method("Terraria", "Projectile", "NewProjectile", 13)

    none_source = q.method("Terraria", "Projectile", "GetNoneSource", 0)

    spawn_info.has_method = (new_projectile_11 or new_projectile_13) ~= nil
    spawn_info.has_source = none_source ~= nil
    spawn_info.has_v2 = new_projectile_11 ~= nil
    spawn_info.has_struct = (mod.patch.invoke_value_args ~= nil and mod.patch.struct_arg ~= nil)

    if not spawn_info.has_method or not none_source then
        mod.warn("碎晶之链：找不到 Projectile.NewProjectile / GetNoneSource")
    end
end

-- 只解析接口、不生成（诊断用，安全）
function M.prepare_spawner()
    resolve_spawner()
end

-- 生成一枚弹幕，返回 Main.projectile 下标；失败返回 nil（原因记在 spawn_info 里）
function M.spawn_projectile(name, x, y, vx, vy, damage, owner)
    resolve_spawner()
    if not (spawn_info.has_method and none_source) then
        spawn_info.fail = "缺少 NewProjectile / GetNoneSource"
        return nil
    end

    local id = q.projectile_id(name)
    if not id or id < 0 then
        spawn_info.fail = "弹幕 ID 无效：" .. tostring(id)
        return nil
    end

    local src = M.get_source()
    if not src then
        spawn_info.fail = "拿不到 EntitySource"
        return nil
    end

    local ok, index

    if new_projectile_11 and spawn_info.has_struct then
        spawn_info.mode = "vector2"
        ok, index = pcall(mod.patch.invoke_value_args, new_projectile_11, {
            src,
            mod.patch.struct_arg({ "float", "float" }, { x, y }),
            mod.patch.struct_arg({ "float", "float" }, { vx, vy }),
            id, damage, 2.0, owner or 255, 0.0, 0.0, 0.0, nil,
        })
    elseif new_projectile_13 then
        spawn_info.mode = "float13"
        ok, index = pcall(q.call, new_projectile_13, src, x, y, vx, vy, id,
                damage, 2.0, owner or 255, 0, 0, 0, nil)
    else
        spawn_info.fail = "没有可用的 NewProjectile 重载"
        return nil
    end

    if not ok then
        spawn_info.fail = "NewProjectile 调用失败：" .. tostring(index)
        return nil
    end
    if type(index) ~= "number" then
        spawn_info.fail = "返回下标无效：" .. tostring(index)
        return nil
    end

    spawn_info.fail = nil
    spawn_info.last_ok = index
    return index
end



-- 用原版弹幕 ID 生成一枚弹幕（诊断用，绕开自定义弹幕名）
function M.spawn_vanilla_projectile(type_id, x, y, vx, vy, damage, owner)
    resolve_spawner()
    if not (spawn_info.has_method and none_source) then
        spawn_info.fail = "缺少 NewProjectile / GetNoneSource"
        return nil
    end
    local src = M.get_source()
    if not src then
        spawn_info.fail = "拿不到 EntitySource"
        return nil
    end
    local ok, index
    if new_projectile_11 and spawn_info.has_struct then
        spawn_info.mode = "vector2"
        ok, index = pcall(mod.patch.invoke_value_args, new_projectile_11, {
            src,
            mod.patch.struct_arg({ "float", "float" }, { x, y }),
            mod.patch.struct_arg({ "float", "float" }, { vx, vy }),
            type_id, damage, 2.0, owner or 255, 0.0, 0.0, 0.0, nil,
        })
    elseif new_projectile_13 then
        spawn_info.mode = "float13"
        ok, index = pcall(q.call, new_projectile_13, src, x, y, vx, vy, type_id,
                damage, 2.0, owner or 255, 0, 0, 0, nil)
    end
    if not ok then
        spawn_info.fail = "NewProjectile 调用失败：" .. tostring(index)
        return nil
    end
    return type(index) == "number" and index or nil
end


-- 把一枚弹幕改成敌弹（原版弹药类弹幕默认 friendly，会打 NPC）
-- timeLeft 一起调大，否则原版弹药类的存活时间太短，射程只有十几格
function M.make_hostile(index, time_left)
    if type(index) ~= "number" or index < 0 then return false end
    local list = q.get_object("Terraria", "Main", "projectile")
    local proj = list and mod.patch.array_at(list, index)
    if not proj then return false end
    pcall(q.set_field_value, "Terraria", "Projectile", "friendly", proj, false, "bool")
    pcall(q.set_field_value, "Terraria", "Projectile", "hostile", proj, true, "bool")
    pcall(q.set_field_value, "Terraria", "Projectile", "owner", proj, 255, "int32")
    if time_left then
        pcall(q.set_field_value, "Terraria", "Projectile", "timeLeft", proj, time_left, "int32")
    end
    return true
end


-- 自己生成的自定义弹幕登记表：index -> spec。
-- 内核每帧会把这些弹幕重置成 active=false / timeLeft=0（实测），
-- 所以每帧开头把它们补回来；track 表只在 Main.Update 前缀里遍历这几项，不扫全表。
local tracked = {}
local keepalive_installed = false
local tick = 0            -- 保活计时（每次钩子回调 +1，每帧两次）

-- life 是我们自己记的寿命（帧）；不传就用 spec.timeLeft
function M.track_custom_projectile(index, spec, life)
    if type(index) ~= "number" or index < 0 or not spec then return end
    tracked[index] = {
        spec = spec,
        born = tick,
        life = life or spec.timeLeft or 300,
    }
    M.install_keepalive()
end

-- 自动登记：弹幕生成时（Projectile.SetDefaults）按 type 认出是自己的，收进保活表
-- 自动登记：SetDefaults 触发时 whoAmI 还是「上一个占用者」的值（实测 2 而真实槽位是 1），
-- 所以这里只记下「这一帧有新弹幕生成」，下一帧按 type 扫一遍数组补登记。
local pending = {}

function M.autotrack(proj, type_id, spec)
    if type(type_id) ~= "number" or not spec then return end
    pending[type_id] = spec
    M.install_keepalive()
end

local function resolve_pending()
    if next(pending) == nil then return end
    local list = q.get_object("Terraria", "Main", "projectile")
    if not list then return end
    local n = mod.patch.array_length(list)
    for i = 0, n - 1 do
        if not tracked[i] then
            local proj = mod.patch.array_at(list, i)
            if proj then
                local type_id = q.get_field_value("Terraria", "Projectile", "type", proj, "int32")
                local spec = type_id and pending[type_id]
                if spec then
                    -- 不要求 active：内核生成后立刻把 active 清成 false，等下一帧扫的时候
                    -- 它已经是「死的」了。用 whoAmI == 下标 自校验，避免收到别的槽位的残留。
                    local who = q.get_field_value("Terraria", "Projectile", "whoAmI", proj, "int32")
                    if who == i then
                        tracked[i] = {
                            spec = spec,
                            born = tick,
                            life = spec.timeLeft or 300,
                            keep_damage = true,
                        }
                    end
                end
            end
        end
    end
    pending = {}
end

-- 命中 / 被销毁时取消保活：内核每帧会把 active 清成 false，
-- 我们又在补活，不打这个标记的话「打中玩家也不消失」。
function M.untrack_projectile_handle(proj)
    if not proj then return end
    M.stats.untracked = M.stats.untracked + 1
    local index = q.get_field_value("Terraria", "Projectile", "whoAmI", proj, "int32")
    if type(index) == "number" and index >= 0 then
        tracked[index] = nil
    end
end

M.stats = { tracked = 0, untracked = 0 }

-- 清掉某一类弹幕的全部保活（召唤物解散时用）。
-- 不依赖 whoAmI 对得上：直接按 spec 引用比对，保证一个不漏。
function M.untrack_spec(spec)
    if not spec then return 0 end
    local n = 0
    for index, entry in pairs(tracked) do
        if entry.spec == spec then
            tracked[index] = nil
            n = n + 1
        end
    end
    return n
end

function M.tracked_first_index()
    for index in pairs(tracked) do return index end
    return nil
end


function M.untrack_custom_projectile(index)
    tracked[index] = nil
end

local keepalive_errors = 0
local keepalive_last_err = nil

local function keepalive_tick()
    tick = tick + 1
    if next(pending) ~= nil then
        local okp, errp = pcall(resolve_pending)
        if not okp then
            mod.warn("碎晶之链：弹幕登记扫描出错 " .. tostring(errp))
        end
    end
    if next(tracked) == nil then return end
    local list = q.get_object("Terraria", "Main", "projectile")
    if not list then return end
    local ok, err = pcall(function()
    for index, entry in pairs(tracked) do
        local proj = mod.patch.array_at(list, index)
        if proj then
            local type_id = q.get_field_value("Terraria", "Projectile", "type", proj, "int32")
            if type_id and type_id > 1000 then
                -- 寿命自己管：timeLeft 每帧被重置，靠它永远不会过期
                local age = math.floor((tick - (entry.born or tick)) / 2)
                if age > entry.life then
                    pcall(q.set_field_value, "Terraria", "Projectile", "active", proj, false, "bool")
                    tracked[index] = nil
                elseif not q.get_field_value("Terraria", "Projectile", "active", proj, "bool") then
                    if entry.primed then
                        M.revive_quick(proj, entry.spec, entry)
                    else
                        M.revive_handle(proj, entry.spec)
                        entry.primed = true
                        entry.damage = entry.spec.damage
                    end
                end
            else
                tracked[index] = nil     -- 槽位被别的弹幕占了，取消跟踪
            end
        else
            tracked[index] = nil
        end
    end
    end)
    if not ok then
        keepalive_errors = keepalive_errors + 1
        keepalive_last_err = tostring(err)
        if keepalive_errors == 1 then
            mod.warn("碎晶之链：弹幕保活出错 " .. tostring(err))
        end
    end
end

function M.keepalive_stats()
    return keepalive_errors, keepalive_last_err
end

-- 每帧补两次：
--   prefix ：让这次更新读到的弹幕是活的 → 位移、命中、伤害都正常（实测能打到玩家）
--   postfix：内核在更新阶段把它重置成 active=false，而绘制发生在更新之后 →
--            不补的话屏幕上什么都看不到（1.2.36 实测「没贴图」就是这个）
function M.install_keepalive()
    if keepalive_installed then return end
    keepalive_installed = true
    local ok, err = pcall(q.install_hook_prefix, "Terraria", "Main", "Update",
            keepalive_tick, { argc = 1 })
    if not ok then
        keepalive_installed = false
        mod.warn("碎晶之链：弹幕保活钩子（prefix）安装失败 " .. tostring(err))
        return
    end
    local ok2, err2 = pcall(q.install_hook_postfix, "Terraria", "Main", "Update",
            keepalive_tick, { argc = 1 })
    if not ok2 then
        mod.warn("碎晶之链：弹幕保活钩子（postfix）安装失败 " .. tostring(err2))
    end
end

-- 把一枚弹幕的「默认值」整份补上：内核给自定义 type 生成时没跑 Projectile.SetDefaults，
-- active / timeLeft / 尺寸 / 伤害全是 0。这里按注册时写的那套字段手工补一遍。
function M.revive_full(index, spec)
    if type(index) ~= "number" or index < 0 then return false end
    local list = q.get_object("Terraria", "Main", "projectile")
    local proj = list and mod.patch.array_at(list, index)
    if not proj then return false end
    return M.revive_handle(proj, spec)
end

-- 精简版补活：只写「每帧会被内核清掉、且不写就出问题」的几个字段。
-- 全量补活要写 12 个字段，同屏几十发弹幕时是主要开销，这里压到 5 个。
function M.revive_quick(proj, spec, entry)
    if not proj or not spec then return false end
    pcall(q.set_field_value, "Terraria", "Projectile", "active", proj, true, "bool")
    pcall(q.set_field_value, "Terraria", "Projectile", "timeLeft", proj,
            (entry and entry.life) or spec.timeLeft or 300, "int32")
    local damage = (entry and entry.damage) or spec.damage
    if damage then
        pcall(q.set_field_value, "Terraria", "Projectile", "damage", proj, damage, "int32")
    end
    if spec.width then
        pcall(q.set_field_value, "Terraria", "Projectile", "width", proj, spec.width, "int32")
    end
    if spec.height then
        pcall(q.set_field_value, "Terraria", "Projectile", "height", proj, spec.height, "int32")
    end
    if spec.scale then
        pcall(q.set_field_value, "Terraria", "Projectile", "scale", proj, spec.scale, "float")
    end
    return true
end

-- 同上，但直接吃一个弹幕 handle（钩子里拿到的就是 handle）
function M.revive_handle(proj, spec)
    if not proj then return false end
    spec = spec or {}

    local function seti(name, value)
        if value ~= nil then
            pcall(q.set_field_value, "Terraria", "Projectile", name, proj, value, "int32")
        end
    end
    local function setf(name, value)
        if value ~= nil then
            pcall(q.set_field_value, "Terraria", "Projectile", name, proj, value, "float")
        end
    end
    local function setb(name, value)
        if value ~= nil then
            pcall(q.set_field_value, "Terraria", "Projectile", name, proj, value, "bool")
        end
    end

    setb("active", true)
    seti("timeLeft", spec.timeLeft or 300)
    if spec.keep_damage then
        local live = q.get_field_value("Terraria", "Projectile", "damage", proj, "int32")
        if type(live) == "number" and live > 0 then
            spec.damage = live
        end
    end
    seti("damage", spec.damage)
    seti("width", spec.width)
    seti("height", spec.height)
    seti("penetrate", spec.penetrate or 0)
    seti("owner", spec.owner or 255)
    setf("knockBack", spec.knockBack)
    setb("friendly", spec.friendly or false)
    setb("hostile", spec.hostile or false)
    setb("tileCollide", spec.tileCollide or false)
    if spec.scale then
        pcall(q.set_field_value, "Terraria", "Projectile", "scale", proj, spec.scale, "float")
    end
    if spec.vx and spec.vy then
        pcall(q.vec.set, "Terraria", "Projectile", "velocity", proj, spec.vx, spec.vy)
    end
    -- ai0：给弹幕自己用的标记（比如 1 = 弱追踪），AI 回调里读它
    if spec.ai0 then
        local okai, arr = pcall(q.get_field_value, "Terraria", "Projectile", "ai", proj, "object")
        if okai and arr then
            pcall(mod.patch.array_set, arr, 0, spec.ai0, "float")
        end
    end
    return true
end

-- 自定义弹幕生成后 active 立刻失效（内核没跑完整初始化），这里手动补一遍关键字段
function M.revive_projectile(index, damage, hostile, time_left)
    if type(index) ~= "number" or index < 0 then return false end
    local list = q.get_object("Terraria", "Main", "projectile")
    local proj = list and mod.patch.array_at(list, index)
    if not proj then return false end
    pcall(q.set_field_value, "Terraria", "Projectile", "active", proj, true, "bool")
    pcall(q.set_field_value, "Terraria", "Projectile", "timeLeft", proj, time_left or 300, "int32")
    if damage then
        pcall(q.set_field_value, "Terraria", "Projectile", "damage", proj, damage, "int32")
    end
    if hostile then
        pcall(q.set_field_value, "Terraria", "Projectile", "friendly", proj, false, "bool")
        pcall(q.set_field_value, "Terraria", "Projectile", "hostile", proj, true, "bool")
        pcall(q.set_field_value, "Terraria", "Projectile", "owner", proj, 255, "int32")
    end
    return true
end

function M.drop_item(target, x, y, count)
    local id
    if type(target) == "number" then
        id = target
    else
        id = q.item_id(target)
    end
    if not id or id < 0 then return nil end
    local ok, index = pcall(mod.npc.drop_item, id, x, y, count)
    if not ok then
        mod.warn("碎晶之链：掉落失败 " .. tostring(index))
        return nil
    end
    return index
end


local my_player_getter, my_player_field, resolved_my_player

local function resolve_my_player()
    if resolved_my_player then return end
    resolved_my_player = true
    local prop = q.property("Terraria", "Main", "myPlayer")
    if prop then
        local ok, m = pcall(mod.patch.property_get_method, prop)
        if ok and m then my_player_getter = m end
    end
    if not my_player_getter then
        my_player_getter = q.method("Terraria", "Main", "get_myPlayer", 0)
    end
    my_player_field = q.field("Terraria", "Main", "myPlayer")
end

-- 本机玩家索引：属性 getter → get_ 方法 → 静态字段，逐级回退。
function M.my_player_index()
    resolve_my_player()
    if my_player_getter then
        local ok, v = pcall(q.call, my_player_getter)
        if ok and type(v) == "number" then return v end
    end
    if my_player_field then
        local ok, v = pcall(q.get_field_value, "Terraria", "Main", "myPlayer", nil, "int32")
        if ok and type(v) == "number" then return v end
    end
    return 0
end

function M.local_player()
    local players = q.get_object("Terraria", "Main", "player")
    if not players then return nil end
    local index = M.my_player_index()
    local player = mod.patch.array_at(players, math.floor(index))
    return player, index
end

-- 物品显示名：走 Lang.GetItemNameValue，查不到返回 nil（本模组的物品名由内核
-- 塞进语言表，可能取不到；调用方要准备好退回自己写的标签）。
local lang_name_method
local name_cache = {}

function M.item_name(type_id)
    if type(type_id) ~= "number" or type_id <= 0 then return nil end
    local cached = name_cache[type_id]
    if cached ~= nil then
        if cached == "" then return nil end
        return cached
    end

    if lang_name_method == nil then
        for _, name in ipairs({ "GetItemNameValue", "GetItemName" }) do
            local ok, method = pcall(q.method, "Terraria", "Lang", name, 1)
            if ok and method then
                lang_name_method = method
                break
            end
        end
        if lang_name_method == nil then lang_name_method = false end
    end

    local value = nil
    if lang_name_method then
        local ok, handle = pcall(q.call, lang_name_method, type_id)
        if ok and handle then
            local ok2, text = pcall(mod.patch.string_value, handle)
            if ok2 and type(text) == "string" and text ~= "" then value = text end
        end
    end
    name_cache[type_id] = value or ""
    return value
end

-- 玩家贴图中心（开火瞄准用；position 是左上角）
function M.player_center(player)
    if not player then return nil end
    local x, y = M.position("Player", player)
    if not x then return nil end
    local w = q.get_field_value("Terraria", "Player", "width", player, "int32") or 20
    local h = q.get_field_value("Terraria", "Player", "height", player, "int32") or 42
    return x + w / 2, y + h / 2
end

-- 玩家当前速度（算提前量）
function M.player_velocity(player)
    if not player then return 0, 0 end
    local ok, vx, vy = pcall(q.vec.get, "Terraria", "Player", "velocity", player)
    if ok then return vx or 0, vy or 0 end
    return 0, 0
end

-- 物品 runtime id：先问内核；问不到就把 Lang 里的名字建一张反查表再查。
-- 内核的 runtime_id 在"注册当场"可能还是 nil，但游戏里能查到；
-- 万一两边都查不到，反查表还能兜住（自定义物品名由内核写进语言表）。
local name_to_id

local function build_name_map()
    if name_to_id then return name_to_id end
    name_to_id = {}
    for id = 1, 6500 do
        local name = M.item_name(id)
        if name and name ~= "" and not name_to_id[name] then
            name_to_id[name] = id
        end
    end
    return name_to_id
end

local id_cache = {}

function M.item_id_of(reg_name, zh_label)
    local key = reg_name or zh_label
    if not key then return nil end
    local cached = id_cache[key]
    if cached then return cached end

    local id = q.item_id(reg_name)
    if type(id) == "number" and id > 0 then
        id_cache[key] = id
        return id
    end

    if zh_label then
        local map = build_name_map()
        local found = map[zh_label]
        if found then
            id_cache[key] = found
            return found
        end
    end
    return nil
end

return M
