-- tests/unit/damage_meter_appearance_revision_test.lua
-- Run: lua tests/unit/damage_meter_appearance_revision_test.lua
--
-- Appearance (header text, fonts, colors) is settings-driven, yet the old
-- Window:Refresh re-applied all three style walks on EVERY data tick before
-- the generation guard. This test pins the pure gating helper and the wiring:
-- every settings entry point funnels through WindowManager:RefreshAll (or
-- ClearRuntimeSessionIDs, which rewrites the header's session label), both of
-- which bump the module appearance revision; Refresh re-applies style only
-- when the window's last-applied revision trails it.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

-- Pure helper behavior.
local chunk = src:match("(local function ShouldReapplyAppearance.-\nend\n)")
assert(chunk, "could not locate ShouldReapplyAppearance in damage_meter.lua")
local ShouldReapplyAppearance =
    assert(loadstring(chunk .. "\nreturn ShouldReapplyAppearance"))()

assert(ShouldReapplyAppearance(nil, 1) == true,
    "freshly spawned window (nil applied rev) must style itself")
assert(ShouldReapplyAppearance(3, 3) == false,
    "matching revision skips the style walks")
assert(ShouldReapplyAppearance(3, 4) == true,
    "bumped revision re-applies style")

-- Wiring: the revision counter and bump exist.
assert(src:find("QUI_DamageMeter._appearanceRev = 1", 1, true),
    "module must seed _appearanceRev")
assert(src:find("function QUI_DamageMeter.BumpAppearanceRevision", 1, true),
    "module must expose BumpAppearanceRevision")

-- Wiring: RefreshAll bumps (settings widgets, skin/border registries, gear
-- menu, challenge swaps, and reset all funnel through it).
local refreshAll = src:match("function WindowManager:RefreshAll%(%)(.-)\nend")
assert(refreshAll, "could not extract WindowManager:RefreshAll body")
assert(refreshAll:find("BumpAppearanceRevision", 1, true),
    "RefreshAll must bump the appearance revision")

-- Wiring: ClearRuntimeSessionIDs bumps (reached from Data._onChange after a
-- meter reset WITHOUT RefreshAll, and it rewrites the header session label).
local clearIDs = src:match("function WindowManager:ClearRuntimeSessionIDs%(%)(.-)\nend")
assert(clearIDs, "could not extract ClearRuntimeSessionIDs body")
assert(clearIDs:find("BumpAppearanceRevision", 1, true),
    "ClearRuntimeSessionIDs must bump the appearance revision")

-- Wiring: Refresh gates the three style walks behind the helper.
assert(src:find("ShouldReapplyAppearance(self._appliedAppearanceRev", 1, true),
    "Window:Refresh must gate style on ShouldReapplyAppearance")

-- Wiring: selective profile import of the damageMeter category must reach
-- the refresh registration (it used to rely on per-tick style reapply).
assert(src:find('importCategories = { "skinning", "theme", "damageMeter" }', 1, true),
    "damageMeterSkin registration must refresh on damageMeter category import")

print("OK: damage_meter_appearance_revision_test")
