-- ============================================================================
--  gui.lua —— 药水叠加 v2.3.1 游戏内面板（3 页，纯 mod.gui，零游戏符号）
--  依赖：ui_kit.lua（主题/图片/滚动/状态文件） + num_field.lua（数字输入/滑块）
--  纪律（19 章 §1.3 全 21 条）：
--    · 入口在 main.lua 的 mod.on_gui；本文件只被 require，不碰游戏方法；
--    · 每帧第一行 set_content_height；整帧 pcall；根上下文只发绝对控件；
--    · 长内容全部进 begin_scroll；只为可见行发绘制；旧加载器回落分页；
--    · 面板只改运行时状态（经 main.lua 的 bs_api），绝不写 TEFManager 设置。
--  视觉：羊皮纸底 + 紫罗兰强调色（panel/button/glyph/white 与 worldforge 共用，
--        但强调色/描边/行底色不同，收起后或标题栏一眼能和别的工坊面板区分开）。
-- ============================================================================
local K  = require("ui_kit")
local NF = require("num_field")

local GUI = {}
local M, ENV, G
local C = K.colors

-- 面板自己的状态（只落盘到私有目录的 buffstack_ui.txt）
local S = {
    page = 1, sub = 1,
    fold = { true, false, false, false, false },
    err_n = 0, err_last = "无",
    page_h = 380, g = 1, win_w = 0,
}
local TE = { key = nil, buf = nil }
local IMG = {}
local ASSET_TRIED, STYLE_DONE, SKIN_DONE, TITLE_DONE, PALETTE_DONE = false, false, false, false, false
local SKIN_G = nil

-- 本模组的强调色：羊皮纸底不变，只换「朱红 → 紫罗兰」这一组，避免和 worldforge 等
-- 工坊面板长得一模一样（玩家分不清哪个是哪个）。ui_kit 1.2 的 K.palette 只覆盖传入的键。
local BUFF_PALETTE = {
    accent = { 104, 58, 138, 255 },
    sel    = { 104, 58, 138, 255 },
    border = { 68, 42, 94, 255 },
    row_a  = { 226, 213, 196, 255 },
    row_b  = { 236, 225, 208, 255 },
    button = { 212, 193, 166, 255 },
    hover  = { 232, 215, 190, 255 },
    active = { 170, 139, 104, 255 },
}

local SCHEMA = {
    page    = { t = "int", lo = 1, hi = 3, d = 1 },
    sub     = { t = "int", lo = 1, hi = 5, d = 1 },
}
local STATE_PATH = "buffstack_ui.txt"

-- 5 个折叠组：键集合必须与 DEFAULTS 一一对应（GUI.spec_ok 会在测试里校验）
local GROUPS = {
    { title = "时长与上限", hint = "面板可直接输入 0：时长上限 0 = 不限，阈值 0 = 不启用。",
      keys = { "max_time_sec", "keep_sec", "per_buff_limits", "per_buff_cat_limits", "potion_delay_mult" } },
    { title = "类别规则", hint = "优先级：黑名单 > 免疫表 > 减益开关 > 强制位 > 类别开关。",
      keys = { "cat_buff", "cat_debuff", "cat_minion", "cat_pet", "cat_food", "cat_imbue", "cat_other",
               "stack_debuff", "immune_buffs" } },
    { title = "黑名单与强制叠加", hint = "blacklist_ids 填真实 ID、逗号分隔（如 94,6,396）；旧槽位填 ID+1，1 = 空。",
      keys = { "blacklist_ids",
               "blacklist_1", "blacklist_2", "blacklist_3", "blacklist_4", "blacklist_5",
               "blacklist_6", "blacklist_7", "blacklist_8", "blacklist_9", "blacklist_10",
               "allow_1", "allow_2", "allow_3", "allow_4", "allow_5", "allow_6" } },
    { title = "永久化", hint = "阈值单位秒；0 = 不启用。内置忽略项（Buff 396）永不永久化。",
      keys = { "perm_threshold_sec", "never_expire", "perm_only_buff", "persist_on_death", "persist_all_on_death" } },
    { title = "联机与日志", hint = "面板开关也在这里：关掉面板后请在 TEFManager 设置页开回。",
      keys = { "enabled", "host_only", "tick_interval", "config_reload_sec", "write_log", "debug_log",
               "announce", "self_check", "diag_report_cmd", "diag_slow_ms",
               "gui_enable", "gui_layout", "gui_slider" } },
}

