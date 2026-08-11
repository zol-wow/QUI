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
