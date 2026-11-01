-- 村正（Murasama）移植 —— 仅默认皮肤 / 仅 PE（Android）
--
-- 来源：BunnyLoader「Murasama Standalone」的 Murasama.js + MuraHeld / MuraSlash。
--
-- 0.3.3（依据 Terraria 1.4.5.8 PE 源码核对后重写取值层）：
--   · 真正的病根：Player.CCed 在 PE 里是「只读属性」，不是字段。
--     q.get_field_value 找不到字段会直接 error()，而当时它写在 AI 的中段，
--     于是 AI 每 tick 都在那里中断 —— frame / position / timeLeft 全都没执行。
--     表现就是「刀不动、动画不放」，60 tick 后弹幕自然死亡再重生。
--     （0.2.0 的「变成射弹飞出去」也是它：中断后没机会把 velocity 归零。）
--   · 现在所有字段读取都走统一的 read()/read_vec2()：先按字段取，失败再按属性
--     取 getter，全都不行就返回 nil（绝不再抛异常）。
--   · Main.MouseWorld / screenPosition / mouseX / mouseY 在 PE 里同样是属性，
--     不是字段。鼠标世界坐标改成多策略探测，实在取不到就退化成按玩家朝向。
--   · AI 主体包在 pcall 里：任何一个名字写错只会打一条警告，不会再让武器卡死。
--   · 自己写 Main.projFrames[type]，不再依赖内核是否登记了帧数。
--
-- 0.3.8（重要）：
--   前几版反复失败的真正原因：**帧尺寸 != 命中框尺寸**时，弹丸落点取决于内核
--   用哪个原点（帧中心 / 命中框中心 / 贴图中心）。这三种取法给出的位置各不相同，
--   所以无论偏移怎么调，总有一边是错的 —— 0.3.7 把画布改成 512x320、命中框 260，
--   这种不匹配反而更严重，于是「朝右也不对、朝左更偏」。
--   现在把不变式直接做进资产：
--       帧尺寸 == 命中框尺寸 == 256（正方形），且刀柄在帧中心
--   于是三种原点取法结果完全一致，都与内核实现无关：
--       draw at Center, origin=帧中心     -> 刀柄在手
--       draw at position + 帧尺寸/2       -> 刀柄在手
--       draw at Center, origin=命中框中心 -> 刀柄在手
--   画面尺寸用 Projectile.scale = 2.0 还原（256*2 = 512，与原画幅一致）。
--   生成脚本 test/bake_centered.py；不变式由 test/check_invariant.py 守护。
--
-- 0.3.7：
--   · 根治「刀柄不在玩家手上」：不再用「引擎端偏移量」去补偿贴图里偏心的刀柄。
--     偏移量必须和引擎的旋转/翻转精确配对，任何一处不一致（多翻一次、换贴图、
--     翻转方向不同）就会把刀柄甩到别处 —— 前面几版反复失败都是这个原因。
--     现在改成资产端解决：每帧内容整体平移，使「刀柄」正好落在帧中心
--     （实测质心距中心 0.5~1.2 px），于是
--         弹丸中心 == 刀柄 == 玩家手
--     无论引擎怎么旋转、怎么翻转，这个等式都成立。偏移常量因此归零。
--     画布 384x270 -> 512x320 以容纳平移后的刀光（裁掉 88 px 边缘）。
--     生成脚本：test/bake_centered.py
--
-- 0.3.6：
--   · 修「刀柄跑到玩家后面、看起来在砍玩家」：这是绘制层的问题，不是位置。
--     源码 Main.Draw 的顺序是
--         DrawProjectiles();              // drawLayer == 0 的弹幕在这里
--         DrawPlayers_AfterProjectiles(); // 玩家
--         DrawCachedProjs(OverPlayers);   // drawLayer == 4 的弹幕在这里
--     我们的弹幕一直用默认层 0，所以整把刀都画在玩家之前、被玩家盖住，
--     刀刃穿过身体看着就像"刀在砍玩家"，朝左时刀身压在身体上尤其明显。
--     现在把斩击设为 drawLayer = 4（OverPlayers），画在玩家之后。
--     BL 里对应的是 HELD_LAYER(=7) + player.heldProj，这里用 4 更简单且等价于"在玩家上面"。
--
-- 0.3.5：
--   · 刀柄逐帧定位。握把在贴图里的位置每帧都不一样（实测 x 56~70、y -17~-38），
--     用单一常数会在某些帧偏出去。现在用逐帧表（由帧 10/0/6 的实测值按动画顺序
--     分段线性插值得到，见 test/hilt_measure.py）。
--   · 挥舞时不再画刀鞘。MuraHeld 本身就是一把深色刀柄，而斩击贴图里也画了刀柄，
--     两者叠在玩家身上就是那个「黑色把柄」。现在斩击在场时不生成刀鞘，
--     收刀后再补回来（BL 用的是更细的 MuraHeld2，这里因为没有绘制钩子，
--     直接不画更干净）。开关见 HIDE_SCABBARD_WHILE_SWINGING。
--
-- 0.3.4：
--   · 刀柄不在玩家手上。之前把弹幕中心摆在「玩家中心 + 120 像素」，
--     但这张贴图里刀柄并不在帧中心：量出来握把在帧内约 (129,160)，
--     而帧中心是 (192,135)，所以偏移应为 (+63, -25)，不是 (+120, 0)。
--     差 56.9 x 24.8 像素 = 3.6 格右 / 1.6 格下，正是「刀把在右边几格」。
--     （量法见 test/hilt_measure.py；三个斩击帧 10/0/6 的握把质心互相吻合。）
--   · 偏移现在带垂直分量，等价于原作 PreDraw 里的 TILT 补偿，不需要再单独加。
--
-- 朝向：PE 的 vanilla 绘制按 Projectile.spriteDirection == -1 做水平翻转
--       （不是 direction）。所以这里把 spriteDirection 固定为 1 让内核不翻，
--       左右朝向交给贴图：MuraSlash = 原图，MuraSlashL = 垂直翻转
--       （等价于原作的 rotation+180° 且 FlipH）。

