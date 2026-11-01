local C=require('core')
local N={}
function N.task(key)return type(key)=='string'and(key=='contract'or key:match('^contract:')~=nil or key=='mail'or key:match('^mail:')~=nil)end
function N.format(text)
 local title,body=text:match('^【(.-)】%s*(.*)$')
 if not title then return text end
 return '━━ '..title..' ━━\n'..body
end
N.biomes={forest='森林',desert='沙漠',snow='雪原',jungle='丛林',hallow='神圣',corrupt='腐化',crimson='猩红'}
function N.skill(tier,name,summary,style,combatStyle)
 local titles={'异化体显现','灾变体现身','终焉体降临'}
 local identity=name..(combatStyle and('〔'..require('styles').names[combatStyle]..'〕')or'')
 return '【'..(titles[tier]or '重构体出现')..'】\n目标：'..identity..'\n招式：'..summary
end
function N.environment(e)
 local depth=e.hell and '地狱' or e.underground and '地下 / 洞穴' or '地表'
 local location=e.special~='' and (e.special..' · '..depth) or (N.biomes[e.biome] or '森林')..' · '..depth
 local conditions={e.night and '夜晚' or '白天'}
 for _,v in ipairs({{e.rain,'降雨'},{e.storm,'沙尘暴'},{e.wind,'大风'},{e.blood,'血月'},{e.eclipse,'日食'},{e.snowMoon,'霜月'},{e.pumpkinMoon,'南瓜月'},{e.slimeRain,'史莱姆雨'}}) do if v[1] then conditions[#conditions+1]=v[2] end end
 local state=location..'｜'..table.concat(conditions,' / ')
 return state,'【环境变化】\n位置：'..location..'\n时间 / 天气：'..table.concat(conditions,' / ')
end
return N
