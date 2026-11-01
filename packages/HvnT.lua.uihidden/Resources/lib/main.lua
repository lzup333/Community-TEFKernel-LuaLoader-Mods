--[[
    UI隐藏（Hide UI）
    作者：HvnT

    历史修复：加载地图到 100% 时卡死

    原因（源码依据）：
      GUIMap.DrawToMap() 上带有
          [Il2CppSetOption(Option.ArrayBoundsChecks, false)]
          [Il2CppSetOption(Option.NullChecks, false)]
          [Il2CppSetOption(Option.StripStaticGuards, true)]
      这是 IL2CPP 的性能关键路径，关闭了全部安全检查。
      在地图生成/加载过程中挂钩打断它，会破坏内部状态 → 卡死。

      GUIMap.DrawMap() 同样是地图流程的一部分，
      跳过它可能导致加载无法收尾。

    处理：
      * 完全移除 GUIMap 的 DrawMap / DrawToMap 钩子
      * 「小地图画面」开关一并移除
      * 其余功能不变

    新增项（均经过实测确认）：
      * 手机显示(右侧信息栏)   GUIAccessoryInfo            ✅ 实测生效
      * 对话键 / 小地图键      RightSideHUDAnchorUpdator
                               .DrawMiniChatButton / .DrawMinimapButton   ✅ 实测生效
      * 设置键                 GUISettings                 ✅ 实测生效
      * 大地图键               无法隐藏 —— 见下
      * 光标                   无法隐藏 —— 见下

    无法隐藏项（源码与实测依据，非推测）：
      大地图键：
        * RightSideHUDAnchorUpdator.DrawMapButton 挂钩后无效果（已实测）
        * GUIMap 中不存在任何 Draw*Button 方法
        * 唯一可能的 GUIMap.DrawMap() 挂钩会导致加载卡死（已实测）
        * 改 GUIMap.MapButtonScale 需要实例，而 GUIInstance.Active 读出为 nil
      光标：
        * 全库无任何 Cursor 绘制类
        * GUIZoom 实为缩放控制器，挂钩导致世界加载卡死
--]]

mod.meta = { pkg_id = "HvnT.lua.uihidden", version = "1.3.5", version_code = 135 }

local TAG = "[UI隐藏]"
local P = mod.patch
local g = mod.gui

local BUTTON_TEXT = "UI"

local S = {
    life    = true,
    inputs  = true,
    hotbar  = false,
    misc    = true,
    chat    = false,
    info    = false,
    paging  = false,
    setting = false,
    bag     = false,
    minimap = false,
}

local installed = 0
local hooks = {}
local inited = false
local report = {}

local function log(fmt, ...)
    mod.info(TAG .. " " .. string.format(fmt, ...))
end

local KEYS = { "life", "inputs", "hotbar", "misc", "chat",
               "info", "paging", "setting", "bag", "minimap" }

