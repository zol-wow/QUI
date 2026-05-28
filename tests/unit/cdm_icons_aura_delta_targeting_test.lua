-- tests/unit/cdm_icons_aura_delta_targeting_test.lua
-- Run: lua tests/unit/cdm_icons_aura_delta_targeting_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame C_Timer

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

local inCombat = false
function InCombatLockdown() return inCombat end
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

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local resolveCounts = {}
local layoutRequests = 0
local subscriptions = {}
local buffContainerShows = 0
local itemAuraDur = { token = "item-aura-duration" }
local itemAuraAppliedDuration
local itemAuraReverse
local itemAuraApplyCount = 0
local mirroredBuffTargetDur = { token = "mirrored-buff-target-duration" }
local mirroredBuffPlayerDur = { token = "mirrored-buff-player-duration" }
local mirroredBuffAppliedDuration
local mirroredBuffReverse
local runtimeBatches = 0
local buffAuraResolutionUnit = "player"
local buffAuraResolutionInstanceID = 621

local function makeIcon(name, cooldownID)
    local icon = {
        name = name,
        _spellEntry = {
            id = cooldownID,
            spellID = cooldownID,
            name = name,
            viewerType = "essential",
            type = "spell",
        },
        _blizzMirrorCooldownID = cooldownID,
        _blizzMirrorCategory = "essential",
        Cooldown = {
            Clear = noop,
            SetReverse = noop,
        },
        Icon = {
            SetDesaturated = noop,
            SetAlpha = noop,
            SetTexture = noop,
        },
        Border = { SetAlpha = noop },
        DurationText = { SetAlpha = noop },
        StackText = { SetAlpha = noop },
    }
    function icon:IsShown() return self._shown ~= false end
    function icon:Show() self._shown = true end
    function icon:Hide() self._shown = false end
    function icon:SetAlpha(value) self._alpha = value end
    return icon
end

local matchingIcon = makeIcon("matching", 88001)
local unrelatedIcon = makeIcon("unrelated", 88002)
local nonMirrorIcon = makeIcon("nonMirror", 88003)
nonMirrorIcon._blizzMirrorCooldownID = nil
local buffAuraIcon = makeIcon("buffAura", 48707)
buffAuraIcon._spellEntry = {
    id = 48707,
    spellID = 48707,
    name = "buffAura",
    kind = "aura",
    viewerType = "buff",
    type = "spell",
}
buffAuraIcon._blizzMirrorCooldownID = nil
buffAuraIcon._shown = false
local mirroredBuffAuraIcon = makeIcon("mirroredBuffAura", 191587)
mirroredBuffAuraIcon._spellEntry = {
    id = 191587,
    spellID = 191587,
    name = "mirroredBuffAura",
    kind = "aura",
    viewerType = "buff",
    type = "spell",
}
mirroredBuffAuraIcon._blizzMirrorCooldownID = 102373
mirroredBuffAuraIcon._blizzMirrorCategory = "buff"
mirroredBuffAuraIcon._shown = false
mirroredBuffAuraIcon.Cooldown.SetCooldownFromDurationObject = function(_, durObj)
    mirroredBuffAppliedDuration = durObj
end
mirroredBuffAuraIcon.Cooldown.SetReverse = function(_, reverse)
    mirroredBuffReverse = reverse
end
local itemAuraIcon = makeIcon("itemAura", 241288)
itemAuraIcon._spellEntry = {
    id = 241288,
    itemID = 241288,
    name = "itemAura",
    kind = "cooldown",
    viewerType = "essential",
    type = "item",
}
itemAuraIcon._runtimeSpellID = 241288
itemAuraIcon._blizzMirrorCooldownID = nil
itemAuraIcon.Cooldown.SetCooldownFromDurationObject = function(_, durObj)
    itemAuraApplyCount = itemAuraApplyCount + 1
    itemAuraAppliedDuration = durObj
end
itemAuraIcon.Cooldown.SetReverse = function(_, reverse)
    itemAuraReverse = reverse
end

