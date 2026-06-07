-- tests/unit/cdm_blizz_mirror_duplicate_cdid_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_duplicate_cdid_test.lua

local function noop() end

function hooksecurefunc(owner, method, hook)
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 789 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local essentialChild = {
    cooldownID = 70001,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
essentialChild.Cooldown.GetParent = function() return essentialChild end

local buffChild = {
    cooldownID = 70001,
    isActive = false,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
buffChild.Cooldown.GetParent = function() return buffChild end

local movedTrackedBarChild = {
    cooldownID = 80001,
    isActive = false,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
movedTrackedBarChild.Cooldown.GetParent = function() return movedTrackedBarChild end

EssentialCooldownViewer = {
    GetChildren = function()
        return essentialChild
    end,
}
UtilityCooldownViewer = { GetChildren = function() end }
BuffIconCooldownViewer = {
    GetChildren = function()
        return buffChild, movedTrackedBarChild
    end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 or category == 2 then
            return { 70001 }
        end
        if category == 3 then
            return { 80001 }
        end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 70001 then
            return {
                cooldownID = 70001,
                spellID = 100001,
                overrideSpellID = 100001,
                overrideTooltipSpellID = 100002,
                linkedSpellIDs = { 100002 },
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 80001 then
            return {
                cooldownID = 80001,
                spellID = 200001,
                overrideSpellID = 200001,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 200002 },
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)
assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMBlizzMirror.ForceRescan()

local rawLines = assert(
    ns.CDMBlizzMirror.GetRawCooldownViewerDebugLines,
    "raw CooldownViewer dump API should exist")()
local rawText = table.concat(rawLines, "\n")
assert(rawText:find("categorySetEntries=3", 1, true), "raw dump should count category-set entries")
assert(rawText:find("viewerChildren=3", 1, true), "raw dump should count real viewer children")
assert(rawText:find("[CDM raw] api", 1, true)
    and rawText:find("cat=essential", 1, true), "raw dump should include essential category-set data")
assert(rawText:find("[CDM raw] child", 1, true)
    and rawText:find("cat=buff", 1, true), "raw dump should include buff viewer child data")

local output = {}
local originalPrint = print
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    output[#output + 1] = table.concat(parts, " ")
end

ns.CDMBlizzMirror.DumpInfoForSpell()
print = originalPrint

local entryCount = 0
for _, line in ipairs(output) do
    if line:find("cdID=70001", 1, true) then
        entryCount = entryCount + 1
    end
end

assert(entryCount == 2, "duplicate cooldownID children in different categories must both be dumped")

local essentialState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001, "essential"), "essential state missing")
local buffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70001, "buff"), "buff state missing")
local trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(80001, "trackedBar"), "trackedBar state missing")

assert(essentialState.viewerCategory == "essential", "essential state should keep its category")
assert(buffState.viewerCategory == "buff", "buff state should keep its category")
assert(trackedBarState.viewerCategory == "trackedBar", "child in wrong viewer should keep its API category")
assert(essentialState.childIsActive == true, "essential state should read the essential child")
assert(buffState.childIsActive == false, "buff state should read the buff child")
assert(trackedBarState.childIsActive == false, "trackedBar state should read the moved buff child")

print("OK: cdm_blizz_mirror_duplicate_cdid_test")