-- 流式控件（button/checkbox/input_text/slider）的标签会按 1.0 字号整行绘制，
-- 太长会超出窗口宽度；这里统一压到 12 个汉字以内。
local LABEL = {
    enabled = "总开关", host_only = "联机仅房主", tick_interval = "刷新间隔(帧)",
    config_reload_sec = "自动重读(秒)", write_log = "写入日志", debug_log = "详细日志",
    self_check = "进世界自检", diag_report_cmd = "报告命令", diag_slow_ms = "慢域阈值(毫秒)",
    max_time_sec = "时长上限(秒,0=不限)", keep_sec = "永久维持(秒)",
    per_buff_limits = "单buff上限表", per_buff_cat_limits = "类别上限表",
    potion_delay_mult = "冷却倍率(%)", stack_debuff = "减益也叠加", immune_buffs = "免疫表",
    cat_buff = "类别:增益", cat_debuff = "类别:减益", cat_minion = "类别:仆从",
    cat_pet = "类别:宠物", cat_food = "类别:食物", cat_imbue = "类别:附魔", cat_other = "类别:其他",
    blacklist_ids = "黑名单真实ID(逗号分隔)", perm_threshold_sec = "永久阈值(秒,0=关)",
    never_expire = "永不消失", perm_only_buff = "只作用于增益", persist_on_death = "死亡保留",
    persist_all_on_death = "全部死亡保留", announce = "聊天栏播报",
    gui_enable = "显示面板", gui_layout = "面板布局", gui_slider = "数值滑块(1~1000)",
}
local UNITS = {
    max_time_sec = "秒", keep_sec = "秒", perm_threshold_sec = "秒", potion_delay_mult = "%",
    tick_interval = "帧", config_reload_sec = "秒", diag_slow_ms = "毫秒",
}

local function U(n) return (tonumber(n) or 0) * (S.g or 1) end
local function has(n) return K.has(n) end
local function click(label)
    if not has("button") then return false end
    local ok, r = pcall(G.button, label)
    return ok and r == true
end
local function txt(x, y, s, col, sc, bw)
    return K.txt(x, y, s, col or C.text, sc or 0.6, bw)
end
local function fill(x, y, w, h, col)
    return K.fill(x, y, w, h, col or C.row_b)
end
local function card(x, y, w, h, col)
    return K.card(x, y, w, h, col or C.row_b)
end
local function ibtn(x, y, w, h, label, border)
    return K.ibtn(x, y, w, h, label, border or 12)
end
local function set_cursor(x, y)
    if has("set_cursor") then pcall(G.set_cursor, x, y) end
end
local function save()
    pcall(K.state_save, S, SCHEMA, STATE_PATH)
end
local function clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end
local function key_label(k)
    if LABEL[k] then return LABEL[k] end
    local n = k:match("^blacklist_(%d+)$")
    if n then return "黑名单槽" .. n .. "(ID+1,1=空)" end
    n = k:match("^allow_(%d+)$")
    if n then return "强制槽" .. n .. "(ID+1,1=空)" end
    return k
end

-- ============================================================================
-- 一、静态一致性：参数页键集合 vs DEFAULTS / LIMITS / CHOICES
-- ============================================================================
function GUI.groups() return GROUPS end
function GUI.key_label(k) return key_label(k) end
function GUI.spec_ok()
    if type(ENV) ~= "table" or type(ENV.defaults) ~= "table" then return false, "ENV 未初始化" end
    local seen, n = {}, 0
    for gi, gr in ipairs(GROUPS) do
        if type(gr.keys) ~= "table" or #gr.keys == 0 then return false, "组 " .. gi .. " 没有键" end
        for _, k in ipairs(gr.keys) do
            if seen[k] then return false, "键重复：" .. k end
            seen[k] = true
            n = n + 1
            local def = ENV.defaults[k]
            if def == nil then return false, "DEFAULTS 里没有：" .. k end
            if type(def) == "number" and not ENV.limits[k] then return false, "LIMITS 里没有：" .. k end
            if k == "gui_layout" then
                local ok = false
                for _, v in ipairs(ENV.choices.gui_layout or {}) do if v == def then ok = true end end
                if not ok then return false, "CHOICES 与默认值不一致：" .. k end
            end
            if k == "gui_slider" and type(def) ~= "boolean" then
                return false, "gui_slider 必须是 SWITCH"
            end
        end
    end
    for k in pairs(ENV.defaults) do
        if not seen[k] then return false, "漏掉：" .. k end
    end
    return true, n
