-- tests/unit/actionbars_preview_driver_test.lua
-- Run: lua tests/unit/actionbars_preview_driver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

local source = readAll("QUI_ActionBars/actionbars/settings/action_bars_preview_driver.lua")

-- T1: file exists and exposes the public surface on ns.QUI_ActionBarsPreviewDriver
assert(source:find("ns.QUI_ActionBarsPreviewDriver", 1, true),
    "driver must publish ns.QUI_ActionBarsPreviewDriver")

for _, fnName in ipairs({"Build", "Refresh", "SetSelectedBar", "Teardown", "IsPreviewable"}) do
    assert(source:find("function ActionBarsPreviewDriver." .. fnName, 1, true)
        or source:find("ActionBarsPreviewDriver." .. fnName .. " = function", 1, true),
        "driver must define ActionBarsPreviewDriver." .. fnName)
end

-- T1: ticker frame must be created (driver-owned, parented to host on Build)
assert(source:find("CreateFrame", 1, true),
    "driver must create at least one frame (the ticker)")
assert(source:find('SetScript("OnUpdate"', 1, true),
    "driver must wire an OnUpdate handler on its ticker")

-- T1: driver must NOT register any game events (PLAYER_*, UNIT_*, SPELL_*)
assert(not source:find("RegisterEvent", 1, true),
    "driver must not register any game events (cycle is time-driven)")

-- T2: BAR_OFFSETS migrated to driver
assert(source:find("BAR_OFFSETS", 1, true),
    "driver must own BAR_OFFSETS after T2 migration")
for _, barKey in ipairs({"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8"}) do
    assert(source:find(barKey, 1, true),
        "driver BAR_OFFSETS must cover " .. barKey)
end

-- T2: live-mirror helpers migrated
for _, fn in ipairs({
    "GetPreviewSourceButton",
    "GetPreviewActionSlot",
    "GetPreviewSlot",
    "GetPreviewDisplayedTexture",
    "GetPreviewBindingText",
    "GetPreviewMacroText",
    "GetPreviewCountText",
    "GetPreviewFontSettings",
    "SetPreviewTextStyle",
    "GetPreviewEffectiveSettings",
}) do
    assert(source:find("local function " .. fn, 1, true)
        or source:find(fn .. " = function", 1, true),
        "driver must own helper " .. fn .. " after T2 migration")
end

-- T2: IsPreviewable now backed by BAR_OFFSETS
assert(source:find("BAR_OFFSETS%[barKey%]"),
    "driver IsPreviewable must read BAR_OFFSETS[barKey]")

-- T2: live-mirror helpers removed from content.lua
local content = readAll("QUI_ActionBars/actionbars/settings/action_bars_content.lua")
for _, fn in ipairs({
    "GetPreviewSourceButton",
    "GetPreviewActionSlot",
    "GetPreviewDisplayedTexture",
    "GetPreviewBindingText",
    "GetPreviewMacroText",
    "GetPreviewCountText",
    "GetPreviewFontSettings",
    "SetPreviewTextStyle",
}) do
    assert(not content:find("local function " .. fn, 1, true),
        "content.lua must no longer define " .. fn .. " (migrated to driver)")
end

-- T3: driver Build must construct MAX_PREVIEW_BUTTONS buttons
assert(source:find("for i = 1, MAX_PREVIEW_BUTTONS do", 1, true),
    "driver Build must contain the MAX_PREVIEW_BUTTONS construction loop")
assert(source:find('CreateTexture(nil, "BACKGROUND"', 1, true),
    "driver Build must create per-button backdrop texture")
assert(source:find("PREVIEW_TEXTURES.normal", 1, true)
    or source:find('"Normal"', 1, true),
    "driver Build must set the Normal texture on each preview button")
assert(source:find("PREVIEW_TEXTURES.gloss", 1, true)
    or source:find('"Gloss"', 1, true),
    "driver Build must set the Gloss texture on each preview button")

-- T3: driver Refresh body lives in the driver, not content.lua
assert(source:find("ActionBarsPreviewDriver.Refresh", 1, true),
    "driver Refresh must be a named function in the driver")
assert(source:find("GetPreviewEffectiveSettings", 1, true),
    "driver Refresh must consult GetPreviewEffectiveSettings")
assert(source:find("GetPreviewSourceButton", 1, true),
    "driver Refresh must look up the live source button")

-- T3: content.lua RefreshPreview is now a one-liner that calls driver.Refresh
content = readAll("QUI_ActionBars/actionbars/settings/action_bars_content.lua")
assert(content:find("ns.QUI_ActionBarsPreviewDriver.Build", 1, true),
    "content.lua BuildActionBarsPreview must call driver.Build")
