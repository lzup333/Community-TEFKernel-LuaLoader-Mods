local defaults=require('config')
local JSON=require('json')
local S={}
local lastRaw
function S.normalize(input)
 local c={};for k,v in pairs(defaults) do
  local x=input and input[k]
  if type(v)=='number' and type(x)=='string' then x=tonumber(x) end
  if type(x)==type(v) then c[k]=x else c[k]=v end
 end
 local function clamp(k,low,high) local x=c[k];if x~=x then x=defaults[k] end;c[k]=math.max(low,math.min(high,math.floor(x+0.5))) end
 clamp('summary_tone',1,5);clamp('summary_style',1,3);clamp('home_distance',10,150);clamp('depart_distance',30,300)
 c.depart_distance=math.max(c.depart_distance,c.home_distance+20)
 clamp('depart_seconds',1,10);clamp('home_seconds',2,20);clamp('autosave_seconds',5,120)
 return c
end
function S.load()
 local raw=mod.read_file('config.json')
 if raw then
  local obj=JSON.decode(raw)
  if type(obj)=='table' and type(obj.values)=='table' then lastRaw=raw;return S.normalize(obj.values) end
 end
 -- Import previous in-game settings only when there is no valid manager file.
 local legacy=mod.read_file('settings.lua');local input
 if legacy and #legacy<16000 then local f=load('return '..legacy,'settings','t',{});if f then local ok,v=pcall(f);if ok and type(v)=='table' then input=v end end end
 return S.normalize(input)
end
function S.poll()
 local raw=mod.read_file('config.json')
 if not raw or raw==lastRaw then return end
 local obj,e=JSON.decode(raw)
 if type(obj)~='table' or type(obj.values)~='table' then return nil,e or '配置缺少values对象' end
 lastRaw=raw;return S.normalize(obj.values)
end
function S.save(config)
 local c=S.normalize(config);local values={}
 for k,v in pairs(c) do values[k]=v end
 -- CHOICE option values are strings in TEFManager's schema.
 values.summary_style=tostring(values.summary_style)
 values.summary_tone=tostring(values.summary_tone)
 local raw=JSON.encode({schemaVersion=1,values=values})
 local ok,e=mod.write_file('config.json',raw)
 if ok then lastRaw=raw end
 return ok,e
end
return S
