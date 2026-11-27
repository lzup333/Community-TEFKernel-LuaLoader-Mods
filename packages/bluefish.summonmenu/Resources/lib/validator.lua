local M={}
-- Ordinary blocks and walls can be cleared. Preserve framed objects, containers,
-- signs, wires, liquids and inactive/protected tiles.
function M.safe(c)
 return type(c)=='table' and type(c.active)=='boolean' and type(c.type)=='number' and type(c.wall)=='number'
  and c.liquid==0 and c.wires==false and not c.protected and not c.special
end
return M