require("quickapi")

local q = mod.quickapi
local patch = mod.patch

-- ------------------------------------------------------------------
-- 日志：同一句话只打一次，避免每 tick 刷屏
-- ------------------------------------------------------------------
local warned = {}
local function warn_once(msg)
    if warned[msg] then return end
    warned[msg] = true
    mod.warn("[murasama] " .. msg)
end

-- ------------------------------------------------------------------
-- 安全取值层
--
-- PE 里很多成员是「属性」而不是字段（CCed / selectedItem / myPlayer /
-- MouseWorld / screenPosition / mouseX / mouseY 都是）。q.field 只认字段，
-- 找不到就 fail()，所以不能直接用它。这里按「字段 -> 属性 getter」的顺序
-- 探测一次并缓存，之后按缓存走；任何一步失败都返回 nil。
-- ------------------------------------------------------------------
local access = {}          -- key -> "field" | "prop" | false

local function resolve_access(ns, cls, name)
    local key = ns .. "." .. cls .. "." .. name
    local how = access[key]
    if how ~= nil then return how end

    local ok, f = pcall(q.field, ns, cls, name)
    if ok and f then
        how = "field"
    else
        local ok2, p = pcall(q.property, ns, cls, name)
        if ok2 and p then how = "prop" else how = false end
    end
    access[key] = how
    return how
end

-- 读标量。失败返回 nil（不抛异常）。
local function read(ns, cls, name, inst, kind)
    local how = resolve_access(ns, cls, name)
    if how == "field" then
        local ok, v = pcall(q.get_field_value, ns, cls, name, inst, kind or "int32")
        if ok then return v end
        return nil
    elseif how == "prop" then
        local p = q.property(ns, cls, name)
        local g = patch.property_get_method(p)
        if not g then return nil end
        local ok, v
        if inst == nil then ok, v = pcall(patch.invoke, g)
        else ok, v = pcall(patch.invoke, g, inst) end
        if ok then return v end
        return nil
    end
    return nil
end

