-- tests/chat_url_detection_test.lua
-- Run: lua tests/chat_url_detection_test.lua

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

assert(loadfile("modules/chat/chat.lua"))("QUI", ns)

local makeURLsClickable = ns.QUI.Chat._internals.MakeURLsClickable
assert(type(makeURLsClickable) == "function", "chat internals should expose URL clickification helper")

local function assertContains(name, haystack, needle)
    assert(haystack:find(needle, 1, true), name .. " missing: " .. needle .. "\nactual: " .. haystack)
end

do
    local text, changed = makeURLsClickable("Join discord.gg/FFUjA4JXnH")
    assert(changed == true, "bare discord invite should be linkified")
    assertContains(
        "bare discord invite",
        text,
        "|Haddon:quaziiuichat:url:discord.gg/FFUjA4JXnH|h[discord.gg/FFUjA4JXnH]|h"
    )
end

do
    local text, changed = makeURLsClickable("Join (https://discord.gg/FFUjA4JXnH).")
    assert(changed == true, "parenthesized discord invite should be linkified")
    assertContains(
        "parenthesized discord invite",
        text,
        "|Haddon:quaziiuichat:url:https://discord.gg/FFUjA4JXnH|h[https://discord.gg/FFUjA4JXnH]|h"
    )
    assertContains("trailing punctuation", text, "|h|r).")
end

print("OK: chat_url_detection_test")
