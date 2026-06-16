-- tests/unit/search_cache_damage_meter_settings_test.lua
-- Regression: the native Damage Meter is a custom "page" feature whose settings
-- are only captured if its page builder runs during cache generation. The
-- builder used to early-return in the headless generator because it captured
-- `ns.QUI_Options` at load time, before that namespace existed in the
-- generator's load order — so its sub-options (Visibility, Bar Height, …) never
-- entered the search cache and searching for them returned nothing.
--
-- This test asserts the generated cache carries the damage meter's settings,
-- plus a few recent Group Frames controls that are easy to miss because they
-- are built by custom page renderers.
--
-- Run: lua tests/unit/search_cache_damage_meter_settings_test.lua

local ns = {}
assert(loadfile("QUI_OptionsSearch/search_cache.lua"))("QUI", ns)
local cache = assert(ns.QUI_SearchCache, "search cache should load")
local settings = assert(cache.settings, "cache must have a settings section")

local FEATURE_ID = "damageMeterNativePage"

local labelsForFeature = {}
local count = 0
for _, entry in ipairs(settings) do
    if entry.featureId == FEATURE_ID then
        count = count + 1
        if type(entry.label) == "string" then
            labelsForFeature[entry.label] = true
        end
    end
end

assert(count > 0,
    "search cache has no Damage Meter settings entries — the page builder did not "
        .. "run during generation (sub-options are unsearchable)")

-- A few representative sub-options that must be findable by name.
for _, label in ipairs({ "Visibility", "Bar Height", "Refresh Rate (Combat)" }) do
    assert(labelsForFeature[label],
        ("expected Damage Meter setting %q in the search cache; found %d dm settings")
            :format(label, count))
end

local function descriptorDbPath(entry)
    local descriptor = entry.widgetDescriptor
    if type(descriptor) == "table" then
        return descriptor.dbPath
    end
    return nil
end

local function isGroupFramesAuraEntry(entry)
    return entry
        and entry.featureId == "groupFramesPage"
        and entry.tileId == "group_frames"
        and entry.tabName == "Group Frames"
        and entry.subTabName == "Auras"
        and entry.surfaceTabKey == "auras"
end

local targetedByPath = {}
local missingRaidBuffLabels = {}

for _, entry in ipairs(settings) do
    if isGroupFramesAuraEntry(entry) then
        if entry.label == "Enable Targeted Spells" then
            targetedByPath[descriptorDbPath(entry) or ""] = entry
        end
        missingRaidBuffLabels[entry.label or ""] = true
    end
end

for _, spec in ipairs({
    { providerKey = "partyFrames", dbPath = "profile.quiGroupFrames.party.targetedSpells" },
    { providerKey = "raidFrames", dbPath = "profile.quiGroupFrames.raid.targetedSpells" },
}) do
    local entry = assert(targetedByPath[spec.dbPath],
        "targeted spells enable row should be searchable at " .. spec.dbPath)
    assert(entry.providerKey == spec.providerKey,
        ("targeted spells row %s should use providerKey %s, got %s")
            :format(spec.dbPath, spec.providerKey, tostring(entry.providerKey)))
    assert(entry.widgetType == "checkbox",
        "targeted spells enable row should remain a checkbox search entry")
end

for _, label in ipairs({
    "Add Missing Raid Buff",
    "Auto-Detect My Buff",
    "Arcane Intellect (Mage)",
    "Power Word: Fortitude (Priest)",
    "Battle Shout (Warrior)",
    "Mark of the Wild (Druid)",
    "Skyfury (Shaman)",
    "Blessing of the Bronze (Evoker)",
}) do
    assert(missingRaidBuffLabels[label],
        ("missing raid buff aura controls should be searchable by label %q"):format(label))
end

print(("OK: search_cache_damage_meter_settings_test (%d dm settings + group frame recent controls)")
    :format(count))
