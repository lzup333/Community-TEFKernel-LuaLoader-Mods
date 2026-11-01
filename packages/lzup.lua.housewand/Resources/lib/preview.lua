-- preview.lua —— 房屋魔杖的「图格预览」（幽灵房屋边框）
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
local bp = require("blueprint")

local M = {}

-- 预览只画「1x1 木块边框」：沿用已验证的 TileObject.DrawPreview 路径
-- （TileObject.DrawPreview 画单 type/style 的 1x1 幽灵，安全）。
-- 门/家具/火把不逐格 set_Type —— DrawPreview 会按 type 重新 GetTileData，
-- 任一 type/style 组合取不到 data 会 NullReference → set_unexpected → SIGABRT，
-- op[i,j] 的 CoordinateHeights 越界会 IndexOutOfRange → 同样 abort（实机已复现）。
local P = {
    ENABLED = true,    -- 预览：1x1 木块幽灵（已验证的安全路径）。
    CALIBRATE_X_TILES = 4,
    CALIBRATE_Y_TILES = 4,
    TILE = 19,          -- 木平台：Android 上已验证可安全走 TileObject.DrawPreview
    STYLE = 0,
    -- 不手动调 Main.LoadTiles：原版 DrawPreview 的 TextureAssets.Tile[].Value 会自动加载，
    -- 实机证明额外的 LoadTiles 是 pos 日志后崩溃的元凶（且多余）。
}

