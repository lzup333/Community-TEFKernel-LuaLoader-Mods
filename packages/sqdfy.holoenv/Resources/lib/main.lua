-- ============================================================================
--  环境监控 v1.1.2 —— 聊天栏单行版
--  pkg: sqdfy.holoenv      author: 烧钱的肥鱼
--  目标版本：Terraria 1.4.5.8 手机版 + LuaLoader（api_version 1）
-- ============================================================================
--  只做一件事：把当前环境压成一行，发到聊天栏。
--
--      环境：丛林丨群系：地表丨事件：史莱姆雨
--
--  · 进世界 0.5 秒后发第一行；
--  · 之后只在群系 / 层深 / 事件变化时再发（带最短间隔，防止穿越群系刷屏）；
--  · 没有悬浮面板，不写文件，不碰任何游戏数值。
--
--  v1.1.0 修复：手机版的 Player.Zone* 是属性（get_ZoneJungle）不是字段，
--  之前按字段读全空，所以永远显示「森林 / 岩层」。现在先字段、再属性，
--  两套都支持。
--
--  挂点：
--    Player.Update(postfix)  主挂点，实例就是玩家本人；用 whoAmI == Main.myPlayer
--                            过滤联机时其它玩家的 Update。
--    Main.Update(postfix)    备挂点：主挂点没装上时自己计时，并从玩家数组取样本。
-- ============================================================================

mod.meta = {
    pkg_id       = "sqdfy.holoenv",
    version      = "1.1.2",
    version_code = 4,
    api_version  = 1,
}

local patch  = mod.patch
local ENV    = require("env")
local FMT    = require("format")
local REPORT = require("report")
local CONFIG = require("config")

-- ============================================================================
-- 状态
-- ============================================================================
local H = {}
local hooks = {}
local ctx = nil
local cfg = nil
local sample = nil
local reporter = nil
local frame = 0
local failFrames = 0
local inited = false
local warnedOnce = {}

local SAMPLE_EVERY = 10          -- 每 10 帧采样一次（≈0.17 秒）

-- ============================================================================
-- 工具
-- ============================================================================
local function warn_once(key, text)
    if warnedOnce[key] then return end
    warnedOnce[key] = true
    pcall(mod.warn, text)
end

local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local ok, f = pcall(patch.get_field, cur, name)
        if ok and f then return f end
        local okp, parent = pcall(patch.get_parent, cur)
        cur = (okp and parent) or nil
        guard = guard + 1
    end
    return nil
end

local function rd(field, inst, ty)
    if not field then return nil end
    local ok, v = pcall(patch.get_field_value, field, inst, ty)
    if ok then return v end
    return nil
end

local function in_world()
    local v = rd(H.f_gamemenu, nil, "bool")
    if v == nil then return true end
    return v == false
end

local function make_sender()
    local ok5, m5 = pcall(patch.get_method, H.T_Main, "NewText", 5)
    local ok4, m4 = pcall(patch.get_method, H.T_Main, "NewText", 4)
    if not ok5 then m5 = nil end
    if not ok4 then m4 = nil end
    if not m5 and not m4 then
        warn_once("chat", "[环境监控] 找不到 Main.NewText，播报不可用")
        return function() return false end
    end
    return function(text, r, g, b)
        local s = text
        if type(patch.string_create) == "function" then
            local ok, handle = pcall(patch.string_create, text)
            if ok and handle then s = handle end
        end
        if m5 then
            local ok, ret = pcall(patch.invoke, m5, s, r, g, b, false)
            if ok and ret ~= false then return true end
        end
        if m4 then
            local ok, ret = pcall(patch.invoke, m4, s, r, g, b)
            if ok and ret ~= false then return true end
        end
        return false
    end
end

-- ============================================================================
-- 采样
-- ============================================================================
local function on_player_update(inst)
    if not inited or not inst then return end

    if not in_world() then
        if sample ~= nil then
            sample = nil
            if reporter then reporter:reset() end
        end
        return
    end

    -- 只处理本机玩家
    local who = rd(H.f_whoami, inst, "int32")
    local my  = rd(H.f_myplayer, nil, "int32")
    if type(who) == "number" and type(my) == "number" and who ~= my then
        return
    end
    if rd(H.f_active, inst, "bool") == false then return end

    frame = frame + 1
    if frame % SAMPLE_EVERY ~= 0 then return end

    local ok, s = pcall(ENV.read, ctx, inst)
    if not ok or type(s) ~= "table" then
        failFrames = failFrames + 1
        return
    end

    sample = s
    failFrames = 0
    if reporter and cfg.enabled then
        reporter:tick(s, frame, cfg, FMT)
    end
end

