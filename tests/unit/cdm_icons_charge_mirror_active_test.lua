-- tests/unit/cdm_icons_charge_mirror_active_test.lua
-- Run: lua tests/unit/cdm_icons_charge_mirror_active_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

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

local chargeDuration = { token = "charge-duration" }
local storedState
local pandemicCleared = false

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    essential = {
                        desaturateOnCooldown = true,
                    },
                }
            end
        end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        SafeToNumber = function(value) return value end,
        CanAccessTable = function(tbl) return type(tbl) == "table" end,
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
    },
    CDMSources = {
        QuerySpellUsable = function() return true, false end,
        QuerySpellCharges = function()
            error("mirror-backed charge apply must not query spell charges")
        end,
        QuerySpellCooldown = function(spellID)
            if spellID == 444347 then
                return {
                    startTime = 0,
                    duration = 0,
                    isActive = false,
                    isOnGCD = false,
                }
            end
            return nil
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
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function() return nil end,
        ResolveCooldownState = function(context)
            local entry = context and context.entry
            -- Under the post-cascade-collapse contract the resolver never
            -- returns mode == "charge". A charge spell whose recharge is
            -- rolling resolves to mode == "cooldown" with the recharge
            -- DurationObject bound. The icon renderer queries charges
            -- separately when it needs to know charges-remaining state.
            if entry and entry.id == 444348 then
                return {
                    mode = "cooldown",
                    active = true,
                    isActive = true,
                    durObj = chargeDuration,
                    sourceID = "444348:2",
                    spellID = 444348,
                    mirrorBacked = nil,
                    isOnCooldown = true,
                    gcdOnly = false,
                }
            end

            local state = {
                cooldownID = 8203,
                viewerCategory = "essential",
                isActive = true,
                resolvedMode = "cooldown",
            }
            return {
                mode = "cooldown",
                active = true,
                isActive = true,
                durObj = chargeDuration,
                sourceID = "mirror:8203:444347",
                spellID = 444347,
                mirrorBacked = true,
                isOnCooldown = false,
                gcdOnly = false,
                cooldownInfo = {
                    startTime = 0,
                    duration = 0,
                    isActive = false,
                    isOnGCD = false,
                },
                cooldownInfoActive = false,
                cooldownInfoOnGCD = false,
                mirrorCooldownID = 8203,
                mirrorCategory = "essential",
                cooldownID = 8203,
                category = "essential",
                state = state,
                mirrorState = state,
            }
        end,
    },
    CDMIconFactory = {
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
    },
    CDMRuntimeStore = {
        SetIconState = function(_, state)
            storedState = state
        end,
    },
    _OwnedGlows = {
        ClearPandemicState = function(icon)
            pandemicCleared = icon and true or false
            if icon and icon.PandemicGlow then
                icon.PandemicGlow:SetAlpha(0)
            end
        end,
    },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local appliedDuration
local cleared = false
local desaturated
local pandemicAlpha = 1

local icon = {
    Cooldown = {
        SetCooldownFromDurationObject = function(_, durObj)
            appliedDuration = durObj
        end,
        SetReverse = noop,
        SetSwipeTexture = noop,
        Clear = function()
            cleared = true
        end,
    },
    Icon = {
        SetDesaturated = function(_, value)
            desaturated = value
        end,
        SetVertexColor = noop,
    },
    PandemicGlow = {
        SetAlpha = function(_, alpha)
            pandemicAlpha = alpha
        end,
    },
    _auraActive = true,
    _lastAuraDurObj = { token = "prior-aura-duration" },
    _auraIsHarmful = false,
    _spellEntry = {
        id = 444347,
        spellID = 444347,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
        name = "Charged Mirror Spell",
    },
}

local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)

assert(applied == true, "active charge mirror should report an applied cooldown")
assert(appliedDuration == chargeDuration, "active charge mirror should keep the recharge DurationObject bound")
assert(cleared == false, "active charge mirror must not clear the cooldown frame")
assert(icon._resolvedCooldownMode == "cooldown",
    "active charge mirror should resolve as cooldown under the new contract")
assert(icon._hasCooldownActive == false, "charge mirror with inactive spell cooldown should not mark the spell unavailable")
assert(icon._hasRealCooldownActive == false, "charge mirror with inactive spell cooldown should not mark a real cooldown")
assert(desaturated == false, "charge mirror with inactive spell cooldown should keep the icon saturated")
assert(icon._auraActive == false, "charge mirror transition should clear stale aura-active state")
assert(icon._lastAuraDurObj == nil, "charge mirror transition should clear stale aura duration state")
assert(pandemicCleared == true, "charge mirror transition should clear stale pandemic glow state")
assert(pandemicAlpha == 0, "charge mirror transition should hide the existing pandemic glow frame")
assert(storedState and storedState.mode == "cooldown",
    "runtime store should classify charge-spell recharge as cooldown under the new contract")
assert(storedState and storedState.active == false, "runtime store should store availability separately from recharge mode")
assert(storedState and storedState.isOnCooldown == false, "runtime store should preserve cooldown lock separately")

pandemicCleared = false
pandemicAlpha = 1
storedState = nil

local liveChargeIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = function(_, durObj)
            appliedDuration = durObj
        end,
        SetReverse = noop,
        SetSwipeTexture = noop,
        Clear = function()
            cleared = true
        end,
    },
    Icon = {
        SetDesaturated = function(_, value)
            desaturated = value
        end,
        SetVertexColor = noop,
    },
    PandemicGlow = {
        SetAlpha = function(_, alpha)
            pandemicAlpha = alpha
        end,
    },
    _auraActive = true,
    _lastAuraDurObj = { token = "prior-live-aura-duration" },
    _auraIsHarmful = false,
    _spellEntry = {
        id = 444348,
        spellID = 444348,
        kind = "aura",
        type = "spell",
        viewerType = "buff",
        name = "Live Charged Aura Spell",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(liveChargeIcon)

assert(applied == true, "live charge fallback should still report an applied cooldown")
assert(liveChargeIcon._resolvedCooldownMode == "cooldown",
    "live charge fallback should resolve as cooldown under the new contract")
assert(liveChargeIcon._auraActive == false,
    "live charge fallback should clear stale aura-active state")
assert(liveChargeIcon._lastAuraDurObj == nil,
    "live charge fallback should clear stale aura duration state")
assert(pandemicCleared == true, "live charge fallback should clear stale pandemic glow state")
assert(pandemicAlpha == 0, "live charge fallback should hide the existing pandemic glow frame")

print("OK: cdm_icons_charge_mirror_active_test")
