-- tests/unit/chat_hyperlink_coords_capture_test.lua
-- Run: lua tests/unit/chat_hyperlink_coords_capture_test.lua
-- Capture-path coordinate linkify: TryLinkifyCoordsForCapture wraps
-- "(x, y)" / "[x, y]" with the waypoint protocol, self-gates on the
-- coordinates toggle, never double-wraps, and passes secrets untouched.
-- luacheck: globals CreateFrame hooksecurefunc

local secret = { __secret = true }

function _G.CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
end
function _G.hooksecurefunc() end

local settings = {
    enabled = true,
    hyperlinks = { coordinates = true },
}

local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = {
        _internals = {
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
        },
        _afterRefresh = {},
    } },
}

(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("QUI_Chat/chat/hyperlinks.lua"))("QUI", ns)
local HL = ns.QUI.Chat.Hyperlinks
assert(type(HL.TryLinkifyCoordsForCapture) == "function", "capture export exists")

-- paren form wraps
local out = HL.TryLinkifyCoordsForCapture("meet at (45.6, 78.9) now")
assert(out:find("|Haddon:quaziiuichat:waypoint:45.6:78.9|h[(45.6, 78.9)]|h", 1, true),
    "paren coords wrapped, got: " .. out)

-- square form wraps
out = HL.TryLinkifyCoordsForCapture("boss at [45, 78]")
assert(out:find("|Haddon:quaziiuichat:waypoint:45:78|h[[45, 78]]|h", 1, true),
    "square coords wrapped, got: " .. out)

-- no double-wrap
local once = HL.TryLinkifyCoordsForCapture("go (10, 20)")
assert(HL.TryLinkifyCoordsForCapture(once) == once, "already-wrapped line passes unchanged")

-- toggle off → untouched
settings.hyperlinks.coordinates = false
assert(HL.TryLinkifyCoordsForCapture("meet at (45.6, 78.9)") == "meet at (45.6, 78.9)",
    "coordinates toggle off -> no wrap")
settings.hyperlinks.coordinates = true

-- chat disabled → untouched
settings.enabled = false
assert(HL.TryLinkifyCoordsForCapture("meet at (45.6, 78.9)") == "meet at (45.6, 78.9)",
    "chat disabled -> no wrap")
settings.enabled = true

-- secret passes by identity, zero operators
assert(rawequal(HL.TryLinkifyCoordsForCapture(secret), secret), "secret untouched")

print("OK: chat_hyperlink_coords_capture_test")
