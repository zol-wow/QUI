-- tests/unit/cdm_icons_stack_resolution_test.lua
-- Run: lua tests/unit/cdm_icons_stack_resolution_test.lua
-- luacheck: globals issecretvalue InCombatLockdown GetTime wipe CreateFrame C_Timer C_StringUtil C_CurveUtil C_TradeSkillUI

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end
local secretStackText = { token = "secret-stack-text" }
local secretDisplayText = { token = "secret-display-text" }
local secretChargeShown = { token = "secret-charge-shown" }
local secretChargeAlpha = { token = "secret-charge-alpha" }

function issecretvalue(value)
    return rawequal(value, secretStackText)
        or rawequal(value, secretDisplayText)
        or rawequal(value, secretChargeShown)
        or rawequal(value, secretChargeAlpha)
end

local inCombatLockdown = false
function InCombatLockdown() return inCombatLockdown end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

C_Timer = { After = function(_, callback) callback() end }
C_StringUtil = {
    TruncateWhenZero = function(value)
        return value == 0 and "" or tostring(value)
    end,
}
C_CurveUtil = {
    EvaluateColorValueFromBoolean = function(value, trueValue, falseValue)
        assert(rawequal(value, secretChargeShown),
            "secret charge visibility should be passed directly to CurveUtil")
        assert(trueValue == 1 and falseValue == 0,
            "secret charge visibility should map true to alpha 1 and false to alpha 0")
        return secretChargeAlpha
    end,
}

