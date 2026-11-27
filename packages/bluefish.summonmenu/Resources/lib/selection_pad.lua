-- Pointer ownership and time-based repetition; no game or rendering calls.
local M={}
local directions={up={0,-1},right={1,0},down={0,1},left={-1,0}}
local function hit(c,b)
 local x,y=c.x-(b.x+b.w/2),c.y-(b.y+b.h/2)
 local r=math.min(b.w,b.h)/2;local d=x*x+y*y
 if d>r*r or d<14*14 then return end
 if math.abs(x)>math.abs(y)then return x>0 and 'right'or 'left'end
 return y>0 and 'down'or 'up'
end
function M.new()
 local s={}
 function s:reset()self.id=nil;self.direction=nil;self.started=nil;self.nextAt=nil end
 function s:update(now,cursors,box,enabled,frame)
  local gap=self.lastTime and (now-self.lastTime>0.25 or now<self.lastTime)
  if frame and self.lastFrame and frame>self.lastFrame+1 then gap=true end
  self.lastTime=now;self.lastFrame=frame
  if gap then self:reset()end
  if not enabled then self:reset();return 0,0 end
  local c
  if self.id~=nil then
   for _,v in ipairs(cursors)do if v.id==self.id then c=v;break end end
   if not c or not c.down or not hit(c,box)then self:reset();return 0,0 end
  else
   for _,v in ipairs(cursors)do
    if v.down and v.wasDown==false and hit(v,box)then c=v;break end
   end
   if not c then return 0,0 end
   self.id=c.id
  end
  local dir=hit(c,box);local axis=directions[dir]
  if self.direction~=dir then
   self.direction=dir;self.started=now;self.nextAt=now+0.3
   return axis[1],axis[2]
  end
  if now<self.nextAt then return 0,0 end
  local accelerated=now-self.started>=1.2
  local period=accelerated and 0.045 or 0.08
  local count=math.min(3,math.floor((now-self.nextAt)/period)+1)
  self.nextAt=now+period
  local step=accelerated and 2 or 1
  return axis[1]*count*step,axis[2]*count*step
 end
 return s
end
return M
