local E={}
function E.category(d)
 if d.accessory==true then return '饰品' end
 if (d.head or -1)>=0 or (d.body or -1)>=0 or (d.legs or -1)>=0 then return '防具' end
 if (d.damage or 0)>0 and (d.ammo or 0)==0 and d.consumable~=true then return '武器/工具' end
end
function E.qualifies(d)
 local r=d.rare or 0
 return E.category(d)~=nil and r>=2 and r<=11
end
return E
