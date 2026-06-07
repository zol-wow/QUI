-- tests/unit/craftingorders_category_resuppress_test.lua
-- Run: lua tests/unit/craftingorders_category_resuppress_test.lua
--
-- Regression guard: the crafting-orders category buttons (left nav) must stay
-- skinned after a category is (de)selected.
--
-- Blizzard's ScrollBox element initializer resets NormalTexture:SetAlpha(1.0)
-- every time a button is re-bound (see
-- Blizzard_ProfessionsCustomerOrdersRecipeCategoryList.lua:101,119), and
-- SetCategoryFilter() invalidates the tree data provider -> the initializer
-- re-runs on already-visible buttons WITHOUT re-firing the acquired-frame
-- callback. So the skin must (a) factor texture suppression into a helper that
-- runs on every acquire and (b) re-suppress after SetCategoryFilter, exactly as
-- the Auction House category list already does (OnFilterClicked). Without this
-- the Blizzard auctionhouse-nav-button texture reappears and the buttons read
-- as unskinned.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("QUI_Skinning/skinning/frames/craftingorders.lua")

assertContains(
    source,
    "local function SuppressCategoryTextures",
    "Crafting-orders category skinning must factor out a re-suppress helper (Blizzard restores NormalTexture alpha on rebind)")

assertContains(
    source,
    "hooksecurefunc(categoryList, \"SetCategoryFilter\"",
    "Crafting-orders category skinning must re-suppress after SetCategoryFilter re-inits visible buttons")

print("OK: craftingorders_category_resuppress_test")
