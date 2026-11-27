-- ============================================================================
--  format.lua —— 聊天栏单行播报
--
--  目标格式（用户指定）：
--      环境：丛林丨群系：地表丨事件：史莱姆雨
--
--  规则：
--    · 多个群系同时成立时用「／」连接（最多两个，多了补「等」）；
--    · 没有事件写「无」；
--    · 有事件时整行用暖色，平时用青色，方便一眼区分。
-- ============================================================================

local F = {}

F.VERSION = "1.1.2"

local COLOR_NORMAL = { 150, 240, 255 }   -- 青
local COLOR_EVENT  = { 255, 190, 120 }   -- 暖橙

local function biome_text(s)
    local names = s.biomes or {}
    if #names == 0 then return "未知" end
    local parts = {}
    for i = 1, math.min(#names, 2) do parts[#parts + 1] = names[i] end
    local text = table.concat(parts, "／")
    if #names > 2 then text = text .. " 等" end
    return text
end

-- 返回 { {text=..., r=,g=,b=} }，和 report 的发送接口保持一致
function F.chat(s)
    local text = string.format("环境：%s丨群系：%s丨事件：%s",
        biome_text(s),
        s.layer or "未知",
        s.eventStr or "无")

    local hasEvent = (s.events and #s.events > 0)
    local c = hasEvent and COLOR_EVENT or COLOR_NORMAL
    return { { text = text, r = c[1], g = c[2], b = c[3] } }
end

F.biome_text = biome_text

return F
