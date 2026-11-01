-- Keep Chinese and Latin/numeric labels in ONE native text draw layer.
local T={nativeScale=1}
local function convert(s)return s end
function T.begin()end
local function charWidth(cp,size)
 if cp==32 then return size*.5 end
 if cp<128 then return size*.56 end
 return size
end
function T.width(s,size)
 local w=0;for _,cp in utf8.codes(s)do w=w+charWidth(cp,size)end;return w
end
function T.fit(s,size,width)
 if T.width(s,size)<=width then return s end
 local a,w={},0
 for _,cp in utf8.codes(s)do local n=charWidth(cp,size)
  if w+n+size*.56*3>width then break end;a[#a+1]=utf8.char(cp);w=w+n
 end
 return table.concat(a)..'...'
end
function T.draw(g,x,y,s,size,color,scale)
 if s~=''then g.text_at(x*scale,y*scale,convert(s),color,size*scale/20)end
end
function T.finish()end
T.convert=convert
return T
