-- preview.lua —— 平台魔杖的「图格预览」（幽灵平台）
--
-- 思路：不自己切片图集 / 调 SpriteBatch，而是直接复用原版的
-- `Terraria.TileObject.DrawPreview`。
--
--   原版放工作台之类的家具时，Player.UpdatePlacementPreview 会算好
--   TileObject.objectPreview，然后 TileDrawing.Draw 末尾调用
--   TileObject.DrawPreview 画出半透明幽灵。
--
--   平台（图格 19）不是「自定义放置」家具，原版不会给它做预览，
--   所以我们自己在每帧的绘制末尾，把 objectPreview 当成一个 1x1 的对象，
--   沿光标方向逐格 set Coordinates 再调用原版 DrawPreview，
--   就能得到和家具完全一致的半透明平台幽灵。
--
-- 平台帧说明（1.4.5.8）：
--   frameY = 材质样式 * 18（0 = 木平台），frameX = 连接形状（0 = 中间段）。
--   DrawPreview 用 Style 选择行（frameY）；我们只画 1 格，frameX 恒为 0
--   （平台中间段），效果就是一条平台。
--
-- 平台：本 Mod 面向 Android。安卓端很多 Main/Player 成员是「属性」，
-- 底层状态存在 LocalUserGameState 实例里（如 screenPosition / myPlayer /
-- tileTargetX），无法当静态字段读。这里按安卓端实际布局取值：
--   screenPosition → LocalUser.Active → GameState + 偏移（见下）
--   myPlayer / placementPreview / tileTargetX … → 直接调用其 get_ 访问器
--
-- 依赖：按值结构体参数（Point16 / Vector2）仅 Android 内核可用
--       —— mod.patch.struct_arg / mod.patch.invoke_value_args。
--       因此本预览仅在 Android 生效；其它平台自动跳过，不影响放置功能。

local q = mod.quickapi
local patch = mod.patch
local geom = require("placement")
local tilefield = require("tilefield")

local M = {}

local P = {
    ENABLED = true,
    LENGTH = geom.LENGTH,
    TILE = geom.TILE_PLATFORM,
    STYLE = geom.PLACE_STYLE,
    -- 手动校准（单位：图格）。当前真机上预览整体偏「上 N 格、左 M 格」，
    -- 这里在传给 DrawPreview 的位置上反向补偿（正值 = 让预览向右/下补）。
    -- 若以后偏移来源修好，把它设回 0 即可。
    CALIBRATE_X_TILES = 4,
    CALIBRATE_Y_TILES = 4,
}

-- LocalUserGameState.screenPosition 在该安卓版本中的字节偏移（float X / Y）。
-- 来自反编译：Main.get_screenPosition => *(float*)(GameState + 976/980)。
local SCREEN_POS_OFFSET = 976

local h = {}          -- 缓存的句柄
local ready = false   -- 句柄是否已解析完成
local warned = false  -- 出错只提示一次，避免刷屏
local logged = false  -- 位置信息只记录一次，便于真机校准
local last_frame      -- 已绘制的游戏帧号，避免一帧内多次绘制叠加

local function warn_once(msg)
    if warned then return end
    warned = true
    if mod.warn then mod.warn("平台魔杖预览：" .. tostring(msg)) end
end

local function call0(ns, class, getter)
    local ok, v = pcall(q.invoke, ns, class, getter)
    if ok then return v end
    return nil
end

-- 读取 Main 上「属性式」的标量（安卓端底层在 LocalUserGameState）。
local function main_prop(getter)
    return call0("Terraria", "Main", getter)
end

-- 按值结构体（Point16 = 两个 int16）
local function point16(x, y)
    return mod.patch.struct_arg({ "int16", "int16" }, { x, y })
end

-- ============================ 屏幕位置 ============================
-- 安卓端 Main.screenPosition 是属性，且返回 struct，LuaLoader 拿不到返回值；
-- 因此从 LocalUser.Active -> GameState 取实例，再按偏移读 float。

