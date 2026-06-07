-- tests/unit/cdm_icon_factory_blizz_fallback_test.lua
-- Run: lua tests/unit/cdm_icon_factory_blizz_fallback_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local auraDuration = { token = "aura-duration-object" }
local queriedAura = false
local stackTextValue
local stackTextShown
local clearedStackCount = 0

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    buff = {
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
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        ResolveCooldownState = function()
            return {
                mode = "aura",
                active = true,
                isActive = true,
                auraActive = true,
                isTotemInstance = false,
                count = nil,
            }
        end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return true end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function()
            return { isOnCooldown = false, rechargeActive = false }
        end,
    },
    CDMSources = {
        QueryUnitAuraBySpellID = function(unit, spellID, filter)
            if unit == "player" and spellID == 1242998 and filter == "HELPFUL" then
                queriedAura = true
                return { auraInstanceID = 77 }
            end
            return nil
        end,
        QueryAuraDuration = function(unit, auraInstanceID)
            if unit == "player" and auraInstanceID == 77 then
                return auraDuration
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID)
            if cooldownID == 73543 then
                return {
                    cooldownID = 73543,
                    isActive = false,
                    durObj = nil,
                    selfAura = true,
                    viewerCategory = "buff",
                    spellID = 137008,
                    overrideSpellID = 137008,
                    overrideTooltipSpellID = 1242999,
                    linkedSpellIDs = { 1242999 },
                    mirrorEpoch = 4,
                    stackText = "6",
                    stackTextSource = "FrameText",
                    stackTextShown = true,
                    stackTextEpoch = 10,
                }
            end
            assert(cooldownID == 73542, "unexpected cooldownID")
            return {
                cooldownID = 73542,
                isActive = true,
                durObj = nil,
                selfAura = true,
                viewerCategory = "buff",
                spellID = 137007,
                overrideSpellID = 137007,
                overrideTooltipSpellID = 1242998,
                linkedSpellIDs = { 1242998 },
                mirrorEpoch = 3,
                stackText = "5",
                stackTextSource = "Applications",
                stackTextShown = true,
                stackTextEpoch = 9,
            }
        end,
    },
    _OwnedSwipe = {
        ApplyToIcon = function() end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_factory.lua")("QUI", ns)
dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local function makeStackText()
    return {
        SetText = function(_, value)
            stackTextValue = value
            if value == "" then
                clearedStackCount = clearedStackCount + 1
            end
        end,
        Show = function()
            stackTextShown = true
        end,
        Hide = function()
            stackTextShown = false
        end,
    }
end

local icon = {
    _spellEntry = {
        id = 1242998,
        spellID = 1242998,
        kind = "aura",
        type = "aura",
        viewerType = "buff",
    },
    _blizzMirrorCooldownID = 73542,
    StackText = makeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(icon)

assert(queriedAura == false, "icon sync must not query aura APIs; UNIT_AURA mirror path owns aura duration")
assert(icon._lastAuraDurObj == nil, "active mirror with no durObj should show without inventing a duration")
assert(stackTextValue == "5",
    "mirrored aura icons should render Blizzard-captured stack text when resolver count is missing")
assert(stackTextShown == true, "mirrored aura icon stack text should be marked visible")

stackTextValue = nil
stackTextShown = nil
clearedStackCount = 0

local inactiveTextIcon = {
    _spellEntry = {
        id = 1242999,
        spellID = 1242999,
        kind = "aura",
        type = "aura",
        viewerType = "buff",
    },
    _blizzMirrorCooldownID = 73543,
    StackText = makeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(inactiveTextIcon)

assert(stackTextValue == "6",
    "source-child text should render even when mirror active state is false")
assert(clearedStackCount == 0,
    "inactive mirror state must not clear source-child text")

print("OK: cdm_icon_factory_blizz_fallback_test")