end

-- ============================================================================
-- 二、初始化 / 重置（只绑定，不调用任何游戏方法）
-- ============================================================================
function GUI.init(mod, env)
    M, ENV = mod, env
    G = type(mod) == "table" and mod.gui or nil
    K.init(mod, { state_path = STATE_PATH })
    NF.init(mod)
    TE.key, TE.buf = nil, nil
    IMG = {}
    ASSET_TRIED, STYLE_DONE, SKIN_DONE, TITLE_DONE, PALETTE_DONE = false, false, false, false, false
    SKIN_G = nil
    S.err_n, S.err_last, S.page_h = 0, "无", 380
    S.fold = { true, false, false, false, false }
    local st = K.state_load(SCHEMA, STATE_PATH)
    S.page = math.max(1, math.min(3, math.floor(tonumber(st.page) or 1)))
    S.sub = math.max(1, math.min(5, math.floor(tonumber(st.sub) or 1)))
    return GUI
end

function GUI.reset()
    NF.reset()
    TE.key, TE.buf = nil, nil
end

-- 固定窗口宽度（按 g_scale 缩放）；不设宽度时加载器会把面板撑满整块屏幕。
local function win_w(pr)
    local g = tonumber(pr.g) or 1
    local w = math.floor(470 * g)
    local sw = tonumber(pr.screen_w) or 0
    if sw > 0 and w > sw * 0.94 then w = math.floor(sw * 0.94) end
    if w < 340 then w = 340 end
    return w
end

-- ============================================================================
-- 三、主题 / 图片 / 容器
-- ============================================================================
local function ensure_assets()
    if not PALETTE_DONE then
        PALETTE_DONE = true
        if K.palette then K.palette(BUFF_PALETTE) end   -- 必须在 apply_style 之前
        STYLE_DONE = false
    end
    if not ASSET_TRIED then
        ASSET_TRIED = true
        K.load_theme()
        IMG.white = K.image_id("white")
        IMG.panel = K.image_id("panel")
        IMG.button = K.image_id("button")
        IMG.glyph = K.image_id("glyph")
    end
    if not STYLE_DONE then
        STYLE_DONE = K.apply_style() and true or false
    end
    if not SKIN_DONE or SKIN_G ~= S.g then
        SKIN_DONE = K.apply_skin(S.g) and true or false
        SKIN_G = S.g
    end
    if not TITLE_DONE and has("set_title") then
        local ok = pcall(G.set_title, "药水叠加 BuffStack", IMG.glyph and "药" or "BS")
        if not ok then pcall(G.set_title, "药水叠加 BuffStack") end
        TITLE_DONE = true
    end
end

local function use_scroll()
    return (ENV and ENV.get("gui_layout") ~= "分页") and has("begin_scroll") and has("end_scroll")
end

local function open_box(id, x, y, w, h, content_h)
    if use_scroll() then
        local _sx, _sy, vw, vh = K.scroll(id, x, y, w, h, w, content_h)
        -- ★ 滚动视口里 text_at/rect 的坐标是「相对内容」的，加载器会自动减去滚动偏移。
        --   这里绝不能把返回的 sx/sy（= 当前滚动量）再加到坐标里，否则内容不动、只有滚动条动。
        return 0, 0, vw, vh, true
    end
    return x, y, w, h, false
end

local function close_box(opened)
    if opened then K.scroll_end() end
end

-- ============================================================================
-- 四、参数页控件
-- ============================================================================
local function slider_range(k)
    if ENV.get("gui_slider") ~= true or not has("slider") then return nil end
    local _, hi = ENV.panel_bounds(k)
    hi = math.floor(tonumber(hi) or 0)
    if hi < 1 then return nil end
    if hi > 1000 then hi = 1000 end
    return 1, hi
end

