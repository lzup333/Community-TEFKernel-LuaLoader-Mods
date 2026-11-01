-- LuaModQuickAPI / quickapi —— LuaLoader Mod 编写便捷层
-- Copyright (c) 2026 lzup333
--
-- MIT License
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--
-- 本文件是库本体：复制到你的 Mod 的 Resources/lib/quickapi.lua，入口脚本首行
-- require("quickapi")，之后即可使用 mod.quickapi.*。
-- 纯 Lua，无需修改 / 重新编译 LuaLoader，一份脚本全平台通用。

local mod_env = mod
if type(mod_env) ~= "table" then
    error("quickapi: 未找到全局 mod 表，请在 LuaLoader Mod 的入口脚本中使用")
end

local patch = mod_env.patch
if type(patch) ~= "table" then
    error("quickapi: mod.patch 不可用，当前 LuaLoader 版本过旧")
end

local q = {}
q.version = "1.3.6"

-- 句柄缓存：类型 / 字段 / 属性 / 方法。句柄在同一个 Lua 状态机内稳定，
-- /reload 会重建状态机，缓存随之一并重建，无需手动清理。
local type_cache = {}
local member_cache = {}
local method_cache = {}

local function key_of(...)
    return table.concat({...}, "\1")
end

local function is_handle(v)
    local t = type(v)
    return t == "userdata" or t == "lightuserdata"
end

local function fail(level, fmt, ...)
    error("quickapi: " .. string.format(fmt, ...), level)
end

-- 沿父类链查找成员：命中返回句柄，找不到返回 nil
local function walk_members(t, getter, name)
    local cur, guard = t, 0
    while cur and guard < 32 do
        local h = getter(cur, name)
        if h then return h end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

-- spec 为空 / 数字 / 含 params|types|argc 的表，对应 patch 的几种选重载方式
local function resolve_spec(t, name, spec)
    if spec == nil then
        return patch.get_method(t, name)
    end
    local st = type(spec)
    if st == "number" then
        return patch.get_method(t, name, spec)
    end
    if st == "table" then
        if spec.params then return patch.get_method_by_names(t, name, spec.params) end
        if spec.types then return patch.get_method_by_param_types(t, name, spec.types) end
        if spec.argc then return patch.get_method(t, name, spec.argc) end
    end
    return patch.get_method(t, name)
end

-- ============================ 解析 ============================

-- mod.quickapi.type(ns, class) -> 类型句柄 | nil
function q.type(ns, class)
    local k = key_of("t", ns, class)
    local t = type_cache[k]
    if t ~= nil then return t end
    t = patch.get_type(ns, class)
    if t ~= nil then type_cache[k] = t end
    return t
end

-- mod.quickapi.field(ns, class, name) -> 字段句柄 | nil（自动向上找父类）
function q.field(ns, class, name)
    local k = key_of("f", ns, class, name)
    local f = member_cache[k]
    if f ~= nil then return f end
    local t = q.type(ns, class)
    if not t then return nil end
    f = walk_members(t, patch.get_field, name)
    if f then member_cache[k] = f end
    return f
end

-- mod.quickapi.property(ns, class, name) -> 属性句柄 | nil（自动向上找父类）
function q.property(ns, class, name)
    local k = key_of("p", ns, class, name)
    local p = member_cache[k]
    if p ~= nil then return p end
    local t = q.type(ns, class)
    if not t then return nil end
    p = walk_members(t, patch.get_property, name)
    if p then member_cache[k] = p end
    return p
end

-- mod.quickapi.method(ns, class, name[, spec]) -> 方法句柄 | nil
-- spec 可为：数字（参数个数）/ {argc=n} / {params={"a","b"}} / {types={类型句柄, ...}}
function q.method(ns, class, name, spec)
    local cache_key
    if spec == nil or type(spec) == "number" then
        cache_key = key_of("m", ns, class, name, tostring(spec))
        local cached = method_cache[cache_key]
        if cached ~= nil then return cached end
    end

    local t = q.type(ns, class)
    if not t then return nil end
    local m = resolve_spec(t, name, spec)
    if not m then
        local cur, guard = patch.get_parent(t), 0
        while cur and guard < 32 do
            m = resolve_spec(cur, name, spec)
            if m then break end
            cur = patch.get_parent(cur)
            guard = guard + 1
        end
    end
    if m and cache_key then method_cache[cache_key] = m end
    return m
end

-- ============================ 字段读写 ============================

local function as_field(ns, class, field)
    if is_handle(field) then return field end
    return q.field(ns, class, field)
end

