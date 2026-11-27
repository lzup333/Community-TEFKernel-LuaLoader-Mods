local M = {}
-- 房屋魔杖 —— 一键建造 房屋.png 里的火柴盒房间
-- 结构 / ID 依据 Source-1.4.5.8 源码与 房屋.png，魔杖框架参考 平台魔杖。
require("wand_quickapi")
local q = mod.quickapi
local patch = mod.patch
local bp = require("fw_blueprint")
local tilefield = require("fw_tilefield")
local preview = require("fw_preview")


-- 放置句柄（懒解析）
local place_tile        -- WorldGen.PlaceTile(i,j,type,mute,forced,plr,style) : bool
local place_door        -- WorldGen.PlaceDoor(i,j,type,style) : bool
local place_1x2         -- WorldGen.Place1x2(x,y,type,style)
local place_2x1         -- WorldGen.Place2x1(x,y,type,style)
local place_3x2         -- WorldGen.Place3x2(x,y,type,style)
local place_wall        -- WorldGen.PlaceWall(i,j,type,mute)
local square_tile_frame -- WorldGen.SquareTileFrame(i,j,resetFrame)
local square_wall_frame -- WorldGen.SquareWallFrame(i,j,resetFrame)
local kill_tile          -- WorldGen.KillTile(i,j,fail,effectOnly,noItem)
local copy_tile_basic    -- TileData.CopyTileBasic(tileIndex, srcTile)
local copy_tile          -- TileData.CopyTile(tileIndex, srcTile)
local td_set_type        -- TileData.SetType(tileIndex, newType)
local td_set_everything  -- TileData.SetEverything(idx, type, sHeader, frameX, frameY, b1, b2, b3, wall, liquid)
local td_clear_everything -- TileData.ClearEverything(tileIndex)
local consume_item
local count_item

