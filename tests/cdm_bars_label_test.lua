-- tests/cdm_bars_label_test.lua
-- Run: lua tests/cdm_bars_label_test.lua

local secretValueMT = {
    __eq = function()
        error("secret value compared")
    end,
    __tostring = function()
        error("secret value stringified")
    end,
}

local function NewSecretValue(label)
    return setmetatable({ label = label }, secretValueMT)
end

local wrappedSecretStacks = { token = "wrapped-secret-stacks" }

function InCombatLockdown() return false end
function CreateFrame()
    local frame = {}
    function frame:SetScript() end
    function frame:CreateAnimationGroup()
        local group = {}
        function group:CreateAnimation()
            return { SetDuration = function() end }
        end
        function group:SetLooping() end
        function group:SetScript() end
        return group
    end
    return frame
end

C_StringUtil = {
    WrapString = function(value, prefix, suffix)
        if getmetatable(value) == secretValueMT then
            if value.label == "empty" then
                return ""
            end
            return wrappedSecretStacks
        end
        if value == nil or value == "" then
            return ""
        end
        return prefix .. tostring(value) .. suffix
    end,
    TruncateWhenZero = function(value)
        if value == 0 then return nil end
        return value
    end,
}

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function(value)
            return getmetatable(value) == secretValueMT
        end,
    },
}

assert(loadfile("modules/cdm/cdm_bars.lua"))("QUI", ns)

local bars = assert(ns.CDMBars, "CDMBars table was not exported")
assert(bars.ApplyNameTextWithStacks == nil, "legacy bar stack label helper should not be exported")
local applyNameText = assert(bars.ApplyNameTextWithCount, "bar count label helper was not exported")

local calls = {}
local fontString = {
    SetFormattedText = function(self, formatString, ...)
        calls[#calls + 1] = {
            formatString = formatString,
            args = { ... },
        }
        return true
    end,
}

local secretStacks = NewSecretValue("stacks")
local ok, method = applyNameText(fontString, "Aura Name", {
    sinkText = secretStacks,
    shown = true,
    source = "display-count",
})

assert(ok == true, "secret display-count stack should be applied")
assert(method == "wrapped-count", "secret display-count stack should use C-side wrapping")
assert(calls[1].formatString == "%s%s", "secret stack suffix should be passed as a SetFormattedText argument")
assert(calls[1].args[1] == "Aura Name", "name should remain the first formatted arg")
assert(rawequal(calls[1].args[2], wrappedSecretStacks), "wrapped secret stack should be forwarded without Lua conversion")

calls = {}
local secretEmptyStacks = NewSecretValue("empty")
ok, method = applyNameText(fontString, "Aura Name", {
    sinkText = secretEmptyStacks,
    shown = true,
    source = "display-count",
})

assert(ok == true, "empty secret display-count stack should still write the name")
assert(method == "name-only", "empty secret display-count stack should not emit empty parentheses")
assert(calls[1].formatString == "%s", "empty secret display-count stack should use name-only formatting")

calls = {}
ok, method = applyNameText(fontString, "Aura Name", nil)

assert(ok == true, "missing stack should still write the name")
assert(method == "name-only", "missing stack should use name-only path")
assert(calls[1].formatString == "%s", "name-only path should not add stack punctuation")

calls = {}
ok, method = applyNameText(fontString, "Aura Name", {
    sinkText = secretStacks,
    shown = true,
    source = "mirror-stack-text",
})

assert(ok == true, "shared secret count payload should be applied")
assert(method == "wrapped-count", "shared secret count should use C-side wrapping")
assert(calls[1].formatString == "%s%s", "shared secret count should append through SetFormattedText")
assert(calls[1].args[1] == "Aura Name", "shared count should preserve the clean name argument")
assert(rawequal(calls[1].args[2], wrappedSecretStacks),
    "shared secret count should be wrapped C-side and forwarded without Lua conversion")

calls = {}
ok, method = applyNameText(fontString, "Aura Name", {
    value = 6,
    shown = true,
    source = "display-count",
})

assert(ok == true, "shared count payload should use the safe numeric value when sink text is absent")
assert(method == "wrapped-count", "shared display count value should use count formatting")
assert(calls[1].formatString == "%s%s", "shared display count should append to the name")
assert(calls[1].args[2] == " (6)", "shared count value should be the rendered suffix")

local capturedParams
ns.CDMSpellData = {
    IsAuraEntry = function(entry, viewerType)
        return entry and entry.kind == "aura" and viewerType == "trackedBar"
    end,
    ResolveAuraState = function(_, params)
        capturedParams = params
        return { isActive = false }
    end,
}