-- ============================================================================
-- 实体上下文（Entity Context）—— 写弹幕/物品时不用再碰句柄和字段
--
--   local ctx = q.proj(p)
--   ctx.x, ctx.y = ctx.pos()          -- 读位置
--   ctx.set_pos(x, y)
--   ctx.add_vel(dx, dy)
--   ctx.rot = ctx.vel_angle()         -- 朝速度方向
--   ctx.ai(0) / ctx.set_ai(0, 12)     -- localAI
--   if ctx.solid(wx, wy) then ... end
--   for _, t in ipairs(ctx.players(600)) do ... end   -- t.player, t.dist
--   ctx.kill()
-- ============================================================================

local function cached(fn)
    local v
    return function() if v == nil then v = fn() end return v end
end

function q.proj(p)
    local field_position = q.field("Terraria", "Projectile", "position")
    local field_velocity = q.field("Terraria", "Projectile", "velocity")
    local field_rotation = q.field("Terraria", "Projectile", "rotation")
    local field_local_ai  = q.field("Terraria", "Projectile", "localAI")
    local field_owner = q.field("Terraria", "Projectile", "owner")
    local array_mode = mod.patch.field_is_reference(field_local_ai)

    -- 碰撞：优先 SolidTileNoAttach(int,int)（无重载二义），退化到 Tile + SolidTile
    local method_solid_tile = nil
    local method_get_tile, method_solid_from_tile
    local solid_methods_resolved = false
    local function resolve_solid()
        if solid_methods_resolved then return end
        solid_methods_resolved = true
        method_solid_tile = q.method("Terraria", "WorldGen", "SolidTileNoAttach", 2)
        if not method_solid_tile then
            local tile = q.type("Terraria", "Tile")
            method_get_tile = q.method("Terraria", "Framing", "GetTileSafely", 2)
            if tile then
                method_solid_from_tile = q.method("Terraria", "WorldGen", "SolidTile", { types = { tile } })
            end
        end
    end

    local method_kill
    local function kill_method()
        if method_kill == nil then method_kill = q.method("Terraria", "Projectile", "Kill", 1) or false end
        return method_kill or nil
    end

    local ctx = setmetatable({}, {
        __index = function(_, k)
            if k == "rot" then
                return q.get_field_value("Terraria", "Projectile", "rotation", p, "float") or 0
            end
        end,
        __newindex = function(t, k, v)
            if k == "rot" then
                q.set_field_value("Terraria", "Projectile", "rotation", p, v, "float")
            else
                rawset(t, k, v)
            end
        end,
    })

    function ctx.pos()
        local x, y = q.get_field_value("Terraria", "Projectile", "position", p)
        return x or 0, y or 0
    end
    function ctx.set_pos(x, y) mod.patch.set_field_vec2(field_position, p, x, y) end
    function ctx.vel()
        local x, y = q.get_field_value("Terraria", "Projectile", "velocity", p)
        return x or 0, y or 0
    end
    function ctx.set_vel(x, y) mod.patch.set_field_vec2(field_velocity, p, x, y) end
    function ctx.add_vel(dx, dy)
        local x, y = ctx.vel()
        ctx.set_vel(x + dx, y + dy)
    end
    function ctx.vel_angle()
        local vx, vy = ctx.vel()
        return math.atan(vy, vx)
    end
    function ctx.owner()
        return q.get_field_value("Terraria", "Projectile", "owner", p, "int32") or 0
    end

    -- localAI：PC 是 float[]，PE 是 12 字节内联结构（FFF）
    local function read_local_ai()
        if array_mode then
            local arr = q.get_object("Terraria", "Projectile", "localAI", p)
            if not arr then return 0, 0, 0 end
            return mod.patch.array_at(arr, 0, "float") or 0,
                   mod.patch.array_at(arr, 1, "float") or 0,
                   mod.patch.array_at(arr, 2, "float") or 0
        end
        local raw = mod.patch.get_field_raw(field_local_ai, p, 12)
        if type(raw) == "string" and #raw == 12 then return string.unpack("fff", raw) end
        return 0, 0, 0
    end
    local function write_local_ai(a, b, c)
        if array_mode then
            local arr = q.get_object("Terraria", "Projectile", "localAI", p)
            if not arr then
                arr = mod.patch.array_create(3, "float")
                if arr then mod.patch.set_field_value(field_local_ai, p, arr, "object") end
                arr = q.get_object("Terraria", "Projectile", "localAI", p)
            end
            if arr then
                mod.patch.array_set(arr, 0, a, "float")
                mod.patch.array_set(arr, 1, b, "float")
                mod.patch.array_set(arr, 2, c, "float")
            end
        else
            mod.patch.set_field_raw(field_local_ai, p, string.pack("fff", a, b, c))
        end
    end

    function ctx.ai(i)
        i = i or 0
        local a, b, c = read_local_ai()
        return ({a, b, c})[i + 1] or 0
    end
    function ctx.set_ai(i, v)
        i = i or 0
        local a, b, c = read_local_ai()
        local t = {a, b, c}
        t[i + 1] = v
        write_local_ai(t[1], t[2], t[3])
    end

    function ctx.solid(wx, wy)
        resolve_solid()
        local tx, ty = math.floor(wx / 16), math.floor(wy / 16)
        if method_solid_tile then
            local ok, r = pcall(q.call, method_solid_tile, tx, ty)
            return ok and r == true
        end
        if method_get_tile and method_solid_from_tile then
            local ok1, tile = pcall(q.call, method_get_tile, tx, ty)
            if ok1 and tile then
                local ok2, r = pcall(q.call, method_solid_from_tile, tile)
                return ok2 and r == true
            end
        end
        return false
    end

    function ctx.players(radius)
        local out = {}
        local px, py = ctx.pos()
        local players = q.get_object("Terraria", "Main", "player")
        if not players then return out end
        local n = mod.patch.array_length(players)
        local r2 = (radius or 0) ^ 2
        for i = 0, n - 1 do
            local pl = mod.patch.array_at(players, i)
            if pl then
                local active = q.get_field_value("Terraria", "Player", "active", pl, "bool")
                local dead = q.get_field_value("Terraria", "Player", "dead", pl, "bool")
                if active and not dead then
                    local ax, ay = q.get_field_value("Terraria", "Player", "position", pl)
                    if ax then
                        local dx, dy = ax - px, ay - py
                        local d2 = dx * dx + dy * dy
                        if not radius or d2 <= r2 then
                            out[#out + 1] = { player = pl, index = i, dist = math.sqrt(d2) }
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.dist < b.dist end)
        return out
    end
    function ctx.kill()
        local m = method_kill()
        if m then pcall(q.call, m, p) end
    end

    return ctx
