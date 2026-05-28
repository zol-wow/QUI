-- tests/unit/resourcebars_preview_driver_test.lua
-- Run: lua tests/unit/resourcebars_preview_driver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

local source = readAll("modules/resourcebars/settings/resource_bars_preview_driver.lua")

-- T1: file exists and exposes the public surface on ns.QUI_ResourceBarsPreview
assert(source:find("ns.QUI_ResourceBarsPreview", 1, true),
    "driver must publish ns.QUI_ResourceBarsPreview")

for _, fnName in ipairs({"Build", "Refresh", "Teardown", "GetCurrentPcts"}) do
    assert(source:find("function Module." .. fnName, 1, true)
        or source:find("Module." .. fnName .. " = function", 1, true),
        "driver must define Module." .. fnName)
end

-- T1: ticker frame must be created
assert(source:find("CreateFrame", 1, true),
    "driver must create at least one frame (the ticker)")
assert(source:find('SetScript("OnUpdate"', 1, true),
    "driver must wire an OnUpdate handler on its ticker")

-- T1: driver must NOT register any game events (cycle is time-driven)
assert(not source:find("RegisterEvent", 1, true),
    "driver must not register any game events (cycle is time-driven)")

-- T2: resourcebars.lua publishes ns.QUI_ResourceBars_Internal with all 9 helpers
local rb = readAll("modules/resourcebars/resourcebars.lua")
assert(rb:find("ns.QUI_ResourceBars_Internal", 1, true),
    "resourcebars.lua must export ns.QUI_ResourceBars_Internal for the driver")
local internalBlock = rb:match("ns%.QUI_ResourceBars_Internal%s*=%s*(%b{})")
assert(internalBlock,
    "ns.QUI_ResourceBars_Internal must be assigned a table literal {...}")
-- Strip Lua line comments so a commented-out key does not satisfy the check.
local blockNoComments = internalBlock:gsub("%-%-[^\n]*", "")
for _, sym in ipairs({
    "GetBarTexture",
    "tickedPowerTypes",
    "fragmentedPowerTypes",
    "ShouldSwapBars",
    "ShouldHidePrimaryOnSwap",
    "GetPrimaryResource",
    "GetSecondaryResource",
    "GetResourceColor",
    "GetSecondaryTextConfig",
}) do
    assert(blockNoComments:find(sym, 1, true),
        "ns.QUI_ResourceBars_Internal must export " .. sym)
end

-- T3: cycle catalog constants and helpers
assert(source:find("CYCLE_LENGTH = 10", 1, true)
    or source:find("CYCLE_LENGTH=10", 1, true),
    "driver CYCLE_LENGTH must be 10 (per spec)")
assert(source:find("local function ComputePcts", 1, true),
    "driver must define a local ComputePcts(t) function")
assert(source:find("local function AdvanceCycle", 1, true),
    "driver must define a local AdvanceCycle(elapsed) function")

-- T3: ComputePcts exposes the 2 pcts named in the spec
for _, sym in ipairs({"primaryPct", "secondaryPct"}) do
    assert(source:find(sym, 1, true),
        "ComputePcts / GetCurrentPcts must expose " .. sym)
end

-- T3: AdvanceCycle wraps t at CYCLE_LENGTH
assert(source:find("% CYCLE_LENGTH", 1, true)
    or source:find("math.fmod", 1, true),
    "AdvanceCycle must wrap state.cycle.t at CYCLE_LENGTH (use t % CYCLE_LENGTH)")

-- T4: preview-only constants and helpers migrated to driver
for _, sym in ipairs({
    "BAR_PAD_X",
    "PREVIEW_LABEL_GAP",
    "PREVIEW_SECTION_GAP",
    "PREVIEW_MIN_HORIZONTAL_LENGTH",
    "PREVIEW_MIN_THICKNESS",
    "PREVIEW_POWER_MAX_FALLBACKS",
    "POWER_DISPLAY_NAMES",
}) do
    assert(source:find(sym, 1, true),
        "driver must own preview constant " .. sym)
end

for _, fn in ipairs({
    "GetPreviewPowerMax",
    "MapPreviewMetric",
    "GetPreviewTextConfig",
    "GetPreviewDisplaySize",
    "GetPreviewBarColor",
    "ApplyPreviewTicks",
    "GetPreviewBgColor",
    "MockValueText",
    "MakeMockBar",
    "ApplyPreviewSectionLayout",
}) do
    assert(source:find("local function " .. fn, 1, true),
        "driver must own preview helper " .. fn)
end

-- T4: driver imports the cross-file Internal export
assert(source:find("ns.QUI_ResourceBars_Internal", 1, true),
    "driver must reference ns.QUI_ResourceBars_Internal for runtime-shared helpers")

-- T5: ApplyDynamics helper exists and writes to the expected primitives
assert(source:find("local function ApplyDynamics", 1, true),
    "driver must define a local ApplyDynamics function")
