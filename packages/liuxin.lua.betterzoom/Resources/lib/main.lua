-- Keep the v1.6 camera path: fresh native calculation -> scale output -> refresh.
mod.meta={pkg_id='liuxin.lua.betterzoom',version='1.6.1',version_code=9,api_version=1}
local P=mod.patch
local get,set,invoke=P.get_field_value,P.set_field_value,P.invoke
local hooks={}
local factor=0.70
local pixelField,lastZoomField,recalculate
local depth,revision=0,0
local failed,confirmed=false,false
local logText=''

local function log(message)
    logText=logText..os.date('%H:%M:%S')..' '..message..'\n'
    pcall(mod.write_file,'betterzoom_runtime.log',logText)
    mod.info('BetterZoom '..message)
end
local function stop(message)
    if failed then return end
    failed=true
    log('ERROR '..tostring(message))
end
local function scaleOutput(instance)
    local native=get(pixelField,instance,'float')
    if type(native)~='number' or native~=native or native<0.05 or native>32 then
        error('invalid native PixelScale: '..tostring(native))
    end
    set(pixelField,instance,math.max(0.20,native*factor),'float')
    revision=revision+1
end
local function onCalculated(instance)
    -- UI and other calculations outside world ApplyCamera do no Lua work.
    if failed or depth==0 or not instance then return end
    local ok,err=pcall(scaleOutput,instance)
    if not ok then stop(err) end
end
local function prepareCamera(instance)
    local before=revision
    local result=invoke(recalculate,instance,false)
    if result==false then error('native UpdatePixelScale call failed') end
    if failed then return end
    if revision==before then error('UpdatePixelScale callback missing') end
    set(lastZoomField,instance,-1.0,'float')
end
local function beforeCamera(instance)
    depth=depth+1
    if not failed and instance and depth==1 then
        -- Named function avoids allocating a closure for every rendered frame.
        local ok,err=pcall(prepareCamera,instance)
        if not ok then stop(err) end
    end
    return false
end
local function confirmCamera(instance)
    local value=get(pixelField,instance,'float')
    log('ACTIVE actual PixelScale='..tostring(value)..'; multiplier='..factor)
end
local function afterCamera(instance)
    depth=math.max(0,depth-1)
    if depth==0 and not failed and not confirmed and instance then
        confirmed=true
        local ok,err=pcall(confirmCamera,instance)
        if not ok then stop(err) end
    end
end
local function removeHooks()
    for i=#hooks,1,-1 do hooks[i]:remove() end
    hooks={}
    depth=0
end
local function loadConfig()
    local ok,data=pcall(mod.read_file,'config.json')
    if ok and type(data)=='string' then
        local value=tonumber(data:match('"camera_zoom_multiplier"%s*:%s*([%d%.]+)'))
        if value and value>=0.50 and value<=1.25 then factor=value end
    end
    -- Retain the working multiplier; remove obsolete GUI/minimum/getter options.
    local clean=string.format('{"version":6,"camera_zoom_multiplier":%.6f}',factor)
    if not ok or data~=clean then
        local success,result=pcall(mod.write_file,'config.json',clean)
        if not success or not result then log('CONFIG save failed; using multiplier='..factor) end
    end
    -- Exact legacy diagnostic file only. Never delete directories or user saves.
    if type(mod.private_dir)=='string' and mod.private_dir~='' then
        pcall(os.remove,mod.private_dir..'/betterzoom_trace.log')
    end
end
function setup()
    log('START v1.6.1; GUI OFF')
    if mod.platform~='android' then stop('Android build required');return end
    loadConfig()
    local base=P.get_type('','DeviceVPPICalculator')
    local world=P.get_type('','XNAWorldCameraSettings')
    if not base or not world then stop('mobile camera types missing');return end
    pixelField=P.get_field(base,'PixelScale')
    lastZoomField=P.get_field(world,'_lastZoomScale')
    recalculate=P.get_method(base,'UpdatePixelScale',1)
    local apply=P.get_method(world,'ApplyCamera',0)
    if not pixelField or not lastZoomField or not recalculate or not apply then stop('mobile camera members missing');return end
    local output=P.install_hook(recalculate,{postfix=onCalculated})
    if not output then stop('UpdatePixelScale hook failed');return end
    hooks[#hooks+1]=output
    local camera=P.install_hook(apply,{prefix=beforeCamera,postfix=afterCamera})
    if not camera then removeHooks();stop('ApplyCamera hook failed');return end
    hooks[#hooks+1]=camera
    log('READY 2 hooks; multiplier='..factor)
end
function mod.cleanup()
    removeHooks()
end
todo_list={'setup'}
