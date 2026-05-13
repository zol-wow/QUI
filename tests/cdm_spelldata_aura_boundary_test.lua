-- tests/cdm_spelldata_aura_boundary_test.lua
-- Run: lua tests/cdm_spelldata_aura_boundary_test.lua

local function noop() end
local inCombat = false

function InCombatLockdown() return inCombat end
function GetTime() return 1 end
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
    CDMSources = {},
    CDMBlizzMirror = {
        HandleUnitAuraChanged = function()
            auraRefreshes = auraRefreshes + 1
        end,
    },
    CDMIcons = {
        HandleUnitAuraChanged = function()
            auraRefreshes = auraRefreshes + 1
        end,
    },
}

assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

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

inCombat = true
local ok, err = pcall(function()
    ns.CDMSpellData:Initialize()
end)
inCombat = false
assert(ok, "CDMSpellData initialization should not bootstrap auraInstanceID cache: " .. tostring(err))

print("OK: cdm_spelldata_aura_boundary_test")
