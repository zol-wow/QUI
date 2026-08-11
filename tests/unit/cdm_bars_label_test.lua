-- tests/unit/cdm_bars_label_test.lua
-- Run: lua tests/unit/cdm_bars_label_test.lua
-- luacheck: globals InCombatLockdown CreateFrame C_StringUtil

local secretValueMT = {
    __eq = function()
        error("secret value compared")
    end,
    __lt = function()
        error("secret value compared")
    end,
    __le = function()
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

local inCombatLockdown = false
function InCombatLockdown() return inCombatLockdown end
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
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function(value)
            return getmetatable(value) == secretValueMT
        end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_bar_renderer.lua"))("QUI", ns)
ns.CDMRuntimeStore = {
    SetBarState = function(bar, state)
        bar._cdmRuntimeState = state
        return state
    end,
    GetFrameState = function(bar)
        return bar and bar._cdmRuntimeState or nil
    end,
    ClearFrame = function(bar)
        if bar then bar._cdmRuntimeState = nil end
    end,
}

local bars = assert(ns.CDMBars, "CDMBars table was not exported")
assert(bars.ApplyNameTextWithStacks == nil, "legacy bar stack label helper should not be exported")
local applyNameText = assert(bars.ApplyNameTextWithCount, "bar count label helper was not exported")

local normalizeTracked = assert(bars._NormalizeTrackedBarRuntimeEntries,
    "tracked-bar runtime entry normalizer should be exported for focused tests")
local nativeEntries = normalizeTracked({
    {
        spellID = 48707,
        baseSpellID = 48707,
        overrideSpellID = 51052,
        name = "Anti-Magic Shell",
        iconTexture = 136120,
        cooldownID = 70805,
        layoutIndex = 2,
        isActive = true,
    },
    {
        spellID = 55233,
        name = "Vampiric Blood",
        cooldownID = 55233,
        layoutIndex = 1,
    },
})
assert(#nativeEntries == 2, "normalizer keeps valid native tracked-bar entries")
assert(nativeEntries[1].id == 51052, "normalizer uses override spell ID as the runtime identity")
assert(nativeEntries[1].spellID == 48707, "normalizer preserves the base aura spell ID")
assert(nativeEntries[1].viewerType == "trackedBar", "normalizer scopes entries to trackedBar")
assert(nativeEntries[1].kind == "aura" and nativeEntries[1].isAura == true,
    "tracked-bar native entries remain aura-kind owned bars")
assert(nativeEntries[1].source == "blizzardCDM", "normalizer records the native CDM source")
assert(nativeEntries[1].iconTexture == 136120, "normalizer preserves the native icon texture")
assert(nativeEntries[1]._trackedBarRuntime == true, "normalizer marks native runtime entries")
assert(nativeEntries[1]._trackedBarActive == true, "normalizer preserves the native active flag")
assert(nativeEntries[1]._instanceKey == "trackedBar:70805",
    "normalizer keys entries by native cooldown identity when available")
assert(normalizeTracked({ { name = "unresolved" } }) == nil,
    "normalizer ignores entries without a usable spell or cooldown identity")

local buildTracked = assert(bars._BuildTrackedBarSpellList,
    "tracked-bar ownership merge helper should be exported for focused tests")
local configuredTracked = {
    {
        id = 395296,
        spellID = 395296,
        name = "Death's Caress",
        type = "spell",
        kind = "aura",
        viewerType = "trackedBar",
        source = "owned-config",
    },
}
local filteredTracked = buildTracked({
    {
        spellID = 395296,
        name = "Death's Caress",
        cooldownID = 91001,
        layoutIndex = 1,
        isActive = true,
    },
    {
        spellID = 377440,
        name = "Anti-Magic Zone",
        cooldownID = 91002,
        layoutIndex = 2,
        isActive = true,
    },
}, configuredTracked, true)
assert(#filteredTracked == 1,
    "tracked-bar runtime mirror must be filtered through initialized QUI ownership")
assert(filteredTracked[1].id == 395296,
    "tracked-bar merge keeps the configured spell identity")
assert(filteredTracked[1].cooldownID == 91001,
    "tracked-bar merge enriches the configured spell with the native cooldown identity")
assert(filteredTracked[1]._trackedBarRuntime == true,
    "tracked-bar merge keeps matched native runtime metadata")
assert(filteredTracked[1].source == "owned-config",
    "tracked-bar merge must not rewrite configured ownership source")

local emptiedTracked = buildTracked({
    { spellID = 377440, name = "Anti-Magic Zone", cooldownID = 91002 },
}, {}, true)
assert(type(emptiedTracked) == "table" and #emptiedTracked == 0,
    "initialized empty trackedBar ownership must clear bars instead of mirroring Blizzard runtime bars")

local fallbackTracked = buildTracked({
    { spellID = 377440, name = "Anti-Magic Zone", cooldownID = 91002 },
}, nil, false)
assert(#fallbackTracked == 1 and fallbackTracked[1].id == 377440,
    "uninitialized trackedBar ownership may still use Blizzard runtime entries as first-load fallback")

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
-- Mirrors the live CDMResolvers.BuildCooldownStateContext contract: the context
-- carries entry/spellID/containerKey only. The Blizzard mirror identity
-- resolution path was removed from the bar renderer, so the context no longer
-- carries mirrorCooldownID/mirrorCategory.
local function BuildTestCooldownStateContext(owner, entry, runtimeSpellID, options)
    local context = owner._cooldownStateContext
    if not context then
        context = {}
        owner._cooldownStateContext = context
    end
    context.entry = entry
    context.runtimeSpellID = runtimeSpellID
    context.containerKey = (options and options.containerKey)
        or (entry and entry.viewerType)
        or (options and options.fallbackContainerKey)
    context.totemSlot = options and options.totemSlot
    context.useBuffSwipe = options and options.useBuffSwipe
    context.skipAuraPhase = options and options.skipAuraPhase == true
    return context
end

ns.CDMSpellData = {
    IsAuraEntry = function(entry, viewerType)
        return entry and entry.kind == "aura" and viewerType == "trackedBar"
    end,
    GetSpellOverride = function() return nil end,
}
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveCooldownState = function(context)
        capturedParams = context
        return {
            mode = "inactive",
            active = false,
            isActive = false,
            spellID = context and context.runtimeSpellID,
        }
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

assert(capturedParams, "bar update should call ResolveCooldownState")
assert(capturedParams.runtimeSpellID == 195182,
    "bar resolver params should carry the bar spellID")
assert(capturedParams.containerKey == "trackedBar",
    "bar resolver params should carry the bar container key")

capturedParams = nil
bar._spellEntry.viewerType = "customBar"
bar._spellEntry.cooldownID = 91002

bars:UpdateOwnedBarAura(bar)

assert(capturedParams, "custom bar update should call ResolveCooldownState")
assert(capturedParams.runtimeSpellID == 195182,
    "custom bar resolver params should carry the bar spellID")
assert(capturedParams.containerKey == "customBar",
    "custom bar resolver params should carry the custom-bar container key")

local barAuraDuration = { token = "bar-aura-duration" }
local barAuraData = { icon = 98765 }
local barStateEntry
local barStateSpellID
local appliedAuraTexture
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveCooldownState = function(context)
        barStateEntry = context.entry
        barStateSpellID = context.runtimeSpellID
        return {
            active = true,
            isActive = true,
            mode = "aura",
            durObj = barAuraDuration,
            auraUnit = "target",
            auraData = barAuraData,
            spellID = context.runtimeSpellID,
            hasExpirationTime = true,
        }
    end,
}
bar._spellEntry = {
    id = 343294,
    spellID = 343294,
    name = "Soul Reaper",
    kind = "aura",
    type = "spell",
    viewerType = "trackedBar",
}
bar._spellID = 343294
bar.IconTexture = {
    SetTexture = function(_, texture)
        appliedAuraTexture = texture
    end,
}

bars:UpdateOwnedBarAura(bar)

assert(barStateEntry == bar._spellEntry,
    "bar state resolution should receive the bar entry")
assert(barStateSpellID == 343294,
    "bar state resolution should receive the bar spellID")
assert(bar._active == true, "active bar aura payload should render as active")
assert(bar._auraDataUnit == "target", "active bar aura payload should pass aura unit to render")
assert(appliedAuraTexture == 98765,
    "active bar aura payload should pass auraData through to runtime texture rendering")

bars:UpdateOwnedBarAura(bar)
-- The bar must NOT feed a cached state back into the resolve. The resolver's
-- cached-state fast path deliberately skips re-querying live data, so a
-- snapshot cached while an aura was inactive would freeze a cross-category
-- buff bar at mode=inactive even after the buff goes live (the "won't activate
-- until a rebuild / breaks on /reload" bug). Resolving fresh each poll, like
-- the icon path, reads the live aura.

local spellCooldownDurObj = { token = "spell-cooldown-duration" }
local spellCooldownTimerDuration
local spellCooldownQueryID
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveCooldownState = function(context)
        local spellID = context and context.runtimeSpellID
        spellCooldownQueryID = spellID
        return {
            mode = "cooldown",
            active = true,
            isActive = true,
            durObj = spellCooldownDurObj,
            spellID = spellID,
            resolvedAuraSpellID = spellID,
            hasExpirationTime = true,
        }
    end,
}
ns.CDMSpellData.ResolveDisplayName = function(_, entry)
    return entry and entry.name
end

local spellCooldownBar = {
    _spellID = 47528,
    _spellEntry = {
        id = 47528,
        spellID = 47528,
        name = "Mind Freeze",
        kind = "cooldown",
        type = "spell",
        viewerType = "customBar",
    },
    StatusBar = {
        SetMinMaxValues = function() end,
        SetValue = function() end,
        SetTimerDuration = function(_, durObj)
            spellCooldownTimerDuration = durObj
        end,
    },
    DurationText = {
        SetText = function() end,
        SetAlpha = function() end,
    },
    PermanentFill = {
        SetAlpha = function() end,
    },
    IconTexture = {
        SetTexture = function() end,
    },
    NameText = {
        SetText = function() end,
        SetFormattedText = function() end,
    },
}

bars:UpdateOwnedBarAura(spellCooldownBar)

assert(spellCooldownQueryID == 47528,
    "non-mirror spell cooldown bar should pass the cooldown spellID to resolved state")
assert(spellCooldownBar._active == true,
    "non-mirror spell cooldown bar should render active from cooldown state")
assert(spellCooldownBar._durObj == spellCooldownDurObj,
    "non-mirror spell cooldown bar should retain the cooldown DurationObject")
assert(spellCooldownTimerDuration == spellCooldownDurObj,
    "non-mirror spell cooldown bar should drive status-bar fill from the cooldown DurationObject")

local itemCooldownDurObj = {
    token = "item-cooldown-duration",
    GetRemainingDuration = function()
        return NewSecretValue("item-remaining")
    end,
}
local itemCooldownContext
local itemCooldownTimerDuration
local itemCooldownTimerInterpolation
local itemCooldownTimerDirection
local itemCooldownNumericWrites = 0
local itemCooldownTextArg
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveCooldownState = function(context)
        itemCooldownContext = context
        return {
            mode = "item-cooldown",
            active = true,
            isActive = true,
            isOnCooldown = true,
            durObj = itemCooldownDurObj,
            numericCooldownActive = nil,
            spellID = context and context.runtimeSpellID,
        }
    end,
}

