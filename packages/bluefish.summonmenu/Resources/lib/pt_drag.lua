-- pt_drag.lua —— 平台魔杖的铺放驱动（每帧检测，不用模式按钮）
--
-- 交互（和物块魔杖保持一致）：
--   轻按（不移动）           → 按朝向铺 geom.LENGTH 格平台
--   按住并拖动（位移超阈值） → 只铺拖出来的那一条（横拖一排 / 竖拖一竖排）
-- 每帧把当前范围写进 pt_state，由 pt_preview 负责画幽灵。
local M = {}

require("wand_quickapi")
local q = mod.quickapi
local patch = mod.patch
local geom = require("pt_placement")
local state = require("pt_state")
local tilefield = require("pt_tilefield")
-- 手持判定：Player.HeldItem 属性 + Item 字段（见 holding_wand）

-- 本魔杖物品的 createTile 值，用于身份自检
local EXPECT_TILE = geom.TILE_PLATFORM

-- 判定「在拖」的最小位移（格）。小于它就算轻按，铺固定长度。
local DRAG_THRESHOLD = 2

-- ==================== 句柄 ====================
local place_tile
local consume_item
local count_item

local function first_method(class, name, specs)
    for _, spec in ipairs(specs) do
        local m = q.method("Terraria", class, name, spec)
        if m then return m end
    end
    return nil
end

local function ensure_handles()
    place_tile = place_tile or q.method("Terraria", "WorldGen", "PlaceTile", 7)
    consume_item = consume_item or first_method("Player", "ConsumeItem",
            { { params = { "type", "reverseOrder", "includeVoidBag" } }, 3, 2, 1 })
    count_item = count_item or first_method("Player", "CountItem",
            { { params = { "type", "stopCountingAt" } }, 2, 1 })
    return place_tile ~= nil
end

-- ==================== 聊天 ====================
-- 安卓端 Main.NewText 的 string 参数必须是托管字符串句柄，直接传 Lua 字符串会闪退。
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

-- ==================== 手持判定（三态） ====================
--   true / false / nil（判不出来 → 铺放放行、预览不亮）
local item_runtime_id = -1

local function wand_runtime_id()
    if item_runtime_id > 0 then return item_runtime_id end
    if not (mod.item and mod.item.runtime_id) then return -1 end
    local ok, v = pcall(mod.item.runtime_id, geom.ITEM_NAME)
    if ok and type(v) == "number" and v > 0 then
        item_runtime_id = v
        return v
    end
    return -1
end

local function holding_wand(player)
    if not player then return nil end

    -- 用 Player.HeldItem 属性直接拿手上物品实例。
    -- 之前走 selectedItem + inventory 两步，实测在这台机器上读不到（判定恒为 nil）。
    local ok_h, it = pcall(q.invoke, "Terraria", "Player", "get_HeldItem", player)
    if not ok_h or not it then return nil end

    -- ① 能拿到 runtime_id 就按它比
    local id = wand_runtime_id()
    if id > 0 then
        local ok_t, ty = pcall(q.get_field_value, "Terraria", "Item", "type", it, "int32")
        if ok_t and type(ty) == "number" then return ty == id end
    end

    -- ② 拿不到 runtime_id 就按 createTile 认人（平台 19 / 灰砖 38）
    local ok_ct, ct = pcall(q.get_field_value, "Terraria", "Item", "createTile", it, "int32")
    if not ok_ct or type(ct) ~= "number" then return nil end
    return ct == EXPECT_TILE
end

-- ==================== 光标 / 按键 ====================
local function get_bind()
    local sd = rawget(_G, "FBW_SD")
    if type(sd) ~= "table" then return nil end
    local b = sd.bind
    if type(b) == "table" then return b end
    return nil
end

local function aim(player)
    local B = get_bind()
    if B and type(B.aim) == "function" then
        local ok, ax, ay = pcall(B.aim, player)
        if ok and type(ax) == "number" and type(ay) == "number" then
            return ax, ay
        end
    end
    local tx = q.invoke("Terraria", "Player", "get_tileTargetX")
    local ty = q.invoke("Terraria", "Player", "get_tileTargetY")
    if type(tx) == "number" and type(ty) == "number" then return tx, ty end
    return nil, nil
