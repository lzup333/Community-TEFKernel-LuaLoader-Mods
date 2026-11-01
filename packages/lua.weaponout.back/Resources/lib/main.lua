-- ============================================================================
-- 武器背显 (WeaponOutBack) —— LuaLoader 版
-- 移植自 KernelLoader 原生版（包名 eternal.qing.backsword）
-- 协议：MIT License，Copyright (c) 2026 lzup
-- ============================================================================

mod.meta = { pkg_id = "lua.weaponout.back", version = "1.0.1" }

local patch = mod.patch

-- ============================================================================
-- 配置
-- ============================================================================
local CFG = {
    enabled = true,
    only_weapons = true,    -- 只对 damage>0 的物品生效
    local_only = false,     -- 只对本地玩家生效
    offset_x = 0.0,         -- 相对玩家水平中心的偏移（按朝向镜像；0 = 正中）
    offset_y = 0.0,         -- 相对玩家竖直中心的偏移（0 = 正中）
    rotation_deg = 109.0,   -- 背挂角度（原生版约 1.9 rad ≈ 109°）
}

local ROT = CFG.rotation_deg * math.pi / 180.0

-- ============================================================================
-- 句柄
-- ============================================================================
local H = { p = {}, i = {}, m = {}, t = {} }
local hook_handle
local warned_once = false

-- ============================================================================
-- 读取工具
-- ============================================================================
local function fv(field, inst, t)
    if not field then return nil end
    local ok, v = pcall(patch.get_field_value, field, inst, t or "int32")
    if ok then return v end
    return nil
end
local function fbool(field, inst) return fv(field, inst, "bool") end
local function ffloat(field, inst) return fv(field, inst, "float") end
local function fvec2(field, inst)
    if not field then return nil, nil end
    local ok, x, y = pcall(patch.get_field_vec2, field, inst)
    if ok then return x, y end
    return nil, nil
end

local function find_field(type_handle, name)
    local t, guard = type_handle, 0
    while t and guard < 16 do
        local f = patch.get_field(t, name)
        if f then return f end
        t = patch.get_parent(t)
        guard = guard + 1
    end
    return nil
end

local function bind_field(tbl, key, type_handle, name)
    local f = find_field(type_handle, name)
    if f then tbl[key] = f end
    return f ~= nil
end

-- ============================================================================
-- 物品贴图尺寸（缓存）
-- 原版把背挂武器绕"贴图底角"旋转，视觉中心会随朝向偏向左右；
-- 要摆正到玩家中心，需要贴图宽高 W/H 来补偿。
--   W = TextureAssets.Item[type].Value.Width
--   H = TextureAssets.Item[type].Value.Height   （Texture2D.Width/Height 为字段）
-- ============================================================================
local tex_size_cache = {}
local function item_tex_size(itype)
    local c = tex_size_cache[itype]
    if c then return c[1], c[2] end
    if not (H.m.item_tex and H.t.asset_value and H.t.tex_w and H.t.tex_h) then
        return nil, nil
    end
    local ok, w, h = pcall(function()
        local arr = patch.get_field_value(H.m.item_tex, nil, "object")
        if not arr then return nil, nil end
        local asset = patch.array_at(arr, itype)
        if not asset then return nil, nil end
        local tex = patch.get_field_value(H.t.asset_value, asset, "object")
        if not tex then return nil, nil end
        return patch.get_field_value(H.t.tex_w, tex, "int32"),
               patch.get_field_value(H.t.tex_h, tex, "int32")
    end)
    if ok and w and h and w > 0 and h > 0 then
        tex_size_cache[itype] = { w, h }
        return w, h
    end
    return nil, nil
end

-- ============================================================================
-- 每次绘制前/后保存的状态（prefix/postfix 成对，顺序执行，单槽即可）
-- ============================================================================
local S = { on = false, ix = 0, iy = 0, rot = 0, hold = 0 }

-- ============================================================================
-- 诊断
-- ============================================================================
local DIAG = { calls = 0, applied = 0, no_ds = 0, no_obj = 0, anim = 0,
    dead = 0, doll = 0, pulley = 0, hold = 0, notweapon = 0, nolocal = 0,
    wdo = 0, tex_miss = 0, last_type = -1, last_iw = 0, last_ih = 0 }

