-- tests/unit/cdm_resolvers_runtime_events_test.lua
-- Run: lua tests/unit/cdm_resolvers_runtime_events_test.lua

local frames = {}

function geterrorhandler()
    return function(err) error(err, 0) end
end

function InCombatLockdown() return false end

function CreateFrame()
    local frame = {
        events = {},
    }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event)
        self.events[event] = true
    end
    function frame:SetScript(scriptName, handler)
        self[scriptName] = handler
    end
    frames[#frames + 1] = frame
    return frame
end

local published = {}
local ns = {
    Helpers = {},
    CDMShared = {},
    CDMSources = {},
    CDMRuntimeQueries = {
        QueryCharges = function() end,
        QueryCooldown = function() end,
        QueryDuration = function() end,
        QueryGCDDuration = function() end,
        QueryChargeDuration = function() end,
        QueryOverrideSpell = function() end,
        QueryDisplayCount = function() end,
        QuerySpellCount = function() end,
    },
    CDMScheduler = {
        Publish = function(...)
            published[#published + 1] = { ... }
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local runtimeFrame
for _, frame in ipairs(frames) do
    if frame.events.SPELL_UPDATE_COOLDOWN then
        runtimeFrame = frame
        break
    end
end
assert(runtimeFrame, "resolver runtime frame should be registered")
assert(runtimeFrame.events.SPELL_UPDATE_CHARGES == true,
    "resolver should keep listening to legacy charge events")
assert(runtimeFrame.events.SPELL_UPDATE_USES == true,
    "resolver should listen to Blizzard CooldownViewer charge-use events")

runtimeFrame.OnEvent(runtimeFrame, "SPELL_UPDATE_USES", 55090, 55091)
local event = assert(published[#published], "SPELL_UPDATE_USES should publish a charge change")
assert(event[1] == "CDM:CHARGES_CHANGED",
    "SPELL_UPDATE_USES should publish through the charge-change bus")
assert(event[2] == 55090 and event[3] == 55091,
    "SPELL_UPDATE_USES should preserve spell and base spell payload")

runtimeFrame.OnEvent(runtimeFrame, "SPELL_UPDATE_CHARGES", 55092)
event = assert(published[#published], "SPELL_UPDATE_CHARGES should still publish a charge change")
assert(event[1] == "CDM:CHARGES_CHANGED" and event[2] == 55092,
    "SPELL_UPDATE_CHARGES compatibility should be preserved")

print("OK: cdm_resolvers_runtime_events_test")
