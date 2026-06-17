-- tests/unit/cdm_effects_overlay_glow_latch_test.lua
-- Run: lua tests/unit/cdm_effects_overlay_glow_latch_test.lua
--
-- Regression: Ret Paladin Wake of Ashes (255937) procs Hammer of Light, whose
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW fires for the override 427453. The essential
-- icon is glowed off that overlay. The proc also fires SPELLS_CHANGED, during
-- which Blizzard's override spell briefly stops resolving: a routine ScanAllGlows
-- that lands in that window calls QueryOverrideSpell(255937) and gets nil, so
-- FindAllowedOverlayGlow no longer links the icon to the still-active overlay
-- 427453 and tears the glow down. Once the override settles the next scan turns
-- it back on -- replaying the proc glow's intro animation: a visible flicker at
-- proc start.
--
-- The overlay glow is now latched on overlayedSpells (the authoritative overlay
-- state, set by GLOW_SHOW and cleared only by GLOW_HIDE). A scan that fails to
-- re-link the icon while overlayedSpells[427453] is still true leaves the glow
-- untouched; only GLOW_HIDE may stop it.

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

local glowStarts = 0
local glowStops = 0
function LibStub()
    return {
        PixelGlow_Start = function() glowStarts = glowStarts + 1 end,
        PixelGlow_Stop = function() glowStops = glowStops + 1 end,
        AutoCastGlow_Stop = noop,
        ButtonGlow_Stop = noop,
        ProcGlow_Stop = noop,
    }
end

local WAKE = 255937   -- base; stable icon identity throughout the proc
local HOL = 427453    -- override that procs; the overlay GLOW_SHOW fires for this

-- Blizzard's override resolver. Flipped to "blind" to model the transient
-- mid-SPELLS_CHANGED window where QueryOverrideSpell(WAKE) stops returning HOL.
local overrideResolves = true

-- One overlay-driven essential icon (no procOnUsable, no per-spell glow override:
-- the glow comes purely from the spell-activation overlay).
local icon = {
    _spellEntry = {
        spellID = WAKE, id = WAKE, type = "spell",
        kind = "cooldown", viewerType = "essential",
    },
    IsShown = function() return true end,
    GetFrameLevel = function() return 1 end,
    Cooldown = { GetFrameLevel = function() return 1 end },
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
        -- Override resolution: blind during the transient. HOL has no base/override.
        QueryOverrideSpell = function(spellID)
            if spellID == WAKE and overrideResolves then return HOL end
            return nil
        end,
        QueryBaseSpell = function() return nil end,
        QuerySpellUsable = function() return false, false end,
    },
    CDMSpellData = {
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        GetSpellOverride = function() return nil end,  -- no per-spell glow override
    },
    CDMIconFactory = {
        ForEachIcon = function(_, callback) callback(icon) end,
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

local Glows = ns._OwnedGlows
assert(Glows, "effects module should publish ns._OwnedGlows")
assert(type(Glows.ScheduleGlowScan) == "function", "ScheduleGlowScan must be exported")

-- Find the overlay event frame.
local eventFrame
for _, frame in ipairs(frames) do
    if frame.events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW then eventFrame = frame break end
end
assert(eventFrame and eventFrame.OnEvent, "overlay glow event frame should exist")

local function fireGlowShow(spellID)
    eventFrame.OnEvent(eventFrame, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", spellID)
end
local function fireGlowHide(spellID)
    eventFrame.OnEvent(eventFrame, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", spellID)
end

-- Proc start: the overlay shows for HOL; the override resolves WAKE -> HOL, so a
-- scan links the icon to the active overlay and glows it.
fireGlowShow(HOL)
Glows.ScheduleGlowScan()
-- The first application starts the glow once. ApplyLibCustomGlow always issues a
-- pre-start StopGlow (a no-op here, nothing was glowing yet), so one benign stop
-- is expected -- the flash would be EXTRA start/stop cycles beyond this baseline.
assert(glowStarts == 1, "overlay GLOW_SHOW should start the icon glow once; got " .. glowStarts)
assert(Glows.activeGlowIcons[icon] == true, "icon should be tracked as glowing")

-- TRANSIENT: mid-SPELLS_CHANGED the override stops resolving. A routine scan now
-- cannot re-link the icon (QueryOverrideSpell(WAKE) -> nil, so FindAllowedOverlayGlow
-- misses 427453) -- but the overlay itself is still active. The latch must keep the
-- glow untouched: NO stop, NO restart (the pre-fix bug tore it down then re-applied).
overrideResolves = false
local startsBefore, stopsBefore = glowStarts, glowStops
Glows.ScheduleGlowScan()
Glows.ScheduleGlowScan()
assert(glowStops == stopsBefore,
    "a scan that fails to re-link a still-active overlay must NOT stop the glow; got "
        .. (glowStops - stopsBefore) .. " stop(s)")
assert(glowStarts == startsBefore,
    "no restart (hence no intro-animation flicker) expected during the transient; got "
        .. (glowStarts - startsBefore) .. " start(s)")
assert(Glows.activeGlowIcons[icon] == true, "icon should remain glowing through the transient")

-- Override settles back. Still a no-op: glow already up.
overrideResolves = true
Glows.ScheduleGlowScan()
assert(glowStarts == startsBefore and glowStops == stopsBefore,
    "glow must stay continuously on once the override resolves again")

-- Proc end: GLOW_HIDE clears overlayedSpells[HOL]. Now the latch is genuinely
-- stale and the next scan stops the glow.
fireGlowHide(HOL)
Glows.ScheduleGlowScan()
assert(glowStops == stopsBefore + 1,
    "GLOW_HIDE must let the next scan stop the glow; got " .. (glowStops - stopsBefore) .. " stop(s)")
assert(Glows.activeGlowIcons[icon] == nil, "icon should no longer be tracked after GLOW_HIDE")

print("OK: cdm_effects_overlay_glow_latch_test")
