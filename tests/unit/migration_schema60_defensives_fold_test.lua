-- tests/unit/migration_schema60_defensives_fold_test.lua
-- Run: lua5.1 tests/unit/migration_schema60_defensives_fold_test.lua
--
-- Migrations.FoldDefensiveIndicatorIntoElements (schema-60 step d): the legacy GF
-- defensive indicator (healer.defensiveIndicator) becomes a seeded
-- "defensives" element. Injection only into LATCHED "*" buckets (unlatched
-- stores get the strip from the surface-aware runtime seed); enabled carries
-- over ONLY when the raw SV stored enabled == true (raw-SV absent-key rule:
-- the AceDB default was false on both surfaces). dedupeDefensives (dead since
-- the pipeline unification) is stripped from EVERY element store: GF (all
-- spec buckets), UF, buffborders.

local envmod = dofile("tools/_addon_env.lua")
local ns = envmod.LoadCore()
envmod.LoadAddonFile("QUI_GroupFrames/groupframes/groupframes_aura_model.lua", "QUI_GroupFrames", ns)
local M = ns.Migrations
local Model = ns.QUI_GroupFramesAuraModel

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function findById(bucket, id)
    for _, e in ipairs(bucket or {}) do if e.id == id then return e end end
end

local function gfSurface(diTable)
    return {
        auras = {
            elementsSeeded = true,
            elements = { ["*"] = {
                { id = "debuffs", mode = "filterStrip", auraType = "HARMFUL", dedupeDefensives = true },
                { id = "buffs", mode = "filterStrip", auraType = "HELPFUL", dedupeDefensives = true },
            } },
        },
        healer = diTable and { defensiveIndicator = diTable } or {},
    }
end

----------------------------------------------------------------------------
-- 1) Latched party with stored enabled=true → injected enabled=true.
--    Latched raid with NO stored table → injected enabled=false.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiGroupFrames = {
            party = gfSurface({ enabled = true, iconSize = 20 }),
            raid  = gfSurface(nil),
        },
    }
    M.RunOnProfile(profile)

    local pd = findById(profile.quiGroupFrames.party.auras.elements["*"], "defensives")
    check("party: defensives injected", pd ~= nil)
    check("party: enabled carried over", pd and pd.enabled == true, pd and tostring(pd.enabled))
    check("party: geometry is SHIPPED not old (iconSize 15)", pd and pd.iconSize == 15,
        pd and tostring(pd.iconSize))
    check("party: green borderColor", pd and pd.borderColor and pd.borderColor[2] == 0.8, "missing")

    local rd = findById(profile.quiGroupFrames.raid.auras.elements["*"], "defensives")
    check("raid: defensives injected", rd ~= nil)
    check("raid: absent table -> disabled", rd and rd.enabled == false, rd and tostring(rd.enabled))

    check("party: old table deleted", profile.quiGroupFrames.party.healer.defensiveIndicator == nil)
    check("party: dedupeDefensives stripped",
        profile.quiGroupFrames.party.auras.elements["*"][1].dedupeDefensives == nil
        and profile.quiGroupFrames.party.auras.elements["*"][2].dedupeDefensives == nil)
    check("stamped to current (60)", profile._schemaVersion == 60, tostring(profile._schemaVersion))
end

----------------------------------------------------------------------------
-- 2) Stored enabled=false → injected disabled. Existing defensives element
--    → NO duplicate, existing element untouched.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiGroupFrames = { party = gfSurface({ enabled = false }) },
    }
    table.insert(profile.quiGroupFrames.party.auras.elements["*"],
        { id = "defensives", mode = "filterStrip", auraType = "HELPFUL", enabled = true, iconSize = 99 })
    M.RunOnProfile(profile)
    local bucket = profile.quiGroupFrames.party.auras.elements["*"]
    local n = 0
    for _, e in ipairs(bucket) do if e.id == "defensives" then n = n + 1 end end
    check("existing defensives: no duplicate", n == 1, tostring(n))
    check("existing defensives: untouched", findById(bucket, "defensives").iconSize == 99)
