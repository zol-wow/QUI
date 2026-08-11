-- tests/unit/resourcebars_value_path_no_layout_test.lua
-- Run: lua tests/unit/resourcebars_value_path_no_layout_test.lua
--
-- The old renderers re-ran SetOrientation / ClearAllPoints / SetPoint /
-- SetWidth / SetHeight / SetStatusBarTexture / font + text placement /
-- tick layout on EVERY power event. After the split, the hot value paths
-- (UpdatePowerBarValue / UpdateSecondaryPowerBarValue) may only touch
-- fill, color, text CONTENT, animation timers, and value-driven unnamed
-- child displays (fragments / charged overlays, via method calls) — never
-- the named bar's layout. This test extracts each value function's body
-- and rejects layout verbs.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local function extract(startMarker, endMarker)
    local s = src:find(startMarker, 1, true)
    assert(s, "missing marker: " .. startMarker)
    local e = src:find(endMarker, s + 1, true)
    assert(e, "missing marker: " .. endMarker)
    return src:sub(s, e - 1)
end

local forbidden = {
    ":SetPoint(", ":ClearAllPoints(", ":SetWidth(", ":SetHeight(",
    ":SetOrientation(", ":SetStatusBarTexture(", "CJKFont(",
    "ApplyPowerBarTextPlacement(", "PowerBarTicks(", "PowerBarIndicators(",
    "CreateBackdropBorder", "SetSnappedPoint(", "CreateFragmentedPowerBars(",
    "TriggerSwapReciprocalUpdate(", "ScheduleNaturalSlotCapture(",
    "SyncSwapAnchorOwnership(",
}

local primaryValue = extract("function QUICore:UpdatePowerBarValue(forceShown)",
    "function QUICore:UpdatePowerBar()")
for _, token in ipairs(forbidden) do
    assert(not primaryValue:find(token, 1, true),
        "layout call in primary value path: " .. token)
end

-- The full renderer must run the value path inline so config changes
-- re-render values immediately.
local primaryFull = extract("function QUICore:UpdatePowerBar()",
    "function QUICore:UpdatePowerBarTicks(")
assert(primaryFull:find("self:UpdatePowerBarValue(true)", 1, true),
    "UpdatePowerBar must run the value pass inline")
-- Config-path propagation to a lockedToPrimary secondary is preserved.
assert(primaryFull:find("secondaryCfg.lockedToPrimary", 1, true),
    "config-path lockedToPrimary propagation must survive the split")
-- ...and it must be the ONLY propagation site left (the old secret-path
-- duplicate at the early return is folded into the shared tail).
local first = primaryFull:find("secondaryCfg.lockedToPrimary", 1, true)
assert(not primaryFull:find("lockedToPrimary", first + 30, true),
    "UpdatePowerBar must have exactly one propagation site")

local secondaryValue = extract("function QUICore:UpdateSecondaryPowerBarValue(forceShown)",
    "function QUICore:UpdateSecondaryPowerBar()")
for _, token in ipairs(forbidden) do
    assert(not secondaryValue:find(token, 1, true),
        "layout call in secondary value path: " .. token)
end
-- Value-driven displays that must stay on the hot path.
assert(secondaryValue:find("self:UpdateFragmentedPowerDisplay(bar, resource, isVertical)", 1, true),
    "fragment fills must update on the value path")
assert(secondaryValue:find("self:UpdateChargedComboPoints(bar, resource, max, current, isVertical)", 1, true),
    "charged combo overlays must update on the value path")

local secondaryFull = extract("function QUICore:UpdateSecondaryPowerBar()",
    "function QUICore:OnUnitPower(event, unit, powerType)")
assert(secondaryFull:find("self:UpdateSecondaryPowerBarValue(true)", 1, true),
    "UpdateSecondaryPowerBar must run the value pass inline")
assert(secondaryFull:find("bar._cachedIsVertical = isVertical", 1, true),
    "config path must cache resolved orientation for the value path")

print("PASS resourcebars_value_path_no_layout_test")