local itemCooldownBar = {
    _spellID = 91004,
    _spellEntry = {
        id = 90004,
        itemID = 90004,
        name = "Light Company Guidon",
        kind = "cooldown",
        type = "item",
        viewerType = "customBar",
    },
    StatusBar = {
        SetMinMaxValues = function()
            itemCooldownNumericWrites = itemCooldownNumericWrites + 1
        end,
        SetValue = function()
            itemCooldownNumericWrites = itemCooldownNumericWrites + 1
        end,
        SetTimerDuration = function(_, durObj, interpolation, direction)
            itemCooldownTimerDuration = durObj
            itemCooldownTimerInterpolation = interpolation
            itemCooldownTimerDirection = direction
        end,
    },
    DurationText = {
        SetText = function() end,
        SetFormattedText = function(_, _, remaining)
            itemCooldownTextArg = remaining
        end,
    },
    IconTexture = {
        SetTexture = function() end,
    },
    NameText = {
        SetText = function() end,
        SetFormattedText = function() end,
    },
}

bars:UpdateOwnedBarAura(itemCooldownBar)

assert(itemCooldownContext and itemCooldownContext.entry == itemCooldownBar._spellEntry,
    "item cooldown bar should use the shared resolved state context")
assert(itemCooldownBar._active == true,
    "DurationObject-only item cooldown should render active")
