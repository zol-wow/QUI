-- tests/unit/cdm_icons_spell_update_usable_targeting_test.lua
-- Run: lua tests/unit/cdm_icons_spell_update_usable_targeting_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

local inCombat = false
local createdFrames = {}

function InCombatLockdown() return inCombat end
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
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local resolveCounts = {}
local usableQueries = {}
local runtimeBatches = 0

local function makeIcon(name, spellID, kind)
    local icon = {
        name = name,
        _spellEntry = {
            id = spellID,
            spellID = spellID,
            name = name,
            kind = kind or "cooldown",
            viewerType = "essential",
            type = "spell",
        },
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
        StackText = { SetAlpha = noop },
    }
    function icon:IsShown() return self._shown ~= false end
    function icon:Show() self._shown = true end
    function icon:Hide() self._shown = false end
    function icon:SetAlpha(value) self._alpha = value end
    return icon
end

local staleIcon = makeIcon("stale", 88101)
local idleIcon = makeIcon("idle", 88102)
local auraIcon = makeIcon("aura", 88103, "aura")
local auraVisualIcon = makeIcon("auraVisual", 88104, "aura")
staleIcon._hasCooldownActive = true
staleIcon._hasRealCooldownActive = true
staleIcon._lastDurObjKey = "cooldown:88101"
auraIcon._hasCooldownActive = true
auraIcon._hasRealCooldownActive = true
auraIcon._lastDurObjKey = "aura:88103"
auraVisualIcon._usabilityTinted = true

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
                        usabilityIndicator = true,
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
        QuerySpellUsable = function(spellID)
            usableQueries[spellID] = (usableQueries[spellID] or 0) + 1
            return true, false
        end,
        QuerySpellHasRange = function() return false end,
        QuerySpellInRange = function() return true end,
        QuerySpellCooldown = function()
            return { isActive = false, isOnGCD = false }
        end,
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
            end
            return {
                mode = "inactive",
                active = false,
                isActive = false,
                spellID = entry and entry.spellID,
            }
        end,
    },
    CDMIconFactory = {
        _iconPools = {
            essential = { staleIcon, idleIcon, auraIcon, auraVisualIcon },
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
ns.CDMIconFactory._iconPools.essential = { staleIcon, idleIcon, auraIcon, auraVisualIcon }

local icons = assert(ns.CDMIcons, "CDMIcons should be exported")
icons.HandleRuntimeRefresh("SPELL_UPDATE_USABLE")

assert(resolveCounts.stale == 1, "stale cooldown icon should be re-resolved on SPELL_UPDATE_USABLE")
assert(resolveCounts.idle == nil, "idle icons should not be re-resolved on SPELL_UPDATE_USABLE")
assert(resolveCounts.aura == nil, "aura icons should not be re-resolved on SPELL_UPDATE_USABLE")
assert(usableQueries[88104] == nil, "aura icons should not run usability checks on SPELL_UPDATE_USABLE")

staleIcon._hasCooldownActive = nil
staleIcon._hasRealCooldownActive = nil
staleIcon._lastDurObjKey = nil
staleIcon._showingRealCooldownSwipe = nil
staleIcon._showingGCDSwipe = nil
staleIcon._cooldownExpiryTimerKey = nil
staleIcon._cdDesaturated = nil
local batchesBeforeIdleUsable = runtimeBatches
icons.HandleRuntimeRefresh("SPELL_UPDATE_USABLE")
assert(runtimeBatches == batchesBeforeIdleUsable,
    "SPELL_UPDATE_USABLE with no stale cooldown icons should not open a runtime query batch")

staleIcon._hasCooldownActive = true
staleIcon._hasRealCooldownActive = true
staleIcon._lastDurObjKey = "cooldown:88101"
resolveCounts.stale = nil
inCombat = true
local batchesBeforeCombatUsable = runtimeBatches
icons.HandleRuntimeRefresh("SPELL_UPDATE_USABLE")
icons.HandleRuntimeRefresh("SPELL_UPDATE_USABLE")
assert(resolveCounts.stale == nil,
    "combat SPELL_UPDATE_USABLE should defer stale cooldown resolution until the coalesced tick")
assert(runtimeBatches == batchesBeforeCombatUsable,
    "queued combat SPELL_UPDATE_USABLE should not open a runtime query batch immediately")

local usabilityFrame
for _, frame in ipairs(createdFrames) do
    if frame.scripts.OnUpdate then
        usabilityFrame = frame
    end
end
assert(usabilityFrame and usabilityFrame.shown == true,
    "combat SPELL_UPDATE_USABLE should arm a reusable coalescing frame")
usabilityFrame.scripts.OnUpdate(usabilityFrame, 0.29)
assert(resolveCounts.stale == nil,
    "combat SPELL_UPDATE_USABLE should wait for its coalescing interval")
usabilityFrame.scripts.OnUpdate(usabilityFrame, 0.02)
assert(resolveCounts.stale == 1,
    "coalesced combat SPELL_UPDATE_USABLE should re-resolve stale cooldown icons once")
assert(usabilityFrame.shown == false,
    "coalesced combat SPELL_UPDATE_USABLE should hide the reusable frame after draining")
inCombat = false

print("OK: cdm_icons_spell_update_usable_targeting_test")
