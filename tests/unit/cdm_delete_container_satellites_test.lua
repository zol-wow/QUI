-- tests/unit/cdm_delete_container_satellites_test.lua
-- Run: lua tests/unit/cdm_delete_container_satellites_test.lua
--
-- Regression: DeleteContainer removed db.containers[key] + the frame but
-- left the per-container satellite settings the settings page and layout
-- mode write keyed on the container name -- profile.customGlow[key.."Freq
-- uency"/"Lines"/"Pandemic*"/"Scale"/"Thickness"/"XOffset"/"YOffset"],
-- profile.cooldownEffects["hide_"..key], profile.frameAnchoring["cdmCustom_
-- "..key] -- orphaning them forever. The shipped seed proves the leak: 15
-- orphan cdmCustom_custom_* anchors (core/new_profile_defaults.lua:3402+)
-- and glow key-sets for 3 nonexistent containers (:2617-2639).
--
-- Extracts PurgeContainerSatellites from cdm_containers.lua (between the
-- QUI_TEST_EXTRACT sentinels) -- cdm_containers.lua as a whole is too
-- dependency-heavy to instantiate headlessly (see
-- cdm_containers_combat_end_refresh_coalesce_test.lua). The function is
-- pure (profile-table in, mutations only; only stdlib type/pairs/string
-- methods) so the extracted snippet needs no upvalue injection.

local loadSource = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text:gsub("\r\n", "\n")
end

local source = readAll("QUI_CDM/cdm/cdm_containers.lua")
local s = assert(source:find("-- >>> QUI_TEST_EXTRACT PurgeContainerSatellites", 1, true), "begin sentinel")
local fnStart = assert(source:find("\n", s)) + 1
local nl = assert(source:find("\n%-%- <<< QUI_TEST_EXTRACT PurgeContainerSatellites", fnStart), "end sentinel")
local fnSource = source:sub(fnStart, nl - 1)

local chunk = assert(loadSource(fnSource .. "\nreturn PurgeContainerSatellites", "PurgeContainerSatellites"))
local PurgeContainerSatellites = chunk()

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

----------------------------------------------------------------------------
-- 1) Deleting one custom container's satellites leaves a sibling live
--    custom container's satellites, the essential/utility builtin glow
--    keys, and unrelated cooldownEffects keys untouched.
----------------------------------------------------------------------------
do
    local deletedKey = "custom_1776292480_7595"
    local liveKey = "custom_1778883503_8224"
    local profile = {
        customGlow = {
            [deletedKey .. "Frequency"] = 0.1,
            [deletedKey .. "Lines"] = 1,
            [deletedKey .. "PandemicEnabled"] = true,
            [deletedKey .. "PandemicBuffEnabled"] = true,
            [deletedKey .. "PandemicDebuffEnabled"] = true,
            [deletedKey .. "Scale"] = 0.5,
            [deletedKey .. "Thickness"] = 1,
            [deletedKey .. "XOffset"] = -20,
            [deletedKey .. "YOffset"] = -20,
            [liveKey .. "Frequency"] = 0.1,
            [liveKey .. "Scale"] = 0.5,
            essentialFrequency = 0.25,
            essentialEnabled = true,
            essentialLines = 14,
            utilityFrequency = 0.25,
            utilityEnabled = true,
            utilityLines = 14,
        },
        cooldownEffects = {
            ["hide_" .. deletedKey] = true,
            ["hide_" .. liveKey] = true,
            hideEssential = false,
            hideUtility = true,
        },
        frameAnchoring = {
            ["cdmCustom_" .. deletedKey] = { parent = "UIParent", point = "CENTER" },
            ["cdmCustom_" .. liveKey] = { parent = "UIParent", point = "TOP" },
            buffFrame = { parent = "UIParent", point = "BOTTOM" },
        },
    }

    PurgeContainerSatellites(profile, deletedKey)

    -- Deleted key's satellites are gone.
    local anyDeletedGlowSurvives = false
    for k in pairs(profile.customGlow) do
        if k:sub(1, #deletedKey) == deletedKey then anyDeletedGlowSurvives = true end
    end
    check("deleted key's customGlow keys purged", not anyDeletedGlowSurvives)
    check("deleted key's cooldownEffects.hide_ purged", profile.cooldownEffects["hide_" .. deletedKey] == nil)
    check("deleted key's frameAnchoring.cdmCustom_ purged", profile.frameAnchoring["cdmCustom_" .. deletedKey] == nil)

    -- Live sibling container's satellites survive.
    check("live key's customGlow Frequency survives", profile.customGlow[liveKey .. "Frequency"] == 0.1)
    check("live key's customGlow Scale survives", profile.customGlow[liveKey .. "Scale"] == 0.5)
    check("live key's cooldownEffects.hide_ survives", profile.cooldownEffects["hide_" .. liveKey] == true)
    check("live key's frameAnchoring.cdmCustom_ survives", profile.frameAnchoring["cdmCustom_" .. liveKey] ~= nil)

    -- Builtin essential/utility glow keys are untouched (prefix-match cannot
    -- collide: containerKey values are custom_<ts>_<n>-shaped).
    check("essentialFrequency survives", profile.customGlow.essentialFrequency == 0.25)
    check("essentialEnabled survives", profile.customGlow.essentialEnabled == true)
    check("essentialLines survives", profile.customGlow.essentialLines == 14)
    check("utilityFrequency survives", profile.customGlow.utilityFrequency == 0.25)
    check("utilityEnabled survives", profile.customGlow.utilityEnabled == true)
    check("utilityLines survives", profile.customGlow.utilityLines == 14)

    -- Unrelated cooldownEffects/frameAnchoring entries are untouched.
    check("hideEssential survives", profile.cooldownEffects.hideEssential == false)
    check("hideUtility survives", profile.cooldownEffects.hideUtility == true)
    check("buffFrame anchoring survives", profile.frameAnchoring.buffFrame ~= nil)
end

----------------------------------------------------------------------------
-- 2) Missing satellite tables (fresh profile with no customGlow/cooldown
--    Effects/frameAnchoring yet) must not error.
----------------------------------------------------------------------------
do
    local ok, err = pcall(PurgeContainerSatellites, {}, "custom_1_1")
    check("no-op safely when satellite tables absent", ok, tostring(err))
end

----------------------------------------------------------------------------
-- 3) Bad argument types are ignored rather than erroring.
----------------------------------------------------------------------------
do
    local ok1 = pcall(PurgeContainerSatellites, nil, "custom_1_1")
    local ok2 = pcall(PurgeContainerSatellites, {}, nil)
    check("nil profile does not error", ok1)
    check("nil containerKey does not error", ok2)
end

if failures > 0 then os.exit(1) end
print("cdm_delete_container_satellites_test: all checks passed")
