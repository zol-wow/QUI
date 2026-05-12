-- tests/cdm_icons_stack_resolution_test.lua
-- Run: lua tests/cdm_icons_stack_resolution_test.lua

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

C_Timer = { After = function(_, callback) callback() end }

local queriedMinApplications

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function()
                return {}
            end
        end,
        IsSecretValue = function() return false end,
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
        QueryAuraApplicationDisplayCount = function(unit, auraInstanceID, minApplications)
            queriedMinApplications = minApplications
            if unit == "target" and auraInstanceID == 9001 and minApplications == 2 then
                return "4"
            end
            return nil
        end,
    },
    CDMResolvers = {
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        IsAuraEntry = function(entry)
            return entry and entry.kind == "aura"
        end,
        QueryOverrideSpell = function() return nil end,
        QueryDisplayCount = function() return nil end,
        QuerySpellCount = function(spellID)
            if spellID == 55091 then
                return 5
            end
            return nil
        end,
        GetChargeMetadataDB = function() return nil end,
    },
    CDMIconFactory = {
        _iconPools = {},
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, category)
            if cooldownID == 73542 and category == "essential" then
                return {
                    stackText = "6",
                    stackTextSource = "Applications",
                    stackTextShown = true,
                }
            end
            if cooldownID == 73544 and category == "essential" then
                return {
                    cooldownChargesCount = "7",
                    cooldownChargesShown = true,
                    stackTextShown = false,
                }
            end
        end,
    },
}

assert(loadfile("modules/cdm/cdm_icons.lua"))("QUI", ns)

local icons = ns.CDMIcons

local text, textSource, mirrorBacked = icons.ResolveIconStackText({
    _spellEntry = {
        type = "spell",
        id = 55090,
        spellID = 55090,
        kind = "cooldown",
        viewerType = "essential",
    },
    _blizzMirrorCooldownID = 73542,
    _blizzMirrorCategory = "essential",
})

assert(text == "6", "cooldown icons should render Blizzard mirror application text")
assert(textSource == "Applications", "cooldown icons should preserve Blizzard mirror text source")

text, textSource, mirrorBacked = icons.ResolveIconStackText({
    _spellEntry = {
        type = "spell",
        id = 55090,
        spellID = 55090,
        kind = "cooldown",
        viewerType = "essential",
    },
    _blizzMirrorCooldownID = 73544,
    _blizzMirrorCategory = "essential",
})

assert(text == "7", "cooldown icons should mirror Blizzard's cached cast count field")
assert(textSource == "ChargeCount", "cached cast count should keep the ChargeCount source")
assert(mirrorBacked == true, "cached cast count should remain mirror-backed")

ns.CDMSpellData = {
    _abilityToAuraSpellID = {
        [55090] = 194310,
    },
    ResolveAuraState = function(_, params)
        if params and params.spellID == 55090 then
            return {
                isActive = true,
                isTotemInstance = false,
                count = {
                    sinkText = "4",
                    value = 4,
                    shown = true,
                    source = "display-count",
                },
            }
        end
        return { isActive = false }
    end,
}

text, textSource = icons.ResolveIconStackText({
    _spellEntry = {
        type = "spell",
        id = 55090,
        spellID = 55090,
        kind = "cooldown",
        viewerType = "essential",
    },
    _runtimeSpellID = 55090,
})

assert(text == nil, "cooldown icons should not synthesize mapped aura application text")
assert(textSource == nil, "cooldown action icons should leave stack text to the mirror")

text, textSource, mirrorBacked = icons.ResolveIconStackText({
    _spellEntry = {
        type = "spell",
        id = 55090,
        spellID = 55090,
        kind = "cooldown",
        viewerType = "essential",
    },
    _runtimeSpellID = 55090,
    _blizzMirrorCooldownID = 73543,
    _blizzMirrorCategory = "essential",
})

