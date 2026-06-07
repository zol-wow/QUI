-- tests/unit/cdm_icon_stack_policy_test.lua
-- Run: lua tests/unit/cdm_icon_stack_policy_test.lua
-- luacheck: globals issecretvalue InCombatLockdown wipe C_StringUtil

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
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_stack_text.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_stack_policy.lua")("QUI", ns)

local policyModule = assert(ns.CDMIconStackPolicy, "CDMIconStackPolicy should be exported")

local mirrorStates = {}
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
    getMirror = function()
        return {
            GetStateByCooldownID = function(cooldownID, category)
                return mirrorStates[tostring(cooldownID) .. ":" .. tostring(category)]
            end,
        }
    end,
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
    resolveMirrorIdentityState = function(entry)
        if entry and entry.identityCooldownID then
            return {
                cooldownID = entry.identityCooldownID,
                category = entry.identityCategory,
                state = entry.identityState,
            }
        end
        return nil
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

mirrorStates["42:essential"] = {
    stackText = "6",
    stackTextSource = "Applications",
    stackTextShown = true,
}
local icon = {
    _blizzMirrorCooldownID = 42,
    _blizzMirrorCategory = "essential",
    _spellEntry = { kind = "cooldown", type = "spell", spellID = 100 },
}
displayCounts[200] = "9"
local text, source, mirrorBacked, mirrorHidden = policy:ResolveIconStackText(icon)
assert(text == nil, "cooldown mirror Applications text should not bleed into charge count")
assert(source == nil, "suppressed cooldown Applications source should not become a count source")
assert(mirrorBacked == true, "mirror stack resolution should mark mirror authority")
assert(mirrorHidden == true, "cooldown mirror state should remain authoritative when count text is absent")
displayCounts[200] = nil

mirrorStates["43:essential"] = {
    stackTextShown = false,
    stackTextSource = "ChargeCount",
}
icon._blizzMirrorCooldownID = 43
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(text == nil, "mirror-hidden stack text should resolve empty")
assert(source == "ChargeCount", "mirror-hidden stack source should be preserved")
assert(mirrorBacked == true, "mirror-hidden stack should remain authoritative")

mirrorStates["44:essential"] = {
    stackText = "2",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    cooldownChargesShown = false,
    chargeCountFrameShown = false,
}
icon._blizzMirrorCooldownID = 44
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(text == nil, "mirror-hidden ChargeCount visibility should suppress stale stack text")
assert(source == "ChargeCount", "suppressed ChargeCount source should be preserved")
assert(mirrorBacked == true, "suppressed ChargeCount stack should remain mirror authoritative")

mirrorStates["45:essential"] = {
    stackText = "8",
    stackTextSource = "ChargeCount",
    stackTextShown = false,
    cooldownChargesShown = false,
    chargeCountFrameShown = false,
}
icon._blizzMirrorCooldownID = 45
icon._runtimeSpellID = 100
displayCounts[200] = "8"
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(text == nil, "mirror-hidden non-charge cooldowns should not re-query display count")
assert(source == "ChargeCount", "mirror-hidden non-charge cooldowns should preserve mirror source")
assert(mirrorBacked == true, "mirror-hidden non-charge cooldowns should remain mirror authoritative")

local chargedIcon = {
    _blizzMirrorCooldownID = 45,
    _blizzMirrorCategory = "essential",
    _runtimeSpellID = 100,
    _spellEntry = { kind = "cooldown", type = "spell", spellID = 100, hasCharges = true },
}
text, source, mirrorBacked = policy:ResolveIconStackText(chargedIcon)
assert(text == nil, "charged spells should not replace hidden mirror ChargeCount with display count")
assert(source == "ChargeCount", "charged hidden ChargeCount source should be preserved")
assert(mirrorBacked == true, "charged hidden ChargeCount should remain mirror authoritative")
displayCounts[200] = nil

