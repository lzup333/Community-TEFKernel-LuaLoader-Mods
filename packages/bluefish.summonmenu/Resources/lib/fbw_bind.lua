-- sd_bind.lua
-- Reflection binding + small read helpers. setup() only resolves handles; no
-- game object is touched here, so this is safe to run before a world exists.

local U = require("fbw_util")
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

    if not (C.MainT and C.PlayerT and C.ItemT and C.WorldGen) then
        U.log_error("[FBW] missing core Terraria types")
        return false
    end

    -- Main: the current build exposes most of these as static properties.
    C.f_playerArray    = U.find_field(C.MainT, "player")
    C.m_myPlayer       = U.prop_getter(C.MainT, "myPlayer")
    C.f_gameMenu       = U.find_field(C.MainT, "gameMenu")
    C.m_gameMenu       = U.prop_getter(C.MainT, "gameMenu")
    C.m_mouseX         = U.prop_getter(C.MainT, "mouseX")
    C.m_mouseY         = U.prop_getter(C.MainT, "mouseY")
    C.m_mouseLeft      = U.prop_getter(C.MainT, "mouseLeft")
    C.m_mouseRight     = U.prop_getter(C.MainT, "mouseRight")
    C.m_playerInventory = U.prop_getter(C.MainT, "playerInventory")
    C.m_screenW        = U.prop_getter(C.MainT, "screenWidth")
    C.m_screenH        = U.prop_getter(C.MainT, "screenHeight")
    C.m_screenPos      = U.prop_getter(C.MainT, "screenPosition")
    C.f_screenPos      = U.find_field(C.MainT, "screenPosition")
    C.m_mouseWorld     = U.prop_getter(C.MainT, "MouseWorld")
    C.f_zoom           = U.find_field(C.MainT, "GameZoomTarget")
    C.f_maxTX          = U.find_field(C.MainT, "maxTilesX")
    C.f_maxTY          = U.find_field(C.MainT, "maxTilesY")
    C.f_hardMode       = U.find_field(C.MainT, "hardMode")   -- 困难模式（击败肉山后）

    -- Player
    C.f_inventory      = U.find_field(C.PlayerT, "inventory")
    C.f_selected       = U.find_field(C.PlayerT, "selectedItem")
    C.m_selected       = U.prop_getter(C.PlayerT, "selectedItem")
    C.f_direction      = U.find_field(C.PlayerT, "direction")
    C.f_position       = U.find_field(C.PlayerT, "position")
    C.f_width          = U.find_field(C.PlayerT, "width")
    C.f_height         = U.find_field(C.PlayerT, "height")
    C.f_useItem        = U.find_field(C.PlayerT, "controlUseItem")
    C.f_useTile        = U.find_field(C.PlayerT, "controlUseTile")
    C.m_tileTargetX    = U.prop_getter(C.PlayerT, "tileTargetX")
    C.m_tileTargetY    = U.prop_getter(C.PlayerT, "tileTargetY")
    -- 原版判定：当前工具（instance 的 inventory[selectedItem]）挖得动这格吗
    C.m_hasPickPower   = U.find_method(C.PlayerT, "HasEnoughPickPowerToHurtTile", 2)

    -- Item
    C.f_type           = U.find_field(C.ItemT, "type")
    C.f_stack          = U.find_field(C.ItemT, "stack")
    C.f_value          = U.find_field(C.ItemT, "value")
    -- 工具能力：镐（挖方块）/ 锤（砸恶魔祭坛）
    C.f_pick           = U.find_field(C.ItemT, "pick")
    C.f_hammer         = U.find_field(C.ItemT, "hammer")
    C.m_itemName       = U.prop_getter(C.ItemT, "Name")
    C.f_itemName       = U.find_field(C.ItemT, "Name")

    -- 聊天栏播报
    C.m_newText5       = U.find_method(C.MainT, "NewText", 5)
    C.m_newText4       = U.find_method(C.MainT, "NewText", 4)
    -- 屏幕中央状态文字：直接写字段，不调方法、不用结构体，最可靠
    C.f_statusText     = U.find_field(C.MainT, "statusText")


    -- WorldGen
    C.m_killTile       = U.find_method(C.WorldGen, "KillTile", 5)
    C.m_killWall       = U.find_method(C.WorldGen, "KillWall", 3)
    C.m_canKillTile    = U.find_method(C.WorldGen, "CanKillTile", 2)

    -- TileData：index = x + maxTilesX * y，GetType 返回图格类型（0 = 空气）
    C.TileDataT        = U.try_type("Terraria", "TileData")
    if C.TileDataT then
        C.m_getTileType = U.find_method(C.TileDataT, "GetType", 1)
        C.m_getWallType = U.find_method(C.TileDataT, "GetWall", 1)
    end

    -- 骷髅王击败标志：地牢墙的门槛
    C.NPCT             = U.try_type("Terraria", "NPC")
    if C.NPCT then
        C.f_downedBoss3 = U.find_field(C.NPCT, "downedBoss3")
    end

    local missing = {}
    local function need(name, v) if not v then missing[#missing + 1] = name end end
    need("Main.player", C.f_playerArray)
    need("Main.myPlayer", C.m_myPlayer)
    need("Player.inventory", C.f_inventory)
    need("Player.selectedItem", C.m_selected or C.f_selected)
    need("Item.type", C.f_type)
    need("WorldGen.KillTile", C.m_killTile)
    if #missing > 0 then
        U.log_error("[FBW] bind miss: " .. table.concat(missing, ","))
    else
        U.log_info("[FBW] bind ok")
    end


    C.ok = C.f_playerArray and C.m_myPlayer and C.f_inventory and C.f_type
        and (C.m_selected or C.f_selected) and C.m_killTile
    return C.ok and true or false
end

function M.update_method()
    local m = U.find_method(C.MainT, "Update", 1) or U.find_method(C.MainT, "Update", 0)
    if m then return m, "Main.Update" end
    local r = U.find_method(C.PlayerT, "ResetEffects", 0)
    if r then return r, "Player.ResetEffects" end
    return nil, nil
end

function M.world()
    if C.m_gameMenu then
        local v = U.call_bool(C.m_gameMenu, nil)
        if v ~= nil then return v == false end
    end
    if C.f_gameMenu then
        return not U.gf_bool(C.f_gameMenu, nil)
    end
    return false
end

function M.local_player()
    if not C.f_playerArray or not C.m_myPlayer then return nil end
    local idx = U.call_int(C.m_myPlayer, nil)
    if not idx or idx < 0 or idx > 255 then return nil end
    local ok, arr = pcall(P.get_field_value, C.f_playerArray, nil, "object")
    if not ok or not arr then return nil end
    local ok2, p = pcall(P.array_at, arr, idx)
    if ok2 and p then return p end
    return nil
end

function M.inventory(player)
    if not C.f_inventory or not player then return nil end
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
    return U.gf_int(C.f_type, item)
end

-- ==================== 工具能力（镐 / 锤） ====================
-- 三项能力都是 Item 上的 int 字段；读不到一律当 0
local function tool_power(field, item)
    if not (field and item) then return 0 end
    local v = U.gf_int(field, item)
    if type(v) == "number" and v > 0 then return v end
    return 0
end

-- 扫描背包 0..58，返回最高镐力 / 最高锤力
-- 树一律允许拆，不检查任何工具
function M.best_tools(player)
    local arr = M.inventory(player)
    if not arr then return 0, 0 end
    local bp, bh = 0, 0
    for i = 0, 58 do
        local it = M.item_at(arr, i)
        if it then
            local pv = tool_power(C.f_pick, it)
            local hv = tool_power(C.f_hammer, it)
            if pv > bp then bp = pv end
            if hv > bh then bh = hv end
        end
    end
    return bp, bh
end

-- 图格类型（0 = 空气）；读不到返回 nil
function M.tile_type(x, y)
    if not (C.m_getTileType and C.f_maxTX) then return nil end
    local mx = U.gf_int(C.f_maxTX, nil)
    if type(mx) ~= "number" or mx <= 0 then return nil end
    local ok, v = pcall(P.invoke, C.m_getTileType, x + mx * y)
    if ok and type(v) == "number" then return v end
    return nil
end

-- 墙类型（0 = 无墙）；读不到返回 nil
function M.wall_type(x, y)
    if not (C.m_getWallType and C.f_maxTX) then return nil end
    local mx = U.gf_int(C.f_maxTX, nil)
    if type(mx) ~= "number" or mx <= 0 then return nil end
    local ok, v = pcall(P.invoke, C.m_getWallType, x + mx * y)
    if ok and type(v) == "number" then return v end
    return nil
end

-- 地牢墙（不安全版，本来就可挖）：击败骷髅王前不许拆
--   7 / 8 / 9       蓝 / 绿 / 粉地牢砖墙
--   94 / 96 / 98    板砖墙
--   95 / 97 / 99    花砖墙
local DUNGEON_WALLS = {
    [7] = true, [8] = true, [9] = true,
    [94] = true, [95] = true, [96] = true,
    [97] = true, [98] = true, [99] = true,
}

function M.is_dungeon_wall(w)
    return DUNGEON_WALLS[w] == true
end

-- 是否击败过骷髅王（NPC.downedBoss3）；读不到返回 nil
function M.downed_boss3()
    if not C.f_downedBoss3 then return nil end
    local v = U.gf_bool(C.f_downedBoss3, nil)
    if type(v) == "boolean" then return v end
    return nil
end

-- 是否困难模式（击败肉山）；读不到返回 nil
function M.hard_mode()
    if not C.f_hardMode then return nil end
    local v = U.gf_bool(C.f_hardMode, nil)
    if type(v) == "boolean" then return v end
    return nil
end

-- 用「背包里最好的镐力」代替手持，问原版这格挖不挖得动。
-- 做法：把当前手持物品的 pick 字段临时改成 best_pick，调 HasEnoughPickPowerToHurtTile，
--       立刻改回原值（同一帧内完成，玩家看不到）。
-- 返回 true / false / nil（nil = 判不了，调用方应当放行，避免功能变砖）
function M.can_mine_with(player, x, y, best_pick)
    if not (C.m_hasPickPower and C.f_pick and player) then return nil end
    if type(best_pick) ~= "number" then return nil end
    local arr = M.inventory(player)
    if not arr then return nil end
    local it = M.item_at(arr, M.selected(player))
    if not it then return nil end
    local orig = U.gf_int(C.f_pick, it)
    if type(orig) ~= "number" then return nil end
    if not pcall(P.set_field_value, C.f_pick, it, best_pick, "int32") then return nil end
    local ok, res = pcall(P.invoke, C.m_hasPickPower, player, x, y)
    pcall(P.set_field_value, C.f_pick, it, orig, "int32")
    if ok and type(res) == "boolean" then return res end
    return nil
end

function M.item_value(item)
    return U.gf_int(C.f_value, item)
end

function M.wand_runtime_id()
    if not (mod.item and mod.item.runtime_id) then return -1 end
    local ok, v = pcall(mod.item.runtime_id, SD.S.item_name)
    if ok and type(v) == "number" and v > 0 then return v end
    return -1
end

function M.refresh_item_id()
    local v = M.wand_runtime_id()
    if v > 0 then SD.S.item_id = v end
    return SD.S.item_id
end

function M.holding_wand(player)
    if not player then return false end
    local inv = M.inventory(player)
    local sel = M.selected(player)
    local it = M.item_at(inv, sel)
    if not it then return false end

    local t = M.item_type(it)
    local id = SD.S.item_id
    if id and id > 0 and t == id then return true end
    local rid = M.wand_runtime_id()
    if rid > 0 and t == rid then return true end

    -- Item.value is written by the register defaults callback and survives
    -- runtime_id being -1 during registration.
    if C.f_value and M.item_value(it) == SD.S.mark then return true end
    return false
end

function M.screen_size()
    local sw = U.call_int(C.m_screenW, nil) or 0
    local sh = U.call_int(C.m_screenH, nil) or 0
    return sw, sh
end

function M.mouse_pos()
    local mx = U.call_int(C.m_mouseX, nil) or 0
    local my = U.call_int(C.m_mouseY, nil) or 0
    return mx, my
end

function M.player_pos(player)
    if not player or not C.f_position then return nil end
    return U.read_vec2_field(C.f_position, player)
end

function M.zoom()
    local z = C.f_zoom and U.gf_float(C.f_zoom, nil) or 0
    if z < 0.5 or z > 4.0 then z = 1.0 end
    return z
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
    -- Fallback: assume the camera is centred on the player. Good enough for a
    -- preview outline when the real screenPosition getter is unavailable.
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

function M.net_mode()
    if mod.net and type(mod.net.mode) == "function" then
        local ok, m = pcall(mod.net.mode)
        if ok and type(m) == "number" then return m end
    end
    return 0
end

function M.world_bounds()
    local mx = C.f_maxTX and U.gf_int(C.f_maxTX, nil) or 0
    local my = C.f_maxTY and U.gf_int(C.f_maxTY, nil) or 0
    if mx <= 0 then mx = 8400 end
    if my <= 0 then my = 2400 end
    return mx, my
end

function M.tile_ok(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return false end
    local mx, my = M.world_bounds()
    return x >= 0 and y >= 0 and x < mx and y < my
end

function M.clamp_tile(x, y)
    local mx, my = M.world_bounds()
    x = U.clamp(math.floor(x), 0, mx - 1)
    y = U.clamp(math.floor(y), 0, my - 1)
    return x, y
end

-- Aim resolver. Player.tileTargetX/Y is the game's own cursor tile and is the
-- most reliable source on this build; the rest are fallbacks.
function M.aim(player)
    local tx = C.m_tileTargetX and U.call_int(C.m_tileTargetX, nil)
    local ty = C.m_tileTargetY and U.call_int(C.m_tileTargetY, nil)
    if tx and ty and M.tile_ok(tx, ty) and not (tx == 0 and ty == 0) then
        return tx, ty, "target"
    end

    if C.m_mouseWorld then
        local wx, wy = U.read_vec2_getter(C.m_mouseWorld, nil)
        if type(wx) == "number" and type(wy) == "number" then
            local x, y = math.floor(wx / 16), math.floor(wy / 16)
            if M.tile_ok(x, y) then return x, y, "mouse" end
        end
    end

    local sx, sy = M.screen_pos(player)
    if type(sx) == "number" then
        local mx, my = M.mouse_pos()
        local z = M.zoom()
        local x, y = math.floor((sx + mx / z) / 16), math.floor((sy + my / z) / 16)
        if M.tile_ok(x, y) then return x, y, "screen" end
    end

    local px, py = M.player_pos(player)
    if px then
        local w = C.f_width and U.gf_int(C.f_width, player) or 20
        local h = C.f_height and U.gf_int(C.f_height, player) or 42
        local dir = C.f_direction and U.gf_int(C.f_direction, player) or 1
        if dir == 0 then dir = 1 end
        local x = math.floor((px + w / 2) / 16) + dir * 2
        local y = math.floor((py + h - 16) / 16)
        x, y = M.clamp_tile(x, y)
        return x, y, "player"
    end

    return 0, 0, "none"
end

function M.use_state(player)
    if not player then return false, false end
    local left = (C.f_useItem and U.gf_bool(C.f_useItem, player)) or false
    local right = (C.f_useTile and U.gf_bool(C.f_useTile, player)) or false
    if not left and C.m_mouseLeft then left = U.call_bool(C.m_mouseLeft, nil) == true end
    if not right and C.m_mouseRight then right = U.call_bool(C.m_mouseRight, nil) == true end
    return left, right
end

function M.inventory_open()
    if not C.m_playerInventory then return false end
    return U.call_bool(C.m_playerInventory, nil) == true
end

-- v1.3.0：聊天栏播报。5 参 (string, byte, byte, byte, bool) 优先，
--   拿不到退回 4 参 (string, byte, byte, byte)；两者都失败就静默。
function M.notify(text, r, g, b)
    local str = tostring(text or "")
    if str == "" then return false end
    r, g, b = r or 255, g or 235, b or 160
    -- 关键：invoke 的参数编组（build_arg_array -> read_patch_value）
    --   对 PATCH_OBJECT 直接 to_handle，而 to_handle 拿到 Lua 字符串会返回 NULL，
    --   于是 NewText 实际收到空串、静默不显示。
    --   （set_field_value 走 read_element，那里才有字符串自动转托管串的分支。）
    --   所以必须先用 string_create 造句柄，再传给 invoke。
    local s = nil
    if type(P.string_create) == "function" then
        local okc, h = pcall(P.string_create, str)
        if okc then s = h end
    end
    if not s then return false end
    -- 注意：invoke 失败是「返回 false」而不是抛错，pcall 拿不到这个信息，
    --   必须额外判返回值。
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

return M