end

-- Buff 便捷层：按名字施加/查询/移除（内部处理 runtime_id 分配时机）
function q.buff_apply(player, name, seconds)
    local id = q.buff_id(name)
    if not id then return false, "buff not ready" end
    local left = mod.buff.add(id, player, math.floor((seconds or 5) * 60))
    return type(left) == "number" and left >= 0, left
end

-- mod.quickapi.get_field_value(ns, class, field[, instance[, type]])
-- instance 为 nil 表示静态字段；type 省略时由内核推断（Android 建议显式写）
function q.get_field_value(ns, class, field, instance, vtype)
    local f = as_field(ns, class, field)
    if not f then fail(2, "找不到字段 %s.%s.%s", ns, class, tostring(field)) end
    return patch.get_field_value(f, instance, vtype)
end

-- mod.quickapi.set_field_value(ns, class, field, instance, value[, type]) -> bool
function q.set_field_value(ns, class, field, instance, value, vtype)
    local f = as_field(ns, class, field)
    if not f then fail(2, "找不到字段 %s.%s.%s", ns, class, tostring(field)) end
    return patch.set_field_value(f, instance, value, vtype)
end

-- 引用类型字段的便捷读写（等价于 type 传 "object"）
function q.get_object(ns, class, field, instance)
    return q.get_field_value(ns, class, field, instance, "object")
end

function q.set_object(ns, class, field, instance, value)
    return q.set_field_value(ns, class, field, instance, value, "object")
end

-- ============================ 方法调用 ============================

-- 一个方法被调用时的 Lua 实参总数 = 形参个数 +（实例方法多出来的 instance）
local function total_args(m)
    local n = patch.method_param_count(m)
    if n == nil then return nil end
    if patch.method_is_instance(m) then return n + 1 end
    return n
end

-- 按实参个数在（含父类的）同名重载里挑一个：唯一匹配 -> 句柄；否则 nil, 匹配个数
local function pick_by_argcount(t, name, nargs)
    local list = patch.get_methods(t, true)
    if type(list) ~= "table" then return nil, 0 end
    local found, count = nil, 0
    for i = 1, #list do
        local m = list[i]
        if m and patch.method_name(m) == name and total_args(m) == nargs then
            found = m
            count = count + 1
        end
    end
    if count == 1 then return found end
    return nil, count
end

