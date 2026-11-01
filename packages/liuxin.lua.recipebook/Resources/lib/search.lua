local initials=require('initials')
local pinyin=require('pinyin')
local S={cache={}}
function S.normalize(s)return (s:lower():gsub('[%s%p]',''))end
function S.initials(s)
 local a={};for _,cp in utf8.codes(s)do a[#a+1]=initials[cp]or utf8.char(cp)end
 return S.normalize(table.concat(a))
end
function S.fullPinyin(s)
 local a={};for _,cp in utf8.codes(s)do
  if cp<128 then a[#a+1]=utf8.char(cp):lower()
  else a[#a+1]=pinyin[cp]or initials[cp]or utf8.char(cp)end
 end
 return S.normalize(table.concat(a))
end
function S.match(id,name,alias,q)
 q=S.normalize(q);if q==''then return true end
 local c=S.cache[id]
 if not c or c.name~=name or c.alias~=(alias or'') then
  c={name=name,alias=alias or'',full=S.normalize(name),short=S.initials(name),pinyin=S.fullPinyin(name),other=S.normalize(alias or''),id=tostring(id)}
  S.cache[id]=c
 end
 return c.full:find(q,1,true)~=nil or c.short:find(q,1,true)~=nil or c.pinyin:find(q,1,true)~=nil or c.other:find(q,1,true)~=nil or c.id:find(q,1,true)~=nil
end
function S.asciiChars(id,name,alias)
 local c=S.cache[id]
 if not c or c.name~=name or c.alias~=(alias or'')then
  c={name=name,alias=alias or'',full=S.normalize(name),short=S.initials(name),pinyin=S.fullPinyin(name),other=S.normalize(alias or''),id=tostring(id)}
  S.cache[id]=c
 end
 local seen,out={},{}
 for _,s in ipairs({c.full,c.short,c.pinyin,c.other,c.id})do
  for ch in s:gmatch('[a-z0-9]')do if not seen[ch]then seen[ch]=true;out[#out+1]=ch end end
 end
 return out
end
return S