local mirrorStates = {
    [88001] = {
        auraInstanceID = 101,
        auraUnit = "target",
        isActive = true,
    },
    [88002] = {
        auraInstanceID = 202,
        auraUnit = "target",
        isActive = true,
    },
    [102373] = {
        cooldownID = 102373,
        viewerCategory = "buff",
        spellID = 77575,
        overrideTooltipSpellID = 191587,
        auraInstanceID = 344,
        auraUnit = "target",
        auraDurObj = mirroredBuffTargetDur,
        auraDurObjSource = "aura-child-frame",
        mirrorEpoch = 1,
    },
}

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    essential = {
                        iconDisplayMode = "always",
                        rangeIndicator = false,
                        usabilityIndicator = false,
                    },
                    buff = {
                        iconDisplayMode = "active",
                        rangeIndicator = false,
                        usabilityIndicator = false,
                    },
                }
            end
        end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        SafeToNumber = function(value) return value end,
        CanAccessTable = function(tbl) return type(tbl) == "table" end,
        IsEditModeActive = function() return false end,
        IsLayoutModeActive = function() return false end,
    },
    Addon = {
        db = {
            profile = {
                ncdm = {
                    essential = { iconDisplayMode = "always" },
                    buff = { iconDisplayMode = "active" },
                    containers = {},
                },
            },
            char = { ncdm = {} },
        },
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        IsSafeNumeric = function(value) return type(value) == "number" end,
    },
    CDMSources = {
        QuerySpellUsable = function() return true, false end,
        QuerySpellHasRange = function() return false end,
        QuerySpellInRange = function() return true end,
        QueryItemSpell = function(itemID)
            if itemID == 241288 then
                return "Potion Use", 1236994
            end
            return nil, nil
        end,
        QueryCooldownAuraBySpellID = function(spellID)
            if spellID == 1236994 then
                return 555001
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID)
            return mirrorStates[cooldownID]
        end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = function(eventName, handler)
            subscriptions[eventName] = handler
        end,
        GetSpellTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        GetEntryTexture = function() return nil end,
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function()
            return {
                isOnCooldown = false,
                rechargeActive = false,
                hasChargesRemaining = false,
                hasCharges = false,
            }
        end,
        ResolveCooldownState = function(context)
            local entry = context and context.entry
            local name = entry and entry.name
            if name then
                resolveCounts[name] = (resolveCounts[name] or 0) + 1
            end
            if name == "buffAura" then
                return {
                    mode = "aura",
                    active = true,
                    isActive = true,
                    sourceID = "aura:direct:48707",
                    spellID = 48707,
                    auraResolved = true,
                    auraInstanceID = buffAuraResolutionInstanceID,
                    auraUnit = buffAuraResolutionUnit,
                    resolvedAuraSpellID = 48707,
                }
            end
            if name == "mirroredBuffAura" then
                return {
                    mode = "aura",
                    active = true,
                    isActive = true,
                    sourceID = "aura:direct:191587",
                    spellID = 191587,
                    auraResolved = true,
                    auraInstanceID = 444,
                    auraUnit = "player",
                    resolvedAuraSpellID = 77575,
                    durObj = mirroredBuffPlayerDur,
                    hasDurationObject = true,
                    hasRenderableCooldown = true,
                }
            end
            if name == "itemAura" then
                return {
                    mode = "aura",
                    active = true,
                    isActive = true,
                    durObj = itemAuraDur,
                    sourceID = "item-aura-instance:241288",
                    spellID = 1236994,
                    auraResolved = true,
                    auraActive = true,
                    auraIsActive = true,
                    auraInstanceID = 622,
                    auraUnit = "player",
                    resolvedAuraSpellID = 555001,
                    isOnCooldown = false,
                    hasDurationObject = true,
                    hasRenderableCooldown = true,
                }
            end
            return {
                mode = "inactive",
                active = false,
                isActive = false,
            }
        end,
    },
    CDMIconFactory = {
        _iconPools = {
            essential = { matchingIcon, unrelatedIcon, nonMirrorIcon, itemAuraIcon },
            buff = { buffAuraIcon, mirroredBuffAuraIcon },
        },
        _recyclePool = {},
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
        SyncCooldownBling = noop,
    },
    CDMRuntimeStore = {
        SetIconState = noop,
    },
    CDMBuffLayout = {
        OnLayoutReady = function()
            layoutRequests = layoutRequests + 1
        end,
    },
    CDMContainers = {
        GetContainer = function(viewerType)
            if viewerType ~= "buff" then return nil end
            return {
                Show = function()
                    buffContainerShows = buffContainerShows + 1
                end,
            }
        end,
    },
    _OwnedSwipe = {
        ApplyToIcon = noop,
        GetSettings = function()
            return {
                showGCDSwipe = true,
                showCooldownSwipe = true,
            }
        end,
    },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
