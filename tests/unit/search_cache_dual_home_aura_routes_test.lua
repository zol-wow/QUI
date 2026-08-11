-- tests/unit/search_cache_dual_home_aura_routes_test.lua
-- Run: lua tests/unit/search_cache_dual_home_aura_routes_test.lua
--
-- Every aura editor is mounted in TWO places -- its owning module tile and the
-- Auras hub -- and both must be indexed for search. Before the dual-surface
-- work, hub pages re-tagged the search context only AFTER the render returned,
-- so the hub carried the page's own chrome (about 5 rows) and not one editor
-- widget.
--
-- These per-surface counts are NOT liveness proofs -- they only assert that
-- rows matching a tileId/surfaceTabKey/featureId exist in sufficient
-- quantity. Two of the module-side probes below (Group Frames, Nameplates)
-- would have passed unchanged at HEAD, when the Group Frames module rows
-- were dead. Route liveness (whether a cache row's route is actually
-- reachable from a live tab/subtab) is carried entirely by
-- tools/audit_search_cache.lua --strict-routes, exercised by
-- tests/unit/search_cache_live_routes_test.lua -- do not over-trust the
-- module-side numbers here as proof of reachability.

local cache = dofile("tests/helpers/search_cache.lua")()
local settings = assert(cache.settings, "cache must have a settings section")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

-- Each surface: a module-route probe and a hub-route probe. minimum is a floor,
-- not an exact count, so ordinary option churn does not redden this test.
--
-- Measured on the tree this test was written against (see task-8-addendum.md):
--   Group Frames auras: module=103, hub=17
--   Unit Frames auras:  module=12,  hub=3
--   Nameplates auras:   module=22,  hub=22
--   Buff/Debuff frames: module=44,  hub=44 (hub counted under featureId
--     actionBarsBuffDebuff post Task 9 dedupe -- see hubMatch comment below)
-- Floors are roughly half the smaller home so ordinary option churn does not
-- redden this test. The Group Frames and Unit Frames module/hub asymmetry is
-- EXPECTED: the module side is inflated by harvest harnesses with no hub
-- equivalent (capture_group_frames_auras_elements force-renders 12 synthetic
-- element variants; the unit capture walks all 6 units while a hub render
-- shows only the selected one). Do not raise the hub floors to match the
-- module counts.
local SURFACES = {
    {
        name = "Group Frames auras",
        moduleMatch = function(e) return e.tileId == "group_frames" and e.surfaceTabKey == "auras" end,
        hubMatch = function(e) return e.tileId == "auras" and e.featureId == "aurasGroupPage" end,
        minimum = 8,
    },
    {
        name = "Unit Frames auras",
        moduleMatch = function(e) return e.tileId == "unit_frames" and e.surfaceTabKey == "icons" end,
        hubMatch = function(e) return e.tileId == "auras" and e.featureId == "aurasUnitPage" end,
        minimum = 2,
    },
    {
        name = "Nameplates auras",
        moduleMatch = function(e) return e.tileId == "nameplates" and e.surfaceTabKey == "auras" end,
        hubMatch = function(e) return e.tileId == "auras" and e.featureId == "aurasNameplatePage" end,
        minimum = 10,
    },
    {
        name = "Buff/Debuff frames",
        moduleMatch = function(e) return e.tileId == "action_bars" and e.featureId == "actionBarsBuffDebuffPage" end,
        -- featureId is actionBarsBuffDebuff here, NOT aurasActionBarPage, even
        -- though these rows live on the Auras hub. Task 9's harvest-time
        -- dedupe (tools/generate_search_cache.lua, register_capture_setting_
        -- entry) collapsed the pair: both features render the identical
        -- QUI_BuffDebuffOptions.BuildBuffDebuffTab at the same destination
        -- (tileId "auras", subPageIndex 4), first registration wins
        -- (QUI_Options.toc loads action_bars.lua, which registers
        -- actionBarsBuffDebuff, before auras_actionbar_page.lua, which
        -- registers aurasActionBarPage), and aurasActionBarPage is now
        -- noSearch = true (core/settings/content/auras_actionbar_page.lua)
        -- with zero harvested rows by design. See
        -- tests/unit/search_cache_no_duplicate_rows_test.lua for the dedupe
        -- guarantee itself.
        hubMatch = function(e) return e.tileId == "auras" and e.featureId == "actionBarsBuffDebuff" end,
        minimum = 20,
    },
}

for _, surface in ipairs(SURFACES) do
    local moduleRows, hubRows = 0, 0
    for _, entry in ipairs(settings) do
        if surface.moduleMatch(entry) then moduleRows = moduleRows + 1 end
        if surface.hubMatch(entry) then hubRows = hubRows + 1 end
    end
    check(surface.name .. " is indexed on its module tile",
        moduleRows >= surface.minimum,
        "got " .. moduleRows .. ", want >= " .. surface.minimum)
    check(surface.name .. " is indexed on the Auras hub",
        hubRows >= surface.minimum,
        "got " .. hubRows .. ", want >= " .. surface.minimum)
end

if failures > 0 then
    print("FAIL: search_cache_dual_home_aura_routes_test (" .. failures .. " failure(s))")
    os.exit(1)
end

print("OK: search_cache_dual_home_aura_routes_test")
