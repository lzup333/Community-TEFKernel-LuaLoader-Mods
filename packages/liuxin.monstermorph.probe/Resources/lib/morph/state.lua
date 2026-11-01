-- Health transactions nest because Player.Update may call Hurt.
local State = {}
State.__index = State

function State.new(maximum)
    return setmetatable({max=maximum, hp=maximum, active=false, depth=0}, State)
end

function State:activate()
    if self.hp <= 0 or self.depth ~= 0 then return false end
    self.active, self.defeated = true, false
    return true
end

function State:begin(current)
    if not self.active then return nil end
    if self.depth == 0 then self.human = current end
    self.depth = self.depth + 1
    if self.depth == 1 then return self.hp end
    return current
end

function State:defeat()
    if self.active then self.defeated = true; self.hp = 0 end
end

function State:finish(current)
    if self.depth == 0 then return nil end
    self.depth = self.depth - 1
    if self.depth > 0 then return nil end
    self.hp = self.defeated and 0 or math.max(0, math.min(self.max, current))
    local broken = self.hp <= 0
    if broken then self.active = false end
    local human = self.human
    self.human = nil
    return human, broken
end

function State:cancel()
    local human = self.human
    self.active, self.depth, self.human = false, 0, nil
    return human
end

return State