-- 编辑态要占「输入框 + 确定 + 取消」三行；否则流式控件会把后面几行压在下面。
-- 这是 v2.3.1 修「确认/取消和其他按钮重叠」的核心：高度必须由布局预留，不能事后补。
local function editing_here(k)
    if TE.key == k then return true end
    if NF.is_editing and NF.is_editing() and NF.editing_key() == k then return true end
    return false
end

-- v2.3.2：编辑态改成自绘 3×4 数字键盘（仿玩家工坊），块高由 num_field 给；
-- 有滑块的行还要多留一行滑块（34）。
local function edit_block_h(k)
    return U((NF.EDIT_H or 116) + (slider_range(k) and 34 or 0))
end

local function field_h(k)
    if editing_here(k) then return edit_block_h(k) end
    local def = ENV.defaults[k]
    if type(def) == "boolean" then return U(38) end
    if type(def) == "number" then
        return (slider_range(k) and U(78) or U(46))
    end
    return U(44)
end

local function text_field(k, cur, x, y)
    local label = key_label(k)
    if TE.key == k then
        set_cursor(x, y)
        if has("input_text") then
            local ok, r = pcall(G.input_text, label, TE.buf or "")
            if ok and type(r) == "string" then
                TE.buf = r:gsub("[\r\n]", ""):sub(1, 200)
            end
        end
        if click("确定") then
            ENV.set(k, TE.buf or "")
            TE.key, TE.buf = nil, nil
        elseif click("取消") then
            TE.key, TE.buf = nil, nil
        end
        return
    end
    local shown = tostring(cur or "")
    if shown == "" then shown = "（空）" end
    set_cursor(x, y)
    if click(label .. "：" .. shown) then
        if NF.reset then NF.reset() end              -- 同一个面板只允许一个编辑框
        TE.key, TE.buf = k, tostring(cur or "")
    end
end

local function choice_field(k, cur, x, y)
    local label = key_label(k)
    local vals = (ENV.choices and ENV.choices[k]) or {}
    if #vals == 0 then txt(x, y, label .. "：" .. tostring(cur)); return end
    if ibtn(x, y, U(420), U(32), label .. "：" .. tostring(cur), 10) then
        local idx = 1
        for i, v in ipairs(vals) do if v == cur then idx = i end end
        idx = idx % #vals + 1
        ENV.set(k, vals[idx])
    end
end

local function draw_field(k, y, vw)
    local cur = ENV.get(k)
    local def = ENV.defaults[k]
    local x = U(6)
    local w = vw - U(12)
    if type(def) == "boolean" then
        fill(x, y, w, U(32), C.row_b)
        local label = key_label(k)
        if has("checkbox") then
            set_cursor(U(12), y + U(4))
            local ok, nv = pcall(G.checkbox, label, cur == true)
            if ok and nv ~= cur then ENV.set(k, nv == true) end
        else
            txt(x + U(6), y + U(6), label .. "：" .. (cur and "开" or "关"), C.text, 0.55, w - U(12))
        end
    elseif type(def) == "number" then
        local lo, hi = ENV.panel_bounds(k)
        local slo, shi = slider_range(k)
        local rh = editing_here(k) and edit_block_h(k) or (slo and U(72) or U(40))
        fill(x, y, w, rh, C.row_b)
        local label = key_label(k)
        local nf_opts = {
            x = U(12), y = slo and (y + U(34)) or (y + U(4)), w = vw - U(24), s = S.g,
            colors = { box = C.row_a, accent = C.accent, text = C.text, muted = C.muted },
            on_default = function(kk)
                local fn = ENV.default_ui
                ENV.set(kk, fn and fn(kk) or ENV.defaults[kk])
            end,
        }
        if slo then
            set_cursor(U(12), y + U(2))
            NF.slider(label, cur, slo, shi, function(n) ENV.set(k, n) end)
            set_cursor(U(12), y + U(34))
            NF.field(label, k, cur, lo, hi, UNITS[k] or "", function(_, n) ENV.set(k, n) end, nf_opts)
        else
            set_cursor(U(12), y + U(4))
            NF.field(label, k, cur, lo, hi, UNITS[k] or "", function(_, n) ENV.set(k, n) end, nf_opts)
        end
        -- 点数字框时把字符串编辑态关掉（两个编辑框同时画按钮就是截图里的“取消”重叠）
        if NF.is_editing and NF.is_editing() and NF.editing_key() == k and TE.key ~= nil then
            TE.key, TE.buf = nil, nil
        end
    elseif k == "gui_layout" then
        fill(x, y, w, U(34), C.row_b)
        choice_field(k, cur, U(12), y + U(3))
    else
        fill(x, y, w, editing_here(k) and edit_block_h(k) or U(34), C.row_b)
        text_field(k, cur, U(12), y + U(3))
    end
