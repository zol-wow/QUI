-- tests/unit/buffborders_blizzard_banish_taint_test.lua
-- Run: lua tests/unit/buffborders_blizzard_banish_taint_test.lua

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
    "currentParent.RemoveManagedFrame",
    "Managed-container removal must use the Blizzard parent mixin")

assertContains(
    source,
    "frame.ignoreFramePositionManager = true",
    "Banished Blizzard aura frames must not be re-added to the frame position manager")

assertContains(
    source,
    "ScheduleBuffUpdate()",
    "Buff aura header events must coalesce styling through the shared update frame")

assertContains(
    source,
    "ScheduleDebuffUpdate()",
    "Debuff aura header events must coalesce styling through the shared update frame")

assertContains(
    source,
    "if ns.AuraEvents then return end",
    "Header UNIT_AURA hooks must be fallback-only when centralized aura deltas are available")

assertContains(
    source,
    "if RefreshPureAuraUpdate(updateInfo) then return end",
    "Pure aura updates must use the auraInstanceID fast path instead of scheduling full scans")

assertContains(
    source,
    "local buffAuraChildrenByID = {}",
    "BuffBorders must keep a visible auraInstanceID-to-child map for direct delta refresh")

assertContains(
    source,
    "SetAuraChildMapEntry(child, auraChildMap, auraInstanceID)",
    "BuffBorders must update aura child maps incrementally instead of wiping them each structural refresh")

assertAbsent(
    source,
    "wipe(auraChildMap)",
    "BuffBorders aura child maps must not be wiped and refilled on every structural refresh")

assertContains(
    source,
    "BB_fastAuraUpdates",
    "Memaudit must expose the BuffBorders fast aura update counter")

assertAbsent(
    source,
    "StyleHeaderChildren(buffContainer, s, true)",
    "Buff aura header events must not run immediate GetUnitAuras scans")

assertAbsent(
    source,
    "StyleHeaderChildren(debuffContainer, s, false)\n        LayoutPrivateAuraSlots()",
    "Debuff aura header events must not run immediate GetUnitAuras scans")

print("OK: buffborders_blizzard_banish_taint_test")