assert(itemCooldownBar._durObj == itemCooldownDurObj,
    "DurationObject-only item cooldown should retain the DurationObject")
assert(itemCooldownTimerDuration == itemCooldownDurObj,
    "DurationObject-only item cooldown should bind StatusBar:SetTimerDuration")
assert(itemCooldownTimerInterpolation == 0,
    "item cooldown bar DurationObject fill should use Immediate interpolation")
assert(itemCooldownTimerDirection == 1,
    "item cooldown bar DurationObject fill should use RemainingTime direction")
assert(itemCooldownNumericWrites == 0,
    "DurationObject-only item cooldown should not require numeric StatusBar writes")
assert(itemCooldownBar._totalDuration == nil and itemCooldownBar._expirationTime == nil,
    "DurationObject-only item cooldown should not invent numeric timing")
assert(getmetatable(itemCooldownTextArg) == secretValueMT,
    "item cooldown bar should forward DurationObject remaining time to SetFormattedText")

local cleanItemDurObj = {
    token = "clean-item-cooldown-duration",
    GetRemainingDuration = function()
        return 80
    end,
}
local cleanItemTimerDuration
ns.CDMResolvers.ResolveCooldownState = function(context)
    return {
        mode = "item-cooldown",
        active = true,
        isActive = true,
        isOnCooldown = true,
        durObj = cleanItemDurObj,
        numericCooldownActive = true,
        start = 100,
        duration = 90,
        spellID = context and context.runtimeSpellID,
    }
