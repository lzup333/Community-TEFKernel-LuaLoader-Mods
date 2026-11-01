local M={}
local keys={'blocks','walls','wires','liquid'}
function M.normalize(o)local r={};for _,k in ipairs(keys)do r[k]=not o or o[k]~=false end;return r end
function M.any(o)o=M.normalize(o);for _,k in ipairs(keys)do if o[k]then return true end end;return false end
local function copy(c)local r={};for k,v in pairs(c)do r[k]=v end;return r end
function M.merge(s,d,o)
 o=M.normalize(o)
 if o.blocks and o.walls and o.wires and o.liquid then return copy(s)end
 local c=copy(d)
 local function bits(k,m)c[k]=((c[k]or 0)&(~m))|((s[k]or 0)&m)end
 if o.blocks then c.type=s.type;c.fx=s.fx;c.fy=s.fy;bits('header',0x743f);bits('b2',0x30);bits('b3',0x50)end
 if o.walls then c.wall=s.wall;bits('b1',0x1f);bits('b2',0xcf);bits('b3',0xa7)end
 if o.wires then bits('header',0x8bc0)end
 if o.liquid then c.liquid=s.liquid;bits('b1',0x60)end
 return c
end
function M.clearBlock(d)return M.merge({type=0,fx=0,fy=0,header=0,b2=0,b3=0},d,{blocks=true,walls=false,wires=false,liquid=false})end
return M
