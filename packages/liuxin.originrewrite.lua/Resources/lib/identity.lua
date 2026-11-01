local I={};I.__index=I
function I.new(r)
 if r.b.p.get_type then r.b.types.PlayerFileData=r.b.p.get_type('Terraria.IO','PlayerFileData')end
 return setmetatable({r=r},I)
end
function I:localToken()
 local r=self.r;if not r.store then return end
 local arr=r:w('player','object',nil);local index=r:w('myPlayer','int32',-1)
 local p=arr and index>=0 and index<r.b.p.array_length(arr)and r.b.p.array_at(arr,index,'object')
 if not p or not r.b:get('Player','active',p,'bool',false)then return end
 local name=r.b:get('Player','name',p,'object',nil)
 if type(name)~='string'and name then name=r.b.p.string_value(name)end
 if type(name)~='string'or #name==0 or #name>256 then return end
 local file=r:w('ActivePlayerFileData','object',nil);local path=file and r.b:get('PlayerFileData','Path',file,'object',nil)
 if path and type(path)~='string'then path=r.b.p.string_value(path)end
 local key=type(path)=='string'and #path>0 and #path<=1024 and('file:'..path)or('name:'..name)
 local token=r.store.data.profiles[key]
 if type(token)=='string'and token:match('^[0-9a-f]+$')and #token==32 then return token end
 local count=0;for _ in pairs(r.store.data.profiles)do count=count+1 end;if count>=512 then return end
 token=require('statefile').token();r.store.data.profiles[key]=token
 if not r.store:save()then r.store.data.profiles[key]=nil;return end
 r.log('PROFILE_ID','created; key='..(key:sub(1,5)=='file:'and 'character_file'or 'device_character_name'))
 return token
end
function I:token()return self.r.profileOverride or self:localToken()end
function I:key()
 local token=self:token();if not token or not self.r.world then return end
 return tostring(self.r.world)..':'..token
end
return I
