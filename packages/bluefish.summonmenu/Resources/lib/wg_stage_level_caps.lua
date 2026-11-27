local Store=require('wg_progress_store')
local M={caps={[0]=5,7,9,10,12,14,15,17,18,19,20}}
M.cap=require('wg_native_backend').cap
function M.threshold(level) return 100*level+25*level*(level-1) end
function M.progress(xp,stage)
 local stored,current,need=Store.level(xp)
 local cap=M.cap(stage);local effective=math.min(stored,cap)
 if stored>=cap then current=0;need=0 end
 return effective,current,need,stored,cap
end
M.allowed=require('wg_native_backend').allowed
return M