end

local function use_left(player)
    local B = get_bind()
    if B and type(B.use_state) == "function" then
        local ok, l = pcall(B.use_state, player)
        if ok then return l == true end
    end
    return q.get_field_value("Terraria", "Player", "controlUseItem", player, "bool") == true
end

-- ==================== 铺放 ====================
-- 铺 (x1..x2) × (y1..y2) 的范围（都含端点）。
-- 障碍处理：草/藤/花 砍掉再放；灰砖（物块魔杖的产物）拆掉再放；其它实体跳过。
-- 材料：优先扣木平台，木平台用完改扣木材。
-- 火把：第 3 格起步，之后每隔 geom.TORCH_STEP(5) 格一个（3、8、13……）。
--   竖向时 tx 恒定，相位落不到火把位置，天然不会放。
-- origin_x 是相位原点：轻按传光标格，拖动不传（用左边界）。
function M.place(player, x1, x2, y1, y2, origin_x)
    if not ensure_handles() then return end
    local width = q.get_field_value("Terraria", "Main", "maxTilesX", nil, "int32")
    local height = q.get_field_value("Terraria", "Main", "maxTilesY", nil, "int32")
    if type(width) ~= "number" or type(height) ~= "number" then return end

    local margin = geom.WORLD_MARGIN
    if x1 < margin then x1 = margin end
    if x2 >= width - margin then x2 = width - margin - 1 end
    if y1 < margin then y1 = margin end
    if y2 >= height - margin then y2 = height - margin - 1 end
    if x1 > x2 or y1 > y2 then return end

    -- 材料：优先木平台，其次木材（木材是木平台的原料）
    local plat_left = 0
    if count_item then
        plat_left = q.call(count_item, player, geom.PLATFORM_ITEM_ID, 0) or 0
    end
    local wood_left = 0
    if count_item then
        wood_left = q.call(count_item, player, geom.WOOD_ID, 0) or 0
    end
    local budget = plat_left + wood_left
    if budget <= 0 then
        chat("背包里没有木平台或木材了")
        return
    end
    local torch_budget = 0
    if count_item then
        torch_budget = q.call(count_item, player, geom.TORCH_ID, 0) or 0
    end

    local ox = origin_x or x1
    local placed, skipped = 0, 0
    for ty = y1, y2 do
        if placed >= budget then break end
        for tx = x1, x2 do
            if placed >= budget then break end

            if tilefield.type_at(tx, ty) == geom.TILE_PLATFORM then
                skipped = skipped + 1      -- 已经是平台，不重复放也不重复扣
            else
                local cls = tilefield.classify(tx, ty)
                if cls == "cut" then
                    tilefield.kill(tx, ty)
                elseif cls == "solid" and tilefield.is_soft(tilefield.type_at(tx, ty)) then
                    -- 软障碍（物块魔杖铺的灰砖）：拆掉换成平台，不掉物品
                    tilefield.kill(tx, ty, true)
                    if tilefield.type_at(tx, ty) == 0 then cls = "empty" end
                end
                -- 已经是平台不算硬块；其它 solid 依然当障碍
                if cls ~= "solid" then
                    local ok = q.call(place_tile, tx, ty, geom.TILE_PLATFORM,
                            true, false, -1, geom.PLACE_STYLE)
                    if ok == true then
                        placed = placed + 1
                        if consume_item then
                            if plat_left > 0 then
                                q.call(consume_item, player, geom.PLATFORM_ITEM_ID, false, false)
                                plat_left = plat_left - 1
                            elseif wood_left > 0 then
                                q.call(consume_item, player, geom.WOOD_ID, false, false)
                                wood_left = wood_left - 1
                            end
                        end
                        -- 第 3 格起步、之后每隔 TORCH_STEP 格放一个火把
                        local phase = (tx - ox) % geom.TORCH_STEP
                        if phase == geom.TORCH_OFFSET and torch_budget > 0 then
                            local ty_t = ty - 1
                            if ty_t >= margin then
                                local tc = tilefield.classify(tx, ty_t)
                                local has_already = tilefield.type_at(tx, ty_t) == geom.TILE_TORCH
                                if tc ~= "solid" and not has_already then
                                    if tc == "cut" then tilefield.kill(tx, ty_t) end
                                    local ok_t = q.call(place_tile, tx, ty_t, geom.TILE_TORCH,
                                            true, false, -1, geom.TORCH_STYLE)
                                    if ok_t == true and tilefield.type_at(tx, ty_t) == geom.TILE_TORCH then
                                        torch_budget = torch_budget - 1
                                        if consume_item then
                                            q.call(consume_item, player, geom.TORCH_ID, false, false)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if placed > 0 then
        local extra = (skipped > 0) and ("，跳过已有 %d 格"):format(skipped) or ""
        mod.info(("平台魔杖：铺放 %d 格"):format(placed) .. extra)
    end
    -- 什么都没铺成（障碍 / 材料不足）不播报，避免刷屏
