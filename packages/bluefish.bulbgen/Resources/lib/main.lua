-- ============================================================================
-- 花苞速生 v1.2.1
-- 面板一个按钮：生成花苞
-- ----------------------------------------------------------------------------
-- 版本演进：
--   v1.0.0  11×11 个位置全交给 PlaceJunglePlant → 一圈草地全被种满（但确实能放）。
--   v1.0.1  引入 TileData 一维下标读图格 → 越界闪退（il2cpp 里 pcall 拦不住）。
--   v1.0.2  WorldGen.SolidTile 预筛 + 只调用一次 → 安全但未验证。
--   v1.0.3  只试 (cx, cy) → 从不生成。
--   v1.0.4  加了播报，但仍然只试 (cx, cy)/(cx+1, cy) ，还是从不生成。
--
--   ★ 真正的根因（v1.0.5 才想明白）：
--     Player.position 是「碰撞箱左上角」，角色高约 42 像素 ≈ 2.6 格。
--     所以 (cx, cy+1) 是玩家身体所在格，不是脚下地面！
--     PlaceJunglePlant 要求「下方那格是丛林草 60」，v1.0.3/1.0.4 拿玩家的身体格去满足,
--     永远是空气，原版必然拒绝 —— 所以一直什么都不生成。
--
--     v1.0.0 之所以能生成，是因为它把 ±5 格 121 个位置全试了一遍，
--     其中恰好包含正确的脚下高度，所以放出来了（顺带放了一堆）。
--
--   v1.0.5 的做法：
--     ① 用 Player.height 精确算出脚底所在格 groundY = floor((py + height) / 16)；
--     ② 花苞放在 Y2 = groundY - 1（占 [groundY-2, groundY-1]，正好坐在 groundY 的地面上）；
--     ③ 水平方向试 cx 和 cx+1 两个位置 —— 两者 2×2 区域共享 cx 列，
--        第一个成功时第二个必然被原版挡掉，所以最多生成一个；
--     ④ 预筛只在 SolidTile 明确返回 false 时排除该位置，返回 nil（取不到）不算；
--     ⑤ 成功/失败都在聊天栏播报并说明原因。
--
--   v1.0.6  放开高度容差：从脚底所在格往下最多找 4 格，取第一块「下方是实心地面」
--           的位置放。这样角色离地一格（跳跃/踩在半空平台）也能生成。
--           找到第一个就立即返回，所以仍然只会生成一个。
-- ============================================================================
mod.meta = { pkg_id = "bluefish.bulbgen", version = "1.2.1", version_code = 1201, api_version = 1 }
local P = mod.patch
local F, H = {}, {}

local T_PLANTERA_BULB = 238
local status = "站在丛林草上方点击"
local first_draw = true          -- 首次绘制时把面板收起，之后不再干预

-- ---------------- 小工具 ----------------
local function gval(field, ty, dflt)
    if not field then return dflt end
    local ok, v = pcall(P.get_field_value, field, nil, ty)
    if not ok or v == nil then return dflt end
    return v
end
local function gint(field, dflt) return gval(field, "int32", dflt) end
-- v1.0.10：gbool 必须严格。
--   原来直接 return gval(field, "bool", ...)，只要返回值非 nil 就原样用；
--   il2cpp 的 bool 如果被当成数字 0 返回，而 Lua 里 0 是 truthy，
--   于是「三王是否击败」永远是真，门槛形同虚设。
local function gbool(field, dflt)
    if not field then return dflt end
    local ok, v = pcall(P.get_field_value, field, nil, "bool")
    if ok and type(v) == "boolean" then return v end
    -- 兜底：按 int32 读，非 0 视为真
    local ok2, n = pcall(P.get_field_value, field, nil, "int32")
    if ok2 and type(n) == "number" then return n ~= 0 end
    return dflt
end
local function gobj(field)
    if not field then return nil end
    local ok, v = pcall(P.get_field_value, field, nil, "object")
    if ok then return v end
    return nil
end

-- 聊天栏播报（PE 上没有 4 参重载，必须 5 参）
local function say(text)
    if not H.new_text then return end
    local s = text
    if P.string_create then
        local okc, v = pcall(P.string_create, text)
        if okc and v then s = v end
    end
    pcall(P.invoke, H.new_text, s, 144, 238, 144, false)   -- 浅绿
end

