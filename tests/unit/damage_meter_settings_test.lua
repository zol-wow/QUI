-- tests/unit/damage_meter_settings_test.lua
-- Run: lua tests/unit/damage_meter_settings_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

-- Settings content file exists and references the three Phase 1 widgets
local contentSrc = readAll("modules/damage_meter/settings/damage_meter_content.lua")
assert(contentSrc:find("visibility", 1, true),     "settings must wire visibility")
assert(contentSrc:find("barHeight", 1, true),      "settings must wire barHeight")
assert(contentSrc:find("refreshRateCombat", 1, true),
    "settings must wire refreshRateCombat")

-- XML loader picked it up
local xmlSrc = readAll("modules/damage_meter/damage_meter.xml")
assert(xmlSrc:find('Script file="settings/damage_meter_content.lua"', 1, true)
    or xmlSrc:find('Script file="settings\\damage_meter_content.lua"', 1, true),
    "damage_meter.xml must load the settings content file")

-- Settings content now lives in the module package (loaded by the main addon
-- via damage_meter.xml, asserted above) rather than QUI_Options/options.xml.

-- T12 (Phase 2): Behavior section additions
assert(contentSrc:find("refreshRateIdle", 1, true),
    "settings must wire refreshRateIdle")
assert(contentSrc:find("showHoverTooltip", 1, true),
    "settings must wire showHoverTooltip")
assert(contentSrc:find("showPinnedSelf", 1, true),
    "settings must wire showPinnedSelf")
assert(contentSrc:find("numberFormat", 1, true),
    "settings must wire numberFormat")
assert(contentSrc:find("iconStyle", 1, true),
    "settings must wire iconStyle")
-- All settings changes route through RefreshAll
assert(contentSrc:find("RefreshAll", 1, true),
    "settings must call WindowManager:RefreshAll on change")

-- T13 (Phase 2): Appearance: Bars collapsible
assert(contentSrc:find('"Appearance: Bars"', 1, true),
    "settings must add 'Appearance: Bars' collapsible")
assert(contentSrc:find("barSpacing", 1, true),
    "settings must wire barSpacing slider")
assert(contentSrc:find("textures", 1, true),
    "settings must wire textures.bar dropdown")
assert(contentSrc:find("useClassColor", 1, true),
    "settings must wire useClassColor checkbox")
assert(contentSrc:find("barColorAccent", 1, true),
    "settings must wire barColorAccent checkbox")
assert(contentSrc:find("barColor", 1, true),
    "settings must wire barColor picker")
assert(contentSrc:find("barFillAlpha", 1, true),
    "settings must wire barFillAlpha slider")

-- T14 (Phase 2): Appearance: Fonts collapsible
assert(contentSrc:find('"Appearance: Fonts"', 1, true),
    "settings must add 'Appearance: Fonts' collapsible")
assert(contentSrc:find("fonts", 1, true),
    "settings must wire fonts table")
for _, label in ipairs({ '"Row Name', '"Row Value', '"Header' }) do
    assert(contentSrc:find(label, 1, true),
        "fonts section must include label " .. label)
end

-- T15 (Phase 2): Appearance: Colors collapsible
assert(contentSrc:find('"Appearance: Colors"', 1, true),
    "settings must add 'Appearance: Colors' collapsible")
for _, key in ipairs({"bg", "border", "rowName", "rowValue", "headerText"}) do
    assert(contentSrc:find(key, 1, true),
        "Colors section must wire colors." .. key)
end

-- Regression: disabling the feature toggle must take effect immediately by
-- despawning all windows in-session AND must restore the damageMeterEnabled
-- CVar so Blizzard's stock meter loads on next reload. Prior to this, the
-- toggle only flipped db.enabled and showed a reload prompt; windows lingered
-- on screen until the user reloaded, and the CVar stayed suppressed.
assert(contentSrc:find("WindowManager:DespawnAll", 1, true),
    "SetDamageMeterEnabled must call WindowManager:DespawnAll on disable")
assert(contentSrc:find("ApplyBlizzardSuppression(false)", 1, true),
    "SetDamageMeterEnabled must call ApplyBlizzardSuppression(false) on disable to restore the CVar")

-- DespawnAll is a real method on WindowManager (not just a string match above).
local coreSrc2 = readAll("modules/damage_meter/damage_meter.lua")
assert(coreSrc2:find("function WindowManager:DespawnAll", 1, true),
    "WindowManager:DespawnAll must be defined in damage_meter.lua")

-- v38 migration: maxVisibleRows is dropped from saved window entries so the
-- dead key doesn't linger in savedvars. Source-pattern assertion: the migration
-- function exists, is wired into the linear gate chain, and the schema version
-- was bumped.
local migSrc = readAll("core/migrations.lua")
assert(migSrc:find("CURRENT_SCHEMA_VERSION = 40", 1, true),
    "CURRENT_SCHEMA_VERSION must be bumped to 40")
assert(migSrc:find("local function DropDamageMeterMaxVisibleRows", 1, true),
    "v38 migration function DropDamageMeterMaxVisibleRows must be defined")
assert(migSrc:find("if stored < 38 then DropDamageMeterMaxVisibleRows", 1, true),
    "v38 migration must be wired into the linear gate chain")

