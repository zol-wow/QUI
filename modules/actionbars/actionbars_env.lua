local ADDON_NAME, ns = ...

local function ActionBarsEnvIndex(tbl, key)
    local declared = rawget(tbl, "__declared")
    if declared and declared[key] then
        return nil
    end
    return _G[key]
end

local function SetActionBarsChunkEnv(level, targetEnv)
    local nativeSetFenv = rawget(_G, "setfenv")
    if type(nativeSetFenv) == "function" and _VERSION == "Lua 5.1" then
        return nativeSetFenv(level + 1, targetEnv)
    end
    if not (debug and debug.getinfo and debug.getupvalue and debug.upvaluejoin) then
        return nil
    end
    local info = debug.getinfo(level + 1, "f")
    local fn = info and info.func
    if not fn then return nil end
    local i = 1
    while true do
        local name = debug.getupvalue(fn, i)
        if name == "_ENV" then
            debug.upvaluejoin(fn, i, function() return targetEnv end, 1)
            return fn
        elseif name == nil then
            return nil
        end
        i = i + 1
    end
end

local env = ns.ActionBarsEnv
if not env then
    env = { __declared = {} }
    ns.ActionBarsEnv = env
elseif not env.__declared then
    env.__declared = {}
end
setmetatable(env, { __index = ActionBarsEnvIndex })
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv = SetActionBarsChunkEnv
