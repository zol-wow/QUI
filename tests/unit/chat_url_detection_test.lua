-- tests/unit/chat_url_detection_test.lua
-- Run: lua tests/unit/chat_url_detection_test.lua

local function noop() end

local settings = {
    enabled = true,
    urls = {
        enabled = true,
        color = { 0.078, 0.608, 0.992, 1 },
    },
    hyperlinks = {
        friendlyURLs = false,
    },
}

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

function CreateFrame()
    return {
        RegisterEvent = noop,
        SetScript = noop,
    }
end

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function() return settings end
        end,
        CreateStateTable = createStateTable,
        IsSecretValue = function() return false end,
        HasSecretValue = function() return false end,
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

local makeURLsClickable = ns.QUI.Chat._internals.MakeURLsClickable
assert(type(makeURLsClickable) == "function", "chat internals should expose URL clickification helper")

local function assertContains(name, haystack, needle)
    assert(haystack:find(needle, 1, true), name .. " missing: " .. needle .. "\nactual: " .. haystack)
end

do
    local text, changed = makeURLsClickable("Join discord.gg/J9Q87C9CM8")
    assert(changed == true, "bare discord invite should be linkified")
    assertContains(
        "bare discord invite",
        text,
        "|Haddon:quichat:url:discord.gg/J9Q87C9CM8|h[discord.gg/J9Q87C9CM8]|h"
    )
end

do
    local text, changed = makeURLsClickable("Join (https://discord.gg/J9Q87C9CM8).")
    assert(changed == true, "parenthesized discord invite should be linkified")
    assertContains(
        "parenthesized discord invite",
        text,
        "|Haddon:quichat:url:https://discord.gg/J9Q87C9CM8|h[https://discord.gg/J9Q87C9CM8]|h"
    )
    assertContains("trailing punctuation", text, "|h|r).")
end

print("OK: chat_url_detection_test")
