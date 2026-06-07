-- tests/unit/shopping_tooltip_compare_header_skinning_test.lua
-- Run: lua tests/unit/shopping_tooltip_compare_header_skinning_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("QUI_Skinning/skinning/system/tooltips.lua")

assertContains(
    source,
    "local SkinBase = ns.SkinBase",
    "tooltip skinning must use SkinBase for shopping tooltip compare headers")

assertContains(
    source,
    "local function StyleShoppingCompareHeader(header, sr, sg, sb, sa, bgr, bgg, bgb, bga)",
    "shopping tooltip compare headers must have a dedicated styler")

assertContains(
    source,
    "SkinBase.StripTextures(header)",
    "shopping tooltip compare headers must strip Blizzard's tooltip-compare-label texture")

assertContains(
    source,
    "SkinBase.CreateBackdrop(header, sr, sg, sb, sa, bgr, bgg, bgb, 0.92)",
    "shopping tooltip compare headers must create QUI tab chrome")

assertContains(
    source,
    "SkinBase.SetPixelInsetPoints(bd, header, 3, 3, 3, 0)",
    "shopping tooltip compare headers must use the same bottom-merging tab inset as other tabs")

assertContains(
    source,
    "header.Label:SetTextColor(sr, sg, sb, 1)",
    "shopping tooltip compare header labels must use the active QUI border color")

assertContains(
    source,
    "StyleShoppingCompareHeader(tooltip.CompareHeader, sr, sg, sb, sa, bgr, bgg, bgb, bga)",
    "tooltip chrome application must style the shopping compare header when present")

print("OK: shopping_tooltip_compare_header_skinning_test")
