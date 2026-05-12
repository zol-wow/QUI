-- tests/cdm_icons_gcd_dedupe_test.lua
-- Run: lua tests/cdm_icons_gcd_dedupe_test.lua

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

local gcdDuration = { token = "gcd-duration" }

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {}
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
    CDMSources = {},
    CDMResolvers = {
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        QueryCharges = function() return nil end,
        QueryCooldown = function() return nil end,
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
            return gcdDuration, "gcd-only", 12345, nil, nil, 12345
        end,
    },
    CDMIconFactory = {
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
    },
    CDMRuntimeStore = {
        SetIconState = noop,
    },
}

assert(loadfile("modules/cdm/cdm_icons.lua"))("QUI", ns)

local icon = {
    Cooldown = {},
    _lastDurObjKey = "gcd-only:12345",
    _lastDurObj = gcdDuration,
    _showingGCDSwipe = nil,
    _showingRealCooldownSwipe = true,
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)

assert(applied == true, "deduped GCD duration should still be treated as applied")
assert(icon._showingGCDSwipe == true, "deduped GCD duration should restore the GCD swipe flag")
assert(icon._showingRealCooldownSwipe == nil, "deduped GCD duration should clear real cooldown swipe state")

print("OK: cdm_icons_gcd_dedupe_test")
