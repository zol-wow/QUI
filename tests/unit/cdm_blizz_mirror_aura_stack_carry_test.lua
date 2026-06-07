-- tests/unit/cdm_blizz_mirror_aura_stack_carry_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_aura_stack_carry_test.lua
-- luacheck: globals hooksecurefunc InCombatLockdown GetTime wipe CreateFrame
-- luacheck: globals EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer BuffBarCooldownViewer C_CooldownViewer

local function noop() end

function hooksecurefunc(owner, method, hook)
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 439 end
function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local function MakeTextOwner()
    local owner = { _shown = true }
    function owner:GetText() return self._text end
    function owner:SetText(text) self._text = text end
    function owner:SetFormattedText(formatText, ...)
        self._text = string.format(formatText, ...)
    end
    function owner:IsShown() return self._shown end
    function owner:Show() self._shown = true end
    function owner:Hide() self._shown = false end
    return owner
end

local essentialChild = {
    cooldownID = 51696,
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

local buffApplications = MakeTextOwner()
local buffApplicationsFrame = {
    Applications = buffApplications,
}
local buffChild = {
    cooldownID = 157723,
    isActive = true,
    auraInstanceID = 119,
    auraDataUnit = "target",
    auraData = {
        auraInstanceID = 119,
        spellId = 434765,
        applications = 7,
        sourceUnit = "player",
    },
    Applications = buffApplicationsFrame,
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

EssentialCooldownViewer = {
    GetChildren = function() return essentialChild end,
}
UtilityCooldownViewer = { GetChildren = function() end }
BuffIconCooldownViewer = {
    GetChildren = function() return buffChild end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then return { 51696 } end
        if category == 2 then return { 157723 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 51696 then
            return {
                cooldownID = 51696,
                spellID = 439843,
                overrideSpellID = 439843,
                linkedSpellIDs = { 434765 },
                selfAura = false,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 157723 then
            return {
                cooldownID = 157723,
                spellID = 439843,
                overrideSpellID = 439843,
                overrideTooltipSpellID = 434765,
                linkedSpellIDs = { 434765 },
                selfAura = false,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local auraDurObj = { token = "reapers-mark-aura" }
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)
ns.CDMSources = {
    QueryAuraFilteredOutByInstanceID = function(unit, auraInstanceID)
        return unit == "target" and auraInstanceID == 119 and false or nil
    end,
    QueryAuraDuration = function(unit, auraInstanceID)
        if unit == "target" and auraInstanceID == 119 then
            return auraDurObj
        end
    end,
    QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
        if unit == "target" and auraInstanceID == 119 then
            return buffChild.auraData
        end
    end,
}
assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMBlizzMirror.ForceRescan()

essentialChild.Cooldown:SetCooldownFromDurationObject({ token = "essential-aura-refresh" }, false)
buffApplications:SetText("7")

local buffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(157723, "buff"),
    "buff mirror state missing after Applications write")
assert(buffState.stackText == "7",
    "buff mirror should keep its own Applications stack text")
assert(buffState.stackTextShown == true,
    "buff mirror should mark its own Applications stack visible")

buffApplications:SetFormattedText("%d", 9)
buffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(157723, "buff"),
    "buff mirror state missing after formatted Applications write")
assert(buffState.stackText == "9",
    "buff mirror should read the formatted Applications display text")
assert(buffState.stackTextShown == true,
    "buff mirror should mark formatted Applications stacks visible")

buffApplications:SetText("")
buffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(157723, "buff"),
    "buff mirror state missing after transient empty Applications write")
assert(buffState.stackText == "",
    "buff mirror should forward Applications text writes without readjudicating the value")
assert(buffState.stackTextShown == true,
    "buff mirror should treat Applications text writes as shown until the mirror hides them")

buffApplications:SetText("7")
buffApplications:Hide()
buffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(157723, "buff"),
    "buff mirror state missing after Applications hide")
assert(buffState.stackTextShown == false,
    "buff mirror should hide Applications stacks when the mirror text owner hides")

buffApplications:Show()
buffApplications:SetText("7")
buffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(157723, "buff"),
    "buff mirror state missing after Applications re-show")
assert(buffState.stackText == "7",
    "buff mirror should accept the re-shown Applications value")
assert(buffState.stackTextShown == true,
    "buff mirror should mark re-shown Applications stacks visible")

local essentialState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(51696, "essential"),
    "essential mirror state missing after related aura capture")
assert(essentialState.auraStackText == "7",
    "essential mirror should pick up the related buff Applications stack after the source writes it")

local rawStates
for _, probe in ipairs(ns._memprobes or {}) do
    if probe.name == "CDM_blizzMirror_state" then
        rawStates = probe.tbl
        break
    end
end
assert(rawStates, "raw mirror state probe missing")
local rawBuffState = assert(rawStates["buff:157723"], "raw buff state missing")

rawBuffState.stackText = nil
rawBuffState.stackTextSource = nil
rawBuffState.stackTextShown = nil

essentialChild.Cooldown:SetCooldownFromDurationObject({ token = "essential-aura-refresh-2" }, false)

essentialState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(51696, "essential"),
    "essential mirror state missing after unknown related stack read")
assert(essentialState.auraStackText == "7",
    "a transient nil Applications read must not clear the carried aura stack")
assert(essentialState.auraStackTextSource == "Applications",
    "preserved carried aura stack should keep its source")

rawBuffState.stackTextShown = false

essentialChild.Cooldown:SetCooldownFromDurationObject({ token = "essential-aura-refresh-3" }, false)

essentialState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(51696, "essential"),
    "essential mirror state missing after explicit related stack hide")
assert(essentialState.auraStackText == nil,
    "an explicitly hidden related Applications stack should clear the carried aura stack")

print("OK: cdm_blizz_mirror_aura_stack_carry_test")