end

-- ==================== 每帧 ====================
local dragging = false
local sx, sy, ex, ey = 0, 0, 0, 0
local preview_allowed = false

local function publish(x1, x2, y1, y2)
    if not preview_allowed then return end
    state.preview_on = true
    state.px1, state.px2, state.py1, state.py2 = x1, x2, y1, y2
end

local function clear_preview()
    state.preview_on = false
    state.px1, state.px2, state.py1, state.py2 = nil, nil, nil, nil
end

-- 轻按的固定范围：光标沿朝向铺 geom.LENGTH 格，一层。
local function fixed_range(player, ax, ay)
    local dir = q.get_field_value("Terraria", "Player", "direction", player, "int32") or 1
    local step = geom.step(dir)
    local far = ax + (geom.LENGTH - 1) * step
    local x1, x2 = ax, far
    if x1 > x2 then x1, x2 = x2, x1 end
    return x1, x2, ay, ay
end

-- 拖动范围：只出一条线。宽 >= 高 → 横向一行；高 > 宽 → 竖向一列。
local function drag_range()
    local ddx = math.abs(ex - sx)
    local ddy = math.abs(ey - sy)
    if ddx >= ddy then
        local x1, x2 = sx, ex
        if x1 > x2 then x1, x2 = x2, x1 end
        if x2 - x1 + 1 > state.MAX_LEN then
            if ex >= sx then x2 = x1 + state.MAX_LEN - 1 else x1 = x2 - state.MAX_LEN + 1 end
        end
        return x1, x2, sy, sy
    end
    local y1, y2 = sy, ey
    if y1 > y2 then y1, y2 = y2, y1 end
    if y2 - y1 + 1 > state.MAX_H then
        if ey >= sy then y2 = y1 + state.MAX_H - 1 else y1 = y2 - state.MAX_H + 1 end
    end
    return sx, sx, y1, y2
end

function M.tick(player)
    if not player then return end

    local held = holding_wand(player)
    if held == false then
        dragging = false
        preview_allowed = false
        clear_preview()
        return
    end
    preview_allowed = (held == true)
    if not preview_allowed then
        clear_preview()
    end

    local ax, ay = aim(player)
    if not ax or not ay then
        clear_preview()
        return
    end

    local down = use_left(player)
    if down then
        if not dragging then
            dragging = true
            sx, sy = ax, ay
            ex, ey = ax, ay
        else
            ex, ey = ax, ay
        end
    end

    if dragging then
        local ddx = math.abs(ex - sx)
        local ddy = math.abs(ey - sy)

        if down then
            if ddx < DRAG_THRESHOLD and ddy < DRAG_THRESHOLD then
                local x1, x2, y1, y2 = fixed_range(player, sx, sy)
                publish(x1, x2, y1, y2)
            else
                local x1, x2, y1, y2 = drag_range()
                publish(x1, x2, y1, y2)
            end
            return
        end

        dragging = false
        if ddx < DRAG_THRESHOLD and ddy < DRAG_THRESHOLD then
            local x1, x2, y1, y2 = fixed_range(player, sx, sy)
            M.place(player, x1, x2, y1, y2, sx)
        else
            local x1, x2, y1, y2 = drag_range()
            M.place(player, x1, x2, y1, y2)
        end
        clear_preview()
        return
    end

    local x1, x2, y1, y2 = fixed_range(player, ax, ay)
    publish(x1, x2, y1, y2)
end

function M.cleanup()
    dragging = false
    preview_allowed = false
    clear_preview()
end

return M