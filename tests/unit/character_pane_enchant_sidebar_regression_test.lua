-- tests/unit/character_pane_enchant_sidebar_regression_test.lua
-- Run: lua tests/unit/character_pane_enchant_sidebar_regression_test.lua

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

local source = readFile("QUI_Skinning/skinning/character_pane/character.lua")

local enchantLocs = assert(
    source:match("local PERMANENT_ENCHANT_EQUIP_LOCS = %b{}"),
    "Permanent enchant equipment-location table should exist")

for _, loc in ipairs({
    "INVTYPE_HEAD",
    "INVTYPE_SHOULDER",
    "INVTYPE_CHEST",
    "INVTYPE_ROBE",
    "INVTYPE_FEET",
    "INVTYPE_FINGER",
    "INVTYPE_WEAPON",
    "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND",
    "INVTYPE_RANGED",
    "INVTYPE_RANGEDRIGHT",
}) do
    assertContains(enchantLocs, loc, loc .. " should be treated as enchantable")
end

for _, loc in ipairs({
    "INVTYPE_NECK",
    "INVTYPE_CLOAK",
    "INVTYPE_WRIST",
    "INVTYPE_HAND",
    "INVTYPE_WAIST",
    "INVTYPE_LEGS",
    "INVTYPE_SHIELD",
    "INVTYPE_HOLDABLE",
}) do
    assertAbsent(enchantLocs, loc, loc .. " should not show missing-enchant text")
end

assertContains(
    source,
    "local function SelectCharacterStatsSidebarTab()",
    "Returning to the main Character tab must reset the PaperDoll sidebar selection")

assertContains(
    source,
    "PaperDollFrame_SetSidebar",
    "Sidebar selection should use Blizzard's PaperDoll sidebar function when available")

assertContains(
    source,
    "pcall(_G.PaperDollFrame_SetSidebar, PaperDollSidebarTab1, 1)",
    "Sidebar selection should call PaperDollFrame_SetSidebar with the same tab/index shape Blizzard uses")

assertAbsent(
    source,
    "pcall(_G.PaperDollFrame_SetSidebar, 1)",
    "Sidebar selection should not call PaperDollFrame_SetSidebar with index as the self argument")

assertContains(
    source,
    "GetPaperDollSideBarFrame",
    "Sidebar active detection should follow Blizzard's shown sidebar frame state")

assertContains(
    source,
    "tab.Hider",
    "Sidebar selected visual should update Blizzard's Hider region")

assertContains(
    source,
    "tab.Highlight",
    "Sidebar selected visual should update Blizzard's Highlight region")

assertContains(
    source,
    "PaperDollFrame_UpdateSidebarTabs",
    "Returning to stats should refresh Blizzard's sidebar tab visual state")

local mainTabHookStart = assert(
    source:find("CharacterFrameTab1:HookScript", 1, true),
    "CharacterFrameTab1 click hook should be present")

local mainTabHookEnd = assert(
    source:find("GetState(CharacterFrameTab1).popoutRestoreHooked = true", mainTabHookStart, true),
    "CharacterFrameTab1 click hook should stamp weak-key state")

local mainTabHook = source:sub(mainTabHookStart, mainTabHookEnd)
assertContains(
    mainTabHook,
    "SelectCharacterStatsSidebarTab()",
    "Clicking the main Character tab must mark the stats sidebar tab selected")

print("OK: character_pane_enchant_sidebar_regression_test")
