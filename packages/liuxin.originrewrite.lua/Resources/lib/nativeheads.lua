-- 读取手机版SpriteFont字形贴图；通过已验证ref贴图接口绘制，绕开按值结构体桥接。
local N={};N.__index=N
function N.decode(raw)
 assert(type(raw)=='string'and #raw>=53,'glyph bytes')
 local x,y,w,h=string.unpack('<i4i4i4i4',raw,5)
 local cx,cy=string.unpack('<i4i4',raw,21)
 local left,right,width,advance=string.unpack('<ffff',raw,37)
 local texture=raw:byte(53)
 assert(w>=0 and h>=0 and w<=512 and h<=512 and advance==advance and math.abs(advance)<1024,'glyph bounds')
 return {character=string.unpack('<I2',raw),rect=raw:sub(5,20),x=cx,y=cy,left=left,width=width,advance=advance,texture=texture,w=w,h=h}
end
function N.new(p,log)
 local self=setmetatable({p=p,log=log,cache={},order={}},N)
 local ok,err=pcall(function()
  assert(p.array_at_raw and p.array_at and p.array_length,'missing raw glyph access')
  local font=assert(p.get_type('Microsoft.Xna.Framework.Graphics','SpriteFont'),'missing SpriteFont')
  local assets=assert(p.get_type('Terraria.GameContent','FontAssets'),'missing FontAssets')
  local generic=assert(p.get_type('ReLogic.Content','Asset`1'))
  self.fontField=assert(p.get_field(assets,'MouseText'))
  local asset=p.make_generic_type(generic,{font});self.valueField=p.get_field(asset,'Value');self.valueGetter=p.get_method(asset,'get_Value',0)
  assert(self.valueField or self.valueGetter,'missing font asset value')
  self.glyphField=assert(p.get_field(font,'_glyphs'));self.textureField=assert(p.get_field(font,'_textures'))
  self.spacing=p.get_method(font,'get_Spacing',0)
  self.available=true
 end)
 log('HEAD_NATIVE_ROUTE','available='..tostring(ok and self.available==true)..' method=SpriteFontAtlas'..(ok and ''or ' error='..tostring(err)))
 return self
end
function N:font()
 local p=self.p;local asset=p.get_field_value(self.fontField,nil,'object')
 local font=asset and(self.valueField and p.get_field_value(self.valueField,asset,'object')or p.invoke(self.valueGetter,asset))
 assert(font,'font unavailable');return font
end
-- LuaLoader PATCH_CHAR is one byte; do not pass Chinese UTF-16 values through invoke.
-- Read the stored two-byte Character directly, at most 128 glyphs per frame.
function N:pump(budget)
 local p=self.p;local font=self:font()
 if font~=self.fontHandle then self:clear();self.fontHandle=font end
 if not self.glyphArray then
  self.glyphArray=assert(p.get_field_value(self.glyphField,font,'object'))
  self.textures=assert(p.get_field_value(self.textureField,font,'object'))
  self.glyphCount=p.array_length(self.glyphArray);self.cursor=0;self.characters={}
 end
 for i=self.cursor,math.min(self.cursor+(budget or 128)-1,self.glyphCount-1)do
  local raw=assert(p.array_at_raw(self.glyphArray,i,56))
  self.characters[string.unpack('<I2',raw)]=raw;self.cursor=i+1
 end
end
function N:label(text)
 local p=self.p;local font=self.fontHandle
 if self.cache[text]then return self.cache[text]end
 if not self.characters then return nil end
 local textures=self.textures
 local spacing=self.spacing and p.invoke(self.spacing,font)or 0;assert(type(spacing)=='number','font spacing')
 local result={text=text,width=0,glyphs={}};local x=0;local lineY=0
 for _,cp in utf8.codes(text)do
  if cp==10 then result.width=math.max(result.width,x);x=0;lineY=lineY+24 else
  local raw=self.characters[cp]
  if not raw then return nil end -- Never substitute a Latin glyph for missing Chinese.
  local g=N.decode(raw);assert(g.texture<p.array_length(textures),'glyph texture index')
  if x>0 and x+spacing+g.advance>240 then x=0;lineY=lineY+24 end
  local texture=assert(p.array_at(textures,g.texture,'object'),'glyph texture')
  if #result.glyphs==0 then x=math.max(0,g.left)else x=x+spacing+g.left end
  if g.w>0 and g.h>0 then result.glyphs[#result.glyphs+1]={texture=texture,rect=g.rect,x=x+g.x,y=g.y+lineY}end
  x=x+g.advance-g.left;result.width=math.max(result.width,x)
  end
 end
 result.height=lineY+24
 if #self.order>=64 then self.cache[table.remove(self.order,1)]=nil end
 self.order[#self.order+1]=text;self.cache[text]=result;return result
end
function N:render(batch,label,x,y,color,drawGlyph,shadow)
 if not self.available then return false end
 local ok,err=pcall(function()
  assert(type(drawGlyph)=='function','missing ref glyph draw')
  local left=math.floor(x-label.width/2)
  for _,g in ipairs(label.glyphs)do
   if shadow~=false then drawGlyph(batch,g.texture,left+g.x+1,y+g.y+1,g.rect,string.char(255,18,14,12))end
   drawGlyph(batch,g.texture,left+g.x,y+g.y,g.rect,color)
  end
 end)
 if not ok then self.available=false;self.log('HEAD_NATIVE_DISABLED',tostring(err));return false end
 return true
end
function N:clear()self.cache={};self.order={};self.fontHandle=nil;self.glyphArray=nil;self.textures=nil;self.characters=nil;self.cursor=0 end
return N