-- 只画边框（与 blueprint.cells 同源），保证预览与建造的框一致。
local border = {}
for _, c in ipairs(bp.cells) do
    border[#border + 1] = { tx = c.tx, ty = c.ty }
end
P.ORDER = border

-- LocalUserGameState.screenPosition 在该安卓版本中的字节偏移（float X / Y）。
-- 来自反编译：Main.get_screenPosition => *(float*)(GameState + 976/980)。
local SCREEN_POS_OFFSET = 976

local h = {}          -- 缓存的句柄
local ready = false   -- 句柄是否已解析完成
local warned = false  -- 出错只提示一次，避免刷屏
local logged = false  -- 位置信息只记录一次，便于真机校准
local last_frame      -- 已绘制的游戏帧号，避免一帧内多次绘制叠加
local last_ensure_frame -- 上次重新 ensure 的帧号（句柄过期保护）

local function warn_once(msg)
    if warned then return end
    warned = true
    if mod.warn then mod.warn("房屋魔杖预览：" .. tostring(msg)) end
end

local function call0(ns, class, getter)
    local ok, v = pcall(q.invoke, ns, class, getter)
    if ok then return v end
    return nil
end

-- pcall0(n, fn, ...)：pcall 并返回前 n 个结果，失败返回 nil。
-- 用于把 pos 日志之后的每个原生调用都兜住（il2cpp 跨边界异常 pcall 不一定拦得住，
-- 但兜住能覆盖“找不到方法→Lua error”这类）。
local function pcall0(n, fn, ...)
    local r = table.pack(pcall(fn, ...))
    if not r[1] then return nil end
    return table.unpack(r, 2, n + 1)
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
    local ok1, r1 = pcall(q.field, "Terraria", "TileObject", "objectPreview")
    h.fObjectPreview = ok1 and r1 or nil
    if h.fObjectPreview then
        h.mGetObjectPreview = nil
    else
        local ok2, r2 = pcall(q.method, "Terraria", "TileObject", "get_objectPreview", 0)
        h.mGetObjectPreview = ok2 and r2 or nil
    end
    local okD, rD = pcall(q.method, "Terraria", "TileObject", "DrawPreview", 4)
    h.mDraw = (okD and rD) or nil
    if not h.mDraw then
        local okD2, rD2 = pcall(q.method, "Terraria", "TileObject", "DrawPreview")
        h.mDraw = okD2 and rD2 or nil
    end

    -- objectPreview 的属性/索引器 setter（il2cpp 属性 → set_XXX 方法）
    local function m(name, argc)
        local ok, r = pcall(q.method, NS_PREVIEW, CLASS_PREVIEW, name, argc)
        return ok and r or nil
    end
    h.mSetSize = m("set_Size", 1)
    h.mSetType = m("set_Type", 1)
    h.mSetStyle = m("set_Style", 1)
    h.mSetAlternate = m("set_Alternate", 1)
    h.mSetRandom = m("set_Random", 1)
    h.mSetCoordinates = m("set_Coordinates", 1)
    h.mSetItem = m("set_Item", 3)

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

    -- 蓝图里木块的 TileObjectData 绘制偏移：DrawPreview 会把 DrawX/YOffset 额外加上，
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
    elseif not tdata then
        -- 预览类型取不到 TileObjectData 时禁用，避免 Android IL2CPP 空引用崩溃。
        -- 交付版本木块 data 正常，此分支仅作兜底。
        warn_once("TileObjectData.GetTileData(19) 为 nil，预览已禁用")
        P.ENABLED = false
        return false
    end
    if mod.info then
        mod.info(("[房屋魔杖] 边框 DrawOffset = (%s, %s)"):format(h.drawOffsetX, h.drawOffsetY))
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
    q.call(h.mSetStyle, op, P.STYLE)    -- short
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

    local itemId = q.item_id(bp.ITEM_NAME)
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
    -- 句柄可能因 Mod /reload 失效：出错就标记过期，下次重新 ensure。
    if frame ~= nil and last_ensure_frame and frame > last_ensure_frame + 600 then
        ready = false
        last_ensure_frame = frame
    end
    if not last_ensure_frame then last_ensure_frame = frame end

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

    local width = pcall0(1, q.get_field_value, "Terraria", "Main", "maxTilesX", nil, "int32")
    local height = pcall0(1, q.get_field_value, "Terraria", "Main", "maxTilesY", nil, "int32")
    if not width or not height then return end

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
        if pcall0(1, q.get_field_value, "Terraria", "Main", "drawToScreen", nil, "bool") ~= true then
            off = pcall0(1, q.get_field_value, "Terraria", "Main", "offScreenRange", nil, "float") or 0
        end
        posx, posy = spx - off, spy - off
    end

    -- 手动校准：预览偏上/偏左，就给 pos 减掉对应像素，让幽灵向右/下补回来。
    posx = posx - (P.CALIBRATE_X_TILES or 0) * 16
    posy = posy - (P.CALIBRATE_Y_TILES or 0) * 16

    if not logged then
        logged = true
        mod.info(("[房屋魔杖] pos源=%s screenPos=(%s, %s) pos=(%s, %s) 校准=(%s, %s)格"):format(
                pos_src, spx, spy, posx, posy,
                P.CALIBRATE_X_TILES or 0, P.CALIBRATE_Y_TILES or 0))
    end

    local opacity = pcall0(1, q.invoke, "Terraria", "Player", "GetPlacementPreviewOpacity", player)
    if type(opacity) ~= "number" then opacity = 1 end

    local sb = pcall0(1, q.get_object, "Terraria", "Main", "spriteBatch", nil)
    if not sb then return end
    local op
    if h.fObjectPreview then
        op = pcall0(1, patch.get_field_value, h.fObjectPreview, nil, "object")
    else
        op = pcall0(1, q.call, h.mGetObjectPreview)
    end
    if not op then return end

    -- 关键：这里【刻意不调 Main.LoadTiles】。
    -- 原版 DrawPreview 里的 TextureAssets.Tile[op.Type].Value 对未加载贴图会自动加载，
    -- 无需手动 LoadTiles；实机崩溃正是出在这类 pos 日志之后的额外原生调用上。
    -- 若真要预加载，务必 pcall——但已确认 LoadTiles 是多余且危险的。

    local okPrep, prepErr = pcall(prepare, op)
    if not okPrep then
        warn_once("prepare 失败，跳过本帧预览：" .. tostring(prepErr))
        P.ENABLED = false   -- 跨边界异常 pcall 可能拦不住，直接关掉保命
        return
    end

    -- position 与 opacity 整行不变，Vector2 结构体复用一份即可。
    local vec = pcall0(1, patch.struct_arg, { "float", "float" }, { posx, posy })
    if not vec then return end
    local drawArgs = { sb, op, vec, opacity }

    local margin = bp.WORLD_MARGIN
    if startY < margin or startY >= height - margin then return end
    if startX < margin or startX >= width - margin then return end

    -- 逐格画 1x1 木块边框：每格 set_coordinates + DrawPreview（单 type/style，安全）。
    local n = 0
    for _, cell in ipairs(P.ORDER) do
        local tx = startX + cell.tx
        local ty = startY + cell.ty
        if tx < margin or tx >= width - margin
                or ty < margin or ty >= height - margin then
            break
        end
        local okC = pcall(set_coordinates, op, tx, ty)
        if not okC then break end   -- 坐标 setter 抛异常 → 停止本帧绘制
        n = n + 1
        pcall(mod.patch.invoke_value_args, h.mDraw, drawArgs)
    end
    if n == 0 then return end
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
