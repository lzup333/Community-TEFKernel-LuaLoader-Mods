-- dot流是对的 v1.3.7 —— 加速痛苦(DoT)增强倍率自定义（支持联机）
-- v1.3.7 修复：飘出的伤害数字不跟着倍率变大
--   原版 GetHurtByDebuff(amount) 内部：
--     life -= amount;
--     CombatText.NewText(rect, CombatText.LifeRegenNegative, amount, dramatic:false, dot:true);
--   而 DoT 每次结算的 amount 基本恒为 1（真实伤害靠 lifeRegenCount 累积多次结算），
--   所以开多大倍率，玩家看到的永远是一排「-1」，只有血条下降变快。
--   本版：登记 CombatText.NewText 的返回下标，把「这一发原本要飘的数字」
--   改写成放大后的真实值，并隐藏补差那一次额外产生的数字。只改显示，不改伤害计算。
-- 目标版本 1.4.5.8
-- ============================================================================
-- v1.2.0 新增：联机（客户端）也能生效
-- ----------------------------------------------------------------------------
-- 为什么以前联机不生效：
--   多人模式下 NPC 血量是「服务器权威」。客户端本地改 Main.npc[i].life，
--   下一次服务器同步就把它覆盖回去；而且服务器算的伤害里根本没有我们的倍率。
--   换句话说：客户端改内存 = 只能骗自己屏幕，还可能数值抖动。
--
-- 怎么让服务器认账：
--   NPC.GetHurtByDebuff 在网络上的同步包是 MessageID **153**。
--   MessageBuffer.cs:4434 处理它：
--       case 153:
--       {
--           int num49 = reader.ReadByte();                  // NPC 索引
--           int num50 = reader.ReadInt16();                 // 伤害
--           Main.npc[num49].GetHurtByDebuff(num50);         // 直接扣血（不打折、不走免疫帧）
--           if (Main.netMode == 2)
--               NetMessage.TrySendData(153, -1, whoAmI, null, num49, num50);  // 广播给所有人
--           break;
--       }
--   注意：这段**没有任何发送者权限校验**——客户端发来的 153 一样会执行。
--   所以客户端只要把「差额」用 153 包报给服务器，服务器就会真的扣血并同步给全场。
--
-- 本模组的分支：
--   netMode == 0（单机）/ 2（开服者本人）→ 本地补差，走 GetHurtByDebuff，不打折最准
--   netMode == 1（加入别人服务器的客户端）→ 算出差额后用 153 包上报服务器
--                                           （本地不再自己扣，等服务器广播回来，避免双扣）
-- ----------------------------------------------------------------------------
-- 机制（NPC.cs 核实）：
--   「加速痛苦」= buffType 398 → NPC.UpdateNPC_BuffSetFlags 置 acceleratePoisons = true。
--   倍率写死在 NPC.UpdateNPC_BuffApplyDOTs()（NPC.cs:92826）：
--       int num2 = none.LifeRegenLoss;                 // L = 全部 DoT 每秒损失
--       if (acceleratePoisons) {
--           int B = none.LifeRegenLossThatCanBeBoosted;  // 可加速部分
--           float num4 = 2f;                            // ← 原版 2 倍，写死
--           num2 = (L - B) + (int)(B * num4);
--       }
--       lifeRegen -= num2;  lifeRegenCount += lifeRegen;
--       while (lifeRegenCount <= -120 * num) GetHurtByDebuff(num);
-- ----------------------------------------------------------------------------
-- 性能：配置只在 setup 读一次；播报后 Update 回调立即返回；无任何周期性文件 IO。
-- 风险：极少数服务器插件（TShock 类）可能对异常 153 包做检测。建议先自己开服试。
-- ============================================================================
mod.meta = { pkg_id = "bluefish.dotflow", version = "1.3.7", version_code = 21, api_version = 1, multiplayer_safe = true }

local patch = mod.patch

local ad_setup, ad_cleanup