assert(text == nil, "mirror-backed cooldown icons should not synthesize mapped aura application text")
assert(textSource == nil, "mirror-backed cooldown icons without mirror text should not set a stack source")
assert(mirrorBacked == true, "mirror-backed cooldown icons without mirror text should mark the mirror authoritative")

text, textSource, mirrorBacked = icons.ResolveIconStackText({
    _spellEntry = {
        type = "spell",
        id = 55091,
        spellID = 55091,
        kind = "cooldown",
        viewerType = "essential",
    },
    _runtimeSpellID = 55091,
    _blizzMirrorCooldownID = 73543,
    _blizzMirrorCategory = "essential",
})

assert(text == 5, "mirror-backed cooldown icons should fall back to spell cast count")
assert(textSource == "spell-cast-count", "spell cast count fallback should identify its source")
assert(mirrorBacked == true, "spell cast count fallback should keep the icon mirror-backed")

icons:EnsurePool("essential")
local pool = icons:GetIconPool("essential")
local stackWrites = 0
pool[#pool + 1] = {
    _stackTextSource = "spell-display-count",
    _blizzMirrorCooldownID = 73543,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        type = "spell",
        id = 55090,
        spellID = 55090,
        kind = "cooldown",
        viewerType = "essential",
    },
    StackText = {
        SetText = function(_, value)
            stackWrites = stackWrites + 1
        end,
        Hide = function()
            stackWrites = stackWrites + 1
        end,
        Show = function()
            stackWrites = stackWrites + 1
        end,
    },
}

icons:UpdateAllIconRanges()

assert(stackWrites == 0, "range/usability refresh must not write stack text")

local apps, source = icons._GetAuraApplicationsFromData({
    applications = 1,
    auraInstanceID = 8001,
}, "target", "direct")

assert(apps == nil, "single numeric aura applications should not be displayed as stack text")
assert(source == nil, "single numeric aura applications should not set a stack source")

apps, source = icons._GetAuraApplicationsFromData({
    applications = "1",
    auraInstanceID = 8002,
}, "target", "direct")

assert(apps == nil, "single string aura applications should not be displayed as stack text")
assert(source == nil, "single string aura applications should not set a stack source")

apps, source = icons._GetAuraApplicationsFromData({
    applications = 4,
    auraInstanceID = 8003,
}, "target", "direct")

assert(apps == 4, "multi-application aura data should keep its application count")
assert(source == "direct", "multi-application aura data should keep its source")

apps, source = icons._GetAuraApplicationsFromData({
    auraInstanceID = 9001,
}, "target", "direct")

assert(queriedMinApplications == 2, "display-count fallback should request only visible stack counts")
assert(apps == "4", "display-count fallback should return C-side stack text")
assert(source == "display-count", "display-count fallback should identify its source")

local stackCalls = {}
local icon = {
    StackText = {
        SetText = function(self, value)
            stackCalls[#stackCalls + 1] = { op = "set", value = value }
            return true
        end,
        Show = function()
            stackCalls[#stackCalls + 1] = { op = "show" }
        end,
        Hide = function()
            stackCalls[#stackCalls + 1] = { op = "hide" }
        end,
    },
}

icons.ApplyAuraCountText(icon, {
    sinkText = "9",
    value = 9,
    shown = true,
    source = "display-count",
}, false, false)

assert(stackCalls[1].op == "set" and stackCalls[1].value == "9",
    "icon renderer should consume shared count sink text")
assert(stackCalls[2].op == "show", "icon renderer should show shared count sink text")

stackCalls = {}
icons.ApplyAuraCountText(icon, {
    shown = false,
    source = "display-count",
}, false, false)

assert(stackCalls[1].op == "set" and stackCalls[1].value == "",
    "hidden shared count should clear icon stack text")
assert(stackCalls[2].op == "hide", "hidden shared count should hide icon stack text")

print("OK: cdm_icons_stack_resolution_test")
