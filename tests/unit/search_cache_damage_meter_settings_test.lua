-- tests/unit/search_cache_damage_meter_settings_test.lua
-- Regression: the native Damage Meter is a custom "page" feature whose settings
-- are only captured if its page builder runs during cache generation. The
-- builder used to early-return in the headless generator because it captured
-- `ns.QUI_Options` at load time, before that namespace existed in the
-- generator's load order — so its sub-options (Visibility, Bar Height, …) never
-- entered the search cache and searching for them returned nothing.
--
-- This test asserts the generated cache carries the damage meter's settings.
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

print(("OK: search_cache_damage_meter_settings_test (%d dm settings)"):format(count))