mirrorStates["46:essential"] = {
    stackText = "8",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    cooldownChargesShown = true,
    chargeCountFrameShown = false,
    wasSetFromCooldown = true,
    wasSetFromCharges = false,
}
icon._blizzMirrorCooldownID = 46
icon._runtimeSpellID = 55090
icon._spellEntry = { kind = "cooldown", type = "spell", spellID = 55090 }
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(text == "8", "non-charge cooldown text owner should survive hidden ChargeCount parent state")
assert(source == "ChargeCount", "mirrored child count text should keep its source")
assert(mirrorBacked == true, "mirrored child count text should remain mirror authoritative")
assert(icon.cooldownChargesCount == nil,
    "icon should not invent cooldownChargesCount when the mirror only has stack text")
assert(icon.cooldownChargesShown == true,
    "icon should mirror cooldownChargesShown from the mirror state")
assert(icon.stackText == "8", "icon should mirror stack text from the mirror state")
assert(icon.stackTextShown == true, "icon should mirror stack text shown-state from the mirror state")

mirrorStates["46:essential"].cooldownChargesShown = false
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(text == nil, "cooldownChargesShown false should suppress cooldown count text")
assert(source == "ChargeCount", "suppressed cooldown count text should keep its source")
assert(icon.cooldownChargesShown == false,
    "icon should update mirrored cooldownChargesShown when the mirror hides the count")
assert(icon.stackText == "8", "icon should preserve hidden mirror stack text for diagnostics")
assert(icon.stackTextShown == true,
    "icon stackTextShown should reflect the mirror state even when cooldownChargesShown hides it")

mirrorStates["47:essential"] = {
    cooldownChargesCount = 0,
    cooldownChargesShown = false,
    chargeTextOwnerShown = true,
    stackText = 0,
    stackTextShown = true,
}
icon._blizzMirrorCooldownID = 47
text, source, mirrorBacked, mirrorHidden = policy:ResolveIconStackText(icon)
assert(text == nil, "explicit hidden cooldown count should suppress a cached zero")
assert(source == "ChargeCount", "explicit hidden cooldown count should remain a ChargeCount decision")
assert(mirrorBacked == true, "explicit hidden cooldown count should remain mirror authoritative")
assert(mirrorHidden == true, "explicit hidden cooldown count should be reported hidden")

mirrorStates["48:essential"] = {
    cooldownChargesCount = "9",
    stackTextSource = "ChargeCount",
}
icon._blizzMirrorCooldownID = 48
text, source, mirrorBacked, mirrorHidden = policy:ResolveIconStackText(icon)
assert(text == nil, "cooldown count without explicit shown state should stay hidden")
assert(source == "ChargeCount", "hidden cooldown count without explicit shown state should keep its source")
assert(mirrorBacked == true, "hidden cooldown count without explicit shown state should remain mirror authoritative")
assert(mirrorHidden == true, "cooldown count without explicit shown state should report hidden")

-- Secret cooldown ChargeCount visibility must not be decoded or overridden by a
-- clean parent frame state. The renderer forwards the secret boolean to the
-- FontString alpha sink, which evaluates it through C_CurveUtil.
mirrorStates["56:essential"] = {
    stackText = secretStackText,
    stackTextSource = "ChargeCount",
    stackTextShown = secretStackText,
    cooldownChargesShown = secretStackText,
    chargeCountFrameShown = false,
    chargeTextOwnerShown = false,
}
icon._blizzMirrorCooldownID = 56
icon._runtimeSpellID = 439843
icon._spellEntry = { kind = "cooldown", type = "spell", spellID = 439843 }
text, source, mirrorBacked, mirrorHidden = policy:ResolveIconStackText(icon)
assert(rawequal(text, secretStackText),
    "secret cooldown ChargeCount text should be forwarded for alpha-gated display")
assert(source == "ChargeCount",
    "secret cooldown ChargeCount should preserve its source")
assert(mirrorBacked == true,
    "secret cooldown ChargeCount should stay mirror authoritative")
assert(mirrorHidden ~= true,
    "secret cooldown ChargeCount should not be reported mirror-hidden")