-- 读 Vector2。先试「当字段读」，再试「当属性 handle 读」，最后试 getter 返回两个数。
local function read_vec2(ns, cls, name, inst)
    local how = resolve_access(ns, cls, name)
    if how == "field" then
        local ok, a, b = pcall(q.vec.get, ns, cls, name, inst)
        if ok and type(a) == "number" then return a, b end
        return nil
    elseif how == "prop" then
        local p = q.property(ns, cls, name)
        -- 属性句柄直接喂给 vec2 读取（某些内核支持）
        local ok, a, b = pcall(patch.get_field_vec2, p, inst)
        if ok and type(a) == "number" then return a, b end
        -- getter 返回两个数
        local g = patch.property_get_method(p)
        if g then
            local ok2, r1, r2 = pcall(patch.invoke, g, inst)
            if ok2 and type(r1) == "number" and type(r2) == "number" then return r1, r2 end
        end
        return nil
    end
    return nil
end

-- 写标量。失败返回 false（不抛异常）。
local function write(ns, cls, name, inst, v, kind)
    local how = resolve_access(ns, cls, name)
    if how ~= "field" then return false end
    local ok = pcall(q.set_field_value, ns, cls, name, inst, v, kind or "int32")
    return ok
end

local function write_vec2(ns, cls, name, inst, x, y)
    local how = resolve_access(ns, cls, name)
    if how ~= "field" then return false end
    local ok = pcall(q.vec.set, ns, cls, name, inst, x, y)
    return ok
end

local function pf(player, name, kind) return read("Terraria", "Player", name, player, kind) end
local function proj_f(p, name, kind) return read("Terraria", "Projectile", name, p, kind) end

-- 玩家选择栏位：PE 里是属性
local function selected(player)
    local v = read("Terraria", "Player", "selectedItem", player, "int32")
    return v or 0
end

local function my_player()
    local v = read("Terraria", "Main", "myPlayer", nil, "int32")
    return v or 0
end

local function center_of(inst, is_player)
    local ns, cls = "Terraria", is_player and "Player" or "Projectile"
    local x, y = read_vec2(ns, cls, "position", inst)
    if not x then return nil end
    local w = read(ns, cls, "width", inst, "int32") or 0
    local h = read(ns, cls, "height", inst, "int32") or 0
    return x, y, w, h, x + w / 2, y + h / 2
end

local function held_item(player)
    local inv = read("Terraria", "Player", "inventory", player, "object")
    if not inv then return nil end
    local ok, item = pcall(patch.array_at, inv, selected(player))
    if ok then return item end
    return nil
end

local function is_murasama(item)
    if not item then return false end
    local t = read("Terraria", "Item", "type", item, "int32")
    return t ~= nil and t == q.item_id("Murasama")
end

local function owned_count(player, name)
    local id = q.projectile_id(name)
    if not id or id < 0 or not player then return 0 end
    local counts = read("Terraria", "Player", "ownedProjectileCounts", player, "object")
    if not counts then return 0 end
    local ok, n = pcall(patch.array_at, counts, id, "int32")
    if ok then return tonumber(n) or 0 end
    return 0
end

-- ------------------------------------------------------------------
-- 生成 / 销毁弹幕
-- ------------------------------------------------------------------
local t_proj = patch.get_type("Terraria", "Projectile")
local m_proj_kill = t_proj and patch.get_method(t_proj, "Kill", 0) or nil

local function find_new_projectile()
    local m = t_proj and patch.get_method(t_proj, "NewProjectile", 12)
    if m then return m end
    return t_proj and patch.get_method(t_proj, "NewProjectile", 13) or nil
end
local m_new_proj = find_new_projectile()

local proj_source
do
    local st = patch.get_type("Terraria.DataStructures", "EntitySource_SpawnNPC")
    if st then
        local ok, inst = pcall(patch.new_instance, st)
        if ok then proj_source = inst end
    end
end

local function spawn_projectile(id, x, y, vx, vy, damage, owner, ai0, ai1, ai2)
    if not id or id < 0 or not m_new_proj then return nil end
    local ok, result = pcall(patch.invoke, m_new_proj, proj_source, x, y, vx, vy, id,
        damage, 0.0, owner, ai0 or 0.0, ai1 or 0.0, ai2 or 0.0, nil)
    if ok then return result end
    warn_once("NewProjectile 调用失败: " .. tostring(result))
    return nil
