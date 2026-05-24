-- tests/unit/cdm_composer_preview_driver_test.lua
-- Run: lua tests/unit/cdm_composer_preview_driver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    data = data:gsub("\r\n", "\n")
    return data
end

local source = readAll("modules/cdm/settings/composer_preview_driver.lua")

-- T4: file exists and exposes the public surface on ns.CDMComposerPreview
assert(source:find("ns.CDMComposerPreview", 1, true),
    "driver must publish ns.CDMComposerPreview")

for _, fnName in ipairs({"Build", "Refresh", "Teardown", "SetScale"}) do
    assert(source:find("function CDMComposerPreview." .. fnName, 1, true)
        or source:find("CDMComposerPreview." .. fnName .. " = function", 1, true),
        "driver must define CDMComposerPreview." .. fnName)
end

-- T4: ticker frame must be created (driver-owned, parented to gridArea on Build)
assert(source:find("CreateFrame", 1, true),
    "driver must create at least one frame (the ticker)")
assert(source:find('SetScript("OnUpdate"', 1, true),
    "driver must wire an OnUpdate handler on its ticker")

-- T4: driver must NOT register any game events (PLAYER_*, UNIT_*, SPELL_*)
assert(not source:find("RegisterEvent", 1, true),
    "driver must not register any game events (cycle is time-driven)")

-- T4: driver must NOT call into cdm_runtime
assert(not source:find('require[("]cdm_runtime', 1, false),
    "driver must not require cdm_runtime")

-- T5: Refresh must dispatch on container type
for _, marker in ipairs({"cooldown", "auraBar", "customBar"}) do
    assert(source:find('"' .. marker .. '"', 1, true),
        "driver Refresh must branch on container type \"" .. marker .. "\"")
end

-- T5: icon acquisition goes through the preview-scoped factory entry
assert(source:find("CDMIconFactory.AcquireForPreview", 1, true),
    "driver must acquire icons via CDMIconFactory.AcquireForPreview")
assert(source:find("CDMIconFactory.ReleaseForPreview", 1, true),
    "driver Teardown must release icons via CDMIconFactory.ReleaseForPreview")

-- T5: Teardown must clear iconState and previewIcons
local teardownStart = assert(source:find("function CDMComposerPreview.Teardown", 1, true),
    "Teardown definition required")
local teardownEnd = assert(source:find("\nend\n", teardownStart, true), "Teardown end")
assert(source:find("state.previewIcons", teardownStart, true) and
       source:find("state.previewIcons", teardownStart, true) < teardownEnd,
    "Teardown must clear state.previewIcons")
assert(source:find("state.iconState", teardownStart, true) and
       source:find("state.iconState", teardownStart, true) < teardownEnd,
    "Teardown must clear state.iconState")

-- T6: bar acquisition uses CDMBars.CreateForPreview + CDMBars.ConfigureBar
assert(source:find("CDMBars.CreateForPreview", 1, true),
    "driver must construct bars via CDMBars.CreateForPreview")
assert(source:find("CDMBars.ConfigureBar", 1, true),
    "driver must style bars via CDMBars.ConfigureBar")

-- T6: bar path lives in its own Refresh helper
assert(source:find("RefreshBars", 1, true),
    "driver must factor a RefreshBars helper")

-- T7: preview glow must use a scoped key, never the runtime glow key
assert(source:find('_QUIComposerPreviewGlow', 1, true),
    "driver must use \"_QUIComposerPreviewGlow\" as its LibCustomGlow key")
assert(not source:find('"_QUICustomGlow"', 1, true) and not source:find("'_QUICustomGlow'", 1, true),
    "driver must NEVER use the runtime glow key \"_QUICustomGlow\"")

-- T7: glow helper accesses LibCustomGlow via LibStub
assert(source:find('LibStub("LibCustomGlow-1.0"', 1, true),
    "driver must access LibCustomGlow via LibStub")

-- T7: helper supports all three glow styles
for _, style in ipairs({"PixelGlow_Start", "AutoCastGlow_Start", "ButtonGlow_Start"}) do
    assert(source:find(style, 1, true),
        "driver must dispatch glow style \"" .. style .. "\"")
