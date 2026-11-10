local model=require('bossbar.model')
local T={}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function T.new(mod,b,c)
 local p=b.p
 local cm=assert(p.get_type('','CursorManager'))
 local cursor=assert(p.get_type('','Cursor'))
 local runner=assert(p.get_type('','XNAUnityRunner'))
 local o={mod=mod,b=b,c=c,locked=true,active=nil,seen={},visible=false}
 o.instance=assert(p.get_field(cm,'Instance'))
 o.num=assert(p.get_method(cm,'GetNumCursors',0))
 o.at=assert(p.get_method(cm,'GetCursor',1))
 o.pos=assert(p.get_field(cursor,'Position'))
 o.down=assert(p.get_field(cursor,'Down'))
 o.id=assert(p.get_field(cursor,'Id'))
 o.ignore_world=assert(p.get_field(cursor,'IgnoreForWorld'))
 o.ignore=assert(p.get_field(cursor,'Ignore'))
 o.adjust=assert(p.get_method(runner,'AdjustRealScreenForUI',1))
 assert(type(b.adjust_screen)=='function')
 local ok,raw=pcall(mod.read_file,'bossbar_position.txt')
 if ok and type(raw)=='string' then
  local x,y=raw:match('^(%d*%.?%d+)%s+(%d*%.?%d+)%s*$'); x,y=tonumber(x),tonumber(y)
  if x and y and x>=0 and x<=1 and y>=0 and y<=1 then c.horizontal_anchor,c.vertical_anchor=x,y end
 end
 return setmetatable(o,{__index=T})
end
function T:save()
 if self.mod.write_file then pcall(self.mod.write_file,'bossbar_position.txt',string.format('%.5f %.5f',self.c.horizontal_anchor or .5,self.c.vertical_anchor or .955)) end
end
function T:draw(sb,layout)
 local b=self.b; local sw,sh=b:dimensions(); local l=layout or model.layout(sw,sh,self.c)
 if not l then self.visible=false; return end
 -- Keep the original touch target while drawing a much smaller emblem inside it.
 local size=clamp(42*l.scale,30,44)
 local x=clamp(l.x+l.width-size,0,sw-size); local y=clamp(l.y+4*l.scale,0,sh-size)
 self.rect={x=x,y=y,w=size,h=size}; self.layout=l; self.sw=sw; self.sh=sh; self.visible=true
 local accent=self.c.style=='D' and b:color(157,246,242,255) or b:color(255,216,129,255)
 local shade=self.c.style=='D' and b:color(15,65,72,255) or b:color(91,48,23,255)
 local function box(xx,yy,w,h,col) b:draw_sprite(sb,self.a.white,xx,yy,w,h,self.src,col) end
 local u=size/30; local ox=x+size*0.34; local oy=y+size*0.23
 -- A narrow, outlined pixel lock echoes the bar trim without a square backdrop.
 box(ox+2*u,oy+7*u,10*u,8*u,shade)
 box(ox+3*u,oy+8*u,8*u,6*u,accent)
 box(ox+4*u,oy+3*u,2*u,5*u,accent); box(ox+5*u,oy+2*u,5*u,2*u,accent)
 if self.locked then box(ox+9*u,oy+3*u,2*u,5*u,accent)
 else box(ox+11*u,oy+2*u,2*u,3*u,accent) end
 box(ox+6*u,oy+9*u,2*u,3*u,shade)
end
function T:update()
 local p,b=self.b.p,self.b
 local instance=p.get_field_value(self.instance,nil,'object')
 if not instance then self.active=nil; self.seen={}; return end
 local count=b:call(self.num,instance); if type(count)~='number' then return end
 local live={}; local found=false
 for i=0,math.min(count,32)-1 do
  local cur=b:call(self.at,instance,i)
  if cur then
   local id=p.get_field_value(self.id,cur,'int32'); local down=p.get_field_value(self.down,cur,'bool')
   local raw=p.get_field_raw(self.pos,cur,8)
   if type(id)=='number' and raw and #raw>=8 then
    live[id]=down==true
    local px,py=string.unpack('<ff',raw); local x,y=b:adjust_screen(self.adjust,px,py)
    if type(x)=='number' and type(y)=='number' then
     local r=self.rect; local a=self.active
     if not a and down and not self.seen[id] and self.visible and r then
      if x>=r.x-8 and x<=r.x+r.w+8 and y>=r.y-8 and y<=r.y+r.h+8 then
       self.active={id=id,kind='lock',sx=x,sy=y}; a=self.active
      elseif not self.locked and self.layout and x>=self.layout.x and x<=self.layout.x+self.layout.width and y>=self.layout.y and y<=self.layout.y+self.layout.height then
       self.active={id=id,kind='drag',sx=x,sy=y,ax=self.c.horizontal_anchor or .5,ay=self.c.vertical_anchor or .955}; a=self.active
      end
     end
     if a and a.id==id then
      found=true
      p.set_field_value(self.ignore_world,cur,true,'bool'); p.set_field_value(self.ignore,cur,true,'bool')
      if a.kind=='drag' and down then
       self.c.horizontal_anchor=clamp(a.ax+(x-a.sx)/self.sw,0,1)
       self.c.vertical_anchor=clamp(a.ay+(y-a.sy)/self.sh,0,1)
      elseif not down then
       if a.kind=='lock' and (x-a.sx)^2+(y-a.sy)^2<144 then self.locked=not self.locked; if self.locked then self:save() end end
       if a.kind=='drag' then self:save() end
       self.active=nil
      end
     end
    end
   end
  end
 end
 if self.active and not found then
  if self.active.kind=='drag' then self:save() end
  self.active=nil
 end
 self.seen=live
end
return T