mirrorStates["58:essential"] = {
    stackText = secretStackText,
    stackTextSource = "ChargeCount",
    stackTextShown = secretStackText,
    cooldownChargesShown = secretStackText,
    chargeCountFrameShown = false,
    chargeTextOwnerShown = true,
}
icon._blizzMirrorCooldownID = 58
text, source, mirrorBacked, mirrorHidden = policy:ResolveIconStackText(icon)
assert(rawequal(text, secretStackText),
    "shown count text owner should preserve secret cooldown ChargeCount text")
assert(source == "ChargeCount",
    "shown count text owner should preserve its ChargeCount source")
assert(mirrorBacked == true,
    "shown count text owner should stay mirror authoritative")
assert(mirrorHidden ~= true,
    "shown count text owner should not be reported mirror-hidden")

-- A definitive non-secret cooldownChargesShown=true still wins over a frame-hidden
-- read (mirrors state 46): an explicit data-driven count can show even when the
-- parent ChargeCount frame state reads false, so the override is secret-only.
mirrorStates["57:essential"] = {
    stackText = "3",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    cooldownChargesShown = true,
    chargeCountFrameShown = false,
}
icon._blizzMirrorCooldownID = 57
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(text == "3",
    "an explicit non-secret cooldownChargesShown=true should still render despite frame-hidden")

icon._blizzMirrorCooldownID = nil
icon._runtimeSpellID = 100
displayCounts[200] = 2
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(text == 2, "multi-charge metadata should use spell display count")
assert(source == "ChargeCount", "multi-charge fallback should report ChargeCount")
assert(mirrorBacked == nil, "non-mirror fallback should not report mirror authority")

auraRuntime.GetApplications = function(unit, auraInstanceID)
    if unit == "target" and auraInstanceID == 9001 then
        return true, secretStackText
    end
    if unit == "target" and auraInstanceID == 9002 then
        return true, "1"
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

-- Mirror-primary for a mirror-backed aura. Reaper's Mark's target debuff genuinely
-- stacks, but its C_UnitAuras data is restricted in combat, so the live applications
-- query (GetApplications) returns not-resolved. The Blizzard CDM mirror child still
-- captured the rendered stack as a secret value; the aura icon must surface that
-- captured stackText (primary) instead of falling through to the empty live query.
-- instID 9002 also has a live fallback in this test; the only way to pass is
-- for the mirror state to stay authoritative. The secret value forwards verbatim.
mirrorStates["434765:buff"] = {
    stackText = secretStackText,
    stackTextSource = "Applications",
    stackTextShown = true,
}
local mirrorBackedAura = {
    _spellEntry = {
        kind = "aura",
        type = "spell",
        auraInstanceID = 9002,
        auraUnit = "target",
        identityCooldownID = 434765,
        identityCategory = "buff",
    },
}
text, source, mirrorBacked = policy:ResolveIconStackText(mirrorBackedAura)
assert(rawequal(text, secretStackText),
    "mirror-backed aura should use the captured mirror stackText when the live query is restricted")
assert(source == "Applications", "mirror-backed aura stack should report Applications")
assert(mirrorBacked == true, "mirror-backed aura stack should report mirror authority")

mirrorStates["434766:buff"] = {
    auraInstanceID = 9003,
    auraUnit = "target",
}
local unknownMirrorBackedAura = {
    _spellEntry = {
        kind = "aura",
        type = "spell",
        auraInstanceID = 9003,
        auraUnit = "target",
        identityCooldownID = 434766,
        identityCategory = "buff",
    },
}
text, source, mirrorBacked = policy:ResolveIconStackText(unknownMirrorBackedAura)
assert(text == "2",
    "mirror-backed aura with no confirmed stack text should fall back to live Applications")
assert(source == "Applications",
    "unknown mirror fallback should keep the Applications source")
assert(mirrorBacked ~= true,
    "unknown mirror fallback should not report mirror authority")

