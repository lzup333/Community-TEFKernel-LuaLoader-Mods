-- num_field.lua — 纯数字输入控件（进入编辑态 → ASCII 缓冲 → 确定时 parse+写回）
-- 纯 Lua 5.4，零游戏符号：只调用 mod.gui 的 input_text / button（缺哪个就降级）。
--
-- 为什么不用 slider：启动器滑块输不进 0，且范围大时拖不到精确值（16-GUI开发.md §2.8）。
--
-- 用法（每帧调用一次，流式布局里）：
--   local NF = require("num_field")
--   NF.init(mod)
--   local v = NF.field("速度倍率", "speed", cur, 0, 131401, "%", function(k, n)
--     cfg[k] = n                      -- 只在「确定」时写回；返回后也可用 committed 判断
--   end)
--
-- 规则（硬要求）：
--   · 初值一律 ASCII；输入框返回的每帧都立即剔除非法字符；
--   · 空串 / "-" / 非法内容在「确定」时不修改原值（返回 cur, false）；
--   · 合法值只做 math.floor，**不再按 lo/hi 夹取**（lo/hi 仅作控件展示/滑块范围提示）；
--   · 只有「确定」才写回，取消 / 未确定绝不改动。

local NF = {}

local G = nil
local M = nil
local edit_key, edit_buf = nil, nil
local last = nil
local ERR = ""

local function set_err(e) ERR = tostring(e) end
function NF.last_error() return ERR end

local function bind()
  if M ~= nil then
    local g = M.gui
    if g ~= nil and g ~= G then G = g end
  end
  return G
end

local function has(n)
  local g = bind()
  if g == nil or type(n) ~= "string" then return false end
  local ok, fn = pcall(function() return g[n] end)
  return ok and type(fn) == "function"
end

local function click(label)
  if not has("button") then return false end
  local ok, r = pcall(G.button, label)
  return ok and r == true
end

-- 立即剔除非法字符：只留 [0-9.-]；负号只保留一个且必须在首位；小数点只保留一个。
-- 全角数字、字母、空格、控制字符都会被删掉（输入框没有数字键盘，只能自己兜）。
local function sanitize(v)
  local s = tostring(v or "")
  s = s:gsub("[^%d%.%-]", "")
  local neg = s:sub(1, 1) == "-"
  s = s:gsub("%-", "")
  local seen = false
  s = s:gsub("%.", function()
    if seen then return "" end
    seen = true
    return "."
  end)
  if neg then s = "-" .. s end
  if #s > 64 then s = s:sub(1, 64) end
  return s
end

-- 初值一律 ASCII：数字先 floor 成整数字符串；非数字字符串走 sanitize。
local function ascii_initial(cur)
  local n = tonumber(cur)
  if n ~= nil and n == n and n ~= math.huge and n ~= -math.huge then
    n = math.floor(n)
    if n >= -9007199254740992 and n <= 9007199254740992 then
      return string.format("%d", n)
    end
    return sanitize(string.format("%.0f", n))   -- 超大数别让 %d 抛错
  end
  return sanitize(cur)
end

function NF.init(mod)
  M = mod
  G = nil
  if type(mod) == "table" then
    local g = mod.gui
    if type(g) == "table" or type(g) == "userdata" then G = g end
  end
  edit_key, edit_buf, last, ERR = nil, nil, nil, ""
  return NF
end

function NF.reset()
  edit_key, edit_buf, last = nil, nil, nil
  return NF
end

function NF.is_editing() return edit_key ~= nil end
function NF.editing_key() return edit_key end
function NF.buf() return edit_buf end
function NF.last_commit() return last end
NF.ascii = sanitize


-- ---------------------------------------------------------------- 自绘键盘（v2.3.2）
-- 仿玩家工坊：数值编辑态不再弹系统输入法，改成 3 列 x 4 行键盘
-- （1~9 / +/- / 0 / 退格）+ 清空 / 默认 / 确定 / 取消。
-- 需要调用方给坐标（x/y/w），否则退回原来的 input_text 路径。
NF.EDIT_H = 226          -- 编辑态块高（dp）：值框 30 + 键盘 4x32 + 动作行 30 + 间隔

local function gui_fill(x, y, w, h, col)
  if not has("rect") then return end
  pcall(G.rect, x, y, w, h, col)
end
local function gui_txt(x, y, s, col, sc)
  if not has("text_at") then return end
  pcall(G.text_at, x, y, tostring(s or ""), col, sc or 0.55)
end
local function gui_btn(x, y, w, h, label)
  if has("button_at") then
    local ok, hit = pcall(G.button_at, x, y, w, h, label)
    return ok and hit == true
  end
  if has("button") then
    local ok, hit = pcall(G.button, label)
    return ok and hit == true
  end
  return false
end

local function do_commit(k, cur, on_commit)
  local n = tonumber(edit_buf or "")
  local valid = n ~= nil and n == n and n ~= math.huge and n ~= -math.huge
  local val = cur
  if valid then
    n = math.floor(n)
    val = n
    last = { key = k, value = n, raw = edit_buf }
    if type(on_commit) == "function" then
      local okc, e = pcall(on_commit, k, n)
      if not okc then set_err("on_commit 出错：" .. tostring(e)) end
    end
  else
    last = { key = k, value = nil, raw = edit_buf, ignored = true }
  end
  edit_key, edit_buf = nil, nil
  return val, valid
end