end

local function draw_group(gi, y, vw)
    local gr = GROUPS[gi]
    local open = S.fold[gi] ~= false
    local head = (open and "收起 " or "展开 ") .. gi .. "、" .. gr.title
    fill(U(6), y, vw - U(12), U(34), C.row_a)
    if ibtn(U(10), y + U(2), vw - U(20), U(30), head, 10) then
        S.fold[gi] = not open
        save()
        open = S.fold[gi] ~= false
    end
    y = y + U(38)
    if not open then return y end
    if gr.hint then
        txt(U(12), y, gr.hint, C.muted, 0.5, vw - U(24))
        y = y + U(24)
    end
    for _, k in ipairs(gr.keys) do
        draw_field(k, y, vw)
        y = y + field_h(k)
    end
    return y
end

local function params_height()
    local h = U(10)
    for gi = 1, #GROUPS do
        h = h + U(38)
        if S.fold[gi] ~= false then
            if GROUPS[gi].hint then h = h + U(24) end
            for _, k in ipairs(GROUPS[gi].keys) do h = h + field_h(k) end
        end
    end
    return h + U(20)
end

-- 分页模式（含没有 begin_scroll 的老加载器）：只读绝对控件，绝不向根上下文发流式控件。
local function draw_params_paged(sx, sy, vw)
    local y = sy + U(4)
    if ibtn(sx + U(6), y, U(120), U(30), "上一组", 10) then S.sub = (S.sub - 2) % #GROUPS + 1; save() end
    if ibtn(sx + U(132), y, U(120), U(30), "下一组", 10) then S.sub = S.sub % #GROUPS + 1; save() end
    y = y + U(40)
    txt(sx + U(6), y, "分页模式：第 " .. S.sub .. "/" .. #GROUPS .. " 组（" .. GROUPS[S.sub].title .. "）",
        C.muted, 0.55, vw - U(12))
    y = y + U(26)
    local gr = GROUPS[S.sub]
    if gr.hint then
        txt(sx + U(6), y, gr.hint, C.muted, 0.5, vw - U(12))
        y = y + U(24)
    end
    for _, k in ipairs(gr.keys) do
        local v = ENV.get(k)
        if type(v) == "boolean" then v = v and "开" or "关" end
        txt(sx + U(6), y, key_label(k) .. " = " .. tostring(v), C.text, 0.52, vw - U(12))
        y = y + U(24)
    end
    txt(sx + U(6), y + U(4), "本机没有滚动容器：参数页只读，请在 TEFManager 设置页修改。",
        C.warn, 0.5, vw - U(12))
end

local function draw_params(sx, sy, vw, scroll)
    if not scroll then draw_params_paged(sx, sy, vw); return end
    set_cursor(U(6), 0)
    local y = sy + U(4)
    for gi = 1, #GROUPS do y = draw_group(gi, y, vw) end
end

