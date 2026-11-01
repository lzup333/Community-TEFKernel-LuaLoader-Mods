-- Copyright (C) 2026 lzup333
--
-- 本程序为自由软件，基于 AGPL-3.0-or-later 授权发布，
-- 详情见 <https://www.gnu.org/licenses/agpl-3.0.html>。
--
-- 死亡台词 —— 玩家每次死亡，从台词表随机挑一条发到聊天栏
-- 台词里可用 <player_name> 占位，发送时自动替换为玩家名字

mod.meta = { pkg_id = "lzup.lua.zakodeath", version = "1.0.0" }

local patch = mod.patch

-- ============ 台词表（想加就往里塞，一行一条） ============
local DEATH_LINES = {
    "杂鱼<player_name>~ 又被打死了喵~",
    "zako~ zako~",
    "杂鱼<player_name>~ 真是小杂鱼呢",
    "你是只杂鱼喵!",
    "杂鱼<player_name>~ fvv喵~"
}

-- ============ 句柄 ============
local T_MAIN, T_PLAYER
local F_main_player, F_my_player, F_player_name
local M_new_text        -- Main.NewText（平台重载不同）
local M_kill_me         -- Player.KillMe（死亡入口）
local last_fire = 0     -- 去重：同一秒内多次 KillMe 只发一条

-- ============ 工具 ============
local function show_chat(text)
    if not text or not M_new_text then return end
    local s = patch.string_create(text)
    if not s then return end
    if mod.platform == "android" then
        patch.invoke(M_new_text, s, 255, 80, 80, false)
    else
        patch.invoke(M_new_text, s, 255, 80, 80)
    end
end

local function local_player()
    if not F_main_player or not F_my_player then return nil end
    local idx = patch.get_field_value(F_my_player, nil, "int32")
    if not idx or idx < 0 then return nil end
    local arr = patch.get_field_value(F_main_player, nil, "object")
    if not arr then return nil end
    return patch.array_at(arr, idx)
end

local function player_name()
    local p = local_player()
    if p and F_player_name then
        local s = patch.get_field_value(F_player_name, p, "object")
        if s then
            local n = patch.string_value(s)
            if n and n ~= "" then return n end
        end
    end
    return "喵"
end

local function on_death()
    -- 去重：KillMe 可能被同一次死亡的多条路径触发
    local now = os and os.time and os.time() or 0
    if now == last_fire then return end
    last_fire = now

    local line = DEATH_LINES[math.random(#DEATH_LINES)]
    line = line:gsub("<player_name>", player_name())
    show_chat(line)
end

-- ============ 初始化 ============
local function setup()
    T_MAIN = patch.get_type("Terraria", "Main")
    T_PLAYER = patch.get_type("Terraria", "Player")
    if not T_MAIN or not T_PLAYER then
        mod.error("获取类型失败 (Main/Player)")
        return
    end

    F_main_player = patch.get_field(T_MAIN, "player")
    F_my_player = patch.get_field(T_MAIN, "myPlayer")
    F_player_name = patch.get_field(T_PLAYER, "name")

    -- 聊天输出：手机 5 参 / PC 4 参
    if mod.platform == "android" then
        M_new_text = patch.get_method(T_MAIN, "NewText", 5) or patch.get_method(T_MAIN, "NewText")
    else
        M_new_text = patch.get_method(T_MAIN, "NewText", 4) or patch.get_method(T_MAIN, "NewText")
    end

    -- 死亡入口：优先 4 参重载 (PlayerDeathReason, double, int, string)，取不到按名兜底
    M_kill_me = patch.get_method(T_PLAYER, "KillMe", 4) or patch.get_method(T_PLAYER, "KillMe")
    if not M_kill_me then
        mod.error("找不到 Player.KillMe，死亡台词不可用")
        return
    end

    if not patch.install_hook(M_kill_me, { postfix = on_death }, "KillMe") then
        mod.error("KillMe 钩子安装失败")
        return
    end

    mod.info("死亡台词已加载（共 " .. #DEATH_LINES .. " 条）")
end

todo_list = { setup }
