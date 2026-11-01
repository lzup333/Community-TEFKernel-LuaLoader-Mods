-- ============================================================================
-- 纯 Lua 绘制桥 —— 依赖面与「Buff显示 v1.2.4」一致
--
--   只用：get_type / get_field / get_method / get_method_by_param_types /
--   make_generic_type / new_instance / field_pointer / mem_write_values /
--   set_field_vec2 / set_field_raw / invoke / array_at / GCHandle。
--   ★ 不用 get_method_by_names、不用 construct、不创建 Unity 对象、不读文件。
--
--   new(p, diag) 的 diag 是诊断回调：每一步都会调用一次，
--   便于崩溃后从项目文件夹里的残血提示_diag.txt 看出炸在哪一行。
-- ============================================================================
local B = {}

-- Color 内存布局是 ABGR（A,B,G,R），见 Microsoft.Xna.Framework.Graphics/Color.cs
local WHITE = string.char(255, 255, 255, 255)

function B.new(p, diag)
    diag = diag or function() end
    local self = { p = p, buff_load_tried = {} }

    local function typ(ns, n)
        diag('类型 ' .. ns .. '.' .. n)
        return assert(p.get_type(ns, n), '缺少类型 ' .. tostring(ns) .. '.' .. n)
    end
    local function field(t, n)
        diag('字段 ' .. n)
        return assert(p.get_field(t, n), '缺少字段 ' .. n)
    end
    local function method(t, n, c)
        diag('方法 ' .. n)
        return assert(p.get_method(t, n, c), '缺少方法 ' .. n)
    end

    self.main = typ('Terraria', 'Main')
    self.player = typ('Terraria', 'Player')
    local sb = typ('Microsoft.Xna.Framework.Graphics', 'SpriteBatch')
    local tx = typ('Microsoft.Xna.Framework.Graphics', 'Texture2D')
    local rect_t = typ('Microsoft.Xna.Framework', 'Rectangle')
    local vec_t = typ('Microsoft.Xna.Framework', 'Vector2')
    local color_t = typ('Microsoft.Xna.Framework.Graphics', 'Color')
    local assets = typ('Terraria.GameContent', 'TextureAssets')
    local state_t = typ('', 'LocalUserGameState')
    local user_t = typ('', 'LocalUser')
    local npc_t = typ('Terraria', 'NPC')
    local ct_t = typ('Terraria', 'CombatText')
    local users_t = typ('', 'UserManagement')
    local gc = typ('System.Runtime.InteropServices', 'GCHandle')
    local generic = typ('ReLogic.Content', 'Asset`1')

    -- ---- 绘制入口与批次 ----
    self.draw_npcs = method(self.main, 'DrawNPCs', 1)
    diag('解析 Draw 重载')
    self.draw = assert(p.get_method_by_param_types(sb, 'Draw', { tx, vec_t, rect_t, color_t }),
        '找不到 Draw 重载')
    self.batch_begun = field(sb, '_beginCalled')

    -- ---- 屏幕 / 玩家 / 相机 ----
    -- 真正的分辨率在 LocalUserGameState 上是普通字段
    -- （Main.screenWidth 是属性，get_field 取不到，v1.5.1 实测）
    diag('字段 GameState.screenWidth')
    self.gs_w = field(state_t, 'screenWidth')
    diag('字段 GameState.screenHeight')
    self.gs_h = field(state_t, 'screenHeight')
    self.sprite_batch = field(self.main, 'spriteBatch')
    self.players = field(self.main, 'player')
    self.active_user = field(user_t, 'Active')
    self.primary_user = field(users_t, 'PrimaryPlayer')
    self.user_state = field(user_t, 'GameState')
    self.gs_menu = field(state_t, 'gameMenu')
    self.my_player = field(state_t, 'myPlayer')
    self.camera = field(state_t, 'screenPosition')

    self.p_pos = field(self.player, 'position')
    self.p_w = field(self.player, 'width')
    self.p_active = field(self.player, 'active')
    self.p_dead = field(self.player, 'dead')
    self.p_buff = field(self.player, 'buffType')
    self.p_buff_time = field(self.player, 'buffTime')

    -- 血量字段单独容错：拿不到就退化（不因此让整个模块失败）
    diag('字段 statLife')
    self.p_life = p.get_field(self.player, 'statLife')
    diag('字段 statLifeMax2')
    self.p_life_max = p.get_field(self.player, 'statLifeMax2')

    self.pixel_asset = field(assets, 'MagicPixel')
    self.buff_assets = field(assets, 'Buff')
    diag('方法 LoadBuff')
    self.load_buff = p.get_method(self.main, 'LoadBuff', 1)
    self.tex_w = field(tx, 'Width')
    self.tex_h = field(tx, 'Height')
    diag('make_generic_type')
    self.asset_value = field(p.make_generic_type(generic, { tx }), 'Value')

    -- 真实时间（秒）：用于让动画与帧率无关。取不到就退 os.clock
    diag('时间源 Time.unscaledTime')
    do
        local ok_t, time_t = pcall(p.get_type, 'UnityEngine', 'Time')
        if ok_t and time_t then
            local ok_p, prop = pcall(p.get_property, time_t, 'unscaledTime')
            if ok_p and prop then
                local ok_m, m = pcall(p.property_get_method, prop)
                if ok_m and m then self.time_getter = m end
            end
        end
    end

    -- ---- GC 保活 ----
    self.gc_alloc = method(gc, 'GetTargetHandle', 3)
    self.gc_target = method(gc, 'GetTarget', 1)
    self.gc_free = method(gc, 'FreeHandle', 1)

    -- ---- position / color 缓冲：一个 CombatText 实例 ----
    diag('new_instance CombatText')
    self.ct_scratch = assert(p.new_instance(ct_t), '无法分配绘制缓冲')
    diag('GCHandle 保活 CombatText')
    self.ct_root = assert(p.invoke(self.gc_alloc, self.ct_scratch, nil, 2), 'GCHandle 保活失败')
    self.pos_field = field(ct_t, 'position')
    self.col_field = field(ct_t, 'color')
    diag('field_pointer position')
    self.pos_ptr = assert(p.field_pointer(self.pos_field, self.ct_scratch), '字段地址接口不可用')
    diag('field_pointer color')
    self.col_ptr = assert(p.field_pointer(self.col_field, self.ct_scratch), '字段地址接口不可用')

    -- ---- srcRect 缓冲：一个保活 NPC 实例的 Rectangle 字段 ----
    diag('new_instance NPC')
    self.npc_scratch = assert(p.new_instance(npc_t), '无法分配矩形缓冲')
    diag('GCHandle 保活 NPC')
    self.npc_root = assert(p.invoke(self.gc_alloc, self.npc_scratch, nil, 2), 'GCHandle 保活失败')
    local rect_how
    for _, nm in ipairs({ 'frame', 'targetRect' }) do
        diag('field_pointer ' .. nm)
        local f = p.get_field(npc_t, nm)
        if f then
            local okp, ptr = pcall(p.field_pointer, f, self.npc_scratch)
            if okp and ptr then
                self.rect_ptr, rect_how = ptr, nm
                break
            end
        end
    end
    assert(self.rect_ptr, '矩形缓冲不可用')
    self.rect_how = rect_how
    diag('hud 初始化完成 矩形缓冲=' .. tostring(rect_how))

    return setmetatable(self, { __index = B })