assert(content:find("ns.QUI_ActionBarsPreviewDriver.Refresh", 1, true),
    "content.lua must call driver.Refresh")

-- T4: Cooldown child attached to each preview button in Build
assert(source:find('CreateFrame("Cooldown"', 1, true),
    "driver Build must attach a Cooldown child (CooldownFrameTemplate) to each preview button")
assert(source:find('"CooldownFrameTemplate"', 1, true),
    "driver Build must specify CooldownFrameTemplate for the Cooldown child")

-- T4: per-button cycle state initialization
assert(source:find("phaseIdx", 1, true),
    "per-button state must track phaseIdx")
assert(source:find("cooldownDur", 1, true),
    "per-button state must record a randomized cooldownDur per button")
assert(source:find("math.random", 1, true),
    "per-button state must randomize initial phase offset")

-- T4: SetSelectedBar resets cycle state
local setBarStart = assert(source:find("function ActionBarsPreviewDriver.SetSelectedBar", 1, true),
    "SetSelectedBar definition required")
local setBarEnd = assert(source:find("\nend\n", setBarStart, true), "SetSelectedBar end")
local resetCall = source:find("state.buttonState", setBarStart, true)
assert(resetCall and resetCall < setBarEnd,
    "SetSelectedBar must clear state.buttonState (per-button cycle reset)")

-- T5: cycle script catalog must define ACTION_BUTTON_PHASES with idle + cooldown
assert(source:find("ACTION_BUTTON_PHASES", 1, true),
    "driver must define ACTION_BUTTON_PHASES cycle catalog")
for _, phase in ipairs({"idle", "cooldown"}) do
    assert(source:find('"' .. phase .. '"', 1, true),
        "cycle script must reference phase \"" .. phase .. "\"")
end

-- T5: cooldown phase exercises real Blizzard Cooldown swipe
assert(source:find(":SetCooldown(", 1, true),
    "cooldown phase must drive cooldown:SetCooldown(start, duration) for real swipe")

-- T5: icon desaturation during cooldown
assert(source:find("SetDesaturated", 1, true),
    "cooldown phase must desaturate the icon while swiping")

-- T5: OnUpdate dispatcher iterates state.previewButtons
local tickerStart = assert(source:find('SetScript("OnUpdate"', 1, true),
    "OnUpdate handler definition required")
local tickerEnd = assert(source:find("\n%s*end%)", tickerStart),
    "OnUpdate handler must terminate")
local advanceCall = source:find("state.previewButtons", tickerStart)
assert(advanceCall and advanceCall < tickerEnd,
    "OnUpdate handler must iterate state.previewButtons")

-- T6: ready_glow phase token
assert(source:find('"ready_glow"', 1, true),
    "cycle must reference phase \"ready_glow\"")

-- T6: glow uses LibCustomGlow via LibStub
assert(source:find('LibStub("LibCustomGlow-1.0"', 1, true),
    "driver must access LibCustomGlow via LibStub")

-- T6: preview glow must use a scoped key
assert(source:find('_QUIActionBarsPreviewGlow', 1, true),
    "driver must use \"_QUIActionBarsPreviewGlow\" as its LibCustomGlow key")

-- T6: all three glow styles are dispatched and stopped
for _, fn in ipairs({"PixelGlow_Start", "AutoCastGlow_Start", "ButtonGlow_Start"}) do
    assert(source:find(fn, 1, true),
        "driver must dispatch glow style \"" .. fn .. "\"")
end
for _, fn in ipairs({"PixelGlow_Stop", "AutoCastGlow_Stop", "ButtonGlow_Stop"}) do
    assert(source:find(fn, 1, true),
        "driver must stop glow style \"" .. fn .. "\"")
end

-- T6: glow-owner rotation present
assert(source:find("glowOwnerIdx", 1, true),
    "cycle must track a rotating glow-owner index")

-- T7: charges phase token
assert(source:find('"charges"', 1, true),
    "cycle must reference phase \"charges\"")

-- T7: charge-owner rotation tracked separately
assert(source:find("chargeOwnerIdx", 1, true),
    "cycle must track a rotating charge-owner index")

-- T7: charge count text exercises pb.count fontstring
assert(source:find("count:SetText", 1, true)
    or source:find(".count:SetText", 1, true),
    "charges phase must write to pb.count via SetText")

-- T8: push_flash phase token
assert(source:find('"push_flash"', 1, true),
    "cycle must reference phase \"push_flash\"")

-- T8: push_flash uses SetVertexColor on the normal texture
assert(source:find("normal:SetVertexColor", 1, true)
    or source:find(".normal:SetVertexColor", 1, true),
    "push_flash phase must drive pb.normal:SetVertexColor for the flash effect")

print("OK: actionbars_preview_driver_test")