end
for _, style in ipairs({"PixelGlow_Stop", "AutoCastGlow_Stop", "ButtonGlow_Stop"}) do
    assert(source:find(style, 1, true),
        "driver must stop glow style \"" .. style .. "\"")
end

-- T8: cycle script catalog tokens present
local cooldownTokens = {"cooldown", "ready_glow", "charges", "idle"}
for _, tok in ipairs(cooldownTokens) do
    assert(source:find('"' .. tok .. '"', 1, true),
        "cooldown cycle must reference phase \"" .. tok .. "\"")
end
local auraTokens = {"applying", "stacking_up", "ticking_down", "expiring"}
for _, tok in ipairs(auraTokens) do
    assert(source:find('"' .. tok .. '"', 1, true),
        "aura cycle must reference phase \"" .. tok .. "\"")
end

-- T8: real Blizzard cooldown swipe is exercised
assert(source:find(":SetCooldown(", 1, true),
    "cycle must drive icon.Cooldown:SetCooldown(start, duration) for real swipe")

-- T8: stack count text is exercised
assert(source:find("StackText:SetText", 1, true),
    "aura cycle must write to StackText for stack ramp")

-- T8: glow-owner rotation present
assert(source:find("glowOwnerIdx", 1, true),
    "cycle must track a rotating glow owner index")

-- T8: ticker dispatch on scriptKind
assert(source:find('scriptKind == "cooldown"', 1, true)
    or source:find("scriptKind] == \"cooldown\"", 1, true),
    "ticker must dispatch on scriptKind")

-- T9: bar cycle phase tokens present
local barTokens = {"draining"}
for _, tok in ipairs(barTokens) do
    assert(source:find('"' .. tok .. '"', 1, true),
        "bar cycle must reference phase \"" .. tok .. "\"")
end

-- T9: bar cycle drives StatusBar:SetValue
assert(source:find("StatusBar:SetValue", 1, true)
    or source:find(".StatusBar:SetValue", 1, true),
    "bar cycle must drive StatusBar:SetValue for animated fill")

-- T9: time text countdown for draining bars
assert(source:find("DurationText:SetText", 1, true)
    or source:find(".DurationText:SetText", 1, true),
    "bar cycle must update DurationText during draining")

---------------------------------------------------------------------------
-- T10: bar preview must be visible after Refresh.
--
-- Regression for "buff bar container preview not showing previews for
-- spells added": CDMBars.ConfigureBar reads bar._active and, with the
-- trackedBar default inactiveMode="hide", applies SetAlpha(0) on inactive
-- bars. New bars start with _active = false, so without the driver forcing
-- _active = true the entire preview stack is at alpha 0 → invisible.
--
-- The same RefreshBars path also has to bind IconTexture and NameText from
-- the entry, since ConfigureBar is content-agnostic (it only handles
-- size/colour/font/alpha). The runtime sets these in its own update path,
-- which the preview driver intentionally bypasses.
---------------------------------------------------------------------------
local refreshBarsStart = assert(
    source:find("local function RefreshBars", 1, true),
    "RefreshBars helper must exist")
local refreshBarsEnd = assert(
    source:find("\nend\n", refreshBarsStart, true),
    "RefreshBars must terminate with end")
local refreshBarsBody = source:sub(refreshBarsStart, refreshBarsEnd)

assert(refreshBarsBody:find("_active", 1, true),
    "RefreshBars must force bar._active = true so ConfigureBar does not " ..
    "apply the inactive-hide alpha (which leaves preview bars invisible)")

assert(refreshBarsBody:find("IconTexture", 1, true),
    "RefreshBars must populate bar.IconTexture from the entry — ConfigureBar " ..
    "does not bind the icon image, so without this the bar swatch is blank")

assert(refreshBarsBody:find("NameText", 1, true),
    "RefreshBars must populate bar.NameText from the entry — ConfigureBar " ..
    "does not bind spell-name text, so without this the bar shows no name")

print("OK: cdm_composer_preview_driver_test (T4-T10)")
