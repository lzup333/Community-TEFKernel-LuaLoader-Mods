mod.meta = { pkg_id = "lua.qing.eatworld", version = "1.0.0", version_code = 1000, api_version = 1 }

local P = mod.patch
local function w(s) return end

local R = 5
local g_on = false
local g_fly = false
local g_in_world = false
local g_vx, g_vy = 0.0, 0.0
local g_hover_y = nil
local FLY_SPEED = 8.0
local ACCEL = 0.06
local g_rot = 0.0
local K_SMOOTH = 0.13
local TILT_OFF = 1.5707963  -- 倾角偏移: 0=身体垂直(头朝上), +pi/2=朝飞行方向

-- 兼容 atan2：Lua5.3+ math.atan(y,x) 支持双参；老版本手动判
local function natan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if select("#", math.atan(1,1)) >= 2 then return math.atan(y, x) end
    if x > 0 then return math.atan(y/x) end
    if x < 0 then return math.atan(y/x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi/2 elseif y < 0 then return -math.pi/2 end
    return 0
end
local mKillTile = nil
local tPlayer, fPlayerPos = nil, nil
local fGravity, fVelocity = nil, nil
local fCtlL, fCtlR, fCtlU, fCtlD = nil, nil, nil, nil
local fImmune, fImmuneTime, fDead = nil,nil,nil
local fWet, fHoney, fHoneyWet, fWebbed, fSticky, fLavaWet = nil,nil,nil,nil,nil,nil
local fStatLife, fStatLifeMax2, fBreath, fBreathMax = nil,nil,nil,nil
local tNPC, fNPCTarget, mClearTarget = nil, nil, nil
local fNpcActive, fNpcLife, fNpcFriendly, fNpcTown, fNpcBoss, fNpcType, fNpcPos = nil, nil, nil, nil, nil, nil, nil
local fNpcImmortal, fNpcNoDmg, fNpcLifeMax = nil, nil, nil
local mStrikeNoInt = nil
local mNPCLoot = nil
local tMain, fMainNpc, fMainPlayer, fMainChest = nil, nil, nil, nil
local fMainTile = nil
local fWorldName = nil
local fGameMenu = nil
local fActiveWorldFileData = nil
local tCollision, fCollHoney, mWet, mLava = nil, nil, nil, nil
local mStickyMove, mDrown, mKillMe = nil, nil, nil
local tChest, fChestX, fChestY, fChestItem = nil, nil, nil, nil
local tItem, fItemType, fItemStack = nil, nil, nil
local g_get_msg_text, m_NewText = nil, nil
local lastx, lasty = -1, -1
local g_eat_tick = 0   -- 静止时也持续挖
local g_last_cmd, g_last_t = nil, 0
local g_chest_map = {}
local g_chest_n = 0
local g_killed_chest = 0
local g_dbg = 0

local function ct(c,s) return "[c/"..c..":"..s.."]" end
local function newtext(s)
    if not s or not m_NewText then return end
    pcall(function() P.invoke(m_NewText, P.string_create(s)) end)
end
local KEY = function(x, y) return x * 100000 + y end

local function build_chest_map()
    g_chest_map = {}; g_chest_n = 0
    if not (fMainChest and fChestX and fChestY) then w("build_map: no handles"); return end
    local ca = P.get_field_value(fMainChest, nil, "object")
    if not ca then w("build_map: no array"); return end
    local n = P.array_length(ca)
    if not n then return end
    for i = 0, n - 1 do
        local c = P.array_at(ca, i)
        if c then
            local cx = P.get_field_value(fChestX, c, "int32")
            local cy = P.get_field_value(fChestY, c, "int32")
            if cx and cy and cx > 0 and cy > 0 then
                g_chest_map[KEY(cx, cy)] = i; g_chest_n = g_chest_n + 1
            end
        end
    end
    w("chest map built: "..g_chest_n)
end

local function wipe_chest(idx)
    w("WC start idx="..tostring(idx))
    if not (fMainChest and fChestItem and fItemType and fItemStack) then w("WC no handles"); return end
    local ca = P.get_field_value(fMainChest, nil, "object")
    w("WC ca="..tostring(ca))
    if not ca then return end
    local c = P.array_at(ca, idx)
    w("WC c="..tostring(c))
    if not c then return end
    w("WC get item field...")
    local items = P.get_field_value(fChestItem, c, "object")
    w("WC items="..tostring(items))
    if not items then return end
    local n = P.array_length(items)
    w("WC n="..tostring(n))
    if not n then return end
    for j = 0, n - 1 do
        w("WC j="..j)
        local it = P.array_at(items, j)
        w("WC it="..tostring(it))
        if it then
            w("WC set type...")
            P.set_field_value(fItemType, it, 0, "int32")
            w("WC set stack...")
            P.set_field_value(fItemStack, it, 0, "int32")
            w("WC j="..j.." cleared")
        end
    end
    w("WC all cleared, vacating coords")
    pcall(function() P.set_field_value(fChestX, c, 0, "int32") end)
    pcall(function() P.set_field_value(fChestY, c, 0, "int32") end)
    w("WC done")
end

local function kill_cell(x, y)
    local k = KEY(x, y)
    local idx = g_chest_map[k]
    if idx then
        wipe_chest(idx); g_chest_map[k] = nil
        g_killed_chest = g_killed_chest + 1
        w("WIPE chest @ "..x..","..y.." #"..g_killed_chest)
    end
    pcall(function() P.invoke(mKillTile, x, y, false, false, true) end)
end

-- 诊断：读某格 tile 的 type（PE Main.tile 是 Tile[,]，尝试用字段指针）
local function dbg_tile(x, y)
    if not (fMainTile) then return -1 end
    local ok, ty = pcall(function()
        -- Main.tile[x,y] : 先取二维数组
        return -2
    end)
    return -2
end


local function probe_tile(px,py) end  -- disabled (caused SIGSEGV)

-- 秒杀半径内的敌对 NPC
local g_killed_npc = 0
local function kill_npcs(px, py)
    if not (fMainNpc and mStrikeNoInt) then w("kn: no handles"); return end
    local ok = pcall(function()
        local arr = P.get_field_value(fMainNpc, nil, "object")
        if not arr then return end
        local n = P.array_length(arr)
        if not n then return end
        local r2 = (R+2) * (R+2) * 256  -- 半径(像素)平方，R+2 格
        local px2, py2 = px*16+8, py*16+8
        for i = 0, n - 1 do
            local npc = P.array_at(arr, i)
            if npc then
                local act = P.get_field_value(fNpcActive, npc, "bool")
                if act then
                    local imm = P.get_field_value(fNpcImmortal, npc, "bool")
                    local nod = P.get_field_value(fNpcNoDmg, npc, "bool")
                    local lmax = P.get_field_value(fNpcLifeMax, npc, "int32")
                    -- 有血条(生命上限>0)且非无敌 → 杀
                    if not imm and not nod and lmax and lmax > 0 then
                        local love = P.get_field_value(fNpcLife, npc, "int32")
                        if love and love > 0 then
                            -- 距离
                            local dist = 99999999
                            local nx, ny = P.get_field_vec2(fNpcPos, npc)
                            if nx then
                                local dx = nx - px2
                                local dy = ny - py2
                                dist = dx*dx + dy*dy
                            end
                            if dist <= r2 then
                                P.invoke(mStrikeNoInt, npc, 9999, 0.0, 0)
                                g_killed_npc = g_killed_npc + 1
                                w("KILL npc type="..tostring(P.get_field_value(fNpcType, npc, "int32")).." #"..g_killed_npc)
                            end
                        end
                    end
                end
            end
        end
    end)
    if not ok then w("kill_npcs err") end
end

-- 立即冻结玩家(开指令瞬间用,避免延迟一帧导致下沉/滑走)
local g_cwe_wn = ""
local function _cwe_read()
    g_cwe_wn = P.get_field_value(fWorldName, nil, "string") or ""
end
local g_last_world = nil
local g_cwe_warned = false
-- 世界进出检测：逐字照抄 dmgprobe 原版
--   wn==""  → 退世界：auto-stop + g_last_world=nil
--   wn~=g_last_world → 进/换世界：reset
local function check_world()
    if not fWorldName then
        if not g_cwe_warned then g_cwe_warned = true; w("cwe: no fWorldName") end
        return
    end
    g_cwe_wn = ""
    pcall(_cwe_read)
    local wn = g_cwe_wn
    if wn == "" then
        -- 退世界：封存 + 关 /eat + 清 g_last_world
        if g_in_world then
            g_on = false; g_fly = false
            g_vx, g_vy = 0.0, 0.0
            g_hover_y = nil; g_rot = 0.0
            lastx, lasty = -1, -1
            w("WORLD EXIT auto-stop")
        end
        g_in_world = false
        g_last_world = nil
        return
    end
    -- 在世界里（wn 非空）
    if wn ~= g_last_world then
        g_last_world = wn
        g_in_world = true
        g_on = false; g_fly = false
        g_vx, g_vy = 0.0, 0.0
        g_hover_y = nil; g_rot = 0.0
        lastx, lasty = -1, -1
        w("WORLD ENTER reset ["..wn.."]")
    end
end

local function freeze_now()
    g_hover_y = nil
    pcall(function()
        if fMainPlayer and fVelocity then
            local n = P.array_length(fMainPlayer)
            for i = 0, n-1 do
                local pl = P.array_at(fMainPlayer, i)
                if pl then
                    P.set_field_vec2(fVelocity, pl, 0.0, 0.0)
                    if fGravity then P.set_field_value(fGravity, pl, 0.0, "float") end
                end
            end
        end
    end)
end

local function eat_at(cx, cy)
    if not mKillTile then return end
    kill_npcs(cx, cy)
    for dx = -R, R do
        for dy = -R, R do
            if dx*dx+dy*dy <= R*R then kill_cell(cx+dx, cy+dy) end
        end
    end
end

local function rbool(f, inst)
    local v = P.get_field_value(f, inst, "bool")
    return v and true or false
end

-- vx,vy = 方向键输入(归一化)；g_vx,g_vy = 当前飞行速度(惯性)
local function do_fly(self)
    if not (fGravity and fVelocity and fCtlL) then return end
    pcall(function() P.set_field_value(fGravity, self, 0.0, "float") end)
    local L = rbool(fCtlL, self)
    local Rt = rbool(fCtlR, self)
    local U = rbool(fCtlU, self)
    local D = rbool(fCtlD, self)
    local dx, dy = 0.0, 0.0
    if L and not Rt then dx = -1.0 elseif Rt and not L then dx = 1.0 end
    if U and not D then dy = -1.0 elseif D and not U then dy = 1.0 end
    local moving = (dx ~= 0.0 or dy ~= 0.0)
    if moving and dx ~= 0.0 and dy ~= 0.0 then
        local inv = 0.70710678; dx = dx * inv; dy = dy * inv
    end
    -- ★加速度系统：速度朝目标方向渐进逼近（小加速度=起步慢/弧形转弯）
    if moving then
        local tx, ty = dx * FLY_SPEED, dy * FLY_SPEED
        g_vx = g_vx + (tx - g_vx) * ACCEL
        g_vy = g_vy + (ty - g_vy) * ACCEL
    end
    -- 松手: 速度保持(惯性滑行)，无加速度
    local spd2 = g_vx*g_vx + g_vy*g_vy
    -- 速度极小时归零(避免抖)
    if spd2 < 0.0025 then g_vx, g_vy = 0.0, 0.0; spd2 = 0 end
    -- 朝向翻面: 只有横向速度足够大才翻(掉头时先刹停)
    if g_vx > 1.2 then
        if fDirection then pcall(function() P.set_field_value(fDirection, self, 1, "int32") end) end
    elseif g_vx < -1.2 then
        if fDirection then pcall(function() P.set_field_value(fDirection, self, -1, "int32") end) end
    end
    -- ★身体倾斜：朝实际速度方向平滑倒过去(最短弧插值)
    -- 方向超向：有速度朝飞行方向，停下则目标=0(竖直)，均平滑插值
    if fFullRot then
        local target = 0.0
        if spd2 > 0.0001 then
            target = natan2(g_vy, g_vx) + TILT_OFF
        end
        local d = target - g_rot
        while d > math.pi do d = d - 2*math.pi end
        while d < -math.pi do d = d + 2*math.pi end
        g_rot = g_rot + d * K_SMOOTH
        pcall(function() P.set_field_value(fFullRot, self, g_rot, "float") end)
        if fFullRotOrig then
            pcall(function()
                local w = 20; local h = 42
                if fWidth then local vw = P.get_field_value(fWidth, self, "int32"); if vw and vw>0 then w=vw end end
                if fHeight then local vh = P.get_field_value(fHeight, self, "int32"); if vh and vh>0 then h=vh end end
                P.set_field_vec2(fFullRotOrig, self, w*0.5, h)
            end)
        end
    end
    -- ★悬停稳定：速度≈0且不在上下输入时，每帧刷新基准y，防止挖空脚下后下沉
    if spd2 < 0.0025 and not U and not D then
        local px, py = P.get_field_vec2(fPlayerPos, self)
        if py then
            if g_hover_y then
                if math.abs(py - g_hover_y) > 0.01 then
                    pcall(function() P.set_field_vec2(fPlayerPos, self, px, g_hover_y) end)
                end
            else
                g_hover_y = py
            end
        end
    else
        g_hover_y = nil
    end
    pcall(function() P.set_field_vec2(fVelocity, self, g_vx, g_vy) end)
end


local function do_clear_liquid(self)
    if fWet then pcall(function() P.set_field_value(fWet, self, false, "bool") end) end
    if fHoneyWet then pcall(function() P.set_field_value(fHoneyWet, self, false, "bool") end) end
    if fLavaWet then pcall(function() P.set_field_value(fLavaWet, self, false, "bool") end) end
    if fWebbed then pcall(function() P.set_field_value(fWebbed, self, false, "bool") end) end
    if fSticky then pcall(function() P.set_field_value(fSticky, self, false, "bool") end) end
    if fHoney then pcall(function() P.set_field_value(fHoney, self, false, "bool") end) end
    if fCollHoney then pcall(function() P.set_field_value(fCollHoney, nil, false, "bool") end) end
end

-- 锁血锁氧：每帧回满
local function do_god(self)
    if fImmune then pcall(function() P.set_field_value(fImmune, self, true, "bool") end) end
    if fImmuneTime then pcall(function() P.set_field_value(fImmuneTime, self, 9999, "int32") end) end
    if fStatLifeMax2 and fStatLife then
        pcall(function()
            local mx = P.get_field_value(fStatLifeMax2, self, "int32")
            if mx and mx > 0 then P.set_field_value(fStatLife, self, mx, "int32") end
        end)
    end
    if fBreathMax and fBreath then
        pcall(function()
            local bm = P.get_field_value(fBreathMax, self, "int32")
            if bm and bm > 0 then P.set_field_value(fBreath, self, bm, "int32") end
        end)
    end
end

local function do_agro_clear()
    if not (fMainNpc and fNPCTarget) then return end
    local arr = P.get_field_value(fMainNpc, nil, "object")
    if not arr then return end
    local n = P.array_length(arr); if not n then return end
    for i = 0, n - 1 do
        local npc = P.array_at(arr, i)
        if npc then pcall(function() P.set_field_value(fNPCTarget, npc, 255, "int32") end) end
    end
end

setup = function()
    -- 热重载保护：若已有旧 hook，先全部卸载，避免叠加/残留
    if _G._eat_hooks then
        for _, h in ipairs(_G._eat_hooks) do pcall(function() h:remove() end) end
        w("hot-reload: removed "..#_G._eat_hooks.." old hooks")
    end
    _G._eat_hooks = {}
    _G._eat_setup = true
    w("=== setup 0.7.1 ===")
    local tWG = P.get_type("Terraria", "WorldGen")
    if tWG then mKillTile = P.get_method(tWG, "KillTile") end
    tPlayer = P.get_type("Terraria", "Player")
    if tPlayer then
        fPlayerPos = P.get_field(tPlayer, "position")
        fGravity = P.get_field(tPlayer, "gravity")
        fVelocity = P.get_field(tPlayer, "velocity")
        fDirection = P.get_field(tPlayer, "direction")
        fFullRot = P.get_field(tPlayer, "fullRotation")
        fFullRotOrig = P.get_field(tPlayer, "fullRotationOrigin")
        fWidth = P.get_field(tPlayer, "width")
        fHeight = P.get_field(tPlayer, "height")
        fCtlL = P.get_field(tPlayer, "controlLeft")
        fCtlR = P.get_field(tPlayer, "controlRight")
        fCtlU = P.get_field(tPlayer, "controlUp")
        fCtlD = P.get_field(tPlayer, "controlDown")
        fImmune = P.get_field(tPlayer, "immune")
        fImmuneTime = P.get_field(tPlayer, "immuneTime")
        fDead = P.get_field(tPlayer, "dead")
        fWet = P.get_field(tPlayer, "wet")
        fHoney = P.get_field(tPlayer, "honey")
        fHoneyWet = P.get_field(tPlayer, "honeyWet")
        fLavaWet = P.get_field(tPlayer, "lavaWet")
        fWebbed = P.get_field(tPlayer, "webbed")
        fSticky = P.get_field(tPlayer, "sticky")
        fStatLife = P.get_field(tPlayer, "statLife")
        fStatLifeMax2 = P.get_field(tPlayer, "statLifeMax2")
        fBreath = P.get_field(tPlayer, "breath")
        fBreathMax = P.get_field(tPlayer, "breathMax")
        mStickyMove = P.get_method(tPlayer, "StickyMovement", 0)
        mDrown = P.get_method(tPlayer, "CheckDrowning", 0)
        mKillMe = P.get_method(tPlayer, "KillMe", 4) or P.get_method(tPlayer, "KillMe", 3)
    end
    tChest = P.get_type("Terraria", "Chest")
    if tChest then
        fChestX = P.get_field(tChest, "x"); fChestY = P.get_field(tChest, "y"); fChestItem = P.get_field(tChest, "item")
    end
    tItem = P.get_type("Terraria", "Item")
    if tItem then
        fItemType = P.get_field(tItem, "type"); fItemStack = P.get_field(tItem, "stack")
    end
    tNPC = P.get_type("Terraria", "NPC")
    if tNPC then
        fNPCTarget = P.get_field(tNPC, "target")
        mClearTarget = P.get_method(tNPC, "ClearTarget", 0)
        fNpcActive = P.get_field(tNPC, "active")
        fNpcLife = P.get_field(tNPC, "life")
        fNpcFriendly = P.get_field(tNPC, "friendly")
        fNpcTown = P.get_field(tNPC, "townNPC")
        fNpcBoss = P.get_field(tNPC, "boss")
        fNpcType = P.get_field(tNPC, "type")
        fNpcPos = P.get_field(tNPC, "position")
        fNpcImmortal = P.get_field(tNPC, "immortal")
        fNpcNoDmg = P.get_field(tNPC, "dontTakeDamage")
        fNpcLifeMax = P.get_field(tNPC, "lifeMax")
        mStrikeNoInt = P.get_method(tNPC, "StrikeNPCNoInteraction", 3)
        mNPCLoot = P.get_method(tNPC, "NPCLoot", 0)
        if mNPCLoot then
            table.insert(_G._eat_hooks, P.install_hook(mNPCLoot, { prefix = function(inst, args, res)
                if g_on then return true end
                return false
            end }) )
            w("NPCLoot hooked (no-loot while /eat)")
        end
    end
    tMain = P.get_type("Terraria", "Main")
    if tMain then
        m_NewText = P.get_method(tMain, "NewText", 3) or P.get_method(tMain, "NewText", 5)
        fMainChest = P.get_field(tMain, "chest")
        fMainNpc = P.get_field(tMain, "npc")
        fMainPlayer = P.get_field(tMain, "player")
        fMainTile = P.get_field(tMain, "tile")
        fWorldName = P.get_field(tMain, "worldName")
        fGameMenu = P.get_field(tMain, "gameMenu")
        fActiveWorldFileData = P.get_field(tMain, "ActiveWorldFileData")
        -- 世界进出检测：纯复制 dmgprobe 写法（裸 install_hook，不存句柄）
        local mUpd = P.get_method(tMain, "Update", 1)
        if mUpd then
            local fc = 0
            P.install_hook(mUpd, { prefix = function(inst,args,res)
                fc = fc + 1
                -- 心跳超时检测：Main.Update 退世界会停跑；重进时若与上次间隔>1.5s -> 视为换世界
                local nowt = os.clock()
                if g_upd_last_t and (nowt - g_upd_last_t) > 0.2 then
                    pcall(function()
                        g_on = false; g_fly = false
                        g_vx, g_vy = 0.0, 0.0
                        g_hover_y = nil; g_rot = 0.0
                        lastx, lasty = -1, -1
                        g_in_world = false
                        g_last_world = nil
                    end)
                end
                g_upd_last_t = nowt
                if (fc % 6) == 0 then pcall(check_world) end
                return false
            end })
            w("hooked Main.Update(1) [copy]")
        else w("Main.Update(1) MISS") end
    end

    -- 进世界清空：尝试多个候选"进世界"方法（哪个存在挂哪个）
    if tWG then
        local cands = {"playWorld"}
        for _, nm in ipairs(cands) do
            local mWL = P.get_method(tWG, nm, 0)
            if mWL then
                P.install_hook(mWL, { postfix = function(inst, args, res)
                    pcall(check_world)
                    return false
                end })
                w("hooked WG."..nm.."(0)")
            end
        end
    end

    tCollision = P.get_type("Terraria", "Collision")
    if tCollision then
        fCollHoney = P.get_field(tCollision, "honey")
        mWet = P.get_method(tCollision, "WetCollision", 3)
        mLava = P.get_method(tCollision, "LavaCollision", 3)
    end
    w("KT="..tostring(mKillTile~=nil).." statLife="..tostring(fStatLife~=nil).." breath="..tostring(fBreath~=nil).." Drown="..tostring(mDrown~=nil).." KillMe="..tostring(mKillMe~=nil).." StickyMove="..tostring(mStickyMove~=nil).." Wet="..tostring(mWet~=nil))

    if mWet then
        table.insert(_G._eat_hooks, P.install_hook(mWet, { prefix = function(inst, args, res)
            if not g_on then return false end
            return true, false
        end }) )
    end
    if mLava then
        table.insert(_G._eat_hooks, P.install_hook(mLava, { prefix = function(inst, args, res)
            if not g_on then return false end
            return true, false
        end }) )
    end
    if mStickyMove then
        table.insert(_G._eat_hooks, P.install_hook(mStickyMove, { prefix = function(inst, args, res)
            if g_on then return true end
            return false
        end }) )
    end
    -- 免窒息
    if mDrown then
        table.insert(_G._eat_hooks, P.install_hook(mDrown, { prefix = function(inst, args, res)
            if g_on then return true end
            return false
        end }) )
    end
    -- 免死亡（终极保命）
    if mKillMe then
        table.insert(_G._eat_hooks, P.install_hook(mKillMe, { prefix = function(inst, args, res)
            if g_on and inst then
                pcall(function()
                    if fStatLife and fStatLifeMax2 then
                        local mx = P.get_field_value(fStatLifeMax2, inst, "int32")
                        if mx and mx > 0 then P.set_field_value(fStatLife, inst, mx, "int32") end
                    end
                    if fDead then P.set_field_value(fDead, inst, false, "bool") end
                end)
                if g_dbg < 20 then g_dbg = g_dbg + 1; w("KillMe blocked!") end
                return true
            end
            return false
        end }) )
    end

    if tPlayer and fPlayerPos then
        local mUpd = P.get_method(tPlayer, "Update", 1)
        if mUpd then
            table.insert(_G._eat_hooks, P.install_hook(mUpd, {
                prefix = function(self, args, res)
                    if g_on and self then do_clear_liquid(self) end
                    return false
                end,
                postfix = function(self, args, res)
                    if not self then return end
                    if g_fly then do_fly(self) end
                    if g_on then do_god(self); do_agro_clear() end
                    local x, y = P.get_field_vec2(fPlayerPos, self)
                    if not g_on then return end
                    if not x then return end
                    local cx = x + 10   -- 身体中心（position 是左上角，width=20）
                    local cy = y + 21   -- 身体中心（height=42）
                    local tx, ty = math.floor(cx/16), math.floor(cy/16)
                    -- 移动了 OR 静止时每 N 帧也挖一次（防被沙子埋住时卡死挖不动）
                    local moved = (tx ~= lastx or ty ~= lasty)
                    g_eat_tick = g_eat_tick + 1
                    if not moved and g_eat_tick < 8 then return end
                    if not moved then
                        -- 静止：从身体中心向上多挖 2 格（清头顶落沙）
                        eat_at(tx, ty - 1)
                        eat_at(tx, ty - 2)
                    end
                    lastx, lasty = tx, ty
                    g_eat_tick = 0
                    eat_at(tx, ty)
                end }) )
            w("Update hooked")
        end
    end

    local ChatCmd = P.get_type("Terraria.Chat", "ChatCommandProcessor")
    local ChatMessage = P.get_type("Terraria.Chat", "ChatMessage")
    if ChatMessage then
        local prop = mod.patch.get_property(ChatMessage, "Text")
        if prop then g_get_msg_text = mod.patch.property_get_method(prop) end
    end
    if ChatCmd then
        local mPM = P.get_method(ChatCmd, "ProcessIncomingMessage", 2)
        if mPM then
            table.insert(_G._eat_hooks, P.install_hook(mPM, { postfix = function(inst, args, res)
                local txt = nil
                pcall(function()
                    local r = P.invoke(g_get_msg_text, args[1])
                    if r then txt = P.string_value(r) end
                end)
                if not txt then return end
                local t = txt:gsub("^%s+",""):gsub("%s+$",""):lower()
                local now = os.clock()
                if t == g_last_cmd and (now - g_last_t) < 0.3 then return end
                g_last_cmd, g_last_t = t, now
                if t == "/eat" then
                    build_chest_map(); g_on = true; g_fly = true; g_dbg = 0; g_vx, g_vy = 0.0, 0.0; freeze_now()
                    newtext(ct("FF5555", "大口大口吃"))
                    w("CMD /eat ON (chests="..g_chest_n..")")
                elseif t == "/stop" then
                    g_on = false; g_fly = false; g_vx, g_vy = 0.0, 0.0
                    newtext(ct("FFAA00", "感觉胃被塞满了"))
                    w("CMD /stop OFF")
                end
            end }) )
            w("chat hooked")
        end
    end

    w("=== setup done ===")
end

todo_list = { "setup" }
