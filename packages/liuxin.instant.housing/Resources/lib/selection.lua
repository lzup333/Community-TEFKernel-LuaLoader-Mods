local B=require('blueprint')
local M={}
function M.new()
 local s={x=0,y=0,width=32,height=20,visible=false,worldKey=nil}
 function s:place(feet,key) self.x=feet.x-math.floor(self.width/2);self.y=feet.y-self.height+1;self.worldKey=key;self.visible=true end
 function s:move(dx,dy) self.x=self.x+dx;self.y=self.y+dy end
 function s:resize(dw,dh) self.width=math.max(1,math.min(B.MAX_W,self.width+dw));self.height=math.max(1,math.min(B.MAX_H,self.height+dh)) end
 function s:show(key)
  if self.worldKey~=key then return false end
  self.visible=true;return true
 end
 function s:setSize(width,height,snapshot)
  if type(width)~='string'or type(height)~='string'or not width:match('^%d+$')or not height:match('^%d+$')then return false,'宽高请输入整数'end
  local w,h=tonumber(width),tonumber(height)
  if not w or not h or w<1 or h<1 or w>B.MAX_W or h>B.MAX_H then return false,'尺寸范围：宽1–256，高1–128格'end
  local x=self.x+math.floor(self.width/2)-math.floor(w/2);local y=self.y+self.height-h
  if not snapshot or snapshot.worldKey~=self.worldKey or x<1 or y<1 or x+w>=snapshot.maxX or y+h>=snapshot.maxY then return false,'尺寸超出当前世界边界'end
  self.x=x;self.y=y;self.width=w;self.height=h;self.visible=true;self.renderLogged=false
  return true
 end
 function s:moveWithin(dx,dy,snapshot)
  if not snapshot or snapshot.worldKey~=self.worldKey then return false end
  self.x=math.max(1,math.min(snapshot.maxX-self.width-1,self.x+dx))
  self.y=math.max(1,math.min(snapshot.maxY-self.height-1,self.y+dy))
  return true
 end
 function s:rect()return {x=self.x,y=self.y,width=self.width,height=self.height,worldKey=self.worldKey}end
 function s:bounds(snapshot)
  return self.worldKey==snapshot.worldKey and self.x>=1 and self.y>=1 and self.x+self.width<snapshot.maxX and self.y+self.height<snapshot.maxY
 end
 return s
end
return M
