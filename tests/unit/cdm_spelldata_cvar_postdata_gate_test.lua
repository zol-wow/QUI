-- tests/unit/cdm_spelldata_cvar_postdata_gate_test.lua
-- Run: lua tests/unit/cdm_spelldata_cvar_postdata_gate_test.lua
--
-- Root-cause guard for the cold-login CDM taint: SetCVar("cooldownViewerEnabled")
-- from addon execution fires Blizzard's CVar callback synchronously in QUI's
-- (tainted) execution. If the CooldownViewer data feed has already loaded,
-- that callback flips the hidden native viewers shown on QUI's stack:
-- OnShow registers UNIT_AURA and RefreshLayout re-mints every item frame
-- under QUI taint, and every later UNIT_AURA dispatch throws on the
-- DisallowTaintedAccess aura map (CooldownViewer.lua:1873 / :1702).
-- So the sync may only write in the pre-data window; once
-- COOLDOWN_VIEWER_DATA_LOADED has fired (or the catalog reports the viewer
-- ready) a 0->1 write must be skipped and left to Blizzard's secure paths.

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown() return false end
function IsPlayerSpell() return false end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local frames = {}
function CreateFrame()
    local f = {
        events = {},
    }
    function f:RegisterEvent(ev) self.events[ev] = true end
    function f:RegisterUnitEvent(ev) self.events[ev] = true end
    function f:UnregisterEvent(ev) self.events[ev] = nil end
    function f:UnregisterAllEvents() wipe(self.events) end
    function f:SetScript(handler, fn) self[handler] = fn end
    frames[#frames + 1] = f
    return f
end

local function FireEvent(event, ...)
    local dispatched = false
    for _, f in ipairs(frames) do
        if f.events[event] and f.OnEvent then
            f:OnEvent(event, ...)
            dispatched = true
        end
    end
    return dispatched
end

local cvars = { cooldownViewerEnabled = "0" }
local setCVarCalls = {}
function GetCVar(name) return cvars[name] end
function GetCVarBool(name) return cvars[name] == "1" end
function SetCVar(name, value)
    setCVarCalls[#setCVarCalls + 1] = { name = name, value = tostring(value) }
    cvars[name] = tostring(value)
end

-- All four builtin containers pre-snapshotted (ownedSpells ~= nil) so
-- SnapshotUnsetBuiltinContainers reports ready. Without them, Initialize()'s
-- guaranteed cold-load-grace closer (Task 7) drives RunColdLoadReconcile
-- into its not-ready retry loop, which never terminates when drained against
-- this test's capturing C_Timer.After stub (see DrainTimers below).
local function ReadyDB()
    return { builtIn = true, ownedSpells = {}, dormantSpells = {}, removedSpells = {} }
end

local ns = {
    Addon = {
        db = {
            profile = { ncdm = {
                essential = ReadyDB(),
                utility = ReadyDB(),
                buff = ReadyDB(),
                trackedBar = ReadyDB(),
            } },
            global = {},
        },
    },
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
        QueryOverrideSpell = function(spellID) return spellID end,
        QueryBaseSpell = function() return nil end,
    },
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function() end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local Sync = ns.CDMSpellData.SyncCooldownViewerCVar
assert(type(Sync) == "function", "SyncCooldownViewerCVar must stay exported")

-- 1) PRE-DATA window: CVar off -> sync must force it on (Blizzard viewers
--    cannot flip shown yet: ShouldBeShown is false while
--    IsCooldownViewerAvailable() is false, so the write is taint-safe).
Sync()
assert(#setCVarCalls == 1
        and setCVarCalls[1].name == "cooldownViewerEnabled"
        and setCVarCalls[1].value == "1",
    "pre-data sync must still force cooldownViewerEnabled on")

-- 2) PRE-DATA re-assert after the engine loads saved CVars: the module must
--    re-sync at VARIABLES_LOADED (still pre-data on a cold login) so a saved
--    "0" is corrected inside the safe window, making later post-data syncs
--    read "1" and no-op.
cvars.cooldownViewerEnabled = "0"
assert(FireEvent("VARIABLES_LOADED"),
    "cdm_spelldata must re-sync the CVar at VARIABLES_LOADED (pre-data safe window)")