end

----------------------------------------------------------------------------
-- 3) UNLATCHED store: no injection (runtime seed owns it), old table still
--    deleted.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiGroupFrames = { party = {
            auras = {},
            healer = { defensiveIndicator = { enabled = true } },
        } },
    }
    M.RunOnProfile(profile)
    check("unlatched: no elements table invented",
        profile.quiGroupFrames.party.auras.elements == nil
        or findById(profile.quiGroupFrames.party.auras.elements["*"], "defensives") == nil)
    check("unlatched: old table still deleted",
        profile.quiGroupFrames.party.healer.defensiveIndicator == nil)
end

----------------------------------------------------------------------------
-- 4) dedupeDefensives stripped from UF and buffborders stores too (all
--    buckets, including GF per-spec buckets).
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiGroupFrames = { party = {
            auras = { elementsSeeded = true, elements = {
                ["*"] = { { id = "buffs", mode = "filterStrip", dedupeDefensives = true } },
                [268] = { { id = "buffs", mode = "filterStrip", dedupeDefensives = true } },
            } },
            healer = {},
        } },
        -- Latched stores: an alpha16-era profile reaching the fold already ran
        -- the elements seed, and the squash's seed step would clobber an
        -- UNLATCHED store before the fold ever saw it.
        quiUnitFrames = { player = { auras = { elementsSeeded = true, elements = { ["*"] = {
            { id = "e1", mode = "filterStrip", dedupeDefensives = true },
        } } } } },
        buffBorders = { buffAuras = { elementsSeeded = true, elements = { ["*"] = {
            { id = "e1", mode = "filterStrip", dedupeDefensives = true },
        } } } },
    }
    M.RunOnProfile(profile)
    check("GF spec bucket stripped",
        profile.quiGroupFrames.party.auras.elements[268][1].dedupeDefensives == nil)
    check("UF stripped",
        profile.quiUnitFrames.player.auras.elements["*"][1].dedupeDefensives == nil)
    check("buffborders stripped",
        profile.buffBorders.buffAuras.elements["*"][1].dedupeDefensives == nil)
end

----------------------------------------------------------------------------
-- 5) Idempotent: second run changes nothing.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiGroupFrames = { party = gfSurface({ enabled = true }) },
    }
    M.RunOnProfile(profile)
    local before = findById(profile.quiGroupFrames.party.auras.elements["*"], "defensives")
    M.RunOnProfile(profile)
    local after = findById(profile.quiGroupFrames.party.auras.elements["*"], "defensives")
    -- debuffs + buffs + defensives.
    check("idempotent", before == after and #profile.quiGroupFrames.party.auras.elements["*"] == 3)
end

----------------------------------------------------------------------------
-- 6) PARITY: the migration's injected strip must equal
--    Model.DefaultStripBucket("party")[3] field-for-field (enabled excepted —
--    the migration carries the user's old value). Guards against drift
--    between the two literal definitions.
----------------------------------------------------------------------------
do
    local profile = {
        _schemaVersion = 47,
        quiGroupFrames = { party = gfSurface({ enabled = true }) },
    }
    M.RunOnProfile(profile)
    local injected = findById(profile.quiGroupFrames.party.auras.elements["*"], "defensives")
    local shipped = Model.DefaultStripBucket("party")[3]

    local function deepEq(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    local ic, sc = {}, {}
    for k, v in pairs(injected) do if k ~= "enabled" then ic[k] = v end end
    for k, v in pairs(shipped) do if k ~= "enabled" then sc[k] = v end end
    check("migration strip == shipped strip (mod enabled)", deepEq(ic, sc), "drift")
end

if failures > 0 then os.exit(1) end
print("migration_schema60_defensives_fold_test: all checks passed")
