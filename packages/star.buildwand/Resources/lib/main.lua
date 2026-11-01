--[[=========================================================================
  建造魔杖 / Wand of Building
  ---------------------------------------------------------------
  泰拉瑞亚 手机端 建筑用魔杖（LuaLoader Mod）

  做一件事：铺任意可放置方块 / 平台。
    · 手持魔杖瞄准 → 沿角色朝向铺一排
    · 长度 1..200 可自定义，面板按钮 / 滑杆 / 10·20·50 快捷键
    · 面板列出背包与四个储蓄容器里的所有可铺材料，点选切换
    · 材料优先取魔杖内部存储，其次取背包；同一次铺设只用一种材料
    · 只在空位放置，不覆盖、不破坏任何已有方块 / 墙 / 家具
    · 半透明实时预览，跟手
    · 联机：客户端请求 → 服务端校验并铺 → 服务端广播图格
  不做：墙、房屋模板、复制粘贴、撤销、形状变换、模式切换。

  运行环境：LuaLoader >= 2.1.0-dev（需要 mod.item / mod.recipe / mod.net）
  =========================================================================]]

local P = mod.patch

--══════════════════════════════════════════════════════════════════════════
-- 配置
--══════════════════════════════════════════════════════════════════════════
local CFG = {
    WAND_NAME = "build_wand",

    -- 物品身份标记：注册时写进 WAND_ITEM.defaults.value（Terraria.Item 的真实 int 字段）。
    -- 为什么用魔法数字而不是名字/注册 id：本机 Lang.GetItemNameValue 是坏的，显示名认不出；
    -- 注册期拿到的 runtime id 也可能恒为 -1。value 是物品实例上一定读得到的整数，最可靠。
    -- 副作用：这把魔杖卖出价 987654 铜币（约 98 金），属免费工具，无所谓。
    WAND_MARK_VALUE = 987654,

    -- 10/20/50 只作为快捷档保留，真正生效的是 S.len（1..200）
    LENGTHS     = { 10, 20, 50 },
    DEFAULT_LEN = 10,
    LEN_MIN     = 1,
    LEN_MAX     = 200,
    -- 固定行高 + 自适应分页（旧版按 CAND_PAGE=6 固定个数分页，面板高度随内容浮动，
    -- 内容一多窗口就长到屏幕外；而屏幕外的按钮永远点不到——mouse_in() 要求窗口矩形命中，
    -- g_input_owner 只由窗口矩形决定。所以改成「行高固定 + 按屏幕剩余高度算行数」。）
    ROW_H         = 44,             -- 每个候选行的基准高度（实际 44*gs）
    CAND_COLS     = 2,              -- 候选材料每行 2 列
    CAND_ROWS_MAX = 6,              -- 一页最多 6 行（竖屏也放得下的上限）
    CAND_ROWS_MIN = 3,              -- 一页至少 3 行（v2.1.0 分页后不用再留 2 行的余地）
    BTN_H         = 36,             -- 行内按钮的基准高度（实际 36*gs）

    -- v2.1.0：整个面板拆成 3 页（1 选料 / 2 长度 / 3 操作）。
    -- 用户实测 2400x1080（gs=1.5）旧版面板一屏放不下，底部「装填/取出/放置」和滑条被切在屏幕外；
    -- 分页后每页各自排版、各自核对高度，任何一页都完整装进屏幕，「放置」永远可见可点。
    PAGE_COUNT = 3,

    STORE_MAX    = 999,             -- 魔杖内部每种材料的存储上限
    BUILD_DIST_X = 96,              -- 服务端允许的最远横向距离（格）
    BUILD_DIST_Y = 40,              -- 服务端允许的最远纵向距离（格）
    MIN_INTERVAL = 0.04,            -- 服务端两次请求的最小间隔（秒）

    -- 面板宽度：420（横向摆得下「[-10][-1][长度 N][+1][+10]」五个按钮 + 同排翻页控件）。
    -- 屏幕更窄时缩到 screenW - 24gs，但绝不低于 PANEL_W_MIN=300（再窄按钮文字就放不下）。
    -- 候选名称放不下就用 fit_text 截断加「…」——完整名称始终显示在首行「当前」里。
    PANEL_W     = 420,
    PANEL_W_MIN = 300,
    PANEL_EDGE  = 24,               -- 面板左右各留的屏幕边距（实际 24*gs）

    PREVIEW_FILL = { 120, 220, 180, 110 },   -- 预览可铺部分
    PREVIEW_MISS = { 255, 130, 130, 55 },    -- 预览材料不足部分

    STORE_FILE = "build_wand_store.txt",
    DEBUG = false,
}

-- 内核把 Lua 字符串写进日志时要走 UTF-16 -> UTF-8 转换，实测会失败并整条丢弃。
-- 这里把 mod.info/warn/error 等包一层，非 ASCII 字节统一替换成 '?'，
-- 保证任何一行日志都能真正落到日志文件里。
do
    local function clean_ascii(v)
        local s = tostring(v)
        local bytes = { s:byte(1, -1) }
        local out = {}
        for i = 1, #bytes do
            local b = bytes[i]
            out[i] = (b >= 32 and b <= 126) and string.char(b) or "?"
        end
        return table.concat(out)
    end
    local wrapped = { "info", "warn", "error", "debug", "trace", "fatal" }
    for _, key in ipairs(wrapped) do
        local orig = mod[key]
        if type(orig) == "function" then
            mod[key] = function(...)
                local n = select("#", ...)
                local args = { ... }
                for i = 1, n do args[i] = clean_ascii(args[i]) end
                return orig(table.unpack(args, 1, n))
            end
        end
    end
end

-- 主背包共 59 格（0..58）：用户明确要求全扫，不再只扫前 50 格。
local INV_SCAN_MAX = 59

local function inv_scan_end(arr)
    -- arr 是加载器 inventory 数组的 lightuserdata 句柄：Lua 5.4 对它取长度会抛
    -- "attempt to get length of a userdata value"（加载器没注册 __len），必须走 P.array_length。
    local ok, n = pcall(P.array_length, arr)
    if not ok or type(n) ~= "number" or n < 1 then return 0 end
    if n > INV_SCAN_MAX then n = INV_SCAN_MAX end
    return n - 1
end

--══════════════════════════════════════════════════════════════════════════
-- 反射缓存 / 运行时状态
--══════════════════════════════════════════════════════════════════════════
local C = {
    bound   = false,
    tile_of = {},                -- [itemType] = { tile=, style= }
    name_cache = {},             -- [itemType] = 显示名（成功/失败都缓存）
    name_broken = false,         -- 只针对 Lang.GetItemNameValue：失败后永久停调第 3 备选
    -- v2.1.0 名字优先读 Item.Name（字段/属性），Lang 只是第 3 备选（详见 item_name）
    f_item_name    = nil,        -- Terraria.Item.Name 字段（实例字段，.NET string）
    m_item_name_get = nil,       -- Terraria.Item.get_Name 访问器（1.4 里 Name 常是属性）
    name_prop_done = false,      -- Name 属性探测只做一次
    name_via       = "编号",     -- 最近一次名字来源："字段" / "Lang" / "编号"（自检行显示）
    name_fixed     = {},         -- [itemType] = true：名字已确定，不再重试
    name_retry     = {},         -- [itemType] = 数字兜底后允许带活实例重试的次数（≤1）
}

local S = {
    len          = CFG.DEFAULT_LEN, -- 当前铺设长度（1..200）
    sel_type     = nil,           -- 当前选中的材料物品类型
    cand_page    = 0,             -- 候选材料当前页（0 起）
    page         = 1,             -- 面板当前页 1..CFG.PAGE_COUNT（随存档落盘）
    wand_id      = -1,
    store        = {},            -- [itemType] = count（按玩家分开）
    store_meta   = {},            -- [itemType] = { tile=, style= }（记住的图格样式）
    store_key    = nil,
    store_dirty  = false,
    save_tick    = 0,             -- 上次落盘时间（os.clock），用来给滑杆拖动节流
    placed_mode  = nil,           -- 上次摆位的模式："ok" / "fail"，模式变了就重摆一次
    recipe_done  = false,
    recipe_inner = false,
    last_req     = {},            -- [playerIndex] = 时间，服务端限流
    debug_line   = "",
    bind_fail    = 0,             -- 反射绑定连续失败帧数（每 60 帧报一次）
    logged       = false,         -- on_gui 首次绑定成功后的自检日志只打一次
    side_down    = false,         -- 侧边常驻按钮：上一帧鼠标是否按下（边沿检测）
    panel_rect   = nil,           -- 面板屏幕矩形 {x,y,w,h}，on_gui 每帧刷新，use 里用来防误铺
    panel_visible = false,        -- 面板窗口本帧是否真的可见（false 时 pointer_in_panel 一律不拦）
    pt_logged    = false,         -- PlaceTile 重载/缺失日志只打一次
    pt_err_logged = false,        -- PlaceTile 调用抛错日志只打一次
    ui_clamped   = false,         -- 窗口位置越界是否已确认纠正（get_pos 真回到范围内才置位）
    clamp_tries  = 0,             -- 越界纠正尝试帧数，到 120 帧就放弃（别再无限重试）
    clamp_logged = false,         -- 越界 warn 只打一次
    setup_done   = false,         -- setup() 幂等保护：只注册一次物品
    hook_installed = false,       -- 配方钩子是否已成功安装
    frame_no     = 0,             -- on_gui 帧计数（背包扫描缓存键）
    inv_cache    = nil,           -- { frame=, who=, data= } 单帧背包扫描缓存（键含玩家索引）
    wand_cache   = nil,           -- { frame=, who=, src=, diag= } 单帧手持/背包找杖缓存
    wand_src     = nil,           -- "hand" / "inv" / nil（最近一次 find_wand 的结果）
    wand_diag    = nil,           -- { ht=, hv=, id=, hits=, scanned= } 门控诊断现场
    scan_inv_slots  = 0,          -- 本帧扫描到的主背包格数（自检行用）
    scan_bank_slots = 0,          -- 本帧扫描到的四个容器总格数（自检行用）
    scan_bank_count = 0,          -- 本帧真正读到的容器数
    container_warned = {},        -- [容器名] = true，容器读取失败只警告一次

    -- ── 面板内诊断（不依赖日志，自检行直接显示）─────────────────────────
    use_seen    = 0,              -- mod.item.use 被内核调用过几次（只证明点击链路通）
    reg_info    = "?",            -- setup 记录：runtime_id(name)(注册返回值)
    place_info  = "-",            -- 最近一次 place_one/request_place 的结果（≤60 字符）
    place_count = 0,              -- 成功落地的格数累计
    fail_count  = 0,              -- 落地返回 false/异常的格数累计
    overflow    = 0,              -- 本帧布局越界次数（正常应为 0）
    panel_rows  = 0,              -- 本帧每页候选行数（调试用）

    -- 瞄准格（resolve_aim 每帧刷新）：自检行的「瞄准格=(x,y) 来源=」
    aim_x       = nil,            -- 当前瞄准的图格 x
    aim_y       = nil,            -- 当前瞄准的图格 y
    aim_src     = nil,            -- "target"（游戏 tileTarget）/ "mouse"（鼠标反算）/
                                  -- "player"（玩家脚下兜底）/ "oob"（全失败，用 0,0）
}

-- 诊断串统一在这里截断：面板只有两行自检空间，长串必须在写入时就限长。
local function set_place_info(s)
    s = tostring(s)
    if #s > 60 then s = s:sub(1, 57) .. "..." end
    S.place_info = s
end

