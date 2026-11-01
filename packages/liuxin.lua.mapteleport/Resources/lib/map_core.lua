local M = {}
function M.to_world(c,x,y)
    return c.mx + (x-c.ox)/c.scale, c.my + (y-c.oy)/c.scale
end
function M.inside(r,x,y)
    return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h
end
function M.new()
    local state={}
    function state:clear() self.frame=nil self.kind=nil end
    function state:tap(frame,x,y,kind,radius)
        local matched=self.frame and frame>=self.frame and frame-self.frame<=30
            and self.kind==kind and (x-self.x)^2+(y-self.y)^2<=radius*radius
        if matched then self:clear(); return true end
        self.frame,self.x,self.y,self.kind=frame,x,y,kind
        return false
    end
    return state
end
return M
