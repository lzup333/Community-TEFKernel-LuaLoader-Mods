mod.meta = { pkg_id = "com.example.localnpcimmunity", version = "1.0.0" }

local patch = mod.patch

local proj_uses_local
local proj_uses_id_static
local proj_local_cd

local LOCAL_NPC_HIT_COOLDOWN = 10  -- 原版默认无敌帧时长

local function on_projectile_defaults(instance, args, result)
    if not instance then return end
    if proj_uses_local then
        patch.set_field_value(proj_uses_local, instance, true, "bool")
    end
    if proj_uses_id_static then
        patch.set_field_value(proj_uses_id_static, instance, false, "bool")
    end
    if proj_local_cd then
        local cd = patch.get_field_value(proj_local_cd, instance, "int32")
        if cd == nil or cd == -2 then
            patch.set_field_value(proj_local_cd, instance, LOCAL_NPC_HIT_COOLDOWN, "int32")
        end
    end
end

function setup()
    local projectile = patch.get_type("Terraria", "Projectile")
    if not projectile then
        mod.error("Terraria.Projectile not found")
        return
    end

    proj_uses_local     = patch.get_field(projectile, "usesLocalNPCImmunity")
    proj_uses_id_static = patch.get_field(projectile, "usesIDStaticNPCImmunity")
    proj_local_cd       = patch.get_field(projectile, "localNPCHitCooldown")
    if not proj_uses_local or not proj_uses_id_static or not proj_local_cd then
        mod.error("Projectile immunity flag fields missing")
        return
    end

    local m = patch.get_method(projectile, "SetDefaults", 1)
    if not m then
        mod.error("Projectile.SetDefaults(int) not found")
        return
    end

    local ok, err = pcall(patch.install_hook, m, { postfix = on_projectile_defaults })
    if not ok then
        mod.error("install_hook failed: " .. tostring(err))
        return
    end

    mod.info("hooked Projectile.SetDefaults -> force local NPC immunity")
end

todo_list = { "setup" }