end

local function kill_projectile(p)
    if m_proj_kill then pcall(patch.invoke, m_proj_kill, p) end
end

local function projectile_at(idx)
    local list = read("Terraria", "Main", "projectile", nil, "object")
    if not list or idx == nil then return nil end
    local ok, p = pcall(patch.array_at, list, idx)
    if ok then return p end
    return nil
end

-- ------------------------------------------------------------------
-- 鼠标世界坐标：PE 里 MouseWorld / screenPosition / mouseX / mouseY 都是属性。
-- 逐级降级，成功一次就记住走哪条路。
-- ------------------------------------------------------------------
local mouse_mode = nil      -- "world" | "screen" | "none"

local function mouse_probe()
    -- 1) Main.MouseWorld（属性，Vector2）
    local x, y = read_vec2("Terraria", "Main", "MouseWorld", nil)
    if x then return "world", x, y end

    -- 2) screenPosition（属性，Vector2）+ mouseX / mouseY（属性，int）
    local sx, sy = read_vec2("Terraria", "Main", "screenPosition", nil)
    local mx = read("Terraria", "Main", "mouseX", nil, "int32")
    local my = read("Terraria", "Main", "mouseY", nil, "int32")
    if sx and mx and my then return "screen", sx + mx, sy + my end

    return "none"
end

local function mouse_world()
    if mouse_mode == nil then
        local mode, x, y = mouse_probe()
        mouse_mode = mode
        if mode == "world" then
            mod.log("[murasama] 瞄准：Main.MouseWorld")
        elseif mode == "screen" then
            mod.log("[murasama] 瞄准：screenPosition + mouseX/Y")
        else
            mod.warn("[murasama] 取不到鼠标世界坐标，瞄准退化为按玩家朝向")
        end
        if mode ~= "none" then return x, y end
    elseif mouse_mode ~= "none" then
        local _, x, y = mouse_probe()
        if x then return x, y end
    end
    return nil
end

-- ------------------------------------------------------------------
-- 斩击的常量
--   逻辑 14 帧，每 3 tick 一帧；起手帧 10；斩击帧 10 / 0 / 6，第三段 ×2。
--   帧号完全由 tick 推出：base = (10 + floor((tick-1)/3)) % 14
-- ------------------------------------------------------------------
local BASE_FRAMES = 14
local SLASH_TICKS = 3
local SLASH_START = 10
-- 刀柄已经在贴图里被摆到帧中心（见 test/bake_centered.py），
-- 所以弹丸中心就等于刀柄，直接放在手上即可，不需要任何偏移。
local HILT_OFFSET = false

-- 挥舞时不画刀鞘（MuraHeld 也是个深色刀柄，会和斩击贴图里的刀柄叠成黑疙瘩）
local HIDE_SCABBARD_WHILE_SWINGING = true
local CUT_FRAMES = { [10] = true, [0] = true, [6] = true }
local CUT_BIG = 6
local PROJ_DIRECTION = 1        -- 固定 1：让内核不按 spriteDirection 翻转
-- ProjectileDrawLayerID.OverPlayers = 4：在 DrawPlayers_AfterProjectiles 之后绘制
local OVER_PLAYERS = 4
-- 命中框必须与贴图帧尺寸完全相等，否则落点会随内核的 origin 取法漂移。
local SLASH_BOX = 256
local SLASH_SCALE = 2.0             -- 256 * 2 = 512，还原原画幅

local SLASH_ID, SLASH_L_ID = -1, -1
local frames_set = false

local function refresh_ids()
    SLASH_ID = q.projectile_id("MuraSlash") or -1
    SLASH_L_ID = q.projectile_id("MuraSlashL") or -1
end