-- mod.quickapi.invoke(ns, class, name, ...) -> 返回值
-- 自动按实参个数选重载，并自动区分实例方法（首参为 instance）与静态方法。
function q.invoke(ns, class, name, ...)
    local nargs = select("#", ...)
    local t = q.type(ns, class)
    if not t then fail(2, "找不到类型 %s.%s", tostring(ns), tostring(class)) end

    local k = key_of("i", ns, class, name, nargs)
    local m = method_cache[k]
    if m == nil then
        local matches
        m, matches = pick_by_argcount(t, name, nargs)
        if m == nil and matches == 0 then
            -- 没有按个数精确匹配的重载时，退回内核按名字取（与裸 patch 行为一致）
            m = q.method(ns, class, name)
        end
        if m then method_cache[k] = m end
    end
    if not m then
        fail(2, "找不到能接受 %d 个实参的方法 %s.%s.%s（重载多义时请用 mod.quickapi.method + mod.patch.invoke 指定）",
                nargs, ns, class, name)
    end

    local args = table.pack(...)
    if patch.method_is_instance(m) then
        return patch.invoke(m, args[1], table.unpack(args, 2, args.n))
    end
    return patch.invoke(m, table.unpack(args, 1, args.n))
end

-- mod.quickapi.call(method, ...) -> 返回值：已持有方法句柄时，自动区分实例 / 静态
function q.call(method, ...)
    if not is_handle(method) then fail(2, "call 需要方法句柄") end
    local args = table.pack(...)
    if patch.method_is_instance(method) then
        return patch.invoke(method, args[1], table.unpack(args, 2, args.n))
    end
    return patch.invoke(method, table.unpack(args, 1, args.n))
end

-- ============================ 钩子 ============================

local function resolve_hook_method(ns, class, method, opts)
    if is_handle(method) then return method end
    local t = q.type(ns, class)
    if not t then fail(3, "找不到类型 %s.%s", tostring(ns), tostring(class)) end

    local spec
    if opts then
        if opts.params then spec = { params = opts.params }
        elseif opts.types then spec = { types = opts.types }
        elseif opts.argc ~= nil then spec = opts.argc end
    end

    local m = resolve_spec(t, method, spec)
    if not m then
        local cur, guard = patch.get_parent(t), 0
        while cur and guard < 32 do
            m = resolve_spec(cur, method, spec)
            if m then break end
            cur = patch.get_parent(cur)
            guard = guard + 1
        end
    end
    if not m then fail(3, "找不到方法 %s.%s.%s", ns, class, tostring(method)) end
    return m
end

-- mod.quickapi.install_hook(ns, class, method[, opts])
-- opts：{prefix=fn, postfix=fn, copy=bool, override_result=bool, argc/params/types 用于选重载}
-- 也可直接把 opts 写成函数（等价 postfix）。返回 hook 句柄，可 hook:remove()。
function q.install_hook(ns, class, method, opts)
    if type(opts) == "function" then opts = { postfix = opts } end
    opts = opts or {}
    local m = resolve_hook_method(ns, class, method, opts)
    return patch.install_hook(m, opts)
end

-- 复制 opts 并写入回调，避免改写调用方传入的表
local function with_callback(opts, key, fn)
    local o = {}
    if type(opts) == "table" then
        for k, v in pairs(opts) do o[k] = v end
    end
    o[key] = fn
    return o
end

-- mod.quickapi.install_hook_prefix(ns, class, method, fn[, opts])
function q.install_hook_prefix(ns, class, method, fn, opts)
    return q.install_hook(ns, class, method, with_callback(opts, "prefix", fn))
end

-- mod.quickapi.install_hook_postfix(ns, class, method, fn[, opts])
function q.install_hook_postfix(ns, class, method, fn, opts)
    return q.install_hook(ns, class, method, with_callback(opts, "postfix", fn))
end

-- ============================ 合成 ============================
--
-- 与自定义物品无关的独立配方（原版物品、多配方等）。
--   mod.quickapi.add_recipe{
--       result    = 22,                              -- 或 { id = 22, count = 3 }
--       materials = { { id = 9, count = 10 }, ... },
--       station   = 18,                              -- 工作台 tile id；省略 = 无站点
--   }
-- 配方不会立刻生效：内核在下次重建配方表（进世界 / 切语言）时统一写入。

local RECIPE_META = { result = true, materials = true, station = true }

function q.add_recipe(t)
    if type(t) ~= "table" then fail(2, "add_recipe 需要表参数") end
    if not mod_env.recipe or type(mod_env.recipe.add) ~= "function" then
        fail(2, "当前 LuaLoader 不支持 mod.recipe，请更新加载器")
    end
    for k in pairs(t) do
        if type(k) == "string" and not RECIPE_META[k] then
            fail(3, "add_recipe: 不认识的属性 %s", tostring(k))
        end
    end
    return mod_env.recipe.add(t)
end