end
itemCooldownBar.StatusBar.SetTimerDuration = function(_, durObj)
    cleanItemTimerDuration = durObj
end
itemCooldownNumericWrites = 0
itemCooldownTextArg = nil

bars:UpdateOwnedBarAura(itemCooldownBar)

assert(cleanItemTimerDuration == cleanItemDurObj,
    "clean item cooldown should still prefer StatusBar:SetTimerDuration")
assert(itemCooldownNumericWrites == 0,
    "clean item cooldown with a DurationObject should not fall back to numeric fill")
assert(itemCooldownBar._totalDuration == 90 and itemCooldownBar._expirationTime == 190,
    "clean item cooldown should retain numeric timing for bar state")

local combatAuraDataDurObj = { token = "combat-auraData-duration" }
local combatAuraDataTimerDuration
local combatAuraData = {
    duration = NewSecretValue("duration"),
    icon = 87654,
}
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveCooldownState = function(context)
        return {
            active = true,
            isActive = true,
            mode = "aura",
            durObj = combatAuraDataDurObj,
            auraUnit = "player",
            auraData = combatAuraData,
            spellID = context and context.runtimeSpellID,
            hasExpirationTime = true,
        }
    end,
}

local combatAuraDataBar = {
    _spellID = 80808,
    _spellEntry = {
        id = 80808,
        spellID = 80808,
        name = "Combat Aura",
        kind = "aura",
        type = "spell",
        viewerType = "trackedBar",
    },
    StatusBar = {
        SetMinMaxValues = function() end,
        SetValue = function() end,
        SetTimerDuration = function(_, durObj)
            combatAuraDataTimerDuration = durObj
        end,
    },
    DurationText = {
        SetText = function() end,
        SetAlpha = function() end,
    },
    PermanentFill = {
        SetAlpha = function() end,
    },
    IconTexture = {
        SetTexture = function() end,
    },
    NameText = {
        SetText = function() end,
        SetFormattedText = function() end,
    },
}

inCombatLockdown = true
ok = pcall(function()
    bars:UpdateOwnedBarAura(combatAuraDataBar)
end)
inCombatLockdown = false

assert(ok == true,
    "combat bar mirror should not compare secret fields from child-sourced auraData")
assert(combatAuraDataBar._active == true,
    "combat bar mirror should render active with child-sourced auraData")
assert(combatAuraDataTimerDuration == combatAuraDataDurObj,
    "combat bar mirror should still bind the child DurationObject")

local immediateRemaining = NewSecretValue("remaining-duration")
local immediateDurObj = {
    GetRemainingDuration = function()
        return immediateRemaining
    end,
}
local immediateDurationFormat
local immediateDurationValue
local immediateTimerDuration
local immediateTimerInterpolation
local immediateTimerDirection
local immediateMinMaxCalls = 0
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveCooldownState = function(context)
        return {
            active = true,
            isActive = true,
            mode = "aura",
            durObj = immediateDurObj,
            auraUnit = "player",
            spellID = context and context.runtimeSpellID,
            hasExpirationTime = true,
        }
    end,
}

