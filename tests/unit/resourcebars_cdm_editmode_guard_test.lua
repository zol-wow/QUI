-- tests/unit/resourcebars_cdm_editmode_guard_test.lua
-- Run: lua tests/unit/resourcebars_cdm_editmode_guard_test.lua
--
-- Regression: the four QUI_UpdateLocked*PowerBar* persistence callbacks must
-- skip while CDM Edit Mode is ACTIVE, so the transient edit-mode viewer
-- dimensions are never persisted to cfg.width (the "flash at Edit Mode width on
-- next load" bug documented at the first guard site). They previously guarded
-- on _G.QUI_IsCDMEditModeHidden(), which was stubbed to always return false
-- when Edit Mode was redesigned to keep containers visible — so the guard never
-- fired. The live flag is _G.QUI_IsCDMEditModeActive() (returns _editModeActive,
-- the same flag cdm_bar_renderer.lua / cdm_icon_renderer.lua already use).
-- This test pins the guard to the live flag and ensures the dead stub is gone.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    -- Normalize CRLF -> LF so source-pattern searches work on Windows.
    return (data:gsub("\r\n", "\n"))
end

local rb = readAll("modules/resourcebars/resourcebars.lua")

-- Each locked-bar persistence callback must guard on the LIVE edit-mode flag.
local lockedFns = {
    "QUI_UpdateLockedPowerBar",
    "QUI_UpdateLockedPowerBarToUtility",
    "QUI_UpdateLockedSecondaryPowerBar",
    "QUI_UpdateLockedSecondaryPowerBarToUtility",
}

for _, fn in ipairs(lockedFns) do
    -- The " = function()" suffix disambiguates the PowerBar / PowerBarToUtility prefixes.
    local header = "_G." .. fn .. " = function()"
    local s = rb:find(header, 1, true)
    assert(s, "expected to find " .. header .. " in resourcebars.lua")
    -- The guard sits within the first few lines of the body; 600 chars is ample.
    local body = rb:sub(s, s + 600)
    assert(body:find("QUI_IsCDMEditModeActive", 1, true),
        fn .. " must guard CDM Edit Mode via the live QUI_IsCDMEditModeActive flag")
    assert(body:find("then return end", 1, true),
        fn .. " must early-return when the CDM Edit Mode guard fires")
end

-- The dead flag must not be referenced anywhere in resourcebars.lua.
assert(not rb:find("QUI_IsCDMEditModeHidden", 1, true),
    "resourcebars.lua must not reference the dead-stub QUI_IsCDMEditModeHidden (use QUI_IsCDMEditModeActive)")

-- The backward-compat stub itself must be removed; the live flag stays defined.
local cont = readAll("modules/cdm/cdm_containers.lua")
assert(not cont:find("QUI_IsCDMEditModeHidden", 1, true),
    "cdm_containers.lua must no longer define the dead QUI_IsCDMEditModeHidden stub")
assert(cont:find("_G.QUI_IsCDMEditModeActive = function()", 1, true),
    "cdm_containers.lua must still define the live QUI_IsCDMEditModeActive flag")

print("resourcebars_cdm_editmode_guard_test: OK")
