---------------------------------------------------------------------------
-- Storage compatibility aliases. The bags data layer lives in core/storage
-- (ns.Storage); bags code predates the move and reads ns.Bags.*. Pure
-- aliasing, no logic. Must load immediately after bootstrap.lua so every
-- later bags file sees the aliases at load time.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Storage = ns.Storage
if not Storage then
    error(("%s requires core storage (ns.Storage); QUI core is too old"):format(ADDON_NAME), 0)
end

Bags.Bus = Storage.Bus
Bags.Store = Storage.Store
Bags.Summaries = Storage.Summaries
Bags.ItemInfo = Storage.ItemInfo
Bags.ScanCommon = Storage.ScanCommon
Bags.ScanBags = Storage.ScanBags
Bags.ScanBank = Storage.ScanBank
Bags.ScanGuild = Storage.ScanGuild
Bags.ScanMail = Storage.ScanMail
Bags.ScanEquipped = Storage.ScanEquipped
Bags.ScanCurrencies = Storage.ScanCurrencies
Bags.ScanAuctions = Storage.ScanAuctions
-- The coalesced drain scheduler now lives in the core collection driver
-- (core/storage/collector.lua). Bags-internal callers (ops, NewItems) keep
-- using Bags.RequestDrain; alias it through to the collector's owner.
Bags.RequestDrain = Storage.RequestDrain