do
    local runtime = assert(ns.CDMRuntimeQueries, "runtime query module should be loaded")
    local originalBegin = runtime.BeginRuntimeQueryBatch
    runtime.BeginRuntimeQueryBatch = function(...)
        runtimeBatches = runtimeBatches + 1
        return originalBegin(...)
    end
end
assert(loadfile("modules/cdm/cdm_icon_renderer.lua"))("QUI", ns)
ns.CDMIconFactory._iconPools.essential = { matchingIcon, unrelatedIcon, nonMirrorIcon, itemAuraIcon }
ns.CDMIconFactory._iconPools.buff = { buffAuraIcon, mirroredBuffAuraIcon }

local icons = assert(ns.CDMIcons, "CDMIcons should be exported")
runtimeBatches = 0
icons.HandleRuntimeRefresh("UNIT_AURA", "target", {
    updatedAuraInstanceIDs = { 999 },
})
assert(runtimeBatches == 0, "unmatched aura deltas should not open a runtime query batch")

icons.HandleRuntimeRefresh("UNIT_AURA", "target", {
    updatedAuraInstanceIDs = { 101 },
})

assert(resolveCounts.matching == 1, "matching aura-instance icon should be re-resolved")
assert(resolveCounts.unrelated == nil, "unrelated mirror aura instance should not be re-resolved")
assert(resolveCounts.nonMirror == nil, "non-mirror icons should not be reached by a target aura-instance delta")

icons.HandleRuntimeRefresh("UNIT_AURA", "target", {
    updatedAuraInstanceIDs = { 344 },
})

assert(mirroredBuffAuraIcon._auraUnit == "target",
    "mirrored buff aura refresh should keep the exact target aura unit")
assert(mirroredBuffAuraIcon._auraInstanceID == 344,
    "mirrored buff aura refresh should keep the exact target aura instance")
assert(mirroredBuffAuraIcon._lastAuraDurObj == mirroredBuffTargetDur,
    "mirrored buff aura refresh should keep the mirror target DurationObject")
assert(mirroredBuffAppliedDuration == mirroredBuffTargetDur,
    "mirrored buff aura refresh should bind the mirror target DurationObject")
assert(mirroredBuffReverse == true,
    "mirrored buff aura refresh should use aura/reverse cooldown mode")

icons.HandleRuntimeRefresh("UNIT_AURA", "player", {
    isFullUpdate = false,
    addedAuras = {
        { spellId = 48707, auraInstanceID = 621 },
    },
})

assert(resolveCounts.buffAura == 1, "added player aura should re-resolve matching buff aura icon by spell ID")
assert(buffAuraIcon._shown == true, "active buff aura icon should be shown by the aura-delta visibility path")
assert(layoutRequests > 0, "buff aura visibility flips should request buff icon layout")
assert(buffContainerShows > 0, "buff aura visibility flips should wake the owning buff container")

buffAuraIcon._shown = false
buffAuraIcon._auraActive = false
layoutRequests = 0
resolveCounts.buffAura = 0
buffContainerShows = 0

local nameAccessTrapAura = setmetatable({
    spellId = 145629,
    auraInstanceID = 623,
}, {
    __index = function(_, key)
        if key == "name" then
            error("auraData.name must not be read while targeting aura deltas", 2)
        end
    end,
})

local ok, err = pcall(function()
    icons.HandleRuntimeRefresh("UNIT_AURA", "player", {
        isFullUpdate = false,
        addedAuras = {
            nameAccessTrapAura,
        },
    })
end)

assert(ok, "player aura delta targeting should not read auraData.name: " .. tostring(err))
assert(resolveCounts.buffAura == 1,
    "added player aura should wake buff aura icons for resolver recheck when spell ID differs")
assert(buffAuraIcon._shown == true,
    "player aura wake-up should re-show a hidden active-only buff aura icon")
assert(layoutRequests > 0,
    "player aura wake-up should request buff icon layout after visibility flips")
assert(buffContainerShows > 0,
    "player aura wake-up should wake the owning buff container")

buffAuraIcon._shown = false
buffAuraIcon._auraActive = false
buffAuraIcon._auraUnit = nil
buffAuraIcon._auraInstanceID = nil
layoutRequests = 0
resolveCounts.buffAura = 0
buffContainerShows = 0
buffAuraResolutionUnit = "target"
buffAuraResolutionInstanceID = 9052

icons.HandleRuntimeRefresh("UNIT_AURA", "target", {
    isFullUpdate = false,
    addedAuras = {
        { auraInstanceID = 9052 },
    },
})

