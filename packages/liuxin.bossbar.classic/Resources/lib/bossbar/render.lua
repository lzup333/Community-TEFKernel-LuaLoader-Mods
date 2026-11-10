local styles=require('bossbar.styles')
local model=require('bossbar.model')
local R={}
function R.new(b,a,c)
 local self={b=b,a=a,c=c,state=model.new(),states={},variants={}}
 for _,key in ipairs({'D'}) do
  local d=styles[key]
  local v={src=b:source(0,0,d.image_w,d.image_h),colors={}}
  for _,name in ipairs({'fill','light','shine','bottom','title'}) do v.colors[name]=b:color(table.unpack(d[name])) end
  self.variants[key]=v
 end
 self.src={left=b:source(0,0,500,724),rail=b:source(500,260,1480,200),right=b:source(1980,200,192,330),white=b:source(0,0,1,1)}
 self.colors={white=b:color(255,255,255),gold=b:color(255,224,151),dark=b:color(12,14,25),
  trail=b:color(244,173,67),red=b:color(172,13,35),light=b:color(224,35,57),shine=b:color(246,73,85),
  bottom=b:color(108,8,22),shield=b:color(81,189,248)}
 return setmetatable(self,{__index=R})
end
function R:draw(sb,life,max,icon,shield,shieldmax,track,now,layout)
 local b,a,c=self.b,self.a,self.c
 local sw,sh=b:dimensions()
 local l=layout or model.layout(sw,sh,c)
 if not l or not model.ratio(life,max) then return false end
 self.last_layout=l
 if b.trace then b.trace(string.format('HUD layout screen=%dx%d x=%.1f y=%.1f width=%.1f height=%.1f',sw,sh,l.x,l.y,l.width,l.height)) end
 a:prepare(c.style)
 local s,x,y=l.scale,l.x,l.y
 local w=620
 self.state=self:state_for(track.key,now)
 local r=self.state:update(track.key,life,max,now)
 local style=styles[c.style] and c.style or 'A'
 if style~='A' then return self:draw_variant(sb,life,max,icon,shield,shieldmax,track,l,r,style) end
 local colors=self.colors
 local function sprite(tex,xx,yy,ww,hh,src,color)
  b:draw_sprite(sb,tex,x+xx*s,y+yy*s,ww*s,hh*s,src,color)
 end
 local function fill(xx,yy,ww,hh,col) sprite(a.white,xx,yy,ww,hh,self.src.white,col) end
 local fw=488
 fill(96,59,fw,25,colors.dark)
 if c.damage_trail and self.state.trail>r then fill(96,60,fw*self.state.trail,23,colors.trail) end
 fill(96,60,fw*r,23,colors.red)
 fill(96,61,fw*r,7,colors.light)
 fill(96,60,fw*r,2,colors.shine)
 fill(96,80,fw*r,3,colors.bottom)
 sprite(a.frame,96,52,w-96-38.4,40,self.src.rail,colors.white)
 sprite(a.frame,0,0,100,144.8,self.src.left,colors.white)
 sprite(a.frame,w-38.4,40,38.4,66,self.src.right,colors.white)
 if icon then
  local iw=b.p.get_field_value(b.tex_width,icon,'int32')
  local ih=b.p.get_field_value(b.tex_height,icon,'int32')
  if iw and ih and iw>0 and ih>0 and iw<=4096 and ih<=4096 then
   local fit=math.min(43/iw,43/ih)
   local src=b:source(0,0,iw,ih)
   sprite(icon,50-iw*fit/2,72-ih*fit/2,iw*fit,ih*fit,src,colors.white)
  end
 end
 local sr=model.ratio(shield or 0,shieldmax or 0)
 if sr and sr>0 and shieldmax>0 then
  fill(100,95,480,4,colors.dark)
  fill(100,95,480*sr,4,colors.shield)
 end
 -- 所有文字放在所有纹理之后，兼容 PE 的纹理批次排序。
 b:draw_text(sb,track.name,x+320*s,y+29*s,colors.gold,0.84*s,0.5)
 b:draw_text(sb,string.format('%d / %d',math.floor(math.max(0,life)),math.floor(max)),x+320*s,y+58*s,colors.white,0.90*s,0.5)
 if c.show_percentage then b:draw_text(sb,string.format('%.1f%%',r*100),x+573*s,y+58*s,colors.gold,0.86*s,1) end
 return true
