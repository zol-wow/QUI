-- tests/unit/search_cache_module_toggle_keywords_test.lua
-- Regression: feature-toggle (moduleToggle) search entries must carry the
-- feature's display name in their label + keywords, so that searching for the
-- feature (e.g. "damage meter") surfaces its enable/disable toggle row.
--
-- The cache generator previously discarded the author-supplied label/keywords
-- for moduleToggle entries and rebuilt them from route info (tileId +
-- subPageIndex), producing a useless "global > Page 3" label with keywords
-- { "global", "Page 3" } and no feature name — so search could never find them.
--
-- Run: lua tests/unit/search_cache_module_toggle_keywords_test.lua

local chunk = assert(loadfile("QUI_Options/search_cache.lua"),
    "could not load QUI_Options/search_cache.lua")
local ns = {}
chunk("QUI", ns)

local cache = assert(ns.QUI_SearchCache, "search_cache.lua must define ns.QUI_SearchCache")
local nav = assert(cache.navigation, "search cache must have a navigation section")

local function findModuleToggle(featureId)
    for _, entry in ipairs(nav) do
        if entry.navType == "moduleToggle" and entry.featureId == featureId then
            return entry
        end
    end
    return nil
end

local function keywordsContain(entry, needle)
    needle = needle:lower()
    for _, kw in ipairs(entry.keywords or {}) do
        if type(kw) == "string" and kw:lower():find(needle, 1, true) then
            return true
        end
    end
    return false
end

-- Specific case from the bug report: searching "damage meter" must surface the
-- damage meter module switch. The legacy damageMeterNativePage master row was
-- retired with the toggle consolidation; the Module Addons row is the switch.
local dm = assert(findModuleToggle("moduleAddon_QUI_DamageMeter"),
    "expected a moduleToggle nav entry for moduleAddon_QUI_DamageMeter")

assert(dm.label == "Damage Meter",
    ("moduleToggle label should be the feature name; got %q"):format(tostring(dm.label)))
assert(keywordsContain(dm, "Damage Meter"),
    "moduleToggle keywords must include the feature name so search can find it; got: { "
        .. table.concat(dm.keywords or {}, ", ") .. " }")

-- Generic guard: no moduleToggle entry should fall back to the route-derived
-- "global > Page 3" placeholder — that placeholder is the signature of the
-- feature name having been stripped during generation.
local stripped = 0
for _, entry in ipairs(nav) do
    if entry.navType == "moduleToggle" and entry.label == "global > Page 3" then
        stripped = stripped + 1
        io.stderr:write(("  moduleToggle %s has placeholder label \"global > Page 3\"\n")
            :format(tostring(entry.featureId)))
    end
end
assert(stripped == 0,
    ("%d moduleToggle entries have the placeholder label \"global > Page 3\" "
        .. "(feature name stripped during cache generation)"):format(stripped))

print("OK: search_cache moduleToggle keywords regression")
