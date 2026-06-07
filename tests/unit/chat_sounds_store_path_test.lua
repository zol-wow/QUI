-- tests/unit/chat_sounds_store_path_test.lua
-- Run: lua tests/unit/chat_sounds_store_path_test.lua
-- Verifies the store-subscriber sound path in sounds.lua:
--   suppressed + matching event  → PlaySoundFile called once
--   not suppressed               → STILL plays (store path owns ALL windows
--                                    incl. the pre-PEW login window)
--   secret entry (entry.s=true)  → silent
--   e="BACKFILL"                 → silent
--   e="ADDMESSAGE"               → silent
--   e="HISTORY"                  → silent
--   self-GUID entry              → silent
--   lockdown active              → silent
--   channel mismatch             → silent (entry event not in configured channel)
--
-- Channel-matching reference (SOUND_CHANNEL_EVENTS in sounds.lua):
--   guild_officer → CHAT_MSG_GUILD, CHAT_MSG_OFFICER
--   guild         → CHAT_MSG_GUILD
--   party         → CHAT_MSG_PARTY, CHAT_MSG_PARTY_LEADER
--   whisper       → CHAT_MSG_WHISPER, CHAT_MSG_BN_WHISPER
-- luacheck: globals PlaySoundFile UnitGUID hooksecurefunc C_Timer NUM_CHAT_WINDOWS ChatFrame1 ChatFrame2

local soundsPlayed = 0
function _G.PlaySoundFile()
    soundsPlayed = soundsPlayed + 1
end

function _G.UnitGUID(unit)
    if unit == "player" then return "Player-Self-0001" end
    return nil
end

-- hooksecurefunc: for this test we only need the table-method variant (frame
-- AddMessage hooks); we stub it as a passthrough so sounds.lua loads cleanly.
local hooksecureCount = 0
function _G.hooksecurefunc(target, method, fn)
    if type(target) == "table" then
        -- Wrap the existing method so the hook fires after.
        local original = target[method] or function() end
        target[method] = function(self, ...)
            local r = { original(self, ...) }
            fn(self, ...)
            return table.unpack and table.unpack(r) or unpack(r)
        end
        hooksecureCount = hooksecureCount + 1
    end
    -- global-name variant: no-op for this test
end

_G.C_Timer = { After = function(_, cb) cb() end }
_G.NUM_CHAT_WINDOWS = 2

local function newChatFrame()
    local f = {}
    function f:AddMessage() end
    return f
end
_G.ChatFrame1 = newChatFrame()
_G.ChatFrame2 = newChatFrame()

local locked = false
local suppressActive = false

local settings = {
    enabled = true,
    newMessageSound = {
        enabled = true,
        entries = {
            { channel = "guild_officer", sound = "ding.ogg" },
        },
    },
}

local storeSubscribers = {}

local ns = {
    Helpers = {
        IsSecretValue = function(v) return type(v) == "table" and v.__secret == true end,
    },
    LSM = {
        -- Fetch returns the sound name as the "path" so PlaySoundFile gets called.
        Fetch = function(_, _, name) return name end,
    },
    QUI = {
        Chat = {
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                IsChatMessagingLockedDown = function() return locked end,
            },
            -- MessageStore stub: captures OnAppend subscribers.
            MessageStore = {
                OnAppend = function(_, fn)
                    -- Called as Store.OnAppend(fn) — fn is first arg here
                    -- because sounds.lua calls Store.OnAppend(function(entry)...)
                    storeSubscribers[#storeSubscribers + 1] = fn
                end,
            },
            -- BlizzardSuppress stub: toggleable.
            BlizzardSuppress = {
                IsActive = function() return suppressActive end,
            },
        },
    },
}

