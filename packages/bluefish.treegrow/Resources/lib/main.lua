-- ============================================================================
-- 一日看尽三回长 v1.0.0
--   ① 7 种宝石果无视深度，表层也能长成宝石树
--   ② 宝石果种下立即长成宝石树
--   ③ 橡实种下立即长成树
--   三个开关各自独立，默认全开
--
-- ── 原理（PC 源码 WorldGen.cs:73395 AttemptToGrowTreeFromSapling）────────────
--   switch (tile.type)
--   {
--       case 590:                              // 590 = 宝石果（Gemcorn）
--           if (!underground) return false;    // ← 深度限制就是这一行
--           num2 = 587;                        // 默认红宝石
--           switch (tile.frameX / 54)          // 7 种果实 → 7 种宝石树
--           { case 0: num2 = 583; ... case 6: num2 = 589; }
--           flag = TryGrowingTreeByType(num2, x, y, ...);
--           return flag;
--       case 20:                               // 20 = 普通树苗（橡实种下后）
--           if (underground && !notTheBees && !remix) return false;
--           flag = TryGrowingTreeByType(5, x, y, ...);   // 普通树
--           return flag;
--   }
--
--   原版随机生长传两种值：表层 false（73019 行）、地下 true（74359 行）。
--   所以「无视深度」= 表层那次返回 false 之后，按 underground=true 再调一次。
--
--   为什么用 postfix + override_result 而不是 prefix 改参数：
--     args 是内核封送出来的只读表（api_patch_hook.cpp 只做 push 没有回写），
--     改了不生效；而 prefix 可以 `return true, 自定义结果` 覆盖原方法返回值。
--     用 postfix 还有个好处——只有原版真的失败了才补一次：
--     表层普通树苗本来就 result=true，完全不会被我们碰到，零误伤。
--
--   「立即长成」= 钩 WorldGen.PlaceTile，放完瓦片后立刻调同一个方法。
--     原版要等随机 tick，这里放完就长。
-- ============================================================================
-- 注意：LuaLoader 用全局 mod，绝不可写成 local mod = ...
mod.meta = { pkg_id = "bluefish.treegrow", version = "1.0.4", version_code = 104, api_version = 1 }

local P     = mod.patch
local hooks = {}

local TILE_GEMCORN = 590    -- 宝石果种下后的瓦片类型
local TILE_TREE     = 20    -- 橡实种下后的树苗瓦片类型

local function note(s) pcall(mod.info, "[一日看尽三回长] " .. tostring(s)) end

-- ==================== 开关（默认全开，落盘 treegrow_cfg.txt）====================
local CFG_FILE = "treegrow_cfg.txt"
local S = { depth = true, gem = true, oak = true }

local function save_cfg()
    pcall(mod.write_file, CFG_FILE, string.format("%s|%s|%s",
        S.depth and "1" or "0", S.gem and "1" or "0", S.oak and "1" or "0"))
end

local function load_cfg()
    local ok, txt = pcall(mod.read_file, CFG_FILE)
    if not ok or type(txt) ~= "string" then return end
    local a, b, c = string.match(txt, "^(%d)|(%d)|(%d)")
    if not a then return end
    S.depth = (a == "1")
    S.gem   = (b == "1")
    S.oak   = (c == "1")
end

-- ==================== 句柄 ====================
local M_attempt      -- WorldGen.AttemptToGrowTreeFromSapling(int,int,bool,int,bool)
local M_place        -- WorldGen.PlaceTile(int,int,int,bool,bool,int,int)
local M_main_update  -- Main.Update(GameTime)
local M_game_menu    -- Main.get_gameMenu()
local M_world_id     -- Main.get_worldID()
local F_generating   -- WorldGen.generatingWorld（世界生成期不处理，防止刷树）
local M_placeit      -- Player.PlaceThing_Tiles_PlaceIt(bool newObjectType, TileObject data, int tileToCreate)
local M_ttx, M_tty   -- Player.get_tileTargetX() / get_tileTargetY()（静态属性）
local F_world_surface -- Main.worldSurface（double，地表线 y）。用来判断某格是否在地下

local function field_bool(f)
    if not f then return false end
    local ok, v = pcall(P.get_field_value, f, nil, "bool")
    if ok and v == true then return true end
    return false
end

-- 调一次「从树苗长树」。underground=true 时宝石果能长，普通树苗会被原版挡掉。
local busy = false
local function grow_sapling(x, y, underground)
    if not M_attempt then return false end
    if busy then return false end
    busy = true
    local ok, r = pcall(P.invoke, M_attempt, x, y, underground, 0, false)
    busy = false
    return ok and r == true
end

