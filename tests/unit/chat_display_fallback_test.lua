-- tests/unit/chat_display_fallback_test.lua
-- Run: lua tests/unit/chat_display_fallback_test.lua
-- Verifies Apply(): enabled=true -> capture setup + display shown + rebuilt;
-- enabled=false -> capture torn down + display hidden, store retained
-- (lossless toggle); lazy creation (disabled never creates the display).

local settings = { enabled = false, customDisplay = {} }
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
    BackfillFromDefaultFrame = function() calls[#calls + 1] = "capture:backfill" end,
}
ns.QUI.Chat.MessageStore = { Size = function() return 0 end }
ns.QUI.Chat.DisplayLayer = {
    EnsureCreated = function() created = true; calls[#calls + 1] = "display:create" end,
    Show = function() calls[#calls + 1] = "display:show" end,
    Hide = function() calls[#calls + 1] = "display:hide" end,
    Rebuild = function() calls[#calls + 1] = "display:rebuild" end,
    Refresh = function() calls[#calls + 1] = "display:refresh" end,
    IsCreated = function() return created end,
}
ns.QUI.Chat.TabManager = {
    GetActiveFilter = function() return nil end,
    ReapplyAll = function()
        -- Mirrors the real ReapplyAll: asks each window to rebuild.
        -- The test only needs to confirm the Display.Rebuild call happens.
        ns.QUI.Chat.DisplayLayer.Rebuild()
    end,
}

assert(loadfile("QUI_Chat/chat/display_fallback.lua"))("QUI", ns)
local FB = ns.QUI.Chat.DisplayFallback

-- Disabled (default): nothing created, nothing shown
FB.Apply()
assert(not created, "disabled chat never creates the display")
local joined = table.concat(calls, ",")
assert(not joined:find("display:show"), "no show when disabled")

-- Enable (takeover): exact sequence (setup -> create -> refresh -> show -> rebuild)
calls = {}
settings.enabled = true
FB.Apply()
joined = table.concat(calls, ",")
assert(joined == "capture:setup,display:create,display:refresh,display:show,capture:backfill,display:rebuild",
    "wrong order or wrong calls when enabling: " .. joined)

-- Repeat Apply in the SAME mode (cosmetic RefreshAll): no Rebuild
calls = {}
FB.Apply()
joined = table.concat(calls, ",")
assert(joined == "capture:setup,display:create,display:refresh,display:show",
    "same-mode re-apply must skip rebuild: " .. joined)

-- Disable: teardown + hide; NO store clear anywhere in this file
calls = {}
settings.enabled = false
FB.Apply()
joined = table.concat(calls, ",")
assert(joined:find("capture:teardown"), "capture torn down")
assert(joined:find("display:hide"), "display hidden")
assert(not joined:find("rebuild"), "no rebuild needed when hiding")

-- Re-enable: rebuild fires again (transition latch)
calls = {}
settings.enabled = true
FB.Apply()
joined = table.concat(calls, ",")
assert(joined:find("display:rebuild"), "re-enabling rebuilds the view")

-- Chat disabled entirely: teardown + hide path (same as above; exercises the code path again)
calls = {}
settings.enabled = false
FB.Apply()
joined = table.concat(calls, ",")
assert(joined:find("capture:teardown") and joined:find("display:hide"),
    "disabled chat tears down custom display")

-- Size=5: store already has content -> backfill NOT called on first enable
ns.QUI.Chat.MessageStore.Size = function() return 5 end
settings.enabled = true
FB.Apply()                         -- transition to enabled (resets latch)
settings.enabled = false
FB.Apply()                         -- back to disabled (resets latch)
calls = {}
settings.enabled = true
FB.Apply()
joined = table.concat(calls, ",")
assert(joined:find("display:rebuild"), "rebuild still fires when store non-empty")
assert(not joined:find("capture:backfill"), "backfill skipped when store non-empty")

-- Skin-refresh Registry entry: registered with group "skinning"; refresh
-- re-themes only when chat is enabled (active takeover)
local registered
ns.Registry = { Register = function(_, name, def) registered = { name = name, def = def } end }
ns.QUI.Chat.TabUI = { Rebuild = function() calls[#calls + 1] = "tabs:rebuild" end }
-- re-load the module so the registration runs with the Registry stub present
assert(loadfile("QUI_Chat/chat/display_fallback.lua"))("QUI", ns)
assert(registered and registered.name == "chatCustomDisplaySkin", "skin entry registered")
assert(registered.def.group == "skinning", "on the skinning group")

settings.enabled = true
calls = {}
registered.def.refresh()
local joined2 = table.concat(calls, ",")
assert(joined2:find("display:refresh"), "skin refresh re-themes the display, got: " .. joined2)
assert(joined2:find("tabs:rebuild"), "skin refresh triggers tab rebuild, got: " .. joined2)

settings.enabled = false
calls = {}
registered.def.refresh()
assert(#calls == 0, "skin refresh inert when chat disabled")

print("OK: chat_display_fallback_test")
