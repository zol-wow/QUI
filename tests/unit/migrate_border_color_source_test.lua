-- tests/unit/migrate_border_color_source_test.lua
-- Verifies the v39 MigrateBorderColorSource step (driven via RunOnProfile with a
-- pre-v39 _schemaVersion so only the new gate fires). Covers class-toggle mapping,
-- the preset/accent freeze fingerprint -> "theme", genuine custom preservation,
-- legacy-key stripping, the tooltip mapping, and idempotency.
-- Run: lua tests/unit/migrate_border_color_source_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()          -- loads core/migrations.lua -> ns.Migrations
local Migrations = ns.Migrations

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

-- Build a PLAIN pre-v39 profile table (NOT AceDB, so unset keys read as real nil
-- rather than metatable defaults) with _schemaVersion=38 so RunOnProfile fires only
-- the new v39 gate (and any later gates, which are no-ops on this minimal shape).
local function freshProfile(mutate)
    local p = { _schemaVersion = 38, general = {}, tooltip = {} }
    mutate(p)
    Migrations.RunOnProfile(p)
    return p
end

-- class toggle on -> "class", legacy key stripped
do
    local p = freshProfile(function(p)
        p.general.skinBorderUseClassColor = true
        p.general.addonAccentColor = { 0.78, 0.19, 0.19, 1 }  -- Horde
    end)
    check("class toggle -> class", p.general.skinBorderColorSource == "class",
        tostring(p.general.skinBorderColorSource))
    check("class toggle legacy key stripped", p.general.skinBorderUseClassColor == nil)
end

-- skinBorderColor == a preset RGB (freeze snapshot) -> "theme"
do
    local p = freshProfile(function(p)
        p.general.addonAccentColor = { 0.78, 0.19, 0.19, 1 }   -- current = Horde
        p.general.skinBorderColor = { 0.376, 0.647, 0.980, 1 } -- frozen Sky Blue preset
    end)
    check("preset-RGB snapshot -> theme", p.general.skinBorderColorSource == "theme",
        tostring(p.general.skinBorderColorSource))
end

-- skinBorderColor == current accent -> "theme"
do
    local p = freshProfile(function(p)
        p.general.addonAccentColor = { 0.78, 0.19, 0.19, 1 }
        p.general.skinBorderColor = { 0.78, 0.19, 0.19, 1 }
    end)
    check("accent-equal snapshot -> theme", p.general.skinBorderColorSource == "theme",
        tostring(p.general.skinBorderColorSource))
end

-- skinBorderColor == nil -> "theme"
do
    local p = freshProfile(function(p)
        p.general.addonAccentColor = { 0.78, 0.19, 0.19, 1 }
        p.general.skinBorderColor = nil
    end)
    check("nil color -> theme", p.general.skinBorderColorSource == "theme",
        tostring(p.general.skinBorderColorSource))
end

-- skinBorderColor == genuine non-preset custom color -> "custom" (preserved)
do
    local p = freshProfile(function(p)
        p.general.addonAccentColor = { 0.78, 0.19, 0.19, 1 }
        p.general.skinBorderColor = { 0.11, 0.22, 0.33, 1 }
    end)
    check("non-preset custom color -> custom", p.general.skinBorderColorSource == "custom",
        tostring(p.general.skinBorderColorSource))
    check("custom color preserved",
        p.general.skinBorderColor and math.abs(p.general.skinBorderColor[1] - 0.11) < 1e-6)
end

-- tooltip: borderUseAccentColor -> "theme"; legacy keys stripped
do
    local p = freshProfile(function(p)
        p.tooltip.borderUseAccentColor = true
    end)
    check("tooltip accent toggle -> theme", p.tooltip.borderColorSource == "theme",
        tostring(p.tooltip.borderColorSource))
    check("tooltip accent legacy stripped",
        p.tooltip.borderUseClassColor == nil and p.tooltip.borderUseAccentColor == nil)
end

-- tooltip: borderUseClassColor -> "class"
do
    local p = freshProfile(function(p)
        p.tooltip.borderUseClassColor = true
    end)
    check("tooltip class toggle -> class", p.tooltip.borderColorSource == "class",
        tostring(p.tooltip.borderColorSource))
end

-- tooltip: default-stripped legacy class/default-accent keys preserve old class behavior
do
    local p = freshProfile(function(p)
        p.tooltip.enabled = true
        p.tooltip.borderColor = nil
        p.tooltip.borderUseClassColor = nil
        p.tooltip.borderUseAccentColor = nil
    end)
    check("tooltip default-stripped legacy toggles -> class", p.tooltip.borderColorSource == "class",
        tostring(p.tooltip.borderColorSource))
end

-- idempotency: a second RunOnProfile leaves the result unchanged
do
    local p = { _schemaVersion = 38, general = { skinBorderUseClassColor = true }, tooltip = {} }
    Migrations.RunOnProfile(p)
    local first = p.general.skinBorderColorSource
    Migrations.RunOnProfile(p)  -- _schemaVersion now 39; v39 gate won't refire
    check("idempotent after second run",
        p.general.skinBorderColorSource == first and first == "class",
        tostring(p.general.skinBorderColorSource))
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
