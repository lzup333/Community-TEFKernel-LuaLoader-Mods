-- ui_kit.lua — 工坊系列共用 UI 套件（v1.2：+ K.palette 强调色）
-- 纯 Lua 5.4，零游戏符号：只访问传入 mod 的 mod.gui / mod.read_file / mod.write_file。
-- 不 require 任何模块，不引用任何游戏类型或设置系统。
--
-- 最小用法：
--   local K = require("ui_kit")
--   function mod.setup()   K.init(mod)  end          -- 只绑定，不画
--   function mod.on_gui()
--     local pr = K.probe()                          -- 第 2 帧起自动测屏
--     K.box(0, 0, 300, 40, K.colors.panel)          -- 无图 → rect
--     K.txt(8, 8, "标题", nil, 0.8, 280)
--   end
--
-- 约定：G 为 nil / API 缺失 / 参数非法时全部安全返回，失败只降级，绝不 throw。
--       K.last_error() 可查最近一次失败原因（供状态页显示）。

local K = {}

local G = nil            -- mod.gui
local M = nil            -- mod
local ERR = ""

local function set_err(e) ERR = tostring(e) end
function K.last_error() return ERR end

local BIG = 999999.0
local MAX_STATE_BYTES = 64 * 1024

-- 颜色永远是「表」，绝不让 nil / false 流进 text_at / rect。
-- 羊皮纸主题：与项目/worldforge 同一套配色，五个工坊模组共用。
-- 只有 7 个键能进 set_style：panel/title/button/hover/active/border/text。
local C = {
  panel  = { 240, 228, 200, 246 },   -- 羊皮纸底
  title  = { 236, 222, 194, 255 },   -- 标题栏（浅底配深字）
  button = { 214, 194, 158, 255 },
  hover  = { 234, 216, 176, 255 },
  active = { 176, 142, 92, 255 },
  border = { 74, 46, 20, 255 },      -- 深褐描边（也管滚动滑轨）
  text   = { 58, 38, 18, 255 },      -- 墨褐正文
  accent = { 138, 40, 26, 255 },     -- 朱红
  gold   = { 156, 112, 44, 255 },    -- 金褐
  muted  = { 108, 86, 58, 255 },
  white  = { 255, 255, 255, 255 },
  invis  = { 255, 255, 255, 0 },
  row    = { 228, 214, 184, 255 },
  row_a  = { 228, 214, 184, 255 },
  row_b  = { 236, 224, 198, 255 },
  diff   = { 246, 222, 158, 255 },
  ok     = { 74, 108, 46, 255 },
  warn   = { 168, 40, 32, 255 },
  bad    = { 168, 40, 32, 255 },
  sel    = { 138, 40, 26, 255 },
}
K.colors = C
K.state_path = "ui_state.txt"
K.VERSION = "1.2"

-- 每个模组选一个自己的强调色，避免所有工坊面板长得一模一样（玩家分不清是哪个模组）。
-- 只覆盖传入的键，其余保持羊皮纸默认；必须在 K.apply_style() 之前调用。
--   K.palette({ accent = {104,58,138,255}, border = {68,42,94,255} })
function K.palette(t)
  if type(t) ~= "table" then return C end
  for k, v in pairs(t) do
    if type(C[k]) == "table" and type(v) == "table" then
      C[k] = { v[1] or C[k][1], v[2] or C[k][2], v[3] or C[k][3], v[4] or C[k][4] }
    end
  end
  return C
end

-- ---------------------------------------------------------------- 基础工具
-- nil / NaN / inf 一律换成默认值：math.floor(nil) 与传 nil 颜色一样会整帧中断。
local function num(v, d)
  v = tonumber(v)
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
  return v
end

local function color(c, d)
  if type(c) == "table" then return c end
  return d
end

-- %d 只接受整数范围内的数；超范围退回 %.0f，绝不让 format 抛错。
local function fmt_int(n)
  if n >= -9007199254740992 and n <= 9007199254740992 then
    return string.format("%d", n)
  end
  return string.format("%.0f", n)
end

