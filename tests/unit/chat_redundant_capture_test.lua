-- tests/unit/chat_redundant_capture_test.lua
-- Run: lua tests/unit/chat_redundant_capture_test.lua
-- Verifies RedundantText.TryCollapseForCapture: collapses a loot line when
-- enabled, passthrough when disabled or unmatched event, secret passthrough.

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

local settings = { enabled = true, modifiers = { redundantText = {
    enabled = true,
    patterns = { loot = true, currency = true, xp = true, honor = true, reputation = true },
} } }
local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = {
        _internals = setmetatable({
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            IsChatMessagingLockedDown = function() return false end,
        }, { __index = function() return function() end end }),
        -- Pipeline stub: redundant_text does not use Pipeline but provide for
        -- consistency with other modifier tests.
        Pipeline = { Register = function() end, Unregister = function() end },
        -- _afterRefresh: redundant_text appends ApplyEnabled to this table
        _afterRefresh = {},
    } },
}

-- Stubs required at load time by redundant_text.lua:
-- CreateFrame: used for the PLAYER_LOGIN listener frame.
function _G.CreateFrame()
    local f = {}
    f.RegisterEvent = function() end
    f.SetScript = function() end
    return f
end
-- hooksecurefunc: used by hookFrame + FCF_OpenNewWindow/TemporaryWindow hooks.
function _G.hooksecurefunc() end
-- FCF_OpenNewWindow / FCF_OpenTemporaryWindow may be nil at load — that's fine;
-- the guards in installRenderedHooks check their existence.

-- Blizzard loot globalstrings the collapser builds patterns from.
-- LOOT_ITEM_SELF is the "you personally looted" template; the real WoW value
-- is "You receive loot: %s." — match the test message below exactly.
_G.LOOT_ITEM_SELF = "You receive loot: %s."
_G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."

assert(loadfile("modules/chat/modifiers/redundant_text.lua"))("QUI", ns)
local RT = ns.QUI.Chat.RedundantText
assert(RT and RT.TryCollapseForCapture, "TryCollapseForCapture exported")

-- Loot collapse: "You receive loot: [Shiny Gem]." -> "✓ [Shiny Gem]"
-- (LOOT_ITEM_SELF template produces "^You receive loot: (.-)%.$"; builder[1]
-- returns "✓ " .. captures[1]; SplitRenderedPrefix strips nothing on a plain
-- line, so no prefix is prepended.)
local out = RT.TryCollapseForCapture("You receive loot: [Shiny Gem].", "CHAT_MSG_LOOT")
assert(out == "\226\156\147 [Shiny Gem]", -- UTF-8 for "✓ [Shiny Gem]"
    "loot line collapsed to checkmark form, got " .. tostring(out))
-- Also confirm item link is preserved and original verbose prefix is gone
assert(out:find("[Shiny Gem]", 1, true), "item name in collapsed output")
assert(not out:find("You receive loot", 1, true), "verbose prefix removed")

-- Disabled -> passthrough (no transform at all)
settings.modifiers.redundantText.enabled = false
local out2 = RT.TryCollapseForCapture("You receive loot: [X].", "CHAT_MSG_LOOT")
assert(out2 == "You receive loot: [X].", "disabled passthrough, got " .. tostring(out2))
settings.modifiers.redundantText.enabled = true

-- Non-collapsible event -> passthrough (SAY is not in EVENT_TO_KEY)
local out3 = RT.TryCollapseForCapture("hello", "CHAT_MSG_SAY")
assert(out3 == "hello", "unmatched event passthrough, got " .. tostring(out3))

-- Secret -> identity passthrough (no operator may touch the secret value)
local out4 = RT.TryCollapseForCapture(secret, "CHAT_MSG_LOOT")
assert(rawequal(out4, secret), "secret untouched by identity")

print("OK: chat_redundant_capture_test")
