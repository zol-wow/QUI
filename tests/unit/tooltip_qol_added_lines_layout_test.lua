-- tests/unit/tooltip_qol_added_lines_layout_test.lua
-- Run: lua tests/unit/tooltip_qol_added_lines_layout_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local data = fh:read("*a")
    fh:close()
    return data
end

local source = readFile("QUI_QoL/qol/tooltip.lua")

assert(source:find("local function AddTooltipInfoLine", 1, true),
    "tooltip QoL additions should use a shared left-aligned wrapped line helper")

local forbiddenDoubleLines = {
    'tooltip:AddDoubleLine(label, string.format("%.1f", itemLevel)',
    'tooltip:AddDoubleLine("Target:", targetInfo.name',
    'tooltip:AddDoubleLine("Mount:", mountName',
    'tooltip:AddDoubleLine("M+ Rating:", string.format("%.1f", rating)',
    'tooltip:AddDoubleLine("Spell ID:", tostring(spellID)',
    'tooltip:AddDoubleLine("Icon ID:", tostring(iconID)',
    'tooltip:AddDoubleLine("Item ID:", tostring(itemID)',
}

for _, needle in ipairs(forbiddenDoubleLines) do
    assert(not source:find(needle, 1, true),
        "QUI-added tooltip info should not use right-column AddDoubleLine layout: " .. needle)
end

local requiredInfoLines = {
    'AddTooltipInfoLine(tooltip, label, string.format("%.1f", itemLevel)',
    'AddTooltipInfoLine(tooltip, "Target", targetInfo.name',
    'AddTooltipInfoLine(tooltip, "Mount", mountName',
    'AddTooltipInfoLine(tooltip, "M+ Rating", string.format("%.1f", rating)',
    'AddTooltipInfoLine(tooltip, "Spell ID", tostring(spellID)',
    'AddTooltipInfoLine(tooltip, "Icon ID", tostring(iconID)',
    'AddTooltipInfoLine(tooltip, "Item ID", tostring(itemID)',
}

for _, needle in ipairs(requiredInfoLines) do
    assert(source:find(needle, 1, true),
        "expected left-aligned wrapped info line call missing: " .. needle)
end

local forbiddenProviderName = string.char(82, 97, 105, 100, 101, 114, 73, 79)
assert(not source:find(forbiddenProviderName, 1, true),
    "tooltip source must not hardcode third-party addon names")

local ratingStart = assert(source:find("local function GetPlayerMythicRating", 1, true),
    "rating resolver should exist")
local ratingEnd = assert(source:find("local function AddUnitTooltipInfoToTooltip", ratingStart, true),
    "rating resolver should remain bounded before unit info handling")
local ratingBody = source:sub(ratingStart, ratingEnd)
local providerLookup = ratingBody:find("rawget(_G, string.char(82, 97, 105, 100, 101, 114, 73, 79))", 1, true)
local nativeLookup = ratingBody:find("C_PlayerInfo.GetPlayerMythicPlusRatingSummary", 1, true)
assert(providerLookup,
    "rating resolver should restore external score provider compatibility")
assert(nativeLookup,
    "rating resolver should keep the native client rating fallback")
assert(providerLookup < nativeLookup,
    "external score provider should be preferred before native client rating fallback")

assert(source:find("local function IsInternalEmbeddedItemTooltipFrame(tooltip)", 1, true),
    "tooltip QoL must identify Blizzard embedded item reward tooltip frames")

local idProcessStart = assert(source:find("local function ShouldProcessTooltipIDs", 1, true),
    "tooltip ID processing gate should exist")
local idProcessEnd = assert(source:find("local function ResolveSpellIDFromTooltipData", idProcessStart, true),
    "tooltip ID processing gate should remain bounded before ID resolvers")
local idProcessBody = source:sub(idProcessStart, idProcessEnd)
assert(idProcessBody:find("IsInternalEmbeddedItemTooltipFrame(tooltip)", 1, true),
    "tooltip ID injection must skip embedded quest reward item tooltips before Blizzard width sizing")

local extrasStart = assert(source:find("local function HandleUnitExtrasPost", 1, true),
    "unit extras post handler should exist")
local extrasEnd = assert(source:find("local function HandleUnitHealthPost", extrasStart, true),
    "unit extras post handler should remain bounded before health handling")
local extrasBody = source:sub(extrasStart, extrasEnd)

local immediateExtras = extrasBody:find("AddUnitTooltipInfoToTooltip(tooltip, unit, settings)", 1, true)
local deferredExtras = extrasBody:find("ScheduleDeferredUnitInfo(tooltip, unit)", 1, true)
assert(immediateExtras,
    "unit tooltip extras should try cheap data enrichment during TooltipDataProcessor before deferring")
assert(deferredExtras,
    "unit tooltip extras should keep deferred enrichment for async/late data")
assert(immediateExtras < deferredExtras,
    "immediate unit enrichment should run before deferred enrichment is scheduled")

print("tooltip_qol_added_lines_layout_test.lua: ok")
