-- lw_drag.lua —— 液体魔杖的判断与铺放
--
-- 为什么不走物品的 use 回调：这台内核会把多个自定义物品的 use 回调串在一起，
-- 后注册的物品可能跑别人的代码。所以铺放全部放在每帧总线里，用使用键状态驱动。
--
-- 交互：
--   单击（位移 < DRAG_THRESHOLD）→ 只作用于光标那一格
--   按住拖动（位移 >= DRAG_THRESHOLD）→ 铺出整个矩形（上限 100×100）
-- 每帧把当前范围写进 lw_state，由 lw_preview 负责画。
local M = {}

require("wand_quickapi")
local q = mod.quickapi
local geom = require("lw_placement")
local state = require("lw_state")
local field = require("lw_tilefield")

-- 本魔杖的运行时 ID（由 lw_wand 注册后回填）
local my_id = -1

function M.set_item_id(id)
    if type(id) == "number" and id > 0 then my_id = id end
end

-- ==================== 聊天播报 ====================
-- 安卓端 Main.NewText 的 string 参数必须是托管字符串句柄，直接传 Lua 字符串会闪退。
local function chat(message)
    local method = q.method("Terraria", "Main", "NewText", 5)
    if not (method and mod.patch.string_create) then
        mod.info(message)
        return
    end
    local s = mod.patch.string_create(message)
    if not s then
        mod.info(message)
        return
    end
    local ok = pcall(q.call, method, s, 255, 200, 100, false)
    if not ok then mod.info(message) end
end

-- 对外暴露，切换模式时用
function M.chat(message)
    chat(message)
end

-- ==================== 手持判定 ====================
-- 液体魔杖的 createTile 是 -1（不铺方块），所以不能用图格类型认人，
-- 改用 Item.type 与注册时拿到的运行时 ID 比对。
--   返回 true / false / nil（nil = 读不到，交给调用方决定放不放行）
local function holding_wand(player)
    if not player then return nil end
    if my_id <= 0 then
        if mod.item and type(mod.item.runtime_id) == "function" then
            local ok, v = pcall(mod.item.runtime_id, geom.ITEM_NAME)
            if ok and type(v) == "number" and v > 0 then my_id = v end
        end
    end
    if my_id <= 0 then return nil end

    local item = q.invoke("Terraria", "Player", "get_HeldItem", player)
    if not item then return nil end

    local t = q.get_field_value("Terraria", "Item", "type", item, "int32")
    if type(t) ~= "number" then return nil end
    return t == my_id
end

-- 光标所在格
local function aim(player)
    local tx = q.invoke("Terraria", "Player", "get_tileTargetX")
    local ty = q.invoke("Terraria", "Player", "get_tileTargetY")
    if type(tx) == "number" and type(ty) == "number" then return tx, ty end
    return nil, nil
end

-- 使用键是否按住
local function use_left(player)
    return q.get_field_value("Terraria", "Player", "controlUseItem", player, "bool") == true
end

-- ==================== 铺放 ====================
-- 在 (x1..x2) × (y1..y2) 范围内按当前模式写入 / 清除液体。
local function apply_rect(player, x1, x2, y1, y2)
    local width = q.get_field_value("Terraria", "Main", "maxTilesX", nil, "int32")
    local height = q.get_field_value("Terraria", "Main", "maxTilesY", nil, "int32")
    if type(width) ~= "number" or type(height) ~= "number" then return end

    local margin = geom.WORLD_MARGIN
    if x1 < margin then x1 = margin end
    if x2 >= width - margin then x2 = width - margin - 1 end
    if y1 < margin then y1 = margin end
    if y2 >= height - margin then y2 = height - margin - 1 end
    if x1 > x2 or y1 > y2 then return end

    local mode = state.mode
    local liquid = geom.MODE_LIQUID[mode]
    local done, skipped = 0, 0

    for ty = y1, y2 do
        for tx = x1, x2 do
            if field.solid(tx, ty) then
                skipped = skipped + 1            -- 实心方块里进不去液体
            elseif mode == geom.MODE_CLEAR then
                if field.has_liquid(tx, ty) then
                    if field.clear_liquid(tx, ty) then done = done + 1 end
                else
                    skipped = skipped + 1
                end
            else
                if field.place_liquid(tx, ty, liquid) then done = done + 1 end
            end
        end
    end

    local label = geom.MODE_NAME[mode] or mode
    if done > 0 then
        local extra = (skipped > 0) and ("，跳过 %d 格"):format(skipped) or ""
        chat(("液体魔杖：%s %d 格"):format(label, done) .. extra)
    elseif skipped > 0 then
        chat(("液体魔杖：%s 无可用格"):format(label))
    end
end

-- ==================== 每帧 ====================
local dragging = false
local sx, sy, ex, ey = 0, 0, 0, 0
local preview_allowed = false

local function publish(x1, x2, y1, y2)
    if not preview_allowed then return end
    state.preview_on = true
    state.preview_mode = state.mode
    state.px1, state.px2, state.py1, state.py2 = x1, x2, y1, y2
end

local function clear_preview()
    state.preview_on = false
    state.px1, state.px2, state.py1, state.py2 = nil, nil, nil, nil
end

-- 单击：只取光标那一格
local function single_cell(ax, ay)
    return ax, ax, ay, ay
end

-- 拖动：取拖出来的矩形（state.rect 内部会裁剪到上限）
local function drag_rect()
    state.dragging = true
    state.sx, state.sy, state.ex, state.ey = sx, sy, ex, ey
    local x1, x2, y1, y2 = state.rect()
    state.dragging = false
    return x1, x2, y1, y2
end

function M.tick(player)
    if not player then return end

    -- 手持判定（三态）：
    --   false → 明确不是本魔杖：不铺、不画预览
    --   nil   → 判不出来：照旧允许铺放（不然功能会失效），但不画预览
    --   true  → 确认手持：正常铺放 + 画预览
    local held = holding_wand(player)
    if held == false then
        dragging = false
        preview_allowed = false
        clear_preview()
        return
    end
    preview_allowed = (held == true)
    if not preview_allowed then clear_preview() end

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
            -- 按住中：预览跟着走
            if ddx < geom.DRAG_THRESHOLD and ddy < geom.DRAG_THRESHOLD then
                publish(single_cell(sx, sy))
            else
                publish(drag_rect())
            end
            return
        end

        -- 松手
        dragging = false
        if ddx < geom.DRAG_THRESHOLD and ddy < geom.DRAG_THRESHOLD then
            local x1, x2, y1, y2 = single_cell(sx, sy)
            apply_rect(player, x1, x2, y1, y2)
        else
            local x1, x2, y1, y2 = drag_rect()
            if x1 then apply_rect(player, x1, x2, y1, y2) end
        end
        clear_preview()
        return
    end

    -- 没按着：显示单击会作用的范围（一格）
    publish(single_cell(ax, ay))
end

function M.cleanup()
    dragging = false
    clear_preview()
end

return M