local function local_player_index()
    if F.my_player_f then
        local v = gint(F.my_player_f, nil)
        if type(v) == "number" and v >= 0 then return v end
    end
    if H.get_my_player then
        local ok, v = pcall(P.invoke, H.get_my_player)
        if ok and type(v) == "number" and v >= 0 then return v end
    end
    return nil
end

local function player_obj()
    local my = local_player_index()
    if not my then return nil end
    local arr = gobj(F.player_f)
    if not arr then return nil end
    local ok, pl = pcall(P.array_at, arr, my)
    if ok then return pl end
    return nil
end

local function player_px(pl)
    if not pl or not F.pos_f then return nil end
    local ok, px, py = pcall(P.get_field_vec2, F.pos_f, pl)
    if not ok or type(px) ~= "number" or type(py) ~= "number" then return nil end
    return px, py
end

-- 实心判断（按图格坐标，内部自带 inWorld 边界检查）；返回 true/false/nil
local function solid(x, y)
    if H.solid3 then
        local ok, v = pcall(P.invoke, H.solid3, x, y, false)
        if ok and type(v) == "boolean" then return v end
    end
    if H.solid2 then
        local ok, v = pcall(P.invoke, H.solid2, x, y)
        if ok and type(v) == "boolean" then return v end
    end
    return nil
end

-- il2cpp 的 bool 可能以数字返回（0 为假），这里统一成 true/false/nil
local function as_bool(v)
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    return nil
end
-- 是否身处丛林（属性，要用 get_ZoneJungle）
local function zone_jungle(pl)
    if not H.get_zone_jungle or not pl then return nil end
    local ok, v = pcall(P.invoke, H.get_zone_jungle, pl)
    if ok and type(v) == "boolean" then return v end
    return nil
end

-- ---------------- 三王状态（只显示） ----------------
local function mech_bits()
    return gbool(F.mech1_f, false), gbool(F.mech2_f, false), gbool(F.mech3_f, false)
end

-- ---------------- 生成 ----------------
local function do_generate()
    if not H.place then
        status = "取不到放置方法"
        return
    end
    local pl = player_obj()
    if not pl then
        status = "取不到角色"
        return
    end
    local px, py = player_px(pl)
    if not px then
        status = "取不到角色坐标"
        return
    end

    -- 三王检查：必须三个机械 Boss 都击败过
    local m1, m2, m3 = mech_bits()
    if not (m1 and m2 and m3) then
        say("生成失败：还没有击败三王")
        status = "未击败三王"
        return
    end

    -- 丛林判断
    local zj = zone_jungle(pl)
    if zj == false then
        say("生成失败：这里不是丛林")
        status = "不在丛林"
        return
    end

    local cx = math.floor(px / 16)

    -- 身高：碰撞箱高度（站立 42，蹲下 22）
    local h = 42
    if F.height_f then
        local okh, v = pcall(P.get_field_value, F.height_f, pl, "int32")
        if okh and type(v) == "number" and v > 0 then h = v end
    end

    -- 脚底所在图格 = 地面格；站立时花苞放 groundY-1（占 [groundY-2, groundY-1]）
    local ground_y = math.floor((py + h) / 16)
    local base_y = ground_y - 1

    -- 世界尺寸也只在点击时读一次
    local mx = gint(F.max_x_f, 0)
    local my = gint(F.max_y_f, 0)
    if type(mx) ~= "number" or mx <= 0 then mx = 0 end
    if type(my) ~= "number" or my <= 0 then my = 0 end
    -- v1.2.0：改走 AttemptToGeneratePlanteraBulbAt(i, j, false)。
    --   它内部就是 PlaceJunglePlant + 检查 Main.tile[i, j].type == 238，
    --   返回值 true/false 才是「真的放上了 / 没放上」。
    --   高度容差保留：从脚底往下最多 4 格，找到第一个成功的位置就停。
    local function try_at(x, y)
        local ok_bounds = (x > 5) and (y > 5)
        if mx > 0 and x >= mx - 5 then ok_bounds = false end
        if my > 0 and y >= my - 5 then ok_bounds = false end
        if not ok_bounds then return false end
        if H.attempt then
            local okr, v = pcall(P.invoke, H.attempt, x, y, false)
            if okr and as_bool(v) == true then return true end
            return false
        end
        -- 兜底：取不到判定方法时只能调用放置方法，无法知道结果
        if H.place then
            pcall(P.invoke, H.place, x, y, T_PLANTERA_BULB, 0, 0, false)
            status = string.format("已放置 (%d, %d) 未校验", x, y)
            return true
        end
        return false
    end

    for k = 0, 4 do
        local y = base_y + k
        for di = 0, 1 do                       -- 水平 cx / cx+1，2×2 区域共享 cx 列
            local x = cx + di
            if try_at(x, y) then
                if not H.attempt then return end
                say("世纪之花花苞已生成")
                status = string.format("已生成 (%d, %d)", x, y)
                return
            end
        end
    end
    say("生成失败：脚下 4 格内没有可用的丛林草地面")
    status = "未生成：脚下没有丛林草"