local immediateTextBar = {
    _spellID = 48707,
    _spellEntry = {
        id = 48707,
        spellID = 48707,
        name = "Immediate Text Aura",
        kind = "aura",
        type = "spell",
        viewerType = "trackedBar",
    },
    StatusBar = {
        SetMinMaxValues = function()
            immediateMinMaxCalls = immediateMinMaxCalls + 1
        end,
        SetValue = function() end,
        SetTimerDuration = function(_, durObj, interpolation, direction)
            immediateTimerDuration = durObj
            immediateTimerInterpolation = interpolation
            immediateTimerDirection = direction
        end,
    },
    DurationText = {
        SetText = function() end,
        SetAlpha = function() end,
        SetFormattedText = function(_, format, value)
            immediateDurationFormat = format
            immediateDurationValue = value
        end,
    },
    PermanentFill = {
        SetAlpha = function() end,
    },
    IconTexture = {
        SetTexture = function() end,
    },
    NameText = {
        SetText = function() end,
        SetFormattedText = function() end,
    },
}

inCombatLockdown = true
ok = pcall(function()
    bars:UpdateOwnedBarAura(immediateTextBar)
end)
inCombatLockdown = false

assert(ok == true,
    "combat bar mirror should write initial duration text without reading secrets in Lua")
assert(immediateTimerDuration == immediateDurObj,
    "immediate duration text bar should still bind the child DurationObject")
assert(immediateTimerInterpolation == 0,
    "bar DurationObject fill should use Immediate interpolation")
assert(immediateTimerDirection == 1,
    "bar DurationObject fill should use RemainingTime direction")
assert(immediateMinMaxCalls == 0,
    "bar DurationObject fill should leave status-bar range to SetTimerDuration")
assert(immediateDurationFormat == "%.1f",
    "active timed bar should write the first duration text immediately")
assert(rawequal(immediateDurationValue, immediateRemaining),
    "initial duration text should forward the secret remaining duration to the C-side formatter")

local refreshedAuraDurObj = {
    token = "refreshed-aura-duration",
    GetRemainingDuration = function()
        return NewSecretValue("refreshed-remaining")
    end,
}
local refreshedAuraTimerCalls = 0
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveCooldownState = function(context)
        return {
            active = true,
            isActive = true,
            mode = "aura",
            durObj = refreshedAuraDurObj,
            auraUnit = "player",
            auraInstanceID = 9901,
            spellID = context and context.runtimeSpellID,
            hasExpirationTime = true,
        }
    end,
}

local refreshedAuraBar = {
    _spellID = 195181,
    _spellEntry = {
        id = 195181,
        spellID = 195181,
        name = "Bone Shield",
        kind = "aura",
        type = "spell",
        viewerType = "trackedBar",
    },
    _active = true,
    _auraUnit = "player",
    _auraInstanceID = 9901,
    _durObj = refreshedAuraDurObj,
    _cSideFill = true,
    StatusBar = {
        SetMinMaxValues = function() end,
        SetValue = function() end,
        SetTimerDuration = function(_, durObj)
            refreshedAuraTimerCalls = refreshedAuraTimerCalls + 1
            assert(durObj == refreshedAuraDurObj,
                "refreshed aura bar should rebind the live DurationObject")
        end,
    },
    DurationText = {
        SetText = function() end,
        SetAlpha = function() end,
        SetFormattedText = function() end,
    },
    PermanentFill = {
        SetAlpha = function() end,
    },
    IconTexture = {
        SetTexture = function() end,
    },
    NameText = {
        SetText = function() end,
        SetFormattedText = function() end,
    },
}

assert(type(bars.MarkBarAuraRefresh) == "function",
    "CDMBars should expose a per-bar aura refresh marker")
assert(bars.MarkBarAuraRefresh(refreshedAuraBar, "player", {
    updatedAuraInstanceIDs = { 9901 },
}) == true, "matching updated aura instance should mark the bar for a timer rebind")

bars:UpdateOwnedBarAura(refreshedAuraBar)

assert(refreshedAuraTimerCalls == 1,
    "a refreshed active aura bar should rebind SetTimerDuration even when the DurationObject identity is unchanged")
assert(refreshedAuraBar._forceTimerDurationRebind == nil,
    "aura refresh rebind flag should clear after the bar is rebound")

print("OK: cdm_bars_label_test")
