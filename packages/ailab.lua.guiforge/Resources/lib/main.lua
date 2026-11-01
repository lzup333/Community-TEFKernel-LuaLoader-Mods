-- ============================================================================
--  界面工坊 (GuiForge) v2.0.0
--  LuaLoader 1.8.0 的 mod.gui 实测台 / 开发范本
--
--  【为什么有 v2.0.0】
--   1.8.0 把 mod.gui 从 22 项扩到 **36 项**，新增的 14 项是三类新能力：
--     · 图片     load_image image_status release_image image
--                image_fit nine_slice image_button set_skin
--     · 配色/自绘 set_style rect text_at button_at set_content_height
--     · 标题入口  set_title(title, icon)  ← 收起后变成可拖动的紧凑方块
--   本模组的目标是「装上去就能逐项验证」，所以 9+1 页里每一页对应一组 API。
--
--  【本 Mod 的定位】
--   不碰任何游戏符号（mod.patch 一次都不用）——能力只来自 mod.gui 与
--   mod.read_file / write_file。因此它是「最安全的一类 Mod」样板，也是
--   「没有实机也不会把游戏搞崩」的调试台。
--
--  【页一「概览」会当场告诉你本机是哪一版加载器】
--   它逐个 type() 探测 36 个函数名，缺哪几个就把名字列出来。
--   1.7.1 → 缺 14 项；1.8.0 → 一项不缺。这比读版本号可靠。
--
--  ⚠️ 本工作区无法启动游戏：所有结论来自 1.8.0 上游源码
--     （参考库/上游/LuaLoader-1.8.0/）与假 GUI 逻辑测试，实机结论以实测为准。
-- ============================================================================

mod.meta = { pkg_id = "ailab.lua.guiforge", version = "2.0.0", version_code = 20261015, api_version = 1 }

local VERSION    = "2.0.0"
local STATE_FILE = "guiforge-state.txt"
local PROBE_LOG  = "guiforge-probe.txt"

-- ★ 绝对禁止在 Lua 源码里出现反斜杠转义（本仓库的写文件流程会吃掉它们）
local NL = string.char(10)
local CR = string.char(13)

-- ============================================================================
-- 0. API 名单：36 项，按 1.8.0 的 gui_funcs[] 顺序抄下来
-- ============================================================================
local API36 = {
  "text", "text_wrapped", "button", "checkbox", "slider", "same_line", "separator", "spacing",
  "collapsing_header", "progress_bar", "input_text", "set_title", "set_pos", "get_pos",
  "set_width", "set_cursor", "set_visible", "is_visible", "show", "hide", "set_collapsed",
  "is_collapsed", "toggle_collapsed", "set_style", "rect", "text_at", "button_at",
  "set_content_height", "load_image", "image_status", "release_image", "image", "image_fit",
  "nine_slice", "image_button", "set_skin",
}
-- 1.8.0 新增的 14 项（概览页用来一眼看出「本机多了什么」）
local API_NEW = {
  "load_image", "image_status", "release_image", "image", "nine_slice", "image_fit",
  "image_button", "set_skin", "set_style", "rect", "text_at", "button_at",
  "set_content_height", "set_title",
}

-- ============================================================================
-- 1. TEFManager 设置（键必须与 Info.json 的 settings 完全一致）
-- ============================================================================
local DEFAULTS = {
  enabled          = true,
  auto_restore     = true,
  auto_restore_sec = 20,
  remember_window  = true,
}
local LIMITS = { auto_restore_sec = { 3, 300 } }
local CFG = {}
for k, v in pairs(DEFAULTS) do CFG[k] = v end

local function clamp_iv(v, lo, hi)
  v = math.floor(tonumber(v) or lo)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function clamp_int(v, lim)
  return clamp_iv(v, lim[1], lim[2])
end

local function set_cfg(key, value)
  if DEFAULTS[key] == nil or value == nil then return end
  local t = type(DEFAULTS[key])
  if t == "boolean" then
    CFG[key] = (value == true or value == "true" or value == 1)
  elseif t == "number" then
    local lim = LIMITS[key]
    CFG[key] = lim and clamp_int(value, lim) or (tonumber(value) or DEFAULTS[key])
  else
    CFG[key] = tostring(value)
  end
end

-- ============================================================================
-- 2. 页面与运行时状态
-- ============================================================================
local PAGES = { "概览", "控件", "自绘", "图片", "进阶", "位置", "显隐", "键盘", "穿刺", "速查" }

-- 头部用绝对坐标画 10 个分页按钮（3 列 x 4 行），流式内容从 TOP 开始
local HDR_BTN_W, HDR_BTN_H = 132, 28
local HDR_BTN_DX, HDR_BTN_DY = 136, 32
local TOP = 180

-- ★ 两个「实机逼出来」的安全框（1.7.1 上：宽度调到 900 后滑块点不到；
--   标题栏能被拖出屏幕后抓不回来）。1.8.0 的加载器自己会夹位置，但
--   我们仍然自己夹一次 —— 不依赖加载器版本，也避免持久化坏坐标。
local WIN_W_MIN, WIN_W_MAX, WIN_W_DEFAULT = 300, 700, 460
local POS_MAX_X, POS_MAX_Y = 1200, 300

