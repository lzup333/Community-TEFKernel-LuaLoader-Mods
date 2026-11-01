-- 崩坏探针 main.lua  v1.1.0
-- 进世界即闪退（os.exit 强退游戏进程）。
-- 修复开关：读 LuaLoader 的 enables.txt —— 若启用列表里有 lua.qing.crashfix，则不崩，否则必崩。
-- 关掉修复模组 → 列表里没有它 → 恢复崩。权威、无残留。
mod.meta = { pkg_id = "lua.qing.crashprobe", version = "1.1.0", version_code = 110, api_version = 1 }

local P = mod.patch

local function clog(s)
  local ok,f = pcall(io.open, "/sdcard/Download/crashprobe.txt", "a")
  if ok and f then f:write("["..tostring(os.date("%H:%M:%S")).."] "..tostring(s).."\n"); f:flush(); f:close() end
end
clog("=== CrashProbe 1.1.0 LOADED ===")

local FIX_ID = "lua.qing.crashfix"

-- 推导 enables.txt 路径：private_dir = <mods_root>/private/<modid>
local function enables_path()
  local pd = tostring(mod.private_dir or "")
  if pd == "" then return nil end
  local root = pd:gsub("/private/[^/]*$", "")
  if root == pd then return nil end
  return root.."/enables.txt"
end

-- 修复模组是否启用
local function fix_enabled()
  local path = enables_path()
  if not path then clog("enables path nil"); return false end
  local ok, f = pcall(io.open, path, "r")
  if not (ok and f) then clog("enables read FAIL: "..path); return false end
  local content = f:read("*a"); f:close()
  clog("enables.txt => "..string.sub(content:gsub("\n","|"),1,300))
  for line in content:gmatch("[^\r\n]+") do
    local id = line:gsub("^%s+",""):gsub("%s+$","")
    if not id:match("^#") and id == FIX_ID then
      return true
    end
  end
  return false
end

local Main, F_wn
local g_last_wn = nil
local g_done = false

local function tick()
  if g_done then return end
  local wn = ""
  pcall(function()
    if not Main then Main = P.get_type("Terraria", "Main") end
    if Main and not F_wn then F_wn = P.get_field(Main, "worldName") end
    if F_wn then wn = P.get_field_value(F_wn, nil, "string") or "" end
  end)
  if type(wn) ~= "string" then wn = "" end
  if wn ~= "" and wn ~= g_last_wn then
    g_last_wn = wn
    clog("ENTER WORLD: "..wn)
    -- 判断修复模组是否启用
    if fix_enabled() then
      clog("FIX ENABLED -> stay alive")
      g_done = true   -- 本世界不再管（换了世界 worldName 变，会再判）
    else
      clog("FIX NOT ENABLED -> os.exit 闪退")
      g_done = true
      local okf, exitfn = pcall(function() return os.exit end)
      if okf and type(exitfn) == "function" then
        exitfn(0)
      else
        error("exit")
      end
    end
  end
  -- 离开世界（worldName 变空）→ 允许下个世界重新判断
  if wn == "" and g_last_wn ~= nil then
    g_last_wn = nil
    g_done = false
  end
end

function setup()
  if _G.g_crashprobe_setup then return end
  _G.g_crashprobe_setup = true
  clog("setup running")
  pcall(function()
    Main = P.get_type("Terraria", "Main")
    local m = P.get_method(Main, "Update", 1)
    if m then P.install_hook(m, { postfix = tick }); clog("hook OK") end
  end)
end

todo_list = { "setup" }
