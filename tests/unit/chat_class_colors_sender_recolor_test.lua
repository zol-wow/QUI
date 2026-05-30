-- tests/unit/chat_class_colors_sender_recolor_test.lua
-- Run: lua tests/unit/chat_class_colors_sender_recolor_test.lua
--
-- The class-colors feature colors a message sender's name by class. The old
-- implementation did this by toggling Blizzard's ChatTypeInfo (which taints
-- chat -- see chat_class_colors_no_chattypeinfo_write_test.lua). The fix moves
-- it into the post-render pipeline modifier: the sender's |Hplayer:..|h[Name]|h
-- hyperlink in the already-rendered line is wrapped with the class color,
-- resolved from the event's sender GUID. Same visual as Blizzard's native
-- colorNameByClass, zero global mutation.
--
-- This test feeds a rendered SAY line through the registered modifier and
-- asserts the sender link comes back class-color-wrapped. It FAILS pre-fix
-- (the modifier does not recolor the sender) and PASSES once it does.

function CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript() end
    return frame
end

RAID_CLASS_COLORS = {
    DEATHKNIGHT = { colorStr = "ffc41e3a", r = 0.77, g = 0.12, b = 0.23 },
}

function GetPlayerInfoByGUID(guid)
    if guid == "Player-1-DK" then
        return "Death Knight", "DEATHKNIGHT", "Human", "Human", 2, "Arthas", "Realm"
    end
    return nil
end

local settings = {
    enabled = true,
    modifiers = {
        classColors = { enabled = true, recolorBodyText = false },
    },
    hyperlinks = { interactiveNames = false },
}

local registered = {}
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = {
        Chat = {
            _afterRefresh = {},
            Pipeline = {
                Register = function(name, _, fn) registered[name] = fn end,
                Unregister = function(name) registered[name] = nil end,
            },
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                IsChatMessagingLockedDown = function() return false end,
            },
        },
    },
}

assert(loadfile("modules/chat/modifiers/class_colors.lua"))("QUI", ns)

local modifier = registered["class_colors"]
assert(type(modifier) == "function", "class_colors must register a pipeline modifier when enabled")

local senderLink = "|Hplayer:Arthas-Realm:357:SAY|h[Arthas]|h"
local line = senderLink .. " says: hello"
local info = { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_SAY" }

local out = modifier(line, info, "CHAT_MSG_SAY")

local expected = "|cffc41e3a" .. senderLink .. "|r says: hello"
assert(
    out == expected,
    "sender name must be wrapped with the class color post-render.\n  expected: "
        .. expected .. "\n  actual:   " .. tostring(out)
)

-- A line with no player link (e.g. a system/monster line) must pass through
-- untouched -- never fabricate a wrap.
local plain = "Some monster yells something"
assert(
    modifier(plain, { event = "CHAT_MSG_MONSTER_YELL" }, "CHAT_MSG_MONSTER_YELL") == plain,
    "lines without a player hyperlink must be returned unchanged"
)

-- Types Blizzard already class-colors natively (PARTY/RAID/GUILD/INSTANCE/...)
-- must NOT be re-wrapped by us, or the sender link gets double-colored. We only
-- color the types Blizzard leaves uncolored: SAY, YELL, CHANNEL.
local partyLine = senderLink .. ": on my way"
local partyInfo = { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_PARTY" }
assert(
    modifier(partyLine, partyInfo, "CHAT_MSG_PARTY") == partyLine,
    "Blizzard-auto-colored types (e.g. PARTY) must pass through unwrapped to avoid double-coloring"
)

-- CHANNEL is one Blizzard does NOT auto-color, so we DO color it.
local channelInfo = { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_CHANNEL" }
assert(
    modifier(senderLink .. " hey", channelInfo, "CHAT_MSG_CHANNEL")
        == "|cffc41e3a" .. senderLink .. "|r hey",
    "CHANNEL sender names should be class-colored (Blizzard does not auto-color them)"
)

-- (Finding 1) An already class-colored sender link must not be double-wrapped.
local preColored = "|cffc41e3a" .. senderLink .. "|r says: hi"
assert(
    modifier(preColored, { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_SAY" }, "CHAT_MSG_SAY")
        == preColored,
    "an already-colored sender link must be left as-is (no double wrap)"
)

-- (Finding 1) When the only player link belongs to someone other than the
-- sender (or the sender prefix is absent), do NOT recolor the wrong link.
local bobLink = "|Hplayer:Bob-Realm:1:CHANNEL|h[Bob]|h"
local otherLine = bobLink .. " waved at you"
assert(
    modifier(otherLine, { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_CHANNEL" }, "CHAT_MSG_CHANNEL")
        == otherLine,
    "must not recolor a non-sender player link with the sender's class color"
)

-- (Finding 1) The sender's OWN link is colored even when another player's link
-- appears first in the line (target by name, not position).
local mixed = bobLink .. " and " .. senderLink .. " arrived"
local mixedExpected = bobLink .. " and |cffc41e3a" .. senderLink .. "|r arrived"
assert(
    modifier(mixed, { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_CHANNEL" }, "CHAT_MSG_CHANNEL")
        == mixedExpected,
    "the sender's own link should be colored even when not the first player link"
)

-- (Finding 1) A same-name link from a DIFFERENT realm must not be colored as
-- the sender. Sender is Arthas-Realm (GUID realm = "Realm"); a same-name
-- Arthas-Other link appears first. Only the sender's own realm link is colored.
local otherRealmLink = "|Hplayer:Arthas-Other:9:CHANNEL|h[Arthas]|h"
local crossLine = otherRealmLink .. " vs " .. senderLink
local crossExpected = otherRealmLink .. " vs |cffc41e3a" .. senderLink .. "|r"
assert(
    modifier(crossLine, { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_CHANNEL" }, "CHAT_MSG_CHANNEL")
        == crossExpected,
    "must color the sender's own realm link, not a same-name cross-realm link"
)

-- (Review) When Blizzard already class-colors the name INSIDE the link display
-- (ChatFrameUtil.ShouldColorChatByClass true via the chatClassColorOverride
-- CVar), the rendered link looks like |Hplayer:..|h[|cff..Name|r]|h. Re-wrapping
-- it would nest color codes, so it must be left untouched.
local blizzColored = "|Hplayer:Arthas-Realm:357:SAY|h[|cffc41e3aArthas|r]|h"
assert(
    modifier(blizzColored .. " says: hi", { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_SAY" }, "CHAT_MSG_SAY")
        == blizzColored .. " says: hi",
    "a link whose display text is already class-colored must not be re-wrapped (no nested |c)"
)

-- (Finding 2) With body recolor on, a cached name that also appears inside a
-- player-link payload must NOT corrupt the link; only plain-text mentions get
-- colored.
settings.modifiers.classColors.recolorBodyText = true
local bodyLine = senderLink .. " says: hi Arthas"
local bodyOut = modifier(bodyLine, { author = "Arthas-Realm", guid = "Player-1-DK", event = "CHAT_MSG_SAY" }, "CHAT_MSG_SAY")
assert(
    bodyOut:find("|Hplayer:Arthas-Realm:357:SAY|h", 1, true) ~= nil,
    "body recolor must not corrupt the sender link payload; got: " .. tostring(bodyOut)
)
assert(
    bodyOut:find("hi |cffc41e3aArthas|r", 1, true) ~= nil,
    "body recolor should still color plain-text name mentions; got: " .. tostring(bodyOut)
)
settings.modifiers.classColors.recolorBodyText = false

print("OK: chat_class_colors_sender_recolor_test")
