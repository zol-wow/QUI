-- tests/unit/chat_suppress_combat_reload_early_apply_test.lua
-- Run: lua tests/unit/chat_suppress_combat_reload_early_apply_test.lua

local function makeBlizzFrame(name, parent)
    local f = { name = name, parent = parent }
    f.GetName = function() return name end
    f.GetParent = function(s) return s.parent end
    f.SetParent = function(s, p) s.parent = p; if s._setParentHook then s._setParentHook(s, p) end end
    f.scripts = {}
    f.SetScript = function(s, k, v) s.scripts[k] = v end
    f.GetScript = function(s, k) return s.scripts[k] end
    f.Hide = function() error("Hide() on Blizzard chat frame is forbidden: " .. name) end
    f.SetPoint = function() error("SetPoint on Blizzard chat frame is forbidden: " .. name) end
    f.SetSize = function() error("SetSize on Blizzard chat frame is forbidden: " .. name) end
    f.events = {}
    f.RegisterEvent = function(s, e) s.events[e] = true; if s._registerHook then s._registerHook(s, e) end end
    f.UnregisterEvent = function(s, e) s.events[e] = nil; if s._unregisterHook then s._unregisterHook(s, e) end end
    f.UnregisterAllEvents = function(s) s.events = {} end
    f.GetID = function(s) return s.id or 1 end
    f.RegisterForMessages = function(s, ...) s.messagesRegistered = { ... } end
    f.RegisterForChannels = function(s, ...)
        s.channelsRegistered = { ... }
        s.channelList = {}
        s.zoneChannelList = {}
    end
    return f
end

_G.UIParent = { name = "UIParent" }
_G.NUM_CHAT_WINDOWS = 2
_G.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
_G.ChatFrame1 = makeBlizzFrame("ChatFrame1", _G.UIParent); _G.ChatFrame1.id = 1
_G.ChatFrame1Tab = makeBlizzFrame("ChatFrame1Tab", { name = "Dock" })
_G.ChatFrame1ButtonFrame = makeBlizzFrame("ChatFrame1ButtonFrame", _G.ChatFrame1)
_G.ChatFrame2 = makeBlizzFrame("ChatFrame2", _G.UIParent); _G.ChatFrame2.id = 2
_G.ChatFrame2Tab = makeBlizzFrame("ChatFrame2Tab", { name = "Dock" })
_G.ChatFrame2ButtonFrame = makeBlizzFrame("ChatFrame2ButtonFrame", _G.ChatFrame2)
_G.ChatFrame1EditBox = makeBlizzFrame("ChatFrame1EditBox", _G.ChatFrame1)
_G.GeneralDockManager = makeBlizzFrame("Dock", _G.UIParent)
_G.ChatMenu = makeBlizzFrame("ChatMenu", _G.UIParent)
_G.TextToSpeechButtonFrame = makeBlizzFrame("TextToSpeechButtonFrame", _G.UIParent)
_G.QuickJoinToastButton = makeBlizzFrame("QuickJoinToastButton", _G.UIParent)
_G.ChatFrameToggleVoiceDeafenButton = makeBlizzFrame("ChatFrameToggleVoiceDeafenButton", _G.UIParent)
_G.ChatFrameToggleVoiceMuteButton = makeBlizzFrame("ChatFrameToggleVoiceMuteButton", _G.UIParent)
_G.ChatFrame1.events = { CHAT_MSG_SAY = true, UPDATE_CHAT_WINDOWS = true }
_G.ChatFrame2.events = { COMBAT_LOG_EVENT = true, UPDATE_CHAT_WINDOWS = true }
_G.ChatTypeGroup = { GUILD = { "CHAT_MSG_GUILD", "GUILD_MOTD" } }
_G.ChatTypeGroupInverted = { CHAT_MSG_GUILD = "GUILD", GUILD_MOTD = "GUILD" }

local unpack = table.unpack or _G.unpack
function _G.GetChatWindowMessages() return "SAY", "GUILD" end
function _G.GetChatWindowChannels() return unpack({ "Trade", 0 }) end
_G.C_EventUtils = { IsEventValid = function() return true end }
_G.FCF_OpenTemporaryWindow = function() end
_G.FCF_OpenNewWindow = function() end
_G.FloatingChatFrameManager = makeBlizzFrame("FloatingChatFrameManager", _G.UIParent)

