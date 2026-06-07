-- tests/unit/chat_keyword_capture_highlight_test.lua
-- Run: lua tests/unit/chat_keyword_capture_highlight_test.lua
-- Verifies KeywordAlert.ProcessForCapture: highlights matches (case-
-- insensitive, preserving original case), gates on enabled + skipSelf,
-- passes secrets through untouched.
--
-- Mode-dependent side effects:
--   pre-suppression (not suppressed): sound fires once (single path owns
--     ALL windows); tab flash NEVER fires
--   suppressed mode: keyword sound fires once; tab flash NEVER fires
--     (custom-tab unread badges serve that role; flash is pipeline-only)

local function explode() error("operator applied to secret sentinel", 2) end
local secret = setmetatable({}, { __tostring = explode, __concat = explode, __len = explode })

local soundPlayed = false   -- tracks PlaySoundFile calls
local flashFired  = false   -- tracks FCF_StartAlertFlash calls
function _G.PlaySoundFile() soundPlayed = true end
function _G.FCF_StartAlertFlash() flashFired = true end
function _G.UnitName() return "Me" end
function _G.InCombatLockdown() return false end

-- keyword_alert.lua calls CreateFrame("Frame") at load time for login/guild
-- events; stub it to a no-op table.
function _G.CreateFrame()
    local f = {}
    f.RegisterEvent = function() end
    f.SetScript = function() end
    return f
end

-- GetGuildInfo may be called during refreshIdentity
function _G.GetGuildInfo() return nil end

local settings = { enabled = true, modifiers = { keywordAlert = {
    enabled = true, keywords = { "gem" }, includeOwnName = false,
    skipSelf = true, highlightColor = { 1, 0, 0, 1 },
    soundFile = "ding.ogg",  -- needed so PlayAlertSound resolves a path
} } }
local suppressActive = false

local ns = {
    Helpers = { IsSecretValue = function(v) return v == secret end },
    QUI = { Chat = {
        _internals = setmetatable({
            GetSettings = function() return settings end,
            IsChatEnabled = function(s) return s and s.enabled ~= false end,
            IsChatMessagingLockedDown = function() return false end,
        }, { __index = function() return function() end end }),
        -- _afterRefresh: keyword_alert appends ApplyEnabled to this table
        _afterRefresh = {},
        -- BlizzardSuppress stub: toggleable for mode tests
        BlizzardSuppress = { IsActive = function() return suppressActive end },
    } },
}

assert(loadfile("modules/chat/modifiers/keyword_alert.lua"))("QUI", ns)
local KA = ns.QUI.Chat.KeywordAlert
assert(KA and KA.ProcessForCapture, "ProcessForCapture exported")

-- Pre-suppression (not suppressed): highlight applied, sound fires, no flash
-- from capture path — the Blizzard frames' pipeline modifier owns side effects.
suppressActive = false
local out = KA.ProcessForCapture("wts GEM cheap", "Ann")
assert(out:find("|c", 1, true) and out:find("GEM", 1, true), "highlighted, got " .. tostring(out))
assert(soundPlayed, "capture path owns the keyword sound pre-suppression too")
assert(not flashFired,  "no flash from capture path while not suppressed")
soundPlayed = false

-- Suppressed mode: capture owns the keyword sound (once); flash NEVER fires
-- (custom-tab unread badges serve that role).
suppressActive = true
soundPlayed = false
flashFired  = false
local out2 = KA.ProcessForCapture("wts GEM cheap", "Ann")
assert(out2:find("|c", 1, true), "still highlights while suppressed")
assert(soundPlayed == true,  "keyword sound fires from capture while suppressed")
assert(flashFired  == false, "tab flash must NOT fire from capture path (badges replace it)")

-- No match -> unchanged
assert(KA.ProcessForCapture("hello", "Ann") == "hello", "no-match passthrough")

-- Disabled -> unchanged
settings.modifiers.keywordAlert.enabled = false
assert(KA.ProcessForCapture("wts gem", "Ann") == "wts gem", "disabled passthrough")
settings.modifiers.keywordAlert.enabled = true

-- skipSelf: own messages not highlighted
assert(KA.ProcessForCapture("my gem", "Me") == "my gem", "skipSelf respected")

-- Secret passthrough by identity
assert(rawequal(KA.ProcessForCapture(secret, "Ann"), secret), "secret untouched")

-- LINK SAFETY (review finding): a trigger matching inside |H...|h link data
-- must NOT corrupt the hyperlink. Keyword "gem" inside the payload/label of
-- a link stays untouched; the same word in plain text still highlights.
suppressActive = true
soundPlayed = false
local link = "|Haddon:quaziiuichat:waypoint:45.6:78.9|h[(45.6, 78.9)]|h"
-- (a) trigger appears ONLY inside the link: message unchanged, no trigger
local lhs = "go " .. "|Haddon:quaziiuichat:waypoint:1:2|h[gem spot]|h" .. " now"
local outL = KA.ProcessForCapture(lhs, "Ann")
assert(outL == lhs, "trigger inside link data/label must not modify the link, got " .. tostring(outL))
assert(not soundPlayed, "no sound when the only match is inside a link span")
-- (b) trigger in plain text NEXT TO a link: plain match highlights, link intact
soundPlayed = false
local rhs = "gem at " .. link
local outR = KA.ProcessForCapture(rhs, "Ann")
assert(outR:find(link, 1, true), "link must survive verbatim, got " .. tostring(outR))
assert(outR:find("|cffff0000gem|r", 1, true) or outR:find("|c%x%x%x%x%x%x%x%xgem|r"),
    "plain-text match still highlighted, got " .. tostring(outR))
assert(soundPlayed, "plain-text match still triggers the sound")

print("OK: chat_keyword_capture_highlight_test")
