-- tests/unit/chat_editbox_history_secure_command_test.lua
-- Run: lua tests/unit/chat_editbox_history_secure_command_test.lua
--
-- Slash commands are captured into edit-box history via an AddHistoryLine hook
-- (ParseText clears the edit box before the chat-message capture callback runs,
-- so slash commands are invisible there). Whether secure ("protected") commands
-- — /tm, /rt, /cast, ... per IsSecureCmd — are allowed into history is governed
-- by the allowSecureCommands policy switch:
--   * true  (default): they ARE captured and recalled. Safe because the real
--            taint root cause (the SlashCmdList global reassignment) is fixed
--            and recall uses SetText only, never SetAttribute.
--   * false (reference behavior): they are excluded at both capture and recall.
-- These tests exercise BOTH modes via EBH._SetAllowSecureCommands.

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

-- ---------------------------------------------------------------------------
-- Mock the Blizzard globals the module touches at load + runtime.
-- ---------------------------------------------------------------------------

-- Stand-in for Blizzard's IsSecureCmd: the protected commands that taint the
-- send path when recalled.
local SECURE = {
    ["/TM"] = true, ["/RT"] = true, ["/CAST"] = true, ["/USE"] = true,
    ["/TARGET"] = true, ["/FOCUS"] = true, ["/CLICK"] = true,
}
function IsSecureCmd(cmd)
    return cmd ~= nil and SECURE[string.upper(cmd)] == true
end

function InCombatLockdown() return false end

local createdFrames = {}
function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    table.insert(createdFrames, f)
    return f
end

-- ---------------------------------------------------------------------------
-- Minimal namespace the module asserts on at load.
-- ---------------------------------------------------------------------------

local settings = {
    enabled = true,
    editboxHistory = {
        enabled = true,
        filterSensitive = false, -- privacy filter OFF on purpose: taint gate must still apply
        maxEntries = 200,
    },
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    QUI = {
        Chat = {
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                IsTemporaryChatFrame = function() return false end,
                IsChatMessagingLockedDown = function() return false end,
            },
            _afterRefresh = {},
        },
    },
}

_G.QUI = { db = { char = {} } }

assert(loadfile("QUI_Chat/chat/editbox_history.lua"))("QUI", ns)
local EBH = ns.QUI.Chat.EditBoxHistory

-- ---------------------------------------------------------------------------
-- 1. Pure classifier recognises protected commands.
-- ---------------------------------------------------------------------------
check("classifier: /tm 8 is protected",
    EBH._IsProtectedCommand("/tm 8") == true)
check("classifier: /rt 0 is protected",
    EBH._IsProtectedCommand("/rt 0") == true)
check("classifier: /cast Fireball is protected",
    EBH._IsProtectedCommand("/cast Fireball") == true)
check("classifier: plain chat is not protected",
    EBH._IsProtectedCommand("hello world") == false)
check("classifier: /g guildchat is not protected",
    EBH._IsProtectedCommand("/g hi team") == false)
check("classifier: empty text is not protected",
    EBH._IsProtectedCommand("") == false)

-- The capture path tells a real slash command from a chat-type prefix purely by
-- hash_SlashCmdList membership: command handlers (/qui, /tm, ...) live there;
-- chat-type prefixes (/g, /s, /w) do NOT (they are captured by captureSent), so
-- they are skipped here and never double-stored.
_G.hash_SlashCmdList = {
    ["/QUI"] = function() end,
    ["/TM"] = function() end,
    ["/CAST"] = function() end,
    ["/RELOAD"] = function() end,
}

local function slashBox()
    return {
        chatFrame = {},
        GetText = function() return "" end,
        GetAttribute = function() return nil end,
    }
end

local function resetStore()
    QUI.db.char.chat = nil -- getStore() lazily re-creates the namespace
end

local function storedEntries()
    local store = QUI.db.char.chat and QUI.db.char.chat.editboxHistory
    return (store and store.entries) or {}
end

-- ---------------------------------------------------------------------------
-- 2. Default policy (allowSecureCommands = true): real slash commands are
--    captured, including secure ones; chat-type prefixes and unknown commands
--    are skipped so they are not double-stored.
-- ---------------------------------------------------------------------------
EBH._SetAllowSecureCommands(true)
resetStore()
EBH._captureSlashCommand(slashBox(), "/qui debug")
EBH._captureSlashCommand(slashBox(), "/tm 8")
EBH._captureSlashCommand(slashBox(), "/g hi team")    -- chat-type prefix: skip
EBH._captureSlashCommand(slashBox(), "/s hello")      -- in both lists: skip
EBH._captureSlashCommand(slashBox(), "/notacommand")  -- not a slash command: skip

local entries = storedEntries()
check("capture: /qui debug stored",
    entries[1] and entries[1].m == "/qui debug", entries[1] and entries[1].m or "nil")
check("capture: secure /tm 8 stored when allowed",
    entries[2] and entries[2].m == "/tm 8", entries[2] and entries[2].m or "nil")
check("capture: chat-type prefixes and unknown commands skipped",
    #entries == 2, ("expected 2 stored entries, got %d"):format(#entries))

-- Consecutive duplicate of the same command is collapsed.
EBH._captureSlashCommand(slashBox(), "/tm 8")
check("capture: consecutive duplicate command not re-stored",
    #storedEntries() == 2, ("expected 2 entries, got %d"):format(#storedEntries()))

-- ---------------------------------------------------------------------------
-- 3. Reference mode (allowSecureCommands = false): secure commands excluded,
--    non-secure slash commands still captured. This is the one-line fallback if
--    recalling a secure command via SetText is found to fault in-game.
-- ---------------------------------------------------------------------------
EBH._SetAllowSecureCommands(false)
resetStore()
EBH._captureSlashCommand(slashBox(), "/qui debug") -- non-secure: stored
EBH._captureSlashCommand(slashBox(), "/tm 8")      -- secure: excluded
local exclEntries = storedEntries()
check("capture(exclude): non-secure /qui still stored",
    #exclEntries == 1 and exclEntries[1].m == "/qui debug",
    ("got %d entries"):format(#exclEntries))

-- ---------------------------------------------------------------------------
-- 4. Recall write-back honours the policy switch.
-- ---------------------------------------------------------------------------
local function recallBox(sink)
    return {
        SetText = function(_, t) table.insert(sink, t) end,
        SetCursorPosition = function() end,
    }
end

EBH._SetAllowSecureCommands(false)
local exclWrites = {}
EBH._applyEntryToEditBox(recallBox(exclWrites), { m = "/tm 8" }, { restoreChatType = false })
check("recall(exclude): secure entry not written",
    #exclWrites == 0, ("expected 0 SetText calls, got %d"):format(#exclWrites))
EBH._applyEntryToEditBox(recallBox(exclWrites), { m = "hello again" }, { restoreChatType = false })
check("recall(exclude): plain entry written",
    #exclWrites == 1 and exclWrites[1] == "hello again", exclWrites[1] or "nil")

EBH._SetAllowSecureCommands(true)
local allowWrites = {}
EBH._applyEntryToEditBox(recallBox(allowWrites), { m = "/tm 8" }, { restoreChatType = false })
check("recall(allow): secure entry written back",
    #allowWrites == 1 and allowWrites[1] == "/tm 8", allowWrites[1] or "nil")

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
