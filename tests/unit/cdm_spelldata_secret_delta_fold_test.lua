-- tests/unit/cdm_spelldata_secret_delta_fold_test.lua
-- Run: lua tests/unit/cdm_spelldata_secret_delta_fold_test.lua
-- 12.1: a UNIT_AURA payload whose delta arrays are secret while isFullUpdate
-- is a readable false must be folded to the full-rescan path (updateInfo=nil)
-- BEFORE NotifyAuraConsumers — consumers run unguarded #/ipairs on the arrays.

local SECRET = setmetatable({}, { __metatable = "secret" })

-- issecretvalue stub: our sentinel is the only secret.
_G.issecretvalue = function(v) return v == SECRET end

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

-- Capture what NotifyAuraConsumers forwards: the icons consumer is
-- ns.CDMIcons.HandleRuntimeRefresh (cdm_spelldata.lua NotifyAuraConsumers).
local forwarded = {}
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
    CDMIcons = {
        HandleRuntimeRefresh = function(event, unit, updateInfo)
            forwarded[#forwarded + 1] = { unit = unit, updateInfo = updateInfo }
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

-- Drive the UNIT_AURA path via the aura capture frame's registered OnEvent
-- handler — the same seam tests/unit/cdm_spelldata_aura_boundary_test.lua
-- uses. HandleUnitAura itself is file-local; this is the reachable seam.
local auraFrame
for _, frame in ipairs(frames) do
    if frame.unitEvents.UNIT_AURA then
        auraFrame = frame
        break
    end
end
assert(auraFrame, "aura capture frame should register UNIT_AURA")

local function dispatchUnitAura(unit, updateInfo)
    auraFrame.script(auraFrame, "UNIT_AURA", unit, updateInfo)
end

-- Shape 1: secret addedAuras, readable isFullUpdate=false.
dispatchUnitAura("player", { isFullUpdate = false, addedAuras = SECRET })
assert(#forwarded == 1, "consumer must still be notified")
assert(forwarded[1].updateInfo == nil,
    "secret addedAuras must fold to the nil/full-rescan payload")

-- Shape 2: secret removedAuraInstanceIDs.
dispatchUnitAura("player", { isFullUpdate = false, removedAuraInstanceIDs = SECRET })
assert(forwarded[2].updateInfo == nil,
    "secret removedAuraInstanceIDs must fold to the nil/full-rescan payload")

-- Shape 3: readable delta passes through untouched.
local readable = { isFullUpdate = false, addedAuras = { { auraInstanceID = 1 } } }
dispatchUnitAura("player", readable)
assert(forwarded[3].updateInfo == readable,
    "readable deltas must pass through unfolded")

print("OK cdm_spelldata_secret_delta_fold_test")