local function gui()
  if M ~= nil then
    local g = M.gui
    if g ~= nil and g ~= G then G = g end
  end
  return G
end

local function getfn(name)
  if type(name) ~= "string" then return nil end
  local g = gui()
  if g == nil then return nil end
  local ok, fn = pcall(function() return g[name] end)
  if ok and type(fn) == "function" then return fn end
  return nil
end

-- 统一入口：先判 type(G[name])=="function"，再 pcall。返回 pcall 的 ok + 结果。
local function api(name, ...)
  local fn = getfn(name)
  if fn == nil then return false end
  return pcall(fn, ...)
end
function K.has(name) return getfn(name) ~= nil end
-- ---------------------------------------------------------------- 主题 / 图片
-- 皮肤资源固定放 lib/ui/：panel.png（九宫格羊皮纸）、button.png（按钮）、
-- glyph.png（标题图标）、white.png（1x1 白图，用于纯色填充）。
-- 图片没有打包进来时全部降级为 rect / button_at，绝不抛错。
local IMG = {}
local ASSET_TRIED, STYLE_DONE, SKIN_DONE = false, false, false

function K.image_id(name) return IMG[name] end

function K.load_theme()
  if not ASSET_TRIED then
    ASSET_TRIED = true
    if K.has("load_image") then
      local names = { "white", "panel", "button", "glyph" }
      for i = 1, #names do
        local ok, id = api("load_image", "lib/ui/" .. names[i] .. ".png")
        if ok and type(id) == "string" then IMG[names[i]] = id end
      end
    end
    -- load_image 只登记；第一次 image 绘制才解码。这里用 1x1 透明画一次。
    if K.has("image") then
      for _, id in pairs(IMG) do
        api("image", id, 0, 0, 1, 1, C.invis, nil)
      end
    end
  end
  return IMG
end

function K.apply_style()
  if not K.has("set_style") then return false end
  local ok = api("set_style", {
    panel = C.panel, title = C.title, button = C.button,
    hover = C.hover, active = C.active, border = C.border, text = C.text,
  })
  STYLE_DONE = ok and true or STYLE_DONE
  return ok
end

function K.apply_skin(scale)
  if not K.has("set_skin") or not IMG.panel or not IMG.glyph then return false end
  local size = math.floor(40 * (tonumber(scale) or 1))
  if size < 24 then size = 24 elseif size > 128 then size = 128 end
  local edge = math.floor(10 * (tonumber(scale) or 1))
  local ok = api("set_skin", IMG.panel, 16, IMG.glyph, size, edge)
  SKIN_DONE = ok and true or SKIN_DONE
  return ok
end

-- 纯色填充：有 white.png 就是纯色；没有就退 rect（带游戏底纹）。
function K.fill(x, y, w, h, col)
  x, y, w, h = num(x, 0), num(y, 0), num(w, 0), num(h, 0)
  if w <= 0 or h <= 0 then return false end
  if IMG.white and K.has("image") then
    local ok = api("image", IMG.white, x, y, w, h, color(col, C.row), nil)
    if ok then return true end
  end
  return K.box(x, y, w, h, col)
end

-- 羊皮纸卡片：九宫格 panel.png；没图时退 rect。
function K.card(x, y, w, h, col, border)
  if IMG.panel and K.has("nine_slice") then
    local ok = api("nine_slice", IMG.panel, num(x, 0), num(y, 0), num(w, 0), num(h, 0),
                   math.max(1, math.floor(num(border, 16))), color(col, C.row_b), 0)
    if ok then return true end
  end
  return K.box(x, y, w, h, col)
end

-- 图片按钮：button.png + image_button；没图 / 旧加载器退 button_at。
function K.ibtn(x, y, w, h, label, border)
  x, y, w, h = num(x, 0), num(y, 0), num(w, 0), num(h, 0)
  if w <= 0 or h <= 0 then return false end
  label = tostring(label or "")
  if IMG.button and K.has("image_button") then
    local ok, hit = api("image_button", IMG.button, x, y, w, h, label,
                        math.max(0, math.floor(num(border, 12))))
    if ok then return hit == true end
  end
  return K.btn(x, y, w, h, label)