end
function R:draw_variant(sb,life,max,icon,shield,shieldmax,track,l,r,key)
 local b,a,c=self.b,self.a,self.c
 local d,v=styles[key],self.variants[key]
 local s,x,y=l.scale,l.x,l.y
 local function sprite(tex,xx,yy,ww,hh,src,col)
  b:draw_sprite(sb,tex,x+xx*s,y+yy*s,ww*s,hh*s,src,col)
 end
 local function fill(xx,yy,ww,hh,col) sprite(a.white,xx,yy,ww,hh,self.src.white,col) end
 local fx,fy,fw,fh=d.fill_x,d.fill_y,d.fill_w,d.fill_h
 fill(fx,fy,fw,fh,self.colors.dark)
 if c.damage_trail and self.state.trail>r then fill(fx,fy,fw*self.state.trail,fh,self.colors.trail) end
 fill(fx,fy,fw*r,fh,v.colors.fill)
 fill(fx,fy+1,fw*r,fh*0.28,v.colors.light)
 fill(fx,fy,fw*r,2,v.colors.shine)
 fill(fx,fy+fh-3,fw*r,3,v.colors.bottom)
 if d.ticks then
  for _,threshold in ipairs({1/3,2/3}) do
   fill(fx+fw*threshold-1,fy,2,fh,r>=threshold and v.colors.shine or self.colors.dark)
  end
 end
 -- 整幅透明边框覆盖血槽，保留骨翼/紫焰完整轮廓。
 sprite(a.frame,0,0,620,d.height,v.src,self.colors.white)
 if icon then
  local iw=b.p.get_field_value(b.tex_width,icon,'int32')
  local ih=b.p.get_field_value(b.tex_height,icon,'int32')
  if iw and ih and iw>0 and ih>0 and iw<=4096 and ih<=4096 then
   local fit=math.min(60/iw,60/ih)
   sprite(icon,d.icon_x-iw*fit/2,d.icon_y-ih*fit/2,iw*fit,ih*fit,b:source(0,0,iw,ih),self.colors.white)
  end
 end
 local sr=model.ratio(shield or 0,shieldmax or 0)
 if sr and sr>0 and shieldmax>0 then
  fill(fx+4,fy+fh+12,fw-8,4,self.colors.dark)
  fill(fx+4,fy+fh+12,(fw-8)*sr,4,self.colors.shield)
 end
 local center=fx+fw/2
 b:draw_text(sb,track.name,x+center*s,y+12*s,v.colors.title,0.84*s,0.5)
 local textscale=(key=='D' and 1.02 or 0.90)*s
 local texty=y+(fy+(fh-28*(key=='D' and 1.02 or 0.90))/2)*s
 b:draw_text(sb,string.format('%d / %d',math.floor(math.max(0,life)),math.floor(max)),x+center*s,texty,self.colors.white,textscale,0.5)
 if c.show_percentage then
  b:draw_text(sb,string.format('%.1f%%',r*100),x+(fx+fw-10)*s,texty,v.colors.title,0.86*s,1)
 end
 return true
end

function R:state_for(key,now)
 for k,value in pairs(self.states) do if now-value.used>3 or now<value.used then self.states[k]=nil end end
 local value=self.states[key]
 if not value then value={model=model.new()};self.states[key]=value end
 value.used=now
 return value.model
end
function R:draw_encounter(frame,encounter,now)
 local sw,sh=self.b:dimensions()
 local base=model.layout(sw,sh,self.c)
 if not base then return false end
 local height=(styles[self.c.style] and styles[self.c.style].height) or 145
 if encounter.mode=='twins' then
  local count=#encounter.bars
  if count==0 then return false end
  local scale=math.min(base.scale,(sw-16)/(620*count+16*(count-1)))
  local total=(620*count+16*(count-1))*scale
  local x=math.max(8,math.min(sw-total-8,base.x+base.width/2-total/2))
  for i,n in ipairs(encounter.bars) do
   local l={x=x+(i-1)*636*scale,y=base.y,scale=scale,width=620*scale,height=height*scale}
   if not self:draw(frame.sb,n.life,n.max,n.icon,0,0,n,now,l) then return false end
  end
  self.last_layout={x=x,y=base.y,scale=scale,width=total,height=height*scale}
  return true
 end
 local count=#encounter.parts
 if count==0 then return self:draw(frame.sb,frame.life,frame.max,frame.icon,frame.shield,frame.shieldmax,frame.tracking,now) end
 local rows=math.ceil(count/2)
 local extra=8+rows*40
 local scale=math.min(base.scale,(sh-16)/(height+extra))
 local total=(height+extra)*scale
 local y=math.max(8,math.min(base.y-extra*scale,sh-total-8))
 local l={x=math.max(8,math.min(sw-620*scale-8,base.x+base.width/2-310*scale)),y=y,scale=scale,width=620*scale,height=height*scale}
 if not self:draw(frame.sb,frame.life,frame.max,frame.icon,frame.shield,frame.shieldmax,frame.tracking,now,l) then return false end
 self:draw_parts(frame.sb,encounter.parts,l,now)
 return true
end
function R:draw_parts(sb,parts,l,now)
 local b,a=self.b,self.a
 local colors=self.colors
 local style=self.variants[self.c.style]
 local tint=style and style.colors.fill or colors.red
 local texts={}
 local function fill(x,y,w,h,color)
  b:draw_sprite(sb,a.white,x,y,w,h,self.src.white,color)
 end
 local s=l.scale
 local width=(l.width-12*s)/2
 for i,n in ipairs(parts) do
  local col,row=(i-1)%2,math.floor((i-1)/2)
  local x=l.x+col*(width+12*s)
  local y=l.y+l.height+8*s+row*40*s
  local state=self:state_for(n.key,now)
  local ratio=state:update(n.key,n.life,n.max,now) or 0
  fill(x,y+24*s,width,8*s,colors.dark)
  if self.c.damage_trail and state.trail>ratio then fill(x,y+24*s,width*state.trail,8*s,colors.trail) end
  fill(x,y+24*s,width*ratio,8*s,tint)
  local status=n.defeated and ' [已击破]' or n.locked and ' [无敌]' or ''
  texts[#texts+1]={n.name..status,x,y,colors.gold,0.70*s,0}
  texts[#texts+1]={string.format('%d/%d',math.floor(n.life),math.floor(n.max)),x+width,y,colors.white,0.68*s,1}
 end
 for _,t in ipairs(texts) do b:draw_text(sb,t[1],t[2],t[3],t[4],t[5],t[6]) end
end

return R
