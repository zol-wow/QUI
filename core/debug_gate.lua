local _, ns = ...

local pending = {}
local active = false

local securecall = securecallfunction

function ns.DebugIsolate(fn)
    if type(fn) ~= "function" then return nil end
    if not securecall then return fn end
    return function(...) return securecall(fn, ...) end
end

function ns.DebugRegister(fn)
    if active then
        fn()
    else
        pending[#pending + 1] = fn
    end
end

function ns.DebugActivate()
    if active then return end
    active = true
    for i = 1, #pending do
        pending[i]()
        pending[i] = nil
    end
end
