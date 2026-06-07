-- tests/unit/chat_editbox_takeover_rewire_test.lua
-- Run: lua tests/unit/chat_editbox_takeover_rewire_test.lua
-- The takeover path owns editbox styling: enabled Apply() styles ChatFrame1's
-- editbox (glass + dock under the QUI display, via editbox_basics which
-- self-gates on settings.editBox/glass); disabled Apply() removes the styling
-- so the stock editbox returns on the flip. Without these callsites the input
-- box renders stock at the suppressed ChatFrame1's old anchors.

local settings = { enabled = false }
local ns = {
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

local created = false
ns.QUI.Chat.MessageCapture = { Setup = function() end, Teardown = function() end }
ns.QUI.Chat.MessageStore = { Size = function() return 5 end }
ns.QUI.Chat.DisplayLayer = {
    EnsureCreated = function() created = true end,
    Show = function() end,
    Hide = function() end,
    Rebuild = function() end,
    Refresh = function() end,
    IsCreated = function() return created end,
}

_G.ChatFrame1 = { _sentinel = "ChatFrame1" }

local styleCalls, removeCalls = {}, {}
ns.QUI.Chat.EditBoxBasics = {
    StyleEditBox = function(frame) styleCalls[#styleCalls + 1] = frame end,
    RemoveEditBoxStyle = function(frame) removeCalls[#removeCalls + 1] = frame end,
}

assert(loadfile("modules/chat/display_fallback.lua"))("QUI", ns)
local FB = ns.QUI.Chat.DisplayFallback

-- Enabled: StyleEditBox runs against ChatFrame1 (the takeover's single input),
-- and only after the display exists so the anchor chooser targets it.
settings.enabled = true
FB.Apply()
assert(created, "display created before styling")
assert(#styleCalls == 1, "enabled Apply styles the editbox")
assert(styleCalls[1] == _G.ChatFrame1, "styling targets ChatFrame1")
assert(#removeCalls == 0, "no removal while enabled")

-- Same-mode re-apply (cosmetic RefreshAll: options/profile changes) re-runs
-- the styling so editBox settings (positionTop/bgAlpha/bgColor) apply live.
FB.Apply()
assert(#styleCalls == 2, "re-apply re-styles (settings changes flow through)")

-- Disabled: RemoveEditBoxStyle returns the stock editbox on the flip.
settings.enabled = false
FB.Apply()
assert(#removeCalls == 1 and removeCalls[1] == _G.ChatFrame1,
    "disabled Apply removes editbox styling from ChatFrame1")
assert(#styleCalls == 2, "no styling while disabled")

print("OK: chat_editbox_takeover_rewire_test")
