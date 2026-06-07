-- tests/unit/border_migration_test.lua
-- Verifies the v40 registry-driven MigrateBorderColoring step: legacy useClass
-- toggle -> "class", legacy accent toggle -> "theme", legacy color-key rename ->
-- "custom", crosshair borderR/G/B/A scalar fold -> "custom", and a plain module
-- with no legacy descriptor -> "custom" (literal color preserved). Also asserts
-- dead legacy keys are stripped and that re-running the migration is a no-op.
-- Run: lua tests/unit/border_migration_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Helpers = ns.Helpers
local BorderRegistry = Helpers.BorderRegistry

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end
local function approx(a, b) return math.abs((a or -1) - (b or -2)) < 1e-6 end

-- Deep-equal for idempotency spot-checks.
local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, nv in pairs(v) do out[k] = deepCopy(nv) end
    return out
end

---------------------------------------------------------------------------
-- Register SYNTHETIC registry entries covering every conversion branch.
-- Each module reads/writes a distinct sub-table of the synthetic profile so
-- the entries don't collide.
---------------------------------------------------------------------------

-- (a) module with a legacy useClass boolean (prefix "" => borderColor*)
BorderRegistry.Register{
    key    = "synthClass",
    prefix = "",
    db     = function(p) return p.synthClass end,
    legacy = { useClass = "useClassColorBorder" },
}

-- (b) module with a legacy accent boolean (prefixed keys)
BorderRegistry.Register{
    key    = "synthAccent",
    prefix = "panel",
    db     = function(p) return p.synthAccent end,
    legacy = { accent = "useAccentColorBorder" },
}

-- (c) module that renames a legacy color key (legacy.table)
BorderRegistry.Register{
    key    = "synthRename",
    prefix = "",
    db     = function(p) return p.synthRename end,
    legacy = { table = "borderColorTable" },
}

-- (d) crosshair-style module: borderR/G/B/A scalars folded into borderColor
BorderRegistry.Register{
    key    = "synthScalars",
    prefix = "",
    db     = function(p) return p.synthScalars end,
    legacy = { scalars = true },
}

-- (e) plain module, no legacy descriptor => "custom", color preserved as-is
BorderRegistry.Register{
    key    = "synthPlain",
    prefix = "",
    db     = function(p) return p.synthPlain end,
}

-- (f) multi module: one entry owns N instance tables; each instance migrates
BorderRegistry.Register{
    key       = "synthMulti",
    prefix    = "",
    multi     = true,
    instances = function(p) return p.synthMulti and p.synthMulti.list or {} end,
    legacy    = { useClass = "useClassColorBorder", accent = "useAccentColorBorder" },
}

-- (g) multi module with a legacy.table rename across EVERY instance (mirrors
-- the CDM icon-container conversion: each row's borderColorTable -> borderColor
-- + source "custom"). Asserts the rename fires per-instance, not just on [1].
BorderRegistry.Register{
    key       = "synthMultiRename",
    prefix    = "",
    multi     = true,
    instances = function(p) return p.synthMultiRename and p.synthMultiRename.rows or {} end,
    legacy    = { table = "borderColorTable" },
}

-- (h) override module: OFF (false) historically meant "inherit the global skin
-- border" (preyTracker/mplusTimer/readyCheck pattern). When override is FALSY,
-- the source must become "inherit" — NOT "custom" with a pinned color.
BorderRegistry.Register{
    key    = "synthOverrideOff",
    prefix = "",
    db     = function(p) return p.synthOverrideOff end,
    legacy = { override = "borderOverride", useClass = "borderUseClassColor" },
}

-- (i) override module where the override key was never written (defaulted false
-- and never saved). A missing override must be treated the same as false ->
-- "inherit".
BorderRegistry.Register{
    key    = "synthOverrideAbsent",
    prefix = "",
    db     = function(p) return p.synthOverrideAbsent end,
    legacy = { override = "borderOverride", useClass = "borderUseClassColor" },
}

-- (j) override module ON + useClass -> "class".
BorderRegistry.Register{
    key    = "synthOverrideOnClass",
    prefix = "",
    db     = function(p) return p.synthOverrideOnClass end,
    legacy = { override = "borderOverride", useClass = "borderUseClassColor" },
}

-- (k) override module ON + no useClass -> "custom", color preserved.
BorderRegistry.Register{
    key    = "synthOverrideOnCustom",
    prefix = "",
    db     = function(p) return p.synthOverrideOnCustom end,
    legacy = { override = "borderOverride", useClass = "borderUseClassColor" },
}