-- Task 4: Scroll infrastructure. Rows live inside a ScrollFrame with a
-- scroll-child Frame. The scrollFrame's parent is the window frame; the
-- scrollContent is the scroll child. Rows are created as children of
-- self.scrollContent.
local coreSrc3 = readAll("modules/damage_meter/damage_meter.lua")
assert(coreSrc3:find('CreateFrame("ScrollFrame"', 1, true),
    "Window:New must create a ScrollFrame for the row viewport")
assert(coreSrc3:find("SetScrollChild(scrollContent)", 1, true),
    "ScrollFrame must have its scroll child set")
assert(coreSrc3:find("self%.scrollFrame", 1, false),
    "Window must expose self.scrollFrame")
assert(coreSrc3:find("self%.scrollContent", 1, false),
    "Window must expose self.scrollContent")
assert(coreSrc3:find("local parent = self%.scrollContent", 1, false),
    "_BuildRow must alias parent = self.scrollContent")
assert(coreSrc3:find('CreateFrame%("Button", nil, parent%)', 1, false),
    "_BuildRow must parent rows to the scrollContent alias")

-- Task 5: Mouse wheel scrolling. scrollFrame must enable mouse wheel and set
-- an OnMouseWheel handler that calls SetVerticalScroll.
assert(coreSrc3:find("scrollFrame:EnableMouseWheel(true)", 1, true),
    "scrollFrame must enable mouse wheel")
assert(coreSrc3:find('scrollFrame:SetScript("OnMouseWheel"', 1, true),
    "scrollFrame must wire an OnMouseWheel handler")
assert(coreSrc3:find("SetVerticalScroll", 1, true),
    "OnMouseWheel handler must call SetVerticalScroll")

-- Task 6: Thumb scrollbar. Thin accent thumb at the right edge, auto-hides
-- when content fits. _UpdateScrollThumb method exists and is called from at
-- least one place (the OnSizeChanged hook).
assert(coreSrc3:find("function Window:_UpdateScrollThumb", 1, true),
    "Window:_UpdateScrollThumb must be defined")
assert(coreSrc3:find("self%.scrollBar", 1, false),
    "Window must expose self.scrollBar")
assert(coreSrc3:find("self:_UpdateScrollThumb()", 1, true),
    "OnSizeChanged or similar must call _UpdateScrollThumb")

-- Task 7: maxVisibleRows is gone from runtime code (kept only as a v38
-- migration target). The cap was replaced by scrollable rows; window height
-- alone decides what renders without scrolling.
assert(not coreSrc3:find("maxVisibleRows", 1, true),
    "maxVisibleRows must not be referenced in damage_meter.lua after Task 7")
local defaultsSrc = readAll("core/defaults.lua")
assert(not defaultsSrc:find("maxVisibleRows", 1, true),
    "maxVisibleRows must not be referenced in core/defaults.lua")

-- Task 8: Sticky self-row + separator. Built in Window:New, hidden by default.
-- The helper _BuildStickyRow constructs the row using _AttachRowVisuals so it
-- shares all behavior with pooled rows (click for breakdown, hover tooltip).
assert(coreSrc3:find("function Window:_BuildStickyRow", 1, true),
    "Window:_BuildStickyRow must be defined")
assert(coreSrc3:find("function Window:_AttachRowVisuals", 1, true),
    "Window:_AttachRowVisuals helper must be defined (shared between _BuildRow and _BuildStickyRow)")
assert(coreSrc3:find("self%.stickyRow", 1, false),
    "Window must expose self.stickyRow")
assert(coreSrc3:find("self%.stickySeparator", 1, false),
    "Window must expose self.stickySeparator")

-- Task 9: Sticky-self visibility. Predicate runs against current viewport +
-- scroll offset. The OnMouseWheel handler (Task 5) was already guarded with
-- `if self._UpdateStickyVisibility` so it picks up the method now.
assert(coreSrc3:find("function Window:_UpdateStickyVisibility", 1, true),
    "Window:_UpdateStickyVisibility must be defined")
assert(coreSrc3:find("self:_UpdateStickyVisibility()", 1, true),
    "Refresh must call _UpdateStickyVisibility")
-- The legacy bottom-row swap is gone.
assert(not coreSrc3:find("localIdx > visibleCount", 1, true),
    "legacy pinned-self bottom-row swap must be removed")
assert(not coreSrc3:find("localIdx > renderCount", 1, true),
    "Task 7 placeholder must be removed")

-- Task 10: _ApplyColors and _ApplyFonts must also style the sticky row.
-- Verify that both functions contain a self.stickyRow guard block by checking
-- that "stickyRow" appears after each function definition in the source.
local colorsPos = coreSrc3:find("function Window:_ApplyColors", 1, true)
local fontsPos  = coreSrc3:find("function Window:_ApplyFonts",  1, true)
assert(colorsPos, "_ApplyColors must be defined")
assert(fontsPos,  "_ApplyFonts must be defined")
-- stickyRow must appear inside _ApplyColors (before _ApplyFonts).
assert(coreSrc3:find("stickyRow", colorsPos, true) < fontsPos,
    "_ApplyColors must style self.stickyRow")
-- stickyRow must also appear inside _ApplyFonts (after fontsPos).
assert(coreSrc3:find("stickyRow", fontsPos, true),
    "_ApplyFonts must style self.stickyRow")

print("OK: damage_meter_settings_test (Phases 1-10 complete)")