assert(#setCVarCalls == 2 and setCVarCalls[2].value == "1",
    "VARIABLES_LOADED sync must rewrite a saved 0 inside the pre-data window")

-- 3) Combat is irrelevant to the sync: the write itself is not a protected
--    action, and pre-data the CVar callback no-ops (IsCooldownViewerAvailable
--    false -> ShouldBeShown false -> no show, no RefreshData, no secret
--    comparisons). So an in-combat pre-data sync writes immediately -- no
--    PLAYER_REGEN_ENABLED deferral machinery.
cvars.cooldownViewerEnabled = "0"
_G.InCombatLockdown = function() return true end
Sync()
assert(#setCVarCalls == 3 and setCVarCalls[3].value == "1",
    "pre-data sync must write immediately even in combat (callback no-ops pre-data)")
for _, f in ipairs(frames) do
    assert(not f.events["PLAYER_REGEN_ENABLED"],
        "no PLAYER_REGEN_ENABLED deferral machinery should remain")
end
_G.InCombatLockdown = function() return false end

-- 4) No blind re-issues: Initialize() and the PEW self-heal must not sync the
--    CVar at all -- VARIABLES_LOADED is the single authoritative write point.
--    (The old Init+0.5s / PEW+1.5s re-issues were exactly what performed the
--    post-data hidden->shown flip on cold login.) Checked PRE-DATA so the
--    post-data gate cannot mask a re-issued write.
cvars.cooldownViewerEnabled = "0"
local timerCallbacks = {}
_G.C_Timer = {
    After = function(_, callback)
        timerCallbacks[#timerCallbacks + 1] = callback
    end,
}

local function DrainTimers()
    while #timerCallbacks > 0 do
        local cb = table.remove(timerCallbacks, 1)
        pcall(cb)
    end
end

local before = #setCVarCalls
ns.CDMSpellData:Initialize()
DrainTimers()
assert(#setCVarCalls == before,
    "Initialize() and its deferred init must not re-issue the CVar write")

pcall(FireEvent, "PLAYER_ENTERING_WORLD")
DrainTimers()
assert(#setCVarCalls == before,
    "the PEW self-heal must not re-issue the CVar write")
assert(ns.CDMSpellData.UpdateCVar == nil,
    "no public UpdateCVar re-issue API: RefreshAll and friends must not sync the CVar")

-- 4) POST-DATA via catalog readiness: with the viewer catalog reporting ready,
--    a 0->1 write must be skipped even if the data-loaded event was missed
--    (e.g. /reload, where the event does not re-fire).
cvars.cooldownViewerEnabled = "0"
ns.CDMCatalog = { IsCooldownViewerReady = function() return true end }
before = #setCVarCalls
Sync()
assert(#setCVarCalls == before,
    "catalog-ready 0->1 SetCVar must be skipped: it would flip hidden viewers shown on QUI's tainted stack")

-- 5) POST-DATA via the event latch: once COOLDOWN_VIEWER_DATA_LOADED has been
--    seen, the write stays blocked even if the catalog probe says not-ready.
ns.CDMCatalog = { IsCooldownViewerReady = function() return false end }
assert(FireEvent("COOLDOWN_VIEWER_DATA_LOADED"),
    "cdm_spelldata must watch COOLDOWN_VIEWER_DATA_LOADED to latch the post-data window")
Sync()
assert(#setCVarCalls == before,
    "post-data-latch 0->1 SetCVar must be skipped")

-- 6) CVar already on: no rewrite in any window.
cvars.cooldownViewerEnabled = "1"
Sync()
assert(#setCVarCalls == before, "an already-on CVar must never be rewritten")

print("OK cdm_spelldata_cvar_postdata_gate_test")