local queriedMinApplications
local lastCooldownStateContext
local trackerDB = {}

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function()
                return trackerDB
            end
        end,
        IsSecretValue = function() return false end,
        CanAccessTable = function(tbl) return type(tbl) == "table" end,
        IsEditModeActive = function() return false end,
        IsLayoutModeActive = function() return false end,
    },
    Addon = {
        db = {
            profile = { ncdm = {} },
            char = { ncdm = {} },
        },
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        IsSafeNumeric = function(value) return type(value) == "number" end,
        GetBuiltinContainerEntryKind = function(containerKey)
            return ({
                essential = "cooldown",
                utility = "cooldown",
                buff = "aura",
                trackedBar = "aura",
                aliasAura = "aura",
                aliasCooldown = "cooldown",
            })[containerKey]
        end,
    },
    CDMSources = {
        QueryAuraApplicationDisplayCount = function(unit, auraInstanceID, minApplications)
            queriedMinApplications = minApplications
            if unit == "target" and auraInstanceID == 9001 and minApplications == 2 then
                return "4"
            end
            return nil
        end,
        QuerySpellCooldown = function()
            return {
                startTime = 0,
                duration = 0,
                isActive = false,
            }
        end,
        QuerySpellDisplayCount = function(spellID)
            if spellID == 1227280 then
                return 2
            elseif spellID == 55091 then
                return "8"
            elseif spellID == 55092 then
                return secretDisplayText
            end
            return nil
        end,
        QuerySpellCount = function(spellID)
            if spellID == 473662 then
                return 5
            end
            return nil
        end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        IsAuraEntry = function(entry)
            return entry and entry.kind == "aura"
        end,
        ResolveBlizzardMirrorIdentityState = function(entry)
            if entry and entry.spellID == 1227280 then
                local state = {
                    cooldownID = 8203,
                    spellID = 1227280,
                    overrideSpellID = 1227280,
                    viewerCategory = "essential",
                    stackText = nil,
                    stackTextSource = nil,
                    stackTextShown = nil,
                    cooldownChargesShown = false,
                    chargeCountFrameShown = false,
                }
                return {
                    cooldownID = 8203,
                    category = "essential",
                    state = state,
                }
            end
            return nil
        end,
        ResolveCooldownState = function(context)
            lastCooldownStateContext = context
            return {
                mode = "inactive",
                active = false,
                isActive = false,
                auraActive = false,
                isOnCooldown = false,
            }
        end,
        ResolveCooldownActivityState = function()
            return { isOnCooldown = false, rechargeActive = false }
        end,
        ResolveMacro = function(entry)
            return entry and entry._macroSpellID, "spell", nil
        end,
        GetSpellTexture = function() return nil end,
        GetEntryTexture = function() return nil end,
        ResolveAuraActiveState = function() return false end,
    },
    CDMIconFactory = {
        _iconPools = {},
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
        SyncCooldownBling = noop,
        GetIconPool = function(self, viewerType)
            return self._iconPools[viewerType] or {}
        end,
        EnsurePool = function(self, viewerType)
            if not self._iconPools[viewerType] then
                self._iconPools[viewerType] = {}
            end
            return self._iconPools[viewerType]
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, category)
            if cooldownID == 73542 and category == "essential" then
                return {
                    stackText = "6",
                    stackTextSource = "Applications",
                    stackTextShown = true,
                }
            end
            if cooldownID == 73544 and category == "essential" then
                return {
                    cooldownChargesCount = "7",
                    cooldownChargesShown = true,
                    stackTextShown = false,
                }
            end
            if cooldownID == 73545 and category == "essential" then
                return {
                    stackText = secretStackText,
                    stackTextSource = "ChargeCount",
                    stackTextShown = true,
                }
            end
            if cooldownID == 73546 and category == "essential" then
                return {
                    stackText = nil,
                    stackTextSource = "ChargeCount",
                    stackTextShown = false,
                    cooldownChargesShown = false,
                    chargeCountFrameShown = false,
                }
            end
            if cooldownID == 73547 and category == "essential" then
                return {
                    cooldownChargesCount = "8",
                    cooldownChargesShown = nil,
                    chargeCountFrameShown = false,
                    chargeTextOwnerShown = true,
                    stackTextSource = "ChargeCount",
                    stackTextShown = false,
                    stackTextEpoch = 88,
                    wasSetFromCooldown = true,
                    wasSetFromCharges = false,
                }
            end
            if cooldownID == 73549 and category == "essential" then
                return {
                    cooldownChargesCount = "8",
                    cooldownChargesShown = true,
                    chargeCountFrameShown = false,
                    chargeTextOwnerShown = false,
                    stackTextSource = "ChargeCount",
                    stackTextShown = false,
                    stackTextEpoch = 90,
                    wasSetFromCooldown = true,
                    wasSetFromCharges = false,
                }
            end
            if cooldownID == 73551 and category == "essential" then
                return {
                    cooldownChargesCount = "5",
                    cooldownChargesShown = secretChargeShown,
                    chargeCountFrameShown = secretChargeShown,
                    stackTextSource = "ChargeCount",
                    stackTextShown = secretChargeShown,
                    stackTextEpoch = 92,
                    wasSetFromCooldown = true,
                    wasSetFromCharges = false,
                }
            end
            if cooldownID == 73552 and category == "essential" then
                return {
                    cooldownChargesCount = secretStackText,
                    cooldownChargesShown = secretChargeShown,
                    chargeCountFrameShown = false,
                    stackText = secretStackText,
                    stackTextSource = "ChargeCount",
                    stackTextShown = secretChargeShown,
                    stackTextEpoch = 93,
                    wasSetFromCooldown = true,
                    wasSetFromCharges = false,
                }
            end
            if cooldownID == 73550 and category == "essential" then
                return {
                    cooldownChargesCount = "9",
                    stackTextSource = "ChargeCount",
                    stackTextEpoch = 91,
                    wasSetFromCooldown = true,
                    wasSetFromCharges = false,
                }
            end
            if cooldownID == 73548 and category == "essential" then
                return {
                    cooldownChargesCount = 0,
                    cooldownChargesShown = false,
                    chargeCountFrameShown = false,
                    chargeTextOwnerShown = true,
                    stackText = 0,
                    stackTextShown = true,
                    stackTextEpoch = 89,
                    wasSetFromCooldown = true,
                    wasSetFromCharges = false,
                }
            end
        end,
    },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local icons = ns.CDMIcons

local cooldownEntry = {
    type = "spell",
    id = 55090,
    spellID = 55090,
    kind = "cooldown",
    viewerType = "essential",
}

local function makePolicyProbeIcon(entry)
    local icon = {
        _spellEntry = entry,
        Cooldown = {
            Clear = noop,
            SetReverse = noop,
        },
        Icon = {
            SetDesaturated = noop,
            SetVertexColor = noop,
        },
        StackText = {
            SetText = noop,
            Hide = noop,
            Show = noop,
        },
    }
    function icon:IsShown() return true end
    function icon:Show() end
    function icon:Hide() end
    function icon:SetAlpha() end
    return icon
end

local function resolvePolicyForEntry(entry)
    local icon = makePolicyProbeIcon(entry)
    local viewerType = entry.viewerType or "__policy"
    local priorPool = ns.CDMIconFactory._iconPools[viewerType]
    ns.CDMIconFactory._iconPools[viewerType] = { icon }
    lastCooldownStateContext = nil
    icons:UpdateCooldownsForType(viewerType)
    ns.CDMIconFactory._iconPools[viewerType] = priorPool
    return lastCooldownStateContext
end

ns._OwnedSwipe = {
    GetSettings = function()
        return {
            showBuffSwipe = true,
            showCooldownIconAuraPhase = true,
        }
    end,
}

local policyContext = resolvePolicyForEntry(cooldownEntry)
assert(policyContext and policyContext.useBuffSwipe == true,
    "cooldown icons should allow buff/debuff phase by default")

