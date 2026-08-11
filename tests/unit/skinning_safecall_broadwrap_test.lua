-- tests/unit/skinning_safecall_broadwrap_test.lua
-- Source-text contract pins for the Task 1c whole-function pcall->SafeCall
-- wrapper swap in modules/skinning/frames/auctionhouse.lua and
-- modules/skinning/system/tooltips.lua. Run: lua5.1 tests/unit/skinning_safecall_broadwrap_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end
local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

local ahSrc = readAll("modules/skinning/frames/auctionhouse.lua")
local ttSrc = readAll("modules/skinning/system/tooltips.lua")

---------------------------------------------------------------------------
-- auctionhouse.lua: five sub-panel skinners routed through SafeCall.
---------------------------------------------------------------------------
check("pin: ns.SafeCall(\"best-effort-style\", SkinCategoriesList) present",
    ahSrc:find('ns.SafeCall("best-effort-style", SkinCategoriesList)', 1, true) ~= nil)
check("pin: ns.SafeCall(\"best-effort-style\", SkinSearchBar) present",
    ahSrc:find('ns.SafeCall("best-effort-style", SkinSearchBar)', 1, true) ~= nil)
check("pin: ns.SafeCall(\"best-effort-style\", SkinBrowsePanel) present",
    ahSrc:find('ns.SafeCall("best-effort-style", SkinBrowsePanel)', 1, true) ~= nil)
check("pin: ns.SafeCall(\"best-effort-style\", SkinSellPanel) present",
    ahSrc:find('ns.SafeCall("best-effort-style", SkinSellPanel)', 1, true) ~= nil)
check("pin: ns.SafeCall(\"best-effort-style\", SkinAuctionsPanel) present",
    ahSrc:find('ns.SafeCall("best-effort-style", SkinAuctionsPanel)', 1, true) ~= nil)
check("pin: NO bare pcall(Skin remains in auctionhouse.lua",
    ahSrc:find("pcall(Skin", 1, true) == nil)

---------------------------------------------------------------------------
-- tooltips.lua: five sites routed through SafeCall (two hot-path
-- ApplyTooltipChrome call sites, the close-button skin, ShowExistingChrome,
-- and the font-queue-flush ApplyFontSize).
---------------------------------------------------------------------------
check("pin: tooltips.lua ns.SafeCall(\"best-effort-style\", ApplyTooltipChrome, tooltip) occurs twice (style + combat-refresh)",
    select(2, ttSrc:gsub('ns%.SafeCall%("best%-effort%-style", ApplyTooltipChrome, tooltip%)', "")) == 2)
check("pin: ns.SafeCall(\"best-effort-style\", SkinBase.SkinCloseButton, closeButton) present",
    ttSrc:find('ns.SafeCall("best-effort-style", SkinBase.SkinCloseButton, closeButton)', 1, true) ~= nil)
check("pin: ns.SafeCall(\"best-effort-style\", ShowExistingChrome, tooltip) present",
    ttSrc:find('ns.SafeCall("best-effort-style", ShowExistingChrome, tooltip)', 1, true) ~= nil)
check("pin: ns.SafeCall(\"best-effort-style\", ApplyFontSize, tt) present",
    ttSrc:find('ns.SafeCall("best-effort-style", ApplyFontSize, tt)', 1, true) ~= nil)

check("pin: NO bare pcall(ApplyTooltipChrome remains in tooltips.lua",
    ttSrc:find("pcall(ApplyTooltipChrome", 1, true) == nil)
check("pin: NO bare pcall(ApplyFontSize remains in tooltips.lua",
    ttSrc:find("pcall(ApplyFontSize", 1, true) == nil)
check("pin: NO bare pcall(ShowExistingChrome remains in tooltips.lua",
    ttSrc:find("pcall(ShowExistingChrome", 1, true) == nil)
check("pin: NO bare pcall(SkinBase.SkinCloseButton remains in tooltips.lua",
    ttSrc:find("pcall(SkinBase.SkinCloseButton", 1, true) == nil)

---------------------------------------------------------------------------
-- Guard against over-conversion: tooltips.lua's legitimate GETTER pcalls
-- (GetName, GetWidth, GetParent, GetNumChildren, GetObjectType, IsShown,
-- etc. — the "ok-checked feeding NineSlice/branch decisions" class) are
-- the analyzer-provable probe-read idiom and must survive untouched;
-- SetPixelPoint was a discarded-result SETTER, converted by Task 45c
-- (safecall_migration_t45c_test.lua pins the exact SafeCall form). Count
-- pin, not enumeration, so unrelated edits don't silently break this test.
---------------------------------------------------------------------------
local ttPcallCount = select(2, ttSrc:gsub("pcall%(", ""))
check("pin: tooltips.lua retains its legit getter pcalls (count >= 15, saw " .. ttPcallCount .. ")",
    ttPcallCount >= 15)
check("pin: tooltips.lua's SetPixelPoint site was converted by Task 45c (no longer a bare pcall)",
    ttSrc:find('SafeCall("best-effort-style", SkinBase.SetPixelPoint, closeButton, "TOPRIGHT", tooltip, "TOPRIGHT", -2, -2)', 1, true) ~= nil)

if fails > 0 then error(fails .. " failure(s) in skinning_safecall_broadwrap_test") end
print("OK: skinning_safecall_broadwrap_test (all checks passed)")
