-- ============================================================================
-- 自动重铸 v1.0.0
--   靠近哥布林工匠时，自动把手持物品和已装备的饰品重铸到顶级词缀。
--
-- 参考实现来源（两个 KernelLoader 原生模组）：
--   NST  ne.ky.nst   —— NPC.FindFirstNPC + Entity.position 距离判定
--                       Main.GetNurseHealCost / NPCChatText_DoNurseHeal
--   RPF  ne.ky.rpf   —— Player.inventory 数组遍历 + Item.Prefix(int)
--
-- 重铸方式与原版 Main.ReforgeItemInReforgeSlot() 完全一致：
--   item.ResetPrefix()          先把属性恢复成基础值（关键！Prefix 是乘算）
--   item.Prefix(-2)             随机滚动词缀，内部带「越好越容易出」的加权
-- 不扣金币、不弹 UI、不进重铸菜单。
-- ============================================================================
local M = {}
mod.meta = { pkg_id = "bluefish.autoreforge", version = "1.2.2", version_code = 122, api_version = 1 }

require("quickapi")
local q     = mod.quickapi
local patch = mod.patch

-- ==================== 默认配置（config.json 缺失时回落） ====================
local DEFAULTS = {
    always_reforge = 1,   -- 一直重铸：不判断达标，见到就刷（默认开）
    charge_coins   = 1,   -- 是否扣钱（默认开）
    range_tiles  = 1000,  -- 触发半径（格），1000 格基本等于全图
    interval     = 1,     -- 每 N 帧处理一件物品
    acc_prefix   = 65,    -- 饰品目标词缀：65=护佑 72=险恶 68=幸运 66=奥秘
    do_weapon    = 0,     -- 是否处理手持物品（always_reforge 开启时此项被忽略）
    do_accessory = 0,     -- 是否处理已装备饰品（同上）
    npc_refresh  = 30,    -- 每 N 帧重新搜索一次哥布林
}

-- ==================== 码表 ====================
-- PrefiID 里各流派的「顶级」词缀
local TOP_WEAPON = {
    [57] = "无情",     -- Ruthless   召唤
    [59] = "神明",     -- Godly      长矛 / 回旋镖 / 链球
    [81] = "传奇",     -- Legendary  剑 / 锤 / 斧 / 镐
    [82] = "不现实",   -- Unreal     枪 / 弓 / 发射器
    [83] = "神话",     -- Mythical   魔法
    [84] = "传奇",     -- Legendary2 悠悠球
}
local ACC_LABEL = { [65] = "护佑", [72] = "险恶", [68] = "幸运", [66] = "奥秘" }

local NPC_GOBLIN = 107   -- NPCID.GoblinTinkerer

-- ==================== 状态 ====================
local S = {
    frame = 0, slot = -1, slot_age = 0, cursor = 0, hooked = nil,
    checked = false, inited = false,
    pay_block = 0, poor = false, pay_err = false, paid_once = false,
}
local cfg = {}
local H = {}

-- ==================== 读数工具 ====================
local function gi(f, inst)
    if not f then return 0 end
    local v = patch.get_field_value(f, inst, "int32")
    if type(v) ~= "number" then v = patch.get_field_value(f, inst, "uint8") end
    if type(v) ~= "number" then return 0 end
    return v
end

local function gb(f, inst)
    if not f then return false end
    return patch.get_field_value(f, inst, "bool") == true
end

local function go(f, inst)
    if not f then return nil end
    return patch.get_field_value(f, inst, "object")
end

-- Item.prefix 是 byte（uint8），字段读取要精确类型，这里逐类型试一次并记住
local prefix_vtype = nil
local function prefix_of(it)
    if not H.prefix then return -1 end
    if prefix_vtype then
        local v = patch.get_field_value(H.prefix, it, prefix_vtype)
        if type(v) == "number" then return v end
        prefix_vtype = nil
    end
    for _, t in ipairs({ "uint8", "int8", "int32" }) do
        local v = patch.get_field_value(H.prefix, it, t)
        if type(v) == "number" then
            prefix_vtype = t
            return v
        end
    end
    return -1
end

local function pos_of(inst)
    if not H.pos then return 0, 0 end
    local x, y = patch.get_field_vec2(H.pos, inst)
    return x or 0, y or 0