mirrorStates["434767:buff"] = {
    stackText = "",
    stackTextSource = "Applications",
    stackTextShown = true,
}
local emptyMirrorBackedAura = {
    _spellEntry = {
        kind = "aura",
        type = "spell",
        auraInstanceID = 9003,
        auraUnit = "target",
        identityCooldownID = 434767,
        identityCategory = "buff",
    },
}
text, source, mirrorBacked = policy:ResolveIconStackText(emptyMirrorBackedAura)
assert(text == nil,
    "confirmed empty mirror Applications text should not fall back to live Applications")
assert(source == "Applications",
    "confirmed empty mirror Applications should keep the mirror source")
assert(mirrorBacked == true,
    "confirmed empty mirror Applications should report mirror authority")

sources.QueryAuraApplicationDisplayCount = function(unit, auraInstanceID, minApplications)
    auraDisplayQueries[#auraDisplayQueries + 1] = {
        unit = unit,
        auraInstanceID = auraInstanceID,
        minApplications = minApplications,
    }
    return "4"
end
local apps, appSource = policy:GetAuraApplicationsFromData({
    applications = 1,
    auraInstanceID = 77,
}, "player", "aura-data")
assert(apps == "4", "aura data fallback should ask the display-count source")
assert(appSource == "display-count", "display-count fallback should identify its source")
assert(auraDisplayQueries[1].minApplications == 1,
    "display-count should request stacks from 1 (abilities that count from a single application)")

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

renderedIcon, writes = makeIcon({ kind = "aura", viewerType = "buff" })
local applied = policy:ApplyMirrorStackText(renderedIcon, {
    stackText = "5",
    stackTextShown = true,
    stackTextSource = "Applications",
    stackTextEpoch = 12,
}, false)
assert(applied == true, "mirror stack payload should apply when shown")
assert(writes[1].op == "set" and writes[1].value == "5",
    "mirror stack payload should write its stack text")
assert(renderedIcon._lastMirrorStackTextEpoch == 12,
    "mirror stack payload should stamp the mirror text epoch")

renderedIcon, writes = makeIcon({ kind = "cooldown", viewerType = "essential" })
applied = policy:ApplyMirrorStackText(renderedIcon, {
    cooldownChargesCount = "8",
    cooldownChargesShown = nil,
    chargeCountFrameShown = false,
    chargeTextOwnerShown = true,
    stackTextShown = false,
    stackTextSource = "ChargeCount",
    stackTextEpoch = 13,
    wasSetFromCooldown = true,
    wasSetFromCharges = false,
}, false)
assert(applied == true, "cooldown count text owner should apply when the child text owner is visible")
assert(writes[1].op == "set" and writes[1].value == "8",
    "cooldown count text owner should write when the child text owner is visible")

renderedIcon, writes = makeIcon({ kind = "cooldown", viewerType = "essential" })
applied = policy:ApplyMirrorStackText(renderedIcon, {
    cooldownChargesCount = "8",
    cooldownChargesShown = true,
    chargeCountFrameShown = false,
    chargeTextOwnerShown = false,
    stackTextShown = false,
    stackTextSource = "ChargeCount",
    stackTextEpoch = 14,
    wasSetFromCooldown = true,
    wasSetFromCharges = false,
}, false)
assert(applied == true, "explicit visible mirror cooldown count payload should apply")
assert(writes[1].op == "set" and writes[1].value == "8",
    "explicit visible mirror cooldown count payload should write the count text")
assert(writes[2].op == "show",
    "explicit visible mirror cooldown count payload should show the FontString")
assert(renderedIcon._lastMirrorStackTextEpoch == 14,
    "explicit visible mirror cooldown count payload should stamp the mirror text epoch")

spellCounts[500] = 3
local count, countSource = policy:GetSpellCountForEntry(500, nil, {})
assert(count == 3, "spell count fallback should return positive action-button counts")
assert(countSource == "spell-cast-count", "spell count fallback should report its source")