local function game_state()
    if not (h.fLocalUserActive and h.fGameState) then return nil end
    local user = mod.patch.get_field_value(h.fLocalUserActive, nil, "object")
    if not user then return nil end
    return mod.patch.get_field_value(h.fGameState, user, "object")
end

-- 直接取原版渲染线程本帧实际使用的「屏幕位置 + 偏移」。
-- 这样得到的是世界坐标（缩放由 spriteBatch 的 Transform 负责），
-- 不会因为缩放 / offScreenRange 推算错误而错位。
local rt = { tried = false }

local function resolve_render_thread()
    if rt.tried then return rt.ok end
    rt.tried = true

    local tTRM  -- ThreadedRenderManager 类型
    for _, ns in ipairs({ "", "ThreadedRenderManager" }) do
        tTRM = q.type(ns, "ThreadedRenderManager")
        if tTRM then break end
    end
    local tRTI  -- RenderThreadInstance 类型（优先内嵌类型）
    if tTRM then tRTI = patch.get_inner_type(tTRM, "RenderThreadInstance") end
    if not tRTI then
        for _, ns in ipairs({ "ThreadedRenderManager", "" }) do
            tRTI = q.type(ns, "RenderThreadInstance")
            if tRTI then break end
        end
    end
    if not (tTRM and tRTI) then return false end

    rt.tTRM = tTRM
    rt.tRTI = tRTI
    rt.mGetInstance = patch.get_method(tTRM, "get_Instance", 0)
    rt.fDrawThreads = patch.get_field(tTRM, "DrawThreads")
    rt.fScreenPos = patch.get_field(tRTI, "_screenPosition")
    rt.fOffset = patch.get_field(tRTI, "_offSet")

    rt.ok = (rt.mGetInstance and rt.fDrawThreads and rt.fScreenPos and rt.fOffset) ~= nil
    return rt.ok
end

local function render_offset()
    -- 只有固定时序（多线程渲染）才会每帧写入 _screenPosition/_offSet。
    local fFixed = q.field("Terraria", "Main", "terrariasFixedTiming")
    if fFixed and patch.get_field_value(fFixed, nil, "bool") == false then
        return nil
    end
    if not resolve_render_thread() then return nil end
    local trm = q.call(rt.mGetInstance)
    if not trm then return nil end
    local arr = patch.get_field_value(rt.fDrawThreads, trm, "object")
    if not arr then return nil end
    if (patch.array_length(arr) or 0) < 1 then return nil end
    local inst = patch.array_at(arr, 0)
    if not inst then return nil end
    local sx, sy = patch.get_field_vec2(rt.fScreenPos, inst)
    local ox, oy = patch.get_field_vec2(rt.fOffset, inst)
    if type(sx) ~= "number" or type(sy) ~= "number" then return nil end
    return sx, sy, (ox or 0), (oy or 0)
end

local function screen_position()
    local gs = game_state()
    if not gs then return nil end

    -- 优先按字段名（若内核对私有字段命名一致），否则退回按偏移读原始字节。
    if h.fScreenPosition then
        local x, y = mod.patch.get_field_vec2(h.fScreenPosition, gs)
        if x then return x, y end
    end
    if mod.patch.mem_read then
        local raw = mod.patch.mem_read(gs, SCREEN_POS_OFFSET, 8)
        if type(raw) == "string" and #raw == 8 then
            local x, y = string.unpack("ff", raw)
            return x, y
        end
    end
    return nil
end

-- ============================ 句柄解析 ============================