end

-- ==================== 配置 ====================
local function load_cfg()
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    local ok, txt = pcall(mod.read_file, "config.json")
    if not ok or type(txt) ~= "string" or #txt == 0 then return end
    for k, def in pairs(DEFAULTS) do
        local v = txt:match('"' .. k .. '"%s*:%s*"?(%d+)')
        local n = tonumber(v)
        if n ~= nil then cfg[k] = n else cfg[k] = def end
    end
end

-- ==================== 句柄绑定 ====================
local function bind()
    local T_MAIN   = q.type("Terraria", "Main")
    local T_PLAYER = q.type("Terraria", "Player")
    local T_ITEM   = q.type("Terraria", "Item")
    local T_NPC    = q.type("Terraria", "NPC")
    local T_ENTITY = q.type("Terraria", "Entity")
    if not (T_MAIN and T_PLAYER and T_ITEM and T_NPC and T_ENTITY) then
        mod.error("[自动重铸] 取不到 Terraria 核心类型")
        return false
    end

    H.npc_arr = q.field("Terraria", "Main", "npc")          -- 静态 NPC[maxNPCs+1]
    H.menu    = q.field("Terraria", "Main", "gameMenu")     -- 静态 bool
    H.pos     = q.field("Terraria", "Entity", "position")   -- Vector2（沿父类链）
    H.inv     = q.field("Terraria", "Player", "inventory")
    H.armor   = q.field("Terraria", "Player", "armor")      -- Item[20]
    H.dead    = q.field("Terraria", "Player", "dead")
    H.discount= q.field("Terraria", "Player", "discountAvailable")
    H.prefix  = q.field("Terraria", "Item", "prefix")       -- byte（uint8）
    H.itype   = q.field("Terraria", "Item", "type")         -- int
    H.value   = q.field("Terraria", "Item", "value")        -- int（含前缀加成）
    H.stack   = q.field("Terraria", "Item", "stack")        -- int

    -- Player.selectedItem 是属性（=> selectedItemState.Selected），不能当字段读
    local prop_sel = q.property("Terraria", "Player", "selectedItem")
    if prop_sel and patch.property_get_method then
        H.m_sel = patch.property_get_method(prop_sel)
    end
    if not H.m_sel then
        H.m_sel = q.method("Terraria", "Player", "get_selectedItem", 0)
    end

    H.m_find  = q.method("Terraria", "NPC", "FindFirstNPC", 1)
    H.m_reset = q.method("Terraria", "Item", "ResetPrefix", 0)
    H.m_prefix= q.method("Terraria", "Item", "Prefix", 1)
    H.m_can   = q.method("Terraria", "Item", "CanHavePrefixes", 0)
    -- Player.BuyItem(long price, int customCurrency)
    -- 注意：C# 写的是 BuyItem(long price, int customCurrency = -1)，
    -- 默认参数在编译期展开，IL2CPP 里**只有一个 2 参方法**，不存在 1 参重载。
    -- 所以必须按 2 个参数取，调用时补上 -1。
    H.m_buy   = q.method("Terraria", "Player", "BuyItem", 2)
    if not H.m_buy then
        H.m_buy = q.method("Terraria", "Player", "BuyItem")   -- 不带 spec 兜底
    end

    local miss = {}
    for _, k in ipairs({ "npc_arr", "pos", "inv", "armor", "m_sel", "dead",
                         "prefix", "itype", "value", "stack", "m_find", "m_reset", "m_prefix" }) do
        if not H[k] then miss[#miss + 1] = k end
    end
    if #miss > 0 then
        mod.error("[自动重铸] 关键句柄缺失: " .. table.concat(miss, ", "))
        return false
    end
    if not H.m_can then
        mod.warn("[自动重铸] 取不到 Item.CanHavePrefixes，将不做可重铸性预判")
    end
    if not H.m_buy then
        mod.error("[自动重铸] 取不到 Player.BuyItem，重铸将不扣钱")
    else
        local nargs = patch.method_param_count and patch.method_param_count(H.m_buy) or -1
        pcall(mod.info, "[自动重铸] BuyItem 已绑定（参数个数 " .. tostring(nargs) .. "）")
    end
    return true
end

-- ==================== 扣钱 ====================
-- 原版价格公式（Main.cs 重铸按钮处）：
--   price = (long)item.value * item.stack
--   if (player.discountAvailable) price = price * 0.8
--   price = price * player.currentShoppingSettings.PriceAdjustment   -- 幸福度，这里按 1.0 算
--   price /= 3
--   if (price < 1) price = 1
-- 然后 player.BuyItem(price)：从背包 + 猪猪/保险库扣币，钱不够返回 false
local function price_of(player, it)
    local v = gi(H.value, it)
    local st = gi(H.stack, it)
    if v <= 0 then v = 1 end
    if st < 1 then st = 1 end
    local p = v * st
    if gb(H.discount, player) then p = p * 0.8 end      -- 快乐值折扣（原版 discountAvailable）
    p = math.floor(p / 3)
    if p < 1 then p = 1 end
    return p
end

local function pay(player, it)
    if cfg.charge_coins ~= 1 then return true end   -- 扣钱开关关闭 → 免费重铸
    if not H.m_buy then return true end             -- 取不到方法就退化为免费（bind 已打 error）
    local price = price_of(player, it)
    -- BuyItem(long price, int customCurrency)，第二参 -1 表示用普通金币
    local ok, res = pcall(q.call, H.m_buy, player, price, -1)
    if not ok then
        if not S.pay_err then
            S.pay_err = true
            pcall(mod.warn, "[自动重铸] Player.BuyItem 调用失败，本次放行不扣钱：" .. tostring(res))
        end
        return true
    end
    if res ~= true then
        if not S.poor then
            S.poor = true
            pcall(mod.info, "[自动重铸] 金币不足，暂停重铸 1 秒（本次报价 " .. tostring(price) .. " 铜）")
        end
        return false
    end
    if not S.paid_once then
        S.paid_once = true
        pcall(mod.info, string.format("[自动重铸] 扣钱生效：本次花费 %d 铜（物品价值 %d）",
            price, gi(H.value, it)))
    end
    S.poor = false
    return true
end

-- ==================== 单件重铸 ====================
-- 与原版 Main.ReforgeItemInReforgeSlot() 同序：
--   ResetPrefix() 把 damage/crit/useTime 等恢复基准，再 Prefix(-2) 重新乘算
local function reforge(it)
    pcall(q.call, H.m_reset, it)
    local ok = pcall(q.call, H.m_prefix, it, -2)
    return ok
end

local function is_done(it, is_acc)
    local p = prefix_of(it)
    if p <= 0 then return false end
    if is_acc then
        return p == cfg.acc_prefix
    end
    return TOP_WEAPON[p] ~= nil
end

-- ==================== 候选收集 ====================
-- always_reforge = 1 时无视 do_weapon / do_accessory，手持 + 全部饰品都收
-- always_reforge = 0 时按两个开关走，且刷到达标就停
local function collect(player)
    local list = {}
    local want_weapon = (cfg.always_reforge == 1) or (cfg.do_weapon == 1)
    local want_acc    = (cfg.always_reforge == 1) or (cfg.do_accessory == 1)

    if want_weapon then
        local inv = go(H.inv, player)
        if inv then
            local oks, sel = pcall(q.call, H.m_sel, player)
            if not oks or type(sel) ~= "number" then sel = 0 end
            if sel < 0 or sel > 9 then sel = 0 end
            local it = patch.array_at(inv, sel)
            if it and gi(H.itype, it) > 0 then
                list[#list + 1] = { it = it, acc = false }
            end
        end
    end
    if want_acc then
        local ar = go(H.armor, player)
        if ar then
            -- armor[0..2] 是头/身/腿，[3..19] 是饰品槽（含大师/恶魔之心扩展槽）
            for i = 3, 19 do
                local it = patch.array_at(ar, i)
                if it and gi(H.itype, it) > 0 then
                    list[#list + 1] = { it = it, acc = true }
                end
            end
        end
    end
    return list
end

-- ==================== 主循环 ====================
local function tick(player)
    S.frame = S.frame + 1
    if not player or not H.npc_arr then return end
    if S.frame % cfg.interval ~= 0 then return end
    if S.frame < S.pay_block then return end      -- 金币不足后的冷却

    if gb(H.menu, nil) then return end          -- 主菜单
    if gb(H.dead, player) then return end       -- 死亡中

    -- 搜索哥布林（带缓存，避免每帧调一次）
    S.slot_age = S.slot_age - cfg.interval
    if S.slot_age <= 0 then
        S.slot_age = cfg.npc_refresh
        local ok, res = pcall(q.call, H.m_find, NPC_GOBLIN)
        if ok and type(res) == "number" then
            S.slot = res
        else
            S.slot = -1
        end
    end
    if S.slot < 0 then return end

    -- 首次进图打一行诊断，方便确认各句柄是否真的可用
    if not S.checked then
        S.checked = true
        local _, sel = pcall(q.call, H.m_sel, player)
        mod.info(string.format("[自动重铸] 就绪：哥布林槽=%d / 手持槽=%s / prefix类型=%s / 可重铸预判=%s",
            S.slot, tostring(sel), tostring(prefix_vtype), H.m_can and "有" or "无"))
    end

    local arr = go(H.npc_arr, nil)
    if not arr then return end
    local npc = patch.array_at(arr, S.slot)
    if not npc then return end

    -- 距离判定（格 → 像素，比较平方，免开方）
    local px, py = pos_of(player)
    local nx, ny = pos_of(npc)
    local dx, dy = nx - px, ny - py
    local lim = cfg.range_tiles * 16
    if dx * dx + dy * dy > lim * lim then return end

    -- 候选与轮询
    local list = collect(player)
    if #list == 0 then return end
    S.cursor = S.cursor + 1
    if S.cursor > #list then S.cursor = 1 end
    local c = list[S.cursor]

    -- 一直重铸模式下不判断达标，见到就刷
    if cfg.always_reforge ~= 1 and is_done(c.it, c.acc) then return end

    if H.m_can then
        local okc, can = pcall(q.call, H.m_can, c.it)
        if not okc or can ~= true then return end
    end

    -- 先扣钱后重铸，和原版按钮一致（BuyItem 返回 false 就不刷）
    if not pay(player, c.it) then
        S.pay_block = S.frame + 60      -- 金币不足，停 1 秒再试
        return
    end

    reforge(c.it)
end

-- ==================== 生命周期 ====================
function M.setup()
    if S.inited then return end
    S.inited = true
    load_cfg()
    if not bind() then return end
    S.hooked = q.install_hook_postfix("Terraria", "Player", "Update",
        function(player) pcall(tick, player) end, { argc = 1 })
    if not S.hooked then
        mod.error("[自动重铸] Player.Update 钩子安装失败")
        return
    end
    mod.info(string.format("[自动重铸] v1.2.2 已加载（半径 %d 格 / 间隔 %d 帧 / 扣钱 %s / 饰品目标 %s）",
        cfg.range_tiles, cfg.interval,
        cfg.charge_coins == 1 and "开" or "关",
        ACC_LABEL[cfg.acc_prefix] or tostring(cfg.acc_prefix)))
end

function M.cleanup()
    if S.hooked then
        pcall(function() S.hooked:remove() end)
        S.hooked = nil
    end
    S.frame, S.slot, S.slot_age, S.cursor = 0, -1, 0, 0
    S.inited = false
end

-- ==================== 入口注册 ====================
-- LuaLoader 3.x 只调用三个全局名：init / cleanup / on_gui，
-- 或者按全局 todo_list 里列出的函数名依次调用。
-- 只写 M.setup 是不够的：脚本会被执行（日志照样显示 Initialized），
-- 但初始化函数永远不会被触发，于是什么钩子都装不上。
local entry_inited = false

function setup()
    if entry_inited then return end
    entry_inited = true
    local ok, err = pcall(M.setup)
    if not ok then pcall(mod.error, "[自动重铸] setup 异常：" .. tostring(err)) end
end

function cleanup()
    local ok, err = pcall(M.cleanup)
    if not ok then pcall(mod.warn, "[自动重铸] cleanup 异常：" .. tostring(err)) end
end

-- 老式 mod.init / mod.cleanup 写法也挂上（幂等保护会挡住重复执行）
if type(mod) == "table" then
    function mod.init() setup() end
    function mod.cleanup() cleanup() end
end

todo_list = { "setup" }

return M
