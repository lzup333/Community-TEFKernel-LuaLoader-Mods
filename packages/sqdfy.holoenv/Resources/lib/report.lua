-- ============================================================================
--  report.lua —— 聊天栏单行播报调度
--
--  行为：
--    · 进世界 0.5 秒后发第一行；
--    · 之后「环境签名」（群系 / 层深 / 事件）变化时发新行；
--    · 最短间隔 report_interval 秒，穿越群系时把多次变化合并成一次；
--    · 发送连续失败 5 次自动停播。
-- ============================================================================

local R = {}

R.VERSION = "1.1.2"

local BOOT_DELAY = 30          -- 30 帧 ≈ 0.5 秒
local MAX_FAILS  = 5

function R.new(send)
    return setmetatable({
        send       = send,
        lastSig    = nil,
        lastFrame  = -100000,
        pendingSig = nil,
        pendingSnap= nil,
        startFrame = nil,
        started    = false,
        fails      = 0,
        dead       = false,
    }, { __index = R })
end

function R:reset()
    self.lastSig    = nil
    self.pendingSig = nil
    self.pendingSnap= nil
    self.startFrame = nil
    self.started    = false
end

function R:emit(snap, fmt)
    if self.dead then return end
    local FMT = fmt or require("format")
    local lines = FMT.chat(snap)
    for _, line in ipairs(lines) do
        local ok = self.send(line.text, line.r, line.g, line.b)
        if not ok then
            self.fails = self.fails + 1
            if self.fails >= MAX_FAILS then
                self.dead = true
                pcall(mod.warn, "[环境监控] 聊天发送连续失败，已停止播报")
                return
            end
        else
            self.fails = 0
        end
    end
end

function R:tick(snap, frame, cfg, fmt)
    if not snap then
        self:reset()
        return false
    end

    if not self.started then
        if not self.startFrame then self.startFrame = frame end
        if frame - self.startFrame < BOOT_DELAY then return false end
        self.started = true
        self:emit(snap, fmt)
        self.lastSig = snap.sig
        self.lastFrame = frame
        return true
    end

    if snap.sig ~= self.lastSig then
        self.pendingSig = snap.sig
        self.pendingSnap = snap
    end

    if self.pendingSig then
        local wait = (cfg.report_interval or 3) * 60
        if frame - self.lastFrame >= wait then
            if self.pendingSig ~= self.lastSig then
                self:emit(self.pendingSnap or snap, fmt)
                self.lastSig = self.pendingSig
                self.lastFrame = frame
                self.pendingSig = nil
                self.pendingSnap = nil
                return true
            end
            self.pendingSig = nil
            self.pendingSnap = nil
            self.lastFrame = frame
        end
    end
    return false
end

return R