-- 复用同一套判定：这件物品是否该背挂。返回 ok, hold
local function qualifies(player, item)
    if fbool(H.p.active, player) == false then return false end
    if fbool(H.p.dead, player) == true then DIAG.dead = DIAG.dead + 1; return false end
    if fbool(H.p.doll, player) == true then DIAG.doll = DIAG.doll + 1; return false end
    if fbool(H.p.pulley, player) == true then DIAG.pulley = DIAG.pulley + 1; return false end

    local anim = fv(H.p.itemanim, player) or 0
    if anim ~= 0 then DIAG.anim = DIAG.anim + 1; return false end

    local itype = fv(H.i.type, item) or 0
    DIAG.last_type = itype
    if itype <= 0 then return false end

    -- 已有原生特殊握持的物品不处理（避免冲突）
    local hold = fv(H.i.hold, item, "uint8") or 0
    if hold ~= 0 then DIAG.hold = DIAG.hold + 1; return false end

    if CFG.only_weapons then
        local dmg = fv(H.i.damage, item) or 0
        if dmg <= 0 then DIAG.notweapon = DIAG.notweapon + 1; return false end
    end

    if CFG.local_only then
        local who = fv(H.p.whoami, player)
        local my = fv(H.m.myplayer, nil)
        if who ~= nil and my ~= nil and who ~= my then
            DIAG.nolocal = DIAG.nolocal + 1
            return false
        end
    end
    return true, hold
end

-- ============================================================================
-- 钩子：PlayerDrawSet.BoringSetup postfix
-- 把 weaponDrawOrder 设为 BehindBackArm(0)，让 27 层在身体之前被调用（视觉在背后）
-- ============================================================================
local function bs_post(instance, args, result)
    if not CFG.enabled then return false end
    local ds = instance
    if not ds or not H.f_wdo then return false end
    local player = fv(H.f_draw_player, ds, "object")
    local item = fv(H.f_held_item, ds, "object")
    if player and item and qualifies(player, item) then
        patch.set_field_value(H.f_wdo, ds, 0, "int32") -- WeaponDrawOrder.BehindBackArm
        DIAG.wdo = DIAG.wdo + 1
    end
    return false
end

-- ============================================================================
-- 钩子：DrawPlayer_27_HeldItem prefix
-- ============================================================================
local function pre(instance, args, result)
    if not CFG.enabled then return false end
    DIAG.calls = DIAG.calls + 1
    if DIAG.calls % 240 == 0 then
        mod.info(string.format(
            "diag calls=%d applied=%d wdo=%d noDS=%d noObj=%d anim=%d dead=%d doll=%d pulley=%d hold=%d notweapon=%d nolocal=%d last_type=%d tex_miss=%d iw=%d ih=%d",
            DIAG.calls, DIAG.applied, DIAG.wdo, DIAG.no_ds, DIAG.no_obj, DIAG.anim, DIAG.dead,
            DIAG.doll, DIAG.pulley, DIAG.hold, DIAG.notweapon, DIAG.nolocal, DIAG.last_type,
            DIAG.tex_miss, DIAG.last_iw, DIAG.last_ih))
    end

    local ds = args and args[1]
    if not ds then DIAG.no_ds = DIAG.no_ds + 1; return false end

    local player = fv(H.f_draw_player, ds, "object")
    local item = fv(H.f_held_item, ds, "object")
    if not player or not item then DIAG.no_obj = DIAG.no_obj + 1; return false end

    local ok, hold = qualifies(player, item)
    if not ok then return false end

    -- 保存
    S.ix, S.iy = fvec2(H.f_itemloc, ds)
    S.rot = ffloat(H.p.itemrot, player) or 0.0
    S.hold = hold
    S.on = true

    -- 应用
    -- 原版绕"贴图底角"旋转（朝右=左下角、朝左=右下角），视觉中心会随朝向偏向左右。
    -- 这里按玩家中心求目标位置：pos = 中心 - 旋转后的(贴图中心-底角)，再按朝向镜像。
    local itype = fv(H.i.type, item) or 0
    local px, py = fvec2(H.p.position, player)
    local dir = fv(H.p.direction, player) or 1
    if px then
        local w = fv(H.p.width, player) or 20
        if not w or w <= 0 then w = 20 end
        local h = fv(H.p.height, player) or 42
        if not h or h <= 0 then h = 42 end
        local cx = px + w * 0.5
        local cy = py + h * 0.5

        local dx, dy = 0.0, 0.0
        local iw, ih = item_tex_size(itype)
        if iw then
            local c, s = math.cos(ROT), math.sin(ROT)
            -- 贴图中心相对底角的向量，旋转 ROT 后即为视觉中心相对 ItemLocation 的偏移
            dx = (iw * 0.5) * c + (ih * 0.5) * s
            dy = (iw * 0.5) * s - (ih * 0.5) * c
            DIAG.last_iw, DIAG.last_ih = iw, ih
        else
            DIAG.tex_miss = DIAG.tex_miss + 1
        end

        -- 水平：抵消旋转偏移并按朝向镜像；offset_x 也按朝向镜像
        local x = cx - dir * (dx - CFG.offset_x)
        local y = cy - dy + CFG.offset_y
        patch.set_field_vec2(H.f_itemloc, ds, x, y)
    end
    patch.set_field_value(H.p.itemrot, player, (dir > 0) and ROT or -ROT, "float")
    patch.set_field_value(H.i.hold, item, 1, "uint8")

    DIAG.applied = DIAG.applied + 1
    return false
