-- tests/unit/cdm_icon_stack_policy_test.lua
-- Run: lua tests/unit/cdm_icon_stack_policy_test.lua
-- luacheck: globals issecretvalue InCombatLockdown wipe C_StringUtil
--
-- The Blizzard-mirror pipeline was removed: the stack policy no longer reads
-- mirror state, captured mirror stack text, or carried cross-category aura
-- stacks (ApplyMirrorStackText / ResolveMirrorStackText* are gone). This test
-- now covers only the LIVE stack/count resolution paths that survive:
--   * live aura applications (resolveAuraActiveState + GetApplications)
--   * multi-charge display-count fallback (ChargeCount)
--   * GetAuraApplicationsFromData display-count sink
--   * ApplyAuraCountText / ShowIconStackText render policy
--   * GetSpellCountForEntry action-button spell count

local secretStackText = { token = "secret-stack-text" }

function issecretvalue(value)
    return value == secretStackText
end

function InCombatLockdown() return false end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

C_StringUtil = {
    TruncateWhenZero = function(value)
        return value == 0 and "" or tostring(value)
    end,
}

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_policies.lua", "cdm_icon_stack_text.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_icon_policies.lua", "cdm_icon_stack_policy.lua")("QUI", ns)

local policyModule = assert(ns.CDMIconStackPolicy, "CDMIconStackPolicy should be exported")

local displayCounts = {}
local spellCounts = {}
local auraDisplayQueries = {}
local auraRuntime = {}
local sources = {}
local debugEvents = {}

local function makeIcon(entry)
    local writes = {}
    local icon = {
        _spellEntry = entry,
        StackText = {
            SetText = function(_, value)
                writes[#writes + 1] = { op = "set", value = value }
            end,
            Show = function()
                writes[#writes + 1] = { op = "show" }
            end,
            Hide = function()
                writes[#writes + 1] = { op = "hide" }
            end,
            SetAlpha = function(_, value)
                writes[#writes + 1] = { op = "alpha", value = value }
            end,
        },
    }
    return icon, writes
end

local policy = policyModule.Create({
    getSink = function() return ns.CDMIconStackText end,
    getSources = function() return sources end,
    getAuraRuntime = function() return auraRuntime end,
    safeBoolean = function(value)
        if value == nil then return nil end
        return value and true or false
    end,
    isAuraEntry = function(entry)
        return entry and entry.kind == "aura"
    end,
    isBuiltinAuraContainerKey = function(containerKey)
        return containerKey == "buff" or containerKey == "trackedBar"
    end,
    resolveAuraActiveState = function(entry)
        if entry and entry.auraInstanceID then
            return true, entry.auraUnit or "player", entry.auraInstanceID
        end
        return false
    end,
    getChargeMetadataDB = function()
        return { [200] = 2 }
    end,
    queryOverrideSpell = function(spellID)
        if spellID == 100 then return 200 end
        return nil
    end,
    queryDisplayCount = function(spellID)
        return displayCounts[spellID]
    end,
    querySpellCount = function(spellID)
        return spellCounts[spellID]
    end,
    getEntryTexture = function(entry)
        return entry and entry.icon
    end,
    getAuraDataInstanceID = function(auraData)
        return auraData and auraData.auraInstanceID
    end,
    getCachedSpellName = function(spellID)
        return spellID == 300 and "Cached Aura" or nil
    end,
    getTrackerSettings = function()
        return {}
    end,
    debugStackText = function(icon, op, value, reason)
        debugEvents[#debugEvents + 1] = { op = op, value = value, reason = reason }
    end,
})

-- Live multi-charge fallback: a cooldown entry whose override spell carries
-- multi-charge metadata resolves to the live display count (ChargeCount source).
local chargeIcon = {
    _runtimeSpellID = 100,
    _spellEntry = { kind = "cooldown", type = "spell", spellID = 100 },
}
displayCounts[200] = 2
local text, source = policy:ResolveIconStackText(chargeIcon)
assert(text == 2, "multi-charge metadata should use spell display count")
assert(source == "ChargeCount", "multi-charge fallback should report ChargeCount")
displayCounts[200] = nil

-- Live aura applications query forwards secret values verbatim.
auraRuntime.GetApplications = function(unit, auraInstanceID)
    if unit == "target" and auraInstanceID == 9001 then
        return true, secretStackText
    end
    if unit == "target" and auraInstanceID == 9003 then
        return true, "2"
    end
    return false
end
local auraIcon = {
    _spellEntry = {
        kind = "aura",
        type = "spell",
        auraInstanceID = 9001,
        auraUnit = "target",
    },
}
text, source = policy:ResolveIconStackText(auraIcon)
assert(rawequal(text, secretStackText), "aura stack text should forward secret values unchanged")
assert(source == "Applications", "aura stack text should report Applications")

-- Live aura applications with a non-secret count.
local liveAura = {
    _spellEntry = {
        kind = "aura",
        type = "spell",
        auraInstanceID = 9003,
        auraUnit = "target",
    },
}
text, source = policy:ResolveIconStackText(liveAura)
assert(text == "2", "aura stack should resolve the live Applications count")
assert(source == "Applications", "live aura fallback should keep the Applications source")

local apps, appSource = policy:GetAuraApplicationsFromData({
    applications = 1,
    auraInstanceID = 77,
}, "player", "aura-data")
assert(apps == nil, "single application data should not use a display-count getter")
assert(appSource == nil, "removed display-count fallback should have no source")
assert(#auraDisplayQueries == 0, "stack policy must not call the aura display-count API")

local renderedIcon, writes = makeIcon({ kind = "aura", viewerType = "buff" })
policy:ApplyAuraCountText(renderedIcon, {
    sinkText = secretStackText,
    value = 9,
    shown = true,
    source = "display-count",
}, false, false)
assert(rawequal(writes[1].value, secretStackText),
    "resolved count rendering should forward secret sink text unchanged")
assert(writes[2].op == "show", "resolved count rendering should show the FontString")
assert(renderedIcon._stackTextSource == "display-count",
    "resolved count rendering should stamp the source")

renderedIcon, writes = makeIcon({ kind = "aura", viewerType = "buff" })
policy:ApplyAuraCountText(renderedIcon, {
    sinkText = "0",
    value = 0,
    shown = true,
    source = "display-count",
}, false, false)
assert(writes[1].op == "set" and writes[1].value == "",
    "aura display-count zero should clear stack text when zero display is not requested")
assert(writes[2].op == "hide",
    "aura display-count zero should hide stack text when zero display is not requested")

renderedIcon, writes = makeIcon({ kind = "aura", viewerType = "buff" })
renderedIcon._rowConfig = { hideStackText = true }
policy:ShowIconStackText(renderedIcon, "8", {}, "test-hide")
assert(writes[1].op == "set" and writes[1].value == "",
    "hidden stack settings should clear stack text")
assert(writes[2].op == "hide", "hidden stack settings should hide stack text")
assert(debugEvents[#debugEvents].reason == "test-hide",
    "hidden stack settings should debug the hide reason")

spellCounts[500] = 3
local count, countSource = policy:GetSpellCountForEntry(500, nil, {})
assert(count == 3, "spell count fallback should return positive action-button counts")
assert(countSource == "spell-cast-count", "spell count fallback should report its source")

print("OK: cdm_icon_stack_policy_test")
