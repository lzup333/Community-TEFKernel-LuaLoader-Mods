-- Credit actual life lost, bounded by the target's spawn-life budget.
local Credit={}
Credit.__index=Credit
function Credit.new(bridge,award)return setmetatable({b=bridge,award=award,targets={},stack={},array=nil},Credit)end
function Credit:spawn(index)self.targets[index]=nil end
function Credit:before(npc,key)
    local b=self.b;local frame=false
    if key and npc and b:get('NPC','active',npc,'bool') and not b:get('NPC','friendly',npc,'bool')
        and not b:get('NPC','dontTakeDamage',npc,'bool') then
        local life=b:get('NPC','life',npc,'int32')
        if life>0 then frame={npc=npc,key=key,before=life,index=b:get('Entity','whoAmI',npc,'int32'),
            kind=b:get('NPC','type',npc,'int32'),maximum=math.max(1,b:get('NPC','lifeMax',npc,'int32'))} end
    end
    self.stack[#self.stack+1]=frame
end
function Credit:after()
    local f=self.stack[#self.stack];self.stack[#self.stack]=nil
    if not f then return end
    local b=self.b;local array=b:get('Main','npc',nil,'object')
    if self.array~=array then self.array=array;self.targets={} end
    if b:get('NPC','type',f.npc,'int32')~=f.kind then return end
    local after=math.max(0,b:get('NPC','life',f.npc,'int32'))
    local t=self.targets[f.index]
    if not t or t.npc~=f.npc or t.kind~=f.kind then t={npc=f.npc,kind=f.kind,remaining=f.maximum,killed=false};self.targets[f.index]=t end
    local damage=math.min(t.remaining,math.max(0,f.before-after))
    t.remaining=t.remaining-damage
    local bonus=0
    if damage>0 and after==0 and not t.killed then bonus=math.min(50,math.floor(f.maximum*.1));t.killed=true end
    if damage+bonus>0 then self.award(f.key,damage+bonus) end
end
return Credit
