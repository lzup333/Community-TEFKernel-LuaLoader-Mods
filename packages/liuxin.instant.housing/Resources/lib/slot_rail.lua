-- Horizontal slot rail uses the same verified touch coordinates as the copy pad.
local M={}
function M.new()
 local s={}
 function s:reset()self.id=nil;self.lastTime=nil;self.lastFrame=nil end
 function s:update(now,cursors,box,total,visible,first,enabled,frame)
  local max=math.max(1,total-visible+1)
  first=math.max(1,math.min(max,first))
  if self.lastTime and (now<self.lastTime or now-self.lastTime>0.25) or frame and self.lastFrame and frame>self.lastFrame+1 then self.id=nil end
  self.lastTime=now;self.lastFrame=frame
  if not enabled or max==1 then self.id=nil;return first end
  local c
  if self.id then
   for _,v in ipairs(cursors)do if v.id==self.id and v.down then c=v;break end end
   if not c then self.id=nil;return first end
  else
   for _,v in ipairs(cursors)do
    if v.down and v.wasDown==false and v.x>=box.x and v.x<box.x+box.w and v.y>=box.y-8 and v.y<box.y+box.h+8 then c=v;self.id=v.id;break end
   end
   if not c then return first end
  end
  local thumb=math.max(38,box.w*visible/total)
  local ratio=math.max(0,math.min(1,(c.x-box.x-thumb/2)/(box.w-thumb)))
  return 1+math.floor(ratio*(max-1)+0.5)
 end
 return s
end
return M