-- ============================ 注册：物品 / 弹幕 / Buff ============================
--
-- 写法刻意贴近泰拉瑞亚源码 Item.SetDefaults / Projectile.SetDefaults：
-- 属性直接平铺在表里（damage = 25, useStyle = 1, ...），不再包一层 defaults。
--
--   mod.quickapi.register_item{
--       name = "my_sword",
--       texture = "sword.png",
--       tooltip = true,
--       sacrifice = 1,
--       prefixes = "sword",
--
--       damage = 25, useTime = 20, useStyle = 1, autoReuse = true,
--       width = 40, height = 40, melee = true, rare = 2, maxStack = 1,
--
--       language = { en = {...}, zh = {...} },
--       recipe   = { result = 1, materials = {...}, station = 18 },
--
--       use = function(player, item) end,   -- 每次真正使用回调一次（on_use 同义）
--   }

-- 注册表元字段：这些不是 Item / Projectile 的字段，需要原样交给 LuaLoader
local ITEM_META = {
    name = true, texture = true, tooltip = true, sacrifice = true,
    defaults = true, prefixes = true, can_use = true, language = true, recipe = true,
    animation = true,   -- { ticks = 8, frames = 9 }：竖向帧图动画（DrawAnimationVertical）
    use_sound = true,   -- SoundID 里的字段名，例如 "Item1" / "Item2"
    use = true, on_use = true,   -- 每次真正使用回调一次：(player, item)
}

local NPC_META = {
    name = true, texture = true, frames = true, defaults = true, ai = true,
    vanilla_ai = true,
    loot = true, on_death = true, on_kill = true,   -- 掉落表 / 死亡回调（on_kill 同义）
}

local PROJECTILE_META = {
    name = true, texture = true, defaults = true, ai = true, no_ai = true,
    vanilla_ai = true,   -- true = 原版 AI 先跑，再调用 ai（不再跳过原版）
    frames = true,       -- 竖向帧图帧数（写进 Main.projFrames[type]；0 = 单帧整图）
    on_kill = true, kill = true,   -- 弹幕被销毁时回调一次：(projectile)
    on_hit_npc = true, hit_npc = true,             -- 命中 NPC：(projectile, npc, damage, dir, crit)
    on_hit_player = true, hit_player = true,       -- 命中玩家：(projectile, player, damage, dir, pvp, crit)
    on_tile_collide = true, tile_collide = true,   -- 撞墙：(projectile, old_vx, old_vy)
}

-- 字段代理：instance.damage = 25 直接写到底层对象（源码风格的关键）。
-- 用于 defaults 函数：拿到 proxy 后按 Item.SetDefaults 的写法逐行赋值。
local function field_proxy(ns, class, inst)
    return setmetatable({}, {
        __index = function(_, k)
            local f = q.field(ns, class, k)
            if not f then return nil end
            return patch.get_field_value(f, inst)
        end,
        __newindex = function(_, k, v)
            if v == nil then return end
            local f = q.field(ns, class, k)
            if not f then
                fail(3, "%s 上不存在字段 %s（属性名拼写？）", class, tostring(k))
            end
            patch.set_field_value(f, inst, v)
        end,
    })
end

-- mod.quickapi.projectile_animate(p[, ticks_per_frame])
-- 帧图推进：frameCounter 计满 ticks 就 frame = (frame+1) % projFrames[type]。
-- 需要 register_projectile 声明了 frames；在弹幕 ai 回调里每帧调用一次。
function q.projectile_animate(p, ticks)
    local t = ticks or 8
    local fc = (q.get_field_value("Terraria", "Projectile", "frameCounter", p, "int32") or 0) + 1
    if fc >= t then
        fc = 0
        local f = q.get_field_value("Terraria", "Projectile", "frame", p, "int32") or 0
        local n = 1
        local arr = q.get_object("Terraria", "Main", "projFrames", nil)
        if arr then
            local ty = q.get_field_value("Terraria", "Projectile", "type", p, "int32") or 0
            n = tonumber(mod.patch.array_at(arr, ty, "int32")) or 1
        end
        if n < 1 then n = 1 end
        q.set_field_value("Terraria", "Projectile", "frame", p, (f + 1) % n, "int32")
    end
    q.set_field_value("Terraria", "Projectile", "frameCounter", p, fc, "int32")
end

-- ============================ 联机同步 ============================

-- mod.quickapi.net_mode() -> 0=单机 1=客户端 2=服务端
function q.net_mode()
    if mod.net and mod.net.mode then return mod.net.mode() end
    return 0
end

-- mod.quickapi.send_to_server(channel, payload)
-- 客户端 -> 服务端 RPC；服务端对应 Mod 的 on_receive 会被调用。
function q.send_to_server(channel, payload)
    if mod.net and mod.net.send_to_server then
        mod.net.send_to_server(channel, payload or "")
    end
end

-- mod.quickapi.on_server_receive(function(channel, payload, player) end)
function q.on_server_receive(fn)
    if mod.net and mod.net.on_receive then
        mod.net.on_receive(fn)
    end
end