-- 自己登记帧数，不依赖内核
local function ensure_frames()
    if frames_set then return end
    local arr = read("Terraria", "Main", "projFrames", nil, "object")
    if not arr then return end
    if SLASH_ID < 0 then refresh_ids() end
    if SLASH_ID >= 0 then pcall(patch.array_set, arr, SLASH_ID, BASE_FRAMES, "int32") end
    if SLASH_L_ID >= 0 then pcall(patch.array_set, arr, SLASH_L_ID, BASE_FRAMES, "int32") end
    local held = q.projectile_id("MuraHeld")
    if held and held >= 0 then pcall(patch.array_set, arr, held, 2, "int32") end
    frames_set = true
end

local function is_slash_type(ty)
    return ty == SLASH_ID or ty == SLASH_L_ID
end

local function is_cut(f) return CUT_FRAMES[f] == true end

local function frame_of(tick)
    if tick <= 1 then return SLASH_START end
    return (SLASH_START + math.floor((tick - 1) / SLASH_TICKS)) % BASE_FRAMES
end

local atan2 = math.atan2 or math.atan

-- ------------------------------------------------------------------
-- 弹幕运行状态：放 Lua 表，以 whoAmI 为键（PE 的 Projectile 没有 identity 字段）
-- ------------------------------------------------------------------
local states = {}

local function state_key(p)
    local id = proj_f(p, "whoAmI")
    return id or -1
end

local function forget(p)
    states[state_key(p)] = nil
end

-- ------------------------------------------------------------------
-- 把刀摆到「玩家中心 + 120 * 朝向角」
-- ------------------------------------------------------------------
-- 把刀摆到手上。贴图里刀柄已在帧中心，所以弹丸中心直接对准玩家中心即可。
local function place_slash(player, p)
    local _, _, _, _, cx, cy = center_of(player, true)
    if not cx then return end
    local w = proj_f(p, "width") or SLASH_BOX
    local h = proj_f(p, "height") or SLASH_BOX
    write_vec2("Terraria", "Projectile", "position", p, cx - w / 2, cy - h / 2)
end

-- ------------------------------------------------------------------
-- 持刀弹幕（刀鞘）。BL 对它用 FlipHorizontally，所以贴图第 2 帧是水平镜像。
-- ------------------------------------------------------------------
local HELD_MIRROR = 1

local function held_ai_impl(p)
    ensure_frames()
    local owner = proj_f(p, "owner") or -1
    local players = read("Terraria", "Main", "player", nil, "object")
    if owner < 0 or not players then kill_projectile(p); return end

    local ok, player = pcall(patch.array_at, players, owner)
    if not ok or not player then kill_projectile(p); return end
    if pf(player, "active", "bool") ~= true or pf(player, "dead", "bool") == true
        or not is_murasama(held_item(player)) then
        kill_projectile(p); return
    end

    local _, _, _, _, cx, cy = center_of(player, true)
    if not cx then kill_projectile(p); return end
    local dir = pf(player, "direction") or 1
    local w = proj_f(p, "width") or 32
    local h = proj_f(p, "height") or 32

    local attacking = owned_count(player, "MuraSlash") > 0 or owned_count(player, "MuraSlashL") > 0
    if HIDE_SCABBARD_WHILE_SWINGING and attacking then
        kill_projectile(p)
        return
    end
    local full_rotation = pf(player, "fullRotation", "float") or 0

    write_vec2("Terraria", "Projectile", "position", p, cx - w / 2, cy + 5 - h / 2)
    write_vec2("Terraria", "Projectile", "velocity", p, 0, 0)
    write("Terraria", "Projectile", "rotation", p,
        math.rad((attacking and 110 or 70) * dir) + full_rotation, "float")
    write("Terraria", "Projectile", "frame", p, (dir < 0) and HELD_MIRROR or 0, "int32")
    write("Terraria", "Projectile", "direction", p, PROJ_DIRECTION, "int32")
    write("Terraria", "Projectile", "spriteDirection", p, PROJ_DIRECTION, "int32")
    write("Terraria", "Projectile", "scale", p, 0.7, "float")
    write("Terraria", "Projectile", "timeLeft", p, 2, "int32")

    if not attacking then
        write("Terraria", "Player", "heldProj", player, proj_f(p, "whoAmI") or -1, "int32")
    end
end