-- ============================================================================
-- 五、四个页面
-- ============================================================================
local function page_status(sx, sy, vw)
    local st = ENV.stats()
    local blist = ENV.buffs() or {}
    local ignored_n = 0
    for i = 1, #blist do if blist[i].ignored then ignored_n = ignored_n + 1 end end
    local on = ENV.get("enabled") == true
    local live = on and not st.readonly
    local y = sy + U(4)
    card(sx + U(4), y, vw - U(8), U(76), C.row_b)
    txt(sx + U(14), y + U(8), "药水叠加 · " .. (on and "运行中" or "已停止"),
        on and C.ok or C.bad, 0.7, vw - U(150))
    txt(sx + U(14), y + U(32), "当前 " .. tostring(st.buff_count) .. " 个效果 · 槽位 " .. tostring(st.cap) ..
        " · " .. (st.readonly and "联机只读" or "可写"), C.muted, 0.5, vw - U(150))
    if ibtn(sx + vw - U(136), y + U(20), U(122), U(32), on and "关闭总开关" or "开启总开关", 10) then
        ENV.set("enabled", not on)
    end
    y = y + U(84)

    local th = ENV.get("perm_threshold_sec") or 0
    local rule
    if ENV.get("never_expire") == true then rule = "永不消失（全部增益转永久）"
    elseif th > 0 then rule = "剩余 >= " .. th .. " 秒转永久（仅增益=" .. tostring(ENV.get("perm_only_buff")) .. "）"
    else rule = "关闭（阈值 0）" end
    local lim = ENV.get("max_time_sec") or 0
    local lim_s = (lim > 0) and (tostring(lim) .. " 秒") or "不限"
    local rows = {
        { "叠加是否生效", live and "生效" or ("未生效" .. (st.readonly and "（联机客机：只读）" or "")), live and C.ok or C.warn },
        { "永久化规则", rule, C.text },
        { "叠加时长上限", lim_s, C.text },
        { "内置忽略项", tostring(ignored_n) .. " 个（永不叠加 / 永久化）", C.muted },
        { "钩子路径", tostring(st.hook_mode), C.muted },
        { "快照帧", tostring(st.snap_tick), C.muted },
    }
    for i = 1, #rows do
        local ry = y + (i - 1) * U(34)
        fill(sx + U(4), ry, vw - U(8), U(32), (i % 2 == 0) and C.row_a or C.row_b)
        txt(sx + U(14), ry + U(7), rows[i][1], C.muted, 0.52, vw * 0.38)
        txt(sx + vw * 0.42, ry + U(7), rows[i][2], rows[i][3] or C.text, 0.52, vw * 0.54)
    end
    y = y + #rows * U(34) + U(8)

    if ibtn(sx + U(8), y, U(112), U(32), "刷新快照", 10) then ENV.refresh_snapshot() end
    if ibtn(sx + U(128), y, U(112), U(32), "重读设置", 10) then ENV.action("reload") end
    y = y + U(42)
    local dn, dlast = ENV.domain_errors()
    local last = S.err_last
    if dn and dn > 0 and dlast then last = dlast end
    txt(sx + U(8), y, "上次错误：" .. tostring(last) .. "（面板异常 " .. S.err_n .. " 次 / 功能域 " .. tostring(dn) .. " 次）",
        (S.err_n > 0 or (dn or 0) > 0) and C.warn or C.muted, 0.5, vw - U(16))
    y = y + U(24)
    txt(sx + U(8), y, "说明：面板只改运行时状态，不改 TEFManager 设置；重读设置会放弃面板改动。",
        C.muted, 0.5, vw - U(16))
end

