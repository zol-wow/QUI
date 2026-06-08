-- tests/unit/search_seed_moduletoggle_label_test.lua
-- Regression: GUI:SeedStaticSearchRoutesFromTiles must NOT rewrite a
-- moduleToggle entry's label/keywords from its route breadcrumb.
--
-- The generated cache stores feature-toggle entries with the feature's own
-- display name ("Damage Meter"). At panel-build time SeedStaticSearchRoutesFromTiles
-- backfills route-derived breadcrumb labels onto tab/subtab/section entries.
-- It used to do this for moduleToggle entries too, clobbering "Damage Meter"
-- into the breadcrumb "General > Feature Toggles" — which made the feature
-- toggle unfindable by its own name even though the cache was correct.
--
-- This test loads the REAL framework + generated cache (via the headless
-- environment the cache generator already establishes), runs the seed pass,
-- and asserts the moduleToggle keeps its name and stays searchable.
--
-- Run: lua tests/unit/search_seed_moduletoggle_label_test.lua

-- Reuse the generator's WoW-API stub preamble (everything up to the point where
-- it starts building its own capture frame) to load framework.lua headlessly.
local GEN_PATH = "tools/generate_search_cache.lua"
local CUT_MARKER = 'local frame = create_stub_node("Frame", nil, false)'
local fh = assert(io.open(GEN_PATH, "rb"), "cannot open " .. GEN_PATH)
local src = fh:read("*a"); fh:close()
local cut = assert(src:find(CUT_MARKER, 1, true),
    "generator preamble cut marker not found — update CUT_MARKER")
assert((loadstring or load)(src:sub(1, cut - 1), "@gen-preamble"))()

local GUI = assert(_G.QUI and _G.QUI.GUI, "framework did not initialize QUI.GUI")

-- Apply the generated cache exactly as the runtime does.
assert(loadfile("QUI_Options/search_cache.lua"))("QUI", {})

-- The legacy damageMeterNativePage master row was retired with the toggle
-- consolidation; the Module Addons row is the damage meter switch now.
local FEATURE_ID = "moduleAddon_QUI_DamageMeter"

local function moduleToggleLabel()
    for _, e in ipairs(GUI.StaticNavigationRegistry or {}) do
        if e.navType == "moduleToggle" and e.featureId == FEATURE_ID then
            return e.label
        end
    end
    return nil
end

-- Sanity: the cache itself carries the feature name (guards against this test
-- silently passing if the cache regresses).
assert(moduleToggleLabel() == "Damage Meter",
    ("expected cache moduleToggle label 'Damage Meter', got %q")
        :format(tostring(moduleToggleLabel())))

-- Minimal tile tree so the seed pass can resolve the "global" feature-toggles
-- page and the "gameplay" damage-meter sub-page.
local frame = { _tiles = {
    { id = "global",   config = { name = "General",  subPages = { [3] = { name = "Feature Toggles" } } } },
    { id = "gameplay", config = { name = "Gameplay", subPages = { [7] = { name = "Damage Meter" } } } },
} }

GUI:SeedStaticSearchRoutesFromTiles(frame)

assert(moduleToggleLabel() == "Damage Meter",
    ("SeedStaticSearchRoutesFromTiles clobbered the moduleToggle label; got %q "
        .. "(route breadcrumb instead of the feature name)")
        :format(tostring(moduleToggleLabel())))

-- End-to-end: the toggle must be returned when searching the feature name.
local _, navResults = GUI:ExecuteSearch("damage meter")
local found = false
for _, r in ipairs(navResults or {}) do
    if r.data and r.data.navType == "moduleToggle" and r.data.featureId == FEATURE_ID then
        found = true
        break
    end
end
assert(found, "searching 'damage meter' did not return the feature-toggle entry after the seed pass")

print("OK: search_seed_moduletoggle_label_test")
