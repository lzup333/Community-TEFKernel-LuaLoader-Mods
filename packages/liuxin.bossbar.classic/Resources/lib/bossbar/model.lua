local styles=require('bossbar.styles')
local M={}
local function finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
function M.ratio(life,max)
 if not finite(life) or not finite(max) or max<=0 then return nil end
 return math.max(0,math.min(1,life/max))
end
function M.layout(sw,sh,c)
 if not finite(sw) or not finite(sh) or sw<240 or sh<160 then return nil end
 local height=(styles[c.style] and styles[c.style].height) or 145
 local width=math.min(sw*(c.width_fraction or 0.58),c.max_width or 820)
 local scale=math.min(width/620,sh/500)*(c.scale or 1)
 scale=math.max(0.2,math.min(scale,(sw-16)/620,(sh-16)/height))
 local w,h=620*scale,height*scale
 local x=math.floor(math.max(8,math.min(sw-w-8,sw*(c.horizontal_anchor or 0.5)-w/2)))
 local y=math.max(8,math.min(sh-h-8,sh*(c.vertical_anchor or 0.86)-h/2))
 return {x=x,y=math.floor(y),width=w,height=h,scale=scale,fill_width=488*scale}
end
function M.new()
 return setmetatable({trail=0,ratio=0,key=nil,hold_until=0,last_time=0},{__index={
  update=function(self,key,life,max,now)
   local r=M.ratio(life,max)
   if not r then return nil end
   if self.key~=key or now-self.last_time>0.5 or now<self.last_time then
    self.key,self.trail,self.hold_until=key,r,now
   elseif r<self.ratio then
    self.hold_until=now+0.25
   elseif r>self.trail then self.trail=r end
   local start=math.max(self.last_time,self.hold_until)
   if now>start then self.trail=math.max(r,self.trail-(now-start)*0.9) end
   self.ratio,self.last_time=r,now
   return r
  end
 }})
end
return M
