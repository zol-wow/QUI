-- tests/unit/cdm_icons_event_trace_fallback_test.lua
-- Run: lua tests/unit/cdm_icons_event_trace_fallback_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

local frameOnEvent

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
            if scriptName == "OnEvent" and handler then
                frameOnEvent = handler
            end
        end,
    }
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    essential = {
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
            profile = { ncdm = { essential = { iconDisplayMode = "always" } } },
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
        ResolveCooldownState = function()
            return {
                mode = "inactive",
                active = false,
                isActive = false,
            }
        end,
    },
    CDMIconFactory = {
        _iconPools = {},
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
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local icons = assert(ns.CDMIcons, "CDMIcons should be exported")
assert(type(icons.EventTracePrint) == "function", "base CDM icons should provide an event trace print fallback")
assert(type(icons.EventTraceAuraInfo) == "function", "base CDM icons should provide an aura trace info fallback")
assert(frameOnEvent, "CDM icon event frame should register an OnEvent handler")

local ok, err = pcall(frameOnEvent, {}, "UPDATE_MACROS")
assert(ok, "UPDATE_MACROS should not require debug event trace helpers: " .. tostring(err))

ok, err = pcall(icons.HandleRuntimeRefresh, "UNIT_AURA", "player", { isFullUpdate = true })
assert(ok, "UNIT_AURA refresh should not require debug event trace helpers: " .. tostring(err))

print("OK: cdm_icons_event_trace_fallback_test")
