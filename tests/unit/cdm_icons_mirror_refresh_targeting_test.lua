-- tests/unit/cdm_icons_mirror_refresh_targeting_test.lua
-- Run: lua tests/unit/cdm_icons_mirror_refresh_targeting_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

local inCombat = false
local createdFrames = {}
local timerAfterCalls = 0

function InCombatLockdown() return inCombat end
function UnitAffectingCombat() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function CreateFrame()
    local frame = {
        scripts = {},
        shown = false,
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = function(self, scriptName, handler)
            self.scripts[scriptName] = handler
        end,
        Show = function(self)
            self.shown = true
        end,
        Hide = function(self)
            self.shown = false
        end,
    }
    createdFrames[#createdFrames + 1] = frame
    return frame
end

C_Timer = {
    After = function(_, callback)
        timerAfterCalls = timerAfterCalls + 1
        callback()
    end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local resolveCounts = {}
local cachedStates = {}
local cachedSourceIDs = {}
local runtimeBatches = 0
local mirrorLookupCounts = {}
local mirrorStates = {
    ["essential:88001"] = {
        cooldownID = 88001,
        viewerCategory = "essential",
        mirrorEpoch = 1,
    },
}

local function makeIcon(name, cooldownID, category)
    local icon = {
        name = name,
        _spellEntry = {
            id = cooldownID,
            spellID = cooldownID,
            name = name,
            kind = "cooldown",
            viewerType = category,
            type = "spell",
        },
        _blizzMirrorCooldownID = cooldownID,
        _blizzMirrorCategory = category,
        Cooldown = {
            Clear = noop,
            SetReverse = noop,
            SetCooldownFromDurationObject = noop,
        },
        Icon = {
            SetDesaturated = noop,
            SetAlpha = noop,
            SetTexture = noop,
            SetVertexColor = noop,
        },
        Border = { SetAlpha = noop },
        DurationText = { SetAlpha = noop },
        StackText = {
            SetAlpha = noop,
            SetText = noop,
            Hide = noop,
            Show = noop,
        },
    }
    function icon:IsShown() return self._shown ~= false end
    function icon:Show() self._shown = true end
    function icon:Hide() self._shown = false end
    function icon:SetAlpha(value) self._alpha = value end
    return icon
end

local matchingIcon = makeIcon("matching", 88001, "essential")
local sameIDWrongCategoryIcon = makeIcon("sameIDWrongCategory", 88001, "buff")
local unrelatedIcon = makeIcon("unrelated", 88002, "essential")

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
                        iconDisplayMode = "always",
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
                    buff = { iconDisplayMode = "always" },
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
    },
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        GetSpellTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        GetEntryTexture = function() return nil end,
        IsAuraEntry = function(entry)
            return entry and entry.kind == "aura"
        end,
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
                cachedStates[name] = context and context.cachedMirrorState or nil
                cachedSourceIDs[name] = context and context.cachedMirrorSourceID or nil
            end
            return {
                mode = "inactive",
                active = false,
                isActive = false,
                spellID = entry and entry.spellID,
            }
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, category)
            local key = tostring(category) .. ":" .. tostring(cooldownID)
            mirrorLookupCounts[key] = (mirrorLookupCounts[key] or 0) + 1
            return mirrorStates[key]
        end,
    },
    CDMIconFactory = {
        _iconPools = {
            essential = { matchingIcon, unrelatedIcon },
            buff = { sameIDWrongCategoryIcon },
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
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)
ns.CDMIconFactory._iconPools.essential = { matchingIcon, unrelatedIcon }
ns.CDMIconFactory._iconPools.buff = { sameIDWrongCategoryIcon }

local icons = assert(ns.CDMIcons, "CDMIcons should be exported")
assert(type(icons.RebuildBlizzMirrorIconIndex) == "function",
    "icons should expose a way to rebuild the mirror icon index")
assert(type(icons.RequestMirrorTextRefresh) == "function",
    "icons should expose scoped mirror refresh requests")

icons.RebuildBlizzMirrorIconIndex()

local fullUpdates = 0
icons.UpdateAllCooldowns = function()
    fullUpdates = fullUpdates + 1
end

icons:RequestMirrorTextRefresh(99001, "essential", "unmatched-test")
assert(runtimeBatches == 0,
    "unmatched mirror refreshes should not open a runtime query batch")

icons:RequestMirrorTextRefresh(88001, "essential", "test")

assert((resolveCounts.matching or 0) >= 1,
    "matching mirror icon should be re-resolved")
assert(cachedStates.matching == mirrorStates["essential:88001"],
    "matching mirror icon should receive the mirror state cached by the targeted refresh")
assert(cachedSourceIDs.matching == "mirror:88001:1",
    "matching mirror icon should receive the cached mirror source key")
assert((mirrorLookupCounts["essential:88001"] or 0) >= 1,
    "targeted mirror refresh should fetch mirror state for the matching mirror key")
assert(resolveCounts.sameIDWrongCategory == nil,
    "same cooldownID in a different mirror category should not be re-resolved")
assert(resolveCounts.unrelated == nil,
    "unrelated mirror icons should not be reached by scoped refresh")
assert(fullUpdates == 0,
    "scoped mirror refresh must not call UpdateAllCooldowns")

local refreshedMirrorState = {
    cooldownID = 88001,
    viewerCategory = "essential",
    mirrorEpoch = 2,
    resolvedMode = "gcd-only",
    durObjSource = "gcd-duration",
}
local mirrorLookupsBeforeBroadCooldown = mirrorLookupCounts["essential:88001"] or 0
cachedStates.matching = nil
cachedSourceIDs.matching = nil
icons:UpdateCooldownOnly()
assert(cachedStates.matching == mirrorStates["essential:88001"],
    "broad cooldown refresh should reuse the icon-cached mirror state")
assert(cachedSourceIDs.matching == "mirror:88001:1",
    "broad cooldown refresh should reuse the icon-cached mirror source key")
assert((mirrorLookupCounts["essential:88001"] or 0) == mirrorLookupsBeforeBroadCooldown,
    "broad cooldown refresh should not repack mirror state while building resolver context")

icons:RequestMirrorTextRefresh(nil, nil, "unknown-test")
assert(fullUpdates == 0,
    "unknown mirror refreshes should be counted but must not schedule broad full icon walks")

local stats = icons:GetCacheStats()
assert(stats.mirrorRefreshTargeted == 1,
    "mirror refresh stats should count targeted refreshes that reached indexed icons")
assert(stats.mirrorRefreshFallback == 1,
    "mirror refresh stats should count unscoped mirror notifications skipped by the icon index")

mirrorStates["essential:88001"] = refreshedMirrorState
cachedStates.matching = nil
cachedSourceIDs.matching = nil
icons:RequestMirrorTextRefresh(88001, "essential", "updated-state-test")
assert(cachedStates.matching == refreshedMirrorState,
    "targeted mirror refresh should refresh the icon-cached mirror state")
assert(cachedSourceIDs.matching == "mirror:88001:2",
    "targeted mirror refresh should refresh the icon-cached mirror source key")

assert(type(icons.RecordEventProfile) == "function",
    "icons should expose CDM-local event profiling")
icons.RecordEventProfile("SPELL_UPDATE_USABLE", 4)
icons.RecordEventProfile("SPELL_UPDATE_USABLE", 6)
icons.RecordEventProfile("SPELL_RANGE_CHECK_UPDATE", 1)

stats = icons:GetCacheStats()
assert(type(stats.iconEventProfileTop) == "table",
    "icon cache stats should expose event-profile rows")
assert(stats.iconEventProfileTop[1].event == "SPELL_UPDATE_USABLE",
    "event profile should sort by elapsed time")
assert(stats.iconEventProfileTop[1].calls == 2,
    "event profile should report per-window call counts")
assert(stats.iconEventProfileTop[1].ms == 10,
    "event profile should report per-window elapsed time")

resolveCounts.matching = nil
inCombat = true
local timersBeforeCombatMirror = timerAfterCalls
local batchesBeforeCombatMirror = runtimeBatches
icons:RequestMirrorTextRefresh(88001, "essential", "combat-test")
assert(resolveCounts.matching == nil,
    "combat mirror refresh should defer until the coalesced frame tick")
assert(timerAfterCalls == timersBeforeCombatMirror,
    "combat mirror refresh should use the reusable frame instead of C_Timer.After")

local mirrorFrame
for _, frame in ipairs(createdFrames) do
    if frame.scripts.OnUpdate and frame.shown then
        mirrorFrame = frame
    end
end
assert(mirrorFrame, "combat mirror refresh should arm a reusable frame")
mirrorFrame.scripts.OnUpdate(mirrorFrame, 0.19)
assert(resolveCounts.matching == nil,
    "combat mirror refresh should wait for its coalescing interval")
mirrorFrame.scripts.OnUpdate(mirrorFrame, 0.02)
assert((resolveCounts.matching or 0) >= 1,
    "coalesced combat mirror refresh should re-resolve the matching icon")
assert(runtimeBatches == batchesBeforeCombatMirror + 1,
    "coalesced combat mirror refresh should open one runtime query batch")
assert(mirrorFrame.shown == false,
    "coalesced combat mirror refresh should hide the reusable frame after draining")
inCombat = false

print("OK: cdm_icons_mirror_refresh_targeting_test")