local function try(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

local function first_method(class, name, specs)
    for _, spec in ipairs(specs) do
        local m = try(q.method, "Terraria", class, name, spec)
        if m then return m end
    end
    return nil
end

local function ensure_handles()
    place_tile = place_tile or try(q.method, "Terraria", "WorldGen", "PlaceTile", 7)
    place_door = place_door or first_method("WorldGen", "PlaceDoor",
            { { params = { "i", "j", "type", "style" } }, 4, 3 })
    place_1x2 = place_1x2 or first_method("WorldGen", "Place1x2",
            { { params = { "x", "y", "type", "style" } }, 4, 3 })
    place_2x1 = place_2x1 or first_method("WorldGen", "Place2x1",
            { { params = { "x", "y", "type", "style" } }, 4, 3 })
    place_3x2 = place_3x2 or first_method("WorldGen", "Place3x2",
            { { params = { "x", "y", "type", "style" } }, 4, 3 })
    place_wall = place_wall or first_method("WorldGen", "PlaceWall",
            { { params = { "i", "j", "type", "mute" } }, 4, 3 })
    square_tile_frame = square_tile_frame or first_method("WorldGen", "SquareTileFrame",
            { { params = { "i", "j", "resetFrame" } }, 3, 2 })
    square_wall_frame = square_wall_frame or first_method("WorldGen", "SquareWallFrame",
            { { params = { "i", "j", "resetFrame" } }, 3, 2 })
    kill_tile = kill_tile or first_method("WorldGen", "KillTile",
            { { params = { "i", "j", "fail", "effectOnly", "noItem" } }, 5, 4 })
    copy_tile_basic = copy_tile_basic or first_method("TileData", "CopyTileBasic",
            { { params = { "tileIndex", "srcTile" } }, 2 })
    copy_tile = copy_tile or first_method("TileData", "CopyTile",
            { { params = { "tileIndex", "srcTile" } }, 2 })
    td_set_type = td_set_type or first_method("TileData", "SetType",
            { { params = { "tileIndex", "newType" } }, 2 })
    td_set_everything = td_set_everything or first_method("TileData", "SetEverything",
            { { params = { "tileIndex", "tileType", "tileSHeader", "frameX", "frameY",
                           "tileBHeader", "tileBHeader2", "tileBHeader3", "wall", "liquid" } }, 10 })
    td_clear_everything = td_clear_everything or first_method("TileData", "ClearEverything",
            { { params = { "tileIndex" } }, 1 })
    consume_item = consume_item or first_method("Player", "ConsumeItem",
            { { params = { "type", "reverseOrder", "includeVoidBag" } }, 3, 2, 1 })
    count_item = count_item or first_method("Player", "CountItem",
            { { params = { "type", "stopCountingAt" } }, 2, 1 })
    return place_tile ~= nil
end

-- 聊天输出（安卓端必须 string_create，否则空指针闪退）
local function chat(message)
    local method = q.method("Terraria", "Main", "NewText", 5)
    if not (method and patch.string_create) then
        mod.info(message)
        return
    end
    local s = patch.string_create(message)
    if not s then
        mod.info(message)
        return
    end
    local ok = pcall(q.call, method, s, 255, 200, 100, false)
    if not ok then mod.info(message) end
end


-- 检查并预扣材料（先检查再扣，数量不足直接取消）
local function consume_materials(player)
    for _, c in ipairs(bp.COST) do
        local have = 0
        if count_item then
            have = q.call(count_item, player, c.id, 0) or 0
        end
        if have < c.count then
            return false, c.id, c.count, have
        end
    end
    for _, c in ipairs(bp.COST) do
        for _ = 1, c.count do
            if consume_item then
                q.call(consume_item, player, c.id, false, false)
            end
        end
    end
    return true
end

local function build_house(player)
    if q.net_mode() ~= 0 then
        chat("房屋魔杖仅支持 Android 单机")
        return
    end
    if not ensure_handles() then
        mod.error("房屋魔杖：找不到 WorldGen.PlaceTile")
        return
    end

    local x = try(q.invoke, "Terraria", "Player", "get_tileTargetX")
    local y = try(q.invoke, "Terraria", "Player", "get_tileTargetY")
    local width = try(q.get_field_value, "Terraria", "Main", "maxTilesX", nil, "int32")
    local height = try(q.get_field_value, "Terraria", "Main", "maxTilesY", nil, "int32")
    if not x or not y or not width or not height then return end
    if type(width) ~= "number" or type(height) ~= "number" then return end

    -- 光标 = 房子「最底下一排」所在的行，整栋往上长（和原版一样防扎进土里）。
    -- 行号换算：世界 y = y0 - (HEIGHT - 1 - ty)
    --   行1 (ty=0，顶部横梁) → y0 - 9，最高
    --   行10(ty=9，底部平台) → y0，正好压在光标上
    -- 注意不能直接写 y0 - ty：那只翻了方向，行的顺序也会跟着上下颠倒。
    local x0, y0 = x, y

    -- 不再做空间检查：允许与已有建筑重叠。
    -- 重叠的部分会在下面的「预清空」里被清掉，再按本图纸重新铺，效果是新建的部分
    -- 直接覆盖旧的。所以对着已有的房子再点一次也能建（会把重叠区改成本样式）。

    local ok, missing_id, need, have = consume_materials(player)
    if not ok then
        q.set_field_value("Terraria", "Player", "itemAnimation", player, 0, "int32")
        chat(("材料不足：物品 %d 需要 %d 个，只有 %d 个"):format(missing_id, need, have))
        return
    end

    -- ===== 预清空：先把整个矩形区域的图格/墙/液体全部清掉 =====
    -- TileData.ClearEverything(idx) 直接把这格的全部数据归零，比 WorldGen.KillTile
    -- 更彻底（KillTile 会受 CanKillTile、图格保护、液体等条件影响）。
    -- 清完之后再从头铺墙、铺块，就不会再出现「土块顶不掉、木块放不上」。
    local cleared = 0
    local out_of_map = 0
    if td_clear_everything and tilefield.index_of then
        for ty = 0, bp.HEIGHT - 1 do
            for tx = 0, bp.WIDTH - 1 do
                local cx = x0 + tx
                local cy = y0 - (bp.HEIGHT - 1 - ty)
                -- 只做地图边界保护（越界调用 ClearEverything 会让游戏崩），
                -- 不再管里面有没有东西 —— 有东西也照样清掉重建。
                if cx >= 0 and cy >= 0 and cx < width and cy < height then
                    local idx = tilefield.index_of(cx, cy)
                    if idx then
                        if pcall(q.call, td_clear_everything, idx) then
                            cleared = cleared + 1
                        end
                    end
                else
                    out_of_map = out_of_map + 1
                end
            end
        end
        -- 清完刷新一下框架，避免残影
        if square_tile_frame then
            pcall(q.call, square_tile_frame, x0, y0, true)
            pcall(q.call, square_tile_frame, x0 + bp.WIDTH - 1, y0 - (bp.HEIGHT - 1), true)
        end
    end

    local placed = 0
    local failed = {}   -- { 说明... } 未成功放置的项
    local function placed_at(x, y, want)
        local ok, t = pcall(tilefield.type_at, x, y)
        return ok and t == want
    end
    -- 先清空该格（noItem=true，不掉任何物品）再放置。
    -- 依据 PC 1.4.5.8 WorldGen.PlaceTile：函数里只有
    --     if (!tile.active()) { tile.Clear(...); }      // 仅「本来就是空位」才清格
    -- 然后就跳到 num==23/199/81/61/518/... 的特例分支，木块 30 不在其中，
    -- 没有任何通用赋值把 tile.type 改成 30。
    -- 所以对已经是土块/石头的格子，PlaceTile(forced=true) 会「进去但什么都不做」，
    -- 原图块原样保留 —— 这就是建完后那格还是土块的原因。
    -- 必须先 KillTile 把原图格打掉（noItem=true 不掉落），木块才放得上去。
    local function clear_then_place(px, py, tile)
        if kill_tile then
            pcall(q.call, kill_tile, px, py, false, false, true)
        end
        local okp = q.call(place_tile, px, py, tile, true, true, -1, 0)
        if okp ~= true and not placed_at(px, py, tile) then
            if kill_tile then
                pcall(q.call, kill_tile, px, py, false, false, true)
            end
            okp = q.call(place_tile, px, py, tile, true, true, -1, 0)
        end
        return okp
    end
    local function bump(okflag, what)
        if okflag == true then
            placed = placed + 1
        elseif what then
            failed[#failed + 1] = what
        end
    end

    -- 1) 木墙（背景层，先铺墙再放家具，互不影响）
    for _, c in ipairs(bp.wall_cells) do
        bump(q.call(place_wall, x0 + c.tx, y0 - (bp.HEIGHT - 1 - c.ty), bp.WALL_WOOD, true))
    end

    -- 2) 边框与平台（PlaceTile forced：与原版世界生成同款，不走 EmptyTile 玩家/NPC 检查）
    --    每格自带 c.tile，木块 30 / 木平台 19；平台不需要支撑，可以悬空
    for _, c in ipairs(bp.cells) do
        local px, py = x0 + c.tx, y0 - (bp.HEIGHT - 1 - c.ty)
        local tile = c.tile or bp.TILE_WOOD
        local what = (tile == bp.TILE_PLATFORM) and "平台" or "木块"
        bump(clear_then_place(px, py, tile), ("%s(%d,%d)"):format(what, c.tx, c.ty))
    end


    -- 4) 火把：贴左/右墙。PlaceTile(forced) → 原版 num==4 分支在内部完成墙面吸附。
    for _, c in ipairs(bp.torch_cells) do
        bump(clear_then_place(x0 + c.tx, y0 - (bp.HEIGHT - 1 - c.ty), bp.TILE_TORCH),
                ("火把(%d,%d)"):format(c.tx, c.ty))
    end

    -- 5) 工作台（18，2宽1高）：源码 PlaceTile 分派 case 18 → Place2x1。
    --    Place2x1(x,y) 写 (x,y)、(x+1,y)，要求下方两格实心。锚 = 左半格 (7,5)，
    --    → 占 (7,5)(8,5)，下方 (7,6)(8,6) 是地板，条件满足。
    -- 工作台只放一次（锚 = 第一个 table_cell），占两格
    local tcell = bp.table_cells[1]
    if tcell then
        local ok
        if place_2x1 then
            local pok = pcall(q.call, place_2x1, x0 + tcell.tx, y0 - (bp.HEIGHT - 1 - tcell.ty), bp.TILE_TABLE, 0)
            if pok then
                ok = placed_at(x0 + tcell.tx, y0 - (bp.HEIGHT - 1 - tcell.ty), bp.TILE_TABLE)
                        or placed_at(x0 + tcell.tx + 1, y0 - (bp.HEIGHT - 1 - tcell.ty), bp.TILE_TABLE)
            end
        end
        bump(ok, ("工作台(%d,%d)-( %d,%d)"):format(
                tcell.tx, tcell.ty, tcell.tx + 1, tcell.ty))
    end

    -- 6) 椅子（15）：Place1x2 锚点 = 座面，写 y-1/y。锚 (4,4) → 占 (4,3)(4,4)。
    for _, c in ipairs(bp.chair_cells) do
        local ok
        if place_1x2 then
            local pok = pcall(q.call, place_1x2, x0 + c.tx, y0 - (bp.HEIGHT - 1 - c.ty), bp.TILE_CHAIR, 0)
            if pok then
                ok = placed_at(x0 + c.tx, y0 - (bp.HEIGHT - 1 - c.ty), bp.TILE_CHAIR)
            end
        end
        bump(ok, ("椅子(%d,%d)"):format(c.tx, c.ty))
    end

    -- ===== 兜底修补：PlaceTile 没能覆盖的格子，用同类型模板格直接复制 =====
    -- TileData 提供整套静态写接口（手机版专有，PC 没有这个类）：
    --   GetType(idx) / SetType(idx, type) / SetEverything(...) / CopyTileBasic(dst, src)
    -- 这里用 CopyTileBasic：拿已经放好的木块 / 平台当模板，把它的整格数据
    -- 复制到没放上的那格，完全绕过 WorldGen.PlaceTile 的各种判定。
    local patched = 0
    local still_bad = {}
    -- 判定某格是否真的到位：类型对 + 实心（平台/火把/家具不是实心，只查类型）
    local function cell_ok(px, py, tile)
        if tilefield.type_at(px, py) ~= tile then return false end
        if tile == bp.TILE_WOOD then
            return tilefield.solid_at(px, py) == true
        end
        return true
    end
    if tilefield.index_of then
        local wood_tpl, plat_tpl
        for _, c in ipairs(bp.cells) do
            local px, py = x0 + c.tx, y0 - (bp.HEIGHT - 1 - c.ty)
            local tile = c.tile or bp.TILE_WOOD
            if cell_ok(px, py, tile) then
                local idx = tilefield.index_of(px, py)
                if tile == bp.TILE_PLATFORM then
                    plat_tpl = plat_tpl or idx
                else
                    wood_tpl = wood_tpl or idx
                end
            end
        end
        for _, c in ipairs(bp.cells) do
            local px, py = x0 + c.tx, y0 - (bp.HEIGHT - 1 - c.ty)
            local tile = c.tile or bp.TILE_WOOD
            if not cell_ok(px, py, tile) then
                local tpl = (tile == bp.TILE_PLATFORM) and plat_tpl or wood_tpl
                local dst = tilefield.index_of(px, py)
                local done = false
                -- ① 完整复制模板格（CopyTile 含类型与帧，比 CopyTileBasic 更彻底）
                if copy_tile and tpl and dst then
                    pcall(q.call, copy_tile, dst, tpl)
                    done = cell_ok(px, py, tile)
                end
                -- ② 只改类型
                if not done and td_set_type and dst then
                    pcall(q.call, td_set_type, dst, tile)
                    done = cell_ok(px, py, tile)
                end
                -- ③ 手工整格构造：字段取自模板格，墙沿用目标格原有的
                if not done and td_set_everything and tpl and dst then
                    local s = tilefield.snapshot(tpl)
                    if s then
                        local keep_wall = tilefield.wall_at(px, py)
                        if type(keep_wall) ~= "number" or keep_wall < 0 then keep_wall = 0 end
                        pcall(q.call, td_set_everything, dst, tile, s.sh, s.fx, s.fy,
                                s.b1, s.b2, s.b3, keep_wall % 256, s.liq)
                        done = cell_ok(px, py, tile)
                    end
                end
                if done then
                    patched = patched + 1
                    placed = placed + 1
                else
                    still_bad[#still_bad + 1] = ("(%d,%d)"):format(c.tx, c.ty)
                end
            end
        end
    end

    -- 刷新整块的图格 / 墙框架（连接处）
    if square_tile_frame then
        pcall(q.call, square_tile_frame, x0, y0, true)
        pcall(q.call, square_tile_frame, x0 + bp.WIDTH - 1, y0 - (bp.HEIGHT - 1), true)
    end
    if square_wall_frame then
        pcall(q.call, square_wall_frame, x0 + 1, y0 - 1, true)
        pcall(q.call, square_wall_frame, x0 + bp.WIDTH - 2, y0 - (bp.HEIGHT - 2), true)
    end

end

function M.setup()
    q.register_item{
        name = bp.ITEM_NAME,
        texture = "house_wand.png",
        sacrifice = 1,   -- 研究需要 1 个（0 = 不可研究）
        width = 24,
        height = 14,
        -- createTile 必须是 -1（表示「这个物品不放置图格」）。
        -- 填 0 会被当成 TileID.Dirt = 土块：每次挥动魔杖，原版 Player.PlaceThing()
        -- 都会先在光标那一格放一块土，于是「光标在哪格，哪格就是土块」，
        -- 而我们随后要放的木块因为那格已是 active 的土块而失败。
        createTile = -1,
        useStyle = 1,
        useTime = 60,
        useAnimation = 60,
        maxStack = 1,
        consumable = false,
        language = {
            zh = {
                name = "房屋魔杖",
                tooltip = ("以光标为左上角一键建造 %dx%d 房间（木墙+门+火把+工作台+椅子，消耗背包材料）")
                        :format(bp.WIDTH, bp.HEIGHT),
            },
            en = {
                name = "房屋魔杖",
                tooltip = ("以光标为左上角一键建造 %dx%d 房间（木墙+门+火把+工作台+椅子，消耗背包材料）")
                        :format(bp.WIDTH, bp.HEIGHT),
            },
        },
        recipe = bp.WAND_RECIPE,
        use = function(plr)
            -- 兜底：任何 Lua 异常都在聊天栏报出来，而不是静默失败
            local uok, uerr = pcall(build_house, plr)
            if not uok then
                mod.error("房屋魔杖异常：" .. tostring(uerr))
                chat("房屋魔杖出错：" .. tostring(uerr))
            end
        end,
    }

    -- 启用「图格预览」（复用原版家具幽灵逐格画蓝图，仅 Android 生效）。
    if not preview.install() then
        mod.info("房屋魔杖：图格预览未启用（需要 Android 内核的按值结构体调用）")
    end
end

return M
