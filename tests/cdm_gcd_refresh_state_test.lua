-- tests/cdm_gcd_refresh_state_test.lua
-- Run: lua tests/cdm_gcd_refresh_state_test.lua

local function noop() end

local frameScripts = {}
local subscriptions = {}
local currentOnGCD = false
local gcdQueryable = false
local gcdDuration = { token = "gcd-duration" }

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
        SetScript = function(_, scriptName, handler)
            frameScripts[scriptName] = handler
        end,
    }
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local function makeIcon(spellID)
    local icon = { vertexColors = {} }
    icon.Cooldown = {
        SetCooldownFromDurationObject = function() return true end,
        SetReverse = noop,
        SetSwipeTexture = noop,
        SetDrawSwipe = noop,
        SetDrawEdge = noop,
        SetSwipeColor = noop,
        SetHideCountdownNumbers = noop,
        Show = noop,
        Clear = noop,
    }
    icon.Icon = {
        SetDesaturated = noop,
        SetVertexColor = function(_, r, g, b, a)
            icon.vertexColors[#icon.vertexColors + 1] = { r, g, b, a }
        end,
    }
    icon._spellEntry = {
        id = spellID,
        spellID = spellID,
        overrideSpellID = spellID,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    }
    function icon:IsShown() return self._shown ~= false end
    function icon:Show() self._shown = true end
    function icon:Hide() self._shown = false end
    function icon:SetAlpha(value) self._alpha = value end
    return icon
end

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    essential = {
                        desaturateOnCooldown = true,
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
                    essential = {
                        iconDisplayMode = "always",
                    },
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
            if spellID == 11111 then
                return false, false
            end
            return true, false
        end,
    },
    CDMResolvers = {
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = function(eventName, handler)
            subscriptions[eventName] = handler
        end,
        QueryCharges = function() return nil end,
        QueryCooldown = function()
            return { isActive = currentOnGCD, isOnGCD = currentOnGCD }
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
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
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
            if not gcdQueryable then
                return nil, "inactive", nil
            end
            local sid = icon and icon._spellEntry and icon._spellEntry.spellID
            return gcdDuration, "gcd-only", sid, nil, nil, sid
        end,
    },
    CDMIconFactory = {
        _iconPools = {},
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
icons:EnsurePool("essential")
local pool = icons:GetIconPool("essential")
local first = makeIcon(11111)
local second = makeIcon(22222)
pool[#pool + 1] = first
pool[#pool + 1] = second

first._isOnGCD = true
second._isOnGCD = true
first._showingGCDSwipe = true
second._showingGCDSwipe = true

currentOnGCD = false
gcdQueryable = false
icons.EventFrameOnEvent({}, "SPELL_UPDATE_USABLE")

assert(first._isOnGCD == false, "SPELL_UPDATE_USABLE should clear stale trusted GCD state for first icon")
assert(second._isOnGCD == false, "SPELL_UPDATE_USABLE should clear stale trusted GCD state for second icon")
assert(first._usabilityTinted == true, "SPELL_UPDATE_USABLE should immediately apply unusable tint after cooldown suppression")
local firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 0.4 and firstColor[2] == 0.4 and firstColor[3] == 0.4 and firstColor[4] == 1,
    "SPELL_UPDATE_USABLE should darken unusable icons without waiting for the range poll")

currentOnGCD = true
gcdQueryable = true
local cooldownChanged = assert(subscriptions["CDM:COOLDOWN_CHANGED"], "cooldown subscriber should be registered")
cooldownChanged("CDM:COOLDOWN_CHANGED", 11111, nil, "refresh")

assert(first._showingGCDSwipe == true, "per-spell GCD refresh should mark the cast spell")
assert(second._showingGCDSwipe == true, "per-spell GCD refresh should broaden when GCD state changed")

print("OK: cdm_gcd_refresh_state_test")