-- (l) prefixed override module (readyCheck pattern): override+useClass keys are
-- NOT prefix-derived (they're explicit legacy names), but the source/color keys
-- ARE prefixed. Proves the override arm works with a non-empty prefix.
BorderRegistry.Register{
    key    = "synthOverridePrefixed",
    prefix = "readyCheck",
    db     = function(p) return p.synthOverridePrefixed end,
    legacy = { override = "readyCheckBorderOverride", useClass = "readyCheckBorderUseClassColor" },
}

---------------------------------------------------------------------------
-- Build a synthetic pre-migration profile with each module's legacy keys.
---------------------------------------------------------------------------
local function buildProfile()
    return {
        synthClass  = { useClassColorBorder = true, borderColor = { 0.1, 0.2, 0.3, 1 } },
        synthAccent = { useAccentColorBorder = true, panelBorderColor = { 0.4, 0.5, 0.6, 1 } },
        synthRename = { borderColorTable = { 0.7, 0.8, 0.9, 1 } },
        synthScalars = { borderR = 0.11, borderG = 0.22, borderB = 0.33, borderA = 0.44 },
        synthPlain  = { borderColor = { 0.12, 0.34, 0.56, 1 } },
        synthMulti  = { list = {
            { useClassColorBorder = true,  borderColor = { 1, 0, 0, 1 } },
            { useAccentColorBorder = true, borderColor = { 0, 1, 0, 1 } },
            { borderColor = { 0, 0, 1, 1 } },  -- no legacy truthy => custom
        } },
        synthMultiRename = { rows = {
            { borderColorTable = { 0.21, 0.22, 0.23, 1 } },
            { borderColorTable = { 0.31, 0.32, 0.33, 1 } },
        } },
        -- Override OFF: a pinned (black) custom color sits in borderColor, but
        -- because the override was OFF the user actually saw the GLOBAL border.
        synthOverrideOff = { borderOverride = false, borderUseClassColor = false, borderColor = { 0, 0, 0, 1 } },
        -- Override key never written (only the frozen color exists).
        synthOverrideAbsent = { borderColor = { 0, 0, 0, 1 } },
        -- Override ON + class color -> "class".
        synthOverrideOnClass = { borderOverride = true, borderUseClassColor = true, borderColor = { 0, 0, 0, 1 } },
        -- Override ON + custom color -> "custom", color preserved.
        synthOverrideOnCustom = { borderOverride = true, borderUseClassColor = false, borderColor = { 0.71, 0.72, 0.73, 1 } },
        -- Prefixed override OFF (readyCheck pattern) -> "inherit".
        synthOverridePrefixed = { readyCheckBorderOverride = false, readyCheckBorderUseClassColor = false, readyCheckBorderColor = { 0, 0, 0, 1 } },
    }
end

local p = buildProfile()
Helpers.MigrateBorderColoring(p)

-- (a) useClass -> "class", legacy bool stripped, color preserved
check("useClass -> class", p.synthClass.borderColorSource == "class",
    tostring(p.synthClass.borderColorSource))
check("useClass legacy bool stripped", p.synthClass.useClassColorBorder == nil)
check("useClass color preserved", approx(p.synthClass.borderColor[1], 0.1))

-- (b) accent -> "theme", legacy bool stripped, prefixed color preserved
check("accent -> theme", p.synthAccent.panelBorderColorSource == "theme",
    tostring(p.synthAccent.panelBorderColorSource))
check("accent legacy bool stripped", p.synthAccent.useAccentColorBorder == nil)
check("accent prefixed color preserved", approx(p.synthAccent.panelBorderColor[2], 0.5))

-- (c) legacy.table renamed -> borderColor + source "custom"
check("rename source custom", p.synthRename.borderColorSource == "custom",
    tostring(p.synthRename.borderColorSource))
check("rename old key removed", p.synthRename.borderColorTable == nil)
check("rename new key populated",
    type(p.synthRename.borderColor) == "table" and approx(p.synthRename.borderColor[1], 0.7))

-- (d) scalars folded into borderColor + source "custom"
check("scalars source custom", p.synthScalars.borderColorSource == "custom",
    tostring(p.synthScalars.borderColorSource))
check("scalars folded into borderColor",
    type(p.synthScalars.borderColor) == "table"
        and approx(p.synthScalars.borderColor[1], 0.11)
        and approx(p.synthScalars.borderColor[2], 0.22)
        and approx(p.synthScalars.borderColor[3], 0.33)
        and approx(p.synthScalars.borderColor[4], 0.44))

-- (e) plain -> "custom", literal color preserved
check("plain -> custom", p.synthPlain.borderColorSource == "custom",
    tostring(p.synthPlain.borderColorSource))
check("plain color preserved", approx(p.synthPlain.borderColor[1], 0.12))

-- (f) multi: each instance migrated independently
check("multi[1] class", p.synthMulti.list[1].borderColorSource == "class")
check("multi[1] legacy stripped", p.synthMulti.list[1].useClassColorBorder == nil)
check("multi[2] theme", p.synthMulti.list[2].borderColorSource == "theme")
check("multi[2] legacy stripped", p.synthMulti.list[2].useAccentColorBorder == nil)
check("multi[3] custom", p.synthMulti.list[3].borderColorSource == "custom")

-- (g) multi legacy.table rename: EVERY instance's borderColorTable is renamed
-- to borderColor and stamped source "custom" (preserving the literal color).
do
    local rows = p.synthMultiRename.rows
    check("multiRename[1] source custom", rows[1].borderColorSource == "custom",
        tostring(rows[1].borderColorSource))
    check("multiRename[1] old key removed", rows[1].borderColorTable == nil)
    check("multiRename[1] color preserved",
        type(rows[1].borderColor) == "table" and approx(rows[1].borderColor[1], 0.21))
    check("multiRename[2] source custom", rows[2].borderColorSource == "custom",
        tostring(rows[2].borderColorSource))
    check("multiRename[2] old key removed", rows[2].borderColorTable == nil)
    check("multiRename[2] color preserved",
        type(rows[2].borderColor) == "table" and approx(rows[2].borderColor[1], 0.31))
end

---------------------------------------------------------------------------
-- (h) override OFF -> "inherit", color NOT pinned, legacy keys stripped.
-- This is the look-preservation case: a user with the override OFF saw the
-- GLOBAL border, so we must NOT pin them to the frozen custom color.
---------------------------------------------------------------------------
check("override off -> inherit", p.synthOverrideOff.borderColorSource == "inherit",
    tostring(p.synthOverrideOff.borderColorSource))
check("override off: NOT custom", p.synthOverrideOff.borderColorSource ~= "custom")
check("override off: override key stripped", p.synthOverrideOff.borderOverride == nil)
check("override off: useClass key stripped", p.synthOverrideOff.borderUseClassColor == nil)

-- (i) override key absent -> treated as OFF -> "inherit".
check("override absent -> inherit", p.synthOverrideAbsent.borderColorSource == "inherit",
    tostring(p.synthOverrideAbsent.borderColorSource))
check("override absent: NOT custom", p.synthOverrideAbsent.borderColorSource ~= "custom")

-- (j) override ON + useClass -> "class".
check("override on + useClass -> class", p.synthOverrideOnClass.borderColorSource == "class",
    tostring(p.synthOverrideOnClass.borderColorSource))
check("override on class: override key stripped", p.synthOverrideOnClass.borderOverride == nil)
check("override on class: useClass key stripped", p.synthOverrideOnClass.borderUseClassColor == nil)

-- (k) override ON + no useClass -> "custom", color preserved.
check("override on, no useClass -> custom", p.synthOverrideOnCustom.borderColorSource == "custom",
    tostring(p.synthOverrideOnCustom.borderColorSource))
check("override on custom: color preserved",
    type(p.synthOverrideOnCustom.borderColor) == "table"
        and approx(p.synthOverrideOnCustom.borderColor[1], 0.71))
check("override on custom: override key stripped", p.synthOverrideOnCustom.borderOverride == nil)

-- (l) prefixed override OFF -> "inherit" (readyCheck pattern).
check("prefixed override off -> inherit",
    p.synthOverridePrefixed.readyCheckBorderColorSource == "inherit",
    tostring(p.synthOverridePrefixed.readyCheckBorderColorSource))
check("prefixed override off: override key stripped",
    p.synthOverridePrefixed.readyCheckBorderOverride == nil)
check("prefixed override off: useClass key stripped",
    p.synthOverridePrefixed.readyCheckBorderUseClassColor == nil)

---------------------------------------------------------------------------
-- Idempotency: a second run leaves the migrated profile byte-for-byte equal.
---------------------------------------------------------------------------
local snapshot = deepCopy(p)
Helpers.MigrateBorderColoring(p)
check("idempotent: second run deep-equal", deepEqual(p, snapshot),
    "second migration mutated the profile")
-- Spot-check the source keys specifically.
check("idempotent: synthClass source unchanged", p.synthClass.borderColorSource == "class")
check("idempotent: synthAccent source unchanged", p.synthAccent.panelBorderColorSource == "theme")
check("idempotent: synthScalars source unchanged", p.synthScalars.borderColorSource == "custom")
check("idempotent: synthOverrideOff source unchanged", p.synthOverrideOff.borderColorSource == "inherit")
check("idempotent: synthOverrideOnClass source unchanged", p.synthOverrideOnClass.borderColorSource == "class")

---------------------------------------------------------------------------
-- Per-table guard: an already-migrated table is skipped wholesale, even if it
-- still carries a stale legacy boolean (must NOT be re-derived or re-stripped).
---------------------------------------------------------------------------
do
    local db = { borderColorSource = "theme", useClassColorBorder = true }
    Helpers.MigrateBorderColoringTable(db, { prefix = "", legacy = { useClass = "useClassColorBorder" } })
    check("guard: source untouched", db.borderColorSource == "theme")
    check("guard: legacy bool left intact", db.useClassColorBorder == true)
end

---------------------------------------------------------------------------
-- Override guard: an already-migrated "inherit" table is NOT re-pinned to
-- custom on a second pass even though a stale override flag lingers.
---------------------------------------------------------------------------
do
    local db = { borderColorSource = "inherit", borderOverride = false, borderColor = { 0, 0, 0, 1 } }
    Helpers.MigrateBorderColoringTable(db, { prefix = "", legacy = { override = "borderOverride", useClass = "borderUseClassColor" } })
    check("override guard: source stays inherit", db.borderColorSource == "inherit")
    check("override guard: stale flag left intact", db.borderOverride == false)
end

---------------------------------------------------------------------------
-- Direct unit: an entry with NO override key in its legacy descriptor must
-- keep today's behavior — a missing useClass/accent falls through to "custom"
-- (it must NOT be coerced to "inherit").
---------------------------------------------------------------------------
do
    local db = { borderColor = { 0, 0, 0, 1 } }
    Helpers.MigrateBorderColoringTable(db, { prefix = "", legacy = { useClass = "borderUseClassColor" } })
    check("no-override entry -> custom (unchanged behavior)", db.borderColorSource == "custom",
        tostring(db.borderColorSource))
end

---------------------------------------------------------------------------
-- defaultSource opt-in: an entry whose legacy descriptor declares a
-- defaultSource must fall through to THAT source (not "custom") when no legacy
-- color/flag is present. This is the flat aura/auraBar CDM container case: the
-- Buff Icons and Buff Bars containers never carried a per-container border
-- color, so an un-migrated profile must land on "inherit" — not a pinned
-- "custom" with no color (which the icon-row containers correctly use).
---------------------------------------------------------------------------
do
    local db = {}
    Helpers.MigrateBorderColoringTable(db, { prefix = "", legacy = { defaultSource = "inherit" } })
    check("defaultSource inherit -> inherit (no legacy color)",
        db.borderColorSource == "inherit", tostring(db.borderColorSource))
    check("defaultSource inherit: no borderColor pinned",
        db.borderColor == nil, tostring(db.borderColor))
end

---------------------------------------------------------------------------
-- Gate wiring: RunOnProfile at a pre-v40 version runs the registry migration
-- and stamps the schema version; a fresh (current-version) profile skips it.
---------------------------------------------------------------------------
do
    local prof = buildProfile()
    prof._schemaVersion = 39
    ns.Migrations.RunOnProfile(prof)
    check("gate: ran via RunOnProfile (useClass -> class)",
        prof.synthClass.borderColorSource == "class",
        tostring(prof.synthClass.borderColorSource))
    check("gate: schema stamped to current", prof._schemaVersion >= 40,
        tostring(prof._schemaVersion))
end
do
    -- A profile already at the current version must NOT run the migration:
    -- its legacy keys are left untouched (proving the version gate skips it).
    local prof = buildProfile()
    prof._schemaVersion = 40 -- re-arm: below current so later gates re-run
    ns.Migrations.RunOnProfile(prof)
    check("gate: current-version profile skipped (no source key)",
        prof.synthClass.borderColorSource == nil
            and prof.synthClass.useClassColorBorder == true,
        tostring(prof.synthClass.borderColorSource))
end

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
