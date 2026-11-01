local C=require('suppression_config')
local M={config=C}
local function valid(n) return type(n)=='number' and n==n and n>0 and n<math.huge end
function M.calculate(world,origin,id,enabled)
 if not C.power[world] then return 1,'unknown_world',1,1 end
 if not C.power[origin] then return 1,'unknown_source',1,1 end
 if origin<=world then return 1,'current_or_earlier',1,1 end
 if not enabled then return 1,'suppression_off',1,1 end
 local base=C.power[world]/C.power[origin]
 local cfg=C.weapons[id]
 local q=cfg and cfg.q or 1
 if not valid(q) or q>1 then q=1 end
 local extra=q^(1-base)
 return base*extra,'period_suppression',base,extra
end
function M.tags(id) local c=C.weapons[id];return c and c.tags or 'standard' end
return M