local function held_ai(p)
    local ok, err = pcall(held_ai_impl, p)
    if not ok then warn_once("held ai: " .. tostring(err)) end
end

-- ------------------------------------------------------------------
-- 斩击弹幕
-- ------------------------------------------------------------------
local function drop_duplicate(p, owner)
    local who = proj_f(p, "whoAmI") or -1
    local list = read("Terraria", "Main", "projectile", nil, "object")
    if who < 0 or not list then return false end
    local ty = proj_f(p, "type") or -1
    if not is_slash_type(ty) then return false end
    local ok, n = pcall(patch.array_length, list)
    if not ok or not n then return false end
    for i = 0, n - 1 do
        local other = projectile_at(i)
        if i ~= who and other
            and proj_f(other, "active", "bool") == true
            and is_slash_type(proj_f(other, "type") or -1)
            and (proj_f(other, "owner") or -1) == owner then
            forget(p)
            kill_projectile(p)
            return true
        end
    end
    return false
end

local function slash_ai_impl(p)
    ensure_frames()
    local owner = proj_f(p, "owner") or -1
    local players = read("Terraria", "Main", "player", nil, "object")
    if owner < 0 or not players then kill_projectile(p); return end

    local okp, player = pcall(patch.array_at, players, owner)
    if not okp or not player then forget(p); kill_projectile(p); return end
    if pf(player, "active", "bool") ~= true or pf(player, "dead", "bool") == true then
        forget(p); kill_projectile(p); return
    end

    -- ---- 状态 ----
    local key = state_key(p)
    local st = states[key]
    if not st then
        if drop_duplicate(p, owner) then return end
        st = { tick = 0, dmg = proj_f(p, "damage") or 0 }
        states[key] = st
        write("Terraria", "Projectile", "alpha", p, 0, "int32")
        write_vec2("Terraria", "Projectile", "velocity", p, 0, 0)
    end
    local dmg = st.dmg
    if dmg <= 0 then
        dmg = proj_f(p, "damage") or 0
        st.dmg = dmg
    end

    st.tick = st.tick + 1
    local tick = st.tick
    local base = frame_of(tick)

    local _, _, _, _, cx, cy = center_of(player, true)
    if not cx then forget(p); kill_projectile(p); return end
    local mine = (owner == my_player())

    -- ---- 是否还在按住 ----
    -- 注意：PE 里没有可写的 CCed 字段（它是只读属性），这里不用它。
    local holding = false
    if mine then
        local use = pf(player, "controlUseItem", "bool") == true
        local chan = pf(player, "channel", "bool") == true
        holding = (use or chan)
            and pf(player, "noItems", "bool") ~= true
        if holding and not is_murasama(held_item(player)) then holding = false end
    end

    -- ---- 朝向角 ----
    local angle
    if mine and holding then
        local mx, my = mouse_world()
        if mx then
            local dx, dy = mx - cx, my - cy
            if dx * dx + dy * dy < 0.25 then
                angle = (pf(player, "direction") or 1) >= 0 and 0.0 or math.pi
            else
                angle = atan2(dy, dx)
            end
        else
            angle = (pf(player, "direction") or 1) >= 0 and 0.0 or math.pi
        end
    else
        angle = proj_f(p, "rotation", "float") or 0
    end

    -- 松手：走完当前这一段再收刀（BL 的 canDie 只在斩击帧成立）
    if mine and not holding and is_cut(base) then
        forget(p)
        kill_projectile(p)
        return
    end

    local dir = (math.cos(angle) >= 0) and 1 or -1
    if dir == 0 then dir = 1 end

    -- ---- 玩家姿态（放在换贴图之前，换的那一 tick 玩家也立刻转向）----
    write("Terraria", "Player", "direction", player, dir, "int32")
    write("Terraria", "Player", "itemRotation", player,
        atan2(math.sin(angle) * dir, math.cos(angle) * dir), "float")
    write("Terraria", "Player", "heldProj", player, proj_f(p, "whoAmI") or -1, "int32")
    write("Terraria", "Player", "itemTime", player, 2, "int32")
    write("Terraria", "Player", "itemAnimation", player, 2, "int32")

    -- ---- 朝左换成镜像贴图的弹幕（只在非斩击帧换，避免半途换图）----
    local want_left = (dir < 0)
    local is_left = (proj_f(p, "type") == SLASH_L_ID)
    if want_left ~= is_left and (tick <= 1 or not is_cut(base)) then
        local new_id = want_left and SLASH_L_ID or SLASH_ID
        if new_id and new_id >= 0 then
            local who = spawn_projectile(new_id, cx, cy, 0, 0, dmg, owner, 0, 0, 0)
            local np = projectile_at(who)
            if np then
                write("Terraria", "Projectile", "frame", np, base, "int32")
                write("Terraria", "Projectile", "rotation", np, angle, "float")
                write("Terraria", "Projectile", "direction", np, PROJ_DIRECTION, "int32")
                write("Terraria", "Projectile", "spriteDirection", np, PROJ_DIRECTION, "int32")
                write_vec2("Terraria", "Projectile", "velocity", np, 0, 0)
                write("Terraria", "Projectile", "drawLayer", np, OVER_PLAYERS, "int32")
                write("Terraria", "Projectile", "scale", np, SLASH_SCALE, "float")
                place_slash(player, np)
                -- 时钟跟着搬过去
                states[state_key(np)] = { tick = st.tick, dmg = st.dmg }
            end
            forget(p)
            kill_projectile(p)
            return
        end
    end

    -- ---- 判定与伤害：只和本 tick 显示的帧绑定 ----
    local slashing = is_cut(base)
    write("Terraria", "Projectile", "friendly", p, slashing, "bool")
    local want = math.floor((slashing and base == CUT_BIG) and dmg * 2 or dmg)
    if (proj_f(p, "damage") or -1) ~= want then
        write("Terraria", "Projectile", "damage", p, want, "int32")
    end

    -- ---- 位置 / 朝向 / 帧 ----
    write("Terraria", "Projectile", "frame", p, base, "int32")
    write("Terraria", "Projectile", "rotation", p, angle, "float")
    write("Terraria", "Projectile", "direction", p, PROJ_DIRECTION, "int32")
    write("Terraria", "Projectile", "spriteDirection", p, PROJ_DIRECTION, "int32")
    write_vec2("Terraria", "Projectile", "velocity", p, 0, 0)
    -- 画在玩家之后（否则会被玩家盖住，看着像刀在砍玩家）
    write("Terraria", "Projectile", "drawLayer", p, OVER_PLAYERS, "int32")
    write("Terraria", "Projectile", "scale", p, SLASH_SCALE, "float")
    place_slash(player, p)

    -- ---- 续命 ----
    write("Terraria", "Projectile", "timeLeft", p, 2, "int32")
