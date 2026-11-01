local C=require('templates.common')
return function(b,o)
 if o.style==1 then
  -- Low living-wood room with a leafy outline and a door at the right.
  local t={block=191,wall=4,beam=191}
  C.hall(b,-4,-5,4,0,t)
  C.line(b,-4,-5,4,-5,192)
  for y=-4,-2 do b:tile(-4,y,192);b:tile(4,y,192) end
  C.door(b,4,0,t)
  if o.furniture then
   b:object('table',-3,-2,3,2,14)
   b:object('chair',1,-2,1,2,15)
  end
  b:object('torch',3,-4,1,1,4)
 elseif o.style==2 then
  -- Gray-brick living room above spaced platform footholds.
  local t={block=38,wall=5,beam=38}
  C.hall(b,-4,-14,4,-6,t)
  -- The screenshot has an opening at the lower right, with separated steps.
  for x=1,2 do b:tile(x,-6,19) end
  if o.furniture then
   b:object('chair',-3,-8,1,2,15)
   b:object('workbench',-1,-7,2,1,18)
  end
  b:object('torch',3,-9,1,1,4)
  for y=-4,-2 do
   for _,x in ipairs{-4,4} do b:tile(x,y,19) end
  end
  C.line(b,-4,0,4,0,38)
 else
  -- Brick lintel and floor; the two sides are vertically stacked platforms.
  local t={block=152,wall=35,beam=152}
  C.hall(b,-2,-12,2,0,t)
  for y=-11,-1 do b:tile(-2,y,19);b:tile(2,y,19) end
  if o.furniture then
   b:object('chair',-1,-2,1,2,15)
   b:object('workbench',0,-1,2,1,18)
  end
  b:object('torch',0,-6,1,1,4)
 end
end
