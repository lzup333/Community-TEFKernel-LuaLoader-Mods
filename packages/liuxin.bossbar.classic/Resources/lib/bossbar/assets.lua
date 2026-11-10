local styles=require('bossbar.styles')
local A={}
function A.new(b,root,exists)
 return setmetatable({b=b,root=root,exists=exists,owned={},frames={},ready=false},{__index=A})
end
function A:pin(obj,unity)
 assert(obj,'贴图对象为空')
 local b=self.b
 local root=assert(b:root(obj),'托管强引用失败')
 self.owned[#self.owned+1]={object=obj,root=root,unity=unity}
 return obj
end
function A:load(name)
 local b=self.b
 local relative='lib/ui/'..name
 -- 先用加载器本地文件接口检查，避免托管文件异常穿过 FFI 终止游戏。
 if self.exists then assert(self.exists(relative),'贴图文件不存在: '..relative) end
 local bytes=self:pin(b:call(b.read_bytes,self.root..'/'..relative))
 local u=self:pin(b:construct(b.unity_ctor,2,2,4,false),true)
 assert(b:call(b.load_png,u,bytes,false)==true,'PNG 解码失败')
 b:call(b.filter,u,0) -- Point
 b:call(b.wrap,u,1)   -- Clamp
 return self:pin(b:construct(b.xna_ctor,u))
end
function A:prepare(style)
 style=styles[style] and style or 'A'
 if not self.white then self.white=self:load('white.png') end
 if not self.frames[style] then self.frames[style]=self:load(styles[style].file) end
 self.frame=self.frames[style]
 self.ready=true
end
function A:cleanup()
 self.ready=false
 local b=self.b
 -- 只 Destroy 自己创建的 Unity 对象；不释放游戏传入的头像。
 for _,e in ipairs(self.owned) do
  -- XNA wrapper 不是 UnityEngine.Object，不能传给 Destroy。
  if e.unity then pcall(b.call,b,b.destroy,e.object) end
  pcall(b.unroot,b,e.root)
 end
 self.owned={}; self.frames={}; self.frame=nil; self.white=nil
end
return A
