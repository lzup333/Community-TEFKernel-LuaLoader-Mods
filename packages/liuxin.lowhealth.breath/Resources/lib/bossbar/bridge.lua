-- 唯一的游戏接口层：仅解析已核对的 Android 1.4.5.8 类型与签名。
-- LuaLoader 3.x：不再使用原生模块；结构体调用走 mod.patch.struct_arg + invoke_value_args。
local B = {}

local function identity_arg(p)
    local fields = {"bool"}
    local values = {true}
    local m = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1} -- Matrix identity
    for i = 1, 16 do
        fields[#fields + 1] = "float"
        values[#values + 1] = m[i]
    end
    return p.struct_arg(fields, values)
end

function B.new(p)
    local self = {p = p, npc_names = {}}
    local function typ(ns, n)
        return assert(p.get_type(ns, n), '缺少类型 ' .. ns .. '.' .. n)
    end
    local function method(t, n, c)
        return assert(p.get_method(t, n, c), '缺少方法 ' .. n)
    end
    local function field(t, n)
        return assert(p.get_field(t, n), '缺少字段 ' .. n)
    end
    local function getter(t, n)
        return assert(p.property_get_method(assert(p.get_property(t, n), '缺少属性 ' .. n)), n)
    end

    self.main = typ('Terraria', 'Main')
    self.npc = typ('Terraria', 'NPC')
    self.system = typ('Terraria.GameContent.UI.BigProgressBar', 'BigProgressBarSystem')
    self.mobile = typ('', 'GUIBossBar')
    local sb = typ('Microsoft.Xna.Framework.Graphics', 'SpriteBatch')
    self.draw_main = method(self.main, 'Draw', 1)
    self.batch_begun = field(sb, '_beginCalled')
    self.force_scale = field(sb, 'forceDrawScale')
    self.begin8 = assert(p.get_method_by_names(sb, 'Begin',
        {'sortMode', 'blendState', 'samplerState', 'depthStencilState', 'rasterizerState', 'effect', 'transformMatrix',
         'defferedBatch'}), '缺少界面绘制 Begin 重载')
    self.batch_end = method(sb, 'End', 0)
    self.setup_ui = method(typ('', 'XNAUnityRunner'), 'SetupRenderingUI', 1)
    assert(p.method_is_static(self.setup_ui), 'SetupRenderingUI 必须为静态方法')

    self.ut = typ('UnityEngine', 'Texture2D')
    self.xt = typ('Microsoft.Xna.Framework.Graphics', 'Texture2D')
    local ub = typ('UnityEngine', 'Texture')
    self.screen_width = getter(self.main, 'screenWidth')
    self.screen_height = getter(self.main, 'screenHeight')
    self.time = getter(typ('UnityEngine', 'Time'), 'unscaledTime')
    self.npcs = field(self.main, 'npc')
    self.sprite_batch = field(self.main, 'spriteBatch')
    self.progress = getter(self.main, 'BigBossProgressBar')
    self.info = field(self.system, '_info')
    self.npc_type = field(self.npc, 'type')
    self.active = field(self.npc, 'active')
    self.life = field(self.npc, 'life')
    self.life_max = field(self.npc, 'lifeMax')
    self.invulnerable = field(self.npc, 'dontTakeDamage')
    self.npc_ai = field(self.npc, 'ai')
    self.boss_head = method(self.npc, 'GetBossHeadTextureIndex', 0)

    -- 头像资源由游戏的静态 Asset 数组持有；未就绪时只显示名称。
    if type(p.make_generic_type) == 'function' then
        pcall(function()
            local asset = p.make_generic_type(typ('ReLogic.Content', 'Asset`1'), {self.xt})
            self.head_value = field(asset, 'Value')
            self.head_assets = field(typ('Terraria.GameContent', 'TextureAssets'), 'NpcHeadBoss')
        end)
    end

    self.name = getter(self.npc, 'FullName')
    self.tex_width = field(self.xt, 'Width')
    self.tex_height = field(self.xt, 'Height')
    self.read_bytes = method(typ('System.IO', 'File'), 'ReadAllBytes', 1)
    self.load_png = method(typ('UnityEngine', 'ImageConversion'), 'LoadImage', 3)
    self.unity_ctor = assert(p.get_method_by_names(self.ut, '.ctor', {'width', 'height', 'textureFormat', 'mipChain'}),
        '缺少 RGBA32 构造函数')
    self.xna_ctor = assert(p.get_method_by_param_types(self.xt, '.ctor', {self.ut}), '缺少 XNA 纹理封装')
    self.filter = method(ub, 'set_filterMode', 1)
    self.wrap = method(ub, 'set_wrapMode', 1)
    self.destroy = method(typ('UnityEngine', 'Object'), 'Destroy', 1)

    -- 使用 LuaLoader gui_images.cpp 相同的 SpriteBatch.Draw 引用矩形重载。
    local rect = typ('Microsoft.Xna.Framework', 'Rectangle')
    local vec = typ('Microsoft.Xna.Framework', 'Vector2')
    local color = typ('Microsoft.Xna.Framework.Graphics', 'Color')
    local float = p.get_basic_type('float')
    local effects = typ('Microsoft.Xna.Framework.Graphics', 'SpriteEffects')
    self.draw = assert(p.get_method_by_signature(sb, 'Draw', {self.xt, vec, rect, color, float, vec, vec, effects, float},
        {'texture', 'position', 'srcRect', 'color', 'rotation', 'origin', 'scale', 'effects', 'layerDepth'}),
        '缺少 GUI SpriteBatch.Draw 重载')
    self.text = method(typ('Terraria', 'Utils'), 'DrawBorderString', 8)
    self.draw_mobile = method(self.mobile, 'Draw', 6)

    -- 复用结构体参数，避免每帧重复分配（struct_arg_set 原地更新）。
    self.identity = identity_arg(p)
    self.arg_pos = p.struct_arg({'float', 'float'}, {0, 0})
    self.arg_rect = p.struct_arg({'int32', 'int32', 'int32', 'int32'}, {0, 0, 0, 0})
    self.arg_color = p.struct_arg({'uint8', 'uint8', 'uint8', 'uint8'}, {255, 255, 255, 255})
    self.arg_zero = p.struct_arg({'float', 'float'}, {0, 0})
    self.arg_scale = p.struct_arg({'float', 'float'}, {1, 1})
    self.arg_vec = p.struct_arg({'float', 'float'}, {0, 0})
    return setmetatable(self, {__index = B})
end

function B:call(m, ...)
    local label = self.p.method_name and self.p.method_name(m) or tostring(m)
    if self.trace then self.trace('invoke begin: ' .. label) end
    -- 当前 LuaLoader 的 invoke 对引用参数仅调用 to_handle，Lua string 会变 nil。
    -- 保留显式 nil 参数槽位（例如托管方法需要 null 参数）。
    local args = table.pack(...)
    for i = 1, args.n do
        if type(args[i]) == 'string' then
            args[i] = assert(self.p.string_create(args[i]), '托管字符串创建失败')
        end
    end
    local r = self.p.invoke(m, table.unpack(args, 1, args.n))
    if self.trace then self.trace('invoke end: ' .. label) end
    if r == false then error('托管调用失败') end
    return r
end

function B:construct(m, ...)
    if self.trace then self.trace('construct begin') end
    local obj = self.p.construct(m, ...)
    if self.trace then self.trace('construct end') end
    return obj
end

function B:color(r, g, b, a)
    -- Android Graphics.Color 的字节顺序为 A,B,G,R；传递整数给 Lua API。
    return (a or 255) | (b << 8) | (g << 16) | (r << 24)
end

function B:set_color(arg, packed)
    local p = self.p
    p.struct_arg_set(arg, 1, packed & 0xFF)
    p.struct_arg_set(arg, 2, (packed >> 8) & 0xFF)
    p.struct_arg_set(arg, 3, (packed >> 16) & 0xFF)
    p.struct_arg_set(arg, 4, (packed >> 24) & 0xFF)
end

--- 为托管对象建立 GC 强引用（LuaLoader 3.x 的 patchlib object_root）。
function B:root(obj)
    if not obj then return nil end
    return self.p.object_root(obj)
end

function B:unroot(root)
    if root then self.p.object_unroot(root) end
end

function B:dimensions()
    return self:call(self.screen_width), self:call(self.screen_height)
end

function B:begin_hud(sb)
    assert(not self.p.get_field_value(self.batch_begun, sb, 'bool'), '游戏绘制批次尚未结束，保留原版血条')
    self.saved_force_scale = self.p.get_field_value(self.force_scale, nil, 'bool')
    self.p.set_field_value(self.force_scale, nil, false, 'bool')
    -- PE 的界面队列需要显式启用；仅 Begin/End 返回不代表内容进入界面渲染。
    local ok, err = pcall(function()
        self:call(self.setup_ui, true)
        if self.trace then self.trace('HUD Begin via invoke_value_args; UI rendering enabled') end
        local r = self.p.invoke_value_args(self.begin8, sb,
            {0, nil, nil, nil, nil, nil, self.identity, true})
        assert(r ~= false, 'HUD Begin 失败')
    end)
    if not ok then
        pcall(self.call, self, self.setup_ui, false)
        self.p.set_field_value(self.force_scale, nil, self.saved_force_scale, 'bool')
        error(err)
    end
end

function B:end_hud(sb)
    local ok, err = pcall(self.call, self, self.batch_end, sb)
    local restored, restore_err = pcall(self.call, self, self.setup_ui, false)
    self.p.set_field_value(self.force_scale, nil, self.saved_force_scale or false, 'bool')
    if not ok then error(err) end
    if not restored then error(restore_err) end
    if self.trace then self.trace('HUD End submitted; UI rendering restored') end
end

function B:tracking(instance)
    local p = self.p
    if self.trace then self.trace('tracking info read begin') end
    local raw = p.get_field_raw(self.info, instance, 8)
    if not raw or #raw < 8 then return nil end
    local index = string.unpack('<i4', raw)
    if self.trace then self.trace('tracking npc lookup begin') end
    local arr = p.get_field_value(self.npcs, nil, 'object')
    if not arr or index < 0 or index >= p.array_length(arr) then return nil end
    local npc = p.array_at(arr, index)
    if not npc or not p.get_field_value(self.active, npc, 'bool') then return nil end
    local id = p.get_field_value(self.npc_type, npc, 'int32')
    local name = p.string_value(self:call(self.name, npc))
    return {key = tostring(index) .. ':' .. tostring(id), name = name or 'Boss', index = index, type = id}
end

function B:snapshot(max)
    if self.trace then self.trace('snapshot spriteBatch read begin') end
    local sb = self.p.get_field_value(self.sprite_batch, nil, 'object')
    if not sb then return nil end
    local progress = self:call(self.progress)
    local track
    if progress then
        local ok, value = pcall(self.tracking, self, progress)
        if ok then track = value end
    end
    -- 手机绘制入口已给出正确血量，姓名信息未就绪时仍显示血条。
    return sb, track or {key = 'mobile:' .. tostring(max), name = 'Boss'}
end

function B:npc_icon(npc)
    if not self.head_assets or not self.head_value then return nil end
    local p = self.p
    local index = self:call(self.boss_head, npc)
    if type(index) ~= 'number' or index < 0 then return nil end
    local arr = p.get_field_value(self.head_assets, nil, 'object')
    if not arr or index >= p.array_length(arr) then return nil end
    local asset = p.array_at(arr, index)
    return asset and p.get_field_value(self.head_value, asset, 'object') or nil
end

function B:scan_npcs(wanted, with_icons)
    local p = self.p
    local arr = p.get_field_value(self.npcs, nil, 'object')
    if not arr then return {} end
    local result = {}
    -- 仅多部位 Boss 调用一次扫描；不在所有 Boss 帧中扫描或逐个加载贴图。
    for index = 0, p.array_length(arr) - 1 do
        local npc = p.array_at(arr, index)
        if npc and p.get_field_value(self.active, npc, 'bool') then
            local id = p.get_field_value(self.npc_type, npc, 'int32')
            if wanted[id] then
                local life = p.get_field_value(self.life, npc, 'int32')
                local max = p.get_field_value(self.life_max, npc, 'int32')
                if life and max and life > 0 and max > 0 then
                    local entry = {index = index, type = id, key = index .. ':' .. id, life = life, max = max,
                        locked = p.get_field_value(self.invulnerable, npc, 'bool')}
                    if id == 396 or id == 397 then
                        local ai = p.get_field_value(self.npc_ai, npc, 'object')
                        if ai and p.array_length(ai) > 0 then entry.ai0 = p.array_at(ai, 0, 'float') end
                    end
                    if with_icons then
                        if not self.npc_names[id] then
                            self.npc_names[id] = p.string_value(self:call(self.name, npc)) or 'Boss'
                        end
                        entry.name = self.npc_names[id]
                        local ok, icon = pcall(self.npc_icon, self, npc)
                        if ok then entry.icon = icon end
                    end
                    result[#result + 1] = entry
                end
            end
        end
    end
    return result
end

-- 所有结构体在 Lua 侧组装；Lua 只传数字和对象句柄。
function B:source(x, y, w, h) return {x = x, y = y, w = w, h = h} end

function B:draw_sprite(sb, tex, x, y, w, h, src, color)
    if w <= 0 or h <= 0 or src.w <= 0 or src.h <= 0 then return end
    if self.trace then self.trace('SpriteBatch.Draw via invoke_value_args begin') end
    local p = self.p
    p.struct_arg_set(self.arg_pos, 1, x)
    p.struct_arg_set(self.arg_pos, 2, y)
    p.struct_arg_set(self.arg_rect, 1, src.x)
    p.struct_arg_set(self.arg_rect, 2, src.y)
    p.struct_arg_set(self.arg_rect, 3, src.w)
    p.struct_arg_set(self.arg_rect, 4, src.h)
    self:set_color(self.arg_color, color)
    p.struct_arg_set(self.arg_scale, 1, w / src.w)
    p.struct_arg_set(self.arg_scale, 2, h / src.h)
    local ok = p.invoke_value_args(self.draw, sb,
        {tex, self.arg_pos, self.arg_rect, self.arg_color, 0, self.arg_zero, self.arg_scale, 0, 0})
    assert(ok ~= false, '原生贴图绘制失败')
    if self.trace then self.trace('SpriteBatch.Draw via invoke_value_args end') end
end

function B:draw_text(sb, text, x, y, color, scale, anchor)
    local p = self.p
    local managed = assert(p.string_create(text), '无法创建绘制文字')
    local width = 0
    for _, cp in utf8.codes(text) do width = width + (cp >= 0x2E80 and 28 or cp == 32 and 8 or 14) end
    if self.trace then self.trace('DrawBorderString via invoke_value_args begin') end
    p.struct_arg_set(self.arg_pos, 1, x - width * scale * (anchor or 0))
    p.struct_arg_set(self.arg_pos, 2, y)
    self:set_color(self.arg_color, color)
    local ok = p.invoke_value_args(self.text, {sb, managed, self.arg_pos, self.arg_color, scale, 0, 0, -1})
    assert(ok ~= false, '原生文字绘制失败')
    if self.trace then self.trace('DrawBorderString via invoke_value_args end') end
end

--- 把 Unity 屏幕坐标转成界面坐标；返回 x, y（结构体返回值是原始字节）。
--- 注意：不要命名为 adjust_ui，Mod 常把方法句柄存到 self.adjust_ui 上。
function B:adjust_screen(m, x, y)
    local p = self.p
    p.struct_arg_set(self.arg_vec, 1, x)
    p.struct_arg_set(self.arg_vec, 2, y)
    local raw = p.invoke_value_args(m, {self.arg_vec})
    if type(raw) ~= 'string' or #raw < 8 then return nil end
    return string.unpack('<ff', raw)
end

return B