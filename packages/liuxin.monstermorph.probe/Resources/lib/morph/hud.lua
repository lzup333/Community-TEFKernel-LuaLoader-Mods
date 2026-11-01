-- Change the displayed pool only inside the original GUIHearts.Draw call.
local Hud={}
Hud.__index=Hud
function Hud.new(bridge)return setmetatable({b=bridge,stack={}},Hud)end
function Hud:begin(player,life,maximum)
    self.stack[#self.stack+1]={player=player,life=self.b:life(player),max=self.b:max_life(player)}
    self.b:set_life(player,life)
    self.b:set('Player','statLifeMax2',player,maximum,'int32')
end
function Hud:finish(player)
    local s=self.stack[#self.stack]
    if not s or s.player~=player then return end
    self.b:set_life(player,s.life)
    self.b:set('Player','statLifeMax2',player,s.max,'int32')
    self.stack[#self.stack]=nil
end
function Hud:restore(player)
    while #self.stack>0 do
        if self.stack[#self.stack].player~=player then self.stack={};return end
        self:finish(player)
    end
end
return Hud
