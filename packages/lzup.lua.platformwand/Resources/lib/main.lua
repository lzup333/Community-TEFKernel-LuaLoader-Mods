require("quickapi")
local q = mod.quickapi
local patch = mod.patch
local geom = require("placement")
local tilefield = require("tilefield")
local preview = require("preview")

mod.meta = { pkg_id = "lzup.lua.platformwand", version = "1.0.0" }

local TILE_PLATFORM = geom.TILE_PLATFORM
local PLACE_STYLE = geom.PLACE_STYLE
local LENGTH = geom.LENGTH
local PLATFORM_ITEM = geom.PLATFORM_ITEM_ID   -- 94 = 木平台

-- 放置时用到的句柄（懒解析，避免注册阶段类型还没加载好）。
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

-- 聊天输出。安卓端 Main.NewText 的 string 参数必须是托管字符串句柄，
-- 直接传 Lua 字符串会变成空指针 → 闪退。这里先 string_create。
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

local function place_line(player)
    if q.net_mode() ~= 0 then
        chat("平台魔杖仅支持 Android 单机")
        return
    end
    if not ensure_handles() then
        mod.error("平台魔杖：找不到 WorldGen.PlaceTile")
        return
    end

    -- 背包里还有多少木平台可用。
    local budget = 0
    if count_item then
        budget = q.call(count_item, player, PLATFORM_ITEM, 0) or 0
    end
    if budget <= 0 then
        chat("背包里没有木平台了")
        return
    end

    -- 安卓端 tileTargetX/Y 是属性（底层在 LocalUserGameState），走 get_ 访问器。
    local x = q.invoke("Terraria", "Player", "get_tileTargetX")
    local y = q.invoke("Terraria", "Player", "get_tileTargetY")
    local dir = q.get_field_value("Terraria", "Player", "direction", player, "int32") or 1
    local width = q.get_field_value("Terraria", "Main", "maxTilesX", nil, "int32")
    local height = q.get_field_value("Terraria", "Main", "maxTilesY", nil, "int32")
    if not x or not y or not width or not height then return end

    local margin = geom.WORLD_MARGIN
    if y < margin or y >= height - margin then
        chat("平台魔杖：超出世界范围")
        return
    end

    local step = geom.step(dir)
    local placed = 0

    for i = 0, LENGTH - 1 do
        local tx = x + i * step
        if tx < margin or tx >= width - margin then break end
        if placed >= budget then break end

        local cls = tilefield.classify(tx, y)
        if cls == "solid" then
            -- 需要镐子的硬块：不摧毁，停止后续铺放。
            break
        end
        if cls == "cut" then
            -- 剑能砍掉的（草/藤/花等）：摧毁后再铺。
            tilefield.kill(tx, y)
        end

        local ok = q.call(place_tile, tx, y, TILE_PLATFORM, true, false, -1, PLACE_STYLE)
        if ok == true then
            placed = placed + 1
            if consume_item then
                q.call(consume_item, player, PLATFORM_ITEM, false, false)
            end
        else
            break
        end
    end

    if placed <= 0 then
        -- 一格都没放：压掉本帧的动作，避免原版（本物品 createTile=19）
        -- 在光标那格单独放一块平台、覆盖硬块。
        q.set_field_value("Terraria", "Player", "itemAnimation", player, 0, "int32")
        chat("平台魔杖：此处无法铺放")
    else
        mod.info(("平台魔杖：铺放 %d 格"):format(placed))
    end
end

function setup()
    q.register_item{
        name = geom.ITEM_NAME,
        texture = "platform_wand.png",
        width = 24,
        height = 14,
        createTile = TILE_PLATFORM,
        placeStyle = PLACE_STYLE,
        useStyle = 1,
        useTime = 30,
        useAnimation = 30,
        maxStack = 1,
        consumable = false,       -- 魔杖本身不消耗，消耗的是背包里的木平台
        tooltip = true,
        language = {
            zh = {
                name = "平台魔杖",
                tooltip = ("向面朝方向铺放木平台（最多 %d 格，消耗背包木平台）"):format(LENGTH),
            },
            en = {
                name = "Platform Wand",
                tooltip = ("Places up to %d wooden platforms, consuming them from your inventory"):format(LENGTH),
            },
        },
        recipe = geom.WAND_RECIPE,
        use = place_line,
    }

    -- 启用「图格预览」（复用原版家具幽灵的绘制，仅 Android 生效）。
    if not preview.install() then
        mod.info("平台魔杖：图格预览未启用（需要 Android 内核的按值结构体调用）")
    end
end

todo_list = { "setup" }