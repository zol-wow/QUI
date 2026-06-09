-- tests/unit/chat_sender_realm_names_test.lua
-- Run: lua tests/unit/chat_sender_realm_names_test.lua
-- Verifies chat.modifiers.showRealmNames independently controls whether
-- cross-realm players keep their "-Realm" suffix in chat sender names, fully
-- decoupled from channelShorten (which only shapes channel/type labels).

-- Mode-aware Ambiguate: "short" strips the realm, "none"/"guild" keep it
-- (matching Blizzard for cross-realm names — ChatFrameUtil.lua:993-998). The
-- shared chat_message_format_test mock ignores the mode and always strips, so a
-- dedicated mock is needed to exercise the toggle.
_G.Ambiguate = function(name, mode)
    if type(name) ~= "string" then return name end
    if mode == "short" then return (name:gsub("%-.*$", "")) end
    return name -- "none" / "guild": keep the realm suffix
end

local settings = { modifiers = {
    classColors = { enabled = false },           -- keep DecorateSender output bare
    channelShorten = { enabled = true, preset = "letter" },
    -- showRealmNames intentionally ABSENT at first to prove the false default.
} }

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = { GetSettings = function() return settings end } } },
}
assert(loadfile("QUI_Chat/chat/message_format.lua"))("QUI", ns)
local F = ns.QUI.Chat.MessageFormat

local fails = 0
local function eq(label, got, want)
    if got == want then print(("  ok  %s"):format(label))
    else fails = fails + 1; print(("FAIL  %s: expected %q got %q"):format(label, tostring(want), tostring(got))) end
end

local CROSS = "Anya-Stormrage"
local SAME  = "Anya"

-- 1. Default (showRealmNames absent ⇒ false): realm stripped, regardless of channelShorten.
eq("default + shorten on  → stripped", F.DecorateSender("CHAT_MSG_SAY", "hi", CROSS), SAME)
settings.modifiers.channelShorten.enabled = false
eq("default + shorten off → stripped", F.DecorateSender("CHAT_MSG_SAY", "hi", CROSS), SAME)
settings.modifiers.channelShorten.enabled = true

-- 2. showRealmNames OFF explicitly: same as the default.
settings.modifiers.showRealmNames = false
eq("off + shorten on  → stripped", F.DecorateSender("CHAT_MSG_SAY", "hi", CROSS), SAME)
settings.modifiers.channelShorten.enabled = false
eq("off + shorten off → stripped", F.DecorateSender("CHAT_MSG_SAY", "hi", CROSS), SAME)
settings.modifiers.channelShorten.enabled = true

-- 3. showRealmNames ON: realm kept, INDEPENDENT of channelShorten.
settings.modifiers.showRealmNames = true
eq("on + shorten on  → kept", F.DecorateSender("CHAT_MSG_SAY", "hi", CROSS), CROSS)
settings.modifiers.channelShorten.enabled = false
eq("on + shorten off → kept", F.DecorateSender("CHAT_MSG_SAY", "hi", CROSS), CROSS)
settings.modifiers.channelShorten.enabled = true

-- 4. Guild chat uses Blizzard's "guild" mode (realm-showing pair) when ON.
eq("on + guild chat → kept", F.DecorateSender("CHAT_MSG_GUILD", "hi", CROSS), CROSS)

-- 5. Same-realm sender (no suffix) never gains a realm, either way.
settings.modifiers.showRealmNames = true
eq("on + same-realm → unchanged", F.DecorateSender("CHAT_MSG_SAY", "hi", SAME), SAME)
settings.modifiers.showRealmNames = false
eq("off + same-realm → unchanged", F.DecorateSender("CHAT_MSG_SAY", "hi", SAME), SAME)

if fails > 0 then error(fails .. " assertion(s) failed") end
print("OK: chat_sender_realm_names_test")
