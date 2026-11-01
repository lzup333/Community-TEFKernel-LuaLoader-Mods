local Store=require('progress_store')
local M={caps={[0]=5,7,9,10,12,14,15,17,18,19,20}}
function M.cap(stage) return M.caps[stage] or 5 end
function M.threshold(level) return 100*level+25*level*(level-1) end
function M.progress(xp,stage)
 local stored,current,need=Store.level(xp)
 local cap=M.cap(stage);local effective=math.min(stored,cap)
 if stored>=cap then current=0;need=0 end
 return effective,current,need,stored,cap
end
function M.allowed(xp,award,stage)
 if type(xp)~='number' or type(award)~='number' or xp~=xp or award~=award or award<=0 then return 0 end
 return math.max(0,math.min(math.floor(award),M.threshold(M.cap(stage))-xp))
end
return M