end

-- ============================================================================
-- 钩子：DrawPlayer_27_HeldItem postfix（还原）
-- ============================================================================
local function post(instance, args, result)
    if not S.on then return false end
    S.on = false
    local ds = args and args[1]
    if not ds then return false end

    local player = fv(H.f_draw_player, ds, "object")
    local item = fv(H.f_held_item, ds, "object")

    if S.ix then pcall(patch.set_field_vec2, H.f_itemloc, ds, S.ix, S.iy) end
    if player then pcall(patch.set_field_value, H.p.itemrot, player, S.rot, "float") end
    if item then pcall(patch.set_field_value, H.i.hold, item, S.hold, "uint8") end
    return false
end

-- ============================================================================
-- 初始化
-- ============================================================================
function setup()
    if mod.platform ~= "android" then
        mod.warn("武器背显：仅支持 Android（需要 field_pointer / 字段读写）")
        return
    end

    local L = patch.get_type("Terraria.DataStructures", "PlayerDrawLayers")
    local DS = patch.get_type("Terraria.DataStructures", "PlayerDrawSet")
    local player_type = patch.get_type("Terraria", "Player")
    local item_type = patch.get_type("Terraria", "Item")
    local main_type = patch.get_type("Terraria", "Main")

    if not (L and DS and player_type and item_type and main_type) then
        mod.error("初始化失败：关键类型未找到 -> PlayerDrawLayers=" .. tostring(L ~= nil)
            .. " PlayerDrawSet=" .. tostring(DS ~= nil)
            .. " Player=" .. tostring(player_type ~= nil)
            .. " Item=" .. tostring(item_type ~= nil)
            .. " Main=" .. tostring(main_type ~= nil))
        return
    end

    -- PlayerDrawSet 字段
    bind_field(H, "f_draw_player", DS, "drawPlayer")
    bind_field(H, "f_itemloc", DS, "ItemLocation")
    bind_field(H, "f_held_item", DS, "heldItem")
    bind_field(H, "f_wdo", DS, "weaponDrawOrder")

    -- Player 字段
    bind_field(H.p, "active", player_type, "active")
    bind_field(H.p, "dead", player_type, "dead")
    bind_field(H.p, "doll", player_type, "isDisplayDollOrInanimate")
    bind_field(H.p, "pulley", player_type, "pulley")
    bind_field(H.p, "itemanim", player_type, "itemAnimation")
    bind_field(H.p, "itemrot", player_type, "itemRotation")
    bind_field(H.p, "position", player_type, "position")
    bind_field(H.p, "width", player_type, "width")
    bind_field(H.p, "height", player_type, "height")
    bind_field(H.p, "direction", player_type, "direction")
    bind_field(H.p, "whoami", player_type, "whoAmI")

    -- Item 字段
    bind_field(H.i, "type", item_type, "type")
    bind_field(H.i, "hold", item_type, "holdStyle")
    bind_field(H.i, "damage", item_type, "damage")

    -- Main 字段
    bind_field(H.m, "myplayer", main_type, "myPlayer")

    -- 贴图尺寸句柄：TextureAssets.Item[type].Value.Width/Height
    local tex_assets = patch.get_type("Terraria.GameContent", "TextureAssets")
    if tex_assets then
        bind_field(H.m, "item_tex", tex_assets, "Item")
    end
    local tex2d = patch.get_type("Microsoft.Xna.Framework.Graphics", "Texture2D")
    if tex2d then
        H.t.tex_w = find_field(tex2d, "Width")
        H.t.tex_h = find_field(tex2d, "Height")
    end
    -- Asset<T> 是泛型，需要构造 Asset<Texture2D> 才能取 Value 字段
    local asset_def = patch.get_type("ReLogic.Content", "Asset`1")
        or patch.get_type("ReLogic.Content", "Asset")
    if asset_def then
        local asset_tex = asset_def
        if tex2d then
            local okg, t = pcall(patch.make_generic_type, asset_def, { tex2d })
            if okg and t then asset_tex = t end
        end
        H.t.asset_value = patch.get_field(asset_tex, "Value")
    end
    if not (H.m.item_tex and H.t.asset_value and H.t.tex_w and H.t.tex_h) then
        mod.warn("贴图尺寸句柄未就绪，背挂武器将无法按贴图尺寸精确居中（会退化为近似居中）")
    end

    if not (H.f_draw_player and H.f_itemloc and H.f_held_item
        and H.p.itemanim and H.p.itemrot and H.p.position and H.i.type and H.i.hold) then
        mod.error("初始化失败：关键字段缺失 -> drawPlayer=" .. tostring(H.f_draw_player ~= nil)
            .. " ItemLocation=" .. tostring(H.f_itemloc ~= nil)
            .. " heldItem=" .. tostring(H.f_held_item ~= nil)
            .. " itemAnimation=" .. tostring(H.p.itemanim ~= nil)
            .. " itemRotation=" .. tostring(H.p.itemrot ~= nil)
            .. " position=" .. tostring(H.p.position ~= nil)
            .. " item.type=" .. tostring(H.i.type ~= nil)
            .. " item.holdStyle=" .. tostring(H.i.hold ~= nil))
        return
    end

    local m27 = patch.get_method(L, "DrawPlayer_27_HeldItem", 1)
    if not m27 then
        mod.error("找不到 PlayerDrawLayers.DrawPlayer_27_HeldItem，模组未启用")
        return
    end

    -- BoringSetup(DrawPlayerSet, ...)：8 参重载，用来把 weaponDrawOrder 改成 BehindBackArm
    local mbs = patch.get_method(DS, "BoringSetup", 8)
    if not mbs then
        mbs = patch.get_method(DS, "BoringSetup")
    end
    if mbs then
        local okb = pcall(patch.install_hook, mbs, { postfix = bs_post })
        if not okb then mod.warn("安装 BoringSetup 钩子失败：背挂可能在人物前面") end
    else
        mod.warn("找不到 PlayerDrawSet.BoringSetup，层级修正未启用（可能画在前面）")
    end

    local ok, err = pcall(patch.install_hook, m27, { prefix = pre, postfix = post })
    if not ok then
        mod.error("安装 DrawPlayer_27_HeldItem 钩子失败：" .. tostring(err))
        return
    end
    hook_handle = err

    mod.info("武器背显已启用（平台：" .. tostring(mod.platform) .. "，钩子：DrawPlayer_27_HeldItem + BoringSetup）")
end

function mod.cleanup()
    if hook_handle and hook_handle.remove then
        pcall(function() hook_handle:remove() end)
        hook_handle = nil
    end
    mod.info("武器背显已卸载")
end

todo_list = { "setup" }