end

function B:read(f, inst, ty)
    if not f then return nil end
    local ok, v = pcall(self.p.get_field_value, f, inst, ty)
    if ok then return v end
    return nil
end

function B:vec2(f, inst)
    local ok, x, y = pcall(self.p.get_field_vec2, f, inst)
    if ok then return x, y end
    return nil, nil
end

function B:state()
    local user = self:read(self.active_user, nil, 'object')
    if not user then user = self:read(self.primary_user, nil, 'object') end
    if not user then return nil end
    return self:read(self.user_state, user, 'object')
end

function B:local_player(gs)
    if not gs then return nil end
    local idx = self:read(self.my_player, gs, 'int32')
    if type(idx) ~= 'number' or idx < 0 or idx > 254 then return nil end
    local arr = self:read(self.players, nil, 'object')
    if not arr then return nil end
    local ok, pl = pcall(self.p.array_at, arr, idx, 'object')
    if not ok or not pl then return nil end
    local cx, cy = self:vec2(self.camera, gs)
    return pl, cx, cy
end

-- 返回单调递增的秒数；优先 Unity 真实时间，失败退回 CPU 时钟
function B:now()
    if self.time_getter then
        local ok, v = pcall(self.p.invoke, self.time_getter)
        if ok and type(v) == 'number' then return v end
    end
    return os.clock()
end

function B:dimensions(gs)
    local w = self:read(self.gs_w, gs, 'int32')
    local h = self:read(self.gs_h, gs, 'int32')
    if type(w) ~= 'number' or w <= 0 then w = 1920 end
    if type(h) ~= 'number' or h <= 0 then h = 1080 end
    return w, h
end

function B:magic_pixel()
    local asset = self:read(self.pixel_asset, nil, 'object')
    if not asset then return nil end
    return self:read(self.asset_value, asset, 'object')
end

function B:asset_tex(asset)
    if not asset then return nil end
    return self:read(self.asset_value, asset, 'object')
end

function B:buff_texture(id)
    local arr = self:read(self.buff_assets, nil, 'object')
    if not arr then return nil end
    local ok, asset = pcall(self.p.array_at, arr, id, 'object')
    if not ok or not asset then return nil end
    local tex = self:asset_tex(asset)
    if tex then return tex end
    if self.load_buff and not self.buff_load_tried[id] then
        self.buff_load_tried[id] = true
        pcall(self.p.invoke, self.load_buff, id)
        return self:asset_tex(asset)
    end
    return nil
end

function B:tex_size(tex)
    return self:read(self.tex_w, tex, 'int32') or 0, self:read(self.tex_h, tex, 'int32') or 0
end

function B:begin_frame()
    local ok, obj = pcall(self.p.invoke, self.gc_target, self.ct_root)
    if ok and obj and obj ~= false then
        self.cur = obj
        return true
    end
    self.cur = nil
    return false
end

-- Draw(Texture2D, Vector2 position, Rectangle? srcRect, Color)
function B:draw_tex(batch, texture, x, y, w, h, color_raw)
    if not texture or not self.cur then return false end
    w = math.floor(w + 0.5)
    h = math.floor(h + 0.5)
    if w <= 0 or h <= 0 then return false end
    -- srcRect 恒为 {0,0,w,h}，w/h 没变就不用重复写内存
    if self.rw ~= w or self.rh ~= h then
        self.p.mem_write_values(self.rect_ptr, 0, { 0, 0, w, h }, 'int32')
        self.rw, self.rh = w, h
    end
    self.p.set_field_vec2(self.pos_field, self.cur, x, y)
    self.p.set_field_raw(self.col_field, self.cur, color_raw or WHITE)
    local r = self.p.invoke(self.draw, batch, texture, self.pos_ptr, self.rect_ptr, self.col_ptr)
    return r ~= false
end

function B:cleanup()
    for _, root in ipairs({ self.ct_root, self.npc_root }) do
        if root then pcall(function() self.p.invoke(self.gc_free, root) end) end
    end
end

B.WHITE = WHITE
return B