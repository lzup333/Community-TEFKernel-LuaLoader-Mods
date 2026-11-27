-- bag_ui.lua
-- 多功能大背包：界面层（mod.gui 全自绘）
--   风格对齐「你已是完全之龙了」：深蓝底 + 亮字
--   做法参考鬼妖村正：透明皮肤 + 空标题 + 全透明 style，
--   内核标题条（连同上左角那个 v）彻底不画，右上角 × 由我们自己画
-- ---------------------------------------------------------------------------

local UI = {}

local D = nil
local get_player = nil
local on_close = nil
local get_effect = nil      -- 取 bag_effect 模块（用于 buff 图标开关）

-- 每个页签管一到多个储物区（药水页细分：增益药水 / 食物 / 药剂）
local TABS = {
    { key = "misc",    label = "物品",   sections = { "misc" } },
    { key = "craft",   label = "制作站", sections = { "craft" } },
    { key = "potion",  label = "药水",   sections = { "buffpot", "food", "flask" } },
    { key = "station", label = "增益站", sections = { "station" } },
    { key = "banner",  label = "旗帜",   sections = { "banner" } },
}

local last_row_err = ""
local tab_index = 1
local last_result = ""
-- 每个页签各记一份搜索词
local search_kw = {}

-- ---------- 尺寸（比上一版短一截：4 排 + 紧凑行距） ----------
local W        = 682   -- v2.0.10：窗口宽 = 搜索框宽（658 -> 682，+24）
local H_TITLE  = 38
local TAB_Y    = 12
local TAB_H    = 36
local TAB_W    = 124
local TAB_GAP  = 6
-- 搜索框：input_text 的落点 y ≈ 调用时的内容区高度，所以临时把高度设成
-- SEARCH_FAKE_H，它就正好排在这一行；调用完立刻恢复真实高度
local SEARCH_FAKE_H = 54
local SEARCH_TOP    = 54
local SEARCH_H      = 40
local STATUS_Y      = SEARCH_TOP + 32            -- 数量提示紧贴搜索框下面（内核输入框本身带下内边距，从 +42 收到 +32）
local LIST_Y        = STATUS_Y + 22
local ROW_H    = 46
local LIST_H   = ROW_H * 4          -- 只露 4 排，正好占满
local BTN_Y    = LIST_Y + LIST_H + 8
local BTN_H    = 36
local HINT_Y   = BTN_Y + BTN_H + 6
local H        = HINT_Y + 24

-- ---------- 配色：与「你已是完全之龙了」一致 ----------
local C = {
    panel  = { 33, 43, 102, 245 },
    title  = { 50, 60, 130, 255 },
    btn    = { 63, 80, 150, 255 },
    btnHot = { 84, 109, 183, 255 },
    row    = { 46, 58, 118, 220 },
    text   = { 235, 237, 229, 255 },
    dim    = { 168, 178, 205, 255 },
    accent = { 120, 180, 255, 255 },
    green  = { 150, 240, 160, 255 },
    close  = { 168, 64, 72, 255 },
    -- 搜索框：比面板亮一档，像完全之龙那种醒目的输入条
    search = { 92, 118, 196, 255 },
}

local styled = false
local opened_frames = 0
local pos_set = false      -- 窗口位置是否已设过

-- 由 bag_core 在「从隐藏切到显示」那一帧调用，重置保护期计数
function UI.on_open()
    opened_frames = 0
end

function UI.init(data, player_fn, close_fn, effect_fn)
    D = data
    get_player = player_fn
    on_close = close_fn
    get_effect = effect_fn
end

function UI.say(s)
    last_result = tostring(s)
end

-- ---------- 小工具 ----------
local function text_w(s, scale)
    local sc = scale or 1
    local n_cn, n_asc = 0, 0
    local ok = pcall(function()
        for _, ch in utf8.codes(s) do
            if ch < 128 then n_asc = n_asc + 1 else n_cn = n_cn + 1 end
        end
    end)
    if not ok then
        n_asc = #s
        n_cn = 0
    end
    return (n_cn * 12.5 + n_asc * 7.5) * sc
end

