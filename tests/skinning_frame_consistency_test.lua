-- tests/skinning_frame_consistency_test.lua
-- Run: lua tests/skinning_frame_consistency_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local professions = readFile("modules/skinning/frames/professions.lua")
local auctionHouse = readFile("modules/skinning/frames/auctionhouse.lua")
local craftingOrders = readFile("modules/skinning/frames/craftingorders.lua")

assertContains(
    professions,
    "local function StyleFilterDropdown",
    "Professions must use a dedicated filter dropdown styler so clear-filter child controls are preserved")

local filterHelperBody = professions:match("local function StyleFilterDropdown%b()%s*(.-)%s*%-%- Style close button")
assert(filterHelperBody, "StyleFilterDropdown body should be present before close-button styling")

assertAbsent(
    filterHelperBody,
    "SkinBase.StripTextures",
    "Filter dropdown styling must not strip child textures used by the clear-filter X")

assertContains(
    filterHelperBody,
    "bd:SetFrameLevel(math.max(0, dropdown:GetFrameLevel() - 1))",
    "Filter dropdown backdrop should sit behind dropdown child controls")

assertContains(
    filterHelperBody,
    'SkinBase.SetFrameData(dropdown, "skinColor"',
    "Filter dropdown hover colors must be stored in SkinBase weak state")

assertContains(
    professions,
    "local function RestoreTabVisual",
    "Professions tabs should restore selected/inactive visuals through one local helper")

assertContains(
    professions,
    "local function HookTabHover",
    "Professions tabs should share hover handling for main and specialization tabs")

assertContains(
    professions,
    "HookTabHover(tab, frame, sr, sg, sb, sa)",
    "Main Professions tabs must get consistent hover restoration")

assertContains(
    professions,
    "HookTabHover(tab, specPage, sr, sg, sb, sa)",
    "Professions specialization tabs must get consistent hover restoration")

assertContains(
    professions,
    "RestoreTabVisual(tab, specPage)",
    "Professions specialization tabs must apply selected/inactive visuals after styling and refresh")

local updateDropdownBody = professions:match("local function UpdateDropdownColors%b()%s*(.-)%s*end%s*local function UpdatePanelColors")
assert(updateDropdownBody, "UpdateDropdownColors body should be present")

assertContains(
    updateDropdownBody,
    'SkinBase.SetFrameData(dropdown, "skinColor"',
    "Dropdown refresh must update stored hover border colors")

assertContains(
    updateDropdownBody,
    'SkinBase.SetFrameData(dropdown, "bgColor"',
    "Dropdown refresh must update stored hover background colors")

local refreshMainTabsBody = professions:match("%-%- Tabs%s*if frame%.TabSystem and frame%.TabSystem%.tabs then%s*(.-)%s*UpdateTabSelectedState%(frame%)")
assert(refreshMainTabsBody, "RefreshProfessionsColors main tab refresh body should be present")

assertContains(
    refreshMainTabsBody,
    'SkinBase.SetFrameData(tab, "skinColor"',
    "Main tab theme refresh must update stored hover border colors")

assertContains(
    refreshMainTabsBody,
    'SkinBase.SetFrameData(tab, "bgColor"',
    "Main tab theme refresh must update stored selected-state background colors")

assertContains(
    auctionHouse,
    "StyleDropdownButton(searchBar.FilterButton",
    "Auction House filter button skinning should remain explicit")

assertContains(
    craftingOrders,
    "StyleDropdownButton(searchBar.FilterDropdown",
    "Crafting Orders filter dropdown skinning should remain explicit")

print("OK: skinning_frame_consistency_test")