end

-- 滑条：范围由调用方给；返回 (新值, 是否变化)。不替调用方写回。
function K.slider(label, cur, lo, hi)
  cur = num(cur, 0)
  lo, hi = num(lo, 0), num(hi, 1)
  if lo > hi then lo, hi = hi, lo end
  local cv = cur
  if cv < lo then cv = lo elseif cv > hi then cv = hi end
  if not K.has("slider") then return cur, false end
  local ok, r = api("slider", tostring(label or ""), cv, lo, hi)
  if not ok or type(r) ~= "number" or r ~= r then return cur, false end
  if r < lo then r = lo elseif r > hi then r = hi end
  return r, r ~= cv
end



-- ---------------------------------------------------------------- UTF-8 / 宽度
-- 非法首字节（孤立 continuation、0xC0/C1、0xF8+）按 1 字节前进，避免死循环。
local function u8len(b)
  if b == nil then return 1 end
  if b < 0x80 then return 1 end
  if b < 0xC2 then return 1 end
  if b < 0xE0 then return 2 end
  if b < 0xF0 then return 3 end
  if b < 0xF8 then return 4 end
  return 1
end

-- 显示宽度单位：ASCII=1，非 ASCII（CJK/全角）=2。
local function units(s)
  local n, i, len = 0, 1, #s
  while i <= len do
    local b = string.byte(s, i)
    local l = u8len(b)
    if i + l - 1 > len then l = len - i + 1 end
    if l < 1 then l = 1 end
    n = n + ((b < 0x80) and 1 or 2)
    i = i + l
  end
  return n
end

local ELLIPSIS = ".."     -- ★ 省略号只占 2 单位（不是 3）
local ELL_U = 2

