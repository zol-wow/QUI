-- tests/cdm_effects_proc_on_usable_test.lua
-- Run: lua tests/cdm_effects_proc_on_usable_test.lua

local function noop() end

function InCombatLockdown() return false end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local frames = {}
function CreateFrame()
    local frame = {
        events = {},
        RegisterEvent = function(self, event)
            self.events[event] = true
        end,
        UnregisterAllEvents = noop,
        SetScript = function(self, script, handler)
            self[script] = handler
        end,
        SetAllPoints = noop,
        SetAlpha = noop,
        GetFrameLevel = function() return 1 end,
        SetFrameLevel = noop,
    }
    frames[#frames + 1] = frame
    return frame
end

C_Timer = {
    NewTicker = function()
        return { Cancel = noop }
    end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local glowStarts = 0
local glowStops = 0
function LibStub()
    return {
        PixelGlow_Start = function()
            glowStarts = glowStarts + 1
        end,
        PixelGlow_Stop = function()
            glowStops = glowStops + 1
        end,
        AutoCastGlow_Stop = noop,
        ButtonGlow_Stop = noop,
        ProcGlow_Stop = noop,
    }
end

local usable = false
local callbackVisits = 0
local forEachCalls = 0
local icon = {
    _spellEntry = {
        spellID = 12345,
        id = 12345,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
    },
    IsShown = function() return true end,
    GetFrameLevel = function() return 1 end,
    Cooldown = {
        GetFrameLevel = function() return 1 end,
    },
}
local idleIcon = {
    _spellEntry = {
        spellID = 67890,
        id = 67890,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
    },
    IsShown = function() return true end,
    GetFrameLevel = function() return 1 end,
    Cooldown = {
        GetFrameLevel = function() return 1 end,
    },
}
local auraIcon = {
    _spellEntry = {
        spellID = 54321,
        id = 54321,
        type = "spell",
        kind = "aura",
        viewerType = "essential",
    },
    IsShown = function() return true end,
    GetFrameLevel = function() return 1 end,
    Cooldown = {
        GetFrameLevel = function() return 1 end,
    },
}

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function()
                return {
                    essentialEnabled = true,
                    essentialGlowType = "Pixel Glow",
                    essentialColor = { 1, 1, 1, 1 },
                }
            end
        end,
        GetModuleSettings = function(_, defaults)
            return defaults
        end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        SettingEnabled = function(value, fallback)
            if value == nil then return fallback == true end
            return value == true
        end,
    },
    CDMSources = {
        QuerySpellUsable = function(spellID)
            assert(spellID == 12345, "unexpected spell usability query")
            return usable, false
        end,
    },
    CDMSpellData = {
        IsAuraEntry = function(entry)
            return entry and entry.kind == "aura"
        end,
        GetSpellOverride = function(_, viewerType, spellID)
            if viewerType == "essential" and spellID == 12345 then
                return { procOnUsable = true }
            elseif viewerType == "essential" and spellID == 54321 then
                return { procOnUsable = true }
            end
        end,
    },
    CDMIcons = {
        ForEachIcon = function(_, callback)
            forEachCalls = forEachCalls + 1
            callbackVisits = callbackVisits + 1
            callback(icon)
            callbackVisits = callbackVisits + 1
            callback(idleIcon)
            callbackVisits = callbackVisits + 1
            callback(auraIcon)
        end,
        GetIconPool = function() return {} end,
        IsAuraCurrentlyActive = function() return false end,
    },
}

assert(loadfile("modules/cdm/cdm_effects.lua"))("QUI", ns)

local eventFrame
for _, frame in ipairs(frames) do
    if frame.events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW then
        eventFrame = frame
        break
    end
end

assert(eventFrame, "glow event frame should exist")
assert(eventFrame.events.SPELL_UPDATE_USABLE, "proc-on-usable glow should listen for usability events")
assert(eventFrame.OnEvent, "glow event frame should have an OnEvent handler")

eventFrame.OnEvent(eventFrame, "SPELL_UPDATE_USABLE")
assert(glowStarts == 0, "unusable spell should not start proc-on-usable glow")

usable = true
eventFrame.OnEvent(eventFrame, "SPELL_UPDATE_USABLE")
assert(glowStarts == 1, "usable spell should start proc-on-usable glow")
assert(ns._OwnedGlows.activeGlowIcons[icon] == true, "usable spell should be tracked as glowing")

forEachCalls = 0
callbackVisits = 0
usable = false
eventFrame.OnEvent(eventFrame, "SPELL_UPDATE_USABLE")
assert(glowStops >= 1, "unusable spell should stop proc-on-usable glow")
assert(ns._OwnedGlows.activeGlowIcons[icon] == nil, "unusable spell should no longer be tracked as glowing")
assert(forEachCalls == 0, "steady-state proc-on-usable events should not call ForEachIcon")
assert(callbackVisits == 0, "steady-state proc-on-usable events should not visit non-proc icons")

print("OK: cdm_effects_proc_on_usable_test")
