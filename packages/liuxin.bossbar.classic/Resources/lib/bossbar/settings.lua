-- TEFManager writes settings to the mod private directory's config.json.
-- The schema is defined in Info.json; the game mod only reads its saved value.
local S={}
function S.new(mod,config)
 local raw
 if mod.read_file then
  local ok,value=pcall(mod.read_file,'config.json')
  if ok and type(value)=='string' then raw=value end
 end
 local values=raw and raw:match('"values"%s*:%s*{(.-)}')
 local style=values and values:match('"bossbar_style"%s*:%s*"([AD])"')
 config.style=style or 'A'
 return config.style
end
return S