-- 解析并缓存所有句柄。解析失败返回 false（该平台不支持预览）。
local function ensure()
    if ready then return true end
    if not (mod.patch.struct_arg and mod.patch.invoke_value_args) then
        return false
    end

    local NS_PREVIEW = "Terraria.DataStructures"
    local CLASS_PREVIEW = "TileObjectPreviewData"

    -- 绘制相关
    h.fObjectPreview = q.field("Terraria", "TileObject", "objectPreview")
    if h.fObjectPreview then
        h.mGetObjectPreview = nil
    else
        h.mGetObjectPreview = q.method("Terraria", "TileObject", "get_objectPreview", 0)
    end
    h.mDraw = q.method("Terraria", "TileObject", "DrawPreview", 4)
            or q.method("Terraria", "TileObject", "DrawPreview")

    -- objectPreview 的属性/索引器 setter
    h.mSetSize = q.method(NS_PREVIEW, CLASS_PREVIEW, "set_Size", 1)
    h.mSetType = q.method(NS_PREVIEW, CLASS_PREVIEW, "set_Type", 1)
    h.mSetStyle = q.method(NS_PREVIEW, CLASS_PREVIEW, "set_Style", 1)
    h.mSetAlternate = q.method(NS_PREVIEW, CLASS_PREVIEW, "set_Alternate", 1)
    h.mSetRandom = q.method(NS_PREVIEW, CLASS_PREVIEW, "set_Random", 1)
    h.mSetCoordinates = q.method(NS_PREVIEW, CLASS_PREVIEW, "set_Coordinates", 1)
    h.mSetItem = q.method(NS_PREVIEW, CLASS_PREVIEW, "set_Item", 3)

    -- 安卓端状态根：LocalUser.Active -> GameState
    h.fLocalUserActive = q.field("", "LocalUser", "Active")
    h.fGameState = q.field("", "LocalUser", "GameState")
    -- 屏幕位置字段名未知时按偏移读；这里先试几种常见命名。
    for _, name in ipairs({ "screenPosition", "_screenPosition",
                            "cameraPosition", "_cameraPosition" }) do
        local f = q.field("", "LocalUserGameState", name)
        if f then h.fScreenPosition = f break end
    end

    -- 坐标：优先直接写 _coordinates 的原始字节（快），否则退回属性 setter。
    h.fCoordinates = q.field(NS_PREVIEW, CLASS_PREVIEW, "_coordinates")
    local isRef = true
    if h.fCoordinates and mod.patch.field_is_reference then
        isRef = mod.patch.field_is_reference(h.fCoordinates) == true
    end
    h.useRawCoordinates = (h.fCoordinates ~= nil)
            and (mod.patch.set_field_raw ~= nil)
            and (not isRef)

    if not ((h.fObjectPreview or h.mGetObjectPreview) and
            h.mDraw and h.mSetSize and h.mSetType and
            h.mSetStyle and h.mSetAlternate and h.mSetRandom and h.mSetItem and
            (h.useRawCoordinates or h.mSetCoordinates)) then
        return false
    end

    -- 平台的 TileObjectData 绘制偏移：DrawPreview 会把 DrawX/YOffset 额外加上，
    -- 但实际图格的渲染不含它，会导致幽灵相对光标整体偏移。取出来抵消。
    h.drawOffsetX = 0
    h.drawOffsetY = 0
    local okTd, tdata = pcall(q.invoke, "Terraria.ObjectData", "TileObjectData", "GetTileData",
            P.TILE, P.STYLE, -1)
    if okTd and tdata then
        local okx, dx = pcall(q.invoke, "Terraria.ObjectData", "TileObjectData", "get_DrawXOffset", tdata)
        local oky, dy = pcall(q.invoke, "Terraria.ObjectData", "TileObjectData", "get_DrawYOffset", tdata)
        if okx and type(dx) == "number" then h.drawOffsetX = dx end
        if oky and type(dy) == "number" then h.drawOffsetY = dy end
    end
    if mod.info then
        mod.info(("[平台魔杖] 平台 DrawOffset = (%s, %s)"):format(h.drawOffsetX, h.drawOffsetY))
    end

    ready = true
    return true