-- Cross-category aura on a non-aura (cooldown) entry. The host (essential)
-- mirror state carries the SOURCE (buff) child's applications text on
-- auraStackText (CaptureAuraInstanceFromChildFrame). The icon must render that
-- carried text -- NOT the host child's own (chargeless) ChargeCount text,
-- which is the wrong source and paints blank in combat.
mirrorStates["51:essential"] = {
    stackText = "2",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    auraInstanceID = 5151,
    auraStackText = "7",
    auraStackTextSource = "Applications",
    auraStackTextShown = true,
}
icon._blizzMirrorCooldownID = 51
icon._blizzMirrorCategory = "essential"
icon._runtimeSpellID = 439843
icon._spellEntry = { kind = "cooldown", type = "spell", spellID = 439843 }
icon._resolvedCooldownMode = "aura"
text, source = policy:ResolveIconStackText(icon)
assert(text == "7",
    "cross-category aura should render the carried aura stack text, not ChargeCount")
assert(source == "Applications",
    "carried aura stack text should report the Applications source")

mirrorStates["55:essential"] = {
    stackText = "2",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    auraInstanceID = 5152,
    auraStackText = secretStackText,
    auraStackTextSource = "Applications",
    auraStackTextShown = true,
}
icon._blizzMirrorCooldownID = 55
icon._auraInstanceID = 5152
icon._auraUnit = "target"
text, source, mirrorBacked = policy:ResolveIconStackText(icon)
assert(rawequal(text, secretStackText),
    "secret carried aura stack text should stay mirror-authoritative")
assert(source == "Applications",
    "secret carried aura stack text should keep the Applications source")
assert(mirrorBacked == true,
    "secret carried aura stack text should report mirror authority")

-- Leak guard: same carried aura stack, but the icon is NOT rendering the aura
-- (on cooldown, or the viewer is configured to skip the aura phase). The
-- carried count must stay off and fall back to the host ChargeCount path.
icon._blizzMirrorCooldownID = 51
icon._resolvedCooldownMode = "cooldown"
local _, cooldownModeSource = policy:ResolveIconStackText(icon)
assert(cooldownModeSource == "ChargeCount",
    "carried aura stack must not show when the icon is not rendering the aura phase")
icon._resolvedCooldownMode = "aura"

local crossCatRender, crossCatWrites = makeIcon({ kind = "cooldown", viewerType = "essential" })
crossCatRender._resolvedCooldownMode = "aura"
applied = policy:ApplyMirrorStackText(crossCatRender, {
    stackText = "2",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    auraInstanceID = 5151,
    auraStackText = "7",
    auraStackTextSource = "Applications",
    auraStackTextShown = true,
    stackTextEpoch = 21,
}, false)
assert(applied == true,
    "cross-category aura stack should apply through the mirror stack path")
assert(crossCatWrites[1].op == "set" and crossCatWrites[1].value == "7",
    "cross-category aura should write the carried aura stack text, not the ChargeCount value")
assert(crossCatWrites[3].op == "alpha" and crossCatWrites[3].value == 1,
    "cross-category aura stack should use the carried aura visibility gate")

local hiddenHostChargeRender, hiddenHostChargeWrites = makeIcon({ kind = "cooldown", viewerType = "essential" })
hiddenHostChargeRender._resolvedCooldownMode = "aura"
applied = policy:ApplyMirrorStackText(hiddenHostChargeRender, {
    stackText = secretStackText,
    stackTextSource = "ChargeCount",
    stackTextShown = secretStackText,
    cooldownChargesShown = secretStackText,
    chargeCountFrameShown = false,
    chargeTextOwnerShown = true,
    auraInstanceID = 5151,
    auraStackText = "8",
    auraStackTextSource = "Applications",
    auraStackTextShown = true,
    stackTextEpoch = 23,
}, false)
assert(applied == true,
    "carried aura stack should apply even when the host ChargeCount frame is hidden")
assert(hiddenHostChargeWrites[1].op == "set" and hiddenHostChargeWrites[1].value == "8",
    "hidden host ChargeCount should not replace carried aura stack text")
