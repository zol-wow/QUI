-- tests/unit/search_cache_buffdebuff_route_test.lua
-- Regression: the Buff/Debuff options tab was moved out of the Action Bars tile
-- into the Auras hub ("Buff/Debuff Frames", tabIndex 21 / subTabIndex 4 /
-- auras subPages[4]), but BuildBuffDebuffTab kept tagging its widgets with the
-- removed surface route (action_bars, subPageIndex 2). Array slot 2 of the
-- Action Bars tile now holds "Per-Bar", so every harvested entry -- the shared
-- toggles AND the whole mounted aura-element editor -- navigated searchers to
-- Action Bars > Per-Bar, a page that contains none of those settings.
--
-- Buff/Debuff is now DUAL-HOMED: the same editor also mounts back on the
-- Action Bars tile (third sub-page, after Task 6), and that module home was
-- given its OWN featureId, "actionBarsBuffDebuffPage", so the two homes can
-- carry different routes from one shared editor. The FEATURE_ID checks below
-- are unchanged and still guard the original regression -- the hub-mounted
-- editor (featureId actionBarsBuffDebuff) must not carry a stale Action Bars
-- route. The block at the end of this file adds coverage for the new module
-- page so a route regression on either home fails this test.
--
-- Run: lua tests/unit/search_cache_buffdebuff_route_test.lua

local cache = dofile("tests/helpers/search_cache.lua")()
local settings = assert(cache.settings, "cache must have a settings section")

local FEATURE_ID = "actionBarsBuffDebuff"

local failures = 0
local function check(name, ok, detail)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

local total, misrouted, labels = 0, {}, {}
for _, entry in ipairs(settings) do
    if entry.featureId == FEATURE_ID then
        total = total + 1
        labels[entry.label or ""] = true
        local routed = entry.tileId == "auras"
            and entry.subPageIndex == 4
            and (entry.tabIndex == nil or entry.tabIndex == 21)
            and (entry.subTabIndex == nil or entry.subTabIndex == 4)
        if not routed then
            misrouted[#misrouted + 1] = ("%s (tile=%s tab=%s subTab=%s subPage=%s)"):format(
                tostring(entry.label), tostring(entry.tileId), tostring(entry.tabIndex),
                tostring(entry.subTabIndex), tostring(entry.subPageIndex))
        end
    end
end

check("cache carries buff/debuff settings at all", total > 0)
check("every buff/debuff entry navigates to the Auras hub sub-page",
    #misrouted == 0)
if #misrouted > 0 then
    for i = 1, math.min(#misrouted, 5) do
        print("      misrouted: " .. misrouted[i])
    end
end

-- The mounted aura-element editor is the bulk of this tab's searchable surface;
-- these labels only enter the cache because its subsection bodies are always
-- built (see aura_elements_editor_test.lua), so pin two of them here.
check("aura-element editor settings are captured under this feature",
    labels["Boss Auras"] == true and labels["Custom Dispel Ring Colors"] == true)

-- Source pin: the route lives in the tab builder itself, not only in the hub
-- page's post-build re-assert (which runs too late for its own widgets).
local handle = assert(io.open("QUI_ActionBars/actionbars/settings/action_bars_buffdebuff_content.lua", "rb"))
local source = handle:read("*a")
handle:close()
check("tab builder tags widgets with the hub route",
    source:find('local BUFF_DEBUFF_SEARCH_TILE_ID = "auras"', 1, true) ~= nil
    and source:find("local BUFF_DEBUFF_SUB_PAGE_INDEX = 4", 1, true) ~= nil
    and source:find("tabIndex = 21", 1, true) ~= nil
    and source:find('subTabName = ns.L["Buff/Debuff Frames"]', 1, true) ~= nil)

-- Route agreement is load-bearing, not cosmetic: GUI:ResolveSearchNavigation
-- (QUI_Options/framework.lua) DISCARDS an entry's explicit tileId/subPageIndex
-- when it disagrees with the navMap route registered for its
-- (tabIndex, subTabIndex), then falls back to that tab route. The auras tile's
-- fourth sub-page must therefore register navRoutes {21, 4} -- RegisterFeatureTile
-- passes the subPages array index as the sub-page (QUI_Options/shared.lua) --
-- or these entries silently land on the hub's default sub-page instead.
local tileHandle = assert(io.open("QUI_Options/tiles/auras.lua", "rb"))
local tileSource = tileHandle:read("*a")
tileHandle:close()
local aursActionBarAt = assert(tileSource:find('id = "aurasActionBar"', 1, true),
    "auras tile must still register the Buff/Debuff Frames sub-page")
local aursActionBarBlock = tileSource:sub(aursActionBarAt, aursActionBarAt + 600)
check("hub sub-page registers the matching navMap route",
    aursActionBarBlock:find("navRoutes = { { tabIndex = 21, subTabIndex = 4 } }", 1, true) ~= nil)
local subPageOrder = {}
for id in tileSource:gmatch('id = "(auras%a+)"') do
    subPageOrder[#subPageOrder + 1] = id
end
check("Buff/Debuff Frames is the fourth auras sub-page",
    subPageOrder[4] == "aurasActionBar")

-- Task 6 added the module home as a SEPARATE feature so the two homes can
-- carry different routes from one shared editor. The assertions above still
-- guard actionBarsBuffDebuff's own rows; these guard the new module page.
local modulePageRows = 0
for _, entry in ipairs(settings) do
    if entry.featureId == "actionBarsBuffDebuffPage" then
        modulePageRows = modulePageRows + 1
        if entry.tileId ~= "action_bars" then
            check("module page rows must carry the action_bars tileId",
                false, "got tileId=" .. tostring(entry.tileId))
        end
        if entry.subPageIndex ~= 3 then
            check("module page rows must point at sub-page 3 (Per-Bar owns 2)",
                false, "got subPageIndex=" .. tostring(entry.subPageIndex))
        end
    end
end
check("the Action Bars module home is indexed", modulePageRows > 0,
    "got " .. modulePageRows)

if failures > 0 then
    error(("search_cache_buffdebuff_route_test: %d check(s) failed"):format(failures), 0)
end
print("search_cache_buffdebuff_route_test: all checks passed")
