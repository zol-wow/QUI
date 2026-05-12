-- tests/cdm_spell_range_event_test.lua
-- Run: lua tests/cdm_spell_range_event_test.lua

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
        ResolveCooldownActivityState = function()
            return {
                isOnCooldown = false,
                rechargeActive = false,
                hasChargesRemaining = false,
                hasCharges = false,
            }
        end,
        ResolveIconDurationObject = function() return nil, "inactive", nil end,
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
local first = makeIcon(33333)
local second = makeIcon(44444)
pool[#pool + 1] = first
pool[#pool + 1] = second

icons.EventFrameOnEvent({}, "SPELL_RANGE_CHECK_UPDATE", 33333, false, true)

local firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 0.8 and firstColor[2] == 0.1 and firstColor[3] == 0.1,
    "range update event should tint matching out-of-range spell")
assert(#second.vertexColors == 0, "range update event should not repaint unrelated spells")

icons.EventFrameOnEvent({}, "SPELL_RANGE_CHECK_UPDATE", 33333, true, true)

firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 1 and firstColor[2] == 1 and firstColor[3] == 1,
    "range update event should clear range tint when the spell returns in range")

icons.EventFrameOnEvent({}, "SPELL_RANGE_CHECK_UPDATE", 33333, false, false)

firstColor = first.vertexColors[#first.vertexColors]
assert(firstColor and firstColor[1] == 1 and firstColor[2] == 1 and firstColor[3] == 1,
    "range update event should clear range tint when Blizzard did not check range")

print("OK: cdm_spell_range_event_test")
