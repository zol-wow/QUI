-- tests/unit/cdm_spell_range_event_test.lua
-- Run: lua tests/unit/cdm_spell_range_event_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function UnitExists(unit) return unit == "target" end
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

local function makeIcon(spellID)
    local icon = { vertexColors = {} }
    icon.Icon = {
        SetVertexColor = function(_, r, g, b, a)
            icon.vertexColors[#icon.vertexColors + 1] = { r, g, b, a }
        end,
        SetDesaturated = noop,
    }
    icon._spellEntry = {
        id = spellID,
        spellID = spellID,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    }
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
                        rangeIndicator = true,
                        rangeColor = {0.8, 0.1, 0.1, 1},
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
        QuerySpellHasRange = function() return true end,
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
local first = makeIcon(33333)
local second = makeIcon(44444)
pool[#pool + 1] = first
pool[#pool + 1] = second

icons.HandleRuntimeRefresh("SPELL_RANGE_CHECK_UPDATE", 33333, false, true)

local firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 0.8 and firstColor[2] == 0.1 and firstColor[3] == 0.1,
    "range update event should tint matching out-of-range spell")
assert(#second.vertexColors == 0, "range update event should not repaint unrelated spells")

icons.HandleRuntimeRefresh("SPELL_RANGE_CHECK_UPDATE", 33333, true, true)

firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 1 and firstColor[2] == 1 and firstColor[3] == 1,
    "range update event should clear range tint when the spell returns in range")

icons.HandleRuntimeRefresh("SPELL_RANGE_CHECK_UPDATE", 33333, false, false)

firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 1 and firstColor[2] == 1 and firstColor[3] == 1,
    "range update event should clear range tint when Blizzard did not check range")

print("OK: cdm_spell_range_event_test")
