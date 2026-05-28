-- tests/unit/cdm_spelldata_target_aura_capture_test.lua
-- Run: lua tests/unit/cdm_spelldata_target_aura_capture_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame

local function noop() end
local frames = {}
local inCombat = true

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

local targetAuraDuration = { token = "target-aura-duration" }

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
        QueryAuraFilteredOutByInstanceID = function(unit, auraInstanceID, filter)
            if unit == "target"
                and auraInstanceID == 9052
                and filter == "HELPFUL|PLAYER" then
                return false
            end
            return true
        end,
        QueryAuraDuration = function(unit, auraInstanceID)
            if unit == "target" and auraInstanceID == 9052 then
                return targetAuraDuration
            end
        end,
        QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
            if unit == "target" and auraInstanceID == 9052 then
                return {
                    spellId = 51052,
                    auraInstanceID = 9052,
                    isHelpful = true,
                    isFromPlayerOrPlayerPet = true,
                }
            end
        end,
        QueryUnitAuraBySpellID = function()
            return nil
        end,
    },
    CDMBlizzMirror = {
        HandleUnitAuraChanged = noop,
    },
    CDMIcons = {
        HandleRuntimeRefresh = noop,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

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
assert(state.durObj == targetAuraDuration,
    "target aura capture should forward the target aura DurationObject")

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

print("OK: cdm_spelldata_target_aura_capture_test")
