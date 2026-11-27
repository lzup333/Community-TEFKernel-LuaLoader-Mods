-- Geometry only. Every blueprint composes its own silhouette and circulation.
-- IDs verified against the supplied Terraria 1.4.5.8 TileID/WallID sources:
-- wood30, grayBrick38, glass wall21, wood wall4 and grayBrick wall5.
local C={}
function C.line(b,x1,y1,x2,y2,id)
 local n=math.max(math.abs(x2-x1),math.abs(y2-y1))
 for i=0,n do local k=n==0 and 0 or i/n;b:tile(math.floor(x1+(x2-x1)*k+.5),math.floor(y1+(y2-y1)*k+.5),id) end
end
function C.fill(b,l,top,r,bottom,id,wall)
 for y=top,bottom do for x=l,r do if wall then b:wall(x,y,id) else b:tile(x,y,id) end end end
end
function C.hall(b,l,top,r,f,t)
 C.fill(b,l+1,top+1,r-1,f-1,t.wall,true)
 C.line(b,l,top,r,top,t.block);C.line(b,l,f,r,f,t.block)
 C.line(b,l,top,l,f,t.beam);C.line(b,r,top,r,f,t.beam)
end
function C.door(b,x,f,t)
 b:tile(x,f-4,t.beam) -- closed doors require a solid lintel as well as a floor
 for y=f-3,f-1 do b:erase(x,y);b:wall(x,y,t.wall) end
 b:object('door',x,f-3,1,3,10)
end
function C.window(b,l,top,r,bottom,o)
 if o.decor then C.fill(b,l,top,r,bottom,21,true) end
end
function C.station(b,l,r,f,o,kind)
 b.stations[#b.stations+1]={l=l,r=r,f=f,kind=kind or 'living'}
end
function C.furnish(b,o,t)
 local dims={table={3,2,14},chair={1,2,15},chest={2,2,21},workbench={2,1,18},furnace={3,2,17},anvil={2,1,16}}
 for _,s in ipairs(b.stations) do
  local kinds=s.kind=='storage' and {'chest','chest','chest','chest','chest'} or s.kind=='work' and {'workbench','furnace','anvil','chest'} or {'table','chair','chest'}
  local cursor=s.l
  if o.furniture then for _,kind in ipairs(kinds) do
   local d=dims[kind]
   for x=cursor,s.r-d[1]+1 do
    if b:freeObject(x,s.f-d[2],d[1],d[2],true) then b:object(kind,x,s.f-d[2],d[1],d[2],d[3]);cursor=x+d[1]+2;break end
   end
  end end
  for x=s.l,s.r do if b:freeObject(x,s.f-5,1,1,false) and (b.map[x..','..(s.f-5)] or {}).wall then b:object('torch',x,s.f-5,1,1,4);break end end
 end
end
return C