-- mod.quickapi.tile_kill(x, y[, no_item])
-- 客户端请求服务端挖掉一个图格（服务端权威执行并广播给所有人）。
-- 单机/服务端调用没有意义（本地 KillTile 本身就会同步），可安全调用。
function q.tile_kill(x, y, no_item)
    if mod.net and mod.net.tile_kill then
        mod.net.tile_kill(x, y, no_item or false)
    end
end

-- mod.quickapi.tile_square(x, y, w, h)：请求服务端同步一块区域的图格
function q.tile_square(x, y, w, h)
    if mod.net and mod.net.tile_square then
        mod.net.tile_square(x, y, w, h)
    end
end

-- mod.quickapi.proxy(ns, class, instance)：手动拿一个字段代理
function q.proxy(ns, class, instance)
    return field_proxy(ns, class, instance)
end

-- 把平铺的属性拆成 { meta = {...}, fields = { 字段名 = 值 } }。
-- 同时校验字段名，拼错在注册阶段就报错，而不是静默忽略。
local function split_spec(t, ns, class, meta, label)
    local spec, fields = {}, {}
    for k, v in pairs(t) do
        if meta[k] then
            spec[k] = v
        else
            if type(k) ~= "string" then
                fail(3, "%s: 属性名必须是字符串", label)
            end
            if not q.field(ns, class, k) then
                fail(3, "%s: %s 上不存在字段 %s", label, class, k)
            end
            fields[k] = v
        end
    end

    -- 显式写的 defaults 表并进平铺字段
    if type(spec.defaults) == "table" then
        for k, v in pairs(spec.defaults) do fields[k] = v end
    end

    -- 物品的 shoot 支持直接写弹幕名（字符串），运行时解析成 ID
    local shoot_name
    if class == "Item" and type(fields.shoot) == "string" then
        shoot_name = fields.shoot
        fields.shoot = nil
    end

    -- 物品音效：quickapi 自己写 Item.UseSound（旧版 LuaLoader 也可用）。
    -- 注意：Android 上 SoundID 的静态字段要等类初始化后才能读到值，
    -- 所以注册阶段只校验字段存在，真正取值推迟到 defaults 回调里。
    local sound_name
    if class == "Item" and spec.use_sound ~= nil then
        sound_name = spec.use_sound
        spec.use_sound = nil
        if type(sound_name) ~= "string" then
            fail(3, "%s: use_sound 需要 SoundID 字段名（如 \"Item1\"）", label)
        end
        if not q.field("Terraria.ID", "SoundID", sound_name) then
            fail(3, "%s: 找不到 SoundID.%s", label, sound_name)
        end
    end

    local sound_obj
    local user_fn = type(spec.defaults) == "function" and spec.defaults or nil

    -- 需要运行时算值（函数 / 弹幕名 / 音效）时，用函数形式 + 字段代理
    if user_fn or shoot_name or sound_name then
        spec.defaults = function(inst)
            local item = field_proxy(ns, class, inst)
            for k, v in pairs(fields) do item[k] = v end
            if shoot_name then
                item.shoot = (mod_env.projectile and mod_env.projectile.runtime_id(shoot_name)) or 0
            end
            if sound_name then
                if not sound_obj then
                    sound_obj = q.get_object("Terraria.ID", "SoundID", sound_name)
                    if not sound_obj and mod_env.warn then
                        mod_env.warn("quickapi: SoundID.%s 读取失败，已跳过", sound_name)
                    end
                end
                if sound_obj then item.UseSound = sound_obj end
            end
            if user_fn then user_fn(item) end
        end
    else
        spec.defaults = fields
    end

    return spec
end

-- 注册新物品。返回 runtime_id（内核分配前为 -1），失败返回 nil。
function q.register_item(t)
    if type(t) ~= "table" then fail(2, "register_item 需要表参数") end
    if not t.name then fail(2, "register_item 缺少 name") end
    return mod_env.item.register(split_spec(t, "Terraria", "Item", ITEM_META,
            "register_item(" .. tostring(t.name) .. ")"))
end

-- 注册新弹幕。返回 runtime_id（内核分配前为 -1），失败返回 nil。
-- 注意：写了 ai 就由 Lua 接管，位移（position += velocity）要自己算；
--       若想保留原版 aiStyle，再加 vanilla_ai = true（原版 AI 先跑，ai 后置补充）。
--       可用 mod.quickapi.projectile_move(p)，或用 q.proj(p) 上下文。
--       on_kill / kill：(projectile) 在弹幕被销毁时回调一次。
--       on_hit_npc / on_hit_player：(projectile, target, damage, direction, [pvp,] crit)
--       on_tile_collide：(projectile, old_vx, old_vy)，想反弹就把 velocity 写回去。
function q.register_projectile(t)
    if type(t) ~= "table" then fail(2, "register_projectile 需要表参数") end
    if not t.name then fail(2, "register_projectile 缺少 name") end
    if not mod_env.projectile then
        fail(2, "当前 LuaLoader / TEFKernel 不支持 mod.projectile，请更新内核与加载器")
    end
    return mod_env.projectile.register(split_spec(t, "Terraria", "Projectile",
            PROJECTILE_META, "register_projectile(" .. tostring(t.name) .. ")"))
