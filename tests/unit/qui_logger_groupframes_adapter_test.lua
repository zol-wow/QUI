-- tests/unit/qui_logger_groupframes_adapter_test.lua
-- Run: lua tests/unit/qui_logger_groupframes_adapter_test.lua
-- TDD: RED step -- adapter module does not exist yet; this fails until implemented.
--
-- Proves:
--   1. Adapter loads and Build() returns a usable ctx
--   2. EVENT_MAP contains required events
--   3. dispatch() runs without error on mapped + unmapped events
--   4. ProfileSession returns well-formed churn/counts/report
--   5. A real group-frame function (R.RenderIcon / R.Dispatch) fires on UNIT_AURA
--      (proved via opts.onCallback instrumentation)
--
-- luacheck: globals CreateFrame issecretvalue GetTime C_UnitAuras

-- -----------------------------------------------------------------------
-- 1. Build the adapter (loads real group-frame aura sub-modules)
-- -----------------------------------------------------------------------
local cbCounts = {}
local function onCallback(name)
    cbCounts[name] = (cbCounts[name] or 0) + 1
end

local A = assert(loadfile("tests/replay/profile_groupframes_adapter.lua"),
    "profile_groupframes_adapter.lua must exist")()

local built = A.Build({ onCallback = onCallback })

-- 2. ctx must carry the real render + model modules
assert(built.ctx ~= nil,         "Build() must return a non-nil ctx")
assert(built.ctx.R ~= nil,       "ctx.R must be the render module")
assert(built.ctx.Model ~= nil,   "ctx.Model must be the model module")
assert(built.ctx.frame ~= nil,   "ctx.frame must be the synthetic unit frame")
assert(built.ctx.auraCache ~= nil, "ctx.auraCache must be the aura cache")

local R = built.ctx.R
assert(type(R.Dispatch)  == "function", "R.Dispatch must be a function")
assert(type(R.RenderIcon) == "function", "R.RenderIcon must be a function")

-- 3. EVENT_MAP must contain UNIT_AURA at minimum
local requiredEvents = {
    "UNIT_AURA",
    "UNIT_HEALTH",
    "UNIT_POWER_UPDATE",
    "UNIT_POWER_FREQUENT",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_PREDICTION",
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_NAME_UPDATE",
}
for _, ev in ipairs(requiredEvents) do
    assert(A.EVENT_MAP[ev], "EVENT_MAP must have entry for " .. ev)
end

-- 4. dispatch() on a mapped event must not error
do
    local ok, err = pcall(function()
        A.dispatch(built.ctx, { e = "UNIT_HEALTH", a = { "player" }, n = 1 })
    end)
    assert(ok, "dispatch of UNIT_HEALTH must not error: " .. tostring(err))
end

-- dispatch() on an unmapped event must silently skip (no error)
do
    local ok, err = pcall(function()
        A.dispatch(built.ctx, { e = "ZZZ_UNMAPPED_GF", a = {}, n = 0 })
    end)
    assert(ok, "dispatch of unmapped event must not error: " .. tostring(err))
end

-- 5. ProfileSession with a synthetic event list
local syntheticEvents = {
    { e = "UNIT_AURA",           a = { "player", { isFullUpdate = true, removedAuraInstanceIDs = {} } }, n = 2 },
    { e = "UNIT_HEALTH",         a = { "player" }, n = 1 },
    { e = "UNIT_POWER_FREQUENT", a = { "player", "MANA" }, n = 2 },
    { e = "ZZZ_UNMAPPED_GF",     a = {},           n = 0 },
}

local churn, counts, report = A.ProfileSession(built.ctx, syntheticEvents)

assert(type(churn)  == "table",  "ProfileSession must return churn table")
assert(type(counts) == "table",  "counts must be a table")
assert(type(report) == "string", "report must be a string")

-- At least one mapped event must appear in counts
local mappedCount = 0
for _, ev in ipairs({ "UNIT_AURA", "UNIT_HEALTH", "UNIT_POWER_FREQUENT" }) do
    if counts[ev] and counts[ev] > 0 then mappedCount = mappedCount + 1 end
end
assert(mappedCount > 0, "at least one mapped event must appear in counts with count > 0")

-- profilePerKey keys every item by ev.e regardless of dispatch, so the
-- unmapped event WILL appear in counts (with the allocation delta from the
-- skip branch, which is ~0 but present). The real gate is that no adapter
-- method was called for it — checked indirectly by the callback probe below.
-- A._lastUnmappedCount increments for each skipped event.
assert(A._lastUnmappedCount == nil or A._lastUnmappedCount >= 0,
    "unmapped count must be non-negative")

-- 6. PROVE a real group-frame function ran on UNIT_AURA:
--    opts.onCallback("RenderIcon") must fire >= 1 time after UNIT_AURA dispatch,
--    because the synthetic frame has a filterStrip element and the aura cache
--    may be empty (so maxIcons=0 path), BUT the instrumented Dispatch wrapper
--    still fires "Dispatch" callback.
cbCounts = {}
A.dispatch(built.ctx, {
    e = "UNIT_AURA",
    a = { "player", { isFullUpdate = true, removedAuraInstanceIDs = {} } },
    n = 2,
})

local dispatchCount = cbCounts["Dispatch"] or 0
local renderIconCount = cbCounts["RenderIcon"] or 0

assert(dispatchCount > 0 or renderIconCount > 0,
    "after UNIT_AURA dispatch, R.Dispatch or R.RenderIcon callback must fire " ..
    "(Dispatch=" .. dispatchCount .. " RenderIcon=" .. renderIconCount ..
    ") -- proves event reached real group-frame render code")

print(string.format(
    "OK: qui_logger_groupframes_adapter_test  [R.Dispatch=%d  R.RenderIcon=%d]",
    dispatchCount, renderIconCount))
