-- 有界文本协议；不执行远端Lua，不接受客户端写战斗状态。
local C={prefix='ORW2|',version='2.4.1',maxBytes=4096}
local fields={
 {'slot','n',0,199},{'type','n',1,2000},{'generation','n',1,2147483647},
 {'tier','n',0,3},{'stage','n',1,5},{'max','n',1,100000000},{'damage','n',0,10000000},
 {'defense','n',-1000000,1000000},{'scale','n',.01,100},{'knock','n',0,10},{'alpha','n',0,255},
 {'headText','s',512},{'skillSummary','s',768},{'displayName','s',768},{'style','s',32},
 {'phase','s',32},{'action','s',32},{'pattern','s',128},{'echoWarning','n',0,1},{'breakable','n',0,1},
 {'guardCounter','n',0,1},{'ghostLeft','n',0,120},{'g1x','n',-1000000,1000000},{'g1y','n',-1000000,1000000},
 {'g2x','n',-1000000,1000000},{'g2y','n',-1000000,1000000},{'helper','n',0,1},
}
function C.hex(s)return(s:gsub('.',function(c)return('%02x'):format(c:byte())end))end
function C.unhex(s,max)
 if type(s)~='string'or #s%2~=0 or #s>(max or 1024)*2 or s:find('[^0-9a-f]')then return end
 return(s:gsub('..',function(v)return string.char(tonumber(v,16))end))
end
local function number(s,min,max)
 local n=tonumber(s);if not n or n~=n or n<min or n>max then return end;return n
end
function C.encode(v)
 local out={}
 for _,f in ipairs(fields)do
  local x=v[f[1]]
  if f[2]=='s'then x=C.hex(tostring(x or ''):sub(1,f[3]))
  else x=x or 0;if not number(x,f[3],f[4])then return end;x=(f[1]=='scale'or f[1]=='knock')and ('%.8g'):format(x)or tostring(math.floor(x))end
  out[#out+1]=x
 end
 return table.concat(out,',')
end
function C.decode(raw)
 if type(raw)~='string'or #raw>C.maxBytes then return end
 local cells={};for x in (raw..','):gmatch('(.-),')do cells[#cells+1]=x;if #cells>#fields then return end end
 if #cells~=#fields then return end
 local v={}
 for i,f in ipairs(fields)do
  local x
  if f[2]=='s'then x=C.unhex(cells[i],f[3])else x=number(cells[i],f[3],f[4])end
  if x==nil then return end
  if f[2]=='n'and f[1]~='scale'and f[1]~='knock'and x%1~=0 then return end
  v[f[1]]=x
 end
 if (v.tier==0)~=(v.helper==1)then return end
 return v
end
function C.pack(world,epoch,sequence,kind,body)
 local raw=C.prefix..world..'|'..epoch..'|'..sequence..'|'..kind..'|'..(body or '')
 if #raw>C.maxBytes then return end;return raw
end
function C.unpack(raw)
 if type(raw)~='string'or #raw>C.maxBytes then return end
 local w,e,q,k,body=raw:match('^ORW2|([%-]?%d+)|([%w_-]+)|(%d+)|([A-Z]+)|(.*)$')
 w=number(w,-2147483648,2147483647);q=number(q,1,2147483647)
 if not w or not q or #e>64 then return end
 return w,e,q,k,body
end
return C
