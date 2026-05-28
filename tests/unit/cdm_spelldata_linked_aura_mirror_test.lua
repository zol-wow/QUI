-- tests/unit/cdm_spelldata_linked_aura_mirror_test.lua
-- Run: lua tests/unit/cdm_spelldata_linked_aura_mirror_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame

local function noop() end
local frames = {}

function InCombatLockdown() return false end
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
        RegisterEvent = noop,
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

local linkedAuraDuration = { token = "linked-aura-duration" }
local exactAuraDuration = { token = "exact-aura-duration" }

-- Models Blur: the parent cooldown reports hasAura=false, and its only link to
-- the buff is linkedSpellIDs. The overlay is sourced from that link but ONLY
-- when the linked ID resolves to a real aura-viewer mirror child carrying live
-- aura state (auraInstanceID + auraDurObj) -- a junk/unrelated link has no
-- backing aura child and is filtered out. Packed mirror state (PackState)
-- exposes activity via auraInstanceID/auraDurObj, not the removed isActive/durObj.
local cooldownInfo = {
    cooldownID = 1000,
    viewerCategory = "essential",
    spellID = 100,
    overrideSpellID = 100,
    hasAura = false,
    linkedSpellIDs = { 200 },
    wasSetFromAura = false,
    wasSetFromCooldown = true,
    wasSetFromCharges = false,
}

local childActiveCooldownInfo = {
    cooldownID = 1100,
    viewerCategory = "utility",
    spellID = 400,
    overrideSpellID = 400,
    hasAura = false,
    linkedSpellIDs = {},
    selfAura = false,
    childIsActive = true,
    wasSetFromCooldown = true,
}

local linkedAuraState = {
    cooldownID = 2000,
    viewerCategory = "buff",
    spellID = 200,
    overrideSpellID = 200,
    auraInstanceID = 2200,
    auraDurObj = linkedAuraDuration,
    auraDurObjSource = "aura-child",
    selfAura = true,
    mirrorEpoch = 9,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID)
            if cooldownID == 1000 then
                return cooldownInfo
            elseif cooldownID == 1100 then
                return childActiveCooldownInfo
            end
        end,
        GetCooldownInfoForViewer = function(spellID, viewerType)
            if spellID == 100 and viewerType == "essential" then
                return cooldownInfo
            elseif spellID == 400 and viewerType == "utility" then
                return childActiveCooldownInfo
            end
        end,
        GetMirroredStateForViewer = function(spellID, viewerType)
            if spellID == 200 and viewerType == "buff" then
                return linkedAuraState
            end
        end,
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

local state = ns.CDMAuraRuntime.ResolveState({
    spellID = 100,
    entrySpellID = 100,
    entryID = 100,
    entryName = "Linked Aura Test",
    entryKind = "cooldown",
    entryIsAura = false,
    entryType = "spell",
    viewerType = "essential",
    blizzardMirrorCooldownID = 1000,
})

assert(state.isActive == true, "cooldown icons should use active linked aura mirror state")
assert(state.durObj == linkedAuraDuration, "cooldown icons should receive the linked aura DurationObject")
assert(state.auraUnit == "player", "self linked aura should resolve to player")
assert(state.resolvedAuraSpellID == 200, "linked aura spellID should become the active aura spellID")

local queriedExactAura = false

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" and spellID == 400 then
        queriedExactAura = true
        return {
            spellId = 400,
            auraInstanceID = 7400,
            isHelpful = true,
            duration = 8,
        }
    end
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 7400 then
        return exactAuraDuration
    elseif unit == "player" and auraInstanceID == 7401 then
        return exactAuraDuration
    end
end

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 400,
    entrySpellID = 400,
    entryID = 400,
    entryName = "Exact Aura Test",
    entryKind = "cooldown",
    entryIsAura = false,
    entryType = "spell",
    viewerType = "utility",
    blizzardMirrorCooldownID = 1100,
    blizzardMirrorCategory = "utility",
})

assert(queriedExactAura == true, "active child cooldown should allow an exact spellID aura lookup")
assert(state.isActive == true, "active child cooldown should resolve its own live aura")
assert(state.durObj == exactAuraDuration, "active child cooldown should carry the exact aura DurationObject")
assert(state.resolvedAuraSpellID == 400, "exact aura spellID should remain the active aura spellID")

ns.CDMSources.QueryUnitAuraBySpellID = function() return nil end
auraFrame.script(auraFrame, "UNIT_AURA", "player", {
    addedAuras = {
        {
            spellId = 401,
            name = "Exact Aura Test",
            auraInstanceID = 7401,
            isHelpful = true,
            duration = 8,
        },
    },
})

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 400,
    entrySpellID = 400,
    entryID = 400,
    entryName = "Exact Aura Test",
    entryKind = "cooldown",
    entryIsAura = false,
    entryType = "spell",
    viewerType = "utility",
    blizzardMirrorCooldownID = 1100,
    blizzardMirrorCategory = "utility",
})

assert(state.isActive == true,
    "active child cooldown should accept same-name captured player aura when aura spellID differs")
assert(state.auraInstanceID == 7401,
    "same-name captured player aura should provide the live auraInstanceID")
assert(state.resolvedAuraSpellID == 401,
    "same-name captured player aura should publish the actual aura spellID")

local queriedLooseStackName = false
local stackDuration = { token = "stack-duration" }

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" and spellID == 300 then
        return {
            spellId = 300,
            auraInstanceID = 700,
            isHelpful = true,
            duration = 12,
        }
    end
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 700 then
        return stackDuration
    end
end

ns.CDMSources.QueryAuraApplicationDisplayCount = function()
    return nil
end

ns.CDMSources.QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 700 then
        return {
            spellId = 300,
            auraInstanceID = 700,
            isHelpful = true,
            duration = 12,
        }
    end
end

ns.CDMSources.QueryAuraDataBySpellName = function(unit, name, filter)
    if unit == "pet" and name == "Stack Lock Test" and filter == "HELPFUL" then
        queriedLooseStackName = true
        return {
            spellId = 301,
            auraInstanceID = 701,
            isHelpful = true,
            applications = 5,
            duration = 12,
        }
    end
end

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 300,
    entrySpellID = 300,
    entryID = 300,
    entryName = "Stack Lock Test",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "custom",
})

assert(state.isActive == true, "instance-backed aura should be active")
assert(state.auraInstanceID == 700, "test must resolve the player aura instance")
assert(state.durObj == stackDuration, "test must use the resolved aura instance duration")
assert(state.stacks == nil, "resolved aura instances with no applications must not inherit loose name fallback stacks")
assert(queriedLooseStackName == false, "resolved aura instances should not query loose name stack fallbacks")

local cacheStats = ns.CDMSpellData:GetCacheStats()
assert(type(cacheStats.capturedAuraEntries) == "number", "cache stats should include captured aura entry count")
assert(type(cacheStats.capturedAuraUnits) == "number", "cache stats should include captured aura unit count")

print("OK: cdm_spelldata_linked_aura_mirror_test")
