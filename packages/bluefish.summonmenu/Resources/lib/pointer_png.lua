-- Bounded PNG decoder for replaceable pointer assets; Lua 5.3+.
local M={}
local function inflate(s,limit)
 assert(#s>=6,'zlib truncated')
 local cmf,flg=s:byte(1,2)
 assert(cmf&15==8 and cmf>>4<=7 and (cmf*256+flg)%31==0 and flg&32==0,'unsupported zlib')
 local pos,bits,nb=3,0,0
 local function read(n)
  while nb<n do assert(pos<=#s-4,'deflate truncated');bits=bits|(s:byte(pos)<<nb);pos=pos+1;nb=nb+8 end
  local v=bits&((1<<n)-1);bits=bits>>n;nb=nb-n;return v
 end
 local function tree(lens)
  local counts,nextcode,t={}, {}, {}
  for _,n in ipairs(lens) do if n>0 then assert(n<=15);counts[n]=(counts[n] or 0)+1 end end
  local code=0
  for n=1,15 do code=(code+(counts[n-1] or 0))*2;nextcode[n]=code;t[n]={};assert(code+(counts[n] or 0)<=1<<n,'invalid Huffman tree') end
  for i,n in ipairs(lens) do if n>0 then t[n][nextcode[n]]=i-1;nextcode[n]=nextcode[n]+1 end end
  return t
 end
 local function symbol(t)
  local code=0
  for n=1,15 do code=code*2+read(1);local v=t[n][code];if v~=nil then return v end end
  error('invalid Huffman code')
 end
 local lb={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
 local le={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
 local db={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
 local de={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
 local out={}
 local function push(v) assert(#out<limit,'inflated PNG too large');out[#out+1]=v end
 local last
 repeat
  last=read(1);local kind=read(2)
  if kind==0 then
   bits,nb=0,0;local n=read(16);assert(read(16)==(n~65535),'stored block length')
   for i=1,n do push(read(8)) end
  else
   assert(kind~=3,'invalid deflate block');local lt,dt
   if kind==1 then
    local l,d={},{};for i=0,287 do l[i+1]=i<=143 and 8 or i<=255 and 9 or i<=279 and 7 or 8 end
    for i=1,32 do d[i]=5 end;lt,dt=tree(l),tree(d)
   else
    local nl,nd,nc=read(5)+257,read(5)+1,read(4)+4;assert(nl<=286)
    local order={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
    local c={};for i=1,19 do c[i]=0 end;for i=1,nc do c[order[i]+1]=read(3) end
    local ct=tree(c);local l={}
    while #l<nl+nd do
     local v=symbol(ct)
     if v<16 then l[#l+1]=v else
      local count,value
      if v==16 then assert(#l>0);count,value=read(2)+3,l[#l]
      elseif v==17 then count,value=read(3)+3,0 else count,value=read(7)+11,0 end
      assert(#l+count<=nl+nd,'length repeat overflow');for i=1,count do l[#l+1]=value end
     end
    end
    local ll,dd={},{};for i=1,nl do ll[i]=l[i] end;for i=1,nd do dd[i]=l[nl+i] end
    assert(ll[257]>0,'missing end code');lt,dt=tree(ll),tree(dd)
   end
   while true do
    local v=symbol(lt)
    if v<256 then push(v) elseif v==256 then break else
     assert(v<=285);local i=v-256;local n=lb[i]+read(le[i]);local d=symbol(dt)+1
     assert(d<=30);local distance=db[d]+read(de[d]);assert(distance<=#out,'invalid backreference')
     for j=1,n do push(out[#out-distance+1]) end
    end
   end
  end
 until last==1
 local a,b=1,0;for _,v in ipairs(out) do a=(a+v)%65521;b=(b+a)%65521 end
 assert((b<<16|a)==string.unpack('>I4',s,#s-3),'PNG checksum mismatch')
 return out
end
function M.decode(s)
 assert(type(s)=='string' and #s<=2097152,'PNG file too large')
 assert(s:sub(1,8)=='\137PNG\13\10\26\10','not a PNG')
 local p=9;local w,h,depth,kind,palette,trans;local chunks={};local ended=false
 while p<=#s do
  assert(p+11<=#s,'truncated PNG chunk');local n=string.unpack('>I4',s,p);local tag=s:sub(p+4,p+7)
  assert(p+11+n<=#s,'truncated PNG data');local data=s:sub(p+8,p+7+n);p=p+n+12
  if tag=='IHDR' then
   assert(not w and n==13);local comp,filter,inter
   w,h,depth,kind,comp,filter,inter=string.unpack('>I4I4BBBBB',data)
   assert(w>0 and h>0 and w<=256 and h<=256,'PNG dimensions must be 1..256')
   assert(comp==0 and filter==0 and inter==0,'interlaced PNG unsupported')
  elseif tag=='PLTE' then palette=data elseif tag=='tRNS' then trans=data
  elseif tag=='IDAT' then assert(w);chunks[#chunks+1]=data
  elseif tag=='IEND' then ended=true;break end
 end
 assert(w and ended and #chunks>0,'incomplete PNG')
 local channels=({[0]=1,[2]=3,[3]=1,[4]=2,[6]=4})[kind];assert(channels,'PNG color type unsupported')
 assert(depth==8 or (depth==16 and kind~=3) or (kind==3 and (depth==1 or depth==2 or depth==4)),'unsupported PNG bit depth')
 if kind==3 then assert(palette and #palette%3==0,'missing palette') end
 local stride=math.ceil(w*channels*depth/8);local bpp=math.max(1,math.ceil(channels*depth/8))
 local raw=inflate(table.concat(chunks),(stride+1)*h);assert(#raw==(stride+1)*h,'PNG row size mismatch')
 local rgba,previous={},{};local idx=1
 local function paeth(a,b,c)
  local v=a+b-c;local aa,bb,cc=math.abs(v-a),math.abs(v-b),math.abs(v-c)
  return aa<=bb and aa<=cc and a or bb<=cc and b or c
 end
 for y=1,h do
  local f=raw[idx];idx=idx+1;assert(f<=4,'invalid PNG filter');local row={}
  for x=1,stride do
   local a,b,c=row[x-bpp] or 0,previous[x] or 0,previous[x-bpp] or 0
   local v=raw[idx];idx=idx+1
   if f==1 then v=v+a elseif f==2 then v=v+b elseif f==3 then v=v+math.floor((a+b)/2) elseif f==4 then v=v+paeth(a,b,c) end
   row[x]=v%256
  end
  for x=0,w-1 do
   local r,g,b,a;local j=x*channels+1
   local maximum=depth==16 and 65535 or 255
   local function sample(i)
    if depth==16 then local k=(i-1)*2+1;return row[k]*256+row[k+1] end
    return row[i]
   end
   if kind==6 then r,g,b,a=sample(j),sample(j+1),sample(j+2),sample(j+3)
   elseif kind==2 then r,g,b,a=sample(j),sample(j+1),sample(j+2),maximum
    if trans and #trans==6 then local tr,tg,tb=string.unpack('>I2I2I2',trans);if r==tr and g==tg and b==tb then a=0 end end
   elseif kind==3 then
    local bit=x*depth;local v=(row[math.floor(bit/8)+1]>>(8-depth-bit%8))&((1<<depth)-1)
    r,g,b=palette:byte(v*3+1,v*3+3);assert(b,'invalid palette index');a=trans and trans:byte(v+1) or 255
   else r=sample(j);g,b,a=r,r,kind==4 and sample(j+1) or maximum
    if kind==0 and trans and #trans==2 and r==string.unpack('>I2',trans) then a=0 end
   end
   -- 透明色比较保留完整16位精度，随后舍入到绘制接口的8位颜色。
   if depth==16 then
    r,g,b,a=math.floor(r/257+0.5),math.floor(g/257+0.5),math.floor(b/257+0.5),math.floor(a/257+0.5)
   end
   local q=a/255;rgba[#rgba+1]={r*q,g*q,b*q,a}
  end
  previous=row
 end
 return {width=w,height=h,pixels=rgba}
end
return M
