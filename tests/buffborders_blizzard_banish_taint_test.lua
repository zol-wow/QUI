-- tests/buffborders_blizzard_banish_taint_test.lua
-- Run: lua tests/buffborders_blizzard_banish_taint_test.lua

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

local source = readFile("modules/actionbars/buffborders.lua")

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

print("OK: buffborders_blizzard_banish_taint_test")