local function try_array_sample()
    local my = rd(H.f_myplayer, nil, "int32")
    local arr = rd(H.f_playerarr, nil, "object")
    if type(my) ~= "number" or my < 0 or not arr then return nil end
    local ok, player = pcall(patch.array_at, arr, my)
    if not ok or not player then return nil end
    local ok2, s = pcall(ENV.read, ctx, player)
    if ok2 and type(s) == "table" then return s end
    return nil
end

local function on_main_update()
    if not inited or not in_world() then return end

    if not H.has_player_hook then
        frame = frame + 1
        if frame % SAMPLE_EVERY == 0 then
            local s = try_array_sample()
            if s then
                sample = s
                failFrames = 0
                if reporter and cfg.enabled then
                    reporter:tick(s, frame, cfg, FMT)
                end
            else
                failFrames = failFrames + 1
            end
        end
        return
    end

    if sample == nil or failFrames > 0 then
        local s = try_array_sample()
        if s then
            sample = s
            failFrames = 0
            if reporter and cfg.enabled then
                reporter:tick(s, frame, cfg, FMT)
            end
            return
        end
        failFrames = failFrames + 1
        if failFrames % 600 == 0 then
            warn_once("nosample", "[环境监控] 尚未采到玩家环境（可能在加载 / 死亡界面）")
        end
    end
end

-- ============================================================================
-- setup
-- ============================================================================
local function install_hook(method, spec, label)
    if not method then
        warn_once("hook:" .. label, "[环境监控] 缺少方法：" .. label)
        return false
    end
    local ok, h = pcall(patch.install_hook, method, spec)
    if not ok or not h then
        warn_once("hookf:" .. label, "[环境监控] 挂钩失败 " .. label .. "：" .. tostring(h))
        return false
    end
    hooks[#hooks + 1] = h
    return true
end

local function setup_impl()
    H.T_Main   = patch.get_type("Terraria", "Main")
    H.T_Player = patch.get_type("Terraria", "Player")
    if not (H.T_Main and H.T_Player) then
        error("关键类型缺失 Main/Player")
    end

    cfg = CONFIG.load(type(mod.read_file) == "function" and mod.read_file or nil)

    H.f_gamemenu  = find_field(H.T_Main, "gameMenu")
    H.f_myplayer  = find_field(H.T_Main, "myPlayer")
    H.f_playerarr = find_field(H.T_Main, "player")
    H.f_whoami    = find_field(H.T_Player, "whoAmI")
    H.f_active    = find_field(H.T_Player, "active")
    if not H.f_whoami or not H.f_active then
        local ok_e, T_Entity = pcall(patch.get_type, "Terraria", "Entity")
        if ok_e and T_Entity then
            if not H.f_whoami then
                local okf, f = pcall(patch.get_field, T_Entity, "whoAmI")
                if okf then H.f_whoami = f end
            end
            if not H.f_active then
                local okf, f = pcall(patch.get_field, T_Entity, "active")
                if okf then H.f_active = f end
            end
        end
    end

    ctx = ENV.attach(patch, H.T_Main, H.T_Player)
    reporter = REPORT.new(make_sender())

    local ok_pu, m_pu = pcall(patch.get_method, H.T_Player, "Update", 1)
    if not ok_pu or not m_pu then
        local ok2, m2 = pcall(patch.get_method, H.T_Player, "Update", 0)
        m_pu = ok2 and m2 or nil
    end
    local ok_main = install_hook(m_pu, { postfix = on_player_update }, "Player.Update")
    H.has_player_hook = ok_main

    local ok_mu, m_mu = pcall(patch.get_method, H.T_Main, "Update", 1)
    if not ok_mu or not m_mu then
        local ok2, m2 = pcall(patch.get_method, H.T_Main, "Update", 0)
        m_mu = ok2 and m2 or nil
    end
    local ok_backup = install_hook(m_mu, { postfix = on_main_update }, "Main.Update")

    if not (ok_main or ok_backup) then
        error("两个 Update 挂点都没装上")
    end

    -- 自检：地带标记解析到几个（手机版应为属性，19 个左右）
    local zones_ok, zones_all = 0, 0
    for _, z in pairs(ctx.z) do
        zones_all = zones_all + 1
        if z then zones_ok = zones_ok + 1 end
    end

    inited = true
    pcall(mod.info, string.format(
        "[环境监控] 已启动 · 地带 %d/%d · 挂点 %s%s · 间隔 %ds",
        zones_ok, zones_all,
        ok_main and "Player.Update" or "-",
        ok_backup and " +Main.Update" or "",
        cfg.report_interval))
end

function setup()
    local ok, err = pcall(setup_impl)
    if not ok then
        pcall(mod.error, "[环境监控] 初始化失败: " .. tostring(err))
    end
end

-- ============================================================================
-- 卸载
-- ============================================================================
function mod.cleanup()
    inited = false
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
    sample = nil
    if reporter then reporter:reset() end
    pcall(mod.info, "[环境监控] 已卸载")
end

todo_list = { "setup" }
