-- tests/unit/cdm_zone_transition_reconcile_drain_test.lua
-- Regression: a SPELLS_CHANGED reconcile suppressed during the post-zone-in
-- settling window must be re-run when that window closes.
--
-- cdm_spelldata.lua sets _inZoneTransition = true on PLAYER_ENTERING_WORLD and
-- clears it 2s later. While set, the SPELLS_CHANGED handler returns early
-- (WoW spell APIs are stale right after a zone/instance change). But the 2s
-- timer only flips the flag back — it never re-runs the reconcile that was
-- dropped. If the only meaningful SPELLS_CHANGED of a key entry lands inside
-- the window (and none fires after it), the dormant reconcile never happens:
-- spells stay shelved / mis-displayed until /reload.
--
-- Contract: record that a SPELLS_CHANGED was suppressed during the window, and
-- when _inZoneTransition clears, drain it by running the reconcile.
--
-- Run from repo root: lua tests/unit/cdm_zone_transition_reconcile_drain_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local spelldata = readAll("QUI_CDM/cdm/cdm_spelldata.lua")

-- Slice an `elseif event == "<NAME>" then` branch from the runtime event
-- handler: from its guard to `stopMarker` (the next branch, or a stable anchor
-- after the handler for the last branch).
local function sliceBetween(startMarker, stopMarker)
    local startPos = assert(
        string.find(spelldata, startMarker, 1, true),
        "expected to find: " .. startMarker
    )
    local stopPos = stopMarker
        and select(1, string.find(spelldata, stopMarker, startPos + #startMarker, true))
    return spelldata:sub(startPos, (stopPos or (#spelldata + 1)) - 1)
end

local spellsChangedBranch =
    sliceBetween('elseif event == "SPELLS_CHANGED" then',
                 'elseif event == "PLAYER_EQUIPMENT_CHANGED" then')
-- PLAYER_ENTERING_WORLD is the last branch; anchor on the PerfRegistry line
-- that immediately follows the handler closure.
local pewBranch =
    sliceBetween('elseif event == "PLAYER_ENTERING_WORLD" then',
                 "ns.QUI_PerfRegistry")

-- Sanity: SPELLS_CHANGED still drops its reconcile during the settling window,
-- and PEW still opens/closes that window.
assert(
    string.find(spellsChangedBranch, "if _inZoneTransition then", 1, true),
    "expected SPELLS_CHANGED to short-circuit during _inZoneTransition"
)
assert(
    string.find(pewBranch, "_inZoneTransition = true", 1, true)
        and string.find(pewBranch, "_inZoneTransition = false", 1, true),
    "expected PLAYER_ENTERING_WORLD to open and later close _inZoneTransition"
)

local DRAIN_FLAG = "_spellsChangedDuringZoneTransition"

-- REGRESSION 1: SPELLS_CHANGED suppressed during the window must record that a
-- reconcile is owed.
assert(
    string.find(spellsChangedBranch, DRAIN_FLAG, 1, true),
    "SPELLS_CHANGED must set " .. DRAIN_FLAG .. " when it short-circuits during "
        .. "the zone-transition window, so the dropped reconcile can be drained."
)

-- REGRESSION 2: when _inZoneTransition clears, the owed reconcile must run.
assert(
    string.find(pewBranch, DRAIN_FLAG, 1, true),
    "the _inZoneTransition clear path must drain " .. DRAIN_FLAG .. "."
)
assert(
    string.find(pewBranch, "RunReconcileSequence", 1, true),
    "when _inZoneTransition clears with a suppressed SPELLS_CHANGED pending, the "
        .. "reconcile (RunReconcileSequence) must run — otherwise the drop is "
        .. "permanent until /reload."
)

print("OK: cdm_zone_transition_reconcile_drain_test")