local S = {
  page          = 1,
  -- 控件页
  slider        = 0.42,
  checkbox      = true,
  text          = "ascii only",
  clicks        = 0,
  header_open   = true,
  header_open2  = false,
  -- 自绘页
  theme         = 1,
  ba_hits       = 0,
  ba_small      = 0,
  -- 图片页
  img_ready     = false,
  -- 进阶页
  ib_hits       = 0,
  mask_hits     = 0,
  skin_on       = false,
  skin_size     = 48,
  skin_border   = 16,
  skin_edge     = 0,
  pending_release = nil,
  release_msg   = "(未测)",
  -- 位置页
  win_w         = WIN_W_DEFAULT,
  width_applied = -1,
  win_x         = 40,
  win_y         = 40,
  pos_valid     = false,
  pos_applied   = false,
  danger_slider = false,   -- ★ 拿 slider 驱动 set_width：1.7.1 上会剧烈抖动
  danger_hits   = 0,
  fx            = 40,
  fy            = 40,
  -- 显隐页
  visible       = true,
  hidden_at     = 0,
  hide_reason   = "",
  collapsed     = false,
  use_icon      = true,
  long_title    = false,
  -- 统计 / 诊断
  frames        = 0,
  fps           = 0,
  fps_t         = 0,
  fps_n         = 0,
  fps_ratio     = 0,
  api_have      = 0,
  api_missing   = {},
  cfg_from      = "(未读)",
  pos_healed    = false,
  last_err      = "",
  err_logged    = false,
  force_save    = false,
  -- 穿刺页（人工判定）
  verdict_button = false,
  verdict_panel  = false,
  verdict_kb     = false,
}

local function clamp_pos(x, y)
  return clamp_iv(x, 0, POS_MAX_X), clamp_iv(y, 0, POS_MAX_Y)
end

local function out_of_safe_area()
  return S.win_x < 0 or S.win_y < 0 or S.win_x > POS_MAX_X or S.win_y > POS_MAX_Y
end

local function log_info(m) if type(mod.info)  == "function" then mod.info(m)  end end
local function log_warn(m) if type(mod.warn)  == "function" then mod.warn(m)  end end
local function log_err(m)  if type(mod.error) == "function" then mod.error(m) end end

local function now() return os.time() end

