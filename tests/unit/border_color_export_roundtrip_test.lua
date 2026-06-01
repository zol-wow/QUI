-- Round-trip guard for the centralized border-coloring settings.
--
-- Phase 4 of the border-coloring centralization added per-module border keys
-- (borderColorSource / borderColor, and prefixed variants) that live inside
-- module subtrees, plus GENERAL-block keys (skinBorderColorSource /
-- skinBorderColor). Selective export/import is driven by hand-maintained
-- category key-lists in core/profile_io.lua; if any of these keys is not owned
-- by a category it is silently dropped on a selective export. The category
-- coverage test (profile_export_category_coverage_test.lua) guards reachability;
-- this test guards the full behavioral round-trip: a profile carrying both a
-- per-module override (minimap.borderColorSource="custom") and a global override
-- (general.skinBorderColorSource="class") must survive export -> import into a
-- fresh profile completely unchanged.
--
-- Run from repo root: lua tests/unit/border_color_export_roundtrip_test.lua

local env = dofile("tools/_addon_env.lua")
local h = env.BuildHarness()

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function colorEq(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Seed the source profile with both a per-module and a global border override.
local CUSTOM_COLOR = { 0.1, 0.2, 0.3, 1 }
local GLOBAL_COLOR = { 0.5, 0.6, 0.7, 1 }

h.db.profile.minimap = h.db.profile.minimap or {}
h.db.profile.minimap.borderColorSource = "custom"
h.db.profile.minimap.borderColor = { CUSTOM_COLOR[1], CUSTOM_COLOR[2], CUSTOM_COLOR[3], CUSTOM_COLOR[4] }

h.db.profile.general = h.db.profile.general or {}
h.db.profile.general.skinBorderColorSource = "class"
h.db.profile.general.skinBorderColor = { GLOBAL_COLOR[1], GLOBAL_COLOR[2], GLOBAL_COLOR[3], GLOBAL_COLOR[4] }

-- Categories that own the keys under test:
--   minimapDatatexts/minimapSubtab -> topLevelKeys includes "minimap"
--   skinning                        -> generalKeys = PROFILE_SKINNING_GENERAL_KEYS
local SELECTED = { "minimapDatatexts", "minimapSubtab", "skinning" }

local exportStr, exportErr = h.QUICore:ExportProfileSelectionToString(SELECTED)
check("selective export returns a QUI1 string",
      type(exportStr) == "string" and exportStr:match("^QUI1:") ~= nil,
      tostring(exportErr or exportStr):sub(1, 80))

-- Import into a fresh profile so we observe real assignment (not the pre-seeded
-- source values bleeding through).
h.db:SetProfile("ImportTarget")
check("fresh profile starts without the per-module override",
      not (h.db.profile.minimap and h.db.profile.minimap.borderColorSource == "custom"),
      "minimap.borderColorSource leaked into fresh profile")
check("fresh profile starts without the global override",
      h.db.profile.general == nil or h.db.profile.general.skinBorderColorSource ~= "class",
      "general.skinBorderColorSource leaked into fresh profile")

local importOK, importMsg = h.QUICore:ImportProfileSelectionFromString(exportStr, SELECTED, "ImportTarget")
check("selective import succeeds", importOK == true, tostring(importMsg))

-- Per-module override survived unchanged.
check('minimap.borderColorSource round-trips as "custom"',
      h.db.profile.minimap and h.db.profile.minimap.borderColorSource == "custom",
      tostring(h.db.profile.minimap and h.db.profile.minimap.borderColorSource))
check("minimap.borderColor round-trips unchanged",
      colorEq(h.db.profile.minimap and h.db.profile.minimap.borderColor, CUSTOM_COLOR),
      "got " .. (h.db.profile.minimap and h.db.profile.minimap.borderColor
                 and table.concat(h.db.profile.minimap.borderColor, ",") or "nil"))

-- Global override survived unchanged.
check('general.skinBorderColorSource round-trips as "class"',
      h.db.profile.general.skinBorderColorSource == "class",
      tostring(h.db.profile.general.skinBorderColorSource))
check("general.skinBorderColor round-trips unchanged",
      colorEq(h.db.profile.general.skinBorderColor, GLOBAL_COLOR),
      "got " .. (h.db.profile.general.skinBorderColor
                 and table.concat(h.db.profile.general.skinBorderColor, ",") or "nil"))

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