assert(resolveCounts.buffAura == 1,
    "target added aura payloads without a readable spell ID should wake buff aura icons")
assert(buffAuraIcon._shown == true,
    "target aura wake-up should re-show hidden active-only buff aura icons")
assert(buffAuraIcon._auraUnit == "target",
    "target aura wake-up should preserve the resolver's target unit")
assert(buffAuraIcon._auraInstanceID == 9052,
    "target aura wake-up should preserve the resolver's target aura instance")
assert(layoutRequests > 0,
    "target aura wake-up should request buff icon layout after visibility flips")
assert(buffContainerShows > 0,
    "target aura wake-up should wake the owning buff container")

buffAuraResolutionUnit = "player"
buffAuraResolutionInstanceID = 621

icons.HandleRuntimeRefresh("UNIT_AURA", "player", {
    isFullUpdate = false,
    addedAuras = {
        { spellId = 555001, auraInstanceID = 622 },
    },
})

assert(resolveCounts.itemAura == 1,
    "added player aura should re-resolve matching item icon through item use aura mapping")
assert(itemAuraIcon._auraActive == true,
    "added player item aura should stamp active aura metadata on the item icon")
assert(itemAuraAppliedDuration == itemAuraDur,
    "added player item aura should bind the aura DurationObject to the item icon")
assert(itemAuraReverse == true,
    "added player item aura should use aura/reverse cooldown mode")
assert(itemAuraApplyCount == 1,
    "initial item aura apply should bind the aura DurationObject once")

inCombat = true
icons.HandleRuntimeRefresh("UNIT_AURA", "player", {
    isFullUpdate = false,
    updatedAuraInstanceIDs = { 622 },
})
inCombat = false

assert(itemAuraApplyCount == 2,
    "combat aura refresh should rebind the DurationObject even when auraInstanceID and durObj identity are unchanged")

buffAuraIcon._shown = false
buffAuraIcon._auraActive = false
layoutRequests = 0
resolveCounts.buffAura = 0

icons.HandleRuntimeRefresh("UNIT_AURA", "player", nil)

assert(resolveCounts.buffAura == 1, "full aura refresh should re-resolve buff aura icons")
assert(buffAuraIcon._shown == true, "full aura refresh should apply buff aura visibility immediately")
assert(layoutRequests > 0, "full aura refresh active flips should request buff icon layout")

buffAuraIcon._shown = false
buffAuraIcon._auraActive = false
layoutRequests = 0
resolveCounts.buffAura = 0
buffContainerShows = 0

local cooldownChanged = assert(subscriptions["CDM:COOLDOWN_CHANGED"],
    "cooldown subscriber should be registered")
local batchesBeforeUnmatchedSpell = runtimeBatches
cooldownChanged("CDM:COOLDOWN_CHANGED", 999999, nil, "refresh")
assert(runtimeBatches == batchesBeforeUnmatchedSpell,
    "unmatched per-spell cooldown refreshes should not open a runtime query batch")

cooldownChanged("CDM:COOLDOWN_CHANGED", 48707, nil, "refresh")

assert(resolveCounts.buffAura == 1, "per-spell cooldown refresh should re-resolve matching aura icons")
assert(buffAuraIcon._shown == true,
    "per-spell cooldown refresh should apply aura visibility after resolving aura state")
assert(layoutRequests > 0,
    "per-spell cooldown refresh should request buff layout when aura state flips active")
assert(buffContainerShows > 0,
    "per-spell cooldown refresh should wake hidden active-only buff containers")

resolveCounts.itemAura = 0
itemAuraIcon._auraActive = false
itemAuraIcon._lastDurObjKey = nil
itemAuraIcon._lastDurObj = nil
itemAuraIcon._lastAuraDurObj = nil
itemAuraAppliedDuration = nil
itemAuraReverse = nil

cooldownChanged("CDM:COOLDOWN_CHANGED", 1236994, nil, "scanner_item")

assert(resolveCounts.itemAura == 1, "scanner item refresh should re-resolve item-backed icons")
assert(itemAuraIcon._auraActive == true,
    "scanner item refresh should stamp active aura metadata on the item icon")
assert(itemAuraAppliedDuration == itemAuraDur,
    "scanner item refresh should bind the aura DurationObject to the item icon")
assert(itemAuraReverse == true,
    "scanner item refresh should use aura/reverse cooldown mode")

print("OK: cdm_icons_aura_delta_targeting_test")
