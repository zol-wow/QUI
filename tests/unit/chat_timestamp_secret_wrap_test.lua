-- tests/unit/chat_timestamp_secret_wrap_test.lua
-- Run: lua tests/unit/chat_timestamp_secret_wrap_test.lua

local function noop() end

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local function createStateTable()
    local state = setmetatable({}, { __mode = "k" })
    return state, function(key)
        local value = state[key]
        if not value then
            value = {}
            state[key] = value
        end
        return value
    end
end

local function explode()
    error("operator applied to secret sentinel", 2)
end

local secret = setmetatable({}, {
    __tostring = explode,
    __concat = explode,
    __len = explode,
    __eq = explode,
})
local wrappedSecret = {}
local wrapCalls = {}

_G.C_StringUtil = {
    WrapString = function(infix, prefix, suffix)
        wrapCalls[#wrapCalls + 1] = { infix = infix, prefix = prefix, suffix = suffix }
        return wrappedSecret
    end,
}
_G.date = function(fmt)
    assert(fmt == "%H:%M", "timestamp should use 24h format in this test")
    return "12:34"
end
function _G.CreateFrame()
    return {
        RegisterEvent = noop,
        UnregisterEvent = noop,
        SetScript = noop,
    }
end

local settings = {
    enabled = true,
    timestamps = {
        enabled = true,
        format = "24h",
    },
}

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function() return settings end
        end,
        CreateStateTable = createStateTable,
        IsSecretValue = function(value) return rawequal(value, secret) or rawequal(value, wrappedSecret) end,
    },
    -- core/safecall.lua stub (Task 45b ns-mock precedent).
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
    UIKit = {},
    QUI = {
        Chat = {
            Sounds = { Setup = noop },
            Skinning = {},
            Cleanup = {},
            EditBoxBasics = {},
            EditBoxHistory = {},
            Copy = {},
        },
    },
}

assert(loadfile("QUI_Chat/chat/chat.lua"))("QUI", ns)

local result, changed = ns.QUI.Chat._internals.AddTimestamp(secret)
assert(rawequal(result, wrappedSecret), "secret timestamp must use C_StringUtil.WrapString result by identity")
assert(changed == true, "successful C-side wrapping should report a changed line")
assert(#wrapCalls == 1, "secret timestamp should call C_StringUtil.WrapString once")
assert(rawequal(wrapCalls[1].infix, secret), "secret payload must be passed to WrapString by identity")
assert(wrapCalls[1].prefix == "[12:34] ", "timestamp prefix mismatch")
assert(wrapCalls[1].suffix == nil, "timestamp suffix should be nil")

local source = readAll("QUI_Chat/chat/chat.lua")
assert(not source:find("wrapped%s*~=%s*nil"),
    "WrapString return is non-nil per generated docs; do not compare possibly-secret wrapped text in Lua")

print("OK: chat_timestamp_secret_wrap_test")
