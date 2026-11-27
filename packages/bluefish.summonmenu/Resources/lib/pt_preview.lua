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
local geom = require("pt_placement")
local state = require("pt_state")

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

-- 本地玩家实例。只用于取 placementPreview 的 opacity ——
-- 手持判定和范围计算都在 pt_drag.tick 里做完了。
local function local_player()
    local players = mod.patch.get_field_value(
            q.field("Terraria", "Main", "player"), nil, "object")
    if not players then return nil end
    local myPlayer = main_prop("get_myPlayer")
    if type(myPlayer) ~= "number" or myPlayer < 0 then return nil end
    return mod.patch.array_at(players, myPlayer)
end

-- ============================ 每帧绘制 ============================

-- ==================== 对外：给物块魔杖借用的火把幽灵绘制 ====================
-- 物块魔杖铺的是灰砖（图格 38），它是普通方块、没有 TileObjectData，
-- 走不了原版 DrawPreview；但火把（图格 4）有，可以正常画幽灵。
-- 所以这里把「帧上下文」和「批量画火把」暴露出去，让 bw_preview 在自己的 batch 里调用。

-- 准备一帧的绘制上下文：返回 sb, op, drawArgs（失败返回 nil）。
-- 位置沿用平台魔杖那一套（渲染线程实际 screenPosition - offSet）。
local function frame_ctx()
    local player = local_player()
    if not player then return nil end

    local posx, posy, spx, spy = nil, nil, nil, nil
    local rsx, rsy, rox, roy = render_offset()
    if rsx then
        posx, posy = rsx - rox, rsy - roy
        spx, spy = rsx, rsy
    else
        spx, spy = screen_position()
        if type(spx) ~= "number" or type(spy) ~= "number" then return nil end
        local off = 0
        if q.get_field_value("Terraria", "Main", "drawToScreen", nil, "bool") ~= true then
            off = q.get_field_value("Terraria", "Main", "offScreenRange", nil, "float") or 0
        end
        posx, posy = spx - off, spy - off
    end
    posx = posx - (P.CALIBRATE_X_TILES or 0) * 16
    posy = posy - (P.CALIBRATE_Y_TILES or 0) * 16

    local opacity = q.invoke("Terraria", "Player", "GetPlacementPreviewOpacity", player)
    if type(opacity) ~= "number" then opacity = 1 end

    local sb = q.get_object("Terraria", "Main", "spriteBatch", nil)
    if not sb then return nil end

    local op
    if h.fObjectPreview then
        op = mod.patch.get_field_value(h.fObjectPreview, nil, "object")
    else
        op = q.call(h.mGetObjectPreview)
    end
    if not op then return nil end

    local mainInstance = q.get_object("Terraria", "Main", "instance", nil)
    if mainInstance then
        q.invoke("Terraria", "Main", "LoadTiles", mainInstance, P.TILE)
        q.invoke("Terraria", "Main", "LoadTiles", mainInstance, geom.TILE_TORCH)
    end

    prepare(op)
    local vec = mod.patch.struct_arg({ "float", "float" }, { posx, posy })
    return sb, op, { sb, op, vec, opacity }
end

-- 在当前已经 SpriteBatch.Begin 过的 batch 里画一批火把幽灵。
-- list 元素形如 { tx = 格x, ty = 格y }（ty 就是火把所在格，不用自己减 1）。
function M.draw_torches_in_batch(list, sb, op, drawArgs)
    if not (sb and op and drawArgs) then return false end
    if not ensure() then return false end
    if not list or #list == 0 then return false end

    for i = 1, #list do
        local it = list[i]
        q.call(h.mSetType, op, geom.TILE_TORCH)
        q.call(h.mSetStyle, op, geom.TORCH_STYLE)
        set_coordinates(op, it.tx, it.ty)
        mod.patch.invoke_value_args(h.mDraw, drawArgs)
    end

    -- 切回平台，避免影响后续（平台魔杖自己的 render 也会重新 prepare，这里是保险）
    q.call(h.mSetType, op, P.TILE)
    q.call(h.mSetStyle, op, P.STYLE)
    return true
