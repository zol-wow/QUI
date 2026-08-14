-- tests/unit/migration_schema60_purge_container_satellites_test.lua
-- Run: lua5.1 tests/unit/migration_schema60_purge_container_satellites_test.lua
--
-- Migrations.PurgeOrphanContainerSatellites (schema-60 step e). DeleteContainer
-- historically removed a custom CDM container's db entry + frame but never
-- cleaned up the per-container satellite settings the settings page and
-- layout mode write keyed on the container name: profile.customGlow[key..
-- "Frequency"/"Lines"/"Pandemic*"/"Scale"/"Thickness"/"XOffset"/"YOffset"/
-- "GlowType"/"Color"/"Enabled"], profile.cooldownEffects["hide_"..key],
-- profile.frameAnchoring["cdmCustom_"..key]. A satellite is orphaned when
-- its derived container key no longer exists in profile.ncdm.containers.
-- The shipped seed proves the leak: 15 orphan cdmCustom_custom_* anchors
-- and glow key-sets for 3 nonexistent containers
-- (core/new_profile_defaults.lua).
--
-- Trap covered below: "Enabled" is a tail of "PandemicBuffEnabled" /
-- "PandemicDebuffEnabled" / "PandemicEnabled". CDM_GLOW_SUFFIXES is ordered
-- longest-suffix-first and the match loop stops at the FIRST suffix whose
-- pattern matches the key's tail (regardless of live/orphan outcome), so a
-- live key like "<liveKey>PandemicBuffEnabled" resolves against the
-- specific "PandemicBuffEnabled" suffix and never falls through to the
-- bare "Enabled" suffix, which would mis-derive "<liveKey>PandemicBuff" as
-- the container prefix and wrongly delete a live key.

local ns = dofile("tools/_addon_env.lua").LoadCore()
local M = ns.Migrations

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