ns._OwnedSwipe = {
    GetSettings = function()
        return {
            showBuffSwipe = true,
            showCooldownIconAuraPhase = false,
        }
    end,
}

policyContext = resolvePolicyForEntry(cooldownEntry)
assert(policyContext and policyContext.useBuffSwipe == false,
    "cooldown icons should skip buff/debuff phase when the option is disabled")
assert(policyContext.skipAuraPhase == true,
    "cooldown icons should pass the disabled aura-phase policy into the resolver context")

policyContext = resolvePolicyForEntry({
    type = "spell",
    id = 194310,
    spellID = 194310,
    kind = "aura",
    viewerType = "buff",
})
assert(policyContext and policyContext.useBuffSwipe == true,
    "aura icons should still use buff/debuff swipe aura detection")

local function makeMirrorStackProbe(cooldownID)
    local stackWrites = {}
    local icon = {
        _spellEntry = {
            type = "spell",
            id = 55090,
            spellID = 55090,
            kind = "cooldown",
            viewerType = "essential",
        },
        _blizzMirrorCooldownID = cooldownID,
        _blizzMirrorCategory = "essential",
        StackText = {
            SetText = function(_, value)
                stackWrites[#stackWrites + 1] = { op = "set", value = value }
            end,
            Show = function()
                stackWrites[#stackWrites + 1] = { op = "show" }
            end,
            SetAlpha = function(_, value)
                stackWrites[#stackWrites + 1] = { op = "alpha", value = value }
            end,
            Hide = function()
                stackWrites[#stackWrites + 1] = { op = "hide" }
            end,
        },
    }
    return icon, stackWrites
end

local icon, stackWrites = makeMirrorStackProbe(73542)
icons.OnFactoryMirrorBound(icon, 73542, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "cooldown icons should not render Blizzard mirror Applications text as charge count")
assert(stackWrites[2].op == "hide",
    "cooldown icons should hide when only Applications text is mirrored")

icon, stackWrites = makeMirrorStackProbe(73544)
icons.OnFactoryMirrorBound(icon, 73544, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "7",
    "cooldown icons should mirror Blizzard's cached cast count field")
assert(stackWrites[2].op == "show",
    "cached cast count should remain visible")
assert(icon.cooldownChargesCount == "7",
    "bound QUI icon should keep the mirrored cooldown charge/count payload")
assert(icon.cooldownChargesShown == true,
    "bound QUI icon should keep the mirrored cooldown charge/count show flag")

icon, stackWrites = makeMirrorStackProbe(73547)
icons.OnFactoryMirrorBound(icon, 73547, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "8",
    "cooldown icons should render count fields when the child count text owner is shown")
assert(stackWrites[2].op == "show",
    "shown child count text owners should show during mirror binding")

icon, stackWrites = makeMirrorStackProbe(73549)
icons.OnFactoryMirrorBound(icon, 73549, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "8",
    "cooldown icons should render Blizzard count fields when cooldownChargesShown is explicit true")
assert(stackWrites[2].op == "show",
    "explicit visible Blizzard count fields should show during mirror binding")
assert(icon._lastMirrorStackTextEpoch == 90,
    "explicit visible Blizzard count fields should stamp the rendered mirror epoch during mirror binding")

icon, stackWrites = makeMirrorStackProbe(73551)
icons.OnFactoryMirrorBound(icon, 73551, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "5",
    "secret Blizzard charge visibility should still render mirrored charge text")
assert(stackWrites[2].op == "show",
    "secret Blizzard charge visibility should keep the charge text frame shown")
assert(stackWrites[3].op == "alpha" and stackWrites[3].value == secretChargeAlpha,
    "secret Blizzard charge visibility should gate charge text through alpha")
assert(icon.cooldownChargesShown == secretChargeShown,
    "bound QUI icon should preserve the secret charge visibility gate")

icon, stackWrites = makeMirrorStackProbe(73552)
icon._resolvedCooldownMode = "aura"
icons.OnFactoryMirrorBound(icon, 73552, "essential")

assert(stackWrites[1].op == "set" and rawequal(stackWrites[1].value, secretStackText),
    "aura-mode mirrored ChargeCount text should forward the secret display count")
assert(stackWrites[2].op == "show",
    "aura-mode mirrored ChargeCount text should keep the stack text frame shown")
assert(stackWrites[3].op == "alpha" and stackWrites[3].value == secretChargeAlpha,
    "aura-mode mirrored ChargeCount text should use the secret show gate as alpha")
assert(icon._lastMirrorStackTextEpoch == 93,
    "aura-mode mirrored ChargeCount text should stamp the rendered mirror epoch")

icon, stackWrites = makeMirrorStackProbe(73550)
icons.OnFactoryMirrorBound(icon, 73550, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "cooldown icons should not render count fields with no explicit true visibility")
assert(stackWrites[2].op == "hide",
    "count fields with no explicit true visibility should hide during mirror binding")

icon, stackWrites = makeMirrorStackProbe(73548)
icons.OnFactoryMirrorBound(icon, 73548, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "cooldown icons should clear explicitly hidden Blizzard count fields")
assert(stackWrites[2].op == "hide",
    "explicitly hidden Blizzard count fields should hide during mirror binding")

icon, stackWrites = makeMirrorStackProbe(73545)
icons.OnFactoryMirrorBound(icon, 73545, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "secret mirror ChargeCount text should not show without visible parent count state")
assert(stackWrites[2].op == "hide",
    "secret mirror ChargeCount text should hide without visible parent count state")

icon, stackWrites = makeMirrorStackProbe(73546)
icon._spellEntry.spellID = 55091
icon._spellEntry.id = 55091
icon._runtimeSpellID = 55091
icons.OnFactoryMirrorBound(icon, 73546, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "mirror-hidden non-charge cooldown icons should not re-query display count")
assert(stackWrites[2].op == "hide",
    "mirror-hidden non-charge cooldown icons should hide stale stack text")
assert(icon.cooldownChargesShown == false,
    "hidden mirror count show flag should be copied onto the QUI icon")
assert(icon.chargeCountFrameShown == false,
    "hidden mirror charge frame show flag should be copied onto the QUI icon")
assert(icon.stackTextShown == false,
    "hidden mirror stack state should be copied onto the QUI icon")

local priorShouldAllowStackTextWrites = icons.ShouldAllowStackTextWrites
icons.ShouldAllowStackTextWrites = function() return true end
icon, stackWrites = makeMirrorStackProbe(73546)
icon._spellEntry.spellID = 55092
icon._spellEntry.id = 55092
icon._runtimeSpellID = 55092
local priorPool = ns.CDMIconFactory._iconPools.essential
ns.CDMIconFactory._iconPools.essential = { icon }
inCombatLockdown = true
icons:UpdateCooldownsForType("essential")
inCombatLockdown = false
ns.CDMIconFactory._iconPools.essential = priorPool
icons.ShouldAllowStackTextWrites = priorShouldAllowStackTextWrites

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "combat mirror-hidden non-charge cooldown icons should not re-query secret display count")
assert(stackWrites[2].op == "hide",
    "combat mirror-hidden non-charge cooldown icons should hide stale stack text")

local function makeCooldownOnlyMirrorCountProbe(initialShown)
    local writes = {}
    local shown = initialShown == true
    local probe = {
        _spellEntry = {
            type = "spell",
            id = 55090,
            spellID = 55090,
            kind = "cooldown",
            viewerType = "essential",
        },
        _blizzMirrorCooldownID = 73547,
        _blizzMirrorCategory = "essential",
        Icon = {
            SetTexture = noop,
            SetDesaturated = noop,
            SetVertexColor = noop,
            SetAlpha = noop,
        },
        Cooldown = {
            Clear = noop,
            SetReverse = noop,
            SetDrawSwipe = noop,
            SetDrawBling = noop,
            SetDrawEdge = noop,
            SetSwipeColor = noop,
            SetHideCountdownNumbers = noop,
            SetAlpha = noop,
            Show = noop,
        },
        StackText = {
            SetText = function(_, value)
                writes[#writes + 1] = { op = "set", value = value }
            end,
            Show = function()
                shown = true
                writes[#writes + 1] = { op = "show" }
            end,
            Hide = function()
                shown = false
                writes[#writes + 1] = { op = "hide" }
            end,
            IsShown = function()
                return shown
            end,
            SetAlpha = noop,
        },
        Border = { SetAlpha = noop },
        DurationText = { SetAlpha = noop },
    }
    function probe:IsShown() return true end
    function probe:Show() end
    function probe:Hide() end
    function probe:SetAlpha() end
    return probe, writes
end

icon, stackWrites = makeCooldownOnlyMirrorCountProbe()
icons.ApplyResolvedCooldown(icon)

assert(stackWrites[1] and stackWrites[1].op == "set" and stackWrites[1].value == "8",
    "direct resolved cooldown refresh should write shown child count text")
assert(stackWrites[2] and stackWrites[2].op == "show",
    "direct resolved cooldown refresh should show shown child count text")

icon, stackWrites = makeCooldownOnlyMirrorCountProbe()
icon._blizzMirrorCooldownID = 73549
icons.ApplyResolvedCooldown(icon)

assert(stackWrites[1] and stackWrites[1].op == "set" and stackWrites[1].value == "8",
    "direct resolved cooldown refresh should write explicit visible mirror count text")
assert(stackWrites[2] and stackWrites[2].op == "show",
    "direct resolved cooldown refresh should show explicit visible mirror count text")
assert(icon._lastMirrorStackTextEpoch == 90,
    "direct resolved cooldown refresh should stamp the explicit visible mirror text epoch")

icon, stackWrites = makeCooldownOnlyMirrorCountProbe()
icon._blizzMirrorCooldownID = 73548
icon._stackTextSource = "ChargeCount"
icons.ApplyResolvedCooldown(icon)

assert(stackWrites[1] and stackWrites[1].op == "set" and stackWrites[1].value == "",
    "direct resolved cooldown refresh should clear explicitly hidden mirror count text")
assert(stackWrites[2] and stackWrites[2].op == "hide",
    "direct resolved cooldown refresh should hide explicitly hidden mirror count text")
assert(icon._lastMirrorStackTextEpoch == 89,
    "direct resolved cooldown refresh should stamp the hidden mirror text epoch")

icon, stackWrites = makeCooldownOnlyMirrorCountProbe()
priorPool = ns.CDMIconFactory._iconPools.essential
ns.CDMIconFactory._iconPools.essential = { icon }
icons:UpdateCooldownOnly()
ns.CDMIconFactory._iconPools.essential = priorPool

assert(stackWrites[1] and stackWrites[1].op == "set" and stackWrites[1].value == "8",
    "cooldown-only mirror refresh should write shown child count text")
assert(stackWrites[2] and stackWrites[2].op == "show",
    "cooldown-only mirror refresh should show shown child count text")

icon, stackWrites = makeCooldownOnlyMirrorCountProbe(true)
icon._lastMirrorStackTextEpoch = 88
icon.cooldownChargesShown = true
icon.chargeCountFrameShown = true
priorPool = ns.CDMIconFactory._iconPools.essential
ns.CDMIconFactory._iconPools.essential = { icon }
icons:UpdateCooldownOnly()
ns.CDMIconFactory._iconPools.essential = priorPool

assert(stackWrites[1] == nil,
    "cooldown-only mirror refresh should not rewrite shown count text at the same epoch")
assert(icon.cooldownChargesShown == true,
    "cooldown-only mirror refresh should preserve shown child text owner state")
assert(icon.chargeCountFrameShown == false,
    "cooldown-only mirror refresh should still mirror the parent count frame state")

ns.CDMAuraRuntime.SetAbilityAuraSpellIDResolver(function(spellID)
    if spellID == 55090 then
        return 194310, true
    end
    return spellID, false
end)
ns.CDMAuraRuntime.SetResolver(function(params)
    if params and params.spellID == 55090 then
        return {
            isActive = true,
            isTotemInstance = false,
            count = {
                sinkText = "4",
                value = 4,
                shown = true,
                source = "display-count",
            },
        }
    end
    return { isActive = false }
end)

icon, stackWrites = makeMirrorStackProbe(73543)
icons.OnFactoryMirrorBound(icon, 73543, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "mirror-backed cooldown icons without mirror text should clear stale stack text")
assert(stackWrites[2].op == "hide",
    "mirror-backed cooldown icons without mirror text should hide stale stack text")

icon, stackWrites = makeMirrorStackProbe(73543)
icon._spellEntry.spellID = 473662
icon._spellEntry.id = 473662
icon._runtimeSpellID = 473662
icons.OnFactoryMirrorBound(icon, 73543, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "",
    "mirror-backed non-charge cooldown icons should not synthesize display count as stack text")
assert(stackWrites[2].op == "hide",
    "mirror-backed non-charge cooldown icons without mirror text should stay mirror-authoritative")

local factory = assert(ns.CDMIconFactory, "CDMIconFactory should be exported")
factory:EnsurePool("essential")
local pool = factory:GetIconPool("essential")
local stackWrites = 0
pool[#pool + 1] = {
    _stackTextSource = "spell-display-count",
    _blizzMirrorCooldownID = 73543,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        type = "spell",
        id = 55090,
        spellID = 55090,
        kind = "cooldown",
        viewerType = "essential",
    },
    StackText = {
        SetText = function(_, value)
            stackWrites = stackWrites + 1
        end,
        Hide = function()
            stackWrites = stackWrites + 1
        end,
        Show = function()
            stackWrites = stackWrites + 1
        end,
    },
}

icons:UpdateAllIconRanges()

assert(stackWrites == 0, "range/usability refresh must not write stack text")

local auraQueryIDs = {}
ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    auraQueryIDs[#auraQueryIDs + 1] = spellID
    if spellID == 99102 then
        return {
            applications = 5,
            auraInstanceID = 99102,
        }
    end
    return nil
end

local function makeMacroStackProbe(viewerType)
    local writes = {}
    local probe = {
        _spellEntry = {
            type = "macro",
            kind = "cooldown",
            id = 99101,
            _macroSpellID = 99101,
            viewerType = viewerType,
            linkedSpellIDs = { 99102 },
            name = viewerType,
        },
        Icon = {
            SetTexture = noop,
            SetDesaturated = noop,
            SetVertexColor = noop,
        },
        Cooldown = {
            SetDrawSwipe = noop,
            SetDrawBling = noop,
            SetSwipeColor = noop,
            SetHideCountdownNumbers = noop,
            SetReverse = noop,
            Clear = noop,
            Show = noop,
        },
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
            SetTextColor = noop,
        },
    }
    return probe, writes
end

icons.ShouldAllowStackTextWrites = function() return true end

local aliasIcon, aliasWrites = makeMacroStackProbe("aliasAura")
icons.OnContainerIconPlaced(aliasIcon)

assert(aliasWrites[1] and aliasWrites[1].op == "set" and aliasWrites[1].value == "",
    "shared aura-family containers should clear instead of synthesizing linked cooldown stack text")
assert(#auraQueryIDs == 1 and auraQueryIDs[1] == 99101,
    "shared aura-family containers should skip linked aura stack probes")

auraQueryIDs = {}
aliasIcon, aliasWrites = makeMacroStackProbe("aliasCooldown")
icons.OnContainerIconPlaced(aliasIcon)

assert(aliasWrites[1] and aliasWrites[1].op == "set" and aliasWrites[1].value == "5",
    "shared cooldown-family containers should still render linked aura stack probes")
assert(aliasWrites[2] and aliasWrites[2].op == "show",
    "linked aura stack probes should show stack text through the icon runtime")

local function makeSlotStackProbe()
    local writes = {}
    local probe = {
        _spellEntry = {
            type = "slot",
            kind = "cooldown",
            id = 13,
            viewerType = "aliasCooldown",
            name = "Slot Item",
        },
        Icon = {
            SetTexture = noop,
            SetDesaturated = noop,
            SetDesaturation = noop,
            SetVertexColor = noop,
        },
        Cooldown = {
            SetDrawSwipe = noop,
            SetDrawBling = noop,
            SetDrawEdge = noop,
            SetSwipeColor = noop,
            SetHideCountdownNumbers = noop,
            SetReverse = noop,
            Clear = noop,
            Show = noop,
        },
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
            SetTextColor = noop,
        },
        IsShown = function()
            return true
        end,
        Show = noop,
        Hide = noop,
        SetAlpha = noop,
    }
    return probe, writes
end

local priorResolveCooldownState = ns.CDMResolvers.ResolveCooldownState
local priorQueryInventoryItemID = ns.CDMSources.QueryInventoryItemID
local priorQueryItemInfoInstant = ns.CDMSources.QueryItemInfoInstant
local priorQueryItemIconByID = ns.CDMSources.QueryItemIconByID
local priorQueryItemSpell = ns.CDMSources.QueryItemSpell
local priorQueryAuraApplicationDisplayCount = ns.CDMSources.QueryAuraApplicationDisplayCount
local priorQuerySpellCount = ns.CDMSources.QuerySpellCount

local slotAuraDisplayText = ""
local slotAuraDisplayQuery
local slotSpellCountQueried = false
ns.CDMResolvers.ResolveCooldownState = function(context)
    if context and context.entry and context.entry.type == "slot" then
        return {
            mode = "aura",
            active = true,
            isActive = true,
            auraResolved = true,
            auraActive = true,
            auraIsActive = true,
            auraUnit = "player",
            auraInstanceID = 4242,
            resolvedAuraSpellID = 439530,
            spellID = 1259633,
        }
    end
    return priorResolveCooldownState(context)
end
ns.CDMSources.QueryInventoryItemID = function(unit, slotID)
    if unit == "player" and slotID == 13 then
        return 2001
    end
    return priorQueryInventoryItemID and priorQueryInventoryItemID(unit, slotID) or nil
end
ns.CDMSources.QueryItemInfoInstant = function(itemID)
    if itemID == 2001 then
        return itemID, nil, nil, nil, "slot-texture"
    end
    return priorQueryItemInfoInstant and priorQueryItemInfoInstant(itemID) or nil
end
ns.CDMSources.QueryItemIconByID = function(itemID)
    if itemID == 2001 then
        return "slot-texture"
    end
    return priorQueryItemIconByID and priorQueryItemIconByID(itemID) or nil
end
ns.CDMSources.QueryItemSpell = function(itemID)
    if itemID == 2001 then
        return "Use Slot Item", 1259633
    end
    return priorQueryItemSpell and priorQueryItemSpell(itemID) or nil
end
ns.CDMSources.QueryAuraApplicationDisplayCount = function(unit, auraInstanceID, minApplications, maxApplications)
    if unit == "player" and auraInstanceID == 4242 then
        slotAuraDisplayQuery = {
            unit = unit,
            auraInstanceID = auraInstanceID,
            minApplications = minApplications,
            maxApplications = maxApplications,
        }
        return slotAuraDisplayText
    end
    return priorQueryAuraApplicationDisplayCount
        and priorQueryAuraApplicationDisplayCount(unit, auraInstanceID, minApplications, maxApplications)
        or nil
end
ns.CDMSources.QuerySpellCount = function(spellID, icon)
    if spellID == 13 then
        slotSpellCountQueried = true
        return 9
    end
    return priorQuerySpellCount and priorQuerySpellCount(spellID, icon) or nil
end

local slotIcon, slotWrites = makeSlotStackProbe()
icons.OnContainerIconPlaced(slotIcon)

assert(slotAuraDisplayQuery
    and slotAuraDisplayQuery.unit == "player"
    and slotAuraDisplayQuery.auraInstanceID == 4242
    and slotAuraDisplayQuery.minApplications == 2
    and slotAuraDisplayQuery.maxApplications == 99,
    "slot aura stack text should query the active aura instance display count")
assert(slotSpellCountQueried == false,
    "slot aura stack text must not treat the equipment slot number as a spell count source")
assert(slotWrites[#slotWrites] and slotWrites[#slotWrites].op == "hide",
    "slot auras with no displayable applications should keep stack text hidden")

slotAuraDisplayText = "3"
slotAuraDisplayQuery = nil
slotSpellCountQueried = false
slotIcon, slotWrites = makeSlotStackProbe()
icons.OnContainerIconPlaced(slotIcon)

assert(slotAuraDisplayQuery and slotAuraDisplayQuery.auraInstanceID == 4242,
    "stacking slot auras should query the active item aura instance")
assert(slotSpellCountQueried == false,
    "stacking slot auras should not use the slot ID spell-count fallback")
assert(slotWrites[#slotWrites - 1] and slotWrites[#slotWrites - 1].op == "set"
    and slotWrites[#slotWrites - 1].value == "3",
    "stacking slot auras should render the active aura application display text")
assert(slotWrites[#slotWrites] and slotWrites[#slotWrites].op == "show",
    "stacking slot auras should show stack text when the active aura has applications")

ns.CDMResolvers.ResolveCooldownState = priorResolveCooldownState
ns.CDMSources.QueryInventoryItemID = priorQueryInventoryItemID
ns.CDMSources.QueryItemInfoInstant = priorQueryItemInfoInstant
ns.CDMSources.QueryItemIconByID = priorQueryItemIconByID
ns.CDMSources.QueryItemSpell = priorQueryItemSpell
ns.CDMSources.QueryAuraApplicationDisplayCount = priorQueryAuraApplicationDisplayCount
ns.CDMSources.QuerySpellCount = priorQuerySpellCount

local itemCounts = {
    [1001] = 1,
    [1002] = 0,
}
local itemUseCounts = {}
local itemTextures = {
    [1001] = "rank-1-texture",
    [1002] = "rank-2-texture",
}
C_TradeSkillUI = {
    GetItemReagentQualityInfo = function(itemID)
        if itemID == 1001 then return { iconInventory = "rank-1-atlas" } end
        if itemID == 1002 then return { iconInventory = "rank-2-atlas" } end
        return nil
    end,
    GetItemCraftedQualityInfo = function()
        return nil
    end,
}
ns.CDMSources.QueryBestOwnedItemVariant = function(itemID)
    if itemID == 1001 or itemID == 1002 then
        return itemCounts[1002] > 0 and 1002 or 1001
    end
    return itemID
end
ns.CDMSources.QueryItemInfoInstant = function(itemID)
    return itemID, nil, nil, nil, itemTextures[itemID]
end
ns.CDMSources.QueryItemIconByID = function(itemID)
    return itemTextures[itemID]
end
ns.CDMSources.QueryItemCount = function(itemID, _, includeUses)
    if includeUses then
        return itemUseCounts[itemID]
    end
    return itemCounts[itemID] or 0
end
ns.CDMSources.QueryItemNameByID = function(itemID)
    return "Rank " .. tostring(itemID)
end

local textureWrites = {}
local overlayState = {}
local textOverlay
local function CreateQualityTexture(parent)
    return {
        SetPoint = noop,
        GetParent = function()
            return parent
        end,
        SetDrawLayer = function(_, layerName, layerSublevel)
            overlayState.drawLayer = layerName
            overlayState.drawSublevel = layerSublevel
        end,
        SetAtlas = function(_, atlas)
            overlayState.atlas = atlas
        end,
        Show = function()
            overlayState.shown = true
        end,
        Hide = function()
            overlayState.shown = false
        end,
    }
end
textOverlay = {
    CreateTexture = function(_, name, layer, template, sublevel)
        overlayState.createParent = "TextOverlay"
        overlayState.createName = name
        overlayState.createLayer = layer
        overlayState.createTemplate = template
        overlayState.createSublevel = sublevel
        return CreateQualityTexture(textOverlay)
    end,
}
local itemIcon
itemIcon = {
    _spellEntry = {
        type = "item",
        id = 1001,
        itemID = 1001,
        kind = "cooldown",
        viewerType = "variantItem",
    },
    Icon = {
        SetTexture = function(_, texture)
            textureWrites[#textureWrites + 1] = texture
        end,
        SetDesaturated = noop,
        SetVertexColor = noop,
    },
    Cooldown = {
        Clear = noop,
        SetDrawSwipe = noop,
        SetDrawBling = noop,
        SetHideCountdownNumbers = noop,
        SetReverse = noop,
        SetSwipeColor = noop,
        Show = noop,
    },
    TextOverlay = textOverlay,
    StackText = (function()
        local s = { _shown = false, _text = nil }
        s.SetText = function(_, text) s._text = text end
        s.SetTextColor = noop
        s.Hide = function() s._shown = false end
        s.Show = function() s._shown = true end
        return s
    end)(),
    CreateTexture = function(_, name, layer, template, sublevel)
        overlayState.createParent = "Icon"
        overlayState.createName = name
        overlayState.createLayer = layer
        overlayState.createTemplate = template
        overlayState.createSublevel = sublevel
        return CreateQualityTexture(itemIcon)
    end,
    IsShown = function()
        return true
    end,
    Show = noop,
    Hide = noop,
    SetAlpha = noop,
}

ns.CDMIconFactory._iconPools.variantItem = { itemIcon }
itemIcon._lastTexture = "rank-1-texture"
icons.OnFactoryIconCreated(itemIcon, itemIcon._spellEntry)
assert(overlayState.atlas == "rank-1-atlas",
    "initial item icon should show the currently-owned lower-rank quality atlas")
assert(overlayState.createParent == "TextOverlay",
    "profession quality overlay should be parented to the CDM text overlay")
assert(overlayState.createLayer == "ARTWORK" and overlayState.createSublevel == 1,
    "profession quality overlay should use a lower text-overlay draw layer")
assert(overlayState.drawLayer == "ARTWORK" and overlayState.drawSublevel == 1,
    "profession quality overlay should stay below OVERLAY text layers")

itemCounts[1001] = 0
itemCounts[1002] = 3
icons.HandleRuntimeRefresh("BAG_UPDATE_DELAYED")

assert(textureWrites[#textureWrites] == "rank-2-texture",
    "bag update should refresh a placed item icon to the newly best-owned variant texture")
assert(overlayState.atlas == "rank-2-atlas",
    "bag update should refresh a placed item icon to the newly best-owned variant quality atlas")

-- Item entries' bag-count badge must survive the entry.type=="spell"
-- harvested-stack-nil fallback below the item branch. Regression guard:
-- before the fix, that fallback clobbered the count immediately after the
-- item branch set it, leaving the badge hidden for every item icon.
itemCounts[1002] = 7
icons.HandleRuntimeRefresh("BAG_UPDATE_DELAYED")
assert(itemIcon.StackText._shown == true,
    "item icon stack text should remain shown after the full UpdateIconCooldown pass")
assert(itemIcon.StackText._text == "7",
    "item icon stack text should reflect the bag count, not be hidden by the spell-only stack fallback")

trackerDB.variantItem = { showItemCharges = true }
itemCounts[1002] = 1
itemUseCounts[1002] = 0
icons.HandleRuntimeRefresh("BAG_UPDATE_DELAYED")
assert(itemIcon.StackText._shown == false,
    "item use count zero on an owned non-charge item should hide the stack text")
assert(itemIcon.StackText._text == "",
    "item use count zero on an owned non-charge item should clear stale item-count text")

itemUseCounts[1002] = 4
icons.HandleRuntimeRefresh("BAG_UPDATE_DELAYED")
assert(itemIcon.StackText._shown == true,
    "items with actual use charges should still show the item charge count")
assert(itemIcon.StackText._text == "4",
    "items with actual use charges should display their use charge count")
trackerDB.variantItem = nil

print("OK: cdm_icons_stack_resolution_test")
