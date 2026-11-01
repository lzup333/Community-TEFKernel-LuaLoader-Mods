local C=require('templates.common')
return function(b,o,t)
 C.hall(b,-11,-11,10,0,t)
 C.door(b,-11,0,t)
 C.window(b,1,-8,5,-5,o)
 C.station(b,-7,8,0,o)
end
