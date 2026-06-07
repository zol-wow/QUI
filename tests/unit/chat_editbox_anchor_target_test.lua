-- tests/unit/chat_editbox_anchor_target_test.lua
-- Run: lua tests/unit/chat_editbox_anchor_target_test.lua
-- Verifies the anchor-target chooser: ChatFrame1's editbox backdrop anchors
-- to the last-active QUI window when chat is enabled AND that container is
-- shown; falls back to window 1 if the active window is hidden; falls back to
-- the Blizzard frame when no shown container is available or chat is disabled.

local settings = { enabled = false }

-- Two containers: window 1 and window 2, each independently togglable.
local container1 = { IsShown = function(self) return self._shown end, _shown = true, _id = 1 }
local container2 = { IsShown = function(self) return self._shown end, _shown = true, _id = 2 }

local activeWindow = 1

local chatFrame1 = { _blizz = 1 }
local chatFrame3 = { _blizz = 3 }

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    UIKit = setmetatable({}, { __index = function() return function() end end }),
    QUI = { Chat = {
        _internals = setmetatable({
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
        }, { __index = function() return function() end end }),
        DisplayLayer = {
            GetActiveWindow = function() return activeWindow end,
            GetContainer = function(id)
                if id == 2 then return container2 end
                return container1
            end,
        },
    } },
}
function _G.CreateFrame()
    return setmetatable({}, { __index = function() return function() end end })
end
function _G.hooksecurefunc() end

assert(loadfile("QUI_Chat/chat/editbox_basics.lua"))("QUI", ns)
local EB = ns.QUI.Chat.EditBoxBasics
assert(EB and EB._GetAnchorFrame, "anchor chooser exported for tests")

-- disabled chat -> blizzard frame
assert(EB._GetAnchorFrame(chatFrame1, 1) == chatFrame1, "disabled chat anchors to chat frame")

-- enabled chat, frame 1, active window 1 shown -> container1
settings.enabled = true
activeWindow = 1
container1._shown = true
container2._shown = true
assert(EB._GetAnchorFrame(chatFrame1, 1) == container1,
    "enabled chat anchors frame 1 to window-1 container when window 1 is active")

-- enabled, other frames stay on their Blizzard frame
assert(EB._GetAnchorFrame(chatFrame3, 3) == chatFrame3, "other frames unaffected")

-- container hidden -> fall back to blizzard frame
container1._shown = false
container2._shown = false
assert(EB._GetAnchorFrame(chatFrame1, 1) == chatFrame1,
    "hidden container falls back to Blizzard frame")

-- ── New T9 asserts ────────────────────────────────────────────────────────

-- (1) active window 2 shown -> returns window 2's container
container1._shown = true
container2._shown = true
activeWindow = 2
assert(EB._GetAnchorFrame(chatFrame1, 1) == container2,
    "active window 2 shown: returns window 2 container")

-- (2) active window 2 HIDDEN -> falls back to window 1's container
container2._shown = false
container1._shown = true
activeWindow = 2
assert(EB._GetAnchorFrame(chatFrame1, 1) == container1,
    "active window 2 hidden: falls back to window 1 container")

-- (3) takeover disabled -> returns chatFrame regardless of active window
settings.enabled = false
activeWindow = 2
container1._shown = true
container2._shown = true
assert(EB._GetAnchorFrame(chatFrame1, 1) == chatFrame1,
    "takeover disabled: returns chatFrame")

print("OK: chat_editbox_anchor_target_test")