----------------------------------------------------------------------------
-- 1) Orphaned anchors/effects/glow (no matching ncdm.containers entry) are
--    purged; the live container's + essential/utility builtin satellites
--    survive.
----------------------------------------------------------------------------
do
    local liveKey = "custom_1778883503_8224"
    local orphanKey = "custom_1776292480_7595"
    local profile = {
        _schemaVersion = 47,
        ncdm = {
            containers = {
                essential = {}, utility = {}, buff = {}, trackedBar = {},
                [liveKey] = {},
            },
        },
        frameAnchoring = {
            ["cdmCustom_" .. liveKey] = { parent = "UIParent", point = "TOP" },
            ["cdmCustom_" .. orphanKey] = { parent = "UIParent", point = "CENTER" },
            buffFrame = { parent = "UIParent", point = "BOTTOM" },
        },
        cooldownEffects = {
            ["hide_" .. liveKey] = true,
            ["hide_" .. orphanKey] = true,
            hideEssential = false,
            hideUtility = true,
        },
        customGlow = {
            [liveKey .. "Frequency"] = 0.1,
            [liveKey .. "Scale"] = 0.5,
            -- Trap case: a LIVE container's PandemicBuffEnabled key ends in
            -- "Enabled" too. If the bare "Enabled" suffix were ever tried
            -- before "PandemicBuffEnabled", this would mis-derive
            -- "<liveKey>PandemicBuff" as the prefix (not live) and wrongly
            -- delete a live container's key. See header note.
            [liveKey .. "PandemicBuffEnabled"] = true,
            [orphanKey .. "Frequency"] = 0.1,
            [orphanKey .. "Lines"] = 1,
            [orphanKey .. "PandemicEnabled"] = true,
            -- Production data carries the Buff/Debuff variants, not just the
            -- bare PandemicEnabled — pin both so a suffix-list reorder or
            -- typo can't silently stop matching them.
            [orphanKey .. "PandemicBuffEnabled"] = true,
            [orphanKey .. "PandemicDebuffEnabled"] = true,
            [orphanKey .. "Scale"] = 0.5,
            [orphanKey .. "Thickness"] = 1,
            [orphanKey .. "XOffset"] = -20,
            [orphanKey .. "YOffset"] = -20,
            [orphanKey .. "GlowType"] = "Pixel Glow",
            [orphanKey .. "Color"] = { 1, 1, 1, 1 },
            [orphanKey .. "Enabled"] = true,
            essentialFrequency = 0.25,
            essentialEnabled = true,
            essentialLines = 14,
            utilityFrequency = 0.25,
            utilityEnabled = true,
        },
    }
    M.RunOnProfile(profile)

    check("orphan frameAnchoring purged", profile.frameAnchoring["cdmCustom_" .. orphanKey] == nil)
    check("live frameAnchoring survives", profile.frameAnchoring["cdmCustom_" .. liveKey] ~= nil)
    check("unrelated frameAnchoring survives", profile.frameAnchoring.buffFrame ~= nil)

    check("orphan cooldownEffects.hide_ purged", profile.cooldownEffects["hide_" .. orphanKey] == nil)
    check("live cooldownEffects.hide_ survives", profile.cooldownEffects["hide_" .. liveKey] == true)
    check("hideEssential survives", profile.cooldownEffects.hideEssential == false)
    check("hideUtility survives", profile.cooldownEffects.hideUtility == true)

    local orphanGlowSurvives = false
    for k in pairs(profile.customGlow) do
        if k:sub(1, #orphanKey) == orphanKey then orphanGlowSurvives = true end
    end
    check("orphan customGlow keys purged", not orphanGlowSurvives)
    check("orphan customGlow GlowType purged", profile.customGlow[orphanKey .. "GlowType"] == nil)
    check("orphan customGlow Color purged", profile.customGlow[orphanKey .. "Color"] == nil)
    check("orphan customGlow Enabled purged", profile.customGlow[orphanKey .. "Enabled"] == nil)
    check("live customGlow Frequency survives", profile.customGlow[liveKey .. "Frequency"] == 0.1)
    check("live customGlow Scale survives", profile.customGlow[liveKey .. "Scale"] == 0.5)
    check("TRAP: live customGlow PandemicBuffEnabled survives",
        profile.customGlow[liveKey .. "PandemicBuffEnabled"] == true)
    check("essentialFrequency survives", profile.customGlow.essentialFrequency == 0.25)
    check("essentialEnabled survives", profile.customGlow.essentialEnabled == true)
    check("essentialLines survives", profile.customGlow.essentialLines == 14)
    check("utilityFrequency survives", profile.customGlow.utilityFrequency == 0.25)
    check("utilityEnabled survives", profile.customGlow.utilityEnabled == true)

    check("stamped to current (current)", profile._schemaVersion == M.CURRENT_SCHEMA_VERSION, tostring(profile._schemaVersion))
end

----------------------------------------------------------------------------
-- 2) No ncdm.containers table at all (e.g. a profile that never touched
--    CDM) -> every cdmCustom_/hide_/custom_* glow satellite is orphaned and
--    purged; essential/utility glow keys still survive (prefix guard, not
--    the live-set check).
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        frameAnchoring = { ["cdmCustom_custom_1_1"] = { parent = "UIParent" } },
        cooldownEffects = { ["hide_custom_1_1"] = true },
        customGlow = { custom_1_1Scale = 0.5, essentialScale = 1, utilityScale = 1 },
    }
    M.RunOnProfile(profile)
    check("no ncdm table: anchor purged", profile.frameAnchoring["cdmCustom_custom_1_1"] == nil)
    check("no ncdm table: hide_ purged", profile.cooldownEffects["hide_custom_1_1"] == nil)
    check("no ncdm table: custom glow purged", profile.customGlow.custom_1_1Scale == nil)
    check("no ncdm table: essentialScale survives", profile.customGlow.essentialScale == 1)
    check("no ncdm table: utilityScale survives", profile.customGlow.utilityScale == 1)
end

----------------------------------------------------------------------------
-- 3) Idempotent: a second run changes nothing further.
----------------------------------------------------------------------------
do
    local liveKey = "custom_1778883503_8224"
    local profile = {
        _schemaVersion = 47,
        ncdm = { containers = { [liveKey] = {} } },
        frameAnchoring = { ["cdmCustom_" .. liveKey] = { parent = "UIParent" } },
        customGlow = { [liveKey .. "Scale"] = 0.5 },
    }
    M.RunOnProfile(profile)
    M.RunOnProfile(profile)
    check("idempotent: live anchor still present", profile.frameAnchoring["cdmCustom_" .. liveKey] ~= nil)
    check("idempotent: live glow still present", profile.customGlow[liveKey .. "Scale"] == 0.5)
    check("idempotent: stays at current (current)", profile._schemaVersion == M.CURRENT_SCHEMA_VERSION, tostring(profile._schemaVersion))
end

if failures > 0 then os.exit(1) end
print("migration_schema60_purge_container_satellites_test: all checks passed")