end

-- 供 bw_preview 拿帧上下文
function M.frame_ctx()
    if not P.ENABLED then return nil end
    if not ensure() then return nil end
    return frame_ctx()
end

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

    -- 手持判定和范围计算都在 pt_drag.tick 里做完了，这里只负责画。
    if not state.preview_on then return end
    local x1, x2, y1, y2 = state.px1, state.px2, state.py1, state.py2
    if type(x1) ~= "number" or type(x2) ~= "number" then return end
    if type(y1) ~= "number" or type(y2) ~= "number" then return end

    local player = local_player()
    if not player then return end
    local width = q.get_field_value("Terraria", "Main", "maxTilesX", nil, "int32")
    local height = q.get_field_value("Terraria", "Main", "maxTilesY", nil, "int32")
    if not width or not height then return end

    -- 原版传给 DrawPreview 的 position = 渲染用 screenPosition - offSet。
    -- 直接读原版渲染线程本帧的实际值，缩放/offScreenRange 都会自动正确。
    local posx, posy, spx, spy
    local rsx, rsy, rox, roy = render_offset()
    if rsx then
        posx, posy = rsx - rox, rsy - roy
        spx, spy = rsx, rsy
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
        -- 火把（图格 4）的图集也提前加载，否则幽灵可能画不出来。
        q.invoke("Terraria", "Main", "LoadTiles", mainInstance, geom.TILE_TORCH)
    end

    prepare(op)

    -- position 与 opacity 整行不变，Vector2 结构体复用一份即可。
    local vec = mod.patch.struct_arg({ "float", "float" }, { posx, posy })
    local drawArgs = { sb, op, vec, opacity }

    -- 画一格「指定图格/样式」的幽灵。
    -- objectPreview 的 type/style 是整体设置，所以画完火把要切回平台，
    -- 否则后面的平台格会被当成火把画。
    local function draw_cell(tile, style, tx, ty)
        q.call(h.mSetType, op, tile)
        q.call(h.mSetStyle, op, style)
        set_coordinates(op, tx, ty)
        mod.patch.invoke_value_args(h.mDraw, drawArgs)
    end

    -- 火把幽灵：与铺放逻辑一致，每 geom.TORCH_STEP 格在平台正上方来一个。
    local function draw_torch(tx, ty)
        if ty - 1 < 0 then return end
        draw_cell(geom.TILE_TORCH, geom.TORCH_STYLE, tx, ty - 1)
        q.call(h.mSetType, op, P.TILE)
        q.call(h.mSetStyle, op, P.STYLE)
    end

    local margin = geom.WORLD_MARGIN
    -- 裁到地图内，避免越界访问图格
    if x1 < margin then x1 = margin end
    if x2 >= width - margin then x2 = width - margin - 1 end
    if y1 < margin then y1 = margin end
    if y2 >= height - margin then y2 = height - margin - 1 end
    if x1 > x2 or y1 > y2 then return end

    -- 逐格画幽灵：平台 + 每 geom.TORCH_STEP 格一个火把。
    -- 相位以左边界为准，与 pt_drag.M.place 的框选分支一致。
    for ty = y1, y2 do
        for tx = x1, x2 do
            set_coordinates(op, tx, ty)
            mod.patch.invoke_value_args(h.mDraw, drawArgs)
            if (tx - x1) % geom.TORCH_STEP == geom.TORCH_OFFSET then
                draw_torch(tx, ty)
            end
        end
    end
end

-- ============================ 安装 ============================

local draw_hooked = false

local function on_draw(_, args)
    -- TileDrawing.Draw(solidLayer, forRenderTargets, intoRenderTargets, waterStyleOverride)
    if args and args[1] == true then
        local ok, err = pcall(M.render)
        if not ok then warn_once(err) end
        -- 给物块魔杖留的挂点：它借这个钩子的环境画自己的火把幽灵
        -- （DrawPreview 的 position 只在这个时刻的 screenPosition 下才对）
        if M.on_draw_extra then
            local ok2, err2 = pcall(M.on_draw_extra)
            if not ok2 then warn_once(err2) end
        end
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