-- 截断必须按 UTF-8 字符边界：按字节切会把汉字劈成半个，
-- text_at 收到无效 UTF-8 就整个字符串渲染不出来（这就是「名字全空白」的原因）
local function short(s, n)
    if not s or s == "" then return "?" end
    if type(utf8) ~= "table" or type(utf8.codes) ~= "function" then
        return s          -- 拿不到 utf8 就不截断，宁长勿空
    end
    local cnt = 0
    local cut = nil
    local ok = pcall(function()
        for _ in utf8.codes(s) do
            cnt = cnt + 1
            if cnt > n then
                cut = utf8.offset(s, n + 1)
                break
            end
        end
    end)
    if not ok or not cut then return s end
    return s:sub(1, cut - 1) .. "…"
end

-- 图片资源（圆角遮罩 / 两种高度的圆角按钮底图）
local IMG = {}
local img_loaded = false

local function load_imgs(g)
    if img_loaded then return end
    img_loaded = true
    local function try(name)
        local ok, v = pcall(g.load_image, "Image/" .. name)
        if not ok or not v then
            ok, v = pcall(g.load_image, name)
        end
        return (ok and v) or nil
    end
    IMG.mask = try("round_mask.png")
    IMG.b30  = try("btn30.png")
    IMG.b36  = try("btn36.png")
end

-- 圆角矩形：优先用内核的 nine_slice + 圆角遮罩（完全之龙的做法），
-- 拿不到就退回直角 rect
local function round_rect(g, x, y, w, h, color, radius)
    if w <= 0 or h <= 0 then return end
    if IMG.mask and type(g.nine_slice) == "function" then
        local r = radius or math.min(18, math.floor(math.min(w, h) / 2))
        local ok = pcall(g.nine_slice, IMG.mask, x, y, w, h, 31, color, r)
        if ok then return end
    end
    pcall(g.rect, x, y, w, h, color)
end

-- 文字居中绘制（水平 + 垂直都居中）
-- text_at 的 y 是文字顶部，要把行高差补回去。
-- v3.0.1：行高从 14*scale 改成 20*scale —— 内核字号约 20，
--   按 14 算会让文字整体偏下 (20-14)*scale/2 ≈ 2.6px，这就是按钮文字「没居中」的原因。
--   lh 是可选的行高基数，右上角 × 用的是老的 14（它另有手动补偿），显式传 14 保持原样。
local function text_center(g, x, y, w, h, label, color, scale, lh)
    local sc = scale or 0.88
    local tw = text_w(label, sc)
    local th = (lh or 20) * sc
    pcall(g.text_at, x + (w - tw) / 2, y + (h - th) / 2, label, color or C.text, sc)
end

-- 圆角按钮。
-- 文字居中交给 image_button 自己做（label 直接传进去）：
-- 之前我传空格 + 自己 text_at 估算坐标，中文宽度算不准，所以一直偏。
-- 只有降级到 button_at 时才需要自己画文字（那条分支仍然用 text_center）。
-- 纯自绘按钮：只用 rect + button_at 做命中，不调用 image_button。
-- 用在滚动容器内部 —— image_button 是 ImGui 控件，在 begin_scroll 里会推进 ImGui 自己的
-- 光标位置，内容越多越容易把滚动位置带偏（物品栏 500 项时整片空白就是这个引起的）。
local function paint_btn_plain(g, x, y, w, h, label, fg)
    round_rect(g, x, y, w, h, C.btn, math.min(18, math.floor(h / 2)))
    text_center(g, x, y, w, h, label, fg or C.text, 0.88)
    return g.button_at(x, y, w, h, " ") and true or false
end

local function paint_btn(g, x, y, w, h, label, fg)
    local img = (h >= 34) and IMG.b36 or IMG.b30
    if img and type(g.image_button) == "function" then
        local ok, r = pcall(g.image_button, img, x, y, w, h, label,
                            math.min(18, math.floor(h / 2)))
        if ok then return r and true or false end
    end
    round_rect(g, x, y, w, h, C.btn, math.min(18, math.floor(h / 2)))
    text_center(g, x, y, w, h, label, fg or C.text, 0.88)
    return g.button_at(x, y, w, h, " ") and true or false
