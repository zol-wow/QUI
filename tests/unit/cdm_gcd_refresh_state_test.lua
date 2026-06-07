-- tests/unit/cdm_gcd_refresh_state_test.lua
-- Run: lua tests/unit/cdm_gcd_refresh_state_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

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
        SetCooldownFromDurationObject = function(_, durObj)
            icon.cooldownBinds = (icon.cooldownBinds or 0) + 1
            icon.lastCooldownDurObj = durObj
            return true
        end,
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
        QuerySpellCooldown = function()
            return { isActive = currentOnGCD, isOnGCD = currentOnGCD }
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
            if not gcdQueryable then
                return {
                    mode = "inactive",
                    active = false,
                    isActive = false,
                }
            end
            local entry = context and context.entry
            local sid = context and context.runtimeSpellID or entry and entry.spellID
            return {
                mode = "gcd-only",
                active = true,
                isActive = true,
                durObj = gcdDuration,
                sourceID = sid,
                spellID = sid,
            }
        end,
    },
    CDMIconFactory = {
        _iconPools = {},
        _recyclePool = {},
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
        GetIconPool = function(self, viewerType)
            return self._iconPools[viewerType] or {}
        end,
        EnsurePool = function(self, viewerType)
            if not self._iconPools[viewerType] then
                self._iconPools[viewerType] = {}
            end
            return self._iconPools[viewerType]
        end,
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
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local icons = assert(ns.CDMIcons, "CDMIcons should be exported")
local factory = assert(ns.CDMIconFactory, "CDMIconFactory should be exported")
factory:EnsurePool("essential")
local pool = factory:GetIconPool("essential")
local first = makeIcon(11111)
local second = makeIcon(22222)
pool[#pool + 1] = first
pool[#pool + 1] = second

-- _showingGCDSwipe is the icon-local GCD render lock. (The former _isOnGCD
-- icon field is gone: isOnGCD is now read directly off cdInfo by the resolver,
-- never stamped on the icon, so the render lock is represented by the swipe
-- flag the renderer already owns.)
first._showingGCDSwipe = true
second._showingGCDSwipe = true
first._lastDurObj = gcdDuration
first._lastDurObjKey = "gcd-only:11111"
first._lastResolvedMode = "gcd-only"
first._lastResolvedSourceID = 11111
second._lastDurObj = gcdDuration
second._lastDurObjKey = "gcd-only:22222"
second._lastResolvedMode = "gcd-only"
second._lastResolvedSourceID = 22222

currentOnGCD = false
gcdQueryable = false
icons.HandleRuntimeRefresh("SPELL_UPDATE_USABLE")

assert(first._showingGCDSwipe == true,
    "SPELL_UPDATE_USABLE should not clear the first icon's active GCD render lock (its swipe)")
assert(second._showingGCDSwipe == true,
    "SPELL_UPDATE_USABLE should not clear the second icon's active GCD render lock (its swipe)")
assert(first._usabilityTinted == true, "SPELL_UPDATE_USABLE should immediately apply unusable tint after cooldown suppression")
local firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 0.4 and firstColor[2] == 0.4 and firstColor[3] == 0.4 and firstColor[4] == 1,
    "SPELL_UPDATE_USABLE should darken unusable icons without waiting for the range poll")

currentOnGCD = true
gcdQueryable = true
local cooldownChanged = assert(subscriptions["CDM:COOLDOWN_CHANGED"], "cooldown subscriber should be registered")
-- A refresh carrying a comparable spellID does a TARGETED ApplySpellID for that
-- spell only — there is no broad GCD-edge walk anymore (isOnGCD is read directly
-- off cdInfo, and GCD-only swipe refresh rides the cast_succeeded
-- InvalidateGCDOnlyBindings path). The cast spell keeps its GCD swipe and the
-- unrelated icon's existing swipe is left untouched (not broadened).
cooldownChanged("CDM:COOLDOWN_CHANGED", 11111, nil, "refresh")

assert(first._showingGCDSwipe == true, "targeted per-spell GCD refresh should keep the cast spell's GCD swipe")
assert(second._showingGCDSwipe == true,
    "targeted per-spell GCD refresh should preserve an unrelated icon's existing GCD swipe")

local firstBinds = first.cooldownBinds or 0
local secondBinds = second.cooldownBinds or 0
cooldownChanged("CDM:COOLDOWN_CHANGED", nil, nil, "refresh")

assert((first.cooldownBinds or 0) == firstBinds,
    "nil-spellID refresh should not rebind an active GCD swipe (no broad walk)")
assert((second.cooldownBinds or 0) == secondBinds,
    "nil-spellID refresh should preserve existing GCD DurationObject bindings")

print("OK: cdm_gcd_refresh_state_test")
