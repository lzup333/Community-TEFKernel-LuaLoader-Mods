-- Some vanilla event bosses and boss parts do not set NPC.boss.
local G={}
local excluded={}
for _,id in ipairs({
 4,13,14,15,35,36,50,113,114,115,125,126,127,128,129,130,131,
 134,135,136,222,245,246,247,248,249,262,263,264,265,266,
 370,396,397,398,400,439,440,454,455,456,457,458,459,
 636,657,668,
 -- Pumpkin Moon: Mourning Wood, Pumpking and blade.
 325,327,328,
 -- Frost Moon: Everscream, Santa-NK1, Ice Queen.
 344,345,346,
 -- Invasion bosses and lunar pillars.
 395,422,493,507,517,551,564,576
}) do excluded[id]=true end
function G.isBoss(r,n)
 return r:n(n,'boss','bool',false) or excluded[r:n(n,'type','int32',0)]==true
end
return G
