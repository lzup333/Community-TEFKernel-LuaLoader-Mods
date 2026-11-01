-- Small pure Lua JSON codec for the manager's configuration file.
local M={}
function M.decode(raw)
 if type(raw)~='string' or #raw>65536 then return nil,'配置过大或不是文本' end
 local i,depth=1,0
 local function ws() local _,last=raw:find('^[ \n\r\t]*',i);i=(last or i-1)+1 end
 local parse
 local function str()
  assert(raw:sub(i,i)=='"','需要字符串');i=i+1;local out={}
  while i<=#raw do
   local c=raw:sub(i,i);i=i+1
   if c=='"' then return table.concat(out) end
   if c=='\\' then
    local e=raw:sub(i,i);i=i+1
    local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
    if escapes[e] then out[#out+1]=escapes[e]
    elseif e=='u' then
     local h=raw:sub(i,i+3);assert(h:match('^%x%x%x%x$'),'Unicode转义无效');i=i+4;local cp=tonumber(h,16)
     if cp>=0xd800 and cp<=0xdbff then
      assert(raw:sub(i,i+1)=='\\u','缺少低代理');i=i+2
      local low=tonumber(raw:sub(i,i+3),16);assert(low and low>=0xdc00 and low<=0xdfff,'低代理无效');i=i+4
      cp=0x10000+(cp-0xd800)*1024+low-0xdc00
     else assert(cp<0xdc00 or cp>0xdfff,'孤立代理') end
     out[#out+1]=utf8.char(cp)
    else error('转义无效') end
   else assert(c:byte()>=32,'字符串包含控制字符');out[#out+1]=c end
  end
  error('字符串未结束')
 end
 parse=function()
  ws();depth=depth+1;assert(depth<=16,'嵌套过深')
  local c=raw:sub(i,i);local v
  if c=='"' then v=str()
  elseif c=='{' or c=='[' then
   local object=c=='{';local close=object and '}' or ']';v={};i=i+1;ws()
   if raw:sub(i,i)~=close then
    while true do
     local key
     if object then key=str();ws();assert(raw:sub(i,i)==':','缺少冒号');i=i+1 else key=#v+1 end
     v[key]=parse();ws();local sep=raw:sub(i,i)
     if sep==close then break end
     assert(sep==',','缺少逗号');i=i+1;ws()
    end
   end;i=i+1
  elseif raw:sub(i,i+3)=='true' then v=true;i=i+4
  elseif raw:sub(i,i+4)=='false' then v=false;i=i+5
  elseif raw:sub(i,i+3)=='null' then v=nil;i=i+4
  else
   local token=raw:match('^%-?%d+%.?%d*[eE]?[+%-]?%d*',i)
   v=token and tonumber(token);assert(v and v==v and math.abs(v)<math.huge,'数值无效');i=i+#token
  end
  depth=depth-1;return v
 end
 local ok,v=pcall(function() local result=parse();ws();assert(i>#raw,'末尾多余内容');return result end)
 if ok then return v end;return nil,tostring(v)
end
local function quote(s)
 return '"'..s:gsub('[%z\1-\31\\"]',function(c)
  if c=='\\' then return '\\\\' elseif c=='"' then return '\\"' end
  return string.format('\\u%04x',c:byte())
 end)..'"'
end
function M.encode(v)
 local t=type(v)
 if t=='string' then return quote(v) elseif t=='boolean' then return tostring(v)
 elseif t=='number' then assert(v==v and math.abs(v)<math.huge);return tostring(v)
 elseif t=='table' then
  local keys={};for k in pairs(v) do assert(type(k)=='string');keys[#keys+1]=k end;table.sort(keys)
  local a={};for _,k in ipairs(keys) do a[#a+1]=quote(k)..':'..M.encode(v[k]) end;return '{'..table.concat(a,',')..'}'
 elseif t=='nil' then return 'null' end
 error('不支持JSON类型')
end
return M
