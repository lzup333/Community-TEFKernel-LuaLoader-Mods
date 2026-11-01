mod.meta = { pkg_id = "lzup.lua.chatcommands", version = "5.0.0" }
local patch = mod.patch

local god_mode = false
local damage_mode = false
local target_fov = nil

local ITEM_MAP = {}
local NPC_MAP = {}

local T_MAIN, T_PLAYER, T_ITEM, T_NPC, T_GAMEVIEWMATRIX
local F_pos, F_velocity, F_width, F_height
local F_main_player, F_my_player, F_day_time, F_time
local F_stat_life, F_stat_life_max, F_stat_mana, F_stat_mana_max
local F_creative_god, F_immune_time
local F_melee, F_ranged, F_magic
local F_gameViewMatrix, F_zoom
local M_get_my_player, M_new_text, M_new_item, M_new_npc, M_get_text, F_msg_text
local function starts(s, prefix) return s and s:sub(1, #prefix) == prefix end
local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- 加载器：重点修复隐藏字符和空格
local function load_id_map(filename, target)
    local content = mod.read_file(filename)
    if not content then mod.warn("未找到 " .. filename) return end
    local count = 0
    for line in content:gmatch("[^\r\n]+") do
        local clean_line = trim(line)
        local name, id = clean_line:match("^([^|]+)|(%d+)$")
        if name and id then
            target[trim(name)] = tonumber(id)
            count = count + 1
        end
    end
    mod.info("已加载 " .. filename .. " 共 " .. count .. " 条")
end

load_id_map("items_final.txt", ITEM_MAP)
load_id_map("npcs_final.txt", NPC_MAP)

local function parse_target(str, map)
    if not str then return nil end
    str = trim(str)
    local num = tonumber(str)
    if num then return num end
    if map[str] then return map[str] end
    return nil
end

local function show_chat(text)
    if not text or not M_new_text then return end
    local s = patch.string_create(text)
    if not s then return end
    if mod.platform == "android" then
        patch.invoke(M_new_text, s, 255, 255, 255, false)
    else
        patch.invoke(M_new_text, s, 255, 255, 255)
    end
end
local function my_player_index()
    if F_my_player then
        local v = patch.get_field_value(F_my_player, nil, "int32")
        if v ~= nil then return v end
    end
    if M_get_my_player then return patch.invoke(M_get_my_player) end
    return -1
end

local function get_player(whoAmI)
    if whoAmI == nil or whoAmI < 0 or whoAmI > 255 then return nil end
    local arr = patch.get_field_value(F_main_player, nil, "object")
    if not arr or whoAmI >= patch.array_length(arr) then return nil end
    return patch.array_at(arr, whoAmI)
end

local function parse_alias(str)
    if not str then return nil end
    local num = trim(str):match("^(%d+)a$")
    return num and (tonumber(num) - 1) or tonumber(trim(str))
end

local function teleport_to(player, x, y)
    if not player then return false end
    patch.set_field_vec2(F_pos, player, x * 16, y * 16)
    if F_velocity then patch.set_field_vec2(F_velocity, player, 0.0, 0.0) end
    return true
end
local function handle_command(raw, sender)
    if starts(raw, "/tp here") then
        local target = parse_alias(raw:sub(9))
        local p1, p2 = get_player(sender), get_player(target)
        if p1 and p2 then
            local px, py = patch.get_field_vec2(F_pos, p1)
            if px and py then
                patch.set_field_vec2(F_pos, p2, px, py)
                if F_velocity then patch.set_field_vec2(F_velocity, p2, 0.0, 0.0) end
                show_chat("[助手] 已将 " .. raw:sub(9) .. " 传送过来")
            end
        end
        return
    end

    if starts(raw, "/tp") then
        local rest = trim(raw:sub(4))
        local x, y = rest:match("^(%d+)%s+(%d+)$")
        if x and y then
            teleport_to(get_player(sender), tonumber(x), tonumber(y))
            show_chat("[助手] 已传送至 " .. rest)
        else
            local target = parse_alias(rest)
            local p1, p2 = get_player(sender), get_player(target)
            if p1 and p2 then
                local tx, ty = patch.get_field_vec2(F_pos, p2)
                if tx and ty then
                    patch.set_field_vec2(F_pos, p1, tx, ty)
                    if F_velocity then patch.set_field_vec2(F_velocity, p1, 0.0, 0.0) end
                    show_chat("[助手] 已传送到 " .. rest)
                end
            end
        end
        return
    end
    if starts(raw, "/time") then
    local arg = trim(raw:sub(6))
    local is_day, time_val = nil, nil
    if arg == "day" or arg == "白天" then is_day, time_val = true, 27000.0
    elseif arg == "night" or arg == "夜晚" then is_day, time_val = false, 16200.0
    else
        local h, m = arg:match("^(%d+):(%d+)$")
        if h then
            h, m = tonumber(h), tonumber(m)
            local total = h * 3600 + m * 60
            if total >= 16200 and total < 70200 then is_day, time_val = true, total - 16200
            else
                if total < 16200 then total = total + 86400 end
                is_day, time_val = false, total - 70200
            end
        end
    end
    if is_day ~= nil then
        patch.set_field_value(F_day_time, nil, is_day, "bool")
        patch.set_field_value(F_time, nil, time_val, "double")
        show_chat("[助手] 时间已修改: " .. (is_day and "白天" or "夜晚"))
    else show_chat("[助手] 用法: /time 01:01 | day|night") end
    return
end

if starts(raw, "/fov") then
    local arg = trim(raw:sub(5))
    if arg == "reset" then target_fov = nil; show_chat("[助手] 视野已重置"); return end
    local v = tonumber(arg)
    if v and v > 0 and v <= 10.0 then target_fov = v; show_chat("[助手] 视野已设为 " .. v) end
    return
end
if starts(raw, "/god") and not starts(raw, "/godx") then
    local p = get_player(sender)
    if p then
        local on = not patch.get_field_value(F_creative_god, p, "bool")
        patch.set_field_value(F_creative_god, p, on, "bool")
        if on then patch.set_field_value(F_immune_time, p, 9999999, "int32") end
        show_chat("[助手] 无敌已" .. (on and "开启" or "关闭"))
    end
    return
end

if starts(raw, "/godx") then
    damage_mode = not damage_mode
    show_chat("[助手] 伤害拉满已" .. (damage_mode and "开启！" or "关闭"))
    return
end

if starts(raw, "/heal") then
    local p = get_player(sender)
    if p then
        if F_stat_life and F_stat_life_max then
            patch.set_field_value(F_stat_life, p, patch.get_field_value(F_stat_life_max, p, "int32") or 0, "int32")
        end
        if F_stat_mana and F_stat_mana_max then
            patch.set_field_value(F_stat_mana, p, patch.get_field_value(F_stat_mana_max, p, "int32") or 0, "int32")
        end
        show_chat("[助手] 已恢复全部生命与法力")
    end
    return
end
local sp_prefix = nil
if starts(raw, "/spawn") and (raw == "/spawn" or raw:sub(8, 8) == " ") then sp_prefix = "/spawn"
elseif starts(raw, "/sp") and (raw == "/sp" or raw:sub(4, 4) == " ") then sp_prefix = "/sp" end
if sp_prefix then
    local rest = trim(raw:sub(#sp_prefix + 1))
    local name_str, count_str = rest:match("^(.-)%s*(%d*)$")
    if name_str == "" and count_str ~= "" then
            name_str = count_str
            count_str = "1"
        end
    local count = math.max(1, math.min(100, tonumber(count_str) or 1))
    local id = parse_target(name_str, NPC_MAP)
    if not id then show_chat("[助手] 找不到该生物：" .. name_str) return end
    if not M_new_npc then return end
    local p = get_player(sender)
    if not p then return end
    local px, py = patch.get_field_vec2(F_pos, p)
    local w = patch.get_field_value(F_width, p, "int32") or 0
    local h = patch.get_field_value(F_height, p, "int32") or 0
    local bx, by = math.floor(px) + math.floor(w / 2), math.floor(py) + math.floor(h)
    for i = 0, count - 1 do
        patch.invoke(M_new_npc, nil, bx + (i % 8) * 24 - 84, by + math.floor(i / 8) * 24, math.floor(id), 0, 0.0, 0.0, 0.0, 0.0, 255)
    end
    show_chat(string.format("[助手] 已生成 %s x %d (ID: %d)", name_str, count, id))
    return
end
    if starts(raw, "/get") or starts(raw, "/give") then
        local prefix = starts(raw, "/give") and "/give" or "/get"
        local rest = trim(raw:sub(#prefix + 1))
        local name_str, count_str = rest:match("^(.-)%s*(%d*)$")
        if name_str == "" and count_str ~= "" then
            name_str = count_str
            count_str = "1"
        end
         local stack = math.max(1, math.min(9999, tonumber(count_str) or 1))
        local id = parse_target(name_str, ITEM_MAP)
        if not id then show_chat("[助手] 找不到物品：" .. name_str) return end
        local p = get_player(sender)
        if not p or not M_new_item then return end
        local px, py = patch.get_field_vec2(F_pos, p)
        local w = patch.get_field_value(F_width, p, "int32") or 0
        local h = patch.get_field_value(F_height, p, "int32") or 0
        patch.invoke(M_new_item, math.floor(px), math.floor(py), math.floor(w), math.floor(h), math.floor(id), math.floor(stack), false, 0, 0)
        show_chat(string.format("[助手] 已给予 %s x %d (ID: %d)", name_str, stack, id))
        return
    end
end
local function on_chat(instance, args, result)
    if not args then return end
    local text = nil
    if M_get_text then
        local s = patch.invoke(M_get_text, args[1])
        if s then text = patch.string_value(s) end
    elseif F_msg_text then
        text = patch.get_field_value(F_msg_text, args[1], "string")
    end
    if text and (starts(text, "/tp") or starts(text, "/time") or starts(text, "/god") or starts(text, "/fov") or starts(text, "/sp") or starts(text, "/spawn") or starts(text, "/get") or starts(text, "/give") or starts(text, "/heal")) then
        handle_command(text, args[2])
    end
end

local function on_reset(instance, args, result)
    if not instance then return end
    local my = my_player_index()
    if my < 0 or instance ~= get_player(my) then return end
    if damage_mode then
        if F_melee then patch.set_field_value(F_melee, instance, 999999, "float") end
        if F_ranged then patch.set_field_value(F_ranged, instance, 999999, "float") end
        if F_magic then patch.set_field_value(F_magic, instance, 999999, "float") end
    end
    if target_fov and F_gameViewMatrix and F_zoom then
        local m = patch.get_field_value(F_gameViewMatrix, nil, "object")
        if m then patch.set_field_vec2(F_zoom, m, math.max(0.1, math.min(10.0, 1.0 / target_fov))) end
    end
end
function setup()
    mod.info("Lua指令助手 v5.0.0 初始化")
    T_MAIN = patch.get_type("Terraria", "Main")
    T_PLAYER = patch.get_type("Terraria", "Player")
    T_ITEM = patch.get_type("Terraria", "Item")
    T_NPC = patch.get_type("Terraria", "NPC")
    if not T_MAIN or not T_PLAYER then return end

    F_pos = patch.get_field(T_PLAYER, "position") or patch.get_field(patch.get_parent(T_PLAYER), "position")
    F_velocity = patch.get_field(T_PLAYER, "velocity") or patch.get_field(patch.get_parent(T_PLAYER), "velocity")
    F_width = patch.get_field(T_PLAYER, "width") or patch.get_field(patch.get_parent(T_PLAYER), "width")
    F_height = patch.get_field(T_PLAYER, "height") or patch.get_field(patch.get_parent(T_PLAYER), "height")
    F_main_player = patch.get_field(T_MAIN, "player")
    F_my_player = patch.get_field(T_MAIN, "myPlayer")
    F_day_time = patch.get_field(T_MAIN, "dayTime")
    F_time = patch.get_field(T_MAIN, "time")
    F_stat_life = patch.get_field(T_PLAYER, "statLife")
    F_stat_life_max = patch.get_field(T_PLAYER, "statLifeMax")
    F_stat_mana = patch.get_field(T_PLAYER, "statMana")
    F_stat_mana_max = patch.get_field(T_PLAYER, "statManaMax")
    F_creative_god = patch.get_field(T_PLAYER, "creativeGodMode")
    F_immune_time = patch.get_field(T_PLAYER, "immuneTime")
    F_melee = patch.get_field(T_PLAYER, "meleeDamage")
    F_ranged = patch.get_field(T_PLAYER, "rangedDamage")
    F_magic = patch.get_field(T_PLAYER, "magicDamage")
    F_gameViewMatrix = patch.get_field(T_MAIN, "GameViewMatrix")
    T_GAMEVIEWMATRIX = patch.get_type("Terraria", "GameViewMatrix")
    if T_GAMEVIEWMATRIX then F_zoom = patch.get_field(T_GAMEVIEWMATRIX, "Zoom") end
    M_new_text = patch.get_method(T_MAIN, "NewText", 5) or patch.get_method(T_MAIN, "NewText")
    M_new_item = patch.get_method(T_ITEM, "NewItem", 9) or patch.get_method(T_ITEM, "NewItem")
    M_new_npc = patch.get_method(T_NPC, "NewNPC", 10) or patch.get_method(T_NPC, "NewNPC")
    if F_my_player then M_get_my_player = patch.get_method(T_MAIN, "get_myPlayer", 0) end
    local msg_type = patch.get_type("Terraria.Chat", "ChatMessage")
    if msg_type then
        M_get_text = patch.get_method(msg_type, "get_Text", 0)
        F_msg_text = patch.get_field(msg_type, "<Text>k__BackingField")
    end
    local chat_type = patch.get_type("Terraria.Chat", "ChatCommandProcessor")
    local chat_method = chat_type and patch.get_method(chat_type, "ProcessIncomingMessage", 2)
    if chat_method then patch.install_hook(chat_method, { postfix = on_chat }) end
    local reset_method = patch.get_method(T_PLAYER, "ResetEffects", 0)
    if reset_method then patch.install_hook(reset_method, { postfix = on_reset }) end
    mod.info("Lua指令助手初始化完成")
end

function cleanup()
    damage_mode = false
    target_fov = nil
    mod.info("清理完成")
end

todo_list = { "setup" }
