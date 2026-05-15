-- tests/cdm_icons_charge_mirror_active_test.lua
-- Run: lua tests/cdm_icons_charge_mirror_active_test.lua

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
    },
    CDMResolvers = {
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        QueryCharges = function()
            error("mirror-backed charge apply must not query spell charges")
        end,
        QueryCooldown = function(spellID)
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
        ResolveCooldownActivityState = function() return nil end,
        ResolveIconDurationObject = function()
            return chargeDuration,
                "charge",
                "charge:mirror:8203:183",
                nil,
                nil,
                444347,
                true,
                {
                    mode = "charge",
                    spellID = 444347,
                    state = {
                        cooldownID = 8203,
                        viewerCategory = "essential",
                        isActive = true,
                        resolvedMode = "charge",
                    },
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
}

assert(loadfile("modules/cdm/cdm_icons.lua"))("QUI", ns)

local appliedDuration
local cleared = false
local desaturated

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
assert(icon._resolvedCooldownMode == "charge",
    "normal cooldown inactivity should not downgrade active charge mirror mode")
assert(icon._hasCooldownActive == true, "active charge mirror should keep cooldown-active state")
assert(desaturated == true, "active charge mirror should still use cooldown desaturation")
assert(storedState and storedState.mode == "charge", "runtime store should keep charge mode")
assert(storedState and storedState.active == true, "runtime store should keep charge active")

print("OK: cdm_icons_charge_mirror_active_test")
