-- tests/unit/cdm_icon_factory_mirror_identity_test.lua
-- Run: lua tests/unit/cdm_icon_factory_mirror_identity_test.lua

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

function InCombatLockdown() return false end
function CreateFrame() return {} end

local sharedIdentityEntry
local childBoundListener
local ns = {
    Helpers = {},
    CDMShared = {
        GetBuiltinContainerEntryKind = function(containerKey)
            return ({
                essential = "cooldown",
                utility = "cooldown",
                buff = "aura",
                trackedBar = "aura",
            })[containerKey]
        end,
        IsCooldownMirrorCategory = function(category)
            return category == "essential" or category == "utility"
        end,
        IsAuraMirrorCategory = function(category)
            return category == "buff" or category == "trackedBar"
        end,
    },
    CDMBlizzMirror = {
        AddOnChildBoundListener = function(callback)
            childBoundListener = callback
        end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        ResolveCooldownState = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return true end,
        ResolveBlizzardMirrorIdentityState = function(entry)
            sharedIdentityEntry = entry
            return {
                cooldownID = entry and entry.expectedCategory and entry.id or 73542,
                category = entry and entry.expectedCategory or "buff",
            }
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_factory.lua")("QUI", ns)

local entry = {
    id = 1242998,
    spellID = 1242998,
    name = "Blood Shield",
    kind = "aura",
    type = "spell",
    viewerType = "customIcon",
}
local icon = {}

assert(ns.CDMIconFactory.TryBindIconToBlizz(icon, entry) == true,
    "icon factory should bind through the shared mirror identity resolver")
assert(sharedIdentityEntry == entry,
    "icon factory should pass the entry to the shared mirror identity resolver")
assert(icon._blizzMirrorCooldownID == 73542,
    "icon binding should carry shared mirror cooldownID")
assert(icon._blizzMirrorCategory == "buff",
    "icon binding should carry shared mirror category")

assert(childBoundListener, "icon factory should register a child-bound retry listener")

local pools = ns.CDMIconFactory._iconPools
local essentialIcon = {
    _spellEntry = {
        id = 91001,
        type = "spell",
        viewerType = "essential",
        expectedCategory = "essential",
    },
}
local buffIcon = {
    _spellEntry = {
        id = 91002,
        type = "spell",
        viewerType = "buff",
        expectedCategory = "buff",
    },
}
local customAuraIcon = {
    _spellEntry = {
        id = 91003,
        type = "spell",
        viewerType = "customBar",
        expectedCategory = "buff",
    },
}
local customCooldownIcon = {
    _spellEntry = {
        id = 91004,
        type = "spell",
        viewerType = "customBar",
        expectedCategory = "essential",
    },
}

pools.essential[1] = essentialIcon
pools.buff[1] = buffIcon
pools.customBar = { customAuraIcon }

childBoundListener(1001, "buff")

assert(essentialIcon._blizzMirrorCooldownID == nil,
    "cooldown built-in icons should not retry-bind for aura mirror categories")
assert(buffIcon._blizzMirrorCooldownID == 91002,
    "aura built-in icons should retry-bind for aura mirror categories")
assert(customAuraIcon._blizzMirrorCooldownID == 91003,
    "custom containers should retry-bind for aura mirror categories")

pools.customBar[#pools.customBar + 1] = customCooldownIcon

childBoundListener(1002, "essential")

assert(essentialIcon._blizzMirrorCooldownID == 91001,
    "cooldown built-in icons should retry-bind for cooldown mirror categories")
assert(customCooldownIcon._blizzMirrorCooldownID == 91004,
    "custom containers should retry-bind for cooldown mirror categories")

print("OK: cdm_icon_factory_mirror_identity_test")
