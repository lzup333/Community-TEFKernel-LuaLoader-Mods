-- 房屋魔杖 —— 一键建造 房屋.png 里的火柴盒房间
-- 结构 / ID 依据 Source-1.4.5.8 源码与 房屋.png，魔杖框架参考 平台魔杖。
require("quickapi")
local q = mod.quickapi
local patch = mod.patch
local bp = require("blueprint")
local tilefield = require("tilefield")
local preview = require("preview")

mod.meta = { pkg_id = "lzup.lua.housewand", version = "1.0.0" }

-- 放置句柄（懒解析）
local place_tile        -- WorldGen.PlaceTile(i,j,type,mute,forced,plr,style) : bool
local place_door        -- WorldGen.PlaceDoor(i,j,type,style) : bool
local place_1x2         -- WorldGen.Place1x2(x,y,type,style)
local place_2x1         -- WorldGen.Place2x1(x,y,type,style)
local place_3x2         -- WorldGen.Place3x2(x,y,type,style)
local place_wall        -- WorldGen.PlaceWall(i,j,type,mute)
local square_tile_frame -- WorldGen.SquareTileFrame(i,j,resetFrame)
local square_wall_frame -- WorldGen.SquareWallFrame(i,j,resetFrame)
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

local function in_world(x, y, width, height)
    local m = bp.WORLD_MARGIN
    return x >= m and y >= m and x < width - m and y < height - m
end

-- 检查建造区域：全部可建（空 / 可砍）才返回 true；并顺手清掉可砍图格。
-- 读取失败（"error"）时不再直接判死，返回 nil 交给上层降级。
local diag = {}   -- 每次检查的诊断信息

