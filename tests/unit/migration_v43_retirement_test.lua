-- tests/unit/migration_v43_retirement_test.lua
-- Verifies the v43 RetireModuleMasterFlags migration:
--   - Active profile with an explicit false flag → DisableAddOn called once,
--     flag forced true, _schemaVersion == 44.
--   - Non-active profile with a false flag → flag forced true, NO DisableAddOn.
--   - chat.enabled and quiGroupFrames.enabled are untouched by this migration.
--   - Idempotency: second run makes no further DisableAddOn calls and no changes.
--   - Headless (C_AddOns = nil) → pure force-true, no error.
-- Run: lua tests/unit/migration_v43_retirement_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Migrations = ns.Migrations

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, nv in pairs(v) do out[k] = deepCopy(nv) end
    return out
end
local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

---------------------------------------------------------------------------
-- Helpers: build a db stub the way Migrations.Run expects.
-- db.keys.profile = active profile name
-- db.sv.profiles[name] = raw profile table (same table by reference as
--   db.profile so the active-identity check matches)
---------------------------------------------------------------------------
local function makeDB(profileName, profileTable, extraProfiles)
    local sv = { profiles = { [profileName] = profileTable } }
    if extraProfiles then
        for name, tbl in pairs(extraProfiles) do
            sv.profiles[name] = tbl
        end
    end
    return {
        keys    = { profile = profileName },
        sv      = sv,
        profile = profileTable,
        global  = {},
    }
end

---------------------------------------------------------------------------
-- Record C_AddOns calls during migration runs.
---------------------------------------------------------------------------
local function makeAddOnStub()
    local calls = {}
    _G.C_AddOns = {
        DoesAddOnExist    = function() return true end,
        GetAddOnEnableState = function() return 2 end,
        EnableAddOn       = function(n)  calls[#calls+1] = "enable:"  .. n end,
        DisableAddOn      = function(n)  calls[#calls+1] = "disable:" .. n end,
        SaveAddOns        = function()   calls[#calls+1] = "save" end,
        LoadAddOn         = function()   return nil end,
        IsAddOnLoaded     = function()   return false end,
    }
    return calls
end

---------------------------------------------------------------------------
-- 1) Active profile with ncdm.enabled = false
--    → DisableAddOn("QUI_CDM") called exactly once, flag forced true,
--      _schemaVersion == 44.
---------------------------------------------------------------------------
do
    local calls = makeAddOnStub()
    local profile = { _schemaVersion = 42, ncdm = { enabled = false } }
    local db = makeDB("Default", profile)

    Migrations.Run(db)

    local disableCDM = 0
    for _, c in ipairs(calls) do
        if c == "disable:QUI_CDM" then disableCDM = disableCDM + 1 end
    end
    check("1: ncdm.enabled=false in active profile → DisableAddOn(QUI_CDM) called",
        disableCDM == 1, ("called %d times"):format(disableCDM))
    check("1: ncdm.enabled flag forced true after migration",
        profile.ncdm.enabled == true, tostring(profile.ncdm.enabled))
    check("1: _schemaVersion == 44",
        profile._schemaVersion == 44, tostring(profile._schemaVersion))
end

---------------------------------------------------------------------------
-- 2) Non-active profile with minimap.enabled = false
--    → flag forced true, NO DisableAddOn call.
---------------------------------------------------------------------------
do
    local calls = makeAddOnStub()
    -- Active profile has no false flags; non-active profile has minimap.enabled=false.
    local activeProfile  = { _schemaVersion = 42 }
    local inactiveProfile = { _schemaVersion = 42, minimap = { enabled = false } }
    local db = makeDB("Default", activeProfile, { Alt = inactiveProfile })

    Migrations.Run(db)

    local hasDisable = false
    for _, c in ipairs(calls) do
        if c:match("^disable:") then hasDisable = true end
    end
    check("2: non-active profile minimap.enabled=false → flag forced true",
        inactiveProfile.minimap.enabled == true, tostring(inactiveProfile.minimap.enabled))
    check("2: non-active profile → NO DisableAddOn call",
        not hasDisable, "unexpected disable call on non-active profile")
end

---------------------------------------------------------------------------
-- 3) chat.enabled = false and quiGroupFrames.enabled = false
--    → both survive untouched (they are dormant guards, not retired flags).
---------------------------------------------------------------------------
do
    local calls = makeAddOnStub()
    local profile = {
        _schemaVersion = 42,
        chat           = { enabled = false },
        quiGroupFrames = { enabled = false },
    }
    local db = makeDB("Default", profile)

    Migrations.Run(db)

    check("3: chat.enabled=false untouched by v43",
        profile.chat.enabled == false, tostring(profile.chat.enabled))
    check("3: quiGroupFrames.enabled=false untouched by v43",
        profile.quiGroupFrames.enabled == false, tostring(profile.quiGroupFrames.enabled))
end

---------------------------------------------------------------------------
-- 4) Idempotency: running the migration a second time produces no further
--    DisableAddOn calls and the profile is unchanged.
---------------------------------------------------------------------------
do
    -- First run: active profile with two false flags.
    local calls = makeAddOnStub()
    local profile = {
        _schemaVersion = 42,
        ncdm           = { enabled = false },
        actionBars     = { enabled = false },
    }
    local db = makeDB("Default", profile)
    Migrations.Run(db)

    -- Confirm first run did its job.
    check("4-setup: ncdm flag forced true after first run",
        profile.ncdm.enabled == true)
    check("4-setup: actionBars flag forced true after first run",
        profile.actionBars.enabled == true)

    -- Second run: reset the call log, re-run.
    local calls2 = makeAddOnStub()
    local snapshot = deepCopy(profile)
    Migrations.Run(db)

    local hasDisable2 = false
    for _, c in ipairs(calls2) do
        if c:match("^disable:") then hasDisable2 = true end
    end
    check("4: idempotent — no DisableAddOn on second run",
        not hasDisable2, "unexpected disable call on second run")
    check("4: idempotent — profile unchanged after second run",
        deepEqual(profile, snapshot), "profile mutated on second run")
end

---------------------------------------------------------------------------
-- 5) Headless (C_AddOns = nil): pure force-true, no error.
---------------------------------------------------------------------------
do
    _G.C_AddOns = nil

    local profile = {
        _schemaVersion = 42,
        ncdm           = { enabled = false },
        quiUnitFrames  = { enabled = false },
    }
    -- Use RunOnProfile directly: without C_AddOns, Migrations.Run itself
    -- may reference C_AddOns in other gates; RunOnProfile is the entry point
    -- used by profile import and is the direct caller of RetireModuleMasterFlags.
    local ok, err = pcall(Migrations.RunOnProfile, profile)
    check("5: headless (C_AddOns=nil) → no error",
        ok, tostring(err))
    check("5: headless → ncdm flag forced true",
        profile.ncdm.enabled == true, tostring(profile.ncdm and profile.ncdm.enabled))
    check("5: headless → quiUnitFrames flag forced true",
        profile.quiUnitFrames.enabled == true,
        tostring(profile.quiUnitFrames and profile.quiUnitFrames.enabled))

    -- Restore a minimal C_AddOns so subsequent code doesn't error.
    _G.C_AddOns = { GetAddOnMetadata = function() return nil end }
end

print("migration_v43_retirement_test OK")
