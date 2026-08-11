-- tests/unit/aura_events_nameplate_tier_test.lua
-- Run: lua tests/unit/aura_events_nameplate_tier_test.lua
--
-- The "nameplate" subscription tier (plans/009-nameplates.md Phase 0):
--   * lazily creates 40 RegisterUnitEvent("UNIT_AURA", "nameplateN") frames
--     on first Subscribe — zero frames before that,
--   * dispatches nameplate deltas through the coalesced pipeline to
--     "nameplate" subscribers,
--   * does NOT widen the "all" tier: nameplate events reach "all" only under
--     the pre-existing interest predicate (tooltip unit / target scoping),
--   * does not double-merge deltas when the global router and the dedicated
--     unit frame both see the same event.

local function noop() end

local env = { inCombat = false, tooltipShown = false, tooltipUnit = nil }

function InCombatLockdown() return env.inCombat end
function wipe(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

GameTooltip = {
    IsShown = function() return env.tooltipShown end,
    GetUnit = function() return env.tooltipUnit and "SomeName" or nil, env.tooltipUnit end,
}

local createdFrames = {}
function CreateFrame()
    local f = {
        _onEvent = nil,
        _onUpdate = nil,
        _registeredGlobal = false,
        _registeredUnits = nil,
        RegisterEvent = function(self, event)
            if event == "UNIT_AURA" then self._registeredGlobal = true end
        end,
        RegisterUnitEvent = function(self, event, unit)
            self._registeredUnits = self._registeredUnits or {}
            self._registeredUnits[unit] = true
        end,
        Show = noop,
        Hide = noop,
        SetScript = function(self, script, handler)
            if script == "OnEvent" then self._onEvent = handler
            elseif script == "OnUpdate" then self._onUpdate = handler end
        end,
    }
    createdFrames[#createdFrames + 1] = f
    return f
end

local ns = {}
assert(loadfile("core/aura_events.lua"))("QUI", ns)
local AuraEvents = ns.AuraEvents
assert(AuraEvents, "core/aura_events.lua must publish ns.AuraEvents")

local eventFrame, coalesceFrame
local function findUnitFrame(unit)
    for _, f in ipairs(createdFrames) do
        if f._registeredUnits and f._registeredUnits[unit] then return f end
    end
    return nil
end
for _, f in ipairs(createdFrames) do
    if f._registeredGlobal and f._onEvent then eventFrame = f end
    if f._onUpdate then coalesceFrame = f end
end
assert(eventFrame and coalesceFrame, "router/coalescer frames not found")

local framesBeforeSubscribe = #createdFrames

local function test(n, f) print(n); f(); print("  ok") end

test("lazy: no nameplate unit frames exist before the first Subscribe", function()
    assert(not findUnitFrame("nameplate1"), "nameplate frames must not exist pre-Subscribe")
end)

-- Subscribe and capture dispatches. Delta tables are POOLED and wiped after
-- dispatch (the tier's documented contract), so snapshot counts at dispatch
-- time instead of retaining the reference.
local npSeen, allSeen = {}, {}
AuraEvents:Subscribe("nameplate", function(unit, info)
    local snap = nil
    if info then
        snap = { added = {}, nRemoved = #(info.removedAuraInstanceIDs or {}) }
        for i, v in ipairs(info.addedAuras or {}) do snap.added[i] = v end
    end
    npSeen[#npSeen + 1] = { unit = unit, info = info, snap = snap }
end)
AuraEvents:Subscribe("all", function(unit) allSeen[unit] = (allSeen[unit] or 0) + 1 end)

local function drain()
    npSeen, allSeen = {}, {}
    coalesceFrame._onUpdate(coalesceFrame)
end

test("Subscribe('nameplate') creates the 40 per-unit frames", function()
    assert(#createdFrames == framesBeforeSubscribe + 40,
        "expected exactly 40 new frames, got " .. (#createdFrames - framesBeforeSubscribe))
    for i = 1, 40 do
        assert(findUnitFrame("nameplate" .. i), "missing frame for nameplate" .. i)
    end
    local before = #createdFrames
    AuraEvents:Subscribe("nameplate", noop)
    assert(#createdFrames == before, "second Subscribe must not create more frames")
end)

local np5 = findUnitFrame("nameplate5")

test("nameplate deltas reach 'nameplate' subscribers through the coalescer", function()
    env.inCombat = true -- combat must NOT gate the nameplate tier
    local delta = { addedAuras = { { spellId = 589 } }, removedAuraInstanceIDs = {}, updatedAuraInstanceIDs = {} }
    npSeen = {}
    np5._onEvent(np5, "UNIT_AURA", "nameplate5", delta)
    -- the global router also sees the event (mirrors live dispatch)
    eventFrame._onEvent(eventFrame, "UNIT_AURA", "nameplate5", delta)
    coalesceFrame._onUpdate(coalesceFrame)
    assert(#npSeen == 1, "expected exactly one dispatch, got " .. #npSeen)
    assert(npSeen[1].unit == "nameplate5")
    assert(npSeen[1].info == delta, "single delta must pass through un-merged")
    env.inCombat = false
end)

test("'all' tier stays narrow: nameplate events don't reach it by default", function()
    env.inCombat, env.tooltipShown, env.tooltipUnit = false, false, nil
    local delta = { addedAuras = {}, removedAuraInstanceIDs = { 11 }, updatedAuraInstanceIDs = {} }
    npSeen, allSeen = {}, {}
    np5._onEvent(np5, "UNIT_AURA", "nameplate5", delta)
    eventFrame._onEvent(eventFrame, "UNIT_AURA", "nameplate5", delta)
    coalesceFrame._onUpdate(coalesceFrame)
    assert(#npSeen == 1, "nameplate tier must receive the event")
    assert(not allSeen["nameplate5"], "'all' must NOT receive uninteresting nameplate events")
end)

test("'all' still receives the tooltip's own nameplate unit (pre-tier contract)", function()
    env.inCombat, env.tooltipShown, env.tooltipUnit = false, true, "nameplate5"
    local delta = { addedAuras = {}, removedAuraInstanceIDs = {}, updatedAuraInstanceIDs = { 7 } }
    npSeen, allSeen = {}, {}
    np5._onEvent(np5, "UNIT_AURA", "nameplate5", delta)
    eventFrame._onEvent(eventFrame, "UNIT_AURA", "nameplate5", delta)
    coalesceFrame._onUpdate(coalesceFrame)
    assert(allSeen["nameplate5"] == 1, "tooltip's own nameplate unit must reach 'all' exactly once")
    assert(#npSeen == 1, "nameplate tier must receive it too")
    assert(npSeen[1].info == delta, "no double-merge: both frames saw the same event once")
    env.tooltipShown, env.tooltipUnit = false, nil
end)

test("two distinct deltas in one frame merge without duplication", function()
    local d1 = { addedAuras = { "a" }, removedAuraInstanceIDs = {}, updatedAuraInstanceIDs = {} }
    local d2 = { addedAuras = { "b" }, removedAuraInstanceIDs = { 42 }, updatedAuraInstanceIDs = {} }
    npSeen = {}
    -- two separate UNIT_AURA events for the same unit within one render frame
    np5._onEvent(np5, "UNIT_AURA", "nameplate5", d1)
    eventFrame._onEvent(eventFrame, "UNIT_AURA", "nameplate5", d1)
    np5._onEvent(np5, "UNIT_AURA", "nameplate5", d2)
    eventFrame._onEvent(eventFrame, "UNIT_AURA", "nameplate5", d2)
    coalesceFrame._onUpdate(coalesceFrame)
    assert(#npSeen == 1, "coalesced to one dispatch")
    local snap = npSeen[1].snap
    assert(#snap.added == 2, "merged addedAuras must have exactly 2 entries, got " .. #snap.added)
    assert(snap.added[1] == "a" and snap.added[2] == "b", "merged in order, no duplicates")
    assert(snap.nRemoved == 1, "merged removed IDs must have exactly 1 entry")
    -- pooled delta contract: the merged accumulator is wiped after dispatch
    assert(#npSeen[1].info.addedAuras == 0, "pooled merged table must be wiped after dispatch")
end)

test("full update (nil updateInfo) dispatches nil to nameplate subscribers", function()
    npSeen = {}
    np5._onEvent(np5, "UNIT_AURA", "nameplate5", nil)
    eventFrame._onEvent(eventFrame, "UNIT_AURA", "nameplate5", nil)
    coalesceFrame._onUpdate(coalesceFrame)
    assert(#npSeen == 1 and npSeen[1].info == nil, "full update must arrive as nil updateInfo")
end)

test("roster and target dispatch is unchanged by the new tier", function()
    env.inCombat, env.tooltipShown = false, false
    allSeen = {}
    eventFrame._onEvent(eventFrame, "UNIT_AURA", "target", nil)
    coalesceFrame._onUpdate(coalesceFrame)
    assert(allSeen["target"] == 1, "target must still reach 'all'")
end)

test("invalid filter error mentions nameplate", function()
    local ok, err = pcall(function() AuraEvents:Subscribe("bogus", noop) end)
    assert(not ok and err:find("nameplate"), "error message must list the nameplate filter")
end)

print("OK: aura_events_nameplate_tier_test")
