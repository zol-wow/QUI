-- tests/unit/cdm_effects_glow_resync_idempotent_test.lua
-- Run: lua tests/unit/cdm_effects_glow_resync_idempotent_test.lua
--
-- Regression: a single proc (Hammer of Light overriding Wake of Ashes) drives
-- several back-to-back post-layout refreshes (RunPostLayoutRefresh). Each one
-- used to call RefreshAllGlows, whose StopAllTrackedGlows + ScanAllGlows tore
-- every glow down and restarted it -- replaying the proc glow's intro animation
-- (a visible flash) on every refresh, so the glow flashed repeatedly at proc
-- start. The post-layout path now calls ResyncAllGlows, which diffs per icon
-- via SyncGlowForIcon and leaves a still-valid glow untouched (no flash). The
-- settings path keeps using RefreshAllGlows (teardown+reapply) so a changed
-- glow type/color still takes effect.

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

-- One proc-on-usable icon, glowing while `usable` is true.
local usable = true
local procIcon = {
    _spellEntry = {
        spellID = 12345, id = 12345, type = "spell",
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
        QuerySpellUsable = function(spellID)
            if spellID ~= 12345 then return false, false end
            return usable, false
        end,
    },
    CDMSpellData = {
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        GetSpellOverride = function(_, viewerType, spellID)
            if viewerType == "essential" and spellID == 12345 then
                return { procOnUsable = true }
            end
        end,
    },
    CDMIconFactory = {
        ForEachIcon = function(_, callback) callback(procIcon) end,
        GetIconPool = function() return {} end,
    },
    CDMResolvers = { ResolveAuraActiveState = function() return false end },
    CDMIcons = {},
    CDMRuntimeStore = {
        GetFrameState = function(frame) return frame and frame._cdmRuntimeState or nil end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_frame_writes.lua", "cdm_effects.lua")("QUI", ns)

local Glows = ns._OwnedGlows
assert(Glows, "effects module should publish ns._OwnedGlows")
assert(type(Glows.ResyncAllGlows) == "function", "ResyncAllGlows must be exported")
assert(type(Glows.RefreshAllGlows) == "function", "RefreshAllGlows must be exported")

-- Establish a steady glow on the proc icon.
local eventFrame
for _, frame in ipairs(frames) do
    if frame.events.SPELL_UPDATE_USABLE then eventFrame = frame break end
end
assert(eventFrame and eventFrame.OnEvent, "glow event frame should exist")
eventFrame.OnEvent(eventFrame, "SPELL_UPDATE_USABLE")
assert(glowStarts == 1, "usable proc-on-usable spell should start glowing")
assert(Glows.activeGlowIcons[procIcon] == true, "proc icon should be tracked as glowing")

-- 1. ResyncAllGlows called repeatedly (mimicking back-to-back post-layout
--    refreshes during a proc) must NOT tear the glow down or restart it.
local startsBefore, stopsBefore = glowStarts, glowStops
for _ = 1, 5 do
    Glows.ResyncAllGlows()
end
assert(glowStarts == startsBefore,
    "ResyncAllGlows must not restart a still-valid glow (no flash); got "
        .. tostring(glowStarts - startsBefore) .. " extra start(s)")
assert(glowStops == stopsBefore,
    "ResyncAllGlows must not stop a still-valid glow; got "
        .. tostring(glowStops - stopsBefore) .. " stop(s)")
assert(Glows.activeGlowIcons[procIcon] == true,
    "proc icon should remain tracked as glowing after resync")

-- 2. The settings path (RefreshAllGlows) still tears down and re-applies so a
--    changed glow type/color takes effect.
local startsBeforeRefresh, stopsBeforeRefresh = glowStarts, glowStops
Glows.RefreshAllGlows()
assert(glowStops > stopsBeforeRefresh,
    "RefreshAllGlows must stop existing glows (settings re-apply)")
assert(glowStarts > startsBeforeRefresh,
    "RefreshAllGlows must restart glows with current settings")
assert(Glows.activeGlowIcons[procIcon] == true,
    "proc icon should be glowing again after a settings refresh")

-- 3. When the glow should genuinely stop (spell no longer usable), ResyncAllGlows
--    still stops it -- idempotency must not mean "never change".
usable = false
local stopsBeforeOff = glowStops
Glows.ResyncAllGlows()
assert(glowStops > stopsBeforeOff,
    "ResyncAllGlows must stop a glow whose icon should no longer glow")
assert(Glows.activeGlowIcons[procIcon] == nil,
    "proc icon should no longer be tracked as glowing")

print("OK: cdm_effects_glow_resync_idempotent_test")
