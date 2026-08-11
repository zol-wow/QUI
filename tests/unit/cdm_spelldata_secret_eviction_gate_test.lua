-- tests/unit/cdm_spelldata_secret_eviction_gate_test.lua
-- Run: lua tests/unit/cdm_spelldata_secret_eviction_gate_test.lua
--
-- Structural regression (the eviction/rescan helpers are file-local and the
-- capture cache needs a full catalog to populate; the suite asserts source
-- structure -- see cdm_buff_layout_no_combat_end_populate_test for precedent).
--
-- 12.1: the Query* instance-ID wrappers bail to nil while auras are secret
-- (cdm_sources AreAurasSecret gate). Two spelldata paths must respect that:
--
--   1. EvictDeadCacheEntriesForUnit treats a nil probe as "aura gone" and
--      releases the entry. While auras are secret, nil means "query gated",
--      not "dead" -- probing anyway would evict every live entry mid-combat.
--      The helper must bail BEFORE its probe loop.
--
--   2. RescanCapturedAurasForUnit releases the unit's cache and repopulates
--      via AuraUtil.ForEachAura -- an index-based getter that THROWS while
--      auras are secret. The bail must come BEFORE the release, or a combat
--      isFullUpdate empties the cache with no way to refill it.

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

local src = readAll("QUI_CDM/cdm/cdm_spelldata.lua")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

---------------------------------------------------------------------------
-- 1. EvictDeadCacheEntriesForUnit: AreAurasSecret bail before the probe.
---------------------------------------------------------------------------
local evictStart = assert(string.find(src, "local function EvictDeadCacheEntriesForUnit(unit)", 1, true),
    "EvictDeadCacheEntriesForUnit definition should exist")
local evictProbe = assert(string.find(src, "Sources.QueryAuraDataByAuraInstanceID(unit, entry.auraInstanceID)", evictStart, true),
    "eviction probe call should exist")
local evictBail = string.find(src, "Sources.AreAurasSecret and Sources.AreAurasSecret()", evictStart, true)

check("EvictDeadCacheEntriesForUnit must gate on AreAurasSecret",
    evictBail ~= nil,
    "no AreAurasSecret bail found in/after EvictDeadCacheEntriesForUnit")

check("eviction gate must come BEFORE the probe loop",
    evictBail ~= nil and evictBail < evictProbe,
    "AreAurasSecret bail found after the probe call -- entries already released")

---------------------------------------------------------------------------
-- 2. RescanCapturedAurasForUnit: bail before ReleaseCapturedAurasForUnit.
---------------------------------------------------------------------------
local rescanStart = assert(string.find(src, "local function RescanCapturedAurasForUnit(unit)", 1, true),
    "RescanCapturedAurasForUnit definition should exist")
-- The target fast-path releases and returns before the aura walk; the
-- gate protects the non-target branch. Find the SECOND release call (the one
-- followed by the repopulate walk). The walk is the probe-first
-- ForEachReadableAura iterator — AuraUtil.ForEachAura is banned (its
-- internal `if auraInfo` truth-test throws on whole-secret auras).
local firstRelease = assert(string.find(src, "ReleaseCapturedAurasForUnit(unit)", rescanStart, true),
    "target-branch release should exist")
local secondRelease = string.find(src, "ReleaseCapturedAurasForUnit(unit)", firstRelease + 1, true)
local rescanBail = string.find(src, "Sources.AreAurasSecret and Sources.AreAurasSecret()", rescanStart, true)
local forEach = assert(string.find(src, "ForEachReadableAura(unit,", rescanStart, true),
    "ForEachReadableAura repopulate should exist")

check("RescanCapturedAurasForUnit must gate on AreAurasSecret",
    rescanBail ~= nil and rescanBail < forEach,
    "no AreAurasSecret bail found before the repopulate walk")

check("rescan gate must come BEFORE the non-target release",
    rescanBail ~= nil and secondRelease ~= nil and rescanBail < secondRelease,
    "bail sits after the release -- combat isFullUpdate would empty the cache and never refill")

check("rescan gate must come AFTER the target fast-path (target release still unconditional)",
    rescanBail ~= nil and firstRelease ~= nil and firstRelease < rescanBail,
    "gate placed before the target branch -- target swap cleanup would be skipped in combat")

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