--══════════════════════════════════════════════════════════════════════════
-- 反射小工具
--══════════════════════════════════════════════════════════════════════════
-- 读整数字段：先量真实字节宽度（get_field_raw 省略 size 时内核按字段真实类型给长度），
-- 再按该宽度解包。原因：Android/IL2CPP 路径下 get_field_value 是"在字段地址按请求宽度读"，
-- 宽度给大了会吃掉相邻字段字节（Item.createTile/placeStyle/type/stack 都是 short，
-- 按 int32 读会变成天文数字），而且不报错、不返回 nil，属于静默错误。
local function gf_int(f, inst)
    if not f then return 0 end
    local ok, raw = pcall(P.get_field_raw, f, inst)
    if ok and type(raw) == "string" and #raw >= 1 and #raw <= 8 then
        local pok, v = pcall(string.unpack, "<i" .. #raw, raw)
        if pok and type(v) == "number" then return v end
    end
    local ok2, v2 = pcall(P.get_field_value, f, inst)
    if ok2 and type(v2) == "number" then return v2 end
    local ok3, v3 = pcall(P.get_field_value, f, inst, "int32")
    if ok3 and type(v3) == "number" then return v3 end
    return 0
end

local function gf_bool(f, inst)
    if not f then return false end
    local ok, v = pcall(P.get_field_value, f, inst, "bool")
    if ok then return v == true or v == 1 end
    return false
end

-- 写整数字段：同样按真实宽度打包，避免写 4 字节把相邻字段踩坏。
local function sf_int(f, inst, v)
    if not f then return false end
    local ok, raw = pcall(P.get_field_raw, f, inst)
    local n = 4
    if ok and type(raw) == "string" and #raw >= 1 and #raw <= 8 then n = #raw end
    local pok, packed = pcall(string.pack, "<i" .. n, math.floor(v))
    if pok then
        local wok = pcall(P.set_field_raw, f, inst, packed)
        if wok then return true end
    end
    return pcall(P.set_field_value, f, inst, v, "int32")
end

local function try_type(ns, cls)
    local ok, t = pcall(P.get_type, ns, cls)
    if ok and t and P.is_valid(t) then return t end
    return nil
end

local function try_field(t, name)
    if not t then return nil end
    local ok, f = pcall(P.get_field, t, name)
    if ok and f and P.is_valid(f) then return f end
    return nil
end

local function try_method(t, name, argc)
    if not t then return nil end
    local ok, m = pcall(P.get_method, t, name, argc)
    if ok and m and P.is_valid(m) then return m end
    return nil
end

--══════════════════════════════════════════════════════════════════════════
-- 反射绑定
--══════════════════════════════════════════════════════════════════════════
-- 玩家四个储蓄容器的官方字段名。仓库里没有 player.h（已核对，见交付报告），
-- 运行期按字段名探测：1 号容器兼容旧命名 bank1，其余固定 bank2..bank4。
-- 字段不存在就跳过，只提示一次；绝不在每帧重复报错。
local CONTAINER_DEFS = {
    { "bank", "bank1" },
    { "bank2" },
    { "bank3" },
    { "bank4" },
}

local function bind_all()
    if C.bound then return true end

    C.MainT    = try_type("Terraria", "Main")
    C.PlayerT  = try_type("Terraria", "Player")
    C.ItemT    = try_type("Terraria", "Item")
    C.WorldGen = try_type("Terraria", "WorldGen")
    if not (C.MainT and C.PlayerT and C.ItemT and C.WorldGen) then
        if not C.bind_err_logged then
            C.bind_err_logged = true
            mod.error("[建筑魔杖] 取不到 Terraria.Main/Player/Item/WorldGen，无法运行")
        end
        return false
    end

    -- Main
    C.f_myPlayer       = try_field(C.MainT, "myPlayer")
    C.f_mouseX         = try_field(C.MainT, "mouseX")
    C.f_mouseY         = try_field(C.MainT, "mouseY")
    C.f_screenW        = try_field(C.MainT, "screenWidth")
    C.f_screenH        = try_field(C.MainT, "screenHeight")
    C.f_gameMenu       = try_field(C.MainT, "gameMenu")
    -- 不再绑定/改写 Main 的「鼠标在 GUI 上」标志位：Terraria 在 ItemCheck 里见到它为真
    -- 会直接跳过一次物品使用，每帧改写会把真实点击吞掉（"点了没反应"）。
    -- 面板/按钮吞点击改由 pointer_in_panel() / pointer_on_side_button() 负责。
    C.f_mouseLeft      = try_field(C.MainT, "mouseLeft")
    C.f_playerArr      = try_field(C.MainT, "player")
    C.f_screenPos      = try_field(C.MainT, "screenPosition")
    C.f_zoom           = try_field(C.MainT, "GameZoomTarget")
    C.f_mouseWorld     = try_field(C.MainT, "MouseWorld")   -- 游戏每帧算好的鼠标世界坐标（Vector2）
    C.f_maxTX          = try_field(C.MainT, "maxTilesX")    -- 世界宽（格），只用于校验/夹取
    C.f_maxTY          = try_field(C.MainT, "maxTilesY")    -- 世界高（格）

    -- Player
    C.f_inventory = try_field(C.PlayerT, "inventory")
    C.f_selected  = try_field(C.PlayerT, "selectedItem")
    C.f_direction = try_field(C.PlayerT, "direction")
    C.f_position  = try_field(C.PlayerT, "position")
    C.f_width     = try_field(C.PlayerT, "width")       -- 玩家碰撞箱宽（px），兜底算脚下用
    C.f_height    = try_field(C.PlayerT, "height")      -- 玩家碰撞箱高（px）
    C.f_whoAmI    = try_field(C.PlayerT, "whoAmI")
    C.f_name      = try_field(C.PlayerT, "name")
    C.f_tileTX    = try_field(C.PlayerT, "tileTargetX")
    C.f_tileTY    = try_field(C.PlayerT, "tileTargetY")

    -- 四个储蓄容器：bank=猪猪储蓄罐、bank2=保险箱、bank3=护卫熔炉、bank4=虚空保险库
    C.f_banks = {}
    for _, def in ipairs(CONTAINER_DEFS) do
        local f, used = nil, nil
        for _, nm in ipairs(def) do
            f = try_field(C.PlayerT, nm)
            if f then used = nm; break end
        end
        if f then
            C.f_banks[#C.f_banks + 1] = { field = f, name = used }
        else
            mod.warn(string.format("[BW] Player.%s not found, container skipped", def[1]))
        end
    end
    if #C.f_banks == 0 then
        mod.warn("[BW] no bank containers bound, only inventory will be scanned")
    end

    -- Item
    C.f_type       = try_field(C.ItemT, "type")
    C.f_value      = try_field(C.ItemT, "value")   -- 身份标记用（见 CFG.WAND_MARK_VALUE）
    C.f_stack      = try_field(C.ItemT, "stack")
    C.f_createTile = try_field(C.ItemT, "createTile")
    C.f_placeStyle = try_field(C.ItemT, "placeStyle")
    -- v2.1.0 名字来源①：Item.Name 实例字段（get_field_value(...,"string") 走托管字符串直读）
    C.f_item_name = try_field(C.ItemT, "Name")

    C.m_setDefaults = try_method(C.ItemT, "SetDefaults", 1)
            or try_method(C.ItemT, "SetDefaults", 2)

    -- 物品显示名
    local LangT = try_type("Terraria", "Lang")
    C.m_item_name = try_method(LangT, "GetItemNameValue", 1)

    -- WorldGen.PlaceTile（版本间参数个数不同，逐个尝试）
    C.m_place_tile, C.place_argc = nil, 0
    for _, n in ipairs({ 7, 6, 8, 5 }) do
        local m = try_method(C.WorldGen, "PlaceTile", n)
        if m then
            C.m_place_tile, C.place_argc = m, n
            break
        end
    end

    -- TileID.Sets.Platforms（bool[]）：判断某个图格类型是不是平台
    local TileID = try_type("Terraria.ID", "TileID")
    if TileID then
        local ok, Sets = pcall(P.get_inner_type, TileID, "Sets")
        if ok and Sets and P.is_valid(Sets) then
            local f = try_field(Sets, "Platforms")
            if f then
                local ok2, arr = pcall(P.get_field_value, f, nil, "object")
                if ok2 and arr then
                    -- 这是静态字段，句柄要留住整局；retain 拿一份不会被回收的引用
                    local ok3, own = pcall(P.retain, arr, false)
                    C.f_platforms = (ok3 and own) or arr
                end
            end
        end
    end
    if not C.f_platforms then
        mod.warn("[建筑魔杖] 取不到 TileID.Sets.Platforms，平台识别不可用")
    end

    C.bound = true
    if CFG.DEBUG then
        mod.info(string.format("[建筑魔杖] 绑定完成：PlaceTile 参数=%d，SetDefaults=%s",
                C.place_argc, tostring(C.m_setDefaults ~= nil)))
    end
    return true
end

local function bind_lazy()
    if not C.bound and not bind_all() then return false end
    if (S.wand_id or -1) < 0 then
        local ok, id = pcall(mod.item.runtime_id, CFG.WAND_NAME)
        if ok and type(id) == "number" and id >= 0 then S.wand_id = id end
    end
    -- 关键：**不**以 wand_id >= 0 作为绑定成功的条件。
    -- mod.item.register 在注册阶段 runtime_id 恒为 -1（api_item.cpp:502 先置 -1、成功后回填），
    -- 运行时 runtime_id() 也未必拿得到非负值。若在这里 return false，use 回调会每帧静默
    -- 早退 —— 症状正是"点了完全没反应"。魔杖身份由 is_wand_stack() 的
    -- type / Item.value 标记 / 显示名四级兜底判定（见文件下方）。
    return true
end

--══════════════════════════════════════════════════════════════════════════
-- 基础取数
--══════════════════════════════════════════════════════════════════════════
local function net_mode()
    local ok, m = pcall(mod.net.mode)
    if ok and type(m) == "number" then return m end
    return 0
end

local function is_authority()          -- 单机 / 专用服 / 开房
    local m = net_mode()
    return m == 0 or m == 2 or m == 3
end

local function player_by_index(idx)
    if not C.f_playerArr then return nil end
    local ok, arr = pcall(P.get_field_value, C.f_playerArr, nil, "object")
    if not ok or not arr then return nil end
    local ok2, pl = pcall(P.array_at, arr, idx)
    if ok2 and pl and P.is_valid(pl) then return pl end
    return nil
end

local function local_player()
    return player_by_index(gf_int(C.f_myPlayer, nil))
end

local function inventory_array(player)
    if not C.f_inventory or not player then return nil end
    local ok, arr = pcall(P.get_field_value, C.f_inventory, player, "object")
    if ok then return arr end
    return nil
end

local function inv_item(arr, i)
    if not arr then return nil end
    local ok, it = pcall(P.array_at, arr, i)
    if ok and it and P.is_valid(it) then return it end
    return nil
end

local function item_type_of(it)  return gf_int(C.f_type, it)  end
local function item_stack_of(it) return gf_int(C.f_stack, it) end

-- 物品显示名（v2.1.0）：按类型缓存，成功/失败都缓存。
-- 这台机器上 Lang.GetItemNameValue 是坏的（内核日志 patch_handle is null 刷屏），
-- 所以名字按下面的优先级取，任何一条成功就缓存并停用后面的：
--   ① Item.Name —— 先按**实例字段**读：patch.get_field(Item, "Name") 拿字段句柄，再用活物品实例
--      （背包/容器里正在用的那个）调 get_field_value(field, inst, "string")。
--      加载器里这条路径是确定的：api_patch_core.cpp:187-189 识别第 3 参 "string" 后走
--      push_managed_string(read_field_object(field, instance))，把 System.String 直接压成
--      Lua 字符串，不需要再调 string_value。
--      1.4 的 Item.Name 也可能被编译成 get_Name 属性：同一优先级里再探一次属性
--      （get_property → property_get_method → invoke(实例) → string_value(托管串句柄)）。
--   ② 新建 Terraria.Item 实例 → SetDefaults(type) → 读同一个 Name（字段/属性任一）。
--   ③ Lang.GetItemNameValue(type)；失败一次就 C.name_broken=true（只停这一条，不影响 ①②）。
--   ④ "物品#<type>"。
-- C.name_broken 只针对 ③，绝不因为 Lang 坏了就跳过 ①②。
local function name_plausible(v)
    if type(v) ~= "string" then return false end
    if v == "" or #v > 64 then return false end
    -- 未本地化时 Name 可能直接是 "ItemName.177" 这种键，不能当名字给人看
    if v:match("^ItemName%.") or v:match("^ItemTooltip%.") then return false end
    return true
end

-- 从指定 Item 实例读 Name：字段优先，属性兜底。成功返回名字，失败 nil。
local function name_of_instance(inst)
    if not inst then return nil end
    if C.f_item_name then
        local ok, v = pcall(P.get_field_value, C.f_item_name, inst, "string")
        if ok and name_plausible(v) then return v end
    end
    if C.m_item_name_get then
        local ok, h = pcall(P.invoke, C.m_item_name_get, inst)
        if ok and h ~= nil and h ~= false then
            local s = h
            if type(h) ~= "string" and type(P.string_value) == "function" then
                local ok2, v2 = pcall(P.string_value, h)
                if ok2 then s = v2 end
            end
            if name_plausible(s) then return s end
        end
    end
    return nil
end

-- 探测 Item.Name 属性访问器：只探一次；没有 get_property 的旧加载器直接跳过。
local function bind_item_name_prop()
    if C.name_prop_done then return end
    C.name_prop_done = true
    if not C.ItemT then return end
    if type(P.get_property) ~= "function" or type(P.property_get_method) ~= "function" then return end
    local okp, prop = pcall(P.get_property, C.ItemT, "Name")
    if not okp or not prop then return end
    local vok, vvalid = pcall(P.is_valid, prop)
    if not vok or not vvalid then return end
    local okm, m = pcall(P.property_get_method, prop)
    if okm and m then
        local mok, mvalid = pcall(P.is_valid, m)
        if mok and mvalid then C.m_item_name_get = m end
    end
    -- 属性句柄不 free：部分平台上 property_free 是空宏，交给进程生命周期更安全
end

-- ② 新建 Item + SetDefaults(type) 再读 Name（拿不到活实例时的兜底）
local function name_from_defaults(item_type)
    if not C.m_setDefaults then return nil end
    local ok, inst = pcall(P.new_instance, C.ItemT)
    if not ok or not inst then return nil end
    if C.ItemVariantT == nil then
        local gok, vt = pcall(P.get_type, "Terraria", "ItemVariant")
        local vok, vvalid = false, false
        if gok and vt then vok, vvalid = pcall(P.is_valid, vt) end
        C.ItemVariantT = (vok and vvalid) and vt or false
    end
    local variant = nil
    if C.ItemVariantT then
        local nok, nv = pcall(P.new_instance, C.ItemVariantT)
        if nok and nv then variant = nv end
    end
    local iok = pcall(P.invoke, C.m_setDefaults, inst, item_type)
    if not iok and variant then
        iok = pcall(P.invoke, C.m_setDefaults, inst, item_type, variant)
    end
    local name = nil
    if iok then name = name_of_instance(inst) end
    if variant then pcall(P.free, variant) end
    pcall(P.free, inst)
    return name
end

-- live_item：调用点手上正拿着的活物品实例句柄（本帧 array_at 出来的），可为 nil
local function item_name(item_type, live_item)
    local t = item_type or 0
    local hit = C.name_cache[t]
    if hit then
        -- 数字兜底不是最终结论：以后真拿到活实例时可以再试一次（最多一次）
        if C.name_fixed[t] or not live_item or (C.name_retry[t] or 0) >= 1 then return hit end
    end
    local name, via = nil, nil
    if t > 0 then
        bind_item_name_prop()
        name = name_of_instance(live_item)
        if name then via = "字段" end
        if not name then
            name = name_from_defaults(t)
            if name then via = "字段" end
        end
        if not name and not C.name_broken and C.m_item_name then
            local ok, v = pcall(P.invoke, C.m_item_name, t)
            if ok and name_plausible(v) then
                name, via = v, "Lang"
            else
                C.name_broken = true
                mod.warn("[BW] Lang.GetItemNameValue unavailable; names fall back to item#type (no more calls)")
            end
        end
    end
    if not name then
        name, via = string.format("物品#%d", t), "编号"
        -- 只有「拿着活实例试过」才算用掉那次重试；没有实例时的失败不给类型判死刑，
        -- 以后真拿到背包里的实例还能再试一次（见上面 hit 分支的 name_retry 判断）。
        if t > 0 and live_item then C.name_retry[t] = (C.name_retry[t] or 0) + 1 end
    else
        C.name_fixed[t] = true
    end
    C.name_cache[t] = name
    C.name_via = via
    return name
end

-- 直接从"活着的物品实例"读 createTile/placeStyle（背包里的物品本来就有这两个字段，
-- 不需要 new_instance + SetDefaults，也就绕开了 SetDefaults 重载参数个数不匹配的坑）
local function tile_style_from_item(it)
    return gf_int(C.f_createTile, it), gf_int(C.f_placeStyle, it)
end

-- 物品 id ->（图格类型, 放置样式），带缓存
local function tile_and_style(item_type)
    local hit = C.tile_of[item_type]
    if hit then
        if hit.tile and hit.tile > 0 then return hit.tile, hit.style end
        if hit.neg then return 0, 0 end
    end

    local tile, style = 0, 0
    if C.m_setDefaults then
        local ok, inst = pcall(P.new_instance, C.ItemT)
        if ok and inst then
            -- 2 参 SetDefaults 重载需要 ItemVariant 做第二参；类型取不到就跳过 variant 分支
            if C.ItemVariantT == nil then
                local gok, vt = pcall(P.get_type, "Terraria", "ItemVariant")
                local vok2, vvalid = false, false
                if gok and vt then vok2, vvalid = pcall(P.is_valid, vt) end
                C.ItemVariantT = (vok2 and vvalid) and vt or false
            end
            local variant = nil
            if C.ItemVariantT then
                local nok, nv = pcall(P.new_instance, C.ItemVariantT)
                if nok and nv then variant = nv end
            end
            local iok
            if C.setdefaults_argc and C.setdefaults_argc >= 2 and variant then
                iok = pcall(P.invoke, C.m_setDefaults, inst, item_type, variant)
            else
                iok = pcall(P.invoke, C.m_setDefaults, inst, item_type)
                if not iok and variant then
                    iok = pcall(P.invoke, C.m_setDefaults, inst, item_type, variant)
                end
            end
            if iok then
                tile  = gf_int(C.f_createTile, inst)
                style = gf_int(C.f_placeStyle, inst)
            end
            if variant then pcall(P.free, variant) end
            pcall(P.free, inst)
        end
    end
    if tile > 0 then
        C.tile_of[item_type] = { tile = tile, style = style }
    else
        C.tile_of[item_type] = { tile = 0, style = 0, neg = true }   -- 负缓存：不可放置物品不再反复实例化
    end
    return tile, style
end

-- 图格类型是否属于"平台"
local function is_platform_tile(tile)
    if not tile or tile <= 0 then return false end
    if not C.f_platforms then
        if not C.plat_nil_logged then
            C.plat_nil_logged = true
            mod.warn("[BW] TileID.Sets.Platforms not bound, platform table check disabled")
        end
        return false
    end
    local ok, v = pcall(P.array_at, C.f_platforms, tile, "bool")
    if not ok then return false end
    return v == true or v == 1
end

-- 读一个储蓄容器数组：字段取不到 / 数组为 nil / array_length 抛错都只 warn 一次。
local function bank_container(player, b)
    if not player or not b or not b.field then return nil, 0 end
    local ok, arr = pcall(P.get_field_value, b.field, player, "object")
    if not ok or not arr then
        if not S.container_warned[b.name] then
            S.container_warned[b.name] = true
            mod.warn(string.format("[BW] Player.%s nil array, container skipped", b.name))
        end
        return nil, 0
    end
    local lok, n = pcall(P.array_length, arr)
    if not lok or type(n) ~= "number" then
        if not S.container_warned[b.name .. "_len"] then
            S.container_warned[b.name .. "_len"] = true
            mod.warn(string.format("[BW] Player.%s array_length failed, container skipped", b.name))
        end
        return nil, 0
    end
    if n <= 0 then return arr, 0 end   -- 空容器是正常状态，不算读取失败
    if n > 100 then n = 100 end       -- 防御：异常长度不要把一帧拖死
    return arr, n
end

local function clamp_len(v)
    v = math.floor(tonumber(v) or CFG.DEFAULT_LEN)
    if v < CFG.LEN_MIN then v = CFG.LEN_MIN end
    if v > CFG.LEN_MAX then v = CFG.LEN_MAX end
    return v
end

local function clamp_page(v)
    local p = math.floor(tonumber(v) or 1)
    if p < 1 then p = 1 end
    if p > CFG.PAGE_COUNT then p = CFG.PAGE_COUNT end
    return p
end

local function set_len(v)
    v = clamp_len(v)
    if v ~= S.len then
        S.len = v
        S.store_dirty = true          -- 由 on_gui 底部节流落盘
    end
end

-- 长按 / 侧边按钮沿用旧习惯：只在 10 → 20 → 50 三个快捷档之间循环
local function cycle_short_len()
    local cur = clamp_len(S.len)
    local nxt = CFG.LENGTHS[1]
    for i = 1, #CFG.LENGTHS do
        if cur < CFG.LENGTHS[i] then nxt = CFG.LENGTHS[i]; break end
    end
    set_len(nxt)
end

local function ui_scale()
    local w = gf_int(C.f_screenW, nil)
    local h = gf_int(C.f_screenH, nil)
    if w <= 0 or h <= 0 then return 1.0 end
    local s = math.min(w, h) / 720.0
    if s < 1.0 then s = 1.0 end
    if s > 2.5 then s = 2.5 end
    return s
end

--══════════════════════════════════════════════════════════════════════════
-- 面板布局：固定行高 + 自适应分页
--══════════════════════════════════════════════════════════════════════════
-- 内核窗口几何（gui_types.inc:521-537、gui_window.inc:320）：
--   标题栏 32*gs、内边距 12*gs；窗口总高 = 标题 + 12 + 内容高 + 12
--   内容区原点 = (x + 12*gs, y + 32*gs + 6*gs)
local WIN_TITLE_H = 32
local WIN_PAD     = 12

-- g.* 的文字宽度规则（gui_types.inc:689-698）：ASCII 10px、多字节 20px，再乘 gs/scale。
-- 这里复刻一份，用来在画之前把文字截断到按钮/行宽内——否则 draw_string 不会裁剪，
-- 长名字会直接压到右边那一列上。
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local function char_px(ch, gs, scale)
    return ((#ch == 1) and 10 or 20) * gs * (scale or 1)
end

local function text_px(s, gs, scale)
    local w = 0
    for ch in s:gmatch(UTF8_CHAR) do w = w + char_px(ch, gs, scale) end
    return math.floor(w)
end

-- 截断到 maxpx 以内，末尾加「…」；本身够短就原样返回。
local function fit_text(s, maxpx, gs, scale)
    if maxpx <= 0 then return "" end
    if text_px(s, gs, scale) <= maxpx then return s end
    local ell = char_px("…", gs, scale)
    local w, out, parts = 0, 0, {}
    for ch in s:gmatch(UTF8_CHAR) do
        local cw = char_px(ch, gs, scale)
        if w + cw + ell > maxpx then break end
        parts[#parts + 1] = ch
        w = w + cw
        out = out + 1
    end
    if out == 0 then return "…" end
    return table.concat(parts) .. "…"
end

-- 按像素宽度折行，最多 maxlines 行；超出时最后一行截断并保留「…」。
local function wrap_text(s, maxpx, gs, scale, maxlines)
    local lines, cur, w = {}, {}, 0
    for ch in s:gmatch(UTF8_CHAR) do
        local cw = char_px(ch, gs, scale)
        if #cur > 0 and w + cw > maxpx then
            lines[#lines + 1] = table.concat(cur)
            cur, w = {}, 0
        end
        cur[#cur + 1] = ch
        w = w + cw
    end
    if #cur > 0 then lines[#lines + 1] = table.concat(cur) end
    if #lines == 0 then lines[1] = "" end
    if #lines > maxlines then
        local kept = {}
        for i = 1, maxlines do kept[i] = lines[i] end
        kept[maxlines] = fit_text(kept[maxlines] .. "…", maxpx, gs, scale)
        return kept
    end
    return lines
end

-- 三页各自的内容高度（px）。逐项与 on_gui 里的绘制顺序一一对应，算错就会误报「溢出」：
--   第 1 页「选料」：分页按钮行 + 「当前材料 + 材料翻页」行 + rows * ROW_H（候选网格）
--   第 2 页「长度」：分页按钮行 + 「当前 + 长度」行 + 五行微调 + 三格快捷档 + 滑条（三行同高）
--   第 3 页「操作」：分页按钮行 + 装填/取出/放置三个全宽行 + 分隔线 + diag 行自检 + 底部 4
-- 其中 tab_h = info_h = BTN_H + 6，自检行距 21（0.75 倍字号）。
local function page_content_h(page, rows, diag, gs)
    local btn_h  = math.floor(CFG.BTN_H * gs)
    local gap    = math.floor(6 * gs)
    local row_h  = math.floor(CFG.ROW_H * gs)
    local line_h = math.floor(21 * gs)
    local tab_h  = btn_h + gap
    local info_h = btn_h + gap
    if page == 1 then
        return tab_h + info_h + rows * row_h
    elseif page == 2 then
        return tab_h + info_h + 3 * (btn_h + gap)
    end
    return tab_h + 3 * (btn_h + gap) + gap + diag * line_h + math.floor(4 * gs)
end

local function world_zoom()
    if C.f_zoom then
        local ok, v = pcall(P.get_field_value, C.f_zoom, nil, "float")
        if ok and type(v) == "number" and v > 0.2 and v < 4.0 then return v end
    end
    return 1.0
end

-- 读 Vector2 字段 → (x, y) 两个 float。
-- 先用内核的 get_field_vec2（它认识 Vector2，最稳）；失败再按 8 字节 <ff 自己解。
-- 目的是让「屏幕坐标反算」这一级在 get_field_vec2 不可用时也能工作。
local function read_vec2(field, inst)
    if not field then return nil end
    local ok, vx, vy = pcall(P.get_field_vec2, field, inst)
    if ok and type(vx) == "number" and type(vy) == "number" then return vx, vy end
    local ok2, raw = pcall(P.get_field_raw, field, inst)
    if ok2 and type(raw) == "string" and #raw >= 8 then
        local ok3, x2, y2 = pcall(string.unpack, "<ff", raw)
        if ok3 and type(x2) == "number" and type(y2) == "number" then return x2, y2 end
    end
    return nil
end

-- 世界边界（格）。只用来校验和夹取：读数失败就按 1.4 大世界上限 8400x2400 兜底，
-- 这样「越界判断」永远不会因为绑定失败而把有效坐标误杀。
local function world_bounds()
    local maxx = gf_int(C.f_maxTX, nil)
    local maxy = gf_int(C.f_maxTY, nil)
    if type(maxx) ~= "number" or maxx <= 0 then maxx = 8400 end
    if type(maxy) ~= "number" or maxy <= 0 then maxy = 2400 end
    return maxx, maxy
end

-- 坐标是否落在世界内。NaN 自己不等于自己，顺手挡掉。
local function tile_ok(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then
        return false
    end
    local maxx, maxy = world_bounds()
    return x >= 0 and y >= 0 and x < maxx and y < maxy
end

-- 把坐标夹进世界范围（floor 后再夹），供「玩家兜底」保证一定有值。
local function clamp_tile(x, y)
    local maxx, maxy = world_bounds()
    if type(x) ~= "number" or x ~= x then x = 0 end
    if type(y) ~= "number" or y ~= y then y = 0 end
    x, y = math.floor(x), math.floor(y)
    if x < 0 then x = 0 elseif x >= maxx then x = maxx - 1 end
    if y < 0 then y = 0 elseif y >= maxy then y = maxy - 1 end
    return x, y
end

-- 记录本次用哪一级算出的瞄准格（S.aim_* 给面板自检行和预览共用）。
local function set_aim(x, y, src)
    S.aim_x, S.aim_y, S.aim_src = x, y, src
    return { ok = true, x = x, y = y, src = src }
end

-- 瞄准格解析：四级回退，**永远返回一个可用的格子，绝不返回 nil/false**。
--   1. player.tileTargetX/Y   —— 游戏自己算好的当前瞄准格，和缩放/UI 无关，最可信；
--   2. Main.MouseWorld 或 screenPosition + mouseX/mouseY / zoom —— 屏幕坐标反算；
--   3. player.position + width/height —— 玩家脚下那一格，再按朝向偏 2 格，不依赖鼠标；
--   4. (0,0) —— 连玩家位置都读不到，来源记 "oob"，request_place 会写 fallback=0,0。
-- 之前 v2.1.0 只有 1、2 两级且失败就 return，所以一旦 tileTarget 没值、
-- get_field_vec2(screenPosition) 又不给数，就会卡在 bad-aim，一次 PlaceTile 都走不到。
local function resolve_aim(player)
    player = player or local_player()

    -- 第 1 级：游戏瞄准格。两个都为 0 视为「没瞄准」（字段默认值），
    -- 否则世界原点 (0,0) 会被误当成有效目标。
    if C.f_tileTX and C.f_tileTY then
        local tx = gf_int(C.f_tileTX, player)
        local ty = gf_int(C.f_tileTY, player)
        if tile_ok(tx, ty) and not (tx == 0 and ty == 0) then
            return set_aim(tx, ty, "target")
        end
    end

    -- 第 2 级：鼠标反算。2a 优先用 Main.MouseWorld（游戏每帧更新，已含缩放/屏幕偏移）；
    -- 2b 没有就自己算：world = screenPosition + (mouseX, mouseY) / zoom。
    if C.f_mouseWorld then
        local wx, wy = read_vec2(C.f_mouseWorld, nil)
        if wx then
            local x, y = math.floor(wx / 16), math.floor(wy / 16)
            if tile_ok(x, y) then return set_aim(x, y, "mouse") end
        end
    end
    if C.f_screenPos and C.f_mouseX and C.f_mouseY then
        local sx, sy = read_vec2(C.f_screenPos, nil)
        if sx then
            local z = world_zoom()
            if z <= 0 then z = 1 end
            local mx, my = gf_int(C.f_mouseX, nil), gf_int(C.f_mouseY, nil)
            local x = math.floor((sx + mx / z) / 16)
            local y = math.floor((sy + my / z) / 16)
            if tile_ok(x, y) then return set_aim(x, y, "mouse") end
        end
    end

    -- 第 3 级：玩家脚下兜底。只依赖 position/width/height/direction，一定算得出；
    -- 朝向前方 2 格，避免正好落在自己站的格子上（那格通常放不了）。
    if player then
        local px, py = read_vec2(C.f_position, player)
        if px then
            local w = gf_int(C.f_width, player)
            local h = gf_int(C.f_height, player)
            if w <= 0 then w = 20 end          -- Terraria.Player.defaultWidth = 20
            if h <= 0 then h = 42 end          -- Terraria.Player.defaultHeight = 42
            local dir = gf_int(C.f_direction, player)
            if dir == 0 then dir = 1 end
            local x = math.floor((px + w / 2) / 16) + dir * 2
            local y = math.floor((py + h - 16) / 16)   -- 脚下一格（取碰撞箱底部往上 16px）
            x, y = clamp_tile(x, y)
            return set_aim(x, y, "player")
        end
    end

    -- 第 4 级：连玩家坐标都读不到。绝不返回 nil —— 给 (0,0)，来源 oob，
    -- request_place 会把这个兜底明确写进自检行，不会静默失败。
    return set_aim(0, 0, "oob")
end

--══════════════════════════════════════════════════════════════════════════
-- 侧边常驻按钮（绝对屏幕坐标）
--
-- 为什么不用 g.button_at 判断点击：加载器的 mouse_in() 只认「窗口矩形」，
--   gui_types.inc:644-649   if (!g_render_owner.empty() && g_render_owner!=g_input_owner) return false;
--   gui_hook.inc:216-227    g_input_owner 只由窗口矩形 / 文件夹图标决定
-- 所以画在窗口外的按钮永远拿不到 hover，点了也不会返回 true。
-- 这里改用 Main.mouseX / Main.mouseLeft 自己做边沿检测，位置随便放都能点。
--══════════════════════════════════════════════════════════════════════════
local SIDE_SIZE    = 48      -- 按钮边长（逻辑像素，实际乘 ui_scale）
local SIDE_RIGHT   = 60      -- 按钮左缘距屏幕右缘（逻辑像素）
local SIDE_TOP     = 0.45    -- 按钮上缘 = 屏幕高度 * 该比例

-- 返回绝对屏幕坐标 x, y, w, h；每帧现算、不缓存，折叠/旋转后不会留下过期区域
local function side_button_rect(gs)
    local sw = gf_int(C.f_screenW, nil)
    local sh = gf_int(C.f_screenH, nil)
    if sw <= 0 or sh <= 0 then return nil end
    local size = math.floor(SIDE_SIZE * gs)
    if size < 24 then size = 24 end
    local x = sw - math.floor(SIDE_RIGHT * gs)
    local y = math.floor(sh * SIDE_TOP)
    if x + size > sw then x = sw - size end
    if x < 0 then x = 0 end
    if y + size > sh then y = sh - size end
    if y < 0 then y = 0 end
    return x, y, size, size
end

-- 指针是否落在侧边按钮上（给 mod.item 的 use 回调做同帧拦截用）
local function pointer_on_side_button()
    local x, y, w, h = side_button_rect(ui_scale())
    if not x then return false end
    local mx, my = gf_int(C.f_mouseX, nil), gf_int(C.f_mouseY, nil)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- 指针是否落在面板上：use 回调里调不到 g.get_pos（那时没有「当前窗口」），
-- 所以用 on_gui 每帧缓存的 S.panel_rect。点面板按钮时别顺手铺一排平台。
-- 只在面板**当前可见**时拦截：窗口被折叠/隐藏后 rect 还留着旧值，
-- 再拿它拦就是"点了没反应"的元凶（竖屏上那一片能盖住右半屏）。
local function pointer_in_panel()
    local r = S.panel_rect
    if not r or not S.panel_visible then return false end
    -- 兜底：若窗口隐藏后 on_gui 不再回调，rect 会一直停在旧值；
    -- 超过 2 秒没刷新就当它过期（宁可不拦，也不要挡住一片屏幕）。
    local okt, now = pcall(os.time)
    if okt and type(now) == "number" and r.t and now - r.t > 2 then return false end
    local mx, my = gf_int(C.f_mouseX, nil), gf_int(C.f_mouseY, nil)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

--══════════════════════════════════════════════════════════════════════════
-- 背包 + 四个储蓄容器里的可铺材料
--══════════════════════════════════════════════════════════════════════════
-- 扫描一个数组：只要 createTile > 0 且 stack > 0 就是候选材料，不再要求必须是平台。
-- slots 里带 arr，扣料时才能从主背包或任意 bank 容器里扣。
local function scan_placeables(arr, first, last, out)
    for i = first, last do
        local it = inv_item(arr, i)
        if it then
            local t  = item_type_of(it)
            local st = item_stack_of(it)
            if t > 0 and st > 0 then
                local tile, style = tile_style_from_item(it)
                if tile <= 0 then tile, style = tile_and_style(t) end
                if tile > 0 then
                    C.tile_of[t] = { tile = tile, style = style }
                    local e = out[t]
                    if not e then
                        e = { count = 0, tile = tile, style = style, slots = {}, item = it }
                        out[t] = e
                    end
                    e.count = e.count + st
                    e.slots[#e.slots + 1] = { arr = arr, index = i, stack = st }
                end
            end
        end
    end
end

-- 返回 { [itemType] = { count=, tile=, style=, slots={ {arr=,index=,stack=} } } }
-- 函数名保留 collect_inventory_platforms（旧调用点/缓存约定不变），实际已覆盖所有可铺图格。
local function collect_inventory_platforms(player)
    local fn = S.frame_no or 0
    -- 服务端 on_net_place 会用不同玩家的 player 句柄调这里，而服务器不跑 on_gui，
    -- S.frame_no 恒为 0；只按帧号做键会导致缓存永不失效、B 玩家拿到 A 玩家的背包。
    local who = player and gf_int(C.f_whoAmI, player) or -1
    if S.inv_cache and S.inv_cache.frame == fn and S.inv_cache.who == who then
        return S.inv_cache.data
    end

    local out = {}
    local inv_slots = 0
    local arr = inventory_array(player)
    if arr then
        local last = inv_scan_end(arr)       -- 0..58，全部 59 格
        inv_slots = last + 1
        scan_placeables(arr, 0, last, out)
    end

    local bank_slots, bank_count = 0, 0
    for _, b in ipairs(C.f_banks or {}) do
        local barr, n = bank_container(player, b)
        if barr then
            bank_count = bank_count + 1
            bank_slots = bank_slots + n
            scan_placeables(barr, 0, n - 1, out)
        end
    end

    S.scan_inv_slots  = inv_slots
    S.scan_bank_slots = bank_slots
    S.scan_bank_count = bank_count
    S.inv_cache = { frame = fn, who = who, data = out }
    return out
end

-- 候选材料按数量从多到少排序（同数量按类型 id 稳定排序）
local function sorted_candidates(cands)
    local list = {}
    for t, e in pairs(cands) do
        list[#list + 1] = { type = t, count = e.count, tile = e.tile, style = e.style, entry = e }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.type < b.type
    end)
    return list
end

-- 默认选中：平台表判定为平台的候选里数量最多的；没有平台就取数量最多的候选。
local function choose_default(cands, list)
    if #list == 0 then return nil end
    for _, e in ipairs(list) do
        if is_platform_tile(e.tile) then return e.type end
    end
    return list[1].type
end

-- 保住上次保存的选择；类型已不在候选里才回退到默认规则
local function ensure_selection(cands, list)
    local sel = S.sel_type
    if sel and cands[sel] then return sel end
    local d = choose_default(cands, list)
    S.sel_type = d
    S.store_dirty = true
    return d
end

-- 候选视图：背包 + 四个储蓄容器，再合并魔杖内部存储。
-- 魔杖存储仍然优先，但面板要能看到并选中只存在魔杖里的材料。
local function candidate_view(player)
    local inv = collect_inventory_platforms(player)
    local view = {}
    for t, e in pairs(inv) do
        view[t] = { type = t, count = e.count, tile = e.tile, style = e.style,
                    entry = e, store_n = 0, inv_n = e.count }
    end
    for t, n in pairs(S.store or {}) do
        if n and n > 0 then
            local v = view[t]
            if not v then
                local tile, style = tile_and_style(t)
                if tile > 0 then
                    v = { type = t, count = 0, tile = tile, style = style,
                          entry = nil, store_n = 0, inv_n = 0 }
                    view[t] = v
                end
            end
            if v then
                v.count = v.count + n
                v.store_n = v.store_n + n
            end
        end
    end
    local list = sorted_candidates(view)
    ensure_selection(view, list)
    return view, list
end

local function consume_inventory(player, entry, amount)
    if not entry or amount <= 0 then return 0 end
    local arr = inventory_array(player)      -- 旧 entry 没有 arr 时的兜底
    local left = amount
    for _, slot in ipairs(entry.slots) do
        if left <= 0 then break end
        local it = inv_item(slot.arr or arr, slot.index)
        if it then
            local st = item_stack_of(it)
            if st > 0 then
                local take = math.min(st, left)
                local rest = st - take
                if rest <= 0 then
                    sf_int(C.f_type, it, 0)
                    sf_int(C.f_stack, it, 0)
                else
                    sf_int(C.f_stack, it, rest)
                end
                left = left - take
            end
        end
    end
    S.inv_cache = nil
    return amount - left
end

local function give_to_inventory(player, item_type, amount)
    local arr = inventory_array(player)
    if not arr then return 0 end
    local ok, len = pcall(P.array_length, arr)
    if not ok or type(len) ~= "number" then return 0 end

    local left, maxStack = amount, 999
    for i = 0, len - 1 do                      -- 先补同类堆
        if left <= 0 then break end
        local it = inv_item(arr, i)
        if it and item_type_of(it) == item_type then
            local st = item_stack_of(it)
            if st > 0 and st < maxStack then
                local add = math.min(maxStack - st, left)
                sf_int(C.f_stack, it, st + add)
                left = left - add
            end
        end
    end
    for i = 0, len - 1 do                      -- 再找空位
        if left <= 0 then break end
        local it = inv_item(arr, i)
        if it and item_type_of(it) == 0 then
            local add = math.min(maxStack, left)
            if C.m_setDefaults then pcall(P.invoke, C.m_setDefaults, it, item_type) end
            sf_int(C.f_type, it, item_type)
            sf_int(C.f_stack, it, add)
            left = left - add
        end
    end
    S.inv_cache = nil
    return amount - left
end

-- 服务端对账用：按图格类型统计/扣除玩家背包里的平台
local function count_by_tile(player, tile)
    local n = 0
    for _, e in pairs(collect_inventory_platforms(player)) do
        if e.tile == tile then n = n + e.count end
    end
    return n
end

local function consume_by_tile(player, tile, amount)
    local left, took = amount, 0
    for _, e in pairs(collect_inventory_platforms(player)) do
        if left <= 0 then break end
        if e.tile == tile then
            local got = consume_inventory(player, e, left)
            left = left - got
            took = took + got
        end
    end
    return took
end

--══════════════════════════════════════════════════════════════════════════
-- 魔杖内部存储（按玩家名分开，落盘到 private_dir）
--══════════════════════════════════════════════════════════════════════════
-- 存档格式：`@<长度>@<选中类型>@` + 旧的 `类型:数量:图格:样式,...`
-- 旧版没有 @ 头，deserialize 会自动按旧格式解析；新版多出的头旧版解析时会忽略。
local function serialize_store()
    local parts = {}
    for t, n in pairs(S.store) do
        if n and n > 0 then parts[#parts + 1] = string.format("%d:%d:%d:%d", t, n, (S.store_meta[t] and S.store_meta[t].tile) or 0, (S.store_meta[t] and S.store_meta[t].style) or 0) end
    end
    table.sort(parts)
    -- v2.1.0：当前页也写进同一行存档 → @len@sel@page@items
    -- 旧格式只有 @len@sel@items，读取端两种都认（见 deserialize_store）
    return string.format("@%d@%d@%d@%s", clamp_len(S.len), S.sel_type or 0,
                         clamp_page(S.page), table.concat(parts, ","))
end

local function deserialize_store(str)
    local out = {}
    local meta = {}
    local len, sel, page = CFG.DEFAULT_LEN, nil, 1
    if type(str) ~= "string" then return out, meta, len, sel, page end
    local body = str
    -- 新格式 @len@sel@page@items（v2.1.0 起）
    local a, b, c, rest = str:match("^@(%d+)@(%d+)@(%d+)@(.*)$")
    if a then
        len = clamp_len(tonumber(a))
        local sb = tonumber(b)
        if sb and sb > 0 then sel = sb end
        page = clamp_page(tonumber(c))
        body = rest or ""
    else
        -- 旧格式 @len@sel@items：没有 page 字段，按第 1 页处理
        local a2, b2, rest2 = str:match("^@(%d+)@(%d+)@(.*)$")
        if a2 then
            len = clamp_len(tonumber(a2))
            local sb = tonumber(b2)
            if sb and sb > 0 then sel = sb end
            body = rest2 or ""
        end
    end
    for t, n, tl, st in body:gmatch("(%d+):(%d+):?(%d*):?(%d*)") do
        local ti, ni = tonumber(t), tonumber(n)
        if ti and ni and ni > 0 then
            out[ti] = ni
            local tl2, st2 = tonumber(tl), tonumber(st)
            if tl2 and tl2 > 0 then meta[ti] = { tile = tl2, style = st2 or 0 } end
        end
    end
    return out, meta, len, sel, page
end

local function player_key(player)
    local name = ""
    if C.f_name then
        local ok, v = pcall(P.get_field_value, C.f_name, player, "string")
        if ok and type(v) == "string" then name = v end
    end
    name = name:gsub("[\r\n|]", "_")
    if name == "" then name = "player" end
    return name
end

local function load_store(player)
    local key = player_key(player)
    if S.store_key == key then return end
    S.store_key = key
    S.store, S.store_meta = {}, {}
    S.len = CFG.DEFAULT_LEN
    S.sel_type = nil
    S.page = 1
    S.store_dirty = false

    local raw = mod.read_file(CFG.STORE_FILE)
    if type(raw) ~= "string" or raw == "" then return end
    for line in raw:gmatch("([^\n]+)") do
        local n, rest = line:match("^([^|]+)|(.*)$")
        if n == key then
            local st, mt, len, sel, pg = deserialize_store(rest)
            S.store, S.store_meta = st, mt
            S.len = clamp_len(len)
            S.sel_type = sel
            S.page = clamp_page(pg)
            S.store_dirty = false
            return
        end
    end
end

local function save_store()
    local raw = mod.read_file(CFG.STORE_FILE)
    local lines, replaced = {}, false
    if type(raw) == "string" and raw ~= "" then
        for line in raw:gmatch("([^\n]+)") do
            local n = line:match("^([^|]+)|")
            if n == S.store_key then
                lines[#lines + 1] = string.format("%s|%s", S.store_key, serialize_store())
                replaced = true
            else
                lines[#lines + 1] = line
            end
        end
    end
    if not replaced then
        lines[#lines + 1] = string.format("%s|%s", S.store_key or "player", serialize_store())
    end
    local ok = pcall(mod.write_file, CFG.STORE_FILE, table.concat(lines, "\n"))
    if ok then S.store_dirty = false
    else mod.warn("[建筑魔杖] 存储落盘失败") end
end

local function store_add(item_type, amount, tile, style)
    local cur  = S.store[item_type] or 0
    local room = CFG.STORE_MAX - cur
    if room <= 0 then return 0 end
    local add = math.min(room, amount)
    S.store[item_type] = cur + add
    if tile and tile > 0 then S.store_meta[item_type] = { tile = tile, style = style } end
    S.store_dirty = true
    return add
end

local function store_sub(item_type, amount)
    local cur  = S.store[item_type] or 0
    local take = math.min(cur, amount)
    if take <= 0 then return 0 end
    cur = cur - take
    if cur <= 0 then S.store[item_type] = nil else S.store[item_type] = cur end
    S.store_dirty = true
    return take
end

-- 选材料：按 S.sel_type 选，数量是魔杖内部 + 背包/容器合计；魔杖内部的先扣。
local function pick_source(player)
    local view = candidate_view(player)
    local sel = S.sel_type
    local v = sel and view[sel]
    if not v or v.count <= 0 then return nil end
    return { from_store = v.store_n > 0, item_type = sel, count = v.count,
             tile = v.tile, style = v.style, entry = v.entry,
             store_n = v.store_n, inv_n = v.inv_n }
end

--══════════════════════════════════════════════════════════════════════════
-- 落位
--══════════════════════════════════════════════════════════════════════════
-- PlaceTile 的合法参数个数：不同版本分别是 8/7/6/5，bind_all 只留第一个命中的。
local PLACE_ARGCS = { 8, 7, 6, 5 }

-- 句柄为 nil 时把 8/7/6/5 全部再探一遍（不要只试第一个）。
-- 每次探测的结果都记进 S.place_info，面板自检行能直接看到「到底卡在哪一步」。
local function ensure_place_method()
    if C.m_place_tile then return true end
    if not C.WorldGen then C.WorldGen = try_type("Terraria", "WorldGen") end
    if not C.WorldGen then
        set_place_info("no-WorldGen")
        return false
    end
    local tried = {}
    for _, n in ipairs(PLACE_ARGCS) do
        local m = try_method(C.WorldGen, "PlaceTile", n)
        tried[#tried + 1] = tostring(n)
        if m then
            C.m_place_tile, C.place_argc = m, n
            set_place_info("re-detect argc=" .. n)
            return true
        end
    end
    set_place_info("no-method argc=" .. table.concat(tried, "/"))
    return false
end

local function place_one(x, y, tile, style, plr)
    if x < 0 or y < 0 then
        set_place_info(string.format("skip oob at=(%d,%d)", x, y))
        return false
    end
    if not ensure_place_method() then return false end

    -- 严格按探测到的 argc 传参，绝不"多塞/少塞"一个：
    --   argc=8 → (x,y,type,mute,forced,plr,style,0)  末位是保留参数，补 0
    --   argc=7 → (x,y,type,mute,forced,plr,style)
    --   argc=6 → (x,y,type,mute,forced,plr)
    --   argc=5 → (x,y,type,mute,forced)
    local argc = C.place_argc
    if not S.pt_logged then
        S.pt_logged = true
        mod.info(string.format("[建筑魔杖] PlaceTile 重载 argc=%d（按探测到的参数个数传参）", argc))
    end

    local ok, r
    if argc == 8 then
        ok, r = pcall(P.invoke, C.m_place_tile, x, y, tile, false, false, plr, style, 0)
    elseif argc == 7 then
        ok, r = pcall(P.invoke, C.m_place_tile, x, y, tile, false, false, plr, style)
    elseif argc == 6 then
        ok, r = pcall(P.invoke, C.m_place_tile, x, y, tile, false, false, plr)
    elseif argc == 5 then
        ok, r = pcall(P.invoke, C.m_place_tile, x, y, tile, false, true)
    else
        set_place_info(string.format("bad-argc=%s", tostring(argc)))
        if not S.pt_err_logged then
            S.pt_err_logged = true
            mod.error(string.format("[建筑魔杖] PlaceTile 重载探测异常 argc=%s", tostring(argc)))
        end
        return false
    end

    local good = ok and (r == true or r == 1)
    if good then
        S.place_count = (S.place_count or 0) + 1
        set_place_info(string.format("ok argc=%d at=(%d,%d)", argc, x, y))
        return true
    end

    S.fail_count = (S.fail_count or 0) + 1
    if not ok then
        -- 真异常才打 warn（含 tostring(r) 抛错信息），只打一次，避免一排 50 行刷屏；
        -- 返回 false 只是"这一格不可落位"（被占/无支撑），属于正常跳过，不报警。
        set_place_info(string.format("err argc=%d at=(%d,%d) %s", argc, x, y, tostring(r)))
        if not S.pt_err_logged then
            S.pt_err_logged = true
            mod.warn(string.format("[建筑魔杖] PlaceTile 调用抛错 argc=%s: %s",
                    tostring(argc), tostring(r)))
        end
    else
        set_place_info(string.format("ret=%s argc=%d at=(%d,%d)", tostring(r), argc, x, y))
    end
    return false
end

-- 沿 dir 铺一排；被占用的格子跳过并继续（只落在空位）
local function place_row(x0, y, dir, tile, style, count, plr)
    local placed = 0
    local x1, x2 = math.huge, -math.huge       -- 全部失败时不给出区间
    for i = 0, count - 1 do
        local x = x0 + dir * i
        if place_one(x, y, tile, style, plr) then
            placed = placed + 1
            if x < x1 then x1 = x end
            if x > x2 then x2 = x end
        end
    end
    return placed, x1, x2
end

local function sync_area(x1, x2, y)
    if net_mode() == 0 then return end
    pcall(mod.net.tile_square, x1 - 1, y - 1, (x2 - x1) + 3, 3)
end

--══════════════════════════════════════════════════════════════════════════
-- 铺设请求
--══════════════════════════════════════════════════════════════════════════
-- 前置声明：实现见文件下方（WAND_NAMES 白名单之后），但 request_place 在它之前就要用。
local find_wand

local function request_place(player, opts)
    -- opts.from_panel = 面板里的「放置」按钮触发：此时指针本来就压在面板上，
    -- 必须跳过下面两条「点在 GUI 上就忽略」的拦截，否则备用入口永远 no-op。
    local from_panel = type(opts) == "table" and opts.from_panel == true
    if not player then
        set_place_info("no-player")
        mod.warn("[建筑魔杖] 点击：player 为空，忽略")
        return nil
    end
    -- 绑定失败也继续往下走：wand_id 在注册阶段恒为 -1（api_item.cpp:502），
    -- 不能因为拿不到非负 id 就让整次点击静默失败（那正是"点了没反应"）。
    if not bind_lazy() then
        set_place_info("bind-fail")
        mod.warn("[建筑魔杖] 点击：反射绑定失败（bind_lazy=false），本次不放置")
        return nil
    end

    -- 门控：手持或背包里有建造魔杖才允许铺设（面板按钮 / 物品 use / 联机请求都走这里）。
    -- 判定用 find_wand（Item.value 身份标记优先，不再只看手持与显示名），必须放在
    -- bind_lazy 之后——它要用 C.f_selected / C.f_whoAmI / C.f_value 读玩家与物品。
    if not find_wand(player) then
        set_place_info("no-wand")
        if from_panel then
            mod.info("[建筑魔杖] 面板放置：未检测到建造魔杖（手持或背包），忽略")
        else
            mod.info("[建筑魔杖] 点击：未检测到建造魔杖（手持或背包），忽略")
        end
        return nil
    end

    -- 点侧边常驻按钮 / 面板本身时别顺手铺一排平台：use 回调和 on_gui 同帧发生，
    -- 已删除的「鼠标在 GUI 上」标志位改写来不及生效（而且它会吞真实点击），只能自己看坐标。
    -- 面板按钮走 from_panel 分支，这两条对它不生效。
    if not from_panel and pointer_on_side_button() then
        set_place_info("on-side")
        mod.info(string.format(
            "[建筑魔杖] 点击：落在侧边按钮上，忽略 mouse=(%s,%s) panel_rect=%s visible=%s",
            tostring(gf_int(C.f_mouseX, nil)), tostring(gf_int(C.f_mouseY, nil)),
            S.panel_rect and string.format("(%d,%d,%d,%d)", S.panel_rect.x, S.panel_rect.y,
                    S.panel_rect.w, S.panel_rect.h) or "nil", tostring(S.panel_visible)))
        return nil
    end
    if not from_panel and pointer_in_panel() then
        set_place_info("on-panel")
        mod.info(string.format(
            "[建筑魔杖] 点击：落在面板上，忽略 mouse=(%s,%s) panel_rect=%s visible=%s",
            tostring(gf_int(C.f_mouseX, nil)), tostring(gf_int(C.f_mouseY, nil)),
            string.format("(%d,%d,%d,%d)", S.panel_rect.x, S.panel_rect.y,
                    S.panel_rect.w, S.panel_rect.h), tostring(S.panel_visible)))
        return nil
    end

    load_store(player)

    -- 瞄准格：resolve_aim 四级回退，永远给一个格子，不再有 bad-aim 早退。
    -- 最坏情况（连玩家坐标都读不到）来源是 "oob"，把 fallback=0,0 明确写进自检行，
    -- 然后仍然继续走 PlaceTile —— 由 place_one 去判定这一格能不能落。
    local aim = resolve_aim(player)
    if aim.src == "oob" then
        set_place_info("fallback=0,0")
        mod.warn("[建筑魔杖] 瞄准格全部回退失败（连玩家位置都读不到），本次按 (0,0) 尝试")
    end

    local src = pick_source(player)
    if not src or src.count <= 0 then
        set_place_info("no-mat")
        mod.info("[建筑魔杖] 没有可用的可铺材料")
        return nil
    end

    local len  = clamp_len(S.len)
    local want = math.min(len, src.count)
    local dir  = gf_int(C.f_direction, player)
    if dir == 0 then dir = 1 end
    local who  = gf_int(C.f_whoAmI, player)

    if net_mode() == 1 then
        -- 联机客户端：只能用背包/容器材料。魔杖内部存储只在本机落盘，服务端看不到；
        -- 拿它当材料就等于让服务端无法对账，所以客户端一律走实体物品、由服务端扣。
        if not src.entry or (src.inv_n or 0) <= 0 then
            set_place_info("net-nomat: 联机需背包材料")
            mod.info("[建筑魔杖] 联机时须用背包/容器里的材料（魔杖内存储仅单机/开房可用）")
            return nil
        end
        local entry = src.entry
        local w = math.min(len, src.inv_n)
        local ok, err = pcall(mod.net.send, "place", string.format("%d,%d,%d,%d,%d,%d",
                aim.x, aim.y, dir, entry.tile, entry.style, w))
        if not ok then
            set_place_info("net-fail: " .. tostring(err))
            mod.warn(string.format("[建筑魔杖] 联机请求发送失败: %s", tostring(err)))
            return nil
        end
        set_place_info(string.format("net-sent w=%d at=(%d,%d)", w, aim.x, aim.y))
        return { x = aim.x, y = aim.y, want = w, placed = -1,
                 kind = "net", itype = src.item_type, left = src.inv_n - w }
    end

    local placed, x1, x2 = place_row(aim.x, aim.y, dir, src.tile, src.style, want, who)
    local left = src.count
    if placed > 0 then
        -- 魔杖内部优先，不够的部分再从背包/容器扣
        local took_store = 0
        if (src.store_n or 0) > 0 then
            took_store = store_sub(src.item_type, math.min(placed, src.store_n))
        end
        local remain = placed - took_store
        if remain > 0 and src.entry then
            consume_inventory(player, src.entry, remain)
        end
        left = src.count - placed
        sync_area(x1, x2, aim.y)
    end
    S.debug_line = string.format("目标(%d,%d) 请求 %d 落地 %d",
            aim.x, aim.y, want, placed)
    if placed <= 0 then
        -- place_one 已经写过的「ret=/err + at=」比这里更具体，别覆盖它；
        -- 只有一排全是「格子被占/越界」、根本没写过信息时才补一句 placed=0。
        if not tostring(S.place_info or ""):find("at=", 1, true) then
            set_place_info(string.format("placed=0 want=%d at=(%d,%d)", want, aim.x, aim.y))
        end
        mod.warn(string.format(
            "[建筑魔杖] 放置失败：目标(%d,%d) 请求 %d 落地 0（格子被占/无支撑/PlaceTile 未执行）",
            aim.x, aim.y, want))
    end
    return { x = aim.x, y = aim.y, want = want, placed = placed,
             kind = src.from_store and "store" or "inv",
             itype = src.item_type, left = left }
end

--══════════════════════════════════════════════════════════════════════════
-- 服务端：接收并校验请求
--══════════════════════════════════════════════════════════════════════════
local function on_net_place(payload, player_index)
    if not is_authority() then return end
    -- 专用服可能在物品注册前就收到包；这里必须自己把反射准备好，
    -- 否则 C.f_platforms / C.m_place_tile 还是 nil，会静默拒绝所有请求。
    if not bind_lazy() then
        mod.warn("[建筑魔杖] 反射未就绪，丢弃一次放置请求")
        return
    end

    -- 服务端没有 on_gui 帧号，S.frame_no 恒为 0；若沿用旧缓存，同一玩家后续请求
    -- 会读到扣料前的背包。每个请求强制重扫一次，扣料后 consume_inventory 还会再清。
    S.inv_cache = nil

    local m = net_mode()
    if m == 2 or m == 3 then
        local now  = os.clock()
        local last = S.last_req[player_index] or 0
        if now - last < CFG.MIN_INTERVAL then return end
        S.last_req[player_index] = now
    end

    local sx, sy, sdir, stile, sstyle, swant =
            tostring(payload):match("^(%-?%d+),(%-?%d+),(%-?%d+),(%d+),(%d+),(%d+)$")
    if not sx then return end

    local x, y  = tonumber(sx), tonumber(sy)
    local dir   = tonumber(sdir)
    local tile  = tonumber(stile)
    local style = tonumber(sstyle)
    local want  = tonumber(swant)

    if not (x and y and dir and tile and want) then return end
    if dir ~= 1 and dir ~= -1 then return end
    if want <= 0 or want > CFG.LEN_MAX then return end
    if x < 0 or y < 0 then return end

    -- 不再只限平台：任何 createTile > 0 的可铺图格都接受（实际有没有材料由下面扣料决定）
    if tile <= 0 then
        mod.warn(string.format("[建筑魔杖] 拒绝非法图格请求 tile=%d", tile))
        return
    end

    local pl = player_by_index(player_index)
    if not pl then return end
    local okp, px, py = pcall(P.get_field_vec2, C.f_position, pl)
    if not okp or type(px) ~= "number" then return end
    local ptx, pty = px / 16, py / 16
    local x_end = x + dir * (want - 1)
    if math.abs(x - ptx) > CFG.BUILD_DIST_X or math.abs(x_end - ptx) > CFG.BUILD_DIST_X then return end
    if math.abs(y - pty) > CFG.BUILD_DIST_Y then return end

    -- 权威扣料：这名玩家背包/四个容器里没有对应材料就直接拒，靠这一步杜绝"空手刷材料"
    local have = count_by_tile(pl, tile)
    if have <= 0 then
        mod.info("[建筑魔杖] 请求被拒：该玩家背包/容器里没有对应材料")
        return
    end
    if want > have then want = have end

    local placed, x1, x2 = place_row(x, y, dir, tile, style, want, player_index)
    if placed > 0 then
        consume_by_tile(pl, tile, placed)
        sync_area(x1, x2, y)
    end
end

--══════════════════════════════════════════════════════════════════════════
-- 配方：金锭版 / 铂金锭版（同一魔杖两条配方）
--══════════════════════════════════════════════════════════════════════════
-- 原版 id：木材 9 / 坠落之星 75 / 金锭 19 / 铂金锭 706 / 工作台 18
local RECIPES = {
    { { id = 9, count = 24 }, { id = 75, count = 2 }, { id = 19,  count = 12 } },
    { { id = 9, count = 24 }, { id = 75, count = 2 }, { id = 706, count = 12 } },
}

local function ensure_recipes()
    if S.recipe_done then return end
    local id = S.wand_id
    if not id or id < 0 then
        local ok, v = pcall(mod.item.runtime_id, CFG.WAND_NAME)
        if ok and type(v) == "number" and v >= 0 then
            id = v
            S.wand_id = v
        end
    end
    if not id or id < 0 then return end

    local all_ok = true
    for _, mats in ipairs(RECIPES) do
        local ok, err = pcall(mod.recipe.add, {
            result = id, materials = mats, station = 18,
        })
        if not ok then
            all_ok = false
            mod.warn(string.format("[建筑魔杖] 配方注册失败: %s", tostring(err)))
        end
    end
    -- 只有两条都注册成功才落标记，否则下次重建配方表还能再试一次
    S.recipe_done = all_ok
end

local function install_recipe_hook()
    if S.hook_installed then return end
    local RecipeT  = try_type("Terraria", "Recipe")
    local m_setup  = try_method(RecipeT, "SetupRecipes", 0)
    if not m_setup then
        mod.warn("[建筑魔杖] 找不到 Recipe.SetupRecipes，配方要等下次重建配方表才生效")
        return
    end
    local ok = pcall(P.install_hook, m_setup, {
        postfix = function()
            if S.recipe_done then return end
            ensure_recipes()
            -- 配方是在本次派发之后才注册进原生列表的，本次重建看不到；
            -- 这里立刻重建一次，让用户进世界当场就能合成。S.recipe_inner 防深度递归（只重入 1 层）。
            if S.recipe_done and not S.recipe_inner then
                S.recipe_inner = true
                pcall(P.invoke, m_setup)
                S.recipe_inner = false
            end
        end,
    })
    if not ok then
        mod.warn("[建筑魔杖] 配方钩子安装失败，配方要等下次重建配方表才生效")
    else
        S.hook_installed = true
    end
end

--══════════════════════════════════════════════════════════════════════════
-- 面板
--══════════════════════════════════════════════════════════════════════════
-- 显示名兜底：mod.item.register 返回的 runtime_id 和 Item.type 未必同源，
-- 所以 type 比不中时再按物品显示名认一次（language 表里的 zh / en / zh-tw 三个名字）。
local WAND_NAMES = {
    ["建造魔杖"]            = true,   -- WAND_ITEM.language.zh.name（v2.0.0 新名）
    ["Wand of Building"]    = true,   -- WAND_ITEM.language.en.name（v2.0.0 新名）
    ["建筑魔杖"]            = true,   -- 旧名，兼容已经存在的物品/存档
    ["Wand of Architecture"] = true,  -- 旧名
    ["建築魔杖"]            = true,   -- 旧繁中名
}

-- ── 物品身份判定 ──────────────────────────────────────────────────────────
-- 这台设备认「魔杖」有三个不可靠点：注册期 id 可能是 -1、Lang.GetItemNameValue 是坏的
-- （日志里 patch_handle is null 刷屏）、selectedItem 读出来的槽可能是空的。所以判定做成
-- 四级、任一命中即可，身份锚点落在 Item.value 的魔法数字上（不依赖名字、不依赖注册 id）。
local function wand_runtime_id()
    if mod.item and mod.item.runtime_id then
        local okr, r = pcall(mod.item.runtime_id, CFG.WAND_NAME)
        if okr and type(r) == "number" and r > 0 then
            if S.wand_id ~= r then S.wand_id = r end
            return r
        end
    end
    return 0
end

-- ① S.wand_id  ② runtime_id  ③ Item.value 标记  ④ 显示名（最后一级兜底）
local function is_wand_stack(it, rid)
    if not it then return false end
    local t = gf_int(C.f_type, it)

    if t > 0 then
        if S.wand_id and S.wand_id > 0 and t == S.wand_id then return true end
        if rid and rid > 0 and t == rid then return true end
    end

    -- ③ 魔法数字：defaults.value 写进去的标记，物品实例上一定读得到
    if C.f_value then
        local v = gf_int(C.f_value, it)
        if v == CFG.WAND_MARK_VALUE then return true end
    end

    -- ④ 显示名兜底；item_name 自带缓存，C.name_broken 之后不会再调内核
    if t > 0 then
        local nm = item_name(t, it)
        if nm and WAND_NAMES[nm] then return true end
    end
    return false
end

-- 返回 "hand" / "inv" / nil（同时写 S.wand_src 与 S.wand_diag 供面板诊断显示）。
-- 结果按 (frame_no, whoAmI) 缓存，一帧最多扫一次背包（与 collect_inventory_platforms 同约定）。
-- 注意：不是「手持」就算通过，背包里有也算——用户反馈手持判定不可靠时面板被锁死，
-- 只要背包里带着魔杖，「放置」按钮就应该还能用。
function find_wand(player)
    if not player then return nil end
    local fn  = S.frame_no or 0
    local who = gf_int(C.f_whoAmI, player) or -1
    local cc  = S.wand_cache
    if cc and cc.frame == fn and cc.who == who then
        S.wand_src  = cc.src
        S.wand_diag = cc.diag
        return cc.src, cc.diag
    end

    local rid  = wand_runtime_id()
    local arr  = inventory_array(player)
    local sel  = gf_int(C.f_selected, player)
    local hand = (arr and type(sel) == "number" and sel >= 0) and inv_item(arr, sel) or nil
    local ht   = hand and gf_int(C.f_type, hand) or -1
    local hv   = (hand and C.f_value) and gf_int(C.f_value, hand) or -1

    local src, hits, scanned = nil, 0, 0
    if is_wand_stack(hand, rid) then src = "hand" end
    if arr then
        local last = inv_scan_end(arr)
        scanned = last + 1
        for i = 0, last do
            local it = inv_item(arr, i)
            if it and is_wand_stack(it, rid) then
                hits = hits + 1
                if not src then src = "inv" end
            end
        end
    end

    local diag = { ht = ht, hv = hv, id = S.wand_id, hits = hits, scanned = scanned }
    S.wand_src   = src
    S.wand_diag  = diag
    S.wand_cache = { frame = fn, who = who, src = src, diag = diag }
    return src, diag
end

local function store_desc()
    local parts = {}
    for t, n in pairs(S.store) do
        if n > 0 then parts[#parts + 1] = string.format("%sx%d", item_name(t), n) end
    end
    if #parts == 0 then return "空" end
    table.sort(parts)
    return table.concat(parts, "  ")
end

local function inv_desc(player)
    local parts = {}
    for t, e in pairs(collect_inventory_platforms(player)) do
        parts[#parts + 1] = string.format("%sx%d", item_name(t, e.item), e.count)
    end
    if #parts == 0 then return "无" end
    table.sort(parts)
    return table.concat(parts, "  ")
end

local function do_load(player)               -- 背包 -> 魔杖
    local moved = 0
    for itype, e in pairs(collect_inventory_platforms(player)) do
        local room = CFG.STORE_MAX - (S.store[itype] or 0)
        if room > 0 then
            moved = moved + store_add(itype, consume_inventory(player, e, math.min(room, e.count)), e.tile, e.style)
        end
    end
    if moved > 0 then
        save_store()
        mod.info(string.format("[建筑魔杖] 装填 %d 个可铺材料进魔杖", moved))
    end
    S.inv_cache = nil
end

local function do_unload(player)             -- 魔杖 -> 背包
    local moved = 0
    for itype, n in pairs(S.store) do
        if n > 0 then
            local added = give_to_inventory(player, itype, n)
            if added > 0 then
                store_sub(itype, added)
                moved = moved + added
            end
        end
    end
    if moved > 0 then
        save_store()
        mod.info(string.format("[建筑魔杖] 从魔杖取出 %d 个可铺材料", moved))
    end
    S.inv_cache = nil
end

-- 半透明预览：以准星为锚点，按世界缩放往朝向延伸
local function draw_preview(aim, src, dir, gx, gy, gs)
    local z = world_zoom()
    -- 锚在 resolve_aim 算出的那一格（与真正落点完全相同），而不是鼠标位置：
    -- 走 tileTarget/玩家兜底时两者可能差几格，锚错等于谎报落点。
    local mx, my
    if aim and aim.ok and C.f_screenPos then
        local sx, sy = read_vec2(C.f_screenPos, nil)
        if sx then
            mx = (aim.x * 16 + 8 - sx) * z
            my = (aim.y * 16 + 8 - sy) * z
        end
    end
    if not mx or mx <= 0 then
        mx, my = gf_int(C.f_mouseX, nil), gf_int(C.f_mouseY, nil)
    end
    if not mx or mx <= 0 or not my or my <= 0 then return end

    local pad = 12 * gs
    local ox  = gx + pad
    local oy  = gy + 32 * gs + pad * 0.5      -- 内容区原点

    local px   = 16 * z
    local len  = clamp_len(S.len)
    local can  = math.min(len, src and src.count or 0)

    for i = 0, len - 1 do
        local cx = mx + dir * i * px - px / 2
        local cy = my - px / 2
        local color = (i < can) and CFG.PREVIEW_FILL or CFG.PREVIEW_MISS
        pcall(mod.gui.rect, cx - ox, cy - oy, px - 1, px - 1, color)
    end
end

local setup    -- 前置声明：绑定失败时 on_gui 下一帧会重试 setup

function mod.on_gui()
    -- setup 以前只在加载时跑一次，bind 失败后注释里说的“下一帧重试”其实是死代码。
    -- 这里每帧检查，绑定失败就再试，成功后 S.setup_done=true。
    if not S.setup_done then pcall(setup) end
    S.frame_no = (S.frame_no or 0) + 1
    local g  = mod.gui
    local gs = ui_scale()

    -- 面板宽度：420*gs（横向更宽松，名字/按钮不再挤成一列）；
    -- 屏幕更窄时缩到 screenW - 24gs，但绝不低于 300gs（再窄按钮文字就放不下）。
    local sw0 = gf_int(C.f_screenW, nil)
    local pw  = math.floor(CFG.PANEL_W * gs)
    if type(sw0) == "number" and sw0 > 0 then
        pw = math.min(pw, sw0 - math.floor(CFG.PANEL_EDGE * gs))
    end
    local pw_min = math.floor(CFG.PANEL_W_MIN * gs)
    if pw < pw_min then pw = pw_min end

    S.panel_rect    = nil   -- 每帧重录；窗口被隐藏/折叠时调用不到 on_gui，宁可不拦截也别拦错地方
    S.panel_visible = false -- 只有本帧 set_visible 成功后才置 true（pointer_in_panel 据此拦截）

    -- ① 反射绑定失败也别静默：计数报警 + 照常把窗口放出来，
    --    让用户至少看到一个写着“初始化失败”的面板，而不是一片空白。
    if not bind_lazy() then
        S.bind_fail = S.bind_fail + 1
        if S.bind_fail % 60 == 1 then
            mod.warn(string.format(
                "[建筑魔杖] 反射绑定失败（连续 %d 帧）：wand_id=%s myPlayer=%s 有选中格字段=%s 模式=%s",
                S.bind_fail, tostring(S.wand_id), tostring(gf_int(C.f_myPlayer, nil)),
                tostring(C.f_selected ~= nil), tostring(net_mode())))
        end
        if pcall(g.set_visible, true) then S.panel_visible = true end
        pcall(g.set_title, "建造魔杖 v2.1.1", "W")
        pcall(g.set_width, pw)
        if S.placed_mode ~= "fail" then
            pcall(g.set_pos, math.max(8, gf_int(C.f_screenW, nil) - pw - 24), math.floor(96 * gs))
            S.placed_mode = "fail"
            S.ui_clamped  = false
        end
        g.text("初始化失败：反射绑定不完整", { 255, 150, 150, 255 })
        g.text(string.format("wand_id = %s", tostring(S.wand_id)))
        g.text("物品能正常合成与持有，但面板功能暂时不可用。")
        g.text("请把日志里 [建筑魔杖] 开头的行发给作者。")
        return
    end
    S.bind_fail = 0

    -- ② 永不自动隐藏：窗口常显，只有用户自己在标题栏点折叠才会收起。
    if pcall(g.set_visible, true) then S.panel_visible = true end
    pcall(g.set_title, "建造魔杖 v2.1.1", "W")
    -- set_width 吃的是屏幕像素；每帧重设一次，屏幕旋转/缩放变化后也能对上。
    pcall(g.set_width, pw)

    if S.placed_mode ~= "ok" then
        local sw = gf_int(C.f_screenW, nil)
        -- 右侧留出 66*gs 的竖条给常驻按钮，别让按钮压在面板按钮上
        pcall(g.set_pos, math.max(8, sw - pw - 24 - math.floor(66 * gs)), math.floor(96 * gs))
        S.placed_mode = "ok"
        S.ui_clamped  = false   -- 换了位置就重新检查一次越界
        S.clamp_tries = 0
        S.clamp_logged = false
    end

    -- 位置兜底：首帧 set_pos 会被 gui_layout.json 的存档位置顶掉
    -- （l_gui_set_pos 在 initial_position==true 时忽略传入坐标，gui_lua.inc:325-336；
    --   而 initial_position 是回调返回后才置 false，gui_window.inc:312）。
    -- 所以越界时**不能**马上认定"纠正过了"，得等某一帧 get_pos 真的回到范围内；
    -- 否则一次失效的 set_pos 就把 ui_clamped 焊死，坏位置永久留着。
    if not S.ui_clamped then
        local okc, cx, cy = pcall(g.get_pos)
        local sw, sh = gf_int(C.f_screenW, nil), gf_int(C.f_screenH, nil)
        if okc and type(cx) == "number" and type(cy) == "number" and sw > 0 and sh > 0 then
            if cx < 0 or cy < 0 or cx > sw * 0.9 or cy > sh * 0.9 then
                pcall(g.set_pos, math.floor(8 * gs), math.floor(sh * 0.25))
                S.clamp_tries = S.clamp_tries + 1
                if not S.clamp_logged then
                    S.clamp_logged = true
                    mod.warn(string.format("[建筑魔杖] 窗口位置越界 (%s,%s)，正在拉回左上",
                            tostring(cx), tostring(cy)))
                end
                if S.clamp_tries >= 120 then S.ui_clamped = true end   -- 极端情况别无限重试
            else
                S.ui_clamped = true
                S.clamp_tries = 0
            end
        end
    end

    local player = local_player()
    if not player or gf_bool(C.f_gameMenu, nil) then
        g.text("请先进入世界")
        g.text("（进入世界并手持建筑魔杖后，面板即可使用）")
        return
    end
    load_store(player)

    local okp, gx, gy = pcall(g.get_pos)
    local have_pos = okp and type(gx) == "number" and type(gy) == "number"
    if not have_pos then gx, gy = 0, 0 end

    -- 内容区宽度与配色：下面所有绝对坐标绘制都基于这两个值
    local W = pw - math.floor(WIN_PAD * 2 * gs)
    if W < 1 then W = 1 end
    local COL_TEXT = { 225, 235, 255, 255 }
    local COL_DIM  = { 160, 175, 205, 255 }
    local COL_WARN = { 255, 190, 120, 255 }
    local COL_SEP  = { 88, 100, 132, 160 }

    -- ③ 一次性自检日志：第一次绑定成功后打一行，用户看一眼就知道卡在哪。
    if not S.logged then
        S.logged = true
        local idx = gf_int(C.f_selected, player)
        local it  = inv_item(inventory_array(player), idx)
        local t   = it and item_type_of(it) or -1
        local okr, rid = pcall(mod.item.runtime_id, CFG.WAND_NAME)
        mod.info(string.format(
            "[建筑魔杖] on_gui 首次绑定：wand_id=%s runtime=%s myPlayer=%s 选中格=%s 选中type=%s 选中名=%s 手持=%s 模式=%s",
            tostring(S.wand_id), tostring(okr and rid or "err"), tostring(gf_int(C.f_myPlayer, nil)),
            tostring(idx), tostring(t), (t > 0) and tostring(item_name(t, it)) or "-",
            tostring(find_wand(player) or "nil"), tostring(net_mode())))

        -- 字段真实字节宽度：内核 get_field_raw 省略 size 时会按字段真实类型给长度，
        -- 若这里不是 2，说明 short 字段的类型推断失败（会读成天文数字 -> 平台判定必然全灭）
        local arr0 = inventory_array(player)
        local it0  = arr0 and inv_item(arr0, gf_int(C.f_selected, player))
        if it0 then
            local function rawlen(f)
                if not f then return "nofield" end
                local ok, raw = pcall(P.get_field_raw, f, it0)
                if ok and type(raw) == "string" then return tostring(#raw) end
                return "err"
            end
            mod.info(string.format("[BW] rawlen: type=%s createTile=%s placeStyle=%s",
                rawlen(C.f_type), rawlen(C.f_createTile), rawlen(C.f_placeStyle)))
        end
        -- 背包前 12 个非空格子的判定明细：type / tile / style / 平台表判定 / 名字判定
        local dumped = 0
        local last0  = arr0 and inv_scan_end(arr0) or -1
        for i = 0, last0 do
            local it = inv_item(arr0, i)
            if it then
                local t  = item_type_of(it)
                local st = item_stack_of(it)
                if t > 0 and st > 0 then
                    local tile, style = tile_style_from_item(it)
                    mod.info(string.format("[BW] slot=%d type=%d stack=%d tile=%d style=%d platTbl=%s",
                        i, t, st, tile, style,
                        tostring(is_platform_tile(tile))))
                    dumped = dumped + 1
                    if dumped >= 12 then break end
                end
            end
        end
        if dumped == 0 then mod.info("[BW] slot dump: inventory has no non-empty item") end
    end

    -- ④ 门控：手持**或背包里**有建造魔杖，面板才可用 —— 否则一个按钮都不画，
    --    只留提示 + 「重新检测」按钮 + 一行诊断现场。绝不能 set_visible(false)：
    --    历史上每帧隐藏会让面板永久消失（还得重进世界才回来）。
    --    为什么不再只看「手持」：注册 id 可能恒为 -1、Lang 显示名在这台设备上坏了，
    --    只看手持会把面板锁死（用户反馈：明明拿着魔杖却只有一行灰字）。
    --    find_wand 用 Item.value 魔法数字做身份锚点，扫背包兜底（见文件下方 is_wand_stack）。
    local wand_src, wdiag = find_wand(player)
    local held = wand_src ~= nil
    if not held then
        local gmsg_h  = math.floor(28 * gs)
        local gbtn_h  = math.floor(CFG.BTN_H * gs)
        local gline   = math.floor(6 * gs)
        local gbtn_w  = math.min(W, math.floor(136 * gs))
        local gdiag_h = math.floor(21 * gs)

        pcall(g.set_cursor, 0, 0)
        g.text(fit_text("未检测到建造魔杖（手持或背包）", W, gs), COL_WARN)

        -- 出口：万一判定逻辑还有漏，点一下强制清缓存重扫，别让用户彻底没救。
        local gb_y = gmsg_h + gline
        if g.button_at(0, gb_y, gbtn_w, gbtn_h,
                fit_text("重新检测", gbtn_w - math.floor(8 * gs), gs)) then
            S.frame_no   = nil       -- 下一帧从 1 重新计数 → 两处背包缓存同时失效
            S.inv_cache  = nil
            S.wand_cache = nil
            mod.info("[建筑魔杖] 手动重新检测：已清空手持/背包扫描缓存")
        end

        -- 诊断现场：直接显示在面板上，用户截图就能回传，不必翻日志。
        local gd_y = gb_y + gbtn_h + gline
        local ht_s = (wdiag and type(wdiag.ht) == "number" and wdiag.ht >= 0)
                and tostring(wdiag.ht) or "-"
        local hv_s = (wdiag and type(wdiag.hv) == "number" and wdiag.hv >= 0)
                and tostring(wdiag.hv) or "-"
        local dtxt = string.format("手type=%s 手value=%s id=%s 包内=%d/%d格",
                ht_s, hv_s, tostring(S.wand_id or "-"),
                (wdiag and wdiag.hits) or 0, (wdiag and wdiag.scanned) or 0)
        g.text_at(0, gd_y, fit_text(dtxt, W, gs, 0.75), COL_DIM, 0.75)

        local gph = gd_y + gdiag_h + math.floor(4 * gs)
        pcall(g.set_cursor, 0, gph)
        if have_pos and S.panel_visible then
            local okt, tn = pcall(os.time)
            S.panel_rect = { x = gx, y = gy, w = pw,
                             h = math.floor((WIN_TITLE_H + WIN_PAD * 2) * gs) + gph,
                             t = ((okt and type(tn) == "number") and tn) or nil }
        end
        return
    end

    -- 先算瞄准/材料/候选：面板内容全部依赖它们
    local aim = resolve_aim(player)
    local src = pick_source(player)          -- 内部会 ensure_selection，填好 S.sel_type
    local view, cand_list = candidate_view(player)
    local sel_e   = S.sel_type and view[S.sel_type] or nil
    local sel_cnt = sel_e and sel_e.count or 0
    local sel_name = sel_e and item_name(S.sel_type, sel_e.entry and sel_e.entry.item) or "无"

    -- ── 三页布局预算（v2.1.0）──────────────────────────────────────────────
    -- 目标只有一个：任何一页都能完整装进屏幕，「装填/取出/放置」永远可见可点。
    -- chrome = 窗口非内容部分（标题栏 32 + 上下内边距 12*2，基准像素再乘 gs）。
    local sh = gf_int(C.f_screenH, nil)
    if type(sh) ~= "number" or sh <= 0 then sh = 1080 end   -- 取不到屏幕高度按 1080 兜底
    local chrome = math.floor((WIN_TITLE_H + WIN_PAD * 2) * gs)
    local edge   = math.floor(12 * gs)      -- 屏幕底部强制留白
    local top    = math.floor(8 * gs)

    -- 行距/控件高度：所有控件沿用 CFG.BTN_H（36*gs），行距 6*gs
    local btn_h = math.floor(CFG.BTN_H * gs)
    local gap   = math.floor(6 * gs)
    local gap_c = math.floor(4 * gs)        -- 同一行内按钮的水平间距
    local cols  = CFG.CAND_COLS
    local row_h = math.floor(CFG.ROW_H * gs)
    local diag_line_h = math.floor(21 * gs)

    local gy_use = (type(gy) == "number") and gy or math.floor(96 * gs)
    local page = clamp_page(S.page)
    S.page = page

    -- 可用内容高度 = 屏幕高 - 窗口 y - 底部留白 - 窗口非内容部分
    local avail = sh - gy_use - edge - chrome
    if avail < 0 then avail = 0 end

    -- 第 1 页的行数：3..6。放不下优先减行（最低 3），再考虑把窗口上移（见下面的 need_h）。
    local tab_h  = btn_h + gap
    local info_h = btn_h + gap
    local rows = math.floor((avail - tab_h - info_h) / row_h)
    if rows < CFG.CAND_ROWS_MIN then rows = CFG.CAND_ROWS_MIN end
    if rows > CFG.CAND_ROWS_MAX then rows = CFG.CAND_ROWS_MAX end
    S.panel_rows = rows

    -- 第 3 页的自检行数：4 -> 2 -> 1。永远优先保证三个操作按钮（尤其「放置」）在屏内。
    local diag_lines = 4
    while diag_lines > 1 and chrome + page_content_h(3, rows, diag_lines, gs) > sh - gy_use - edge do
        diag_lines = (diag_lines == 4) and 2 or 1
    end

    -- 窗口位置兜底：按三页里最高的一页核对；装不下就整体上移，且只上移不下移（尊重用户拖动）。
    local need_h = 0
    for p = 1, CFG.PAGE_COUNT do
        local hh = page_content_h(p, rows, diag_lines, gs)
        if hh > need_h then need_h = hh end
    end
    if have_pos and gy_use + chrome + need_h > sh - edge then
        local ny = sh - chrome - need_h - edge
        if ny < top then ny = top end
        if ny < gy_use then
            pcall(g.set_pos, gx, ny)
            gy_use = ny
            avail  = sh - gy_use - edge - chrome
            if avail < 0 then avail = 0 end
        end
    end
    local budget = avail
    S.overflow = 0

    -- 候选材料分页（按物品类型分页，行数随屏幕自适应）
    local page_size = rows * cols
    local pages     = math.max(1, math.ceil(#cand_list / page_size))
    if S.cand_page < 0 then S.cand_page = 0 end
    if S.cand_page >= pages then S.cand_page = pages - 1 end
    local first_i = S.cand_page * page_size + 1
    local last_i  = math.min(#cand_list, first_i + page_size - 1)

    local y = 0
    -- 每个元素画完都检查「y0 + h <= budget」；溢出数显示在自检行，正常恒为 0。
    local function mark(y0, h)
        if y0 + h > budget then S.overflow = S.overflow + 1 end
    end
    local function sep()
        g.rect(0, y, W, math.max(1, math.floor(gs)), COL_SEP)
        mark(y, gap)
        y = y + gap
    end

    -- 0) 分页按钮：三个等宽，当前页文案前加 ▶（g.button_at 没有按下态，只能靠文案区分）。
    --    点击后立刻改 S.page，并**在本帧**继续按新页排版（page 变量马上重读，不等下一帧）。
    local tab_w = math.floor((W - gap_c * (CFG.PAGE_COUNT - 1)) / CFG.PAGE_COUNT)
    local TAB_LABELS = { "选料", "长度", "操作" }
    for i = 1, CFG.PAGE_COUNT do
        local label = string.format("%s%d %s", (page == i) and "▶" or "", i,
                TAB_LABELS[i] or tostring(i))
        if g.button_at((i - 1) * (tab_w + gap_c), 0, tab_w, btn_h,
                fit_text(label, tab_w - math.floor(8 * gs), gs)) then
            if page ~= i then
                page = i
                S.page = i
                S.store_dirty = true      -- 页码与 len/sel 同一个存档文件，一起落盘
            end
        end
    end
    mark(0, tab_h)
    y = tab_h

    if page == 1 then
        -- ── 第 1 页「选料」──────────────────────────────────────────────────
        -- 1) 当前材料（左）｜材料翻页 ◀ n/m ▶（右，同一行）—— 翻页逻辑原样搬过来，只改位置
        local info_y   = y
        local pb_w     = btn_h
        local ptxt     = string.format("%d/%d", S.cand_page + 1, pages)
        local ptw      = text_px(ptxt, gs)
        local pgap     = math.floor(4 * gs)
        local paging_w = pb_w * 2 + ptw + pgap * 2
        local left_w   = W - paging_w - math.floor(8 * gs)
        if left_w < 1 then left_w = 1 end
        local info = string.format("当前: %s x%d", sel_name, sel_cnt)
        g.text_at(0, info_y + math.floor((btn_h - 28 * gs) / 2),
                  fit_text(info, left_w, gs), COL_TEXT)
        local pv_x = W - paging_w
        local nx_x = W - pb_w
        if g.button_at(pv_x, info_y, pb_w, btn_h, "◀") and S.cand_page > 0 then
            S.cand_page = S.cand_page - 1
        end
        if g.button_at(nx_x, info_y, pb_w, btn_h, "▶") and S.cand_page < pages - 1 then
            S.cand_page = S.cand_page + 1
        end
        g.text_at(pv_x + pb_w + pgap, info_y + math.floor((btn_h - 28 * gs) / 2), ptxt, COL_DIM)
        mark(info_y, btn_h)
        y = info_y + btn_h + gap

        -- 2) 候选材料：2 列 × rows 行（固定高度，只画当前页）
        local col_w   = math.floor((W - gap_c * (cols - 1)) / cols)
        local cand_y0 = y
        for r = 0, rows - 1 do
            local by = cand_y0 + r * row_h + math.floor((row_h - btn_h) / 2)
            for c = 0, cols - 1 do
                local idx = first_i + r * cols + c
                if idx <= last_i then
                    local e = cand_list[idx]
                    local label = string.format("%s%s x%d",
                            (e.type == S.sel_type) and "▶" or " ",
                            item_name(e.type, e.entry and e.entry.item), e.count)
                    local bx = c * (col_w + gap_c)
                    if g.button_at(bx, by, col_w, btn_h,
                            fit_text(label, col_w - math.floor(8 * gs), gs)) then
                        S.sel_type = e.type
                        S.store_dirty = true
                    end
                end
            end
        end
        if #cand_list == 0 then
            g.text_at(0, cand_y0 + math.floor(6 * gs), "背包/容器里没有可铺材料", COL_WARN)
        end
        mark(cand_y0, rows * row_h)
        y = cand_y0 + rows * row_h

    elseif page == 2 then
        -- ── 第 2 页「长度」──────────────────────────────────────────────────
        -- 1) 当前材料 + 长度
        local info_y = y
        local info = string.format("当前: %s 长度 %d", sel_name, clamp_len(S.len))
        g.text_at(0, info_y + math.floor((btn_h - 28 * gs) / 2), fit_text(info, W, gs), COL_TEXT)
        mark(info_y, btn_h)
        y = info_y + btn_h + gap

        -- 2) 长度微调：[-10] [-1] [长度 N] [+1] [+10] 五个按钮同一行横排
        local step_y = y
        local cell_w = math.floor((W - gap_c * 4) / 5)
        local steps  = { { "-10", -10 }, { "-1", -1 }, { "+1", 1 }, { "+10", 10 } }
        local cx = 0
        for i = 1, 2 do
            if g.button_at(cx, step_y, cell_w, btn_h, steps[i][1]) then
                set_len(S.len + steps[i][2])
            end
            cx = cx + cell_w + gap_c
        end
        g.rect(cx, step_y, cell_w, btn_h, { 38, 52, 92, 220 })
        local len_txt = string.format("长度 %d", clamp_len(S.len))
        g.text_at(cx + math.floor((cell_w - text_px(len_txt, gs)) / 2),
                  step_y + math.floor((btn_h - 28 * gs) / 2), len_txt, COL_TEXT)
        cx = cx + cell_w + gap_c
        for i = 3, 4 do
            if g.button_at(cx, step_y, cell_w, btn_h, steps[i][1]) then
                set_len(S.len + steps[i][2])
            end
            cx = cx + cell_w + gap_c
        end
        mark(step_y, btn_h)
        y = step_y + btn_h + gap

        -- 3) 10 / 20 / 50 快捷档：一行三格
        local pre_y = y
        local pre_w = math.floor((W - gap_c * 2) / 3)
        for i = 1, #CFG.LENGTHS do
            local label = string.format("%d 格", CFG.LENGTHS[i])
            if g.button_at((i - 1) * (pre_w + gap_c), pre_y, pre_w, btn_h, label) then
                set_len(CFG.LENGTHS[i])
            end
        end
        mark(pre_y, btn_h)
        y = pre_y + btn_h + gap

        -- 4) 滑条：唯一依赖布局光标的控件；画完立刻把光标交给下一个绝对 y
        local sld_y = y
        pcall(g.set_cursor, 0, sld_y)
        local okv, sv = pcall(g.slider, "长度", clamp_len(S.len), CFG.LEN_MIN, CFG.LEN_MAX)
        if okv and type(sv) == "number" then set_len(sv) end
        mark(sld_y, btn_h)
        y = sld_y + btn_h + gap

    else
        -- ── 第 3 页「操作」──────────────────────────────────────────────────
        -- 装填 / 取出 / 放置 三个全宽按钮各占一行（放在最上面，永远看得见）
        if g.button_at(0, y, W, btn_h,
                fit_text("装填（背包/容器 → 魔杖）", W - math.floor(8 * gs), gs)) then
            do_load(player)
        end
        mark(y, btn_h)
        y = y + btn_h + gap

        if g.button_at(0, y, W, btn_h,
                fit_text("取出（魔杖 → 背包）", W - math.floor(8 * gs), gs)) then
            do_unload(player)
        end
        mark(y, btn_h)
        y = y + btn_h + gap

        -- 「放置」备用入口：和物品 use 走同一个 request_place；
        -- from_panel=true 跳过「指针在面板上就忽略」的拦截（否则按钮永远 no-op）。
        -- 门控：手持或背包里都没有建造魔杖就只写自检，绝不放行（这里是第二道闸）。
        if g.button_at(0, y, W, btn_h,
                fit_text("放置（不用点物品）", W - math.floor(8 * gs), gs)) then
            if not find_wand(player) then
                set_place_info("no-wand")
                mod.info("[建筑魔杖] 面板放置：未检测到建造魔杖（手持或背包），忽略")
            else
                local okr, res = pcall(request_place, player, { from_panel = true })
                S.inv_cache = nil
                if not okr then
                    set_place_info("err:" .. tostring(res))
                    mod.error("[建筑魔杖] 面板放置异常: " .. tostring(res))
                elseif type(res) == "table" then
                    mod.info(string.format("[建筑魔杖] 面板放置：目标(%d,%d) 落地=%s",
                            res.x, res.y, tostring(res.placed)))
                end
            end
        end
        mark(y, btn_h)
        y = y + btn_h + gap

        sep()

        -- 自检区（v2.1.1）：diag_lines 行 0.75 倍字号，放不下就折行/截断加 …
        -- 字段含义（原 n/m 这类临时值已删除，用户看不懂）：
        --   Use触发   mod.item.use 回调被内核调用的次数，只证明「点击→物品使用」链路通
        --   落位      PlaceTile 返回 true 的格数累计（真正铺下去的）
        --   失败      PlaceTile 返回 false / 抛异常的格数累计（被占、无支撑都算）
        --   单机/联机 net_mode()：0=单机、1=联机客户端、其它=服务端
        --   名字      物品显示名来源：字段 / Lang / 编号
        --   溢出      本帧面板内容超出版面预算的次数，正常恒 0
        --   瞄准格    resolve_aim 算出的图格坐标，来源＝
        --             target(游戏 tileTarget)/mouse(鼠标反算)/player(脚下兜底)/oob(全失败用 0,0)
        --   材料      当前可铺材料种类数（候选列表长度，不是个数）
        --   手持格    Player.selectedItem，当前选中的背包格号（0 起）
        --   物品id    最近一次 use 读到的魔杖 Item.type（运行时类型号，不是注册 id）
        --   注册      setup 注册物品得到的 id（括号里是 runtime 名字）
        --   PlaceTile 探测到的 PlaceTile 重载参数个数 / 是否可用
        --   上次放置  最近一次 place_one / request_place 的结果（含落点坐标）
        local mn = net_mode()
        local mode_s = (mn == 0 and "单机") or (mn == 1 and "联机") or "服务端"
        local pt_s = C.m_place_tile and (tostring(C.place_argc) .. "参/ok") or "nil"
        local aim_s = string.format("(%s,%s)", tostring(S.aim_x or -1), tostring(S.aim_y or -1))
        local sel_slot = gf_int(C.f_selected, player)
        local wand_id = tonumber(S.wand_id) or -1
        local diag_texts = {
            string.format("Use触发 %d 次 | 落位 %d 格 | 失败 %d | %s | 名字=%s | 溢出 %d",
                    S.use_seen or 0, S.place_count or 0, S.fail_count or 0, mode_s,
                    tostring(C.name_via or "编号"), S.overflow or 0),
            string.format("瞄准格=%s 来源=%s | 材料 %d 种 | 手持格 %d | 物品id %d | 注册 %s | PlaceTile=%s",
                    aim_s, tostring(S.aim_src or "-"), #cand_list, sel_slot,
                    wand_id, tostring(S.reg_info or "?"), pt_s),
            "上次放置=" .. tostring(S.place_info or "-"),
        }
        local sc_lines = {}
        for i = 1, #diag_texts do
            if #sc_lines >= diag_lines then break end
            local got = wrap_text(diag_texts[i], W, gs, 0.75, diag_lines - #sc_lines)
            for k = 1, #got do sc_lines[#sc_lines + 1] = got[k] end
        end
        local sc_y = y
        for i = 1, #sc_lines do
            g.text_at(0, sc_y + (i - 1) * diag_line_h, sc_lines[i],
                    { 150, 165, 200, 255 }, 0.75)
        end
        mark(sc_y, diag_lines * diag_line_h)
        y = sc_y + diag_lines * diag_line_h + math.floor(4 * gs)
    end

    -- 预览直接画在世界层（绝对屏幕坐标），不占内容高度（三页都画）
    if aim.ok and src then
        local dir = gf_int(C.f_direction, player)
        if dir == 0 then dir = 1 end
        draw_preview(aim, src, dir, gx or 0, gy_use, gs)
    end

    -- ── 布局收尾：把布局光标推到面板内容的真实底部 ─────────────────────────
    -- g.rect / g.text_at / g.button_at 都是「相对内容区原点的绝对坐标」，画完不推进
    -- ctx.cy / ctx.prev_h（gui_lua.inc:427-473）；内核在 on_gui 返回后才按
    -- ws.h = th + p + (ctx.cy + ctx.prev_h) + p 算窗口高度（gui_window.inc:319-320）。
    -- set_cursor 会把 cy 设为传入值并把 prev_h 清 0（gui_lua.inc:354-366），所以这里传 ph
    -- 等于把窗口高度精确写成 chrome + ph；不推光标，窗口就只有「标题 + 内边距」那么高，
    -- 窗口外的一切（包括「放置」按钮）就永远收不到点击（g_input_owner 只按窗口矩形判定）。
    local ph = y
    if ph > budget then ph = budget end     -- 极端矮屏：宁可少露一点，也不让窗口画出屏幕
    if ph < 1 then ph = 1 end
    pcall(g.set_cursor, 0, ph)

    -- 拦截矩形：窗口实际高度 = 标题 + 上下内边距 + 内容高度（不是 ph 本身）
    if have_pos and S.panel_visible then
        local okt, tn = pcall(os.time)
        S.panel_rect = { x = gx, y = gy_use, w = pw, h = chrome + ph,
                         t = ((okt and type(tn) == "number") and tn) or nil }
    end

    -- 长度/选中变化后节流落盘（1 秒最多一次），避免每帧写文件
    if S.store_dirty and (os.clock() - (S.save_tick or 0)) >= 1.0 then
        save_store()
        S.save_tick = os.clock()
    end

    -- ⑧ 侧边常驻档位按钮：绝对屏幕坐标，画在最后（后画的上层，不会被面板内容盖住）。
    --    门控：不持杖不画、不响应点击（held 在上面已判过，这里再收一道口子）。
    --    内容区原点 = (gx + pad, gy + title + pad*0.5)，与 gui_window.inc:247-248 / 303-304 同源；
    --    g.rect / g.text_at 吃的是「相对内容区原点」的坐标，所以这里减掉原点。
    if held then
        local sx, sy, sbw, sbh = side_button_rect(gs)
        if sx then
            local ox = gx + math.floor(12 * gs)
            local oy = gy + math.floor(32 * gs + 6 * gs)
            local mx, my = gf_int(C.f_mouseX, nil), gf_int(C.f_mouseY, nil)
            local hit = mx >= sx and mx <= sx + sbw and my >= sy and my <= sy + sbh
            local mdown = false
            if C.f_mouseLeft then
                local okm, mv = pcall(P.get_field_value, C.f_mouseLeft, nil, "bool")
                mdown = okm and (mv == true or mv == 1) or false
            end
            local label = tostring(clamp_len(S.len))
            g.rect(sx - ox, sy - oy, sbw, sbh, hit and { 70, 130, 210, 235 } or { 30, 48, 92, 220 })
            -- ASCII 字符宽 10*gs、行高 28*gs（gui_types.inc:689-698），据此手算居中
            local tw = math.floor(10 * gs * #label)
            local th = math.floor(28 * gs)
            g.text_at(sx - ox + math.floor((sbw - tw) / 2), sy - oy + math.floor((sbh - th) / 2),
                    label, { 245, 250, 255, 255 }, 1.0)
            if hit and mdown and not S.side_down then
                cycle_short_len()
                mod.info(string.format("[建筑魔杖] 侧边按钮切档 → %d 格", S.len))
            end
            S.side_down = mdown
        end
    end
end

--══════════════════════════════════════════════════════════════════════════
-- 物品定义与加载
--══════════════════════════════════════════════════════════════════════════
local WAND_ITEM = {
    name      = CFG.WAND_NAME,
    texture   = "wand_architecture.png",
    tooltip   = true,
    sacrifice = 1,
    defaults  = {
        width = 28, height = 28,
        useStyle = 1, useAnimation = 10, useTime = 10,
        autoReuse = false, noMelee = true,
        damage = 0, knockBack = 0,
        maxStack = 1, rare = 3, value = 987654,   -- value 是身份标记，见 CFG.WAND_MARK_VALUE
        melee = false, magic = false, ranged = false,
    },
    language = {
        en = {
            name    = "Wand of Building",
            tooltip = "Places a row of any placeable blocks or platforms toward your facing.\n"
                    .. "Length 1-200, adjustable in the panel (10/20/50 shortcuts).\n"
                    .. "Only fills empty tiles. Uses the wand's stock first, then inventory and banks.",
        },
        zh = {
            name    = "建造魔杖",
            tooltip = "沿朝向铺一排任意可放置方块或平台，只落在空位。\n"
                    .. "长度 1-200 可在面板调节（10/20/50 快捷档）。\n"
                    .. "材料优先取魔杖内存储，其次取背包与储蓄容器。",
        },
        ["zh-tw"] = {
            name    = "建造魔杖",
            tooltip = "沿朝向鋪一排任意可放置方塊或平台，只落在空位。\n"
                    .. "長度 1-200 可在面板調節（10/20/50 快捷檔）。\n"
                    .. "材料優先取魔杖內存儲，其次取背包與儲蓄容器。",
        },
    },
    can_use = function(player, item, ignore_cursed)
        return true
    end,
    use = function(player, item)
        -- 面板内诊断：只要内核调到 use 就计数，自检行直接显示，不必翻日志。
        -- 只保留「被调用次数」——原来那串 p=/t=/n=/m= 是临时值，含义不明且与
        -- 自检行的「物品id / 手持格」重复，已删除（S.use_last 同步移除）。
        S.use_seen = (S.use_seen or 0) + 1

        -- ① 先无条件留痕：只要 use 被内核调到，就必须有一行日志，避免"点了没反应"无迹可查。
        local mx  = gf_int(C.f_mouseX, nil)
        local my  = gf_int(C.f_mouseY, nil)
        local mid = gf_int(C.f_myPlayer, nil)
        if not player then
            mod.warn(string.format(
                "[建筑魔杖] 点击：player 为空，忽略 myPlayer=%s mouse=(%s,%s) mode=%s",
                tostring(mid), tostring(mx), tostring(my), tostring(net_mode())))
            return
        end
        -- ② 不再依赖 wand_id 放行：注册阶段 runtime_id 恒为 -1，bind_lazy 只要反射就绪即可。
        bind_lazy()
        if (S.wand_id or -1) < 0 then
            -- item 是 lightuserdata 句柄，不能 item.type 直接索引；走反射取 type。
            local t = item_type_of(item)
            if t > 0 then S.wand_id = t end
        end
        local aim, src
        pcall(load_store, player)          -- 日志里的材料数要与 request_place 看到的一致
        local ok1, a = pcall(resolve_aim, player)
        if ok1 then aim = a end
        local ok2, s = pcall(pick_source, player)
        if ok2 then src = s end
        mod.info(string.format(
            "[建筑魔杖] 点击 bind=%s wand_id=%s myPlayer=%s mode=%s mouse=(%s,%s) aim=%s mats=%s",
            tostring(C.bound), tostring(S.wand_id), tostring(mid), tostring(net_mode()),
            tostring(mx), tostring(my),
            (aim and aim.ok) and string.format("(%d,%d)@%s",
                    aim.x, aim.y, tostring(aim.src)) or "nil",
            tostring(src and src.count or 0)))

        -- ③ 真正落位；request_place 的所有静默分支现已各自带 info/warn。
        local ok, res = pcall(request_place, player)
        if not ok then
            mod.error(string.format("[建筑魔杖] 放置异常: %s", tostring(res)))
            return
        end
        if type(res) ~= "table" then
            mod.warn("[建筑魔杖] 放置未执行（原因见上一行 info/warn）")
            return
        end
        mod.info(string.format(
            "[建筑魔杖] 放置：目标(%d,%d) 请求=%d 落地=%s 材料=%s 剩余=%s",
            res.x, res.y, res.want,
            tostring(res.placed < 0 and "联机请求已发送" or res.placed),
            tostring(res.itype), tostring(res.left)))
    end,
}

setup = function()
    if S.setup_done then return end
    if not bind_all() then
        mod.warn("[BW] setup: bind_all failed, will retry from on_gui")
        return
    end
    mod.info(string.format("[BW] bind: platforms=%s itemname=%s setdefaults=%s placetile=%s place_argc=%s",
        tostring(C.f_platforms ~= nil), tostring(C.m_item_name ~= nil),
        tostring(C.m_setDefaults ~= nil), tostring(C.m_place_tile ~= nil), tostring(C.place_argc)))
    mod.info(string.format("[BW] env: lualoader=%s platform=%s arch=%s mod_dir=%s",
        tostring(mod.version), tostring(mod.platform), tostring(mod.arch), tostring(mod.mod_dir)))

    -- 防幽灵重复注册：内核 l_item_register 没有同名去重，两个 Lua state 或重复加载
    -- 会各注册一个同名物品。注册前先按内部名查 runtime_id，有效就复用。
    local existed = nil
    if mod.item.runtime_id then
        local oke, v = pcall(mod.item.runtime_id, WAND_ITEM.name)
        if oke and type(v) == "number" and v > 0 then existed = v end
    end

    local ok, id
    if existed then
        ok, id = true, existed
        mod.info(string.format("[BW] item %s already registered id=%d, reuse", WAND_ITEM.name, existed))
    else
        ok, id = pcall(mod.item.register, WAND_ITEM)
    end
    -- 注册失败时 api_item.cpp:510-517 是 push nil，不抛错 —— pcall 的 ok 依然是 true，
    -- 所以必须再查返回值本身，否则 S.wand_id 会静默停在 -1，面板永远不出、配方永远不生效。
    if not ok or type(id) ~= "number" then
        S.wand_id = -1
        S.reg_info = "ret=" .. tostring(id)
        mod.error(string.format(
                "[建造魔杖] 物品注册失败（需要 LuaLoader >= 2.1.0-dev）：返回 %s", tostring(id)))
        return
    end
    if id <= 0 then
        -- 理论上是成功回调，但 id 还没分配好；别判成失败，交给 bind_lazy() 用 runtime_id 补
        mod.warn(string.format("[建造魔杖] 注册返回 id=%s，等运行期补 id", tostring(id)))
    end
    S.wand_id = (id > 0) and id or -1
    -- 面板自检行要显示「runtime_id(name) 与注册返回值」两个数：
    -- 注册阶段 runtime_id 常为 -1（api_item.cpp:502），进游戏后才会回填，
    -- 两个数放在一起才能一眼区分「没注册上」和「注册了但 id 还没分配」。
    local rt_name = "?"
    if mod.item.runtime_id then
        local okn, vn = pcall(mod.item.runtime_id, WAND_ITEM.name)
        if okn and type(vn) == "number" then rt_name = tostring(vn) end
    end
    S.reg_info = string.format("%s(%s)", rt_name, tostring(id))
    S.setup_done = true          -- 只有物品注册成功才封口；失败时 on_gui 下一帧还能重试
    -- 配方别只等 SetupRecipes 的 postfix：api_item.cpp:237-246 会跳过 runtime_id<0 的条目，
    -- 若注册晚于那次重建，本轮就再也没有配方了。这里 id 已有效，立刻补一次。
    ensure_recipes()
    -- 注册阶段 runtime_id 通常还是 -1（doc/api.md:364），真正的值要进游戏后读；
    -- 这里只打印出来留档，实时值在 on_gui 的首帧日志里。
    local okr, rid = pcall(mod.item.runtime_id, CFG.WAND_NAME)
    mod.info(string.format("[建筑魔杖] 物品已注册 id=%s runtime=%s recipe_done=%s（注册阶段 -1 属正常）",
            tostring(id), tostring(okr and rid or "err"), tostring(S.recipe_done)))

    pcall(mod.net.on, "place", on_net_place)
    install_recipe_hook()

    mod.info(string.format("[建筑魔杖] 已加载（LuaLoader %s，%s/%s）",
            tostring(mod.version), tostring(mod.platform), tostring(mod.arch)))
end

function mod.cleanup()
    if S.store_dirty then save_store() end
    -- 窗口没了就别再拦点击（否则 rect 留在屏幕上，点哪儿都被吞）
    S.panel_visible = false
    S.panel_rect    = nil
end

todo_list = { setup }
