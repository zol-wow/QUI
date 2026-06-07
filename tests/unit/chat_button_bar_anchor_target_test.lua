-- tests/unit/chat_button_bar_anchor_target_test.lua
-- Run: lua tests/unit/chat_button_bar_anchor_target_test.lua
-- Verifies the bar anchor chooser: frame 1's bar follows the custom display
-- container ONLY while Blizzard suppression is active; all other cases (other
-- frames, suppression off, container hidden) anchor to the Blizzard frame.

local container = { IsShown = function() return true end }
local chatFrame1 = { _blizz = 1 }
local chatFrame3 = { _blizz = 3 }
local suppressActive = false

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    UIKit = setmetatable({}, { __index = function() return function() end end }),
    QUI = { Chat = {
        _internals = setmetatable({
            GetSettings = function() return { enabled = true } end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
        }, { __index = function() return function() end end }),
        _afterRefresh = {},
        DisplayLayer = { GetContainer = function() return container end },
        BlizzardSuppress = { IsActive = function() return suppressActive end },
    } },
}
function _G.CreateFrame()
    return setmetatable({}, { __index = function() return function() end end })
end
function _G.hooksecurefunc() end
_G.UIParent = setmetatable({}, { __index = function() return function() end end })

assert(loadfile("modules/chat/button_bar.lua"))("QUI", ns)
local BB = ns.QUI.Chat.ButtonBar
assert(BB and BB._GetBarAnchorFrame, "anchor chooser exported for tests")

-- Suppression off -> blizzard frame
assert(BB._GetBarAnchorFrame(chatFrame1, 1) == chatFrame1, "no suppression -> blizzard frame")

-- Suppression on, frame 1, container shown -> container
suppressActive = true
assert(BB._GetBarAnchorFrame(chatFrame1, 1) == container, "suppressed frame-1 bar follows container")

-- Other frames stay put
assert(BB._GetBarAnchorFrame(chatFrame3, 3) == chatFrame3, "other frames unaffected")

-- Hidden container -> fall back
container.IsShown = function() return false end
assert(BB._GetBarAnchorFrame(chatFrame1, 1) == chatFrame1, "hidden container falls back")

-- Review fix: a suppressed (hidden) frame-1 must NOT tear its bar down when
-- the anchor chooser would redirect it to the custom display
container.IsShown = function() return true end
suppressActive = true
assert(BB._ShouldSkipVisibilityTeardown(chatFrame1, 1) == true, "suppressed frame-1 bar survives")
assert(BB._ShouldSkipVisibilityTeardown(chatFrame3, 3) == false, "other frames still teardown-gated")
suppressActive = false
assert(BB._ShouldSkipVisibilityTeardown(chatFrame1, 1) == false, "no suppression -> normal gating")

print("OK: chat_button_bar_anchor_target_test")