assert(hiddenHostChargeWrites[3].op == "alpha" and hiddenHostChargeWrites[3].value == 1,
    "hidden host ChargeCount should not alpha-hide the carried aura stack text")

local emptyMirrorRender, emptyMirrorWrites = makeIcon({ kind = "aura", viewerType = "buff" })
applied = policy:ApplyMirrorStackText(emptyMirrorRender, {
    stackText = "",
    stackTextSource = "Applications",
    stackTextShown = true,
    stackTextEpoch = 22,
}, false)
assert(applied == true,
    "mirror-backed aura stack text writes should be authoritative even when the Lua value is empty")
assert(emptyMirrorWrites[1].op == "set" and emptyMirrorWrites[1].value == "",
    "mirror-backed aura stack text should be forwarded verbatim to SetText")
assert(emptyMirrorWrites[2].op == "show",
    "mirror-backed aura stack text visibility should follow mirror shown-state")

local buffAuraRender, buffAuraWrites = makeIcon({ kind = "aura", viewerType = "buff" })
applied = policy:ApplyMirrorStackText(buffAuraRender, {
    stackText = "8",
    stackTextSource = "Applications",
    stackTextShown = true,
    cooldownChargesShown = secretStackText,
    chargeCountFrameShown = false,
    chargeTextOwnerShown = true,
    stackTextEpoch = 24,
}, false)
assert(applied == true,
    "buff aura stack should apply from its own Applications mirror text")
assert(buffAuraWrites[1].op == "set" and buffAuraWrites[1].value == "8",
    "buff aura stack should write the Applications count")
assert(buffAuraWrites[3].op == "alpha" and buffAuraWrites[3].value == 1,
    "buff aura Applications stack should not inherit the hidden ChargeCount gate")

-- An explicitly hidden carried aura stack falls back to the host ChargeCount
-- resolution (the source child hid its count, so show nothing).
mirrorStates["52:essential"] = {
    stackText = "2",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    auraInstanceID = 5151,
    auraStackText = "7",
    auraStackTextSource = "Applications",
    auraStackTextShown = false,
}
icon._blizzMirrorCooldownID = 52
local _, hiddenSource = policy:ResolveIconStackText(icon)
assert(hiddenSource == "ChargeCount",
    "an explicitly hidden carried aura stack should fall back to the host ChargeCount path")

-- A cooldown entry with no carried aura stack (plain cooldown) is untouched:
-- the auraStackText branch only fires when the source child supplied one.
mirrorStates["53:essential"] = {
    stackText = "2",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
}
icon._blizzMirrorCooldownID = 53
local _, plainCdSource = policy:ResolveIconStackText(icon)
assert(plainCdSource == "ChargeCount",
    "a cooldown with no carried aura stack should still resolve via the mirror ChargeCount path")

-- Flicker guard: the borrowed aura stack is captured from the source child via
-- two paths -- the raw SetText(number) argument and the rendered owner:GetText()
-- string -- which alternate per UNIT_AURA. Carrying the value verbatim made the
-- essential icon's count flip secret-number <-> secret-string every refresh
-- (visible flicker). The resolver must coerce a numeric carried value to the
-- SAME rendered string the buff icon shows (C_StringUtil.TruncateWhenZero), so
-- consecutive frames write a stable string regardless of which capture last won.
mirrorStates["54:essential"] = {
    stackText = "2",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
    auraInstanceID = 5151,
    auraStackText = 7, -- numeric capture (raw SetText arg); the other path is "7"
    auraStackTextSource = "Applications",
    auraStackTextShown = true,
}
icon._blizzMirrorCooldownID = 54
local numericText, numericSource = policy:ResolveIconStackText(icon)
assert(type(numericText) == "string",
    "a numeric carried aura stack must be coerced to a string so it can't oscillate with the string-capture frame")
assert(numericText == "7",
    "the coerced numeric carried aura stack must render the same glyph the buff icon shows")
assert(numericSource == "Applications",
    "coercing the carried aura stack type must not change its Applications source")

print("OK: cdm_icon_stack_policy_test")
