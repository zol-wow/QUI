-- tests/unit/cdm_spelldata_aura_boundary_test.lua
-- Run: lua tests/unit/cdm_spelldata_aura_boundary_test.lua

local function noop() end
local inCombat = false
local now = 1

function InCombatLockdown() return inCombat end
function GetTime() return now end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local frames = {}
function CreateFrame()
    local frame = {
        events = {},
        unitEvents = {},
        script = nil,
    }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event, ...)
        self.unitEvents[event] = { ... }
    end
    function frame:UnregisterEvent(event)
        self.events[event] = nil
    end
    function frame:UnregisterAllEvents()
        self.events = {}
        self.unitEvents = {}
    end
    function frame:SetScript(script, handler)
        if script == "OnEvent" then
            self.script = handler
        end
    end
    frames[#frames + 1] = frame
    return frame
end

C_Timer = { After = function(_, callback) callback() end }
AuraUtil = {
    ForEachAura = function()
        error("boundary events should not force an auraInstanceID rescan")
    end,
}

local auraRefreshes = 0
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
        QueryUnitAuraBySpellID = function(unit, spellID)
            if unit == "player" and spellID == 8001 then
                return {
                    auraInstanceID = 9001,
                    spellId = spellID,
                    duration = 10,
                    expirationTime = 11,
                    isHelpful = true,
                    sourceUnit = "player",
                }
            end
        end,
    },
    CDMIndex = {
        Version = function() return 1 end,
        Get = function(spellID)
            if spellID == 7001 then
                return { cooldownID = 9002 }
            end
        end,
    },
    CDMCatalog = {
        GetCooldownInfo = function(cooldownID)
            if cooldownID == 9002 then
                return { linkedSpellID = 8001 }
            end
        end,
    },
    CDMIcons = {
        HandleRuntimeRefresh = function()
            auraRefreshes = auraRefreshes + 1
        end,
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
assert(auraFrame.events.PLAYER_ENTERING_WORLD ~= true, "zone/login bootstrap should not force an auraInstanceID rescan")
assert(auraFrame.events.PLAYER_REGEN_ENABLED ~= true, "combat exit should not force an auraInstanceID rescan")
assert(auraFrame.events.ENCOUNTER_START ~= true, "encounter start should not force an auraInstanceID rescan")
assert(auraFrame.events.CHALLENGE_MODE_START ~= true, "challenge start should not force an auraInstanceID rescan")
assert(auraFrame.events.PVP_MATCH_ACTIVE ~= true, "active PvP match should not force an auraInstanceID rescan")
assert(auraFrame.events.PLAYER_REGEN_DISABLED ~= true, "combat start should not be treated as an aura-instance rerandomization boundary")

local boundaryEvents = {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_START",
    "CHALLENGE_MODE_START",
    "PVP_MATCH_ACTIVE",
    "PLAYER_ENTERING_WORLD",
}

for _, event in ipairs(boundaryEvents) do
    local ok, err = pcall(function()
        auraFrame.script(auraFrame, event)
    end)
    assert(ok, event .. " should not rescan captured auraInstanceIDs: " .. tostring(err))
end

assert(auraRefreshes == 0, "PLAYER_REGEN_DISABLED should not notify aura consumers by itself")

auraFrame.script(auraFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 7001)
auraFrame.script(auraFrame, "UNIT_AURA", "player", {
    addedAuras = {
        {
            auraInstanceID = 9001,
            spellId = 8001,
            name = "Applied Aura Name",
            isHelpful = true,
        },
    },
})

local captured = ns.CDMSpellData.GetCapturedAuraForLookup({ 7001 }, nil, { "player" }, false)
assert(captured and captured.auraInstanceID == 9001,
    "clean added aura payloads should also be keyed by recent cast spellID")

local resolvedAura = ns.CDMAuraRuntime.ResolveState({
    spellID = 7001,
    entrySpellID = 7001,
    entryID = 7001,
    entryKind = "cooldown",
    entryType = "spell",
    viewerType = "custom",
})
assert(resolvedAura.isActive == true and resolvedAura.resolvedAuraSpellID == 8001,
    "cooldown aura resolution should probe linked spell IDs for custom entries")

local directEntryAura = ns.CDMAuraRuntime.ResolveState({
    spellID = 7002,
    entrySpellID = 7002,
    entryID = 7002,
    entryLinkedSpellID = 8001,
    entryKind = "cooldown",
    entryType = "spell",
    viewerType = "custom",
})
assert(directEntryAura.isActive == true and directEntryAura.resolvedAuraSpellID == 8001,
    "custom entry linkedSpellID should resolve without a catalog mapping")

inCombat = true
local ok, err = pcall(function()
    ns.CDMSpellData:Initialize()
end)
inCombat = false
assert(ok, "CDMSpellData initialization should not bootstrap auraInstanceID cache: " .. tostring(err))

print("OK: cdm_spelldata_aura_boundary_test")
