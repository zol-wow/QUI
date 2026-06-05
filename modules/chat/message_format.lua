-- modules/chat/message_format.lua
-- Minimal formatter for custom-display lines captured from CHAT_MSG_* events.
-- Phase 1 uses deliberately short prefixes ([G], [2. Trade]); full Blizzard
-- formatting parity is the Phase 2 expansion of this file (design Risk 2 —
-- ALL replicated Blizzard formatting must stay isolated here).
--
-- HARD CONSTRAINT: ChatTypeInfo is READ-ONLY here. Never assign into it and
-- never call ChangeChatColor.
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local _I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: message_format.lua loaded before chat.lua. Check chat.xml — chat.lua must precede message_format.lua.")

ns.QUI.Chat.MessageFormat = ns.QUI.Chat.MessageFormat or {}
local Format = ns.QUI.Chat.MessageFormat

local function IsSecret(v)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(v) or false
end

-- Short prefixes for the common routed types. Types not listed render bare.
local TYPE_PREFIX = {
    GUILD = "[G] ",
    OFFICER = "[O] ",
    PARTY = "[P] ",
    PARTY_LEADER = "[PL] ",
    RAID = "[R] ",
    RAID_LEADER = "[RL] ",
    RAID_WARNING = "[RW] ",
    INSTANCE_CHAT = "[I] ",
    INSTANCE_CHAT_LEADER = "[IL] ",
    WHISPER = "[W:From] ",
    WHISPER_INFORM = "[W:To] ",
    BN_WHISPER = "[W:From] ",
    BN_WHISPER_INFORM = "[W:To] ",
    YELL = "[Y] ",
}

-- "CHAT_MSG_SAY" -> "SAY". Event names come from our own RegisterEvent list —
-- plain Lua strings, never secret.
function Format.EventToTypeKey(event)
    if type(event) ~= "string" then return nil end
    return event:match("^CHAT_MSG_(.+)$")
end

-- READ-ONLY ChatTypeInfo lookup; white fallback.
-- NOTE: for CHANNEL events pass "CHANNEL"..channelNumber (e.g. "CHANNEL2") —
-- ChatTypeInfo.CHANNEL itself carries no r/g/b; per-channel colors live in
-- ChatTypeInfo.CHANNEL1..CHANNEL10.
function Format.ColorForTypeKey(typeKey)
    local info = typeKey and _G.ChatTypeInfo and _G.ChatTypeInfo[typeKey]
    if info then
        return info.r or 1, info.g or 1, info.b or 1
    end
    return 1, 1, 1
end

-- Build the display line for a NON-secret body. Secret/absent sender or
-- channel args degrade gracefully (drop that fragment; never touch secrets).
-- Args mirror the CHAT_MSG_* payload positions used: text=arg1, sender=arg2,
-- channelNumber=arg8, channelBaseName=arg9.
function Format.BuildLine(event, text, sender, channelNumber, channelName)
    -- Contract: non-secret string body (capture guards this). Degrade to an
    -- empty body rather than erroring/tainting if a future caller slips.
    if IsSecret(text) or type(text) ~= "string" then text = "" end
    local typeKey = Format.EventToTypeKey(event)
    local prefix = ""
    if typeKey == "CHANNEL" then
        if not IsSecret(channelName) and type(channelName) == "string" and channelName ~= "" then
            if not IsSecret(channelNumber) and type(channelNumber) == "number" and channelNumber > 0 then
                prefix = ("[%d. %s] "):format(channelNumber, channelName)
            else
                prefix = ("[%s] "):format(channelName)
            end
        end
    elseif typeKey and TYPE_PREFIX[typeKey] then
        prefix = TYPE_PREFIX[typeKey]
    end

    local senderPart = ""
    if not IsSecret(sender) and type(sender) == "string" and sender ~= "" then
        local shown = (_G.Ambiguate and _G.Ambiguate(sender, "short")) or sender
        if typeKey == "BN_WHISPER" or typeKey == "BN_WHISPER_INFORM" then
            -- BN senders are display names, not Char-Realm; a |Hplayer:| link
            -- would be a broken click target (a proper |HBNplayer:| link needs
            -- the bnSenderID). Render plain until Phase 2 passes arg13 through.
            senderPart = ("[%s]: "):format(shown)
        else
            senderPart = ("|Hplayer:%s|h[%s]|h: "):format(sender, shown)
        end
    end

    return prefix .. senderPart .. text
end