-- ==================== 钩子 1：无视深度 ====================
-- 原版返回 false 且这次是「表层调用」时，按 underground=true 再来一次。
local function on_attempt(inst, args, result)
    if result == true then return nil end      -- 原版成功了，不碰
    if not S.depth then return nil end         -- 无视深度：关
    if args[3] ~= false then return nil end    -- 本来就在地下，失败与深度无关
    if grow_sapling(args[1], args[2], true) then
        return true                            -- 覆盖返回值：告诉原版「长成了」
    end
    return nil
end

-- ==================== 钩子 2/3：种下立即长成 ====================
-- v1.0.1：改成 prefix 记录 + 下一帧执行。
--   原来在 PlaceTile 的 postfix 里当场长，两个隐患：
--     ① postfix 时瓦片可能还没走完 SquareTileFrame，frameX 还没算好；
--     ② 在 PlaceTile 的调用栈内部再调 AttemptToGrowTreeFromSapling（它自己也会
--        改瓦片、调 SquareTileFrame），容易踩到重入。
--   现在只记坐标，下一帧 Main.Update 里再做，等价于「原版刚放完就长」，
--   而且瓦片状态一定已经稳定。延迟 1 帧（约 16ms）肉眼看不出。
local pending = {}          -- { {x, y, ty}, ... }
local function on_place_prefix(inst, args, result)
    local ty = args[3]
    if ty ~= TILE_GEMCORN and ty ~= TILE_TREE then return false end
    if field_bool(F_generating) then return false end   -- 世界生成阶段不动手
    pending[#pending + 1] = { args[1], args[2], ty }
    if #pending > 32 then table.remove(pending, 1) end
    return false
end

-- v1.0.2：真正的入口。PE 版玩家种树走这里，不走 WorldGen.PlaceTile。
--   参数 args[3] = tileToCreate，就是瓦片 ID（590 宝石果 / 20 橡实）。
--   坐标从静态属性 tileTargetX / tileTargetY 读（player 那边一直是这两个）。
local function on_placeit(inst, args, result)
    local ty = args[3]
    if ty ~= TILE_GEMCORN and ty ~= TILE_TREE then return end
    if field_bool(F_generating) then return end
    if not M_ttx or not M_tty then return end
    local ok1, x = pcall(P.invoke, M_ttx)
    local ok2, y = pcall(P.invoke, M_tty)
    if not ok1 or not ok2 or type(x) ~= "number" or type(y) ~= "number" then return end
    pending[#pending + 1] = { x, y, ty }
    if #pending > 32 then table.remove(pending, 1) end
end

-- v1.0.3：读 Main.worldSurface（地表线）。y 大于它才算「地下」。
local function read_world_surface()
    if not F_world_surface then return nil end
    local ok, v = pcall(P.get_field_value, F_world_surface, nil, "double")
    if ok and type(v) == "number" then return v end
    return nil
end

-- 宝石果这一株能不能长：
--   开了「无视深度」→ 一律放行（表层也长）
--   关了「无视深度」→ 只有真的在地下才放行，表层保持小苗（跟原版一致）
local function gem_depth_ok(y)
    if S.depth then return true end
    local surf = read_world_surface()
    if type(surf) ~= "number" then return true end   -- 读不到就别把功能卡死，放行
    return y > surf
end

-- 去重：同坐标同类型只处理一次（PlaceTile 与 PlaceIt 可能都报一次）
local done, done_n = {}, 0
local function seen(x, y, ty)
    local k = tostring(x) .. "," .. tostring(y) .. "," .. tostring(ty)
    if done[k] then return true end
    done[k] = true
    done_n = done_n + 1
    if done_n > 200 then done, done_n = {}, 0 end
    return false
end

-- 每帧处理一次待长队列
local function flush_pending()
    if #pending == 0 then return end
    local list = pending
    pending = {}
    for i = 1, #list do
        local p = list[i]
        local ty = p[3]
        local want = (ty == TILE_GEMCORN) and S.gem or (ty == TILE_TREE) and S.oak
        if want and not seen(p[1], p[2], ty) then
            if ty == TILE_GEMCORN then
                -- 宝石果：无视深度开着、或确实在地表线以下才长（原版 case 590 要求 underground）
                if gem_depth_ok(p[2]) then
                    grow_sapling(p[1], p[2], true)
                end
            else
                -- 橡实：传 false，走原版普通树流程
                grow_sapling(p[1], p[2], false)
            end
        end
    end
end

-- ==================== 播报 ====================
local GREET_TEXT = "枝繁叶茂，不过几度春秋。"
local GREET_COLOR = { 130, 220, 140 }   -- 嫩绿
local GREET_DELAY = 60                  -- 进世界后 1 秒

local say_method
local function say(text)
    if not say_method then
        local ok, m = pcall(P.get_type, "Terraria", "Main")
        if not ok or not m then return false end
        local ok2, mm = pcall(P.get_method, m, "NewText", 5)
        if not ok2 or not mm then return false end
        say_method = mm
    end
    local s = text
    if P.string_create then
        local okc, r = pcall(P.string_create, text)
        if okc and r then s = r end
    end
    local ok, r = pcall(P.invoke, say_method, s,
        GREET_COLOR[1], GREET_COLOR[2], GREET_COLOR[3], false)
    return ok and r ~= false
end

local frame = 0
local world_frame0 = -1     -- 进世界的第一帧
local greeted = false

local function main_frame()
    frame = frame + 1
    flush_pending()                              -- v1.0.1：每帧先处理「刚种下」的队列
    if frame % 15 ~= 0 then return end          -- 每 15 帧查一次世界状态

    if not M_game_menu or not M_world_id then return end
    local ok1, gm = pcall(P.invoke, M_game_menu)
    local ok2, wid = pcall(P.invoke, M_world_id)
    if not ok1 or not ok2 then return end

    local now_in_world = (gm == false) and (type(wid) == "number") and wid > 0
    if not now_in_world then
        world_frame0 = -1
        greeted = false
        return
    end
    if world_frame0 < 0 then
        world_frame0 = frame
        return
    end
    if (not greeted) and (frame - world_frame0 >= GREET_DELAY) then
        if say(GREET_TEXT) then greeted = true end
    end
end

-- ==================== 生命周期 ====================
local function add_hook(method, spec, label)
    if not method then note("缺少方法: " .. label); return end
    local ok, h = pcall(P.install_hook, method, spec)
    if ok and h then
        hooks[#hooks + 1] = h
    else
        note("装钩子失败: " .. label .. " " .. tostring(h))
    end
end

function setup()
    load_cfg()

    local okw, T_WG = pcall(P.get_type, "Terraria", "WorldGen")
    if okw and T_WG then
        local ok1, v1 = pcall(P.get_method, T_WG, "AttemptToGrowTreeFromSapling", 5)
        if ok1 then M_attempt = v1 end
        local ok2, v2 = pcall(P.get_method, T_WG, "PlaceTile", 7)
        if ok2 then M_place = v2 end
        local ok3, v3 = pcall(P.get_field, T_WG, "generatingWorld")
        if ok3 then F_generating = v3 end
    else
        note("找不到 Terraria.WorldGen")
    end

    local okp, T_Player = pcall(P.get_type, "Terraria", "Player")
    if okp and T_Player then
        local ok1, v1 = pcall(P.get_method, T_Player, "PlaceThing_Tiles_PlaceIt", 3)
        if ok1 then M_placeit = v1 end
        local ok2, v2 = pcall(P.get_method, T_Player, "get_tileTargetX", 0)
        if ok2 then M_ttx = v2 end
        local ok3, v3 = pcall(P.get_method, T_Player, "get_tileTargetY", 0)
        if ok3 then M_tty = v3 end
    else
        note("找不到 Terraria.Player")
    end

    local okm, T_Main = pcall(P.get_type, "Terraria", "Main")
    if okm and T_Main then
        local ok1, v1 = pcall(P.get_method, T_Main, "Update", 1)
        if ok1 then M_main_update = v1 end
        local ok2, v2 = pcall(P.get_method, T_Main, "get_gameMenu", 0)
        if ok2 then M_game_menu = v2 end
        local ok3, v3 = pcall(P.get_method, T_Main, "get_worldID", 0)
        if ok3 then M_world_id = v3 end
        local ok4, v4 = pcall(P.get_field, T_Main, "worldSurface")
        if ok4 then F_world_surface = v4 end
    else
        note("找不到 Terraria.Main")
    end

    add_hook(M_attempt, { postfix = on_attempt, override_result = true }, "AttemptToGrowTreeFromSapling")
    add_hook(M_placeit, { postfix = on_placeit },                          "PlaceThing_Tiles_PlaceIt")
    add_hook(M_place,   { prefix = on_place_prefix },                      "PlaceTile")
    add_hook(M_main_update, { postfix = main_frame },                      "Main.Update")
    note("setup 完成")
end

function cleanup()
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
end

-- ==================== 开关面板 ====================
function mod.on_gui()
    local g = mod.gui
    if type(g) ~= "table" then return end

    if type(g.set_title) == "function" then
        pcall(g.set_title, "一日看尽三回长", "树")
    end

    local v
    v = g.checkbox("宝石果无视深度", S.depth)
    if v ~= S.depth then S.depth = v; save_cfg() end

    v = g.checkbox("宝石果立即长成", S.gem)
    if v ~= S.gem then S.gem = v; save_cfg() end

    v = g.checkbox("橡实立即长成", S.oak)
    if v ~= S.oak then S.oak = v; save_cfg() end
end

todo_list = { "setup" }
