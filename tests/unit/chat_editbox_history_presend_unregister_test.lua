-- tests/unit/chat_editbox_history_presend_unregister_test.lua
-- Run: lua tests/unit/chat_editbox_history_presend_unregister_test.lua
--
-- The edit-box history pre-send capture callback (EventRegistry
-- "ChatFrame.OnEditBoxPreSendText") must be physically REGISTERED only while the
-- feature is active and UNREGISTERED otherwise -- not merely left installed and
-- short-circuiting internally. This guards the "remove the hooks when chat is
-- disabled" behavior. (The per-editbox OnArrowPressed / AddHistoryLine hooks use
-- HookScript / hooksecurefunc, which the WoW API cannot unhook; they are instead
-- gated at install time and covered by sibling tests + the reload prompt.)

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local EVENT = "ChatFrame.OnEditBoxPreSendText"
local OWNER = "QUI_ChatEditBoxHistory"

-- EventRegistry mock that tracks registrations by owner, mirroring
-- CallbackRegistryMixin:Register/UnregisterCallback(event, [func,] owner).
local function makeRegistry()
    local owners = {} -- event -> { [owner] = func }
    return {
        RegisterCallback = function(_, event, func, owner)
            owners[event] = owners[event] or {}
            owners[event][owner] = func
        end,
        UnregisterCallback = function(_, event, owner)
            assert(type(event) == "string", "UnregisterCallback needs string event")
            assert(owner ~= nil, "UnregisterCallback needs non-nil owner")
            if owners[event] then owners[event][owner] = nil end
        end,
        _isRegistered = function() return owners[EVENT] and owners[EVENT][OWNER] ~= nil end,
    }
end

function InCombatLockdown() return false end

function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
end

-- Build a fresh module instance with the given enabled flags. Each loadfile call
-- runs the chunk with fresh upvalues, so file-load registration is exercised.
local function loadModule(chatEnabled, historyEnabled)
    local settings = {
        enabled = chatEnabled,
        editboxHistory = { enabled = historyEnabled, maxEntries = 200 },
    }
    local ns = {
        Helpers = { IsSecretValue = function() return false end },
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
    _G.EventRegistry = makeRegistry()
    assert(loadfile("QUI_Chat/chat/editbox_history.lua"))("QUI", ns)
    return ns, settings, _G.EventRegistry
end

-- 1. Disabled chat module at load: callback must NOT be registered.
do
    local _, _, reg = loadModule(false, true)
    check("disabled chat: pre-send callback not registered at load", not reg._isRegistered())
end

-- 2. Enabled feature at load: callback IS registered.
do
    local ns, settings, reg = loadModule(true, true)
    check("enabled: pre-send callback registered at load", reg._isRegistered())

    -- 3. Toggle chat module OFF -> RefreshAll runs ApplyEnabled -> unregistered.
    settings.enabled = false
    for _, fn in ipairs(ns.QUI.Chat._afterRefresh) do fn() end
    check("toggle off: pre-send callback unregistered live", not reg._isRegistered())

    -- 4. Toggle back ON -> re-registered.
    settings.enabled = true
    for _, fn in ipairs(ns.QUI.Chat._afterRefresh) do fn() end
    check("toggle on: pre-send callback re-registered", reg._isRegistered())
end

-- 5. History sub-feature off (chat enabled) also keeps the callback out.
do
    local _, _, reg = loadModule(true, false)
    check("history sub-toggle off: pre-send callback not registered", not reg._isRegistered())
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
