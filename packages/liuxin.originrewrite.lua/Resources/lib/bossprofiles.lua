local profiles={
 [4]={name='克苏鲁之眼',kind='eye',min=180,max=520,warning=48,duration=18,speed=9},
 [50]={name='史莱姆王',kind='jump',min=120,max=480,warning=36,duration=12,speed=5},
 [266]={name='克苏鲁之脑',kind='brain',min=90,max=460,warning=42,duration=16,speed=7},
 [125]={name='激光眼',kind='laser',min=150,max=680,warning=42,duration=16,speed=8,style=30},
 [126]={name='魔焰眼',kind='flame',min=160,max=680,warning=42,duration=14,speed=9,style=31},
 [127]={name='机械骷髅王',kind='prime',min=160,max=680,warning=48,duration=16,speed=7,style=32},
 [134]={name='毁灭者',kind='worm',min=240,max=680,warning=24,duration=20,speed=0,style=37},
 [222]={name='蜂王',kind='bee',min=180,max=620,warning=36,duration=12,speed=6,style=43},
 [657]={name='史莱姆皇后',kind='queen',min=140,max=600,warning=36,duration=12,speed=6,style=121},
 [370]={name='猪龙鱼公爵',kind='fish',min=200,max=680,warning=24,duration=6,speed=8,style=69},
 [262]={name='世纪之花',kind='plant',min=180,max=620,warning=30,duration=12,speed=0,style=51},
 [245]={name='石巨人',kind='golem',min=160,max=520,warning=36,duration=10,speed=3,style=45,jumpVY=6},
 [668]={name='独眼巨鹿',kind='walker',min=160,max=440,warning=30,duration=12,speed=2.5,style=123},
 [35]={name='骷髅王',kind='head',min=120,max=480,warning=48,duration=16,speed=7}
}
-- Sources for mechanical encounters: https://terraria.wiki.gg/wiki/The_Twins
-- https://terraria.wiki.gg/wiki/The_Destroyer
-- https://terraria.wiki.gg/wiki/Skeletron_Prime
-- Additional mechanics: https://terraria.wiki.gg/wiki/Queen_Bee
-- https://terraria.wiki.gg/wiki/Queen_Slime
-- https://terraria.wiki.gg/wiki/Duke_Fishron
-- Experimental state windows must be checked against the target mobile version.
-- Wiki describes encounter semantics; AI indices remain version-specific adapters.
-- Sources: https://terraria.wiki.gg/wiki/King_Slime
-- https://terraria.wiki.gg/wiki/Eye_of_Cthulhu
-- https://terraria.wiki.gg/wiki/Brain_of_Cthulhu
-- https://terraria.wiki.gg/wiki/Skeletron
for id,a in pairs(require('bosslate').profiles)do profiles[id]=a end
for _,id in ipairs({125,126,127,134}) do profiles[id].night=true end
function profiles.stage(kind,phase,step,r,n)
 if kind=='plant' then return r:n(n,'life','int32',0)/math.max(1,r:n(n,'lifeMax','int32',1))<=.5 and 'second' or 'first' end
 if kind=='golem' then return r:n(n,'dontTakeDamage','bool',true) and 'protected_body' or 'exposed_body' end
 if kind=='walker' then return 'ground_fighter' end
 if kind=='bee' then return 'hive' end
 if kind=='queen' then return r:n(n,'noGravity','bool',false) and 'winged' or 'ground' end
 if kind=='fish' then return phase>=10 and 'third' or (phase==4 or phase==9) and 'transition' or phase>=5 and 'second' or 'first' end
 if kind=='brain' then return phase<0 and 'exposed' or 'creepers' end
 if kind=='laser' or kind=='flame' then return phase==0 and 'first' or phase==3 and 'second' or 'transform' end
 if kind=='prime' then return 'head' end
 if kind=='worm' then return 'linked_worm' end
 if kind=='eye' then return phase==0 and 'first' or phase==3 and 'second' or 'transform' end
 if kind=='head' then return 'head' end
 return 'jump'
end
return profiles
