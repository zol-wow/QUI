-- tests/cdm_icons_stack_resolution_test.lua
-- Run: lua tests/cdm_icons_stack_resolution_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end
local secretStackText = { token = "secret-stack-text" }

function issecretvalue(value)
    return value == secretStackText
end

function InCombatLockdown() return false end
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

local queriedMinApplications
local lastCooldownStateContext

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function()
                return {}
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
        end,
    },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_icons.lua"))("QUI", ns)

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
            Hide = function()
                stackWrites[#stackWrites + 1] = { op = "hide" }
            end,
        },
    }
    return icon, stackWrites
end

local icon, stackWrites = makeMirrorStackProbe(73542)
icons.OnFactoryMirrorBound(icon, 73542, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "6",
    "cooldown icons should render Blizzard mirror application text")
assert(stackWrites[2].op == "show",
    "cooldown icons should show Blizzard mirror application text")

icon, stackWrites = makeMirrorStackProbe(73544)
icons.OnFactoryMirrorBound(icon, 73544, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == "7",
    "cooldown icons should mirror Blizzard's cached cast count field")
assert(stackWrites[2].op == "show",
    "cached cast count should remain visible")

icon, stackWrites = makeMirrorStackProbe(73545)
icons.OnFactoryMirrorBound(icon, 73545, "essential")

assert(stackWrites[1].op == "set" and stackWrites[1].value == secretStackText,
    "secret mirror stack text should be forwarded unchanged")
assert(stackWrites[2].op == "show",
    "secret mirror stack text should show the FontString")

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
    "mirror-backed non-charge cooldown icons should not synthesize spell cast count as stack text")
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

local itemCounts = {
    [1001] = 1,
    [1002] = 0,
}
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
ns.CDMSources.QueryItemCount = function(itemID)
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
local itemIcon = {
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
    StackText = {
        SetText = noop,
        SetTextColor = noop,
        Hide = noop,
        Show = noop,
    },
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

print("OK: cdm_icons_stack_resolution_test")
