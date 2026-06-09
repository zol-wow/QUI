-- tests/unit/cdm_buff_container_wake_defer_test.lua
-- Run: lua tests/unit/cdm_buff_container_wake_defer_test.lua
--
-- Verifies: RequestBuffIconLayoutRefresh never wakes (Show()s) the buff icon
-- container SYNCHRONOUSLY. WakeBuffIconContainer calls container:Show(), and
-- when the refresh is requested inside an in-combat cooldown/aura dispatch (a
-- secure-execution context) that Show is a blocked protected action
-- (ADDON_ACTION_BLOCKED on QUI_CDMBuffIconContainer:Show). The wake must be
-- deferred one frame so it runs outside that dispatch; the container is a plain
-- UIParent child, so a deferred Show is safe even mid-combat.

local ns = {}
assert(loadfile("QUI_CDM/cdm/cdm_icon_visibility_policy.lua"))("QUI", ns)
local Policy = assert(ns.CDMIconVisibilityPolicy, "CDMIconVisibilityPolicy exported")

local shows = 0
local container = { Show = function() shows = shows + 1 end }

local scheduled = {}
local layoutReady = 0

local controller = Policy.Create({
    getContainer = function(key)
        assert(key == "buff", "buff container requested, got " .. tostring(key))
        return container
    end,
    isHiddenByAnchor = function() return false end,
    scheduleAfter = function(delay, fn)
        scheduled[#scheduled + 1] = { delay = delay, fn = fn }
    end,
    onBuffLayoutReady = function() layoutReady = layoutReady + 1 end,
})

-- A refresh request must NOT Show() the container synchronously.
controller:RequestBuffIconLayoutRefresh()
assert(shows == 0, "container:Show must be deferred, not synchronous (got " .. shows .. ")")
assert(#scheduled == 1, "exactly one deferred wake scheduled, got " .. #scheduled)
assert(scheduled[1].delay == 0, "wake deferred one frame (delay 0), got " .. tostring(scheduled[1].delay))

-- Coalescing: a second request while one is pending schedules nothing new and
-- still does not Show synchronously.
controller:RequestBuffIconLayoutRefresh()
assert(shows == 0, "still no synchronous Show on a coalesced request, got " .. shows)
assert(#scheduled == 1, "coalesced request schedules no extra wake, got " .. #scheduled)

-- Running the deferred callback wakes the container and fires layout once.
scheduled[1].fn()
assert(shows == 1, "deferred wake Shows the container exactly once, got " .. shows)
assert(layoutReady == 1, "deferred wake runs the layout-ready callback once, got " .. layoutReady)

-- After draining, a fresh request schedules a new deferred wake (still no sync Show).
controller:RequestBuffIconLayoutRefresh()
assert(#scheduled == 2, "post-drain request schedules a new wake, got " .. #scheduled)
assert(shows == 1, "fresh request still does not Show synchronously, got " .. shows)

-- Anchor-hidden buff containers never wake, even when the deferred callback runs.
local hiddenShows = 0
local hiddenController = Policy.Create({
    getContainer = function() return { Show = function() hiddenShows = hiddenShows + 1 end } end,
    isHiddenByAnchor = function(key) return key == "buffIcon" end,
    scheduleAfter = function(_, fn) fn() end, -- run inline
})
hiddenController:RequestBuffIconLayoutRefresh()
assert(hiddenShows == 0, "anchor-hidden buff container never wakes, got " .. hiddenShows)

print("cdm_buff_container_wake_defer_test: PASS")
