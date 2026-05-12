-- tests/cdm_spelldata_aura_boundary_test.lua
-- Run: lua tests/cdm_spelldata_aura_boundary_test.lua

local function noop() end

function InCombatLockdown() return false end
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
        error("PLAYER_REGEN_DISABLED should not force an aura rescan")
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
assert(auraFrame.events.ENCOUNTER_START == true, "aura capture should refresh on encounter start")
assert(auraFrame.events.CHALLENGE_MODE_START == true, "aura capture should refresh on challenge start")
assert(auraFrame.events.PVP_MATCH_ACTIVE == true, "aura capture should refresh on active PvP match")
assert(auraFrame.events.PLAYER_REGEN_DISABLED ~= true, "combat start should not be treated as an aura-instance rerandomization boundary")

local ok, err = pcall(function()
    auraFrame.script(auraFrame, "PLAYER_REGEN_DISABLED")
end)

assert(ok, "PLAYER_REGEN_DISABLED should not rescan captured auras: " .. tostring(err))
assert(auraRefreshes == 0, "PLAYER_REGEN_DISABLED should not notify aura consumers by itself")

print("OK: cdm_spelldata_aura_boundary_test")