end

-- ============================ 幽灵绘制 ============================

local function prepare(op)
    -- Size 必须 >= (1,1)：属性 setter 会顺带分配 _data。
    mod.patch.invoke_value_args(h.mSetSize, op, { point16(1, 1) })
    -- data[0,0] = ValidSpot(1)，DrawPreview 才会真正画这一格。
    q.call(h.mSetItem, op, 0, 0, 1)
    q.call(h.mSetType, op, P.TILE)      -- ushort
    q.call(h.mSetStyle, op, P.STYLE)    -- short，0 = 木平台
    q.call(h.mSetAlternate, op, -1)
    q.call(h.mSetRandom, op, -1)
end

local function set_coordinates(op, tx, ty)
    if h.useRawCoordinates then
        mod.patch.set_field_raw(h.fCoordinates, op, string.pack("hh", tx, ty))
    else
        mod.patch.invoke_value_args(h.mSetCoordinates, op, { point16(tx, ty) })
    end
end

-- 取本地玩家正在手持的、属于本 Mod 的物品；不是就返回 nil。
local function local_held_item()
    local players = mod.patch.get_field_value(
            q.field("Terraria", "Main", "player"), nil, "object")
    if not players then return nil end
    local myPlayer = main_prop("get_myPlayer")
    if type(myPlayer) ~= "number" or myPlayer < 0 then return nil end
    local player = mod.patch.array_at(players, myPlayer)
    if not player then return nil end

    local itemId = q.item_id(geom.ITEM_NAME)
    if not itemId or itemId < 0 then return nil end

    local held = q.invoke("Terraria", "Player", "get_HeldItem", player)
    if not held then return nil end
    local heldType = q.get_field_value("Terraria", "Item", "type", held, "int32")
    if heldType ~= itemId then return nil end
    return player
end

-- ============================ 每帧绘制 ============================

