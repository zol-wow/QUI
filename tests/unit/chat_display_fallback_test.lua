-- tests/unit/chat_display_fallback_test.lua
-- Run: lua tests/unit/chat_display_fallback_test.lua
-- Verifies Apply(): custom mode -> capture setup + display shown + rebuilt;
-- blizzard mode -> capture torn down + display hidden, store retained
-- (lossless toggle); chat disabled -> same as blizzard; lazy creation
-- (blizzard mode never creates the display).

local settings = { enabled = true, displayMode = "blizzard", customDisplay = {} }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

local calls = {}
local created = false
ns.QUI.Chat.MessageCapture = {
    Setup = function() calls[#calls + 1] = "capture:setup" end,
    Teardown = function() calls[#calls + 1] = "capture:teardown" end,
}
ns.QUI.Chat.DisplayLayer = {
    EnsureCreated = function() created = true; calls[#calls + 1] = "display:create" end,
    Show = function() calls[#calls + 1] = "display:show" end,
    Hide = function() calls[#calls + 1] = "display:hide" end,
    Rebuild = function() calls[#calls + 1] = "display:rebuild" end,
    Refresh = function() calls[#calls + 1] = "display:refresh" end,
    IsCreated = function() return created end,
}
ns.QUI.Chat.TabManager = { GetActiveFilter = function() return nil end }

assert(loadfile("modules/chat/display_fallback.lua"))("QUI", ns)
local FB = ns.QUI.Chat.DisplayFallback

-- Blizzard mode (default): nothing created, nothing shown
FB.Apply()
assert(not created, "blizzard mode never creates the display")
local joined = table.concat(calls, ",")
assert(not joined:find("display:show"), "no show in blizzard mode")

-- Flip to custom: exact sequence (setup -> create -> refresh -> show -> rebuild)
calls = {}
settings.displayMode = "custom"
FB.Apply()
joined = table.concat(calls, ",")
assert(joined == "capture:setup,display:create,display:refresh,display:show,display:rebuild",
    "wrong order or wrong calls in custom mode: " .. joined)

-- Repeat Apply in the SAME mode (cosmetic RefreshAll): no Rebuild
calls = {}
FB.Apply()
joined = table.concat(calls, ",")
assert(joined == "capture:setup,display:create,display:refresh,display:show",
    "same-mode re-apply must skip rebuild: " .. joined)

-- Flip back to blizzard: teardown + hide; NO store clear anywhere in this file
calls = {}
settings.displayMode = "blizzard"
FB.Apply()
joined = table.concat(calls, ",")
assert(joined:find("capture:teardown"), "capture torn down")
assert(joined:find("display:hide"), "display hidden")
assert(not joined:find("rebuild"), "no rebuild needed when hiding")

-- Re-entering custom after blizzard: rebuild fires again (transition latch)
calls = {}
settings.displayMode = "custom"
FB.Apply()
joined = table.concat(calls, ",")
assert(joined:find("display:rebuild"), "re-entering custom rebuilds the view")

-- Chat disabled entirely: same as blizzard path
calls = {}
settings.enabled = false
FB.Apply()
joined = table.concat(calls, ",")
assert(joined:find("capture:teardown") and joined:find("display:hide"),
    "disabled chat tears down custom display")

print("OK: chat_display_fallback_test")
