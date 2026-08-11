-- tests/unit/buffborders_blizzard_banish_taint_test.lua
-- Run: lua tests/unit/buffborders_blizzard_banish_taint_test.lua
--
-- Guards behaviors that survive the E4 unification onto the SHARED secure
-- CustomAuraContainer model:
--   1. Blizzard buff/debuff frame banish state must live OFF the Blizzard frame
--      keys (taint hygiene), and banished frames must be removed from managed
--      containers + the frame position manager. (Unchanged across models.)
--   2. The forbidden AuraContainer is created/configured OUT OF COMBAT only and
--      combat-deferred to PLAYER_REGEN_ENABLED (it is a forbidden object).
--   3. QUI does NOT poll auras on UNIT_AURA for the live display anymore: the
--      secure container self-drives UNIT_AURA C-side (AuraContainerPrivateMixin),
--      so the bespoke per-frame UNIT_AURA registration + ScheduleBuffUpdate/
--      ScheduleDebuffUpdate coalescing of the old insecure pool must be GONE.
--      (Its replacement -- the container's own C-side UNIT_AURA handling -- is
--      strictly better and not a QUI-side mechanism to assert here.)

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local source = readFile("QUI_ActionBars/actionbars/buffborders.lua")

-- (1) Banish hygiene -- unchanged across models.
assertContains(
    source,
    "local blizzardBanishState = Helpers.CreateStateTable()",
    "Buff/debuff banish state must live outside Blizzard frame keys")

assertAbsent(
    source,
    "_quiBanished",
    "Buff/debuff banish state must not be stored on Blizzard frame keys")

assertContains(
    source,
    "local function RemoveFromManagedContainer(frame)",
    "Banished Blizzard aura frames must be removed from managed containers")

assertContains(
    source,
    'ns.SafeCallMethodIfPresent("best-effort-style", currentParent, "RemoveManagedFrame"',
    "Managed-container removal must use the Blizzard parent mixin (lookup inside pcall)")

assertContains(
    source,
    "frame.ignoreFramePositionManager = true",
    "Banished Blizzard aura frames must not be re-added to the frame position manager")

-- (2) The forbidden container is configured OOC only and combat-deferred.
assertContains(
    source,
    "PLAYER_REGEN_ENABLED",
    "Forbidden-container work must be deferred to PLAYER_REGEN_ENABLED")
assertContains(
    source,
    "InCombatLockdown()",
    "Container (re)config must be gated behind InCombatLockdown and deferred")

-- (3) No bespoke insecure UNIT_AURA poll/coalesce for the live display -- the
-- secure container self-drives UNIT_AURA C-side now.
assertAbsent(
    source,
    "ScheduleBuffUpdate",
    "Live aura restyling must NOT coalesce through a bespoke ScheduleBuffUpdate (container self-drives UNIT_AURA)")
assertAbsent(
    source,
    "ScheduleDebuffUpdate",
    "Live aura restyling must NOT coalesce through a bespoke ScheduleDebuffUpdate (container self-drives UNIT_AURA)")
assertAbsent(
    source,
    'RegisterUnitEvent("UNIT_AURA"',
    "buffborders.lua must NOT register UNIT_AURA itself for the live display (the secure container owns it)")

print("OK: buffborders_blizzard_banish_taint_test")