local function save_state()
    local parts = {}
    for _, k in ipairs(KEYS) do
        parts[#parts + 1] = k .. "=" .. (S[k] and "1" or "0")
    end
    pcall(mod.write_file, "ui_state.txt", table.concat(parts, "\n") .. "\n")
end

local function load_state()
    local ok, txt = pcall(mod.read_file, "ui_state.txt")
    if not (ok and type(txt) == "string") then return end
    for k, v in txt:gmatch("(%w+)=(%d)") do
        if S[k] ~= nil then S[k] = (v == "1") end
    end
end

-- 按命名空间依次尝试获取类型。
-- 注意：Main 在 "Terraria" 命名空间下，用空命名空间取不到。
-- 依据：更好的体验 源码 P.get_type("Terraria", "Main")
local TYPE_NS = { "", "Terraria", "Terraria.GameContent", "Terraria.IO",
                  "Terraria.GameContent.Events", "Microsoft.Xna.Framework" }

local function get_global_type(name)
    if type(P) ~= "table" then return nil end
    for _, ns in ipairs(TYPE_NS) do
        local ok, t = pcall(P.get_type, ns, name)
        if ok and t and P.is_valid(t) then return t end
    end
    return nil
end

local function hook_draw(class_name, getter, label, report_key)
    local t = get_global_type(class_name)
    if not t then
        log("未找到类型 %s（%s）", class_name, label)
        if report_key then report[report_key] = "找不到" end
        return false
    end
    local m = P.get_method(t, "Draw", 0)
    if not (m and P.is_valid(m)) then
        m = P.get_method(t, "Draw")
    end
    if not (m and P.is_valid(m)) then
        log("%s 没有 Draw()（%s）", class_name, label)
        if report_key then report[report_key] = "无Draw" end
        return false
    end
    local ok, hook = pcall(P.install_hook, m, {
        prefix = function() return getter() end
    })
    if not ok or not hook then
        log("%s.Draw 钩子失败：%s", class_name, tostring(hook))
        if report_key then report[report_key] = "钩子失败" end
        return false
    end
    hooks[#hooks + 1] = hook
    installed = installed + 1
    log("已接管 %s.Draw（%s）", class_name, label)
    if report_key then report[report_key] = "OK" end
    return true
end

-- 小地图相关钩子已移除
-- 原因：GUIMap.DrawToMap 带 Il2CppSetOption 关闭安全检查，挂钩会导致地图加载卡死

--- 对话键 / 小地图键
-- 依据：RightSideHUDAnchorUpdator.cs
--   private static void DrawMinimapButton()
--   private static void DrawMiniChatButton()
--   private static void DrawMapButton()
--   public  static void HandleTopRightState()   ← 统一调度
-- 策略：先逐个挂三个 private static 绘制方法（无参数）；
--       全部失败再挂 HandleTopRightState。
local function hook_top_right_buttons()
    local t = get_global_type("RightSideHUDAnchorUpdator")
    if not t then
        log("未找到类型 RightSideHUDAnchorUpdator（三键）")
        report.paging = "找不到"
        return false
    end

    local report_paging_names = {
        "DrawMinimapButton",
        "DrawMiniChatButton",
    }
    -- 说明：不再挂钩 DrawMapButton。
    -- 原因（实测）：单独跳过 DrawMapButton 会破坏同批次按钮的点击判定，
    -- 表现为隐藏「对话/小地图」后大地图键点不到。且该键本就无法隐藏。
    local okCount = 0
    for _, mname in ipairs(report_paging_names) do
        local m = P.get_method(t, mname, 0)
        if not (m and P.is_valid(m)) then
            m = P.get_method(t, mname)
        end
        if m and P.is_valid(m) then
            local ok, hook = pcall(P.install_hook, m, {
                prefix = function() return S.paging end
            })
            if ok and hook then
                hooks[#hooks + 1] = hook
                installed = installed + 1
                okCount = okCount + 1
                log("已接管 %s.%s", "RightSideHUDAnchorUpdator", mname)
            else
                log("%s 钩子失败：%s", mname, tostring(hook))
            end
        else
            log("%s 取不到方法句柄", mname)
        end
    end

    if okCount > 0 then
        report.paging = "OK"
        return true
    end

    -- 全部失败，退回统一入口
    local mh = P.get_method(t, "HandleTopRightState", 0)
    if not (mh and P.is_valid(mh)) then
        mh = P.get_method(t, "HandleTopRightState")
    end
    if mh and P.is_valid(mh) then
        local ok, hook = pcall(P.install_hook, mh, {
            prefix = function() return S.paging end
        })
        if ok and hook then
            hooks[#hooks + 1] = hook
            installed = installed + 1
            report.paging = "OK(HandleTopRightState)"
            log("已接管 HandleTopRightState（三键统一入口）")
            return true
        end
    end

    report.paging = "钩子失败"
    log("三键：三个绘制方法与统一入口均无法挂钩")
    return false
end

-- 小地图本体（右上角地图画面）
-- 依据：GUIMap.DrawMap() 绘制小地图；MapButtonScale / ActiveFrameStyle /
--       BackingMiniTextureId 等字段均在同一类中。
--
-- 为什么需要保护：
--   直接挂钩 GUIMap.DrawMap 会导致「世界加载到 100% 卡死」。
--   原因是加载过程中本方法也在参与收尾，被跳过会破坏内部状态。
--
-- 这次改为「检测玩家是否已进入世界」，不再用固定帧数猜测。
--   依据（来源：更好的体验 源码用法）：
--       Main.player           —— static 字段，玩家数组
--       Main.get_myPlayer()   —— static 方法，返回 myPlayer 索引
--   在世界外取不到有效玩家实例；进入世界后可以取到。
--   只有取到玩家实例时，才允许跳过绘制。
local map_hooked = false

-- 取当前玩家实例是否可用（等价于「是否已在世界中」）
local function in_world()
    if type(P) ~= "table" then return false end
    local mt = get_global_type("Main")
    if not mt then return false end

    local fPlayer = P.get_field(mt, "player")
    if not (fPlayer and P.is_valid(fPlayer)) then return false end

    local mMy = P.get_method(mt, "get_myPlayer", 0)
    if not (mMy and P.is_valid(mMy)) then
        mMy = P.get_method(mt, "get_myPlayer")
    end
    if not (mMy and P.is_valid(mMy)) then return false end

    local okIdx, idx = pcall(P.invoke, mMy, nil)
    if not (okIdx and type(idx) == "number") then return false end
    if idx < 0 then return false end

    local okArr, arr = pcall(P.get_field_value, fPlayer, nil, "object")
    if not (okArr and arr) then return false end

    local okAt, inst = pcall(P.array_at, arr, idx)
    if not okAt then return false end
    return inst ~= nil
end

local function hook_minimap_body()
    local t = get_global_type("GUIMap")
    if not t then
        log("未找到类型 GUIMap（小地图本体）")
        report.minimap = "找不到"
        return false
    end
    local m = P.get_method(t, "DrawMap", 0)
    if not (m and P.is_valid(m)) then
        m = P.get_method(t, "DrawMap")
    end
    if not (m and P.is_valid(m)) then
        log("GUIMap 没有 DrawMap()（小地图本体）")
        report.minimap = "无DrawMap"
        return false
    end
    local ok, hook = pcall(P.install_hook, m, {
        prefix = function()
            -- 未开启隐藏，直接放行
            if not S.minimap then return false end
            -- 未进入世界，放行（保护加载流程）
            if not in_world() then return false end
            return true
        end
    })
    if ok and hook then
        hooks[#hooks + 1] = hook
        installed = installed + 1
        map_hooked = true
        report.minimap = "OK"
        log("已接管 GUIMap.DrawMap（小地图本体，带加载保护）")
        return true
    end
    report.minimap = "钩子失败"
    log("GUIMap.DrawMap 钩子失败：%s", tostring(hook))
    return false
end

local function hook_settings_bool()
    local t = get_global_type("GUISettings")
    if not t then
        report.setting = report.setting or "找不到"
        return false
    end
    local m = P.get_method(t, "Draw", 0)
    if not (m and P.is_valid(m)) then
        m = P.get_method(t, "Draw")
    end
    if not (m and P.is_valid(m)) then
        report.setting = report.setting or "无Draw"
        return false
    end
    local ok, hook = pcall(P.install_hook, m, {
        prefix = function() return S.setting end
    })
    if ok and hook then
        hooks[#hooks + 1] = hook
        installed = installed + 1
        report.setting = "OK"
        log("已接管 GUISettings.Draw（设置键）")
        return true
    end
    report.setting = report.setting or "钩子失败"
    return false
end

local function toggle(label, key)
    local ok, v = pcall(g.checkbox, label, S[key])
    if ok and type(v) == "boolean" and v ~= S[key] then
        S[key] = v
        save_state()
        log("%s -> %s", key, v and "隐藏" or "显示")
    end
end

function on_gui()
if type(g) ~= "table" then return end

    pcall(g.set_visible, true)

    if not inited then
        inited = true
        pcall(g.set_title, "UI隐藏", BUTTON_TEXT)
        pcall(g.set_width, 320)
        log("面板初始化，按钮文字 = %s", BUTTON_TEXT)
    end

    pcall(g.text, "勾选 = 隐藏该项")
    pcall(g.separator)

    toggle("生命值 / 魔力值", "life")
    toggle("操作按键", "inputs")
    toggle("增益 / 弹药 / 货币", "misc")
    toggle("聊天", "chat")
    toggle("手机显示", "info")

    if report.paging == "OK" then
        toggle("对话 / 小地图", "paging")
    else
        pcall(g.text, "对话 / 小地图：" .. tostring(report.paging or "未测试"))
    end

    if report.setting == "OK" then
        toggle("设置", "setting")
    else
        pcall(g.text, "设置：" .. tostring(report.setting or "未测试"))
    end

    if report.minimap == "OK" then
        toggle("地图", "minimap")
    else
        pcall(g.text, "地图：" .. tostring(report.minimap or "未测试"))
    end

    if report.bag == "OK" then
        toggle("背包开关", "bag")
    else
        pcall(g.text, "背包开关：" .. tostring(report.bag or "未测试"))
    end

    toggle("快捷栏 / 背包", "hotbar")

    pcall(g.text, string.format("已接管 %d 项", installed))

    pcall(g.text, "除操作按键以外的UI隐藏后都无法点击")
    local okA, a = pcall(g.button, "全部隐藏")
    if okA and a == true then
        for _, k in ipairs(KEYS) do S[k] = true end
        save_state()
        log("全部隐藏")
    end
    local okB, b = pcall(g.button, "全部显示")
    if okB and b == true then
        for _, k in ipairs(KEYS) do S[k] = false end
        save_state()
        log("全部显示")
    end
end

mod.on_gui = on_gui
_G.on_gui = on_gui

function setup()
    installed = 0
    report = {}
    load_state()

    log("=======================================")
    log("UI隐藏（Hide UI）v1.3.5  by HvnT")
    log("=======================================")

    hook_draw("GUIHearts", function() return S.life end, "生命值")
    hook_draw("GUIMana",   function() return S.life end, "魔力值")
    hook_draw("GUIVirtualInputController", function() return S.inputs end, "操作按键")
    hook_draw("GUIBuffs", function() return S.misc end, "增益图标")
    hook_draw("GUIAmmo",  function() return S.misc end, "弹药")
    hook_draw("GUICoins", function() return S.misc end, "货币")
    hook_draw("GUIChat_Overlay", function() return S.chat end, "聊天浮层")
    hook_draw("GUIChat_Mini",    function() return S.chat end, "迷你聊天")
    hook_draw("GUIHotbar",    function() return S.hotbar end, "快捷栏")
    hook_draw("GUIInventory", function() return S.hotbar end, "背包")

    -- 手机显示（右侧信息栏）
    hook_draw("GUIAccessoryInfo", function() return S.info end, "手机显示/信息栏", "info")

    -- 对话 / 小地图 / 大地图 三键
    -- 修正（源码依据 RightSideHUDAnchorUpdator.cs）：
    --     private static void DrawMinimapButton()    ← 小地图键
    --     private static void DrawMiniChatButton()   ← 对话键
    --     private static void DrawMapButton()        ← 大地图键
    --     public  static void HandleTopRightState()  ← 三者统一调度
    -- 之前用的 GUIStatusMenu / GUIPageIcons 都不是这三键，故未生效。
    hook_top_right_buttons()

    -- 设置键（白色扳手）
    -- 修正：GUISettingsOverlay 是「设置面板本体」，挂它只是面板不显示
    -- 正确目标 GUISettings —— 含 settingsButtonScale（设置按钮）
    -- 注意其 Draw() 返回 bool
    hook_settings_bool()

    -- 背包开关按键
    -- 依据：GUIPageIcons.Draw 负责页面图标（含背包开关键）
    -- 早期误挂此钩子时曾隐藏掉背包开关键，反证挂钩位置正确
    hook_draw("GUIPageIcons", function() return S.bag end, "背包开关按键", "bag")

    -- 小地图本体（右上角地图画面，带加载保护）
    hook_minimap_body()

    -- 光标：源码中没有任何 Cursor 绘制类。
-- GUIZoom 已确认是「缩放控制器」（含 CursorInputLayer / UpdatePinchZoom /
-- DefaultWorldZoomScale），挂钩会导致世界加载越来越卡直至卡死，因此禁用。
-- 结论：光标无法通过拦截 Draw 隐藏。
report.cursor = "不支持"

    log("---------------------------------------")
    log("共接管 %d 项", installed)
    log("信息栏=%s 三键=%s 设置键=%s 光标=%s",
        tostring(report.info), tostring(report.paging),
        tostring(report.setting), tostring(report.cursor))
end

function mod.cleanup()
    for i = 1, #hooks do
        pcall(function()
            if hooks[i] and hooks[i].remove then hooks[i]:remove() end
        end)
    end
    hooks = {}
    log("已卸载")
end

todo_list = { "setup" }