local function trunc(s, maxu)
  s = tostring(s or "")
  maxu = math.floor(num(maxu, 0))
  if maxu <= 0 then return "" end
  if units(s) <= maxu then return s end
  if maxu <= ELL_U then return ELLIPSIS:sub(1, maxu) end
  local keep = maxu - ELL_U
  local out, n, i, len = {}, 0, 1, #s
  while i <= len do
    local b = string.byte(s, i)
    local l = u8len(b)
    if i + l - 1 > len then l = len - i + 1 end
    if l < 1 then l = 1 end
    local u = (b < 0x80) and 1 or 2
    if n + u > keep then break end
    out[#out + 1] = s:sub(i, i + l - 1)
    n = n + u
    i = i + l
  end
  return table.concat(out) .. ELLIPSIS
end

-- 1.0 比例下一个显示宽度单位约 13px（16-GUI开发.md 真机实测）。
function K.fit(s, bw, sc)
  if s == nil then return "" end
  local px = num(bw, 200)
  local scale = num(sc, 0.6)
  if scale <= 0 then scale = 0.6 end
  local maxu = math.floor(px / (13.0 * scale))
  if maxu < ELL_U then maxu = ELL_U end
  return trunc(s, maxu)
end

-- ---------------------------------------------------------------- 面板 / 按钮
-- box(x, y, w, h, col?, img?, border?, edge?)
--   有图且 nine_slice 可用 → 九宫格；无图 / 无 API / 调用失败 → rect。
--   返回 true = 画了（不保证用户看见），false = 什么也没画。
function K.box(x, y, w, h, col, img, border, edge)
  x, y, w, h = num(x, 0), num(y, 0), num(w, 0), num(h, 0)
  if w <= 0 or h <= 0 then return false end
  col = color(col, C.panel)
  border = math.floor(num(border, 16))
  if img ~= nil and border > 0 and K.has("nine_slice") then
    if api("nine_slice", img, x, y, w, h, border, col, num(edge, 0)) then
      return true
    end
    set_err("nine_slice 调用失败，退化为 rect")
  end
  if not K.has("rect") then
    set_err("缺少 rect：box 无图可退")
    return false
  end
  return api("rect", x, y, w, h, col) == true
end

-- btn(x, y, w, h, label, img?, border?)
--   image_button 可用且成功 → 命中；否则退 button_at；两者都没有 → false。
function K.btn(x, y, w, h, label, img, border)
  x, y, w, h = num(x, 0), num(y, 0), num(w, 0), num(h, 0)
  if w <= 0 or h <= 0 then return false end
  label = tostring(label or "")
  if img ~= nil and K.has("image_button") then
    local ok, hit = api("image_button", img, x, y, w, h, label,
                        math.max(0, math.floor(num(border, 0))))
    if ok then return hit == true end
    set_err("image_button 调用失败，退化为 button_at")
  end
  if K.has("button_at") then
    local ok, hit = api("button_at", x, y, w, h, label)
    return ok and hit == true
  end
  set_err("缺少 button_at / image_button：btn 不可点击")
  return false
end

-- ---------------------------------------------------------------- 滚动视口
-- 滚动容器必须配对：K.scroll(...) ... K.scroll_end()
-- 返回 sx, sy, vw, vh（加载器给的视口原点与尺寸）。
-- 老加载器没有 begin_scroll：返回 0,0,w,h —— 不裁剪、不偏移。
local SC = { depth = 0, opened = 0, closed = 0 }

function K.scroll(id, x, y, w, h, cw, ch)
  x, y = num(x, 0), num(y, 0)
  w, h = num(w, 1), num(h, 1)
  if w <= 0 then w = 1 end
  if h <= 0 then h = 1 end
  cw, ch = num(cw, 0), num(ch, 0)
  if cw < 0 then cw = 0 end
  if ch < 0 then ch = 0 end
  if K.has("begin_scroll") then
    local ok, a, b, c, d = api("begin_scroll", id, x, y, w, h, cw, ch)
    if ok then
      SC.depth = SC.depth + 1
      SC.opened = SC.opened + 1
      return num(a, 0), num(b, 0), num(c, w), num(d, h)
    end
    set_err("begin_scroll 调用失败，退化为不裁剪")
  end
  return 0, 0, w, h
end

function K.scroll_end()
  if SC.depth > 0 then
    SC.depth = SC.depth - 1
    SC.closed = SC.closed + 1
    if K.has("end_scroll") then api("end_scroll") end
  end
end

-- 诊断：返回 depth, opened, closed。正常每帧结束应 depth == 0。
function K.scroll_state() return SC.depth, SC.opened, SC.closed end

-- ---------------------------------------------------------------- 绝对文字
-- txt(x, y, s, col?, sc?, bw?)
--   col 为 nil / 非表 → 主题 text 色；sc 夹进 (0,4]；给 bw 就先 fit() 截断。
function K.txt(x, y, s, col, sc, bw)
  s = tostring(s or "")
  x, y = num(x, 0), num(y, 0)
  sc = num(sc, 0.6)
  if sc <= 0 then sc = 0.6 end
  if sc > 4 then sc = 4 end
  if bw ~= nil then s = K.fit(s, bw, sc) end
  if not K.has("text_at") then
    set_err("缺少 text_at：txt 不绘制")
    return false
  end
  return api("text_at", x, y, s, color(col, C.text), sc) == true
end

-- ---------------------------------------------------------------- 状态文件
-- schema = {
--   page = { t = "int",  lo = 1, hi = 9, d = 1 },
--   on   = { t = "bool", d = false },
--   name = { t = "str",  max = 40, d = "" },
-- }
-- state_load 返回新表（缺文件/读坏 → 全默认值）；state_save 只写 schema 里的键。
local function entry_type(e)
  local t = e.t
  if t == "int" or t == "number" or t == "num" then return "num" end
  if t == "bool" or t == "boolean" then return "bool" end
  if t == "str" or t == "string" then return "str" end
  local d = e.d
  if type(d) == "number" then return "num" end
  if type(d) == "boolean" then return "bool" end
  return "str"
end

local function clamp_num(e, n)
  n = math.floor(n)
  local lo = num(e.lo, -1e15)
  local hi = num(e.hi, 1e15)
  if lo > hi then lo, hi = hi, lo end
  if n < lo then n = lo end
  if n > hi then n = hi end
  return n
end

-- 按 UTF-8 字符边界截断字节数，避免把多字节字符切成半个。
local function cut_utf8(s, maxb)
  if maxb <= 0 then return "" end
  if #s <= maxb then return s end
  local i, len = 1, #s
  while i <= len do
    local l = u8len(string.byte(s, i))
    if i + l - 1 > maxb then break end
    i = i + l
  end
  return s:sub(1, i - 1)
end

function K.state_load(schema, path)
  if type(schema) ~= "table" then
    set_err("state_load：schema 必须是表")
    return {}, false
  end
  local out = {}
  for k, e in pairs(schema) do
    if type(k) == "string" and type(e) == "table" then out[k] = e.d end
  end
  if M == nil or type(M.read_file) ~= "function" then
    set_err("state_load：没有 mod.read_file，使用默认值")
    return out, false
  end
  local p = path or K.state_path
  local ok, raw = pcall(M.read_file, p)
  if not ok then
    set_err("state_load：读文件失败：" .. tostring(raw))
    return out, false
  end
  if type(raw) ~= "string" or raw == "" then return out, false end
  if #raw > MAX_STATE_BYTES then raw = raw:sub(1, MAX_STATE_BYTES) end
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    local e = k and schema[k]
    if type(e) == "table" then
      local tp = entry_type(e)
      if tp == "num" then
        local n = tonumber(v)
        -- 非法/NaN/空串 → 保持默认值
        if n ~= nil and n == n and n ~= math.huge and n ~= -math.huge then
          out[k] = clamp_num(e, n)
        end
      elseif tp == "bool" then
        if v == "true" or v == "1" then out[k] = true
        elseif v == "false" or v == "0" then out[k] = false end
      else
        local s = v:gsub("[\r\1-\31]", "")
        out[k] = cut_utf8(s, math.floor(num(e.max, 64)))
      end
    end
  end
  return out, true
end

function K.state_save(state, schema, path)
  if type(state) ~= "table" or type(schema) ~= "table" then
    set_err("state_save：state/schema 必须是表")
    return false
  end
  if M == nil or type(M.write_file) ~= "function" then
    set_err("state_save：没有 mod.write_file")
    return false
  end
  local lines = {}
  for k, e in pairs(schema) do
    if type(k) == "string" and type(e) == "table" then
      local tp = entry_type(e)
      if tp == "num" then
        local n = num(state[k], e.d)
        if n ~= nil then
          n = clamp_num(e, n)
          lines[#lines + 1] = k .. "=" .. fmt_int(n)
        end
      elseif tp == "bool" then
        lines[#lines + 1] = k .. "=" .. ((state[k] == true) and "true" or "false")
      else
        local s = tostring(state[k] or "")
        s = s:gsub("[\r\n\1-\31]", " ")
        s = cut_utf8(s, math.floor(num(e.max, 64)))
        lines[#lines + 1] = k .. "=" .. s
      end
    end
  end
  table.sort(lines)
  local payload = table.concat(lines, "\n") .. "\n"
  local p = path or K.state_path
  local ok, res = pcall(M.write_file, p, payload)
  if not ok then
    set_err("state_save：写文件失败：" .. tostring(res))
    return false
  end
  if res == false then
    set_err("state_save：write_file 返回 false")
    return false
  end
  return true
end

-- ---------------------------------------------------------------- 屏幕探测
-- 零游戏符号（16-GUI开发.md §3.2）：加载器把窗口坐标夹进 [0, screen-32*g]，
-- 因此「请求超大坐标 → 下一帧 get_pos 读回上界」。
-- ★ 第 1 帧绝不 set_pos（会被 gui_layout.json 覆盖），第 2 帧起才开始。
-- 每帧调用一次；返回同一个表（缓存，不每帧分配）。
local PR = {}

function K.probe_reset()
  PR.phase, PR.frames, PR.done, PR.unclamped = 0, 0, false, false
  PR.x_max, PR.y_max = 0, 0
  PR.g, PR.screen_w, PR.screen_h, PR.budget = 1.0, 0, 0, 380.0
  PR.saved_x, PR.saved_y = 24.0, 24.0
  PR.reason = "pending"
  local o = PR.out or {}
  PR.out = o
  o.done, o.g, o.screen_w, o.screen_h = false, 1.0, 0, 0
  o.budget, o.x_max, o.y_max = 380.0, 0, 0
  o.unclamped, o.phase, o.reason = false, 0, "pending"
  o.saved_x, o.saved_y = 24.0, 24.0
  return o
end

local function pr_sync()
  local o = PR.out
  o.done, o.g, o.screen_w, o.screen_h = PR.done, PR.g, PR.screen_w, PR.screen_h
  o.budget, o.x_max, o.y_max = PR.budget, PR.x_max, PR.y_max
  o.unclamped, o.phase, o.reason = PR.unclamped, PR.phase, PR.reason
  o.saved_x, o.saved_y = PR.saved_x, PR.saved_y
  return o
end

function K.probe()
  PR.frames = PR.frames + 1
  if PR.done then return pr_sync() end
  if not (K.has("get_pos") and K.has("set_pos")) then
    PR.done, PR.unclamped, PR.phase, PR.reason = true, true, 3, "no_get_pos/set_pos"
    return pr_sync()
  end
  if PR.frames < 2 then
    PR.reason = "first_frame"
    return pr_sync()
  end
  if PR.phase == 0 then
    local okp, px, py = api("get_pos")
    if okp and type(px) == "number" then
      PR.saved_x, PR.saved_y = num(px, PR.saved_x), num(py, PR.saved_y)
    end
    if not api("set_pos", BIG, 0) then
      PR.done, PR.unclamped, PR.reason = true, true, "set_pos_failed"
      return pr_sync()
    end
    PR.phase, PR.reason = 1, "probe_x"
  elseif PR.phase == 1 then
    local ok, x = api("get_pos")
    PR.x_max = (ok and type(x) == "number") and num(x, 0) or 0
    if not api("set_pos", 0, BIG) then
      PR.done, PR.unclamped, PR.reason = true, true, "set_pos_failed"
      return pr_sync()
    end
    PR.phase, PR.reason = 2, "probe_y"
  else
    local ok, _x, y = api("get_pos")
    PR.y_max = (ok and type(y) == "number") and num(y, 0) or 0
    if PR.x_max > 20000 or PR.y_max > 20000 or PR.x_max <= 0 or PR.y_max <= 0 then
      PR.unclamped, PR.reason = true, "unclamped"
    else
      local mn = math.min(PR.x_max, PR.y_max)
      local g = mn / 688.0
      if g < 1.0 then g = 1.0 elseif g > 2.5 then g = 2.5 end
      PR.g = g
      PR.screen_w = PR.x_max + 32.0 * g
      PR.screen_h = PR.y_max + 32.0 * g
      PR.budget = PR.y_max - 24.0 * g
      PR.reason = "ok"
    end
    api("set_pos", PR.saved_x, PR.saved_y)     -- 测完还原，别把窗口丢到角落
    PR.done, PR.phase = true, 3
  end
  return pr_sync()
end

-- ---------------------------------------------------------------- 绑定
-- init(mod, opts?)：opts.state_path / opts 也可以直接是字符串路径。
function K.init(mod, opts)
  M = mod
  G = nil
  IMG = {}
  ASSET_TRIED, STYLE_DONE, SKIN_DONE = false, false, false
  local g = type(mod) == "table" and mod.gui or nil
  if type(g) == "table" or type(g) == "userdata" then G = g end
  if type(opts) == "string" then opts = { state_path = opts } end
  opts = type(opts) == "table" and opts or {}
  K.state_path = tostring(opts.state_path or "ui_state.txt")
  K.colors = C
  ERR = ""
  SC.depth, SC.opened, SC.closed = 0, 0, 0   -- 热重载时别留下未配对的视口
  K.probe_reset()
  return K
end

-- 模块加载时先建好 probe 缓存表：没 init 就调 K.probe() 也不会索引 nil。
K.probe_reset()

return K
