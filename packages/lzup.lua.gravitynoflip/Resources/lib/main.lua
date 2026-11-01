--[[
  重力药水屏幕不翻转 —— LuaLoader (Lua) 版
  ---------------------------------------------------------------------------
  由经典 EFMod (C++) 版 `重力药水屏幕不翻转.cpp` 移植，并针对
  Terraria 1.4.5.8 的行为差异做了适配。

  === 原版 C++ 做法 ===
  原版 Hook 了 Player.Update，在原方法执行完之后：
      if ((gravControl || gravControl2) && gravDir == -1f) gravDir = -0.99f;
  把 gravDir 从 -1 改成 -0.99。这样：
      * 所有 `gravDir == -1f` 的判断都不再成立（鼠标取世界坐标、放方块、
        玩家贴图等都不会上下翻转）；
      * 而物理使用 gravDir 的符号/乘法，-0.99 < 0，重力方向仍然是反的。
  于是“屏幕不翻转、但重力照旧反向”。

  === 1.4.5.8 的差异（关键） ===
  Terraria 1.4.5.8 里，整屏翻转的判定在 Main.DoDraw：
      Main.GameViewMatrix.Effects =
          (!gameMenu && player[Main.myPlayer].gravDir != 1f)
              ? SpriteEffects.FlipVertically : SpriteEffects.None;
  （Source-1.4.5.8/PC/Terraria/Main.cs:62992）
  注意条件是 `gravDir != 1f`，不是 `gravDir == -1f`。
  所以把 gravDir 改成 -0.99 依然满足 `!= 1f`，屏幕照样翻转——旧做法在
  1.4.5.8 上对“整屏翻转”已失效。

  === 本 Lua 版的适配 ===
  1. 保留 -0.99 的做法：绕过所有 `== -1f` 的翻转判断，同时保留反向重力；
  2. 额外 Hook 绘制入口 Main.DoDraw（找不到则回退 Main.Draw）：
      - prefix：把本地玩家的 gravDir 临时设为 1 并保存原值；
      - postfix：恢复原值。
     这样 DoDraw 里那句 `gravDir != 1f` 不成立，GameViewMatrix 不再翻转。
  两者配合，在 1.4.5.8（以及更旧版本）上都能真正做到屏幕不翻转。

  说明：
  - 只影响本地玩家；联机时可能与其他玩家表现不同，已在 luamod.json 标记
    multiplayer_safe = false。
  - 只处理重力药水/重力球（gravControl / gravControl2）。
    克苏鲁之脑等造成的 forcedGravity 保持原版翻转，与原 C++ 版一致。
--]]

mod.meta = { pkg_id = "lzup.lua.gravitynoflip", version = "1.0.0" }

-- ============ 句柄 / 状态 ============
local grav_control          -- Player.gravControl  (bool)
local grav_control2         -- Player.gravControl2 (bool)
local grav_dir              -- Player.gravDir      (float)

-- 取本地玩家用：桌面端 Main.myPlayer 是字段；Android 端是属性，
-- 通过 get_myPlayer() 读取。Main.player 两端都是静态字段。
local my_player_field
local get_my_player
local main_player_field

local draw_player           -- 绘制期间缓存（retain 过的）本地玩家句柄
local restore_grav          -- 绘制期间被改掉的 gravDir 原值

-- ============ 小工具 ============
local function read_float(field, instance)
    return mod.patch.get_field_value(field, instance, "float")
end

local function read_bool(field, instance)
    return mod.patch.get_field_value(field, instance, "bool")
end

--- 玩家是否处于（药水/重力球）可控反向重力状态
local function has_gravity_control(player)
    return read_bool(grav_control, player) or read_bool(grav_control2, player)
end

--- 本地玩家编号；失败返回 nil
local function my_player_index()
    if my_player_field then
        return mod.patch.get_field_value(my_player_field, nil, "int32")
    end
    if get_my_player then
        return mod.patch.invoke(get_my_player)
    end
    return nil
end

--- 取本地玩家实例。句柄为借用句柄，仅当次调用有效，切勿长期保存。
local function local_player()
    if not main_player_field then return nil end
    local idx = my_player_index()
    if idx == nil or idx < 0 then return nil end
    local arr = mod.patch.get_field_value(main_player_field, nil, "object")
    if not arr then return nil end
    return mod.patch.array_at(arr, idx)
