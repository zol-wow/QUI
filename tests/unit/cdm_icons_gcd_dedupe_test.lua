-- tests/unit/cdm_icons_gcd_dedupe_test.lua
-- Run: lua tests/unit/cdm_icons_gcd_dedupe_test.lua

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

local gcdDuration = { token = "gcd-duration" }
local resolvedDuration = gcdDuration

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
        ResolveCooldownState = function()
            return {
                mode = "gcd-only",
                active = true,
                isActive = true,
                durObj = resolvedDuration,
                sourceID = 12345,
                spellID = 12345,
            }
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

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local durationBindingKeyBuilds
for _, probe in ipairs(ns._memprobes or {}) do
    if probe.name == "CDM_durationBindingKeys" then
        durationBindingKeyBuilds = probe.fn
        break
    end
end

local icon = {
    Cooldown = {
        SetCooldownFromDurationObject = function()
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
    },
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

local keyBuildsBefore = durationBindingKeyBuilds and durationBindingKeyBuilds() or 0
local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)
local keyBuildsAfter = durationBindingKeyBuilds and durationBindingKeyBuilds() or 0

assert(applied == true, "deduped GCD duration should still be treated as applied")
assert(keyBuildsAfter == keyBuildsBefore,
    "legacy duration binding comparison should not allocate a replacement key")
assert(icon._showingGCDSwipe == true, "deduped GCD duration should restore the GCD swipe flag")
assert(icon._showingRealCooldownSwipe == nil, "deduped GCD duration should clear real cooldown swipe state")

print("OK: cdm_icons_gcd_dedupe_test")