local function split_lines(t)
  local out = {}
  for line in string.gmatch(t, "[^" .. NL .. CR .. "]+") do out[#out + 1] = line end
  return out
end

-- ============================================================================
-- 3. 读 TEFManager 的 config.json（结构：{"values":{"key":值}}）
-- ============================================================================
local function read_config()
  if type(mod.read_file) ~= "function" then S.cfg_from = "(无 read_file)" return false end
  local okr, raw = pcall(mod.read_file, "config.json")
  if not okr or type(raw) ~= "string" or raw == "" then S.cfg_from = "(读不到，用默认值)" return false end
  local function get(key, pat)
    return raw:match('"' .. key .. '"%s*:%s*' .. pat)
  end
  for key, dflt in pairs(DEFAULTS) do
    local t = type(dflt)
    if t == "boolean" then
      local m = get(key, "([%a]+)")
      if m then set_cfg(key, m == "true") end
    elseif t == "number" then
      local m = get(key, "(-?%d+)")
      if m then set_cfg(key, tonumber(m)) end
    else
      local m = get(key, '"([^"]*)"')
      if m then set_cfg(key, m) end
    end
  end
  S.cfg_from = "config.json"
  return true
end

-- ============================================================================
-- 4. 自己的状态文件（私有目录内，key=value）
-- ============================================================================
local function save_state()
  if type(mod.write_file) ~= "function" then return false end
  local wx, wy = clamp_pos(S.win_x, S.win_y)
  local lines = {
    "v=" .. VERSION,
    "page=" .. tostring(S.page),
    "theme=" .. tostring(S.theme),
    "win_w=" .. tostring(clamp_iv(S.win_w, WIN_W_MIN, WIN_W_MAX)),
    "wx=" .. tostring(S.pos_valid and wx or -1),
    "wy=" .. tostring(S.pos_valid and wy or -1),
    "header_open=" .. (S.header_open and "1" or "0"),
    "use_icon=" .. (S.use_icon and "1" or "0"),
  }
  local okw, err = pcall(mod.write_file, STATE_FILE, table.concat(lines, NL))
  if not okw then log_warn("界面工坊：状态写入失败：" .. tostring(err)) return false end
  return true
end

local function load_state()
  if type(mod.read_file) ~= "function" then return false end
  local okr, raw = pcall(mod.read_file, STATE_FILE)
  if not okr or type(raw) ~= "string" or raw == "" then return false end
  local function num(key)
    local v = raw:match(key .. "=(-?%d+)")
    return v and tonumber(v) or nil
  end
  local p = num("page")
  if p and p >= 1 and p <= #PAGES then S.page = p end
  local th = num("theme")
  if th and th >= 1 then S.theme = th end
  local w = num("win_w")
  if w then S.win_w = clamp_iv(w, WIN_W_MIN, WIN_W_MAX) end
  local wx, wy = num("wx"), num("wy")
  if wx and wy and wx >= 0 and wy >= 0 then
    local cx, cy = clamp_pos(wx, wy)
    if cx ~= wx or cy ~= wy then S.pos_healed = true end
    S.win_x, S.win_y, S.pos_valid = cx, cy, true
  end
  if raw:match("header_open=0") then S.header_open = false end
  if raw:match("use_icon=0")    then S.use_icon = false end
  return true
end

-- ============================================================================
-- 5. 帧率（纯 Lua 计数，绝不碰游戏 API）
-- ============================================================================
local function tick_frames()
  S.frames = S.frames + 1
  local t = now()
  if S.fps_t ~= t then
    if S.fps_t > 0 then S.fps = S.fps_n end
    S.fps_t = t
    S.fps_n = 0
  end
  S.fps_n = S.fps_n + 1
  S.fps_ratio = math.min(1.0, math.max(0.0, S.fps / 60.0))
end

-- ============================================================================
-- 6. 图片：全部延迟到 on_gui 里加载（load_image 依赖私有目录，setup 里没有）
-- ============================================================================
local IMG = {}
local IMG_TRIED = false
local IMG_STATUS = {}
local IMG_ORDER = { "white", "panel", "button", "icon", "atlas", "mask", "stretch" }
local IMG_PATHS = {
  white   = "lib/ui/white.png",
  panel   = "lib/ui/panel.png",
  button  = "lib/ui/button.png",
  icon    = "lib/ui/icon.png",
  atlas   = "lib/ui/atlas.png",
  mask    = "lib/ui/mask.png",
  stretch = "lib/ui/stretch.png",
}

local WHITE = { 255, 255, 255, 255 }
local HILITE = { 255, 224, 130, 255 }
local MUTED  = { 168, 186, 200, 255 }
local DARKBG = { 14, 20, 28, 210 }

local G = nil

local function has(name)
  return G ~= nil and type(G[name]) == "function"
end

-- 所有对 mod.gui 的调用都走 pcall：本面板不允许把异常抛回加载器
local function api(name, ...)
  if not has(name) then return false, nil end
  return pcall(G[name], ...)
end

local function ensure_images()
  if IMG_TRIED then return end
  IMG_TRIED = true
  if type(G.load_image) ~= "function" then return end
  S.img_ready = true
  for _, name in ipairs(IMG_ORDER) do
    local ok, id = pcall(G.load_image, IMG_PATHS[name])
    if ok and type(id) == "string" then IMG[name] = id end
  end
end

local function refresh_status()
  if type(G.image_status) ~= "function" then return end
  local n = 0
  for _, name in ipairs(IMG_ORDER) do
    local id = IMG[name]
    if id then
      local ok, st, w, h = pcall(G.image_status, id)
      if ok then
        IMG_STATUS[name] = tostring(st) .. " " .. tostring(w) .. "x" .. tostring(h)
        if tostring(st) == "ready" then n = n + 1 end
      else
        IMG_STATUS[name] = "(status 调用失败)"
      end
    else
      IMG_STATUS[name] = "nil（load_image 返回 nil）"
    end
  end
  S.img_count = n
end

local function img(name, x, y, w, h, color, source)
  local id = IMG[name]
  if not id then return end
  api("image", id, x, y, w, h, color or WHITE, source)
end

local function img_fit(name, x, y, w, h, mode, color)
  local id = IMG[name]
  if not id then return end
  api("image_fit", id, x, y, w, h, mode or "contain", color or WHITE)
end

local function nine(name, x, y, w, h, border, color, edge)
  local id = IMG[name]
  if not id or type(border) ~= "number" or border <= 0 then return end
  api("nine_slice", id, x, y, w, h, math.floor(border), color or WHITE, edge or 0)
end

local function img_button(name, x, y, w, h, label, border)
  local id = IMG[name]
  if not id then return false end
  local ok, hit = api("image_button", id, x, y, w, h, label or "", border or 0)
  return ok and hit == true
end

-- ============================================================================
-- 7. 配色（set_style 的 7 个键）
-- ============================================================================
local THEMES = {
  { name = "默认", style = nil },
  { name = "暗夜", style = {
      panel = { 16, 18, 26, 245 }, title = { 38, 40, 58, 255 }, button = { 44, 48, 70, 255 },
      hover = { 62, 68, 98, 255 }, active = { 30, 34, 52, 255 }, border = { 8, 9, 14, 255 },
      text = { 222, 228, 248, 255 } } },
  { name = "青铜", style = {
      panel = { 48, 36, 20, 245 }, title = { 92, 66, 30, 255 }, button = { 104, 76, 34, 255 },
      hover = { 128, 96, 44, 255 }, active = { 72, 52, 22, 255 }, border = { 28, 20, 10, 255 },
      text = { 246, 232, 196, 255 } } },
  { name = "高对比", style = {
      panel = { 0, 0, 0, 255 }, title = { 236, 236, 236, 255 }, button = { 30, 30, 30, 255 },
      hover = { 255, 215, 0, 255 }, active = { 255, 255, 255, 255 }, border = { 255, 255, 255, 255 },
      text = { 255, 255, 0, 255 } } },
}

local function apply_theme()
  local t = THEMES[clamp_iv(S.theme, 1, #THEMES)]
  if t and t.style and has("set_style") then pcall(G.set_style, t.style) end
end

-- ============================================================================
-- 8. 头部（绝对坐标分页）与窗口几何
-- ============================================================================
local function mode_line()
  local n = #API_NEW
  local miss = 0
  for _, k in ipairs(API_NEW) do if type(G[k]) ~= "function" then miss = miss + 1 end end
  if miss == 0 then
    return "本机 mod.gui " .. tostring(S.api_have) .. "/36  ·  1.8.0 新增的 14 项全部可用  ·  帧 " .. tostring(S.frames)
  end
  return "本机 mod.gui " .. tostring(S.api_have) .. "/36  ·  缺 " .. tostring(miss) .. " 项新功能（旧加载器）  ·  帧 " .. tostring(S.frames)
end

local function draw_header()
  apply_theme()
  local abs_ok = has("text_at") and has("button_at")
  if abs_ok then
    pcall(G.text_at, 0, 0, "界面工坊 GuiForge v" .. VERSION .. "  —— LuaLoader 1.8.0 mod.gui 实测台", WHITE, 1.0)
    pcall(G.text_at, 0, 26, mode_line(), MUTED, 0.8)
    for i = 1, #PAGES do
      local col = (i - 1) % 3
      local row = math.floor((i - 1) / 3)
      local label = (i == S.page and "> " or "") .. PAGES[i]
      local ok, hit = pcall(G.button_at, col * HDR_BTN_DX, 52 + row * HDR_BTN_DY, HDR_BTN_W, HDR_BTN_H, label)
      if ok and hit == true then S.page = i end
    end
    pcall(G.set_cursor, 0, TOP)
  else
    G.text("界面工坊 GuiForge v" .. VERSION .. "（加载器无 1.8.0 绝对定位 API，降级为流式布局）")
    G.text(mode_line())
    for i = 1, #PAGES do
      if (i - 1) % 3 ~= 0 then G.same_line() end
      local label = (i == S.page and "> " or "") .. PAGES[i]
      if G.button(label) then S.page = i end
    end
  end
end

local function apply_window_geometry()
  if S.width_applied ~= S.win_w then
    api("set_width", S.win_w)
    S.width_applied = S.win_w
  end
  if not S.pos_applied then
    local x, y = clamp_pos(S.win_x, S.win_y)
    if api("set_pos", x, y) then
      S.pos_applied = true
      S.pos_valid = true
    end
  end
end

local function try_auto_restore()
  if not CFG.auto_restore then return end
  if now() - S.hidden_at >= CFG.auto_restore_sec then
    S.visible = true
    S.pos_applied = false
    api("show")
  end
end

local function hide_panel(why, raw_hide)
  S.hidden_at = now()
  S.hide_reason = why
  if raw_hide then api("hide") else api("set_visible", false) end
  S.visible = false
end

local function set_title_now()
  local title = S.long_title and "界面工坊 GuiForge v2.0.0 · 1.8.0 实测台" or ("GuiForge " .. VERSION)
  local icon = S.use_icon and "册" or ""
  api("set_title", title, icon)
end

-- ============================================================================
-- 9. 各页
-- ============================================================================
local function page_overview()
  G.text("本页回答一个问题：这台设备上的 mod.gui 到底有几项？")
  if #S.api_missing == 0 then
    G.text("实测：36 / 36 全部存在 —— 加载器就是 1.8.0 或更新。")
    G.text("1.7.1 只有 22 项；1.8.0 新增的 14 项本机全在。")
  else
    G.text(string.format("实测：%d / 36，缺 %d 项", S.api_have, #S.api_missing))
    G.text_wrapped("缺失：" .. table.concat(S.api_missing, " "))
    G.text("→ 本机加载器是 1.7.1 或更旧，进阶页会自动降级。")
  end
  G.separator()
  G.text(string.format("平台 %s/%s   帧计数 %d   帧率估计 %.1f", tostring(mod.platform), tostring(mod.arch), S.frames, S.fps))
  G.progress_bar(S.fps_ratio)
  G.text("上面这条 progress_bar 用的是纯 Lua 帧计数，不是游戏内置 FPS。")
  G.separator()
  G.text("设置来源：" .. tostring(S.cfg_from) .. "   enabled=" .. tostring(CFG.enabled))
  G.text_wrapped("本模组不使用任何游戏符号（一次 mod.patch 都没有），能力只来自 mod.gui 与 mod.read_file/write_file —— 这是「最安全的一类 Mod」样板。")
  G.separator()
  if G.button("复位窗口：位置 (40,40) · 宽度 460 · 默认配色") then
    S.win_x, S.win_y = 40, 40
    S.pos_applied = false
    S.win_w = WIN_W_DEFAULT
    S.width_applied = -1
    S.theme = 1
  end
  G.same_line()
  if G.button("立刻保存状态") then S.force_save = true end
end

local function page_widgets()
  G.text("内置控件：1.4.0 起的 11 项，流式布局（从上到下）")
  if G.button("button 点我（" .. tostring(S.clicks) .. " 次）") then S.clicks = S.clicks + 1 end
  G.same_line()
  G.text("← same_line() 让这一行跟在按钮后面")
  S.checkbox = G.checkbox("checkbox 开关", S.checkbox)
  G.text(string.format("slider 当前值 = %.3f", S.slider))
  S.slider = G.slider("slider", S.slider, 0.0, 1.0)
  G.text("progress_bar(slider)：")
  G.progress_bar(S.slider)
  G.separator()
  G.text("collapsing_header 只返回开关状态，不会自动隐藏后面的内容：")
  S.header_open = G.collapsing_header("第 1 层（正确用法是用 if 包住内容）")
  if S.header_open then
    G.text("   第 1 层的内容 —— 这就是「自己 if」的正确写法")
    G.spacing()
    S.header_open2 = G.collapsing_header("   第 2 层")
    if S.header_open2 then G.text("      第 2 层的内容") end
  end
  G.separator()
  G.text("input_text（自绘键盘，只能 ASCII；细节见「键盘」页）：")
  S.text = G.input_text("text", S.text)
  G.spacing()
  G.text_wrapped("text_wrapped：这一句会按窗口内容宽自动折行。把宽度调到很窄再回来看，折行位置会变。")
end

local function page_custom()
  if not (has("rect") and has("text_at") and has("button_at") and has("set_content_height")) then
    G.text("本页需要 LuaLoader 1.8.0（rect / text_at / button_at / set_content_height）")
    return
  end
  local y0 = TOP
  -- ★ 本页刻意**只用绝对坐标**：rect/text_at/button_at 都是相对窗口内容区左上角，
  --   末尾必须 set_content_height，否则窗口高度只剩标题栏。
  pcall(G.text_at, 0, y0, "set_style：覆盖本 Mod 窗口的 7 个配色键（只影响调用者）", WHITE, 0.75)
  for i, t in ipairs(THEMES) do
    local label = (S.theme == i and "[*] " or "") .. t.name
    local okb, hit = pcall(G.button_at, (i - 1) * 92, y0 + 18, 88, 26, label)
    if okb and hit == true then S.theme = i end
  end
  if THEMES[S.theme].style then pcall(G.set_style, THEMES[S.theme].style) end
  pcall(G.text_at, 0, y0 + 50, "当前配色 = " .. THEMES[S.theme].name, HILITE, 0.75)
  pcall(G.rect, 0, y0 + 70, 300, 40, { 40, 90, 140, 255 })
  pcall(G.text_at, 10, y0 + 78, "rect(x,y,w,h,color) + text_at 叠字", WHITE, 1.0)
  pcall(G.text_at, 10, y0 + 96, "rect 走 DrawInvBG 底纹；w 或 h < 24 时改用 1x1 白图", MUTED, 0.7)
  pcall(G.rect, 320, y0 + 78, 8, 8, { 220, 80, 80, 255 })
  pcall(G.rect, 320, y0 + 92, 60, 4, { 240, 210, 90, 255 })
  pcall(G.text_at, 0, y0 + 118, "text_at 的字号：scale 只能落在 (0,4]，4 以上什么都不画", WHITE, 0.8)
  pcall(G.text_at, 0,   y0 + 142, "0.5", HILITE, 0.5)
  pcall(G.text_at, 36,  y0 + 142, "1",   HILITE, 1.0)
  pcall(G.text_at, 62,  y0 + 142, "1.5", HILITE, 1.5)
  pcall(G.text_at, 130, y0 + 142, "2",   HILITE, 2.0)
  pcall(G.text_at, 180, y0 + 142, "3",   HILITE, 3.0)
  pcall(G.text_at, 0, y0 + 236, string.format("button_at 命中：大框 %d 次 · 小框 %d 次 · 指定坐标 %d 次",
        S.ba_hits, S.ba_small, S.ba_line or 0), WHITE, 0.8)
  local okb, hit = pcall(G.button_at, 0, y0 + 258, 300, 34, "button_at 300x34（全宽）")
  if okb and hit == true then S.ba_hits = S.ba_hits + 1 end
  local oks, hs = pcall(G.button_at, 0, y0 + 296, 140, 30, "140x30")
  if oks and hs == true then S.ba_small = S.ba_small + 1 end
  local okl, hl = pcall(G.button_at, 148, y0 + 296, 140, 30, "指定坐标的按钮")
  if okl and hl == true then S.ba_line = (S.ba_line or 0) + 1 end
  pcall(G.text_at, 0, y0 + 332, "set_content_height(TOP + 340)：不声明的话窗口高度只剩标题栏", MUTED, 0.7)
  pcall(G.set_content_height, TOP + 340)
end

local function page_images()
  ensure_images()
  refresh_status()
  if not S.img_ready then
    G.text("本机没有 load_image（需要 LuaLoader 1.8.0）")
    G.text("图片必须放在 Resources/lib/ui/ 下，路径写 lib/ui/x.png")
    return
  end
  local y0 = TOP
  if has("text_at") then
    pcall(G.text_at, 0, y0, "图片：PNG 放 Resources/lib/ui/，路径写 lib/ui/x.png；解码/上传在回调结束后执行", WHITE, 0.8)
    for i, name in ipairs(IMG_ORDER) do
      pcall(G.text_at, 0, y0 + 20 + (i - 1) * 18,
        string.format("%-8s -> %s", name .. ".png", tostring(IMG_STATUS[name])), MUTED, 0.7)
    end
    pcall(G.text_at, 0, y0 + 150, string.format("image_status 为 ready 的有 %d/7 张；第 1 帧通常是 pending", S.img_count or 0), HILITE, 0.75)
    pcall(G.text_at, 0, y0 + 168, "image()：32x32 拉伸到 220x54（四角白点应保持方形才是正确拉伸）", WHITE, 0.75)
  end
  img("stretch", 0, y0 + 186, 220, 54)
  img("stretch", 232, y0 + 186, 100, 54, { 255, 90, 90, 150 })
  if has("text_at") then
    pcall(G.text_at, 0, y0 + 246, "image(...,source)：从 128x128 图集里裁出 4 个 64x64 象限", WHITE, 0.75)
  end
  img("atlas", 0,   y0 + 264, 56, 56, WHITE, { 0, 0, 64, 64 })
  img("atlas", 60,  y0 + 264, 56, 56, WHITE, { 64, 0, 64, 64 })
  img("atlas", 120, y0 + 264, 56, 56, WHITE, { 0, 64, 64, 64 })
  img("atlas", 180, y0 + 264, 56, 56, WHITE, { 64, 64, 64, 64 })
  if has("text_at") then
    pcall(G.text_at, 0, y0 + 326, "image_fit：同一个 64x64 图标塞进 130x40 的框 —— 左 contain（完整），右 cover（填满并居中裁切）", WHITE, 0.75)
  end
  img("white", 0,   y0 + 344, 130, 40, DARKBG)
  img("white", 140, y0 + 344, 130, 40, DARKBG)
  img_fit("icon", 0,   y0 + 344, 130, 40, "contain")
  img_fit("icon", 140, y0 + 344, 130, 40, "cover")
  if has("set_content_height") then pcall(G.set_content_height, TOP + 392) end
end

local function page_advanced()
  ensure_images()
  refresh_status()
  if not (has("nine_slice") and has("text_at")) then
    G.text("本页需要 LuaLoader 1.8.0（nine_slice / image_button / set_skin）")
    return
  end
  local y0 = TOP
  pcall(G.text_at, 0, y0, "nine_slice：等宽四边九宫格，border 是**源图**像素，目标边框默认同像素", WHITE, 0.85)
  nine("panel", 0,   y0 + 22, 220, 50, 16)
  nine("panel", 232, y0 + 22, 100, 50, 16, WHITE, 26)
  nine("panel", 0,   y0 + 82, 40, 26, 16)
  pcall(G.text_at, 0, y0 + 114, "← 三个目标共用一个 64x64 面板（border=16）：中间那个用了 edge=26 放大边框，右边那个目标小于 2*border", MUTED, 0.7)
  pcall(G.text_at, 0, y0 + 136, "image_button：border>0 走九宫格；mask.png 是菱形但命中区仍是矩形", WHITE, 0.85)
  if img_button("button", 0, y0 + 158, 220, 40, "图片按钮", 12) then S.ib_hits = S.ib_hits + 1 end
  if img_button("mask", 232, y0 + 158, 72, 72, "", 0) then S.mask_hits = S.mask_hits + 1 end
  pcall(G.text_at, 0, y0 + 234, string.format("图片按钮命中 %d 次 · 点菱形透明四角也会中的次数 %d", S.ib_hits, S.mask_hits), HILITE, 0.8)
  pcall(G.text_at, 0, y0 + 258, "white.png(1x1) + color 调制 = 真正的纯色矩形（rect 做不到纯色）：", WHITE, 0.8)
  img("white", 0, y0 + 280, 200, 14, { 255, 150, 40, 255 })
  img("white", 208, y0 + 280, 120, 14, { 80, 200, 255, 120 })
  pcall(G.text_at, 0, y0 + 302, "set_skin：用图片当窗口面板 + 收起入口图片（iconSize 必须 24~128）", WHITE, 0.8)
  local okb, hit = pcall(G.button_at, 0, y0 + 324, 170, 28, S.skin_on and "关闭图片皮肤（自救）" or "开启图片皮肤")
  if okb and hit == true then S.skin_on = not S.skin_on end
  local okm, hm = pcall(G.button_at, 178, y0 + 324, 60, 28, "size+")
  if okm and hm == true then S.skin_size = clamp_iv(S.skin_size + 8, 24, 128) end
  local okn, hn = pcall(G.button_at, 242, y0 + 324, 60, 28, "size-")
  if okn and hn == true then S.skin_size = clamp_iv(S.skin_size - 8, 24, 128) end
  local oke, he = pcall(G.button_at, 0, y0 + 358, 170, 28, "edge " .. tostring(S.skin_edge))
  if oke and he == true then S.skin_edge = (S.skin_edge == 0) and 24 or 0 end
  pcall(G.text_at, 178, y0 + 362, string.format("iconSize=%d edge=%d", S.skin_size, S.skin_edge), MUTED, 0.7)
  if S.skin_on and IMG.panel and IMG.icon then
    pcall(G.set_skin, IMG.panel, S.skin_border, IMG.icon, S.skin_size, S.skin_edge)
  end
  -- release_image 的生命周期：加载 → 查状态 → 请求释放 → 下一帧再查
  local okr, hr = pcall(G.button_at, 0, y0 + 392, 170, 28, "release_image 生命周期")
  if okr and hr == true then
    local ok1, id = pcall(G.load_image, "lib/ui/stretch.png")
    if ok1 and type(id) == "string" then
      local _, st = pcall(G.image_status, id)
      pcall(G.release_image, id)
      S.pending_release = id
      S.release_msg = "释放前 " .. tostring(st)
    else
      S.release_msg = "load_image 失败"
    end
  end
  if S.pending_release then
    local _, st2 = pcall(G.image_status, S.pending_release)
    S.release_msg = S.release_msg .. " → 释放后 " .. tostring(st2)
    S.pending_release = nil
  end
  pcall(G.text_at, 178, y0 + 396, S.release_msg, HILITE, 0.7)
  pcall(G.set_content_height, TOP + 426)
end

local function page_position()
  local okp, x, y = api("get_pos")
  if not (okp and type(x) == "number") then x, y = 0, 0 end
  G.text(string.format("当前位置 = (%.0f, %.0f)   宽度 = %d", x, y, S.win_w))
  if out_of_safe_area() then G.text("⚠ 记录的位置越界，已自动夹回安全框") end
  if G.button("(20,20)") then S.win_x, S.win_y, S.pos_applied = 20, 20, false end
  G.same_line()
  if G.button("(60,60)") then S.win_x, S.win_y, S.pos_applied = 60, 60, false end
  G.same_line()
  if G.button("(200,160)") then S.win_x, S.win_y, S.pos_applied = 200, 160, false end
  G.same_line()
  if G.button("复位") then S.win_x, S.win_y, S.pos_applied = 40, 40, false end
  G.separator()
  G.text("set_width：只在值变化时调一次（每帧调会把窗口按死）")
  if G.button("宽 -40") then S.win_w = clamp_iv(S.win_w - 40, WIN_W_MIN, WIN_W_MAX) end
  G.same_line()
  if G.button("宽 +40") then S.win_w = clamp_iv(S.win_w + 40, WIN_W_MIN, WIN_W_MAX) end
  G.same_line()
  if G.button("宽 = 460") then S.win_w = WIN_W_DEFAULT end
  G.same_line()
  if G.button(S.danger_slider and "关掉危险滑块" or "打开危险滑块") then S.danger_slider = not S.danger_slider end
  G.text("★ 下面这个滑块刻意拿 set_width 当被控量：")
  if S.danger_slider then
    G.text("⚠ 已开启。1.7.1 上拖动会剧烈抖动（轨道 x 由窗口宽度决定 → 自反馈）。")
    if has("slider") then
      S.win_w = clamp_iv(G.slider("窗口宽度（危险）", S.win_w, WIN_W_MIN, WIN_W_MAX), WIN_W_MIN, WIN_W_MAX)
      S.danger_hits = S.danger_hits + 1
    end
  else
    G.text("   （关闭状态：不调用，所以默认不会抖）")
  end
  G.separator()
  G.text(string.format("set_cursor 标记位置 = (%d, %d)", S.fx, S.fy))
  if G.button("标记 x+20") then S.fx = clamp_iv(S.fx + 20, 0, 300) end
  G.same_line()
  if G.button("标记 x-20") then S.fx = clamp_iv(S.fx - 20, 0, 300) end
  G.same_line()
  if G.button("标记 y+12") then S.fy = clamp_iv(S.fy + 12, 0, 200) end
  G.same_line()
  if G.button("set_cursor 归零") then S.fx, S.fy = 0, 0 end
end

local function page_visible()
  local okv, vis = api("is_visible")
  G.text("is_visible() = " .. tostring(okv and vis or "?"))
  G.text("is_collapsed() = " .. tostring(select(2, api("is_collapsed"))))
  if G.button("hide() 隐藏") then hide_panel("hide()", true) end
  G.same_line()
  if G.button("set_visible(false)") then hide_panel("set_visible(false)", false) end
  G.same_line()
  if G.button("show() 显示") then api("show") end
  G.text_wrapped("注意：隐藏（visible=false）时加载器**仍然每帧回调 on_gui**，所以才能自己 show() 回来；本模组还有 auto_restore 兜底。")
  G.separator()
  G.text("★ 收起（collapsed）跟隐藏完全不同：收起后加载器**直接 return，不再回调 on_gui**")
  if G.button("收起") then S.collapsed = true; api("set_collapsed", true) end
  G.same_line()
  if G.button("展开") then S.collapsed = false; api("set_collapsed", false) end
  G.same_line()
  if G.button("toggle_collapsed()") then
    S.collapsed = not S.collapsed
    api("toggle_collapsed")
  end
  G.text_wrapped("一旦收起，本函数就再也调不到 —— 只能点标题栏左端的箭头，或者（设置了 icon 时）点紧凑方块展开。")
  G.separator()
  G.text("set_title(title, icon)：icon 会让「收起」变成一个可拖动的紧凑入口方块")
  if G.button(S.long_title and "用短标题" or "用长标题") then S.long_title = not S.long_title; set_title_now() end
  G.same_line()
  if G.button(S.use_icon and "取消紧凑图标" or "启用紧凑图标(册)") then S.use_icon = not S.use_icon; set_title_now() end
  G.separator()
  if G.button("保存状态") then S.force_save = true end
  G.same_line()
  if G.button("重读状态文件") then
    load_state()
    S.pos_applied = false
    S.width_applied = -1
  end
end

local function page_keyboard()
  G.text("虚拟键盘：input_text 点击后弹出，加载器自绘，**不走系统输入法**")
  S.text = G.input_text("输入框", S.text)
  local n_bytes = #S.text
  local n_chars = 0
  local okc, cnt = pcall(utf8 and utf8.len, S.text)
  if okc and type(cnt) == "number" then n_chars = cnt else n_chars = -1 end
  G.text(string.format("字节数 = %d   字符数 = %s", n_bytes, tostring(n_chars)))
  G.text_wrapped("键盘是 ASCII 版（数字行 + qwerty 三行 + shift + del），没有中文输入法。")
  G.text_wrapped("★ 退格是 C++ 的 pop_back()：删的是**1 个字节**。所以输入框放中文初值、再按 del，会留下半个非法 UTF-8 → 乱码/方块。")
  if G.button("塞一个中文初值（然后按 del 试试）") then S.text = "中文测试" end
  G.same_line()
  if G.button("清空") then S.text = "" end
  G.same_line()
  if G.button("ASCII 初值") then S.text = "hello 123" end
  G.separator()
  G.text("键盘几何由 gui_keyboard_bounds.hpp 定义（与绘制共用同一份常量）")
  G.text_wrapped("官方文档 §6 声称：键盘区域内的触摸不会落到游戏上，且键盘出现时该区域属于 GUI 的输入屏蔽范围。")
  if G.button("把窗口移到屏幕底部（看键盘是否压住窗口）") then
    S.win_x, S.win_y, S.pos_applied = 20, POS_MAX_Y, false
  end
  G.same_line()
  if G.button("回到(40,40)") then S.win_x, S.win_y, S.pos_applied = 40, 40, false end
  G.spacing()
  G.text_wrapped("要观察的：① 键盘弹出时是否遮住窗口下半部分；② 点键盘按键时是否同时触发了游戏操作；③ 键盘外的窗口区域点按是否仍然穿透。")
end

local function page_probe()
  G.text("穿刺复测：1.7.1 实测「点面板会把周围挖掉」，1.8.0 换了输入屏蔽方案")
  G.text_wrapped("1.8.0 的做法：钩住 CursorInputLayer.UpdateCursor（在按键回调之前），把那一根手指的 Cursor 标记为 IgnoreForWorld 并让它不参与世界分发；键盘区域也单独算输入归属。")
  G.separator()
  G.text("操作步骤：")
  G.text("  1) 手上拿镐子/武器")
  G.text("  2) 点下面这个按钮，看世界有没有被挖")
  G.text("  3) 点本页的空白面板处，再看一次")
  G.text("  4) 打开输入框弹出键盘，点键盘上的键，看世界有没有被挖")
  G.separator()
  if G.button("点我：按钮收到的点击 = " .. tostring(S.clicks)) then S.clicks = S.clicks + 1 end
  G.spacing()
  S.verdict_button = G.checkbox("确认①：点按钮时，世界没有被挖/没触发游戏操作", S.verdict_button)
  S.verdict_panel  = G.checkbox("确认②：点面板空白处，世界也没有被挖", S.verdict_panel)
  S.verdict_kb     = G.checkbox("确认③：点虚拟键盘时，世界也没有被挖", S.verdict_kb)
  G.separator()
  if G.button("把三条判定写进 " .. PROBE_LOG) then
    local lines = {
      "VERSION=" .. VERSION,
      "platform=" .. tostring(mod.platform) .. "/" .. tostring(mod.arch),
      "api_have=" .. tostring(S.api_have) .. "/36",
      "verdict_button=" .. tostring(S.verdict_button),
      "verdict_panel=" .. tostring(S.verdict_panel),
      "verdict_keyboard=" .. tostring(S.verdict_kb),
      "clicks=" .. tostring(S.clicks),
      "saved_at=" .. tostring(now()),
    }
    local okw, err = pcall(mod.write_file, PROBE_LOG, table.concat(lines, NL))
    G.text(okw and ("已写入 " .. PROBE_LOG) or ("写入失败：" .. tostring(err)))
  end
  G.text_wrapped("注：本模组无法自己判断「世界有没有被挖」，所以这三条必须由你勾选后写文件，我按文件内容回填文档。")
end

local function page_cheatsheet()
  if not has("text_at") then
    G.text("速查表需要 1.8.0 的 text_at；本机加载器较旧。")
    G.text_wrapped("36 项清单见 开发文档/17-GUI-1.8.md 与 参考库/api/lualoader-1.8.0-gui.tsv")
    return
  end
  local L = {
    "36 项 = 1.7.1 的 22 项 + 1.8.0 新增 14 项；旧 Mod 无需修改。",
    "新增·图片：load_image image_status release_image image image_fit nine_slice image_button set_skin",
    "新增·自绘：set_style rect text_at button_at set_content_height",
    "新增·标题：set_title(title, icon?)  —— icon 非空则收起为可拖动紧凑方块",
    "坑1 set_width：本帧背景/内容宽仍是旧值，下一帧才变；<=60 被忽略。",
    "坑2 set_collapsed：收起后加载器不再回调 on_gui，代码里再也展开不了。",
    "坑3 set_visible(false)：仍会每帧回调（可自救），但不绘制、不响应点击。",
    "坑4 slider：轨道只在右侧 45%；轨道 x 由窗口宽度决定，拿它驱动 set_width 会抖。",
    "坑5 collapsing_header：只返回状态，不会隐藏内容，要自己 if。",
    "坑6 input_text：按字节存；del 是 pop_back()，删中文会留半个 UTF-8。",
    "坑7 text_at：scale 必须落在 (0,4]，4 以上什么都不画。",
    "坑8 set_content_height：覆盖而非累加；纯绝对布局必须调它，否则窗口只剩标题栏。",
    "坑9 图片：路径相对私有目录（lib/ui/x.png），仅 PNG，<=2048x2048、<=16MiB，128 张/64MiB 上限。",
    "坑10 image_status：pending / ready / failed: 原因（有空格） / invalid。",
    "坑11 release_image：排到下一渲染帧，旧 id 立即不可再用。",
    "坑12 set_skin：iconSize 必须 24~128、border>0、两个 id 都属于自己，否则整次调用被忽略。",
    "坑13 nine_slice：目标小于 2*border 会压缩边框；edge 用来显式指定目标边框像素。",
    "坑14 image_button：命中区是矩形，不做透明像素检测。",
    "坑15 层级：PE 上窗口在游戏 HUD 之下（上游已知），没有 z-order API。",
    "坑16 没有样式/字体 API，也没有中文输入；圆角/异形只能用透明 PNG。",
  }
  local y = TOP
  pcall(G.text_at, 0, y - 26, "速查（36 项签名与 16 条坑，完整版见 开发文档/17-GUI-1.8.md）", WHITE, 0.85)
  for i = 1, #L do
    pcall(G.text_at, 0, y + (i - 1) * 16, L[i], (i <= 4) and HILITE or MUTED, 0.7)
  end
  pcall(G.set_content_height, TOP + #L * 16 + 12)
end

-- ============================================================================
-- 10. mod.on_gui —— 加载器每帧回调一次（必须挂在 mod 表上）
-- ============================================================================
function mod.on_gui()
  G = mod.gui
  if type(G) ~= "table" then return end
  tick_frames()

  if not S.visible then
    try_auto_restore()
    return
  end

  if not CFG.enabled then
    local ok = pcall(function()
      G.text("界面工坊已停用（config.json: enabled = false）")
      if G.button("重新启用") then
        set_cfg("enabled", true)
        S.pos_applied = false
      end
    end)
    if not ok then S.last_err = "disabled-branch" end
    return
  end

  local ok, err = pcall(function()
    -- 运行时探测：本机到底有几项
    local have, missing = 0, {}
    for _, n in ipairs(API36) do
      if type(G[n]) == "function" then have = have + 1 else missing[#missing + 1] = n end
    end
    S.api_have, S.api_missing = have, missing

    apply_window_geometry()
    set_title_now()

    local okp, px, py = api("get_pos")
    if okp and type(px) == "number" then
      S.win_x, S.win_y, S.pos_valid = px, py, true
    end

    if S.page < 1 or S.page > #PAGES then S.page = 1 end
    draw_header()

    local p = PAGES[S.page]
    if     p == "概览" then page_overview()
    elseif p == "控件" then page_widgets()
    elseif p == "自绘" then page_custom()
    elseif p == "图片" then page_images()
    elseif p == "进阶" then page_advanced()
    elseif p == "位置" then page_position()
    elseif p == "显隐" then page_visible()
    elseif p == "键盘" then page_keyboard()
    elseif p == "穿刺" then page_probe()
    else page_cheatsheet() end
  end)

  if not ok then
    S.last_err = tostring(err)
    if not S.err_logged then
      S.err_logged = true
      log_err("界面工坊：on_gui 出错，已停用面板以免刷屏：" .. tostring(err))
      S.visible = false
      S.hidden_at = 0
    end
  end

  if S.force_save then
    S.force_save = false
    if save_state() then log_info("界面工坊：状态已保存") end
  end
end

-- ============================================================================
-- 11. 生命周期：setup / cleanup 里绝不调用游戏方法（本 Mod 本来也不调）
-- ============================================================================
function setup()
  read_config()
  load_state()
  S.width_applied = -1
  S.applied = false
  S.pos_applied   = false
  S.visible       = true
  S.fps_t         = now()
  S.theme         = clamp_iv(S.theme, 1, #THEMES)
  S.win_w         = clamp_iv(S.win_w, WIN_W_MIN, WIN_W_MAX)
  log_info(string.format(
    "界面工坊 v%s 已加载：%s/%s。定义 mod.on_gui 后加载器每帧回调；本 Mod 不使用任何游戏符号。",
    VERSION, tostring(mod.platform), tostring(mod.arch)))
  if S.pos_healed then
    log_warn(string.format("界面工坊：上次记录的窗口位置在屏幕外，已回落到 (%d, %d)", S.win_x, S.win_y))
  end
end

function mod.cleanup()
  if CFG.remember_window then save_state() end
  log_info("界面工坊：已卸载，状态文件 " .. STATE_FILE)
end

todo_list = { "setup" }

