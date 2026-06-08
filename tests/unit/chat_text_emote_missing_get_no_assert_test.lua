-- tests/unit/chat_text_emote_missing_get_no_assert_test.lua
-- Run: lua tests/unit/chat_text_emote_missing_get_no_assert_test.lua
--
-- REGRESSION: "'formatKey' at _G[CHAT_TEXT_EMOTE_GET] doesn't exist." (4x spam).
--
-- TEXT_EMOTE (and GUILD_ITEM_LOOTED) bodies arrive pre-formatted; Blizzard's
-- own MessageFormatter never queries a CHAT_<TYPE>_GET key for them. QUI used to
-- resolve one eagerly for every line, which routed through
-- ChatFrameUtil.GetOutMessageFormatKey -> assertsafe -> geterrorhandler for the
-- missing key. assertsafe is NON-throwing (it reports straight to the error
-- handler), so the pcall wrapping the helper could never suppress it.
--
-- This test models the helper FAITHFULLY (asserting via geterrorhandler on a
-- missing key, exactly like the live client) and asserts that formatting these
-- key-less types renders correctly AND fires zero errors. The pre-existing
-- chat_message_format_test mock returned "" on a miss instead of asserting, so
-- it never caught this.

local errorCount = 0
function _G.geterrorhandler()
    return function(_) errorCount = errorCount + 1 end
end

-- Faithful ChatFrameUtil.GetOutMessageFormatKey: reports a non-fatal error when
-- CHAT_<TYPE>_GET is absent and returns "" (mirrors ChatFrameUtil.lua + the
-- assertsafe contract), instead of silently returning "".
_G.ChatFrameUtil = {
    GetOutMessageFormatKey = function(typeKey)
        local key = _G["CHAT_" .. typeKey .. "_GET"]
        if key == nil then
            geterrorhandler()(("'formatKey' at _G[CHAT_%s_GET] doesn't exist."):format(typeKey))
            return ""
        end
        return key
    end,
}

-- GET globals that DO exist in the live client (sanity: their resolution must
-- not regress and must not error). TEXT_EMOTE / GUILD_ITEM_LOOTED deliberately
-- have none.
_G.CHAT_SAY_GET = "%s says: "
_G.CHAT_EMOTE_GET = "%s "

-- channelShorten OFF -> full Blizzard GET path (this is the mode that also
-- routes GUILD_ITEM_LOOTED through the format-key resolver).
local settings = { modifiers = {
    classColors = { enabled = false },
    channelShorten = { enabled = false },
} }

local ns = {
    Helpers = { IsSecretValue = function() return false end },
    QUI = { Chat = { _internals = { GetSettings = function() return settings end } } },
}

assert(loadfile("QUI_Chat/chat/message_format.lua"))("QUI", ns)
local F = ns.QUI.Chat.MessageFormat

local function eq(label, got, want)
    assert(got == want, label .. ": expected " .. tostring(want) .. " got " .. tostring(got))
end

-- 1. TEXT_EMOTE with a sender: the body is pre-formatted, so the first sender
--    occurrence becomes a player link (no "%s: " prefix). The reported case.
eq("text emote line",
    F.BuildEventLine("CHAT_MSG_TEXT_EMOTE", { text = "Ann waves.", sender = "Ann" }),
    "|Hplayer:Ann:0:TEXT_EMOTE:|hAnn|h waves.")

-- 2. TEXT_EMOTE without a renderable sender still renders the bare body.
eq("text emote no sender",
    F.BuildEventLine("CHAT_MSG_TEXT_EMOTE", { text = "Someone dances." }),
    "Someone dances.")

-- 3. GUILD_ITEM_LOOTED (full mode): "$s" -> bare player link; also key-less.
eq("guild item looted line",
    F.BuildEventLine("CHAT_MSG_GUILD_ITEM_LOOTED", { text = "$s loots [Sword]", sender = "Ann" }),
    "|Hplayer:Ann|h[Ann]|h loots [Sword]")

-- 4. A type that DOES have a GET key must still resolve through the helper.
eq("say still formats",
    F.BuildEventLine("CHAT_MSG_SAY", { text = "hello", sender = "Bob" }),
    "|Hplayer:Bob:0:SAY:|h[Bob]|h says: hello")

-- THE GUARD: not one of the above may have tripped the missing-key assert.
eq("no missing-GET assertions fired", errorCount, 0)

print("OK: chat_text_emote_missing_get_no_assert_test")
