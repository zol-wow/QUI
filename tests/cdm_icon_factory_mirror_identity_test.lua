-- tests/cdm_icon_factory_mirror_identity_test.lua
-- Run: lua tests/cdm_icon_factory_mirror_identity_test.lua

function InCombatLockdown() return false end
function CreateFrame() return {} end

local sharedIdentityEntry
local ns = {
    Helpers = {},
    CDMResolvers = {
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        QueryCharges = function() return nil end,
        QueryCooldown = function() return nil end,
        QueryOverrideSpell = function() return nil end,
        QueryDisplayCount = function() return nil end,
        ResolveAuraStateForIcon = function() return nil end,
        HasRealCooldownState = function() return false end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function() return true end,
        ResolveBlizzardMirrorIdentity = function(entry)
            sharedIdentityEntry = entry
            return 73542, "buff"
        end,
    },
}

assert(loadfile("modules/cdm/cdm_icon_factory.lua"))("QUI", ns)

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

print("OK: cdm_icon_factory_mirror_identity_test")