end

-- 注册新 NPC。返回 runtime_id（内核分配前为 -1），失败返回 nil。
--
--   mod.quickapi.register_npc{
--       name       = "my_slime",
--       texture    = "slime.png",
--       frames     = 1,
--       vanilla_ai = false,              -- true = 原版 AI 先跑，再调 ai
--       width = 32, height = 32, lifeMax = 100, damage = 10, ...  -- NPC 字段平铺
--       ai = function(npc) end,
--   }
function q.register_npc(t)
    if type(t) ~= "table" then fail(2, "register_npc 需要表参数") end
    if not t.name then fail(2, "register_npc 缺少 name") end
    if not mod_env.npc then
        fail(2, "当前 LuaLoader / TEFKernel 不支持 mod.npc，请更新内核与加载器")
    end
    return mod_env.npc.register(split_spec(t, "Terraria", "NPC", NPC_META,
            "register_npc(" .. tostring(t.name) .. ")"))
end

-- 注册新 Buff。返回 runtime_id（内核分配前为 -1），失败返回 nil。
--
--   mod.quickapi.register_buff{
--       name       = "my_buff",
--       texture    = "buff.png",     -- 图标；不放用内核占位图
--       debuff     = false,          -- 减益：图标红框、优先被顶掉
--       no_time    = false,          -- 不显示剩余时间
--       pvp        = false,          -- 仅 PvP 生效
--       light_pet  = false, vanity_pet = false,   -- 宠物类（同类互斥）
--       apply  = function(player, time) end,        -- 挂上时
--       update = function(player, buff_index) end,  -- 每帧，Buff 激活时
--       language = { en = {name=, description=}, zh = {...} },
--   }
--
-- 注意：原版不认识自定义 type，属性加成/扣血等效果必须写在 update 里。
--       自定义 Buff 不进原版 .plr，由内核伴生存档 <角色>.plr.tef 存读。
local BUFF_META = {
    name = true, texture = true, debuff = true, no_time = true, pvp = true,
    light_pet = true, vanity_pet = true,
    apply = true, update = true, language = true,
}

function q.register_buff(t)
    if type(t) ~= "table" then fail(2, "register_buff 需要表参数") end
    if not t.name then fail(2, "register_buff 缺少 name") end
    if not mod_env.buff then
        fail(2, "当前 LuaLoader / TEFKernel 不支持 mod.buff，请更新内核与加载器")
    end

    -- Buff 没有 Terraria.Buff 类型可校验字段，这里只允许上面列出的键，
    -- 拼错在注册阶段就报错，避免"写了没效果"。
    local spec = {}
    for k, v in pairs(t) do
        if type(k) ~= "string" or not BUFF_META[k] then
            fail(3, "register_buff(%s): 不认识的属性 %s", tostring(t.name), tostring(k))
        end
        spec[k] = v
    end
    return mod_env.buff.register(spec)
end

-- 取运行时 ID（内核分配后才有效）
function q.item_id(name)
    if not mod_env.item then return nil end
    return mod_env.item.runtime_id(name)
end

function q.projectile_id(name)
    if not mod_env.projectile then return nil end
    return mod_env.projectile.runtime_id(name)
end

function q.npc_id(name)
    if not mod_env.npc then return nil end
    return mod_env.npc.runtime_id(name)
end

-- 在世界坐标生成自定义 NPC，返回 Main.npc 下标（失败 nil）
function q.npc_spawn(name, x, y)
    if not mod_env.npc then return nil end
    return mod_env.npc.spawn(name, x, y)
end

function q.buff_id(name)
    if not mod_env.buff then return nil end
    return mod_env.buff.runtime_id(name)
end

-- 玩家身上某 Buff 的剩余帧数（未挂上返回 0）。走内核自管状态，不读 buffType。
function q.player_buff_time(player, id)
    if not player or not id or id < 0 then return 0 end
    if not mod_env.buff or not mod_env.buff.time then return 0 end
    return tonumber(mod_env.buff.time(id, player)) or 0
end

-- 给玩家挂 Buff。time 单位是帧（60 = 1 秒）；已存在时取较长者。
-- 返回 true/false, 失败原因。
function q.player_add_buff(player, id, time)
    if not player or not id or id < 0 then return false, "invalid player/id" end
    if not mod_env.buff or not mod_env.buff.add then
        return false, "当前内核不支持自定义 Buff（mod.buff.add）"
    end
    local left = mod_env.buff.add(id, player, time)
    if type(left) ~= "number" or left < 0 then return false, "内核拒绝添加（列表满或 id 无效）" end
    return true
