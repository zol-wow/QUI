-- tests/unit/cdm_effects_no_combat_end_rescan_test.lua
-- Run: lua5.1 tests/unit/cdm_effects_no_combat_end_rescan_test.lua
--
-- The effects event frame previously registered PLAYER_REGEN_ENABLED, which
-- caused ScanAllGlows() to run unconditionally at every combat end. Glow state
-- is maintained live in combat (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE), so
-- the rescan is redundant and was contributing to the end-of-pull FPS stutter.
-- This test verifies the registration is gone while the live glow events remain.

local function noop() end

function InCombatLockdown() return false end
function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end

local frames = {}
function CreateFrame()
    local frame = {
        events = {},
        RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterAllEvents = noop,
        SetScript = function(self, script, handler) self[script] = handler end,
        SetAllPoints = noop,
        SetAlpha = noop,
        GetFrameLevel = function() return 1 end,
        SetFrameLevel = noop,
    }
    frames[#frames + 1] = frame
    return frame
end

C_Timer = {
    NewTicker = function() return { Cancel = noop } end,
    NewTimer = function() return { Cancel = noop } end,
}

function LibStub()
    return {
        PixelGlow_Start = noop,
        PixelGlow_Stop = noop,
        AutoCastGlow_Stop = noop,
        ButtonGlow_Stop = noop,
        ProcGlow_Stop = noop,
    }
end

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
        GetModuleSettings = function(_, defaults) return defaults end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        SettingEnabled = function(value, fallback)
            if value == nil then return fallback == true end
            return value == true
        end,
        GetBuiltinContainerKeysByEntryKind = function(entryKind)
            if entryKind == "cooldown" then return { "essential", "utility" } end
            return nil
        end,
        GetBuiltinContainerKeysByShape = function(shape)
            if shape == "icon" then return { "essential", "utility", "buff" } end
            return nil
        end,
        IsBuiltinAuraContainerKey = function(containerKey)
            return containerKey == "buff" or containerKey == "trackedBar"
        end,
    },
    CDMSources = {
        QueryOverrideSpell = function() return nil end,
        QueryBaseSpell = function() return nil end,
        QuerySpellUsable = function() return false, false end,
    },
    CDMSpellData = {
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        GetSpellOverride = function() return nil end,
    },
    CDMIconFactory = {
        ForEachIcon = function(_, _) end,
        GetIconPool = function() return {} end,
    },
    CDMResolvers = { ResolveAuraActiveState = function() return false end },
    CDMIcons = {},
    CDMRuntimeStore = {
        GetFrameState = function() return nil end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_frame_writes.lua", "cdm_effects.lua")("QUI", ns)

-- Find the glow event frame (the one registering the overlay glow events).
local glowFrame
for _, f in ipairs(frames) do
    if f.events and f.events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW then
        glowFrame = f
        break
    end
end
assert(glowFrame, "effects should register a glow event frame")

assert(not glowFrame.events.PLAYER_REGEN_ENABLED,
    "effects glow frame must NOT register PLAYER_REGEN_ENABLED -- the combat-end "
        .. "ScanAllGlows is redundant; glow is maintained live in combat")

-- Live glow events must remain registered.
assert(glowFrame.events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW,
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW must stay registered")
assert(glowFrame.events.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE,
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE must stay registered")
assert(glowFrame.events.SPELL_UPDATE_USABLE,
    "SPELL_UPDATE_USABLE must stay registered")
assert(glowFrame.events.SPELL_UPDATE_COOLDOWN,
    "SPELL_UPDATE_COOLDOWN must stay registered")

print("OK: cdm_effects_no_combat_end_rescan_test")