local function area_ok(x0, y0, width, height)
    diag = { errors = 0, solids = 0, first_solid = nil, first_error = nil }
    local function check(tx, ty)
        local x, y = x0 + tx, y0 + ty
        if not in_world(x, y, width, height) then return false end
        local cls = tilefield.classify(x, y)
        if cls == "error" then
            diag.errors = diag.errors + 1
            if not diag.first_error then
                diag.first_error = ("(%d,%d)"):format(tx, ty)
            end
            return nil          -- 读不到 → 不确定，交给上层降级
        end
        if cls == "cut" then
            tilefield.kill(x, y)
            return true
        end
        if cls == "solid" then
            diag.solids = diag.solids + 1
            if not diag.first_solid then
                diag.first_solid = ("(%d,%d)"):format(tx, ty)
            end
            return false
        end
        return true
    end
    local saw_error = false
    local function scan(list)
        for _, c in ipairs(list) do
            local r = check(c.tx, c.ty)
            if r == false then return false end   -- 确定实心：拦
            if r == nil then saw_error = true end
        end
        return true
    end
    local ok = scan(bp.cells)
        and scan(bp.wall_cells)
        and scan(bp.torch_cells)
        and scan(bp.chair_cells)
        and scan(bp.table_cells)
    if not ok then return false end
    -- 门的三格
    local d = bp.door
    for k = -1, 1 do
        local r = check(d.tx, d.ty + k)
        if r == false then return false end
        if r == nil then saw_error = true end
    end
    if saw_error then return nil end   -- 读取失败：不确定（上层降级放行）
    return true
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

    -- 光标 = 房间左上角
    local x0, y0 = x, y

    local ok_area = area_ok(x0, y0, width, height)
    if ok_area == false then
        q.set_field_value("Terraria", "Player", "itemAnimation", player, 0, "int32")
        local where = diag.first_solid
                and ("（被挡在 %s）"):format(diag.first_solid) or ""
        chat("房屋魔杖：此处空间不足（需要 10x7 空地）" .. where)
        return
    end
    if ok_area == nil then
        -- 图格读取失败：诊断并降级（不拦截建造，交给原版放置逻辑判断）
        mod.warn(("房屋魔杖：图格读取失败 %d 处，首个 %s —— 已降级为直接建造"):format(
                diag.errors or 0, tostring(diag.first_error)))
    end

    local ok, missing_id, need, have = consume_materials(player)
    if not ok then
        q.set_field_value("Terraria", "Player", "itemAnimation", player, 0, "int32")
        chat(("材料不足：物品 %d 需要 %d 个，只有 %d 个"):format(missing_id, need, have))
        return
    end

    local placed = 0
    local failed = {}   -- { 说明... } 未成功放置的项
    local function bump(okflag, what)
        if okflag == true then
            placed = placed + 1
        elseif what then
            failed[#failed + 1] = what
        end
    end

    -- 1) 木墙（室内 8x5，先铺墙再放家具，互不影响）
    for _, c in ipairs(bp.wall_cells) do
        bump(q.call(place_wall, x0 + c.tx, y0 + c.ty, bp.WALL_WOOD, true))
    end

    -- 2) 木块边框（PlaceTile forced：与原版世界生成同款，不走 EmptyTile 玩家/NPC 检查）
    for _, c in ipairs(bp.cells) do
        bump(q.call(place_tile, x0 + c.tx, y0 + c.ty, bp.TILE_WOOD, true, true, -1, 0),
                ("木块(%d,%d)"):format(c.tx, c.ty))
    end

    -- 3) 门：门中格 = (0,3)。PlaceDoor 要求 j-2、j+2 实心（正好是左墙木块）。
    --    它自带空间校验、不走 EmptyTile，比 PlaceTile(forced) 更合适。
    local dh = bp.door
    local okDoor = false
    if place_door then
        okDoor = q.call(place_door, x0 + dh.tx, y0 + dh.ty, bp.TILE_DOOR, 0) == true
    end
    if not okDoor and place_tile then
        -- 兜底：按原版 frameY 手动铺三格（forced）
        for k = -1, 1 do
            local ok = q.call(place_tile, x0 + dh.tx, y0 + dh.ty + k,
                    bp.TILE_DOOR, true, true, -1, 0)
            okDoor = okDoor or ok == true
        end
    end
    bump(okDoor, "门")

    -- 4) 火把：贴左/右墙。PlaceTile(forced) → 原版 num==4 分支在内部完成墙面吸附。
    for _, c in ipairs(bp.torch_cells) do
        bump(q.call(place_tile, x0 + c.tx, y0 + c.ty, bp.TILE_TORCH, true, true, -1, 0),
                ("火把(%d,%d)"):format(c.tx, c.ty))
    end

    -- 5) 工作台（18，2宽1高）：源码 PlaceTile 分派 case 18 → Place2x1。
    --    Place2x1(x,y) 写 (x,y)、(x+1,y)，要求下方两格实心。锚 = 左半格 (7,5)，
    --    → 占 (7,5)(8,5)，下方 (7,6)(8,6) 是地板，条件满足。
    local function placed_at(x, y, want)
        local ok, t = pcall(tilefield.type_at, x, y)
        return ok and t == want
    end
    -- 工作台只放一次（锚 = 第一个 table_cell），占两格
    local tcell = bp.table_cells[1]
    if tcell then
        local ok
        if place_2x1 then
            local pok = pcall(q.call, place_2x1, x0 + tcell.tx, y0 + tcell.ty, bp.TILE_TABLE, 0)
            if pok then
                ok = placed_at(x0 + tcell.tx, y0 + tcell.ty, bp.TILE_TABLE)
                        or placed_at(x0 + tcell.tx + 1, y0 + tcell.ty, bp.TILE_TABLE)
            end
        end
        bump(ok, ("工作台(%d,%d)-( %d,%d)"):format(
                tcell.tx, tcell.ty, tcell.tx + 1, tcell.ty))
    end

    -- 6) 椅子（15）：Place1x2 锚点 = 座面，写 y-1/y。锚 (6,5) → 占 (6,4)(6,5)。
    for _, c in ipairs(bp.chair_cells) do
        local ok
        if place_1x2 then
            local pok = pcall(q.call, place_1x2, x0 + c.tx, y0 + c.ty, bp.TILE_CHAIR, 0)
            if pok then
                ok = placed_at(x0 + c.tx, y0 + c.ty, bp.TILE_CHAIR)
            end
        end
        bump(ok, ("椅子(%d,%d)"):format(c.tx, c.ty))
    end

    -- 刷新整块的图格 / 墙框架（连接处）
    if square_tile_frame then
        pcall(q.call, square_tile_frame, x0, y0, true)
        pcall(q.call, square_tile_frame, x0 + bp.WIDTH - 1, y0 + bp.HEIGHT - 1, true)
    end
    if square_wall_frame then
        pcall(q.call, square_wall_frame, x0 + 1, y0 + 1, true)
        pcall(q.call, square_wall_frame, x0 + bp.WIDTH - 2, y0 + bp.HEIGHT - 2, true)
    end

    local msg = ("房屋魔杖：建好 %dx%d 房间（墙 %d + 框 %d + 门/家具 %d）"):format(
            bp.WIDTH, bp.HEIGHT, #bp.wall_cells, #bp.cells, placed)
    if #failed > 0 then
        mod.warn(msg .. ("；未放置 %d 项：%s"):format(#failed, table.concat(failed, ", ")))
    else
        mod.info(msg)
    end
end

function setup()
    q.register_item{
        name = bp.ITEM_NAME,
        texture = "house_wand.png",
        width = 24,
        height = 14,
        createTile = 0,     -- 不在脚下生成图格，建造完全由 use 回调完成
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
                name = "House Wand",
                tooltip = ("Builds a %dx%d room at the cursor (wall, door, torch, workbench, chair), consuming materials")
                        :format(bp.WIDTH, bp.HEIGHT),
            },
        },
        recipe = bp.WAND_RECIPE,
        use = build_house,
    }

    -- 启用「图格预览」（复用原版家具幽灵逐格画蓝图，仅 Android 生效）。
    if not preview.install() then
        mod.info("房屋魔杖：图格预览未启用（需要 Android 内核的按值结构体调用）")
    end
end

todo_list = { "setup" }