end

-- 收集某个页签下所有分区的条目
local function list_of(tab)
    local out = {}
    if not D or not tab then return out end
    for _, sec in ipairs(tab.sections) do
        local pool = D.pools[sec]
        local cap = D.section_cap(sec)
        for i = 1, cap do
            local s = pool and pool[i]
            if s and s.id and s.id > 0 and (s.stack or 0) > 0 then
                out[#out + 1] = { section = sec, index = i, id = s.id, stack = s.stack }
            end
        end
    end
    return out
end

local function tab_used(tab)
    local n = 0
    if not D or not tab then return 0 end
    for _, sec in ipairs(tab.sections) do
        n = n + D.section_used(sec)
    end
    return n
end

local function tab_cap(tab)
    local n = 0
    if not D or not tab then return 0 end
    for _, sec in ipairs(tab.sections) do
        n = n + D.section_cap(sec)
    end
    return n
end

-- 状态行文字：单分区显示 67/100，药水页分别列出三类
local function status_text(tab)
    if not D or not tab then return "" end
    if tab.key == "potion" then
        return string.format("增益 %d/%d · 食物 %d/%d · 药剂 %d/%d",
                D.section_used("buffpot"), D.section_cap("buffpot"),
                D.section_used("food"), D.section_cap("food"),
                D.section_used("flask"), D.section_cap("flask"))
    end
    return string.format("%s %d/%d", tab.label, tab_used(tab), tab_cap(tab))
end

-- ---------- 主绘制 ----------
function UI.draw(g)
    if not D or type(g) ~= "table" then return end

    -- 一次性：透明皮肤 + 空标题 + 全透明 style（干掉内核标题条与左上角 v）
    if not styled then
        -- 【鬼妖村正的做法】把内核整套框架全涂透明，然后自己向外画一个完整面板
        -- 1) 皮肤用全透明图（面板底、标题条、边框全部不画）
        -- 2) 标题设成空格
        -- 3) style 七项全 0 透明
        -- 这样屏幕上只剩我们自己画的东西，不会出现「两层标题栏」
        local okb, blank = pcall(g.load_image, "Image/blank.png")
        if not okb or not blank then
            okb, blank = pcall(g.load_image, "blank.png")
        end
        pcall(g.set_title, " ", " ")
        if okb and blank and type(g.set_skin) == "function" then
            -- 第 3 参（最小化悬浮窗图标）也传透明图，折叠后不留图标
            pcall(g.set_skin, blank, 1, blank, 32, 0)
        end
        if type(g.set_style) == "function" then
            pcall(g.set_style, {
                panel  = { 0, 0, 0, 0 },
                title  = { 0, 0, 0, 0 },
                border = { 0, 0, 0, 0 },
                button = { 0, 0, 0, 0 },
                hover  = { 0, 0, 0, 0 },
                active = { 0, 0, 0, 0 },
                -- text 必须给正常颜色：image_button 的 label 用它绘制，
                -- 设成全透明的话按钮文字就看不见了
                text   = { 235, 237, 229, 255 },
            })
        end
        if type(g.set_style) == "function" then
            pcall(g.set_style, {
                panel  = { 0, 0, 0, 0 },
                title  = { 0, 0, 0, 0 },
                border = { 0, 0, 0, 0 },
                button = { 0, 0, 0, 0 },
                hover  = { 0, 0, 0, 0 },
                active = { 0, 0, 0, 0 },
                text   = { 0, 0, 0, 0 },
            })
        end
        styled = true
    end

    -- 左上角 v：只压制，不接管。
    -- 曾经试过「点 v = 收起面板」，结果点一次之后面板就再也打不开了：
    -- 内核的 collapsed 复位有延迟，重新打开的第一帧又被判成「正在收起」，
    -- 于是开了立刻关。加过 12 帧保护期也没根治，所以这条功能砍掉。
    -- 现在每帧强制展开，点 v 会闪一下但不会收起，关闭只能靠右上角 ×。
    opened_frames = opened_frames + 1
    -- 左上角 v：当成「关闭」来处理。
    -- 注意保护期：刚打开的前 20 帧只复位折叠态、不关窗口。
    -- 因为内核的 collapsed 归零有延迟，重开时头几帧可能还读到 true，
    -- 没有保护期就会「开了立刻关」，表现就是再也打不开。
    opened_frames = opened_frames + 1
    if type(g.is_collapsed) == "function" then
        local okc, c = pcall(g.is_collapsed)
        if okc and c then
            pcall(g.set_collapsed, false)
            if opened_frames > 20 then
                opened_frames = 0
                if on_close then pcall(on_close) end
                return
            end
        end
    end

    g.set_width(W)
    g.set_content_height(H)

    -- 搜索框的状态（真正的控件在后面画，要压在自己的底衬上面）
    local cur_tab = TABS[tab_index]
    local kw = search_kw[cur_tab.key] or ""
    if type(g.show) == "function" then
        pcall(g.show)
    else
        g.set_visible(true)
    end

    local p = get_player and get_player() or nil
    if p and D.inv_debug == "未探测" then
        pcall(D.inv, p)
    end

    load_imgs(g)

    -- ---------- 背景 + 自绘标题栏 ----------
    -- Y0：用负 y 向上探，盖住内核那条被涂透明但仍占高度的标题栏
    local Y0 = -34
    -- ===== v2.0.5：窗口定位 =====
    -- 面板贴住窗口左边缘（X0=0），窗口本身用 g.set_pos 移到屏幕右侧。
    -- 这样 ImGui 的搜索框（跟着窗口走）自然落在面板内，不需要任何光标 hack。
    local CX = 0                      -- 内容左起点 = 窗口左边缘
    local PAD = 12                    -- 面板左右内边距（搜索框距面板边缘的距离）
    local PANEL_W = 682               -- v2.0.10：面板宽固定 682（与 v2.0.8 一致，不随窗口加宽）
    local BX0 = -PAD                  -- 背景左边缘（探出窗口 12px，自绘不受窗口裁剪）
    local PW = PANEL_W                -- 面板总宽
    -- 窗口初始位置（依据 dragon：set_pos 只在初始化时调一次，每帧调会让窗口拖不动）
    local WIN_X, WIN_Y = 318, 40   -- v2.0.11：再右移 24（294 -> 318）
    if not pos_set and type(g.set_pos) == "function" then
        pcall(g.set_pos, WIN_X, WIN_Y)
        pos_set = true   -- 无论成败都标记：每帧重试会让窗口拖不动（dragon v9.0.4 教训）
    end
    local LIST_W = PANEL_W - 24            -- 列表可用宽
    round_rect(g, BX0, Y0, PW, H - Y0, C.panel, 18)
    round_rect(g, BX0, Y0, PW, H_TITLE, C.title, 18)
    pcall(g.text_at, CX + 0, Y0 + 7, "多功能大背包", C.text, 1.0)   -- v2.0.12：左移 8、上移 2


    -- ---------- 右上角 ×（唯一的关闭方式） ----------
    -- 贴住内容区最上沿、最右端（内核标题栏在内容区之外，画不进去，
    -- 所以能到的最高处就是 y=0 这一行）
    -- 标题栏在负坐标区，× 跟着上去，就是面板真正的右上角
    -- 负坐标已确认可绘制（标题栏整条都画出来了），× 直接放到最右上角
    local cw, ch = 36, 26
    -- v2.0.11：按「面板右边缘」算，不能用窗口宽 W（面板比窗口左探 12，会算出界）
    -- v2.0.14：紫框按数学居中（Y0+6），字形单独上移 2px（见下面的 text_center）
    local cx, cy = BX0 + PW - cw - 8, Y0 + (H_TITLE - ch) / 2
    round_rect(g, cx, cy, cw, ch, C.close, 13)
    text_center(g, cx - 1, cy - 4, cw, ch, "×", C.text, 1.05, 14)   -- 字形微调：上 4、左 1（框不动）
    if g.button_at(cx, cy, cw, ch, " ") then
        if on_close then pcall(on_close) end
        return
    end

    -- ---------- 搜索框 ----------
    -- 像完全之龙那样直接用内核输入框自带的背景，不自绘底衬（那样会框套框）。
    -- 之前为了盖住内核标题栏，把 style 的 panel/button 等全设了透明，
    -- 输入框背景也因此透明 → 这里临时恢复成正常色，调用完立刻改回透明。
    if type(g.input_text) == "function" then
        if type(g.set_style) == "function" then
            pcall(g.set_style, {
                panel  = C.search,
                button = C.search,
                hover  = C.search,
                active = C.search,
                text   = C.text,
            })
        end
        pcall(g.set_content_height, SEARCH_FAKE_H)
        -- 注：v1.1.0 曾在这里用 set_width 把窗口压窄来缩短输入框，结果 ImGui 内容区被重排，
        --     列表滚动位置错乱（物品明明 500/500 却一片空白，得往下翻才出来）。
        --     这里的搜索框恢复全宽，开关改成屏幕悬浮按钮。
        local nk = g.input_text("搜索", kw)
        pcall(g.set_content_height, H)
        if type(g.set_style) == "function" then
            pcall(g.set_style, {
                panel  = { 0, 0, 0, 0 },
                button = { 0, 0, 0, 0 },
                hover  = { 0, 0, 0, 0 },
                active = { 0, 0, 0, 0 },
                text   = { 235, 237, 229, 255 },
            })
        end
        if type(nk) == "string" then kw = nk end
        search_kw[cur_tab.key] = kw
    end

    -- ---------- 页签 ----------
    local tx = CX + 8
    for i, t in ipairs(TABS) do
        local label = t.label .. "(" .. tostring(tab_used(t)) .. "/" .. tostring(tab_cap(t)) .. ")"
        if paint_btn(g, tx, TAB_Y, TAB_W, TAB_H, label) then
            tab_index = i
        end
        -- 选中态：页签底部一条高亮短线（按钮文字颜色统一由 style 决定，改不了单个）
        if i == tab_index then
            round_rect(g, tx + 26, TAB_Y + TAB_H - 5, TAB_W - 52, 4, C.accent, 2)
        end
        tx = tx + TAB_W + TAB_GAP
    end

    -- ---------- 数量提示 + 结果（放在列表之前，列表必须最后画） ----------
    pcall(g.text_at, CX + 12, STATUS_Y + 2, status_text(cur_tab), C.accent, 0.82)
    if last_result ~= "" then
        -- 右侧显示结果提示；和左边的容量分开，避免压字
        pcall(g.text_at, CX + 400, STATUS_Y + 4, short(last_result, 14), C.green, 0.7)
    end

    -- ---------- 底部操作按钮 ----------
    if paint_btn(g, CX + 10, BTN_Y, 204, BTN_H, "收纳分类物") then
        if p then
            local n, err = D.collect(p, true)
            UI.say(err or ("收纳了 " .. tostring(n) .. " 个"))
        else
            UI.say("拿不到本地玩家")
        end
    end
    if paint_btn(g, CX + 220, BTN_Y, 204, BTN_H, "收纳全部") then
        if p then
            local n, err = D.collect(p, false)
            UI.say(err or ("收纳了 " .. tostring(n) .. " 个"))
        else
            UI.say("拿不到本地玩家")
        end
    end
    if paint_btn(g, CX + 430, BTN_Y, 204, BTN_H, "收纳手上") then
        if p then
            local n, err = D.collect_held(p)
            UI.say(err or ("手持收纳 " .. tostring(n) .. " 个"))
        else
            UI.say("拿不到本地玩家")
        end
    end

    -- ---------- 列表（最后画；begin_scroll 之后坐标会复位） ----------
    local items = list_of(cur_tab)

    -- 搜索过滤：名字包含关键词，或直接输入物品 ID
    if kw ~= "" then
        local hit = {}
        local low = kw:lower()
        for _, it in ipairs(items) do
            local nm = D.item_name(it.id) or ""
            if nm:find(kw, 1, true) or nm:lower():find(low, 1, true)
               or tostring(it.id) == kw then
                hit[#hit + 1] = it
            end
        end
        items = hit
    end

    local content_h = math.max(LIST_H, #items * ROW_H)

    if #items == 0 then
        local tip = (kw ~= "") and ("（没有匹配「" .. kw .. "」的物品）") or "（这个分类还没有东西）"
        pcall(g.text_at, CX + 18, LIST_Y + 12, tip, C.dim, 0.9)
        return
    end

    -- 关键：内核返回的滚动偏移可能是字符串（完全之龙那边就写了 tonumber(sy0)），
    -- 直接拿它和数字比较会抛 "attempt to compare number with string"，
    -- 整个列表循环中断 → 一行都画不出来（页签/状态行/底部按钮在它之前画，所以看着都正常）。
    -- 关键：内核返回的滚动偏移可能是字符串（完全之龙那边就写了 tonumber），
    -- 直接和数字比较会抛 "attempt to compare number with string"，
    -- 整个列表循环中断 → 一行都画不出来（页签/状态行/底部按钮在它之前画，所以看着都正常）。
    local _, sy0 = g.begin_scroll("multibag_list",
            CX + 10, LIST_Y, LIST_W, LIST_H, LIST_W, content_h)
    local sy = tonumber(sy0) or 0
    local maxsy = math.max(0, content_h - LIST_H)
    if sy < 0 or sy > maxsy then sy = 0 end
    local vh = LIST_H

    -- 单行绘制抽成函数，方便"可见性判断失灵时"兜底再画一遍
    local function draw_row(n, it)
        local y = (n - 1) * ROW_H
        round_rect(g, 0, y, LIST_W - 6, ROW_H - 6, C.row, 10)
        -- 名字读不到就用 ID 顶上：500 个物品里只要有一个 nil，short() 就会抛错，
        -- 整个列表循环随之中断 → 一行都不显示（其他栏位项少，碰不到这种 id，所以看着正常）
        local okn, nm = pcall(D.item_name, it.id)
        if not okn or type(nm) ~= "string" or nm == "" then
            nm = "ID:" .. tostring(it.id)
        end
        pcall(g.text_at, 12, y + (ROW_H - 6 - 14 * 0.86) / 2,
                short(nm, 14) .. "  ×" .. tostring(it.stack),
                C.text, 0.86)
        local bh = ROW_H - 16
        local by = y + 8
        if paint_btn_plain(g, LIST_W - 312, by, 88, bh, "取1", C.text) then
            if p then
                local got = D.take_out(p, it.section, it.index, 1)
                UI.say(got > 0 and ("取出 " .. D.item_name(it.id)) or "取出失败")
            else
                UI.say("拿不到本地玩家")
            end
        end
        if paint_btn_plain(g, LIST_W - 216, by, 88, bh, "取10", C.text) then
            if p then
                local got = D.take_out(p, it.section, it.index, 10)
                UI.say(got > 0 and string.format("取出 %s x%d", D.item_name(it.id), got)
                        or "取出失败（背包满？）")
            else
                UI.say("拿不到本地玩家")
            end
        end
        if paint_btn_plain(g, LIST_W - 120, by, 88, bh, "全取", C.text) then
            if p then
                local got = D.take_out(p, it.section, it.index, it.stack)
                UI.say(got > 0 and string.format("取出 %s x%d", D.item_name(it.id), got)
                        or "取出失败（背包满？）")
            else
                UI.say("拿不到本地玩家")
            end
        end
    end

    local drawn = 0
    local first_err = nil
    for n, it in ipairs(items) do
        local y = (n - 1) * ROW_H
        if y + ROW_H > sy and y < sy + vh then
            local okr, errr = pcall(draw_row, n, it)
            if not okr and not first_err then first_err = tostring(errr) end
            drawn = drawn + 1
        end
    end
    -- 单行绘制失败已被 pcall 拦住，不影响其它行

    -- 兜底：可见性判断若算出 0 行（sy/vh 与内核实际平移不一致），先画前 12 行，
    -- 内容由内核裁剪 —— 至少不会是一整片空白
    if drawn == 0 then
        local lim = math.min(#items, 12)
        for n = 1, lim do draw_row(n, items[n]) end
        drawn = lim
    end
    g.end_scroll()
end
return UI
