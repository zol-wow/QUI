local _, ns = ...

local pcall = pcall
local tostring = tostring
local strfind = string.find
local print = print
local issecretvalue = issecretvalue or function() return false end

local POLICIES = {
    ["park-fail-closed"] = true,
    ["defer-ooc"] = true,
    ["defer-lift"] = true,
    ["chain-next"] = true,
    ["sink-forward"] = true,
    ["best-effort-style"] = true,
    ["bulkhead"] = true,
    ["compat"] = true,
    ["secret-probe"] = true,
    ["report"] = true,
}

local EXPECTED = {
    "secret value",
    "Cannot use SecureHandlers API on forbidden frames",
    "Cannot use SecureHandlers API during combat",
    "forbidden object",
    "locked-down object",
    "attempted to store a secret",
    "combat lockdown",
    "ADDON_ACTION_BLOCKED",
}

---@type table<string, any> -- counters plus a per-policy sub-table added by bump()
local stats = { badpolicy = 0, seenOverflow = 0 }
local seen = {}
local seenCount = 0
local SEEN_CAP = 200
local observer

local function bump(policy, field)
    local t = stats[policy]
    if not t then
        t = { expected = 0, unexpected = 0, secretErr = 0 }
        stats[policy] = t
    end
    t[field] = t[field] + 1
end

local function currentHandler()
    local get = geterrorhandler
    local handler = get and get()
    return handler or print
end

local dispatching = false
local function reportToHandler(err)
    if dispatching then return false end
    dispatching = true
    local okH, handler = pcall(currentHandler)
    if not okH then
        dispatching = false
        return false
    end
    local delivered = (pcall(handler, err))
    dispatching = false
    return delivered
end

local observing = false
local function notifyObserver(policy, err, wasExpected)
    if not observer or observing then return end
    observing = true
    pcall(observer, policy, err, wasExpected)
    observing = false
end

local function onFailure(policy, err)
    if not POLICIES[policy] then
        stats.badpolicy = stats.badpolicy + 1
        policy = "report"
    end
    -- Probe FIRST: error messages can BE secret (Blizzard_ScriptErrorsFrame.lua:95-105).
    if issecretvalue(err) then
        bump(policy, "secretErr")
        reportToHandler(err)
        return
    end
    local okStr, str = pcall(tostring, err)
    if okStr and issecretvalue(str) then
        bump(policy, "secretErr")
        reportToHandler(str)
        return
    end
    if not okStr or type(str) ~= "string" then
        str = "SafeCall(" .. policy .. "): unprintable error object"
    end
    err = str
    if policy ~= "report" then
        for i = 1, #EXPECTED do
            if strfind(err, EXPECTED[i], 1, true) then
                bump(policy, "expected")
                notifyObserver(policy, err, true)
                return
            end
        end
    end
    bump(policy, "unexpected")
    notifyObserver(policy, err, false)
    local n = seen[err]
    if n then
        seen[err] = n + 1
    elseif seenCount < SEEN_CAP then
        seen[err] = 1
        seenCount = seenCount + 1
        if not reportToHandler(err) then
            seen[err] = nil
            seenCount = seenCount - 1
        end
    else
        stats.seenOverflow = stats.seenOverflow + 1
        reportToHandler(err)
    end
end

local function finish(policy, ok, ...)
    if ok then
        return true, ...
    end
    onFailure(policy, ...)
    return false
end

local function invoke(obj, name, ...)
    return obj[name](obj, ...)
end

local SKIP = {}
local function probeMethod(obj, name)
    if issecretvalue(obj) or obj == nil then return SKIP end
    local m = obj[name]
    if issecretvalue(m) or m == nil then return SKIP end
    return m
end

function ns.SafeCall(policy, fn, ...)
    return finish(policy, pcall(fn, ...))
end

function ns.SafeCallMethod(policy, obj, methodName, ...)
    return finish(policy, pcall(invoke, obj, methodName, ...))
end

function ns.SafeCallMethodIfPresent(policy, obj, methodName, ...)
    local okProbe, m = pcall(probeMethod, obj, methodName)
    if not okProbe then
        onFailure(policy, m)
        return false
    end
    if m == SKIP then return nil end
    return finish(policy, pcall(m, obj, ...))
end

function ns.SafeCallStats()
    return stats
end

function ns.SafeCallSetObserver(fn)
    observer = fn
end
