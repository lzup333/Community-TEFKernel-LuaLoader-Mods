-- afm_bind.lua
-- 反射绑定与小工具：世界判断、玩家背包、箱子（Chest / ChestItem 结构体数组）、
-- 液体读取、物品实例创建。所有读数都是防御式的：拿不到就返回 nil，绝不抛错。
local U = require("afm_util")
local P = U.P

local M = {}
local C = {}
local SD

function M.setup(ctx)
    SD = ctx
    ctx.C = C
    M.C = C

    C.MainT    = U.try_type("Terraria", "Main")
    C.PlayerT  = U.try_type("Terraria", "Player")
    C.ItemT    = U.try_type("Terraria", "Item")
    C.WorldGen = U.try_type("Terraria", "WorldGen")
    C.ChestT   = U.try_type("Terraria", "Chest")
    C.TileData = U.try_type("Terraria", "TileData")

    if not (C.MainT and C.PlayerT and C.ItemT and C.WorldGen) then
        U.log_error("[AFM] 缺少核心 Terraria 类型")
        return false
    end

    -- Main
    C.f_playerArray  = U.find_field(C.MainT, "player")
    C.m_myPlayer     = U.prop_getter(C.MainT, "myPlayer")
    C.f_gameMenu     = U.find_field(C.MainT, "gameMenu")
    C.m_gameMenu     = U.prop_getter(C.MainT, "gameMenu")
    C.m_mouseX       = U.prop_getter(C.MainT, "mouseX")
    C.m_mouseY       = U.prop_getter(C.MainT, "mouseY")
    C.m_mouseLeft    = U.prop_getter(C.MainT, "mouseLeft")
    C.m_screenW      = U.prop_getter(C.MainT, "screenWidth")
    C.m_screenH      = U.prop_getter(C.MainT, "screenHeight")
    C.m_screenPos    = U.prop_getter(C.MainT, "screenPosition")
    C.f_screenPos    = U.find_field(C.MainT, "screenPosition")
    C.f_zoom         = U.find_field(C.MainT, "GameZoomTarget")
    C.f_maxTX        = U.find_field(C.MainT, "maxTilesX")
    C.f_maxTY        = U.find_field(C.MainT, "maxTilesY")
    C.f_worldSurface = U.find_field(C.MainT, "worldSurface")
    C.f_chest        = U.find_field(C.MainT, "chest")   -- Chest[] 静态字段
    C.f_statusText   = U.find_field(C.MainT, "statusText")
    C.m_newText5     = U.find_method(C.MainT, "NewText", 5)
    C.m_newText4     = U.find_method(C.MainT, "NewText", 4)
    C.f_rand         = U.find_field(C.MainT, "rand")    -- UnifiedRandom

    -- 随机数：优先用游戏自己的 rand，保证与世界种子风格一致
    local RandT = U.try_type("Terraria.Utilities", "UnifiedRandom")
    if RandT then
        C.m_randNext = U.find_method(RandT, "Next", 1) or U.find_method(RandT, "Next", 2)
    end

    -- Player
    C.f_inventory = U.find_field(C.PlayerT, "inventory")
    C.f_selected  = U.find_field(C.PlayerT, "selectedItem")
    C.m_selected  = U.prop_getter(C.PlayerT, "selectedItem")
    C.f_position  = U.find_field(C.PlayerT, "position")
    C.f_width     = U.find_field(C.PlayerT, "width")
    C.f_height    = U.find_field(C.PlayerT, "height")
    C.f_useItem   = U.find_field(C.PlayerT, "controlUseItem")
    C.f_useTile   = U.find_field(C.PlayerT, "controlUseTile")
    C.m_tileTargetX = U.prop_getter(C.PlayerT, "tileTargetX")
    C.m_tileTargetY = U.prop_getter(C.PlayerT, "tileTargetY")
    C.f_luck        = U.find_field(C.PlayerT, "luck")
    C.f_armor       = U.find_field(C.PlayerT, "armor")
    C.f_buffType    = U.find_field(C.PlayerT, "buffType")
    C.f_usedGummy   = U.find_field(C.PlayerT, "usedGummyWorm")

    -- 世界环境（渔力倍率用）
    C.f_raining     = U.find_field(C.MainT, "raining")
    C.f_cloud        = U.find_field(C.MainT, "cloudBGAlpha")
    C.f_dayTime     = U.find_field(C.MainT, "dayTime")
    C.f_time        = U.find_field(C.MainT, "time")
    C.f_moonPhase   = U.find_field(C.MainT, "moonPhase")
    C.f_bloodMoon   = U.find_field(C.MainT, "bloodMoon")

    -- Item
    C.f_type      = U.find_field(C.ItemT, "type")
    C.f_stack     = U.find_field(C.ItemT, "stack")
    C.f_value     = U.find_field(C.ItemT, "value")
    C.f_fishPole  = U.find_field(C.ItemT, "fishingPole")
    C.f_bait      = U.find_field(C.ItemT, "bait")
    C.m_setDef    = U.find_method(C.ItemT, "SetDefaults", 1) or U.find_method(C.ItemT, "SetDefaults", 2)

    -- Chest
    if C.ChestT then
        C.f_chestItem  = U.find_field(C.ChestT, "item")     -- ChestItem[]
        C.f_chestX     = U.find_field(C.ChestT, "x")
        C.f_chestY     = U.find_field(C.ChestT, "y")
        C.f_chestMax   = U.find_field(C.ChestT, "maxItems")
        C.f_mainItem   = U.find_field(C.MainT, "item")       -- Item[] 掉落物数组
        C.f_maxItems   = U.find_field(C.MainT, "maxItems")
        C.f_itemActive = U.find_field(C.ItemT, "active")
        C.f_chestName  = U.find_field(C.ChestT, "name")     -- 箱子名字（string）
    end

    -- WorldGen.PlaceChest(int x, int y, ushort type, bool notNearOtherChests, int style)
    C.m_placeChest = U.find_method(C.WorldGen, "PlaceChest", 5)

    -- TileData：静态方法 GetType / GetLiquid / GetWall（index = x + maxTilesX * y）
    if C.TileData then
        C.m_getTileType = U.find_method(C.TileData, "GetType", 1)
        C.m_getLiquid   = U.find_method(C.TileData, "GetLiquid", 1)
        C.m_getWallType = U.find_method(C.TileData, "GetWall", 1)
    end

    local missing = {}
    local function need(n, v) if not v then missing[#missing + 1] = n end end
    need("Main.player", C.f_playerArray)
    need("Main.myPlayer", C.m_myPlayer)
    need("Main.chest", C.f_chest)
    need("Player.inventory", C.f_inventory)
    need("Item.type", C.f_type)
    need("Chest.item", C.f_chestItem)
    need("WorldGen.PlaceChest", C.m_placeChest)
    if #missing > 0 then
        U.log_error("[AFM] 绑定缺失: " .. table.concat(missing, ","))
    else
        U.log_info("[AFM] 绑定完成")
    end
    return #missing == 0
end

-- ==================== 世界 / 玩家 ====================
function M.world()
    if C.m_gameMenu then
        local v = U.call_bool(C.m_gameMenu, nil)
        if v ~= nil then return v == false end
    end
    if C.f_gameMenu then return not U.gf_bool(C.f_gameMenu, nil) end
    return false
end

-- v2.0.7：本地玩家句柄缓存。原来每帧都要 invoke(MyPlayer) + 读数组 + 取元素 =
--   4 次跨语言调用，一秒 240 次。玩家句柄在同一世界里是稳定的，缓存 60 帧即可，
--   切世界时由 main.lua 调 invalidate_player 主动作废。
-- v2.1.4：Main.maxTilesX / maxTilesY 是世界常量，但原来每查一格液面都要
--   反射读一次 maxTilesX（tile_index 里），tile_ok/atmo 也各读一次。
--   整局缓存下来，切世界时由 invalidate_player 一并作废。
local tile_mx, tile_my = 0, 0
local lp_cache, lp_age = nil, 0
function M.invalidate_player()
    lp_cache, lp_age = nil, 0
    tile_mx, tile_my = 0, 0
end
function M.local_player()
    if lp_cache and lp_age < 60 then
        lp_age = lp_age + 1
        return lp_cache
    end
    if not (C.f_playerArray and C.m_myPlayer) then return nil end
    local idx = U.call_int(C.m_myPlayer, nil)
    if not idx or idx < 0 or idx > 255 then return nil end
    local ok, arr = pcall(P.get_field_value, C.f_playerArray, nil, "object")
    if not ok or not arr then return nil end
    local ok2, p = pcall(P.array_at, arr, idx)
    if ok2 and p then
        lp_cache, lp_age = p, 1
        return p
    end
    return nil
end

function M.inventory(player)
    if not (C.f_inventory and player) then return nil end
    local ok, arr = pcall(P.get_field_value, C.f_inventory, player, "object")
    if ok and arr then return arr end
    return nil
end

function M.item_at(arr, i)
    if not arr or type(i) ~= "number" or i < 0 then return nil end
    local ok, it = pcall(P.array_at, arr, i)
    if ok and it then return it end
    return nil
end

function M.selected(player)
    if not player then return -1 end
    if C.m_selected then
        local v = U.call_int(C.m_selected, player)
        if v then return v end
    end
    if C.f_selected then return U.gf_int(C.f_selected, player) end
    return -1
end

function M.item_type(item)
    if not item then return 0 end
    return U.gf_int(C.f_type, item)
end

function M.item_stack(item)
    if not item then return 0 end
    return U.gf_int(C.f_stack, item)
end

function M.set_stack(item, n)
    if not (item and C.f_stack) then return false end
    return pcall(P.set_field_value, C.f_stack, item, n, "int16")
end

function M.item_pole(item)
    if not (item and C.f_fishPole) then return 0 end
    local v = U.gf_int(C.f_fishPole, item)
    if type(v) == "number" and v > 0 then return v end
    return 0
end

function M.item_bait(item)
    if not (item and C.f_bait) then return 0 end
    local v = U.gf_int(C.f_bait, item)
    if type(v) == "number" and v > 0 then return v end
    return 0
end

function M.item_value(item)
    if not (item and C.f_value) then return 0 end
    return U.gf_int(C.f_value, item)
end

-- 手持物品是否为本模组的机器（靠 Item.value 稳定标记）
function M.holding_machine(player)
    if not player then return false end
    local inv = M.inventory(player)
    local it = M.item_at(inv, M.selected(player))
    if not it then return false end
    local t = M.item_type(it)
    local id = SD and SD.S and SD.S.item_id or -1
    if type(id) == "number" and id > 0 and t == id then return true end
    local mark = SD and SD.S and SD.S.mark or 0
    if mark > 0 and C.f_value and M.item_value(it) == mark then return true end
    return false
end

-- 消耗手持 1 个
function M.consume_held(player)
    local inv = M.inventory(player)
    local it = M.item_at(inv, M.selected(player))
    if not it then return false end
    local n = M.item_stack(it)
    if n <= 1 then
        return M.set_stack(it, 0)
    end
    return M.set_stack(it, n - 1)
end

-- ==================== 图格 / 液体 ====================
function M.world_bounds()
    if tile_mx <= 0 then
        tile_mx = C.f_maxTX and U.gf_int(C.f_maxTX, nil) or 0
    end
    if tile_my <= 0 then
        tile_my = C.f_maxTY and U.gf_int(C.f_maxTY, nil) or 0
    end
    local mx, my = tile_mx, tile_my
    if mx <= 0 then mx = 8400 end
    if my <= 0 then my = 2400 end
    return mx, my
end

local function tile_index(x, y)
    local mx = tile_mx
    if mx <= 0 then
        mx = C.f_maxTX and U.gf_int(C.f_maxTX, nil) or 0
        if mx > 0 then tile_mx = mx end
    end
    if mx <= 0 then return nil end
    return x + mx * y
end

function M.tile_type(x, y)
    if not C.m_getTileType then return nil end
    local i = tile_index(x, y)
    if not i then return nil end
    local ok, v = pcall(P.invoke, C.m_getTileType, i)
    if ok and type(v) == "number" then return v end
    return nil
end

-- 液体量 0..255（0 = 无水）
function M.liquid(x, y)
    if not C.m_getLiquid then return nil end
    local i = tile_index(x, y)
    if not i then return nil end
    local ok, v = pcall(P.invoke, C.m_getLiquid, i)
    if ok and type(v) == "number" then return v end
    return nil
end

-- 在 (cx, cy) 半径 r 内统计「水格」数量（液体量 >= 32 算一格）
-- 水域格数：口径对齐原版 —— 以某点为中心 (2r+1)×(2r+1) 的方框里，
--   liquid > 0 的格子数量（原版 Projectile.FishingCheck 就是这么数的）。
-- v1.0.4 两处修正：
--   ① 原来以「钓鱼机所在格」为中心，而机器通常放在岸上/水面上方，
--      方框有一半是空气 —— 明明 396 格水只数出 90 格。
--      现在先往下找水面（最多 20 格），再以水面下 2 格为中心数。
--   ② 阈值 32 -> 0：原版只要 liquid > 0 就算水，浅水/半格水也算。
-- v1.0.6：改成「以钓鱼机为圆心、半径 r 的圆」统计水域格数。
--   判定用 dx² + dy² <= r²，只对圆内格子做液面查询（圆外不算，也不查）。
-- v2.1.4：按行统计「钓鱼机下方半圆」里的水格数，供分帧扫描用。
--   钓鱼机永远放在水面之上，上半圆只会是空气，所以只查 dy >= 0（含水平线）。
--   dy 是相对行号（0 = 与机器同一行），返回这一行圆内 liquid > 0 的格数。
function M.water_rows_down(cx, cy, r, dy)
    if not C.m_getLiquid then return 0 end
    if dy < 0 or dy > r then return 0 end
    local rem = r * r - dy * dy
    if rem < 0 then return 0 end
    local maxdx = math.floor(math.sqrt(rem))
    local n = 0
    for dx = -maxdx, maxdx do
        local v = M.liquid(cx + dx, cy + dy)
        if type(v) == "number" and v > 0 then n = n + 1 end
    end
    return n
end
-- v2.1.7：按笔记 60.3 重写。原版 Main.item[] 里装的是 WorldItem（Entity 子类），
--   不是 Item。把 WorldItem 当 Item 读 type/position 一律读到 nil，
--   这就是 v1.8.1~v1.8.6 六版「清理逻辑看起来对、实测一件没删」的根因。
--   正确读法：inner = WorldItem.inner（Item 本体），type/position 从 inner 读；
--   清除用 WorldItem.TurnToAir（优先 TurnToAirAndSync）。
local WI = { tried = false }
local function wi_binds()
    if WI.tried then return WI end
    WI.tried = true
    local T = U.try_type("Terraria", "WorldItem")
    local E = U.try_type("Terraria", "Entity")
    if T then
        WI.f_inner = U.find_field(T, "inner")
    end
    WI.f_active = (T and U.find_field(T, "active")) or (E and U.find_field(E, "active"))
    WI.f_pos = (T and U.find_field(T, "position")) or (E and U.find_field(E, "position"))
    if T then
        for _, n in ipairs({ "TurnToAirAndSync", "TurnToAir" }) do
            for _, argc in ipairs({ 1, 0 }) do
                local mm = U.find_method(T, n, argc)
                if mm then
                    WI.m_turn = mm
                    break
                end
            end
            if WI.m_turn then break end
        end
    end
    return WI
end
function M.clear_drops_near(tx, ty, itype, r)
    if type(tx) ~= "number" or type(ty) ~= "number" then return 0 end
    if not C.f_mainItem then return 0 end
    local ok, arr = pcall(P.get_field_value, C.f_mainItem, nil, "object")
    if not ok or not arr then return 0 end
    local n = 400
    if C.f_maxItems then
        local ok2, v = pcall(P.get_field_value, C.f_maxItems, nil, "int32")
        if ok2 and type(v) == "number" and v > 0 and v <= 1200 then n = v end
    end
    local W = wi_binds()
    r = r or 3
    local cleared = 0
    for i = 0, n - 1 do
        local ok3, wi = pcall(P.array_at, arr, i)
        if ok3 and wi then
            local act = W.f_active and U.gf_bool(W.f_active, wi)
            if (not W.f_active) or act == true then
                local inner = wi
                if W.f_inner then
                    local ok4, got = pcall(P.get_field_value, W.f_inner, wi, "object")
                    if ok4 and got then inner = got end
                end
                local t = C.f_type and U.gf_int(C.f_type, inner)
                if t == itype then
                    local px, py = U.read_vec2_field(W.f_pos, inner)
                    if type(px) ~= "number" and C.f_position then
                        px, py = U.read_vec2_field(C.f_position, inner)
                    end
                    if type(px) == "number" and type(py) == "number" then
                        local cx = math.floor((px + 8) / 16)
                        local cy = math.floor((py + 8) / 16)
                        if math.abs(cx - tx) <= r and math.abs(cy - ty) <= r then
                            local done = false
                            if W.m_turn then
                                done = pcall(P.invoke, W.m_turn, wi)
                            end
                            if not done and C.f_itemActive then
                                pcall(P.set_field_value, C.f_itemActive, wi, false, "bool")
                                done = true
                            end
                            if done then cleared = cleared + 1 end
                        end
                    end
                end
            end
        end
    end
    return cleared
end
local function item_template(itype)
    local ok, inst = pcall(P.create_instance, C.ItemT)
    if not ok or not inst then return nil end
    if C.m_setDef then
        if not pcall(P.invoke, C.m_setDef, inst, itype) then
            pcall(P.invoke, C.m_setDef, inst, itype, nil)
        end
    end
    return inst
end
M.item_template = item_template

-- ContentSamples.ItemsByType：Dictionary<int, Item>，里面全是已 SetDefaults 好的模板，
-- 直接读字段即可（只读，不写）。这是最稳的一条路。
local CS_T = nil
local F_itemsByType = nil

local function items_by_type()
    if CS_T == nil then
        CS_T = U.try_type("Terraria.ID", "ContentSamples") or false
    end
    if CS_T == false then return nil end
    if not F_itemsByType then
        F_itemsByType = U.find_field(CS_T, "ItemsByType")
    end
    if not F_itemsByType then return nil end
    local ok, dict = pcall(P.get_field_value, F_itemsByType, nil, "object")
    if ok and dict then return dict end
    return nil
end

-- 查一个物品 ID 的渔力与鱼饵力（0,0 = 既不是竿也不是饵）
function M.probe_item(itype)
    local cache = SD and SD.S and SD.S.probe
    if cache then
        local hit = cache[itype]
        if hit then return hit[1], hit[2] end
    end

    local pole, bait = 0, 0

    -- ① ContentSamples 模板
    local dict = items_by_type()
    if dict and type(P.dictionary_get_value) == "function" then
        local ok, tmpl = pcall(P.dictionary_get_value, dict, itype, "int32", "object")
        if ok and tmpl then
            pole = M.item_pole(tmpl)
            bait = M.item_bait(tmpl)
        end
    end

    -- ② 退路：现场造一个 Item 再 SetDefaults
    if pole == 0 and bait == 0 then
        local inst = item_template(itype)
        if inst then
            pole = M.item_pole(inst)
            bait = M.item_bait(inst)
        end
    end

    -- 只有真查到东西才缓存，避免把一次失败永久记住
    if cache and (pole > 0 or bait > 0) then
        cache[itype] = { pole, bait }
    end
    return pole, bait
end

-- ==================== 屏幕 / 瞄准 ====================
function M.screen_size()
    local sw = C.m_screenW and U.call_int(C.m_screenW, nil) or 0
    local sh = C.m_screenH and U.call_int(C.m_screenH, nil) or 0
    return sw, sh
end

function M.zoom()
    local z = C.f_zoom and U.gf_float(C.f_zoom, nil) or 0
    if z < 0.5 or z > 4.0 then z = 1.0 end
    return z
end

function M.player_pos(player)
    if not (player and C.f_position) then return nil end
    return U.read_vec2_field(C.f_position, player)
end

function M.screen_pos(player)
    if C.f_screenPos then
        local x, y = U.read_vec2_field(C.f_screenPos, nil)
        if type(x) == "number" and type(y) == "number" then return x, y end
    end
    if C.m_screenPos then
        local x, y = U.read_vec2_getter(C.m_screenPos, nil)
        if type(x) == "number" and type(y) == "number" then return x, y end
    end
    local px, py = M.player_pos(player)
    if px then
        local sw, sh = M.screen_size()
        local z = M.zoom()
        local w = C.f_width and U.gf_int(C.f_width, player) or 20
        local h = C.f_height and U.gf_int(C.f_height, player) or 42
        return px + w / 2 - sw / (2 * z), py + h / 2 - sh / (2 * z)
    end
    return nil
end

function M.tile_ok(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return false end
    local mx, my = M.world_bounds()
    return x >= 0 and y >= 0 and x < mx and y < my
end

function M.aim(player)
    local tx = C.m_tileTargetX and U.call_int(C.m_tileTargetX, nil)
    local ty = C.m_tileTargetY and U.call_int(C.m_tileTargetY, nil)
    if tx and ty and M.tile_ok(tx, ty) and not (tx == 0 and ty == 0) then
        return tx, ty
    end
    local px, py = M.player_pos(player)
    if px then
        local w = C.f_width and U.gf_int(C.f_width, player) or 20
        local h = C.f_height and U.gf_int(C.f_height, player) or 42
        local x = math.floor((px + w / 2) / 16)
        local y = math.floor((py + h) / 16)
        return x, y
    end
    return nil, nil
end

function M.use_state(player)
    if not player then return false end
    local left = (C.f_useItem and U.gf_bool(C.f_useItem, player)) or false
    if not left and C.m_mouseLeft then left = U.call_bool(C.m_mouseLeft, nil) == true end
    return left
end

-- ==================== 放置箱子 ====================
-- 返回 chest index（成功）或 nil
function M.place_chest(x, y)
    if not C.m_placeChest then return nil, "缺少 PlaceChest" end
    local ok, ret = pcall(P.invoke, C.m_placeChest, x, y, 21, false, 0)
    if not ok then
        -- 参数编组失败时换一套写法再试一次
        ok, ret = pcall(P.invoke, C.m_placeChest, x, y, 21, true, 0)
    end
    if ok and type(ret) == "number" and ret >= 0 then return ret end
    return nil, "PlaceChest 返回 " .. tostring(ret)
end

-- ==================== 播报 ====================
function M.notify(text, r, g, b)
    local str = tostring(text or "")
    if str == "" then return false end
    r, g, b = r or 255, g or 235, b or 160
    local s = nil
    if type(P.string_create) == "function" then
        local okc, h = pcall(P.string_create, str)
        if okc then s = h end
    end
    if not s then return false end
    if C.m_newText5 then
        local ok, ret = pcall(P.invoke, C.m_newText5, s, r, g, b, false)
        if ok and ret ~= false then return true end
    end
    if C.m_newText4 then
        local ok, ret = pcall(P.invoke, C.m_newText4, s, r, g, b)
        if ok and ret ~= false then return true end
    end
    return false
end

-- 1..n 的随机整数（优先用游戏 rand）
function M.rand(max)
    if type(max) ~= "number" or max < 1 then return 1 end
    max = math.floor(max)
    if C.m_randNext then
        local ok, arr = pcall(P.get_field_value, C.f_rand, nil, "object")
        local rnd = nil
        if ok and arr then rnd = arr end
        if rnd then
            local ok2, v = pcall(P.invoke, C.m_randNext, rnd, max)
            if ok2 and type(v) == "number" then return v + 1 end
        end
    end
    return math.random(1, max)
end

-- 0..n-1（对应 Main.rand.Next(n)）
function M.rand0(max)
    if type(max) ~= "number" or max <= 1 then return 0 end
    return M.rand(max) - 1
end

-- 0..1 的浮点（近似 Main.rand.NextFloat()）
function M.rand0f()
    return (M.rand(1000000) - 1) / 1000000
end

-- 世界表面高度（Main.worldSurface，double）
function M.world_surface()
    local f = C.f_worldSurface
    if not f then return nil end
    if type(P.get_field_raw) == "function" then
        local ok, raw = pcall(P.get_field_raw, f, nil)
        if ok and type(raw) == "string" then
            if #raw == 8 then
                local okd, v = pcall(string.unpack, "<d", raw)
                if okd and type(v) == "number" and v > 0 and v < 1000000 then return v end
            elseif #raw == 4 then
                local okf, v = pcall(string.unpack, "<f", raw)
                if okf and type(v) == "number" and v > 0 and v < 1000000 then return v end
            end
        end
    end
    return nil
end

-- 大气因子（原版 Projectile.FishingCheck 的 atmo）：
--   num  = (maxTilesX / 4200)^2
--   atmo = (y - (60 + 10*num)) / (worldSurface / 6)，夹在 0.25..1
function M.atmo(y)
    local mx, my = M.world_bounds()
    local num = mx / 4200
    num = num * num
    local cst = 60 + 10 * num
    local ws = M.world_surface()
    if not ws or ws < 100 then ws = my * 0.35 end
    local a = (y - cst) / (ws / 6.0)
    if a < 0.25 then a = 0.25 end
    if a > 1 then a = 1 end
    return a
end

-- 玩家幸运值（Player.luck，float）
function M.player_luck(player)
    local f = C.f_luck
    if not (f and player) then return 0 end
    local v = U.gf_float(f, player)
    if type(v) == "number" and v == v then return v end
    return 0
end

-- ==================== 背包写入 ====================
-- 用一个模板克隆出可放进背包的 Item 实例
local function clone_item(itype)
    local dict = items_by_type()
    local tmpl = nil
    if dict and type(P.dictionary_get_value) == "function" then
        local ok, v = pcall(P.dictionary_get_value, dict, itype, "int32", "object")
        if ok then tmpl = v end
    end
    if not C.m_clone then
        C.m_clone = U.find_method(C.ItemT, "Clone", 0)
    end
    if tmpl and C.m_clone then
        local ok2, c = pcall(P.invoke, C.m_clone, tmpl)
        if ok2 and c then return c end
    end
    local inst = item_template(itype)
    if inst then return inst end
    return nil
end
M.clone_item = clone_item

-- 往玩家背包加物品，返回实际加进去的数量
function M.inv_add(player, itype, count)
    local arr = M.inventory(player)
    if not arr or type(itype) ~= "number" or itype <= 0 or count <= 0 then return 0 end
    local added = 0
    -- ① 叠到同类
    for i = 0, 58 do
        local it = M.item_at(arr, i)
        if it and M.item_type(it) == itype then
            local s = M.item_stack(it)
            if s > 0 and s < 999 then
                local add = math.min(999 - s, count - added)
                if add > 0 and M.set_stack(it, s + add) then
                    added = added + add
                    if added >= count then return added end
                end
            end
        end
    end
    -- ② 找空槽
    for i = 0, 58 do
        local it = M.item_at(arr, i)
        if it then
            local t = M.item_type(it)
            local s = M.item_stack(it)
            if t == 0 or s <= 0 then
                local copy = clone_item(itype)
                if copy then
                    local add = math.min(999, count - added)
                    if M.set_stack(copy, add) then
                        local ok = pcall(P.array_set, arr, i, copy, "object")
                        if ok then
                            added = added + add
                            if added >= count then return added end
                        end
                    end
                end
            end
        end
    end
    return added
end

-- 玩家所在图格
function M.player_tile(player)
    local px, py = M.player_pos(player)
    if not px then return nil end
    local w = C.f_width and U.gf_int(C.f_width, player) or 20
    local h = C.f_height and U.gf_int(C.f_height, player) or 42
    return math.floor((px + w / 2) / 16), math.floor((py + h / 2) / 16)
end
-- Main.time 是 double，单独读
function M.gf_double(field)
    if not field then return nil end
    if type(P.get_field_raw) == "function" then
        local ok, raw = pcall(P.get_field_raw, field, nil)
        if ok and type(raw) == "string" and #raw == 8 then
            local okd, v = pcall(string.unpack, "<d", raw)
            if okd and type(v) == "number" then return v end
        end
    end
    return nil
end

-- 渔力倍率需要的环境
function M.world_env()
    local e = {}
    e.raining = (C.f_raining and U.gf_bool(C.f_raining, nil)) or false
    e.cloud   = (C.f_cloud and U.gf_float(C.f_cloud, nil)) or 0
    e.day     = (C.f_dayTime and U.gf_bool(C.f_dayTime, nil))
    if e.day == nil then e.day = true end
    e.time    = M.gf_double(C.f_time) or 0
    e.moon    = (C.f_moonPhase and U.gf_int(C.f_moonPhase, nil)) or 0
    e.blood   = (C.f_bloodMoon and U.gf_bool(C.f_bloodMoon, nil)) or false
    return e
end

-- ==================== 玩家渔具加成（原版 fishingSkill）====================
-- 原版 Player.GetFishingConditions：
--   渔力 = 竿渔力 + 饵渔力 + fishingSkill + 额外
-- 这里的 fishingSkill 来自渔夫套、钓鱼饰品、钓鱼药水、软糖蠕虫。
local ARMOR_BONUS = {
    [2367] = 5, [2368] = 5, [2369] = 5,     -- 渔夫帽 / 背心 / 裤
    [5591] = 5, [5592] = 5, [5593] = 5,     -- 同上的另一组 ID
    [2374] = 10,                            -- 渔夫耳环
    [3721] = 10,                            -- 渔夫工具包
    [5064] = 10,                            -- 岩浆钓具袋
}
local GEAR_NAME = {
    [2367] = "渔夫帽", [2368] = "渔夫背心", [2369] = "渔夫裤",
    [5591] = "渔夫帽", [5592] = "渔夫背心", [5593] = "渔夫裤",
    [2374] = "渔夫耳环", [3721] = "渔夫工具包", [5064] = "岩浆钓具袋",
}

-- 返回：加成点数, 明细文本
function M.gear_bonus(player)
    if not player then return 0, "" end
    local bonus = 0
    local names = {}
    local seen = {}

    local arr
    if C.f_armor then
        local ok, a = pcall(P.get_field_value, C.f_armor, player, "object")
        if ok then arr = a end
    end
    if arr then
        for i = 0, 19 do
            local it = M.item_at(arr, i)
            local t = it and M.item_type(it) or 0
            local plus = ARMOR_BONUS[t]
            if plus and not seen[t] then
                seen[t] = true
                bonus = bonus + plus
                names[#names + 1] = string.format("%s+%d", GEAR_NAME[t] or ("物品" .. t), plus)
            end
        end
    end

    -- 钓鱼药水：buff 121 → +15
    local barr
    if C.f_buffType then
        local ok, bb = pcall(P.get_field_value, C.f_buffType, player, "object")
        if ok then barr = bb end
    end
    if barr then
        for i = 0, 30 do
            local t
            local ok1, v1 = pcall(P.array_at, barr, i, "int16")
            if ok1 and type(v1) == "number" then
                t = v1
            else
                local ok2, v2 = pcall(P.array_at, barr, i, "int32")
                if ok2 and type(v2) == "number" then t = v2 end
            end
            if t == 121 then
                bonus = bonus + 15
                names[#names + 1] = "钓鱼药水+15"
                break
            end
        end
    end

    if C.f_usedGummy and U.gf_bool(C.f_usedGummy, player) then
        bonus = bonus + 3
        names[#names + 1] = "软糖蠕虫+3"
    end

    return bonus, table.concat(names, " ")
end

return M
