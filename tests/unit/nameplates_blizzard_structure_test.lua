-- tests/unit/nameplates_blizzard_structure_test.lua
-- Run: lua tests/unit/nameplates_blizzard_structure_test.lua
--
-- Early-warning tripwire for patch bumps (plans/009-nameplates.md risk #2):
-- QUI_Nameplates suppresses Blizzard plate art by reparenting specific
-- UnitFrame children. This asserts every child key the driver reparents
-- still exists as a parentKey in the vendored Blizzard_NamePlates snapshot —
-- when Blizzard reshuffles the plate tree, this fails before the game does.

local function fail(msg)
    print("FAIL: nameplates_blizzard_structure_test - " .. msg)
    os.exit(1)
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local xml = readAll("tests/framexml/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.xml")
if not xml then fail("vendored Blizzard_NamePlates.xml not found — refresh the framexml snapshot") end

local driverSrc = readAll("QUI_Nameplates/nameplates/driver.lua")
if not driverSrc then fail("driver.lua not found") end

-- Extract the driver's SUPPRESS_CHILD_KEYS list.
local listBody = driverSrc:match("local SUPPRESS_CHILD_KEYS = {(.-)}")
if not listBody then fail("SUPPRESS_CHILD_KEYS list not found in driver.lua") end

local keys = {}
for key in listBody:gmatch('"([%w_]+)"') do
    keys[#keys + 1] = key
end
if #keys < 5 then fail("suspiciously short SUPPRESS_CHILD_KEYS list (" .. #keys .. " keys)") end

-- Every reparented key must exist as parentKey in the snapshot. `name` and
-- `castBar` are lowercase parentKeys; the scan is exact-match.
for _, key in ipairs(keys) do
    if not xml:find('parentKey="' .. key .. '"', 1, true) then
        fail("driver reparents UnitFrame." .. key ..
            " but the vendored Blizzard_NamePlates.xml has no such parentKey — plate tree changed")
    end
end

-- The alpha-pinned UnitFrame itself must still exist.
if not xml:find('parentKey="UnitFrame"', 1, true)
    and not driverSrc:find("base.UnitFrame", 1, true) then
    fail("UnitFrame acquisition contract changed")
end
if not xml:find("BaseNamePlateUnitFrameTemplate", 1, true) then
    fail("BaseNamePlateUnitFrameTemplate missing from snapshot — suppression targets need re-audit")
end

-- Suppression rule (the scar): UnitCanAttack must NEVER gate suppression.
-- Isolate the OnNamePlateAdded hook body and assert it has no attackability
-- check; routing (which may consult UnitCanAttack) lives elsewhere.
local hookBody = driverSrc:match('hooksecurefunc%(blizzDriver, "OnNamePlateAdded",(.-)\n    end%)')
if not hookBody then fail("OnNamePlateAdded suppression hook not found in driver.lua") end
if hookBody:find("UnitCanAttack", 1, true) then
    fail("suppression hook consults UnitCanAttack — first-frame attackability LIES; suppression must be unconditional")
end
if not hookBody:find("SuppressBlizzardArt", 1, true) then
    fail("suppression hook must call SuppressBlizzardArt")
end

print("OK: nameplates_blizzard_structure_test")
