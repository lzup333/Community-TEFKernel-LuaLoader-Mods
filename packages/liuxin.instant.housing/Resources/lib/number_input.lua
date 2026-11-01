-- Numeric drafts never mutate world selection until explicitly submitted.
local M={}
function M.new()
 local n={active=false,buffer=''}
 function n:open(key,value)self.active=true;self.keyName=key;self.buffer=tostring(value);self.replace=true end
 function n:key(k)
  if k=='清空'then self.buffer='';self.replace=false
  elseif k=='退格'then self.buffer=self.buffer:sub(1,-2);self.replace=false
  elseif k:match('^%d$')then
   if self.replace then self.buffer='';self.replace=false end
   if #self.buffer<5 then self.buffer=self.buffer..k end
  end
 end
 function n:cancel()self.active=false;self.keyName=nil end
 return n
end
return M
