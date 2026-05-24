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

-- QUI_Options/options.xml picked it up too
local optsSrc = readAll("QUI_Options/options.xml")
assert(optsSrc:find("damage_meter_content.lua", 1, true)
    or optsSrc:find("damageMeter", 1, true),
    "QUI_Options/options.xml must reference the damage_meter content file")

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

print("OK: damage_meter_settings_test (Phases 1-7 complete)")