end

-- ============================ 弹幕 AI 辅助 ============================

-- 向量工具（Terraria 的 Vector2 是内联结构体，走 get_field_vec2）
local vec = {}
q.vec = vec

function vec.get(ns, class, field, instance)
    local f = as_field(ns, class, field)
    if not f then fail(2, "找不到字段 %s.%s.%s", ns, class, tostring(field)) end
    return patch.get_field_vec2(f, instance)
end

function vec.set(ns, class, field, instance, x, y)
    local f = as_field(ns, class, field)
    if not f then fail(2, "找不到字段 %s.%s.%s", ns, class, tostring(field)) end
    return patch.set_field_vec2(f, instance, x, y)
end

-- 自定义弹幕的「移动」：position += velocity，并按速度旋转。
-- 内核在 Mod 提供 ai 时会跳过原版 AI()，位移必须自己做。
--
-- opts:
--   face_velocity    = false 时不做旋转（默认 true）
--   rotation_offset  = 贴图朝向补偿（弧度，默认 0）
--                      约定：贴图「朝右（+x）」时用 0；
--                      贴图「朝上（-y）」时传 math.pi / 2。
-- 返回新的 position（x, y）。
function q.projectile_move(p, opts)
    opts = opts or {}
    local px, py = vec.get("Terraria", "Projectile", "position", p)
    local vx, vy = vec.get("Terraria", "Projectile", "velocity", p)
    vec.set("Terraria", "Projectile", "position", p, px + vx, py + vy)
    if opts.face_velocity ~= false then
        -- rotation 是 float（不是 Vector2），必须用 set_field_value
        q.set_field_value("Terraria", "Projectile", "rotation", p,
                math.atan(vy, vx) + (opts.rotation_offset or 0), "float")
    end
    return px + vx, py + vy
end

-- 朝目标转向：保持速率不变，按 rate(0~1) 比例插值方向。
-- 返回新的 vx, vy。
function q.projectile_homing(p, tx, ty, rate, max_turn)
    local px, py = vec.get("Terraria", "Projectile", "position", p)
    local vx, vy = vec.get("Terraria", "Projectile", "velocity", p)
    local speed = math.sqrt(vx * vx + vy * vy)
    if speed < 1e-4 then return vx, vy end

    local dx, dy = tx - px, ty - py
    local dlen = math.sqrt(dx * dx + dy * dy)
    if dlen < 1e-3 then return vx, vy end

    -- 当前方向与目标方向的夹角
    local cur = math.atan(vy, vx)
    local want = math.atan(dy, dx)
    local diff = want - cur
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end

    local turn = diff * (rate or 0.2)
    if max_turn and math.abs(turn) > max_turn then
        turn = (turn > 0) and max_turn or -max_turn
    end

    local a = cur + turn
    vx, vy = math.cos(a) * speed, math.sin(a) * speed
    vec.set("Terraria", "Projectile", "velocity", p, vx, vy)
    return vx, vy
end

-- 找最近的敌对 NPC（供弹幕追踪用）。range 单位为像素，默认 900。
-- 返回 npc 句柄、距离；找不到返回 nil。
function q.find_nearest_npc(p, range)
    range = range or 900
    local T_NPC = q.type("Terraria", "NPC")
    local T_Main = q.type("Terraria", "Main")
    if not (T_NPC and T_Main) then return nil end

    local npcs = q.get_object("Terraria", "Main", "npc", nil)
    if not npcs then return nil end

    local px, py = vec.get("Terraria", "Projectile", "position", p)
    local best, best_d2 = nil, range * range
    local n = patch.array_length(npcs)
    for i = 0, n - 1 do
        local npc = patch.array_at(npcs, i)
        if npc then
            local active = q.get_field_value("Terraria", "NPC", "active", npc, "bool")
            local friendly = q.get_field_value("Terraria", "NPC", "friendly", npc, "bool")
            local life = q.get_field_value("Terraria", "NPC", "life", npc, "int32")
            if active and not friendly and life and life > 0 then
                local nx, ny = vec.get("Terraria", "NPC", "position", npc)
                local dx, dy = nx - px, ny - py
                local d2 = dx * dx + dy * dy
                if d2 < best_d2 then
                    best, best_d2 = npc, d2
                end
            end
        end
    end
    return best, math.sqrt(best_d2)
end

-- 自动挂到 mod 表，require 之后 mod.quickapi.* 即可用（与直接使用 require 的返回值等价）
mod_env.quickapi = q

return q
