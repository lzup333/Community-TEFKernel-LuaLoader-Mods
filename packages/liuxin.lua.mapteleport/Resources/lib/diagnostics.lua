local D={}
local name='map_teleport_debug.log'
local lines={}
local last={}
local sampled={}
local maximum=256
local last_write_error=false
local function write(text)
    local ok, result, err = pcall(mod.write_file, name, text)
    if not ok or not result then
        if not last_write_error then
            last_write_error=true
            mod.warn('[地图传送诊断] 私有日志写入失败: '..tostring(err or result))
        end
    else last_write_error=false end
end
function D.log(event,detail)
    local stamp=os.date('%Y-%m-%d %H:%M:%S')
    local line=stamp..' '..event..(detail and (' | '..tostring(detail)) or '')
    lines[#lines+1]=line
    if #lines>maximum then table.remove(lines,1) end
    write(table.concat(lines,'\n')..'\n')
    if event=='启动' or event=='初始化' or event=='初始化失败' or event:find('ERROR ',1,true) or event=='触摸变化' or event=='点击结束' or event=='传送已排队' or event=='传送调用' then
        mod.info('[地图传送诊断] '..event..(detail and (' | '..tostring(detail)) or ''))
    end
end
function D.changed(key,value)
    local s=tostring(value)
    if last[key]~=s then last[key]=s; D.log(key,s) end
end
function D.sample(key,value,frame,interval)
    if type(frame)~='number' then return end
    local previous=sampled[key]
    if not previous or frame<previous or frame-previous>=interval then
        sampled[key]=frame
        D.log(key,value)
    end
end
function D.guard(label,fn,...)
    local args=table.pack(...)
    local ok,err=xpcall(function() fn(table.unpack(args,1,args.n)) end,debug.traceback)
    if not ok then D.changed('ERROR '..label,err) end
end
D.log('启动','版本 1.0.1; 路径 '..tostring(mod.private_dir or '未知'))
mod.info('[地图传送诊断] 私有日志: '..tostring(mod.private_dir or '')..'/'..name)
return D