end

-- ============================================================================
-- setup
-- ============================================================================
function setup()
    local okM, TM = pcall(P.get_type, "Terraria", "Main")
    local okPlr, TP = pcall(P.get_type, "Terraria", "Player")
    local okW, TW = pcall(P.get_type, "Terraria", "WorldGen")
    local okN, TN = pcall(P.get_type, "Terraria", "NPC")
    if not (okM and okW) then return end

    F.my_player_f = P.get_field(TM, "myPlayer")
    do
        local ok, m = pcall(P.get_method, TM, "get_myPlayer", 0)
        if ok then H.get_my_player = m end
    end
    F.max_x_f = P.get_field(TM, "maxTilesX")
    F.max_y_f = P.get_field(TM, "maxTilesY")
    F.player_f = P.get_field(TM, "player")

    do
        local ok, m = pcall(P.get_method, TM, "NewText", 5)
        if ok then H.new_text = m end
    end

    if okPlr then
        F.pos_f = P.get_field(TP, "position")
        F.height_f = P.get_field(TP, "height")
        if not F.pos_f or not F.height_f then
            local okE, TE = pcall(P.get_type, "Terraria", "Entity")
            if okE then
                if not F.pos_f then F.pos_f = P.get_field(TE, "position") end
                if not F.height_f then F.height_f = P.get_field(TE, "height") end
            end
        end
        local okz, mz = pcall(P.get_method, TP, "get_ZoneJungle", 0)
        if okz then H.get_zone_jungle = mz end
    end

    if okN then
        F.mech1_f = P.get_field(TN, "downedMechBoss1")
        F.mech2_f = P.get_field(TN, "downedMechBoss2")
        F.mech3_f = P.get_field(TN, "downedMechBoss3")
    end

    -- SolidTile(int i, int j, bool noDoors = false)
    do
        local ok, m = pcall(P.get_method, TW, "SolidTile", 3)
        if ok then H.solid3 = m end
        local ok2, m2 = pcall(P.get_method, TW, "SolidTile", 2)
        if ok2 then H.solid2 = m2 end
    end

    -- PlaceJunglePlant(int X2, int Y2, ushort type, int styleX, int styleY, bool inheritPaint)
    local ok, m = pcall(P.get_method, TW, "PlaceJunglePlant", 6)
    if ok then H.place = m end
    -- AttemptToGeneratePlanteraBulbAt(int i, int j, bool forceBulb) —— private static bool
    --   内部就是 PlaceJunglePlant + 检查 Main.tile[i, j].type == 238，
    --   返回值才是真正的「放上了 / 没放上」。
    do
        local oka, ma = pcall(P.get_method, TW, "AttemptToGeneratePlanteraBulbAt", 3)
        if oka then H.attempt = ma end
    end
end

-- ============================================================================
-- on_gui
-- ============================================================================
-- 每帧只画界面，不读任何游戏字段；三王状态、世界尺寸都在 do_generate 里现读。
-- v1.1.1：面板精简为「按钮 + 按钮下方的状态提示」，去掉标题行、三王行和分隔线。
function mod.on_gui()
    local g = mod.gui
    if type(g) ~= "table" then return end
    if type(g.set_title) == "function" then pcall(g.set_title, "花苞速生", "花") end
    if type(g.set_width) == "function" then pcall(g.set_width, 260) end
    -- 进游戏第一帧收起面板，避免挡住视线；用户展开后不会再被强制收起
    if first_draw then
        first_draw = false
        if type(g.set_collapsed) == "function" then pcall(g.set_collapsed, true) end
    end
    local function line(s) pcall(g.text, s) end

    if type(g.button) == "function" then
        if g.button("生成花苞") then do_generate() end
    end
    line(status ~= "" and status or "就绪")
end

mod.setup = setup
todo_list = { "setup" }