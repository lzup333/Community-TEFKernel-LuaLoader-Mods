-- Cached PNG schematic, generated from saved cells rather than the live camera.
local M={}
local crcTable={}
for n=0,255 do local c=n;for _=1,8 do c=(c&1)~=0 and ((c>>1)~0xedb88320) or (c>>1) end;crcTable[n]=c end
local function crc(s)local c=0xffffffff;for i=1,#s do c=(c>>8)~crcTable[(c~s:byte(i))&255] end;return (~c)&0xffffffff end
local function chunk(kind,raw)return string.pack('>I4',#raw)..kind..raw..string.pack('>I4',crc(kind..raw)) end
local materials={[0]={114,89,63},[1]={124,128,140},[30]={155,111,69},[38]={125,131,140},[321]={125,92,64},[311]={161,105,61},[479]={200,163,99},[151]={196,159,89},[19]={164,120,75},[147]={228,240,246},[171]={36,139,76},[405]={160,86,52},[406]={116,110,111},[149]={225,105,71},[101]={155,112,65},[88]={156,116,76},[312]={192,78,61},[313]={66,109,164}}
local paints={{255,75,75},{255,145,65},{255,220,65},{170,235,70},{65,205,70},{65,225,155},{70,220,230},{70,155,240},{85,90,230},{150,75,235},{220,75,230},{240,75,155}}
local function color(c)
 if (c.header & 0x20)==0 then if c.wall==0 then return 24,34,45 end;if c.wall==21 or c.wall==90 then return 106,152,183 elseif c.wall==313 then return 186,112,51 elseif c.wall==38 then return 91,112,106 elseif c.wall==149 or c.wall==115 then return 87,67,48 end;return 79,65,57 end
 local paint=c.header & 31;local rgb=materials[c.type] or {184,167,118}
 if paint>=1 and paint<=12 then rgb=paints[paint] elseif paint>=13 and paint<=24 then local a=paints[paint-12];return a[1]//2,a[2]//2,a[3]//2 elseif paint==25 then return 32,32,32 elseif paint==26 then return 235,235,235 elseif paint==27 then return 124,124,124 end
 return rgb[1],rgb[2],rgb[3]
end
function M.schematic(bp)
 local runs={}
 for y=0,bp.height-1 do
  local first=0;local previous
  for x=0,bp.width do
   local r,g,b
   if x<bp.width then r,g,b=color(bp.cells[y*bp.width+x+1]) end
   if previous and (x==bp.width or r~=previous[1] or g~=previous[2] or b~=previous[3]) then
    runs[#runs+1]={x=first,y=y,w=x-first,color={previous[1],previous[2],previous[3],255}}
   end
   if x<bp.width and (not previous or r~=previous[1] or g~=previous[2] or b~=previous[3]) then
    first=x;previous={r,g,b}
   end
  end
 end
 return {width=bp.width,height=bp.height,runs=runs}
end
function M.png(bp)
 local scale=math.max(1,math.min(4,math.floor(192/bp.width),math.floor(96/bp.height)))
 local w,h=bp.width*scale,bp.height*scale;local rows={}
 for y=0,bp.height-1 do
  local row={'\0'}
  for x=0,bp.width-1 do
   local c=bp.cells[y*bp.width+x+1];local r,g,b=color(c);row[#row+1]=string.rep(string.char(r,g,b),scale)
  end
  row=table.concat(row);for _=1,scale do rows[#rows+1]=row end
 end
 local raw=table.concat(rows);local blocks={'\120\1'};local pos=1
 while pos<=#raw do local part=raw:sub(pos,pos+65534);pos=pos+#part;blocks[#blocks+1]=string.char(pos>#raw and 1 or 0)..string.pack('<I2I2',#part,(~#part)&65535)..part end
 local a,b=1,0;for i=1,#raw do a=(a+raw:byte(i))%65521;b=(b+a)%65521 end
 blocks[#blocks+1]=string.pack('>I4',(b<<16)|a)
 return '\137PNG\13\10\26\10'..chunk('IHDR',string.pack('>I4I4BBBBB',w,h,8,2,0,0,0))..chunk('IDAT',table.concat(blocks))..chunk('IEND','')
end
return M