assert(source:find(":SetValue(", 1, true),
    "ApplyDynamics must drive bar:SetValue per tick")
assert(source:find(":SetText(MockValueText", 1, true)
    or source:find(":SetText( MockValueText", 1, true),
    "ApplyDynamics must drive section.val:SetText(MockValueText(...))")

-- T6: OnUpdate ticker dispatches AdvanceCycle + ApplyDynamics
local tickerStart = assert(source:find('SetScript("OnUpdate"', 1, true),
    "ticker SetScript('OnUpdate', ...) required")
local tickerEnd = assert(source:find("\n%s*end%)", tickerStart),
    "OnUpdate handler must terminate")
local advanceCall = source:find("AdvanceCycle", tickerStart, true)
assert(advanceCall and advanceCall < tickerEnd,
    "OnUpdate handler must call AdvanceCycle(elapsed)")
local applyCall = source:find("ApplyDynamics", tickerStart, true)
assert(applyCall and applyCall < tickerEnd,
    "OnUpdate handler must call ApplyDynamics(...)")

-- T7: Refresh body reads settings and calls ApplyDynamics
local refreshStart = assert(source:find("function Module.Refresh", 1, true),
    "Refresh definition required")
local refreshEnd = source:find("function Module.Teardown", refreshStart + 1, true)
    or #source
assert(source:find("powerBar", refreshStart, true)
    and source:find("powerBar", refreshStart, true) < refreshEnd,
    "Refresh must read core.db.profile.powerBar")
assert(source:find("secondaryPowerBar", refreshStart, true)
    and source:find("secondaryPowerBar", refreshStart, true) < refreshEnd,
    "Refresh must read core.db.profile.secondaryPowerBar")
local refreshApplyCall = source:find("ApplyDynamics", refreshStart, true)
assert(refreshApplyCall and refreshApplyCall < refreshEnd,
    "Refresh must call ApplyDynamics to paint the first frame after refresh")
assert(source:find("ApplyPreviewSectionLayout", refreshStart, true),
    "Refresh must call ApplyPreviewSectionLayout for each visible section")
assert(source:find("ApplyPreviewTicks", refreshStart, true),
    "Refresh must call ApplyPreviewTicks for each visible section")

-- T8: Build constructs chrome, mock sections, and calls Refresh
local buildStart = assert(source:find("function Module.Build", 1, true),
    "Build definition required")
local buildEnd = source:find("function Module.Refresh", buildStart + 1, true)
    or #source
assert(source:find("MakeMockBar", buildStart, true)
    and source:find("MakeMockBar", buildStart, true) < buildEnd,
    "Build must call MakeMockBar to create the two sections")
assert(source:find("OnSizeChanged", buildStart, true)
    and source:find("OnSizeChanged", buildStart, true) < buildEnd,
    "Build must hook OnSizeChanged to call Refresh on host resize")
assert(source:find("Module.Refresh()", buildStart, true)
    and source:find("Module.Refresh()", buildStart, true) < buildEnd,
    "Build must call Module.Refresh() to paint the first frame")

-- T9: preview text must render above the child StatusBar and mirror text styling.
assert(source:find("section.textFrame", 1, true),
    "mock bars must use a dedicated section.textFrame above the StatusBar for value text")
assert(source:find("section.textFrame:CreateFontString", 1, true),
    "value text must be created on section.textFrame, not directly on the bar container")
assert(source:find("section.textFrame:SetFrameLevel", 1, true),
    "section.textFrame must be frame-leveled above the StatusBar")
assert(source:find("section.val:SetTextColor", refreshStart, true)
    and source:find("textCustomColor", refreshStart, true),
    "Refresh must apply textCustomColor/textUseClassColor to preview value text")
assert(source:find("section.val:SetJustifyH", refreshStart, true),
    "Refresh must apply textAlign justification to preview value text")
assert(source:find('section.val:SetPoint("LEFT", section.textFrame, "LEFT", textX, textY)', refreshStart, true),
    "LEFT preview text placement must use textX/textY against section.textFrame")
assert(source:find('section.val:SetPoint("RIGHT", section.textFrame, "RIGHT", textX, textY)', refreshStart, true),
    "RIGHT preview text placement must use textX/textY against section.textFrame")

-- T10: preview value text must use the same runtime font family/outline as live bars.
assert(source:find("Helpers.GetGeneralFont", refreshStart, true),
    "Refresh must use Helpers.GetGeneralFont for preview value text")
assert(source:find("Helpers.GetGeneralFontOutline", refreshStart, true),
    "Refresh must use Helpers.GetGeneralFontOutline for preview value text")
assert(source:find("section.val:SetFont(valueFont, fontSize, valueFontOutline)", refreshStart, true),
    "preview value text must apply the runtime general font path and outline")

print("OK: resourcebars_preview_driver_test (T1-T10)")
