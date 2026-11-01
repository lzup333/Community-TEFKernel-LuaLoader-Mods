local Melee={}
function Melee.phase(form,remaining)
    if remaining<=0 then return 'idle' end
    if remaining>form.duration-(form.windup or 0) then return 'windup' end
    if remaining<=(form.recovery or 0) then return 'recovery' end
    return 'active'
end
function Melee.angle(form,remaining)
    local elapsed=form.duration-remaining
    local windup,recovery=form.windup or 0,form.recovery or 0
    local active=form.duration-windup-recovery
    if elapsed<windup then return -1.1-.8*elapsed/math.max(1,windup) end
    if remaining>recovery then
        local t=math.min(1,(elapsed-windup)/math.max(1,active))
        return -1.9+3.4*t*t*(3-2*t)
    end
    return 1.5-1.9*(recovery-remaining)/math.max(1,recovery)
end
return Melee
