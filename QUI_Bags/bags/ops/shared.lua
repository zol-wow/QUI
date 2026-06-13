---------------------------------------------------------------------------
-- Bags ops: shared constants + the cross-op busy gate.
--
-- Loads before the individual ops files (sort_executor / transfers / junk)
-- so each can alias these without re-defining them. Behavior is identical
-- to the per-file copies these replaced.
--
--  PREFIX   informational house-print prefix (cyan "QUI:"), shared so the
--           color/format can never drift between ops messages.
--  OpsBusy() shared refusal gate for cursor/slot ops (sort, deposit, sell,
--           fill): they must never overlap (wrong-item hazards). Reads the
--           sibling ops modules off ns.Bags at CALL time, so load order
--           among the ops files does not matter.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local OpsShared = {}
Bags.OpsShared = OpsShared

OpsShared.PREFIX = "|cFF30D1FFQUI:|r"

function OpsShared.OpsBusy()
    return (Bags.SortExecutor and Bags.SortExecutor.IsRunning and Bags.SortExecutor.IsRunning())
        or (Bags.Transfers and Bags.Transfers.IsRunning and Bags.Transfers.IsRunning())
        or (Bags.Junk and Bags.Junk.IsSelling and Bags.Junk.IsSelling())
end
