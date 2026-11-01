-- Fixed-capacity log ring: preserve order without shifting the whole array.
local Buffer={};Buffer.__index=Buffer
function Buffer.new(capacity)
 assert(type(capacity)=='number'and capacity>=1 and capacity%1==0)
 return setmetatable({capacity=capacity,rows={},first=1,size=0},Buffer)
end
function Buffer:push(line)
 if self.size<self.capacity then
  local index=(self.first+self.size-1)%self.capacity+1
  self.rows[index]=line;self.size=self.size+1
 else
  self.rows[self.first]=line;self.first=self.first%self.capacity+1
 end
end
function Buffer:dump()
 local rows={}
 for i=0,self.size-1 do rows[i+1]=self.rows[(self.first+i-1)%self.capacity+1]end
 return table.concat(rows,'\n')..(self.size>0 and '\n'or '')
end
return Buffer
