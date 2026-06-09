-- tests/unit/group_loot_container_position_manager_optout_test.lua
-- Run: lua tests/unit/group_loot_container_position_manager_optout_test.lua
--
-- Regression guard: GroupLootContainer inherits UIParentBottomManagedFrameTemplate,
-- so Blizzard's UIParent position manager (UIParentManagedFrameContainerMixin:
-- AddManagedFrame) reparents and snaps it to screen-bottom-center every time it
-- shows from its default position. Because GroupLootContainer is the HEAD of the
-- alert anchor chain (AddExternallyAnchoredSubSystem, priority 30), a roll-won
-- toast chained off it then intermittently appears at the Blizzard default
-- location instead of QUI's Alert Anchor mover.
--
-- The opt-out the position manager actually honors is `ignoreFramePositionManager`
-- (the flag AddManagedFrame early-returns on). `ignoreInLayout` is a different,
-- unrelated LayoutFrame child-region flag and must NOT be relied on alone here.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_Skinning/skinning/notifications/alerts.lua")

assert(source:find("GroupLootContainer.ignoreFramePositionManager = true", 1, true),
    "GroupLootContainer must opt out of Blizzard's UIParent frame-position manager "
    .. "via ignoreFramePositionManager, or roll-won toasts snap to the default location")

-- It must deregister from the managed container before/while flagging it, so a
-- stale showingFrames reference can't drive a later Layout pass.
assert(source:find("RemoveManagedFrame", 1, true),
    "GroupLootContainer must be deregistered from its managed container (RemoveManagedFrame)")

print("OK: group_loot_container_position_manager_optout_test")