end

-- ============ Hook 1：Player.Update 后置 ============
-- 保留原 C++ 版语义：反向重力时把 gravDir 从 -1 改成 -0.99。
-- 这样所有 `gravDir == -1f` 的翻转判断失效，而物理仍按负方向计算。
local function on_player_update(instance)
    if not instance then return end
    local dir = read_float(grav_dir, instance)
    if dir == -1.0 and has_gravity_control(instance) then
        mod.patch.set_field_value(grav_dir, instance, -0.99, "float")
    end
end

-- ============ Hook 2：Main.DoDraw 前后置 ============
-- 1.4.5.8 的整屏翻转用 `gravDir != 1f` 判断，-0.99 拦不住。
-- 绘制期间临时把 gravDir 置为 1，绘制后恢复，屏幕才真正不翻转。
local function on_draw_prefix()
    draw_player = nil
    restore_grav = nil

    local p = local_player()
    if not p then return false end

    local dir = read_float(grav_dir, p)
    if dir ~= 1.0 and has_gravity_control(p) then
        -- retain 出 GC 托管句柄，可安全跨到 postfix 使用
        draw_player = mod.patch.retain(p)
        restore_grav = dir
        mod.patch.set_field_value(grav_dir, p, 1.0, "float")
    end
    return false
end

local function on_draw_postfix()
    if draw_player and restore_grav ~= nil then
        mod.patch.set_field_value(grav_dir, draw_player, restore_grav, "float")
    end
    draw_player = nil
    restore_grav = nil
end

-- ============ 生命周期 ============
--- 安装钩子并吞掉异常，返回是否成功
local function safe_install_hook(method, hooks, label)
    if not method then
        mod.error("安装钩子失败(" .. label .. ")：方法句柄为空")
        return false
    end
    local ok, err = pcall(mod.patch.install_hook, method, hooks)
    if not ok then
        mod.error("安装钩子失败(" .. label .. ")：" .. tostring(err))
    end
    return ok
end

function setup()
    local player_type = mod.patch.get_type("Terraria", "Player")
    if not player_type then
        mod.error("找不到类型 Terraria.Player，模组未启用")
        return
    end

    grav_control = mod.patch.get_field(player_type, "gravControl")
    grav_control2 = mod.patch.get_field(player_type, "gravControl2")
    grav_dir = mod.patch.get_field(player_type, "gravDir")
    if not grav_control or not grav_control2 or not grav_dir then
        mod.error("缺少 Player.gravControl / gravControl2 / gravDir 字段，模组未启用")
        return
    end

    -- 1) Player.Update(int)：每帧执行完原版逻辑后再改 gravDir
    local update = mod.patch.get_method(player_type, "Update", 1)
    if not safe_install_hook(update, { postfix = on_player_update }, "Player.Update") then
        mod.error("找不到 / 无法 Hook Player.Update(int)，重力绕过逻辑未安装")
    end

    -- 2) 屏幕翻转修复：优先 DoDraw，回退 Draw
    local main_type = mod.patch.get_type("Terraria", "Main")
    if main_type then
        main_player_field = mod.patch.get_field(main_type, "player")
        my_player_field = mod.patch.get_field(main_type, "myPlayer")
        if not my_player_field then
            get_my_player = mod.patch.get_method(main_type, "get_myPlayer", 0)
        end

        local draw = mod.patch.get_method(main_type, "DoDraw", 1)
                or mod.patch.get_method(main_type, "Draw", 1)
        if safe_install_hook(draw, {
            prefix = on_draw_prefix,
            postfix = on_draw_postfix,
        }, "Main.Draw") then
            mod.info("屏幕翻转修复已安装")
        else
            mod.warn("找不到 / 无法 Hook Main.DoDraw / Main.Draw，屏幕仍可能翻转")
        end
    else
        mod.warn("找不到类型 Terraria.Main，屏幕仍可能翻转")
    end

    mod.info("重力药水屏幕不翻转已启用")
end

todo_list = { "setup" }