function _G.hooksecurefunc(tbl, name, fn)
    if type(tbl) == "string" then return end
    if name == "SetParent" then
        tbl._setParentHook = function(self, p) fn(self, p) end
    elseif name == "RegisterEvent" then
        tbl._registerHook = function(self, e) fn(self, e) end
    elseif name == "UnregisterEvent" then
        tbl._unregisterHook = function(self, e) fn(self, e) end
    elseif name == "SetScript" then
        local orig = tbl.SetScript
        tbl.SetScript = function(self, k, v) orig(self, k, v); fn(self, k, v) end
    end
end

local createdFrames = {}
function _G.CreateFrame(_, name, parent)
    local f = { name = name, parent = parent, events = {}, shown = true }
    f.Hide = function(s) s.shown = false end
    f.Show = function(s) s.shown = true end
    f.RegisterEvent = function(s, e) s.events[e] = true end
    f.UnregisterAllEvents = function(s) s.events = {} end
    f.SetScript = function(s, k, v) s["_" .. k] = v end
    f.GetParent = function(s) return s.parent end
    f.SetParent = function(s, p) s.parent = p end
    createdFrames[#createdFrames + 1] = f
    return f
end

local afterCalls = {}
_G.C_Timer = { After = function(_, fn) afterCalls[#afterCalls + 1] = fn end }

_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function(unit) return unit == "player" end

local settings = { enabled = true, customDisplay = {} }
local ns = {
    Helpers = { IsSecretValue = function() return false end },
    -- core/safecall.lua stub (Task 45b ns-mock precedent).
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
    QUI = { Chat = { _internals = {
        GetSettings = function() return settings end,
        IsChatEnabled = function(s) return s and s.enabled ~= false end,
    } } },
}

assert(loadfile("QUI_Chat/chat/blizzard_suppress.lua"))("QUI", ns)
local SP = ns.QUI.Chat.BlizzardSuppress

-- Combat /reload: Apply() must suppress SYNCHRONOUSLY, before PEW fires.
SP.Apply()
assert(SP.IsActive(), "combat /reload: suppression active synchronously (no wait for PEW)")

local hidden
for _, f in ipairs(createdFrames) do
    if f.name == "QUI_ChatSuppressAnchor" then hidden = f end
end
assert(hidden, "hidden anchor created")
assert(_G.ChatFrame1.parent == hidden, "ChatFrame1 reparented to hidden anchor in the load grace")
assert(_G.ChatFrame2.parent == hidden, "ChatFrame2 reparented in the load grace")
assert(_G.ChatFrame1Tab.parent == hidden, "tab reparented in the load grace")
assert(_G.ChatFrame1ButtonFrame.parent == hidden, "button frame reparented in the load grace")
assert(_G.GeneralDockManager.parent == hidden, "dock reparented in the load grace")
assert(_G.ChatFrame1EditBox.parent == _G.UIParent, "editbox parented OUT to UIParent")

-- The PEW path stays armed (later flips/diagnostics still route through it).
local pewFrame
for _, f in ipairs(createdFrames) do
    if f.events.PLAYER_ENTERING_WORLD then pewFrame = f end
end
assert(pewFrame, "PEW frame still registered after early apply")

-- No redundant deferred re-apply was queued (we applied synchronously, so
-- pendingApply is false when PEW fires).
pewFrame._OnEvent(pewFrame, "PLAYER_ENTERING_WORLD")
assert(#afterCalls == 0, "no C_Timer.After re-apply queued at PEW (already applied early)")

-- Idempotent: still active, frames still parked. Latch makes any further
-- Apply() a no-op.
assert(SP.IsActive(), "still active after PEW")
assert(_G.ChatFrame1.parent == hidden, "frame stays parked after PEW")
local p = _G.ChatFrame1.parent
SP.Apply()
assert(_G.ChatFrame1.parent == p, "post-PEW Apply latched to no-op")

print("OK: chat_suppress_combat_reload_early_apply_test")
