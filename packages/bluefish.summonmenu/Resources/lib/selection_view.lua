-- Pure geometry. PE AdjustWorldPositionForUI uses UI/world virtual resolutions
-- and the UI safe-area offsets (verified in the supplied 1.4.5.8 ARM64 body).
local M={}
function M.project(s,v)
 local sx,sy=v.uiWidth/v.worldWidth,v.uiHeight/v.worldHeight
 return {x=(s.x*16-v.x)*sx+v.offsetX,y=(s.y*16-v.y)*sy+v.offsetY,w=s.width*16*sx,h=s.height*16*sy}
end
function M.bands(r,sw,sh,t)
 local out={}
 local function add(x,y,w,h)
  local l,top=math.max(0,x),math.max(0,y);local right,bottom=math.min(sw,x+w),math.min(sh,y+h)
  if right>l and bottom>top then out[#out+1]={l,top,right-l,bottom-top}end
 end
 add(r.x,r.y,r.w,t);add(r.x,r.y+r.h-t,r.w,t)
 add(r.x,r.y+t,t,math.max(0,r.h-2*t));add(r.x+r.w-t,r.y+t,t,math.max(0,r.h-2*t))
 return out
end
function M.subtract(b,mask)
 if not mask then return {b}end
 local x,y,w,h=table.unpack(b);local l,t=math.max(x,mask.x),math.max(y,mask.y)
 local r,bt=math.min(x+w,mask.x+mask.w),math.min(y+h,mask.y+mask.h)
 if r<=l or bt<=t then return {b}end
 local out={}
 local function add(a,b,c,d)if c>0 and d>0 then out[#out+1]={a,b,c,d}end end
 add(x,y,w,t-y);add(x,bt,w,y+h-bt);add(x,t,l-x,bt-t);add(r,t,x+w-r,bt-t)
 return out
end
function M.origin(v,wx,wy)
 local scale=math.max(1,math.min(2.5,math.min(v.width,v.height)/720))
 -- LuaLoader src/gui.cpp: PAD=12, TITLE_H=32, ctx.oy=y+th+p/2.
 return wx+12*scale,wy+38*scale
end
return M
