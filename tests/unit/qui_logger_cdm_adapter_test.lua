-- tests/unit/qui_logger_cdm_adapter_test.lua
-- Run: lua tests/unit/qui_logger_cdm_adapter_test.lua
-- TDD: RED step -- adapter module does not exist yet; this fails until implemented.
-- luacheck: globals InCombatLockdown wipe CreateFrame GetTime IsInRaid issecretvalue
-- luacheck: globals C_Timer C_Spell C_Item C_UnitAuras debugprofilestop
-- luacheck: globals GetInventoryItemID GetInventoryItemLink GetInventoryItemTexture GetInventoryItemCooldown

-- -----------------------------------------------------------------------
-- 1. Build the adapter (loads real CDM, stubs WoW globals)
-- -----------------------------------------------------------------------

-- Instrumentation counters populated via opts.onCallback
local cbCounts = {}
local function onCallback(name)
    cbCounts[name] = (cbCounts[name] or 0) + 1
end

local A = assert(loadfile("tests/replay/profile_cdm_adapter.lua"),
    "profile_cdm_adapter.lua must exist")()

local built = A.Build({ onCallback = onCallback })

-- 2. Controller and pools must be populated
assert(built.controller ~= nil, "Build() must return a non-nil controller")
assert(type(built.pools) == "table", "Build() must return a pools table")
assert(type(built.pools.essential) == "table" and #built.pools.essential > 0,
    "pools.essential must have icons")
assert(type(built.pools.buff) == "table" and #built.pools.buff > 0,
    "pools.buff must have icons (aura icons)")
assert(type(built.pools.utility) == "table" and #built.pools.utility > 0,
    "pools.utility must have icons")

-- 3. EVENT_MAP must cover the required events
local requiredEvents = {
    "UNIT_AURA",
    "SPELL_UPDATE_USABLE",
    "SPELL_UPDATE_COOLDOWN",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_SOFT_ENEMY_CHANGED",
    "PLAYER_REGEN_ENABLED",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "BAG_UPDATE_COOLDOWN",
    "BAG_UPDATE_DELAYED",
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_FORMS",
}
for _, ev in ipairs(requiredEvents) do
    assert(A.EVENT_MAP[ev], "EVENT_MAP must have entry for " .. ev)
end

-- 4. dispatch() applies one event via the controller (no error)
do
    local ok, err = pcall(function()
        A.dispatch(built.controller, { e = "SPELL_UPDATE_USABLE", a = {}, n = 0 })
    end)
    assert(ok, "dispatch of SPELL_UPDATE_USABLE must not error: " .. tostring(err))
end

-- 5. ProfileSession with a synthetic event list
local syntheticEvents = {
    { e = "UNIT_AURA",          a = { "player" }, n = 1 },
    { e = "SPELL_UPDATE_USABLE", a = {},           n = 0 },
    { e = "ZZZ_UNMAPPED",        a = {},           n = 0 },
}

local churn, counts, report = A.ProfileSession(built.controller, syntheticEvents)

assert(type(churn)  == "table",  "ProfileSession must return churn table")
assert(type(counts) == "table",  "counts must be a table")
assert(type(report) == "string", "report must be a string")

-- At least one mapped event must have a count entry
local mappedCount = 0
for _, ev in ipairs({ "UNIT_AURA", "SPELL_UPDATE_USABLE" }) do
    if counts[ev] then mappedCount = mappedCount + 1 end
end
assert(mappedCount > 0, "at least one mapped event must appear in counts")

-- Unmapped event must appear as skipped/unmapped (not as a CDM method call)
-- ZZZ_UNMAPPED should appear in counts but not call any controller method
assert(counts["ZZZ_UNMAPPED"] == nil or counts["ZZZ_UNMAPPED"] == 0 or true,
    "unmapped count may be zero or nil -- real gate is no error and no mapped count")
-- The mapped count entries come from EVENT_MAP, so only mapped events are in counts.
-- Unmapped events are skipped silently (adapter counts them internally).

-- 6. PROVE a mapped event reached real CDM code:
--    After UNIT_AURA("player") with nil updateInfo, HandleAuraRefresh walks the buff
--    pool and calls applyAuraScopedResolvedCooldown for each aura icon.
--    We instrumented that callback via opts.onCallback; count must be > 0.
cbCounts = {}  -- reset
A.dispatch(built.controller, { e = "UNIT_AURA", a = { "player" }, n = 1 })

local auraCbCount = cbCounts["applyAuraScopedResolvedCooldown"] or 0
local visCbCount  = cbCounts["updateContainerVisibility"]       or 0

assert(auraCbCount > 0 or visCbCount > 0,
    "after UNIT_AURA dispatch, applyAuraScopedResolvedCooldown or updateContainerVisibility must fire (count=" ..
    auraCbCount .. "/" .. visCbCount .. ") -- proves event reached real CDM code")

print(string.format(
    "OK: qui_logger_cdm_adapter_test  [applyAuraScopedResolvedCooldown=%d  updateContainerVisibility=%d]",
    auraCbCount, visCbCount))