local bar = {
    _spellID = 195182,
    _spellEntry = {
        id = 195182,
        spellID = 195182,
        name = "Marrowrend",
        kind = "aura",
        type = "spell",
        viewerType = "trackedBar",
        cooldownID = 5872,
    },
}

bars:UpdateOwnedBarAura(bar)

assert(capturedParams, "bar update should call ResolveAuraState")
assert(capturedParams.blizzardMirrorCooldownID == 5872,
    "bar resolver params should carry the exact mirror cooldownID")
assert(capturedParams.blizzardMirrorCategory == "trackedBar",
    "bar resolver params should carry the exact mirror category")

capturedParams = nil
bar._spellEntry.viewerType = "customBar"
bar._spellEntry.cooldownID = 91002

bars:UpdateOwnedBarAura(bar)

assert(capturedParams, "custom bar update should call ResolveAuraState")
assert(capturedParams.blizzardMirrorCooldownID == 91002,
    "custom bar resolver params should still carry the exact mirror cooldownID")
assert(capturedParams.blizzardMirrorCategory == nil,
    "custom bar resolver params should not invent a non-native mirror category")

local sharedIdentityEntry
ns.CDMResolvers = {
    ResolveBlizzardMirrorIdentity = function(entry)
        sharedIdentityEntry = entry
        return 73542, "buff"
    end,
}
capturedParams = nil
bar._spellEntry = {
    id = 1242998,
    spellID = 1242998,
    name = "Blood Shield",
    kind = "aura",
    type = "spell",
    viewerType = "customBar",
}
bar._spellID = 1242998

bars:UpdateOwnedBarAura(bar)

assert(sharedIdentityEntry == bar._spellEntry,
    "bar aura update should use the shared entry mirror identity resolver")
assert(capturedParams.blizzardMirrorCooldownID == 73542,
    "bar resolver params should carry shared mirror cooldownID")
assert(capturedParams.blizzardMirrorCategory == "buff",
    "bar resolver params should carry shared mirror category")

local barMirrorDuration = { token = "bar-mirror-duration" }
local mirrorPayloadEntry
local mirrorPayloadCooldownID
local mirrorPayloadCategory
local mirrorPayloadSpellID
local resolveAuraStateCalls = 0
ns.CDMResolvers = {
    ResolveBlizzardMirrorIdentity = function(entry)
        sharedIdentityEntry = entry
        return 73543, "trackedBar"
    end,
    ResolveMirrorRenderPayloadForEntry = function(entry, cooldownID, category, spellID)
        mirrorPayloadEntry = entry
        mirrorPayloadCooldownID = cooldownID
        mirrorPayloadCategory = category
        mirrorPayloadSpellID = spellID
        return {
            mirrorBacked = true,
            active = true,
            mode = "aura",
            durObj = barMirrorDuration,
            auraUnit = "target",
            hasExpirationTime = true,
            count = {
                value = 4,
                sinkText = 4,
                shown = true,
                source = "mirror-text",
            },
            state = {
                cooldownID = cooldownID,
                viewerCategory = category,
                durObj = barMirrorDuration,
            },
        }
    end,
}
ns.CDMSpellData.ResolveAuraState = function()
    resolveAuraStateCalls = resolveAuraStateCalls + 1
    return { isActive = false }
end

bar._spellEntry = {
    id = 343294,
    spellID = 343294,
    name = "Soul Reaper",
    kind = "aura",
    type = "spell",
    viewerType = "trackedBar",
}
bar._spellID = 343294

bars:UpdateOwnedBarAura(bar)

assert(sharedIdentityEntry == bar._spellEntry,
    "bar mirror payload lookup should use the shared mirror identity resolver")
assert(mirrorPayloadEntry == bar._spellEntry,
    "bar mirror payload lookup should receive the bar entry")
assert(mirrorPayloadCooldownID == 73543,
    "bar mirror payload lookup should receive the resolved mirror cooldownID")
assert(mirrorPayloadCategory == "trackedBar",
    "bar mirror payload lookup should receive the resolved mirror category")
assert(mirrorPayloadSpellID == 343294,
    "bar mirror payload lookup should receive the bar spellID")
assert(resolveAuraStateCalls == 0,
    "valid bar mirror payload should bypass ResolveAuraState adjudication")
assert(bar._active == true, "valid bar mirror payload should render as active")
assert(bar._auraDataUnit == "target", "valid bar mirror payload should pass aura unit to render")

print("OK: cdm_bars_label_test")