function M.render()
    if not P.ENABLED then return end
    if not ensure() then return end

    -- 一帧内 TileDrawing.Draw 可能被调用多次（非实心/实心/渲染目标），只画一次。
    local frame = main_prop("get_GameUpdateCount")
    if type(frame) == "number" then
        if frame == last_frame then return end
        last_frame = frame
    end

    if main_prop("get_gameMenu") == true then return end
    if main_prop("get_placementPreview") == false then return end

    local player = local_held_item()
    if not player then return end
    if q.get_field_value("Terraria", "Player", "active", player, "bool") == false then
        return
    end

    local startX = call0("Terraria", "Player", "get_tileTargetX")
    local startY = call0("Terraria", "Player", "get_tileTargetY")
    if type(startX) ~= "number" or type(startY) ~= "number" then return end

    local width = q.get_field_value("Terraria", "Main", "maxTilesX", nil, "int32")
    local height = q.get_field_value("Terraria", "Main", "maxTilesY", nil, "int32")
    if not width or not height then return end

    local dir = q.get_field_value("Terraria", "Player", "direction", player, "int32") or 1

    -- 原版传给 DrawPreview 的 position = 渲染用 screenPosition - offSet。
    -- 直接读原版渲染线程本帧的实际值，缩放/offScreenRange 都会自动正确。
    local posx, posy, spx, spy
    local pos_src = "fallback"
    local rsx, rsy, rox, roy = render_offset()
    if rsx then
        posx, posy = rsx - rox, rsy - roy
        spx, spy = rsx, rsy
        pos_src = "render"
    else
        spx, spy = screen_position()
        if type(spx) ~= "number" or type(spy) ~= "number" then return end
        local off = 0
        if q.get_field_value("Terraria", "Main", "drawToScreen", nil, "bool") ~= true then
            off = q.get_field_value("Terraria", "Main", "offScreenRange", nil, "float") or 0
        end
        posx, posy = spx - off, spy - off
    end

    -- 手动校准：预览偏上/偏左，就给 pos 减掉对应像素，让幽灵向右/下补回来。
    posx = posx - (P.CALIBRATE_X_TILES or 0) * 16
    posy = posy - (P.CALIBRATE_Y_TILES or 0) * 16

    if not logged then
        logged = true
        mod.info(("[平台魔杖] pos源=%s screenPos=(%s, %s) pos=(%s, %s) 校准=(%s, %s)格"):format(
                pos_src, spx, spy, posx, posy,
                P.CALIBRATE_X_TILES or 0, P.CALIBRATE_Y_TILES or 0))
    end

    local opacity = q.invoke("Terraria", "Player", "GetPlacementPreviewOpacity", player)
    if type(opacity) ~= "number" then opacity = 1 end

    local sb = q.get_object("Terraria", "Main", "spriteBatch", nil)
    if not sb then return end
    local op
    if h.fObjectPreview then
        op = mod.patch.get_field_value(h.fObjectPreview, nil, "object")
    else
        op = q.call(h.mGetObjectPreview)
    end
    if not op then return end

    -- 原版 DrawPreview 前也会 LoadTiles，这里补上以防平台图集未加载。
    local mainInstance = q.get_object("Terraria", "Main", "instance", nil)
    if mainInstance then
        q.invoke("Terraria", "Main", "LoadTiles", mainInstance, P.TILE)
    end

    prepare(op)

    -- position 与 opacity 整行不变，Vector2 结构体复用一份即可。
    local vec = mod.patch.struct_arg({ "float", "float" }, { posx, posy })
    local drawArgs = { sb, op, vec, opacity }

    local step = geom.step(dir)
    local margin = geom.WORLD_MARGIN
    if startY < margin or startY >= height - margin then return end

    -- 预览画满一整行，不做「有无物块挡住」的判断（按需求）。
    -- 不做屏内裁剪：缩放时可见世界范围不等于 screenWidth，裁剪会漏画。
    for i = 0, P.LENGTH - 1 do
        local tx = startX + i * step
        if tx < margin or tx >= width - margin then break end

        -- 与放置行为一致：硬块处停止预览。
        if tilefield.classify(tx, startY) == "solid" then break end

        set_coordinates(op, tx, startY)
        mod.patch.invoke_value_args(h.mDraw, drawArgs)
    end
end

-- ============================ 安装 ============================

local draw_hooked = false

local function on_draw(_, args)
    -- TileDrawing.Draw(solidLayer, forRenderTargets, intoRenderTargets, waterStyleOverride)
    if args and args[1] == true then
        local ok, err = pcall(M.render)
        if not ok then warn_once(err) end
    end
end

-- 尝试装上 TileDrawing.Draw 钩子；成功返回 true。
local function try_hook_draw()
    if draw_hooked then return true end
    -- 不同版本 Draw 的参数个数/名字略有差异，逐个候选尝试。
    local candidates = {
        { params = { "solidLayer", "forRenderTargets", "intoRenderTargets", "waterStyleOverride" } },
        { argc = 4 },
        { params = { "solidLayer", "intoRenderTargets", "waterStyleOverride" } },
        { argc = 3 },
    }
    for _, opts in ipairs(candidates) do
        local ok, hook = pcall(q.install_hook_postfix,
                "Terraria.GameContent.Drawing", "TileDrawing", "Draw", on_draw, opts)
        if ok and hook then
            draw_hooked = true
            return true
        end
    end
    return false
end

function M.install()
    if mod.platform ~= "android" then
        return false
    end
    if try_hook_draw() then return true end

    -- 类型可能还没加载好：挂一个 Main.Update，等类型可用后补装钩子。
    local retry
    retry = q.install_hook_postfix("Terraria", "Main", "Update", function()
        if try_hook_draw() and retry then
            pcall(function() retry:remove() end)
        end
    end, { argc = 1 })
    return retry ~= nil
end

M.config = P
return M