do
    local H = {}
    local hooks = {}

    local ANN_TEXT = "这就是dot的力量∠·ω< )⌒☆"
    local ANN_DELAY = 60

    local MULT_MIN, MULT_MAX = 0, 20
    local net_inited = false
    local SEND_ARGC = 0          -- SendData 实际参数个数
    -- 不依赖任何 hook 的保险：即便防放大钩子装不上，也不会无限放大/刷包
    local SENT = {}              -- who -> 已上报累计伤害
    local SENT_RATIO = 4         -- 每只怪 30 秒内最多注入 lifeMax * 4 的伤害（兜底，主防线是回声识别）
    local sent_tick = 0
    local ECHO = {}               -- who -> {dmg, t}  最近一次发包的数值，用来识别服务器广播回来的回声
    local ECHO_WIN = 1.5          -- 回声有效窗口（秒）
    local WIN_START, WIN_COUNT = 0, 0
    local MAX_PER_SEC = 30       -- 全局每秒最多 30 个包（同一轮可触发多次结算，留足余量）

    local DOT_MULT = 2
    local ORIG_MULT = 2

    local ann_done = false
    local ann_frames = 0
    local in_extra = false
    -- v1.3.7：伤害数字修正用的状态
    local ct_seq = 0             -- CombatText.NewText 被调用次数（判断本次结算是否真的产生了一条飘字）
    local ct_mark = -1           -- 进入 GetHurtByDebuff 前的计数快照
    local ct_last = -1           -- 最近一次 NewText 返回的下标
    local net_mode = 0            -- 0 单机 / 1 客户端 / 2 服务器
    local can_send = false        -- 是否拿到了 153 发包能力
    local in_net = false          -- 正在处理服务器消息（120 号以前：防放大丢包）
    local last_send = {}          -- npc 索引 -> 上次发包时刻（节流）
    local pending = {}            -- npc 索引 -> 被节流/预算挡下、尚未上报的伤害
    local SEND_GAP = 0.15         -- 只防同一帧内疯狂重复；真正的防放大靠「回声识别」
    local frame_budget = 0        -- 本帧剩余发包预算
    local MAX_PER_FRAME = 2       -- 每帧最多发 2 个包

    local function find_field(t, name)
        local cur, guard = t, 0
        while cur and guard < 16 do
            local f = patch.get_field(cur, name)
            if f then return f end
            cur = patch.get_parent(cur)
            guard = guard + 1
        end
        return nil
    end

    local function rd(field, inst, ty)
        if not field then return nil end
        local ok, v = pcall(patch.get_field_value, field, inst, ty)
        if ok then return v end
        return nil
    end

    local function wr(field, inst, v, ty)
        if not field then return false end
        local ok, r = pcall(patch.set_field_value, field, inst, v, ty)
        return ok and r ~= false
    end

    -- ---------- v1.3.7：伤害数字修正（只改显示，不碰伤害） ----------
    local function ct_at(idx)
        if type(idx) ~= "number" or idx < 0 or not H.f_ct_arr then return nil end
        local arr = rd(H.f_ct_arr, nil, "object")
        if not arr then return nil end
        local okn, n = pcall(patch.array_length, arr)
        if not okn or type(n) ~= "number" or idx >= n then return nil end
        local okr, ct = pcall(patch.array_at, arr, idx, "object")
        if okr then return ct end
        return nil
    end
    local function ct_set_text(idx, value)
        local ct = ct_at(idx)
        if not ct then return false end
        local s = tostring(value)
        if patch.string_create then
            local okc, r = pcall(patch.string_create, s)
            if okc and r then s = r end
        end
        return wr(H.f_ct_text, ct, s, "object")
    end
    local function ct_hide(idx)
        local ct = ct_at(idx)
        if not ct then return false end
        return wr(H.f_ct_active, ct, false, "bool")
    end

    -- ---------- 配置（只在 setup 读一次） ----------
    local function parse_mult(text)
        if type(text) ~= "string" then return nil end
        local raw = text:match('"dot_mult"%s*:%s*"?([%d%.%-]+)"?')
        if not raw then return nil end
        local n = tonumber(raw)
        if not n then return nil end
        if n < MULT_MIN then n = MULT_MIN end
        if n > MULT_MAX then n = MULT_MAX end
        return math.floor(n + 0.5)
    end

    local function load_cfg()
        local ok, txt = pcall(mod.read_file, "config.json")
        if not ok then return end
        local n = parse_mult(txt)
        if n then DOT_MULT = n end
    end

    -- ---------- 播报 ----------
    local function in_world()
        local v = rd(H.f_gamemenu, nil, "bool")
        if v ~= nil then return v == false end
        if H.m_game_menu then
            local ok, r = pcall(patch.invoke, H.m_game_menu)
            if ok and type(r) == "boolean" then return r == false end
        end
        return false
    end

    local function say(text)
        if type(text) ~= "string" then return false end
        local s = text
        if patch.string_create then
            local okc, r = pcall(patch.string_create, text)
            if okc and r then s = r end
        end
        if H.m_newtext5 then
            local okc, r = pcall(patch.invoke, H.m_newtext5, s, 150, 255, 200, false)
            if okc and r ~= false then return true end
        end
        if H.m_newtext4 then
            local okc, r = pcall(patch.invoke, H.m_newtext4, s, 150, 255, 200)
            if okc and r ~= false then return true end
        end
        return false
    end

    -- ---------- 联机：把差额用 153 包报给服务器 ----------
    local function send_153(inst, who, dmg)
        if type(who) ~= "number" or who < 0 or who > 200 then return false end
        if not (can_send and H.m_send153) then return false end
        -- 保险 1：每只怪累计注入伤害封顶（放大链即使存在也不会无限滚）
        local lmax = rd(H.f_life_max, inst, "int32")
        if type(lmax) == "number" and lmax > 0 then
            if (SENT[who] or 0) >= lmax * SENT_RATIO then return false end
        end
        -- 保险 2：全局发包频率硬限速（防止一波怪同时结算刷爆网络）
        local now = os.clock()
        if now - WIN_START >= 1 then WIN_START, WIN_COUNT = now, 0 end
        if WIN_COUNT >= MAX_PER_SEC then return false end
        -- 被节流/预算挡下的伤害不丢，累到下1次一起报；包数不变，总伤害不缩水
        local total = (pending[who] or 0) + dmg
        local prev = last_send[who]
        if prev and (now - prev) < SEND_GAP then
            -- 不累积：被挡下的基本上是「服务器广播回来又触发的同一轮」，
            -- 累积会让伤害滚雪球（实测倍率 10 打出了远超 10 倍的效果）
            return false
        end
        if frame_budget <= 0 then
            pending[who] = total
            return false
        end
        local d = math.floor(total)
        if d < 1 then pending[who] = total return false end
        if d > 32000 then d = 32000 end
        pending[who] = nil
        frame_budget = frame_budget - 1
        WIN_COUNT = WIN_COUNT + 1
        SENT[who] = (SENT[who] or 0) + d
        ECHO[who] = { dmg = d, t = now }   -- 记住发出的数值，用于回声识别
        last_send[who] = now
        -- H.f_nt_empty 是静态只读字段，读一次就够便宜；跨帧保活反而要额外 invoke，不划算
        local nt = rd(H.f_nt_empty, nil, "object")
        -- SendData 的可选参数在 IL 里是完整列表，必须按实际个数补齐
        local ok
        if SEND_ARGC == 6 then
            ok = pcall(patch.invoke, H.m_send153, 153, -1, -1, nt, who, d)
        else
            local a = { 153, -1, -1, nt, who, d }
            for i = 7, SEND_ARGC do a[i] = 0 end
            ok = pcall(patch.invoke, H.m_send153, table.unpack(a))
        end
        return ok
    end

    -- ---------- DoT 倍率介入 ----------
    local function on_hurt_prefix(inst, args, result)
        ct_mark = ct_seq
        return false
    end
    local function on_hurt_debuff(inst, args, result)
        if in_extra then return end
        if DOT_MULT == ORIG_MULT then return end
        if not inst then return end
        if rd(H.f_accel, inst, "bool") ~= true then return end
        local amount = args and args[1]
        if type(amount) ~= "number" or amount <= 0 then return end

        local target = math.floor(amount * DOT_MULT / ORIG_MULT + 0.5)
        if target < 0 then target = 0 end
        local diff = target - amount
        if diff == 0 then return end

        if net_mode == 1 then
            -- 防放大：如果这一下是「服务器广播回来的 DOT」，它一定不能被我们二次利用。
            -- 识别方法：那个包里的 amount 正好等于我们自己刚发出去的数。
            if in_net then return end
            local who = rd(H.f_who, inst, "int32")
            local e = who and ECHO[who]
            if e and e.dmg == amount and (os.clock() - e.t) < ECHO_WIN then
                return
            end
            if diff > 0 then
                send_153(inst, who, diff)
            end
            return
        end

        -- 单机 / 开服者：本地直接补差
        if diff > 0 then
            -- 本次结算里原版已经飘了一条「amount」，先记住它的下标
            local ct_a = (ct_seq > ct_mark) and ct_last or -1
            in_extra = true
            pcall(patch.invoke, H.m_hurt, inst, diff)
            in_extra = false
            -- v1.3.7：把那条数字改成放大后的真实值，并隐藏补差那一次额外产生的数字
            if ct_a >= 0 then
                local ct_b = ct_last
                ct_set_text(ct_a, target)
                if ct_b ~= ct_a then ct_hide(ct_b) end
            end
        else
            local life = rd(H.f_life, inst, "int32")
            local lifeMax = rd(H.f_life_max, inst, "int32")
            if type(life) == "number" and type(lifeMax) == "number" and life > 0 then
                local nl = life + (-diff)
                if nl > lifeMax then nl = lifeMax end
                wr(H.f_life, inst, nl, "int32")
            end
        end
    end

    -- 倍率等于原版时不介入，这里只在那种情况下提醒一句，正常进入世界不刷任何文字
    local function report_status()
        if DOT_MULT == ORIG_MULT then
            say("[dot] 当前倍率=2（等于原版），模组不介入；请到模组设置里改倍率，改完退出世界再进")
        end
    end

    -- ---------- 联机能力初始化（进世界时重判：setup 时还在主菜单，netMode 恒为 0）----------
    local function init_net()
        if net_inited or net_mode ~= 1 then return end
        local t_net = patch.get_type("Terraria", "NetMessage")
        local t_nt  = patch.get_type("Terraria.Localization", "NetworkText")
        if not (t_net and t_nt) then return end
        H.f_nt_empty = patch.get_field(t_nt, "Empty")
        local i32 = patch.get_basic_type and patch.get_basic_type("int32")
        local f32 = patch.get_basic_type and patch.get_basic_type("float")
        -- SendData 的可选参数在 IL 里是完整参数列表，必须按全参数匹配
        local cands = {}
        if i32 and f32 and patch.get_method_by_param_types then
            cands[#cands + 1] = { 11, { i32, i32, i32, t_nt, i32, f32, f32, f32, i32, i32, i32 } }
            cands[#cands + 1] = { 9,  { i32, i32, i32, t_nt, i32, f32, f32, f32, i32 } }
            cands[#cands + 1] = { 6,  { i32, i32, i32, t_nt, i32, f32 } }
        end
        for _, c in ipairs(cands) do
            local ok, m = pcall(patch.get_method_by_param_types, t_net, "SendData", c[2])
            if ok and m then
                H.m_send153 = m
                SEND_ARGC = c[1]
                break
            end
        end
        if not H.m_send153 then
            for _, cnt in ipairs({ 11, 10, 9, 6, 5, 3 }) do
                local ok, m = pcall(patch.get_method, t_net, "SendData", cnt)
                if ok and m then
                    H.m_send153 = m
                    SEND_ARGC = cnt
                    break
                end
            end
        end
        can_send = (H.m_send153 ~= nil)
        -- 防放大：标记「正在处理服务器网络消息」的窗口
        -- 首选 MessageBuffer.GetData（逐条消息）；带 out 参数时参数个数可能算成 2，所以 3/2/1 都试
        -- 再退到 Netplay 的客户端帧处理入口（整个网络处理期间屏蔽补发）
        local hooked = false
        local t_mb = patch.get_type("Terraria", "MessageBuffer")
        if t_mb then
            for cnt = 0, 15 do
                local m = patch.get_method(t_mb, "GetData", cnt)
                if m then
                    local okg, hg = pcall(patch.install_hook, m, {
                        prefix  = function() in_net = true end,
                        postfix = function() in_net = false end,
                    })
                    if okg and hg then
                        hooks[#hooks + 1] = hg
                        hooked = true
                        break
                    end
                end
            end
        end
        if not hooked then
            local t_np = patch.get_type("Terraria", "Netplay")
            if t_np then
                for _, nm in ipairs({ "ClientFrame", "ClientUpdate", "ReadNetMessage", "UpdateClient", "ClientLoop", "DoNet" }) do
                    for cnt = 0, 15 do
                        local m = patch.get_method(t_np, nm, cnt)
                        if m then
                            local okg, hg = pcall(patch.install_hook, m, {
                                prefix  = function() in_net = true end,
                                postfix = function() in_net = false end,
                            })
                            if okg and hg then
                                hooks[#hooks + 1] = hg
                                hooked = true
                                break
                            end
                        end
                        if hooked then break end
                    end
                    if hooked then break end
                end
            end
        end
        -- 防放大主防线是「回声识别」（比对 amount 与最近发出的数值），不依赖 hook

        net_inited = true
    end

    -- ---------- 播报用的 Update 回调（播完空转） ----------
    local function on_main_update()
        frame_budget = MAX_PER_FRAME          -- 每帧重置发包预算（一次赋值，开销极低）
        sent_tick = sent_tick + 1
        if sent_tick >= 1800 then sent_tick = 0; SENT = {} end
        if not in_world() then
            ann_frames = 0
            return
        end
        ann_frames = ann_frames + 1
        -- 每次进世界重读一次配置并重判联机模式
        -- （setup 时还在主菜单，netMode 恒为 0，联机能力必须在这时补装）
        if ann_frames == 1 then
            load_cfg()
            net_mode = rd(H.f_netmode, nil, "int32") or 0
            pcall(init_net)
        end
        if ann_done then return end
        if ann_frames >= ANN_DELAY then
            if say(ANN_TEXT) then
                ann_done = true
                report_status()
            end
        end
    end

    -- ---------- setup ----------
    ad_setup = function()
        local ok, err = pcall(function()
            local t_npc  = patch.get_type("Terraria", "NPC")
            local t_main = patch.get_type("Terraria", "Main")
            if not (t_npc and t_main) then
                error("关键类型缺失")
            end
            H.f_accel    = find_field(t_npc, "acceleratePoisons")
            H.f_life     = find_field(t_npc, "life")
            H.f_life_max = find_field(t_npc, "lifeMax")
            H.f_who      = find_field(t_npc, "whoAmI")
            H.f_gamemenu = patch.get_field(t_main, "gameMenu")
            H.f_netmode  = patch.get_field(t_main, "netMode")
            H.m_game_menu = patch.get_method(t_main, "get_gameMenu", 0)
            H.m_newtext5 = patch.get_method(t_main, "NewText", 5)
            H.m_newtext4 = patch.get_method(t_main, "NewText", 4)
            H.m_hurt     = patch.get_method(t_npc, "GetHurtByDebuff", 1)
            if not H.f_accel then error("找不到 NPC.acceleratePoisons") end
            if not H.m_hurt then error("找不到 NPC.GetHurtByDebuff(int)") end

            load_cfg()
            net_mode = rd(H.f_netmode, nil, "int32") or 0
            init_net()

            -- v1.3.7：伤害数字修正——登记 CombatText.NewText 的返回下标
            --   只在倍率不等原版时安装；拿不到就降级（数字仍显示原值，不影响伤害）
            if DOT_MULT ~= ORIG_MULT then
                H.f_ct_arr = patch.get_field(t_main, "combatText")
                local t_ct = patch.get_type("Terraria", "CombatText")
                if t_ct then
                    H.f_ct_text   = patch.get_field(t_ct, "text")
                    H.f_ct_active = patch.get_field(t_ct, "active")
                end
                local m_nt
                local t_rect  = patch.get_type("Microsoft.Xna.Framework", "Rectangle")
                local t_color = patch.get_type("Microsoft.Xna.Framework", "Color")
                local i32 = patch.get_basic_type and patch.get_basic_type("int32")
                local blo = patch.get_basic_type and patch.get_basic_type("bool")
                if t_ct and t_rect and t_color and i32 and blo and patch.get_method_by_param_types then
                    local okm, m = pcall(patch.get_method_by_param_types, t_ct, "NewText",
                                         { t_rect, t_color, i32, blo, blo })
                    if okm and m then m_nt = m end
                end
                if not m_nt and t_ct then
                    local okm, m = pcall(patch.get_method, t_ct, "NewText", 5)
                    if okm and m then m_nt = m end
                end
                if m_nt and H.f_ct_arr and H.f_ct_text and H.f_ct_active then
                    local okn, hn = pcall(patch.install_hook, m_nt, {
                        postfix = function(inst2, args2, result)
                            if type(result) == "number" then
                                ct_seq = ct_seq + 1
                                ct_last = result
                            end
                        end,
                    })
                    if okn and hn then
                        hooks[#hooks + 1] = hn
                        mod.info("[dot] 伤害数字修正已启用")
                    else
                        mod.warn("[dot] 伤害数字修正挂钩失败，数字仍为原值")
                    end
                else
                    mod.warn("[dot] 找不到 CombatText.NewText，跳过数字修正")
                end
            end
            local okh, h = pcall(patch.install_hook, H.m_hurt, { prefix = on_hurt_prefix, postfix = on_hurt_debuff })
            if not (okh and h) then error("GetHurtByDebuff 挂钩失败") end
            hooks[#hooks + 1] = h

            local m_up = patch.get_method(t_main, "Update", 1)
                or patch.get_method(t_main, "Update", 0)
            if m_up then
                local okh2, h2 = pcall(patch.install_hook, m_up, { postfix = on_main_update })
                if okh2 and h2 then
                    hooks[#hooks + 1] = h2
                else
                    frame_budget = 1e9      -- 拿不到 Update 钩子就没有每帧重置，放开预算只靠节流
                end
            else
                frame_budget = 1e9
            end
            mod.info(string.format("[dot] 就绪 倍率=%s 网络模式=%d 发包=%s",
                tostring(DOT_MULT), net_mode, tostring(can_send)))
        end)
        if not ok then
            mod.warn("[dot] 初始化失败: " .. tostring(err))
        end
    end

    ad_cleanup = function()
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
    end
end

function setup()
    pcall(ad_setup)
end

function mod.cleanup()
    pcall(ad_cleanup)
end

todo_list = { "setup" }