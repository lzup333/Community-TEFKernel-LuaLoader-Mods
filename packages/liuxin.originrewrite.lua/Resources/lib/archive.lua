-- Private sidecar keyed by worldID + character name; not a Terraria world-file extension.
local A={};A.__index=A
local function hex(s)return(s:gsub('.',function(c)return('%02x'):format(c:byte())end))end
local function checksum(raw)
 local a,b=1,0
 for i=1,#raw do a=(a+raw:byte(i))%65521;b=(b+a)%65521 end
 return('%08x'):format(b*65536+a)
end
local function parse(raw)
 if type(raw)~='string'or #raw>262144 or raw:sub(1,15)~='OR_ARCHIVE_216\n' or raw:sub(-1)~='\n' then return end
 local body,sum=raw:match('^(.*\n)CHECKSUM\t([0-9a-f]+)\n$')
 if not body or #sum~=8 or checksum(body)~=sum then return end
 raw=body
 local rows={};local count=0
 for line in raw:sub(16):gmatch('[^\n]+')do
  local w,n,a,b,c,d=line:match('^([%-]?%d+)\t([0-9a-f]+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)$')
  if not w or #n>512 or #n%2~=0 then return end
  if w and #n<=512 and #n%2==0 then
   a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
   if a>1000000000 or b>1000000000 or c>1000000000 or d>1000000000 then return end
   if a<=1000000000 and b<=1000000000 and c<=1000000000 and d<=1000000000 then rows[w..':'..n]={a,b,c,d};count=count+1 end
  end
 end
 if count>256 then return end
 return rows
end
function A.new(r,host)
 local self=setmetatable({r=r,host=host,rows={},dirty=false},A)
 if type(host.read_file)=='function'then
  for _,path in ipairs({'rewrite_archive.tsv','rewrite_archive_backup.tsv'})do
   local ok,raw=pcall(host.read_file,path);local rows=ok and parse(raw)
   if rows then self.rows=rows;self.lastGood=raw;break end
  end
 end
 local count=0;for _ in pairs(self.rows)do count=count+1 end;r.log('ARCHIVE_LOAD','records='..count..' private_sidecar=true')
 return self
end
function A:bind()
 local r=self.r;local player=r:player();if not player then return end
 local name=r.b:get('Player','name',player,'object',nil);name=name and r.b.p.string_value(name)
 if not name or #name==0 or #name>256 then return end
 local token=r.identity and r.identity:token()
 local legacy=tostring(r.world)..':'..hex(name)
 local key=token and(tostring(r.world)..':'..hex('id:'..token))or legacy
 if token and r:w('netMode','int32',-1)==0 and not self.rows[key]and self.rows[legacy]then self.rows[key]=self.rows[legacy];self.rows[legacy]=nil;self.dirty=true;self:save()end
 if self.key==key then return self.current end
 local count=0;for _ in pairs(self.rows)do count=count+1 end
 if not self.rows[key]and count>=256 then r.log('ARCHIVE_FULL','limit=256');return end
 self.key=key;self.rows[key]=self.rows[key]or{0,0,0,0};self.current=self.rows[key]
 if r.cfg.archive then r:notice('【重构档案】异化'..self.current[1]..'｜灾变'..self.current[2]..'｜终焉'..self.current[3]..'\n契约完成：'..self.current[4],{180,225,255},'archive')end
 return self.current
end
function A:kill(s)
 if not self.r.cfg.archive then return end
 local row=self:bind();if not row then return end
 row[s.tier]=math.min(1000000000,row[s.tier]+1);self.dirty=true;self:save()
 if(row[1]+row[2]+row[3])%5==0 then self.r:notice('【重构档案】异化'..row[1]..'｜灾变'..row[2]..'｜终焉'..row[3],{180,225,255},'archive')end
 if self.r.net and self.r.playerOverride~=nil then self.r.net:send('A',table.concat(row,','),self.r.playerOverride)end
 self.r.log('ARCHIVE_KILL','tier='..s.tier..' total='..(row[1]+row[2]+row[3]))
end
function A:complete()
 if not self.r.cfg.archive then return end
 local row=self:bind();if row then row[4]=math.min(1000000000,row[4]+1);self.dirty=true;self:save();if self.r.net and self.r.playerOverride~=nil then self.r.net:send('A',table.concat(row,','),self.r.playerOverride)end end
end
function A:clear()self:save();self.key=nil;self.current=nil end
function A:save()
 if not self.dirty or type(self.host.write_file)~='function'then return end
 local keys={};for key in pairs(self.rows)do keys[#keys+1]=key end;table.sort(keys)
 local lines={'OR_ARCHIVE_216'}
 for _,key in ipairs(keys)do local w,n=key:match('^(.-):(.*)$');local v=self.rows[key];lines[#lines+1]=table.concat({w,n,v[1],v[2],v[3],v[4]},'\t')end
 local body=table.concat(lines,'\n')..'\n'
 local raw=body..'CHECKSUM\t'..checksum(body)..'\n'
 if self.lastGood then pcall(self.host.write_file,'rewrite_archive_backup.tsv',self.lastGood)end
 local ok,result=pcall(self.host.write_file,'rewrite_archive.tsv',raw)
 if ok and result==true then self.lastGood=raw;self.dirty=false else self.r.log('ARCHIVE_SAVE_FAILED','retry later')end
end
A.parse=parse
return A