-- Fix: MessageStore.OnAppend is called as Store.OnAppend(fn) (not Store:OnAppend(fn))
-- so the first arg IS the function. Patch to handle both.
ns.QUI.Chat.MessageStore.OnAppend = function(fn)
    if type(fn) == "function" then
        storeSubscribers[#storeSubscribers + 1] = fn
    end
end

assert(loadfile("modules/chat/sounds.lua"))("QUI", ns)
ns.QUI.Chat.Sounds.Setup()

-- Verify a store subscriber was installed.
assert(#storeSubscribers == 1, "one store subscriber installed on Setup, got " .. #storeSubscribers)

local function fire(entry)
    storeSubscribers[1](entry)
end

-- Helper to snapshot and reset count.
local function played()
    local n = soundsPlayed
    soundsPlayed = 0
    return n
end

-------------------------------------------------------------------------------
-- Case 1: suppressed + CHAT_MSG_GUILD (matches guild_officer channel) → play
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "CHAT_MSG_GUILD", gid = "Player-Other-0002", s = false })
assert(played() == 1, "case 1: suppressed + guild event should play once")

-------------------------------------------------------------------------------
-- Case 2: not suppressed (pre-PEW window) → STILL plays (single path)
-------------------------------------------------------------------------------
suppressActive = false
fire({ e = "CHAT_MSG_GUILD", gid = "Player-Other-0002", s = false })
assert(played() == 1, "case 2: not suppressed must STILL play (single path)")
suppressActive = true

-------------------------------------------------------------------------------
-- Case 3: secret entry (entry.s = true) → silent
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "CHAT_MSG_GUILD", gid = nil, s = true })
assert(played() == 0, "case 3: secret entry → silent")

-------------------------------------------------------------------------------
-- Case 4: e = "BACKFILL" → silent
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "BACKFILL", gid = "Player-Other-0002", s = false })
assert(played() == 0, "case 4: e=BACKFILL → silent")

-------------------------------------------------------------------------------
-- Case 5: e = "ADDMESSAGE" → silent
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "ADDMESSAGE", gid = "Player-Other-0002", s = false })
assert(played() == 0, "case 5: e=ADDMESSAGE → silent")

-------------------------------------------------------------------------------
-- Case 6: e = "HISTORY" → silent
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "HISTORY", gid = "Player-Other-0002", s = false })
assert(played() == 0, "case 6: e=HISTORY → silent")

-------------------------------------------------------------------------------
-- Case 7: self-GUID → silent
-- UnitGUID("player") returns "Player-Self-0001" above.
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "CHAT_MSG_GUILD", gid = "Player-Self-0001", s = false })
assert(played() == 0, "case 7: self-GUID → silent")

-------------------------------------------------------------------------------
-- Case 8: lockdown active → silent
-------------------------------------------------------------------------------
suppressActive = true
locked = true
fire({ e = "CHAT_MSG_GUILD", gid = "Player-Other-0002", s = false })
assert(played() == 0, "case 8: lockdown → silent")
locked = false

-------------------------------------------------------------------------------
-- Case 9: channel mismatch — CHAT_MSG_SAY not in guild_officer entries → silent
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "CHAT_MSG_SAY", gid = "Player-Other-0002", s = false })
assert(played() == 0, "case 9: channel mismatch → silent")

-------------------------------------------------------------------------------
-- Case 10: suppressed + CHAT_MSG_OFFICER (also matches guild_officer) → play
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "CHAT_MSG_OFFICER", gid = "Player-Other-0002", s = false })
assert(played() == 1, "case 10: suppressed + officer event should play once")

-------------------------------------------------------------------------------
-- Case 11: gid = nil (no GUID, e.g. NPC or absent) → plays (cannot self-suppress)
-- Matches guild_officer channel, gid nil means no self-check possible.
-------------------------------------------------------------------------------
suppressActive = true
fire({ e = "CHAT_MSG_GUILD", gid = nil, s = false })
assert(played() == 1, "case 11: nil gid → plays (no self-suppress possible)")

print("OK: chat_sounds_store_path_test")
