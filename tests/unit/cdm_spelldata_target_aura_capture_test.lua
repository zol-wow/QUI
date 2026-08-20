-- tests/unit/cdm_spelldata_target_aura_capture_test.lua
-- Run: lua tests/unit/cdm_spelldata_target_aura_capture_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame

local function noop() end
local frames = {}
local inCombat = true
local aurasSecret = false
local unitAuraScanCalls = 0

function InCombatLockdown() return inCombat end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    local frame = {
        events = {},
        unitEvents = {},
        RegisterEvent = function(self, event)
            self.events[event] = true
        end,
        RegisterUnitEvent = function(self, event, ...)
            self.unitEvents[event] = { ... }
        end,
        UnregisterEvent = noop,
        UnregisterAllEvents = function(self)
            self.events = {}
            self.unitEvents = {}
        end,
        SetScript = function(self, script, handler)
            if script == "OnEvent" then
                self.script = handler
            end
        end,
    }
    frames[#frames + 1] = frame
    return frame
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function(auraData)
            return auraData and auraData.isFromPlayerOrPlayerPet == true
        end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
    },
    CDMIcons = {
        HandleRuntimeRefresh = noop,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local auraFrame
for _, frame in ipairs(frames) do
    if frame.unitEvents.UNIT_AURA then
        auraFrame = frame
        break
    end
end
assert(auraFrame, "aura capture frame should register UNIT_AURA")

auraFrame.script(auraFrame, "UNIT_AURA", "target", {
    isFullUpdate = false,
    addedAuras = {
        {
            spellId = 51052,
            name = "Helpful Zone Aura",
            auraInstanceID = 9052,
            isHelpful = true,
            isFromPlayerOrPlayerPet = true,
        },
    },
})

local state = ns.CDMAuraRuntime.ResolveState({
    spellID = 51052,
    entrySpellID = 51052,
    entryID = 51052,
    entryName = "Helpful Zone Aura",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "buff",
})

assert(state.isActive == true,
    "target UNIT_AURA payload should activate the matching standard aura")
assert(state.auraUnit == "target",
    "target aura capture should preserve the target unit")
assert(state.auraInstanceID == 9052,
    "target aura capture should preserve the auraInstanceID")
assert(state.durObj == nil,
    "target aura capture must not query a DurationObject through C_UnitAuras")

auraFrame.script(auraFrame, "UNIT_AURA", "target", {
    isFullUpdate = false,
    removedAuraInstanceIDs = { 9052 },
})

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 51052,
    entrySpellID = 51052,
    entryID = 51052,
    entryName = "Helpful Zone Aura",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "buff",
})

assert(state.isActive ~= true,
    "target removedAuraInstanceIDs should evict target aura capture")

auraFrame.script(auraFrame, "UNIT_AURA", "target", {
    isFullUpdate = false,
    addedAuras = {
        {
            spellId = 51053,
            name = "Persistent Zone Aura",
            auraInstanceID = 9053,
            isHelpful = true,
            isFromPlayerOrPlayerPet = true,
        },
    },
})
auraFrame.script(auraFrame, "UNIT_AURA", "target", { isFullUpdate = true })
state = ns.CDMAuraRuntime.ResolveState({
    spellID = 51053,
    entrySpellID = 51053,
    entryID = 51053,
    entryName = "Persistent Zone Aura",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "buff",
})
assert(state.isActive == true,
    "target full updates must retain captured active auras when no safe rescan is available")

auraFrame.script(auraFrame, "UNIT_AURA", "target", {
    isFullUpdate = false,
    addedAuras = {
        {
            spellId = 51054,
            name = "Someone Else's Zone Aura",
            auraInstanceID = 9054,
            isHelpful = true,
            isFromPlayerOrPlayerPet = false,
        },
    },
})
state = ns.CDMAuraRuntime.ResolveState({
    spellID = 51054,
    entrySpellID = 51054,
    entryID = 51054,
    entryName = "Someone Else's Zone Aura",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "buff",
})
assert(state.isActive ~= true,
    "target aura capture must reject a readable aura owned by another player")

-- Aura restriction is broader than combat lockdown; captured payloads remain
-- the only target presence source.
inCombat = false
aurasSecret = true
AuraUtil = {
    ForEachAura = function()
        error("AuraUtil.ForEachAura must not run while auras are secret")
    end,
}
local ok, err = pcall(ns.CDMAuraRuntime.ResolveState, {
    spellID = 61052,
    entrySpellID = 61052,
    entryID = 61052,
    entryName = "Restricted Target Debuff",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "buff",
})
assert(ok, "secret target aura fallback must not throw: " .. tostring(err))
assert(unitAuraScanCalls == 0, "target fallback must not scan aura indexes")

print("OK: cdm_spelldata_target_aura_capture_test")
