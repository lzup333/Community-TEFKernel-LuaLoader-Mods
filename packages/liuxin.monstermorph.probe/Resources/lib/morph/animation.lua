-- NPC.UpdateNPC is skipped for the harmless appearance proxy, so drive its
-- vanilla animation clock explicitly before calling FindFrame.
local Animation={}
function Animation.step(bridge,npc,form,attacking)
    if form.kind~='skeleton' then return end
    local counter=bridge:get('NPC','frameCounter',npc,'double') or 0
    local rate=attacking and 2.5 or 1.0
    bridge:set('NPC','frameCounter',npc,counter+rate,'double')
end
return Animation
