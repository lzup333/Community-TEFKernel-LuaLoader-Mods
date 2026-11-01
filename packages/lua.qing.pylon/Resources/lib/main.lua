mod.meta = { pkg_id = "lua.qing.pylon", version = "1.0.0", version_code = 100, api_version = 1 }
local P = mod.patch

-- 日志：发布版关掉，w() 空转不写文件
local function w(s) end

-- 1) HasPylonOfType → false（解除"同种晶塔只能放一个"）
local function has_pylon_post(...)
    return false
end

-- 2) DoesPositionHaveEnoughNPCs → true（解除"附近必须有NPC"）
local function enough_npc_post(...)
    return true
end

local function try_hook(T, name, argc, fn)
    local M = P.get_method(T, name, argc)
    if not M then return end
    pcall(P.install_hook, M, { postfix = fn, override_result = true })
end

function setup()
    if _G.g_py_done then return end
    _G.g_py_done = true
    local T = P.get_type("Terraria.GameContent", "TeleportPylonsSystem")
    if not T then return end
    try_hook(T, "HasPylonOfType", 1, has_pylon_post)
    try_hook(T, "DoesPositionHaveEnoughNPCs", 2, enough_npc_post)
    -- 不 hook DoesPylonAcceptTeleportation（保留生物群系原规则）
end

todo_list = { "setup" }