local function page_actions(sx, sy, vw, scroll)
    local y = sy + U(4)
    local half = math.floor((vw - U(28)) / 2)
    local function B(label, act, x)
        if ibtn(sx + x, y, half, U(32), label, 10) then ENV.action(act) end
    end
    B("清空减益", "clear_debuffs", U(8))
    B("全部增益转永久", "perm_all", U(8) + half + U(12))
    y = y + U(38)
    B("重读设置", "reload", U(8))
    B("自检", "self_check", U(8) + half + U(12))
    y = y + U(38)
    if ibtn(sx + U(8), y, vw - U(16), U(32), "清空面板日志", 10) then ENV.action("clear_log") end
    y = y + U(44)
    txt(sx + U(8), y, "最近 30 行日志（运行时环形缓存；写文件需打开 write_log）", C.text, 0.55, vw - U(16))
    y = y + U(24)
    local logs = ENV.logs() or {}
    local first = math.max(1, #logs - (scroll and 29 or 7))
    for i = first, #logs do
        local e = logs[i]
        local line = "[" .. tostring(e.kind) .. "] " .. tostring(e.msg)
        fill(sx + U(6), y - U(2), vw - U(12), U(22), (i % 2 == 0) and C.row_a or C.row_b)
        txt(sx + U(12), y, line, (e.kind == "error") and C.bad or C.muted, 0.48, vw - U(24))
        y = y + U(24)
    end
    if #logs == 0 then
        card(sx + U(4), y, vw - U(8), U(44), C.row_b)
        txt(sx + U(14), y + U(12), "（还没有日志；打开 write_log 可写文件）", C.muted, 0.5, vw - U(28))
        y = y + U(48)
    end
    return y
end

local function actions_height()
    local logs = #(ENV.logs() or {})
    return U(210) + math.min(logs, 30) * U(24) + U(24)
end

-- ============================================================================
-- 六、每帧入口
-- ============================================================================
local function draw(pr)
    S.g = tonumber(pr.g) or 1
    local ww = S.win_w
    if not ww or ww <= 0 then ww = win_w(pr) end
    local w = ww - U(24)
    local page_h = math.max(U(280), tonumber(pr.budget) or 380)
    ensure_assets()

    -- 标题 + 副标题（根上下文只用绝对控件；坐标全部按 g_scale 缩放）
    -- ★ v2.3.2：版本号取运行时 meta（以前是硬编码 v2.3.1，升版本后标题栏会对不上）
    local ver = tostring((M and M.meta and M.meta.version) or "?")
    txt(U(10), U(6), "v" .. ver .. " · 时长叠加", C.accent, 0.64, w - U(20))
    local n_buff = #(ENV.buffs() or {})
    txt(U(10), U(25), "第 " .. S.page .. "/3 页 · " .. (use_scroll() and "滚动" or "分页") ..
        " · 当前 " .. n_buff .. " 个效果" .. (has("begin_scroll") and "" or " · 本机不支持滚动"),
        C.muted, 0.5, w - U(20))

    -- 3 页导航（图片按钮 + 选中强调色下划线；v2.3.1 起删掉时间轴页）
    local names = { "状态", "参数", "一键" }
    local gap = U(6)
    local nw = math.floor((w - gap * 2) / 3)
    for i = 1, 3 do
        local bx = U(10) + (i - 1) * (nw + gap)
        if ibtn(bx, U(40), nw, U(32), names[i], 10) then
            S.page = i
            save()
        end
        if S.page == i then
            fill(bx, U(74), nw, U(3), C.accent)
        end
    end

    local vx, vy, vw, vh = U(10), U(84), w - U(20), page_h - U(94)
    if vh < U(80) then vh = U(80) end
    local opened = false
    local sx, sy
    if S.page == 1 then
        sx, sy, vw, vh, opened = open_box("bs1", vx, vy, vw, vh, U(420))
        page_status(sx, sy, vw)
    elseif S.page == 2 then
        sx, sy, vw, vh, opened = open_box("bs2", vx, vy, vw, vh, params_height())
        draw_params(sx, sy, vw, opened)
    else
        sx, sy, vw, vh, opened = open_box("bs3", vx, vy, vw, vh, actions_height())
        page_actions(sx, sy, vw, opened)
    end
    close_box(opened)
end

function GUI.on_gui()
    if type(M) ~= "table" then return end
    G = M.gui
    if type(G) ~= "table" and type(G) ~= "userdata" then return end

    -- ★ 每帧第一行：先按上一帧的高度声明（覆盖而非累加），再测屏修正。
    if type(G.set_content_height) == "function" then
        pcall(G.set_content_height, S.page_h)
    end
    local ok0, pr = pcall(K.probe)
    if not ok0 or type(pr) ~= "table" then
        pr = { g = 1, screen_w = 0, screen_h = 0, budget = 380 }
    end
    S.g = tonumber(pr.g) or 1
    -- 固定窗口宽度（否则加载器默认撑满整块屏幕；set_width 下一帧生效）
    local ww = win_w(pr)
    if S.win_w ~= ww then
        S.win_w = ww
        if type(G.set_width) == "function" then pcall(G.set_width, ww) end
    end
    local ph = math.max(U(280), tonumber(pr.budget) or 380)
    if ph ~= S.page_h then
        S.page_h = ph
        if type(G.set_content_height) == "function" then pcall(G.set_content_height, ph) end
    end
    local ok, err = pcall(draw, pr)
    if not ok then
        S.err_n = S.err_n + 1
        S.err_last = tostring(err)
        pcall(G.set_content_height, S.page_h)
        pcall(K.txt, U(10), U(8), K.fit("面板出错：" .. S.err_last, ww - U(20), 0.6), C.bad, 0.6, ww - U(20))
    end
end

return GUI
