-- dr_gui.lua
-- 面板只有四项：随机掉落开关 / 掉落概率 / 数量最小 / 数量最大。
-- 某个控件接口缺失时只少一行，不让整块面板报错。
local U = require("dr_util")
local Cfg = require("dr_cfg")

local M = {}

-- 悬浮窗图标：首次画面板时加载字母 R 图标并交给加载器皮肤接口。
--   加载器没有 load_image / set_skin 时静默跳过，不影响面板功能。
local skin_state = 0
local collapsed_done = false
local pos_done = false      -- v1.1.6：窗口初始位置是否已设过
local btn_img = nil         -- v1.2.1：圆角按钮底图（button_36.png）

-- 图片路径自适应（3.0.x 私有目录根可能是 <mod>/ 也可能是 <mod>/lib/）
local function load_img(g, name)
    if type(g.load_image) ~= "function" then return nil end
    local ok, id = pcall(g.load_image, "lib/ui/" .. name)
    if ok and id then return id end
    ok, id = pcall(g.load_image, "ui/" .. name)
    if ok and id then return id end
    return nil
end

-- v1.2.0：配色照抄完全之龙 v10.0.0（main.lua:2783 的 set_style）
local style_done = false
local function apply_style(g)
    if style_done then return end
    style_done = true       -- 无论成败都只做一次，避免每帧重设
    if type(g.set_style) ~= "function" then return end
    pcall(g.set_style, {
        panel  = { 33, 43, 102, 245 },
        title  = { 50, 60, 130, 255 },
        button = { 92, 118, 190, 255 },
        hover  = { 116, 145, 220, 255 },
        active = { 74, 80, 90, 255 },
        border = { 14, 15, 18, 255 },
        text   = { 235, 237, 229, 255 },
    })
end

-- v1.2.0：皮肤改用完全之龙的 panel_skin.png（圆角深蓝底图 + 九宫格 border 18）
local function apply_skin(g)
    if skin_state ~= 0 then return end
    if type(g.load_image) ~= "function" or type(g.set_skin) ~= "function" then
        skin_state = 2
        return
    end
    local ico = load_img(g, "r.png")
    if not ico then return end   -- 私有目录可能还没解压完，下一帧再试
    local panel = load_img(g, "panel_skin.png")
    btn_img = load_img(g, "button_36.png")
    local ok
    if panel then
        ok = pcall(g.set_skin, panel, 18, ico, 24, 0)
    else
        ok = pcall(g.set_skin, nil, 18, ico, 24, 0)   -- 底图拿不到就退回无底图
    end
    skin_state = ok and 1 or 2
end

local function has(g, name)
    return type(g[name]) == "function"
end

local function onoff(v)
    return v and "已开启" or "已关闭"
end
-- v1.2.1：圆角胶囊按钮（完全之龙 btn_at 的简化版）
--   有底图 + image_button 就用圆角图按钮；否则依次退回 button_at、流式 button。
local function pill(g, x, y, w, h, label)
    if btn_img and type(g.image_button) == "function" then
        local ok, ret = pcall(g.image_button, btn_img, x, y, w, h, label, 18)
        if ok then return ret end
    end
    if type(g.button_at) == "function" then
        local ok, ret = pcall(g.button_at, x, y, w, h, label)
        if ok then return ret end
    end
    return g.button(label)
end
-- 这一帧能不能用绝对定位布局
local function abs_ok(g)
    return type(g.set_cursor) == "function" and type(g.image_button) == "function" and btn_img ~= nil
end

-- 滑杆数值 → 整数
local function snap(v, lo, hi)
    return U.clamp(math.floor((tonumber(v) or lo) + 0.5), lo, hi)
end

function M.draw(bind)
    local g = mod.gui
    if not g then return end
    apply_style(g)
    apply_skin(g)
    if not collapsed_done then
        collapsed_done = true
        if type(g.set_collapsed) == "function" then pcall(g.set_collapsed, true) end
    end
    local c = Cfg.cfg

    if has(g, "set_title") then g.set_title("死亡随机掉落", "R") end
    if has(g, "set_width") then g.set_width(420) end
    -- v1.1.16：135（v1.1.15 是 140）
    if not pos_done and has(g, "set_pos") then
        pcall(g.set_pos, 8, 135)
        pos_done = true
    end

    -- 面板内容宽（窗口 420 - 左右内边距）
    local CW = 400

    if abs_ok(g) then
        -- ===== 绝对定位布局：圆角按钮 + set_cursor 把流式滑杆推到下方 =====
        if pill(g, 0, 4, CW, 36, "随机掉落：" .. onoff(c.on)) then
            c.on = not c.on
            Cfg.save()
        end
        pcall(g.set_cursor, 0, 46)     -- 后面三个滑杆从这里开始流式排
        if has(g, "slider") then
            local v = snap(g.slider("掉落概率 %", c.chance, 1, 100), 1, 100)
            if v ~= c.chance then c.chance = v Cfg.save() end
            local mn = snap(g.slider("数量最小", c.min, 1, 99), 1, 99)
            local mx = snap(g.slider("数量最大", c.max, 1, 99), 1, 99)
            if mn ~= c.min or mx ~= c.max then
                c.min, c.max = mn, mx
                if c.max < c.min then c.max = c.min end
                Cfg.save()
            end
        end
    else
        -- ===== 退回流式布局（直角按钮）=====
        if has(g, "button") then
            if g.button("随机掉落：" .. onoff(c.on)) then
                c.on = not c.on
                Cfg.save()
            end
        end
        if has(g, "slider") then
            local v = snap(g.slider("掉落概率 %", c.chance, 1, 100), 1, 100)
            if v ~= c.chance then c.chance = v Cfg.save() end
            local mn = snap(g.slider("数量最小", c.min, 1, 99), 1, 99)
            local mx = snap(g.slider("数量最大", c.max, 1, 99), 1, 99)
            if mn ~= c.min or mx ~= c.max then
                c.min, c.max = mn, mx
                if c.max < c.min then c.max = c.min end
                Cfg.save()
            end
        elseif has(g, "button") then
            if g.button("掉落概率：" .. c.chance .. "%") then
                c.chance = c.chance >= 100 and 10 or (c.chance + 10)
                Cfg.save()
            end
            if g.button("数量：" .. c.min .. " ~ " .. c.max .. "（点一下 +1）") then
                c.min = c.min >= 99 and 1 or (c.min + 1)
                if c.max < c.min then c.max = c.min end
                Cfg.save()
            end
        end
    end
end

return M
