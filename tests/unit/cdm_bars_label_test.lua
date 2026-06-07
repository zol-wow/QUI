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
local function NormalizeTestMirrorCategory(category)
    if category == "essential"
        or category == "utility"
        or category == "buff"
        or category == "trackedBar" then
        return category
    end
    return nil
end

local function BuildTestCooldownStateContext(owner, entry, runtimeSpellID, options)
    local context = owner._cooldownStateContext
    if not context then
        context = {}
        owner._cooldownStateContext = context
    end
    local identity = ns.CDMResolvers.ResolveBlizzardMirrorIdentityState
        and ns.CDMResolvers.ResolveBlizzardMirrorIdentityState(entry)
    context.entry = entry
    context.runtimeSpellID = runtimeSpellID
    if identity then
        context.mirrorCooldownID = identity.cooldownID
        context.mirrorCategory = identity.category
    else
        context.mirrorCooldownID = entry and entry.cooldownID
        context.mirrorCategory = entry
            and (NormalizeTestMirrorCategory(entry.blizzardMirrorCategory)
                or NormalizeTestMirrorCategory(entry.viewerCategory)
                or NormalizeTestMirrorCategory(entry.viewerType))
            or nil
    end
    context.containerKey = (options and options.containerKey)
        or (entry and entry.viewerType)
        or (options and options.fallbackContainerKey)
    context.totemSlot = options and options.totemSlot
    context.useBuffSwipe = options and options.useBuffSwipe
    context.skipAuraPhase = options and options.skipAuraPhase == true
    context.cachedMirrorState = options and options.cachedMirrorState
    context.cachedMirrorSourceID = options and options.cachedMirrorSourceID
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
assert(capturedParams.mirrorCooldownID == 5872,
    "bar resolver params should carry the exact mirror cooldownID")
assert(capturedParams.mirrorCategory == "trackedBar",
    "bar resolver params should carry the exact mirror category")

capturedParams = nil
bar._spellEntry.viewerType = "customBar"
bar._spellEntry.cooldownID = 91002

bars:UpdateOwnedBarAura(bar)

assert(capturedParams, "custom bar update should call ResolveCooldownState")
assert(capturedParams.mirrorCooldownID == 91002,
    "custom bar resolver params should still carry the exact mirror cooldownID")
assert(capturedParams.mirrorCategory == nil,
    "custom bar resolver params should not invent a non-native mirror category")

local sharedIdentityEntry
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveBlizzardMirrorIdentityState = function(entry)
        sharedIdentityEntry = entry
        return {
            cooldownID = 73542,
            category = "buff",
        }
    end,
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
assert(capturedParams.mirrorCooldownID == 73542,
    "bar resolver params should carry shared mirror cooldownID")
assert(capturedParams.mirrorCategory == "buff",
    "bar resolver params should carry shared mirror category")

local barMirrorDuration = { token = "bar-mirror-duration" }
local barMirrorAuraData = { icon = 98765 }
local mirrorStateEntry
local mirrorStateCooldownID
local mirrorStateCategory
local mirrorStateSpellID
local cachedBarMirrorState
local cachedBarMirrorSourceID
local appliedMirrorAuraTexture
local barMirrorState = {
    cooldownID = 73543,
    viewerCategory = "trackedBar",
    durObj = barMirrorDuration,
}
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveBlizzardMirrorIdentityState = function(entry)
        sharedIdentityEntry = entry
        return {
            cooldownID = 73543,
            category = "trackedBar",
        }
    end,
    ResolveCooldownState = function(context)
        mirrorStateEntry = context.entry
        mirrorStateCooldownID = context.mirrorCooldownID
        mirrorStateCategory = context.mirrorCategory
        mirrorStateSpellID = context.runtimeSpellID
        cachedBarMirrorState = context.cachedMirrorState
        cachedBarMirrorSourceID = context.cachedMirrorSourceID
        return {
            mirrorBacked = true,
            active = true,
            isActive = true,
            mode = "aura",
            durObj = barMirrorDuration,
            auraUnit = "target",
            auraData = barMirrorAuraData,
            spellID = context.runtimeSpellID,
            hasExpirationTime = true,
            count = {
                value = 4,
                sinkText = 4,
                shown = true,
                source = "mirror-text",
            },
            sourceID = "mirror:73543:1",
            mirrorState = barMirrorState,
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
        appliedMirrorAuraTexture = texture
    end,
}

bars:UpdateOwnedBarAura(bar)

assert(sharedIdentityEntry == bar._spellEntry,
    "bar state resolution should use the shared mirror identity resolver")
assert(mirrorStateEntry == bar._spellEntry,
    "bar state resolution should receive the bar entry")
assert(mirrorStateCooldownID == 73543,
    "bar state resolution should receive the resolved mirror cooldownID")
assert(mirrorStateCategory == "trackedBar",
    "bar state resolution should receive the resolved mirror category")
assert(mirrorStateSpellID == 343294,
    "bar state resolution should receive the bar spellID")
assert(bar._active == true, "valid bar mirror payload should render as active")
assert(bar._auraDataUnit == "target", "valid bar mirror payload should pass aura unit to render")
assert(appliedMirrorAuraTexture == 98765,
    "valid bar mirror payload should pass auraData through to runtime texture rendering")
assert(bar._cdmRuntimeState and bar._cdmRuntimeState.mirrorState == barMirrorState,
    "bar runtime state should keep the renderer mirror state on the bar frame")
assert(bar._cdmRuntimeState and bar._cdmRuntimeState.mirrorSourceID == "mirror:73543:1",
    "bar runtime state should keep the mirror source key on the bar frame")

bars:UpdateOwnedBarAura(bar)
-- The bar must NOT feed its frame-owned mirror state back into the resolve.
-- GetStateByCooldownID returns a per-key PackState table refreshed only when
-- called, and the resolver's cached-state fast path deliberately skips
-- re-querying the live mirror -- so a snapshot cached while an aura was
-- inactive freezes a cross-category buff bar at mode=inactive even after the
-- buff goes live (the "won't activate until a rebuild / breaks on /reload"
-- bug). Resolving fresh each poll, like the icon path, reads the live aura.
assert(cachedBarMirrorState == nil,
    "bar resolver context must not feed a cached mirror state (resolve fresh each poll)")
assert(cachedBarMirrorSourceID == nil,
    "bar resolver context must not feed a cached mirror source key")

local spellCooldownDurObj = { token = "spell-cooldown-duration" }
local spellCooldownTimerDuration
local spellCooldownQueryID
ns.CDMResolvers = {
    BuildCooldownStateContext = BuildTestCooldownStateContext,
    ResolveBlizzardMirrorIdentityState = function()
        return nil
    end,
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
    ResolveBlizzardMirrorIdentityState = function()
        return nil
    end,
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
    ResolveBlizzardMirrorIdentityState = function()
        return {
            cooldownID = 80808,
            category = "trackedBar",
        }
    end,
    ResolveCooldownState = function(context)
        return {
            mirrorBacked = true,
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
    ResolveBlizzardMirrorIdentityState = function()
        return {
            cooldownID = 48707,
            category = "trackedBar",
        }
    end,
    ResolveCooldownState = function(context)
        return {
            mirrorBacked = true,
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
            mirrorBacked = true,
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
