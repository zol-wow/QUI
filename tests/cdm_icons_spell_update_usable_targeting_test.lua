-- tests/cdm_icons_spell_update_usable_targeting_test.lua
-- Run: lua tests/cdm_icons_spell_update_usable_targeting_test.lua

local function noop() end

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

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local resolveCounts = {}
local usableQueries = {}

local function makeIcon(name, spellID, kind)
    local icon = {
        name = name,
        _spellEntry = {
            id = spellID,
            spellID = spellID,
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
    },
    CDMResolvers = {
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        BeginRuntimeQueryBatch = noop,
        EndRuntimeQueryBatch = noop,
        QueryCharges = function() return nil end,
        QueryCooldown = function()
            return { isActive = false, isOnGCD = false }
        end,
        QueryDuration = function() return nil end,
        QueryChargeDuration = function() return nil end,
        QueryOverrideSpell = function() return nil end,
        QueryDisplayCount = function() return nil end,
        QuerySpellCount = function() return nil end,
        GetSpellTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        GetEntryTexture = function() return nil end,
        HasRealCooldownState = function() return false end,
        ResolveAuraStateForIcon = function() return nil end,
        ResolveAuraDurationObjectForIcon = function() return nil end,
        IsAuraEntry = function(entry)
            return entry and entry.kind == "aura"
        end,
        GetChargeMetadataDB = function() return nil end,
        IsItemLikeEntry = function() return false end,
        ResolveItemCooldownIdentity = function() return nil end,
        ResolveEntryItemID = function() return nil end,
        ClassifySpellCooldownState = function() return nil end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function()
            return {
                isOnCooldown = false,
                rechargeActive = false,
                hasChargesRemaining = false,
                hasCharges = false,
            }
        end,
        ResolveIconDurationObject = function(icon)
            resolveCounts[icon.name] = (resolveCounts[icon.name] or 0) + 1
            return nil, "inactive", nil
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
        UpdateIconCooldown = noop,
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

assert(loadfile("modules/cdm/cdm_icons.lua"))("QUI", ns)

local icons = assert(ns.CDMIcons, "CDMIcons should be exported")
icons.EventFrameOnEvent({}, "SPELL_UPDATE_USABLE")

assert(resolveCounts.stale == 1, "stale cooldown icon should be re-resolved on SPELL_UPDATE_USABLE")
assert(resolveCounts.idle == nil, "idle icons should not be re-resolved on SPELL_UPDATE_USABLE")
assert(resolveCounts.aura == nil, "aura icons should not be re-resolved on SPELL_UPDATE_USABLE")
assert(usableQueries[88104] == nil, "aura icons should not run usability checks on SPELL_UPDATE_USABLE")

print("OK: cdm_icons_spell_update_usable_targeting_test")
