-- tests/unit/unitframes_surface_uses_body_preview_test.lua
-- Run: lua tests/unit/unitframes_surface_uses_body_preview_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    data = data:gsub("\r\n", "\n")
    return data
end

local surface = readAll("modules/unitframes/settings/unit_frames_surface.lua")

-- T8: surface.lua delegates to the body preview driver for lifecycle
assert(surface:find("ns.QUI_UnitFramesBodyPreview.Build", 1, true),
    "surface.lua BuildMockFrame must call ns.QUI_UnitFramesBodyPreview.Build(mock)")
assert(surface:find("ns.QUI_UnitFramesBodyPreview.Refresh", 1, true),
    "surface.lua RefreshMock must call ns.QUI_UnitFramesBodyPreview.Refresh(unitDB, general)")
assert(surface:find("ns.QUI_UnitFramesBodyPreview.SetSelectedUnit", 1, true),
    "surface.lua UnitSelection.afterSet must call ns.QUI_UnitFramesBodyPreview.SetSelectedUnit")

-- T8: the pct-dependent writes are no longer inside RefreshMock
-- (the 0.72 / 0.85 / 0.15 / 0.20 literals introduced in T2 are gone)
assert(not surface:find("(w - (inner * 2)) * 0.72", 1, true),
    "RefreshMock must no longer SetWidth on healthBar from a static pct (driver owns it)")
assert(not surface:find("(w - inner * 2) * 0.85", 1, true),
    "RefreshMock must no longer SetWidth on powerBar from a static pct (driver owns it)")
assert(not surface:find('predFrac = 0.15', 1, true),
    "RefreshMock must no longer hardcode healPred predFrac (driver owns it)")
assert(not surface:find('absFrac = 0.20', 1, true),
    "RefreshMock must no longer hardcode absorb absFrac (driver owns it)")
assert(not surface:find('icon._stack:SetText(tostring(i + 1))', 1, true),
    "RefreshMock must no longer hardcode aura stack text (driver owns it)")
assert(not surface:find('icon._dur:SetText("12s")', 1, true),
    "RefreshMock must no longer hardcode aura duration text (driver owns it)")

-- T8: surface.lua no longer calls FormatHealthText / FormatPowerText itself
-- (RefreshMock used to call them inline; the driver now does this on every tick)
assert(not surface:find('FormatHealthText(', 1, true),
    "RefreshMock must no longer call FormatHealthText (driver writes health text per tick)")
assert(not surface:find('FormatPowerText(', 1, true),
    "RefreshMock must no longer call FormatPowerText (driver writes power text per tick)")

-- T9: options.xml registers the body preview driver, AFTER the castbar driver
local optionsXml = readAll("QUI_Options/options.xml")
assert(optionsXml:find("unit_frames_body_preview.lua", 1, true),
    "QUI_Options/options.xml must register unit_frames_body_preview.lua")
local castbarPos = optionsXml:find("unit_frames_castbar_preview.lua", 1, true)
local bodyPos    = optionsXml:find("unit_frames_body_preview.lua", 1, true)
assert(castbarPos and bodyPos and castbarPos < bodyPos,
    "options.xml must load unit_frames_body_preview.lua after unit_frames_castbar_preview.lua")

print("OK: unitframes_surface_uses_body_preview_test")