local function draw_editor(o)
  local sc = tonumber(o.s) or 1
  local function u(n) return n * sc end
  local x, y, w = o.x, o.y, o.w
  local c = o.colors or {}
  local gap = u(6)
  gui_fill(x, y, w, u(30), c.box)
  gui_fill(x, y, u(3), u(30), c.accent)
  local shown = tostring(edit_buf or "")
  if shown == "" then
    gui_txt(x + u(10), y + u(8), "点键盘输入数字", c.muted, 0.55)
  else
    gui_txt(x + u(10), y + u(7), shown, c.text, 0.66)
  end
  local top = y + u(36)
  local kw = math.floor((w - gap * 2) / 3)
  local kh = u(32)
  local keys = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
                 { "+/-", "0", "退格" } }
  local hit = nil
  for ri = 1, 4 do
    for ci = 1, 3 do
      local k = keys[ri][ci]
      if gui_btn(x + (ci - 1) * (kw + gap), top + (ri - 1) * (kh + gap), kw, kh, k) then hit = k end
    end
  end
  local ay = top + 4 * (kh + gap) + u(2)
  local aw = math.floor((w - gap * 3) / 4)
  local acts = { "清空", "默认", "确定", "取消" }
  for i = 1, 4 do
    if gui_btn(x + (i - 1) * (aw + gap), ay, aw, u(30), acts[i]) then hit = acts[i] end
  end
  if hit == nil then return end
  if hit == "退格" then
    edit_buf = tostring(edit_buf or ""):sub(1, -2)
  elseif hit == "+/-" then
    local b = tostring(edit_buf or "")
    if b:sub(1, 1) == "-" then edit_buf = b:sub(2) else edit_buf = "-" .. b end
  elseif hit == "清空" then
    edit_buf = ""
  elseif hit == "默认" then
    if type(o.on_default) == "function" then pcall(o.on_default, edit_key) end
    edit_key, edit_buf = nil, nil
  elseif hit == "确定" then
    do_commit(o.key, o.cur, o.on_commit)
  elseif hit == "取消" then
    last = { key = edit_key, value = nil, raw = nil, canceled = true }
    edit_key, edit_buf = nil, nil
  else
    edit_buf = tostring(edit_buf or "") .. hit
  end
end

-- NF.field(label, key, cur, lo, hi, unit?, on_commit?) -> value, committed
--   committed = true 仅表示「这次确定解析成功并写入了合法值」。
--   非法/空串时编辑态照样关闭，但原值不变、on_commit 不调用、返回 false。
function NF.field(label, key, cur, lo, hi, unit, on_commit, opts)
  bind()
  label = tostring(label or "")
  key = key or label
  unit = tostring(unit or "")

  lo = tonumber(lo)
  hi = tonumber(hi)
  if lo == nil or lo ~= lo then lo = -1e15 end
  if hi == nil or hi ~= hi then hi = 1e15 end
  if lo > hi then lo, hi = hi, lo end

  cur = tonumber(cur)
  if cur == nil or cur ~= cur then cur = lo end

  if edit_key == key then
    -- 有坐标 → 自绘键盘（v2.3.2）；没有坐标（老调用方）→ 原来的系统输入框
    if opts ~= nil and opts.x ~= nil and opts.y ~= nil and opts.w ~= nil then
      draw_editor({ x = opts.x, y = opts.y, w = opts.w, s = opts.s,
                    colors = opts.colors, on_default = opts.on_default,
                    key = key, cur = cur, on_commit = on_commit })
      return cur, false
    end
    -- 编辑态：每帧把输入框返回值清洗后放回缓冲；不直接写回设置。
    if has("input_text") then
      local ok, r = pcall(G.input_text, label, edit_buf or ascii_initial(cur))
      if ok and type(r) == "string" then edit_buf = sanitize(r) end
    end

    if click("确定") then
      -- ★ v2.3.0：自由输入。lo/hi 只用于滑块/提示，不再夹取；
      --   设置页的 Info.json 区间仍由打包器与游戏侧解析负责。
      return do_commit(key, cur, on_commit)
    end

    if click("取消") then
      last = { key = key, value = nil, raw = nil, canceled = true }
      edit_key, edit_buf = nil, nil
      return cur, false
    end
    return cur, false
  end

  -- 非编辑态：显示「标签：当前值 单位」，点击进入编辑态（初值 ASCII）。
  local s = ascii_initial(cur)
  local text = label .. "：" .. s .. ((unit ~= "") and (" " .. unit) or "")
  if click(text) then
    edit_key, edit_buf = key, s
    return cur, false
  end
  return cur, false
end

-- NF.slider(label, cur, lo, hi, on_change?) -> value, changed
--   可选滑块（面板设置 gui_slider 打开时用）。范围 1~1000 由调用方给；
--   当前值在范围外时只把滑块放在边界，**不主动写回**，避免一开开关就把 86400 夹成 1000。
--   只有玩家真的拖动（返回值 != 边界）才回调 on_change。
function NF.slider(label, cur, lo, hi, on_change)
  bind()
  cur = tonumber(cur)
  lo = tonumber(lo) or 1
  hi = tonumber(hi) or 1000
  if lo ~= lo then lo = 1 end
  if hi ~= hi then hi = 1000 end
  if lo > hi then lo, hi = hi, lo end
  if cur == nil or cur ~= cur then cur = lo end
  local cv = cur
  if cv < lo then cv = lo elseif cv > hi then cv = hi end
  if not has("slider") then return cur, false end
  local ok, r = pcall(G.slider, tostring(label or ""), cv, lo, hi)
  if not ok or type(r) ~= "number" or r ~= r or r == math.huge or r == -math.huge then
    return cur, false
  end
  r = math.floor(r + 0.5)
  if r < lo then r = lo elseif r > hi then r = hi end
  if r == cv then return cur, false end
  if type(on_change) == "function" then
    local okc, e = pcall(on_change, r)
    if not okc then set_err("slider on_change 出错：" .. tostring(e)) end
  end
  return r, true
end

return NF
