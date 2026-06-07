-- tests/unit/cdm_shared_test.lua
-- Headless verification of shared CDM helper semantics. Run: lua tests/unit/cdm_shared_test.lua

local core = {
    db = {
        profile = {
            ncdm = {
                enabled = true,
                essential = { enabled = true },
                containers = {
                    custom = { enabled = true },
                    shapedBar = { enabled = true, shape = "bar" },
                    legacyAuraBar = { enabled = true, containerType = "auraBar" },
                    mixed = { enabled = true, shape = "icon" },
                },
            },
        },
    },
}

local ns = {
    Helpers = {
        IsSecretValue = function(value)
            return value == "__secret__"
        end,
        GetCore = function()
            return core
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
local chunk = loadChunk("QUI_CDM/cdm/cdm_shared.lua", "cdm_shared.lua")
chunk("QUI", ns)

local Shared = assert(ns.CDMShared, "CDMShared table was not exported")

assert(Shared.IsRuntimeEnabled() == true, "runtime should be enabled by default")
core.db.profile.ncdm.enabled = false
assert(Shared.IsRuntimeEnabled() == false, "runtime should follow ncdm.enabled=false")
core.db.profile.ncdm.enabled = true

assert(Shared.GetNcdmDB() == core.db.profile.ncdm, "GetNcdmDB returned wrong table")
assert(Shared.GetContainerDB("essential") == core.db.profile.ncdm.essential, "builtin container lookup failed")
assert(Shared.GetContainerDB("custom") == core.db.profile.ncdm.containers.custom, "custom container lookup failed")
assert(Shared.GetContainerDB("missing") == nil, "missing container should return nil")

assert(Shared.IsSafeNumeric(12.5) == true, "number should be safe numeric")
assert(Shared.IsSafeNumeric("__secret__") == false, "secret should not be safe numeric")
assert(Shared.IsSafeNumeric("12") == false, "string should not be safe numeric")

assert(Shared.SafeBoolean(true) == true, "true should stay true")
assert(Shared.SafeBoolean(false) == false, "false should stay false")
assert(Shared.SafeBoolean("__secret__") == nil, "secret boolean should become nil")

assert(Shared.SettingEnabled(nil, true) == true, "nil should use fallback")
assert(Shared.SettingEnabled(nil, false) == false, "nil should use false fallback")
assert(Shared.SettingEnabled(false, true) == false, "explicit false should stay false")
assert(Shared.SettingEnabled(0, false) == false, "non-true value should be disabled")

assert(Shared.IsBuiltinContainerKey("essential") == true, "essential should be a built-in container key")
assert(Shared.IsBuiltinContainerKey("custom") == false, "custom should not be a built-in container key")
assert(Shared.GetBuiltinContainerLabel("trackedBar") == "Buff Bars", "trackedBar label mismatch")
assert(Shared.GetBuiltinContainerType("buff") == "aura", "buff container type mismatch")
assert(Shared.GetBuiltinContainerShape("trackedBar") == "bar", "trackedBar shape mismatch")
assert(Shared.GetBuiltinContainerShape("essential") == "icon", "essential shape mismatch")
assert(Shared.GetEntryKindForContainerType("cooldown") == "cooldown", "cooldown type should imply cooldown kind")
assert(Shared.GetEntryKindForContainerType("aura") == "aura", "aura type should imply aura kind")
assert(Shared.GetEntryKindForContainerType("auraBar") == "aura", "auraBar type should imply aura kind")
assert(Shared.GetEntryKindForContainerType("customBar") == nil, "customBar should not imply a single entry kind")
assert(Shared.GetBuiltinContainerEntryKind("utility") == "cooldown", "utility should imply cooldown kind")
assert(Shared.GetBuiltinContainerEntryKind("trackedBar") == "aura", "trackedBar should imply aura kind")
assert(Shared.GetContainerType("essential") == "cooldown", "builtin container type should resolve")
assert(Shared.GetContainerType("custom") == nil, "custom mixed container should not invent a type")
assert(Shared.GetContainerShape("essential") == "icon", "builtin icon shape should resolve")
assert(Shared.GetContainerShape("trackedBar") == "bar", "builtin bar shape should resolve")
assert(Shared.GetContainerShape("shapedBar") == "bar", "custom shape should override defaults")
assert(Shared.GetContainerShape("legacyAuraBar") == "bar", "legacy auraBar type should imply bar shape")
assert(Shared.GetContainerShape("custom") == "icon", "unknown custom shape should default to icon")
assert(Shared.GetContainerEntryKind("buff") == "aura", "builtin aura key should imply aura kind")
assert(Shared.GetContainerEntryKind("custom") == nil, "custom mixed container should not imply entry kind")
assert(Shared.GetContainerEntryKind("legacyAuraBar") == "aura",
    "legacy auraBar type should imply aura entry kind")
assert(Shared.GetBuiltinContainerKeysByEntryKind("cooldown")[1] == "essential",
    "cooldown built-in key list should start with essential")
assert(Shared.GetBuiltinContainerKeysByEntryKind("aura")[2] == "trackedBar",
    "aura built-in key list should include trackedBar")
assert(Shared.GetBuiltinContainerKeysByShape("icon")[3] == "buff",
    "built-in icon key list should include buff")
assert(Shared.GetBuiltinContainerKeysByShape("bar")[1] == "trackedBar",
    "built-in bar key list should include trackedBar")
assert(Shared.IsBuiltinCooldownContainerKey("essential") == true,
    "essential should be a built-in cooldown container")
assert(Shared.IsBuiltinAuraContainerKey("buff") == true,
    "buff should be a built-in aura container")
assert(Shared.IsBuiltinIconContainerKey("trackedBar") == false,
    "trackedBar should not be a built-in icon container")
assert(Shared.IsBuiltinBarContainerKey("trackedBar") == true,
    "trackedBar should be a built-in bar container")
assert(Shared.NormalizeMirrorCategory("buff") == "buff", "buff should be a mirror category")
assert(Shared.NormalizeMirrorCategory("customBar") == nil, "customBar should not be a mirror category")
assert(Shared.IsAuraMirrorCategory("trackedBar") == true, "trackedBar should be an aura mirror category")
assert(Shared.IsCooldownMirrorCategory("essential") == true, "essential should be a cooldown mirror category")
assert(Shared.IsCooldownMirrorCategory("buff") == false, "buff should not be a cooldown mirror category")

local customBar = {
    containerType = "customBar",
    showOnlyOnCooldown = true,
    showOnlyWhenActive = true,
    showOnlyWhenOffCooldown = true,
    dynamicLayout = true,
    clickableIcons = true,
}
assert(Shared.IsCustomBarContainer(customBar) == true, "customBar container should be detected")
assert(Shared.IsCustomBarContainer({ containerType = "cooldown" }) == false,
    "non-customBar container should not be detected")
assert(Shared.NormalizeCustomBarVisibilityFlags({ containerType = "cooldown" }) == "always",
    "non-customBar normalization should return always")
assert(Shared.NormalizeCustomBarVisibilityFlags(customBar) == "onCooldown",
    "showOnlyOnCooldown should win visibility precedence")
assert(customBar.visibilityMode == "onCooldown", "visibilityMode should be stamped")
assert(customBar.showOnlyWhenActive == false, "active visibility flag should be cleared")
assert(customBar.showOnlyWhenOffCooldown == false, "off-cooldown visibility flag should be cleared")
assert(customBar.desaturateOnCooldown == true, "desaturateOnCooldown should default true")
assert(customBar.dynamicLayout == true, "dynamicLayout should preserve explicit true")
assert(customBar.clickableIcons == false, "dynamicLayout should disable clickable icons")
assert(customBar.tooltipContext == "customTrackers", "tooltip context should default")
assert(customBar.keybindContext == "customTrackers", "keybind context should default")
assert(Shared.GetCustomBarVisibilityMode(customBar) == "onCooldown",
    "visibility mode getter should return normalized mode")

local offCooldownCustomBar = {
    containerType = "customBar",
    showOnlyWhenOffCooldown = true,
    noDesaturateWithCharges = true,
}
assert(Shared.NormalizeCustomBarVisibilityFlags(offCooldownCustomBar) == "offCooldown",
    "off-cooldown flag should resolve to offCooldown")
assert(offCooldownCustomBar.noDesaturateWithCharges == false,
    "noDesaturateWithCharges should be allowed only for onCooldown mode")
assert(offCooldownCustomBar.dynamicLayout == false, "dynamicLayout should default false")

print("OK: cdm_shared_test")
