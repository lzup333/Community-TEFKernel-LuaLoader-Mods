local M={}
function M.random_skill(b,player)
    if b.cooldown>0 then return false end
    local tx=b:nearest_target(player);if not tx then return false end
    local choices={}
    if b.normal_runtime and(b.normal_runtime.cast or b.form.kind=='skeleton')then choices[#choices+1]=0 end
    if b.learned then for i=1,2 do if b.learned.ids[i]and b.learned.cooldowns[i]==0 then choices[#choices+1]=i end end end
    local random=b.random or math.random
    if #choices==0 or random()>=.4 then return false end
    local index=math.min(#choices,math.floor(random()*#choices)+1);local slot=choices[index];local success
    if slot==0 then
        if b.form.kind=='skeleton'then success=b:throw_bone(player)else success=b.normal_runtime:cast(player)end
    else success=b.learned:cast(player,slot)end
    if success then b.cooldown=math.max(b.form.duration,b:cd(b.form.cooldown,true));return true end
    return false
end
return M