end

local function slash_ai(p)
    local ok, err = pcall(slash_ai_impl, p)
    if not ok then warn_once("slash ai: " .. tostring(err)) end
end

-- ------------------------------------------------------------------
-- 注册
-- ------------------------------------------------------------------
local function player_of(a, b)
    local list = { a, b }
    for i = 1, 2 do
        local v = list[i]
        if v then
            local ok, who = pcall(read, "Terraria", "Player", "whoAmI", v, "int32")
            if ok and type(who) == "number" then return v end
        end
    end
    return nil
end

local function register_slash(name, texture)
    q.register_projectile{
        name = name,
        texture = texture,
        frames = BASE_FRAMES,
        defaults = {
            width = SLASH_BOX, height = SLASH_BOX,
            scale = SLASH_SCALE,
            aiStyle = -1,
            friendly = true, hostile = false,
            penetrate = -1,
            tileCollide = false,
            timeLeft = 60,
            alpha = 0,
            usesLocalNPCImmunity = true,
            localNPCHitCooldown = 6,
            drawLayer = 4,          -- ProjectileDrawLayerID.OverPlayers：画在玩家之后
        },
        ai = slash_ai,
    }
end

function mod.init()
    q.register_projectile{
        name = "MuraHeld",
        texture = "MuraHeld.png",
        frames = 2,                 -- 0 = 原图，1 = 水平镜像
        defaults = {
            width = 32, height = 32,
            aiStyle = -1,
            friendly = false, hostile = false,
            penetrate = -1,
            tileCollide = false,
            ignoreWater = true,
            timeLeft = 300,
            alpha = 0,
        },
        ai = held_ai,
    }

    register_slash("MuraSlash", "MuraSlash.png")     -- 朝右
    register_slash("MuraSlashL", "MuraSlashL.png")   -- 朝左（原图垂直翻转）

    q.register_item{
        name = "Murasama",
        texture = "Murasama.png",
        animation = { ticks = 2, frames = 13 },

        width = 90, height = 134,
        damage = 90,
        knockBack = 6.5,
        noMelee = true,
        noUseGraphic = true,
        channel = true,
        autoReuse = false,
        useStyle = 5,
        useAnimation = 25,
        useTime = 9,
        rare = 8,
        value = 0,
        maxStack = 1,

        -- shootSpeed = 0：刀生成时速度为 0，位置完全由 AI 摆放
        shoot = "MuraSlash",
        shootSpeed = 0,

        can_use = function(a, b)
            local player = player_of(a, b)
            if not player then return true end
            return owned_count(player, "MuraSlash") == 0
                and owned_count(player, "MuraSlashL") == 0
        end,

        language = {
            zh = {
                name = "村正",
                tooltip = "灾厄模组的村正（移植版）：按住左键连续三段斩击，第三段造成双倍伤害。\n特殊按键技能暂未移植。",
            },
        },

        recipe = {
            result = 1,
            materials = {
                { id = 22, count = 15 },
                { id = 177, count = 5 },
                { id = 75, count = 5 },
            },
            station = 16,
        },
    }
