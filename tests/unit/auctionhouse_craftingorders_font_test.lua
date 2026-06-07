-- tests/unit/auctionhouse_craftingorders_font_test.lua
-- Run: lua tests/unit/auctionhouse_craftingorders_font_test.lua
--
-- Regression guard: the Auction House and Crafting Orders skins must apply the
-- global QUI font to their key labels (tabs, category buttons, search box,
-- action buttons) via the shared SkinBase font plumbing. Backgrounds/borders
-- already track the theme; this pins the text-font/color wiring so it can't
-- silently regress. Dense list rows / money frames are intentionally left on
-- Blizzard fonts and are NOT asserted here.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

---------------------------------------------------------------------------
-- Auction House
---------------------------------------------------------------------------
local ah = readFile("QUI_Skinning/skinning/frames/auctionhouse.lua")

assertContains(ah, "SkinTabGroup(AuctionHouseFrame.Tabs, AuctionHouseFrame, { font = true })",
    "AH tabs must opt in to the global QUI font")
assertContains(ah, "SkinEditBox(searchBar.SearchBox, { font = true })",
    "AH search box must use the global QUI font")
assertContains(ah, "SkinBase.SkinFontString(button.Text)",
    "AH category buttons must reapply the QUI font on rebind")
assertContains(ah, "SkinButton(commoditiesSell.PostButton, { font = true })",
    "AH action buttons must use the global QUI font")

---------------------------------------------------------------------------
-- Crafting Orders
---------------------------------------------------------------------------
local co = readFile("QUI_Skinning/skinning/frames/craftingorders.lua")

assertContains(co, "SkinTabGroup(tabs, frame, { font = true })",
    "CO tabs must opt in to the global QUI font")
assertContains(co, "SkinEditBox(searchBar.SearchBox, { font = true })",
    "CO search box must use the global QUI font")
assertContains(co, "SkinBase.SkinFontString(button.Text)",
    "CO category buttons must reapply the QUI font on rebind")
assertContains(co, "SkinButton(form.BackButton, { font = true })",
    "CO action buttons must use the global QUI font")

print("OK: auctionhouse_craftingorders_font_test")