end

-- ------------------------------------------------------------------
-- 每 tick（玩家更新之后）：
--   1) 保证手里有一把刀鞘
--   2) 再摆一次刀的位置（弹幕 AI 可能跑在玩家移动之前，否则奔跑时刀会拖在身后）
-- ------------------------------------------------------------------
q.install_hook_postfix("Terraria", "Player", "ItemCheck", function(player)
    if not player then return end
    local ok, err = pcall(function()
        if SLASH_ID < 0 then refresh_ids() end
        ensure_frames()

        local who = pf(player, "whoAmI")
        if who ~= my_player() then return end

        local swinging = owned_count(player, "MuraSlash") > 0
            or owned_count(player, "MuraSlashL") > 0
        if HIDE_SCABBARD_WHILE_SWINGING and swinging then
            -- 斩击在场时不画刀鞘，收刀后由下面这段补回来
            local held_id = q.projectile_id("MuraHeld")
            if held_id and held_id >= 0 then
                local list0 = read("Terraria", "Main", "projectile", nil, "object")
                if list0 then
                    local n0 = select(2, pcall(patch.array_length, list0))
                    if type(n0) == "number" then
                        for i = 0, n0 - 1 do
                            local px = projectile_at(i)
                            if px and proj_f(px, "active", "bool") == true
                                and (proj_f(px, "type") or -1) == held_id
                                and (proj_f(px, "owner") or -1) == who then
                                kill_projectile(px)
                            end
                        end
                    end
                end
            end
        elseif is_murasama(held_item(player)) and owned_count(player, "MuraHeld") == 0 then
            local held_id = q.projectile_id("MuraHeld")
            if held_id and held_id >= 0 then
                local _, _, _, _, cx, cy = center_of(player, true)
                if cx then spawn_projectile(held_id, cx, cy, 0, 0, 0, who) end
            end
        end

        local list = read("Terraria", "Main", "projectile", nil, "object")
        if not list then return end
        local n = select(2, pcall(patch.array_length, list))
        if type(n) ~= "number" then return end
        for i = 0, n - 1 do
            local p = projectile_at(i)
            if p and proj_f(p, "active", "bool") == true
                and is_slash_type(proj_f(p, "type") or -1)
                and (proj_f(p, "owner") or -1) == who then
                place_slash(player, p)
            end
        end
    end)
    if not ok then warn_once("ItemCheck hook: " .. tostring(err)) end
end)
